#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
compiler="${TUNGSTEN_TEST_COMPILER:-$root/implementations/c/build/tungsten-c}"
if [[ ! -x "$compiler" ]]; then
  echo "missing compiler runtime: $compiler" >&2
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

run_compiler() {
  TUNGSTEN_ROOT="$root" \
  TUNGSTEN_C_FAST_PARSE=0 \
  TUNGSTEN_MARCH_ARGS="${TUNGSTEN_MARCH_ARGS:--mcpu=apple-m5}" \
    "$compiler" "$root/compiler/tungsten.w" "$@"
}

set +e
run_compiler run "$root/compiler/test/fixtures/run_wire_contract.w" -- alpha "two words" >"$tmp/run.out" 2>"$tmp/run.err"
status=$?
set -e
[[ "$status" -eq 7 ]]
printf '2\nalpha\ntwo words\n' >"$tmp/run.expected"
cmp "$tmp/run.expected" "$tmp/run.out"

run_compiler -e '<< 6 * 7' >"$tmp/eval.out" 2>"$tmp/eval.err"
printf '42\n' >"$tmp/eval.expected"
cmp "$tmp/eval.expected" "$tmp/eval.out"

echo "WIRE run: PASS"
