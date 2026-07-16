#!/usr/bin/env bash
# Matched-root three-way revisit for String/Symbol#size/#length, plus a
# separate fixed-root check for resolved public String/Symbol class identity.
#
# Baseline retains the shared native IC. `direct` calls the canonical byte-
# length helper and performs checked w_int boxing. `branchless` calls that same
# canonical helper, then constructs the exact tagged i48 result without a range
# branch or cold w_int edge. STATIC_ONLY=1 is the safe default while another
# benchmark lane is active. Set STATIC_ONLY=0 to build/check, then CHECK_ONLY=0
# only when exclusive timing is available.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASELINE_ROOT="${BASELINE_ROOT:-/tmp/tungsten-string-length-revisit-baseline}"
DIRECT_ROOT="${DIRECT_ROOT:-/tmp/tungsten-string-length-revisit-direct}"
BRANCHLESS_ROOT="${BRANCHLESS_ROOT:-/tmp/tungsten-string-length-revisit-branchless}"
BOOTSTRAP_COMPILER="${BOOTSTRAP_COMPILER:-}"
SKIP_COMPILER_BUILD="${SKIP_COMPILER_BUILD:-0}"
BASELINE_COMPILER="${BASELINE_COMPILER:-}"
DIRECT_COMPILER="${DIRECT_COMPILER:-}"
BRANCHLESS_COMPILER="${BRANCHLESS_COMPILER:-}"
STATIC_ONLY="${STATIC_ONLY:-1}"
CHECK_ONLY="${CHECK_ONLY:-1}"
REPEAT="${REPEAT:-0}"
RUNS="${RUNS:-10}"
ITERS="${ITERS:-20000000}"
WARMUP="${WARMUP:-500000}"
GATE="${GATE:-1.10}"
ONLY="${ONLY:-}"
KEEP_TMP="${KEEP_TMP:-0}"

for toggle in STATIC_ONLY CHECK_ONLY REPEAT SKIP_COMPILER_BUILD KEEP_TMP; do
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
case "$ONLY" in ''|string.size|string.length|symbol.size|symbol.length) ;;
  *) echo "ONLY must be empty or one of string.size/string.length/symbol.size/symbol.length" >&2; exit 2 ;;
esac
if ! awk -v gate="$GATE" 'BEGIN { exit !(gate ~ /^[0-9]+([.][0-9]+)?$/ && gate > 0) }'; then
  echo "GATE must be positive" >&2
  exit 2
fi

BASELINE_ROOT="$(cd "$BASELINE_ROOT" && pwd)"
DIRECT_ROOT="$(cd "$DIRECT_ROOT" && pwd)"
BRANCHLESS_ROOT="$(cd "$BRANCHLESS_ROOT" && pwd)"
roots=("$BASELINE_ROOT" "$DIRECT_ROOT" "$BRANCHLESS_ROOT")
if [ "$(printf '%s\n' "${roots[@]}" | sort -u | wc -l | tr -d ' ')" != 3 ]; then
  echo "baseline/direct/branchless must be distinct isolated roots" >&2
  exit 2
fi

baseline_head="$(git -C "$BASELINE_ROOT" rev-parse HEAD)"
direct_head="$(git -C "$DIRECT_ROOT" rev-parse HEAD)"
branchless_head="$(git -C "$BRANCHLESS_ROOT" rev-parse HEAD)"
if [ "$baseline_head" != "$direct_head" ] || [ "$baseline_head" != "$branchless_head" ]; then
  echo "matched-root HEAD mismatch: $baseline_head / $direct_head / $branchless_head" >&2
  exit 1
fi

# Exact source/runtime/loader/interpreter shape check. No compiler or linker is
# invoked before this finishes, so STATIC_ONLY=1 is a genuinely light audit.
python3 - "$BASELINE_ROOT" "$DIRECT_ROOT" "$BRANCHLESS_ROOT" <<'PY'
from pathlib import Path
import hashlib
import re
import subprocess
import sys

base, direct, branchless = map(Path, sys.argv[1:])

base_changed = subprocess.run(
    ["git", "-C", str(base), "diff", "--name-only", "HEAD", "--"],
    check=True, capture_output=True, text=True
).stdout.splitlines()
if base_changed != ["compiler/lib/builtins.w", "compiler/lib/interpreter.w", "runtime/runtime.c"]:
    raise SystemExit(f"fixed native baseline must differ only in shared builtin/interpreter fixes + class identity: {base_changed}")

def once(text, needle, label):
    n = text.count(needle)
    if n != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {n}")

def region(text, start, end, label):
    once(text, start, f"{label} start")
    once(text, end, f"{label} end")
    i = text.index(start)
    j = text.index(end, i)
    return text[i:j]

base_rt = (base / "runtime/runtime.c").read_text()
if base_rt.count("w_ic_string_length") != 3:
    raise SystemExit("baseline must contain one length handler and two table rows")
head_rt = subprocess.run(
    ["git", "-C", str(base), "show", "HEAD:runtime/runtime.c"],
    check=True, capture_output=True, text=True
).stdout

def replace_once(text, old, new, label):
    once(text, old, label)
    return text.replace(old, new)

# Prove the native baseline's runtime delta is exactly the final resolved-entry
# public-identity cache. Pin the two broad changed regions before replacing
# them with their HEAD counterparts; this prevents an unrelated edit inside a
# hot function from being normalized away. Candidate roots additionally carry
# the separately audited String IC removal/reindex, but must have byte-identical
# public-identity regions.
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
class_start = 'WValue w_class_new(const char *name, WValue superclass) {'
class_end = 'WValue w_class_new_wv(WValue name, WValue superclass) {'
identity_start = '/* ---- Type class table: dispatch key → class_id for Tungsten-defined methods ---- */'
identity_end = 'WValue w_class_name(WValue v) {'
fixed_class = region(base_rt, class_start, class_end, "fixed class cache region")
head_class = region(head_rt, class_start, class_end, "HEAD class control region")
fixed_identity = region(base_rt, identity_start, identity_end, "fixed public lookup region")
head_identity = region(head_rt, identity_start, identity_end, "HEAD public lookup control region")
expected_hashes = {
    "fixed class cache": (fixed_class, "4727ee7384b16016f6b687bc6d639984f49b1ce3a21dc28a5420677879b192fe"),
    "HEAD class control": (head_class, "4a34f4ba41111274771b06e26b295fa9fbb5c50cef3c0fcd6d10de83f8ffc235"),
    "fixed public lookup": (fixed_identity, "b69a6128d067e23a9e4a343adb6ca90f3f5173ce8a9a68adbfc321cbe2445f8f"),
    "HEAD public control": (head_identity, "514bf60b07bbf06b9e8cc3c9439b1fda329fae206c7ec7493885d7a9598a1a1e"),
}
for label, (body, expected) in expected_hashes.items():
    got = hashlib.sha256(body.encode()).hexdigest()
    if got != expected:
        raise SystemExit(f"{label} hash drift: {got} != {expected}")

normalized_rt = replace_once(base_rt, cache_decl, "", "resolved public identity cache declaration")
normalized_rt = replace_once(normalized_rt, fixed_class, head_class, "class cache region")
normalized_rt = replace_once(normalized_rt, fixed_identity, head_identity, "public lookup region")
if normalized_rt != head_rt:
    raise SystemExit("fixed native baseline runtime contains changes beyond the exact resolved-entry public identity repair")

