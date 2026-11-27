# cinder/ll_a64 — Pure-Tungsten LLVM IR (.ll) -> ARM64 Machine Code & Object Compiler.
#
# Compiles an entire Tungsten `.ll` module directly into a `MachO64Writer` (macOS ARM64)
# or `Elf64Writer` (Linux AArch64) without invoking `clang`, `llc`, `opt`, or `as`.

use ./buf
use ./a64
use ./a64_asm
use ./macho64
use ./elf64
use ./ll_parser
use ./opt_config
use ./ll_opt

-> lla64_icmp_cc(pred)
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

# Sort `[[slot_off, uses], ...]` descending by `uses`, breaking ties by ascending `slot_off` for 100% determinism!
-> lla64_sort_slot_candidates(cands)
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

+ LLA64FuncCompiler
  rw :fn_ir, :mod_info, :is_macho, :opt_cfg, :rodata_buf, :a
  rw :out_arg_bytes, :local_base, :save_off, :save_bytes, :asm_spill_off, :body_frame_bytes
  rw :has_inline_asm, :has_any_call, :has_wide128, :omit_frame
  rw :do_peephole, :do_simd, :slot_reg_g, :slot_reg_f, :vec_reg_q, :used_cs_g, :used_cs_f
  rw :blk_labels, :l_epi, :edge_labels, :edge_list

  -> new(@fn_ir, @mod_info, @is_macho, @opt_cfg = nil, @rodata_buf = nil)
    @opt_cfg = CinderOptConfig.new(2) if @opt_cfg == nil
    @a = CinderA64.new(@fn_ir.blocks.size() * 32 + 64)
    @out_arg_bytes = 0
    @local_base = 0
    @save_off = 0
    @save_bytes = 0
    @asm_spill_off = 0
    @body_frame_bytes = 0
    @has_inline_asm = false
    @has_any_call = false
    @has_wide128 = false
    @omit_frame = false
    @do_peephole = @opt_cfg.pass_enabled?("peephole")
    @do_simd = @opt_cfg.pass_enabled?("simd")
    @slot_reg_g = {}
    @slot_reg_f = {}
    @vec_reg_q = {}
    @used_cs_g = []
    @used_cs_f = []
    @blk_labels = []
    @l_epi = -1
    @edge_labels = {}
    @edge_list = []

  -> check_sym_tls_call(k, v)
    if k == LLOP_SYM && @mod_info.sym_kind[v] == LLSYM_TLS && !(v == @fn_ir.ic_sym_id && @fn_ir.uses_ic)
      @has_any_call = true
    nil

  -> compute_layout
    # Scan instructions for outgoing stack args, calls, TLS helpers, inline asm, and 128-bit ops
    max_stack_args = 0
    max_phis = 0
    vi = 0
    while vi < @fn_ir.n_vals
      vt = @fn_ir.val_tys[vi]
      @has_wide128 = true if vt == LLTY_I128 || vt == LLTY_V2I64 || vt == LLTY_OV64
      vi += 1

    bi = 0
    while bi < @fn_ir.blocks.size()
      blk = @fn_ir.blocks[bi]
      max_phis = blk.phis.size() if blk.phis.size() > max_phis
      ii = 0
      while ii < blk.insts.size()
        ins = blk.insts[ii]
        op = ins.op
        check_sym_tls_call(ins.k0, ins.v0)
        check_sym_tls_call(ins.k1, ins.v1)
        check_sym_tls_call(ins.k2, ins.v2)
        if op == :call_asm
          @has_inline_asm = true if ins.extra[0] != ""
        elsif op == :frem
          @has_any_call = true
        elsif op == :intrinsic && ins.pred == "memcpy.p0.p0.i64"
          @has_any_call = true
        elsif op == :call
          @has_any_call = true
          if ins.extra != nil
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
                if gi < 8
                  gi += 1
                else
                  st_n += 1
              ai += 1
            max_stack_args = st_n if st_n > max_stack_args
        ii += 1
      bi += 1

    # Check incoming stack parameters (`> 8` GPR or `> 8` FP params require FP-relative stack access)
    has_in_stack_params = false
    pg = 0; pf = 0; pi = 0
    while pi < @fn_ir.n_params
      pty = @fn_ir.param_tys[pi]
      if pty == LLTY_F64 || pty == LLTY_F32
        pf += 1
        has_in_stack_params = true if pf > 8
      else
        pg += 1
        has_in_stack_params = true if pg > 8
      pi += 1

    # Promote hottest scalar slots into hardware registers when `-freg-promote` is active!
    if @opt_cfg.pass_enabled?("reg-promote") && !@fn_ir.is_preserve_most && @fn_ir.slot_is_fp != nil
      g_cands = []
      f_cands = []
      off = ((@fn_ir.alloca_bytes + 15) / 16) * 16
      while off < @fn_ir.phi_stage_off
        kind_fp = @fn_ir.slot_is_fp[off]
        if kind_fp == false
          g_cands.push([off, @fn_ir.slot_uses[off]])
        elsif kind_fp == true && !@has_inline_asm
          f_cands.push([off, @fn_ir.slot_uses[off]])
        off += 8
      lla64_sort_slot_candidates(g_cands)
      lla64_sort_slot_candidates(f_cands)

      # Zero-frame pure 64-bit leaf fast path (`R_X12..R_X15`, zero `stp fp, lr`, zero `sp` adjustment!)
      can_leaf = @opt_cfg.pass_enabled?("leaf-frame-elim") && !@opt_cfg.debug && !@opt_cfg.frame_pointers && !@has_any_call && !@has_inline_asm && !@fn_ir.uses_ic && !@has_wide128 && !has_in_stack_params && @fn_ir.alloca_bytes == 0 && max_phis == 0 && g_cands.size() <= 4 && f_cands.size() == 0
      if can_leaf
        leaf_regs = [R_X12, R_X13, R_X14, R_X15]
        li = 0
        while li < g_cands.size()
          @slot_reg_g[g_cands[li][0]] = leaf_regs[li]
          li += 1
        @omit_frame = true
        @out_arg_bytes = 0
        @local_base = 0
        @save_off = 0
        @save_bytes = 0
        @asm_spill_off = 0
        @body_frame_bytes = 0
        return nil

      cs_g_pool = [R_X19, R_X20, R_X21, R_X22, R_X23, R_X24, R_X25, R_X26]
      cs_f_pool = [R_D8, R_D9, R_D10, R_D11, R_D12, R_D13, R_D14, R_D15]
      gi = 0
      while gi < g_cands.size() && gi < cs_g_pool.size()
        r = cs_g_pool[gi]
        @slot_reg_g[g_cands[gi][0]] = r
        @used_cs_g.push(r)
        gi += 1
      fi = 0
      while fi < f_cands.size() && fi < cs_f_pool.size()
        r = cs_f_pool[fi]
        @slot_reg_f[f_cands[fi][0]] = r
        @used_cs_f.push(r)
        fi += 1

    # Promote intra-block call-free `<2 x i64>` (`LLTY_V2I64`) SSA vectors directly to NEON `v16..v31`!
    if @do_simd && @has_wide128
      v2_def_blk = {}
      no_qreg = {}
      bi = 0
      while bi < @fn_ir.blocks.size()
        blk = @fn_ir.blocks[bi]
        blk.phis.each ->(ph)
          no_qreg[ph.dst] = true if ph.dst >= 0
          prs = ph.extra
          pk = 0
          while pk < prs.size()
            no_qreg[prs[pk][2]] = true if prs[pk][1] == LLOP_VAL
            pk += 1
        ii = 0
        while ii < blk.insts.size()
          ins = blk.insts[ii]
          if ins.dst >= 0 && @fn_ir.val_tys[ins.dst] == LLTY_V2I64
            if ins.op == :load || ins.op == :and || ins.op == :or || ins.op == :xor
              v2_def_blk[ins.dst] = bi
            else
              no_qreg[ins.dst] = true
          if ins.op == :extractelement || ins.op == :extractvalue
            no_qreg[ins.v0] = true if ins.k0 == LLOP_VAL
          else
            no_qreg[ins.v0] = true if ins.k0 == LLOP_VAL && v2_def_blk[ins.v0] != nil && v2_def_blk[ins.v0] != bi
            no_qreg[ins.v1] = true if ins.k1 == LLOP_VAL && v2_def_blk[ins.v1] != nil && v2_def_blk[ins.v1] != bi
            no_qreg[ins.v2] = true if ins.k2 == LLOP_VAL && v2_def_blk[ins.v2] != nil && v2_def_blk[ins.v2] != bi
          if ins.extra != nil && (ins.op == :call || ins.op == :intrinsic)
            ai = 0
            while ai < ins.extra.size()
              ca = ins.extra[ai]
              no_qreg[ca[2]] = true if ca[1] == LLOP_VAL
              ai += 1
          ii += 1
        bi += 1

      bi = 0
      while bi < @fn_ir.blocks.size()
        blk = @fn_ir.blocks[bi]
        blk_has_call = false
        v2_defs = []
        ii = 0
        while ii < blk.insts.size()
          ins = blk.insts[ii]
          op = ins.op
          if op == :call || op == :frem || (op == :call_asm && ins.extra[0] != "") || (op == :intrinsic && ins.pred == "memcpy.p0.p0.i64")
            blk_has_call = true
          if ins.dst >= 0 && v2_def_blk[ins.dst] == bi && !no_qreg[ins.dst]
            v2_defs.push(ins.dst)
          ii += 1
        if !blk_has_call && v2_defs.size() > 0 && v2_defs.size() <= 16
          qi = 0
          while qi < v2_defs.size()
            @vec_reg_q[v2_defs[qi]] = 16 + qi
            qi += 1
        bi += 1

    @out_arg_bytes = ((max_stack_args * 8 + 15) / 16) * 16
    @local_base = @out_arg_bytes
    @save_off = @local_base + @fn_ir.frame_slots_bytes

    if @fn_ir.is_preserve_most
      @save_bytes = 208    # x1..x15 (120->128) + x19..x28 (80) = 208 bytes (16-byte aligned)
    elsif @has_inline_asm
      @save_bytes = 80     # x19..x28 (5 pairs = 80 bytes)
    else
      ng_pairs = (@used_cs_g.size() + 1) / 2
      nf_pairs = (@used_cs_f.size() + 1) / 2
      ic_pair  = @fn_ir.uses_ic ? 16 : 0
      @save_bytes = ng_pairs * 16 + nf_pairs * 16 + ic_pair

    @asm_spill_off = @save_off + @save_bytes
    asm_spill_bytes = (@has_inline_asm && @used_cs_g.size() > 0) ? 64 : 0
    @body_frame_bytes = ((@asm_spill_off + asm_spill_bytes + 15) / 16) * 16
    nil

  -> slot_sp_off(val_id)
    @local_base + @fn_ir.val_slot[val_id]

  # Materialize symbol address into `rd`
  -> load_sym_addr(rd, sym_id, addend = 0)
    if sym_id == @fn_ir.ic_sym_id && @fn_ir.uses_ic
      # Cached thread-local `@.ic` pointer in x28!
      if addend == 0
        @a.mov_r(rd, R_X28)
      else
        @a.add_sp_imm(rd, R_X28, addend, R_X17)
      return nil
    sn = @mod_info.sym_list[sym_id]
    sk = @mod_info.sym_kind[sym_id]
    if sk == LLSYM_TLS
      # Save x0 if rd != x0? In single-op materialization x0 is caller-saved scratch!
      if rd != R_X0
        # Preserve x0 across _tlv_bootstrap only if needed; here x0 is free between instructions!
        @a.addr_tls_macos(sn, addend)
        @a.mov_r(rd, R_X0)
      else
        @a.addr_tls_macos(sn, addend)
    elsif sk == LLSYM_DEF_FN || sk == LLSYM_DEF_DATA
      @a.addr_sym_local(rd, sn, addend)
    else
      @a.addr_sym_got(rd, sn, addend)
    nil

  # Load 64-bit integer/ptr operand `(kind, val)` into `rd`
  -> load_op64(rd, kind, val, ty = 64)
    if kind == LLOP_VAL
      raw_sl = @fn_ir.val_slot[val]
      pr = @slot_reg_g[raw_sl]
      if pr != nil
        @a.mov_r(rd, pr) if rd != pr
      else
        @a.ldr_x(rd, R_SP, @local_base + raw_sl, R_X17)
      # Canonicalize narrow integer widths if needed
      if ty == LLTY_I1
        @a.and_xi(rd, rd, 1)
      elsif ty == LLTY_I32
        @a.uxtw(rd, rd)
    elsif kind == LLOP_IMM
      @a.mov_imm64(rd, val)
    elsif kind == LLOP_SYM
      load_sym_addr(rd, val, 0)
    else
      @a.movz_x(rd, 0)
    nil

  -> store_val64(val_id, rs)
    raw_sl = @fn_ir.val_slot[val_id]
    pr = @slot_reg_g[raw_sl]
    if pr != nil
      @a.mov_r(pr, rs) if pr != rs
    else
      @a.str_x(rs, R_SP, @local_base + raw_sl, R_X17)
    nil

  # Load 128-bit / `<2 x i64>` operand `(kind, val)` into `(rd_lo, rd_hi)`
  -> load_op128(rd_lo, rd_hi, kind, val)
    if kind == LLOP_VAL
      off = slot_sp_off(val)
      @a.ldr_x(rd_lo, R_SP, off, R_X17)
      @a.ldr_x(rd_hi, R_SP, off + 8, R_X17)
    else
      @a.mov_imm64(rd_lo, val)
      @a.mov_imm64(rd_hi, val < 0 ? -1 : 0)
    nil

  -> store_val128(val_id, rs_lo, rs_hi)
    off = slot_sp_off(val_id)
    @a.str_x(rs_lo, R_SP, off, R_X17)
    @a.str_x(rs_hi, R_SP, off + 8, R_X17)
    nil

  # Load double/float operand `(kind, val)` into `dd`
  -> load_op_f64(dd, kind, val)
    if kind == LLOP_VAL
      raw_sl = @fn_ir.val_slot[val]
      pr = @slot_reg_f[raw_sl]
      if pr != nil
        @a.fmov_d(dd, pr) if dd != pr
      else
        @a.ldr_d(dd, R_SP, @local_base + raw_sl, R_X17)
    else
      @a.mov_imm64(R_X16, val)
      @a.fmov_d_x(dd, R_X16)
    nil

  -> store_val_f64(val_id, ds)
    raw_sl = @fn_ir.val_slot[val_id]
    pr = @slot_reg_f[raw_sl]
    if pr != nil
      @a.fmov_d(pr, ds) if pr != ds
    else
      @a.str_d(ds, R_SP, @local_base + raw_sl, R_X17)
    nil

  # Return branch target label for jumping from `pred_bid` -> `succ_bid` (creating a PHI copy thunk if `succ` has PHIs!)
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
      succ = @fn_ir.blocks[succ_bid]
      phis = succ.phis
      @a.bind(el)
      # Fast register-staged PHI copy when <= 4 scalar 64-bit GPR PHIs (zero stack memory ops!)
      all_gpr64 = phis.size() <= 4
      pi = 0
      while all_gpr64 && pi < phis.size()
        pty = phis[pi].ty
        all_gpr64 = false if pty == LLTY_I128 || pty == LLTY_V2I64 || pty == LLTY_OV64 || pty == LLTY_F64 || pty == LLTY_F32
        pi += 1

      if all_gpr64
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
          load_op64(R_X12 + pi, pk, pv, ph.ty)
          pi += 1
        pi = 0
        while pi < phis.size()
          store_val64(phis[pi].dst, R_X12 + pi)
          pi += 1
        @a.b(@blk_labels[succ_bid])
        ei += 1
        next

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
          load_op128(R_X9, R_X10, pk, pv)
          @a.str_x(R_X9,  R_SP, stage_base + pi * 16, R_X17)
          @a.str_x(R_X10, R_SP, stage_base + pi * 16 + 8, R_X17)
        elsif ph.ty == LLTY_F64 || ph.ty == LLTY_F32
          load_op_f64(R_D0, pk, pv)
          @a.str_d(R_D0, R_SP, stage_base + pi * 16, R_X17)
        else
          load_op64(R_X9, pk, pv, ph.ty)
          @a.str_x(R_X9, R_SP, stage_base + pi * 16, R_X17)
        pi += 1
      pi = 0
      while pi < phis.size()
        ph = phis[pi]
        if ph.ty == LLTY_I128 || ph.ty == LLTY_V2I64 || ph.ty == LLTY_OV64
          @a.ldr_x(R_X9,  R_SP, stage_base + pi * 16, R_X17)
          @a.ldr_x(R_X10, R_SP, stage_base + pi * 16 + 8, R_X17)
          store_val128(ph.dst, R_X9, R_X10)
        elsif ph.ty == LLTY_F64 || ph.ty == LLTY_F32
          @a.ldr_d(R_D0, R_SP, stage_base + pi * 16, R_X17)
          store_val_f64(ph.dst, R_D0)
        else
          @a.ldr_x(R_X9, R_SP, stage_base + pi * 16, R_X17)
          store_val64(ph.dst, R_X9)
        pi += 1
      @a.b(@blk_labels[succ_bid])
      ei += 1
    nil

  -> emit_prologue
    a = @a
    if !@omit_frame
      a.stp_pre(R_FP, R_LR, R_SP, -16)
      a.mov_sp(R_FP, R_SP)
      a.sub_sp_imm(R_SP, R_SP, @body_frame_bytes, R_X16) if @body_frame_bytes > 0

      so = @save_off
      if @fn_ir.is_preserve_most
        a.str_x(R_X1,  R_SP, so + 0);   a.str_x(R_X2,  R_SP, so + 8)
        a.str_x(R_X3,  R_SP, so + 16);  a.str_x(R_X4,  R_SP, so + 24)
        a.str_x(R_X5,  R_SP, so + 32);  a.str_x(R_X6,  R_SP, so + 40)
        a.str_x(R_X7,  R_SP, so + 48);  a.str_x(R_X8,  R_SP, so + 56)
        a.str_x(R_X9,  R_SP, so + 64);  a.str_x(R_X10, R_SP, so + 72)
        a.str_x(R_X11, R_SP, so + 80);  a.str_x(R_X12, R_SP, so + 88)
        a.str_x(R_X13, R_SP, so + 96);  a.str_x(R_X14, R_SP, so + 104)
        a.str_x(R_X15, R_SP, so + 112)
        a.str_x(R_X19, R_SP, so + 128); a.str_x(R_X20, R_SP, so + 136)
        a.str_x(R_X21, R_SP, so + 144); a.str_x(R_X22, R_SP, so + 152)
        a.str_x(R_X23, R_SP, so + 160); a.str_x(R_X24, R_SP, so + 168)
        a.str_x(R_X25, R_SP, so + 176); a.str_x(R_X26, R_SP, so + 184)
        a.str_x(R_X27, R_SP, so + 192); a.str_x(R_X28, R_SP, so + 200)
      elsif @has_inline_asm
        a.str_x(R_X19, R_SP, so + 0);   a.str_x(R_X20, R_SP, so + 8)
        a.str_x(R_X21, R_SP, so + 16);  a.str_x(R_X22, R_SP, so + 24)
        a.str_x(R_X23, R_SP, so + 32);  a.str_x(R_X24, R_SP, so + 40)
        a.str_x(R_X25, R_SP, so + 48);  a.str_x(R_X26, R_SP, so + 56)
        a.str_x(R_X27, R_SP, so + 64);  a.str_x(R_X28, R_SP, so + 72)
      else
        cur_s = so
        ng = @used_cs_g.size()
        a.str_x(R_X19, R_SP, cur_s + 0)  if ng >= 1
        a.str_x(R_X20, R_SP, cur_s + 8)  if ng >= 2
        a.str_x(R_X21, R_SP, cur_s + 16) if ng >= 3
        a.str_x(R_X22, R_SP, cur_s + 24) if ng >= 4
        a.str_x(R_X23, R_SP, cur_s + 32) if ng >= 5
        a.str_x(R_X24, R_SP, cur_s + 40) if ng >= 6
        a.str_x(R_X25, R_SP, cur_s + 48) if ng >= 7
        a.str_x(R_X26, R_SP, cur_s + 56) if ng >= 8
        cur_s += ((ng + 1) / 2) * 16
        nf = @used_cs_f.size()
        a.str_d(R_D8,  R_SP, cur_s + 0)  if nf >= 1
        a.str_d(R_D9,  R_SP, cur_s + 8)  if nf >= 2
        a.str_d(R_D10, R_SP, cur_s + 16) if nf >= 3
        a.str_d(R_D11, R_SP, cur_s + 24) if nf >= 4
        a.str_d(R_D12, R_SP, cur_s + 32) if nf >= 5
        a.str_d(R_D13, R_SP, cur_s + 40) if nf >= 6
        a.str_d(R_D14, R_SP, cur_s + 48) if nf >= 7
        a.str_d(R_D15, R_SP, cur_s + 56) if nf >= 8
        cur_s += ((nf + 1) / 2) * 16
        if @fn_ir.uses_ic
          a.str_x(R_X27, R_SP, cur_s + 0)
          a.str_x(R_X28, R_SP, cur_s + 8)

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
          a.ldr_d(R_D16, R_FP, 16 + st_idx * 8, R_X17)
          store_val_f64(pi, R_D16)
          st_idx += 1
      else
        if gi < 8
          store_val64(pi, gi)
          gi += 1
        else
          a.ldr_x(R_X9, R_FP, 16 + st_idx * 8, R_X17)
          store_val64(pi, R_X9)
          st_idx += 1
      pi += 1

    if @fn_ir.uses_ic
      a.addr_tls_macos(".ic", 0)
      a.mov_r(R_X28, R_X0)
    nil

  -> emit_epilogue
    a = @a
    a.bind(@l_epi)
    if @omit_frame
      a.ret()
      return nil
    so = @save_off
    if @fn_ir.is_preserve_most
      a.ldr_x(R_X1,  R_SP, so + 0);   a.ldr_x(R_X2,  R_SP, so + 8)
      a.ldr_x(R_X3,  R_SP, so + 16);  a.ldr_x(R_X4,  R_SP, so + 24)
      a.ldr_x(R_X5,  R_SP, so + 32);  a.ldr_x(R_X6,  R_SP, so + 40)
      a.ldr_x(R_X7,  R_SP, so + 48);  a.ldr_x(R_X8,  R_SP, so + 56)
      a.ldr_x(R_X9,  R_SP, so + 64);  a.ldr_x(R_X10, R_SP, so + 72)
      a.ldr_x(R_X11, R_SP, so + 80);  a.ldr_x(R_X12, R_SP, so + 88)
      a.ldr_x(R_X13, R_SP, so + 96);  a.ldr_x(R_X14, R_SP, so + 104)
      a.ldr_x(R_X15, R_SP, so + 112)
      a.ldr_x(R_X19, R_SP, so + 128); a.ldr_x(R_X20, R_SP, so + 136)
      a.ldr_x(R_X21, R_SP, so + 144); a.ldr_x(R_X22, R_SP, so + 152)
      a.ldr_x(R_X23, R_SP, so + 160); a.ldr_x(R_X24, R_SP, so + 168)
      a.ldr_x(R_X25, R_SP, so + 176); a.ldr_x(R_X26, R_SP, so + 184)
      a.ldr_x(R_X27, R_SP, so + 192); a.ldr_x(R_X28, R_SP, so + 200)
    elsif @has_inline_asm
      a.ldr_x(R_X19, R_SP, so + 0);   a.ldr_x(R_X20, R_SP, so + 8)
      a.ldr_x(R_X21, R_SP, so + 16);  a.ldr_x(R_X22, R_SP, so + 24)
      a.ldr_x(R_X23, R_SP, so + 32);  a.ldr_x(R_X24, R_SP, so + 40)
      a.ldr_x(R_X25, R_SP, so + 48);  a.ldr_x(R_X26, R_SP, so + 56)
      a.ldr_x(R_X27, R_SP, so + 64);  a.ldr_x(R_X28, R_SP, so + 72)
    else
      cur_s = so
      ng = @used_cs_g.size()
      a.ldr_x(R_X19, R_SP, cur_s + 0)  if ng >= 1
      a.ldr_x(R_X20, R_SP, cur_s + 8)  if ng >= 2
      a.ldr_x(R_X21, R_SP, cur_s + 16) if ng >= 3
      a.ldr_x(R_X22, R_SP, cur_s + 24) if ng >= 4
      a.ldr_x(R_X23, R_SP, cur_s + 32) if ng >= 5
      a.ldr_x(R_X24, R_SP, cur_s + 40) if ng >= 6
      a.ldr_x(R_X25, R_SP, cur_s + 48) if ng >= 7
      a.ldr_x(R_X26, R_SP, cur_s + 56) if ng >= 8
      cur_s += ((ng + 1) / 2) * 16
      nf = @used_cs_f.size()
      a.ldr_d(R_D8,  R_SP, cur_s + 0)  if nf >= 1
      a.ldr_d(R_D9,  R_SP, cur_s + 8)  if nf >= 2
      a.ldr_d(R_D10, R_SP, cur_s + 16) if nf >= 3
      a.ldr_d(R_D11, R_SP, cur_s + 24) if nf >= 4
      a.ldr_d(R_D12, R_SP, cur_s + 32) if nf >= 5
      a.ldr_d(R_D13, R_SP, cur_s + 40) if nf >= 6
      a.ldr_d(R_D14, R_SP, cur_s + 48) if nf >= 7
      a.ldr_d(R_D15, R_SP, cur_s + 56) if nf >= 8
      cur_s += ((nf + 1) / 2) * 16
      if @fn_ir.uses_ic
        a.ldr_x(R_X27, R_SP, cur_s + 0)
        a.ldr_x(R_X28, R_SP, cur_s + 8)
    a.mov_sp(R_SP, R_FP)
    a.ldp_post(R_FP, R_LR, R_SP, 16)
    a.ret()
    nil

  # Inline 128-bit unsigned remainder `rem = num % den`:
  # Inputs: num=(R_X9, R_X10), den=(R_X11, R_X12) -> Output: rem=(R_X13, R_X14)!
  -> emit_urem_i128
    a = @a
    a.movz_x(R_X13, 0)
    a.movz_x(R_X14, 0)
    a.movz_x(R_X15, 128)
    l_lp = a.new_label()
    l_no_sub = a.new_label()
    a.bind(l_lp)
    # carry_bit = (num_hi >> 63) & 1; num <<= 1; rem = (rem << 1) | carry_bit
    a.lsr_xi(R_X16, R_X10, 63)
    a.extr_x(R_X10, R_X10, R_X9, 63)
    a.lsl_xi(R_X9, R_X9, 1)
    a.extr_x(R_X14, R_X14, R_X13, 63)
    a.lsl_xi(R_X13, R_X13, 1)
    a.orr_r(R_X13, R_X13, R_X16)
    # Compare rem (X14:X13) >=u den (X12:X11): subs x16, x13, x11; sbcs x17, x14, x12
    a.subs_r(R_X16, R_X13, R_X11)
    a.sbcs_x(R_X17, R_X14, R_X12)
    a.b_cond(CC_LO, l_no_sub)
    a.mov_r(R_X13, R_X16)
    a.mov_r(R_X14, R_X17)
    a.bind(l_no_sub)
    a.sub_i(R_X15, R_X15, 1)
    a.cbnz_x(R_X15, l_lp)
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
          load_op128(R_X9, R_X10, ins.k0, ins.v0)
          store_val128(ins.dst, R_X9, R_X10)
        elsif ins.ty == LLTY_F64 || ins.ty == LLTY_F32
          load_op_f64(R_D0, ins.k0, ins.v0)
          store_val_f64(ins.dst, R_D0)
        else
          load_op64(R_X9, ins.k0, ins.v0, ins.ty)
          store_val64(ins.dst, R_X9)
      elsif op == :umulh
        load_op64(R_X9, ins.k0, ins.v0, LLTY_I64)
        load_op64(R_X10, ins.k1, ins.v1, LLTY_I64)
        a.umulh_x(R_X9, R_X9, R_X10)
        store_val64(ins.dst, R_X9)
      elsif op == :alloca
        a.add_sp_imm(R_X9, R_SP, @local_base + ins.v0, R_X16)
        store_val64(ins.dst, R_X9)
      elsif op == :load
        load_op64(R_X10, ins.k0, ins.v0, LLTY_PTR)
        ty = ins.ty
        if ty == LLTY_I64 || ty == LLTY_PTR
          a.ldr_x(R_X9, R_X10, 0)
          store_val64(ins.dst, R_X9)
        elsif ty == LLTY_I32
          a.ldr_w(R_X9, R_X10, 0)
          store_val64(ins.dst, R_X9)
        elsif ty == LLTY_I16
          a.ldrh(R_X9, R_X10, 0)
          store_val64(ins.dst, R_X9)
        elsif ty == LLTY_I8 || ty == LLTY_I1
          a.ldrb(R_X9, R_X10, 0)
          store_val64(ins.dst, R_X9)
        elsif ty == LLTY_F64
          a.ldr_d(R_D0, R_X10, 0)
          store_val_f64(ins.dst, R_D0)
        elsif ty == LLTY_V2I64 && @vec_reg_q[ins.dst] != nil
          a.ldr_q(@vec_reg_q[ins.dst], R_X10, 0)
        elsif ty == LLTY_V2I64 && @do_simd && slot_sp_off(ins.dst) <= 65520 && (slot_sp_off(ins.dst) & 15) == 0
          a.ldr_q(3, R_X10, 0)
          a.str_q(3, R_SP, slot_sp_off(ins.dst))
        elsif ty == LLTY_I128 || ty == LLTY_V2I64
          a.ldr_x(R_X9, R_X10, 0)
          a.ldr_x(R_X11, R_X10, 8)
          store_val128(ins.dst, R_X9, R_X11)
      elsif op == :store
        load_op64(R_X10, ins.k1, ins.v1, LLTY_PTR)
        ty = ins.ty
        if ty == LLTY_I64 || ty == LLTY_PTR
          load_op64(R_X9, ins.k0, ins.v0, ty)
          a.str_x(R_X9, R_X10, 0)
        elsif ty == LLTY_I32
          load_op64(R_X9, ins.k0, ins.v0, ty)
          a.str_w(R_X9, R_X10, 0)
        elsif ty == LLTY_I16
          load_op64(R_X9, ins.k0, ins.v0, ty)
          a.strh(R_X9, R_X10, 0)
        elsif ty == LLTY_I8 || ty == LLTY_I1
          load_op64(R_X9, ins.k0, ins.v0, ty)
          a.strb(R_X9, R_X10, 0)
        elsif ty == LLTY_F64
          load_op_f64(R_D0, ins.k0, ins.v0)
          a.str_d(R_D0, R_X10, 0)
        elsif ty == LLTY_V2I64 && ins.k0 == LLOP_VAL && @vec_reg_q[ins.v0] != nil
          a.str_q(@vec_reg_q[ins.v0], R_X10, 0)
        elsif ty == LLTY_V2I64 && @do_simd && ins.k0 == LLOP_VAL && slot_sp_off(ins.v0) <= 65520 && (slot_sp_off(ins.v0) & 15) == 0
          a.ldr_q(3, R_SP, slot_sp_off(ins.v0))
          a.str_q(3, R_X10, 0)
        elsif ty == LLTY_I128 || ty == LLTY_V2I64
          load_op128(R_X9, R_X11, ins.k0, ins.v0)
          a.str_x(R_X9, R_X10, 0)
          a.str_x(R_X11, R_X10, 8)
      elsif op == :gep
        # Fast path when base is a symbol: fold `ins.v1` constant offset right into `load_sym_addr`!
        if ins.k0 == LLOP_SYM
          load_sym_addr(R_X9, ins.v0, ins.v1)
        else
          load_op64(R_X9, ins.k0, ins.v0, LLTY_PTR)
          a.add_sp_imm(R_X9, R_X9, ins.v1, R_X16) if ins.v1 != 0
        if ins.extra != nil
          si = 0
          while si < ins.extra.size()
            st = ins.extra[si]
            load_op64(R_X10, st[0], st[1], LLTY_I64)
            # Sign-extend i32 dynamic index if needed? GEP dynamic indices in tungsten.ll are i64 (or non-negative i32)
            stride = st[2]
            if stride == 1
              a.add_r(R_X9, R_X9, R_X10)
            elsif stride == 2
              a.add_r(R_X9, R_X9, R_X10, 1)
            elsif stride == 4
              a.add_r(R_X9, R_X9, R_X10, 2)
            elsif stride == 8
              a.add_r(R_X9, R_X9, R_X10, 3)
            else
              a.mov_imm64(R_X11, stride)
              a.madd_x(R_X9, R_X10, R_X11, R_X9)
            si += 1
        store_val64(ins.dst, R_X9)
      elsif op == :add || op == :sub || op == :mul || op == :sdiv || op == :udiv || op == :srem || op == :urem || op == :and || op == :or || op == :xor || op == :shl || op == :ashr || op == :lshr
        ty = ins.ty
        if ty == LLTY_V2I64 && @do_simd && (op == :and || op == :or || op == :xor) && ins.k0 == LLOP_VAL && ins.k1 == LLOP_VAL && (@vec_reg_q[ins.v0] != nil || (slot_sp_off(ins.v0) <= 65520 && (slot_sp_off(ins.v0) & 15) == 0)) && (@vec_reg_q[ins.v1] != nil || (slot_sp_off(ins.v1) <= 65520 && (slot_sp_off(ins.v1) & 15) == 0)) && (@vec_reg_q[ins.dst] != nil || (slot_sp_off(ins.dst) <= 65520 && (slot_sp_off(ins.dst) & 15) == 0))
          q0 = @vec_reg_q[ins.v0]
          if q0 == nil
            a.ldr_q(3, R_SP, slot_sp_off(ins.v0))
            q0 = 3
          q1 = @vec_reg_q[ins.v1]
          if q1 == nil
            a.ldr_q(4, R_SP, slot_sp_off(ins.v1))
            q1 = 4
          qd = @vec_reg_q[ins.dst]
          rd_q = qd != nil ? qd : 3
          a.and_16b(rd_q, q0, q1) if op == :and
          a.orr_16b(rd_q, q0, q1) if op == :or
          a.eor_16b(rd_q, q0, q1) if op == :xor
          a.str_q(3, R_SP, slot_sp_off(ins.dst)) if qd == nil
        elsif ty == LLTY_I128 || ty == LLTY_V2I64
          load_op128(R_X9, R_X10, ins.k0, ins.v0)
          load_op128(R_X11, R_X12, ins.k1, ins.v1)
          if op == :add
            a.adds_r(R_X13, R_X9, R_X11)
            a.adc_x(R_X14, R_X10, R_X12)
          elsif op == :sub
            a.subs_r(R_X13, R_X9, R_X11)
            a.sbc_x(R_X14, R_X10, R_X12)
          elsif op == :and
            a.and_r(R_X13, R_X9, R_X11)
            a.and_r(R_X14, R_X10, R_X12)
          elsif op == :or
            a.orr_r(R_X13, R_X9, R_X11)
            a.orr_r(R_X14, R_X10, R_X12)
          elsif op == :xor
            a.eor_r(R_X13, R_X9, R_X11)
            a.eor_r(R_X14, R_X10, R_X12)
          elsif op == :mul
            a.mul_x(R_X13, R_X9, R_X11)
            a.umulh_x(R_X14, R_X9, R_X11)
            a.madd_x(R_X14, R_X9, R_X12, R_X14)
            a.madd_x(R_X14, R_X10, R_X11, R_X14)
          elsif op == :shl
            if ins.k1 == LLOP_IMM && ins.v1 == 64
              a.movz_x(R_X13, 0); a.mov_r(R_X14, R_X9)
            elsif ins.k1 == LLOP_IMM && ins.v1 == 1
              a.adds_r(R_X13, R_X9, R_X9); a.adc_x(R_X14, R_X10, R_X10)
            else
              # General 128-bit shl by R_X11 (0..127)
              l_z = a.new_label(); l_ge64 = a.new_label(); l_dn = a.new_label()
              a.cbz_x(R_X11, l_z)
              a.cmp_i(R_X11, 64)
              a.b_cond(CC_HS, l_ge64)
              a.lsl_x(R_X13, R_X9, R_X11)
              a.lsl_x(R_X14, R_X10, R_X11)
              a.mov_imm64(R_X15, 64)
              a.sub_r(R_X15, R_X15, R_X11)
              a.lsr_x(R_X15, R_X9, R_X15)
              a.orr_r(R_X14, R_X14, R_X15)
              a.b(l_dn)
              a.bind(l_ge64)
              a.sub_i(R_X15, R_X11, 64)
              a.movz_x(R_X13, 0)
              a.lsl_x(R_X14, R_X9, R_X15)
              a.b(l_dn)
              a.bind(l_z)
              a.mov_r(R_X13, R_X9); a.mov_r(R_X14, R_X10)
              a.bind(l_dn)
          elsif op == :lshr
            if ins.k1 == LLOP_IMM && ins.v1 == 64
              a.mov_r(R_X13, R_X10); a.movz_x(R_X14, 0)
            else
              l_z = a.new_label(); l_ge64 = a.new_label(); l_dn = a.new_label()
              a.cbz_x(R_X11, l_z)
              a.cmp_i(R_X11, 64)
              a.b_cond(CC_HS, l_ge64)
              a.lsr_x(R_X13, R_X9, R_X11)
              a.lsr_x(R_X14, R_X10, R_X11)
              a.mov_imm64(R_X15, 64)
              a.sub_r(R_X15, R_X15, R_X11)
              a.lsl_x(R_X15, R_X10, R_X15)
              a.orr_r(R_X13, R_X13, R_X15)
              a.b(l_dn)
              a.bind(l_ge64)
              a.sub_i(R_X15, R_X11, 64)
              a.lsr_x(R_X13, R_X10, R_X15)
              a.movz_x(R_X14, 0)
              a.b(l_dn)
              a.bind(l_z)
              a.mov_r(R_X13, R_X9); a.mov_r(R_X14, R_X10)
              a.bind(l_dn)
          elsif op == :urem
            emit_urem_i128()
          store_val128(ins.dst, R_X13, R_X14)
        elsif @do_peephole && (ty == LLTY_I64 || ty == LLTY_PTR) && ins.k1 == LLOP_IMM && ((op == :add || op == :sub) && ins.v1 >= 0 && ins.v1 <= 4095)
          load_op64(R_X9, ins.k0, ins.v0, ty)
          op == :add ? a.add_i(R_X9, R_X9, ins.v1) : a.sub_i(R_X9, R_X9, ins.v1)
          store_val64(ins.dst, R_X9)
        elsif @do_peephole && (ty == LLTY_I64 || ty == LLTY_PTR) && ins.k1 == LLOP_IMM && op == :and && (ins.v1 == 1 || ins.v1 == 255 || ins.v1 == 65535 || ins.v1 == 0xFFFFFFFF)
          load_op64(R_X9, ins.k0, ins.v0, ty)
          a.and_xi(R_X9, R_X9, 1) if ins.v1 == 1
          a.uxtb_x(R_X9, R_X9)    if ins.v1 == 255
          a.uxth_x(R_X9, R_X9)    if ins.v1 == 65535
          a.uxtw(R_X9, R_X9)      if ins.v1 == 0xFFFFFFFF
          store_val64(ins.dst, R_X9)
        elsif @do_peephole && (ty == LLTY_I64 || ty == LLTY_PTR) && ins.k1 == LLOP_IMM && (op == :shl || op == :lshr || op == :ashr) && ins.v1 >= 0 && ins.v1 <= 63
          load_op64(R_X9, ins.k0, ins.v0, ty)
          a.lsl_xi(R_X9, R_X9, ins.v1) if op == :shl
          a.lsr_xi(R_X9, R_X9, ins.v1) if op == :lshr
          a.asr_xi(R_X9, R_X9, ins.v1) if op == :ashr
          store_val64(ins.dst, R_X9)
        else
          load_op64(R_X9, ins.k0, ins.v0, ty)
          load_op64(R_X10, ins.k1, ins.v1, ty)
          if ty == LLTY_I32
            a.add_w(R_X9, R_X9, R_X10)  if op == :add
            a.sub_w(R_X9, R_X9, R_X10)  if op == :sub
            a.mul_w(R_X9, R_X9, R_X10)  if op == :mul
            a.sdiv_w(R_X9, R_X9, R_X10) if op == :sdiv
            a.udiv_w(R_X9, R_X9, R_X10) if op == :udiv
            if op == :srem
              a.sdiv_w(R_X11, R_X9, R_X10); a.msub_w(R_X9, R_X11, R_X10, R_X9)
            elsif op == :urem
              a.udiv_w(R_X11, R_X9, R_X10); a.msub_w(R_X9, R_X11, R_X10, R_X9)
            a.and_w(R_X9, R_X9, R_X10) if op == :and
            a.orr_w(R_X9, R_X9, R_X10) if op == :or
            a.eor_w(R_X9, R_X9, R_X10) if op == :xor
            a.lsl_w(R_X9, R_X9, R_X10) if op == :shl
            a.asr_w(R_X9, R_X9, R_X10) if op == :ashr
            a.lsr_w(R_X9, R_X9, R_X10) if op == :lshr
          else
            a.add_r(R_X9, R_X9, R_X10)  if op == :add
            a.sub_r(R_X9, R_X9, R_X10)  if op == :sub
            a.mul_x(R_X9, R_X9, R_X10)  if op == :mul
            a.sdiv_x(R_X9, R_X9, R_X10) if op == :sdiv
            a.udiv_x(R_X9, R_X9, R_X10) if op == :udiv
            if op == :srem
              a.sdiv_x(R_X11, R_X9, R_X10); a.msub_x(R_X9, R_X11, R_X10, R_X9)
            elsif op == :urem
              a.udiv_x(R_X11, R_X9, R_X10); a.msub_x(R_X9, R_X11, R_X10, R_X9)
            a.and_r(R_X9, R_X9, R_X10) if op == :and
            a.orr_r(R_X9, R_X9, R_X10) if op == :or
            a.eor_r(R_X9, R_X9, R_X10) if op == :xor
            a.lsl_x(R_X9, R_X9, R_X10) if op == :shl
            a.asr_x(R_X9, R_X9, R_X10) if op == :ashr
            a.lsr_x(R_X9, R_X9, R_X10) if op == :lshr
            a.and_xi(R_X9, R_X9, 1) if ty == LLTY_I1
          store_val64(ins.dst, R_X9)
      elsif op == :fadd || op == :fsub || op == :fmul || op == :fdiv
        load_op_f64(R_D0, ins.k0, ins.v0)
        load_op_f64(R_D1, ins.k1, ins.v1)
        a.fadd_d(R_D0, R_D0, R_D1) if op == :fadd
        a.fsub_d(R_D0, R_D0, R_D1) if op == :fsub
        a.fmul_d(R_D0, R_D0, R_D1) if op == :fmul
        a.fdiv_d(R_D0, R_D0, R_D1) if op == :fdiv
        store_val_f64(ins.dst, R_D0)
      elsif op == :frem
        load_op_f64(R_D0, ins.k0, ins.v0)
        load_op_f64(R_D1, ins.k1, ins.v1)
        @mod_info.intern_sym("fmod", LLSYM_EXT_FN)
        a.bl_sym(@is_macho ? "_fmod" : "fmod")
        store_val_f64(ins.dst, R_D0)
      elsif op == :icmp
        ty = ins.ty
        if ty == LLTY_I128
          load_op128(R_X9, R_X10, ins.k0, ins.v0)
          load_op128(R_X11, R_X12, ins.k1, ins.v1)
          p = ins.pred
          if p == :slt
            a.subs_r(R_XZR, R_X9, R_X11); a.sbcs_x(R_XZR, R_X10, R_X12); a.cset(R_X9, CC_LT)
          elsif p == :ugt
            a.subs_r(R_XZR, R_X11, R_X9); a.sbcs_x(R_XZR, R_X12, R_X10); a.cset(R_X9, CC_LO)
          elsif p == :ult
            a.subs_r(R_XZR, R_X9, R_X11); a.sbcs_x(R_XZR, R_X10, R_X12); a.cset(R_X9, CC_LO)
          elsif p == :eq
            a.eor_r(R_X9, R_X9, R_X11); a.eor_r(R_X10, R_X10, R_X12); a.orr_r(R_X9, R_X9, R_X10)
            a.cmp_i(R_X9, 0); a.cset(R_X9, CC_EQ)
          else
            a.eor_r(R_X9, R_X9, R_X11); a.eor_r(R_X10, R_X10, R_X12); a.orr_r(R_X9, R_X9, R_X10)
            a.cmp_i(R_X9, 0); a.cset(R_X9, CC_NE)
          store_val64(ins.dst, R_X9)
        else
          load_op64(R_X9, ins.k0, ins.v0, ty)
          if @do_peephole && (ty == LLTY_I64 || ty == LLTY_PTR) && ins.k1 == LLOP_IMM && ins.v1 >= 0 && ins.v1 <= 4095
            a.cmp_i(R_X9, ins.v1)
          elsif @do_peephole && ty == LLTY_I32 && ins.k1 == LLOP_IMM && ins.v1 >= 0 && ins.v1 <= 4095
            a.cmp_wi(R_X9, ins.v1)
          else
            load_op64(R_X10, ins.k1, ins.v1, ty)
            if ty == LLTY_I8
              is_s = ins.pred == :slt || ins.pred == :sle || ins.pred == :sgt || ins.pred == :sge
              if is_s
                a.sxtb_x(R_X9, R_X9); a.sxtb_x(R_X10, R_X10)
              else
                a.uxtb_x(R_X9, R_X9); a.uxtb_x(R_X10, R_X10)
              a.cmp_r(R_X9, R_X10)
            elsif ty == LLTY_I16
              is_s = ins.pred == :slt || ins.pred == :sle || ins.pred == :sgt || ins.pred == :sge
              if is_s
                a.sxth_x(R_X9, R_X9); a.sxth_x(R_X10, R_X10)
              else
                a.uxth_x(R_X9, R_X9); a.uxth_x(R_X10, R_X10)
              a.cmp_r(R_X9, R_X10)
            elsif ty == LLTY_I32
              a.cmp_w(R_X9, R_X10)
            else
              a.cmp_r(R_X9, R_X10)
          cc = lla64_icmp_cc(ins.pred)
          if @do_peephole && ii < n && @fn_ir.val_uses != nil && @fn_ir.val_uses[ins.dst] == 1 && insts[ii].op == :cond_br && insts[ii].k0 == LLOP_VAL && insts[ii].v0 == ins.dst
            cbr = insts[ii]
            ii += 1
            a.b_cond_far(cc, branch_target_label(bid, cbr.v1))
            a.b(branch_target_label(bid, cbr.v2))
          else
            a.cset(R_X9, cc)
            store_val64(ins.dst, R_X9)
      elsif op == :fcmp
        load_op_f64(R_D0, ins.k0, ins.v0)
        load_op_f64(R_D1, ins.k1, ins.v1)
        a.fcmp_d(R_D0, R_D1)
        p = ins.pred
        cc = CC_NE
        cc = CC_EQ if p == :oeq || p == :ueq
        cc = CC_MI if p == :olt
        cc = CC_LS if p == :ole
        cc = CC_GT if p == :ogt
        cc = CC_GE if p == :oge
        cc = CC_VC if p == :ord
        cc = CC_VS if p == :uno
        a.cset(R_X9, cc)
        store_val64(ins.dst, R_X9)
      elsif op == :select
        load_op64(R_X11, ins.k0, ins.v0, LLTY_I1)
        a.cmp_i(R_X11, 0)
        if ins.ty == LLTY_F64 || ins.ty == LLTY_F32
          load_op_f64(R_D0, ins.k1, ins.v1)
          load_op_f64(R_D1, ins.k2, ins.v2)
          a.fcsel_d(R_D0, R_D0, R_D1, CC_NE)
          store_val_f64(ins.dst, R_D0)
        else
          load_op64(R_X9, ins.k1, ins.v1, ins.ty)
          load_op64(R_X10, ins.k2, ins.v2, ins.ty)
          a.csel_x(R_X9, R_X9, R_X10, CC_NE)
          store_val64(ins.dst, R_X9)
      elsif op == :sext
        if ins.ty == LLTY_I128
          load_op64(R_X9, ins.k0, ins.v0, ins.ty2)
          a.sxtw(R_X9, R_X9) if ins.ty2 == LLTY_I32
          a.asr_xi(R_X10, R_X9, 63)
          store_val128(ins.dst, R_X9, R_X10)
        else
          load_op64(R_X9, ins.k0, ins.v0, ins.ty2)
          if ins.ty2 == LLTY_I1
            a.and_xi(R_X9, R_X9, 1)
            a.neg_x(R_X9, R_X9)
          elsif ins.ty2 == LLTY_I8
            a.sxtb_x(R_X9, R_X9)
          elsif ins.ty2 == LLTY_I16
            a.sxth_x(R_X9, R_X9)
          elsif ins.ty2 == LLTY_I32
            a.sxtw(R_X9, R_X9)
          store_val64(ins.dst, R_X9)
      elsif op == :zext
        if @do_peephole && @fn_ir.val_uses != nil && ins.ty == LLTY_I128 && ins.ty2 == LLTY_I64 && ii + 3 < n
          i1 = insts[ii]; i2 = insts[ii + 1]; i3 = insts[ii + 2]; i4 = insts[ii + 3]
          if @fn_ir.val_uses[ins.dst] == 1 && i1.op == :zext && i1.ty == LLTY_I128 && i1.ty2 == LLTY_I64 && @fn_ir.val_uses[i1.dst] == 1 && (i2.op == :mul || i2.op == :add || i2.op == :sub) && i2.ty == LLTY_I128 && @fn_ir.val_uses[i2.dst] == 1 && i2.k0 == LLOP_VAL && i2.v0 == ins.dst && i2.k1 == LLOP_VAL && i2.v1 == i1.dst && i3.op == :lshr && i3.ty == LLTY_I128 && @fn_ir.val_uses[i3.dst] == 1 && i3.k0 == LLOP_VAL && i3.v0 == i2.dst && i3.k1 == LLOP_IMM && i4.op == :trunc && i4.ty == LLTY_I64 && i4.ty2 == LLTY_I128 && i4.k0 == LLOP_VAL && i4.v0 == i3.dst && ((i2.op != :sub && i3.v1 == 64) || (i2.op == :sub && i3.v1 == 127))
            # Hardware peephole for single-use `mulhi_u64` / `addcarry_u64` / `subborrow_u64` IR idioms!
            load_op64(R_X9, ins.k0, ins.v0, LLTY_I64)
            load_op64(R_X10, i1.k0, i1.v0, LLTY_I64)
            if i2.op == :mul
              a.umulh_x(R_X9, R_X9, R_X10)
            elsif i2.op == :add
              a.cmn_r(R_X9, R_X10)
              a.cset(R_X9, CC_HS)
            else
              a.cmp_r(R_X9, R_X10)
              a.cset(R_X9, CC_LO)
            store_val64(i4.dst, R_X9)
            ii += 4
            next
        if @do_peephole && @fn_ir.val_uses != nil && ins.ty == LLTY_I128 && ins.ty2 == LLTY_I64 && ii + 1 < n
          i1 = insts[ii]; i2 = insts[ii + 1]
          if @fn_ir.val_uses[ins.dst] == 1 && i1.op == :zext && i1.ty == LLTY_I128 && i1.ty2 == LLTY_I64 && @fn_ir.val_uses[i1.dst] == 1 && i2.op == :mul && i2.ty == LLTY_I128 && i2.k0 == LLOP_VAL && i2.v0 == ins.dst && i2.k1 == LLOP_VAL && i2.v1 == i1.dst
            # 2-instruction `64x64 -> 128` unsigned widening multiply (`__bigint_mul1_1_product` after inlining!)
            load_op64(R_X9, ins.k0, ins.v0, LLTY_I64)
            load_op64(R_X10, i1.k0, i1.v0, LLTY_I64)
            a.mul_x(R_X11, R_X9, R_X10)
            a.umulh_x(R_X12, R_X9, R_X10)
            store_val128(i2.dst, R_X11, R_X12)
            ii += 2
            next
        if ins.ty == LLTY_I128
          load_op64(R_X9, ins.k0, ins.v0, ins.ty2)
          a.and_xi(R_X9, R_X9, 1) if ins.ty2 == LLTY_I1
          a.uxtw(R_X9, R_X9)      if ins.ty2 == LLTY_I32
          a.movz_x(R_X10, 0)
          store_val128(ins.dst, R_X9, R_X10)
        else
          load_op64(R_X9, ins.k0, ins.v0, ins.ty2)
          a.and_xi(R_X9, R_X9, 1) if ins.ty2 == LLTY_I1
          a.uxtb_x(R_X9, R_X9)    if ins.ty2 == LLTY_I8
          a.uxth_x(R_X9, R_X9)    if ins.ty2 == LLTY_I16
          a.uxtw(R_X9, R_X9)      if ins.ty2 == LLTY_I32
          store_val64(ins.dst, R_X9)
      elsif op == :trunc
        if ins.ty2 == LLTY_I128
          load_op128(R_X9, R_X10, ins.k0, ins.v0)
        else
          load_op64(R_X9, ins.k0, ins.v0, ins.ty2)
        a.and_xi(R_X9, R_X9, 1) if ins.ty == LLTY_I1
        a.uxtb_x(R_X9, R_X9)    if ins.ty == LLTY_I8
        a.uxth_x(R_X9, R_X9)    if ins.ty == LLTY_I16
        a.uxtw(R_X9, R_X9)      if ins.ty == LLTY_I32
        store_val64(ins.dst, R_X9)
      elsif op == :inttoptr || op == :ptrtoint
        load_op64(R_X9, ins.k0, ins.v0, LLTY_I64)
        store_val64(ins.dst, R_X9)
      elsif op == :bitcast
        if ins.ty == LLTY_F64 && (ins.ty2 == LLTY_I64 || ins.ty2 == LLTY_PTR)
          load_op64(R_X9, ins.k0, ins.v0, LLTY_I64)
          a.fmov_d_x(R_D0, R_X9)
          store_val_f64(ins.dst, R_D0)
        elsif (ins.ty == LLTY_I64 || ins.ty == LLTY_PTR) && ins.ty2 == LLTY_F64
          load_op_f64(R_D0, ins.k0, ins.v0)
          a.fmov_x_d(R_X9, R_D0)
          store_val64(ins.dst, R_X9)
        else
          load_op64(R_X9, ins.k0, ins.v0, LLTY_I64)
          store_val64(ins.dst, R_X9)
      elsif op == :sitofp
        load_op64(R_X9, ins.k0, ins.v0, ins.ty2)
        ins.ty2 == LLTY_I32 ? a.scvtf_d_w(R_D0, R_X9) : a.scvtf_d_x(R_D0, R_X9)
        store_val_f64(ins.dst, R_D0)
      elsif op == :uitofp
        load_op64(R_X9, ins.k0, ins.v0, ins.ty2)
        ins.ty2 == LLTY_I32 ? a.ucvtf_d_w(R_D0, R_X9) : a.ucvtf_d_x(R_D0, R_X9)
        store_val_f64(ins.dst, R_D0)
      elsif op == :fptosi
        load_op_f64(R_D0, ins.k0, ins.v0)
        ins.ty == LLTY_I32 ? a.fcvtzs_w_d(R_X9, R_D0) : a.fcvtzs_x_d(R_X9, R_D0)
        store_val64(ins.dst, R_X9)
      elsif op == :fptoui
        load_op_f64(R_D0, ins.k0, ins.v0)
        ins.ty == LLTY_I32 ? a.fcvtzu_w_d(R_X9, R_D0) : a.fcvtzu_x_d(R_X9, R_D0)
        store_val64(ins.dst, R_X9)
      elsif op == :extractvalue || op == :extractelement
        off = slot_sp_off(ins.v0) + (ins.v1 == 1 ? 8 : 0)
        a.ldr_x(R_X9, R_SP, off, R_X17)
        store_val64(ins.dst, R_X9)
      elsif op == :intrinsic
        intr = ins.pred
        cargs = ins.extra
        if intr == "smul.with.overflow.i64"
          load_op64(R_X9, cargs[0][1], cargs[0][2], LLTY_I64)
          load_op64(R_X10, cargs[1][1], cargs[1][2], LLTY_I64)
          a.mul_x(R_X11, R_X9, R_X10)
          a.smulh_x(R_X12, R_X9, R_X10)
          a.cmp_r(R_X12, R_X11, 63, 2)
          a.cset(R_X12, CC_NE)
          store_val128(ins.dst, R_X11, R_X12)
        elsif intr == "cttz.i64"
          load_op64(R_X9, cargs[0][1], cargs[0][2], LLTY_I64)
          a.rbit_x(R_X9, R_X9)
          a.clz_x(R_X9, R_X9)
          store_val64(ins.dst, R_X9)
        elsif intr == "ctlz.i64"
          load_op64(R_X9, cargs[0][1], cargs[0][2], LLTY_I64)
          a.clz_x(R_X9, R_X9)
          store_val64(ins.dst, R_X9)
        elsif intr == "ctpop.i64"
          load_op64(R_X9, cargs[0][1], cargs[0][2], LLTY_I64)
          a.fmov_d_x(R_D0, R_X9)
          a.cnt_8b(R_D0, R_D0)
          a.uaddlv_8b(R_D0, R_D0)
          a.fmov_x_d(R_X9, R_D0)
          store_val64(ins.dst, R_X9)
        elsif intr == "sqrt.f64"
          load_op_f64(R_D0, cargs[0][1], cargs[0][2])
          a.fsqrt_d(R_D0, R_D0)
          store_val_f64(ins.dst, R_D0)
        elsif intr == "fmuladd.f64"
          load_op_f64(R_D0, cargs[0][1], cargs[0][2])
          load_op_f64(R_D1, cargs[1][1], cargs[1][2])
          load_op_f64(R_D2, cargs[2][1], cargs[2][2])
          a.fmadd_d(R_D0, R_D0, R_D1, R_D2)
          store_val_f64(ins.dst, R_D0)
        elsif intr == "memcpy.p0.p0.i64"
          load_op64(R_X0, cargs[0][1], cargs[0][2], LLTY_PTR)
          load_op64(R_X1, cargs[1][1], cargs[1][2], LLTY_PTR)
          load_op64(R_X2, cargs[2][1], cargs[2][2], LLTY_I64)
          @mod_info.intern_sym("memcpy", LLSYM_EXT_FN)
          a.bl_sym(@is_macho ? "_memcpy" : "memcpy")
      elsif op == :call_asm
        tmpl = ins.extra[0]
        aargs = ins.extra[1]
        if tmpl == "" && aargs.size() >= 1 && ins.dst >= 0
          # Zero-cost compiler barrier (`asm sideeffect "", "=r,0"`) without clobbering x19..x28!
          load_op64(R_X9, aargs[0][1], aargs[0][2], LLTY_I64)
          store_val64(ins.dst, R_X9)
        else
          # Evaluate inputs into caller-saved x0..x7 BEFORE spilling promoted x19..x26!
          ai = 0
          while ai < aargs.size() && ai < 8
            load_op64(ai, aargs[ai][1], aargs[ai][2], LLTY_I64)
            ai += 1
          ng_cs = @used_cs_g.size()
          if ng_cs > 0
            csi = 0
            while csi < ng_cs
              a.str_x(@used_cs_g[csi], R_SP, @asm_spill_off + csi * 8, R_X17)
              csi += 1
          ai = 0
          while ai < aargs.size() && ai < 8
            a.mov_r(20 + ai, ai)
            ai += 1
          op_regs = [19, 20, 21, 22, 23, 24, 25, 26, 27, 28]
          st = A64AsmState.new(a)
          st.assemble_text(a64_asm_unescape(tmpl, op_regs))
          a.mov_r(R_X9, R_X19) if ins.dst >= 0
          if ng_cs > 0
            csi = 0
            while csi < ng_cs
              a.ldr_x(@used_cs_g[csi], R_SP, @asm_spill_off + csi * 8, R_X17)
              csi += 1
          store_val64(ins.dst, R_X9) if ins.dst >= 0
      elsif op == :call
        cargs = ins.extra
        slab_puts_off = -1
        if @do_peephole && ins.dst < 0 && ins.k0 == LLOP_SYM && @mod_info.sym_list[ins.v0] == "w_puts" && cargs.size() == 1 && cargs[0][1] == LLOP_IMM
          slab_puts_off = ll_slab_puts_offset(@mod_info, @rodata_buf, cargs[0][2])
        if slab_puts_off >= 0
          a.addr_sym_local(R_X0, "__static_slab", slab_puts_off)
          @mod_info.intern_sym("puts", LLSYM_EXT_FN)
          a.bl_sym(@is_macho ? "_puts" : "puts")
        else
          # Stage stack arguments FIRST (`[sp + st_idx * 8]`), then register arguments (`x0..x7`, `d0..d7`)!
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
                load_op_f64(R_D16, ca[1], ca[2])
                a.str_d(R_D16, R_SP, st_idx * 8, R_X17)
                st_idx += 1
            else
              if reg_g_ops.size() < 8
                reg_g_ops.push(ca)
              else
                load_op64(R_X9, ca[1], ca[2], aty)
                a.str_x(R_X9, R_SP, st_idx * 8, R_X17)
                st_idx += 1
            ai += 1
          # Load indirect callee pointer into `R_X8` BEFORE filling x0..x7
          if ins.k0 != LLOP_SYM
            load_op64(R_X8, ins.k0, ins.v0, LLTY_PTR)
          fi = 0
          while fi < reg_f_ops.size()
            load_op_f64(fi, reg_f_ops[fi][1], reg_f_ops[fi][2])
            fi += 1
          gi = reg_g_ops.size() - 1
          while gi >= 0
            ca = reg_g_ops[gi]
            load_op64(gi, ca[1], ca[2], ca[0])
            gi -= 1

          if ins.k0 == LLOP_SYM
            cal_nm = @mod_info.sym_list[ins.v0]
            a.bl_sym(@is_macho ? ("_" + cal_nm) : cal_nm)
          else
            a.blr(R_X8)

          if ins.dst >= 0 && ins.ty != LLTY_VOID
            if ins.ty == LLTY_I128
              store_val128(ins.dst, R_X0, R_X1)
            elsif ins.ty == LLTY_F64 || ins.ty == LLTY_F32
              store_val_f64(ins.dst, R_D0)
            else
              store_val64(ins.dst, R_X0)
      elsif op == :br
        a.b(branch_target_label(bid, ins.v0))
      elsif op == :cond_br
        load_op64(R_X9, ins.k0, ins.v0, LLTY_I1)
        a.cbnz_x_far(R_X9, branch_target_label(bid, ins.v1))
        a.b(branch_target_label(bid, ins.v2))
      elsif op == :switch
        load_op64(R_X9, ins.k0, ins.v0, ins.ty)
        cases = ins.extra
        ci = 0
        while ci < cases.size()
          cv = cases[ci][0]
          cb = cases[ci][1]
          if cv >= 0 && cv <= 4095
            a.cmp_i(R_X9, cv)
          else
            a.mov_imm64(R_X10, cv)
            a.cmp_r(R_X9, R_X10)
          a.b_cond_far(CC_EQ, branch_target_label(bid, cb))
          ci += 1
        a.b(branch_target_label(bid, ins.v1))
      elsif op == :ret_void
        a.b(@l_epi)
      elsif op == :ret
        if ins.ty == LLTY_I128
          load_op128(R_X0, R_X1, ins.k0, ins.v0)
        elsif ins.ty == LLTY_F64 || ins.ty == LLTY_F32
          load_op_f64(R_D0, ins.k0, ins.v0)
        else
          load_op64(R_X0, ins.k0, ins.v0, ins.ty)
        a.b(@l_epi)
      elsif op == :unreachable
        a.brk(1)
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
      raise "Cinder LL->A64 fixup overflow in function " + @fn_ir.name
    @a

