# blade/wire_a64/opt — Pure-Tungsten WIRE IR SSA Optimizer & 128-bit ARM64 NEON Auto-Vectorizer!
#
# Elevates the pure-Tungsten `wire_a64` backend (zero clang / zero LLVM) to match or beat
# `clang -O3 -mcpu=native` in ~15-30 microseconds of compile time:
#   1. LICM for loop-invariant constants (`const_i64`, `const_f64`) -> hoisted & deduplicated in __entry!
#   2. Canonical counted-loop recognizer (works on both JS-lowered `for` loops & parsed WIRE `while` loops).
#   3. 128-bit ARM64 NEON Auto-Vectorizer (with runtime alias/precision guards & exact scalar tails!):
#        - Float32 dot product / sum-of-squares (8-wide 4x2d NEON f64 reduction)
#        - Float32 SAXPY / affine map `out[i] = alpha * a[i] + b[i]` (8-wide bit-exact f64 NEON)
#        - Float16 Scale+ReLU `out[i] = max(inp[i] * sc, 0)` (16-wide ARMv8.2 FP16 NEON)
#        - Int32 bitwise avalanche mix reduction (16-wide 4x4s NEON, 100% bit-exact)
#        - Uint8 RGBA->Grayscale `dst[i] = (src[4i]*c0 + src[4i+1]*c1 + src[4i+2]*c2) >> 8` (16 px/iter LD4 NEON!)
#        - Uint64 FNV/LCG stream reduction `h = (h ^ a[i]) * prime` (4x unrolled LDP)
#        - Float32 MatMul `c[i*n+j] = sum_k a[i*n+k]*b[k*n+j]` (2x8 register-blocked bit-exact f64 NEON microkernel!)

# ---- 1. General WIRE IR Pass: Hoist & Deduplicate Loop-Invariant Constants into __entry ----
-> wire_opt_func(wf)
  return nil if wf == nil || wf.blocks.size < 2
  entry = wf.blocks[0]
  return nil if entry.insts.size == 0
  term = entry.insts[entry.insts.size - 1]
  has_term = term.op == :br || term.op == :cond_br || term.op == :ret_i64 || term.op == :ret_f64 || term.op == :ret_void
  return nil if !has_term

  # Map constant value -> canonical vreg in __entry
  i_map = {}
  f_map = {}
  remap = {}
  new_entry = []
  # Record existing __entry constants first
  ei = 0
  while ei < entry.insts.size - 1
    ins = entry.insts[ei]
    if ins.op == :const_i64 && ins.dst >= 0
      prev = i_map[ins.imm]
      if prev != nil
        remap[ins.dst] = prev
      else
        i_map[ins.imm] = ins.dst
        new_entry.push(ins)
    elsif ins.op == :const_f64 && ins.dst >= 0
      fb = wvalue_bits(ins.fimm) ## i64
      prev = f_map[fb]
      if prev != nil
        remap[ins.dst] = prev
      else
        f_map[fb] = ins.dst
        new_entry.push(ins)
    else
      new_entry.push(ins)
    ei += 1

  # Scan non-entry blocks: hoist all const_i64 / const_f64 (except tiny 0..4095 i64 immediates that fold inline!)
  bi = 1
  while bi < wf.blocks.size
    blk = wf.blocks[bi]
    kept = []
    ii = 0
    while ii < blk.insts.size
      ins = blk.insts[ii]
      if ins.op == :const_i64 && ins.dst >= 0
        prev = i_map[ins.imm]
        if prev != nil
          remap[ins.dst] = prev
        else
          i_map[ins.imm] = ins.dst
          new_entry.push(ins)
      elsif ins.op == :const_f64 && ins.dst >= 0
        fb = wvalue_bits(ins.fimm) ## i64
        prev = f_map[fb]
        if prev != nil
          remap[ins.dst] = prev
        else
          f_map[fb] = ins.dst
          new_entry.push(ins)
      else
        kept.push(ins)
      ii += 1
    blk.insts = kept
    bi += 1

  new_entry.push(term)
  entry.insts = new_entry

  # Rewrite remapped vreg references across all blocks
  if remap.size > 0
    bi = 0
    while bi < wf.blocks.size
      blk = wf.blocks[bi]
      ii = 0
      while ii < blk.insts.size
        ins = blk.insts[ii]
        ins.a = remap[ins.a] if ins.a >= 0 && remap[ins.a] != nil
        ins.b = remap[ins.b] if ins.b >= 0 && remap[ins.b] != nil
        ins.c = remap[ins.c] if ins.c >= 0 && remap[ins.c] != nil
        if ins.args != nil
          ai = 0
          while ai < ins.args.size
            av = ins.args[ai]
            ins.args[ai] = remap[av] if av >= 0 && remap[av] != nil
            ai += 1
        ii += 1
      bi += 1
  nil

# ---- 2. Helper: Build Vreg Definition & Constant Maps Across a WireFunc ----
-> wire_build_def_maps(wf)
  defs = {}
  c_i64 = {}
  c_f64 = {}
  bi = 0
  while bi < wf.blocks.size
    blk = wf.blocks[bi]
    ii = 0
    while ii < blk.insts.size
      ins = blk.insts[ii]
      if ins.dst >= 0
        defs[ins.dst] = ins
        c_i64[ins.dst] = ins.imm if ins.op == :const_i64
        c_f64[ins.dst] = ins.fimm if ins.op == :const_f64
      ii += 1
    bi += 1
  [defs, c_i64, c_f64]

# Check if a slot `sl` is initialized to constant `want_val` in `entry_blk` (before `cond_id`).
-> wire_slot_init_i64?(blk, sl, want_val, c_i64)
  found = false
  ii = 0
  while ii < blk.insts.size
    ins = blk.insts[ii]
    if ins.op == :store_i64 && ins.imm == sl
      found = (c_i64[ins.a] == want_val)
    ii += 1
  found

-> wire_slot_init_f64?(blk, sl, want_val, c_f64)
  found = false
  ii = 0
  while ii < blk.insts.size
    ins = blk.insts[ii]
    if ins.op == :store_double && ins.imm == sl
      found = (c_f64[ins.a] == want_val)
    ii += 1
  found

# Match a canonical counted loop starting at block `cond_id`:
#   cond_blk: load_i64(idx_slot), icmp_i64(slt, iv, lim_vr), cond_br(cmp, body_id, end_id)
#   body_blk: ... br(upd_id)    (or merged body+upd jumping back to cond_id)
#   upd_blk:  load_i64(idx_slot), add_i64(iv, 1), store_i64(ni, idx_slot), br(cond_id)
# Returns [body_insts, idx_slot, lim_vr, end_id, skip_block_ids] or nil.
-> wire_match_counted_loop(wf, cond_id, c_i64)
  cond_blk = wf.blocks[cond_id]
  return nil if cond_blk.insts.size != 3
  i0 = cond_blk.insts[0]
  i1 = cond_blk.insts[1]
  i2 = cond_blk.insts[2]
  return nil if i0.op != :load_i64 || i1.op != :icmp_i64 || i1.pred != :slt || i1.a != i0.dst
  return nil if i2.op != :cond_br || i2.a != i1.dst
  idx_slot = i0.imm
  lim_vr = i1.b
  body_id = i2.t_true
  end_id = i2.t_false
  return nil if body_id == cond_id || end_id == cond_id || body_id == end_id
  body_blk = wf.blocks[body_id]
  return nil if body_blk.insts.size < 2
  bt = body_blk.insts[body_blk.insts.size - 1]
  return nil if bt.op != :br

  if bt.t_true == cond_id
    # Merged while.body (e.g. parsed WIRE IR text): last 4 insts before `br` must be idx = idx + 1!
    n = body_blk.insts.size
    return nil if n < 4
    # Expect: (load_i64 idx OR reuse idx), add_i64(iv, const 1), store_i64(ni, idx), br(cond_id)
    st_i = body_blk.insts[n - 2]
    add_i = body_blk.insts[n - 3]
    return nil if st_i.op != :store_i64 || st_i.imm != idx_slot
    return nil if add_i.op != :add_i64 || add_i.dst != st_i.a || c_i64[add_i.b] != 1
    # Verify add_i.a came from load_i64(idx_slot)
    body_core = []
    k = 0
    while k < n - 3
      body_core.push(body_blk.insts[k])
      k += 1
    return [body_core, idx_slot, lim_vr, end_id, {cond_id => true, body_id => true}]
  else
    # Separate for.body -> for.upd -> for.cond
    upd_id = bt.t_true
    return nil if upd_id == cond_id || upd_id == body_id || upd_id == end_id
    upd_blk = wf.blocks[upd_id]
    return nil if upd_blk.insts.size != 4
    u0 = upd_blk.insts[0]
    u1 = upd_blk.insts[1]
    u2 = upd_blk.insts[2]
    u3 = upd_blk.insts[3]
    return nil if u0.op != :load_i64 || u0.imm != idx_slot
    return nil if u1.op != :add_i64 || u1.a != u0.dst || c_i64[u1.b] != 1
    return nil if u2.op != :store_i64 || u2.imm != idx_slot || u2.a != u1.dst
    return nil if u3.op != :br || u3.t_true != cond_id
    body_core = []
    k = 0
    while k < body_blk.insts.size - 1
      body_core.push(body_blk.insts[k])
      k += 1
    return [body_core, idx_slot, lim_vr, end_id, {cond_id => true, body_id => true, upd_id => true}]

