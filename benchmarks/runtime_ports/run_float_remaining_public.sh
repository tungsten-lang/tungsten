#!/usr/bin/env bash
# Relaxed revisit for Float#floor/#ceil/#round/#sqrt/#sq.
#
# STATIC_ONLY=1 (the default) performs source/runtime/loader/interpreter and
# harness audits without invoking either compiler, native linker, or timer.
# Set STATIC_ONLY=0 only when the exclusive heavy lane is free. A full run
# uses fresh matched-root compilers, balanced four-leg per-thread CPU samples,
# and a <=1.10 median gate. Run again with REPEAT=1 before retention.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CANDIDATE_ROOT="${CANDIDATE_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
BASELINE_ROOT="${BASELINE_ROOT:-/tmp/tungsten-float-remaining-baseline}"
BOOTSTRAP_COMPILER="${BOOTSTRAP_COMPILER:-}"
BASELINE_COMPILER="${BASELINE_COMPILER:-}"
CANDIDATE_COMPILER="${CANDIDATE_COMPILER:-}"
SKIP_COMPILER_BUILD="${SKIP_COMPILER_BUILD:-0}"
STATIC_ONLY="${STATIC_ONLY:-1}"
CHECK_ONLY="${CHECK_ONLY:-1}"
REPEAT="${REPEAT:-0}"
RUNS="${RUNS:-10}"
ITERS="${ITERS:-40000000}"
WARMUP="${WARMUP:-1000000}"
GATE="${GATE:-1.10}"
ONLY="${ONLY:-}"
RESULTS_OUT="${RESULTS_OUT:-/tmp/float-remaining-$([ "$REPEAT" = 1 ] && echo repeat || echo first)-20260715.txt}"

for flag in STATIC_ONLY CHECK_ONLY REPEAT SKIP_COMPILER_BUILD; do
  value="${!flag}"
  case "$value" in 0|1) ;; *) echo "$flag must be 0 or 1" >&2; exit 2 ;; esac
done
case "$RUNS" in ''|*[!0-9]*) echo "RUNS must be an even integer from 8 through 12" >&2; exit 2 ;; esac
if [ "$RUNS" -lt 8 ] || [ "$RUNS" -gt 12 ] || [ $((RUNS % 2)) -ne 0 ]; then
  echo "RUNS must be an even integer from 8 through 12" >&2
  exit 2
fi
for value in "$ITERS" "$WARMUP"; do
  case "$value" in ''|*[!0-9]*|0) echo "ITERS and WARMUP must be positive integers" >&2; exit 2 ;; esac
done
case "$ONLY" in ''|floor|ceil|round|sqrt|sq) ;; *) echo "ONLY must be empty or one Float method" >&2; exit 2 ;; esac
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
if [ "$(git -C "$BASELINE_ROOT" rev-parse HEAD)" != "$(git -C "$CANDIDATE_ROOT" rev-parse HEAD)" ]; then
  echo "matched-root HEAD mismatch" >&2
  exit 1
fi

# Static production-shape proof. This intentionally permits the isolated
# roots' expected tracked changes while requiring the delta under study to be
# exactly five Float handlers and their source/autoload support.
python3 - "$BASELINE_ROOT" "$CANDIDATE_ROOT" <<'PY'
from pathlib import Path
import re
import sys

base, cand = map(Path, sys.argv[1:])

def require_once(text, block, label):
    count = text.count(block)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")

