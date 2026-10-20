# Lowering / pipeline_fusion — fused map / select / reject / reduce / detect.
#
# fuse_pipeline flattens nested Map/Calc AST into {base, stages[], terminal};
# lower_pipeline emits ONE loop (no intermediate arrays), or a closed-form
# ranged sum via poly_sum when the chain is polynomial over a range.
# Extracted from calls.w; dispatched from lower_expression (:map / :calc).
#
# Depends on earlier workers + poly_sum (poly_of_expr / emit_poly_ranged_sum).
# This file deliberately has no `use` directives — see pass_registry.w.

# === Fused pipeline lowering (map / select / reject / reduce / detect) ===
#
# A `source /sq /select(:even?) :sum` pipeline is parsed into nested Map
# nodes plus an optional terminal Calc (reduce/detect). fuse_pipeline
# flattens that into {base, stages[], terminal}; lower_pipeline emits ONE
# counted loop over the base (array or range) with no intermediate arrays:
# each stage transforms or filters the value in registers, and the terminal
# folds (reduce) or short-circuits (detect). Known scalar ops (sq/cube/
# negate, sum/product) lower to inline arithmetic via synthetic BinaryOp/
# UnaryOp AST that reuses lower_binary_op; everything else falls back to a
# per-element method call (correct, still fused).

-> fuse_pipeline(node)
  terminal_op = nil
  cur = node
  if ast_kind(cur) == :calc
    terminal_op = "" + ast_get(cur, :op)
    cur = ast_get(cur, :source)
  outer = []
  while is_ast_node?(cur) && ast_kind(cur) == :map
    outer.push(cur)
    cur = ast_get(cur, :source)
  # Unwrap a `.lazy` marker at the base: `(1..100).lazy/sq` parses as
  # Map(Call(range, "lazy", []), …), so the fused base is the lazy Call.
  # `.lazy` is purely informative (fusion already avoids intermediate
  # arrays); strip it so the base is the real range/array source.
  if is_ast_node?(cur) && ast_kind(cur) == :call && ast_get(cur, :name) == "lazy" && cur.receiver != nil
    a = ast_get(cur, :args)
    if a == nil || a.size() == 0
      cur = cur.receiver
  # outer holds outermost-first; reverse to application order (innermost first)
  stages = []
  i = outer.size() - 1
  while i >= 0
    stages.push(outer[i])
    i -= 1
  {base: cur, stages: stages, terminal: terminal_op}

# Build the synthetic transform AST for a map stage applied to `cur_name`.
# Known elementwise calcs inline; otherwise call the method on the element.
-> pipeline_transform_node(name, args, cur_name)
  if name == "sq"
    return Tungsten:AST:BinaryOp.new(Tungsten:AST:Var.new(cur_name), :STAR, Tungsten:AST:Var.new(cur_name))
  if name == "cube"
    inner = Tungsten:AST:BinaryOp.new(Tungsten:AST:Var.new(cur_name), :STAR, Tungsten:AST:Var.new(cur_name))
    return Tungsten:AST:BinaryOp.new(inner, :STAR, Tungsten:AST:Var.new(cur_name))
  if name == "negate"
    return Tungsten:AST:UnaryOp.new(:MINUS, Tungsten:AST:Var.new(cur_name))
  # Predicates used as a map (`/even?:count`) inline to arithmetic, same as
  # when used as a filter (pipeline_pred_node) — otherwise the fused loop emits
  # a runtime `cur.even?` call, and even?/odd?/etc. have no runtime IC handler
  # (they're inline-only on the compiled path).
  if name == "even?"
    return Tungsten:AST:BinaryOp.new(Tungsten:AST:BinaryOp.new(Tungsten:AST:Var.new(cur_name), :PERCENT, Tungsten:AST:Int.new(2)), :EQ, Tungsten:AST:Int.new(0))
  if name == "odd?"
    return Tungsten:AST:BinaryOp.new(Tungsten:AST:BinaryOp.new(Tungsten:AST:Var.new(cur_name), :PERCENT, Tungsten:AST:Int.new(2)), :NEQ, Tungsten:AST:Int.new(0))
  if name == "zero?"
    return Tungsten:AST:BinaryOp.new(Tungsten:AST:Var.new(cur_name), :EQ, Tungsten:AST:Int.new(0))
  if name == "positive?"
    return Tungsten:AST:BinaryOp.new(Tungsten:AST:Var.new(cur_name), :GT, Tungsten:AST:Int.new(0))
  if name == "negative?"
    return Tungsten:AST:BinaryOp.new(Tungsten:AST:Var.new(cur_name), :LT, Tungsten:AST:Int.new(0))
  Tungsten:AST:Call.new(Tungsten:AST:Var.new(cur_name), name, args, nil)

# Build the predicate expression for a select/reject/detect stage. Common
# numeric predicates inline to arithmetic so they fuse without a method
# call; anything else falls back to `cur.predname(args)`. `func` is the
# Call(nil, predname, args) the parser produced.
-> pipeline_pred_node(func, cur_name)
  pname = ast_get(func, :name)
  if pname == "even?"
    return Tungsten:AST:BinaryOp.new(Tungsten:AST:BinaryOp.new(Tungsten:AST:Var.new(cur_name), :PERCENT, Tungsten:AST:Int.new(2)), :EQ, Tungsten:AST:Int.new(0))
  if pname == "odd?"
    return Tungsten:AST:BinaryOp.new(Tungsten:AST:BinaryOp.new(Tungsten:AST:Var.new(cur_name), :PERCENT, Tungsten:AST:Int.new(2)), :NEQ, Tungsten:AST:Int.new(0))
  if pname == "zero?"
    return Tungsten:AST:BinaryOp.new(Tungsten:AST:Var.new(cur_name), :EQ, Tungsten:AST:Int.new(0))
  if pname == "positive?"
    return Tungsten:AST:BinaryOp.new(Tungsten:AST:Var.new(cur_name), :GT, Tungsten:AST:Int.new(0))
  if pname == "negative?"
    return Tungsten:AST:BinaryOp.new(Tungsten:AST:Var.new(cur_name), :LT, Tungsten:AST:Int.new(0))
  Tungsten:AST:Call.new(Tungsten:AST:Var.new(cur_name), pname, ast_get(func, :args), nil)

