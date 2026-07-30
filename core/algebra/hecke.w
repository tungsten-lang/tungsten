# Exact Hecke operators on weight-two Gamma_0(N) modular symbols.
#
# The producer uses Cremona's Heilbronn matrices.  Its certificate replays
# every matrix image, the Manin-quotient reduction, the cuspidal restriction,
# and characteristic-polynomial determinants.  The theorem that this finite
# matrix sum realizes T_p is an explicit trusted import. Composite indices
# use the exact multiplicative and prime-power Hecke relations.

+ HeckeLinearAlgebra
  -> .zero_matrix(rows, columns = nil)
    width = columns == nil ? rows : columns
    matrix = []
    i = 0
    while i < rows
      matrix.push(ModularSymbolsLinearAlgebra.zero_vector(width))
      i += 1
    matrix

  -> .identity(size)
    matrix = []
    i = 0
    while i < size
      row = ModularSymbolsLinearAlgebra.zero_vector(size)
      row[i] = Rational.new(1)
      matrix.push(row)
      i += 1
    matrix

  -> .transpose(matrix, columns = nil)
    width = columns
    if matrix.size > 0
      width = matrix[0].size
      matrix.each -> (row)
        raise "matrix rows have inconsistent sizes" if row.size != width
    elsif width == nil
      raise "empty matrix transpose needs an explicit column count"
    out = HeckeLinearAlgebra.zero_matrix(width, matrix.size)
    i = 0
    while i < matrix.size
      j = 0
      while j < width
        out[j][i] = Rational.coerce(matrix[i][j])
        j += 1
      i += 1
    out

  -> .matrix_add(left, right)
    raise "matrix addition dimensions do not match" if left.size != right.size
    out = []
    i = 0
    while i < left.size
      raise "matrix addition dimensions do not match" if left[i].size != right[i].size
      row = []
      j = 0
      while j < left[i].size
        row.push(
          Rational.coerce(left[i][j]) +
          Rational.coerce(right[i][j]))
        j += 1
      out.push(row)
      i += 1
    out

  -> .matrix_product(left, right)
    return [] if left.size == 0
    raise "matrix product needs a nonempty right matrix" if right.size == 0
    inner = left[0].size
    raise "matrix product dimensions do not match" if right.size != inner
    columns = right[0].size
    out = []
    i = 0
    while i < left.size
      raise "matrix rows have inconsistent sizes" if left[i].size != inner
      row = ModularSymbolsLinearAlgebra.zero_vector(columns)
      k = 0
      while k < inner
        raise "matrix rows have inconsistent sizes" if right[k].size != columns
        if !Rational.coerce(left[i][k]).zero?
          j = 0
          while j < columns
            row[j] += (
              Rational.coerce(left[i][k]) *
              Rational.coerce(right[k][j]))
            j += 1
        k += 1
      out.push(row)
      i += 1
    out

  -> .matrix_subtract(left, right)
    raise "matrix subtraction dimensions do not match" if left.size != right.size
    out = []
    i = 0
    while i < left.size
      raise "matrix subtraction dimensions do not match" if left[i].size != right[i].size
      row = []
      j = 0
      while j < left[i].size
        row.push(
          Rational.coerce(left[i][j]) -
          Rational.coerce(right[i][j]))
        j += 1
      out.push(row)
      i += 1
    out

  -> .matrix_scale(matrix, scalar)
    factor = Rational.coerce(scalar)
    out = []
    matrix.each -> (source)
      row = []
      source.each -> (entry)
        row.push(Rational.coerce(entry)*factor)
      out.push(row)
    out

  # Evaluate a univariate rational polynomial at a square matrix.  Horner's
  # rule keeps the number of exact matrix products linear in the degree.
  -> .matrix_polynomial(polynomial, matrix)
    if (polynomial.class_name != "Polynomial" ||
        polynomial.ring.arity != 1 ||
        polynomial.ring.field.class_name != "RationalField")
      raise "matrix-polynomial evaluation needs a univariate rational polynomial"
    size = matrix.size
    matrix.each -> (row)
      raise "matrix-polynomial evaluation needs a square matrix" if row.size != size
    result = HeckeLinearAlgebra.zero_matrix(size)
    identity = HeckeLinearAlgebra.identity(size)
    degree = polynomial.degree
    while degree >= 0
      result = HeckeLinearAlgebra.matrix_product(result, matrix)
      coefficient = polynomial.coeff(degree)
      if !coefficient.zero?
        result = HeckeLinearAlgebra.matrix_add(
          result,
          HeckeLinearAlgebra.matrix_scale(identity, coefficient))
      degree -= 1
    result

  # Row vectors v satisfying v*matrix = 0.
  -> .left_kernel(matrix)
    size = matrix.size
    matrix.each -> (row)
      raise "left kernel needs a square matrix" if row.size != size
    ModularSymbolsLinearAlgebra.nullspace(
      HeckeLinearAlgebra.transpose(matrix, size), size)

  -> .row_vector_matrix(vector, matrix)
    return [] if matrix.size == 0
    raise "row-vector/matrix dimensions do not match" if vector.size != matrix.size
    columns = matrix[0].size
    out = ModularSymbolsLinearAlgebra.zero_vector(columns)
    i = 0
    while i < matrix.size
      raise "matrix rows have inconsistent sizes" if matrix[i].size != columns
      if !Rational.coerce(vector[i]).zero?
        j = 0
        while j < columns
          out[j] += (
            Rational.coerce(vector[i]) *
            Rational.coerce(matrix[i][j]))
          j += 1
      i += 1
    out

  # Coordinates c such that c*basis = vector, where basis consists of
  # independent row vectors.
  -> .row_span_solver(basis)
    if basis.size == 0
      return [basis, [], []]
    reduced = ModularSymbolsLinearAlgebra.rref(basis)
    pivots = reduced[1]
    if pivots.size != basis.size
      raise "row-span basis is not independent"
    square = []
    basis.each -> (row)
      restricted = []
      pivots.each -> (column)
        restricted.push(row[column])
      square.push(restricted)
    inverse = ExactRationalLinearAlgebra.inverse(square)
    [basis, pivots, inverse]

  -> .row_span_coordinates_with_solver(solver, vector)
    basis = solver[0]
    pivots = solver[1]
    inverse = solver[2]
    return [] if basis.size == 0 && vector.size == 0
    if basis.size == 0
      raise "vector does not lie in the zero row span"
    selected = []
    pivots.each -> (column)
      selected.push(Rational.coerce(vector[column]))
    coordinates = HeckeLinearAlgebra.row_vector_matrix(
      selected, inverse)
    reconstructed = HeckeLinearAlgebra.row_vector_matrix(
      coordinates, basis)
    if !ModularSymbolsLinearAlgebra.same_vector?(
         reconstructed, vector)
      raise "vector does not lie in the requested row span"
    coordinates

  -> .row_span_coordinates(basis, vector)
    HeckeLinearAlgebra.row_span_coordinates_with_solver(
      HeckeLinearAlgebra.row_span_solver(basis), vector)

  -> .characteristic_polynomial(matrix)
    size = matrix.size
    ring = PolynomialRing.new([:x], RationalField.new)
    return ring.one if size == 0
    matrix.each -> (row)
      raise "characteristic polynomial needs a square matrix" if row.size != size

    identity = HeckeLinearAlgebra.identity(size)
    b = identity
    coefficients = [Rational.new(1)]
    k = 1
    while k <= size
      product = HeckeLinearAlgebra.matrix_product(matrix, b)
      trace = Rational.new(0)
      i = 0
      while i < size
        trace += product[i][i]
        i += 1
      coefficient = (0 - trace) / Rational.new(k)
      coefficients.push(coefficient)
      i = 0
      while i < size
        product[i][i] += coefficient
        i += 1
      b = product
      k += 1

    polynomial = ring.zero
    i = 0
    while i < coefficients.size
      polynomial += ring.monomial(
        coefficients[i], [size - i])
      i += 1
    polynomial

  -> .shifted_determinant(matrix, value)
    shifted = []
    i = 0
    while i < matrix.size
      row = []
      j = 0
      while j < matrix.size
        entry = 0 - Rational.coerce(matrix[i][j])
        entry += Rational.coerce(value) if i == j
        row.push(entry)
        j += 1
      shifted.push(row)
      i += 1
    Algebra.determinant(shifted, RationalField.new)

  -> .row_basis(matrix, width = nil)
    if matrix.size == 0
      return []
    reduced = ModularSymbolsLinearAlgebra.rref(matrix)
    rank = reduced[1].size
    out = []
    i = 0
    while i < rank
      row = []
      reduced[0][i].each -> row.push(item)
      out.push(row)
      i += 1
    out

  # Quotient V / rowspan(relations), returning
  # [free source indices, source generators -> quotient coordinates].
  -> .quotient_map(relations, width)
    if relations.size == 0
      free = []
      map = []
      i = 0
      while i < width
        free.push(i)
        row = ModularSymbolsLinearAlgebra.zero_vector(width)
        row[i] = Rational.new(1)
        map.push(row)
        i += 1
      return [free, map]
    reduced = ModularSymbolsLinearAlgebra.rref(relations)
    rows = reduced[0]
    pivots = reduced[1]
    pivot_set = {}
    pivots.each -> (pivot)
      pivot_set[pivot.to_s] = true
    free = []
    i = 0
    while i < width
      free.push(i) if pivot_set[i.to_s] == nil
      i += 1
    map = []
    i = 0
    while i < width
      map.push(ModularSymbolsLinearAlgebra.zero_vector(free.size))
      i += 1
    i = 0
    while i < free.size
      map[free[i]][i] = Rational.new(1)
      i += 1
    i = 0
    while i < pivots.size
      j = 0
      while j < free.size
        map[pivots[i]][j] = 0 - rows[i][free[j]]
        j += 1
      i += 1
    [free, map]

  -> .restrict_operator(matrix, invariant_basis)
    out = []
    solver = HeckeLinearAlgebra.row_span_solver(invariant_basis)
    invariant_basis.each -> (vector)
      image = HeckeLinearAlgebra.row_vector_matrix(vector, matrix)
      out.push(
        HeckeLinearAlgebra.row_span_coordinates_with_solver(
          solver, image))
    out

  -> .quotient_operator(matrix, relations)
    quotient = HeckeLinearAlgebra.quotient_map(
      relations, matrix.size)
    free = quotient[0]
    map = quotient[1]
    out = []
    free.each -> (source)
      out.push(HeckeLinearAlgebra.row_vector_matrix(
        matrix[source], map))
    out

  -> .verify_characteristic_polynomial(matrix, polynomial)
    size = matrix.size
    return false if polynomial.degree != size
    return false if polynomial.leading_coefficient != Rational.new(1)
    value = 0
    while value <= size
      expected = HeckeLinearAlgebra.shifted_determinant(matrix, value)
      return false if polynomial.at(value) != expected
      value += 1
    true


