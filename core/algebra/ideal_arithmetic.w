# Canonical ideal arithmetic in exact orders. Invertible fractional ideals
# additionally require a certified maximal order.
#
# Products and sums begin with redundant Z-generators.  A certified row
# Hermite normal form replaces them by a canonical full-rank lattice basis.
# This makes ideal equality, norm, powers, principal ideals, and containment
# exact.  Prime valuations are then finite membership witnesses:
#
#   ord_P(x) = k  iff  x is in P^k but not P^(k+1),
#
# with the analogous containment criterion for integral ideals.

+ IntegerLinearAlgebra
  -> .copy_row(row)
    out = []
    row.each -> (entry)
      out.push(entry)
    out

  -> .copy_matrix(matrix)
    out = []
    matrix.each -> (row)
      out.push(IntegerLinearAlgebra.copy_row(row))
    out

  -> .integer_value?(value)
    name = value.class_name
    integer = name == "Int"
    integer = true if name == "BigInt"
    integer

  -> .extended_gcd(left, right)
    a = left.abs
    b = right.abs
    old_r = a
    r = b
    old_s = 1
    s = 0
    old_t = 0
    t = 1
    while r != 0
      quotient = old_r / r
      next_r = old_r - quotient * r
      old_r = r
      r = next_r
      next_s = old_s - quotient * s
      old_s = s
      s = next_s
      next_t = old_t - quotient * t
      old_t = t
      t = next_t
    old_s = 0 - old_s if left < 0
    old_t = 0 - old_t if right < 0
    [old_r, old_s, old_t]

  -> .floor_quotient(value, positive_divisor)
    if positive_divisor <= 0
      raise "floor quotient needs a positive divisor"
    quotient = value / positive_divisor
    remainder = value - quotient * positive_divisor
    quotient -= 1 if remainder < 0
    quotient

  -> .combine_rows(left, left_scale,
                    right, right_scale)
    if left.size != right.size
      raise "integer row dimensions do not match"
    out = []
    i = 0
    while i < left.size
      value = left_scale * left[i]
      value += right_scale * right[i]
      out.push(value)
      i += 1
    out

  -> .row_hnf_shape?(basis)
    return false if basis.class_name != "Array"
    size = basis.size
    return false if size == 0
    i = 0
    while i < size
      row = basis[i]
      return false if row.class_name != "Array"
      return false if row.size != size
      j = 0
      while j < size
        return false if !IntegerLinearAlgebra.integer_value?(
          row[j])
        if j < i
          return false if row[j] != 0
        j += 1
      return false if row[i] <= 0
      above = 0
      while above < i
        value = basis[above][i]
        return false if value < 0 || value >= row[i]
        above += 1
      i += 1
    true


+ IntegerHermiteNormalFormCertificate
  -> new(@computation)
    @verified_cache = nil

  -> computation
    @computation

  -> verified?
    answer = false
    begin
      answer = verify!
    rescue error
      answer = false
    answer

  -> verify!
    return true if @verified_cache == true
    if @computation.class_name != "IntegerHermiteNormalForm"
      raise "HNF certificate has the wrong computation"
    generators = @computation.generator_rows
    basis = @computation.basis_rows
    combinations = @computation.basis_combinations
    if generators.size == 0
      raise "HNF certificate has no generators"
    width = generators[0].size
    if width < 1 || basis.size != width
      raise "HNF basis has the wrong rank"
    if combinations.size != width
      raise "HNF certificate has the wrong combination count"
    if !IntegerLinearAlgebra.row_hnf_shape?(basis)
      raise "displayed integer basis is not in row HNF"

    i = 0
    while i < basis.size
      coefficients = combinations[i]
      if coefficients.size != generators.size
        raise "HNF combination has the wrong width"
      replay = []
      column = 0
      while column < width
        value = 0 ## big
        generator = 0
        while generator < generators.size
          value += coefficients[generator] * generators[generator][column]
          generator += 1
        replay.push(value)
        column += 1
      if replay.to_s != basis[i].to_s
        raise "HNF basis row is not the displayed generator combination"
      i += 1

    basis_matrix = ExactRationalLinearAlgebra.matrix_from_columns(
      basis)
    inverse = ExactRationalLinearAlgebra.inverse(
      basis_matrix)
    generator = 0
    while generator < generators.size
      rational_row = []
      generators[generator].each -> (entry)
        rational_row.push(Rational.new(entry))
      coordinates = ExactRationalLinearAlgebra.matrix_vector(
        inverse, rational_row)
      i = 0
      while i < coordinates.size
        if coordinates[i].denominator != 1
          raise "original generator is outside the displayed HNF lattice"
        i += 1
      generator += 1
    @verified_cache = true
    true

  -> certified?
    verified?

  -> to_s
    text = "IntegerHermiteNormalFormCertificate(rank "
    text + @computation.rank.to_s + ")"

  -> inspect
    to_s


