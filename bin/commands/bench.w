#!/usr/bin/env bash
exec "$(dirname "$0")/../tungsten" run "$0" "$@"
# ---------------------------------------------------------------------------
# `tungsten bench` — Tungsten primitive-operation velocity baseline.
#
# Measures the raw throughput of the language's PRIMITIVE operations — integer
# and float arithmetic, allocation, collection access, string building, and
# dispatch — as ops/sec. The point is a stable, machine-diffable regression
# baseline: run it before and after a compiler change and compare the numbers.
#
# Each primitive is a self-contained program in benchmarks/primitives/<name>.w
# that runs a fixed op count in a DATA-DEPENDENT loop (so SCEV / dead-code
# elimination can't collapse it), then prints three lines:
#     <checksum>            (line 1 — keeps the work observable)
#     ops: <n>              (the primitive-op count it performed)
#     elapsed: <seconds>s   (inner-loop wall time, excludes process start-up)
# The harness turns that into ops/sec = ops / elapsed, best-of-N.
#
# Usage:
#   tungsten bench                     # full primitive baseline, pretty table
#   tungsten bench int_add new_array   # only named primitives
#   tungsten bench --baseline          # machine-readable `name<TAB>ops` (diffable)
#   tungsten bench --compare           # also time C/Rust/... peers where a fair
#                                      #   equivalent exists, and show the ratio
#   tungsten bench --runs 5            # best-of-N timing (default 3)
#   tungsten bench --list              # list primitives and exit
#
# The cross-language ALGORITHM suite moved to `tungsten bench --suite ...`
# (bin/commands/bench-suite.w).
# ---------------------------------------------------------------------------

root = capture("cd \"[__DIR__]/../..\" && pwd").strip
primdir = root + "/benchmarks/primitives"
tungsten = root + "/bin/tungsten"

# ---- palette --------------------------------------------------------------
# Tungsten's brand colors (from tungsten-lang.org): amber-orange #E8A020 and a
# dark gray. 256-color approximations: orange 214, dark gray 245 (matches the
# brand #8A8A96). No bright cyan.
BOLD   = "\e[1m"
DIM    = "\e[2m"
RESET  = "\e[0m"
GOLD   = "\e[38;5;220m"
GREEN  = "\e[38;5;47m"
REDC   = "\e[38;5;203m"
GREY   = "\e[38;5;245m"
WHITE  = "\e[38;5;255m"
ORANGE = "\e[38;5;214m"
DARKB  = "\e[1m\e[38;5;245m"
WCOL   = "\e[38;5;214m"

# ---- catalogue ------------------------------------------------------------
# Ordered list of primitives grouped by category. Op counts are NOT stored
# here — each program reports its own `ops:` line, so retuning a program never
# desyncs the harness. `cat` groups the display; `desc` documents the metric;
# `peer` marks primitives that have a fair single-op peer equivalent for
# --compare.
prims = ["int_add", "int_mul", "int_bitops", "float_mul", "new_array", "new_string", "str_concat", "new_object", "new_hash", "array_get", "array_get_heap", "array_mod", "array_set", "array_set_heap", "hash_get", "str_build", "fn_call", "method_call", "block_call"]

cat = {}
desc = {}
peer = {}

