#!/usr/bin/env bash
# Same-binary full immutable and consumed BigInt &, |, ^ source/C gate.
# Default mode is fail-closed acceptance. Use MODE=baseline explicitly to
# capture an older partial-seam artifact with identical machinery.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TUNGSTEN="${TUNGSTEN:-$ROOT/bin/tungsten}"
MODE="${MODE:-accept}"
PAIRS="${PAIRS:-8}"
MAX_RATIO="${MAX_RATIO:-1.10}"
TARGET_NS="${TARGET_NS:-110000000}"
SAMPLE_MIN_NS="${SAMPLE_MIN_NS:-$TARGET_NS}"
CALIBRATION_MIN_NS="${CALIBRATION_MIN_NS:-5000000}"
LABEL="${LABEL:-current}"
CHECK_ONLY="${CHECK_ONLY:-0}"
OUT="${OUT:-/tmp/tungsten-bigint-bitwise-full-${LABEL}-${MODE}.txt}"
JSON_OUT="${JSON_OUT:-${OUT%.txt}.json}"

case "$MODE" in baseline|accept) ;; *) echo "MODE must be baseline or accept" >&2; exit 2 ;; esac
case "$PAIRS" in ''|*[!0-9]*|0) echo "PAIRS must be positive" >&2; exit 2 ;; esac
case "$TARGET_NS" in ''|*[!0-9]*|0) echo "TARGET_NS must be positive" >&2; exit 2 ;; esac
case "$SAMPLE_MIN_NS" in ''|*[!0-9]*|0) echo "SAMPLE_MIN_NS must be positive" >&2; exit 2 ;; esac
case "$CALIBRATION_MIN_NS" in ''|*[!0-9]*|0) echo "CALIBRATION_MIN_NS must be positive" >&2; exit 2 ;; esac
case "$CHECK_ONLY" in 0|1) ;; *) echo "CHECK_ONLY must be 0 or 1" >&2; exit 2 ;; esac

DEFAULT_WIDTHS="1 2 3 4 5 8 16 24 32 40 48 64 128 256 384 448 512 1024 2048 4096 8192"
DEFAULT_SHAPES="boundary-4095 boundary-4097 skew-64-4 skew-4-64 skew-8192-4 skew-4-8192 inline-left inline-right negneg-overlay-1 negpos-overlay-1 posneg-overlay-1 negneg-overlay-4 negpos-overlay-4 posneg-overlay-4 negneg-overlay-64 negpos-overlay-64 posneg-overlay-64 negneg-header-4 negpos-header-4 posneg-header-4 negneg-header-64 negpos-header-64 posneg-header-64 same-object distinct-equal zero-left zero-right minus-one-left minus-one-right normalize-top normalize-inline normalize-zero"

ROW_LIST=()
CUSTOM_MATRIX=0
if [ -n "${ROWS:-}" ]; then
  CUSTOM_MATRIX=1
  read -r -a ROW_LIST <<< "$ROWS"
  if [ "$MODE" = "accept" ] && [ "${ALLOW_SUBSET_ACCEPT:-0}" != "1" ]; then
    echo "custom ROWS are not a full acceptance matrix; use MODE=baseline or set ALLOW_SUBSET_ACCEPT=1 for a labelled subset gate" >&2
    exit 2
  fi
else
  for op in and or xor; do
    for width in $DEFAULT_WIDTHS; do
      ROW_LIST+=("$op/width-$width")
    done
    for shape in $DEFAULT_SHAPES; do
      ROW_LIST+=("$op/$shape")
    done
    if [ "$MODE" = "accept" ]; then
      for width in 1 2 4 8 16 32 64 128 256; do
        ROW_LIST+=("$op/mut-width-$width")
      done
    fi
  done
fi

if [ "${#ROW_LIST[@]}" -eq 0 ]; then
  echo "benchmark matrix is empty" >&2
  exit 2
fi
for row in "${ROW_LIST[@]}"; do
  case "$row" in and/*|or/*|xor/*) ;; *) echo "invalid row '$row' (expected and/..., or/..., or xor/...)" >&2; exit 2 ;; esac
  if [ "$MODE" = "baseline" ]; then
    case "$row" in
      */mut-width-*) echo "compound source seams are fail-closed acceptance-only; remove '$row' or use MODE=accept" >&2; exit 2 ;;
    esac
  fi
done

TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-bigint-bitwise-full.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bigint-bitwise-full"
LL="$TMP/bigint-bitwise-full.ll"
NM_OUT="$TMP/nm.txt"
SUMMARY="$TMP/summary.tsv"
IR_REPORT="$TMP/ir-report.txt"

