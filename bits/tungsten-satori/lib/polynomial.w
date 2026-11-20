# Bounded polynomial recognition for recurrence and quadratic-form rules.
# The caller checks the suggested coefficients when reconstructing the proof.

# Bound expansion before calling ring_norm/ring_eq. Opaque atoms cost one;
# sums add costs, products multiply them, and callers bound literal powers.
-> recurrence_ring_cost(t, kind, nodes, max_power = 3)
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
        cost = recurrence_ring_cost(a, kind, nodes, max_power) + recurrence_ring_cost(b, kind, nodes, max_power)
      elsif op == OP_MUL
        cost = recurrence_ring_cost(a, kind, nodes, max_power) * recurrence_ring_cost(b, kind, nodes, max_power)
      elsif op == OP_POW && b.tag == :lit
        if b.val < 0 || b.val > max_power
          raise "recurrence: power limit"
        base = recurrence_ring_cost(a, kind, nodes, max_power)
        i = 0
        while i < b.val
          cost *= base
          i += 1
      elsif op == OP_DIV && (kind == "rat" || kind == "real") && b.tag == :lit && b.val[0] != 0
        cost = recurrence_ring_cost(a, kind, nodes, max_power)
    elsif t.a.tag == :const && t.a.op == OP_NEG && kind != "nat"
      cost = recurrence_ring_cost(t.b, kind, nodes, max_power)
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
-> recurrence_atom_coefficients(k, t, index, atom, max_degree = 3, max_factors = 64)
  ty = type_of(t)
  kind = ty.name
  recurrence_ring_cost(t, kind, [128], max_degree)
  ctx = RingCtx.new(kind)
  index_id = ctx.atom(atom)
  polynomial = ring_norm(t, kind, ctx)
  atoms = {}
  ctx.atoms.each -> (key, bucket)
    bucket.each -> (pair)
      if pair[1] != index_id && tm_free_in?(index, pair[0])
        raise "recurrence: nonpolynomial index"
      atoms[pair[1]] = pair[0]
  polynomial_coefficients(k, ty, ctx, polynomial, atoms, index_id, nil, max_degree, max_factors)

# Collect powers of one axis. With a second axis, require each monomial to
# have total degree two in the pair and leave both axes out of its coefficient.
-> polynomial_coefficients(k, ty, ctx, polynomial, atoms, index_id, second_id = nil, max_degree = 3, max_factors = 64)
  kind = ty.name
  zero = mk_lit(kind == "nat" || kind == "int" ? 0 : Q_ZERO, ty)
  coefficients = Array.new(max_degree + 1, zero)
  plus = k.mk_const("+", ty_funs([ty, ty], ty))
  times = k.mk_const("*", ty_funs([ty, ty], ty))
  size = 0
  polynomial.each -> (mid, q)
    if (kind == "nat" && q[0] < 0) || ((kind == "nat" || kind == "int") && q[1] != 1)
      raise "recurrence: coefficient type"
    coefficient = mk_lit(kind == "nat" || kind == "int" ? q[0] : q, ty)
    mono = ctx.monos[mid]
    degree = 0
    second_degree = 0
    i = 0
    while i < mono.size
      if mono[i] == index_id
        degree = mono[i + 1]
      elsif mono[i] == second_id
        second_degree = mono[i + 1]
      else
        j = 0
        while j < mono[i + 1]
          size += 1
          if size > max_factors
            raise "recurrence: coefficient limit"
          coefficient = mk_apps(times, [coefficient, atoms[mono[i]]])
          j += 1
      i += 2
    if second_id != nil && degree + second_degree != 2
      return nil
    if degree > max_degree
      raise "recurrence: degree limit"
    if tm_eq(coefficients[degree], zero)
      coefficients[degree] = coefficient
    else
      coefficients[degree] = mk_apps(plus, [coefficients[degree], coefficient])
  degree = max_degree
  while degree > 0 && tm_eq(coefficients[degree], zero)
    degree -= 1
  [degree, coefficients]

