#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten-compiler}"
TMP_ROOT="${TMPDIR:-/tmp}/tungsten-small-array-wide-wire.$$"
WIRE="$TMP_ROOT/small-array-wide.wire"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT
mkdir -p "$TMP_ROOT"

"$TUNGSTEN" compile \
  "$ROOT/spec/compiler/small_array_wide_element_boxing_spec.w" \
  --emit-wire > "$WIRE"

wire_body() {
  local name="$1"
  sed -n "/^function __w_${name}(/,/^$/p" "$WIRE"
}

require_count() {
  local name="$1"
  local pattern="$2"
  local expected="$3"
  local count
  count="$(wire_body "$name" | grep -Ec "$pattern" || true)"
  if [[ "$count" -ne "$expected" ]]; then
    echo "WIRE check failed: $name has $count /$pattern/, expected $expected" >&2
    wire_body "$name" >&2
    exit 1
  fi
}

# Each function has exactly one SmallArray load.  u64 must box through the
# unsigned bridge, i64 through the checked signed bridge, and w64 not at all.
require_count stack_u64_text 'small_array_get_inline' 1
require_count stack_u64_text '@w_u64' 1
require_count stack_u64_text 'nanbox_int' 0

require_count stack_i64_text 'small_array_get_inline' 1
require_count stack_i64_text '@__w_int_fast' 1
require_count stack_i64_text 'nanbox_int' 0

require_count stack_w64_value 'small_array_get_inline' 1
require_count stack_w64_value '@w_u64|@__w_int_fast|nanbox_int' 0

echo "PASS small-array wide element WIRE"