for root in (direct, branchless):
    runtime = (root / "runtime/runtime.c").read_text()
    once(runtime, cache_decl, f"{root.name} resolved public identity cache declaration")
    if region(runtime, class_start, class_end, f"{root.name} class cache region") != fixed_class:
        raise SystemExit(f"{root.name}: class cache region differs from the fixed native baseline")
    if region(runtime, identity_start, identity_end, f"{root.name} public lookup region") != fixed_identity:
        raise SystemExit(f"{root.name}: public lookup region differs from the fixed native baseline")

for needle in (
    'static WPublicClassEntry g_public_type_class[512] = {0};',
    'else if (strcmp(name, "Symbol") == 0) {',
    '!w_is_class(g_public_type_class[0x101].value)',
    'static void w_public_type_class_register(uint8_t key, WClass *klass)',
    'key == W_SUBTAG_ATOMIC',
    'key == (0x80u | W_TYPE_THREAD)',
    'key == (0x80u | W_TYPE_CHANNEL)',
    'key == 0xE6',
    'g_public_type_class[key].resolved = 0;',
    'g_public_type_class[0x100u | key].resolved = 0;',
    'public_slot = (unsigned)key | ((unsigned)(v & 1u) << 8);',
    'if (cached->resolved) return cached->value;',
    'if (klass && strcmp(klass->name, want) == 0) {',
    'if (cacheable) w_public_class_cache(public_slot, W_NIL);',
    'w_public_class_cache(0x001, class_value);',
    'w_public_class_cache(0x101, class_value);',
    'w_public_class_cache(0x081, class_value);',
    'w_public_class_cache(0x181, class_value);',
    'w_public_class_cache(0x084, class_value);',
    'w_public_class_cache(0x184, class_value);',
):
    if base_rt.count(needle) != 1:
        raise SystemExit(f"fixed runtime lacks unique resolved public-identity path: {needle}")
    if needle in head_rt:
        raise SystemExit(f"HEAD control unexpectedly contains resolved public-identity path: {needle}")
for stale in (
    "g_public_symbol_class", "g_declared_unknown_class",
    "g_public_unknown_class", "public_class_singleton",
):
    for root in (base, direct, branchless):
        if stale in (root / "runtime/runtime.c").read_text():
            raise SystemExit(f"{root.name}: stale singleton public-identity cache remains: {stale}")

for root in (base, direct, branchless):
    builtins = (root / "compiler/lib/builtins.w").read_text()
    once(builtins,
         'target = args.empty?() ? recv : args[0]\n    type(target)',
         f"{root.name} explicit-argument type builtin")
    interpreter = (root / "compiler/lib/interpreter.w").read_text()
    once(interpreter,
         'if type(recv) in ("String" "Symbol") && name == "to_sym"',
         f"{root.name} common primitive to_sym interpreter route")
    once(interpreter,
         'recv = ccall("w_rope_flatten", recv)\n      return ccall("w_str_to_sym", recv)',
         f"{root.name} rope-safe direct to_sym bridge")
    once(interpreter,
         'if type(recv) in ("String" "Symbol") && name == "is_a?" && args.size() == 1\n      return is_a_class?(recv, args[0])',
         f"{root.name} pre-autoload String/Symbol is_a identity route")
    once(interpreter, 'when "w_str_to_sym"',
         f"{root.name} common w_str_to_sym interpreter bridge")
    once(interpreter, 'when "w_string_byte_length"',
         f"{root.name} canonical byte-length interpreter bridge")
    once(interpreter, 'if primitive_name in ("String" "Symbol")',
         f"{root.name} exact primitive is_a interpreter identity")
base_interpreter = (base / "compiler/lib/interpreter.w").read_text()
once(base_interpreter,
     'if type(recv) == "Symbol" && (name == "size" || name == "length")',
     "baseline native Symbol length fallback")
for root, variant in ((direct, "direct"), (branchless, "branchless")):
    source = (root / "core/string_native.w").read_text()
    if source.count("\n  -> size\n") != 1 or source.count("\n  -> length\n") != 1:
        raise SystemExit(f"{variant}: source size/length definitions are not unique")
    runtime = (root / "runtime/runtime.c").read_text()
    if "w_ic_string_length" in runtime:
        raise SystemExit(f"{variant}: removed native length handler/row remains")

    table_match = re.search(r"static WICEntry w_ic_string_table\[\] = \{(.*?)\n\};", runtime, re.S)
    if not table_match:
        raise SystemExit(f"{variant}: missing String IC table")
    rows = re.findall(r"\{0,\s*(w_ic_[a-zA-Z0-9_]+)\}", table_match.group(1))
    expected_rows = [
        "w_ic_string_idx", "w_ic_string_upcase", "w_ic_string_downcase",
        "w_ic_string_swapcase", "w_ic_string_capitalize", "w_ic_string_concat",
        "w_ic_string_concat", "w_ic_string_concat", "w_ic_string_prepend",
        "w_ic_string_include", "w_ic_string_starts_with", "w_ic_string_ends_with",
        "w_ic_string_ascii_q", "w_ic_string_valid_utf8_q", "w_ic_string_repeat",
        "w_ic_string_chars", "w_ic_string_codes", "w_ic_string_lchs",
        "w_ic_string_bytes", "w_ic_string_slice", "w_ic_string_strip",
        "w_ic_string_ltrim", "w_ic_string_rtrim", "w_ic_string_ord",
        "w_ic_string_to_i", "w_ic_string_to_f", "w_ic_string_to_sym",
        "w_ic_string_split", "w_ic_string_replace", "w_ic_string_replace",
        "w_ic_string_index", "w_ic_string_matchop", "w_ic_string_matchop",
        "w_ic_string_rindex", "w_ic_string_reverse", "w_ic_string_empty",
    ]
    if rows != expected_rows:
        raise SystemExit(f"{variant}: String IC rows are not the exact 36-row reindex: {rows}")
    assigns = re.findall(r"w_ic_string_table\[(\d+)\]\.name\s*=\s*(WN_[a-zA-Z0-9_]+);", runtime)
    expected_names = [
        "WN_idx", "WN_upcase", "WN_downcase", "WN_swapcase", "WN_capitalize",
        "WN_concat", "WN_append", "WN_lshift", "WN_prepend", "WN_include_q",
        "WN_starts_with_q", "WN_ends_with_q", "WN_ascii_q", "WN_valid_utf8_q",
        "WN_repeat", "WN_chars", "WN_codes", "WN_lchs", "WN_bytes", "WN_slice",
        "WN_strip", "WN_ltrim", "WN_rtrim", "WN_ord", "WN_to_i", "WN_to_f",
        "WN_to_sym", "WN_split", "WN_replace", "WN_gsub", "WN_index",
        "WN_matchop", "WN_match_q", "WN_rindex", "WN_reverse", "WN_empty_q",
    ]
    if assigns != [(str(i), name) for i, name in enumerate(expected_names)]:
        raise SystemExit(f"{variant}: String IC name assignments are not contiguous/exact")

    # Pin the established public receiver contract as well as the canonical
    # helper's own defensive flatten: no source String body may see pointer bits
    # from a WRope before the 0xF9 dispatch key is selected.
    def function_body(signature):
        start = runtime.find(signature)
        if start < 0: raise SystemExit(f"{variant}: missing {signature}")
        brace = runtime.find("{", start)
        depth = 0
        for i in range(brace, len(runtime)):
            if runtime[i] == "{": depth += 1
            elif runtime[i] == "}":
                depth -= 1
                if depth == 0: return runtime[brace:i+1]
        raise SystemExit(f"{variant}: unterminated {signature}")
    for signature in (
        "WValue w_method_call_cached(WValue recv",
        "WValue w_method_call_cached_0(WValue recv",
    ):
        body = function_body(signature)
        flatten = body.find("w_is_rope(recv)")
        key = body.find("w_dispatch_key(recv)")
        if flatten < 0 or key < 0 or flatten > key:
            raise SystemExit(f"{variant}: {signature} no longer flattens rope before dispatch key")
    generic = function_body("static WValue w_method_dispatch(WValue recv, WValue name, WArray *args, WValue args_arr) {")
    flatten = generic.find("w_is_rope(recv)")
    resolve = generic.find("w_resolve_ic(")
    if flatten < 0 or resolve < 0 or flatten > resolve:
        raise SystemExit(f"{variant}: generic dispatch no longer flattens rope before IC/type dispatch")

    loader = (root / "compiler/lib/loader.w").read_text()
    once(loader, '@string_length_unresolved = defined["String"] != true && registry["String"] != nil && @autoload_loaded["String"] != true', f"{variant} loader flag")
    once(loader, 'if @string_length_unresolved\n        if call_name in ("size" "length")', f"{variant} direct-name loader gate")
    once(loader, 'elsif call_name in ("map" "select" "reject" "count") && node.block == nil && call_receiver != nil && node.args != nil && node.args.size() == 1', f"{variant} symbol-to-proc outer gate")
    once(loader, 'ast_kind(iteratee) == :symbol && iteratee.value in ("size" "length") && ast_kind(call_receiver) in (:range :array :var :call :map :calc)', f"{variant} generated-call loader gate")
    once(loader, '"loader-ast-v11"', f"{variant} cache epoch")
    lowering = (root / "compiler/lib/lowering/method_call.w").read_text()
    once(lowering, 'method_name in ("map" "select" "reject" "count")', f"{variant} symbol-to-proc lowering methods")
    once(lowering, 'ast_kind(recv_node) in (:range :array :var :call :map :calc)', f"{variant} symbol-to-proc lowering receivers")
    once(lowering, 'per_elem = Tungsten:AST:Call.new(nil, "" + ast_get(node.args[0], :value), [], nil)', f"{variant} generated per-element call")
    interpreter = (root / "compiler/lib/interpreter.w").read_text()
    once(interpreter, 'name in ("size" "length")', f"{variant} Symbol interpreter route")
    once(interpreter, 'if m[:w_class] != nil && m[:w_class][:name] == "String"', f"{variant} declaring-String rope guard")
    once(interpreter, 'if m[:w_class] != nil && m[:w_class][:name] == "String"\n          recv = ccall("w_rope_flatten", recv)', f"{variant} tree-walker String-method rope canonicalization")
    compiler = (root / "compiler/tungsten.w").read_text()
    if not compiler.startswith("# The self-host calls size/length") or compiler.count("use core/string_native\n") != 1:
        raise SystemExit(f"{variant}: compiler bootstrap anchor missing/duplicated")

