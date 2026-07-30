# Exact rational enclosures for elementary transcendental values.
#
# This is deliberately separate from Interval's binary64 branch-and-bound
# surface.  Every endpoint here is Rational, and every enclosure comes from a
# convergent series with an explicit exact remainder bound.  The analytic
# series/remainder theorems are named trusted imports; all finite arithmetic
# and the reported width are replayed.

use core/numeric/rational

+ CertifiedRealInterval
  -> new(lower, upper)
    @lower = Rational.coerce(lower)
    @upper = Rational.coerce(upper)
    if @lower > @upper
      raise "certified interval lower endpoint exceeds upper endpoint"

  -> lower_bound
    @lower

  -> upper_bound
    @upper

  -> lo
    @lower

  -> hi
    @upper

  -> width
    @upper - @lower

  -> midpoint
    (@lower + @upper) / Rational.new(2)

  -> contains?(value)
    point = Rational.coerce(value)
    point >= @lower && point <= @upper

  -> +(other)
    if other.class_name == "CertifiedRealInterval"
      return CertifiedRealInterval.new(
        @lower + other.lower_bound,
        @upper + other.upper_bound)
    scalar = Rational.coerce(other)
    CertifiedRealInterval.new(
      @lower + scalar, @upper + scalar)

  -> negate
    CertifiedRealInterval.new(0 - @upper, 0 - @lower)

  -> -@
    negate

  -> -(other)
    return self + other.negate if (
      other.class_name == "CertifiedRealInterval")
    self + (0 - Rational.coerce(other))

  -> scale(value)
    scalar = Rational.coerce(value)
    if scalar >= Rational.new(0)
      return CertifiedRealInterval.new(
        @lower*scalar, @upper*scalar)
    CertifiedRealInterval.new(
      @upper*scalar, @lower*scalar)

  -> *(other)
    if other.class_name != "CertifiedRealInterval"
      return scale(other)
    products = [
      @lower*other.lower_bound,
      @lower*other.upper_bound,
      @upper*other.lower_bound,
      @upper*other.upper_bound
    ]
    lower = products[0]
    upper = products[0]
    products.each -> (product)
      lower = product if product < lower
      upper = product if product > upper
    CertifiedRealInterval.new(lower, upper)

  -> reciprocal
    zero = Rational.new(0)
    if @lower <= zero && @upper >= zero
      raise "certified interval reciprocal contains zero"
    CertifiedRealInterval.new(
      Rational.new(1) / @upper,
      Rational.new(1) / @lower)

  -> /(other)
    if other.class_name == "CertifiedRealInterval"
      return self*other.reciprocal
    scale(Rational.new(1) / Rational.coerce(other))

  -> intersect(lower, upper)
    left = Rational.coerce(lower)
    right = Rational.coerce(upper)
    left = @lower if @lower > left
    right = @upper if @upper < right
    if left > right
      raise "certified interval intersection is empty"
    CertifiedRealInterval.new(left, right)

  -> ==(other)
    return false if other == nil
    return false if other.class_name != "CertifiedRealInterval"
    @lower == other.lower_bound && @upper == other.upper_bound

  -> eql?(other)
    self == other

  -> to_s
    '[' + @lower.to_s + ', ' + @upper.to_s + ']'

  -> inspect
    to_s


+ CertifiedTranscendentalValue
  -> new(@function, arguments, @tolerance,
         @term_limit, interval)
    @arguments = []
    arguments.each -> (argument)
      @arguments.push(Rational.coerce(argument))
    @tolerance = Rational.coerce(@tolerance)
    if @tolerance <= Rational.new(0)
      raise "certified transcendental tolerance must be positive"
    @interval = interval
    @certificate = CertifiedTranscendentalCertificate.new(self)
    if !@certificate.verified?
      raise "certified transcendental enclosure failed replay"

  -> function
    @function

  -> arguments
    out = []
    @arguments.each -> out.push(item)
    out

  -> tolerance
    @tolerance

  -> term_limit
    @term_limit

  -> interval
    @interval

  -> lower_bound
    @interval.lower_bound

  -> upper_bound
    @interval.upper_bound

  -> width
    @interval.width

  -> midpoint
    @interval.midpoint

  -> contains?(value)
    @interval.contains?(value)

  -> approximate
    midpoint.to_f

  -> certificate
    @certificate

  -> certified?
    @certificate.verified?

  -> to_s
    @function.to_s + arguments.to_s + " in " + @interval.to_s

  -> inspect
    to_s


