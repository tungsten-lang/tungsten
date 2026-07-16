#!/usr/bin/env bash
# Relaxed true-public IC-vs-source gate for five BigInt representation leaves.
#
# STATIC_ONLY=1 (the default while another benchmark lane is active) performs
# only the production-shape/harness audit. STATIC_ONLY=0 CHECK_ONLY=1 builds a
# matched-root baseline/candidate compiler pair and runs every semantic/WIRE/
# LLVM/interpreter gate. The timed mode always performs two independently
# rebuilt 10-observation campaigns and
# retains a method only when every one of its input strata is <= 1.10 in both.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CANDIDATE_ROOT="${CANDIDATE_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
BASELINE_ROOT="${BASELINE_ROOT:-/tmp/tungsten-bigint-predicate-relaxed-baseline}"
BOOTSTRAP_COMPILER="${BOOTSTRAP_COMPILER:-/Users/erik/tungsten/bin/tungsten-compiler}"
STATIC_ONLY="${STATIC_ONLY:-1}"
CHECK_ONLY="${CHECK_ONLY:-1}"
RUNS="${RUNS:-10}"
ITERS="${ITERS:-10000000}"
WARMUP="${WARMUP:-250000}"
GATE="${GATE:-1.10}"
ONLY="${ONLY:-}"

case "$STATIC_ONLY" in 0|1) ;; *) echo "STATIC_ONLY must be 0 or 1" >&2; exit 2 ;; esac
case "$CHECK_ONLY" in 0|1) ;; *) echo "CHECK_ONLY must be 0 or 1" >&2; exit 2 ;; esac
case "$RUNS" in ''|*[!0-9]*) echo "RUNS must be an even integer from 8 through 12" >&2; exit 2 ;; esac
if [ "$RUNS" -lt 8 ] || [ "$RUNS" -gt 12 ] || [ $((RUNS % 2)) -ne 0 ]; then
  echo "RUNS must be an even integer from 8 through 12" >&2
  exit 2
fi
for value in "$ITERS" "$WARMUP"; do
  case "$value" in ''|*[!0-9]*|0) echo "ITERS/WARMUP must be positive integers" >&2; exit 2 ;; esac
done
if [ "$GATE" != "1.10" ]; then
  echo "the relaxed retention gate is fixed at 1.10" >&2
  exit 2
fi

BASELINE_ROOT="$(cd "$BASELINE_ROOT" && pwd)"
CANDIDATE_ROOT="$(cd "$CANDIDATE_ROOT" && pwd)"
if [ "$BASELINE_ROOT" = "$CANDIDATE_ROOT" ]; then
  echo "baseline and candidate roots must differ" >&2
  exit 2
fi
if [ "$(git -C "$BASELINE_ROOT" rev-parse HEAD)" != "$(git -C "$CANDIDATE_ROOT" rev-parse HEAD)" ]; then
  echo "baseline/candidate HEAD mismatch" >&2
  exit 1
fi

DRIVER_REL="benchmarks/runtime_ports/bigint_predicate_relaxed_public.w"
REF_REL="benchmarks/runtime_ports/bigint_predicate_relaxed_ref.c"
AUTO_REL="benchmarks/runtime_ports/bigint_predicate_relaxed_autoload.w"
INTERP_REL="benchmarks/runtime_ports/bigint_predicate_relaxed_interpreter.w"

echo "Auditing exact production shape and dormant benchmark protocol..."
python3 - "$BASELINE_ROOT" "$CANDIDATE_ROOT" "$DRIVER_REL" "$REF_REL" "$AUTO_REL" "$INTERP_REL" <<'PY'
from pathlib import Path
import re
import subprocess
import sys

base, cand = map(Path, sys.argv[1:3])
driver_rel, ref_rel, auto_rel, interp_rel = sys.argv[3:7]

core = (cand / "core/numeric/big_int.w").read_text()
for body in ("zero?", "even?", "odd?", "negative?", "positive?"):
    if len(re.findall(rf"^  -> {re.escape(body)}$", core, re.M)) != 1:
        raise SystemExit(f"BigInt source body missing/duplicated: {body}")
if "    i32 length\n" not in core or "    u64 limb0\n" not in core:
    raise SystemExit("BigInt candidate lacks signed i32 length / explicit u64 limb0 view")
if core.count("$length ## i64") != 5 or core.count("$limb0 ## u64") != 2:
    raise SystemExit("predicate views must keep signed length/raw limb types explicit")
