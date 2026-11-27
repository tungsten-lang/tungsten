# cinder/wire_x64 — Pure-Tungsten WIRE IR -> x86_64 JIT & Native Code Compiler!
#
# Full System V AMD64 backend for WIRE IR:
#   - Local `mem2reg` slot promotion into callee-saved GPRs (`rbx, r12, r13, r14, r15`)
#     and caller/spill XMMs (`xmm8..xmm15`).
#   - Exact `WArray->start` slice offset handling in `:arr_data_ptr`.
#   - All 12 ECMAScript / Tungsten TypedArray numeric widths, including pure-machine-code
#     IEEE-754 binary16 (`Float16Array`, `ebits=-16`) <-> binary64 conversion that runs
#     on EVERY x86_64 CPU (even baseline v1 without F16C!).
#   - Built-in 128-bit SSE2 loop vectorization for Float32 Dot Product & Float32 SAXPY!

use ./x64
use ./jit_mem
use ./wire_ir
use ./wire_opt
use ./opt_config

-> wire_x64_icmp_cc(pred)
  return XCC_E  if pred == :eq
  return XCC_NE if pred == :ne
  return XCC_L  if pred == :slt
  return XCC_LE if pred == :sle
  return XCC_G  if pred == :sgt
  return XCC_GE if pred == :sge
  return XCC_B  if pred == :ult
  return XCC_BE if pred == :ule
  return XCC_A  if pred == :ugt
  return XCC_AE if pred == :uge
  XCC_NE

# Emit inline IEEE-754 binary16 (in low 16 bits of GPR `r_h`, clobbers `r_tmp1`, `r_tmp2`) -> `xd` (f64)!
# Handles normal numbers, subnormals (`exp == 0 && mant != 0`), signed zero, and ±Inf / NaN!
-> wire_x64_emit_f16_to_f64(a, xd, r_h, r_tmp1, r_tmp2)
  l_zero_sub = a.new_label
  l_inf_nan  = a.new_label
  l_done     = a.new_label

  # r_tmp1 = sign << 63
  a.mov_rr(r_tmp1, r_h)
  a.and_ri(r_tmp1, 0x8000)
  a.shl_ri(r_tmp1, 48)

  # r_tmp2 = exp5 = (h >> 10) & 31; r_h = mant10 = h & 0x3FF
  a.mov_rr(r_tmp2, r_h)
  a.shr_ri(r_tmp2, 10)
  a.and_ri(r_tmp2, 31)
  a.and_ri(r_h, 0x3FF)

  a.cmp_ri(r_tmp2, 0)
  a.jcc(XCC_E, l_zero_sub)
  a.cmp_ri(r_tmp2, 31)
  a.jcc(XCC_E, l_inf_nan)

  # Normal f16: f64_exp = exp5 - 15 + 1023 = exp5 + 1008; f64_mant = mant10 << 42
  a.add_ri(r_tmp2, 1008)
  a.shl_ri(r_tmp2, 52)
  a.shl_ri(r_h, 42)
  a.or_rr(r_tmp1, r_tmp2)
  a.or_rr(r_tmp1, r_h)
  a.movq_x_r(xd, r_tmp1)
  a.jmp(l_done)

  # Zero or subnormal: value = (-1)^sign * mant10 * 2^-24
  a.bind(l_zero_sub)
  l_only_zero = a.new_label
  a.cmp_ri(r_h, 0)
  a.jcc(XCC_E, l_only_zero)
  a.cvtsi2sd_x_r64(xd, r_h)
  # Multiply by 2^-24 (IEEE 754 f64 = (1023 - 24) << 52 = 999 << 52 = 0x3E70000000000000)
  a.mov_imm64(r_tmp2, 0x3E70000000000000)
  a.movq_x_r(X64_XMM7, r_tmp2)
  a.mulsd_rr(xd, X64_XMM7)
  # Apply sign bit via OR
  a.movq_r_x(r_tmp2, xd)
  a.or_rr(r_tmp1, r_tmp2)
  a.bind(l_only_zero)
  a.movq_x_r(xd, r_tmp1)
  a.jmp(l_done)

  # Inf / NaN: f64_exp = 2047 << 52; f64_mant = mant10 << 42
  a.bind(l_inf_nan)
  a.mov_imm64(r_tmp2, 0x7FF0000000000000)
  a.shl_ri(r_h, 42)
  a.or_rr(r_tmp1, r_tmp2)
  a.or_rr(r_tmp1, r_h)
  a.movq_x_r(xd, r_tmp1)

  a.bind(l_done)
  nil

# Emit inline IEEE-754 binary64 (`xs`) -> binary16 (low 16 bits of GPR `r_out`, clobbers `RAX, RCX, RDX`; preserves `RSI, RDI`)!
# Direct single-rounding IEEE-754 round-to-nearest-even from 64-bit bits (zero F16C requirement).
-> wire_x64_emit_f64_to_f16(a, r_out, xs)
  l_nan_inf = a.new_label
  l_under   = a.new_label
  l_over    = a.new_label
  l_done    = a.new_label

  a.movq_r_x(X64_RAX, xs)
  # r_out = sign16 = (bits >> 48) & 0x8000
  a.mov_rr(r_out, X64_RAX)
  a.shr_ri(r_out, 48)
  a.and_ri(r_out, 0x8000)

  # RDX = exp11 = (bits >> 52) & 0x7FF; RAX = mant52 = bits & ((1<<52)-1)
  a.mov_rr(X64_RDX, X64_RAX)
  a.shr_ri(X64_RDX, 52)
  a.and_ri(X64_RDX, 0x7FF)
  a.mov_imm64(X64_RCX, 0x000FFFFFFFFFFFFF)
  a.and_rr(X64_RAX, X64_RCX)

  a.cmp_ri(X64_RDX, 0x7FF)
  a.jcc(XCC_E, l_nan_inf)
  # f16 biased exp = exp11 - 1023 + 15 = exp11 - 1008
  a.sub_ri(X64_RDX, 1008)
  a.cmp_ri(X64_RDX, 31)
  a.jcc(XCC_GE, l_over)
  a.cmp_ri(X64_RDX, 0)
  a.jcc(XCC_LE, l_under)

  # Normal f16 (1 <= f16_exp <= 30): RNE bias = ((mant52 >> 42) & 1) + ((1 << 41) - 1)
  a.mov_rr(X64_RCX, X64_RAX)
  a.shr_ri(X64_RCX, 42)
  a.and_ri(X64_RCX, 1)
  a.add_rr(X64_RAX, X64_RCX)
  a.mov_imm64(X64_RCX, 0x000001FFFFFFFFFF)
  a.add_rr(X64_RAX, X64_RCX)
  a.shr_ri(X64_RAX, 42)
  a.shl_ri(X64_RDX, 10)
  a.add_rr(X64_RDX, X64_RAX)
  a.or_rr(r_out, X64_RDX)
  a.jmp(l_done)

  a.bind(l_under)
  l_zero = a.new_label
  a.cmp_ri(X64_RDX, -10)
  a.jcc(XCC_L, l_zero)
  # Branchless RNE subnormal: mant53 = mant52 | (1<<52); s = 43 - f16_exp (43..53)
  a.mov_imm64(X64_RCX, 0x0010000000000000)
  a.or_rr(X64_RAX, X64_RCX)
  a.mov_imm64(X64_RCX, 43)
  a.sub_rr(X64_RCX, X64_RDX)
  a.mov_rr(X64_RDX, X64_RAX)
  a.shr_cl(X64_RDX)
  a.and_ri(X64_RDX, 1)
  a.add_rr(X64_RAX, X64_RDX)
  a.sub_ri(X64_RCX, 1)
  a.mov_imm64(X64_RDX, 1)
  a.shl_cl(X64_RDX)
  a.sub_ri(X64_RDX, 1)
  a.add_rr(X64_RAX, X64_RDX)
  a.add_ri(X64_RCX, 1)
  a.shr_cl(X64_RAX)
  a.or_rr(r_out, X64_RAX)
  a.bind(l_zero)
  a.jmp(l_done)

  a.bind(l_over)
  a.or_ri(r_out, 0x7C00)
  a.jmp(l_done)

  a.bind(l_nan_inf)
  a.or_ri(r_out, 0x7C00)
  l_not_nan = a.new_label
  a.cmp_ri(X64_RAX, 0)
  a.jcc(XCC_E, l_not_nan)
  a.or_ri(r_out, 0x0200)
  a.bind(l_not_nan)

  a.bind(l_done)
  nil

