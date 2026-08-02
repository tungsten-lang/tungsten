#!/usr/bin/env sh
set -eu

DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$DIR/../.." && pwd)
RUNTIME="$ROOT/runtime"
CC=${CC:-clang}
OUT="$DIR/bench_big_math"
PROFILE="$OUT.profile"

# -falign-functions=64: the bignum kernels are layout-sensitive (unaligned
# hot-loop heads swing small-multiply timings by 10-20% between otherwise
# identical builds); fixed alignment keeps benchmark results comparable.
CFLAGS=${CFLAGS:-"-O3 -DNDEBUG -mcpu=native -falign-functions=64 -Wno-deprecated-declarations"}

if [ "${1:-}" = "--profile" ]; then
  printf '%s\n' "$CC|$CFLAGS"
  exit 0
fi
ONIG_CFLAGS=$(pkg-config --cflags oniguruma 2>/dev/null || true)
ONIG_LDFLAGS=$(pkg-config --libs oniguruma 2>/dev/null || true)
GMP_CFLAGS=$(pkg-config --cflags gmp 2>/dev/null || true)
GMP_LDFLAGS=$(pkg-config --libs gmp 2>/dev/null || true)
GMP_DEFS=
if [ -n "$GMP_LDFLAGS" ]; then
  GMP_DEFS="-DHAVE_GMP"
fi

UNAME_S=$(uname -s)
case "$UNAME_S" in
  Darwin)
    EVENT_SRC="$RUNTIME/event_kqueue.c"
    METAL_SRC="$RUNTIME/metal.m $RUNTIME/graphics.m $RUNTIME/hid_bridge.m"
    PLATFORM_LDFLAGS="-framework Metal -framework Foundation -framework AppKit -framework QuartzCore -framework CoreGraphics -framework IOKit -framework CoreFoundation -framework Accelerate"
    ;;
  Linux)
    EVENT_SRC="$RUNTIME/event_epoll.c"
    METAL_SRC=
    PLATFORM_LDFLAGS=
    ;;
  *)
    echo "Unsupported platform: $UNAME_S" >&2
    exit 1
    ;;
esac

# shellcheck disable=SC2086
"$CC" $CFLAGS $ONIG_CFLAGS $GMP_CFLAGS $GMP_DEFS \
  "$DIR/bench_big_math.c" \
  "$EVENT_SRC" "$RUNTIME/terminal_input.c" "$RUNTIME/tls_stub.c" "$RUNTIME/aks.c" $METAL_SRC \
  $ONIG_LDFLAGS $GMP_LDFLAGS $PLATFORM_LDFLAGS \
  -o "$OUT"

printf '%s\n' "$CC|$CFLAGS" > "$PROFILE"

if [ "${1:-}" = "--build-only" ]; then
  exit 0
fi

exec "$OUT" "$@"
