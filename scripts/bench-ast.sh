#!/bin/bash
# bench-ast.sh — AST performance regression tracker (EXP-1 perf lab).
#
# Runs the slab-AST micro-benchmarks (runtime/bench_node), compares the
# result against a recorded baseline, and WARNS (does not block) on a
# regression beyond the threshold. Every roadmap task runs this to get a
# real before/after number.
#
#   scripts/bench-ast.sh                  compare current run vs baseline
#   scripts/bench-ast.sh --save-baseline  record the current run as baseline
#
# The first run with no baseline records one automatically.
# Run from anywhere; the script cd's to the repo root.

set -euo pipefail
cd "$(dirname "$0")/.."

BASELINE="build/cache/bench-ast-baseline.txt"
THRESHOLD=5   # percent; >5% regression warns

mkdir -p build/cache

echo "Building bench_node..."
make -C runtime bench_node >/dev/null 2>&1

echo "Running bench_node..."
OUT=$(runtime/bench_node)
echo "$OUT"

# Pull "<value> <unit>" out of a named line. grep-miss is non-fatal.
extract() {
  echo "$OUT" | { grep -F "$1" || true; } \
    | awk -v u="$2" '{ for (i = 1; i <= NF; i++) if ($i == u) { print $(i-1); exit } }'
}

cur_alloc=$(extract "node_alloc" "ops/s")
cur_inline=$(extract "inline-payload create" "ops/s")
cur_singleton=$(extract "singleton create" "ops/s")
cur_field=$(extract "field store+load" "ops/s")
cur_reset=$(extract "reset+init" "ops/s")
cur_peak_kb=$(extract "TOTAL" "KB")

write_baseline() {
  {
    echo "alloc=$cur_alloc"
    echo "inline=$cur_inline"
    echo "singleton=$cur_singleton"
    echo "field=$cur_field"
    echo "reset=$cur_reset"
    echo "peak_kb=$cur_peak_kb"
  } > "$BASELINE"
}

if [ "${1:-}" = "--save-baseline" ] || [ ! -f "$BASELINE" ]; then
  write_baseline
  echo ""
  echo "Baseline recorded -> $BASELINE"
  exit 0
fi

# Load the baseline as shell vars (alloc_sc2=..., field=..., etc.).
. "$BASELINE"

WARNED=0

# compare <metric> <higher|lower> <current> <baseline>
#   higher: ops/s — a drop beyond THRESHOLD% is a regression
#   lower:  memory — a rise beyond THRESHOLD% is a regression
compare() {
  metric=$1; dir=$2; cur=$3; base=$4
  if [ -z "$base" ] || [ -z "$cur" ]; then
    echo "  --    $metric: incomplete data"
    return
  fi
  pct=$(awk -v c="$cur" -v b="$base" \
    'BEGIN { if (b + 0 == 0) print "0.0"; else printf "%.1f", (c - b) / b * 100 }')
  bad=$(awk -v p="$pct" -v t="$THRESHOLD" -v d="$dir" \
    'BEGIN { if (d == "higher") print (p < -t) ? 1 : 0; else print (p > t) ? 1 : 0 }')
  if [ "$bad" = 1 ]; then
    echo "  WARN  $metric: ${pct}%  (regressed beyond ${THRESHOLD}%)"
    WARNED=1
  else
    echo "  ok    $metric: ${pct}%"
  fi
}

echo ""
echo "vs baseline ($BASELINE):"
compare alloc     higher "$cur_alloc"     "${alloc:-}"
compare inline    higher "$cur_inline"    "${inline:-}"
compare singleton higher "$cur_singleton" "${singleton:-}"
compare field     higher "$cur_field"     "${field:-}"
compare reset     higher "$cur_reset"     "${reset:-}"
compare peak_kb   lower  "$cur_peak_kb"   "${peak_kb:-}"

echo ""
if [ "$WARNED" = 1 ]; then
  echo "bench-ast: regressions flagged above (warning only — does not block)."
else
  echo "bench-ast: no regression beyond ${THRESHOLD}%."
fi
exit 0
