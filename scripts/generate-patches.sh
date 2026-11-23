#!/usr/bin/env bash
# Generate a portable -p1 patch for one release. Keep the previous patch on errors.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
version="${1:-$(readlink "$ROOT/src/patched/ruby/current" || true)}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "usage: $0 x.y.z" >&2; exit 2; }
pristine="$ROOT/src/pristine/ruby-$version"
patched="$ROOT/src/patched/ruby/$version"
[[ -d "$pristine" && -d "$patched" ]] || { echo "Missing pristine or patched Ruby $version" >&2; exit 1; }
patch_dir="$ROOT/src/patches/ruby/$version"
mkdir -p "$patch_dir"
work="$(mktemp -d "$patch_dir/.generate.XXXXXX")"
trap 'rm -rf "$work"' EXIT
ln -s "$pristine" "$work/a"
ln -s "$patched" "$work/b"
cd "$work"
status=0
diff -ruN \
    --exclude='*.o' --exclude='*.a' --exclude='*.so' --exclude='*.dylib' \
    --exclude='*.log' --exclude='config.status' --exclude='config.h' \
    --exclude='Makefile' --exclude='.ext' --exclude='enc' --exclude='tmp' \
    --exclude='miniruby' --exclude='ruby' --exclude='.bundle' \
    --exclude='*.inc' --exclude='*.rbinc' --exclude='GNUmakefile' \
    a b > tungsten.patch || status=$?
case "$status" in
  0) rm -f "$patch_dir/tungsten.patch" ;;
  1) mv tungsten.patch "$patch_dir/tungsten.patch" ;;
  *) exit "$status" ;;
esac
