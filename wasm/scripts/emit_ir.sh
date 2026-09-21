#!/bin/bash
# Step 1: lower wasm/repl_entry.w to wasm32-wasi LLVM IR with a host compiler.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
HOSTC="${TUNGSTEN_HOST_COMPILER:-$ROOT/wasm/build/host/tungsten-compiler}"
CLANG="${WASM_CLANG:-/opt/homebrew/opt/llvm/bin/clang}"
mkdir -p wasm/build
export TUNGSTEN_ROOT="$ROOT"
export TUNGSTEN_CC="$CLANG"
export TUNGSTEN_INCREMENTAL=0
export TUNGSTEN_CACHE_DIR="$ROOT/wasm/build/cache/host"   # see build_host.sh
mkdir -p "$TUNGSTEN_CACHE_DIR"
# Feature flags shared with the runtime's C objects (wasm/scripts/config.sh).
source "$ROOT/wasm/scripts/config.sh"
export TUNGSTEN_TARGET_MARCH_ARGS="$WASM_FEATURE_FLAGS"
export TUNGSTEN_LL_PATH="$ROOT/wasm/build/repl_entry.ll"
"$HOSTC" compile wasm/repl_entry.w --emit-ll --target=wasm32-wasip1 --release --no-debug \
  --out wasm/build/repl_entry "$@"
ls -la wasm/build/repl_entry.ll
