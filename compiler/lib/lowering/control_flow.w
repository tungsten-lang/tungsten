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
    then_sid = next_scope_id(wfn)
    emit_scope_push(wfn, then_sid)
    lower_program(ctx, node.then_body)
    if !block_terminated(wfn)
      materialize_bindings(ctx)
      emit_scope_pop(wfn, then_sid)
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
      else_sid = next_scope_id(wfn)
      emit_scope_push(wfn, else_sid)
      lower_program(ctx, node.else_body)
      if !block_terminated(wfn)
        materialize_bindings(ctx)
        emit_scope_pop(wfn, else_sid)
    return nil

  cond = lower_expression(ctx, node.condition)

  # If condition is already i1 (from inline comparison), use directly
  if cond[:type] == :i1
    cond_bool = cond[:value]
  else
    cond_reg = ensure_i64_value(wfn, cond)
    cond_bool = next_temp(wfn)
    emit_instruction(wfn, {op: :truthy_inline, temp: cond_bool, value: cond_reg})

  then_label = next_label(wfn, "if.then")
  else_label = next_label(wfn, "if.else")
  end_label = next_label(wfn, "if.end")

  has_else = node.else_body != nil && node.else_body.size() > 0
  has_elsif = node.elsif_clauses != nil && node.elsif_clauses.size() > 0

  if has_else || has_elsif
    emit_instruction(wfn, {op: :cond_br, cond: cond_bool, then_label: then_label, else_label: else_label})
  else
    emit_instruction(wfn, {op: :cond_br, cond: cond_bool, then_label: then_label, else_label: end_label})

  # Then branch.
  #
  # If the branch terminates early (via return / raise / unreachable
  # signal), the bindings established inside the branch must NOT leak
  # into the merge block. Clear ctx[:bindings] on termination. If the
  # branch doesn't terminate, materialize_bindings already resets
  # ctx[:bindings] to {} internally (wire.w:1799), so either path
  # leaves ctx[:bindings] clean for the next branch / merge.
  start_block(wfn, then_label)
  then_sid = next_scope_id(wfn)
  emit_scope_push(wfn, then_sid)
  lower_program(ctx, node.then_body)
  if !block_terminated(wfn)
    materialize_bindings(ctx)
    emit_scope_pop(wfn, then_sid)
    emit_instruction(wfn, {op: :br, label: end_label})
  else
    ctx[:bindings] = {}

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
        emit_instruction(wfn, {op: :truthy_inline, temp: et, value: ec_reg})
        eb = et

      ethen_label = next_label(wfn, "elsif.then")
      if i + 1 < node.elsif_clauses.size()
        next_else = next_label(wfn, "elsif.else")
      elsif has_else
        next_else = next_label(wfn, "else")
      else
        next_else = end_label

      emit_instruction(wfn, {op: :cond_br, cond: eb, then_label: ethen_label, else_label: next_else})

      start_block(wfn, ethen_label)
      elsif_sid = next_scope_id(wfn)
      emit_scope_push(wfn, elsif_sid)
      lower_program(ctx, clause[1])
      if !block_terminated(wfn)
        materialize_bindings(ctx)
        emit_scope_pop(wfn, elsif_sid)
        emit_instruction(wfn, {op: :br, label: end_label})
      else
        ctx[:bindings] = {}

      current_else = next_else
      i += 1

    # Else branch after elsifs
    if has_else
      start_block(wfn, current_else)
      else_sid = next_scope_id(wfn)
      emit_scope_push(wfn, else_sid)
      lower_program(ctx, node.else_body)
      if !block_terminated(wfn)
        materialize_bindings(ctx)
        emit_scope_pop(wfn, else_sid)
        emit_instruction(wfn, {op: :br, label: end_label})
      else
        ctx[:bindings] = {}
  elsif has_else
    # Simple if/else
    start_block(wfn, else_label)
    else_sid = next_scope_id(wfn)
    emit_scope_push(wfn, else_sid)
    lower_program(ctx, node.else_body)
    if !block_terminated(wfn)
      materialize_bindings(ctx)
      emit_scope_pop(wfn, else_sid)
      emit_instruction(wfn, {op: :br, label: end_label})
    else
      ctx[:bindings] = {}

  start_block(wfn, end_label)
  nil

