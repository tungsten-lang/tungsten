# Degree-generic exact orders in finite etale Q-algebras.
#
# The p-maximal algorithm is Pohst-Zassenhaus Round 2. For an order O and a
# prime p, let I be the radical of pO. The multiplier ring
#
#   (I:I) = {x in A : xI is contained in I}
#
# is either O, which certifies p-maximality, or a strict p-power overorder.
# The implementation computes I/pO as the kernel of a sufficiently high
# Frobenius power on O/pO, then computes (I:I) as a canonical F_p kernel.
# Every strict lattice extension, ring-closure assertion, discriminant
# quotient, and final fixed point is replayed by a certificate.

+ AlgebraOrderCertificate
  -> new(@order)
    @verified_cache = nil

  -> order
    @order

  -> verified?
    answer = false
    begin
      answer = verify!
    rescue error
      answer = false
    answer

  -> verify!
    return true if @verified_cache == true
    if @order.class_name != "AlgebraOrder"
      raise "order certificate needs an AlgebraOrder"
    if !@order.algebra.certificate.verified?
      raise "ambient etale algebra is not certified"
    if !@order.contains?(@order.algebra.one)
      raise "order lattice does not contain one"
    if !@order.closed?
      raise "order lattice is not multiplicatively closed"
    discriminant = @order.compute_discriminant
    if discriminant.denominator != 1 || discriminant.numerator == 0
      raise "order trace discriminant is not a nonzero integer"
    if discriminant.numerator != @order.discriminant
      raise "cached order discriminant does not replay"
    @verified_cache = true
    true

  -> certified?
    verified?

  -> to_s
    "AlgebraOrderCertificate(rank " + @order.rank.to_s + ")"

  -> inspect
    to_s


+ EtaleProductMaximalOrderCertificate
  -> new(@source, @result, computations)
    @computations = []
    computations.each -> (computation)
      @computations.push(computation)
    @verified_cache = nil

  -> source
    @source

  -> result
    @result

  -> computations
    out = []
    @computations.each -> (computation)
      out.push(computation)
    out

  -> verified?
    answer = false
    begin
      answer = verify!
    rescue error
      answer = false
    answer

  -> verify!
    return true if @verified_cache == true
    if @source.class_name != "EtaleProductOrder"
      raise "product maximal-order certificate needs a product order"
    if @result.class_name != "EtaleProductOrder"
      raise "product maximal-order result has the wrong type"
    invalid_order = !@source.certificate.verified?
    invalid_order = true if !@result.certificate.verified?
    if invalid_order
      raise "product maximal-order certificate has an invalid order"
    source_orders = @source.component_algebra_orders
    result_orders = @result.component_algebra_orders
    wrong_size = source_orders.size != @computations.size
    wrong_size = true if result_orders.size != @computations.size
    if wrong_size
      raise "product maximal-order component count changed"
    i = 0
    while i < @computations.size
      computation = @computations[i]
      if computation.class_name != "MaximalOrderComputation"
        raise "invalid component maximal-order computation"
      if !computation.source.same_order?(source_orders[i])
        raise "component computation has the wrong source"
      if !computation.order.same_order?(result_orders[i])
        raise "component computation has the wrong result"
      if !computation.certificate.verified?
        raise "component maximal-order certificate failed"
      i += 1
    @verified_cache = true
    true

  -> index
    result_orders = @result.component_algebra_orders
    source_orders = @source.component_algebra_orders
    value = 1 ## big
    i = 0
    while i < result_orders.size
      value *= result_orders[i].index_from(source_orders[i])
      i += 1
    value

  -> maximal?
    verified?

  -> certified?
    verified?

  -> to_s
    text = "EtaleProductMaximalOrderCertificate(index "
    text + index.to_s + ")"

  -> inspect
    to_s


