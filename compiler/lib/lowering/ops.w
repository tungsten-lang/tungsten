# Lowering / ops — operator lowering: binary, unary, short-circuit
# logic, compound assignment, and the machine-int / float typed-op
# infrastructure.
#
# Depends on pass_registry.w, types.w, literals.w. This file
# deliberately has no `use` directives — see pass_registry.w.


# -- Machine-int + float typed ops --

-> infer_lchs_return_type(args)
  bits = 64
  known = true
  if args != nil && args.size() > 0
    last = args[args.size() - 1]
    if ast_kind(last) == :hash_literal
      entries = last.entries
      i = 0
      while i < entries.size()
        key = entries[i][0]
        value = entries[i][1]
        if ast_kind(key) == :symbol && key.value == "bits"
          if ast_kind(value) == :int
            bits = value.value
          else
            known = false
        i += 1
  if !known
    return nil
  if bits == 16
    return :typed_array_u16
  if bits == 32
    return :typed_array_u32
  :typed_array_i64

-> machine_int_result_type(lt, rt)
  if is_u128_type(lt) || is_u128_type(rt)
    return :u128
  if is_i128_type(lt) || is_i128_type(rt)
    return :i128
  if is_u64_type(lt) || is_u64_type(rt)
    return :u64
  if is_i64_type(lt) || is_i64_type(rt)
    return :i64
  # :char + int / int + :char → :char (character offset stays a char).
  # :char + :char → :char too (machine-level same as u8 + u8, but kept
  # as :char so downstream typing preserves the character context).
  if is_char_type(lt) || is_char_type(rt)
    return :char
  # Small int types (u8, u16, etc.) promote to i64
  if is_small_int_type(lt) || is_small_int_type(rt)
    return :i64
  nil

-> machine_slot_type(t)
  if is_machine_int128_type(t)
    return "i128"
  "i64"

-> machine_load_op(t)
  if is_machine_int128_type(t)
    return :load_i128
  :load_i64

-> machine_store_op(t)
  if is_machine_int128_type(t)
    return :store_i128
  :store_i64

-> machine_cmp_op(t)
  if is_machine_int128_type(t)
    return :icmp_i128
  :icmp_i64

-> machine_box_fn(t)
  case t
  when :u64
    "w_u64"
  when :raw_u64
    "w_u64"
  when :i128
    "w_i128"
  when :raw_i128
    "w_i128"
  when :u128
    "w_u128"
  when :raw_u128
    "w_u128"
  else
    "__w_int_fast"

-> machine_unbox_fn(t)
  case t
  when :u64
    "w_to_u64"
  when :raw_u64
    "w_to_u64"
  when :i128
    "w_to_i128"
  when :raw_i128
    "w_to_i128"
  when :u128
    "w_to_u128"
  when :raw_u128
    "w_to_u128"
  else
    "__w_to_i64_fast"

-> machine_call_return_op(t)
  if is_machine_int128_type(t)
    return :call_direct_i128
  :call_direct_i64

-> machine_int_to_i128_ext_op(from_type)
  if is_u64_type(from_type)
    return :zext_i64_i128
  :sext_i64_i128

-> machine_int_op(type, op)
  wide = is_machine_int128_type(type)
  unsigned = type in (:u64 :u128)
  case op
  when :PLUS
    if wide
      :add_i128
    else
      :add_i64
  when :MINUS
    if wide
      :sub_i128
    else
      :sub_i64
  when :STAR
    if wide
      :mul_i128
    else
      :mul_i64
  when :SLASH
    if wide
      if unsigned
        :udiv_i128
      else
        :sdiv_i128
    elsif unsigned
      :udiv_i64
    else
      :sdiv_i64
  when :PERCENT
    if wide
      if unsigned
        :urem_i128
      else
        :srem_i128
    elsif unsigned
      :urem_i64
    else
      :srem_i64
  when :AMPERSAND
    if wide
      :and_i128
    else
      :and_i64
  when :PIPE
    if wide
      :or_i128
    else
      :or_i64
  when :CARET
    if wide
      :xor_i128
    else
      :xor_i64
  when :LSHIFT
    if wide
      :shl_i128
    else
      :shl_i64
  when :RSHIFT
    if wide
      if type == :u128
        :lshr_i128
      else
        :ashr_i128
    elsif type == :u64
      :lshr_i64
    else
      :ashr_i64
  else
    nil

-> machine_cmp_pred(type, op)
  unsigned = type in (:u64 :u128)
  case op
  when :EQ
    "eq"
  when :NEQ
    "ne"
  when :LT
    if unsigned
      "ult"
    else
      "slt"
  when :GT
    if unsigned
      "ugt"
    else
      "sgt"
  when :LTE
    if unsigned
      "ule"
    else
      "sle"
  when :GTE
    if unsigned
      "uge"
    else
      "sge"
  else
    nil

-> machine_int_to_f64_op(type)
  case type
  when :u128
    :uitofp_i128_f64
  when :i128
    :sitofp_i128_f64
  when :u64
    :uitofp_i64_f64
  else
    :sitofp_i64_f64

-> f64_to_machine_int_op(type)
  case type
  when :u128
    :fptoui_f64_i128
  when :i128
    :fptosi_f64_i128
  when :u64
    :fptoui_f64_i64
  else
    :fptosi_f64_i64

-> raw_machine_source_type(tv, inferred_type = nil)
  case tv[:type]
  when :raw_int
    return :int
  when :raw_i64
    return :i64
  when :raw_u64
    return :u64
  when :raw_i128
    return :i128
  when :raw_u128
    return :u128
  when :char
    return :i64
  if inferred_type != nil && is_raw_int_storage_type(inferred_type)
    return inferred_type
  if inferred_type == :int
    return :int
  nil

-> overflow_mode_guards_machine_int_arith?(mode, op)
  if mode != :promote && mode != :trap
    return false
  op == :PLUS || op == :MINUS || op == :STAR

-> is_raw_float_value_type(t)
  t in (:raw_f32 :raw_f64)

-> is_machine_float_type(t)
  t in (:float :f32 :f64 :raw_f32 :raw_f64)

-> raw_float_value_type(t)
  if t in (:f32 :raw_f32)
    return :raw_f32
  :raw_f64

-> float_slot_type(t)
  if t in (:f32 :raw_f32)
    return "float"
  "double"

-> float_load_op(t)
  if t in (:f32 :raw_f32)
    return :load_float
  :load_double

-> float_store_op(t)
  if t in (:f32 :raw_f32)
    return :store_float
  :store_double

-> cast_raw_machine_int(wfn, value, from_type, to_type)
  if from_type == to_type
    return value
  if is_machine_int128_type(to_type)
    if is_machine_int128_type(from_type)
      return value
    temp = next_temp(wfn)
    emit_instruction(wfn, {op: machine_int_to_i128_ext_op(from_type), temp: temp, value: value})
    return temp
  if is_machine_int128_type(from_type)
    temp = next_temp(wfn)
    emit_instruction(wfn, {op: :trunc_i128_i64, temp: temp, value: value})
    return temp
  value

-> machine_int_literal_bits(val, type, raw = nil)
  if raw != nil
    clean = raw
    if raw.index("_") != nil
      clean = raw.replace("_", "")
    if !clean.starts_with?("0x") && !clean.starts_with?("0X") && !clean.starts_with?("0b") && !clean.starts_with?("0B") && !clean.starts_with?("0o") && !clean.starts_with?("0O")
      return clean
    # Hex/bin/oct literal of a u64 type. Its bit pattern can have the high bit
    # set (e.g. `0xe7037ed1a0b428db ## u64`), which is a NEGATIVE i64. Neither
    # decimal form is stage-consistent: the signed form (val.to_s()) differs
    # because stage 0 stores the literal in int64_t (negative) while the
    # compiled bignum runtime keeps it positive, and the unsigned form
    # (val + 2^64) overflows int64_t to a wrong value in stage 0. Emit the
    # low-64-bit pattern as a `u0x` immediate instead — wvalue_literal_text
    # extracts each nibble with `(u >> shift) & 15`, which reads the SAME bits
    # in both stages regardless of sign/bignum representation. The emitter
    # accepts u0x immediates as call args. (Reached once such a literal is
    # boxed, which escape analysis now triggers in hashing.w's wyhash.)
    if type == :u64
      return wvalue_literal_text(val)
  val.to_s()

-> wvalue_literal_text(value)
  u = value.to_i()
  if u < 0
    wrap = 1
    i = 0
    while i < 64
      wrap = wrap * 2
      i += 1
    u = u + wrap
  hex_chars = "0123456789ABCDEF"
  out = StringBuffer(19)
  out << "u0x"
  shift = 60
  while shift >= 0
    out << hex_chars.slice((u >> shift) & 15, 1)
    shift -= 4
  out.to_s()

-> lower_machine_int_expression(ctx, node, type)
  # An assignment hint belongs to the target, so a conditional RHS reaches
  # this helper without an inner TypeAscription node. Merge its arms in a raw
  # machine slot instead of first producing a boxed WValue and unboxing it.
  if ast_kind(node) == :if && node.else_body != nil && node.else_body.size() > 0
    materialize_bindings(ctx)
    return lower_if_expr(ctx, node, type)[:value]
  if ast_kind(node) == :int
    return machine_int_literal_bits(node.value, type, node.raw)
  # `:-X` char literals flow as raw integer immediates so ARM64 can
  # fold them into `cmp Wn, #imm` without going through nanbox/unbox.
  if ast_kind(node) == :char
    return node.value.to_s()
  # Carry-primitive intrinsic: `mulhi(a, b)` = high 64 bits of the unsigned
  # 64x64->128 product. Lowers to a single UMULH (arm64) / MULX (x86). It's a
  # builtin because the surface language can't express the high half of a wide
  # multiply — this is the keystone for fast multi-word bignum (SSA/Montgomery).
  if ast_kind(node) == :call && node.receiver == nil && node.name == "mulhi" && node.args != nil && node.args.size() == 2
    wfn = ctx[:func]
    a_raw = lower_machine_int_expression(ctx, node.args[0], type)
    b_raw = lower_machine_int_expression(ctx, node.args[1], type)
    t = next_temp(wfn)
    emit_instruction(wfn, {op: :mulhi_u64, temp: t, lhs: a_raw, rhs: b_raw})
    return t
  # Carry-primitives addcarry/subborrow (see calls.w) — carry/borrow out of a+b/a-b.
  if ast_kind(node) == :call && node.receiver == nil && node.name == "addcarry" && node.args != nil && node.args.size() == 2
    wfn = ctx[:func]
    a_raw = lower_machine_int_expression(ctx, node.args[0], type)
    b_raw = lower_machine_int_expression(ctx, node.args[1], type)
    t = next_temp(wfn)
    emit_instruction(wfn, {op: :addcarry_u64, temp: t, lhs: a_raw, rhs: b_raw})
    return t
  if ast_kind(node) == :call && node.receiver == nil && node.name == "subborrow" && node.args != nil && node.args.size() == 2
    wfn = ctx[:func]
    a_raw = lower_machine_int_expression(ctx, node.args[0], type)
    b_raw = lower_machine_int_expression(ctx, node.args[1], type)
    t = next_temp(wfn)
    emit_instruction(wfn, {op: :subborrow_u64, temp: t, lhs: a_raw, rhs: b_raw})
    return t
  # Fused subscript capture: `x = recv[i] ## i64/u64` on a receiver WITHOUT
  # static typed-array identity would lower to generic dispatch returning a
  # boxed value whose fresh bignum box (element > 2^48) leaked — one bignum
  # per read (2026-07-22). Emit the raw-returning runtime read instead:
  # typed integer arrays load raw inside the helper (no box at all); other
  # receivers take the identical dynamic dispatch + coercion. Receivers the
  # compiler already types as typed arrays keep the inline raw path below.
  # Restricted to plain :var receivers (locals/params — the leak class):
  # :gvar `$field` receivers are packed VIEW FIELDS whose subscript lowers
  # through the view-aware inline path, not a boxed WValue — feeding one to
  # the dispatch helper segfaults (caught by network_native_spec, whose
  # binary compiles core/ipv6.w's `$bytes[0] ## i64` sites).
  if ast_kind(node) == :call && node.name == "\[]" && node.args != nil && node.args.size() == 1 && node.receiver != nil && is_ast_node?(node.receiver) && ast_kind(node.receiver) == :var && type in (:i64 :u64)
    recv_t = infer_type(node.receiver, ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)
    # Small/big-array receivers have their own inline element ops
    # (small_array_get_inline / big_array_get_inline) — fall through to the
    # inline path below rather than the boxed w_index_raw_i64 CALL, so element
    # reads in a loop stay call-free and can vectorize. Only genuinely untyped /
    # poly (:array) receivers use the runtime raw-read helper.
    if !is_typed_array_type?(recv_t) && !is_small_array_type?(recv_t) && !is_big_array_type?(recv_t)
      wfn = ctx[:func]
      recv_tv = lower_expression(ctx, node.receiver)
      recv_reg = ensure_i64_value(wfn, recv_tv)
      idx_tv = lower_expression(ctx, node.args[0])
      idx_reg = ensure_i64_value(wfn, idx_tv)
      t = next_temp(wfn)
      fused_fn = "w_index_raw_i64"
      if type == :u64
        fused_fn = "w_index_raw_u64"
      emit_instruction(wfn, {op: :call_direct_i64, temp: t, name: fused_fn, args: [recv_reg, idx_reg]})
      return t
  tv = lower_expression(ctx, node)
  inferred = infer_type(node, ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)
  ensure_raw_machine_int(ctx[:func], tv, type, inferred)

-> is_safe_inline_int_op(op, left_node, right_node)
  # Only safe for +0 or *0/*1 — even +1/-1 can overflow at i48 boundary
  if left_node != nil && ast_kind(left_node) == :int && left_node.value == 0
    return true
  if right_node != nil && ast_kind(right_node) == :int && right_node.value == 0
    return true
  false

-> ast_equiv?(a, b)
  if a == nil && b == nil
    return true
  if a == nil || b == nil
    return false
  if !is_ast_node?(a) || !is_ast_node?(b)
    return a == b
  if ast_kind(a) != ast_kind(b)
    return false
  case ast_kind(a)
  when :var
    return a.name == b.name
  when :int
    return a.value == b.value
  when :ivar, :cvar, :gvar
    return a.name == b.name
  when :boolean, :string_literal, :float, :nil
    return a.value == b.value
  when :binary_op
    if a.op != b.op
      return false
    return ast_equiv?(a.left, b.left) && ast_equiv?(a.right, b.right)
  when :unary_op
    if a.op != b.op
      return false
    return ast_equiv?(a.operand, b.operand)
  else
    return false

-> init_int_op_map
  m = {}
  m[:PLUS] = :add_i64
  m[:MINUS] = :sub_i64
  m[:STAR] = :mul_i64
  m[:SLASH] = :sdiv_i64
  m[:PERCENT] = :srem_i64
  m[:AMPERSAND] = :and_i64
  m[:PIPE] = :or_i64
  m[:CARET] = :xor_i64
  m[:LSHIFT] = :shl_i64
  m[:RSHIFT] = :ashr_i64
  m

-> init_cmp_op_map
  m = {}
  m[:LT] = "slt"
  m[:GT] = "sgt"
  m[:LTE] = "sle"
  m[:GTE] = "sge"
  m[:EQ] = "eq"
  m[:NEQ] = "ne"
  m

-> init_float_op_map
  m = {}
  m[:PLUS] = :fadd_f64
  m[:MINUS] = :fsub_f64
  m[:STAR] = :fmul_f64
  m[:SLASH] = :fdiv_f64
  m[:PERCENT] = :frem_f64
  m

-> init_fcmp_op_map
  m = {}
  m[:LT] = "olt"
  m[:GT] = "ogt"
  m[:LTE] = "ole"
  m[:GTE] = "oge"
  m[:EQ] = "oeq"
  m[:NEQ] = "une"
  m

# -- Type inference --

-> build_infer_maps(int_op_map, cmp_op_map, float_op_map, fcmp_op_map)
  {
    int_op_map: int_op_map,
    cmp_op_map: cmp_op_map,
    float_op_map: float_op_map,
    fcmp_op_map: fcmp_op_map
  }

lowering_op_map = init_op_map()
lowering_int_op_map = init_int_op_map()
lowering_cmp_op_map = init_cmp_op_map()
lowering_float_op_map = init_float_op_map()
lowering_fcmp_op_map = init_fcmp_op_map()
lowering_infer_maps = build_infer_maps(lowering_int_op_map, lowering_cmp_op_map, lowering_float_op_map, lowering_fcmp_op_map)

# Compute the LLVM fast-math flag string for the current lowering context.
# Respects @fastmath / @strictmath block overrides (ctx[:math_mode_override])
# over the module-level math_mode. Returns "fast " or "".
# Note: precise mode returns "" here — FMA is emitted via the fmuladd peephole
# in lower_binary_op, not via a blanket flag on all operations.
-> float_inst_flags(ctx)
  mode = ctx[:math_mode_override]
  if mode == nil
    mode = ctx[:mod][:math_mode]
  if mode == :fast
    return "fast "
  ""


# -- Compound assign, binary/unary ops, short-circuit, in-test --

-> rebind_local_i64(ctx, name, value_reg, type_hint = nil)
  wfn = ctx[:func]
  ptr = wfn[:var_slots][name]
  if ptr != nil
    emit_instruction(wfn, {op: :store_i64, value: value_reg, ptr: ptr})
  else
    ctx[:bindings][name] = value_reg
  if type_hint != nil
    ctx[:var_types][name] = type_hint
  if wfn[:name] == "main"
    ctx[:mod][:top_level_vars][name] = true
    ctx[:mod][:top_level_var_types][name] = nil
    if ctx[:mod][:top_level_static_types] != nil
      ctx[:mod][:top_level_static_types][name] = type_hint
    emit_store_global_unless_const(wfn, ctx, name, value_reg)
  typed_value(:i64, value_reg)

-> bigint_linear_word_shape(node, op)
  if env("TUNGSTEN_BIGINT_ADDMUL_FUSION") == "0" || !(op in (:PLUS :MINUS))
    return nil
  if node == nil || !is_ast_node?(node) || ast_kind(node) != :binary_op || node.op != :STAR
    return nil
  {multiplicand: node.left, word: node.right}

-> emit_bigint_linear_word_mut(ctx, cur, shape, subtract)
  wfn = ctx[:func]
  x_tv = lower_expression(ctx, shape[:multiplicand])
  word_tv = lower_expression(ctx, shape[:word])
  x_reg = ensure_i64_value(wfn, x_tv)
  word_reg = ensure_i64_value(wfn, word_tv)
  result = next_temp(wfn)
  fn_name = subtract ? "w_bigint_submul_mut" : "w_bigint_addmul_mut"
  emit_instruction(wfn, {
    op: :call_direct_i64, temp: result, name: fn_name,
    args: [cur, x_reg, word_reg], call_conv: "preserve_mostcc"
  })
  result

-> lower_bigint_linear_word_mut(ctx, name, cur, ptr, shape, subtract)
  wfn = ctx[:func]
  result = emit_bigint_linear_word_mut(ctx, cur, shape, subtract)
  # Operand lowering may materialize bindings and make the original
  # binding-only write-back decision stale (same hazard as ordinary compound
  # assignment below).
  if ptr == nil && ctx[:bindings][name] == nil
    ptr = ensure_var_slot(wfn, name)
  if ptr != nil
    emit_instruction(wfn, {op: :store_i64, value: result, ptr: ptr})
  else
    ctx[:bindings][name] = result
  typed_value(:i64, result)