cat["int_add"] = "arithmetic";   desc["int_add"] = "i64 add throughput (data-dependent accumulate)"
cat["int_mul"] = "arithmetic";   desc["int_mul"] = "i64 multiply throughput (wrapping LCG)"
cat["int_bitops"] = "arithmetic"; desc["int_bitops"] = "i64 shift/xor throughput (xorshift mix)"
cat["float_mul"] = "arithmetic"; desc["float_mul"] = "f64 multiply throughput (logistic map)"
cat["new_array"] = "allocation"; desc["new_array"] = "array-literal alloc + free churn"
cat["new_string"] = "allocation"; desc["new_string"] = "int-to-string allocation"
cat["str_concat"] = "allocation"; desc["str_concat"] = "string concatenation (+ alloc)"
cat["new_object"] = "allocation"; desc["new_object"] = "user-object instantiation"
cat["new_hash"] = "allocation";  desc["new_hash"] = "hash alloc + one insert churn"
cat["array_get"] = "collection"; desc["array_get"] = "STACK array read (headerless SmallArray)"
cat["array_get_heap"] = "collection"; desc["array_get_heap"] = "HEAP array read (WArray, 24B header)"
cat["array_mod"] = "collection"; desc["array_mod"] = "wraparound read tab\[i & 1023\] (novec loop)"
cat["array_set"] = "collection"; desc["array_set"] = "STACK array write (headerless SmallArray)"
cat["array_set_heap"] = "collection"; desc["array_set_heap"] = "HEAP array write (WArray, 24B header)"
cat["hash_get"] = "collection";  desc["hash_get"] = "hash lookup by string key"
cat["str_build"] = "string";     desc["str_build"] = "StringBuffer append throughput (chars/s)"
cat["fn_call"] = "dispatch";     desc["fn_call"] = "static function call (may inline)"
cat["method_call"] = "dispatch"; desc["method_call"] = "method dispatch via inline cache"
cat["block_call"] = "dispatch";  desc["block_call"] = "closure invocation (.call)"

# unit label per category (what one op is)
unit = {}
unit["arithmetic"] = "ops"
unit["allocation"] = "allocs"
unit["collection"] = "ops"
unit["string"] = "chars"
unit["dispatch"] = "calls"

cats = ["arithmetic", "allocation", "collection", "string", "dispatch"]

# --compare peers: name -> {lang -> source-basename}. Only fair single-op
# equivalents. Sources live in benchmarks/primitives/peers/<name>.<ext>.
# (Absent files are silently skipped, so this degrades gracefully.)
peer["int_add"] = true
peer["int_mul"] = true
peer["int_bitops"] = true
peer["float_mul"] = true
peer["array_get"] = true
peer["array_mod"] = true
peer["array_set"] = true

# ---- regression thresholds (min ops/sec) ----------------------------------
# A primitive with a defined floor is measured best-of-N (see THRESH_RUNS, to
# reach steady-state peak) and flagged RED when it falls below. `tungsten bench
# --gate` turns a breach into a non-zero exit (for CI); a plain run only warns.
# Floors are tuned for the reference machine (Apple M5 Max) — retune per host.
# array_get: the headerless-SmallArray sequential read fully NEON-vectorizes on
# LLVM-22 and PEAKS at ~15.8B ops/s here (best-of-9), edging out clang/rustc.
# The floor is 12B — well under the peak so CPU-frequency/load variance never
# trips it, but a codegen regression (lost vectorization, align/headerless
# breakage) more than halves the rate to ~4-8B and is caught immediately. A
# literal ~15B floor would flap: 15B IS the peak, so any load dips below it.
# array_mod: the wraparound read `tab[i & 1023]` relies on lowering's
# masked-index loop detection stamping `llvm.loop.vectorize.enable=false`
# (LLVM's vectorizer mis-peels this shape). With the stamp: ~10.4B ops/s,
# C parity. Losing it drops to ~3.8B — the 7B floor catches that while
# riding out load variance.
THRESH_RUNS = 9
thresh = {}
thresh["array_get"] = 12000000000
thresh["array_mod"] = 7000000000

# ---- integer-only formatting (interpreter float division is exact-rational) -
-> lj(s, w)
  out = "" + s
  while out.size() < w
    out = out + " "
  out

-> rj(s, w)
  out = "" + s
  while out.size() < w
    out = " " + out
  out

-> pad(n, w)
  s = n.to_s()
  while s.size() < w
    s = "0" + s
  s

-> scaled(n, d)
  whole = n / d
  frac = ((n % d) * 100) / d
  if frac == 0
    return whole.to_s()
  whole.to_s() + "." + pad(frac, 2)

# integer ops/sec -> "1.35B" / "80.0M" / "4.34M" / "512K" / "42"
-> fmt_rate(n)
  if n >= 1000000000
    return scaled(n, 1000000000) + "B"
  if n >= 1000000
    return scaled(n, 1000000) + "M"
  if n >= 1000
    return scaled(n, 1000) + "K"
  n.to_s()