+ EtaleProductMaximalOrderComputation
  -> new(@source, @factor_search_limit = 1_000_000,
         @step_limit = 10_000)
    if @source.class_name != "EtaleProductOrder"
      raise "product maximal-order computation needs an EtaleProductOrder"
    @component_computations = []
    result_orders = []
    @source.component_orders.each -> (component)
      computation = component.maximal_order_with_certificate(
        @factor_search_limit, @step_limit)
      @component_computations.push(computation)
      result_orders.push(computation.order)
    @order = EtaleProductOrder.new(result_orders)
    @certificate = EtaleProductMaximalOrderCertificate.new(
      @source, @order, @component_computations)
    if !@certificate.verified?
      raise "product maximal order failed certification"

  -> source
    @source

  -> order
    @order

  -> result
    @order

  -> index
    @certificate.index

  -> component_computations
    out = []
    @component_computations.each -> (computation)
      out.push(computation)
    out

  -> certificate
    @certificate

  -> certified?
    @certificate.verified?

  -> to_s
    text = "EtaleProductMaximalOrderComputation(index "
    text + index.to_s + ")"

  -> inspect
    to_s


+ AlgebraOrderIdealCertificate
  -> new(@ideal)
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
    if @ideal.class_name != "AlgebraOrderIdeal"
      raise "order-ideal certificate needs an AlgebraOrderIdeal"
    order = @ideal.order
    if !order.certificate.verified?
      raise "order ideal has an uncertified parent order"
    if !@ideal.ideal?
      raise "lattice is not an order ideal"
    if @ideal.kind == :p_radical
      prime = @ideal.prime
      expected = AlgebraOrderLattice.new(
        order.algebra, order.p_radical_basis(prime))
      if !@ideal.lattice.same_lattice?(expected)
        raise "p-radical lattice does not replay"
    @verified_cache = true
    true

  -> certified?
    verified?

  -> to_s
    "AlgebraOrderIdealCertificate(" + @ideal.kind.to_s + ")"

  -> inspect
    to_s


+ AlgebraOrderIdeal
  -> new(@order, basis_vectors, @kind = :ideal, @prime = nil)
    if @order.class_name != "AlgebraOrder"
      raise "order ideal needs an AlgebraOrder"
    @lattice = AlgebraOrderLattice.new(
      @order.algebra, basis_vectors)
    @certificate_cache = AlgebraOrderIdealCertificate.new(self)
    if !@certificate_cache.verified?
      raise "order ideal failed certification"

  -> order
    @order

  -> algebra
    @order.algebra

  -> lattice
    @lattice

  -> kind
    @kind

  -> prime
    @prime

  -> basis_vectors
    @lattice.basis_vectors

  -> basis
    out = []
    basis_vectors.each -> (vector)
      out.push(@order.algebra.coerce(vector))
    out

  -> contains?(value)
    element = algebra.normalize_element(value)
    @lattice.contains_vector?(element.coefficients)

  -> ideal?
    order_basis = @order.basis
    ideal_basis = basis
    i = 0
    while i < order_basis.size
      j = 0
      while j < ideal_basis.size
        product = algebra.multiply(
          order_basis[i], ideal_basis[j])
        return false if !contains?(product)
        j += 1
      i += 1
    true

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> to_s
    text = "OrderIdeal(" + @kind.to_s + ", rank "
    text + @order.rank.to_s + ")"

  -> inspect
    to_s


