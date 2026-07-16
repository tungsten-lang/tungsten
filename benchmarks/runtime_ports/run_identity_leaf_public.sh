#!/usr/bin/env bash
# Relaxed production revisit for Float#to_f and BigInt#to_i.
#
# Default CHECK_ONLY=1 performs the matched-root build, bootstrap, autoload,
# interpreter, WIRE/LLVM, IC-reindex, and semantic proofs without timing. Set
# CHECK_ONLY=0 only when the shared benchmark lane is free. Every timed sample
# is a balanced native/source/source/native four-leg pair (or its reverse) and
# uses CLOCK_THREAD_CPUTIME_ID inside the workload. REPEAT=1 labels a fresh,
# independently rebuilt repeat; the same <= 1.10 policy applies to both runs.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CANDIDATE_ROOT="${CANDIDATE_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
BASELINE_ROOT="${BASELINE_ROOT:-/tmp/tungsten-identity-leaf-baseline}"
BOOTSTRAP_COMPILER="${BOOTSTRAP_COMPILER:-}"
SKIP_COMPILER_BUILD="${SKIP_COMPILER_BUILD:-0}"
STATIC_ONLY="${STATIC_ONLY:-0}"
BASELINE_COMPILER="${BASELINE_COMPILER:-}"
CANDIDATE_COMPILER="${CANDIDATE_COMPILER:-}"
CHECK_ONLY="${CHECK_ONLY:-1}"
REPEAT="${REPEAT:-0}"
RUNS="${RUNS:-10}"
ITERS="${ITERS:-40000000}"
WARMUP="${WARMUP:-1000000}"
GATE="${GATE:-1.10}"
ONLY="${ONLY:-}"

case "$CHECK_ONLY" in 0|1) ;; *) echo "CHECK_ONLY must be 0 or 1" >&2; exit 2 ;; esac
case "$REPEAT" in 0|1) ;; *) echo "REPEAT must be 0 or 1" >&2; exit 2 ;; esac
case "$SKIP_COMPILER_BUILD" in 0|1) ;; *) echo "SKIP_COMPILER_BUILD must be 0 or 1" >&2; exit 2 ;; esac
case "$STATIC_ONLY" in 0|1) ;; *) echo "STATIC_ONLY must be 0 or 1" >&2; exit 2 ;; esac
case "$RUNS" in ''|*[!0-9]*) echo "RUNS must be an even integer from 8 through 12" >&2; exit 2 ;; esac
if [ "$RUNS" -lt 8 ] || [ "$RUNS" -gt 12 ] || [ $((RUNS % 2)) -ne 0 ]; then
  echo "RUNS must be an even integer from 8 through 12" >&2
  exit 2
fi
for value in "$ITERS" "$WARMUP"; do
  case "$value" in ''|*[!0-9]*|0) echo "ITERS and WARMUP must be positive integers" >&2; exit 2 ;; esac
done
case "$ONLY" in ''|float|bigint) ;; *) echo "ONLY must be empty, float, or bigint" >&2; exit 2 ;; esac
if ! awk -v gate="$GATE" 'BEGIN { exit !(gate ~ /^[0-9]+([.][0-9]+)?$/ && gate > 0) }'; then
  echo "GATE must be a positive number" >&2
  exit 2
fi

BASELINE_ROOT="$(cd "$BASELINE_ROOT" && pwd)"
CANDIDATE_ROOT="$(cd "$CANDIDATE_ROOT" && pwd)"
if [ "$BASELINE_ROOT" = "$CANDIDATE_ROOT" ]; then
  echo "BASELINE_ROOT and CANDIDATE_ROOT must be distinct isolated roots" >&2
  exit 2
fi

baseline_head="$(git -C "$BASELINE_ROOT" rev-parse HEAD)"
candidate_head="$(git -C "$CANDIDATE_ROOT" rev-parse HEAD)"
if [ "$baseline_head" != "$candidate_head" ]; then
  echo "matched-root HEAD mismatch: $baseline_head vs $candidate_head" >&2
  exit 1
fi

# Audit the integrated identity leaves and their current loader/runtime shape.
# The shared candidate may contain unrelated in-progress ports, so this checks
# the relevant invariants exactly without requiring a five-file-only worktree.
python3 - "$BASELINE_ROOT" "$CANDIDATE_ROOT" <<'PY'
from pathlib import Path
import subprocess
import sys