# nanoseconds/op (integer) -> "0.48" / "12.4" / "284"
-> fmt_ns(ns_x100)
  if ns_x100 >= 100000
    return (ns_x100 / 100).to_s()
  if ns_x100 >= 1000
    return (ns_x100 / 100).to_s() + "." + pad((ns_x100 % 100) / 10, 1)
  (ns_x100 / 100).to_s() + "." + pad(ns_x100 % 100, 2)

-> fmt_x(x100)
  if x100 >= 1000
    return (x100 / 100).to_s() + "×"
  (x100 / 100).to_s() + "." + pad(x100 % 100, 2) + "×"

-> have_cmd(c)
  capture("command -v [c] 2>/dev/null").strip().size() > 0

-> have_file(path)
  capture("test -f \"[path]\" && echo yes").strip() == "yes"

-> is_exe(path)
  capture("test -s \"[path]\" -a -x \"[path]\" && echo yes").strip() == "yes"

# ---- output parsing -------------------------------------------------------
-> line_value(output, prefix)
  lines = output.split("\n")
  i = 0
  plen = prefix.size()
  while i < lines.size()
    ln = lines[i]
    if ln.size() >= plen && ln.slice(0, plen) == prefix
      return ln.slice(plen, ln.size() - plen).strip()
    i = i + 1
  ""

-> parse_elapsed(output)
  v = line_value(output, "elapsed: ")
  if v.size() > 0 && v.slice(v.size() - 1, 1) == "s"
    v = v.slice(0, v.size() - 1)
  if v == ""
    return -1.0
  v.to_f()

-> parse_ops(output)
  v = line_value(output, "ops: ")
  if v == ""
    return 0
  v.to_i()

# ---- argument parsing (options via env; wrapper translates --flags) --------
# Default runs=1: each run is calibrated to ~1s, stable enough on its own.
runs = 1
rv = env("BENCH_RUNS")
if rv != nil && rv != ""
  runs = rv.to_i()
if runs < 1
  runs = 1

list_only = env("BENCH_LIST") != nil && env("BENCH_LIST") != ""
baseline_mode = env("BENCH_BASELINE") != nil && env("BENCH_BASELINE") != ""
compare_mode = env("BENCH_COMPARE") != nil && env("BENCH_COMPARE") != ""
gate_mode = env("BENCH_GATE") != nil && env("BENCH_GATE") != ""
baseline_path = "bench_baseline.txt"

want = []
args = argv()
ai = 0
while ai < args.size()
  a = args[ai]
  if a.size() >= 2 && a.slice(0, 2) == "--"
    ai = ai
  else
    if !prims.include?(a)
      << "[REDC]unknown primitive: [a][RESET]"
      << "available: " + prims.join(" ")
      exit(1)
    want.push(a)
  ai = ai + 1

if want.size() > 0
  prims = want

if list_only
  << "[BOLD]Tungsten primitive-op baseline[RESET]"
  ci = 0
  while ci < cats.size()
    c = cats[ci]
    << "  [WHITE][c][RESET]"
    pi = 0
    while pi < prims.size()
      p = prims[pi]
      if cat[p] == c
        << "    " + lj(p, 14) + DIM + desc[p] + RESET
      pi = pi + 1
    ci = ci + 1
  exit(0)

# ---- measurement ----------------------------------------------------------
builddir = capture("mktemp -d 2>/dev/null").strip
if builddir == ""
  builddir = "/tmp/tungsten-bench-prim"
  system("mkdir -p \"[builddir]\"")

timeout_prefix = ""
if have_cmd("timeout")
  timeout_prefix = "timeout 120 "
elsif have_cmd("gtimeout")
  timeout_prefix = "gtimeout 120 "

# Calibration: each measured run is auto-sized to ~1 second so numbers are
# stable and the whole suite streams predictably. A cheap pilot finds the
# per-op cost; the real run is scaled to hit the target. BENCH_ITERS overrides
# the loop count in every primitive (see benchmarks/primitives/*.w).
CAL_PILOT = 500000
CAL_TARGET_US = 1000000
CAL_MIN = 500000
CAL_MAX = 4000000000

