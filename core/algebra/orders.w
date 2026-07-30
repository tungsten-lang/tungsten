# Exact monogenic orders and certified Dedekind index tests.
#
# For a primitive integral polynomial
#
#   f(x) = a_n x^n + ... + a_0,
#
# beta = a_n*alpha satisfies the monic integral polynomial
#
#   g(y) = a_n^(n-1) f(y/a_n).
#
# MonogenicOrder represents Z[beta] inside the etale Q-algebra Q[y]/(g).
# Its trace-form discriminant is exact. At every prime p whose square divides
# the discriminant, Dedekind's index criterion certifies whether p divides
# [O_max : Z[beta]]. Passing all such primes proves maximality. Failure proves
# that the displayed power order is nonmaximal; maximal_orders.w then uses
# degree-generic Round 2 multiplier rings to construct the integral closure.

+ IntegralGeneratorTransformCertificate
  -> new(@source_polynomial, @integral_polynomial, @scale)

  -> source_polynomial
    @source_polynomial

  -> integral_polynomial
    @integral_polynomial

  -> scale
    @scale

  -> verified?
    return false if @source_polynomial.class_name != "Polynomial"
    return false if @source_polynomial.ring.arity != 1
    return false if @source_polynomial.ring.field.class_name != "RationalField"
    return false if @source_polynomial.degree <= 0
    return false if @integral_polynomial.class_name != "Polynomial"
    return false if @integral_polynomial.ring != @source_polynomial.ring
    transformed = MonogenicOrder.integral_transform_data(
      @source_polynomial)
    return false if transformed[0] != @scale
    transformed[1].eql?(@integral_polynomial)

  -> certified?
    verified?

  -> to_s
    text = "IntegralGeneratorTransformCertificate(scale "
    text + @scale.to_s + ")"

  -> inspect
    to_s


+ MonogenicOrderCertificate
  -> new(@order)

  -> order
    @order

  -> verified?
    return false if @order.class_name != "MonogenicOrder"
    return false if !@order.transform_certificate.verified?
    polynomial = @order.integral_polynomial
    return false if polynomial.degree != @order.rank
    return false if !polynomial.eql?(polynomial.monic)
    coefficients = polynomial.coefficients
    i = 0
    while i < coefficients.size
      return false if coefficients[i].denominator != 1
      i += 1
    return false if !@order.algebra.certificate.verified?
    return false if !@order.algebra.defining_polynomial.eql?(polynomial)
    discriminant = polynomial.discriminant
    return false if discriminant.denominator != 1
    discriminant.numerator == @order.discriminant

  -> certified?
    verified?

  -> to_s
    "MonogenicOrderCertificate(rank " + @order.rank.to_s + ")"

  -> inspect
    to_s


+ DedekindIndexCertificate
  -> new(@order, @prime, @factor_search_limit = 250_000)
    @factorization = nil
    @radical_factor = nil
    @repeated_factor = nil
    @index_obstruction = nil
    @index_prime_to_p = nil

  -> order
    @order

  -> prime
    @prime

  -> factorization
    verify! if @factorization == nil
    @factorization

  -> radical_factor
    verify! if @radical_factor == nil
    @radical_factor

  -> repeated_factor
    verify! if @repeated_factor == nil
    @repeated_factor

  -> obstruction
    verify! if @index_obstruction == nil
    @index_obstruction

  -> index_prime_to_p?
    verify!
    @index_prime_to_p

  -> p_divides_index?
    !index_prime_to_p?

  -> verified?
    answer = false
    begin
      answer = verify!
    rescue error
      answer = false
    answer

  -> verify!
    return true if @index_prime_to_p != nil
    if @order.class_name != "MonogenicOrder"
      raise "Dedekind certificate needs a MonogenicOrder"
    prime_class = @prime.class_name
    integer_prime = prime_class == "Integer" || prime_class == "Int"
    integer_prime = integer_prime || prime_class == "BigInt"
    if !integer_prime || @prime < 2 || !@prime.prime?
      raise "Dedekind certificate needs a prime integer"

    polynomial = @order.integral_polynomial
    finite_field = FiniteField.new(@prime)
    finite_ring = PolynomialRing.new(
      polynomial.ring.names, finite_field)
    reduced = polynomial.change_ring(finite_ring).monic
    @factorization = reduced.factor_with_certificate(
      @factor_search_limit)
    if !@factorization.certificate.verified?
      raise "Dedekind modular factorization did not certify"

    unique = []
    @factorization.factors.each -> (factor)
      if factor.degree > 0
        seen = false
        unique.each ->
          seen = true if item.eql?(factor.monic)
        unique.push(factor.monic) if !seen

    @radical_factor = finite_ring.one
    unique.each ->
      @radical_factor = @radical_factor * item
    @repeated_factor = reduced / @radical_factor

    rational_ring = polynomial.ring
    radical_lift = lift_prime_polynomial(
      @radical_factor, rational_ring)
    repeated_lift = lift_prime_polynomial(
      @repeated_factor, rational_ring)
    difference = polynomial - radical_lift * repeated_lift
    divided_terms = []
    i = 0
    while i <= polynomial.degree
      coefficient = difference.coeff(i)
      if coefficient.denominator != 1
        raise "Dedekind difference is not integral"
      numerator = coefficient.numerator
      if numerator % @prime != 0
        raise "Dedekind difference is not divisible by p"
      quotient = numerator / @prime
      divided_terms.push([Rational.new(quotient), [i]]) if quotient != 0
      i += 1
    divided = Polynomial.new(rational_ring, divided_terms)
    divided_mod_p = divided.change_ring(finite_ring)
    @index_obstruction = @radical_factor.gcd(
      @repeated_factor).gcd(divided_mod_p).monic
    @index_prime_to_p = @index_obstruction.degree == 0
    true

  -> lift_prime_polynomial(polynomial, target_ring)
    terms = []
    polynomial.each_term -> (coefficient, exponents)
      terms.push([Rational.new(coefficient), exponents])
    Polynomial.new(target_ring, terms)

  -> certified?
    verified?

  -> to_s
    status = index_prime_to_p? ? "p-maximal" : "p divides index"
    "DedekindIndexCertificate(" + @prime.to_s + ": " + status + ")"

  -> inspect
    to_s


