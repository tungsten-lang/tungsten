# Bounded, untrusted recognition for polynomial recurrence automation.
# Coefficients are suggestions only: the caller replays the recurrence rule
# and checks the resulting identity with the kernel's ring conversion.

# Bound expansion before calling ring_norm/ring_eq. Opaque atoms cost one;
# sums add costs, products multiply them, and literal powers are at most cubic.
-> recurrence_ring_cost(t, kind, nodes)
  nodes[0] -= 1
  if nodes[0] < 0
    raise "recurrence: term limit"
  cost = 1
  if t.tag == :app
    if t.a.tag == :app && t.a.a.tag == :const
      op = t.a.a.op
      a = t.a.b
      b = t.b
      if op == OP_ADD || (op == OP_SUB && kind != "nat")
        cost = recurrence_ring_cost(a, kind, nodes) + recurrence_ring_cost(b, kind, nodes)
      elsif op == OP_MUL
        cost = recurrence_ring_cost(a, kind, nodes) * recurrence_ring_cost(b, kind, nodes)
      elsif op == OP_POW && b.tag == :lit
        if b.val < 0 || b.val > 3
          raise "recurrence: power limit"
        base = recurrence_ring_cost(a, kind, nodes)
        i = 0
        while i < b.val
          cost *= base
          i += 1
      elsif op == OP_DIV && (kind == "rat" || kind == "real") && b.tag == :lit && b.val[0] != 0
        cost = recurrence_ring_cost(a, kind, nodes)
    elsif t.a.tag == :const && t.a.op == OP_NEG && kind != "nat"
      cost = recurrence_ring_cost(t.b, kind, nodes)
  if cost > 64
    raise "recurrence: expansion limit"
  cost

# Small formulas for a single induction step. Sequence atoms are opt-in;
# powers may have a small literal degree or exponent index+k, with 0<=k<=3.
# Division is only by a nonzero literal over a field.
-> recurrence_formula?(k, t, index, nodes, sequences = nil)
  nodes[0] -= 1
  if nodes[0] < 0
    return false
  if !tm_free_in?(index, t) || tm_eq(t, index)
    return true
  spine = strip_app(t)
  head = spine[0]
  args = spine[1]
  # Optionally admit a few distinct sequence values at exactly this index. Their
  # initial values and steps still have to be proved by the caller; an opaque
  # function contributes no recurrence merely because it has this shape.
  if sequences != nil && ["nat", "int", "rat", "real"].include?(type_of(t).name) && (head.tag == :var || (head.tag == :const && head.op == OP_NONE))
    indices = 0
    other_index = false
    args.each -> (arg)
      if tm_eq(arg, index)
        indices += 1
      elsif tm_free_in?(index, arg)
        other_index = true
    if indices == 1 && !other_index
      if sequences[1].any?(-> (old) tm_eq(old, t))
        return true
      if sequences[0] <= 0
        return false
      sequences[0] -= 1
      sequences[1].push(t)
      return true
  if head.tag != :const
    return false
  if args.size == 1 && (head.op == OP_NEG || (head.op >= OP_INT_OF_NAT && head.op <= OP_REAL_OF_RAT))
    return recurrence_formula?(k, args[0], index, nodes, sequences)
  if args.size != 2
    return false
  if head.op == OP_ADD || head.op == OP_SUB || head.op == OP_MUL
    return recurrence_formula?(k, args[0], index, nodes, sequences) && recurrence_formula?(k, args[1], index, nodes, sequences)
  if head.op == OP_DIV && ["rat", "real"].include?(type_of(t).name) && args[1].tag == :lit && args[1].val[0] != 0
    return recurrence_formula?(k, args[0], index, nodes, sequences)
  if head.op != OP_POW
    return false
  if args[1].tag == :lit && args[1].val >= 0 && args[1].val <= 3
    return recurrence_formula?(k, args[0], index, nodes, sequences)
  if tm_free_in?(index, args[0])
    return false
  begin
    coefficients = recurrence_coefficients(k, args[1], index)
    cs = coefficients[1]
    return coefficients[0] == 1 && cs[1].tag == :lit && cs[1].val == 1 && cs[0].tag == :lit && cs[0].val >= 0 && cs[0].val <= 3
  rescue e
    false

-> recurrence_coefficients(k, t, index)
  ty = type_of(t)
  kind = ty.name
  cast = index
  if kind != "nat"
    cast = mk_app(k.mk_const("int_of_nat", ty_fun(ty_nat, ty_int)), cast)
  if kind == "rat" || kind == "real"
    cast = mk_app(k.mk_const("rat_of_int", ty_fun(ty_int, ty_rat)), cast)
  if kind == "real"
    cast = mk_app(k.mk_const("real_of_rat", ty_fun(ty_rat, ty_real)), cast)
  recurrence_atom_coefficients(k, t, index, cast)

# The distinguished atom may also be r^index. All other atoms must be
# independent of the index, so a second rate or a shifted exponent is rejected.
-> recurrence_atom_coefficients(k, t, index, atom)
  ty = type_of(t)
  kind = ty.name
  recurrence_ring_cost(t, kind, [128])
  ctx = RingCtx.new(kind)
  index_id = ctx.atom(atom)
  polynomial = ring_norm(t, kind, ctx)
  atoms = {}
  ctx.atoms.each -> (key, bucket)
    bucket.each -> (pair)
      if pair[1] != index_id && tm_free_in?(index, pair[0])
        raise "recurrence: nonpolynomial index"
      atoms[pair[1]] = pair[0]
  zero = mk_lit(kind == "nat" || kind == "int" ? 0 : Q_ZERO, ty)
  coefficients = [zero, zero, zero, zero]
  plus = k.mk_const("+", ty_funs([ty, ty], ty))
  times = k.mk_const("*", ty_funs([ty, ty], ty))
  size = 0
  polynomial.each -> (mid, q)
    if (kind == "nat" && q[0] < 0) || ((kind == "nat" || kind == "int") && q[1] != 1)
      raise "recurrence: coefficient type"
    coefficient = mk_lit(kind == "nat" || kind == "int" ? q[0] : q, ty)
    mono = ctx.monos[mid]
    degree = 0
    i = 0
    while i < mono.size
      if mono[i] == index_id
        degree = mono[i + 1]
      else
        j = 0
        while j < mono[i + 1]
          size += 1
          if size > 64
            raise "recurrence: coefficient limit"
          coefficient = mk_apps(times, [coefficient, atoms[mono[i]]])
          j += 1
      i += 2
    if degree > 3
      raise "recurrence: degree limit"
    if tm_eq(coefficients[degree], zero)
      coefficients[degree] = coefficient
    else
      coefficients[degree] = mk_apps(plus, [coefficients[degree], coefficient])
  degree = 3
  while degree > 0 && tm_eq(coefficients[degree], zero)
    degree -= 1
  [degree, coefficients]
