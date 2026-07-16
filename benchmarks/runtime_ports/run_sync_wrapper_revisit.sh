#!/usr/bin/env bash
# Matched-root audit for Atomic, Channel, and Thread runtime-wrapper migration.
# STATIC_ONLY=1 remains the safe default. The archived retained decision used
# two separate rebuilt campaigns (REPEAT=0 and REPEAT=1), each with every
# source candidate <= 1.10.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CANDIDATE_ROOT="${CANDIDATE_ROOT:-/tmp/tungsten-sync-wrapper-candidate}"
BASELINE_ROOT="${BASELINE_ROOT:-/tmp/tungsten-sync-wrapper-baseline}"
BOOTSTRAP_COMPILER="${BOOTSTRAP_COMPILER:-}"
BASELINE_COMPILER="${BASELINE_COMPILER:-}"
CANDIDATE_COMPILER="${CANDIDATE_COMPILER:-}"
SKIP_COMPILER_BUILD="${SKIP_COMPILER_BUILD:-0}"
KEEP_TMP="${KEEP_TMP:-0}"
STATIC_ONLY="${STATIC_ONLY:-1}"
CHECK_ONLY="${CHECK_ONLY:-1}"
REPEAT="${REPEAT:-0}"
RUNS="${RUNS:-10}"
LOAD_RUNS="${LOAD_RUNS:-5}"
GATE="${GATE:-1.10}"
ONLY="${ONLY:-}"
RESULTS_OUT="${RESULTS_OUT:-/tmp/sync-wrapper-revisit-$([ "$REPEAT" = 1 ] && echo repeat || echo first)-20260715.txt}"

for flag in STATIC_ONLY CHECK_ONLY REPEAT SKIP_COMPILER_BUILD KEEP_TMP; do
  value="${!flag}"
  case "$value" in 0|1) ;; *) echo "$flag must be 0 or 1" >&2; exit 2 ;; esac
done
case "$RUNS" in ''|*[!0-9]*) echo "RUNS must be an even integer from 8 through 12" >&2; exit 2 ;; esac
if [ "$RUNS" -lt 8 ] || [ "$RUNS" -gt 12 ] || [ $((RUNS % 2)) -ne 0 ]; then
  echo "RUNS must be an even integer from 8 through 12" >&2
  exit 2
fi
case "$LOAD_RUNS" in ''|*[!0-9]*) echo "LOAD_RUNS must be an odd integer from 3 through 7" >&2; exit 2 ;; esac
if [ "$LOAD_RUNS" -lt 3 ] || [ "$LOAD_RUNS" -gt 7 ] || [ $((LOAD_RUNS % 2)) -ne 1 ]; then
  echo "LOAD_RUNS must be an odd integer from 3 through 7" >&2
  exit 2
fi
if [ "$GATE" != "1.10" ]; then
  echo "the synchronization-wrapper retention gate is fixed at 1.10" >&2
  exit 2
fi

BASELINE_ROOT="$(cd "$BASELINE_ROOT" && pwd)"
CANDIDATE_ROOT="$(cd "$CANDIDATE_ROOT" && pwd)"
if [ "$BASELINE_ROOT" = "$CANDIDATE_ROOT" ]; then
  echo "BASELINE_ROOT and CANDIDATE_ROOT must be distinct" >&2
  exit 2
fi
if [ "$(git -C "$BASELINE_ROOT" rev-parse HEAD)" != "$(git -C "$CANDIDATE_ROOT" rev-parse HEAD)" ]; then
  echo "matched-root HEAD mismatch" >&2
  exit 1
fi

for rel in \
  benchmarks/runtime_ports/sync_wrapper_revisit_public.w \
  benchmarks/runtime_ports/sync_wrapper_revisit_ref.c \
  benchmarks/runtime_ports/sync_wrapper_revisit_load_probe.w \
  benchmarks/runtime_ports/sync_wrapper_revisit_load_probe_atomic.w \
  benchmarks/runtime_ports/sync_wrapper_revisit_load_probe_channel.w \
  benchmarks/runtime_ports/sync_wrapper_revisit_load_probe_factories.w \
  benchmarks/runtime_ports/sync_wrapper_revisit_load_probe_thread.w \
  benchmarks/runtime_ports/sync_wrapper_revisit_load_probe_retained.w
do
  if ! cmp -s "$BASELINE_ROOT/$rel" "$CANDIDATE_ROOT/$rel"; then
    echo "matched-root workload mismatch: $rel" >&2
    exit 1
  fi
done

python3 - "$BASELINE_ROOT" "$CANDIDATE_ROOT" <<'PY'
from pathlib import Path
import re
import sys

base, cand = map(Path, sys.argv[1:])

def once(text, needle, label):
    n = text.count(needle)
    if n != 1:
        raise SystemExit(f"{label}: expected exactly one occurrence, found {n}")

if (base / "core/atomic.w").exists():
    raise SystemExit("matched baseline unexpectedly contains core/atomic.w")
if (base / "core/channel.w").read_text() != "+ Channel\n":
    raise SystemExit("matched baseline Channel facade is not bodyless")
base_thread = (base / "core/thread.w").read_text()
if '  -> alive?\n    ccall("w_thread_alive", self)\n' in base_thread:
    raise SystemExit("matched baseline Thread#alive? already has a source body")

