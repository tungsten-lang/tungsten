#!/usr/bin/env bash
# A multiple assignment of machine-typed locals from a literal list lowers to
# register moves: no Array is built, nothing is boxed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten-compiler}"
TMP_ROOT="${TMPDIR:-/tmp}/tungsten-multi-assign-swap-wire.$$"
WIRE="$TMP_ROOT/multi-assign-swap.wire"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT
mkdir -p "$TMP_ROOT"

"$TUNGSTEN" compile "$ROOT/spec/compiler/multi_assign_swap_spec.w" --emit-wire > "$WIRE"

for fn in multi_assign_fib multi_assign_swap_diff multi_assign_rotate; do
  body="$(sed -n "/^function __w_${fn}__/,/^\$/p" "$WIRE")"
  if [[ -z "$body" ]]; then
    echo "WIRE check failed: no function body for $fn" >&2
    exit 1
  fi
  if grep -Eq 'w_array|w_destructure|@__w_int_fast|@__w_to_i64_fast|@__w_num_to_f64_fast|w_box' <<<"$body"; then
    echo "WIRE check failed: $fn allocates or boxes in a typed multiple assignment" >&2
    echo "$body" >&2
    exit 1
  fi
done

echo "PASS multiple assignment swap WIRE"