-> cinder_ms_since(t0)
  ((clock - t0) * ~1000.0).floor()

-> lla64_mark_ref(ref_syms, ref_wl, nm)
  return nil if nm == nil
  if ref_syms[nm] == nil
    ref_syms[nm] = true
    ref_wl.push(nm) if ref_wl != nil
  nil

# Emit a compiled `LLFunc` (`fa = LLA64FuncCompiler.compile()`) into `writer.text` and record relocations
-> lla64_emit_func_to_writer(writer, is_macho, fn_ir, fa, fn_offsets, ref_syms, ref_wl = nil)
  writer.text.align_to(8, 0)
  fn_off = writer.text.len
  fn_sz = fa.byte_len()
  writer.text.put_buf(fa.buf)
  fn_offsets[fn_ir.name] = [fn_off, fn_sz]
  if is_macho
    writer.define_sym(fn_ir.name, MSEC_TEXT, fn_off, fn_ir.is_internal ? MSYM_LOCAL : MSYM_GLOBAL)
  else
    writer.define_sym(fn_ir.name, ESEC_TEXT, fn_off, fn_sz, fn_ir.is_internal ? ESYM_LOCAL : ESYM_GLOBAL, ESTT_FUNC)

  ri = 0
  while ri < fa.rel_off.size()
    roff = fn_off + fa.rel_off[ri]
    rsym = fa.rel_sym[ri]
    rkind = fa.rel_kind[ri]
    radd = fa.rel_add[ri]
    lla64_mark_ref(ref_syms, ref_wl, rsym)
    if is_macho && rsym.starts_with?("_")
      lla64_mark_ref(ref_syms, ref_wl, rsym.slice(1, cinder_blen(rsym) - 1))
    if is_macho
      if rkind == CREL_A64_BRANCH26
        writer.add_text_reloc_raw(roff, rsym, rkind, radd)
      else
        writer.add_text_reloc(roff, rsym, rkind, radd)
    else
      writer.add_text_reloc(roff, rsym, rkind, radd)
    ri += 1
  nil