cd "$ROOT"
unset TUNGSTEN_BIGINT_SRC_OPS
echo "Compiling $LABEL with --release --native --fast..." >&2
TUNGSTEN_LL_PATH="$LL" \
  TUNGSTEN_C_INCLUDES="$SCRIPT_DIR/bigint_leaf_public_ref.c:$SCRIPT_DIR/bigint_bitwise_full_ref.c" \
  "$TUNGSTEN" compile "$SCRIPT_DIR/bigint_bitwise_full.w" \
  --release --native --fast --out "$BIN" >/dev/null

ruby "$SCRIPT_DIR/check_bigint_bitwise_full_ir.rb" "$LL" "$MODE" > "$IR_REPORT"
nm -g "$BIN" > "$NM_OUT"

ll_definition_count() {
  local symbol="$1"
  awk -v symbol="$symbol" '
    $0 ~ ("^define[[:space:]].*[@]" symbol "\\(") { count++ }
    END { print count + 0 }
  ' "$LL"
}

require_ll_definition() {
  local symbol="$1"
  local count
  count="$(ll_definition_count "$symbol")"
  if [ "$count" -ne 1 ]; then
    echo "expected exactly one strong LLVM definition for $symbol, found $count" >&2
    exit 1
  fi
}

symbol_type() {
  local symbol="$1"
  awk -v symbol="$symbol" '
    $NF == symbol || $NF == "_" symbol { type = $(NF - 1) }
    END { if (type != "") print type }
  ' "$NM_OUT"
}

require_strong_symbol() {
  local symbol="$1"
  local type
  type="$(symbol_type "$symbol")"
  if [ "$type" != "T" ] && [ "$type" != "t" ]; then
    echo "final binary did not bind strong symbol $symbol (nm type: ${type:-missing})" >&2
    exit 1
  fi
}

for op in and or xor; do
  require_ll_definition "__w_bigint_${op}_src"
  require_strong_symbol "__w_bigint_${op}_src"
  require_strong_symbol "w_bigint_${op}_c"
  require_strong_symbol "w_bigint_${op}_source"
  require_strong_symbol "w_bitwise_gate_${op}_c"
  require_strong_symbol "w_bitwise_gate_${op}_source"
  if [ "$MODE" = "accept" ]; then
    require_ll_definition "__w_bigint_${op}_mut_src"
    require_strong_symbol "__w_bigint_${op}_mut_src"
    require_strong_symbol "w_bigint_${op}_mut"
    require_strong_symbol "w_bitwise_gate_${op}_mut_c"
    require_strong_symbol "w_bitwise_gate_${op}_mut_source"
  fi
done
if [ "$MODE" = "accept" ]; then
  require_ll_definition "__w_bigint_bitwise_source_complete"
  require_strong_symbol "__w_bigint_bitwise_source_complete"
fi

SEAM_STATUS="$($BIN seams)"
if [ "$MODE" = "accept" ] && [ "$SEAM_STATUS" != "SEAMS|full|1" ]; then
  echo "full acceptance requires __w_bigint_bitwise_source_complete() == 1; got '$SEAM_STATUS'" >&2
  exit 1
fi

CHECK_OUTPUT="$($BIN check)"
echo "$CHECK_OUTPUT"

sha256_file() {
  local path="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" | awk '{print $1}'
  else
    sha256sum "$path" | awk '{print $1}'
  fi
}

HOST_OS="$(uname -a)"
HOST_CPU="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || sysctl -n hw.model 2>/dev/null || uname -m)"
LOGICAL_CPUS="$(sysctl -n hw.logicalcpu 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo unknown)"
HOST_LOAD="$(uptime | tr '\n' ' ')"
if command -v pmset >/dev/null 2>&1; then
  POWER_STATE="$(pmset -g batt 2>/dev/null | tr '\n' ';' || true)"
elif [ -r /sys/class/power_supply/AC/online ]; then
  POWER_STATE="ac_online=$(sed -n '1p' /sys/class/power_supply/AC/online)"
else
  POWER_STATE="unknown"
