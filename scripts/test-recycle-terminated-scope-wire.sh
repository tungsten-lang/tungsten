#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten}"
TMP_ROOT="${TMPDIR:-/tmp}/tungsten-recycle-scope-wire.$$"
WIRE="$TMP_ROOT/recycle-scope.wire"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT
mkdir -p "$TMP_ROOT"

"$TUNGSTEN" compile "$ROOT/spec/compiler/recycle_terminated_scope_spec.w" --emit-wire > "$WIRE"

wire_body() {
  sed -n "/^function $1(/,/^$/p" "$WIRE"
}

require_count() {
  local fn="$1"
  local pattern="$2"
  local expected="$3"
  local count
  count="$(wire_body "$fn" | grep -Ec "$pattern" || true)"
  if [[ "$count" -ne "$expected" ]]; then
    echo "WIRE check failed: $fn has $count /$pattern/, expected $expected" >&2
    wire_body "$fn" >&2
    exit 1
  fi
}

# Explicit return abandons two nested scopes. The taken return has Hash+Array
# cleanup; the nested-if false path has the outer Array's ordinary scope exit.
# Thus the one Array push has two mutually exclusive cleanup sites.
RETURN_FN="__w_recycle_scope_return"
require_count "$RETURN_FN" 'cleanup_push_array' 1
require_count "$RETURN_FN" 'cleanup_push_hash' 1
require_count "$RETURN_FN" 'cleanup_pop' 3
require_count "$RETURN_FN" 'call_recycle_array' 2
require_count "$RETURN_FN" 'call_recycle_hash' 1
if ! wire_body "$RETURN_FN" | awk '
  /cleanup_pop/ && state == 0 { state = 1; next }
  /call_recycle_hash/ && state == 1 { state = 2; next }
  /cleanup_pop/ && state == 2 { state = 3; next }
  /call_recycle_array/ && state == 3 { found = 1 }
  END { exit(found ? 0 : 1) }
'; then
  echo "WIRE check failed: $RETURN_FN lacks LIFO Hash-then-Array return cleanup" >&2
  wire_body "$RETURN_FN" >&2
  exit 1
fi

# The Hash is allocated only after the early-return branch. Its cleanup appears
# only at the later return, never at the non-dominated earlier return.
LATE_FN="__w_recycle_scope_return_before_sibling"
require_count "$LATE_FN" 'cleanup_push_hash' 1
require_count "$LATE_FN" 'cleanup_pop' 1
require_count "$LATE_FN" 'call_recycle_hash' 1

# One allocation site has two mutually exclusive normal exits: transfer and
# loop fallthrough. Thus each loop has one push site and two cleanup call sites.
for fn in __w_recycle_scope_break __w_recycle_scope_next; do
  require_count "$fn" 'cleanup_push_array' 1
  require_count "$fn" 'cleanup_pop' 2
  require_count "$fn" 'call_recycle_array' 2
done

# Exact Array#uniq regression: the Hash after the break-containing branch must
# now attach to function scope and receive its final-ret cleanup pair.
SIBLING_FN="__w_recycle_scope_sibling"
require_count "$SIBLING_FN" 'cleanup_push_hash' 1
require_count "$SIBLING_FN" 'cleanup_pop' 1
require_count "$SIBLING_FN" 'call_recycle_hash' 1

# The raise path is handled by w_raise at runtime; WIRE contains only the one
# normal try cleanup and one normal rescue cleanup, with no duplicated pair.
EXCEPTION_FN="__w_recycle_scope_exception"
require_count "$EXCEPTION_FN" 'cleanup_push_array' 1
require_count "$EXCEPTION_FN" 'cleanup_push_hash' 1
require_count "$EXCEPTION_FN" 'cleanup_pop' 2
require_count "$EXCEPTION_FN" 'call_recycle_array' 1
require_count "$EXCEPTION_FN" 'call_recycle_hash' 1

echo "PASS recycle terminated-scope WIRE (return, break, next, sibling restore, exception balance)"