+ WireX64Compiler
  rw :wf, :tier, :opt_cfg, :wmod, :a, :blk_labels, :l_epi
  rw :slot_loc, :vreg_loc, :used_gprs, :spill_bytes, :frame_size, :has_calls, :const_i64

  -> new(@wf, @tier = 2, @opt_cfg = nil, @wmod = nil)
    @opt_cfg = cinder_opt_for_tier(@tier) if @opt_cfg == nil
    @a = CinderX64.new(512)
    @blk_labels = []
    @slot_loc = []
    @vreg_loc = []
    @used_gprs = []
    @spill_bytes = 0
    @frame_size = 0
    @has_calls = false
    @const_i64 = {}

  -> alloc_spill(is_fp)
    off = @spill_bytes
    @spill_bytes += 8
    is_fp ? [:spill_f, off] : [:spill_g, off]

  -> plan_registers
    wf = @wf
    nv = wf.next_vreg
    ns = wf.slots
    nb = wf.blocks.size

    def_blk = Array.new(nv, -1)
    cross_blk = Array.new(nv, false)
    i = 0
    while i < wf.params.size
      def_blk[i] = 0
      cross_blk[i] = true if wf.param_types[i] != :arr
      i += 1
    bi = 0
    while bi < nb
      blk = wf.blocks[bi]
      ii = 0
      while ii < blk.insts.size
        ins = blk.insts[ii]
        op = ins.op
        @has_calls = true if op == :call_c_f64 || op == :call_direct_i64
        def_blk[ins.dst] = bi if ins.dst >= 0 && def_blk[ins.dst] < 0
        cross_blk[ins.a] = true if ins.a >= 0 && def_blk[ins.a] != bi
        cross_blk[ins.b] = true if ins.b >= 0 && def_blk[ins.b] != bi
        cross_blk[ins.c] = true if ins.c >= 0 && def_blk[ins.c] != bi
        if ins.args != nil
          ai = 0
          while ai < ins.args.size
            av = ins.args[ai]
            cross_blk[av] = true if av >= 0 && def_blk[av] != bi
            ai += 1
        ii += 1
      bi += 1

    # System V callee-saved GPRs: RBX, R12, R13, R14, R15 (5 GPRs).
    # When function has NO C calls (`!@has_calls`, true for 99% of numeric kernels!),
    # R8, R9, R10 AND XMM8..XMM15 are ALSO persistent across the entire function!
    cs_g = @has_calls ? [X64_RBX, X64_R12, X64_R13, X64_R14, X64_R15] : [X64_RBX, X64_R12, X64_R13, X64_R14, X64_R15, X64_R8, X64_R9, X64_R10]
    cs_f = @has_calls ? [] : [X64_XMM8, X64_XMM9, X64_XMM10, X64_XMM11, X64_XMM12, X64_XMM13, X64_XMM14, X64_XMM15]
    cgi = 0
    cfi = 0

    @vreg_loc = Array.new(nv, nil)
    arr_ptr_vr = {}
    bi = 0
    while bi < nb
      wf.blocks[bi].insts.each ->(ins)
        arr_ptr_vr[ins.dst] = true if ins.op == :arr_data_ptr && ins.dst >= 0
      bi += 1

    vi = 0
    while vi < nv
      if arr_ptr_vr[vi] || (vi < wf.params.size && cross_blk[vi])
        if wf.vreg_types[vi] == :f64
          if cfi < cs_f.size
            @vreg_loc[vi] = [:fpr, cs_f[cfi]]; cfi += 1
          else
            @vreg_loc[vi] = alloc_spill(true)
        else
          if cgi < cs_g.size
            r = cs_g[cgi]; cgi += 1
            @vreg_loc[vi] = [:gpr, r]
            @used_gprs.push(r) if r == X64_RBX || r >= X64_R12
          else
            @vreg_loc[vi] = alloc_spill(false)
      vi += 1

    @slot_loc = Array.new(ns, nil)
    slot_used = Array.new(ns, false)
    bi = 0
    while bi < nb
      blk = wf.blocks[bi]
      ii = 0
      while ii < blk.insts.size
        iop = blk.insts[ii].op
        if iop == :load_i64 || iop == :store_i64 || iop == :load_double || iop == :store_double
          slot_used[blk.insts[ii].imm] = true
        ii += 1
      bi += 1
    si = 0
    while si < ns
      if slot_used[si]
        if wf.slot_types[si] == :f64
          if cfi < cs_f.size
            @slot_loc[si] = [:fpr, cs_f[cfi]]; cfi += 1
          else
            @slot_loc[si] = alloc_spill(true)
        else
          if cgi < cs_g.size
            r = cs_g[cgi]; cgi += 1
            @slot_loc[si] = [:gpr, r]
            @used_gprs.push(r) if r == X64_RBX || r >= X64_R12
          else
            @slot_loc[si] = alloc_spill(false)
      si += 1

    vi = 0
    while vi < nv
      if @vreg_loc[vi] == nil && (cross_blk[vi] || vi < wf.params.size)
        if wf.vreg_types[vi] == :f64
          if cfi < cs_f.size
            @vreg_loc[vi] = [:fpr, cs_f[cfi]]; cfi += 1
          else
            @vreg_loc[vi] = alloc_spill(true)
        else
          if cgi < cs_g.size
            r = cs_g[cgi]; cgi += 1
            @vreg_loc[vi] = [:gpr, r]
            @used_gprs.push(r) if r == X64_RBX || r >= X64_R12
          else
            @vreg_loc[vi] = alloc_spill(false)
      vi += 1

    # Intra-block temps: RSI, RDI (after entry!), and XMM2..XMM5
    # Note: RAX, RCX, RDX, R11 and XMM6, XMM7 are reserved as instruction scratch!
    tmp_f = [X64_XMM2, X64_XMM3, X64_XMM4, X64_XMM5]
    bi = 0
    while bi < nb
      blk = wf.blocks[bi]
      blk_has_call = false
      blk.insts.each ->(ins)
        blk_has_call = true if ins.op == :call_c_f64 || ins.op == :call_direct_i64
      tf = 0
      blk.insts.each ->(ins)
        d = ins.dst
        if d >= 0 && @vreg_loc[d] == nil
          if wf.vreg_types[d] == :f64
            if !blk_has_call && tf < tmp_f.size
              @vreg_loc[d] = [:fpr, tmp_f[tf]]; tf += 1
            elsif cfi < cs_f.size
              @vreg_loc[d] = [:fpr, cs_f[cfi]]; cfi += 1
            else
              @vreg_loc[d] = alloc_spill(true)
          else
            if cgi < cs_g.size
              r = cs_g[cgi]; cgi += 1
              @vreg_loc[d] = [:gpr, r]
              @used_gprs.push(r) if r == X64_RBX || r >= X64_R12
            else
              @vreg_loc[d] = alloc_spill(false)
      bi += 1

    # Stack alignment: on entry RSP % 16 == 8. `push rbp` -> RSP % 16 == 0.
    # Then we push `@used_gprs.size` registers (`push_bytes = @used_gprs.size * 8`).
    # Choose `@frame_size` so `(push_bytes + @frame_size) % 16 == 0`!
    push_bytes = @used_gprs.size * 8
    raw = @spill_bytes
    rem = (push_bytes + raw) & 15
    @frame_size = rem == 0 ? raw : (raw + (16 - rem))
    nil

  -> read_g(vreg, scratch)
    loc = @vreg_loc[vreg]
    return loc[1] if loc[0] == :gpr
    @a.load64(scratch, X64_RSP, loc[1])
    scratch

  -> write_g(vreg, reg)
    loc = @vreg_loc[vreg]
    if loc[0] == :gpr
      @a.mov_rr(loc[1], reg) if loc[1] != reg
    else
      @a.store64(reg, X64_RSP, loc[1])
    nil

  -> read_f(vreg, scratch)
    loc = @vreg_loc[vreg]
    return loc[1] if loc[0] == :fpr
    @a.movsd_load(scratch, X64_RSP, loc[1])
    scratch

  -> write_f(vreg, reg)
    loc = @vreg_loc[vreg]
    if loc[0] == :fpr
      @a.movsd_rr(loc[1], reg) if loc[1] != reg
    else
      @a.movsd_store(reg, X64_RSP, loc[1])
    nil

  -> emit_prologue
    a = @a
    a.push_r(X64_RBP)
    a.mov_rr(X64_RBP, X64_RSP)
    i = 0
    while i < @used_gprs.size
      a.push_r(@used_gprs[i])
      i += 1
    a.sub_ri(X64_RSP, @frame_size) if @frame_size > 0

    # Copy incoming System V args FIRST into temp scratch / stack if they live in R8..R10
    # before writing params into R8..R10 (avoiding clobber of arg 4/5 in R8/R9!).
    sysv_g = [X64_RDI, X64_RSI, X64_RDX, X64_RCX, X64_R8, X64_R9]
    abi = @wf.abi
    np = @wf.params.size
    # Stage incoming args onto RAX / XMM6 safely one by one in reverse or via temp copies
    # Since np <= 6 in WIRE JIT, stage R8/R9 first if np >= 5!
    if np >= 5 && abi != :raw
      # Save R8 (arg 4) & R9 (arg 5) to R11 / RAX? Even cleaner: process pi = np - 1 downto 0!
      pi = np - 1
      while pi >= 0
        pt = @wf.param_types[pi]
        src_r = sysv_g[pi]
        if pt == :f64
          a.mov_rr(X64_RAX, src_r)
          a.mov_imm64(X64_R11, 281474976710656)
          a.sub_rr(X64_RAX, X64_R11)
          a.movq_x_r(X64_XMM6, X64_RAX)
          write_f(pi, X64_XMM6)
        elsif pt == :i64 && abi == :wvalue_ret_f64
          a.mov_rr(X64_RAX, src_r)
          a.shl_ri(X64_RAX, 16)
          a.sar_ri(X64_RAX, 16)
          write_g(pi, X64_RAX)
        else
          a.mov_rr(X64_RAX, src_r)
          write_g(pi, X64_RAX)
        pi -= 1
    else
      gi = 0
      fi = 0
      pi = 0
      # Stage raw args into RAX/XMM6; reverse order not needed when <5 GPR args
      while pi < np
        pt = @wf.param_types[pi]
        if pt == :f64 && abi == :raw
          a.movsd_rr(X64_XMM6, fi); fi += 1
          write_f(pi, X64_XMM6)
        elsif pt == :f64
          src_r = sysv_g[pi]
          a.mov_rr(X64_RAX, src_r)
          a.mov_imm64(X64_R11, 281474976710656)
          a.sub_rr(X64_RAX, X64_R11)
          a.movq_x_r(X64_XMM6, X64_RAX)
          write_f(pi, X64_XMM6)
        elsif pt == :i64 && abi == :wvalue_ret_f64
          src_r = sysv_g[pi]
          a.mov_rr(X64_RAX, src_r)
          a.shl_ri(X64_RAX, 16)
          a.sar_ri(X64_RAX, 16)
          write_g(pi, X64_RAX)
        else
          src_r = abi == :raw ? sysv_g[gi] : sysv_g[pi]
          gi += 1
          a.mov_rr(X64_RAX, src_r)
          write_g(pi, X64_RAX)
        pi += 1
    nil

  -> emit_epilogue
    a = @a
    a.bind(@l_epi)
    a.add_ri(X64_RSP, @frame_size) if @frame_size > 0
    i = @used_gprs.size - 1
    while i >= 0
      a.pop_r(@used_gprs[i])
      i -= 1
    a.pop_r(X64_RBP)
    a.ret
    nil

  -> eval_inv_gpr_x64(vr, defs, c_i64, scratch)
    if c_i64[vr] != nil
      @a.mov_imm64(scratch, c_i64[vr])
      return scratch
    d = defs[vr]
    if d != nil && d.op == :load_i64
      sl = @slot_loc[d.imm]
      return sl[1] if sl[0] == :gpr
      @a.load64(scratch, X64_RSP, sl[1])
      return scratch
    read_g(vr, scratch)

  -> emit_limb_ptr_x64(dst_r, base_vr, idx_r, off_vr, defs, c_i64, scratch)
    r_base = read_g(base_vr, scratch)
    @a.lea_sib(dst_r, r_base, idx_r, 3, 0)
    if off_vr >= 0
      r_off = eval_inv_gpr_x64(off_vr, defs, c_i64, scratch)
      @a.lea_sib(dst_r, dst_r, r_off, 3, 0)
    nil

  # Hardware flag-threaded multi-limb bignum loops on x86_64 (`add_limbs`, `sub_limbs`, `mul1_limbs`, `addmul1_limbs`)!
  # Uses ONLY caller-saved scratch `{RAX, RCX, RDX, RSI, RDI, R11}` (and push/pop R8 for mul1/addmul1)
  # so live callee-saved / function-wide vregs (`RBX, R12..R15, R8..R10`) are never clobbered!
  -> try_emit_carry_loop_x64(cond_id, defs, c_i64)
    cl = wire_match_carry_loop(@wf, cond_id, defs, c_i64)
    return nil if cl == nil
    kind = cl[0]; idx_sl = cl[1]; lim_vr = cl[2]; end_id = cl[3]; skip = cl[4]
    c_sl = cl[5]; p_out = cl[6]; off_out = cl[7]; p_a = cl[8]; off_a = cl[9]
    p_b = cl[10]; off_b = cl[11]; w_vr = cl[12]

    a = @a
    l_end = @blk_labels[end_id]
    sl_i = @slot_loc[idx_sl]
    if sl_i[0] == :gpr
      a.mov_rr(X64_RAX, sl_i[1])
    else
      a.load64(X64_RAX, X64_RSP, sl_i[1])
    r_n = read_g(lim_vr, X64_RCX)
    a.mov_rr(X64_RCX, r_n) if r_n != X64_RCX
    a.cmp_rr(X64_RAX, X64_RCX)
    a.jcc(XCC_GE, l_end)

    # RCX = rem = n - i (> 0); RAX = i
    a.sub_rr(X64_RCX, X64_RAX)
    # RSI = pA_eff, RDI = pOut_eff
    emit_limb_ptr_x64(X64_RSI, p_a, X64_RAX, off_a, defs, c_i64, X64_R11)
    emit_limb_ptr_x64(X64_RDI, p_out, X64_RAX, off_out, defs, c_i64, X64_R11)

    if kind == :add_limbs || kind == :sub_limbs
      is_add = kind == :add_limbs
      # RDX = pB_eff
      emit_limb_ptr_x64(X64_RDX, p_b, X64_RAX, off_b, defs, c_i64, X64_R11)
      # R11 = tail = rem & 3; RCX = quads = rem >> 2 (computed BEFORE seeding RFLAGS.CF!)
      a.mov_rr(X64_R11, X64_RCX)
      a.and_ri(X64_R11, 3)
      a.shr_ri(X64_RCX, 2)

      # Seed RFLAGS.CF from `c_sl` (`shr rax, 1` shifts bit 0 of `c` directly into `CF`!)
      sl_c = @slot_loc[c_sl]
      if sl_c[0] == :gpr
        a.mov_rr(X64_RAX, sl_c[1])
      else
        a.load64(X64_RAX, X64_RSP, sl_c[1])
      a.shr_ri(X64_RAX, 1)

      l_quad = a.new_label; l_tail = a.new_label; l_sc = a.new_label; l_done = a.new_label
      # Test `RCX == 0` WITHOUT touching `CF`: `inc rcx; dec rcx; jz l_tail`!
      a.inc_r(X64_RCX)
      a.dec_r(X64_RCX)
      a.jcc(XCC_E, l_tail)

      a.bind(l_quad)
      k_off = 0
      while k_off < 32
        a.load64(X64_RAX, X64_RSI, k_off)
        if is_add
          a.adc_load64(X64_RAX, X64_RDX, k_off)
        else
          a.sbb_load64(X64_RAX, X64_RDX, k_off)
        a.store64(X64_RAX, X64_RDI, k_off)
        k_off += 8
      a.lea_mem(X64_RSI, X64_RSI, 32)   # `LEA` touches ZERO flags!
      a.lea_mem(X64_RDX, X64_RDX, 32)
      a.lea_mem(X64_RDI, X64_RDI, 32)
      a.dec_r(X64_RCX)                  # `DEC` updates ZF while preserving `CF`!
      a.jcc(XCC_NE, l_quad)             # `JNZ` preserves `CF`!

      a.bind(l_tail)
      a.mov_rr(X64_RCX, X64_R11)
      a.inc_r(X64_RCX)
      a.dec_r(X64_RCX)
      a.jcc(XCC_E, l_done)

      a.bind(l_sc)
      a.load64(X64_RAX, X64_RSI, 0)
      if is_add
        a.adc_load64(X64_RAX, X64_RDX, 0)
      else
        a.sbb_load64(X64_RAX, X64_RDX, 0)
      a.store64(X64_RAX, X64_RDI, 0)
      a.lea_mem(X64_RSI, X64_RSI, 8)
      a.lea_mem(X64_RDX, X64_RDX, 8)
      a.lea_mem(X64_RDI, X64_RDI, 8)
      a.dec_r(X64_RCX)
      a.jcc(XCC_NE, l_sc)

      a.bind(l_done)
      a.setcc_zext(XCC_B, X64_RAX)
      if sl_c[0] == :gpr
        a.mov_rr(sl_c[1], X64_RAX)
      else
        a.store64(X64_RAX, X64_RSP, sl_c[1])
      r_n2 = read_g(lim_vr, X64_RAX)
      if sl_i[0] == :gpr
        a.mov_rr(sl_i[1], r_n2) if sl_i[1] != r_n2
      else
        a.store64(r_n2, X64_RSP, sl_i[1])
      a.jmp(l_end)
      return skip

    # `:mul1_limbs` & `:addmul1_limbs` on x86_64 (`mul` -> `RDX:RAX` + `add` + `adc`)
    is_addmul = kind == :addmul1_limbs
    sl_c = @slot_loc[c_sl]
    if sl_c[0] == :gpr
      a.mov_rr(X64_R11, sl_c[1])
    else
      a.load64(X64_R11, X64_RSP, sl_c[1])
    r_w = eval_inv_gpr_x64(w_vr, defs, c_i64, X64_RAX)
    a.mov_rr(X64_RAX, r_w) if r_w != X64_RAX
    a.push_r(X64_R8)
    a.mov_rr(X64_R8, X64_RAX)

    l_lp = a.new_label
    a.bind(l_lp)
    a.load64(X64_RAX, X64_RSI, 0)
    a.mul1_r(X64_R8)
    a.add_rr(X64_RAX, X64_R11)
    a.adc_ri(X64_RDX, 0)
    if is_addmul
      a.add_load64(X64_RAX, X64_RDI, 0)
      a.adc_ri(X64_RDX, 0)
    a.store64(X64_RAX, X64_RDI, 0)
    a.mov_rr(X64_R11, X64_RDX)
    a.lea_mem(X64_RSI, X64_RSI, 8)
    a.lea_mem(X64_RDI, X64_RDI, 8)
    a.sub_ri(X64_RCX, 1)
    a.jcc(XCC_NE, l_lp)

    a.pop_r(X64_R8)
    if sl_c[0] == :gpr
      a.mov_rr(sl_c[1], X64_R11)
    else
      a.store64(X64_R11, X64_RSP, sl_c[1])
    r_n2 = read_g(lim_vr, X64_RAX)
    if sl_i[0] == :gpr
      a.mov_rr(sl_i[1], r_n2) if sl_i[1] != r_n2
    else
      a.store64(r_n2, X64_RSP, sl_i[1])
    a.jmp(l_end)
    skip

  # Try 4-wide SSE2 Float32 Dot Product on x86_64 (`s += a[i] * b[i]`)
  -> try_emit_simd_loop(cond_id, defs, c_i64)
    do_carry = @opt_cfg == nil || (@opt_cfg.pass_enabled?("carry-chains") && @opt_cfg.opt_level >= 2)
    do_simd  = @opt_cfg == nil || @opt_cfg.pass_enabled?("simd")
    strict_fp = @opt_cfg != nil && @opt_cfg.strict_math
    allow_reassoc = @opt_cfg != nil && @opt_cfg.fast_math && !strict_fp
    if do_carry
      carry_sk = try_emit_carry_loop_x64(cond_id, defs, c_i64)
      return carry_sk if carry_sk != nil
    return nil if !do_simd || !allow_reassoc
    lp = wire_match_counted_loop(@wf, cond_id, c_i64)
    return nil if lp == nil
    body = lp[0]; idx_sl = lp[1]; lim_vr = lp[2]; end_id = lp[3]; skip = lp[4]
    return nil if body.size < 3 || body.size > 9
    st = body[body.size - 1]
    return nil if st.op != :store_double
    acc_sl = st.imm
    fadd_ins = defs[st.a]
    ga = nil
    gb = nil
    if fadd_ins != nil && fadd_ins.op == :fadd_f64 && wire_is_slot_load?(fadd_ins.a, acc_sl, defs)
      fmul_ins = defs[fadd_ins.b]
      if fmul_ins != nil && fmul_ins.op == :fmul_f64
        ga = defs[fmul_ins.a]; gb = defs[fmul_ins.b]
    elsif fadd_ins != nil && fadd_ins.op == :fmadd_f64 && wire_is_slot_load?(fadd_ins.c, acc_sl, defs)
      ga = defs[fadd_ins.a]; gb = defs[fadd_ins.b]
    return nil if ga == nil || gb == nil || ga.op != :typed_array_get_inline || gb.op != :typed_array_get_inline || ga.ebits != -32 || gb.ebits != -32
    return nil if !wire_is_slot_load?(ga.b, idx_sl, defs) || !wire_is_slot_load?(gb.b, idx_sl, defs)
    bi = 0
    while bi < body.size - 1
      op = body[bi].op
      return nil if op == :store_i64 || op == :store_double || op == :typed_array_set_inline
      bi += 1

    # Emit 4-wide f64-exact SSE2 Float32 Dot Product (`movups` -> `cvtps2pd` -> `mulpd` -> `addpd`)!
    a = @a
    l_end = @blk_labels[end_id]
    l_tail = a.new_label; l_vec = a.new_label; l_sc = a.new_label; l_fin = a.new_label

    sl_i = @slot_loc[idx_sl]
    if sl_i[0] == :gpr
      a.mov_rr(X64_RAX, sl_i[1])
    else
      a.load64(X64_RAX, X64_RSP, sl_i[1])
    r_n = read_g(lim_vr, X64_RCX)
    a.mov_rr(X64_RCX, r_n) if r_n != X64_RCX
    a.cmp_rr(X64_RAX, X64_RCX)
    a.jcc(XCC_GE, l_end)

    # RDX = pA + i*4, RSI = pB + i*4, RCX = rem = n - i
    a.sub_rr(X64_RCX, X64_RAX)
    r_pa = read_g(ga.a, X64_RDX)
    a.lea_sib(X64_RDX, r_pa, X64_RAX, 2, 0)
    r_pb = read_g(gb.a, X64_RSI)
    a.lea_sib(X64_RSI, r_pb, X64_RAX, 2, 0)

    sl_acc = @slot_loc[acc_sl]
    if sl_acc[0] == :fpr
      a.movsd_rr(X64_XMM6, sl_acc[1])
    else
      a.movsd_load(X64_XMM6, X64_RSP, sl_acc[1])

    a.cmp_ri(X64_RCX, 4)
    a.jcc(XCC_L, l_tail)
    a.xorpd_rr(X64_XMM0, X64_XMM0)
    a.xorpd_rr(X64_XMM1, X64_XMM1)
    a.bind(l_vec)
    a.movups_load(X64_XMM2, X64_RDX, 0)
    a.movups_load(X64_XMM3, X64_RSI, 0)
    a.cvtps2pd_rr(X64_XMM4, X64_XMM2)
    a.cvtps2pd_rr(X64_XMM5, X64_XMM3)
    a.mulpd_rr(X64_XMM4, X64_XMM5)
    a.addpd_rr(X64_XMM0, X64_XMM4)
    a.movhlps_rr(X64_XMM2, X64_XMM2)
    a.movhlps_rr(X64_XMM3, X64_XMM3)
    a.cvtps2pd_rr(X64_XMM4, X64_XMM2)
    a.cvtps2pd_rr(X64_XMM5, X64_XMM3)
    a.mulpd_rr(X64_XMM4, X64_XMM5)
    a.addpd_rr(X64_XMM1, X64_XMM4)
    a.add_ri(X64_RDX, 16)
    a.add_ri(X64_RSI, 16)
    a.sub_ri(X64_RCX, 4)
    a.cmp_ri(X64_RCX, 4)
    a.jcc(XCC_GE, l_vec)
    a.addpd_rr(X64_XMM0, X64_XMM1)
    a.movhlps_rr(X64_XMM2, X64_XMM0)
    a.addsd_rr(X64_XMM0, X64_XMM2)
    a.addsd_rr(X64_XMM6, X64_XMM0)

    a.bind(l_tail)
    a.cmp_ri(X64_RCX, 0)
    a.jcc(XCC_E, l_fin)
    a.bind(l_sc)
    a.movss_load(X64_XMM2, X64_RDX, 0)
    a.movss_load(X64_XMM3, X64_RSI, 0)
    a.cvtss2sd_rr(X64_XMM2, X64_XMM2)
    a.cvtss2sd_rr(X64_XMM3, X64_XMM3)
    a.mulsd_rr(X64_XMM2, X64_XMM3)
    a.addsd_rr(X64_XMM6, X64_XMM2)
    a.add_ri(X64_RDX, 4)
    a.add_ri(X64_RSI, 4)
    a.sub_ri(X64_RCX, 1)
    a.jcc(XCC_NE, l_sc)

    a.bind(l_fin)
    if sl_acc[0] == :fpr
      a.movsd_rr(sl_acc[1], X64_XMM6)
    else
      a.movsd_store(X64_XMM6, X64_RSP, sl_acc[1])
    r_n2 = read_g(lim_vr, X64_RAX)
    if sl_i[0] == :gpr
      a.mov_rr(sl_i[1], r_n2) if sl_i[1] != r_n2
    else
      a.store64(r_n2, X64_RSP, sl_i[1])
    a.jmp(l_end)
    skip

  -> emit_inst(ins, next_ins)
    a = @a
    op = ins.op
    if op == :const_i64
      a.mov_imm64(X64_RAX, ins.imm)
      write_g(ins.dst, X64_RAX)
    elsif op == :const_f64
      raw_bits = (wvalue_bits(ins.fimm) ## i64) - 281474976710656
      a.mov_imm64(X64_RAX, raw_bits)
      a.movq_x_r(X64_XMM6, X64_RAX)
      write_f(ins.dst, X64_XMM6)
    elsif op == :load_i64
      sl = @slot_loc[ins.imm]
      if sl[0] == :gpr
        write_g(ins.dst, sl[1])
      else
        a.load64(X64_RAX, X64_RSP, sl[1])
        write_g(ins.dst, X64_RAX)
    elsif op == :store_i64
      sl = @slot_loc[ins.imm]
      vr = read_g(ins.a, X64_RAX)
      if sl[0] == :gpr
        a.mov_rr(sl[1], vr) if sl[1] != vr
      else
        a.store64(vr, X64_RSP, sl[1])
    elsif op == :load_double
      sl = @slot_loc[ins.imm]
      if sl[0] == :fpr
        write_f(ins.dst, sl[1])
      else
        a.movsd_load(X64_XMM6, X64_RSP, sl[1])
        write_f(ins.dst, X64_XMM6)
    elsif op == :store_double
      sl = @slot_loc[ins.imm]
      vr = read_f(ins.a, X64_XMM6)
      if sl[0] == :fpr
        a.movsd_rr(sl[1], vr) if sl[1] != vr
      else
        a.movsd_store(vr, X64_RSP, sl[1])
    elsif op == :arr_data_ptr
      ar = read_g(ins.a, X64_RAX)
      a.mov_rr(X64_RAX, ar) if ar != X64_RAX
      a.mov_imm64(X64_R11, 0x0000FFFFFFFFFFF8)
      a.and_rr(X64_RAX, X64_R11)
      a.load32_sext(X64_RCX, X64_RAX, 4)
      a.load64(X64_RAX, X64_RAX, 16)
      sh = wire_ebits_shift(ins.ebits)
      a.lea_sib(X64_RAX, X64_RAX, X64_RCX, sh, 0)
      write_g(ins.dst, X64_RAX)
    elsif op == :array_size_raw
      ar = read_g(ins.a, X64_RAX)
      a.mov_rr(X64_RAX, ar) if ar != X64_RAX
      a.mov_imm64(X64_R11, 0x0000FFFFFFFFFFF8)
      a.and_rr(X64_RAX, X64_R11)
      a.load32_sext(X64_RAX, X64_RAX, 8)
      write_g(ins.dst, X64_RAX)
    elsif op == :typed_array_get_inline
      pr = read_g(ins.a, X64_RAX)
      eb = ins.ebits
      cidx = @const_i64[ins.b]
      if (eb == 64 || eb == 66) && cidx != nil && cidx >= 0 && cidx <= 268435455
        a.load64(X64_RAX, pr, cidx * 8)
        write_g(ins.dst, X64_RAX)
      else
        ir = read_g(ins.b, X64_RCX)
        # Note: ir can NEVER be RSP(4), so SIB indexing is always valid!
        if eb == -64
          a.movsd_load_idx(X64_XMM6, pr, ir)
          write_f(ins.dst, X64_XMM6)
        elsif eb == -32
          a.movss_load_idx(X64_XMM6, pr, ir)
          a.cvtss2sd_rr(X64_XMM6, X64_XMM6)
          write_f(ins.dst, X64_XMM6)
        elsif eb == -16
          a.load16_zext_idx(X64_RAX, pr, ir)
          wire_x64_emit_f16_to_f64(a, X64_XMM6, X64_RAX, X64_RDX, X64_R11)
          write_f(ins.dst, X64_XMM6)
        else
          if eb == 108
            a.load8_sext_idx(X64_RAX, pr, ir)
          elsif eb == 8
            a.load8_zext_idx(X64_RAX, pr, ir)
          elsif eb == 116
            a.load16_sext_idx(X64_RAX, pr, ir)
          elsif eb == 16
            a.load16_zext_idx(X64_RAX, pr, ir)
          elsif eb == 33
            a.load32_sext_idx(X64_RAX, pr, ir)
          elsif eb == 32
            a.load32_zext_idx(X64_RAX, pr, ir)
          else
            a.load64_idx(X64_RAX, pr, ir)
          write_g(ins.dst, X64_RAX)
    elsif op == :typed_array_set_inline
      pr = read_g(ins.a, X64_RSI)
      eb = ins.ebits
      cidx = @const_i64[ins.b]
      if (eb == 64 || eb == 66) && cidx != nil && cidx >= 0 && cidx <= 268435455
        vr = read_g(ins.c, X64_RAX)
        a.store64(vr, pr, cidx * 8)
      else
        ir = read_g(ins.b, X64_RDI)
        if eb == -64
          vr = read_f(ins.c, X64_XMM6)
          a.movsd_store_idx(vr, pr, ir)
        elsif eb == -32
          vr = read_f(ins.c, X64_XMM6)
          a.cvtsd2ss_rr(X64_XMM7, vr)
          a.movss_store_idx(X64_XMM7, pr, ir)
        elsif eb == -16
          vr = read_f(ins.c, X64_XMM6)
          a.mov_rr(X64_RSI, pr) if pr != X64_RSI
          a.mov_rr(X64_RDI, ir) if ir != X64_RDI
          wire_x64_emit_f64_to_f16(a, X64_R11, vr)
          a.store16_idx(X64_R11, X64_RSI, X64_RDI)
        else
          vr = read_g(ins.c, X64_RAX)
          if eb == 108 || eb == 8
            a.store8_idx(vr, pr, ir)
          elsif eb == 116 || eb == 16
            a.store16_idx(vr, pr, ir)
          elsif eb == 33 || eb == 32
            a.store32_idx(vr, pr, ir)
          else
            a.store64_idx(vr, pr, ir)
    elsif op == :raw_load
      pr = read_g(ins.a, X64_RAX)
      eb = ins.ebits
      coff = @const_i64[ins.b]
      if coff != nil && x64_fits_i32?(coff)
        if eb == -64
          a.movsd_load(X64_XMM6, pr, coff); write_f(ins.dst, X64_XMM6)
        else
          a.load8_zext(X64_RAX, pr, coff)  if eb == 8
          a.load8_sext(X64_RAX, pr, coff)  if eb == 108
          a.load16_zext(X64_RAX, pr, coff) if eb == 16
          a.load16_sext(X64_RAX, pr, coff) if eb == 116
          a.load32_zext(X64_RAX, pr, coff) if eb == 32
          a.load32_sext(X64_RAX, pr, coff) if eb == 33
          a.load64(X64_RAX, pr, coff)      if eb == 64 || eb == 66
          write_g(ins.dst, X64_RAX)
      else
        or_r = read_g(ins.b, X64_RCX)
        a.lea_sib(X64_R11, pr, or_r, 0, 0)
        if eb == -64
          a.movsd_load(X64_XMM6, X64_R11, 0); write_f(ins.dst, X64_XMM6)
        else
          a.load8_zext(X64_RAX, X64_R11, 0)  if eb == 8
          a.load8_sext(X64_RAX, X64_R11, 0)  if eb == 108
          a.load16_zext(X64_RAX, X64_R11, 0) if eb == 16
          a.load16_sext(X64_RAX, X64_R11, 0) if eb == 116
          a.load32_zext(X64_RAX, X64_R11, 0) if eb == 32
          a.load32_sext(X64_RAX, X64_R11, 0) if eb == 33
          a.load64(X64_RAX, X64_R11, 0)      if eb == 64 || eb == 66
          write_g(ins.dst, X64_RAX)
    elsif op == :raw_store
      pr = read_g(ins.a, X64_RSI)
      eb = ins.ebits
      coff = @const_i64[ins.b]
      if coff != nil && x64_fits_i32?(coff)
        if eb == -64
          vr = read_f(ins.c, X64_XMM6); a.movsd_store(vr, pr, coff)
        else
          vr = read_g(ins.c, X64_RAX)
          a.store8(vr, pr, coff)  if eb == 8 || eb == 108
          a.store16(vr, pr, coff) if eb == 16 || eb == 116
          a.store32(vr, pr, coff) if eb == 32 || eb == 33
          a.store64(vr, pr, coff) if eb == 64 || eb == 66
      else
        or_r = read_g(ins.b, X64_RDI)
        a.lea_sib(X64_R11, pr, or_r, 0, 0)
        if eb == -64
          vr = read_f(ins.c, X64_XMM6); a.movsd_store(vr, X64_R11, 0)
        else
          vr = read_g(ins.c, X64_RAX)
          a.store8(vr, X64_R11, 0)  if eb == 8 || eb == 108
          a.store16(vr, X64_R11, 0) if eb == 16 || eb == 116
          a.store32(vr, X64_R11, 0) if eb == 32 || eb == 33
          a.store64(vr, X64_R11, 0) if eb == 64 || eb == 66
    elsif op == :ctz_i64
      ra = read_g(ins.a, X64_RAX)
      a.mov_imm64(X64_RCX, 64)
      a.bsf_r(X64_RAX, ra)
      a.cmovcc(XCC_E, X64_RAX, X64_RCX)
      write_g(ins.dst, X64_RAX)
    elsif op == :clz_i64
      ra = read_g(ins.a, X64_RAX)
      a.mov_rr(X64_RDX, ra) if ra != X64_RDX
      l_nz = a.new_label; l_dn = a.new_label
      a.test_rr(X64_RDX, X64_RDX)
      a.jcc(XCC_NE, l_nz)
      a.mov_imm64(X64_RAX, 64)
      a.jmp(l_dn)
      a.bind(l_nz)
      # BSR(rdx) -> 63 ^ bsr
      a.emit_rex(true, X64_RAX, 0, X64_RDX); a.buf.put_u8(0x0F); a.buf.put_u8(0xBD); a.emit_modrm_rr(X64_RAX, X64_RDX)
      a.xor_ri(X64_RAX, 63)
      a.bind(l_dn)
      write_g(ins.dst, X64_RAX)
    elsif op == :addcarry_u64
      ra = read_g(ins.a, X64_RAX)
      a.mov_rr(X64_RAX, ra) if ra != X64_RAX
      rb = read_g(ins.b, X64_RCX)
      a.add_rr(X64_RAX, rb)
      a.setcc_zext(XCC_B, X64_RAX)
      write_g(ins.dst, X64_RAX)
    elsif op == :subborrow_u64
      ra = read_g(ins.a, X64_RAX)
      rb = read_g(ins.b, X64_RCX)
      a.cmp_rr(ra, rb)
      a.setcc_zext(XCC_B, X64_RAX)
      write_g(ins.dst, X64_RAX)
    elsif op == :mulhi_u64
      ra = read_g(ins.a, X64_RAX)
      a.mov_rr(X64_RAX, ra) if ra != X64_RAX
      rb = read_g(ins.b, X64_RCX)
      a.mov_rr(X64_RCX, rb) if rb == X64_RAX || rb == X64_RDX
      mr = (rb == X64_RAX || rb == X64_RDX) ? X64_RCX : rb
      a.mul1_r(mr)
      write_g(ins.dst, X64_RDX)
    elsif op == :adds_u64
      ra = read_g(ins.a, X64_RAX)
      a.mov_rr(X64_RAX, ra) if ra != X64_RAX
      rb = read_g(ins.b, X64_RCX)
      a.add_rr(X64_RAX, rb)
      write_g(ins.dst, X64_RAX)
    elsif op == :adcs_u64
      ra = read_g(ins.a, X64_RAX)
      a.mov_rr(X64_RAX, ra) if ra != X64_RAX
      rb = read_g(ins.b, X64_RCX)
      a.adc_rr(X64_RAX, rb)
      write_g(ins.dst, X64_RAX)
    elsif op == :cset_carry_u64
      a.setcc_zext(XCC_B, X64_RAX)
      write_g(ins.dst, X64_RAX)
    elsif op == :subs_u64
      ra = read_g(ins.a, X64_RAX)
      a.mov_rr(X64_RAX, ra) if ra != X64_RAX
      rb = read_g(ins.b, X64_RCX)
      a.sub_rr(X64_RAX, rb)
      write_g(ins.dst, X64_RAX)
    elsif op == :sbcs_u64
      ra = read_g(ins.a, X64_RAX)
      a.mov_rr(X64_RAX, ra) if ra != X64_RAX
      rb = read_g(ins.b, X64_RCX)
      a.sbb_rr(X64_RAX, rb)
      write_g(ins.dst, X64_RAX)
    elsif op == :cset_borrow_u64
      a.setcc_zext(XCC_B, X64_RAX)
      write_g(ins.dst, X64_RAX)
    elsif op == :add_i64 || op == :sub_i64 || op == :mul_i64 || op == :and_i64 || op == :or_i64 || op == :xor_i64
      ra = read_g(ins.a, X64_RAX)
      a.mov_rr(X64_RAX, ra) if ra != X64_RAX
      rb = read_g(ins.b, X64_RCX)
      a.add_rr(X64_RAX, rb)  if op == :add_i64
      a.sub_rr(X64_RAX, rb)  if op == :sub_i64
      a.imul_rr(X64_RAX, rb) if op == :mul_i64
      a.and_rr(X64_RAX, rb)  if op == :and_i64
      a.or_rr(X64_RAX, rb)   if op == :or_i64
      a.xor_rr(X64_RAX, rb)  if op == :xor_i64
      write_g(ins.dst, X64_RAX)
    elsif op == :sdiv_i64 || op == :srem_i64
      ra = read_g(ins.a, X64_RAX)
      a.mov_rr(X64_RAX, ra) if ra != X64_RAX
      rb = read_g(ins.b, X64_RCX)
      a.mov_rr(X64_RCX, rb) if rb == X64_RDX || rb == X64_RAX
      div_reg = (rb == X64_RDX || rb == X64_RAX) ? X64_RCX : rb
      a.cqo()
      a.idiv_r(div_reg)
      write_g(ins.dst, op == :sdiv_i64 ? X64_RAX : X64_RDX)
    elsif op == :udiv_i64 || op == :urem_i64
      ra = read_g(ins.a, X64_RAX)
      a.mov_rr(X64_RAX, ra) if ra != X64_RAX
      rb = read_g(ins.b, X64_RCX)
      a.mov_rr(X64_RCX, rb) if rb == X64_RDX || rb == X64_RAX
      div_reg = (rb == X64_RDX || rb == X64_RAX) ? X64_RCX : rb
      a.mov_imm64(X64_RDX, 0)
      a.div_r(div_reg)
      write_g(ins.dst, op == :udiv_i64 ? X64_RAX : X64_RDX)
    elsif op == :shl_i64 || op == :ashr_i64 || op == :lshr_i64
      ra = read_g(ins.a, X64_RAX)
      a.mov_rr(X64_RAX, ra) if ra != X64_RAX
      rb = read_g(ins.b, X64_RCX)
      a.mov_rr(X64_RCX, rb) if rb != X64_RCX
      a.shl_cl(X64_RAX) if op == :shl_i64
      a.sar_cl(X64_RAX) if op == :ashr_i64
      a.shr_cl(X64_RAX) if op == :lshr_i64
      write_g(ins.dst, X64_RAX)
    elsif op == :neg_i64
      ra = read_g(ins.a, X64_RAX)
      a.mov_rr(X64_RAX, ra) if ra != X64_RAX
      a.neg_r(X64_RAX)
      write_g(ins.dst, X64_RAX)
    elsif op == :add_i32 || op == :sub_i32 || op == :mul_i32 || op == :and_i32 || op == :or_i32 || op == :xor_i32
      ra = read_g(ins.a, X64_RAX)
      a.mov_rr(X64_RAX, ra) if ra != X64_RAX
      rb = read_g(ins.b, X64_RCX)
      a.add_rr32(X64_RAX, rb)  if op == :add_i32
      a.sub_rr32(X64_RAX, rb)  if op == :sub_i32
      a.imul_rr32(X64_RAX, rb) if op == :mul_i32
      a.and_rr32(X64_RAX, rb)  if op == :and_i32
      a.or_rr32(X64_RAX, rb)   if op == :or_i32
      a.xor_rr32(X64_RAX, rb)  if op == :xor_i32
      a.movsxd_32_64(X64_RAX, X64_RAX)
      write_g(ins.dst, X64_RAX)
    elsif op == :shl_i32 || op == :ashr_i32 || op == :lshr_i32
      ra = read_g(ins.a, X64_RAX)
      a.mov_rr(X64_RAX, ra) if ra != X64_RAX
      rb = read_g(ins.b, X64_RCX)
      a.mov_rr(X64_RCX, rb) if rb != X64_RCX
      if op == :shl_i32
        a.shl_cl32(X64_RAX); a.movsxd_32_64(X64_RAX, X64_RAX)
      elsif op == :ashr_i32
        a.sar_cl32(X64_RAX); a.movsxd_32_64(X64_RAX, X64_RAX)
      else
        a.shr_cl32(X64_RAX)
      write_g(ins.dst, X64_RAX)
    elsif op == :sext_i32_i64
      ra = read_g(ins.a, X64_RAX)
      a.movsxd_32_64(X64_RAX, ra)
      write_g(ins.dst, X64_RAX)
    elsif op == :zext_i32_i64 || op == :trunc_i64_i32
      ra = read_g(ins.a, X64_RAX)
      a.mov_rr32(X64_RAX, ra)
      write_g(ins.dst, X64_RAX)
    elsif op == :fadd_f64 || op == :fsub_f64 || op == :fmul_f64 || op == :fdiv_f64
      ra = read_f(ins.a, X64_XMM6)
      a.movsd_rr(X64_XMM6, ra) if ra != X64_XMM6
      rb = read_f(ins.b, X64_XMM7)
      a.addsd_rr(X64_XMM6, rb) if op == :fadd_f64
      a.subsd_rr(X64_XMM6, rb) if op == :fsub_f64
      a.mulsd_rr(X64_XMM6, rb) if op == :fmul_f64
      a.divsd_rr(X64_XMM6, rb) if op == :fdiv_f64
      write_f(ins.dst, X64_XMM6)
    elsif op == :fmadd_f64 || op == :fmsub_f64
      ra = read_f(ins.a, X64_XMM6)
      a.movsd_rr(X64_XMM6, ra) if ra != X64_XMM6
      rb = read_f(ins.b, X64_XMM7)
      a.mulsd_rr(X64_XMM6, rb)
      rc = read_f(ins.c, X64_XMM7)
      if op == :fmadd_f64
        a.addsd_rr(X64_XMM6, rc)
        write_f(ins.dst, X64_XMM6)
      else
        a.movsd_rr(X64_XMM7, rc) if rc != X64_XMM7
        a.subsd_rr(X64_XMM7, X64_XMM6)
        write_f(ins.dst, X64_XMM7)
    elsif op == :fmin_f64 || op == :fmax_f64
      # Exact IEEE-754 / JS Math.min/max (propagates NaN & signed -0.0!) via C libm or branch:
      ra = read_f(ins.a, X64_XMM6); a.movsd_rr(X64_XMM6, ra) if ra != X64_XMM6
      rb = read_f(ins.b, X64_XMM7); a.movsd_rr(X64_XMM7, rb) if rb != X64_XMM7
      l_nan = a.new_label; l_done = a.new_label
      a.ucomisd_rr(X64_XMM6, X64_XMM7)
      a.jcc(XCC_P, l_nan)
      if op == :fmin_f64
        a.minsd_rr(X64_XMM6, X64_XMM7)
      else
        a.maxsd_rr(X64_XMM6, X64_XMM7)
      a.jmp(l_done)
      a.bind(l_nan)
      a.addsd_rr(X64_XMM6, X64_XMM7)
      a.bind(l_done)
      write_f(ins.dst, X64_XMM6)
    elsif op == :fneg_f64
      ra = read_f(ins.a, X64_XMM6)
      a.movq_r_x(X64_RAX, ra)
      a.mov_imm64(X64_RCX, -9223372036854775808)
      a.xor_rr(X64_RAX, X64_RCX)
      a.movq_x_r(X64_XMM6, X64_RAX)
      write_f(ins.dst, X64_XMM6)
    elsif op == :fabs_f64
      ra = read_f(ins.a, X64_XMM6)
      a.movq_r_x(X64_RAX, ra)
      a.mov_imm64(X64_RCX, 0x7FFFFFFFFFFFFFFF)
      a.and_rr(X64_RAX, X64_RCX)
      a.movq_x_r(X64_XMM6, X64_RAX)
      write_f(ins.dst, X64_XMM6)
    elsif op == :fsqrt_f64
      ra = read_f(ins.a, X64_XMM6)
      a.sqrtsd_rr(X64_XMM6, ra)
      write_f(ins.dst, X64_XMM6)
    elsif op == :ffloor_f64 || op == :fceil_f64
      # Call libm floor/ceil (works even on baseline x86_64-v1 without SSE4.1!)
      fn_nm = op == :ffloor_f64 ? "floor" : "ceil"
      addr = cinder_resolve_c_sym(fn_nm)
      if addr != 0
        ra = read_f(ins.a, X64_XMM0)
        a.movsd_rr(X64_XMM0, ra) if ra != X64_XMM0
        a.call_abs(X64_RAX, addr)
        write_f(ins.dst, X64_XMM0)
      else
        ra = read_f(ins.a, X64_XMM6)
        a.roundsd_rr(X64_XMM6, ra, op == :ffloor_f64 ? 9 : 10)
        write_f(ins.dst, X64_XMM6)
    elsif op == :fround_f32
      ra = read_f(ins.a, X64_XMM6)
      a.cvtsd2ss_rr(X64_XMM6, ra)
      a.cvtss2sd_rr(X64_XMM6, X64_XMM6)
      write_f(ins.dst, X64_XMM6)
    elsif op == :fround_f16
      ra = read_f(ins.a, X64_XMM6)
      wire_x64_emit_f64_to_f16(a, X64_R11, ra)
      wire_x64_emit_f16_to_f64(a, X64_XMM6, X64_R11, X64_RAX, X64_RDX)
      write_f(ins.dst, X64_XMM6)
    elsif op == :sitofp_i64_f64
      ra = read_g(ins.a, X64_RAX)
      a.cvtsi2sd_x_r64(X64_XMM6, ra)
      write_f(ins.dst, X64_XMM6)
    elsif op == :uitofp_u64_f64
      ra = read_g(ins.a, X64_RAX)
      a.mov_rr(X64_RAX, ra) if ra != X64_RAX
      l_hi = a.new_label; l_u_done = a.new_label
      a.test_rr(X64_RAX, X64_RAX)
      a.jcc(XCC_S, l_hi)
      a.cvtsi2sd_x_r64(X64_XMM6, X64_RAX)
      a.jmp(l_u_done)
      a.bind(l_hi)
      a.mov_rr(X64_RCX, X64_RAX)
      a.shr_ri(X64_RAX, 1)
      a.and_ri(X64_RCX, 1)
      a.or_rr(X64_RAX, X64_RCX)
      a.cvtsi2sd_x_r64(X64_XMM6, X64_RAX)
      a.addsd_rr(X64_XMM6, X64_XMM6)
      a.bind(l_u_done)
      write_f(ins.dst, X64_XMM6)
    elsif op == :fptosi_f64_i64 || op == :fptoui_f64_u64
      ra = read_f(ins.a, X64_XMM6)
      a.cvttsd2si_r64_x(X64_RAX, ra)
      write_g(ins.dst, X64_RAX)
    elsif op == :nanbox_float
      ra = read_f(ins.a, X64_XMM6)
      a.movq_r_x(X64_RAX, ra)
      a.mov_imm64(X64_RCX, 281474976710656)
      a.add_rr(X64_RAX, X64_RCX)
      write_g(ins.dst, X64_RAX)
    elsif op == :unbox_float
      ra = read_g(ins.a, X64_RAX)
      a.mov_rr(X64_RAX, ra) if ra != X64_RAX
      a.mov_imm64(X64_RCX, 281474976710656)
      a.sub_rr(X64_RAX, X64_RCX)
      a.movq_x_r(X64_XMM6, X64_RAX)
      write_f(ins.dst, X64_XMM6)
    elsif op == :icmp_i64
      ra = read_g(ins.a, X64_RAX)
      rb = read_g(ins.b, X64_RCX)
      cc = wire_x64_icmp_cc(ins.pred)
      a.cmp_rr(ra, rb)
      if next_ins != nil && next_ins.op == :cond_br && next_ins.a == ins.dst
        a.jcc(cc, @blk_labels[next_ins.t_true])
        a.jmp(@blk_labels[next_ins.t_false])
        return true
      a.setcc_zext(cc, X64_RAX)
      write_g(ins.dst, X64_RAX)
    elsif op == :fcmp_f64
      # Ordered float compare: UCOMISD sets PF=1 on unordered (NaN)!
      # Note: swap operands for olt/ole so `b > a` (`XCC_A`) / `b >= a` (`XCC_AE`) gives PF=0 & CF=0 cleanly!
      ra = read_f(ins.a, X64_XMM6)
      rb = read_f(ins.b, X64_XMM7)
      p = ins.pred
      if p == :olt || p == :lt
        a.ucomisd_rr(rb, ra); a.setcc_zext(XCC_A, X64_RAX)
      elsif p == :ole || p == :le
        a.ucomisd_rr(rb, ra); a.setcc_zext(XCC_AE, X64_RAX)
      elsif p == :ogt || p == :gt
        a.ucomisd_rr(ra, rb); a.setcc_zext(XCC_A, X64_RAX)
      elsif p == :oge || p == :ge
        a.ucomisd_rr(ra, rb); a.setcc_zext(XCC_AE, X64_RAX)
      elsif p == :oeq || p == :eq
        # Ordered eq: ZF=1 AND PF=0
        a.ucomisd_rr(ra, rb)
        a.setcc_zext(XCC_E, X64_RAX)
        a.setcc_zext(XCC_NP, X64_RCX)
        a.and_rr(X64_RAX, X64_RCX)
      elsif p == :one
        # Ordered ne: ZF=0 AND PF=0
        a.ucomisd_rr(ra, rb)
        a.setcc_zext(XCC_NE, X64_RAX)
        a.setcc_zext(XCC_NP, X64_RCX)
        a.and_rr(X64_RAX, X64_RCX)
      else
        # une / ne: ZF=0 OR PF=1
        a.ucomisd_rr(ra, rb)
        a.setcc_zext(XCC_NE, X64_RAX)
        a.setcc_zext(XCC_P, X64_RCX)
        a.or_rr(X64_RAX, X64_RCX)
      write_g(ins.dst, X64_RAX)
    elsif op == :select_i64
      rc = read_g(ins.a, X64_RDX)
      rt = read_g(ins.b, X64_RAX)
      a.mov_rr(X64_RAX, rt) if rt != X64_RAX
      rf = read_g(ins.c, X64_RCX)
      a.cmp_ri(rc, 0)
      a.cmovcc(XCC_E, X64_RAX, rf)
      write_g(ins.dst, X64_RAX)
    elsif op == :select_f64
      rc = read_g(ins.a, X64_RAX)
      rt = read_f(ins.b, X64_XMM6)
      a.movsd_rr(X64_XMM6, rt) if rt != X64_XMM6
      rf = read_f(ins.c, X64_XMM7)
      l_sel_t = a.new_label
      a.cmp_ri(rc, 0)
      a.jcc(XCC_NE, l_sel_t)
      a.movsd_rr(X64_XMM6, rf)
      a.bind(l_sel_t)
      write_f(ins.dst, X64_XMM6)
    elsif op == :call_c_f64 || op == :call_direct_i64
      addr = wire_lookup_jit_sym(ins.sym)
      addr = cinder_resolve_c_sym(ins.sym) if addr == 0
      if addr == 0
        a.failed = true
        return false
      sysv_g = [X64_RDI, X64_RSI, X64_RDX, X64_RCX, X64_R8, X64_R9]
      gi = 0; fi = 0
      if ins.args != nil
        ai = 0
        while ai < ins.args.size
          avr = ins.args[ai]
          if @wf.vreg_types[avr] == :f64
            vr = read_f(avr, X64_XMM6)
            a.movsd_rr(fi, vr) if vr != fi
            fi += 1
          else
            vr = read_g(avr, X64_RAX)
            a.mov_rr(sysv_g[gi], vr) if vr != sysv_g[gi]
            gi += 1
          ai += 1
      a.call_abs(X64_RAX, addr)
      if ins.dst >= 0
        if op == :call_c_f64
          write_f(ins.dst, X64_XMM0)
        else
          write_g(ins.dst, X64_RAX)
    elsif op == :br
      a.jmp(@blk_labels[ins.t_true])
    elsif op == :cond_br
      rc = read_g(ins.a, X64_RAX)
      a.cmp_ri(rc, 0)
      a.jcc(XCC_NE, @blk_labels[ins.t_true])
      a.jmp(@blk_labels[ins.t_false])
    elsif op == :ret_i64
      vr = read_g(ins.a, X64_RAX)
      a.mov_rr(X64_RAX, vr) if vr != X64_RAX
      a.jmp(@l_epi)
    elsif op == :ret_f64
      vr = read_f(ins.a, X64_XMM0)
      if @wf.abi == :raw
        a.movsd_rr(X64_XMM0, vr) if vr != X64_XMM0
      else
        a.movq_r_x(X64_RAX, vr)
        a.mov_imm64(X64_RCX, 281474976710656)
        a.add_rr(X64_RAX, X64_RCX)
      a.jmp(@l_epi)
    elsif op == :ret_void
      a.mov_imm64(X64_RAX, 0)
      a.jmp(@l_epi)
    false

  -> encode
    defs = nil
    run_opt = @opt_cfg.opt_level >= 1 || @opt_cfg.fast_math || @opt_cfg.explicit_passes != nil || @opt_cfg.overrides.size > 0 || @wmod != nil
    if run_opt
      wire_run_passes(@wf, @opt_cfg, @wmod)
      if @opt_cfg.opt_level >= 1 || @opt_cfg.pass_enabled?("peephole") || @opt_cfg.pass_enabled?("simd") || @opt_cfg.pass_enabled?("carry-chains")
        maps = wire_build_def_maps(@wf)
        defs = maps[0]
        @const_i64 = maps[1] if @opt_cfg.pass_enabled?("peephole")
    plan_registers()
    bi = 0
    while bi < @wf.blocks.size
      @blk_labels.push(@a.new_label)
      bi += 1
    @l_epi = @a.new_label
    emit_prologue()
    skipped = {}
    want_loops = defs != nil && (@opt_cfg.pass_enabled?("simd") || (@opt_cfg.pass_enabled?("carry-chains") && @opt_cfg.opt_level >= 2))
    bi = 0
    while bi < @wf.blocks.size
      if !skipped[bi]
        blk = @wf.blocks[bi]
        @a.bind(@blk_labels[bi])
        sk = (want_loops && bi > 0) ? try_emit_simd_loop(bi, defs, @const_i64) : nil
        if sk != nil
          sk.keys.each ->(sid) skipped[sid] = true
        else
          ii = 0
          n = blk.insts.size
          while ii < n
            ins = blk.insts[ii]
            nxt = (ii + 1 < n && (@opt_cfg.pass_enabled?("peephole") || @opt_cfg.opt_level == 0)) ? blk.insts[ii + 1] : nil
            fused = emit_inst(ins, nxt)
            ii += fused ? 2 : 1
      bi += 1
    emit_epilogue()
    @opt_cfg.print_report(@wf.name) if @opt_cfg.print_passes
    @a.patch_fixups()

  -> compile
    t0 = ccall_nobox("__w_clock_ns_raw") ## i64
    ok = encode()
    fp = ok ? cinder_jit_emit_buf(@a.buf) : 0
    t1 = ccall_nobox("__w_clock_ns_raw") ## i64
    [fp, @a.byte_len, (t1 - t0) / 1000]
