# Exact Lenstra--Lenstra--Lovasz reduction for lattices presented by a
# positive-definite rational Gram matrix.
#
# This layer is intentionally independent of numerical embeddings.  Number
# field orders use the Frobenius inner product on multiplication matrices:
#
#   <x,y> = sum M_x[i,j] M_y[i,j].
#
# It is positive definite, integral on an order, and often removes the severe
# coefficient distortion caused by a nonmonic defining polynomial.  LLL is a
# producer optimization only; ideal and principal-relation certificates still
# replay the resulting arithmetic exactly.

+ ExactGramLatticeReductionCertificate
  -> new(@reduction)
    @verified_cache = nil

  -> reduction
    @reduction

  -> proof_kind
    :exact_lll

  -> kernel_checked?
    true

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
    expected = "ExactGramLatticeReduction"
    return false if @reduction.class_name != expected
    return false if !@reduction.valid_input?

    source = @reduction.source_basis
    reduced = @reduction.reduced_basis
    transformation = @reduction.transformation
    size = source.size
    return false if reduced.size != size
    return false if transformation.size != size

    row = 0
    while row < size
      return false if transformation[row].size != size
      replay = []
      coordinate = 0
      while coordinate < size
        value = 0 ## big
        source_index = 0
        while source_index < size
          coefficient = transformation[row][source_index]
          return false if !@reduction.integer_value?(coefficient)
          value += coefficient * source[source_index][coordinate]
          source_index += 1
        replay.push(value)
        coordinate += 1
      return false if !@reduction.same_integer_vector?(
        replay, reduced[row])
      row += 1

    determinant = Algebra.determinant(
      transformation, RationalField.new)
    return false if determinant.abs != Rational.new(1)

    gram_schmidt = @reduction.compute_gram_schmidt(reduced)
    return false if !@reduction.same_rational_matrix?(
      gram_schmidt[0],
      @reduction.gram_schmidt_coefficients)
    return false if !@reduction.same_rational_vector?(
      gram_schmidt[1],
      @reduction.orthogonal_norms)
    @reduction.reduced_conditions?(
      gram_schmidt[0], gram_schmidt[1])

  -> certified?
    verified?

  -> to_s
    text = "ExactGramLatticeReductionCertificate(rank "
    text + @reduction.rank.to_s + ")"

  -> inspect
    to_s