+ AlgebraOrder
  -> new(@algebra, basis_vectors)
    if @algebra.class_name != "EtaleAlgebra"
      raise "AlgebraOrder needs an EtaleAlgebra"
    @lattice = AlgebraOrderLattice.new(
      @algebra, basis_vectors)
    @multiplication_matrices_cache = nil
    @one_coordinates_cache = nil
    @discriminant_cache = nil
    @certificate_cache = AlgebraOrderCertificate.new(self)
    if !@certificate_cache.verified?
      raise "algebra order failed certification"

  -> .power_order(monogenic_order)
    if monogenic_order.class_name != "MonogenicOrder"
      raise "power_order needs a MonogenicOrder"
    rank = monogenic_order.rank
    basis = []
    i = 0
    while i < rank
      vector = []
      j = 0
      while j < rank
        vector.push(Rational.new(i == j ? 1 : 0))
        j += 1
      basis.push(vector)
      i += 1
    AlgebraOrder.new(monogenic_order.algebra, basis)

  -> algebra
    @algebra

  -> lattice
    @lattice

  -> rank
    @lattice.rank

  -> degree
    rank

  -> basis_vectors
    @lattice.basis_vectors

  -> basis
    out = []
    basis_vectors.each -> (vector)
      out.push(@algebra.coerce(vector))
    out

  -> coordinates(value)
    element = @algebra.normalize_element(value)
    @lattice.coordinates(element.coefficients)

  -> contains?(value)
    return false if value.class_name != "EtaleAlgebraElement"
    return false if value.algebra != @algebra
    @lattice.contains_vector?(value.coefficients)

  -> coerce(value)
    element = @algebra.coerce(value)
    if !contains?(element)
      raise "element is not in this algebra order"
    element

  -> element(coordinates)
    coerce(@algebra.coerce(
      @lattice.ambient_vector(coordinates)))

  -> zero
    @algebra.zero

  -> one
    @algebra.one

  -> unit?(value)
    return false if !contains?(value)
    element = @algebra.normalize_element(value)
    return false if !element.unit?
    contains?(element.inverse)

  -> inverse(value)
    element = coerce(value)
    if !unit?(element)
      raise "element is not a unit of this algebra order"
    element.inverse

  -> trace(value)
    @algebra.trace(coerce(value))

  -> norm(value)
    @algebra.norm(coerce(value))

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> same_order?(other)
    return false if other.class_name != "AlgebraOrder"
    return false if other.algebra != @algebra
    @lattice.same_lattice?(other.lattice)

  -> contains_order?(other)
    return false if other.class_name != "AlgebraOrder"
    return false if other.algebra != @algebra
    @lattice.contains_lattice?(other.lattice)

  # Return [self : suborder].
  -> index_from(suborder)
    if suborder.class_name != "AlgebraOrder"
      raise "order index needs an AlgebraOrder"
    @lattice.index_from(suborder.lattice)

  -> multiplication_matrices
    if @multiplication_matrices_cache != nil
      return @multiplication_matrices_cache
    order_basis = basis
    matrices = []
    right = 0
    while right < rank
      rows = []
      row_index = 0
      while row_index < rank
        row = []
        column_index = 0
        while column_index < rank
          row.push(0)
          column_index += 1
        rows.push(row)
        row_index += 1
      left = 0
      while left < rank
        product = @algebra.multiply(
          order_basis[left], order_basis[right])
        product_coordinates = coordinates(product)
        row = 0
        while row < rank
          coefficient = product_coordinates[row]
          if coefficient.denominator != 1
            raise "order basis is not multiplicatively closed"
          rows[row][left] = coefficient.numerator
          row += 1
        left += 1
      matrices.push(rows)
      right += 1
    @multiplication_matrices_cache = matrices
    matrices

  -> release_linear_cache
    @multiplication_matrices_cache = nil
    @one_coordinates_cache = nil
    self

  -> closed?
    answer = false
    begin
      multiplication_matrices
      answer = true
    rescue error
      answer = false
    answer

  -> one_coordinates
    if @one_coordinates_cache == nil
      values = coordinates(@algebra.one)
      out = []
      values.each -> (value)
        if value.denominator != 1
          raise "order lattice does not contain one"
        out.push(value.numerator)
      @one_coordinates_cache = out
    out = []
    @one_coordinates_cache.each -> (value)
      out.push(value)
    out

  -> multiply_coordinates_mod(left, right, prime)
    if left.size != rank || right.size != rank
      raise "order-coordinate product has the wrong dimension"
    matrices = multiplication_matrices
    out = []
    i = 0
    while i < rank
      out.push(0)
      i += 1
    right_index = 0
    while right_index < rank
      right_coefficient = PrimeLinearAlgebra.normalize(
        right[right_index], prime)
      if right_coefficient != 0
        left_index = 0
        while left_index < rank
          left_coefficient = PrimeLinearAlgebra.normalize(
            left[left_index], prime)
          if left_coefficient != 0
            row = 0
            while row < rank
              contribution = right_coefficient * left_coefficient
              contribution *= matrices[right_index][row][left_index]
              out[row] = PrimeLinearAlgebra.normalize(
                out[row] + contribution, prime)
              row += 1
          left_index += 1
      right_index += 1
    out

  -> power_coordinates_mod(value, exponent, prime)
    result = one_coordinates
    factor = []
    value.each -> (coefficient)
      factor.push(PrimeLinearAlgebra.normalize(
        coefficient, prime))
    remaining = exponent
    while remaining > 0
      if remaining.odd?
        result = multiply_coordinates_mod(
          result, factor, prime)
      remaining = remaining / 2
      if remaining > 0
        factor = multiply_coordinates_mod(
          factor, factor, prime)
    result

  # I_p/pO is the nilradical of O/pO. In a rank-n commutative F_p-algebra,
  # the kernel of x |-> x^(p^r) is the nilradical once p^r >= n.
  -> p_radical_kernel_data(prime)
    if prime < 2 || !prime.prime?
      raise "p-radical needs a prime integer"
    rounds = 0
    exponent_bound = 1
    while exponent_bound < rank
      exponent_bound *= prime
      rounds += 1

    columns = []
    column = 0
    while column < rank
      value = []
      i = 0
      while i < rank
        value.push(0)
        i += 1
      value[column] = 1
      round = 0
      while round < rounds
        value = power_coordinates_mod(
          value, prime, prime)
        round += 1
      columns.push(value)
      column += 1

    rows = []
    row = 0
    while row < rank
      values = []
      column = 0
      while column < rank
        values.push(columns[column][row])
        column += 1
      rows.push(values)
      row += 1
    PrimeLinearAlgebra.kernel_data(rows, prime, rank)

  -> p_radical_basis(prime)
    kernel = p_radical_kernel_data(prime)
    relative = []
    kernel[0].each -> (vector)
      lifted = []
      vector.each -> (coefficient)
        lifted.push(Rational.new(coefficient))
      relative.push(lifted)
    kernel[1].each -> (pivot)
      vector = []
      i = 0
      while i < rank
        vector.push(Rational.new(i == pivot ? prime : 0))
        i += 1
      relative.push(vector)
    ExactRationalLinearAlgebra.compose_columns(
      basis_vectors, relative)

  -> p_radical(prime)
    AlgebraOrderIdeal.new(
      self, p_radical_basis(prime), :p_radical, prime)

  # Lemma 4.3.6 in the Round 2 construction:
  # (I:I) = (1/p) Ker(O -> End(I/pI)).
  -> round_two_overorder_basis(prime)
    ideal = p_radical(prime)
    ideal_basis = ideal.basis
    equations = []
    ideal_index = 0
    while ideal_index < rank
      coordinate_columns = []
      order_index = 0
      while order_index < rank
        product = @algebra.multiply(
          basis[order_index], ideal_basis[ideal_index])
        coordinates_in_ideal = ideal.lattice.coordinates(
          product.coefficients)
        column = []
        coordinates_in_ideal.each -> (coefficient)
          if coefficient.denominator != 1
            raise "p-radical is not stable under its parent order"
          column.push(coefficient.numerator)
        coordinate_columns.push(column)
        order_index += 1
      coordinate = 0
      while coordinate < rank
        equation = []
        order_index = 0
        while order_index < rank
          equation.push(
            coordinate_columns[order_index][coordinate])
          order_index += 1
        equations.push(equation)
        coordinate += 1
      ideal_index += 1

    kernel = PrimeLinearAlgebra.kernel_data(
      equations, prime, rank)
    relative = []
    kernel[0].each -> (vector)
      lifted = []
      vector.each -> (coefficient)
        lifted.push(Rational.new(coefficient, prime))
      relative.push(lifted)
    kernel[1].each -> (pivot)
      vector = []
      i = 0
      while i < rank
        vector.push(Rational.new(i == pivot ? 1 : 0))
        i += 1
      relative.push(vector)
    ExactRationalLinearAlgebra.compose_columns(
      basis_vectors, relative)

  -> round_two_overorder(prime)
    candidate = AlgebraOrder.new(
      @algebra, round_two_overorder_basis(prime))
    return self if candidate.same_order?(self)
    if !candidate.contains_order?(self)
      raise "Round 2 multiplier ring does not contain its source order"
    candidate

  -> compute_discriminant
    order_basis = basis
    matrix = []
    i = 0
    while i < rank
      row = []
      j = 0
      while j < rank
        product = @algebra.multiply(
          order_basis[i], order_basis[j])
        row.push(@algebra.trace(product))
        j += 1
      matrix.push(row)
      i += 1
    Algebra.determinant(matrix, RationalField.new)

  -> discriminant
    if @discriminant_cache == nil
      value = compute_discriminant
      if value.denominator != 1 || value.numerator == 0
        raise "order discriminant is not a nonzero integer"
      @discriminant_cache = value.numerator
    @discriminant_cache

  -> factor_discriminant(search_limit = 1_000_000)
    value = discriminant.abs
    return [] if value == 1
    factors = []
    remaining = value
    candidate = 2
    attempts = 0
    while candidate * candidate <= remaining
      attempts += 1
      if attempts > search_limit
        raise "discriminant factor search limit exceeded; maximal order unknown"
      exponent = 0
      while remaining % candidate == 0
        remaining = remaining / candidate
        exponent += 1
      factors.push([candidate, exponent]) if exponent > 0
      candidate = candidate == 2 ? 3 : candidate + 2
    factors.push([remaining, 1]) if remaining > 1
    factors

  -> p_maximal_order_with_certificate(
       prime, step_limit = 10_000,
       verify_certificate = true)
    PMaximalOrderComputation.new(
      self, prime, step_limit, verify_certificate)

  -> p_maximal_order(prime, step_limit = 10_000)
    p_maximal_order_with_certificate(
      prime, step_limit).order

  -> maximal_order_with_certificate(
       factor_search_limit = 1_000_000,
       step_limit = 10_000)
    MaximalOrderComputation.new(
      self, factor_search_limit, step_limit)

  -> maximal_order(
       factor_search_limit = 1_000_000,
       step_limit = 10_000)
    maximal_order_with_certificate(
      factor_search_limit, step_limit).order

  -> maximal?(
       factor_search_limit = 1_000_000,
       step_limit = 10_000)
    maximal_order(
      factor_search_limit, step_limit).same_order?(self)

  -> to_s
    text = "AlgebraOrder(rank " + rank.to_s
    text + ", disc " + discriminant.to_s + ")"

  -> inspect
    to_s