common_source = {
    "to_f": "  -> to_f\n    self\n",
    "abs": "  -> abs\n    magnitude = (((($value ## i64) - (0x0001000000000000 ## i64)) ## i64) & (0x7FFFFFFFFFFFFFFF ## i64)) ## i64\n",
    "nan?": "  -> nan?\n    magnitude = (((($value ## i64) - (0x0001000000000000 ## i64)) ## i64) & (0x7FFFFFFFFFFFFFFF ## i64)) ## i64\n",
    "infinite?": "  -> infinite?\n    magnitude = (((($value ## i64) - (0x0001000000000000 ## i64)) ## i64) & (0x7FFFFFFFFFFFFFFF ## i64)) ## i64\n",
}
for root, label in ((base, "baseline"), (cand, "candidate")):
    text = (root / "core/numeric/float.w").read_text()
    for name, block in common_source.items():
        require_once(text, block, f"{label} retained Float#{name}")
    compiler = (root / "compiler/tungsten.w").read_text()
    if compiler.count("use core/numeric/float\n") != 1:
        raise SystemExit(f"{label} compiler lacks Float bootstrap anchor")

candidate_float = (cand / "core/numeric/float.w").read_text()
candidate_bodies = {
    "floor": '  -> floor\n    ccall("w_int", ccall_nobox("w_numeric_to_i64", Math.floor(self)))\n',
    "ceil": '  -> ceil\n    ccall("w_int", ccall_nobox("w_numeric_to_i64", Math.ceil(self)))\n',
    "round": '  -> round\n    ccall("w_int", ccall_nobox("w_numeric_to_i64", Math.round(self)))\n',
    "sqrt": '  -> sqrt\n    Math.sqrt(self)\n',
    "sq": '  -> sq\n    self * self\n',
}
for name, body in candidate_bodies.items():
    require_once(candidate_float, body, f"candidate Float#{name}")

baseline_float = (base / "core/numeric/float.w").read_text()
for name in ("floor", "ceil", "round"):
    require_once(baseline_float, f"  -> {name}\n    Math.{name}(self)\n", f"baseline hidden Float#{name}")
for name in ("sqrt", "sq"):
    if f"\n  -> {name}\n" in baseline_float:
        raise SystemExit(f"baseline unexpectedly defines Float#{name}")

def table_handlers(text):
    m = re.search(r"static WICEntry w_ic_float_table\[\] = \{.*?\n\};", text, re.S)
    if not m:
        raise SystemExit("missing Float IC table")
    return re.findall(r"\{0, (w_ic_[A-Za-z0-9_]+)\}", m.group(0))

def assigned_names(text):
    m = re.search(r"    /\* Float \*/\n(.*?)\n\n    w_ic_decimal_table", text, re.S)
    if not m:
        raise SystemExit("missing Float IC assignment block")
    rows = re.findall(r"w_ic_float_table\[(\d+)\]\.name\s*=\s*(WN_[A-Za-z0-9_]+);", m.group(1))
    if [int(i) for i, _ in rows] != list(range(len(rows))):
        raise SystemExit(f"Float assignment indices are not dense: {rows}")
    return [name for _, name in rows]

b_runtime = (base / "runtime/runtime.c").read_text()
c_runtime = (cand / "runtime/runtime.c").read_text()
expected_base_handlers = [
    "w_ic_float_to_i", "w_ic_float_to_s", "w_ic_float_sqrt",
    "w_ic_float_ceil", "w_ic_float_floor", "w_ic_float_round", "w_ic_num_sq",
]
expected_base_names = ["WN_to_i", "WN_to_s", "WN_sqrt", "WN_ceil", "WN_floor", "WN_round", "WN_sq"]
if table_handlers(b_runtime) != expected_base_handlers or assigned_names(b_runtime) != expected_base_names:
    raise SystemExit("baseline Float table is not the retained-leaf seven-row shape")
if table_handlers(c_runtime) != ["w_ic_float_to_i", "w_ic_float_to_s"]:
    raise SystemExit(f"candidate Float table mismatch: {table_handlers(c_runtime)}")
if assigned_names(c_runtime) != ["WN_to_i", "WN_to_s"]:
    raise SystemExit(f"candidate Float names mismatch: {assigned_names(c_runtime)}")