+ IntegerHermiteNormalForm
  -> new(generator_rows)
    invalid = generator_rows.class_name != "Array"
    if !invalid
      invalid = true if generator_rows.size == 0
    if invalid
      raise "row HNF needs integer generators"
    @generator_rows = []
    width = nil
    generator_rows.each -> (source)
      if source.class_name != "Array"
        raise "row HNF generators must be arrays"
      width = source.size if width == nil
      if source.size != width || width < 1
        raise "row HNF generators have inconsistent dimensions"
      row = []
      source.each -> (entry)
        if !IntegerLinearAlgebra.integer_value?(entry)
          raise "row HNF entries must be integers"
        row.push(entry)
      @generator_rows.push(row)
    if @generator_rows.size < width
      raise "row HNF needs at least rank-many generators"
    @rank = width
    compute_hnf
    @certificate_cache = IntegerHermiteNormalFormCertificate.new(
      self)
    if !@certificate_cache.verified?
      raise "integer row HNF failed certification"

  -> compute_hnf
    rows = IntegerLinearAlgebra.copy_matrix(
      @generator_rows)
    row_count = rows.size
    combinations = []
    i = 0
    while i < row_count
      combination = []
      j = 0
      while j < row_count
        combination.push(i == j ? 1 : 0)
        j += 1
      combinations.push(combination)
      i += 1

    pivot = 0
    column = 0
    while column < @rank
      selected = pivot
      while selected < row_count
        break if rows[selected][column] != 0
        selected += 1
      if selected == row_count
        raise "integer generators do not have full rank"
      if selected != pivot
        temporary = rows[pivot]
        rows[pivot] = rows[selected]
        rows[selected] = temporary
        temporary = combinations[pivot]
        combinations[pivot] = combinations[selected]
        combinations[selected] = temporary

      row = pivot + 1
      while row < row_count
        if rows[row][column] != 0
          left_value = rows[pivot][column]
          right_value = rows[row][column]
          bezout = IntegerLinearAlgebra.extended_gcd(
            left_value, right_value)
          gcd = bezout[0]
          old_pivot = rows[pivot]
          old_row = rows[row]
          old_pivot_combination = combinations[pivot]
          old_row_combination = combinations[row]
          rows[pivot] = IntegerLinearAlgebra.combine_rows(
            old_pivot, bezout[1],
            old_row, bezout[2])
          rows[row] = IntegerLinearAlgebra.combine_rows(
            old_pivot, 0 - right_value / gcd,
            old_row, left_value / gcd)
          combinations[pivot] = IntegerLinearAlgebra.combine_rows(
            old_pivot_combination, bezout[1],
            old_row_combination, bezout[2])
          combinations[row] = IntegerLinearAlgebra.combine_rows(
            old_pivot_combination,
            0 - right_value / gcd,
            old_row_combination,
            left_value / gcd)
        row += 1

      if rows[pivot][column] < 0
        rows[pivot] = IntegerLinearAlgebra.combine_rows(
          rows[pivot], -1, rows[pivot], 0)
        combinations[pivot] = IntegerLinearAlgebra.combine_rows(
          combinations[pivot], -1,
          combinations[pivot], 0)

      row = 0
      while row < pivot
        quotient = IntegerLinearAlgebra.floor_quotient(
          rows[row][column],
          rows[pivot][column])
        if quotient != 0
          rows[row] = IntegerLinearAlgebra.combine_rows(
            rows[row], 1,
            rows[pivot], 0 - quotient)
          combinations[row] = IntegerLinearAlgebra.combine_rows(
            combinations[row], 1,
            combinations[pivot], 0 - quotient)
        row += 1
      pivot += 1
      column += 1

    row = @rank
    while row < row_count
      nonzero = false
      rows[row].each -> (entry)
        nonzero = true if entry != 0
      if nonzero
        raise "row HNF left a nonzero redundant row"
      row += 1
    @basis_rows = []
    @basis_combinations = []
    i = 0
    while i < @rank
      @basis_rows.push(rows[i])
      @basis_combinations.push(combinations[i])
      i += 1

  -> rank
    @rank

  -> generator_rows
    IntegerLinearAlgebra.copy_matrix(
      @generator_rows)

  -> basis_rows
    IntegerLinearAlgebra.copy_matrix(
      @basis_rows)

  -> basis_combinations
    IntegerLinearAlgebra.copy_matrix(
      @basis_combinations)

  -> determinant
    result = 1 ## big
    i = 0
    while i < @rank
      result *= @basis_rows[i][i]
      i += 1
    result

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> to_s
    text = "IntegerHermiteNormalForm(rank " + @rank.to_s
    text + ", determinant " + determinant.to_s + ")"

  -> inspect
    to_s


+ AlgebraIdealOperationCertificate
  -> new(@operation, @left, @right, @result)
    @verified_cache = nil

  -> operation
    @operation

  -> left
    @left

  -> right
    @right

  -> result
    @result

  -> verified?
    answer = false
    begin
      answer = verify!
    rescue error
      answer = false
    answer

  -> verify!
    return true if @verified_cache == true
    invalid_ideal = @left.class_name != "AlgebraOrderIdeal"
    invalid_ideal = true if @right.class_name != "AlgebraOrderIdeal"
    invalid_ideal = true if @result.class_name != "AlgebraOrderIdeal"
    if invalid_ideal
      raise "ideal-operation certificate needs integral ideals"
    uncertified = !@left.certificate.verified?
    uncertified = true if !@right.certificate.verified?
    uncertified = true if !@result.certificate.verified?
    if uncertified
      raise "ideal-operation certificate has an uncertified ideal"
    wrong_order = !@left.order.same_order?(
      @right.order)
    if !wrong_order
      wrong_order = true if !@left.order.same_order?(
        @result.order)
    if wrong_order
      raise "ideal operation changes its parent order"
    expected = nil
    if @operation == :product
      expected = @left.raw_product(@right)
    elsif @operation == :sum
      expected = @left.raw_sum(@right)
    else
      raise "unknown certified ideal operation"
    if !@result.eql?(expected)
      raise "ideal operation does not replay"
    @verified_cache = true
    true

  -> certified?
    verified?

  -> to_s
    text = "AlgebraIdealOperationCertificate("
    text + @operation.to_s + ")"

  -> inspect
    to_s


+ AlgebraIdealComputation
  -> new(@operation, @left, @right)
    if @operation == :product
      @ideal = @left.raw_product(@right)
    elsif @operation == :sum
      @ideal = @left.raw_sum(@right)
    else
      raise "unknown ideal computation"
    @certificate = AlgebraIdealOperationCertificate.new(
      @operation, @left, @right, @ideal)
    if !@certificate.verified?
      raise "ideal computation failed certification"

  -> operation
    @operation

  -> left
    @left

  -> right
    @right

  -> ideal
    @ideal

  -> result
    @ideal

  -> certificate
    @certificate

  -> certified?
    @certificate.verified?

  -> to_s
    "AlgebraIdealComputation(" + @operation.to_s + ")"

  -> inspect
    to_s


