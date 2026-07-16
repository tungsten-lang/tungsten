#!/usr/bin/env bash
# Isolated native-IC versus public source-method gate for String/Symbol#empty?.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SOURCE="$SCRIPT_DIR/string_empty_public_hot.w"
CLOCK_REF="$SCRIPT_DIR/runtime_port_clock_ref.c"
CANDIDATE_ROOT="${CANDIDATE_ROOT:-$ROOT}"
RUNS="${RUNS:-10}"
ITERS="${ITERS:-30000000}"
GATE="${GATE:-1.10}"

if [ -z "${BASELINE_ROOT:-}" ]; then
  echo "BASELINE_ROOT must name an isolated pre-migration Tungsten root" >&2
  exit 2
fi
case "$RUNS" in ''|*[!0-9]*) echo "RUNS must be an integer" >&2; exit 2 ;; esac
if [ "$RUNS" -lt 8 ] || [ "$RUNS" -gt 12 ] || [ $((RUNS % 2)) -ne 0 ]; then
  echo "RUNS must be an even integer from 8 through 12" >&2
  exit 2
fi
case "$ITERS" in ''|*[!0-9]*|0) echo "ITERS must be a positive integer" >&2; exit 2 ;; esac
if ! awk -v gate="$GATE" 'BEGIN { exit !(gate ~ /^[0-9]+([.][0-9]+)?$/ && gate > 0) }'; then
  echo "GATE must be a positive number" >&2
  exit 2
fi

BASELINE_ROOT="$(cd "$BASELINE_ROOT" && pwd)"
CANDIDATE_ROOT="$(cd "$CANDIDATE_ROOT" && pwd)"
if [ "$BASELINE_ROOT" = "$CANDIDATE_ROOT" ]; then
  echo "BASELINE_ROOT and CANDIDATE_ROOT must differ" >&2
  exit 2
fi
for root in "$BASELINE_ROOT" "$CANDIDATE_ROOT"; do
  test -x "$root/bin/tungsten" || { echo "missing $root/bin/tungsten" >&2; exit 2; }
  test -f "$root/core/string_native.w" || { echo "missing core/string_native.w in $root" >&2; exit 2; }
done

handler_pattern='[{]0,[[:space:]]*w_ic_string_empty[}]'
assignment_pattern='w_ic_string_table\[[0-9]+\][.]name[[:space:]]*=[[:space:]]*WN_empty_q[[:space:]]*;'
if ! grep -Eq "$handler_pattern" "$BASELINE_ROOT/runtime/runtime.c" || \
   ! grep -Eq "$assignment_pattern" "$BASELINE_ROOT/runtime/runtime.c"; then
  echo "shape audit failed: baseline lacks String#empty? native IC" >&2
  exit 1
fi
if grep -Eq "$handler_pattern" "$CANDIDATE_ROOT/runtime/runtime.c" || \
   grep -Eq "$assignment_pattern" "$CANDIDATE_ROOT/runtime/runtime.c"; then
  echo "shape audit failed: candidate still installs String#empty? native IC" >&2
  exit 1
fi
if ! grep -Eq '[$]value[[:space:]]*&[[:space:]]*14' "$CANDIDATE_ROOT/core/string_native.w"; then
  echo "shape audit failed: candidate lacks optimized String#empty? mask" >&2
  exit 1
fi
echo "shape audit: baseline native IC / candidate optimized public source"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-string-empty-public.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
SOURCE_COPY="$TMP/string_empty_public_hot.w"
CLOCK_COPY="$TMP/runtime_port_clock_ref.c"
BASE_BIN="$TMP/baseline"
CAND_BIN="$TMP/candidate"
WIRE="$TMP/candidate.wire"
RAW="$TMP/results.txt"
cp "$SOURCE" "$SOURCE_COPY"
cp "$CLOCK_REF" "$CLOCK_COPY"

echo "Compiling isolated WIRE and release binaries (excluded from timings)..."
(
  cd "$TMP"
  TUNGSTEN_C_INCLUDES="$CLOCK_COPY" "$CANDIDATE_ROOT/bin/tungsten" compile "$SOURCE_COPY" --emit-wire > "$WIRE"
  TUNGSTEN_C_INCLUDES="$CLOCK_COPY" "$CANDIDATE_ROOT/bin/tungsten" compile "$SOURCE_COPY" --release --out "$CAND_BIN" >/dev/null
)
(
  cd "$TMP"
  TUNGSTEN_C_INCLUDES="$CLOCK_COPY" "$BASELINE_ROOT/bin/tungsten" compile "$SOURCE_COPY" --release --out "$BASE_BIN" >/dev/null
)

