#!/bin/bash
# Fan out one compiled searcher binary across N walkers (distinct RNG bases),
# one log per walker. Blocks until all walkers finish.
#   fleet.sh <binary> <nwalkers> <outdir> [base_offset]
set -euo pipefail
BIN="$1"; N="$2"; OUT="$3"; OFF="${4:-0}"
mkdir -p "$OUT"
NAME=$(basename "$BIN")
for b in $(seq 1 "$N"); do
  "$BIN" $((b + OFF)) > "$OUT/${NAME}_$((b + OFF)).out" &
done
wait
grep -h "DONE" "$OUT/${NAME}"_*.out | sort -t= -k2 -n | head -3
