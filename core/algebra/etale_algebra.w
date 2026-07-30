# Certified finite etale quotient algebras K[t]/(f).
#
# Here "finite" means finite-dimensional over K, not finite cardinality.
# Squarefreeness of f is the exact etaleness certificate. A supplied
# factorization f = product f_i need only be into pairwise-coprime squarefree
# components; the f_i are not mislabeled as fields unless irreducibility is
# separately proved. Chinese-remainder idempotents make the product structure
# executable without requiring full factorization into geometric points.

+ EtaleAlgebraElement
  -> new(@algebra, coefficients)
    initialize_etale_element(coefficients, false)

  -> new(@algebra, coefficients, raw)
    initialize_etale_element(coefficients, raw)

  -> .raw(algebra, coefficients)
    EtaleAlgebraElement.new(algebra, coefficients, true)

  -> initialize_etale_element(coefficients, raw)
    @coefficients = @algebra.reduce_coefficients(coefficients, raw)
    self

  -> algebra
    @algebra

  -> coefficients
    out = []
    @coefficients.each -> out.push(item)
    out

  -> polynomial
    @algebra.element_polynomial(self)

  -> zero?
    @algebra.zero?(self)

  -> one?
    @algebra.one?(self)

  -> unit?
    @algebra.unit?(self)

  -> zero_divisor?
    @algebra.zero_divisor?(self)

  -> +(other)
    @algebra.add(self, other)

  -> -(other)
    @algebra.subtract(self, other)

  -> negate
    @algebra.negate(self)

  -> -@
    negate

  -> *(other)
    @algebra.multiply(self, other)

  -> /(other)
    @algebra.divide(self, other)

  -> inverse
    @algebra.inverse(self)

  -> **(exponent)
    @algebra.power(self, exponent)

  -> trace
    @algebra.trace(self)

  -> norm
    @algebra.norm(self)

  -> components
    @algebra.components(self)

  -> ==/1
    self.eql?(@1)

  -> eql?(other)
    right = nil
    if other.class_name == "EtaleAlgebraElement"
      return false if other.algebra != @algebra
      right = other
    else
      value_class = other.class_name
      scalar = value_class == "Integer" || value_class == "Int"
      scalar = scalar || value_class == "BigInt"
      scalar = scalar || value_class == "Rational"
      scalar = scalar || value_class == "NumberFieldElement"
      scalar = scalar || value_class == "SimpleExtensionElement"
      return false if !scalar
      right = @algebra.coerce(other)

    right_coefficients = right.coefficients
    i = 0
    while i < @algebra.dimension
      if !@algebra.base_field.equal?(
          @coefficients[i], right_coefficients[i])
        return false
      i += 1
    true

  -> to_s
    @algebra.element_to_s(self)

  -> inspect
    to_s


+ EtaleAlgebraCertificate
  -> new(@polynomial, components)
    initialize_etale_certificate(components, nil)

  -> new(@polynomial, components, source_certificate)
    initialize_etale_certificate(components, source_certificate)

  -> initialize_etale_certificate(components, @source_certificate)
    @components = []
    components.each -> @components.push(item)
    @verified_cache = nil
    self

  -> polynomial
    @polynomial

  -> components
    out = []
    @components.each -> out.push(item)
    out

  -> source_certificate
    @source_certificate

  -> verified?
    return @verified_cache if @verified_cache != nil
    @verified_cache = verify_fresh
    @verified_cache

  -> verify_fresh
    return false if @polynomial.class_name != "Polynomial"
    return false if @polynomial.ring.arity != 1
    return false if @polynomial.degree <= 0
    return false if !Field.supported?(@polynomial.ring.field)
    return false if !@polynomial.eql?(@polynomial.monic)
    if @source_certificate == nil
      derivative = @polynomial.derivative(0)
      return false if derivative.zero?
      return false if @polynomial.gcd(derivative).degree != 0
    else
      source_name = @source_certificate.class_name
      supported_source = source_name == "BitangentProjectionCertificate"
      supported_source = supported_source || source_name == "BitangentEtaleComponentCertificate"
      return false if !supported_source
      return false if !@source_certificate.verified?
      if source_name == "BitangentEtaleComponentCertificate"
        return false if @components.size != 0
        return @source_certificate.factor.monic.eql?(@polynomial)
      source_polynomial = @source_certificate.eliminant.monic
      return false if !source_polynomial.eql?(@polynomial)
      source_components = @source_certificate.components
      return false if source_components.size != @components.size
      i = 0
      while i < source_components.size
        return false if !source_components[i].factor.monic.eql?(
          @components[i])
        i += 1
    return true if @components.size == 0

    product = @polynomial.ring.one
    i = 0
    while i < @components.size
      component = @components[i]
      return false if component.class_name != "Polynomial"
      return false if component.ring != @polynomial.ring
      return false if component.degree <= 0
      return false if !component.eql?(component.monic)
      if @source_certificate == nil
        return false if component.gcd(component.derivative(0)).degree != 0
        j = 0
        while j < i
          return false if component.gcd(@components[j]).degree != 0
          j += 1
      product = product * component
      i += 1
    product.eql?(@polynomial)

  -> certified?
    verified?

  -> to_s
    "EtaleAlgebraCertificate(degree " + @polynomial.degree.to_s + ")"

  -> inspect
    to_s


