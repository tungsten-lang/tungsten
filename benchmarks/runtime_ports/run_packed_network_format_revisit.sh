#!/usr/bin/env bash
# Relaxed true-public IC-vs-source gate for IPv4/IPv6/MAC to_s.
#
# STATIC_ONLY=1 is the default and performs no build, link, generated-program,
# or timing work.  STATIC_ONLY=0 CHECK_ONLY=1 runs one fully rebuilt semantic,
# WIRE, LLVM, autoload, interpreter, and block-surface campaign.  Timed mode
# rebuilds independently for two campaigns and retains a method only if every
# relevant input stratum has median source/native <= 1.10 in both campaigns.
# The three inspect rows deliberately remain native: removing them is not
# sound for values crossing an untyped native-return boundary.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CANDIDATE_ROOT="${CANDIDATE_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
BASELINE_ROOT="${BASELINE_ROOT:-/tmp/tungsten-packed-network-format-baseline}"
BOOTSTRAP_COMPILER="${BOOTSTRAP_COMPILER:-/Users/erik/tungsten/bin/tungsten-compiler}"
STATIC_ONLY="${STATIC_ONLY:-1}"
CHECK_ONLY="${CHECK_ONLY:-1}"
RUNS="${RUNS:-10}"
ITERS="${ITERS:-2000000}"
WARMUP="${WARMUP:-100000}"
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

DRIVER_REL="benchmarks/runtime_ports/packed_network_format_public.w"
REF_REL="benchmarks/runtime_ports/packed_network_format_ref.c"
AUTO_REL="benchmarks/runtime_ports/packed_network_format_autoload.w"
INTERP_REL="benchmarks/runtime_ports/packed_network_format_interpreter.w"

echo "Auditing isolated production delta and dormant benchmark protocol..."
python3 - "$BASELINE_ROOT" "$CANDIDATE_ROOT" "$DRIVER_REL" "$REF_REL" "$AUTO_REL" "$INTERP_REL" <<'PY'
from pathlib import Path
import re
import sys

base, cand = map(Path, sys.argv[1:3])
driver_rel, ref_rel, auto_rel, interp_rel = sys.argv[3:7]

def regular_files(root, top):
    out = {}
    for path in (root / top).rglob("*"):
        if path.is_file() and not path.is_symlink():
            out[path.relative_to(root).as_posix()] = path.read_bytes()
    return out

# The baseline is a snapshot of the current integrated compiler/core/runtime,
# not pristine HEAD.  Compare roots directly so every unrelated retained port
# is byte-identical and the measured production delta is exactly runtime.c.
bd = {}
cd = {}
for top in ("compiler", "core", "runtime"):
    bd.update(regular_files(base, top))
    cd.update(regular_files(cand, top))
if set(bd) != set(cd):
    raise SystemExit(f"production file-set mismatch: baseline-only={sorted(set(bd)-set(cd))}, candidate-only={sorted(set(cd)-set(bd))}")
different = sorted(path for path in bd if bd[path] != cd[path])
expected_different = ["runtime/runtime.c"]
if different != expected_different:
    raise SystemExit(f"candidate production delta is not the exact one-file shape: {different}")

for rel, cname in (("core/ipv4.w", "IPv4"), ("core/ipv6.w", "IPv6"), ("core/mac.w", "MAC")):
    btext = (base / rel).read_text()
    ctext = (cand / rel).read_text()
    if btext.count('  -> to_s\n    ccall("w_to_s", self)') != 1:
        raise SystemExit(f"{cname} baseline lacks its dormant direct to_s source wrapper")
    if ctext.count('  -> to_s\n    ccall("w_to_s", self)') != 1:
        raise SystemExit(f"{cname} candidate lacks its direct to_s source wrapper")
    if btext != ctext:
        raise SystemExit(f"{cname} source changed even though only its dormant to_s body is being exposed")
    if ctext.count('  -> inspect') != 1 or ctext.count('    ccall("w_to_s", self)') != 1:
        raise SystemExit(f"{cname} candidate source formatter shape changed")
    inspect = re.search(r"^  -> inspect\n(?P<body>.*?)(?=^  ->|\Z)", ctext, re.M | re.S)
    if not inspect or not re.search(r"^    self\.to_s\s*$", inspect.group("body"), re.M):
        raise SystemExit(f"{cname} dormant inspect source body changed; its native row must remain authoritative")

