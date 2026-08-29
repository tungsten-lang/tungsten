#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten}"
CC="${CC:-clang}"
FIXTURE="$ROOT/spec/compiler/fused_destination_reuse_spec.w"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-fused-reuse.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

TUNGSTEN_LL_PATH="$TMP/fused-reuse.ll" \
  "$TUNGSTEN" compile "$FIXTURE" --release --emit-ll \
  --out "$TMP/fused-reuse" >/dev/null
"$TUNGSTEN" compile "$FIXTURE" --release \
  --out "$TMP/fused-reuse" >/dev/null

if ! "$CC" -x ir -c "$TMP/fused-reuse.ll" \
  -o "$TMP/fused-reuse.o" >"$TMP/clang.out" 2>&1; then
  cat "$TMP/clang.out" >&2
  exit 1
fi

run_out="$(TUNGSTEN_FUSED_THREADS=1 "$TMP/fused-reuse")"
if grep -Fq 'FAIL ' <<<"$run_out"; then
  printf '%s\n' "$run_out" >&2
  exit 1
fi
pass_count="$(grep -Fc 'PASS ' <<<"$run_out")"
if [[ "$pass_count" -ne 3 ]]; then
  printf '%s\n' "$run_out" >&2
  echo "FAIL: expected three destination-reuse checks" >&2
  exit 1
fi

symbol_for_method() {
  sed -n "/\"method\":\"$1\"/ { s/.*\"symbol\": \"\(__wy_[^\"]*\)\".*/\1/p; q; }" \
    "$TMP/fused-reuse.sidemap"
}

safe_symbol="$(symbol_for_method auto_reuse_values)"
self_symbol="$(symbol_for_method auto_reuse_self_input)"
alias_symbol="$(symbol_for_method alias_forces_fresh_output)"
if [[ -z "$safe_symbol" || -z "$self_symbol" || -z "$alias_symbol" ]]; then
  echo "FAIL: could not resolve compact fixture symbols from sidemap" >&2
  exit 1
fi

safe_body="$(sed -n "/define internal i64 @$safe_symbol(/,/^}/p" "$TMP/fused-reuse.ll")"
self_body="$(sed -n "/define internal i64 @$self_symbol(/,/^}/p" "$TMP/fused-reuse.ll")"
alias_body="$(sed -n "/define internal i64 @$alias_symbol(/,/^}/p" "$TMP/fused-reuse.ll")"

if ! grep -Fq '@w_fused_out_reuse_value_or_new' <<<"$safe_body"; then
  echo "FAIL: proven-unique assignment did not reuse its destination" >&2
  exit 1
fi
if ! grep -Fq '@w_fused_out_reuse_value_or_new' <<<"$self_body"; then
  echo "FAIL: self-input fused assignment did not reuse its destination" >&2
  exit 1
fi
self_reuse_tail="$(sed -n '/@w_fused_out_reuse_value_or_new/,$p' <<<"$self_body")"
if grep -Eq '!noalias|!alias\.scope' <<<"$self_reuse_tail"; then
  echo "FAIL: self-input reuse retained fresh-output noalias metadata" >&2
  exit 1
fi
if grep -Fq '@w_fused_out_reuse_value_or_new' <<<"$alias_body"; then
  echo "FAIL: aliased destination was incorrectly reused" >&2
  exit 1
fi
if ! grep -Fq '@w_array_new_uninit_sized' <<<"$alias_body"; then
  echo "FAIL: aliased destination did not keep the fresh-output path" >&2
  exit 1
fi

echo "fused destination reuse correctness + IR: ok"
