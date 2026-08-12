#!/usr/bin/env sh
set -eu

DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$DIR/../.." && pwd)
RUNTIME="$ROOT/runtime"
CC=${CC:-clang}
OUT="$DIR/toom_sweep"

# Match run.sh's CPU resolution: clang's `native` lags new silicon (an M5
# resolves to apple-m4), so name the chip when the compiler knows it.
MCPU=native
if [ "$(uname -s)" = "Darwin" ] && sysctl -n machdep.cpu.brand_string 2>/dev/null | grep -q "M5"; then
  if "$CC" -mcpu=apple-m5 -fsyntax-only -x c /dev/null >/dev/null 2>&1; then
    MCPU=apple-m5
  else
    MCPU="apple-m4+sme2p1+sme-f16f16+sme-b16b16+cssc+wfxt+hbc"
  fi
fi
CFLAGS="-O3 -mcpu=$MCPU -Wno-deprecated-declarations"
ONIG_CFLAGS=$(pkg-config --cflags oniguruma 2>/dev/null || true)
ONIG_LDFLAGS=$(pkg-config --libs oniguruma 2>/dev/null || true)

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
"$CC" $CFLAGS $ONIG_CFLAGS \
  "$DIR/toom_sweep.c" \
  "$RUNTIME/ssmr_witness.c" "$EVENT_SRC" "$RUNTIME/terminal_input.c" "$RUNTIME/tls_stub.c" "$RUNTIME/aks.c" $METAL_SRC \
  $ONIG_LDFLAGS $PLATFORM_LDFLAGS \
  -o "$OUT"

exec "$OUT" "$@"
