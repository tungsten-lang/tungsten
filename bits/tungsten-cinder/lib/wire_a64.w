# cinder/wire_a64 — Pure-Tungsten WIRE IR -> ARM64 JIT & Native Code Compiler.
#
# Upgraded from the initial prototype with:
#   1. Exact `WArray->start` slice offset handling in `:arr_data_ptr` (`slots + start * elem_bytes`).
#   2. Exact callee-saved register save/restore (only saves the pairs actually used by the function).
#   3. Cross-platform symbol resolution (`cinder_resolve_c_sym`) & ByteBuf emission (`compile_bytes` + `compile`).

use ./a64
use ./jit_mem
use ./wire_ir
use ./wire_opt
use ./opt_config

-> wire_a64_icmp_cc(pred)
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

-> wire_a64_fcmp_cc(pred)
  return CC_EQ if pred == :oeq || pred == :eq
  return CC_NE if pred == :one || pred == :ne
  return CC_MI if pred == :olt || pred == :lt
  return CC_LS if pred == :ole || pred == :le
  return CC_GT if pred == :ogt || pred == :gt
  return CC_GE if pred == :oge || pred == :ge
  CC_NE

+ WireA64Compiler
  rw :wf, :tier, :opt_cfg, :wmod, :a, :blk_labels, :l_epi
  rw :slot_loc, :vreg_loc, :used_gprs, :used_fprs, :spill_bytes, :save_base_bytes
  rw :frame_size, :has_calls, :const_i64

  -> new(@wf, @tier = 2, @opt_cfg = nil, @wmod = nil)
    @opt_cfg = cinder_opt_for_tier(@tier) if @opt_cfg == nil
    @a = CinderA64.new(512)
    @blk_labels = []
    @slot_loc = []
    @vreg_loc = []
    @used_gprs = []
    @used_fprs = []
    @spill_bytes = 0
    @save_base_bytes = 16
    @frame_size = 0
    @has_calls = false
    @const_i64 = {}

  -> alloc_spill(is_fp)
    off = @save_base_bytes + @spill_bytes
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

    # Reserve up to 160 bytes at bottom of frame for FP/LR + exact callee-saved pairs
    @save_base_bytes = 160

    cs_g = [R_X19, R_X20, R_X21, R_X22, R_X23, R_X24, R_X25, R_X26, R_X27, R_X28]
    cs_f = [R_D8, R_D9, R_D10, R_D11, R_D12, R_D13, R_D14, R_D15]
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

    @slot_loc = Array.new(ns, nil)
    slot_score = Array.new(ns, 0)
    bi = 0
    while bi < nb
      blk = wf.blocks[bi]
      w = bi > 0 ? 8 : 1
      ii = 0
      while ii < blk.insts.size
        iop = blk.insts[ii].op
        if iop == :load_i64 || iop == :store_i64 || iop == :load_double || iop == :store_double
          slot_score[blk.insts[ii].imm] = slot_score[blk.insts[ii].imm] + w
        ii += 1
      bi += 1
    # Allocate callee-saved registers to the hottest live slots first!
    live_slots = []
    si = 0
    while si < ns
      live_slots.push(si) if slot_score[si] > 0
      si += 1
    # Simple insertion sort descending by `slot_score` (deterministic tie-break on slot index)
    li = 1
    while li < live_slots.size
      cur_s = live_slots[li]
      cur_sc = slot_score[cur_s]
      lj = li - 1
      while lj >= 0 && slot_score[live_slots[lj]] < cur_sc
        live_slots[lj + 1] = live_slots[lj]
        lj -= 1
      live_slots[lj + 1] = cur_s
      li += 1
    li = 0
    while li < live_slots.size
      si = live_slots[li]
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
      li += 1

    vi = 0
    while vi < nv
      if @vreg_loc[vi] == nil && (cross_blk[vi] || vi < wf.params.size)
        cval = @const_i64[vi]
        if cval != nil
          # Never spill constants to stack! Small constants rematerialize in 1 cycle (`movz`/`movn`),
          # and large 64-bit constants only take a callee-saved GPR if one is still free!
          if (cval < -65536 || cval > 65535) && cgi < cs_g.size
            r = cs_g[cgi]; cgi += 1
            @vreg_loc[vi] = [:gpr, r]
            @used_gprs.push(r)
          else
            @vreg_loc[vi] = [:imm, cval]
        else
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

    tmp_g = [R_X15, R_X14, R_X13, R_X12, R_X11, R_X10, R_X9]
    tmp_f = [R_D31, R_D30, R_D29, R_D28, R_D27, R_D26, R_D25, R_D24, R_D23, R_D22, R_D21, R_D20, R_D19, R_D18, R_D17, R_D16]
    last_use = Array.new(nv, -1)
    bi = 0
    while bi < nb
      blk = wf.blocks[bi]
      n_ins = blk.insts.size
      call_idxs = []
      ii = 0
      while ii < n_ins
        ins = blk.insts[ii]
        call_idxs.push(ii) if ins.op == :call_c_f64 || ins.op == :call_direct_i64
        last_use[ins.a] = ii if ins.a >= 0
        last_use[ins.b] = ii if ins.b >= 0
        last_use[ins.c] = ii if ins.c >= 0
        if ins.args != nil
          ai = 0
          while ai < ins.args.size
            av = ins.args[ai]
            last_use[av] = ii if av >= 0
            ai += 1
        ii += 1

      free_g = []
      gi = 0
      while gi < tmp_g.size
        free_g.push(tmp_g[gi]); gi += 1
      free_f = []
      fi = 0
      while fi < tmp_f.size
        free_f.push(tmp_f[fi]); fi += 1
      # `active_g` / `active_f`: `[vreg, reg]` pairs currently occupying scratch registers in `blk`
      active_g = []
      active_f = []

      ii = 0
      while ii < n_ins
        ins = blk.insts[ii]
        d = ins.dst
        if d >= 0 && @vreg_loc[d] == nil
          if ins.op == :const_i64 && @opt_cfg.pass_enabled?("peephole")
            @vreg_loc[d] = [:imm, ins.imm]
          else
            lu = last_use[d]
            lu = ii if lu < ii
            spans_call = false
            ci = 0
            while ci < call_idxs.size
              cpos = call_idxs[ci]
              if cpos > ii && cpos <= lu
                spans_call = true
                break
              ci += 1
            is_f = wf.vreg_types[d] == :f64
            if spans_call
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
                if free_f.size > 0
                  rf = free_f.pop()
                  @vreg_loc[d] = [:fpr, rf]
                  active_f.push([d, rf])
                else
                  @vreg_loc[d] = alloc_spill(true)
              else
                if free_g.size > 0
                  rg = free_g.pop()
                  @vreg_loc[d] = [:gpr, rg]
                  active_g.push([d, rg])
                else
                  @vreg_loc[d] = alloc_spill(false)

        # Recycle scratch registers whose `last_use <= ii` AFTER allocating `ins.dst`
        # so `dst` never aliases a live input operand of `ins`!
        if active_g.size > 0
          kept_ag = []
          agi = 0
          while agi < active_g.size
            pair = active_g[agi]
            if last_use[pair[0]] <= ii
              free_g.push(pair[1])
            else
              kept_ag.push(pair)
            agi += 1
          active_g = kept_ag
        if active_f.size > 0
          kept_af = []
          afi = 0
          while afi < active_f.size
            pair = active_f[afi]
            if last_use[pair[0]] <= ii
              free_f.push(pair[1])
            else
              kept_af.push(pair)
            afi += 1
          active_f = kept_af
        ii += 1
      bi += 1

    ng_pairs = (@used_gprs.size + 1) / 2
    nf_pairs = (@used_fprs.size + 1) / 2
    exact_save = 16 + ng_pairs * 16 + nf_pairs * 16
    if @spill_bytes == 0
      @frame_size = exact_save
    else
      @frame_size = ((@save_base_bytes + @spill_bytes + 15) / 16) * 16
    nil

  -> read_g(vreg, scratch)
    loc = @vreg_loc[vreg]
    return loc[1] if loc[0] == :gpr
    if loc[0] == :imm
      @a.mov_imm64(scratch, loc[1])
      return scratch
    @a.ldr_x(scratch, R_SP, loc[1])
    scratch

  -> dst_g(vreg, scratch)
    loc = @vreg_loc[vreg]
    loc[0] == :gpr ? loc[1] : scratch

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
    a.sub_sp_imm(R_SP, R_SP, fs)
    a.stp_x(R_FP, R_LR, R_SP, 0)
    a.mov_sp(R_FP, R_SP)
    ng = @used_gprs.size
    a.stp_x(R_X19, R_X20, R_SP, 16) if ng >= 1
    a.stp_x(R_X21, R_X22, R_SP, 32) if ng >= 3
    a.stp_x(R_X23, R_X24, R_SP, 48) if ng >= 5
    a.stp_x(R_X25, R_X26, R_SP, 64) if ng >= 7
    a.stp_x(R_X27, R_X28, R_SP, 80) if ng >= 9
    fp_base = 16 + ((ng + 1) / 2) * 16
    nf = @used_fprs.size
    a.stp_d(R_D8,  R_D9,  R_SP, fp_base)      if nf >= 1
    a.stp_d(R_D10, R_D11, R_SP, fp_base + 16) if nf >= 3
    a.stp_d(R_D12, R_D13, R_SP, fp_base + 32) if nf >= 5
    a.stp_d(R_D14, R_D15, R_SP, fp_base + 48) if nf >= 7

    abi = @wf.abi
    pi = 0
    while pi < @wf.params.size
      pt = @wf.param_types[pi]
      if pt == :f64
        if abi == :raw
          write_f(pi, pi)
        else
          a.mov_imm64(R_X16, 281474976710656)
          a.sub_r(R_X17, pi, R_X16)
          a.fmov_d_x(R_D6, R_X17)
          write_f(pi, R_D6)
      elsif pt == :i64 && abi == :wvalue_ret_f64
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
    ng = @used_gprs.size
    fp_base = 16 + ((ng + 1) / 2) * 16
    nf = @used_fprs.size
    a.ldp_d(R_D8,  R_D9,  R_SP, fp_base)      if nf >= 1
    a.ldp_d(R_D10, R_D11, R_SP, fp_base + 16) if nf >= 3
    a.ldp_d(R_D12, R_D13, R_SP, fp_base + 32) if nf >= 5
    a.ldp_d(R_D14, R_D15, R_SP, fp_base + 48) if nf >= 7
    a.ldp_x(R_X19, R_X20, R_SP, 16) if ng >= 1
    a.ldp_x(R_X21, R_X22, R_SP, 32) if ng >= 3
    a.ldp_x(R_X23, R_X24, R_SP, 48) if ng >= 5
    a.ldp_x(R_X25, R_X26, R_SP, 64) if ng >= 7
    a.ldp_x(R_X27, R_X28, R_SP, 80) if ng >= 9
    a.ldp_x(R_FP, R_LR, R_SP, 0)
    a.add_sp_imm(R_SP, R_SP, fs)
    a.ret
    nil

  -> emit_inst(ins, next_ins)
    a = @a
    op = ins.op
    if op == :const_i64
      return false if @vreg_loc[ins.dst][0] == :imm
      dr = dst_g(ins.dst, R_X16)
      a.mov_imm64(dr, ins.imm)
      write_g(ins.dst, dr)
    elsif op == :const_f64
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
      # Untag WArray* (`arr & 0x00007FFFFFFFFFF0`), load `slots` (+16) AND `start` (+4) * elem_bytes!
      ar = read_g(ins.a, R_X16)
      dr = dst_g(ins.dst, R_X16)
      sh = wire_ebits_shift(ins.ebits)
      a.and_x_ptr47(R_X17, ar)
      a.ldrsw(R_X8, R_X17, 4)
      a.ldr_x(dr, R_X17, 16)
      a.add_r(dr, dr, R_X8, sh)
      write_g(ins.dst, dr)
    elsif op == :array_size_raw
      ar = read_g(ins.a, R_X16)
      dr = dst_g(ins.dst, R_X16)
      a.and_x_ptr47(R_X17, ar)
      a.ldrsw(dr, R_X17, 8)
      write_g(ins.dst, dr)
    elsif op == :typed_array_get_inline
      pr = read_g(ins.a, R_X16)
      eb = ins.ebits
      cidx = @const_i64[ins.b]
      if (eb == 64 || eb == 66) && cidx != nil && cidx >= 0 && cidx <= 4095
        dr = dst_g(ins.dst, R_X16)
        a.ldr_x(dr, pr, cidx * 8)
        write_g(ins.dst, dr)
      else
        ir = read_g(ins.b, R_X17)
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
          dr = dst_f(ins.dst, R_D6)
          a.ldr_h_idx(dr, pr, ir)
          a.fcvt_d_h(dr, dr)
          write_f(ins.dst, dr)
        else
          dr = dst_g(ins.dst, R_X16)
          if eb == 108
            a.ldrsb_idx(dr, pr, ir); a.sxtw(dr, dr)
          elsif eb == 8
            a.ldrb_idx(dr, pr, ir)
          elsif eb == 116
            a.ldrsh_idx(dr, pr, ir); a.sxtw(dr, dr)
          elsif eb == 16
            a.ldrh_idx(dr, pr, ir)
          elsif eb == 33
            a.ldrsw_idx(dr, pr, ir)
          elsif eb == 32
            a.ldr_w_idx(dr, pr, ir)
          else
            a.ldr_x_idx(dr, pr, ir)
          write_g(ins.dst, dr)
    elsif op == :typed_array_set_inline
      pr = read_g(ins.a, R_X16)
      eb = ins.ebits
      cidx = @const_i64[ins.b]
      if (eb == 64 || eb == 66) && cidx != nil && cidx >= 0 && cidx <= 4095
        vr = read_g(ins.c, R_X8)
        a.str_x(vr, pr, cidx * 8)
      else
        ir = read_g(ins.b, R_X17)
        if eb == -64
          vr = read_f(ins.c, R_D6); a.str_d_idx(vr, pr, ir)
        elsif eb == -32
          vr = read_f(ins.c, R_D6); a.fcvt_s_d(R_D7, vr); a.str_s_idx(R_D7, pr, ir)
        elsif eb == -16
          vr = read_f(ins.c, R_D6); a.fcvt_h_d(R_D7, vr); a.str_h_idx(R_D7, pr, ir)
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
    elsif op == :raw_load
      pr = read_g(ins.a, R_X16)
      eb = ins.ebits
      coff = @const_i64[ins.b]
      if coff != nil
        if eb == -64
          dr = dst_f(ins.dst, R_D6); a.ldr_d(dr, pr, coff); write_f(ins.dst, dr)
        else
          dr = dst_g(ins.dst, R_X16)
          if eb == 8
            a.ldrb(dr, pr, coff)
          elsif eb == 108
            a.ldrb(dr, pr, coff); a.sxtb_x(dr, dr)
          elsif eb == 16
            a.ldrh(dr, pr, coff)
          elsif eb == 116
            a.ldrh(dr, pr, coff); a.sxth_x(dr, dr)
          elsif eb == 32
            a.ldr_w(dr, pr, coff)
          elsif eb == 33
            a.ldrsw(dr, pr, coff)
          else
            a.ldr_x(dr, pr, coff)
          write_g(ins.dst, dr)
      else
        or_r = read_g(ins.b, R_X17)
        if eb == -64
          dr = dst_f(ins.dst, R_D6); a.add_r(R_X17, pr, or_r); a.ldr_d(dr, R_X17, 0); write_f(ins.dst, dr)
        else
          dr = dst_g(ins.dst, R_X16)
          if eb == 8
            a.ldrb_idx(dr, pr, or_r)
          elsif eb == 108
            a.ldrsb_idx(dr, pr, or_r)
          elsif eb == 16
            a.add_r(R_X17, pr, or_r); a.ldrh(dr, R_X17, 0)
          elsif eb == 116
            a.add_r(R_X17, pr, or_r); a.ldrh(dr, R_X17, 0); a.sxth_x(dr, dr)
          elsif eb == 32
            a.add_r(R_X17, pr, or_r); a.ldr_w(dr, R_X17, 0)
          elsif eb == 33
            a.add_r(R_X17, pr, or_r); a.ldrsw(dr, R_X17, 0)
          else
            a.ldr_x_reg(dr, pr, or_r)
          write_g(ins.dst, dr)
    elsif op == :raw_store
      pr = read_g(ins.a, R_X16)
      eb = ins.ebits
      coff = @const_i64[ins.b]
      if coff != nil
        if eb == -64
          vr = read_f(ins.c, R_D6); a.str_d(vr, pr, coff)
        else
          vr = read_g(ins.c, R_X8)
          if eb == 8 || eb == 108
            a.strb(vr, pr, coff)
          elsif eb == 16 || eb == 116
            a.strh(vr, pr, coff)
          elsif eb == 32 || eb == 33
            a.str_w(vr, pr, coff)
          else
            a.str_x(vr, pr, coff)
      else
        or_r = read_g(ins.b, R_X17)
        if eb == -64
          vr = read_f(ins.c, R_D6); a.add_r(R_X17, pr, or_r); a.str_d(vr, R_X17, 0)
        else
          vr = read_g(ins.c, R_X8)
          if eb == 8 || eb == 108
            a.strb_idx(vr, pr, or_r)
          elsif eb == 16 || eb == 116
            a.add_r(R_X17, pr, or_r); a.strh(vr, R_X17, 0)
          elsif eb == 32 || eb == 33
            a.add_r(R_X17, pr, or_r); a.str_w(vr, R_X17, 0)
          else
            a.str_x_reg(vr, pr, or_r)
    elsif op == :ctz_i64
      ra = read_g(ins.a, R_X16); dr = dst_g(ins.dst, R_X16)
      a.rbit_x(dr, ra); a.clz_x(dr, dr); write_g(ins.dst, dr)
    elsif op == :clz_i64
      ra = read_g(ins.a, R_X16); dr = dst_g(ins.dst, R_X16)
      a.clz_x(dr, ra); write_g(ins.dst, dr)
    elsif op == :addcarry_u64
      ra = read_g(ins.a, R_X16); rb = read_g(ins.b, R_X17); dr = dst_g(ins.dst, R_X16)
      a.cmn_r(ra, rb); a.cset(dr, CC_HS); write_g(ins.dst, dr)
    elsif op == :subborrow_u64
      ra = read_g(ins.a, R_X16); rb = read_g(ins.b, R_X17); dr = dst_g(ins.dst, R_X16)
      a.cmp_r(ra, rb); a.cset(dr, CC_LO); write_g(ins.dst, dr)
    elsif op == :mulhi_u64
      ra = read_g(ins.a, R_X16); rb = read_g(ins.b, R_X17); dr = dst_g(ins.dst, R_X16)
      a.umulh_x(dr, ra, rb); write_g(ins.dst, dr)
    elsif op == :adds_u64
      ra = read_g(ins.a, R_X16); rb = read_g(ins.b, R_X17); dr = dst_g(ins.dst, R_X16)
      a.adds_r(dr, ra, rb); write_g(ins.dst, dr)
    elsif op == :adcs_u64
      ra = read_g(ins.a, R_X16); rb = read_g(ins.b, R_X17); dr = dst_g(ins.dst, R_X16)
      a.adcs_x(dr, ra, rb); write_g(ins.dst, dr)
    elsif op == :cset_carry_u64
      dr = dst_g(ins.dst, R_X16)
      a.cset(dr, CC_HS); write_g(ins.dst, dr)
    elsif op == :subs_u64
      ra = read_g(ins.a, R_X16); rb = read_g(ins.b, R_X17); dr = dst_g(ins.dst, R_X16)
      a.subs_r(dr, ra, rb); write_g(ins.dst, dr)
    elsif op == :sbcs_u64
      ra = read_g(ins.a, R_X16); rb = read_g(ins.b, R_X17); dr = dst_g(ins.dst, R_X16)
      a.sbcs_x(dr, ra, rb); write_g(ins.dst, dr)
    elsif op == :cset_borrow_u64
      dr = dst_g(ins.dst, R_X16)
      a.cset(dr, CC_LO); write_g(ins.dst, dr)
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
      a.sdiv_x(R_X8, ra, rb); a.msub_x(dr, R_X8, rb, ra); write_g(ins.dst, dr)
    elsif op == :urem_i64
      ra = read_g(ins.a, R_X16); rb = read_g(ins.b, R_X17); dr = dst_g(ins.dst, R_X8)
      a.udiv_x(R_X8, ra, rb); a.msub_x(dr, R_X8, rb, ra); write_g(ins.dst, dr)
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
      cv = @const_i64[ins.b]
      if cv != nil && cv >= 0 && cv <= 63
        ra = read_g(ins.a, R_X16); dr = dst_g(ins.dst, R_X16)
        a.lsl_xi(dr, ra, cv); write_g(ins.dst, dr)
      else
        ra = read_g(ins.a, R_X16); rb = read_g(ins.b, R_X17); dr = dst_g(ins.dst, R_X16)
        a.lsl_x(dr, ra, rb); write_g(ins.dst, dr)
    elsif op == :ashr_i64
      cv = @const_i64[ins.b]
      if cv != nil && cv >= 0 && cv <= 63
        ra = read_g(ins.a, R_X16); dr = dst_g(ins.dst, R_X16)
        a.asr_xi(dr, ra, cv); write_g(ins.dst, dr)
      else
        ra = read_g(ins.a, R_X16); rb = read_g(ins.b, R_X17); dr = dst_g(ins.dst, R_X16)
        a.asr_x(dr, ra, rb); write_g(ins.dst, dr)
    elsif op == :lshr_i64
      cv = @const_i64[ins.b]
      if cv != nil && cv >= 0 && cv <= 63
        ra = read_g(ins.a, R_X16); dr = dst_g(ins.dst, R_X16)
        a.lsr_xi(dr, ra, cv); write_g(ins.dst, dr)
      else
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
      cv = @const_i64[ins.b]; ra = read_g(ins.a, R_X16); dr = dst_g(ins.dst, R_X16)
      if cv != nil && cv >= 0 && cv <= 31
        a.lsl_wi(dr, ra, cv)
      else
        rb = read_g(ins.b, R_X17); a.lsl_w(dr, ra, rb)
      a.sxtw(dr, dr); write_g(ins.dst, dr)
    elsif op == :ashr_i32
      cv = @const_i64[ins.b]; ra = read_g(ins.a, R_X16); dr = dst_g(ins.dst, R_X16)
      if cv != nil && cv >= 0 && cv <= 31
        a.asr_wi(dr, ra, cv)
      else
        rb = read_g(ins.b, R_X17); a.asr_w(dr, ra, rb)
      a.sxtw(dr, dr); write_g(ins.dst, dr)
    elsif op == :lshr_i32
      cv = @const_i64[ins.b]; ra = read_g(ins.a, R_X16); dr = dst_g(ins.dst, R_X16)
      if cv != nil && cv >= 0 && cv <= 31
        a.lsr_wi(dr, ra, cv)
      else
        rb = read_g(ins.b, R_X17); a.lsr_w(dr, ra, rb)
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
    elsif op == :fmadd_f64
      ra = read_f(ins.a, R_D6); rb = read_f(ins.b, R_D7); rc = read_f(ins.c, R_D5); dr = dst_f(ins.dst, R_D6)
      a.fmadd_d(dr, ra, rb, rc); write_f(ins.dst, dr)
    elsif op == :fmsub_f64
      ra = read_f(ins.a, R_D6); rb = read_f(ins.b, R_D7); rc = read_f(ins.c, R_D5); dr = dst_f(ins.dst, R_D6)
      a.fmsub_d(dr, ra, rb, rc); write_f(ins.dst, dr)
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
      a.fmov_x_d(R_X16, ra); a.mov_imm64(R_X17, 281474976710656); a.add_r(dr, R_X16, R_X17)
      write_g(ins.dst, dr)
    elsif op == :unbox_float
      ra = read_g(ins.a, R_X16); dr = dst_f(ins.dst, R_D6)
      a.mov_imm64(R_X17, 281474976710656); a.sub_r(R_X16, ra, R_X17); a.fmov_d_x(dr, R_X16)
      write_f(ins.dst, dr)
    elsif op == :icmp_i64
      ra = read_g(ins.a, R_X16)
      cv = @const_i64[ins.b]
      cc = wire_a64_icmp_cc(ins.pred)
      if cv != nil && cv >= 0 && cv <= 4095
        a.cmp_i(ra, cv)
      else
        rb = read_g(ins.b, R_X17)
        a.cmp_r(ra, rb)
      if next_ins != nil && next_ins.op == :cond_br && next_ins.a == ins.dst
        a.b_cond(cc, @blk_labels[next_ins.t_true])
        a.b(@blk_labels[next_ins.t_false])
        return true
      dr = dst_g(ins.dst, R_X16)
      a.cset(dr, cc); write_g(ins.dst, dr)
    elsif op == :fcmp_f64
      ra = read_f(ins.a, R_D6); rb = read_f(ins.b, R_D7)
      cc = wire_a64_fcmp_cc(ins.pred)
      a.fcmp_d(ra, rb)
      if next_ins != nil && next_ins.op == :cond_br && next_ins.a == ins.dst
        a.b_cond(cc, @blk_labels[next_ins.t_true])
        a.b(@blk_labels[next_ins.t_false])
        return true
      dr = dst_g(ins.dst, R_X16)
      a.cset(dr, cc); write_g(ins.dst, dr)
    elsif op == :select_i64
      rc = read_g(ins.a, R_X8); rt = read_g(ins.b, R_X16); rf = read_g(ins.c, R_X17)
      dr = dst_g(ins.dst, R_X16)
      a.cmp_i(rc, 0); a.csel_x(dr, rt, rf, CC_NE); write_g(ins.dst, dr)
    elsif op == :select_f64
      rc = read_g(ins.a, R_X16); rt = read_f(ins.b, R_D6); rf = read_f(ins.c, R_D7)
      dr = dst_f(ins.dst, R_D6)
      a.cmp_i(rc, 0); a.fcsel_d(dr, rt, rf, CC_NE); write_f(ins.dst, dr)
    elsif op == :call_c_f64 || op == :call_direct_i64
      addr = wire_lookup_jit_sym(ins.sym)
      addr = cinder_resolve_c_sym(ins.sym) if addr == 0
      if addr == 0
        a.failed = true
        return false
      gi = 0; fi = 0
      if ins.args != nil
        ai = 0
        while ai < ins.args.size
          avr = ins.args[ai]
          if @wf.vreg_types[avr] == :f64
            vr = read_f(avr, R_D6)
            a.fmov_d(fi, vr) if vr != fi
            fi += 1
          else
            vr = read_g(avr, R_X16)
            a.mov_r(gi, vr) if vr != gi
            gi += 1
          ai += 1
      a.call_abs(R_X16, addr)
      if ins.dst >= 0
        if op == :call_c_f64
          write_f(ins.dst, R_D0)
        else
          write_g(ins.dst, R_X0)
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
        a.fmov_x_d(R_X16, vr)
        a.mov_imm64(R_X17, 281474976710656)
        a.add_r(R_X0, R_X16, R_X17)
      a.b(@l_epi)
    elsif op == :ret_void
      a.movz_x(R_X0, 0)
      a.b(@l_epi)
    false

  -> encode
    defs = nil
    c_f64 = nil
    run_opt = @opt_cfg.opt_level >= 1 || @opt_cfg.fast_math || @opt_cfg.explicit_passes != nil || @opt_cfg.overrides.size > 0 || @wmod != nil
    if run_opt
      wire_run_passes(@wf, @opt_cfg, @wmod)
      if @opt_cfg.opt_level >= 1 || @opt_cfg.pass_enabled?("peephole") || @opt_cfg.pass_enabled?("simd") || @opt_cfg.pass_enabled?("carry-chains")
        maps = wire_build_def_maps(@wf)
        defs = maps[0]
        @const_i64 = maps[1] if @opt_cfg.pass_enabled?("peephole")
        c_f64 = maps[2]
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
        sk = (want_loops && bi > 0) ? wire_try_emit_simd_loop(self, bi, defs, @const_i64, c_f64, @opt_cfg) : nil
        if sk != nil
          sk.keys.each ->(sid) skipped[sid] = true
        else
          ii = 0
          n = blk.insts.size
          while ii < n
            ins = blk.insts[ii]
            nxt = (ii + 1 < n && @opt_cfg.pass_enabled?("peephole")) ? blk.insts[ii + 1] : (ii + 1 < n && @opt_cfg.opt_level == 0 ? blk.insts[ii + 1] : nil)
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