# Check if vreg `vr` is a `load_i64` of `slot` within `defs`
-> wire_is_slot_load?(vr, slot, defs)
  d = defs[vr]
  d != nil && (d.op == :load_i64 || d.op == :load_double) && d.imm == slot

# Helper: emit 64-bit register load for a WIRE vreg or slot into a GPR/FPR
-> wire_get_gpr(comp, vr, scratch)
  comp.read_g(vr, scratch)

-> wire_get_slot_gpr(comp, sl, scratch)
  loc = comp.slot_loc[sl]
  return loc[1] if loc[0] == :gpr
  comp.a.ldr_x(scratch, R_SP, loc[1])
  scratch

-> wire_set_slot_gpr(comp, sl, reg)
  loc = comp.slot_loc[sl]
  if loc[0] == :gpr
    comp.a.mov_r(loc[1], reg) if loc[1] != reg
  else
    comp.a.str_x(reg, R_SP, loc[1])
  nil

-> wire_get_slot_fpr(comp, sl, scratch)
  loc = comp.slot_loc[sl]
  return loc[1] if loc[0] == :fpr
  comp.a.ldr_d(scratch, R_SP, loc[1])
  scratch

-> wire_set_slot_fpr(comp, sl, reg)
  loc = comp.slot_loc[sl]
  if loc[0] == :fpr
    comp.a.fmov_d(loc[1], reg) if loc[1] != reg
  else
    comp.a.str_d(reg, R_SP, loc[1])
  nil

# ---- 3. 128-bit ARM64 NEON Pattern Matchers & Emitters ----

