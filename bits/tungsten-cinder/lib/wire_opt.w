# cinder/wire_opt — Pure-Tungsten Tiered WIRE IR Optimizer, Carry-Chain Pass & Loop Vectorizer!
#
# Structured into explicit Tier-2 optimization passes (`wire_run_tier2_passes`):
#   Pass 1 (`wire_pass_const_fold_and_hoist`): Constant deduplication, hoisting to `__entry`,
#          constant folding, and algebraic identity simplification.
#   Pass 2 (`wire_pass_slot_sroa_and_forward`): Intra-block store->load forwarding, redundant
#          slot-load elimination, and dead block-local scratch-slot elimination.
#   Pass 3 (`wire_pass_licm_and_cse`): Loop-invariant code motion to `__entry` and local CSE.
#   Pass 4 (`wire_pass_carry_canonicalize`): Canonicalizes unsigned overflow/borrow idioms
#          (`s = a + b; s <u a` and `a <u b` paired with `a - b`) into `:addcarry_u64` / `:subborrow_u64`.
#   Pass 5 (`wire_pass_carry_chains`): Fuses straight-line multi-limb carry/borrow chains into
#          hardware flag-threaded `:adds_u64` -> `:adcs_u64`* -> `:cset_carry_u64` and
#          `:subs_u64` -> `:sbcs_u64`* -> `:cset_borrow_u64` across flag-neutral memory ops.
#   Pass 6 (`wire_pass_dce`): Eliminates dead pure SSA instructions.
#
# Also provides portable counted carry-loop matching (`wire_match_carry_loop`: `add_limbs`,
# `sub_limbs`, `mul1_limbs`, `addmul1_limbs`) shared by both ARM64 and x86_64 backends, plus
# ARM64's 4x-unrolled flag-threaded carry/borrow/mul loops and 7 NEON SIMD microkernels!

use ./a64
use ./wire_ir
use ./opt_config

# ---- Shared IR Remap & Inspection Helpers ----

-> wire_resolve_remap(remap, vr)
  cur = vr
  guard = 0
  while cur >= 0 && remap[cur] != nil && remap[cur] != cur && guard < 32
    cur = remap[cur]
    guard += 1
  cur

-> wire_apply_vreg_remap(wf, remap)
  return nil if remap.size == 0
  bi = 0
  while bi < wf.blocks.size
    blk = wf.blocks[bi]
    ii = 0
    while ii < blk.insts.size
      ins = blk.insts[ii]
      ins.a = wire_resolve_remap(remap, ins.a) if ins.a >= 0 && remap[ins.a] != nil
      ins.b = wire_resolve_remap(remap, ins.b) if ins.b >= 0 && remap[ins.b] != nil
      ins.c = wire_resolve_remap(remap, ins.c) if ins.c >= 0 && remap[ins.c] != nil
      if ins.args != nil
        ai = 0
        while ai < ins.args.size
          av = ins.args[ai]
          ins.args[ai] = wire_resolve_remap(remap, av) if av >= 0 && remap[av] != nil
          ai += 1
      ii += 1
    bi += 1
  nil

-> wire_is_pure_op?(op)
  return true if op == :const_i64 || op == :const_f64
  return true if op == :add_i64 || op == :sub_i64 || op == :mul_i64 || op == :and_i64 || op == :or_i64 || op == :xor_i64
  return true if op == :udiv_i64 || op == :urem_i64
  return true if op == :shl_i64 || op == :ashr_i64 || op == :lshr_i64 || op == :neg_i64
  return true if op == :add_i32 || op == :sub_i32 || op == :mul_i32 || op == :and_i32 || op == :or_i32 || op == :xor_i32
  return true if op == :shl_i32 || op == :ashr_i32 || op == :lshr_i32 || op == :sext_i32_i64 || op == :zext_i32_i64 || op == :trunc_i64_i32
  return true if op == :fadd_f64 || op == :fsub_f64 || op == :fmul_f64 || op == :fdiv_f64 || op == :fmin_f64 || op == :fmax_f64 || op == :fmadd_f64 || op == :fmsub_f64
  return true if op == :fneg_f64 || op == :fabs_f64 || op == :fsqrt_f64 || op == :ffloor_f64 || op == :fceil_f64 || op == :fround_f32 || op == :fround_f16
  return true if op == :sitofp_i64_f64 || op == :uitofp_u64_f64 || op == :fptosi_f64_i64 || op == :fptoui_f64_u64 || op == :nanbox_float || op == :unbox_float
  return true if op == :icmp_i64 || op == :fcmp_f64 || op == :select_i64 || op == :select_f64
  return true if op == :arr_data_ptr || op == :array_size_raw
  return true if op == :addcarry_u64 || op == :subborrow_u64 || op == :mulhi_u64
  return true if op == :ctz_i64 || op == :clz_i64
  false

# Instructions whose native emission on BOTH ARM64 and x86_64 never modifies NZCV.C / RFLAGS.CF!
-> wire_is_flag_neutral?(ins)
  op = ins.op
  return true if op == :load_i64 || op == :store_i64 || op == :load_double || op == :store_double
  return true if op == :cset_carry_u64 || op == :cset_borrow_u64
  return true if op == :raw_load || op == :raw_store
  if op == :typed_array_get_inline || op == :typed_array_set_inline
    # Note: ebits == -16 (`Float16Array`) uses `cmp` on x86_64 software FP16 conversion, so exclude -16!
    return ins.ebits != -16
  false

# ---- Pass 1: Constant Deduplication, Hoisting & Algebraic Simplification ----

-> wire_intern_const_i64(wf, val, i_map, c_i64, hoisted_consts)
  existing = i_map[val]
  return existing if existing != nil
  d = wf.new_vreg(:i64)
  ins = WireInst.new(:const_i64, d)
  ins.imm = val
  i_map[val] = d
  c_i64[d] = val
  hoisted_consts.push(ins)
  d

-> wire_pass_const_fold_and_hoist(wf)
  return nil if wf == nil || wf.blocks.size == 0
  entry = wf.blocks[0]
  return nil if entry.insts.size == 0
  term = entry.insts[entry.insts.size - 1]
  has_term = term.op == :br || term.op == :cond_br || term.op == :ret_i64 || term.op == :ret_f64 || term.op == :ret_void
  return nil if !has_term

  i_map = {}
  f_map = {}
  c_i64 = {}
  remap = {}
  hoisted_consts = []
  entry_body = []

  bi = 0
  while bi < wf.blocks.size
    blk = wf.blocks[bi]
    limit = bi == 0 ? (blk.insts.size - 1) : blk.insts.size
    kept = []
    ii = 0
    while ii < limit
      ins = blk.insts[ii]
      ins.a = wire_resolve_remap(remap, ins.a) if ins.a >= 0 && remap[ins.a] != nil
      ins.b = wire_resolve_remap(remap, ins.b) if ins.b >= 0 && remap[ins.b] != nil
      ins.c = wire_resolve_remap(remap, ins.c) if ins.c >= 0 && remap[ins.c] != nil
      op = ins.op
      if op == :const_i64 && ins.dst >= 0
        prev = i_map[ins.imm]
        if prev != nil
          remap[ins.dst] = prev
        else
          i_map[ins.imm] = ins.dst
          c_i64[ins.dst] = ins.imm
          hoisted_consts.push(ins)
      elsif op == :const_f64 && ins.dst >= 0
        fb = wvalue_bits(ins.fimm) ## i64
        prev = f_map[fb]
        if prev != nil
          remap[ins.dst] = prev
        else
          f_map[fb] = ins.dst
          hoisted_consts.push(ins)
      else
        ca = ins.a >= 0 ? c_i64[ins.a] : nil
        cb = ins.b >= 0 ? c_i64[ins.b] : nil
        folded = false
        if op == :add_i64
          if ca != nil && cb != nil
            remap[ins.dst] = wire_intern_const_i64(wf, ca + cb, i_map, c_i64, hoisted_consts)
            folded = true
          elsif cb == 0
            remap[ins.dst] = ins.a; folded = true
          elsif ca == 0
            remap[ins.dst] = ins.b; folded = true
        elsif op == :sub_i64
          if ca != nil && cb != nil
            remap[ins.dst] = wire_intern_const_i64(wf, ca - cb, i_map, c_i64, hoisted_consts)
            folded = true
          elsif cb == 0
            remap[ins.dst] = ins.a; folded = true
        elsif op == :mul_i64
          if ca != nil && cb != nil
            remap[ins.dst] = wire_intern_const_i64(wf, ca * cb, i_map, c_i64, hoisted_consts)
            folded = true
          elsif cb == 1
            remap[ins.dst] = ins.a; folded = true
          elsif ca == 1
            remap[ins.dst] = ins.b; folded = true
          elsif ca == 0 || cb == 0
            remap[ins.dst] = wire_intern_const_i64(wf, 0, i_map, c_i64, hoisted_consts)
            folded = true
        elsif op == :xor_i64 || op == :or_i64
          if cb == 0
            remap[ins.dst] = ins.a; folded = true
          elsif ca == 0
            remap[ins.dst] = ins.b; folded = true
        elsif op == :and_i64
          if ca == 0 || cb == 0
            remap[ins.dst] = wire_intern_const_i64(wf, 0, i_map, c_i64, hoisted_consts)
            folded = true
          elsif cb == -1
            remap[ins.dst] = ins.a; folded = true
        elsif op == :shl_i64 || op == :lshr_i64 || op == :ashr_i64
          if cb == 0
            remap[ins.dst] = ins.a; folded = true
        elsif op == :addcarry_u64
          if ca == 0 || cb == 0
            remap[ins.dst] = wire_intern_const_i64(wf, 0, i_map, c_i64, hoisted_consts)
            folded = true
        elsif op == :subborrow_u64
          if cb == 0
            remap[ins.dst] = wire_intern_const_i64(wf, 0, i_map, c_i64, hoisted_consts)
            folded = true
        if !folded
          if bi == 0
            entry_body.push(ins)
          else
            kept.push(ins)
      ii += 1
    if bi > 0
      blk.insts = kept
    bi += 1

  new_entry = []
  hi = 0
  while hi < hoisted_consts.size
    new_entry.push(hoisted_consts[hi])
    hi += 1
  ei = 0
  while ei < entry_body.size
    new_entry.push(entry_body[ei])
    ei += 1
  new_entry.push(term)
  entry.insts = new_entry
  wire_apply_vreg_remap(wf, remap)
  nil

# ---- Pass 2: Intra-Block Slot Store->Load Forwarding & Dead Scratch-Slot SROA ----

-> wire_pass_slot_sroa_and_forward(wf)
  return nil if wf == nil || wf.slots == 0
  remap = {}

  # Step 1: Forward store->load and load->load within every basic block
  bi = 0
  while bi < wf.blocks.size
    blk = wf.blocks[bi]
    cur_val = {}
    kept = []
    ii = 0
    while ii < blk.insts.size
      ins = blk.insts[ii]
      ins.a = wire_resolve_remap(remap, ins.a) if ins.a >= 0 && remap[ins.a] != nil
      ins.b = wire_resolve_remap(remap, ins.b) if ins.b >= 0 && remap[ins.b] != nil
      ins.c = wire_resolve_remap(remap, ins.c) if ins.c >= 0 && remap[ins.c] != nil
      op = ins.op
      if op == :store_i64 || op == :store_double
        cur_val[ins.imm] = ins.a
        kept.push(ins)
      elsif op == :load_i64 || op == :load_double
        known = cur_val[ins.imm]
        if known != nil
          remap[ins.dst] = known
        else
          cur_val[ins.imm] = ins.dst
          kept.push(ins)
      else
        kept.push(ins)
      ii += 1
    blk.insts = kept
    bi += 1

  wire_apply_vreg_remap(wf, remap)

  # Step 2: Any slot that now has ZERO loads across the entire function is write-only dead!
  # Also collapse consecutive stores to the same slot within a single basic block (keep last store).
  has_load = Array.new(wf.slots, false)
  bi = 0
  while bi < wf.blocks.size
    blk = wf.blocks[bi]
    ii = 0
    while ii < blk.insts.size
      op = blk.insts[ii].op
      has_load[blk.insts[ii].imm] = true if op == :load_i64 || op == :load_double
      ii += 1
    bi += 1

  bi = 0
  while bi < wf.blocks.size
    blk = wf.blocks[bi]
    # Walk backwards to drop dead stores and overwritten same-block stores
    seen_later_store = {}
    rev = []
    ii = blk.insts.size - 1
    while ii >= 0
      ins = blk.insts[ii]
      op = ins.op
      if op == :store_i64 || op == :store_double
        sl = ins.imm
        if has_load[sl] && !seen_later_store[sl]
          seen_later_store[sl] = true
          rev.push(ins)
      else
        # Note: loads before a later store already got forwarded/used, and stores only touch slot `sl`
        rev.push(ins)
      ii -= 1
    fwd = []
    ri = rev.size - 1
    while ri >= 0
      fwd.push(rev[ri])
      ri -= 1
    blk.insts = fwd
    bi += 1
  nil

# ---- Pass 3: LICM (Hoist Invariants to Entry) & Intra-Block CSE ----

-> wire_cse_key(ins)
  op = ins.op
  return nil if !wire_is_pure_op?(op) || op == :const_i64 || op == :const_f64
  a = ins.a
  b = ins.b
  # Canonicalize commutative ops so `a + b` and `b + a` share one key
  if (op == :add_i64 || op == :mul_i64 || op == :and_i64 || op == :or_i64 || op == :xor_i64 || op == :addcarry_u64 || op == :mulhi_u64) && a > b
    t = a; a = b; b = t
  op.to_s + ":" + a.to_s + ":" + b.to_s + ":" + ins.c.to_s + ":" + ins.ebits.to_s + ":" + (ins.pred != nil ? ins.pred.to_s : "")