core_bodies = {
    "core/atomic.w": [
        '  -> increment\n    ccall("w_atomic_increment", self)\n',
        '  -> decrement\n    ccall("w_atomic_decrement", self)\n',
    ],
    "core/channel.w": [
        '  -> recv\n    ccall("w_chan_recv", self)\n',
    ],
    "core/thread.w": [
        '  -> alive?\n    ccall("w_thread_alive", self)\n',
    ],
}
for rel, bodies in core_bodies.items():
    text = (cand / rel).read_text()
    for body in bodies:
        once(text, body, f"candidate {rel} body")

atomic = (cand / "core/atomic.w").read_text()
channel = (cand / "core/channel.w").read_text()
thread = (cand / "core/thread.w").read_text()
for forbidden, text in (
    ("  -> cas", atomic),
    ("  -> get\n", atomic), ("  -> set(", atomic), ("  -> add(", atomic),
    ("  -> send", channel),
    ("  -> close\n", channel),
):
    if forbidden in text:
        raise SystemExit(f"retained-native selector leaked into source facade: {forbidden.strip()}")
for declaration in ("  -> join\n", "  -> join(ms)\n", "  -> kill\n"):
    once(thread, declaration, f"retained Thread declaration {declaration.strip()}")
if "w_thread_join" in thread or "w_thread_kill" in thread:
    raise SystemExit("retained Thread join/kill unexpectedly gained source bodies")

registry = (cand / "core/tungsten.w").read_text()
once(registry, '  auto :Atomic,       "atomic"\n', "Atomic autoload registry")
once(registry, '  auto :Channel,      "channel"\n', "Channel autoload registry")
once(registry, '  auto :Thread,       "thread"\n', "Thread autoload registry")

types = (cand / "compiler/lib/lowering/types.w").read_text()
for needle in ('"Atomic"        => 0x01', '"Thread"        => 0x81', '"Channel"       => 0x84'):
    once(types, needle, f"dispatch key {needle}")

loader = (cand / "compiler/lib/loader.w").read_text()
for needle in (
    '@atomic_source_method_unresolved', '@channel_source_method_unresolved',
    '@thread_source_method_unresolved', 'call_name in ("increment" "decrement")',
    'call_name == "recv"', 'call_name == "alive?"',
    'if name == "w_atomic_new"', 'if name == "w_chan_new"',
    'if name in ("w_thread_spawn" "w_thread_spawn_slots")', '"loader-ast-v10"',
):
    if needle not in loader:
        raise SystemExit(f"loader lacks {needle}")
for forbidden_gate in (
    'call_name in ("cas" "increment"', 'call_name in ("send" "recv")',
    'call_name in ("cas" "get"', 'call_name in ("send" "recv" "close")',
    'call_name in ("join" "alive?" "kill")',
):
    if forbidden_gate in loader:
        raise SystemExit(f"loader retains an over-broad synchronization gate: {forbidden_gate}")
if "w_syncwrap_" in loader:
    raise SystemExit("neutral benchmark fixture leaked into loader provenance maps")

interp = (cand / "compiler/lib/interpreter.w").read_text()
for needle in (
    'when "w_atomic_new"',
    'when "w_atomic_increment"', 'when "w_atomic_decrement"',
    'when "w_chan_new"', 'when "w_chan_recv"',
    'when "w_thread_alive"', 'if recv[:name] == "Atomic"',
    'if recv[:name] == "Channel"', 'if recv[:name] == "Thread"',
    'sync_kind = ccall("w_sync_handle_kind_support", recv)',
    'if sync_kind == 1\n        class_name = "Atomic"',
    'elsif sync_kind == 2\n        class_name = "Thread"',
    'elsif sync_kind == 3\n        class_name = "Channel"',
    'if primitive_class != nil\n      native_class_name = primitive_class[:name]',
    'if native_class_name == "Atomic" && name in ("cas" "get" "set" "add")',
    'if native_class_name == "Channel" && name in ("send" "close")',
    'if native_class_name == "Thread" && name in ("join" "kill")',
    'return ccall("w_method_call", recv, "" + name, args)',
):
    if needle not in interp:
        raise SystemExit(f"interpreter lacks {needle}")
for forbidden in (
    'native_class_name = ccall("w_class_name", recv)',
    'when "w_sync_handle_kind_support"',
    'when "w_atomic_cas"', 'when "w_chan_send"',
    'when "w_atomic_get"', 'when "w_atomic_set"', 'when "w_atomic_add"',
    'when "w_chan_close"', 'when "w_thread_join"', 'when "w_thread_kill"',
    '-> dispatch_interpreted_ccall_rawargs(args)',
):
    if forbidden in interp:
        raise SystemExit(f"interpreter retains rejected source-call bridge {forbidden}")

brt = (base / "runtime/runtime.c").read_text()
crt = (cand / "runtime/runtime.c").read_text()

def c_function(text, name):
    definition = re.search(
        rf"^WValue {re.escape(name)}\([^;{{}}]*\)\s*\{{",
        text,
        re.M,
    )
    if definition is None:
        return None
    start = definition.start()
    opening = text.find("{", start, definition.end())
    depth = 0
    i = opening
    while i < len(text):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[start:i + 1]
        i += 1
    return None

if c_function(brt, "__w_type") != c_function(crt, "__w_type"):
    raise SystemExit("public type()/class_name behavior changed")