-> lower_if_expr(ctx, node)
  wfn = ctx[:func]

  # Allocate a result slot
  result_var = "__if_expr." + next_label(wfn, "ie")
  result_ptr = ensure_var_slot(wfn, result_var)
  # Initialize to nil
  emit_instruction(wfn, {op: :store_i64, value: w_nil.to_s(), ptr: result_ptr})

  cond = lower_expression(ctx, node.condition)
  if cond[:type] == :i1
    cond_bool = cond[:value]
  else
    cond_reg = ensure_i64_value(wfn, cond)
    cond_bool = next_temp(wfn)
    emit_instruction(wfn, {op: :truthy_inline, temp: cond_bool, value: cond_reg})

  then_label = next_label(wfn, "ie.then")
  else_label = next_label(wfn, "ie.else")
  end_label = next_label(wfn, "ie.end")

  has_else = node.else_body != nil && node.else_body.size() > 0
  has_elsif = node.elsif_clauses != nil && node.elsif_clauses.size() > 0
  end_reachable = false

  if has_else || has_elsif
    emit_instruction(wfn, {op: :cond_br, cond: cond_bool, then_label: then_label, else_label: else_label})
  else
    emit_instruction(wfn, {op: :cond_br, cond: cond_bool, then_label: then_label, else_label: end_label})
    end_reachable = true

  # Then branch — lower body, store last expression as result
  start_block(wfn, then_label)
  then_body = node.then_body
  if then_body != nil && then_body.size() > 0
    lower_if_expr_body(ctx, wfn, then_body, result_ptr)
  materialize_bindings(ctx)
  if !block_terminated(wfn)
    emit_instruction(wfn, {op: :br, label: end_label})
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
        emit_instruction(wfn, {op: :truthy_inline, temp: et, value: ec_reg})
        eb = et

      ethen_label = next_label(wfn, "ie.ethen")
      if i + 1 < node.elsif_clauses.size()
        next_else = next_label(wfn, "ie.eelse")
      elsif has_else
        next_else = next_label(wfn, "ie.else")
      else
        next_else = end_label

      emit_instruction(wfn, {op: :cond_br, cond: eb, then_label: ethen_label, else_label: next_else})
      if next_else == end_label
        end_reachable = true

      start_block(wfn, ethen_label)
      clause_body = clause[1]
      if clause_body != nil && clause_body.size() > 0
        lower_if_expr_body(ctx, wfn, clause_body, result_ptr)
      materialize_bindings(ctx)
      if !block_terminated(wfn)
        emit_instruction(wfn, {op: :br, label: end_label})
        end_reachable = true

      current_else = next_else
      i += 1

    # Else branch after elsifs
    if has_else
      start_block(wfn, current_else)
      else_body = node.else_body
      if else_body != nil && else_body.size() > 0
        lower_if_expr_body(ctx, wfn, else_body, result_ptr)
      materialize_bindings(ctx)
      if !block_terminated(wfn)
        emit_instruction(wfn, {op: :br, label: end_label})
        end_reachable = true
  elsif has_else
    # Simple if/else
    start_block(wfn, else_label)
    else_body = node.else_body
    if else_body != nil && else_body.size() > 0
      lower_if_expr_body(ctx, wfn, else_body, result_ptr)
    materialize_bindings(ctx)
    if !block_terminated(wfn)
      emit_instruction(wfn, {op: :br, label: end_label})
      end_reachable = true

  if !end_reachable
    return typed_value(:i64, w_nil.to_s())

  start_block(wfn, end_label)
  result = next_temp(wfn)
  emit_instruction(wfn, {op: :load_i64, temp: result, ptr: result_ptr})
  typed_value(:i64, result)

