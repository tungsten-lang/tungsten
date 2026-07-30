# Exact weight-two Manin-symbol quotients for Gamma_0(N).
#
# The producer exhausts P^1(Z/NZ), materializes the S and order-three Manin
# relations, and constructs the cusp-boundary map. Dimensions use Manin's
# presentation theorem as an explicit non-kernel-checked trust boundary.
# Exact rational basis extraction is deliberately lazy and resource-bounded.

+ ModularSymbolsLinearAlgebra
  -> .copy_matrix(matrix)
    out = []
    matrix.each -> (row)
      copied = []
      row.each -> (entry)
        copied.push(Rational.coerce(entry))
      out.push(copied)
    out

  -> .zero_vector(size)
    out = []
    i = 0
    while i < size
      out.push(Rational.new(0))
      i += 1
    out

  -> .zero_integer_vector(size)
    out = []
    i = 0
    while i < size
      out.push(0)
      i += 1
    out

  -> .rref(matrix)
    work = ModularSymbolsLinearAlgebra.copy_matrix(matrix)
    return [work, []] if work.size == 0
    columns = work[0].size
    row = 0
    column = 0
    pivots = []
    while row < work.size && column < columns
      pivot = row
      while pivot < work.size && work[pivot][column].zero?
        pivot += 1
      if pivot == work.size
        column += 1
      else
        if pivot != row
          temporary = work[row]
          work[row] = work[pivot]
          work[pivot] = temporary
        pivot_value = work[row][column]
        j = column
        while j < columns
          work[row][j] = work[row][j] / pivot_value
          j += 1
        i = 0
        while i < work.size
          if i != row && !work[i][column].zero?
            factor = work[i][column]
            j = column
            while j < columns
              work[i][j] = work[i][j] - factor*work[row][j]
              j += 1
          i += 1
        pivots.push(column)
        row += 1
        column += 1
    [work, pivots]

  -> .rank(matrix)
    ModularSymbolsLinearAlgebra.rref(matrix)[1].size

  -> .nullspace(matrix, columns = nil)
    if matrix.size == 0
      raise "nullspace needs an explicit column count" if columns == nil
      basis = []
      i = 0
      while i < columns
        vector = ModularSymbolsLinearAlgebra.zero_vector(columns)
        vector[i] = Rational.new(1)
        basis.push(vector)
        i += 1
      return basis
    reduced = ModularSymbolsLinearAlgebra.rref(matrix)
    rref = reduced[0]
    pivots = reduced[1]
    width = matrix[0].size
    pivot_set = {}
    pivots.each -> (pivot)
      pivot_set[pivot.to_s] = true
    basis = []
    free = 0
    while free < width
      if pivot_set[free.to_s] == nil
        vector = ModularSymbolsLinearAlgebra.zero_vector(width)
        vector[free] = Rational.new(1)
        i = 0
        while i < pivots.size
          vector[pivots[i]] = 0 - rref[i][free]
          i += 1
        basis.push(vector)
      free += 1
    basis

  -> .same_vector?(left, right)
    return false if left.size != right.size
    i = 0
    while i < left.size
      return false if Rational.coerce(left[i]) != Rational.coerce(right[i])
      i += 1
    true

  -> .same_matrix?(left, right)
    return false if left.size != right.size
    i = 0
    while i < left.size
      return false if !ModularSymbolsLinearAlgebra.same_vector?(
        left[i], right[i])
      i += 1
    true

  -> .same_sparse_relations?(left, right)
    return false if left.size != right.size
    i = 0
    while i < left.size
      lrow = left[i]
      rrow = right[i]
      return false if lrow.size != rrow.size
      j = 0
      while j < lrow.size
        return false if lrow[j][0] != rrow[j][0]
        return false if lrow[j][1] != rrow[j][1]
        j += 1
      i += 1
    true

  -> .matrix_vector(matrix, vector)
    out = []
    matrix.each -> (row)
      raise "matrix/vector arity mismatch" if row.size != vector.size
      value = Rational.new(0)
      i = 0
      while i < row.size
        value += Rational.coerce(row[i])*Rational.coerce(vector[i])
        i += 1
      out.push(value)
    out

