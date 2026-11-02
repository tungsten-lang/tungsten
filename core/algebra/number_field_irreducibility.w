# Modular, relative, tower, and isomorphic-model irreducibility certificates for number fields.

use algebra/finite_field
use algebra/polynomial
use algebra/polynomial_factor

+ NumberFieldModularIrreducibilityCertificate
  -> new(@polynomial, @prime)

  ro :polynomial, :prime

  -> reduced_polynomial
    if @polynomial.class_name != "Polynomial"
      raise "modular irreducibility needs a polynomial"
    finite_field = FiniteField.new(@prime)
    finite_ring = PolynomialRing.new(
      @polynomial.ring.names, finite_field)
    terms = []
    @polynomial.each_term -> (coefficient, exponents)
      reduced = finite_field.embed_from(
        @polynomial.ring.field, coefficient)
      terms.push([reduced, exponents])
    Polynomial.new(finite_ring, terms)

  -> verified?
    answer = false
    begin
      answer = verify!
    rescue error
      answer = false
    answer

  -> verify!
    return false if @polynomial.class_name != "Polynomial"
    return false if @polynomial.ring.arity != 1
    return false if @polynomial.degree < 2
    return false if @polynomial.ring.field.class_name != "RationalField"
    return false if !@prime.prime?
    reduction = reduced_polynomial
    return false if reduction.degree != @polynomial.degree
    reduction.finite_field_irreducible?

  -> certified?
    verified?

  -> proof_kind
    :modular_rabin

  -> kernel_checked?
    true

  -> to_s
    "irreducible modulo " + @prime.to_s

  -> inspect
    to_s


+ NumberFieldModularDegreeIrreducibilityCertificate
  -> new(@polynomial, primes,
         @factor_search_limit = 250_000)
    @primes = []
    @factorizations = []
    primes.each -> (prime)
      @primes.push(prime)
      helper = NumberFieldModularDegreeIrreducibilityCertificate
      factorization = helper.factorization_at(
        @polynomial, prime, @factor_search_limit)
      @factorizations.push(factorization)

  -> new(@polynomial, primes, factorizations,
         @factor_search_limit)
    @primes = []
    primes.each -> (prime)
      @primes.push(prime)
    @factorizations = []
    factorizations.each -> (factorization)
      @factorizations.push(factorization)

  ro :polynomial

  -> primes
    out = []
    @primes.each -> (prime)
      out.push(prime)
    out

  -> factorizations
    out = []
    @factorizations.each -> (factorization)
      out.push(factorization)
    out

  -> factor_degree_patterns
    out = []
    @factorizations.each -> (factorization)
      degrees = []
      factorization.factors.each -> (factor)
        degrees.push(factor.degree) if factor.degree > 0
      out.push(degrees)
    out

  -> .reduction_at(polynomial, prime)
    integral = NumberField.primitive_integral_polynomial(
      polynomial)
    finite_field = FiniteField.new(prime)
    finite_ring = PolynomialRing.new(
      integral.ring.names, finite_field)
    terms = []
    integral.each_term -> (coefficient, exponents)
      terms.push([
        finite_field.coerce(coefficient.numerator),
        exponents
      ])
    Polynomial.new(finite_ring, terms)

  -> .factorization_at(
       polynomial, prime,
       factor_search_limit = 250_000)
    helper = NumberFieldModularDegreeIrreducibilityCertificate
    reduction = helper.reduction_at(polynomial, prime)
    reduction.factor_with_certificate(
      factor_search_limit)

  -> candidate_degrees(factorization)
    degree = @polynomial.degree
    possible = []
    (degree + 1).times -> possible.push(false)
    possible[0] = true
    factorization.factors.each -> (factor)
      factor_degree = factor.degree
      if factor_degree > 0
        current = degree - factor_degree
        while current >= 0
          if possible[current]
            possible[current + factor_degree] = true
          current -= 1
    out = []
    candidate = 1
    while candidate * 2 <= degree
      out.push(candidate) if possible[candidate]
      candidate += 1
    out

  -> remaining_degrees
    remaining = []
    candidate = 1
    while candidate * 2 <= @polynomial.degree
      remaining.push(candidate)
      candidate += 1
    @factorizations.each -> (factorization)
      local = candidate_degrees(factorization)
      kept = []
      remaining.each -> (degree)
        kept.push(degree) if local.include?(degree)
      remaining = kept
    remaining

  -> verified?
    answer = false
    begin
      answer = verify!
    rescue error
      answer = false
    answer

  -> verify!
    return false if @polynomial.class_name != "Polynomial"
    return false if @polynomial.ring.arity != 1
    return false if @polynomial.degree < 2
    return false if @polynomial.ring.field.class_name != "RationalField"
    return false if @primes.size == 0
    return false if @primes.size != @factorizations.size
    i = 0
    while i < @primes.size
      return false if !@primes[i].prime?
      j = 0
      while j < i
        return false if @primes[j] == @primes[i]
        j += 1
      helper = NumberFieldModularDegreeIrreducibilityCertificate
      reduction = helper.reduction_at(
        @polynomial, @primes[i])
      return false if reduction.degree != @polynomial.degree
      factorization = @factorizations[i]
      expected_factorization_class = "PolynomialFactorization"
      return false if factorization.class_name != expected_factorization_class
      return false if !factorization.polynomial.eql?(reduction)
      return false if !factorization.certificate.verified?
      i += 1
    remaining_degrees.size == 0

  -> certified?
    verified?

  -> proof_kind
    :modular_factor_degree_exclusion

  -> kernel_checked?
    true

  -> to_s
    text = "modular factor-degree irreducibility at "
    text + @primes.to_s

  -> inspect
    to_s