+ ExactGramLatticeReduction
  -> new(gram_matrix, source_basis = nil,
         delta = Rational.new(3, 4))
    @gram_matrix = copy_rational_matrix(gram_matrix)
    @delta = Rational.coerce(delta)
    if source_basis == nil
      @source_basis = integer_identity(@gram_matrix.size)
    else
      @source_basis = copy_integer_matrix(source_basis)
    if !valid_input?
      raise "exact LLL needs a full-rank integer basis and a positive-definite symmetric Gram matrix"
    @reduced_basis = copy_integer_matrix(@source_basis)
    @transformation = integer_identity(@source_basis.size)
    reduce
    gram_schmidt = compute_gram_schmidt(@reduced_basis)
    @gram_schmidt_coefficients = gram_schmidt[0]
    @orthogonal_norms = gram_schmidt[1]
    @certificate_cache = ExactGramLatticeReductionCertificate.new(
      self)
    if !@certificate_cache.verified?
      raise "exact LLL reduction failed certification"

  -> integer_value?(value)
    name = value.class_name
    integer = name == "Integer"
    integer = true if name == "Int"
    integer = true if name == "BigInt"
    integer

  -> integer_identity(size)
    rows = []
    i = 0
    while i < size
      row = []
      j = 0
      while j < size
        row.push(i == j ? 1 : 0)
        j += 1
      rows.push(row)
      i += 1
    rows

  -> copy_integer_vector(vector)
    out = []
    vector.each -> (entry)
      if !integer_value?(entry)
        raise "exact LLL basis entries must be integers"
      out.push(entry)
    out

  -> copy_integer_matrix(matrix)
    if matrix.class_name != "Array"
      raise "exact LLL basis must be a matrix"
    out = []
    matrix.each -> (row)
      if row.class_name != "Array"
        raise "exact LLL basis rows must be arrays"
      out.push(copy_integer_vector(row))
    out

  -> copy_rational_matrix(matrix)
    if matrix.class_name != "Array"
      raise "exact LLL Gram data must be a matrix"
    out = []
    matrix.each -> (source)
      if source.class_name != "Array"
        raise "exact LLL Gram rows must be arrays"
      row = []
      source.each -> (entry)
        row.push(Rational.coerce(entry))
      out.push(row)
    out

  -> same_integer_vector?(left, right)
    return false if left.size != right.size
    i = 0
    while i < left.size
      return false if left[i] != right[i]
      i += 1
    true

  -> same_rational_vector?(left, right)
    return false if left.size != right.size
    i = 0
    while i < left.size
      return false if Rational.coerce(left[i]) != Rational.coerce(right[i])
      i += 1
    true

  -> same_rational_matrix?(left, right)
    return false if left.size != right.size
    i = 0
    while i < left.size
      return false if !same_rational_vector?(
        left[i], right[i])
      i += 1
    true

  -> valid_input?
    size = @gram_matrix.size
    return false if size < 1
    return false if @source_basis.size != size
    return false if @delta <= Rational.new(1, 4)
    return false if @delta >= Rational.new(1)
    i = 0
    while i < size
      return false if @gram_matrix[i].size != size
      return false if @source_basis[i].size != size
      j = 0
      while j < size
        return false if @gram_matrix[i][j] != @gram_matrix[j][i]
        return false if !integer_value?(@source_basis[i][j])
        j += 1
      i += 1
    determinant = Algebra.determinant(
      @source_basis, RationalField.new)
    return false if determinant.zero?
    begin
      data = compute_gram_schmidt(@source_basis)
      i = 0
      while i < data[1].size
        return false if data[1][i] <= Rational.new(0)
        i += 1
    rescue error
      return false
    true

  -> rank
    @source_basis.size

  -> gram_matrix
    copy_rational_matrix(@gram_matrix)

  -> source_basis
    copy_integer_matrix(@source_basis)

  -> reduced_basis
    copy_integer_matrix(@reduced_basis)

  -> transformation
    copy_integer_matrix(@transformation)

  -> delta
    @delta

  -> gram_schmidt_coefficients
    copy_rational_matrix(@gram_schmidt_coefficients)

  -> orthogonal_norms
    out = []
    @orthogonal_norms.each -> (value)
      out.push(value)
    out

  -> inner_product(left, right)
    value = Rational.new(0)
    i = 0
    while i < rank
      j = 0
      while j < rank
        term = Rational.coerce(left[i]) * @gram_matrix[i][j]
        value += term * Rational.coerce(right[j])
        j += 1
      i += 1
    value

  # Return [mu, squared Gram--Schmidt norms].
  -> compute_gram_schmidt(basis)
    stars = []
    mu = []
    norms = []
    i = 0
    while i < basis.size
      star = []
      basis[i].each -> (entry)
        star.push(Rational.coerce(entry))
      row = []
      basis.size.times -> row.push(Rational.new(0))
      j = 0
      while j < i
        coefficient = inner_product(
          basis[i], stars[j]) / norms[j]
        row[j] = coefficient
        coordinate = 0
        while coordinate < rank
          projection = coefficient * stars[j][coordinate]
          star[coordinate] -= projection
          coordinate += 1
        j += 1
      stars.push(star)
      mu.push(row)
      norms.push(inner_product(star, star))
      i += 1
    [mu, norms]

  -> nearest_integer(value)
    rational = Rational.coerce(value)
    numerator = rational.numerator
    denominator = rational.denominator
    quotient = numerator / denominator
    remainder = numerator - quotient * denominator
    if remainder < 0
      quotient -= 1
      remainder += denominator
    quotient += 1 if remainder * 2 > denominator
    quotient

  -> subtract_multiple(target, source, multiplier)
    out = []
    i = 0
    while i < target.size
      out.push(target[i] - multiplier * source[i])
      i += 1
    out

  -> reduce
    k = 1
    while k < rank
      data = compute_gram_schmidt(@reduced_basis)
      mu = data[0]
      norms = data[1]
      j = k - 1
      while j >= 0
        quotient = nearest_integer(mu[k][j])
        if quotient != 0
          @reduced_basis[k] = subtract_multiple(
            @reduced_basis[k],
            @reduced_basis[j], quotient)
          @transformation[k] = subtract_multiple(
            @transformation[k],
            @transformation[j], quotient)
          data = compute_gram_schmidt(@reduced_basis)
          mu = data[0]
          norms = data[1]
        j -= 1

      threshold = @delta - mu[k][k - 1] ** 2
      if norms[k] >= threshold * norms[k - 1]
        k += 1
      else
        temporary = @reduced_basis[k]
        @reduced_basis[k] = @reduced_basis[k - 1]
        @reduced_basis[k - 1] = temporary
        temporary = @transformation[k]
        @transformation[k] = @transformation[k - 1]
        @transformation[k - 1] = temporary
        k -= 1
        k = 1 if k < 1
    self

  -> reduced_conditions?(mu, norms)
    half = Rational.new(1, 2)
    i = 0
    while i < rank
      return false if norms[i] <= Rational.new(0)
      j = 0
      while j < i
        return false if mu[i][j].abs > half
        j += 1
      if i > 0
        threshold = @delta - mu[i][i - 1] ** 2
        return false if norms[i] < threshold * norms[i - 1]
      i += 1
    true

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> to_s
    "ExactGramLatticeReduction(rank " + rank.to_s + ")"

  -> inspect
    to_s


