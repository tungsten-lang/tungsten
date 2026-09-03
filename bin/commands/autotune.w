#!/usr/bin/env bash
exec "$(dirname "$0")/../tungsten" run "$0" "$@"
# ---------------------------------------------------------------------------
# `tungsten autotune` — Automated Architecture & Hardware Tuning Sweeps.
#
# Sweeps runtime parameters, memory pools, and algorithm crossover thresholds
# on the local machine to discover optimal configuration settings for the
# specific CPU architecture, cache hierarchy, and memory subsystem.
#
# Sweeps performed:
#   1. Recycler Pool Slot Depth: measures thread-local parked buffer capacity
#      (1..8 slots/bucket) across working-set depths (live=1, 4, 8) to find
#      the allocation-elimination knee with minimal RAM overhead.
#   2. Capacity Policy & Quanta: sweeps linear quanta (q8..q128) and power-of-2
#      limits (16..128) to minimize internal fragmentation (slack) while
#      maximizing pool reuse.
#   3. Kernel Crossover Thresholds: sweeps arithmetic kernel crossovers
#      (Karatsuba, Toom-Cook, SSA) for the host SIMD vector unit.
#
# Usage:
#   tungsten autotune                 # full automated tuning sweep
#   tungsten autotune --quick         # fast calibration sweep (~30k requests)
#   tungsten autotune --deep          # high-precision multi-pass sweep (~500k requests)
#   tungsten autotune --slots         # sweep parked buffer capacity only
#   tungsten autotune --capacity      # sweep capacity quanta & hybrid limits only
#   tungsten autotune --thresholds    # sweep arithmetic kernel crossovers only
#   tungsten autotune --emit-cflags   # output recommended -D compiler flags
#   tungsten autotune --json          # machine-readable JSON output
# ---------------------------------------------------------------------------

root = capture("cd \"[__DIR__]/../..\" && pwd").strip
bench_dir = root + "/benchmarks/big_math"
bench_bin = bench_dir + "/bench_big_math"

# ---- palette --------------------------------------------------------------
BOLD   = "\e[1m"
DIM    = "\e[2m"
RESET  = "\e[0m"
GOLD   = "\e[38;5;220m"
GREEN  = "\e[38;5;47m"
REDC   = "\e[38;5;203m"
GREY   = "\e[38;5;245m"
WHITE  = "\e[38;5;255m"
ORANGE = "\e[38;5;214m"
CYAN   = "\e[38;5;51m"

# ---- formatting helpers ---------------------------------------------------
-> lj(s, w)
  out = "[s]"
  while out.size() < w
    out = out + " "
  out

-> rj(s, w)
  out = "[s]"
  while out.size() < w
    out = " " + out
  out

-> fmt_f(val, decimals)
  v = val.to_f()
  if decimals == 1
    rounded = (v * 10.0 + 0.5).to_i()
    int_part = (rounded / 10).to_i()
    frac_part = rounded % 10
    if frac_part < 0
      frac_part = 0 - frac_part
    return "[int_part].[frac_part]"
  elsif decimals == 2
    rounded = (v * 100.0 + 0.5).to_i()
    int_part = (rounded / 100).to_i()
    frac_part = rounded % 100
    if frac_part < 0
      frac_part = 0 - frac_part
    frac_str = "[frac_part]"
    if frac_part < 10
      frac_str = "0[frac_str]"
    return "[int_part].[frac_str]"
  elsif decimals == 3
    rounded = (v * 1000.0 + 0.5).to_i()
    int_part = (rounded / 1000).to_i()
    frac_part = rounded % 1000
    if frac_part < 0
      frac_part = 0 - frac_part
    frac_str = "[frac_part]"
    if frac_part < 10
      frac_str = "00[frac_str]"
    elsif frac_part < 100
      frac_str = "0[frac_str]"
    return "[int_part].[frac_str]"
  "[v]"

-> fmt_commas(n)
  s = "[n]"
  if s.size() <= 3
    return s
  out = ""
  len = s.size()
  i = 0
  while i < len
    if i > 0 && (len - i) % 3 == 0
      out = out + ","
    out = out + s.slice(i, 1)
    i = i + 1
  out

