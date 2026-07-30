# Exact number fields.
#
# A NumberField is Q[a]/(f), where f is a certified irreducible univariate
# polynomial. Field elements use the power basis 1, a, ..., a^(n-1) with
# Rational coefficients. Arithmetic, signatures, and power-order
# discriminants work in every degree. Degree-generic maximal orders use the
# certified Round 2 implementation in maximal_orders.w. The older cubic
# lattice search below remains as an independent regression oracle. If O is the
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
    right_coefficients = right.coefficients
    i = 0
    while i < @field.degree
      return false if @coefficients[i] != right_coefficients[i]
      i += 1
    true

  -> to_s
    @field.element_to_s(self)

  -> inspect
    to_s

  -> trace
    @field.trace(self)

  -> norm
    @field.norm(self)

  -> minimal_polynomial
    @field.minimal_polynomial(self)

  -> minimal_polynomial_certificate
    @field.minimal_polynomial_certificate(self)

  -> characteristic_polynomial
    @field.characteristic_polynomial(self)

  -> algebraic_degree
    minimal_polynomial.degree

  -> integral?
    @field.integral_element?(self)


+ NumberFieldMinimalPolynomialCertificate
  -> new(@field, element, @polynomial)
    @element = @field.coerce(element)

  -> field
    @field

  -> element
    @field.coerce(@element)

  -> polynomial
    @polynomial

  # Replay both halves of minimality: the displayed monic polynomial
  # annihilates the element, and no shorter Krylov prefix is dependent.
  -> verified?
    return false if @field.class_name != "NumberField"
    return false if @polynomial.class_name != "Polynomial"
    return false if @polynomial.ring.arity != 1
    return false if @polynomial.ring.field.class_name != "RationalField"
    return false if @polynomial.degree < 1 || @polynomial.degree > @field.degree
    return false if !@polynomial.eql?(@polynomial.monic)
    return false if !@field.evaluate(@polynomial, @element).zero?
    degree = 1
    while degree < @polynomial.degree
      return false if @field.power_relation(@element, degree) != nil
      degree += 1
    relation = @field.power_relation(@element, @polynomial.degree)
    return false if relation == nil
    expected = @field.polynomial_from_power_relation(
      relation, @polynomial.degree)
    expected.eql?(@polynomial)

  -> certified?
    verified?

  -> to_s
    "NumberFieldMinimalPolynomialCertificate(" + @polynomial.to_s + ")"

  -> inspect
    to_s


+ NumberFieldRealEmbedding
  -> new(@field, root)
    @root = root.refined(0)
    if !verified?
      raise "invalid certified real embedding of a number field"

  -> field
    @field

  -> root
    @root.refined(0)

  -> verified?
    return false if @field.class_name != "NumberField"
    return false if @root.class_name != "AlgebraicRealRoot"
    return false if !@root.certificate.verified?
    @root.defining_polynomial.eql?(@field.defining_polynomial)

  -> certified?
    verified?

  # Evaluate a power-basis element at the selected certified real root.
  # AlgebraicRealArithmetic keeps every intermediate image exact.
  -> image(value)
    element = @field.coerce(value)
    return @root.refined(0) if element.eql?(@field.generator)
    coefficients = element.coefficients
    result = coefficients[coefficients.size - 1]
    i = coefficients.size - 2
    while i >= 0
      result = AlgebraicRealArithmetic.compute(
        result, @root, "*").value
      result = AlgebraicRealArithmetic.compute(
        result, coefficients[i], "+").value
      i -= 1
    result

  # Determine only the sign without constructing the exact algebraic image.
  # Interval Horner evaluation is refined around the certified root until the
  # image interval avoids zero. An irreducible defining polynomial and a
  # nonzero power-basis element cannot share that root.
  -> sign(value)
    element = @field.coerce(value)
    return 0 if element.zero?
    coefficients = element.coefficients
    defining = @root.defining_polynomial
    sequence = defining.sturm_sequence
    lower = @root.lower_bound
    upper = @root.upper_bound
    refinements = 0
    while refinements < 10_000
      interval = polynomial_interval(
        coefficients, lower, upper)
      return -1 if interval[1] < 0
      return 1 if interval[0] > 0
      middle = (lower + upper) / Rational.new(2)
      if defining.at(middle).zero?
        exact = evaluate_coefficients(
          coefficients, middle)
        return 0 if exact.zero?
        return exact.negative? ? -1 : 1
      left_count = defining.sturm_root_count_with_sequence(
        sequence, lower, middle)
      if left_count == 1
        upper = middle
      else
        lower = middle
      refinements += 1
    raise "could not determine exact number-field embedding sign"

  -> evaluate_coefficients(coefficients, value)
    result = Rational.new(0)
    i = coefficients.size - 1
    while i >= 0
      result = result * value + coefficients[i]
      i -= 1
    result

  -> polynomial_interval(coefficients, lower, upper)
    result_lower = Rational.new(0)
    result_upper = Rational.new(0)
    i = coefficients.size - 1
    while i >= 0
      products = [
        result_lower * lower,
        result_lower * upper,
        result_upper * lower,
        result_upper * upper
      ]
      product_lower = products[0]
      product_upper = products[0]
      products.each -> (product)
        product_lower = product if product < product_lower
        product_upper = product if product > product_upper
      result_lower = product_lower + coefficients[i]
      result_upper = product_upper + coefficients[i]
      i -= 1
    [result_lower, result_upper]

  -> call(value)
    image(value)

  -> to_s
    "RealEmbedding(" + @field.to_s + ", root " + @root.root_index.to_s + ")"

  -> inspect
    to_s


