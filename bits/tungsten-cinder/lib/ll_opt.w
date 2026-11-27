# cinder/ll_opt — Pure-Tungsten AOT LLVM IR (.ll) Optimizer & Function Inliner.
#
# Operates directly on `LLFunc` SSA IR before stack/register slot allocation:
#   1. `ll_pass_inline`: Mandatory `alwaysinline` / `; tungsten:alwaysinline` expansion at all
#      optimization levels (`-O0..-O3`), plus cost-modeled heuristic function inlining (`-finline`)
#      at `-O1` (<= 15), `-O2` (<= 65), and `-O3` (<= 200, x2 for constant args).
#      Supports zero-overhead single-block splicing and full multi-block CFG splitting with
#      successor-PHI repair and return-PHI construction.
#   2. `ll_pass_sroa`: Scalar `alloca` store->load forwarding & dead write-only `alloca` elimination.
#   3. `ll_pass_const_fold`: Constant folding, algebraic identities, `i128` pack/unpack scalarization
#      (eliminates `i128` wrapper shifts/ors on inlined bignum helpers!), and `--fast` FP contraction
#      (`fmul` + `fadd` -> `fmuladd.f64`, reciprocal const division).
#   4. `ll_pass_jump_threading`: Constant `cond_br` folding, empty-block jump threading, and
#      single-incoming PHI simplification with full predecessor-PHI maintenance.
#   5. `ll_pass_gvn`: Hash-based value numbering & CSE across entry + basic blocks.
#   6. `ll_pass_licm`: Hoists loop-invariant pure expressions out of natural loop bodies into entry.
#   7. `ll_pass_strength_reduce`: Power-of-2 shift/mask strength reduction + Granlund & Montgomery
#      (PLDI 1994) 64-bit unsigned division/modulo by arbitrary constants via `:umulh`.
#   8. `ll_pass_dce`: Iterative dead pure SSA & dead PHI elimination.

use ./ll_parser
use ./opt_config

# ---- Shared Helpers & Inspection ----

-> ll_count_func_insts(fn_ir)
  tot = 0
  bi = 0
  while bi < fn_ir.blocks.size()
    tot += fn_ir.blocks[bi].phis.size() + fn_ir.blocks[bi].insts.size()
    bi += 1
  tot

-> ll_is_pure_inst?(ins)
  op = ins.op
  return true if op == :copy || op == :gep || op == :umulh
  return true if op == :add || op == :sub || op == :mul || op == :and || op == :or || op == :xor
  return true if op == :shl || op == :ashr || op == :lshr
  return true if op == :fadd || op == :fsub || op == :fmul || op == :fdiv
  return true if op == :icmp || op == :fcmp || op == :select
  return true if op == :sext || op == :zext || op == :trunc || op == :inttoptr || op == :ptrtoint || op == :bitcast
  return true if op == :sitofp || op == :uitofp || op == :fptosi || op == :fptoui || op == :fptrunc || op == :fpext
  return true if op == :extractvalue || op == :extractelement
  if op == :intrinsic
    intr = ins.pred
    return true if intr == "smul.with.overflow.i64" || intr == "cttz.i64" || intr == "ctlz.i64" || intr == "ctpop.i64" || intr == "sqrt.f64" || intr == "fmuladd.f64"
  false

-> ll_types_inline_compat?(actual_ty, formal_ty)
  return true if actual_ty == formal_ty
  is_a64 = (actual_ty == LLTY_I64 || actual_ty == LLTY_PTR)
  is_f64 = (formal_ty == LLTY_I64 || formal_ty == LLTY_PTR)
  is_a64 && is_f64

-> ll_make_copy_inst(dst_id, ty, src_k, src_v)
  ins = LLInst.new(:copy, dst_id, ty)
  ins.k0 = src_k
  ins.v0 = src_v
  ins

# Resolve transitive `[kind, val]` alias map (`val_id -> [op_kind, op_val]`)
-> ll_resolve_val_subst(subst, k, v)
  return [k, v] if k != LLOP_VAL
  cur_k = k
  cur_v = v
  guard = 0
  while cur_k == LLOP_VAL && subst[cur_v] != nil && guard < 32
    nxt = subst[cur_v]
    break if nxt[0] == LLOP_VAL && nxt[1] == cur_v
    cur_k = nxt[0]
    cur_v = nxt[1]
    guard += 1
  [cur_k, cur_v]

-> ll_apply_subst_to_func(fn_ir, subst)
  return nil if subst.size() == 0
  bi = 0
  while bi < fn_ir.blocks.size()
    blk = fn_ir.blocks[bi]
    pi = 0
    while pi < blk.phis.size()
      prs = blk.phis[pi].extra
      j = 0
      while j < prs.size()
        if prs[j][1] == LLOP_VAL && subst[prs[j][2]] != nil
          r = ll_resolve_val_subst(subst, prs[j][1], prs[j][2])
          prs[j][1] = r[0]; prs[j][2] = r[1]
        j += 1
      pi += 1

    ii = 0
    while ii < blk.insts.size()
      ins = blk.insts[ii]
      if ins.k0 == LLOP_VAL && subst[ins.v0] != nil
        r0 = ll_resolve_val_subst(subst, ins.k0, ins.v0)
        ins.k0 = r0[0]; ins.v0 = r0[1]
      if ins.k1 == LLOP_VAL && subst[ins.v1] != nil
        r1 = ll_resolve_val_subst(subst, ins.k1, ins.v1)
        ins.k1 = r1[0]; ins.v1 = r1[1]
      if ins.k2 == LLOP_VAL && subst[ins.v2] != nil
        r2 = ll_resolve_val_subst(subst, ins.k2, ins.v2)
        ins.k2 = r2[0]; ins.v2 = r2[1]
      if ins.extra != nil
        op = ins.op
        if op == :call || op == :intrinsic
          ai = 0
          while ai < ins.extra.size()
            ca = ins.extra[ai]
            if ca[1] == LLOP_VAL && subst[ca[2]] != nil
              ra = ll_resolve_val_subst(subst, ca[1], ca[2])
              ca[1] = ra[0]; ca[2] = ra[1]
            ai += 1
        elsif op == :call_asm
          aargs = ins.extra[1]
          ai = 0
          while ai < aargs.size()
            ca = aargs[ai]
            if ca[1] == LLOP_VAL && subst[ca[2]] != nil
              ra = ll_resolve_val_subst(subst, ca[1], ca[2])
              ca[1] = ra[0]; ca[2] = ra[1]
            ai += 1
        elsif op == :gep
          ai = 0
          while ai < ins.extra.size()
            st = ins.extra[ai]
            if st[0] == LLOP_VAL && subst[st[1]] != nil
              rg = ll_resolve_val_subst(subst, st[0], st[1])
              st[0] = rg[0]; st[1] = rg[1]
            ai += 1
      ii += 1
    bi += 1
  nil

-> ll_count_uses(fn_ir)
  uses = Array.new(fn_ir.n_vals, 0)
  bi = 0
  while bi < fn_ir.blocks.size()
    blk = fn_ir.blocks[bi]
    pi = 0
    while pi < blk.phis.size()
      prs = blk.phis[pi].extra
      j = 0
      while j < prs.size()
        uses[prs[j][2]] = uses[prs[j][2]] + 1 if prs[j][1] == LLOP_VAL
        j += 1
      pi += 1
    ii = 0
    while ii < blk.insts.size()
      ins = blk.insts[ii]
      uses[ins.v0] = uses[ins.v0] + 1 if ins.k0 == LLOP_VAL
      uses[ins.v1] = uses[ins.v1] + 1 if ins.k1 == LLOP_VAL
      uses[ins.v2] = uses[ins.v2] + 1 if ins.k2 == LLOP_VAL
      if ins.extra != nil
        op = ins.op
        if op == :call || op == :intrinsic
          ai = 0
          while ai < ins.extra.size()
            ca = ins.extra[ai]
            uses[ca[2]] = uses[ca[2]] + 1 if ca[1] == LLOP_VAL
            ai += 1
        elsif op == :call_asm
          aargs = ins.extra[1]
          ai = 0
          while ai < aargs.size()
            ca = aargs[ai]
            uses[ca[2]] = uses[ca[2]] + 1 if ca[1] == LLOP_VAL
            ai += 1
        elsif op == :gep
          ai = 0
          while ai < ins.extra.size()
            st = ins.extra[ai]
            uses[st[1]] = uses[st[1]] + 1 if st[0] == LLOP_VAL
            ai += 1
      ii += 1
    bi += 1
  uses

# ---- Pass 1: Function Inliner (`alwaysinline` + Cost-Modeled `-finline`) ----