+ NumberFieldRelativeModularIrreducibilityCertificate
  -> new(@polynomial, @prime_ideal)
    @reduced_polynomial_cache = nil
    @verified_cache = nil

  ro :polynomial, :prime_ideal

  -> reduced_polynomial
    if @reduced_polynomial_cache == nil
      field = @polynomial.ring.field
      finite_field = @prime_ideal.residue_field
      finite_ring = PolynomialRing.new(
        @polynomial.ring.names, finite_field)
      terms = []
      @polynomial.each_term -> (coefficient, exponents)
        terms.push([
          @prime_ideal.reduce(field.coerce(coefficient)),
          exponents
        ])
      @reduced_polynomial_cache = Polynomial.new(
        finite_ring, terms)
    @reduced_polynomial_cache

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
    return false if @polynomial.class_name != "Polynomial"
    return false if @polynomial.ring.arity != 1
    return false if @polynomial.degree < 2
    field = @polynomial.ring.field
    return false if field.class_name != "NumberField"
    return false if @prime_ideal.class_name != "NumberFieldPrimeIdeal"
    return false if @prime_ideal.field != field
    return false if !@prime_ideal.certificate.verified?
    return false if !@polynomial.eql?(@polynomial.monic)
    coefficients = @polynomial.coefficients
    i = 0
    while i < coefficients.size
      return false if !field.coerce(coefficients[i]).integral?
      i += 1
    reduction = reduced_polynomial
    return false if reduction.degree != @polynomial.degree
    reduction.finite_field_irreducible?

  -> certified?
    verified?

  -> proof_kind
    :relative_modular_rabin

  -> kernel_checked?
    true

  -> to_s
    text = "relative irreducibility modulo "
    text + @prime_ideal.to_s

  -> inspect
    to_s


