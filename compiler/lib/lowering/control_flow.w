# Lowering / control_flow — control flow and exception handling.
# Includes if / while / for / with / return / break / next /
# case / case-value / begin-rescue-ensure / raise.
#
# Depends on pass_registry.w, types.w, ops.w, blocks.w. This file
# deliberately has no `use` directives — see pass_registry.w.


# -- Control flow --

-> lower_if(ctx, node)
  wfn = ctx[:func]

  # Constant-fold the condition. `if true` (and `unless false`, which
  # the parser desugars to `if !false`) lowers to just the then body
  # with no branch at all. `if false` skips straight to the else body
  # (or the first elsif if no else). Folding only kicks in when the
  # condition is a literal — runtime conditions take the existing path.
  static_cond = static_bool_value(node.condition)

  if static_cond == :true
    # Lower then body inline, skip elsif/else entirely.
    then_recycle_depth = wfn[:scope_recycle_stack].size()
    then_sid = next_scope_id(wfn)
    emit_scope_push(wfn, then_sid)
    lower_program(ctx, node.then_body)
    if !block_terminated(wfn)
      materialize_bindings(ctx)
      emit_scope_pop(wfn, then_sid)
    else
      restore_recycle_scope_depth(wfn, then_recycle_depth)
    return nil

  if static_cond == :false
    # Skip then body. If there are elsif clauses, the next one becomes
    # the new top-level if; otherwise lower else_body if present.
    if node.elsif_clauses != nil && node.elsif_clauses.size() > 0
      first = node.elsif_clauses[0]
      rest = []
      ri = 1
      while ri < node.elsif_clauses.size()
        rest.push(node.elsif_clauses[ri])
        ri += 1
      new_node = Tungsten:AST:If.new(first[0], first[1], rest, node.else_body)
      return lower_if(ctx, new_node)
    if node.else_body != nil && node.else_body.size() > 0
      else_recycle_depth = wfn[:scope_recycle_stack].size()
      else_sid = next_scope_id(wfn)
      emit_scope_push(wfn, else_sid)
      lower_program(ctx, node.else_body)
      if !block_terminated(wfn)
        materialize_bindings(ctx)
        emit_scope_pop(wfn, else_sid)
      else
        restore_recycle_scope_depth(wfn, else_recycle_depth)
    return nil

  # Snapshot the bindings valid on entry, and the set of vars assigned in ANY
  # branch. The merge block below is reached only via non-terminating paths, so
  # a var NOT assigned in any branch keeps its entry binding — its defining
  # register dominates the merge. Restoring these at the merge stops a
  # terminating branch's `ctx[:bindings] = {}` (or materialize_bindings' reset)
  # from dropping a typed param's binding: without the binding the param loses
  # its raw-int type and a later use mis-unboxes it (w_to_i64 on a raw param →
  # "expected int, got singleton") — the same class as the while-loop bug.
  pre_if_bindings = {}
  if ctx[:bindings] != nil
    pbk = ctx[:bindings].keys()
    pbi = 0
    while pbi < pbk.size()
      pre_if_bindings[pbk[pbi]] = ctx[:bindings][pbk[pbi]]
      pbi += 1
  if_assigned = {}
  scan_assigns_for_params(node.then_body, if_assigned)
  scan_assigns_for_params(node.else_body, if_assigned)
  if node.elsif_clauses != nil
    eci = 0
    while eci < node.elsif_clauses.size()
      scan_assigns_for_params(node.elsif_clauses[eci][1], if_assigned)
      eci += 1

  cond = lower_expression(ctx, node.condition)

  # If condition is already i1 (from inline comparison), use directly
  if cond[:type] == :i1
    cond_bool = cond[:value]
  else
    cond_reg = ensure_i64_value(wfn, cond)
    cond_bool = next_temp(wfn)
    emit_wire_truthy_inline(wfn, cond_bool, cond_reg)

  then_label = next_label(wfn, "if.then")
  else_label = next_label(wfn, "if.else")
  end_label = next_label(wfn, "if.end")

  has_else = node.else_body != nil && node.else_body.size() > 0
  has_elsif = node.elsif_clauses != nil && node.elsif_clauses.size() > 0

  if has_else || has_elsif
    emit_wire_cond_br(wfn, cond_bool, else_label, nil, then_label)
  else
    emit_wire_cond_br(wfn, cond_bool, end_label, nil, then_label)

  # Then branch.
  #
  # If the branch terminates early (via return / raise / unreachable
  # signal), the bindings established inside the branch must NOT leak
  # into the merge block. Clear ctx[:bindings] on termination. If the
  # branch doesn't terminate, materialize_bindings already resets
  # ctx[:bindings] to {} internally (wire.w:1799), so either path
  # leaves ctx[:bindings] clean for the next branch / merge.
  start_block(wfn, then_label)
  then_recycle_depth = wfn[:scope_recycle_stack].size()
  then_sid = next_scope_id(wfn)
  emit_scope_push(wfn, then_sid)
  lower_program(ctx, node.then_body)
  if !block_terminated(wfn)
    materialize_bindings(ctx)
    emit_scope_pop(wfn, then_sid)
    emit_wire_br(wfn, end_label, nil, nil)
  else
    ctx[:bindings] = {}
    restore_recycle_scope_depth(wfn, then_recycle_depth)

  # Elsif branches
  if has_elsif
    current_else = else_label
    i = 0
    while i < node.elsif_clauses.size()
      clause = node.elsif_clauses[i]
      start_block(wfn, current_else)
      ec = lower_expression(ctx, clause[0])
      # If the elsif condition already produced an i1 (inline comparison),
      # branch on it directly — avoid the i1 → nanbox_bool → icmp ugt 1
      # round trip that ensure_i64_value + truthy_inline would emit.
      if ec[:type] == :i1
        eb = ec[:value]
      else
        ec_reg = ensure_i64_value(wfn, ec)
        et = next_temp(wfn)
        emit_wire_truthy_inline(wfn, et, ec_reg)
        eb = et

      ethen_label = next_label(wfn, "elsif.then")
      if i + 1 < node.elsif_clauses.size()
        next_else = next_label(wfn, "elsif.else")
      elsif has_else
        next_else = next_label(wfn, "else")
      else
        next_else = end_label

      emit_wire_cond_br(wfn, eb, next_else, nil, ethen_label)

      start_block(wfn, ethen_label)
      elsif_recycle_depth = wfn[:scope_recycle_stack].size()
      elsif_sid = next_scope_id(wfn)
      emit_scope_push(wfn, elsif_sid)
      lower_program(ctx, clause[1])
      if !block_terminated(wfn)
        materialize_bindings(ctx)
        emit_scope_pop(wfn, elsif_sid)
        emit_wire_br(wfn, end_label, nil, nil)
      else
        ctx[:bindings] = {}
        restore_recycle_scope_depth(wfn, elsif_recycle_depth)

      current_else = next_else
      i += 1

    # Else branch after elsifs
    if has_else
      start_block(wfn, current_else)
      else_recycle_depth = wfn[:scope_recycle_stack].size()
      else_sid = next_scope_id(wfn)
      emit_scope_push(wfn, else_sid)
      lower_program(ctx, node.else_body)
      if !block_terminated(wfn)
        materialize_bindings(ctx)
        emit_scope_pop(wfn, else_sid)
        emit_wire_br(wfn, end_label, nil, nil)
      else
        ctx[:bindings] = {}
        restore_recycle_scope_depth(wfn, else_recycle_depth)
  elsif has_else
    # Simple if/else
    start_block(wfn, else_label)
    else_recycle_depth = wfn[:scope_recycle_stack].size()
    else_sid = next_scope_id(wfn)
    emit_scope_push(wfn, else_sid)
    lower_program(ctx, node.else_body)
    if !block_terminated(wfn)
      materialize_bindings(ctx)
      emit_scope_pop(wfn, else_sid)
      emit_wire_br(wfn, end_label, nil, nil)
    else
      ctx[:bindings] = {}
      restore_recycle_scope_depth(wfn, else_recycle_depth)

  start_block(wfn, end_label)

  # Restore entry bindings for vars untouched by every branch (see the snapshot
  # above). Vars assigned in a branch are materialized to slots and resolve via
  # var_slots; everything else keeps its still-valid entry binding, preserving
  # e.g. a typed param's raw-int type across the if.
  merged = {}
  mbk = pre_if_bindings.keys()
  mbi = 0
  while mbi < mbk.size()
    mname = mbk[mbi]
    if if_assigned[mname] == nil
      merged[mname] = pre_if_bindings[mname]
    mbi += 1
  ctx[:bindings] = merged
  nil