+ MonogenicOrderMaximalityCertificate
  -> new(@order, @factor_search_limit = 1_000_000)
    @discriminant_factors = nil
    @local_certificates = nil

  -> order
    @order

  -> discriminant_factors
    build if @discriminant_factors == nil
    out = []
    @discriminant_factors.each ->
      out.push([item[0], item[1]])
    out

  -> local_certificates
    build if @local_certificates == nil
    out = []
    @local_certificates.each -> out.push(item)
    out

  -> build
    if @order.class_name != "MonogenicOrder"
      raise "maximality certificate needs a MonogenicOrder"
    @discriminant_factors = @order.factor_discriminant(
      @factor_search_limit)
    @local_certificates = []
    @discriminant_factors.each -> (factor)
      if factor[1] >= 2
        @local_certificates.push(DedekindIndexCertificate.new(
          @order, factor[0], @factor_search_limit))
    true

  -> verified?
    answer = false
    begin
      answer = verify!
    rescue error
      answer = false
    answer

  -> verify!
    build if @discriminant_factors == nil
    product = 1 ## big
    @discriminant_factors.each -> (factor)
      prime = factor[0]
      exponent = factor[1]
      if prime < 2 || !prime.prime? || exponent < 1
        raise "invalid discriminant prime-power factor"
      product *= prime ** exponent
    if product != @order.discriminant.abs
      raise "discriminant factorization did not reconstruct"
    @local_certificates.each ->
      if !item.verified?
        raise "Dedekind local certificate failed"
    true

  -> maximal?
    verify!
    i = 0
    while i < @local_certificates.size
      return false if !@local_certificates[i].index_prime_to_p?
      i += 1
    true

  -> obstructed_primes
    verify!
    out = []
    @local_certificates.each ->
      out.push(item.prime) if item.p_divides_index?
    out

  -> certified?
    verified?

  -> to_s
    status = maximal? ? "maximal" : "nonmaximal"
    "MonogenicOrderMaximalityCertificate(" + status + ")"

  -> inspect
    to_s