direct_src = (direct / "core/string_native.w").read_text()
if direct_src.count('ccall_nobox("w_string_byte_length", self)') != 2:
    raise SystemExit("direct: canonical byte-length helper must appear once per method")
if direct_src.count('ccall("w_int", n)') != 2 or direct_src.count("140_737_488_355_327") != 2:
    raise SystemExit("direct: exact signed-i48 checked boxing is incomplete")
if "w_string_stored_byte_length" in direct_src:
    raise SystemExit("direct: optimized bridge leaked into reference candidate")

branchless_src = (branchless / "core/string_native.w").read_text()
if branchless_src.count('ccall_nobox("w_string_byte_length", self)') != 2:
    raise SystemExit("branchless: canonical byte-length helper must appear once per method")
if branchless_src.count("tag = -1_688_849_860_263_936 ## i64") != 2:
    raise SystemExit("branchless: exact 0xFFFA signed-i48 tag must appear once per method")
if branchless_src.count("wvalue_from_bits((tag | n) ## i64)") != 2:
    raise SystemExit("branchless: exact tag-or-result construction must appear once per method")
for forbidden in (
    'ccall("w_int", n)', "140_737_488_355_327", "140_737_488_355_328",
    "mask =", "if n ", "w_string_stored_byte_length",
):
    if forbidden in branchless_src:
        raise SystemExit(f"branchless: forbidden checked/masked/narrow path remains: {forbidden}")
for rel in ("compiler/lib/builtins.w", "compiler/lib/interpreter.w", "compiler/lib/loader.w",
            "compiler/tungsten.w", "runtime/runtime.c"):
    if (direct / rel).read_bytes() != (branchless / rel).read_bytes():
        raise SystemExit(f"branchless: {rel} must exactly match direct; only the source boxing body differs")
branchless_header = (branchless / "runtime/runtime.h").read_text()
if not re.search(r"typedef struct WString\s*\{\s*uint32_t len;", branchless_header):
    raise SystemExit("branchless: WString.len is no longer pinned to uint32_t")
if not re.search(r"uint32_t total_len;\s*/\* cached byte length \*/.*?\}\s*WRope;", branchless_header, re.S):
    raise SystemExit("branchless: WRope.total_len is no longer pinned to uint32_t")
branchless_rt = (branchless / "runtime/runtime.c").read_text()
once(branchless_rt, "int64_t w_string_byte_length(int64_t str_wval)", "branchless canonical helper")
if "*len = slot[1];" not in branchless_rt:
    raise SystemExit("branchless: slab length is no longer read from the uint8_t slot")
if "return (int64_t)len;" not in branchless_rt:
    raise SystemExit("branchless: canonical helper no longer returns the stored length as i64")

for rel in (
    "benchmarks/runtime_ports/string_length_revisit_public.w",
    "benchmarks/runtime_ports/string_length_revisit_ref.c",
    "benchmarks/runtime_ports/string_length_loader_control.w",
    "benchmarks/runtime_ports/string_length_loader_size_probe.w",
    "benchmarks/runtime_ports/string_length_loader_length_probe.w",
    "spec/compiler/string_size_no_use_native_spec.w",
    "spec/compiler/string_length_no_use_rope_spec.w",
    "spec/compiler/symbol_size_no_use_native_spec.w",
    "spec/compiler/symbol_length_no_use_native_spec.w",
    "spec/compiler/string_size_symbol_proc_map_no_use_spec.w",
    "spec/compiler/string_size_symbol_proc_select_no_use_spec.w",
    "spec/compiler/string_size_symbol_proc_reject_no_use_spec.w",
    "spec/compiler/string_size_symbol_proc_count_no_use_spec.w",
    "spec/compiler/string_length_symbol_proc_map_no_use_spec.w",
    "spec/compiler/string_length_symbol_proc_select_no_use_spec.w",
    "spec/compiler/string_length_symbol_proc_reject_no_use_spec.w",
    "spec/compiler/string_length_symbol_proc_count_no_use_spec.w",
    "spec/compiler/string_symbol_class_identity_spec.w",
    "spec/interpreter/string_length_revisit_spec.w",
    "benchmarks/runtime_ports/string_symbol_class_identity_bench.w",
):
    if not (branchless / rel).is_file():
        raise SystemExit(f"missing prepared fixture {rel}")

workload = (branchless / "benchmarks/runtime_ports/string_length_revisit_public.w").read_text()
for name in ("time_string_size", "time_string_length", "time_symbol_size", "time_symbol_length"):
    once(workload, f"-> {name}(values, iters, run_id)", f"timing body {name}")