# Fuse the exact adjacent context
#
#   r += value
#   r %= 1 << literal_bits
#
# after the existing liveness analysis proved r's old binding consumable.
# There is no reordering across statements and the runtime entry retains a
# complete add-then-mod fallback for every guard-refused dynamic shape.
-> try_lower_bigint_modular_pair(ctx, add_node, mod_node)
  if env("TUNGSTEN_BIGINT_MOD_RING_FUSION") == "0"
    return false
  if add_node == nil || mod_node == nil || ast_kind(add_node) != :compound_assign || ast_kind(mod_node) != :compound_assign
    return false
  if add_node.op != :PLUS || mod_node.op != :PERCENT
    return false
  if add_node.target == nil || mod_node.target == nil || ast_kind(add_node.target) != :var || ast_kind(mod_node.target) != :var
    return false
  name = add_node.target.name
  if mod_node.target.name != name || ctx[:var_types][name] != :bigint
    return false
  if ctx[:mut_accumulators] == nil || ctx[:mut_accumulators][name] != true
    return false
  if ctx[:sum_chunk] != nil && name == ctx[:sum_chunk][:var]
    return false
  bits = bigint_pow2_modulus_bits(mod_node.value)
  if bits == nil
    return false

  wfn = ctx[:func]
  range_binding_invalidate(ctx, name)
  binding = ctx[:bindings][name]
  if binding != nil
    cur = binding
    ptr = nil
  else
    ptr = ensure_var_slot(wfn, name)
    cur = next_temp(wfn)
    emit_instruction(wfn, {op: :load_i64, temp: cur, ptr: ptr})

  rhs_tv = lower_expression(ctx, add_node.value)
  rhs_reg = ensure_i64_value(wfn, rhs_tv)
  if ptr == nil && ctx[:bindings][name] == nil
    ptr = ensure_var_slot(wfn, name)
  bits_reg = ensure_i64_value(wfn, typed_value(:raw_int, bits.to_s()))
  result = next_temp(wfn)
  emit_instruction(wfn, {
    op: :call_direct_i64, temp: result, name: "w_bigint_add_mod_pow2_mut",
    args: [cur, rhs_reg, bits_reg], call_conv: "preserve_mostcc"
  })
  if ptr != nil
    emit_instruction(wfn, {op: :store_i64, value: result, ptr: ptr})
  else
    ctx[:bindings][name] = result
  true

-> lower_compound_assign(ctx, node)
  # Desugar: x += val  →  x = x op val
  target = node.target
  wfn = ctx[:func]

  # Tag facts (Phase 2): compound writes void entry-condition facts the
  # same way lower_assign_expr's plain writes do.
  if ctx[:tag_facts] != nil && target != nil && is_ast_node?(target) && ast_kind(target) == :var
    ctx[:tag_facts][target.name] = nil

  # Method/index compound assignment must dispatch through the setter while
  # preserving the target's original arguments:
  #
  #   values[i] += rhs  →  values.[]=(i, values[i] + rhs)
  #
  # Treating a call target like a local variable creates a slot named `[]`
  # and reads it before initialization.  Keeping the getter in the synthetic
  # binary expression also lets typed-array lowering recognize its existing
  # single-load compound-op fast path, so receiver and index are evaluated
  # once for that path.
  if ast_kind(target) == :call && target.receiver != nil
    setter_args = []
    ai = 0
    while ai < target.args.size()
      setter_args.push(target.args[ai])
      ai += 1
    setter_args.push(Tungsten:AST:BinaryOp.new(target, node.op, node.value))
    setter_call = Tungsten:AST:Call.new(target.receiver, target.name + "=", setter_args, nil)
    setter_call.loc = ast_get(target, :loc)
    return lower_method_call(ctx, setter_call)

  if ast_kind(target) == :view_field_var
    result = lower_binary_op(ctx, Tungsten:AST:BinaryOp.new(target, node.op, node.value))
    return lower_view_field_var_set(ctx, target, result)

  name = target.name
  # A compound rebind invalidates range stashes exactly like a plain assign
  # (the var itself, and any recorded range whose bounds read it).
  range_binding_invalidate(ctx, name)

  # Sum-chunking: a qualifying accumulator's `r ±= e` feeds the raw
  # partial (see lower_while_sum_chunked).
  if ctx[:sum_chunk] != nil && name == ctx[:sum_chunk][:var] && node.op in (:PLUS :MINUS)
    return lower_sum_chunk_step(ctx, node.op, node.value)

  # Ivar compound assignment: @name += val → @name = @name op val
  if ast_kind(target) == :ivar
    cur_tv = lower_ivar(ctx, target)
    cur = ensure_i64_value(wfn, cur_tv)
    rhs = lower_expression(ctx, node.value)
    rhs_reg = ensure_i64_value(wfn, rhs)
    op = node.op
    rt_op = lowering_op_map[op]
    if rt_op != nil
      result = next_temp(wfn)
      emit_instruction(wfn, {op: :call_direct_i64, temp: result, name: rt_op, args: [cur, rhs_reg]})
      return lower_ivar_set_expr(ctx, target.name, typed_value(:i64, result))
    return typed_value(:i64, cur)

  # Class variable compound assignment: @@name += val
  if ast_kind(target) == :cvar
    cur_tv = lower_cvar(ctx, target)
    cur = ensure_i64_value(wfn, cur_tv)
    rhs = lower_expression(ctx, node.value)
    rhs_reg = ensure_i64_value(wfn, rhs)
    op = node.op
    rt_op = lowering_op_map[op]
    if rt_op != nil
      result = next_temp(wfn)
      emit_instruction(wfn, {op: :call_direct_i64, temp: result, name: rt_op, args: [cur, rhs_reg]})
      return lower_cvar_set(ctx, target, typed_value(:i64, result))
    return typed_value(:i64, cur)

  # Global variable compound assignment: $name += val → $name = $name op val.
  # Always the generic boxed path (lower_gvar/lower_gvar_set), regardless
  # of which function/method body this is in — see lower_gvar's doc
  # comment.
  if ast_kind(target) == :gvar
    cur_tv = lower_gvar(ctx, target)
    cur = ensure_i64_value(wfn, cur_tv)
    rhs = lower_expression(ctx, node.value)
    rhs_reg = ensure_i64_value(wfn, rhs)
    op = node.op
    rt_op = lowering_op_map[op]
    if rt_op != nil
      result = next_temp(wfn)
      emit_instruction(wfn, {op: :call_direct_i64, temp: result, name: rt_op, args: [cur, rhs_reg]})
      return lower_gvar_set(ctx, target.name, typed_value(:i64, result))
    return typed_value(:i64, cur)

  # Fast path: unboxed loop variable — operate on raw i64 directly.
  #
  # Phase 2 change (2026-04-15): +/-/* now emit native add_i64/sub_i64/
  # mul_i64 directly, NOT through the w_add/w_sub/w_mul runtime helpers.
  # Silent-wrap overflow semantics per the plan decision — the old path
  # boxed both operands, called the runtime for bigint-promotion on
  # i48 overflow, then unboxed. That's ~5-10x slower than native and
  # was the primary thing keeping hot-loop integer arithmetic slow.
  #
  # Users who explicitly want bigint promotion can annotate with ## int
  # which routes through the boxed path instead of this fast path.
  if ctx[:unboxed_vars] != nil && ctx[:unboxed_vars][name] != nil
    raw_slot = ctx[:unboxed_vars][name]
    cur_raw = next_temp(wfn)
    emit_instruction(wfn, {op: :load_i64, temp: cur_raw, ptr: raw_slot})

    rhs = lower_expression(ctx, node.value)
    rhs_raw = ensure_raw_int(wfn, rhs)

    op = node.op
    int_op = lowering_int_op_map[op]

    # All inline int ops (+/-/*, div, mod, bitwise) use native LLVM i64
    # arithmetic. No runtime fallback, no overflow guard. Return as
    # :raw_i64 so boundary-crossing boxing goes through w_int (which
    # correctly handles values outside the 48-bit nanbox range). If we
    # returned :raw_int here, a sum like 0..99999999 → 4999999950000000
    # would be truncated to 48 bits at the return site and produce
    # garbage. :raw_i64 is the safe, Phase-2-correct shape.
    if int_op != nil
      result_raw = next_temp(wfn)
      emit_instruction(wfn, {op: int_op, temp: result_raw, lhs: cur_raw, rhs: rhs_raw})
      emit_instruction(wfn, {op: :store_i64, value: result_raw, ptr: raw_slot})
      return typed_value(:raw_i64, result_raw)

    # Fallback: rebox, use runtime, unbox result
    cur_boxed_tv = nanbox_int_emit(wfn, cur_raw)
    rhs_reg = ensure_i64_value(wfn, rhs)
    rt_op = lowering_op_map[op]
    if rt_op != nil
      result = next_temp(wfn)
      emit_instruction(wfn, {op: :call_direct_i64, temp: result, name: rt_op, args: [cur_boxed_tv[:value], rhs_reg]})
      result_raw = nanunbox_int_emit(wfn, result)
      emit_instruction(wfn, {op: :store_i64, value: result_raw, ptr: raw_slot})
      return typed_value(:i64, result)
    return cur_boxed_tv

  if is_raw_int_storage_type(ctx[:var_types][name])
    machine_type = ctx[:var_types][name]
    ptr = ensure_var_slot(wfn, name, machine_slot_type(machine_type))
    cur_raw = next_temp(wfn)
    emit_instruction(wfn, {op: machine_load_op(machine_type), temp: cur_raw, ptr: ptr})

    rhs_raw = lower_machine_int_expression(ctx, node.value, machine_type)

    op = node.op
    int_op = machine_int_op(machine_type, op)
    rt_op = lowering_op_map[op]

    if int_op != nil
      result_raw = next_temp(wfn)
      emit_instruction(wfn, {op: int_op, temp: result_raw, lhs: cur_raw, rhs: rhs_raw})
      emit_instruction(wfn, {op: machine_store_op(machine_type), value: result_raw, ptr: ptr})
      return typed_value(raw_machine_value_type(machine_type), result_raw)

    cur_boxed = ensure_i64_value(wfn, typed_value(raw_machine_value_type(machine_type), cur_raw))
    rhs = lower_expression(ctx, node.value)
    rhs_reg = ensure_i64_value(wfn, rhs)
    if rt_op != nil
      result = next_temp(wfn)
      emit_instruction(wfn, {op: :call_direct_i64, temp: result, name: rt_op, args: [cur_boxed, rhs_reg]})
      result_raw = ensure_raw_machine_int(wfn, typed_value(:i64, result), machine_type, machine_type)
      emit_instruction(wfn, {op: machine_store_op(machine_type), value: result_raw, ptr: ptr})
      return typed_value(raw_machine_value_type(machine_type), result_raw)
    emit_instruction(wfn, {op: machine_store_op(machine_type), value: rhs_raw, ptr: ptr})
    return typed_value(raw_machine_value_type(machine_type), rhs_raw)

  if is_machine_float_type(ctx[:var_types][name])
    float_type = ctx[:var_types][name]
    ptr = ensure_var_slot(wfn, name, float_slot_type(float_type))
    cur_raw = next_temp(wfn)
    emit_instruction(wfn, {op: float_load_op(float_type), temp: cur_raw, ptr: ptr})

    rhs = lower_expression(ctx, node.value)
    # A Decimal RHS (bare `3.5` parses as a Decimal, so `f64var += 3.5`) is
    # coerced to a real double here by ensure_raw_f64 → w_num_to_f64; a bitcast-
    # unbox would produce garbage (see ensure_raw_f64's fallback comment).
    rhs_raw = nil
    if float_type in (:f32 :raw_f32)
      rhs_raw = ensure_raw_f32(wfn, rhs)
    else
      rhs_raw = ensure_raw_f64(wfn, rhs)

    op = node.op
    float_op = lowering_float_op_map[op]
    rt_op = lowering_op_map[op]

    if float_op != nil
      lhs64 = cur_raw
      rhs64 = rhs_raw
      if float_type in (:f32 :raw_f32)
        lhs64 = next_temp(wfn)
        rhs64_wide = next_temp(wfn)
        emit_instruction(wfn, {op: :fpext_f32_f64, temp: lhs64, value: cur_raw})
        emit_instruction(wfn, {op: :fpext_f32_f64, temp: rhs64_wide, value: rhs_raw})
        rhs64 = rhs64_wide
      result_raw = next_temp(wfn)
      emit_instruction(wfn, {op: float_op, temp: result_raw, lhs: lhs64, rhs: rhs64})
      store_raw = result_raw
      if float_type in (:f32 :raw_f32)
        store_raw = next_temp(wfn)
        emit_instruction(wfn, {op: :fptrunc_f64_f32, temp: store_raw, value: result_raw})
        emit_instruction(wfn, {op: :store_float, value: store_raw, ptr: ptr})
        return typed_value(:raw_f32, store_raw)
      emit_instruction(wfn, {op: :store_double, value: store_raw, ptr: ptr})
      return typed_value(:raw_f64, store_raw)

    cur_boxed = ensure_i64_value(wfn, typed_value(raw_float_value_type(float_type), cur_raw))
    rhs_reg = ensure_i64_value(wfn, rhs)
    if rt_op != nil
      result = next_temp(wfn)
      emit_instruction(wfn, {op: :call_direct_i64, temp: result, name: rt_op, args: [cur_boxed, rhs_reg]})
      result_raw = nil
      if float_type in (:f32 :raw_f32)
        result_raw = ensure_raw_f32(wfn, typed_value(:i64, result))
        emit_instruction(wfn, {op: :store_float, value: result_raw, ptr: ptr})
        return typed_value(:raw_f32, result_raw)
      result_raw = ensure_raw_f64(wfn, typed_value(:i64, result))
      emit_instruction(wfn, {op: :store_double, value: result_raw, ptr: ptr})
      return typed_value(:raw_f64, result_raw)
    emit_instruction(wfn, {op: float_store_op(float_type), value: rhs_raw, ptr: ptr})
    return typed_value(raw_float_value_type(float_type), rhs_raw)

  # Read current value: check binding first, then var slot
  binding = ctx[:bindings][name]
  if binding != nil
    cur = binding
    ptr = nil
  else
    ptr = ensure_var_slot(wfn, name)
    cur = next_temp(wfn)
    emit_instruction(wfn, {op: :load_i64, temp: cur, ptr: ptr})

  # A proven-dead boxed accumulator does not need to materialize the
  # intermediate product in `r += x * word` / `r -= x * word`.  The runtime
  # entry validates the dynamic integer/one-limb/capacity shape and otherwise
  # performs the original two operators, so this remains fail-closed.
  if ctx[:mut_accumulators] != nil && ctx[:mut_accumulators][name] == true
    linear_shape = bigint_linear_word_shape(node.value, node.op)
    if linear_shape != nil
      return lower_bigint_linear_word_mut(
        ctx, name, cur, ptr, linear_shape, node.op == :MINUS)

  # A literal power-of-two modulus carries its complete arithmetic context in
  # the syntax. Avoid materializing `1 << k` and route BigInt `%=` directly to
  # the low-limb truncation entry. Only the liveness-proved form may consume
  # the receiver; ordinary compound assignment keeps the immutable entry.
  pow2_bits = node.op == :PERCENT ? bigint_pow2_modulus_bits(node.value) : nil
  if pow2_bits != nil && env("TUNGSTEN_BIGINT_MOD_POW2") != "0" && ctx[:var_types][name] == :bigint
    bits_tv = typed_value(:raw_int, pow2_bits.to_s())
    bits_reg = ensure_i64_value(wfn, bits_tv)
    can_mutate = ctx[:mut_accumulators] != nil && ctx[:mut_accumulators][name] == true
    rt_name = can_mutate ? "w_bigint_mod_pow2_mut" : "w_bigint_mod_pow2"
    rt_cc = can_mutate ? "preserve_mostcc" : nil
    result_temp = next_temp(wfn)
    emit_instruction(wfn, {
      op: :call_direct_i64, temp: result_temp, name: rt_name,
      args: [cur, bits_reg], call_conv: rt_cc
    })
    if ptr != nil
      emit_instruction(wfn, {op: :store_i64, value: result_temp, ptr: ptr})
    else
      ctx[:bindings][name] = result_temp
    return typed_value(:i64, result_temp)

  # Evaluate RHS
  rhs = lower_expression(ctx, node.value)
  rhs_reg = ensure_i64_value(wfn, rhs)

  # Re-resolve the write-back target: lowering the RHS may have MATERIALIZED
  # bindings. Any :map / :calc (a fused pipeline), :or, :case, … calls
  # materialize_bindings, which spills every live binding into a var_slot and
  # clears ctx[:bindings]. The `ptr = nil` decision above is then stale —
  # storing the result into the now-cleared binding leaves the slot, which
  # every later read of this variable uses, still holding the pre-op value.
  # That silently DROPPED the compound assignment and desynchronized the
  # variable for the rest of the body: `t = 0` then `t += range/Σ(x)` returned
  # 0, and a following `t += 1` was lost too. `cur` stays valid either way —
  # materialize only copies binding registers into slots, and those registers
  # still dominate this point.
  if ptr == nil && ctx[:bindings][name] == nil
    ptr = ensure_var_slot(wfn, name)

  # Map compound op to binary op
  op = node.op
  int_op = lowering_int_op_map[op]
  rt_op = lowering_op_map[op]
  self_square = op == :STAR && node.value != nil && is_ast_node?(node.value) && ast_kind(node.value) == :var && node.value.name == name

  # Check if both sides are int for inline op
  lt = ctx[:var_types][name]
  vt = infer_type(node.value, ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)

  # For boxed integer compound assignment, use runtime calls because the
  # accumulator may already be a bigint and raw i48 operations would consume
  # pointer bits. Machine-declared i64/u64 variables take the earlier typed
  # path; this arm preserves arbitrary-precision promotion.
  if lt == :int && vt == :int && op in (:PLUS :MINUS :STAR :SLASH :PERCENT :AMPERSAND :PIPE :CARET :LSHIFT :RSHIFT)
    rt_fb = nil
    if op == :PLUS
      rt_fb = "w_add"
    elsif op == :MINUS
      rt_fb = "w_sub"
    elsif op == :STAR
      rt_fb = "w_mul"
    elsif op == :SLASH
      rt_fb = "w_div"
    elsif op == :PERCENT
      rt_fb = "w_mod"
    elsif op == :AMPERSAND
      rt_fb = "__w_band_fast"
    elsif op == :PIPE
      rt_fb = "__w_bor_fast"
    elsif op == :CARET
      rt_fb = "__w_bxor_fast"
    elsif op == :LSHIFT
      rt_fb = "__w_shl_fast"
    elsif op == :RSHIFT
      rt_fb = "__w_shr_fast"
    # Mutate-if-unique (E4 stage 1): compound arithmetic on a proven-dead
    # accumulator takes the in-place entry; its runtime guards fall back.
    mut_cc = nil
    if ctx[:mut_accumulators] != nil && ctx[:mut_accumulators][name] == true && op in (:PLUS :MINUS :STAR :SLASH :PERCENT :AMPERSAND :PIPE :CARET :LSHIFT :RSHIFT)
      if self_square && env("TUNGSTEN_BIGINT_SQR_MUT") == "0"
        rt_fb = "w_mul"
      elsif op == :PERCENT
        rt_fb = env("TUNGSTEN_BIGINT_MOD_MUT") == "0" ? "w_mod" : "w_bigint_mod_mut"
      elsif op == :AMPERSAND && env("TUNGSTEN_BIGINT_BITWISE_MUT") != "0"
        rt_fb = "w_bigint_and_mut"
      elsif op == :PIPE && env("TUNGSTEN_BIGINT_BITWISE_MUT") != "0"
        rt_fb = "w_bigint_or_mut"
      elsif op == :CARET && env("TUNGSTEN_BIGINT_BITWISE_MUT") != "0"
        rt_fb = "w_bigint_xor_mut"
      elsif op == :LSHIFT && env("TUNGSTEN_BIGINT_SHIFT_MUT") != "0"
        rt_fb = "w_bigint_shl_mut"
      elsif op == :RSHIFT && env("TUNGSTEN_BIGINT_SHIFT_MUT") != "0"
        rt_fb = "w_bigint_shr_mut"
      elsif op in (:AMPERSAND :PIPE :CARET :LSHIFT :RSHIFT)
        # Benchmark control: retain the immutable fast wrapper.
        nil
      else
        rt_fb = op == :PLUS ? "w_bigint_add_mut" : (op == :MINUS ? "w_bigint_sub_mut" : (op == :STAR ? "w_bigint_mul_mut" : "w_bigint_div_mut"))
      # must match the preserve_mostcc declaration or the call is UB
      if rt_fb in ("w_bigint_add_mut" "w_bigint_sub_mut" "w_bigint_mul_mut" "w_bigint_div_mut" "w_bigint_mod_mut" "w_bigint_and_mut" "w_bigint_or_mut" "w_bigint_xor_mut" "w_bigint_shl_mut" "w_bigint_shr_mut")
        mut_cc = "preserve_mostcc"
    result_temp = next_temp(wfn)
    emit_instruction(wfn, {op: :call_direct_i64, temp: result_temp, name: rt_fb, args: [cur, rhs_reg], call_conv: mut_cc})
    if ptr != nil
      emit_instruction(wfn, {op: :store_i64, value: result_temp, ptr: ptr})
    else
      ctx[:bindings][name] = result_temp
    return typed_value(:i64, result_temp)

  if lt == :int && vt == :int && int_op != nil
    cur_raw = nanunbox_int_emit(wfn, cur)
    rhs_raw = nanunbox_int_emit(wfn, rhs_reg)
    result = next_temp(wfn)
    emit_instruction(wfn, {op: int_op, temp: result, lhs: cur_raw, rhs: rhs_raw})
    boxed = nanbox_int_emit(wfn, result)
    boxed_reg = boxed[:value]
    if ptr != nil
      emit_instruction(wfn, {op: :store_i64, value: boxed_reg, ptr: ptr})
    else
      ctx[:bindings][name] = boxed_reg
    return boxed

  # Float compound assign: inline fadd/fsub/fmul/fdiv
  float_op = lowering_float_op_map[op]
  if lt == :float && vt == :float && float_op != nil
    cur_raw = ensure_raw_f64(wfn, typed_value(:i64, cur))
    rhs_raw = ensure_raw_f64(wfn, rhs)
    result = next_temp(wfn)
    emit_instruction(wfn, {op: float_op, temp: result, lhs: cur_raw, rhs: rhs_raw})
    boxed = typed_value(:raw_f64, result)
    boxed_reg = boxed[:value]
    if ptr != nil
      stored = ensure_i64_value(wfn, boxed)
      emit_instruction(wfn, {op: :store_i64, value: stored, ptr: ptr})
    else
      ctx[:bindings][name] = boxed_reg
    return boxed

  # String self-append: s += "x" → w_str_append(s, "x")
  # Uses mutable in-place append (realloc) instead of rope allocation.
  # Only triggered when we know the LHS is a string — an unknown (nil) type
  # used to trigger this path, which wrongly promoted integer parameters
  # to string-append semantics and hung loops like `while n < 3; n += 1`.
  # The RHS must be provably text too: strict `+` means s += 3 is a
  # TypeError, so non-text and unknown RHS fall to the generic w_add,
  # which concatenates text and raises for everything else.
  if op == :PLUS && lt == :string && vt in (:string :char)
    result = next_temp(wfn)
    emit_instruction(wfn, {op: :call_direct_i64, temp: result, name: "w_str_append", args: [cur, rhs_reg]})
    if ptr != nil
      emit_instruction(wfn, {op: :store_i64, value: result, ptr: ptr})
    else
      ctx[:bindings][name] = result
    ctx[:var_types][name] = :string
    return typed_value(:i64, result)

  # Fallback: runtime call. Unknown-typed compound accumulators reach this
  # arm, so preserve their mutate-if-unique routing too.
  if rt_op != nil
    rt_call_conv = nil
    if ctx[:mut_accumulators] != nil && ctx[:mut_accumulators][name] == true && op in (:PLUS :MINUS :STAR :SLASH :PERCENT :AMPERSAND :PIPE :CARET :LSHIFT :RSHIFT)
      if self_square && env("TUNGSTEN_BIGINT_SQR_MUT") == "0"
        rt_op = "w_mul"
      elsif op == :PERCENT
        rt_op = env("TUNGSTEN_BIGINT_MOD_MUT") == "0" ? "w_mod" : "w_bigint_mod_mut"
      elsif op == :AMPERSAND && env("TUNGSTEN_BIGINT_BITWISE_MUT") != "0"
        rt_op = "w_bigint_and_mut"
      elsif op == :PIPE && env("TUNGSTEN_BIGINT_BITWISE_MUT") != "0"
        rt_op = "w_bigint_or_mut"
      elsif op == :CARET && env("TUNGSTEN_BIGINT_BITWISE_MUT") != "0"
        rt_op = "w_bigint_xor_mut"
      elsif op == :LSHIFT && env("TUNGSTEN_BIGINT_SHIFT_MUT") != "0"
        rt_op = "w_bigint_shl_mut"
      elsif op == :RSHIFT && env("TUNGSTEN_BIGINT_SHIFT_MUT") != "0"
        rt_op = "w_bigint_shr_mut"
      elsif op in (:AMPERSAND :PIPE :CARET :LSHIFT :RSHIFT)
        nil
      else
        rt_op = op == :PLUS ? "w_bigint_add_mut" : (op == :MINUS ? "w_bigint_sub_mut" : (op == :STAR ? "w_bigint_mul_mut" : "w_bigint_div_mut"))
      if rt_op in ("w_bigint_add_mut" "w_bigint_sub_mut" "w_bigint_mul_mut" "w_bigint_div_mut" "w_bigint_mod_mut" "w_bigint_and_mut" "w_bigint_or_mut" "w_bigint_xor_mut" "w_bigint_shl_mut" "w_bigint_shr_mut")
        rt_call_conv = "preserve_mostcc"
    result = next_temp(wfn)
    emit_instruction(wfn, {op: :call_direct_i64, temp: result, name: rt_op, args: [cur, rhs_reg], call_conv: rt_call_conv})
    if ptr != nil
      emit_instruction(wfn, {op: :store_i64, value: result, ptr: ptr})
    else
      ctx[:bindings][name] = result
    return typed_value(:i64, result)

  # Unknown op — just store RHS
  if ptr != nil
    emit_instruction(wfn, {op: :store_i64, value: rhs_reg, ptr: ptr})
  else
    ctx[:bindings][name] = rhs_reg
  typed_value(:i64, rhs_reg)