if c_function(brt, "w_class_name") != c_function(crt, "w_class_name"):
    raise SystemExit("public class_name implementation changed")
if c_function(brt, "w_sync_handle_kind_support") is not None:
    raise SystemExit("matched baseline unexpectedly has sync support-kind helper")
support_kind = c_function(crt, "w_sync_handle_kind_support")
if support_kind is None:
    raise SystemExit("candidate lacks private sync support-kind helper")
once(
    crt,
    '__attribute__((visibility("hidden")))\nWValue w_sync_handle_kind_support(WValue v)',
    "hidden support-kind definition",
)
for needle in (
    "if (w_is_atomic(v)) return w_int(1);",
    "if (w_is_thread(v)) return w_int(2);",
    "if (w_is_channel(v)) return w_int(3);",
    "return w_int(0);",
):
    once(support_kind, needle, f"private support-kind check {needle}")
runtime_h = (cand / "runtime/runtime.h").read_text()
once(runtime_h, "WValue w_sync_handle_kind_support(WValue value)", "private support-kind declaration")
once(runtime_h, 'w_sync_handle_kind_support(WValue value) __attribute__((visibility("hidden")))', "hidden support-kind declaration")

migrated_handlers = [
    "w_ic_atomic_increment", "w_ic_atomic_decrement",
    "w_ic_channel_recv", "w_ic_thread_alive",
]
retained_handlers = [
    "w_ic_atomic_cas", "w_ic_atomic_get", "w_ic_atomic_set", "w_ic_atomic_add",
    "w_ic_channel_send", "w_ic_channel_close",
    "w_ic_thread_join", "w_ic_thread_kill",
]
for name in migrated_handlers:
    if brt.count(f"static WValue {name}(") != 1:
        raise SystemExit(f"baseline lacks exactly one {name}")
    if f"static WValue {name}(" in crt:
        raise SystemExit(f"candidate retains {name}")
for dead_name in ("WN_increment", "WN_decrement", "WN_recv", "WN_alive_q"):
    if re.search(rf"\b{dead_name}\b", crt):
        raise SystemExit(f"candidate retains dead migrated method-name state {dead_name}")
for name in ("WN_cas", "WN_send"):
    if len(re.findall(rf"\b{name}\b", crt)) != 2:
        raise SystemExit(f"retained native method-name state is not exact for {name}")
for name in retained_handlers:
    if brt.count(f"static WValue {name}(") != 1 or crt.count(f"static WValue {name}(") != 1:
        raise SystemExit(f"retained native handler is not exact for {name}")
    pattern = rf"static WValue {name}\(.*?\n\}}"
    before = re.search(pattern, brt, re.S)
    after = re.search(pattern, crt, re.S)
    if before is None or after is None or before.group(0) != after.group(0):
        raise SystemExit(f"retained native handler changed for {name}")

def table_handlers(text, table):
    m = re.search(rf"static WICEntry {table}\[\] = \{{(.*?)\n\}};", text, re.S)
    if not m:
        raise SystemExit(f"missing runtime table {table}")
    return re.findall(r"\{0, (w_ic_[A-Za-z0-9_]+)\}", m.group(1))

expected_tables = {
    "w_ic_atomic_table": ["w_ic_atomic_cas", "w_ic_atomic_get", "w_ic_atomic_set", "w_ic_atomic_add"],
    "w_ic_channel_table": ["w_ic_channel_send", "w_ic_channel_close"],
    "w_ic_thread_table": ["w_ic_thread_join", "w_ic_thread_kill"],
}
for table, expected in expected_tables.items():
    if table_handlers(crt, table) != expected:
        raise SystemExit(f"candidate {table} is not dense retained-only order: {table_handlers(crt, table)}")
for assignment in (
    "w_ic_atomic_table[0].name  = WN_cas;",
    "w_ic_atomic_table[1].name  = WN_get;",
    "w_ic_atomic_table[2].name  = WN_set;",
    "w_ic_atomic_table[3].name  = WN_add;",
    "w_ic_channel_table[0].name = WN_send;",
    "w_ic_channel_table[1].name = WN_close;",
    "w_ic_thread_table[0].name = WN_join;",
    "w_ic_thread_table[1].name = WN_kill;",
):
    once(crt, assignment, f"retained IC name assignment {assignment}")
for key in ("case 0x01:", "case 0x81:", "case 0x84:"):
    if key not in brt or key not in crt:
        raise SystemExit(f"retained resolver key missing: {key}")

# Atomic memory-order parity is inherited exactly by calling the same C
# primitives. Pin their default C11 sequentially-consistent operations.
for expr in (
    "atomic_load(&as_atomic(a)->value)",
    "atomic_store(&as_atomic(a)->value, v)",
    "atomic_fetch_add(&as_atomic(a)->value, d)",
    "atomic_compare_exchange_strong(&as_atomic(a)->value, &exp, des)",
    "atomic_fetch_add(&as_atomic(a)->value, 1)",
    "atomic_fetch_sub(&as_atomic(a)->value, 1)",
):
    if expr not in crt:
        raise SystemExit(f"Atomic seq_cst primitive shape changed: {expr}")
public = (cand / "benchmarks/runtime_ports/sync_wrapper_revisit_public.w").read_text()
if "\nuse " in public or re.search(r"^\+ ", public, re.M):
    raise SystemExit("public workload must remain use-free and class-reopen-free")