fi
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
CLANG_VERSION="$($BENCH_CC --version 2>/dev/null | sed -n '1p')"
TARGET_TRIPLE="$(sed -n 's/^target triple = "\([^"]*\)"/\1/p' "$LL" | sed -n '1p')"
TARGET_CPU="$(sed -n 's/.*"target-cpu"="\([^"]*\)".*/\1/p' "$LL" | sed -n '1p')"
GIT_HEAD="$(git rev-parse HEAD)"
if [ -n "$(git status --porcelain)" ]; then GIT_DIRTY=true; else GIT_DIRTY=false; fi
GENERATED_UTC="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
MATRIX_KIND="full"
if [ "$CUSTOM_MATRIX" -eq 1 ]; then MATRIX_KIND="custom-subset"; fi

: > "$OUT"
meta() { printf 'META|%s|%s\n' "$1" "$2" >> "$OUT"; }
meta schema tungsten/runtime-port-bigint-bitwise-full/v1
meta generated_utc "$GENERATED_UTC"
meta label "$LABEL"
meta mode "$MODE"
meta matrix "$MATRIX_KIND"
meta flags "--release --native --fast"
meta host_os "$HOST_OS"
meta host_cpu "$HOST_CPU"
meta logical_cpus "$LOGICAL_CPUS"
meta host_load "$HOST_LOAD"
meta power "$POWER_STATE"
meta target_triple "$TARGET_TRIPLE"
meta target_cpu "$TARGET_CPU"
meta clang "$CLANG_VERSION"
meta git_head "$GIT_HEAD"
meta git_dirty "$GIT_DIRTY"
meta pairs "$PAIRS"
meta target_ns "$TARGET_NS"
meta sample_min_ns "$SAMPLE_MIN_NS"
meta calibration_min_ns "$CALIBRATION_MIN_NS"
meta max_ratio "$MAX_RATIO"
meta row_count "${#ROW_LIST[@]}"
meta compound "$([ "$MODE" = "accept" ] && echo 'source/C consumed seams included' || echo 'not-run:baseline has no strong consumed seams')"
meta source_w_sha256 "$(sha256_file "$SCRIPT_DIR/bigint_bitwise_full.w")"
meta source_c_sha256 "$(sha256_file "$SCRIPT_DIR/bigint_bitwise_full_ref.c")"
meta runner_sha256 "$(sha256_file "$SCRIPT_DIR/run_bigint_bitwise_full.sh")"
meta ir_sha256 "$(sha256_file "$LL")"
meta binary_sha256 "$(sha256_file "$BIN")"
printf 'CHECK|%s\n' "$CHECK_OUTPUT" >> "$OUT"
cat "$IR_REPORT" >> "$OUT"
printf '%s\n' "$SEAM_STATUS" >> "$OUT"

if [ "$CHECK_ONLY" = "1" ]; then
  echo "focused compile/correctness validation only; raw metadata: $OUT"
  exit 0
fi

bench_once() {
  local lane="$1" op="$2" stratum="$3" iters="$4" warmup="$5"
  local line prefix name elapsed actual_iters checksum kind
  line="$($BIN bench "$lane" "$op" "$stratum" "$iters" "$warmup")"
  IFS='|' read -r prefix name elapsed actual_iters checksum kind <<< "$line"
  if [ "$prefix" != "RESULT" ] || [ "$name" != "$op/$stratum" ] || [ "$actual_iters" != "$iters" ]; then
    echo "malformed benchmark result: $line" >&2
    exit 1
  fi
  case "$elapsed" in ''|*[!0-9]*) echo "non-numeric elapsed time: $line" >&2; exit 1 ;; esac
  case "$checksum" in ''|*[!0-9]*) echo "non-numeric checksum: $line" >&2; exit 1 ;; esac
  case "$kind" in 0|1|2) ;; *) echo "invalid lane kind: $line" >&2; exit 1 ;; esac
  printf '%s|%s|%s\n' "$elapsed" "$checksum" "$kind"
}

seed_iters() {
  case "$1" in
    *8192*) echo 64 ;;
    *4095*|*4096*|*4097*) echo 128 ;;
    *2048*) echo 256 ;;
    *1024*) echo 512 ;;
    *512*|*448*|*384*) echo 1000 ;;
    *256*|*128*) echo 2500 ;;
    *) echo 20000 ;;
  esac
}

scaled_iters() {
  local current="$1" elapsed="$2" target="$3" multiplier="$4"
  awk -v current="$current" -v elapsed="$elapsed" -v target="$target" -v multiplier="$multiplier" '
    BEGIN {
      wanted = current * target * multiplier / elapsed
      result = int(wanted)
      if (result < wanted) result++
      if (result <= current) result = current + 1
      print result
    }
  '
}

