#!/usr/bin/env bash
# Balanced in-process benchmark for w_method_call_cached_0.  Production keeps
# the narrow ABI only if both source and native cache shapes avoid regression.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten}"
RUNS="${RUNS:-10}"
ITERS="${ITERS:-50000000}"
GATE="${GATE:-0.97}"
ONLY="${ONLY:-}"

case "$RUNS" in
  ''|*[!0-9]*|0) echo "RUNS must be a positive even integer" >&2; exit 2 ;;
esac
if [ $((RUNS % 2)) -ne 0 ]; then
  echo "RUNS must be even so ABBA and BAAB orientations balance" >&2
  exit 2
fi
case "$ITERS" in
  ''|*[!0-9]*|0) echo "ITERS must be a positive integer" >&2; exit 2 ;;
esac
case "$ONLY" in
  ''|source0|native0) ;;
  *) echo "ONLY must be source0 or native0" >&2; exit 2 ;;
esac

TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-zero-arg-dispatch.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/zero-arg-dispatch-ab"
RAW="$TMP/results.txt"

cd "$ROOT"
echo "Compiling benchmark (setup; excluded from timings)..."
TUNGSTEN_C_INCLUDES="$SCRIPT_DIR/zero_arg_dispatch_ab.c" \
  "$TUNGSTEN" compile "$SCRIPT_DIR/zero_arg_dispatch_ab.w" \
  --release --out "$BIN" >/dev/null

echo "Checking exact generic/specialized behavior..."
"$BIN" check

echo "Running $RUNS balanced samples x $ITERS calls per measurement${ONLY:+ ($ONLY only)}..."
: > "$RAW"
i=1
while [ "$i" -le "$RUNS" ]; do
  parity=$(( (i - 1) % 2 ))
  echo "  sample $i/$RUNS (parity $parity)" >&2
  "$BIN" bench "$ITERS" "$parity" "$ONLY" >> "$RAW"
  i=$((i + 1))
done

median_stream() {
  sort -n | awk '
    { v[NR] = $1 }
    END {
      if (NR == 0) exit 1
      if (NR % 2) print v[(NR + 1) / 2]
      else print (v[NR / 2] + v[NR / 2 + 1]) / 2
    }
  '
}

if [ -n "$ONLY" ]; then
  targets=("$ONLY")
else
  targets=(source0 native0)
fi

echo
printf '%-10s %12s %12s %10s %8s\n' target 'generic ns' 'argc-0 ns' ratio gate
for target in "${targets[@]}"; do
  generic_med="$(awk -F'|' -v target="$target" '$1=="RESULT" && $2==target {print $3}' "$RAW" | median_stream)"
  zero_med="$(awk -F'|' -v target="$target" '$1=="RESULT" && $2==target {print $4}' "$RAW" | median_stream)"
  ratio_med="$(awk -F'|' -v target="$target" '$1=="RESULT" && $2==target {print $5}' "$RAW" | median_stream)"
  decision="$(awk -v ratio="$ratio_med" -v gate="$GATE" 'BEGIN {print (ratio <= gate) ? "PASS" : "SKIP"}')"
  printf '%-10s %12.3f %12.3f %10.3f %8s\n' \
    "$target" "$generic_med" "$zero_med" "$ratio_med" "$decision"
done

echo "Retention requires every target to avoid regression, source0 to clear $GATE, and an independent repeat below 1.00."