+ HeilbronnCremonaMatrices
  -> new(@prime)
    if @prime < 2 || !@prime.prime?
      raise "Cremona-Heilbronn matrices need a prime"
    @matrices = HeilbronnCremonaMatrices.produce(@prime)
    @certificate = HeilbronnCremonaCertificate.new(self)
    raise "Cremona-Heilbronn matrix certificate failed" if !@certificate.verified?

  -> .nearest_integer_quotient(numerator, denominator)
    raise "nearest quotient has zero denominator" if denominator == 0
    sign = (numerator < 0) == (denominator < 0) ? 1 : -1
    absolute_numerator = numerator.abs
    absolute_denominator = denominator.abs
    scaled_denominator = 2*absolute_denominator
    rounded_numerator = 2*absolute_numerator + absolute_denominator
    magnitude = (
      (rounded_numerator -
       rounded_numerator % scaled_denominator) /
      scaled_denominator)
    sign*magnitude

  -> .produce(prime)
    matrices = [[1, 0, 0, prime]]
    if prime == 2
      matrices.push([2, 0, 0, 1])
      matrices.push([2, 1, 0, 1])
      matrices.push([1, 0, 1, 2])
      return matrices

    half = (prime - 1)/2
    r = 0 - half
    while r <= half
      x1 = prime
      x2 = 0 - r
      y1 = 0
      y2 = 1
      a = 0 - prime
      b = r
      matrices.push([x1, x2, y1, y2])
      while b != 0
        quotient = HeilbronnCremonaMatrices.nearest_integer_quotient(a, b)
        c = a - b*quotient
        a = 0 - b
        b = c
        x3 = quotient*x2 - x1
        x1 = x2
        x2 = x3
        y3 = quotient*y2 - y1
        y1 = y2
        y2 = y3
        matrices.push([x1, x2, y1, y2])
      r += 1
    matrices

  -> prime
    @prime

  -> matrices
    out = []
    @matrices.each -> (matrix)
      out.push([matrix[0], matrix[1], matrix[2], matrix[3]])
    out

  -> size
    @matrices.size

  -> apply(c, d)
    out = []
    @matrices.each -> (matrix)
      out.push([
        c*matrix[0] + d*matrix[2],
        c*matrix[1] + d*matrix[3]
      ])
    out

  -> certificate
    @certificate

  -> certified?
    @certificate.verified?

  -> to_s
    "HeilbronnCremona(p=" + @prime.to_s + ")"

  -> inspect
    to_s


