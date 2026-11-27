# cinder/opt_config — Multi-Level Optimizer Configuration, Pass Toggles & Magic Division Math.
#
# Supports standard optimization levels (-O0, -O1, -O2, -O3), fast-math (--fast / -ffast-math),
# debug policy (--debug / --no-debug), frame-pointer control, and fine-grained per-pass toggles
# (-f<pass> / -fno-<pass>, --opt-passes=..., --print-passes).
#
# Also provides exact Granlund & Montgomery (PLDI 1994) 64-bit unsigned constant division
# magic-multiplier synthesis shared by both the WIRE optimizer and AOT LL optimizer.

-> cinder_canon_pass_name(raw)
  s = raw.strip().downcase().gsub("_", "-")
  return "inline"          if s == "inline" || s == "inline-functions" || s == "finline"
  return "always-inline"   if s == "always-inline" || s == "alwaysinline"
  return "const-fold"      if s == "const-fold" || s == "constprop" || s == "sccp"
  return "sroa"            if s == "sroa" || s == "mem2reg" || s == "slot-sroa"
  return "jump-threading"  if s == "jump-threading" || s == "simplify-cfg" || s == "cfg"
  return "gvn"             if s == "gvn" || s == "cse" || s == "gvn-cse"
  return "licm"            if s == "licm" || s == "loop-invariant-code-motion"
  return "strength-reduce" if s == "strength-reduce" || s == "strength-reduction" || s == "div-magic"
  return "carry-chains"    if s == "carry-chains" || s == "carry"
  return "simd"            if s == "simd" || s == "vectorize" || s == "tree-vectorize" || s == "loop-vectorize"
  return "unroll-loops"    if s == "unroll-loops" || s == "unroll"
  return "dce"             if s == "dce" || s == "adce" || s == "dead-code-elim"
  return "peephole"        if s == "peephole" || s == "instcombine"
  return "reg-promote"     if s == "reg-promote" || s == "regalloc"
  return "leaf-frame-elim" if s == "leaf-frame-elim" || s == "omit-leaf-frame-pointer"
  return "lto-internalize" if s == "lto-internalize" || s == "internalize"
  return "ipa-sccp"        if s == "ipa-sccp" || s == "ipsccp" || s == "ipa-constprop"
  return "lto-dce"         if s == "lto-dce" || s == "lto-global-dce" || s == "global-dce"
  ""

CINDER_ALL_PASSES = [
  "always-inline",
  "inline",
  "lto-internalize",
  "ipa-sccp",
  "const-fold",
  "sroa",
  "jump-threading",
  "gvn",
  "licm",
  "strength-reduce",
  "carry-chains",
  "simd",
  "unroll-loops",
  "dce",
  "lto-dce",
  "peephole",
  "reg-promote",
  "leaf-frame-elim"
]

