#!/usr/bin/env bash
exec "$(dirname "$0")/../tungsten" run "$0" "$@"
# ---------------------------------------------------------------------------
# `tungsten bench` — the Tungsten cross-language benchmark suite.
#
# Compiles a curated set of workloads in Tungsten and every peer toolchain it
# can find (C, Rust, Go, Crystal, Ruby, Python), verifies they all compute the
# same answer, times the hot loop of each, and renders a colourful report:
#   · HEAD TO HEAD       — same algorithm in every language, parity vs C
#   · THROUGHPUT BASELINES — raw ops/sec to track across releases
#   · SCOREBOARD         — geometric-mean speed vs each language
#
# Sources live in benchmarks/suite/<name>.<ext>. Each program prints its
# result on line 1 and `elapsed: <seconds>s` on line 2, so we time the inner
# computation (not process start-up) — fair to compiled and interpreted alike.
#
# All ratio arithmetic is done in integer microseconds on purpose: the
# interpreter's float division promotes inexact results to exact rationals,
# so we never divide floats here.
#
# Usage:
#   tungsten bench                      # full suite, all detected languages
#   tungsten bench collatz mandelbrot   # only named benchmarks
#   tungsten bench --only w,c,rust      # only these languages
#   tungsten bench --runs 5             # best-of-N timing (default 3)
#   tungsten bench --list               # list benchmarks and exit
# ---------------------------------------------------------------------------

root = capture("cd \"[__DIR__]/../..\" && pwd").strip
suite = root + "/benchmarks/suite"
tungsten = root + "/bin/tungsten"
gmp = capture("brew --prefix gmp 2>/dev/null").strip

# ---- palette --------------------------------------------------------------
BOLD  = "\e[1m"
DIM   = "\e[2m"
RESET = "\e[0m"
GOLD  = "\e[38;5;220m"
GREEN = "\e[38;5;47m"
REDC  = "\e[38;5;203m"
GREY  = "\e[38;5;245m"
WHITE = "\e[38;5;255m"

col = {}
col["w"]  = "\e[38;5;51m"
col["c"]  = "\e[38;5;223m"
col["rs"] = "\e[38;5;208m"
col["go"] = "\e[38;5;44m"
col["cr"] = "\e[38;5;213m"
col["rb"] = "\e[38;5;197m"
col["py"] = "\e[38;5;75m"

disp = {}
disp["w"] = "Tungsten"
disp["c"] = "C"
disp["rs"] = "Rust"
disp["go"] = "Go"
disp["cr"] = "Crystal"
disp["rb"] = "Ruby"
disp["py"] = "Python"

all_langs = ["w", "c", "rs", "go", "cr", "rb", "py"]
compiled = ["w", "c", "rs", "go", "cr"]

BLOCK = "█"
PARTS = [" ", "▏", "▎", "▍", "▌", "▋", "▊", "▉"]
BARW = 24

# ---- benchmark catalogue --------------------------------------------------
# section "h" = head-to-head (parity story); "t" = throughput baseline.
benches = ["collatz", "mandelbrot", "julia", "nbody", "decimal_e", "string_scan", "array_sort", "array_fill", "string_build", "bigint_fib", "rational_harmonic"]

glyph = {}
title = {}
desc  = {}
work  = {}
unit  = {}
section = {}

glyph["collatz"] = "🔁"
title["collatz"] = "collatz"
desc["collatz"]  = "sum of Collatz stopping times, 1..1,000,000"
work["collatz"]  = 131434424
unit["collatz"]  = "steps"
section["collatz"] = "h"

glyph["mandelbrot"] = "🌀"
title["mandelbrot"] = "mandelbrot"
desc["mandelbrot"]  = "escape-time fractal, 2000×2000, 50 iterations"
work["mandelbrot"]  = 4000000
unit["mandelbrot"]  = "pixels"
section["mandelbrot"] = "h"

glyph["julia"] = "🌌"
title["julia"] = "julia"
desc["julia"]  = "Julia-set fractal, 2000×2000 grid"
work["julia"]  = 4000000
unit["julia"]  = "pixels"
section["julia"] = "h"

