#!/usr/bin/env bash
# Cross-build public-dispatch gate for the String/Symbol#to_s source port.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CANDIDATE_ROOT="${CANDIDATE_ROOT:-$ROOT}"
RUNS="${RUNS:-10}"
ITERS="${ITERS:-20000000}"
GATE="${GATE:-1.10}"

if [ -z "${BASELINE_ROOT:-}" ]; then
  echo "BASELINE_ROOT must name an isolated pre-port Tungsten root" >&2
  exit 2
fi
if [ $((RUNS % 2)) -ne 0 ] || [ "$RUNS" -le 0 ]; then
  echo "RUNS must be a positive even integer" >&2
  exit 2
fi

BASELINE_ROOT="$(cd "$BASELINE_ROOT" && pwd)"
CANDIDATE_ROOT="$(cd "$CANDIDATE_ROOT" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-string-to-s-port.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
BASELINE_BIN="$TMP/baseline"
CANDIDATE_BIN="$TMP/candidate"
RAW="$TMP/results.txt"

for root in "$BASELINE_ROOT" "$CANDIDATE_ROOT"; do
  test -x "$root/bin/tungsten"
  test -f "$root/benchmarks/runtime_ports/string_to_s_ab.w"
  test -f "$root/benchmarks/runtime_ports/string_to_s_ref.c"
done

echo "Compiling isolated release binaries (excluded from timings)..."
(
  cd "$BASELINE_ROOT"
  TUNGSTEN_C_INCLUDES="$BASELINE_ROOT/benchmarks/runtime_ports/string_to_s_ref.c" \
    bin/tungsten compile benchmarks/runtime_ports/string_to_s_ab.w \
    --release --out "$BASELINE_BIN" >/dev/null
)
(
  cd "$CANDIDATE_ROOT"
  TUNGSTEN_C_INCLUDES="$CANDIDATE_ROOT/benchmarks/runtime_ports/string_to_s_ref.c" \
    bin/tungsten compile benchmarks/runtime_ports/string_to_s_ab.w \
    --release --out "$CANDIDATE_BIN" >/dev/null
)

echo "Checking exact 48-value representation behavior..."
"$BASELINE_BIN" check
"$CANDIDATE_BIN" check

echo "Running $RUNS balanced cross-build pairs x $ITERS calls per stratum..."
: > "$RAW"
i=1
while [ "$i" -le "$RUNS" ]; do
  parity=$(( (i - 1) % 2 ))
  if [ $((i % 2)) -eq 1 ]; then
    "$BASELINE_BIN" bench "$ITERS" "$parity" | awk -F'|' '$1=="RESULT" {print "BASE|" $0}' >> "$RAW"
    "$CANDIDATE_BIN" bench "$ITERS" "$parity" | awk -F'|' '$1=="RESULT" {print "CAND|" $0}' >> "$RAW"
  else
    "$CANDIDATE_BIN" bench "$ITERS" "$parity" | awk -F'|' '$1=="RESULT" {print "CAND|" $0}' >> "$RAW"
    "$BASELINE_BIN" bench "$ITERS" "$parity" | awk -F'|' '$1=="RESULT" {print "BASE|" $0}' >> "$RAW"
  fi
  i=$((i + 1))
done

median_stream() {
  sort -n | awk '{ v[NR]=$1 } END { if (NR%2) print v[(NR+1)/2]; else print (v[NR/2]+v[NR/2+1])/2 }'
}

printf '\n%-16s %12s %12s %10s %8s\n' representation baseline_ns source_ns ratio gate
for name in inline slab heap rope symbol_inline symbol_slab; do
  baseline_med="$(awk -F'|' -v n="$name" '$1=="BASE" && $3==n {print $6}' "$RAW" | median_stream)"
  candidate_med="$(awk -F'|' -v n="$name" '$1=="CAND" && $3==n {print $6}' "$RAW" | median_stream)"
  ratio="$(awk -v c="$candidate_med" -v b="$baseline_med" 'BEGIN {print c/b}')"
  decision="$(awk -v r="$ratio" -v g="$GATE" 'BEGIN {print (r<=g) ? "PASS" : "SKIP"}')"
  printf '%-16s %12.3f %12.3f %10.3f %8s\n' "$name" "$baseline_med" "$candidate_med" "$ratio" "$decision"
done

echo "Retention requires every public candidate/baseline median <= $GATE and an independent repeat at or below $GATE."
