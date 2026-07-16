#!/usr/bin/env bash
# Independent public `.class` correctness/performance gate for the dispatch-
# facade identity repair. The same compiler and neutral source are used for
# old/fixed binaries; only the linked runtime root differs. STATIC_ONLY=1 is
# the safe default and performs no compiler build, native link, or timing.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ROOT="${PACKAGE_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
FIXED_ROOT="${FIXED_ROOT:-/tmp/tungsten-string-length-revisit-baseline}"
OLD_ROOT="${OLD_ROOT:-/tmp/tungsten-string-class-identity-old}"
COMPILER="${COMPILER:-}"
BOOTSTRAP_COMPILER="${BOOTSTRAP_COMPILER:-}"
STATIC_ONLY="${STATIC_ONLY:-1}"
CHECK_ONLY="${CHECK_ONLY:-1}"
REPEAT="${REPEAT:-0}"
RUNS="${RUNS:-10}"
ITERS="${ITERS:-10000000}"
WARMUP="${WARMUP:-250000}"
GATE="${GATE:-1.10}"
ONLY="${ONLY:-}"
KEEP_TMP="${KEEP_TMP:-0}"

for toggle in STATIC_ONLY CHECK_ONLY REPEAT KEEP_TMP; do
  value="${!toggle}"
  case "$value" in 0|1) ;; *) echo "$toggle must be 0 or 1" >&2; exit 2 ;; esac
done
case "$RUNS" in ''|*[!0-9]*) echo "RUNS must be an even integer from 8 through 12" >&2; exit 2 ;; esac
if [ "$RUNS" -lt 8 ] || [ "$RUNS" -gt 12 ] || [ $((RUNS % 2)) -ne 0 ]; then
  echo "RUNS must be an even integer from 8 through 12" >&2
  exit 2
fi
for value in "$ITERS" "$WARMUP"; do
  case "$value" in ''|*[!0-9]*|0) echo "ITERS/WARMUP must be positive integers" >&2; exit 2 ;; esac
done
case "$ONLY" in ''|string.class|symbol.class|atomic.class|thread.class|channel.class) ;;
  *) echo "ONLY must be empty or string.class/symbol.class/atomic.class/thread.class/channel.class" >&2; exit 2 ;;
esac
if ! awk -v gate="$GATE" 'BEGIN { exit !(gate ~ /^[0-9]+([.][0-9]+)?$/ && gate > 0) }'; then
  echo "GATE must be positive" >&2
  exit 2
fi

PACKAGE_ROOT="$(cd "$PACKAGE_ROOT" && pwd)"
FIXED_ROOT="$(cd "$FIXED_ROOT" && pwd)"
OLD_ROOT="$(cd "$OLD_ROOT" && pwd)"
if [ "$FIXED_ROOT" = "$OLD_ROOT" ]; then
  echo "FIXED_ROOT and OLD_ROOT must be distinct isolated roots" >&2
  exit 2
fi
fixed_head="$(git -C "$FIXED_ROOT" rev-parse HEAD)"
old_head="$(git -C "$OLD_ROOT" rev-parse HEAD)"
if [ "$fixed_head" != "$old_head" ]; then
  echo "old/fixed matched-root HEAD mismatch: $old_head / $fixed_head" >&2
  exit 1
fi

python3 - "$FIXED_ROOT" "$OLD_ROOT" "$PACKAGE_ROOT" <<'PY'
from pathlib import Path
import hashlib, re, subprocess, sys

fixed, old, package = map(Path, sys.argv[1:])

def changed(root):
    return subprocess.run(
        ["git", "-C", str(root), "diff", "--name-only", "HEAD", "--"],
        check=True, capture_output=True, text=True
    ).stdout.splitlines()

if changed(fixed) != ["compiler/lib/builtins.w", "compiler/lib/interpreter.w", "runtime/runtime.c"]:
    raise SystemExit(f"fixed identity root has unexpected tracked changes: {changed(fixed)}")
if changed(old) != ["compiler/lib/builtins.w", "compiler/lib/interpreter.w"]:
    raise SystemExit(f"old identity control has unexpected tracked changes: {changed(old)}")