# Build the per-element reduce combine `acc <op> cur`. Known reduces inline
# (sum/product as arithmetic, min/max as a comparison-select); anything else
# falls back to `acc.op(cur)` (the classic reduce desugar).
-> pipeline_reduce_node(op, acc_name, cur_name)
  if op == "sum"
    return Tungsten:AST:BinaryOp.new(Tungsten:AST:Var.new(acc_name), :PLUS, Tungsten:AST:Var.new(cur_name))
  if op == "product"
    return Tungsten:AST:BinaryOp.new(Tungsten:AST:Var.new(acc_name), :STAR, Tungsten:AST:Var.new(cur_name))
  if op == "min"
    return Tungsten:AST:If.new(Tungsten:AST:BinaryOp.new(Tungsten:AST:Var.new(cur_name), :LT, Tungsten:AST:Var.new(acc_name)), [Tungsten:AST:Var.new(cur_name)], [], [Tungsten:AST:Var.new(acc_name)])
  if op == "max"
    return Tungsten:AST:If.new(Tungsten:AST:BinaryOp.new(Tungsten:AST:Var.new(cur_name), :GT, Tungsten:AST:Var.new(acc_name)), [Tungsten:AST:Var.new(cur_name)], [], [Tungsten:AST:Var.new(acc_name)])
  # count: add 1 per truthy element. After a predicate map (`/prime?:count`)
  # the elements are booleans, so this counts the matches. Pairs with the
  # `(cur ? 1 : 0)` seed below so the accumulator starts from 0, not the first
  # element. Consistent with Enumerable#count(:predicate).
  if op == "count"
    inc = Tungsten:AST:BinaryOp.new(Tungsten:AST:Var.new(acc_name), :PLUS, Tungsten:AST:Int.new(1))
    return Tungsten:AST:If.new(Tungsten:AST:Var.new(cur_name), [inc], [], [Tungsten:AST:Var.new(acc_name)])
  if op == "__size"
    return Tungsten:AST:BinaryOp.new(Tungsten:AST:Var.new(acc_name), :PLUS, Tungsten:AST:Int.new(1))
  Tungsten:AST:Call.new(Tungsten:AST:Var.new(acc_name), op, [Tungsten:AST:Var.new(cur_name)], nil)

-> bind_slot_value(ctx, wfn, name, value_reg)
  ptr = ensure_var_slot(wfn, name)
  emit_wire_store_i64(wfn, ptr, value_reg)
  ctx[:bindings][name] = nil
  ctx[:var_types][name] = nil
  ptr

# Bind the fused loop's element var to a stage value. A :raw_f64 value stays
# unboxed in the slot (var_types :f64, the machine-float slot convention from
# lower_var) so later stages and the reduce combine keep lowering on raw
# doubles; anything else boxes into an ordinary WValue slot as before.
# Returns the bound register (raw double or boxed i64 — the caller reads
# ctx[:var_types][name] == :f64 to know which).
-> pipeline_bind_cur(ctx, wfn, name, tval)
  if tval[:type] == :raw_f64
    ptr = ensure_var_slot(wfn, name)
    emit_wire_dynamic_2(wfn, :store_double, :value, tval[:value], :ptr, ptr)
    ctx[:bindings][name] = nil
    ctx[:var_types][name] = :f64
    return tval[:value]
  reg = ensure_i64_value(wfn, tval)
  bind_slot_value(ctx, wfn, name, reg)
  reg

-> lower_pipeline_block_stage(ctx, wfn, sfunc, cur_name, cur_reg, uid, si)
  bparams = ast_get(sfunc, :params)
  bbody = ast_get(sfunc, :body)
  bp_name = nil
  if bparams != nil && bparams.size() >= 1
    p0 = bparams[0]
    if is_ast_node?(p0)
      bp_name = "" + p0.name
    else
      bp_name = "" + p0
  saved_slot = nil
  saved_slot_type = nil
  saved_has_vtype = false
  saved_vtype = nil
  saved_binding = nil
  saved_unboxed = nil
  if bp_name != nil
    saved_slot = wfn[:var_slots][bp_name]
    saved_slot_type = wfn[:var_slot_types][bp_name]
    saved_has_vtype = ctx[:var_types].has_key?(bp_name)
    if saved_has_vtype
      saved_vtype = ctx[:var_types][bp_name]
    saved_binding = ctx[:bindings][bp_name]
    if ctx[:unboxed_vars] != nil
      saved_unboxed = ctx[:unboxed_vars][bp_name]
      ctx[:unboxed_vars][bp_name] = nil
    p_key = "__pipe_bp." + uid + "." + si.to_s()
    is_f64 = ctx[:var_types][cur_name] == :f64
    p_slot_type = is_f64 ? "double" : "i64"
    p_ptr = ensure_var_slot(wfn, p_key, p_slot_type)
    wfn[:var_slots][bp_name] = p_ptr
    wfn[:var_slot_types][bp_name] = p_slot_type
    ctx[:bindings][bp_name] = nil
    if is_f64
      emit_wire_dynamic_2(wfn, :store_double, :value, cur_reg, :ptr, p_ptr)
      ctx[:var_types][bp_name] = :f64
    else
      emit_wire_store_i64(wfn, p_ptr, cur_reg)
      ctx[:var_types][bp_name] = nil
  tval = nil
  if bbody != nil && bbody.size() > 0
    nb = bbody.size()
    bi = 0
    while bi < nb - 1
      lower_statement(ctx, bbody[bi])
      bi += 1
    tval = lower_expression(ctx, bbody[nb - 1])
  if bp_name != nil
    if saved_slot != nil
      wfn[:var_slots][bp_name] = saved_slot
    else
      wfn[:var_slots].delete(bp_name)
    if saved_slot_type != nil
      wfn[:var_slot_types][bp_name] = saved_slot_type
    else
      wfn[:var_slot_types].delete(bp_name)
    if saved_has_vtype
      ctx[:var_types][bp_name] = saved_vtype
    else
      ctx[:var_types].delete(bp_name)
    if saved_binding != nil
      ctx[:bindings][bp_name] = saved_binding
    else
      ctx[:bindings].delete(bp_name)
    if ctx[:unboxed_vars] != nil
      if saved_unboxed != nil
        ctx[:unboxed_vars][bp_name] = saved_unboxed
      else
        ctx[:unboxed_vars].delete(bp_name)
  tval

