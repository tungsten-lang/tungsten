#!/usr/bin/env bash
# Matched-root public gate for UUID#byte and StringBuffer#size. The default is
# correctness/representation-only; set CHECK_ONLY=0 explicitly to time.

set -euo pipefail

BASELINE_ROOT="${BASELINE_ROOT:-/tmp/tungsten-uuid-strbuf-revisit-baseline}"
CANDIDATE_ROOT="${CANDIDATE_ROOT:-/tmp/tungsten-uuid-strbuf-revisit-candidate}"
CANDIDATE_COMPILER="${CANDIDATE_COMPILER:-$CANDIDATE_ROOT/bin/tungsten-compiler-revisit-v2}"
RUNS="${RUNS:-10}"
UUID_ITERS="${UUID_ITERS:-30000000}"
UUID_FALLBACK_ITERS="${UUID_FALLBACK_ITERS:-5000000}"
STRBUF_ITERS="${STRBUF_ITERS:-50000000}"
STRBUF_OVERFLOW_ITERS="${STRBUF_OVERFLOW_ITERS:-2000000}"
GATE="${GATE:-1.10}"
CHECK_ONLY="${CHECK_ONLY:-1}"

case "$RUNS" in
  ''|*[!0-9]*) echo "RUNS must be an integer" >&2; exit 2 ;;
esac
if [ "$RUNS" -lt 8 ] || [ "$RUNS" -gt 12 ] || [ $((RUNS % 2)) -ne 0 ]; then
  echo "RUNS must be an even integer from 8 through 12" >&2
  exit 2
fi
for value in "$UUID_ITERS" "$UUID_FALLBACK_ITERS" "$STRBUF_ITERS" "$STRBUF_OVERFLOW_ITERS"; do
  case "$value" in
    ''|*[!0-9]*|0) echo "iteration counts must be positive integers" >&2; exit 2 ;;
  esac
done
case "$CHECK_ONLY" in
  0|1) ;;
  *) echo "CHECK_ONLY must be 0 or 1" >&2; exit 2 ;;
esac
if ! awk -v gate="$GATE" 'BEGIN { exit !(gate ~ /^[0-9]+([.][0-9]+)?$/ && gate > 0) }'; then
  echo "GATE must be a positive number" >&2
  exit 2
fi

for root in "$BASELINE_ROOT" "$CANDIDATE_ROOT"; do
  if [ ! -x "$root/bin/tungsten" ] || [ ! -x "$root/bin/tungsten-compiler" ]; then
    echo "missing compiler driver/artifact under $root" >&2
    exit 2
  fi
done

UUID_SRC="benchmarks/runtime_ports/uuid_byte_revisit_public.w"
STRBUF_SRC="benchmarks/runtime_ports/string_buffer_size_revisit_public.w"
CLOCK_SRC="benchmarks/runtime_ports/revisit_thread_clock.c"
STRBUF_REF="benchmarks/runtime_ports/string_buffer_size_revisit_ref.c"
for rel in "$UUID_SRC" "$STRBUF_SRC" "$CLOCK_SRC" "$STRBUF_REF"; do
  if ! cmp -s "$BASELINE_ROOT/$rel" "$CANDIDATE_ROOT/$rel"; then
    echo "matched-root source mismatch: $rel" >&2
    exit 1
  fi
done

baseline_head="$(git -C "$BASELINE_ROOT" rev-parse HEAD)"
candidate_head="$(git -C "$CANDIDATE_ROOT" rev-parse HEAD)"
if [ "$baseline_head" != "$candidate_head" ]; then
  echo "baseline/candidate HEAD mismatch: $baseline_head vs $candidate_head" >&2
  exit 1
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-uuid-strbuf-revisit.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

compile_trial() {
  label="$1"
  root="$2"
  src="$3"
  wire="$4"
  bin="$5"
  includes="$root/$CLOCK_SRC"
  if [ "$src" = "$STRBUF_SRC" ]; then
    includes="$includes:$root/$STRBUF_REF"
  fi
  # The compiler already receives absolute source/root paths, but run inside
  # the matching root too: older bootstrap compilers still let cwd influence
  # native runtime-archive discovery.
  (
    cd "$root"
    TUNGSTEN_C_INCLUDES="$includes" \
      "$root/bin/tungsten" compile "$root/$src" --emit-wire > "$wire"
    TUNGSTEN_C_INCLUDES="$includes" \
      "$root/bin/tungsten" compile "$root/$src" --release --out "$bin" >/dev/null
  )
  echo "prepared $label $(basename "$src")" >&2
}