# -- Binary ops --

# Returns the bit-value (as a string for IR emission) if `n` is a sentinel
# literal — nil (W_NIL=0), false (W_FALSE=1), true (W_TRUE=2) — otherwise
# nil. Used by the eq/neq fast path to emit single-instruction checks
# instead of polymorphic w_eq/w_neq dispatch.
-> sentinel_value_of(n)
  if n == nil
    return nil
  if ast_kind(n) == :nil_lit
    return "0"
  if ast_kind(n) == :bool
    if n.value == true
      return "2"
    return "1"
  nil

# Return k for the exact compile-time modulus shape `1 << k`. Restricting
# the fold to a literal exponent keeps operator dispatch and evaluation order
# unchanged for every dynamic expression.
-> bigint_pow2_modulus_bits(n)
  if n == nil || !is_ast_node?(n) || ast_kind(n) != :binary_op || n.op != :LSHIFT
    return nil
  if n.left == nil || !is_ast_node?(n.left) || ast_kind(n.left) != :int || n.left.value != 1
    return nil
  if n.right == nil || !is_ast_node?(n.right) || ast_kind(n.right) != :int
    return nil
  bits = n.right.value
  if bits < 0 || bits > 140737488355327
    return nil
  bits

# True when `nm` names a local slot, binding, typed var, or a known
# fn/call — i.e. the identifier refers to real code, not a unit name.
# Anything a bare name could legitimately resolve to at lowering time —
# the pipe shadow set plus function parameters (fn bodies have no
# class_name, and params live in wfn[:params], not var_slots) and
# already-registered top-level globals. Used by the symbolic `*` rewrite.
-> star_ident_bound?(ctx, nm)
  if pipe_ident_shadowed?(ctx, nm)
    return true
  if ctx[:mod][:top_level_vars] != nil && ctx[:mod][:top_level_vars][nm] != nil
    return true
  params = ctx[:func][:params]
  if params != nil
    i = 0
    while i < params.size()
      if params[i] == nm
        return true
      i += 1
  false

-> pipe_ident_shadowed?(ctx, nm)
  if ctx[:func][:var_slots][nm] != nil || ctx[:bindings][nm] != nil || ctx[:var_types][nm] != nil
    return true
  if ctx[:mod][:known_calls][nm] != nil || ctx[:mod][:known_fn_param_counts][nm] != nil
    return true
  false

# Rebuild a bare unit spelling from the expression shape a compound or
# mixed-case conversion target parses to: `km/h` is a `/`-map, `J·s` a
# DOT_PRODUCT, `W/m²` a POW over a map, and a mixed-case name like `eV` or
# `mmHg` is a juxtaposition call `e(V)`. Leaves that name real locals or fns
# stay expressions; the caller validates the joined spelling against the unit
# registry. Mirrors interpreter.w interp_pipe_unit_spelling.
-> pipe_unit_spelling(ctx, rhs)
  if !is_ast_node?(rhs)
    return nil
  k = ast_kind(rhs)
  if k == :var || k == :class_ref
    nm = ast_get(rhs, :name)
    if nm == nil
      return nil
    if pipe_ident_shadowed?(ctx, nm)
      return nil
    return nm
  if k == :binary_op
    bop = rhs.op
    if bop == :SLASH || bop == :DOT_PRODUCT
      lsp = pipe_unit_spelling(ctx, rhs.left)
      if lsp == nil
        return nil
      rsp = pipe_unit_spelling(ctx, rhs.right)
      if rsp == nil
        return nil
      if bop == :SLASH
        return lsp + "/" + rsp
      return lsp + "·" + rsp
    if bop == :POW
      ex = rhs.right
      if is_ast_node?(ex) && ast_kind(ex) == :int
        lsp = pipe_unit_spelling(ctx, rhs.left)
        if lsp == nil
          return nil
        sup = unit_superscript_for_power(ast_get(ex, :value))
        if sup == nil
          return nil
        return lsp + sup
    return nil
  if k == :map
    src = ast_get(rhs, :source)
    fnode = ast_get(rhs, :func)
    if !is_ast_node?(src) || !is_ast_node?(fnode)
      return nil
    fname = nil
    fk = ast_kind(fnode)
    if fk == :call && fnode.receiver == nil
      fargs = fnode.args
      if fargs == nil || fargs.size() == 0
        fname = ast_get(fnode, :name)
    elsif fk == :var || fk == :class_ref
      fname = ast_get(fnode, :name)
    if fname == nil
      return nil
    if pipe_ident_shadowed?(ctx, fname)
      return nil
    lsp = pipe_unit_spelling(ctx, src)
    if lsp == nil
      return nil
    return lsp + "/" + fname
  if k == :call
    cname = ast_get(rhs, :name)
    if cname != nil && (ctx[:mod][:known_calls][cname] != nil || ctx[:mod][:known_fn_param_counts][cname] != nil)
      return nil
    jt = pipe_juxta_target(rhs)
    if jt == nil
      return nil
    if jt[:digits] >= 0
      return nil
    return jt[:name]
  nil

# `eV` lexes as ident + Constant and parses as the juxtaposition call `e(V)`;
# `mmHg` and `kWh` nest the same way, and rounding digits ride the innermost
# call — `eV(3)` is `e(V(3))`. Rejoin the pieces — the parts are lexer
# artifacts, not identifiers, so only the joined spelling is meaningful (and
# is registry-checked by the caller). Returns {name, digits}; digits is -1
# when absent. Mirrors interpreter.w interp_pipe_juxta_target.
-> pipe_juxta_target(rhs)
  if !is_ast_node?(rhs)
    return nil
  k = ast_kind(rhs)
  if k == :var || k == :class_ref
    nm = ast_get(rhs, :name)
    if nm == nil
      return nil
    return {name: nm, digits: 0 - 1}
  if k != :call
    return nil
  if rhs.receiver != nil
    return nil
  nm = ast_get(rhs, :name)
  if nm == nil
    return nil
  cargs = rhs.args
  if cargs == nil || cargs.size() != 1
    return nil
  if !is_ast_node?(cargs[0])
    return nil
  if ast_kind(cargs[0]) == :int
    return {name: nm, digits: ast_get(cargs[0], :value)}
  inner = pipe_juxta_target(cargs[0])
  if inner == nil
    return nil
  {name: nm + inner[:name], digits: inner[:digits]}

# Conversion-pipe target: `| lb`, `| lb(2)`, `| J`, or a quoted registry
# spelling such as `| "metric cup"`. Returns
# {name, digits} when the RHS is a quoted spelling or a bare known-unit name —
# a var, PascalCase class_ref, one-int-arg call, or a compound spelling that
# parsed as an expression shape (see pipe_unit_spelling). Anything a local/fn
# shadows lowers as ordinary bitwise-or / division instead; quoted spellings
# are always explicit.
-> pipe_unit_target(ctx, rhs)
  if !is_ast_node?(rhs)
    return nil
  name = nil
  digits = 0 - 1
  quoted = false
  k = ast_kind(rhs)
  if k == :string
    name = ast_get(rhs, :value)
    quoted = true
  elsif k == :var || k == :class_ref
    name = ast_get(rhs, :name)
  elsif k == :call && rhs.receiver == nil
    cargs = rhs.args
    if cargs != nil && cargs.size() == 1 && is_ast_node?(cargs[0]) && ast_kind(cargs[0]) == :int
      name = ast_get(rhs, :name)
      digits = ast_get(cargs[0], :value)
    else
      # `eV` / `mmHg` / `eV(3)`: mixed-case juxtaposition, digits riding the
      # innermost call. A name that resolves to real code stays a call.
      cname = ast_get(rhs, :name)
      if cname == nil || (ctx[:mod][:known_calls][cname] == nil && ctx[:mod][:known_fn_param_counts][cname] == nil)
        jt = pipe_juxta_target(rhs)
        if jt != nil
          name = jt[:name]
          digits = jt[:digits]
  elsif k == :map
    # `km/h` lexes as a `/`-map: source `km`, func the bare call `h`; the
    # rounding form `km/h(2)` carries one int arg on the func call. Rebuild
    # the compound name and require the components to be unshadowed — else
    # `x | a/b` with a real variable a or b stays a division.
    src = ast_get(rhs, :source)
    fnode = ast_get(rhs, :func)
    if is_ast_node?(src) && is_ast_node?(fnode) && ast_kind(fnode) == :call && fnode.receiver == nil
      fargs = fnode.args
      fdigits = 0 - 1
      fok = fargs == nil || fargs.size() == 0
      if !fok && fargs.size() == 1 && is_ast_node?(fargs[0]) && ast_kind(fargs[0]) == :int
        fok = true
        fdigits = ast_get(fargs[0], :value)
      if fok
        sname = pipe_unit_spelling(ctx, src)
        fname = ast_get(fnode, :name)
        if sname != nil && fname != nil && !pipe_ident_shadowed?(ctx, fname)
          name = sname + "/" + fname
          digits = fdigits
  if name == nil
    name = pipe_unit_spelling(ctx, rhs)
  if name == nil
    return nil
  if !known_unit_name?(name)
    return nil
  if !quoted && (ctx[:func][:var_slots][name] != nil || ctx[:bindings][name] != nil || ctx[:var_types][name] != nil)
    return nil
  if !quoted && (ctx[:mod][:known_calls][name] != nil || ctx[:mod][:known_fn_param_counts][name] != nil)
    return nil
  {name: name, digits: digits}

# Range#/ (step): `(a..b) / n` → an Array of a, a+n, a+2n, ... while < b
# (or <= b for an inclusive range). Bounds aren't known at compile time in
# general (e.g. `pass.prev..100`), so this desugars to real statements —
# an empty array, a counter, and a while-loop — lowered through the normal
# statement pipeline rather than hand-emitted IR.
# `range.step(n)` (block_node == nil) is parsed identically to any other
# no-block call, so a trailing arrow-block instead attaches directly to
# `step` itself — `step` is on the block-taking exclusion list in
# method_takes_no_block? (types.w), same as Ruby's Numeric#step. Honor
# that: with a block, dispatch it per stepped value (like .each); without
# one, return the materialized array.
-> lower_range_step(ctx, range_node, step_node, block_node = nil)
  uid = ctx[:mod][:next_block]
  ctx[:mod][:next_block] = uid + 1
  arr_name = "__step_arr_" + uid.to_s()
  i_name = "__step_i_" + uid.to_s()
  lim_name = "__step_lim_" + uid.to_s()

  lower_statement(ctx, Tungsten:AST:Assign.new(Tungsten:AST:Var.new(arr_name), Tungsten:AST:Array.new([])))
  lower_statement(ctx, Tungsten:AST:Assign.new(Tungsten:AST:Var.new(i_name), range_node.from))

  limit_expr = range_node.to
  if range_node.exclusive != true
    limit_expr = Tungsten:AST:BinaryOp.new(range_node.to, :PLUS, Tungsten:AST:Int.new(1))
  lower_statement(ctx, Tungsten:AST:Assign.new(Tungsten:AST:Var.new(lim_name), limit_expr))

  cond = Tungsten:AST:BinaryOp.new(Tungsten:AST:Var.new(i_name), :LT, Tungsten:AST:Var.new(lim_name))
  push_call = Tungsten:AST:Call.new(Tungsten:AST:Var.new(arr_name), "push", [Tungsten:AST:Var.new(i_name)])
  incr = Tungsten:AST:CompoundAssign.new(Tungsten:AST:Var.new(i_name), :PLUS, step_node)
  lower_statement(ctx, Tungsten:AST:While.new(cond, [push_call, incr]))

  if block_node != nil
    lower_statement(ctx, Tungsten:AST:Call.new(Tungsten:AST:Var.new(arr_name), "each", [], block_node))
    return typed_value(:i64, w_nil.to_s())

  lower_expression(ctx, Tungsten:AST:Var.new(arr_name))

# -- Tag-guard folding (Phase 3, with Phase 2.5's assert lever) --
#
# Known-bits abstract evaluation of NaN-box tag expressions. The only
# base fact is `wvalue_bits(X)` where X carries a :structural tag fact
# (Phase 2, infer_tag): a :top_tag entry fixes bits 48..63 and nothing
# else — bit 47 (the sign overlay) stays a runtime value, so sign reads
# never fold. The guard idioms in core sources are
# `(bits >> 48) & 0xFFFF` and `bits & TAG_MASK` against a tag constant;
# RSHIFT, AND and integer literals are the whole expression language,
# evaluated through a {known-mask, bits} lattice with bits normalized to
# known positions. `fact` marks that a tag fact fed the value — the
# engagement condition, so plain integer compares lower exactly as
# before (no drive-by constant folding, no byte drift off the fact path).
-> tag_known_bits(ctx, node)
  if node == nil || !is_ast_node?(node)
    return nil
  k = ast_kind(node)
  if k == :int
    return {known: 0 - 1, bits: node.value, fact: false}
  # Negative literals parse as unary MINUS over an int; a fully-known
  # operand negates to a fully-known constant (mask-compare guards spell
  # TAG_MASK/BIGINT_TAG as signed literals).
  if k == :unary_op && node.op == :MINUS
    uk = tag_known_bits(ctx, node.operand)
    if uk != nil && uk[:known] == 0 - 1
      return {known: 0 - 1, bits: 0 - uk[:bits], fact: uk[:fact]}
    return nil
  if k == :var || k == :gvar
    # `$value` is the receiver's own 64-bit content (parsed as a GVar in
    # expression position, a Var in others; lower_gvar/lower_var both
    # expose it raw for any class) — exactly wvalue_bits(self), so it
    # carries the same __self fact.
    if node.name == "$value"
      facts = ctx[:tag_facts]
      if facts != nil
        f = facts["__self"]
        if f != nil && tag_fact_structural?(f)
          entry = f[:entry]
          if entry != nil && entry[:shape] == :top_tag
            m = entry[:mask].to_i
            return {known: m, bits: entry[:tag].to_i & m, fact: true}
      return nil
    # A single-assignment `## i64` top-level constant with a literal RHS
    # (mod[:top_level_const_values]) loads as its literal — resolve it so
    # named tag constants (`__W_BI_TAG`) fold exactly like immediates.
    cvals = ctx[:mod][:top_level_const_values]
    if cvals != nil
      cv = cvals[node.name]
      # Values outside the inline i48 payload live as BigInts in compiler
      # arithmetic (the tag constants themselves do) — both spellings of
      # integer are table-valid.
      if cv != nil && type(cv) in ("Integer" "BigInt")
        return {known: 0 - 1, bits: cv, fact: false}
    return nil
  if k == :call && node.name == "wvalue_bits" && node.receiver == nil && node.args != nil && node.args.size() == 1
    f = infer_tag(node.args[0], ctx)
    if f != nil && tag_fact_structural?(f)
      entry = f[:entry]
      if entry != nil && entry[:shape] == :top_tag
        m = entry[:mask].to_i
        return {known: m, bits: entry[:tag].to_i & m, fact: true}
    return nil
  if k == :binary_op
    if node.op == :RSHIFT
      rk = tag_known_bits(ctx, node.right)
      if rk == nil || rk[:known] != 0 - 1 || rk[:bits] < 0 || rk[:bits] > 63
        return nil
      lk = tag_known_bits(ctx, node.left)
      if lk == nil
        return nil
      sh = rk[:bits]
      # Arithmetic shift of both fields: fill positions inherit bit 63's
      # known-ness and value; re-normalize bits to the known mask.
      known2 = lk[:known] >> sh
      return {known: known2, bits: (lk[:bits] >> sh) & known2, fact: lk[:fact]}
    if node.op == :AMPERSAND
      lk = tag_known_bits(ctx, node.left)
      rk = tag_known_bits(ctx, node.right)
      if lk == nil || rk == nil
        return nil
      allb = 0 - 1
      # Known where both are known, or where either side is a known zero.
      known2 = (lk[:known] & rk[:known]) | (lk[:known] & (lk[:bits] ^ allb)) | (rk[:known] & (rk[:bits] ^ allb))
      return {known: known2, bits: (lk[:bits] & rk[:bits]) & known2, fact: lk[:fact] || rk[:fact]}
  nil

