#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TUNGSTEN="$ROOT/bin/tungsten"
INPUT="$ROOT/spec/cli/fmt_input.w"
EXPECTED="$ROOT/spec/cli/fmt_expected.w"
UNSUPPORTED="$ROOT/spec/cli/fmt_unsupported.w"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-fmt.XXXXXX")"
trap 'rc=$?; rm -rf "$TMP"; exit $rc' EXIT INT TERM

"$TUNGSTEN" fmt "$INPUT" >"$TMP/once.w"
cmp "$EXPECTED" "$TMP/once.w"

"$TUNGSTEN" fmt "$TMP/once.w" >"$TMP/twice.w"
cmp "$TMP/once.w" "$TMP/twice.w"

"$TUNGSTEN" --canonical-ast "$INPUT" >"$TMP/input.ast"
"$TUNGSTEN" --canonical-ast "$TMP/once.w" >"$TMP/output.ast"
cmp "$TMP/input.ast" "$TMP/output.ast"

cp "$INPUT" "$TMP/in-place.w"
"$TUNGSTEN" fmt -w "$TMP/in-place.w" >"$TMP/in-place.out"
cmp "$EXPECTED" "$TMP/in-place.w"
grep -q '^formatted ' "$TMP/in-place.out"

if "$TUNGSTEN" fmt "$UNSUPPORTED" >"$TMP/unsupported.out" 2>"$TMP/unsupported.err"; then
  printf 'tungsten fmt accepted an unsupported AST node\n' >&2
  exit 1
fi
grep -q 'unsupported expression node :currency' "$TMP/unsupported.err"

printf '# retained comment   \nvalue=1   \n\n' >"$TMP/commented.w"
"$TUNGSTEN" fmt "$TMP/commented.w" >"$TMP/commented.out"
printf '# retained comment\nvalue=1\n' >"$TMP/commented.expected"
cmp "$TMP/commented.expected" "$TMP/commented.out"

printf 'value=Tensor<f64, m/s>.zeros([1])   \n' >"$TMP/generic.w"
"$TUNGSTEN" fmt "$TMP/generic.w" >"$TMP/generic.out"
printf 'value = Tensor<f64, m/s>.zeros([1])\n' >"$TMP/generic.expected"
cmp "$TMP/generic.expected" "$TMP/generic.out"

"$TUNGSTEN" fmt "$ROOT/spec/cli/fmt_generic_input.w" >"$TMP/generic-class.out"
cmp "$ROOT/spec/cli/fmt_generic_expected.w" "$TMP/generic-class.out"
"$TUNGSTEN" --canonical-ast "$ROOT/spec/cli/fmt_generic_input.w" >"$TMP/generic-class.in.ast"
"$TUNGSTEN" --canonical-ast "$TMP/generic-class.out" >"$TMP/generic-class.out.ast"
cmp "$TMP/generic-class.in.ast" "$TMP/generic-class.out.ast"

# Exercise the compact frontend fixture corpus. Known-invalid parser fixtures
# and the two intentionally unsupported formatter fixtures are classified
# explicitly; every other file must format idempotently and preserve its
# canonical AST.
fixture_count=0
for fixture in "$ROOT"/compiler/test/fixtures/*.w "$ROOT"/spec/cli/*.w; do
  rel="${fixture#"$ROOT"/}"
  case "$rel" in
    compiler/test/fixtures/frontend_fuzz_20add648ea927d31.w|\
    compiler/test/fixtures/frontend_fuzz_62f1c679cc3ef149.w|\
    spec/cli/camel_case_invalid.w|\
    spec/cli/str_type_invalid.w|\
    spec/cli/fmt_unsupported.w|\
    spec/cli/gpu_check_multiple_errors.w)
      continue
      ;;
  esac
  fixture_count=$((fixture_count + 1))
  "$TUNGSTEN" fmt "$fixture" >"$TMP/corpus-$fixture_count.w"
  "$TUNGSTEN" fmt "$TMP/corpus-$fixture_count.w" >"$TMP/corpus-$fixture_count-twice.w"
  cmp "$TMP/corpus-$fixture_count.w" "$TMP/corpus-$fixture_count-twice.w"
  "$TUNGSTEN" --canonical-ast "$fixture" >"$TMP/corpus-$fixture_count.in.ast"
  "$TUNGSTEN" --canonical-ast "$TMP/corpus-$fixture_count.w" >"$TMP/corpus-$fixture_count.out.ast"
  cmp "$TMP/corpus-$fixture_count.in.ast" "$TMP/corpus-$fixture_count.out.ast"
done
[[ "$fixture_count" -ge 60 ]]

printf 'fmt contracts: PASS (%s corpus fixtures)\n' "$fixture_count"
