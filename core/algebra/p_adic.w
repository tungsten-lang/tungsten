# Certified finite-precision p-adic primitives.
#
# `PadicField` currently exposes the exact rational subfield of Q_p, its
# square-class quotient, and simple-root Hensel lifts. It does not pretend
# that arbitrary completed Q_p arithmetic or extensions are implemented.

+ PadicArithmetic
  -> .integer?(value)
    name = value.class_name
    name == "Integer" || name == "Int" || name == "BigInt"

  -> .integer_valuation(value, prime)
    if value == 0
      raise "the p-adic valuation of zero is infinite"
    remaining = value.abs
    valuation = 0
    while remaining % prime == 0
      remaining = remaining / prime
      valuation += 1
    valuation

  -> .extended_gcd(left, right)
    old_r = left
    r = right
    old_s = 1
    s = 0
    while r != 0
      quotient = old_r / r
      next_r = old_r - quotient * r
      old_r = r
      r = next_r
      next_s = old_s - quotient * s
      old_s = s
      s = next_s
    [old_r, old_s]

  -> .inverse_mod(value, modulus)
    normalized = value % modulus
    normalized += modulus if normalized < 0
    bezout = PadicArithmetic.extended_gcd(
      normalized, modulus)
    if bezout[0] != 1
      raise "p-adic unit denominator is not invertible"
    inverse = bezout[1] % modulus
    inverse += modulus if inverse < 0
    inverse

  -> .power_mod(base, exponent, modulus)
    result = 1
    factor = base % modulus
    remaining = exponent
    while remaining > 0
      result = result * factor % modulus if remaining.odd?
      remaining = remaining / 2
      factor = factor * factor % modulus if remaining > 0
    result

  -> .evaluate_integer_polynomial(coefficients, value)
    result = 0 ## big
    index = coefficients.size - 1
    while index >= 0
      result = result * value + coefficients[index]
      index -= 1
    result

  -> .derivative_coefficients(coefficients)
    out = []
    index = 1
    while index < coefficients.size
      out.push(coefficients[index] * index)
      index += 1
    out


+ PadicSquareClassCertificate
  -> new(@square_class)
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
    expected = "PadicSquareClass"
    return false if @square_class.class_name != expected
    element = @square_class.element
    return false if element.zero?
    prime = element.field.prime
    vector = @square_class.vector
    return false if vector.size != (prime == 2 ? 3 : 2)
    return false if !vector.all? -> item == 0 || item == 1
    return false if vector[0] != element.valuation % 2
    if prime == 2
      unit = element.unit_residue(3)
      tail = nil
      tail = [0, 0] if unit == 1
      tail = [1, 1] if unit == 3
      tail = [0, 1] if unit == 5
      tail = [1, 0] if unit == 7
      return false if tail == nil
      return false if vector[1] != tail[0]
      return false if vector[2] != tail[1]
    else
      unit = element.unit_residue(1)
      symbol = PadicArithmetic.power_mod(
        unit, (prime - 1) / 2, prime)
      nonsquare = symbol == 1 ? 0 : 1
      return false if vector[1] != nonsquare
    true

  -> certified?
    verified?

  -> proof_kind
    :exact_local_square_class

  -> kernel_checked?
    true


+ PadicSquareClass
  -> new(@element)
    if @element.class_name != "PadicRationalElement"
      raise "p-adic square classes currently need exact rational elements"
    if @element.zero?
      raise "zero has no multiplicative p-adic square class"
    @vector = compute_vector
    @certificate_cache = PadicSquareClassCertificate.new(self)
    if !@certificate_cache.verified?
      raise "p-adic square-class computation failed certification"

  -> element
    @element

  -> field
    @element.field

  -> vector
    out = []
    @vector.each -> out.push(item)
    out

  -> compute_vector
    valuation_bit = @element.valuation % 2
    if field.prime == 2
      unit = @element.unit_residue(3)
      return [valuation_bit, 0, 0] if unit == 1
      return [valuation_bit, 1, 1] if unit == 3
      return [valuation_bit, 0, 1] if unit == 5
      return [valuation_bit, 1, 0] if unit == 7
      raise "2-adic unit did not reduce to an odd residue"
    unit = @element.unit_residue(1)
    symbol = PadicArithmetic.power_mod(
      unit, (field.prime - 1) / 2, field.prime)
    [valuation_bit, symbol == 1 ? 0 : 1]

  -> square?
    @vector.all? -> item == 0

  -> *(other)
    if other.class_name != "PadicSquareClass" || other.field != field
      raise "p-adic square classes belong to different fields"
    bits = []
    i = 0
    while i < @vector.size
      bits.push(@vector[i] ^ other.vector[i])
      i += 1
    PadicSquareClass.from_vector(field, bits)

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> representative
    value = @vector[0] == 1 ? field.prime : 1
    if field.prime == 2
      value = 0 - value if @vector[1] == 1
      value = value * 5 if @vector[2] == 1
    else
      value = value * field.smallest_nonsquare_unit if @vector[1] == 1
    value

  -> .from_vector(field, vector)
    if vector.class_name != "Array"
      raise "p-adic square-class vector must be an Array"
    expected = field.prime == 2 ? 3 : 2
    if vector.size != expected
      raise "p-adic square-class vector has the wrong dimension"
    representative = vector[0] == 1 ? field.prime : 1
    if field.prime == 2
      representative = 0 - representative if vector[1] == 1
      representative = representative * 5 if vector[2] == 1
    elsif vector[1] == 1
      representative = representative * field.smallest_nonsquare_unit
    PadicSquareClass.new(field.coerce(representative))