+ Gamma0ProjectiveLine
  -> new(group, @search_limit = 1_000_000)
    @group = group.class_name == "Gamma0" ? group : Gamma0.new(group)
    @level = @group.level
    @units = []
    if @level == 1
      @units.push(0)
    else
      candidate = 1
      while candidate < @level
        @units.push(candidate) if candidate.gcd(@level) == 1
        candidate += 1
    estimated = @level**2 + @group.index*@units.size
    if estimated > @search_limit
      raise "Manin-symbol enumeration unknown: projective-line search exceeds limit"

    @pairs = []
    @index_by_key = {}
    @prime_level = @level.prime?
    if @prime_level
      @pairs.push([0, 1])
      d = 0
      while d < @level
        @pairs.push([1, d])
        d += 1
    else
      visited = {}
      c = 0
      while c < @level
        d = 0
        while d < @level
          key = Gamma0ProjectiveLine.pair_key(c, d, @level)
          primitive = c.gcd(d).gcd(@level) == 1
          if primitive && visited[key] == nil
            orbit = []
            @units.each -> (unit)
              cc = @level == 1 ? 0 : (unit*c) % @level
              dd = @level == 1 ? 0 : (unit*d) % @level
              orbit.push([cc, dd])
            canonical = orbit[0]
            orbit.each -> (pair)
              if Gamma0ProjectiveLine.pair_less?(pair, canonical)
                canonical = pair
            index = @pairs.size
            @pairs.push(canonical)
            orbit.each -> (pair)
              orbit_key = Gamma0ProjectiveLine.pair_key(
                pair[0], pair[1], @level)
              visited[orbit_key] = true
              @index_by_key[orbit_key] = index
          d += 1
        c += 1
    @certificate = Gamma0ProjectiveLineCertificate.new(self)
    if !@certificate.verified?
      raise "Gamma0 projective-line certificate failed"

  -> .pair_key(c, d, level)
    c*level + d

  -> .pair_less?(left, right)
    return true if left[0] < right[0]
    left[0] == right[0] && left[1] < right[1]

  -> group
    @group

  -> level
    @level

  -> units
    out = []
    @units.each -> (unit)
      out.push(unit)
    out

  -> pairs
    out = []
    @pairs.each -> (pair)
      out.push([pair[0], pair[1]])
    out

  -> size
    @pairs.size

  -> normalize(value)
    @level == 1 ? 0 : ((value % @level) + @level) % @level

  -> index_of(c, d)
    cc = normalize(c)
    dd = normalize(d)
    if @prime_level
      if cc == 0
        raise "pair is not primitive in P1(Z/NZ)" if dd == 0
        return 0
      return 1 + (dd*cc.invmod(@level)) % @level
    key = Gamma0ProjectiveLine.pair_key(cc, dd, @level)
    index = @index_by_key[key]
    raise "pair is not primitive in P1(Z/NZ)" if index == nil
    index

  -> pair(index)
    source = @pairs[index]
    [source[0], source[1]]

  -> certificate
    @certificate

  -> certified?
    @certificate.verified?

  -> to_s
    "P1(Z/" + @level.to_s + "Z)"

  -> inspect
    to_s


+ Gamma0ProjectiveLineCertificate
  -> new(@line)
    @verified_cache = nil

  -> line
    @line

  -> theorem
    "Gamma_0(N) right cosets are P^1(Z/NZ)"

  -> proof_kind
    :trusted_theorem_import

  -> kernel_checked?
    false

  -> arithmetic_replay_checked?
    verified?

  -> verified?
    return @verified_cache if @verified_cache != nil
    answer = false
    begin
      answer = verify!
    rescue error
      answer = false
    @verified_cache = answer
    answer

  -> verify!
    return false if @line.class_name != "Gamma0ProjectiveLine"
    return false if !@line.group.certificate.verified?
    return false if @line.size != @line.group.index
    pairs = @line.pairs
    units = @line.units
    i = 0
    while i < pairs.size
      pair = pairs[i]
      return false if pair[0].gcd(pair[1]).gcd(@line.level) != 1
      return false if @line.index_of(pair[0], pair[1]) != i
      if !@line.level.prime?
        units.each -> (unit)
          cc = @line.level == 1 ? 0 : (unit*pair[0]) % @line.level
          dd = @line.level == 1 ? 0 : (unit*pair[1]) % @line.level
          return false if @line.index_of(cc, dd) != i
      i += 1
    true

  -> certified?
    verified?

  -> to_s
    "Gamma0ProjectiveLineCertificate(N=" + @line.level.to_s + ")"

  -> inspect
    to_s