if len(re.findall(r"^  -> to_i$", core, re.M)) != 1:
    raise SystemExit("retained BigInt#to_i source body missing/duplicated")

brt = (base / "runtime/runtime.c").read_text()
crt = (cand / "runtime/runtime.c").read_text()
preds = ["zero_q", "even_q", "odd_q", "negative_q", "positive_q"]
for pred in preds:
    marker = f"static WValue w_ic_bigint_{pred}("
    if brt.count(marker) != 1 or marker in crt:
        raise SystemExit(f"handler transform mismatch for {pred}")
to_i_marker = "static WValue w_ic_bigint_to_i("
if brt.count(to_i_marker) != 1 or to_i_marker in crt:
    raise SystemExit("integrated BigInt#to_i handler transform mismatch")

def section(text, start, end):
    a = text.index(start)
    b = text.index(end, a)
    return text[a:b]

def names(text, table=False):
    if table:
        return re.findall(r"\{0, (w_ic_bigint_[a-z0-9_]+)\}", text)
    return re.findall(r"= (WN_[a-z0-9_]+);", text)

btable = names(section(brt, "static WICEntry w_ic_bigint_table", "static WICEntry w_ic_channel_table"), True)
ctable = names(section(crt, "static WICEntry w_ic_bigint_table", "static WICEntry w_ic_channel_table"), True)
removed_handlers = {f"w_ic_bigint_{p}" for p in preds} | {"w_ic_bigint_to_i"}
if [x for x in btable if x not in removed_handlers] != ctable:
    raise SystemExit("integrated BigInt IC table is not baseline minus identity and five predicates")

binit = names(section(brt, "/* Bigint (Phase 7+m) */", "/* Channel (Phase 7+m) */"))
cinit = names(section(crt, "/* Bigint (Phase 7+m) */", "/* Channel (Phase 7+m) */"))
removed_names = {"WN_to_i", "WN_zero_q", "WN_even_q", "WN_odd_q", "WN_negative_q", "WN_positive_q"}
if [x for x in binit if x not in removed_names] != cinit:
    raise SystemExit("integrated BigInt IC names are not baseline minus identity and five predicates")

loader = (cand / "compiler/lib/loader.w").read_text()
if loader.count("@bigint_predicates_unresolved") < 3 or 'consider_autoload_name("BigInt"' not in loader:
    raise SystemExit("sound one-shot BigInt predicate autoload trigger missing")
if '    "loader-ast-v16"\n' not in loader:
    raise SystemExit("integrated loader cache epoch is not v16")
interp = (cand / "compiler/lib/interpreter.w").read_text()
if 'cname == "BigInt"' not in interp or 'name in ("length" "limb0")' not in interp:
    raise SystemExit("narrow interpreter BigInt view-field allowlist missing")
for snippet in (
    'strcmp(name, "length")',
    'strcmp(name, "limb0")',
    'return b->size == 0 ? w_int(0) : w_u64(b->limbs[0]);',
):
    if snippet not in crt:
        raise SystemExit(f"runtime BigInt interpreter bridge missing: {snippet}")

driver = (cand / driver_rel).read_text()
if "use core/" in driver:
    raise SystemExit("public driver must test autoload and contain no core use")
if driver.count('ccall("w_bigpred_thread_cpu_ns")') != 10:
    raise SystemExit("five timing bodies must each take two direct thread-CPU timestamps")
for pred in ("zero", "even", "odd", "negative", "positive"):
    sig = f"-> time_{pred}(values, iters, run_id)"
    if driver.count(sig) != 1:
        raise SystemExit(f"non-memoizable timing signature missing: {sig}")
    direct = f"wvalue_bits(values[i & CORPUS_MASK].{pred}?)"
    if direct not in driver:
        raise SystemExit(f"{pred}? checksum does not consume Bool WValue bits directly")
if re.search(r"result\s*=\s*[^\n]*\.(zero|even|odd|negative|positive)\?", driver):
    raise SystemExit("predicate result assignment risks the known BigInt/raw-inference bug")

autoload_driver = (cand / auto_rel).read_text()
if "use core/" in autoload_driver:
    raise SystemExit("autoload driver must contain no core use")
for call in ("one.zero?", "one.even?", "odd.odd?", "negative.negative?", "negative.positive?", "multi.even?", "multi.positive?"):
    if call not in autoload_driver:
        raise SystemExit(f"autoload driver is missing public predicate call: {call}")

interp_driver = (cand / interp_rel).read_text()
if "use core/" in interp_driver:
    raise SystemExit("interpreter driver must exercise loader behavior and contain no core use")
