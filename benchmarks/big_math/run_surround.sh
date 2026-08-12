#!/usr/bin/env sh
# Build + run the surrounding-cost decomposition probe (see surround_probe.c).
set -eu
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$DIR/../.." && pwd)
RUNTIME="$ROOT/runtime"
CC=${CC:-$("$DIR/run.sh" --profile | cut -d'|' -f1)}
CFLAGS=${CFLAGS:-$("$DIR/run.sh" --profile | cut -d'|' -f2)}
OUT=${BENCH_OUT:-"$DIR/surround_probe"}
ONIG_CFLAGS=$(pkg-config --cflags oniguruma 2>/dev/null || true)
ONIG_LDFLAGS=$(pkg-config --libs oniguruma 2>/dev/null || true)
# shellcheck disable=SC2086
"$CC" $CFLAGS $ONIG_CFLAGS \
  "$DIR/surround_probe.c" \
  "$RUNTIME/event_kqueue.c" "$RUNTIME/terminal_input.c" "$RUNTIME/tls_stub.c" "$RUNTIME/aks.c" \
  "$RUNTIME/metal.m" "$RUNTIME/graphics.m" "$RUNTIME/hid_bridge.m" \
  $ONIG_LDFLAGS \
  -framework Metal -framework Foundation -framework AppKit -framework QuartzCore \
  -framework CoreGraphics -framework IOKit -framework CoreFoundation -framework Accelerate \
  -o "$OUT"
if [ "${1:-}" = "--build-only" ]; then exit 0; fi
exec "$OUT"
