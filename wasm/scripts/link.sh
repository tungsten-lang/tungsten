#!/bin/bash
# Step 4: link tungsten.wasm (wasm32-wasi command module: exports _start + memory).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT/wasm/scripts/config.sh"
B="$ROOT/wasm/build"
LIB="$WASM_SYSROOT/lib/$WASM_TRIPLE"
OPT="${WASM_OPT_LEVEL:--O2}"
LTO=""
if [ "${WASM_LTO:-1}" = "1" ]; then LTO="-flto"; fi
# clang looks for compiler-rt under <resource-dir>/lib/<triple>/; Homebrew LLVM
# ships no wasm builtins, so point it at the wasi-sdk copy.
mkdir -p "$B/resource/lib/wasm32-unknown-wasip1"
cp "$WASM_RTLIB" "$B/resource/lib/wasm32-unknown-wasip1/libclang_rt.builtins.a"
export PATH="$(dirname "$WASM_LD"):$PATH"   # clang execs `wasm-ld` from PATH
rm -f "$B/tungsten.raw.wasm"
# Stack: the tree-walking interpreter recurses deeply; 8 MiB matches the native
# main-thread stack. --stack-first makes an overflow trap instead of silently
# corrupting the data segment.
"$WASM_CLANG" --target=$WASM_TRIPLE --sysroot="$WASM_SYSROOT" $OPT $LTO $WASM_FEATURE_FLAGS \
  -Wl,-mllvm,-wasm-enable-sjlj \
  -resource-dir "$B/resource" \
  -Wl,--stack-first -Wl,-z,stack-size=8388608 \
  -Wl,--initial-memory=33554432 -Wl,--max-memory=1073741824 \
  -Wl,--gc-sections -Wl,--strip-debug \
  "$B/repl_entry.o" "$B"/rt/*.o \
  -lsetjmp -lwasi-emulated-signal -lwasi-emulated-process-clocks -lwasi-emulated-getpid \
  -ldl -lm \
  -o "$B/tungsten.raw.wasm" "$@" 2>&1 | tee "$B/link.log" | grep -v "loop not vectorized" || true
test -s "$B/tungsten.raw.wasm"
# WebAssembly type-checks calls. wasm-ld only WARNS about a caller/callee
# signature mismatch and links a stub that traps when reached, so treat it as
# a build failure (see "ccall_nobox ABI adapters" in wasm/compat/wasi_compat.h).
if grep -A2 "function signature mismatch" "$B/link.log"; then
  echo "link.sh: signature mismatches above would trap at run time" >&2
  exit 1
fi
# A call whose IR type disagrees with its callee links "successfully" as a stub
# that traps when reached (LTO hides it from wasm-ld's signature check). Fail
# the build instead: fix the declaration/definition pair it names.
if LC_ALL=C grep -a -o '[A-Za-z0-9_.]*_bitcast_invalid' "$B/tungsten.raw.wasm" | sort -u | grep . ; then
  echo "link.sh: mistyped calls above would trap at run time" >&2
  exit 1
fi
ls -la "$B/tungsten.raw.wasm"