for handler in ("sqrt", "ceil", "floor", "round"):
    fn = f"static WValue w_ic_float_{handler}("
    if b_runtime.count(fn) != 1 or fn in c_runtime:
        raise SystemExit(f"runtime handler delta is not exact for Float#{handler}")
if c_runtime.count("static WValue w_ic_num_sq(") != 1:
    raise SystemExit("shared Numeric sq helper was incorrectly removed")
if c_runtime.count("{0, w_ic_num_sq}") != 1:
    raise SystemExit("Decimal must retain the shared sq IC row")

b_loader = (base / "compiler/lib/loader.w").read_text()
c_loader = (cand / "compiler/lib/loader.w").read_text()
base_gate = '      if @float_source_method_unresolved && call_name in ("to_f" "abs" "nan?" "infinite?")\n'
cand_gate = '      if @float_source_method_unresolved && call_name in ("to_f" "abs" "nan?" "infinite?" "sqrt" "ceil" "floor" "round" "sq")\n'
require_once(b_loader, base_gate, "baseline retained Float autoload gate")
require_once(c_loader, cand_gate, "candidate Float autoload gate")
require_once(b_loader, '    "loader-ast-v10"\n', "baseline cache epoch")
require_once(c_loader, '    "loader-ast-v16"\n', "candidate cache epoch")

interp = (cand / "compiler/lib/interpreter.w").read_text()
require_once(interp, '    when "w_int"\n', "candidate interpreter w_int bridge")
require_once(interp, '        return ccall("w_float_from_u64_bits", bits - 0x0001000000000000)\n', "candidate Float raw-bit bridge")

calls_lowering = (cand / "compiler/lib/lowering/calls.w").read_text()
require_once(calls_lowering,
             '    if fn_name == "w_numeric_to_i64" && args.size() == 2\n',
             "candidate raw Float-rounding peephole")
require_once(calls_lowering,
             '          emit_instruction(wfn, {op: :fptosi_f64_i64, temp: converted, value: rounded})\n',
             "candidate raw fptosi emission")
emitter = (cand / "compiler/lib/emitter.w").read_text()
require_once(emitter,
             '  when :fptosi_f64_i64\n    inst[:temp] + " = fptosi double " + inst[:value] + " to i64"\n',
             "candidate fptosi LLVM renderer")

artifacts = [
    "float_remaining_public.w", "float_remaining_public_ref.c",
    "float_remaining_no_use_literal.w", "float_remaining_no_use_factory.w",
    "float_remaining_interpreter.w", "float_remaining_revisit_audit.md",
    "run_float_remaining_public.sh",
]
for name in artifacts:
    path = cand / "benchmarks/runtime_ports" / name
    if not path.is_file() or path.stat().st_size == 0:
        raise SystemExit(f"missing prepared artifact {name}")

ref = (cand / "benchmarks/runtime_ports/float_remaining_public_ref.c").read_text()
for expr in (
    "w_int((int64_t)floor(w_as_double(value)))",
    "w_int((int64_t)ceil(w_as_double(value)))",
    "w_int((int64_t)round(w_as_double(value)))",
    "w_box_double(sqrt(w_as_double(value)))",
    "w_mul(value, value)",
):
    require_once(ref, expr, f"reference expression {expr}")

print("PASS STATIC_ONLY: exact five-method Float candidate, retained baseline, IC tables, autoload, interpreter, and guarded harness")
PY

if [ "$STATIC_ONLY" = 1 ]; then
  exit 0
fi

SHARED_SRC="$CANDIDATE_ROOT/benchmarks/runtime_ports/float_remaining_public.w"
SHARED_REF="$CANDIDATE_ROOT/benchmarks/runtime_ports/float_remaining_public_ref.c"
NO_USE_LITERAL="$CANDIDATE_ROOT/benchmarks/runtime_ports/float_remaining_no_use_literal.w"
NO_USE_FACTORY="$CANDIDATE_ROOT/benchmarks/runtime_ports/float_remaining_no_use_factory.w"
INTERPRETER_SRC="$CANDIDATE_ROOT/benchmarks/runtime_ports/float_remaining_interpreter.w"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-float-remaining.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

