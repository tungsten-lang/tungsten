#!/bin/bash
# Step 0: build a NATIVE compiler from this checkout's sources.
#
# The wasm IR has to be produced by a compiler that contains this checkout's
# compiler/lib/target.w (triple-aware `detect_target`), so the prebuilt seed
# compiler is only used to compile compiler/tungsten.w once.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
SEED="${TUNGSTEN_SEED_COMPILER:-$ROOT/bin/tungsten-compiler}"
OUT="$ROOT/wasm/build/host/tungsten-compiler"
mkdir -p "$(dirname "$OUT")"
export TUNGSTEN_ROOT="$ROOT"
export TUNGSTEN_INCREMENTAL=0
# The compiler's on-disk caches (function text, core lowering, parse) are not
# keyed by compiler identity or target. Sharing <repo>/build/cache between the
# seed and the host built below made the seed reuse function text the HOST had
# written (wrong string ids -> a host whose `main` mis-parses argv). Each
# compiler therefore gets its own cache dir, emptied whenever this script runs
# (only the slow-to-build native runtime archive is kept).
export TUNGSTEN_CACHE_DIR="$ROOT/wasm/build/cache/seed"
mkdir -p "$TUNGSTEN_CACHE_DIR"
find "$TUNGSTEN_CACHE_DIR" -mindepth 1 -maxdepth 1 ! -name 'runtime-native-*.a' -exec rm -rf {} +
rm -rf "$ROOT/wasm/build/cache/host"
unset TUNGSTEN_TARGET TUNGSTEN_LL_PATH
"$SEED" compile compiler/tungsten.w --out "$OUT" --release --no-debug --no-lto
ls -la "$OUT"
