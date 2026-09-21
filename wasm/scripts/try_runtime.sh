#!/bin/bash
# Diagnostic: syntax-check one runtime source for wasm32-wasi and dump errors.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT/wasm/scripts/config.sh"
SRC="${1:-runtime.c}"
cd "$ROOT/runtime"
"$WASM_CLANG" --target=$WASM_TRIPLE --sysroot="$WASM_SYSROOT" $WASM_FEATURE_FLAGS \
  -mllvm -wasm-enable-sjlj \
  -D_WASI_EMULATED_MMAN -D_WASI_EMULATED_SIGNAL -D_WASI_EMULATED_PROCESS_CLOCKS -D_WASI_EMULATED_GETPID \
  -I"$ROOT/wasm/compat" -include "$ROOT/wasm/compat/wasi_compat.h" \
  -DTUNGSTEN_RUNTIME_COMPILER_IMAGE=1 \
  -fsyntax-only -ferror-limit=0 -Wno-everything "$SRC" > "$ROOT/wasm/build/try_$SRC.log" 2>&1
grep -c "error:" "$ROOT/wasm/build/try_$SRC.log"