base = Path(sys.argv[1])
cand = Path(sys.argv[2])

if subprocess.run(["git", "-C", str(base), "diff", "--quiet", "HEAD", "--"]).returncode != 0:
    raise SystemExit("baseline has tracked changes")

def require_once(text, block, label):
    count = text.count(block)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")

float_text = (cand / "core/numeric/float.w").read_text()
float_body = """+ Float < Real

  # Conversion to Float is receiver identity. Preserve every valid Float
  # WValue bit pattern, including signed zero and dispatch-safe raw NaNs.
  -> to_f
    self
"""
require_once(float_text, float_body, "Float#to_f identity body")
if float_text.count("\n  -> to_f\n") != 1:
    raise SystemExit("Float#to_f must have exactly one source definition")

bigint_text = (cand / "core/numeric/big_int.w").read_text()
if not bigint_text.startswith("use core/numeric/int\n\n+ BigInt < Int\n"):
    raise SystemExit("BigInt source is missing its explicit Int bootstrap dependency")
if "    u64 limb0\n" not in bigint_text:
    raise SystemExit("BigInt source is missing the retained explicit first-limb view")
bigint_body = """  # Conversion to the already-integral representation is receiver identity.
  # Do not normalize: callers can observe exact heap identity.
  -> to_i
    self
"""
require_once(bigint_text, bigint_body, "BigInt#to_i identity body")
if bigint_text.count("\n  -> to_i\n") != 1:
    raise SystemExit("BigInt#to_i must have exactly one source definition")

compiler_text = (cand / "compiler/tungsten.w").read_text()
compiler_prefix = """use core/integer
use core/numeric/float
use core/numeric/big_int
"""
if not compiler_text.startswith(compiler_prefix):
    raise SystemExit("compiler bootstrap is missing the Float/BigInt source anchors")
for anchor in ("use core/numeric/float\n", "use core/numeric/big_int\n"):
    require_once(compiler_text, anchor, f"bootstrap anchor {anchor.strip()}")

loader_text = (cand / "compiler/lib/loader.w").read_text()
for block, label in (
    ('    @float_source_method_unresolved = defined["Float"] != true && registry["Float"] != nil && @autoload_loaded["Float"] != true\n',
     "Float source-method autoload flag"),
    ('    @bigint_to_i_unresolved = defined["BigInt"] != true && registry["BigInt"] != nil && @autoload_loaded["BigInt"] != true\n',
     "BigInt#to_i autoload flag"),
    ('      if @float_source_method_unresolved && call_name in ("to_f" "abs" "nan?" "infinite?" "sqrt" "ceil" "floor" "round" "sq")\n'
     '        consider_autoload_name("Float", defined, registry, seen, pending)\n'
     '        @float_source_method_unresolved = false\n',
     "Float source-method autoload gate"),
    ('      if call_name in ("to_i" "prev" "succ" "next" "zero?" "even?" "odd?" "negative?" "positive?" "sq")\n'
     '        consider_autoload_name("Integer", defined, registry, seen, pending)\n'
     '        if call_name == "to_i" && @bigint_to_i_unresolved\n'
     '          consider_autoload_name("BigInt", defined, registry, seen, pending)\n'
     '          @bigint_to_i_unresolved = false\n',
     "Integer/BigInt nested autoload gate"),
    ('    "loader-ast-v16"\n', "loader cache epoch"),
):
    require_once(loader_text, block, label)
if "@identity_leaf_unresolved" in loader_text:
    raise SystemExit("obsolete identity-leaf aggregate loader flag is still present")