-> lla64_assemble_mod_asm(mod_info, writer, is_macho, fn_offsets, ref_syms, ref_wl)
  return nil if mod_info.mod_asm_lines.size() == 0
  asm_a64 = CinderA64.new(mod_info.mod_asm_lines.size() * 4 + 64)
  st = A64AsmState.new(asm_a64)
  joined_sb = StringBuffer(mod_info.mod_asm_lines.size() * 48)
  mi = 0
  while mi < mod_info.mod_asm_lines.size()
    joined_sb << a64_asm_unescape(mod_info.mod_asm_lines[mi], nil)
    joined_sb << "\n"
    mi += 1
  st.assemble_text(joined_sb.to_s())
  if !asm_a64.patch_fixups()
    raise "Cinder ARM64 module asm fixup failed"
  writer.text.align_to(64, 0)
  base_off = writer.text.len
  writer.text.put_buf(asm_a64.buf)
  di = 0
  while di < st.def_syms.size()
    raw_nm = st.def_syms[di][0]
    soff = base_off + st.def_syms[di][1]
    is_glob = st.globl_syms[raw_nm] == true
    if is_macho
      writer.define_sym_raw(raw_nm, MSEC_TEXT, soff, is_glob ? MSYM_GLOBAL : MSYM_LOCAL)
      ir_nm = raw_nm.starts_with?("_") ? raw_nm.slice(1, raw_nm.size() - 1) : raw_nm
      fn_offsets[ir_nm] = [soff, 0]
    else
      writer.define_sym(raw_nm, ESEC_TEXT, soff, 0, is_glob ? ESYM_GLOBAL : ESYM_LOCAL, ESTT_FUNC)
      fn_offsets[raw_nm] = [soff, 0]
    di += 1
  ri = 0
  while ri < asm_a64.rel_off.size()
    roff = base_off + asm_a64.rel_off[ri]
    rsym = asm_a64.rel_sym[ri]
    rkind = asm_a64.rel_kind[ri]
    radd = asm_a64.rel_add[ri]
    lla64_mark_ref(ref_syms, ref_wl, rsym)
    lla64_mark_ref(ref_syms, ref_wl, rsym.slice(1, cinder_blen(rsym) - 1)) if is_macho && rsym.starts_with?("_")
    if is_macho
      writer.add_text_reloc_raw(roff, rsym, rkind, radd)
    else
      writer.add_text_reloc(roff, rsym, rkind, radd)
    ri += 1
  nil

