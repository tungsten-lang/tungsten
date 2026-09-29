#!/bin/bash
# Snapshot bits/tungsten-robolab onto the branch robolab-campaign-2026-09.
#
# The repo root is shared with other sessions that commit to main, so this never
# touches the shared index, the working tree or HEAD. It builds the commit with
# plumbing (a temporary index, commit-tree, and a compare-and-swap update-ref on
# the snapshot branch only) and needs the branch to exist already.
#
#   tools/snapshot_commit.sh --dry-run                # what would be committed
#   tools/snapshot_commit.sh -m "robolab: <what changed>"
#   tools/snapshot_commit.sh --only tools requirements README.md -m "..."   # just these paths (a partial snapshot;
#       paths relative to bits/tungsten-robolab first, then to the repo root; directories are walked). Use it while agents are
#       mid-edit in lib/ and playground/, so unverified sources do not ride along.
#
# Included: every file under bits/tungsten-robolab that is tracked or untracked
# and not ignored (.gitignore already keeps out the venvs, out/, bin/robolab*,
# playground/cache and the copyrighted clips), minus the exclusions below.
# Excluded: files over 2 MB, compiled scratch binaries (extensionless files under
# scratchpad/), scratch media and pid files, debug junk, the arena lock file.
# Only commit when Erik has asked for a commit; never push from here.
set -euo pipefail

BR=robolab-campaign-2026-09
DRY=0
MSG=""
ONLY=()
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --only) shift; while [ $# -gt 0 ] && [ "${1#-}" = "$1" ]; do ONLY+=("$1"); shift; done; continue ;;
    -m) MSG="$2"; shift ;;
    --branch) BR="$2"; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

here=$(cd "$(dirname "$0")/.." && pwd)
repo=$(cd "$here/../.." && pwd)
cd "$repo"
rel=bits/tungsten-robolab

git rev-parse --verify -q "refs/heads/$BR" >/dev/null || { echo "branch $BR does not exist" >&2; exit 1; }
OLD=$(git rev-parse "refs/heads/$BR")
# Other sessions commit to main. When main has moved on from the branch tip (the branch tip is its ancestor), build the
# snapshot on main's tip so the branch stays a fast-forward of main and landing is a fast-forward too.
BASE=$OLD
MAIN=$(git rev-parse -q --verify refs/heads/main || true)
if [ -n "$MAIN" ] && [ "$MAIN" != "$OLD" ] && git merge-base --is-ancestor "$OLD" "$MAIN"; then
  BASE=$MAIN
  echo "building on main ($MAIN), which is ahead of $BR"
fi

LIST=$(mktemp /tmp/robolab_snapshot_files.XXXXXX)
FORCE=$(mktemp /tmp/robolab_snapshot_force.XXXXXX)
IDX=$(mktemp -u /tmp/robolab_snapshot_index.XXXXXX)
trap 'rm -f "$LIST" "$FORCE" "$IDX"' EXIT

MODE=all
if [ "${#ONLY[@]}" -gt 0 ]; then
  MODE=only
  : > "$FORCE"
  printf '%s\0' "${ONLY[@]}" | python3 -c '
import os, sys
rel = "bits/tungsten-robolab"
args = [a for a in sys.stdin.buffer.read().decode().split("\0") if a]
found = []
for a in args:
    # bit-relative first: a bare README.md or .gitignore must mean the file of this bit, not of the repo root
    p = os.path.join(rel, a) if os.path.exists(os.path.join(rel, a)) else a
    if os.path.isdir(p):
        for d, _, fs in os.walk(p):
            found += [os.path.join(d, f) for f in fs]
    elif os.path.isfile(p):
        found.append(p)
    else:
        sys.stderr.write("only: no such path %s\n" % a)