hash_file() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}';
  else sha256sum "$1" | awk '{print $1}'; fi
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
  test -x "$common_output" || { echo "$label compiler bootstrap produced no executable" >&2; return 1; }
  cp "$common_output" "$output"
  if [ -f "$common_output.sidemap" ]; then cp "$common_output.sidemap" "$output.sidemap"; fi
  if [ "$(uname -s)" = Darwin ] && command -v codesign >/dev/null 2>&1; then
    codesign --force -s - "$output" >/dev/null 2>&1 || true
  fi
  echo "prepared $label compiler $(hash_file "$output")" >&2
}

if [ "$SKIP_COMPILER_BUILD" = 0 ]; then
  if [ -z "$BOOTSTRAP_COMPILER" ] || [ ! -x "$BOOTSTRAP_COMPILER" ]; then
    echo "set BOOTSTRAP_COMPILER to one executable used for both roots" >&2
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
    echo "SKIP_COMPILER_BUILD=1 requires both compiler paths" >&2
    exit 2
  fi
fi
for compiler in "$BASELINE_COMPILER" "$CANDIDATE_COMPILER"; do
  test -x "$compiler" || { echo "missing compiler $compiler" >&2; exit 2; }
done

compile_workload() {
  local label="$1" root="$2" compiler="$3"
  (
    cd "$root"
    TUNGSTEN_ROOT="$root" TUNGSTEN_C_INCLUDES="$SHARED_REF" \
      "$compiler" compile "$SHARED_SRC" --emit-wire >"$TMP/$label.wire"
    TUNGSTEN_ROOT="$root" TUNGSTEN_C_INCLUDES="$SHARED_REF" \
      TUNGSTEN_LL_PATH="$TMP/$label.ll" \
      "$compiler" compile "$SHARED_SRC" --release --out "$TMP/$label" >/dev/null
  )
  for artifact in "$TMP/$label" "$TMP/$label.wire" "$TMP/$label.ll" "$TMP/$label.sidemap"; do
    test -s "$artifact" || { echo "$label workload missing $artifact" >&2; exit 1; }
  done
}

compile_workload baseline "$BASELINE_ROOT" "$BASELINE_COMPILER"
compile_workload candidate "$CANDIDATE_ROOT" "$CANDIDATE_COMPILER"

python3 - "$TMP/baseline.wire" "$TMP/candidate.wire" \
  "$TMP/baseline.ll" "$TMP/baseline.sidemap" \
  "$TMP/candidate.ll" "$TMP/candidate.sidemap" <<'PY'
from pathlib import Path
import json
import re
import sys

bwire, cwire, bll, bmap, cll, cmap = map(Path, sys.argv[1:])
methods = {
    "__w_Float_floor__a1": (("call_libm_f64", "@floor", "fptosi_f64_i64", "@w_int"),
                              ("@floor(", "fptosi double", "@w_int(")),
    "__w_Float_ceil__a1": (("call_libm_f64", "@ceil", "fptosi_f64_i64", "@w_int"),
                             ("@ceil(", "fptosi double", "@w_int(")),
    "__w_Float_round__a1": (("call_libm_f64", "@round", "fptosi_f64_i64", "@w_int"),
                              ("@round(", "fptosi double", "@w_int(")),
    "__w_Float_sqrt__a1": (("w_math_sqrt",), ("@w_math_sqrt(",)),
    "__w_Float_sq__a1": (("w_mul",), ("@w_mul(",)),
}

def wire_body(path, name):
    lines = path.read_text().splitlines()
    starts = [i for i, line in enumerate(lines) if line.startswith(f"function {name}(")]
    if not starts:
        return []
    if len(starts) != 1:
        raise SystemExit(f"WIRE {name}: expected one body, found {len(starts)}")
    body = []
    for line in lines[starts[0] + 1:]:
        if line.startswith("function ") or (not line.strip() and body):
            break
        body.append(line.strip())
    return body