calibrate_row() {
  local op="$1" stratum="$2" name="$op/$stratum"
  local iters warmup c_result w_result c_ns w_ns c_sum w_sum c_kind w_kind min_ns rounds
  iters="$(seed_iters "$stratum")"
  rounds=0
  while :; do
    warmup=$((iters / 20))
    if [ "$warmup" -lt 1 ]; then warmup=1; fi
    c_result="$(bench_once c "$op" "$stratum" "$iters" "$warmup")"
    w_result="$(bench_once source "$op" "$stratum" "$iters" "$warmup")"
    IFS='|' read -r c_ns c_sum c_kind <<< "$c_result"
    IFS='|' read -r w_ns w_sum w_kind <<< "$w_result"
    if [ "$c_sum" != "$w_sum" ]; then
      echo "calibration checksum mismatch for $name: C=$c_sum source=$w_sum" >&2
      exit 1
    fi
    min_ns="$c_ns"
    if [ "$w_ns" -lt "$min_ns" ]; then min_ns="$w_ns"; fi
    if [ "$min_ns" -ge "$CALIBRATION_MIN_NS" ]; then break; fi
    iters=$((iters * 2))
    rounds=$((rounds + 1))
    if [ "$rounds" -ge 20 ]; then
      echo "could not calibrate $name to ${CALIBRATION_MIN_NS}ns" >&2
      exit 1
    fi
  done

  # Twenty-five percent headroom keeps every retained sample above the hard
  # 110ms floor even if the host speeds up after calibration.
  iters="$(scaled_iters "$iters" "$min_ns" "$TARGET_NS" 1.25)"
  rounds=0
  while :; do
    warmup=$((iters / 8))
    if [ "$warmup" -lt 1 ]; then warmup=1; fi
    c_result="$(bench_once c "$op" "$stratum" "$iters" "$warmup")"
    w_result="$(bench_once source "$op" "$stratum" "$iters" "$warmup")"
    IFS='|' read -r c_ns c_sum c_kind <<< "$c_result"
    IFS='|' read -r w_ns w_sum w_kind <<< "$w_result"
    if [ "$c_sum" != "$w_sum" ]; then
      echo "calibration checksum mismatch for $name: C=$c_sum source=$w_sum" >&2
      exit 1
    fi
    min_ns="$c_ns"
    if [ "$w_ns" -lt "$min_ns" ]; then min_ns="$w_ns"; fi
    if [ "$min_ns" -ge "$TARGET_NS" ]; then break; fi
    iters="$(scaled_iters "$iters" "$min_ns" "$TARGET_NS" 1.25)"
    rounds=$((rounds + 1))
    if [ "$rounds" -ge 6 ]; then
      echo "could not calibrate $name to ${TARGET_NS}ns" >&2
      exit 1
    fi
  done
  printf 'CALIBRATION|%s|%s|%s|%s|%s|%s\n' "$name" "$iters" "$c_ns" "$w_ns" "$c_sum" "$c_kind" >> "$OUT"
  printf '%s\n' "$iters"
}

run_sample() {
  local op="$1" stratum="$2" pair="$3" leg="$4" lane="$5" iters="$6"
  local warmup result elapsed checksum kind name
  warmup=$((iters / 8))
  if [ "$warmup" -lt 1 ]; then warmup=1; fi
  result="$(bench_once "$lane" "$op" "$stratum" "$iters" "$warmup")"
  IFS='|' read -r elapsed checksum kind <<< "$result"
  name="$op/$stratum"
  if [ "$elapsed" -lt "$SAMPLE_MIN_NS" ]; then
    echo "$name pair $pair leg $leg ran only ${elapsed}ns (< ${SAMPLE_MIN_NS}ns sample floor); rerun with more calibration headroom" >&2
    exit 1
  fi
  printf 'SAMPLE|%s|%s|%s|%s|%s|%s|%s|%s\n' "$name" "$pair" "$leg" "$lane" "$elapsed" "$iters" "$checksum" "$kind" >> "$OUT"
}

for row in "${ROW_LIST[@]}"; do
  op="${row%%/*}"
  stratum="${row#*/}"
  echo "Calibrating $row..." >&2
  iters="$(calibrate_row "$op" "$stratum")"
  pair=1
  while [ "$pair" -le "$PAIRS" ]; do
    echo "  $row pair $pair/$PAIRS" >&2
    if [ $((pair % 2)) -eq 1 ]; then
      run_sample "$op" "$stratum" "$pair" 1 c "$iters"
      run_sample "$op" "$stratum" "$pair" 2 source "$iters"
      run_sample "$op" "$stratum" "$pair" 3 source "$iters"
      run_sample "$op" "$stratum" "$pair" 4 c "$iters"
    else
      run_sample "$op" "$stratum" "$pair" 1 source "$iters"
      run_sample "$op" "$stratum" "$pair" 2 c "$iters"
      run_sample "$op" "$stratum" "$pair" 3 c "$iters"
      run_sample "$op" "$stratum" "$pair" 4 source "$iters"
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

