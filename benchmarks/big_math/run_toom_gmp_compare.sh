#!/usr/bin/env sh
set -eu

DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$DIR/../.." && pwd)
RUNTIME="$ROOT/runtime"
CC=${CC:-clang}
OUT="$DIR/toom_gmp_compare"

CFLAGS=${CFLAGS:-"-O3 -mcpu=native -Wno-deprecated-declarations"}
ONIG_CFLAGS=$(pkg-config --cflags oniguruma 2>/dev/null || true)
ONIG_LDFLAGS=$(pkg-config --libs oniguruma 2>/dev/null || true)
GMP_CFLAGS=$(pkg-config --cflags gmp 2>/dev/null || true)
GMP_LDFLAGS=$(pkg-config --libs gmp 2>/dev/null || true)
if [ -z "$GMP_LDFLAGS" ]; then
  echo "GMP is required for the forced Toom comparison (pkg-config gmp failed)." >&2
  exit 1
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
"$CC" $CFLAGS $ONIG_CFLAGS $GMP_CFLAGS \
  "$DIR/toom_gmp_compare.c" \
  "$EVENT_SRC" "$RUNTIME/tls_stub.c" "$RUNTIME/aks.c" $METAL_SRC \
  $ONIG_LDFLAGS $GMP_LDFLAGS $PLATFORM_LDFLAGS \
  -o "$OUT"

exec "$OUT" "$@"