for name, expected in methods.items():
    if wire_body(bwire, name):
        raise SystemExit(f"baseline unexpectedly emitted source body {name}")
    body = wire_body(cwire, name)
    if not body:
        raise SystemExit(f"candidate missing WIRE body {name}")
    joined = "\n".join(body)
    for token in expected[0]:
        if token not in joined:
            raise SystemExit(f"candidate WIRE {name} lacks {token}: {body}")
    if "call_method_i64" in joined or "w_ic_float" in joined:
        raise SystemExit(f"candidate WIRE {name} retains dynamic/C fallback")

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
    starts = [i for i, line in enumerate(lines) if re.match(rf"^define .* @{re.escape(symbol)}\(", line)]
    if len(starts) != 1:
        raise SystemExit(f"LLVM {symbol}: expected one definition, found {len(starts)}")
    body = []
    for line in lines[starts[0] + 1:]:
        if line.strip() == "}": break
        body.append(line)
    return body

for name, expected in methods.items():
    if mapped_symbols(bmap, name):
        raise SystemExit(f"baseline sidemap unexpectedly contains {name}")
    symbols = mapped_symbols(cmap, name)
    if len(symbols) != 1:
        raise SystemExit(f"candidate sidemap {name}: expected one symbol, found {symbols}")
    body = "\n".join(llvm_body(cll, next(iter(symbols))))
    for token in expected[1]:
        if token not in body:
            raise SystemExit(f"candidate LLVM {name} lacks {token}")
    if "@w_method_call" in body or "w_ic_float" in body:
        raise SystemExit(f"candidate LLVM {name} retains dynamic/C fallback")

for map_path, ll_path, label in ((bmap, bll, "baseline"), (cmap, cll, "candidate")):
    for method in ("floor", "ceil", "round", "sqrt", "sq"):
        original = f"__w_time_{method}"
        symbols = mapped_symbols(map_path, original)
        if len(symbols) != 1:
            raise SystemExit(f"{label} missing timed function {original}: {symbols}")
        body = llvm_body(ll_path, next(iter(symbols)))
        cached = sum("@w_method_call_cached_0(" in line for line in body)
        clocks = sum("@w_float_remaining_thread_cpu_ns(" in line for line in body)
        if cached != 1 or clocks != 2:
            raise SystemExit(f"{label} {original}: cached={cached}, clocks={clocks}")

print("PASS WIRE/LLVM: five source bodies use only direct primitives; timed loops retain one public cached dispatch")
PY

"$TMP/baseline" check
"$TMP/candidate" check

for mode in fatal-sqrt-block fatal-sq-block; do
  set +e
  "$TMP/baseline" "$mode" >"$TMP/baseline-$mode.out" 2>&1
  b_status=$?
  "$TMP/candidate" "$mode" >"$TMP/candidate-$mode.out" 2>&1
  c_status=$?
  set -e
  if [ "$b_status" -eq 0 ] || [ "$c_status" -eq 0 ] || [ "$b_status" -ne "$c_status" ]; then
    echo "$mode failure parity mismatch: baseline=$b_status candidate=$c_status" >&2
    exit 1
  fi
done

(
  cd "$CANDIDATE_ROOT"
  TUNGSTEN_ROOT="$CANDIDATE_ROOT" "$CANDIDATE_COMPILER" compile "$NO_USE_LITERAL" --release --out "$TMP/no-use-literal" >/dev/null
  TUNGSTEN_ROOT="$CANDIDATE_ROOT" TUNGSTEN_C_INCLUDES="$SHARED_REF" \
    "$CANDIDATE_COMPILER" compile "$NO_USE_FACTORY" --release --out "$TMP/no-use-factory" >/dev/null
  TUNGSTEN_ROOT="$CANDIDATE_ROOT" "$CANDIDATE_COMPILER" run "$INTERPRETER_SRC"
)
"$TMP/no-use-literal"
"$TMP/no-use-factory"