+ PadicRationalElement
  -> new(@field, value)
    if @field.class_name != "PadicField"
      raise "p-adic rational element needs a PadicField"
    @value = Rational.coerce(value)

  -> field
    @field

  -> exact_value
    @value

  -> zero?
    @value.zero?

  -> valuation
    raise "the p-adic valuation of zero is infinite" if zero?
    numerator = PadicArithmetic.integer_valuation(
      @value.numerator, @field.prime)
    denominator = PadicArithmetic.integer_valuation(
      @value.denominator, @field.prime)
    numerator - denominator

  -> unit_residue(digits = nil)
    raise "zero has no p-adic unit residue" if zero?
    use_digits = digits == nil ? @field.precision : digits
    if use_digits < 1 || use_digits > @field.precision
      raise "p-adic unit residue precision is out of range"
    prime = @field.prime
    numerator = @value.numerator
    denominator = @value.denominator
    numerator_power = PadicArithmetic.integer_valuation(
      numerator, prime)
    denominator_power = PadicArithmetic.integer_valuation(
      denominator, prime)
    numerator = numerator / prime**numerator_power
    denominator = denominator / prime**denominator_power
    modulus = prime**use_digits
    inverse = PadicArithmetic.inverse_mod(
      denominator, modulus)
    residue = numerator * inverse % modulus
    residue += modulus if residue < 0
    residue

  -> square_class
    PadicSquareClass.new(self)

  -> square?
    return true if zero?
    square_class.square?

  -> congruent?(other, absolute_precision)
    right = @field.coerce(other)
    difference = @value - right.exact_value
    return true if difference.zero?
    PadicRationalElement.new(
      @field, difference).valuation >= absolute_precision

  -> +(other)
    right = @field.coerce(other)
    PadicRationalElement.new(
      @field, @value + right.exact_value)

  -> -(other)
    right = @field.coerce(other)
    PadicRationalElement.new(
      @field, @value - right.exact_value)

  -> *(other)
    right = @field.coerce(other)
    PadicRationalElement.new(
      @field, @value * right.exact_value)

  -> /(other)
    right = @field.coerce(other)
    raise "p-adic division by zero" if right.zero?
    PadicRationalElement.new(
      @field, @value / right.exact_value)

  -> inverse
    raise "p-adic division by zero" if zero?
    PadicRationalElement.new(@field, Rational.new(1) / @value)

  -> to_s
    @value.to_s + " in Q_" + @field.prime.to_s

  -> inspect
    to_s


+ PadicHenselRootCertificate
  -> new(@root)
    @verified_cache = nil

  -> theorem
    "a simple root modulo p lifts uniquely to a root in Z_p"

  -> theorem_reference
    "simple-root Hensel lemma"

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
    return false if @root.class_name != "PadicHenselRoot"
    prime = @root.field.prime
    coefficients = @root.integer_coefficients
    derivative = PadicArithmetic.derivative_coefficients(
      coefficients)
    start = @root.starting_residue
    start_value = PadicArithmetic.evaluate_integer_polynomial(
      coefficients, start)
    return false if start_value % prime != 0
    derivative_value = PadicArithmetic.evaluate_integer_polynomial(
      derivative, start)
    return false if derivative_value % prime == 0
    final_value = PadicArithmetic.evaluate_integer_polynomial(
      coefficients, @root.residue)
    return false if final_value % @root.modulus != 0
    @root.residue % prime == start % prime

  -> certified?
    verified?

  -> proof_kind
    :trusted_hensel_theorem_with_exact_lift_replay

  -> kernel_checked?
    false

  -> arithmetic_replay_checked?
    true


