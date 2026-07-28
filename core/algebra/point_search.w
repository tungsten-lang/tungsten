# Exact rational-point search for a monotone family of plane quartics.
#
# This is deliberately a certified, narrow capability rather than a generic
# "try some boxes" routine.  After clearing denominators and primitive-part
# normalization, the supported equations are
#
#   a X^3 Z + b X Y^2 Z
#     + c0 Y^4 + c1 Y^3 Z + c2 Y^2 Z^2 + c3 Y Z^3 + c4 Z^4 = 0,
#
# with a and b nonzero and of the same sign, and c0 nonzero.  Multiplying the
# equation by -1 lets us take a,b > 0.  For fixed (Y,Z) with Z > 0, the
# polynomial in X has positive derivative
#
#   Z (3 a X^2 + b Y^2),
#
# so it has at most one integral root.
#
# Two exact sieves make a height search practical:
#
# * reducing modulo Z gives Z | c0 Y^4;
# * if d = gcd(Y,Z), primitivity forces gcd(X,d)=1.  Dividing the equation by
#   d and reducing modulo d^2 then gives d^2 | a (Z/d).
#
# Small-prime masks reject pairs for which the equation has no X-root even
# modulo p.  Surviving cubics are isolated with integer Newton iteration and
# checked by exact substitution.  No floating-point approximation or fixture
# lookup participates in the result.