compile_trial baseline "$BASELINE_ROOT" "$UUID_SRC" "$TMP/uuid.baseline.wire" "$TMP/uuid.baseline"
compile_trial candidate "$CANDIDATE_ROOT" "$UUID_SRC" "$TMP/uuid.candidate.wire" "$TMP/uuid.candidate"
compile_trial baseline "$BASELINE_ROOT" "$STRBUF_SRC" "$TMP/strbuf.baseline.wire" "$TMP/strbuf.baseline"
compile_trial candidate "$CANDIDATE_ROOT" "$STRBUF_SRC" "$TMP/strbuf.candidate.wire" "$TMP/strbuf.candidate"

wire_body() {
  wire="$1"
  fn="$2"
  sed -n "/^function $fn(/,/^$/p" "$wire"
}

require_body() {
  wire="$1"
  fn="$2"
  pattern="$3"
  if ! wire_body "$wire" "$fn" | grep -Eq "$pattern"; then
    echo "WIRE check failed: $fn in $(basename "$wire") lacks /$pattern/" >&2
    exit 1
  fi
}

reject_body() {
  wire="$1"
  fn="$2"
  pattern="$3"
  if wire_body "$wire" "$fn" | grep -Eq "$pattern"; then
    echo "WIRE check failed: $fn in $(basename "$wire") contains /$pattern/" >&2
    exit 1
  fi
}

UUID_FN="__w_UUID_byte__a2"
STRBUF_BASE_FN="__w_string_buffer_size__a1"
STRBUF_CAND_FN="__w_StringBuffer_size__a1"
STRBUF_V1_FN="__w_StringBuffer___w_string_buffer_size_v1__a1"
require_body "$TMP/uuid.baseline.wire" "$UUID_FN" 'call_direct_i64 .*@w_uuid_byte'
reject_body  "$TMP/uuid.baseline.wire" "$UUID_FN" 'view_load_inline_byte'
require_body "$TMP/uuid.candidate.wire" "$UUID_FN" 'call_direct_i64 .*@w_to_i64'
require_body "$TMP/uuid.candidate.wire" "$UUID_FN" 'and_i64'
require_body "$TMP/uuid.candidate.wire" "$UUID_FN" 'view_load_inline_byte'
reject_body  "$TMP/uuid.candidate.wire" "$UUID_FN" 'w_uuid_byte|call_method_i64'

# The baseline bodyless declaration returns nil/zero and is bypassed by the
# native size IC. The candidate has a registered StringBuffer class and an
# inline exact-i48 arm plus a cold canonical-BigInt fallback after removal.
require_body "$TMP/strbuf.baseline.wire" "$STRBUF_BASE_FN" 'ret_i64 0'
reject_body  "$TMP/strbuf.baseline.wire" "$STRBUF_BASE_FN" 'view_load_field'
for wire in "$TMP/strbuf.baseline.wire" "$TMP/strbuf.candidate.wire"; do
  require_body "$wire" "$STRBUF_V1_FN" 'view_load_field'
  require_body "$wire" "$STRBUF_V1_FN" 'call_direct_i64 .*@w_int'
  reject_body  "$wire" "$STRBUF_V1_FN" 'icmp_i64|and_i64|or_i64|call_method_i64'
done
require_body "$TMP/strbuf.candidate.wire" "$STRBUF_CAND_FN" 'view_load_field'
require_body "$TMP/strbuf.candidate.wire" "$STRBUF_CAND_FN" 'icmp_i64'
require_body "$TMP/strbuf.candidate.wire" "$STRBUF_CAND_FN" 'and_i64'
require_body "$TMP/strbuf.candidate.wire" "$STRBUF_CAND_FN" 'shl_i64'
require_body "$TMP/strbuf.candidate.wire" "$STRBUF_CAND_FN" 'ashr_i64'
require_body "$TMP/strbuf.candidate.wire" "$STRBUF_CAND_FN" 'or_i64'
require_body "$TMP/strbuf.candidate.wire" "$STRBUF_CAND_FN" 'call_direct_i64 .*@w_int'
reject_body  "$TMP/strbuf.candidate.wire" "$STRBUF_CAND_FN" 'call_method_i64'
if [ "$(wire_body "$TMP/strbuf.candidate.wire" "$STRBUF_CAND_FN" | awk '/icmp_i64/ { n += 1 } END { print n + 0 }')" -ne 1 ]; then
  echo "WIRE check failed: optimized StringBuffer#size must use one range-test comparison" >&2
  exit 1