# Decide an EQ/NEQ over tag bits: :true_const, :false_const, or nil
# (lower normally). A known-bit mismatch decides inequality even under
# partial knowledge; equality needs both sides fully known.
-> fold_tag_compare(ctx, node)
  if ctx[:tag_assert_skip] == true
    return nil
  lk = tag_known_bits(ctx, node.left)
  if lk == nil
    return nil
  rk = tag_known_bits(ctx, node.right)
  if rk == nil
    return nil
  if lk[:fact] == false && rk[:fact] == false
    return nil
  common = lk[:known] & rk[:known]
  differs = ((lk[:bits] ^ rk[:bits]) & common) != 0
  allb = 0 - 1
  eq_val = nil
  if differs
    eq_val = false
  elsif lk[:known] == allb && rk[:known] == allb
    eq_val = true
  if eq_val == nil
    return nil
  want = node.op == :EQ ? eq_val : !eq_val
  want ? :true_const : :false_const

-> lower_binary_op(ctx, node)
  wfn = ctx[:func]
  op = node.op

  # Tag-guard fold: a comparison over NaN-box tag bits decided by a
  # :structural fact folds to its constant. An undecided or fact-free
  # compare falls through unchanged — the nil path is the load-bearing
  # safe default.
  if op in (:EQ :NEQ)
    tfold = fold_tag_compare(ctx, node)
    if tfold != nil
      fold_rhs = tfold == :true_const ? "0" : "1"
      tconst = next_temp(wfn)
      emit_instruction(wfn, {op: :icmp_i64, temp: tconst, pred: "eq", lhs: "0", rhs: fold_rhs})
      return typed_value(:i1, tconst)

  # Reject dimensionally impossible additions/subtractions while compiling
  # when both sides are statically known quantities. Dynamic and user-defined
  # unit expressions retain the existing runtime check.
  if op in (:PLUS :MINUS)
    qleft = static_quantity_signature(ctx, node.left)
    qright = static_quantity_signature(ctx, node.right)
    pbj = false
    if op == :PLUS && ast_kind(node.left) == :quantity && ast_kind(node.right) == :quantity
      lu = node.left.unit
      ru = node.right.unit
      one_each = node.left.number_str.replace("_", "") == "1" && node.right.number_str.replace("_", "") == "1"
      pbj = one_each && ((lu == "PB" && ru == "J") || (lu == "J" && ru == "PB"))
    if qleft != nil && qright != nil && !static_quantity_add_compatible?(qleft, qright) && !pbj
      raise compile_error_for_node(:E_LOWER_QUANTITY_DIMENSION, "quantity dimension mismatch in " + op.to_s(), ctx[:source_path], node)

  # Assignment spelling of the same fused shape handled by compound
  # assignment above: `r = r +/- x * word`.  lower_assign_expr scopes the
  # marker to a fail-closed mutate-if-unique proof for this exact RHS.
  mut_name = ctx[:mut_accum_target]
  if mut_name != nil && op in (:PLUS :MINUS)
    if node.left != nil && is_ast_node?(node.left) && ast_kind(node.left) == :var && node.left.name == mut_name
      linear_shape = bigint_linear_word_shape(node.right, op)
      if linear_shape != nil
        acc_tv = lower_expression(ctx, node.left)
        acc_reg = ensure_i64_value(wfn, acc_tv)
        result = emit_bigint_linear_word_mut(
          ctx, acc_reg, linear_shape, op == :MINUS)
        return typed_value(:i64, result)

  if op == :SLASH && ast_kind(node.left) == :range
    return lower_range_step(ctx, node.left, node.right)

  # Conversion pipe on quantities: `5 kg + 3 kg | lb(2)` — converts into the
  # named unit, optionally rounding. Syntactic: the RHS names a unit rather
  # than evaluating to a value.
  if op == :PIPE
    pu = pipe_unit_target(ctx, node.right)
    if pu != nil
      lhs_tv = lower_expression(ctx, node.left)
      lhs_reg = ensure_i64_value(wfn, lhs_tv)
      uname_tv = lower_string(ctx, Tungsten:AST:String.new(pu[:name]))
      uname_reg = ensure_i64_value(wfn, uname_tv)
      dig_tv = lower_expression(ctx, Tungsten:AST:Int.new(pu[:digits]))
      dig_reg = ensure_i64_value(wfn, dig_tv)
      temp = next_temp(wfn)
      emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_quantity_pipe", args: [lhs_reg, uname_reg, dig_reg]})
      return typed_value(:i64, temp)

  # `2 * x` with an undefined bare name at SCRIPT level mirrors the `2x`
  # juxtaposition — the name becomes a 1·name unit factor
  # (w_quantity_parse registers custom units on demand), so explicit-star
  # and juxtaposed spellings of the same symbolic product agree. Scoped
  # OUTSIDE class bodies (implicit-self dispatch owns bare names there)
  # and to names no local/param/binding/fn/global shadows.
  if op == :STAR && ctx[:class_name] == nil
    if is_ast_node?(node.left) && ast_kind(node.left) == :var
      sym_lname = node.left.name
      if sym_lname != nil && !star_ident_bound?(ctx, sym_lname)
        node.left = Tungsten:AST:Quantity.new("1", sym_lname)
    if is_ast_node?(node.right) && ast_kind(node.right) == :var
      sym_rname = node.right.name
      if sym_rname != nil && !star_ident_bound?(ctx, sym_rname)
        node.right = Tungsten:AST:Quantity.new("1", sym_rname)

  # Phase 4e dot-prefix elementwise operators — `lhs .+ rhs` etc. The
  # lexer guards whitespace at scan time so these never collide with
  # method-call dot syntax. Runtime helpers handle the float/int/w64
  # ebits split internally and broadcast scalar rhs. Phase 6 SIMD will
  # rewrite the float and 32-bit-integer paths to use NEON/AVX intrinsics.
  if op in (:DOT_PLUS :DOT_MINUS :DOT_STAR :DOT_SLASH :DOT_PIPE :DOT_AMP :DOT_CARET :DOT_LSHIFT :DOT_RSHIFT)
    # f64 elementwise trees fuse into a single loop (see try_fuse_
    # elementwise below); everything else keeps the runtime kernels.
    fused = try_fuse_elementwise(ctx, node)
    if fused != nil
      return fused
    lhs_tv = lower_expression(ctx, node.left)
    rhs_tv = lower_expression(ctx, node.right)
    lhs_reg = ensure_i64_value(wfn, lhs_tv)
    rhs_reg = ensure_i64_value(wfn, rhs_tv)
    fn_name = "w_array_add_elem"
    if op == :DOT_MINUS
      fn_name = "w_array_sub_elem"
    elsif op == :DOT_STAR
      fn_name = "w_array_mul_elem"
    elsif op == :DOT_SLASH
      fn_name = "w_array_div_elem"
    elsif op == :DOT_PIPE
      fn_name = "w_array_bor_elem"
    elsif op == :DOT_AMP
      fn_name = "w_array_band_elem"
    elsif op == :DOT_CARET
      fn_name = "w_array_bxor_elem"
    elsif op == :DOT_LSHIFT
      fn_name = "w_array_shl_elem"
    elsif op == :DOT_RSHIFT
      fn_name = "w_array_shr_elem"
    temp = next_temp(wfn)
    emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: fn_name, args: [lhs_reg, rhs_reg]})
    return typed_value(:i64, temp)

  if op == :MATCH
    if ast_kind(node.left) == :regex
      return lower_regex_match(ctx, Tungsten:AST:RegexMatch.new(node.left, node.right))
    if ast_kind(node.right) == :regex
      return lower_regex_match(ctx, Tungsten:AST:RegexMatch.new(node.right, node.left))

  # Sentinel fast path: `x == nil|true|false` / `x != nil|true|false`
  # → inline icmp against the sentinel bit value. W_NIL=0, W_FALSE=1,
  # W_TRUE=2 are unique WValue bit patterns, so equality to any of them
  # is a single icmp — no polymorphic w_eq / w_neq dispatch.
  if op in (:EQ :NEQ)
    sentinel = nil
    lhs_is = sentinel_value_of(node.left)
    rhs_is = sentinel_value_of(node.right)
    if lhs_is != nil
      sentinel = lhs_is
      other = node.right
    elsif rhs_is != nil
      sentinel = rhs_is
      other = node.left
    if sentinel != nil
      other_val = lower_expression(ctx, other)
      other_reg = ensure_i64_value(wfn, other_val)
      pred = op == :EQ ? "eq" : "ne"
      temp = next_temp(wfn)
      emit_instruction(wfn, {op: :icmp_i64, temp: temp, pred: pred, lhs: other_reg, rhs: sentinel})
      return typed_value(:i1, temp)

  # String/symbol-LITERAL fast path: `x == "when"` / `x != :sym` is three
  # inline instructions in the common case instead of a w_eq call. Sound by
  # the canonical-representation invariants (wvalue.h): modes 0-5 pack the
  # content in the box (length = mode, 0-5 bytes), mode 6 is the interned
  # slab (6-61 bytes) — length-disjoint, so equal content in a canonical
  # mode ⇒ equal bits, and different bits + canonical lhs ⇒ not equal.
  # Everything else (mode-7 heap/rope strings, non-strings, user objects
  # with == overloads) falls to the runtime call, preserving dispatch. Only
  # literals that lowered to a compile-time constant qualify (>61-byte
  # literals and no-static-slab builds lower to calls and are skipped).
  if op in (:EQ :NEQ)
    slit = nil
    sother = nil
    if node.left != nil && is_ast_node?(node.left) && ast_kind(node.left) in (:string :symbol)
      slit = node.left
      sother = node.right
    elsif node.right != nil && is_ast_node?(node.right) && ast_kind(node.right) in (:string :symbol)
      slit = node.right
      sother = node.left
    if slit != nil
      lit_tv = lower_expression(ctx, slit)
      lit_reg = "" + lit_tv[:value]
      if lit_tv[:type] == :i64 && lit_reg.starts_with?("u0x")
        other_val = lower_expression(ctx, sother)
        other_reg = ensure_i64_value(wfn, other_val)
        sv = next_temp(wfn)
        emit_instruction(wfn, {op: :call_direct_i64, temp: sv, name: "__w_streq_fast", args: [other_reg, lit_reg]})
        temp = next_temp(wfn)
        pred = op == :EQ ? "eq" : "ne"
        emit_instruction(wfn, {op: :icmp_i64, temp: temp, pred: pred, lhs: sv, rhs: w_true.to_s()})
        return typed_value(:i1, temp)

  # Type-directed: if both sides are int, emit inline LLVM ops
  lt = infer_type(node.left, ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)
  rt = infer_type(node.right, ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)

  # Compile-time modular context: `big % (1 << k)` needs neither construction
  # of the modulus nor general division. Keep this type-directed so a
  # user-defined `%` method on an unknown/non-BigInt receiver still dispatches
  # normally. A proven-dead assignment may consume its receiver buffer.
  pow2_bits = op == :PERCENT ? bigint_pow2_modulus_bits(node.right) : nil
  if pow2_bits != nil && env("TUNGSTEN_BIGINT_MOD_POW2") != "0" && is_bigint_type(lt)
    lhs_tv = lower_expression(ctx, node.left)
    lhs_reg = ensure_i64_value(wfn, lhs_tv)
    bits_reg = ensure_i64_value(wfn, typed_value(:raw_int, pow2_bits.to_s()))
    can_mutate = ctx[:mut_accum_target] != nil && node.left != nil && is_ast_node?(node.left) && ast_kind(node.left) == :var && node.left.name == ctx[:mut_accum_target]
    rt_name = can_mutate ? "w_bigint_mod_pow2_mut" : "w_bigint_mod_pow2"
    rt_cc = can_mutate ? "preserve_mostcc" : nil
    temp = next_temp(wfn)
    emit_instruction(wfn, {
      op: :call_direct_i64, temp: temp, name: rt_name,
      args: [lhs_reg, bits_reg], call_conv: rt_cc
    })
    return typed_value(:i64, temp)

  # Var-var string == / != under a :string type fact on either side: route
  # through __w_streq2_fast — bits equal -> true, BOTH canonical stringy
  # (tag 0xFFF9, mode 0-6) -> false, anything else (mode-7 heap, ropes,
  # stale facts, non-strings) -> w_eq. Semantics-preserving for every
  # value, so a stale/wrong fact only costs the two inline checks; the
  # fact just picks the sites where the fold PAYS (w_eq was the compiler
  # self-profile's #1 leaf at ~15%, dominated by canonical-key compares).
  # The literal arm above already took every site with a constant operand.
  if op in (:EQ :NEQ) && (lt == :string || rt == :string)
    lhs_tv2 = lower_expression(ctx, node.left)
    lhs_reg2 = ensure_i64_value(wfn, lhs_tv2)
    rhs_tv2 = lower_expression(ctx, node.right)
    rhs_reg2 = ensure_i64_value(wfn, rhs_tv2)
    sv2 = next_temp(wfn)
    emit_instruction(wfn, {op: :call_direct_i64, temp: sv2, name: "__w_streq2_fast", args: [lhs_reg2, rhs_reg2]})
    temp2 = next_temp(wfn)
    pred2 = op == :EQ ? "eq" : "ne"
    emit_instruction(wfn, {op: :icmp_i64, temp: temp2, pred: pred2, lhs: sv2, rhs: w_true.to_s()})
    return typed_value(:i1, temp2)

  # Unicode vector / matrix products. For known WArray-backed receivers,
  # lower straight to the float kernels. Otherwise preserve normal method
  # dispatch so user-defined `-> ·(other)` / `-> ×(other)` / `-> ⊙(other)`
  # / `-> ⊗(other)` methods still work.
  #
  # ·   DOT_PRODUCT   — inner product (vectors)
  # ×   CROSS_PRODUCT — cross product (Vec3)
  # ⊙   HADAMARD      — componentwise / element-wise product (Vec, Mat)
  # ⊗   KRONECKER     — Kronecker / tensor / outer product (Mat, Vec→Mat)
  if op in (:DOT_PRODUCT :CROSS_PRODUCT :HADAMARD :KRONECKER)
    lhs_tv = lower_expression(ctx, node.left)
    rhs_tv = lower_expression(ctx, node.right)
    lhs_reg = ensure_i64_value(wfn, lhs_tv)
    rhs_reg = ensure_i64_value(wfn, rhs_tv)

    if op == :DOT_PRODUCT && lt in (:typed_array_i8 :typed_array_u8) && rt in (:typed_array_i8 :typed_array_u8)
      temp = next_temp(wfn)
      emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_array_dot_i8", args: [lhs_reg, rhs_reg]})
      return typed_value(:i64, temp)

    if op in (:DOT_PRODUCT :CROSS_PRODUCT) && (lt == :array || is_typed_array_type?(lt)) && (rt == :array || is_typed_array_type?(rt))
      fn_name = op == :DOT_PRODUCT ? "w_array_dot_float" : "w_array_cross_float"
      temp = next_temp(wfn)
      emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: fn_name, args: [lhs_reg, rhs_reg]})
      return typed_value(:i64, temp)

    method_name = "·"
    if op == :CROSS_PRODUCT
      method_name = "×"
    if op == :HADAMARD
      method_name = "⊙"
    if op == :KRONECKER
      method_name = "⊗"
    method_name_tv = lower_string(ctx, Tungsten:AST:String.new(method_name))
    method_name_val = ensure_i64_value(wfn, method_name_tv)
    temp_args_val = next_temp(wfn)
    temp = next_temp(wfn)
    ic_id = ctx[:mod][:next_ic]
    ctx[:mod][:next_ic] = ic_id + 1
    emit_instruction(wfn, {
      op: :call_method_i64,
      temp: temp,
      temp_args_val: temp_args_val,
      receiver: lhs_reg,
      method_name_val: method_name_val,
      args: [rhs_reg],
      ic_id: ic_id,
      src_line: node.line,
      src_col: node.col
    })
    return typed_value(:i64, temp)

  # StringBuffer#<<(string): static typed receiver dispatch. This avoids the
  # generic `w_bit_shl` path and its runtime method/operator checks.
  if op == :LSHIFT && lt == :string_buffer && rt == :string
    lhs = lower_expression(ctx, node.left)
    rhs = lower_expression(ctx, node.right)
    lhs_reg = ensure_i64_value(wfn, lhs)
    rhs_reg = ensure_i64_value(wfn, rhs)
    temp = next_temp(wfn)
    emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_strbuf_append", args: [lhs_reg, rhs_reg]})
    return typed_value(:i64, temp)

  # String#<< mutates at the language level. Runtime strings are immutable
  # WValues, so compile the common variable form as a rebinding append.
  if op == :LSHIFT && lt == :string && node.left != nil && ast_kind(node.left) == :var
    lhs = lower_expression(ctx, node.left)
    rhs = lower_expression(ctx, node.right)
    lhs_reg = ensure_i64_value(wfn, lhs)
    rhs_reg = ensure_i64_value(wfn, rhs)
    temp = next_temp(wfn)
    emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_str_append", args: [lhs_reg, rhs_reg]})
    return rebind_local_i64(ctx, node.left.name, temp, :string)

  # String + String: both sides statically text → direct w_str_concat.
  # The generic path (__w_add_fast → w_add) re-discovers stringiness per
  # call and coerces the RHS through w_to_s; with both types known that
  # whole preamble is a no-op. Concat semantics (rope over 61 bytes,
  # canonical w_string_n below) are w_add's own string arm.
  if op == :PLUS && lt == :string && rt == :string
    lhs = lower_expression(ctx, node.left)
    rhs = lower_expression(ctx, node.right)
    lhs_reg = ensure_i64_value(wfn, lhs)
    rhs_reg = ensure_i64_value(wfn, rhs)
    temp = next_temp(wfn)
    # `pre + i.to_s()`: when the RHS is syntactically an anonymous call
    # whose lowering's LAST emitted instruction is a guaranteed-fresh
    # string producer with this very temp (w_int_to_s mints an
    # independent heap string per call), no name can alias it and this
    # concat is its only consumer — route through the freeing variant so
    # the intermediate doesn't leak (str_concat primitive: 482MB RSS at
    # 30M iterations from exactly this temp). Both syntactic anonymity
    # AND last-instruction identity are required: a bare var RHS
    # binding-forwards an earlier temp that IS nameable.
    # TUNGSTEN_FREE=0 is the documented kill switch for ALL compiler-inserted
    # frees — the concat variants must honor it too or corruption triage
    # can't rule them out.
    cname = "w_str_concat"
    if env("TUNGSTEN_FREE") != "0" && node.right != nil && is_ast_node?(node.right) && ast_kind(node.right) == :call
      li = last_emitted_instruction(wfn)
      if li != nil && li[:op] == :call_direct_i64 && li[:name] == "w_int_to_s" && li[:temp] == rhs_reg
        cname = "w_str_concat_free_rhs"
    emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: cname, args: [lhs_reg, rhs_reg]})
    return typed_value(:i64, temp)

  # Untyped shift-left must keep arbitrary-precision semantics. Integer
  # literals infer :i64 and int-shaped locals ride raw slots, so the machine
  # and inline arms below would emit a bare `shl` that silently wraps past
  # 63 bits: `1 << 200` compiled to 0 while the interpreter promotes to
  # BigInt. A literal base folds when the shifted value provably fits the
  # inline i48 payload (mask idioms stay free); every other literal-based
  # shift routes to the boxed __w_shl_fast fallback, whose inline fast path
  # is itself a checked shl that promotes on overflow. A non-literal base
  # keeps the machine arm: a machine-typed operand chose wrap semantics.
  # The fold guard only accepts 0 <= lv < 2^47, where the stage-0 C VM's
  # wrapped i64 view of a literal agrees exactly with the self-hosted
  # BigInt view, so the fold decision cannot diverge between stages.
  shl_literal_base = op == :LSHIFT && node.left != nil && is_ast_node?(node.left) && ast_kind(node.left) == :int
  if shl_literal_base && node.right != nil && is_ast_node?(node.right) && ast_kind(node.right) == :int
    lv = node.left.value
    rv = node.right.value
    if lv >= 0 && rv >= 0 && rv <= 46 && lv <= (140737488355327 >> rv)
      return typed_value(:raw_int, (lv << rv).to_s())

  machine_type = machine_int_result_type(lt, rt)
  # `:int` is a BOXED integer that may have promoted to a heap BigInt at
  # runtime -- that is exactly what distinguishes `## int` from `## i64`. It
  # must never be unboxed as a raw i48: `shl 16 / ashr 16` on a BigInt WValue
  # sign-extends POINTER bits, and everything downstream then computes on the
  # pointer. A plain integer literal infers :i64, so `big + 1` satisfied
  # machine_int_result_type through the literal alone and took the raw path --
  # printing garbage for +, -, *, & and >>, and answering `==` wrong.
  # Suppressing the machine path drops these to the guarded i48 path
  # (tag-checked, with a w_add/w_sub/w_mul fallback) and to the boxed runtime
  # ops, both of which handle promotion correctly. This mirrors the
  # compound-assign path above, which already refuses the checked i48 ops for
  # `:int` operands for exactly this reason.
  promotable_int_operand = lt == :int || rt == :int
  if machine_type != nil && !promotable_int_operand && !shl_literal_base && is_integer_like_type(lt) && is_integer_like_type(rt)
    int_op = machine_int_op(machine_type, op)
    cmp_pred = machine_cmp_pred(machine_type, op)

    # In a `Math.promote` / `Math.trap` block, integer +/-/* must reach the
    # guarded i48 path below even when inference has classified operands as
    # machine ints. Plain integer literals infer as :i64, and default raw locals
    # are also stored as machine ints; letting them take this fast path would
    # silently wrap before the lexical mode can promote or trap. `Math.wrap`
    # and the default mode keep this native path unchanged.
    ovf_mode_mi = ctx[:overflow_mode]
    ovf_guard_machine = overflow_mode_guards_machine_int_arith?(ovf_mode_mi, op)

    if int_op != nil && !ovf_guard_machine
      lhs_raw = lower_machine_int_expression(ctx, node.left, machine_type)
      rhs_raw = lower_machine_int_expression(ctx, node.right, machine_type)
      temp = next_temp(wfn)
      emit_instruction(wfn, {op: int_op, temp: temp, lhs: lhs_raw, rhs: rhs_raw})
      return typed_value(raw_machine_value_type(machine_type), temp)

    if cmp_pred != nil
      lhs_raw = lower_machine_int_expression(ctx, node.left, machine_type)
      rhs_raw = lower_machine_int_expression(ctx, node.right, machine_type)
      temp = next_temp(wfn)
      emit_instruction(wfn, {op: machine_cmp_op(machine_type), temp: temp, pred: cmp_pred, lhs: lhs_raw, rhs: rhs_raw})
      return typed_value(:i1, temp)

  lhs_unboxed = node.left != nil && ast_kind(node.left) == :var && ctx[:unboxed_vars][node.left.name] != nil
  rhs_unboxed = node.right != nil && ast_kind(node.right) == :var && ctx[:unboxed_vars][node.right.name] != nil
  # Opt-in BigInt accumulator (`## big`): if either operand is a BigInt-typed
  # var, do NOT take the native-i64 unbox shortcut — `ensure_raw_int` would
  # truncate the boxed accumulator to 48/64 bits and silently wrap. Fall
  # through to the runtime fallback (w_add/w_mul), which boxes the other
  # (possibly unboxed loop-counter) operand and auto-promotes to BigInt.
  #
  # Same for an active `Math.promote` / `Math.trap` block: +/-/* must reach
  # the guarded path so overflow promotes (or traps) instead of natively
  # wrapping. This covers an outer unboxed loop-counter referenced inside the
  # block. `Math.wrap` and the default (nil) keep this native fast path.
  ovf_mode_bo = ctx[:overflow_mode]
  # In a promote/trap block an unboxed operand may hold a BigInt promoted by an
  # earlier +/-/*; the native shortcut would truncate it. Suppress the shortcut
  # for ALL arithmetic/bitwise int ops (not just +/-/*), so +/-/* reach the
  # guarded path and div/mod/bitwise fall through to the runtime fallback
  # (w_div/w_mod/w_bit_*), which dispatches BigInt-correctly.
  ovf_guard_arith = (ovf_mode_bo == :promote || ovf_mode_bo == :trap) && (lowering_int_op_map[op] != nil || lowering_cmp_op_map[op] != nil)
  # A float (or decimal) operand must NOT take this raw-int shortcut:
  # ensure_raw_int on a boxed float nanunbox-INTs it — `i + ~1.0` inside a
  # loop silently became `i + 0`. Known-float operands fall through to the
  # type-directed int×float path below (sitofp + fadd).
  mixed_float_operand = is_machine_float_type(lt) || is_machine_float_type(rt) || lt == :decimal || rt == :decimal
  # Shift-left is excluded from the raw-unbox shortcut outright: an unboxed
  # slot's inferred raw type carries no wrap opt-in (`## i64` operands take
  # the machine arm above instead), and `x << k` overflows i64 with tiny
  # operands, so it must reach __w_shl_fast's checked shl to promote.
  #
  # The NON-unboxed side must have a KNOWN inline-int-safe type before this
  # arm may ensure_raw_int it: an nil-typed operand can hold anything —
  # `r = 1 << 4096` infers nil and holds a heap BigInt, and nanunboxing it
  # fed pointer bits to `add i64` (accumulate checksum diverged from the
  # interpreter). `:int` is excluded for the same reason as everywhere
  # else: it may have promoted at runtime.
  lhs_raw_safe = lhs_unboxed || (lt != nil && lt != :int && is_integer_like_type(lt) && !is_bigint_type(lt))
  rhs_raw_safe = rhs_unboxed || (rt != nil && rt != :int && is_integer_like_type(rt) && !is_bigint_type(rt))
  if (lhs_unboxed || rhs_unboxed) && lhs_raw_safe && rhs_raw_safe && op != :LSHIFT && !mixed_float_operand && !is_bigint_type(lt) && !is_bigint_type(rt) && !ovf_guard_arith
    int_op = lowering_int_op_map[op]
    cmp_pred = lowering_cmp_op_map[op]
    if int_op != nil || cmp_pred != nil
      lhs = lower_expression(ctx, node.left)
      rhs = lower_expression(ctx, node.right)
      lhs_raw = ensure_raw_int(wfn, lhs)
      rhs_raw = ensure_raw_int(wfn, rhs)
      temp = next_temp(wfn)
      if int_op != nil
        emit_instruction(wfn, {op: int_op, temp: temp, lhs: lhs_raw, rhs: rhs_raw})
        return typed_value(:raw_i64, temp)
      emit_instruction(wfn, {op: :icmp_i64, temp: temp, pred: cmp_pred, lhs: lhs_raw, rhs: rhs_raw})
      return typed_value(:i1, temp)

  if is_integer_like_type(lt) && is_integer_like_type(rt)
    int_op = lowering_int_op_map[op]
    cmp_pred = lowering_cmp_op_map[op]

    # Arithmetic: guarded inline i48 with bigint/overflow fallback to runtime
    if int_op != nil && op in (:PLUS :MINUS :STAR)
      ovf_mode = ctx[:overflow_mode]
      # `Math.wrap -> ...`: explicit native silent-wrap on (boxed) ints — no
      # overflow guard, mirroring the default unboxed fast path. Returns
      # :raw_i64 so a >48-bit result isn't re-truncated at the box site.
      if ovf_mode == :wrap
        lhs = lower_expression(ctx, node.left)
        rhs = lower_expression(ctx, node.right)
        # Use ensure_raw_i64 (routes boxed operands through w_to_i64 = low 64
        # bits), NOT ensure_raw_int (nanunbox_int, which assumes a NaN-boxed
        # i48 and reads garbage from a BigInt heap pointer — non-deterministic
        # corruption for a bare `>2^48` literal). w_to_i64 gives the defined
        # i64-wrap of any integer; raw `## i64` operands pass straight through.
        lhs_raw = ensure_raw_i64(wfn, lhs)
        rhs_raw = ensure_raw_i64(wfn, rhs)
        temp = next_temp(wfn)
        emit_instruction(wfn, {op: int_op, temp: temp, lhs: lhs_raw, rhs: rhs_raw})
        return typed_value(:raw_i64, temp)
      guarded_op = nil
      rt_fn = nil
      if op == :PLUS
        guarded_op = :add_i48_guarded
        rt_fn = "w_add"
      elsif op == :MINUS
        guarded_op = :sub_i48_guarded
        rt_fn = "w_sub"
      elsif op == :STAR
        guarded_op = :mul_i48_guarded
        rt_fn = "w_mul"
      # Mutate-if-unique (E4 stage 1): this binary op is the RHS of
      # `r = r ± e` for a proven-dead accumulator (lower_assign_expr set
      # the marker). The i48 fast path is untouched — only the overflow/
      # boxed fallback becomes the in-place entry, whose runtime guards
      # (alias count, overlay bit, capacity) fall back to w_add/w_sub.
      if ctx[:mut_accum_target] != nil && node.left != nil && is_ast_node?(node.left) && ast_kind(node.left) == :var && node.left.name == ctx[:mut_accum_target] && op in (:PLUS :MINUS :STAR)
        rt_fn = op == :PLUS ? "w_bigint_add_mut" : (op == :MINUS ? "w_bigint_sub_mut" : "w_bigint_mul_mut")
      lhs = lower_expression(ctx, node.left)
      rhs = lower_expression(ctx, node.right)
      lhs_reg = ensure_i64_value(wfn, lhs)
      rhs_reg = ensure_i64_value(wfn, rhs)
      block_id = ctx[:mod][:next_block]
      ctx[:mod][:next_block] = block_id + 4
      temp = next_temp(wfn)
      # `Math.trap -> ...`: on i48 overflow, branch to llvm.trap (abort) in
      # the guarded emitter instead of the BigInt-promoting runtime call.
      # `Math.promote` (and the default boxed path) keep the w_add/w_sub/w_mul
      # fallback, which auto-promotes to BigInt. The `:trap` key is added ONLY
      # in trap mode, so the promote/default guarded instruction is byte-
      # identical to before this feature (no codegen drift on the fast path).
      guarded_inst = {
        op: guarded_op, temp: temp,
        lhs: lhs_reg, rhs: rhs_reg,
        rt_fallback: rt_fn, block_id: block_id
      }
      if ovf_mode == :trap
        guarded_inst[:trap] = true
      emit_instruction(wfn, guarded_inst)
      return typed_value(:i64, temp)

    # Non-overflowing int ops (div, mod, bitwise): inline without check.
    # Exception: inside a `Math.promote`/`Math.trap` block an operand may have
    # been promoted to BigInt by an earlier +/-/*; the inline path's
    # `ensure_raw_int` would truncate it to i64 and silently corrupt the result.
    # Skip to the runtime fallback (w_div/w_mod/w_bit_*), which keeps operands
    # boxed (ensure_i64_value) and dispatches BigInt-correctly. `wrap` and the
    # default (nil) keep the native inline path — div/mod don't overflow-promote
    # and there's no boxed bignum to mishandle.
    om_dm = ctx[:overflow_mode]
    # A `:int` operand carries the same hazard the promote/trap note above
    # describes, but unconditionally: it may ALREADY hold a BigInt (`big =
    # a + b` promoted it), and ensure_raw_int nanunbox-INTs a heap pointer.
    # `b2 & 255` and `b2 >> 8` returned pointer-derived garbage in the
    # default mode too, so `:int` skips this inline path regardless of the
    # lexical overflow mode.
    # :LSHIFT is excluded here for the same reason as the raw-unbox shortcut
    # above: this inline path wraps at i64, and operands landing here carry
    # no machine-type wrap opt-in.
    if int_op != nil && op != :LSHIFT && om_dm != :promote && om_dm != :trap && !promotable_int_operand
      lhs = lower_expression(ctx, node.left)
      rhs = lower_expression(ctx, node.right)
      lhs_raw = ensure_raw_int(wfn, lhs)
      rhs_raw = ensure_raw_int(wfn, rhs)
      temp = next_temp(wfn)
      emit_instruction(wfn, {op: int_op, temp: temp, lhs: lhs_raw, rhs: rhs_raw})
      return typed_value(:raw_int, temp)

    # Comparisons: inline icmp, return as i1 (avoids box/unbox when used in branch).
    # In a `Math.promote`/`Math.trap` block an operand may be a boxed BigInt (loop
    # var with unboxing suppressed, or one promoted by an earlier +/-/*); the inline
    # path's `ensure_raw_int` would TRUNCATE it to i64 and compare garbage. Skip to
    # the runtime fallback (w_eq/w_neq/w_lt/...), which keeps operands boxed and
    # compares BigInt-correctly (returning a boxed bool the branch lowering handles).
    # Same for comparisons: a promoted `:int` compared through ensure_raw_int
    # compares pointer bits, which made `b2 == 281474976710654` answer FALSE.
    if cmp_pred != nil && om_dm != :promote && om_dm != :trap && !promotable_int_operand
      lhs = lower_expression(ctx, node.left)
      rhs = lower_expression(ctx, node.right)
      lhs_raw = ensure_raw_int(wfn, lhs)
      rhs_raw = ensure_raw_int(wfn, rhs)
      temp = next_temp(wfn)
      emit_instruction(wfn, {op: :icmp_i64, temp: temp, pred: cmp_pred, lhs: lhs_raw, rhs: rhs_raw})
      return typed_value(:i1, temp)

  # Float arithmetic: inline fadd/fsub/fmul/fdiv
  if (lt == :float || lt == :f64) && (rt == :float || rt == :f64)
    float_op = lowering_float_op_map[op]
    fcmp_pred = lowering_fcmp_op_map[op]

    # fmuladd peephole — precise mode only (not strict, not fast).
    # Emits llvm.fmuladd.f64 for *direct* `a*b + c` / `a*b - c` patterns, where
    # the addend `c` is NOT itself a product. This is a deliberately SAFER
    # variant of C's -ffp-contract=on, which would also contract `a*b - c*d`.
    #
    # The carve-out is the whole point of precise mode: contracting
    # `x1*y2 - x2*y1` to fmuladd(x1, y2, -(x2*y1)) makes a cross product /
    # 2x2 determinant come out NON-ZERO when x1==x2, y1==y2 (the inner
    # x2*y1 rounds first, while x1*y2 stays exact inside the FMA). That sign
    # surprise is exactly what we refuse here — when both sides of the
    # add/sub are products we fall through to bare fmul/fmul/fadd, so the
    # determinant is exactly 0. Direct `a*b ± scalar` (Horner, accumulation)
    # still contracts. See doc/specification/floating-point-math.md.
    #
    # `addend_is_product` gates both branches: left-multiply (`a*b ± c`) and
    # the commuted add (`c + a*b`).
    if float_op in (:fadd_f64 :fsub_f64)
      effective_mode = ctx[:math_mode_override]
      if effective_mode == nil
        effective_mode = ctx[:mod][:math_mode]
      left_is_product = ast_kind(node.left) == :binary_op && node.left.op == :STAR
      right_is_product = ast_kind(node.right) == :binary_op && node.right.op == :STAR
      both_products = left_is_product && right_is_product
      if effective_mode == :precise && !both_products
        # Detect lhs = a*b (left-multiply): a*b + c  or  a*b - c  (c not a product)
        if left_is_product
          c_tv = lower_expression(ctx, node.right)
          c_raw = ensure_raw_f64(wfn, c_tv)
          a_tv = lower_expression(ctx, node.left.left)
          a_raw = ensure_raw_f64(wfn, a_tv)
          b_tv = lower_expression(ctx, node.left.right)
          b_raw = ensure_raw_f64(wfn, b_tv)
          if float_op == :fsub_f64
            neg_c = next_temp(wfn)
            emit_instruction(wfn, {op: :fneg_f64, temp: neg_c, value: c_raw})
            c_raw = neg_c
          temp = next_temp(wfn)
          # Operands ride on lhs/rhs/value (a*b+c) — the field names apply_subst
          # and content_hash already rewrite, so mem2reg promotion of the a/b/c
          # loads stays correct. See the :fmuladd_f64 emitter case for why.
          emit_instruction(wfn, {op: :fmuladd_f64, temp: temp, lhs: a_raw, rhs: b_raw, value: c_raw})
          return typed_value(:raw_f64, temp)
        # Detect rhs = a*b (right-multiply, commuted add only): c + a*b.
        # `both_products` already excluded above, so reaching here means the
        # left addend is not a product — safe to contract.
        if float_op == :fadd_f64 && right_is_product
          c_tv = lower_expression(ctx, node.left)
          c_raw = ensure_raw_f64(wfn, c_tv)
          a_tv = lower_expression(ctx, node.right.left)
          a_raw = ensure_raw_f64(wfn, a_tv)
          b_tv = lower_expression(ctx, node.right.right)
          b_raw = ensure_raw_f64(wfn, b_tv)
          temp = next_temp(wfn)
          emit_instruction(wfn, {op: :fmuladd_f64, temp: temp, lhs: a_raw, rhs: b_raw, value: c_raw})
          return typed_value(:raw_f64, temp)

    if float_op != nil
      lhs = lower_expression(ctx, node.left)
      rhs = lower_expression(ctx, node.right)
      lhs_raw = ensure_raw_f64(wfn, lhs)
      rhs_raw = ensure_raw_f64(wfn, rhs)
      temp = next_temp(wfn)
      inst_flags = float_inst_flags(ctx)
      emit_instruction(wfn, {op: float_op, temp: temp, lhs: lhs_raw, rhs: rhs_raw, fp_flags: inst_flags})
      return typed_value(:raw_f64, temp)

    if fcmp_pred != nil
      lhs = lower_expression(ctx, node.left)
      rhs = lower_expression(ctx, node.right)
      lhs_raw = ensure_raw_f64(wfn, lhs)
      rhs_raw = ensure_raw_f64(wfn, rhs)
      temp = next_temp(wfn)
      emit_instruction(wfn, {op: :fcmp_f64, temp: temp, pred: fcmp_pred, lhs: lhs_raw, rhs: rhs_raw})
      return typed_value(:i1, temp)

  # Mixed int×float: promote int to double, then inline float op.
  # Equality promotes ONLY for an int LITERAL whose value is exactly
  # representable (|n| ≤ 2^47 covers every inline literal) — the
  # exactness-gated adaptation rule. A non-literal int operand falls to
  # the runtime call and stays strict (Floats equal only Float VALUES).
  if (lt == :float && is_integer_like_type(rt)) || (is_integer_like_type(lt) && rt == :float)
    float_op = lowering_float_op_map[op]
    fcmp_pred = lowering_fcmp_op_map[op]
    if op in (:EQ :NEQ)
      eq_lit_node = lt == :float ? node.right : node.left
      eq_lit_ok = eq_lit_node != nil && is_ast_node?(eq_lit_node) && ast_kind(eq_lit_node) == :int
      if eq_lit_ok
        eq_lit_v = eq_lit_node.value
        eq_lit_ok = eq_lit_v > 0 - 140737488355328 && eq_lit_v < 140737488355328
      if !eq_lit_ok
        fcmp_pred = nil

    if float_op != nil || fcmp_pred != nil
      lhs = lower_expression(ctx, node.left)
      rhs = lower_expression(ctx, node.right)

      # Unbox each operand according to its type
      if lt == :float
        lhs_f = ensure_raw_f64(wfn, lhs)
      else
        lhs_raw = ensure_raw_machine_int(wfn, lhs, lt, lt)
        lhs_f = next_temp(wfn)
        emit_instruction(wfn, {op: machine_int_to_f64_op(lt), temp: lhs_f, value: lhs_raw})

      if rt == :float
        rhs_f = ensure_raw_f64(wfn, rhs)
      else
        rhs_raw = ensure_raw_machine_int(wfn, rhs, rt, rt)
        rhs_f = next_temp(wfn)
        emit_instruction(wfn, {op: machine_int_to_f64_op(rt), temp: rhs_f, value: rhs_raw})

      if float_op != nil
        temp = next_temp(wfn)
        inst_flags = float_inst_flags(ctx)
        emit_instruction(wfn, {op: float_op, temp: temp, lhs: lhs_f, rhs: rhs_f, fp_flags: inst_flags})
        return typed_value(:raw_f64, temp)

      if fcmp_pred != nil
        temp = next_temp(wfn)
        emit_instruction(wfn, {op: :fcmp_f64, temp: temp, pred: fcmp_pred, lhs: lhs_f, rhs: rhs_f})
        return typed_value(:i1, temp)

  # Compile-time type algebra: detect invalid literal type combinations
  if lt != nil && rt != nil
    check_type_algebra(lt, rt, op, node)

  # Fallback: call runtime
  lhs = lower_expression(ctx, node.left)
  rhs = lower_expression(ctx, node.right)
  lhs_reg = ensure_i64_value(wfn, lhs)
  rhs_reg = ensure_i64_value(wfn, rhs)

  rt_name = lowering_op_map[op]
  if rt_name == nil
    rt_name = "w_add"  # fallback, should not happen

  # Static typed dispatch (DEFAULT): a call site whose operand types both
  # infer bigint lowers to a tag-GUARDED direct call to the operator
  # worker through its stable alias (`__w_bigint_{plus,minus,times}_src`,
  # strong when the program compiles BigInt, weak C kernel otherwise) —
  # w_add/w_sub/w_mul stay the slow path for types the compiler cannot
  # see. The two masked compares are load-bearing, not paranoia: a bigint
  # RESULT demotes to an inline int whenever it fits i48 (`d = a - b` of
  # near-equal bigints), so an inferred-bigint slot can legally hold an
  # int at runtime, and the worker bodies carry NO tag checks of their
  # own. A failed test falls to the polymorphic entry. The worker itself
  # re-routes the C-favored strata (equal-length same-raw-sign, squaring)
  # to the direct C entries, so this path keeps the measured per-shape
  # routing. Mutate-if-unique accumulator sites keep their in-place
  # entries (the marker check below mirrors the fallback rewrite).
  bidir_mut = ctx[:mut_accum_target] != nil && node.left != nil && is_ast_node?(node.left) && ast_kind(node.left) == :var && node.left.name == ctx[:mut_accum_target]
  # --tags report: classify this infix arithmetic site. :static_direct
  # takes the guarded direct-worker call below; :near_miss has exactly
  # one bigint-inferred operand (typing the other would upgrade it);
  # :polymorphic is everything else reaching the runtime entry. Side
  # data only — never read by hashing or emission.
  if op in (:PLUS :MINUS :STAR :AMPERSAND :PIPE :CARET :SLASH :PERCENT)
    bidir_report = :polymorphic
    if !bidir_mut && is_bigint_type(lt) && is_bigint_type(rt)
      bidir_report = :static_direct
    elsif !bidir_mut && (is_bigint_type(lt) || is_bigint_type(rt))
      bidir_report = :near_miss
    if ctx[:mod][:tag_report_infix] == nil
      ctx[:mod][:tag_report_infix] = []
    ctx[:mod][:tag_report_infix].push({op: op, route: bidir_report, fname: wfn[:source_method], class_name: ctx[:class_name]})
  if op in (:PLUS :MINUS :STAR :AMPERSAND :PIPE :CARET :SLASH :PERCENT) && !bidir_mut && is_bigint_type(lt) && is_bigint_type(rt)
    # Seam symbol per op (strong = the compiled typed worker, weak = the C
    # kernel) and the polymorphic entry for the guard's slow arm. The
    # workers handle every both-heap-bigint shape themselves (in-body
    # bails go to the polymorphic entries, whose seam gates exclude
    # exactly those shapes — no recursion), so the exact-tag guard is the
    # only precondition this route needs.
    bidir_fast = "__w_bigint_plus_src"
    bidir_slow = "w_add"
    if op == :MINUS
      bidir_fast = "__w_bigint_minus_src"
      bidir_slow = "w_sub"
    elsif op == :STAR
      bidir_fast = "__w_bigint_times_src"
      bidir_slow = "w_mul"
    elsif op == :AMPERSAND
      bidir_fast = "__w_bigint_and_src"
      bidir_slow = "w_bit_and"
    elsif op == :PIPE
      bidir_fast = "__w_bigint_or_src"
      bidir_slow = "w_bit_or"
    elsif op == :CARET
      bidir_fast = "__w_bigint_xor_src"
      bidir_slow = "w_bit_xor"
    elsif op == :SLASH
      bidir_fast = "__w_bigint_div_src"
      bidir_slow = "w_div"
    elsif op == :PERCENT
      bidir_fast = "__w_bigint_mod_src"
      bidir_slow = "w_mod"
    # Tag/mask spellings come from the generated B3 table — the same
    # single source the typed-overload gate emission uses.
    bidir_entry = overload_exact_tag_entry("BigInt")
    bm1 = next_temp(wfn)
    emit_instruction(wfn, {op: :and_i64, temp: bm1, lhs: lhs_reg, rhs: bidir_entry[:mask]})
    bc1 = next_temp(wfn)
    emit_instruction(wfn, {op: :icmp_i64, temp: bc1, pred: "eq", lhs: bm1, rhs: bidir_entry[:tag]})
    bm2 = next_temp(wfn)
    emit_instruction(wfn, {op: :and_i64, temp: bm2, lhs: rhs_reg, rhs: bidir_entry[:mask]})
    bc2 = next_temp(wfn)
    emit_instruction(wfn, {op: :icmp_i64, temp: bc2, pred: "eq", lhs: bm2, rhs: bidir_entry[:tag]})
    bboth = next_temp(wfn)
    emit_instruction(wfn, {op: :and_i1, temp: bboth, lhs: bc1, rhs: bc2})
    fast_label = next_label(wfn, "bidir.fast")
    slow_label = next_label(wfn, "bidir.slow")
    done_label = next_label(wfn, "bidir.done")
    bidir_slot = ensure_var_slot(wfn, "__bidir." + done_label)
    emit_instruction(wfn, {op: :cond_br, cond: bboth, then_label: fast_label, else_label: slow_label})
    start_block(wfn, fast_label)
    bfast = next_temp(wfn)
    emit_instruction(wfn, {op: :call_direct_i64, temp: bfast, name: bidir_fast, args: [lhs_reg, rhs_reg]})
    emit_instruction(wfn, {op: :store_i64, value: bfast, ptr: bidir_slot})
    emit_instruction(wfn, {op: :br, label: done_label})
    start_block(wfn, slow_label)
    bslow = next_temp(wfn)
    emit_instruction(wfn, {op: :call_direct_i64, temp: bslow, name: bidir_slow, args: [lhs_reg, rhs_reg]})
    emit_instruction(wfn, {op: :store_i64, value: bslow, ptr: bidir_slot})
    emit_instruction(wfn, {op: :br, label: done_label})
    start_block(wfn, done_label)
    bres = next_temp(wfn)
    emit_instruction(wfn, {op: :load_i64, temp: bres, ptr: bidir_slot})
    return typed_value(:i64, bres)

  # Exactness-gated literal adaptation: ==/!= with an int or decimal
  # LITERAL operand routes through w_eq_lit, which adapts the literal to
  # a Float operand iff exactly representable. Provenance-based —
  # variables keep the plain strict w_eq path. case/when inherits this
  # via its BinaryOp(:EQ, pattern) desugar.
  if op in (:EQ :NEQ)
    lit_adjacent = false
    if node.left != nil && is_ast_node?(node.left) && ast_kind(node.left) in (:int :decimal)
      lit_adjacent = true
    if node.right != nil && is_ast_node?(node.right) && ast_kind(node.right) in (:int :decimal)
      lit_adjacent = true
    if lit_adjacent
      rt_name = op == :EQ ? "__w_eq_lit_fast" : "__w_neq_lit_fast"
  # Mutate-if-unique (E4 stage 1): the untyped accumulator shape lands here
  # (an nil-typed `r` skips the machine and guarded arms), so the marker
  # set by lower_assign_expr routes `r = r ± e` through the in-place entry
  # instead of __w_add_fast/__w_sub_fast.
  rt_call_conv = nil
  if ctx[:mut_accum_target] != nil && op in (:PLUS :MINUS :STAR :SLASH :PERCENT) && node.left != nil && is_ast_node?(node.left) && ast_kind(node.left) == :var && node.left.name == ctx[:mut_accum_target]
    self_square = op == :STAR && node.right != nil && is_ast_node?(node.right) && ast_kind(node.right) == :var && node.right.name == ctx[:mut_accum_target]
    if self_square && env("TUNGSTEN_BIGINT_SQR_MUT") == "0"
      rt_name = "w_mul"
    elsif op == :PERCENT
      rt_name = env("TUNGSTEN_BIGINT_MOD_MUT") == "0" ? "w_mod" : "w_bigint_mod_mut"
    else
      rt_name = op == :PLUS ? "w_bigint_add_mut" : (op == :MINUS ? "w_bigint_sub_mut" : (op == :STAR ? "w_bigint_mul_mut" : "w_bigint_div_mut"))
    if rt_name != "w_mod" && rt_name != "w_mul"
      rt_call_conv = "preserve_mostcc"

  temp = next_temp(wfn)
  emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: rt_name, args: [lhs_reg, rhs_reg], call_conv: rt_call_conv})
  typed_value(:i64, temp)