+ AlgebraOrderIdeal
  -> .from_lattice_generators(
       order, generators, kind = :ideal,
       prime = nil)
    if order.class_name != "AlgebraOrder"
      raise "ideal lattice generators need an AlgebraOrder"
    invalid = generators.class_name != "Array"
    if !invalid
      invalid = true if generators.size == 0
    if invalid
      raise "ideal lattice needs generators"
    integer_rows = []
    generators.each -> (value)
      element = order.algebra.normalize_element(value)
      if !order.contains?(element)
        raise "integral ideal generator is outside its order"
      coordinates = order.coordinates(element)
      row = []
      coordinates.each -> (coefficient)
        if coefficient.denominator != 1
          raise "integral ideal generator has nonintegral order coordinates"
        row.push(coefficient.numerator)
      integer_rows.push(row)
    hnf = IntegerHermiteNormalForm.new(integer_rows)
    relative_basis = []
    hnf.basis_rows.each -> (row)
      vector = []
      row.each -> (entry)
        vector.push(Rational.new(entry))
      relative_basis.push(vector)
    ambient_basis = ExactRationalLinearAlgebra.compose_columns(
      order.basis_vectors, relative_basis)
    AlgebraOrderIdeal.new(
      order, ambient_basis, kind, prime)

  -> .unit(order)
    AlgebraOrderIdeal.new(
      order, order.basis_vectors, :unit)

  -> .principal(order, value)
    element = order.coerce(value)
    if element.zero?
      raise "zero principal ideal is not a full-rank lattice"
    generators = []
    order.basis.each -> (basis_element)
      generators.push(order.algebra.multiply(
        element, basis_element))
    AlgebraOrderIdeal.from_lattice_generators(
      order, generators, :principal)

  -> integral?
    @order.lattice.contains_lattice?(@lattice)

  -> index
    if !integral?
      raise "fractional order lattice has no integral ideal index"
    @order.lattice.index_from(@lattice)

  -> norm
    index

  -> unit?
    @lattice.same_lattice?(@order.lattice)

  -> proper?
    !unit?

  -> contains_ideal?(other)
    wrong = other.class_name != "AlgebraOrderIdeal"
    if !wrong
      wrong = true if !@order.same_order?(
        other.order)
    if wrong
      return false
    @lattice.contains_lattice?(other.lattice)

  -> eql?(other)
    return false if other.class_name != "AlgebraOrderIdeal"
    return false if !@order.same_order?(other.order)
    @lattice.same_lattice?(other.lattice)

  -> ==/1
    self.eql?(@1)

  -> raw_sum(other)
    wrong = other.class_name != "AlgebraOrderIdeal"
    if !wrong
      wrong = true if !@order.same_order?(
        other.order)
    if wrong
      raise "cannot add ideals from different orders"
    generators = basis + other.basis
    AlgebraOrderIdeal.from_lattice_generators(
      @order, generators, :sum)

  -> raw_product(other)
    wrong = other.class_name != "AlgebraOrderIdeal"
    if !wrong
      wrong = true if !@order.same_order?(
        other.order)
    if wrong
      raise "cannot multiply ideals from different orders"
    generators = []
    left_basis = basis
    right_basis = other.basis
    i = 0
    while i < left_basis.size
      j = 0
      while j < right_basis.size
        generators.push(@order.algebra.multiply(
          left_basis[i], right_basis[j]))
        j += 1
      i += 1
    AlgebraOrderIdeal.from_lattice_generators(
      @order, generators, :product)

  -> +(other)
    raw_sum(other)

  -> *(other)
    raw_product(other)

  -> sum_with_certificate(other)
    AlgebraIdealComputation.new(:sum, self, other)

  -> product_with_certificate(other)
    AlgebraIdealComputation.new(
      :product, self, other)

  -> **(exponent)
    if !IntegerLinearAlgebra.integer_value?(exponent)
      raise "integral ideal exponent must be an integer"
    if exponent < 0
      raise "negative ideal powers need fractional ideal inversion"
    result = AlgebraOrderIdeal.unit(@order)
    factor = self
    remaining = exponent
    while remaining > 0
      result = result.raw_product(factor) if remaining.odd?
      remaining = remaining / 2
      factor = factor.raw_product(factor) if remaining > 0
    result

  -> to_s
    text = "OrderIdeal(" + @kind.to_s
    text + ", norm " + norm.to_s + ")"


+ AlgebraOrder
  -> unit_ideal
    AlgebraOrderIdeal.unit(self)

  -> principal_ideal(value)
    AlgebraOrderIdeal.principal(self, value)

  # The O-ideal generated by the supplied elements, not merely their
  # additive Z-span.
  -> ideal(generators)
    values = generators
    values = [generators] if generators.class_name != "Array"
    expanded = []
    values.each -> (value)
      element = coerce(value)
      basis.each -> (basis_element)
        expanded.push(@algebra.multiply(
          element, basis_element))
    AlgebraOrderIdeal.from_lattice_generators(
      self, expanded, :generated)


+ AlgebraPrimeIdeal
  -> as_ideal
    if @as_ideal_cache == nil
      @as_ideal_cache = AlgebraOrderIdeal.new(
        @order, basis_vectors, :prime,
        rational_prime)
    @as_ideal_cache

  -> ideal_power(exponent)
    as_ideal ** exponent

  # Valuation walks need consecutive powers and reuse them across many
  # elements. Keep that cache separate so an arbitrary call to
  # ideal_power(n) retains exponentiation-by-squaring behavior instead of
  # materializing every power through n.
  -> valuation_ideal_power(exponent)
    if !IntegerLinearAlgebra.integer_value?(exponent)
      raise "prime-ideal exponent must be an integer"
    if exponent < 0
      raise "prime-ideal power exponent must be nonnegative"
    if @ideal_power_cache == nil
      @ideal_power_cache = [
        AlgebraOrderIdeal.unit(@order),
        as_ideal
      ]
    while @ideal_power_cache.size <= exponent
      previous = @ideal_power_cache[
        @ideal_power_cache.size - 1]
      @ideal_power_cache.push(
        previous.raw_product(as_ideal))
    @ideal_power_cache[exponent]

+ ExactIntegerArithmetic
  -> .factor_pairs(value, search_limit = 1_000_000)
    if !IntegerLinearAlgebra.integer_value?(value)
      raise "bounded integer factorization needs an integer"
    if value < 1
      raise "bounded integer factorization needs a positive integer"
    if search_limit < 1
      raise "bounded integer factor search limit must be positive"
    remaining = value
    factors = []
    candidate = 2
    attempts = 0
    while candidate * candidate <= remaining
      attempts += 1
      if attempts > search_limit
        raise "integer factor search limit exceeded; ideal factorization unknown"
      exponent = 0
      while remaining % candidate == 0
        remaining = remaining / candidate
        exponent += 1
      factors.push([candidate, exponent]) if exponent > 0
      candidate = candidate == 2 ? 3 : candidate + 2
    factors.push([remaining, 1]) if remaining > 1
    factors

  -> .factor_pairs_verified?(value, factors)
    product = 1 ## big
    previous = 1
    i = 0
    while i < factors.size
      factor = factors[i]
      return false if factor.class_name != "Array"
      return false if factor.size != 2
      prime = factor[0]
      exponent = factor[1]
      return false if prime <= previous
      return false if !prime.prime? || exponent < 1
      product *= prime ** exponent
      previous = prime
      i += 1
    product == value