# Find the two squared atoms of a homogeneous binary form. Atom identifiers
# need not be variables: evaluations such as u(t) and v(t) work as coordinates.
-> binary_form_coefficients(k, cmp)
  ty = type_of(cmp[1])
  nodes = [96]
  if recurrence_ring_cost(cmp[1], ty.name, nodes) + recurrence_ring_cost(cmp[2], ty.name, nodes) > 32
    return nil
  ctx = RingCtx.new(ty.name)
  poly = poly_add(ring_norm(cmp[2], ty.name, ctx), poly_scale(ring_norm(cmp[1], ty.name, ctx), Q_NEG_ONE))
  axes = []
  poly.each -> (mid, coefficient)
    mono = ctx.monos[mid]
    i = 0
    while i < mono.size
      if mono[i + 1] == 2 && !axes.include?(mono[i])
        axes.push(mono[i])
      i += 2
  if axes.size != 2
    return nil
  atoms = {}
  ctx.atoms.each -> (_key, bucket)
    bucket.each -> (entry) atoms[entry[1]] = entry[0]
  result = polynomial_coefficients(k, ty, ctx, poly, atoms, axes[0], axes[1])
  if result == nil
    return nil
  cs = result[1]
  [cs[2], cs[1], cs[0], atoms[axes[0]], atoms[axes[1]]]