if workload.count('ccall_nobox("w_strlen_thread_cpu_ns")') != 8:
    raise SystemExit("workload must contain exactly two raw thread clocks per timing body")
ref = (branchless / "benchmarks/runtime_ports/string_length_revisit_ref.c").read_text()
once(ref, "clock_gettime(CLOCK_THREAD_CPUTIME_ID, &ts)", "thread CPU clock")
if "inline_nul" not in ref or "w_str_concat" not in ref or "w_str_to_sym" not in ref or "w_strlen_fresh_rope" not in ref:
    raise SystemExit("reference fixture lacks NUL/rope-first/Symbol coverage")
once(ref, "WValue w_strlen_one_string_array(void)", "unmapped native WArray fixture")
once(ref, "WValue values = w_array_new_empty();", "fixture-native WArray constructor")
once(ref, 'w_array_push(values, w_string("a"));', "fixture-native WArray population")
once(ref, "WValue w_class_identity_register_facade(WValue key_value, WValue klass)",
     "delayed class-facade registration helper")
once(ref, "WValue w_class_identity_declare_unknown(void)",
     "delayed explicit Unknown class helper")
interpreter_fixture = (branchless / "spec/interpreter/string_length_revisit_spec.w").read_text()
once(interpreter_fixture, "use core/string_native", "interpreter String registration")
once(interpreter_fixture, "rope_symbol = rope_for_symbol.to_sym", "fresh-rope to_sym regression")
once(interpreter_fixture, 'check("symbol.fresh-rope.content"', "fresh-rope symbol content check")
for needle in (
    'type(identity_symbol), "Symbol"',
    'identity_symbol.class_name, "Symbol"',
    'identity_symbol_class.name, "Symbol"',
    'identity_symbol.class == identity_symbol_class, true',
    'identity_symbol.is_a?("Symbol"), true',
    'identity_symbol.is_a?(identity_symbol_class), true',
    'identity_symbol.is_a?("String"), false',
    'type(identity_string), "String"',
    'identity_string.class_name, "String"',
    'identity_string_class.name, "String"',
    'identity_string.class == identity_string_class, true',
    'identity_string.is_a?("String"), true',
    'identity_string.is_a?(identity_string_class), true',
    'identity_string.is_a?("Symbol"), false',
    'identity_string_class == identity_symbol_class, false',
):
    if needle not in interpreter_fixture:
        raise SystemExit(f"interpreter class-identity fixture lacks {needle}")

identity_spec = (branchless / "spec/compiler/string_symbol_class_identity_spec.w").read_text()
once(identity_spec, "use core/string_native", "compiled identity String registration")
for needle in (
    'type(symbol), "Symbol"',
    'symbol.class_name, "Symbol"',
    'ccall("w_class_identity_class_label", symbol_class), "Symbol"',
    'wvalue_bits(symbol.class), wvalue_bits(symbol_class)',
    'symbol.is_a?("Symbol"), true',
    'symbol.is_a?(symbol_class), true',
    'symbol.is_a?("String"), false',
    'type(string), "String"',
    'string.class_name, "String"',
    'ccall("w_class_identity_class_label", string_class), "String"',
    'wvalue_bits(string.class), wvalue_bits(string_class)',
    'string.is_a?("String"), true',
    'string.is_a?(string_class), true',
    'string.is_a?("Symbol"), false',
    'string_class == symbol_class, false',
    '+ AtomicIdentityFacade',
    '+ ThreadIdentityFacade',
    '+ ChannelIdentityFacade',
    '+ ArrayIdentityFacade',
    'value.class_name, "Unknown"',
    'check("[name] class before", before, nil)',
    'check("[name] class after", after, nil)',
    'check("[name] class stable across facade", after, before)',
    'ccall("w_class_identity_register_facade", key, facade)',
    'value.is_a?(facade), false',
    'value.identity_facade_probe, key',
    'Atomic.new(0)',
    'Channel.new(1)',
    'Thread.new ->',
    'check("Declared Unknown class before declaration", atomic.class, nil)',
    'declared = ccall("w_class_identity_declare_unknown")',
    'check("Declared Unknown class selected", atomic.class, declared)',
    'check("Declared Unknown class after facade", atomic.class, declared)',
    'check("Array alias class stable bits", wvalue_bits(value.class), wvalue_bits(before))',
    'check("Array alias not facade identity", value.is_a?(ArrayIdentityFacade), false)',
    'check("Array alias facade method dispatch", value.identity_facade_probe, 10)',
    'check("Array cold alias class", ccall("w_class_identity_class_label", selected), "Array")',
    'check("Array cold alias not facade identity", value.is_a?(ArrayIdentityFacade), false)',
    'check("Late Hash cache replaced", before == after, false)',
    'check("Late Hash registered class selected", wvalue_bits(after), wvalue_bits(declared))',
):
    if needle not in identity_spec:
        raise SystemExit(f"compiled class-identity fixture lacks {needle}")

identity_workload = (branchless / "benchmarks/runtime_ports/string_symbol_class_identity_bench.w").read_text()
once(identity_workload, "use core/string_native", "identity benchmark String registration")
if identity_workload.count('ccall_nobox("w_strlen_thread_cpu_ns")') != 2:
    raise SystemExit("identity benchmark must contain exactly two raw thread clocks")
match = re.search(r"^-> time_public_class\(value, iters, run_id\)\n(.*?)(?=^-> |\Z)",
                  identity_workload, re.M | re.S)
if not match:
    raise SystemExit("identity benchmark lacks unique three-argument public class timer")
body = match.group(1)
body_code = "\n".join(line for line in body.splitlines() if not line.lstrip().startswith("#"))
if body_code.count(".class") != 2:
    raise SystemExit("identity benchmark timer must have one setup and one timed public .class call")
if body_code.count('ccall_nobox("w_strlen_thread_cpu_ns")') != 2:
    raise SystemExit("identity benchmark timer must have exactly two raw thread clocks")
if "wvalue_bits(value.class) ^ expected_bits" not in body_code or \
   "mismatch = (mismatch |" not in body_code:
    raise SystemExit("identity benchmark must consume every class result through raw xor/or mismatch")
for stratum in ("string.class", "symbol.class", "atomic.class", "thread.class", "channel.class"):
    if f'"{stratum}"' not in identity_workload:
        raise SystemExit(f"identity benchmark lacks {stratum}")
for key, facade in (("0x01", "AtomicIdentityFacade"),
                    ("0x81", "ThreadIdentityFacade"),
                    ("0x84", "ChannelIdentityFacade")):
    once(identity_workload, f'ccall("w_class_identity_register_facade", {key}, {facade})',
         f"identity benchmark delayed {facade} registration")
once(identity_workload, '<< "IDENTITY_RESULT|[stratum]|[result[0]]|[args[2]]|[result[1]]"',
     "identity result record")
once(identity_workload, '<< "IDENTITY_PROBE|[stratum]|[public_class_label(value_for(stratum))]"',
     "identity semantic probe record")
for method in ("size", "length"):
    for op in ("map", "select", "reject", "count"):
        rel = f"spec/compiler/string_{method}_symbol_proc_{op}_no_use_spec.w"
        fixture = (branchless / rel).read_text()
        code = "\n".join(line for line in fixture.splitlines() if not line.lstrip().startswith("#"))
        once(code, 'ccall("w_strlen_one_string_array")', f"{op}(:{method}) unmapped native WArray fixture")
        once(code, f"got = values.{op}(:{method})", f"{op}(:{method}) generated-name seam")
        if f".{method}" in code or " = [" in code or "\nuse " in "\n" + code:
            raise SystemExit(f"{rel}: fixture leaks an explicit target call, array literal, or import")