# Box the current element register when the slot is in raw-f64 mode; a
# no-op passthrough otherwise. Used where a WValue is mandatory (detect
# result, array push).
-> pipeline_boxed_cur(ctx, wfn, cur_name, cur_reg)
  if ctx[:var_types][cur_name] == :f64
    return ensure_i64_value(wfn, typed_value(:raw_f64, cur_reg))
  cur_reg

# Mod-12 wheel range `(0..N / 12)`: indices m with candidates 12m±{1,5,7}.
# Returns the AST of the dividend N (the left side of `/ 12`), or nil.
-> wheel12_prime_hi_ast(base)
  if !is_ast_node?(base) || ast_kind(base) != :range
    return nil
  from = ast_get(base, :from)
  to = ast_get(base, :to)
  if !is_ast_node?(from) || ast_kind(from) != :int || ast_get(from, :value) != 0
    return nil
  if !is_ast_node?(to) || ast_kind(to) != :binary_op || ast_get(to, :op) != :SLASH
    return nil
  right = ast_get(to, :right)
  if !is_ast_node?(right) || ast_kind(right) != :int || ast_get(right, :value) != 12
    return nil
  ast_get(to, :left)

-> lower_pipeline(ctx, node, take_node = nil)
  fused = fuse_pipeline(node)
  base = fused[:base]
  # Range-elision (#49): a pipeline whose base is a variable bound to a range
  # literal (`range = (lo..hi)` then `range/Σ…`) substitutes the range node so
  # the closed-form path below sees a :range base, exactly as the `.each`
  # handler does at the call site. Without this the pipeline falls through to
  # the per-element loop (which can't even-form, and is O(N)).
  if is_ast_node?(base) && ast_kind(base) == :var && ctx[:range_bindings] != nil && ctx[:range_bindings][base.name] != nil
    base = ctx[:range_bindings][base.name]
  stages = fused[:stages]
  terminal = fused[:terminal]
  wfn = ctx[:func]

  uid = next_label(wfn, "pipe")
  is_detect = terminal == "detect"
  is_reduce = terminal != nil && !is_detect
  is_range = is_ast_node?(base) && ast_kind(base) == :range
  # `.take(n)` always materializes to an array — it can't combine with a
  # reduce/detect terminal (those produce a scalar).
  has_take = take_node != nil
  take_name = "__pipe_take." + uid

  # --- Closed-form ranged sum (polynomial Faulhaber) ----------------------
  # `range / map… / [parity-filter] : sum` has an O(1) closed form whenever
  # every map function is a polynomial in the element. We analyze each map
  # function's *body AST* (resolving named methods like `sq`/`cube` to
  # their definitions) into a coefficient array and COMPOSE them into one
  # transform polynomial P(x). Then Σ_{x∈range} P(x) = Σ_k cₖ·Σ xᵏ — a
  # linear combination of power sums (one w_range_pow_sum per term). A
  # single parity filter restricts to the even/odd subsequence, sound iff
  # the transform up to that point preserves parity (x even ⟺ P(x) even).
  # Exact (BigInt-promoting, like the loop's w_add), and faster than even
  # clang's scalar-evolution because we recognize it at the source level.
  if is_reduce && terminal == "sum" && is_range && !has_take
    cf_poly = poly_var()
    cf_parity = 0
    cf_ok = true
    cf_empty = false
    cf_seen_filter = false
    csi = 0
    while csi < stages.size()
      if cf_ok
        st = stages[csi]
        skn = ast_get(st, :kind)
        if skn == :map
          fp = poly_of_expr(ctx, ast_get(st, :func), nil, 0)
          if fp == nil
            cf_ok = false
          else
            cf_poly = poly_compose(fp, cf_poly)
        elsif skn == :select || skn == :reject
          st_fn = ast_get(st, :func)
          pname = (st_fn != nil && is_ast_node?(st_fn) && ast_kind(st_fn) == :call) ? ast_get(st_fn, :name) : nil
          # filter-kind + predicate → which VALUE parity survives. reject is
          # the complement of select. Only one parity filter is foldable.
          want_even = nil
          if pname == "even?"
            want_even = skn == :select
          elsif pname == "odd?"
            want_even = skn == :reject
          else
            cf_ok = false
          if want_even != nil
            if cf_seen_filter
              cf_ok = false
            cf_seen_filter = true
            # Value parity is c₀ at even x, Σcₖ at odd x. Keep the x whose
            # value parity matches the filter; collapse to an x-parity
            # restriction (1=even, 2=odd), keep-all (0), or keep-none.
            c0p = poly_const_parity(cf_poly)
            smp = poly_sum_parity(cf_poly)
            keep_e = false
            keep_o = false
            if want_even
              keep_e = c0p == 0
              keep_o = smp == 0
            else
              keep_e = c0p != 0
              keep_o = smp != 0
            if keep_e && keep_o
              cf_parity = 0
            elsif keep_e
              cf_parity = 1
            elsif keep_o
              cf_parity = 2
            else
              cf_empty = true
        else
          cf_ok = false
      csi += 1
    if cf_ok && cf_empty
      zero = next_temp(wfn)
      emit_wire_call_direct_i64(wfn, nil, ["0"], nil, nil, "w_int", nil, nil, zero)
      return typed_value(:i64, zero)
    if cf_ok && poly_emittable(cf_poly)
      # Bounds unbox via w_range_bound_i64, NOT nanunbox — same hazard the
      # `:count` path below documents: a bound past 2^48 is a BOXED bigint
      # WValue, and the 48-bit nanunbox shortcut silently truncates it, so
      # `(1..10^15)/Σ(2x + 3)` folded to a wrapped answer while every bound
      # under 2^48 looked correct. w_range_bound_i64 handles both int
      # representations (and a whole-valued Decimal bound).
      lo_b = ensure_i64_value(wfn, lower_expression(ctx, ast_get(base, :from)))
      hi_b = ensure_i64_value(wfn, lower_expression(ctx, ast_get(base, :to)))
      lo_cf = next_temp(wfn)
      emit_wire_call_direct_i64(wfn, nil, [lo_b], nil, nil, "w_range_bound_i64", nil, nil, lo_cf)
      hi_cf = next_temp(wfn)
      emit_wire_call_direct_i64(wfn, nil, [hi_b], nil, nil, "w_range_bound_i64", nil, nil, hi_cf)
      # Exclusive range (1...n) drops the top endpoint.
      if ast_get(base, :exclusive)
        hi_excl = next_temp(wfn)
        emit_wire_sub_i64(wfn, hi_cf, "1", hi_excl)
        hi_cf = hi_excl
      return emit_poly_ranged_sum(wfn, cf_poly, lo_cf, hi_cf, cf_parity)

  # --- Range/predicate:count closed forms ----------------------------------
  # `range / prime? : count` → the segmented wheel sieve (w_prime_count_u64),
  # O(n log log n) vs the O(n) per-number loop. `range / even?|odd? : count` →
  # O(1) arithmetic (w_parity_count_u64). Fires only on the exact shape: one
  # such predicate map, a `count` terminal, a range base, and no `.take` (a
  # filter or extra stage changes what's counted → falls through to the loop).
  count_pred = nil
  if is_reduce && terminal == "count" && is_range && !has_take && stages.size() == 1 && ast_get(stages[0], :kind) == :map
    st0_fn = ast_get(stages[0], :func)
    if st0_fn != nil && is_ast_node?(st0_fn) && ast_kind(st0_fn) == :call
      count_pred = ast_get(st0_fn, :name)
  wheel12_hi = nil
  if count_pred == "prime_12k?"
    wheel12_hi = wheel12_prime_hi_ast(base)
  if count_pred == "prime?" || count_pred == "even?" || count_pred == "odd?" || wheel12_hi != nil
    # Bounds unbox via w_range_bound_i64, NOT nanunbox: a bound > 2^48 is a
    # BOXED bigint WValue, and nanunbox on it yields garbage (wrong counts
    # for e.g. (0..10^18).count(:even?)). w_range_bound_i64 handles both
    # int representations, plus a whole-valued Decimal bound (`1e10`,
    # common scientific-notation shorthand for a big integer) — raising a
    # catchable TypeError instead of the fatal abort plain w_to_i64/as_int
    # hit on a Decimal (0xfffd... "numeric" isn't w_is_int).
    lo_pc = nil
    hi_pc = nil
    if wheel12_hi != nil
      lo_b = ensure_i64_value(wfn, lower_expression(ctx, Tungsten:AST:Int.new(2, nil, "2")))
      hi_b = ensure_i64_value(wfn, lower_expression(ctx, wheel12_hi))
      lo_pc = next_temp(wfn)
      emit_wire_call_direct_i64(wfn, nil, [lo_b], nil, nil, "w_range_bound_i64", nil, nil, lo_pc)
      hi_pc = next_temp(wfn)
      emit_wire_call_direct_i64(wfn, nil, [hi_b], nil, nil, "w_range_bound_i64", nil, nil, hi_pc)
    else
      lo_b = ensure_i64_value(wfn, lower_expression(ctx, ast_get(base, :from)))
      hi_b = ensure_i64_value(wfn, lower_expression(ctx, ast_get(base, :to)))
      lo_pc = next_temp(wfn)
      emit_wire_call_direct_i64(wfn, nil, [lo_b], nil, nil, "w_range_bound_i64", nil, nil, lo_pc)
      hi_pc = next_temp(wfn)
      emit_wire_call_direct_i64(wfn, nil, [hi_b], nil, nil, "w_range_bound_i64", nil, nil, hi_pc)
      if ast_get(base, :exclusive)
        hi_ex = next_temp(wfn)
        emit_wire_sub_i64(wfn, hi_pc, "1", hi_ex)
        hi_pc = hi_ex
    # `/prime?` counts through the Tungsten sieve in core/prime_sieve.w when
    # the loader pulled it in (it autoloads PrimeSieve on a `/prime?` stage):
    # psv_count rides the (n, p_n) checkpoint ladder, so π(x) below a rung
    # sieves only the tail. Bounds are already normalized raw i64 — box them
    # for the untyped fn. The C twin (w_prime_count_u64) stays the fallback.
    psv_count_fn = nil
    if count_pred == "prime?" && wheel12_hi == nil
      psv_count_fn = ctx[:mod][:known_calls]["psv_count"]
    if psv_count_fn != nil
      lo_box = next_temp(wfn)
      emit_wire_call_direct_i64(wfn, nil, [lo_pc], nil, nil, "w_int", nil, nil, lo_box)
      hi_box = next_temp(wfn)
      emit_wire_call_direct_i64(wfn, nil, [hi_pc], nil, nil, "w_int", nil, nil, hi_box)
      psv_cnt = next_temp(wfn)
      emit_wire_call_direct_i64(wfn, nil, [lo_box, hi_box], nil, nil, psv_count_fn, nil, nil, psv_cnt)
      return typed_value(:i64, psv_cnt)
    cnt_raw = next_temp(wfn)
    if count_pred == "prime?" || wheel12_hi != nil
      emit_wire_call_direct_i64(wfn, nil, [lo_pc, hi_pc], nil, nil, "w_prime_count_u64", nil, nil, cnt_raw)
    else
      want = "0"
      if count_pred == "even?"
        want = "1"
      emit_wire_call_direct_i64(wfn, nil, [lo_pc, hi_pc, want], nil, nil, "w_parity_count_u64", nil, nil, cnt_raw)
    cnt_box = next_temp(wfn)
    emit_wire_call_direct_i64(wfn, nil, [cnt_raw], nil, nil, "w_int", nil, nil, cnt_box)
    return typed_value(:i64, cnt_box)

  # Does the pipeline contain a select/reject filter? With a filter, the
  # count of PRODUCED elements differs from the count of ITERATIONS, so a
  # take(n) needs a runtime produced-counter (checked at body entry,
  # decremented after each push). WITHOUT a filter, produced == iterated,
  # so we instead clamp the loop bound to min(count, n) — exactly n
  # iterations, zero per-iteration take overhead, and no extra
  # exhaustion-detection cycle.
  has_filter = false
  if has_take
    fi0 = 0
    while fi0 < stages.size()
      sk0 = ast_get(stages[fi0], :kind)
      if sk0 == :select || sk0 == :reject
        has_filter = true
      fi0 += 1
  use_take_counter = has_take && has_filter
  clamp_take = has_take && !has_filter
  take_clamp_raw = nil
  if clamp_take
    take_clamp_tv = lower_expression(ctx, take_node)
    take_clamp_raw = nanunbox_int_emit(wfn, ensure_i64_value(wfn, take_clamp_tv))

  # --- source setup: count_raw + per-iter element ---
  receiver_reg = nil
  lo_raw = nil
  # Static element-access mode for array bases. The inline WValue slot read
  # (:array_get_inline) is only correct for plain boxed arrays — typed
  # arrays store raw elements (different encodings AND different strides),
  # so reading their slots as WValues yields silently wrong values. Proven
  # :array keeps the inline read; a proven %f64 array takes a raw-double
  # fast path; everything else (typed, small, unknown) goes through the
  # kind-dispatching w_array_get runtime call — correct for every layout.
  base_static_type = nil
  raw_f64_source = false
  raw_f64_base = nil
  if is_range
    lo_tv = lower_expression(ctx, ast_get(base, :from))
    lo_raw = nanunbox_int_emit(wfn, ensure_i64_value(wfn, lo_tv))
    hi_tv = lower_expression(ctx, ast_get(base, :to))
    hi_raw = nanunbox_int_emit(wfn, ensure_i64_value(wfn, hi_tv))
    span = next_temp(wfn)
    emit_wire_sub_i64(wfn, hi_raw, lo_raw, span)
    count_raw = next_temp(wfn)
    if ast_get(base, :exclusive)
      emit_wire_add_i64(wfn, span, "0", count_raw)
    else
      emit_wire_add_i64(wfn, span, "1", count_raw)
  else
    receiver_val = lower_expression(ctx, base)
    receiver_reg = ensure_i64_value(wfn, receiver_val)
    base_static_type = receiver_static_type(ctx, base)
    size_box = next_temp(wfn)
    emit_wire_call_direct_i64(wfn, nil, [receiver_reg], nil, nil, "w_array_size", nil, nil, size_box)
    count_raw = nanunbox_int_emit(wfn, size_box)
    if base_static_type == :typed_array_f64
      # Hoist the elems base pointer: the fused loop never pushes/clears the
      # SOURCE array, so slots/start are invariant for its duration (same
      # argument as the elementwise fuser's hoisted header decode).
      raw_f64_source = true
      raw_f64_base = next_temp(wfn)
      emit_wire_dynamic_2(wfn, :ta_f64_elems_ptr, :value, receiver_reg, :temp, raw_f64_base)

  # Filter-free take(n): clamp the iteration bound to min(count, n). Every
  # iteration produces exactly one element, so n iterations yield n
  # elements — no produced-counter, no per-iteration check, no extra
  # exhaustion cycle. `take(0)` → bound 0 → zero iterations.
  if clamp_take
    take_lt = next_temp(wfn)
    emit_wire_icmp_i64(wfn, take_clamp_raw, "slt", count_raw, take_lt)
    clamped = next_temp(wfn)
    emit_wire_select_i64(wfn, take_lt, count_raw, clamped, take_clamp_raw)
    count_raw = clamped

  # --- terminal state ---
  acc_name = "__pipe_acc." + uid
  seen_name = "__pipe_seen." + uid
  out_arr = nil
  if is_reduce || is_detect
    acc_ptr = ensure_var_slot(wfn, acc_name)
    seen_ptr = ensure_var_slot(wfn, seen_name)
    emit_wire_store_i64(wfn, seen_ptr, w_false.to_s())
    init_acc = w_nil.to_s()
    if terminal in ("sum" "count" "__size")
      init_acc = ensure_i64_value(wfn, lower_expression(ctx, Tungsten:AST:Int.new(0)))
    elsif terminal == "product"
      init_acc = ensure_i64_value(wfn, lower_expression(ctx, Tungsten:AST:Int.new(1)))
    emit_wire_store_i64(wfn, acc_ptr, init_acc)
  else
    out_arr = next_temp(wfn)
    emit_wire_call_direct_i64(wfn, nil, [], nil, nil, "w_array_new_empty", nil, nil, out_arr)

  # take(n) produced-counter — ONLY when a filter is present (otherwise the
  # min(count,n) bound clamp above handles it). `take_remaining` (raw i64)
  # is seeded to n, checked at body entry, decremented after each push.
  take_ptr = nil
  if use_take_counter
    take_tv = lower_expression(ctx, take_node)
    take_raw = nanunbox_int_emit(wfn, ensure_i64_value(wfn, take_tv))
    take_ptr = ensure_var_slot(wfn, take_name)
    emit_wire_store_i64(wfn, take_ptr, take_raw)

  materialize_bindings(ctx)
  outer_pipe_bindings = ctx[:bindings]
  if outer_pipe_bindings.size() > 0
    ctx[:bindings] = {}

  pre = next_label(wfn, "pipe.pre")
  hdr = next_label(wfn, "pipe.hdr")
  body = next_label(wfn, "pipe.body")
  inc = next_label(wfn, "pipe.inc")
  exit_l = next_label(wfn, "pipe.exit")

  emit_wire_br(wfn, pre, nil, nil)
  start_block(wfn, pre)
  emit_wire_br(wfn, hdr, nil, nil)

  start_block(wfn, hdr)
  idx_raw = next_temp(wfn)
  idx_next = next_temp(wfn)
  emit_wire_phi_i64(wfn, pre, "0", inc, idx_next, idx_raw)
  cmp = next_temp(wfn)
  emit_wire_icmp_i64(wfn, idx_raw, "slt", count_raw, cmp)
  emit_wire_cond_br(wfn, cmp, exit_l, nil, body)

  start_block(wfn, body)
  # take(n) with a filter: bail once n elements have been produced.
  # Checked at body entry so a fully-consumed take exits before doing more
  # element work. (Filter-free take uses the clamped bound instead.)
  if use_take_counter
    take_chk = next_temp(wfn)
    emit_wire_load_i64(wfn, take_ptr, take_chk)
    take_ok = next_temp(wfn)
    emit_wire_icmp_i64(wfn, take_chk, "sgt", "0", take_ok)
    take_go = next_label(wfn, "pipe.go")
    emit_wire_cond_br(wfn, take_ok, exit_l, nil, take_go)
    start_block(wfn, take_go)
  elem = next_temp(wfn)
  elem_raw_f64 = false
  if is_range
    val_raw = next_temp(wfn)
    emit_wire_add_i64(wfn, lo_raw, idx_raw, val_raw)
    boxed = nanbox_int_emit(wfn, val_raw)
    emit_wire_store_i64(wfn, ensure_var_slot(wfn, "__pipe_box." + uid), boxed[:value])
    elem = boxed[:value]
  elsif raw_f64_source
    # Raw double read — no boxing. idx_raw indexes from the hoisted elems
    # base (which already folds in the array's start offset).
    emit_wire_dynamic_3(wfn, :load_f64_at, :index, idx_raw, :ptr, raw_f64_base, :temp, elem)
    elem_raw_f64 = true
  elsif base_static_type == :array
    idx_boxed = nanbox_int_emit(wfn, idx_raw)
    scratch = []
    si = 0
    while si < 10
      scratch.push(next_temp(wfn))
      si += 1
    emit_wire_array_get_inline(wfn, receiver_reg, idx_boxed[:value], scratch, elem)
  else
    idx_boxed = nanbox_int_emit(wfn, idx_raw)
    emit_wire_call_direct_i64(wfn, nil, [receiver_reg, idx_boxed[:value]], nil, nil, "w_array_get", nil, nil, elem)

  cur_name = "__pipe_cur." + uid
  if elem_raw_f64
    cur_reg = pipeline_bind_cur(ctx, wfn, cur_name, typed_value(:raw_f64, elem))
  else
    cur_reg = pipeline_bind_cur(ctx, wfn, cur_name, typed_value(:i64, elem))

  push_loop(wfn, exit_l, inc, nil)

  si = 0
  while si < stages.size()
    stage = stages[si]
    skind = ast_get(stage, :kind)
    sfunc = ast_get(stage, :func)
    if skind == :select || skind == :reject
      pred_val = nil
      if ast_kind(sfunc) == :block
        pred_val = lower_pipeline_block_stage(ctx, wfn, sfunc, cur_name, cur_reg, uid, si)
      else
        pred_val = lower_expression(ctx, pipeline_pred_node(sfunc, cur_name))
      pred_bool = nil
      if pred_val[:type] == :i1
        pred_bool = pred_val[:value]
      else
        pred_reg = ensure_i64_value(wfn, pred_val)
        pred_bool = next_temp(wfn)
        emit_wire_truthy_inline(wfn, pred_bool, pred_reg)
      keep = next_label(wfn, "pipe.keep")
      if skind == :select
        emit_wire_cond_br(wfn, pred_bool, inc, nil, keep)
      else
        emit_wire_cond_br(wfn, pred_bool, keep, nil, inc)
      start_block(wfn, keep)
    elsif ast_kind(sfunc) == :block
      # Inline a `map(-> (x) body)` lambda: bind its param to the current
      # element, then lower the body in place (no closure allocation).
      tval = lower_pipeline_block_stage(ctx, wfn, sfunc, cur_name, cur_reg, uid, si)
      cur_reg = pipeline_bind_cur(ctx, wfn, cur_name, tval)
    else
      tval = lower_expression(ctx, pipeline_transform_node(ast_get(sfunc, :name), ast_get(sfunc, :args), cur_name))
      cur_reg = pipeline_bind_cur(ctx, wfn, cur_name, tval)
    si += 1

  # Raw f64 accumulator: element still raw after the stages, and the
  # terminal folds arithmetically. min/max additionally need the host
  # clang to know llvm.minimumnum/llvm.maximumnum (single fminnm/fmaxnm
  # on AArch64, NaN treated as missing — matching the runtime's NEON
  # array min/max kernels); without the intrinsics they keep the boxed
  # compare-select combine.
  acc_raw = is_reduce && ctx[:var_types][cur_name] == :f64
  if acc_raw
    if terminal in ("min" "max")
      acc_raw = host_cc_supports_llvm_fminmaxnum?()
    elsif !(terminal in ("sum" "product"))
      acc_raw = false
  if is_detect
    acc_ptr2 = ensure_var_slot(wfn, acc_name)
    emit_wire_store_i64(wfn, acc_ptr2, pipeline_boxed_cur(ctx, wfn, cur_name, cur_reg))
    emit_wire_store_i64(wfn, ensure_var_slot(wfn, seen_name), w_true.to_s())
    emit_wire_br(wfn, exit_l, nil, nil)
  elsif is_reduce
    acc_ptr3 = ensure_var_slot(wfn, acc_name)
    seen_ptr3 = ensure_var_slot(wfn, seen_name)
    seen_box = next_temp(wfn)
    emit_wire_load_i64(wfn, seen_ptr3, seen_box)
    seen_bool = next_temp(wfn)
    emit_wire_truthy_inline(wfn, seen_bool, seen_box)
    seed_l = next_label(wfn, "pipe.seed")
    comb_l = next_label(wfn, "pipe.comb")
    after_l = next_label(wfn, "pipe.after")
    emit_wire_cond_br(wfn, seen_bool, seed_l, nil, comb_l)
    start_block(wfn, seed_l)
    if terminal == "count"
      # Seed with the first element's contribution (0 or 1), not the element
      # itself, so the count folds from 0. cur_name is bound to the (mapped)
      # element here.
      seed_val = lower_expression(ctx, Tungsten:AST:If.new(Tungsten:AST:Var.new(cur_name), [Tungsten:AST:Int.new(1)], [], [Tungsten:AST:Int.new(0)]))
      emit_wire_store_i64(wfn, acc_ptr3, ensure_i64_value(wfn, seed_val))
    elsif terminal == "__size"
      seed_one = lower_expression(ctx, Tungsten:AST:Int.new(1))
      emit_wire_store_i64(wfn, acc_ptr3, ensure_i64_value(wfn, seed_one))
    elsif acc_raw
      emit_wire_dynamic_2(wfn, :store_double, :value, cur_reg, :ptr, acc_ptr3)
    else
      emit_wire_store_i64(wfn, acc_ptr3, pipeline_boxed_cur(ctx, wfn, cur_name, cur_reg))
    emit_wire_store_i64(wfn, seen_ptr3, w_true.to_s())
    emit_wire_br(wfn, after_l, nil, nil)
    start_block(wfn, comb_l)
    ctx[:bindings][acc_name] = nil
    ctx[:var_types][acc_name] = acc_raw ? :f64 : nil
    if acc_raw && terminal in ("min" "max")
      intrinsic = terminal == "min" ? "llvm.minimumnum.f64" : "llvm.maximumnum.f64"
      acc_raw_reg = ensure_raw_f64(wfn, lower_expression(ctx, Tungsten:AST:Var.new(acc_name)))
      cur_raw_reg = ensure_raw_f64(wfn, lower_expression(ctx, Tungsten:AST:Var.new(cur_name)))
      comb_temp = next_temp(wfn)
      emit_wire_call_libm_f64(wfn, acc_raw_reg, intrinsic, cur_raw_reg, comb_temp, nil)
      emit_wire_dynamic_2(wfn, :store_double, :value, comb_temp, :ptr, acc_ptr3)
    elsif acc_raw
      comb_val = lower_expression(ctx, pipeline_reduce_node(terminal, acc_name, cur_name))
      comb_raw = ensure_raw_f64(wfn, comb_val)
      emit_wire_dynamic_2(wfn, :store_double, :value, comb_raw, :ptr, acc_ptr3)
    else
      comb_val = lower_expression(ctx, pipeline_reduce_node(terminal, acc_name, cur_name))
      comb_reg = ensure_i64_value(wfn, comb_val)
      emit_wire_store_i64(wfn, acc_ptr3, comb_reg)
    emit_wire_br(wfn, after_l, nil, nil)
    start_block(wfn, after_l)
  else
    push_tmp = next_temp(wfn)
    emit_wire_call_direct_i64(wfn, nil, [out_arr, pipeline_boxed_cur(ctx, wfn, cur_name, cur_reg)], nil, nil, "w_array_push", nil, nil, push_tmp)
    # take(n) with a filter: one more element produced — decrement the
    # counter. Only reached for elements that survived all select/reject
    # stages, so the count is of PRODUCED (not iterated) elements.
    if use_take_counter
      take_cur = next_temp(wfn)
      emit_wire_load_i64(wfn, take_ptr, take_cur)
      take_dec = next_temp(wfn)
      emit_wire_sub_i64(wfn, take_cur, "1", take_dec)
      emit_wire_store_i64(wfn, take_ptr, take_dec)

  pop_loop(wfn)

  if !block_terminated(wfn)
    emit_wire_br(wfn, inc, nil, nil)
  start_block(wfn, inc)
  emit_wire_add_i64(wfn, idx_raw, "1", idx_next)
  emit_wire_br(wfn, hdr, nil, nil)

  start_block(wfn, exit_l)
  ctx[:bindings] = outer_pipe_bindings
  if is_reduce || is_detect
    result = next_temp(wfn)
    if acc_raw
      # Box the raw accumulator once at the boundary. An empty source never
      # seeded the slot (it still holds the init_acc bits stored at setup), so
      # select on the seen flag to preserve the empty-source contract.
      emit_wire_dynamic_2(wfn, :load_double, :ptr, ensure_var_slot(wfn, acc_name), :temp, result)
      boxed_tv = nanbox_float_emit(wfn, result)
      seen_exit = next_temp(wfn)
      emit_wire_load_i64(wfn, ensure_var_slot(wfn, seen_name), seen_exit)
      seen_exit_bool = next_temp(wfn)
      emit_wire_truthy_inline(wfn, seen_exit_bool, seen_exit)
      empty_acc = w_nil.to_s()
      if terminal == "sum"
        empty_acc = ensure_i64_value(wfn, lower_expression(ctx, Tungsten:AST:Int.new(0)))
      elsif terminal == "product"
        empty_acc = ensure_i64_value(wfn, lower_expression(ctx, Tungsten:AST:Int.new(1)))
      final = next_temp(wfn)
      emit_wire_select_i64(wfn, seen_exit_bool, empty_acc, final, boxed_tv[:value])
      return typed_value(:i64, final)
    emit_wire_load_i64(wfn, ensure_var_slot(wfn, acc_name), result)
    return typed_value(:i64, result)
  typed_value(:i64, out_arr)

