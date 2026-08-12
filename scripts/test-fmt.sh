#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TUNGSTEN="$ROOT/bin/tungsten"
INPUT="$ROOT/spec/cli/fmt_input.w"
EXPECTED="$ROOT/spec/cli/fmt_expected.w"
ON_GUARD_INPUT="$ROOT/spec/cli/fmt_on_guard_input.w"
ON_GUARD_EXPECTED="$ROOT/spec/cli/fmt_on_guard_expected.w"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-fmt.XXXXXX")"
trap 'rc=$?; rm -rf "$TMP"; exit $rc' EXIT INT TERM

"$TUNGSTEN" fmt --help >"$TMP/help.out"
grep -q '^Usage: tungsten fmt \[-w\] <file\.w \.\.\.>$' "$TMP/help.out"

if "$TUNGSTEN" fmt >"$TMP/no-files.out" 2>&1; then
  printf 'tungsten fmt accepted an empty file list\n' >&2
  exit 1
fi
grep -q '^Usage: tungsten fmt \[-w\] <file\.w \.\.\.>$' "$TMP/no-files.out"

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

"$TUNGSTEN" fmt "$ON_GUARD_INPUT" >"$TMP/on-guard.out"
cmp "$ON_GUARD_EXPECTED" "$TMP/on-guard.out"
"$TUNGSTEN" fmt "$TMP/on-guard.out" >"$TMP/on-guard-twice.out"
cmp "$TMP/on-guard.out" "$TMP/on-guard-twice.out"
"$TUNGSTEN" --canonical-ast "$ON_GUARD_INPUT" >"$TMP/on-guard.in.ast"
"$TUNGSTEN" --canonical-ast "$TMP/on-guard.out" >"$TMP/on-guard.out.ast"
cmp "$TMP/on-guard.in.ast" "$TMP/on-guard.out.ast"

printf '# retained comment   \nvalue=1   \n\n' >"$TMP/commented.w"
"$TUNGSTEN" fmt "$TMP/commented.w" >"$TMP/commented.out"
printf '# retained comment\nvalue = 1\n' >"$TMP/commented.expected"
cmp "$TMP/commented.expected" "$TMP/commented.out"
"$TUNGSTEN" fmt "$TMP/commented.out" >"$TMP/commented-twice.out"
cmp "$TMP/commented.out" "$TMP/commented-twice.out"
"$TUNGSTEN" --canonical-ast "$TMP/commented.w" >"$TMP/commented.in.ast"
"$TUNGSTEN" --canonical-ast "$TMP/commented.out" >"$TMP/commented.out.ast"
cmp "$TMP/commented.in.ast" "$TMP/commented.out.ast"

cat >"$TMP/comment-attachment.w" <<'EOF'
# file heading
if true # branch reason
  # before assignment
  value=1 # retained inline
  text="# not a comment"
# file tail
EOF
cat >"$TMP/comment-attachment.expected" <<'EOF'
# file heading
if true  # branch reason
  # before assignment
  value = 1  # retained inline
  text = "# not a comment"
# file tail
EOF
"$TUNGSTEN" fmt "$TMP/comment-attachment.w" >"$TMP/comment-attachment.out"
cmp "$TMP/comment-attachment.expected" "$TMP/comment-attachment.out"
"$TUNGSTEN" fmt "$TMP/comment-attachment.out" >"$TMP/comment-attachment-twice.out"
cmp "$TMP/comment-attachment.out" "$TMP/comment-attachment-twice.out"
"$TUNGSTEN" --canonical-ast "$TMP/comment-attachment.w" >"$TMP/comment-attachment.in.ast"
"$TUNGSTEN" --canonical-ast "$TMP/comment-attachment.out" >"$TMP/comment-attachment.out.ast"
cmp "$TMP/comment-attachment.in.ast" "$TMP/comment-attachment.out.ast"

# Grouped-expression comments remain on the explicit lossless fallback: no
# comment is lost, and formatting never risks moving an array element.
printf 'values=[\n  1, # first\n  2\n]   \n' >"$TMP/group-comment.w"
"$TUNGSTEN" fmt "$TMP/group-comment.w" >"$TMP/group-comment.out"
printf 'values=[\n  1, # first\n  2\n]\n' >"$TMP/group-comment.expected"
cmp "$TMP/group-comment.expected" "$TMP/group-comment.out"

# Packed token lengths wrap after 4095 codepoints. A hash inside a longer
# string must never be mistaken for an uncovered comment marker.
long_payload="$(printf '%04100d' 0 | tr '0' 'x')"
printf 'text="%s#inside"\n' "$long_payload" >"$TMP/long-comment-like-string.w"
"$TUNGSTEN" fmt "$TMP/long-comment-like-string.w" >"$TMP/long-comment-like-string.out"
cmp "$TMP/long-comment-like-string.w" "$TMP/long-comment-like-string.out"

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
# are classified explicitly; every other file must format idempotently and
# preserve its canonical AST.
fixture_count=0
for fixture in "$ROOT"/compiler/test/fixtures/*.w "$ROOT"/spec/cli/*.w; do
  rel="${fixture#"$ROOT"/}"
  case "$rel" in
    compiler/test/fixtures/frontend_fuzz_20add648ea927d31.w|\
    compiler/test/fixtures/frontend_fuzz_62f1c679cc3ef149.w|\
    spec/cli/camel_case_invalid.w|\
    spec/cli/str_type_invalid.w)
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