fi
if rg -q 'w_ic_strbuf_size' "$CANDIDATE_ROOT/runtime/runtime.c"; then
  echo "candidate still contains the public StringBuffer#size IC" >&2
  exit 1
fi
echo "WIRE/runtime: public UUID source load and StringBuffer IC removal are exact"

"$TMP/uuid.baseline" check > "$TMP/uuid.baseline.check"
"$TMP/uuid.candidate" check > "$TMP/uuid.candidate.check"
cmp "$TMP/uuid.baseline.check" "$TMP/uuid.candidate.check"
cat "$TMP/uuid.candidate.check"

"$TMP/strbuf.baseline" check > "$TMP/strbuf.baseline.check"
"$TMP/strbuf.candidate" check > "$TMP/strbuf.candidate.check"
cmp "$TMP/strbuf.baseline.check" "$TMP/strbuf.candidate.check"
cat "$TMP/strbuf.candidate.check"

for label in baseline candidate; do
  set +e
  "$TMP/uuid.$label" fatal-float > "$TMP/uuid.$label.fatal.out" 2> "$TMP/uuid.$label.fatal.err"
  status=$?
  set -e
  if [ "$status" -eq 0 ] || ! head -n 1 "$TMP/uuid.$label.fatal.err" | grep -q '^runtime error: expected int, got numeric'; then
    echo "UUID Float-index error check failed for $label (status=$status)" >&2
    exit 1
  fi
  # Caller symbol/offset naturally changes when the public method body moves;
  # compare the exact diagnostic payload before that location suffix.
  head -n 1 "$TMP/uuid.$label.fatal.err" | sed 's/ (caller=.*$//' > "$TMP/uuid.$label.fatal.first"
done
cmp "$TMP/uuid.baseline.fatal.first" "$TMP/uuid.candidate.fatal.first"
echo "errors: UUID Float conversion diagnostic payload matches exactly"

if [ -x "$CANDIDATE_COMPILER" ]; then
  TUNGSTEN_ROOT="$CANDIDATE_ROOT" "$CANDIDATE_COMPILER" \
    compile "$CANDIDATE_ROOT/spec/compiler/uuid_byte_revisit_autoload_spec.w" \
    --release --out "$TMP/uuid.autoload" >/dev/null
  TUNGSTEN_ROOT="$CANDIDATE_ROOT" "$CANDIDATE_COMPILER" \
    compile "$CANDIDATE_ROOT/spec/compiler/string_buffer_size_revisit_autoload_spec.w" \
    --release --out "$TMP/strbuf.autoload" >/dev/null
  "$TMP/uuid.autoload"
  "$TMP/strbuf.autoload"
  TUNGSTEN_ROOT="$CANDIDATE_ROOT" "$CANDIDATE_COMPILER" \
    run "$CANDIDATE_ROOT/spec/interpreter/uuid_byte_revisit_spec.w"
  TUNGSTEN_ROOT="$CANDIDATE_ROOT" "$CANDIDATE_COMPILER" \
    run "$CANDIDATE_ROOT/spec/interpreter/string_buffer_size_revisit_spec.w"
else
  echo "candidate compiler unavailable; skipped rebuilt-loader/interpreter checks" >&2
  exit 1
fi

if [ "$CHECK_ONLY" = "1" ]; then
  echo "CHECK_ONLY=1: all compile, WIRE, runtime, autoload, interpreter, and exactness gates passed; timings not run."
  exit 0
fi

sample_field() {
  sample="$1"
  field="$2"
  printf '%s\n' "$sample" | awk -F'|' -v f="$field" '$1 == "SAMPLE" {print $f}'
}

