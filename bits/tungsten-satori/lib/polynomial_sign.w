# Univariate sign certificates. The power basis uses a displacement from
# one endpoint. On a finite interval the Bernstein basis uses both. All
# suggested weights and polynomial identities are checked by KKernel.farkas.
+ PolynomialViolation
  ro :conversion, :fact, :weight, :coefficients, :strict
  -> new(@conversion, @fact, @weight, @coefficients, @strict)
    nil

+ PolynomialSign
  -> new(@prover)
    @k = @prover.k
    @d = @prover.d

  -> literal(t)
    if t.tag == :lit
      return t
    if t.tag == :app && t.b.tag == :lit && (t.a.op == OP_NEG || (t.a.tag == :app && t.a.a.op == OP_DIV && t.a.b.tag == :lit))
      rhs = @k.compute(t).concl.b
      return rhs.tag == :lit ? rhs : nil
    nil

  # Keep the strongest literal endpoint on each side of this variable.
  -> bounds(axis, facts)
    ends = [nil, nil]
    facts.each -> (fact)
      cmp = dest_cmp_rel(fact.concl)
      if cmp == nil || cmp[0] == "="
        next
      side = tm_eq(cmp[2], axis) ? 0 : 1
      if !tm_eq(cmp[2 - side], axis)
        next
      endpoint = literal(cmp[1 + side])
      if endpoint == nil
        next
      value = ring_lit_q(endpoint, axis.ty.name)
      prev = ends[side]
      order = prev == nil ? 1 : q_cmp(value, prev[1]) * (side == 0 ? 1 : -1)
      if prev == nil || order > 0 || (order == 0 && cmp[0] == "<")
        ends[side] = [endpoint, value, fact]
    ends

  # Expand only scalar polynomial operations and applications of definitions.
  # Return a checked conversion, degree bound and coefficient-size estimate.
  -> expand(t, axis, fuel)
    fuel[0] -= 1
    if fuel[0] < 0
      raise "polynomial sign: expression limit"
    if tm_eq(t, axis)
      return [@k.refl(t), 1, 1]
    if t.tag == :lit
      return [@k.refl(t), 0, t.val.to_s.size + 1]
    if t.tag == :app && t.a.op == OP_NEG
      child = expand(t.b, axis, fuel)
      conversion = @d.ap_term(t.a, child[0])
      if child[1] == 0
        conversion = @k.trans(conversion, @k.compute(conversion.concl.b))
      return [conversion, child[1], child[2]]
    op = t.tag == :app && t.a.tag == :app ? t.a.a.op : OP_NONE
    if [OP_ADD, OP_SUB, OP_MUL, OP_DIV, OP_POW].include?(op)
      left = expand(t.a.b, axis, fuel)
      if op == OP_POW
        if t.b.tag != :lit || t.b.val < 0 || t.b.val > 16
          raise "polynomial sign: exponent limit"
        conversion = @d.ap_thm(@d.ap_term(t.a.a, left[0]), t.b)
        degree = left[1] * t.b.val
        size = left[2] * t.b.val
      else
        right = expand(t.b, axis, fuel)
        degree = op == OP_MUL ? left[1] + right[1] : (left[1] > right[1] ? left[1] : right[1])
        size = left[2] + right[2] + 1
        if op == OP_DIV && (right[1] != 0 || ring_lit_q(right[0].concl.b, axis.ty.name)[0] == 0 || (axis.ty == TY_INT_SINGLETON && left[1] > 0))
          raise "polynomial sign: nonpolynomial quotient"
        conversion = @k.mk_comb(@d.ap_term(t.a.a, left[0]), right[0])
      if degree > 16 || size > 8192
        raise "polynomial sign: degree or coefficient limit"
      if degree == 0
        folded = @k.compute(conversion.concl.b)
        if folded.concl.b.tag != :lit
          raise "polynomial sign: unknown coefficient"
        conversion = @k.trans(conversion, folded)
      return [conversion, degree, size]
    spine = strip_app(t)
    head = spine[0]
    if head.tag != :const || @k.defs[head.name] == nil || fuel[1] <= 0
      raise "polynomial sign: nonpolynomial atom"
    fuel[1] -= 1
    conversion = @k.defs[head.name]
    spine[1].each -> (arg)
      conversion = @d.ap_thm(conversion, arg)
      conversion = @k.trans(conversion, @k.beta(conversion.concl.b))
    result = expand(conversion.concl.b, axis, fuel)
    [@k.trans(conversion, result[0]), result[1], result[2]]

  -> choose(n, k)
    value = 1
    i = 1
    while i <= k
      value = value * (n-i+1) / i
      i += 1
    value

  -> powers(q, n)
    values = [Q_ONE]
    n.times -> values.push(q_mul(values.last, q))
    values

  -> coefficients(poly, ctx)
    n = 0
    poly.each -> (mid, coeff)
      if mid != 0
        n = ctx.monos[mid][1] > n ? ctx.monos[mid][1] : n
    cs = Array.new(n+1, Q_ZERO)
    poly.each -> (mid, coeff) cs[mid == 0 ? 0 : ctx.monos[mid][1]] = coeff
    cs

  # Coefficients in u = x-lower (or upper-x on a left half-line).
  -> shifted(cs, endpoint, reverse)
    offsets = powers(endpoint, cs.size - 1)
    out = Array.new(cs.size, Q_ZERO)
    cs.each_with_index -> (coeff, j)
      if coeff[0] == 0
        next
      i = 0
      while i <= j
        weight = choose(j, i)
        if reverse && i % 2 == 1
          weight = -weight
        out[i] = q_add(out[i], q_mul(coeff, q_mul([weight, 1], offsets[j-i])))
        i += 1
    out

  # Elevate u^j to degree n using (u+v)^(n-j) = width^(n-j).
  # Subtract the least normalized weight. The removed multiple of
  # (u+v)^n is constant and can certify strictness even at the endpoints.
  -> bernstein_weights(cs, width)
    n = cs.size - 1
    widths = powers(width, n)
    weights = []
    minimum = nil
    i = 0
    while i <= n
      q = Q_ZERO
      j = 0
      while j <= i
        q = q_add(q, q_mul(q_div(cs[j], widths[n-j]), [choose(n-j, i-j), 1]))
        j += 1
      weights.push(q)
      normalized = q_div(q, [choose(n, i), 1])
      if minimum == nil || q_cmp(normalized, minimum) < 0
        minimum = normalized
      i += 1
    if minimum[0] < 0
      return nil
    i = 0
    while i <= n
      weights[i] = q_sub(weights[i], q_mul(minimum, [choose(n, i), 1]))
      i += 1
    [weights, minimum]

  -> weaken(proof)
    if proof.concl.a.a.op == OP_LE
      return proof
    law = @prover.auto_loaded_rule("le_of_lt." + @ty.name)
    @k.mp(@k.spec(proof.concl.b, @k.spec(@zero, law)), proof)

  -> product(a, b)
    strict = a.concl.a.a.op == OP_LT && b.concl.a.a.op == OP_LT
    law = strict ? @mul_pos : @mul_nonneg
    instance = @k.spec(b.concl.b, @k.spec(a.concl.b, law))
    @k.mp(@k.mp(instance, strict ? a : weaken(a)), strict ? b : weaken(b))

  # Entry zero is a sentinel: a missing factor is the multiplicative identity.
  -> sign_powers(axis, end, reverse, n)
    fact = end[2]
    minus = @k.mk_const("-", ty_funs([@ty, @ty], @ty))
    delta = reverse ? mk_apps(minus, [end[0], axis]) : mk_apps(minus, [axis, end[0]])
    target = mk_apps(fact.concl.a.a, [@zero, delta])
    sign = @prover.linarith_proof(Goal.new([], [], target), [fact])
    out = [nil, sign]
    while out.size <= n
      out.push(product(out.last, sign))
    out

  -> certificate(c, weights, left, right)
    cmp = dest_cmp_rel(c)
    opposite = @prover.auto_loaded_rule((cmp[0] == "<" ? "not_lt." : "not_le.") + @ty.name)
    negated = @k.assume(@k.neg_tm(c))
    facts = [@k.mp(@k.spec(cmp[2], @k.spec(cmp[1], opposite)), negated)]
    coeffs = [Q_ONE]
    n = weights.size - 1
    weights.each_with_index -> (weight, i)
      if weight[0] == 0
        next
      term = left[i]
      if right != nil && n-i > 0
        term = term == nil ? right[n-i] : product(term, right[n-i])
      if term != nil
        facts.push(term)
        coeffs.push(weight)
    @prover.classical_by_contra(c, @k.farkas(facts, coeffs))

  # Plan with exact coefficients first. Only replay a tree whose leaves all
  # have sign certificates. A split node holds its cut and its two children.
  -> leaf(cs, width, start_open, end_open, strict)
    if cs.all?(-> (q) q[0] >= 0)
      if !strict || cs[0][0] > 0 || start_open
        return [:power, cs]
    if width == nil
      return nil
    bs = bernstein_weights(cs, width)
    if bs == nil
      return nil
    if !strict || bs[1][0] > 0
      return [:bernstein, bs[0]]
    # A positive weight contributes strictness if every factor it uses
    # is positive on this branch.
    n = cs.size - 1
    i = 0
    while i <= n
      if bs[0][i][0] > 0 && (i == 0 || start_open) && (i == n || end_open)
        return [:bernstein, bs[0]]
      i += 1
    nil

  -> excludes_sign(value, open_end)
    value[0] < 0 || (@strict && !open_end && value[0] == 0)

  -> finite_region(lo, hi, lo_open, hi_open, budget)
    cs = shifted(@coefficients, lo, false)
    width = q_sub(hi, lo)
    # Horner evaluation at the other end cheaply rejects a false claim.
    value = evaluate_at(cs, width)
    if excludes_sign(cs[0], lo_open) || excludes_sign(value, hi_open)
      return nil
    proof = leaf(cs, width, lo_open, hi_open, @strict)
    if proof != nil || budget[0] <= 0
      return proof
    mid = q_div(q_add(lo, hi), [2, 1])
    if @ty == TY_INT_SINGLETON
      mid = [int_fdiv(mid[0], mid[1]), 1]
      if q_cmp(mid, lo) <= 0
        return nil
    budget[0] -= 1
    left = finite_region(lo, mid, lo_open, false, budget)
    if left == nil
      return nil
    right = finite_region(mid, hi, false, hi_open, budget)
    right == nil ? nil : [:split, mid, left, right]

  -> unbounded_region(start, open_end, reverse)
    cs = shifted(@coefficients, start, reverse)
    if excludes_sign(cs[0], open_end) || cs.last[0] < 0
      return nil
    whole = leaf(cs, nil, open_end, false, @strict)
    if whole != nil
      return whole
    # Find one certifiable tail, then bisect only the finite remainder.
    step = reverse ? Q_NEG_ONE : Q_ONE
    16.times ->
      cut = q_add(start, step)
      tail_cs = shifted(@coefficients, cut, reverse)
      if excludes_sign(tail_cs[0], false)
        return nil
      tail = leaf(tail_cs, nil, false, false, @strict)
      if tail != nil
        inside = reverse ? finite_region(cut, start, false, open_end, [32]) : finite_region(start, cut, open_end, false, [32])
        if inside == nil
          return nil
        return reverse ? [:split, cut, tail, inside] : [:split, cut, inside, tail]
      step = q_add(step, step)
    nil

  -> replay(node, goal, axis, lower, upper)
    if node[0] == :split
      q = node[1]
      cut = mk_lit(@ty == TY_INT_SINGLETON ? q[0] : q, @ty)
      total = @k.spec(cut, @k.spec(axis, @prover.auto_loaded_rule("le_total." + @ty.name)))
      sides = dest_binop(total.concl, "∨")
      left = replay(node[2], goal, axis, lower, [cut, q, @k.assume(sides[0])])
      right = replay(node[3], goal, axis, [cut, q, @k.assume(sides[1])], upper)
      return @k.disj_cases(total, left, right)
    n = node[1].size - 1
    start = lower == nil ? upper : lower
    left = sign_powers(axis, start, lower == nil, n)
    right = node[0] == :bernstein ? sign_powers(axis, upper, true, n) : nil
    certificate(goal, node[1], left, right)

  -> prepare(c, axis, min_degree = 2)
    fuel = [1536, 96]
    lhs = expand(c.a.b, axis, fuel)
    rhs = expand(c.b, axis, fuel)
    if lhs[1] < min_degree && rhs[1] < min_degree
      return nil
    conv = @k.mk_comb(@d.ap_term(c.a.a, lhs[0]), rhs[0])
    goal = conv.concl.b
    ctx = RingCtx.new(@ty.name)
    poly = poly_add(ring_norm(goal.b, @ty.name, ctx), poly_scale(ring_norm(goal.a.b, @ty.name, ctx), Q_NEG_ONE))
    aid = ctx.atom(axis)
    if poly.keys.any?(-> (mid) mid != 0 && (ctx.monos[mid].size != 2 || ctx.monos[mid][0] != aid))
      return nil
    if min_degree > 0 && !poly.keys.any?(-> (mid) mid != 0)
      return nil
    @coefficients = coefficients(poly, ctx)
    @strict = goal.a.a.op == OP_LT
    conv

  -> prove_axis(c, axis, ends)
    lower = ends[0]
    upper = ends[1]
    if lower != nil && upper != nil && q_cmp(lower[1], upper[1]) >= 0
      return nil
    conv = prepare(c, axis)
    if conv == nil
      return nil
    goal = conv.concl.b
    lo_open = lower != nil && lower[2].concl.a.a.op == OP_LT
    hi_open = upper != nil && upper[2].concl.a.a.op == OP_LT
    if lower != nil && upper != nil
      plan = finite_region(lower[1], upper[1], lo_open, hi_open, [32])
    elsif lower != nil
      plan = unbounded_region(lower[1], lo_open, false)
    elsif upper != nil
      plan = unbounded_region(upper[1], hi_open, true)
    else
      left = unbounded_region(Q_ZERO, false, true)
      if left == nil
        return nil
      right = unbounded_region(Q_ZERO, false, false)
      plan = right == nil ? nil : [:split, Q_ZERO, left, right]
    if plan == nil
      return nil
    @k.eq_mp(@k.sym(conv), replay(plan, goal, axis, lower, upper))

  # Build a conversion for every original guard before looking for a model.
  # Unsupported or opaque premises leave the diagnostic silent.
  -> guard_conversion(p, axis, fuel)
    if p.op == OP_TRUE || p.op == OP_FALSE
      return @k.refl(p)
    if p.tag == :app && p.a.op == OP_NOT
      return @d.ap_term(p.a, guard_conversion(p.b, axis, fuel))
    if p.tag != :app || p.a.tag != :app
      raise "counterexample: undecidable premise"
    op = p.a.a.op
    if [OP_AND, OP_OR, OP_IMP].include?(op) || (op == OP_EQ && type_of(p.b) == ty_bool)
      lhs = guard_conversion(p.a.b, axis, fuel)
      rhs = guard_conversion(p.b, axis, fuel)
    elsif [OP_LE, OP_LT, OP_EQ].include?(op) && ty_eq(type_of(p.b), axis.ty)
      lhs = expand(p.a.b, axis, fuel)[0]
      rhs = expand(p.b, axis, fuel)[0]
    else
      raise "counterexample: unsupported premise"
    @k.mk_comb(@d.ap_term(p.a.a, lhs), rhs)

  # Instantiate checked definitional conversions, then evaluate with the
  # kernel. A model has to satisfy every premise and falsify the comparison.
  -> checked_counterexample(v, axis, guards, goal)
    pairs = [[axis, v]]
    guards.each -> (rule)
      inst = @k.inst(rule, pairs)
      if @k.trans(inst, @k.compute(inst.concl.b)).concl.b.op != OP_TRUE
        return nil
    inst = @k.inst(goal, pairs)
    c = inst.concl.b
    folded = @k.mk_comb(@d.ap_term(c.a.a, @k.compute(c.a.b)), @k.compute(c.b))
    reduced = @k.trans(inst, folded)
    if reduced.concl.b.a.b.tag != :lit || reduced.concl.b.b.tag != :lit || @k.trans(reduced, @k.compute(reduced.concl.b)).concl.b.op != OP_FALSE
      return nil
    note = "  counterexample " + axis.name + " = " + tm_show(v)
    comparison = tm_show(reduced.concl.b)
    comparison.size <= 96 ? note + " (" + comparison + " is false)" : note

  -> evaluate_at(cs, q)
    value = Q_ZERO
    i = cs.size - 1
    while i >= 0
      value = q_add(cs[i], q_mul(q, value))
      i -= 1
    value

  -> counterexample(c, facts, premises)
    vars = tm_frees(c)
    if vars.size != 1
      return nil
    axis = vars[0]
    @ty = axis.ty
    if ![TY_INT_SINGLETON, TY_REAL_SINGLETON, TY_RAT_SINGLETON].include?(@ty) || !ty_eq(@ty, type_of(c.b))
      return nil
    goal = prepare(c, axis, 0)
    if goal == nil
      return nil
    fuel = [512, 32]
    guards = premises.map(-> (p) guard_conversion(p, axis, fuel))
    find_point(bounds(axis, facts), -> (v) checked_counterexample(v, axis, guards, goal))

  # Search for a point where the prepared comparison fails. The caller
  # decides whether the original statement accepts that exact numeral.
  -> find_point(ends, check)
    cs = @coefficients
    # Use Cauchy's root bound to choose a finite search window for a ray.
    # A power of two favors simple dyadic points during bisection.
    span = [2, 1]
    if (ends[0] == nil || ends[1] == nil) && cs.size > 1
      radius = Q_ONE
      cs.each -> (coeff)
        ratio = q_div(coeff, cs.last)
        ratio = q_add(Q_ONE, [ratio[0].abs, ratio[1]])
        if q_cmp(ratio, radius) > 0
          radius = ratio
      bits = (radius[0] / radius[1]).bit_length
      span = [int_pow_fast(2, bits > 128 ? 128 : bits), 1]
    lo = ends[0] == nil ? q_neg(span) : ends[0][1]
    hi = ends[1] == nil ? span : ends[1][1]
    if ends[1] == nil && q_cmp(lo, hi) >= 0
      hi = q_add(lo, Q_ONE)
    if ends[0] == nil && q_cmp(lo, hi) >= 0
      lo = q_sub(hi, Q_ONE)
    if q_cmp(lo, hi) > 0
      return nil
    try_point = -> (q)
      excludes_sign(evaluate_at(cs, q), false) ? check.call(mk_lit(@ty == TY_INT_SINGLETON ? q[0] : q, @ty)) : nil
    seeds = [Q_ZERO, Q_ONE, Q_NEG_ONE, [2, 1], [-2, 1], lo, hi]
    seeds.each -> (q)
      if q_cmp(lo, q) <= 0 && q_cmp(q, hi) <= 0
        found = try_point.call(q)
        if found != nil
          return found
    boxes = [[lo, hi]]
    i = 0
    while i < boxes.size && i < 64
      box = boxes[i]
      i += 1
      a = box[0]
      b = box[1]
      if q_cmp(a, b) >= 0
        next
      mid = q_div(q_add(a, b), [2, 1])
      if @ty == TY_INT_SINGLETON
        mid = [int_fdiv(mid[0], mid[1]), 1]
        if q_cmp(mid, a) <= 0
          next
      found = try_point.call(mid)
      if found != nil
        return found
      if leaf(shifted(@coefficients, a, false), q_sub(b, a), false, false, @strict) == nil
        boxes.push([a, mid])
        boxes.push([mid, b])
    nil

  -> existential(goal, binder)
    @ty = binder.ty
    if ![TY_INT_SINGLETON, TY_REAL_SINGLETON, TY_RAT_SINGLETON].include?(@ty) || !binder.cl
      return nil
    opened = dest_lam_fresh(binder, goal.all_terms)
    axis = opened[0]
    body = opened[1]
    parts = @prover.witness_components(body)
    if parts.size > 8
      return nil
    attempts = 0
    conversion = nil
    ends = nil
    parts.each -> (part)
      cmp = dest_cmp_rel(part)
      if cmp == nil || cmp[0] == "=" || !ty_eq(type_of(cmp[1]), @ty)
        next
      # A counterexample to b ≤ a is a witness for a < b, and conversely.
      opposite = @k.mk_const(cmp[0] == "<" ? "≤" : "<", type_of(part.a.a))
      if prepare(mk_apps(opposite, [cmp[2], cmp[1]]), axis) == nil
        next
      if conversion == nil
        conversion = guard_conversion(body, axis, [1536, 96])
        ends = bounds(axis, parts.map(-> (p) @k.assume(p)))
      check = -> (v)
        inst = @k.inst(conversion, [[axis, v]])
        ev = @k.trans(inst, @k.compute(inst.concl.b))
        ev.concl.b.op == OP_TRUE ? @k.exists_intro(goal.concl, v, @d.eqt_elim(ev)) : nil
      point = find_point(ends, check)
      attempts += 1
      if point != nil || attempts >= 3
        return point
    nil

  # A region is impossible if one of its input comparisons is violated.
  # Save the conversion as well as the coefficients for checked replay.
  -> violation_rule(fact, axis, reverse)
    cmp = dest_cmp_rel(fact.concl)
    a = reverse ? cmp[2] : cmp[1]
    b = reverse ? cmp[1] : cmp[2]
    rel = @k.mk_const(cmp[0] == "<" ? "≤" : "<", ty_funs([@ty, @ty], ty_bool))
    begin
      conv = prepare(mk_apps(rel, [b, a]), axis)
      conv == nil ? nil : PolynomialViolation.new(conv, fact, reverse ? Q_NEG_ONE : Q_ONE, @coefficients, @strict)
    rescue unsupported_polynomial
      nil

  -> violation_at(rules, q)
    rules.each -> (rule)
      value = evaluate_at(rule.coefficients, q)
      if value[0] > 0 || (!rule.strict && value[0] == 0)
        return rule
    nil

  # Plan on open halves and check the cut separately. This also handles
  # adjacent regions meeting at a root where a weak inequality is sharp.
  -> cover_region(rules, lo, hi, lo_open, hi_open, step, budget)
    if lo != nil || hi != nil
      start = lo == nil ? hi : lo
      width = lo == nil || hi == nil ? nil : q_sub(hi, lo)
      rules.each -> (rule)
        cs = shifted(rule.coefficients, start, lo == nil)
        weights = leaf(cs, width, lo == nil ? hi_open : lo_open, hi_open, rule.strict)
        if weights != nil
          return [:violation, rule, weights]
    if budget[0] <= 0
      return nil
    cut = Q_ZERO
    if lo != nil && hi != nil
      cut = q_div(q_add(lo, hi), [2, 1])
      if @ty == TY_INT_SINGLETON
        if lo_open && hi_open && hi[0] == lo[0] + 1
          return [:integer_gap]
        cut = [int_fdiv(cut[0], cut[1]), 1]
      if q_cmp(cut, lo) <= 0 || q_cmp(cut, hi) >= 0
        return nil
    elsif lo != nil
      cut = q_add(lo, step)
    elsif hi != nil
      cut = q_sub(hi, step)
    center = violation_at(rules, cut)
    if center == nil
      return nil
    budget[0] -= 1
    stride = q_add(step, step)
    left = cover_region(rules, lo, cut, lo_open, true, stride, budget)
    if left == nil
      return nil
    right = cover_region(rules, cut, hi, true, hi_open, stride, budget)
    right == nil ? nil : [:cut, cut, center, left, right]

  -> refute(rule, proof)
    opposite = @k.eq_mp(@k.sym(rule.conversion), proof)
    @k.farkas([rule.fact, opposite], [rule.weight, Q_ONE])

  -> replay_cover(node, axis, lower, upper)
    if node[0] == :integer_gap
      steps = @prover.integer_strengthen([lower[2], upper[2]], @ty)
      return @k.farkas(steps, [Q_ONE, Q_ONE])
    if node[0] == :violation
      rule = node[1]
      return refute(rule, replay(node[2], rule.conversion.concl.b, axis, lower, upper))
    q = node[1]
    cut = mk_lit(@ty == TY_INT_SINGLETON ? q[0] : q, @ty)
    lt = @k.mk_const("<", ty_funs([@ty, @ty], ty_bool))
    before = mk_apps(lt, [axis, cut])
    after = mk_apps(lt, [cut, axis])
    left = replay_cover(node[3], axis, lower, [cut, q, @k.assume(before)])
    right = replay_cover(node[4], axis, [cut, q, @k.assume(after)], upper)
    le = @prover.auto_loaded_rule("not_lt." + @ty.name)
    hi = @k.mp(@k.spec(axis, @k.spec(cut, le)), @k.assume(@k.neg_tm(after)))
    lo = @k.mp(@k.spec(cut, @k.spec(axis, le)), @k.assume(@k.neg_tm(before)))
    antisym = @prover.auto_loaded_rule("le_antisymm." + @ty.name)
    eq = @k.mp(@k.mp(@k.spec(cut, @k.spec(axis, antisym)), hi), lo)
    rule = node[2]
    at_cut = @prover.replace_conv(rule.conversion.concl.b, axis, eq)
    value = @d.eqt_elim(@k.compute(at_cut.concl.b))
    center = refute(rule, @k.eq_mp(@k.sym(at_cut), value))
    @k.disj_cases(@k.excluded_middle(before), left, @k.disj_cases(@k.excluded_middle(after), right, center))

  -> guarded(c, axis, facts)
    rules = []
    i = 0
    while i < facts.size && rules.size < 6
      fact = facts[i]
      i += 1
      cmp = dest_cmp_rel(fact.concl)
      if cmp == nil || !ty_eq(type_of(cmp[1]), @ty) || (cmp[1].tag != :app && cmp[2].tag != :app)
        next
      vs = tm_frees(fact.concl)
      if vs.size != 1 || !tm_eq(vs[0], axis)
        next
      rule = violation_rule(fact, axis, false)
      if rule != nil
        rules.push(rule)
        if cmp[0] == "="
          other = violation_rule(fact, axis, true)
          if other != nil
            rules.push(other)
    if rules.empty?()
      return nil
    conversion = prepare(c, axis, 0)
    if conversion == nil
      return nil
    c = conversion.concl.b
    neg = @k.assume(@k.neg_tm(c))
    law = @prover.auto_loaded_rule((c.a.a.op == OP_LT ? "not_lt." : "not_le.") + @ty.name)
    opposite = @k.mp(@k.spec(c.b, @k.spec(c.a.b, law)), neg)
    ends = bounds(axis, facts + [opposite])
    if @coefficients.size > 1
      rules.push(PolynomialViolation.new(@k.refl(c), opposite, Q_ONE, @coefficients, @strict))
    lo = ends[0]
    hi = ends[1]
    if lo != nil && hi != nil && q_cmp(lo[1], hi[1]) >= 0
      return nil
    lo_open = lo != nil && lo[2].concl.a.a.op == OP_LT
    hi_open = hi != nil && hi[2].concl.a.a.op == OP_LT
    if (lo != nil && !lo_open && violation_at(rules, lo[1]) == nil) || (hi != nil && !hi_open && violation_at(rules, hi[1]) == nil)
      return nil
    plan = cover_region(rules, lo == nil ? nil : lo[1], hi == nil ? nil : hi[1], lo_open, hi_open, Q_ONE, [32])
    if plan == nil
      return nil
    proof = @prover.classical_by_contra(c, replay_cover(plan, axis, lo, hi))
    @k.eq_mp(@k.sym(conversion), proof)

  -> prove(c, facts)
    cmp = dest_cmp_rel(c)
    if cmp == nil || cmp[0] == "="
      return nil
    @ty = type_of(cmp[1])
    if ![TY_RAT_SINGLETON, TY_REAL_SINGLETON, TY_INT_SINGLETON].include?(@ty)
      return nil
    axes = tm_frees(c).select(-> (v) ty_eq(v.ty, @ty))
    if axes.size == 1
      axis = axes[0]
      ends = bounds(axis, facts)
    else
      # A transparent function may discard an argument when unfolded.
      # Try it only if the hypotheses single out one bounded variable.
      axis = nil
      axes.each -> (v)
        candidate = bounds(v, facts)
        if candidate[0] != nil || candidate[1] != nil
          if axis != nil
            return nil
          axis = v
          ends = candidate
      if axis == nil
        return nil
    @zero = @prover.model_integer(@ty, 0)
    @mul_nonneg = @prover.auto_loaded_rule("mul_nonneg." + @ty.name)
    @mul_pos = @prover.auto_loaded_rule("mul_pos." + @ty.name)
    direct = prove_axis(c, axis, ends)
    direct == nil ? guarded(c, axis, facts) : direct
