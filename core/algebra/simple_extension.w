# Exact simple algebraic extensions K[a]/(m).
#
# This is the field-theoretic quotient layer between PolynomialRing and
# geometry. Unlike NumberField, it is not tied to Q or to arithmetic of the
# maximal order: coefficients remain elements of an explicit base Field.
# The modulus is accepted only after a replay-certified factorization proves
# it irreducible. Today that means Q and finite base fields; unsupported base
# factorization fails loudly.

+ SimpleExtensionElement
  -> new(@field, coefficients)
    initialize_simple_extension_element(coefficients, false)

  -> new(@field, coefficients, raw)
    initialize_simple_extension_element(coefficients, raw)

  -> .raw(field, coefficients)
    SimpleExtensionElement.new(field, coefficients, true)

  -> initialize_simple_extension_element(coefficients, raw)
    @coefficients = @field.reduce_coefficients(coefficients, raw)
    self

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
    right = nil
    if other.class_name == "SimpleExtensionElement"
      if other.field == @field
        right = other
      elsif other.field == @field.base_field
        right = @field.embed_base_element(other)
      else
        return false
    else
      value_class = other.class_name
      scalar = value_class == "Integer" || value_class == "Int"
      scalar = scalar || value_class == "BigInt"
      scalar = scalar || value_class == "Rational"
      scalar = scalar || value_class == "NumberFieldElement"
      return false if !scalar
      right = @field.coerce(other)

    right_coefficients = right.coefficients
    i = 0
    while i < @field.degree
      if !@field.base_field.equal?(
          @coefficients[i], right_coefficients[i])
        return false
      i += 1
    true

  -> to_s
    @field.element_to_s(self)

  -> inspect
    to_s


+ SimpleExtensionModulusCertificate
  -> new(@base_field, @polynomial, @factorization)

  -> base_field
    @base_field

  -> polynomial
    @polynomial

  -> factorization
    @factorization

  -> verified?
    return false if !Field.supported?(@base_field)
    return false if @polynomial.class_name != "Polynomial"
    return false if @polynomial.ring.arity != 1
    return false if @polynomial.ring.field != @base_field
    return false if @polynomial.degree < 2
    return false if !@polynomial.eql?(@polynomial.monic)
    return false if @factorization.class_name != "PolynomialFactorization"
    return false if !@factorization.polynomial.eql?(@polynomial)
    return false if !@factorization.certificate.verified?
    nonconstant = []
    @factorization.factors.each ->
      nonconstant.push(item) if item.degree > 0
    return false if nonconstant.size != 1
    nonconstant[0].eql?(@polynomial)

  -> certified?
    verified?

  -> to_s
    "SimpleExtensionModulusCertificate(" + @polynomial.to_s + ")"

  -> inspect
    to_s