runtime_text = (cand / "runtime/runtime.c").read_text()
big_table = """static WICEntry w_ic_bigint_table[] = {    /* Phase 7+m */
    {0, w_ic_bigint_to_s},
    {0, w_ic_bigint_gcd},
    {0, w_ic_bigint_abs},
    {0, w_ic_bigint_prime_q},
    {0, w_ic_bigint_to_f},
    {0, w_ic_bigint_prev},
    {0, w_ic_bigint_succ},
    {0, w_ic_bigint_succ},      /* next */
    {0, w_ic_integer_lcm},
    {0, NULL}
};
"""
big_assign = """    w_ic_bigint_table[0].name  = WN_to_s;
    w_ic_bigint_table[1].name  = WN_gcd;
    w_ic_bigint_table[2].name  = WN_abs;
    w_ic_bigint_table[3].name  = WN_prime_q;
    w_ic_bigint_table[4].name  = WN_to_f;
    w_ic_bigint_table[5].name  = WN_prev;
    w_ic_bigint_table[6].name  = WN_succ;
    w_ic_bigint_table[7].name  = WN_next;
    w_ic_bigint_table[8].name  = WN_lcm;
"""
float_table = """static WICEntry w_ic_float_table[] = {     /* Phase 7+i */
    {0, w_ic_float_to_i},
    {0, w_ic_float_to_s},
    {0, NULL}
};
"""
float_assign = """    w_ic_float_table[0].name  = WN_to_i;
    w_ic_float_table[1].name  = WN_to_s;
"""
for block, label in (
    (big_table, "BigInt current-pruned IC table"),
    (big_assign, "BigInt current-pruned IC names"),
    (float_table, "Float current-pruned IC table"),
    (float_assign, "Float current-pruned IC names"),
):
    require_once(runtime_text, block, label)
for removed in ("w_ic_bigint_to_i", "w_ic_bigint_zero_q", "w_ic_bigint_even_q",
                "w_ic_bigint_odd_q", "w_ic_bigint_negative_q",
                "w_ic_bigint_positive_q", "w_ic_float_to_f",
                "w_ic_float_sqrt", "w_ic_float_ceil", "w_ic_float_floor",
                "w_ic_float_round"):
    if removed in runtime_text:
        raise SystemExit(f"removed runtime identity handler remains: {removed}")

# The benchmark clock must not sit behind a <=2-argument pure-function memo
# table. Keep both timestamps as direct ccalls in three-argument timing bodies.
workload = (cand / "benchmarks/runtime_ports/identity_leaf_public.w").read_text()
if "-> thread_cpu_ns" in workload or "thread_cpu_ns()" in workload:
    raise SystemExit("benchmark clock is hidden behind a memoizable wrapper")
if workload.count('ccall("w_identity_thread_cpu_ns")') != 4:
    raise SystemExit("benchmark must contain exactly two direct clock ccalls per timing function")
for signature in (
    "-> time_float(values, iters, run_id)",
    "-> time_bigint(values, iters, run_id)",
):
    require_once(workload, signature, f"non-memoizable timing signature {signature}")
clock_ref = (cand / "benchmarks/runtime_ports/identity_leaf_public_ref.c").read_text()
if clock_ref.count("clock_gettime(CLOCK_THREAD_CPUTIME_ID, &ts)") != 1:
    raise SystemExit("benchmark helper is not using the thread CPU clock exactly once")

print("PASS static audit: exact identity bodies, v16 autoload/bootstrap anchors, current-pruned IC tables, and non-memoized thread-CPU timing")
PY

if [ "$STATIC_ONLY" = 1 ]; then
  echo "STATIC_ONLY=1: exact production/source audit passed; no compiler or native build was started."
  exit 0
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-identity-leaf.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/shared"
SHARED_SRC="$TMP/shared/identity_leaf_public.w"
SHARED_REF="$TMP/shared/identity_leaf_public_ref.c"
INTERPRETER_SRC="$TMP/shared/identity_leaf_interpreter.w"
cp "$SCRIPT_DIR/identity_leaf_public.w" "$SHARED_SRC"
cp "$SCRIPT_DIR/identity_leaf_public_ref.c" "$SHARED_REF"
cp "$SCRIPT_DIR/identity_leaf_interpreter.w" "$INTERPRETER_SRC"

hash_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    sha256sum "$1" | awk '{print $1}'
  fi
}