-> lower_if_expr(ctx, node, result_machine_type = nil)
  wfn = ctx[:func]

  # A machine-typed conditional must merge raw branch values directly. Boxing
  # each arm and unboxing after the merge is both semantically unnecessary and
  # especially costly in arithmetic helpers where the conditional is inlined.
  result_var = "__if_expr." + next_label(wfn, "ie")
  if result_machine_type != nil
    result_ptr = ensure_var_slot(wfn, result_var, machine_slot_type(result_machine_type))
    emit_wire_dynamic_2(wfn, machine_store_op(result_machine_type), :ptr, result_ptr, :value, "0")
  else
    result_ptr = ensure_var_slot(wfn, result_var)
    # Initialize an ordinary value conditional to nil.
    emit_wire_store_i64(wfn, result_ptr, w_nil.to_s())

  cond = lower_expression(ctx, node.condition)
  if cond[:type] == :i1
    cond_bool = cond[:value]
  else
    cond_reg = ensure_i64_value(wfn, cond)
    cond_bool = next_temp(wfn)
    emit_wire_truthy_inline(wfn, cond_bool, cond_reg)

  then_label = next_label(wfn, "ie.then")
  else_label = next_label(wfn, "ie.else")
  end_label = next_label(wfn, "ie.end")

  has_else = node.else_body != nil && node.else_body.size() > 0
  has_elsif = node.elsif_clauses != nil && node.elsif_clauses.size() > 0
  end_reachable = false

  if has_else || has_elsif
    emit_wire_cond_br(wfn, cond_bool, else_label, nil, then_label)
  else
    emit_wire_cond_br(wfn, cond_bool, end_label, nil, then_label)
    end_reachable = true

  # Then branch — lower body, store last expression as result
  start_block(wfn, then_label)
  then_body = node.then_body
  if then_body != nil && then_body.size() > 0
    lower_if_expr_body(ctx, wfn, then_body, result_ptr, result_machine_type)
  materialize_bindings(ctx)
  if !block_terminated(wfn)
    emit_wire_br(wfn, end_label, nil, nil)
    end_reachable = true

  # Elsif branches
  if has_elsif
    current_else = else_label
    i = 0
    while i < node.elsif_clauses.size()
      clause = node.elsif_clauses[i]
      start_block(wfn, current_else)
      ec = lower_expression(ctx, clause[0])
      # If the elsif condition already produced an i1 (inline comparison),
      # branch on it directly — avoid the i1 → nanbox_bool → icmp ugt 1
      # round trip that ensure_i64_value + truthy_inline would emit.
      if ec[:type] == :i1
        eb = ec[:value]
      else
        ec_reg = ensure_i64_value(wfn, ec)
        et = next_temp(wfn)
        emit_wire_truthy_inline(wfn, et, ec_reg)
        eb = et

      ethen_label = next_label(wfn, "ie.ethen")
      if i + 1 < node.elsif_clauses.size()
        next_else = next_label(wfn, "ie.eelse")
      elsif has_else
        next_else = next_label(wfn, "ie.else")
      else
        next_else = end_label

      emit_wire_cond_br(wfn, eb, next_else, nil, ethen_label)
      if next_else == end_label
        end_reachable = true

      start_block(wfn, ethen_label)
      clause_body = clause[1]
      if clause_body != nil && clause_body.size() > 0
        lower_if_expr_body(ctx, wfn, clause_body, result_ptr, result_machine_type)
      materialize_bindings(ctx)
      if !block_terminated(wfn)
        emit_wire_br(wfn, end_label, nil, nil)
        end_reachable = true

      current_else = next_else
      i += 1

    # Else branch after elsifs
    if has_else
      start_block(wfn, current_else)
      else_body = node.else_body
      if else_body != nil && else_body.size() > 0
        lower_if_expr_body(ctx, wfn, else_body, result_ptr, result_machine_type)
      materialize_bindings(ctx)
      if !block_terminated(wfn)
        emit_wire_br(wfn, end_label, nil, nil)
        end_reachable = true
  elsif has_else
    # Simple if/else
    start_block(wfn, else_label)
    else_body = node.else_body
    if else_body != nil && else_body.size() > 0
      lower_if_expr_body(ctx, wfn, else_body, result_ptr, result_machine_type)
    materialize_bindings(ctx)
    if !block_terminated(wfn)
      emit_wire_br(wfn, end_label, nil, nil)
      end_reachable = true

  if !end_reachable
    return typed_value(:i64, w_nil.to_s())

  start_block(wfn, end_label)
  result = next_temp(wfn)
  if result_machine_type != nil
    emit_wire_dynamic_2(wfn, machine_load_op(result_machine_type), :ptr, result_ptr, :temp, result)
    return typed_value(raw_machine_value_type(result_machine_type), result)
  emit_wire_load_i64(wfn, result_ptr, result)
  typed_value(:i64, result)

-> lower_if_expr_body(ctx, wfn, body, result_ptr, result_machine_type = nil)
  # Lower all but last as statements
  i = 0
  while i < body.size() - 1
    lower_statement(ctx, body[i])
    i += 1
  last = body[body.size() - 1]
  last_t = ast_kind(last)
  # If last is a statement (return, puts, while, etc.), lower as statement — no result to store
  # (:begin left OFF this list 2026-07-22: begin/rescue is a value expression)
  if last_t in (:return :puts :print :raise :while :method_def :fn_def :class_def)
    lower_statement(ctx, last)
  elsif result_machine_type != nil
    # Lower under the destination type from the outset. Calling the generic
    # expression lowerer first would construct a boxed BigInt for a u64 literal
    # above INT64_MAX and then immediately unbox it at the branch merge.
    last_reg = lower_machine_int_expression(ctx, last, result_machine_type)
    if !block_terminated(wfn)
      emit_wire_dynamic_2(wfn, machine_store_op(result_machine_type), :ptr, result_ptr, :value, last_reg)
  else
    last_tv = lower_expression(ctx, last)
    if !block_terminated(wfn)
      last_reg = ensure_i64_value(wfn, last_tv)
      emit_wire_store_i64(wfn, result_ptr, last_reg)

# Returns :true / :false / nil if the AST node is a compile-time boolean.
# Handles :bool literals, :nil_lit, :int (always truthy in Tungsten),
# :float (always truthy), :string (always truthy), and :not over any of
# those — so `unless` (parser desugars to `if !cond`) and `until` (parser
# desugars to `while !cond`) inherit constant folding for free.
#
# Tungsten's truthiness rule: only `nil` and `false` are falsy. Integer
# literals (including `0`), float literals (including `0.0` and NaN),
# and string literals (including `""`) are all truthy. This is
# Ruby-style truthiness preserved across all types. Earlier versions of
# this function incorrectly folded `:int 0` to `:false` — that rule
# contradicted Tungsten's own semantics and was caught during the
# Codex plan review (2026-04-14).
-> static_bool_value(node)
  if node == nil
    return nil
  if !is_ast_node?(node)
    return nil
  t = ast_kind(node)
  case t
  when :bool
    if node.value == true
      return :true
    return :false
  when :nil_lit
    return :false
  when :int
    return :true
  when :float
    return :true
  when :string
    return :true
  when :not
    inner = static_bool_value(node.operand)
    if inner == :true
      return :false
    if inner == :false
      return :true
    return nil
  else
    nil

-> lower_while(ctx, node)
  static_cond = static_bool_value(node.condition)
  if static_cond == :false
    return nil
  # Loop versioning: a qualifying untyped-array element loop (see
  # loop_version_spec) lowers TWICE behind a one-time runtime guard — once
  # with the array retyped :typed_array_w64 (the existing unchecked inline
  # path; poly slots hold boxed WValues, so it is representation-exact) and
  # once as the original checked loop. The per-iteration bounds check whose
  # failure edge calls the runtime is what blocks LICM/vectorization on
  # these loops (measured 4.8x, matching the typed path). Locals live in
  # shared alloca slots, so no merge plumbing is needed.
  if static_cond == nil
    ver = loop_version_spec(node, ctx[:var_types])
    if ver != nil
      return lower_while_versioned(ctx, node, ver)
  # Sum-chunking (E4 stage 1.5): a mut-candidate accumulator touched only
  # by `r = r ± int-shaped` statements in this loop keeps a raw i64
  # partial sum and flushes it into r with ONE mut-add per ~2^63 of
  # accumulated magnitude. Per-iteration cost: a fused add + overflow
  # flag, branch-weighted unlikely — no tag checks, no calls.
  sc = sum_chunk_var(node, ctx[:mut_accumulators], ctx[:var_types], ctx[:mod])
  if sc != nil
    return lower_while_sum_chunked(ctx, node, sc)
  # Rotation shape (E4 stage 2; MINUS mirror stage 4): t = a ± b; a = b;
  # b = t with the triple isolated — the result computes into old-a's
  # dying buffer (w_bigint_add_dest / w_bigint_sub_dest), so the steady
  # state allocates nothing.
  rot = env("TUNGSTEN_BIGINT_MUTATE_UNIQUE") == "0" ? nil : rotation_shape_spec(node)
  if rot != nil
    # Fresh-or-MARKED at the loop boundary: pre-loop plain copies (y = a)
    # and other pre-loop escapes mint aliases of the SEED values with no
    # runtime mark, and the first two rotations consume exactly those two
    # seed values as destinations — a slack-capacity seed then let the
    # dest entry clobber the alias (reachable on the PLUS rotation too,
    # not just the subtract mirror that exposed it). Mark both source
    # seeds once per loop entry: the first two dest calls refuse and fall
    # back immutably, and every later destination is a loop-minted fresh
    # value the isolation proof keeps alias-free. Inline seeds no-op.
    wfn_rot = ctx[:func]
    seed_a_tv = lower_expression(ctx, Tungsten:AST:Var.new(rot[:a]))
    seed_a_reg = ensure_i64_value(wfn_rot, seed_a_tv)
    mark_a = next_temp(wfn_rot)
    emit_wire_call_direct_i64(wfn_rot, nil, [seed_a_reg], nil, nil, "w_bigint_mark_shared_value", nil, nil, mark_a)
    seed_b_tv = lower_expression(ctx, Tungsten:AST:Var.new(rot[:b]))
    seed_b_reg = ensure_i64_value(wfn_rot, seed_b_tv)
    mark_b = next_temp(wfn_rot)
    emit_wire_call_direct_i64(wfn_rot, nil, [seed_b_reg], nil, nil, "w_bigint_mark_shared_value", nil, nil, mark_b)
    prev_rot = ctx[:rotation_shape]
    ctx[:rotation_shape] = rot
    lower_while_core(ctx, node)
    ctx[:rotation_shape] = prev_rot
    return nil
  lower_while_core(ctx, node)

-> lower_while_sum_chunked(ctx, node, name)
  wfn = ctx[:func]
  # r must live in its slot: the flush writes memory and every later read
  # loads it, so a register binding would go stale.
  binding = ctx[:bindings][name]
  r_slot = ensure_var_slot(wfn, name)
  if binding != nil
    emit_wire_store_i64(wfn, r_slot, binding)
    ctx[:bindings][name] = nil
  partial_slot = ensure_var_slot(wfn, "__sumchunk_" + name)
  emit_wire_store_i64(wfn, partial_slot, "0")
  prev_chunk = ctx[:sum_chunk]
  ctx[:sum_chunk] = {var: name, partial: partial_slot, acc: r_slot}
  lower_while_core(ctx, node)
  ctx[:sum_chunk] = prev_chunk
  # Flush the pending partial once. partial == 0 (zero-trip loop) costs
  # one add_mut identity return.
  pcur = next_temp(wfn)
  emit_wire_load_i64(wfn, partial_slot, pcur)
  boxed = next_temp(wfn)
  emit_wire_call_direct_i64(wfn, nil, [pcur], nil, nil, "w_int", nil, nil, boxed)
  racc = next_temp(wfn)
  emit_wire_load_i64(wfn, r_slot, racc)
  racc2 = next_temp(wfn)
  emit_wire_call_direct_i64(wfn, nil, [racc, boxed], "preserve_mostcc", nil, "w_bigint_add_mut", nil, nil, racc2)
  emit_wire_store_i64(wfn, r_slot, racc2)
  range_binding_invalidate(ctx, name)
  nil