for spelling in (
    ".cas(", ".get", ".set(", ".increment", ".decrement", ".add(",
    ".send(", ".recv", ".close", ".join", ".alive?", ".kill",
):
    if spelling not in public:
        raise SystemExit(f"public workload lacks {spelling}")
for fixture in ("w_syncwrap_atomic_fixture", "w_syncwrap_channel_fixture", "w_syncwrap_dead_thread_fixture"):
    once(public, f'ccall("{fixture}"', f"opaque fixture {fixture}")
for mode in (
    "fatal-atomic-bool-block", "fatal-channel-nil-block",
    "fatal-thread-bool-block", "fatal-thread-nil-block",
    "fatal-atomic-cas-missing0", "fatal-atomic-cas-missing1",
    "fatal-channel-send-missing",
):
    if mode not in public:
        raise SystemExit(f"public workload lacks fatal block mode {mode}")

ref = (cand / "benchmarks/runtime_ports/sync_wrapper_revisit_ref.c").read_text()
for primitive in (
    "w_atomic_cas", "w_atomic_get", "w_atomic_set", "w_atomic_increment",
    "w_atomic_decrement", "w_atomic_add", "w_chan_send", "w_chan_recv",
    "w_chan_close", "w_thread_join", "w_thread_join_timeout",
    "w_thread_alive", "w_thread_kill",
):
    if primitive not in ref:
        raise SystemExit(f"reference lacks primitive {primitive}")

interpreter_probe = (cand / "benchmarks/runtime_ports/sync_wrapper_revisit_interpreter.w").read_text()
for needle in (
    'check("Atomic public class_name parity", atomic.class_name, "Unknown")',
    'check("Channel public class_name parity", channel.class_name, "Unknown")',
):
    once(interpreter_probe, needle, f"interpreter public type parity {needle}")

factory_probe = (cand / "benchmarks/runtime_ports/sync_wrapper_revisit_exact_factory.w").read_text()
for needle in (
    'check("Atomic public class_name parity", ccall("w_class_name", atomic), "Unknown")',
    'check("Channel public class_name parity", ccall("w_class_name", channel), "Unknown")',
    'check("Thread public class_name parity", ccall("w_class_name", thread), "Unknown")',
    'ccall("w_sync_handle_kind_support", atomic), 1',
    'ccall("w_sync_handle_kind_support", thread), 2',
    'ccall("w_sync_handle_kind_support", channel), 3',
):
    once(factory_probe, needle, f"exact factory support/type parity {needle}")

for rel in (
    "benchmarks/runtime_ports/sync_wrapper_revisit_public.w",
    "benchmarks/runtime_ports/sync_wrapper_revisit_ref.c",
    "benchmarks/runtime_ports/sync_wrapper_revisit_interpreter.w",
    "benchmarks/runtime_ports/sync_wrapper_revisit_exact_factory.w",
    "benchmarks/runtime_ports/sync_wrapper_revisit_load_probe.w",
    "benchmarks/runtime_ports/sync_wrapper_revisit_load_probe_atomic.w",
    "benchmarks/runtime_ports/sync_wrapper_revisit_load_probe_channel.w",
    "benchmarks/runtime_ports/sync_wrapper_revisit_load_probe_factories.w",
    "benchmarks/runtime_ports/sync_wrapper_revisit_load_probe_thread.w",
    "benchmarks/runtime_ports/sync_wrapper_revisit_load_probe_retained.w",
    "benchmarks/runtime_ports/sync_wrapper_revisit_audit.md",
    "benchmarks/runtime_ports/run_sync_wrapper_revisit.sh",
):
    path = cand / rel
    if not path.is_file() or path.stat().st_size == 0:
        raise SystemExit(f"missing prepared artifact {rel}")

runner = (cand / "benchmarks/runtime_ports/run_sync_wrapper_revisit.sh").read_text()
default_kinds = "KINDS=(" + "atomic.increment atomic.decrement channel.recv thread.alive" + ")"
once(
    runner,
    default_kinds,
    "four-candidate default timing set",
)

print("PASS STATIC_ONLY: exact four-method synchronization-wrapper package, dense retained-native rows, sound narrow autoload/type routing, seq_cst parity, interpreter bridges, and neutral/load harnesses")
PY

if [ "$STATIC_ONLY" = 1 ]; then
  exit 0
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-sync-wrapper.XXXXXX")"
cleanup() {
  if [ "$KEEP_TMP" = 1 ]; then
    echo "retained temp: $TMP" >&2
  else
    rm -rf "$TMP"
  fi
}
trap cleanup EXIT

hash_file() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  else sha256sum "$1" | awk '{print $1}'; fi
}

build_trial_compiler() {
  local label="$1" root="$2" output="$3"
  local source="$TMP/compiler-source-$label" log="$TMP/compiler-$label.log"
  mkdir -p "$source/languages"
  cp -R "$root/compiler" "$source/compiler"
  cp -R "$root/core" "$source/core"
  cp -R "$root/runtime" "$source/runtime"
  cp -R "$root/languages/tungsten" "$source/languages/tungsten"
  if ! (
    cd "$source"
    TUNGSTEN_ROOT="$source" TUNGSTEN_CACHE_DIR="$TMP/cache-$label" \
      "$BOOTSTRAP_COMPILER" compile "$source/compiler/tungsten.w" \
      --release --no-lto --out "$output" >"$log" 2>&1
  ); then
    echo "$label compiler build failed" >&2
    sed -n '1,240p' "$log" >&2
    return 1
  fi
  test -x "$output" || { echo "$label compiler build produced no executable" >&2; return 1; }
  echo "prepared $label compiler $(hash_file "$output")" >&2
}

