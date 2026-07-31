# Exact finite fields with Integer-encoded elements.
#
# A prime-field element is its least nonnegative residue. An element of
# F_{p^n} is the base-p encoding a0 + a1*p + ... + a[n-1]*p^(n-1), interpreted
# as a0 + a1*t + ... modulo a monic irreducible polynomial. This keeps the hot
# representation an unboxed Integer; structural polynomial code routes every
# coefficient operation through the Field protocol.

+ FiniteField < Field
  -> coefficient_field?
    true

  -> new(characteristic)
    initialize_finite_field(characteristic, nil)

  -> new(characteristic, modulus)
    initialize_finite_field(characteristic, modulus)

  -> initialize_finite_field(characteristic, modulus)
    characteristic_class = characteristic.class_name
    if characteristic_class != "Integer" && characteristic_class != "Int" && characteristic_class != "BigInt"
      raise "finite-field characteristic must be an integer"
    if characteristic < 2 || !characteristic.prime?
      raise "finite-field characteristic must be prime"
    @characteristic = characteristic
    @modulus = nil
    @degree = 1
    if modulus != nil
      raise "finite-field modulus must be an Array" if modulus.class_name != "Array"
      raise "finite-field extension degree must be at least two" if modulus.size < 3
      @degree = modulus.size - 1
      @modulus = []
      modulus.each -> @modulus.push(base_residue(item))
      raise "finite-field modulus must be monic" if @modulus[@degree] != 1
      raise "finite-field modulus must be irreducible" if !modulus_irreducible?(@modulus)
    @order = @characteristic ** @degree
    @multiplication_table = nil
    self

  ro :characteristic, :degree, :order, :modulus

  -> exact?
    true

  -> finite_field?
    true

  -> prime_field?
    @degree == 1

  -> absolute_degree
    @degree

  -> irreducibility_certified?
    true

  -> modulus_certificate
    raise "a prime field has no extension modulus" if prime_field?
    FiniteFieldModulusCertificate.new(@characteristic, @modulus)

  # The residue class of t. It generates the extension as an algebra over the
  # prime field, though it need not generate the multiplicative group.
  -> generator
    prime_field? ? one : @characteristic

  -> power_basis
    basis = []
    value = one
    i = 0
    while i < @degree
      basis.push(value)
      value = multiply(value, generator)
      i += 1
    basis

  -> base_residue(value)
    result = value % @characteristic
    result += @characteristic if result < 0
    result

  -> encode_coefficients(coefficients)
    raise "finite-field element has too many coefficients" if coefficients.size > @degree
    result = 0
    place = 1
    i = 0
    while i < @degree
      coefficient = i < coefficients.size ? base_residue(coefficients[i]) : 0
      result += coefficient * place
      place *= @characteristic
      i += 1
    result

  -> element_coefficients(value)
    encoded = normalize_element(value)
    coefficients = []
    i = 0
    while i < @degree
      coefficients.push(encoded % @characteristic)
      encoded = encoded / @characteristic
      i += 1
    coefficients

  # External Integers embed through the prime subfield. Arrays explicitly
  # describe extension-basis coefficients.
  -> coerce(value)
    return encode_coefficients(value) if value.class_name == "Array"
    if value.class_name == "Rational"
      numerator = coerce(value.numerator)
      denominator = coerce(value.denominator)
      return divide(numerator, denominator)
    base_residue(value)

  # Internal arithmetic already returns an encoded residue in [0, order).
  -> normalize_element(value)
    value_class = value.class_name
    if value_class == "Integer" || value_class == "Int" || value_class == "BigInt"
      return value if value >= 0 && value < @order
    coerce(value)

  -> embed_from(source_field, value)
    return normalize_element(value) if source_field == self
    if source_field.class_name == "RationalField"
      return coerce(value)
    if source_field.class_name == "FiniteField"
      if source_field.prime_field? && source_field.characteristic == @characteristic
        return coerce(value)
    raise "no certified field embedding from " + source_field.to_s + " into " + to_s

  # Canonical enumeration index used by finite-field algorithms. Packed
  # finite fields already use exactly this integer representation.
  -> element_from_index(index)
    if index < 0 || index >= @order
      raise "finite-field element index out of range"
    index

  -> zero
    0

  -> one
    1

  -> zero?(value)
    normalize_element(value) == 0

  -> one?(value)
    normalize_element(value) == 1

  -> equal?(left, right)
    normalize_element(left) == normalize_element(right)

  -> add(left, right)
    a = normalize_element(left)
    b = normalize_element(right)
    return base_residue(a + b) if @degree == 1
    p = @characteristic
    a0 = a % p
    b0 = b % p
    a = a / p
    b = b / p
    result = base_residue(a0 + b0)
    place = p
    i = 1
    while i < @degree
      result += base_residue((a % p) + (b % p)) * place
      a = a / p
      b = b / p
      place *= p
      i += 1
    result

  -> negate(value)
    a = normalize_element(value)
    return base_residue(0 - a) if @degree == 1
    p = @characteristic
    result = 0
    place = 1
    i = 0
    while i < @degree
      result += base_residue(0 - (a % p)) * place
      a = a / p
      place *= p
      i += 1
    result

  -> subtract(left, right)
    add(left, negate(right))

  -> multiply(left, right)
    a = normalize_element(left)
    b = normalize_element(right)
    if @multiplication_table != nil
      return @multiplication_table[a * @order + b]
    multiply_encoded(a, b)

  -> multiply_encoded(a, b)
    return base_residue(a * b) if @degree == 1
    if @degree <= 3
      p = @characteristic
      a0 = a % p
      a = a / p
      a1 = a % p
      b0 = b % p
      b = b / p
      b1 = b % p

      if @degree == 2
        high = a1 * b1
        r0 = base_residue(a0 * b0 - high * @modulus[0])
        r1 = base_residue(a0 * b1 + a1 * b0 - high * @modulus[1])
        return r0 + r1 * p

      a2 = (a / p) % p
      b2 = (b / p) % p
      c0 = a0 * b0
      c1 = a0 * b1 + a1 * b0
      c2 = a0 * b2 + a1 * b1 + a2 * b0
      c4 = a2 * b2
      c3 = a1 * b2 + a2 * b1 - c4 * @modulus[2]
      r0 = base_residue(c0 - c3 * @modulus[0])
      r1 = base_residue(c1 - c4 * @modulus[0] - c3 * @modulus[1])
      r2 = base_residue(c2 - c4 * @modulus[1] - c3 * @modulus[2])
      return r0 + r1 * p + r2 * p * p

    left_coefficients = element_coefficients(a)
    right_coefficients = element_coefficients(b)
    product = []
    i = 0
    while i < @degree * 2 - 1
      product.push(0)
      i += 1
    i = 0
    while i < @degree
      j = 0
      while j < @degree
        product[i + j] = base_residue(
          product[i + j] + left_coefficients[i] * right_coefficients[j])
        j += 1
      i += 1

    exponent = product.size - 1
    while exponent >= @degree
      leading = product[exponent]
      if leading != 0
        shift = exponent - @degree
        j = 0
        while j < @degree
          product[shift + j] = base_residue(
            product[shift + j] - leading * @modulus[j])
          j += 1
      exponent -= 1
    # Reduction only needs the low-degree coefficients. This result must own
    # its storage: `slice` creates a zero-copy view whose parent is a temporary
    # multiplication buffer, and retaining those views makes every later
    # parent-array growth walk an ever-growing view registry.
    encode_coefficients(product.copy(0, @degree))

  # Small finite geometries evaluate the same field products many thousands
  # of times. A checked q^2 table turns those exact operations into one Array
  # lookup without changing the packed public representation. Larger fields
  # retain the sparse generic kernel.
  -> prepare_arithmetic!(table_order_limit = 256)
    return self if @multiplication_table != nil
    return self if prime_field? || @order > table_order_limit
    table = []
    left = 0
    while left < @order
      right = 0
      while right < @order
        table.push(multiply_encoded(left, right))
        right += 1
      left += 1
    @multiplication_table = table
    self

  -> arithmetic_prepared?
    prime_field? || @multiplication_table != nil

  -> power(value, exponent)
    exponent_class = exponent.class_name
    if exponent_class != "Integer" && exponent_class != "Int" && exponent_class != "BigInt"
      raise "finite-field exponent must be an integer"
    return power(inverse(value), 0 - exponent) if exponent < 0
    result = one
    factor = normalize_element(value)
    remaining = exponent
    while remaining > 0
      result = multiply(result, factor) if remaining.odd?
      remaining = remaining / 2
      factor = multiply(factor, factor) if remaining > 0
    result

  # Exact square testing in F_q.  In characteristic two Frobenius is an
  # automorphism, so every element has a unique square root.  For odd q,
  # Euler's criterion distinguishes the two cosets of F_q^*/F_q^{*2}.
  -> square?(value)
    element = normalize_element(value)
    return true if element == zero
    return true if @characteristic == 2
    one?(power(element, (@order - 1) / 2))

  # Return 0 on zero and +/-1 on the two multiplicative square classes.
  # A signed quadratic character is deliberately unavailable in
  # characteristic two, where the square-class quotient is trivial.
  -> quadratic_character(value)
    if @characteristic == 2
      raise "quadratic character is not signed in characteristic two"
    element = normalize_element(value)
    return 0 if element == zero
    criterion = power(element, (@order - 1) / 2)
    return 1 if one?(criterion)
    return -1 if equal?(criterion, negate(one))
    raise "Euler criterion produced a nonquadratic residue-field value"

  -> inverse(value)
    element = normalize_element(value)
    raise "division by zero in finite field" if element == 0
    power(element, @order - 2)

  -> divide(left, right)
    multiply(left, inverse(right))

  -> frobenius(value, iterations = 1)
    iteration_class = iterations.class_name
    if iteration_class != "Integer" && iteration_class != "Int" && iteration_class != "BigInt"
      raise "Frobenius iteration count must be an integer"
    raise "Frobenius iteration count must be nonnegative" if iterations < 0
    result = normalize_element(value)
    return result if prime_field?
    remaining = iterations % @degree
    while remaining > 0
      result = power(result, @characteristic)
      remaining -= 1
    result

  -> inverse_frobenius(value, iterations = 1)
    iteration_class = iterations.class_name
    if iteration_class != "Integer" && iteration_class != "Int" && iteration_class != "BigInt"
      raise "inverse Frobenius iteration count must be an integer"
    raise "inverse Frobenius iteration count must be nonnegative" if iterations < 0
    return normalize_element(value) if prime_field?
    reduced = iterations % @degree
    frobenius(value, reduced == 0 ? 0 : @degree - reduced)

  -> frobenius_orbit(value)
    element = normalize_element(value)
    orbit = []
    current = element
    while !orbit.include?(current)
      orbit.push(current)
      current = frobenius(current)
      if orbit.size > @degree
        raise "finite-field Frobenius orbit exceeded the extension degree"
    if current != element
      raise "finite-field Frobenius orbit failed to close at its source"
    orbit

  -> prime_subfield_value(value)
    coefficients = element_coefficients(value)
    i = 1
    while i < coefficients.size
      if coefficients[i] != 0
        raise "finite-field invariant did not land in the prime subfield"
      i += 1
    coefficients[0]

  -> trace(value)
    element = normalize_element(value)
    result = zero
    conjugate = element
    i = 0
    while i < @degree
      result = add(result, conjugate)
      conjugate = frobenius(conjugate)
      i += 1
    prime_subfield_value(result)

  -> norm(value)
    element = normalize_element(value)
    return element if prime_field?
    exponent = (@order - 1) / (@characteristic - 1)
    prime_subfield_value(power(element, exponent))

  -> evaluate_prime_polynomial(polynomial, value)
    if polynomial.class_name != "Polynomial" || polynomial.ring.arity != 1
      raise "finite-field evaluation needs a univariate polynomial"
    source_field = polynomial.ring.field
    matching_prime_field = false
    if source_field.class_name == "FiniteField"
      matching_prime_field = source_field.prime_field?
      if matching_prime_field
        matching_prime_field = source_field.characteristic == @characteristic
    if !matching_prime_field
      raise "finite-field minimal-polynomial evaluation needs the matching prime field"
    result = zero
    coefficients = polynomial.coefficients
    i = coefficients.size - 1
    while i >= 0
      result = add(multiply(result, value), coefficients[i])
      i -= 1
    result

  # Product over the exact Frobenius orbit. The coefficients are checked to
  # lie in F_p before they are copied from the extension ring to F_p[T].
  -> minimal_polynomial(value, name = :T)
    element = normalize_element(value)
    orbit = frobenius_orbit(element)
    extension_ring = PolynomialRing.new([name], self)
    variable = extension_ring.generator(0)
    polynomial = extension_ring.one
    orbit.each -> (conjugate)
      constant = extension_ring.monomial_raw(
        conjugate, extension_ring.zero_exponents)
      polynomial = polynomial * (variable - constant)

    prime_field = FiniteField.new(@characteristic)
    prime_ring = PolynomialRing.new([name], prime_field)
    terms = []
    polynomial.each_term -> (coefficient, exponents)
      terms.push([prime_subfield_value(coefficient), exponents])
    result = Polynomial.new(prime_ring, terms).monic
    if !zero?(evaluate_prime_polynomial(result, element))
      raise "finite-field minimal-polynomial invariant failed"
    result

  -> minimal_polynomial_certificate(value, name = :T)
    FiniteFieldMinimalPolynomialCertificate.new(
      self, normalize_element(value), minimal_polynomial(value, name))

  -> negative?(value)
    false

  -> element_to_s(value)
    encoded = normalize_element(value)
    return encoded.to_s if @degree == 1
    element_coefficients(encoded).to_s

  -> normalize_projective_coordinates(coordinates)
    raise "projective coordinates need at least one entry" if coordinates.size == 0
    values = []
    pivot = nil
    coordinates.each -> (coordinate)
      value = normalize_element(coordinate)
      values.push(value)
      pivot = value if pivot == nil && !zero?(value)
    raise "projective coordinates cannot all be zero" if pivot == nil
    scale = inverse(pivot)
    values.map -> multiply(item, scale)

  -> modulus_at(coefficients, value)
    result = 0
    i = coefficients.size - 1
    while i >= 0
      result = base_residue(result * value + coefficients[i])
      i -= 1
    result

  -> trim_base_polynomial(coefficients)
    out = []
    coefficients.each -> out.push(base_residue(item))
    while out.size > 1 && out[out.size - 1] == 0
      out.delete_at(out.size - 1)
    out.push(0) if out.size == 0
    out

  -> base_polynomial_zero?(polynomial)
    value = trim_base_polynomial(polynomial)
    value.size == 1 && value[0] == 0

  -> base_polynomial_equal?(left, right)
    a = trim_base_polynomial(left)
    b = trim_base_polynomial(right)
    return false if a.size != b.size
    i = 0
    while i < a.size
      return false if a[i] != b[i]
      i += 1
    true

  -> base_polynomial_subtract(left, right)
    size = left.size > right.size ? left.size : right.size
    out = []
    i = 0
    while i < size
      a = i < left.size ? left[i] : 0
      b = i < right.size ? right[i] : 0
      out.push(base_residue(a - b))
      i += 1
    trim_base_polynomial(out)

  -> base_inverse(value)
    element = base_residue(value)
    raise "division by zero in prime subfield" if element == 0
    result = 1
    factor = element
    exponent = @characteristic - 2
    while exponent > 0
      result = base_residue(result * factor) if exponent.odd?
      exponent = exponent / 2
      factor = base_residue(factor * factor) if exponent > 0
    result

  -> base_polynomial_remainder(dividend, divisor)
    remainder = trim_base_polynomial(dividend)
    denominator = trim_base_polynomial(divisor)
    raise "base-polynomial division by zero" if base_polynomial_zero?(denominator)
    denominator_degree = denominator.size - 1
    inverse_leading = base_inverse(denominator[denominator_degree])
    while !base_polynomial_zero?(remainder)
      remainder_degree = remainder.size - 1
      break if remainder_degree < denominator_degree
      factor = base_residue(
        remainder[remainder_degree] * inverse_leading)
      shift = remainder_degree - denominator_degree
      i = 0
      while i <= denominator_degree
        remainder[shift + i] = base_residue(
          remainder[shift + i] - factor * denominator[i])
        i += 1
      remainder = trim_base_polynomial(remainder)
    remainder

  -> base_polynomial_multiply_mod(left, right, modulus)
    product = []
    i = 0
    while i < left.size + right.size - 1
      product.push(0)
      i += 1
    i = 0
    while i < left.size
      j = 0
      while j < right.size
        product[i + j] = base_residue(
          product[i + j] + left[i] * right[j])
        j += 1
      i += 1
    base_polynomial_remainder(product, modulus)

  -> base_polynomial_power_mod(value, exponent, modulus)
    raise "base-polynomial exponent must be nonnegative" if exponent < 0
    result = [1]
    factor = base_polynomial_remainder(value, modulus)
    remaining = exponent
    while remaining > 0
      if remaining.odd?
        result = base_polynomial_multiply_mod(result, factor, modulus)
      remaining = remaining / 2
      if remaining > 0
        factor = base_polynomial_multiply_mod(factor, factor, modulus)
    result

  -> base_polynomial_gcd(left, right)
    a = trim_base_polynomial(left)
    b = trim_base_polynomial(right)
    while !base_polynomial_zero?(b)
      remainder = base_polynomial_remainder(a, b)
      a = b
      b = remainder
    return [0] if base_polynomial_zero?(a)
    scale = base_inverse(a[a.size - 1])
    out = []
    a.each -> out.push(base_residue(item * scale))
    trim_base_polynomial(out)

  -> prime_divisors(value)
    remaining = value
    factors = []
    candidate = 2
    while candidate * candidate <= remaining
      if remaining % candidate == 0
        factors.push(candidate)
        while remaining % candidate == 0
          remaining = remaining / candidate
      candidate = candidate == 2 ? 3 : candidate + 2
    factors.push(remaining) if remaining > 1
    factors

  # Rabin's criterion: a monic degree-n polynomial f over F_p is irreducible
  # exactly when X^(p^n)=X mod f and
  # gcd(f, X^(p^(n/q))-X)=1 for every prime q dividing n.
  -> modulus_irreducible?(coefficients)
    polynomial = trim_base_polynomial(coefficients)
    degree = polynomial.size - 1
    return false if degree < 1 || polynomial[degree] != 1
    x = [0, 1]
    critical_degrees = []
    prime_divisors(degree).each ->
      critical_degrees.push(degree / item)

    frobenius = x
    iteration = 1
    while iteration <= degree
      frobenius = base_polynomial_power_mod(
        frobenius, @characteristic, polynomial)
      if critical_degrees.include?(iteration)
        difference = base_polynomial_subtract(frobenius, x)
        common = base_polynomial_gcd(polynomial, difference)
        return false if common.size - 1 != 0
      iteration += 1
    base_polynomial_equal?(frobenius, x)

  -> extension(degree, search_limit = 1_000_000)
    raise "extensions must be constructed from a prime field" if @degree != 1
    FiniteField.extension(@characteristic, degree, search_limit)

  -> each_element(&)
    value = 0
    while value < @order
      &(value)
      value += 1
    self

  -> ==/1
    other = @1
    return false if other.class_name != "FiniteField"
    return false if @characteristic != other.characteristic || @degree != other.degree
    return true if @modulus == nil && other.modulus == nil
    return false if @modulus == nil || other.modulus == nil
    @modulus.to_s == other.modulus.to_s

  -> to_s
    return "𝔽_" + @characteristic.to_s if @degree == 1
    "𝔽_" + @characteristic.to_s + "^" + @degree.to_s

  -> inspect
    to_s

  -> .prime(characteristic)
    FiniteField.new(characteristic)

  -> .small_irreducible?(characteristic, coefficients)
    FiniteField.new(characteristic).modulus_irreducible?(coefficients)

  # Deterministically choose the first monic irreducible polynomial in base-p
  # coefficient order. Rabin verification makes every returned modulus a
  # certificate-checked field definition. Search exhaustion raises instead of
  # silently substituting a reducible quotient.
  -> .extension(characteristic, degree, search_limit = 1_000_000)
    degree_class = degree.class_name
    if degree_class != "Integer" && degree_class != "Int" && degree_class != "BigInt"
      raise "finite-field extension degree must be an integer"
    if degree < 1
      raise "finite-field extension degree must be positive"
    search_class = search_limit.class_name
    if search_class != "Integer" && search_class != "Int" && search_class != "BigInt"
      raise "finite-field modulus search limit must be an integer"
    if search_limit < 1
      raise "finite-field modulus search limit must be positive"
    return FiniteField.new(characteristic) if degree == 1
    prime_field = FiniteField.new(characteristic)
    limit = characteristic ** degree
    code = 1
    attempts = 0
    while code < limit
      attempts += 1
      if attempts > search_limit
        raise "finite-field modulus search limit exceeded; extension construction unknown"
      remaining = code
      coefficients = []
      i = 0
      while i < degree
        coefficients.push(remaining % characteristic)
        remaining = remaining / characteristic
        i += 1
      coefficients.push(1)
      if prime_field.modulus_irreducible?(coefficients)
        return FiniteField.new(characteristic, coefficients)
      code += 1
    raise "could not find a finite-field modulus"