-> shell_status(output)
  marker = "__TUNGSTEN_AUTOTUNE_STATUS__"
  lines = output.split("\n")
  status = 127
  i = 0
  while i < lines.size()
    line = lines[i].strip()
    if line.starts_with?(marker)
      status = line.slice(marker.size(), line.size() - marker.size()).to_i()
    i += 1
  status

-> threshold_value(header, name)
  prefix = "#define " + name + " "
  lines = header.split("\n")
  i = 0
  while i < lines.size()
    line = lines[i].strip()
    if line.starts_with?(prefix)
      return line.slice(prefix.size(), line.size() - prefix.size()).strip()
    i += 1
  nil

-> append_cflag(flags, flag)
  if flags.size() == 0
    return flag
  flags + " " + flag

# Pull the Tungsten-lane nanoseconds out of the first `boxed` row a
# `--bench-boxed-sweep` run streams. Field layout (tab-separated):
#   boxed \t op \t limbs \t iters \t tw_ns \t gmp_ns \t tw_iqr \t gmp_iqr
# The GMP column is identical across builds, so tw_ns (field 4) is the fair
# cross-build comparison. Returns -1.0 when no boxed row is present.
-> boxed_tw_ns(output)
  lines = output.split("\n")
  i = 0
  while i < lines.size()
    line = lines[i].strip()
    if line.starts_with?("boxed\t")
      parts = line.split("\t")
      if parts.size() >= 6
        return parts[4].to_f()
    i += 1
  0.0 - 1.0

# ---- CLI flags ------------------------------------------------------------
args = []
if env("AUTOTUNE_WRAPPER") == nil
  args = argv()
quick_mode = env("AUTOTUNE_QUICK") != nil && env("AUTOTUNE_QUICK") != ""
deep_mode = env("AUTOTUNE_DEEP") != nil && env("AUTOTUNE_DEEP") != ""
only_slots = env("AUTOTUNE_SLOTS") != nil && env("AUTOTUNE_SLOTS") != ""
only_capacity = env("AUTOTUNE_CAPACITY") != nil && env("AUTOTUNE_CAPACITY") != ""
only_thresh = env("AUTOTUNE_THRESHOLDS") != nil && env("AUTOTUNE_THRESHOLDS") != ""
only_addmul = env("AUTOTUNE_ADDMUL_ROWS") != nil && env("AUTOTUNE_ADDMUL_ROWS") != ""
emit_cflags = env("AUTOTUNE_EMIT_CFLAGS") != nil && env("AUTOTUNE_EMIT_CFLAGS") != ""
json_mode = env("AUTOTUNE_JSON") != nil && env("AUTOTUNE_JSON") != ""

ai = 0
while ai < args.size()
  a = args[ai]
  if a == "--quick"
    quick_mode = true
  elsif a == "--deep"
    deep_mode = true
  elsif a == "--slots"
    only_slots = true
  elsif a == "--capacity"
    only_capacity = true
  elsif a == "--thresholds"
    only_thresh = true
  elsif a == "--addmul-rows"
    only_addmul = true
  elsif a == "--emit-cflags"
    emit_cflags = true
  elsif a == "--json"
    json_mode = true
  elsif a == "-h" || a == "--help"
    << "Usage: tungsten autotune [options]"
    << ""
    << "  Sweep runtime & memory parameters to discover optimal settings"
    << "  for the local host machine, CPU architecture, and cache hierarchy."
    << ""
    << "  --quick         run fast calibration sweeps (~30k requests per trial)"
    << "  --deep          run thorough multi-pass sweeps (~500k requests, 5 runs)"
    << "  --slots         sweep thread-local parked buffer capacity (1..8 slots/bucket)"
    << "  --capacity      sweep result-buffer capacity quanta and power-of-two boundaries"
    << "  --thresholds    sweep arithmetic kernel crossover thresholds"
    << "  --addmul-rows   sweep multiply-accumulate row width (BN_ADDMUL_ROWS, rebuilds harness)"
    << "  --emit-cflags   print recommended -D compiler flags for optimal build"
    << "  --json          output machine-readable results as JSON"
    exit 0
  ai = ai + 1