glyph["nbody"] = "🪐"
title["nbody"] = "nbody"
desc["nbody"]  = "gravitational n-body: 5 bodies, 500k timesteps"
work["nbody"]  = 500000
unit["nbody"]  = "steps"
section["nbody"] = "h"

glyph["decimal_e"] = "🧊"
title["decimal_e"] = "decimal_e"
desc["decimal_e"]  = "Euler's number via 100k Taylor expansions"
work["decimal_e"]  = 10100000
unit["decimal_e"]  = "terms"
section["decimal_e"] = "h"

glyph["string_scan"] = "🔎"
title["string_scan"] = "string_scan"
desc["string_scan"]  = "substring search across a 110 MB text"
work["string_scan"]  = 110000000
unit["string_scan"]  = "bytes"
section["string_scan"] = "h"

glyph["array_sort"] = "📊"
title["array_sort"] = "array_sort"
desc["array_sort"]  = "sort 2,000,000 pseudo-random 32-bit ints"
work["array_sort"]  = 2000000
unit["array_sort"]  = "elements"
section["array_sort"] = "h"

glyph["array_fill"] = "🗄"
title["array_fill"] = "array_fill"
desc["array_fill"]  = "200M indexed writes into a raw int64 array"
work["array_fill"]  = 200000000
unit["array_fill"]  = "stores"
section["array_fill"] = "t"

glyph["string_build"] = "🧵"
title["string_build"] = "string_build"
desc["string_build"]  = "400k growable-buffer appends → 10.4M chars"
work["string_build"]  = 10400000
unit["string_build"]  = "chars"
section["string_build"] = "t"

glyph["bigint_fib"] = "🔢"
title["bigint_fib"] = "bigint_fib"
desc["bigint_fib"]  = "100,000-term Fibonacci in arbitrary precision"
work["bigint_fib"]  = 100000
unit["bigint_fib"]  = "big adds"
section["bigint_fib"] = "t"

glyph["rational_harmonic"] = "🧮"
title["rational_harmonic"] = "rational_harmonic"
desc["rational_harmonic"]  = "exact harmonic sum as a reduced fraction, 3000 terms"
work["rational_harmonic"]  = 3000
unit["rational_harmonic"]  = "terms"
section["rational_harmonic"] = "t"

# ---- string + integer helpers (no float division anywhere) ----------------
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

# n/d rendered with up to two decimals, integer math only
-> scaled(n, d)
  whole = n / d
  frac = ((n % d) * 100) / d
  if frac == 0
    return whole.to_s()
  whole.to_s() + "." + pad(frac, 2)

# integer ops/sec → human string ("1.35B", "80M", "4.34M", "512K", "42")
-> fmt_rate(n)
  if n >= 1000000000
    return scaled(n, 1000000000) + "B"
  if n >= 1000000
    return scaled(n, 1000000) + "M"
  if n >= 1000
    return scaled(n, 1000) + "K"
  n.to_s()

# integer microseconds → "1.234s" / "96.8ms" / "0.7ms"
-> fmt_time(us)
  if us >= 1000000
    return (us / 1000000).to_s() + "." + pad((us % 1000000) / 1000, 3) + "s"
  (us / 1000).to_s() + "." + (((us % 1000) / 100)).to_s() + "ms"

# ratio×100 → "1.00×" / "0.95×" / "43×"
-> fmt_x(x100)
  if x100 >= 1000
    return (x100 / 100).to_s() + "×"
  (x100 / 100).to_s() + "." + pad(x100 % 100, 2) + "×"

-> ipow(base, e)
  r = 1
  i = 0
  while i < e
    r = r * base
    i = i + 1
  r

# floor(x ** (1/n)) by bisection — for geometric means in integer fixed point
-> inth_root(x, n)
  if x <= 0
    return 0
  hi = 2
  while ipow(hi, n) <= x
    hi = hi * 2
  lo = 1
  while lo < hi
    mid = ((lo + hi + 1) / 2).to_i
    if ipow(mid, n) <= x
      lo = mid
    else
      hi = mid - 1
  lo

-> have_cmd(c)
  capture("command -v [c] 2>/dev/null").strip().size() > 0

-> have_file(path)
  capture("test -f \"[path]\" && echo yes").strip() == "yes"

-> is_exe(path)
  capture("test -s \"[path]\" -a -x \"[path]\" && echo yes").strip() == "yes"

