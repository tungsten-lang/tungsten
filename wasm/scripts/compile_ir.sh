#!/bin/bash
# Step 2: LLVM IR -> wasm object (bitcode when WASM_LTO=1).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT/wasm/scripts/config.sh"
cd "$ROOT/wasm/build"
OPT="${WASM_OPT_LEVEL:--O2}"
LTO=""
if [ "${WASM_LTO:-1}" = "1" ]; then LTO="-flto"; fi
"$WASM_CLANG" --target=$WASM_TRIPLE $OPT $LTO $WASM_FEATURE_FLAGS \
  -mllvm -wasm-enable-sjlj -Wno-override-module \
  -c repl_entry.ll -o repl_entry.o
ls -la repl_entry.o