if [ "$CHECK_ONLY" = 1 ]; then
  echo "CHECK_ONLY=1: build, bootstrap, WIRE/LLVM, correctness, blocks, autoload, and interpreter passed"
  exit 0
fi

if [ -n "$ONLY" ]; then kinds=("$ONLY"); else kinds=(floor ceil round sqrt sq); fi
: >"$RESULTS_OUT"
run_leg() {
  local bin="$1" kind="$2" line
  line="$("$bin" bench "$kind" "$ITERS" "$WARMUP")"
  printf '%s\n' "$line" | awk -F'|' '$1 == "RESULT" {print $3 "|" $4}'
}

sample=1
while [ "$sample" -le "$RUNS" ]; do
  parity=$(( (sample - 1) % 2 ))
  for kind in "${kinds[@]}"; do
    if [ "$parity" -eq 0 ]; then order=(B C C B); else order=(C B B C); fi
    b_sum=0; c_sum=0; checksum=""
    for side in "${order[@]}"; do
      if [ "$side" = B ]; then bin="$TMP/baseline"; else bin="$TMP/candidate"; fi
      result="$(run_leg "$bin" "$kind")"
      elapsed="${result%%|*}"
      got_checksum="${result#*|}"
      if [ -n "$checksum" ] && [ "$got_checksum" != "$checksum" ]; then
        echo "checksum mismatch $kind: $got_checksum != $checksum" >&2
        exit 1
      fi
      checksum="$got_checksum"
      if [ "$side" = B ]; then b_sum=$((b_sum + elapsed)); else c_sum=$((c_sum + elapsed)); fi
    done
    ratio="$(awk -v c="$c_sum" -v b="$b_sum" 'BEGIN {printf "%.9f", c/b}')"
    printf 'PAIR|%s|%s|%s|%s|%s|%s|%s\n' "$kind" "$b_sum" "$c_sum" "$ratio" "$checksum" "$sample" "$parity" | tee -a "$RESULTS_OUT"
  done
  sample=$((sample + 1))
done

median_stream() { sort -n | awk '{v[NR]=$1} END {if (NR%2) print v[(NR+1)/2]; else print (v[NR/2]+v[NR/2+1])/2}'; }
printf '\n%-8s %14s %14s %12s %12s %8s\n' method baseline-ns candidate-ns median-C/B max-C/B gate
failed=0
for kind in "${kinds[@]}"; do
  b_med="$(awk -F'|' -v k="$kind" '$1=="PAIR" && $2==k {print $3}' "$RESULTS_OUT" | median_stream)"
  c_med="$(awk -F'|' -v k="$kind" '$1=="PAIR" && $2==k {print $4}' "$RESULTS_OUT" | median_stream)"
  r_med="$(awk -F'|' -v k="$kind" '$1=="PAIR" && $2==k {print $5}' "$RESULTS_OUT" | median_stream)"
  r_max="$(awk -F'|' -v k="$kind" '$1=="PAIR" && $2==k {if($5>m)m=$5} END{print m}' "$RESULTS_OUT")"
  decision="$(awk -v ratio="$r_med" -v gate="$GATE" 'BEGIN {print (ratio <= gate ? "PASS" : "SKIP")}')"
  [ "$decision" = PASS ] || failed=1
  printf '%-8s %14.0f %14.0f %12.6f %12.6f %8s\n' "$kind" "$b_med" "$c_med" "$r_med" "$r_max" "$decision"
done
echo "raw paired results: $RESULTS_OUT"
echo "Repeat with REPEAT=1 and independently rebuilt compilers before retaining any method."
if [ "$failed" -ne 0 ]; then exit 3; fi