+ Gamma0Cusp
  -> new(@group, @denominator_class, @residue)
    if @group.class_name != "Gamma0"
      raise "Gamma0 cusp needs a Gamma0 group"
    if @group.level % @denominator_class != 0
      raise "Gamma0 cusp denominator class must divide the level"
    modulus = @denominator_class.gcd(
      @group.level / @denominator_class)
    expected = modulus == 1 ? 0 : ((@residue % modulus) + modulus) % modulus
    if @residue != expected
      raise "Gamma0 cusp residue is not normalized"
    if modulus > 1 && @residue.gcd(modulus) != 1
      raise "Gamma0 cusp residue must be a unit"

  -> group
    @group

  -> denominator_class
    @denominator_class

  -> residue
    @residue

  -> residue_modulus
    @denominator_class.gcd(
      @group.level / @denominator_class)

  -> ==(other)
    return false if other == nil || other.class_name != "Gamma0Cusp"
    (@group == other.group &&
      @denominator_class == other.denominator_class &&
      @residue == other.residue)

  -> eql?(other)
    self == other

  -> key
    @denominator_class.to_s + ":" + @residue.to_s

  -> to_s
    ("Gamma0Cusp(N=" + @group.level.to_s +
      ", d=" + @denominator_class.to_s +
      ", a=" + @residue.to_s + ")")

  -> inspect
    to_s


+ ManinSymbol
  -> new(@space, @index)
    pair = @space.projective_line.pair(@index)
    @c = pair[0]
    @d = pair[1]

  -> space
    @space

  -> index
    @index

  -> c
    @c

  -> d
    @d

  -> pair
    [@c, @d]

  -> boundary
    @space.symbol_boundary(@index)

  -> to_s
    "[" + @c.to_s + ":" + @d.to_s + "]"

  -> inspect
    to_s


