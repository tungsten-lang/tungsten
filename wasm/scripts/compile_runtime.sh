#!/bin/bash
# Step 3: compile the C runtime (+ wasm/wasi_stubs.c) for wasm32-wasi.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT/wasm/scripts/config.sh"
OUT="${WASM_RT_DIR:-$ROOT/wasm/build/rt}"
mkdir -p "$OUT"
OPT="${WASM_OPT_LEVEL:--O2}"
LTO=""
if [ "${WASM_LTO:-1}" = "1" ]; then LTO="-flto"; fi

# Set `wasm` of runtime/sources.txt (the one list of runtime sources): the
# portable subset of the compiler's runtime. Left out, with their few
# referenced symbols stubbed in wasm/wasi_stubs.c: the event backends (no
# event loop), the terminal input (termios), the Apple bridges, TLS and the
# HTTP/2 and HTTP/3 servers (the TLS stub is used) and the zstd slab codec
# (its stub is used).
SRCS="$(sh "$ROOT/runtime/sources.sh" wasm wasm | tr '\n' ' ')"
[ -n "$SRCS" ] || { echo "compile_runtime.sh: empty runtime source list" >&2; exit 1; }

CFLAGS="--target=$WASM_TRIPLE --sysroot=$WASM_SYSROOT $OPT $LTO $WASM_FEATURE_FLAGS \
  -mllvm -wasm-enable-sjlj \
  -D_WASI_EMULATED_MMAN -D_WASI_EMULATED_SIGNAL -D_WASI_EMULATED_PROCESS_CLOCKS -D_WASI_EMULATED_GETPID \
  -DTUNGSTEN_RUNTIME_COMPILER_IMAGE=1 -DNDEBUG -DW_SLAB_MAX_SLOTS=${WASM_SLAB_SLOTS:-262144} \
  -I$ROOT/wasm/compat -include $ROOT/wasm/compat/wasi_compat.h -I$ROOT/runtime \
  -fmerge-all-constants -fno-strict-aliasing -Wno-everything ${WASM_RT_CFLAGS:-}"

pids=()
for src in $SRCS; do
  ( "$WASM_CLANG" $CFLAGS -c "$ROOT/runtime/$src" -o "$OUT/$(basename "${src%.c}").o" ) &
  pids+=($!)
done
( "$WASM_CLANG" $CFLAGS -c "$ROOT/wasm/wasi_stubs.c" -o "$OUT/wasi_stubs.o" ) &
pids+=($!)
# WASM_ALLOC=seg links wasm_alloc.c (size-class pages, no coalescing: for one-shot
# instances; trees kernel -13%, DETOUR solver -22..34%). The default keeps dlmalloc.
rm -f "$OUT/wasm_alloc.o"
if [ "${WASM_ALLOC:-dlmalloc}" != "dlmalloc" ]; then
  ( "$WASM_CLANG" $CFLAGS -c "$ROOT/wasm/wasm_alloc.c" -o "$OUT/wasm_alloc.o" ) &
  pids+=($!)
fi
for p in "${pids[@]}"; do wait "$p"; done
ls -la "$OUT"