# One accumulation step against the raw partial. Emitted for every
# `r = r ± e` / `r ±= e` the sum-chunk detection admitted; the flush arm
# is the cold path (the partial absorbs ~2^63 of magnitude between
# flushes when addends are small).
-> lower_sum_chunk_step(ctx, op, addend_node)
  wfn = ctx[:func]
  chunk = ctx[:sum_chunk]
  addend_tv = lower_expression(ctx, addend_node)
  addend_raw = ensure_raw_i64(wfn, addend_tv)
  if op == :MINUS
    neg = next_temp(wfn)
    emit_wire_sub_i64(wfn, "0", addend_raw, neg)
    addend_raw = neg
  pcur = next_temp(wfn)
  emit_wire_load_i64(wfn, chunk[:partial], pcur)
  sum = next_temp(wfn)
  emit_wire_sadd_with_overflow(wfn, pcur, addend_raw, sum)
  flush_label = next_label(wfn, "sc.flush")
  ok_label = next_label(wfn, "sc.ok")
  done_label = next_label(wfn, "sc.done")
  emit_wire_cond_br(wfn, sum + ".ovf", ok_label, :unlikely, flush_label)
  start_block(wfn, flush_label)
  boxed = next_temp(wfn)
  emit_wire_call_direct_i64(wfn, nil, [pcur], nil, nil, "w_int", nil, nil, boxed)
  racc = next_temp(wfn)
  emit_wire_load_i64(wfn, chunk[:acc], racc)
  racc2 = next_temp(wfn)
  emit_wire_call_direct_i64(wfn, nil, [racc, boxed], "preserve_mostcc", nil, "w_bigint_add_mut", nil, nil, racc2)
  emit_wire_store_i64(wfn, chunk[:acc], racc2)
  emit_wire_store_i64(wfn, chunk[:partial], addend_raw)
  emit_wire_br(wfn, done_label, nil, nil)
  start_block(wfn, ok_label)
  emit_wire_store_i64(wfn, chunk[:partial], sum)
  emit_wire_br(wfn, done_label, nil, nil)
  start_block(wfn, done_label)
  typed_value(:i64, w_nil.to_s())

# Copy a bindings map (nil-safe) — the versioned arms must not leak
# registers defined inside one arm into the other's lowering.
-> lv_bindings_copy(b)
  if b == nil
    return nil
  out = {}
  keys = b.keys()
  i = 0
  while i < keys.size()
    out[keys[i]] = b[keys[i]]
    i += 1
  out

# Current value of an int-typed var as a RAW i64 register.
-> lv_raw_int_value(ctx, wfn, name)
  tv = lower_expression(ctx, Tungsten:AST:Var.new(name))
  vt = ctx[:var_types][name]
  if is_machine_int_type(vt) || vt == :raw_int || vt == :raw_i64 || tv[:type] in (:raw_int :raw_i64 :raw_u64)
    return tv[:value]
  reg = ensure_i64_value(wfn, tv)
  nanunbox_int_emit(wfn, reg)

-> lower_while_versioned(ctx, node, ver)
  wfn = ctx[:func]
  arr_name = ver[:arr]
  arr_tv = lower_expression(ctx, Tungsten:AST:Var.new(arr_name))
  arr_reg = ensure_i64_value(wfn, arr_tv)
  chk_label = next_label(wfn, "lv.chk")
  fast_label = next_label(wfn, "lv.fast")
  slow_label = next_label(wfn, "lv.slow")
  done_label = next_label(wfn, "lv.done")
  # Guard 1: receiver is a live polymorphic WArray (obj space, subtag 10,
  # ebits 65) — the exact precondition of the unchecked inline path.
  g = next_temp(wfn)
  emit_wire_poly_array_guard(wfn, g, arr_reg)
  emit_wire_cond_br(wfn, g, slow_label, nil, chk_label)
  start_block(wfn, chk_label)
  # Guard 2: counter starts >= 0 (monotone +step keeps every index in
  # bounds against the loop condition / the checked bound below).
  i0 = lv_raw_int_value(ctx, wfn, ver[:ivar])
  c1 = next_temp(wfn)
  emit_wire_icmp_i64(wfn, i0, "sge", "0", c1)
  if ver[:bound_kind] == :var
    chk2_label = next_label(wfn, "lv.chk2")
    emit_wire_cond_br(wfn, c1, slow_label, nil, chk2_label)
    start_block(wfn, chk2_label)
    # Guard 3 (var bound): n <= size at entry; n is loop-invariant and the
    # body cannot resize the array (loop_version_spec rejects all calls).
    sz = next_temp(wfn)
    emit_wire_ta_size_raw(wfn, sz, arr_reg)
    nraw = lv_raw_int_value(ctx, wfn, ver[:bound_name])
    c2 = next_temp(wfn)
    emit_wire_icmp_i64(wfn, nraw, "sle", sz, c2)
    emit_wire_cond_br(wfn, c2, slow_label, nil, fast_label)
  else
    emit_wire_cond_br(wfn, c1, slow_label, nil, fast_label)
  saved_bindings = lv_bindings_copy(ctx[:bindings])
  start_block(wfn, fast_label)
  saved_vt = ctx[:var_types][arr_name]
  ctx[:var_types][arr_name] = :typed_array_w64
  lower_while_core(ctx, node)
  ctx[:var_types][arr_name] = saved_vt
  if !block_terminated(wfn)
    emit_wire_br(wfn, done_label, nil, nil)
  # The fast arm's register bindings do not dominate the slow arm.
  ctx[:bindings] = lv_bindings_copy(saved_bindings)
  start_block(wfn, slow_label)
  lower_while_core(ctx, node)
  if !block_terminated(wfn)
    emit_wire_br(wfn, done_label, nil, nil)
  start_block(wfn, done_label)
  nil

-> lower_while_core(ctx, node)
  wfn = ctx[:func]

  # Constant-fold the loop condition. `while true` (and `until false`,
  # which the parser desugars to `while !false`) collapses to a single
  # back-edge branch with no cond block at all. `while false` (and its
  # `until true` cousin) is a no-op — the body is unreachable.
  static_cond = static_bool_value(node.condition)
  if static_cond == :false
    return nil

  # Find variables safe to keep unboxed (only compound-assigned ints, no full assigns)
  unboxable = find_unboxable_loop_vars(node.body, node.condition, ctx[:var_types])
  # Wraparound array indexing (`tab[i & 1023]`) defeats LLVM's loop
  # vectorizer — it mis-peels the loop ~2.6x slower than its own unroller.
  # Stamp the latch to opt just this loop out; see loop_masked_array_index?.
  loop_novec = loop_masked_array_index?(node.body, find_loop_assigned_vars(node.body, node.condition))
  # Carry-chain kernels (addcarry/subborrow in the body) get an explicit
  # `llvm.loop.unroll.count` — LLVM won't unroll them on its own and the carry
  # flag spills across the back-edge; see loop_has_carry_intrinsic?. Keep the
  # measured default at 8 while allowing benchmark campaigns to tune or
  # disable it without rebuilding the compiler.
  loop_unroll_count = 0
  if loop_has_carry_intrinsic?(node.body)
    loop_unroll_count = carry_chain_unroll_count(ctx, node)
  # Inside a `Math.promote` / `Math.trap` block, suppress loop-var unboxing so
  # accumulators stay boxed WValues: their +/-/* then route through the
  # guarded path (lower_binary_op), which promotes to BigInt (promote) or
  # aborts (trap) on i48 overflow instead of truncating a raw i64 slot. The
  # default (nil) and explicit `Math.wrap` keep native unboxing intact.
  ovf_mode = ctx[:overflow_mode]
  if ovf_mode == :promote || ovf_mode == :trap
    unboxable = []
  unboxed = {}

  # Set up raw alloca slots: unbox current value, store raw.
  # For machine-int-typed vars (i64 etc.), the var slot already holds
  # a raw i64 — just reuse it directly; no __raw_ alloca needed.
  ui = 0
  while ui < unboxable.size()
    vname = unboxable[ui]
    vtype = ctx[:var_types][vname]
    if is_machine_int_type(vtype) || vtype == :raw_int || vtype == :raw_i64
      raw_slot = ensure_var_slot(wfn, vname, machine_slot_type(vtype))
      unboxed[vname] = raw_slot
    else
      raw_slot = ensure_var_slot(wfn, "__raw_" + vname)
      boxed_slot = ensure_var_slot(wfn, vname)
      cur = next_temp(wfn)
      emit_wire_load_i64(wfn, boxed_slot, cur)
      raw = nanunbox_int_emit(wfn, cur)
      emit_wire_store_i64(wfn, raw_slot, raw)
      unboxed[vname] = raw_slot
    ui += 1

  prev_unboxed = ctx[:unboxed_vars]
  active_unboxed = {}
  # Nested loops still need to see outer raw counters; inner loop vars override by name.
  if prev_unboxed != nil
    prev_names = prev_unboxed.keys()
    ui = 0
    while ui < prev_names.size()
      name = prev_names[ui]
      active_unboxed[name] = prev_unboxed[name]
      ui += 1
  unames = unboxed.keys()
  ui = 0
  while ui < unames.size()
    name = unames[ui]
    active_unboxed[name] = unboxed[name]
    ui += 1
  ctx[:unboxed_vars] = active_unboxed

  cond_label = next_label(wfn, "while.cond")
  body_label = next_label(wfn, "while.body")
  end_label = next_label(wfn, "while.end")

  if static_cond == :true
    # Skip the cond block entirely — entry branches directly to body,
    # `next` (continue) jumps to body, and the back-edge is the only
    # branch in the loop. After -O3 this is a single `b .Lbody` per
    # iteration — the theoretical minimum for an unbounded loop.
    emit_wire_br(wfn, body_label, nil, nil)
    cont_label = body_label
  else
    emit_wire_br(wfn, cond_label, nil, nil)
    start_block(wfn, cond_label)
    cond = lower_expression(ctx, node.condition)
    if cond[:type] == :i1
      cond_bool = cond[:value]
    else
      cond_reg = ensure_i64_value(wfn, cond)
      cond_bool = next_temp(wfn)
      emit_wire_truthy_inline(wfn, cond_bool, cond_reg)
    emit_wire_cond_br(wfn, cond_bool, end_label, nil, body_label)
    cont_label = cond_label

  # Body
  start_block(wfn, body_label)
  while_recycle_depth = wfn[:scope_recycle_stack].size()
  while_sid = next_scope_id(wfn)
  emit_scope_push(wfn, while_sid)
  push_loop_with_recycle_depth(wfn, end_label, cont_label, body_label, while_recycle_depth)
  lower_program(ctx, node.body)
  pop_loop(wfn)
  if !block_terminated(wfn)
    emit_scope_pop(wfn, while_sid)
    if loop_novec && loop_unroll_count > 0
      emit_wire_br(wfn, cont_label, true, loop_unroll_count)
    elsif loop_novec
      emit_wire_br(wfn, cont_label, true, nil)
    elsif loop_unroll_count > 0
      emit_wire_br(wfn, cont_label, nil, loop_unroll_count)
    else
      emit_wire_br(wfn, cont_label, nil, nil)
  else
    restore_recycle_scope_depth(wfn, while_recycle_depth)

  start_block(wfn, end_label)

  # Rebox unboxed vars back to WValue slots. As of 2026-04-15:
  # use w_int (runtime bigint-safe boxing) instead of inline
  # nanbox_int, because under silent-wrap native arithmetic the
  # accumulated value can exceed the 48-bit nanbox payload range.
  # Inline nanbox would mask to 48 bits and truncate. w_int handles
  # any i64 correctly, promoting to bigint when needed.
  unames = unboxed.keys()
  ui = 0
  while ui < unames.size()
    vname = unames[ui]
    vtype = ctx[:var_types][vname]
    already_raw = is_machine_int_type(vtype) || vtype == :raw_int || vtype == :raw_i64
    if already_raw != true
      raw_slot = unboxed[vname]
      raw = next_temp(wfn)
      emit_wire_load_i64(wfn, raw_slot, raw)
      boxed_temp = next_temp(wfn)
      emit_wire_call_direct_i64(wfn, nil, [raw], nil, nil, "__w_int_fast", nil, nil, boxed_temp)
      boxed_slot = wfn[:var_slots][vname]
      emit_wire_store_i64(wfn, boxed_slot, boxed_temp)
    ui += 1

  # Invalidate bindings for vars ASSIGNED inside the loop — their pre-loop
  # register bindings are now stale (the value lives in a loop-internal block).
  # Clearing ALL bindings (the old behavior) also dropped bindings for vars the
  # loop never touched, e.g. an `## i64`-typed param used after the loop: losing
  # its binding lost its raw-int type, so the later use re-materialized it as a
  # boxed WValue and mis-unboxed it (w_to_i64 on a raw param → "expected int,
  # got singleton"). A var not assigned in the loop keeps its binding, which is
  # still valid: its defining register dominates the loop-exit block.
  if ctx[:bindings] != nil && ctx[:bindings].size() > 0
    loop_assigned = find_loop_assigned_vars(node.body, node.condition)
    kept = {}
    bkeys = ctx[:bindings].keys()
    bi = 0
    while bi < bkeys.size()
      bname = bkeys[bi]
      if loop_assigned[bname] == nil
        kept[bname] = ctx[:bindings][bname]
      bi += 1
    ctx[:bindings] = kept

  ctx[:unboxed_vars] = prev_unboxed
  nil

