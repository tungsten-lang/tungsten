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
  when :i128
    "w_i128"
  when :u128
    "w_u128"
  else
    "w_int"

-> machine_unbox_fn(t)
  case t
  when :u64
    "w_to_u64"
  when :i128
    "w_to_i128"
  when :u128
    "w_to_u128"
  else
    "w_to_i64"

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

-> lower_compound_assign(ctx, node)
  # Desugar: x += val  →  x = x op val
  target = node.target
  name = target.name
  wfn = ctx[:func]

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

  # Evaluate RHS
  rhs = lower_expression(ctx, node.value)
  rhs_reg = ensure_i64_value(wfn, rhs)

  # Map compound op to binary op
  op = node.op
  int_op = lowering_int_op_map[op]
  rt_op = lowering_op_map[op]

  # Check if both sides are int for inline op
  lt = ctx[:var_types][name]
  vt = infer_type(node.value, ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)

  # For +/-/* compound assignment on ints: use runtime calls (w_add/w_sub/w_mul)
  # because the accumulator may be a bigint after overflow, and checked/guarded
  # i48 ops produce garbage when given non-i48 inputs
  if lt == :int && vt == :int && op in (:PLUS :MINUS :STAR)
    rt_fb = nil
    if op == :PLUS
      rt_fb = "w_add"
    elsif op == :MINUS
      rt_fb = "w_sub"
    elsif op == :STAR
      rt_fb = "w_mul"
    result_temp = next_temp(wfn)
    emit_instruction(wfn, {op: :call_direct_i64, temp: result_temp, name: rt_fb, args: [cur, rhs_reg]})
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

  # Fallback: runtime call
  if rt_op != nil
    result = next_temp(wfn)
    emit_instruction(wfn, {op: :call_direct_i64, temp: result, name: rt_op, args: [cur, rhs_reg]})
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

# True when `nm` names a local slot, binding, typed var, or a known
# fn/call — i.e. the identifier refers to real code, not a unit name.
-> pipe_ident_shadowed?(ctx, nm)
  if ctx[:func][:var_slots][nm] != nil || ctx[:bindings][nm] != nil || ctx[:var_types][nm] != nil
    return true
  if ctx[:mod][:known_calls][nm] != nil || ctx[:mod][:known_fn_param_counts][nm] != nil
    return true
  false

# Conversion-pipe target: `| lb`, `| lb(2)`, `| J`, or a quoted registry
# spelling such as `| "metric cup"`. Returns
# {name, digits} when the RHS is a quoted spelling or a bare known-unit name —
# a var, PascalCase class_ref, one-int-arg call, or a compound rate unit that
# parsed as a `/`-map. Anything a local/fn shadows lowers as ordinary
# bitwise-or / division instead; quoted spellings are always explicit.
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
  elsif k == :map
    # `km/h` lexes as a `/`-map: source `km`, func the bare call `h`. Rebuild
    # the compound name and require BOTH components to be unshadowed — else
    # `x | a/b` with a real variable a or b stays a division.
    src = ast_get(rhs, :source)
    fnode = ast_get(rhs, :func)
    if is_ast_node?(src) && is_ast_node?(fnode) && ast_kind(src) == :var && ast_kind(fnode) == :call && fnode.receiver == nil
      fargs = fnode.args
      if fargs == nil || fargs.size() == 0
        sname = ast_get(src, :name)
        fname = ast_get(fnode, :name)
        if sname != nil && fname != nil && !pipe_ident_shadowed?(ctx, sname) && !pipe_ident_shadowed?(ctx, fname)
          name = sname + "/" + fname
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

-> lower_binary_op(ctx, node)
  wfn = ctx[:func]
  op = node.op

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

  # Type-directed: if both sides are int, emit inline LLVM ops
  lt = infer_type(node.left, ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)
  rt = infer_type(node.right, ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)

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

  machine_type = machine_int_result_type(lt, rt)
  if machine_type != nil && is_integer_like_type(lt) && is_integer_like_type(rt)
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
  if (lhs_unboxed || rhs_unboxed) && !mixed_float_operand && !is_bigint_type(lt) && !is_bigint_type(rt) && !ovf_guard_arith
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
    if int_op != nil && om_dm != :promote && om_dm != :trap
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
    if cmp_pred != nil && om_dm != :promote && om_dm != :trap
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

  # Mixed int×float: promote int to double, then inline float op
  if (lt == :float && is_integer_like_type(rt)) || (is_integer_like_type(lt) && rt == :float)
    float_op = lowering_float_op_map[op]
    fcmp_pred = lowering_fcmp_op_map[op]

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

  temp = next_temp(wfn)
  emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: rt_name, args: [lhs_reg, rhs_reg]})
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
  boxed = ensure_i64_value(wfn, tv)
  if inferred_type == :int
    raw = nanunbox_int_emit(wfn, boxed)
    return cast_raw_machine_int(wfn, raw, :int, type)
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
  nanunbox_float_emit(wfn, ensure_i64_value(wfn, tv))

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
  if k == :call && node.receiver != nil && node.name != nil && node.name in ("sin" "cos" "sqrt")
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
-> fuse_ew_emit_range_loop(ctx, spec, arrs, out_base, lo_val, hi_val, odt)
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
    emit_instruction(wfn, {op: fuse_ew_load_op(arrs[ai][:etype]), temp: cur, ptr: arrs[ai][:base], index: bi_v})
    arrs[ai][:cur] = cur
    ai += 1
  result_raw = fuse_ew_emit_scalar(ctx, spec)
  stw = next_temp(wfn)
  emit_instruction(wfn, {op: fuse_ew_store_op(odt), temp: stw, ptr: out_base, index: bi_v, value: result_raw})
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
-> fuse_ew_build_worker(ctx, spec, arrs, scls, odt, sid)
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
  fuse_ew_emit_range_loop(ctx, spec, arrs, out_base, "%__fw_lo", "%__fw_hi", odt)
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
  emit_instruction(wfn, {op: :call_direct_i64, temp: out_reg, name: "w_array_new_uninit_sized", args: [fuse_ew_alloc_bits(odt), size_reg]})

  sid = ctx[:mod][:next_fuse_site]
  if sid == nil
    sid = 0
  ctx[:mod][:next_fuse_site] = sid + 1
  worker_name = fuse_ew_build_worker(ctx, spec, arrs, scls, odt, sid)

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
  fuse_ew_emit_range_loop(ctx, spec, arrs, out_base, "0", size_reg, odt)
  emit_instruction(wfn, {op: :br, label: done_label})

  start_block(wfn, done_label)
  typed_value(:i64, out_reg)