# Run a compiled primitive with a specific iteration count; [ops, microseconds]
# or [-1, -1] on failure.
-> run_with(out, iters)
  o = capture("BENCH_ITERS=[iters] " + timeout_prefix + "\"[out]\" 2>/dev/null")
  e = parse_elapsed(o)
  if e < 0.0
    return [-1, -1]
  us = (e * 1000000).to_i
  if us < 1
    us = 1
  [parse_ops(o), us]

# Compile, pilot to size a ~1s run, then best-of-N at that size.
# Returns [ops_per_sec, ok]. Integer microseconds throughout.
-> bench_native(src, runs)
  out = builddir + "/" + capture("basename \"[src]\" .w").strip
  # Fast archive-linked -o path (~9x faster to compile than `compile --native`,
  # identical runtime for these self-contained hot loops).
  system("\"[tungsten]\" -o \"[out]\" \"[src]\" >/dev/null 2>&1")
  if !is_exe(out)
    return [0, false]
  pilot = run_with(out, CAL_PILOT)
  if pilot[0] <= 0
    return [0, false]
  target = (CAL_PILOT * CAL_TARGET_US) / pilot[1]
  if target < CAL_MIN
    target = CAL_MIN
  if target > CAL_MAX
    target = CAL_MAX
  best_us = -1
  ops = 0
  r = 0
  while r < runs
    m = run_with(out, target)
    if m[0] <= 0
      r = runs
    else
      ops = m[0]
      if best_us < 0 || m[1] < best_us
        best_us = m[1]
    r = r + 1
  if best_us <= 0 || ops <= 0
    return [0, false]
  [(ops * 1000000) / best_us, true]

# peer languages for --compare
-> peer_cmd(lang, src, out)
  case lang
  when "c"
    return "clang -O3 -march=native -flto -DNDEBUG \"[src]\" -o \"[out]\" >/dev/null 2>&1"
  when "rs"
    return "rustc -O -C target-cpu=native \"[src]\" -o \"[out]\" >/dev/null 2>&1"
  when "go"
    return "go build -o \"[out]\" \"[src]\" >/dev/null 2>&1"
  when "zig"
    return "zig build-exe -O ReleaseFast -lc \"[src]\" -femit-bin=\"[out]\" >/dev/null 2>&1"
  when "odin"
    return "odin build \"[src]\" -file -o:speed -out:\"[out]\" >/dev/null 2>&1"
  when "py"
    # No compile — the .py carries a python3 shebang; "build" is copy+chmod.
    return "cp \"[src]\" \"[out]\" && chmod +x \"[out]\" >/dev/null 2>&1"
  ""

-> bench_peer(name, lang, ext, runs)
  src = primdir + "/peers/" + name + "." + ext
  if !have_file(src)
    return 0
  out = builddir + "/" + name + "_" + lang
  cmd = peer_cmd(lang, src, out)
  if cmd == ""
    return 0
  system(cmd)
  if !is_exe(out)
    return 0
  best_us = -1
  ops = 0
  r = 0
  while r < runs
    o = capture(timeout_prefix + "\"[out]\" 2>/dev/null")
    e = parse_elapsed(o)
    if r == 0
      ops = parse_ops(o)
    if e >= 0.0
      us = (e * 1000000).to_i
      if us < 1
        us = 1
      if best_us < 0 || us < best_us
        best_us = us
    else
      r = runs
    r = r + 1
  if best_us <= 0 || ops <= 0
    return 0
  (ops * 1000000) / best_us

# CPU spin to stabilize frequency + caches before measuring (BENCH_ITERS=2B
# int_add ≈ 1s/run, so ~3 runs fills the budget).
-> warmup(secs)
  wout = builddir + "/warmup"
  system("\"[tungsten]\" -o \"[wout]\" \"[primdir]/int_add.w\" >/dev/null 2>&1")
  if is_exe(wout)
    warmed = 0.0
    while warmed < secs
      o = capture("BENCH_ITERS=2000000000 \"[wout]\" 2>/dev/null")
      e = parse_elapsed(o)
      if e < 0.0
        warmed = secs
      else
        warmed = warmed + e
  nil