+ AlgebraPrimeValuationCertificate
  -> new(@computation)
    @verified_cache = nil

  -> computation
    @computation

  -> verified?
    answer = false
    begin
      answer = verify!
    rescue error
      answer = false
    answer

  -> verify!
    return true if @verified_cache == true
    if @computation.class_name != "AlgebraPrimeValuationComputation"
      raise "prime-valuation certificate has the wrong computation"
    prime_ideal = @computation.prime_ideal
    if !prime_ideal.certificate.verified?
      raise "prime valuation has an uncertified prime ideal"
    target = @computation.target
    target_kind = @computation.target_kind
    if @computation.infinite?
      if target_kind != :element || !target.zero?
        raise "only zero has infinite certified prime valuation"
      @verified_cache = true
      return true
    value = @computation.value
    integer_value = value.class_name == "Int"
    integer_value = true if value.class_name == "BigInt"
    if !integer_value
      raise "finite prime valuation is not an integer"
    if value < 0
      raise "integral prime valuation cannot be negative"
    if value == 0
      if target_kind == :element
        return false if prime_ideal.contains?(target)
      elsif target_kind == :ideal
        return false if prime_ideal.as_ideal.contains_ideal?(
          target)
      else
        raise "unknown prime-valuation target kind"
      @verified_cache = true
      return true
    power = prime_ideal.valuation_ideal_power(value)
    next_power = prime_ideal.valuation_ideal_power(
      value + 1)
    contained = false
    contained_next = false
    if target_kind == :element
      contained = power.contains?(target)
      contained_next = next_power.contains?(target)
    elsif target_kind == :ideal
      if target.class_name != "AlgebraOrderIdeal"
        raise "ideal valuation has the wrong target"
      contained = power.contains_ideal?(target)
      contained_next = next_power.contains_ideal?(target)
    else
      raise "unknown prime-valuation target kind"
    if !contained || contained_next
      raise "prime valuation membership witnesses do not isolate the exponent"
    @verified_cache = true
    true

  -> certified?
    verified?

  -> to_s
    text = "AlgebraPrimeValuationCertificate("
    text + @computation.value.to_s + ")"

  -> inspect
    to_s


+ AlgebraPrimeValuationComputation
  -> new(@prime_ideal, target,
         @step_limit = 10_000)
    if @prime_ideal.class_name != "AlgebraPrimeIdeal"
      raise "prime valuation needs an AlgebraPrimeIdeal"
    if @step_limit < 0
      raise "prime valuation step limit must be nonnegative"
    @order = @prime_ideal.order
    if target.class_name == "AlgebraOrderIdeal"
      if !@order.same_order?(target.order)
        raise "ideal valuation target belongs to a different order"
      @target_kind = :ideal
      @target = target
    else
      @target_kind = :element
      @target = @order.coerce(target)
    if @target_kind == :element && @target.zero?
      @value = :infinity
    elsif !target_in_prime?
      @value = 0
    else
      compute_finite_valuation
    @certificate_cache = AlgebraPrimeValuationCertificate.new(
      self)
    if !@certificate_cache.verified?
      raise "prime valuation failed certification"

  -> compute_finite_valuation
    @value = 0
    while true
      next_power = @prime_ideal.valuation_ideal_power(
        @value + 1)
      contained = false
      if @target_kind == :element
        contained = next_power.contains?(@target)
      else
        contained = next_power.contains_ideal?(
          @target)
      break if !contained
      if @value >= @step_limit
        raise "prime valuation step limit exceeded; valuation unknown"
      @value += 1

  -> target_in_prime?
    if @target_kind == :element
      return @prime_ideal.contains?(@target)
    @prime_ideal.as_ideal.contains_ideal?(@target)

  -> prime_ideal
    @prime_ideal

  -> order
    @order

  -> target
    @target

  -> target_kind
    @target_kind

  -> value
    @value

  -> infinite?
    @value == :infinity

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> to_s
    text = "AlgebraPrimeValuation("
    text + @value.to_s + ")"

  -> inspect
    to_s


+ AlgebraPrimeIdeal
  -> valuation_with_certificate(
       value, step_limit = 10_000)
    AlgebraPrimeValuationComputation.new(
      self, value, step_limit)

  -> valuation(value, step_limit = 10_000)
    valuation_with_certificate(
      value, step_limit).value

  -> ideal_valuation_with_certificate(
       ideal, step_limit = 10_000)
    AlgebraPrimeValuationComputation.new(
      self, ideal, step_limit)

  -> ideal_valuation(
       ideal, step_limit = 10_000)
    ideal_valuation_with_certificate(
      ideal, step_limit).value