for root in (base, direct, branchless):
    if "w_strlen_one_string_array" in (root / "compiler/lib/loader.w").read_text():
        raise SystemExit(f"{root.name}: benchmark-only WArray helper unexpectedly became a loader-known factory")

print("PASS static audit: matched roots; exact resolved-entry public identity with String/Symbol parity and stable nil/declared-Unknown results; exact IC removal/reindex; direct checked and canonical-helper branchless candidates; literal/generated autoload; rope-safe interpreter; full fixtures")
PY

if [ "$STATIC_ONLY" = 1 ]; then
  echo "STATIC_ONLY=1: no compiler build, native link, executable, or timing was started."
  exit 0
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-string-length-revisit.XXXXXX")"
cleanup() {
  if [ "$KEEP_TMP" = 1 ]; then
    echo "retained diagnostic directory: $TMP" >&2
  else
    rm -rf "$TMP"
  fi
}
trap cleanup EXIT
mkdir -p "$TMP/shared"

# Neutral copies are mandatory: baseline never compiles a source path rooted
# in either candidate worktree, preventing source-root/autoload contamination.
SHARED_SRC="$TMP/shared/string_length_revisit_public.w"
SHARED_REF="$TMP/shared/string_length_revisit_ref.c"
INTERPRETER_SRC="$TMP/shared/string_length_revisit_interpreter.w"
IDENTITY_SPEC="$TMP/shared/string_symbol_class_identity_spec.w"
cp "$SCRIPT_DIR/string_length_revisit_public.w" "$SHARED_SRC"
cp "$SCRIPT_DIR/string_length_revisit_ref.c" "$SHARED_REF"
cp "$BRANCHLESS_ROOT/spec/interpreter/string_length_revisit_spec.w" "$INTERPRETER_SRC"
cp "$BRANCHLESS_ROOT/spec/compiler/string_symbol_class_identity_spec.w" "$IDENTITY_SPEC"

AUTOLOAD_SPECS=(
  string_size_no_use_native_spec.w
  string_length_no_use_rope_spec.w
  symbol_size_no_use_native_spec.w
  symbol_length_no_use_native_spec.w
  string_size_symbol_proc_map_no_use_spec.w
  string_size_symbol_proc_select_no_use_spec.w
  string_size_symbol_proc_reject_no_use_spec.w
  string_size_symbol_proc_count_no_use_spec.w
  string_length_symbol_proc_map_no_use_spec.w
  string_length_symbol_proc_select_no_use_spec.w
  string_length_symbol_proc_reject_no_use_spec.w
  string_length_symbol_proc_count_no_use_spec.w
)
for name in "${AUTOLOAD_SPECS[@]}"; do
  cp "$BRANCHLESS_ROOT/spec/compiler/$name" "$TMP/shared/$name"
done
for name in string_length_loader_control.w string_length_loader_size_probe.w string_length_loader_length_probe.w; do
  cp "$SCRIPT_DIR/$name" "$TMP/shared/$name"
done

hash_file() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}';
  else sha256sum "$1" | awk '{print $1}'; fi
}

build_trial_compiler() {
  local label="$1" root="$2" output="$3"
  local source="$TMP/compiler-source-$label" built="$TMP/compiler-built-$label" log="$TMP/$label-compiler.log"
  mkdir -p "$source/languages"
  cp -R "$root/compiler" "$source/compiler"
  cp -R "$root/core" "$source/core"
  cp -R "$root/runtime" "$source/runtime"
  cp -R "$root/languages/tungsten" "$source/languages/tungsten"
  (
    cd "$source"
    TUNGSTEN_ROOT="$source" TUNGSTEN_CACHE_DIR="$TMP/cache-build-$label" \
      "$BOOTSTRAP_COMPILER" compile "$source/compiler/tungsten.w" \
      --release --no-lto --out "$built" >"$log" 2>&1
  ) || { echo "$label compiler bootstrap failed" >&2; sed -n '1,240p' "$log" >&2; return 1; }
  test -x "$built" || { echo "$label compiler bootstrap produced no executable" >&2; return 1; }
  cp "$built" "$output"
  test ! -f "$built.sidemap" || cp "$built.sidemap" "$output.sidemap"
  if [ "$(uname -s)" = Darwin ] && command -v codesign >/dev/null 2>&1; then
    codesign --force -s - "$output" >/dev/null 2>&1 || true
  fi
  echo "prepared $label trial compiler $(hash_file "$output")" >&2
}

if [ "$SKIP_COMPILER_BUILD" = 0 ]; then
  if [ -z "$BOOTSTRAP_COMPILER" ] || [ ! -x "$BOOTSTRAP_COMPILER" ]; then
    echo "set BOOTSTRAP_COMPILER to one executable used for all three fresh trial builds" >&2
    exit 2
  fi
  BOOTSTRAP_COMPILER="$(cd "$(dirname "$BOOTSTRAP_COMPILER")" && pwd)/$(basename "$BOOTSTRAP_COMPILER")"
  BASELINE_COMPILER="$TMP/baseline-compiler"
  DIRECT_COMPILER="$TMP/direct-compiler"
  BRANCHLESS_COMPILER="$TMP/branchless-compiler"
  echo "common bootstrap $(hash_file "$BOOTSTRAP_COMPILER")" >&2
  build_trial_compiler baseline "$BASELINE_ROOT" "$BASELINE_COMPILER"
  build_trial_compiler direct "$DIRECT_ROOT" "$DIRECT_COMPILER"
  build_trial_compiler branchless "$BRANCHLESS_ROOT" "$BRANCHLESS_COMPILER"
else
  for variable in BASELINE_COMPILER DIRECT_COMPILER BRANCHLESS_COMPILER; do
    if [ -z "${!variable}" ] || [ ! -x "${!variable}" ]; then
      echo "SKIP_COMPILER_BUILD=1 requires executable $variable" >&2
      exit 2
    fi
  done
fi

compile_workload() {
  local label="$1" root="$2" compiler="$3"
  local wire="$TMP/$label.wire" ll="$TMP/$label.ll" bin="$TMP/$label"
  (
    cd "$root"
    TUNGSTEN_ROOT="$root" TUNGSTEN_CACHE_DIR="$TMP/cache-work-$label" TUNGSTEN_C_INCLUDES="$SHARED_REF" \
      "$compiler" compile "$SHARED_SRC" --emit-wire >"$wire"
    TUNGSTEN_ROOT="$root" TUNGSTEN_CACHE_DIR="$TMP/cache-work-$label" TUNGSTEN_C_INCLUDES="$SHARED_REF" TUNGSTEN_LL_PATH="$ll" \
      "$compiler" compile "$SHARED_SRC" --release --out "$bin" >/dev/null
  )
  test -x "$bin" && test -s "$wire" && test -s "$ll" && test -s "$bin.sidemap" || {
    echo "$label workload did not produce binary/WIRE/LLVM/sidemap" >&2; exit 1;
  }
}

compile_workload baseline "$BASELINE_ROOT" "$BASELINE_COMPILER"
compile_workload direct "$DIRECT_ROOT" "$DIRECT_COMPILER"
compile_workload branchless "$BRANCHLESS_ROOT" "$BRANCHLESS_COMPILER"