if "undefined method 'each'" in interp_driver:
    raise SystemExit("tree-walker driver must not expect compiled result-iteration errors")
for snippet in ("hits[0] += 1", 'check("block ignored [methods[i]]", hits[0], 0)', "ignored blocks"):
    if snippet not in interp_driver:
        raise SystemExit(f"tree-walker ignored-block compatibility gate missing: {snippet}")

ref = (cand / ref_rel).read_text()
for assertion in ("offsetof(WBigint, size) == 4", "offsetof(WBigint, cap) == 8", "offsetof(WBigint, limbs) == 16"):
    if assertion not in ref:
        raise SystemExit(f"ABI assertion missing: {assertion}")
if ref.count("clock_gettime(CLOCK_THREAD_CPUTIME_ID, &ts)") != 1:
    raise SystemExit("timing reference must use exactly one thread-CPU clock primitive")
print("static audit: ok (five predicate and identity IC removals, direct view bodies, sound autoload/interpreter bridges, ABI and non-memoized Bool-bit timing)")
PY

all_strata=(
  zero.zero_nostorage zero.zero_spare zero.one zero.multi
  even.zero_nostorage even.zero_spare even.one_even even.one_odd even.multi_even even.multi_odd
  odd.zero_nostorage odd.zero_spare odd.one_even odd.one_odd odd.multi_even odd.multi_odd
  negative.zero negative.one_positive negative.one_negative negative.multi_positive negative.multi_negative
  positive.zero positive.one_positive positive.one_negative positive.multi_positive positive.multi_negative
)
strata=("${all_strata[@]}")
if [ -n "$ONLY" ]; then
  found=0
  for stratum in "${all_strata[@]}"; do
    if [ "$stratum" = "$ONLY" ]; then found=1; fi
  done
  if [ "$found" -ne 1 ]; then
    echo "ONLY must name one complete predicate/input stratum" >&2
    exit 2
  fi
  strata=("$ONLY")
fi

if [ "$STATIC_ONLY" = 1 ]; then
  echo "STATIC_ONLY=1: no compiler, linker, generated program, or timing process was started."
  exit 0
fi
if [ ! -x "$BOOTSTRAP_COMPILER" ]; then
  echo "BOOTSTRAP_COMPILER must be one executable used for both fresh campaigns" >&2
  exit 2
fi
BOOTSTRAP_COMPILER="$(cd "$(dirname "$BOOTSTRAP_COMPILER")" && pwd)/$(basename "$BOOTSTRAP_COMPILER")"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-bigint-predicate-relaxed.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/shared"
cp "$CANDIDATE_ROOT/$DRIVER_REL" "$TMP/shared/public.w"
cp "$CANDIDATE_ROOT/$REF_REL" "$TMP/shared/ref.c"
cp "$CANDIDATE_ROOT/$AUTO_REL" "$TMP/shared/autoload.w"
cp "$CANDIDATE_ROOT/$INTERP_REL" "$TMP/shared/interpreter.w"

hash_file() {
  shasum -a 256 "$1" | awk '{print $1}'
}

wire_body() {
  local wire="$1" fn="$2"
  sed -n "/^function $fn(/,/^$/p" "$wire"
}
require_wire() {
  local wire="$1" fn="$2" pattern="$3"
  if ! wire_body "$wire" "$fn" | grep -Eq "$pattern"; then
    echo "WIRE check failed: $fn lacks /$pattern/" >&2
    exit 1
  fi
}
reject_wire() {
  local wire="$1" fn="$2" pattern="$3"
  if wire_body "$wire" "$fn" | grep -Eq "$pattern"; then
    echo "WIRE check failed: $fn contains /$pattern/" >&2
    exit 1
  fi
}

build_trial_compiler() {
  local campaign="$1" label="$2" root="$3" out="$4"
  echo "Building $label compiler for campaign $campaign (setup; untimed)..." >&2
  (
    cd "$root"
    TUNGSTEN_ROOT="$root" \
    TUNGSTEN_CACHE_DIR="$TMP/compiler-cache-$campaign-$label" \
      "$BOOTSTRAP_COMPILER" compile compiler/tungsten.w --release --out "$out" >/dev/null
  )
  test -x "$out"
  echo "campaign $campaign $label compiler SHA-256 $(hash_file "$out")" >&2
}

