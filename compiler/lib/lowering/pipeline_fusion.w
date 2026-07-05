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
  Tungsten:AST:Call.new(Tungsten:AST:Var.new(acc_name), op, [Tungsten:AST:Var.new(cur_name)], nil)

-> bind_slot_value(ctx, wfn, name, value_reg)
  ptr = ensure_var_slot(wfn, name)
  emit_instruction(wfn, {op: :store_i64, value: value_reg, ptr: ptr})
  ctx[:bindings][name] = nil
  ctx[:var_types][name] = nil
  ptr

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
          pname = ast_get(ast_get(st, :func), :name)
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
      emit_instruction(wfn, {op: :call_direct_i64, temp: zero, name: "w_int", args: ["0"]})
      return typed_value(:i64, zero)
    if cf_ok && poly_emittable(cf_poly)
      lo_cf = nanunbox_int_emit(wfn, ensure_i64_value(wfn, lower_expression(ctx, ast_get(base, :from))))
      hi_box = lower_expression(ctx, ast_get(base, :to))
      hi_cf = nanunbox_int_emit(wfn, ensure_i64_value(wfn, hi_box))
      # Exclusive range (1...n) drops the top endpoint.
      if ast_get(base, :exclusive)
        hi_excl = next_temp(wfn)
        emit_instruction(wfn, {op: :sub_i64, temp: hi_excl, lhs: hi_cf, rhs: "1"})
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
    count_pred = ast_get(ast_get(stages[0], :func), :name)
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
      emit_instruction(wfn, {op: :call_direct_i64, temp: lo_pc, name: "w_range_bound_i64", args: [lo_b]})
      hi_pc = next_temp(wfn)
      emit_instruction(wfn, {op: :call_direct_i64, temp: hi_pc, name: "w_range_bound_i64", args: [hi_b]})
    else
      lo_b = ensure_i64_value(wfn, lower_expression(ctx, ast_get(base, :from)))
      hi_b = ensure_i64_value(wfn, lower_expression(ctx, ast_get(base, :to)))
      lo_pc = next_temp(wfn)
      emit_instruction(wfn, {op: :call_direct_i64, temp: lo_pc, name: "w_range_bound_i64", args: [lo_b]})
      hi_pc = next_temp(wfn)
      emit_instruction(wfn, {op: :call_direct_i64, temp: hi_pc, name: "w_range_bound_i64", args: [hi_b]})
      if ast_get(base, :exclusive)
        hi_ex = next_temp(wfn)
        emit_instruction(wfn, {op: :sub_i64, temp: hi_ex, lhs: hi_pc, rhs: "1"})
        hi_pc = hi_ex
    cnt_raw = next_temp(wfn)
    if count_pred == "prime?" || wheel12_hi != nil
      emit_instruction(wfn, {op: :call_direct_i64, temp: cnt_raw, name: "w_prime_count_u64", args: [lo_pc, hi_pc]})
    else
      want = "0"
      if count_pred == "even?"
        want = "1"
      emit_instruction(wfn, {op: :call_direct_i64, temp: cnt_raw, name: "w_parity_count_u64", args: [lo_pc, hi_pc, want]})
    cnt_box = next_temp(wfn)
    emit_instruction(wfn, {op: :call_direct_i64, temp: cnt_box, name: "w_int", args: [cnt_raw]})
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
  if is_range
    lo_tv = lower_expression(ctx, ast_get(base, :from))
    lo_raw = nanunbox_int_emit(wfn, ensure_i64_value(wfn, lo_tv))
    hi_tv = lower_expression(ctx, ast_get(base, :to))
    hi_raw = nanunbox_int_emit(wfn, ensure_i64_value(wfn, hi_tv))
    span = next_temp(wfn)
    emit_instruction(wfn, {op: :sub_i64, temp: span, lhs: hi_raw, rhs: lo_raw})
    count_raw = next_temp(wfn)
    if ast_get(base, :exclusive)
      emit_instruction(wfn, {op: :add_i64, temp: count_raw, lhs: span, rhs: "0"})
    else
      emit_instruction(wfn, {op: :add_i64, temp: count_raw, lhs: span, rhs: "1"})
  else
    receiver_val = lower_expression(ctx, base)
    receiver_reg = ensure_i64_value(wfn, receiver_val)
    size_box = next_temp(wfn)
    emit_instruction(wfn, {op: :call_direct_i64, temp: size_box, name: "w_array_size", args: [receiver_reg]})
    count_raw = nanunbox_int_emit(wfn, size_box)

  # Filter-free take(n): clamp the iteration bound to min(count, n). Every
  # iteration produces exactly one element, so n iterations yield n
  # elements — no produced-counter, no per-iteration check, no extra
  # exhaustion cycle. `take(0)` → bound 0 → zero iterations.
  if clamp_take
    take_lt = next_temp(wfn)
    emit_instruction(wfn, {op: :icmp_i64, temp: take_lt, pred: "slt", lhs: take_clamp_raw, rhs: count_raw})
    clamped = next_temp(wfn)
    emit_instruction(wfn, {op: :select_i64, temp: clamped, cond: take_lt, then_val: take_clamp_raw, else_val: count_raw})
    count_raw = clamped

  # --- terminal state ---
  acc_name = "__pipe_acc." + uid
  seen_name = "__pipe_seen." + uid
  out_arr = nil
  if is_reduce || is_detect
    acc_ptr = ensure_var_slot(wfn, acc_name)
    seen_ptr = ensure_var_slot(wfn, seen_name)
    emit_instruction(wfn, {op: :store_i64, value: w_false.to_s(), ptr: seen_ptr})
    emit_instruction(wfn, {op: :store_i64, value: w_nil.to_s(), ptr: acc_ptr})
  else
    out_arr = next_temp(wfn)
    emit_instruction(wfn, {op: :call_direct_i64, temp: out_arr, name: "w_array_new_empty", args: []})

  # take(n) produced-counter — ONLY when a filter is present (otherwise the
  # min(count,n) bound clamp above handles it). `take_remaining` (raw i64)
  # is seeded to n, checked at body entry, decremented after each push.
  take_ptr = nil
  if use_take_counter
    take_tv = lower_expression(ctx, take_node)
    take_raw = nanunbox_int_emit(wfn, ensure_i64_value(wfn, take_tv))
    take_ptr = ensure_var_slot(wfn, take_name)
    emit_instruction(wfn, {op: :store_i64, value: take_raw, ptr: take_ptr})

  materialize_bindings(ctx)

  pre = next_label(wfn, "pipe.pre")
  hdr = next_label(wfn, "pipe.hdr")
  body = next_label(wfn, "pipe.body")
  inc = next_label(wfn, "pipe.inc")
  exit_l = next_label(wfn, "pipe.exit")

  emit_instruction(wfn, {op: :br, label: pre})
  start_block(wfn, pre)
  emit_instruction(wfn, {op: :br, label: hdr})

  start_block(wfn, hdr)
  idx_raw = next_temp(wfn)
  idx_next = next_temp(wfn)
  emit_instruction(wfn, {op: :phi_i64, temp: idx_raw, a_value: "0", a_label: pre, b_value: idx_next, b_label: inc})
  cmp = next_temp(wfn)
  emit_instruction(wfn, {op: :icmp_i64, temp: cmp, pred: "slt", lhs: idx_raw, rhs: count_raw})
  emit_instruction(wfn, {op: :cond_br, cond: cmp, then_label: body, else_label: exit_l})

  start_block(wfn, body)
  # take(n) with a filter: bail once n elements have been produced.
  # Checked at body entry so a fully-consumed take exits before doing more
  # element work. (Filter-free take uses the clamped bound instead.)
  if use_take_counter
    take_chk = next_temp(wfn)
    emit_instruction(wfn, {op: :load_i64, temp: take_chk, ptr: take_ptr})
    take_ok = next_temp(wfn)
    emit_instruction(wfn, {op: :icmp_i64, temp: take_ok, pred: "sgt", lhs: take_chk, rhs: "0"})
    take_go = next_label(wfn, "pipe.go")
    emit_instruction(wfn, {op: :cond_br, cond: take_ok, then_label: take_go, else_label: exit_l})
    start_block(wfn, take_go)
  elem = next_temp(wfn)
  if is_range
    val_raw = next_temp(wfn)
    emit_instruction(wfn, {op: :add_i64, temp: val_raw, lhs: lo_raw, rhs: idx_raw})
    boxed = nanbox_int_emit(wfn, val_raw)
    emit_instruction(wfn, {op: :store_i64, value: boxed[:value], ptr: ensure_var_slot(wfn, "__pipe_box." + uid)})
    elem = boxed[:value]
  else
    idx_boxed = nanbox_int_emit(wfn, idx_raw)
    scratch = []
    si = 0
    while si < 10
      scratch.push(next_temp(wfn))
      si += 1
    emit_instruction(wfn, {op: :array_get_inline, temp: elem, arr: receiver_reg, idx: idx_boxed[:value], s: scratch})

  cur_name = "__pipe_cur." + uid
  cur_ptr = bind_slot_value(ctx, wfn, cur_name, elem)
  cur_reg = elem

  push_loop(wfn, exit_l, inc, nil)

  si = 0
  while si < stages.size()
    stage = stages[si]
    skind = ast_get(stage, :kind)
    sfunc = ast_get(stage, :func)
    if skind == :select || skind == :reject
      pred_val = lower_expression(ctx, pipeline_pred_node(sfunc, cur_name))
      pred_reg = ensure_i64_value(wfn, pred_val)
      pred_bool = next_temp(wfn)
      emit_instruction(wfn, {op: :truthy_inline, temp: pred_bool, value: pred_reg})
      keep = next_label(wfn, "pipe.keep")
      if skind == :select
        emit_instruction(wfn, {op: :cond_br, cond: pred_bool, then_label: keep, else_label: inc})
      else
        emit_instruction(wfn, {op: :cond_br, cond: pred_bool, then_label: inc, else_label: keep})
      start_block(wfn, keep)
    elsif ast_kind(sfunc) == :block
      # Inline a `map(-> (x) body)` lambda: bind its param to the current
      # element, then lower the body in place (no closure allocation).
      bparams = ast_get(sfunc, :params)
      bbody = ast_get(sfunc, :body)
      if bparams != nil && bparams.size() >= 1
        bind_slot_value(ctx, wfn, "" + bparams[0], cur_reg)
      bi = 0
      tval = nil
      while bi < bbody.size()
        tval = lower_expression(ctx, bbody[bi])
        bi = bi + 1
      treg = ensure_i64_value(wfn, tval)
      cur_ptr = bind_slot_value(ctx, wfn, cur_name, treg)
      cur_reg = treg
    else
      tval = lower_expression(ctx, pipeline_transform_node(ast_get(sfunc, :name), ast_get(sfunc, :args), cur_name))
      treg = ensure_i64_value(wfn, tval)
      cur_ptr = bind_slot_value(ctx, wfn, cur_name, treg)
      cur_reg = treg
    si += 1

  if is_detect
    acc_ptr2 = ensure_var_slot(wfn, acc_name)
    emit_instruction(wfn, {op: :store_i64, value: cur_reg, ptr: acc_ptr2})
    emit_instruction(wfn, {op: :store_i64, value: w_true.to_s(), ptr: ensure_var_slot(wfn, seen_name)})
    emit_instruction(wfn, {op: :br, label: exit_l})
  elsif is_reduce
    acc_ptr3 = ensure_var_slot(wfn, acc_name)
    seen_ptr3 = ensure_var_slot(wfn, seen_name)
    seen_box = next_temp(wfn)
    emit_instruction(wfn, {op: :load_i64, temp: seen_box, ptr: seen_ptr3})
    seen_bool = next_temp(wfn)
    emit_instruction(wfn, {op: :truthy_inline, temp: seen_bool, value: seen_box})
    seed_l = next_label(wfn, "pipe.seed")
    comb_l = next_label(wfn, "pipe.comb")
    after_l = next_label(wfn, "pipe.after")
    emit_instruction(wfn, {op: :cond_br, cond: seen_bool, then_label: comb_l, else_label: seed_l})
    start_block(wfn, seed_l)
    if terminal == "count"
      # Seed with the first element's contribution (0 or 1), not the element
      # itself, so the count folds from 0. cur_name is bound to the (mapped)
      # element here.
      seed_val = lower_expression(ctx, Tungsten:AST:If.new(Tungsten:AST:Var.new(cur_name), [Tungsten:AST:Int.new(1)], [], [Tungsten:AST:Int.new(0)]))
      emit_instruction(wfn, {op: :store_i64, value: ensure_i64_value(wfn, seed_val), ptr: acc_ptr3})
    else
      emit_instruction(wfn, {op: :store_i64, value: cur_reg, ptr: acc_ptr3})
    emit_instruction(wfn, {op: :store_i64, value: w_true.to_s(), ptr: seen_ptr3})
    emit_instruction(wfn, {op: :br, label: after_l})
    start_block(wfn, comb_l)
    ctx[:bindings][acc_name] = nil
    ctx[:var_types][acc_name] = nil
    comb_val = lower_expression(ctx, pipeline_reduce_node(terminal, acc_name, cur_name))
    comb_reg = ensure_i64_value(wfn, comb_val)
    emit_instruction(wfn, {op: :store_i64, value: comb_reg, ptr: acc_ptr3})
    emit_instruction(wfn, {op: :br, label: after_l})
    start_block(wfn, after_l)
  else
    push_tmp = next_temp(wfn)
    emit_instruction(wfn, {op: :call_direct_i64, temp: push_tmp, name: "w_array_push", args: [out_arr, cur_reg]})
    # take(n) with a filter: one more element produced — decrement the
    # counter. Only reached for elements that survived all select/reject
    # stages, so the count is of PRODUCED (not iterated) elements.
    if use_take_counter
      take_cur = next_temp(wfn)
      emit_instruction(wfn, {op: :load_i64, temp: take_cur, ptr: take_ptr})
      take_dec = next_temp(wfn)
      emit_instruction(wfn, {op: :sub_i64, temp: take_dec, lhs: take_cur, rhs: "1"})
      emit_instruction(wfn, {op: :store_i64, value: take_dec, ptr: take_ptr})

  pop_loop(wfn)

  if !block_terminated(wfn)
    emit_instruction(wfn, {op: :br, label: inc})
  start_block(wfn, inc)
  emit_instruction(wfn, {op: :add_i64, temp: idx_next, lhs: idx_raw, rhs: "1"})
  emit_instruction(wfn, {op: :br, label: hdr})

  start_block(wfn, exit_l)
  if is_reduce || is_detect
    result = next_temp(wfn)
    emit_instruction(wfn, {op: :load_i64, temp: result, ptr: ensure_var_slot(wfn, acc_name)})
    return typed_value(:i64, result)
  typed_value(:i64, out_arr)
