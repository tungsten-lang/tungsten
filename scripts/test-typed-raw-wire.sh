#!/usr/bin/env bash
# Typed code must lower to raw machine ops: a typed fn in
# spec/fixtures/typed/raw_probe.w that calls a boxed arithmetic helper
# (__w_add_fast, __w_shl_fast, __w_mul_fast, w_bigint_*_mut, __w_int_fast, ...)
# has regressed to the boxed path. Float functions still take and return boxed
# floats (the raw ABI covers integer and typed-array parameters only), so the
# param unbox __w_to_i64_fast is allowed in the float-returning fns.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten}"
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
"$TUNGSTEN" --wire "$ROOT/spec/fixtures/typed/raw_probe.w" >"$tmp" 2>&1
fail=0
for fn in fa fc gc hc band mixf elemf elemf2 loopshl early clip useclip wid tern2 flt gtab; do
  body=$(awk -v f="$fn" '$1 == "function" && index($2, "__w_" f "__") == 1 {on=1; next} on && /^$/ {on=0} on {print}' "$tmp")
  if [[ -z "$body" ]]; then
    echo "typed-raw: no WIRE for $fn" >&2; fail=1; continue
  fi
  bad=$(printf '%s\n' "$body" | grep -E '@(__w_(add|sub|mul|shl|shr|band|bor|bxor|int|div|mod|gte|gt|lt|lte)_fast|w_bigint_[a-z_]*mut|w_(add|sub|mul)\b|w_index_raw_i64)' || true)
  if [[ "$fn" != mixf && "$fn" != elemf && "$fn" != elemf2 && "$fn" != flt ]]; then
    bad="$bad$(printf '%s\n' "$body" | grep -E '@__w_to_i64_fast' || true)"
  fi
  if [[ -n "$bad" ]]; then
    echo "typed-raw: $fn boxes:" >&2; printf '%s\n' "$bad" >&2; fail=1
  fi
done
(( fail == 0 )) && echo "typed raw wire: ok"
exit $fail