compile_campaign() {
  local campaign="$1" base_compiler="$2" cand_compiler="$3" dir="$TMP/campaign-$1"
  mkdir -p "$dir"
  (
    cd "$BASELINE_ROOT"
    TUNGSTEN_ROOT="$BASELINE_ROOT" TUNGSTEN_CACHE_DIR="$dir/base-wire-cache" \
    TUNGSTEN_C_INCLUDES="$TMP/shared/ref.c" \
      "$base_compiler" compile "$TMP/shared/public.w" --emit-wire > "$dir/base.wire"
    TUNGSTEN_ROOT="$BASELINE_ROOT" TUNGSTEN_CACHE_DIR="$dir/base-build-cache" \
    TUNGSTEN_C_INCLUDES="$TMP/shared/ref.c" TUNGSTEN_LL_PATH="$dir/base.ll" \
      "$base_compiler" compile "$TMP/shared/public.w" --release --out "$dir/base" >/dev/null
  )
  (
    cd "$CANDIDATE_ROOT"
    TUNGSTEN_ROOT="$CANDIDATE_ROOT" TUNGSTEN_CACHE_DIR="$dir/cand-wire-cache" \
    TUNGSTEN_C_INCLUDES="$TMP/shared/ref.c" \
      "$cand_compiler" compile "$TMP/shared/public.w" --emit-wire > "$dir/cand.wire"
    TUNGSTEN_ROOT="$CANDIDATE_ROOT" TUNGSTEN_CACHE_DIR="$dir/cand-build-cache" \
    TUNGSTEN_C_INCLUDES="$TMP/shared/ref.c" TUNGSTEN_LL_PATH="$dir/cand.ll" \
      "$cand_compiler" compile "$TMP/shared/public.w" --release --out "$dir/cand" >/dev/null
    TUNGSTEN_ROOT="$CANDIDATE_ROOT" TUNGSTEN_CACHE_DIR="$dir/auto-wire-cache" \
      "$cand_compiler" compile "$TMP/shared/autoload.w" --emit-wire > "$dir/autoload.wire"
    TUNGSTEN_ROOT="$CANDIDATE_ROOT" TUNGSTEN_CACHE_DIR="$dir/auto-build-cache" \
      "$cand_compiler" compile "$TMP/shared/autoload.w" --release --out "$dir/autoload" >/dev/null
  )
  for artifact in "$dir/base" "$dir/cand" "$dir/autoload"; do test -x "$artifact"; done
  for artifact in "$dir/base.wire" "$dir/cand.wire" "$dir/autoload.wire" \
                  "$dir/base.ll" "$dir/cand.ll" "$dir/base.sidemap" "$dir/cand.sidemap"; do
    test -s "$artifact"
  done
}