# Read a bench_baseline.txt (name<TAB>ops_per_sec per line) into a map.
-> read_baseline(path)
  m = {}
  raw = capture("cat \"[path]\" 2>/dev/null")
  lines = raw.split("\n")
  i = 0
  while i < lines.size()
    ln = lines[i].strip()
    if ln.size() > 0
      parts = ln.split("\t")
      if parts.size() == 2
        m[parts[0].strip()] = parts[1].strip().to_i()
    i = i + 1
  m

# ---- baseline mode: warm up, measure, WRITE bench_baseline.txt ------------
if baseline_mode
  << "  [GREY]warming up (3s)…[RESET]"
  warmup(3.0)
  content = ""
  pi = 0
  while pi < prims.size()
    p = prims[pi]
    res = bench_native(primdir + "/" + p + ".w", runs)
    if res[1]
      content = content + p + "\t" + res[0].to_s() + "\n"
    pi = pi + 1
  system("printf '%s' '" + content + "' > \"[baseline_path]\"")
  << "  [GREEN]✔[RESET] wrote [WHITE][baseline_path][RESET] — rerun [WHITE]tungsten bench[RESET] to see before/after/Δ"
  if builddir != "" && builddir != "/"
    system("rm -rf \"[builddir]\"")
  exit(0)

# ---- machine + header -----------------------------------------------------
os = capture("uname -s").strip
cpu = "unknown CPU"
cores = capture("getconf _NPROCESSORS_ONLN 2>/dev/null").strip
if os == "Darwin"
  cpu = capture("sysctl -n machdep.cpu.brand_string 2>/dev/null").strip
  cores = capture("sysctl -n hw.ncpu 2>/dev/null").strip
else
  b2 = capture("grep -m1 'model name' /proc/cpuinfo 2>/dev/null | sed 's/.*: //'").strip
  if b2.size() > 0
    cpu = b2

version = env("TUNGSTEN_VERSION")
if version == nil || version == ""
  version = capture("cat \"[root]/VERSION\" 2>/dev/null").strip
if version == ""
  version = "dev"

# A baseline file (from a prior `--baseline`) turns on the before/after/Δ table.
base = read_baseline(baseline_path)
have_base = base.size() > 0

# Absolute bar (full = 4B ops/s) so each row's bar is drawn as it streams in,
# with no pre-pass to find the global max.
BAR_FULL = 4000000000
BARW = 16
BLOCK = "█"
-> bar_for(r, w)
  cells = (r * w) / BAR_FULL
  if cells > w
    cells = w
  BLOCK * cells

# Peer ratio column (Tungsten ÷ peer) or blank when the peer is absent/fails.
# Width 7 fits compiled peers (1.23×); Python ratios run to hundreds× — pass 9.
-> ratio_col(r, peer_rate, w = 7)
  if peer_rate <= 0
    return rj("·", w)
  rj(fmt_x((r * 100) / peer_rate), w)

<< ""
<< "  " + ORANGE + BOLD + "⚡ TUNGSTEN PRIMITIVE BASELINE" + RESET + "   " + DIM + "v" + version + RESET
<< "  [GREY]" + "─" * 66 + "[RESET]"
<< "  [GREY]machine[RESET] [cpu]  [GREY]·[RESET] [cores] cores  [GREY]·[RESET] [os]"
<< "  [GREY]method  ~1s/op calibrated · 3s warmup · data-dependent loops · native -O[RESET]"

hdr = "  " + lj("primitive", 14) + rj("ns/op", 8) + "  " + rj("rate", 9) + "  " + lj("unit", 7)
if compare_mode
  hdr = hdr + rj("C", 7) + rj("Rust", 7) + rj("Go", 7) + rj("Zig", 7) + rj("Odin", 7) + rj("Py", 9)
elsif have_base
  hdr = hdr + rj("baseline", 10) + rj("Δ", 8)
<< ""
<< DIM + hdr + RESET

# warm up before the first measurement
<< "  [GREY]warming up (3s)…[RESET]"
warmup(3.0)