+ MonogenicOrder
  -> new(polynomial)
    transformed = MonogenicOrder.integral_transform_data(
      polynomial)
    @source_polynomial = polynomial
    @generator_scale = transformed[0]
    @integral_polynomial = transformed[1]
    @algebra = EtaleAlgebra.new(@integral_polynomial)
    @discriminant_cache = nil
    @algebra_order_cache = nil
    if !certificate.verified?
      raise "monogenic order failed certification"

  -> .primitive_integer_coefficients(polynomial)
    if polynomial.class_name != "Polynomial"
      raise "integral transform needs a Polynomial"
    if polynomial.ring.arity != 1
      raise "integral transform needs a univariate polynomial"
    if polynomial.ring.field.class_name != "RationalField"
      raise "integral transform is currently implemented over Q"
    if polynomial.degree <= 0
      raise "integral transform needs a nonconstant polynomial"
    common = 1 ## big
    polynomial.coefficients.each ->
      common = (common / common.gcd(item.denominator)) * item.denominator
    integers = []
    i = 0
    while i <= polynomial.degree
      coefficient = polynomial.coeff(i)
      integers.push(
        coefficient.numerator * (common / coefficient.denominator))
      i += 1
    divisor = 0 ## big
    integers.each -> divisor = divisor.gcd(item.abs)
    integers = integers.map -> item / divisor
    if integers[integers.size - 1] < 0
      integers = integers.map -> 0 - item
    integers

  -> .integral_transform_data(polynomial)
    integers = MonogenicOrder.primitive_integer_coefficients(
      polynomial)
    degree = integers.size - 1
    scale = integers[degree]
    if scale <= 0
      raise "integral generator transform needs positive leading coefficient"
    ring = polynomial.ring
    terms = []
    i = 0
    while i < degree
      coefficient = integers[i] * (scale ** (degree - 1 - i))
      terms.push([Rational.new(coefficient), [i]]) if coefficient != 0
      i += 1
    terms.push([Rational.new(1), [degree]])
    [scale, Polynomial.new(ring, terms)]

  -> source_polynomial
    @source_polynomial

  -> integral_polynomial
    @integral_polynomial

  -> generator_scale
    @generator_scale

  -> algebra
    @algebra

  -> generator
    @algebra.generator

  -> rank
    @integral_polynomial.degree

  -> degree
    rank

  -> basis
    @algebra.power_basis

  -> discriminant
    if @discriminant_cache == nil
      value = @integral_polynomial.discriminant
      if value.denominator != 1
        raise "integral power order has nonintegral discriminant"
      @discriminant_cache = value.numerator
    @discriminant_cache

  -> transform_certificate
    IntegralGeneratorTransformCertificate.new(
      @source_polynomial, @integral_polynomial,
      @generator_scale)

  -> certificate
    MonogenicOrderCertificate.new(self)

  -> certified?
    certificate.verified?

  -> algebra_order
    if @algebra_order_cache == nil
      @algebra_order_cache = AlgebraOrder.power_order(self)
    @algebra_order_cache

  -> as_algebra_order
    algebra_order

  # If beta is the displayed integral generator and
  #
  #   g(T) = T^n + sum c_i T^i,
  #
  # then gamma=beta/d is integral exactly when d^(n-i) divides every c_i.
  # Taking the largest such d gives a certified power overorder before the
  # general Round 2 loop starts.
  -> integral_generator_divisor(
       factor_search_limit = 1_000_000)
    factors = algebra_order.factor_discriminant(
      factor_search_limit)
    divisor = 1 ## big
    factors.each -> (factor)
      prime = factor[0]
      maximum = nil
      i = 0
      while i < rank
        coefficient = @integral_polynomial.coeff(i)
        if coefficient.denominator != 1
          raise "integral generator polynomial has a nonintegral coefficient"
        value = coefficient.numerator.abs
        if value != 0
          valuation = 0
          while value % prime == 0
            value = value / prime
            valuation += 1
          bound = valuation / (rank - i)
          maximum = bound if maximum == nil || bound < maximum
        i += 1
      divisor *= prime ** maximum if maximum != nil && maximum > 0
    divisor

  -> integral_generator_overorder(
       factor_search_limit = 1_000_000)
    divisor = integral_generator_divisor(
      factor_search_limit)
    return algebra_order if divisor == 1
    vectors = []
    i = 0
    while i < rank
      vector = []
      j = 0
      while j < rank
        coefficient = Rational.new(0)
        if i == j
          coefficient = Rational.new(1, divisor ** i)
        vector.push(coefficient)
        j += 1
      vectors.push(vector)
      i += 1
    overorder = AlgebraOrder.new(@algebra, vectors)
    if !overorder.contains_order?(algebra_order)
      raise "integral generator overorder does not contain its power order"
    overorder

  -> coerce(value)
    element = @algebra.coerce(value)
    if !contains?(element)
      raise "element is not integral in this monogenic order"
    element

  -> element(coefficients)
    coerce(coefficients)

  -> contains?(value)
    return false if value.class_name != "EtaleAlgebraElement"
    return false if value.algebra != @algebra
    coefficients = value.coefficients
    i = 0
    while i < coefficients.size
      return false if coefficients[i].class_name != "Rational"
      return false if coefficients[i].denominator != 1
      i += 1
    true

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
      raise "element is not a unit of this monogenic order"
    element.inverse

  -> index_certificate(prime, factor_search_limit = 250_000)
    DedekindIndexCertificate.new(
      self, prime, factor_search_limit)

  -> maximality_certificate(factor_search_limit = 1_000_000)
    MonogenicOrderMaximalityCertificate.new(
      self, factor_search_limit)

  -> maximal?(factor_search_limit = 1_000_000)
    maximality_certificate(factor_search_limit).maximal?

  -> obstructed_primes(factor_search_limit = 1_000_000)
    maximality_certificate(
      factor_search_limit).obstructed_primes

  -> maximal_order(
       factor_search_limit = 1_000_000,
       step_limit = 10_000)
    certificate = maximality_certificate(
      factor_search_limit)
    return self if certificate.maximal?
    maximal_order_with_certificate(
      factor_search_limit, step_limit).order

  -> maximal_order_with_certificate(
       factor_search_limit = 1_000_000,
       step_limit = 10_000)
    seed = integral_generator_overorder(
      factor_search_limit)
    MaximalOrderComputation.new(
      algebra_order, factor_search_limit,
      step_limit, seed)

  -> p_maximal_order_with_certificate(
       prime, step_limit = 10_000)
    algebra_order.p_maximal_order_with_certificate(
      prime, step_limit)

  -> p_maximal_order(prime, step_limit = 10_000)
    p_maximal_order_with_certificate(
      prime, step_limit).order

  # Exact bounded trial division. Exhaustion is "unknown", never a claim that
  # the unfactored cofactor is prime.
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
        raise "discriminant factor search limit exceeded; maximality unknown"
      exponent = 0
      while remaining % candidate == 0
        remaining = remaining / candidate
        exponent += 1
      factors.push([candidate, exponent]) if exponent > 0
      candidate = candidate == 2 ? 3 : candidate + 2
    factors.push([remaining, 1]) if remaining > 1
    factors

  -> to_s
    "Z[" + @algebra.generator.to_s + "]"

  -> inspect
    to_s