-> src_path(bench, lang)
  suite + "/" + bench + "." + lang

-> compile_command(lang, src, out, bench)
  case lang
  when "w"
    return "\"[tungsten]\" compile --native \"[src]\" -o \"[out]\" >/dev/null 2>&1"
  when "c"
    extra = ""
    if bench == "bigint_fib" || bench == "rational_harmonic"
      extra = " -I[gmp]/include -L[gmp]/lib -lgmp"
    return "clang -O3 -march=native -flto -DNDEBUG \"[src]\"[extra] -o \"[out]\" >/dev/null 2>&1"
  when "rs"
    return "rustc -O -C target-cpu=native \"[src]\" -o \"[out]\" >/dev/null 2>&1"
  when "go"
    return "go build -o \"[out]\" \"[src]\" >/dev/null 2>&1"
  when "cr"
    return "crystal build --release --no-debug -o \"[out]\" \"[src]\" >/dev/null 2>&1"
  ""

-> run_command(lang, src, out)
  base = "\"[out]\""
  if lang == "rb"
    base = "ruby --yjit \"[src]\""
  elsif lang == "py"
    base = "python3 \"[src]\""
  # timeout_prefix bounds any single run so a pathological program (e.g. a
  # quadratic string scan) can never hang the whole suite.
  timeout_prefix + base

-> parse_elapsed(output)
  lines = output.split("\n")
  i = 0
  while i < lines.size()
    ln = lines[i]
    if ln.size() >= 9 && ln.slice(0, 9) == "elapsed: "
      rest = ln.slice(9, ln.size() - 9)
      if rest.size() > 0 && rest.slice(rest.size() - 1, 1) == "s"
        rest = rest.slice(0, rest.size() - 1)
      return rest.to_f()
    i = i + 1
  -1.0

-> first_line(output)
  lines = output.split("\n")
  if lines.size() > 0
    return lines[0]
  ""

-> digit?(ch)
  ch == "0" || ch == "1" || ch == "2" || ch == "3" || ch == "4" || ch == "5" || ch == "6" || ch == "7" || ch == "8" || ch == "9"

-> numeric?(s)
  if s.size() == 0
    return false
  i = 0
  seen = false
  while i < s.size()
    ch = s.slice(i, 1)
    if digit?(ch)
      seen = true
    elsif ch == "." || ch == "-" || ch == "+" || ch == "e" || ch == "E"
      seen = seen
    else
      return false
    i = i + 1
  seen

# results agree when equal, or numeric within 0.01% (fp counts differ in the
# last digits). integer cross-multiply — never divide.
-> has_dot(s)
  i = 0
  while i < s.size()
    if s.slice(i, 1) == "."
      return true
    i = i + 1
  false

-> results_match(a, b)
  if a == b
    return true
  if numeric?(a) && numeric?(b)
    # fractional result (e.g. nbody's energy): relative tolerance via
    # float subtract + integer-scaled compare (no float division).
    if has_dot(a) || has_dot(b)
      fa = a.to_f
      fb = b.to_f
      d = fa - fb
      if d < 0.0
        d = 0.0 - d
      m = fa
      if m < 0.0
        m = 0.0 - m
      fb2 = fb
      if fb2 < 0.0
        fb2 = 0.0 - fb2
      if fb2 > m
        m = fb2
      if m == 0.0
        return true
      return d * 10000 < m
    # integer result: exact, or within 0.01% (fp counts differ in last digits)
    ia = a.to_i
    ib = b.to_i
    diff = ia - ib
    if diff < 0
      diff = 0 - diff
    m = ia
    if ib > m
      m = ib
    if m < 0
      m = 0 - m
    if m == 0
      return true
    return diff * 10000 < m
  false

# ---- argument parsing (options via env; wrapper translates --flags) --------
-> normalize_langs(spec)
  out = []
  parts = spec.downcase.split(",")
  i = 0
  while i < parts.size()
    s = parts[i].strip
    if s == "tungsten"
      s = "w"
    elsif s == "rust"
      s = "rs"
    elsif s == "golang"
      s = "go"
    elsif s == "crystal"
      s = "cr"
    elsif s == "ruby"
      s = "rb"
    elsif s == "python" || s == "py3"
      s = "py"
    if s == "w" || s == "c" || s == "rs" || s == "go" || s == "cr" || s == "rb" || s == "py"
      out.push(s)
    i = i + 1
  out