for shared in ("compiler/lib/builtins.w", "compiler/lib/interpreter.w"):
    if (fixed / shared).read_bytes() != (old / shared).read_bytes():
        raise SystemExit(f"old/fixed controls must share the exact {shared} overlay")
fixed_builtins = (fixed / "compiler/lib/builtins.w").read_text()
if fixed_builtins.count('target = args.empty?() ? recv : args[0]\n    type(target)') != 1:
    raise SystemExit("identity controls lack the explicit-argument type builtin fix")

fixed_rt = (fixed / "runtime/runtime.c").read_text()
old_rt = (old / "runtime/runtime.c").read_text()
fixed_types = (fixed / "compiler/lib/lowering/types.w").read_text()
old_types = (old / "compiler/lib/lowering/types.w").read_text()

def once(text, needle, label):
    count = text.count(needle)
    if count != 1:
        raise SystemExit(f"fixed runtime expected one {label}, got {count}")

def replace_once(text, old_text, new_text, label):
    once(text, old_text, label)
    return text.replace(old_text, new_text)

# Make the timing control causal. The only allowed changes are one exact cache
# declaration plus two hash-pinned regions: class creation/cache maintenance,
# and type registration/public lookup. Replacing those regions with their old
# counterparts must recover the old runtime byte-for-byte. Hash pinning keeps
# an unrelated edit inside the broad hot function from becoming a confounder.
cache_decl = '''/* Public identity is not always method-dispatch identity: String/Symbol share
 * key 0xF9, while Atomic/Thread/Channel source classes are dispatch facades
 * whose public type remains Unknown. Cache the final class WValue (including
 * W_NIL) separately from g_type_class. The extra page is selected by bit 0,
 * which distinguishes String from Symbol; other keys may use both aliases. */
typedef struct {
    WValue value;
    uint8_t resolved;
} WPublicClassEntry;
static WPublicClassEntry g_public_type_class[512] = {0};

static inline void w_public_class_cache(unsigned slot, WValue value) {
    g_public_type_class[slot].value = value;
    g_public_type_class[slot].resolved = 1;
}
'''

def region(text, start, end):
    i = text.index(start)
    j = text.index(end, i)
    return text[i:j]

class_start = 'WValue w_class_new(const char *name, WValue superclass) {'
class_end = 'WValue w_class_new_wv(WValue name, WValue superclass) {'
identity_start = '/* ---- Type class table: dispatch key → class_id for Tungsten-defined methods ---- */'
identity_end = 'WValue w_class_name(WValue v) {'
fixed_class = region(fixed_rt, class_start, class_end)
old_class = region(old_rt, class_start, class_end)
fixed_identity = region(fixed_rt, identity_start, identity_end)
old_identity = region(old_rt, identity_start, identity_end)
expected_hashes = {
    'fixed class cache': (fixed_class, '4727ee7384b16016f6b687bc6d639984f49b1ce3a21dc28a5420677879b192fe'),
    'old class control': (old_class, '4a34f4ba41111274771b06e26b295fa9fbb5c50cef3c0fcd6d10de83f8ffc235'),
    'fixed public lookup': (fixed_identity, 'b69a6128d067e23a9e4a343adb6ca90f3f5173ce8a9a68adbfc321cbe2445f8f'),
    'old public control': (old_identity, '514bf60b07bbf06b9e8cc3c9439b1fda329fae206c7ec7493885d7a9598a1a1e'),
}
for label, (body, expected) in expected_hashes.items():
    got = hashlib.sha256(body.encode()).hexdigest()
    if got != expected:
        raise SystemExit(f'{label} hash drift: {got} != {expected}')

normalized_rt = replace_once(fixed_rt, cache_decl, '', 'public identity cache declaration')
normalized_rt = replace_once(normalized_rt, fixed_class, old_class, 'class cache region')
normalized_rt = replace_once(normalized_rt, fixed_identity, old_identity, 'public lookup region')
if normalized_rt != old_rt:
    raise SystemExit("fixed runtime contains changes beyond the exact public identity repair")