-> wire_pass_licm_and_cse(wf)
  return nil if wf == nil || wf.blocks.size == 0
  entry = wf.blocks[0]
  return nil if entry.insts.size == 0
  term = entry.insts[entry.insts.size - 1]
  has_term = term.op == :br || term.op == :cond_br || term.op == :ret_i64 || term.op == :ret_f64 || term.op == :ret_void
  return nil if !has_term

  in_entry = Array.new(wf.next_vreg, false)
  pi = 0
  while pi < wf.params.size
    in_entry[pi] = true
    pi += 1

  remap = {}
  entry_cse = {}
  entry_kept = []
  ei = 0
  while ei < entry.insts.size - 1
    ins = entry.insts[ei]
    ins.a = wire_resolve_remap(remap, ins.a) if ins.a >= 0 && remap[ins.a] != nil
    ins.b = wire_resolve_remap(remap, ins.b) if ins.b >= 0 && remap[ins.b] != nil
    ins.c = wire_resolve_remap(remap, ins.c) if ins.c >= 0 && remap[ins.c] != nil
    k = wire_cse_key(ins)
    if k != nil && entry_cse[k] != nil
      remap[ins.dst] = entry_cse[k]
    else
      entry_cse[k] = ins.dst if k != nil && ins.dst >= 0
      in_entry[ins.dst] = true if ins.dst >= 0
      entry_kept.push(ins)
    ei += 1

  bi = 1
  while bi < wf.blocks.size
    blk = wf.blocks[bi]
    blk_cse = {}
    kept = []
    ii = 0
    while ii < blk.insts.size
      ins = blk.insts[ii]
      ins.a = wire_resolve_remap(remap, ins.a) if ins.a >= 0 && remap[ins.a] != nil
      ins.b = wire_resolve_remap(remap, ins.b) if ins.b >= 0 && remap[ins.b] != nil
      ins.c = wire_resolve_remap(remap, ins.c) if ins.c >= 0 && remap[ins.c] != nil
      k = wire_cse_key(ins)
      if k != nil && entry_cse[k] != nil
        remap[ins.dst] = entry_cse[k]
      elsif k != nil && blk_cse[k] != nil
        remap[ins.dst] = blk_cse[k]
      elsif ins.dst >= 0 && wire_is_pure_op?(ins.op) && ins.op != :icmp_i64 && ins.op != :fcmp_f64 && (ins.a < 0 || in_entry[ins.a]) && (ins.b < 0 || in_entry[ins.b]) && (ins.c < 0 || in_entry[ins.c]) && ins.args == nil
        # Loop-invariant pure instruction: hoist to `__entry`!
        entry_cse[k] = ins.dst if k != nil
        in_entry[ins.dst] = true
        entry_kept.push(ins)
      else
        blk_cse[k] = ins.dst if k != nil && ins.dst >= 0
        kept.push(ins)
      ii += 1
    blk.insts = kept
    bi += 1

  entry_kept.push(term)
  entry.insts = entry_kept
  wire_apply_vreg_remap(wf, remap)
  nil

# ---- Pass 4: Carry & Borrow Idiom Canonicalization ----

-> wire_pass_carry_canonicalize(wf)
  return nil if wf == nil
  defs = {}
  c_i64 = {}
  bi = 0
  while bi < wf.blocks.size
    blk = wf.blocks[bi]
    ii = 0
    while ii < blk.insts.size
      ins = blk.insts[ii]
      if ins.dst >= 0
        defs[ins.dst] = ins
        c_i64[ins.dst] = ins.imm if ins.op == :const_i64
      ii += 1
    bi += 1

  remap = {}
  bi = 0
  while bi < wf.blocks.size
    blk = wf.blocks[bi]
    sub_pairs = {}
    ii = 0
    while ii < blk.insts.size
      ins = blk.insts[ii]
      if ins.op == :sub_i64
        sub_pairs[ins.a.to_s + ":" + ins.b.to_s] = true
      ii += 1

    ii = 0
    while ii < blk.insts.size
      ins = blk.insts[ii]
      if ins.op == :icmp_i64
        if ins.pred == :ult
          da = defs[ins.a]
          if da != nil && da.op == :add_i64 && (ins.b == da.a || ins.b == da.b)
            ins.op = :addcarry_u64
            ins.a = da.a
            ins.b = da.b
            ins.pred = nil
          elsif sub_pairs[ins.a.to_s + ":" + ins.b.to_s]
            ins.op = :subborrow_u64
            ins.pred = nil
        elsif ins.pred == :ugt
          db = defs[ins.b]
          if db != nil && db.op == :add_i64 && (ins.a == db.a || ins.a == db.b)
            ins.op = :addcarry_u64
            ins.a = db.a
            ins.b = db.b
            ins.pred = nil
          elsif sub_pairs[ins.b.to_s + ":" + ins.a.to_s]
            ins.op = :subborrow_u64
            t_swp = ins.a
            ins.a = ins.b
            ins.b = t_swp
            ins.pred = nil
      elsif ins.op == :select_i64
        # `cond ? 1 : 0` where `cond` is already a 0/1 boolean (`icmp_i64`, `addcarry_u64`, `subborrow_u64`)
        dc = defs[ins.a]
        if c_i64[ins.b] == 1 && c_i64[ins.c] == 0 && dc != nil && (dc.op == :icmp_i64 || dc.op == :addcarry_u64 || dc.op == :subborrow_u64)
          remap[ins.dst] = ins.a
      ii += 1
    bi += 1

  wire_apply_vreg_remap(wf, remap)
  nil

# ---- Counted Loop & Multi-Limb Carry-Loop Matcher (Shared by ARM64 & x86_64) ----

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

-> wire_slot_init_i64?(blk, sl, want_val, c_i64)
  found = false
  ii = 0
  while ii < blk.insts.size
    ins = blk.insts[ii]
    if ins.op == :store_i64 && ins.imm == sl
      found = (c_i64[ins.a] == want_val)
    ii += 1
  found

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
    n = body_blk.insts.size
    return nil if n < 4
    st_i = body_blk.insts[n - 2]
    add_i = body_blk.insts[n - 3]
    return nil if st_i.op != :store_i64 || st_i.imm != idx_slot
    return nil if add_i.op != :add_i64 || add_i.dst != st_i.a || c_i64[add_i.b] != 1
    body_core = []
    k = 0
    while k < n - 3
      body_core.push(body_blk.insts[k])
      k += 1
    return [body_core, idx_slot, lim_vr, end_id, {cond_id => true, body_id => true}]
  else
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

-> wire_is_slot_load?(vr, slot, defs)
  d = defs[vr]
  d != nil && (d.op == :load_i64 || d.op == :load_double) && d.imm == slot

-> wire_comm_pair?(ins, want_op, x, y)
  ins != nil && ins.op == want_op && ((ins.a == x && ins.b == y) || (ins.a == y && ins.b == x))

-> wire_is_loop_inv_vr?(vr, idx_sl, c_sl, defs, body_vregs)
  return false if vr < 0
  d = defs[vr]
  return true if d == nil   # function parameter
  if d.op == :load_i64
    return d.imm != idx_sl && d.imm != c_sl
  !body_vregs[vr]

# Match `idx_vr` == `load(idx_sl)` -> `[true, -1]`, or `load(idx_sl) + inv_vr` -> `[true, inv_vr]`
-> wire_match_idx_plus_inv(idx_vr, idx_sl, c_sl, defs, body_vregs)
  return [true, -1] if wire_is_slot_load?(idx_vr, idx_sl, defs)
  d = defs[idx_vr]
  if d != nil && d.op == :add_i64
    if wire_is_slot_load?(d.a, idx_sl, defs) && wire_is_loop_inv_vr?(d.b, idx_sl, c_sl, defs, body_vregs)
      return [true, d.b]
    if wire_is_slot_load?(d.b, idx_sl, defs) && wire_is_loop_inv_vr?(d.a, idx_sl, c_sl, defs, body_vregs)
      return [true, d.a]
  [false, -1]

# Verify every write to `c_sl` outside the loop (`skip`) produces a 1-bit `{0, 1}` carry/borrow.
-> wire_slot_init_u1?(wf, c_sl, skip, defs, c_i64)
  found = false
  bi = 0
  while bi < wf.blocks.size
    if !skip[bi]
      blk = wf.blocks[bi]
      ii = 0
      while ii < blk.insts.size
        ins = blk.insts[ii]
        if ins.op == :store_i64 && ins.imm == c_sl
          found = true
          cv = c_i64[ins.a]
          if cv != 0 && cv != 1
            d = defs[ins.a]
            ok_d = d != nil && (d.op == :addcarry_u64 || d.op == :subborrow_u64 || d.op == :cset_carry_u64 || d.op == :cset_borrow_u64 || d.op == :icmp_i64)
            return false if !ok_d
        ii += 1
    bi += 1
  found

# Match counted 64-bit multi-limb bignum loops:
#   - `:add_limbs`:    `out[i+oo] = a[i+ao] + b[i+bo] + c`
#   - `:sub_limbs`:    `out[i+oo] = a[i+ao] - b[i+bo] - b_in`
#   - `:mul1_limbs`:   `p = a[i+ao] * w + c; out[i+oo] = lo(p); c = hi(p)`
#   - `:addmul1_limbs`:`p = out[i+oo] + a[i+ao] * w + c; out[i+oo] = lo(p); c = hi(p)`
# Returns `[kind, idx_sl, lim_vr, end_id, skip_map, c_sl, p_out_vr, off_out_vr, p_a_vr, off_a_vr, p_b_vr, off_b_vr, w_vr]` or `nil`.
-> wire_match_carry_loop(wf, cond_id, defs, c_i64)
  lp = wire_match_counted_loop(wf, cond_id, c_i64)
  return nil if lp == nil
  body = lp[0]; idx_sl = lp[1]; lim_vr = lp[2]; end_id = lp[3]; skip = lp[4]
  return nil if body.size < 4 || body.size > 24

  st_ta = nil
  st_c = nil
  body_vregs = {}
  bi = 0
  while bi < body.size
    ins = body[bi]
    body_vregs[ins.dst] = true if ins.dst >= 0
    op = ins.op
    if op == :typed_array_set_inline
      return nil if st_ta != nil || (ins.ebits != 64 && ins.ebits != 66)
      st_ta = ins
    elsif op == :store_i64
      return nil if st_c != nil || ins.imm == idx_sl
      st_c = ins
    elsif op == :store_double || op == :call_c_f64 || op == :call_direct_i64
      return nil
    bi += 1
  return nil if st_ta == nil || st_c == nil

  c_sl = st_c.imm
  oi_m = wire_match_idx_plus_inv(st_ta.b, idx_sl, c_sl, defs, body_vregs)
  return nil if !oi_m[0]
  off_out = oi_m[1]
  val_vr = st_ta.c
  cout_vr = st_c.a
  val_def = defs[val_vr]
  cout_def = defs[cout_vr]
  return nil if val_def == nil || cout_def == nil

  # 1. Check `:add_limbs`, `:mul1_limbs`, and `:addmul1_limbs` (`val_def.op == :add_i64`)
  if val_def.op == :add_i64
    # 1a. 2-addend `:mul1_limbs`: `val_vr = lo_vr + cin_vr` where `lo_vr = mul_i64(ai_vr, w_vr)`
    m_lo_vr = -1; m_cin_vr = -1
    if wire_is_slot_load?(val_def.b, c_sl, defs)
      m_lo_vr = val_def.a; m_cin_vr = val_def.b
    elsif wire_is_slot_load?(val_def.a, c_sl, defs)
      m_lo_vr = val_def.b; m_cin_vr = val_def.a
    if m_lo_vr >= 0
      m_def = defs[m_lo_vr]
      if m_def != nil && m_def.op == :mul_i64
        ai_vr = -1; w_vr = -1
        ga = defs[m_def.a]; gb = defs[m_def.b]
        if ga != nil && ga.op == :typed_array_get_inline && (ga.ebits == 64 || ga.ebits == 66) && wire_is_loop_inv_vr?(m_def.b, idx_sl, c_sl, defs, body_vregs)
          ai_vr = m_def.a; w_vr = m_def.b
        elsif gb != nil && gb.op == :typed_array_get_inline && (gb.ebits == 64 || gb.ebits == 66) && wire_is_loop_inv_vr?(m_def.a, idx_sl, c_sl, defs, body_vregs)
          ai_vr = m_def.b; w_vr = m_def.a
        if ai_vr >= 0
          ga = defs[ai_vr]
          ai_m = wire_match_idx_plus_inv(ga.b, idx_sl, c_sl, defs, body_vregs)
          if ai_m[0] && cout_def.op == :add_i64
            ca = defs[cout_def.a]; cb = defs[cout_def.b]
            ok_c = (wire_comm_pair?(ca, :mulhi_u64, ai_vr, w_vr) && wire_comm_pair?(cb, :addcarry_u64, m_lo_vr, m_cin_vr)) || (wire_comm_pair?(cb, :mulhi_u64, ai_vr, w_vr) && wire_comm_pair?(ca, :addcarry_u64, m_lo_vr, m_cin_vr))
            if ok_c
              return [:mul1_limbs, idx_sl, lim_vr, end_id, skip, c_sl, st_ta.a, off_out, ga.a, ai_m[1], -1, -1, w_vr]

    # 1b. 3-addend `(x_vr + y_vr) + z_vr` (handles all associativities of `:add_limbs` and `:addmul1_limbs`!)
    s1_vr = -1; z_vr = -1
    da_v = defs[val_def.a]; db_v = defs[val_def.b]
    if da_v != nil && da_v.op == :add_i64
      s1_vr = val_def.a; z_vr = val_def.b
    elsif db_v != nil && db_v.op == :add_i64
      s1_vr = val_def.b; z_vr = val_def.a

    if s1_vr >= 0
      s1_def = defs[s1_vr]
      x_vr = s1_def.a; y_vr = s1_def.b
      add3 = [x_vr, y_vr, z_vr]
      cin_pos = -1
      ki = 0
      while ki < 3
        cin_pos = ki if wire_is_slot_load?(add3[ki], c_sl, defs)
        ki += 1
      if cin_pos >= 0
        other = []
        ki = 0
        while ki < 3
          other.push(add3[ki]) if ki != cin_pos
          ki += 1
        u_vr = other[0]; v_vr = other[1]
        du = defs[u_vr]; dv = defs[v_vr]

        # Check `:add_limbs`: `u_vr` and `v_vr` are both `typed_array_get_inline(64/66)` and `c_sl` init is `{0, 1}`
        if du != nil && dv != nil && du.op == :typed_array_get_inline && dv.op == :typed_array_get_inline && (du.ebits == 64 || du.ebits == 66) && (dv.ebits == 64 || dv.ebits == 66)
          mu = wire_match_idx_plus_inv(du.b, idx_sl, c_sl, defs, body_vregs)
          mv = wire_match_idx_plus_inv(dv.b, idx_sl, c_sl, defs, body_vregs)
          if mu[0] && mv[0] && wire_slot_init_u1?(wf, c_sl, skip, defs, c_i64) && (cout_def.op == :add_i64 || cout_def.op == :or_i64 || cout_def.op == :xor_i64)
            ca = defs[cout_def.a]; cb = defs[cout_def.b]
            ok_c = (wire_comm_pair?(ca, :addcarry_u64, x_vr, y_vr) && wire_comm_pair?(cb, :addcarry_u64, s1_vr, z_vr)) || (wire_comm_pair?(cb, :addcarry_u64, x_vr, y_vr) && wire_comm_pair?(ca, :addcarry_u64, s1_vr, z_vr))
            if ok_c
              return [:add_limbs, idx_sl, lim_vr, end_id, skip, c_sl, st_ta.a, off_out, du.a, mu[1], dv.a, mv[1], -1]

        # Check `:addmul1_limbs`: one of `(u_vr, v_vr)` is `out[i+off_out]`, the other is `mul_i64(ai_vr, w_vr)`
        oi_vr = -1; mul_def = nil
        if du != nil && du.op == :typed_array_get_inline && du.a == st_ta.a && du.b == st_ta.b && dv != nil && dv.op == :mul_i64
          oi_vr = u_vr; mul_def = dv
        elsif dv != nil && dv.op == :typed_array_get_inline && dv.a == st_ta.a && dv.b == st_ta.b && du != nil && du.op == :mul_i64
          oi_vr = v_vr; mul_def = du
        if oi_vr >= 0 && mul_def != nil
          ai_vr = -1; w_vr = -1
          ga = defs[mul_def.a]; gb = defs[mul_def.b]
          if ga != nil && ga.op == :typed_array_get_inline && (ga.ebits == 64 || ga.ebits == 66) && wire_is_loop_inv_vr?(mul_def.b, idx_sl, c_sl, defs, body_vregs)
            ai_vr = mul_def.a; w_vr = mul_def.b
          elsif gb != nil && gb.op == :typed_array_get_inline && (gb.ebits == 64 || gb.ebits == 66) && wire_is_loop_inv_vr?(mul_def.a, idx_sl, c_sl, defs, body_vregs)
            ai_vr = mul_def.b; w_vr = mul_def.a
          if ai_vr >= 0
            ga = defs[ai_vr]
            ai_m = wire_match_idx_plus_inv(ga.b, idx_sl, c_sl, defs, body_vregs)
            if ai_m[0] && cout_def.op == :add_i64
              terms = []
              d_l = defs[cout_def.a]; d_r = defs[cout_def.b]
              if d_l != nil && d_l.op == :add_i64
                terms = [defs[d_l.a], defs[d_l.b], d_r]
              elsif d_r != nil && d_r.op == :add_i64
                terms = [d_l, defs[d_r.a], defs[d_r.b]]
              if terms.size == 3
                has_mh = false; has_c1 = false; has_c2 = false
                ti = 0
                while ti < 3
                  tm = terms[ti]
                  has_mh = true if wire_comm_pair?(tm, :mulhi_u64, ai_vr, w_vr)
                  has_c1 = true if wire_comm_pair?(tm, :addcarry_u64, x_vr, y_vr)
                  has_c2 = true if wire_comm_pair?(tm, :addcarry_u64, s1_vr, z_vr)
                  ti += 1
                if has_mh && has_c1 && has_c2
                  return [:addmul1_limbs, idx_sl, lim_vr, end_id, skip, c_sl, st_ta.a, off_out, ga.a, ai_m[1], -1, -1, w_vr]

  # 2. Check `:sub_limbs` (`val_def.op == :sub_i64`)
  if val_def.op == :sub_i64 && wire_is_slot_load?(val_def.b, c_sl, defs)
    d1_vr = val_def.a
    bin_vr = val_def.b
    d1_def = defs[d1_vr]
    if d1_def != nil && d1_def.op == :sub_i64
      dx = defs[d1_def.a]; dy = defs[d1_def.b]
      if dx != nil && dy != nil && dx.op == :typed_array_get_inline && dy.op == :typed_array_get_inline && (dx.ebits == 64 || dx.ebits == 66) && (dy.ebits == 64 || dy.ebits == 66)
        mx = wire_match_idx_plus_inv(dx.b, idx_sl, c_sl, defs, body_vregs)
        my = wire_match_idx_plus_inv(dy.b, idx_sl, c_sl, defs, body_vregs)
        if mx[0] && my[0] && wire_slot_init_u1?(wf, c_sl, skip, defs, c_i64) && (cout_def.op == :add_i64 || cout_def.op == :or_i64 || cout_def.op == :xor_i64)
          ca = defs[cout_def.a]; cb = defs[cout_def.b]
          ok_b = (ca != nil && ca.op == :subborrow_u64 && ca.a == d1_def.a && ca.b == d1_def.b && cb != nil && cb.op == :subborrow_u64 && cb.a == d1_vr && cb.b == bin_vr) || (cb != nil && cb.op == :subborrow_u64 && cb.a == d1_def.a && cb.b == d1_def.b && ca != nil && ca.op == :subborrow_u64 && ca.a == d1_vr && ca.b == bin_vr)
          if ok_b
            return [:sub_limbs, idx_sl, lim_vr, end_id, skip, c_sl, st_ta.a, off_out, dx.a, mx[1], dy.a, my[1], -1]

  nil