+ NumberFieldModularIrreducibilityCertificate
  -> new(@polynomial, @prime)

  -> polynomial
    @polynomial

  -> prime
    @prime

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

  -> polynomial
    @polynomial

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

  -> polynomial
    @polynomial

  -> prime_ideal
    @prime_ideal

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


+ NumberFieldTowerIrreducibilityCertificate
  -> new(@polynomial, @relative_polynomial,
         @relative_certificate)
    @extension_cache = nil
    @primitive_element_determinant_cache = nil
    @verified_cache = nil

  -> polynomial
    @polynomial

  -> relative_polynomial
    @relative_polynomial

  -> relative_certificate
    @relative_certificate

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

  -> polynomial
    @polynomial

  -> model_polynomial
    @model_polynomial

  -> root_expression
    @root_expression

  -> model_certificate
    @model_certificate

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


+ NumberField < Field
  -> new(polynomial)
    initialize_number_field(
      polynomial, :a, 1_000_000, 250_000)

  -> new(polynomial, name)
    initialize_number_field(
      polynomial, name, 1_000_000, 250_000)

  -> new(polynomial, name, irreducibility_certificate)
    initialize_number_field(
      polynomial, name, 1_000_000, 250_000,
      irreducibility_certificate)

  -> initialize_number_field(
       polynomial, name, irreducibility_limit,
       order_limit, supplied_certificate = nil)
    if polynomial.class_name != "Polynomial"
      raise "NumberField defining polynomial must be a Polynomial"
    if polynomial.ring.arity != 1 || polynomial.degree < 2
      raise "NumberField needs a univariate polynomial of degree at least two"
    if polynomial.ring.field.class_name != "RationalField"
      raise "NumberField is currently implemented only over ℚ"

    if supplied_certificate == nil
      @irreducibility_certificate = NumberField.certify_irreducible(
        polynomial, irreducibility_limit)
    else
      if !NumberField.valid_irreducibility_certificate?(
           polynomial, supplied_certificate)
        raise "supplied number-field irreducibility certificate failed"
      @irreducibility_certificate = supplied_certificate
    @name = name
    @defining_polynomial = polynomial.monic
    @degree = @defining_polynomial.degree
    @power_basis_discriminant = @defining_polynomial.discriminant
    @order_search_limit = order_limit
    @source_order_polynomial = polynomial
    @generic_monogenic_order = nil
    @generic_maximal_order_computation = nil
    @generic_integral_basis = nil
    @generic_integral_basis_inverse = nil

    defining_coefficients = @defining_polynomial.coefficients
    @relation = []
    i = 0
    while i < @degree
      @relation.push(defining_coefficients[i])
      i += 1

    generator_coefficients = zero_coefficients
    generator_coefficients[1] = Rational.new(1)
    @generator = NumberFieldElement.new(self, generator_coefficients)
    initialize_cubic_maximal_order(polynomial) if cubic?
    self

  ro :name, :defining_polynomial, :power_basis_discriminant, :generator

  -> cubic?
    @degree == 3

  -> require_cubic_maximal_order(capability)
    if !cubic?
      raise capability + " is currently certified only for cubic number fields; power-basis arithmetic remains available"
    true

  -> monogenic_order
    if @generic_monogenic_order == nil
      @generic_monogenic_order = MonogenicOrder.new(
        @source_order_polynomial)
    @generic_monogenic_order

  -> certify_maximal_order(
       factor_search_limit = 1_000_000,
       step_limit = 10_000)
    if @generic_maximal_order_computation == nil
      computation = monogenic_order.maximal_order_with_certificate(
        factor_search_limit, step_limit)
      @generic_maximal_order_computation = computation
      if !@generic_maximal_order_computation.certificate.verified?
        raise "number-field maximal order failed certification"
      if cubic?
        generic_discriminant = @generic_maximal_order_computation.order.discriminant
        if generic_discriminant != @field_discriminant
          raise "generic and cubic maximal-order discriminants disagree"
    @generic_maximal_order_computation.order

  -> maximal_order_computation
    return nil if @generic_maximal_order_computation == nil
    @generic_maximal_order_computation

  -> maximal_order_certificate
    certify_maximal_order
    @generic_maximal_order_computation.certificate

  -> maximal_order
    certify_maximal_order

  -> generic_integral_basis
    if @generic_integral_basis == nil
      order = certify_maximal_order
      scale = monogenic_order.generator_scale
      @generic_integral_basis = []
      order.basis_vectors.each -> (vector)
        coefficients = []
        power = 1 ## big
        i = 0
        while i < @degree
          coefficients.push(
            Rational.coerce(vector[i]) * power)
          power *= scale
          i += 1
        @generic_integral_basis.push(coerce(coefficients))
    out = []
    @generic_integral_basis.each -> (element)
      out.push(element)
    out

  -> initialize_cubic_maximal_order(polynomial)
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

    @integral_basis = []
    @integral_basis_vectors.each -> (vector)
      @integral_basis.push(coerce([
        vector[0],
        vector[1] * @integral_generator_scale,
        vector[2] * @integral_generator_scale * @integral_generator_scale]))

  -> integral_defining_polynomial
    return @integral_defining_polynomial if cubic?
    monogenic_order.integral_polynomial

  -> integral_power_basis_discriminant
    return @integral_power_basis_discriminant if cubic?
    monogenic_order.discriminant

  -> field_discriminant
    return @field_discriminant if cubic?
    certify_maximal_order.discriminant

  -> maximal_order_index
    return @maximal_order_index if cubic?
    certify_maximal_order
    @generic_maximal_order_computation.index

  -> integral_generator_scale
    return @integral_generator_scale if cubic?
    monogenic_order.generator_scale

  -> integral_basis
    if cubic?
      out = []
      @integral_basis.each -> (element)
        out.push(element)
      return out
    generic_integral_basis

  -> degree
    @degree

  -> characteristic
    0

  -> coefficient_field?
    true

  -> exact?
    true

  -> finite_field?
    false

  -> irreducible?
    true

  -> irreducibility_certified?
    return true if @irreducibility_certificate == true
    NumberField.valid_irreducibility_certificate?(
      @defining_polynomial,
      @irreducibility_certificate)

  -> irreducibility_certificate
    @irreducibility_certificate

  -> field_discriminant_certified?
    cubic? || @generic_maximal_order_computation != nil

  -> maximal_order_certified?
    field_discriminant_certified?

  -> power_basis_discriminant_certified?
    true

  # Number-field discriminant means the discriminant of the maximal order.
  # power_basis_discriminant remains available when the defining generator's
  # order is what the caller wants to inspect.
  -> discriminant
    field_discriminant

  -> normalize_scalar(value)
    Rational.coerce(value)

  -> reduce_coefficients(coefficients)
    raise "number-field coefficients must be an Array" if coefficients.class_name != "Array"
    values = []
    coefficients.each -> values.push(normalize_scalar(item))
    while values.size < @degree
      values.push(Rational.new(0))
    i = values.size - 1
    while i >= @degree
      leading = values[i]
      if !leading.zero?
        shift = i - @degree
        j = 0
        while j < @degree
          values[shift + j] = values[shift + j] - leading * @relation[j]
          j += 1
      values[i] = Rational.new(0)
      i -= 1
    out = []
    i = 0
    while i < @degree
      out.push(values[i])
      i += 1
    out

  -> zero_coefficients
    values = []
    i = 0
    while i < @degree
      values.push(Rational.new(0))
      i += 1
    values

  -> coerce(value)
    if value.class_name == "NumberFieldElement"
      if value.field != self
        raise "number-field elements belong to different fields"
      return value
    return NumberFieldElement.new(self, value) if value.class_name == "Array"
    value_class = value.class_name
    if value_class != "Integer" && value_class != "Int" && value_class != "BigInt" && value_class != "Rational"
      raise "cannot coerce " + value_class + " into " + to_s
    coefficients = zero_coefficients
    coefficients[0] = normalize_scalar(value)
    NumberFieldElement.new(self, coefficients)

  -> normalize_element(value)
    coerce(value)

  -> embed_from(source_field, value)
    return normalize_element(value) if source_field == self
    if source_field.class_name == "RationalField"
      return coerce(value)
    raise "no certified field embedding from " + source_field.to_s + " into " + to_s

  -> zero
    NumberFieldElement.new(self, zero_coefficients)

  -> one
    coefficients = zero_coefficients
    coefficients[0] = Rational.new(1)
    NumberFieldElement.new(self, coefficients)

  -> zero?(value)
    coefficients = coerce(value).coefficients
    i = 0
    while i < @degree
      return false if !coefficients[i].zero?
      i += 1
    true

  -> one?(value)
    coefficients = coerce(value).coefficients
    return false if !coefficients[0].one?
    i = 1
    while i < @degree
      return false if !coefficients[i].zero?
      i += 1
    true

  -> equal?(left, right)
    coerce(left).eql?(coerce(right))

  -> add(left, right)
    a = coerce(left).coefficients
    b = coerce(right).coefficients
    sum = []
    i = 0
    while i < @degree
      sum.push(a[i] + b[i])
      i += 1
    NumberFieldElement.new(self, sum)

  -> negate(value)
    coefficients = coerce(value).coefficients
    negative = []
    coefficients.each -> negative.push(0 - item)
    NumberFieldElement.new(self, negative)

  -> subtract(left, right)
    add(left, negate(right))

  -> multiply(left, right)
    a = coerce(left).coefficients
    b = coerce(right).coefficients
    product = []
    i = 0
    while i < @degree * 2 - 1
      product.push(Rational.new(0))
      i += 1
    i = 0
    while i < @degree
      j = 0
      while j < @degree
        product[i + j] = product[i + j] + a[i] * b[j]
        j += 1
      i += 1
    NumberFieldElement.new(self, product)

  -> inverse(value)
    element = coerce(value)
    raise "division by zero in number field" if zero?(element)
    polynomial = element_polynomial(element)
    bezout = polynomial.xgcd(@defining_polynomial)
    gcd_coefficient = bezout[0].coefficients[0]
    if bezout[0].degree != 0 || gcd_coefficient.zero?
      raise "nonzero number-field element was not invertible; defining polynomial invariant failed"
    inverse_polynomial = bezout[1] / gcd_coefficient
    NumberFieldElement.new(self, inverse_polynomial.coefficients)

  -> element_polynomial(value)
    coefficients = coerce(value).coefficients
    x = @defining_polynomial.ring.generator(0)
    polynomial = @defining_polynomial.ring.zero
    i = coefficients.size - 1
    while i >= 0
      polynomial = polynomial * x + coefficients[i]
      i -= 1
    polynomial

  -> power_basis
    basis = []
    value = one
    i = 0
    while i < @degree
      basis.push(value)
      value = multiply(value, @generator)
      i += 1
    basis

  # Solve vector = sum basis[j]*c[j] over Q. A nil result certifies that the
  # vector is outside the supplied span. The caller uses only independent
  # Krylov prefixes, so every coefficient column must have a pivot.
  -> solve_rational_span(vector, basis)
    columns = basis.size
    matrix = []
    row = 0
    while row < @degree
      entries = []
      column = 0
      while column < columns
        entries.push(Rational.coerce(basis[column][row]))
        column += 1
      entries.push(Rational.coerce(vector[row]))
      matrix.push(entries)
      row += 1

    pivot_rows = []
    pivot_row = 0
    column = 0
    while column < columns
      pivot = pivot_row
      while pivot < @degree && matrix[pivot][column].zero?
        pivot += 1
      return nil if pivot == @degree
      if pivot != pivot_row
        temporary = matrix[pivot_row]
        matrix[pivot_row] = matrix[pivot]
        matrix[pivot] = temporary
      pivot_value = matrix[pivot_row][column]
      cell = column
      while cell <= columns
        matrix[pivot_row][cell] = matrix[pivot_row][cell] / pivot_value
        cell += 1
      row = 0
      while row < @degree
        if row != pivot_row && !matrix[row][column].zero?
          factor = matrix[row][column]
          cell = column
          while cell <= columns
            matrix[row][cell] = matrix[row][cell] - factor * matrix[pivot_row][cell]
            cell += 1
        row += 1
      pivot_rows.push(pivot_row)
      pivot_row += 1
      column += 1

    row = pivot_row
    while row < @degree
      all_zero = true
      column = 0
      while column < columns
        all_zero = false if !matrix[row][column].zero?
        column += 1
      if all_zero && !matrix[row][columns].zero?
        return nil
      row += 1

    solution = []
    column = 0
    while column < columns
      solution.push(matrix[pivot_rows[column]][columns])
      column += 1
    solution

  # The first exact dependence among 1, b, b^2, ... is the monic minimal
  # polynomial of b. Failed span solves certify independence of every shorter
  # prefix, rather than merely finding an annihilating polynomial.
  -> power_relation(value, relation_degree)
    if relation_degree < 1 || relation_degree > @degree
      raise "power-relation degree must lie between one and the field degree"
    element = coerce(value)
    basis = []
    power_value = one
    i = 0
    while i < relation_degree
      basis.push(power_value.coefficients)
      power_value = multiply(power_value, element)
      i += 1
    solve_rational_span(power_value.coefficients, basis)

  -> polynomial_from_power_relation(relation, relation_degree)
    if relation.class_name != "Array" || relation.size != relation_degree
      raise "power relation has the wrong arity"
    x = @defining_polynomial.ring.generator(0)
    polynomial = x**relation_degree
    i = 0
    while i < relation.size
      polynomial = polynomial - x**i * relation[i]
      i += 1
    polynomial.monic

  -> minimal_polynomial(value)
    element = coerce(value)
    basis = [one.coefficients]
    power_value = element
    relation_degree = 1
    while relation_degree <= @degree
      relation = solve_rational_span(power_value.coefficients, basis)
      if relation != nil
        polynomial = polynomial_from_power_relation(
          relation, relation_degree)
        if !evaluate(polynomial, element).zero?
          raise "minimal-polynomial relation invariant failed"
        return polynomial
      basis.push(power_value.coefficients)
      power_value = multiply(power_value, element)
      relation_degree += 1
    raise "number-field power dependence invariant failed"

  -> minimal_polynomial_certified?(value)
    minimal_polynomial_certificate(value).verified?

  -> minimal_polynomial_certificate(value)
    element = coerce(value)
    NumberFieldMinimalPolynomialCertificate.new(
      self, element, minimal_polynomial(element))

  # Multiplication by b on K has characteristic polynomial
  # minpoly_b(T)^[K:Q(b)]. This also supplies exact trace and norm without
  # numerical embeddings or a floating determinant.
  -> characteristic_polynomial(value)
    polynomial = minimal_polynomial(value)
    if @degree % polynomial.degree != 0
      raise "minimal-polynomial degree does not divide number-field degree"
    polynomial ** (@degree / polynomial.degree)

  -> trace(value)
    polynomial = characteristic_polynomial(value)
    0 - polynomial.coeff(@degree - 1)

  -> norm(value)
    polynomial = characteristic_polynomial(value)
    constant = polynomial.coeff(0)
    @degree.odd? ? 0 - constant : constant

  -> integral_element?(value)
    polynomial = minimal_polynomial(value)
    coefficients = polynomial.coefficients
    i = 0
    while i < coefficients.size
      return false if coefficients[i].denominator != 1
      i += 1
    true

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
    [real, (@degree - real) / 2]

  -> signature_certified?
    true

  -> totally_real?
    signature[0] == @degree

  -> real_embeddings(search_limit = 250_000)
    embeddings = []
    @defining_polynomial.real_roots(search_limit).each -> (root)
      embeddings.push(NumberFieldRealEmbedding.new(self, root))
    if embeddings.size != signature[0]
      raise "real-embedding count disagrees with the certified signature"
    embeddings

  -> complex_embedding_pair_count
    signature[1]

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
    return false if polynomial.ring.arity != 1 || polynomial.degree != @degree
    return false if polynomial.ring.field.class_name != "RationalField"
    left = @defining_polynomial.coefficients
    right = polynomial.monic.coefficients
    i = 0
    while i <= @degree
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
    if !cubic?
      raise "roots_in is currently complete only for cubic number fields"
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
    require_cubic_maximal_order("cubic order coordinate solve")
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
    require_cubic_maximal_order("cubic integral-power multiplication")
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
    require_cubic_maximal_order("cubic order basis determinant")
    a = basis[0]
    b = basis[1]
    c = basis[2]
    first = a[0] * (b[1] * c[2] - b[2] * c[1])
    second = b[0] * (a[1] * c[2] - a[2] * c[1])
    third = c[0] * (a[1] * b[2] - a[2] * b[1])
    first - second + third

  -> order_discriminant(basis)
    require_cubic_maximal_order("cubic order discriminant")
    determinant = determinant_of_basis(basis)
    value = determinant * determinant * @integral_power_basis_discriminant
    if value.denominator != 1
      raise "closed cubic order has a nonintegral discriminant"
    value.numerator

  -> order_closed?(basis)
    require_cubic_maximal_order("cubic order closure test")
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
    require_cubic_maximal_order("cubic order discriminant factorization")
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
    require_cubic_maximal_order("cubic Minkowski discriminant bound")
    @defining_polynomial.real_root_count == 3 ? 21 : 12

  -> possible_order_indices
    require_cubic_maximal_order("cubic possible-order indices")
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
    require_cubic_maximal_order("cubic overorder HNF")
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
    require_cubic_maximal_order("cubic order-basis composition")
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
    require_cubic_maximal_order("cubic relative overorder search")
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
    require_cubic_maximal_order("cubic overorder search")
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
    require_cubic_maximal_order("cubic maximal-order search")
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

  # Exact irreducibility certification over Q. Quadratics and cubics use the
  # rational-root criterion. Higher degrees first seek an irreducible
  # reduction modulo a good prime and replay Rabin's finite-field criterion;
  # this is a short proof of irreducibility over Q. An irreducible polynomial
  # need not have such a reduction, so failure to find one falls back to
  # exhaustive, resource-bounded Kronecker factorization.
  -> .valid_irreducibility_certificate?(
       polynomial, certificate)
    return false if certificate == nil
    name = certificate.class_name
    supported = name == "NumberFieldModularIrreducibilityCertificate"
    supported = true if name == "NumberFieldModularDegreeIrreducibilityCertificate"
    supported = true if name == "NumberFieldTowerIrreducibilityCertificate"
    supported = true if name == "NumberFieldIsomorphicModelIrreducibilityCertificate"
    return false if !supported
    return false if !certificate.verified?
    return false if certificate.polynomial.class_name != "Polynomial"
    certificate.polynomial.monic.eql?(polynomial.monic)

  -> .relative_modular_irreducibility_certificate(
       polynomial, rational_prime_limit = 100,
       factor_search_limit = 250_000,
       generator_search_limit = 250_000)
    if polynomial.class_name != "Polynomial"
      raise "relative modular irreducibility needs a Polynomial"
    field = polynomial.ring.field
    if field.class_name != "NumberField"
      raise "relative modular irreducibility needs a number-field coefficient field"
    rational_prime = 2
    while rational_prime <= rational_prime_limit
      if rational_prime.prime?
        primes = field.prime_ideals_above(
          rational_prime, factor_search_limit,
          generator_search_limit)
        prime_index = 0
        while prime_index < primes.size
          certificate = NumberFieldRelativeModularIrreducibilityCertificate.new(
            polynomial.monic, primes[prime_index])
          return certificate if certificate.verified?
          prime_index += 1
      rational_prime += 1
    nil

  -> .tower_irreducibility_certificate(
       polynomial, relative_polynomial,
       relative_certificate = nil)
    certificate = relative_certificate
    if certificate == nil
      certificate = NumberField.relative_modular_irreducibility_certificate(
        relative_polynomial)
    if certificate == nil
      raise "relative modular irreducibility search exhausted"
    result = NumberFieldTowerIrreducibilityCertificate.new(
      polynomial, relative_polynomial,
      certificate)
    if !result.verified?
      raise "tower irreducibility certificate failed"
    result

  -> .isomorphic_model_irreducibility_certificate(
       polynomial, model_polynomial,
       root_expression, model_certificate)
    result = NumberFieldIsomorphicModelIrreducibilityCertificate.new(
      polynomial, model_polynomial,
      root_expression, model_certificate)
    if !result.verified?
      raise "isomorphic-model irreducibility certificate failed"
    result

  -> .modular_irreducibility_certificate(
       polynomial, search_count = 64)
    if polynomial.class_name != "Polynomial"
      raise "modular irreducibility search needs a Polynomial"
    tried = 0
    candidate = 2
    while tried < search_count
      if candidate.prime?
        tried += 1
        certificate = NumberFieldModularIrreducibilityCertificate.new(
          polynomial, candidate)
        return certificate if certificate.verified?
      candidate = candidate == 2 ? 3 : candidate + 2
    nil

  -> .primitive_integral_polynomial(polynomial)
    if polynomial.class_name != "Polynomial"
      raise "primitive integral conversion needs a Polynomial"
    if polynomial.ring.arity != 1
      raise "primitive integral conversion needs one variable"
    if polynomial.ring.field.class_name != "RationalField"
      raise "primitive integral conversion is implemented over Q"
    common = 1 ## big
    polynomial.coefficients.each -> (coefficient)
      common = common.lcm(coefficient.denominator)
    integers = []
    polynomial.coefficients.each -> (coefficient)
      multiplier = common / coefficient.denominator
      integers.push(coefficient.numerator * multiplier)
    divisor = 0 ## big
    integers.each -> (coefficient)
      divisor = divisor.gcd(coefficient.abs)
    integers = integers.map -> item / divisor
    if integers[integers.size - 1] < 0
      integers = integers.map -> 0 - item
    terms = []
    i = 0
    while i < integers.size
      if integers[i] != 0
        terms.push([Rational.new(integers[i]), [i]])
      i += 1
    Polynomial.new(polynomial.ring, terms)

  -> .modular_degree_irreducibility_certificate(
       polynomial, search_count = 32,
       factor_search_limit = 250_000)
    primes = []
    factorizations = []
    candidate = 2
    tried = 0
    while tried < search_count
      if candidate.prime?
        tried += 1
        helper = NumberFieldModularDegreeIrreducibilityCertificate
        reduction = helper.reduction_at(
          polynomial, candidate)
        if reduction.degree == polynomial.degree
          factorization = reduction.factor_with_certificate(
            factor_search_limit)
          primes.push(candidate)
          factorizations.push(factorization)
          certificate = NumberFieldModularDegreeIrreducibilityCertificate.new(
            polynomial, primes,
            factorizations,
            factor_search_limit)
          return certificate if certificate.verified?
      candidate = candidate == 2 ? 3 : candidate + 2
    nil

  -> .certify_irreducible(polynomial, search_limit = 250_000)
    if polynomial.class_name != "Polynomial" || polynomial.ring.arity != 1 || polynomial.degree < 2
      raise "number-field irreducibility certification needs a univariate polynomial of degree at least two"
    if polynomial.ring.field.class_name != "RationalField"
      raise "number-field irreducibility certification is only implemented over ℚ"
    if polynomial.degree == 3
      return NumberField.certify_irreducible_cubic(polynomial, search_limit)

    monic = polynomial.monic
    modular_count = search_limit < 64 ? search_limit : 64
    modular = NumberField.modular_irreducibility_certificate(
      monic, modular_count)
    return modular if modular != nil
    degree_modular = nil
    if search_limit > 0
      degree_modular = NumberField.modular_degree_irreducibility_certificate(
        monic, 8, search_limit)
    return degree_modular if degree_modular != nil
    factors = monic.factor(search_limit)
    if factors.size != 1 || !factors[0].eql?(monic)
      raise "number field defining polynomial is reducible over ℚ"
    true

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
    invalid = @ring.arity != 1 || degree < 2
    invalid = true if @ring.field.class_name != "RationalField"
    if invalid
      raise "field_discriminant needs a univariate polynomial of degree at least two over ℚ"
    NumberField.new(self).field_discriminant

  -> roots_in(number_field)
    if number_field.class_name != "NumberField"
      raise "roots_in currently needs a NumberField"
    number_field.roots_of(self)
