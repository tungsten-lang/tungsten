#!/bin/sh
# Mirror the engine into Blade (apps/blade/lib/blade/wasm/). Blade takes no shared code, so
# it carries a copy; this directory (languages/wasm/ in the Tungsten repo) is the source.
# The JS API binding is Blade's own lib/blade/jswasm.w.
set -e
SRC="$(cd "$(dirname "$0")/.." && pwd)"
DST="${1:-$HOME/studio/apps/blade}/lib/blade/wasm"
mkdir -p "$DST"
for f in "$SRC"/*.w; do
  cp "$f" "$DST/$(basename "$f")"
done
echo "synced $(ls "$SRC"/*.w | wc -l | tr -d ' ') files to $DST"