# Divide the goal difference by the supplied equation differences. A zero
# remainder proposes a linear combination; the tactic checks that identity.
+ PolynomialReduction
  -> new(@ty)
    @ctx = RingCtx.new(@ty.name)

  -> difference(left, right)
    nodes = [160]
    recurrence_ring_cost(left, @ty.name, nodes, 8)
    recurrence_ring_cost(right, @ty.name, nodes, 8)
    poly_add(ring_norm(left, @ty.name, @ctx), poly_scale(ring_norm(right, @ty.name, @ctx), Q_NEG_ONE))

  # Sparse lexicographic order. Smaller atom IDs have priority. The leading
  # term of a product is the product of the leading terms in this order.
  -> precedes(a, b)
    i = 0
    while i < a.size && i < b.size
      if a[i] != b[i]
        return a[i] < b[i]
      if a[i+1] != b[i+1]
        return a[i+1] > b[i+1]
      i += 2
    a.size > b.size

  -> leading(poly)
    best = 0
    poly.each -> (id, _q)
      if precedes(@ctx.monos[id], @ctx.monos[best])
        best = id
    best

  -> quotient(dividend, divisor)
    out = []
    j = 0
    i = 0
    while i < dividend.size
      atom = dividend[i]
      exponent = dividend[i+1]
      if j < divisor.size
        if divisor[j] < atom
          return nil
        if divisor[j] == atom
          exponent -= divisor[j+1]
          if exponent < 0
            return nil
          j += 2
      if exponent > 0
        out.push(atom)
        out.push(exponent)
      i += 2
    j == divisor.size ? out : nil

  -> certificate(target, facts)
    remainder = difference(target[0], target[1])
    if remainder.empty?()
      return nil
    divisors = []
    facts.each -> (fact)
      begin
        poly = difference(fact.concl.a.b, fact.concl.b)
        head = leading(poly)
        if head != 0
          divisors.push([fact, poly, head])
      rescue unsupported
        0
    direct = reduce(remainder, divisors, [], [32])
    if direct != nil || divisors.empty?()
      return direct
    span_certificate(remainder, divisors)

  # Several equations can divide the same leading term. Backtrack within
  # one shared budget to try another divisor when the first leaves a remainder.
  -> reduce(remainder, divisors, steps, fuel)
    if remainder.empty?()
      return steps
    if steps.size >= 24 || remainder.size > 64 || fuel[0] <= 0
      return nil
    mid = leading(remainder)
    i = 0
    while i < divisors.size && fuel[0] > 0
      divisor = divisors[i]
      i += 1
      head = divisor[2]
      mono = quotient(@ctx.monos[mid], @ctx.monos[head])
      if mono == nil
        next
      coeff = q_div(remainder[mid], divisor[1][head])
      if (@ty.name == "int" || @ty.name == "nat") && coeff[1] != 1
        next
      fuel[0] -= 1
      factor = {}
      factor[@ctx.intern_mono(mono)] = q_neg(coeff)
      rest = poly_add(remainder, poly_mul(factor, divisor[1], @ctx))
      proof = reduce(rest, divisors, steps + [[divisor[0], coeff, mono]], fuel)
      if proof != nil
        return proof
    nil

  # Row operations act on the polynomial and its expression in the original
  # columns together. An absent pivot leaves a new independent row.
  -> eliminate(row, weights, basis, fuel)
    while !row.empty?()
      if row.size > 64
        raise "polynomial row size limit"
      pivot = leading(row)
      entry = basis[pivot]
      if entry == nil
        break
      fuel[0] -= 1
      if fuel[0] < 0
        raise "polynomial elimination limit"
      multiplier = q_neg(q_div(row[pivot], entry[0][pivot]))
      row = poly_add(row, poly_scale(entry[0], multiplier))
      weights = poly_add(weights, poly_scale(entry[1], multiplier))
    [row, weights]

  # Search the span of small monomial multiples. This can combine equations
  # whose leading terms overlap even when neither divides the final remainder.
  -> span_certificate(target, divisors)
    atoms = []
    @ctx.atoms.each -> (_hash, bucket)
      bucket.each -> (pair) atoms.push(@ctx.atom_mono(pair[0]))
    if atoms.size > 8 || target.size > 32
      return nil
    # A coefficient may raise the degree above the goal before the highest
    # terms cancel. Try constants first, then atoms and quadratic monomials.
    factors = [0] + atoms
    atoms.each -> (a)
      atoms.each -> (b)
        if a <= b
          factors.push(@ctx.mono_mul(a, b))
    columns = []
    basis = {}
    pending = [target, {}]
    fuel = [192]
    factors.each -> (factor)
      divisors.each -> (divisor)
        if columns.size >= 48
          return nil
        multiple = factor == 0 ? divisor[1] : poly_mul({factor => Q_ONE}, divisor[1], @ctx)
        entry = eliminate(multiple, {columns.size => Q_ONE}, basis, fuel)
        columns.push([divisor[0], @ctx.monos[factor]])
        if entry[0].empty?()
          next
        pivot = leading(entry[0])
        basis[pivot] = entry
        if pending[0][pivot] != nil
          pending = eliminate(pending[0], pending[1], basis, fuel)
          if pending[0].empty?()
            steps = []
            pending[1].each -> (index, weight)
              column = columns[index]
              steps.push([column[0], q_neg(weight), column[1]])
            return steps
    nil

  -> prove(prover, target, facts)
    steps = certificate(target, facts)
    if steps == nil
      return nil
    atoms = {}
    @ctx.atoms.each -> (_hash, bucket)
      bucket.each -> (pair) atoms[pair[1]] = pair[0]
    times = prover.k.mk_const("*", ty_funs([@ty, @ty], @ty))
    power = prover.k.mk_const("^", ty_funs([@ty, ty_nat], @ty))
    # Fractional coefficients over ℕ or ℤ certify a positive multiple of the
    # equality. Clear them before constructing terms, then check cancellation.
    denominator = 1
    if @ty.name == "nat" || @ty.name == "int"
      steps.each -> (step)
        den = step[1][1]
        denominator = zmul(denominator / int_gcd(denominator, den), den)
    proof = nil
    steps.each -> (step)
      fact = step[0]
      q = q_mul(step[1], [denominator, 1])
      if q[0] < 0
        fact = prover.k.sym(fact)
        q = q_neg(q)
      coefficient = mk_lit(@ty.name == "int" || @ty.name == "nat" ? q[0] : q, @ty)
      mono = step[2]
      i = 0
      while i < mono.size
        if mono[i+1] > 16
          return nil
        atom = atoms[mono[i]]
        factor = mono[i+1] == 1 ? atom : mk_apps(power, [atom, mk_lit(mono[i+1], ty_nat)])
        coefficient = mk_apps(times, [coefficient, factor])
        i += 2
      scaled = prover.combination_binop("*", @ty, prover.k.refl(coefficient), fact)
      proof = proof == nil ? scaled : prover.combination_binop("+", @ty, proof, scaled)
    if denominator != 1
      goal = Goal.new([], [], prover.k.eq_tm(target[0], target[1]))
      return prover.linarith_proof(goal, [proof])
    prover.finish_combination(target, @ty, proof)
