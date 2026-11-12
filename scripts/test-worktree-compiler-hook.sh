#!/usr/bin/env bash
# post-checkout / link-host-compiler: a new worktree gets the compiler the
# build store holds for exactly its sources, as a copy, or no compiler. It
# never gets one built from different sources, and never a link to another
# checkout's.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$ROOT/.githooks/post-checkout"
LINKER="$ROOT/.githooks/link-host-compiler.sh"
STORE_SH="$ROOT/bin/commands/store.sh"
[ -f "$HOOK" ] && [ -f "$LINKER" ] && [ -f "$STORE_SH" ]

bash -n "$HOOK"
bash -n "$LINKER"
bash -n "$STORE_SH"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-compiler-hook.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT INT TERM

# Nothing here may reach the user's real store.
export TUNGSTEN_BUILD_STORE="$TMP/store"
unset TUNGSTEN_CACHE_DIR TUNGSTEN_HOME

git_init() {
  git init -q "$1"
  git -C "$1" config user.email "hook@test"
  git -C "$1" config user.name "hook test"
}

fail() {
  echo "$1" >&2
  exit 1
}

# A miniature checkout: the files the compiler fingerprint reads, the hook,
# and the store script.
MAIN="$TMP/main"
git_init "$MAIN"
mkdir -p "$MAIN/bin/commands" "$MAIN/.githooks" "$MAIN/compiler/lib" "$MAIN/core" "$MAIN/runtime"
printf 'use tungsten_driver\n' >"$MAIN/compiler/tungsten.w"
printf '# driver\n' >"$MAIN/compiler/tungsten_driver.w"
printf '# lib\n' >"$MAIN/compiler/lib/lexer.w"
printf '# core manifest\n' >"$MAIN/core/tungsten.w"
printf '/* runtime */\n' >"$MAIN/runtime/runtime.c"
cp "$HOOK" "$MAIN/.githooks/post-checkout"
cp "$LINKER" "$MAIN/.githooks/link-host-compiler.sh"
cp "$STORE_SH" "$MAIN/bin/commands/store.sh"
chmod +x "$MAIN/.githooks/post-checkout" "$MAIN/.githooks/link-host-compiler.sh"
mkdir -p "$MAIN/.git/hooks"
cp "$HOOK" "$MAIN/.git/hooks/post-checkout"
chmod +x "$MAIN/.git/hooks/post-checkout"
git -C "$MAIN" add .githooks bin compiler core runtime
git -C "$MAIN" commit -q -m "sources and hooks"

# The fingerprint is a function of content, not of location.
fp="$(bash "$STORE_SH" compiler-fingerprint "$MAIN")"
[ "${#fp}" -eq 64 ] || fail "compiler fingerprint is not a sha256: $fp"
cp -R "$MAIN" "$TMP/copy"
[ "$(bash "$STORE_SH" compiler-fingerprint "$TMP/copy")" = "$fp" ] ||
  fail "identical sources in another directory fingerprint differently"

# What `tungsten build` leaves in the store for these sources: the compiler
# under its id, its images, and the by-source record naming them.
id="$(printf 'compiler-for-main' | shasum -a 256 | awk '{print $1}')"
repl="$(printf 'repl-for-main' | shasum -a 256 | awk '{print $1}')"
mkdir -p "$TMP/store/compilers/by-source"
printf '#!/bin/sh\necho store-compiler\n' >"$TMP/store/compilers/$id"
chmod +x "$TMP/store/compilers/$id"
printf 'sidemap\n' >"$TMP/store/compilers/$id.sidemap"
printf '#!/bin/sh\necho repl-image\n' >"$TMP/store/compilers/image-repl-$repl"
chmod +x "$TMP/store/compilers/image-repl-$repl"
printf 'repl sidemap\n' >"$TMP/store/compilers/image-repl-$repl.sidemap"
printf 'tungsten-compiler-record-v1\ncompiler=%s\nrepl=%s\nrelease=0\ncpu=native\ndebug=1\npgo=0\n' \
  "$id" "$repl" >"$TMP/store/compilers/by-source/$fp"

# 1. A new worktree with the same sources gets that compiler: a real file,
#    not a link, with its sidemap, image and build record.
WT="$TMP/wt"
git -C "$MAIN" worktree add -q "$WT" HEAD
[ -x "$WT/bin/tungsten-compiler" ] || fail "expected a compiler at $WT/bin/tungsten-compiler"
[ ! -L "$WT/bin/tungsten-compiler" ] || fail "the worktree compiler must be a copy, not a symlink"
[ "$("$WT/bin/tungsten-compiler")" = "store-compiler" ]
[ "$(cat "$WT/bin/tungsten-compiler.sidemap")" = "sidemap" ]
[ "$("$WT/build/compiler-images/tungsten-repl")" = "repl-image" ]
[ "$(cat "$WT/build/compiler-images/tungsten-repl.sidemap")" = "repl sidemap" ]
grep -qx "source=$fp" "$WT/build/compiler-build.profile"
grep -qx "verified=1" "$WT/build/compiler-build.profile"