brt = (base / "runtime/runtime.c").read_text()
crt = (cand / "runtime/runtime.c").read_text()
for label, text in (("baseline", brt), ("candidate", crt)):
    if len(re.findall(r"^static WValue w_ic_value_to_s\(", text, re.M)) != 1:
        raise SystemExit(f"{label} must contain exactly one shared network inspect handler")

def table_rows(text, table):
    m = re.search(rf"static WICEntry {table}\[\] = \{{(?P<body>.*?)^\}};", text, re.M | re.S)
    if not m:
        return None
    return re.findall(r"\{0, ([A-Za-z0-9_]+|NULL)\}", m.group("body"))

for table in ("w_ic_ipv4_table", "w_ic_ipv6_table", "w_ic_mac_table"):
    if table_rows(brt, table) != ["w_ic_value_to_s", "w_ic_value_to_s", "NULL"]:
        raise SystemExit(f"baseline {table} is not exactly to_s, inspect, sentinel")
    if table_rows(crt, table) != ["w_ic_value_to_s", "NULL"]:
        raise SystemExit(f"candidate {table} must retain exactly inspect plus sentinel")

for key in ("0xE5", "0x85", "0x86"):
    pattern = rf"case {key}: table = w_ic_(?:ipv4|ipv6|mac)_table;"
    if not re.search(pattern, brt):
        raise SystemExit(f"baseline resolver lacks network table key {key}")
    if not re.search(pattern, crt):
        raise SystemExit(f"candidate resolver lost inspect table key {key}")
for klass in ("ipv4", "ipv6", "mac"):
    if len(re.findall(rf"w_ic_{klass}_table\[[01]\]\.name", brt)) != 2:
        raise SystemExit(f"baseline {klass} name initialization is not exactly two rows")
    assignments = re.findall(rf"w_ic_{klass}_table\[(\d+)\]\.name = ([A-Za-z0-9_()\"]+);", crt)
    if assignments != [("0", 'w_string("inspect")')]:
        raise SystemExit(f"candidate {klass} must initialize only row zero as inspect: {assignments}")

# The migration must be mechanically limited to deleting to_s from each
# two-row table and shifting inspect to slot zero. Universal `to_s` fallback
# remains separately available for an otherwise-untyped receiver.
if 'if (name == WN_to_s) return w_to_s(recv);' not in crt:
    raise SystemExit("candidate lost universal runtime to_s fallback")
if len(re.findall(r"\{0, w_ic_value_to_s\},\s*/\* inspect \*/", crt)) != 3:
    raise SystemExit("candidate does not retain exactly three native inspect rows")

# Pin the already-retained network state copied into both roots.  This revisit
# must not accidentally resurrect or absorb IPv4#octets.
for root in (base, cand):
    ipv4 = (root / "core/ipv4.w").read_text()
    runtime = (root / "runtime/runtime.c").read_text()
    if ipv4.count("  -> octets\n") != 1 or "w_ic_ipv4_octets" in runtime:
        raise SystemExit(f"{root}: retained IPv4#octets state is not intact")

loader = (cand / "compiler/lib/loader.w").read_text()
for snippet in (
    'if t == :ip4 || t == :cidr4',
    'consider_autoload_name("IPv4"',
    'if t == :ip6 || t == :cidr6',
    'consider_autoload_name("IPv6"',
    'if name in ("w_mac" "w_mac_parse")',
    'return "MAC"',
    'if name in ("w_ipv4" "w_ipv4_parse" "w_ipv4_from_octets")',
    'if name in ("w_ipv6" "w_ipv6_from_string" "w_ipv6_parse" "w_ipv6_storage_clone" "w_ipv6_storage_from_words")',
):
    if snippet not in loader:
        raise SystemExit(f"supported network autoload route missing: {snippet}")
if re.search(r'if call_name == "inspect".*consider_autoload_name\("(?:IPv4|IPv6|MAC)"', loader, re.S):
    raise SystemExit("candidate added a broad inspect-name gate that would bloat unrelated programs")

interp = (cand / "compiler/lib/interpreter.w").read_text()
for snippet in (
    'when "w_to_s"',
    'return ccall("w_to_s", value)',
    'when "w_ipv4_parse"',
    'when "w_ipv6_parse"',
    'when "w_mac_parse"',
    'if cname in ("IPv6" "MAC")',
):
    if snippet not in interp:
        raise SystemExit(f"interpreter network/source bridge missing: {snippet}")