verify_campaign() {
  local campaign="$1" base_compiler="$2" cand_compiler="$3" dir="$TMP/campaign-$1"
  local methods=(zero_Q even_Q odd_Q negative_Q positive_Q)
  for method in "${methods[@]}"; do
    local fn="__w_BigInt_${method}__a1"
    if [ -n "$(wire_body "$dir/base.wire" "$fn")" ]; then
      echo "baseline unexpectedly emitted source BigInt predicate $fn; native IC comparison is contaminated" >&2
      exit 1
    fi
    require_wire "$dir/cand.wire" "$fn" 'view_load_field'
    reject_wire "$dir/cand.wire" "$fn" 'call_method_i64|call_direct_i64 .*@(w_eq|w_mod|w_lt|w_gt)'
    require_wire "$dir/autoload.wire" "$fn" 'view_load_field'
  done
  for fn in __w_time_zero __w_time_even __w_time_odd __w_time_negative __w_time_positive; do
    require_wire "$dir/cand.wire" "$fn" 'call_method_i64'
    require_wire "$dir/base.wire" "$fn" 'call_method_i64'
    if ! diff -u <(wire_body "$dir/base.wire" "$fn") <(wire_body "$dir/cand.wire" "$fn") >/dev/null; then
      echo "caller WIRE differs across matched roots: $fn" >&2
      diff -u <(wire_body "$dir/base.wire" "$fn") <(wire_body "$dir/cand.wire" "$fn") >&2 || true
      exit 1
    fi
  done
  require_wire "$dir/cand.wire" __w_BigInt_even_Q__a1 'and_i64'
  require_wire "$dir/cand.wire" __w_BigInt_odd_Q__a1 'and_i64'

  # Resolve content-hashed source methods and prove signed i32 extension plus
  # direct offset-16 u64 loads in the actual LLVM used by the benchmark.
  python3 - "$dir/cand.ll" "$dir/cand.sidemap" <<'PY'
from pathlib import Path
import json
import re
import sys

ll_path, map_path = map(Path, sys.argv[1:])
ll = ll_path.read_text()
data = json.loads(map_path.read_text())

def symbols(original):
    out = set()
    for entry in data.get("hashes", {}).values():
        if any(item.get("symbol") == original for item in entry.get("originals", [])):
            out.add(entry["symbol"])
    return out

def body(symbol):
    m = re.search(
        rf"^define [^\n]* @{re.escape(symbol)}\(i64 %__self\)[^\n]*\{{\n.*?^}}$",
        ll,
        re.M | re.S,
    )
    if not m:
        raise SystemExit(f"missing LLVM definition for {symbol}")
    return m.group(0)

originals = {
    "zero": "__w_BigInt_zero_Q__a1",
    "even": "__w_BigInt_even_Q__a1",
    "odd": "__w_BigInt_odd_Q__a1",
    "negative": "__w_BigInt_negative_Q__a1",
    "positive": "__w_BigInt_positive_Q__a1",
}
for name, original in originals.items():
    syms = symbols(original)
    if len(syms) != 1:
        raise SystemExit(f"{original}: expected one content-hash symbol, got {syms}")
    text = body(next(iter(syms)))
    for required in ("getelementptr i8", "i64 4", "load i32", "sext i32"):
        if required not in text:
            raise SystemExit(f"{name} lacks signed length load component {required!r}")
    if re.search(r"call .*@(w_eq|w_mod|w_lt|w_gt|w_cached_call)", text):
        raise SystemExit(f"{name} retained a numeric/method call")
    if name in ("even", "odd"):
        for required in ("i64 16", "load i64", "and i64"):
            if required not in text:
                raise SystemExit(f"{name} lacks direct limb0 component {required!r}")
print("LLVM: ok (signed offset-4 i32 length and direct offset-16 u64 limb0; no numeric dispatch)")
PY

  "$dir/base" check > "$dir/base.check"
  "$dir/cand" check > "$dir/cand.check"
  diff -u "$dir/base.check" "$dir/cand.check"
  cat "$dir/cand.check"

  for method in zero even odd negative positive; do
    for label in base cand; do
      set +e
      "$dir/$label" block-fatal "$method" > "$dir/$label-$method-block.out" 2> "$dir/$label-$method-block.err"
      rc=$?
      set -e
      if [ "$rc" -eq 0 ] || ! grep -Fq "undefined method 'each'" "$dir/$label-$method-block.err"; then
        echo "$label $method? block fatal surface changed" >&2
        exit 1
      fi
    done
    base_error="$(grep -m1 "undefined method 'each'" "$dir/base-$method-block.err")"
    cand_error="$(grep -m1 "undefined method 'each'" "$dir/cand-$method-block.err")"
    if [ "$base_error" != "$cand_error" ]; then
      echo "$method? block error differs across roots" >&2
      exit 1
    fi
  done

  "$dir/autoload" > "$dir/autoload.out"
  grep -Fq "autoload: ok" "$dir/autoload.out"
  cat "$dir/autoload.out"

  echo "Checking candidate tree-walker bridge (campaign $campaign)..." >&2
  (
    cd "$CANDIDATE_ROOT"
    TUNGSTEN_ROOT="$CANDIDATE_ROOT" "$cand_compiler" run "$TMP/shared/interpreter.w"
  )
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

max_stream() {
  sort -n | awk 'END { if (NR == 0) exit 1; print $1 }'
}

run_leg() {
  local raw="$1" campaign="$2" sample="$3" leg="$4" label="$5" bin="$6" stratum="$7"
  "$bin" bench "$stratum" "$ITERS" "$WARMUP" |
    awk -F'|' -v c="$campaign" -v s="$sample" -v l="$leg" -v label="$label" \
      '$1 == "RESULT" {print c "|" s "|" l "|" label "|" $0}' >> "$raw"
}

time_campaign() {
  local campaign="$1" dir="$TMP/campaign-$1" raw="$TMP/results-$1.txt"
  : > "$raw"
  local sample=0
  while [ "$sample" -lt "$RUNS" ]; do
    for stratum in "${strata[@]}"; do
      echo "campaign $campaign $stratum sample $((sample + 1))/$RUNS x $ITERS" >&2
      if [ $((sample % 2)) -eq 0 ]; then
        run_leg "$raw" "$campaign" "$sample" 1 BASE "$dir/base" "$stratum"
        run_leg "$raw" "$campaign" "$sample" 2 CAND "$dir/cand" "$stratum"
        run_leg "$raw" "$campaign" "$sample" 3 CAND "$dir/cand" "$stratum"
        run_leg "$raw" "$campaign" "$sample" 4 BASE "$dir/base" "$stratum"
      else
        run_leg "$raw" "$campaign" "$sample" 1 CAND "$dir/cand" "$stratum"
        run_leg "$raw" "$campaign" "$sample" 2 BASE "$dir/base" "$stratum"
        run_leg "$raw" "$campaign" "$sample" 3 BASE "$dir/base" "$stratum"
        run_leg "$raw" "$campaign" "$sample" 4 CAND "$dir/cand" "$stratum"
      fi
    done
    sample=$((sample + 1))
  done

  printf '\ncampaign %s\n' "$campaign"
  printf '%-30s %11s %11s %9s %9s %8s\n' stratum native_ns source_ns pair_med max_pair gate
  local failed=0
  for stratum in "${strata[@]}"; do
    base_checksums="$(awk -F'|' -v m="$stratum" '$4=="BASE" && $6==m {print $9}' "$raw" | sort -u)"
    cand_checksums="$(awk -F'|' -v m="$stratum" '$4=="CAND" && $6==m {print $9}' "$raw" | sort -u)"
    if [ "$base_checksums" != "$cand_checksums" ]; then
      echo "checksum mismatch for $stratum campaign $campaign" >&2
      exit 1
    fi
    base_ns="$(awk -F'|' -v m="$stratum" '$4=="BASE" && $6==m {print $7 / $8}' "$raw" | median_stream)"
    cand_ns="$(awk -F'|' -v m="$stratum" '$4=="CAND" && $6==m {print $7 / $8}' "$raw" | median_stream)"
    ratios="$(awk -F'|' -v m="$stratum" '
      $6==m && $4=="BASE" { base[$2] += $7 }
      $6==m && $4=="CAND" { cand[$2] += $7 }
      END { for (s in base) if (s in cand) print cand[s] / base[s] }
    ' "$raw")"
    ratio="$(printf '%s\n' "$ratios" | median_stream)"
    max_pair="$(printf '%s\n' "$ratios" | max_stream)"
    # Parenthesize the ternary: BSD awk otherwise parses `print r <= ...` as
    # an output-redirection expression instead of a comparison to print.
    decision="$(awk -v r="$ratio" 'BEGIN {print (r <= 1.10 ? "PASS" : "SKIP")}')"
    if [ "$decision" != PASS ]; then failed=1; fi
    printf '%-30s %11.3f %11.3f %9.3f %9.3f %8s\n' \
      "$stratum" "$base_ns" "$cand_ns" "$ratio" "$max_pair" "$decision"
  done
  if [ "$failed" -ne 0 ]; then
    overall_failed=1
  fi
}

campaigns=1
if [ "$CHECK_ONLY" = 0 ]; then campaigns=2; fi
overall_failed=0
campaign=1
while [ "$campaign" -le "$campaigns" ]; do
  base_compiler="$TMP/baseline-compiler-$campaign"
  cand_compiler="$TMP/candidate-compiler-$campaign"
  build_trial_compiler "$campaign" baseline "$BASELINE_ROOT" "$base_compiler"
  build_trial_compiler "$campaign" candidate "$CANDIDATE_ROOT" "$cand_compiler"
  compile_campaign "$campaign" "$base_compiler" "$cand_compiler"
  verify_campaign "$campaign" "$base_compiler" "$cand_compiler"
  if [ "$CHECK_ONLY" = 0 ]; then
    time_campaign "$campaign"
  fi
  campaign=$((campaign + 1))
done

if [ "$CHECK_ONLY" = 1 ]; then
  echo "CHECK_ONLY=1: matched-root compiler pair, identical caller WIRE, true public native/source binaries, exact layouts/Bool bits/extras/block errors, autoload, interpreter bridge, LLVM signedness, and release/LTO gates passed; timings skipped."
  exit 0
fi

echo "Two fresh matched-root compiler-pair campaigns; each observation is alternating ABBA/BAAB under CLOCK_THREAD_CPUTIME_ID. Retention requires every predicate/input median <= 1.10 in both campaigns; max_pair is diagnostic."
if [ "$overall_failed" -ne 0 ]; then
  echo "Gate failed: retain the native IC for each method with any failing stratum/repeat." >&2
  exit 3
fi