+ EtaleAlgebraDecompositionCertificate
  -> new(@algebra)
    @verified_cache = nil

  -> algebra
    @algebra

  -> verified?
    return @verified_cache if @verified_cache != nil
    @verified_cache = verify_fresh
    @verified_cache

  -> verify_fresh
    return false if @algebra.class_name != "EtaleAlgebra"
    return false if !@algebra.certificate.verified?
    factors = @algebra.component_polynomials
    return false if factors.size == 0
    idempotents = @algebra.primitive_idempotents
    return false if idempotents.size != factors.size
    sum = @algebra.zero
    i = 0
    while i < idempotents.size
      e = idempotents[i]
      return false if !(e * e).eql?(e)
      sum = sum + e
      j = 0
      while j < i
        return false if !(e * idempotents[j]).zero?
        j += 1
      images = @algebra.components(e)
      j = 0
      while j < images.size
        if j == i
          return false if !images[j].one?
        else
          return false if !images[j].zero?
        j += 1
      i += 1
    sum.one?

  -> certified?
    verified?

  -> to_s
    label = "EtaleAlgebraDecompositionCertificate("
    label + @algebra.component_count.to_s + " components)"

  -> inspect
    to_s


+ EtaleAlgebra
  -> new(polynomial)
    initialize_etale_algebra(polynomial, [], nil)

  -> new(polynomial, components)
    initialize_etale_algebra(polynomial, components, nil)

  -> new(polynomial, components, source_certificate)
    initialize_etale_algebra(
      polynomial, components, source_certificate)

  -> initialize_etale_algebra(polynomial, components, source_certificate)
    if polynomial.class_name != "Polynomial"
      raise "etale algebra modulus must be a Polynomial"
    if polynomial.ring.arity != 1 || polynomial.degree <= 0
      raise "etale algebra needs a nonconstant univariate modulus"
    @base_field = Field.require_supported(polynomial.ring.field)
    @defining_polynomial = polynomial.monic
    @dimension = @defining_polynomial.degree
    @component_polynomials = []
    components.each -> @component_polynomials.push(item.monic)
    @source_certificate = source_certificate
    @certificate_cache = EtaleAlgebraCertificate.new(
      @defining_polynomial, @component_polynomials,
      source_certificate)
    if !@certificate_cache.verified?
      raise "etale algebra modulus/decomposition failed certification"

    coefficients = @defining_polynomial.coefficients
    @relation = []
    i = 0
    while i < @dimension
      @relation.push(coefficients[i])
      i += 1
    generator_coefficients = base_zero_coefficients
    generator_coefficients[1] = @base_field.one if @dimension > 1
    if @dimension == 1
      generator_coefficients[0] = @base_field.negate(@relation[0])
    @generator = EtaleAlgebraElement.raw(
      self, generator_coefficients)
    @component_algebras_cache = nil
    @idempotents_cache = nil
    @decomposition_certificate_cache = nil
    self

  -> base_field
    @base_field

  -> defining_polynomial
    @defining_polynomial

  -> dimension
    @dimension

  -> degree
    @dimension

  -> generator
    @generator

  -> component_polynomials
    out = []
    @component_polynomials.each -> out.push(item)
    out

  -> component_degrees
    out = []
    @component_polynomials.each -> out.push(item.degree)
    out

  -> component_count
    @component_polynomials.size

  -> decomposed?
    component_count > 0

  -> certificate
    @certificate_cache

  -> decomposition_certificate
    if !decomposed?
      raise "etale algebra has no supplied component decomposition"
    if @decomposition_certificate_cache == nil
      @decomposition_certificate_cache = EtaleAlgebraDecompositionCertificate.new(self)
    @decomposition_certificate_cache

  -> certified?
    certificate.verified?

  -> base_zero_coefficients
    out = []
    i = 0
    while i < @dimension
      out.push(@base_field.zero)
      i += 1
    out

  -> reduce_coefficients(coefficients, raw = false)
    if coefficients.class_name != "Array"
      raise "etale-algebra coefficients must be an Array"
    values = []
    coefficients.each ->
      value = raw ? @base_field.normalize_element(item) : @base_field.coerce(item)
      values.push(value)
    while values.size < @dimension
      values.push(@base_field.zero)
    i = values.size - 1
    while i >= @dimension
      leading = values[i]
      if !@base_field.zero?(leading)
        shift = i - @dimension
        j = 0
        while j < @dimension
          correction = @base_field.multiply(
            leading, @relation[j])
          values[shift + j] = @base_field.subtract(
            values[shift + j], correction)
          j += 1
      values[i] = @base_field.zero
      i -= 1
    out = []
    i = 0
    while i < @dimension
      out.push(values[i])
      i += 1
    out

  -> element_raw(coefficients)
    EtaleAlgebraElement.raw(self, coefficients)

  -> from_polynomial(polynomial)
    if polynomial.class_name != "Polynomial"
      raise "etale quotient needs a Polynomial"
    if polynomial.ring != @defining_polynomial.ring
      raise "etale quotient polynomial belongs to a different ring"
    element_raw(polynomial.rem(@defining_polynomial).coefficients)

  -> coerce(value)
    if value.class_name == "EtaleAlgebraElement"
      if value.algebra != self
        raise "etale-algebra elements belong to different algebras"
      return value
    if value.class_name == "Polynomial"
      return from_polynomial(value)
    if value.class_name == "Array"
      return EtaleAlgebraElement.new(self, value)
    embed_base_element(@base_field.coerce(value))

  -> normalize_element(value)
    if value.class_name == "EtaleAlgebraElement" && value.algebra == self
      return value
    coerce(value)

  -> embed_base_element(value)
    coefficients = base_zero_coefficients
    coefficients[0] = @base_field.normalize_element(value)
    element_raw(coefficients)

  -> zero
    element_raw(base_zero_coefficients)

  -> one
    coefficients = base_zero_coefficients
    coefficients[0] = @base_field.one
    element_raw(coefficients)

  -> zero?(value)
    coefficients = normalize_element(value).coefficients
    i = 0
    while i < @dimension
      return false if !@base_field.zero?(coefficients[i])
      i += 1
    true

  -> one?(value)
    coefficients = normalize_element(value).coefficients
    return false if !@base_field.one?(coefficients[0])
    i = 1
    while i < @dimension
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
    while i < @dimension
      out.push(@base_field.add(a[i], b[i]))
      i += 1
    element_raw(out)

  -> negate(value)
    out = []
    normalize_element(value).coefficients.each ->
      out.push(@base_field.negate(item))
    element_raw(out)

  -> subtract(left, right)
    add(left, negate(right))

  -> multiply(left, right)
    a = normalize_element(left).coefficients
    b = normalize_element(right).coefficients
    product = []
    i = 0
    while i < @dimension * 2 - 1
      product.push(@base_field.zero)
      i += 1
    i = 0
    while i < @dimension
      j = 0
      while j < @dimension
        product[i + j] = @base_field.add(
          product[i + j],
          @base_field.multiply(a[i], b[j]))
        j += 1
      i += 1
    element_raw(product)

  -> element_polynomial(value)
    coefficients = normalize_element(value).coefficients
    terms = []
    i = 0
    while i < coefficients.size
      if !@base_field.zero?(coefficients[i])
        terms.push([coefficients[i], [i]])
      i += 1
    Polynomial.new(@defining_polynomial.ring, terms)

  -> unit?(value)
    element = normalize_element(value)
    return false if zero?(element)
    element_polynomial(element).gcd(
      @defining_polynomial).degree == 0

  -> zero_divisor?(value)
    element = normalize_element(value)
    !zero?(element) && !unit?(element)

  -> inverse(value)
    element = normalize_element(value)
    raise "zero is not a unit in an etale algebra" if zero?(element)
    polynomial = element_polynomial(element)
    bezout = polynomial.xgcd(@defining_polynomial)
    gcd = bezout[0]
    if gcd.degree != 0 || @base_field.zero?(gcd.coeff(0))
      raise "etale-algebra element is a zero divisor, not a unit"
    scale = @base_field.inverse(gcd.coeff(0))
    terms = []
    bezout[1].each_term -> (coefficient, exponents)
      terms.push([
        @base_field.multiply(coefficient, scale),
        exponents
      ])
    from_polynomial(Polynomial.new(
      @defining_polynomial.ring, terms))

  -> divide(left, right)
    multiply(left, inverse(right))

  -> power(value, exponent)
    exponent_class = exponent.class_name
    integer_exponent = exponent_class == "Integer"
    integer_exponent = integer_exponent || exponent_class == "Int"
    integer_exponent = integer_exponent || exponent_class == "BigInt"
    raise "etale-algebra exponent must be an integer" if !integer_exponent
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
    while i < @dimension
      out.push(value)
      value = multiply(value, @generator)
      i += 1
    out

  -> multiplication_matrix(value)
    rows = []
    i = 0
    while i < @dimension
      row = []
      j = 0
      while j < @dimension
        row.push(@base_field.zero)
        j += 1
      rows.push(row)
      i += 1
    basis = power_basis
    column = 0
    while column < @dimension
      image = multiply(value, basis[column]).coefficients
      row = 0
      while row < @dimension
        rows[row][column] = image[row]
        row += 1
      column += 1
    rows

  -> trace(value)
    matrix = multiplication_matrix(value)
    result = @base_field.zero
    i = 0
    while i < @dimension
      result = @base_field.add(result, matrix[i][i])
      i += 1
    result

  -> norm(value)
    Algebra.determinant_raw(
      multiplication_matrix(value), @base_field)

  -> component_algebras
    if !decomposed?
      raise "etale algebra has no supplied component decomposition"
    if @component_algebras_cache == nil
      @component_algebras_cache = []
      source_components = []
      if @source_certificate != nil
        if @source_certificate.class_name == "BitangentProjectionCertificate"
          source_components = @source_certificate.components
      i = 0
      while i < @component_polynomials.size
        if source_components.size == @component_polynomials.size
          @component_algebras_cache.push(EtaleAlgebra.new(
            @component_polynomials[i], [], source_components[i]))
        else
          @component_algebras_cache.push(
            EtaleAlgebra.new(@component_polynomials[i]))
        i += 1
    out = []
    @component_algebras_cache.each -> out.push(item)
    out

  -> components(value)
    element = normalize_element(value)
    polynomial = element_polynomial(element)
    out = []
    component_algebras.each ->
      out.push(item.from_polynomial(polynomial))
    out

  -> primitive_idempotents
    if !decomposed?
      raise "etale algebra has no supplied component decomposition"
    if @idempotents_cache == nil
      @idempotents_cache = []
      @component_polynomials.each -> (factor)
        complementary = @defining_polynomial / factor
        bezout = complementary.xgcd(factor)
        gcd = bezout[0]
        if gcd.degree != 0 || @base_field.zero?(gcd.coeff(0))
          raise "etale component factors are not coprime"
        scale = @base_field.inverse(gcd.coeff(0))
        inverse_terms = []
        bezout[1].each_term -> (coefficient, exponents)
          inverse_terms.push([
            @base_field.multiply(coefficient, scale),
            exponents
          ])
        inverse_mod_factor = Polynomial.new(
          @defining_polynomial.ring, inverse_terms)
        @idempotents_cache.push(
          from_polynomial(complementary * inverse_mod_factor))
    out = []
    @idempotents_cache.each -> out.push(item)
    out

  -> from_components(values)
    algebras = component_algebras
    if values.class_name != "Array" || values.size != algebras.size
      raise "wrong etale component count"
    idempotents = primitive_idempotents
    result = zero
    i = 0
    while i < algebras.size
      component = algebras[i].coerce(values[i])
      lifted = from_polynomial(component.polynomial)
      result = result + idempotents[i] * lifted
      i += 1
    result

  -> element_to_s(value)
    coefficients = normalize_element(value).coefficients
    parts = []
    coefficients.each ->
      parts.push(@base_field.element_to_s(item))
    text = "(" + parts.join(", ") + ") mod ("
    text + @defining_polynomial.to_s + ")"

  -> ==/1
    other = @1
    return false if other.class_name != "EtaleAlgebra"
    return false if @base_field != other.base_field
    return false if !@defining_polynomial.eql?(other.defining_polynomial)
    component_degrees.to_s == other.component_degrees.to_s

  -> to_s
    text = "EtaleAlgebra(" + @base_field.to_s
    text + ", degree " + @dimension.to_s + ")"

  -> inspect
    to_s
