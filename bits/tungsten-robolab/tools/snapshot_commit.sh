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
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
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

LIST=$(mktemp /tmp/robolab_snapshot_files.XXXXXX)
IDX=$(mktemp -u /tmp/robolab_snapshot_index.XXXXXX)
trap 'rm -f "$LIST" "$IDX"' EXIT

git ls-files -co --exclude-standard -z -- "$rel" | python3 -c '
import os, sys
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
sys.stderr.write("snapshot: %d files, %.1f MB; skipped over 2 MB: %s\n" % (
    len(keep), sum(os.path.getsize(f) for f in keep) / 1e6, big or "none"))
sys.stdout.buffer.write("\0".join(keep).encode())
' > "$LIST"

export GIT_INDEX_FILE="$IDX"
git read-tree "$OLD"
git rm -r -q -f --cached --ignore-unmatch -- "$rel"
git add --pathspec-from-file="$LIST" --pathspec-file-nul
TREE=$(git write-tree)
unset GIT_INDEX_FILE

if [ "$TREE" = "$(git rev-parse "$OLD^{tree}")" ]; then
  echo "nothing new to snapshot (tree equals $BR)"
  exit 0
fi
git diff-tree --stat -r --no-color "$OLD" "$TREE" | tail -1
if [ "$DRY" = 1 ]; then
  echo "dry run: nothing written"
  exit 0
fi

[ -n "$MSG" ] || MSG="robolab: snapshot $(date '+%Y-%m-%d %H:%M')"
NEW=$(git commit-tree "$TREE" -p "$OLD" -m "$MSG")
git update-ref "refs/heads/$BR" "$NEW" "$OLD"
echo "$BR: $OLD -> $NEW"
git log --oneline -1 "$BR"