+ EtaleProductOrderElement
  -> new(@order, values)
    if values.class_name != "Array"
      raise "product-order element needs component values"
    component_orders = @order.component_orders
    if values.size != component_orders.size
      raise "wrong product-order component count"
    @components = []
    i = 0
    while i < values.size
      @components.push(component_orders[i].coerce(values[i]))
      i += 1

  -> order
    @order

  -> components
    out = []
    @components.each -> out.push(item)
    out

  -> [](index)
    @components[index]

  -> zero?
    @order.zero?(self)

  -> one?
    @order.one?(self)

  -> unit?
    @order.unit?(self)

  -> +(other)
    @order.add(self, other)

  -> -(other)
    @order.subtract(self, other)

  -> negate
    @order.negate(self)

  -> -@
    negate

  -> *(other)
    @order.multiply(self, other)

  -> /(other)
    @order.divide(self, other)

  -> inverse
    @order.inverse(self)

  -> trace
    @order.trace(self)

  -> norm
    @order.norm(self)

  -> ==/1
    self.eql?(@1)

  -> eql?(other)
    return false if other.class_name != "EtaleProductOrderElement"
    return false if other.order != @order
    right = other.components
    i = 0
    while i < @components.size
      return false if !@components[i].eql?(right[i])
      i += 1
    true

  -> to_s
    @components.to_s

  -> inspect
    "EtaleProductOrderElement(" + to_s + ")"


+ EtaleProductOrderCertificate
  -> new(@order)

  -> verified?
    return false if @order.class_name != "EtaleProductOrder"
    components = @order.component_orders
    return false if components.size == 0
    total = 0
    i = 0
    while i < components.size
      return false if !components[i].certificate.verified?
      total += components[i].rank
      i += 1
    total == @order.rank

  -> certified?
    verified?

  -> to_s
    text = "EtaleProductOrderCertificate(rank "
    text + @order.rank.to_s + ")"

  -> inspect
    to_s


