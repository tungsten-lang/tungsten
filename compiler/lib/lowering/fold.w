# Compile-time demanded fold for `expr ## fold` / `expr ## fold T` and
# `-> ## fold` blocks. Fail closed: anything this evaluator cannot prove
# constant is E_LOWER_FOLD. The result is re-lowered as a literal so the
# rest of the pipeline (including a remaining type ascription) is unchanged.

FOLD_STEP_LIMIT = 100000

-> fold_type_hint?(text)
  if text == nil
    return false
  s = ("" + text.to_s()).strip()
  if s == "fold"
    return true
  s.starts_with?("fold ")

-> fold_type_hint_rest(text)
  if text == nil
    return nil
  s = ("" + text.to_s()).strip()
  if s == "fold"
    return nil
  if !s.starts_with?("fold ")
    return nil
  rest = s.slice(5, s.size() - 5).strip()
  if rest.size() == 0
    return nil
  rest

-> fold_fail(ctx, node, message)
  raise compile_error_for_node(:E_LOWER_FOLD, message, ctx[:source_path], node)

-> fold_bump(state, ctx, node)
  n = state[:steps] + 1
  if n > FOLD_STEP_LIMIT
    fold_fail(ctx, node, "cannot fold: exceeded " + FOLD_STEP_LIMIT.to_s() + " steps")
  state[:steps] = n
  n

-> lower_fold_ascription(ctx, node)
  hint = node.type_hint
  folded = fold_eval(ctx, node.expression, {}, {steps: 0})
  folded_ast = fold_value_to_ast(folded, node)
  rest = fold_type_hint_rest(hint)
  if rest != nil
    etype = array_hint_element_type(rest)
    if etype != nil && type(folded) == "Array" && etype != "f32" && etype != "f64"
      return lower_fold_typed_array(ctx, folded, etype, node)
    return lower_expression(ctx, Tungsten:AST:TypeAscription.new(folded_ast, rest))
  lower_expression(ctx, folded_ast)

-> fold_etype_inline_bits(etype)
  if etype == "bool" || etype == "u1" || etype == "i1"
    return 1
  if etype == "u8"
    return 8
  if etype == "i8"
    return 108
  if etype == "u16"
    return 16
  if etype == "i16"
    return 116
  if etype == "u32"
    return 32
  if etype == "i32"
    return 33
  if etype == "u64"
    return 64
  if etype == "i64"
    return 66
  if etype == "w64"
    return 65
  0

-> fold_etype_store_bits(etype)
  if etype in ("u8" "i8")
    return 8
  if etype in ("u16" "i16")
    return 16
  if etype in ("u32" "i32")
    return 32
  64

-> fold_etype_signed?(etype)
  etype.starts_with?("i")

-> lower_fold_typed_array(ctx, values, etype, origin)
  wfn = ctx[:func]
  bits = fold_etype_inline_bits(etype)
  if bits == 0
    fold_fail(ctx, origin, "cannot fold typed array element type '" + etype + "'")
  n = values.size()
  arr = next_temp(wfn)
  emit_wire_call_direct_i64(wfn, nil, [bits.to_s(), n.to_s()], nil, nil, "w_array_new_inline", nil, nil, arr)
  store_bits = fold_etype_store_bits(etype)
  signed = fold_etype_signed?(etype)
  i = 0
  while i < n
    val_ast = fold_value_to_ast(values[i], origin)
    val = lower_expression(ctx, val_ast)
    val_reg = ensure_raw_machine_int(wfn, val, :i64, nil)
    scratch = []
    si = 0
    while si < 10
      scratch.push(next_temp(wfn))
      si += 1
    stored = next_temp(wfn)
    emit_wire_typed_array_set_inline(wfn, arr, store_bits, i.to_s(), true, scratch, signed, stored, val_reg)
    i += 1
  typed_value(typed_array_etype_to_sym(etype), arr)