+ CertifiedTranscendentals
  -> .default_tolerance
    Rational.new(1, 10**20)

  -> .require_limit(limit)
    value_class = limit.class
    integral = (
      value_class == Integer ||
      value_class == Int ||
      value_class == BigInt)
    if !integral || limit < 1
      raise "certified transcendental term limit must be positive"
    limit

  -> .absolute(value)
    rational = Rational.coerce(value)
    rational < Rational.new(0) ? 0 - rational : rational

  -> .between_sum_and_remainder(sum, signed_remainder)
    endpoint = sum + signed_remainder
    if endpoint < sum
      return CertifiedRealInterval.new(endpoint, sum)
    CertifiedRealInterval.new(sum, endpoint)

  # Positive Taylor terms.  After summing through x^n/n!, the remaining
  # ratios are bounded by x/(n+2), hence
  #   R_n <= next_term / (1 - x/(n+2)).
  -> .exp_positive_raw(value, tolerance, term_limit)
    x = Rational.coerce(value)
    zero = Rational.new(0)
    one = Rational.new(1)
    raise "positive exponential helper needs x >= 0" if x < zero
    return CertifiedRealInterval.new(one, one) if x == zero
    sum = one
    term = one
    n = 0
    while n < term_limit
      n += 1
      term = term*x / Rational.new(n)
      sum += term
      next_term = term*x / Rational.new(n + 1)
      if Rational.new(n + 2) > x
        remainder = (
          next_term*Rational.new(n + 2) /
          (Rational.new(n + 2) - x))
        if remainder <= tolerance
          return CertifiedRealInterval.new(
            sum, sum + remainder)
    raise "certified exp unknown: Taylor term limit exceeded"

  -> .exp_raw(value, tolerance, term_limit)
    x = Rational.coerce(value)
    if x < Rational.new(0)
      return CertifiedTranscendentals.exp_positive_raw(
        0 - x, tolerance, term_limit).reciprocal
    CertifiedTranscendentals.exp_positive_raw(
      x, tolerance, term_limit)

  # log(x) = 2 atanh((x-1)/(x+1)).  For |y|<1, the omitted tail after
  # n terms is at most
  #   2 |y|^(2n+1) / ((2n+1)(1-y^2)).
  -> .log_atanh_raw(value, tolerance, term_limit)
    x = Rational.coerce(value)
    one = Rational.new(1)
    zero = Rational.new(0)
    raise "certified log needs a positive argument" if x <= zero
    y = (x - one) / (x + one)
    absolute_y = CertifiedTranscendentals.absolute(y)
    return CertifiedRealInterval.new(zero, zero) if absolute_y.zero?
    y_squared = y*y
    power = y
    sum = zero
    terms = 0
    while terms < term_limit
      denominator = 2*terms + 1
      sum += Rational.new(2)*power / Rational.new(denominator)
      terms += 1
      next_denominator = 2*terms + 1
      next_power = power*y_squared
      remainder = (
        Rational.new(2)*
        CertifiedTranscendentals.absolute(next_power) /
        (Rational.new(next_denominator)*(one - y_squared)))
      if remainder <= tolerance
        signed = y < zero ? 0 - remainder : remainder
        return CertifiedTranscendentals.between_sum_and_remainder(
          sum, signed)
      power = next_power
    raise "certified log unknown: atanh term limit exceeded"

  # Exact powers-of-two range reduction keeps the atanh parameter at most
  # 1/3 in magnitude.  Component tolerances account for the integer multiple
  # of log(2), so the final width remains below the requested tolerance.
  -> .log_raw(value, tolerance, term_limit)
    x = Rational.coerce(value)
    zero = Rational.new(0)
    one = Rational.new(1)
    two = Rational.new(2)
    raise "certified log needs a positive argument" if x <= zero
    return CertifiedRealInterval.new(zero, zero) if x == one
    normalized = x
    exponent = 0
    while normalized >= two
      normalized /= two
      exponent += 1
      if exponent > term_limit
        raise "certified log unknown: range-reduction limit exceeded"
    half = Rational.new(1, 2)
    while normalized < half
      normalized *= two
      exponent -= 1
      if 0 - exponent > term_limit
        raise "certified log unknown: range-reduction limit exceeded"
    error_parts = exponent.abs + 1
    component_tolerance = tolerance / Rational.new(error_parts)
    normalized_log = CertifiedTranscendentals.log_atanh_raw(
      normalized, component_tolerance, term_limit)
    return normalized_log if exponent == 0
    log_two = CertifiedTranscendentals.log_atanh_raw(
      two, component_tolerance, term_limit)
    normalized_log + log_two.scale(exponent)

  -> .sin_raw(value, tolerance, term_limit)
    x = Rational.coerce(value)
    zero = Rational.new(0)
    if x < zero
      return CertifiedTranscendentals.sin_raw(
        0 - x, tolerance, term_limit).negate
    return CertifiedRealInterval.new(zero, zero) if x == zero
    x_squared = x*x
    term = x
    sum = zero
    index = 0
    while index < term_limit
      sum += term
      next_term = (
        (0 - term)*x_squared /
        Rational.new((2*index + 2)*(2*index + 3)))
      decreasing = (
        CertifiedTranscendentals.absolute(next_term) <=
        CertifiedTranscendentals.absolute(term))
      if (decreasing &&
          CertifiedTranscendentals.absolute(next_term) <= tolerance)
        return (
          CertifiedTranscendentals.between_sum_and_remainder(
            sum, next_term).intersect(-1, 1))
      term = next_term
      index += 1
    raise "certified sin unknown: Taylor term limit exceeded"

  -> .cos_raw(value, tolerance, term_limit)
    x = CertifiedTranscendentals.absolute(value)
    zero = Rational.new(0)
    one = Rational.new(1)
    return CertifiedRealInterval.new(one, one) if x == zero
    x_squared = x*x
    term = one
    sum = zero
    index = 0
    while index < term_limit
      sum += term
      next_term = (
        (0 - term)*x_squared /
        Rational.new((2*index + 1)*(2*index + 2)))
      decreasing = (
        CertifiedTranscendentals.absolute(next_term) <=
        CertifiedTranscendentals.absolute(term))
      if (decreasing &&
          CertifiedTranscendentals.absolute(next_term) <= tolerance)
        return (
          CertifiedTranscendentals.between_sum_and_remainder(
            sum, next_term).intersect(-1, 1))
      term = next_term
      index += 1
    raise "certified cos unknown: Taylor term limit exceeded"

  -> .atan_small_raw(value, tolerance, term_limit)
    x = Rational.coerce(value)
    absolute_x = CertifiedTranscendentals.absolute(x)
    if absolute_x > Rational.new(1, 2)
      raise "small arctangent helper needs |x| <= 1/2"
    zero = Rational.new(0)
    return CertifiedRealInterval.new(zero, zero) if x == zero
    x_squared = x*x
    term = x
    sum = zero
    index = 0
    while index < term_limit
      sum += term / Rational.new(2*index + 1)
      next_term = 0 - term*x_squared
      next_signed = next_term / Rational.new(2*index + 3)
      if CertifiedTranscendentals.absolute(next_signed) <= tolerance
        return CertifiedTranscendentals.between_sum_and_remainder(
          sum, next_signed)
      term = next_term
      index += 1
    raise "certified atan unknown: Taylor term limit exceeded"

  # Machin's identity:
  #   pi = 16 atan(1/5) - 4 atan(1/239).
  -> .pi_raw(tolerance, term_limit)
    component_tolerance = tolerance / Rational.new(20)
    first = CertifiedTranscendentals.atan_small_raw(
      Rational.new(1, 5), component_tolerance, term_limit)
    second = CertifiedTranscendentals.atan_small_raw(
      Rational.new(1, 239), component_tolerance, term_limit)
    first.scale(16) - second.scale(4)

  -> .atan_raw(value, tolerance, term_limit)
    x = Rational.coerce(value)
    zero = Rational.new(0)
    return CertifiedRealInterval.new(zero, zero) if x == zero
    if x < zero
      return CertifiedTranscendentals.atan_raw(
        0 - x, tolerance, term_limit).negate
    half = Rational.new(1, 2)
    two = Rational.new(2)
    if x <= half
      return CertifiedTranscendentals.atan_small_raw(
        x, tolerance, term_limit)
    component_tolerance = tolerance / Rational.new(2)
    pi = CertifiedTranscendentals.pi_raw(
      component_tolerance, term_limit)
    if x <= two
      transformed = (x - Rational.new(1)) / (x + Rational.new(1))
      local = CertifiedTranscendentals.atan_small_raw(
        transformed, component_tolerance, term_limit)
      return pi.scale(Rational.new(1, 4)) + local
    local = CertifiedTranscendentals.atan_small_raw(
      Rational.new(1) / x, component_tolerance, term_limit)
    pi.scale(Rational.new(1, 2)) - local

  -> .produce(function, arguments, tolerance, term_limit)
    value = arguments.size == 0 ? nil : arguments[0]
    if function == :exp
      return CertifiedTranscendentals.exp_raw(
        value, tolerance, term_limit)
    if function == :log
      return CertifiedTranscendentals.log_raw(
        value, tolerance, term_limit)
    if function == :sin
      return CertifiedTranscendentals.sin_raw(
        value, tolerance, term_limit)
    if function == :cos
      return CertifiedTranscendentals.cos_raw(
        value, tolerance, term_limit)
    if function == :atan
      return CertifiedTranscendentals.atan_raw(
        value, tolerance, term_limit)
    if function == :pi
      return CertifiedTranscendentals.pi_raw(
        tolerance, term_limit)
    raise "unsupported certified transcendental function"

  -> .build(function, arguments, tolerance, term_limit)
    CertifiedTranscendentals.require_limit(term_limit)
    exact_tolerance = Rational.coerce(tolerance)
    if exact_tolerance <= Rational.new(0)
      raise "certified transcendental tolerance must be positive"
    interval = CertifiedTranscendentals.produce(
      function, arguments, exact_tolerance, term_limit)
    CertifiedTranscendentalValue.new(
      function, arguments, exact_tolerance, term_limit, interval)

  -> .requested_tolerance(tolerance)
    tolerance == nil ? CertifiedTranscendentals.default_tolerance : tolerance

  -> .exp(value, tolerance = nil, term_limit = 10_000)
    requested = CertifiedTranscendentals.requested_tolerance(
      tolerance)
    CertifiedTranscendentals.build(
      :exp, [value], requested, term_limit)

  -> .log(value, tolerance = nil, term_limit = 10_000)
    requested = CertifiedTranscendentals.requested_tolerance(
      tolerance)
    CertifiedTranscendentals.build(
      :log, [value], requested, term_limit)

  -> .sin(value, tolerance = nil, term_limit = 10_000)
    requested = CertifiedTranscendentals.requested_tolerance(
      tolerance)
    CertifiedTranscendentals.build(
      :sin, [value], requested, term_limit)

  -> .cos(value, tolerance = nil, term_limit = 10_000)
    requested = CertifiedTranscendentals.requested_tolerance(
      tolerance)
    CertifiedTranscendentals.build(
      :cos, [value], requested, term_limit)

  -> .atan(value, tolerance = nil, term_limit = 10_000)
    requested = CertifiedTranscendentals.requested_tolerance(
      tolerance)
    CertifiedTranscendentals.build(
      :atan, [value], requested, term_limit)

  -> .pi(tolerance = nil, term_limit = 10_000)
    requested = CertifiedTranscendentals.requested_tolerance(
      tolerance)
    CertifiedTranscendentals.build(
      :pi, [], requested, term_limit)

  -> .e(tolerance = nil, term_limit = 10_000)
    CertifiedTranscendentals.exp(
      Rational.new(1), tolerance, term_limit)


+ CertifiedTranscendentalCertificate
  -> new(@value)
    @verified_cache = nil

  -> value
    @value

  -> theorem
    "exact rational transcendental enclosure with explicit series remainder"

  -> theorem_reference
    ("Taylor theorem, alternating-series bound, atanh log series, " +
     "and Machin's formula")

  -> proof_kind
    :trusted_theorem_import

  -> kernel_checked?
    false

  -> arithmetic_replay_checked?
    verified?

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
    if @value.class_name != "CertifiedTranscendentalValue"
      return false
    return false if @value.tolerance <= Rational.new(0)
    expected = CertifiedTranscendentals.produce(
      @value.function, @value.arguments,
      @value.tolerance, @value.term_limit)
    return false if expected != @value.interval
    @value.width <= @value.tolerance

  -> certified?
    verified?

  -> to_s
    ("CertifiedTranscendentalCertificate(" +
      @value.function.to_s + ", width=" +
      @value.width.to_s + ")")

  -> inspect
    to_s