+ PMaximalOrderStepCertificate
  -> new(@source, @prime, @radical, @result)
    @verified_cache = nil

  -> source
    @source

  -> prime
    @prime

  -> radical
    @radical

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
    invalid_orders = @source.class_name != "AlgebraOrder"
    invalid_orders = true if @result.class_name != "AlgebraOrder"
    if invalid_orders
      raise "Round 2 step needs algebra orders"
    if @source.algebra != @result.algebra
      raise "Round 2 step changes ambient algebra"
    if @radical.class_name != "AlgebraOrderIdeal"
      raise "Round 2 step needs its p-radical"
    if @radical.order != @source || @radical.prime != @prime
      raise "Round 2 p-radical is bound to the wrong source"
    if !@radical.certificate.verified?
      raise "Round 2 p-radical did not certify"
    expected = AlgebraOrderLattice.new(
      @source.algebra,
      @source.round_two_overorder_basis(@prime))
    if !@result.lattice.same_lattice?(expected)
      raise "Round 2 multiplier-ring lattice does not replay"
    if !@result.contains_order?(@source)
      raise "Round 2 result does not contain its source"
    index = @result.index_from(@source)
    if index <= 1
      raise "Round 2 strict step has nonpositive index"
    remaining = index
    while remaining % @prime == 0
      remaining = remaining / @prime
    if remaining != 1
      raise "Round 2 index is not a p-power"
    expected_discriminant = @result.discriminant * index * index
    if @source.discriminant != expected_discriminant
      raise "Round 2 discriminant quotient is inconsistent"
    @verified_cache = true
    true

  -> certified?
    verified?

  -> to_s
    text = "PMaximalOrderStepCertificate(p=" + @prime.to_s
    text + ", index=" + @result.index_from(@source).to_s + ")"

  -> inspect
    to_s