keep = []
for f in sorted(set(found)):
    b = os.path.basename(f)
    ext = b.rsplit(".", 1)[-1].lower() if "." in b else ""
    if f.endswith("playground/arena/.lock") or ".dSYM" in f or "__pycache__" in f or ext == "pyc":
        continue
    if "/scratchpad/" in f and (ext in ("gif", "mp4", "png", "pid", "sidemap", "o", "dylib") or "." not in b):
        continue
    if os.path.getsize(f) > 2_000_000:
        sys.stderr.write("only: skipped over 2 MB: %s\n" % f)
        continue
    keep.append(f)
sys.stderr.write("snapshot (only): %d files\n" % len(keep))
sys.stdout.buffer.write("\0".join(keep).encode())
' > "$LIST"
else
# Erik's global ~/.gitignore drops *.log, so the practice logs the docs cite are added with -f (FORCE list).
git ls-files -co --exclude-standard -z -- "$rel" | FORCE_OUT="$FORCE" python3 -c '
import glob, os, sys
files = [f for f in sys.stdin.buffer.read().decode().split("\0") if f and os.path.isfile(f)]
keep, big = [], []
for f in files:
    b = os.path.basename(f)
    ext = b.rsplit(".", 1)[-1].lower() if "." in b else ""
    scratch = "/scratchpad/" in f
    if f.endswith("playground/arena/.lock") or b in ("dbg.png", "MUJOCO_LOG.TXT") or ".dSYM" in f:
        continue
    if scratch and (ext in ("gif", "mp4", "png", "pid", "sidemap", "o", "dylib") or "." not in b):
        continue
    if os.path.getsize(f) > 2_000_000:
        big.append(f)
        continue
    keep.append(f)
force = []
for pat in ("bits/tungsten-robolab/playground/search_results/**/*.log", "bits/tungsten-robolab/params/search_logs/*.log"):
    for f in glob.glob(pat, recursive=True):
        if os.path.isfile(f) and os.path.getsize(f) <= 2_000_000 and f not in keep:
            force.append(f)
open(os.environ["FORCE_OUT"], "wb").write("\0".join(force).encode())
sys.stderr.write("snapshot: %d files (+%d forced logs), %.1f MB; skipped over 2 MB: %s\n" % (
    len(keep), len(force), sum(os.path.getsize(f) for f in keep) / 1e6, big or "none"))
sys.stdout.buffer.write("\0".join(keep).encode())
' > "$LIST"
fi

export GIT_INDEX_FILE="$IDX"
git read-tree "$BASE"
if [ "$MODE" = only ]; then
  [ -s "$LIST" ] && git add -f --pathspec-from-file="$LIST" --pathspec-file-nul
else
  git rm -r -q -f --cached --ignore-unmatch -- "$rel"
  # -f: the list holds every tracked file, and tracked files that a global ignore rule matches (the cited *.log files)
  # would otherwise be refused after the rm above; untracked ignored files are not in the list.
  git add -f --pathspec-from-file="$LIST" --pathspec-file-nul
  [ -s "$FORCE" ] && git add -f --pathspec-from-file="$FORCE" --pathspec-file-nul
fi
TREE=$(git write-tree)
unset GIT_INDEX_FILE

if [ "$TREE" = "$(git rev-parse "$BASE^{tree}")" ]; then
  if [ "$BASE" != "$OLD" ] && [ "$DRY" != 1 ]; then
    git update-ref "refs/heads/$BR" "$BASE" "$OLD"
    echo "$BR fast-forwarded to main"
  fi
  echo "nothing new to snapshot (tree equals ${BASE:0:9})"
  exit 0
fi
git diff-tree --stat -r --no-color "$BASE" "$TREE" | tail -1
if [ "$DRY" = 1 ]; then
  echo "dry run: nothing written"
  exit 0
fi

[ -n "$MSG" ] || MSG="robolab: snapshot $(date '+%Y-%m-%d %H:%M')"
NEW=$(git commit-tree "$TREE" -p "$BASE" -m "$MSG")
git update-ref "refs/heads/$BR" "$NEW" "$OLD"
echo "$BR: $OLD -> $NEW"
git log --oneline -1 "$BR"
