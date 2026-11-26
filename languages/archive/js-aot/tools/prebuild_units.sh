#!/bin/sh
# prebuild_units.sh dir — build the units Blade's jsn/unitcache.w would build, for every
# script source it saved in dir (<sha40>.js), one compile at a time; windows of 2,000
# functions (functions over 100 KB of source stay in tier 0), named as unitcache.w names
# them. Stops a script's windows at the first one that compiles no function.
set -u
D="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$D/../.." && pwd)"
dir="${1:-$HOME/Library/Caches/Blade/js-units}"
id=$(sed -n 's/^JSU_ENGINE_ID = "\(.*\)"/\1/p' "$D/runtime/unit_id.w")
CC=/opt/homebrew/opt/llvm/bin/clang
for js in "$dir"/*.js; do
  sha=$(basename "$js" .js)
  k=0
  while :; do
    base="$dir/$sha-$id-w2000-$k"
    if [ ! -f "$base.json" ]; then
      tmp="$base.tmp$$"
      if ! TUNGSTEN_ROOT="$ROOT" TUNGSTEN_INCREMENTAL=0 TUNGSTEN_SHARD_CODEGEN=0 TUNGSTEN_MEMORY_LIMIT=6G \
          TUNGSTEN_LL_PATH="$tmp.ll" JSC_JS="$js" JSC_UNIT="$tmp.json" JSC_LIMIT=2000 JSC_SKIP=$((k * 2000)) \
          JSC_MAXSIZE=100000 timeout 1200 "$D/build/jsc" compile --emit-ll "$D/unit/prelude.w" -o "$tmp.bin" > "$tmp.log" 2>&1; then
        echo "FAILED $sha window $k ($tmp.log)"; break
      fi
      sed -i '' 's/ = internal thread_local global / = internal global /' "$tmp.ll"
      if ! "$CC" -O2 -fno-asynchronous-unwind-tables -c "$tmp.ll" -o "$tmp.o" 2>> "$tmp.log"; then
        echo "FAILED clang $sha window $k"; break
      fi
      t=$(sed -n 's/.*translated=\([0-9]*\).*/\1/p' "$tmp.log" | tail -1)
      echo "${t:-0}" > "$base.count"
      mv "$tmp.o" "$base.o"; mv "$tmp.json" "$base.json"; rm -f "$tmp.ll" "$tmp.bin"* "$tmp.ll.done" "$tmp.log"
      echo "built $sha window $k ($t functions)"
    fi
    # a window short of 2,000 functions (plus the script's own body) is the last
    t=$(cat "$base.count" 2>/dev/null || echo 2001)
    [ "$t" -ge 2000 ] || break
    k=$((k + 1))
  done
done