if [ "$SKIP_COMPILER_BUILD" = 0 ]; then
  if [ -z "$BOOTSTRAP_COMPILER" ] || [ ! -x "$BOOTSTRAP_COMPILER" ]; then
    echo "set BOOTSTRAP_COMPILER to one executable used for both matched roots" >&2
    exit 2
  fi
  BASELINE_COMPILER="$TMP/baseline-compiler"
  CANDIDATE_COMPILER="$TMP/candidate-compiler"
  build_trial_compiler baseline "$BASELINE_ROOT" "$BASELINE_COMPILER"
  build_trial_compiler candidate "$CANDIDATE_ROOT" "$CANDIDATE_COMPILER"
else
  for compiler in "$BASELINE_COMPILER" "$CANDIDATE_COMPILER"; do
    test -x "$compiler" || { echo "missing prebuilt compiler $compiler" >&2; exit 2; }
  done
fi

baseline_compiler_bytes="$(wc -c <"$BASELINE_COMPILER" | tr -d ' ')"
candidate_compiler_bytes="$(wc -c <"$CANDIDATE_COMPILER" | tr -d ' ')"
compiler_binary_ratio="$(awk -v c="$candidate_compiler_bytes" -v b="$baseline_compiler_bytes" 'BEGIN {printf "%.12f", c/b}')"
compiler_binary_result="COMPILER_BINARY|$baseline_compiler_bytes|$candidate_compiler_bytes|$compiler_binary_ratio"
echo "$compiler_binary_result"
if ! awk -v r="$compiler_binary_ratio" 'BEGIN {exit !(r <= 1.10)}'; then
  echo "candidate compiler binary exceeded the 10% size gate" >&2
  exit 1
fi

compile_workload() {
  local label="$1" root="$2" compiler="$3"
  local src="$root/benchmarks/runtime_ports/sync_wrapper_revisit_public.w"
  local ref="$root/benchmarks/runtime_ports/sync_wrapper_revisit_ref.c"
  (
    cd "$root"
    TUNGSTEN_ROOT="$root" TUNGSTEN_CACHE_DIR="$TMP/cache-workload-$label-wire" \
      TUNGSTEN_C_INCLUDES="$ref" \
      "$compiler" compile "$src" --emit-wire >"$TMP/$label.wire"
    TUNGSTEN_ROOT="$root" TUNGSTEN_CACHE_DIR="$TMP/cache-workload-$label-native" \
      TUNGSTEN_C_INCLUDES="$ref" \
      TUNGSTEN_LL_PATH="$TMP/$label.ll" \
      "$compiler" compile "$src" --release --out "$TMP/$label" >/dev/null
  )
  for artifact in "$TMP/$label" "$TMP/$label.wire" "$TMP/$label.ll"; do
    test -s "$artifact" || { echo "$label workload missing $artifact" >&2; exit 1; }
  done
}

compile_workload baseline "$BASELINE_ROOT" "$BASELINE_COMPILER"
compile_workload candidate "$CANDIDATE_ROOT" "$CANDIDATE_COMPILER"

python3 - "$TMP/baseline.wire" "$TMP/candidate.wire" "$TMP/candidate.ll" <<'PY'
from pathlib import Path
import re
import sys

bwire, cwire, cll = map(Path, sys.argv[1:])
bt, ct, lt = bwire.read_text(), cwire.read_text(), cll.read_text()
targets = {
    "__w_Atomic_increment__a1": "w_atomic_increment",
    "__w_Atomic_decrement__a1": "w_atomic_decrement",
    "__w_Channel_recv__a1": "w_chan_recv",
    "__w_Thread_alive_Q__a1": "w_thread_alive",
}

def body(text, name, llvm=False):
    if llvm:
        m = re.search(rf"define [^@]*@{re.escape(name)}\([^{{]*\)\s*[^{{]*\{{(.*?)\n\}}", text, re.S)
    else:
        m = re.search(rf"^function {re.escape(name)}\(.*?(?=^function |\Z)", text, re.S | re.M)
    return m.group(0) if m else None

for name, target in targets.items():
    if body(bt, name) is not None:
        raise SystemExit(f"baseline unexpectedly defines migrated source method {name}")
    wb = body(ct, name)
    if wb is None or target not in wb:
        raise SystemExit(f"candidate WIRE method {name} lacks {target}")
    # Content hashing deliberately renames source functions from their WIRE
    # names to __wy_* in emitted LLVM. Pin the lowered wrapper shape by target
    # instead: one internal i64(self) body that calls the unchanged primitive
    # with self and returns its result.
    wrapper = re.search(
        rf"define internal i64 @__wy_[0-9a-f]+\(i64 %__self\)[^{{]*\{{"
        rf".*?call i64 @{re.escape(target)}\(i64 %__self\).*?ret i64 %[^\n]+\n\}}",
        lt,
        re.S,
    )
    if wrapper is None:
        raise SystemExit(f"candidate LLVM lacks hashed source wrapper for @{target}")

