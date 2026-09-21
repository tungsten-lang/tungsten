#!/bin/bash
# Build wasm/repl_entry.w as a NATIVE binary from the same sources. test.mjs
# uses it as the like-for-like reference: same entry, same interpreter, same
# core — the only variable left is the target.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
HOSTC="${TUNGSTEN_HOST_COMPILER:-$ROOT/wasm/build/host/tungsten-compiler}"
export TUNGSTEN_ROOT="$ROOT"
export TUNGSTEN_INCREMENTAL=0
export TUNGSTEN_CACHE_DIR="$ROOT/wasm/build/cache/host"   # see build_host.sh
mkdir -p "$TUNGSTEN_CACHE_DIR"
unset TUNGSTEN_TARGET TUNGSTEN_LL_PATH TUNGSTEN_TARGET_MARCH_ARGS
"$HOSTC" compile wasm/repl_entry.w --out wasm/build/native_entry --release --no-debug --no-lto
ls -la wasm/build/native_entry