# 2. A worktree whose compiler sources differ gets nothing: not the store's
#    compiler for other sources, and not another worktree's.
WT2="$TMP/wt-different"
git -C "$MAIN" worktree add -q "$WT2" HEAD
rm -f "$WT2/bin/tungsten-compiler" "$WT2/bin/tungsten-compiler.sidemap"
printf '# one more line\n' >>"$WT2/compiler/tungsten_driver.w"
[ "$(bash "$STORE_SH" compiler-fingerprint "$WT2")" != "$fp" ] ||
  fail "a changed compiler source did not change the fingerprint"
bash "$LINKER" "$WT2"
[ ! -e "$WT2/bin/tungsten-compiler" ] || fail "a worktree with different sources was given a compiler"

# 3. So does a change to the runtime or to core.
for file in runtime/runtime.c core/tungsten.w; do
  WT3="$TMP/wt-$(basename "$file")"
  git -C "$MAIN" worktree add -q "$WT3" HEAD
  rm -f "$WT3/bin/tungsten-compiler"
  printf '\n' >>"$WT3/$file"
  bash "$LINKER" "$WT3"
  [ ! -e "$WT3/bin/tungsten-compiler" ] || fail "a change to $file still matched the store compiler"
done

# 4. A worktree that already has a real compiler keeps it.
WT4="$TMP/wt-own"
git -C "$MAIN" worktree add -q "$WT4" HEAD
rm -f "$WT4/bin/tungsten-compiler"
mkdir -p "$WT4/bin"
printf '#!/bin/sh\necho own-compiler\n' >"$WT4/bin/tungsten-compiler"
chmod +x "$WT4/bin/tungsten-compiler"
bash "$LINKER" "$WT4"
[ "$("$WT4/bin/tungsten-compiler")" = "own-compiler" ]
[ ! -L "$WT4/bin/tungsten-compiler" ] || fail "must not replace an existing compiler"

# 5. A symlink left by the old hook (to another checkout's compiler) is
#    replaced by a copy when the store has this checkout's compiler ...
WT5="$TMP/wt-legacy"
git -C "$MAIN" worktree add -q "$WT5" HEAD
rm -f "$WT5/bin/tungsten-compiler"
ln -s "$WT4/bin/tungsten-compiler" "$WT5/bin/tungsten-compiler"
bash "$LINKER" "$WT5"
[ ! -L "$WT5/bin/tungsten-compiler" ] || fail "a legacy symlink with a store match was not replaced"
[ "$("$WT5/bin/tungsten-compiler")" = "store-compiler" ]
[ "$("$WT4/bin/tungsten-compiler")" = "own-compiler" ] || fail "replacing a symlink wrote through it"

# ... a broken one too ...
WT6="$TMP/wt-broken"
git -C "$MAIN" worktree add -q "$WT6" HEAD
rm -f "$WT6/bin/tungsten-compiler"
ln -s "$TMP/missing-compiler" "$WT6/bin/tungsten-compiler"
bash "$LINKER" "$WT6"
[ ! -L "$WT6/bin/tungsten-compiler" ] && [ "$("$WT6/bin/tungsten-compiler")" = "store-compiler" ] ||
  fail "a broken symlink with a store match was not replaced"

# ... and left alone when it has not.
WT7="$TMP/wt-legacy-different"
git -C "$MAIN" worktree add -q "$WT7" HEAD
rm -f "$WT7/bin/tungsten-compiler"
printf '# differs\n' >>"$WT7/compiler/lib/lexer.w"
ln -s "$WT4/bin/tungsten-compiler" "$WT7/bin/tungsten-compiler"
bash "$LINKER" "$WT7"
[ -L "$WT7/bin/tungsten-compiler" ] || fail "a legacy symlink without a store match was removed"

# 6. An empty store: the compiler stays missing (never a bootstrap).
ALONE="$TMP/alone"
cp -R "$MAIN" "$ALONE"
rm -rf "$ALONE/bin/tungsten-compiler"
TUNGSTEN_BUILD_STORE="$TMP/empty-store" bash "$LINKER" "$ALONE"
[ ! -e "$ALONE/bin/tungsten-compiler" ] || fail "must not invent a compiler when the store has none"

# 7. A record that names a compiler the store no longer holds installs nothing.
rm -f "$TMP/store/compilers/$id"
WT8="$TMP/wt-swept"
git -C "$MAIN" worktree add -q "$WT8" HEAD
[ ! -e "$WT8/bin/tungsten-compiler" ] || fail "installed a compiler the store does not hold"

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