print("PASS WIRE/LLVM: all four source methods route directly to their unchanged lower primitives")
PY

"$TMP/baseline" check >"$TMP/baseline.check"
"$TMP/candidate" check >"$TMP/candidate.check"
cmp "$TMP/baseline.check" "$TMP/candidate.check"
cat "$TMP/candidate.check"

for mode in \
  fatal-atomic-bool-block fatal-channel-nil-block \
  fatal-thread-bool-block fatal-thread-nil-block \
  fatal-atomic-cas-missing0 fatal-atomic-cas-missing1 \
  fatal-channel-send-missing
do
  set +e
  "$TMP/baseline" "$mode" >"$TMP/baseline.$mode.out" 2>"$TMP/baseline.$mode.err"
  bs=$?
  "$TMP/candidate" "$mode" >"$TMP/candidate.$mode.out" 2>"$TMP/candidate.$mode.err"
  cs=$?
  set -e
  if [ "$bs" -eq 0 ] || [ "$cs" -eq 0 ] || [ "$bs" -ne "$cs" ]; then
    echo "fatal parity mismatch for $mode: baseline=$bs candidate=$cs" >&2
    exit 1
  fi
  expected_error=""
  case "$mode" in
    fatal-atomic-bool-block|fatal-thread-bool-block)
      expected_error="undefined method 'each' for Boolean" ;;
    fatal-channel-nil-block|fatal-thread-nil-block)
      expected_error="undefined method 'each' for nil" ;;
    fatal-atomic-cas-missing0|fatal-atomic-cas-missing1)
      expected_error="atomic.cas requires 2 arguments" ;;
    fatal-channel-send-missing)
      expected_error="channel.send requires 1 argument" ;;
  esac
  if [ -n "$expected_error" ]; then
    for side in baseline candidate; do
      rg -Fq "$expected_error" "$TMP/$side.$mode.err" || {
        echo "$side $mode did not preserve error text: $expected_error" >&2
        exit 1
      }
      if rg -Fq "FAIL " "$TMP/$side.$mode.out"; then
        echo "$side $mode reached its impossible-return sentinel" >&2
        exit 1
      fi
    done
  fi
done

TUNGSTEN_ROOT="$CANDIDATE_ROOT" TUNGSTEN_CACHE_DIR="$TMP/cache-interpreter" \
  "$CANDIDATE_COMPILER" run \
  "$CANDIDATE_ROOT/benchmarks/runtime_ports/sync_wrapper_revisit_interpreter.w"

# Exact-factory autoload: no public synchronization selector appears in this
# source, so its emitted source classes can only come from native result maps.
FACTORY_SRC="$CANDIDATE_ROOT/benchmarks/runtime_ports/sync_wrapper_revisit_exact_factory.w"
TUNGSTEN_ROOT="$CANDIDATE_ROOT" TUNGSTEN_CACHE_DIR="$TMP/cache-exact-factory-wire" \
  "$CANDIDATE_COMPILER" compile \
  "$FACTORY_SRC" --emit-wire >"$TMP/exact-factory.wire"
TUNGSTEN_ROOT="$CANDIDATE_ROOT" TUNGSTEN_CACHE_DIR="$TMP/cache-exact-factory-native" \
  "$CANDIDATE_COMPILER" compile \
  "$FACTORY_SRC" --release --out "$TMP/exact-factory" >/dev/null
"$TMP/exact-factory"
for fn in __w_Atomic_increment__a1 __w_Channel_recv__a1 __w_Thread_alive_Q__a1; do
  rg -q "^function $fn\\(" "$TMP/exact-factory.wire" || {
    echo "exact factory autoload did not emit $fn" >&2
    exit 1
  }
done

# False-positive gate impact. Each probe is compiled repeatedly with fresh AST
# caches; binary size and median end-to-end compiler wall time are both fixed
# at <=10% candidate/baseline. The retained-name probe must load no facade.
LOAD_RESULTS="$TMP/load-impact.txt"
: >"$LOAD_RESULTS"

median_file() {
  sort -n "$1" | awk '{v[NR]=$1} END {if (NR%2) print v[(NR+1)/2]; else print (v[NR/2]+v[NR/2+1])/2}'
}

compile_probe_once() {
  local label="$1" root="$2" compiler="$3" src="$4" output="$5" cache="$6"
  local started ended
  # Separate Python processes cannot compare process-relative monotonic clocks
  # in the benchmark sandbox. Epoch wall time is shared across invocations.
  started="$(python3 -c 'import time; print(time.time_ns())')"
  TUNGSTEN_ROOT="$root" TUNGSTEN_CACHE_DIR="$cache" \
    "$compiler" compile "$src" --release --out "$output" >/dev/null
  ended="$(python3 -c 'import time; print(time.time_ns())')"
  echo $((ended - started))
}