# ---- Pass 5: Straight-Line Multi-Limb Carry/Borrow Chain Fusion ----

-> wire_count_vreg_uses(wf)
  uses = Array.new(wf.next_vreg, 0)
  bi = 0
  while bi < wf.blocks.size
    blk = wf.blocks[bi]
    ii = 0
    while ii < blk.insts.size
      ins = blk.insts[ii]
      uses[ins.a] = uses[ins.a] + 1 if ins.a >= 0
      uses[ins.b] = uses[ins.b] + 1 if ins.b >= 0
      uses[ins.c] = uses[ins.c] + 1 if ins.c >= 0
      if ins.args != nil
        ai = 0
        while ai < ins.args.size
          av = ins.args[ai]
          uses[av] = uses[av] + 1 if av >= 0
          ai += 1
      ii += 1
    bi += 1
  uses

-> wire_pass_carry_chains(wf)
  return nil if wf == nil
  maps = wire_build_def_maps(wf)
  defs = maps[0]; c_i64 = maps[1]

  # Skip blocks that belong to counted carry loops (those loops emit 4x-unrolled flag-threaded kernels!)
  loop_skip = {}
  bi = 1
  while bi < wf.blocks.size
    cl = wire_match_carry_loop(wf, bi, defs, c_i64)
    if cl != nil
      cl[4].keys.each ->(sid) loop_skip[sid] = true
    bi += 1

  uses = wire_count_vreg_uses(wf)

  bi = 0
  while bi < wf.blocks.size
    if !loop_skip[bi]
      blk = wf.blocks[bi]
      n = blk.insts.size
      def_pos = {}
      ii = 0
      while ii < n
        d = blk.insts[ii].dst
        def_pos[d] = ii if d >= 0
        ii += 1

      dead_idx = {}
      insert_after = {}   # idx -> WireInst (`:cset_carry_u64` or `:cset_borrow_u64`)

      ii = 0
      while ii < n
        ins = blk.insts[ii]
        if !dead_idx[ii] && (ins.op == :add_i64 || ins.op == :sub_i64)
          is_add = ins.op == :add_i64
          carry_op = is_add ? :addcarry_u64 : :subborrow_u64
          a0 = ins.a; b0 = ins.b
          # Look forward across flag-neutral instructions for matching `c0 = addcarry_u64(a0, b0)` / `subborrow_u64(a0, b0)`
          c0_idx = -1
          scan = ii + 1
          while scan < n
            si_ins = blk.insts[scan]
            if !dead_idx[scan]
              if si_ins.op == carry_op && ((is_add && ((si_ins.a == a0 && si_ins.b == b0) || (si_ins.a == b0 && si_ins.b == a0))) || (!is_add && si_ins.a == a0 && si_ins.b == b0))
                c0_idx = scan
                break
              break if !wire_is_flag_neutral?(si_ins)
            scan += 1

          if c0_idx >= 0
            ins.op = is_add ? :adds_u64 : :subs_u64
            dead_idx[c0_idx] = true
            flag_pos = ii
            c_prev = blk.insts[c0_idx].dst

            # Greedily extend chain through subsequent limbs `k = 1, 2, ...` in the same block!
            extending = true
            while extending && c_prev >= 0 && uses[c_prev] == 2
              extending = false
              # Search forward from `flag_pos + 1` for Limb `k`:
              #   `t_k = add/sub(a_k, b_k)` (`uses == 2`)
              #   `c1_k = addcarry/subborrow(a_k, b_k)` (`uses == 1`)
              #   `s_k = add/sub(t_k, c_prev)`
              #   `c2_k = addcarry/subborrow(t_k, c_prev)` (`uses == 1`)
              #   `c_k = add/or/xor(c1_k, c2_k)`
              i_tk = -1; i_c1 = -1; i_sk = -1; i_c2 = -1; i_ck = -1
              ak = -1; bk = -1; tk_vr = -1; c1_vr = -1; c2_vr = -1; ck_vr = -1
              p = flag_pos + 1
              while p < n
                pi_ins = blk.insts[p]
                if !dead_idx[p]
                  if i_tk < 0 && pi_ins.op == (is_add ? :add_i64 : :sub_i64) && uses[pi_ins.dst] == 2 && pi_ins.a != c_prev && pi_ins.b != c_prev
                    i_tk = p; tk_vr = pi_ins.dst; ak = pi_ins.a; bk = pi_ins.b
                  elsif i_tk >= 0 && i_c1 < 0 && pi_ins.op == carry_op && uses[pi_ins.dst] == 1 && ((is_add && ((pi_ins.a == ak && pi_ins.b == bk) || (pi_ins.a == bk && pi_ins.b == ak))) || (!is_add && pi_ins.a == ak && pi_ins.b == bk))
                    i_c1 = p; c1_vr = pi_ins.dst
                  elsif i_tk >= 0 && i_sk < 0 && pi_ins.op == (is_add ? :add_i64 : :sub_i64) && ((is_add && ((pi_ins.a == tk_vr && pi_ins.b == c_prev) || (pi_ins.a == c_prev && pi_ins.b == tk_vr))) || (!is_add && pi_ins.a == tk_vr && pi_ins.b == c_prev))
                    i_sk = p
                  elsif i_tk >= 0 && i_c2 < 0 && pi_ins.op == carry_op && uses[pi_ins.dst] == 1 && ((is_add && ((pi_ins.a == tk_vr && pi_ins.b == c_prev) || (pi_ins.a == c_prev && pi_ins.b == tk_vr))) || (!is_add && pi_ins.a == tk_vr && pi_ins.b == c_prev))
                    i_c2 = p; c2_vr = pi_ins.dst
                  elsif i_c1 >= 0 && i_c2 >= 0 && i_sk >= 0 && (pi_ins.op == :add_i64 || pi_ins.op == :or_i64 || pi_ins.op == :xor_i64) && ((pi_ins.a == c1_vr && pi_ins.b == c2_vr) || (pi_ins.a == c2_vr && pi_ins.b == c1_vr))
                    i_ck = p; ck_vr = pi_ins.dst
                    break
                  elsif !wire_is_flag_neutral?(pi_ins)
                    break
                p += 1

              if i_tk >= 0 && i_c1 >= 0 && i_sk >= 0 && i_c2 >= 0 && i_ck >= 0
                # Verify every non-limb instruction in `(flag_pos .. i_ck)` is flag-neutral!
                ok_span = true
                q = flag_pos + 1
                while q < i_ck
                  if !dead_idx[q] && q != i_tk && q != i_c1 && q != i_sk && q != i_c2
                    ok_span = false if !wire_is_flag_neutral?(blk.insts[q])
                  q += 1
                if ok_span
                  sk_ins = blk.insts[i_sk]
                  sk_ins.op = is_add ? :adcs_u64 : :sbcs_u64
                  sk_ins.a = ak
                  sk_ins.b = bk
                  dead_idx[i_tk] = true
                  dead_idx[i_c1] = true
                  dead_idx[i_c2] = true
                  dead_idx[i_ck] = true
                  flag_pos = i_sk
                  c_prev = ck_vr
                  extending = true

            # Materialize final carry/borrow if `c_prev` is used after the chain!
            if c_prev >= 0 && uses[c_prev] > 0
              cset_op = is_add ? :cset_carry_u64 : :cset_borrow_u64
              insert_after[flag_pos] = WireInst.new(cset_op, c_prev)
        ii += 1

      if dead_idx.size > 0 || insert_after.size > 0
        rebuilt = []
        ii = 0
        while ii < n
          rebuilt.push(blk.insts[ii]) if !dead_idx[ii]
          rebuilt.push(insert_after[ii]) if insert_after[ii] != nil
          ii += 1
        blk.insts = rebuilt
    bi += 1
  nil

# ---- Pass 6: Dead Pure SSA Instruction Elimination (DCE) ----

-> wire_pass_dce(wf)
  return nil if wf == nil
  uses = wire_count_vreg_uses(wf)
  changed = true
  while changed
    changed = false
    bi = wf.blocks.size - 1
    while bi >= 0
      blk = wf.blocks[bi]
      kept_rev = []
      ii = blk.insts.size - 1
      while ii >= 0
        ins = blk.insts[ii]
        if ins.dst >= 0 && uses[ins.dst] == 0 && wire_is_pure_op?(ins.op)
          uses[ins.a] = uses[ins.a] - 1 if ins.a >= 0
          uses[ins.b] = uses[ins.b] - 1 if ins.b >= 0
          uses[ins.c] = uses[ins.c] - 1 if ins.c >= 0
          changed = true
        else
          kept_rev.push(ins)
        ii -= 1
      fwd = []
      ri = kept_rev.size - 1
      while ri >= 0
        fwd.push(kept_rev[ri])
        ri -= 1
      blk.insts = fwd
      bi -= 1
  nil

# ---- Pass 7: Function Inlining (Mandatory `alwaysinline` + Cost-Modeled `-finline`) ----

-> wire_count_func_insts(wf)
  tot = 0
  bi = 0
  while bi < wf.blocks.size
    tot += wf.blocks[bi].insts.size
    bi += 1
  tot

-> wire_estimate_inline_cost(callee, call_ins, c_i64, c_f64)
  cost = 0
  bi = 0
  while bi < callee.blocks.size
    blk = callee.blocks[bi]
    cost += 2 if bi > 0
    ii = 0
    while ii < blk.insts.size
      op = blk.insts[ii].op
      if op == :typed_array_get_inline || op == :typed_array_set_inline
        cost += 2
      elsif op == :call_direct_i64 || op == :call_c_f64
        cost += 5
      elsif op != :br && op != :ret_i64 && op != :ret_f64 && op != :ret_void
        cost += 1
      ii += 1
    bi += 1
  if call_ins.args != nil && call_ins.args.size > 0
    all_const = true
    ai = 0
    while ai < call_ins.args.size
      av = call_ins.args[ai]
      if c_i64[av] != nil || c_f64[av] != nil
        cost -= 6
      else
        all_const = false
      ai += 1
    cost -= 10 if all_const
  cost < 0 ? 0 : cost

