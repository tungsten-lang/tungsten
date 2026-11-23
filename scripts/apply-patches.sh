#!/usr/bin/env bash
# Apply the named Ruby release's Tungsten patch, preserving existing source edits.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
version="${1:-$(readlink "$ROOT/src/patched/ruby/current" || true)}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "usage: $0 x.y.z" >&2; exit 2; }
patch_file="$ROOT/src/patches/ruby/$version/tungsten.patch"
[[ -f "$patch_file" ]] || { echo "No Tungsten patch for Ruby $version"; exit 0; }
patched="$ROOT/src/patched/ruby/$version"
if [[ ! -d "$patched" ]]; then
  pristine="$ROOT/src/pristine/ruby-$version"
  [[ -d "$pristine" ]] || { echo "Missing $pristine" >&2; exit 1; }
  patch -f --dry-run -d "$pristine" -p1 < "$patch_file"
  mkdir -p "$(dirname "$patched")"
  cp -a "$pristine" "$patched"
fi
patch -f --dry-run -d "$patched" -p1 < "$patch_file"
patch -f -d "$patched" -p1 < "$patch_file"