# WIRE/LLVM audit: public calls must remain cached dispatch, while only the
# candidate modules contain source method bodies with their intended bridges.
python3 - "$TMP/baseline.wire" "$TMP/direct.wire" "$TMP/branchless.wire" \
  "$TMP/baseline.ll" "$TMP/baseline.sidemap" \
  "$TMP/direct.ll" "$TMP/direct.sidemap" "$TMP/branchless.ll" "$TMP/branchless.sidemap" <<'PY'
from pathlib import Path
import json, re, sys

bwire, dwire, fwire, bll, bmap, dll, dmap, fll, fmap = map(Path, sys.argv[1:])

def wire_bodies(path, name):
    lines = path.read_text().splitlines()
    out = []
    for i, line in enumerate(lines):
        if not line.startswith(f"function {name}("):
            continue
        body = []
        for following in lines[i + 1:]:
            if following.startswith("function ") or (not following.strip() and body): break
            if following.strip(): body.append(following.strip())
        out.append("\n".join(body))
    return out

for method in ("size", "length"):
    name = f"__w_String_{method}__a1"
    if wire_bodies(bwire, name):
        raise SystemExit(f"baseline unexpectedly contains source body {name}")
    db = wire_bodies(dwire, name)
    fb = wire_bodies(fwire, name)
    if len(db) != 1 or "w_string_byte_length" not in db[0] or "w_int" not in db[0]:
        raise SystemExit(f"direct WIRE {name} lacks canonical helper + checked box")
    if len(fb) != 1 or fb[0].count("w_string_byte_length") != 1:
        raise SystemExit(f"branchless WIRE {name} lacks its one canonical helper call")
    if fb[0].count("or_i64") != 1 or "ret_i64" not in fb[0]:
        raise SystemExit(f"branchless WIRE {name} lacks its direct tag-or return")
    for forbidden in ("@w_int", "cond_br", "icmp_i64", "and_i64"):
        if forbidden in fb[0]:
            raise SystemExit(f"branchless WIRE {name} still contains {forbidden}")

def symbols(map_path, original):
    data = json.loads(map_path.read_text())
    found = set()
    for entry in data.get("hashes", {}).values():
        if any(item.get("symbol") == original for item in entry.get("originals", [])):
            found.add(entry["symbol"])
    return found

def llvm_body(path, symbol):
    lines = path.read_text().splitlines()
    starts = [i for i, line in enumerate(lines) if re.match(rf"^define .* @{re.escape(symbol)}\(", line)]
    if len(starts) != 1: raise SystemExit(f"LLVM {symbol}: expected one definition, got {len(starts)}")
    body = []
    for line in lines[starts[0] + 1:]:
        if line.strip() == "}": break
        body.append(line)
    return body

timers = ("__w_time_string_size", "__w_time_string_length", "__w_time_symbol_size", "__w_time_symbol_length")
for ll, smap, label in ((bll,bmap,"baseline"),(dll,dmap,"direct"),(fll,fmap,"branchless")):
    for original in timers:
        syms = symbols(smap, original)
        if len(syms) != 1: raise SystemExit(f"{label} sidemap {original}: {syms}")
        body = llvm_body(ll, next(iter(syms)))
        if sum("@w_method_call_cached_0(" in line for line in body) != 1:
            raise SystemExit(f"{label} {original}: timed call is not one public cached-0 dispatch")
        if sum("@w_strlen_thread_cpu_ns(" in line for line in body) != 2:
            raise SystemExit(f"{label} {original}: expected two direct raw thread clocks")

print("PASS WIRE/LLVM: checked direct and branchless canonical-helper source bodies; one true public dispatch per timed loop")
PY

for label in baseline direct branchless; do
  "$TMP/$label" check >"$TMP/$label.check"
done
cmp "$TMP/baseline.check" "$TMP/direct.check"
cmp "$TMP/baseline.check" "$TMP/branchless.check"
cat "$TMP/branchless.check"

# Compile the identity regression from the same neutral path in every fixed
# root. This is deliberately separate from the old-vs-fixed timing control:
# semantic acceptance never treats the old, wrong Symbol.class result as a
# correctness oracle.
compile_identity_spec() {
  local label="$1" root="$2" compiler="$3"
  local wire="$TMP/$label-class-identity.wire" ll="$TMP/$label-class-identity.ll" bin="$TMP/$label-class-identity"
  (
    cd "$root"
    TUNGSTEN_ROOT="$root" TUNGSTEN_CACHE_DIR="$TMP/cache-class-identity-$label" TUNGSTEN_C_INCLUDES="$SHARED_REF" \
      "$compiler" compile "$IDENTITY_SPEC" --emit-wire >"$wire"
    TUNGSTEN_ROOT="$root" TUNGSTEN_CACHE_DIR="$TMP/cache-class-identity-$label" TUNGSTEN_C_INCLUDES="$SHARED_REF" TUNGSTEN_LL_PATH="$ll" \
      "$compiler" compile "$IDENTITY_SPEC" --release --out "$bin" >/dev/null
  )
  test -x "$bin" && test -s "$wire" && test -s "$ll" || {
    echo "$label class-identity regression did not produce binary/WIRE/LLVM" >&2; exit 1;
  }
  "$bin" >"$bin.out"
  "$bin" declared >"$bin.declared.out"
}
compile_identity_spec baseline "$BASELINE_ROOT" "$BASELINE_COMPILER"
compile_identity_spec direct "$DIRECT_ROOT" "$DIRECT_COMPILER"
compile_identity_spec branchless "$BRANCHLESS_ROOT" "$BRANCHLESS_COMPILER"
cmp "$TMP/baseline-class-identity.out" "$TMP/direct-class-identity.out"
cmp "$TMP/baseline-class-identity.out" "$TMP/branchless-class-identity.out"
cmp "$TMP/baseline-class-identity.declared.out" "$TMP/direct-class-identity.declared.out"
cmp "$TMP/baseline-class-identity.declared.out" "$TMP/branchless-class-identity.declared.out"
grep -Fx 'PASS public class identity all: __w_type-authoritative identity, alias invalidation, and late matching registration' \
  "$TMP/branchless-class-identity.out"
grep -Fx 'PASS public class identity declared: __w_type-authoritative identity, alias invalidation, and late matching registration' \
  "$TMP/branchless-class-identity.declared.out"
python3 - "$TMP/baseline-class-identity.wire" "$TMP/direct-class-identity.wire" \
  "$TMP/branchless-class-identity.wire" \
  "$TMP/baseline-class-identity.ll" "$TMP/direct-class-identity.ll" \
  "$TMP/branchless-class-identity.ll" <<'PY'
from pathlib import Path
import re, sys
paths = list(map(Path, sys.argv[1:]))
for path in paths[:3]:
    wire = path.read_text()
    if len(re.findall(r"^function __w_String_empty", wire, re.M)) != 1:
        raise SystemExit(f"{path.name}: identity regression did not force one source String registration target")
    if wire.count("type_class_register") != 1:
        raise SystemExit(f"{path.name}: expected only String's one generated type-class registration")
    if re.search(r"^function __w_Symbol_", wire, re.M):
        raise SystemExit(f"{path.name}: Symbol source class masked the shared-key regression")
    if wire.count("w_class_of") != 20 or wire.count("w_class_name") != 8:
        raise SystemExit(f"{path.name}: class/class_name calls were not lowered through the exact regression shape")
for path in paths[3:]:
    llvm = path.read_text()
    if llvm.count("call void @w_type_class_register_wv(i32 249,") != 1:
        raise SystemExit(f"{path.name}: expected exact String dispatch-key 249 registration")
print("PASS compiled identity: fixed trio preserves __w_type-authoritative identity through cold/warm aliases, late matching registration, and opaque facade dispatch")
PY

