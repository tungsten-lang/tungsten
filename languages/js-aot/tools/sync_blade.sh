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
"$D/tools/engine_id.sh" > /dev/null
# drop engine files that no longer exist upstream (Blade's own engine.w/compat.w stay)
for f in "$J"/*.w; do
  b=$(basename "$f")
  case "$b" in engine.w|compat.w|unitcache.w|lexer.w|parser.w|analyze.w|walk.w) continue ;; esac
  [ -f "$D/runtime/$b" ] || rm -f "$f"
done
cp "$D/frontend/lexer.w" "$D/frontend/parser.w" "$J/"
sed 's|^use frontend/parser|use parser|' "$D/analyze.w" > "$J/analyze.w"
sed 's|^use \.\./frontend/parser|use parser|; s|^use \.\./analyze|use analyze|' "$D/tier0/walk.w" > "$J/walk.w"
for f in "$D"/runtime/*.w; do cp "$f" "$J/"; done
echo "synced into $J"