if fixed_types != old_types:
    raise SystemExit("old/fixed controls must share the exact lowering type map")
for source_name in ("Array", "TypedArray", "ByteArray", "BoolArray"):
    pattern = rf'(?m)^\s*"{source_name}"\s*=>\s*0x0A(?:\s*#.*)?$'
    if len(re.findall(pattern, fixed_types)) != 1:
        raise SystemExit(f"lowering type map lacks unique {source_name} => 0x0A alias")
array_public_type = 'if (w_is_array(v) || w_is_body(v)) return w_string("Array");'
if fixed_rt.count(array_public_type) != 1 or old_rt.count(array_public_type) != 1:
    raise SystemExit("old/fixed runtimes must keep __w_type authoritative for native Arrays")

for needle in (
    'static WPublicClassEntry g_public_type_class[512] = {0};',
    'else if (strcmp(name, "Symbol") == 0) {',
    '!w_is_class(g_public_type_class[0x101].value)',
    'static void w_public_type_class_register(uint8_t key, WClass *klass)',
    'key == W_SUBTAG_ATOMIC',
    'key == (0x80u | W_TYPE_THREAD)',
    'key == (0x80u | W_TYPE_CHANNEL)',
    'g_public_type_class[key].resolved = 0;',
    'g_public_type_class[0x100u | key].resolved = 0;',
    'public_slot = (unsigned)key | ((unsigned)(v & 1u) << 8);',
    'if (cached->resolved) return cached->value;',
    'w_public_class_cache(public_slot, W_NIL);',
):
    if fixed_rt.count(needle) != 1:
        raise SystemExit(f"fixed runtime lacks unique public-identity path: {needle}")
    if needle in old_rt:
        raise SystemExit(f"old control unexpectedly contains fixed path: {needle}")

spec = (package / "spec/compiler/string_symbol_class_identity_spec.w").read_text()
bench = (package / "benchmarks/runtime_ports/string_symbol_class_identity_bench.w").read_text()
ref = (package / "benchmarks/runtime_ports/string_length_revisit_ref.c").read_text()
for needle in (
    'check("[name] class before", before, nil)',
    'check("[name] class after", after, nil)',
    'check("[name] class stable across facade", after, before)',
    'check("[name] not facade identity", value.is_a?(facade), false)',
    'check("[name] facade method dispatch", value.identity_facade_probe, key)',
    'check_unknown_handle("Atomic", Atomic.new(0), 0x01, AtomicIdentityFacade)',
    'check_unknown_handle("Channel", Channel.new(1), 0x84, ChannelIdentityFacade)',
    'check_unknown_handle("Thread", thread, 0x81, ThreadIdentityFacade)',
    'check("Declared Unknown class before declaration", atomic.class, nil)',
    'declared = ccall("w_class_identity_declare_unknown")',
    'check("Declared Unknown class after facade", atomic.class, declared)',
    'check("Array alias class stable bits", wvalue_bits(value.class), wvalue_bits(before))',
    'check("Array alias not facade identity", value.is_a?(ArrayIdentityFacade), false)',
    'check("Array alias facade method dispatch", value.identity_facade_probe, 10)',
    'ccall("w_class_identity_register_facade", 0x0A, ArrayIdentityFacade)',
    'check("Array cold alias class", ccall("w_class_identity_class_label", selected), "Array")',
    'check("Array cold alias not facade identity", value.is_a?(ArrayIdentityFacade), false)',
    'value = ccall("w_class_identity_native_hash")',
    'before = value.class',
    'declared = ccall("w_class_identity_declare_hash")',
    'check("Late Hash cache replaced", before == after, false)',
    'check("Late Hash registered class selected", wvalue_bits(after), wvalue_bits(declared))',
):
    if needle not in spec:
        raise SystemExit(f"identity spec lacks {needle}")
for stratum in ("string.class", "symbol.class", "atomic.class", "thread.class", "channel.class"):
    if f'"{stratum}"' not in bench:
        raise SystemExit(f"identity benchmark lacks {stratum}")
