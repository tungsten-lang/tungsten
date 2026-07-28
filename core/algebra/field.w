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
  -> coerce(value)
    raise "Field#coerce is not implemented for " + self.class_name

  -> zero
    raise "Field#zero is not implemented for " + self.class_name

  -> one
    raise "Field#one is not implemented for " + self.class_name

  -> equal?(left, right)
    coerce(left) == coerce(right)

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
    raise "unsupported coefficient field: " + text

  -> .supported?(field)
    field != nil && field.class_name == "RationalField"

  -> .require_supported(field)
    raise "unsupported coefficient field: nil" if field == nil
    if !Field.supported?(field)
      raise "unsupported coefficient field: " + field.class_name
    field


+ RationalField < Field
  -> coerce(value)
    Rational.coerce(value)

  -> zero
    Rational.new(0)

  -> one
    Rational.new(1)

  -> equal?(left, right)
    coerce(left) == coerce(right)

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
