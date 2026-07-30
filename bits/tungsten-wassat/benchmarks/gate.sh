#!/usr/bin/env bash
# The wassat pre-commit gate.
#
#   benchmarks/gate.sh <wassat-binary> [wrat-binary]
#
# Always run it against a binary built to a scratch path, NEVER over bin/ --
# concurrent agents have twice rebuilt bin/wassat into a silent no-op mid-run
# and produced fake TIMEOUTs from it.
#
# Covers the Wassat library specs, the 200-case differential in BOTH
# default and WASSAT_RAW_AT=0 modes, and php87 --proof verified by wrat.
#
# The spec check parses the "N examples: N passed, M failed" summary and
# treats a MISSING summary as failure -- a spec that dies before summarising
# must never read as green.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WASSAT_BIN="${1:?usage: gate.sh <wassat-binary> [wrat-binary]}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/wassat-gate.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten}"
WRAT_BIN="${2:-$TMP/wrat}"
cd "$ROOT"
fail=0

echo "### router tooling"
python3 bits/tungsten-wassat/benchmarks/router_tools_test.py || fail=1

echo "### smoke"
"$WASSAT_BIN" --version || { echo "FATAL: --version"; exit 2; }

if [[ ! -x "$WRAT_BIN" ]]; then
  echo "### building wrat (proof checker)"
  "$TUNGSTEN" compile bits/tungsten-wrat/bin/wrat.w --out "$WRAT_BIN" --no-lto >/dev/null || {
    echo "FATAL: wrat build failed"; exit 2; }
fi

echo
echo "### library specs"
for spec in solver cli preprocess incremental sls trim explain portfolio multiplier fermat sum_of_three_cubes mdp automata_sync ternary_affine ais coloring covering directed_kernel edge_matching sliding_puzzle stedman hantzsche_wendt knight_tour local_core latin_csp; do
  path="bits/tungsten-wassat/spec/${spec}_spec.w"
  # `solver` includes true concurrent CAS/conflict-budget regressions and SLS
  # now exercises the same native atomic cancellation ABI. Run both against
  # the compiled runtime; compiler/test/test_interpreter.w separately pins the
  # source interpreter's single-threaded mirror of those calls.
  # Everything compiles except the interpreter-only trio; a new spec added to
  # the loop above therefore defaults to the compiled engine — the safe side,
  # since only interpreter-tolerant specs belong in the exclusion list.
  case "$spec" in incremental|trim|explain) gate_compile=0 ;; *) gate_compile=1 ;; esac
  if [[ "$gate_compile" == "1" ]]; then
    if ! "$TUNGSTEN" compile "$path" --out "$TMP/gate-$spec" --no-lto >/dev/null 2>&1; then
      echo "  FAIL [$spec] compile failed"; fail=1; continue
    fi
    out="$(WASSAT_TEST_BIN="$WASSAT_BIN" "$TMP/gate-$spec" 2>&1)"; rc=$?
  else
    out="$(WASSAT_TEST_BIN="$WASSAT_BIN" "$TUNGSTEN" run "$path" 2>&1)"; rc=$?
  fi
  summary=$(printf '%s\n' "$out" | grep -E '^[0-9]+ examples:' | tail -1)
  nfail=$(printf '%s\n' "$summary" | sed -nE 's/.*, ([0-9]+) failed.*/\1/p')
  printf '  %-14s rc=%-3s %s\n' "$spec" "$rc" "${summary:-<NO SUMMARY LINE>}"
  if [[ $rc -ne 0 || -z "$summary" || "${nfail:-1}" != "0" ]]; then
    fail=1
    printf '%s\n' "$out" | grep -iE 'fail|error' | head -5 | sed 's/^/      /'
  fi
done

echo
for mode in default raw0; do
  echo "### differential, 200 cases, $mode"
  if [[ "$mode" == raw0 ]]; then extra=(env WASSAT_RAW_AT=0); else extra=(env); fi
  "${extra[@]}" WASSAT="$WASSAT_BIN" WRAT="$WRAT_BIN" CASES=200 \
    python3 bits/tungsten-wassat/benchmarks/differential.py > "$TMP/diff-$mode.log" 2>&1
  rc=$?
  echo "  rc=$rc  $(tail -2 "$TMP/diff-$mode.log" | tr '\n' ' ')"
  [[ $rc -ne 0 ]] && fail=1
done

echo
echo "### php87 --proof, verified by wrat"
PHP87="${BENCH:-/tmp/satbench}/php87.cnf"
if [[ ! -f "$PHP87" ]]; then
  echo "  SKIP: $PHP87 absent (run benchmarks/gen_instances.py)"
else
  "$WASSAT_BIN" "$PHP87" --proof "$TMP/php87.wrat" > "$TMP/php87.out" 2>&1
  rc=$?
  echo "  solve rc=$rc  $(grep '^s ' "$TMP/php87.out")"
  [[ $rc -ne 20 ]] && { echo "  FAIL: expected exit 20"; fail=1; }
  "$WRAT_BIN" "$PHP87" "$TMP/php87.wrat" > "$TMP/wrat.out" 2>&1
  rc=$?
  echo "  wrat  rc=$rc  $(tail -1 "$TMP/wrat.out")"
  [[ $rc -ne 0 ]] && fail=1
fi

echo
if [[ $fail -eq 0 ]]; then echo "GATE PASS"; else echo "GATE FAIL"; fi
exit $fail
