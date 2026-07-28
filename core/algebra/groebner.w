# Buchberger reduction and finitely generated polynomial ideals.

+ GroebnerBasis
  -> new(generators, pair_limit = 20_000)
    @generators = generators
    @polynomials = GroebnerBasis.basis(generators, pair_limit)

  -> source_generators
    @generators

  -> generators
    @generators

  -> polynomials
    @polynomials

  -> size
    @polynomials.size

  -> [](index)
    @polynomials[index]

  -> reduce(polynomial)
    polynomial.normal_form(@polynomials)

  -> contains?(polynomial)
    reduce(polynomial).zero?

  -> unit?
    @polynomials.size == 1 && @polynomials[0].one?

  -> .same_monomial?(left, right)
    return false if left.size != right.size
    i = 0
    while i < left.size
      return false if left[i] != right[i]
      i += 1
    true

  -> .monomial_divides?(divisor, dividend)
    i = 0
    while i < divisor.size
      return false if divisor[i] > dividend[i]
      i += 1
    true

  -> .relatively_prime?(left, right)
    i = 0
    while i < left.size
      return false if left[i] > 0 && right[i] > 0
      i += 1
    true

  -> .validate_generators(generators)
    raise "a Gröbner basis needs at least one generator" if generators.size == 0
    ring = nil
    generators.each ->
      raise "Gröbner generators must be polynomials" if item.class_name != "Polynomial"
      ring = item.ring if ring == nil
      raise "Gröbner generators belong to different rings" if item.ring != ring
    ring

  -> .s_polynomial(left, right)
    raise "S-polynomials require a common polynomial ring" if left.ring != right.ring
    raise "S-polynomial of zero is undefined" if left.zero? || right.zero?
    llt = left.leading_term
    rlt = right.leading_term
    lp = []
    rp = []
    i = 0
    while i < left.ring.arity
      lcm = llt[1][i] > rlt[1][i] ? llt[1][i] : rlt[1][i]
      lp.push(lcm - llt[1][i])
      rp.push(lcm - rlt[1][i])
      i += 1
    left.monomial_multiply_raw(
      lp, left.ring.field.divide(left.ring.field.one, llt[0])) - right.monomial_multiply_raw(
      rp, right.ring.field.divide(right.ring.field.one, rlt[0]))

  -> .monomial_lcm(left, right)
    out = []
    i = 0
    while i < left.size
      out.push(left[i] > right[i] ? left[i] : right[i])
      i += 1
    out

  -> .pair_key(i, j)
    i < j ? (i.to_s + ":" + j.to_s) : (j.to_s + ":" + i.to_s)

  # Buchberger's second criterion (the chain criterion): a selected pair
  # (i, j) is redundant when some third basis element's leading term divides
  # lcm(lt_i, lt_j) and both mixed pairs (i, k) and (j, k) have already left
  # the pending set — their treatment links the i and j syzygies through k.
  # This is the Cox–Little–O'Shea improved-Buchberger formulation, tested
  # after the pair itself is removed from the pending set.
  -> .chain_redundant?(basis, pending, pair)
    k = 0
    while k < basis.size
      if k != pair[0] && k != pair[1]
        if GroebnerBasis.monomial_divides?(basis[k].leading_term[1], pair[2])
          left_key = GroebnerBasis.pair_key(pair[0], k)
          right_key = GroebnerBasis.pair_key(pair[1], k)
          return true if !pending.has_key?(left_key) && !pending.has_key?(right_key)
      k += 1
    false

  # Buchberger's algorithm with the classical pair pruning:
  #   - normal selection strategy: always process the pending pair whose
  #     leading-term lcm is smallest in the ring's monomial order, which
  #     keeps reductions low-degree and surfaces constant remainders early;
  #   - product criterion: a pair with coprime leading monomials reduces to
  #     zero (Buchberger's first criterion);
  #   - chain criterion: see chain_redundant? above.
  # Pairs are decorated with their lcm ([i, j, lcm-exponents]) so selection
  # and the chain test never recompute it.
  -> .buchberger(generators, pair_limit = 20_000)
    GroebnerBasis.validate_generators(generators)
    basis = []
    generator_index = 0
    while generator_index < generators.size
      generator = generators[generator_index]
      if !generator.zero?
        reduced = generator.normal_form(basis)
        if !reduced.zero?
          reduced = reduced.monic
          return [reduced] if reduced.constant?
          basis.push(reduced)
      generator_index += 1
    return [generators[0].ring.one] if basis.size == 1 && basis[0].constant?
    # All generators reduced to zero (the zero ideal): nothing to pair.
    return basis if basis.size == 0
    ring = basis[0].ring
    pairs = []
    pending = {}
    i = 0
    while i < basis.size
      j = 0
      while j < i
        pairs.push([j, i, GroebnerBasis.monomial_lcm(
          basis[j].leading_term[1], basis[i].leading_term[1])])
        pending[GroebnerBasis.pair_key(j, i)] = true
        j += 1
      i += 1
    processed = 0
    while pairs.size > 0
      raise "Gröbner pair limit exceeded" if processed >= pair_limit
      best = 0
      i = 1
      while i < pairs.size
        best = i if ring.monomial_compare(pairs[i][2], pairs[best][2]) < 0
        i += 1
      pair = pairs.delete_at(best)
      pending.delete(GroebnerBasis.pair_key(pair[0], pair[1]))
      processed += 1
      left = basis[pair[0]]
      right = basis[pair[1]]
      next if GroebnerBasis.relatively_prime?(
        left.leading_term[1], right.leading_term[1])
      next if GroebnerBasis.chain_redundant?(basis, pending, pair)
      remainder = GroebnerBasis.s_polynomial(left, right).normal_form(basis)
      if !remainder.zero?
        remainder = remainder.monic
        return [remainder] if remainder.constant?
        new_index = basis.size
        basis.push(remainder)
        j = 0
        while j < new_index
          pairs.push([j, new_index, GroebnerBasis.monomial_lcm(
            basis[j].leading_term[1], remainder.leading_term[1])])
          pending[GroebnerBasis.pair_key(j, new_index)] = true
          j += 1
    basis

  -> .minimal_basis(generators)
    result = []
    i = 0
    while i < generators.size
      term = generators[i].leading_term
      keep = true
      j = 0
      while j < generators.size
        if i != j
          candidate = generators[j].leading_term
          if GroebnerBasis.monomial_divides?(candidate[1], term[1])
            same = GroebnerBasis.same_monomial?(candidate[1], term[1])
            keep = false if !same || j < i
        j += 1
      result.push(generators[i].monic) if keep
      i += 1
    result

  -> .sort_basis(basis)
    result = []
    basis.each -> result.push(item)
    i = 1
    while i < result.size
      j = i
      while j > 0 && result[j].ring.monomial_compare(
          result[j].leading_term[1], result[j - 1].leading_term[1]) > 0
        temporary = result[j - 1]
        result[j - 1] = result[j]
        result[j] = temporary
        j -= 1
      i += 1
    result

  -> .reduced_basis(generators, pair_limit = 20_000)
    raw = GroebnerBasis.buchberger(generators, pair_limit)
    return [raw[0].ring.one] if raw.size == 1 && raw[0].constant?
    minimal = GroebnerBasis.minimal_basis(raw)
    result = []
    i = 0
    while i < minimal.size
      others = []
      j = 0
      while j < minimal.size
        others.push(minimal[j]) if i != j
        j += 1
      reduced = minimal[i].normal_form(others)
      result.push(reduced.monic) if !reduced.zero?
      i += 1
    GroebnerBasis.sort_basis(result)

  -> .basis(generators, pair_limit = 20_000)
    GroebnerBasis.reduced_basis(generators, pair_limit)

  -> .unit_ideal?(generators)
    result = GroebnerBasis.basis(generators)
    result.size == 1 && result[0].one?