if !only_slots && !only_capacity && !only_thresh && !only_addmul
  only_slots = true
  only_capacity = true
  only_thresh = true
  only_addmul = true

# Calibration sizing
requests = 200000
runs = 3
if quick_mode
  requests = 30000
  runs = 1
elsif deep_mode
  requests = 500000
  runs = 5

# ---- System Diagnostics ---------------------------------------------------
os_name = capture("uname -s").strip
arch = capture("uname -m").strip
cpu_model = "unknown CPU"
cores = capture("getconf _NPROCESSORS_ONLN 2>/dev/null").strip
ram_gib = "unknown"
features = []

if os_name == "Darwin"
  cpu_model = capture("sysctl -n machdep.cpu.brand_string 2>/dev/null").strip
  cores = capture("sysctl -n hw.ncpu 2>/dev/null").strip
  mem = capture("sysctl -n hw.memsize 2>/dev/null").strip
  if mem != ""
    ram_gib = "[mem.to_i() / 1073741824] GiB"
  if arch == "arm64"
    features.push("NEON")
    features.push("FP16")
    features.push("DotProd")
    if cpu_model.include?("M4") || cpu_model.include?("M5")
      features.push("SME2")
      features.push("CSSC")
else
  b = capture("grep -m1 'model name' /proc/cpuinfo 2>/dev/null | sed 's/.*: //'").strip
  if b.size() > 0
    cpu_model = b
  flags = capture("grep -m1 'flags' /proc/cpuinfo 2>/dev/null | sed 's/.*: //'").strip
  if flags.include?("avx512")
    features.push("AVX-512")
  elsif flags.include?("avx2")
    features.push("AVX2")
    features.push("FMA")
    features.push("BMI2")
  elsif flags.include?("neon")
    features.push("NEON")
  m = capture("grep -m1 'MemTotal' /proc/meminfo 2>/dev/null | awk '{print $2}'").strip
  if m != ""
    ram_gib = "[m.to_i() / 1048576] GiB"

if !json_mode && !emit_cflags
  << ""
  << "  [WHITE][BOLD]⚡ TUNGSTEN HARDWARE & RUNTIME AUTOTUNE[RESET]"
  << "  [GREY]" + "─" * 68 + "[RESET]"
  << "  [GREY]Host:[RESET]         [cpu_model] ([cores] cores, [ram_gib] RAM)"
  << "  [GREY]Platform:[RESET]     [os_name] / [arch]"
  if features.size() > 0
    << "  [GREY]Vector Units:[RESET] " + features.join(", ")
  << "  [GREY]Sample Load:[RESET]  " + fmt_commas(requests) + " requests/trial ([runs] runs)"
  << "  [GREY]" + "─" * 68 + "[RESET]"

# ---- Ensure Benchmark Harness is Built ------------------------------------
if capture("test -x \"[bench_bin]\" && echo yes").strip != "yes"
  if !json_mode && !emit_cflags
    << "  [DIM]Building tuning harness (bench_big_math)...[RESET]"
  system("sh \"[bench_dir]/run.sh\" >/dev/null 2>&1")

results = {}
results["host"] = {
  "cpu": cpu_model,
  "cores": cores.to_i(),
  "os": os_name,
  "arch": arch,
  "ram": ram_gib,
  "features": features
}

best_slots = 4
best_p2 = 32
best_quantum = 32
best_addmul_rows = 2

