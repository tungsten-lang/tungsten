# cinder/ll_x64 — Pure-Tungsten LLVM IR (.ll) -> x86_64 Machine Code & ELF64 Compiler.
#
# Compiles an entire Tungsten `.ll` module directly into an `Elf64Writer` (`EM_X86_64`)
# without invoking `clang`, `llc`, `opt`, or `as`:
#   - Full System V AMD64 calling convention (`rdi, rsi, rdx, rcx, r8, r9`, `xmm0..xmm7`,
#     plus arbitrary overflow stack arguments `[rsp + k*8]` / `[rbp + 16 + k*8]`).
#   - `preserve_mostcc` ABI preservation (`rcx..r10`, `rbx`, `r12..r15`).
#   - 1-instruction cached Local-Exec TLS `@.ic` access via `r15` (`%fs:0 + TPOFF32`).
#   - Full `i128`, `<2 x i64>`, `{ i64, i1 }` `smul.with.overflow`, SWAR `ctpop.i64`,
#     baseline-v1-safe `cttz.i64` / `ctlz.i64`, and PHI edge parallel-copy thunks.

use ./buf
use ./x64
use ./elf64
use ./ll_parser
use ./opt_config
use ./ll_opt

-> llx64_icmp_cc(pred)
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

-> llx64_sort_slot_candidates(cands)
  i = 1
  while i < cands.size()
    cur = cands[i]
    j = i - 1
    while j >= 0 && (cands[j][1] < cur[1] || (cands[j][1] == cur[1] && cands[j][0] > cur[0]))
      cands[j + 1] = cands[j]
      j -= 1
    cands[j + 1] = cur
    i += 1
  cands