-> wire_remap_cloned_vr(vmap, vr)
  return vr if vr < 0
  mv = vmap[vr]
  mv != nil ? mv : vr

-> wire_clone_inst_for_inline(ins, vmap, slot_base, blk_base)
  cp = ins.clone()
  cp.dst = wire_remap_cloned_vr(vmap, cp.dst) if cp.dst >= 0
  cp.a = wire_remap_cloned_vr(vmap, cp.a) if cp.a >= 0
  cp.b = wire_remap_cloned_vr(vmap, cp.b) if cp.b >= 0
  cp.c = wire_remap_cloned_vr(vmap, cp.c) if cp.c >= 0
  if cp.args != nil
    ai = 0
    while ai < cp.args.size
      cp.args[ai] = wire_remap_cloned_vr(vmap, cp.args[ai])
      ai += 1
  if cp.op == :load_i64 || cp.op == :store_i64 || cp.op == :load_double || cp.op == :store_double
    cp.imm = cp.imm + slot_base
  if cp.op == :br
    cp.t_true = cp.t_true + blk_base
  elsif cp.op == :cond_br
    cp.t_true = cp.t_true + blk_base
    cp.t_false = cp.t_false + blk_base
  cp

-> wire_pass_inline(wf, wmod, opt_cfg, inline_only_always = false)
  return nil if wf == nil || wmod == nil
  allow_always = opt_cfg == nil || opt_cfg.pass_enabled?("always-inline")
  allow_heur = !inline_only_always && opt_cfg != nil && opt_cfg.pass_enabled?("inline")
  return nil if !allow_always && !allow_heur

  thresh = opt_cfg != nil ? opt_cfg.inline_threshold() : 65
  uid = 0
  round = 0
  changed = true
  while changed && round < 4
    changed = false
    round += 1
    maps = wire_build_def_maps(wf)
    c_i64 = maps[1]; c_f64 = maps[2]
    total_caller_insts = wire_count_func_insts(wf)

    bi = 0
    while bi < wf.blocks.size
      blk = wf.blocks[bi]
      ii = 0
      while ii < blk.insts.size
        ins = blk.insts[ii]
        if (ins.op == :call_direct_i64 || ins.op == :call_c_f64) && ins.sym != nil && ins.sym != wf.name
          callee = wmod.find_func(ins.sym)
          nargs = ins.args != nil ? ins.args.size : 0
          if callee != nil && callee.inline_hint != :never && callee.blocks.size > 0 && nargs == callee.params.size
            do_inl = false
            if callee.inline_hint == :always && allow_always
              do_inl = true
            elsif allow_heur && total_caller_insts < 1200
              est = wire_estimate_inline_cost(callee, ins, c_i64, c_f64)
              eff_thresh = thresh
              if ins.args != nil && ins.args.size > 0
                all_c = true
                ci = 0
                while ci < ins.args.size
                  all_c = false if c_i64[ins.args[ci]] == nil && c_f64[ins.args[ci]] == nil
                  ci += 1
                eff_thresh = thresh * 2 if all_c
              do_inl = (est <= eff_thresh)

            if do_inl
              uid += 1
              vmap = {}
              pi = 0
              while pi < callee.params.size
                vmap[pi] = ins.args[pi]
                pi += 1
              vi = callee.params.size
              while vi < callee.next_vreg
                vmap[vi] = wf.new_vreg(callee.vreg_types[vi])
                vi += 1
              slot_base = wf.slots
              si = 0
              while si < callee.slots
                wf.new_slot(callee.slot_types[si])
                si += 1

              # Fast path: single-block callee ending in `ret_*` -> splice directly in-place!
              cblk0 = callee.blocks[0]
              cterm = cblk0.insts.size > 0 ? cblk0.insts[cblk0.insts.size - 1] : nil
              if callee.blocks.size == 1 && cterm != nil && (cterm.op == :ret_i64 || cterm.op == :ret_f64 || cterm.op == :ret_void)
                # If returning a newly allocated callee vreg and call has `ins.dst >= 0`, map directly to `ins.dst`!
                direct_dst = false
                if ins.dst >= 0 && cterm.a >= callee.params.size
                  vmap[cterm.a] = ins.dst
                  direct_dst = true
                spliced = []
                ki = 0
                while ki < ii
                  spliced.push(blk.insts[ki])
                  ki += 1
                ci = 0
                while ci < cblk0.insts.size - 1
                  spliced.push(wire_clone_inst_for_inline(cblk0.insts[ci], vmap, slot_base, 0))
                  ci += 1
                if ins.dst >= 0 && !direct_dst && cterm.a >= 0
                  rv = wire_remap_cloned_vr(vmap, cterm.a)
                  if ins.ty == :f64
                    z_vr = wf.new_vreg(:f64)
                    zi = WireInst.new(:const_f64, z_vr); zi.fimm = ~0.0; zi.ty = :f64
                    spliced.push(zi)
                    mv = WireInst.new(:fadd_f64, ins.dst, rv, z_vr); mv.ty = :f64
                    spliced.push(mv)
                  else
                    z_vr = wf.new_vreg(:i64)
                    zi = WireInst.new(:const_i64, z_vr); zi.imm = 0
                    spliced.push(zi)
                    mv = WireInst.new(:add_i64, ins.dst, rv, z_vr)
                    spliced.push(mv)
                ki = ii + 1
                while ki < blk.insts.size
                  spliced.push(blk.insts[ki])
                  ki += 1
                blk.insts = spliced
                total_caller_insts += cblk0.insts.size
                changed = true
                # Re-scan from `ii` in case the inlined body itself contained nested calls!
                next
              else
                # Multi-block callee: split `blk` into `pre -> cloned_blocks -> cont_blk`
                ret_slot = ins.dst >= 0 ? wf.new_slot(ins.ty) : -1
                blk_base = wf.blocks.size
                cbi = 0
                while cbi < callee.blocks.size
                  wf.new_block(wf.name + "_inl" + uid.to_s() + "_b" + cbi.to_s())
                  cbi += 1
                cont_blk = wf.new_block(wf.name + "_inl" + uid.to_s() + "_cont")

                # Populate continuation block with instructions after the call
                ki = ii + 1
                while ki < blk.insts.size
                  cont_blk.insts.push(blk.insts[ki])
                  ki += 1
                if ins.dst >= 0
                  ld_op = ins.ty == :f64 ? :load_double : :load_i64
                  ld_i = WireInst.new(ld_op, ins.dst)
                  ld_i.imm = ret_slot
                  ld_i.ty = ins.ty
                  new_cont = [ld_i]
                  ci = 0
                  while ci < cont_blk.insts.size
                    new_cont.push(cont_blk.insts[ci])
                    ci += 1
                  cont_blk.insts = new_cont

                # Truncate `blk` before call and jump to cloned entry `blk_base`
                pre_insts = []
                ki = 0
                while ki < ii
                  pre_insts.push(blk.insts[ki])
                  ki += 1
                br_entry = WireInst.new(:br)
                br_entry.t_true = blk_base
                pre_insts.push(br_entry)
                blk.insts = pre_insts

                # Clone callee blocks and convert `ret_*` into slot store + branch to `cont_blk`
                cbi = 0
                while cbi < callee.blocks.size
                  src_b = callee.blocks[cbi]
                  dst_b = wf.blocks[blk_base + cbi]
                  cii = 0
                  while cii < src_b.insts.size
                    sins = src_b.insts[cii]
                    if sins.op == :ret_i64 || sins.op == :ret_f64 || sins.op == :ret_void
                      if ret_slot >= 0 && sins.a >= 0
                        st_op = ins.ty == :f64 ? :store_double : :store_i64
                        st_i = WireInst.new(st_op, -1, wire_remap_cloned_vr(vmap, sins.a))
                        st_i.imm = ret_slot
                        st_i.ty = ins.ty
                        dst_b.insts.push(st_i)
                      br_c = WireInst.new(:br)
                      br_c.t_true = cont_blk.id
                      dst_b.insts.push(br_c)
                    else
                      dst_b.insts.push(wire_clone_inst_for_inline(sins, vmap, slot_base, blk_base))
                    cii += 1
                  cbi += 1

                total_caller_insts += wire_count_func_insts(callee)
                changed = true
                break
        ii += 1
      bi += 1
  nil

# ---- Pass 8: Strength Reduction (Shifts & Granlund-Montgomery Constant Division) ----

-> wire_is_pow2_pos?(v)
  v > 0 && (v & (v - 1)) == 0

-> wire_ctz_pow2(v)
  sh = 0
  x = v
  while x > 1
    x = x >> 1
    sh += 1
  sh

-> wire_pass_strength_reduce(wf, opt_cfg)
  return nil if wf == nil
  do_magic_div = opt_cfg == nil || opt_cfg.opt_level >= 2
  maps = wire_build_def_maps(wf)
  c_i64 = maps[1]
  entry = wf.blocks[0]

  bi = 0
  while bi < wf.blocks.size
    blk = wf.blocks[bi]
    rebuilt = []
    ii = 0
    while ii < blk.insts.size
      ins = blk.insts[ii]
      op = ins.op
      ca = ins.a >= 0 ? c_i64[ins.a] : nil
      cb = ins.b >= 0 ? c_i64[ins.b] : nil
      replaced = false

      if op == :mul_i64
        if cb != nil && cb > 1 && wire_is_pow2_pos?(cb)
          sh_vr = wf.new_vreg(:i64)
          ci = WireInst.new(:const_i64, sh_vr); ci.imm = wire_ctz_pow2(cb)
          rebuilt.push(ci)
          si = WireInst.new(:shl_i64, ins.dst, ins.a, sh_vr)
          rebuilt.push(si)
          replaced = true
        elsif ca != nil && ca > 1 && wire_is_pow2_pos?(ca)
          sh_vr = wf.new_vreg(:i64)
          ci = WireInst.new(:const_i64, sh_vr); ci.imm = wire_ctz_pow2(ca)
          rebuilt.push(ci)
          si = WireInst.new(:shl_i64, ins.dst, ins.b, sh_vr)
          rebuilt.push(si)
          replaced = true
      elsif (op == :udiv_i64 || op == :urem_i64) && cb != nil && cb != 0
        is_rem = (op == :urem_i64)
        if cb == 1
          if is_rem
            zi = WireInst.new(:const_i64, ins.dst); zi.imm = 0
            rebuilt.push(zi)
          else
            z_vr = wf.new_vreg(:i64)
            zi = WireInst.new(:const_i64, z_vr); zi.imm = 0
            rebuilt.push(zi)
            rebuilt.push(WireInst.new(:add_i64, ins.dst, ins.a, z_vr))
          replaced = true
        elsif cb > 1 && wire_is_pow2_pos?(cb)
          if is_rem
            m_vr = wf.new_vreg(:i64)
            mi = WireInst.new(:const_i64, m_vr); mi.imm = cb - 1
            rebuilt.push(mi)
            rebuilt.push(WireInst.new(:and_i64, ins.dst, ins.a, m_vr))
          else
            sh_vr = wf.new_vreg(:i64)
            ci = WireInst.new(:const_i64, sh_vr); ci.imm = wire_ctz_pow2(cb)
            rebuilt.push(ci)
            rebuilt.push(WireInst.new(:lshr_i64, ins.dst, ins.a, sh_vr))
          replaced = true
        elsif do_magic_div
          mg = cinder_udiv_magic_u64(cb)
          if mg != nil
            q_dst = is_rem ? wf.new_vreg(:i64) : ins.dst
            if mg[0] == :shr
              sh_vr = wf.new_vreg(:i64)
              ci = WireInst.new(:const_i64, sh_vr); ci.imm = mg[2]
              rebuilt.push(ci)
              rebuilt.push(WireInst.new(:lshr_i64, q_dst, ins.a, sh_vr))
            elsif mg[0] == :mulhi_shr
              m_vr = wf.new_vreg(:i64)
              mi = WireInst.new(:const_i64, m_vr); mi.imm = mg[1]
              rebuilt.push(mi)
              if mg[2] == 0
                rebuilt.push(WireInst.new(:mulhi_u64, q_dst, ins.a, m_vr))
              else
                mh_vr = wf.new_vreg(:i64)
                rebuilt.push(WireInst.new(:mulhi_u64, mh_vr, ins.a, m_vr))
                sh_vr = wf.new_vreg(:i64)
                ci = WireInst.new(:const_i64, sh_vr); ci.imm = mg[2]
                rebuilt.push(ci)
                rebuilt.push(WireInst.new(:lshr_i64, q_dst, mh_vr, sh_vr))
            else
              # `:mulhi_add_shr`: `t1 = mulhi(x, m); q = (t1 + ((x - t1) >>u 1)) >>u sh2`
              m_vr = wf.new_vreg(:i64)
              mi = WireInst.new(:const_i64, m_vr); mi.imm = mg[1]
              rebuilt.push(mi)
              t1_vr = wf.new_vreg(:i64)
              rebuilt.push(WireInst.new(:mulhi_u64, t1_vr, ins.a, m_vr))
              d_vr = wf.new_vreg(:i64)
              rebuilt.push(WireInst.new(:sub_i64, d_vr, ins.a, t1_vr))
              one_vr = wf.new_vreg(:i64)
              oi = WireInst.new(:const_i64, one_vr); oi.imm = 1
              rebuilt.push(oi)
              h_vr = wf.new_vreg(:i64)
              rebuilt.push(WireInst.new(:lshr_i64, h_vr, d_vr, one_vr))
              if mg[3] == 0
                rebuilt.push(WireInst.new(:add_i64, q_dst, t1_vr, h_vr))
              else
                s_vr = wf.new_vreg(:i64)
                rebuilt.push(WireInst.new(:add_i64, s_vr, t1_vr, h_vr))
                sh2_vr = wf.new_vreg(:i64)
                s2i = WireInst.new(:const_i64, sh2_vr); s2i.imm = mg[3]
                rebuilt.push(s2i)
                rebuilt.push(WireInst.new(:lshr_i64, q_dst, s_vr, sh2_vr))
            if is_rem
              p_vr = wf.new_vreg(:i64)
              rebuilt.push(WireInst.new(:mul_i64, p_vr, q_dst, ins.b))
              rebuilt.push(WireInst.new(:sub_i64, ins.dst, ins.a, p_vr))
            replaced = true

      rebuilt.push(ins) if !replaced
      ii += 1
    blk.insts = rebuilt
    bi += 1
  nil