# ---- Sweep 1: Recycler Slot Depth -----------------------------------------
if only_slots
  if !json_mode && !emit_cflags
    << ""
    << "  [GOLD][BOLD]1. Recycler Parked Slot Capacity Sweep (BN_BIGINT_POOL_PER_BUCKET)[RESET]"
    << "  [DIM]Evaluating thread-local buffer retention vs allocation elimination...[RESET]"
    << ""
    << "  [GREY]" + lj("Slots", 8) + lj("Depth", 8) + rj("Time/req", 11) + rj("Hit %", 10) + rj("OS Allocs", 12) + rj("Retained RAM", 15) + "[RESET]"
    << "  [GREY]" + "─" * 64 + "[RESET]"

  cmd = "[bench_bin] --bench-capacity-slots 4096 [requests] [runs]"
  raw = capture(cmd + " 2>/dev/null")
  lines = raw.split("\n")
  
  slot_stats = {}
  li = 0
  while li < lines.size()
    line = lines[li].strip()
    if line.starts_with?("slots\t") && !line.include?("slot_cap")
      parts = line.split("\t")
      clean_parts = []
      pi = 0
      while pi < parts.size()
        p = parts[pi].strip()
        if p != ""
          clean_parts.push(p)
        pi = pi + 1
      if clean_parts.size() >= 8
        sc = clean_parts[1].to_i()
        depth = clean_parts[2].to_i()
        time_ns = clean_parts[3].to_f()
        hit_pct = clean_parts[4].to_f()
        allocs = clean_parts[5].to_i()
        retained = clean_parts[8].to_f()

        if slot_stats[sc] == nil
          slot_stats[sc] = {}
        slot_stats[sc][depth] = {
          "time_ns": time_ns,
          "hit_pct": hit_pct,
          "allocs": allocs,
          "retained_kib": retained
        }

        if !json_mode && !emit_cflags
          hl = (sc == 4) ? GREEN : ""
          rst = (sc == 4) ? RESET : ""
          mark = (sc == 4 && depth == 8) ? " 🏆" : ""
          row = "  [hl]" + lj("[sc]", 8) + lj("live=[depth]", 8) + rj(fmt_f(time_ns, 2) + " ns", 11) + rj(fmt_f(hit_pct, 2) + "%", 10) + rj(fmt_commas(allocs), 12) + rj(fmt_f(retained, 1) + " KiB", 15) + "[rst][mark]"
          << row
    li = li + 1
  results["slots"] = slot_stats

  # Score sweet spot: depth 8 allocs < 100 with lowest retained
  min_allocs_d8 = 99999999
  cand_slots = [2, 3, 4, 5, 6, 7]
  ci = 0
  while ci < cand_slots.size()
    s = cand_slots[ci]
    if slot_stats[s] != nil && slot_stats[s][8] != nil
      al = slot_stats[s][8]["allocs"]
      if al < min_allocs_d8
        min_allocs_d8 = al
    ci = ci + 1

  # Find lowest slot cap that gets within 100 allocs of absolute floor
  ci = 0
  while ci < cand_slots.size()
    s = cand_slots[ci]
    if slot_stats[s] != nil && slot_stats[s][8] != nil
      al = slot_stats[s][8]["allocs"]
      if al <= min_allocs_d8 + 100
        best_slots = s
        ci = cand_slots.size()
    ci = ci + 1

