#!/usr/bin/env bash
# Matched-root correctness, WIRE, release/LTO, and balanced thread-CPU gate for
# the relaxed Mmap#size revisit.

set -euo pipefail

BASELINE_ROOT="${BASELINE_ROOT:-/tmp/tungsten-mmap-size-relaxed-baseline}"
CANDIDATE_ROOT="${CANDIDATE_ROOT:-/tmp/tungsten-mmap-size-relaxed-candidate}"
CANDIDATE_COMPILER="${CANDIDATE_COMPILER:-$CANDIDATE_ROOT/bin/tungsten-compiler-mmap-relaxed}"
CHECK_ONLY="${CHECK_ONLY:-1}"
GATE="${GATE:-1.10}"
RUNS="${RUNS:-10}"
INLINE_ITERS="${INLINE_ITERS:-50000000}"
OVERFLOW_ITERS="${OVERFLOW_ITERS:-2000000}"
RESULTS_OUT="${RESULTS_OUT:-}"
ARTIFACT_DIR="${ARTIFACT_DIR:-}"

case "$CHECK_ONLY" in
  0|1) ;;
  *) echo "CHECK_ONLY must be 0 or 1" >&2; exit 2 ;;
esac
if [ "$GATE" != "1.10" ]; then
  echo "relaxed retention gate is fixed at 1.10" >&2
  exit 2
fi
case "$RUNS" in
  ''|*[!0-9]*) echo "RUNS must be an integer" >&2; exit 2 ;;
esac
if [ "$RUNS" -lt 8 ] || [ "$RUNS" -gt 12 ] || [ $((RUNS % 2)) -ne 0 ]; then
  echo "RUNS must be an even integer from 8 through 12" >&2
  exit 2
fi
for value in "$INLINE_ITERS" "$OVERFLOW_ITERS"; do
  case "$value" in
    ''|*[!0-9]*|0) echo "iteration counts must be positive integers" >&2; exit 2 ;;
  esac
done

SRC="benchmarks/runtime_ports/mmap_size_relaxed_public.w"
REF="benchmarks/runtime_ports/mmap_size_relaxed_ref.c"
CLOCK="benchmarks/runtime_ports/mmap_size_relaxed_thread_clock.c"
for rel in "$SRC" "$REF" "$CLOCK"; do
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

if rg -q 'w_ic_mmap_size' "$CANDIDATE_ROOT/runtime/runtime.c"; then
  echo "candidate still contains Mmap#size native IC" >&2
  exit 1
fi

# Removing one row shifts every following slot. Compare both the wrapper table
# and its initialized method-name sequence against baseline-minus-size so a
# merge cannot silently drop, duplicate, or misalign a retained primitive.
baseline_mmap_ic="$({
  sed -n '/^static WICEntry w_ic_mmap_table/,/^};/p' \
    "$BASELINE_ROOT/runtime/runtime.c" |
    rg -o 'w_ic_mmap_[a-z0-9_]+' |
    rg -v '^w_ic_mmap_size$'
} || true)"
candidate_mmap_ic="$({
  sed -n '/^static WICEntry w_ic_mmap_table/,/^};/p' \
    "$CANDIDATE_ROOT/runtime/runtime.c" |
    rg -o 'w_ic_mmap_[a-z0-9_]+'
} || true)"
if [ -z "$baseline_mmap_ic" ] || [ "$candidate_mmap_ic" != "$baseline_mmap_ic" ]; then
  echo "candidate Mmap IC table is not baseline-minus-size" >&2
  exit 1
fi

baseline_mmap_names="$({
  sed -n '/\/\* Mmap (Phase 7+o) \*\//,/\/\* StringBuffer/p' \
    "$BASELINE_ROOT/runtime/runtime.c" |
    rg -o 'WN_[a-z0-9_]+' |
    rg -v '^WN_size$'
} || true)"
candidate_mmap_names="$({
  sed -n '/\/\* Mmap (Phase 7+o) \*\//,/\/\* StringBuffer/p' \
    "$CANDIDATE_ROOT/runtime/runtime.c" |
    rg -o 'WN_[a-z0-9_]+'
} || true)"
if [ -z "$baseline_mmap_names" ] || [ "$candidate_mmap_names" != "$baseline_mmap_names" ]; then
  echo "candidate Mmap IC names are not baseline-minus-size" >&2
  exit 1