+ WeightTwoCompositeHeckeOperator
  -> new(@space, @index)
    if @space.class_name != "WeightTwoModularSymbols"
      raise "composite Hecke operator needs a weight-two modular-symbol space"
    valid_index = ModularFormsArithmetic.integer?(@index) && @index >= 1
    if !valid_index || @index.prime?
      raise "composite Hecke operator needs one or a composite positive index"
    @relative_matrix = produce_matrix(false)
    @cuspidal_matrix = produce_matrix(true)
    @relative_characteristic_polynomial = (
      HeckeLinearAlgebra.characteristic_polynomial(@relative_matrix))
    @cuspidal_characteristic_polynomial = (
      HeckeLinearAlgebra.characteristic_polynomial(@cuspidal_matrix))
    @certificate = WeightTwoCompositeHeckeOperatorCertificate.new(self)
    if !@certificate.verified?
      raise "composite Hecke operator certificate failed"

  -> space
    @space

  -> index
    @index

  -> prime_power_matrix(prime, exponent, cuspidal)
    dimension = cuspidal ? @space.cuspidal_dimension : @space.relative_dimension
    return HeckeLinearAlgebra.identity(dimension) if exponent == 0
    prime_operator = @space.hecke_operator(prime)
    base = cuspidal ? prime_operator.cuspidal_matrix : prime_operator.relative_matrix
    return base if exponent == 1
    if @space.level % prime == 0
      result = base
      power = 2
      while power <= exponent
        result = HeckeLinearAlgebra.matrix_product(result, base)
        power += 1
      return result
    previous_previous = HeckeLinearAlgebra.identity(dimension)
    previous = base
    power = 2
    while power <= exponent
      product = HeckeLinearAlgebra.matrix_product(base, previous)
      correction = HeckeLinearAlgebra.matrix_scale(
        previous_previous, prime)
      current = HeckeLinearAlgebra.matrix_subtract(
        product, correction)
      previous_previous = previous
      previous = current
      power += 1
    previous

  -> produce_matrix(cuspidal)
    dimension = cuspidal ? @space.cuspidal_dimension : @space.relative_dimension
    result = HeckeLinearAlgebra.identity(dimension)
    @index.factor.each -> (factor)
      component = prime_power_matrix(
        factor.prime, factor.exponent, cuspidal)
      result = HeckeLinearAlgebra.matrix_product(result, component)
    result

  -> relative_matrix
    ModularSymbolsLinearAlgebra.copy_matrix(@relative_matrix)

  -> cuspidal_matrix
    ModularSymbolsLinearAlgebra.copy_matrix(@cuspidal_matrix)

  -> relative_characteristic_polynomial
    @relative_characteristic_polynomial

  -> characteristic_polynomial
    @cuspidal_characteristic_polynomial

  -> cuspidal_characteristic_polynomial
    @cuspidal_characteristic_polynomial

  -> certificate
    @certificate

  -> certified?
    @certificate.verified?

  -> to_s
    ("T_" + @index.to_s + " on ModularSymbols(Gamma0(" +
      @space.level.to_s + "), weight=2)")

  -> inspect
    to_s