+ CinderOptConfig
  rw :opt_level, :fast_math, :strict_math, :debug, :frame_pointers, :print_passes, :lto_mode
  rw :overrides, :explicit_passes, :pass_stats, :pass_agg, :pass_agg_order

  -> new(level = 2)
    @opt_level = level
    @fast_math = false
    @strict_math = false
    @debug = false
    @frame_pointers = false
    @print_passes = false
    @lto_mode = :none
    @overrides = {}
    @explicit_passes = nil
    @pass_stats = []
    @pass_agg = {}
    @pass_agg_order = []

  -> lto_enabled?
    @lto_mode != :none

  -> clone
    cp = CinderOptConfig.new(@opt_level)
    cp.fast_math = @fast_math
    cp.strict_math = @strict_math
    cp.debug = @debug
    cp.frame_pointers = @frame_pointers
    cp.print_passes = @print_passes
    cp.lto_mode = @lto_mode
    @overrides.keys.each ->(k)
      cp.overrides[k] = @overrides[k]
    if @explicit_passes != nil
      ep = {}
      @explicit_passes.keys.each ->(k)
        ep[k] = @explicit_passes[k]
      cp.explicit_passes = ep
    cp

  -> set_level(lvl)
    @opt_level = lvl < 0 ? 0 : (lvl > 3 ? 3 : lvl)
    self

  -> enable_pass(name)
    cn = cinder_canon_pass_name(name)
    return false if cn == ""
    @overrides[cn] = true
    @explicit_passes[cn] = true if @explicit_passes != nil
    true

  -> disable_pass(name)
    cn = cinder_canon_pass_name(name)
    return false if cn == ""
    @overrides[cn] = false
    @explicit_passes[cn] = false if @explicit_passes != nil
    true

  -> default_pass_enabled?(cn)
    return true if cn == "always-inline"
    return false if @opt_level <= 0
    # -O1 defaults: fast local cleanups, tiny inlining, straight-line carry chains, peepholes & reg-promote
    if @opt_level == 1
      return true if cn == "inline" || cn == "const-fold" || cn == "sroa" || cn == "jump-threading"
      return true if cn == "strength-reduce" || cn == "carry-chains" || cn == "dce"
      return true if cn == "lto-internalize" || cn == "ipa-sccp" || cn == "lto-dce"
      return true if cn == "peephole" || cn == "reg-promote"
      return (!@debug && !@frame_pointers) if cn == "leaf-frame-elim"
      return false
    # -O2 defaults: full second-pass optimizer (inlining, GVN, LICM, SIMD, magic div, carry loops)
    if @opt_level == 2
      return false if cn == "unroll-loops"
      return (!@debug && !@frame_pointers) if cn == "leaf-frame-elim"
      return true
    # -O3 defaults: all passes including aggressive inlining and loop unrolling
    return (!@debug && !@frame_pointers) if cn == "leaf-frame-elim"
    true

  -> pass_enabled?(name)
    cn = cinder_canon_pass_name(name)
    return false if cn == ""
    if @explicit_passes != nil
      return true if cn == "always-inline" && @overrides["always-inline"] != false
      return @explicit_passes[cn] == true
    ov = @overrides[cn]
    return ov if ov != nil
    default_pass_enabled?(cn)

  # Cost threshold (in instruction-equivalents) for heuristic function inlining
  -> inline_threshold
    return 0 if !pass_enabled?("inline")
    return 15  if @opt_level == 1
    return 320 if @opt_level >= 3
    90

  # Parse a single CLI flag into this config. Returns true if recognized, false otherwise.
  -> parse_flag(arg)
    if arg == "-O0"
      set_level(0)
      return true
    if arg == "-O1"
      set_level(1)
      return true
    if arg == "-O2" || arg == "-O"
      set_level(2)
      return true
    if arg == "-O3"
      set_level(3)
      return true
    if arg == "-Ofast"
      set_level(3)
      @fast_math = true
      @strict_math = false
      return true
    if arg == "--fast" || arg == "-fast" || arg == "-ffast-math"
      @fast_math = true
      @strict_math = false
      return true
    if arg == "-fno-fast-math"
      @fast_math = false
      return true
    if arg == "--strict-math"
      @strict_math = true
      @fast_math = false
      return true
    if arg == "--debug" || arg == "-g"
      @debug = true
      @frame_pointers = true
      return true
    if arg == "--no-debug"
      @debug = false
      return true
    if arg == "--frame-pointers" || arg == "-fno-omit-frame-pointer"
      @frame_pointers = true
      return true
    if arg == "--no-frame-pointers" || arg == "-fomit-frame-pointer"
      @frame_pointers = false
      return true
    if arg == "--print-passes"
      @print_passes = true
      return true
    if arg == "--lto" || arg == "-flto" || arg == "-flto=thin"
      @lto_mode = :thin
      return true
    if arg == "--full-lto" || arg == "-flto=full"
      @lto_mode = :full
      return true
    if arg == "--no-lto" || arg == "-fno-lto"
      @lto_mode = :none
      return true
    if arg.starts_with?("--opt-passes=")
      spec = arg.slice(13, arg.size() - 13).strip()
      @explicit_passes = {}
      if spec != "" && spec != "none"
        parts = spec.split(",")
        pi = 0
        while pi < parts.size()
          cn = cinder_canon_pass_name(parts[pi])
          return false if cn == ""
          @explicit_passes[cn] = true
          pi += 1
      return true
    if arg.starts_with?("-fno-")
      return disable_pass(arg.slice(5, arg.size() - 5))
    if arg.starts_with?("-f") && arg.size() > 2
      return enable_pass(arg.slice(2, arg.size() - 2))
    false

  -> apply_arg(arg)
    parse_flag(arg)

  -> record_stat(pass_name, before_insts, after_insts, elapsed_us)
    if @pass_stats.size() < 64
      @pass_stats.push([pass_name, before_insts, after_insts, elapsed_us])
    ag = @pass_agg[pass_name]
    if ag == nil
      @pass_agg[pass_name] = [1, before_insts, after_insts, elapsed_us]
      @pass_agg_order.push(pass_name)
    else
      ag[0] = ag[0] + 1
      ag[1] = ag[1] + before_insts
      ag[2] = ag[2] + after_insts
      ag[3] = ag[3] + elapsed_us
    nil

  -> enabled_pass_list
    out = []
    i = 0
    while i < CINDER_ALL_PASSES.size()
      nm = CINDER_ALL_PASSES[i]
      out.push(nm) if pass_enabled?(nm)
      i += 1
    out

  -> summary_line
    fp_s = @fast_math ? "fast" : (@strict_math ? "strict" : "precise")
    dbg_s = @debug ? "debug" : "no-debug"
    lto_s = @lto_mode == :full ? " lto=full" : (@lto_mode == :thin ? " lto=thin" : "")
    "cinder opt: -O" + @opt_level.to_s() + " math=" + fp_s + " " + dbg_s + lto_s + " passes=\[" + enabled_pass_list().join(",") + "\]"

  -> summary
    summary_line()

  -> print_report(target_label = "")
    hdr = summary_line()
    hdr = hdr + " (" + target_label + ")" if target_label != ""
    ccall("w_eputs", hdr)
    ai = 0
    while ai < @pass_agg_order.size()
      pnm = @pass_agg_order[ai]
      ag = @pass_agg[pnm]
      delta = ag[2] - ag[1]
      d_str = delta >= 0 ? ("+" + delta.to_s()) : delta.to_s()
      ccall("w_eputs", "  pass " + pnm + " (n=" + ag[0].to_s() + "): " + ag[1].to_s() + " -> " + ag[2].to_s() + " insts (" + d_str + ") in " + (ag[3] / 1000).to_s() + " ms (" + ag[3].to_s() + " us)")
      ai += 1
    nil

  -> to_cli_args
    parts = ["-O" + @opt_level.to_s()]
    parts.push("--fast") if @fast_math
    parts.push("--strict-math") if @strict_math
    parts.push(@debug ? "--debug" : "--no-debug")
    parts.push("--frame-pointers") if @frame_pointers && !@debug
    parts.push("--full-lto") if @lto_mode == :full
    parts.push("--lto") if @lto_mode == :thin
    parts.push("--print-passes") if @print_passes
    if @explicit_passes != nil
      ep = []
      CINDER_ALL_PASSES.each ->(nm)
        ep.push(nm) if @explicit_passes[nm] == true
      parts.push("--opt-passes=" + (ep.size() == 0 ? "none" : ep.join(",")))
    @overrides.keys.each ->(k)
      parts.push(@overrides[k] ? ("-f" + k) : ("-fno-" + k))
    parts