+ FiniteFieldModulusCertificate
  -> new(@characteristic, modulus)
    @modulus = []
    modulus.each -> @modulus.push(item)

  -> characteristic
    @characteristic

  -> modulus
    out = []
    @modulus.each -> out.push(item)
    out

  -> degree
    @modulus.size - 1

  -> verified?
    characteristic_class = @characteristic.class_name
    integer_characteristic = characteristic_class == "Integer"
    integer_characteristic = integer_characteristic || characteristic_class == "Int"
    integer_characteristic = integer_characteristic || characteristic_class == "BigInt"
    return false if !integer_characteristic
    return false if @characteristic < 2 || !@characteristic.prime?
    return false if @modulus.size < 3
    prime_field = FiniteField.new(@characteristic)
    normalized = []
    @modulus.each -> normalized.push(prime_field.base_residue(item))
    return false if normalized[normalized.size - 1] != 1
    prime_field.modulus_irreducible?(normalized)

  -> certified?
    verified?

  -> to_s
    text = "FiniteFieldModulusCertificate(" + @characteristic.to_s
    text + ", " + @modulus.to_s + ")"

  -> inspect
    to_s


+ FiniteFieldMinimalPolynomialCertificate
  -> new(@field, element, @polynomial)
    @element = @field.normalize_element(element)

  -> field
    @field

  -> element
    @element

  -> polynomial
    @polynomial

  -> verified?
    return false if @field.class_name != "FiniteField"
    return false if @polynomial.class_name != "Polynomial"
    return false if @polynomial.ring.arity != 1
    coefficient_field = @polynomial.ring.field
    return false if coefficient_field.class_name != "FiniteField"
    return false if !coefficient_field.prime_field?
    return false if coefficient_field.characteristic != @field.characteristic
    return false if !@polynomial.eql?(@polynomial.monic)
    return false if !@field.zero?(
      @field.evaluate_prime_polynomial(@polynomial, @element))
    orbit = @field.frobenius_orbit(@element)
    return false if @polynomial.degree != orbit.size
    expected = @field.minimal_polynomial(
      @element, @polynomial.ring.names[0])
    expected.eql?(@polynomial)

  -> certified?
    verified?

  -> to_s
    "FiniteFieldMinimalPolynomialCertificate(" + @polynomial.to_s + ")"

  -> inspect
    to_s