# An exact degree-one residue map from a power-basis number field to F_p.
# The defining polynomial must have a simple root at `root`; squarefreeness of
# the full reduction makes the power order etale at p. Rational denominators
# are accepted exactly when they are units modulo p.
+ NumberFieldPowerBasisPrimeReductionCertificate
  -> new(@reduction)
    @verified_cache = nil

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
    expected = "NumberFieldPowerBasisPrimeReduction"
    return false if @reduction.class_name != expected
    field = @reduction.field
    return false if field.class_name != "NumberField"
    prime = @reduction.prime
    return false if !prime.prime?
    root = @reduction.root
    return false if root < 0 || root >= prime
    polynomial = @reduction.reduced_defining_polynomial
    return false if polynomial.degree != field.degree
    return false if !polynomial.at(root).zero?
    polynomial.gcd(polynomial.derivative(0)).degree == 0

  -> certified?
    verified?

  -> proof_kind
    :exact_unramified_power_basis_residue_map

  -> kernel_checked?
    true


+ NumberFieldPowerBasisPrimeReduction
  -> new(@field, @prime, root)
    if @field.class_name != "NumberField"
      raise "power-basis reduction needs a NumberField"
    if !@prime.prime?
      raise "power-basis reduction needs a rational prime"
    @finite_field = FiniteField.new(@prime)
    @root = @finite_field.coerce(root)
    @certificate_cache = NumberFieldPowerBasisPrimeReductionCertificate.new(
      self)
    if !@certificate_cache.verified?
      raise "power-basis prime reduction failed certification"

  ro :field, :prime, :root

  -> residue_field
    @finite_field

  -> reduce_rational(value)
    rational = value.class_name == "Rational" ? value : Rational.new(value)
    if rational.denominator % @prime == 0
      raise "coefficient is not integral at the selected prime"
    numerator = @finite_field.coerce(rational.numerator)
    denominator = @finite_field.coerce(rational.denominator)
    @finite_field.divide(numerator, denominator)

  -> reduce(value)
    coefficients = @field.coerce(value).coefficients
    answer = @finite_field.zero
    power = @finite_field.one
    i = 0
    while i < coefficients.size
      scalar = reduce_rational(coefficients[i])
      answer = @finite_field.add(
        answer, @finite_field.multiply(scalar, power))
      power = @finite_field.multiply(power, @root)
      i += 1
    answer

  -> reduced_defining_polynomial
    source = @field.defining_polynomial
    ring = PolynomialRing.new(
      source.ring.names, @finite_field, :lex)
    terms = []
    source.each_term -> (coefficient, exponents)
      terms.push([reduce_rational(coefficient), exponents])
    Polynomial.new(ring, terms)

  -> reduce_polynomial(polynomial)
    if polynomial.class_name != "Polynomial"
      raise "relative reduction needs a Polynomial"
    if polynomial.ring.arity != 1
      raise "relative reduction needs a univariate polynomial"
    if polynomial.ring.field != @field
      raise "relative polynomial belongs to a different number field"
    ring = PolynomialRing.new(
      polynomial.ring.names, @finite_field, :lex)
    terms = []
    polynomial.each_term -> (coefficient, exponents)
      terms.push([reduce(coefficient), exponents])
    Polynomial.new(ring, terms)

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?