driver = (cand / driver_rel).read_text()
if re.search(r"^use core/", driver, re.M):
    raise SystemExit("public driver must exercise autoload and contain no core use")
if driver.count('ccall("w_pnf_thread_cpu_ns")') != 6:
    raise SystemExit("three timing bodies must each take two direct thread-CPU timestamps")
for method in ("time_ipv4_to_s", "time_ipv6_to_s", "time_mac_to_s"):
    if driver.count(f"-> {method}(values, expected, iters, run_id)") != 1:
        raise SystemExit(f"non-memoizable timing body missing: {method}")
if re.search(r"-> time_.*inspect|-> block_.*inspect", driver):
    raise SystemExit("inspect accidentally entered the migrated timing/block surface")
for probe in ("block_ipv4_to_s", "block_ipv6_to_s", "block_mac_to_s"):
    if driver.count(f"-> {probe}") != 1:
        raise SystemExit(f"native block-surface probe missing: {probe}")
if "prefix <= 32" not in driver or "prefix <= 128" not in driver:
    raise SystemExit("correctness fixture does not exhaust both CIDR prefix domains")
if driver.count("receiver bits stable") < 3 or driver.count("receiver fields stable") < 3:
    raise SystemExit("receiver representation stability checks are incomplete")

autoload = (cand / auto_rel).read_text()
if re.search(r"^use core/", autoload, re.M):
    raise SystemExit("autoload probe must contain no core use")
for snippet in ("198.51.100.7", "2001:db8::1", 'ccall("w_ipv4_parse"', 'ccall("w_ipv6_parse"', 'ccall("w_mac_parse"'):
    if snippet not in autoload:
        raise SystemExit(f"autoload probe route missing: {snippet}")

interpreter = (cand / interp_rel).read_text()
if re.search(r"^use core/", interpreter, re.M):
    raise SystemExit("interpreter probe must contain no core use")
if interpreter.count("block ignored") != 3 or interpreter.count("hits += 1") != 3:
    raise SystemExit("interpreter must pin ignored-block behavior for all three to_s wrappers")

ref = (cand / ref_rel).read_text()
for assertion in (
    "offsetof(WNetAddr, type) == 0", "offsetof(WNetAddr, len) == 1",
    "offsetof(WNetAddr, prefix) == 2", "offsetof(WNetAddr, bytes) == 4",
    "sizeof(WNetAddr) == 32",
):
    if assertion not in ref:
        raise SystemExit(f"network ABI assertion missing: {assertion}")
if ref.count("clock_gettime(CLOCK_THREAD_CPUTIME_ID, &ts)") != 1:
    raise SystemExit("fixture must use exactly one thread-CPU clock primitive")
if "reference formatter" not in ref or "w_pnf_network_fingerprint" not in ref or "w_pnf_string_signature" not in ref:
    raise SystemExit("fixture separation/fingerprint audit text missing")

print("static audit: ok (three to_s IC rows removed, three inspect rows retained, source files unchanged, current IPv4#octets preserved, supported autoload/interpreter routes, exhaustive prefixes, ABI/stability/block/timing protocol)")
PY

all_strata=(
  ipv4.to_s.plain ipv4.to_s.cidr
  ipv6.to_s.plain ipv6.to_s.cidr
  mac.to_s
)
strata=("${all_strata[@]}")
if [ -n "$ONLY" ]; then
  found=0
  for stratum in "${all_strata[@]}"; do
    if [ "$stratum" = "$ONLY" ]; then found=1; fi
  done
  if [ "$found" -ne 1 ]; then
    echo "ONLY must name one complete packed-network formatter stratum" >&2
    exit 2
  fi
  strata=("$ONLY")
fi

if [ "$STATIC_ONLY" = 1 ]; then
  echo "STATIC_ONLY=1: no compiler, linker, generated program, or timing process was started."
  exit 0
fi
if [ ! -x "$BOOTSTRAP_COMPILER" ]; then
  echo "BOOTSTRAP_COMPILER must be one executable used for both roots" >&2
  exit 2