# Get raw i64 from a typed_value — skip unbox if already raw
-> ensure_raw_int(wfn, tv)
  if tv[:type] in (:raw_int :raw_i64 :raw_u64)
    return tv[:value]
  return nanunbox_int_emit(wfn, ensure_i64_value(wfn, tv))

-> ensure_raw_i64(wfn, tv, inferred_type = nil)
  ensure_raw_machine_int(wfn, tv, :i64, inferred_type)

-> ensure_raw_u64(wfn, tv, inferred_type = nil)
  ensure_raw_machine_int(wfn, tv, :u64, inferred_type)

-> ensure_raw_machine_int(wfn, tv, type, inferred_type = nil)
  src_type = raw_machine_source_type(tv, inferred_type)
  # `:char` typed_values carry the literal codepoint directly (no temp),
  # so they're already in raw immediate form — skip nanunbox.
  if tv[:type] == :char
    return cast_raw_machine_int(wfn, tv[:value], :i64, type)
  if src_type != nil && tv[:type] in (:raw_i64 :raw_u64 :raw_i128 :raw_u128 :raw_int)
    return cast_raw_machine_int(wfn, tv[:value], src_type, type)
  if tv[:type] in (:raw_f32 :raw_f64)
    raw = tv[:value]
    if tv[:type] == :raw_f32
      extended = next_temp(wfn)
      emit_instruction(wfn, {op: :fpext_f32_f64, temp: extended, value: raw})
      raw = extended
    converted = next_temp(wfn)
    emit_instruction(wfn, {op: f64_to_machine_int_op(type), temp: converted, value: raw})
    return converted
  boxed = ensure_i64_value(wfn, tv)
  # No nanunbox shortcut for `:int`-inferred values: `:int` means "may have
  # promoted to a heap BigInt at runtime" (same exclusion as every raw
  # shortcut above), and nanunbox_int on a heap WValue reads pointer bits —
  # `(x * <beyond-i64 literal>) ## u64` returned allocator garbage instead
  # of the defined low-64 wrap. The runtime unbox (w_to_i64 family) gives
  # the same value for inline ints and the defined truncation for BigInts.
  temp = next_temp(wfn)
  emit_instruction(wfn, {
    op: machine_call_return_op(type),
    temp: temp,
    name: machine_unbox_fn(type),
    args: [boxed],
    arg_types: ["i64"]
  })
  temp