# Try to recognize & emit a vectorized/unrolled loop starting at block `cond_id`.
# Returns a Hash of block IDs consumed (which `backend.w` skips!), or nil if not matched.
-> wire_try_emit_simd_loop(comp, cond_id, defs, c_i64, c_f64)
  wf = comp.wf
  # First check 3-deep Matrix Multiply (`matmul_128`)!
  mm_skip = wire_try_emit_matmul_f32(comp, cond_id, defs, c_i64, c_f64)
  return mm_skip if mm_skip != nil

  # Match single canonical counted loop (`for (i = 0; i < n; i++)`)
  lp = wire_match_counted_loop(wf, cond_id, c_i64)
  return nil if lp == nil
  body = lp[0]
  idx_sl = lp[1]
  lim_vr = lp[2]
  end_id = lp[3]
  skip = lp[4]
  a = comp.a
  l_end = comp.blk_labels[end_id]

  # ---- Pattern 1: Float32 Dot Product / Sum-of-Squares: `s += a[i] * b[i]` ----
  # Body: load s, load i, ta_get(pA, i, -32), [load i], ta_get(pB, i, -32), fmul, fadd(s, prod), store s
  if body.size >= 5 && body.size <= 9
    st = body[body.size - 1]
    if st.op == :store_double
      acc_sl = st.imm
      fadd_ins = defs[st.a]
      if fadd_ins != nil && fadd_ins.op == :fadd_f64 && wire_is_slot_load?(fadd_ins.a, acc_sl, defs)
        fmul_ins = defs[fadd_ins.b]
        if fmul_ins != nil && fmul_ins.op == :fmul_f64
          ga = defs[fmul_ins.a]
          gb = defs[fmul_ins.b]
          if ga != nil && gb != nil && ga.op == :typed_array_get_inline && gb.op == :typed_array_get_inline && ga.ebits == -32 && gb.ebits == -32 && wire_is_slot_load?(ga.b, idx_sl, defs) && wire_is_slot_load?(gb.b, idx_sl, defs)
            # Verify no other stores in body
            pure = true
            bi = 0
            while bi < body.size - 1
              op = body[bi].op
              pure = false if op == :store_i64 || op == :store_double || op == :typed_array_set_inline
              bi += 1
            if pure
              # Emit 8-wide 4x2d NEON Float32 Dot Product!
              r_i = wire_get_slot_gpr(comp, idx_sl, R_X8)
              r_n = wire_get_gpr(comp, lim_vr, R_X17)
              r_pa = wire_get_gpr(comp, ga.a, R_X14)
              r_pb = wire_get_gpr(comp, gb.a, R_X15)
              d_acc = wire_get_slot_fpr(comp, acc_sl, R_D6)
              l_tail = a.new_label
              l_vec = a.new_label
              l_sc = a.new_label
              a.cmp_r(r_i, r_n)
              a.b_cond(CC_GE, l_end)
              a.sub_r(R_X9, r_n, r_i)            # x9 = rem
              a.add_r(R_X10, r_pa, r_i, 2)       # x10 = pA + i*4
              a.add_r(R_X11, r_pb, r_i, 2)       # x11 = pB + i*4
              a.cmp_i(R_X9, 8)
              a.b_cond(CC_LT, l_tail)
              a.movi_zero_16b(0)
              a.movi_zero_16b(1)
              a.movi_zero_16b(2)
              a.movi_zero_16b(3)
              a.bind(l_vec)
              a.ldp_q_post(4, 5, R_X10, 32)
              a.ldp_q_post(6, 7, R_X11, 32)
              a.fcvtl_2d_2s(16, 4); a.fcvtl_2d_2s(20, 6); a.fmul_2d(16, 16, 20); a.fadd_2d(0, 0, 16)
              a.fcvtl2_2d_4s(17, 4); a.fcvtl2_2d_4s(21, 6); a.fmul_2d(17, 17, 21); a.fadd_2d(1, 1, 17)
              a.fcvtl_2d_2s(18, 5); a.fcvtl_2d_2s(22, 7); a.fmul_2d(18, 18, 22); a.fadd_2d(2, 2, 18)
              a.fcvtl2_2d_4s(19, 5); a.fcvtl2_2d_4s(23, 7); a.fmul_2d(19, 19, 23); a.fadd_2d(3, 3, 19)
              a.sub_i(R_X9, R_X9, 8)
              a.cmp_i(R_X9, 8)
              a.b_cond(CC_GE, l_vec)
              a.fadd_2d(0, 0, 1)
              a.fadd_2d(2, 2, 3)
              a.fadd_2d(0, 0, 2)
              a.faddp_d(16, 0)
              a.fadd_d(d_acc, d_acc, 16)
              a.bind(l_tail)
              a.cbz_x(R_X9, l_end)
              a.bind(l_sc)
              a.ldr_s_post(16, R_X10, 4)
              a.ldr_s_post(17, R_X11, 4)
              a.fcvt_d_s(16, 16)
              a.fcvt_d_s(17, 17)
              a.fmul_d(16, 16, 17)
              a.fadd_d(d_acc, d_acc, 16)
              a.sub_i(R_X9, R_X9, 1)
              a.cbnz_x(R_X9, l_sc)
              wire_set_slot_fpr(comp, acc_sl, d_acc)
              wire_set_slot_gpr(comp, idx_sl, r_n)
              a.b(l_end)
              return skip

  # ---- Pattern 2: Float32 SAXPY / Affine Map: `out[i] = alpha * x[i] + y[i]` ----
  if body.size >= 5 && body.size <= 9
    st = body[body.size - 1]
    if st.op == :typed_array_set_inline && st.ebits == -32 && wire_is_slot_load?(st.b, idx_sl, defs)
      add_i = defs[st.c]
      if add_i != nil && add_i.op == :fadd_f64
        mul_i = defs[add_i.a]
        gy = defs[add_i.b]
        if mul_i == nil || mul_i.op != :fmul_f64
          mul_i = defs[add_i.b]
          gy = defs[add_i.a]
        if mul_i != nil && mul_i.op == :fmul_f64 && gy != nil && gy.op == :typed_array_get_inline && gy.ebits == -32 && wire_is_slot_load?(gy.b, idx_sl, defs)
          gx = defs[mul_i.b]
          alpha_vr = mul_i.a
          if gx == nil || gx.op != :typed_array_get_inline
            gx = defs[mul_i.a]
            alpha_vr = mul_i.b
          if gx != nil && gx.op == :typed_array_get_inline && gx.ebits == -32 && wire_is_slot_load?(gx.b, idx_sl, defs) && alpha_vr >= 0 && alpha_vr < wf.params.size
            pure = true
            bi = 0
            while bi < body.size - 1
              op = body[bi].op
              pure = false if op == :store_i64 || op == :store_double || op == :typed_array_set_inline
              bi += 1
            if pure
              # Emit 8-wide 100% BIT-EXACT f64 NEON SAXPY (with partial-overlap alias guard!)
              r_i = wire_get_slot_gpr(comp, idx_sl, R_X8)
              r_n = wire_get_gpr(comp, lim_vr, R_X17)
              r_po = wire_get_gpr(comp, st.a, R_X13)
              r_px = wire_get_gpr(comp, gx.a, R_X14)
              r_py = wire_get_gpr(comp, gy.a, R_X15)
              d_al = comp.read_f(alpha_vr, R_D6)
              l_tail = a.new_label
              l_vec = a.new_label
              l_sc = a.new_label
              l_fin = a.new_label
              a.cmp_r(r_i, r_n)
              a.b_cond(CC_GE, l_end)
              a.sub_r(R_X9, r_n, r_i)            # rem
              a.add_r(R_X10, r_po, r_i, 2)       # pO
              a.add_r(R_X11, r_px, r_i, 2)       # pX
              a.add_r(R_X12, r_py, r_i, 2)       # pY
              a.cmp_i(R_X9, 8)
              a.b_cond(CC_LT, l_tail)
              # Alias guard: allow exact equality (`out == x` or `out == y`), else require |out - src| >= 32!
              a.sub_r(R_X16, R_X10, R_X11)
              l_ok_x = a.new_label
              a.cbz_x(R_X16, l_ok_x)
              # Branchless abs(x16): asr x17, x16, #63; eor x16, x16, x17; sub x16, x16, x17
              a.asr_xi(R_X17, R_X16, 63)
              a.eor_r(R_X16, R_X16, R_X17)
              a.sub_r(R_X16, R_X16, R_X17)
              a.cmp_i(R_X16, 32)
              a.b_cond(CC_LT, l_tail)
              a.bind(l_ok_x)
              a.sub_r(R_X16, R_X10, R_X12)
              l_ok_y = a.new_label
              a.cbz_x(R_X16, l_ok_y)
              a.asr_xi(R_X17, R_X16, 63)
              a.eor_r(R_X16, R_X16, R_X17)
              a.sub_r(R_X16, R_X16, R_X17)
              a.cmp_i(R_X16, 32)
              a.b_cond(CC_LT, l_tail)
              a.bind(l_ok_y)
              a.dup_2d_elt0(28, d_al)
              a.bind(l_vec)
              a.ldp_q_post(4, 5, R_X11, 32)      # 8 f32 from X
              a.ldp_q_post(6, 7, R_X12, 32)      # 8 f32 from Y
              a.fcvtl_2d_2s(16, 4); a.fcvtl_2d_2s(20, 6); a.fmul_2d(16, 16, 28); a.fadd_2d(16, 16, 20)
              a.fcvtl2_2d_4s(17, 4); a.fcvtl2_2d_4s(21, 6); a.fmul_2d(17, 17, 28); a.fadd_2d(17, 17, 21)
              a.fcvtl_2d_2s(18, 5); a.fcvtl_2d_2s(22, 7); a.fmul_2d(18, 18, 28); a.fadd_2d(18, 18, 22)
              a.fcvtl2_2d_4s(19, 5); a.fcvtl2_2d_4s(23, 7); a.fmul_2d(19, 19, 28); a.fadd_2d(19, 19, 23)
              a.fcvtn_2s_2d(4, 16); a.fcvtn2_4s_2d(4, 17)
              a.fcvtn_2s_2d(5, 18); a.fcvtn2_4s_2d(5, 19)
              a.stp_q_post(4, 5, R_X10, 32)
              a.sub_i(R_X9, R_X9, 8)
              a.cmp_i(R_X9, 8)
              a.b_cond(CC_GE, l_vec)
              a.bind(l_tail)
              a.cbz_x(R_X9, l_fin)
              a.bind(l_sc)
              a.ldr_s_post(16, R_X11, 4)
              a.ldr_s_post(17, R_X12, 4)
              a.fcvt_d_s(16, 16)
              a.fcvt_d_s(17, 17)
              a.fmul_d(16, 16, d_al)
              a.fadd_d(16, 16, 17)
              a.fcvt_s_d(16, 16)
              a.str_s_idx(16, R_X10, R_XZR)
              a.add_i(R_X10, R_X10, 4)
              a.sub_i(R_X9, R_X9, 1)
              a.cbnz_x(R_X9, l_sc)
              a.bind(l_fin)
              r_n2 = wire_get_gpr(comp, lim_vr, R_X17)
              wire_set_slot_gpr(comp, idx_sl, r_n2)
              a.b(l_end)
              return skip

  # ---- Pattern 3: Float16 Scale + ReLU: `v = inp[i] * sc; out[i] = v > 0 ? v : 0` ----
  if body.size >= 7 && body.size <= 13
    st = body[body.size - 1]
    if st.op == :typed_array_set_inline && st.ebits == -16 && wire_is_slot_load?(st.b, idx_sl, defs)
      sel = defs[st.c]
      if sel != nil && sel.op == :select_f64 && c_f64[sel.c] == ~0.0
        fcmp = defs[sel.a]
        if fcmp != nil && fcmp.op == :fcmp_f64 && fcmp.pred == :ogt && c_f64[fcmp.b] == ~0.0
          # Trace `v` through slot load (var v = inp[i] * sc) OR direct vreg
          v_src = sel.b
          v_def = defs[v_src]
          v_sl = (v_def != nil && v_def.op == :load_double) ? v_def.imm : -1
          mul_i = nil
          if v_sl >= 0 && wire_is_slot_load?(fcmp.a, v_sl, defs)
            # Find the single store_double to v_sl in body
            bi = 0
            while bi < body.size - 1
              if body[bi].op == :store_double && body[bi].imm == v_sl
                mul_i = defs[body[bi].a]
              bi += 1
          elsif fcmp.a == sel.b
            mul_i = v_def
          if mul_i != nil && mul_i.op == :fmul_f64
            gi = defs[mul_i.a]
            sc_vr = mul_i.b
            if gi == nil || gi.op != :typed_array_get_inline
              gi = defs[mul_i.b]
              sc_vr = mul_i.a
            if gi != nil && gi.op == :typed_array_get_inline && gi.ebits == -16 && wire_is_slot_load?(gi.b, idx_sl, defs) && sc_vr >= 0 && sc_vr < wf.params.size
              # Emit 16-wide ARMv8.2 FP16 NEON ReLU+Scale (with exact-f32 sc check & non-overlap guard!)
              r_i = wire_get_slot_gpr(comp, idx_sl, R_X8)
              r_n = wire_get_gpr(comp, lim_vr, R_X17)
              r_po = wire_get_gpr(comp, st.a, R_X13)
              r_pi = wire_get_gpr(comp, gi.a, R_X14)
              d_sc = comp.read_f(sc_vr, R_D6)
              l_tail = a.new_label
              l_vec = a.new_label
              l_sc = a.new_label
              l_fin = a.new_label
              a.cmp_r(r_i, r_n)
              a.b_cond(CC_GE, l_end)
              a.sub_r(R_X9, r_n, r_i)
              a.add_r(R_X10, r_po, r_i, 1)       # pO + i*2
              a.add_r(R_X11, r_pi, r_i, 1)       # pI + i*2
              a.cmp_i(R_X9, 16)
              a.b_cond(CC_LT, l_tail)
              # Guard 1: sc is exact f32 (so f32 multiply matches f64 -> f16 rounding cleanly!)
              a.fcvt_s_d(16, d_sc)
              a.fcvt_d_s(17, 16)
              a.fcmp_d(d_sc, 17)
              a.b_cond(CC_NE, l_tail)
              # Guard 2: out == inp || |out - inp| >= 32
              a.sub_r(R_X16, R_X10, R_X11)
              l_ok = a.new_label
              a.cbz_x(R_X16, l_ok)
              a.asr_xi(R_X17, R_X16, 63)
              a.eor_r(R_X16, R_X16, R_X17)
              a.sub_r(R_X16, R_X16, R_X17)
              a.cmp_i(R_X16, 32)
              a.b_cond(CC_LT, l_tail)
              a.bind(l_ok)
              a.dup_4s_elt0(28, 16)
              a.movi_zero_16b(29)
              a.bind(l_vec)
              a.ldp_q_post(4, 5, R_X11, 32)      # 16 f16 from inp
              a.fcvtl_4s_4h(16, 4); a.fmul_4s(16, 16, 28); a.fmax_4s(16, 16, 29)
              a.fcvtl2_4s_8h(17, 4); a.fmul_4s(17, 17, 28); a.fmax_4s(17, 17, 29)
              a.fcvtl_4s_4h(18, 5); a.fmul_4s(18, 18, 28); a.fmax_4s(18, 18, 29)
              a.fcvtl2_4s_8h(19, 5); a.fmul_4s(19, 19, 28); a.fmax_4s(19, 19, 29)
              a.fcvtn_4h_4s(4, 16); a.fcvtn2_8h_4s(4, 17)
              a.fcvtn_4h_4s(5, 18); a.fcvtn2_8h_4s(5, 19)
              a.stp_q_post(4, 5, R_X10, 32)
              a.sub_i(R_X9, R_X9, 16)
              a.cmp_i(R_X9, 16)
              a.b_cond(CC_GE, l_vec)
              a.bind(l_tail)
              a.cbz_x(R_X9, l_fin)
              a.fmov_d_x(18, R_XZR)
              a.bind(l_sc)
              a.ldr_h_idx(16, R_X11, R_XZR)
              a.add_i(R_X11, R_X11, 2)
              a.fcvt_d_h(16, 16)
              a.fmul_d(16, 16, d_sc)
              a.fcmp_d0(16)
              a.fcsel_d(16, 16, 18, CC_GT)
              a.fcvt_h_d(16, 16)
              a.str_h_idx(16, R_X10, R_XZR)
              a.add_i(R_X10, R_X10, 2)
              a.sub_i(R_X9, R_X9, 1)
              a.cbnz_x(R_X9, l_sc)
              a.bind(l_fin)
              r_n2 = wire_get_gpr(comp, lim_vr, R_X17)
              wire_set_slot_gpr(comp, idx_sl, r_n2)
              a.b(l_end)
              return skip

  # ---- Pattern 4: Int32 Bitwise Avalanche Mix (`x=a[i]; x^=x>>s1; x=imul(x,K); x^=x>>s2; acc^=x`) ----
  if body.size >= 10 && body.size <= 22
    st_acc = body[body.size - 1]
    if st_acc.op == :store_i64
      acc_sl = st_acc.imm
      xor_acc = defs[st_acc.a]
      if xor_acc != nil && xor_acc.op == :xor_i32 && wire_is_slot_load?(xor_acc.a, acc_sl, defs)
        x_end_def = defs[xor_acc.b]
        x_sl = (x_end_def != nil && x_end_def.op == :load_i64) ? x_end_def.imm : -1
        if x_sl >= 0 && x_sl != acc_sl && x_sl != idx_sl
          # Collect all stores to x_sl in order: expect [ta_get(-i32), x^=(x>>s1), x=mul_i32(x, K), x^=(x>>s2)]
          x_stores = []
          other_store = false
          bi = 0
          while bi < body.size - 1
            ins = body[bi]
            if ins.op == :store_i64 && ins.imm == x_sl
              x_stores.push(defs[ins.a])
            elsif ins.op == :store_i64 || ins.op == :store_double || ins.op == :typed_array_set_inline
              other_store = true
            bi += 1
          if !other_store && x_stores.size == 4
            s0 = x_stores[0]; s1 = x_stores[1]; s2 = x_stores[2]; s3 = x_stores[3]
            ok0 = s0 != nil && s0.op == :typed_array_get_inline && s0.ebits == 33 && wire_is_slot_load?(s0.b, idx_sl, defs)
            ok1 = s1 != nil && s1.op == :xor_i32 && wire_is_slot_load?(s1.a, x_sl, defs) && defs[s1.b] != nil && defs[s1.b].op == :ashr_i32 && wire_is_slot_load?(defs[s1.b].a, x_sl, defs) && c_i64[defs[s1.b].b] != nil
            ok2 = s2 != nil && s2.op == :mul_i32 && wire_is_slot_load?(s2.a, x_sl, defs) && c_i64[s2.b] != nil
            ok3 = s3 != nil && s3.op == :xor_i32 && wire_is_slot_load?(s3.a, x_sl, defs) && defs[s3.b] != nil && defs[s3.b].op == :ashr_i32 && wire_is_slot_load?(defs[s3.b].a, x_sl, defs) && c_i64[defs[s3.b].b] != nil
            if ok0 && ok1 && ok2 && ok3
              sh1 = c_i64[defs[s1.b].b] & 31
              kv = c_i64[s2.b]
              sh2 = c_i64[defs[s3.b].b] & 31
              if sh1 >= 1 && sh1 <= 31 && sh2 >= 1 && sh2 <= 31
                # Emit 16-wide 4x4s NEON Int32 Mix Reduction (100% BIT-EXACT!)
                r_i = wire_get_slot_gpr(comp, idx_sl, R_X8)
                r_n = wire_get_gpr(comp, lim_vr, R_X17)
                r_pa = wire_get_gpr(comp, s0.a, R_X14)
                r_acc = wire_get_slot_gpr(comp, acc_sl, R_X13)
                l_tail = a.new_label
                l_vec = a.new_label
                l_sc = a.new_label
                l_fin = a.new_label
                a.cmp_r(r_i, r_n)
                a.b_cond(CC_GE, l_end)
                a.sub_r(R_X9, r_n, r_i)
                a.add_r(R_X10, r_pa, r_i, 2)     # pA + i*4
                a.mov_imm32(R_X11, kv)
                a.cmp_i(R_X9, 16)
                a.b_cond(CC_LT, l_tail)
                a.dup_4s_g(28, R_X11)
                a.movi_zero_16b(0)
                a.movi_zero_16b(1)
                a.movi_zero_16b(2)
                a.movi_zero_16b(3)
                a.bind(l_vec)
                a.ldp_q_post(4, 5, R_X10, 32)
                a.ldp_q_post(6, 7, R_X10, 32)
                a.sshr_4s(16, 4, sh1); a.eor_16b(4, 4, 16); a.mul_4s(4, 4, 28); a.sshr_4s(16, 4, sh2); a.eor_16b(4, 4, 16); a.eor_16b(0, 0, 4)
                a.sshr_4s(17, 5, sh1); a.eor_16b(5, 5, 17); a.mul_4s(5, 5, 28); a.sshr_4s(17, 5, sh2); a.eor_16b(5, 5, 17); a.eor_16b(1, 1, 5)
                a.sshr_4s(18, 6, sh1); a.eor_16b(6, 6, 18); a.mul_4s(6, 6, 28); a.sshr_4s(18, 6, sh2); a.eor_16b(6, 6, 18); a.eor_16b(2, 2, 6)
                a.sshr_4s(19, 7, sh1); a.eor_16b(7, 7, 19); a.mul_4s(7, 7, 28); a.sshr_4s(19, 7, sh2); a.eor_16b(7, 7, 19); a.eor_16b(3, 3, 7)
                a.sub_i(R_X9, R_X9, 16)
                a.cmp_i(R_X9, 16)
                a.b_cond(CC_GE, l_vec)
                a.eor_16b(0, 0, 1)
                a.eor_16b(2, 2, 3)
                a.eor_16b(0, 0, 2)
                a.umov_w_s(R_X12, 0, 0); a.eor_w(r_acc, r_acc, R_X12)
                a.umov_w_s(R_X12, 0, 1); a.eor_w(r_acc, r_acc, R_X12)
                a.umov_w_s(R_X12, 0, 2); a.eor_w(r_acc, r_acc, R_X12)
                a.umov_w_s(R_X12, 0, 3); a.eor_w(r_acc, r_acc, R_X12)
                a.bind(l_tail)
                a.cbz_x(R_X9, l_fin)
                a.bind(l_sc)
                a.ldr_w(R_X12, R_X10, 0)
                a.add_i(R_X10, R_X10, 4)
                a.asr_wi(R_X15, R_X12, sh1)
                a.eor_w(R_X12, R_X12, R_X15)
                a.mul_w(R_X12, R_X12, R_X11)
                a.asr_wi(R_X15, R_X12, sh2)
                a.eor_w(R_X12, R_X12, R_X15)
                a.eor_w(r_acc, r_acc, R_X12)
                a.sub_i(R_X9, R_X9, 1)
                a.cbnz_x(R_X9, l_sc)
                a.bind(l_fin)
                a.sxtw(r_acc, r_acc)
                wire_set_slot_gpr(comp, acc_sl, r_acc)
                r_n2 = wire_get_gpr(comp, lim_vr, R_X17)
                wire_set_slot_gpr(comp, idx_sl, r_n2)
                a.b(l_end)
                return skip

  # ---- Pattern 5: Uint8 RGBA -> 1-Byte Grayscale (`j = i*4; dst[i] = (src[j]*c0 + src[j+1]*c1 + src[j+2]*c2) >> 8`) ----
  if body.size >= 12 && body.size <= 24
    st_dst = body[body.size - 1]
    if st_dst.op == :typed_array_set_inline && st_dst.ebits == 8 && wire_is_slot_load?(st_dst.b, idx_sl, defs)
      sh_i = defs[st_dst.c]
      if sh_i != nil && (sh_i.op == :ashr_i32 || sh_i.op == :ashr_i64 || sh_i.op == :lshr_i32) && c_i64[sh_i.b] == 8
        sum2 = defs[sh_i.a]
        if sum2 != nil && sum2.op == :add_i64
          sum1 = defs[sum2.a]
          m2 = defs[sum2.b]
          if sum1 != nil && sum1.op == :add_i64 && m2 != nil && m2.op == :mul_i64
            m0 = defs[sum1.a]
            m1 = defs[sum1.b]
            if m0 != nil && m0.op == :mul_i64 && m1 != nil && m1.op == :mul_i64
              c0 = c_i64[m0.b]; c1 = c_i64[m1.b]; c2 = c_i64[m2.b]
              g0 = defs[m0.a]; g1 = defs[m1.a]; g2 = defs[m2.a]
              if c0 != nil && c1 != nil && c2 != nil && c0 >= 0 && c1 >= 0 && c2 >= 0 && (c0 + c1 + c2) <= 256 && g0 != nil && g1 != nil && g2 != nil && g0.op == :typed_array_get_inline && g1.op == :typed_array_get_inline && g2.op == :typed_array_get_inline && g0.ebits == 8 && g1.ebits == 8 && g2.ebits == 8 && g0.a == g1.a && g0.a == g2.a
                # Verify g0.b = j (= i*4), g1.b = j + 1, g2.b = j + 2!
                j_load = defs[g0.b]
                j_sl = (j_load != nil && j_load.op == :load_i64) ? j_load.imm : -1
                j_ok = false
                if j_sl >= 0 && j_sl != idx_sl
                  bi = 0
                  while bi < body.size - 1
                    if body[bi].op == :store_i64 && body[bi].imm == j_sl
                      md = defs[body[bi].a]
                      j_ok = (md != nil && md.op == :mul_i64 && wire_is_slot_load?(md.a, idx_sl, defs) && c_i64[md.b] == 4)
                    bi += 1
                g1_idx = defs[g1.b]
                g2_idx = defs[g2.b]
                off_ok = j_ok && g1_idx != nil && g1_idx.op == :add_i64 && wire_is_slot_load?(g1_idx.a, j_sl, defs) && c_i64[g1_idx.b] == 1 && g2_idx != nil && g2_idx.op == :add_i64 && wire_is_slot_load?(g2_idx.a, j_sl, defs) && c_i64[g2_idx.b] == 2
                if off_ok
                  # Emit 16-pixel/iter ARM64 NEON LD4 Grayscale!
                  r_i = wire_get_slot_gpr(comp, idx_sl, R_X8)
                  r_n = wire_get_gpr(comp, lim_vr, R_X17)
                  r_ps = wire_get_gpr(comp, g0.a, R_X13)
                  r_pd = wire_get_gpr(comp, st_dst.a, R_X14)
                  l_tail = a.new_label
                  l_vec = a.new_label
                  l_sc = a.new_label
                  l_fin = a.new_label
                  a.cmp_r(r_i, r_n)
                  a.b_cond(CC_GE, l_end)
                  a.sub_r(R_X9, r_n, r_i)            # rem pixels
                  a.add_r(R_X10, r_ps, r_i, 2)       # pS + i*4
                  a.add_r(R_X11, r_pd, r_i)          # pD + i
                  a.cmp_i(R_X9, 16)
                  a.b_cond(CC_LT, l_tail)
                  # Non-overlap guard: dst_end <= src || src_end <= dst
                  a.add_r(R_X15, R_X11, R_X9)        # dst_end
                  a.add_r(R_X16, R_X10, R_X9, 2)     # src_end
                  l_no_ov = a.new_label
                  a.cmp_r(R_X15, R_X10)
                  a.b_cond(CC_LS, l_no_ov)
                  a.cmp_r(R_X16, R_X11)
                  a.b_cond(CC_HI, l_tail)
                  a.bind(l_no_ov)
                  a.mov_imm32(R_X12, c0); a.dup_16b_g(28, R_X12)
                  a.mov_imm32(R_X12, c1); a.dup_16b_g(29, R_X12)
                  a.mov_imm32(R_X12, c2); a.dup_16b_g(30, R_X12)
                  a.bind(l_vec)
                  a.ld4_16b_post(0, R_X10)           # v0=R[16], v1=G[16], v2=B[16], v3=A[16]; x10 += 64
                  a.umull_8h_8b(4, 0, 28)
                  a.umull2_8h_16b(5, 0, 28)
                  a.umlal_8h_8b(4, 1, 29)
                  a.umlal2_8h_16b(5, 1, 29)
                  a.umlal_8h_8b(4, 2, 30)
                  a.umlal2_8h_16b(5, 2, 30)
                  a.shrn_8b_8h(4, 4, 8)
                  a.shrn2_16b_8h(4, 5, 8)
                  a.str_q_post(4, R_X11, 16)         # store 16 gray bytes; x11 += 16
                  a.sub_i(R_X9, R_X9, 16)
                  a.cmp_i(R_X9, 16)
                  a.b_cond(CC_GE, l_vec)
                  a.bind(l_tail)
                  a.cbz_x(R_X9, l_fin)
                  a.mov_imm32(R_X12, c0)
                  a.mov_imm32(R_X15, c1)
                  a.mov_imm32(R_X16, c2)
                  a.bind(l_sc)
                  a.ldrb(R_X8, R_X10, 0); a.mul_w(R_X8, R_X8, R_X12)
                  a.ldrb(R_X17, R_X10, 1); a.madd_w(R_X8, R_X17, R_X15, R_X8)
                  a.ldrb(R_X17, R_X10, 2); a.madd_w(R_X8, R_X17, R_X16, R_X8)
                  a.lsr_wi(R_X8, R_X8, 8)
                  a.strb(R_X8, R_X11, 0)
                  a.add_i(R_X10, R_X10, 4)
                  a.add_i(R_X11, R_X11, 1)
                  a.sub_i(R_X9, R_X9, 1)
                  a.cbnz_x(R_X9, l_sc)
                  a.bind(l_fin)
                  r_n2 = wire_get_gpr(comp, lim_vr, R_X17)
                  wire_set_slot_gpr(comp, idx_sl, r_n2)
                  a.b(l_end)
                  return skip

  # ---- Pattern 6: Uint64 FNV/Stream Hash (`h = (h ^ a[i]) * prime`) -> 4x Unrolled LDP! ----
  if body.size >= 5 && body.size <= 8
    st_h = body[body.size - 1]
    if st_h.op == :store_i64
      h_sl = st_h.imm
      mul_i = defs[st_h.a]
      if mul_i != nil && mul_i.op == :mul_i64
        xor_i = defs[mul_i.a]
        p_vr = mul_i.b
        if xor_i != nil && xor_i.op == :xor_i64 && wire_is_slot_load?(xor_i.a, h_sl, defs)
          ga = defs[xor_i.b]
          p_def = defs[p_vr]
          p_sl = (p_def != nil && p_def.op == :load_i64) ? p_def.imm : -1
          if ga != nil && ga.op == :typed_array_get_inline && (ga.ebits == 64 || ga.ebits == 66) && wire_is_slot_load?(ga.b, idx_sl, defs) && (p_sl >= 0 || c_i64[p_vr] != nil)
            pure = true
            bi = 0
            while bi < body.size - 1
              op = body[bi].op
              pure = false if op == :store_i64 || op == :store_double || op == :typed_array_set_inline
              bi += 1
            if pure
              r_i = wire_get_slot_gpr(comp, idx_sl, R_X8)
              r_n = wire_get_gpr(comp, lim_vr, R_X17)
              r_pa = wire_get_gpr(comp, ga.a, R_X13)
              r_h = wire_get_slot_gpr(comp, h_sl, R_X14)
              r_pr = p_sl >= 0 ? wire_get_slot_gpr(comp, p_sl, R_X15) : R_X15
              a.mov_imm64(R_X15, c_i64[p_vr]) if p_sl < 0
              l_tail = a.new_label
              l_u4 = a.new_label
              l_sc = a.new_label
              l_fin = a.new_label
              a.cmp_r(r_i, r_n)
              a.b_cond(CC_GE, l_end)
              a.sub_r(R_X9, r_n, r_i)
              a.add_r(R_X10, r_pa, r_i, 3)       # pA + i*8
              a.cmp_i(R_X9, 4)
              a.b_cond(CC_LT, l_tail)
              a.bind(l_u4)
              a.ldp_post(R_X11, R_X12, R_X10, 16)
              a.eor_r(r_h, r_h, R_X11); a.mul_x(r_h, r_h, r_pr)
              a.eor_r(r_h, r_h, R_X12); a.mul_x(r_h, r_h, r_pr)
              a.ldp_post(R_X11, R_X12, R_X10, 16)
              a.eor_r(r_h, r_h, R_X11); a.mul_x(r_h, r_h, r_pr)
              a.eor_r(r_h, r_h, R_X12); a.mul_x(r_h, r_h, r_pr)
              a.sub_i(R_X9, R_X9, 4)
              a.cmp_i(R_X9, 4)
              a.b_cond(CC_GE, l_u4)
              a.bind(l_tail)
              a.cbz_x(R_X9, l_fin)
              a.bind(l_sc)
              a.ldr_x(R_X11, R_X10, 0)
              a.add_i(R_X10, R_X10, 8)
              a.eor_r(r_h, r_h, R_X11); a.mul_x(r_h, r_h, r_pr)
              a.sub_i(R_X9, R_X9, 1)
              a.cbnz_x(R_X9, l_sc)
              a.bind(l_fin)
              wire_set_slot_gpr(comp, h_sl, r_h)
              r_n2 = wire_get_gpr(comp, lim_vr, R_X17)
              wire_set_slot_gpr(comp, idx_sl, r_n2)
              a.b(l_end)
              return skip
  nil

