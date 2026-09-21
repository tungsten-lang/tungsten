#!/bin/bash
# Reproducible end-to-end build of the WebAssembly Tungsten interpreter.
# Run from anywhere; everything is written under wasm/.
#
#   wasm/build.sh            full build
#   wasm/build.sh --no-test  skip node wasm/test.mjs
#   wasm/build.sh --skip-host  reuse wasm/build/host/tungsten-compiler (the slow step)
#
# Outputs:  wasm/tungsten.wasm   wasm/tungsten.fs
#
# Requirements (macOS/Homebrew paths are the defaults; override via env):
#   WASM_LLVM   dir holding clang + llvm-objcopy, LLVM >= 23   (/opt/homebrew/opt/llvm/bin)
#   WASM_LD     wasm-ld                                         (brew install lld)
#   TUNGSTEN_SEED_COMPILER  any working native tungsten-compiler, used ONCE to
#               compile this checkout's compiler (default: bin/tungsten-compiler here)
#   node, python3, curl; optional wasm-opt (npm --prefix wasm/toolchain install binaryen)
#
# Knobs: WASM_OPT_LEVEL (-O2) · WASM_LTO (1) · WASM_OPT_PASSES (-O2) ·
#        WASM_SKIP_WASM_OPT=1 · WASI_SDK_VERSION (34)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
S="$ROOT/wasm/scripts"
RUN_TESTS=1
BUILD_HOST=1
for arg in "$@"; do
  case "$arg" in
    --no-test) RUN_TESTS=0 ;;
    --skip-host) BUILD_HOST=0 ;;
    *) echo "unknown option $arg" >&2; exit 2 ;;
  esac
done
step() { printf '\n==> %s\n' "$1"; }

step "0/7 wasi sysroot + compiler-rt builtins (wasi-sdk release assets)"
"$S/fetch_toolchain.sh"

step "1/7 native host compiler from THIS checkout (triple-aware detect_target, wasm entry symbol, typed ccalls)"
if [ "$BUILD_HOST" = "1" ] || [ ! -x "$ROOT/wasm/build/host/tungsten-compiler" ]; then "$S/build_host.sh"; else echo "reusing wasm/build/host/tungsten-compiler"; fi

step "2/7 wasm/repl_entry.w -> wasm32-wasip1 LLVM IR"
"$S/emit_ir.sh"

step "3/7 LLVM IR -> wasm object"
"$S/compile_ir.sh"

step "4/7 C runtime + wasm/wasi_stubs.c -> wasm objects"
"$S/compile_runtime.sh" | tail -3

step "5/7 link (fails on any call that would trap from a signature mismatch)"
"$S/link.sh"

step "6/7 optimize + strip -> wasm/tungsten.wasm; pack wasm/tungsten.fs"
"$S/finish.sh" "$ROOT/wasm/tungsten.wasm"
python3 "$ROOT/wasm/pack_fs.py" --root "$ROOT" --out "$ROOT/wasm/tungsten.fs"

if [ "$RUN_TESTS" = "1" ]; then
  step "7/7 native twin of the same entry + node wasm/test.mjs"
  "$S/build_native_entry.sh" | tail -1
  node "$ROOT/wasm/test.mjs"
fi