-> nanunbox_int_emit(wfn, boxed_reg)
  temp_shl = next_temp(wfn)
  temp = next_temp(wfn)
  emit_instruction(wfn, {op: :nanunbox_int, temp: temp, temp_shl: temp_shl, boxed: boxed_reg})
  temp

-> nanbox_int_emit(wfn, raw_reg)
  temp_masked = next_temp(wfn)
  temp = next_temp(wfn)
  emit_instruction(wfn, {op: :nanbox_int, temp: temp, temp_masked: temp_masked, raw: raw_reg})
  typed_value(:i64, temp)

-> nanunbox_float_emit(wfn, boxed_reg)
  temp_bits = next_temp(wfn)
  temp = next_temp(wfn)
  emit_instruction(wfn, {op: :nanunbox_float, temp: temp, temp_bits: temp_bits, boxed: boxed_reg})
  temp

-> nanbox_float_emit(wfn, raw_reg)
  temp_bits = next_temp(wfn)
  temp = next_temp(wfn)
  emit_instruction(wfn, {op: :nanbox_float, temp: temp, temp_bits: temp_bits, raw: raw_reg})
  typed_value(:i64, temp)

-> ensure_raw_f64(wfn, tv)
  if tv[:type] == :raw_f64
    return tv[:value]
  if tv[:type] == :raw_f32
    temp = next_temp(wfn)
    emit_instruction(wfn, {op: :fpext_f32_f64, temp: temp, value: tv[:value]})
    return temp
  src_type = raw_machine_source_type(tv)
  if src_type != nil && tv[:type] in (:raw_int :raw_i64 :raw_u64 :raw_i128 :raw_u128 :char)
    temp = next_temp(wfn)
    emit_instruction(wfn, {op: machine_int_to_f64_op(src_type), temp: temp, value: tv[:value]})
    return temp
  # Fallback: a boxed WValue (`:i64`) whose concrete numeric kind isn't known at
  # compile time — a boxed double, a Decimal literal (bare `3.5` parses as a
  # Decimal, so `x ## f64` and mixed float/decimal expressions carry Decimals
  # here), or a boxed Integer. A bare bitcast-unbox is correct ONLY for a genuine
  # boxed double; for a Decimal/Int it reinterprets unrelated bits as an IEEE
  # double (garbage — the root of the `## f64 += 3.5`, `f64 > 3.0`, `f64 + 3.5`
  # bugs). w_num_to_f64 dispatches on the runtime type and converts each kind
  # correctly. (`## f64` hot loops keep their accumulator as :raw_f64 and never
  # reach this fallback, so the extra call only lands at boxed-value boundaries.)
  temp = next_temp(wfn)
  emit_instruction(wfn, {op: :call_num_to_f64, temp: temp, value: ensure_i64_value(wfn, tv)})
  temp

-> ensure_raw_f32(wfn, tv)
  if tv[:type] == :raw_f32
    return tv[:value]
  raw64 = ensure_raw_f64(wfn, tv)
  temp = next_temp(wfn)
  emit_instruction(wfn, {op: :fptrunc_f64_f32, temp: temp, value: raw64})
  temp

-> raw_float_bits_i64(wfn, tv, elem_type)
  if elem_type == :typed_array_f32
    raw32 = ensure_raw_f32(wfn, tv)
    bits32 = next_temp(wfn)
    bits64 = next_temp(wfn)
    emit_instruction(wfn, {op: :bitcast_f32_i32, temp: bits32, value: raw32})
    emit_instruction(wfn, {op: :zext_i32_i64, temp: bits64, value: bits32})
    return bits64
  if elem_type == :typed_array_bf16
    raw32 = ensure_raw_f32(wfn, tv)
    bits32 = next_temp(wfn)
    bits64 = next_temp(wfn)
    lsb_shift = next_temp(wfn)
    lsb = next_temp(wfn)
    bias = next_temp(wfn)
    rounded = next_temp(wfn)
    bf16 = next_temp(wfn)
    emit_instruction(wfn, {op: :bitcast_f32_i32, temp: bits32, value: raw32})
    emit_instruction(wfn, {op: :zext_i32_i64, temp: bits64, value: bits32})
    emit_instruction(wfn, {op: :lshr_i64, temp: lsb_shift, lhs: bits64, rhs: "16"})
    emit_instruction(wfn, {op: :and_i64, temp: lsb, lhs: lsb_shift, rhs: "1"})
    emit_instruction(wfn, {op: :add_i64, temp: bias, lhs: lsb, rhs: "32767"})
    emit_instruction(wfn, {op: :add_i64, temp: rounded, lhs: bits64, rhs: bias})
    emit_instruction(wfn, {op: :lshr_i64, temp: bf16, lhs: rounded, rhs: "16"})
    return bf16
  if elem_type == :typed_array_f16
    # f32 → half is a real rounding conversion (fcvt), unlike bf16's
    # truncate-with-RNE bit trick; round-trip the bits through LLVM half.
    raw32 = ensure_raw_f32(wfn, tv)
    half = next_temp(wfn)
    bits16 = next_temp(wfn)
    bits64 = next_temp(wfn)
    emit_instruction(wfn, {op: :fptrunc_f32_f16, temp: half, value: raw32})
    emit_instruction(wfn, {op: :bitcast_f16_i16, temp: bits16, value: half})
    emit_instruction(wfn, {op: :zext_i16_i64, temp: bits64, value: bits16})
    return bits64
  raw64 = ensure_raw_f64(wfn, tv)
  bits = next_temp(wfn)
  emit_instruction(wfn, {op: :bitcast_f64_i64, temp: bits, value: raw64})
  bits

-> raw_float_from_bits_i64(wfn, bits, elem_type)
  if elem_type == :typed_array_f32
    bits32 = next_temp(wfn)
    raw32 = next_temp(wfn)
    emit_instruction(wfn, {op: :trunc_i64_i32, temp: bits32, value: bits})
    emit_instruction(wfn, {op: :bitcast_i32_f32, temp: raw32, value: bits32})
    return typed_value(:raw_f32, raw32)
  if elem_type == :typed_array_bf16
    shifted = next_temp(wfn)
    bits32 = next_temp(wfn)
    raw32 = next_temp(wfn)
    emit_instruction(wfn, {op: :shl_i64, temp: shifted, lhs: bits, rhs: "16"})
    emit_instruction(wfn, {op: :trunc_i64_i32, temp: bits32, value: shifted})
    emit_instruction(wfn, {op: :bitcast_i32_f32, temp: raw32, value: bits32})
    return typed_value(:raw_f32, raw32)
  if elem_type == :typed_array_f16
    bits16 = next_temp(wfn)
    half = next_temp(wfn)
    raw32 = next_temp(wfn)
    emit_instruction(wfn, {op: :trunc_i64_i16, temp: bits16, value: bits})
    emit_instruction(wfn, {op: :bitcast_i16_f16, temp: half, value: bits16})
    emit_instruction(wfn, {op: :fpext_f16_f32, temp: raw32, value: half})
    return typed_value(:raw_f32, raw32)
  raw64 = next_temp(wfn)
  emit_instruction(wfn, {op: :bitcast_i64_f64, temp: raw64, value: bits})
  typed_value(:raw_f64, raw64)