+ AlgebraIdealFactorizationCertificate
  -> new(@factorization)
    @verified_cache = nil

  -> factorization
    @factorization

  -> verified?
    answer = false
    begin
      answer = verify!
    rescue error
      answer = false
    answer

  -> verify!
    return true if @verified_cache == true
    if @factorization.class_name != "AlgebraIdealFactorization"
      raise "ideal-factorization certificate has the wrong subject"
    ideal = @factorization.ideal
    if !ideal.certificate.verified? || !ideal.integral?
      raise "ideal factorization needs a certified integral ideal"
    rational_factors = @factorization.rational_norm_factors
    if !ExactIntegerArithmetic.factor_pairs_verified?(
         ideal.norm, rational_factors)
      raise "ideal norm factorization does not reconstruct"
    factors = @factorization.factors
    valuations = @factorization.valuation_computations
    if factors.size != valuations.size
      raise "ideal factorization lost a valuation certificate"
    product = AlgebraOrderIdeal.unit(ideal.order)
    norm_product = 1 ## big
    i = 0
    while i < factors.size
      prime_ideal = factors[i][0]
      exponent = factors[i][1]
      valuation = valuations[i]
      if prime_ideal.class_name != "AlgebraPrimeIdeal"
        raise "ideal factorization has a nonprime factor"
      if !prime_ideal.order.same_order?(ideal.order)
        raise "ideal factorization changes the parent order"
      if exponent < 1
        raise "ideal factorization has a nonpositive exponent"
      if !valuation.certificate.verified?
        raise "ideal factorization has an uncertified valuation"
      wrong_valuation = valuation.target_kind != :ideal
      wrong_valuation = true if !valuation.target.eql?(ideal)
      wrong_valuation = true if valuation.value != exponent
      if wrong_valuation
        raise "ideal factorization exponent is not its certified valuation"
      product = product.raw_product(
        prime_ideal.as_ideal ** exponent)
      norm_product *= prime_ideal.norm ** exponent
      i += 1
    if !product.eql?(ideal)
      raise "prime-ideal product does not reconstruct the ideal"
    if norm_product != ideal.norm
      raise "prime-ideal norms do not reconstruct the ideal norm"
    @verified_cache = true
    true

  -> certified?
    verified?

  -> to_s
    text = "AlgebraIdealFactorizationCertificate("
    text + @factorization.factors.size.to_s + " factors)"

  -> inspect
    to_s


+ AlgebraIdealFactorization
  -> new(@ideal,
         @factor_search_limit = 1_000_000,
         @valuation_step_limit = 10_000)
    if @ideal.class_name != "AlgebraOrderIdeal"
      raise "ideal factorization needs an AlgebraOrderIdeal"
    if !@ideal.integral?
      raise "ideal factorization currently needs an integral ideal"
    @rational_norm_factors = ExactIntegerArithmetic.factor_pairs(
      @ideal.norm, @factor_search_limit)
    @factors = []
    @valuation_computations = []
    @rational_norm_factors.each -> (rational_factor)
      decomposition = @ideal.order.prime_decomposition(
        rational_factor[0])
      decomposition.prime_ideals.each -> (prime_ideal)
        valuation = prime_ideal.ideal_valuation_with_certificate(
          @ideal, @valuation_step_limit)
        if valuation.value > 0
          @factors.push([
            prime_ideal, valuation.value])
          @valuation_computations.push(
            valuation)
    @certificate_cache = AlgebraIdealFactorizationCertificate.new(
      self)
    if !@certificate_cache.verified?
      raise "ideal factorization failed certification"

  -> ideal
    @ideal

  -> rational_norm_factors
    out = []
    @rational_norm_factors.each -> (factor)
      out.push([factor[0], factor[1]])
    out

  -> factors
    out = []
    @factors.each -> (factor)
      out.push([factor[0], factor[1]])
    out

  -> valuation_computations
    out = []
    @valuation_computations.each -> (valuation)
      out.push(valuation)
    out

  -> size
    @factors.size

  -> [](index)
    factor = @factors[index]
    [factor[0], factor[1]]

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> to_s
    parts = []
    @factors.each -> (factor)
      text = factor[0].to_s + "^"
      parts.push(text + factor[1].to_s)
    return "1" if parts.size == 0
    parts.join(" * ")

  -> inspect
    to_s


+ AlgebraOrderIdeal
  -> factorization(
       factor_search_limit = 1_000_000,
       valuation_step_limit = 10_000)
    AlgebraIdealFactorization.new(
      self, factor_search_limit,
      valuation_step_limit)

  -> factor_with_certificate(
       factor_search_limit = 1_000_000,
       valuation_step_limit = 10_000)
    factorization(
      factor_search_limit,
      valuation_step_limit)


+ NumberFieldIdealCertificate
  -> new(@ideal)

  -> verified?
    return false if @ideal.class_name != "NumberFieldIdeal"
    field = @ideal.field
    algebra_ideal = @ideal.algebra_ideal
    return false if !algebra_ideal.certificate.verified?
    return false if !algebra_ideal.order.same_order?(
      field.certify_maximal_order)
    vectors = algebra_ideal.basis_vectors
    i = 0
    while i < vectors.size
      element = field.generic_order_vector_to_element(
        vectors[i])
      return false if !@ideal.contains?(element)
      i += 1
    true

  -> certified?
    verified?

  -> to_s
    text = "NumberFieldIdealCertificate(norm "
    text + @ideal.norm.to_s + ")"

  -> inspect
    to_s


+ NumberFieldIdeal
  -> new(@field, @algebra_ideal)
    if @field.class_name != "NumberField"
      raise "number-field ideal needs a NumberField"
    if @algebra_ideal.class_name != "AlgebraOrderIdeal"
      raise "number-field ideal needs an AlgebraOrderIdeal"
    if !certificate.verified?
      raise "number-field ideal failed certification"

  -> field
    @field

  -> algebra_ideal
    @algebra_ideal

  -> order
    @algebra_ideal.order

  -> norm
    @algebra_ideal.norm

  -> basis
    out = []
    @algebra_ideal.basis_vectors.each -> (vector)
      out.push(@field.generic_order_vector_to_element(
        vector))
    out

  -> contains?(value)
    coordinates = @field.maximal_order_coordinates(value)
    return false if coordinates == nil
    element = order.element(coordinates)
    @algebra_ideal.contains?(element)

  -> unit?
    @algebra_ideal.unit?

  -> proper?
    @algebra_ideal.proper?

  -> +(other)
    require_same_field_ideal(other)
    NumberFieldIdeal.new(
      @field,
      @algebra_ideal.raw_sum(
        other.algebra_ideal))

  -> *(other)
    require_same_field_ideal(other)
    NumberFieldIdeal.new(
      @field,
      @algebra_ideal.raw_product(
        other.algebra_ideal))

  -> **(exponent)
    NumberFieldIdeal.new(
      @field, @algebra_ideal ** exponent)

  -> require_same_field_ideal(other)
    wrong = other.class_name != "NumberFieldIdeal"
    if !wrong
      wrong = true if other.field != @field
    if wrong
      raise "number-field ideals belong to different fields"
    true

  -> factorization(
       factor_search_limit = 1_000_000,
       valuation_step_limit = 10_000)
    NumberFieldIdealFactorization.new(
      self, @algebra_ideal.factorization(
        factor_search_limit,
        valuation_step_limit))

  -> eql?(other)
    return false if other.class_name != "NumberFieldIdeal"
    return false if other.field != @field
    @algebra_ideal.eql?(other.algebra_ideal)

  -> ==/1
    self.eql?(@1)

  -> certificate
    NumberFieldIdealCertificate.new(self)

  -> certified?
    certificate.verified?

  -> to_s
    "NumberFieldIdeal(norm " + norm.to_s + ")"

  -> inspect
    to_s