-> lower_with(ctx, node)
  wfn = ctx[:func]
  materialize_bindings(ctx)
  bindings = node.bindings

  # Pre-compute binding info
  binding_info = []
  i = 0
  while i < bindings.size()
    binding = bindings[i]
    var_node = binding[0]
    collection = binding[1]
    name = var_node.name

    # Evaluate range bounds. Right-unbounded ranges (`1..`, `1...`) have
    # collection.to == nil and iterate forever until a `break` exits.
    #
    # Raw `:nanunbox_int` is bit extraction with no type check — correct
    # only when the bound is genuinely an inline-boxed int. A bound
    # statically known non-int (e.g. a Decimal literal like `1e10`) would
    # otherwise silently reinterpret its sig/scale bits as a small garbage
    # int instead of raising/coercing. Route those through
    # w_range_bound_i64 (real type check + coercion, catchable TypeError
    # on a non-whole bound); leave the fast nanunbox path untouched for
    # the common case (known int, or non-statically-typed but an int at
    # runtime).
    from_type = infer_type(collection.from, ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)
    to_type = infer_type(collection.to, ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)

    start_tv = lower_expression(ctx, collection.from)
    start_reg = ensure_i64_value(wfn, start_tv)
    start_raw = next_temp(wfn)
    if from_type != nil && !is_integer_like_type(from_type)
      emit_wire_call_direct_i64(wfn, nil, [start_reg], nil, nil, "w_range_bound_i64", nil, nil, start_raw)
    else
      emit_wire_nanunbox_int(wfn, start_reg, start_raw, start_raw + ".shl")

    unbounded = collection.to == nil
    end_raw = nil
    if !unbounded
      end_tv = lower_expression(ctx, collection.to)
      end_reg = ensure_i64_value(wfn, end_tv)
      end_raw = next_temp(wfn)
      if to_type != nil && !is_integer_like_type(to_type)
        emit_wire_call_direct_i64(wfn, nil, [end_reg], nil, nil, "w_range_bound_i64", nil, nil, end_raw)
      else
        emit_wire_nanunbox_int(wfn, end_reg, end_raw, end_raw + ".shl")

    cmp_op = "sle"
    if collection.exclusive == true
      cmp_op = "slt"

    pre_label = next_label(wfn, "with.pre")
    header_label = next_label(wfn, "with.hdr")
    body_label = next_label(wfn, "with.body")
    inc_label = next_label(wfn, "with.inc")
    exit_label = next_label(wfn, "with.exit")
    slot_type = "i64"
    if is_machine_int_type(from_type)
      slot_type = machine_slot_type(from_type)

    # Ensure variable has a slot
    ensure_var_slot(wfn, name, slot_type)

    binding_info.push({
      name: name,
      start_raw: start_raw,
      end_raw: end_raw,
      cmp_op: cmp_op,
      unbounded: unbounded,
      from_type: from_type,
      pre_label: pre_label,
      header_label: header_label,
      body_label: body_label,
      inc_label: inc_label,
      exit_label: exit_label
    })
    i += 1

  # Emit nested loop headers (outer to inner)
  i = 0
  while i < binding_info.size()
    info = binding_info[i]

    emit_wire_br(wfn, info[:pre_label], nil, nil)
    start_block(wfn, info[:pre_label])
    emit_wire_br(wfn, info[:header_label], nil, nil)

    start_block(wfn, info[:header_label])
    phi_reg = next_temp(wfn)
    inc_next = next_temp(wfn)
    emit_wire_phi_i64(wfn, info[:pre_label], info[:start_raw], info[:inc_label], inc_next, phi_reg)

    # Bound check — skipped for right-unbounded ranges (loop exits only via break).
    if info[:unbounded] == true
      emit_wire_br(wfn, info[:body_label], nil, nil)
    else
      cmp_reg = next_temp(wfn)
      emit_wire_icmp_i64(wfn, phi_reg, info[:cmp_op], info[:end_raw], cmp_reg)
      emit_wire_cond_br(wfn, cmp_reg, info[:exit_label], nil, info[:body_label])

    # Body entry: store counter to var slot, clear stale binding
    start_block(wfn, info[:body_label])
    slot = wfn[:var_slots][info[:name]]
    if is_machine_int_type(info[:from_type])
      emit_wire_dynamic_2(wfn, machine_store_op(info[:from_type]), :ptr, slot, :value, phi_reg)
    else
      boxed_tv = nanbox_int_emit(wfn, phi_reg)
      emit_wire_store_i64(wfn, slot, boxed_tv[:value])
    if ctx[:bindings][info[:name]] != nil
      ctx[:bindings][info[:name]] = nil
    # Infer iteration variable type from range bounds
    if info[:from_type] != nil
      ctx[:var_types][info[:name]] = info[:from_type]

    # Store phi and inc names for later
    info[:phi_reg] = phi_reg
    info[:inc_next] = inc_next
    i += 1

  # Set loop context: break to outermost exit, next to innermost inc
  outermost_exit = binding_info[0][:exit_label]
  innermost_inc = binding_info[binding_info.size() - 1][:inc_label]
  with_recycle_depth = wfn[:scope_recycle_stack].size()
  with_sid = next_scope_id(wfn)
  emit_scope_push(wfn, with_sid)
  push_loop_with_recycle_depth(wfn, outermost_exit, innermost_inc, nil, with_recycle_depth)

  # Emit the body
  lower_program(ctx, node.body)
  pop_loop(wfn)
  if !block_terminated(wfn)
    emit_scope_pop(wfn, with_sid)
  else
    restore_recycle_scope_depth(wfn, with_recycle_depth)

  # Emit inc and exit blocks (inner to outer)
  i = binding_info.size() - 1
  while i >= 0
    info = binding_info[i]
    if !block_terminated(wfn)
      emit_wire_br(wfn, info[:inc_label], nil, nil)
    start_block(wfn, info[:inc_label])
    emit_wire_add_i64(wfn, info[:phi_reg], "1", info[:inc_next])
    emit_wire_br(wfn, info[:header_label], nil, nil)
    start_block(wfn, info[:exit_label])
    i -= 1
  nil

-> lower_break(ctx)
  wfn = ctx[:func]
  loop_info = current_loop(wfn)
  if loop_info != nil
    # Run the ensure bodies and pop the frames of begin regions opened
    # inside the loop body that this break abandons (spec 4.6.5).
    base_eh = loop_info[:eh_depth]
    if base_eh == nil
      base_eh = wfn[:eh_depth]
    ensure_base = loop_info[:ensure_base]
    if ensure_base == nil
      ensure_base = wfn[:ensure_stack].size()
    emit_transfer_unwind(ctx, wfn, ensure_base, base_eh)
    if block_terminated(wfn)
      return nil
    recycle_depth = loop_info[:recycle_depth]
    if recycle_depth == nil
      recycle_depth = wfn[:scope_recycle_stack].size()
    emit_recycles_above_depth(wfn, recycle_depth)
    emit_wire_br(wfn, loop_info[:break_label], nil, nil)
  nil

-> lower_next(ctx)
  wfn = ctx[:func]
  # Inside a .each / iterator block, `next` returns from the block (not the
  # enclosing loop, which doesn't exist as a wire-level loop). The iterator
  # will continue to the next element. Matches Ruby semantics.
  if ctx[:is_block] == true
    # Leaving the block function runs the ensure bodies of and abandons the
    # frames of any begin regions opened inside it (spec 4.6.5).
    emit_transfer_unwind(ctx, wfn, 0, 0)
    if block_terminated(wfn)
      return nil
    # The finalizer handles the function-body scope before this ret; flush only
    # nested lexical scopes here so no value is recycled twice.
    emit_recycles_above_depth(wfn, 1)
    emit_return_instruction(wfn, wire_make_ret_i64(nil, w_nil.to_s()))
    return nil
  loop_info = current_loop(wfn)
  if loop_info != nil
    # Run the ensure bodies and pop the frames of begin regions opened
    # inside the loop body that this next abandons (spec 4.6.5).
    base_eh = loop_info[:eh_depth]
    if base_eh == nil
      base_eh = wfn[:eh_depth]
    ensure_base = loop_info[:ensure_base]
    if ensure_base == nil
      ensure_base = wfn[:ensure_stack].size()
    emit_transfer_unwind(ctx, wfn, ensure_base, base_eh)
    if block_terminated(wfn)
      return nil
    recycle_depth = loop_info[:recycle_depth]
    if recycle_depth == nil
      recycle_depth = wfn[:scope_recycle_stack].size()
    emit_recycles_above_depth(wfn, recycle_depth)
    emit_wire_br(wfn, loop_info[:next_label], nil, nil)
  nil