# A monic relative polynomial is irreducible when good residue
# factorizations leave no possible degree for a proper characteristic-zero
# factor. For example, a sextic with patterns 2+2+2 and 3+3 has no common
# proper subset degree.
+ NumberFieldRelativeModularDegreeIrreducibilityCertificate
  -> new(@polynomial, reductions,
         @factor_search_limit = 250_000)
    @reductions = []
    @factorizations = []
    reductions.each -> (reduction)
      @reductions.push(reduction)
      reduced = reduction.reduce_polynomial(@polynomial)
      @factorizations.push(
        reduced.factor_with_certificate(
          @factor_search_limit))
    @verified_cache = nil

  ro :polynomial

  -> reductions
    out = []
    @reductions.each -> out.push(item)
    out

  -> factorizations
    out = []
    @factorizations.each -> out.push(item)
    out

  -> factor_degree_patterns
    out = []
    @factorizations.each -> (factorization)
      degrees = []
      factorization.factors.each -> (factor)
        degrees.push(factor.degree) if factor.degree > 0
      helper = NumberFieldRelativeModularDegreeIrreducibilityCertificate
      out.push(helper.sort_integers(degrees))
    out

  -> .sort_integers(values)
    out = []
    values.each -> out.push(item)
    i = 1
    while i < out.size
      value = out[i]
      position = i
      while position > 0 && out[position - 1] > value
        out[position] = out[position - 1]
        position -= 1
      out[position] = value
      i += 1
    out

  -> candidate_degrees(factorization)
    degree = @polynomial.degree
    possible = []
    (degree + 1).times -> possible.push(false)
    possible[0] = true
    factorization.factors.each -> (factor)
      factor_degree = factor.degree
      if factor_degree > 0
        current = degree - factor_degree
        while current >= 0
          if possible[current]
            possible[current + factor_degree] = true
          current -= 1
    out = []
    candidate = 1
    while candidate * 2 <= degree
      out.push(candidate) if possible[candidate]
      candidate += 1
    out

  -> remaining_degrees
    remaining = []
    candidate = 1
    while candidate * 2 <= @polynomial.degree
      remaining.push(candidate)
      candidate += 1
    @factorizations.each -> (factorization)
      local = candidate_degrees(factorization)
      kept = []
      remaining.each -> (degree)
        kept.push(degree) if local.include?(degree)
      remaining = kept
    remaining

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
    return false if @polynomial.class_name != "Polynomial"
    return false if @polynomial.ring.arity != 1
    return false if @polynomial.degree < 2
    field = @polynomial.ring.field
    return false if field.class_name != "NumberField"
    return false if !@polynomial.eql?(@polynomial.monic)
    return false if @reductions.size == 0
    return false if @reductions.size != @factorizations.size
    i = 0
    while i < @reductions.size
      reduction = @reductions[i]
      return false if reduction.field != field
      return false if !reduction.certificate.verified?
      reduced = reduction.reduce_polynomial(@polynomial)
      return false if reduced.degree != @polynomial.degree
      factorization = @factorizations[i]
      return false if !factorization.polynomial.eql?(reduced)
      return false if !factorization.certificate.verified?
      i += 1
    remaining_degrees.size == 0

  -> certified?
    verified?

  -> proof_kind
    :relative_modular_factor_degree_exclusion

  -> kernel_checked?
    true

  -> to_s
    "relative modular degree exclusion " + factor_degree_patterns.to_s

  -> inspect
    to_s