run_pair() {
  metric="$1"
  mode="$2"
  iters="$3"
  parity="$4"
  baseline_bin="$5"
  candidate_bin="$6"

  if [ "$parity" -eq 0 ]; then
    b1="$("$baseline_bin" "$mode" "$iters")"
    c1="$("$candidate_bin" "$mode" "$iters")"
    c2="$("$candidate_bin" "$mode" "$iters")"
    b2="$("$baseline_bin" "$mode" "$iters")"
  else
    c1="$("$candidate_bin" "$mode" "$iters")"
    b1="$("$baseline_bin" "$mode" "$iters")"
    b2="$("$baseline_bin" "$mode" "$iters")"
    c2="$("$candidate_bin" "$mode" "$iters")"
  fi

  bsum="$(awk -v a="$(sample_field "$b1" 3)" -v b="$(sample_field "$b2" 3)" 'BEGIN {print a+b}')"
  csum="$(awk -v a="$(sample_field "$c1" 3)" -v b="$(sample_field "$c2" 3)" 'BEGIN {print a+b}')"
  checksum="$(sample_field "$b1" 5)"
  for sample in "$b2" "$c1" "$c2"; do
    if [ "$(sample_field "$sample" 5)" != "$checksum" ]; then
      echo "checksum mismatch in $metric" >&2
      exit 1
    fi
  done
  ratio="$(awk -v c="$csum" -v b="$bsum" 'BEGIN {print c/b}')"
  bns="$(awk -v n="$bsum" -v calls="$iters" 'BEGIN {print n/(2*calls)}')"
  cns="$(awk -v n="$csum" -v calls="$iters" 'BEGIN {print n/(2*calls)}')"
  echo "PAIR|$metric|$bns|$cns|$ratio|$checksum"
}

RAW="$TMP/results.txt"
: > "$RAW"
i=0
while [ "$i" -lt "$RUNS" ]; do
  parity=$((i % 2))
  echo "timed pair $((i + 1))/$RUNS (parity $parity)" >&2
  run_pair uuid.hot hot "$UUID_ITERS" "$parity" "$TMP/uuid.baseline" "$TMP/uuid.candidate" >> "$RAW"
  run_pair uuid.fallback fallback "$UUID_FALLBACK_ITERS" "$parity" "$TMP/uuid.baseline" "$TMP/uuid.candidate" >> "$RAW"
  run_pair strbuf.size hot "$STRBUF_ITERS" "$parity" "$TMP/strbuf.baseline" "$TMP/strbuf.candidate" >> "$RAW"
  run_pair strbuf.overflow overflow "$STRBUF_OVERFLOW_ITERS" "$parity" "$TMP/strbuf.baseline" "$TMP/strbuf.candidate" >> "$RAW"
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

failed=0
printf '%-16s %12s %12s %10s %10s %8s\n' "function" "native ns" "source ns" "median W/C" "worst W/C" "gate"
for metric in uuid.hot uuid.fallback strbuf.size strbuf.overflow; do
  bmed="$(awk -F'|' -v m="$metric" '$1 == "PAIR" && $2 == m {print $3}' "$RAW" | median_stream)"
  cmed="$(awk -F'|' -v m="$metric" '$1 == "PAIR" && $2 == m {print $4}' "$RAW" | median_stream)"
  ratio="$(awk -F'|' -v m="$metric" '$1 == "PAIR" && $2 == m {print $5}' "$RAW" | median_stream)"
  worst="$(awk -F'|' -v m="$metric" '$1 == "PAIR" && $2 == m { if (!seen || $5 > max) max = $5; seen = 1 } END { if (seen) print max }' "$RAW")"
  decision="$(awk -v r="$ratio" -v g="$GATE" 'BEGIN {print (r <= g ? "PASS" : "SKIP")}')"
  printf '%-16s %12.4f %12.4f %10.4f %10.4f %8s\n' "$metric" "$bmed" "$cmed" "$ratio" "$worst" "$decision"
  if [ "$decision" != "PASS" ]; then
    failed=1
  fi
done

echo "Each pair is native/source/source/native or its reverse, summed before ratio."
echo "All timed legs use per-thread CPU time. Retention also requires an independent repeat."
if [ "$failed" -ne 0 ]; then
  exit 3
fi