# `recase [expr]` — re-dispatch the innermost enclosing case. With a value:
# store it as the new subject. Bare: re-evaluate the original subject (so
# `case next_token()` advances). Then branch back to the case's dispatch header
# (a synthetic loop back-edge; the subject var slot picks up the new value).
-> lower_recase(ctx, node)
  wfn = ctx[:func]
  info = current_case(wfn)
  if info == nil
    << "recase used outside a case statement"
    exit 1
  if node.value != nil
    if info[:subj_ptr] == nil
      << "recase with a value requires a case with a subject"
      exit 1
    new_tv = lower_expression(ctx, node.value)
    new_reg = ensure_i64_value(wfn, new_tv)
    materialize_bindings(ctx)
    emit_wire_store_i64(wfn, info[:subj_ptr], new_reg)
  elsif info[:subject_node] != nil
    # Bare recase on a value-case: re-evaluate the original subject expression.
    new_tv = lower_expression(ctx, info[:subject_node])
    new_reg = ensure_i64_value(wfn, new_tv)
    materialize_bindings(ctx)
    emit_wire_store_i64(wfn, info[:subj_ptr], new_reg)
  else
    # Bare recase on a subject-less cond-case: just re-test the conditions.
    materialize_bindings(ctx)
  # Branching back to the case header abandons any begin regions opened
  # between the header and this recase; run their ensure bodies and pop
  # their frames (spec 4.6.5).
  base_eh = info[:eh_depth]
  if base_eh == nil
    base_eh = wfn[:eh_depth]
  ensure_base = info[:ensure_base]
  if ensure_base == nil
    ensure_base = wfn[:ensure_stack].size()
  emit_transfer_unwind(ctx, wfn, ensure_base, base_eh)
  if block_terminated(wfn)
    return typed_value(:i64, w_nil.to_s())
  emit_wire_br(wfn, info[:redispatch_label], nil, nil)
  typed_value(:i64, w_nil.to_s())

# Scan a statement body for a `recase` that targets THIS case. Descends into
# if/while/begin/with bodies but STOPS at a nested case (which owns its own
# recase). Used to decide whether a case needs the structured re-dispatch form.
-> body_contains_recase?(body)
  if body == nil
    return false
  i = 0
  while i < body.size()
    if node_contains_recase?(body[i])
      return true
    i += 1
  false

-> node_contains_recase?(node)
  if node == nil || !is_ast_node?(node)
    return false
  t = ast_kind(node)
  if t == :recase
    return true
  if t == :case || t == :case_value
    return false
  if t == :if
    if body_contains_recase?(node.then_body)
      return true
    if body_contains_recase?(node.else_body)
      return true
    ec = node.elsif_clauses
    if ec != nil
      j = 0
      while j < ec.size()
        if ec[j] != nil && ec[j].size() >= 2 && body_contains_recase?(ec[j][1])
          return true
        j += 1
    return false
  if t == :while
    return body_contains_recase?(node.body)
  if t == :begin
    if body_contains_recase?(node.body)
      return true
    if body_contains_recase?(node.rescue_body)
      return true
    return body_contains_recase?(node.ensure_body)
  if t == :with || t == :parallel_with
    return body_contains_recase?(node.body)
  false

-> lower_return(ctx, node)
  wfn = ctx[:func]

  if ctx[:is_block] == true && ctx[:block_return_frame] != nil
    frame_reg = ctx[:block_return_frame]
    if frame_reg[0] != "%"
      frame_val = lower_var(ctx, Tungsten:AST:Var.new(frame_reg))
      frame_reg = ensure_i64_value(wfn, frame_val)
    if node.value != nil
      val = lower_expression(ctx, node.value)
      val_reg = ensure_i64_value(wfn, val)
    else
      val_reg = w_nil.to_s()
    # Run the ensure bodies of begin regions opened inside this block
    # function that the non-local return abandons (spec 4.6.5). eh_base is
    # the current depth: only interleaved pops are needed here — the
    # signal's longjmp restores w_exception_stack to the target frame's
    # snapshot itself.
    emit_transfer_unwind(ctx, wfn, 0, wfn[:eh_depth])
    if block_terminated(wfn)
      return nil
    # This longjmp never reaches the block function's ret/finalizer, so clean
    # the function-body entry as well as all nested lexical scopes.
    emit_recycles_above_depth(wfn, 0)
    emit_wire_call_direct_void(wfn, [frame_reg, val_reg], "w_block_return_signal")
    emit_wire_unreachable(wfn)
    return nil

  if wfn[:exit_label] != nil && wfn[:result_slot] != nil
    if node.value != nil
      val = lower_expression(ctx, node.value)
      val_reg = ensure_i64_value(wfn, val)
    else
      val_reg = w_nil.to_s()
    # Returning from inside begin regions runs their ensure bodies and
    # abandons their frames (spec 4.6.5) — the fall-through pops/ensures
    # are never reached on this path.
    emit_transfer_unwind(ctx, wfn, 0, 0)
    if block_terminated(wfn)
      return nil
    # The common exit ret intentionally owns no recycle values: its catch edge
    # is reached by a runtime unwind, while a normal return must clean the
    # exact compile-time prefix live at this transfer before joining it.
    emit_recycles_above_depth(wfn, 0)
    emit_wire_store_i64(wfn, wfn[:result_slot], val_reg)
    emit_wire_br(wfn, wfn[:exit_label], nil, nil)
    return nil

  if node.value != nil
    val = lower_expression(ctx, node.value)
    val_reg = ensure_return_value(ctx, val, node.value)
  else
    val_reg = default_return_value(wfn)

  # Run the ensure bodies of and pop the frames of any begin regions this
  # return abandons (spec 4.6.5).
  emit_transfer_unwind(ctx, wfn, 0, 0)
  if block_terminated(wfn)
    return nil
  # Function-body values are injected once by insert_function_scope_recycles;
  # this path-specific flush covers only nested scopes abandoned by return.
  emit_recycles_above_depth(wfn, 1)

  if wfn[:return_type] == "i64"
    emit_return_instruction(wfn, wire_make_ret_i64(nil, val_reg))
  elsif wfn[:return_type] == "i32"
    # Truncate for main
    temp = next_temp(wfn)
    emit_wire_trunc_i64_i32(wfn, temp, val_reg)
    emit_return_instruction(wfn, wire_make_ret_i32(temp))
  nil

-> default_return_value(wfn)
  ret_type = wfn[:raw_return_type]
  if ret_type != nil && is_raw_int_storage_type(ret_type)
    return "0"
  w_nil.to_s()

-> ensure_return_value(ctx, tv, node)
  wfn = ctx[:func]
  ret_type = wfn[:raw_return_type]
  if ret_type != nil && is_raw_int_storage_type(ret_type)
    inferred = nil
    if node != nil
      inferred = infer_type(node, ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)
    return ensure_raw_machine_int(wfn, tv, ret_type, inferred)
  ensure_i64_value(wfn, tv)

# -- Method definitions --

-> has_nonlocal_block_return(body)
  if body == nil
    return false
  i = 0
  while i < body.size()
    if has_nonlocal_block_return_in_node(body[i], false)
      return true
    i += 1
  false

-> has_nonlocal_block_return_in_node(node, in_block)
  if node == nil
    return false
  if type(node) == "Array"
    i = 0
    while i < node.size()
      if has_nonlocal_block_return_in_node(node[i], in_block)
        return true
      i += 1
    return false
  if !is_ast_node?(node)
    return false

  ntype = ast_kind(node)
  case ntype
  when :call
    if has_nonlocal_block_return_in_node(node.receiver, in_block)
      return true
    if has_nonlocal_block_return_in_node(node.args, in_block)
      return true
    if node.block != nil
      return has_nonlocal_block_return_in_node(node.block.body, true)
    return false
  when :return
    return in_block
  when :method_def, :fn_def, :class_def
    return false
  when :block
    return has_nonlocal_block_return_in_node(node.body, true)

  when :program
    return has_nonlocal_block_return_in_node(node.expressions, in_block)

  when :array
    return has_nonlocal_block_return_in_node(node.elements, in_block)

  when :hash_literal
    return has_nonlocal_block_return_in_node(node.entries, in_block)

  when :string_interp, :byte_array_interp
    return has_nonlocal_block_return_in_node(node.parts, in_block)

  when :typed_array_new, :typed_array, :view_access
    return has_nonlocal_block_return_in_node(node.size, in_block) || has_nonlocal_block_return_in_node(node.index, in_block)

  when :assign, :compound_assign
    return has_nonlocal_block_return_in_node(node.target, in_block) || has_nonlocal_block_return_in_node(node.value, in_block)

  when :multi_assign
    return has_nonlocal_block_return_in_node(node.targets, in_block) || has_nonlocal_block_return_in_node(node.value, in_block)

  when :binary_op, :and, :or, :target_and, :target_or
    return has_nonlocal_block_return_in_node(node.left, in_block) || has_nonlocal_block_return_in_node(node.right, in_block)

  when :unary_op, :not
    return has_nonlocal_block_return_in_node(node.operand, in_block)

  when :target_not
    return has_nonlocal_block_return_in_node(node.expression, in_block)

  when :in_test
    return has_nonlocal_block_return_in_node(node.lhs, in_block) || has_nonlocal_block_return_in_node(node.elements, in_block)

  when :range
    return has_nonlocal_block_return_in_node(node.from, in_block) || has_nonlocal_block_return_in_node(node.to, in_block)

  when :if
    if has_nonlocal_block_return_in_node(node.condition, in_block)
      return true
    if has_nonlocal_block_return_in_node(node.then_body, in_block)
      return true
    if has_nonlocal_block_return_in_node(node.elsif_clauses, in_block)
      return true
    return has_nonlocal_block_return_in_node(node.else_body, in_block)

  when :while
    return has_nonlocal_block_return_in_node(node.condition, in_block) || has_nonlocal_block_return_in_node(node.body, in_block)

  when :with, :parallel_with
    return has_nonlocal_block_return_in_node(node.bindings, in_block) || has_nonlocal_block_return_in_node(node.body, in_block)

  when :case
    return has_nonlocal_block_return_in_node(node.whens, in_block) || has_nonlocal_block_return_in_node(node.else_body, in_block)

  when :when
    return has_nonlocal_block_return_in_node(node.conditions, in_block) || has_nonlocal_block_return_in_node(node.body, in_block)

  when :case_value
    if has_nonlocal_block_return_in_node(node.subject, in_block)
      return true
    if has_nonlocal_block_return_in_node(node.arms, in_block)
      return true
    return has_nonlocal_block_return_in_node(node.else_body, in_block)

  when :case_arm
    if has_nonlocal_block_return_in_node(node.pattern, in_block)
      return true
    if has_nonlocal_block_return_in_node(node.guard, in_block)
      return true
    return has_nonlocal_block_return_in_node(node.body, in_block)

  when :safe_nav
    if has_nonlocal_block_return_in_node(node.receiver, in_block)
      return true
    if has_nonlocal_block_return_in_node(node.args, in_block)
      return true
    return has_nonlocal_block_return_in_node(node.block, in_block)

  when :rescue_expr
    return has_nonlocal_block_return_in_node(node.body, in_block) || has_nonlocal_block_return_in_node(node.fallback, in_block)

  when :puts
    vals = node.value
    i = 0
    while i < vals.size()
      if has_nonlocal_block_return_in_node(vals[i], in_block)
        return true
      i += 1
    return false

  when :print, :raise
    return has_nonlocal_block_return_in_node(node.value, in_block)

  when :module_def, :trait_def
    return has_nonlocal_block_return_in_node(node.body, in_block)

  when :gpu_kernel_def
    return false

  when :param
    return has_nonlocal_block_return_in_node(node.default, in_block)

  when :begin
    if has_nonlocal_block_return_in_node(node.body, in_block)
      return true
    if has_nonlocal_block_return_in_node(node.rescue_body, in_block)
      return true
    return has_nonlocal_block_return_in_node(node.ensure_body, in_block)

  when :yield, :super
    return has_nonlocal_block_return_in_node(node.args, in_block)

  when :go
    return has_nonlocal_block_return_in_node(node.body, in_block)

  when :schedule_def, :layout_def
    return has_nonlocal_block_return_in_node(node.directives, in_block)

  when :on_guard
    return has_nonlocal_block_return_in_node(node.predicate, in_block) || has_nonlocal_block_return_in_node(node.body, in_block)

  when :regex_match
    return has_nonlocal_block_return_in_node(node.regex, in_block) || has_nonlocal_block_return_in_node(node.subject, in_block)

  when :cidr_match
    return has_nonlocal_block_return_in_node(node.subject, in_block) || has_nonlocal_block_return_in_node(node.cidr, in_block)

  else
    false