compile_autoload_specs() {
  local label="$1" root="$2" compiler="$3" spec name out wire
  for name in "${AUTOLOAD_SPECS[@]}"; do
    spec="$TMP/shared/$name"
    out="$TMP/$label-${name%.w}"
    wire="$out.wire"
    (
      cd "$root"
      TUNGSTEN_ROOT="$root" TUNGSTEN_CACHE_DIR="$TMP/cache-auto-$label-$name" TUNGSTEN_C_INCLUDES="$SHARED_REF" \
        "$compiler" compile "$spec" --emit-wire >"$wire"
      TUNGSTEN_ROOT="$root" TUNGSTEN_CACHE_DIR="$TMP/cache-auto-$label-$name" TUNGSTEN_C_INCLUDES="$SHARED_REF" \
        "$compiler" compile "$spec" --release --out "$out" >/dev/null
    )
    "$out" >"$out.out"
  done
}
compile_autoload_specs baseline "$BASELINE_ROOT" "$BASELINE_COMPILER"
compile_autoload_specs direct "$DIRECT_ROOT" "$DIRECT_COMPILER"
compile_autoload_specs branchless "$BRANCHLESS_ROOT" "$BRANCHLESS_COMPILER"
for name in "${AUTOLOAD_SPECS[@]}"; do
  stem="${name%.w}"
  cmp "$TMP/baseline-$stem.out" "$TMP/direct-$stem.out"
  cmp "$TMP/baseline-$stem.out" "$TMP/branchless-$stem.out"
  cat "$TMP/branchless-$stem.out"
done
python3 - "$TMP" "${AUTOLOAD_SPECS[@]}" <<'PY'
from pathlib import Path
import re, sys
tmp = Path(sys.argv[1])
for name in sys.argv[2:]:
    stem = name[:-2]
    counts = {}
    array_defs = {}
    for label in ("baseline", "direct", "branchless"):
        wire = (tmp / f"{label}-{stem}.wire").read_text()
        counts[label] = len(re.findall(r"^function __w_String_(?:size|length)__a1", wire, re.M))
        array_defs[label] = len(re.findall(r"^function __w_Array_", wire, re.M))
    if counts["baseline"] != 0 or counts["direct"] != 2 or counts["branchless"] != 2:
        raise SystemExit(f"{name}: wrong source String length definitions: {counts}")
    if "_symbol_proc_" in name and any(array_defs.values()):
        raise SystemExit(f"{name}: generated-name gate was masked by Array source autoload: {array_defs}")
print("PASS twelve no-use gates: four direct/native/rope/Symbol plus eight isolated map/select/reject/count(:size/:length) generated-name seams")
PY

# Quantify the conservative broad-name load in deliberately non-String user
# code. Output size/function count is deterministic and more useful here than
# noisy wall timing. The self-host itself has an explicit String anchor, so its
# marginal class-load delta is zero; these probes measure the worst tiny-file
# false positive before the one-shot flag turns off.
profile_loader_impact() {
  local label="$1" root="$2" compiler="$3" kind src wire bin wire_bytes fn_count bin_bytes string_defs
  for kind in control size length; do
    case "$kind" in
      control) src="$TMP/shared/string_length_loader_control.w" ;;
      size) src="$TMP/shared/string_length_loader_size_probe.w" ;;
      length) src="$TMP/shared/string_length_loader_length_probe.w" ;;
    esac
    wire="$TMP/load-$label-$kind.wire"
    bin="$TMP/load-$label-$kind"
    (
      cd "$root"
      TUNGSTEN_ROOT="$root" TUNGSTEN_CACHE_DIR="$TMP/cache-load-$label-$kind" \
        "$compiler" compile "$src" --emit-wire >"$wire"
      TUNGSTEN_ROOT="$root" TUNGSTEN_CACHE_DIR="$TMP/cache-load-$label-$kind" \
        "$compiler" compile "$src" --release --out "$bin" >/dev/null
    )
    "$bin"
    wire_bytes="$(wc -c <"$wire" | tr -d ' ')"
    fn_count="$(grep -c '^function ' "$wire" || true)"
    bin_bytes="$(wc -c <"$bin" | tr -d ' ')"
    string_defs="$(grep -Ec '^function __w_String_(size|length)__a1' "$wire" || true)"
    printf 'LOAD_IMPACT|%s|%s|wire=%s|functions=%s|binary=%s|string-length-defs=%s\n' \
      "$label" "$kind" "$wire_bytes" "$fn_count" "$bin_bytes" "$string_defs" | tee -a "$TMP/load-impact.txt"
  done
}
: >"$TMP/load-impact.txt"
profile_loader_impact baseline "$BASELINE_ROOT" "$BASELINE_COMPILER"
profile_loader_impact direct "$DIRECT_ROOT" "$DIRECT_COMPILER"
profile_loader_impact branchless "$BRANCHLESS_ROOT" "$BRANCHLESS_COMPILER"
python3 - "$TMP/load-impact.txt" <<'PY'
from pathlib import Path
import re, sys
rows = {}
for line in Path(sys.argv[1]).read_text().splitlines():
    parts = line.split("|")
    rows[(parts[1], parts[2])] = {k:int(v) for k,v in (field.split("=",1) for field in parts[3:])}
for label in ("baseline", "direct", "branchless"):
    if rows[(label,"control")]["string-length-defs"] != 0:
        raise SystemExit(f"{label}: control unexpectedly loaded String length source")
if rows[("baseline","size")]["string-length-defs"] or rows[("baseline","length")]["string-length-defs"]:
    raise SystemExit("baseline unexpectedly emitted source String length methods")
for label in ("direct", "branchless"):
    for kind in ("size", "length"):
        if rows[(label,kind)]["string-length-defs"] != 2:
            raise SystemExit(f"{label}/{kind}: broad one-shot gate did not load both shared methods")
    for kind in ("size", "length"):
        probe = rows[(label,kind)]
        control = rows[(label,"control")]
        base_probe = rows[("baseline",kind)]
        base_control = rows[("baseline","control")]
        wire_delta = (probe['wire']-control['wire']) - (base_probe['wire']-base_control['wire'])
        fn_delta = (probe['functions']-control['functions']) - (base_probe['functions']-base_control['functions'])
        bin_delta = (probe['binary']-control['binary']) - (base_probe['binary']-base_control['binary'])
        print(f"{label} {kind} conservative String-load net delta: wire {wire_delta:+d} B, "
              f"functions {fn_delta:+d}, binary {bin_delta:+d} B")
print("PASS loader impact: one sound false-positive class load is measured; self-host marginal load is zero because core/string_native is explicitly anchored")
PY

for tuple in "baseline|$BASELINE_ROOT|$BASELINE_COMPILER" "direct|$DIRECT_ROOT|$DIRECT_COMPILER" "branchless|$BRANCHLESS_ROOT|$BRANCHLESS_COMPILER"; do
  label="${tuple%%|*}"; rest="${tuple#*|}"; root="${rest%%|*}"; compiler="${rest#*|}"
  echo "running $label tree-walker parity" >&2
  if ! (
    cd "$root"
    TUNGSTEN_ROOT="$root" TUNGSTEN_CACHE_DIR="$TMP/cache-interpreter-$label" \
      "$compiler" run "$INTERPRETER_SRC"
  ) >"$TMP/$label.interpreter" 2>"$TMP/$label.interpreter.err"; then
    echo "$label tree-walker parity failed" >&2
    sed -n '1,240p' "$TMP/$label.interpreter.err" >&2
    sed -n '1,240p' "$TMP/$label.interpreter" >&2
    exit 1
  fi