+ WeightTwoCompositeHeckeOperatorCertificate
  -> new(@operator)
    @verified_cache = nil

  -> operator
    @operator

  -> theorem
    "weight-two Hecke multiplicativity and prime-power recurrences"

  -> theorem_reference
    "Miyake, Modular Forms, Hecke algebra relations for Gamma_0(N)"

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
    if @operator.class_name != "WeightTwoCompositeHeckeOperator"
      return false
    return false if !@operator.space.certificate.verified?
    return false if @operator.index < 1 || @operator.index.prime?
    expected_relative = @operator.produce_matrix(false)
    expected_cuspidal = @operator.produce_matrix(true)
    return false if !ModularSymbolsLinearAlgebra.same_matrix?(
      @operator.relative_matrix, expected_relative)
    return false if !ModularSymbolsLinearAlgebra.same_matrix?(
      @operator.cuspidal_matrix, expected_cuspidal)
    return false if !HeckeLinearAlgebra.verify_characteristic_polynomial(
      @operator.relative_matrix,
      @operator.relative_characteristic_polynomial)
    HeckeLinearAlgebra.verify_characteristic_polynomial(
      @operator.cuspidal_matrix,
      @operator.cuspidal_characteristic_polynomial)

  -> certified?
    verified?

  -> to_s
    ("WeightTwoCompositeHeckeOperatorCertificate(N=" +
      @operator.space.level.to_s + ", n=" +
      @operator.index.to_s + ")")

  -> inspect
    to_s