+ LLInlineContext
  rw :src, :src_ptr, :mod_info, :opt_cfg, :callee_cache, :alias_sym_id
  rw :call_counts, :const_ret_map

  -> new(@src, @src_ptr, @mod_info, @opt_cfg)
    @callee_cache = {}
    @alias_sym_id = {}
    @call_counts = {}
    @const_ret_map = {}
    if @mod_info != nil && @mod_info.aliases != nil
      ai = 0
      while ai < @mod_info.aliases.size()
        al_nm = @mod_info.aliases[ai][0]
        tg_nm = @mod_info.aliases[ai][1]
        al_id = @mod_info.sym_to_id[al_nm]
        tg_id = @mod_info.sym_to_id[tg_nm]
        if al_id != nil && tg_id != nil
          @alias_sym_id[al_id] = tg_id
        ai += 1

  -> resolve_sym_id(raw_sym_id)
    sym_id = raw_sym_id
    guard = 0
    while @alias_sym_id[sym_id] != nil && guard < 8
      sym_id = @alias_sym_id[sym_id]
      guard += 1
    sym_id

  -> span_is_alwaysinline?(span)
    hdr = span[0]
    return true if hdr.index("alwaysinline") != nil
    # Check `#N` attribute group references on `define` header
    hi = hdr.index("#")
    while hi != nil
      hend = hi + 1
      while hend < hdr.size() && hdr.byte_at(hend) >= 48 && hdr.byte_at(hend) <= 57
        hend += 1
      if hend > hi + 1
        tag = hdr.slice(hi, hend - hi)
        return true if @mod_info.attr_groups[tag] == :always
      hi = hdr.index("#", hend)
    # Check first 160 bytes of body for `; tungsten:alwaysinline`
    b_start = span[1]
    b_end = span[2]
    peek_len = b_end - b_start
    peek_len = 160 if peek_len > 160
    if peek_len > 0
      head_s = @src.slice(b_start, peek_len)
      return true if head_s.index("; tungsten:alwaysinline") != nil
    false

  -> get_callee(raw_sym_id, only_always)
    sym_id = resolve_sym_id(raw_sym_id)
    span_idx = @mod_info.fn_span_by_sym_id[sym_id]
    return nil if span_idx == nil
    cached = @callee_cache[sym_id]
    if cached != nil
      return nil if cached == :skip
      return nil if only_always && cached.inline_hint != :always
      return cached
    span = @mod_info.fn_spans[span_idx]
    is_alw = span_is_alwaysinline?(span)
    return nil if only_always && !is_alw
    if !is_alw
      hdr = span[0]
      if hdr.index("noinline") != nil
        @callee_cache[sym_id] = :skip
        return nil
      blen = span[2] - span[1]
      max_b = @opt_cfg.opt_level >= 3 ? 45000 : (@opt_cfg.opt_level == 2 ? 12000 : 2400)
      if blen > max_b
        @callee_cache[sym_id] = :skip
        return nil
    cal_ir = ll_parse_function(@src, @src_ptr, @mod_info, span, false)
    if cal_ir.inline_hint == :never
      @callee_cache[sym_id] = :skip
      return nil
    # Pre-simplify callee (`sroa` + `const-fold` + `jump-threading` + `dce`) once before caching
    # so `%vs.*` allocas disappear and cost estimation reflects actual simplified IR!
    if @opt_cfg == nil || @opt_cfg.opt_level >= 1
      ll_pass_sroa(cal_ir)
      ll_pass_const_fold(cal_ir, @opt_cfg)
      ll_pass_jump_threading(cal_ir)
      ll_pass_dce(cal_ir)
    @callee_cache[sym_id] = cal_ir
    return nil if only_always && cal_ir.inline_hint != :always
    cal_ir

-> ll_estimate_inline_cost(callee, call_ins)
  cost = 0
  bi = 0
  while bi < callee.blocks.size()
    blk = callee.blocks[bi]
    cost += 2 if bi > 0
    cost += blk.phis.size()
    ii = 0
    while ii < blk.insts.size()
      ins = blk.insts[ii]
      op = ins.op
      if op == :load || op == :store
        cost += 2
      elsif op == :call
        cost += 4
      elsif op == :call_asm
        cost += 2 + (ins.extra[0].size() / 8)
      elsif op == :switch
        cost += 12
      elsif op == :inttoptr || op == :ptrtoint || op == :bitcast
        cost += 0
      elsif op != :br && op != :ret && op != :ret_void
        cost += 1
      ii += 1
    bi += 1
  cost -= 10 if callee.is_internal
  cargs = call_ins.extra
  if cargs != nil && cargs.size() > 0
    all_imm = true
    ai = 0
    while ai < cargs.size()
      if cargs[ai][1] == LLOP_IMM
        cost -= 8
      else
        all_imm = false
      ai += 1
    cost -= 15 if all_imm
  cost < 0 ? 0 : cost

-> ll_remap_inline_op(k, v, param_ops, val_remap)
  return [k, v] if k != LLOP_VAL
  return param_ops[v] if v < param_ops.size()
  nv = val_remap[v]
  [LLOP_VAL, nv != nil ? nv : v]

-> ll_clone_inst_for_inline(ins, param_ops, val_remap, blk_remap, alloca_base)
  cp = ins.clone()
  if cp.dst >= 0
    nd = val_remap[cp.dst]
    cp.dst = nd if nd != nil
  if cp.op == :alloca
    cp.v0 = cp.v0 + alloca_base
    return cp
  if cp.op == :br
    cp.v0 = blk_remap[cp.v0]
    return cp
  if cp.op == :cond_br
    r0 = ll_remap_inline_op(cp.k0, cp.v0, param_ops, val_remap)
    cp.k0 = r0[0]; cp.v0 = r0[1]
    cp.v1 = blk_remap[cp.v1]
    cp.v2 = blk_remap[cp.v2]
    return cp
  if cp.op == :switch
    r0 = ll_remap_inline_op(cp.k0, cp.v0, param_ops, val_remap)
    cp.k0 = r0[0]; cp.v0 = r0[1]
    cp.v1 = blk_remap[cp.v1]
    ci = 0
    while ci < cp.extra.size()
      cp.extra[ci][1] = blk_remap[cp.extra[ci][1]]
      ci += 1
    return cp
  if cp.op == :phi
    pi = 0
    while pi < cp.extra.size()
      pr = cp.extra[pi]
      pr[0] = blk_remap[pr[0]]
      rv = ll_remap_inline_op(pr[1], pr[2], param_ops, val_remap)
      pr[1] = rv[0]; pr[2] = rv[1]
      pi += 1
    return cp

  if cp.k0 == LLOP_VAL
    r0 = ll_remap_inline_op(cp.k0, cp.v0, param_ops, val_remap)
    cp.k0 = r0[0]; cp.v0 = r0[1]
  if cp.k1 == LLOP_VAL
    r1 = ll_remap_inline_op(cp.k1, cp.v1, param_ops, val_remap)
    cp.k1 = r1[0]; cp.v1 = r1[1]
  if cp.k2 == LLOP_VAL
    r2 = ll_remap_inline_op(cp.k2, cp.v2, param_ops, val_remap)
    cp.k2 = r2[0]; cp.v2 = r2[1]
  if cp.extra != nil
    op = cp.op
    if op == :call || op == :intrinsic
      ai = 0
      while ai < cp.extra.size()
        ca = cp.extra[ai]
        if ca[1] == LLOP_VAL
          ra = ll_remap_inline_op(ca[1], ca[2], param_ops, val_remap)
          ca[1] = ra[0]; ca[2] = ra[1]
        ai += 1
    elsif op == :call_asm
      aargs = cp.extra[1]
      ai = 0
      while ai < aargs.size()
        ca = aargs[ai]
        if ca[1] == LLOP_VAL
          ra = ll_remap_inline_op(ca[1], ca[2], param_ops, val_remap)
          ca[1] = ra[0]; ca[2] = ra[1]
        ai += 1
    elsif op == :gep
      ai = 0
      while ai < cp.extra.size()
        st = cp.extra[ai]
        if st[0] == LLOP_VAL
          rg = ll_remap_inline_op(st[0], st[1], param_ops, val_remap)
          st[0] = rg[0]; st[1] = rg[1]
        ai += 1
  cp

# When caller block `orig_bid` is split into `orig_bid ... -> cont_bid`, every successor of `cont_bid`
# that had PHI incoming edges from `orig_bid` now receives control from `cont_bid`!
-> ll_repair_split_succ_phis(fn_ir, cont_blk, orig_bid, cont_bid)
  return nil if cont_blk.insts.size() == 0
  term = cont_blk.insts[cont_blk.insts.size() - 1]
  succs = []
  if term.op == :br
    succs.push(term.v0)
  elsif term.op == :cond_br
    succs.push(term.v1)
    succs.push(term.v2) if term.v2 != term.v1
  elsif term.op == :switch
    succs.push(term.v1)
    ci = 0
    while ci < term.extra.size()
      sb = term.extra[ci][1]
      succs.push(sb) if !succs.include?(sb)
      ci += 1
  si = 0
  while si < succs.size()
    sblk = fn_ir.blocks[succs[si]]
    pi = 0
    while pi < sblk.phis.size()
      prs = sblk.phis[pi].extra
      j = 0
      while j < prs.size()
        prs[j][0] = cont_bid if prs[j][0] == orig_bid
        j += 1
      pi += 1
    si += 1
  nil

-> ll_callee_can_inline?(caller, caller_bid, call_ins, callee)
  return false if callee == nil || callee.name == caller.name
  return false if callee.inline_hint == :never || callee.blocks.size() == 0
  return false if callee.is_preserve_most && !caller.is_preserve_most
  cargs = call_ins.extra
  nargs = cargs != nil ? cargs.size() : 0
  return false if nargs != callee.n_params
  return false if !ll_types_inline_compat?(call_ins.ty, callee.ret_ty)
  pi = 0
  while pi < nargs
    return false if !ll_types_inline_compat?(cargs[pi][0], callee.param_tys[pi])
    pi += 1
  # `callee.alloca_bytes` are static frame slots in `fn_ir.alloca_bytes` (never dynamic SP bumps);
  # bound frame growth for heuristic inlining into non-entry blocks to <= 256 bytes.
  return false if callee.alloca_bytes > 256 && caller_bid != 0 && callee.inline_hint != :always
  # Ensure at least one return exists when caller expects a return value
  if call_ins.dst >= 0
    has_ret = false
    bi = 0
    while bi < callee.blocks.size()
      b = callee.blocks[bi]
      if b.insts.size() > 0 && b.insts[b.insts.size() - 1].op == :ret
        has_ret = true
      bi += 1
    return false if !has_ret
  true