if bench.count('ccall_nobox("w_strlen_thread_cpu_ns")') != 2:
    raise SystemExit("identity timer must contain exactly two raw thread clocks")
if bench.count("-> time_public_class(value, iters, run_id)") != 1:
    raise SystemExit("identity benchmark lacks one three-argument timer")
if "wvalue_bits(value.class) ^ expected_bits" not in bench:
    raise SystemExit("identity timer does not consume every public class result")
if "mismatch = (mismatch |" not in bench:
    raise SystemExit("identity timer lacks branch-free normalized mismatch accumulation")
if 'IDENTITY_PROBE|[stratum]|[public_class_label(value_for(stratum))]' not in bench:
    raise SystemExit("identity benchmark lacks an untimed linked-runtime semantic probe")
if ref.count("WValue w_class_identity_register_facade(WValue key_value, WValue klass)") != 1:
    raise SystemExit("neutral reference lacks delayed facade registration")
if ref.count("WValue w_class_identity_declare_unknown(void)") != 1:
    raise SystemExit("neutral reference lacks delayed explicit Unknown declaration")
if ref.count("WValue w_class_identity_native_hash(void)") != 1:
    raise SystemExit("neutral reference lacks native cold-Hash fixture")
if ref.count("WValue w_class_identity_declare_hash(void)") != 1:
    raise SystemExit("neutral reference lacks delayed matching Hash registration")
print("PASS identity static audit: matched old/fixed roots; four real 0x0A aliases; cold/warm alias and late matching-registration regressions; neutral five-stratum benchmark")
PY

if [ "$STATIC_ONLY" = 1 ]; then
  echo "STATIC_ONLY=1: no compiler build, native link, executable, or timing was started."
  exit 0
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-public-class-identity.XXXXXX")"
cleanup() {
  if [ "$KEEP_TMP" = 1 ]; then
    echo "retained diagnostic directory: $TMP" >&2
  else
    rm -rf "$TMP"
  fi
}
trap cleanup EXIT
mkdir -p "$TMP/shared"
SPEC="$TMP/shared/public_class_identity_spec.w"
BENCH="$TMP/shared/public_class_identity_bench.w"
REF="$TMP/shared/public_class_identity_ref.c"
cp "$PACKAGE_ROOT/spec/compiler/string_symbol_class_identity_spec.w" "$SPEC"
cp "$PACKAGE_ROOT/benchmarks/runtime_ports/string_symbol_class_identity_bench.w" "$BENCH"
cp "$PACKAGE_ROOT/benchmarks/runtime_ports/string_length_revisit_ref.c" "$REF"

hash_file() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}';
  else sha256sum "$1" | awk '{print $1}'; fi
}

build_fixed_compiler() {
  local source="$TMP/compiler-source" built="$TMP/compiler-built" log="$TMP/compiler.log"
  mkdir -p "$source/languages"
  cp -R "$FIXED_ROOT/compiler" "$source/compiler"
  cp -R "$FIXED_ROOT/core" "$source/core"
  cp -R "$FIXED_ROOT/runtime" "$source/runtime"
  cp -R "$FIXED_ROOT/languages/tungsten" "$source/languages/tungsten"
  (
    cd "$source"
    TUNGSTEN_ROOT="$source" TUNGSTEN_CACHE_DIR="$TMP/cache-build" \
      "$BOOTSTRAP_COMPILER" compile "$source/compiler/tungsten.w" \
      --release --no-lto --out "$built" >"$log" 2>&1
  ) || { echo "fixed compiler bootstrap failed" >&2; sed -n '1,240p' "$log" >&2; return 1; }
  test -x "$built" || { echo "fixed compiler bootstrap produced no executable" >&2; return 1; }
  COMPILER="$TMP/fixed-compiler"
  cp "$built" "$COMPILER"
  test ! -f "$built.sidemap" || cp "$built.sidemap" "$COMPILER.sidemap"
  if [ "$(uname -s)" = Darwin ] && command -v codesign >/dev/null 2>&1; then
    codesign --force -s - "$COMPILER" >/dev/null 2>&1 || true
  fi
}