+ SimpleExtensionField < Field
  -> new(polynomial)
    initialize_simple_extension(polynomial, :a, 250_000)

  -> new(polynomial, name)
    initialize_simple_extension(polynomial, name, 250_000)

  -> new(polynomial, name, factor_search_limit)
    initialize_simple_extension(
      polynomial, name, factor_search_limit)

  -> initialize_simple_extension(polynomial, name, factor_search_limit)
    if polynomial.class_name != "Polynomial"
      raise "simple extension modulus must be a Polynomial"
    if polynomial.ring.arity != 1 || polynomial.degree < 2
      raise "simple extension needs a univariate modulus of degree at least two"
    @base_field = Field.require_supported(polynomial.ring.field)
    @name = name
    @defining_polynomial = polynomial.monic
    @degree = @defining_polynomial.degree
    @modulus_factorization = @defining_polynomial.factor_with_certificate(
      factor_search_limit)
    certificate = SimpleExtensionModulusCertificate.new(
      @base_field, @defining_polynomial, @modulus_factorization)
    if !certificate.verified?
      raise "simple extension modulus is reducible over its base field"

    coefficients = @defining_polynomial.coefficients
    @relation = []
    i = 0
    while i < @degree
      @relation.push(coefficients[i])
      i += 1

    generator_coefficients = base_zero_coefficients
    generator_coefficients[1] = @base_field.one
    @generator = SimpleExtensionElement.raw(
      self, generator_coefficients)
    self

  -> coefficient_field?
    true

  -> exact?
    true

  -> finite_field?
    @base_field.finite_field?

  -> prime_field?
    false

  -> characteristic
    @base_field.characteristic

  -> degree
    @degree

  -> relative_degree
    @degree

  -> absolute_degree
    if !finite_field?
      raise "absolute finite-field degree requires a finite base field"
    @base_field.absolute_degree * @degree

  -> order
    if !finite_field?
      raise "an infinite simple extension has no finite order"
    @base_field.order ** @degree

  -> base_field
    @base_field

  -> name
    @name

  -> defining_polynomial
    @defining_polynomial

  -> generator
    @generator

  -> irreducible?
    true

  -> irreducibility_certified?
    true

  -> modulus_certificate
    SimpleExtensionModulusCertificate.new(
      @base_field, @defining_polynomial, @modulus_factorization)

  -> factorization_certificate
    @modulus_factorization.certificate

  -> base_zero_coefficients
    out = []
    i = 0
    while i < @degree
      out.push(@base_field.zero)
      i += 1
    out

  -> reduce_coefficients(coefficients, raw = false)
    if coefficients.class_name != "Array"
      raise "simple-extension coefficients must be an Array"
    values = []
    coefficients.each ->
      value = raw ? @base_field.normalize_element(item) : @base_field.coerce(item)
      values.push(value)
    while values.size < @degree
      values.push(@base_field.zero)

    i = values.size - 1
    while i >= @degree
      leading = values[i]
      if !@base_field.zero?(leading)
        shift = i - @degree
        j = 0
        while j < @degree
          correction = @base_field.multiply(
            leading, @relation[j])
          values[shift + j] = @base_field.subtract(
            values[shift + j], correction)
          j += 1
      values[i] = @base_field.zero
      i -= 1

    out = []
    i = 0
    while i < @degree
      out.push(values[i])
      i += 1
    out

  -> element_raw(coefficients)
    SimpleExtensionElement.raw(self, coefficients)

  # Public arrays contain external base-field scalars. Use element_raw when
  # the coefficients are already normalized elements of a packed base field.
  -> coerce(value)
    if value.class_name == "SimpleExtensionElement"
      return value if value.field == self
      if value.field == @base_field
        return embed_base_element(value)
      raise "simple-extension elements belong to different fields"
    if value.class_name == "Array"
      return SimpleExtensionElement.new(self, value)
    embed_base_element(@base_field.coerce(value))

  -> normalize_element(value)
    if value.class_name == "SimpleExtensionElement" && value.field == self
      return value
    coerce(value)

  -> embed_base(value)
    embed_base_element(@base_field.coerce(value))

  -> embed_base_element(value)
    coefficients = base_zero_coefficients
    coefficients[0] = @base_field.normalize_element(value)
    SimpleExtensionElement.raw(self, coefficients)

  -> embed_from(source_field, value)
    return normalize_element(value) if source_field == self
    base_value = @base_field.embed_from(source_field, value)
    embed_base_element(base_value)

  -> zero
    SimpleExtensionElement.raw(self, base_zero_coefficients)

  -> one
    coefficients = base_zero_coefficients
    coefficients[0] = @base_field.one
    SimpleExtensionElement.raw(self, coefficients)

  -> zero?(value)
    coefficients = normalize_element(value).coefficients
    i = 0
    while i < @degree
      return false if !@base_field.zero?(coefficients[i])
      i += 1
    true

  -> one?(value)
    coefficients = normalize_element(value).coefficients
    return false if !@base_field.one?(coefficients[0])
    i = 1
    while i < @degree
      return false if !@base_field.zero?(coefficients[i])
      i += 1
    true

  -> equal?(left, right)
    normalize_element(left).eql?(normalize_element(right))

  -> add(left, right)
    a = normalize_element(left).coefficients
    b = normalize_element(right).coefficients
    out = []
    i = 0
    while i < @degree
      out.push(@base_field.add(a[i], b[i]))
      i += 1
    SimpleExtensionElement.raw(self, out)

  -> negate(value)
    coefficients = normalize_element(value).coefficients
    out = []
    coefficients.each ->
      out.push(@base_field.negate(item))
    SimpleExtensionElement.raw(self, out)

  -> subtract(left, right)
    add(left, negate(right))

  -> multiply(left, right)
    a = normalize_element(left).coefficients
    b = normalize_element(right).coefficients
    product = []
    i = 0
    while i < @degree * 2 - 1
      product.push(@base_field.zero)
      i += 1
    i = 0
    while i < @degree
      j = 0
      while j < @degree
        product[i + j] = @base_field.add(
          product[i + j],
          @base_field.multiply(a[i], b[j]))
        j += 1
      i += 1
    SimpleExtensionElement.raw(self, product)

  -> element_polynomial(value)
    element = normalize_element(value)
    terms = []
    coefficients = element.coefficients
    i = 0
    while i < coefficients.size
      if !@base_field.zero?(coefficients[i])
        terms.push([coefficients[i], [i]])
      i += 1
    Polynomial.new(@defining_polynomial.ring, terms)

  -> inverse(value)
    element = normalize_element(value)
    raise "division by zero in simple extension" if zero?(element)
    polynomial = element_polynomial(element)
    bezout = polynomial.xgcd(@defining_polynomial)
    gcd = bezout[0]
    if gcd.degree != 0 || @base_field.zero?(gcd.coeff(0))
      raise "nonzero extension element was not invertible; modulus invariant failed"
    scale = @base_field.inverse(gcd.coeff(0))
    terms = []
    bezout[1].each_term -> (coefficient, exponents)
      terms.push([
        @base_field.multiply(coefficient, scale),
        exponents
      ])
    inverse_polynomial = Polynomial.new(
      @defining_polynomial.ring, terms)
    element_raw(inverse_polynomial.coefficients)

  -> divide(left, right)
    multiply(left, inverse(right))

  -> power(value, exponent)
    exponent_class = exponent.class_name
    integer_exponent = exponent_class == "Integer"
    integer_exponent = integer_exponent || exponent_class == "Int"
    integer_exponent = integer_exponent || exponent_class == "BigInt"
    if !integer_exponent
      raise "simple-extension exponent must be an integer"
    return power(inverse(value), 0 - exponent) if exponent < 0
    result = one
    factor = normalize_element(value)
    remaining = exponent
    while remaining > 0
      result = multiply(result, factor) if remaining.odd?
      remaining = remaining / 2
      factor = multiply(factor, factor) if remaining > 0
    result

  -> power_basis
    out = []
    value = one
    i = 0
    while i < @degree
      out.push(value)
      value = multiply(value, @generator)
      i += 1
    out

  # Matrix of multiplication by value in the power basis, with images stored
  # as columns. This gives trace and norm over the immediate base field for
  # both finite and characteristic-zero extensions.
  -> multiplication_matrix(value)
    rows = []
    i = 0
    while i < @degree
      row = []
      j = 0
      while j < @degree
        row.push(@base_field.zero)
        j += 1
      rows.push(row)
      i += 1

    basis = power_basis
    column = 0
    while column < @degree
      image = multiply(value, basis[column]).coefficients
      row = 0
      while row < @degree
        rows[row][column] = image[row]
        row += 1
      column += 1
    rows

  -> trace(value)
    matrix = multiplication_matrix(value)
    result = @base_field.zero
    i = 0
    while i < @degree
      result = @base_field.add(result, matrix[i][i])
      i += 1
    result

  -> norm(value)
    Algebra.determinant_raw(
      multiplication_matrix(value), @base_field)

  -> negative?(value)
    raise "a simple extension has no canonical ordering"

  -> element_to_s(value)
    coefficients = normalize_element(value).coefficients
    parts = []
    coefficients.each ->
      parts.push(@base_field.element_to_s(item))
    "(" + parts.join(", ") + ")_" + @name.to_s

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

  -> prepare_arithmetic!(table_order_limit = 256)
    if finite_field?
      @base_field.prepare_arithmetic!(table_order_limit)
    self

  -> arithmetic_prepared?
    !finite_field? || @base_field.arithmetic_prepared?

  -> element_from_index(index)
    q = order
    if index < 0 || index >= q
      raise "finite-field element index out of range"
    base_order = @base_field.order
    remaining = index
    coefficients = []
    i = 0
    while i < @degree
      coefficients.push(
        @base_field.element_from_index(remaining % base_order))
      remaining = remaining / base_order
      i += 1
    element_raw(coefficients)

  -> each_element(&)
    value = 0
    while value < order
      &(element_from_index(value))
      value += 1
    self

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

  -> frobenius(value, iterations = 1)
    if !finite_field?
      raise "Frobenius requires a finite simple extension"
    if iterations < 0
      raise "Frobenius iteration count must be nonnegative"
    result = normalize_element(value)
    remaining = iterations % absolute_degree
    while remaining > 0
      result = power(result, characteristic)
      remaining -= 1
    result

  -> inverse_frobenius(value, iterations = 1)
    if !finite_field?
      raise "inverse Frobenius requires a finite simple extension"
    if iterations < 0
      raise "inverse Frobenius iteration count must be nonnegative"
    reduced = iterations % absolute_degree
    frobenius(value, reduced == 0 ? 0 : absolute_degree - reduced)

  -> relative_trace(value)
    if !finite_field?
      raise "relative trace currently requires a finite base field"
    result = zero
    conjugate = normalize_element(value)
    i = 0
    while i < @degree
      result = add(result, conjugate)
      conjugate = power(conjugate, @base_field.order)
      i += 1
    projected = project_to_base(result)
    if !@base_field.equal?(projected, trace(value))
      raise "relative trace disagrees with multiplication matrix"
    projected

  -> relative_norm(value)
    if !finite_field?
      raise "relative norm currently requires a finite base field"
    exponent = (order - 1) / (@base_field.order - 1)
    projected = project_to_base(power(value, exponent))
    if !@base_field.equal?(projected, norm(value))
      raise "relative norm disagrees with multiplication matrix"
    projected

  -> project_to_base(value)
    coefficients = normalize_element(value).coefficients
    i = 1
    while i < coefficients.size
      if !@base_field.zero?(coefficients[i])
        raise "extension invariant did not land in the base field"
      i += 1
    coefficients[0]

  -> ==/1
    other = @1
    return false if other.class_name != "SimpleExtensionField"
    return false if @base_field != other.base_field
    @defining_polynomial.eql?(other.defining_polynomial)

  -> to_s
    @base_field.to_s + "(" + @name.to_s + ")"

  -> inspect
    to_s