+ PadicHenselRoot
  -> new(@field, @polynomial, starting_residue)
    if @field.class_name != "PadicField"
      raise "Hensel lift needs a PadicField"
    if @polynomial.class_name != "Polynomial"
      raise "Hensel lift needs a Polynomial"
    if @polynomial.ring.arity != 1
      raise "Hensel lift needs a univariate polynomial"
    if @polynomial.ring.field.class_name != "RationalField"
      raise "Hensel lift currently needs rational coefficients"
    integral = NumberField.primitive_integral_polynomial(
      @polynomial)
    @integer_coefficients = []
    integral.coefficients.each ->
      @integer_coefficients.push(item.numerator)
    @starting_residue = starting_residue % @field.prime
    @residue = lift
    @certificate_cache = PadicHenselRootCertificate.new(self)
    if !@certificate_cache.verified?
      raise "simple-root Hensel lift failed certification"

  -> field
    @field

  -> polynomial
    @polynomial

  -> integer_coefficients
    out = []
    @integer_coefficients.each -> out.push(item)
    out

  -> starting_residue
    @starting_residue

  -> precision
    @field.precision

  -> modulus
    @field.prime**precision

  -> residue
    @residue

  -> lift
    prime = @field.prime
    derivative = PadicArithmetic.derivative_coefficients(
      @integer_coefficients)
    value = PadicArithmetic.evaluate_integer_polynomial(
      @integer_coefficients, @starting_residue)
    derivative_value = PadicArithmetic.evaluate_integer_polynomial(
      derivative, @starting_residue)
    if value % prime != 0 || derivative_value % prime == 0
      raise "Hensel lift needs a simple root modulo p"
    root = @starting_residue
    current_modulus = prime
    current_precision = 1
    while current_precision < precision
      value = PadicArithmetic.evaluate_integer_polynomial(
        @integer_coefficients, root)
      quotient = value / current_modulus
      derivative_value = PadicArithmetic.evaluate_integer_polynomial(
        derivative, root)
      inverse = PadicArithmetic.inverse_mod(
        derivative_value, prime)
      correction = (0 - quotient * inverse) % prime
      correction += prime if correction < 0
      root += correction * current_modulus
      current_modulus *= prime
      current_precision += 1
    root % current_modulus

  -> evaluate_residue
    value = PadicArithmetic.evaluate_integer_polynomial(
      @integer_coefficients, @residue)
    value % modulus

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> refine(precision)
    if precision < self.precision
      raise "Hensel refinement cannot lower precision"
    PadicField.new(@field.prime, precision).hensel_root(
      @polynomial, @residue)

  -> to_s
    text = @residue.to_s + " mod " + @field.prime.to_s
    text + "^" + precision.to_s

  -> inspect
    to_s


+ PadicField
  -> new(@prime, @precision = 20)
    if !PadicArithmetic.integer?(@prime) || !@prime.prime?
      raise "p-adic field needs a prime"
    if !PadicArithmetic.integer?(@precision) || @precision < 1
      raise "p-adic precision must be positive"

  -> prime
    @prime

  -> precision
    @precision

  -> coerce(value)
    if value.class_name == "PadicRationalElement"
      if value.field != self
        raise "p-adic elements belong to different fields"
      return value
    PadicRationalElement.new(self, value)

  -> square_class(value)
    coerce(value).square_class

  -> square_class_dimension
    @prime == 2 ? 3 : 2

  -> smallest_nonsquare_unit
    if @prime == 2
      raise "2-adic square classes use the basis -1, 5, 2"
    candidate = 2
    while candidate < @prime
      symbol = PadicArithmetic.power_mod(
        candidate, (@prime - 1) / 2, @prime)
      return candidate if symbol != 1
      candidate += 1
    raise "finite field has no nonsquare unit"

  -> hensel_root(polynomial, starting_residue)
    PadicHenselRoot.new(
      self, polynomial, starting_residue)

  -> exact_rational_subfield?
    true

  -> arbitrary_completed_elements_implemented?
    false

  -> extensions_implemented?
    false

  -> to_s
    "Q_" + @prime.to_s + " (precision " + @precision.to_s + ")"

  -> inspect
    to_s


+ Algebra
  -> .p_adic_field(prime, precision = 20)
    PadicField.new(prime, precision)
