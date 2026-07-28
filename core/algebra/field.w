# Coefficient fields for exact algebra.
#
# Field belongs under core/algebra rather than the numeric tower: it describes
# operations on a coefficient domain, not one scalar representation. Concrete
# implementations may use core numeric values (RationalField does), extension
# elements, or finite-field elements.
#
# This base class is the executable Field protocol. Its capability errors keep
# a partially implemented field from silently behaving like the rationals.
+ Field
  # Concrete coefficient domains opt in explicitly. New field
  # implementations register here through behavior, not a central class-name
  # list; the abstract Field itself remains unsupported.
  -> coefficient_field?
    false

  -> coerce(value)
    raise "Field#coerce is not implemented for " + self.class_name

  # External scalar coercion and internal element normalization differ for
  # extension fields whose elements are packed into one Integer.
  -> normalize_element(value)
    coerce(value)

  -> zero
    raise "Field#zero is not implemented for " + self.class_name

  -> one
    raise "Field#one is not implemented for " + self.class_name

  -> zero?(value)
    equal?(value, zero)

  -> one?(value)
    equal?(value, one)

  -> equal?(left, right)
    normalize_element(left) == normalize_element(right)

  -> add(left, right)
    normalize_element(left) + normalize_element(right)

  -> subtract(left, right)
    add(left, negate(right))

  -> negate(value)
    normalize_element(value).negate

  -> multiply(left, right)
    normalize_element(left) * normalize_element(right)

  -> inverse(value)
    one / normalize_element(value)

  -> divide(left, right)
    multiply(left, inverse(right))

  -> power(value, exponent)
    return power(inverse(value), 0 - exponent) if exponent < 0
    result = one
    factor = normalize_element(value)
    remaining = exponent
    while remaining > 0
      result = multiply(result, factor) if remaining.odd?
      remaining = remaining / 2
      factor = multiply(factor, factor) if remaining > 0
    result

  -> negative?(value)
    normalize_element(value).negative?

  -> element_to_s(value)
    normalize_element(value).to_s

  -> exact?
    raise "Field#exact? is not implemented for " + self.class_name

  -> characteristic
    raise "Field#characteristic is not implemented for " + self.class_name

  -> normalize_projective_coordinates(coordinates)
    raise "projective normalization is not implemented over " + to_s

  -> .rational
    RationalField.new

  -> .for(name)
    text = name.to_s
    if text == "ℚ" || text == "Q" || text == "RationalField" || text == "rational"
      return RationalField.new
    if text.starts_with?("𝔽_") || text.starts_with?("F_")
      pieces = text.split("_")
      return FiniteField.new(pieces[pieces.size - 1].to_i)
    raise "unsupported coefficient field: " + text

  -> .supported?(field)
    return false if field == nil
    return false if !field.respond_to?("coefficient_field?")
    field.coefficient_field?

  -> .require_supported(field)
    raise "unsupported coefficient field: nil" if field == nil
    if !Field.supported?(field)
      raise "unsupported coefficient field: " + field.class_name
    field


+ RationalField < Field
  -> coefficient_field?
    true

  -> coerce(value)
    Rational.coerce(value)

  -> normalize_element(value)
    coerce(value)

  -> zero
    Rational.new(0)

  -> one
    Rational.new(1)

  -> zero?(value)
    coerce(value).zero?

  -> one?(value)
    coerce(value).one?

  -> equal?(left, right)
    coerce(left) == coerce(right)

  # Explicit arithmetic: Tungsten does not yet dispatch Field defaults through
  # every subclass method table, so the hot polynomial path needs these on
  # RationalField itself as well as on FiniteField.
  -> add(left, right)
    coerce(left) + coerce(right)

  -> subtract(left, right)
    coerce(left) - coerce(right)

  -> negate(value)
    coerce(value).negate

  -> multiply(left, right)
    coerce(left) * coerce(right)

  -> inverse(value)
    one / coerce(value)

  -> divide(left, right)
    coerce(left) / coerce(right)

  -> power(value, exponent)
    coerce(value) ** exponent

  -> negative?(value)
    coerce(value).negative?

  -> element_to_s(value)
    rational = coerce(value)
    return rational.numerator.to_s if rational.denominator == 1
    rational.to_s

  -> exact?
    true

  -> characteristic
    0

  -> ==(other)
    other != nil && other.class_name == "RationalField"

  # Pick the unique primitive integral representative whose first nonzero
  # coordinate is positive. Clearing denominators before the gcd makes
  # integer and fractional input follow the same canonical path:
  #
  #   [2:0:0]       -> [1:0:0]
  #   [1/2:-1/3:0]  -> [3:-2:0]
  -> normalize_projective_coordinates(coordinates)
    raise "projective coordinates need at least one entry" if coordinates.size == 0

    values = []
    all_zero = true
    coordinates.each -> (coordinate)
      value = coerce(coordinate)
      values.push(value)
      all_zero = false if !equal?(value, zero)
    raise "projective coordinates cannot all be zero" if all_zero

    # These accumulators must retain arbitrary precision when coordinates use
    # the heap-backed Rational tier.
    common = 1 ## big
    values.each -> (value)
      denominator = value.denominator
      common = (common / common.gcd(denominator)) * denominator

    integers = []
    values.each -> (value)
      integers.push(value.numerator * (common / value.denominator))

    divisor = 0 ## big
    integers.each -> (value)
      divisor = divisor.gcd(value.abs)
    integers = integers.map -> item / divisor

    i = 0
    while i < integers.size
      if integers[i] != 0
        if integers[i] < 0
          integers = integers.map -> 0 - item
        return integers
      i += 1
    # The all-zero case was rejected above; this is an invariant guard for a
    # future field implementation that supplies nonstandard equality.
    raise "projective normalization produced the zero tuple"

  -> to_s
    "ℚ"

  -> inspect
    to_s