runs = 3
rv = env("BENCH_RUNS")
if rv != nil && rv != ""
  runs = rv.to_i()
if runs < 1
  runs = 1

langs = all_langs
ov = env("BENCH_ONLY")
if ov != nil && ov != ""
  langs = normalize_langs(ov)

list_only = false
lv = env("BENCH_LIST")
if lv != nil && lv != ""
  list_only = true

want = []
args = argv()
ai = 0
while ai < args.size()
  a = args[ai]
  if a.size() >= 2 && a.slice(0, 2) == "--"
    ai = ai
  else
    if !benches.include?(a)
      << "[REDC]unknown benchmark: [a][RESET]"
      << "available: " + benches.join(" ")
      exit(1)
    want.push(a)
  ai = ai + 1

if want.size() > 0
  benches = want

if list_only
  << "[BOLD]Tungsten benchmark suite[RESET]"
  bi = 0
  while bi < benches.size()
    b = benches[bi]
    tag = "head-to-head"
    if section[b] == "t"
      tag = "throughput"
    << "  " + glyph[b] + "  " + lj(title[b], 20) + DIM + lj(tag, 14) + desc[b] + RESET
    bi = bi + 1
  exit(0)

# ---- detect toolchains ----------------------------------------------------
avail = {}
avail["w"] = is_exe(tungsten) || have_file(tungsten)
avail["c"] = have_cmd("clang")
avail["rs"] = have_cmd("rustc")
avail["go"] = have_cmd("go")
avail["cr"] = have_cmd("crystal")
avail["rb"] = have_cmd("ruby")
avail["py"] = have_cmd("python3")

active = []
li = 0
while li < langs.size()
  l = langs[li]
  if avail[l]
    active.push(l)
  li = li + 1

# ---- machine + banner -----------------------------------------------------
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

<< ""
<< "  [WHITE][BOLD]⚡ TUNGSTEN BENCHMARK SUITE[RESET]   [DIM]v[version][RESET]"
<< "  [GREY]" + "─" * 60 + "[RESET]"
<< "  [GREY]machine[RESET] [cpu]  [GREY]·[RESET] [cores] cores  [GREY]·[RESET] [os]"

print("  [GREY]field  [RESET]")
ci = 0
while ci < all_langs.size()
  l = all_langs[ci]
  if active.include?(l)
    print(col[l] + disp[l] + RESET + "  ")
  elsif langs.include?(l)
    print(DIM + disp[l] + " (missing)" + RESET + "  ")
  ci = ci + 1
<< ""
<< "  [GREY]method best of [runs] runs · inner-loop time · outputs cross-checked · fastest = full bar[RESET]"

# ---- compile --------------------------------------------------------------
builddir = capture("mktemp -d 2>/dev/null").strip
if builddir == ""
  builddir = "/tmp/tungsten-bench"
  system("mkdir -p \"[builddir]\"")

built = {}
srcok = {}
times = {}
results = {}

# ---- measure --------------------------------------------------------------
-> measure(cmd, runs)
  best = -1.0
  result = ""
  r = 0
  while r < runs
    out = capture(cmd + " 2>/dev/null")
    if r == 0
      result = first_line(out)
    e = parse_elapsed(out)
    if e >= 0.0
      if best < 0.0 || e < best
        best = e
    else
      # no elapsed line → the run failed or the timeout killed it; don't
      # burn further attempts on a broken/hanging command.
      r = runs
    r = r + 1
  [best, result]

# ---- rendering ------------------------------------------------------------
-> make_bar(num, den)
  if den <= 0
    return ""
  cells8 = (num * BARW * 8) / den
  full = (cells8 / 8).to_i
  if full > BARW
    full = BARW
  bar = BLOCK * full
  part = (cells8 % 8).to_i
  if part > 0 && full < BARW
    bar = bar + PARTS[part]
  bar