+ LLX64FuncCompiler
  rw :fn_ir, :mod_info, :opt_cfg, :a
  rw :out_arg_bytes, :local_base, :pushed_regs, :body_frame_bytes
  rw :do_peephole, :do_simd, :slot_reg_g
  rw :blk_labels, :l_epi, :edge_labels, :edge_list

  -> new(@fn_ir, @mod_info, @opt_cfg = nil)
    @opt_cfg = CinderOptConfig.new(2) if @opt_cfg == nil
    @a = CinderX64.new(@fn_ir.blocks.size() * 48 + 64)
    @out_arg_bytes = 0
    @local_base = 0
    @pushed_regs = []
    @body_frame_bytes = 0
    @do_peephole = @opt_cfg.pass_enabled?("peephole")
    @do_simd = @opt_cfg.pass_enabled?("simd")
    @slot_reg_g = {}
    @blk_labels = []
    @l_epi = -1
    @edge_labels = {}
    @edge_list = []

  -> compute_layout
    max_stack_args = 0
    bi = 0
    while bi < @fn_ir.blocks.size()
      insts = @fn_ir.blocks[bi].insts
      ii = 0
      while ii < insts.size()
        ins = insts[ii]
        if ins.op == :call && ins.extra != nil
          gi = 0; fi = 0; st_n = 0
          ai = 0
          while ai < ins.extra.size()
            aty = ins.extra[ai][0]
            if aty == LLTY_F64 || aty == LLTY_F32
              if fi < 8
                fi += 1
              else
                st_n += 1
            else
              if gi < 6
                gi += 1
              else
                st_n += 1
            ai += 1
          max_stack_args = st_n if st_n > max_stack_args
        ii += 1
      bi += 1

    @out_arg_bytes = ((max_stack_args * 8 + 15) / 16) * 16
    @local_base = @out_arg_bytes

    if @fn_ir.is_preserve_most
      @pushed_regs = [X64_RBX, X64_RCX, X64_RDX, X64_RSI, X64_RDI, X64_R8, X64_R9, X64_R10, X64_R12, X64_R13, X64_R14, X64_R15]
    else
      @pushed_regs = []
      if @opt_cfg.pass_enabled?("reg-promote") && @fn_ir.slot_is_fp != nil
        g_cands = []
        off = ((@fn_ir.alloca_bytes + 15) / 16) * 16
        while off < @fn_ir.phi_stage_off
          g_cands.push([off, @fn_ir.slot_uses[off]]) if @fn_ir.slot_is_fp[off] == false
          off += 8
        llx64_sort_slot_candidates(g_cands)
        cs_pool = [X64_RBX, X64_R12, X64_R13, X64_R14]
        gi = 0
        while gi < g_cands.size() && gi < cs_pool.size()
          r = cs_pool[gi]
          @slot_reg_g[g_cands[gi][0]] = r
          @pushed_regs.push(r)
          gi += 1
      @pushed_regs.push(X64_R15) if @fn_ir.uses_ic

    push_bytes = @pushed_regs.size() * 8
    raw = @local_base + @fn_ir.frame_slots_bytes
    rem = (push_bytes + raw) & 15
    @body_frame_bytes = rem == 0 ? raw : (raw + (16 - rem))
    nil

  -> slot_sp_off(val_id)
    @local_base + @fn_ir.val_slot[val_id]

  -> load_sym_addr(rd, sym_id, addend = 0)
    if sym_id == @fn_ir.ic_sym_id && @fn_ir.uses_ic
      if addend == 0
        @a.mov_rr(rd, X64_R15)
      else
        @a.lea_mem(rd, X64_R15, addend)
      return nil
    sn = @mod_info.sym_list[sym_id]
    sk = @mod_info.sym_kind[sym_id]
    if sk == LLSYM_TLS
      @a.addr_tls_linux(rd, sn, addend)
    elsif sk == LLSYM_DEF_FN || sk == LLSYM_DEF_DATA
      @a.addr_sym_local(rd, sn, addend)
    else
      @a.addr_sym_got(rd, sn, addend)
    nil

  -> load_op64(rd, kind, val, ty = 64)
    if kind == LLOP_VAL
      raw_sl = @fn_ir.val_slot[val]
      pr = @slot_reg_g[raw_sl]
      if pr != nil
        @a.mov_rr(rd, pr) if rd != pr
      else
        @a.load64(rd, X64_RSP, @local_base + raw_sl)
      if ty == LLTY_I1
        @a.and_ri(rd, 1)
      elsif ty == LLTY_I32
        @a.mov_rr32(rd, rd)
    elsif kind == LLOP_IMM
      @a.mov_imm64(rd, val)
    elsif kind == LLOP_SYM
      load_sym_addr(rd, val, 0)
    else
      @a.mov_imm64(rd, 0)
    nil

  -> store_val64(val_id, rs)
    raw_sl = @fn_ir.val_slot[val_id]
    pr = @slot_reg_g[raw_sl]
    if pr != nil
      @a.mov_rr(pr, rs) if pr != rs
    else
      @a.store64(rs, X64_RSP, @local_base + raw_sl)
    nil

  -> load_op128(rd_lo, rd_hi, kind, val)
    if kind == LLOP_VAL
      off = slot_sp_off(val)
      @a.load64(rd_lo, X64_RSP, off)
      @a.load64(rd_hi, X64_RSP, off + 8)
    else
      @a.mov_imm64(rd_lo, val)
      @a.mov_imm64(rd_hi, val < 0 ? -1 : 0)
    nil

  -> store_val128(val_id, rs_lo, rs_hi)
    off = slot_sp_off(val_id)
    @a.store64(rs_lo, X64_RSP, off)
    @a.store64(rs_hi, X64_RSP, off + 8)
    nil

  -> load_op_f64(xd, kind, val)
    if kind == LLOP_VAL
      @a.movsd_load(xd, X64_RSP, slot_sp_off(val))
    else
      @a.mov_imm64(X64_R11, val)
      @a.movq_x_r(xd, X64_R11)
    nil

  -> store_val_f64(val_id, xs)
    @a.movsd_store(xs, X64_RSP, slot_sp_off(val_id))
    nil

  -> branch_target_label(pred_bid, succ_bid)
    succ = @fn_ir.blocks[succ_bid]
    return @blk_labels[succ_bid] if succ.phis.size() == 0
    key = pred_bid.to_s() + ":" + succ_bid.to_s()
    existing = @edge_labels[key]
    return existing if existing != nil
    el = @a.new_label()
    @edge_labels[key] = el
    @edge_list.push([pred_bid, succ_bid, el])
    el

  -> emit_phi_edge_thunks
    ei = 0
    while ei < @edge_list.size()
      edge = @edge_list[ei]
      pred_bid = edge[0]
      succ_bid = edge[1]
      el = edge[2]
      phis = @fn_ir.blocks[succ_bid].phis
      @a.bind(el)
      stage_base = @local_base + @fn_ir.phi_stage_off
      pi = 0
      while pi < phis.size()
        ph = phis[pi]
        prs = ph.extra
        pk = LLOP_IMM; pv = 0
        j = 0
        while j < prs.size()
          if prs[j][0] == pred_bid
            pk = prs[j][1]; pv = prs[j][2]
            j = prs.size()
          j += 1
        if ph.ty == LLTY_I128 || ph.ty == LLTY_V2I64 || ph.ty == LLTY_OV64
          load_op128(X64_RAX, X64_RDX, pk, pv)
          @a.store64(X64_RAX, X64_RSP, stage_base + pi * 16)
          @a.store64(X64_RDX, X64_RSP, stage_base + pi * 16 + 8)
        elsif ph.ty == LLTY_F64 || ph.ty == LLTY_F32
          load_op_f64(X64_XMM0, pk, pv)
          @a.movsd_store(X64_XMM0, X64_RSP, stage_base + pi * 16)
        else
          load_op64(X64_RAX, pk, pv, ph.ty)
          @a.store64(X64_RAX, X64_RSP, stage_base + pi * 16)
        pi += 1
      pi = 0
      while pi < phis.size()
        ph = phis[pi]
        if ph.ty == LLTY_I128 || ph.ty == LLTY_V2I64 || ph.ty == LLTY_OV64
          @a.load64(X64_RAX, X64_RSP, stage_base + pi * 16)
          @a.load64(X64_RDX, X64_RSP, stage_base + pi * 16 + 8)
          store_val128(ph.dst, X64_RAX, X64_RDX)
        elsif ph.ty == LLTY_F64 || ph.ty == LLTY_F32
          @a.movsd_load(X64_XMM0, X64_RSP, stage_base + pi * 16)
          store_val_f64(ph.dst, X64_XMM0)
        else
          @a.load64(X64_RAX, X64_RSP, stage_base + pi * 16)
          store_val64(ph.dst, X64_RAX)
        pi += 1
      @a.jmp(@blk_labels[succ_bid])
      ei += 1
    nil

  -> emit_prologue
    a = @a
    a.push_r(X64_RBP)
    a.mov_rr(X64_RBP, X64_RSP)
    ri = 0
    while ri < @pushed_regs.size()
      a.push_r(@pushed_regs[ri])
      ri += 1
    a.sub_ri(X64_RSP, @body_frame_bytes) if @body_frame_bytes > 0

    sysv_g = [X64_RDI, X64_RSI, X64_RDX, X64_RCX, X64_R8, X64_R9]
    gi = 0
    fi = 0
    st_idx = 0
    pi = 0
    while pi < @fn_ir.n_params
      pty = @fn_ir.param_tys[pi]
      if pty == LLTY_F64 || pty == LLTY_F32
        if fi < 8
          store_val_f64(pi, fi)
          fi += 1
        else
          a.movsd_load(X64_XMM7, X64_RBP, 16 + st_idx * 8)
          store_val_f64(pi, X64_XMM7)
          st_idx += 1
      else
        if gi < 6
          store_val64(pi, sysv_g[gi])
          gi += 1
        else
          a.load64(X64_RAX, X64_RBP, 16 + st_idx * 8)
          store_val64(pi, X64_RAX)
          st_idx += 1
      pi += 1

    if @fn_ir.uses_ic
      a.addr_tls_linux(X64_R15, ".ic", 0)
    nil

  -> emit_epilogue
    a = @a
    a.bind(@l_epi)
    a.add_ri(X64_RSP, @body_frame_bytes) if @body_frame_bytes > 0
    ri = @pushed_regs.size() - 1
    while ri >= 0
      a.pop_r(@pushed_regs[ri])
      ri -= 1
    a.pop_r(X64_RBP)
    a.ret()
    nil

  # Inline 128-bit unsigned remainder:
  # Inputs: num=(R8=lo, R9=hi), den=(R10=lo, R11=hi) -> Output: rem=(RAX=lo, RDX=hi)
  -> emit_urem_i128
    a = @a
    a.mov_imm64(X64_RAX, 0)
    a.mov_imm64(X64_RDX, 0)
    a.mov_imm64(X64_RCX, 128)
    l_lp = a.new_label()
    l_no_sub = a.new_label()
    a.bind(l_lp)
    # RSI = (R9 >> 63) & 1; R9:R8 <<= 1; RDX:RAX = (RDX:RAX << 1) | RSI
    a.mov_rr(X64_RSI, X64_R9)
    a.shr_ri(X64_RSI, 63)
    a.add_rr(X64_R8, X64_R8)
    a.adc_rr(X64_R9, X64_R9)
    a.add_rr(X64_RAX, X64_RAX)
    a.adc_rr(X64_RDX, X64_RDX)
    a.or_rr(X64_RAX, X64_RSI)
    # Test RDX:RAX >=u R11:R10 via temp RDI:RSI = RDX:RAX - R11:R10
    a.mov_rr(X64_RSI, X64_RAX)
    a.mov_rr(X64_RDI, X64_RDX)
    a.sub_rr(X64_RSI, X64_R10)
    a.sbb_rr(X64_RDI, X64_R11)
    a.jcc(XCC_B, l_no_sub)
    a.mov_rr(X64_RAX, X64_RSI)
    a.mov_rr(X64_RDX, X64_RDI)
    a.bind(l_no_sub)
    a.sub_ri(X64_RCX, 1)
    a.jcc(XCC_NE, l_lp)
    nil

  -> emit_block(bid, blk)
    a = @a
    insts = blk.insts
    ii = 0
    n = insts.size()
    while ii < n
      ins = insts[ii]
      ii += 1
      op = ins.op

      if op == :copy
        if ins.ty == LLTY_I128 || ins.ty == LLTY_V2I64 || ins.ty == LLTY_OV64
          load_op128(X64_RAX, X64_RDX, ins.k0, ins.v0)
          store_val128(ins.dst, X64_RAX, X64_RDX)
        elsif ins.ty == LLTY_F64 || ins.ty == LLTY_F32
          load_op_f64(X64_XMM0, ins.k0, ins.v0)
          store_val_f64(ins.dst, X64_XMM0)
        else
          load_op64(X64_RAX, ins.k0, ins.v0, ins.ty)
          store_val64(ins.dst, X64_RAX)
      elsif op == :umulh
        load_op64(X64_RAX, ins.k0, ins.v0, LLTY_I64)
        load_op64(X64_RCX, ins.k1, ins.v1, LLTY_I64)
        a.mul1_r(X64_RCX)
        store_val64(ins.dst, X64_RDX)
      elsif op == :alloca
        a.lea_mem(X64_RAX, X64_RSP, @local_base + ins.v0)
        store_val64(ins.dst, X64_RAX)
      elsif op == :load
        load_op64(X64_RCX, ins.k0, ins.v0, LLTY_PTR)
        ty = ins.ty
        if ty == LLTY_I64 || ty == LLTY_PTR
          a.load64(X64_RAX, X64_RCX, 0)
          store_val64(ins.dst, X64_RAX)
        elsif ty == LLTY_I32
          a.load32_zext(X64_RAX, X64_RCX, 0)
          store_val64(ins.dst, X64_RAX)
        elsif ty == LLTY_I16
          a.load16_zext(X64_RAX, X64_RCX, 0)
          store_val64(ins.dst, X64_RAX)
        elsif ty == LLTY_I8 || ty == LLTY_I1
          a.load8_zext(X64_RAX, X64_RCX, 0)
          store_val64(ins.dst, X64_RAX)
        elsif ty == LLTY_F64
          a.movsd_load(X64_XMM0, X64_RCX, 0)
          store_val_f64(ins.dst, X64_XMM0)
        elsif ty == LLTY_V2I64 && @do_simd
          a.movups_load(X64_XMM0, X64_RCX, 0)
          a.movups_store(X64_XMM0, X64_RSP, slot_sp_off(ins.dst))
        elsif ty == LLTY_I128 || ty == LLTY_V2I64
          a.load64(X64_RAX, X64_RCX, 0)
          a.load64(X64_RDX, X64_RCX, 8)
          store_val128(ins.dst, X64_RAX, X64_RDX)
      elsif op == :store
        load_op64(X64_RCX, ins.k1, ins.v1, LLTY_PTR)
        ty = ins.ty
        if ty == LLTY_I64 || ty == LLTY_PTR
          load_op64(X64_RAX, ins.k0, ins.v0, ty)
          a.store64(X64_RAX, X64_RCX, 0)
        elsif ty == LLTY_I32
          load_op64(X64_RAX, ins.k0, ins.v0, ty)
          a.store32(X64_RAX, X64_RCX, 0)
        elsif ty == LLTY_I16
          load_op64(X64_RAX, ins.k0, ins.v0, ty)
          a.store16(X64_RAX, X64_RCX, 0)
        elsif ty == LLTY_I8 || ty == LLTY_I1
          load_op64(X64_RAX, ins.k0, ins.v0, ty)
          a.store8(X64_RAX, X64_RCX, 0)
        elsif ty == LLTY_F64
          load_op_f64(X64_XMM0, ins.k0, ins.v0)
          a.movsd_store(X64_XMM0, X64_RCX, 0)
        elsif ty == LLTY_V2I64 && @do_simd && ins.k0 == LLOP_VAL
          a.movups_load(X64_XMM0, X64_RSP, slot_sp_off(ins.v0))
          a.movups_store(X64_XMM0, X64_RCX, 0)
        elsif ty == LLTY_I128 || ty == LLTY_V2I64
          load_op128(X64_RAX, X64_RDX, ins.k0, ins.v0)
          a.store64(X64_RAX, X64_RCX, 0)
          a.store64(X64_RDX, X64_RCX, 8)
      elsif op == :gep
        if ins.k0 == LLOP_SYM && x64_fits_i32?(ins.v1)
          load_sym_addr(X64_RAX, ins.v0, ins.v1)
        else
          load_op64(X64_RAX, ins.k0, ins.v0, LLTY_PTR)
          a.add_ri(X64_RAX, ins.v1) if ins.v1 != 0
        if ins.extra != nil
          si = 0
          while si < ins.extra.size()
            st = ins.extra[si]
            load_op64(X64_RCX, st[0], st[1], LLTY_I64)
            stride = st[2]
            if stride == 1
              a.add_rr(X64_RAX, X64_RCX)
            elsif stride == 2
              a.lea_sib(X64_RAX, X64_RAX, X64_RCX, 1, 0)
            elsif stride == 4
              a.lea_sib(X64_RAX, X64_RAX, X64_RCX, 2, 0)
            elsif stride == 8
              a.lea_sib(X64_RAX, X64_RAX, X64_RCX, 3, 0)
            else
              a.mov_imm64(X64_RDX, stride)
              a.imul_rr(X64_RCX, X64_RDX)
              a.add_rr(X64_RAX, X64_RCX)
            si += 1
        store_val64(ins.dst, X64_RAX)
      elsif op == :add || op == :sub || op == :mul || op == :sdiv || op == :udiv || op == :srem || op == :urem || op == :and || op == :or || op == :xor || op == :shl || op == :ashr || op == :lshr
        ty = ins.ty
        if ty == LLTY_V2I64 && @do_simd && (op == :and || op == :or || op == :xor) && ins.k0 == LLOP_VAL && ins.k1 == LLOP_VAL
          a.movups_load(X64_XMM0, X64_RSP, slot_sp_off(ins.v0))
          a.movups_load(X64_XMM1, X64_RSP, slot_sp_off(ins.v1))
          a.andpd_rr(X64_XMM0, X64_XMM1) if op == :and
          a.orpd_rr(X64_XMM0, X64_XMM1)  if op == :or
          a.xorpd_rr(X64_XMM0, X64_XMM1) if op == :xor
          a.movups_store(X64_XMM0, X64_RSP, slot_sp_off(ins.dst))
        elsif ty == LLTY_I128 || ty == LLTY_V2I64
          load_op128(X64_R8, X64_R9, ins.k0, ins.v0)
          load_op128(X64_R10, X64_R11, ins.k1, ins.v1)
          if op == :add
            a.mov_rr(X64_RAX, X64_R8); a.mov_rr(X64_RDX, X64_R9)
            a.add_rr(X64_RAX, X64_R10); a.adc_rr(X64_RDX, X64_R11)
          elsif op == :sub
            a.mov_rr(X64_RAX, X64_R8); a.mov_rr(X64_RDX, X64_R9)
            a.sub_rr(X64_RAX, X64_R10); a.sbb_rr(X64_RDX, X64_R11)
          elsif op == :and
            a.mov_rr(X64_RAX, X64_R8); a.mov_rr(X64_RDX, X64_R9)
            a.and_rr(X64_RAX, X64_R10); a.and_rr(X64_RDX, X64_R11)
          elsif op == :or
            a.mov_rr(X64_RAX, X64_R8); a.mov_rr(X64_RDX, X64_R9)
            a.or_rr(X64_RAX, X64_R10); a.or_rr(X64_RDX, X64_R11)
          elsif op == :xor
            a.mov_rr(X64_RAX, X64_R8); a.mov_rr(X64_RDX, X64_R9)
            a.xor_rr(X64_RAX, X64_R10); a.xor_rr(X64_RDX, X64_R11)
          elsif op == :mul
            a.mov_rr(X64_RAX, X64_R8)
            a.mul1_r(X64_R10)            # RDX:RAX = R8 *u R10
            a.imul_rr(X64_R8, X64_R11)
            a.add_rr(X64_RDX, X64_R8)
            a.imul_rr(X64_R9, X64_R10)
            a.add_rr(X64_RDX, X64_R9)
          elsif op == :shl
            l_z = a.new_label(); l_ge64 = a.new_label(); l_dn = a.new_label()
            a.cmp_ri(X64_R10, 0); a.jcc(XCC_E, l_z)
            a.cmp_ri(X64_R10, 64); a.jcc(XCC_AE, l_ge64)
            a.mov_rr(X64_RCX, X64_R10)
            a.mov_rr(X64_RAX, X64_R8); a.shl_cl(X64_RAX)
            a.mov_rr(X64_RDX, X64_R9); a.shl_cl(X64_RDX)
            a.mov_imm64(X64_RCX, 64); a.sub_rr(X64_RCX, X64_R10)
            a.mov_rr(X64_RSI, X64_R8); a.shr_cl(X64_RSI)
            a.or_rr(X64_RDX, X64_RSI)
            a.jmp(l_dn)
            a.bind(l_ge64)
            a.mov_rr(X64_RCX, X64_R10); a.sub_ri(X64_RCX, 64)
            a.mov_imm64(X64_RAX, 0)
            a.mov_rr(X64_RDX, X64_R8); a.shl_cl(X64_RDX)
            a.jmp(l_dn)
            a.bind(l_z)
            a.mov_rr(X64_RAX, X64_R8); a.mov_rr(X64_RDX, X64_R9)
            a.bind(l_dn)
          elsif op == :lshr
            l_z = a.new_label(); l_ge64 = a.new_label(); l_dn = a.new_label()
            a.cmp_ri(X64_R10, 0); a.jcc(XCC_E, l_z)
            a.cmp_ri(X64_R10, 64); a.jcc(XCC_AE, l_ge64)
            a.mov_rr(X64_RCX, X64_R10)
            a.mov_rr(X64_RAX, X64_R8); a.shr_cl(X64_RAX)
            a.mov_rr(X64_RDX, X64_R9); a.shr_cl(X64_RDX)
            a.mov_imm64(X64_RCX, 64); a.sub_rr(X64_RCX, X64_R10)
            a.mov_rr(X64_RSI, X64_R9); a.shl_cl(X64_RSI)
            a.or_rr(X64_RAX, X64_RSI)
            a.jmp(l_dn)
            a.bind(l_ge64)
            a.mov_rr(X64_RCX, X64_R10); a.sub_ri(X64_RCX, 64)
            a.mov_rr(X64_RAX, X64_R9); a.shr_cl(X64_RAX)
            a.mov_imm64(X64_RDX, 0)
            a.jmp(l_dn)
            a.bind(l_z)
            a.mov_rr(X64_RAX, X64_R8); a.mov_rr(X64_RDX, X64_R9)
            a.bind(l_dn)
          elsif op == :urem
            emit_urem_i128()
          store_val128(ins.dst, X64_RAX, X64_RDX)
        elsif @do_peephole && (ty == LLTY_I64 || ty == LLTY_PTR) && ins.k1 == LLOP_IMM && (op == :add || op == :sub || op == :and || op == :or || op == :xor) && x64_fits_i32?(ins.v1)
          load_op64(X64_RAX, ins.k0, ins.v0, ty)
          a.add_ri(X64_RAX, ins.v1) if op == :add
          a.sub_ri(X64_RAX, ins.v1) if op == :sub
          a.and_ri(X64_RAX, ins.v1) if op == :and
          a.or_ri(X64_RAX, ins.v1)  if op == :or
          a.xor_ri(X64_RAX, ins.v1) if op == :xor
          store_val64(ins.dst, X64_RAX)
        elsif @do_peephole && (ty == LLTY_I64 || ty == LLTY_PTR) && ins.k1 == LLOP_IMM && (op == :shl || op == :lshr || op == :ashr) && ins.v1 >= 0 && ins.v1 <= 63
          load_op64(X64_RAX, ins.k0, ins.v0, ty)
          a.shl_ri(X64_RAX, ins.v1) if op == :shl
          a.shr_ri(X64_RAX, ins.v1) if op == :lshr
          a.sar_ri(X64_RAX, ins.v1) if op == :ashr
          store_val64(ins.dst, X64_RAX)
        else
          load_op64(X64_RAX, ins.k0, ins.v0, ty)
          load_op64(X64_RCX, ins.k1, ins.v1, ty)
          if ty == LLTY_I32
            if op == :add
              a.add_rr32(X64_RAX, X64_RCX)
            elsif op == :sub
              a.sub_rr32(X64_RAX, X64_RCX)
            elsif op == :mul
              a.imul_rr32(X64_RAX, X64_RCX)
            elsif op == :sdiv || op == :srem
              a.movsxd_32_64(X64_RAX, X64_RAX)
              a.movsxd_32_64(X64_RCX, X64_RCX)
              a.cqo(); a.idiv_r(X64_RCX)
              a.mov_rr(X64_RAX, X64_RDX) if op == :srem
              a.mov_rr32(X64_RAX, X64_RAX)
            elsif op == :udiv || op == :urem
              a.mov_rr32(X64_RAX, X64_RAX); a.mov_rr32(X64_RCX, X64_RCX)
              a.mov_imm64(X64_RDX, 0); a.div_r(X64_RCX)
              a.mov_rr(X64_RAX, X64_RDX) if op == :urem
              a.mov_rr32(X64_RAX, X64_RAX)
            elsif op == :and
              a.and_rr32(X64_RAX, X64_RCX)
            elsif op == :or
              a.or_rr32(X64_RAX, X64_RCX)
            elsif op == :xor
              a.xor_rr32(X64_RAX, X64_RCX)
            elsif op == :shl
              a.shl_cl32(X64_RAX)
            elsif op == :ashr
              a.sar_cl32(X64_RAX)
            elsif op == :lshr
              a.shr_cl32(X64_RAX)
          else
            if op == :add
              a.add_rr(X64_RAX, X64_RCX)
            elsif op == :sub
              a.sub_rr(X64_RAX, X64_RCX)
            elsif op == :mul
              a.imul_rr(X64_RAX, X64_RCX)
            elsif op == :sdiv || op == :srem
              a.cqo(); a.idiv_r(X64_RCX)
              a.mov_rr(X64_RAX, X64_RDX) if op == :srem
            elsif op == :udiv || op == :urem
              a.mov_imm64(X64_RDX, 0); a.div_r(X64_RCX)
              a.mov_rr(X64_RAX, X64_RDX) if op == :urem
            elsif op == :and
              a.and_rr(X64_RAX, X64_RCX)
            elsif op == :or
              a.or_rr(X64_RAX, X64_RCX)
            elsif op == :xor
              a.xor_rr(X64_RAX, X64_RCX)
            elsif op == :shl
              a.shl_cl(X64_RAX)
            elsif op == :ashr
              a.sar_cl(X64_RAX)
            elsif op == :lshr
              a.shr_cl(X64_RAX)
            a.and_ri(X64_RAX, 1) if ty == LLTY_I1
          store_val64(ins.dst, X64_RAX)
      elsif op == :fadd || op == :fsub || op == :fmul || op == :fdiv
        load_op_f64(X64_XMM0, ins.k0, ins.v0)
        load_op_f64(X64_XMM1, ins.k1, ins.v1)
        a.addsd_rr(X64_XMM0, X64_XMM1) if op == :fadd
        a.subsd_rr(X64_XMM0, X64_XMM1) if op == :fsub
        a.mulsd_rr(X64_XMM0, X64_XMM1) if op == :fmul
        a.divsd_rr(X64_XMM0, X64_XMM1) if op == :fdiv
        store_val_f64(ins.dst, X64_XMM0)
      elsif op == :frem
        load_op_f64(X64_XMM0, ins.k0, ins.v0)
        load_op_f64(X64_XMM1, ins.k1, ins.v1)
        @mod_info.intern_sym("fmod", LLSYM_EXT_FN)
        a.call_sym("fmod")
        store_val_f64(ins.dst, X64_XMM0)
      elsif op == :icmp
        ty = ins.ty
        if ty == LLTY_I128
          load_op128(X64_R8, X64_R9, ins.k0, ins.v0)
          load_op128(X64_R10, X64_R11, ins.k1, ins.v1)
          p = ins.pred
          if p == :slt
            a.sub_rr(X64_R8, X64_R10); a.sbb_rr(X64_R9, X64_R11); a.setcc_zext(XCC_L, X64_RAX)
          elsif p == :ugt
            a.sub_rr(X64_R10, X64_R8); a.sbb_rr(X64_R11, X64_R9); a.setcc_zext(XCC_B, X64_RAX)
          elsif p == :ult
            a.sub_rr(X64_R8, X64_R10); a.sbb_rr(X64_R9, X64_R11); a.setcc_zext(XCC_B, X64_RAX)
          elsif p == :eq
            a.xor_rr(X64_R8, X64_R10); a.xor_rr(X64_R9, X64_R11); a.or_rr(X64_R8, X64_R9)
            a.cmp_ri(X64_R8, 0); a.setcc_zext(XCC_E, X64_RAX)
          else
            a.xor_rr(X64_R8, X64_R10); a.xor_rr(X64_R9, X64_R11); a.or_rr(X64_R8, X64_R9)
            a.cmp_ri(X64_R8, 0); a.setcc_zext(XCC_NE, X64_RAX)
          store_val64(ins.dst, X64_RAX)
        else
          load_op64(X64_RAX, ins.k0, ins.v0, ty)
          if @do_peephole && (ty == LLTY_I64 || ty == LLTY_PTR) && ins.k1 == LLOP_IMM && x64_fits_i32?(ins.v1)
            a.cmp_ri(X64_RAX, ins.v1)
          else
            load_op64(X64_RCX, ins.k1, ins.v1, ty)
            if ty == LLTY_I8
              is_s = ins.pred == :slt || ins.pred == :sle || ins.pred == :sgt || ins.pred == :sge
              if is_s
                a.movsx_8_64(X64_RAX, X64_RAX); a.movsx_8_64(X64_RCX, X64_RCX)
              else
                a.movzx_8_64(X64_RAX, X64_RAX); a.movzx_8_64(X64_RCX, X64_RCX)
              a.cmp_rr(X64_RAX, X64_RCX)
            elsif ty == LLTY_I16
              is_s = ins.pred == :slt || ins.pred == :sle || ins.pred == :sgt || ins.pred == :sge
              if is_s
                a.movsx_16_64(X64_RAX, X64_RAX); a.movsx_16_64(X64_RCX, X64_RCX)
              else
                a.movzx_16_64(X64_RAX, X64_RAX); a.movzx_16_64(X64_RCX, X64_RCX)
              a.cmp_rr(X64_RAX, X64_RCX)
            elsif ty == LLTY_I32
              a.cmp_rr32(X64_RAX, X64_RCX)
            else
              a.cmp_rr(X64_RAX, X64_RCX)
          cc = llx64_icmp_cc(ins.pred)
          if @do_peephole && ii < n && @fn_ir.val_uses != nil && @fn_ir.val_uses[ins.dst] == 1 && insts[ii].op == :cond_br && insts[ii].k0 == LLOP_VAL && insts[ii].v0 == ins.dst
            cbr = insts[ii]
            ii += 1
            a.jcc(cc, branch_target_label(bid, cbr.v1))
            a.jmp(branch_target_label(bid, cbr.v2))
          else
            a.setcc_zext(cc, X64_RAX)
            store_val64(ins.dst, X64_RAX)
      elsif op == :fcmp
        load_op_f64(X64_XMM0, ins.k0, ins.v0)
        load_op_f64(X64_XMM1, ins.k1, ins.v1)
        p = ins.pred
        if p == :olt
          a.ucomisd_rr(X64_XMM1, X64_XMM0); a.setcc_zext(XCC_A, X64_RAX)
        elsif p == :ole
          a.ucomisd_rr(X64_XMM1, X64_XMM0); a.setcc_zext(XCC_AE, X64_RAX)
        elsif p == :ogt
          a.ucomisd_rr(X64_XMM0, X64_XMM1); a.setcc_zext(XCC_A, X64_RAX)
        elsif p == :oge
          a.ucomisd_rr(X64_XMM0, X64_XMM1); a.setcc_zext(XCC_AE, X64_RAX)
        elsif p == :oeq
          a.ucomisd_rr(X64_XMM0, X64_XMM1)
          a.setcc_zext(XCC_E, X64_RAX); a.setcc_zext(XCC_NP, X64_RCX); a.and_rr(X64_RAX, X64_RCX)
        elsif p == :one
          a.ucomisd_rr(X64_XMM0, X64_XMM1)
          a.setcc_zext(XCC_NE, X64_RAX); a.setcc_zext(XCC_NP, X64_RCX); a.and_rr(X64_RAX, X64_RCX)
        elsif p == :ord
          a.ucomisd_rr(X64_XMM0, X64_XMM1); a.setcc_zext(XCC_NP, X64_RAX)
        elsif p == :uno
          a.ucomisd_rr(X64_XMM0, X64_XMM1); a.setcc_zext(XCC_P, X64_RAX)
        else
          a.ucomisd_rr(X64_XMM0, X64_XMM1)
          a.setcc_zext(XCC_NE, X64_RAX); a.setcc_zext(XCC_P, X64_RCX); a.or_rr(X64_RAX, X64_RCX)
        store_val64(ins.dst, X64_RAX)
      elsif op == :select
        load_op64(X64_RDX, ins.k0, ins.v0, LLTY_I1)
        if ins.ty == LLTY_F64 || ins.ty == LLTY_F32
          load_op_f64(X64_XMM0, ins.k1, ins.v1)
          load_op_f64(X64_XMM1, ins.k2, ins.v2)
          l_st = a.new_label()
          a.cmp_ri(X64_RDX, 0)
          a.jcc(XCC_NE, l_st)
          a.movsd_rr(X64_XMM0, X64_XMM1)
          a.bind(l_st)
          store_val_f64(ins.dst, X64_XMM0)
        else
          load_op64(X64_RAX, ins.k1, ins.v1, ins.ty)
          load_op64(X64_RCX, ins.k2, ins.v2, ins.ty)
          a.cmp_ri(X64_RDX, 0)
          a.cmovcc(XCC_E, X64_RAX, X64_RCX)
          store_val64(ins.dst, X64_RAX)
      elsif op == :sext
        if ins.ty == LLTY_I128
          load_op64(X64_RAX, ins.k0, ins.v0, ins.ty2)
          a.movsxd_32_64(X64_RAX, X64_RAX) if ins.ty2 == LLTY_I32
          a.cqo()
          store_val128(ins.dst, X64_RAX, X64_RDX)
        else
          load_op64(X64_RAX, ins.k0, ins.v0, ins.ty2)
          if ins.ty2 == LLTY_I1
            a.and_ri(X64_RAX, 1); a.neg_r(X64_RAX)
          elsif ins.ty2 == LLTY_I8
            a.movsx_8_64(X64_RAX, X64_RAX)
          elsif ins.ty2 == LLTY_I16
            a.movsx_16_64(X64_RAX, X64_RAX)
          elsif ins.ty2 == LLTY_I32
            a.movsxd_32_64(X64_RAX, X64_RAX)
          store_val64(ins.dst, X64_RAX)
      elsif op == :zext
        if @do_peephole && @fn_ir.val_uses != nil && ins.ty == LLTY_I128 && ins.ty2 == LLTY_I64 && ii + 3 < n
          i1 = insts[ii]; i2 = insts[ii + 1]; i3 = insts[ii + 2]; i4 = insts[ii + 3]
          if @fn_ir.val_uses[ins.dst] == 1 && i1.op == :zext && i1.ty == LLTY_I128 && i1.ty2 == LLTY_I64 && @fn_ir.val_uses[i1.dst] == 1 && (i2.op == :mul || i2.op == :add || i2.op == :sub) && i2.ty == LLTY_I128 && @fn_ir.val_uses[i2.dst] == 1 && i2.k0 == LLOP_VAL && i2.v0 == ins.dst && i2.k1 == LLOP_VAL && i2.v1 == i1.dst && i3.op == :lshr && i3.ty == LLTY_I128 && @fn_ir.val_uses[i3.dst] == 1 && i3.k0 == LLOP_VAL && i3.v0 == i2.dst && i3.k1 == LLOP_IMM && i4.op == :trunc && i4.ty == LLTY_I64 && i4.ty2 == LLTY_I128 && i4.k0 == LLOP_VAL && i4.v0 == i3.dst && ((i2.op != :sub && i3.v1 == 64) || (i2.op == :sub && i3.v1 == 127))
            load_op64(X64_RAX, ins.k0, ins.v0, LLTY_I64)
            load_op64(X64_RCX, i1.k0, i1.v0, LLTY_I64)
            if i2.op == :mul
              a.mul1_r(X64_RCX)
              store_val64(i4.dst, X64_RDX)
            elsif i2.op == :add
              a.add_rr(X64_RAX, X64_RCX)
              a.setcc_zext(XCC_B, X64_RAX)
              store_val64(i4.dst, X64_RAX)
            else
              a.cmp_rr(X64_RAX, X64_RCX)
              a.setcc_zext(XCC_B, X64_RAX)
              store_val64(i4.dst, X64_RAX)
            ii += 4
            next
        if @do_peephole && @fn_ir.val_uses != nil && ins.ty == LLTY_I128 && ins.ty2 == LLTY_I64 && ii + 1 < n
          i1 = insts[ii]; i2 = insts[ii + 1]
          if @fn_ir.val_uses[ins.dst] == 1 && i1.op == :zext && i1.ty == LLTY_I128 && i1.ty2 == LLTY_I64 && @fn_ir.val_uses[i1.dst] == 1 && i2.op == :mul && i2.ty == LLTY_I128 && i2.k0 == LLOP_VAL && i2.v0 == ins.dst && i2.k1 == LLOP_VAL && i2.v1 == i1.dst
            load_op64(X64_RAX, ins.k0, ins.v0, LLTY_I64)
            load_op64(X64_RCX, i1.k0, i1.v0, LLTY_I64)
            a.mul1_r(X64_RCX)
            store_val128(i2.dst, X64_RAX, X64_RDX)
            ii += 2
            next
        if ins.ty == LLTY_I128
          load_op64(X64_RAX, ins.k0, ins.v0, ins.ty2)
          a.and_ri(X64_RAX, 1)            if ins.ty2 == LLTY_I1
          a.mov_rr32(X64_RAX, X64_RAX)    if ins.ty2 == LLTY_I32
          a.mov_imm64(X64_RDX, 0)
          store_val128(ins.dst, X64_RAX, X64_RDX)
        else
          load_op64(X64_RAX, ins.k0, ins.v0, ins.ty2)
          a.and_ri(X64_RAX, 1)            if ins.ty2 == LLTY_I1
          a.movzx_8_64(X64_RAX, X64_RAX)  if ins.ty2 == LLTY_I8
          a.movzx_16_64(X64_RAX, X64_RAX) if ins.ty2 == LLTY_I16
          a.mov_rr32(X64_RAX, X64_RAX)    if ins.ty2 == LLTY_I32
          store_val64(ins.dst, X64_RAX)
      elsif op == :trunc
        if ins.ty2 == LLTY_I128
          load_op128(X64_RAX, X64_RDX, ins.k0, ins.v0)
        else
          load_op64(X64_RAX, ins.k0, ins.v0, ins.ty2)
        a.and_ri(X64_RAX, 1)            if ins.ty == LLTY_I1
        a.movzx_8_64(X64_RAX, X64_RAX)  if ins.ty == LLTY_I8
        a.movzx_16_64(X64_RAX, X64_RAX) if ins.ty == LLTY_I16
        a.mov_rr32(X64_RAX, X64_RAX)    if ins.ty == LLTY_I32
        store_val64(ins.dst, X64_RAX)
      elsif op == :inttoptr || op == :ptrtoint
        load_op64(X64_RAX, ins.k0, ins.v0, LLTY_I64)
        store_val64(ins.dst, X64_RAX)
      elsif op == :bitcast
        if ins.ty == LLTY_F64 && (ins.ty2 == LLTY_I64 || ins.ty2 == LLTY_PTR)
          load_op64(X64_RAX, ins.k0, ins.v0, LLTY_I64)
          a.movq_x_r(X64_XMM0, X64_RAX)
          store_val_f64(ins.dst, X64_XMM0)
        elsif (ins.ty == LLTY_I64 || ins.ty == LLTY_PTR) && ins.ty2 == LLTY_F64
          load_op_f64(X64_XMM0, ins.k0, ins.v0)
          a.movq_r_x(X64_RAX, X64_XMM0)
          store_val64(ins.dst, X64_RAX)
        else
          load_op64(X64_RAX, ins.k0, ins.v0, LLTY_I64)
          store_val64(ins.dst, X64_RAX)
      elsif op == :sitofp
        load_op64(X64_RAX, ins.k0, ins.v0, ins.ty2)
        ins.ty2 == LLTY_I32 ? a.cvtsi2sd_x_r32(X64_XMM0, X64_RAX) : a.cvtsi2sd_x_r64(X64_XMM0, X64_RAX)
        store_val_f64(ins.dst, X64_XMM0)
      elsif op == :uitofp
        load_op64(X64_RAX, ins.k0, ins.v0, ins.ty2)
        if ins.ty2 == LLTY_I32
          a.mov_rr32(X64_RAX, X64_RAX)
          a.cvtsi2sd_x_r64(X64_XMM0, X64_RAX)
        else
          l_hi = a.new_label(); l_ud = a.new_label()
          a.test_rr(X64_RAX, X64_RAX)
          a.jcc(XCC_S, l_hi)
          a.cvtsi2sd_x_r64(X64_XMM0, X64_RAX)
          a.jmp(l_ud)
          a.bind(l_hi)
          a.mov_rr(X64_RCX, X64_RAX)
          a.shr_ri(X64_RAX, 1)
          a.and_ri(X64_RCX, 1)
          a.or_rr(X64_RAX, X64_RCX)
          a.cvtsi2sd_x_r64(X64_XMM0, X64_RAX)
          a.addsd_rr(X64_XMM0, X64_XMM0)
          a.bind(l_ud)
        store_val_f64(ins.dst, X64_XMM0)
      elsif op == :fptosi
        load_op_f64(X64_XMM0, ins.k0, ins.v0)
        ins.ty == LLTY_I32 ? a.cvttsd2si_r32_x(X64_RAX, X64_XMM0) : a.cvttsd2si_r64_x(X64_RAX, X64_XMM0)
        store_val64(ins.dst, X64_RAX)
      elsif op == :fptoui
        # Handle unsigned 64-bit doubles >= 2^63 cleanly!
        load_op_f64(X64_XMM0, ins.k0, ins.v0)
        if ins.ty == LLTY_I32
          a.cvttsd2si_r64_x(X64_RAX, X64_XMM0)
          a.mov_rr32(X64_RAX, X64_RAX)
        else
          a.mov_imm64(X64_RCX, 0x43E0000000000000)   # 2^63 in IEEE 754 f64
          a.movq_x_r(X64_XMM1, X64_RCX)
          l_big = a.new_label(); l_fd = a.new_label()
          a.ucomisd_rr(X64_XMM0, X64_XMM1)
          a.jcc(XCC_AE, l_big)
          a.cvttsd2si_r64_x(X64_RAX, X64_XMM0)
          a.jmp(l_fd)
          a.bind(l_big)
          a.subsd_rr(X64_XMM0, X64_XMM1)
          a.cvttsd2si_r64_x(X64_RAX, X64_XMM0)
          a.mov_imm64(X64_RCX, -9223372036854775808)
          a.xor_rr(X64_RAX, X64_RCX)
          a.bind(l_fd)
        store_val64(ins.dst, X64_RAX)
      elsif op == :extractvalue || op == :extractelement
        off = slot_sp_off(ins.v0) + (ins.v1 == 1 ? 8 : 0)
        a.load64(X64_RAX, X64_RSP, off)
        store_val64(ins.dst, X64_RAX)
      elsif op == :intrinsic
        intr = ins.pred
        cargs = ins.extra
        if intr == "smul.with.overflow.i64"
          load_op64(X64_RAX, cargs[0][1], cargs[0][2], LLTY_I64)
          load_op64(X64_RCX, cargs[1][1], cargs[1][2], LLTY_I64)
          a.imul1_r(X64_RCX)
          a.setcc_zext(XCC_O, X64_RCX)
          store_val128(ins.dst, X64_RAX, X64_RCX)
        elsif intr == "cttz.i64"
          # Baseline x86_64-v1 safe: BSF + 64-on-zero!
          load_op64(X64_RCX, cargs[0][1], cargs[0][2], LLTY_I64)
          a.mov_imm64(X64_RDX, 64)
          a.bsf_r(X64_RAX, X64_RCX)
          a.test_rr(X64_RCX, X64_RCX)
          a.cmovcc(XCC_E, X64_RAX, X64_RDX)
          store_val64(ins.dst, X64_RAX)
        elsif intr == "ctlz.i64"
          # Baseline x86_64-v1 safe: BSR ^ 63, or 64 when 0!
          load_op64(X64_RCX, cargs[0][1], cargs[0][2], LLTY_I64)
          l_z = a.new_label(); l_dn = a.new_label()
          a.test_rr(X64_RCX, X64_RCX)
          a.jcc(XCC_E, l_z)
          a.bsr_r(X64_RAX, X64_RCX)
          a.xor_ri(X64_RAX, 63)
          a.jmp(l_dn)
          a.bind(l_z)
          a.mov_imm64(X64_RAX, 64)
          a.bind(l_dn)
          store_val64(ins.dst, X64_RAX)
        elsif intr == "ctpop.i64"
          # SWAR 64-bit popcount (100% baseline x86_64-v1 compatible!)
          load_op64(X64_RAX, cargs[0][1], cargs[0][2], LLTY_I64)
          a.mov_rr(X64_RCX, X64_RAX); a.shr_ri(X64_RCX, 1)
          a.mov_imm64(X64_RDX, 0x5555555555555555); a.and_rr(X64_RCX, X64_RDX); a.sub_rr(X64_RAX, X64_RCX)
          a.mov_imm64(X64_RDX, 0x3333333333333333)
          a.mov_rr(X64_RCX, X64_RAX); a.shr_ri(X64_RCX, 2); a.and_rr(X64_RAX, X64_RDX); a.and_rr(X64_RCX, X64_RDX); a.add_rr(X64_RAX, X64_RCX)
          a.mov_rr(X64_RCX, X64_RAX); a.shr_ri(X64_RCX, 4); a.add_rr(X64_RAX, X64_RCX)
          a.mov_imm64(X64_RDX, 0x0F0F0F0F0F0F0F0F); a.and_rr(X64_RAX, X64_RDX)
          a.mov_imm64(X64_RDX, 0x0101010101010101); a.imul_rr(X64_RAX, X64_RDX); a.shr_ri(X64_RAX, 56)
          store_val64(ins.dst, X64_RAX)
        elsif intr == "sqrt.f64"
          load_op_f64(X64_XMM0, cargs[0][1], cargs[0][2])
          a.sqrtsd_rr(X64_XMM0, X64_XMM0)
          store_val_f64(ins.dst, X64_XMM0)
        elsif intr == "fmuladd.f64"
          load_op_f64(X64_XMM0, cargs[0][1], cargs[0][2])
          load_op_f64(X64_XMM1, cargs[1][1], cargs[1][2])
          load_op_f64(X64_XMM2, cargs[2][1], cargs[2][2])
          a.mulsd_rr(X64_XMM0, X64_XMM1)
          a.addsd_rr(X64_XMM0, X64_XMM2)
          store_val_f64(ins.dst, X64_XMM0)
        elsif intr == "memcpy.p0.p0.i64"
          load_op64(X64_RDI, cargs[0][1], cargs[0][2], LLTY_PTR)
          load_op64(X64_RSI, cargs[1][1], cargs[1][2], LLTY_PTR)
          load_op64(X64_RDX, cargs[2][1], cargs[2][2], LLTY_I64)
          @mod_info.intern_sym("memcpy", LLSYM_EXT_FN)
          a.call_sym("memcpy")
      elsif op == :call
        cargs = ins.extra
        sysv_g = [X64_RDI, X64_RSI, X64_RDX, X64_RCX, X64_R8, X64_R9]
        reg_g_ops = []
        reg_f_ops = []
        st_idx = 0
        ai = 0
        while ai < cargs.size()
          ca = cargs[ai]
          aty = ca[0]
          if aty == LLTY_F64 || aty == LLTY_F32
            if reg_f_ops.size() < 8
              reg_f_ops.push(ca)
            else
              load_op_f64(X64_XMM7, ca[1], ca[2])
              a.movsd_store(X64_XMM7, X64_RSP, st_idx * 8)
              st_idx += 1
          else
            if reg_g_ops.size() < 6
              reg_g_ops.push(ca)
            else
              load_op64(X64_RAX, ca[1], ca[2], aty)
              a.store64(X64_RAX, X64_RSP, st_idx * 8)
              st_idx += 1
          ai += 1

        # Load indirect callee into R10 before populating arg registers
        if ins.k0 != LLOP_SYM
          load_op64(X64_R10, ins.k0, ins.v0, LLTY_PTR)

        fi = 0
        while fi < reg_f_ops.size()
          load_op_f64(fi, reg_f_ops[fi][1], reg_f_ops[fi][2])
          fi += 1

        gi = reg_g_ops.size() - 1
        while gi >= 0
          ca = reg_g_ops[gi]
          load_op64(sysv_g[gi], ca[1], ca[2], ca[0])
          gi -= 1

        # Set AL = # of XMM register args (System V varargs convention — e.g. snprintf / printf in runtime!)
        a.mov_imm64(X64_RAX, reg_f_ops.size()) if reg_f_ops.size() > 0 || ins.k0 == LLOP_SYM

        if ins.k0 == LLOP_SYM
          a.call_sym(@mod_info.sym_list[ins.v0])
        else
          a.call_r(X64_R10)

        if ins.dst >= 0 && ins.ty != LLTY_VOID
          if ins.ty == LLTY_I128
            store_val128(ins.dst, X64_RAX, X64_RDX)
          elsif ins.ty == LLTY_F64 || ins.ty == LLTY_F32
            store_val_f64(ins.dst, X64_XMM0)
          else
            store_val64(ins.dst, X64_RAX)
      elsif op == :br
        a.jmp(branch_target_label(bid, ins.v0))
      elsif op == :cond_br
        load_op64(X64_RAX, ins.k0, ins.v0, LLTY_I1)
        a.cmp_ri(X64_RAX, 0)
        a.jcc(XCC_NE, branch_target_label(bid, ins.v1))
        a.jmp(branch_target_label(bid, ins.v2))
      elsif op == :switch
        load_op64(X64_RAX, ins.k0, ins.v0, ins.ty)
        cases = ins.extra
        ci = 0
        while ci < cases.size()
          cv = cases[ci][0]
          cb = cases[ci][1]
          if x64_fits_i32?(cv)
            a.cmp_ri(X64_RAX, cv)
          else
            a.mov_imm64(X64_RCX, cv)
            a.cmp_rr(X64_RAX, X64_RCX)
          a.jcc(XCC_E, branch_target_label(bid, cb))
          ci += 1
        a.jmp(branch_target_label(bid, ins.v1))
      elsif op == :ret_void
        a.jmp(@l_epi)
      elsif op == :ret
        if ins.ty == LLTY_I128
          load_op128(X64_RAX, X64_RDX, ins.k0, ins.v0)
        elsif ins.ty == LLTY_F64 || ins.ty == LLTY_F32
          load_op_f64(X64_XMM0, ins.k0, ins.v0)
        else
          load_op64(X64_RAX, ins.k0, ins.v0, ins.ty)
        a.jmp(@l_epi)
      elsif op == :unreachable
        a.ud2()
    nil

  -> compile
    compute_layout()
    bi = 0
    while bi < @fn_ir.blocks.size()
      @blk_labels.push(@a.new_label())
      bi += 1
    @l_epi = @a.new_label()
    emit_prologue()
    bi = 0
    while bi < @fn_ir.blocks.size()
      @a.bind(@blk_labels[bi])
      emit_block(bi, @fn_ir.blocks[bi])
      bi += 1
    emit_phi_edge_thunks()
    emit_epilogue()
    if !@a.patch_fixups()
      raise "Cinder LL->X64 fixup failed in function " + @fn_ir.name
    @a