-> lower_if_expr_body(ctx, wfn, body, result_ptr)
  # Lower all but last as statements
  i = 0
  while i < body.size() - 1
    lower_statement(ctx, body[i])
    i += 1
  last = body[body.size() - 1]
  last_t = ast_kind(last)
  # If last is a statement (return, puts, while, etc.), lower as statement — no result to store
  if last_t in (:return :puts :print :raise :while :method_def :fn_def :class_def :begin)
    lower_statement(ctx, last)
  else
    last_tv = lower_expression(ctx, last)
    if !block_terminated(wfn)
      last_reg = ensure_i64_value(wfn, last_tv)
      emit_instruction(wfn, {op: :store_i64, value: last_reg, ptr: result_ptr})

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
# Phase 2 Codex plan review (2026-04-14).
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
      emit_instruction(wfn, {op: :load_i64, temp: cur, ptr: boxed_slot})
      raw = nanunbox_int_emit(wfn, cur)
      emit_instruction(wfn, {op: :store_i64, value: raw, ptr: raw_slot})
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
    emit_instruction(wfn, {op: :br, label: body_label})
    cont_label = body_label
  else
    emit_instruction(wfn, {op: :br, label: cond_label})
    start_block(wfn, cond_label)
    cond = lower_expression(ctx, node.condition)
    if cond[:type] == :i1
      cond_bool = cond[:value]
    else
      cond_reg = ensure_i64_value(wfn, cond)
      cond_bool = next_temp(wfn)
      emit_instruction(wfn, {op: :truthy_inline, temp: cond_bool, value: cond_reg})
    emit_instruction(wfn, {op: :cond_br, cond: cond_bool, then_label: body_label, else_label: end_label})
    cont_label = cond_label

  # Body
  start_block(wfn, body_label)
  while_sid = next_scope_id(wfn)
  emit_scope_push(wfn, while_sid)
  push_loop(wfn, end_label, cont_label, body_label)
  lower_program(ctx, node.body)
  pop_loop(wfn)
  if !block_terminated(wfn)
    emit_scope_pop(wfn, while_sid)
    emit_instruction(wfn, {op: :br, label: cont_label})

  start_block(wfn, end_label)

  # Rebox unboxed vars back to WValue slots. Phase 2 (2026-04-15):
  # use w_int (runtime bigint-safe boxing) instead of inline
  # nanbox_int, because under silent-wrap native arithmetic the
  # accumulated value can exceed the 48-bit nanbox payload range.
  # Inline nanbox would mask to 48 bits and truncate. w_int handles
  # any i64 correctly, promoting to bigint when needed.
  unames = unboxed.keys().sort()
  ui = 0
  while ui < unames.size()
    vname = unames[ui]
    vtype = ctx[:var_types][vname]
    already_raw = is_machine_int_type(vtype) || vtype == :raw_int || vtype == :raw_i64
    if already_raw != true
      raw_slot = unboxed[vname]
      raw = next_temp(wfn)
      emit_instruction(wfn, {op: :load_i64, temp: raw, ptr: raw_slot})
      boxed_temp = next_temp(wfn)
      emit_instruction(wfn, {op: :call_direct_i64, temp: boxed_temp, name: "w_int", args: [raw]})
      boxed_slot = wfn[:var_slots][vname]
      emit_instruction(wfn, {op: :store_i64, value: boxed_temp, ptr: boxed_slot})
    ui += 1

  # Clear any stale bindings for vars that were modified inside the loop
  # (they point to registers from inside the loop's blocks)
  ctx[:bindings] = {}

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
    start_tv = lower_expression(ctx, collection.from)
    start_reg = ensure_i64_value(wfn, start_tv)
    start_raw = next_temp(wfn)
    emit_instruction(wfn, {op: :nanunbox_int, temp: start_raw, temp_shl: start_raw + ".shl", boxed: start_reg})

    unbounded = collection.to == nil
    end_raw = nil
    if !unbounded
      end_tv = lower_expression(ctx, collection.to)
      end_reg = ensure_i64_value(wfn, end_tv)
      end_raw = next_temp(wfn)
      emit_instruction(wfn, {op: :nanunbox_int, temp: end_raw, temp_shl: end_raw + ".shl", boxed: end_reg})

    cmp_op = "sle"
    if collection.exclusive == true
      cmp_op = "slt"

    pre_label = next_label(wfn, "with.pre")
    header_label = next_label(wfn, "with.hdr")
    body_label = next_label(wfn, "with.body")
    inc_label = next_label(wfn, "with.inc")
    exit_label = next_label(wfn, "with.exit")

    from_type = infer_type(collection.from, ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)
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

    emit_instruction(wfn, {op: :br, label: info[:pre_label]})
    start_block(wfn, info[:pre_label])
    emit_instruction(wfn, {op: :br, label: info[:header_label]})

    start_block(wfn, info[:header_label])
    phi_reg = next_temp(wfn)
    inc_next = next_temp(wfn)
    emit_instruction(wfn, {op: :phi_i64, temp: phi_reg, a_value: info[:start_raw], a_label: info[:pre_label], b_value: inc_next, b_label: info[:inc_label]})

    # Bound check — skipped for right-unbounded ranges (loop exits only via break).
    if info[:unbounded] == true
      emit_instruction(wfn, {op: :br, label: info[:body_label]})
    else
      cmp_reg = next_temp(wfn)
      emit_instruction(wfn, {op: :icmp_i64, temp: cmp_reg, pred: info[:cmp_op], lhs: phi_reg, rhs: info[:end_raw]})
      emit_instruction(wfn, {op: :cond_br, cond: cmp_reg, then_label: info[:body_label], else_label: info[:exit_label]})

    # Body entry: store counter to var slot, clear stale binding
    start_block(wfn, info[:body_label])
    slot = wfn[:var_slots][info[:name]]
    if is_machine_int_type(info[:from_type])
      emit_instruction(wfn, {op: machine_store_op(info[:from_type]), value: phi_reg, ptr: slot})
    else
      boxed_tv = nanbox_int_emit(wfn, phi_reg)
      emit_instruction(wfn, {op: :store_i64, value: boxed_tv[:value], ptr: slot})
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
  with_sid = next_scope_id(wfn)
  emit_scope_push(wfn, with_sid)
  push_loop(wfn, outermost_exit, innermost_inc, nil)

  # Emit the body
  lower_program(ctx, node.body)
  pop_loop(wfn)
  if !block_terminated(wfn)
    emit_scope_pop(wfn, with_sid)

  # Emit inc and exit blocks (inner to outer)
  i = binding_info.size() - 1
  while i >= 0
    info = binding_info[i]
    if !block_terminated(wfn)
      emit_instruction(wfn, {op: :br, label: info[:inc_label]})
    start_block(wfn, info[:inc_label])
    emit_instruction(wfn, {op: :add_i64, temp: info[:inc_next], lhs: info[:phi_reg], rhs: "1"})
    emit_instruction(wfn, {op: :br, label: info[:header_label]})
    start_block(wfn, info[:exit_label])
    i -= 1
  nil