if [ -n "$COMPILER" ]; then
  test -x "$COMPILER" || { echo "COMPILER must be executable" >&2; exit 2; }
  COMPILER="$(cd "$(dirname "$COMPILER")" && pwd)/$(basename "$COMPILER")"
else
  if [ -z "$BOOTSTRAP_COMPILER" ] || [ ! -x "$BOOTSTRAP_COMPILER" ]; then
    echo "set one executable COMPILER, or BOOTSTRAP_COMPILER for one fixed-root trial build" >&2
    exit 2
  fi
  BOOTSTRAP_COMPILER="$(cd "$(dirname "$BOOTSTRAP_COMPILER")" && pwd)/$(basename "$BOOTSTRAP_COMPILER")"
  build_fixed_compiler
fi

# --no-lto keeps the measured public call external. The compiler's native
# runtime archive is keyed/freshness-checked by canonical runtime root; the
# semantic probe below additionally proves each final binary linked its
# intended old/fixed implementation. Both sides use identical flags.
compile_case() {
  local label="$1" root="$2" source="$3" stem="$4"
  local wire="$TMP/$label-$stem.wire" ll="$TMP/$label-$stem.ll" bin="$TMP/$label-$stem"
  (
    cd "$root"
    TUNGSTEN_ROOT="$root" TUNGSTEN_CACHE_DIR="$TMP/cache-$label-$stem" TUNGSTEN_C_INCLUDES="$REF" \
      "$COMPILER" compile "$source" --emit-wire >"$wire"
    TUNGSTEN_ROOT="$root" TUNGSTEN_CACHE_DIR="$TMP/cache-$label-$stem" TUNGSTEN_C_INCLUDES="$REF" TUNGSTEN_LL_PATH="$ll" \
      "$COMPILER" compile "$source" --release --no-lto --out "$bin" >/dev/null
  )
  test -x "$bin" && test -s "$wire" && test -s "$ll" && test -s "$bin.sidemap" || {
    echo "$label/$stem did not produce binary/WIRE/LLVM/sidemap" >&2; exit 1;
  }
}

compile_case old "$OLD_ROOT" "$SPEC" spec
compile_case fixed "$FIXED_ROOT" "$SPEC" spec
"$TMP/fixed-spec" >"$TMP/fixed-spec.out"
grep -Fx 'PASS public class identity all: __w_type-authoritative identity, alias invalidation, and late matching registration' \
  "$TMP/fixed-spec.out"
"$TMP/fixed-spec" declared >"$TMP/fixed-spec-declared.out"
grep -Fx 'PASS public class identity declared: __w_type-authoritative identity, alias invalidation, and late matching registration' \
  "$TMP/fixed-spec-declared.out"

for mode in symbol atomic thread channel declared alias alias_cold; do
  set +e
  "$TMP/old-spec" "$mode" >"$TMP/old-spec-$mode.out" 2>&1
  status=$?
  set -e
  if [ "$status" -ne 1 ]; then
    echo "old $mode causal control should fail with status 1, got $status" >&2
    sed -n '1,120p' "$TMP/old-spec-$mode.out" >&2
    exit 1
  fi
  case "$mode" in
    symbol) failure='FAIL class identity Symbol class name' ;;
    atomic) failure='FAIL class identity Atomic class after' ;;
    thread) failure='FAIL class identity Thread class after' ;;
    channel) failure='FAIL class identity Channel class after' ;;
    declared) failure='FAIL class identity Declared Unknown class after facade' ;;
    alias) failure='FAIL class identity Array alias class stable bits' ;;
    alias_cold) failure='FAIL class identity Array cold alias class' ;;
  esac
  grep -F "$failure" "$TMP/old-spec-$mode.out" >/dev/null || {
    echo "old $mode causal control failed at the wrong assertion" >&2
    sed -n '1,120p' "$TMP/old-spec-$mode.out" >&2
    exit 1
  }
done
echo "PASS causal controls: old runtime fails Symbol, all three delayed facades, explicit Unknown, and cold/warm Array alias identity; fixed runtime passes all including late Hash replacement"