# ---- Pass 9: Jump Threading & Constant Branch Simplification ----

-> wire_pass_jump_threading(wf)
  return nil if wf == nil || wf.blocks.size <= 1
  maps = wire_build_def_maps(wf)
  c_i64 = maps[1]

  # 1. Fold constant `cond_br` and `t_true == t_false` into `:br`
  bi = 0
  while bi < wf.blocks.size
    blk = wf.blocks[bi]
    if blk.insts.size > 0
      term = blk.insts[blk.insts.size - 1]
      if term.op == :cond_br
        cv = term.a >= 0 ? c_i64[term.a] : nil
        if cv != nil
          tgt = cv != 0 ? term.t_true : term.t_false
          nb = WireInst.new(:br); nb.t_true = tgt
          blk.insts[blk.insts.size - 1] = nb
        elsif term.t_true == term.t_false
          nb = WireInst.new(:br); nb.t_true = term.t_true
          blk.insts[blk.insts.size - 1] = nb
    bi += 1

  # 2. Thread branches through empty jump-only trampoline blocks (`insts == [br X]`)
  # Note: preserve counted-loop headers (`bi > 0`) if they jump back to themselves!
  tramp = Array.new(wf.blocks.size, -1)
  bi = 1
  while bi < wf.blocks.size
    blk = wf.blocks[bi]
    if blk.insts.size == 1 && blk.insts[0].op == :br && blk.insts[0].t_true != bi
      tramp[bi] = blk.insts[0].t_true
    bi += 1

  bi = 0
  while bi < wf.blocks.size
    blk = wf.blocks[bi]
    if blk.insts.size > 0
      term = blk.insts[blk.insts.size - 1]
      if term.op == :br
        cur = term.t_true
        steps = 0
        while cur >= 0 && tramp[cur] >= 0 && steps < 8
          cur = tramp[cur]
          steps += 1
        term.t_true = cur
      elsif term.op == :cond_br
        cur_t = term.t_true
        steps = 0
        while cur_t >= 0 && tramp[cur_t] >= 0 && steps < 8
          cur_t = tramp[cur_t]
          steps += 1
        term.t_true = cur_t
        cur_f = term.t_false
        steps = 0
        while cur_f >= 0 && tramp[cur_f] >= 0 && steps < 8
          cur_f = tramp[cur_f]
          steps += 1
        term.t_false = cur_f
    bi += 1
  nil

# ---- Pass 10: Fast-Math Contraction (`fmadd_f64` / `fmsub_f64`) & FP Identities (`--fast`) ----

-> wire_pass_fast_math(wf)
  return nil if wf == nil
  maps = wire_build_def_maps(wf)
  defs = maps[0]; c_f64 = maps[2]
  uses = wire_count_vreg_uses(wf)
  remap = {}

  bi = 0
  while bi < wf.blocks.size
    blk = wf.blocks[bi]
    rebuilt = []
    ii = 0
    while ii < blk.insts.size
      ins = blk.insts[ii]
      ins.a = wire_resolve_remap(remap, ins.a) if ins.a >= 0 && remap[ins.a] != nil
      ins.b = wire_resolve_remap(remap, ins.b) if ins.b >= 0 && remap[ins.b] != nil
      ins.c = wire_resolve_remap(remap, ins.c) if ins.c >= 0 && remap[ins.c] != nil
      op = ins.op
      fa = ins.a >= 0 ? c_f64[ins.a] : nil
      fb = ins.b >= 0 ? c_f64[ins.b] : nil
      handled = false

      if op == :fadd_f64
        if fb == ~0.0
          remap[ins.dst] = ins.a; handled = true
        elsif fa == ~0.0
          remap[ins.dst] = ins.b; handled = true
        else
          da = defs[ins.a]; db = defs[ins.b]
          if da != nil && da.op == :fmul_f64 && uses[ins.a] == 1
            fma = WireInst.new(:fmadd_f64, ins.dst, da.a, da.b, ins.b); fma.ty = :f64
            rebuilt.push(fma); handled = true
          elsif db != nil && db.op == :fmul_f64 && uses[ins.b] == 1
            fma = WireInst.new(:fmadd_f64, ins.dst, db.a, db.b, ins.a); fma.ty = :f64
            rebuilt.push(fma); handled = true
      elsif op == :fsub_f64
        if fb == ~0.0
          remap[ins.dst] = ins.a; handled = true
        else
          db = defs[ins.b]
          if db != nil && db.op == :fmul_f64 && uses[ins.b] == 1
            fms = WireInst.new(:fmsub_f64, ins.dst, db.a, db.b, ins.a); fms.ty = :f64
            rebuilt.push(fms); handled = true
      elsif op == :fmul_f64
        if fb == ~1.0
          remap[ins.dst] = ins.a; handled = true
        elsif fa == ~1.0
          remap[ins.dst] = ins.b; handled = true
      elsif op == :fdiv_f64 && fb != nil && fb != ~0.0
        rec = ~1.0 / fb
        if rec == rec && rec != (~1.0 / ~0.0) && rec != (~-1.0 / ~0.0)
          r_vr = wf.new_vreg(:f64)
          ri = WireInst.new(:const_f64, r_vr); ri.fimm = rec; ri.ty = :f64
          rebuilt.push(ri)
          mi = WireInst.new(:fmul_f64, ins.dst, ins.a, r_vr); mi.ty = :f64
          rebuilt.push(mi)
          handled = true

      rebuilt.push(ins) if !handled
      ii += 1
    blk.insts = rebuilt
    bi += 1

  wire_apply_vreg_remap(wf, remap)
  nil

# ---- Top-Level Configurable Pass Pipeline (`-O0` .. `-O3`, `--fast`, `-f<pass>` / `-fno-<pass>`) ----

-> wire_run_pass_timed(wf, opt_cfg, pass_name, fn_cb)
  if opt_cfg != nil && opt_cfg.print_passes
    b0 = wire_count_func_insts(wf)
    t0 = ccall_nobox("__w_clock_ns_raw") ## i64
    fn_cb.call()
    t1 = ccall_nobox("__w_clock_ns_raw") ## i64
    b1 = wire_count_func_insts(wf)
    opt_cfg.record_stat(pass_name, b0, b1, (t1 - t0) / 1000)
  else
    fn_cb.call()
  nil

-> wire_run_passes(wf, opt_cfg, wmod = nil)
  return nil if wf == nil || wf.blocks.size == 0
  cfg = opt_cfg != nil ? opt_cfg : CinderOptConfig.new(2)

  # 1. Function Inlining (`alwaysinline` at all levels; heuristic `-finline` at `-O1+`)
  if wmod != nil && (cfg.pass_enabled?("always-inline") || cfg.pass_enabled?("inline"))
    only_always = !cfg.pass_enabled?("inline")
    wire_run_pass_timed(wf, cfg, only_always ? "always-inline" : "inline", ->() wire_pass_inline(wf, wmod, cfg, only_always))

  return nil if cfg.opt_level <= 0 && cfg.explicit_passes == nil && cfg.overrides.size == 0 && !cfg.fast_math

  if cfg.pass_enabled?("const-fold")
    wire_run_pass_timed(wf, cfg, "const-fold", ->() wire_pass_const_fold_and_hoist(wf))
  if cfg.pass_enabled?("sroa")
    wire_run_pass_timed(wf, cfg, "sroa", ->() wire_pass_slot_sroa_and_forward(wf))
  if cfg.pass_enabled?("licm") || cfg.pass_enabled?("gvn")
    wire_run_pass_timed(wf, cfg, "licm+gvn", ->() wire_pass_licm_and_cse(wf))
  if cfg.pass_enabled?("strength-reduce")
    wire_run_pass_timed(wf, cfg, "strength-reduce", ->() wire_pass_strength_reduce(wf, cfg))
  if cfg.fast_math
    wire_run_pass_timed(wf, cfg, "fast-math", ->() wire_pass_fast_math(wf))
  if cfg.pass_enabled?("carry-chains")
    wire_run_pass_timed(wf, cfg, "carry-canonicalize", ->() wire_pass_carry_canonicalize(wf))
  if cfg.pass_enabled?("const-fold")
    wire_run_pass_timed(wf, cfg, "const-fold-2", ->() wire_pass_const_fold_and_hoist(wf))
  if cfg.pass_enabled?("jump-threading")
    wire_run_pass_timed(wf, cfg, "jump-threading", ->() wire_pass_jump_threading(wf))
  if cfg.pass_enabled?("carry-chains")
    wire_run_pass_timed(wf, cfg, "carry-chains", ->() wire_pass_carry_chains(wf))
  if cfg.pass_enabled?("dce")
    wire_run_pass_timed(wf, cfg, "dce", ->() wire_pass_dce(wf))
  if cfg.opt_level >= 3 && cfg.pass_enabled?("gvn")
    wire_run_pass_timed(wf, cfg, "O3-licm+gvn", ->() wire_pass_licm_and_cse(wf))
    wire_run_pass_timed(wf, cfg, "O3-dce", ->() wire_pass_dce(wf))
  nil

-> wire_run_tier2_passes(wf)
  wire_run_passes(wf, CinderOptConfig.new(2), nil)

# Backwards-compatible entry point
-> wire_opt_func(wf)
  wire_run_tier2_passes(wf)

# ---- ARM64 Register & Slot Accessors for Loop Kernels ----

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

-> wire_eval_inv_gpr_a64(comp, vr, defs, c_i64, scratch)
  if c_i64[vr] != nil
    comp.a.mov_imm64(scratch, c_i64[vr])
    return scratch
  d = defs[vr]
  if d != nil && d.op == :load_i64
    return wire_get_slot_gpr(comp, d.imm, scratch)
  wire_get_gpr(comp, vr, scratch)

# Compute effective limb pointer `dst_r = base_ptr + (r_i + off_vr) * 8` on ARM64
-> wire_emit_limb_ptr_a64(comp, dst_r, base_vr, r_i, off_vr, defs, c_i64, scratch)
  r_base = wire_get_gpr(comp, base_vr, scratch)
  comp.a.add_r(dst_r, r_base, r_i, 3)
  if off_vr >= 0
    r_off = wire_eval_inv_gpr_a64(comp, off_vr, defs, c_i64, scratch)
    comp.a.add_r(dst_r, dst_r, r_off, 3)
  nil

# ---- ARM64 Hardware Flag-Threaded Multi-Limb Carry/Borrow/Mul Loop Emitter ----

-> wire_try_emit_carry_loop_a64(comp, cond_id, defs, c_i64)
  cl = wire_match_carry_loop(comp.wf, cond_id, defs, c_i64)
  return nil if cl == nil
  kind = cl[0]; idx_sl = cl[1]; lim_vr = cl[2]; end_id = cl[3]; skip = cl[4]
  c_sl = cl[5]; p_out = cl[6]; off_out = cl[7]; p_a = cl[8]; off_a = cl[9]
  p_b = cl[10]; off_b = cl[11]; w_vr = cl[12]

  a = comp.a
  l_end = comp.blk_labels[end_id]
  r_i = wire_get_slot_gpr(comp, idx_sl, R_X8)
  r_n = wire_get_gpr(comp, lim_vr, R_X17)
  a.cmp_r(r_i, r_n)
  a.b_cond(CC_GE, l_end)

  # R_X9 = rem = n - i (> 0)
  a.sub_r(R_X9, r_n, r_i)
  # R_X13 = pA_eff, R_X15 = pOut_eff
  wire_emit_limb_ptr_a64(comp, R_X13, p_a, r_i, off_a, defs, c_i64, R_X10)
  wire_emit_limb_ptr_a64(comp, R_X15, p_out, r_i, off_out, defs, c_i64, R_X10)

  if kind == :add_limbs || kind == :sub_limbs
    is_add = kind == :add_limbs
    wire_emit_limb_ptr_a64(comp, R_X14, p_b, r_i, off_b, defs, c_i64, R_X10)
    r_cin = wire_get_slot_gpr(comp, c_sl, R_X12)
    # R_X8 = quads = rem >> 2; R_X9 = tail = rem & 3 (computed BEFORE seeding NZCV.C!)
    a.lsr_xi(R_X8, R_X9, 2)
    a.and_xi(R_X9, R_X9, 3)
    # Seed hardware carry/borrow flag in NZCV.C:
    #   add: `cmp r_cin, #1` sets C=1 iff r_cin >= 1, C=0 iff r_cin == 0
    #   sub: `subs xzr, xzr, r_cin` sets C=1 iff r_cin == 0 (no borrow), C=0 iff r_cin != 0 (borrow)
    if is_add
      a.cmp_i(r_cin, 1)
    else
      a.subs_r(R_XZR, R_XZR, r_cin)

    l_quad = a.new_label; l_tail = a.new_label; l_sc = a.new_label; l_done = a.new_label
    a.cbz_x(R_X8, l_tail)
    a.bind(l_quad)
    a.ldp_post(R_X10, R_X11, R_X13, 16)
    a.ldp_post(R_X16, R_X17, R_X14, 16)
    if is_add
      a.adcs_x(R_X12, R_X10, R_X16)
      a.adcs_x(R_X16, R_X11, R_X17)
    else
      a.sbcs_x(R_X12, R_X10, R_X16)
      a.sbcs_x(R_X16, R_X11, R_X17)
    a.stp_post(R_X12, R_X16, R_X15, 16)
    a.ldp_post(R_X10, R_X11, R_X13, 16)
    a.ldp_post(R_X16, R_X17, R_X14, 16)
    if is_add
      a.adcs_x(R_X12, R_X10, R_X16)
      a.adcs_x(R_X16, R_X11, R_X17)
    else
      a.sbcs_x(R_X12, R_X10, R_X16)
      a.sbcs_x(R_X16, R_X11, R_X17)
    a.stp_post(R_X12, R_X16, R_X15, 16)
    a.sub_i(R_X8, R_X8, 1)    # Flag-neutral! NZCV.C preserved across loop back-edge!
    a.cbnz_x(R_X8, l_quad)    # Flag-neutral!

    a.bind(l_tail)
    a.cbz_x(R_X9, l_done)
    a.bind(l_sc)
    a.ldr_x_post(R_X10, R_X13, 8)
    a.ldr_x_post(R_X11, R_X14, 8)
    if is_add
      a.adcs_x(R_X12, R_X10, R_X11)
    else
      a.sbcs_x(R_X12, R_X10, R_X11)
    a.str_x_post(R_X12, R_X15, 8)
    a.sub_i(R_X9, R_X9, 1)
    a.cbnz_x(R_X9, l_sc)

    a.bind(l_done)
    a.cset(R_X12, is_add ? CC_HS : CC_LO)
    wire_set_slot_gpr(comp, c_sl, R_X12)
    r_n2 = wire_get_gpr(comp, lim_vr, R_X17)
    wire_set_slot_gpr(comp, idx_sl, r_n2)
    a.b(l_end)
    return skip

  # `:mul1_limbs` & `:addmul1_limbs` (2x-unrolled `ldp`/`stp` + `mul`/`umulh` + `adds`/`cinc`)
  is_addmul = kind == :addmul1_limbs
  r_w_src = wire_eval_inv_gpr_a64(comp, w_vr, defs, c_i64, R_X14)
  a.mov_r(R_X14, r_w_src) if r_w_src != R_X14
  r_c_src = wire_get_slot_gpr(comp, c_sl, R_X17)
  a.mov_r(R_X17, r_c_src) if r_c_src != R_X17

  a.lsr_xi(R_X8, R_X9, 1)
  a.and_xi(R_X9, R_X9, 1)
  l_pair = a.new_label; l_tail = a.new_label; l_done = a.new_label
  a.cbz_x(R_X8, l_tail)
  a.bind(l_pair)
  a.ldp_post(R_X10, R_X11, R_X13, 16)
  if is_addmul
    a.ldp_x(R_X12, R_X16, R_X15, 0)
    # Limb 0
    a.adds_r(R_X12, R_X12, R_X17)
    a.umulh_x(R_X17, R_X10, R_X14)
    a.cinc_x(R_X17, R_X17, CC_HS)
    a.mul_x(R_X10, R_X10, R_X14)
    a.adds_r(R_X12, R_X12, R_X10)
    a.cinc_x(R_X17, R_X17, CC_HS)
    # Limb 1
    a.adds_r(R_X16, R_X16, R_X17)
    a.umulh_x(R_X17, R_X11, R_X14)
    a.cinc_x(R_X17, R_X17, CC_HS)
    a.mul_x(R_X11, R_X11, R_X14)
    a.adds_r(R_X16, R_X16, R_X11)
    a.cinc_x(R_X17, R_X17, CC_HS)
    a.stp_post(R_X12, R_X16, R_X15, 16)
  else
    # `:mul1_limbs` pair
    a.mul_x(R_X12, R_X10, R_X14)
    a.umulh_x(R_X10, R_X10, R_X14)
    a.adds_r(R_X12, R_X12, R_X17)
    a.cinc_x(R_X17, R_X10, CC_HS)
    a.mul_x(R_X16, R_X11, R_X14)
    a.umulh_x(R_X11, R_X11, R_X14)
    a.adds_r(R_X16, R_X16, R_X17)
    a.cinc_x(R_X17, R_X11, CC_HS)
    a.stp_post(R_X12, R_X16, R_X15, 16)
  a.sub_i(R_X8, R_X8, 1)
  a.cbnz_x(R_X8, l_pair)

  a.bind(l_tail)
  a.cbz_x(R_X9, l_done)
  a.ldr_x(R_X10, R_X13, 0)
  if is_addmul
    a.ldr_x(R_X12, R_X15, 0)
    a.adds_r(R_X12, R_X12, R_X17)
    a.umulh_x(R_X17, R_X10, R_X14)
    a.cinc_x(R_X17, R_X17, CC_HS)
    a.mul_x(R_X10, R_X10, R_X14)
    a.adds_r(R_X12, R_X12, R_X10)
    a.cinc_x(R_X17, R_X17, CC_HS)
    a.str_x(R_X12, R_X15, 0)
  else
    a.mul_x(R_X12, R_X10, R_X14)
    a.umulh_x(R_X10, R_X10, R_X14)
    a.adds_r(R_X12, R_X12, R_X17)
    a.cinc_x(R_X17, R_X10, CC_HS)
    a.str_x(R_X12, R_X15, 0)

  a.bind(l_done)
  wire_set_slot_gpr(comp, c_sl, R_X17)
  r_n2 = wire_get_gpr(comp, lim_vr, R_X16)
  wire_set_slot_gpr(comp, idx_sl, r_n2)
  a.b(l_end)
  skip

