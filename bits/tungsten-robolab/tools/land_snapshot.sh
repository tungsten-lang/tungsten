#!/bin/bash
# Land the snapshot branch (robolab-campaign-2026-09) on main without touching the shared index, the working
# tree's other files, or anyone else's staged work.
#
#   tools/land_snapshot.sh --dry-run          # show what would happen
#   tools/land_snapshot.sh                    # do it (only when Erik has said to land)
#
# 1. New main commit: the branch tip itself when it is a descendant of main (fast-forward), otherwise a merge
#    commit built with `git merge-tree --write-tree` (it refuses on conflicts; robolab only adds files under
#    bits/tungsten-robolab, so a conflict means somebody else touched that directory).
# 2. `git update-ref refs/heads/main NEW OLD` is a compare-and-swap: it fails if another session committed to
#    main in between, and nothing is changed.
# 3. The shared index still describes the OLD main, so the landed files would show as staged deletions (and
#    the next `git commit` by another session would revert them). `git reset -q -- bits/tungsten-robolab`
#    fixes exactly those paths and leaves every other staged change alone. Never run a bare `git reset`.
# Never pushes.
set -euo pipefail

BR=robolab-campaign-2026-09
DRY=0
MSG="Merge branch '$BR': robolab, a muscle-contraction control plane with a MuJoCo/MyoSuite playground and arena"
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
cd "$(cd "$here/../.." && pwd)"
rel=bits/tungsten-robolab

OLD=$(git rev-parse refs/heads/main)
TIP=$(git rev-parse "refs/heads/$BR")
if [ "$(git rev-parse --abbrev-ref HEAD)" != "main" ]; then
  echo "HEAD is not main here; refusing (the index heal below assumes main is checked out)" >&2; exit 1
fi
if git merge-base --is-ancestor "$TIP" "$OLD"; then
  echo "main already contains $BR ($TIP)"; exit 0
fi

if git merge-base --is-ancestor "$OLD" "$TIP"; then
  NEW=$TIP; HOW="fast-forward"
else
  TREE=$(git merge-tree --write-tree "$OLD" "$TIP") || { echo "merge conflicts; not landing" >&2; exit 1; }
  NEW=$(git commit-tree "$TREE" -p "$OLD" -p "$TIP" -m "$MSG

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>")
  HOW="merge commit"
fi
echo "main $OLD -> $NEW ($HOW), branch $BR at $TIP"
git diff --stat "$OLD" "$NEW" | tail -1
if [ "$DRY" = 1 ]; then echo "dry run: nothing written"; exit 0; fi

git update-ref -m "land $BR" refs/heads/main "$NEW" "$OLD"
git reset -q -- "$rel"
echo "landed. shared index healed for $rel."
echo "robolab paths still differing from main (uncommitted work since the snapshot):"
git status --short -- "$rel" | awk '{print $1}' | sort | uniq -c
