#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-source-argc1-proof.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

check_count() {
  local source="$1"
  local expected="$2"
  local stem
  local ll
  local actual
  stem="$(basename "${source%.w}")"
  ll="$TMP/$stem.ll"
  TUNGSTEN_LL_PATH="$ll" "$TUNGSTEN" compile "$ROOT/$source" \
    --release --emit-ll >/dev/null
  actual="$(grep -Ec 'call i64 @w_method_call_cached_1\(' "$ll" || true)"
  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL $source: expected $expected scalar argc-one call(s), got $actual" >&2
    exit 1
  fi
  echo "PASS $source: $actual scalar argc-one call(s)"
}

check_count spec/compiler/source_argc1_exact_ivar_spec.w 1
check_count spec/compiler/source_argc1_exact_ivar_soundness_spec.w 0
check_count spec/compiler/source_argc1_constructor_exclusion_spec.w 0
check_count spec/compiler/source_argc1_namespaced_reopen_spec.w 0
check_count spec/compiler/source_argc1_hint_compat_spec.w 1

echo "PASS exact-ivar argc-one selector structure"
