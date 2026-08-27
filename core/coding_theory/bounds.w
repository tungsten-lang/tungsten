# Numerical Johnson-radius transforms.  These return approximate Floats and
# do not construct a decoder, bound a finite list size, or verify a theorem.

+ JohnsonBound
  -> .supported_real?(value)
    return true if CodingTheorySupport.integer?(value)
    name = value.class_name
    return true if name == "Rational" || name == "Float" || name == "BF16"
    return true if name.starts_with?("Float")
    name == "Decimal" || name.starts_with?("Decimal")

  -> .unit_interval(value, label)
    if !JohnsonBound.supported_real?(value)
      raise label + " must be a real numeric value"
    number = value.to_f
    if number.nan? || number.infinite?
      raise label + " must be finite"
    if number < ~0.0 || number > ~1.0
      raise label + " must lie between zero and one"
    number

  -> .exceeds_boundary?(original, approximate, exact_boundary)
    name = original.class_name
    if CodingTheorySupport.integer?(original) || name == "Rational"
      return Rational.coerce(original) > exact_boundary
    approximate > exact_boundary.to_f

  # Alphabet-independent asymptotic capacity form 1 - sqrt(1-delta).
  -> .capacity_radius(relative_distance)
    delta = JohnsonBound.unit_interval(
      relative_distance, "relative distance")
    delta / (~1.0 + Math.sqrt(~1.0 - delta))

  -> .q_ary_radius(alphabet_size, relative_distance)
    CodingTheorySupport.require_integer(alphabet_size, "alphabet size")
    raise "alphabet size must be at least two" if alphabet_size < 2
    delta = JohnsonBound.unit_interval(
      relative_distance, "relative distance")
    boundary = Rational.new(alphabet_size - 1, alphabet_size)
    if JohnsonBound.exceeds_boundary?(
      relative_distance, delta, boundary)
      raise "q-ary Johnson radius has a negative radicand"
    scale = ~1.0 - Rational.new(1, alphabet_size).to_f
    radicand = ~1.0 - delta / scale
    # The exact domain check above makes a small negative value roundoff, not
    # an out-of-domain request (notably at delta=(q-1)/q).
    radicand = ~0.0 if radicand < ~0.0
    delta / (~1.0 + Math.sqrt(radicand))

  -> .finite_list_radius(alphabet_size, list_size, relative_distance)
    CodingTheorySupport.require_integer(alphabet_size, "alphabet size")
    CodingTheorySupport.require_integer(list_size, "list size")
    raise "alphabet size must be at least two" if alphabet_size < 2
    raise "finite-list Johnson radius requires list size at least two" if list_size < 2
    delta = JohnsonBound.unit_interval(
      relative_distance, "relative distance")
    boundary = Rational.new(
      (alphabet_size - 1) * list_size,
      alphabet_size * (list_size - 1))
    if JohnsonBound.exceeds_boundary?(
      relative_distance, delta, boundary)
      raise "finite-list Johnson radius has a negative radicand"
    scale = ~1.0 - Rational.new(1, alphabet_size).to_f
    list_factor = ~1.0 - Rational.new(1, list_size).to_f
    adjusted = list_factor * delta
    radicand = ~1.0 - adjusted / scale
    radicand = ~0.0 if radicand < ~0.0
    adjusted / (~1.0 + Math.sqrt(radicand))

  # The asymptotic MDS rate boundary 1 - sqrt(rate).  A finite Reed-Solomon
  # code's capacity_radius(minimum_distance/length) includes its finite-length
  # correction and is generally different.
  -> .mds_asymptotic_radius(rate)
    value = JohnsonBound.unit_interval(rate, "MDS rate")
    (~1.0 - value) / (~1.0 + Math.sqrt(value))
