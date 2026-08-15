#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-source-argc1-proof.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

check_count() {
  local source="$1"
  local expected_one="$2"
  local expected_two="$3"
  local stem
  local ll
  local actual_one
  local actual_two
  stem="$(basename "${source%.w}")"
  ll="$TMP/$stem.ll"
  TUNGSTEN_LL_PATH="$ll" "$TUNGSTEN" compile "$ROOT/$source" \
    --release --emit-ll >/dev/null
  actual_one="$(grep -Ec 'call i64 @w_method_call_cached_1\(' "$ll" || true)"
  actual_two="$(grep -Ec 'call i64 @w_method_call_cached_2\(' "$ll" || true)"
  if [[ "$actual_one" != "$expected_one" || "$actual_two" != "$expected_two" ]]; then
    echo "FAIL $source: expected argc-one=$expected_one argc-two=$expected_two, got argc-one=$actual_one argc-two=$actual_two" >&2
    exit 1
  fi
  echo "PASS $source: argc-one=$actual_one argc-two=$actual_two scalar call(s)"
}

check_count spec/compiler/source_argc1_exact_ivar_spec.w 1 1
# Unknown, compound, destructuring, accessor, reopened, and inherited writes
# must all stay generic. Assignment-hint compatibility has its own executable
# fixture below and is intentionally not mixed into this zero-count corpus.
check_count spec/compiler/source_argc1_exact_ivar_soundness_spec.w 0 0
# The ordinary source-class holder is the single positive control; every
# runtime-backed constructor in the same fixture must remain excluded.
check_count spec/compiler/source_argc1_constructor_exclusion_spec.w 1 0
check_count spec/compiler/source_argc1_namespaced_reopen_spec.w 0 0
check_count spec/compiler/source_argc1_hint_compat_spec.w 1 0

echo "PASS exact-ivar scalar selector structure"
