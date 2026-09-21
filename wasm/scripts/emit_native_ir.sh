#!/bin/bash
# Regression aid: emit the NATIVE (host-target) IR of wasm/repl_entry.w to the
# given path. Used to prove that core/compiler edits made for the wasm port do
# not change native codegen (diff the before/after files).
#   wasm/scripts/emit_native_ir.sh <out.ll> [compiler]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
OUT="$1"
HOSTC="${2:-$ROOT/wasm/build/host/tungsten-compiler}"
export TUNGSTEN_ROOT="$ROOT"
export TUNGSTEN_INCREMENTAL=0
export TUNGSTEN_CACHE_DIR="$ROOT/wasm/build/cache/host"   # see build_host.sh
mkdir -p "$TUNGSTEN_CACHE_DIR"
export TUNGSTEN_LL_PATH="$OUT"
unset TUNGSTEN_TARGET
rm -f "$OUT"
"$HOSTC" compile wasm/repl_entry.w --emit-ll --release --no-debug --out wasm/build/native_entry
ls -la "$OUT"