probe_pair() {
  local tag="$1" rel="$2" expected_class="$3"
  local bsrc="$BASELINE_ROOT/$rel" csrc="$CANDIDATE_ROOT/$rel"
  local btimes="$TMP/$tag.baseline.times" ctimes="$TMP/$tag.candidate.times"
  : >"$btimes"; : >"$ctimes"
  local i=0
  while [ "$i" -lt "$LOAD_RUNS" ]; do
    if [ $((i % 2)) -eq 0 ]; then
      compile_probe_once baseline "$BASELINE_ROOT" "$BASELINE_COMPILER" "$bsrc" "$TMP/$tag.baseline.$i" "$TMP/cache-load-$tag-b-$i" >>"$btimes"
      compile_probe_once candidate "$CANDIDATE_ROOT" "$CANDIDATE_COMPILER" "$csrc" "$TMP/$tag.candidate.$i" "$TMP/cache-load-$tag-c-$i" >>"$ctimes"
    else
      compile_probe_once candidate "$CANDIDATE_ROOT" "$CANDIDATE_COMPILER" "$csrc" "$TMP/$tag.candidate.$i" "$TMP/cache-load-$tag-c-$i" >>"$ctimes"
      compile_probe_once baseline "$BASELINE_ROOT" "$BASELINE_COMPILER" "$bsrc" "$TMP/$tag.baseline.$i" "$TMP/cache-load-$tag-b-$i" >>"$btimes"
    fi
    i=$((i + 1))
  done
  TUNGSTEN_ROOT="$BASELINE_ROOT" TUNGSTEN_CACHE_DIR="$TMP/cache-load-wire-$tag-b" \
    "$BASELINE_COMPILER" compile "$bsrc" --emit-wire >"$TMP/$tag.baseline.wire"
  TUNGSTEN_ROOT="$CANDIDATE_ROOT" TUNGSTEN_CACHE_DIR="$TMP/cache-load-wire-$tag-c" \
    "$CANDIDATE_COMPILER" compile "$csrc" --emit-wire >"$TMP/$tag.candidate.wire"
  "$TMP/$tag.baseline.0" >"$TMP/$tag.baseline.out"
  "$TMP/$tag.candidate.0" >"$TMP/$tag.candidate.out"
  cmp "$TMP/$tag.baseline.out" "$TMP/$tag.candidate.out"

  for fn in __w_Atomic_increment__a1 __w_Channel_recv__a1 __w_Thread_alive_Q__a1; do
    if rg -q "^function $fn\\(" "$TMP/$tag.baseline.wire"; then
      echo "$tag baseline unexpectedly emitted migrated facade $fn" >&2
      exit 1
    fi
  done

  if [ "$expected_class" = "none" ]; then
    for fn in __w_Atomic_increment__a1 __w_Channel_recv__a1 __w_Thread_alive_Q__a1; do
      if rg -q "^function $fn\\(" "$TMP/$tag.candidate.wire"; then
        echo "retained-name probe unexpectedly loaded $fn" >&2
        exit 1
      fi
    done
  else
    case "$expected_class" in
      Atomic) expected_fn=__w_Atomic_increment__a1 ;;
      Channel) expected_fn=__w_Channel_recv__a1 ;;
      Thread) expected_fn=__w_Thread_alive_Q__a1 ;;
      all) expected_fn=__w_Atomic_increment__a1 ;;
    esac
    rg -q "^function $expected_fn\\(" "$TMP/$tag.candidate.wire" || {
      echo "$tag did not load expected $expected_class facade" >&2
      exit 1
    }
    if [ "$expected_class" = "all" ]; then
      for fn in __w_Channel_recv__a1 __w_Thread_alive_Q__a1; do
        rg -q "^function $fn\\(" "$TMP/$tag.candidate.wire" || exit 1
      done
    else
      for pair in \
        Atomic:__w_Atomic_increment__a1 \
        Channel:__w_Channel_recv__a1 \
        Thread:__w_Thread_alive_Q__a1
      do
        owner="${pair%%:*}"
        fn="${pair#*:}"
        if [ "$owner" != "$expected_class" ] && rg -q "^function $fn\\(" "$TMP/$tag.candidate.wire"; then
          echo "$tag unexpectedly bundled the unrelated $owner facade" >&2
          exit 1
        fi
      done
    fi
  fi

  local btime ctime tratio bbytes cbytes bratio verdict
  btime="$(median_file "$btimes")"
  ctime="$(median_file "$ctimes")"
  tratio="$(awk -v c="$ctime" -v b="$btime" 'BEGIN {printf "%.12f", c/b}')"
  bbytes="$(wc -c <"$TMP/$tag.baseline.0" | tr -d ' ')"
  cbytes="$(wc -c <"$TMP/$tag.candidate.0" | tr -d ' ')"
  bratio="$(awk -v c="$cbytes" -v b="$bbytes" 'BEGIN {printf "%.12f", c/b}')"
  verdict=PASS
  if ! awk -v t="$tratio" -v s="$bratio" 'BEGIN {exit !(t <= 1.10 && s <= 1.10)}'; then verdict=FAIL; fi
  echo "LOAD|$tag|$btime|$ctime|$tratio|$bbytes|$cbytes|$bratio|$verdict" | tee -a "$LOAD_RESULTS"
  [ "$verdict" = PASS ] || { echo "$tag gate load impact exceeded 10%" >&2; exit 1; }
}

probe_pair atomic-gate benchmarks/runtime_ports/sync_wrapper_revisit_load_probe_atomic.w Atomic
probe_pair channel-gate benchmarks/runtime_ports/sync_wrapper_revisit_load_probe_channel.w Channel
probe_pair thread-gate benchmarks/runtime_ports/sync_wrapper_revisit_load_probe_thread.w Thread
probe_pair exact-factories benchmarks/runtime_ports/sync_wrapper_revisit_load_probe_factories.w all
probe_pair retained-names benchmarks/runtime_ports/sync_wrapper_revisit_load_probe_retained.w none
probe_pair combined-gates benchmarks/runtime_ports/sync_wrapper_revisit_load_probe.w all