# Interprocedural constant-return discovery & whole-module call-site counting (`ipa-sccp` + single-caller LTO boost):
#   - Counts direct call references per target symbol across the module so single-caller `internal`
#     functions get a 2.5x inline threshold boost (inlining eliminates the out-of-line body!).
#   - Identifies side-effect-free functions whose simplified body unconditionally returns an immediate
#     constant (`ret i64 C`), allowing callers to fold `call @fn(...)` directly to `C` even with `-fno-inline`!
-> ll_build_ipa_summaries(src, src_ptr, mod_info, inl_ctx, opt_cfg)
  return nil if mod_info == nil || inl_ctx == nil
  do_sccp = opt_cfg != nil && opt_cfg.pass_enabled?("ipa-sccp")
  n_spans = mod_info.fn_spans.size()
  fi = 0
  while fi < n_spans
    span = mod_info.fn_spans[fi]
    b_start = span[1]
    b_end = span[2]
    # Fast byte-level scan for `call ... @<sym>(` to populate `call_counts` without full IR parse!
    pos = b_start
    while pos < b_end
      nl = ll_find_nl(src_ptr, pos, b_end)
      if nl > pos
        ln = src.slice(pos, nl - pos)
        c_idx = ln.index("call ")
        if c_idx != nil
          at_i = ll_index_outside_quotes(ln, 64, c_idx + 5)
          if at_i >= 0
            lp_i = ll_index_outside_quotes(ln, 40, at_i + 1)
            if lp_i > at_i
              cnm = ll_clean_sym(ln.slice(at_i, lp_i - at_i))
              raw_sid = mod_info.sym_to_id[cnm]
              if raw_sid != nil
                sid = inl_ctx.resolve_sym_id(raw_sid)
                prev_c = inl_ctx.call_counts[sid]
                inl_ctx.call_counts[sid] = (prev_c == nil ? 1 : (prev_c + 1))
      pos = nl + 1

    # Check tiny single-block functions (`<= 320` body bytes) for pure constant return (`ipa-sccp`)
    if do_sccp && (b_end - b_start) <= 320
      hdr = span[0]
      if hdr.index("weak") == nil && hdr.index("linkonce") == nil
        at_h = ll_index_outside_quotes(hdr, 64, 0)
        lp_h = ll_index_outside_quotes(hdr, 40, at_h)
        fnm = ll_clean_sym(hdr.slice(at_h, lp_h - at_h))
        fsid = mod_info.sym_to_id[fnm]
        if fsid != nil
          cal = ll_parse_function(src, src_ptr, mod_info, span, false)
          ll_pass_sroa(cal)
          ll_pass_const_fold(cal, opt_cfg)
          ll_pass_jump_threading(cal)
          ll_pass_dce(cal)
          inl_ctx.callee_cache[fsid] = cal if cal.inline_hint != :never
          if cal.blocks.size() == 1 && cal.blocks[0].phis.size() == 0
            insts = cal.blocks[0].insts
            if insts.size() >= 1
              last_i = insts[insts.size() - 1]
              if last_i.op == :ret && last_i.k0 == LLOP_IMM
                pure_all = true
                ki = 0
                while ki < insts.size() - 1
                  if !ll_is_pure_inst?(insts[ki])
                    pure_all = false
                    break
                  ki += 1
                inl_ctx.const_ret_map[fsid] = [last_i.ty, last_i.v0] if pure_all
    fi += 1
  nil

-> ll_pass_inline(fn_ir, inl_ctx, opt_cfg)
  return nil if fn_ir == nil || inl_ctx == nil
  allow_always = opt_cfg == nil || opt_cfg.pass_enabled?("always-inline")
  allow_heur = opt_cfg != nil && opt_cfg.pass_enabled?("inline")
  return nil if !allow_always && !allow_heur

  thresh = opt_cfg != nil ? opt_cfg.inline_threshold() : 65
  only_always = !allow_heur
  round = 0
  changed = true
  while changed && round < 4
    changed = false
    round += 1
    caller_insts = ll_count_func_insts(fn_ir)

    bi = 0
    while bi < fn_ir.blocks.size()
      blk = fn_ir.blocks[bi]
      ii = 0
      while ii < blk.insts.size()
        ins = blk.insts[ii]
        if ins.op == :call && ins.k0 == LLOP_SYM
          res_sid = inl_ctx.resolve_sym_id(ins.v0)
          cret = (opt_cfg != nil && opt_cfg.pass_enabled?("ipa-sccp")) ? inl_ctx.const_ret_map[res_sid] : nil
          if cret != nil && ll_types_inline_compat?(ins.ty, cret[0])
            if ins.dst >= 0
              blk.insts[ii] = ll_make_copy_inst(ins.dst, ins.ty, LLOP_IMM, cret[1])
            else
              blk.insts[ii] = LLInst.new(:copy, -1, LLTY_VOID)
            changed = true
            ii += 1
            next
          callee = inl_ctx.get_callee(res_sid, only_always)
          if callee != nil && ll_callee_can_inline?(fn_ir, bi, ins, callee)
            do_inl = false
            if callee.inline_hint == :always && allow_always
              do_inl = true
            elsif allow_heur && caller_insts < 1600
              est = ll_estimate_inline_cost(callee, ins)
              eff_t = thresh
              if callee.is_internal && inl_ctx.call_counts[res_sid] == 1 && caller_insts <= 80 && callee.blocks.size() <= 4
                eff_t = (eff_t * 5) / 2
              cargs = ins.extra
              if cargs != nil && cargs.size() > 0
                all_c = true
                ci = 0
                while ci < cargs.size()
                  all_c = false if cargs[ci][1] != LLOP_IMM
                  ci += 1
                eff_t = eff_t * 2 if all_c
              do_inl = (est <= eff_t)

            if do_inl
              cargs = ins.extra
              param_ops = []
              pi = 0
              while pi < callee.n_params
                param_ops.push([cargs[pi][1], cargs[pi][2]])
                pi += 1
              val_remap = {}
              vi = callee.n_params
              while vi < callee.n_vals
                val_remap[vi] = fn_ir.alloc_anon_val(callee.val_tys[vi])
                vi += 1

              alloca_base = 0
              if callee.alloca_bytes > 0
                alloca_base = ((fn_ir.alloca_bytes + 15) / 16) * 16
                fn_ir.alloca_bytes = alloca_base + callee.alloca_bytes
              if callee.uses_ic && !fn_ir.uses_ic
                fn_ir.uses_ic = true
                fn_ir.ic_sym_id = callee.ic_sym_id

              # Fast path: single-block callee with no PHIs ending in `:ret` / `:ret_void`!
              cb0 = callee.blocks[0]
              cterm = cb0.insts.size() > 0 ? cb0.insts[cb0.insts.size() - 1] : nil
              if callee.blocks.size() == 1 && cb0.phis.size() == 0 && cterm != nil && (cterm.op == :ret || cterm.op == :ret_void)
                direct_dst = false
                if ins.dst >= 0 && cterm.op == :ret && cterm.k0 == LLOP_VAL && cterm.v0 >= callee.n_params
                  val_remap[cterm.v0] = ins.dst
                  direct_dst = true
                spliced = []
                ki = 0
                while ki < ii
                  spliced.push(blk.insts[ki])
                  ki += 1
                ci = 0
                while ci < cb0.insts.size() - 1
                  spliced.push(ll_clone_inst_for_inline(cb0.insts[ci], param_ops, val_remap, nil, alloca_base))
                  ci += 1
                if ins.dst >= 0 && !direct_dst && cterm.op == :ret
                  rop = ll_remap_inline_op(cterm.k0, cterm.v0, param_ops, val_remap)
                  spliced.push(ll_make_copy_inst(ins.dst, ins.ty, rop[0], rop[1]))
                ki = ii + 1
                while ki < blk.insts.size()
                  spliced.push(blk.insts[ki])
                  ki += 1
                blk.insts = spliced
                caller_insts += cb0.insts.size()
                changed = true
                next
              else
                # General multi-block CFG splice: `blk -> cloned_blocks -> cont_blk`
                blk_remap = Array.new(callee.blocks.size(), -1)
                cbi = 0
                while cbi < callee.blocks.size()
                  blk_remap[cbi] = fn_ir.alloc_anon_block()
                  cbi += 1
                cont_bid = fn_ir.alloc_anon_block()
                cont_blk = fn_ir.blocks[cont_bid]

                ki = ii + 1
                while ki < blk.insts.size()
                  cont_blk.insts.push(blk.insts[ki])
                  ki += 1
                ll_repair_split_succ_phis(fn_ir, cont_blk, bi, cont_bid)

                pre_insts = []
                ki = 0
                while ki < ii
                  pre_insts.push(blk.insts[ki])
                  ki += 1
                br_in = LLInst.new(:br, -1, LLTY_VOID)
                br_in.v0 = blk_remap[0]
                pre_insts.push(br_in)
                blk.insts = pre_insts

                ret_incoming = []
                cbi = 0
                while cbi < callee.blocks.size()
                  src_b = callee.blocks[cbi]
                  dst_bid = blk_remap[cbi]
                  dst_b = fn_ir.blocks[dst_bid]
                  phi_i = 0
                  while phi_i < src_b.phis.size()
                    dst_b.phis.push(ll_clone_inst_for_inline(src_b.phis[phi_i], param_ops, val_remap, blk_remap, alloca_base))
                    phi_i += 1
                  cii = 0
                  while cii < src_b.insts.size()
                    sins = src_b.insts[cii]
                    if sins.op == :ret || sins.op == :ret_void
                      if ins.dst >= 0 && sins.op == :ret
                        rop = ll_remap_inline_op(sins.k0, sins.v0, param_ops, val_remap)
                        ret_incoming.push([dst_bid, rop[0], rop[1]])
                      br_out = LLInst.new(:br, -1, LLTY_VOID)
                      br_out.v0 = cont_bid
                      dst_b.insts.push(br_out)
                    else
                      dst_b.insts.push(ll_clone_inst_for_inline(sins, param_ops, val_remap, blk_remap, alloca_base))
                    cii += 1
                  cbi += 1

                if ins.dst >= 0
                  if ret_incoming.size() == 1
                    rb_id = ret_incoming[0][0]
                    rb = fn_ir.blocks[rb_id]
                    rb_term = rb.insts.pop()
                    rb.insts.push(ll_make_copy_inst(ins.dst, ins.ty, ret_incoming[0][1], ret_incoming[0][2]))
                    rb.insts.push(rb_term)
                  elsif ret_incoming.size() > 1
                    rphi = LLInst.new(:phi, ins.dst, ins.ty)
                    rphi.extra = ret_incoming
                    new_phis = [rphi]
                    pi2 = 0
                    while pi2 < cont_blk.phis.size()
                      new_phis.push(cont_blk.phis[pi2])
                      pi2 += 1
                    cont_blk.phis = new_phis

                caller_insts += ll_count_func_insts(callee)
                changed = true
                break
        ii += 1
      bi += 1
  nil

