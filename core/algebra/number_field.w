# Exact cubic number fields.
#
# A NumberField is Q[a]/(f), where f is a certified irreducible cubic. Field
# elements use the power basis 1, a, a^2 with Rational coefficients. The
# maximal-order calculation is deliberately cubic-specific. If O is the
# integral power order and M contains O with index m, then m^2 divides disc(O).
# A minimal proper overorder M/O has elementary p-group quotient: O+pM is an
# intermediate order, so minimality forces pM into O. Since 1 is primitive in
# both rank-three orders, dim_Fp(M/O) is at most two. It is therefore enough to
# enumerate the index-p and index-p^2 over-lattices for every p whose square
# divides the current order discriminant. Exact multiplicative-closure tests
# select the overorders, and the process restarts after every extension.
# Minkowski's discriminant bound removes candidates whose putative field
# discriminant is impossible. Reaching an order with no such extension is a
# maximality certificate. Search bounds fail with an explicit "unknown"
# error; neither a squarefree-part heuristic nor a resource-limit fallback is
# ever presented as a field discriminant.

+ NumberFieldElement
  -> new(@field, coefficients)
    @coefficients = @field.reduce_coefficients(coefficients)

  -> field
    @field

  -> coefficients
    out = []
    @coefficients.each -> out.push(item)
    out

  -> zero?
    @field.zero?(self)

  -> one?
    @field.one?(self)

  -> +(other)
    @field.add(self, other)

  -> -(other)
    @field.subtract(self, other)

  -> negate
    @field.negate(self)

  -> -@
    negate

  -> *(other)
    @field.multiply(self, other)

  -> /(other)
    @field.divide(self, other)

  -> inverse
    @field.inverse(self)

  -> **(exponent)
    @field.power(self, exponent)

  -> ==/1
    self.eql?(@1)

  -> eql?(other)
    other_class = other.class_name
    if other_class == "NumberFieldElement"
      return false if other.field != @field
      right = other
    elsif other_class == "Integer" || other_class == "Int" || other_class == "BigInt" || other_class == "Rational"
      right = @field.coerce(other)
    else
      return false
    i = 0
    while i < 3
      return false if @coefficients[i] != right.coefficients[i]
      i += 1
    true

  -> to_s
    @field.element_to_s(self)

  -> inspect
    to_s


