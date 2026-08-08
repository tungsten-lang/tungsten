#!/usr/bin/env sh
set -eu

DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$DIR/../.." && pwd)
RUNTIME="$ROOT/runtime"
# Match the tungsten driver's compiler preference: a clang with LLVM >= 22
# when installed (better vectorizer; same toolchain users' --release builds
# get), else the system clang.
if [ -z "${CC:-}" ]; then
  CC=clang
  for cand in /opt/homebrew/opt/llvm/bin/clang /usr/local/opt/llvm/bin/clang; do
    if [ -x "$cand" ]; then
      case "$("$cand" --version 2>/dev/null | head -1)" in
        *"version 22."*|*"version 23."*|*"version 24."*) CC=$cand; break ;;
      esac
    fi
  done
fi
# A worker-count sweep builds several otherwise-identical harnesses with
# different compile-time parallelism caps.  Keep those binaries outside the
# normal development harness so a measurement cannot silently replace it.
OUT=${BENCH_OUT:-"$DIR/bench_big_math"}
PROFILE=${BENCH_PROFILE:-"$OUT.profile"}
mkdir -p "$(dirname "$OUT")"

# Match the driver's CPU resolution: clang's `native` detection lags new
# silicon (resolves an M5 to apple-m4), so name the chip explicitly when the
# compiler knows it, with the driver's same feature-suffix fallback.
MCPU=native
if [ "$(uname -s)" = "Darwin" ] && sysctl -n machdep.cpu.brand_string 2>/dev/null | grep -q "M5"; then
  if "$CC" -mcpu=apple-m5 -fsyntax-only -x c /dev/null >/dev/null 2>&1; then
    MCPU=apple-m5
  else
    MCPU="apple-m4+sme2p1+sme-f16f16+sme-b16b16+cssc+wfxt+hbc"
  fi
fi

# -falign-functions=64: the bignum kernels are layout-sensitive (unaligned
# hot-loop heads swing small-multiply timings by 10-20% between otherwise
# identical builds); fixed alignment keeps benchmark results comparable.
# -flto -ffast-math: mirror `tungsten compile --release --fast` (fast FP
# semantics + backend -ffast-math, NOT the FAST_MATH source define) so the
# `bench bignum` lane is built the way the other bench subcommands build
# Tungsten. IEEE-sensitive kernels can opt out locally (strict math blocks).
CFLAGS=${CFLAGS:-"-O3 -flto -ffast-math -DNDEBUG -mcpu=$MCPU -falign-functions=64 -Wno-deprecated-declarations"}

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
