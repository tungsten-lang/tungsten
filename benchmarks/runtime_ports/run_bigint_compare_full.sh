#!/usr/bin/env bash
# Same-binary full BigInt comparison source/C gate. Each pair balances
# C/W/W/C with W/C/C/W and reports the median paired source/C ratio.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten}"
PAIRS="${PAIRS:-8}"
MAX_RATIO="${MAX_RATIO:-1.10}"
LABEL="${LABEL:-current}"
OUT="${OUT:-/tmp/tungsten-bigint-compare-${LABEL}.txt}"
JSON_OUT="${JSON_OUT:-${OUT%.txt}.json}"
ROWS="${ROWS:-width-1:10000000 width-2:8000000 width-3:7000000 width-4:6000000 width-8:5000000 width-16:4000000 width-24:3500000 width-32:3000000 width-40:2500000 width-48:2200000 width-64:1800000 width-128:1000000 width-256:600000 width-384:400000 width-448:350000 width-512:300000 width-1024:160000 width-2048:80000 width-4096:40000 width-8192:20000 unequal:6000000 negative:5000000 negative-unequal:5000000 mixed-sign:10000000 identity:10000000 int-left:10000000 int-right:10000000 int-neg-left:10000000 int-neg-right:10000000 int-zero:10000000}"

case "$PAIRS" in ''|*[!0-9]*|0) echo "PAIRS must be positive" >&2; exit 2 ;; esac

TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-bigint-compare.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bigint-compare"
LL="$TMP/bigint-compare.ll"
SUMMARY="$TMP/summary.tsv"

cd "$ROOT"
echo "Compiling $LABEL with --release --native --fast..."
TUNGSTEN_LL_PATH="$LL" \
  TUNGSTEN_C_INCLUDES="$SCRIPT_DIR/bigint_leaf_public_ref.c" \
  "$TUNGSTEN" compile "$SCRIPT_DIR/bigint_compare_full.w" \
  --release --native --fast --out "$BIN" >/dev/null

if [ "$(grep -c '^define i64 @__w_bigint_compare_src(i64 %a, i64 %b)' "$LL")" -ne 1 ]; then
  echo "expected exactly one strong native comparator seam" >&2
  exit 1
fi
COMPARE_SYMBOL="$(nm -g "$BIN" | awk '$NF == "__w_bigint_compare_src" || $NF == "___w_bigint_compare_src" { symbol = $(NF - 1) } END { if (symbol != "") print symbol }')"
if [ "$COMPARE_SYMBOL" != "T" ] && [ "$COMPARE_SYMBOL" != "t" ]; then
  echo "final binary did not bind a strong native comparator seam (nm type: ${COMPARE_SYMBOL:-missing})" >&2
  exit 1
fi

