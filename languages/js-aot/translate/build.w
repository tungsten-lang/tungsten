# translate/build — small constructors over the Tungsten AST (compiler/lib/ast.w).
#
# The translator builds Tungsten:AST nodes directly; no Tungsten source text is
# generated (tools/dump_w prints one for people). Bodies are Arrays of nodes.

# Unit mode (translate/unit.w): a JtUnit, while translating a unit.
JT_UNIT = [nil]

-> ta_var(name)
  u = JT_UNIT[0]
  if u != nil
    x = u.var(name)
    return x if x != nil
  Tungsten:AST:Var.new(name)

-> ta_set(name, value)
  Tungsten:AST:Assign.new(Tungsten:AST:Var.new(name), value)

-> ta_call(name, args)
  u = JT_UNIT[0]
  return u.call(name, args) if u != nil
  Tungsten:AST:Call.new(nil, name, args)

-> ta_send(recv, name, args)
  u = JT_UNIT[0]
  if u != nil
    x = u.send(recv, name, args)
    return x if x != nil
  Tungsten:AST:Call.new(recv, name, args)

-> ta_nil
  Tungsten:AST:Nil.new

-> ta_bool(b)
  Tungsten:AST:Bool.new(b)

-> ta_int(i)
  Tungsten:AST:Int.new(i, nil, i.to_s)

-> ta_str(s)
  u = JT_UNIT[0]
  return u.str(s) if u != nil && !jsu_inline_str?(s)
  Tungsten:AST:String.new(s)

# A number literal: Float text that round-trips; NaN and the infinities are computed.
-> ta_num(x)
  return ta_call("js_nan", []) if x != x
  return ta_send(Tungsten:AST:Float.new("1.0"), "/", [Tungsten:AST:Float.new("0.0")]) if x == ~1.0 / ~0.0
  return ta_send(Tungsten:AST:Float.new("-1.0"), "/", [Tungsten:AST:Float.new("0.0")]) if x == ~-1.0 / ~0.0
  return ta_call("js_neg", [Tungsten:AST:Float.new("0.0")]) if x == ~0.0 && ~1.0 / x < ~0.0
  Tungsten:AST:Float.new(x.to_s)

-> ta_if(c, then_body, else_body)
  Tungsten:AST:If.new(c, then_body, [], else_body)

# A sequence used as an expression: its value is the last element's.
-> ta_seq(list)
  return list[0] if list.size == 1
  Tungsten:AST:If.new(Tungsten:AST:Bool.new(true), list, [], nil)

-> ta_while(c, body)
  Tungsten:AST:While.new(c, body)

-> ta_break
  Tungsten:AST:Break.new

-> ta_next
  Tungsten:AST:Next.new

-> ta_return(v)
  Tungsten:AST:Return.new(v)

-> ta_and(a, b)
  Tungsten:AST:And.new(a, b)

-> ta_or(a, b)
  Tungsten:AST:Or.new(a, b)

-> ta_not(a)
  Tungsten:AST:Not.new(a)

# Comparison operators are the parser's symbols (compiler/lib/parser/core.w): a string
# op is not one of them and does not lower as a comparison.
-> ta_eq(a, b)
  Tungsten:AST:BinaryOp.new(a, :EQ, b)

-> ta_ne(a, b)
  Tungsten:AST:BinaryOp.new(a, :NEQ, b)

-> ta_lt(a, b)
  Tungsten:AST:BinaryOp.new(a, :LT, b)

-> ta_le(a, b)
  Tungsten:AST:BinaryOp.new(a, :LTE, b)

-> ta_array(elems)
  Tungsten:AST:Array.new(elems)

-> ta_typed_array(etype, n)
  Tungsten:AST:TypedArray.new(etype, ta_int(n))

-> ta_def(name, params, body)
  ps = []
  if JT_UNIT[0] != nil && (name.starts_with?("jsd_") || name.starts_with?("jsf_"))
    ps.push(Tungsten:AST:Param.new("ctx"))
  i = 0
  while i < params.size
    ps.push(Tungsten:AST:Param.new(params[i]))
    i += 1
  Tungsten:AST:MethodDef.new(name, ps, body)

-> ta_begin(body, var, rescue_body)
  Tungsten:AST:Begin.new(body, var, rescue_body, nil)

-> ta_raise(v)
  Tungsten:AST:Raise.new(v)

# case subject / when pattern → body ... / else
-> ta_case(subject, arms, else_body)
  out = []
  i = 0
  while i < arms.size
    out.push(Tungsten:AST:CaseArm.new(arms[i][0], nil, arms[i][1]))
    i += 1
  Tungsten:AST:CaseValue.new(subject, out, else_body)

-> ta_gt(a, b)
  Tungsten:AST:BinaryOp.new(a, :GT, b)

-> ta_add(a, b)
  Tungsten:AST:BinaryOp.new(a, :PLUS, b)