+ NumberFieldTowerIrreducibilityCertificate
  -> new(@polynomial, @relative_polynomial,
         @relative_certificate)
    @extension_cache = nil
    @primitive_element_determinant_cache = nil
    @verified_cache = nil

  ro :polynomial, :relative_polynomial, :relative_certificate

  -> base_field
    @relative_polynomial.ring.field

  -> extension
    if @extension_cache == nil
      @extension_cache = SimpleExtensionField.new(
        @relative_polynomial, :z, 250_000,
        @relative_certificate)
    @extension_cache

  -> evaluate_over_extension(polynomial, value)
    result = extension.zero
    power = extension.one
    i = 0
    while i <= polynomial.degree
      coefficient = polynomial.coeff(i)
      if coefficient != Rational.new(0)
        term = extension.multiply(
          extension.coerce(coefficient), power)
        result = extension.add(result, term)
      power = extension.multiply(power, value)
      i += 1
    result

  -> absolute_coordinates(value)
    out = []
    extension.normalize_element(value).coefficients.each -> (coefficient)
      base = base_field.coerce(coefficient)
      base.coefficients.each -> (entry)
        out.push(entry)
    out

  -> power_coordinate_columns(value)
    columns = []
    power = extension.one
    expected = base_field.degree * extension.degree
    i = 0
    while i < expected
      columns.push(absolute_coordinates(power))
      power = extension.multiply(power, value)
      i += 1
    columns

  -> primitive_element_determinant
    if @primitive_element_determinant_cache == nil
      matrix = ExactRationalLinearAlgebra.matrix_from_columns(
        power_coordinate_columns(extension.generator))
      @primitive_element_determinant_cache = Algebra.determinant(
        matrix, RationalField.new)
    @primitive_element_determinant_cache

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
    return false if @polynomial.class_name != "Polynomial"
    return false if @polynomial.ring.arity != 1
    return false if @polynomial.ring.field.class_name != "RationalField"
    return false if @relative_polynomial.class_name != "Polynomial"
    return false if base_field.class_name != "NumberField"
    return false if !base_field.irreducibility_certified?
    expected = "NumberFieldRelativeModularIrreducibilityCertificate"
    return false if @relative_certificate.class_name != expected
    return false if !@relative_certificate.verified?
    return false if !@relative_certificate.polynomial.eql?(
      @relative_polynomial)
    absolute_degree = base_field.degree * @relative_polynomial.degree
    return false if @polynomial.degree != absolute_degree
    return false if extension.modulus_certificate != @relative_certificate
    value = evaluate_over_extension(
      @polynomial, extension.generator)
    return false if !extension.zero?(value)
    !primitive_element_determinant.zero?

  -> certified?
    verified?

  -> proof_kind
    :relative_modular_tower

  -> kernel_checked?
    true

  -> to_s
    text = "tower irreducibility of degree "
    text + @polynomial.degree.to_s

  -> inspect
    to_s


+ NumberFieldIsomorphicModelIrreducibilityCertificate
  -> new(@polynomial, @model_polynomial,
         @root_expression, @model_certificate)
    @model_field_cache = nil
    @root_cache = nil
    @verified_cache = nil

  ro :polynomial, :model_polynomial, :root_expression, :model_certificate

  -> model_field
    if @model_field_cache == nil
      @model_field_cache = NumberField.new(
        @model_polynomial, :b,
        @model_certificate)
    @model_field_cache

  -> model_root
    if @root_cache == nil
      value = model_field.zero
      power = model_field.one
      i = 0
      while i <= @root_expression.degree
        coefficient = @root_expression.coeff(i)
        value += power * coefficient if coefficient != Rational.new(0)
        power *= model_field.generator
        i += 1
      @root_cache = value
    @root_cache

  -> same_coefficients?(left, right)
    return false if left.degree != right.degree
    i = 0
    while i <= left.degree
      return false if left.coeff(i) != right.coeff(i)
      i += 1
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
    return false if @polynomial.class_name != "Polynomial"
    return false if @polynomial.ring.arity != 1
    return false if @polynomial.ring.field.class_name != "RationalField"
    return false if @model_polynomial.class_name != "Polynomial"
    return false if @model_polynomial.ring.arity != 1
    return false if @model_polynomial.ring.field.class_name != "RationalField"
    return false if @root_expression.class_name != "Polynomial"
    return false if @root_expression.ring.arity != 1
    return false if @root_expression.ring.field.class_name != "RationalField"
    return false if !NumberField.valid_irreducibility_certificate?(
      @model_polynomial, @model_certificate)
    return false if model_field.evaluate(
      @polynomial, model_root) != model_field.zero
    minimum = model_field.minimal_polynomial(model_root)
    minimum_certificate = NumberFieldMinimalPolynomialCertificate.new(
      model_field, model_root, minimum)
    return false if !minimum_certificate.verified?
    same_coefficients?(
      @polynomial.monic, minimum.monic)

  -> certified?
    verified?

  -> proof_kind
    :isomorphic_irreducible_model

  -> kernel_checked?
    true

  -> to_s
    text = "irreducible via degree-"
    text + @model_polynomial.degree.to_s + " isomorphic model"

  -> inspect
    to_s