-> lower_break(ctx)
  wfn = ctx[:func]
  loop_info = current_loop(wfn)
  if loop_info != nil
    emit_instruction(wfn, {op: :br, label: loop_info[:break_label]})
  nil

-> lower_next(ctx)
  wfn = ctx[:func]
  # Inside a .each / iterator block, `next` returns from the block (not the
  # enclosing loop, which doesn't exist as a wire-level loop). The iterator
  # will continue to the next element. Matches Ruby semantics.
  if ctx[:is_block] == true
    emit_instruction(wfn, {op: :ret_i64, value: w_nil.to_s()})
    return nil
  loop_info = current_loop(wfn)
  if loop_info != nil
    emit_instruction(wfn, {op: :br, label: loop_info[:next_label]})
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
    emit_instruction(wfn, {op: :store_i64, value: new_reg, ptr: info[:subj_ptr]})
  elsif info[:subject_node] != nil
    # Bare recase on a value-case: re-evaluate the original subject expression.
    new_tv = lower_expression(ctx, info[:subject_node])
    new_reg = ensure_i64_value(wfn, new_tv)
    materialize_bindings(ctx)
    emit_instruction(wfn, {op: :store_i64, value: new_reg, ptr: info[:subj_ptr]})
  else
    # Bare recase on a subject-less cond-case: just re-test the conditions.
    materialize_bindings(ctx)
  emit_instruction(wfn, {op: :br, label: info[:redispatch_label]})
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
    emit_instruction(wfn, {op: :call_direct_void, name: "w_block_return_signal", args: [frame_reg, val_reg]})
    emit_instruction(wfn, {op: :unreachable})
    return nil

  if wfn[:exit_label] != nil && wfn[:result_slot] != nil
    if node.value != nil
      val = lower_expression(ctx, node.value)
      val_reg = ensure_i64_value(wfn, val)
    else
      val_reg = w_nil.to_s()
    emit_instruction(wfn, {op: :store_i64, value: val_reg, ptr: wfn[:result_slot]})
    emit_instruction(wfn, {op: :br, label: wfn[:exit_label]})
    return nil

  if node.value != nil
    val = lower_expression(ctx, node.value)
    val_reg = ensure_return_value(ctx, val, node.value)
  else
    val_reg = default_return_value(wfn)

  if wfn[:return_type] == "i64"
    emit_instruction(wfn, {op: :ret_i64, value: val_reg})
  elsif wfn[:return_type] == "i32"
    # Truncate for main
    temp = next_temp(wfn)
    emit_instruction(wfn, {op: :trunc_i64_i32, temp: temp, value: val_reg})
    emit_instruction(wfn, {op: :ret_i32, value: temp})
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
    emit_instruction(wfn, {op: :store_i64, value: raw_reg, ptr: subj_ptr})
    ctx[:var_types][subj_var] = subj_type
  else
    subj_reg = ensure_i64_value(wfn, subj_tv)
    emit_instruction(wfn, {op: :store_i64, value: subj_reg, ptr: subj_ptr})
    if !has_recase && subj_type != nil
      ctx[:var_types][subj_var] = subj_type

  # recase: open the re-dispatch header (a synthetic loop). `recase` rewrites
  # subj_var and branches back here; the if/elsif chain below re-reads subj_var.
  if has_recase
    redispatch_header = next_label(wfn, "recase.head")
    materialize_bindings(ctx)
    emit_instruction(wfn, {op: :br, label: redispatch_header})
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
  emit_instruction(wfn, {op: :store_i64, value: w_nil.to_s(), ptr: result_ptr})

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
    emit_instruction(wfn, {op: :call_direct_i64, temp: subj_raw, name: "w_switch_canonical", args: [subj_boxed]})
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
  emit_instruction(wfn, {op: :switch_i64, value: subj_raw, default_label: default_label, cases: cases, is_symbol: symbol_switch})

  i = 0
  while i < cases.size()
    c = cases[i]
    start_block(wfn, c[:label])
    body = c[:arm].body
    if body != nil && body.size() > 0
      lower_if_expr_body(ctx, wfn, body, result_ptr)
    materialize_bindings(ctx)
    if !block_terminated(wfn)
      emit_instruction(wfn, {op: :br, label: end_label})
    i += 1

  start_block(wfn, default_label)
  if node.else_body != nil && node.else_body.size() > 0
    lower_if_expr_body(ctx, wfn, node.else_body, result_ptr)
  materialize_bindings(ctx)
  if !block_terminated(wfn)
    emit_instruction(wfn, {op: :br, label: end_label})

  start_block(wfn, end_label)
  result = next_temp(wfn)
  emit_instruction(wfn, {op: :load_i64, temp: result, ptr: result_ptr})
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
    emit_instruction(wfn, {op: :br, label: redispatch_header})
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
  is_if_stmt = last_t == :if && (last.else_body == nil || last.else_body.size() == 0) && (last.elsif_clauses == nil || last.elsif_clauses.size() == 0)
  if last_t in (:return :puts :print :raise :while :method_def :fn_def :class_def :begin) || is_if_stmt
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