+ NumberField < Field
  -> new(polynomial, name = :a)
    initialize_number_field(polynomial, name, 1_000_000, 250_000)

  -> initialize_number_field(polynomial, name, irreducibility_limit, order_limit)
    if polynomial.class_name != "Polynomial"
      raise "NumberField defining polynomial must be a Polynomial"
    if polynomial.ring.arity != 1 || polynomial.degree != 3
      raise "NumberField currently needs a univariate cubic"
    if polynomial.ring.field.class_name != "RationalField"
      raise "NumberField is currently implemented only over ℚ"

    NumberField.certify_irreducible_cubic(polynomial, irreducibility_limit)
    @name = name
    @defining_polynomial = polynomial.monic
    @power_basis_discriminant = @defining_polynomial.discriminant
    @order_search_limit = order_limit

    defining_coefficients = @defining_polynomial.coefficients
    @relation = [
      defining_coefficients[0],
      defining_coefficients[1],
      defining_coefficients[2]]

    primitive = NumberField.primitive_integer_coefficients(polynomial)
    leading = primitive[3]
    @integral_generator_scale = leading
    x = polynomial.ring.generator(0)
    @integral_defining_polynomial = x**3 + x**2 * primitive[2] + x * (leading * primitive[1]) + leading * leading * primitive[0]
    integral_discriminant = @integral_defining_polynomial.discriminant
    if integral_discriminant.denominator != 1
      raise "integral cubic transformation produced a nonintegral discriminant"
    @integral_power_basis_discriminant = integral_discriminant.numerator

    maximized = maximize_integral_order
    @integral_basis_vectors = maximized[0]
    @field_discriminant = maximized[1]
    quotient = @integral_power_basis_discriminant / @field_discriminant
    @maximal_order_index = quotient.isqrt
    if @maximal_order_index * @maximal_order_index != quotient
      raise "maximal-order index invariant failed"

    @generator = NumberFieldElement.new(self, [0, 1, 0])
    @integral_basis = []
    @integral_basis_vectors.each -> (vector)
      @integral_basis.push(coerce([
        vector[0],
        vector[1] * @integral_generator_scale,
        vector[2] * @integral_generator_scale * @integral_generator_scale]))
    self

  ro :name, :defining_polynomial, :integral_defining_polynomial
  ro :power_basis_discriminant, :integral_power_basis_discriminant
  ro :field_discriminant, :maximal_order_index, :generator
  ro :integral_generator_scale

  -> integral_basis
    out = []
    @integral_basis.each -> out.push(item)
    out

  -> degree
    3

  -> characteristic
    0

  -> coefficient_field?
    true

  -> exact?
    true

  -> irreducible?
    true

  -> irreducibility_certified?
    true

  -> field_discriminant_certified?
    true

  # Number-field discriminant means the discriminant of the maximal order.
  # power_basis_discriminant remains available when the defining generator's
  # order is what the caller wants to inspect.
  -> discriminant
    @field_discriminant

  -> normalize_scalar(value)
    Rational.coerce(value)

  -> reduce_coefficients(coefficients)
    raise "number-field coefficients must be an Array" if coefficients.class_name != "Array"
    values = []
    coefficients.each -> values.push(normalize_scalar(item))
    while values.size < 3
      values.push(Rational.new(0))
    i = values.size - 1
    while i >= 3
      leading = values[i]
      if !leading.zero?
        shift = i - 3
        j = 0
        while j < 3
          values[shift + j] = values[shift + j] - leading * @relation[j]
          j += 1
      values[i] = Rational.new(0)
      i -= 1
    [values[0], values[1], values[2]]

  -> coerce(value)
    if value.class_name == "NumberFieldElement"
      if value.field != self
        raise "number-field elements belong to different fields"
      return value
    return NumberFieldElement.new(self, value) if value.class_name == "Array"
    value_class = value.class_name
    if value_class != "Integer" && value_class != "Int" && value_class != "BigInt" && value_class != "Rational"
      raise "cannot coerce " + value_class + " into " + to_s
    NumberFieldElement.new(self, [normalize_scalar(value), 0, 0])

  -> normalize_element(value)
    coerce(value)

  -> zero
    NumberFieldElement.new(self, [0, 0, 0])

  -> one
    NumberFieldElement.new(self, [1, 0, 0])

  -> zero?(value)
    coefficients = coerce(value).coefficients
    coefficients[0].zero? && coefficients[1].zero? && coefficients[2].zero?

  -> one?(value)
    coefficients = coerce(value).coefficients
    coefficients[0].one? && coefficients[1].zero? && coefficients[2].zero?

  -> equal?(left, right)
    coerce(left).eql?(coerce(right))

  -> add(left, right)
    a = coerce(left).coefficients
    b = coerce(right).coefficients
    NumberFieldElement.new(self, [
      a[0] + b[0], a[1] + b[1], a[2] + b[2]])

  -> negate(value)
    coefficients = coerce(value).coefficients
    NumberFieldElement.new(self, [
      0 - coefficients[0],
      0 - coefficients[1],
      0 - coefficients[2]])

  -> subtract(left, right)
    add(left, negate(right))

  -> multiply(left, right)
    a = coerce(left).coefficients
    b = coerce(right).coefficients
    product = [
      a[0] * b[0],
      a[0] * b[1] + a[1] * b[0],
      a[0] * b[2] + a[1] * b[1] + a[2] * b[0],
      a[1] * b[2] + a[2] * b[1],
      a[2] * b[2]]
    NumberFieldElement.new(self, product)

  -> inverse(value)
    element = coerce(value)
    raise "division by zero in number field" if zero?(element)
    a = element.coefficients
    columns = []
    columns.push(a)
    columns.push(reduce_coefficients([0, a[0], a[1], a[2]]))
    columns.push(reduce_coefficients([0, 0, a[0], a[1], a[2]]))
    solution = solve_rational_coordinates([1, 0, 0], columns)
    NumberFieldElement.new(self, solution)

  -> divide(left, right)
    multiply(left, inverse(right))

  -> power(value, exponent)
    exponent_class = exponent.class_name
    if exponent_class != "Integer" && exponent_class != "Int" && exponent_class != "BigInt"
      raise "number-field exponent must be an integer"
    return power(inverse(value), 0 - exponent) if exponent < 0
    result = one
    factor = coerce(value)
    remaining = exponent
    while remaining > 0
      result = multiply(result, factor) if remaining.odd?
      remaining = remaining / 2
      factor = multiply(factor, factor) if remaining > 0
    result

  -> negative?(value)
    raise "a number field has no canonical ordering"

  -> element_to_s(value)
    coefficients = coerce(value).coefficients
    rational_field = RationalField.new
    parts = []
    coefficients.each -> parts.push(rational_field.element_to_s(item))
    "(" + parts.join(", ") + ")_" + @name.to_s

  -> normalize_projective_coordinates(coordinates)
    raise "projective coordinates need at least one entry" if coordinates.size == 0
    values = []
    pivot = nil
    coordinates.each -> (coordinate)
      value = coerce(coordinate)
      values.push(value)
      pivot = value if pivot == nil && !zero?(value)
    raise "projective coordinates cannot all be zero" if pivot == nil
    scale = inverse(pivot)
    values.map -> multiply(item, scale)

  -> ==/1
    other = @1
    return false if other.class_name != "NumberField"
    same_monic_polynomial?(other.defining_polynomial)

  -> to_s
    "ℚ(" + @name.to_s + ")"

  -> inspect
    to_s

  -> signature
    real = @defining_polynomial.real_root_count
    [real, (3 - real) / 2]

  -> signature_certified?
    true

  -> totally_real?
    signature[0] == 3

  -> evaluate(polynomial, value)
    if polynomial.class_name != "Polynomial" || polynomial.ring.arity != 1
      raise "number-field evaluation needs a univariate polynomial"
    if polynomial.ring.field.class_name != "RationalField"
      raise "number-field evaluation currently needs a polynomial over ℚ"
    result = zero
    coefficients = polynomial.coefficients
    i = coefficients.size - 1
    while i >= 0
      result = add(multiply(result, value), coefficients[i])
      i -= 1
    result

  -> same_monic_polynomial?(polynomial)
    return false if polynomial.class_name != "Polynomial"
    return false if polynomial.ring.arity != 1 || polynomial.degree != 3
    return false if polynomial.ring.field.class_name != "RationalField"
    left = @defining_polynomial.coefficients
    right = polynomial.monic.coefficients
    i = 0
    while i < 4
      return false if left[i] != right[i]
      i += 1
    true

  # For the quartic workflow, unequal cubic-field discriminants certify that
  # no root can lie in K. Equal-discriminant, differently presented cubic
  # fields still require an isomorphism algorithm and therefore fail loudly.
  -> roots_of(polynomial)
    if polynomial.class_name != "Polynomial" || polynomial.ring.arity != 1
      raise "roots_in needs a univariate polynomial"
    if polynomial.ring.field.class_name != "RationalField"
      raise "roots_in is currently implemented only for polynomials over ℚ"
    raise "roots_in currently supports degree at most three" if polynomial.degree > 3

    roots = []
    polynomial.rational_root_candidates.each -> (candidate)
      if polynomial.at(candidate).zero?
        root = coerce(candidate)
        roots.push(root) if !roots.include?(root)
    return roots if polynomial.degree < 3 || roots.size > 0

    source = NumberField.new(polynomial, :b)
    return [] if source.field_discriminant != @field_discriminant
    if !same_monic_polynomial?(polynomial)
      raise "equal-discriminant cubic field isomorphism is not implemented; roots_in is unknown"

    discriminant = polynomial.monic.discriminant
    if !NumberField.rational_square?(discriminant)
      return [@generator]

    # If an irreducible cubic has square discriminant it is cyclic. Given one
    # root a and s = sqrt(disc(f)), the other-root difference is
    # s/f'(a), because s is the Vandermonde product
    # f'(a)(b-c). This constructs all three roots without radicals outside K.
    numerator_root = discriminant.numerator.isqrt
    denominator_root = discriminant.denominator.isqrt
    square_root = Rational.new(numerator_root, denominator_root)
    derivative_value = evaluate(polynomial.monic.derivative(0), @generator)
    difference = divide(square_root, derivative_value)
    quadratic_sum = negate(add(
      polynomial.monic.coefficients[2], @generator))
    two = coerce(2)
    second = divide(add(quadratic_sum, difference), two)
    third = divide(subtract(quadratic_sum, difference), two)
    out = [@generator, second, third]
    out.each ->
      if !evaluate(polynomial, item).zero?
        raise "cyclic cubic root construction invariant failed"
    out

  # Solve B*c = vector, where the three entries of B are its columns.
  -> solve_rational_coordinates(vector, basis)
    matrix = []
    row = 0
    while row < 3
      matrix.push([
        Rational.coerce(basis[0][row]),
        Rational.coerce(basis[1][row]),
        Rational.coerce(basis[2][row]),
        Rational.coerce(vector[row])])
      row += 1
    column = 0
    while column < 3
      pivot = column
      while pivot < 3 && matrix[pivot][column].zero?
        pivot += 1
      raise "singular number-field basis" if pivot == 3
      if pivot != column
        temporary = matrix[column]
        matrix[column] = matrix[pivot]
        matrix[pivot] = temporary
      pivot_value = matrix[column][column]
      cell = column
      while cell < 4
        matrix[column][cell] = matrix[column][cell] / pivot_value
        cell += 1
      row = 0
      while row < 3
        if row != column && !matrix[row][column].zero?
          factor = matrix[row][column]
          cell = column
          while cell < 4
            matrix[row][cell] = matrix[row][cell] - factor * matrix[column][cell]
            cell += 1
        row += 1
      column += 1
    [matrix[0][3], matrix[1][3], matrix[2][3]]

  -> multiply_power_vectors(left, right)
    product = [Rational.new(0), Rational.new(0), Rational.new(0),
               Rational.new(0), Rational.new(0)]
    i = 0
    while i < 3
      j = 0
      while j < 3
        product[i + j] = product[i + j] + Rational.coerce(left[i]) * Rational.coerce(right[j])
        j += 1
      i += 1
    relation = @integral_defining_polynomial.coefficients
    degree = 4
    while degree >= 3
      leading = product[degree]
      if !leading.zero?
        shift = degree - 3
        j = 0
        while j < 3
          product[shift + j] = product[shift + j] - leading * relation[j]
          j += 1
      degree -= 1
    [product[0], product[1], product[2]]

  -> determinant_of_basis(basis)
    a = basis[0]
    b = basis[1]
    c = basis[2]
    first = a[0] * (b[1] * c[2] - b[2] * c[1])
    second = b[0] * (a[1] * c[2] - a[2] * c[1])
    third = c[0] * (a[1] * b[2] - a[2] * b[1])
    first - second + third

  -> order_discriminant(basis)
    determinant = determinant_of_basis(basis)
    value = determinant * determinant * @integral_power_basis_discriminant
    if value.denominator != 1
      raise "closed cubic order has a nonintegral discriminant"
    value.numerator

  -> order_closed?(basis)
    i = 0
    while i < 3
      j = i
      while j < 3
        product = multiply_power_vectors(basis[i], basis[j])
        coordinates = solve_rational_coordinates(product, basis)
        coordinate_index = 0
        while coordinate_index < coordinates.size
          return false if coordinates[coordinate_index].denominator != 1
          coordinate_index += 1
        j += 1
      i += 1
    true

  -> discriminant_factorization
    remaining = @integral_power_basis_discriminant.abs
    factors = []
    candidate = 2
    attempts = 0
    while candidate * candidate <= remaining
      attempts += 1
      if attempts > @order_search_limit
        raise "discriminant factor search limit exceeded; field discriminant unknown"
      exponent = 0
      while remaining % candidate == 0
        remaining = remaining / candidate
        exponent += 1
      factors.push([candidate, exponent]) if exponent > 0
      candidate = candidate == 2 ? 3 : candidate + 2
    factors.push([remaining, 1]) if remaining > 1
    factors

  # Minkowski's theorem gives
  #
  #   sqrt(|D_K|) >= (pi/4)^r2 * 3^3 / 3! .
  #
  # Thus a totally real cubic has |D_K| >= 21. A cubic with one complex pair
  # has sqrt(|D_K|) > (3/4)*(9/2) = 27/8, using only the certified inequality
  # pi > 3, and hence |D_K| >= 12. These deliberately slightly weak integral
  # bounds need no floating-point approximation and are valid for every cubic
  # field. They are used only to reject impossible overorder indices.
  -> minkowski_discriminant_lower_bound
    @defining_polynomial.real_root_count == 3 ? 21 : 12

  -> possible_order_indices
    indices = [1]
    discriminant_factorization.each -> (factor)
      maximum = factor[1] / 2
      if maximum > 0
        previous = indices
        expanded = []
        previous.each -> (base)
          power = 1
          exponent = 0
          while exponent <= maximum
            expanded.push(base * power)
            power *= factor[0]
            exponent += 1
        indices = expanded
    lower_bound = minkowski_discriminant_lower_bound
    possible = []
    absolute_discriminant = @integral_power_basis_discriminant.abs
    indices.each -> (index)
      square = index * index
      if absolute_discriminant % square != 0
        raise "possible cubic order index did not square-divide the discriminant"
      candidate_discriminant = absolute_discriminant / square
      possible.push(index) if candidate_discriminant >= lower_bound
    possible.sort -> (left, right)
      right <=> left

  # A lower-triangular column Hermite normal form
  #
  #   [ a 0 0 ]
  #   [ b d 0 ]   with 0 <= b < d and 0 <= c,e < f
  #   [ c e f ]
  #
  # enumerates each index-m sublattice of Z^3 once (a*d*f=m). Taking duals
  # enumerates every index-m lattice containing the integral power order.
  -> hnf_dual_basis(a, b, c, d, e, f)
    [
      [Rational.new(1, a), Rational.new(0), Rational.new(0)],
      [Rational.new(0 - b, a * d), Rational.new(1, d), Rational.new(0)],
      [
        Rational.new(b * e - c * d, a * d * f),
        Rational.new(0 - e, d * f),
        Rational.new(1, f)]]

  # If base_basis is B and relative_basis is T, return the columns of B*T in
  # integral-power-basis coordinates.
  -> compose_order_bases(base_basis, relative_basis)
    out = []
    column = 0
    while column < 3
      vector = [Rational.new(0), Rational.new(0), Rational.new(0)]
      source = 0
      while source < 3
        scale = Rational.coerce(relative_basis[column][source])
        row = 0
        while row < 3
          vector[row] = vector[row] + Rational.coerce(base_basis[source][row]) * scale
          row += 1
        source += 1
      out.push(vector)
      column += 1
    out

  -> closed_relative_overorder_of_index(base_basis, index)
    attempts = 0
    a = 1
    while a <= index
      if index % a == 0
        after_a = index / a
        d = 1
        while d <= after_a
          if after_a % d == 0
            f = after_a / d
            b = 0
            while b < d
              c = 0
              while c < f
                e = 0
                while e < f
                  attempts += 1
                  if attempts > @order_search_limit
                    raise "maximal-order local lattice search limit exceeded at relative index " + index.to_s + "; field discriminant unknown"
                  relative_basis = hnf_dual_basis(a, b, c, d, e, f)
                  basis = compose_order_bases(base_basis, relative_basis)
                  return basis if order_closed?(basis)
                  e += 1
                c += 1
              b += 1
          d += 1
      a += 1
    nil

  -> closed_overorder_of_index(index)
    identity = [
      [Rational.new(1), Rational.new(0), Rational.new(0)],
      [Rational.new(0), Rational.new(1), Rational.new(0)],
      [Rational.new(0), Rational.new(0), Rational.new(1)]]
    closed_relative_overorder_of_index(identity, index)

  # Why the local search certifies maximality:
  #
  # Let S/R be a minimal proper overorder. For every integer n, R+nS is again
  # an order between R and S. Choosing a prime p dividing [S:R], minimality
  # therefore forces R+pS=R, while it also rules out any other primary part.
  # Hence S/R is an elementary F_p-vector space. Moreover 1 is primitive in
  # both rank-three orders and its nonzero class lies in the image of R/pS in
  # S/pS. Since dim_Fp(S/pS)=3, dim_Fp(S/R)<=2. Thus every nonmaximal cubic
  # order has a closed overorder of index p or p^2. Conversely, exhausting all
  # of the corresponding dual HNFs proves that no proper overorder exists.
  -> maximize_integral_order
    basis = [
      [Rational.new(1), Rational.new(0), Rational.new(0)],
      [Rational.new(0), Rational.new(1), Rational.new(0)],
      [Rational.new(0), Rational.new(0), Rational.new(1)]]
    discriminant = @integral_power_basis_discriminant
    factors = discriminant_factorization
    lower_bound = minkowski_discriminant_lower_bound

    while true
      extension = nil
      relative_index = 0
      factors.each -> (factor)
        if extension == nil
          prime = factor[0]
          prime_square = prime * prime
          absolute_discriminant = discriminant.abs

          # Every index-p overorder is the dual of one of the HNFs enumerated
          # here. The discriminant quotient and Minkowski check can reject the
          # entire family before any lattice arithmetic.
          if absolute_discriminant % prime_square == 0
            if absolute_discriminant / prime_square >= lower_bound
              extension = closed_relative_overorder_of_index(basis, prime)
              relative_index = prime if extension != nil

          # A minimal cubic overorder can also have index p^2 (for example
          # Z + p*O_K inside an inert cubic order), so index-p tests alone are
          # not a maximality certificate.
          prime_fourth = prime_square * prime_square
          if extension == nil
            if absolute_discriminant % prime_fourth == 0
              if absolute_discriminant / prime_fourth >= lower_bound
                extension = closed_relative_overorder_of_index(basis, prime_square)
                relative_index = prime_square if extension != nil

      if extension == nil
        return [basis, discriminant]

      next_discriminant = order_discriminant(extension)
      expected = discriminant / (relative_index * relative_index)
      if next_discriminant != expected
        raise "cubic local overorder discriminant invariant failed"
      basis = extension
      discriminant = next_discriminant

  -> .primitive_integer_coefficients(polynomial)
    coefficients = polynomial.coefficients
    common = 1
    coefficients.each ->
      common = (common / common.gcd(item.denominator)) * item.denominator
    integers = []
    coefficients.each ->
      integers.push(item.numerator * (common / item.denominator))
    divisor = 0
    integers.each -> divisor = divisor.gcd(item.abs)
    primitive = []
    integers.each -> (value)
      primitive.push(value / divisor)
    if primitive[3] < 0
      positive = []
      primitive.each -> (value)
        positive.push(0 - value)
      primitive = positive
    primitive

  -> .divisors_with_limit(value, limit)
    n = value.abs
    return [[0], 0] if n == 0
    divisors = []
    candidate = 1
    attempts = 0
    while candidate * candidate <= n
      attempts += 1
      if attempts > limit
        raise "cubic irreducibility resource limit exceeded; reducibility unknown"
      if n % candidate == 0
        divisors.push(candidate)
        other = n / candidate
        divisors.push(other) if other != candidate
      candidate += 1
    [divisors, attempts]

  # Exact rational-root theorem for degree three. Exhaustion proves
  # irreducibility; finding a root proves reducibility. Hitting the explicit
  # resource limit proves neither and raises a different error.
  -> .certify_irreducible_cubic(polynomial, trial_limit = 1_000_000)
    if polynomial.class_name != "Polynomial" || polynomial.ring.arity != 1 || polynomial.degree != 3
      raise "cubic irreducibility certification needs a univariate cubic"
    if polynomial.ring.field.class_name != "RationalField"
      raise "cubic irreducibility certification is only implemented over ℚ"
    integers = NumberField.primitive_integer_coefficients(polynomial)
    if integers[0] == 0
      raise "number field defining cubic is reducible over ℚ (root 0)"
    numerator_data = NumberField.divisors_with_limit(
      integers[0], trial_limit)
    remaining_limit = trial_limit - numerator_data[1]
    denominator_data = NumberField.divisors_with_limit(
      integers[3], remaining_limit)
    numerators = numerator_data[0]
    denominators = denominator_data[0]
    attempts = numerator_data[1] + denominator_data[1]
    numerators.each -> (numerator)
      denominators.each -> (denominator)
        sign = -1
        while sign <= 1
          if sign != 0
            attempts += 1
            if attempts > trial_limit
              raise "cubic irreducibility resource limit exceeded; reducibility unknown"
            p = sign * numerator
            q = denominator
            value = integers[0] * q * q * q + integers[1] * p * q * q + integers[2] * p * p * q + integers[3] * p * p * p
            if value == 0
              raise "number field defining cubic is reducible over ℚ (rational root)"
          sign += 1
    true

  -> .rational_square?(value)
    rational = Rational.coerce(value)
    return false if rational.numerator < 0
    numerator_root = rational.numerator.isqrt
    denominator_root = rational.denominator.isqrt
    numerator_square = numerator_root * numerator_root == rational.numerator
    denominator_square = denominator_root * denominator_root == rational.denominator
    numerator_square && denominator_square

+ Polynomial
  -> field_discriminant
    if @ring.arity != 1 || degree != 3 || @ring.field.class_name != "RationalField"
      raise "field_discriminant currently needs an irreducible cubic over ℚ"
    NumberField.new(self).field_discriminant

  -> roots_in(number_field)
    if number_field.class_name != "NumberField"
      raise "roots_in currently needs a NumberField"
    number_field.roots_of(self)
