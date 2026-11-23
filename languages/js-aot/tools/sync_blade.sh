#!/bin/sh
# sync_blade — copy the engine into Blade (Blade takes copies, no shared code):
#   tools/sync_blade.sh [~/studio/apps/blade]
# Everything lands flat in lib/blade/jsn/ with the `use` lines rewritten. Blade's own
# jsn/engine.w and jsn/compat.w are not touched.
set -e
D="$(cd "$(dirname "$0")/.." && pwd)"
B="${1:-$HOME/studio/apps/blade}"
J="$B/lib/blade/jsn"
mkdir -p "$J"
cp "$D/frontend/lexer.w" "$D/frontend/parser.w" "$J/"
sed 's|^use frontend/parser|use parser|' "$D/analyze.w" > "$J/analyze.w"
sed 's|^use \.\./frontend/parser|use parser|; s|^use \.\./analyze|use analyze|' "$D/tier0/walk.w" > "$J/walk.w"
for f in "$D"/runtime/*.w; do cp "$f" "$J/"; done
echo "synced into $J"
