#!/usr/bin/env bash
# If this worktree has no bin/tungsten-compiler, symlink one from another
# worktree of the same repo (usually the primary checkout). Gitignored
# build artifacts are not copied by `git worktree add`.
#
# Usage: link-host-compiler.sh [worktree-root]
# Always exits 0: callers are checkout hooks and the CLI fallback.
set -u

root="${1:-}"
if [ -z "$root" ]; then
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
fi
cd "$root" 2>/dev/null || exit 0

dest="$root/bin/tungsten-compiler"

resolve_exec() {
  local p="$1" n=0 t
  while [ -L "$p" ] && [ "$n" -lt 20 ]; do
    t="$(readlink "$p")" || return 1
    case "$t" in
      /*) p="$t" ;;
      *) p="$(cd "$(dirname "$p")" && pwd)/$t" ;;
    esac
    n=$((n + 1))
  done
  [ -f "$p" ] && [ -x "$p" ] || return 1
  echo "$(cd "$(dirname "$p")" && pwd)/$(basename "$p")"
}

if resolve_exec "$dest" >/dev/null; then
  exit 0
fi

worktrees=()
while IFS= read -r line; do
  case "$line" in
    worktree\ *)
      worktrees[${#worktrees[@]}]="${line#worktree }"
      ;;
  esac
done <<EOF
$(git worktree list --porcelain 2>/dev/null)
EOF

src=""
i=0
while [ "$i" -lt "${#worktrees[@]}" ]; do
  wt="${worktrees[$i]}"
  i=$((i + 1))
  [ -n "$wt" ] || continue
  [ "$wt" != "$root" ] || continue
  cand="$wt/bin/tungsten-compiler"
  if resolved="$(resolve_exec "$cand")"; then
    src="$resolved"
    break
  fi
done

[ -n "$src" ] || exit 0
mkdir -p "$root/bin" || exit 0
# Replace a missing or broken dest; never clobber a working compiler.
rm -f "$dest" 2>/dev/null || exit 0
ln -s "$src" "$dest" 2>/dev/null || exit 0
exit 0