+ NumberFieldIdealFactorization
  -> new(@ideal, @algebra_factorization)
    if @ideal.class_name != "NumberFieldIdeal"
      raise "number-field ideal factorization needs a NumberFieldIdeal"
    if @algebra_factorization.class_name != "AlgebraIdealFactorization"
      raise "number-field ideal factorization needs algebra factor data"
    if !@algebra_factorization.certificate.verified?
      raise "number-field ideal factorization has an invalid certificate"
    if !@algebra_factorization.ideal.eql?(
         @ideal.algebra_ideal)
      raise "number-field ideal factorization has the wrong source"
    @factors = []
    @algebra_factorization.factors.each -> (factor)
      @factors.push([
        NumberFieldPrimeIdeal.new(
          @ideal.field, factor[0]),
        factor[1]
      ])

  -> ideal
    @ideal

  -> factors
    out = []
    @factors.each -> (factor)
      out.push([factor[0], factor[1]])
    out

  -> size
    @factors.size

  -> [](index)
    factor = @factors[index]
    [factor[0], factor[1]]

  -> certificate
    @algebra_factorization.certificate

  -> certified?
    certificate.verified?

  -> to_s
    @algebra_factorization.to_s

  -> inspect
    to_s


+ NumberField
  -> ideal(generators)
    values = generators
    values = [generators] if generators.class_name != "Array"
    order = certify_maximal_order
    algebra_values = []
    values.each -> (value)
      coordinates = maximal_order_coordinates(value)
      if coordinates == nil
        raise "number-field ideal generator is not integral"
      algebra_values.push(order.element(coordinates))
    NumberFieldIdeal.new(
      self, order.ideal(algebra_values))

  -> principal_ideal(value)
    coordinates = maximal_order_coordinates(value)
    if coordinates == nil
      raise "principal integral ideal needs an integral number-field element"
    order = certify_maximal_order
    NumberFieldIdeal.new(
      self, order.principal_ideal(
        order.element(coordinates)))

  -> unit_ideal
    NumberFieldIdeal.new(
      self, certify_maximal_order.unit_ideal)


+ NumberFieldPrimeIdeal
  -> as_ideal
    NumberFieldIdeal.new(
      @field, @algebra_prime_ideal.as_ideal)

  -> valuation_with_certificate(
       value, step_limit = 10_000)
    coordinates = @field.maximal_order_coordinates(value)
    if coordinates == nil
      raise "integral prime valuation needs an integral number-field element"
    element = @algebra_prime_ideal.order.element(
      coordinates)
    @algebra_prime_ideal.valuation_with_certificate(
      element, step_limit)

  -> valuation(value, step_limit = 10_000)
    valuation_with_certificate(
      value, step_limit).value

  -> ideal_valuation_with_certificate(
       ideal, step_limit = 10_000)
    wrong = ideal.class_name != "NumberFieldIdeal"
    if !wrong
      wrong = true if ideal.field != @field
    if wrong
      raise "number-field ideal valuation has the wrong field"
    @algebra_prime_ideal.ideal_valuation_with_certificate(
      ideal.algebra_ideal, step_limit)

  -> ideal_valuation(
       ideal, step_limit = 10_000)
    ideal_valuation_with_certificate(
      ideal, step_limit).value


+ AlgebraFractionalIdealCertificate
  -> new(@ideal)
    @verified_cache = nil

  -> ideal
    @ideal

  -> verified?
    answer = false
    begin
      answer = verify!
    rescue error
      answer = false
    answer

  -> verify!
    return true if @verified_cache == true
    if @ideal.class_name != "AlgebraFractionalIdeal"
      raise "fractional-ideal certificate has the wrong subject"
    if !@ideal.order.certificate.verified?
      raise "fractional ideal has an uncertified order"
    maximality = @ideal.order.fractional_ideal_maximality_certificate
    if !maximality.verified?
      raise "fractional ideal needs a certified maximal order"
    factors = @ideal.factors
    i = 0
    while i < factors.size
      prime_ideal = factors[i][0]
      exponent = factors[i][1]
      if prime_ideal.class_name != "AlgebraPrimeIdeal"
        raise "fractional ideal has a nonprime factor"
      if !prime_ideal.certificate.verified?
        raise "fractional ideal has an uncertified prime"
      if !prime_ideal.order.same_order?(@ideal.order)
        raise "fractional ideal factor changes the order"
      invalid_exponent = !IntegerLinearAlgebra.integer_value?(
        exponent)
      invalid_exponent = true if exponent == 0
      if invalid_exponent
        raise "fractional ideal has an invalid exponent"
      j = 0
      while j < i
        if prime_ideal.eql?(factors[j][0])
          raise "fractional ideal repeats a prime factor"
        j += 1
      i += 1
    if @ideal.norm <= Rational.new(0)
      raise "fractional ideal norm must be positive"
    @verified_cache = true
    true

  -> certified?
    verified?

  -> to_s
    text = "AlgebraFractionalIdealCertificate("
    text + @ideal.factors.size.to_s + " factors)"

  -> inspect
    to_s


