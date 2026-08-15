#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten-compiler}"
TMP_ROOT="${TMPDIR:-/tmp}/tungsten-small-matrix-wire.$$"
WIRE="$TMP_ROOT/matrix.wire"
BENCH_WIRE="$TMP_ROOT/matmul-bench.wire"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT
mkdir -p "$TMP_ROOT"

"$TUNGSTEN" compile "$ROOT/spec/numeric/matrix_spec.w" --emit-wire > "$WIRE"
"$TUNGSTEN" compile "$ROOT/benchmarks/matmul/tungsten_matmul.w" --emit-wire > "$BENCH_WIRE"

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
require_count Mat3 '@w_array_new_inline' 1
require_count Mat3 'call_method_i64.*devirt=@__w_Mat3\$f64_elements__a1 class=Mat3\$f64' 1
require_count Mat3 'call_method_i64.*construct=@__w_Mat3\$f64_new__a2 class=Mat3\$f64' 1
require_absent Mat3 '@__w_mul_fast|@__w_add_fast'
require_absent Mat3 '@__w_array_lit_store|@w_array_to_f64'

require_count Mat4 'typed_array_get_inline' 128
require_count Mat4 'typed_array_set_inline' 16
require_count Mat4 '@w_array_new_inline' 1
require_count Mat4 'call_method_i64.*devirt=@__w_Mat4\$f64_elements__a1 class=Mat4\$f64' 1
require_count Mat4 'call_method_i64.*construct=@__w_Mat4\$f64_new__a2 class=Mat4\$f64' 1
require_absent Mat4 '@__w_mul_fast|@__w_add_fast'
require_absent Mat4 '@__w_array_lit_store|@w_array_to_f64'

school_body() {
  sed -n '/^function __w_matmul_school/,/^$/p' "$BENCH_WIRE"
}

school_require_count() {
  local pattern="$1"
  local expected="$2"
  local count
  count="$(school_body | grep -Ec "$pattern" || true)"
  if [[ "$count" -ne "$expected" ]]; then
    echo "WIRE check failed: matmul_school has $count /$pattern/, expected $expected" >&2
    school_body >&2
    exit 1
  fi
}

# A missing `i64` dimension annotation turns all four loop conditions and
# index expressions back into boxed runtime sends (~18x regression at N=512).
school_require_count 'icmp_i64' 4
school_require_count 'mul_i64' 4
school_require_count '@__w_(lt|mul|add|int)_fast' 0

echo "PASS small matrix WIRE"