compile_case old "$OLD_ROOT" "$BENCH" bench
compile_case fixed "$FIXED_ROOT" "$BENCH" bench
if [ "$(hash_file "$TMP/old-bench")" = "$(hash_file "$TMP/fixed-bench")" ]; then
  echo "old/fixed benchmark binaries are identical; selected runtime roots were not distinguished" >&2
  exit 1
fi

probe_class() {
  local bin="$1" stratum="$2" sample observed
  sample="$("$bin" probe "$stratum")"
  observed="$(printf '%s\n' "$sample" | awk -F'|' -v s="$stratum" '$1=="IDENTITY_PROBE"&&$2==s{print $3}')"
  test -n "$observed" || { echo "missing identity probe for $stratum from $bin" >&2; return 1; }
  printf '%s\n' "$observed"
}
for stratum in string.class symbol.class atomic.class thread.class channel.class; do
  old_observed="$(probe_class "$TMP/old-bench" "$stratum")"
  fixed_observed="$(probe_class "$TMP/fixed-bench" "$stratum")"
  case "$stratum" in
    string.class) expected_old=String; expected_fixed=String ;;
    symbol.class) expected_old=String; expected_fixed=Symbol ;;
    atomic.class) expected_old=AtomicIdentityFacade; expected_fixed=nil ;;
    thread.class) expected_old=ThreadIdentityFacade; expected_fixed=nil ;;
    channel.class) expected_old=ChannelIdentityFacade; expected_fixed=nil ;;
  esac
  if [ "$old_observed" != "$expected_old" ] || [ "$fixed_observed" != "$expected_fixed" ]; then
    echo "wrong linked-runtime probe $stratum: old=$old_observed/$expected_old fixed=$fixed_observed/$expected_fixed" >&2
    exit 1
  fi
  printf 'IDENTITY_PROBE_OK|%s|old=%s|fixed=%s\n' "$stratum" "$old_observed" "$fixed_observed"
done

python3 - "$TMP/old-bench.wire" "$TMP/fixed-bench.wire" \
  "$TMP/old-bench.ll" "$TMP/old-bench.sidemap" \
  "$TMP/fixed-bench.ll" "$TMP/fixed-bench.sidemap" <<'PY'
from pathlib import Path
import json, re, sys

owire, fwire, oll, omap, fll, fmap = map(Path, sys.argv[1:])

def wire_body(path, prefix):
    lines = path.read_text().splitlines()
    starts = [i for i, line in enumerate(lines) if line.startswith(f"function {prefix}(")]
    if len(starts) != 1:
        raise SystemExit(f"{path.name}: expected one {prefix}, got {len(starts)}")
    body = []
    for line in lines[starts[0] + 1:]:
        if line.startswith("function ") or (not line.strip() and body): break
        if line.strip(): body.append(line.strip())
    return "\n".join(body)

old_wire_body = wire_body(owire, "__w_time_public_class")
fixed_wire_body = wire_body(fwire, "__w_time_public_class")
if old_wire_body != fixed_wire_body:
    raise SystemExit("old/fixed timer WIRE bodies differ despite one common compiler/source")
if old_wire_body.count("w_class_of") != 2 or old_wire_body.count("w_strlen_thread_cpu_ns") != 2:
    raise SystemExit("timer WIRE must contain one pre-clock + one loop class call and two clocks")
wire_xors = list(re.finditer(r"(?m)^xor_i64\b", old_wire_body))
wire_ors = list(re.finditer(r"(?m)^or_i64\b", old_wire_body))
if len(wire_xors) != 1 or len(wire_ors) != 1:
    raise SystemExit("timer WIRE lacks the one raw xor/or stability accumulator")
if "w_eq" in old_wire_body or "w_method_call_cached" in old_wire_body:
    raise SystemExit("timer WIRE contains equality or unrelated public dispatch dilution")
wire_classes = [m.start() for m in re.finditer("w_class_of", old_wire_body)]
wire_clocks = [m.start() for m in re.finditer("w_strlen_thread_cpu_ns", old_wire_body)]
wire_xor = wire_xors[0].start()
wire_or = wire_ors[0].start()
if not (wire_classes[0] < wire_clocks[0] < wire_classes[1] <
        wire_xor < wire_or < wire_clocks[1]):
    raise SystemExit("timer WIRE does not place exactly one consumed class call between its clocks")