+ AlgebraFractionalIdeal
  -> new(@order, factors)
    if @order.class_name != "AlgebraOrder"
      raise "fractional ideal needs an AlgebraOrder"
    if factors.class_name != "Array"
      raise "fractional ideal factors must be an Array"
    @factors = []
    factors.each -> (factor)
      invalid_factor = factor.class_name != "Array"
      if !invalid_factor
        invalid_factor = true if factor.size != 2
      if invalid_factor
        raise "fractional ideal factor must be \[prime, exponent]"
      prime_ideal = factor[0]
      exponent = factor[1]
      if prime_ideal.class_name != "AlgebraPrimeIdeal"
        raise "fractional ideal factor is not prime"
      if !IntegerLinearAlgebra.integer_value?(exponent)
        raise "fractional ideal exponent must be an integer"
      existing = nil
      i = 0
      while i < @factors.size
        unused = existing == nil
        same_prime = @factors[i][0].eql?(prime_ideal)
        existing = i if unused && same_prime
        i += 1
      if existing == nil
        @factors.push([prime_ideal, exponent]) if exponent != 0
      else
        combined = @factors[existing][1] + exponent
        if combined == 0
          @factors.delete_at(existing)
        else
          @factors[existing][1] = combined
    @certificate_cache = AlgebraFractionalIdealCertificate.new(
      self)
    if !@certificate_cache.verified?
      raise "fractional ideal failed certification"

  -> .unit(order)
    AlgebraFractionalIdeal.new(order, [])

  -> .from_integral(ideal,
                    factor_search_limit = 1_000_000,
                    valuation_step_limit = 10_000)
    if ideal.class_name != "AlgebraOrderIdeal"
      raise "fractional conversion needs an integral order ideal"
    factorization = ideal.factorization(
      factor_search_limit, valuation_step_limit)
    AlgebraFractionalIdeal.new(
      ideal.order, factorization.factors)

  -> order
    @order

  -> factors
    out = []
    @factors.each -> (factor)
      out.push([factor[0], factor[1]])
    out

  -> exponent_at(prime_ideal)
    i = 0
    while i < @factors.size
      return @factors[i][1] if @factors[i][0].eql?(
        prime_ideal)
      i += 1
    0

  -> valuation(prime_ideal)
    exponent_at(prime_ideal)

  -> norm
    value = Rational.new(1)
    @factors.each -> (factor)
      prime_norm = factor[0].norm
      exponent = factor[1]
      if exponent > 0
        value *= Rational.new(
          prime_norm ** exponent)
      else
        value /= Rational.new(
          prime_norm ** (0 - exponent))
    value

  -> unit?
    @factors.size == 0

  -> integral?
    i = 0
    while i < @factors.size
      return false if @factors[i][1] < 0
      i += 1
    true

  -> numerator_ideal
    result = AlgebraOrderIdeal.unit(@order)
    @factors.each -> (factor)
      if factor[1] > 0
        result = result.raw_product(
          factor[0].as_ideal ** factor[1])
    result

  -> denominator_ideal
    result = AlgebraOrderIdeal.unit(@order)
    @factors.each -> (factor)
      if factor[1] < 0
        result = result.raw_product(
          factor[0].as_ideal ** (0 - factor[1]))
    result

  -> to_integral_ideal
    if !integral?
      raise "fractional ideal has negative prime valuations"
    numerator_ideal

  -> *(other)
    incompatible = other.class_name != "AlgebraFractionalIdeal"
    if !incompatible
      incompatible = !@order.same_order?(other.order)
    if incompatible
      raise "cannot multiply fractional ideals from different orders"
    AlgebraFractionalIdeal.new(
      @order, factors + other.factors)

  -> inverse
    inverted = []
    @factors.each -> (factor)
      inverted.push([factor[0], 0 - factor[1]])
    AlgebraFractionalIdeal.new(@order, inverted)

  -> /(other)
    self * other.inverse

  -> **(exponent)
    if !IntegerLinearAlgebra.integer_value?(exponent)
      raise "fractional ideal exponent must be an integer"
    powered = []
    @factors.each -> (factor)
      powered.push([factor[0], factor[1] * exponent])
    AlgebraFractionalIdeal.new(@order, powered)

  -> eql?(other)
    return false if other.class_name != "AlgebraFractionalIdeal"
    return false if !@order.same_order?(other.order)
    return false if @factors.size != other.factors.size
    i = 0
    while i < @factors.size
      return false if other.exponent_at(
        @factors[i][0]) != @factors[i][1]
      i += 1
    true

  -> ==/1
    self.eql?(@1)

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> to_s
    return "FractionalIdeal(1)" if unit?
    parts = []
    @factors.each -> (factor)
      text = factor[0].to_s + "^"
      parts.push(text + factor[1].to_s)
    "FractionalIdeal(" + parts.join(" * ") + ")"

  -> inspect
    to_s


+ AlgebraPrincipalFractionalIdealCertificate
  -> new(@computation)
    @verified_cache = nil

  -> verified?
    answer = false
    begin
      answer = verify!
    rescue error
      answer = false
    answer

  -> verify!
    return true if @verified_cache == true
    expected_class = "AlgebraPrincipalFractionalIdealComputation"
    if @computation.class_name != expected_class
      raise "principal fractional-ideal certificate has the wrong computation"
    order = @computation.order
    value = @computation.value
    denominator = @computation.denominator
    if denominator < 1
      raise "principal fractional ideal has an invalid denominator"
    scaled = order.algebra.multiply(
      value, denominator)
    if !order.contains?(scaled)
      raise "principal fractional denominator does not clear coordinates"
    numerator = order.principal_ideal(scaled)
    denominator_ideal = order.principal_ideal(
      order.algebra.coerce(denominator))
    numerator_fractional = AlgebraFractionalIdeal.from_integral(
      numerator, @computation.factor_search_limit,
      @computation.valuation_step_limit)
    denominator_fractional = AlgebraFractionalIdeal.from_integral(
      denominator_ideal,
      @computation.factor_search_limit,
      @computation.valuation_step_limit)
    expected = numerator_fractional / denominator_fractional
    if !@computation.ideal.eql?(expected)
      raise "principal fractional ideal does not replay"
    @verified_cache = true
    true

  -> certified?
    verified?

  -> to_s
    "AlgebraPrincipalFractionalIdealCertificate"

  -> inspect
    to_s