+ AlgebraOrder
  -> frobenius_gram_matrix
    if @frobenius_gram_matrix_cache == nil
      matrices = multiplication_matrices
      gram = []
      i = 0
      while i < rank
        row = []
        j = 0
        while j < rank
          value = 0 ## big
          matrix_row = 0
          while matrix_row < rank
            matrix_column = 0
            while matrix_column < rank
              product = matrices[i][matrix_row][matrix_column]
              product *= matrices[j][matrix_row][matrix_column]
              value += product
              matrix_column += 1
            matrix_row += 1
          row.push(value)
          j += 1
        gram.push(row)
        i += 1
      @frobenius_gram_matrix_cache = gram
    out = []
    @frobenius_gram_matrix_cache.each -> (row)
      copied = []
      row.each -> (entry)
        copied.push(entry)
      out.push(copied)
    out

  -> frobenius_lattice_reduction
    ExactGramLatticeReduction.new(
      frobenius_gram_matrix)

  -> multiplication_matrix_from_coordinates(coordinates)
    if coordinates.class_name != "Array" || coordinates.size != rank
      raise "order-coordinate multiplication matrix has the wrong dimension"
    matrices = multiplication_matrices
    out = []
    row = 0
    while row < rank
      values = []
      column = 0
      while column < rank
        value = 0 ## big
        basis_index = 0
        while basis_index < rank
          coefficient = coordinates[basis_index]
          name = coefficient.class_name
          integer = name == "Integer" || name == "Int"
          integer = true if name == "BigInt"
          if !integer
            raise "order multiplication coordinates must be integers"
          term = coefficient * matrices[basis_index][row][column]
          value += term
          basis_index += 1
        values.push(value)
        column += 1
      out.push(values)
      row += 1
    out

  -> norm_from_coordinates(coordinates)
    determinant = Algebra.determinant(
      multiplication_matrix_from_coordinates(
        coordinates),
      RationalField.new)
    if determinant.denominator != 1
      raise "integral order element has nonintegral norm"
    determinant.numerator

  -> reduced_frobenius_basis
    out = []
    frobenius_lattice_reduction.reduced_basis.each -> (coordinates)
      out.push(element(coordinates))
    out


+ AlgebraOrderIdeal
  -> order_coordinate_basis
    out = []
    basis.each -> (basis_element)
      coordinates = @order.coordinates(basis_element)
      row = []
      coordinates.each -> (coefficient)
        if coefficient.denominator != 1
          raise "ideal basis has nonintegral order coordinates"
        row.push(coefficient.numerator)
      out.push(row)
    out

  -> frobenius_lattice_reduction
    ExactGramLatticeReduction.new(
      @order.frobenius_gram_matrix,
      order_coordinate_basis)

  -> reduced_frobenius_coordinate_basis
    frobenius_lattice_reduction.reduced_basis

  -> reduced_frobenius_basis
    out = []
    frobenius_lattice_reduction.reduced_basis.each -> (coordinates)
      out.push(@order.element(coordinates))
    out
