#!/usr/bin/env bash
# Isolated native-IC versus public source-method gate for Integer#to_i.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SOURCE="$SCRIPT_DIR/integer_to_i_public.w"
CLOCK_REF="$SCRIPT_DIR/runtime_port_clock_ref.c"
CANDIDATE_ROOT="${CANDIDATE_ROOT:-$ROOT}"
PAIRS="${PAIRS:-12}"
ITERS="${ITERS:-50000000}"
WARMUP="${WARMUP:-1000000}"
GATE="${GATE:-1.10}"
CHECK_ONLY="${CHECK_ONLY:-0}"

if [ -z "${BASELINE_ROOT:-}" ]; then
  echo "BASELINE_ROOT must name an isolated pre-migration Tungsten root" >&2
  exit 2
fi
case "$PAIRS" in ''|*[!0-9]*|0) echo "PAIRS must be positive" >&2; exit 2 ;; esac
case "$ITERS" in ''|*[!0-9]*|0) echo "ITERS must be positive" >&2; exit 2 ;; esac
case "$WARMUP" in ''|*[!0-9]*) echo "WARMUP must be nonnegative" >&2; exit 2 ;; esac
case "$CHECK_ONLY" in 0|1) ;; *) echo "CHECK_ONLY must be 0 or 1" >&2; exit 2 ;; esac
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
done

if ! grep -q 'static WValue w_ic_int_to_i' "$BASELINE_ROOT/runtime/runtime.c"; then
  echo "shape audit failed: baseline lacks Integer#to_i native IC" >&2
  exit 1
fi
if grep -q 'static WValue w_ic_int_to_i' "$CANDIDATE_ROOT/runtime/runtime.c"; then
  echo "shape audit failed: candidate still contains Integer#to_i native IC" >&2
  exit 1
fi
if ! grep -A1 -E '^[[:space:]]*->[[:space:]]+to_i' "$CANDIDATE_ROOT/core/integer.w" | grep -Eq '^[[:space:]]*self[[:space:]]*$'; then
  echo "shape audit failed: candidate lacks the exact self identity body" >&2
  exit 1
fi
if ! grep -Eq '^use core/integer$' "$CANDIDATE_ROOT/compiler/tungsten.w"; then
  echo "shape audit failed: candidate lacks first-generation bootstrap import" >&2
  exit 1
fi
echo "shape audit: baseline native IC / candidate source identity"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-int-to-i-public.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
SOURCE_COPY="$TMP/integer_to_i_public.w"
CLOCK_COPY="$TMP/runtime_port_clock_ref.c"
BASE_BIN="$TMP/baseline"
CAND_BIN="$TMP/candidate"
WIRE="$TMP/candidate.wire"
RAW="$TMP/results.txt"
cp "$SOURCE" "$SOURCE_COPY"
cp "$CLOCK_REF" "$CLOCK_COPY"

echo "Compiling matched public binaries (excluded from timings)..."
(
  cd "$TMP"
  TUNGSTEN_C_INCLUDES="$CLOCK_COPY" "$BASELINE_ROOT/bin/tungsten" compile "$SOURCE_COPY" --release --out "$BASE_BIN" >/dev/null
)
(
  cd "$TMP"
  TUNGSTEN_C_INCLUDES="$CLOCK_COPY" "$CANDIDATE_ROOT/bin/tungsten" compile "$SOURCE_COPY" --emit-wire > "$WIRE"
  TUNGSTEN_C_INCLUDES="$CLOCK_COPY" "$CANDIDATE_ROOT/bin/tungsten" compile "$SOURCE_COPY" --release --out "$CAND_BIN" >/dev/null
)

method_body="$(sed -n '/^function __w_Integer_to_i__a1(/,/^$/p' "$WIRE")"
if [ -z "$method_body" ] || ! printf '%s\n' "$method_body" | grep -Eq 'ret_i64[[:space:]]+%__self'; then
  echo "WIRE audit failed: Integer#to_i is not a direct self return" >&2
  exit 1