# -- Case/When --

# True when any arm body (or the else body) of a value-case contains a recase
# that targets this case.
-> case_value_has_recase?(node)
  arms = node.arms
  i = 0
  while i < arms.size()
    if body_contains_recase?(arms[i].body)
      return true
    i += 1
  body_contains_recase?(node.else_body)

-> lower_case_value(ctx, node)
  has_recase = case_value_has_recase?(node)

  # The switch_i64 fast path can't host the re-dispatch back-edge, so
  # recase-cases fall through to the if/elsif desugar below.
  if !has_recase
    switch_result = lower_case_value_switch(ctx, node)
    if switch_result != nil
      return switch_result

  arms = node.arms
  if arms.size() == 0
    if node.else_body != nil
      return lower_body_value(ctx, node.else_body)
    return typed_value(:i64, w_nil.to_s())

  # Evaluate subject once and store in a var slot
  wfn = ctx[:func]
  subj_var = "__case_subj." + next_label(wfn, "cv")
  subj_ptr = ensure_var_slot(wfn, subj_var)
  subj_tv = lower_expression(ctx, node.subject)

  # Propagate subject type so comparisons in when-arms use raw ops. For
  # recase-cases the subject slot is rewritten by `recase` with a boxed value,
  # so it must stay boxed (skip the machine-int raw fast path) to keep the
  # initial store and the recase store type-consistent.
  subj_type = infer_type(node.subject, ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)
  if !has_recase && subj_type != nil && is_machine_int_type(subj_type)
    # Machine int subject: store raw value directly (no boxing)
    raw_reg = ensure_raw_machine_int(wfn, subj_tv, subj_type, subj_type)
    emit_wire_store_i64(wfn, subj_ptr, raw_reg)
    ctx[:var_types][subj_var] = subj_type
  else
    subj_reg = ensure_i64_value(wfn, subj_tv)
    emit_wire_store_i64(wfn, subj_ptr, subj_reg)
    # The slot holds a BOXED value; recording a float type would make the
    # when-arm comparisons read it as a raw f64 (invalid bitcast IR). Only
    # propagate types whose var reads expect boxed storage.
    if !has_recase && subj_type != nil && subj_type != :float && !is_machine_float_type(subj_type)
      ctx[:var_types][subj_var] = subj_type

  # recase: open the re-dispatch header (a synthetic loop). `recase` rewrites
  # subj_var and branches back here; the if/elsif chain below re-reads subj_var.
  if has_recase
    redispatch_header = next_label(wfn, "recase.head")
    materialize_bindings(ctx)
    emit_wire_br(wfn, redispatch_header, nil, nil)
    start_block(wfn, redispatch_header)
    push_case(wfn, {subj_ptr: subj_ptr, subject_node: node.subject, redispatch_label: redispatch_header})

  # Build a pre-lowered AST node that loads from the var slot
  subj_ref = Tungsten:AST:Var.new(subj_var)

  # First arm → if condition
  first = arms[0]
  condition = case_value_pattern_condition(subj_ref, first.pattern)
  if first.guard != nil
    condition = Tungsten:AST:And.new(condition, first.guard)

  # Remaining arms → elsif clauses
  elsif_clauses = []
  ai = 1
  while ai < arms.size()
    arm = arms[ai]
    arm_cond = case_value_pattern_condition(subj_ref, arm.pattern)
    if arm.guard != nil
      arm_cond = Tungsten:AST:And.new(arm_cond, arm.guard)
    elsif_clauses.push([arm_cond, arm.body])
    ai += 1

  if_node = Tungsten:AST:If.new(condition, first.body, elsif_clauses, node.else_body)
  result = lower_if_expr(ctx, if_node)
  if has_recase
    pop_case(wfn)
  result

-> case_switch_literal_value(pattern)
  if ast_kind(pattern) == :int
    return pattern.value.to_i()
  if ast_kind(pattern) == :char
    return pattern.value.to_i()
  # SSO-5 symbols / strings (≤5 bytes) have a deterministic
  # compile-time WValue. Symbols add the `| 1` symbol bit; strings
  # don't. Medium-length (6-61 bytes) symbols and strings are also
  # switchable — slab-interned at module-load with a WValue of the
  # form `w_tag_stringsym + 12 + slot_index * 16`, but slot_index
  # isn't assigned until build_string_wvalues runs at emit time.
  # Those go through the string_id deferral path (returning nil
  # here so the caller can detect and register the string).
  if ast_kind(pattern) == :symbol
    s = pattern.value.to_s()
    if utf8_byte_length(s) <= 5
      return sso5_wvalue(s) + 1
  if ast_kind(pattern) == :string
    s = pattern.value.to_s()
    if utf8_byte_length(s) <= 5
      return sso5_wvalue(s)
  nil

# Returns :symbol if every arm pattern is a switchable symbol
# literal (SSO-5 or slab-interned), :string if every arm is a
# switchable string literal, nil otherwise. Mixed arm types are
# rejected — case-on-string vs case-on-symbol semantics differ at
# runtime equality (symbol bit), and mixing them in one switch
# would conflate the two interned spaces. Heap-mode literals
# (>61 bytes) disqualify the whole switch because their WValues
# are allocator-dependent.
-> case_switch_interned_kind(arms)
  k = nil
  i = 0
  while i < arms.size()
    pattern = arms[i].pattern
    pk = ast_kind(pattern)
    if pk != :symbol && pk != :string
      return nil
    if k == nil
      k = pk
    elsif k != pk
      return nil
    s = pattern.value.to_s()
    if utf8_byte_length(s) > 61
      return nil
    i += 1
  k

-> case_switch_simple_body?(body)
  if body == nil || body.size() != 1
    return false
  t = ast_kind(body[0])
  # :return and :raise both terminate their block cleanly — lower_if_expr_body
  # calls lower_statement on them, which emits `ret i64` / the raise path, and
  # the block is marked terminated so the result-ptr store is skipped. Allowing
  # them here enables switch_i64 for the hot dispatch functions in pass_registry
  # (lower_statement / lower_expression) whose arms are all `return lower_X(…)`.
  t != :if && t != :while && t != :with && t != :parallel_with && t != :case && t != :case_value && t != :begin && t != :method_def && t != :fn_def && t != :class_def

# True when every arm pattern is an integer (or char) literal. Used
# to relax the case-switch gate the same way case_switch_interned_kind
# relaxes it for symbol/string arms: when the arm patterns themselves
# determine the literal type, we don't need infer_type to confirm
# the subject's type. The subject's runtime form must produce
# integer-compatible bits — ensure_raw_machine_int handles raw_int
# directly and nanunboxes :i64-typed values; mismatched subjects
# (e.g. a string passed to an int-case) will simply not match any
# arm and fall through to the default.
-> case_switch_all_int_literals?(arms)
  i = 0
  while i < arms.size()
    pattern = arms[i].pattern
    pk = ast_kind(pattern)
    if pk != :int && pk != :char
      return false
    i += 1
  true