wire_body() { sed -n '/^function __w_String_empty_Q__a1(/,/^$/p' "$WIRE"; }
if ! wire_body | grep -q 'and_i64' || ! wire_body | grep -q 'icmp_i64'; then
  echo "WIRE audit failed: public String#empty? lacks mask/compare" >&2
  exit 1
fi
if wire_body | grep -Eq 'shr_i64|w_ic_string_empty|w_str_data'; then
  echo "WIRE audit failed: public String#empty? retained shift or C fallback" >&2
  exit 1
fi
echo "WIRE audit: public source is one mask and comparison"

echo "Checking exact public behavior in both isolated builds..."
"$BASE_BIN" check
"$CAND_BIN" check

measure() {
  local binary="$1" stratum="$2" output line
  output="$("$binary" bench "$stratum" "$ITERS")"
  line="$(printf '%s\n' "$output" | awk -F'|' -v name="public.empty?.$stratum" '$1=="RESULT" && $2==name {print $3 "|" $4}')"
  test -n "$line" || { echo "missing RESULT for $stratum from $binary" >&2; return 1; }
  printf '%s\n' "$line"
}

strata=(inline slab heap rope symbol)
: > "$RAW"
echo "Running $RUNS balanced process-CPU pairs per representation stratum..."
for stratum in "${strata[@]}"; do
  sample=0
  while [ "$sample" -lt "$RUNS" ]; do
    if [ $((sample % 2)) -eq 0 ]; then
      echo "  $stratum pair $((sample + 1))/$RUNS (native/source)" >&2
      base_result="$(measure "$BASE_BIN" "$stratum")"
      cand_result="$(measure "$CAND_BIN" "$stratum")"
    else
      echo "  $stratum pair $((sample + 1))/$RUNS (source/native)" >&2
      cand_result="$(measure "$CAND_BIN" "$stratum")"
      base_result="$(measure "$BASE_BIN" "$stratum")"
    fi
    base_ns="${base_result%%|*}"; base_sum="${base_result#*|}"
    cand_ns="${cand_result%%|*}"; cand_sum="${cand_result#*|}"
    if [ "$base_sum" != "$cand_sum" ]; then
      echo "checksum mismatch for $stratum: $base_sum != $cand_sum" >&2
      exit 1
    fi
    ratio="$(awk -v c="$cand_ns" -v b="$base_ns" 'BEGIN {print c / b}')"
    printf 'PAIR|%s|%s|%s|%s|%s\n' "$stratum" "$base_ns" "$cand_ns" "$ratio" "$base_sum" >> "$RAW"
    sample=$((sample + 1))
  done
done

median_stream() { sort -n | awk '{v[NR]=$1} END {if (NR%2) print v[(NR+1)/2]; else print (v[NR/2]+v[NR/2+1])/2}'; }
printf '\n%-12s %12s %12s %10s %8s\n' stratum 'native ns' 'source ns' source/C gate
failed=0
for stratum in "${strata[@]}"; do
  base_med="$(awk -F'|' -v s="$stratum" '$1=="PAIR" && $2==s {print $3}' "$RAW" | median_stream)"
  cand_med="$(awk -F'|' -v s="$stratum" '$1=="PAIR" && $2==s {print $4}' "$RAW" | median_stream)"
  ratio_med="$(awk -F'|' -v s="$stratum" '$1=="PAIR" && $2==s {print $5}' "$RAW" | median_stream)"
  base_per_call="$(awk -v total="$base_med" -v iters="$ITERS" 'BEGIN {print total / iters}')"
  cand_per_call="$(awk -v total="$cand_med" -v iters="$ITERS" 'BEGIN {print total / iters}')"
  decision="$(awk -v ratio="$ratio_med" -v gate="$GATE" 'BEGIN {print (ratio <= gate) ? "PASS" : "SKIP"}')"
  test "$decision" = PASS || failed=1
  printf '%-12s %12.3f %12.3f %10.3f %8s\n' "$stratum" "$base_per_call" "$cand_per_call" "$ratio_med" "$decision"
done

echo "Thread CPU time excludes competing-process scheduling; every stratum must remain <= $GATE."
if [ "$failed" -ne 0 ]; then
  echo "String#empty? public source failed at least one stratum" >&2
  exit 3
fi