fi

require_static() {
  rel="$1"
  pattern="$2"
  label="$3"
  if ! rg -q "$pattern" "$CANDIDATE_ROOT/$rel"; then
    echo "candidate static audit lacks $label: $rel /$pattern/" >&2
    exit 1
  fi
}

require_static core/tungsten.w 'auto :Mmap,.*"mmap"' 'Mmap autoload registry'
require_static core/file.w '^use core/mmap$' 'core/file compatibility import'
require_static core/mmap.w '^  - data \(WMmap\)$' 'WMmap source view'
require_static compiler/lib/loader.w \
  'call_receiver.name == "File" && call_name == "mmap"' \
  'exact File.mmap autoload trigger'
require_static compiler/lib/loader.w 'if name == "__w_file_mmap"' \
  'native-return autoload map'
require_static compiler/lib/interpreter.w 'when "__w_file_mmap"' \
  'tree-walker mmap constructor bridge'
require_static compiler/lib/interpreter.w 'cname == "Mmap"' \
  'tree-walker WMmap field allowlist'
require_static compiler/lib/lowering/types.w '"Mmap".*=> 0x91' \
  'generic-object dispatch key'
require_static runtime/runtime.c 'w_is_mmap\(v\).*"Mmap"' \
  'runtime type discovery'
require_static runtime/runtime.c 'w_is_mmap\(recv\)' \
  'interpreter native-field bridge'

if [ ! -x "$CANDIDATE_COMPILER" ]; then
  echo "common trial compiler is absent; rebuild is intentionally deferred pending authorization" >&2
  exit 2
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-mmap-size-relaxed.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

compile_trial() {
  label="$1"
  root="$2"
  compiler="$3"
  (
    cd "$root"
    includes="$root/$CLOCK:$root/$REF"
    TUNGSTEN_ROOT="$root" TUNGSTEN_C_INCLUDES="$includes" \
      "$compiler" compile "$root/$SRC" --emit-wire > "$TMP/$label.wire"
    TUNGSTEN_ROOT="$root" TUNGSTEN_C_INCLUDES="$includes" \
      "$compiler" compile "$root/$SRC" --release --out "$TMP/$label" >/dev/null
  )
}

# Use one candidate compiler for both roots. Mmap's 0x91 registration is the
# compiler fix under audit and does not exist in the installed bootstrap;
# sharing the rebuilt artifact keeps all generated call-site code identical.
compile_trial baseline "$BASELINE_ROOT" "$CANDIDATE_COMPILER"
compile_trial candidate "$CANDIDATE_ROOT" "$CANDIDATE_COMPILER"

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
    echo "WIRE check failed: $fn lacks /$pattern/ in $(basename "$wire")" >&2
    exit 1
  fi
}

reject_body() {
  wire="$1"
  fn="$2"
  pattern="$3"
  if wire_body "$wire" "$fn" | grep -Eq "$pattern"; then
    echo "WIRE check failed: $fn contains /$pattern/ in $(basename "$wire")" >&2
    exit 1
  fi
}

PUBLIC_FN="__w_Mmap_size__a1"
require_body "$TMP/baseline.wire" "$PUBLIC_FN" 'ret_i64 0'
reject_body  "$TMP/baseline.wire" "$PUBLIC_FN" 'view_load_field'
require_body "$TMP/candidate.wire" "$PUBLIC_FN" 'view_load_field'
require_body "$TMP/candidate.wire" "$PUBLIC_FN" 'ashr_i64'
require_body "$TMP/candidate.wire" "$PUBLIC_FN" 'icmp_i64'
require_body "$TMP/candidate.wire" "$PUBLIC_FN" 'call_direct_i64 .*@w_int'
require_body "$TMP/candidate.wire" "$PUBLIC_FN" 'and_i64'
require_body "$TMP/candidate.wire" "$PUBLIC_FN" 'or_i64'
reject_body  "$TMP/candidate.wire" "$PUBLIC_FN" 'call_method_i64|nanbox_bool|truthy_inline|shl_i64'
if [ "$(wire_body "$TMP/candidate.wire" "$PUBLIC_FN" | awk '/icmp_i64/ { n += 1 } END { print n + 0 }')" -ne 1 ]; then
  echo "optimized public Mmap#size must contain exactly one comparison" >&2
  exit 1