# ---- Pass 2: Scalar `alloca` Store->Load Forwarding & Dead `alloca` SROA ----

-> ll_pass_sroa(fn_ir)
  return nil if fn_ir == nil || fn_ir.alloca_bytes == 0
  # Identify non-escaping scalar `alloca` SSA values (used ONLY as pointer in `:load` / `:store` of one scalar type!)
  alloca_ty = {}
  escaped = {}
  bi = 0
  while bi < fn_ir.blocks.size()
    blk = fn_ir.blocks[bi]
    blk.phis.each ->(ph)
      ph.extra.each ->(pr)
        escaped[pr[2]] = true if pr[1] == LLOP_VAL
    ii = 0
    while ii < blk.insts.size()
      ins = blk.insts[ii]
      op = ins.op
      if op == :alloca && ins.dst >= 0
        alloca_ty[ins.dst] = 0
      elsif op == :load
        if ins.k0 == LLOP_VAL && alloca_ty[ins.v0] != nil
          prev = alloca_ty[ins.v0]
          if prev == 0 || prev == ins.ty
            alloca_ty[ins.v0] = ins.ty
          else
            escaped[ins.v0] = true
      elsif op == :store
        escaped[ins.v0] = true if ins.k0 == LLOP_VAL && alloca_ty[ins.v0] != nil
        if ins.k1 == LLOP_VAL && alloca_ty[ins.v1] != nil
          prev = alloca_ty[ins.v1]
          if prev == 0 || prev == ins.ty
            alloca_ty[ins.v1] = ins.ty
          else
            escaped[ins.v1] = true
      else
        escaped[ins.v0] = true if ins.k0 == LLOP_VAL && alloca_ty[ins.v0] != nil
        escaped[ins.v1] = true if ins.k1 == LLOP_VAL && alloca_ty[ins.v1] != nil
        escaped[ins.v2] = true if ins.k2 == LLOP_VAL && alloca_ty[ins.v2] != nil
        if ins.extra != nil
          if op == :call || op == :intrinsic
            ins.extra.each ->(ca)
              escaped[ca[2]] = true if ca[1] == LLOP_VAL && alloca_ty[ca[2]] != nil
          elsif op == :call_asm
            ins.extra[1].each ->(ca)
              escaped[ca[2]] = true if ca[1] == LLOP_VAL && alloca_ty[ca[2]] != nil
          elsif op == :gep
            ins.extra.each ->(st)
              escaped[st[1]] = true if st[0] == LLOP_VAL && alloca_ty[st[1]] != nil
      ii += 1
    bi += 1

  promotable = {}
  alloca_ty.keys.each ->(aid)
    ty = alloca_ty[aid]
    if !escaped[aid] && (ty == 0 || ty == LLTY_I64 || ty == LLTY_PTR || ty == LLTY_I32 || ty == LLTY_F64)
      promotable[aid] = true
  return nil if promotable.size() == 0

  # Step 1: Intra-block store->load and load->load forwarding on promotable `alloca`s
  subst = {}
  bi = 0
  while bi < fn_ir.blocks.size()
    blk = fn_ir.blocks[bi]
    cur_mem = {}
    kept = []
    ii = 0
    while ii < blk.insts.size()
      ins = blk.insts[ii]
      if ins.op == :store && ins.k1 == LLOP_VAL && promotable[ins.v1]
        r_val = ll_resolve_val_subst(subst, ins.k0, ins.v0)
        ins.k0 = r_val[0]; ins.v0 = r_val[1]
        cur_mem[ins.v1] = r_val
        kept.push(ins)
      elsif ins.op == :load && ins.k0 == LLOP_VAL && promotable[ins.v0]
        known = cur_mem[ins.v0]
        if known != nil
          subst[ins.dst] = known
        else
          cur_mem[ins.v0] = [LLOP_VAL, ins.dst]
          kept.push(ins)
      else
        kept.push(ins)
      ii += 1
    blk.insts = kept
    bi += 1

  ll_apply_subst_to_func(fn_ir, subst)

  # Step 2: Eliminate any promotable `alloca` (and all stores to it) that now has ZERO loads!
  has_load = {}
  bi = 0
  while bi < fn_ir.blocks.size()
    blk = fn_ir.blocks[bi]
    ii = 0
    while ii < blk.insts.size()
      ins = blk.insts[ii]
      has_load[ins.v0] = true if ins.op == :load && ins.k0 == LLOP_VAL && promotable[ins.v0]
      ii += 1
    bi += 1

  rem_allocas = []
  promotable.keys.each ->(aid)
    rem_allocas.push(aid) if has_load[aid] == true && alloca_ty[aid] != 0

  # Step 3: Multi-block SSA `mem2reg` (Braun et al., CC 2013) for remaining scalar `alloca`s!
  if rem_allocas.size() > 0 && fn_ir.blocks.size() > 1
    nb = fn_ir.blocks.size()
    reach = Array.new(nb, false)
    reach[0] = true
    wl = [0]
    wi = 0
    while wi < wl.size()
      b = fn_ir.blocks[wl[wi]]
      wi += 1
      if b.insts.size() > 0
        t = b.insts[b.insts.size() - 1]
        if t.op == :br
          if !reach[t.v0]
            reach[t.v0] = true; wl.push(t.v0)
        elsif t.op == :cond_br
          if !reach[t.v1]
            reach[t.v1] = true; wl.push(t.v1)
          if !reach[t.v2]
            reach[t.v2] = true; wl.push(t.v2)
        elsif t.op == :switch
          if !reach[t.v1]
            reach[t.v1] = true; wl.push(t.v1)
          ci = 0
          while ci < t.extra.size()
            sb = t.extra[ci][1]
            if !reach[sb]
              reach[sb] = true; wl.push(sb)
            ci += 1

    preds = Array.new(nb, nil)
    bi = 0
    while bi < nb
      preds[bi] = []
      bi += 1
    bi = 0
    while bi < nb
      if reach[bi]
        b = fn_ir.blocks[bi]
        if b.insts.size() > 0
          t = b.insts[b.insts.size() - 1]
          if t.op == :br
            preds[t.v0].push(bi) if !preds[t.v0].include?(bi)
          elsif t.op == :cond_br
            preds[t.v1].push(bi) if !preds[t.v1].include?(bi)
            preds[t.v2].push(bi) if !preds[t.v2].include?(bi)
          elsif t.op == :switch
            preds[t.v1].push(bi) if !preds[t.v1].include?(bi)
            ci = 0
            while ci < t.extra.size()
              sb = t.extra[ci][1]
              preds[sb].push(bi) if !preds[sb].include?(bi)
              ci += 1
      bi += 1

    subst2 = {}
    promoted_done = {}
    ri = 0
    while ri < rem_allocas.size()
      aid = rem_allocas[ri]
      aty = alloca_ty[aid]
      entry_load_dst = Array.new(nb, -1)
      last_store = Array.new(nb, nil)
      bi = 0
      while bi < nb
        if reach[bi]
          blk = fn_ir.blocks[bi]
          ii = 0
          while ii < blk.insts.size()
            ins = blk.insts[ii]
            if ins.op == :load && ins.k0 == LLOP_VAL && ins.v0 == aid
              entry_load_dst[bi] = ins.dst
            elsif ins.op == :store && ins.k1 == LLOP_VAL && ins.v1 == aid
              last_store[bi] = [ins.k0, ins.v0]
            ii += 1
        bi += 1

      entry_memo = Array.new(nb, nil)
      created_phis = []

      # Iterative helper: resolve value of `aid` at ENTRY of reachable block `start_b`
      resolve_entry = ->(start_b)
        return entry_memo[start_b] if entry_memo[start_b] != nil
        chain = []
        cur = start_b
        res = nil
        while res == nil
          if entry_memo[cur] != nil
            res = entry_memo[cur]
          elsif cur == 0 || preds[cur].size() == 0
            res = [LLOP_IMM, 0]
          elsif preds[cur].size() == 1
            p0 = preds[cur][0]
            if last_store[p0] != nil
              res = last_store[p0]
            else
              chain.push(cur)
              cur = p0
          else
            ph = LLInst.new(:phi, fn_ir.alloc_anon_val(aty), aty)
            ph.extra = []
            fn_ir.blocks[cur].phis.push(ph)
            res = [LLOP_VAL, ph.dst]
            entry_memo[cur] = res
            created_phis.push([cur, ph])
        ci2 = 0
        while ci2 < chain.size()
          entry_memo[chain[ci2]] = res
          ci2 += 1
        entry_memo[start_b] = res
        res

      bi = 0
      while bi < nb
        ld_dst = entry_load_dst[bi]
        if ld_dst >= 0
          subst2[ld_dst] = resolve_entry.call(bi)
        bi += 1

      qi = 0
      while qi < created_phis.size()
        item = created_phis[qi]
        qi += 1
        pb = item[0]
        ph = item[1]
        ps = preds[pb]
        pi2 = 0
        while pi2 < ps.size()
          pr_b = ps[pi2]
          pv = last_store[pr_b] != nil ? last_store[pr_b] : resolve_entry.call(pr_b)
          ph.extra.push([pr_b, pv[0], pv[1]])
          pi2 += 1

      promoted_done[aid] = true
      has_load[aid] = false
      ri += 1

    ll_apply_subst_to_func(fn_ir, subst2)

  any_alloca_left = false
  bi = 0
  while bi < fn_ir.blocks.size()
    blk = fn_ir.blocks[bi]
    kept = []
    ii = 0
    while ii < blk.insts.size()
      ins = blk.insts[ii]
      drop = false
      if ins.op == :alloca && promotable[ins.dst] && !has_load[ins.dst]
        drop = true
      elsif (ins.op == :store && ins.k1 == LLOP_VAL && promotable[ins.v1] && !has_load[ins.v1]) || (ins.op == :load && ins.k0 == LLOP_VAL && promotable[ins.v0] && !has_load[ins.v0])
        drop = true
      if !drop
        any_alloca_left = true if ins.op == :alloca
        kept.push(ins)
      ii += 1
    blk.insts = kept
    bi += 1
  fn_ir.alloca_bytes = 0 if !any_alloca_left
  nil