# ---- ARM64 NEON Auto-Vectorizer & Loop Microkernels ----

-> wire_try_emit_simd_loop(comp, cond_id, defs, c_i64, c_f64, opt_cfg = nil)
  wf = comp.wf
  do_carry = opt_cfg == nil || (opt_cfg.pass_enabled?("carry-chains") && opt_cfg.opt_level >= 2)
  do_simd  = opt_cfg == nil || opt_cfg.pass_enabled?("simd")
  strict_fp = opt_cfg != nil && opt_cfg.strict_math
  allow_reassoc = opt_cfg != nil && opt_cfg.fast_math && !strict_fp

  if do_carry
    carry_skip = wire_try_emit_carry_loop_a64(comp, cond_id, defs, c_i64)
    return carry_skip if carry_skip != nil

  return nil if !do_simd

  if !strict_fp
    mm_skip = wire_try_emit_matmul_f32(comp, cond_id, defs, c_i64, c_f64)
    return mm_skip if mm_skip != nil

  lp = wire_match_counted_loop(wf, cond_id, c_i64)
  return nil if lp == nil
  body = lp[0]
  idx_sl = lp[1]
  lim_vr = lp[2]
  end_id = lp[3]
  skip = lp[4]
  a = comp.a
  l_end = comp.blk_labels[end_id]

  # Pattern 1: Float32 Dot Product / Sum-of-Squares
  #   - Default / `--strict-math`: 4x-unrolled ORDERED binary64 accumulation (100% IEEE-754 bit-exact with JS!)
  #   - Explicit `--fast` / `-ffast-math` (without `--strict-math`): 4-way reassociated NEON accumulators
  #     (also matches `:fmadd_f64` fused by `wire_pass_fast_math` when `--fast` is enabled!)
  if body.size >= 3 && body.size <= 9
    st = body[body.size - 1]
    if st.op == :store_double
      acc_sl = st.imm
      fadd_ins = defs[st.a]
      ga = nil
      gb = nil
      if fadd_ins != nil && fadd_ins.op == :fadd_f64 && wire_is_slot_load?(fadd_ins.a, acc_sl, defs)
        fmul_ins = defs[fadd_ins.b]
        if fmul_ins != nil && fmul_ins.op == :fmul_f64
          ga = defs[fmul_ins.a]
          gb = defs[fmul_ins.b]
      elsif fadd_ins != nil && fadd_ins.op == :fmadd_f64 && wire_is_slot_load?(fadd_ins.c, acc_sl, defs)
        ga = defs[fadd_ins.a]
        gb = defs[fadd_ins.b]
      if ga != nil && gb != nil && ga.op == :typed_array_get_inline && gb.op == :typed_array_get_inline && ga.ebits == -32 && gb.ebits == -32 && wire_is_slot_load?(ga.b, idx_sl, defs) && wire_is_slot_load?(gb.b, idx_sl, defs)
        if true
          if true
            pure = true
            bi = 0
            while bi < body.size - 1
              op = body[bi].op
              pure = false if op == :store_i64 || op == :store_double || op == :typed_array_set_inline
              bi += 1
            if pure
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
              a.sub_r(R_X9, r_n, r_i)
              a.add_r(R_X10, r_pa, r_i, 2)
              a.add_r(R_X11, r_pb, r_i, 2)
              if allow_reassoc
                a.cmp_i(R_X9, 8)
                a.b_cond(CC_LT, l_tail)
                a.movi_zero_16b(0); a.movi_zero_16b(1); a.movi_zero_16b(2); a.movi_zero_16b(3)
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
                a.fadd_2d(0, 0, 1); a.fadd_2d(2, 2, 3); a.fadd_2d(0, 0, 2)
                a.faddp_d(16, 0)
                a.fadd_d(d_acc, d_acc, 16)
              else
                # 4x unrolled ordered binary64 accumulation (preserves exact left-to-right IEEE-754 rounding!)
                a.cmp_i(R_X9, 4)
                a.b_cond(CC_LT, l_tail)
                a.bind(l_vec)
                a.ldr_s_post(16, R_X10, 4); a.ldr_s_post(17, R_X10, 4)
                a.ldr_s_post(18, R_X10, 4); a.ldr_s_post(19, R_X10, 4)
                a.ldr_s_post(20, R_X11, 4); a.ldr_s_post(21, R_X11, 4)
                a.ldr_s_post(22, R_X11, 4); a.ldr_s_post(23, R_X11, 4)
                a.fcvt_d_s(16, 16); a.fcvt_d_s(20, 20); a.fmul_d(16, 16, 20)
                a.fcvt_d_s(17, 17); a.fcvt_d_s(21, 21); a.fmul_d(17, 17, 21)
                a.fcvt_d_s(18, 18); a.fcvt_d_s(22, 22); a.fmul_d(18, 18, 22)
                a.fcvt_d_s(19, 19); a.fcvt_d_s(23, 23); a.fmul_d(19, 19, 23)
                a.fadd_d(d_acc, d_acc, 16)
                a.fadd_d(d_acc, d_acc, 17)
                a.fadd_d(d_acc, d_acc, 18)
                a.fadd_d(d_acc, d_acc, 19)
                a.sub_i(R_X9, R_X9, 4)
                a.cmp_i(R_X9, 4)
                a.b_cond(CC_GE, l_vec)
              a.bind(l_tail)
              l_fin = a.new_label
              a.cbz_x(R_X9, l_fin)
              a.bind(l_sc)
              a.ldr_s_post(16, R_X10, 4)
              a.ldr_s_post(17, R_X11, 4)
              a.fcvt_d_s(16, 16); a.fcvt_d_s(17, 17)
              a.fmul_d(16, 16, 17)
              a.fadd_d(d_acc, d_acc, 16)
              a.sub_i(R_X9, R_X9, 1)
              a.cbnz_x(R_X9, l_sc)
              a.bind(l_fin)
              wire_set_slot_fpr(comp, acc_sl, d_acc)
              wire_set_slot_gpr(comp, idx_sl, r_n)
              a.b(l_end)
              return skip

  # Pattern 2: Float32 SAXPY / Affine Map
  if body.size >= 4 && body.size <= 9
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
          if gx != nil && gx.op == :typed_array_get_inline && gx.ebits == -32 && wire_is_slot_load?(gx.b, idx_sl, defs)
            al_def = defs[alpha_vr]
            is_inv = alpha_vr < wf.params.size || (al_def != nil && (al_def.op == :const_f64 || al_def.op == :load_double))
            pure = is_inv
            bi = 0
            while bi < body.size - 1
              op = body[bi].op
              pure = false if op == :store_i64 || op == :store_double || op == :typed_array_set_inline
              bi += 1
            if pure
              r_i = wire_get_slot_gpr(comp, idx_sl, R_X8)
              r_n = wire_get_gpr(comp, lim_vr, R_X17)
              r_po = wire_get_gpr(comp, st.a, R_X13)
              r_px = wire_get_gpr(comp, gx.a, R_X14)
              r_py = wire_get_gpr(comp, gy.a, R_X15)
              d_al = al_def != nil && al_def.op == :load_double ? wire_get_slot_fpr(comp, al_def.imm, R_D6) : comp.read_f(alpha_vr, R_D6)
              l_tail = a.new_label
              l_vec = a.new_label
              l_sc = a.new_label
              l_fin = a.new_label
              a.cmp_r(r_i, r_n)
              a.b_cond(CC_GE, l_end)
              a.sub_r(R_X9, r_n, r_i)
              a.add_r(R_X10, r_px, r_i, 2)
              a.add_r(R_X11, r_py, r_i, 2)
              a.add_r(R_X12, r_po, r_i, 2)
              a.cmp_i(R_X9, 8)
              a.b_cond(CC_LT, l_tail)
              a.lsl_xi(R_X16, R_X9, 2)
              a.add_r(R_X17, R_X12, R_X16)
              l_ok1 = a.new_label
              a.cmp_r(R_X12, R_X10); a.b_cond(CC_EQ, l_ok1)
              a.cmp_r(R_X17, R_X10); a.b_cond(CC_LS, l_ok1)
              a.add_r(R_X8, R_X10, R_X16); a.cmp_r(R_X8, R_X12); a.b_cond(CC_HI, l_tail)
              a.bind(l_ok1)
              l_ok2 = a.new_label
              a.cmp_r(R_X12, R_X11); a.b_cond(CC_EQ, l_ok2)
              a.cmp_r(R_X17, R_X11); a.b_cond(CC_LS, l_ok2)
              a.add_r(R_X8, R_X11, R_X16); a.cmp_r(R_X8, R_X12); a.b_cond(CC_HI, l_tail)
              a.bind(l_ok2)
              a.dup_2d_elt0(0, d_al)
              a.bind(l_vec)
              a.ldp_q_post(4, 5, R_X10, 32)
              a.ldp_q_post(6, 7, R_X11, 32)
              a.fcvtl_2d_2s(16, 4); a.fcvtl_2d_2s(20, 6); a.fmul_2d(16, 16, 0); a.fadd_2d(16, 16, 20)
              a.fcvtl2_2d_4s(17, 4); a.fcvtl2_2d_4s(21, 6); a.fmul_2d(17, 17, 0); a.fadd_2d(17, 17, 21)
              a.fcvtn_2s_2d(24, 16); a.fcvtn2_4s_2d(24, 17)
              a.fcvtl_2d_2s(18, 5); a.fcvtl_2d_2s(22, 7); a.fmul_2d(18, 18, 0); a.fadd_2d(18, 18, 22)
              a.fcvtl2_2d_4s(19, 5); a.fcvtl2_2d_4s(23, 7); a.fmul_2d(19, 19, 0); a.fadd_2d(19, 19, 23)
              a.fcvtn_2s_2d(25, 18); a.fcvtn2_4s_2d(25, 19)
              a.stp_q_post(24, 25, R_X12, 32)
              a.sub_i(R_X9, R_X9, 8)
              a.cmp_i(R_X9, 8)
              a.b_cond(CC_GE, l_vec)
              a.bind(l_tail)
              a.cbz_x(R_X9, l_fin)
              a.bind(l_sc)
              a.ldr_s_post(16, R_X10, 4)
              a.ldr_s_post(17, R_X11, 4)
              a.fcvt_d_s(16, 16); a.fcvt_d_s(17, 17)
              a.fmul_d(16, 16, d_al); a.fadd_d(16, 16, 17)
              a.fcvt_s_d(16, 16)
              a.str_s_idx(16, R_X12, R_XZR)
              a.add_i(R_X12, R_X12, 4)
              a.sub_i(R_X9, R_X9, 1)
              a.cbnz_x(R_X9, l_sc)
              a.bind(l_fin)
              r_n2 = wire_get_gpr(comp, lim_vr, R_X17)
              wire_set_slot_gpr(comp, idx_sl, r_n2)
              a.b(l_end)
              return skip

  # Pattern 2b: Float64 Dot Product
  if body.size >= 4 && body.size <= 9
    st = body[body.size - 1]
    if st.op == :store_double
      acc_sl = st.imm
      fadd_ins = defs[st.a]
      if fadd_ins != nil && fadd_ins.op == :fadd_f64 && wire_is_slot_load?(fadd_ins.a, acc_sl, defs)
        fmul_ins = defs[fadd_ins.b]
        if fmul_ins != nil && fmul_ins.op == :fmul_f64
          ga = defs[fmul_ins.a]
          gb = defs[fmul_ins.b]
          if ga != nil && gb != nil && ga.op == :typed_array_get_inline && gb.op == :typed_array_get_inline && ga.ebits == -64 && gb.ebits == -64 && wire_is_slot_load?(ga.b, idx_sl, defs) && wire_is_slot_load?(gb.b, idx_sl, defs)
            pure = true
            bi = 0
            while bi < body.size - 1
              op = body[bi].op
              pure = false if op == :store_i64 || op == :store_double || op == :typed_array_set_inline
              bi += 1
            if pure
              r_i = wire_get_slot_gpr(comp, idx_sl, R_X8)
              r_n = wire_get_gpr(comp, lim_vr, R_X17)
              r_pa = wire_get_gpr(comp, ga.a, R_X14)
              r_pb = wire_get_gpr(comp, gb.a, R_X15)
              d_acc = wire_get_slot_fpr(comp, acc_sl, R_D6)
              l_sc = a.new_label
              l_fin = a.new_label
              a.cmp_r(r_i, r_n)
              a.b_cond(CC_GE, l_end)
              a.sub_r(R_X9, r_n, r_i)
              a.add_r(R_X10, r_pa, r_i, 3)
              a.add_r(R_X11, r_pb, r_i, 3)
              l_u4 = a.new_label
              l_tail = a.new_label
              a.cmp_i(R_X9, 4)
              a.b_cond(CC_LT, l_tail)
              a.bind(l_u4)
              a.ldp_d(16, 17, R_X10, 0); a.ldp_d(20, 21, R_X11, 0)
              a.ldp_d(18, 19, R_X10, 16); a.ldp_d(22, 23, R_X11, 16)
              a.add_i(R_X10, R_X10, 32); a.add_i(R_X11, R_X11, 32)
              a.fmul_d(16, 16, 20); a.fadd_d(d_acc, d_acc, 16)
              a.fmul_d(17, 17, 21); a.fadd_d(d_acc, d_acc, 17)
              a.fmul_d(18, 18, 22); a.fadd_d(d_acc, d_acc, 18)
              a.fmul_d(19, 19, 23); a.fadd_d(d_acc, d_acc, 19)
              a.sub_i(R_X9, R_X9, 4)
              a.cmp_i(R_X9, 4)
              a.b_cond(CC_GE, l_u4)
              a.bind(l_tail)
              a.cbz_x(R_X9, l_fin)
              a.bind(l_sc)
              a.ldr_d(16, R_X10, 0); a.ldr_d(17, R_X11, 0)
              a.add_i(R_X10, R_X10, 8); a.add_i(R_X11, R_X11, 8)
              a.fmul_d(16, 16, 17); a.fadd_d(d_acc, d_acc, 16)
              a.sub_i(R_X9, R_X9, 1)
              a.cbnz_x(R_X9, l_sc)
              a.bind(l_fin)
              wire_set_slot_fpr(comp, acc_sl, d_acc)
              wire_set_slot_gpr(comp, idx_sl, r_n)
              a.b(l_end)
              return skip

  # Pattern 3: Float16 ReLU + Scale
  if body.size >= 5 && body.size <= 12
    st_out = body[body.size - 1]
    if st_out.op == :typed_array_set_inline && st_out.ebits == -16 && wire_is_slot_load?(st_out.b, idx_sl, defs)
      sel = defs[st_out.c]
      if sel != nil && sel.op == :select_f64 && c_f64[sel.c] == ~0.0
        cmp_ins = defs[sel.a]
        if cmp_ins != nil && cmp_ins.op == :fcmp_f64 && cmp_ins.pred == :ogt && c_f64[cmp_ins.b] == ~0.0 && cmp_ins.a == sel.b
          v_def = defs[sel.b]
          v_sl = -1
          mul_i = v_def
          if v_def != nil && v_def.op == :load_double
            v_sl = v_def.imm
            bi = 0
            while bi < body.size - 1
              if body[bi].op == :store_double && body[bi].imm == v_sl
                mul_i = defs[body[bi].a]
              bi += 1
          if mul_i != nil && mul_i.op == :fmul_f64
            gi = defs[mul_i.a]
            sc_vr = mul_i.b
            if gi == nil || gi.op != :typed_array_get_inline
              gi = defs[mul_i.b]
              sc_vr = mul_i.a
            if gi != nil && gi.op == :typed_array_get_inline && gi.ebits == -16 && wire_is_slot_load?(gi.b, idx_sl, defs) && sc_vr < wf.params.size
              r_i = wire_get_slot_gpr(comp, idx_sl, R_X8)
              r_n = wire_get_gpr(comp, lim_vr, R_X17)
              r_po = wire_get_gpr(comp, st_out.a, R_X13)
              r_pi = wire_get_gpr(comp, gi.a, R_X14)
              d_sc = comp.read_f(sc_vr, R_D6)
              l_tail = a.new_label; l_vec = a.new_label; l_sc = a.new_label; l_fin = a.new_label
              a.cmp_r(r_i, r_n); a.b_cond(CC_GE, l_end)
              a.sub_r(R_X9, r_n, r_i)
              a.add_r(R_X10, r_pi, r_i, 1)
              a.add_r(R_X11, r_po, r_i, 1)
              a.cmp_i(R_X9, 8); a.b_cond(CC_LT, l_tail)
              a.lsl_xi(R_X15, R_X9, 1)
              a.add_r(R_X16, R_X11, R_X15)
              l_ok = a.new_label
              a.cmp_r(R_X11, R_X10); a.b_cond(CC_EQ, l_ok)
              a.cmp_r(R_X16, R_X10); a.b_cond(CC_LS, l_ok)
              a.add_r(R_X8, R_X10, R_X15); a.cmp_r(R_X8, R_X11); a.b_cond(CC_HI, l_tail)
              a.bind(l_ok)
              a.dup_2d_elt0(0, d_sc)
              a.movi_zero_16b(1)
              a.bind(l_vec)
              a.ldr_q_post(2, R_X10, 16)
              a.fcvtl_4s_4h(16, 2); a.fcvtl2_4s_8h(17, 2)
              a.fcvtl_2d_2s(20, 16); a.fcvtl2_2d_4s(21, 16)
              a.fcvtl_2d_2s(22, 17); a.fcvtl2_2d_4s(23, 17)
              a.fmul_2d(20, 20, 0); a.fmul_2d(21, 21, 0); a.fmul_2d(22, 22, 0); a.fmul_2d(23, 23, 0)
              a.fcmgt_2d(24, 20, 1); a.and_16b(20, 20, 24)
              a.fcmgt_2d(25, 21, 1); a.and_16b(21, 21, 25)
              a.fcmgt_2d(26, 22, 1); a.and_16b(22, 22, 26)
              a.fcmgt_2d(27, 23, 1); a.and_16b(23, 23, 27)
              a.fcvt_h_d(16, 20); a.umov_d_lane1(28, 20); a.fcvt_h_d(28, 28); a.ins_h_elt(16, 1, 28)
              a.fcvt_h_d(29, 21); a.ins_h_elt(16, 2, 29); a.umov_d_lane1(28, 21); a.fcvt_h_d(28, 28); a.ins_h_elt(16, 3, 28)
              a.fcvt_h_d(29, 22); a.ins_h_elt(16, 4, 29); a.umov_d_lane1(28, 22); a.fcvt_h_d(28, 28); a.ins_h_elt(16, 5, 28)
              a.fcvt_h_d(29, 23); a.ins_h_elt(16, 6, 29); a.umov_d_lane1(28, 23); a.fcvt_h_d(28, 28); a.ins_h_elt(16, 7, 28)
              a.str_q_post(16, R_X11, 16)
              a.sub_i(R_X9, R_X9, 8)
              a.cmp_i(R_X9, 8)
              a.b_cond(CC_GE, l_vec)
              a.bind(l_tail)
              a.cbz_x(R_X9, l_fin)
              a.fmov_d_x(R_D7, R_XZR)
              a.bind(l_sc)
              a.ldr_h_idx(16, R_X10, R_XZR); a.fcvt_d_h(16, 16); a.fmul_d(16, 16, d_sc)
              a.fcmp_d(16, R_D7); a.fcsel_d(16, 16, R_D7, CC_GT)
              a.fcvt_h_d(16, 16); a.str_h_idx(16, R_X11, R_XZR)
              a.add_i(R_X10, R_X10, 2); a.add_i(R_X11, R_X11, 2)
              a.sub_i(R_X9, R_X9, 1)
              a.cbnz_x(R_X9, l_sc)
              a.bind(l_fin)
              if v_sl >= 0
                a.sub_i(R_X15, r_n, 1)
                a.ldr_h_idx(16, r_pi, R_X15); a.fcvt_d_h(16, 16); a.fmul_d(16, 16, d_sc)
                wire_set_slot_fpr(comp, v_sl, 16)
              r_n2 = wire_get_gpr(comp, lim_vr, R_X17)
              wire_set_slot_gpr(comp, idx_sl, r_n2)
              a.b(l_end)
              return skip

  # Pattern 5: Uint8 RGBA -> Grayscale
  if body.size >= 8 && body.size <= 24
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
                j_def = defs[g0.b]
                j_ok = false
                if j_def != nil && j_def.op == :mul_i64 && wire_is_slot_load?(j_def.a, idx_sl, defs) && (c_i64[j_def.b] == 4)
                  j_vr = g0.b
                  g1_idx = defs[g1.b]; g2_idx = defs[g2.b]
                  j_ok = g1_idx != nil && g1_idx.op == :add_i64 && g1_idx.a == j_vr && c_i64[g1_idx.b] == 1 && g2_idx != nil && g2_idx.op == :add_i64 && g2_idx.a == j_vr && c_i64[g2_idx.b] == 2
                elsif j_def != nil && j_def.op == :load_i64 && j_def.imm != idx_sl
                  j_sl = j_def.imm
                  bi = 0
                  while bi < body.size - 1
                    if body[bi].op == :store_i64 && body[bi].imm == j_sl
                      md = defs[body[bi].a]
                      j_ok = (md != nil && md.op == :mul_i64 && wire_is_slot_load?(md.a, idx_sl, defs) && c_i64[md.b] == 4)
                    bi += 1
                  g1_idx = defs[g1.b]; g2_idx = defs[g2.b]
                  j_ok = j_ok && g1_idx != nil && g1_idx.op == :add_i64 && wire_is_slot_load?(g1_idx.a, j_sl, defs) && c_i64[g1_idx.b] == 1 && g2_idx != nil && g2_idx.op == :add_i64 && wire_is_slot_load?(g2_idx.a, j_sl, defs) && c_i64[g2_idx.b] == 2
                if j_ok
                  r_i = wire_get_slot_gpr(comp, idx_sl, R_X8)
                  r_n = wire_get_gpr(comp, lim_vr, R_X17)
                  r_ps = wire_get_gpr(comp, g0.a, R_X13)
                  r_pd = wire_get_gpr(comp, st_dst.a, R_X14)
                  l_tail = a.new_label; l_vec = a.new_label; l_sc = a.new_label; l_fin = a.new_label
                  a.cmp_r(r_i, r_n); a.b_cond(CC_GE, l_end)
                  a.sub_r(R_X9, r_n, r_i)
                  a.add_r(R_X10, r_ps, r_i, 2)
                  a.add_r(R_X11, r_pd, r_i)
                  a.cmp_i(R_X9, 16); a.b_cond(CC_LT, l_tail)
                  a.add_r(R_X15, R_X11, R_X9)
                  a.add_r(R_X16, R_X10, R_X9, 2)
                  l_no_ov = a.new_label
                  a.cmp_r(R_X15, R_X10); a.b_cond(CC_LS, l_no_ov)
                  a.cmp_r(R_X16, R_X11); a.b_cond(CC_HI, l_tail)
                  a.bind(l_no_ov)
                  a.mov_imm32(R_X12, c0); a.dup_16b_g(28, R_X12)
                  a.mov_imm32(R_X12, c1); a.dup_16b_g(29, R_X12)
                  a.mov_imm32(R_X12, c2); a.dup_16b_g(30, R_X12)
                  a.bind(l_vec)
                  a.ld4_16b_post(0, R_X10)
                  a.umull_8h_8b(4, 0, 28); a.umull2_8h_16b(5, 0, 28)
                  a.umlal_8h_8b(4, 1, 29); a.umlal2_8h_16b(5, 1, 29)
                  a.umlal_8h_8b(4, 2, 30); a.umlal2_8h_16b(5, 2, 30)
                  a.shrn_8b_8h(4, 4, 8); a.shrn2_16b_8h(4, 5, 8)
                  a.str_q_post(4, R_X11, 16)
                  a.sub_i(R_X9, R_X9, 16); a.cmp_i(R_X9, 16); a.b_cond(CC_GE, l_vec)
                  a.bind(l_tail)
                  a.cbz_x(R_X9, l_fin)
                  a.mov_imm32(R_X12, c0); a.mov_imm32(R_X15, c1); a.mov_imm32(R_X16, c2)
                  a.bind(l_sc)
                  a.ldrb(R_X8, R_X10, 0); a.mul_w(R_X8, R_X8, R_X12)
                  a.ldrb(R_X17, R_X10, 1); a.madd_w(R_X8, R_X17, R_X15, R_X8)
                  a.ldrb(R_X17, R_X10, 2); a.madd_w(R_X8, R_X17, R_X16, R_X8)
                  a.lsr_wi(R_X8, R_X8, 8); a.strb(R_X8, R_X11, 0)
                  a.add_i(R_X10, R_X10, 4); a.add_i(R_X11, R_X11, 1)
                  a.sub_i(R_X9, R_X9, 1); a.cbnz_x(R_X9, l_sc)
                  a.bind(l_fin)
                  r_n2 = wire_get_gpr(comp, lim_vr, R_X17)
                  wire_set_slot_gpr(comp, idx_sl, r_n2)
                  a.b(l_end)
                  return skip

  # Pattern 6: Uint64 FNV/Stream Hash -> 4x Unrolled LDP
  if body.size >= 4 && body.size <= 8
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
              l_tail = a.new_label; l_u4 = a.new_label; l_sc = a.new_label; l_fin = a.new_label
              a.cmp_r(r_i, r_n); a.b_cond(CC_GE, l_end)
              a.sub_r(R_X9, r_n, r_i)
              a.add_r(R_X10, r_pa, r_i, 3)
              a.cmp_i(R_X9, 4); a.b_cond(CC_LT, l_tail)
              a.bind(l_u4)
              a.ldp_post(R_X11, R_X12, R_X10, 16)
              a.eor_r(r_h, r_h, R_X11); a.mul_x(r_h, r_h, r_pr)
              a.eor_r(r_h, r_h, R_X12); a.mul_x(r_h, r_h, r_pr)
              a.ldp_post(R_X11, R_X12, R_X10, 16)
              a.eor_r(r_h, r_h, R_X11); a.mul_x(r_h, r_h, r_pr)
              a.eor_r(r_h, r_h, R_X12); a.mul_x(r_h, r_h, r_pr)
              a.sub_i(R_X9, R_X9, 4); a.cmp_i(R_X9, 4); a.b_cond(CC_GE, l_u4)
              a.bind(l_tail)
              a.cbz_x(R_X9, l_fin)
              a.bind(l_sc)
              a.ldr_x(R_X11, R_X10, 0); a.add_i(R_X10, R_X10, 8)
              a.eor_r(r_h, r_h, R_X11); a.mul_x(r_h, r_h, r_pr)
              a.sub_i(R_X9, R_X9, 1); a.cbnz_x(R_X9, l_sc)
              a.bind(l_fin)
              wire_set_slot_gpr(comp, h_sl, r_h)
              r_n2 = wire_get_gpr(comp, lim_vr, R_X17)
              wire_set_slot_gpr(comp, idx_sl, r_n2)
              a.b(l_end)
              return skip
  nil