-> render_row(b, l, best_us, ref)
  us = times[b][l]
  if us == nil || us <= 0
    if srcok[b] != nil && srcok[b][l]
      << "    " + col[l] + BOLD + lj(disp[l], 9) + RESET + GREY + "  build failed" + RESET
    return 0
  rate = (work[b] * 1000000) / us
  bar = make_bar(best_us, us)
  marker = "  "
  if l == "w"
    marker = col["w"] + "▶ " + RESET
  crown = ""
  if us == best_us
    crown = " [GOLD]★[RESET]"
  vmark = ""
  res = results[b][l]
  if res != nil && ref != "" && !results_match(res, ref)
    vmark = " [REDC]≠[RESET]"
  line = "  " + marker + col[l] + BOLD + lj(disp[l], 9) + RESET
  line = line + GREY + rj(fmt_time(us), 8) + RESET
  line = line + "  " + WHITE + rj(fmt_rate(rate), 7) + RESET + " " + DIM + lj(unit[b] + "/s", 10) + RESET
  line = line + col[l] + bar + RESET + crown + vmark
  << line
  0

# Compile, time, and render ONE benchmark, streaming: the title is printed
# first (so on a TTY it flushes immediately and the run never looks frozen
# during the seconds-long interpreter runs), then rows fill in below it.
-> process_bench(b)
  built[b] = {}
  srcok[b] = {}
  times[b] = {}
  results[b] = {}
  << ""
  << "  " + glyph[b] + " " + BOLD + WHITE + title[b] + RESET + "  [GREY]" + desc[b] + "[RESET]"
  li = 0
  while li < active.size()
    l = active[li]
    src = src_path(b, l)
    srcok[b][l] = have_file(src)
    built[b][l] = false
    times[b][l] = nil
    if srcok[b][l]
      if compiled.include?(l)
        out = builddir + "/" + b + "_" + l
        cmd = compile_command(l, src, out, b)
        if cmd != ""
          system(cmd)
          built[b][l] = is_exe(out)
      else
        built[b][l] = true
    if built[b][l]
      rout = builddir + "/" + b + "_" + l
      rcmd = run_command(l, src, rout)
      rlang = runs
      if l == "rb" || l == "py"
        rlang = 1
      m = measure(rcmd, rlang)
      bt = m[0]
      results[b][l] = m[1]
      if bt > 0.0
        usv = (bt * 1000000).to_i
        if usv < 1
          usv = 1
        times[b][l] = usv
    li = li + 1
  best_us = -1
  li = 0
  while li < active.size()
    l = active[li]
    us = times[b][l]
    if us != nil && us > 0
      if best_us < 0 || us < best_us
        best_us = us
    li = li + 1
  ref = ""
  if results[b]["w"] != nil && results[b]["w"] != ""
    ref = results[b]["w"]
  else
    li = 0
    while li < active.size()
      l = active[li]
      if ref == "" && results[b][l] != nil && results[b][l] != ""
        ref = results[b][l]
      li = li + 1
  li = 0
  while li < active.size()
    l = active[li]
    render_row(b, l, best_us, ref)
    li = li + 1
  0

# Per-run wall-clock guard so no single benchmark can hang the suite.
timeout_prefix = ""
if have_cmd("timeout")
  timeout_prefix = "timeout 60 "
elsif have_cmd("gtimeout")
  timeout_prefix = "gtimeout 60 "

# section 1: head to head
<< ""
<< "  [BOLD][WHITE]━━ HEAD TO HEAD ━━[RESET][GREY]  same algorithm, every language[RESET]"
bi = 0
while bi < benches.size()
  b = benches[bi]
  if section[b] == "h"
    process_bench(b)
  bi = bi + 1

# section 2: throughput baselines
has_t = false
bi = 0
while bi < benches.size()
  if section[benches[bi]] == "t"
    has_t = true
  bi = bi + 1
if has_t
  << ""
  << ""
  << "  [BOLD][WHITE]━━ THROUGHPUT BASELINES ━━[RESET][GREY]  raw ops/sec · record to catch regressions[RESET]"
  bi = 0
  while bi < benches.size()
    b = benches[bi]
    if section[b] == "t"
      process_bench(b)
    bi = bi + 1

# ---- scoreboard -----------------------------------------------------------
# geometric mean of (peer_time / tungsten_time) over the head-to-head set.
<< ""
<< ""
<< "  [BOLD][WHITE]━━ SCOREBOARD ━━[RESET][GREY]  Tungsten speed vs each language (head-to-head geomean)[RESET]"
<< ""

