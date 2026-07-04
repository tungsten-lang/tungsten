#!/bin/bash
# Apply patches from patches/ to src/pristine/ → src/patched/
# Usage: scripts/apply-patches.sh

set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

for dep in ruby; do
  PRISTINE=$(ls -d "$ROOT/src/pristine/${dep}-"* 2>/dev/null | head -1)

  if [ -z "$PRISTINE" ] || [ ! -d "$PRISTINE" ]; then
    echo "skip $dep: no pristine source at src/pristine/${dep}-*"
    continue
  fi

  VERSION=$(basename "$PRISTINE" | sed "s/^${dep}-//")
  PATCH="$ROOT/patches/$dep/$VERSION/tungsten.patch"

  if [ ! -f "$PATCH" ]; then
    echo "skip $dep $VERSION: no patch file"
    continue
  fi

  PATCHED="$ROOT/src/patched/$dep"

  echo "copying pristine $dep $VERSION → patched..."
  rm -rf "$PATCHED"
  cp -a "$PRISTINE" "$PATCHED"

  echo "applying patches/$dep/$VERSION/tungsten.patch..."
  cd "$PATCHED"
  patch -p1 < "$PATCH"
  echo "done"
done