+ HeilbronnCremonaCertificate
  -> new(@producer)
    @verified_cache = nil

  -> producer
    @producer

  -> theorem
    "Cremona's continued-fraction Heilbronn matrix construction"

  -> theorem_reference
    "Cremona, Algorithms for Modular Elliptic Curves, section 2.4"

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
    return false if @producer.class_name != "HeilbronnCremonaMatrices"
    prime = @producer.prime
    return false if prime < 2 || !prime.prime?
    expected = HeilbronnCremonaMatrices.produce(prime)
    actual = @producer.matrices
    return false if actual.size != expected.size
    i = 0
    while i < actual.size
      matrix = actual[i]
      reference = expected[i]
      return false if matrix.size != 4 || reference.size != 4
      j = 0
      while j < 4
        return false if matrix[j] != reference[j]
        j += 1
      determinant = matrix[0]*matrix[3] - matrix[1]*matrix[2]
      return false if determinant != prime
      i += 1
    true

  -> certified?
    verified?

  -> to_s
    "HeilbronnCremonaCertificate(p=" + @producer.prime.to_s + ")"

  -> inspect
    to_s


+ WeightTwoHeckeOperator
  -> new(@space, @prime)
    if @space.class_name != "WeightTwoModularSymbols"
      raise "weight-two Hecke operator needs a modular-symbol space"
    if @prime < 2 || !@prime.prime?
      raise "weight-two Hecke operator currently needs a prime index"
    @heilbronn = HeilbronnCremonaMatrices.new(@prime)
    @relative_matrix = produce_relative_matrix
    @cuspidal_matrix = produce_cuspidal_matrix
    @relative_characteristic_polynomial = (
      HeckeLinearAlgebra.characteristic_polynomial(
        @relative_matrix))
    @cuspidal_characteristic_polynomial = (
      HeckeLinearAlgebra.characteristic_polynomial(
        @cuspidal_matrix))
    @certificate = WeightTwoHeckeOperatorCertificate.new(self)
    raise "weight-two Hecke operator certificate failed" if !@certificate.verified?

  -> space
    @space

  -> prime
    @prime

  -> heilbronn
    @heilbronn

  -> image_index(pair)
    c = pair[0]
    d = pair[1]
    return nil if c.gcd(d).gcd(@space.level) != 1
    @space.projective_line.index_of(c, d)

  -> produce_relative_matrix
    quotient_basis = @space.quotient_basis_indices
    generators_to_basis = @space.manin_generators_to_basis
    out = []
    quotient_basis.each -> (generator_index)
      source = @space.projective_line.pair(generator_index)
      image = ModularSymbolsLinearAlgebra.zero_vector(
        @space.relative_dimension)
      @heilbronn.apply(source[0], source[1]).each -> (pair)
        index = image_index(pair)
        if index != nil
          coordinates = generators_to_basis[index]
          j = 0
          while j < image.size
            image[j] += coordinates[j]
            j += 1
      out.push(image)
    out

  -> produce_cuspidal_matrix
    basis = @space.cuspidal_basis_coordinates
    solver = @space.cuspidal_basis_solver
    out = []
    basis.each -> (vector)
      image = HeckeLinearAlgebra.row_vector_matrix(
        vector, @relative_matrix)
      out.push(
        HeckeLinearAlgebra.row_span_coordinates_with_solver(
          solver, image))
    out

  -> relative_matrix
    ModularSymbolsLinearAlgebra.copy_matrix(@relative_matrix)

  -> cuspidal_matrix
    ModularSymbolsLinearAlgebra.copy_matrix(@cuspidal_matrix)

  -> relative_characteristic_polynomial
    @relative_characteristic_polynomial

  -> characteristic_polynomial
    @cuspidal_characteristic_polynomial

  -> cuspidal_characteristic_polynomial
    @cuspidal_characteristic_polynomial

  -> certificate
    @certificate

  -> certified?
    @certificate.verified?

  -> to_s
    ("T_" + @prime.to_s + " on ModularSymbols(Gamma0(" +
      @space.level.to_s + "), weight=2)")

  -> inspect
    to_s