-> lla64_compile_span_into(src, src_ptr, mod_info, span, inl_ctx, is_macho, cfg, writer, fn_offsets, ref_syms, ref_wl, prof, prof_sec)
  if prof
    ts0 = clock
    fn_ir = ll_parse_function(src, src_ptr, mod_info, span, false)
    ts1 = clock
    ll_opt_function(fn_ir, inl_ctx, cfg)
    ts2 = clock
    fc = LLA64FuncCompiler.new(fn_ir, mod_info, is_macho, cfg, writer.rodata)
    fa = fc.compile()
    lla64_emit_func_to_writer(writer, is_macho, fn_ir, fa, fn_offsets, ref_syms, ref_wl)
    ts3 = clock
    prof_sec[0] = prof_sec[0] + (ts1 - ts0)
    prof_sec[1] = prof_sec[1] + (ts2 - ts1)
    prof_sec[2] = prof_sec[2] + (ts3 - ts2)
  else
    fn_ir = ll_parse_function(src, src_ptr, mod_info, span, false)
    ll_opt_function(fn_ir, inl_ctx, cfg)
    fc = LLA64FuncCompiler.new(fn_ir, mod_info, is_macho, cfg, writer.rodata)
    fa = fc.compile()
    lla64_emit_func_to_writer(writer, is_macho, fn_ir, fa, fn_offsets, ref_syms, ref_wl)
  nil