fi
if printf '%s\n' "$method_body" | grep -Eq 'call_|ccall|w_ic_int_to_i'; then
  echo "WIRE audit failed: Integer#to_i retained a call" >&2
  exit 1
fi
echo "WIRE audit: public source body is a bare self return"

"$BASE_BIN" check
"$CAND_BIN" check

if [ "$CHECK_ONLY" = "1" ]; then
  echo "CHECK_ONLY=1: shape, WIRE, compile, and exact semantic gates passed."
  exit 0
fi

measure() {
  local binary="$1" output="$2"
  "$binary" bench "$ITERS" "$WARMUP" > "$output"
}

: > "$RAW"
pair=1
while [ "$pair" -le "$PAIRS" ]; do
  if [ $((pair % 2)) -eq 1 ]; then
    echo "  pair $pair/$PAIRS (native/source)" >&2
    measure "$BASE_BIN" "$TMP/baseline.txt"
    measure "$CAND_BIN" "$TMP/candidate.txt"
  else
    echo "  pair $pair/$PAIRS (source/native)" >&2
    measure "$CAND_BIN" "$TMP/candidate.txt"
    measure "$BASE_BIN" "$TMP/baseline.txt"
  fi
  for target in varying inferred; do
    b_ns="$(awk -F'|' -v target="$target" '$1=="RESULT" && $2==target {print $3}' "$TMP/baseline.txt")"
    b_sum="$(awk -F'|' -v target="$target" '$1=="RESULT" && $2==target {print $4}' "$TMP/baseline.txt")"
    c_ns="$(awk -F'|' -v target="$target" '$1=="RESULT" && $2==target {print $3}' "$TMP/candidate.txt")"
    c_sum="$(awk -F'|' -v target="$target" '$1=="RESULT" && $2==target {print $4}' "$TMP/candidate.txt")"
    test "$b_sum" = "$c_sum" || { echo "checksum mismatch for $target" >&2; exit 1; }
    ratio="$(awk -v b="$b_ns" -v c="$c_ns" 'BEGIN {print c / b}')"
    printf 'PAIR|%d|%s|%s|%s|%s\n' "$pair" "$target" "$b_ns" "$c_ns" "$ratio" >> "$RAW"
  done
  pair=$((pair + 1))
done

median_stream() { sort -n | awk '{v[NR]=$1} END {if (NR%2) print v[(NR+1)/2]; else print (v[NR/2]+v[NR/2+1])/2}'; }
printf '\n%-10s %12s %12s %10s %8s\n' path 'native ns' 'source ns' source/C gate
failed=0
for target in varying inferred; do
  base_med="$(awk -F'|' -v t="$target" '$1=="PAIR" && $3==t {print $4}' "$RAW" | median_stream)"
  cand_med="$(awk -F'|' -v t="$target" '$1=="PAIR" && $3==t {print $5}' "$RAW" | median_stream)"
  ratio_med="$(awk -F'|' -v t="$target" '$1=="PAIR" && $3==t {print $6}' "$RAW" | median_stream)"
  base_call="$(awk -v n="$base_med" -v i="$ITERS" 'BEGIN {print n/i}')"
  cand_call="$(awk -v n="$cand_med" -v i="$ITERS" 'BEGIN {print n/i}')"
  decision="$(awk -v r="$ratio_med" -v g="$GATE" 'BEGIN {print r<=g ? "PASS" : "SKIP"}')"
  test "$decision" = PASS || failed=1
  printf '%-10s %12.4f %12.4f %10.4f %8s\n' "$target" "$base_call" "$cand_call" "$ratio_med" "$decision"
done

echo "Thread CPU time excludes competing-process scheduling; repeat independently before retention."
if [ "$failed" -ne 0 ]; then
  exit 3
fi