-> cinder_opt_for_tier(tier)
  tier >= 2 ? CinderOptConfig.new(2) : CinderOptConfig.new(0)

-> cinder_opt_from_env(default_level = 2)
  cfg = CinderOptConfig.new(default_level)
  raw = env("CINDER_OPT_FLAGS")
  if raw != nil && raw != ""
    toks = raw.split(" ")
    i = 0
    while i < toks.size()
      t = toks[i].strip()
      cfg.parse_flag(t) if t != ""
      i += 1
  cfg

# Granlund & Montgomery (PLDI 1994, Fig. 4.1 / Thm. 4.2) 64-bit unsigned division by constant!
# Given raw 64-bit signed representation `d_raw` of unsigned divisor `d_u`:
#   Returns `nil` if `d_u <= 1`, else:
#   - `[:shr, 0, k, 0]`               for `d_u == 2^k` (`q = x >>u k`)
#   - `[:mulhi_shr, m_i64, sh, 0]`    for 64-bit magic `m < 2^64` (`q = mulhi_u64(x, m_i64) >>u sh`)
#   - `[:mulhi_add_shr, m_i64, 1, s]` for 65-bit overflow magic (`t = mulhi_u64(x, m_i64); q = (t + ((x - t) >>u 1)) >>u s`)
-> cinder_udiv_magic_u64(d_raw)
  two64 = (1 ## int) << 64
  du = d_raw < 0 ? ((d_raw ## int) + two64) : (d_raw ## int)
  return nil if du <= 1

  # 1. Exact power of two: `x / 2^k == x >>u k`
  if (du & (du - 1)) == 0
    k = 0
    v = du
    while v > 1
      v = v >> 1
      k += 1
    return [:shr, 0, k, 0]

  # 2. Compute `l = ceil(log2(du))` (`1 <= l <= 64`, `2^(l-1) < du < 2^l`)
  l = 1
  while l < 64 && (((1 ## int) << l) < du)
    l += 1

  n_max = two64 - 1
  q1_max = two64 / du
  q_nmax = n_max / du
  two63 = (1 ## int) << 63

  # 3. Check 64-bit no-add magic at `p = l - 1` then `p = l`:
  #    Exact iff `m < 2^64`, `q1_max * (m * du - 2^(64 + p)) < m`, and `(m * n_max) >> (64 + p) == n_max / du`.
  p = l - 1
  while p <= l
    pow_np = (1 ## int) << (64 + p)
    m = (pow_np + du - 1) / du
    e = m * du - pow_np
    if m < two64 && (q1_max * e) < m && ((m * n_max) >> (64 + p)) == q_nmax
      m_i64 = (m >= two63 ? (m - two64) : m) ## i64
      return [:mulhi_shr, m_i64, p, 0]
    p += 1

  # 4. 65-bit add-overflow magic (`2^64 <= m < 2^65`, e.g. `du = 7`):
  pow_nl = (1 ## int) << (64 + l)
  m_full = (pow_nl + du - 1) / du
  m_low = m_full - two64
  m_i64 = (m_low >= two63 ? (m_low - two64) : m_low) ## i64
  [:mulhi_add_shr, m_i64, 1, l - 1]