if [ "$CHECK_ONLY" = 1 ]; then
  echo "CHECK_ONLY=1: synchronization-wrapper correctness/WIRE/LLVM/autoload/interpreter audit passed; timings skipped"
  exit 0
fi

ALL_KINDS=(
  atomic.cas atomic.get atomic.set atomic.increment atomic.decrement atomic.add
  channel.send channel.recv channel.close
  thread.join0 thread.join1 thread.alive thread.kill
)
KINDS=(atomic.increment atomic.decrement channel.recv thread.alive)
if [ -n "$ONLY" ]; then
  found=0
  for kind in "${ALL_KINDS[@]}"; do [ "$kind" = "$ONLY" ] && found=1; done
  [ "$found" -eq 1 ] || { echo "unknown ONLY=$ONLY" >&2; exit 2; }
  KINDS=("$ONLY")
fi

iters_for() {
  case "$1" in
    atomic.*|thread.join0|thread.join1|thread.alive) echo 2000000 ;;
    channel.*) echo 200000 ;;
    thread.kill) echo 100 ;;
  esac
}

warmup_for() {
  case "$1" in
    atomic.*|thread.join0|thread.join1|thread.alive) echo 20000 ;;
    channel.*) echo 2000 ;;
    thread.kill) echo 5 ;;
  esac
}

sample_field() {
  printf '%s\n' "$1" | awk -F'|' -v f="$2" '$1 == "RESULT" {print $f}'
}

run_pair() {
  local kind="$1" iters="$2" warmup="$3" parity="$4"
  local b1 b2 c1 c2
  if [ $((parity % 2)) -eq 0 ]; then
    b1="$("$TMP/baseline" bench "$kind" "$iters" "$warmup")"
    c1="$("$TMP/candidate" bench "$kind" "$iters" "$warmup")"
    c2="$("$TMP/candidate" bench "$kind" "$iters" "$warmup")"
    b2="$("$TMP/baseline" bench "$kind" "$iters" "$warmup")"
  else
    c1="$("$TMP/candidate" bench "$kind" "$iters" "$warmup")"
    b1="$("$TMP/baseline" bench "$kind" "$iters" "$warmup")"
    b2="$("$TMP/baseline" bench "$kind" "$iters" "$warmup")"
    c2="$("$TMP/candidate" bench "$kind" "$iters" "$warmup")"
  fi
  local checksum elapsed
  checksum="$(sample_field "$b1" 4)"
  for sample in "$b1" "$b2" "$c1" "$c2"; do
    [ "$(sample_field "$sample" 2)" = "$kind" ] || { echo "sample label mismatch for $kind" >&2; exit 1; }
    elapsed="$(sample_field "$sample" 3)"
    awk -v t="$elapsed" 'BEGIN {exit !(t > 0)}' || { echo "non-positive timer sample for $kind: $elapsed" >&2; exit 1; }
    [ "$(sample_field "$sample" 4)" = "$checksum" ] || { echo "checksum mismatch for $kind" >&2; exit 1; }
  done
  local bsum csum ratio
  bsum="$(awk -v a="$(sample_field "$b1" 3)" -v b="$(sample_field "$b2" 3)" 'BEGIN {printf "%.0f", a+b}')"
  csum="$(awk -v a="$(sample_field "$c1" 3)" -v b="$(sample_field "$c2" 3)" 'BEGIN {printf "%.0f", a+b}')"
  ratio="$(awk -v c="$csum" -v b="$bsum" 'BEGIN {printf "%.12f", c/b}')"
  echo "PAIR|$kind|$ratio|$checksum|$bsum|$csum"
}

median_stream() {
  sort -n | awk '{v[NR]=$1} END {if (NR%2) print v[(NR+1)/2]; else print (v[NR/2]+v[NR/2+1])/2}'
}

: >"$RESULTS_OUT"
echo "$compiler_binary_result" >>"$RESULTS_OUT"
cat "$LOAD_RESULTS" >>"$RESULTS_OUT"
overall=0
for kind in "${KINDS[@]}"; do
  iters="$(iters_for "$kind")"
  warmup="$(warmup_for "$kind")"
  pairs="$TMP/$kind.pairs"
  : >"$pairs"
  run=0
  while [ "$run" -lt "$RUNS" ]; do
    pair="$(run_pair "$kind" "$iters" "$warmup" "$run")"
    echo "$pair" | tee -a "$pairs" "$RESULTS_OUT"
    run=$((run + 1))
  done
  median="$(awk -F'|' '$1=="PAIR" {print $3}' "$pairs" | median_stream)"
  verdict="PASS"
  if ! awk -v r="$median" -v g="$GATE" 'BEGIN {exit !(r <= g)}'; then
    verdict="FAIL"
    overall=1
  fi
  summary="SUMMARY|$kind|$median|$verdict|$RUNS|$iters"
  echo "$summary" | tee -a "$RESULTS_OUT"
done

[ "$overall" -eq 0 ] || { echo "one or more methods exceeded the <=$GATE gate" >&2; exit 1; }
echo "PASS campaign REPEAT=$REPEAT: every independently timed synchronization-wrapper method is <=$GATE"