fi

"$TMP/baseline" check > "$TMP/baseline.check"
"$TMP/candidate" check > "$TMP/candidate.check"
cmp "$TMP/baseline.check" "$TMP/candidate.check"
cat "$TMP/candidate.check"

TUNGSTEN_ROOT="$CANDIDATE_ROOT" "$CANDIDATE_COMPILER" \
  compile "$CANDIDATE_ROOT/spec/compiler/mmap_size_relaxed_autoload_spec.w" \
  --release --out "$TMP/autoload" >/dev/null
"$TMP/autoload"
TUNGSTEN_ROOT="$CANDIDATE_ROOT" "$CANDIDATE_COMPILER" \
  compile "$CANDIDATE_ROOT/spec/compiler/mmap_size_relaxed_native_autoload_spec.w" \
  --release --out "$TMP/native-autoload" >/dev/null
"$TMP/native-autoload"
TUNGSTEN_ROOT="$CANDIDATE_ROOT" "$CANDIDATE_COMPILER" \
  run "$CANDIDATE_ROOT/spec/interpreter/mmap_size_relaxed_spec.w"

if [ -n "$ARTIFACT_DIR" ]; then
  mkdir -p "$ARTIFACT_DIR"
  cp "$TMP/baseline" "$TMP/candidate" "$TMP/baseline.wire" \
    "$TMP/candidate.wire" "$TMP/baseline.check" "$TMP/candidate.check" \
    "$ARTIFACT_DIR/"
fi

if [ "$CHECK_ONLY" = "1" ]; then
  echo "CHECK_ONLY=1: Mmap relaxed source/WIRE/exactness/autoload/interpreter audit passed; timings skipped."
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

  if [ "$parity" -eq 0 ]; then
    b1="$("$TMP/baseline" "$mode" "$iters")"
    c1="$("$TMP/candidate" "$mode" "$iters")"
    c2="$("$TMP/candidate" "$mode" "$iters")"
    b2="$("$TMP/baseline" "$mode" "$iters")"
  else
    c1="$("$TMP/candidate" "$mode" "$iters")"
    b1="$("$TMP/baseline" "$mode" "$iters")"
    b2="$("$TMP/baseline" "$mode" "$iters")"
    c2="$("$TMP/candidate" "$mode" "$iters")"
  fi

  for sample in "$b1" "$b2" "$c1" "$c2"; do
    if [ "$(sample_field "$sample" 2)" != "$metric" ]; then
      echo "unexpected sample label in $metric: $sample" >&2
      exit 1
    fi
  done

  checksum="$(sample_field "$b1" 5)"
  for sample in "$b2" "$c1" "$c2"; do
    if [ "$(sample_field "$sample" 5)" != "$checksum" ]; then
      echo "checksum mismatch in $metric" >&2
      exit 1
    fi
  done

  b1ns="$(sample_field "$b1" 3)"
  b2ns="$(sample_field "$b2" 3)"
  c1ns="$(sample_field "$c1" 3)"
  c2ns="$(sample_field "$c2" 3)"
  bsum="$(awk -v a="$b1ns" -v b="$b2ns" 'BEGIN {printf "%.0f", a+b}')"
  csum="$(awk -v a="$c1ns" -v b="$c2ns" 'BEGIN {printf "%.0f", a+b}')"
  ratio="$(awk -v c="$csum" -v b="$bsum" 'BEGIN {printf "%.12f", c/b}')"
  bavg="$(awk -v n="$bsum" -v calls="$iters" 'BEGIN {printf "%.12f", n/(2*calls)}')"
  cavg="$(awk -v n="$csum" -v calls="$iters" 'BEGIN {printf "%.12f", n/(2*calls)}')"
  echo "PAIR|$metric|$bavg|$cavg|$ratio|$checksum|$b1ns|$b2ns|$c1ns|$c2ns"
}

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

