#!/usr/bin/env sh
set -eu

# Factorial vs. Stirling's approximation, computed entirely in Tungsten bigints
# (no IEEE floats — 2000! ~= 10^5736 overflows every double). Compiles the .w
# program to a native binary and runs it.

DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$DIR/../.." && pwd)
OUT="$DIR/stirling_factorial"

"$ROOT/bin/tungsten" -o "$OUT" "$DIR/stirling_factorial.w"

exec "$OUT" "$@"
