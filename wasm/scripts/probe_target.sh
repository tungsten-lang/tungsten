#!/bin/bash
# Diagnostic: emit IR for a one-line program for an arbitrary triple.
#   wasm/scripts/probe_target.sh <triple> [compiler]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
TRIPLE="$1"
HOSTC="${2:-$ROOT/wasm/build/host/tungsten-compiler}"
mkdir -p wasm/build/probe
printf '%s\n' "${PROBE_SRC:-<< 2 ** 100}" > wasm/build/probe/p.w
export TUNGSTEN_ROOT="$ROOT"
export TUNGSTEN_CC="${WASM_CLANG:-/opt/homebrew/opt/llvm/bin/clang}"
export TUNGSTEN_INCREMENTAL=0
export TUNGSTEN_CACHE_DIR="$ROOT/wasm/build/cache/host"   # see build_host.sh
mkdir -p "$TUNGSTEN_CACHE_DIR"
export TUNGSTEN_LL_PATH="$ROOT/wasm/build/probe/p.ll"
rm -f "$TUNGSTEN_LL_PATH"
"$HOSTC" compile wasm/build/probe/p.w --emit-ll --target="$TRIPLE" --release --no-debug --out wasm/build/probe/p 2>&1 | head -8
ls -la "$TUNGSTEN_LL_PATH" 2>&1 || true