+ WeightTwoModularSymbols
  -> new(group, weight = 2, @search_limit = 1_000_000)
    if weight != 2
      raise "the first Manin-symbol implementation supports weight 2"
    @weight = 2
    @group = group.class_name == "Gamma0" ? group : Gamma0.new(group)
    @projective_line = Gamma0ProjectiveLine.new(
      @group, @search_limit)
    @symbols = []
    i = 0
    while i < @projective_line.size
      @symbols.push(ManinSymbol.new(self, i))
      i += 1
    @relation_terms = WeightTwoModularSymbols.relation_terms(
      @projective_line)
    @relative_dimension = (
      2*@group.genus + @group.number_of_cusps - 1)
    @relation_rank = @symbols.size - @relative_dimension

    boundary_data = WeightTwoModularSymbols.boundary_data(
      @group, @projective_line, @search_limit)
    @cusps = boundary_data[0]
    @boundaries = boundary_data[1]
    @boundary_matrix = boundary_data[2]
    @boundary_rank = @group.number_of_cusps - 1
    @cuspidal_dimension = @relative_dimension - @boundary_rank
    @cuspidal_basis = nil
    @certificate = WeightTwoModularSymbolsCertificate.new(self)
    if !@certificate.verified?
      raise "weight-two modular-symbol certificate failed"

  -> .sparse_relation(indices)
    terms = []
    indices.each -> (index)
      found = false
      terms.each -> (term)
        if term[0] == index
          term[1] += 1
          found = true
      terms.push([index, 1]) if !found
    terms.sort_by -> (term) term[0]

  -> .relation_terms(projective_line)
    size = projective_line.size
    relations = []
    i = 0
    while i < size
      pair = projective_line.pair(i)
      c = pair[0]
      d = pair[1]
      s = projective_line.index_of(d, 0 - c)
      relations.push(
        WeightTwoModularSymbols.sparse_relation([i, s]))

      r1 = projective_line.index_of(d, 0 - c - d)
      r2 = projective_line.index_of(0 - c - d, c)
      relations.push(
        WeightTwoModularSymbols.sparse_relation([i, r1, r2]))
      i += 1
    relations

  -> .relation_matrix(projective_line)
    size = projective_line.size
    matrix = []
    WeightTwoModularSymbols.relation_terms(projective_line).each -> (terms)
      row = ModularSymbolsLinearAlgebra.zero_integer_vector(size)
      terms.each -> (term)
        row[term[0]] = term[1]
      matrix.push(row)
    matrix

  -> .extended_gcd(left, right)
    old_r = left
    r = right
    old_s = 1
    s = 0
    old_t = 0
    t = 1
    while r != 0
      quotient = old_r / r
      next_r = old_r - quotient*r
      old_r = r
      r = next_r
      next_s = old_s - quotient*s
      old_s = s
      s = next_s
      next_t = old_t - quotient*t
      old_t = t
      t = next_t
    if old_r < 0
      old_r = 0 - old_r
      old_s = 0 - old_s
      old_t = 0 - old_t
    [old_r, old_s, old_t]

  -> .coprime_lift(c, d, level, search_limit)
    return [0, 1] if level == 1
    # Varying c by multiples of N is sufficient. For every prime q|d,
    # either q|N (then primitivity makes every lift nonzero mod q) or exactly
    # one residue class of k is forbidden. Since 0 <= d < N, a valid k occurs
    # within this bounded scan; a quadratic k/l search is unnecessary.
    k = 0
    while k <= level
      if k > search_limit
        raise "Manin-symbol lift unknown: coprime-lift search exceeds limit"
      cc = c + k*level
      return [cc, d] if cc.gcd(d) == 1
      k += 1
    raise "primitive residue pair has no coprime lift"

  -> .cusp_from_fraction(group, numerator, denominator)
    if denominator == 0
      return Gamma0Cusp.new(group, group.level, 0)
    common = numerator.abs.gcd(denominator.abs)
    a = numerator / common
    c = denominator / common
    if c < 0
      a = 0 - a
      c = 0 - c
    denominator_class = c.gcd(group.level)
    modulus = denominator_class.gcd(
      group.level / denominator_class)
    residue = 0
    if modulus > 1
      residue = (a*(c / denominator_class)) % modulus
      residue += modulus if residue < 0
    Gamma0Cusp.new(group, denominator_class, residue)

  # Return [cusps, per-symbol [infinity, zero], boundary matrix].
  -> .boundary_data(group, projective_line, search_limit)
    boundaries = []
    cusps = []
    cusp_index = {}
    i = 0
    while i < projective_line.size
      pair = projective_line.pair(i)
      lift = WeightTwoModularSymbols.coprime_lift(
        pair[0], pair[1], group.level, search_limit)
      bezout = WeightTwoModularSymbols.extended_gcd(
        lift[0], lift[1])
      if bezout[0] != 1
        raise "Manin-symbol lift is not coprime"
      top_a = bezout[2]
      top_b = 0 - bezout[1]
      infinity = WeightTwoModularSymbols.cusp_from_fraction(
        group, top_a, lift[0])
      zero = WeightTwoModularSymbols.cusp_from_fraction(
        group, top_b, lift[1])
      boundaries.push([infinity, zero])
      [infinity, zero].each -> (cusp)
        if cusp_index[cusp.key] == nil
          cusp_index[cusp.key] = cusps.size
          cusps.push(cusp)
      i += 1
    matrix = []
    cusps.each ->
      matrix.push(
        ModularSymbolsLinearAlgebra.zero_integer_vector(projective_line.size))
    i = 0
    while i < boundaries.size
      infinity = boundaries[i][0]
      zero = boundaries[i][1]
      matrix[cusp_index[infinity.key]][i] += 1
      matrix[cusp_index[zero.key]][i] -= 1
      i += 1
    [cusps, boundaries, matrix]

  -> group
    @group

  -> level
    @group.level

  -> weight
    @weight

  -> projective_line
    @projective_line

  -> symbols
    out = []
    @symbols.each -> (symbol)
      out.push(symbol)
    out

  -> relations
    WeightTwoModularSymbols.relation_matrix(@projective_line)

  -> relation_terms
    out = []
    @relation_terms.each -> (terms)
      copied = []
      terms.each -> (term)
        copied.push([term[0], term[1]])
      out.push(copied)
    out

  -> relation_rank
    @relation_rank

  -> relative_dimension
    @relative_dimension

  -> cusps
    out = []
    @cusps.each -> (cusp)
      out.push(cusp)
    out

  -> symbol_boundary(index)
    boundary = @boundaries[index]
    [boundary[0], boundary[1]]

  -> boundary_matrix
    ModularSymbolsLinearAlgebra.copy_matrix(@boundary_matrix)

  -> boundary_rank
    @boundary_rank

  -> cuspidal_dimension
    @cuspidal_dimension

  -> cuspidal_basis
    if @cuspidal_basis == nil
      work = @symbols.size**3
      if work > @search_limit
        raise "cuspidal rational basis unknown: dense RREF exceeds limit"
      dense_relations = WeightTwoModularSymbols.relation_matrix(
        @projective_line)
      relation_reduction = ModularSymbolsLinearAlgebra.rref(
        dense_relations)
      pivots = relation_reduction[1]
      quotient_columns = []
      pivot_set = {}
      pivots.each -> (pivot)
        pivot_set[pivot.to_s] = true
      i = 0
      while i < @symbols.size
        quotient_columns.push(i) if pivot_set[i.to_s] == nil
        i += 1
      quotient_boundary = []
      @boundary_matrix.each -> (row)
        restricted = []
        quotient_columns.each -> (column)
          restricted.push(row[column])
        quotient_boundary.push(restricted)
      kernel = ModularSymbolsLinearAlgebra.nullspace(
        quotient_boundary, quotient_columns.size)
      @cuspidal_basis = []
      kernel.each -> (quotient_vector)
        lifted = ModularSymbolsLinearAlgebra.zero_vector(@symbols.size)
        i = 0
        while i < quotient_columns.size
          lifted[quotient_columns[i]] = quotient_vector[i]
          i += 1
        @cuspidal_basis.push(lifted)
      if @cuspidal_basis.size != @cuspidal_dimension
        raise "cuspidal rational basis dimension mismatch"
    out = []
    @cuspidal_basis.each -> (vector)
      copied = []
      vector.each -> (entry)
        copied.push(entry)
      out.push(copied)
    out

  -> certificate
    @certificate

  -> certified?
    @certificate.verified?

  -> to_s
    ("ModularSymbols(Gamma0(" + level.to_s +
      "), weight=2, dimension=" +
      @relative_dimension.to_s + ")")

  -> inspect
    to_s


