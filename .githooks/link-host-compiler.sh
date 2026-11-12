#!/usr/bin/env bash
# Give a checkout that has no compiler the one the build store holds for
# exactly its sources (bin/commands/store.sh install-compiler). Gitignored
# build products are not copied by `git worktree add`, so a new worktree
# starts without bin/tungsten-compiler.
#
# This used to symlink whatever compiler another worktree had, which was the
# wrong compiler as soon as the two worktrees' compiler sources differed (and
# changed under this worktree whenever the other one rebuilt). Now the
# worktree's own sources are fingerprinted and looked up in the store: a
# match installs a copy of that compiler and its images; no match installs
# nothing, and `bin/tungsten build` (or `bootstrap`) builds one and adds it
# to the store. The file keeps its old name because hooks already installed
# in a repository's common .git/hooks call it by that name.
#
# Usage: link-host-compiler.sh [worktree-root]
# Always exits 0: callers are checkout hooks and the CLI fallback.
set -u

root="${1:-}"
if [ -z "$root" ]; then
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
fi
cd "$root" 2>/dev/null || exit 0
root="$(pwd)"

store_sh="$root/bin/commands/store.sh"
[ -f "$store_sh" ] || exit 0
. "$store_sh"
tungsten_install_store_compiler "$root" || true
exit 0