-> lower_begin(ctx, node)
  wfn = ctx[:func]

  # Push exception frame: buf = w_exception_push()
  buf = next_temp(wfn)
  emit_instruction(wfn, {op: :call_direct_ptr, temp: buf, name: "w_exception_push", args: []})

  # setjmp(buf) → 0 = normal, non-zero = exception
  sj = next_temp(wfn)
  emit_instruction(wfn, {op: :setjmp, temp: sj, buf: buf})

  # Branch: 0 → try, else → rescue
  cmp = next_temp(wfn)
  emit_instruction(wfn, {op: :icmp_eq_i32, temp: cmp, lhs: sj, rhs: "0"})

  try_label = next_label(wfn, "try")
  rescue_label = next_label(wfn, "rescue")
  end_label = next_label(wfn, "begin.end")

  emit_instruction(wfn, {op: :cond_br, cond: cmp, then_label: try_label, else_label: rescue_label})

  # Try block
  start_block(wfn, try_label)
  try_sid = next_scope_id(wfn)
  emit_scope_push(wfn, try_sid)
  lower_program(ctx, node.body)
  if !block_terminated(wfn)
    materialize_bindings(ctx)
    emit_scope_pop(wfn, try_sid)
    emit_instruction(wfn, {op: :call_direct_void, name: "w_exception_pop", args: []})
    if node.ensure_body != nil
      lower_program(ctx, node.ensure_body)
      materialize_bindings(ctx)
    if !block_terminated(wfn)
      emit_instruction(wfn, {op: :br, label: end_label})

  # Rescue block
  start_block(wfn, rescue_label)
  rescue_sid = next_scope_id(wfn)
  err = next_temp(wfn)
  emit_instruction(wfn, {op: :call_direct_i64, temp: err, name: "w_exception_error", args: []})
  emit_instruction(wfn, {op: :call_direct_void, name: "w_exception_pop", args: []})
  if node.rescue_var != nil
    ptr = ensure_var_slot(wfn, node.rescue_var)
    emit_instruction(wfn, {op: :store_i64, value: err, ptr: ptr})
  emit_scope_push(wfn, rescue_sid)
  if node.rescue_body != nil
    lower_program(ctx, node.rescue_body)
  if !block_terminated(wfn)
    materialize_bindings(ctx)
    emit_scope_pop(wfn, rescue_sid)
    if node.ensure_body != nil
      lower_program(ctx, node.ensure_body)
      materialize_bindings(ctx)
    if !block_terminated(wfn)
      emit_instruction(wfn, {op: :br, label: end_label})

  start_block(wfn, end_label)
  nil

