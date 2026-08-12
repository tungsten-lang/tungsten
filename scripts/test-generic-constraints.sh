#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten}"
FIXTURES="$ROOT/compiler/test/fixtures"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-generic-constraints.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

check_accepts() {
  local fixture="$1"
  "$TUNGSTEN" check "$FIXTURES/$fixture" >"$TMP/$fixture.out" 2>&1
}

check_rejects() {
  local fixture="$1"
  local code="$2"
  local message="$3"
  if "$TUNGSTEN" check "$FIXTURES/$fixture" >"$TMP/$fixture.out" 2>&1; then
    printf 'generic constraint fixture unexpectedly passed: %s\n' "$fixture" >&2
    exit 1
  fi
  grep -Fq "$code" "$TMP/$fixture.out"
  grep -Fq "$message" "$TMP/$fixture.out"
}

check_accepts generic_constraint_valid_inherited.w
check_rejects generic_constraint_unknown_param.w E_LOWER_GENERIC_CONSTRAINT \
  'constraint names unknown parameter U of Broken'
check_rejects generic_constraint_duplicate.w E_LOWER_GENERIC_CONSTRAINT \
  'duplicate constraint for parameter T of Broken'
check_rejects generic_constraint_empty.w E_LOWER_GENERIC_CONSTRAINT \
  'constraint for parameter T of Broken has no allowed types'
check_rejects generic_constraint_repeated_type.w E_LOWER_GENERIC_CONSTRAINT \
  "constraint for parameter T of Broken repeats type 'i32'"
check_rejects generic_constraint_parent_arity.w E_LOWER_GENERIC_ARITY \
  'generic parent Parent of Broken expects 2 type args, got 1'
check_rejects generic_constraint_parent_incompatible.w E_LOWER_GENERIC_CONSTRAINT \
  "constraint type 'String' for parameter T of Broken is not allowed by parent Parent"
check_rejects generic_constraint_parent_concrete.w E_LOWER_GENERIC_CONSTRAINT \
  "parent type argument 'String' for Broken is not allowed for parameter T of Parent"
check_rejects generic_constraint_inherited_use.w E_LOWER_GENERIC_CONSTRAINT \
  "type 'String' not allowed for parameter T of Child"
check_rejects generic_constraint_trait_unknown_param.w E_LOWER_GENERIC_CONSTRAINT \
  'constraint names unknown parameter U of BrokenTrait'
check_rejects generic_constraint_parent_cycle.w E_LOWER_GENERIC_CONSTRAINT \
  'cyclic generic parent chain involving First'
check_rejects generic_constraint_nongeneric_parent.w E_LOWER_GENERIC_CONSTRAINT \
  'parent Parent of Broken is not a generic template'

printf 'generic constraint definition checks: PASS\n'