def symbols(map_path, original):
    data = json.loads(map_path.read_text())
    return {
        entry["symbol"] for entry in data.get("hashes", {}).values()
        if any(item.get("symbol") == original for item in entry.get("originals", []))
    }

def llvm_body(path, symbol):
    lines = path.read_text().splitlines()
    starts = [i for i, line in enumerate(lines) if re.match(rf"^define .* @{re.escape(symbol)}\(", line)]
    if len(starts) != 1:
        raise SystemExit(f"{path.name}: expected one LLVM {symbol}, got {len(starts)}")
    body = []
    for line in lines[starts[0] + 1:]:
        if line.strip() == "}": break
        body.append(line)
    return "\n".join(body)

bodies = []
for ll, smap, label in ((oll, omap, "old"), (fll, fmap, "fixed")):
    syms = symbols(smap, "__w_time_public_class")
    if len(syms) != 1:
        raise SystemExit(f"{label}: timer sidemap symbols {syms}")
    body = llvm_body(ll, next(iter(syms)))
    if body.count("call i64 @w_class_of(") != 2:
        raise SystemExit(f"{label}: final timer must retain two external w_class_of calls")
    if body.count("call i64 @w_strlen_thread_cpu_ns(") != 2:
        raise SystemExit(f"{label}: final timer must retain two raw clocks")
    llvm_classes = [m.start() for m in re.finditer(r"call i64 @w_class_of\(", body)]
    llvm_clocks = [m.start() for m in re.finditer(r"call i64 @w_strlen_thread_cpu_ns\(", body)]
    if not (llvm_classes[0] < llvm_clocks[0] < llvm_classes[1] < llvm_clocks[1]):
        raise SystemExit(f"{label}: final timer does not place exactly one class call between its clocks")
    timed_slice = body[llvm_classes[1]:llvm_clocks[1]]
    llvm_xors = list(re.finditer(r"(?m)^\s*%[^=]+ = xor i64\b", timed_slice))
    llvm_ors = list(re.finditer(r"(?m)^\s*%[^=]+ = or i64\b", timed_slice))
    if len(llvm_xors) != 1 or len(llvm_ors) != 1 or llvm_ors[0].start() < llvm_xors[0].start():
        raise SystemExit(f"{label}: timed class result is not consumed by xor/or before the stop clock")
    bodies.append(body)
if bodies[0] != bodies[1]:
    raise SystemExit("old/fixed extracted timer LLVM differs; runtime comparison is confounded")
print("PASS benchmark IR: identical old/fixed timer; one external public class call per iteration; branch-free normalized use; no LTO")
PY

if [ "$CHECK_ONLY" = 1 ]; then
  echo "CHECK_ONLY=1: fixed semantics, seven old causal failures, late Hash replacement, neutral WIRE/LLVM, and root-specific links passed; timings skipped."
  exit 0
fi

all_strata=(string.class symbol.class atomic.class thread.class channel.class)
strata=()
for stratum in "${all_strata[@]}"; do
  if [ -z "$ONLY" ] || [ "$stratum" = "$ONLY" ]; then strata+=("$stratum"); fi
done
campaign=first
test "$REPEAT" = 0 || campaign=repeat
OUT="${OUT:-${TMPDIR:-/tmp}/public-class-identity-$campaign-$(date +%Y%m%d-%H%M%S).txt}"
: >"$OUT"
printf 'IDENTITY_META|campaign|%s|head|%s|compiler|%s|old|%s|fixed|%s|iters|%s|warmup|%s\n' \
  "$campaign" "$fixed_head" "$(hash_file "$COMPILER")" \
  "$(hash_file "$TMP/old-bench")" "$(hash_file "$TMP/fixed-bench")" "$ITERS" "$WARMUP" >>"$OUT"

