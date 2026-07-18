#!/bin/bash
# Compile and time each builtin microbenchmark in this directory.
#
# Usage: benchmarks/builtins/run.sh [output.tsv] [name-filter...]
#   output.tsv    optional file to append "name<TAB>ns_per_op<TAB>checksum" rows
#   name-filter   optional bench names (without .w) to run; default: all
#
# Each bench prints "name <ns/op> <checksum>". Best of 3 runs is reported.
# Run from anywhere; compiles happen from the repo root.
set -u
cd "$(dirname "$0")/../.."
BENCH_DIR=benchmarks/builtins
OUT="${1:-}"
shift 2>/dev/null || true
FILTERS=("$@")
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

for src in "$BENCH_DIR"/*.w; do
  name=$(basename "$src" .w)
  if [ ${#FILTERS[@]} -gt 0 ]; then
    keep=0
    for f in "${FILTERS[@]}"; do [ "$f" = "$name" ] && keep=1; done
    [ $keep -eq 1 ] || continue
  fi
  exe="$WORK_DIR/$name"
  if ! bin/tungsten -o "$exe" "$src" >/dev/null 2>&1; then
    echo -e "$name\tCOMPILE_FAIL\t-"
    continue
  fi
  best=""
  check="-"
  for r in 1 2 3; do
    line=$("$exe") || { best="RUN_FAIL"; break; }
    ns=$(echo "$line" | awk '{print $2}')
    check=$(echo "$line" | awk '{print $3}')
    if [ -z "$best" ] || awk "BEGIN{exit !($ns < $best)}"; then best=$ns; fi
  done
  echo -e "$name\t$best\t$check"
  [ -n "$OUT" ] && echo -e "$name\t$best\t$check" >> "$OUT"
done