fi
BOOTSTRAP_COMPILER="$(cd "$(dirname "$BOOTSTRAP_COMPILER")" && pwd)/$(basename "$BOOTSTRAP_COMPILER")"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/tungsten-packed-network-format.XXXXXX")"
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
  local campaign="$1" base_compiler="$2" cand_compiler="$3"
  local dir="$TMP/campaign-$campaign"
  mkdir -p "$dir"
  (
    cd "$BASELINE_ROOT"
    TUNGSTEN_ROOT="$BASELINE_ROOT" TUNGSTEN_CACHE_DIR="$dir/base-wire-cache" \
    TUNGSTEN_C_INCLUDES="$TMP/shared/ref.c" \
      "$base_compiler" compile "$TMP/shared/public.w" --emit-wire > "$dir/base.wire"
    TUNGSTEN_ROOT="$BASELINE_ROOT" TUNGSTEN_CACHE_DIR="$dir/base-build-cache" \
    TUNGSTEN_C_INCLUDES="$TMP/shared/ref.c" TUNGSTEN_LL_PATH="$dir/base.ll" \
      "$base_compiler" compile "$TMP/shared/public.w" --release --lto --out "$dir/base" >/dev/null
  )
  (
    cd "$CANDIDATE_ROOT"
    TUNGSTEN_ROOT="$CANDIDATE_ROOT" TUNGSTEN_CACHE_DIR="$dir/cand-wire-cache" \
    TUNGSTEN_C_INCLUDES="$TMP/shared/ref.c" \
      "$cand_compiler" compile "$TMP/shared/public.w" --emit-wire > "$dir/cand.wire"
    TUNGSTEN_ROOT="$CANDIDATE_ROOT" TUNGSTEN_CACHE_DIR="$dir/cand-build-cache" \
    TUNGSTEN_C_INCLUDES="$TMP/shared/ref.c" TUNGSTEN_LL_PATH="$dir/cand.ll" \
      "$cand_compiler" compile "$TMP/shared/public.w" --release --lto --out "$dir/cand" >/dev/null
    TUNGSTEN_ROOT="$CANDIDATE_ROOT" TUNGSTEN_CACHE_DIR="$dir/auto-wire-cache" \
      "$cand_compiler" compile "$TMP/shared/autoload.w" --emit-wire > "$dir/autoload.wire"
    TUNGSTEN_ROOT="$CANDIDATE_ROOT" TUNGSTEN_CACHE_DIR="$dir/auto-build-cache" \
      "$cand_compiler" compile "$TMP/shared/autoload.w" --release --lto --out "$dir/autoload" >/dev/null
  )
  for artifact in "$dir/base" "$dir/cand" "$dir/autoload"; do test -x "$artifact"; done
  for artifact in "$dir/base.wire" "$dir/cand.wire" "$dir/autoload.wire" \
                  "$dir/base.ll" "$dir/cand.ll" "$dir/base.sidemap" "$dir/cand.sidemap"; do
    test -s "$artifact"
  done
}

verify_llvm() {
  local ll="$1" sidemap="$2"
  python3 - "$ll" "$sidemap" <<'PY'
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
    m = re.search(rf"^define [^\n]* @{re.escape(symbol)}\([^\n]*\)[^\n]*\{{\n.*?^}}$", ll, re.M | re.S)
    if not m:
        raise SystemExit(f"missing LLVM definition for {symbol}")
    return m.group(0)

originals = [f"__w_{cls}_to_s__a1" for cls in ("IPv4", "IPv6", "MAC")]
for original in originals:
    syms = symbols(original)
    if len(syms) != 1:
        raise SystemExit(f"{original}: expected one content-hash symbol, got {syms}")
    text = body(next(iter(syms)))
    if not re.search(r"call i64 @w_to_s\(i64 %__self\)", text):
        raise SystemExit(f"{original}: LLVM is not a direct w_to_s wrapper")
    if re.search(r"@w_(?:method_call|cached_call)", text):
        raise SystemExit(f"{original}: LLVM retained a secondary method dispatch")
print("LLVM: ok (all three source to_s wrappers are one direct canonical formatter call)")
PY
}