peers = ["c", "rs", "go", "cr", "rb", "py"]
pi = 0
while pi < peers.size()
  l = peers[pi]
  if active.include?(l)
    prod = 1
    n = 0
    bi = 0
    while bi < benches.size()
      b = benches[bi]
      if section[b] == "h"
        tw = times[b]["w"]
        tl = times[b][l]
        if tw != nil && tw > 0 && tl != nil && tl > 0
          prod = prod * ((tl * 1000) / tw)
          n = n + 1
      bi = bi + 1
    if n > 0
      geo_x1000 = inth_root(prod, n)
      geo_x100 = (geo_x1000 / 10).to_i
      verdict = ""
      if geo_x100 >= 105
        verdict = GREEN + "Tungsten faster" + RESET
      elsif geo_x100 >= 95
        verdict = GOLD + "dead heat" + RESET
      elsif geo_x100 >= 70
        gap = (10000 / geo_x100) - 100
        verdict = GREY + disp[l] + " " + gap.to_s() + "% faster" + RESET
      else
        verdict = GREY + disp[l] + " ahead" + RESET
      barnum = geo_x100
      if barnum > 100
        barnum = 100
      bar = make_bar(barnum, 100)
      label = "vs " + disp[l]
      line = "  " + col[l] + BOLD + lj(label, 12) + RESET
      line = line + WHITE + rj(fmt_x(geo_x100), 7) + RESET + "  " + col[l] + bar + RESET
      line = line + "  " + verdict
      << line
  pi = pi + 1

# headline vs C (count parity wins across the head-to-head set)
cprod = 1
cn = 0
wins = 0
total_h = 0
bi = 0
while bi < benches.size()
  b = benches[bi]
  if section[b] == "h"
    tw = times[b]["w"]
    tc = times[b]["c"]
    if tw != nil && tw > 0 && tc != nil && tc > 0
      total_h = total_h + 1
      cprod = cprod * ((tc * 1000) / tw)
      cn = cn + 1
      if tw * 10 <= tc * 11
        wins = wins + 1
  bi = bi + 1
<< ""
if cn > 0
  cgeo = (inth_root(cprod, cn) / 10).to_i
  msg = ""
  if cgeo >= 95
    msg = "Neck-and-neck with optimized C on general-purpose compute"
  elsif cgeo >= 70
    gap = (10000 / cgeo) - 100
    msg = "Within [gap]% of optimized C on general-purpose compute"
  else
    msg = "Trails optimized C on this set — see the bars"
  << "  [GREEN]▹[RESET] [WHITE][msg][RESET][GREY], matching or beating it on [wins]/[total_h] workloads.[RESET]"
# interpreter blowout line
best_interp = 0
best_interp_lang = ""
pi = 0
while pi < peers.size()
  l = peers[pi]
  if l == "rb" || l == "py"
    if active.include?(l)
      prod = 1
      n = 0
      bi = 0
      while bi < benches.size()
        b = benches[bi]
        tw = times[b]["w"]
        tl = times[b][l]
        if tw != nil && tw > 0 && tl != nil && tl > 0
          prod = prod * ((tl * 100) / tw)
          n = n + 1
        bi = bi + 1
      if n > 0
        g = (inth_root(prod, n) / 100).to_i
        if g > best_interp
          best_interp = g
          best_interp_lang = disp[l]
  pi = pi + 1
if best_interp > 0
  << "  [GREEN]▹[RESET] [WHITE]Up to [best_interp]× faster than [best_interp_lang][RESET][GREY] across the full suite.[RESET]"

<< ""
<< "  [GREY]flags  C clang -O3 -march=native -flto · rustc -O target-cpu=native · go build[RESET]"
<< "  [GREY]       crystal --release · ruby --yjit · python3 · tungsten compile --native[RESET]"
<< "  [GREY]★ fastest   ≠ differs beyond fp tolerance   fp escape/iter counts vary in the last digits[RESET]"
<< ""

# ---- cleanup --------------------------------------------------------------
if builddir != "" && builddir != "/"
  system("rm -rf \"[builddir]\"")