build_trial_compiler() {
  local label="$1" root="$2" output="$3"
  local log="$TMP/$label-compiler-build.log"
  local common_source="$TMP/compiler-source" common_output="$TMP/compiler-output"
  rm -rf "$common_source"
  rm -f "$common_output" "$common_output.sidemap"
  mkdir -p "$common_source/languages"
  cp -R "$root/compiler" "$common_source/compiler"
  cp -R "$root/core" "$common_source/core"
  cp -R "$root/runtime" "$common_source/runtime"
  cp -R "$root/languages/tungsten" "$common_source/languages/tungsten"
  if ! (
    cd "$common_source"
    TUNGSTEN_ROOT="$common_source" TUNGSTEN_CACHE_DIR="$TMP/cache-$label" \
      "$BOOTSTRAP_COMPILER" compile "$common_source/compiler/tungsten.w" \
      --release --no-lto --out "$common_output" >"$log" 2>&1
  ); then
    echo "$label compiler bootstrap failed" >&2
    sed -n '1,240p' "$log" >&2
    return 1
  fi
  if [ ! -x "$common_output" ]; then
    echo "$label compiler bootstrap produced no executable" >&2
    return 1
  fi
  cp "$common_output" "$output"
  if [ -f "$common_output.sidemap" ]; then
    cp "$common_output.sidemap" "$output.sidemap"
  fi
  if [ "$(uname -s)" = Darwin ] && command -v codesign >/dev/null 2>&1; then
    codesign --force -s - "$output" >/dev/null 2>&1 || true
  fi
  echo "prepared $label trial compiler $(hash_file "$output")" >&2
}

if [ "$SKIP_COMPILER_BUILD" = 0 ]; then
  if [ -z "$BOOTSTRAP_COMPILER" ] || [ ! -x "$BOOTSTRAP_COMPILER" ]; then
    echo "set BOOTSTRAP_COMPILER to one executable used for both fresh trial builds" >&2
    exit 2
  fi
  BOOTSTRAP_COMPILER="$(cd "$(dirname "$BOOTSTRAP_COMPILER")" && pwd)/$(basename "$BOOTSTRAP_COMPILER")"
  BASELINE_COMPILER="$TMP/baseline-compiler"
  CANDIDATE_COMPILER="$TMP/candidate-compiler"
  echo "common bootstrap $(hash_file "$BOOTSTRAP_COMPILER")" >&2
  build_trial_compiler baseline "$BASELINE_ROOT" "$BASELINE_COMPILER"
  build_trial_compiler candidate "$CANDIDATE_ROOT" "$CANDIDATE_COMPILER"
else
  if [ -z "$BASELINE_COMPILER" ] || [ -z "$CANDIDATE_COMPILER" ]; then
    echo "SKIP_COMPILER_BUILD=1 requires BASELINE_COMPILER and CANDIDATE_COMPILER" >&2
    exit 2
  fi
fi
for compiler in "$BASELINE_COMPILER" "$CANDIDATE_COMPILER"; do
  if [ ! -x "$compiler" ]; then
    echo "missing trial compiler: $compiler" >&2
    exit 2
  fi
done

compile_workload() {
  local label="$1" root="$2" compiler="$3"
  local wire="$TMP/$label.wire" ll="$TMP/$label.ll" bin="$TMP/$label"
  (
    cd "$root"
    TUNGSTEN_ROOT="$root" TUNGSTEN_C_INCLUDES="$SHARED_REF" \
      "$compiler" compile "$SHARED_SRC" --emit-wire >"$wire"
    TUNGSTEN_ROOT="$root" TUNGSTEN_C_INCLUDES="$SHARED_REF" \
      TUNGSTEN_LL_PATH="$ll" \
      "$compiler" compile "$SHARED_SRC" --release --out "$bin" >/dev/null
  )
  if [ ! -x "$bin" ] || [ ! -s "$wire" ] || [ ! -s "$ll" ] || [ ! -s "$bin.sidemap" ]; then
    echo "$label workload did not produce binary, WIRE, LLVM, and sidemap artifacts" >&2
    exit 1
  fi
  echo "prepared $label public workload" >&2
}

compile_workload baseline "$BASELINE_ROOT" "$BASELINE_COMPILER"
compile_workload candidate "$CANDIDATE_ROOT" "$CANDIDATE_COMPILER"

# Candidate source bodies must exist only in the candidate WIRE and consist of
# exactly a direct self return. The LLVM sidemap resolves content-hashed names;
# both methods may intentionally deduplicate to the same identity function.
python3 - "$TMP/baseline.wire" "$TMP/candidate.wire" \
  "$TMP/baseline.ll" "$TMP/baseline.sidemap" \
  "$TMP/candidate.ll" "$TMP/candidate.sidemap" <<'PY'