-> pipeline_block_has_control_transfer?(node)
  if node == nil
    return false
  if type(node) == "Array"
    n_node = node.size()
    i = 0
    while i < n_node
      if pipeline_block_has_control_transfer?(node[i])
        return true
      i += 1
    return false
  if !is_ast_node?(node)
    return false
  k = ast_kind(node)
  if k in (:method_def :fn_def :class_def :module_def :trait_def :block)
    return false
  if k in (:return :break :next :redo :yield)
    return true
  if k == :while
    return has_nonlocal_block_return([node])
  kids = ast_children(node)
  n_kids = kids.size()
  i = 0
  while i < n_kids
    if pipeline_block_has_control_transfer?(kids[i])
      return true
    i += 1
  false

-> pipeline_fusable_block?(blk)
  if blk == nil || !is_ast_node?(blk) || ast_kind(blk) != :block
    return false
  bparams = ast_get(blk, :params)
  if bparams == nil || bparams.size() != 1
    return false
  p0 = bparams[0]
  if is_ast_node?(p0)
    if p0.default != nil || p0.splat == true || p0.keyword == true || p0.block_param == true || p0.ivar_assign == true
      return false
  bbody = ast_get(blk, :body)
  if bbody == nil || bbody.size() == 0
    return false
  if block_spawns_escaping_closure?(blk)
    return false
  if pipeline_block_has_control_transfer?(bbody)
    return false
  true

