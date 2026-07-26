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
BOLD  = "\e[1m"
DIM   = "\e[2m"
RESET = "\e[0m"
GOLD  = "\e[38;5;220m"
GREEN = "\e[38;5;47m"
REDC  = "\e[38;5;203m"
GREY  = "\e[38;5;245m"
WHITE = "\e[38;5;255m"
WCOL  = "\e[38;5;51m"

# ---- catalogue ------------------------------------------------------------
# Ordered list of primitives grouped by category. Op counts are NOT stored
# here — each program reports its own `ops:` line, so retuning a program never
# desyncs the harness. `cat` groups the display; `desc` documents the metric;
# `peer` marks primitives that have a fair single-op peer equivalent for
# --compare.
prims = ["int_add", "int_mul", "int_bitops", "float_mul", "new_array", "new_string", "str_concat", "new_object", "new_hash", "array_get", "array_set", "hash_get", "str_build", "fn_call", "method_call", "block_call"]

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
cat["array_get"] = "collection"; desc["array_get"] = "typed-array element read (in-bounds)"
cat["array_set"] = "collection"; desc["array_set"] = "typed-array element write (in-bounds)"
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
peer["array_set"] = true

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
runs = 3
rv = env("BENCH_RUNS")
if rv != nil && rv != ""
  runs = rv.to_i()
if runs < 1
  runs = 1

list_only = env("BENCH_LIST") != nil && env("BENCH_LIST") != ""
baseline_mode = env("BENCH_BASELINE") != nil && env("BENCH_BASELINE") != ""
compare_mode = env("BENCH_COMPARE") != nil && env("BENCH_COMPARE") != ""

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

# Compile + run a program best-of-N; return [ops_per_sec, ok]. Uses integer
# microseconds throughout (no float division): ops/sec = ops * 1e6 / us.
-> bench_native(src, runs)
  out = builddir + "/" + capture("basename \"[src]\" .w").strip
  cmd = "\"[tungsten]\" compile --native \"[src]\" -o \"[out]\" >/dev/null 2>&1"
  system(cmd)
  if !is_exe(out)
    return [0, false]
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
    return [0, false]
  [(ops * 1000000) / best_us, true]

# peer languages for --compare
-> peer_cmd(lang, src, out)
  case lang
  when "c"
    return "clang -O3 -march=native -flto -DNDEBUG \"[src]\" -o \"[out]\" >/dev/null 2>&1"
  when "rs"
    return "rustc -O -C target-cpu=native \"[src]\" -o \"[out]\" >/dev/null 2>&1"
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

# ---- run all --------------------------------------------------------------
rate = {}
okf = {}
pi = 0
while pi < prims.size()
  p = prims[pi]
  res = bench_native(primdir + "/" + p + ".w", runs)
  rate[p] = res[0]
  okf[p] = res[1]
  pi = pi + 1

# ---- baseline (machine-readable) ------------------------------------------
if baseline_mode
  pi = 0
  while pi < prims.size()
    p = prims[pi]
    if okf[p]
      << p + "\t" + rate[p].to_s()
    pi = pi + 1
  if builddir != "" && builddir != "/"
    system("rm -rf \"[builddir]\"")
  exit(0)

# ---- pretty report --------------------------------------------------------
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

# widest bar scales to the fastest rate across the whole run
maxrate = 1
pi = 0
while pi < prims.size()
  p = prims[pi]
  if okf[p] && rate[p] > maxrate
    maxrate = rate[p]
  pi = pi + 1

BARW = 20
BLOCK = "█"
-> bar_for(r, maxr, w)
  if maxr <= 0
    return ""
  cells = (r * w) / maxr
  if cells > w
    cells = w
  BLOCK * cells

<< ""
<< "  [WHITE][BOLD]⚡ TUNGSTEN PRIMITIVE BASELINE[RESET]   [DIM]v[version][RESET]"
<< "  [GREY]" + "─" * 62 + "[RESET]"
<< "  [GREY]machine[RESET] [cpu]  [GREY]·[RESET] [cores] cores  [GREY]·[RESET] [os]"
<< "  [GREY]method  best of [runs] runs · data-dependent loops (no dead-code elision) · native -O[RESET]"

hdr = "  " + lj("primitive", 14) + rj("ns/op", 8) + "  " + rj("rate", 9) + "  " + lj("unit", 7)
if compare_mode
  hdr = hdr + rj("C", 8) + rj("Rust", 8)
<< ""
<< DIM + hdr + RESET

ci = 0
while ci < cats.size()
  c = cats[ci]
  # does any selected primitive belong to this category?
  any = false
  pi = 0
  while pi < prims.size()
    if cat[prims[pi]] == c
      any = true
    pi = pi + 1
  if any
    << ""
    << "  [WHITE][BOLD][c][RESET]"
    pi = 0
    while pi < prims.size()
      p = prims[pi]
      if cat[p] == c
        if !okf[p]
          << "  " + lj(p, 14) + GREY + "  build/run failed" + RESET
        else
          r = rate[p]
          # ns/op ×100 = 1e11 / rate  (integer)
          ns100 = 0
          if r > 0
            ns100 = 100000000000 / r
          line = "  " + WCOL + lj(p, 14) + RESET
          line = line + GREY + rj(fmt_ns(ns100), 8) + RESET
          line = line + "  " + WHITE + rj(fmt_rate(r), 9) + RESET
          line = line + "  " + DIM + lj(unit[c], 7) + RESET
          if compare_mode && peer[p] == true
            cr = bench_peer(p, "c", "c", runs)
            rr = bench_peer(p, "rs", "rs", runs)
            cx = ""
            if cr > 0
              cx = fmt_x((r * 100) / cr)
            rx = ""
            if rr > 0
              rx = fmt_x((r * 100) / rr)
            line = line + GREY + rj(cx, 8) + rj(rx, 8) + RESET
          line = line + "  " + WCOL + bar_for(r, maxrate, BARW) + RESET + "  " + DIM + desc[p] + RESET
          << line
      pi = pi + 1
  ci = ci + 1

<< ""
if compare_mode
  << "  [GREY]C clang -O3 -march=native -flto · Rust rustc -O target-cpu=native · ratio = Tungsten ÷ peer[RESET]"
<< "  [GREY]tip  `tungsten bench --baseline > before.txt`, change code, diff against `--baseline` again[RESET]"
<< ""

if builddir != "" && builddir != "/"
  system("rm -rf \"[builddir]\"")