from pathlib import Path
import json
import re
import sys

bwire, cwire, bll, bmap, cll, cmap = map(Path, sys.argv[1:])
functions = ["__w_Float_to_f__a1", "__w_BigInt_to_i__a1"]

def wire_functions(path, name):
    lines = path.read_text().splitlines()
    starts = [i for i, line in enumerate(lines) if line.startswith(f"function {name}(")]
    bodies = []
    for start in starts:
        body = []
        for line in lines[start + 1:]:
            if line.startswith("function ") or (not line.strip() and body):
                break
            s = line.strip()
            if not s or s in ("{", "}", "end", "entry:", "__entry:") or s.startswith("block "):
                continue
            body.append(s)
        bodies.append(body)
    return bodies

for name in functions:
    if wire_functions(bwire, name):
        raise SystemExit(f"baseline unexpectedly emits WIRE body {name}")
    bodies = wire_functions(cwire, name)
    if bodies != [["ret_i64 %__self"]]:
        raise SystemExit(f"candidate WIRE {name} is not exact direct self return: {bodies}")

def mapped_symbols(map_path, original):
    data = json.loads(map_path.read_text())
    result = set()
    for entry in data.get("hashes", {}).values():
        for item in entry.get("originals", []):
            if item.get("symbol") == original:
                result.add(entry["symbol"])
    return result

def llvm_body(path, symbol):
    lines = path.read_text().splitlines()
    starts = [i for i, line in enumerate(lines)
              if re.match(rf"^define .* @{re.escape(symbol)}\(i64 %__self\).*[{{]$", line)]
    if len(starts) != 1:
        raise SystemExit(f"LLVM symbol {symbol}: expected one exact i64-self definition, found {len(starts)}")
    body = []
    for line in lines[starts[0] + 1:]:
        s = line.strip()
        if s == "}":
            break
        if s:
            body.append(s)
    return body

def llvm_body_any_signature(path, symbol):
    lines = path.read_text().splitlines()
    starts = [i for i, line in enumerate(lines)
              if re.match(rf"^define .* @{re.escape(symbol)}\(", line)]
    if len(starts) != 1:
        raise SystemExit(f"LLVM symbol {symbol}: expected one definition, found {len(starts)}")
    body = []
    for line in lines[starts[0] + 1:]:
        if line.strip() == "}":
            break
        body.append(line)
    return body

for name in functions:
    if mapped_symbols(bmap, name):
        raise SystemExit(f"baseline sidemap unexpectedly contains {name}")
    symbols = mapped_symbols(cmap, name)
    if len(symbols) != 1:
        raise SystemExit(f"candidate sidemap {name}: expected one symbol, found {symbols}")
    body = llvm_body(cll, next(iter(symbols)))
    if body != ["__entry:", "ret i64 %__self"]:
        raise SystemExit(f"candidate LLVM {name} is not exact direct self return: {body}")

# Do not accidentally benchmark a statically folded/direct call. The untyped
# corpus parameter must retain one public zero-argument cached dispatch inside
# each timed loop in both roots.
for map_path, ll_path, label in ((bmap, bll, "baseline"), (cmap, cll, "candidate")):
    for original in ("__w_time_float", "__w_time_bigint"):
        symbols = mapped_symbols(map_path, original)
        if len(symbols) != 1:
            raise SystemExit(f"{label} sidemap {original}: expected one symbol, found {symbols}")
        body = llvm_body_any_signature(ll_path, next(iter(symbols)))
        calls = sum("@w_method_call_cached_0(" in line for line in body)
        if calls != 1:
            raise SystemExit(f"{label} {original}: expected one public cached-0 dispatch, found {calls}")
        clocks = sum("@w_identity_thread_cpu_ns(" in line for line in body)
        if clocks != 2:
            raise SystemExit(f"{label} {original}: expected two direct thread-CPU clock calls, found {clocks}")
        memo_clocks = sum("@__w_memo_call" in line and "w_identity_thread_cpu_ns" in line for line in body)
        if memo_clocks != 0:
            raise SystemExit(f"{label} {original}: thread-CPU clock unexpectedly passed through memoization")