+ PMaximalOrderCertificate
  -> new(@source, @prime, @result)
    @verified_cache = nil

  -> source
    @source

  -> prime
    @prime

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
    if @prime < 2 || !@prime.prime?
      raise "p-maximal certificate needs a prime"
    invalid_order = !@source.certificate.verified?
    invalid_order = true if !@result.certificate.verified?
    if invalid_order
      raise "p-maximal certificate has an invalid order"
    if !@result.contains_order?(@source)
      raise "p-maximal result does not contain its source"
    index = @result.index_from(@source)
    remaining = index
    while remaining % @prime == 0
      remaining = remaining / @prime
    if remaining != 1
      raise "p-maximal overorder index is not a p-power"
    expected_discriminant = @result.discriminant * index * index
    if @source.discriminant != expected_discriminant
      raise "p-maximal discriminant quotient is inconsistent"
    fixed = AlgebraOrderLattice.new(
      @result.algebra,
      @result.round_two_overorder_basis(@prime))
    if !@result.lattice.same_lattice?(fixed)
      raise "final order is not a Round 2 fixed point"
    @verified_cache = true
    true

  -> p_maximal?
    verified?

  -> certified?
    verified?

  -> to_s
    "PMaximalOrderCertificate(p=" + @prime.to_s + ")"

  -> inspect
    to_s


