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

+ ExactIntegerLinearAlgebra
  -> .integer_value?(value)
    name = value.class_name
    integer = name == "Integer" || name == "Int"
    integer = true if name == "BigInt"
    integer

  # Fraction-free Bareiss elimination.  Every division is exact; this avoids
  # constructing rational temporaries for integral multiplication matrices.
  -> .determinant(matrix)
    if matrix.class_name != "Array" || matrix.size < 1
      raise "integer determinant needs a nonempty square matrix"
    size = matrix.size
    work = []
    i = 0
    while i < size
      row = matrix[i]
      if row.class_name != "Array" || row.size != size
        raise "integer determinant needs a square matrix"
      copied = []
      j = 0
      while j < size
        value = row[j]
        if !ExactIntegerLinearAlgebra.integer_value?(value)
          raise "integer determinant entries must be integers"
        copied.push(value)
        j += 1
      work.push(copied)
      i += 1
    return work[0][0] if size == 1

    sign = 1
    previous_pivot = 1
    column = 0
    while column < size - 1
      pivot_row = column
      while pivot_row < size && work[pivot_row][column] == 0
        pivot_row += 1
      return 0 if pivot_row == size
      if pivot_row != column
        temporary = work[column]
        work[column] = work[pivot_row]
        work[pivot_row] = temporary
        sign = 0 - sign
      pivot = work[column][column]
      row = column + 1
      while row < size
        target_column = column + 1
        while target_column < size
          numerator = work[row][target_column] * pivot
          numerator -= work[row][column] * work[column][target_column]
          if numerator % previous_pivot != 0
            raise "Bareiss determinant division was not exact"
          work[row][target_column] = numerator / previous_pivot
          target_column += 1
        work[row][column] = 0
        row += 1
      previous_pivot = pivot
      column += 1
    sign * work[size - 1][size - 1]

  # A simple exact Leibniz bound:
  #
  #   |det(A)| <= product_i sum_j |a_ij|.
  #
  # It is weaker than Hadamard's Euclidean bound, but entirely integral and
  # cheap to certify.
  -> .determinant_bound(matrix)
    if matrix.class_name != "Array" || matrix.size < 1
      raise "integer determinant needs a nonempty square matrix"
    size = matrix.size
    bound = 1 ## big
    i = 0
    while i < size
      row = matrix[i]
      if row.class_name != "Array" || row.size != size
        raise "integer determinant needs a square matrix"
      row_sum = 0 ## big
      j = 0
      while j < size
        value = row[j]
        if !ExactIntegerLinearAlgebra.integer_value?(value)
          raise "integer determinant entries must be integers"
        row_sum += value.abs
        j += 1
      return 0 if row_sum == 0
      bound *= row_sum
      i += 1
    bound

  -> .determinant_mod_prime(matrix, prime)
    if prime < 2 || !prime.prime?
      raise "modular determinant needs a prime modulus"
    size = matrix.size
    work = []
    i = 0
    while i < size
      if matrix[i].class_name != "Array" || matrix[i].size != size
        raise "modular determinant needs a square matrix"
      row = []
      j = 0
      while j < size
        value = matrix[i][j]
        if !ExactIntegerLinearAlgebra.integer_value?(value)
          raise "modular determinant entries must be integers"
        row.push(PrimeLinearAlgebra.normalize(
          value, prime))
        j += 1
      work.push(row)
      i += 1
    determinant = 1
    column = 0
    while column < size
      pivot = column
      while pivot < size && work[pivot][column] == 0
        pivot += 1
      return 0 if pivot == size
      if pivot != column
        temporary = work[column]
        work[column] = work[pivot]
        work[pivot] = temporary
        determinant = PrimeLinearAlgebra.normalize(
          0 - determinant, prime)
      pivot_value = work[column][column]
      determinant = PrimeLinearAlgebra.normalize(
        determinant * pivot_value, prime)
      inverse = PrimeLinearAlgebra.inverse(
        pivot_value, prime)
      row = column + 1
      while row < size
        if work[row][column] != 0
          factor = PrimeLinearAlgebra.normalize(
            work[row][column] * inverse, prime)
          target = column
          while target < size
            product = factor * work[column][target]
            work[row][target] = PrimeLinearAlgebra.normalize(
              work[row][target] - product, prime)
            target += 1
        row += 1
      column += 1
    determinant

  # Reconstruct det(A) from prime-field images.  Once the product M of the
  # pairwise-coprime moduli exceeds twice the certified bound B, exactly one
  # integer in [-B, B] has the accumulated residue.  This is an exact
  # determinant algorithm, not a probabilistic modular test.
  -> .modular_determinant(matrix)
    bound = ExactIntegerLinearAlgebra.determinant_bound(
      matrix)
    return 0 if bound == 0
    residue = 0 ## big
    modulus_product = 1 ## big
    candidate = 65_521
    while modulus_product <= bound * 2
      while candidate > 2 && !candidate.prime?
        candidate -= 2
      if candidate <= 2
        raise "modular determinant exhausted its certified prime table"
      prime = candidate
      image = ExactIntegerLinearAlgebra.determinant_mod_prime(
        matrix, prime)
      current_image = PrimeLinearAlgebra.normalize(
        residue, prime)
      delta = PrimeLinearAlgebra.normalize(
        image - current_image, prime)
      inverse = PrimeLinearAlgebra.inverse(
        PrimeLinearAlgebra.normalize(
          modulus_product, prime), prime)
      correction = PrimeLinearAlgebra.normalize(
        delta * inverse, prime)
      residue += modulus_product * correction
      modulus_product *= prime
      candidate -= 2
    signed = residue
    signed -= modulus_product if signed > modulus_product / 2
    if signed.abs > bound
      raise "modular determinant reconstruction exceeds its exact bound"
    signed


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
  -> new(gram_matrix)
    initialize_exact_gram_reduction(
      gram_matrix, nil,
      Rational.new(3, 4), :exact)

  -> new(gram_matrix, source_basis)
    initialize_exact_gram_reduction(
      gram_matrix, source_basis,
      Rational.new(3, 4), :exact)

  -> new(gram_matrix, source_basis, delta)
    initialize_exact_gram_reduction(
      gram_matrix, source_basis,
      delta, :exact)

  -> new(gram_matrix, source_basis, delta,
         producer)
    initialize_exact_gram_reduction(
      gram_matrix, source_basis,
      delta, producer)

  -> initialize_exact_gram_reduction(
       gram_matrix, source_basis,
       delta, producer)
    @gram_matrix = copy_rational_matrix(gram_matrix)
    @delta = Rational.coerce(delta)
    @producer = producer
    if source_basis == nil
      @source_basis = integer_identity(@gram_matrix.size)
    else
      @source_basis = copy_integer_matrix(source_basis)
    if !valid_input?
      raise "exact LLL needs a full-rank integer basis and a positive-definite symmetric Gram matrix"
    @reduced_basis = copy_integer_matrix(@source_basis)
    @transformation = integer_identity(@source_basis.size)
    if @producer == :approximate
      reduce_approximately
      exact_data = compute_gram_schmidt(
        @reduced_basis)
      if !reduced_conditions?(
           exact_data[0], exact_data[1])
        reduce
    elsif @producer == :exact
      reduce
    else
      raise "exact LLL producer must be exact or approximate"
    gram_schmidt = compute_gram_schmidt(@reduced_basis)
    @gram_schmidt_coefficients = gram_schmidt[0]
    @orthogonal_norms = gram_schmidt[1]
    @certificate_cache = ExactGramLatticeReductionCertificate.new(
      self)
    if !@certificate_cache.verified?
      raise "exact LLL reduction failed certification"

  -> integer_value?(value)
    name = value.class_name
    integer = name == "Int"
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

  -> producer
    @producer

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

  -> approximate_inner_product(left, right)
    value = ~0.0
    i = 0
    while i < rank
      j = 0
      while j < rank
        left_value = left[i] + ~0.0
        right_value = right[j] + ~0.0
        gram_value = @gram_matrix[i][j].to_f
        value += left_value * gram_value * right_value
        j += 1
      i += 1
    value

  -> compute_approximate_gram_schmidt(basis)
    stars = []
    mu = []
    norms = []
    i = 0
    while i < basis.size
      star = []
      basis[i].each -> (entry)
        star.push(entry + ~0.0)
      row = []
      basis.size.times -> row.push(~0.0)
      j = 0
      while j < i
        coefficient = approximate_inner_product(
          basis[i], stars[j]) / norms[j]
        row[j] = coefficient
        coordinate = 0
        while coordinate < rank
          star[coordinate] -= coefficient * stars[j][coordinate]
          coordinate += 1
        j += 1
      stars.push(star)
      mu.push(row)
      norms.push(approximate_inner_product(
        star, star))
      i += 1
    [mu, norms]

  # Size-reduce b_k against b_j (quotient already computed) and update row k
  # of mu in place: b_k -= q·b_j subtracts q·mu[j][l] from mu[k][l] for
  # l < j and q from mu[k][j]; stars, norms, and every other mu row are
  # unchanged. Exact-arithmetic identity with recomputing the full
  # Gram-Schmidt data, at O(j) instead of O(rank³).
  -> size_reduce_step(mu, k, j, quotient)
    @reduced_basis[k] = subtract_multiple(
      @reduced_basis[k],
      @reduced_basis[j], quotient)
    @transformation[k] = subtract_multiple(
      @transformation[k],
      @transformation[j], quotient)
    l = 0
    while l < j
      mu[k][l] = mu[k][l] - quotient * mu[j][l]
      l += 1
    mu[k][j] = mu[k][j] - quotient

  # Swap b_{k-1} and b_k and update mu/norms in place (the classical LLL
  # exchange formulas; O(rank) instead of an O(rank³) rebuild). `norms`
  # entries stay positive: the Gram matrix is positive definite and the
  # basis stays full rank, so B' = |b*_k|² + mu²·|b*_{k-1}|² > 0.
  -> swap_step(mu, norms, k)
    swapped_mu = mu[k][k - 1]
    updated_norm = norms[k] + swapped_mu * swapped_mu * norms[k - 1]
    revised_mu = swapped_mu * norms[k - 1] / updated_norm
    norms[k] = norms[k - 1] * norms[k] / updated_norm
    norms[k - 1] = updated_norm
    temporary = @reduced_basis[k]
    @reduced_basis[k] = @reduced_basis[k - 1]
    @reduced_basis[k - 1] = temporary
    temporary = @transformation[k]
    @transformation[k] = @transformation[k - 1]
    @transformation[k - 1] = temporary
    j = 0
    while j < k - 1
      temporary = mu[k][j]
      mu[k][j] = mu[k - 1][j]
      mu[k - 1][j] = temporary
      j += 1
    i = k + 1
    while i < rank
      shifted = mu[i][k]
      mu[i][k] = mu[i][k - 1] - swapped_mu * shifted
      mu[i][k - 1] = shifted + revised_mu * mu[i][k]
      i += 1
    mu[k][k - 1] = revised_mu

  -> reduce_approximately
    data = compute_approximate_gram_schmidt(
      @reduced_basis)
    mu = data[0]
    norms = data[1]
    k = 1
    steps = 0
    while k < rank
      steps += 1
      if steps > 100_000
        @reduced_basis = copy_integer_matrix(
          @source_basis)
        @transformation = integer_identity(rank)
        return reduce
      j = k - 1
      while j >= 0
        quotient = mu[k][j].round
        if quotient != 0
          size_reduce_step(mu, k, j, quotient)
        j -= 1

      delta_float = @delta.to_f
      threshold = delta_float - mu[k][k - 1] * mu[k][k - 1]
      if norms[k] >= threshold * norms[k - 1]
        k += 1
      else
        swap_step(mu, norms, k)
        k -= 1
        k = 1 if k < 1
    self

  -> reduce
    data = compute_gram_schmidt(@reduced_basis)
    mu = data[0]
    norms = data[1]
    k = 1
    while k < rank
      j = k - 1
      while j >= 0
        quotient = nearest_integer(mu[k][j])
        if quotient != 0
          size_reduce_step(mu, k, j, quotient)
        j -= 1

      threshold = @delta - mu[k][k - 1] ** 2
      if norms[k] >= threshold * norms[k - 1]
        k += 1
      else
        swap_step(mu, norms, k)
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


