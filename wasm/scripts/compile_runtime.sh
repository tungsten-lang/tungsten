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

# The portable subset of bin/commands/build.w's runtime_srcs. Left out, with
# their few referenced symbols stubbed in wasm/wasi_stubs.c:
#   event_kqueue.c / event_epoll.c / event_iouring.c  (no event loop)
#   terminal_input.c                                  (termios)
#   metal.m blas_bridge.c hid_bridge.m                (Apple frameworks / GPU)
#   tls.c http2.c http3.c                             (tls_stub.c is used)
#   slab_zstd.c                                       (slab_zstd_stub.c is used)
SRCS="runtime.c tensor_bridge.c ssmr_witness.c lexchar_tables.c unicode_tables.c aks.c tls_stub.c slab_zstd_stub.c"

CFLAGS="--target=$WASM_TRIPLE --sysroot=$WASM_SYSROOT $OPT $LTO $WASM_FEATURE_FLAGS \
  -mllvm -wasm-enable-sjlj \
  -D_WASI_EMULATED_MMAN -D_WASI_EMULATED_SIGNAL -D_WASI_EMULATED_PROCESS_CLOCKS -D_WASI_EMULATED_GETPID \
  -DTUNGSTEN_RUNTIME_COMPILER_IMAGE=1 -DNDEBUG -DW_SLAB_MAX_SLOTS=${WASM_SLAB_SLOTS:-262144} \
  -I$ROOT/wasm/compat -include $ROOT/wasm/compat/wasi_compat.h -I$ROOT/runtime \
  -fmerge-all-constants -fno-strict-aliasing -Wno-everything"

pids=()
for src in $SRCS; do
  ( "$WASM_CLANG" $CFLAGS -c "$ROOT/runtime/$src" -o "$OUT/${src%.c}.o" ) &
  pids+=($!)
done
( "$WASM_CLANG" $CFLAGS -c "$ROOT/wasm/wasi_stubs.c" -o "$OUT/wasi_stubs.o" ) &
pids+=($!)
for p in "${pids[@]}"; do wait "$p"; done
ls -la "$OUT"