+ PMaximalOrderComputation
  -> new(@source, @prime, @step_limit = 10_000,
         verify_certificate = true)
    if @source.class_name != "AlgebraOrder"
      raise "p-maximal computation needs an AlgebraOrder"
    if @prime < 2 || !@prime.prime?
      raise "p-maximal computation needs a prime"
    @step_indices = []
    @step_discriminants = []
    current = @source
    iterations = 0
    while true
      candidate_basis = current.round_two_overorder_basis(@prime)
      candidate_lattice = AlgebraOrderLattice.new(
        current.algebra, candidate_basis)
      break if current.lattice.same_lattice?(candidate_lattice)
      iterations += 1
      if iterations > @step_limit
        raise "Round 2 step limit exceeded; p-maximal order unknown"
      candidate = AlgebraOrder.new(
        current.algebra, candidate_basis)
      if !candidate.contains_order?(current)
        raise "Round 2 result does not contain its source"
      index = candidate.index_from(current)
      remaining = index
      while remaining % @prime == 0
        remaining = remaining / @prime
      if index <= 1 || remaining != 1
        raise "Round 2 step index is not a positive p-power"
      expected = candidate.discriminant * index * index
      if current.discriminant != expected
        raise "Round 2 step discriminant quotient is inconsistent"
      @step_indices.push(index)
      @step_discriminants.push(candidate.discriminant)
      previous = current
      current = candidate
      previous.release_linear_cache
    @order = current
    @certificate = PMaximalOrderCertificate.new(
      @source, @prime, @order)
    if verify_certificate && !@certificate.verified?
      raise "p-maximal order failed certification"

  -> source
    @source

  -> prime
    @prime

  -> order
    @order

  -> result
    @order

  -> steps
    out = []
    i = 0
    while i < @step_indices.size
      out.push([
        @step_indices[i],
        @step_discriminants[i]
      ])
      i += 1
    out

  -> step_count
    @step_indices.size

  -> certificate
    @certificate

  -> certified?
    @certificate.verified?

  -> to_s
    text = "PMaximalOrderComputation(p=" + @prime.to_s
    text + ", steps=" + @step_indices.size.to_s + ")"

  -> inspect
    to_s