+ ApproximateGramLatticeBasisSearch
  -> new(gram_matrix, source_basis)
    initialize_approximate_gram_search(
      gram_matrix, source_basis, ~0.75,
      200)

  -> new(gram_matrix, source_basis, delta)
    initialize_approximate_gram_search(
      gram_matrix, source_basis, delta,
      200)

  -> new(gram_matrix, source_basis, delta,
         step_limit)
    initialize_approximate_gram_search(
      gram_matrix, source_basis, delta,
      step_limit)

  -> initialize_approximate_gram_search(
       gram_matrix, source_basis, delta,
       step_limit)
    @delta = delta + ~0.0
    if !ExactIntegerLinearAlgebra.integer_value?(step_limit)
      raise "approximate LLL step limit must be an integer"
    if step_limit < 1
      raise "approximate LLL step limit must be positive"
    @step_limit = step_limit
    @steps = 0
    @gram_matrix = []
    gram_matrix.each -> (source)
      row = []
      source.each -> (entry)
        row.push(Rational.coerce(entry).to_f)
      @gram_matrix.push(row)
    @basis = []
    source_basis.each -> (source)
      row = []
      source.each -> (entry)
        if !ExactIntegerLinearAlgebra.integer_value?(entry)
          raise "approximate LLL source basis must be integral"
        row.push(entry)
      @basis.push(row)
    @completed = valid_shape?
    reduce if @completed

  -> valid_shape?
    size = @gram_matrix.size
    return false if size < 1
    return false if @basis.size != size
    i = 0
    while i < size
      return false if @gram_matrix[i].size != size
      return false if @basis[i].size != size
      i += 1
    determinant = ExactIntegerLinearAlgebra.determinant(
      @basis)
    !determinant.zero?

  -> rank
    @basis.size

  -> completed?
    @completed

  -> step_limit
    @step_limit

  -> steps
    @steps

  -> reduced_basis
    out = []
    @basis.each -> (source)
      row = []
      source.each -> (entry)
        row.push(entry)
      out.push(row)
    out

  -> finite_float?(value)
    return false if value != value
    value.abs < ~1.0e300

  -> inner_product(left, right)
    value = ~0.0
    i = 0
    while i < rank
      j = 0
      while j < rank
        left_value = left[i] + ~0.0
        right_value = right[j] + ~0.0
        value += left_value * @gram_matrix[i][j] * right_value
        j += 1
      i += 1
    value

  -> gram_schmidt
    stars = []
    mu = []
    norms = []
    i = 0
    while i < rank
      star = []
      @basis[i].each -> (entry)
        star.push(entry + ~0.0)
      row = []
      rank.times -> row.push(~0.0)
      j = 0
      while j < i
        return nil if norms[j] == ~0.0
        coefficient = inner_product(
          @basis[i], stars[j]) / norms[j]
        return nil if !finite_float?(coefficient)
        row[j] = coefficient
        coordinate = 0
        while coordinate < rank
          star[coordinate] -= coefficient * stars[j][coordinate]
          coordinate += 1
        j += 1
      norm = inner_product(star, star)
      return nil if !finite_float?(norm) || norm <= ~0.0
      stars.push(star)
      mu.push(row)
      norms.push(norm)
      i += 1
    [mu, norms]

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
      @steps += 1
      if @steps > @step_limit
        @completed = false
        return self
      data = gram_schmidt
      if data == nil
        @completed = false
        return self
      mu = data[0]
      norms = data[1]
      j = k - 1
      while j >= 0
        quotient = mu[k][j].round
        if quotient != 0
          @basis[k] = subtract_multiple(
            @basis[k], @basis[j], quotient)
          data = gram_schmidt
          if data == nil
            @completed = false
            return self
          mu = data[0]
          norms = data[1]
        j -= 1
      threshold = @delta - mu[k][k - 1] * mu[k][k - 1]
      if norms[k] >= threshold * norms[k - 1]
        k += 1
      else
        temporary = @basis[k]
        @basis[k] = @basis[k - 1]
        @basis[k - 1] = temporary
        k -= 1
        k = 1 if k < 1
    self


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
    matrix = multiplication_matrix_from_coordinates(
      coordinates)
    if matrix.size < 6
      return ExactIntegerLinearAlgebra.determinant(
        matrix)
    ExactIntegerLinearAlgebra.modular_determinant(
      matrix)

  -> reduced_frobenius_basis
    out = []
    frobenius_lattice_reduction.reduced_basis.each -> (coordinates)
      out.push(element(coordinates))
    out

  -> approximate_frobenius_coordinate_basis
    source = []
    i = 0
    while i < rank
      row = []
      j = 0
      while j < rank
        row.push(i == j ? 1 : 0)
        j += 1
      source.push(row)
      i += 1
    search = ApproximateGramLatticeBasisSearch.new(
      frobenius_gram_matrix, source)
    return source if !search.completed?
    search.reduced_basis

  -> approximate_frobenius_basis
    out = []
    approximate_frobenius_coordinate_basis.each -> (coordinates)
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

  -> approximate_frobenius_coordinate_basis
    source = order_coordinate_basis
    search = ApproximateGramLatticeBasisSearch.new(
      @order.frobenius_gram_matrix,
      source)
    return source if !search.completed?
    search.reduced_basis

  -> reduced_frobenius_coordinate_basis
    frobenius_lattice_reduction.reduced_basis

  -> reduced_frobenius_basis
    out = []
    frobenius_lattice_reduction.reduced_basis.each -> (coordinates)
      out.push(@order.element(coordinates))
    out