+ WeightTwoModularSymbolsCertificate
  -> new(@space)
    @verified_cache = nil

  -> space
    @space

  -> theorem
    "Manin presentation of weight-two modular symbols for Gamma_0(N)"

  -> theorem_reference
    "Manin, Parabolic points and zeta functions of modular curves"

  -> proof_kind
    :trusted_theorem_import

  -> kernel_checked?
    false

  -> arithmetic_replay_checked?
    verified?

  -> verified?
    return @verified_cache if @verified_cache != nil
    answer = false
    begin
      answer = verify!
    rescue error
      answer = false
    @verified_cache = answer
    answer

  -> verify!
    return false if @space.class_name != "WeightTwoModularSymbols"
    group = @space.group
    return false if !group.certificate.verified?
    line = @space.projective_line
    return false if !line.certificate.verified?
    return false if @space.symbols.size != line.size
    expected_relations = WeightTwoModularSymbols.relation_terms(line)
    return false if !ModularSymbolsLinearAlgebra.same_sparse_relations?(
      @space.relation_terms, expected_relations)
    expected_relative = 2*group.genus + group.number_of_cusps - 1
    expected_relation_rank = line.size - expected_relative
    return false if @space.relation_rank != expected_relation_rank
    return false if @space.relative_dimension != expected_relative

    boundary = @space.boundary_matrix
    return false if @space.cusps.size != group.number_of_cusps
    return false if @space.boundary_rank != group.number_of_cusps - 1
    expected_relations.each -> (relation)
      boundary.each -> (row)
        value = 0
        relation.each -> (term)
          value += row[term[0]]*term[1]
        return false if value != 0

    expected_cuspidal = expected_relative - @space.boundary_rank
    return false if @space.cuspidal_dimension != expected_cuspidal
    expected_cuspidal == 2*group.genus

  -> certified?
    verified?

  -> to_s
    ("WeightTwoModularSymbolsCertificate(N=" +
      @space.level.to_s + ")")

  -> inspect
    to_s