# ---- Pass 3: Constant Folding, Copy Propagation, `i128` Pack/Unpack & `--fast` FP ----

-> ll_eval_icmp_imm(pred, a, b, ty)
  va = ty == LLTY_I32 ? ((a << 32) >> 32) : (ty == LLTY_I1 ? (a & 1) : a)
  vb = ty == LLTY_I32 ? ((b << 32) >> 32) : (ty == LLTY_I1 ? (b & 1) : b)
  return (va == vb ? 1 : 0) if pred == :eq
  return (va != vb ? 1 : 0) if pred == :ne
  return (va <  vb ? 1 : 0) if pred == :slt
  return (va <= vb ? 1 : 0) if pred == :sle
  return (va >  vb ? 1 : 0) if pred == :sgt
  return (va >= vb ? 1 : 0) if pred == :sge
  two64 = (1 ## int) << 64
  ua = va < 0 ? ((va ## int) + two64) : (va ## int)
  ub = vb < 0 ? ((vb ## int) + two64) : (vb ## int)
  if ty == LLTY_I32
    ua = ua & 0xFFFFFFFF
    ub = ub & 0xFFFFFFFF
  return (ua <  ub ? 1 : 0) if pred == :ult
  return (ua <= ub ? 1 : 0) if pred == :ule
  return (ua >  ub ? 1 : 0) if pred == :ugt
  return (ua >= ub ? 1 : 0) if pred == :uge
  0

-> ll_bits_to_f64(bits)
  wvalue_from_bits((bits + 281474976710656) ## i64)

-> ll_f64_to_bits(fv)
  (wvalue_bits(fv) ## i64) - 281474976710656

-> ll_pass_const_fold(fn_ir, opt_cfg)
  return nil if fn_ir == nil
  fast_fp = opt_cfg != nil && opt_cfg.fast_math
  uses = fast_fp ? ll_count_uses(fn_ir) : nil
  defs = {}
  subst = {}

  bi = 0
  while bi < fn_ir.blocks.size()
    blk = fn_ir.blocks[bi]
    blk.phis.each ->(ph)
      defs[ph.dst] = ph if ph.dst >= 0
    kept = []
    ii = 0
    while ii < blk.insts.size()
      ins = blk.insts[ii]
      if ins.k0 == LLOP_VAL && subst[ins.v0] != nil
        r0 = ll_resolve_val_subst(subst, ins.k0, ins.v0); ins.k0 = r0[0]; ins.v0 = r0[1]
      if ins.k1 == LLOP_VAL && subst[ins.v1] != nil
        r1 = ll_resolve_val_subst(subst, ins.k1, ins.v1); ins.k1 = r1[0]; ins.v1 = r1[1]
      if ins.k2 == LLOP_VAL && subst[ins.v2] != nil
        r2 = ll_resolve_val_subst(subst, ins.k2, ins.v2); ins.k2 = r2[0]; ins.v2 = r2[1]

      op = ins.op
      ty = ins.ty
      folded = false

      if op == :copy
        subst[ins.dst] = [ins.k0, ins.v0]
        folded = true
      elsif op == :inttoptr || op == :ptrtoint
        subst[ins.dst] = [ins.k0, ins.v0]
        folded = true
      elsif (ty == LLTY_I64 || ty == LLTY_PTR || ty == LLTY_I32 || ty == LLTY_I1) && (op == :add || op == :sub || op == :mul || op == :and || op == :or || op == :xor || op == :shl || op == :lshr || op == :ashr)
        both_imm = (ins.k0 == LLOP_IMM && ins.k1 == LLOP_IMM)
        if both_imm && ty != LLTY_I32
          a = ins.v0; b = ins.v1; rv = 0
          rv = a + b if op == :add
          rv = a - b if op == :sub
          rv = a * b if op == :mul
          rv = a & b if op == :and
          rv = a | b if op == :or
          rv = a ^ b if op == :xor
          rv = (a << (b & 63)) if op == :shl
          rv = (((a ## u64) >> ((b & 63) ## u64)) ## i64) if op == :lshr
          rv = (a >> (b & 63)) if op == :ashr
          rv = rv & 1 if ty == LLTY_I1
          subst[ins.dst] = [LLOP_IMM, rv]
          folded = true
        elsif op == :add
          if ins.k1 == LLOP_IMM && ins.v1 == 0
            subst[ins.dst] = [ins.k0, ins.v0]; folded = true
          elsif ins.k0 == LLOP_IMM && ins.v0 == 0
            subst[ins.dst] = [ins.k1, ins.v1]; folded = true
        elsif op == :sub && ins.k1 == LLOP_IMM && ins.v1 == 0
          subst[ins.dst] = [ins.k0, ins.v0]; folded = true
        elsif op == :mul
          if ins.k1 == LLOP_IMM && ins.v1 == 1
            subst[ins.dst] = [ins.k0, ins.v0]; folded = true
          elsif ins.k0 == LLOP_IMM && ins.v0 == 1
            subst[ins.dst] = [ins.k1, ins.v1]; folded = true
          elsif (ins.k0 == LLOP_IMM && ins.v0 == 0) || (ins.k1 == LLOP_IMM && ins.v1 == 0)
            subst[ins.dst] = [LLOP_IMM, 0]; folded = true
        elsif op == :or || op == :xor
          if ins.k1 == LLOP_IMM && ins.v1 == 0
            subst[ins.dst] = [ins.k0, ins.v0]; folded = true
          elsif ins.k0 == LLOP_IMM && ins.v0 == 0
            subst[ins.dst] = [ins.k1, ins.v1]; folded = true
        elsif op == :and
          if (ins.k0 == LLOP_IMM && ins.v0 == 0) || (ins.k1 == LLOP_IMM && ins.v1 == 0)
            subst[ins.dst] = [LLOP_IMM, 0]; folded = true
          elsif ins.k1 == LLOP_IMM && ins.v1 == -1
            subst[ins.dst] = [ins.k0, ins.v0]; folded = true
        elsif (op == :shl || op == :lshr || op == :ashr) && ins.k1 == LLOP_IMM && ins.v1 == 0
          subst[ins.dst] = [ins.k0, ins.v0]; folded = true
      elsif op == :icmp && ty != LLTY_I128 && ins.k0 == LLOP_IMM && ins.k1 == LLOP_IMM
        subst[ins.dst] = [LLOP_IMM, ll_eval_icmp_imm(ins.pred, ins.v0, ins.v1, ty)]
        folded = true
      elsif op == :select && ins.k0 == LLOP_IMM
        subst[ins.dst] = (ins.v0 & 1) != 0 ? [ins.k1, ins.v1] : [ins.k2, ins.v2]
        folded = true
      elsif op == :zext && ins.k0 == LLOP_IMM && ins.ty != LLTY_I128
        v = ins.v0
        v = v & 1 if ins.ty2 == LLTY_I1
        v = v & 0xFF if ins.ty2 == LLTY_I8
        v = v & 0xFFFF if ins.ty2 == LLTY_I16
        v = v & 0xFFFFFFFF if ins.ty2 == LLTY_I32
        subst[ins.dst] = [LLOP_IMM, v]
        folded = true
      elsif op == :trunc && ins.ty == LLTY_I64 && ins.ty2 == LLTY_I128 && ins.k0 == LLOP_VAL
        # Scalarize packed `i128` (`or (shl hi128, 64), (zext i64 lo)`) from inlined `alwaysinline` helpers!
        src_d = defs[ins.v0]
        if src_d != nil && src_d.op == :or && src_d.ty == LLTY_I128 && src_d.k0 == LLOP_VAL && src_d.k1 == LLOP_VAL
          d0 = defs[src_d.v0]; d1 = defs[src_d.v1]
          if d0 != nil && d0.op == :shl && d0.k1 == LLOP_IMM && d0.v1 == 64 && d1 != nil && d1.op == :zext && d1.ty2 == LLTY_I64
            subst[ins.dst] = [d1.k0, d1.v0]
            folded = true
          elsif d1 != nil && d1.op == :shl && d1.k1 == LLOP_IMM && d1.v1 == 64 && d0 != nil && d0.op == :zext && d0.ty2 == LLTY_I64
            subst[ins.dst] = [d0.k0, d0.v0]
            folded = true
        elsif src_d != nil && src_d.op == :lshr && src_d.ty == LLTY_I128 && src_d.k1 == LLOP_IMM && src_d.v1 == 64 && src_d.k0 == LLOP_VAL
          or_d = defs[src_d.v0]
          if or_d != nil && or_d.op == :or && or_d.ty == LLTY_I128 && or_d.k0 == LLOP_VAL && or_d.k1 == LLOP_VAL
            d0 = defs[or_d.v0]; d1 = defs[or_d.v1]
            hi_sh = (d0 != nil && d0.op == :shl && d0.k1 == LLOP_IMM && d0.v1 == 64 && d1 != nil && d1.op == :zext && (d1.ty2 == LLTY_I64 || d1.ty2 == LLTY_I1)) ? d0 : ((d1 != nil && d1.op == :shl && d1.k1 == LLOP_IMM && d1.v1 == 64 && d0 != nil && d0.op == :zext && (d0.ty2 == LLTY_I64 || d0.ty2 == LLTY_I1)) ? d1 : nil)
            if hi_sh != nil && hi_sh.k0 == LLOP_VAL
              hz = defs[hi_sh.v0]
              if hz != nil && hz.op == :zext
                if hz.ty2 == LLTY_I64
                  subst[ins.dst] = [hz.k0, hz.v0]
                  folded = true
                elsif hz.ty2 == LLTY_I1
                  z64 = LLInst.new(:zext, ins.dst, LLTY_I64)
                  z64.ty2 = LLTY_I1; z64.k0 = hz.k0; z64.v0 = hz.v0
                  defs[ins.dst] = z64
                  kept.push(z64)
                  folded = true
      elsif fast_fp && ty == LLTY_F64 && (op == :fadd || op == :fsub || op == :fmul || op == :fdiv)
        if op == :fadd
          if ins.k1 == LLOP_IMM && ins.v1 == 0
            subst[ins.dst] = [ins.k0, ins.v0]; folded = true
          elsif ins.k0 == LLOP_IMM && ins.v0 == 0
            subst[ins.dst] = [ins.k1, ins.v1]; folded = true
          elsif ins.k0 == LLOP_VAL && defs[ins.v0] != nil && defs[ins.v0].op == :fmul && uses[ins.v0] == 1
            md = defs[ins.v0]
            fma = LLInst.new(:intrinsic, ins.dst, LLTY_F64)
            fma.pred = "fmuladd.f64"
            fma.extra = [[LLTY_F64, md.k0, md.v0], [LLTY_F64, md.k1, md.v1], [LLTY_F64, ins.k1, ins.v1]]
            defs[ins.dst] = fma; kept.push(fma); folded = true
          elsif ins.k1 == LLOP_VAL && defs[ins.v1] != nil && defs[ins.v1].op == :fmul && uses[ins.v1] == 1
            md = defs[ins.v1]
            fma = LLInst.new(:intrinsic, ins.dst, LLTY_F64)
            fma.pred = "fmuladd.f64"
            fma.extra = [[LLTY_F64, md.k0, md.v0], [LLTY_F64, md.k1, md.v1], [LLTY_F64, ins.k0, ins.v0]]
            defs[ins.dst] = fma; kept.push(fma); folded = true
        elsif op == :fsub && ins.k1 == LLOP_IMM && ins.v1 == 0
          subst[ins.dst] = [ins.k0, ins.v0]; folded = true
        elsif op == :fmul
          one_bits = 0x3FF0000000000000
          if ins.k1 == LLOP_IMM && ins.v1 == one_bits
            subst[ins.dst] = [ins.k0, ins.v0]; folded = true
          elsif ins.k0 == LLOP_IMM && ins.v0 == one_bits
            subst[ins.dst] = [ins.k1, ins.v1]; folded = true
        elsif op == :fdiv && ins.k1 == LLOP_IMM && ins.v1 != 0
          fb = ll_bits_to_f64(ins.v1)
          if fb != ~0.0
            rec = ~1.0 / fb
            if rec == rec && rec != (~1.0 / ~0.0) && rec != (~-1.0 / ~0.0)
              ins.op = :fmul
              ins.v1 = ll_f64_to_bits(rec)

      if !folded
        defs[ins.dst] = ins if ins.dst >= 0
        kept.push(ins)
      ii += 1
    blk.insts = kept
    bi += 1

  ll_apply_subst_to_func(fn_ir, subst)
  nil

# ---- Pass 4: Jump Threading & Constant Branch Simplification ----

-> ll_remove_phi_pred_edge(blk, dead_pred_bid)
  pi = 0
  while pi < blk.phis.size()
    prs = blk.phis[pi].extra
    kept = []
    j = 0
    while j < prs.size()
      kept.push(prs[j]) if prs[j][0] != dead_pred_bid
      j += 1
    blk.phis[pi].extra = kept
    pi += 1
  nil

# Can edge `pred_bid -> mid_bid` thread directly to `succ_bid` (`mid` has 0 PHIs and `[br succ_bid]`)?
# Safe iff `succ_bid` has NO PHIs, OR `succ_bid` does not already have a PHI entry from `pred_bid`!
-> ll_can_thread_trampoline?(fn_ir, pred_bid, mid_bid, succ_bid)
  return false if succ_bid == mid_bid || pred_bid == mid_bid
  sblk = fn_ir.blocks[succ_bid]
  return true if sblk.phis.size() == 0
  pi = 0
  while pi < sblk.phis.size()
    prs = sblk.phis[pi].extra
    j = 0
    while j < prs.size()
      return false if prs[j][0] == pred_bid
      j += 1
    pi += 1
  true

-> ll_add_phi_edge_from_trampoline(fn_ir, pred_bid, mid_bid, succ_bid)
  sblk = fn_ir.blocks[succ_bid]
  pi = 0
  while pi < sblk.phis.size()
    prs = sblk.phis[pi].extra
    j = 0
    while j < prs.size()
      if prs[j][0] == mid_bid
        prs.push([pred_bid, prs[j][1], prs[j][2]])
        break
      j += 1
    pi += 1
  nil

-> ll_pass_jump_threading(fn_ir)
  return nil if fn_ir == nil || fn_ir.blocks.size() <= 1

  # 1. Fold constant `cond_br` and `t_true == t_false` `cond_br`
  bi = 0
  while bi < fn_ir.blocks.size()
    blk = fn_ir.blocks[bi]
    if blk.insts.size() > 0
      term = blk.insts[blk.insts.size() - 1]
      if term.op == :cond_br
        if term.v1 == term.v2
          nb = LLInst.new(:br, -1, LLTY_VOID); nb.v0 = term.v1
          blk.insts[blk.insts.size() - 1] = nb
        elsif term.k0 == LLOP_IMM
          taken = (term.v0 & 1) != 0 ? term.v1 : term.v2
          dropped = (term.v0 & 1) != 0 ? term.v2 : term.v1
          ll_remove_phi_pred_edge(fn_ir.blocks[dropped], bi) if dropped != taken
          nb = LLInst.new(:br, -1, LLTY_VOID); nb.v0 = taken
          blk.insts[blk.insts.size() - 1] = nb
    bi += 1

  # 2. Thread branches through empty jump-only trampoline blocks (`phis == 0 && insts == [br succ]`)
  bi = 0
  while bi < fn_ir.blocks.size()
    blk = fn_ir.blocks[bi]
    if blk.insts.size() > 0
      term = blk.insts[blk.insts.size() - 1]
      if term.op == :br
        mid = term.v0
        mblk = fn_ir.blocks[mid]
        if mid > 0 && mblk.phis.size() == 0 && mblk.insts.size() == 1 && mblk.insts[0].op == :br
          succ = mblk.insts[0].v0
          if ll_can_thread_trampoline?(fn_ir, bi, mid, succ)
            ll_add_phi_edge_from_trampoline(fn_ir, bi, mid, succ)
            term.v0 = succ
      elsif term.op == :cond_br
        mid1 = term.v1
        mb1 = fn_ir.blocks[mid1]
        if mid1 > 0 && mb1.phis.size() == 0 && mb1.insts.size() == 1 && mb1.insts[0].op == :br
          succ1 = mb1.insts[0].v0
          if succ1 != term.v2 && ll_can_thread_trampoline?(fn_ir, bi, mid1, succ1)
            ll_add_phi_edge_from_trampoline(fn_ir, bi, mid1, succ1)
            term.v1 = succ1
        mid2 = term.v2
        mb2 = fn_ir.blocks[mid2]
        if mid2 > 0 && mb2.phis.size() == 0 && mb2.insts.size() == 1 && mb2.insts[0].op == :br
          succ2 = mb2.insts[0].v0
          if succ2 != term.v1 && ll_can_thread_trampoline?(fn_ir, bi, mid2, succ2)
            ll_add_phi_edge_from_trampoline(fn_ir, bi, mid2, succ2)
            term.v2 = succ2
    bi += 1

  # 3. Prune dead incoming PHI edges from unreachable blocks & fold single-incoming PHIs!
  reach = Array.new(fn_ir.blocks.size(), false)
  reach[0] = true
  wl = [0]
  wi = 0
  while wi < wl.size()
    b = fn_ir.blocks[wl[wi]]
    wi += 1
    if b.insts.size() > 0
      t = b.insts[b.insts.size() - 1]
      if t.op == :br
        if !reach[t.v0]
          reach[t.v0] = true; wl.push(t.v0)
      elsif t.op == :cond_br
        if !reach[t.v1]
          reach[t.v1] = true; wl.push(t.v1)
        if !reach[t.v2]
          reach[t.v2] = true; wl.push(t.v2)
      elsif t.op == :switch
        if !reach[t.v1]
          reach[t.v1] = true; wl.push(t.v1)
        ci = 0
        while ci < t.extra.size()
          sb = t.extra[ci][1]
          if !reach[sb]
            reach[sb] = true; wl.push(sb)
          ci += 1

  subst = {}
  bi = 0
  while bi < fn_ir.blocks.size()
    blk = fn_ir.blocks[bi]
    if !reach[bi]
      blk.phis = []
      blk.insts = [LLInst.new(:unreachable, -1, LLTY_VOID)]
    elsif blk.phis.size() > 0
      kept_phis = []
      pi = 0
      while pi < blk.phis.size()
        ph = blk.phis[pi]
        live_prs = []
        j = 0
        while j < ph.extra.size()
          live_prs.push(ph.extra[j]) if reach[ph.extra[j][0]]
          j += 1
        if live_prs.size() == 1
          subst[ph.dst] = [live_prs[0][1], live_prs[0][2]]
        else
          ph.extra = live_prs
          kept_phis.push(ph)
        pi += 1
      blk.phis = kept_phis
    bi += 1

  ll_apply_subst_to_func(fn_ir, subst)
  nil

# ---- Pass 5: Hash-Based Value Numbering (GVN / CSE) ----

-> ll_gvn_key(ins)
  op = ins.op
  return nil if !ll_is_pure_inst?(ins) || op == :copy || op == :intrinsic || op == :extractvalue || op == :extractelement
  if op == :gep
    return nil if ins.extra != nil   # keep simple constant-offset GEP keys compact and fast
    return "gep:" + ins.k0.to_s() + ":" + ins.v0.to_s() + ":" + ins.v1.to_s()
  k0 = ins.k0; v0 = ins.v0
  k1 = ins.k1; v1 = ins.v1
  # Canonicalize commutative ops
  if op == :add || op == :mul || op == :and || op == :or || op == :xor || op == :umulh
    if k0 > k1 || (k0 == k1 && v0 > v1)
      tk = k0; tv = v0; k0 = k1; v0 = v1; k1 = tk; v1 = tv
  op.to_s() + ":" + ins.ty.to_s() + ":" + ins.ty2.to_s() + ":" + (ins.pred != nil ? ins.pred.to_s() : "") + ":" + k0.to_s() + ":" + v0.to_s() + ":" + k1.to_s() + ":" + v1.to_s() + ":" + ins.k2.to_s() + ":" + ins.v2.to_s()

-> ll_pass_gvn(fn_ir)
  return nil if fn_ir == nil || fn_ir.blocks.size() == 0
  entry_tbl = {}
  subst = {}

  bi = 0
  while bi < fn_ir.blocks.size()
    blk = fn_ir.blocks[bi]
    local_tbl = {}
    kept = []
    ii = 0
    while ii < blk.insts.size()
      ins = blk.insts[ii]
      if ins.k0 == LLOP_VAL && subst[ins.v0] != nil
        r0 = ll_resolve_val_subst(subst, ins.k0, ins.v0); ins.k0 = r0[0]; ins.v0 = r0[1]
      if ins.k1 == LLOP_VAL && subst[ins.v1] != nil
        r1 = ll_resolve_val_subst(subst, ins.k1, ins.v1); ins.k1 = r1[0]; ins.v1 = r1[1]
      if ins.k2 == LLOP_VAL && subst[ins.v2] != nil
        r2 = ll_resolve_val_subst(subst, ins.k2, ins.v2); ins.k2 = r2[0]; ins.v2 = r2[1]

      key = ins.dst >= 0 ? ll_gvn_key(ins) : nil
      if key != nil
        dom_hit = entry_tbl[key]
        loc_hit = local_tbl[key]
        if dom_hit != nil
          subst[ins.dst] = [LLOP_VAL, dom_hit]
        elsif loc_hit != nil
          subst[ins.dst] = [LLOP_VAL, loc_hit]
        else
          if bi == 0
            entry_tbl[key] = ins.dst
          else
            local_tbl[key] = ins.dst
          kept.push(ins)
      else
        kept.push(ins)
      ii += 1
    blk.insts = kept
    bi += 1

  ll_apply_subst_to_func(fn_ir, subst)
  nil

# ---- Pass 6: Loop-Invariant Code Motion (LICM toDominating Entry) ----

-> ll_op_in_entry?(k, v, in_entry, mod_info = nil)
  if k == LLOP_SYM
    return false if mod_info != nil && mod_info.sym_kind[v] == LLSYM_TLS
    return true
  return true if k != LLOP_VAL
  in_entry[v] == true

-> ll_inst_operands_in_entry?(ins, in_entry, mod_info = nil)
  return false if !ll_op_in_entry?(ins.k0, ins.v0, in_entry, mod_info)
  return false if !ll_op_in_entry?(ins.k1, ins.v1, in_entry, mod_info)
  return false if !ll_op_in_entry?(ins.k2, ins.v2, in_entry, mod_info)
  if ins.op == :gep && ins.extra != nil
    ai = 0
    while ai < ins.extra.size()
      return false if !ll_op_in_entry?(ins.extra[ai][0], ins.extra[ai][1], in_entry, mod_info)
      ai += 1
  elsif ins.extra != nil
    return false
  true

-> ll_pass_licm(fn_ir, mod_info = nil)
  return nil if fn_ir == nil || fn_ir.blocks.size() <= 1
  entry = fn_ir.blocks[0]
  return nil if entry.insts.size() == 0
  term = entry.insts[entry.insts.size() - 1]
  return nil if term.op != :br && term.op != :cond_br

  # Mark all blocks inside natural back-edge loops (`hdr .. bi` where `0 < hdr <= bi`)
  in_loop = Array.new(fn_ir.blocks.size(), false)
  bi = 1
  while bi < fn_ir.blocks.size()
    b = fn_ir.blocks[bi]
    if b.insts.size() > 0
      t = b.insts[b.insts.size() - 1]
      if t.op == :br && t.v0 <= bi && t.v0 > 0
        ki = t.v0
        while ki <= bi
          in_loop[ki] = true
          ki += 1
      elsif t.op == :cond_br
        if t.v1 <= bi && t.v1 > 0
          ki = t.v1
          while ki <= bi
            in_loop[ki] = true
            ki += 1
        if t.v2 <= bi && t.v2 > 0
          ki = t.v2
          while ki <= bi
            in_loop[ki] = true
            ki += 1
    bi += 1

  in_entry = Array.new(fn_ir.n_vals, false)
  pi = 0
  while pi < fn_ir.n_params
    in_entry[pi] = true
    pi += 1
  ei = 0
  while ei < entry.insts.size() - 1
    d = entry.insts[ei].dst
    in_entry[d] = true if d >= 0
    ei += 1

  hoisted = []
  bi = 1
  while bi < fn_ir.blocks.size()
    if in_loop[bi]
      blk = fn_ir.blocks[bi]
      kept = []
      ii = 0
      while ii < blk.insts.size()
        ins = blk.insts[ii]
        op = ins.op
        # Hoist trap-free pure scalar/comparison/address arithmetic whose operands are defined in entry!
        safe_op = (op == :gep || op == :icmp || op == :select || op == :add || op == :sub || op == :mul || op == :and || op == :or || op == :xor || op == :shl || op == :lshr || op == :ashr || op == :zext || op == :sext || op == :trunc) && ins.ty != LLTY_I128 && ins.ty != LLTY_V2I64
        if ins.dst >= 0 && safe_op && ll_inst_operands_in_entry?(ins, in_entry, mod_info)
          in_entry[ins.dst] = true
          hoisted.push(ins)
        else
          kept.push(ins)
        ii += 1
      blk.insts = kept
    bi += 1

  if hoisted.size() > 0
    new_e = []
    ei = 0
    while ei < entry.insts.size() - 1
      new_e.push(entry.insts[ei])
      ei += 1
    hi = 0
    while hi < hoisted.size()
      new_e.push(hoisted[hi])
      hi += 1
    new_e.push(term)
    entry.insts = new_e
  nil

# ---- Pass 7: Strength Reduction & Granlund-Montgomery Constant Division (`:umulh`) ----

-> ll_is_pow2_pos?(v)
  v > 0 && (v & (v - 1)) == 0

-> ll_ctz_pow2(v)
  sh = 0
  x = v
  while x > 1
    x = x >> 1
    sh += 1
  sh

-> ll_pass_strength_reduce(fn_ir, opt_cfg)
  return nil if fn_ir == nil
  do_magic_div = opt_cfg == nil || opt_cfg.opt_level >= 2

  bi = 0
  while bi < fn_ir.blocks.size()
    blk = fn_ir.blocks[bi]
    rebuilt = []
    ii = 0
    while ii < blk.insts.size()
      ins = blk.insts[ii]
      op = ins.op
      ty = ins.ty
      replaced = false

      if (ty == LLTY_I64 || ty == LLTY_I32) && op == :mul
        if ins.k1 == LLOP_IMM && ins.v1 > 1 && ll_is_pow2_pos?(ins.v1)
          ins.op = :shl
          ins.v1 = ll_ctz_pow2(ins.v1)
        elsif ins.k0 == LLOP_IMM && ins.v0 > 1 && ll_is_pow2_pos?(ins.v0)
          sh = ll_ctz_pow2(ins.v0)
          ins.op = :shl
          ins.k0 = ins.k1; ins.v0 = ins.v1
          ins.k1 = LLOP_IMM; ins.v1 = sh
      elsif ty == LLTY_I64 && (op == :udiv || op == :urem) && ins.k1 == LLOP_IMM && ins.v1 != 0
        is_rem = (op == :urem)
        d_raw = ins.v1
        if d_raw == 1
          if is_rem
            rebuilt.push(ll_make_copy_inst(ins.dst, LLTY_I64, LLOP_IMM, 0))
          else
            rebuilt.push(ll_make_copy_inst(ins.dst, LLTY_I64, ins.k0, ins.v0))
          replaced = true
        elsif d_raw > 1 && ll_is_pow2_pos?(d_raw)
          if is_rem
            ins.op = :and
            ins.v1 = d_raw - 1
          else
            ins.op = :lshr
            ins.v1 = ll_ctz_pow2(d_raw)
        elsif do_magic_div
          mg = cinder_udiv_magic_u64(d_raw)
          if mg != nil
            q_id = is_rem ? fn_ir.alloc_anon_val(LLTY_I64) : ins.dst
            if mg[0] == :shr
              sh_i = LLInst.new(:lshr, q_id, LLTY_I64)
              sh_i.k0 = ins.k0; sh_i.v0 = ins.v0
              sh_i.k1 = LLOP_IMM; sh_i.v1 = mg[2]
              rebuilt.push(sh_i)
            elsif mg[0] == :mulhi_shr
              if mg[2] == 0
                mh_i = LLInst.new(:umulh, q_id, LLTY_I64)
                mh_i.k0 = ins.k0; mh_i.v0 = ins.v0
                mh_i.k1 = LLOP_IMM; mh_i.v1 = mg[1]
                rebuilt.push(mh_i)
              else
                mh_id = fn_ir.alloc_anon_val(LLTY_I64)
                mh_i = LLInst.new(:umulh, mh_id, LLTY_I64)
                mh_i.k0 = ins.k0; mh_i.v0 = ins.v0
                mh_i.k1 = LLOP_IMM; mh_i.v1 = mg[1]
                rebuilt.push(mh_i)
                sh_i = LLInst.new(:lshr, q_id, LLTY_I64)
                sh_i.k0 = LLOP_VAL; sh_i.v0 = mh_id
                sh_i.k1 = LLOP_IMM; sh_i.v1 = mg[2]
                rebuilt.push(sh_i)
            else
              # `:mulhi_add_shr`: `t1 = umulh(x, m); q = (t1 + ((x - t1) >>u 1)) >>u sh2`
              t1_id = fn_ir.alloc_anon_val(LLTY_I64)
              mh_i = LLInst.new(:umulh, t1_id, LLTY_I64)
              mh_i.k0 = ins.k0; mh_i.v0 = ins.v0
              mh_i.k1 = LLOP_IMM; mh_i.v1 = mg[1]
              rebuilt.push(mh_i)
              d_id = fn_ir.alloc_anon_val(LLTY_I64)
              sb_i = LLInst.new(:sub, d_id, LLTY_I64)
              sb_i.k0 = ins.k0; sb_i.v0 = ins.v0
              sb_i.k1 = LLOP_VAL; sb_i.v1 = t1_id
              rebuilt.push(sb_i)
              h_id = fn_ir.alloc_anon_val(LLTY_I64)
              ls1 = LLInst.new(:lshr, h_id, LLTY_I64)
              ls1.k0 = LLOP_VAL; ls1.v0 = d_id
              ls1.k1 = LLOP_IMM; ls1.v1 = 1
              rebuilt.push(ls1)
              if mg[3] == 0
                ad_i = LLInst.new(:add, q_id, LLTY_I64)
                ad_i.k0 = LLOP_VAL; ad_i.v0 = t1_id
                ad_i.k1 = LLOP_VAL; ad_i.v1 = h_id
                rebuilt.push(ad_i)
              else
                s_id = fn_ir.alloc_anon_val(LLTY_I64)
                ad_i = LLInst.new(:add, s_id, LLTY_I64)
                ad_i.k0 = LLOP_VAL; ad_i.v0 = t1_id
                ad_i.k1 = LLOP_VAL; ad_i.v1 = h_id
                rebuilt.push(ad_i)
                ls2 = LLInst.new(:lshr, q_id, LLTY_I64)
                ls2.k0 = LLOP_VAL; ls2.v0 = s_id
                ls2.k1 = LLOP_IMM; ls2.v1 = mg[3]
                rebuilt.push(ls2)
            if is_rem
              p_id = fn_ir.alloc_anon_val(LLTY_I64)
              ml_i = LLInst.new(:mul, p_id, LLTY_I64)
              ml_i.k0 = LLOP_VAL; ml_i.v0 = q_id
              ml_i.k1 = LLOP_IMM; ml_i.v1 = d_raw
              rebuilt.push(ml_i)
              rm_i = LLInst.new(:sub, ins.dst, LLTY_I64)
              rm_i.k0 = ins.k0; rm_i.v0 = ins.v0
              rm_i.k1 = LLOP_VAL; rm_i.v1 = p_id
              rebuilt.push(rm_i)
            replaced = true

      rebuilt.push(ins) if !replaced
      ii += 1
    blk.insts = rebuilt
    bi += 1
  nil

# ---- Pass 8: Dead Pure SSA & Dead PHI Elimination (DCE) ----

-> ll_dec_inst_uses(ins, uses)
  uses[ins.v0] = uses[ins.v0] - 1 if ins.k0 == LLOP_VAL
  uses[ins.v1] = uses[ins.v1] - 1 if ins.k1 == LLOP_VAL
  uses[ins.v2] = uses[ins.v2] - 1 if ins.k2 == LLOP_VAL
  if ins.extra != nil
    op = ins.op
    if op == :intrinsic
      ai = 0
      while ai < ins.extra.size()
        ca = ins.extra[ai]
        uses[ca[2]] = uses[ca[2]] - 1 if ca[1] == LLOP_VAL
        ai += 1
    elsif op == :gep
      ai = 0
      while ai < ins.extra.size()
        st = ins.extra[ai]
        uses[st[1]] = uses[st[1]] - 1 if st[0] == LLOP_VAL
        ai += 1
  nil

-> ll_pass_dce(fn_ir)
  return nil if fn_ir == nil
  uses = ll_count_uses(fn_ir)
  changed = true
  rounds = 0
  while changed && rounds < 6
    changed = false
    rounds += 1
    bi = fn_ir.blocks.size() - 1
    while bi >= 0
      blk = fn_ir.blocks[bi]
      rev = []
      ii = blk.insts.size() - 1
      while ii >= 0
        ins = blk.insts[ii]
        if ins.dst >= 0 && uses[ins.dst] <= 0 && ll_is_pure_inst?(ins)
          ll_dec_inst_uses(ins, uses)
          changed = true
        else
          rev.push(ins)
        ii -= 1
      fwd = []
      ri = rev.size() - 1
      while ri >= 0
        fwd.push(rev[ri])
        ri -= 1
      blk.insts = fwd

      if blk.phis.size() > 0
        kept_p = []
        pi = 0
        while pi < blk.phis.size()
          ph = blk.phis[pi]
          if ph.dst >= 0 && uses[ph.dst] <= 0
            j = 0
            while j < ph.extra.size()
              pr = ph.extra[j]
              uses[pr[2]] = uses[pr[2]] - 1 if pr[1] == LLOP_VAL
              j += 1
            changed = true
          else
            kept_p.push(ph)
          pi += 1
        blk.phis = kept_p
      bi -= 1
  nil

# ---- Top-Level Per-Function AOT Optimization Pipeline ----

-> ll_run_pass_timed(fn_ir, cfg, pass_name, fn_cb)
  if cfg != nil && cfg.print_passes
    b0 = ll_count_func_insts(fn_ir)
    t0 = clock
    fn_cb.call()
    dt_us = ((clock - t0) * ~1000000.0).to_i()
    b1 = ll_count_func_insts(fn_ir)
    cfg.record_stat(pass_name, b0, b1, dt_us)
  else
    fn_cb.call()
  nil

-> ll_opt_function(fn_ir, inl_ctx, opt_cfg)
  cfg = opt_cfg != nil ? opt_cfg : CinderOptConfig.new(2)

  # 1. Mandatory `alwaysinline` (all levels) + Heuristic `-finline` (`-O1+`)
  if inl_ctx != nil && (cfg.pass_enabled?("always-inline") || cfg.pass_enabled?("inline"))
    pname = cfg.pass_enabled?("inline") ? "inline" : "always-inline"
    ll_run_pass_timed(fn_ir, cfg, pname, ->() ll_pass_inline(fn_ir, inl_ctx, cfg))

  # At `-O0` (without explicit pass overrides or `--fast`), stop right after `alwaysinline`!
  if cfg.opt_level <= 0 && cfg.explicit_passes == nil && cfg.overrides.size() == 0 && !cfg.fast_math
    ll_assign_stack_slots(fn_ir)
    return fn_ir

  if cfg.pass_enabled?("sroa")
    ll_run_pass_timed(fn_ir, cfg, "sroa", ->() ll_pass_sroa(fn_ir))
  if cfg.pass_enabled?("const-fold") || cfg.fast_math
    ll_run_pass_timed(fn_ir, cfg, "const-fold", ->() ll_pass_const_fold(fn_ir, cfg))
  if cfg.pass_enabled?("jump-threading")
    ll_run_pass_timed(fn_ir, cfg, "jump-threading", ->() ll_pass_jump_threading(fn_ir))
  if cfg.pass_enabled?("gvn")
    ll_run_pass_timed(fn_ir, cfg, "gvn", ->() ll_pass_gvn(fn_ir))
  if cfg.pass_enabled?("licm")
    minfo = inl_ctx != nil ? inl_ctx.mod_info : nil
    ll_run_pass_timed(fn_ir, cfg, "licm", ->() ll_pass_licm(fn_ir, minfo))
  if cfg.pass_enabled?("strength-reduce")
    ll_run_pass_timed(fn_ir, cfg, "strength-reduce", ->() ll_pass_strength_reduce(fn_ir, cfg))
  if cfg.pass_enabled?("const-fold")
    ll_run_pass_timed(fn_ir, cfg, "const-fold-2", ->() ll_pass_const_fold(fn_ir, cfg))
  if cfg.pass_enabled?("dce")
    ll_run_pass_timed(fn_ir, cfg, "dce", ->() ll_pass_dce(fn_ir))
  if cfg.opt_level >= 3
    if cfg.pass_enabled?("jump-threading")
      ll_run_pass_timed(fn_ir, cfg, "O3-jump-threading", ->() ll_pass_jump_threading(fn_ir))
    if cfg.pass_enabled?("gvn")
      ll_run_pass_timed(fn_ir, cfg, "O3-gvn", ->() ll_pass_gvn(fn_ir))
    if cfg.pass_enabled?("dce")
      ll_run_pass_timed(fn_ir, cfg, "O3-dce", ->() ll_pass_dce(fn_ir))

  ll_assign_stack_slots(fn_ir)
  fn_ir
