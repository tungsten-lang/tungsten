# Finitely presented groups, their abelianisations, and Seifert fibrations.
#
# A presentation <x_1..x_n | r_1..r_k> abelianises to the cokernel of its
# relation matrix: the n x k integer matrix whose column j records the
# exponent sum of each generator in the relator r_j. Smith normal form then
# reads off H_1 = G^ab as Z^free (+) torsion. That is the whole of the
# computable content of most van Kampen arguments — the group itself may be
# undecidable, its abelianisation never is.
#
# Words are arrays of [generator, exponent] pairs, generators numbered from 0.

+ FinitelyPresentedGroup
  -> new(generator_count, relators)
    raise "a presentation needs a nonnegative generator count" if generator_count < 0
    @generator_count = generator_count
    @relators = []
    relators.each ->(word)
      @relators.push(FinitelyPresentedGroup.validate_word(generator_count, word))
    @abelianization_cache = nil

  -> .validate_word(generator_count, word)
    raise "a relator must be an array of [generator, exponent] pairs" if word.class_name != "Array"
    out = []
    word.each ->(letter)
      if letter.class_name != "Array" || letter.size != 2
        raise "a relator letter is a [generator, exponent] pair"
      g = letter[0]
      e = letter[1]
      raise "generator index out of range" if g < 0 || g >= generator_count
      out.push([g, e]) if e != 0
    out

  # --- constructors ---

  -> .free(rank)
    FinitelyPresentedGroup.new(rank, [])

  -> .cyclic(order)
    FinitelyPresentedGroup.new(1, [[[0, order]]])

  -> .free_abelian(rank)
    relators = []
    i = 0
    while i < rank
      j = i + 1
      while j < rank
        relators.push(FinitelyPresentedGroup.commutator(i, j))
        j += 1
      i += 1
    FinitelyPresentedGroup.new(rank, relators)

  # The word x y x^-1 y^-1.
  -> .commutator(x, y)
    [[x, 1], [y, 1], [x, -1], [y, -1]]

  # --- structure ---

  -> generator_count
    @generator_count

  -> relators
    @relators

  -> relator_count
    @relators.size

  -> exponent_sums(word)
    out = []
    i = 0
    while i < @generator_count
      out.push(0)
      i += 1
    word.each ->(letter)
      out[letter[0]] = out[letter[0]] + letter[1]
    out

  # generator_count x relator_count; columns are relators.
  -> relation_matrix
    out = []
    i = 0
    while i < @generator_count
      out.push([])
      i += 1
    @relators.each ->(word)
      sums = exponent_sums(word)
      i = 0
      while i < @generator_count
        out[i].push(sums[i])
        i += 1
    out

  -> abelianization
    return @abelianization_cache if @abelianization_cache != nil
    if @generator_count == 0
      @abelianization_cache = FinitelyGeneratedAbelianGroup.trivial
    elsif @relators.size == 0
      @abelianization_cache = FinitelyGeneratedAbelianGroup.free(@generator_count)
    else
      @abelianization_cache = FinitelyGeneratedAbelianGroup.from_relations(relation_matrix)
    @abelianization_cache

  -> first_homology
    abelianization

  # Order of the abelianisation, 0 when infinite.
  -> abelian_order
    abelianization.order

  -> perfect?
    abelianization.trivial?

  -> to_s
    "FinitelyPresentedGroup(" + @generator_count.to_s + " generators, " + @relators.size.to_s + " relators)"

  -> inspect
    to_s

# A Seifert fibration over the 2-sphere with unnormalised Seifert invariants
# (a_1, b_1), ..., (a_n, b_n) and obstruction class e0, in the convention
#
#   pi_1 = < h, q_1..q_n | h central, q_i^a_i h^b_i, q_1 ... q_n h^-e0 >,
#
# so that (Orlik) |H_1| = |e0 a_1...a_n + sum_i b_i prod_{j != i} a_j|, the
# rational Euler number being e0 + sum b_i / a_i. The paper's threefold X has
# pi_1(X) = < c, x, y | c central, x y = c^l0, x^3 = c^l1, y^4 = c^l2 >, which
# is this group for (a, b) = (3, -l1), (4, -l2) and e0 = l0.

+ SeifertFibration
  -> new(obstruction, invariants)
    @obstruction = obstruction
    @invariants = []
    invariants.each ->(pair)
      if pair.class_name != "Array" || pair.size != 2
        raise "a Seifert invariant is an [a, b] pair"
      raise "Seifert multiplicities must be positive" if pair[0] < 1
      @invariants.push([pair[0], pair[1]])
    @group_cache = nil

  # The three-sphere with the circle action (z, w) -> (l^p z, l^q w) for
  # coprime p, q: exceptional fibres of multiplicities p and q, and Seifert
  # invariants any (p, b1), (q, b2) with q b1 + p b2 = +-1 (Bezout).
  -> .three_sphere(p, q)
    raise "three_sphere needs coprime multiplicities" if p.gcd(q) != 1
    b1 = 0
    remainder = 0
    found = false
    while !found
      remainder = 1 - q * b1
      if remainder % p == 0
        found = true
      else
        remainder = 0 - 1 - q * b1
        if remainder % p == 0
          found = true
        else
          b1 += 1
    b2 = remainder / p
    SeifertFibration.new(0, [[p, b1], [q, b2]])

  # Poincare's homology sphere: e0 = -1, invariants (2,1), (3,1), (5,1).
  -> .poincare_sphere
    SeifertFibration.new(0 - 1, [[2, 1], [3, 1], [5, 1]])

  -> obstruction
    @obstruction

  -> invariants
    @invariants

  -> exceptional_fibre_count
    @invariants.size

  -> multiplicities
    out = []
    @invariants.each ->(pair)
      out.push(pair[0])
    out

  # Generators: h is 0, q_i is i (1-based over the invariants).
  -> fundamental_group
    return @group_cache if @group_cache != nil
    n = @invariants.size
    relators = []
    i = 0
    while i < n
      relators.push(FinitelyPresentedGroup.commutator(0, i + 1))
      relators.push([[i + 1, @invariants[i][0]], [0, @invariants[i][1]]])
      i += 1
    product = []
    i = 0
    while i < n
      product.push([i + 1, 1])
      i += 1
    product.push([0, 0 - @obstruction])
    relators.push(product)
    @group_cache = FinitelyPresentedGroup.new(n + 1, relators)
    @group_cache

  -> first_homology
    fundamental_group.abelianization

  -> first_homology_order
    first_homology.order

  # Orlik's closed formula, independent of the presentation.
  -> first_homology_order_formula
    total = @obstruction
    @invariants.each ->(pair)
      total = total * pair[0]
    i = 0
    while i < @invariants.size
      term = @invariants[i][1]
      j = 0
      while j < @invariants.size
        term = term * @invariants[j][0] if j != i
        j += 1
      total += term
      i += 1
    total < 0 ? 0 - total : total

  # The rational Euler number e0 + sum b_i / a_i as a reduced [num, den].
  -> euler_number
    num = @obstruction
    den = 1
    @invariants.each ->(pair)
      num = num * pair[0] + pair[1] * den
      den = den * pair[0]
    g = num.gcd(den)
    g = 0 - g if g < 0
    g = 1 if g == 0
    [num / g, den / g]

  -> homology_sphere?
    first_homology_order == 1

  -> to_s
    "SeifertFibration(e0 " + @obstruction.to_s + ", " + @invariants.to_s + ")"

  -> inspect
    to_s
