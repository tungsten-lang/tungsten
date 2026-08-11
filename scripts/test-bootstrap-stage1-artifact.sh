#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-bootstrap-artifact.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

. "$ROOT/bin/commands/bootstrap_helpers.sh"

log_path="$TMP/stage1.log"
printf 'compiler claimed success\n' > "$log_path"

set +e
output="$(bootstrap_require_executable \
  "$TMP/missing-stage1" "$log_path" "stage 1 (C VM)" 2>&1)"
status=$?
set -e

if [ "$status" -eq 0 ]; then
  printf 'FAIL: missing stage-1 executable was accepted\n' >&2
  exit 1
fi
if ! grep -Fq 'compiler claimed success' <<<"$output"; then
  printf 'FAIL: stage-1 log was not shown\n%s\n' "$output" >&2
  exit 1
fi
if ! grep -Fq 'returned success but produced no executable' <<<"$output"; then
  printf 'FAIL: missing-artifact diagnosis was not shown\n%s\n' "$output" >&2
  exit 1
fi

stage1="$TMP/stage1"
printf '#!/usr/bin/env bash\nexit 0\n' > "$stage1"
chmod 755 "$stage1"
bootstrap_require_executable "$stage1" "$log_path" "stage 1 (C VM)"

source_tree="$TMP/source-tree"
compiler_w="$source_tree/compiler/tungsten.w"
lex64_table="$source_tree/languages/tungsten/tungsten.lex64"
mkdir -p \
  "$source_tree/compiler/lib" \
  "$source_tree/core/numeric" \
  "$source_tree/data" \
  "$source_tree/languages/tungsten/lexers"
printf 'compiler\n' > "$compiler_w"
printf 'lexer\n' > "$lex64_table"
printf 'compiler a\n' > "$source_tree/compiler/lib/a.w"
printf 'compiler z\n' > "$source_tree/compiler/lib/z.w"
printf 'core a\n' > "$source_tree/core/a.w"
printf 'core numeric b\n' > "$source_tree/core/numeric/b.w"
printf 'ignored\n' > "$source_tree/core/ignored.txt"
printf 'eV\n' > "$source_tree/data/unit_names.txt"
printf 'lexer helper a\n' > "$source_tree/languages/tungsten/lexers/a.w"
printf 'lexer helper z\n' > "$source_tree/languages/tungsten/lexers/z.w"

actual_inputs="$TMP/actual-inputs"
expected_inputs="$TMP/expected-inputs"
bootstrap_stage1_source_inputs \
  "$source_tree" "$compiler_w" "$lex64_table" > "$actual_inputs"
printf '%s\n' \
  "$compiler_w" \
  "$lex64_table" \
  "$source_tree/data/unit_names.txt" \
  "$source_tree/compiler/lib/a.w" \
  "$source_tree/compiler/lib/z.w" \
  "$source_tree/core/a.w" \
  "$source_tree/core/numeric/b.w" \
  "$source_tree/languages/tungsten/lexers/a.w" \
  "$source_tree/languages/tungsten/lexers/z.w" > "$expected_inputs"
if ! cmp -s "$expected_inputs" "$actual_inputs"; then
  printf 'FAIL: stage-1 source inputs are incomplete or unstable\n' >&2
  diff -u "$expected_inputs" "$actual_inputs" >&2 || true
  exit 1
fi

identity_before="$(
  bootstrap_stage1_source_manifest \
    "$source_tree" "$compiler_w" "$lex64_table"
)"
printf 'core a changed\n' > "$source_tree/core/a.w"
identity_after="$(
  bootstrap_stage1_source_manifest \
    "$source_tree" "$compiler_w" "$lex64_table"
)"
if [ "$identity_before" = "$identity_after" ]; then
  printf 'FAIL: a core source edit did not change stage-1 source identity\n' >&2
  exit 1
fi

printf 'lexer helper a changed\n' \
  > "$source_tree/languages/tungsten/lexers/a.w"
identity_after_lexer_change="$(
  bootstrap_stage1_source_manifest \
    "$source_tree" "$compiler_w" "$lex64_table"
)"
if [ "$identity_after" = "$identity_after_lexer_change" ]; then
  printf 'FAIL: a lexer helper edit did not change stage-1 source identity\n' >&2
  exit 1
fi

printf 'mmHg\n' >> "$source_tree/data/unit_names.txt"
identity_after_unit_change="$(
  bootstrap_stage1_source_manifest \
    "$source_tree" "$compiler_w" "$lex64_table"
)"
if [ "$identity_after_lexer_change" = "$identity_after_unit_change" ]; then
  printf 'FAIL: a unit-name registry edit did not change stage-1 source identity\n' >&2
  exit 1
fi

if ! grep -Fq 'bootstrap_stage1_source_manifest' \
  "$ROOT/bin/commands/bootstrap.sh"; then
  printf 'FAIL: bootstrap does not use the stage-1 source-input contract\n' >&2
  exit 1
fi

printf 'bootstrap stage-1 artifact and source-cache contracts: ok\n'