-> lower_case_value_switch(ctx, node)
  arms = node.arms
  if arms.size() < 3
    return nil
  if node.else_body != nil && !case_switch_simple_body?(node.else_body)
    return nil

  # Four switchable shapes:
  #   1a. All arms are integer literals AND subject infers to an
  #       integer-like type → dispatch with dense-range heuristic.
  #   1b. All arms are integer literals (regardless of subject's
  #       inferred type) → trust the arm literals as switch keys;
  #       ensure_raw_machine_int handles whatever the subject
  #       actually is at runtime (raw_int pass-through, :i64
  #       nanunbox). Mismatched subjects don't match any arm.
  #   2. All arms are symbol literals (≤61 bytes) → keys are the
  #      symbols' WValues with the `| 1` symbol bit set.
  #   3. All arms are string literals (≤61 bytes) → same as (2)
  #      but without the symbol bit; subject must hold a string
  #      WValue at runtime.
  # For (2) and (3): SSO-5 keys are inline i64 literals; medium
  # (6-61 byte) keys defer to emit time via the string_id form,
  # where build_string_wvalues assigns slot indices and the
  # emitter resolves to the slab WValue. Sparse keys are fine
  # (LLVM uses binary search).
  interned_kind = case_switch_interned_kind(arms)
  symbol_switch = interned_kind == :symbol
  string_switch = interned_kind == :string
  interned_switch = symbol_switch || string_switch
  all_int_arms = case_switch_all_int_literals?(arms)
  subj_type = infer_type(node.subject, ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)
  # If we have neither an interned-arm shape nor an all-integer-arm
  # shape, we need the subject's type to confirm it's integer-like.
  # When all arms ARE integer literals, the arm types determine the
  # value space — relax the subject-type gate (same principle as the
  # interned-switch relaxation). Still reject if subj_type is known
  # to be incompatible (e.g. :string), since the case would always
  # take the default and we'd waste compile time on a switch that
  # never matches.
  if !interned_switch && !all_int_arms
    if subj_type == nil || !is_integer_like_type(subj_type) || is_machine_int128_type(subj_type)
      return nil
  if all_int_arms && subj_type != nil && !is_integer_like_type(subj_type) && !interned_switch
    # Subject statically known to be non-integer → don't compile as int switch.
    return nil

  seen = {}
  cases = []
  min_v = nil
  max_v = nil
  i = 0
  while i < arms.size()
    arm = arms[i]
    if arm.guard != nil
      return nil
    if !case_switch_simple_body?(arm.body)
      return nil
    pattern = arm.pattern
    v = case_switch_literal_value(pattern)
    str_id = nil
    if v == nil
      # Medium-length symbol/string (6-61 bytes): defer WValue to
      # emit time via string_id. Bail unless this is an
      # interned-switch shape.
      if !interned_switch
        return nil
      s = pattern.value.to_s()
      str_id = module_string_constant(ctx[:mod], s)
      key = "sid:" + str_id.to_s()
      if seen[key] == true
        return nil
      seen[key] = true
      cases.push({value: nil, string_id: str_id, arm: arm})
    else
      # Skip i64-min conservatively; spelling -2^63 is not portable across
      # host/self-host literal paths.
      max_i64 = 9223372036854775807
      if v < 0 - max_i64 || v > max_i64
        return nil
      key = v.to_s()
      if seen[key] == true
        return nil
      seen[key] = true
      if min_v == nil || v < min_v
        min_v = v
      if max_v == nil || v > max_v
        max_v = v
      cases.push({value: v, arm: arm})
    i += 1

  # Density check applies only to the type-inferred integer-switch
  # shape (case 1a). For interned switches and all-integer-arm
  # switches with non-inferred subjects (case 1b), LLVM picks the
  # right lowering strategy (jump table, bit test, or binary
  # search) based on the actual key distribution — any of which is
  # strictly better than the O(N) if-chain. KIND_X-style dispatches
  # have sparse keys (~1-150) but ≥3 arms; LLVM handles them well
  # via binary search even though they fail the 2N-span heuristic.
  if !interned_switch && !all_int_arms
    span = max_v - min_v + 1
    if span > arms.size() * 2
      return nil

  wfn = ctx[:func]
  result_var = "__case_switch." + next_label(wfn, "cs")
  result_ptr = ensure_var_slot(wfn, result_var)
  emit_wire_store_i64(wfn, result_ptr, w_nil.to_s())

  subj_tv = lower_expression(ctx, node.subject)
  # Interned (symbol/string) subject: the WValue's raw i64 bits ARE
  # the switch key. No unbox needed because the keys are themselves
  # raw WValue bits. Use ensure_i64_value to materialize the boxed
  # WValue in a register; the LLVM switch_i64 treats it as i64.
  subj_raw = nil
  if interned_switch
    subj_boxed = ensure_i64_value(wfn, subj_tv)
    # Canonicalize: slab-stored/heap short strings and symbols carry
    # different WValue bits than the SSO literal keys baked into the
    # switch; w_switch_canonical repacks ≤5-byte content to SSO bits
    # (longer content already matches by slab id).
    subj_raw = next_temp(wfn)
    emit_wire_call_direct_i64(wfn, nil, [subj_boxed], nil, nil, "w_switch_canonical", nil, nil, subj_raw)
  else
    subj_raw = ensure_raw_machine_int(wfn, subj_tv, :i64, subj_type)
  default_label = next_label(wfn, "case.default")
  end_label = next_label(wfn, "case.end")

  i = 0
  while i < cases.size()
    cases[i][:label] = next_label(wfn, "case.arm")
    i += 1

  # is_symbol tells the emitter whether to OR in the `| 1` symbol
  # bit when resolving medium-length string_id keys. SSO-5 keys
  # already have the bit baked into their literal value, so they
  # don't need this flag.
  emit_wire_switch_i64(wfn, cases, default_label, symbol_switch, subj_raw)

  i = 0
  while i < cases.size()
    c = cases[i]
    start_block(wfn, c[:label])
    body = c[:arm].body
    if body != nil && body.size() > 0
      lower_if_expr_body(ctx, wfn, body, result_ptr)
    materialize_bindings(ctx)
    if !block_terminated(wfn)
      emit_wire_br(wfn, end_label, nil, nil)
    i += 1

  start_block(wfn, default_label)
  if node.else_body != nil && node.else_body.size() > 0
    lower_if_expr_body(ctx, wfn, node.else_body, result_ptr)
  materialize_bindings(ctx)
  if !block_terminated(wfn)
    emit_wire_br(wfn, end_label, nil, nil)

  start_block(wfn, end_label)
  result = next_temp(wfn)
  emit_wire_load_i64(wfn, result_ptr, result)
  typed_value(:i64, result)

# True when any when-arm body (or the else body) of a subject-less cond-case
# contains a recase targeting this case.
-> case_cond_has_recase?(node)
  whens = node.whens
  i = 0
  while i < whens.size()
    if body_contains_recase?(whens[i].body)
      return true
    i += 1
  body_contains_recase?(node.else_body)

-> lower_case(ctx, node)
  whens = node.whens
  if whens.size() == 0
    if node.else_body != nil
      return lower_body_value(ctx, node.else_body)
    return typed_value(:i64, w_nil.to_s())

  wfn = ctx[:func]
  has_recase = case_cond_has_recase?(node)

  # recase: open the re-dispatch header. A subject-less case has no subject to
  # rewrite — bare `recase` just re-tests the conditions (subj_ptr/subject_node
  # are nil; lower_recase only branches back).
  if has_recase
    redispatch_header = next_label(wfn, "recase.head")
    materialize_bindings(ctx)
    emit_wire_br(wfn, redispatch_header, nil, nil)
    start_block(wfn, redispatch_header)
    push_case(wfn, {subj_ptr: nil, subject_node: nil, redispatch_label: redispatch_header})

  # First when → if condition (OR multiple conditions)
  first = whens[0]
  condition = first.conditions[0]
  ci = 1
  while ci < first.conditions.size()
    condition = Tungsten:AST:Or.new(condition, first.conditions[ci])
    ci += 1

  # Remaining whens → elsif clauses
  elsif_clauses = []
  wi = 1
  while wi < whens.size()
    w = whens[wi]
    wcond = w.conditions[0]
    wci = 1
    while wci < w.conditions.size()
      wcond = Tungsten:AST:Or.new(wcond, w.conditions[wci])
      wci += 1
    elsif_clauses.push([wcond, w.body])
    wi += 1

  if_node = Tungsten:AST:If.new(condition, first.body, elsif_clauses, node.else_body)
  result = lower_if_expr(ctx, if_node)
  if has_recase
    pop_case(wfn)
  result

# Lower a @fastmath / @strictmath scoped block.
# Temporarily sets ctx[:math_mode_override] to :fast or :strict so float_inst_flags
# and the fmuladd peephole see the right mode while lowering the body.
# The block is a hash node {node: :fastmath_block, body: [stmts]}.
-> lower_mathmode_block(ctx, node, mode)
  saved_override = ctx[:math_mode_override]
  ctx[:math_mode_override] = mode
  body = node[:body]
  result = lower_body_value(ctx, body)
  ctx[:math_mode_override] = saved_override
  result

# Lower a `Math.promote / Math.trap / Math.wrap -> body` scoped integer-
# overflow-mode block. Temporarily sets ctx[:overflow_mode] (:promote /
# :trap / :wrap) so that default int +/-/* inside the body route through the
# guarded promote/trap path (or explicit native silent-wrap) in
# lower_binary_op. LEXICAL: only governs the block's own statements; called
# functions keep their own mode. NESTING: inner overrides outer; the
# enclosing mode is restored on exit. The block is a hash node
# {node: :overflow_block, mode:, body: [stmts]}.
-> lower_overflow_block(ctx, node)
  saved_mode = ctx[:overflow_mode]
  ctx[:overflow_mode] = node[:mode]
  result = lower_body_value(ctx, node[:body])
  ctx[:overflow_mode] = saved_mode
  result

-> lower_body_value(ctx, body)
  wfn = ctx[:func]
  if body == nil || body.size() == 0
    return typed_value(:i64, w_nil.to_s())

  i = 0
  while i < body.size() - 1
    lower_statement(ctx, body[i])
    i += 1

  last = body[body.size() - 1]
  last_t = ast_kind(last)
  # (:begin left OFF this list 2026-07-22: begin/rescue is a value expression)
  if last_t in (:return :puts :print :raise :while :method_def :fn_def :class_def)
    lower_statement(ctx, last)
    return typed_value(:i64, w_nil.to_s())
  lower_expression(ctx, last)

-> case_value_pattern_condition(subject, pattern)
  if ast_kind(pattern) == :range
    lower_cmp = Tungsten:AST:BinaryOp.new(subject, :GTE, pattern.from)
    upper_op = :LTE
    if pattern.exclusive == true
      upper_op = :LT
    upper_cmp = Tungsten:AST:BinaryOp.new(subject, upper_op, pattern.to)
    return Tungsten:AST:And.new(lower_cmp, upper_cmp)
  # CIDR pattern: case ip when 10.0.0.0/8 → w_ipv4_in_cidr(subject, cidr)
  if ast_kind(pattern) == :cidr4
    return Tungsten:AST:CidrMatch.new(subject, pattern)
  if ast_kind(pattern) == :regex
    return Tungsten:AST:RegexMatch.new(pattern, subject)
  Tungsten:AST:BinaryOp.new(subject, :EQ, pattern)

# -- Exception handling --

# Emit `count` w_exception_pop calls. Used by every control transfer that
# abandons open begin/rescue try regions (return/break/next/recase): the
# fall-through pop in lower_begin is never reached on those paths, and a
# stale frame left on w_exception_stack makes the next raise longjmp into
# a dead (since-clobbered) stack frame.
-> emit_eh_pops(wfn, count)
  i = 0
  while i < count
    emit_wire_call_direct_void(wfn, [], "w_exception_pop")
    i += 1
  nil