+ MaximalOrderCertificate
  -> new(@source, @initial_order, @result,
         factors, local_computations)
    @factors = []
    factors.each -> (factor)
      @factors.push([factor[0], factor[1]])
    @local_computations = []
    local_computations.each -> (computation)
      @local_computations.push(computation)
    @verified_cache = nil

  -> source
    @source

  -> result
    @result

  -> initial_order
    @initial_order

  -> factors
    out = []
    @factors.each -> (factor)
      out.push([factor[0], factor[1]])
    out

  -> local_computations
    out = []
    @local_computations.each -> (computation)
      out.push(computation)
    out

  -> verified?
    answer = false
    begin
      answer = verify!
    rescue error
      answer = false
    answer

  -> verify!
    return true if @verified_cache == true
    invalid_order = !@source.certificate.verified?
    invalid_order = true if !@initial_order.certificate.verified?
    invalid_order = true if !@result.certificate.verified?
    if invalid_order
      raise "maximal-order certificate has an invalid order"
    product = 1 ## big
    relevant_primes = []
    @factors.each -> (factor)
      prime = factor[0]
      exponent = factor[1]
      if prime < 2 || !prime.prime? || exponent < 1
        raise "invalid discriminant factorization"
      product *= prime ** exponent
      relevant_primes.push(prime) if exponent >= 2
    if product != @source.discriminant.abs
      raise "maximal-order discriminant factors do not reconstruct"
    if relevant_primes.size != @local_computations.size
      raise "maximal-order certificate omits a local prime"

    if !@initial_order.contains_order?(@source)
      raise "maximal-order seed does not contain its source"
    seed_index = @initial_order.index_from(@source)
    seed_expected = @initial_order.discriminant * seed_index * seed_index
    if @source.discriminant != seed_expected
      raise "maximal-order seed has an invalid discriminant quotient"

    current = @initial_order
    i = 0
    while i < relevant_primes.size
      computation = @local_computations[i]
      if computation.class_name != "PMaximalOrderComputation"
        raise "maximal-order local computation has the wrong type"
      if computation.prime != relevant_primes[i]
        raise "maximal-order local primes are out of order"
      if !computation.source.same_order?(current)
        raise "maximal-order local chain is discontinuous"
      if !computation.order.certificate.verified?
        raise "maximal-order local result is not an order"
      if !computation.order.contains_order?(current)
        raise "maximal-order local result is not an overorder"
      local_index = computation.order.index_from(current)
      remaining = local_index
      while remaining % computation.prime == 0
        remaining = remaining / computation.prime
      if remaining != 1
        raise "maximal-order local index is not a p-power"
      local_expected = computation.order.discriminant * local_index * local_index
      if current.discriminant != local_expected
        raise "maximal-order local discriminant quotient is inconsistent"
      current = computation.order
      i += 1
    if !current.same_order?(@result)
      raise "maximal-order local chain ends at the wrong order"

    # Later q-power extensions preserve p-maximality for p != q, but replay
    # every final fixed point directly so the certificate need not rely on
    # that optimization.
    relevant_primes.each -> (prime)
      fixed = AlgebraOrderLattice.new(
        @result.algebra,
        @result.round_two_overorder_basis(prime))
      if !@result.lattice.same_lattice?(fixed)
        raise "result is not p-maximal at a discriminant prime"

    if !@result.contains_order?(@source)
      raise "maximal order does not contain its source"
    index = @result.index_from(@source)
    expected_discriminant = @result.discriminant * index * index
    if @source.discriminant != expected_discriminant
      raise "maximal-order discriminant quotient is inconsistent"
    @verified_cache = true
    true

  -> maximal?
    verified?

  -> certified?
    verified?

  -> to_s
    text = "MaximalOrderCertificate(index "
    text + @result.index_from(@source).to_s + ")"

  -> inspect
    to_s


+ MaximalOrderComputation
  -> new(@source, @factor_search_limit = 1_000_000,
         @step_limit = 10_000, initial_order = nil)
    if @source.class_name != "AlgebraOrder"
      raise "maximal-order computation needs an AlgebraOrder"
    @factors = @source.factor_discriminant(
      @factor_search_limit)
    @local_computations = []
    @order = initial_order == nil ? @source : initial_order
    if @order.class_name != "AlgebraOrder"
      raise "maximal-order seed needs an AlgebraOrder"
    if @order.algebra != @source.algebra
      raise "maximal-order seed changes ambient algebra"
    if !@order.contains_order?(@source)
      raise "maximal-order seed does not contain its source"
    seed_index = @order.index_from(@source)
    seed_expected = @order.discriminant * seed_index * seed_index
    if @source.discriminant != seed_expected
      raise "maximal-order seed has an invalid discriminant quotient"
    @factors.each -> (factor)
      if factor[1] >= 2
        computation = @order.p_maximal_order_with_certificate(
          factor[0], @step_limit, false)
        @local_computations.push(computation)
        @order = computation.order
    @certificate = MaximalOrderCertificate.new(
      @source, initial_order == nil ? @source : initial_order,
      @order, @factors, @local_computations)
    if !@certificate.verified?
      raise "maximal order failed certification"

  -> source
    @source

  -> order
    @order

  -> result
    @order

  -> index
    @order.index_from(@source)

  -> factors
    out = []
    @factors.each -> (factor)
      out.push([factor[0], factor[1]])
    out

  -> local_computations
    out = []
    @local_computations.each -> (computation)
      out.push(computation)
    out

  -> certificate
    @certificate

  -> certified?
    @certificate.verified?

  -> to_s
    "MaximalOrderComputation(index " + index.to_s + ")"

  -> inspect
    to_s