done
cmp "$TMP/baseline.interpreter" "$TMP/direct.interpreter"
cmp "$TMP/baseline.interpreter" "$TMP/branchless.interpreter"
cat "$TMP/branchless.interpreter"

if [ "$CHECK_ONLY" = 1 ]; then
  echo "CHECK_ONLY=1: bootstrap, neutral-source compile, WIRE/LLVM, 17-case length semantics, resolved-entry public class identity, twelve no-use gates, and interpreter parity passed; timings skipped."
  exit 0
fi

all_strata=(
  string.size.inline string.size.slab string.size.heap string.size.rope-warm string.size.nul
  string.length.inline string.length.slab string.length.heap string.length.rope-warm string.length.nul
  symbol.size.inline symbol.size.slab symbol.size.heap symbol.size.nul
  symbol.length.inline symbol.length.slab symbol.length.heap symbol.length.nul
)
strata=()
for stratum in "${all_strata[@]}"; do
  method="${stratum%.*}"
  if [ -z "$ONLY" ] || [ "$method" = "$ONLY" ]; then strata+=("$stratum"); fi
done

campaign=first
test "$REPEAT" = 0 || campaign=repeat
OUT="${OUT:-${TMPDIR:-/tmp}/string-length-revisit-$campaign-$(date +%Y%m%d-%H%M%S).txt}"
: >"$OUT"
printf 'META|campaign|%s|head|%s|bootstrap|%s|baseline|%s|direct|%s|branchless|%s\n' \
  "$campaign" "$baseline_head" "$(hash_file "$BOOTSTRAP_COMPILER")" \
  "$(hash_file "$BASELINE_COMPILER")" "$(hash_file "$DIRECT_COMPILER")" "$(hash_file "$BRANCHLESS_COMPILER")" >>"$OUT"

measure() {
  local bin="$1" stratum="$2" sample ns checksum
  sample="$("$bin" bench "$stratum" "$ITERS" "$WARMUP")"
  ns="$(printf '%s\n' "$sample" | awk -F'|' -v s="$stratum" '$1=="RESULT" && $2==s {print $3}')"
  checksum="$(printf '%s\n' "$sample" | awk -F'|' -v s="$stratum" '$1=="RESULT" && $2==s {print $5}')"
  case "$ns" in ''|*[!0-9]*|0) echo "invalid duration for $stratum from $bin: $ns" >&2; return 1 ;; esac
  test -n "$checksum" || { echo "missing checksum for $stratum from $bin" >&2; return 1; }
  printf '%s|%s\n' "$ns" "$checksum"
}

run_six_leg() {
  local stratum="$1" parity="$2" order side result ns got checksum="" bsum=0 dsum=0 xsum=0
  if [ "$parity" -eq 0 ]; then order="B D X X D B"; else order="X D B B D X"; fi
  for side in $order; do
    case "$side" in
      B) result="$(measure "$TMP/baseline" "$stratum")" ;;
      D) result="$(measure "$TMP/direct" "$stratum")" ;;
      X) result="$(measure "$TMP/branchless" "$stratum")" ;;
    esac
    ns="${result%%|*}"; got="${result#*|}"
    if [ -n "$checksum" ] && [ "$got" != "$checksum" ]; then
      echo "checksum mismatch $stratum: $got != $checksum" >&2; exit 1
    fi
    checksum="$got"
    case "$side" in B) bsum=$((bsum+ns));; D) dsum=$((dsum+ns));; X) xsum=$((xsum+ns));; esac
  done
  dratio="$(awk -v c="$dsum" -v b="$bsum" 'BEGIN {printf "%.9f",c/b}')"
  xratio="$(awk -v c="$xsum" -v b="$bsum" 'BEGIN {printf "%.9f",c/b}')"
  printf 'PAIR|%s|%s|%s|%s|%s|%s|%s\n' "$stratum" "$bsum" "$dsum" "$xsum" "$dratio" "$xratio" "$checksum"
}

for ((sample=1; sample<=RUNS; sample++)); do
  parity=$(((sample-1)%2))
  echo "$campaign sample $sample/$RUNS parity=$parity" >&2
  for stratum in "${strata[@]}"; do run_six_leg "$stratum" "$parity" | tee -a "$OUT"; done
done

median_stream() {
  sort -n | awk '{v[NR]=$1} END {if(!NR)exit 1; if(NR%2)print v[(NR+1)/2]; else print (v[NR/2]+v[NR/2+1])/2}'
}

failed=0
printf '\n%-24s %11s %11s %11s %9s %9s\n' stratum native-ns direct-ns branchless-ns direct/C branchless/C
for stratum in "${strata[@]}"; do
  bmed="$(awk -F'|' -v s="$stratum" '$1=="PAIR"&&$2==s{print $3}' "$OUT" | median_stream)"
  dmed="$(awk -F'|' -v s="$stratum" '$1=="PAIR"&&$2==s{print $4}' "$OUT" | median_stream)"
  xmed="$(awk -F'|' -v s="$stratum" '$1=="PAIR"&&$2==s{print $5}' "$OUT" | median_stream)"
  dr="$(awk -F'|' -v s="$stratum" '$1=="PAIR"&&$2==s{print $6}' "$OUT" | median_stream)"
  xr="$(awk -F'|' -v s="$stratum" '$1=="PAIR"&&$2==s{print $7}' "$OUT" | median_stream)"
  bcall="$(awk -v n="$bmed" -v i="$ITERS" 'BEGIN{print n/(2*i)}')"
  dcall="$(awk -v n="$dmed" -v i="$ITERS" 'BEGIN{print n/(2*i)}')"
  xcall="$(awk -v n="$xmed" -v i="$ITERS" 'BEGIN{print n/(2*i)}')"
  printf '%-24s %11.4f %11.4f %11.4f %9.4f %9.4f\n' "$stratum" "$bcall" "$dcall" "$xcall" "$dr" "$xr"
  printf 'SUMMARY|%s|%s|%s\n' "$stratum" "$dr" "$xr" >>"$OUT"
done

methods=(string.size string.length symbol.size symbol.length)
for method in "${methods[@]}"; do
  if [ -n "$ONLY" ] && [ "$method" != "$ONLY" ]; then continue; fi
  dworst="$(awk -F'|' -v m="$method." '$1=="SUMMARY"&&index($2,m)==1{if($3>x)x=$3}END{print x+0}' "$OUT")"
  xworst="$(awk -F'|' -v m="$method." '$1=="SUMMARY"&&index($2,m)==1{if($4>x)x=$4}END{print x+0}' "$OUT")"
  ddecision="$(awk -v r="$dworst" -v g="$GATE" 'BEGIN{print (r <= g ? "RETAIN" : "SKIP")}')"
  xdecision="$(awk -v r="$xworst" -v g="$GATE" 'BEGIN{print (r <= g ? "RETAIN" : "SKIP")}')"
  echo "$method direct=$ddecision worst=$dworst branchless=$xdecision worst=$xworst"
  if [ "$ddecision" = SKIP ] && [ "$xdecision" = SKIP ]; then failed=1; fi
done

echo "raw results: $OUT"
echo "Each sample is B/D/X/X/D/B or X/D/B/B/D/X using thread CPU time; every method/variant is gated independently at <= $GATE."
echo "Run REPEAT=1 for a second independently rebuilt campaign before retaining either candidate."
if [ "$failed" -ne 0 ]; then exit 3; fi