# -- Unary ops --

-> lower_unary_op(ctx, node)
  wfn = ctx[:func]
  if node.op == :DEREF
    return lower_expression(ctx, node.operand)

  if node.operand != nil && ast_kind(node.operand) == :int
    if node.op == :MINUS
      # Fold into a negated integer literal and reuse lower_int, so the
      # i48/i64/BigInt promotion (no truncation) applies to `-<literal>` too.
      opraw = node.operand.raw
      neg_raw = opraw
      if opraw != nil
        neg_raw = "-" + opraw
      return lower_int(ctx, Tungsten:AST:Int.new(0 - node.operand.value, node.operand.format, neg_raw))
    if node.op == :PLUS
      return lower_int(ctx, node.operand)

  # Integer-scalar `-x` desugars to `0 - x` so the binary machinery's
  # native/raw/guarded arms apply — the generic path below boxes the
  # operand and calls the polymorphic w_neg, measured 4-9x slower in
  # tight loops (worst on ## i32). Scope is deliberate:
  #   - machine ints and boxed :int only. The guarded/binary w_sub
  #     fallback matches w_neg's promotion semantics exactly.
  #   - floats KEEP w_neg: `0.0 - x` turns +0.0 into +0.0 where negation
  #     must produce -0.0.
  #   - bigints KEEP w_neg: it is the O(1) tag-flip alias; `0 - x` would
  #     route w_sub's promotion arm and allocate.
  #   - objects KEEP w_neg: they dispatch `-@`; `0 - obj` has no
  #     reverse-operand dispatch.
  if node.op == :MINUS && node.operand != nil
    ut = infer_type(node.operand, ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)
    if ut != nil && !is_bigint_type(ut) && (ut == :int || ut in (:raw_int :raw_i64 :raw_u64) || is_machine_int_type(ut))
      return lower_binary_op(ctx, Tungsten:AST:BinaryOp.new(Tungsten:AST:Int.new(0, nil, "0"), :MINUS, node.operand))

  operand = lower_expression(ctx, node.operand)
  operand_reg = ensure_i64_value(wfn, operand)

  if node.op == :MINUS
    temp = next_temp(wfn)
    emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_neg", args: [operand_reg]})
    return typed_value(:i64, temp)

  # Fallback for unknown unary ops
  typed_value(:i64, operand_reg)

# -- Short-circuit boolean --

# Flatten a right-associated OR tree into a flat arm list.
# Returns nil if the node isn't a pure :or tree.
-> flatten_or_chain(node)
  if node == nil || ast_kind(node) != :or
    return nil
  arms = []
  flatten_or_into(node, arms)
  arms

-> flatten_or_into(node, arms)
  if ast_kind(node) == :or
    flatten_or_into(node.left, arms)
    flatten_or_into(node.right, arms)
  else
    arms.push(node)

# Structural equality over AST hashes for the Phase 8 homogeneity
# check. Only handles the node shapes that the peephole can realistically
# hoist: vars, ivars, cvars, simple binary ops, calls with pure args,
# and literals. Returns true if both nodes are the same expression.
-> ast_structurally_equal?(a, b)
  if a == nil || b == nil
    return a == b
  if ast_kind(a) != ast_kind(b)
    return false
  t = ast_kind(a)
  if t == :var
    return a.name == b.name
  if t in (:ivar :cvar :gvar)
    return a.name == b.name
  if t == :int
    return a.value == b.value
  if t == :string
    return a.value == b.value
  if t == :binary_op
    if a.op != b.op
      return false
    if !ast_structurally_equal?(a.left, b.left)
      return false
    return ast_structurally_equal?(a.right, b.right)
  if t == :unary_op
    if a.op != b.op
      return false
    return ast_structurally_equal?(a.operand, b.operand)
  if t == :call
    if a.name != b.name
      return false
    if !ast_structurally_equal?(a.receiver, b.receiver)
      return false
    args_a = a.args
    args_b = b.args
    if args_a == nil || args_b == nil
      return args_a == args_b
    if args_a.size() != args_b.size()
      return false
    i = 0
    while i < args_a.size()
      if !ast_structurally_equal?(args_a[i], args_b[i])
        return false
      i += 1
    return true
  # Conservative default: unknown shapes are not equal
  false

# Check whether a flat arm list is `lhs == c1, lhs == c2, ..., lhs == ck`
# with structurally identical lhs across all arms and integer-literal rhs
# that fit in the 48-bit nanbox int range. Returns {lhs, consts} if
# homogeneous, nil otherwise.
-> homogeneous_eq_chain?(arms)
  if arms == nil || arms.size() < 3
    return nil
  first = arms[0]
  if ast_kind(first) != :binary_op || first.op != :EQ
    return nil
  if first.right == nil || ast_kind(first.right) != :int
    return nil
  first_val = first.right.value
  if first_val > 140737488355327 || first_val < -140737488355328
    return nil
  shared_lhs = first.left
  consts = [first_val]
  i = 1
  while i < arms.size()
    arm = arms[i]
    if ast_kind(arm) != :binary_op || arm.op != :EQ
      return nil
    if arm.right == nil || ast_kind(arm.right) != :int
      return nil
    val = arm.right.value
    if val > 140737488355327 || val < -140737488355328
      return nil
    if !ast_structurally_equal?(arm.left, shared_lhs)
      return nil
    consts.push(val)
    i += 1
  {lhs: shared_lhs, consts: consts}

-> lower_short_circuit(ctx, node, kind)
  wfn = ctx[:func]

  # Phase 8 peephole: homogeneous OR chain → hoisted LHS chain.
  # Detects `a == c1 || a == c2 || a == c3 [|| ...]` with structurally
  # identical LHS and integer-constant RHS, and lowers to a hoisted
  # form where the LHS is evaluated exactly once. This fixes a
  # correctness issue in Phase 6's naive in-operator lowering where
  # a side-effecting LHS (e.g., a method call) would be evaluated
  # multiple times.
  #
  # A future Phase 8b commit (gated on Phase 2's raw i64 default) will
  # replace the hoisted comparison chain with a single bitmap test on
  # the raw integer, for the common case where the constants fit in
  # a u64 window. The recognition machinery (flatten_or_chain,
  # ast_structurally_equal?, homogeneous_eq_chain?) is reused.
  if kind == :or
    arms = flatten_or_chain(node)
    if arms != nil
      match = homogeneous_eq_chain?(arms)
      if match != nil
        return lower_hoisted_eq_chain(ctx, match[:lhs], match[:consts])

  # Allocate result slot before any branching
  result_ptr = ensure_var_slot(wfn, "__sc_result." + next_label(wfn, "sc"))

  # Evaluate LHS
  lhs = lower_expression(ctx, node.left)

  # If LHS is already an i1 (inline comparison), use it for the branch
  # decision directly. We still need to nanbox it once for the result
  # slot because `a && b` / `a || b` can return the raw LHS value — but
  # a bool-returning LHS always stores as `true`/`false`, which is
  # exactly what nanbox_bool emits for an i1.
  if lhs[:type] == :i1
    lhs_bool = lhs[:value]
    lhs_reg = next_temp(wfn)
    emit_instruction(wfn, {op: :nanbox_bool, temp: lhs_reg, value: lhs_bool})
  else
    lhs_reg = ensure_i64_value(wfn, lhs)
    lhs_bool = next_temp(wfn)
    emit_instruction(wfn, {op: :truthy_inline, temp: lhs_bool, value: lhs_reg})

  # Store LHS as default result (used if we short-circuit)
  emit_instruction(wfn, {op: :store_i64, value: lhs_reg, ptr: result_ptr})

  rhs_label = next_label(wfn, "sc.rhs")
  end_label = next_label(wfn, "sc.end")

  if kind == :and
    # AND: truthy LHS → evaluate RHS; falsy → short-circuit with LHS
    emit_instruction(wfn, {op: :cond_br, cond: lhs_bool, then_label: rhs_label, else_label: end_label})
  else
    # OR: truthy LHS → short-circuit with LHS; falsy → evaluate RHS
    emit_instruction(wfn, {op: :cond_br, cond: lhs_bool, then_label: end_label, else_label: rhs_label})

  # RHS block: evaluate and overwrite result
  start_block(wfn, rhs_label)
  rhs = lower_expression(ctx, node.right)
  rhs_reg = ensure_i64_value(wfn, rhs)
  emit_instruction(wfn, {op: :store_i64, value: rhs_reg, ptr: result_ptr})
  emit_instruction(wfn, {op: :br, label: end_label})

  # End block: load merged result
  start_block(wfn, end_label)
  result = next_temp(wfn)
  emit_instruction(wfn, {op: :load_i64, temp: result, ptr: result_ptr})
  typed_value(:i64, result)

-> lower_not(ctx, node)
  wfn = ctx[:func]
  operand = lower_expression(ctx, node.operand)

  # Inline comparisons already produce i1 — skip the i1 → nanbox_bool →
  # truthy_inline round trip and feed the i1 straight into not_i1.
  if operand[:type] == :i1
    bool_val = operand[:value]
  else
    operand_reg = ensure_i64_value(wfn, operand)
    bool_val = next_temp(wfn)
    emit_instruction(wfn, {op: :truthy_inline, temp: bool_val, value: operand_reg})

  negated = next_temp(wfn)
  emit_instruction(wfn, {op: :not_i1, temp: negated, value: bool_val})
  # Return the i1 directly so consumers that can branch on i1 (if,
  # while, elsif, short-circuit) avoid another round trip. Consumers
  # that need a WValue will nanbox via ensure_i64_value.
  typed_value(:i1, negated)

# Phase 8 dispatch: emit a homogeneous equality chain with a single
# evaluation of the LHS. All comparisons and OR reductions happen in
# the current basic block as a straight-line sequence — no branching,
# no multi-block control flow. This is safe because every comparison
# is a constant-rhs icmp with no side effects, so we can always
# evaluate all of them and OR the i1 results. LLVM's optimizer will
# typically lift this to a switch/bitmap at -O3 based on the constant
# spread.
#
# Keeping everything in one block sidesteps the store-load forwarding
# issue where a load-temp substitution from the entry block wouldn't
# propagate to branched-to iteration blocks.
-> lower_hoisted_eq_chain(ctx, lhs_node, consts)
  wfn = ctx[:func]

  # Evaluate the LHS ONCE.
  lhs_tv = lower_expression(ctx, lhs_node)
  lhs_reg = ensure_i64_value(wfn, lhs_tv)

  # Emit an icmp for each constant, collecting the i1 results.
  cmp_temps = []
  i = 0
  n = consts.size()
  while i < n
    c = consts[i]
    c_raw = c.to_i()
    # Compile-time nanboxed form of the integer constant c.
    # Range already checked in homogeneous_eq_chain? — all consts
    # here fit in the signed 48-bit range.
    nanboxed = (c_raw & 281474976710655) | -1688849860263936
    eq = next_temp(wfn)
    emit_instruction(wfn, {op: :icmp_i64, temp: eq, pred: "eq", lhs: lhs_reg, rhs: nanboxed.to_s()})
    cmp_temps.push(eq)
    i += 1

  # Left-fold OR over the i1 results.
  acc = cmp_temps[0]
  j = 1
  while j < cmp_temps.size()
    new_acc = next_temp(wfn)
    emit_instruction(wfn, {op: :or_i1, temp: new_acc, lhs: acc, rhs: cmp_temps[j]})
    acc = new_acc
    j += 1

  # Box the final i1 result to a wvalue bool.
  boxed = next_temp(wfn)
  emit_instruction(wfn, {op: :nanbox_bool, temp: boxed, value: acc})
  typed_value(:i64, boxed)

# `lhs in (a b c)` — membership test.
#
# Character tests lower to a single raw LHS plus straight-line icmps. Plain
# integer/hex membership desugars to a flat OR chain so it follows the same
# WValue peephole path as `a == b || a == c || ...`.
#
# Single-element form is rewritten to a plain == for clarity.
-> lower_in_test(ctx, node)
  lhs_node = node.lhs
  elements = node.elements

  if elements.size() == 1
    eq_node = Tungsten:AST:BinaryOp.new(lhs_node, :EQ, elements[0])
    return lower_expression(ctx, eq_node)

  lhs_type = infer_type(lhs_node, ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)
  if lhs_type == :char
    machine_type = lhs_type
    all_ints = true
    i = 0
    while i < elements.size()
      et = infer_type(elements[i], ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)
      if !is_integer_like_type(et)
        all_ints = false
        break
      machine_type = machine_int_result_type(machine_type, et)
      if machine_type == :char
        machine_type = :i64
      i += 1

    if all_ints && machine_type != nil
      lhs_raw = lower_machine_int_expression(ctx, lhs_node, machine_type)
      acc = nil
      i = 0
      while i < elements.size()
        rhs_raw = lower_machine_int_expression(ctx, elements[i], machine_type)
        cmp = next_temp(ctx[:func])
        emit_instruction(ctx[:func], {op: machine_cmp_op(machine_type), temp: cmp, pred: "eq", lhs: lhs_raw, rhs: rhs_raw})
        if acc == nil
          acc = cmp
        else
          merged = next_temp(ctx[:func])
          emit_instruction(ctx[:func], {op: :or_i1, temp: merged, lhs: acc, rhs: cmp})
          acc = merged
        i += 1
      return typed_value(:i1, acc)

  # Build the OR chain bottom-up: a == e0 || a == e1 || a == e2 ...
  # Note: the LHS is duplicated structurally at each arm. A following
  # Phase 8 peephole will detect the homogeneous chain and hoist the
  # LHS to a single temp before the dispatch.
  chain = Tungsten:AST:BinaryOp.new(lhs_node, :EQ, elements[0])
  i = 1
  while i < elements.size()
    arm = Tungsten:AST:BinaryOp.new(lhs_node, :EQ, elements[i])
    chain = Tungsten:AST:Or.new(chain, arm)
    i += 1
  lower_expression(ctx, chain)

# ---------------------------------------------------------------------------
# Fused elementwise lowering with automatic backend selection.
#
# A tree of float elementwise ops — `(x .* a .+ b).sin() .+ c` — historically
# lowered to one runtime kernel call per node, each allocating a full
# temporary array. When every array leaf is statically f64[] (or f32[], all
# one type) and every scalar leaf is a float/int, the whole tree collapses
# into ONE loop: load leaves, apply raw fadd/fmul/…/libm ops, store. No
# temporaries, no boxing, and the loop body is plain scalar IR that LLVM's
# vectorizer can work on (-fveclib turns the sin into _simd_sin_d2).
#
# The loop body is ALSO outlined into a worker function
#     i64 __w_fuse_worker_N(i64 blk, i64 lo, i64 hi)
# and the site gates on runtime size (w_fused_should_mt): below the measured
# threshold the loop runs inline single-core; at/above it the runtime
# partitions [0, n) across OS threads (w_fused_parallel_run). Thresholds are
# from the size sweep in doc/scientific-computing/fusion.md; TUNGSTEN_FUSED_*
# env vars override. The arg block is an i64[] of
#     [out WValue, leaf-array WValues..., scalar f64 bit patterns...]
#
# Anything outside the fusable shape returns nil and falls back to the
# kernel path, so kernel semantics are preserved exactly: lhs must be
# array-valued, rhs arrays must match the lhs size (same raise text via
# w_elementwise_size_check), scalars broadcast, int/mixed-dtype arrays keep
# kernels.
#
# Fusion triggers only when it wins: a libm node in the tree (vector sin
# beats a scalar kernel loop) or ≥2 elementwise ops (temporaries saved).
# A single bare DOT op keeps the already-SIMD runtime kernel.

# Classify `node` into a fusion spec tree, or nil if not fusable.
#   {cls: :dot,    op:, left:, right:, odt:, ops:, libm:}
#   {cls: :libm,   name:, recv:, odt:, ops:, libm:}
#   {cls: :arr,    node:, etype:, odt:}   — f64[] / f32[] leaf
#   {cls: :scalar, node:}                 — float/int scalar leaf
# odt is the node's OUTPUT dtype under kernel semantics: a DOT op inherits
# its lhs dtype (array_elementwise_into: out ebits = lhs ebits), and the
# libm array methods always produce f64 (array_map_f64 allocates -64
# regardless of input). Leaves may mix f32/f64 — kernels read either into
# doubles — so computation is f64 throughout; only loads and the final
# store are dtype-specific.
-> fuse_ew_analyze(ctx, node)
  k = ast_kind(node)
  if k == :binary_op && node.op in (:DOT_PLUS :DOT_MINUS :DOT_STAR :DOT_SLASH)
    l = fuse_ew_analyze(ctx, node.left)
    # Kernel semantics: the lhs of a DOT op must be array-valued.
    if l == nil || l[:cls] == :scalar
      return nil
    r = fuse_ew_analyze(ctx, node.right)
    if r == nil
      return nil
    return {cls: :dot, op: node.op, left: l, right: r, odt: l[:odt], ops: l[:ops] + r[:ops] + 1, libm: l[:libm] + r[:libm]}
  if k == :call && node.receiver != nil && node.name != nil && node.name in ("sin" "cos" "sqrt" "exp" "log" "tan")
    argc = 0
    if node.args != nil
      argc = node.args.size()
    if argc == 0
      rcv = fuse_ew_analyze(ctx, node.receiver)
      # Scalar receivers (Float#sin etc.) keep normal dispatch.
      if rcv != nil && rcv[:cls] != :scalar
        return {cls: :libm, name: node.name, recv: rcv, odt: :f64, ops: rcv[:ops], libm: rcv[:libm] + 1}
    return nil
  t = infer_type(node, ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)
  if t == :typed_array_f64
    return {cls: :arr, node: node, etype: :f64, odt: :f64, ops: 0, libm: 0}
  if t == :typed_array_f32
    return {cls: :arr, node: node, etype: :f32, odt: :f32, ops: 0, libm: 0}
  if t == :float || t == :f64 || is_integer_like_type(t)
    return {cls: :scalar, node: node, ops: 0, libm: 0}
  nil

# Per-element-type op/constant tables.
-> fuse_ew_elems_ptr_op(etype)
  etype == :f32 ? :ta_f32_elems_ptr : :ta_f64_elems_ptr

-> fuse_ew_load_op(etype)
  etype == :f32 ? :load_f32_at : :load_f64_at

-> fuse_ew_store_op(etype)
  etype == :f32 ? :store_f32_at : :store_f64_at

-> fuse_ew_alloc_bits(etype)
  etype == :f32 ? "-32" : "-64"

# Lower the tree's leaves once, in source (DFS in-order) evaluation order —
# the same order the unfused kernel path would evaluate them. Array leaves
# get their boxed reg stashed on the spec and are collected into `arrs`;
# scalar leaves are hoisted to a raw f64 and collected into `scls`.
-> fuse_ew_lower_leaves(ctx, spec, arrs, scls)
  wfn = ctx[:func]
  cls = spec[:cls]
  if cls == :arr
    tv = lower_expression(ctx, spec[:node])
    spec[:reg] = ensure_i64_value(wfn, tv)
    spec[:ai] = arrs.size()
    arrs.push(spec)
    return nil
  if cls == :scalar
    tv = lower_expression(ctx, spec[:node])
    spec[:raw] = ensure_raw_f64(wfn, tv)
    spec[:sj] = scls.size()
    scls.push(spec)
    return nil
  if cls == :libm
    fuse_ew_lower_leaves(ctx, spec[:recv], arrs, scls)
    return nil
  fuse_ew_lower_leaves(ctx, spec[:left], arrs, scls)
  fuse_ew_lower_leaves(ctx, spec[:right], arrs, scls)
  nil

