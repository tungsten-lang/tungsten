#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TUNGSTEN="$ROOT/bin/tungsten"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-lint-contracts.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT INT TERM

GOOD="$TMP/good.w"
HYGIENE="$TMP/hygiene.w"
INVALID="$TMP/invalid.w"

printf '%s\n' '<< "a tab in a string is fine: \t"' >"$GOOD"
printf '%s\n\t%s  \n%s' '-> emit' '<< "ok"' 'emit()' >"$HYGIENE"
printf '%s\n' 'camelCase = 1' >"$INVALID"

"$TUNGSTEN" lint --help >"$TMP/help.out"
grep -q '^Usage: tungsten lint \[options\]' "$TMP/help.out"
"$TUNGSTEN" explain LINT_TRAILING_WHITESPACE >"$TMP/explain.out"
grep -q '^LINT_TRAILING_WHITESPACE$' "$TMP/explain.out"

"$TUNGSTEN" lint "$GOOD" >"$TMP/good.out"
[[ ! -s "$TMP/good.out" ]]

before="$(cksum "$HYGIENE")"
"$TUNGSTEN" lint --json "$HYGIENE" >"$TMP/warnings.jsonl"
after="$(cksum "$HYGIENE")"
[[ "$before" == "$after" ]]

ruby -rjson -e '
  rows = File.readlines(ARGV.fetch(0), chomp: true).reject(&:empty?).map { |line| JSON.parse(line) }
  codes = rows.map { |row| row.fetch("code") }
  expected = %w[LINT_TAB_INDENT LINT_TRAILING_WHITESPACE LINT_FINAL_NEWLINE]
  abort "unexpected lint codes: #{codes.inspect}" unless codes == expected
  abort "warnings were not warnings" unless rows.all? { |row| row["severity"] == "warning" }
  abort "missing stable locations" unless rows.all? { |row| row["file"] && row["row"] && row["col"] }
' "$TMP/warnings.jsonl"

set +e
"$TUNGSTEN" lint --json --warnings-as-errors "$HYGIENE" >"$TMP/errors.jsonl"
warning_status=$?
set -e
[[ "$warning_status" -eq 1 ]]
ruby -rjson -e '
  rows = File.readlines(ARGV.fetch(0), chomp: true).reject(&:empty?).map { |line| JSON.parse(line) }
  abort "warnings were not promoted" unless rows.all? { |row| row["severity"] == "error" }
' "$TMP/errors.jsonl"

TUNGSTEN_LINT_SEVERITIES=LINT_TAB_INDENT=error \
  "$TUNGSTEN" lint --json \
    --severity LINT_TAB_INDENT=off \
    --severity LINT_TRAILING_WHITESPACE=off \
    --severity LINT_FINAL_NEWLINE=off \
    "$HYGIENE" >"$TMP/overrides.jsonl"
[[ ! -s "$TMP/overrides.jsonl" ]]

set +e
"$TUNGSTEN" lint --json "$INVALID" >"$TMP/compiler.jsonl"
compiler_status=$?
set -e
[[ "$compiler_status" -eq 1 ]]
ruby -rjson -e '
  rows = File.readlines(ARGV.fetch(0), chomp: true).reject(&:empty?).map { |line| JSON.parse(line) }
  abort "missing compiler diagnostic" unless rows.any? { |row| row["code"] == "E_LEX_INVALID_IDENTIFIER" }
' "$TMP/compiler.jsonl"

set +e
"$TUNGSTEN" lint --severity NO_SUCH_CODE=error "$GOOD" >"$TMP/usage.out" 2>&1
usage_status=$?
set -e
[[ "$usage_status" -eq 2 ]]
grep -q "unknown lint code 'NO_SUCH_CODE'" "$TMP/usage.out"

printf 'lint contracts: ok\n'