+ EtaleProductOrder
  -> new(polynomials)
    if polynomials.class_name != "Array" || polynomials.size == 0
      raise "etale product order needs component polynomials"
    @component_orders = []
    polynomials.each ->
      item_class = item.class_name
      supported_order = item_class == "MonogenicOrder"
      supported_order = true if item_class == "AlgebraOrder"
      if supported_order
        @component_orders.push(item)
      else
        @component_orders.push(MonogenicOrder.new(item))
    if !certificate.verified?
      raise "etale product order failed certification"

  -> component_orders
    out = []
    @component_orders.each -> out.push(item)
    out

  -> component_count
    @component_orders.size

  -> component_ranks
    out = []
    @component_orders.each -> out.push(item.rank)
    out

  -> rank
    total = 0
    @component_orders.each -> total += item.rank
    total

  -> discriminant
    result = 1 ## big
    @component_orders.each ->
      result *= item.discriminant
    result

  -> certificate
    EtaleProductOrderCertificate.new(self)

  -> certified?
    certificate.verified?

  -> component_algebra_orders
    out = []
    @component_orders.each ->
      item_class = item.class_name
      if item_class == "MonogenicOrder"
        out.push(item.algebra_order)
      elsif item_class == "AlgebraOrder"
        out.push(item)
      else
        raise "unsupported etale product order component"
    out

  -> coerce(value)
    if value.class_name == "EtaleProductOrderElement"
      if value.order != self
        raise "product-order elements belong to different orders"
      return value
    EtaleProductOrderElement.new(self, value)

  -> element(values)
    coerce(values)

  -> zero
    values = []
    @component_orders.each -> values.push(item.zero)
    EtaleProductOrderElement.new(self, values)

  -> one
    values = []
    @component_orders.each -> values.push(item.one)
    EtaleProductOrderElement.new(self, values)

  -> zero?(value)
    element = coerce(value)
    components = element.components
    i = 0
    while i < components.size
      return false if !components[i].zero?
      i += 1
    true

  -> one?(value)
    element = coerce(value)
    components = element.components
    i = 0
    while i < components.size
      return false if !components[i].one?
      i += 1
    true

  -> add(left, right)
    a = coerce(left).components
    b = coerce(right).components
    out = []
    i = 0
    while i < a.size
      out.push(a[i] + b[i])
      i += 1
    EtaleProductOrderElement.new(self, out)

  -> negate(value)
    out = []
    coerce(value).components.each ->
      out.push(item.negate)
    EtaleProductOrderElement.new(self, out)

  -> subtract(left, right)
    add(left, negate(right))

  -> multiply(left, right)
    a = coerce(left).components
    b = coerce(right).components
    out = []
    i = 0
    while i < a.size
      out.push(a[i] * b[i])
      i += 1
    EtaleProductOrderElement.new(self, out)

  -> unit?(value)
    element = coerce(value)
    components = element.components
    i = 0
    while i < components.size
      return false if !@component_orders[i].unit?(components[i])
      i += 1
    true

  -> inverse(value)
    element = coerce(value)
    if !unit?(element)
      raise "element is not a unit of this etale product order"
    components = element.components
    out = []
    i = 0
    while i < components.size
      out.push(@component_orders[i].inverse(components[i]))
      i += 1
    EtaleProductOrderElement.new(self, out)

  -> divide(left, right)
    multiply(left, inverse(right))

  -> trace(value)
    result = Rational.new(0)
    coerce(value).components.each ->
      result = result + item.trace
    result

  -> norm(value)
    result = Rational.new(1)
    coerce(value).components.each ->
      result = result * item.norm
    result

  -> maximality_certificates(factor_search_limit = 1_000_000)
    out = []
    @component_orders.each ->
      if item.class_name == "MonogenicOrder"
        out.push(item.maximality_certificate(
          factor_search_limit))
      else
        out.push(item.maximal_order_with_certificate(
          factor_search_limit).certificate)
    out

  -> maximal?(factor_search_limit = 1_000_000)
    components = @component_orders
    i = 0
    while i < components.size
      return false if !components[i].maximal?(
        factor_search_limit)
      i += 1
    true

  -> obstructed_components(factor_search_limit = 1_000_000)
    out = []
    certificates = maximality_certificates(
      factor_search_limit)
    i = 0
    while i < certificates.size
      if !certificates[i].maximal?
        primes = []
        if certificates[i].respond_to?("obstructed_primes")
          primes = certificates[i].obstructed_primes
        out.push([i, primes])
      i += 1
    out

  -> maximal_order_with_certificate(
       factor_search_limit = 1_000_000,
       step_limit = 10_000)
    EtaleProductMaximalOrderComputation.new(
      self, factor_search_limit, step_limit)

  -> maximal_order(
       factor_search_limit = 1_000_000,
       step_limit = 10_000)
    maximal_order_with_certificate(
      factor_search_limit, step_limit).order

  -> to_s
    "EtaleProductOrder(" + component_ranks.to_s + ")"

  -> inspect
    to_s