+ AlgebraPrincipalFractionalIdealComputation
  -> new(@order, value,
         @factor_search_limit = 1_000_000,
         @valuation_step_limit = 10_000)
    if @order.class_name != "AlgebraOrder"
      raise "principal fractional ideal needs an AlgebraOrder"
    @value = @order.algebra.normalize_element(value)
    if @value.zero?
      raise "zero does not define an invertible fractional ideal"
    coordinates = @order.coordinates(@value)
    @denominator = 1 ## big
    coordinates.each -> (coefficient)
      divisor = @denominator.gcd(
        coefficient.denominator)
      reduced = @denominator / divisor
      @denominator = reduced * coefficient.denominator
    scaled = @order.algebra.multiply(
      @value, @denominator)
    if !@order.contains?(scaled)
      raise "failed to clear principal fractional-ideal coordinates"
    numerator = @order.principal_ideal(scaled)
    denominator_ideal = @order.principal_ideal(
      @order.algebra.coerce(@denominator))
    numerator_fractional = AlgebraFractionalIdeal.from_integral(
      numerator, @factor_search_limit,
      @valuation_step_limit)
    denominator_fractional = AlgebraFractionalIdeal.from_integral(
      denominator_ideal,
      @factor_search_limit,
      @valuation_step_limit)
    @ideal = numerator_fractional / denominator_fractional
    @certificate_cache = AlgebraPrincipalFractionalIdealCertificate.new(
      self)
    if !@certificate_cache.verified?
      raise "principal fractional ideal failed certification"

  -> order
    @order

  -> value
    @value

  -> denominator
    @denominator

  -> factor_search_limit
    @factor_search_limit

  -> valuation_step_limit
    @valuation_step_limit

  -> ideal
    @ideal

  -> result
    @ideal

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> to_s
    prefix = "AlgebraPrincipalFractionalIdealComputation("
    prefix + @ideal.to_s + ")"

  -> inspect
    to_s


+ AlgebraOrderIdeal
  -> to_fractional(
       factor_search_limit = 1_000_000,
       valuation_step_limit = 10_000)
    AlgebraFractionalIdeal.from_integral(
      self, factor_search_limit,
      valuation_step_limit)


+ AlgebraOrder
  -> fractional_ideal_maximality_certificate
    if @fractional_ideal_maximality_certificate_cache == nil
      computation = maximal_order_with_certificate
      if !computation.order.same_order?(self)
        raise "invertible fractional ideals need a maximal order"
      @fractional_ideal_maximality_certificate_cache = computation.certificate
    @fractional_ideal_maximality_certificate_cache

  -> principal_fractional_ideal_with_certificate(
       value, factor_search_limit = 1_000_000,
       valuation_step_limit = 10_000)
    AlgebraPrincipalFractionalIdealComputation.new(
      self, value, factor_search_limit,
      valuation_step_limit)

  -> principal_fractional_ideal(
       value, factor_search_limit = 1_000_000,
       valuation_step_limit = 10_000)
    principal_fractional_ideal_with_certificate(
      value, factor_search_limit,
      valuation_step_limit).ideal


+ NumberFieldFractionalIdealCertificate
  -> new(@ideal)

  -> verified?
    return false if @ideal.class_name != "NumberFieldFractionalIdeal"
    return false if !@ideal.algebra_fractional_ideal.certificate.verified?
    @ideal.algebra_fractional_ideal.order.same_order?(
      @ideal.field.certify_maximal_order)

  -> certified?
    verified?

  -> to_s
    "NumberFieldFractionalIdealCertificate"

  -> inspect
    to_s


+ NumberFieldFractionalIdeal
  -> new(@field, @algebra_fractional_ideal)
    if @field.class_name != "NumberField"
      raise "number-field fractional ideal needs a NumberField"
    expected_class = "AlgebraFractionalIdeal"
    if @algebra_fractional_ideal.class_name != expected_class
      raise "number-field fractional ideal needs algebra factor data"
    if !certificate.verified?
      raise "number-field fractional ideal failed certification"

  -> field
    @field

  -> algebra_fractional_ideal
    @algebra_fractional_ideal

  -> norm
    @algebra_fractional_ideal.norm

  -> integral?
    @algebra_fractional_ideal.integral?

  -> unit?
    @algebra_fractional_ideal.unit?

  -> valuation(prime_ideal)
    wrong_prime = prime_ideal.class_name != "NumberFieldPrimeIdeal"
    if !wrong_prime
      wrong_prime = true if prime_ideal.field != @field
    if wrong_prime
      raise "fractional-ideal valuation needs a prime of the same field"
    @algebra_fractional_ideal.valuation(
      prime_ideal.algebra_prime_ideal)

  -> *(other)
    require_same_field(other)
    NumberFieldFractionalIdeal.new(
      @field,
      @algebra_fractional_ideal * other.algebra_fractional_ideal)

  -> inverse
    NumberFieldFractionalIdeal.new(
      @field, @algebra_fractional_ideal.inverse)

  -> /(other)
    self * other.inverse

  -> **(exponent)
    NumberFieldFractionalIdeal.new(
      @field, @algebra_fractional_ideal ** exponent)

  -> require_same_field(other)
    wrong_field = other.class_name != "NumberFieldFractionalIdeal"
    if !wrong_field
      wrong_field = true if other.field != @field
    if wrong_field
      raise "number-field fractional ideals belong to different fields"
    true

  -> eql?(other)
    expected_class = "NumberFieldFractionalIdeal"
    return false if other.class_name != expected_class
    return false if other.field != @field
    @algebra_fractional_ideal.eql?(
      other.algebra_fractional_ideal)

  -> ==/1
    self.eql?(@1)

  -> certificate
    NumberFieldFractionalIdealCertificate.new(self)

  -> certified?
    certificate.verified?

  -> to_s
    "NumberField" + @algebra_fractional_ideal.to_s

  -> inspect
    to_s


+ NumberField
  -> generic_algebra_element(value)
    element = coerce(value)
    scale = monogenic_order.generator_scale
    vector = []
    power = 1 ## big
    i = 0
    while i < @degree
      coefficient = element.coefficients[i]
      vector.push(coefficient / Rational.new(power))
      power *= scale
      i += 1
    certify_maximal_order.algebra.coerce(vector)

  -> principal_fractional_ideal(
       value, factor_search_limit = 1_000_000,
       valuation_step_limit = 10_000)
    algebra_value = generic_algebra_element(value)
    NumberFieldFractionalIdeal.new(
      self,
      certify_maximal_order.principal_fractional_ideal(
        algebra_value, factor_search_limit,
        valuation_step_limit))

  -> fractional_unit_ideal
    NumberFieldFractionalIdeal.new(
      self, AlgebraFractionalIdeal.unit(
        certify_maximal_order))


+ NumberFieldIdeal
  -> to_fractional(
       factor_search_limit = 1_000_000,
       valuation_step_limit = 10_000)
    NumberFieldFractionalIdeal.new(
      @field, @algebra_ideal.to_fractional(
        factor_search_limit,
        valuation_step_limit))
