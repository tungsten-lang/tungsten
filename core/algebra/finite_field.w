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
      raise "finite-field extension degree must be two or three" if modulus.size < 3 || modulus.size > 4
      @degree = modulus.size - 1
      @modulus = []
      modulus.each -> @modulus.push(base_residue(item))
      raise "finite-field modulus must be monic" if @modulus[@degree] != 1
      raise "finite-field modulus must be irreducible" if !modulus_irreducible?(@modulus)
    @order = @characteristic ** @degree
    self

  ro :characteristic, :degree, :order, :modulus

  -> exact?
    true

  -> prime_field?
    @degree == 1

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
    return base_residue(a * b) if @degree == 1
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
    r0 + r1 * p + r2 * p * p

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

  -> inverse(value)
    element = normalize_element(value)
    raise "division by zero in finite field" if element == 0
    power(element, @order - 2)

  -> divide(left, right)
    multiply(left, inverse(right))

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

  -> modulus_irreducible?(coefficients)
    root = 0
    while root < @characteristic
      return false if modulus_at(coefficients, root) == 0
      root += 1
    true

  -> extension(degree)
    raise "extensions must be constructed from a prime field" if @degree != 1
    FiniteField.extension(@characteristic, degree)

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
    root = 0
    while root < characteristic
      value = 0
      i = coefficients.size - 1
      while i >= 0
        value = (value * root + coefficients[i]) % characteristic
        value += characteristic if value < 0
        i -= 1
      return false if value == 0
      root += 1
    true

  # Deterministically choose the first monic irreducible quadratic or cubic
  # in base-p coefficient order. The exact modulus is exposed and tested.
  -> .extension(characteristic, degree)
    return FiniteField.new(characteristic) if degree == 1
    if degree < 2 || degree > 3
      raise "finite-field extension degree must be one, two, or three"
    limit = characteristic ** degree
    code = 1
    while code < limit
      remaining = code
      coefficients = []
      i = 0
      while i < degree
        coefficients.push(remaining % characteristic)
        remaining = remaining / characteristic
        i += 1
      coefficients.push(1)
      if FiniteField.small_irreducible?(characteristic, coefficients)
        return FiniteField.new(characteristic, coefficients)
      code += 1
    raise "could not find a finite-field modulus"