printf '%-34s %10s %10s %10s %10s %10s\n' operation median p25 p75 min max
printf '%-34s %10s %10s %10s %10s %10s\n' ---------------------------------- ---------- ---------- ---------- ---------- ----------
: > "$SUMMARY"
failed=0
for row in "${ROW_LIST[@]}"; do
  sample_count="$(awk -F'|' -v name="$row" '$1 == "SAMPLE" && $2 == name { count++ } END { print count + 0 }' "$OUT")"
  if [ "$sample_count" -ne $((PAIRS * 4)) ]; then
    echo "$row has $sample_count samples, expected $((PAIRS * 4))" >&2
    exit 1
  fi
  checksum_count="$(awk -F'|' -v name="$row" '$1 == "SAMPLE" && $2 == name { seen[$8] = 1 } END { for (v in seen) count++; print count + 0 }' "$OUT")"
  if [ "$checksum_count" -ne 1 ]; then
    echo "$row source/C checksum mismatch" >&2
    exit 1
  fi
  kind_count="$(awk -F'|' -v name="$row" '$1 == "SAMPLE" && $2 == name { seen[$9] = 1 } END { for (v in seen) count++; print count + 0 }' "$OUT")"
  if [ "$kind_count" -ne 1 ]; then
    echo "$row changed lane kind during the campaign" >&2
    exit 1
  fi
  kind="$(awk -F'|' -v name="$row" '$1 == "SAMPLE" && $2 == name { print $9; exit }' "$OUT")"
  if [ "$MODE" = "accept" ] && [ "$kind" -ne 2 ]; then
    echo "$row did not exercise the complete source seam (lane kind $kind)" >&2
    exit 1
  fi
  stats="$(awk -F'|' -v name="$row" -v pairs="$PAIRS" '
    $1 == "SAMPLE" && $2 == name {
      pair = $3
      if ($5 == "c") c[pair] += $6; else w[pair] += $6
      legs[pair]++
    }
    END {
      for (pair = 1; pair <= pairs; pair++) {
        if (legs[pair] != 4 || c[pair] == 0) exit 1
        printf "%.12f\n", w[pair] / c[pair]
      }
    }
  ' "$OUT" | stats_stream)"
  read -r median p25 p75 min_ratio max_observed <<< "$stats"
  iters="$(awk -F'|' -v name="$row" '$1 == "CALIBRATION" && $2 == name { print $3; exit }' "$OUT")"
  printf '%-34s %10.4f %10.4f %10.4f %10.4f %10.4f\n' "$row" "$median" "$p25" "$p75" "$min_ratio" "$max_observed"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$row" "$median" "$p25" "$p75" "$min_ratio" "$max_observed" "$iters" "$kind" >> "$SUMMARY"
  if awk -v ratio="$median" -v cap="$MAX_RATIO" 'BEGIN { exit !(ratio > cap) }'; then
    failed=1
  fi
done

ruby -rjson -e '
  summary, raw, out = ARGV
  meta = {}
  File.foreach(raw) do |line|
    next unless line.start_with?("META|")
    _, key, value = line.chomp.split("|", 3)
    meta[key] = value
  end
  rows = File.readlines(summary, chomp: true).map do |line|
    name, median, p25, p75, min, max, iters, kind = line.split("\t")
    {
      operation: name,
      median_source_over_c: median.to_f,
      p25: p25.to_f,
      p75: p75.to_f,
      min: min.to_f,
      max: max.to_f,
      iterations_per_leg: iters.to_i,
      lane_kind: {"0" => "c-control", "1" => "partial-source", "2" => "complete-source"}.fetch(kind)
    }
  end
  doc = {
    schema: meta.delete("schema"),
    metadata: meta,
    rows: rows,
    raw_samples: File.basename(raw)
  }
  File.write(out, JSON.pretty_generate(doc) + "\n")
' "$SUMMARY" "$OUT" "$JSON_OUT"

echo "raw samples: $OUT"
echo "json summary: $JSON_OUT"
if [ "$failed" -ne 0 ]; then
  echo "bitwise acceptance failed: a median exceeded ${MAX_RATIO}x retained C" >&2
  exit 1
fi
