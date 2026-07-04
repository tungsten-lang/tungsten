#!/bin/bash
# Slab-AST perf bench: builds the compiler with -O2 once, then times
# `tungsten-compiler --emit-ll` against tungsten.w (5 trims-after-first
# samples). Prints median in ms.
#
# Run from repo root: scripts/bench-slab-ast.sh

set -euo pipefail

cd "$(dirname "$0")/.."

if [ ! -x bin/tungsten-compiler ] || [ "${1:-}" = "--rebuild" ]; then
  echo "Building --release compiler (-O3 -flto=full -march=native -mtune=native)..."
  bin/tungsten build --release --force > /dev/null 2>&1
fi

echo "Timing emit-ll on tungsten.w (6 runs, dropping cold start)..."
SAMPLES=()
for i in 1 2 3 4 5 6; do
  START=$(date +%s%N)
  ./bin/tungsten-compiler compile compiler/tungsten.w --emit-ll --out /tmp/bench-slab-ast.ll --release 2>/dev/null
  END=$(date +%s%N)
  MS=$(( (END-START)/1000000 ))
  SAMPLES+=($MS)
  echo "  run $i: ${MS}ms"
done

# Drop first sample, sort remaining 5, take middle (median).
IFS=$'\n' SORTED=($(sort -n <<<"${SAMPLES[*]:1}"))
unset IFS
MEDIAN=${SORTED[2]}
echo "median (of 5): ${MEDIAN}ms"