# Compile an entire `.ll` text string into `MachO64Writer` (`is_macho = true`) or `Elf64Writer` (`is_macho = false`)!
-> cinder_compile_ll_a64(src, is_macho = true, opt_cfg = nil)
  prof = env("CINDER_PROFILE") == "1"
  t_p = [clock, ~0.0, ~0.0, ~0.0]
  cfg = opt_cfg != nil ? opt_cfg : cinder_opt_from_env(2)
  src = src + "                        " if cinder_blen(src) <= 16
  writer = is_macho ? MachO64Writer.new() : Elf64Writer.new(ELF_EM_AARCH64)
  mod_info = ll_scan_module_and_emit_globals(src, writer, is_macho)
  t_p[1] = clock
  src_ptr = cinder_heap_str_ptr(wvalue_bits(src) ## i64)
  inl_ctx = LLInlineContext.new(src, src_ptr, mod_info, cfg)
  if cfg.opt_level >= 1 && (cfg.pass_enabled?("ipa-sccp") || cfg.lto_enabled?())
    ll_build_ipa_summaries(src, src_ptr, mod_info, inl_ctx, cfg)
  t_p[2] = clock

  fn_offsets = {}
  ref_syms = {}
  ref_wl = []
  ui = 0
  while ui < mod_info.used_syms.size()
    lla64_mark_ref(ref_syms, ref_wl, mod_info.used_syms[ui])
    ui += 1
  ali = 0
  while ali < mod_info.aliases.size()
    lla64_mark_ref(ref_syms, ref_wl, mod_info.aliases[ali][1])
    ali += 1
  if is_macho
    cri = 0
    while cri < writer.const_rel_sym.size()
      rs = writer.const_rel_sym[cri]
      lla64_mark_ref(ref_syms, ref_wl, rs)
      lla64_mark_ref(ref_syms, ref_wl, rs.slice(1, cinder_blen(rs) - 1)) if rs.starts_with?("_")
      cri += 1
    dri = 0
    while dri < writer.data_rel_sym.size()
      rs = writer.data_rel_sym[dri]
      lla64_mark_ref(ref_syms, ref_wl, rs)
      lla64_mark_ref(ref_syms, ref_wl, rs.slice(1, cinder_blen(rs) - 1)) if rs.starts_with?("_")
      dri += 1
  else
    rri = 0
    while rri < writer.ro_rel_sym.size()
      lla64_mark_ref(ref_syms, ref_wl, writer.ro_rel_sym[rri])
      rri += 1
    dri = 0
    while dri < writer.data_rel_sym.size()
      lla64_mark_ref(ref_syms, ref_wl, writer.data_rel_sym[dri])
      dri += 1

  # 1. Assemble `module asm` block (if present — e.g., macOS ARM64 limb_kernels!)
  lla64_assemble_mod_asm(mod_info, writer, is_macho, fn_offsets, ref_syms, ref_wl)
  t_p[3] = clock

  # 2. Stream, optimize, and compile each `define` function into `writer.text`.
  prof_sec = [~0.0, ~0.0, ~0.0]
  n_compiled = 0
  drop_dead_int = !cfg.debug && cfg.pass_enabled?("dce")
  deferred_map = {}
  deferred_emitted = {}
  fi = 0
  while fi < mod_info.fn_spans.size()
    span = mod_info.fn_spans[fi]
    hdr = span[0]
    is_int_hdr = hdr.index(" internal ") != nil || hdr.index(" private ") != nil
    if drop_dead_int && is_int_hdr
      dat = ll_index_outside_quotes(hdr, 64, 0)
      dlp = ll_index_outside_quotes(hdr, 40, dat)
      dnm = ll_clean_sym(hdr.slice(dat, dlp - dat))
      deferred_map[dnm] = span
    else
      lla64_compile_span_into(src, src_ptr, mod_info, span, inl_ctx, is_macho, cfg, writer, fn_offsets, ref_syms, ref_wl, prof, prof_sec)
      n_compiled += 1
    fi += 1

  wi = 0
  while wi < ref_wl.size()
    wnm = ref_wl[wi]
    wi += 1
    dspan = deferred_map[wnm]
    if dspan != nil && deferred_emitted[wnm] == nil
      deferred_emitted[wnm] = true
      lla64_compile_span_into(src, src_ptr, mod_info, dspan, inl_ctx, is_macho, cfg, writer, fn_offsets, ref_syms, ref_wl, prof, prof_sec)
      n_compiled += 1

  # 3. Emit `hidden alias` symbols pointing at their target functions!
  ai = 0
  while ai < mod_info.aliases.size()
    al_nm = mod_info.aliases[ai][0]
    tg_nm = mod_info.aliases[ai][1]
    info = fn_offsets[tg_nm]
    if info != nil
      if is_macho
        writer.define_sym(al_nm, MSEC_TEXT, info[0], MSYM_HIDDEN)
      else
        writer.define_sym(al_nm, ESEC_TEXT, info[0], info[1], ESYM_HIDDEN, ESTT_FUNC)
    ai += 1

  if prof
    total_fns = mod_info.fn_spans.size()
    dropped_fns = total_fns - n_compiled
    ms_scan = ((t_p[1] - t_p[0]) * ~1000.0).to_i()
    ms_ipa  = ((t_p[2] - t_p[1]) * ~1000.0).to_i()
    ms_asm  = ((t_p[3] - t_p[2]) * ~1000.0).to_i()
    ms_prs  = (prof_sec[0] * ~1000.0).to_i()
    ms_opt  = (prof_sec[1] * ~1000.0).to_i()
    ms_cg   = (prof_sec[2] * ~1000.0).to_i()
    ccall("w_eputs", "\[cinder-profile\] functions: total=" + total_fns.to_s() + " compiled=" + n_compiled.to_s() + " dce_skipped=" + dropped_fns.to_s() + " inline_cached=" + inl_ctx.callee_cache.keys.size().to_s())
    ccall("w_eputs", "\[cinder-profile\] phases (ms): scan_globals=" + ms_scan.to_s() + " ipa_summaries=" + ms_ipa.to_s() + " mod_asm=" + ms_asm.to_s() + " ir_parse=" + ms_prs.to_s() + " ir_opt=" + ms_opt.to_s() + " a64_codegen=" + ms_cg.to_s())
    if is_macho
      ccall("w_eputs", "\[cinder-profile\] sections (bytes): __text=" + writer.text.len.to_s() + " __const=" + writer.rodata.len.to_s() + " __data_const=" + writer.const_data.len.to_s() + " __data=" + writer.data.len.to_s() + " __bss=" + writer.bss_size.to_s() + " syms=" + writer.sym_names.size().to_s() + " text_relocs=" + writer.text_rel_off.size().to_s())
  cfg.print_report("aot-a64") if cfg.print_passes
  writer