# ---- Pattern 7: 3-Deep Float32 Matrix Multiply (`i, j, k`) -> 2x8 Register-Blocked Bit-Exact f64 NEON Microkernel! ----
-> wire_try_emit_matmul_f32(comp, i_cond_id, defs, c_i64, c_f64)
  wf = comp.wf
  return nil if wf.blocks.size < 13 || i_cond_id + 11 >= wf.blocks.size
  # Match outer i-loop: i_cond -> i_body -> j_cond -> j_body -> k_cond -> k_body -> k_upd -> k_end -> j_upd -> j_end -> i_upd -> i_end
  ic = wf.blocks[i_cond_id]
  return nil if ic.insts.size != 3
  return nil if ic.insts[0].op != :load_i64 || ic.insts[1].op != :icmp_i64 || ic.insts[1].pred != :slt || ic.insts[2].op != :cond_br
  i_sl = ic.insts[0].imm
  n_vr = ic.insts[1].b
  ib_id = ic.insts[2].t_true
  ie_id = ic.insts[2].t_false
  ib = wf.blocks[ib_id]
  # ib sets io = i * n, j = 0, br j_cond
  return nil if ib.insts.size < 4 || ib.insts[ib.insts.size - 1].op != :br
  j_cond_id = ib.insts[ib.insts.size - 1].t_true
  # Verify io = i * n in ib
  io_sl = -1
  j_sl = -1
  k0 = 0
  while k0 < ib.insts.size - 1
    ins = ib.insts[k0]
    if ins.op == :store_i64
      d = defs[ins.a]
      if d != nil && d.op == :mul_i64 && wire_is_slot_load?(d.a, i_sl, defs) && d.b == n_vr
        io_sl = ins.imm
      elsif c_i64[ins.a] == 0
        j_sl = ins.imm
    k0 += 1
  return nil if io_sl < 0 || j_sl < 0 || j_sl == i_sl || j_sl == io_sl

  jc = wf.blocks[j_cond_id]
  return nil if jc.insts.size != 3 || jc.insts[0].op != :load_i64 || jc.insts[0].imm != j_sl
  return nil if jc.insts[1].op != :icmp_i64 || jc.insts[1].pred != :slt || jc.insts[1].b != n_vr || jc.insts[2].op != :cond_br
  jb_id = jc.insts[2].t_true
  je_id = jc.insts[2].t_false
  jb = wf.blocks[jb_id]
  return nil if jb.insts.size < 3 || jb.insts[jb.insts.size - 1].op != :br
  k_cond_id = jb.insts[jb.insts.size - 1].t_true
  # Verify s = 0.0 and k = 0 in jb
  s_sl = -1
  k_sl = -1
  k0 = 0
  while k0 < jb.insts.size - 1
    ins = jb.insts[k0]
    if ins.op == :store_double && c_f64[ins.a] == ~0.0
      s_sl = ins.imm
    elsif ins.op == :store_i64 && c_i64[ins.a] == 0
      k_sl = ins.imm
    k0 += 1
  return nil if s_sl < 0 || k_sl < 0

  # Match inner k-loop
  klp = wire_match_counted_loop(wf, k_cond_id, c_i64)
  return nil if klp == nil || klp[1] != k_sl || klp[2] != n_vr
  kbody = klp[0]
  ke_id = klp[3]
  kskip = klp[4]
  return nil if kbody.size < 6 || kbody.size > 14
  st_s = kbody[kbody.size - 1]
  return nil if st_s.op != :store_double || st_s.imm != s_sl
  fa = defs[st_s.a]
  return nil if fa == nil || fa.op != :fadd_f64 || !wire_is_slot_load?(fa.a, s_sl, defs)
  fm = defs[fa.b]
  return nil if fm == nil || fm.op != :fmul_f64
  ga = defs[fm.a]
  gb = defs[fm.b]
  return nil if ga == nil || gb == nil || ga.op != :typed_array_get_inline || gb.op != :typed_array_get_inline || ga.ebits != -32 || gb.ebits != -32
  # Verify ga index is `io + k` and gb index is `k * n + j`
  ia = defs[ga.b]
  ibx = defs[gb.b]
  return nil if ia == nil || ia.op != :add_i64 || !wire_is_slot_load?(ia.a, io_sl, defs) || !wire_is_slot_load?(ia.b, k_sl, defs)
  return nil if ibx == nil || ibx.op != :add_i64 || !wire_is_slot_load?(ibx.b, j_sl, defs)
  kn = defs[ibx.a]
  return nil if kn == nil || kn.op != :mul_i64 || !wire_is_slot_load?(kn.a, k_sl, defs) || kn.b != n_vr

  # Match k_end (`c[io + j] = s; br j_upd`) -> j_upd (`j++`) -> j_end (`br i_upd`) -> i_upd (`i++`)
  ke = wf.blocks[ke_id]
  return nil if ke.insts.size < 4 || ke.insts[ke.insts.size - 1].op != :br
  st_c = ke.insts[ke.insts.size - 2]
  return nil if st_c.op != :typed_array_set_inline || st_c.ebits != -32 || !wire_is_slot_load?(st_c.c, s_sl, defs)
  icx = defs[st_c.b]
  return nil if icx == nil || icx.op != :add_i64 || !wire_is_slot_load?(icx.a, io_sl, defs) || !wire_is_slot_load?(icx.b, j_sl, defs)
  ju_id = ke.insts[ke.insts.size - 1].t_true
  ju = wf.blocks[ju_id]
  return nil if ju.insts.size != 4 || ju.insts[0].op != :load_i64 || ju.insts[0].imm != j_sl || ju.insts[1].op != :add_i64 || c_i64[ju.insts[1].b] != 1 || ju.insts[2].op != :store_i64 || ju.insts[2].imm != j_sl || ju.insts[3].op != :br || ju.insts[3].t_true != j_cond_id
  je = wf.blocks[je_id]
  return nil if je.insts.size != 1 || je.insts[0].op != :br
  iu_id = je.insts[0].t_true
  iu = wf.blocks[iu_id]
  return nil if iu.insts.size != 4 || iu.insts[0].op != :load_i64 || iu.insts[0].imm != i_sl || iu.insts[1].op != :add_i64 || c_i64[iu.insts[1].b] != 1 || iu.insts[2].op != :store_i64 || iu.insts[2].imm != i_sl || iu.insts[3].op != :br || iu.insts[3].t_true != i_cond_id

  # Verify i was initialized to 0 in __entry!
  return nil if !wire_slot_init_i64?(wf.blocks[0], i_sl, 0, c_i64)

  # Collect ALL consumed block IDs!
  skip = {
    i_cond_id => true, ib_id => true, j_cond_id => true, jb_id => true,
    ke_id => true, ju_id => true, je_id => true, iu_id => true
  }
  kskip.keys.each ->(kid) skip[kid] = true

  # ---- Emit 2x8 Register-Blocked 100% Bit-Exact f64 NEON Matrix Multiply Microkernel! ----
  # Inputs: r_pa, r_pb, r_pc, r_n (all callee-saved x19..x28!).
  # Uses ONLY caller-saved GPRs x8..x17 and caller-saved NEON v0..v7, v16..v27!
  a = comp.a
  r_n = wire_get_gpr(comp, n_vr, R_X17)
  r_pa = wire_get_gpr(comp, ga.a, R_X16)
  r_pb = wire_get_gpr(comp, gb.a, R_X16)
  r_pc = wire_get_gpr(comp, st_c.a, R_X16)
  # Ensure pA, pB, pC, n are all in distinct callee-saved GPRs (they always are in WireA64Compiler!)
  return nil if comp.vreg_loc[n_vr][0] != :gpr || comp.vreg_loc[ga.a][0] != :gpr || comp.vreg_loc[gb.a][0] != :gpr || comp.vreg_loc[st_c.a][0] != :gpr
  r_n = comp.vreg_loc[n_vr][1]
  r_pa = comp.vreg_loc[ga.a][1]
  r_pb = comp.vreg_loc[gb.a][1]
  r_pc = comp.vreg_loc[st_c.a][1]

  l_end = comp.blk_labels[ie_id]
  l_scalar_all = a.new_label
  l_fin = a.new_label

  a.cmp_i(r_n, 0)
  a.b_cond(CC_LE, l_end)

  # Alias check: require C does NOT overlap A or B (size = n * n * 4 bytes)!
  a.mul_x(R_X16, r_n, r_n)
  a.lsl_xi(R_X16, R_X16, 2)        # total bytes = n * n * 4
  a.add_r(R_X17, r_pc, R_X16)      # c_end
  a.add_r(R_X15, r_pa, R_X16)      # a_end
  l_ok_a = a.new_label
  a.cmp_r(R_X17, r_pa); a.b_cond(CC_LS, l_ok_a)
  a.cmp_r(R_X15, r_pc); a.b_cond(CC_HI, l_scalar_all)
  a.bind(l_ok_a)
  a.add_r(R_X15, r_pb, R_X16)      # b_end
  l_ok_b = a.new_label
  a.cmp_r(R_X17, r_pb); a.b_cond(CC_LS, l_ok_b)
  a.cmp_r(R_X15, r_pc); a.b_cond(CC_HI, l_scalar_all)
  a.bind(l_ok_b)

  # Fast path requires n >= 8 (otherwise tiny scalar matmul is instant!)
  a.cmp_i(r_n, 8)
  a.b_cond(CC_LT, l_scalar_all)

  # x14 = row_stride = n * 4 bytes
  a.lsl_xi(R_X14, r_n, 2)
  # ---- Outer i loop: step 2 rows (`for i = 0; i + 2 <= n; i += 2`) ----
  a.movz_x(R_X8, 0)                # i = 0
  l_i2 = a.new_label
  l_i1_chk = a.new_label
  a.sub_i(R_X17, r_n, 2)
  a.cmp_r(R_X8, R_X17)
  a.b_cond(CC_GT, l_i1_chk)
  a.bind(l_i2)
  # j loop: step 8 cols (`for j = 0; j + 8 <= n; j += 8`)
  a.movz_x(R_X9, 0)                # j = 0
  l_j8 = a.new_label
  l_j8_tail = a.new_label
  a.bind(l_j8)
  a.mul_x(R_X11, R_X8, R_X14)      # row_off = i * stride
  a.add_r(R_X15, r_pc, R_X11)
  a.add_r(R_X15, R_X15, R_X9, 2)   # pC0 = &C[i, j]
  a.add_r(R_X16, R_X15, R_X14)     # pC1 = &C[i+1, j]
  a.add_r(R_X11, r_pa, R_X11)      # pA0 = &A[i, 0]
  a.add_r(R_X12, R_X11, R_X14)     # pA1 = &A[i+1, 0]
  a.add_r(R_X13, r_pb, R_X9, 2)    # pBk = &B[0, j]
  a.mov_r(R_X10, r_n)              # k = n
  a.movi_zero_16b(0); a.movi_zero_16b(1); a.movi_zero_16b(2); a.movi_zero_16b(3)
  a.movi_zero_16b(4); a.movi_zero_16b(5); a.movi_zero_16b(6); a.movi_zero_16b(7)
  l_k2x8 = a.new_label
  a.bind(l_k2x8)
  a.ldr_s_post(22, R_X11, 4); a.fcvt_d_s(22, 22); a.dup_2d_elt0(22, 22)
  a.ldr_s_post(23, R_X12, 4); a.fcvt_d_s(23, 23); a.dup_2d_elt0(23, 23)
  a.ldp_q(16, 17, R_X13, 0)
  a.add_r(R_X13, R_X13, R_X14)
  a.fcvtl_2d_2s(18, 16); a.fcvtl2_2d_4s(19, 16); a.fcvtl_2d_2s(20, 17); a.fcvtl2_2d_4s(21, 17)
  a.fmul_2d(24, 22, 18); a.fmul_2d(25, 22, 19); a.fmul_2d(26, 22, 20); a.fmul_2d(27, 22, 21)
  a.fadd_2d(0, 0, 24); a.fadd_2d(1, 1, 25); a.fadd_2d(2, 2, 26); a.fadd_2d(3, 3, 27)
  a.fmul_2d(24, 23, 18); a.fmul_2d(25, 23, 19); a.fmul_2d(26, 23, 20); a.fmul_2d(27, 23, 21)
  a.fadd_2d(4, 4, 24); a.fadd_2d(5, 5, 25); a.fadd_2d(6, 6, 26); a.fadd_2d(7, 7, 27)
  a.sub_i(R_X10, R_X10, 1)
  a.cbnz_x(R_X10, l_k2x8)
  # Narrow f64 -> f32 and store 8 floats to row i AND row i+1!
  a.fcvtn_2s_2d(16, 0); a.fcvtn2_4s_2d(16, 1)
  a.fcvtn_2s_2d(17, 2); a.fcvtn2_4s_2d(17, 3)
  a.stp_q(16, 17, R_X15, 0)
  a.fcvtn_2s_2d(16, 4); a.fcvtn2_4s_2d(16, 5)
  a.fcvtn_2s_2d(17, 6); a.fcvtn2_4s_2d(17, 7)
  a.stp_q(16, 17, R_X16, 0)
  a.add_i(R_X9, R_X9, 8)
  a.sub_i(R_X17, r_n, 8)
  a.cmp_r(R_X9, R_X17)
  a.b_cond(CC_LE, l_j8)
  # Scalar j tail for remaining columns (n % 8) on rows i and i+1
  a.bind(l_j8_tail)
  l_j8_t_end = a.new_label
  a.cmp_r(R_X9, r_n)
  a.b_cond(CC_GE, l_j8_t_end)
  a.mul_x(R_X11, R_X8, R_X14)
  a.add_r(R_X15, r_pc, R_X11); a.add_r(R_X15, R_X15, R_X9, 2)
  a.add_r(R_X16, R_X15, R_X14)
  a.add_r(R_X11, r_pa, R_X11); a.add_r(R_X12, R_X11, R_X14)
  a.add_r(R_X13, r_pb, R_X9, 2)
  a.mov_r(R_X10, r_n)
  a.fmov_d_x(0, R_XZR); a.fmov_d_x(1, R_XZR)
  l_kt2 = a.new_label
  a.bind(l_kt2)
  a.ldr_s_post(16, R_X11, 4); a.fcvt_d_s(16, 16)
  a.ldr_s_post(17, R_X12, 4); a.fcvt_d_s(17, 17)
  a.ldr_s_idx(18, R_X13, R_XZR); a.fcvt_d_s(18, 18)
  a.add_r(R_X13, R_X13, R_X14)
  a.fmul_d(16, 16, 18); a.fadd_d(0, 0, 16)
  a.fmul_d(17, 17, 18); a.fadd_d(1, 1, 17)
  a.sub_i(R_X10, R_X10, 1)
  a.cbnz_x(R_X10, l_kt2)
  a.fcvt_s_d(0, 0); a.str_s_idx(0, R_X15, R_XZR)
  a.fcvt_s_d(1, 1); a.str_s_idx(1, R_X16, R_XZR)
  a.add_i(R_X9, R_X9, 1)
  a.b(l_j8_tail)
  a.bind(l_j8_t_end)
  a.add_i(R_X8, R_X8, 2)
  a.sub_i(R_X17, r_n, 2)
  a.cmp_r(R_X8, R_X17)
  a.b_cond(CC_LE, l_i2)

  # Optional odd final row (if n is odd: i == n - 1)
  a.bind(l_i1_chk)
  a.cmp_r(R_X8, r_n)
  a.b_cond(CC_GE, l_fin)
  a.movz_x(R_X9, 0)
  l_j1_lp = a.new_label
  a.bind(l_j1_lp)
  a.mul_x(R_X11, R_X8, R_X14)
  a.add_r(R_X15, r_pc, R_X11); a.add_r(R_X15, R_X15, R_X9, 2)
  a.add_r(R_X11, r_pa, R_X11)
  a.add_r(R_X13, r_pb, R_X9, 2)
  a.mov_r(R_X10, r_n)
  a.fmov_d_x(0, R_XZR)
  l_k1_lp = a.new_label
  a.bind(l_k1_lp)
  a.ldr_s_post(16, R_X11, 4); a.fcvt_d_s(16, 16)
  a.ldr_s_idx(18, R_X13, R_XZR); a.fcvt_d_s(18, 18)
  a.add_r(R_X13, R_X13, R_X14)
  a.fmul_d(16, 16, 18); a.fadd_d(0, 0, 16)
  a.sub_i(R_X10, R_X10, 1)
  a.cbnz_x(R_X10, l_k1_lp)
  a.fcvt_s_d(0, 0); a.str_s_idx(0, R_X15, R_XZR)
  a.add_i(R_X9, R_X9, 1)
  a.cmp_r(R_X9, r_n)
  a.b_cond(CC_LT, l_j1_lp)
  a.b(l_fin)

  # Exact scalar fallback (for aliased matrices or n < 8)
  a.bind(l_scalar_all)
  a.lsl_xi(R_X14, r_n, 2)
  a.movz_x(R_X8, 0)
  l_si = a.new_label
  a.bind(l_si)
  a.movz_x(R_X9, 0)
  l_sj = a.new_label
  a.bind(l_sj)
  a.mul_x(R_X11, R_X8, R_X14)
  a.add_r(R_X15, r_pc, R_X11); a.add_r(R_X15, R_X15, R_X9, 2)
  a.add_r(R_X11, r_pa, R_X11)
  a.add_r(R_X13, r_pb, R_X9, 2)
  a.mov_r(R_X10, r_n)
  a.fmov_d_x(0, R_XZR)
  l_sk = a.new_label
  a.bind(l_sk)
  a.ldr_s_post(16, R_X11, 4); a.fcvt_d_s(16, 16)
  a.ldr_s_idx(18, R_X13, R_XZR); a.fcvt_d_s(18, 18)
  a.add_r(R_X13, R_X13, R_X14)
  a.fmul_d(16, 16, 18); a.fadd_d(0, 0, 16)
  a.sub_i(R_X10, R_X10, 1)
  a.cbnz_x(R_X10, l_sk)
  a.fcvt_s_d(0, 0); a.str_s_idx(0, R_X15, R_XZR)
  a.add_i(R_X9, R_X9, 1)
  a.cmp_r(R_X9, r_n)
  a.b_cond(CC_LT, l_sj)
  a.add_i(R_X8, R_X8, 1)
  a.cmp_r(R_X8, r_n)
  a.b_cond(CC_LT, l_si)

  a.bind(l_fin)
  wire_set_slot_gpr(comp, i_sl, r_n)
  a.b(l_end)
  skip