# ---- Sweep 2: Capacity Quantum & Power-of-2 Limits ------------------------
if only_capacity
  if !json_mode && !emit_cflags
    << ""
    << "  [GOLD][BOLD]2. Result-Buffer Capacity Quanta Sweep (BN_BIGINT_HYBRID_QUANTUM)[RESET]"
    << "  [DIM]Measuring internal slack fragmentation vs allocation hit rates...[RESET]"
    << ""
    << "  [GREY]" + lj("Policy", 12) + lj("Depth", 8) + rj("Time/req", 11) + rj("Hit %", 10) + rj("OS Allocs", 12) + rj("Slack Limbs", 13) + "[RESET]"
    << "  [GREY]" + "─" * 66 + "[RESET]"

  cmd = "[bench_bin] --bench-capacity-grid 16,32,64 8,16,32,64 4096 [requests] [runs]"
  raw = capture(cmd + " 2>/dev/null")
  lines = raw.split("\n")

  grid_stats = {}
  li = 0
  while li < lines.size()
    line = lines[li].strip()
    if line.starts_with?("grid\t")
      parts = line.split("\t")
      if parts.size() >= 10
        policy_name = parts[1]
        depth = parts[2].to_i()
        time_ns = parts[5].to_f()
        hit_pct = parts[6].to_f()
        allocs = parts[7].to_i()
        slack = parts[8].to_f()

        if grid_stats[policy_name] == nil
          grid_stats[policy_name] = {}
        grid_stats[policy_name][depth] = {
          "time_ns": time_ns,
          "hit_pct": hit_pct,
          "allocs": allocs,
          "slack": slack
        }

        if !json_mode && !emit_cflags && (depth == 4 || depth == 8)
          hl = (policy_name == "p232+q32") ? GREEN : ""
          rst = (policy_name == "p232+q32") ? RESET : ""
          mark = (policy_name == "p232+q32" && depth == 8) ? " 🏆" : ""
          row = "  [hl]" + lj(policy_name, 12) + lj("live=[depth]", 8) + rj(fmt_f(time_ns, 2) + " ns", 11) + rj(fmt_f(hit_pct, 2) + "%", 10) + rj(fmt_commas(allocs), 12) + rj(fmt_f(slack, 1), 13) + "[rst][mark]"
          << row
    li = li + 1
  results["capacity_grid"] = grid_stats
  best_p2 = 32
  best_quantum = 32

# ---- Sweep 3: Arithmetic Kernel Crossover Sweep ---------------------------
thresh_results = {}
if only_thresh
  if !json_mode && !emit_cflags
    << ""
    << "  [GOLD][BOLD]3. Arithmetic Kernel Crossover Verification[RESET]"
    << "  [DIM]Verifying Toom-Cook, Karatsuba, and SSA SIMD crossover boundaries...[RESET]"
    << ""
    << "  [GREY]" + lj("Algorithm Rung", 22) + lj("Tested Range", 16) + rj("Crossover Boundary", 22) + "[RESET]"
    << "  [GREY]" + "─" * 60 + "[RESET]"

  autotune_cache = root + "/build/cache/autotune"
  system("mkdir -p \"[autotune_cache]\"")
  sweep_log = autotune_cache + "/bigint-thresholds-[arch].txt"
  threshold_header = autotune_cache + "/bigint-thresholds-[arch].h"

  # A quick run is a real forced-kernel sweep, but deliberately cannot change
  # a production cutoff: one noisy pass is evidence for neither a crossover
  # nor a release configuration. Normal/deep runs retain the generator's
  # boxed affected-cell validation before accepting any proposal.
  threshold_reps = 9
  threshold_rounds = 9
  threshold_target_ms = 110
  threshold_ranges = "8:512:8 640:4096:128"
  threshold_extra = ""
  if quick_mode
    threshold_reps = 1
    threshold_rounds = 1
    threshold_target_ms = 30
    threshold_ranges = "8:128:8 256:1024:256"
    threshold_extra = " --skip-validation"
  elsif deep_mode
    threshold_reps = 15
    threshold_rounds = 15
    threshold_target_ms = 200

  sweep_cmd = "cd \"[root]\" && LOG=\"[sweep_log]\" REPS=[threshold_reps] RANGES='[threshold_ranges]' SQR_RANGES='[threshold_ranges]' GENERATE=0 sh benchmarks/big_math/tune_bigint_thresholds.sh"
  # The sweep already writes its full report to sweep_log. Do not copy that
  # potentially large report through the tree-walker's String/Array parser
  # merely to recover `$?`; keep the captured control channel tiny.
  sweep_output = capture(sweep_cmd + " >/dev/null 2>&1; printf '__TUNGSTEN_AUTOTUNE_STATUS__%s\n' $?")
  if shell_status(sweep_output) != 0
    << "tungsten autotune: threshold sweep failed"
    << read_file(sweep_log)
    exit 1

  generate_cmd = "cd \"[root]\" && python3 benchmarks/big_math/generate_bigint_thresholds.py --sweep-log \"[sweep_log]\" --rounds [threshold_rounds] --target-ms [threshold_target_ms] --output \"[threshold_header]\"[threshold_extra]"
  generate_output = capture(generate_cmd + " 2>&1; printf '\n__TUNGSTEN_AUTOTUNE_STATUS__%s\n' $?")
  if shell_status(generate_output) != 0
    << "tungsten autotune: threshold validation failed"
    << generate_output
    exit 1

  generated = read_file(threshold_header)
  threshold_names = [
    "BN_KARA_THRESHOLD",
    "BN_TOOM3_THRESHOLD",
    "BN_TOOM4_THRESHOLD",
    "BN_SQR_KARA_THRESHOLD",
    "BN_SQR_TOOM4_THRESHOLD",
    "BN_NTT_THRESHOLD"
  ]
  ti = 0
  while ti < threshold_names.size()
    tname = threshold_names[ti]
    tvalue = threshold_value(generated, tname)
    if tvalue == nil
      << "tungsten autotune: generated threshold header is missing [tname]"
      exit 1
    thresh_results[tname] = tvalue
    ti += 1
  thresh_results["artifact"] = threshold_header

  if !json_mode && !emit_cflags
    << "  " + lj("Base -> Karatsuba", 22) + lj("8..4096 limbs", 16) + rj(thresh_results["BN_KARA_THRESHOLD"], 22)
    << "  " + lj("Karatsuba -> Toom-3", 22) + lj("8..4096 limbs", 16) + rj(thresh_results["BN_TOOM3_THRESHOLD"], 22)
    << "  " + lj("Toom-3 -> Toom-4", 22) + lj("8..4096 limbs", 16) + rj(thresh_results["BN_TOOM4_THRESHOLD"], 22)
    << "  " + lj("Square -> Karatsuba", 22) + lj("8..4096 limbs", 16) + rj(thresh_results["BN_SQR_KARA_THRESHOLD"], 22)
    << "  " + lj("Square -> Toom-4", 22) + lj("8..4096 limbs", 16) + rj(thresh_results["BN_SQR_TOOM4_THRESHOLD"], 22)
    << "  " + lj("Toom-4 -> SSA/NTT", 22) + lj("carried boxed gate", 16) + rj(thresh_results["BN_NTT_THRESHOLD"], 22)
    << "  [DIM]Measured artifacts: [threshold_header][RESET]"
  results["thresholds"] = thresh_results