-> llx64_emit_func_to_writer(writer, fn_ir, fa, fn_offsets, ref_syms)
  writer.text.align_to(16, 0x90)
  fn_off = writer.text.len
  fn_sz = fa.byte_len()
  writer.text.put_buf(fa.buf)
  fn_offsets[fn_ir.name] = [fn_off, fn_sz]
  writer.define_sym(fn_ir.name, ESEC_TEXT, fn_off, fn_sz, fn_ir.is_internal ? ESYM_LOCAL : ESYM_GLOBAL, ESTT_FUNC)
  ri = 0
  while ri < fa.rel_off.size()
    rsym = fa.rel_sym[ri]
    ref_syms[rsym] = true
    writer.add_text_reloc(fn_off + fa.rel_off[ri], rsym, fa.rel_kind[ri], fa.rel_add[ri])
    ri += 1
  nil

-> cinder_compile_ll_x64(src, opt_cfg = nil)
  cfg = opt_cfg != nil ? opt_cfg : cinder_opt_from_env(2)
  src = src + "                        " if cinder_blen(src) <= 16
  writer = Elf64Writer.new(ELF_EM_X86_64)
  mod_info = ll_scan_module_and_emit_globals(src, writer, false)
  src_ptr = cinder_heap_str_ptr(wvalue_bits(src) ## i64)
  inl_ctx = LLInlineContext.new(src, src_ptr, mod_info, cfg)

  fn_offsets = {}
  ref_syms = {}
  mod_info.used_syms.each ->(unm) ref_syms[unm] = true
  mod_info.aliases.each ->(al) ref_syms[al[1]] = true
  writer.ro_rel_sym.each   ->(rs) ref_syms[rs] = true
  writer.data_rel_sym.each ->(rs) ref_syms[rs] = true

  drop_dead_inl = !cfg.debug && cfg.pass_enabled?("dce") && cfg.pass_enabled?("always-inline")
  deferred_spans = []
  fi = 0
  while fi < mod_info.fn_spans.size()
    span = mod_info.fn_spans[fi]
    hdr = span[0]
    is_int_hdr = hdr.index(" internal ") != nil || hdr.index(" private ") != nil
    if drop_dead_inl && is_int_hdr && inl_ctx.span_is_alwaysinline?(span)
      deferred_spans.push(span)
    else
      fn_ir = ll_parse_function(src, src_ptr, mod_info, span, false)
      ll_opt_function(fn_ir, inl_ctx, cfg)
      fc = LLX64FuncCompiler.new(fn_ir, mod_info, cfg)
      fa = fc.compile()
      llx64_emit_func_to_writer(writer, fn_ir, fa, fn_offsets, ref_syms)
    fi += 1

  di = 0
  while di < deferred_spans.size()
    dspan = deferred_spans[di]
    dhdr = dspan[0]
    dat = ll_index_outside_quotes(dhdr, 64, 0)
    dlp = ll_index_outside_quotes(dhdr, 40, dat)
    dnm = ll_clean_sym(dhdr.slice(dat, dlp - dat))
    if ref_syms[dnm] == true
      fn_ir = ll_parse_function(src, src_ptr, mod_info, dspan, false)
      ll_opt_function(fn_ir, inl_ctx, cfg)
      fc = LLX64FuncCompiler.new(fn_ir, mod_info, cfg)
      fa = fc.compile()
      llx64_emit_func_to_writer(writer, fn_ir, fa, fn_offsets, ref_syms)
    di += 1

  ai = 0
  while ai < mod_info.aliases.size()
    al_nm = mod_info.aliases[ai][0]
    tg_nm = mod_info.aliases[ai][1]
    info = fn_offsets[tg_nm]
    if info != nil
      writer.define_sym(al_nm, ESEC_TEXT, info[0], info[1], ESYM_HIDDEN, ESTT_FUNC)
    ai += 1

  cfg.print_report("aot-x64") if cfg.print_passes
  writer