measure() {
  local bin="$1" stratum="$2" sample ns checksum
  sample="$("$bin" bench "$stratum" "$ITERS" "$WARMUP")"
  ns="$(printf '%s\n' "$sample" | awk -F'|' -v s="$stratum" '$1=="IDENTITY_RESULT"&&$2==s{print $3}')"
  checksum="$(printf '%s\n' "$sample" | awk -F'|' -v s="$stratum" '$1=="IDENTITY_RESULT"&&$2==s{print $5}')"
  case "$ns" in ''|*[!0-9]*|0) echo "invalid duration for $stratum from $bin: $ns" >&2; return 1 ;; esac
  if [ "$checksum" != 0 ]; then
    echo "unstable class result for $stratum from $bin: mismatch=$checksum" >&2
    return 1
  fi
  printf '%s|%s\n' "$ns" "$checksum"
}

run_four_leg() {
  local stratum="$1" parity="$2" order side result ns got checksum="" osum=0 fsum=0 ratio
  if [ "$parity" -eq 0 ]; then order="O F F O"; else order="F O O F"; fi
  for side in $order; do
    case "$side" in
      O) result="$(measure "$TMP/old-bench" "$stratum")" ;;
      F) result="$(measure "$TMP/fixed-bench" "$stratum")" ;;
    esac
    ns="${result%%|*}"; got="${result#*|}"
    if [ -n "$checksum" ] && [ "$got" != "$checksum" ]; then
      echo "checksum mismatch $stratum: $got != $checksum" >&2; exit 1
    fi
    checksum="$got"
    case "$side" in O) osum=$((osum+ns));; F) fsum=$((fsum+ns));; esac
  done
  ratio="$(awk -v f="$fsum" -v o="$osum" 'BEGIN {printf "%.9f",f/o}')"
  printf 'IDENTITY_PAIR|%s|%s|%s|%s|%s\n' "$stratum" "$osum" "$fsum" "$ratio" "$checksum"
}

for ((sample=1; sample<=RUNS; sample++)); do
  parity=$(((sample-1)%2))
  echo "$campaign identity sample $sample/$RUNS parity=$parity" >&2
  for stratum in "${strata[@]}"; do run_four_leg "$stratum" "$parity" | tee -a "$OUT"; done
done

median_stream() {
  sort -n | awk '{v[NR]=$1} END {if(!NR)exit 1; if(NR%2)print v[(NR+1)/2]; else print (v[NR/2]+v[NR/2+1])/2}'
}

failed=0
printf '\n%-16s %12s %12s %10s %9s\n' stratum old-ns/call fixed-ns/call fixed/old decision
for stratum in "${strata[@]}"; do
  omed="$(awk -F'|' -v s="$stratum" '$1=="IDENTITY_PAIR"&&$2==s{print $3}' "$OUT" | median_stream)"
  fmed="$(awk -F'|' -v s="$stratum" '$1=="IDENTITY_PAIR"&&$2==s{print $4}' "$OUT" | median_stream)"
  ratio="$(awk -F'|' -v s="$stratum" '$1=="IDENTITY_PAIR"&&$2==s{print $5}' "$OUT" | median_stream)"
  ocall="$(awk -v n="$omed" -v i="$ITERS" 'BEGIN{print n/(2*i)}')"
  fcall="$(awk -v n="$fmed" -v i="$ITERS" 'BEGIN{print n/(2*i)}')"
  decision="$(awk -v r="$ratio" -v g="$GATE" 'BEGIN{print (r <= g ? "RETAIN" : "SKIP")}')"
  printf '%-16s %12.4f %12.4f %10.4f %9s\n' "$stratum" "$ocall" "$fcall" "$ratio" "$decision"
  printf 'IDENTITY_SUMMARY|%s|%s|%s\n' "$stratum" "$ratio" "$decision" >>"$OUT"
  if [ "$decision" = SKIP ]; then failed=1; fi
done

echo "raw identity results: $OUT"
echo "Each sample is O/F/F/O or F/O/O/F with thread CPU time; every public .class receiver stratum is gated independently at <= $GATE."
echo "Run REPEAT=1 for a second independently linked campaign before retaining the identity repair."
if [ "$failed" -ne 0 ]; then exit 3; fi
