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
    "$compiler" "$root/compiler/tungsten.w" "$@"
}

# Exit status and script arguments (including embedded spaces) survive the
# compile-and-exec round trip.
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

# Runtime errors in `-e` report "(eval)", never the materialized cache path.
set +e
run_compiler -e 'raise "wire eval label"' >"$tmp/label.out" 2>"$tmp/label.err"
label_status=$?
set -e
[[ "$label_status" -eq 1 ]]
grep -q '(eval)' "$tmp/label.err"
if grep -q 'cache/run/eval-' "$tmp/label.err"; then
  echo "eval diagnostics leak the materialized cache path:" >&2
  cat "$tmp/label.err" >&2
  exit 1
fi

# Two concurrent runs of the same script must both succeed: builds are
# serialized by the run lock and published by rename, so neither invocation
# can truncate a binary the other is executing.
run_compiler run "$root/compiler/test/fixtures/run_wire_contract.w" -- prime prime >/dev/null 2>&1 || true
set +e
run_compiler run "$root/compiler/test/fixtures/run_wire_contract.w" -- one "first copy" >"$tmp/conc1.out" 2>"$tmp/conc1.err" &
pid1=$!
run_compiler run "$root/compiler/test/fixtures/run_wire_contract.w" -- two "second copy" >"$tmp/conc2.out" 2>"$tmp/conc2.err" &
pid2=$!
wait "$pid1"; conc1=$?
wait "$pid2"; conc2=$?
set -e
[[ "$conc1" -eq 7 ]]
[[ "$conc2" -eq 7 ]]
printf '2\none\nfirst copy\n' >"$tmp/conc1.expected"
printf '2\ntwo\nsecond copy\n' >"$tmp/conc2.expected"
cmp "$tmp/conc1.expected" "$tmp/conc1.out"
cmp "$tmp/conc2.expected" "$tmp/conc2.out"

echo "WIRE run: PASS"