# ---- stream: measure + print each primitive the moment it completes --------
# gate_fail is a 1-element list so the top-level loop can mutate it in place.
gate_fail = [false]
ci = 0
while ci < cats.size()
  c = cats[ci]
  any = false
  pi = 0
  while pi < prims.size()
    if cat[prims[pi]] == c
      any = true
    pi = pi + 1
  if any
    << ""
    << "  " + DARKB + c + RESET
    pi = 0
    while pi < prims.size()
      p = prims[pi]
      if cat[p] == c
        # Primitives with a regression floor are measured best-of-THRESH_RUNS to
        # reach steady-state peak, so a floor near the peak doesn't flap on noise.
        pruns = runs
        floor = thresh[p]
        if floor != nil && pruns < THRESH_RUNS
          pruns = THRESH_RUNS
        res = bench_native(primdir + "/" + p + ".w", pruns)
        if !res[1]
          << "  " + lj(p, 14) + GREY + "  build/run failed" + RESET
        else
          r = res[0]
          # ns/op ×100 = 1e11 / rate  (integer)
          ns100 = 0
          if r > 0
            ns100 = 100000000000 / r
          line = "  " + ORANGE + lj(p, 14) + RESET
          line = line + GREY + rj(fmt_ns(ns100), 8) + RESET
          line = line + "  " + WHITE + rj(fmt_rate(r), 9) + RESET
          line = line + "  " + DIM + lj(unit[c], 7) + RESET
          if compare_mode
            if peer[p] == true
              line = line + GREY + ratio_col(r, bench_peer(p, "c", "c", runs)) + ratio_col(r, bench_peer(p, "rs", "rs", runs)) + ratio_col(r, bench_peer(p, "go", "go", runs)) + ratio_col(r, bench_peer(p, "zig", "zig", runs)) + ratio_col(r, bench_peer(p, "odin", "odin", runs)) + ratio_col(r, bench_peer(p, "py", "py", runs), 9) + RESET
            else
              line = line + GREY + rj("·", 7) + rj("·", 7) + rj("·", 7) + rj("·", 7) + rj("·", 7) + rj("·", 9) + RESET
          elsif have_base
            b = base[p]
            if b != nil && b > 0
              dx = (r * 100) / b
              dcol = GREY
              if dx >= 102
                dcol = GREEN
              elsif dx <= 98
                dcol = REDC
              line = line + GREY + rj(fmt_rate(b), 10) + RESET + dcol + rj(fmt_x(dx), 8) + RESET
            else
              line = line + GREY + rj("·", 10) + rj("new", 8) + RESET
          line = line + "  " + ORANGE + bar_for(r, BARW) + RESET + "  " + DIM + desc[p] + RESET
          # The floor is a clean-machine codegen gate; --compare compiles 8 peer
          # binaries mid-run and depresses the numbers, so skip the check there.
          if floor != nil && !compare_mode
            if r >= floor
              line = line + GREEN + "  ✔ >=" + fmt_rate(floor) + " floor" + RESET
            else
              line = line + REDC + "  x " + fmt_rate(r) + " < " + fmt_rate(floor) + " floor — REGRESSION" + RESET
              gate_fail[0] = true
          << line
      pi = pi + 1
  ci = ci + 1

<< ""
if compare_mode
  << "  [GREY]C clang -O3 -march=native -flto · Rust rustc -O · Go go build · Zig ReleaseFast · Odin -o:speed · Py CPython 3 · ratio = Tungsten ÷ peer[RESET]"
elsif have_base
  << "  [GREY]Δ = now ÷ baseline · [GREEN]green[GREY] faster now · [REDC]red[GREY] slower · baseline from [baseline_path][RESET]"
else
  << "  [GREY]tip  `tungsten bench --baseline` writes bench_baseline.txt; rerun `tungsten bench` for before/after/Δ[RESET]"
<< ""

if builddir != "" && builddir != "/"
  system("rm -rf \"[builddir]\"")

# Regression gate: a breached floor is always flagged RED inline; `--gate` makes
# it a hard failure (non-zero exit) for CI.
if gate_fail[0]
  if gate_mode
    << "  [REDC]✗ regression gate FAILED — a primitive fell below its floor[RESET]"
    << ""
    exit(1)
  else
    << "  [REDC]✗ a primitive is below its regression floor (run with --gate to fail CI)[RESET]"
    << ""