-> pipeline_extract_call_stage(node)
  if node == nil || !is_ast_node?(node) || ast_kind(node) != :call
    return nil
  if node.receiver == nil
    return nil
  mname = node.name
  if !(mname in ("map" "select" "reject"))
    return nil
  cargs = node.args
  nargs = cargs != nil ? cargs.size() : 0
  blk = node.block
  sfunc = nil
  if blk != nil && nargs == 0
    if pipeline_fusable_block?(blk)
      sfunc = blk
  elsif blk == nil && nargs == 1
    arg0 = cargs[0]
    if arg0 != nil && is_ast_node?(arg0)
      ak = ast_kind(arg0)
      if ak == :block
        if pipeline_fusable_block?(arg0)
          sfunc = arg0
      elsif ak == :symbol
        sfunc = Tungsten:AST:Call.new(nil, "" + ast_get(arg0, :value), [], nil)
  if sfunc == nil
    return nil
  {kind: mname.to_sym(), func: sfunc, source: node.receiver}

-> try_lower_method_chain_pipeline(ctx, node)
  if env("TUNGSTEN_PIPELINE_FUSION") == "0"
    return nil
  if node == nil || !is_ast_node?(node) || ast_kind(node) != :call || node.receiver == nil
    return nil
  terminal = nil
  cur = node
  mname = node.name
  cargs = node.args
  nargs = cargs != nil ? cargs.size() : 0
  if node.block == nil && nargs == 0 && mname in ("sum" "count" "size" "min" "max")
    terminal = mname
    if mname in ("count" "size")
      terminal = "__size"
    cur = node.receiver
  outer = []
  while cur != nil && is_ast_node?(cur)
    ck = ast_kind(cur)
    if ck == :map
      outer.push({kind: ast_get(cur, :kind), func: ast_get(cur, :func)})
      cur = ast_get(cur, :source)
    else
      st = pipeline_extract_call_stage(cur)
      if st == nil
        break
      outer.push({kind: st[:kind], func: st[:func]})
      cur = st[:source]
  if outer.size() == 0
    return nil
  if terminal == nil && outer.size() < 2
    return nil
  if cur != nil && is_ast_node?(cur) && ast_kind(cur) == :call && ast_get(cur, :name) == "lazy" && cur.receiver != nil
    la = ast_get(cur, :args)
    if la == nil || la.size() == 0
      cur = cur.receiver
  if cur == nil || !is_ast_node?(cur)
    return nil
  base_k = ast_kind(cur)
  is_range_base = base_k == :range || (base_k == :var && ctx[:range_bindings] != nil && ctx[:range_bindings][cur.name] != nil)
  base_t = receiver_static_type(ctx, cur)
  is_array_base = base_k == :array || base_t == :array || is_typed_array_type?(base_t)
  if !is_range_base && !is_array_base
    return nil
  pipe_node = cur
  i = outer.size() - 1
  while i >= 0
    st_info = outer[i]
    pipe_node = Tungsten:AST:Map.new(pipe_node, st_info[:func], st_info[:kind])
    i -= 1
  if terminal != nil
    pipe_node = Tungsten:AST:Calc.new(terminal, pipe_node, :auto)
  lower_pipeline(ctx, pipe_node)