+ Ideal
  -> new(generators)
    raise "an ideal needs at least one generator; use Ideal.zero(ring)" if generators.size == 0
    @ring = nil
    @generators = []
    generators.each ->
      raise "ideal generators must be polynomials" if item.class_name != "Polynomial"
      @ring = item.ring if @ring == nil
      raise "ideal generators belong to different rings" if item.ring != @ring
      @generators.push(item)
    @basis_cache = nil

  -> ring
    @ring

  -> source_generators
    @generators

  -> generators
    @generators

  -> .zero(ring)
    Ideal.new([ring.zero])

  -> .unit(ring)
    Ideal.new([ring.one])

  -> basis
    if @basis_cache == nil
      @basis_cache = GroebnerBasis.basis(@generators)
    @basis_cache

  -> groebner_basis
    self.basis

  -> reduce(polynomial)
    @ring.coerce(polynomial).normal_form(self.basis)

  -> normal_form(polynomial)
    reduce(polynomial)

  -> contains?(polynomial)
    reduce(polynomial).zero?

  -> include?(polynomial)
    contains?(polynomial)

  -> unit?
    result = self.basis
    result.size == 1 && result[0].one?

  -> unit_ideal?
    unit?

  -> proper?
    !unit?

  -> zero?
    result = self.basis
    result.size == 0 || (result.size == 1 && result[0].zero?)

  -> +(other)
    raise "cannot add ideals from different rings" if other.ring != @ring
    Ideal.new(@generators + other.source_generators)

  -> ==/1
    self.eql?(@1)

  -> eql?(other)
    return false if other.class_name != "Ideal" || other.ring != @ring
    i = 0
    while i < @generators.size
      return false if !other.contains?(@generators[i])
      i += 1
    i = 0
    while i < other.source_generators.size
      return false if !contains?(other.source_generators[i])
      i += 1
    true

  # Elimination ideal I ∩ k[x_k, ..., x_{n-1}] for a ring ordered so the first
  # `count` variables are the ones being eliminated.  The ring's monomial order
  # must eliminate those variables (lex with those first, or a product order
  # with the same split); otherwise the result is only a subset of the true
  # elimination ideal.
  -> eliminate(count)
    raise "elimination count must be nonnegative" if count < 0
    raise "elimination count exceeds ring arity" if count > @ring.arity
    remaining_names = []
    i = count
    while i < @ring.arity
      remaining_names.push(@ring.names[i])
      i += 1
    if remaining_names.size == 0
      return unit? ? Ideal.unit(@ring) : Ideal.zero(@ring)
    remaining_order = @ring.order
    if @ring.order.name == "product" && @ring.order.split == count
      remaining_order = @ring.order.right
    remaining_ring = PolynomialRing.new(remaining_names, @ring.field, remaining_order)
    kept = []
    self.basis.each -> (poly)
      if poly.degree_in_prefix(count) == 0
        kept.push(poly.drop_variables(count, remaining_ring))
    return Ideal.zero(remaining_ring) if kept.size == 0
    Ideal.new(kept)

  # Colon / saturation I : f^∞ = { g | ∃k. g f^k ∈ I }.  Computed from a
  # Gröbner basis of I + ⟨t f - 1⟩ by eliminating the auxiliary tag t under a
  # product order that puts t first (Cox–Little–O'Shea, §4.4).
  -> colon(element)
    f = @ring.coerce(element)
    return Ideal.unit(@ring) if unit?
    if f.zero?
      return contains?(@ring.zero) ? Ideal.unit(@ring) : Ideal.zero(@ring)
    return self if f.constant? && !f.zero?
    tagged_names = [("__t").to_sym]
    @ring.names.each -> tagged_names.push(item)
    tagged = PolynomialRing.new(
      tagged_names, @ring.field, MonomialOrder.product(1, :lex, @ring.order))
    t = tagged.generator(0)
    lifted = []
    @generators.each -> lifted.push(item.lift_variables(1, tagged))
    lifted.push(t * f.lift_variables(1, tagged) - tagged.one)
    eliminated = Ideal.new(lifted).eliminate(1)
    return Ideal.unit(@ring) if eliminated.unit?
    return Ideal.zero(@ring) if eliminated.zero?
    rebound = []
    eliminated.source_generators.each -> rebound.push(item.rename_into(@ring))
    Ideal.new(rebound)

  # Saturation I : f^∞ = ∪_k (I : f^k).  The single tagged construction
  # I + ⟨t f - 1⟩ eliminates to I : f^∞ (not merely I : f).
  -> saturate(element)
    colon(element)

  -> saturation(element)
    saturate(element)

  # Saturate by every coordinate: I : (x0,...,x_{n-1})^∞.  A homogeneous ideal
  # cuts out the empty projective scheme iff this saturation is the unit ideal.
  -> saturate_irrelevant
    result = self
    i = 0
    while i < @ring.arity
      result = result.saturate(@ring.generator(i))
      return result if result.unit?
      i += 1
    result

  -> to_s
    pieces = []
    @generators.each -> pieces.push(item.to_s)
    "Ideal(" + pieces.join(", ") + ")"

  -> inspect
    to_s
