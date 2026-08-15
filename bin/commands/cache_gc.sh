#!/usr/bin/env bash
# Remove stale, reproducible artifacts from build/cache. The cache is an
# optimization only: deleting any entry must cause a rebuild, never data loss.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CACHE="${1:-$ROOT/build/cache}"
MAX_AGE_DAYS="${TUNGSTEN_CACHE_MAX_AGE_DAYS:-7}"
STAMP="$CACHE/.gc-last-run"
LOCK="$CACHE/.gc-lock"

case "$MAX_AGE_DAYS" in
  ''|*[!0-9]*)
    printf 'tungsten cache gc: invalid TUNGSTEN_CACHE_MAX_AGE_DAYS=%s\n' "$MAX_AGE_DAYS" >&2
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
if ! mkdir "$LOCK" 2>/dev/null; then
  exit 0
fi
trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT INT TERM

removed=0
list="${TMPDIR:-/tmp}/tungsten-cache-gc-$$"
trap 'rm -f "$list"; rmdir "$LOCK" 2>/dev/null || true' EXIT INT TERM

# Delete files first, then empty directories. We intentionally do not remove a
# directory merely because its own mtime is old: it may contain a fresh cache
# entry. Related cache triplets can become partial, which is safe—the normal
# identity probe treats a missing member as a miss and regenerates the set.
find "$CACHE" -type f ! -name '.gc-last-run' -mtime "+$MAX_AGE_DAYS" -print0 > "$list"
while IFS= read -r -d '' path; do
  rm -f -- "$path"
  removed=$((removed + 1))
done < "$list"

find "$CACHE" -type l -mtime "+$MAX_AGE_DAYS" -print0 > "$list"
while IFS= read -r -d '' path; do
  rm -f -- "$path"
  removed=$((removed + 1))
done < "$list"

# *.lock directories are live mkdir-mutexes (compiled `run` serializes cache
# builds through them); a crashed holder's lock is stolen by the next run,
# never swept here.
find "$CACHE" -depth -type d ! -path "$CACHE" ! -path "$LOCK" ! -name '*.lock' -empty -delete
rm -f "$list"
touch "$STAMP"

if [ "$removed" -gt 0 ] || [ "${TUNGSTEN_CACHE_GC_VERBOSE:-0}" = 1 ]; then
  printf 'tungsten cache gc: removed %s artifact(s) older than %s day(s)\n' \
    "$removed" "$MAX_AGE_DAYS"
fi