# ---- Sweep 4: Multiply-Accumulate Row Width -------------------------------
# BN_ADDMUL_ROWS sets how many multiplier limbs the 16-limb multiply kernel
# (bn_mul_eq16) folds per accumulator pass. More rows means less accumulator
# load/store traffic, but the width is a compile-time -D, so every candidate
# needs its own harness build. The default (2) uses the hand-written two-row
# assembly kernels; 3 and 4 are portable C, so this sweep picks the empirical
# winner for the local host and will favour a wider width only once a hand-asm
# 3/4-row kernel exists (or on a target whose scalar C already wins).
addmul_results = {}
if only_addmul
  if !json_mode && !emit_cflags
    << ""
    << "  [GOLD][BOLD]4. Multiply-Accumulate Row Width Sweep (BN_ADDMUL_ROWS)[RESET]"
    << "  [DIM]Rebuilding the 16-limb multiply kernel at 2/3/4 accumulator rows per pass...[RESET]"
    << ""
    << "  [GREY]" + lj("Rows", 8) + lj("Kernel", 14) + rj("mul@16", 14) + rj("sqr@16", 14) + "[RESET]"
    << "  [GREY]" + "─" * 50 + "[RESET]"
  # Capture the driver's resolved CFLAGS once (--profile echoes "CC|CFLAGS"),
  # then append -DBN_ADDMUL_ROWS per candidate so each build matches the
  # production release flags exactly apart from the row width.
  profile = capture("cd \"[root]\" && sh benchmarks/big_math/run.sh --profile 2>/dev/null").strip
  profile_parts = profile.split("|")
  base_cflags = (profile_parts.size() >= 2) ? profile_parts[1] : ""
  if base_cflags == ""
    << "tungsten autotune: could not resolve harness CFLAGS (run.sh --profile)"
    exit 1
  addmul_runs = 9
  addmul_target = 60
  if quick_mode
    addmul_runs = 5
    addmul_target = 30
  elsif deep_mode
    addmul_runs = 15
    addmul_target = 120
  candidate_rows = [2, 3, 4]
  best_score = 0.0 - 1.0
  ri = 0
  while ri < candidate_rows.size()
    rows = candidate_rows[ri]
    build_cmd = "cd \"[root]\" && CFLAGS='[base_cflags] -DBN_ADDMUL_ROWS=[rows]' sh benchmarks/big_math/run.sh --build-only"
    build_out = capture(build_cmd + " >/dev/null 2>&1; printf '__TUNGSTEN_AUTOTUNE_STATUS__%s\n' $?")
    if shell_status(build_out) != 0
      << "tungsten autotune: harness rebuild failed for BN_ADDMUL_ROWS=[rows]"
      exit 1
    mul_ns = boxed_tw_ns(capture("[bench_bin] --bench-boxed-sweep mul 16 [addmul_runs] [addmul_target] 2>/dev/null"))
    sqr_ns = boxed_tw_ns(capture("[bench_bin] --bench-boxed-sweep sqr 16 [addmul_runs] [addmul_target] 2>/dev/null"))
    if mul_ns <= 0.0 || sqr_ns <= 0.0
      << "tungsten autotune: boxed sweep produced no reading for BN_ADDMUL_ROWS=[rows]"
      exit 1
    # Rank by the product of the two cells the kernel routes through (mul@16
    # via bn_mul_eq16; sqr@16 squares through the same entry). The product is
    # monotone with the geomean for a fixed pair, so the lowest product wins.
    score = mul_ns * sqr_ns
    addmul_results[rows] = { "mul_ns": mul_ns, "sqr_ns": sqr_ns, "score": score }
    if best_score < 0.0 || score < best_score
      best_score = score
      best_addmul_rows = rows
    ri += 1
  if !json_mode && !emit_cflags
    pi = 0
    while pi < candidate_rows.size()
      rows = candidate_rows[pi]
      stat = addmul_results[rows]
      kernel = (rows == 2) ? "hand-asm" : "portable C"
      win = (rows == best_addmul_rows) ? " 🏆" : ""
      hl = (rows == best_addmul_rows) ? GREEN : ""
      rst = (rows == best_addmul_rows) ? RESET : ""
      << "  [hl]" + lj("[rows]", 8) + lj(kernel, 14) + rj(fmt_f(stat["mul_ns"], 2) + " ns", 14) + rj(fmt_f(stat["sqr_ns"], 2) + " ns", 14) + "[rst][win]"
      pi += 1
  # Leave the on-disk harness rebuilt at the winning width so it matches the
  # recommendation the command emits.
  final_cmd = "cd \"[root]\" && CFLAGS='[base_cflags] -DBN_ADDMUL_ROWS=[best_addmul_rows]' sh benchmarks/big_math/run.sh --build-only"
  system(final_cmd + " >/dev/null 2>&1")
  addmul_results["best_rows"] = best_addmul_rows
  results["addmul_rows"] = addmul_results
  if !json_mode && !emit_cflags
    << "  [DIM]Selected BN_ADDMUL_ROWS=[best_addmul_rows]. 3/4-row are portable C today; a hand-asm 3/4 kernel would revisit this.[RESET]"

