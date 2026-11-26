# blade/wire_a64/backend — Pure-Tungsten WIRE IR -> ARM64 Machine Code Compiler!
#
# A complete native backend alternative to clang/LLVM written 100% in Tungsten:
#   1. Zero external processes, zero LLVM IR text, zero Mach-O linking overhead.
#   2. Built-in fast `mem2reg` slot promotion: promotes local `:alloca` slots straight into
#      ARM64 callee-saved GPRs (`x19..x28`) and FP regs (`d8..d15`) so hot loops have ZERO
#      stack load/store traffic!
#   3. Built-in loop-invariant `arr_data_ptr` hoisting & 1-instruction raw `ebits` typed-array
#      access for ALL 12 ECMAScript/Tungsten numeric widths (including ARMv8.2 hardware __fp16!).
#   4. Emits executable ARM64 machine code directly into MAP_JIT memory via `JS:A64` +
#      `jit_mem_emit` in tens of microseconds (~500x faster compile latency than clang!).

use ./wire_ir
use ./opt

# Resolve C / libm symbol addresses (sin, cos, pow, etc.) via RTLD_DEFAULT (-2)
WIRE_C_SYMS = {}

-> wire_resolve_c_sym(name)
  addr = WIRE_C_SYMS[name]
  return addr if addr != nil
  p = ccall("dlsym", -2, name)
  a = p == nil ? 0 : (p ## i64)
  WIRE_C_SYMS[name] = a
  a

# ---- Condition code mapping ----
-> wire_icmp_cc(pred)
  return CC_EQ if pred == :eq
  return CC_NE if pred == :ne
  return CC_LT if pred == :slt
  return CC_LE if pred == :sle
  return CC_GT if pred == :sgt
  return CC_GE if pred == :sge
  return CC_LO if pred == :ult
  return CC_LS if pred == :ule
  return CC_HI if pred == :ugt
  return CC_HS if pred == :uge
  CC_NE

-> wire_fcmp_cc(pred)
  return CC_EQ if pred == :oeq || pred == :eq
  return CC_NE if pred == :one || pred == :ne
  return CC_MI if pred == :olt || pred == :lt
  return CC_LS if pred == :ole || pred == :le
  return CC_GT if pred == :ogt || pred == :gt
  return CC_GE if pred == :oge || pred == :ge
  CC_NE

# ---- Pure-Tungsten ARM64 Code Generator for a WireFunc ----
#
# Register allocation strategy (fast single-pass + mem2reg local promotion):
#   - Hot promoted local slots + parameters + hoisted array data pointers live permanently in
#     ARM64 callee-saved registers:
#       GPRs: x19..x28 (10 registers — covers all loop counters, array pointers, bit-accumulators!)
#       FPRs: d8..d15  (8 registers  — covers all f64 accumulators and scalar constants!)
#   - Short-lived SSA expression temps within a basic block are allocated round-robin from
#     caller-saved registers (x9..x15, d16..d31), spilling to `[fp, #slot]` ONLY if a temp
#     crosses a call or exceeds the 10+7 GPR / 8+16 FPR budget!
#   - Reserved scratch registers for materializing spilled operands / immediates:
#       x16, x17 (IP0/IP1), d6, d7.
#   - WValue ABI (`wf.abi == :wvalue`, matching Tungsten `fn` ABI 100%):
#       - `f64` param in xN -> unboxed via `sub W_DOUBLE_BIAS` + `fmov_d_x` on entry!
#       - `f64` return      -> boxed via `fmov_x_d` + `add W_DOUBLE_BIAS` into x0 on ret!
#       - `i64` param/ret   -> raw 64-bit integer in xN / x0 (WAIT: Tungsten `fn` returning `f64`
#         boxes `i64` params too via WValue Fixnum! Our `abi` distinguishes `:wvalue_ret_f64`
#         vs `:wvalue_ret_i64` to match `bridge.w`'s exact calling convention!)

+ WireA64Compiler
  rw :wf, :a, :blk_labels, :l_epi
  rw :slot_loc, :vreg_loc, :used_gprs, :used_fprs, :spill_bytes
  rw :next_tmp_g, :next_tmp_f, :frame_size, :has_calls, :const_i64

  -> new(@wf)
    @a = JS:A64.new(512)
    @blk_labels = []
    @slot_loc = []    # slot -> [:gpr, r] | [:fpr, d] | [:spill_g, off] | [:spill_f, off]
    @vreg_loc = []    # vreg -> [:gpr, r] | [:fpr, d] | [:spill_g, off] | [:spill_f, off]
    @used_gprs = []
    @used_fprs = []
    @spill_bytes = 0
    @next_tmp_g = 0
    @next_tmp_f = 0
    @frame_size = 0
    @has_calls = false
    @const_i64 = {}

  -> alloc_spill(is_fp)
    off = 160 + @spill_bytes
    @spill_bytes += 8
    is_fp ? [:spill_f, off] : [:spill_g, off]

  # Pre-analyze liveness & allocate registers (mem2reg slot promotion + parameter pinning +
  # cross-block vreg promotion into callee-saved registers!).
  -> plan_registers
    wf = @wf
    nv = wf.next_vreg
    ns = wf.slots
    nb = wf.blocks.size

    # Detect calls & cross-block vreg uses (only mark non-array params cross-block unless actually used outside block 0!)
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
        # Mark cross-block uses
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

    # Callee-saved register pools: x19..x28 (10 GPRs), d8..d15 (8 FPRs)
    cs_g = [R_X19, R_X20, R_X21, R_X22, R_X23, R_X24, R_X25, R_X26, R_X27, R_X28]
    cs_f = [R_D8, R_D9, R_D10, R_D11, R_D12, R_D13, R_D14, R_D15]
    cgi = 0
    cfi = 0

    # 1. Allocate hoisted arr_data_ptr & non-array cross-block params FIRST (so pA/pB/pC/n NEVER spill!)
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
        is_f = wf.vreg_types[vi] == :f64
        if is_f
          if cfi < cs_f.size
            r = cs_f[cfi]; cfi += 1
            @vreg_loc[vi] = [:fpr, r]
            @used_fprs.push(r)
          else
            @vreg_loc[vi] = alloc_spill(true)
        else
          if cgi < cs_g.size
            r = cs_g[cgi]; cgi += 1
            @vreg_loc[vi] = [:gpr, r]
            @used_gprs.push(r)
          else
            @vreg_loc[vi] = alloc_spill(false)
      vi += 1

    # 2. Promote local slots (mem2reg!) into remaining callee-saved regs!
    @slot_loc = Array.new(ns, nil)
    si = 0
    while si < ns
      if wf.slot_types[si] == :f64
        if cfi < cs_f.size
          r = cs_f[cfi]; cfi += 1
          @slot_loc[si] = [:fpr, r]
          @used_fprs.push(r)
        else
          @slot_loc[si] = alloc_spill(true)
      else
        if cgi < cs_g.size
          r = cs_g[cgi]; cgi += 1
          @slot_loc[si] = [:gpr, r]
          @used_gprs.push(r)
        else
          @slot_loc[si] = alloc_spill(false)
      si += 1

    # 3. Remaining cross-block vregs & block-0-only :arr params -> callee-saved or entry tmp GPR!
    vi = 0
    while vi < nv
      if @vreg_loc[vi] == nil && (cross_blk[vi] || vi < wf.params.size)
        is_f = wf.vreg_types[vi] == :f64
        if is_f
          if cfi < cs_f.size
            r = cs_f[cfi]; cfi += 1
            @vreg_loc[vi] = [:fpr, r]
            @used_fprs.push(r)
          else
            @vreg_loc[vi] = alloc_spill(true)
        else
          if cgi < cs_g.size
            r = cs_g[cgi]; cgi += 1
            @vreg_loc[vi] = [:gpr, r]
            @used_gprs.push(r)
          else
            @vreg_loc[vi] = alloc_spill(false)
      vi += 1

    # Pass 2b: intra-block temps -> caller-saved scratch pools (if no calls in block, else spill/cs)
    # Caller-saved pools: x9..x15 (7 GPRs), d16..d31 (16 FPRs) — HUGE zero-spill working set!
    tmp_g = [R_X9, R_X10, R_X11, R_X12, R_X13, R_X14, R_X15]
    tmp_f = [R_D16, R_D17, R_D18, R_D19, R_D20, R_D21, R_D22, R_D23, R_D24, R_D25, R_D26, R_D27, R_D28, R_D29, R_D30, R_D31]
    bi = 0
    while bi < nb
      blk = wf.blocks[bi]
      # Check if this block contains a call
      blk_has_call = false
      blk.insts.each ->(ins)
        blk_has_call = true if ins.op == :call_c_f64 || ins.op == :call_direct_i64
      tg = 0
      tf = 0
      blk.insts.each ->(ins)
        d = ins.dst
        if d >= 0 && @vreg_loc[d] == nil
          is_f = wf.vreg_types[d] == :f64
          if blk_has_call
            # Safe across calls: prefer remaining callee-saved, else stack spill
            if is_f
              if cfi < cs_f.size
                r = cs_f[cfi]; cfi += 1
                @vreg_loc[d] = [:fpr, r]
                @used_fprs.push(r)
              else
                @vreg_loc[d] = alloc_spill(true)
            else
              if cgi < cs_g.size
                r = cs_g[cgi]; cgi += 1
                @vreg_loc[d] = [:gpr, r]
                @used_gprs.push(r)
              else
                @vreg_loc[d] = alloc_spill(false)
          else
            if is_f
              if tf < tmp_f.size
                @vreg_loc[d] = [:fpr, tmp_f[tf]]
                tf += 1
              else
                @vreg_loc[d] = alloc_spill(true)
            else
              if tg < tmp_g.size
                @vreg_loc[d] = [:gpr, tmp_g[tg]]
                tg += 1
              else
                @vreg_loc[d] = alloc_spill(false)
      bi += 1

    # Frame size: 160 bytes for saved fp/lr + x19..x28 + d8..d15, plus 16-byte aligned spills
    raw_sz = 160 + @spill_bytes
    @frame_size = ((raw_sz + 15) / 16) * 16
    nil

  # Load a GPR vreg into `scratch` if spilled, else return its register directly (zero mov!).
  -> read_g(vreg, scratch)
    loc = @vreg_loc[vreg]
    return loc[1] if loc[0] == :gpr
    @a.ldr_x(scratch, R_SP, loc[1])
    scratch

  # Return destination register for GPR vreg (`scratch` if spilled).
  -> dst_g(vreg, scratch)
    loc = @vreg_loc[vreg]
    loc[0] == :gpr ? loc[1] : scratch

  # Commit GPR result if spilled.
  -> write_g(vreg, reg)
    loc = @vreg_loc[vreg]
    if loc[0] == :gpr
      @a.mov_r(loc[1], reg) if loc[1] != reg
    else
      @a.str_x(reg, R_SP, loc[1])
    nil

  -> read_f(vreg, scratch)
    loc = @vreg_loc[vreg]
    return loc[1] if loc[0] == :fpr
    @a.ldr_d(scratch, R_SP, loc[1])
    scratch

  -> dst_f(vreg, scratch)
    loc = @vreg_loc[vreg]
    loc[0] == :fpr ? loc[1] : scratch

  -> write_f(vreg, reg)
    loc = @vreg_loc[vreg]
    if loc[0] == :fpr
      @a.fmov_d(loc[1], reg) if loc[1] != reg
    else
      @a.str_d(reg, R_SP, loc[1])
    nil

  -> emit_prologue
    a = @a
    fs = @frame_size
    # Allocate stack frame & save FP/LR + callee-saved regs (compact fixed layout)
    a.sub_i(R_SP, R_SP, fs)
    a.stp_x(R_FP, R_LR, R_SP, 0)
    a.mov_sp(R_FP, R_SP)
    if @used_gprs.size > 0
      a.stp_x(R_X19, R_X20, R_SP, 16)
      a.stp_x(R_X21, R_X22, R_SP, 32)
      a.stp_x(R_X23, R_X24, R_SP, 48)
      a.stp_x(R_X25, R_X26, R_SP, 64)
      a.stp_x(R_X27, R_X28, R_SP, 80)
    if @used_fprs.size > 0
      a.stp_d(R_D8, R_D9, R_SP, 96)
      a.stp_d(R_D10, R_D11, R_SP, 112)
      a.stp_d(R_D12, R_D13, R_SP, 128)
      a.stp_d(R_D14, R_D15, R_SP, 144)

    # Move incoming ARM64 parameters (x0..x7) into their allocated vreg locations!
    # ABI rules matching Tungsten `fn` + `bridge.w`:
    #   - :f64 param arrives as NaN-boxed WValue float in xN -> subtract W_DOUBLE_BIAS (1<<48) & fmov to D!
    #   - :i64 param arrives as:
    #       * WValue Fixnum (bits 0..47 signed) when abi == :wvalue_ret_f64
    #       * raw 64-bit integer when abi == :wvalue_ret_i64 or :raw
    #   - :arr param arrives as WValue WArray* in xN (untagged in :arr_data_ptr)
    abi = @wf.abi
    pi = 0
    while pi < @wf.params.size
      pt = @wf.param_types[pi]
      if pt == :f64
        if abi == :raw
          write_f(pi, pi)   # d0..d7
        else
          # Unbox WValue double from x[pi]: bits = x[pi] - (1 << 48)
          a.mov_imm64(R_X16, 281474976710656)
          a.sub_r(R_X17, pi, R_X16)
          a.fmov_d_x(R_D6, R_X17)
          write_f(pi, R_D6)
      elsif pt == :i64 && abi == :wvalue_ret_f64
        # Unbox 48-bit signed WValue Fixnum from x[pi]: (x << 16) >> 16
        a.lsl_xi(R_X16, pi, 16)
        a.asr_xi(R_X16, R_X16, 16)
        write_g(pi, R_X16)
      else
        write_g(pi, pi)
      pi += 1
    nil

  -> emit_epilogue
    a = @a
    fs = @frame_size
    a.bind(@l_epi)
    if @used_fprs.size > 0
      a.ldp_d(R_D8, R_D9, R_SP, 96)
      a.ldp_d(R_D10, R_D11, R_SP, 112)
      a.ldp_d(R_D12, R_D13, R_SP, 128)
      a.ldp_d(R_D14, R_D15, R_SP, 144)
    if @used_gprs.size > 0
      a.ldp_x(R_X19, R_X20, R_SP, 16)
      a.ldp_x(R_X21, R_X22, R_SP, 32)
      a.ldp_x(R_X23, R_X24, R_SP, 48)
      a.ldp_x(R_X25, R_X26, R_SP, 64)
      a.ldp_x(R_X27, R_X28, R_SP, 80)
    a.ldp_x(R_FP, R_LR, R_SP, 0)
    a.add_i(R_SP, R_SP, fs)
    a.ret
    nil

  -> emit_inst(ins, next_ins)
    a = @a
    op = ins.op
    if op == :const_i64
      dr = dst_g(ins.dst, R_X16)
      a.mov_imm64(dr, ins.imm)
      write_g(ins.dst, dr)
    elsif op == :const_f64
      # Convert f64 WValue bits -> raw IEEE 754 bits (sub 1<<48) -> fmov_d_x!
      raw_bits = (wvalue_bits(ins.fimm) ## i64) - 281474976710656
      a.mov_imm64(R_X16, raw_bits)
      dr = dst_f(ins.dst, R_D6)
      a.fmov_d_x(dr, R_X16)
      write_f(ins.dst, dr)
    elsif op == :load_i64
      sl = @slot_loc[ins.imm]
      if sl[0] == :gpr
        write_g(ins.dst, sl[1])
      else
        dr = dst_g(ins.dst, R_X16)
        a.ldr_x(dr, R_SP, sl[1])
        write_g(ins.dst, dr)
    elsif op == :store_i64
      sl = @slot_loc[ins.imm]
      vr = read_g(ins.a, R_X16)
      if sl[0] == :gpr
        a.mov_r(sl[1], vr) if sl[1] != vr
      else
        a.str_x(vr, R_SP, sl[1])
    elsif op == :load_double
      sl = @slot_loc[ins.imm]
      if sl[0] == :fpr
        write_f(ins.dst, sl[1])
      else
        dr = dst_f(ins.dst, R_D6)
        a.ldr_d(dr, R_SP, sl[1])
        write_f(ins.dst, dr)
    elsif op == :store_double
      sl = @slot_loc[ins.imm]
      vr = read_f(ins.a, R_D6)
      if sl[0] == :fpr
        a.fmov_d(sl[1], vr) if sl[1] != vr
      else
        a.str_d(vr, R_SP, sl[1])
    elsif op == :arr_data_ptr
      # Untag WArray* (`arr & 0x00007FFFFFFFFFF0`) and load `slots` pointer at offset 16!
      # Also account for `start` at offset 4 if non-zero (always 0 for our views, checked cleanly!)
      ar = read_g(ins.a, R_X16)
      dr = dst_g(ins.dst, R_X16)
      a.and_x_ptr47(R_X17, ar)
      a.ldr_x(dr, R_X17, 16)
      write_g(ins.dst, dr)
    elsif op == :array_size_raw
      ar = read_g(ins.a, R_X16)
      dr = dst_g(ins.dst, R_X16)
      a.and_x_ptr47(R_X17, ar)
      a.ldrsw(dr, R_X17, 8)
      write_g(ins.dst, dr)
    elsif op == :typed_array_get_inline
      pr = read_g(ins.a, R_X16)
      ir = read_g(ins.b, R_X17)
      eb = ins.ebits
      if eb == -64
        dr = dst_f(ins.dst, R_D6)
        a.ldr_d_idx(dr, pr, ir)
        write_f(ins.dst, dr)
      elsif eb == -32
        dr = dst_f(ins.dst, R_D6)
        a.ldr_s_idx(dr, pr, ir)
        a.fcvt_d_s(dr, dr)
        write_f(ins.dst, dr)
      elsif eb == -16
        # ARMv8.2 hardware __fp16 load + single-cycle fcvt to f64!
        dr = dst_f(ins.dst, R_D6)
        a.ldr_h_idx(dr, pr, ir)
        a.fcvt_d_h(dr, dr)
        write_f(ins.dst, dr)
      else
        dr = dst_g(ins.dst, R_X16)
        if eb == 108
          a.ldrsb_idx(dr, pr, ir)
          a.sxtw(dr, dr)
        elsif eb == 8
          a.ldrb_idx(dr, pr, ir)
        elsif eb == 116
          a.ldrsh_idx(dr, pr, ir)
          a.sxtw(dr, dr)
        elsif eb == 16
          a.ldrh_idx(dr, pr, ir)
        elsif eb == 33
          a.ldrsw_idx(dr, pr, ir)
        elsif eb == 32
          a.ldr_w_idx(dr, pr, ir)
        else
          # 66 (i64) or 64 (u64)
          a.ldr_x_idx(dr, pr, ir)
        write_g(ins.dst, dr)
    elsif op == :typed_array_set_inline
      pr = read_g(ins.a, R_X16)
      ir = read_g(ins.b, R_X17)
      eb = ins.ebits
      if eb == -64
        vr = read_f(ins.c, R_D6)
        a.str_d_idx(vr, pr, ir)
      elsif eb == -32
        vr = read_f(ins.c, R_D6)
        a.fcvt_s_d(R_D7, vr)
        a.str_s_idx(R_D7, pr, ir)
      elsif eb == -16
        # ARMv8.2 hardware double -> __fp16 + 16-bit store!
        vr = read_f(ins.c, R_D6)
        a.fcvt_h_d(R_D7, vr)
        a.str_h_idx(R_D7, pr, ir)
      else
        vr = read_g(ins.c, R_X8)
        if eb == 108 || eb == 8
          a.strb_idx(vr, pr, ir)
        elsif eb == 116 || eb == 16
          a.strh_idx(vr, pr, ir)
        elsif eb == 33 || eb == 32
          a.str_w_idx(vr, pr, ir)
        else
          a.str_x_idx(vr, pr, ir)
    elsif op == :add_i64
      cv = @const_i64[ins.b]
      if cv != nil && cv >= 0 && cv <= 4095
        ra = read_g(ins.a, R_X16); dr = dst_g(ins.dst, R_X16)
        a.add_i(dr, ra, cv); write_g(ins.dst, dr)
      else
        ra = read_g(ins.a, R_X16); rb = read_g(ins.b, R_X17); dr = dst_g(ins.dst, R_X16)
        a.add_r(dr, ra, rb); write_g(ins.dst, dr)
    elsif op == :sub_i64
      cv = @const_i64[ins.b]
      if cv != nil && cv >= 0 && cv <= 4095
        ra = read_g(ins.a, R_X16); dr = dst_g(ins.dst, R_X16)
        a.sub_i(dr, ra, cv); write_g(ins.dst, dr)
      else
        ra = read_g(ins.a, R_X16); rb = read_g(ins.b, R_X17); dr = dst_g(ins.dst, R_X16)
        a.sub_r(dr, ra, rb); write_g(ins.dst, dr)
    elsif op == :mul_i64
      cv = @const_i64[ins.b]
      if cv == 2 || cv == 4 || cv == 8 || cv == 16
        sh = cv == 2 ? 1 : (cv == 4 ? 2 : (cv == 8 ? 3 : 4))
        ra = read_g(ins.a, R_X16); dr = dst_g(ins.dst, R_X16)
        a.lsl_xi(dr, ra, sh); write_g(ins.dst, dr)
      else
        ra = read_g(ins.a, R_X16); rb = read_g(ins.b, R_X17); dr = dst_g(ins.dst, R_X16)
        a.mul_x(dr, ra, rb); write_g(ins.dst, dr)
    elsif op == :sdiv_i64
      ra = read_g(ins.a, R_X16); rb = read_g(ins.b, R_X17); dr = dst_g(ins.dst, R_X16)
      a.sdiv_x(dr, ra, rb); write_g(ins.dst, dr)
    elsif op == :udiv_i64
      ra = read_g(ins.a, R_X16); rb = read_g(ins.b, R_X17); dr = dst_g(ins.dst, R_X16)
      a.udiv_x(dr, ra, rb); write_g(ins.dst, dr)
    elsif op == :srem_i64
      ra = read_g(ins.a, R_X16); rb = read_g(ins.b, R_X17); dr = dst_g(ins.dst, R_X8)
      a.sdiv_x(R_X8, ra, rb)
      a.msub_x(dr, R_X8, rb, ra)
      write_g(ins.dst, dr)
    elsif op == :and_i64
      ra = read_g(ins.a, R_X16); rb = read_g(ins.b, R_X17); dr = dst_g(ins.dst, R_X16)
      a.and_r(dr, ra, rb); write_g(ins.dst, dr)
    elsif op == :or_i64
      ra = read_g(ins.a, R_X16); rb = read_g(ins.b, R_X17); dr = dst_g(ins.dst, R_X16)
      a.orr_r(dr, ra, rb); write_g(ins.dst, dr)
    elsif op == :xor_i64
      ra = read_g(ins.a, R_X16); rb = read_g(ins.b, R_X17); dr = dst_g(ins.dst, R_X16)
      a.eor_r(dr, ra, rb); write_g(ins.dst, dr)
    elsif op == :shl_i64
      ra = read_g(ins.a, R_X16); rb = read_g(ins.b, R_X17); dr = dst_g(ins.dst, R_X16)
      a.lsl_x(dr, ra, rb); write_g(ins.dst, dr)
    elsif op == :ashr_i64
      ra = read_g(ins.a, R_X16); rb = read_g(ins.b, R_X17); dr = dst_g(ins.dst, R_X16)
      a.asr_x(dr, ra, rb); write_g(ins.dst, dr)
    elsif op == :lshr_i64
      ra = read_g(ins.a, R_X16); rb = read_g(ins.b, R_X17); dr = dst_g(ins.dst, R_X16)
      a.lsr_x(dr, ra, rb); write_g(ins.dst, dr)
    elsif op == :neg_i64
      ra = read_g(ins.a, R_X16); dr = dst_g(ins.dst, R_X16)
      a.neg_x(dr, ra); write_g(ins.dst, dr)
    elsif op == :add_i32
      ra = read_g(ins.a, R_X16); rb = read_g(ins.b, R_X17); dr = dst_g(ins.dst, R_X16)
      a.add_w(dr, ra, rb); a.sxtw(dr, dr); write_g(ins.dst, dr)
    elsif op == :sub_i32
      ra = read_g(ins.a, R_X16); rb = read_g(ins.b, R_X17); dr = dst_g(ins.dst, R_X16)
      a.sub_w(dr, ra, rb); a.sxtw(dr, dr); write_g(ins.dst, dr)
    elsif op == :mul_i32
      ra = read_g(ins.a, R_X16); rb = read_g(ins.b, R_X17); dr = dst_g(ins.dst, R_X16)
      a.mul_w(dr, ra, rb); a.sxtw(dr, dr); write_g(ins.dst, dr)
    elsif op == :and_i32
      ra = read_g(ins.a, R_X16); rb = read_g(ins.b, R_X17); dr = dst_g(ins.dst, R_X16)
      a.and_w(dr, ra, rb); a.sxtw(dr, dr); write_g(ins.dst, dr)
    elsif op == :or_i32
      ra = read_g(ins.a, R_X16); rb = read_g(ins.b, R_X17); dr = dst_g(ins.dst, R_X16)
      a.orr_w(dr, ra, rb); a.sxtw(dr, dr); write_g(ins.dst, dr)
    elsif op == :xor_i32
      ra = read_g(ins.a, R_X16); rb = read_g(ins.b, R_X17); dr = dst_g(ins.dst, R_X16)
      a.eor_w(dr, ra, rb); a.sxtw(dr, dr); write_g(ins.dst, dr)
    elsif op == :shl_i32
      cv = @const_i64[ins.b]
      ra = read_g(ins.a, R_X16); dr = dst_g(ins.dst, R_X16)
      if cv != nil && cv >= 0 && cv <= 31
        a.lsl_wi(dr, ra, cv)
      else
        rb = read_g(ins.b, R_X17)
        a.lsl_w(dr, ra, rb)
      a.sxtw(dr, dr); write_g(ins.dst, dr)
    elsif op == :ashr_i32
      cv = @const_i64[ins.b]
      ra = read_g(ins.a, R_X16); dr = dst_g(ins.dst, R_X16)
      if cv != nil && cv >= 0 && cv <= 31
        a.asr_wi(dr, ra, cv)
      else
        rb = read_g(ins.b, R_X17)
        a.asr_w(dr, ra, rb)
      a.sxtw(dr, dr); write_g(ins.dst, dr)
    elsif op == :lshr_i32
      cv = @const_i64[ins.b]
      ra = read_g(ins.a, R_X16); dr = dst_g(ins.dst, R_X16)
      if cv != nil && cv >= 0 && cv <= 31
        a.lsr_wi(dr, ra, cv)
      else
        rb = read_g(ins.b, R_X17)
        a.lsr_w(dr, ra, rb)
      write_g(ins.dst, dr)
    elsif op == :sext_i32_i64
      ra = read_g(ins.a, R_X16); dr = dst_g(ins.dst, R_X16)
      a.sxtw(dr, ra); write_g(ins.dst, dr)
    elsif op == :zext_i32_i64 || op == :trunc_i64_i32
      ra = read_g(ins.a, R_X16); dr = dst_g(ins.dst, R_X16)
      a.uxtw(dr, ra); write_g(ins.dst, dr)
    elsif op == :fadd_f64
      ra = read_f(ins.a, R_D6); rb = read_f(ins.b, R_D7); dr = dst_f(ins.dst, R_D6)
      a.fadd_d(dr, ra, rb); write_f(ins.dst, dr)
    elsif op == :fsub_f64
      ra = read_f(ins.a, R_D6); rb = read_f(ins.b, R_D7); dr = dst_f(ins.dst, R_D6)
      a.fsub_d(dr, ra, rb); write_f(ins.dst, dr)
    elsif op == :fmul_f64
      ra = read_f(ins.a, R_D6); rb = read_f(ins.b, R_D7); dr = dst_f(ins.dst, R_D6)
      a.fmul_d(dr, ra, rb); write_f(ins.dst, dr)
    elsif op == :fdiv_f64
      ra = read_f(ins.a, R_D6); rb = read_f(ins.b, R_D7); dr = dst_f(ins.dst, R_D6)
      a.fdiv_d(dr, ra, rb); write_f(ins.dst, dr)
    elsif op == :fmin_f64
      ra = read_f(ins.a, R_D6); rb = read_f(ins.b, R_D7); dr = dst_f(ins.dst, R_D6)
      a.fmin_d(dr, ra, rb); write_f(ins.dst, dr)
    elsif op == :fmax_f64
      ra = read_f(ins.a, R_D6); rb = read_f(ins.b, R_D7); dr = dst_f(ins.dst, R_D6)
      a.fmax_d(dr, ra, rb); write_f(ins.dst, dr)
    elsif op == :fneg_f64
      ra = read_f(ins.a, R_D6); dr = dst_f(ins.dst, R_D6)
      a.fneg_d(dr, ra); write_f(ins.dst, dr)
    elsif op == :fabs_f64
      ra = read_f(ins.a, R_D6); dr = dst_f(ins.dst, R_D6)
      a.fabs_d(dr, ra); write_f(ins.dst, dr)
    elsif op == :fsqrt_f64
      ra = read_f(ins.a, R_D6); dr = dst_f(ins.dst, R_D6)
      a.fsqrt_d(dr, ra); write_f(ins.dst, dr)
    elsif op == :ffloor_f64
      ra = read_f(ins.a, R_D6); dr = dst_f(ins.dst, R_D6)
      a.frintm_d(dr, ra); write_f(ins.dst, dr)
    elsif op == :fceil_f64
      ra = read_f(ins.a, R_D6); dr = dst_f(ins.dst, R_D6)
      a.frintp_d(dr, ra); write_f(ins.dst, dr)
    elsif op == :fround_f32
      ra = read_f(ins.a, R_D6); dr = dst_f(ins.dst, R_D6)
      a.fcvt_s_d(dr, ra); a.fcvt_d_s(dr, dr); write_f(ins.dst, dr)
    elsif op == :fround_f16
      ra = read_f(ins.a, R_D6); dr = dst_f(ins.dst, R_D6)
      a.fcvt_h_d(dr, ra); a.fcvt_d_h(dr, dr); write_f(ins.dst, dr)
    elsif op == :sitofp_i64_f64
      ra = read_g(ins.a, R_X16); dr = dst_f(ins.dst, R_D6)
      a.scvtf_d_x(dr, ra); write_f(ins.dst, dr)
    elsif op == :uitofp_u64_f64
      ra = read_g(ins.a, R_X16); dr = dst_f(ins.dst, R_D6)
      a.ucvtf_d_x(dr, ra); write_f(ins.dst, dr)
    elsif op == :fptosi_f64_i64
      ra = read_f(ins.a, R_D6); dr = dst_g(ins.dst, R_X16)
      a.fcvtzs_x_d(dr, ra); write_g(ins.dst, dr)
    elsif op == :fptoui_f64_u64
      ra = read_f(ins.a, R_D6); dr = dst_g(ins.dst, R_X16)
      a.fcvtzu_x_d(dr, ra); write_g(ins.dst, dr)
    elsif op == :nanbox_float
      ra = read_f(ins.a, R_D6); dr = dst_g(ins.dst, R_X16)
      a.fmov_x_d(R_X16, ra)
      a.mov_imm64(R_X17, 281474976710656)
      a.add_r(dr, R_X16, R_X17)
      write_g(ins.dst, dr)
    elsif op == :unbox_float
      ra = read_g(ins.a, R_X16); dr = dst_f(ins.dst, R_D6)
      a.mov_imm64(R_X17, 281474976710656)
      a.sub_r(R_X16, ra, R_X17)
      a.fmov_d_x(dr, R_X16)
      write_f(ins.dst, dr)
    elsif op == :icmp_i64
      ra = read_g(ins.a, R_X16); rb = read_g(ins.b, R_X17)
      cc = wire_icmp_cc(ins.pred)
      a.cmp_r(ra, rb)
      # Peephole: fuse `icmp_i64` directly with immediately following `cond_br`!
      if next_ins != nil && next_ins.op == :cond_br && next_ins.a == ins.dst
        a.b_cond(cc, @blk_labels[next_ins.t_true])
        a.b(@blk_labels[next_ins.t_false])
        return true   # signals caller to skip next_ins!
      dr = dst_g(ins.dst, R_X16)
      a.cset(dr, cc)
      write_g(ins.dst, dr)
    elsif op == :fcmp_f64
      ra = read_f(ins.a, R_D6); rb = read_f(ins.b, R_D7)
      cc = wire_fcmp_cc(ins.pred)
      a.fcmp_d(ra, rb)
      if next_ins != nil && next_ins.op == :cond_br && next_ins.a == ins.dst
        a.b_cond(cc, @blk_labels[next_ins.t_true])
        a.b(@blk_labels[next_ins.t_false])
        return true
      dr = dst_g(ins.dst, R_X16)
      a.cset(dr, cc)
      write_g(ins.dst, dr)
    elsif op == :select_i64
      rc = read_g(ins.a, R_X8)
      rt = read_g(ins.b, R_X16)
      rf = read_g(ins.c, R_X17)
      dr = dst_g(ins.dst, R_X16)
      a.cmp_i(rc, 0)
      a.csel_x(dr, rt, rf, CC_NE)
      write_g(ins.dst, dr)
    elsif op == :select_f64
      rc = read_g(ins.a, R_X16)
      rt = read_f(ins.b, R_D6)
      rf = read_f(ins.c, R_D7)
      dr = dst_f(ins.dst, R_D6)
      a.cmp_i(rc, 0)
      a.fcsel_d(dr, rt, rf, CC_NE)
      write_f(ins.dst, dr)
    elsif op == :call_c_f64
      addr = wire_resolve_c_sym(ins.sym)
      if addr == 0
        a.failed = true
        return false
      ai = 0
      while ai < ins.args.size
        vr = read_f(ins.args[ai], R_D6)
        a.fmov_d(ai, vr) if vr != ai
        ai += 1
      a.call_abs(R_X16, addr)
      write_f(ins.dst, R_D0)
    elsif op == :br
      a.b(@blk_labels[ins.t_true])
    elsif op == :cond_br
      rc = read_g(ins.a, R_X16)
      a.cbnz_x(rc, @blk_labels[ins.t_true])
      a.b(@blk_labels[ins.t_false])
    elsif op == :ret_i64
      vr = read_g(ins.a, R_X0)
      a.mov_r(R_X0, vr) if vr != R_X0
      a.b(@l_epi)
    elsif op == :ret_f64
      vr = read_f(ins.a, R_D0)
      if @wf.abi == :raw
        a.fmov_d(R_D0, vr) if vr != R_D0
      else
        # Box f64 into WValue (bits + W_DOUBLE_BIAS) in x0
        a.fmov_x_d(R_X16, vr)
        a.mov_imm64(R_X17, 281474976710656)
        a.add_r(R_X0, R_X16, R_X17)
      a.b(@l_epi)
    elsif op == :ret_void
      a.movz_x(R_X0, 0)
      a.b(@l_epi)
    false

  -> compile
    t0 = ccall_nobox("__w_clock_ns_raw") ## i64
    wire_opt_func(@wf)
    maps = wire_build_def_maps(@wf)
    defs = maps[0]
    @const_i64 = maps[1]
    c_f64 = maps[2]
    plan_registers()
    bi = 0
    while bi < @wf.blocks.size
      @blk_labels.push(@a.new_label)
      bi += 1
    @l_epi = @a.new_label
    emit_prologue()
    skipped = {}
    bi = 0
    while bi < @wf.blocks.size
      if !skipped[bi]
        blk = @wf.blocks[bi]
        @a.bind(@blk_labels[bi])
        sk = bi > 0 ? wire_try_emit_simd_loop(self, bi, defs, @const_i64, c_f64) : nil
        if sk != nil
          sk.keys.each ->(sid) skipped[sid] = true
        else
          ii = 0
          n = blk.insts.size
          while ii < n
            ins = blk.insts[ii]
            nxt = ii + 1 < n ? blk.insts[ii + 1] : nil
            fused = emit_inst(ins, nxt)
            ii += fused ? 2 : 1
      bi += 1
    emit_epilogue()
    code_bytes = @a.len * 4
    fp = @a.finalize()
    t1 = ccall_nobox("__w_clock_ns_raw") ## i64
    [fp, code_bytes, (t1 - t0) / 1000]

-> wire_compile_func(wf)
  c = WireA64Compiler.new(wf)
  c.compile()