verify_block_surfaces() {
  local dir="$1"
  local methods=(ipv4.to_s ipv6.to_s mac.to_s)
  for method in "${methods[@]}"; do
    set +e
    "$dir/base" block "$method" >"$dir/base.block.$method" 2>&1
    base_status=$?
    "$dir/cand" block "$method" >"$dir/cand.block.$method" 2>&1
    cand_status=$?
    set -e
    if [ "$base_status" -ne "$cand_status" ]; then
      echo "block surface status mismatch for $method: baseline=$base_status candidate=$cand_status" >&2
      exit 1
    fi
    if [ "$base_status" -eq 0 ]; then
      cmp "$dir/base.block.$method" "$dir/cand.block.$method"
    else
      if ! grep -F "undefined method 'each'" "$dir/base.block.$method" >/dev/null || \
         ! grep -F "undefined method 'each'" "$dir/cand.block.$method" >/dev/null; then
        echo "unexpected trailing-block failure for $method" >&2
        sed -n '1,12p' "$dir/base.block.$method" >&2
        sed -n '1,12p' "$dir/cand.block.$method" >&2
        exit 1
      fi
    fi
  done
  echo "PASS native trailing-block surface parity for all three network to_s methods"
}

verify_campaign() {
  local campaign="$1" cand_compiler="$2"
  local dir="$TMP/campaign-$campaign"

  for cls in IPv4 IPv6 MAC; do
    fn="__w_${cls}_to_s__a1"
    require_wire "$dir/cand.wire" "$fn" 'call_direct_i64.*w_to_s'
    reject_wire "$dir/cand.wire" "$fn" 'call_method_i64|call_cached'
    require_wire "$dir/autoload.wire" "$fn" 'call_direct_i64.*w_to_s'
  done
  for fn in __w_time_ipv4_to_s __w_time_ipv6_to_s __w_time_mac_to_s; do
    require_wire "$dir/base.wire" "$fn" 'call_method_i64'
    require_wire "$dir/cand.wire" "$fn" 'call_method_i64'
    if ! diff -u <(wire_body "$dir/base.wire" "$fn") <(wire_body "$dir/cand.wire" "$fn") >/dev/null; then
      echo "hot caller WIRE differs across matched roots: $fn" >&2
      diff -u <(wire_body "$dir/base.wire" "$fn") <(wire_body "$dir/cand.wire" "$fn") >&2 || true
      exit 1
    fi
  done
  verify_llvm "$dir/cand.ll" "$dir/cand.sidemap"

  "$dir/base" check >"$dir/base.check"
  "$dir/cand" check >"$dir/cand.check"
  cmp "$dir/base.check" "$dir/cand.check"
  cat "$dir/cand.check"
  "$dir/autoload" >"$dir/autoload.check"
  cat "$dir/autoload.check"
  verify_block_surfaces "$dir"

  (
    cd "$CANDIDATE_ROOT"
    TUNGSTEN_ROOT="$CANDIDATE_ROOT" TUNGSTEN_CACHE_DIR="$dir/interpreter-cache" \
      "$cand_compiler" run "$TMP/shared/interpreter.w"
  ) >"$dir/interpreter.check"
  cat "$dir/interpreter.check"
}

prepare_campaign() {
  local campaign="$1"
  local dir="$TMP/campaign-$campaign"
  mkdir -p "$dir"
  build_trial_compiler "$campaign" baseline "$BASELINE_ROOT" "$dir/base-compiler"
  build_trial_compiler "$campaign" candidate "$CANDIDATE_ROOT" "$dir/cand-compiler"
  compile_campaign "$campaign" "$dir/base-compiler" "$dir/cand-compiler"
  verify_campaign "$campaign" "$dir/cand-compiler"
}

if [ "$CHECK_ONLY" = 1 ]; then
  prepare_campaign check
  echo "CHECK_ONLY=1: matched-root build, exact behavior, WIRE/LLVM, no-import autoload, interpreter, and to_s block-surface gates passed; inspect remained native; no timing samples taken."
  exit 0
fi

RAW="$TMP/pairs.tsv"
: > "$RAW"