-> fold_value_to_ast(value, origin)
  if value == nil
    return Tungsten:AST:Nil.new
  t = type(value)
  if t == "Bool" || value == true || value == false
    return Tungsten:AST:Bool.new(value)
  if t == "Int" || t == "BigInt"
    return Tungsten:AST:Int.new(value)
  if t == "String"
    return Tungsten:AST:String.new(value)
  if t == "Float"
    return Tungsten:AST:Float.new(value)
  if t == "Array"
    els = []
    i = 0
    while i < value.size()
      els.push(fold_value_to_ast(value[i], origin))
      i += 1
    return Tungsten:AST:Array.new(els)
  if t == "Hash"
    entries = []
    ks = value.keys()
    i = 0
    while i < ks.size()
      k = ks[i]
      entries.push([fold_value_to_ast(k, origin), fold_value_to_ast(value[k], origin)])
      i += 1
    return Tungsten:AST:HashLiteral.new(entries)
  fold_fail({source_path: nil}, origin, "cannot fold: unsupported result type " + t.to_s())

-> fold_eval(ctx, node, env, state)
  if node == nil
    return nil
  if !is_ast_node?(node)
    return node
  fold_bump(state, ctx, node)
  k = ast_kind(node)
  if k == :int || k == :wvalue
    return node.value
  if k == :float
    return node.value.to_s().to_f()
  if k == :string
    return node.value
  if k == :bool
    return node.value
  if k == :nil_lit
    return nil
  if k == :symbol
    return node.value.to_sym()
  if k == :array
    out = []
    els = node.elements
    if els == nil
      return out
    i = 0
    while i < els.size()
      out.push(fold_eval(ctx, els[i], env, state))
      i += 1
    return out
  if k == :hash_literal
    out = {}
    entries = node.entries
    if entries == nil
      return out
    i = 0
    while i < entries.size()
      pair = entries[i]
      out[fold_eval(ctx, pair[0], env, state)] = fold_eval(ctx, pair[1], env, state)
      i += 1
    return out
  if k == :unary_op
    v = fold_eval(ctx, node.operand, env, state)
    if node.op == :MINUS
      return 0 - v
    fold_fail(ctx, node, "cannot fold unary operator")
  if k == :not
    v = fold_eval(ctx, node.operand, env, state)
    return v == nil || v == false
  if k == :binary_op
    return fold_eval_binary(ctx, node, env, state)
  if k == :and
    left = fold_eval(ctx, node.left, env, state)
    if left == nil || left == false
      return left
    return fold_eval(ctx, node.right, env, state)
  if k == :or
    left = fold_eval(ctx, node.left, env, state)
    if left != nil && left != false
      return left
    return fold_eval(ctx, node.right, env, state)
  if k == :var
    name = node.name
    if env.has_key?(name)
      return env[name]
    consts = ctx[:mod][:top_level_const_values]
    if consts != nil && consts.has_key?(name)
      return consts[name]
    fold_fail(ctx, node, "cannot fold unbound name '" + name.to_s() + "'")
  if k == :assign
    return fold_eval_assign(ctx, node, env, state)
  if k == :compound_assign
    return fold_eval_compound(ctx, node, env, state)
  if k == :block
    return fold_eval_body(ctx, node.body, env, state)
  if k == :type_ascription
    inner = fold_eval(ctx, node.expression, env, state)
    rest = fold_type_hint_rest(node.type_hint)
    if rest == nil && !fold_type_hint?(node.type_hint)
      rest = node.type_hint
    if rest != nil
      return fold_apply_rest_type(inner, rest)
    return inner
  if k == :if
    return fold_eval_if(ctx, node, env, state)
  if k == :while
    return fold_eval_while(ctx, node, env, state)
  if k == :call
    return fold_eval_call(ctx, node, env, state)
  if k == :passthrough
    fold_eval(ctx, node.expression, env, state)
    return fold_eval(ctx, node.value, env, state)
  fold_fail(ctx, node, "cannot fold " + k.to_s())

-> fold_eval_body(ctx, body, env, state)
  if body == nil || body.size() == 0
    return nil
  result = nil
  i = 0
  while i < body.size()
    result = fold_eval(ctx, body[i], env, state)
    i += 1
  result

-> fold_truthy?(value)
  value != nil && value != false

-> fold_eval_if(ctx, node, env, state)
  if fold_truthy?(fold_eval(ctx, node.condition, env, state))
    return fold_eval_body(ctx, node.then_body, env, state)
  elsifs = node.elsif_clauses
  if elsifs != nil
    i = 0
    while i < elsifs.size()
      clause = elsifs[i]
      if fold_truthy?(fold_eval(ctx, clause[0], env, state))
        return fold_eval_body(ctx, clause[1], env, state)
      i += 1
  if node.else_body != nil
    return fold_eval_body(ctx, node.else_body, env, state)
  nil