-> lower_rescue_expr(ctx, node)
  wfn = ctx[:func]

  # Push exception frame
  buf = next_temp(wfn)
  emit_instruction(wfn, {op: :call_direct_ptr, temp: buf, name: "w_exception_push", args: []})
  sj = next_temp(wfn)
  emit_instruction(wfn, {op: :setjmp, temp: sj, buf: buf})
  cmp = next_temp(wfn)
  emit_instruction(wfn, {op: :icmp_eq_i32, temp: cmp, lhs: sj, rhs: "0"})

  try_label = next_label(wfn, "rescexpr.try")
  rescue_label = next_label(wfn, "rescexpr.rescue")
  end_label = next_label(wfn, "rescexpr.end")

  emit_instruction(wfn, {op: :cond_br, cond: cmp, then_label: try_label, else_label: rescue_label})

  # Try block: evaluate body
  start_block(wfn, try_label)
  try_tv = lower_expression(ctx, node.body)
  try_reg = ensure_i64_value(wfn, try_tv)
  emit_instruction(wfn, {op: :call_direct_void, name: "w_exception_pop", args: []})
  try_from = wfn[:blocks][wfn[:blocks].size() - 1][:label]
  emit_instruction(wfn, {op: :br, label: end_label})

  # Rescue block: evaluate fallback
  start_block(wfn, rescue_label)
  emit_instruction(wfn, {op: :call_direct_void, name: "w_exception_pop", args: []})
  rescue_tv = lower_expression(ctx, node.fallback)
  rescue_reg = ensure_i64_value(wfn, rescue_tv)
  rescue_from = wfn[:blocks][wfn[:blocks].size() - 1][:label]
  emit_instruction(wfn, {op: :br, label: end_label})

  # Merge
  start_block(wfn, end_label)
  result = next_temp(wfn)
  emit_instruction(wfn, {op: :phi_i64, temp: result, a_value: try_reg, a_label: try_from, b_value: rescue_reg, b_label: rescue_from})
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
    emit_instruction(wfn, {
      op: :call_loc_set_col,
      temp_ptr: tp,
      file_str_id: file_str_id,
      file_byte_len: file_byte_len,
      line: node.line,
      col: col_val
    })
  emit_instruction(wfn, {op: :call_direct_void, name: "w_raise", args: [val_reg]})
  emit_instruction(wfn, {op: :unreachable})
  nil