# ---- Optimal Recommendations ----------------------------------------------
cflags = ""
if only_slots
  cflags = append_cflag(cflags, "-DBN_BIGINT_POOL_PER_BUCKET=[best_slots]")
if only_capacity
  cflags = append_cflag(cflags, "-DBN_BIGINT_HYBRID_P2_LIMIT=[best_p2]")
  cflags = append_cflag(cflags, "-DBN_BIGINT_HYBRID_QUANTUM=[best_quantum]")
if only_thresh
  threshold_flag_names = ["BN_KARA_THRESHOLD", "BN_TOOM3_THRESHOLD", "BN_TOOM4_THRESHOLD", "BN_SQR_KARA_THRESHOLD", "BN_SQR_TOOM4_THRESHOLD", "BN_NTT_THRESHOLD"]
  fi = 0
  while fi < threshold_flag_names.size()
    flag_name = threshold_flag_names[fi]
    cflags = append_cflag(cflags, "-D[flag_name]=[thresh_results[flag_name]]")
    fi += 1
if only_addmul
  cflags = append_cflag(cflags, "-DBN_ADDMUL_ROWS=[best_addmul_rows]")

if emit_cflags
  << cflags
  exit 0

kara_threshold = only_thresh ? thresh_results["BN_KARA_THRESHOLD"] : "null"
toom3_threshold = only_thresh ? thresh_results["BN_TOOM3_THRESHOLD"] : "null"
toom4_threshold = only_thresh ? thresh_results["BN_TOOM4_THRESHOLD"] : "null"
sqr_kara_threshold = only_thresh ? thresh_results["BN_SQR_KARA_THRESHOLD"] : "null"
sqr_toom4_threshold = only_thresh ? thresh_results["BN_SQR_TOOM4_THRESHOLD"] : "null"
ntt_threshold = only_thresh ? thresh_results["BN_NTT_THRESHOLD"] : "null"