run_leg() {
  local bin="$1" stratum="$2" label="$3"
  local output line elapsed checksum
  output="$("$bin" bench "$stratum" "$ITERS" "$WARMUP")"
  line="$(printf '%s\n' "$output" | awk -F'|' -v want="$stratum" '$1 == "RESULT" && $2 == want { line=$0 } END { print line }')"
  if [ -z "$line" ]; then
    echo "$label produced no RESULT for $stratum" >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi
  elapsed="$(printf '%s\n' "$line" | awk -F'|' '{print $3}')"
  checksum="$(printf '%s\n' "$line" | awk -F'|' '{print $4}')"
  case "$elapsed" in ''|*[!0-9]*) echo "$label invalid elapsed: $elapsed" >&2; exit 1 ;; esac
  if [ "$checksum" != "$ITERS" ]; then
    echo "$label checksum mismatch for $stratum: got $checksum expected $ITERS" >&2
    exit 1
  fi
  printf '%s %s\n' "$elapsed" "$checksum"
}

for campaign in 1 2; do
  prepare_campaign "$campaign"
  dir="$TMP/campaign-$campaign"
  for stratum in "${strata[@]}"; do
    obs=1
    while [ "$obs" -le "$RUNS" ]; do
      echo "campaign $campaign $stratum observation $obs/$RUNS" >&2
      if [ $((obs % 2)) -eq 1 ]; then
        read -r b1 _ < <(run_leg "$dir/base" "$stratum" "campaign $campaign baseline A")
        read -r c1 _ < <(run_leg "$dir/cand" "$stratum" "campaign $campaign candidate A")
        read -r c2 _ < <(run_leg "$dir/cand" "$stratum" "campaign $campaign candidate B")
        read -r b2 _ < <(run_leg "$dir/base" "$stratum" "campaign $campaign baseline B")
      else
        read -r c1 _ < <(run_leg "$dir/cand" "$stratum" "campaign $campaign candidate A")
        read -r b1 _ < <(run_leg "$dir/base" "$stratum" "campaign $campaign baseline A")
        read -r b2 _ < <(run_leg "$dir/base" "$stratum" "campaign $campaign baseline B")
        read -r c2 _ < <(run_leg "$dir/cand" "$stratum" "campaign $campaign candidate B")
      fi
      base_avg=$(( (b1 + b2) / 2 ))
      cand_avg=$(( (c1 + c2) / 2 ))
      ratio="$(awk -v c="$cand_avg" -v b="$base_avg" 'BEGIN { printf "%.9f", c / b }')"
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$campaign" "$stratum" "$obs" "$base_avg" "$cand_avg" "$ratio" >> "$RAW"
      obs=$((obs + 1))
    done
  done
done

python3 - "$RAW" "$GATE" "$ONLY" <<'PY'
from collections import defaultdict
from pathlib import Path
from statistics import median
import sys

path = Path(sys.argv[1])
gate = float(sys.argv[2])
only = sys.argv[3]
rows = defaultdict(list)
for line in path.read_text().splitlines():
    campaign, stratum, obs, base, cand, ratio = line.split("\t")
    rows[(int(campaign), stratum)].append((int(obs), int(base), int(cand), float(ratio)))

failed = []
method_status = defaultdict(lambda: True)
print("campaign  stratum                    native ns    source ns     median    max-pair")
print("--------  -------------------------  -----------  -----------  ---------  ---------")
for key in sorted(rows):
    campaign, stratum = key
    samples = rows[key]
    native = median(x[1] for x in samples)
    source = median(x[2] for x in samples)
    ratios = [x[3] for x in samples]
    ratio = median(ratios)
    max_pair = max(ratios)
    print(f"{campaign:8d}  {stratum:25s}  {native:11.1f}  {source:11.1f}  {ratio:9.3f}  {max_pair:9.3f}")
    method = stratum
    if method.endswith(".plain") or method.endswith(".cidr"):
        method = method.rsplit(".", 1)[0]
    if ratio > gate:
        failed.append((campaign, stratum, ratio))
        method_status[method] = False
    else:
        method_status[method] = method_status[method] and True

if only:
    if failed:
        raise SystemExit(f"diagnostic stratum exceeds {gate:.2f}: {failed}")
    print(f"ONLY={only}: diagnostic stratum passes both independent campaigns; run the full matrix before retaining its method")
    raise SystemExit(0)

print()
for method in sorted(method_status):
    print(f"{method}: {'RETAIN source wrapper' if method_status[method] else 'KEEP native IC'}")
if failed:
    raise SystemExit(f"relaxed gate failures (> {gate:.2f} median): {failed}")
print(f"PASS: every packed-network to_s stratum is <= {gate:.2f} in both independently rebuilt campaigns")
PY
