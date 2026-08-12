#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten-compiler}"
TMP_ROOT="${TMPDIR:-/tmp}/tungsten-small-matrix-wire.$$"
WIRE="$TMP_ROOT/matrix.wire"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT
mkdir -p "$TMP_ROOT"

"$TUNGSTEN" compile "$ROOT/spec/numeric/matrix_spec.w" --emit-wire > "$WIRE"

matrix_body() {
  local class_name="$1"
  sed -n "/^function __w_${class_name}\\\$f64__STAR__ovl_${class_name}\\\$f64__a2(/,/^$/p" "$WIRE"
}

require_count() {
  local class_name="$1"
  local pattern="$2"
  local expected="$3"
  local count
  count="$(matrix_body "$class_name" | grep -Ec "$pattern" || true)"
  if [[ "$count" -ne "$expected" ]]; then
    echo "WIRE check failed: $class_name#* has $count /$pattern/, expected $expected" >&2
    matrix_body "$class_name" >&2
    exit 1
  fi
}

require_absent() {
  local class_name="$1"
  local pattern="$2"
  require_count "$class_name" "$pattern" 0
}

# Each result element reads one full row/column pair and writes directly into
# one typed result buffer. Boxed arithmetic and the old boxed-literal copy are
# performance regressions, not alternate valid shapes for these f64 workers.
require_count Mat3 'typed_array_get_inline' 54
require_count Mat3 'typed_array_set_inline' 9
require_count Mat3 '@w_array_new_inline_uninit_sized' 1
require_absent Mat3 '@__w_mul_fast|@__w_add_fast'
require_absent Mat3 '@__w_array_lit_store|@w_array_to_f64'

require_count Mat4 'typed_array_get_inline' 128
require_count Mat4 'typed_array_set_inline' 16
require_count Mat4 '@w_array_new_inline_uninit_sized' 1
require_absent Mat4 '@__w_mul_fast|@__w_add_fast'
require_absent Mat4 '@__w_array_lit_store|@w_array_to_f64'

echo "PASS small matrix WIRE"
