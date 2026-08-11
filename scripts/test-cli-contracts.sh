#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TUNGSTEN="$ROOT/bin/tungsten"
VALID="$ROOT/spec/compiler/string_buffer_dynamic_append_spec.w"
TYPED_SIGNATURE_VALID="$ROOT/spec/compiler/small_array_stack_escape_spec.w"
INVALID="$ROOT/spec/cli/check_type_error.w"
INVALID_CAMEL="$ROOT/spec/cli/camel_case_invalid.w"
EXIT_7="$ROOT/spec/cli/exit_7.w"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-cli-contracts.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT INT TERM

"$TUNGSTEN" -c "$VALID" >"$TMP/check-short.out"
grep -qx '200 OK' "$TMP/check-short.out"

"$TUNGSTEN" check "$VALID" >"$TMP/check-command.out"
grep -qx '200 OK' "$TMP/check-command.out"

"$TUNGSTEN" -c "$TYPED_SIGNATURE_VALID" >"$TMP/check-typed-signature.out"
grep -qx '200 OK' "$TMP/check-typed-signature.out"

if "$TUNGSTEN" --check "$INVALID" >"$TMP/check-error.out" 2>&1; then
  printf 'tungsten --check accepted a lowering error\n' >&2
  exit 1
fi
grep -q 'E_LOWER_CTOR_ARITY' "$TMP/check-error.out"

if "$TUNGSTEN" --check "$INVALID_CAMEL" >"$TMP/check-camel-error.out" 2>&1; then
  printf 'tungsten --check accepted a camelCase identifier\n' >&2
  exit 1
fi
grep -q 'E_LEX_INVALID_IDENTIFIER' "$TMP/check-camel-error.out"
grep -q "uppercase ASCII is not valid in identifiers: 'camelCase'" "$TMP/check-camel-error.out"

for spelling in _camelCase @camelCase @@camelCase '$camelCase'; do
  if "$TUNGSTEN" --check -e "$spelling = 1" >"$TMP/check-camel-variant.out" 2>&1; then
    printf 'tungsten --check accepted invalid identifier %s\n' "$spelling" >&2
    exit 1
  fi
  grep -q 'E_LEX_INVALID_IDENTIFIER' "$TMP/check-camel-variant.out"
  grep -Fq "uppercase ASCII is not valid in identifiers: '$spelling'" "$TMP/check-camel-variant.out"
done

set +e
"$TUNGSTEN" run "$EXIT_7" >"$TMP/run.out" 2>&1
run_status=$?
set -e
if [[ "$run_status" -ne 7 ]]; then
  printf 'tungsten run collapsed exit 7 to %s\n' "$run_status" >&2
  cat "$TMP/run.out" >&2
  exit 1
fi

"$TUNGSTEN" explain E_PARSE_UNEXPECTED_TOKEN >"$TMP/explain.out"
grep -q '^E_PARSE_UNEXPECTED_TOKEN$' "$TMP/explain.out"
if "$TUNGSTEN" explain NO_SUCH_CODE >"$TMP/explain-missing.out" 2>&1; then
  printf 'tungsten explain accepted an unknown code\n' >&2
  exit 1
fi

printf 'CLI check, explain, and exit-status contracts: ok\n'
