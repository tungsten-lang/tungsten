#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten-compiler}"
COUNT="${COUNT:-150}"
RUNS="${RUNS:-5}"
PROGRAM="${PROGRAM:-compiler/test/fixtures/core_abi_stable_b.w}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-core-cache-bench.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/src"
sources=()
i=0
while [[ $i -lt $COUNT ]]; do
  path="$TMP/src/program_$(printf '%03d' "$i").w"
  cp "$PROGRAM" "$path"
  sources+=("$path")
  i=$((i + 1))
done

flags=(--emit-ll --ll --release --native --fast --no-debug)
off_times=()
on_times=()

run_once() {
  local mode="$1"
  local started finished elapsed
  started="$(ruby -e 'puts Process.clock_gettime(Process::CLOCK_MONOTONIC)')"
  TUNGSTEN_CORE_LOWER_CACHE="$mode" \
    "$TUNGSTEN" compile-batch --jobs 1 "${sources[@]}" "${flags[@]}" \
    >/dev/null 2>&1
  finished="$(ruby -e 'puts Process.clock_gettime(Process::CLOCK_MONOTONIC)')"
  elapsed="$(ruby -e 'printf "%.3f", ARGV[1].to_f - ARGV[0].to_f' "$started" "$finished")"
  echo "$elapsed"
}

pair=1
while [[ $pair -le $RUNS ]]; do
  if (( pair % 2 == 1 )); then
    off="$(run_once 0)"
    on="$(run_once 1)"
  else
    on="$(run_once 1)"
    off="$(run_once 0)"
  fi
  off_times+=("$off")
  on_times+=("$on")
  echo "pair $pair: cache-off=${off}s cache-on=${on}s"
  pair=$((pair + 1))
done

median() {
  printf '%s\n' "$@" | sort -n | awk '
    { values[NR] = $1 }
    END {
      if (NR % 2) print values[(NR + 1) / 2]
      else printf "%.3f\n", (values[NR / 2] + values[NR / 2 + 1]) / 2
    }'
}

off_median="$(median "${off_times[@]}")"
on_median="$(median "${on_times[@]}")"
awk -v off="$off_median" -v on="$on_median" -v count="$COUNT" '
  BEGIN {
    printf "median (%d programs): cache-off=%.3fs cache-on=%.3fs improvement=%.2f%% speedup=%.3fx\n",
      count, off, on, (off - on) * 100.0 / off, off / on
  }'