RAW="$TMP/results.txt"
compiler_sha="$(shasum -a 256 "$CANDIDATE_COMPILER" | awk '{print $1}')"
sidemap_sha="missing"
if [ -f "$CANDIDATE_COMPILER.sidemap" ]; then
  sidemap_sha="$(shasum -a 256 "$CANDIDATE_COMPILER.sidemap" | awk '{print $1}')"
fi
{
  echo "META|compiler_sha256|$compiler_sha"
  echo "META|sidemap_sha256|$sidemap_sha"
  echo "META|head|$candidate_head"
  echo "META|gate|$GATE"
  echo "META|runs|$RUNS"
  echo "META|inline_iters|$INLINE_ITERS"
  echo "META|overflow_iters|$OVERFLOW_ITERS"
} > "$RAW"

i=0
while [ "$i" -lt "$RUNS" ]; do
  parity=$((i % 2))
  echo "timed balanced pair $((i + 1))/$RUNS (parity $parity)" >&2
  if [ "$parity" -eq 0 ]; then
    run_pair mmap.size inline "$INLINE_ITERS" "$parity" >> "$RAW"
    run_pair mmap.overflow overflow "$OVERFLOW_ITERS" "$parity" >> "$RAW"
  else
    run_pair mmap.overflow overflow "$OVERFLOW_ITERS" "$parity" >> "$RAW"
    run_pair mmap.size inline "$INLINE_ITERS" "$parity" >> "$RAW"
  fi
  i=$((i + 1))
done

failed=0
printf '%-15s %11s %11s %11s %11s %11s %11s %11s %8s\n' \
  "stratum" "native med" "source med" "med ratio" "paired med" \
  "max pair" "max native" "max source" "gate"
for metric in mmap.size mmap.overflow; do
  if [ "$metric" = "mmap.size" ]; then
    calls="$INLINE_ITERS"
  else
    calls="$OVERFLOW_ITERS"
  fi
  bmed="$(awk -F'|' -v m="$metric" '$1 == "PAIR" && $2 == m {print $3}' "$RAW" | median_stream)"
  cmed="$(awk -F'|' -v m="$metric" '$1 == "PAIR" && $2 == m {print $4}' "$RAW" | median_stream)"
  ratio_medians="$(awk -v c="$cmed" -v b="$bmed" 'BEGIN {print c/b}')"
  paired_median="$(awk -F'|' -v m="$metric" '$1 == "PAIR" && $2 == m {print $5}' "$RAW" | median_stream)"
  max_pair="$(awk -F'|' -v m="$metric" '$1 == "PAIR" && $2 == m {if (!seen || $5 > max) max=$5; seen=1} END {if (seen) print max}' "$RAW")"
  max_native="$(awk -F'|' -v m="$metric" -v n="$calls" '$1 == "PAIR" && $2 == m {if ($7/n > max) max=$7/n; if ($8/n > max) max=$8/n} END {print max}' "$RAW")"
  max_source="$(awk -F'|' -v m="$metric" -v n="$calls" '$1 == "PAIR" && $2 == m {if ($9/n > max) max=$9/n; if ($10/n > max) max=$10/n} END {print max}' "$RAW")"
  decision="$(awk -v r="$paired_median" -v g="$GATE" 'BEGIN {print (r <= g ? "PASS" : "SKIP")}')"
  printf '%-15s %11.4f %11.4f %11.4f %11.4f %11.4f %11.4f %11.4f %8s\n' \
    "$metric" "$bmed" "$cmed" "$ratio_medians" "$paired_median" \
    "$max_pair" "$max_native" "$max_source" "$decision"
  echo "SUMMARY|$metric|$bmed|$cmed|$ratio_medians|$paired_median|$max_pair|$max_native|$max_source|$decision" >> "$RAW"
  if [ "$decision" != "PASS" ]; then
    failed=1
  fi
done

echo "Each pair is B/C/C/B or C/B/B/C and is summed before its W/C ratio."
echo "Metric order also alternates by pair; every timed leg uses per-thread CPU time."
if [ -n "$RESULTS_OUT" ]; then
  cp "$RAW" "$RESULTS_OUT"
  echo "Raw paired results: $RESULTS_OUT"
fi
if [ -n "$ARTIFACT_DIR" ]; then
  cp "$RAW" "$ARTIFACT_DIR/results.txt"
fi
if [ "$failed" -ne 0 ]; then
  exit 3
fi