# Emit the per-element scalar computation for one loop iteration.
-> fuse_ew_emit_scalar(ctx, spec)
  wfn = ctx[:func]
  cls = spec[:cls]
  if cls == :arr
    return spec[:cur]
  if cls == :scalar
    return spec[:raw]
  if cls == :libm
    v = fuse_ew_emit_scalar(ctx, spec[:recv])
    temp = next_temp(wfn)
    emit_instruction(wfn, {op: :call_libm_f64, temp: temp, name: spec[:name], value: v})
    return temp
  l = fuse_ew_emit_scalar(ctx, spec[:left])
  r = fuse_ew_emit_scalar(ctx, spec[:right])
  fop = :fadd_f64
  if spec[:op] == :DOT_MINUS
    fop = :fsub_f64
  elsif spec[:op] == :DOT_STAR
    fop = :fmul_f64
  elsif spec[:op] == :DOT_SLASH
    fop = :fdiv_f64
  temp = next_temp(wfn)
  emit_instruction(wfn, {op: fop, temp: temp, lhs: l, rhs: r, fp_flags: float_inst_flags(ctx)})
  temp

# Emit the [lo, hi) element loop into ctx[:func]. arrs[k][:base] must hold
# element-base pointers valid in that function; scalar specs must have
# [:raw] set to in-function raw f64 temps. Computation is f64 throughout —
# f32 arrays fpext on load and fptrunc on store, matching the runtime
# kernels (which read f32 elements into doubles).
#
# ewsid: fusion-site id for scoped no-alias metadata, or nil to skip. On the
# fresh-output path the destination is a w_array_new_uninit_sized malloc that
# cannot alias ANY source array, but TBAA can't say so (all elements share
# warray_data), so -O3 emits per-source runtime overlap checks plus a
# duplicated scalar loop. Stamping the store `!alias.scope` and the source
# loads `!noalias` (one distinct scope per fusion site — emitter
# ewscope_md_defs) removes the memchecks. The `## reuse` path passes nil:
# its output buffer persists across calls and the freshness proof is the
# user's assertion, not the compiler's.
-> fuse_ew_emit_range_loop(ctx, spec, arrs, out_base, lo_val, hi_val, odt, ewsid = nil)
  wfn = ctx[:func]
  cond_label = next_label(wfn, "fuse.cond")
  body_label = next_label(wfn, "fuse.body")
  end_label = next_label(wfn, "fuse.end")
  i_slot = ensure_var_slot(wfn, "__fuse_i." + cond_label, "i64")
  emit_instruction(wfn, {op: :store_i64, value: lo_val, ptr: i_slot})
  emit_instruction(wfn, {op: :br, label: cond_label})
  start_block(wfn, cond_label)
  iv = next_temp(wfn)
  emit_instruction(wfn, {op: :load_i64, temp: iv, ptr: i_slot})
  cmp = next_temp(wfn)
  emit_instruction(wfn, {op: :icmp_i64, temp: cmp, pred: "slt", lhs: iv, rhs: hi_val})
  emit_instruction(wfn, {op: :cond_br, cond: cmp, then_label: body_label, else_label: end_label})
  start_block(wfn, body_label)
  bi_v = next_temp(wfn)
  emit_instruction(wfn, {op: :load_i64, temp: bi_v, ptr: i_slot})
  ai = 0
  while ai < arrs.size()
    cur = next_temp(wfn)
    emit_instruction(wfn, {op: fuse_ew_load_op(arrs[ai][:etype]), temp: cur, ptr: arrs[ai][:base], index: bi_v, ewscope: ewsid})
    arrs[ai][:cur] = cur
    ai += 1
  result_raw = fuse_ew_emit_scalar(ctx, spec)
  stw = next_temp(wfn)
  emit_instruction(wfn, {op: fuse_ew_store_op(odt), temp: stw, ptr: out_base, index: bi_v, value: result_raw, ewscope: ewsid})
  nxt = next_temp(wfn)
  emit_instruction(wfn, {op: :add_i64, temp: nxt, lhs: bi_v, rhs: "1"})
  emit_instruction(wfn, {op: :store_i64, value: nxt, ptr: i_slot})
  emit_instruction(wfn, {op: :br, label: cond_label})
  start_block(wfn, end_label)
  nil

# Store one i64 value into the arg block at a literal index.
-> fuse_ew_block_store(wfn, blk_reg, idx_str, val_reg)
  scratch = []
  si = 0
  while si < 10
    scratch.push(next_temp(wfn))
    si += 1
  stw = next_temp(wfn)
  emit_instruction(wfn, {op: :typed_array_set_inline, temp: stw, arr: blk_reg, idx: idx_str, idx_raw: true, value: val_reg, s: scratch, bits: 64, signed: true})
  nil

# ---- GPU offload (arithmetic-only f32 trees) ----
# The libm array methods promote to f64 output (kernel semantics), and MSL
# has no double at all, so only pure-arithmetic all-f32 trees are
# GPU-eligible. Their MSL kernel is generated here at compile time; the
# runtime (w_fused_gpu_run in metal.m) compiles it once per site, keeps
# cached buffers, and only fires above TUNGSTEN_FUSED_GPU_MIN elements.

-> fuse_ew_gpu_eligible?(spec, arrs)
  if spec[:odt] != :f32
    return false
  if spec[:libm] != 0
    return false
  ai = 0
  while ai < arrs.size()
    if arrs[ai][:etype] != :f32
      return false
    ai += 1
  true

-> fuse_ew_msl_expr(spec)
  cls = spec[:cls]
  if cls == :arr
    return "a" + spec[:ai].to_s() + "\[i]"
  if cls == :scalar
    return "s\[" + spec[:sj].to_s() + "]"
  if cls == :libm
    return spec[:name] + "(" + fuse_ew_msl_expr(spec[:recv]) + ")"
  op_str = " + "
  if spec[:op] == :DOT_MINUS
    op_str = " - "
  elsif spec[:op] == :DOT_STAR
    op_str = " * "
  elsif spec[:op] == :DOT_SLASH
    op_str = " / "
  "(" + fuse_ew_msl_expr(spec[:left]) + op_str + fuse_ew_msl_expr(spec[:right]) + ")"

-> fuse_ew_msl_kernel(spec, n_arrs)
  out = StringBuffer(640)
  out << "#include <metal_stdlib>\nusing namespace metal;\nkernel void fuse("
  k = 0
  while k < n_arrs
    out << "device const float* a" + k.to_s() + " \[\[buffer(" + k.to_s() + ")]], "
    k += 1
  out << "device float* outb \[\[buffer(" + n_arrs.to_s() + ")]], "
  out << "constant float* s \[\[buffer(" + (n_arrs + 1).to_s() + ")]], "
  out << "constant uint& n \[\[buffer(" + (n_arrs + 2).to_s() + ")]], "
  out << "uint i \[\[thread_position_in_grid]]) {\n"
  out << "  if (i < n) outb\[i] = " + fuse_ew_msl_expr(spec) + ";\n}\n"
  out.to_s()

# Build the outlined worker for the parallel path. The spec's per-leaf
# bindings ([:base]/[:raw]) are temporarily rebound to worker-local temps
# (loaded from the arg block) and restored afterwards so the site's inline
# path still sees its own temps.
-> fuse_ew_build_worker(ctx, spec, arrs, scls, odt, sid, ewsid = nil)
  mod = ctx[:mod]
  wname = "__w_fuse_worker_" + sid.to_s()
  wfn2 = build_function(wname, ["__fw_blk", "__fw_lo", "__fw_hi"], "i64", false, [])
  wfn2[:source_kind] = :fn_def
  wfn2[:source_method] = wname
  wfn2[:source_path] = ctx[:source_path]
  wfn2[:source_line] = 0
  mod[:functions].push(wfn2)

  saved_raw = []
  sj = 0
  while sj < scls.size()
    saved_raw.push(scls[sj][:raw])
    sj += 1
  saved_base = []
  ai = 0
  while ai < arrs.size()
    saved_base.push(arrs[ai][:base])
    ai += 1

  blk_ptr = next_temp(wfn2)
  emit_instruction(wfn2, {op: :inttoptr_i64, temp: blk_ptr, value: "%__fw_blk"})
  out_wv = next_temp(wfn2)
  emit_instruction(wfn2, {op: :load_i64_at, temp: out_wv, ptr: blk_ptr, index: "0"})
  ai = 0
  while ai < arrs.size()
    wv = next_temp(wfn2)
    emit_instruction(wfn2, {op: :load_i64_at, temp: wv, ptr: blk_ptr, index: (1 + ai).to_s()})
    base = next_temp(wfn2)
    emit_instruction(wfn2, {op: fuse_ew_elems_ptr_op(arrs[ai][:etype]), temp: base, value: wv})
    arrs[ai][:base] = base
    ai += 1
  sj = 0
  while sj < scls.size()
    raw = next_temp(wfn2)
    emit_instruction(wfn2, {op: :load_f64_at, temp: raw, ptr: blk_ptr, index: (1 + arrs.size() + sj).to_s()})
    scls[sj][:raw] = raw
    sj += 1
  out_base = next_temp(wfn2)
  emit_instruction(wfn2, {op: fuse_ew_elems_ptr_op(odt), temp: out_base, value: out_wv})

  saved_func = ctx[:func]
  ctx[:func] = wfn2
  fuse_ew_emit_range_loop(ctx, spec, arrs, out_base, "%__fw_lo", "%__fw_hi", odt, ewsid)
  ctx[:func] = saved_func

  emit_instruction(wfn2, {op: :ret_i64, value: "0"})
  finalize_function(wfn2)

  sj = 0
  while sj < scls.size()
    scls[sj][:raw] = saved_raw[sj]
    sj += 1
  ai = 0
  while ai < arrs.size()
    arrs[ai][:base] = saved_base[ai]
    ai += 1
  wname

# Entry point: fuse `node` if it is a worthwhile elementwise tree.
# Returns the result typed_value, or nil to fall back to the kernel path.
-> try_fuse_elementwise(ctx, node)
  spec = fuse_ew_analyze(ctx, node)
  if spec == nil
    return nil
  if spec[:cls] != :dot && spec[:cls] != :libm
    return nil
  if spec[:libm] == 0 && spec[:ops] < 2
    return nil
  odt = spec[:odt]
  if odt == nil
    return nil
  wfn = ctx[:func]
  arrs = []
  scls = []
  fuse_ew_lower_leaves(ctx, spec, arrs, scls)
  if arrs.size() == 0
    return nil
  arr0 = arrs[0]
  size_reg = next_temp(wfn)
  emit_instruction(wfn, {op: :ta_size_raw, temp: size_reg, value: arr0[:reg]})
  ai = 1
  while ai < arrs.size()
    chk = next_temp(wfn)
    emit_instruction(wfn, {op: :call_direct_i64, temp: chk, name: "w_elementwise_size_check", args: [arr0[:reg], arrs[ai][:reg]]})
    ai += 1
  out_reg = next_temp(wfn)
  # `y = <fused expr> ## reuse` — per-site persistent output buffer (same
  # user-assertion contract as `f64[n] ## reuse`). A stable output base
  # also lets the GPU tier cache its zero-copy wrap across executions.
  if ast_get(node, :reuse_safe) == true
    rs_id = ctx[:mod][:next_reuse_site]
    ctx[:mod][:next_reuse_site] = rs_id + 1
    rs_name = "reuse.site." + rs_id.to_s()
    ctx[:mod][:reuse_sites].push(rs_name)
    emit_instruction(wfn, {op: :call_fused_out_reuse, temp: out_reg, slot: rs_name, bits: fuse_ew_alloc_bits(odt), cap: size_reg})
  else
    emit_instruction(wfn, {op: :call_direct_i64, temp: out_reg, name: "w_array_new_uninit_sized", args: [fuse_ew_alloc_bits(odt), size_reg]})

  sid = ctx[:mod][:next_fuse_site]
  if sid == nil
    sid = 0
  ctx[:mod][:next_fuse_site] = sid + 1
  # Scoped no-alias metadata only where the output is THIS SITE's fresh
  # malloc; a `## reuse` buffer persists across calls, so skip it there.
  ewsid = nil
  if ast_get(node, :reuse_safe) != true
    ewsid = sid
  worker_name = fuse_ew_build_worker(ctx, spec, arrs, scls, odt, sid, ewsid)

  mt_label = next_label(wfn, "fuse.mt")
  st_label = next_label(wfn, "fuse.st")
  done_label = next_label(wfn, "fuse.done")
  mt_reg = next_temp(wfn)
  emit_instruction(wfn, {op: :call_direct_i64, temp: mt_reg, name: "w_fused_should_mt", args: [size_reg]})
  mt_cmp = next_temp(wfn)
  emit_instruction(wfn, {op: :icmp_i64, temp: mt_cmp, pred: "ne", lhs: mt_reg, rhs: "0"})
  emit_instruction(wfn, {op: :cond_br, cond: mt_cmp, then_label: mt_label, else_label: st_label})

  start_block(wfn, mt_label)
  nslots = 1 + arrs.size() + scls.size()
  blk_reg = next_temp(wfn)
  emit_instruction(wfn, {op: :call_direct_i64, temp: blk_reg, name: "w_array_zeros", args: ["64", nslots.to_s()]})
  fuse_ew_block_store(wfn, blk_reg, "0", out_reg)
  ai = 0
  while ai < arrs.size()
    fuse_ew_block_store(wfn, blk_reg, (1 + ai).to_s(), arrs[ai][:reg])
    ai += 1
  sj = 0
  while sj < scls.size()
    bits = next_temp(wfn)
    emit_instruction(wfn, {op: :bitcast_f64_i64, temp: bits, value: scls[sj][:raw]})
    fuse_ew_block_store(wfn, blk_reg, (1 + arrs.size() + sj).to_s(), bits)
    sj += 1
  blk_addr = next_temp(wfn)
  emit_instruction(wfn, {op: :ta_data_addr, temp: blk_addr, value: blk_reg})
  if fuse_ew_gpu_eligible?(spec, arrs)
    mtcpu_label = next_label(wfn, "fuse.mtcpu")
    msl_tv = lower_string(ctx, Tungsten:AST:String.new(fuse_ew_msl_kernel(spec, arrs.size())))
    msl_reg = ensure_i64_value(wfn, msl_tv)
    gpu_reg = next_temp(wfn)
    emit_instruction(wfn, {op: :call_direct_i64, temp: gpu_reg, name: "w_fused_gpu_run", args: [sid.to_s(), msl_reg, blk_addr, arrs.size().to_s(), scls.size().to_s(), size_reg]})
    gpu_cmp = next_temp(wfn)
    emit_instruction(wfn, {op: :icmp_i64, temp: gpu_cmp, pred: "ne", lhs: gpu_reg, rhs: "0"})
    emit_instruction(wfn, {op: :cond_br, cond: gpu_cmp, then_label: done_label, else_label: mtcpu_label})
    start_block(wfn, mtcpu_label)
  fn_addr = next_temp(wfn)
  emit_instruction(wfn, {op: :fn_addr_i64, temp: fn_addr, name: worker_name})
  run_reg = next_temp(wfn)
  emit_instruction(wfn, {op: :call_direct_i64, temp: run_reg, name: "w_fused_parallel_run", args: [fn_addr, blk_addr, size_reg]})
  emit_instruction(wfn, {op: :br, label: done_label})

  start_block(wfn, st_label)
  out_base = next_temp(wfn)
  emit_instruction(wfn, {op: fuse_ew_elems_ptr_op(odt), temp: out_base, value: out_reg})
  ai = 0
  while ai < arrs.size()
    base = next_temp(wfn)
    emit_instruction(wfn, {op: fuse_ew_elems_ptr_op(arrs[ai][:etype]), temp: base, value: arrs[ai][:reg]})
    arrs[ai][:base] = base
    ai += 1
  fuse_ew_emit_range_loop(ctx, spec, arrs, out_base, "0", size_reg, odt, ewsid)
  emit_instruction(wfn, {op: :br, label: done_label})

  start_block(wfn, done_label)
  typed_value(:i64, out_reg)

# One registry for Math intrinsics that have both a native implementation and,
# in some cases, a source-level fallback in core/math.w. Static source dispatch
# must not shadow a matching intrinsic: the same lookup drives precedence and
# the boxed runtime call, so adding a fallback cannot silently change codegen.
# Lives here (not method_call.w) so lower_call — earlier in the worker chain —
# can consult it for `use math/globals` alias calls.
-> math_intrinsic_runtime_name(name, arity)
  if arity == 1
    if name == "exp"
      return "w_math_exp"
    if name == "log"
      return "w_math_log"
    if name == "expm1"
      return "w_math_expm1"
    if name == "log1p"
      return "w_math_log1p"
    if name == "sin"
      return "w_math_sin"
    if name == "cos"
      return "w_math_cos"
    if name == "tan"
      return "w_math_tan"
    if name == "asin"
      return "w_math_asin"
    if name == "acos"
      return "w_math_acos"
    if name == "atan"
      return "w_math_atan"
    if name == "cbrt"
      return "w_math_cbrt"
    if name == "sqrt"
      return "w_math_sqrt"
    if name == "floor"
      return "w_math_floor"
    if name == "ceil"
      return "w_math_ceil"
    if name == "round"
      return "w_math_round"
    if name == "abs"
      return "w_math_abs"
  if arity == 2
    if name == "pow"
      return "w_math_pow"
    if name == "ldexp"
      return "w_math_ldexp"
    if name == "atan2"
      return "w_math_atan2"
    if name == "hypot"
      return "w_math_hypot"
  nil

# Shared Math-intrinsic call lowering, used by the `Math.<name>` receiver
# branch (method_call.w) and by bare calls to registered `use math/globals`
# aliases (calls.w). Raw operands go straight to libm (call_libm_f64),
# skipping the box -> w_math_* -> unbox -> re-box round-trip; boxed WValues
# keep the runtime path, which resolves Int/Float dynamically. Returns nil
# for shapes the intrinsic path doesn't cover (caller falls back).
-> lower_math_intrinsic_call(ctx, method_name, math_runtime, args)
  wfn = ctx[:func]
  if args.size() == 1
    arg_val = lower_expression(ctx, args[0])
    if arg_val[:type] in (:raw_f64 :raw_f32 :raw_int :raw_i64 :raw_u64)
      libm_name = method_name
      if method_name == "abs"
        libm_name = "fabs"
      arg_raw = ensure_raw_f64(wfn, arg_val)
      temp = next_temp(wfn)
      emit_instruction(wfn, {op: :call_libm_f64, temp: temp, name: libm_name, value: arg_raw})
      return typed_value(:raw_f64, temp)
    arg_reg = ensure_i64_value(wfn, arg_val)
    temp = next_temp(wfn)
    emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: math_runtime, args: [arg_reg]})
    return typed_value(:i64, temp)
  if args.size() == 2
    a_val = lower_expression(ctx, args[0])
    b_val = lower_expression(ctx, args[1])
    # Raw fast path for the pure-libm pair (ldexp's second arg is an
    # int, so it stays on the runtime path). Both operands must already
    # be raw — a boxed WValue needs w_math_to_double's dynamic Int/Float
    # handling.
    if method_name in ("pow" "atan2" "hypot")
      if a_val[:type] in (:raw_f64 :raw_f32 :raw_int :raw_i64 :raw_u64) && b_val[:type] in (:raw_f64 :raw_f32 :raw_int :raw_i64 :raw_u64)
        a_raw = ensure_raw_f64(wfn, a_val)
        b_raw = ensure_raw_f64(wfn, b_val)
        temp = next_temp(wfn)
        emit_instruction(wfn, {op: :call_libm_f64, temp: temp, name: method_name, lhs: a_raw, rhs: b_raw})
        return typed_value(:raw_f64, temp)
    a_reg = ensure_i64_value(wfn, a_val)
    b_reg = ensure_i64_value(wfn, b_val)
    temp = next_temp(wfn)
    emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: math_runtime, args: [a_reg, b_reg]})
    return typed_value(:i64, temp)
  nil
