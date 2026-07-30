#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten-compiler}"
TMP_ROOT="${TMPDIR:-/tmp}/tungsten-raw-static-return-wire.$$"
WIRE="$TMP_ROOT/raw-static-return.wire"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT
mkdir -p "$TMP_ROOT"

"$TUNGSTEN" compile "$ROOT/spec/compiler/raw_static_machine_return_spec.w" --emit-wire > "$WIRE"

wire_body() {
  sed -n '/^function __w_raw_static_machine_selector__u16_A_u64(/,/^$/p' "$WIRE"
}

require_count() {
  local pattern="$1"
  local expected="$2"
  local count
  count="$(wire_body | grep -Ec "$pattern" || true)"
  if [[ "$count" -ne "$expected" ]]; then
    echo "WIRE check failed: selector has $count /$pattern/, expected $expected" >&2
    wire_body >&2
    exit 1
  fi
}

# The old lowering boxed the call result and dependent arithmetic, producing
# three __w_int_fast calls plus boxed add/compare/final-return conversions.
require_count '@__w_int_fast' 0
require_count '@__w_add_fast' 0
require_count '@__w_lt_fast' 0
require_count '@__w_to_i64_fast' 0
require_count 'add_i64' 1
require_count 'icmp_i64' 1
require_count 'ret_i64' 1

echo "PASS raw static machine-return WIRE"