# Unwind emission for a control transfer (return/break/next/recase) that
# abandons enclosing begin regions. Spec 4.6.5: every exit path runs the
# ensure bodies of the regions it leaves, innermost first, AFTER the
# transfer's value has been computed. Each region's exception frame is
# popped BEFORE its ensure body is lowered so an error raised inside an
# ensure propagates to handlers OUTSIDE its begin (never its own rescue).
# Unwinds down to ensure-stack size `ensure_base` and frame depth `eh_base`;
# compile-time bookkeeping is restored before returning because this
# sequence is emitted on one branch while lowering continues lexically.
# An ensure body may itself terminate the block (unconditional raise or
# return — those override the in-flight transfer, matching the
# interpreter's pending-error shape); emission stops there and the caller
# must check block_terminated before emitting the transfer itself.
-> emit_transfer_unwind(ctx, wfn, ensure_base, eh_base)
  stack = wfn[:ensure_stack]
  saved_depth = wfn[:eh_depth]
  saved = []
  while stack.size() > ensure_base && !block_terminated(wfn)
    entry = stack.pop()
    saved.push(entry)
    emit_eh_pops(wfn, wfn[:eh_depth] - entry[:eh_base])
    wfn[:eh_depth] = entry[:eh_base]
    lower_program(ctx, entry[:body])
  if !block_terminated(wfn)
    emit_eh_pops(wfn, wfn[:eh_depth] - eh_base)
  i = saved.size() - 1
  while i >= 0
    stack.push(saved[i])
    i -= 1
  wfn[:eh_depth] = saved_depth
  nil

# want_value: begin/rescue in VALUE position (last expression of a method,
# case arm, or if arm, or an assignment rhs) produces the last expression of
# whichever arm ran — via a result slot rather than a phi, because the
# ensure/unwind machinery gives the merge block an open-ended predecessor
# set. Statement position (want_value false) keeps the historical
# discard-everything behavior. Before 2026-07-22 (round-3 bug 2) value
# position silently produced nil from BOTH arms.
-> lower_nonraising_begin(ctx, node, want_value)
  wfn = ctx[:func]
  ensure_entry = nil
  if node.ensure_body != nil
    ensure_entry = {body: node.ensure_body, eh_base: wfn[:eh_depth]}
    wfn[:ensure_stack].push(ensure_entry)

  result = typed_value(:i64, w_nil.to_s())
  if want_value
    result = lower_body_value(ctx, node.body)
  else
    lower_program(ctx, node.body)

  if ensure_entry != nil
    wfn[:ensure_stack].pop()
    if !block_terminated(wfn)
      lower_program(ctx, node.ensure_body)
      materialize_bindings(ctx)
  result

-> lower_begin(ctx, node, want_value = false)
  wfn = ctx[:func]

  # A closed-world no-raise proof makes the landing pad unreachable. Keep the
  # normal body and ensure semantics, but emit no heap/TLS frame, setjmp, or
  # rescue CFG at all. Unknown operations and integer division retain the
  # ordinary handler path.
  if body_cannot_raise?(ctx, node.body)
    return lower_nonraising_begin(ctx, node, want_value)

  result_ptr = nil
  if want_value
    result_var = "__begin_expr." + next_label(wfn, "be")
    result_ptr = ensure_var_slot(wfn, result_var)
    emit_wire_store_i64(wfn, result_ptr, w_nil.to_s())

  # Push exception frame: buf = w_exception_push()
  buf = next_temp(wfn)
  emit_wire_call_direct_ptr(wfn, [], "w_exception_push", buf)

  # setjmp(buf) → 0 = normal, non-zero = exception
  sj = next_temp(wfn)
  emit_wire_setjmp(wfn, buf, sj)

  # Branch: 0 → try, else → rescue
  cmp = next_temp(wfn)
  emit_wire_icmp_eq_i32(wfn, sj, "0", cmp)

  try_label = next_label(wfn, "try")
  rescue_label = next_label(wfn, "rescue")
  end_label = next_label(wfn, "begin.end")

  emit_wire_cond_br(wfn, cmp, rescue_label, nil, try_label)

  # Try block. The frame is live for exactly the try body's lowering:
  # return/break/next/recase lowered inside it consult eh_depth to pop it.
  # An `ensure` clause additionally guards both the try and rescue bodies:
  # its entry sits on ensure_stack while they lower, so any control
  # transfer out of them replays the ensure body at the transfer site
  # (emit_transfer_unwind). It is OFF the stack while the ensure body
  # itself lowers — an exit from inside ensure must not re-run it.
  start_block(wfn, try_label)
  try_recycle_depth = wfn[:scope_recycle_stack].size()
  try_sid = next_scope_id(wfn)
  emit_scope_push(wfn, try_sid)
  ensure_entry = nil
  if node.ensure_body != nil
    ensure_entry = {body: node.ensure_body, eh_base: wfn[:eh_depth]}
  wfn[:eh_depth] = wfn[:eh_depth] + 1
  if ensure_entry != nil
    wfn[:ensure_stack].push(ensure_entry)
  if result_ptr != nil && node.body != nil && node.body.size() > 0
    lower_if_expr_body(ctx, wfn, node.body, result_ptr)
  else
    lower_program(ctx, node.body)
  if ensure_entry != nil
    wfn[:ensure_stack].pop()
  wfn[:eh_depth] = wfn[:eh_depth] - 1
  if !block_terminated(wfn)
    materialize_bindings(ctx)
    emit_scope_pop(wfn, try_sid)
    emit_wire_call_direct_void(wfn, [], "w_exception_pop")
    if node.ensure_body != nil
      lower_program(ctx, node.ensure_body)
      materialize_bindings(ctx)
    if !block_terminated(wfn)
      emit_wire_br(wfn, end_label, nil, nil)
  else
    restore_recycle_scope_depth(wfn, try_recycle_depth)

  # Rescue block
  start_block(wfn, rescue_label)
  rescue_sid = next_scope_id(wfn)
  err = next_temp(wfn)
  emit_wire_call_direct_i64(wfn, nil, [], nil, nil, "w_exception_error", nil, nil, err)
  emit_wire_call_direct_void(wfn, [], "w_exception_pop")
  if node.rescue_var != nil
    ptr = ensure_var_slot(wfn, node.rescue_var)
    emit_wire_store_i64(wfn, ptr, err)
  rescue_recycle_depth = wfn[:scope_recycle_stack].size()
  emit_scope_push(wfn, rescue_sid)
  if node.rescue_body != nil
    # The ensure clause guards the rescue body too (its frame is already
    # consumed by this landing pad, so eh_base == the current depth).
    if ensure_entry != nil
      wfn[:ensure_stack].push(ensure_entry)
    if result_ptr != nil && node.rescue_body.size() > 0
      lower_if_expr_body(ctx, wfn, node.rescue_body, result_ptr)
    else
      lower_program(ctx, node.rescue_body)
    if ensure_entry != nil
      wfn[:ensure_stack].pop()
  if !block_terminated(wfn)
    materialize_bindings(ctx)
    emit_scope_pop(wfn, rescue_sid)
    if node.ensure_body != nil
      lower_program(ctx, node.ensure_body)
      materialize_bindings(ctx)
    if !block_terminated(wfn)
      if node.rescue_body == nil && node.rescue_var == nil
        # `begin/ensure` with no rescue clause: the landing pad exists only
        # to run the ensure body. Spec 4.6.5: an unrescued error propagates
        # AFTER ensure — re-raise it instead of falling through (which
        # silently swallowed the exception).
        emit_wire_call_direct_void(wfn, [err], "w_raise")
        emit_wire_unreachable(wfn)
      else
        emit_wire_br(wfn, end_label, nil, nil)
  else
    restore_recycle_scope_depth(wfn, rescue_recycle_depth)

  start_block(wfn, end_label)
  if result_ptr != nil
    result = next_temp(wfn)
    emit_wire_load_i64(wfn, result_ptr, result)
    return typed_value(:i64, result)
  nil

-> lower_rescue_expr(ctx, node)
  wfn = ctx[:func]

  # Push exception frame
  buf = next_temp(wfn)
  emit_wire_call_direct_ptr(wfn, [], "w_exception_push", buf)
  sj = next_temp(wfn)
  emit_wire_setjmp(wfn, buf, sj)
  cmp = next_temp(wfn)
  emit_wire_icmp_eq_i32(wfn, sj, "0", cmp)

  try_label = next_label(wfn, "rescexpr.try")
  rescue_label = next_label(wfn, "rescexpr.rescue")
  end_label = next_label(wfn, "rescexpr.end")

  emit_wire_cond_br(wfn, cmp, rescue_label, nil, try_label)

  # Try block: evaluate body (tracked in eh_depth like lower_begin's try, in
  # case the expression lowers an inline construct containing an early exit)
  start_block(wfn, try_label)
  wfn[:eh_depth] = wfn[:eh_depth] + 1
  try_tv = lower_expression(ctx, node.body)
  wfn[:eh_depth] = wfn[:eh_depth] - 1
  try_reg = ensure_i64_value(wfn, try_tv)
  # An assignment inside the guarded expression (`x = f() rescue nil`) binds
  # its var to an SSA reg defined in THIS arm; flush bindings to slots before
  # the join (as lower_begin does) or a post-join read of the var uses a reg
  # that doesn't dominate it — invalid IR. (try_reg itself is safe: its only
  # cross-block use is the phi below, which reads it on the edge.)
  materialize_bindings(ctx)
  emit_wire_call_direct_void(wfn, [], "w_exception_pop")
  try_from = wfn[:blocks][wfn[:blocks].size() - 1][:label]
  emit_wire_br(wfn, end_label, nil, nil)

  # Rescue block: evaluate fallback
  start_block(wfn, rescue_label)
  emit_wire_call_direct_void(wfn, [], "w_exception_pop")
  rescue_tv = lower_expression(ctx, node.fallback)
  rescue_reg = ensure_i64_value(wfn, rescue_tv)
  materialize_bindings(ctx)
  rescue_from = wfn[:blocks][wfn[:blocks].size() - 1][:label]
  emit_wire_br(wfn, end_label, nil, nil)

  # Merge
  start_block(wfn, end_label)
  result = next_temp(wfn)
  emit_wire_phi_i64(wfn, try_from, try_reg, rescue_from, rescue_reg, result)
  typed_value(:i64, result)

-> lower_raise(ctx, node)
  wfn = ctx[:func]
  val = lower_expression(ctx, node.value)
  val_reg = ensure_i64_value(wfn, val)
  # w_raise is declared noreturn so LLVM DCEs anything after the call,
  # breaking the side-table PC lookup. Stash the source location into a
  # thread-local via __w_loc_set_col right before the raise instead;
  # the error formatter reads it back as a fallback when the side-table
  # lookup misses.
  if node.line != nil && ctx[:source_path] != nil
    file_str = ctx[:source_path]
    file_str_id = module_string_constant(ctx[:mod], file_str)
    file_byte_len = utf8_byte_length(file_str) + 1
    col_val = node.col
    if col_val == nil
      col_val = 0
    tp = next_temp(wfn)
    emit_wire_call_loc_set_col(wfn, col_val, file_byte_len, file_str_id, node.line, tp)
  emit_wire_call_direct_void(wfn, [val_reg], "w_raise")
  emit_wire_unreachable(wfn)
  nil
