#!/usr/bin/env bash
# Sweep the build store (or any cache directory given as $1). Everything in
# it is reproducible: removing an entry costs a rebuild, never data.
#
# The store is shared by every checkout and by builds that run at the same
# time, so the sweep only ever removes what nothing is using:
#   - by age: files not used for TUNGSTEN_CACHE_MAX_AGE_DAYS (default 7).
#     Readers renew an entry's mtime when they use it (at most daily), so
#     "old" means unused, not merely built long ago;
#   - by size: when the directory is over TUNGSTEN_CACHE_MAX_SIZE_MB (default
#     20000; 0 turns the limit off), the least recently used files go first,
#     but never one used within the last day.
# A file is unlinked, never truncated or rewritten: a process that already
# opened it keeps reading it, and one that finds it gone rebuilds it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$ROOT/bin/commands/store.sh"
CACHE="${1:-$(tungsten_store_dir "$ROOT")}"
MAX_AGE_DAYS="${TUNGSTEN_CACHE_MAX_AGE_DAYS:-7}"
MAX_SIZE_MB="${TUNGSTEN_CACHE_MAX_SIZE_MB:-20000}"
STAMP="$CACHE/.gc-last-run"
LOCK="$CACHE/.gc-lock"

case "$MAX_AGE_DAYS" in
  ''|*[!0-9]*)
    printf 'tungsten cache gc: invalid TUNGSTEN_CACHE_MAX_AGE_DAYS=%s\n' "$MAX_AGE_DAYS" >&2
    exit 2
    ;;
esac

case "$MAX_SIZE_MB" in
  ''|*[!0-9]*)
    printf 'tungsten cache gc: invalid TUNGSTEN_CACHE_MAX_SIZE_MB=%s\n' "$MAX_SIZE_MB" >&2
    exit 2
    ;;
esac

case "$CACHE" in
  ''|/)
    printf 'tungsten cache gc: refusing unsafe cache path %s\n' "$CACHE" >&2
    exit 2
    ;;
esac

mkdir -p "$CACHE"

# Automatic callers run on every build/bootstrap, but a daily sweep is enough.
# Tests and explicit maintenance can force a pass.
if [ "${TUNGSTEN_CACHE_GC_FORCE:-0}" != 1 ] && [ -f "$STAMP" ] &&
   find "$STAMP" -mtime -1 -print -quit | grep -q .; then
  exit 0
fi

# mkdir is the portable lock primitive available on fresh macOS/Linux clones.
# One sweep at a time; whoever loses simply leaves it to the winner.
if ! mkdir "$LOCK" 2>/dev/null; then
  exit 0
fi
removed=0
list="${TMPDIR:-/tmp}/tungsten-cache-gc-$$"
trap 'rm -f "$list" "$list.sorted"; rmdir "$LOCK" 2>/dev/null || true' EXIT INT TERM

# "mtime-seconds size-bytes path" per file; BSD and GNU stat differ.
if stat -f '%m %z %N' "$CACHE" >/dev/null 2>&1; then
  STAT_ROW=(stat -f '%m %z %N')
  mtime_of() { stat -f '%m' "$1"; }
else
  STAT_ROW=(stat -c '%Y %s %n')
  mtime_of() { stat -c '%Y' "$1"; }
fi

# The default root also contains application data (for example, memoized
# functions). Only the store's own directories participate in its sweep.
roots=("$CACHE")
if [[ "$CACHE" -ef "$(tungsten_store_dir "$ROOT")" ]]; then
  roots=()
  for part in $(tungsten_store_parts); do
    if [[ -d "$CACHE/$part" && ! -L "$CACHE/$part" ]]; then
      roots+=("$CACHE/$part")
    fi
  done
  if [[ "${#roots[@]}" -eq 0 ]]; then
    touch "$STAMP"
    exit 0
  fi
fi

# A directory holding a .ready marker is ONE entry (an LTO object bundle):
# its reader trusts the marker for the whole set of objects, so the bundle is
# removed whole, by the marker's age (a link renews every file in it), marker
# first, and never file by file. Every other entry is a set of files whose
# reader requires each member, so removing files one at a time is safe: an
# entry that lost a member (a binary without its manifest) is a miss.
remove_bundle() {
  rm -f -- "$1/.ready"
  rm -rf -- "$1"
}
find "${roots[@]}" -type f -name .ready -mtime "+$MAX_AGE_DAYS" -print0 > "$list"
while IFS= read -r -d '' marker; do
  remove_bundle "$(dirname "$marker")"
  removed=$((removed + 1))