+ MonotoneQuarticPointSearch
  -> new(@curve, @height)
    validate_height
    extract_primitive_integral_model
    validate_supported_family
    @smallest_prime_factor = build_smallest_prime_factor_table
    @modular_sieves = build_modular_sieves

  -> validate_height
    kind = @height.class_name
    if kind != "Integer" && kind != "Int" && kind != "BigInt"
      raise "rational point height must be an integer"
    raise "rational point height must be positive" if @height <= 0
    # Array indices and capacities are u32.  Keep the +1 used by the SPF table
    # representable as an ordinary native index rather than failing later in a
    # storage primitive.
    if @height > 4_294_967_294
      raise "rational point height exceeds the exact search index range"

  -> extract_primitive_integral_model
    if @curve.field.class_name != "RationalField"
      raise "rational_points currently requires a curve over ℚ"
    if @curve.space.dimension != 2 || @curve.degree != 4
      raise "rational_points currently supports plane quartics"

    terms = []
    denominator_lcm = 1 ## big
    @curve.equation.each_term -> (coefficient, exponents)
      rational = Rational.coerce(coefficient)
      denominator_lcm = denominator_lcm.lcm(rational.denominator)
      terms.push([rational, exponents])

    integral_terms = []
    content = 0 ## big
    terms.each -> (term)
      coefficient = term[0].numerator * (denominator_lcm / term[0].denominator)
      integral_terms.push([coefficient, term[1]])
      content = content.gcd(coefficient.abs)
    raise "rational_points cannot search the zero equation" if content == 0

    @a = 0 ## big
    @b = 0 ## big
    @g = [0 ## big, 0 ## big, 0 ## big, 0 ## big, 0 ## big]
    unsupported = false
    integral_terms.each -> (term)
      coefficient = term[0] / content
      powers = term[1]
      if powers[0] == 3 && powers[1] == 0 && powers[2] == 1
        @a = coefficient
      elsif powers[0] == 1 && powers[1] == 2 && powers[2] == 1
        @b = coefficient
      elsif powers[0] == 0 && powers[1] + powers[2] == 4
        @g[powers[2]] = coefficient
      else
        unsupported = true
      @unsupported_monomial = unsupported

  -> validate_supported_family
    if @unsupported_monomial
      raise "rational_points supports only a X^3 Z + b X Y^2 Z + g(Y,Z)"
    if @a == 0 || @b == 0 || (@a < 0) != (@b < 0)
      raise "rational_points requires nonzero a and b of the same sign"
    if @g[0] == 0
      raise "rational_points requires a nonzero Y^4 coefficient"

    # The equation itself is only defined up to a nonzero scalar.  Choose the
    # sign that makes the monotone cubic increasing.
    if @a < 0
      @a = 0 - @a
      @b = 0 - @b
      i = 0
      while i < @g.size
        @g[i] = 0 - @g[i]
        i += 1

  -> build_smallest_prime_factor_table
    table = []
    index = 0
    while index <= @height
      table.push(0)
      index += 1
    prime = 2
    while prime * prime <= @height
      if table[prime] == 0
        multiple = prime * prime
        while multiple <= @height
          table[multiple] = prime if table[multiple] == 0
          multiple += prime
      prime += 1
    table

  # The fixed list is not curve data: each entry supplies an independent
  # necessary congruence for every integral point on every supported model.
  # Ordering smaller primes first minimizes the average number of mask probes.
  -> modular_sieve_primes
    [7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43]

  -> mod_normalize(value, modulus)
    reduced = value % modulus
    reduced < 0 ? reduced + modulus : reduced

  -> build_modular_sieves
    sieves = []
    modular_sieve_primes.each -> (prime)
      aa = mod_normalize(@a, prime)
      bb = mod_normalize(@b, prime)
      gg = []
      @g.each -> gg.push(mod_normalize(item, prime))
      mask = []
      mask_index = 0
      while mask_index < prime * prime
        mask.push(false)
        mask_index += 1

      yr = 0
      while yr < prime
        y2 = yr * yr % prime
        y3 = y2 * yr % prime
        y4 = y2 * y2 % prime
        zr = 0
        while zr < prime
          z2 = zr * zr % prime
          z3 = z2 * zr % prime
          z4 = z2 * z2 % prime
          constant = (gg[0] * y4 +
                      gg[1] * y3 % prime * zr +
                      gg[2] * y2 % prime * z2 +
                      gg[3] * yr % prime * z3 +
                      gg[4] * z4) % prime
          linear = bb * y2 % prime * zr % prime
          cubic = aa * zr % prime

          xr = 0
          while xr < prime
            value = (cubic * xr % prime * xr % prime * xr +
                     linear * xr + constant) % prime
            if value == 0
              mask[yr * prime + zr] = true
              break
            xr += 1
          zr += 1
        yr += 1
      sieves.push([prime, mask])
    sieves

  -> passes_modular_sieves?(y, z)
    i = 0
    while i < @modular_sieves.size
      sieve = @modular_sieves[i]
      prime = sieve[0]
      yr = mod_normalize(y, prime)
      zr = z % prime
      return false if !sieve[1][yr * prime + zr]
      i += 1
    true

  # Least m > 0 for which z | c0 m^4.  If e=v_p(z) and k=v_p(c0), m needs
  # p^ceil(max(e-k,0)/4); factoring z/gcd(z,c0) computes exactly that.
  -> minimum_y_step(z)
    remaining = z / z.gcd(@g[0].abs)
    step = 1
    while remaining > 1
      prime = @smallest_prime_factor[remaining]
      prime = remaining if prime == 0
      exponent = 0
      while remaining % prime == 0
        remaining = remaining / prime
        exponent += 1
      required = (exponent + 3) / 4
      while required > 0
        step *= prime
        required -= 1
    step

  -> integer_cube_root(value)
    raise "integer cube root needs a nonnegative integer" if value < 0
    return value if value < 2

    # 2^ceil(bit_length/3) is an exact upper bound.  Newton iteration for
    # x^3-value decreases to floor(cuberoot(value)).
    x = 2 ** ((value.bit_length + 2) / 3)
    y = (2 * x + value / (x * x)) / 3
    while y < x
      x = y
      y = (2 * x + value / (x * x)) / 3
    x

  -> scan_infinity(points)
    # Z=0 leaves c0 Y^4=0.  Since c0 != 0, Y=0 and there is exactly the
    # primitive projective point [1:0:0].
    points.push(@curve.space.point(1, 0, 0))

  -> scan_y_zero(points)
    constant = @g[4]
    if constant == 0
      points.push(@curve.space.point(0, 0, 1))
      return nil

    # a X^3 + c4 Z^3=0 has a rational solution exactly when the reduced
    # fraction -c4/a is a rational cube.
    numerator = 0 - constant
    sign = numerator < 0 ? -1 : 1
    numerator = numerator.abs
    denominator = @a
    divisor = numerator.gcd(denominator)
    numerator = numerator / divisor
    denominator = denominator / divisor
    x_abs = integer_cube_root(numerator)
    z = integer_cube_root(denominator)
    return nil if x_abs * x_abs * x_abs != numerator
    return nil if z * z * z != denominator
    x = sign * x_abs
    return nil if x.abs > @height || z > @height
    points.push(@curve.space.point(x, 0, z))

  -> g_value(y, z, y2)
    y3 = y2 * y
    y4 = y2 * y2
    inside = @g[3] * y + @g[4] * z
    inside = @g[2] * y2 + z * inside
    inside = @g[1] * y3 + z * inside
    @g[0] * y4 + z * inside

  # Return the unique possible integral root of A X^3 + B X + C, or nil.
  # A,B are positive.  Thus X has the opposite sign from C, and |X|=t solves
  # A t^3 + B t = |C|.
  -> monotone_integer_root(a, b, constant)
    return 0 if constant == 0
    target = constant.abs

    # Both quantities are upper bounds for an *integral* solution t:
    # target >= (a+b)t and target >= a t^3.
    upper = target / (a + b)
    return nil if upper < 1
    cube_upper = integer_cube_root(target / a)
    upper = cube_upper if cube_upper < upper
    upper = @height if @height < upper
    return nil if upper < 1

    # Newton's tangent to the convex increasing cubic stays at or above an
    # integral root.  Flooring therefore cannot skip one.  At termination an
    # exact substitution is the certificate.
    candidate = upper
    loop
      square = candidate * candidate
      next_candidate = (2 * a * square * candidate + target) / (3 * a * square + b)
      break if next_candidate >= candidate
      candidate = next_candidate

    magnitude = nil
    low = candidate > 1 ? candidate - 1 : 1
    high = candidate + 1
    probe = low
    while probe <= high && probe <= @height
      value = a * probe * probe * probe + b * probe
      magnitude = probe if value == target
      probe += 1
    return nil if magnitude == nil
    constant > 0 ? 0 - magnitude : magnitude

  -> candidate_point(y, z)
    common = y.abs.gcd(z)
    reduced_z = z / common
    # If X were a root but shared a prime with common, the triple would not be
    # primitive.  Conversely primitivity makes X invertible modulo common and
    # forces this divisibility after dividing the equation by common.
    return nil if (@a * reduced_z) % (common * common) != 0
    return nil if !passes_modular_sieves?(y, z)

    y2 = y * y
    a = @a * z
    b = @b * y2 * z
    constant = g_value(y, z, y2)
    x = monotone_integer_root(a, b, constant)
    return nil if x == nil
    return nil if x.abs.gcd(common) != 1

    # The isolation formula is exact, but keep the original homogeneous
    # equation as the final independent certificate.
    value = @curve.equation.evaluate([x, y, z])
    return nil if !@curve.field.zero?(value)
    @curve.space.point(x, y, z)

  -> search
    points = []
    scan_infinity(points)
    scan_y_zero(points)

    z = 1
    while z <= @height
      step = minimum_y_step(z)
      y = step
      while y <= @height
        positive = candidate_point(y, z)
        points.push(positive) if positive != nil
        negative = candidate_point(0 - y, z)
        points.push(negative) if negative != nil
        y += step
      z += 1
    points


+ Curve
  -> rational_points(height:)
    MonotoneQuarticPointSearch.new(self, height).search
