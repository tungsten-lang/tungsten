#!/usr/bin/env bash
# post-checkout / link-host-compiler: new worktrees inherit the primary
# checkout's gitignored compiler via symlink.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$ROOT/.githooks/post-checkout"
LINKER="$ROOT/.githooks/link-host-compiler.sh"
[ -f "$HOOK" ] && [ -f "$LINKER" ]

bash -n "$HOOK"
bash -n "$LINKER"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-compiler-hook.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT INT TERM

git_init() {
  git init -q "$1"
  git -C "$1" config user.email "hook@test"
  git -C "$1" config user.name "hook test"
}

MAIN="$TMP/main"
git_init "$MAIN"
mkdir -p "$MAIN/bin" "$MAIN/.githooks"
printf '#!/bin/sh\necho host-compiler\n' >"$MAIN/bin/tungsten-compiler"
chmod +x "$MAIN/bin/tungsten-compiler"
cp "$HOOK" "$MAIN/.githooks/post-checkout"
cp "$LINKER" "$MAIN/.githooks/link-host-compiler.sh"
chmod +x "$MAIN/.githooks/post-checkout" "$MAIN/.githooks/link-host-compiler.sh"
mkdir -p "$MAIN/.git/hooks"
cp "$HOOK" "$MAIN/.git/hooks/post-checkout"
chmod +x "$MAIN/.git/hooks/post-checkout"

git -C "$MAIN" add .githooks
git -C "$MAIN" commit -q -m "hooks"
# The compiler is gitignored in the real repo; here it is untracked on
# purpose so worktree add does not copy it.

WT="$TMP/wt"
git -C "$MAIN" worktree add -q "$WT" HEAD

if [ ! -L "$WT/bin/tungsten-compiler" ]; then
  echo "expected symlink at $WT/bin/tungsten-compiler" >&2
  ls -la "$WT/bin" >&2 || true
  exit 1
fi
resolved="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$WT/bin/tungsten-compiler")"
expect="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$MAIN/bin/tungsten-compiler")"
if [ "$resolved" != "$expect" ]; then
  echo "symlink target mismatch: $resolved != $expect" >&2
  exit 1
fi
out="$("$WT/bin/tungsten-compiler")"
[ "$out" = "host-compiler" ]

# A worktree that already has a real compiler must not be replaced.
WT2="$TMP/wt-own"
git -C "$MAIN" worktree add -q "$WT2" HEAD
rm -f "$WT2/bin/tungsten-compiler"
mkdir -p "$WT2/bin"
printf '#!/bin/sh\necho own-compiler\n' >"$WT2/bin/tungsten-compiler"
chmod +x "$WT2/bin/tungsten-compiler"
bash "$LINKER" "$WT2"
out="$("$WT2/bin/tungsten-compiler")"
[ "$out" = "own-compiler" ]
if [ -L "$WT2/bin/tungsten-compiler" ]; then
  echo "must not replace an existing compiler with a symlink" >&2
  exit 1
fi

# A broken dest symlink is replaced, not left pointing at nothing.
WT3="$TMP/wt-broken"
git -C "$MAIN" worktree add -q "$WT3" HEAD
rm -f "$WT3/bin/tungsten-compiler"
mkdir -p "$WT3/bin"
ln -s "$TMP/missing-compiler" "$WT3/bin/tungsten-compiler"
bash "$LINKER" "$WT3"
if [ ! -L "$WT3/bin/tungsten-compiler" ]; then
  echo "expected broken dest to be replaced with a symlink" >&2
  exit 1
fi
resolved="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$WT3/bin/tungsten-compiler")"
if [ "$resolved" != "$expect" ]; then
  echo "broken dest retarget mismatch: $resolved != $expect" >&2
  exit 1
fi
out="$("$WT3/bin/tungsten-compiler")"
[ "$out" = "host-compiler" ]

# No other compiler in any worktree: dest stays missing (never a bootstrap).
ALONE="$TMP/alone"
git_init "$ALONE"
mkdir -p "$ALONE/.githooks"
cp "$HOOK" "$ALONE/.githooks/post-checkout"
cp "$LINKER" "$ALONE/.githooks/link-host-compiler.sh"
chmod +x "$ALONE/.githooks/post-checkout" "$ALONE/.githooks/link-host-compiler.sh"
bash "$LINKER" "$ALONE"
if [ -e "$ALONE/bin/tungsten-compiler" ]; then
  echo "must not invent a compiler when no host exists" >&2
  ls -la "$ALONE/bin" >&2 || true
  exit 1
fi

# doctor.sh installer: copy our hook; never clobber a foreign post-checkout.
eval "$(sed -n '/^install_worktree_compiler_hook()/,/^}/p' "$ROOT/bin/commands/doctor.sh")"
install_into() {
  ROOT="$1"
  install_worktree_compiler_hook
}

DOC="$TMP/doctor-empty"
git_init "$DOC"
mkdir -p "$DOC/.githooks"
cp "$HOOK" "$DOC/.githooks/post-checkout"
chmod +x "$DOC/.githooks/post-checkout"
install_into "$DOC"
grep -q "tungsten: symlink host compiler into worktrees" "$DOC/.git/hooks/post-checkout"

FOREIGN="$TMP/doctor-foreign"
git_init "$FOREIGN"
mkdir -p "$FOREIGN/.githooks" "$FOREIGN/.git/hooks"
cp "$HOOK" "$FOREIGN/.githooks/post-checkout"
printf '#!/bin/sh\necho foreign-hook\n' >"$FOREIGN/.git/hooks/post-checkout"
chmod +x "$FOREIGN/.git/hooks/post-checkout"
foreign_status=0
install_into "$FOREIGN" || foreign_status=$?
if [ "$foreign_status" -ne 2 ]; then
  echo "foreign post-checkout must be skipped (got $foreign_status)" >&2
  exit 1
fi
grep -q 'foreign-hook' "$FOREIGN/.git/hooks/post-checkout"
if grep -q "tungsten: symlink host compiler into worktrees" "$FOREIGN/.git/hooks/post-checkout"; then
  echo "foreign post-checkout was overwritten" >&2
  exit 1
fi

echo "worktree compiler hook: ok"
