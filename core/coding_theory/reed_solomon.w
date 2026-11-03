# Exact Reed-Solomon evaluation codes over an explicitly ordered finite-field
# domain.  Messages are coefficient Arrays in ascending degree order.  The
# degree bound may exceed the domain size: in that case encoding remains
# defined, but the encoder is not injective and the code dimension saturates at
# the block length.

+ ReedSolomonCode
  -> new(domain, degree_bound)
    if domain == nil || domain.class_name != "FiniteFieldEvaluationDomain"
      raise "Reed-Solomon codes require a FiniteFieldEvaluationDomain"
    @domain = domain
    @field = domain.field
    @degree_bound = CodingTheorySupport.require_nonnegative_integer(
      degree_bound, "Reed-Solomon degree bound")
    self

  ro :domain, :field, :degree_bound

  -> length
    @domain.size

  -> size
    length

  -> dimension
    @degree_bound < length ? @degree_bound : length

  -> encoder_injective?
    @degree_bound <= length

  -> zero_code?
    dimension == 0

  -> minimum_distance
    zero_code? ? 0 : length - dimension + 1

  -> rate
    Rational.new(dimension, length)

  -> normalize_message(coefficients)
    if coefficients.class_name != "Array"
      raise "Reed-Solomon message must be an Array"
    if coefficients.size != @degree_bound
      raise "Reed-Solomon message length must equal the degree bound"
    CodingTheorySupport.coerce_elements(
      @field, coefficients, "Reed-Solomon coefficient")

  -> normalize_message_raw(coefficients)
    if coefficients.class_name != "Array"
      raise "Reed-Solomon message must be an Array"
    if coefficients.size != @degree_bound
      raise "Reed-Solomon message length must equal the degree bound"
    CodingTheorySupport.normalize_elements(
      @field, coefficients, "Reed-Solomon coefficient")

  -> message_polynomial(coefficients)
    coefficients = normalize_message(coefficients)
    __polynomial_from_raw(coefficients)

  -> message_polynomial_raw(coefficients)
    coefficients = normalize_message_raw(coefficients)
    __polynomial_from_raw(coefficients)

  -> __polynomial_from_raw(coefficients)
    ring = PolynomialRing.new([:x], @field)
    terms = []
    degree = 0
    while degree < coefficients.size
      coefficient = coefficients[degree]
      if !@field.zero?(coefficient)
        terms.push([coefficient, [degree]])
      degree += 1
    Polynomial.new(ring, terms)

  -> encode(coefficients)
    __encode_normalized(normalize_message(coefficients))

  -> encode_raw(coefficients)
    __encode_normalized(normalize_message_raw(coefficients))

  -> __encode_normalized(coefficients)
    symbols = []
    position = 0
    while position < length
      x = @domain.at(position)
      value = @field.zero
      degree = coefficients.size - 1
      while degree >= 0
        value = @field.add(
          @field.multiply(value, x), coefficients[degree])
        degree -= 1
      symbols.push(value)
      position += 1
    FiniteFieldCodeword.raw(@field, symbols)

  -> encode_polynomial(polynomial)
    if polynomial == nil || polynomial.class_name != "Polynomial"
      raise "Reed-Solomon evaluation expects a Polynomial"
    if polynomial.ring.arity != 1
      raise "Reed-Solomon evaluation expects a univariate polynomial"
    if polynomial.ring.field != @field
      raise "Reed-Solomon polynomial belongs to a different field"
    if !polynomial.zero? && polynomial.degree >= @degree_bound
      raise "Reed-Solomon polynomial exceeds the degree bound"
    symbols = []
    position = 0
    while position < length
      symbols.push(polynomial.at_raw(@domain.at(position)))
      position += 1
    FiniteFieldCodeword.raw(@field, symbols)

  # Exact membership by Newton interpolation on the first degree_bound
  # coordinates, followed by evaluation on the remaining coordinates.  When
  # the degree bound saturates the domain, every ambient word is a member.
  -> contains?(word)
    return false if word == nil || word.class_name != "FiniteFieldCodeword"
    return false if word.field != @field || word.size != length
    if @degree_bound == 0
      position = 0
      while position < length
        return false if !@field.zero?(word.at(position))
        position += 1
      return true
    return true if @degree_bound >= length

    coefficients = []
    i = 0
    while i < @degree_bound
      coefficients.push(word.at(i))
      i += 1
    order = 1
    while order < @degree_bound
      i = @degree_bound - 1
      while i >= order
        numerator = @field.subtract(coefficients[i], coefficients[i - 1])
        denominator = @field.subtract(
          @domain.at(i), @domain.at(i - order))
        coefficients[i] = @field.divide(numerator, denominator)
        i -= 1
      order += 1

    position = @degree_bound
    while position < length
      value = coefficients[@degree_bound - 1]
      i = @degree_bound - 2
      while i >= 0
        value = @field.add(
          coefficients[i],
          @field.multiply(
            @field.subtract(@domain.at(position), @domain.at(i)), value))
        i -= 1
      return false if !@field.equal?(value, word.at(position))
      position += 1
    true

  -> include?(word)
    contains?(word)

  -> codeword(symbols)
    word = FiniteFieldCodeword.new(@field, symbols)
    __require_codeword(word)

  -> codeword_raw(symbols)
    word = FiniteFieldCodeword.raw(@field, symbols)
    __require_codeword(word)

  -> __require_codeword(word)
    if word.size != length
      raise "Reed-Solomon codeword length does not match the domain"
    if !contains?(word)
      raise "word is not a member of the Reed-Solomon code"
    word

  -> to_s
    text = "ReedSolomonCode(length=" + length.to_s
    text += ", degree_bound=" + @degree_bound.to_s
    text += ", dimension=" + dimension.to_s + ")"
    text

  -> inspect
    to_s