"$BIN" check
: > "$OUT"
HOST_OS="$(uname -a)"
HOST_CPU="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || sysctl -n hw.model 2>/dev/null || uname -m)"
BENCH_CC="${TUNGSTEN_CC:-}"
CONFIG_PATH="${TUNGSTEN_CONFIG:-${HOME:-}/.tungsten/config}"
if [ -z "$BENCH_CC" ] && [ -f "$CONFIG_PATH" ]; then
  BENCH_CC="$(awk '
    /^\[build\][[:space:]]*$/ { in_build = 1; next }
    /^\[/ { in_build = 0 }
    in_build && /^[[:space:]]*cc[[:space:]]*=/ {
      sub(/^[^=]*=[[:space:]]*/, "")
      gsub(/^"|"$/, "")
      print
      exit
    }
  ' "$CONFIG_PATH")"
fi
if [ -z "$BENCH_CC" ]; then BENCH_CC="clang"; fi
CLANG_VERSION="$("$BENCH_CC" --version 2>/dev/null | sed -n '1p')"
TARGET_TRIPLE="$(sed -n 's/^target triple = "\([^"]*\)"/\1/p' "$LL" | sed -n '1p')"
TARGET_CPU="$(sed -n 's/.*"target-cpu"="\([^"]*\)".*/\1/p' "$LL" | sed -n '1p')"
printf 'META|schema|tungsten/runtime-port-bigint-compare/v1\n' >> "$OUT"
printf 'META|label|%s\n' "$LABEL" >> "$OUT"
printf 'META|flags|--release --native --fast\n' >> "$OUT"
printf 'META|host_os|%s\n' "$HOST_OS" >> "$OUT"
printf 'META|host_cpu|%s\n' "$HOST_CPU" >> "$OUT"
printf 'META|target_triple|%s\n' "$TARGET_TRIPLE" >> "$OUT"
printf 'META|target_cpu|%s\n' "$TARGET_CPU" >> "$OUT"
printf 'META|clang|%s\n' "$CLANG_VERSION" >> "$OUT"
printf 'META|pairs|%s\n' "$PAIRS" >> "$OUT"
printf 'META|max_ratio|%s\n' "$MAX_RATIO" >> "$OUT"

run_leg() {
  local lane="$1" stratum="$2" iters="$3"
  printf '%s|%s\n' "$lane" "$("$BIN" bench "$(printf '%s' "$lane" | tr 'CW' 'cw')" "$stratum" "$iters")" >> "$OUT"
}

for row in $ROWS; do
  stratum="${row%%:*}"
  iters="${row##*:}"
  pair=1
  while [ "$pair" -le "$PAIRS" ]; do
    echo "  $LABEL compare-$stratum pair $pair/$PAIRS" >&2
    if [ $((pair % 2)) -eq 1 ]; then
      run_leg C "$stratum" "$iters"
      run_leg W "$stratum" "$iters"
      run_leg W "$stratum" "$iters"
      run_leg C "$stratum" "$iters"
    else
      run_leg W "$stratum" "$iters"
      run_leg C "$stratum" "$iters"
      run_leg C "$stratum" "$iters"
      run_leg W "$stratum" "$iters"
    fi
    pair=$((pair + 1))
  done
done

stats_stream() {
  sort -n | awk '
    { v[NR] = $1 }
    END {
      if (NR == 0) exit 1
      if (NR % 2) median = v[(NR + 1) / 2]
      else median = (v[NR / 2] + v[NR / 2 + 1]) / 2
      q1i = int((NR + 3) / 4)
      q3i = int((3 * NR + 3) / 4)
      if (q1i < 1) q1i = 1
      if (q3i < 1) q3i = 1
      printf "%.12f %.12f %.12f %.12f %.12f\n", median, v[q1i], v[q3i], v[1], v[NR]
    }
  '
}

printf '%-24s %11s %11s %11s %11s %11s\n' "operation" "median" "p25" "p75" "min" "max"
printf '%-24s %11s %11s %11s %11s %11s\n' "------------------------" "-----------" "-----------" "-----------" "-----------" "-----------"
: > "$SUMMARY"
failed=0
for row in $ROWS; do
  stratum="${row%%:*}"
  name="compare-$stratum"
  stats="$(awk -F'|' -v n="$name" '
    $2 == "RESULT" && $3 == n {
      if ($1 == "C") c += $4; else w += $4
      legs++
      if (legs == 4) {
        printf "%.12f\n", w / c
        c = 0; w = 0; legs = 0
      }
    }
  ' "$OUT" | stats_stream)"
  read -r median p25 p75 min_ratio max_observed <<< "$stats"
  printf '%-24s %11.4f %11.4f %11.4f %11.4f %11.4f\n' "$name" "$median" "$p25" "$p75" "$min_ratio" "$max_observed"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$median" "$p25" "$p75" "$min_ratio" "$max_observed" >> "$SUMMARY"
  if awk -v ratio="$median" -v cap="$MAX_RATIO" 'BEGIN { exit !(ratio > cap) }'; then
    failed=1
  fi
done
echo "raw samples: $OUT"
if command -v ruby >/dev/null 2>&1; then
  ruby -rjson -e '
    summary, raw, out, label, host_os, host_cpu, triple, cpu, clang, pairs, max_ratio = ARGV
    rows = File.readlines(summary, chomp: true).map do |line|
      name, median, p25, p75, min, max = line.split("\t")
      {operation: name, median_source_over_c: median.to_f, p25: p25.to_f, p75: p75.to_f, min: min.to_f, max: max.to_f}
    end
    doc = {
      schema: "tungsten/runtime-port-bigint-compare/v1",
      label: label,
      flags: ["--release", "--native", "--fast"],
      machine: {host_os: host_os, host_cpu: host_cpu, target_triple: triple, target_cpu: cpu, clang: clang},
      pairs: pairs.to_i,
      max_ratio: max_ratio.to_f,
      rows: rows,
      raw_samples: File.basename(raw)
    }
    File.write(out, JSON.pretty_generate(doc) + "\n")
  ' "$SUMMARY" "$OUT" "$JSON_OUT" "$LABEL" "$HOST_OS" "$HOST_CPU" "$TARGET_TRIPLE" "$TARGET_CPU" "$CLANG_VERSION" "$PAIRS" "$MAX_RATIO"
  echo "json summary: $JSON_OUT"
fi
if [ "$failed" -ne 0 ]; then
  echo "comparison acceptance failed: a median exceeded ${MAX_RATIO}x C" >&2
  exit 1
fi
