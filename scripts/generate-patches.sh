#!/bin/bash
# Generate patch files by diffing src/patched/ against src/pristine/
# Usage: scripts/generate-patches.sh

set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

for dep in ruby; do
  PATCHED="$ROOT/src/patched/$dep"
  # Find the versioned pristine dir (e.g., ruby-4.0.2)
  PRISTINE=$(ls -d "$ROOT/src/pristine/${dep}-"* 2>/dev/null | head -1)

  if [ -z "$PRISTINE" ] || [ ! -d "$PRISTINE" ]; then
    echo "skip $dep: no pristine source at src/pristine/${dep}-*"
    continue
  fi

  VERSION=$(basename "$PRISTINE" | sed "s/^${dep}-//")
  PATCH_DIR="$ROOT/patches/$dep/$VERSION"
  mkdir -p "$PATCH_DIR"

  echo "diffing $dep $VERSION..."
  diff -ruN \
    --exclude='*.o' --exclude='*.a' --exclude='*.so' --exclude='*.dylib' \
    --exclude='*.log' --exclude='config.status' --exclude='config.h' \
    --exclude='Makefile' --exclude='.ext' --exclude='enc' --exclude='tmp' \
    --exclude='miniruby' --exclude='ruby' --exclude='.bundle' \
    --exclude='*.inc' --exclude='*.rbinc' --exclude='GNUmakefile' \
    "$PRISTINE" "$PATCHED" > "$PATCH_DIR/tungsten.patch" || true

  LINES=$(wc -l < "$PATCH_DIR/tungsten.patch" | tr -d ' ')
  if [ "$LINES" -eq 0 ]; then
    echo "  no differences (pristine == patched)"
    rm "$PATCH_DIR/tungsten.patch"
  else
    echo "  wrote $PATCH_DIR/tungsten.patch ($LINES lines)"
  fi
done