print("PASS WIRE/LLVM: exact ret self bodies, one public cached-0 dispatch, and two direct thread-CPU clocks per timed loop")
PY

"$TMP/baseline" check >"$TMP/baseline.check"
"$TMP/candidate" check >"$TMP/candidate.check"
cmp "$TMP/baseline.check" "$TMP/candidate.check"
cat "$TMP/candidate.check"

expect_fatal_block() {
  local label="$1" bin="$2" mode="$3"
  local out="$TMP/$label.$mode.out" err="$TMP/$label.$mode.err"
  local status
  set +e
  "$bin" "$mode" >"$out" 2>"$err"
  status=$?
  set -e
  if [ "$status" -eq 0 ] || ! grep -Eq "undefined method .*each|undefined method 'each'" "$err"; then
    echo "$label $mode did not preserve implicit-result-each failure (status=$status)" >&2
    sed -n '1,20p' "$err" >&2
    exit 1
  fi
  head -n 1 "$err" | sed 's/ (caller=.*$//' >"$TMP/$label.$mode.first"
}

mode=fatal-float-block
expect_fatal_block baseline "$TMP/baseline" "$mode"
expect_fatal_block candidate "$TMP/candidate" "$mode"
cmp "$TMP/baseline.$mode.first" "$TMP/candidate.$mode.first"

# Keep the heap-BigInt call in statement position, break on first block entry,
# and return an explicit fixed sentinel from its helper. The break preserves
# real syntax while bounding a separate heap-BigInt result-each nanunbox bug.
"$TMP/baseline" check-bigint-block >"$TMP/baseline.check-bigint-block"
"$TMP/candidate" check-bigint-block >"$TMP/candidate.check-bigint-block"
cmp "$TMP/baseline.check-bigint-block" "$TMP/candidate.check-bigint-block"
cat "$TMP/candidate.check-bigint-block"
echo "PASS native trailing blocks: Float preserves implicit-result-each failure; heap BigInt enters bounded statement-position result-each once"

# Run only the candidate tree walker here. The old BigInt interpreter builtin
# round-trips through a decimal string and therefore did not preserve heap
# identity; the migrated source method intentionally fixes that discrepancy.
(
  cd "$CANDIDATE_ROOT"
  TUNGSTEN_ROOT="$CANDIDATE_ROOT" \
    "$CANDIDATE_COMPILER" run "$INTERPRETER_SRC"
)

echo "PASS bootstrap/no-use: fresh candidate compiler autoloaded both source identities without explicit imports"

if [ "$CHECK_ONLY" = 1 ]; then
  echo "CHECK_ONLY=1: static, bootstrap, no-use autoload, WIRE, LLVM, IC reindex, native semantics, and interpreter gates passed; timings skipped."
  exit 0
fi

if [ "$ONLY" = float ]; then
  kinds=(float-finite float-nan)
elif [ "$ONLY" = bigint ]; then
  kinds=(bigint-one-limb bigint-multilimb)
else
  kinds=(float-finite float-nan bigint-one-limb bigint-multilimb)
fi

campaign=first
if [ "$REPEAT" = 1 ]; then campaign=repeat; fi
OUT="${OUT:-${TMPDIR:-/tmp}/identity-leaf-$campaign-$(date +%Y%m%d-%H%M%S).txt}"
: >"$OUT"
printf 'META|campaign|%s|head|%s|bootstrap|%s|baseline-compiler|%s|candidate-compiler|%s\n' \
  "$campaign" "$baseline_head" \
  "$(if [ -n "$BOOTSTRAP_COMPILER" ]; then hash_file "$BOOTSTRAP_COMPILER"; else echo retained; fi)" \
  "$(hash_file "$BASELINE_COMPILER")" "$(hash_file "$CANDIDATE_COMPILER")" >>"$OUT"

sample_field() {
  local sample="$1" field="$2"
  printf '%s\n' "$sample" | awk -F'|' -v f="$field" '$1 == "RESULT" {print $f}'
}