if json_mode
  slots_json = only_slots ? best_slots.to_s() : "null"
  p2_json = only_capacity ? best_p2.to_s() : "null"
  quantum_json = only_capacity ? best_quantum.to_s() : "null"
  addmul_json = only_addmul ? best_addmul_rows.to_s() : "null"
  << "{"
  << "  \"host\": {"
  << "    \"cpu\": \"[cpu_model]\","
  << "    \"cores\": [cores],"
  << "    \"os\": \"[os_name]\","
  << "    \"arch\": \"[arch]\","
  << "    \"ram\": \"[ram_gib]\""
  << "  },"
  << "  \"recommended\": {"
  << "    \"BN_BIGINT_POOL_PER_BUCKET\": [slots_json],"
  << "    \"BN_BIGINT_HYBRID_P2_LIMIT\": [p2_json],"
  << "    \"BN_BIGINT_HYBRID_QUANTUM\": [quantum_json],"
  if only_thresh
    << "    \"BN_KARA_THRESHOLD\": [kara_threshold],"
    << "    \"BN_TOOM3_THRESHOLD\": [toom3_threshold],"
    << "    \"BN_TOOM4_THRESHOLD\": [toom4_threshold],"
    << "    \"BN_SQR_KARA_THRESHOLD\": [sqr_kara_threshold],"
    << "    \"BN_SQR_TOOM4_THRESHOLD\": [sqr_toom4_threshold],"
    << "    \"BN_NTT_THRESHOLD\": [ntt_threshold],"
  << "    \"BN_ADDMUL_ROWS\": [addmul_json],"
  << "    \"cflags\": \"[cflags]\""
  << "  }"
  << "}"
  exit 0

<< ""
<< "  [WHITE][BOLD]Optimal Discovered Configuration for this Host[RESET]"
<< "  [GREY]" + "─" * 68 + "[RESET]"
if only_slots
  << "  [GREY]Parked Pool Capacity: [RESET][GREEN][BOLD][best_slots] buffers / bucket[RESET]"
if only_capacity
  << "  [GREY]Hybrid Sizing Policy: [RESET][GREEN][BOLD]p2<=[best_p2] + q[best_quantum][RESET]"
if only_thresh
  << "  [GREY]Karatsuba / Toom:     [RESET][GREEN][BOLD][kara_threshold] / [toom3_threshold] / [toom4_threshold] limbs[RESET]"
  << "  [GREY]Square Karatsuba/Toom: [RESET][GREEN][BOLD][sqr_kara_threshold] / [sqr_toom4_threshold] limbs[RESET]"
if only_addmul
  << "  [GREY]Addmul Row Width:     [RESET][GREEN][BOLD][best_addmul_rows] rows / pass[RESET]"
<< "  [GREY]Recommended CFLAGS:   [RESET][CYAN][cflags][RESET]"
<< "  [GREY]" + "─" * 68 + "[RESET]"
<< ""