-> wire_try_emit_matmul_f32(comp, i_cond_id, defs, c_i64, c_f64)
  wf = comp.wf
  return nil if wf.blocks.size < 13 || i_cond_id + 11 >= wf.blocks.size
  ic = wf.blocks[i_cond_id]
  return nil if ic.insts.size != 3
  return nil if ic.insts[0].op != :load_i64 || ic.insts[1].op != :icmp_i64 || ic.insts[1].pred != :slt || ic.insts[2].op != :cond_br
  i_sl = ic.insts[0].imm
  n_vr = ic.insts[1].b
  ib_id = ic.insts[2].t_true
  ie_id = ic.insts[2].t_false
  ib = wf.blocks[ib_id]
  return nil if ib.insts.size < 3 || ib.insts[ib.insts.size - 1].op != :br
  j_cond_id = ib.insts[ib.insts.size - 1].t_true
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

  klp = wire_match_counted_loop(wf, k_cond_id, c_i64)
  return nil if klp == nil || klp[1] != k_sl || klp[2] != n_vr
  kbody = klp[0]
  ke_id = klp[3]
  kskip = klp[4]
  return nil if kbody.size < 5 || kbody.size > 14
  st_s = kbody[kbody.size - 1]
  return nil if st_s.op != :store_double || st_s.imm != s_sl
  fa = defs[st_s.a]
  return nil if fa == nil || fa.op != :fadd_f64 || !wire_is_slot_load?(fa.a, s_sl, defs)
  fm = defs[fa.b]
  return nil if fm == nil || fm.op != :fmul_f64
  ga = defs[fm.a]
  gb = defs[fm.b]
  return nil if ga == nil || gb == nil || ga.op != :typed_array_get_inline || gb.op != :typed_array_get_inline || ga.ebits != -32 || gb.ebits != -32
  ia = defs[ga.b]
  ibx = defs[gb.b]
  return nil if ia == nil || ia.op != :add_i64 || !wire_is_slot_load?(ia.a, io_sl, defs) || !wire_is_slot_load?(ia.b, k_sl, defs)
  return nil if ibx == nil || ibx.op != :add_i64 || !wire_is_slot_load?(ibx.b, j_sl, defs)
  kn = defs[ibx.a]
  return nil if kn == nil || kn.op != :mul_i64 || !wire_is_slot_load?(kn.a, k_sl, defs) || kn.b != n_vr

  ke = wf.blocks[ke_id]
  return nil if ke.insts.size < 2 || ke.insts[ke.insts.size - 1].op != :br
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
  return nil if !wire_slot_init_i64?(wf.blocks[0], i_sl, 0, c_i64)

  skip = {
    i_cond_id => true, ib_id => true, j_cond_id => true, jb_id => true,
    ke_id => true, ju_id => true, je_id => true, iu_id => true
  }
  kskip.keys.each ->(kid) skip[kid] = true

  return nil if comp.vreg_loc[n_vr][0] != :gpr || comp.vreg_loc[ga.a][0] != :gpr || comp.vreg_loc[gb.a][0] != :gpr || comp.vreg_loc[st_c.a][0] != :gpr
  a = comp.a
  r_n = comp.vreg_loc[n_vr][1]
  r_pa = comp.vreg_loc[ga.a][1]
  r_pb = comp.vreg_loc[gb.a][1]
  r_pc = comp.vreg_loc[st_c.a][1]

  l_end = comp.blk_labels[ie_id]
  l_scalar_all = a.new_label
  l_fin = a.new_label

  a.cmp_i(r_n, 0); a.b_cond(CC_LE, l_end)
  a.mul_x(R_X16, r_n, r_n); a.lsl_xi(R_X16, R_X16, 2)
  a.add_r(R_X17, r_pc, R_X16); a.add_r(R_X15, r_pa, R_X16)
  l_ok_a = a.new_label
  a.cmp_r(R_X17, r_pa); a.b_cond(CC_LS, l_ok_a)
  a.cmp_r(R_X15, r_pc); a.b_cond(CC_HI, l_scalar_all)
  a.bind(l_ok_a)
  a.add_r(R_X15, r_pb, R_X16)
  l_ok_b = a.new_label
  a.cmp_r(R_X17, r_pb); a.b_cond(CC_LS, l_ok_b)
  a.cmp_r(R_X15, r_pc); a.b_cond(CC_HI, l_scalar_all)
  a.bind(l_ok_b)

  a.cmp_i(r_n, 8); a.b_cond(CC_LT, l_scalar_all)
  a.lsl_xi(R_X14, r_n, 2)
  a.movz_x(R_X8, 0)
  l_i2 = a.new_label; l_i1_chk = a.new_label
  a.sub_i(R_X17, r_n, 2); a.cmp_r(R_X8, R_X17); a.b_cond(CC_GT, l_i1_chk)
  a.bind(l_i2)
  a.movz_x(R_X9, 0)
  l_j8 = a.new_label; l_j8_tail = a.new_label
  a.bind(l_j8)
  a.mul_x(R_X11, R_X8, R_X14)
  a.add_r(R_X15, r_pc, R_X11); a.add_r(R_X15, R_X15, R_X9, 2)
  a.add_r(R_X16, R_X15, R_X14)
  a.add_r(R_X11, r_pa, R_X11); a.add_r(R_X12, R_X11, R_X14)
  a.add_r(R_X13, r_pb, R_X9, 2)
  a.mov_r(R_X10, r_n)
  a.movi_zero_16b(0); a.movi_zero_16b(1); a.movi_zero_16b(2); a.movi_zero_16b(3)
  a.movi_zero_16b(4); a.movi_zero_16b(5); a.movi_zero_16b(6); a.movi_zero_16b(7)
  l_k2x8 = a.new_label
  a.bind(l_k2x8)
  a.ldr_s_post(22, R_X11, 4); a.fcvt_d_s(22, 22); a.dup_2d_elt0(22, 22)
  a.ldr_s_post(23, R_X12, 4); a.fcvt_d_s(23, 23); a.dup_2d_elt0(23, 23)
  a.ldp_q(16, 17, R_X13, 0); a.add_r(R_X13, R_X13, R_X14)
  a.fcvtl_2d_2s(18, 16); a.fcvtl2_2d_4s(19, 16); a.fcvtl_2d_2s(20, 17); a.fcvtl2_2d_4s(21, 17)
  a.fmul_2d(24, 22, 18); a.fmul_2d(25, 22, 19); a.fmul_2d(26, 22, 20); a.fmul_2d(27, 22, 21)
  a.fadd_2d(0, 0, 24); a.fadd_2d(1, 1, 25); a.fadd_2d(2, 2, 26); a.fadd_2d(3, 3, 27)
  a.fmul_2d(24, 23, 18); a.fmul_2d(25, 23, 19); a.fmul_2d(26, 23, 20); a.fmul_2d(27, 23, 21)
  a.fadd_2d(4, 4, 24); a.fadd_2d(5, 5, 25); a.fadd_2d(6, 6, 26); a.fadd_2d(7, 7, 27)
  a.sub_i(R_X10, R_X10, 1); a.cbnz_x(R_X10, l_k2x8)
  a.fcvtn_2s_2d(16, 0); a.fcvtn2_4s_2d(16, 1); a.fcvtn_2s_2d(17, 2); a.fcvtn2_4s_2d(17, 3)
  a.stp_q(16, 17, R_X15, 0)
  a.fcvtn_2s_2d(16, 4); a.fcvtn2_4s_2d(16, 5); a.fcvtn_2s_2d(17, 6); a.fcvtn2_4s_2d(17, 7)
  a.stp_q(16, 17, R_X16, 0)
  a.add_i(R_X9, R_X9, 8); a.sub_i(R_X17, r_n, 8); a.cmp_r(R_X9, R_X17); a.b_cond(CC_LE, l_j8)
  a.bind(l_j8_tail)
  l_j8_t_end = a.new_label
  a.cmp_r(R_X9, r_n); a.b_cond(CC_GE, l_j8_t_end)
  a.mul_x(R_X11, R_X8, R_X14)
  a.add_r(R_X15, r_pc, R_X11); a.add_r(R_X15, R_X15, R_X9, 2); a.add_r(R_X16, R_X15, R_X14)
  a.add_r(R_X11, r_pa, R_X11); a.add_r(R_X12, R_X11, R_X14); a.add_r(R_X13, r_pb, R_X9, 2)
  a.mov_r(R_X10, r_n); a.fmov_d_x(0, R_XZR); a.fmov_d_x(1, R_XZR)
  l_kt2 = a.new_label
  a.bind(l_kt2)
  a.ldr_s_post(16, R_X11, 4); a.fcvt_d_s(16, 16)
  a.ldr_s_post(17, R_X12, 4); a.fcvt_d_s(17, 17)
  a.ldr_s_idx(18, R_X13, R_XZR); a.fcvt_d_s(18, 18); a.add_r(R_X13, R_X13, R_X14)
  a.fmul_d(16, 16, 18); a.fadd_d(0, 0, 16)
  a.fmul_d(17, 17, 18); a.fadd_d(1, 1, 17)
  a.sub_i(R_X10, R_X10, 1); a.cbnz_x(R_X10, l_kt2)
  a.fcvt_s_d(0, 0); a.str_s_idx(0, R_X15, R_XZR)
  a.fcvt_s_d(1, 1); a.str_s_idx(1, R_X16, R_XZR)
  a.add_i(R_X9, R_X9, 1); a.b(l_j8_tail)
  a.bind(l_j8_t_end)
  a.add_i(R_X8, R_X8, 2); a.sub_i(R_X17, r_n, 2); a.cmp_r(R_X8, R_X17); a.b_cond(CC_LE, l_i2)

  a.bind(l_i1_chk)
  a.cmp_r(R_X8, r_n); a.b_cond(CC_GE, l_fin)
  a.movz_x(R_X9, 0)
  l_j1_lp = a.new_label
  a.bind(l_j1_lp)
  a.mul_x(R_X11, R_X8, R_X14)
  a.add_r(R_X15, r_pc, R_X11); a.add_r(R_X15, R_X15, R_X9, 2)
  a.add_r(R_X11, r_pa, R_X11); a.add_r(R_X13, r_pb, R_X9, 2)
  a.mov_r(R_X10, r_n); a.fmov_d_x(0, R_XZR)
  l_k1_lp = a.new_label
  a.bind(l_k1_lp)
  a.ldr_s_post(16, R_X11, 4); a.fcvt_d_s(16, 16)
  a.ldr_s_idx(18, R_X13, R_XZR); a.fcvt_d_s(18, 18); a.add_r(R_X13, R_X13, R_X14)
  a.fmul_d(16, 16, 18); a.fadd_d(0, 0, 16)
  a.sub_i(R_X10, R_X10, 1); a.cbnz_x(R_X10, l_k1_lp)
  a.fcvt_s_d(0, 0); a.str_s_idx(0, R_X15, R_XZR)
  a.add_i(R_X9, R_X9, 1); a.cmp_r(R_X9, r_n); a.b_cond(CC_LT, l_j1_lp)
  a.b(l_fin)

  a.bind(l_scalar_all)
  a.lsl_xi(R_X14, r_n, 2); a.movz_x(R_X8, 0)
  l_si = a.new_label
  a.bind(l_si)
  a.movz_x(R_X9, 0)
  l_sj = a.new_label
  a.bind(l_sj)
  a.mul_x(R_X11, R_X8, R_X14)
  a.add_r(R_X15, r_pc, R_X11); a.add_r(R_X15, R_X15, R_X9, 2)
  a.add_r(R_X11, r_pa, R_X11); a.add_r(R_X13, r_pb, R_X9, 2)
  a.mov_r(R_X10, r_n); a.fmov_d_x(0, R_XZR)
  l_sk = a.new_label
  a.bind(l_sk)
  a.ldr_s_post(16, R_X11, 4); a.fcvt_d_s(16, 16)
  a.ldr_s_idx(18, R_X13, R_XZR); a.fcvt_d_s(18, 18); a.add_r(R_X13, R_X13, R_X14)
  a.fmul_d(16, 16, 18); a.fadd_d(0, 0, 16)
  a.sub_i(R_X10, R_X10, 1); a.cbnz_x(R_X10, l_sk)
  a.fcvt_s_d(0, 0); a.str_s_idx(0, R_X15, R_XZR)
  a.add_i(R_X9, R_X9, 1); a.cmp_r(R_X9, r_n); a.b_cond(CC_LT, l_sj)
  a.add_i(R_X8, R_X8, 1); a.cmp_r(R_X8, r_n); a.b_cond(CC_LT, l_si)

  a.bind(l_fin)
  wire_set_slot_gpr(comp, i_sl, r_n)
  a.b(l_end)
  skip
