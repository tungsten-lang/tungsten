#!/bin/sh
# jsu.sh file.js out — compile file.js's functions as a unit (translate/unit.w):
# out.json (the manifest), out.ll, out.o (what runtime/units.w loads).
# Builds build/jsc on first use (or when JSC_REBUILD=1). JSC_LIMIT/JSC_SKIP/JSC_MAXSIZE
# window the functions as for jsc.sh.
set -e
D="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$D/../.." && pwd)"
JSC="$D/build/jsc"
if [ ! -x "$JSC" ] || [ "$JSC_REBUILD" = "1" ]; then
  mkdir -p "$D/build"
  "$ROOT/bin/tungsten" -o "$JSC" "$D/tools/jsc.w" >&2
fi
js="$1"; out="$2"
case "$js" in /*) ;; *) js="$PWD/$js" ;; esac
case "$out" in /*) ;; *) out="$PWD/$out" ;; esac
# unsharded: jsu_init reaches each entry through its `w:` alias in the same module
TUNGSTEN_ROOT="$ROOT" TUNGSTEN_INCREMENTAL=0 TUNGSTEN_SHARD_CODEGEN=0 TUNGSTEN_LL_PATH="$out.ll" \
  JSC_JS="$js" JSC_UNIT="$out.json" "$JSC" compile --emit-ll "$D/unit/prelude.w" -o "$out.bin"
# the method-call inline caches become plain globals (a unit runs on its host's JS thread;
# the in-memory loader takes no thread-local relocations)
sed -i '' 's/ = internal thread_local global / = internal global /' "$out.ll"
"${CLANG:-/opt/homebrew/opt/llvm/bin/clang}" -O2 -fno-asynchronous-unwind-tables -c "$out.ll" -o "$out.o"