done < "$list"

# Then files outside bundles, then empty directories. We intentionally do not
# remove a directory merely because its own mtime is old: it may contain a
# fresh cache entry.
find "${roots[@]}" -type d -exec test -e '{}/.ready' ';' -prune -o \
  -type f ! -name '.gc-last-run' -mtime "+$MAX_AGE_DAYS" -print0 > "$list"
while IFS= read -r -d '' path; do
  rm -f -- "$path"
  removed=$((removed + 1))
done < "$list"

find "${roots[@]}" -type l -mtime "+$MAX_AGE_DAYS" -print0 > "$list"
while IFS= read -r -d '' path; do
  rm -f -- "$path"
  removed=$((removed + 1))
done < "$list"

# Size limit: least recently used first, among files idle for over a day.
evicted=0
if [ "$MAX_SIZE_MB" -gt 0 ]; then
  total_kb="$(du -sk "${roots[@]}" 2>/dev/null | awk '{n += $1} END {print n}')"
  limit_kb=$((MAX_SIZE_MB * 1024))
  if [ -n "$total_kb" ] && [ "$total_kb" -gt "$limit_kb" ]; then
    # "mtime size kind path": kind f is a file, b a whole bundle (above).
    {
      find "${roots[@]}" -type d -exec test -e '{}/.ready' ';' -prune -o \
        -type f ! -name '.gc-last-run' -mtime +0 -exec "${STAT_ROW[@]}" {} + 2>/dev/null |
        sed 's/^\([0-9]*\) \([0-9]*\) /\1 \2 f /'
      find "${roots[@]}" -type f -name .ready -mtime +0 -print 2>/dev/null |
        while IFS= read -r marker; do
          bundle="$(dirname "$marker")"
          kb="$(du -sk "$bundle" 2>/dev/null | awk '{ s = $1 } END { print s + 0 }')"
          printf '%s %s b %s\n' "$(mtime_of "$marker")" "$((kb * 1024))" "$bundle"
        done
    } > "$list" || true
    LC_ALL=C sort -n "$list" > "$list.sorted"
    excess_kb=$((total_kb - limit_kb))
    while IFS= read -r row; do
      [ "$excess_kb" -gt 0 ] || break
      rest="${row#* }"
      size="${rest%% *}"
      rest="${rest#* }"
      kind="${rest%% *}"
      path="${rest#* }"
      case "$size" in
        ''|*[!0-9]*) continue ;;
      esac
      if [ "$kind" = b ]; then
        remove_bundle "$path"
      else
        rm -f -- "$path"
      fi
      evicted=$((evicted + 1))
      excess_kb=$((excess_kb - (size + 1023) / 1024))
    done < "$list.sorted"
  fi
fi

# Then directories that have been empty for over a day. Not younger ones: a
# builder creates its directory first and fills it next (the store's own
# sub-directories, a runtime build directory), and must not lose it in
# between. *.lock directories are live mkdir-mutexes (compiled `run`
# serializes cache builds through them); a crashed holder's lock is stolen
# by the next run, never swept here.
find "${roots[@]}" -depth -type d ! -path "$CACHE" ! -path "$LOCK" ! -name '*.lock' -empty -mtime +0 -delete 2>/dev/null || true
rm -f "$list" "$list.sorted"
touch "$STAMP"

if [ "$removed" -gt 0 ] || [ "$evicted" -gt 0 ] || [ "${TUNGSTEN_CACHE_GC_VERBOSE:-0}" = 1 ]; then
  printf 'tungsten cache gc: removed %s artifact(s) older than %s day(s)' \
    "$removed" "$MAX_AGE_DAYS"
  if [ "$evicted" -gt 0 ]; then
    printf ', evicted %s to stay under %s MB' "$evicted" "$MAX_SIZE_MB"
  fi
  printf ' (%s)\n' "$CACHE"
fi
