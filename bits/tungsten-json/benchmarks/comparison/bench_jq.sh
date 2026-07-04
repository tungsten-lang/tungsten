#!/bin/bash
# Benchmark jq against our SIMD classifier on the same JSON file.
#
# IMPORTANT CAVEAT: jq is a parse + filter + re-serialize tool, not a
# tokenizer. The numbers below measure two different workloads:
#
#   - jq:  parses JSON → builds internal value tree → walks tree under
#          the filter expression → serializes result back to JSON text
#          → writes to stdout.
#   - simdjson stage 1 / Tungsten SIMD classifier: tokenize source bytes
#          into a structural-offsets array. No value tree, no filter,
#          no serialization.
#
# This means jq is doing 3-5× more work than the tokenizers it's being
# compared against. The point of including it is to show "where does
# the most popular CLI JSON tool sit on the same chart" — not to claim
# the tokenizers are 100× faster than jq in practice.
#
# Usage: bench_jq.sh [file.json] [rounds]

FILE="${1:-/tmp/big.json}"
ROUNDS="${2:-5}"

if [ ! -f "$FILE" ]; then
    echo "error: file not found: $FILE" >&2
    exit 1
fi

BYTES=$(stat -f%z "$FILE" 2>/dev/null || stat -c%s "$FILE")
echo "Benchmarking on $FILE ($BYTES bytes), $ROUNDS rounds"
echo

run_bench() {
    local label="$1"
    shift
    local cmd="$@"
    local start_ns=$(date +%s%N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1e9))')
    for ((i=0; i<ROUNDS; i++)); do
        eval "$cmd" > /dev/null
    done
    local end_ns=$(date +%s%N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1e9))')
    local elapsed_ms=$(( (end_ns - start_ns) / 1000000 ))
    if [ "$elapsed_ms" -lt 1 ]; then elapsed_ms=1; fi
    local mb_per_sec=$(( BYTES * ROUNDS * 1000 / elapsed_ms / 1000000 ))
    printf "  %-40s %6d ms  %6d MB/s\n" "$label" "$elapsed_ms" "$mb_per_sec"
}

# jq with the noop filter: parse + re-serialize, single thread
run_bench "jq '.' (parse + reserialize)"        "jq -c '.' < '$FILE'"

# jq with structural-only output: parse + walk
run_bench "jq 'paths|length' (count keys)"      "jq -c 'paths | length' < '$FILE'"

# Reference: cat (memory bandwidth ceiling)
run_bench "cat (memory bandwidth ceiling)"      "cat '$FILE'"