+ WeightTwoHeckeOperatorCertificate
  -> new(@operator)
    @verified_cache = nil

  -> operator
    @operator

  -> theorem
    "Heilbronn matrix action realizes T_p on weight-two Manin symbols"

  -> theorem_reference
    "Merel, Universal Fourier expansions of modular forms"

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

  -> verify_characteristic_polynomial(matrix, polynomial)
    HeckeLinearAlgebra.verify_characteristic_polynomial(
      matrix, polynomial)

  -> verify!
    return false if @operator.class_name != "WeightTwoHeckeOperator"
    space = @operator.space
    return false if !space.certificate.verified?
    return false if !@operator.heilbronn.certificate.verified?

    expected_relative = @operator.produce_relative_matrix
    return false if !ModularSymbolsLinearAlgebra.same_matrix?(
      @operator.relative_matrix, expected_relative)
    expected_cuspidal = @operator.produce_cuspidal_matrix
    return false if !ModularSymbolsLinearAlgebra.same_matrix?(
      @operator.cuspidal_matrix, expected_cuspidal)

    return false if !verify_characteristic_polynomial(
      @operator.relative_matrix,
      @operator.relative_characteristic_polynomial)
    verify_characteristic_polynomial(
      @operator.cuspidal_matrix,
      @operator.cuspidal_characteristic_polynomial)

  -> certified?
    verified?

  -> to_s
    ("WeightTwoHeckeOperatorCertificate(N=" +
      @operator.space.level.to_s + ", p=" +
      @operator.prime.to_s + ")")

  -> inspect
    to_s