measure() {
  local bin="$1" kind="$2" sample ns checksum
  sample="$("$bin" bench "$kind" "$ITERS" "$WARMUP")"
  ns="$(sample_field "$sample" 3)"
  checksum="$(sample_field "$sample" 4)"
  if [ -z "$ns" ] || [ -z "$checksum" ]; then
    echo "missing RESULT for $kind from $bin" >&2
    return 1
  fi
  case "$ns" in
    ''|*[!0-9]*|0)
      echo "invalid non-positive thread-CPU duration for $kind from $bin: $ns" >&2
      return 1
      ;;
  esac
  if [ "$checksum" != "$ITERS" ]; then
    echo "identity checksum mismatch for $kind from $bin: $checksum != $ITERS" >&2
    return 1
  fi
  printf '%s|%s\n' "$ns" "$checksum"
}

run_pair() {
  local kind="$1" parity="$2" order side result ns checksum="" bsum=0 csum=0
  if [ "$parity" -eq 0 ]; then
    order="B C C B"
  else
    order="C B B C"
  fi
  for side in $order; do
    if [ "$side" = B ]; then
      result="$(measure "$TMP/baseline" "$kind")"
    else
      result="$(measure "$TMP/candidate" "$kind")"
    fi
    ns="${result%%|*}"
    got_checksum="${result#*|}"
    if [ -n "$checksum" ] && [ "$got_checksum" != "$checksum" ]; then
      echo "checksum mismatch for $kind: $got_checksum != $checksum" >&2
      exit 1
    fi
    checksum="$got_checksum"
    if [ "$side" = B ]; then bsum=$((bsum + ns)); else csum=$((csum + ns)); fi
  done
  ratio="$(awk -v c="$csum" -v b="$bsum" 'BEGIN {printf "%.9f", c / b}')"
  printf 'PAIR|%s|%s|%s|%s|%s\n' "$kind" "$bsum" "$csum" "$ratio" "$checksum"
}

for ((sample = 1; sample <= RUNS; sample++)); do
  parity=$(( (sample - 1) % 2 ))
  echo "$campaign sample $sample/$RUNS (parity $parity)" >&2
  for kind in "${kinds[@]}"; do
    run_pair "$kind" "$parity" | tee -a "$OUT"
  done
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
float_failed=0
bigint_failed=0
printf '\n%-22s %13s %13s %10s %8s\n' stratum native-ns/call source-ns/call C/B gate
for kind in "${kinds[@]}"; do
  bmed="$(awk -F'|' -v k="$kind" '$1 == "PAIR" && $2 == k {print $3}' "$OUT" | median_stream)"
  cmed="$(awk -F'|' -v k="$kind" '$1 == "PAIR" && $2 == k {print $4}' "$OUT" | median_stream)"
  ratio="$(awk -F'|' -v k="$kind" '$1 == "PAIR" && $2 == k {print $5}' "$OUT" | median_stream)"
  bcall="$(awk -v n="$bmed" -v calls="$ITERS" 'BEGIN {print n/(2*calls)}')"
  ccall="$(awk -v n="$cmed" -v calls="$ITERS" 'BEGIN {print n/(2*calls)}')"
  decision="$(awk -v r="$ratio" -v g="$GATE" 'BEGIN {print (r <= g ? "PASS" : "SKIP")}')"
  printf '%-22s %13.4f %13.4f %10.4f %8s\n' "$kind" "$bcall" "$ccall" "$ratio" "$decision"
  if [ "$decision" != PASS ]; then
    failed=1
    case "$kind" in float-*) float_failed=1 ;; bigint-*) bigint_failed=1 ;; esac
  fi
done

if [ "$ONLY" != bigint ]; then
  if [ "$float_failed" = 0 ]; then echo "Float#to_f: RETAIN for this $campaign campaign"; else echo "Float#to_f: SKIP"; fi
fi
if [ "$ONLY" != float ]; then
  if [ "$bigint_failed" = 0 ]; then echo "BigInt#to_i: RETAIN for this $campaign campaign"; else echo "BigInt#to_i: SKIP"; fi
fi
echo "raw results: $OUT"
echo "Each ratio sums a balanced native/source/source/native pair (or reverse) using per-thread CPU time."
echo "REPEAT=1 is a fresh independent compiler rebuild and uses the same relaxed <= $GATE gate."
if [ "$failed" -ne 0 ]; then exit 3; fi