-> fold_eval_while(ctx, node, env, state)
  result = nil
  while fold_truthy?(fold_eval(ctx, node.condition, env, state))
    result = fold_eval_body(ctx, node.body, env, state)
  result

-> fold_eval_assign(ctx, node, env, state)
  value = fold_eval(ctx, node.value, env, state)
  target = node.target
  if is_ast_node?(target) && ast_kind(target) == :var
    env[target.name] = value
    return value
  fold_fail(ctx, node, "cannot fold assignment target")

-> fold_eval_compound(ctx, node, env, state)
  target = node.target
  if !(is_ast_node?(target) && ast_kind(target) == :var)
    fold_fail(ctx, node, "cannot fold compound assignment target")
  name = target.name
  if !env.has_key?(name)
    fold_fail(ctx, node, "cannot fold unbound name '" + name.to_s() + "'")
  right = fold_eval(ctx, node.value, env, state)
  result = fold_apply_op(node.op, env[name], right, ctx, node)
  env[name] = result
  result

-> fold_eval_binary(ctx, node, env, state)
  left = fold_eval(ctx, node.left, env, state)
  right = fold_eval(ctx, node.right, env, state)
  fold_apply_op(node.op, left, right, ctx, node)

-> fold_apply_op(op, left, right, ctx, node)
  if op == :PLUS
    return left + right
  if op == :MINUS
    return left - right
  if op == :STAR
    return left * right
  if op == :SLASH
    return left / right
  if op == :PERCENT
    return left % right
  if op == :POW
    return left ** right
  if op == :AMPERSAND
    return left & right
  if op == :PIPE
    return left | right
  if op == :CARET
    return left ^ right
  if op == :LSHIFT
    return left << right
  if op == :RSHIFT
    return left >> right
  if op == :EQ
    return left == right
  if op == :NEQ
    return left != right
  if op == :LT
    return left < right
  if op == :LTE
    return left <= right
  if op == :GT
    return left > right
  if op == :GTE
    return left >= right
  fold_fail(ctx, node, "cannot fold operator")

-> fold_eval_call(ctx, node, env, state)
  if node.block != nil
    fold_fail(ctx, node, "cannot fold call with a trailing block")
  args = []
  raw_args = node.args
  if raw_args != nil
    i = 0
    while i < raw_args.size()
      args.push(fold_eval(ctx, raw_args[i], env, state))
      i += 1
  recv_node = node.receiver
  if recv_node != nil
    recv = fold_eval(ctx, recv_node, env, state)
    return fold_eval_method(ctx, node, recv, args, state)
  name = node.name
  if name in ("l1d_cache_bytes" "l2_cache_bytes" "cpus_per_l2") && args.size() == 0
    if !host_native_build?()
      fold_fail(ctx, node, "cannot fold host fact '" + name + "' in a cross build")
    return host_cache_bytes(ctx[:mod], name)
  if name in ("env" "read_file" "write_file" "system" "capture" "puts" "print")
    fold_fail(ctx, node, "cannot fold impure call '" + name + "'")
  fn_def = ctx[:mod][:known_fn_defs][name]
  if fn_def == nil
    fold_fail(ctx, node, "cannot fold unknown function '" + name + "'")
  if fn_body_calls_impure_ccall?(fn_def.body)
    fold_fail(ctx, node, "cannot fold '" + name + "': body is not pure")
  child = {}
  params = fn_def.params
  i = 0
  while i < params.size()
    pname = params[i].name
    if i < args.size()
      child[pname] = args[i]
    else
      child[pname] = nil
    i += 1
  fold_eval_body(ctx, fn_def.body, child, state)

-> fold_eval_method(ctx, node, recv, args, state)
  name = node.name
  if type(recv) == "Array"
    if name == "push" && args.size() == 1
      recv.push(args[0])
      return recv
    if name == "size" || name == "length"
      if args.size() == 0
        return recv.size()
    if name in ("\[]" "[]") && args.size() == 1
      return recv[args[0]]
    if name in ("\[]=" "[]=") && args.size() == 2
      recv[args[0]] = args[1]
      return args[1]
  fold_fail(ctx, node, "cannot fold method '" + name.to_s() + "'")

-> fold_apply_rest_type(value, rest)
  value
