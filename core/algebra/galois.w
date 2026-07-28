# Certified Galois groups for reciprocal genus-three Weil polynomials.
#
# This is deliberately not a general degree-six classifier.  For
#
#   L(T) = product_i (1 - a_i T + q T^2)
#
# put h(x) = product_i (x - a_i), d_i = a_i^2 - 4q, and let K be the
# splitting field of h.  The splitting field of L is
#
#   K(sqrt(d_1), sqrt(d_2), sqrt(d_3)).
#
# If h is irreducible, Gal(h) is A3 or S3.  Its permutation module F2^3 has
# only the relation submodules 0, <(1,1,1)>, the even-weight plane, and all of
# F2^3.  It therefore suffices to test one individual class d_1, one pair
# d_2*d_3, and their product.  Exact cubic characteristic polynomials turn
# those square tests into rational-root certificates.
#
# Irreducibility is certified by an explicit Rabin witness modulo a good
# prime.  Failure to find such a witness is reported as unknown: an
# irreducible polynomial need not have an irreducible reduction, so absence of
# a witness is never reported as reducibility.

+ ModularIrreducibilityCertificate
  -> new(coefficients, @prime)
    @coefficients = []
    coefficients.each -> @coefficients.push(item)

  -> prime
    @prime

  -> degree
    @coefficients.size - 1

  -> coefficients
    out = []
    @coefficients.each -> out.push(item)
    out

  -> verified?
    WeilSexticGaloisGroup.modular_irreducible?(@coefficients, @prime)

  -> certified?
    verified?

  -> to_s
    "irreducible modulo " + @prime.to_s

  -> inspect
    to_s


+ WeilSexticGaloisCertificate
  -> new(@q, @real_weil_cubic, @real_cubic_group,
         @real_cubic_discriminant, @sextic_irreducibility,
         @cubic_irreducibility, @individual_square,
         @pair_square, @product_square, @kummer_rank,
         @individual_witness, @pair_witness,
         @individual_characteristic, @pair_characteristic,
         @quadratic_product)

  -> q
    @q

  -> real_weil_cubic
    @real_weil_cubic

  -> real_cubic_group
    @real_cubic_group

  -> real_cubic_discriminant
    @real_cubic_discriminant

  -> sextic_irreducibility
    @sextic_irreducibility

  -> cubic_irreducibility
    @cubic_irreducibility

  -> individual_square
    @individual_square

  -> pair_square
    @pair_square

  -> product_square
    @product_square

  -> kummer_rank
    @kummer_rank

  -> individual_witness
    @individual_witness

  -> pair_witness
    @pair_witness

  -> individual_characteristic
    @individual_characteristic

  -> pair_characteristic
    @pair_characteristic

  -> quadratic_product
    @quadratic_product

  -> relation_dimension
    3 - @kummer_rank

  -> relation_basis
    return [[1, 0, 0], [0, 1, 0], [0, 0, 1]] if @individual_square
    return [[1, 1, 0], [0, 1, 1]] if @pair_square
    return [[1, 1, 1]] if @product_square
    []

  -> certified?
    return false if !@sextic_irreducibility.verified?
    return false if !@cubic_irreducibility.verified?
    cyclic = WeilSexticGaloisGroup.rational_square_root(
      @real_cubic_discriminant) != nil
    expected_base = cyclic ? "A3" : "S3"
    return false if @real_cubic_group.name != expected_base

    individual = WeilSexticGaloisGroup.square_in_cubic_splitting_field(
      @individual_characteristic, @real_cubic_discriminant, cyclic)
    pair = WeilSexticGaloisGroup.square_in_cubic_splitting_field(
      @pair_characteristic, @real_cubic_discriminant, cyclic)
    product = WeilSexticGaloisGroup.rational_square_in_cubic_splitting_field?(
      @quadratic_product, @real_cubic_discriminant, cyclic)
    return false if individual[0] != @individual_square
    return false if pair[0] != @pair_square
    return false if product != @product_square

    expected_rank = 3
    expected_rank = 0 if individual[0]
    expected_rank = 1 if !individual[0] && pair[0]
    expected_rank = 2 if !individual[0] && !pair[0] && product
    expected_rank == @kummer_rank

  -> to_s
    label = "WeilSexticCertificate(q=" + @q.to_s
    label += ", Gal(h)=" + @real_cubic_group.name
    label + ", Kummer rank=" + @kummer_rank.to_s + ")"

  -> inspect
    to_s


+ WeilSexticGaloisGroup < GaloisGroup
  -> new(@name, @order, @certificate)

  -> name
    @name

  -> order
    @order

  -> certificate
    @certificate

  -> certified?
    @certificate.certified?

  -> ==/1
    self.eql?(@1)

  -> eql?(other)
    return false if other.class_name != "WeilSexticGaloisGroup"
    @name == other.name && @order == other.order

  -> to_s
    @name

  -> inspect
    to_s

  # Convert a rational polynomial to a primitive integer coefficient vector.
  -> .primitive_integer_coefficients(polynomial)
    coefficients = polynomial.coefficients
    common_denominator = 1
    coefficients.each ->
      denominator = item.denominator
      common_denominator = (common_denominator / common_denominator.gcd(denominator)) * denominator
    integers = []
    coefficients.each ->
      integers.push(item.numerator *
        (common_denominator / item.denominator))
    content = 0
    integers.each -> content = content.gcd(item.abs)
    content = 1 if content == 0
    primitive = []
    integers.each -> primitive.push(item / content)
    if primitive[primitive.size - 1] < 0
      positive = []
      primitive.each -> positive.push(0 - item)
      primitive = positive
    primitive

  -> .mod_normalize(value, prime)
    residue = value % prime
    residue += prime if residue < 0
    residue

  -> .mod_trim(values, prime)
    out = []
    values.each ->
      out.push(WeilSexticGaloisGroup.mod_normalize(item, prime))
    while out.size > 0 && out[out.size - 1] == 0
      out.delete_at(out.size - 1)
    out

  -> .mod_equal?(left, right, prime)
    a = WeilSexticGaloisGroup.mod_trim(left, prime)
    b = WeilSexticGaloisGroup.mod_trim(right, prime)
    return false if a.size != b.size
    i = 0
    while i < a.size
      return false if a[i] != b[i]
      i += 1
    true

  -> .mod_inverse(value, prime)
    value = WeilSexticGaloisGroup.mod_normalize(value, prime)
    raise "zero has no modular inverse" if value == 0
    result = 1
    factor = value
    exponent = prime - 2
    while exponent > 0
      if exponent.odd?
        result = WeilSexticGaloisGroup.mod_normalize(
          result * factor, prime)
      exponent = exponent / 2
      if exponent > 0
        factor = WeilSexticGaloisGroup.mod_normalize(
          factor * factor, prime)
    result

  -> .mod_remainder(dividend, divisor, prime)
    remainder = WeilSexticGaloisGroup.mod_trim(dividend, prime)
    denominator = WeilSexticGaloisGroup.mod_trim(divisor, prime)
    raise "polynomial remainder modulo zero" if denominator.size == 0
    denominator_degree = denominator.size - 1
    denominator_inverse = WeilSexticGaloisGroup.mod_inverse(
      denominator[denominator_degree], prime)
    while remainder.size > 0 && remainder.size - 1 >= denominator_degree
      shift = remainder.size - 1 - denominator_degree
      scale = WeilSexticGaloisGroup.mod_normalize(
        remainder[remainder.size - 1] * denominator_inverse, prime)
      i = 0
      while i <= denominator_degree
        target = shift + i
        remainder[target] = WeilSexticGaloisGroup.mod_normalize(
          remainder[target] - scale * denominator[i], prime)
        i += 1
      remainder = WeilSexticGaloisGroup.mod_trim(remainder, prime)
    remainder

  -> .mod_multiply(left, right, modulus, prime)
    return [] if left.size == 0 || right.size == 0
    out = []
    size = left.size + right.size - 1
    i = 0
    while i < size
      out.push(0)
      i += 1
    i = 0
    while i < left.size
      j = 0
      while j < right.size
        out[i + j] = WeilSexticGaloisGroup.mod_normalize(
          out[i + j] + left[i] * right[j], prime)
        j += 1
      i += 1
    WeilSexticGaloisGroup.mod_remainder(out, modulus, prime)

  -> .mod_power(base, exponent, modulus, prime)
    result = [1]
    factor = WeilSexticGaloisGroup.mod_remainder(base, modulus, prime)
    remaining = exponent
    while remaining > 0
      if remaining.odd?
        result = WeilSexticGaloisGroup.mod_multiply(
          result, factor, modulus, prime)
      remaining = remaining / 2
      if remaining > 0
        factor = WeilSexticGaloisGroup.mod_multiply(
          factor, factor, modulus, prime)
    result

  -> .mod_gcd(left, right, prime)
    a = WeilSexticGaloisGroup.mod_trim(left, prime)
    b = WeilSexticGaloisGroup.mod_trim(right, prime)
    while b.size > 0
      remainder = WeilSexticGaloisGroup.mod_remainder(a, b, prime)
      a = b
      b = remainder
    return [] if a.size == 0
    scale = WeilSexticGaloisGroup.mod_inverse(a[a.size - 1], prime)
    out = []
    a.each ->
      out.push(WeilSexticGaloisGroup.mod_normalize(item * scale, prime))
    WeilSexticGaloisGroup.mod_trim(out, prime)

  -> .prime?(value)
    return false if value < 2
    return true if value == 2
    return false if value.even?
    candidate = 3
    while candidate * candidate <= value
      return false if value % candidate == 0
      candidate += 2
    true

  -> .degree_prime_divisors(degree)
    out = []
    remaining = degree
    candidate = 2
    while candidate * candidate <= remaining
      if remaining % candidate == 0
        out.push(candidate)
        while remaining % candidate == 0
          remaining = remaining / candidate
      candidate = candidate == 2 ? 3 : candidate + 2
    out.push(remaining) if remaining > 1
    out

  # Rabin's finite-field irreducibility criterion:
  #   X^(p^n) = X mod f, and
  #   gcd(f, X^(p^(n/r)) - X) = 1 for every prime r | n.
  -> .modular_irreducible?(integer_coefficients, prime)
    return false if !WeilSexticGaloisGroup.prime?(prime)
    polynomial = WeilSexticGaloisGroup.mod_trim(
      integer_coefficients, prime)
    degree = polynomial.size - 1
    return false if degree <= 0
    leading_inverse = WeilSexticGaloisGroup.mod_inverse(
      polynomial[degree], prime)
    monic = []
    polynomial.each ->
      monic.push(WeilSexticGaloisGroup.mod_normalize(
        item * leading_inverse, prime))

    required_degrees = []
    WeilSexticGaloisGroup.degree_prime_divisors(degree).each ->
      required_degrees.push(degree / item)

    x = [0, 1]
    frobenius = x
    step = 1
    while step <= degree
      frobenius = WeilSexticGaloisGroup.mod_power(
        frobenius, prime, monic, prime)
      if required_degrees.include?(step)
        difference = []
        size = frobenius.size > 2 ? frobenius.size : 2
        i = 0
        while i < size
          value = i < frobenius.size ? frobenius[i] : 0
          value -= 1 if i == 1
          difference.push(
            WeilSexticGaloisGroup.mod_normalize(value, prime))
          i += 1
        common = WeilSexticGaloisGroup.mod_gcd(
          monic, difference, prime)
        return false if common.size != 1
      step += 1
    WeilSexticGaloisGroup.mod_equal?(frobenius, x, prime)

  -> .modular_irreducibility_certificate(polynomial, search_count = 64)
    integers = WeilSexticGaloisGroup.primitive_integer_coefficients(polynomial)
    candidate = 2
    tried = 0
    while tried < search_count
      if WeilSexticGaloisGroup.prime?(candidate)
        tried += 1
        if integers[integers.size - 1] % candidate != 0 && WeilSexticGaloisGroup.modular_irreducible?(integers, candidate)
          return ModularIrreducibilityCertificate.new(integers, candidate)
      candidate = candidate == 2 ? 3 : candidate + 2
    nil

  -> .integer_cube_root(value)
    raise "integer cube root needs a nonnegative integer" if value < 0
    low = 0
    high = 1
    while high * high * high < value
      high *= 2
    while low + 1 < high
      middle = (low + high) / 2
      cube = middle * middle * middle
      if cube <= value
        low = middle
      else
        high = middle
    return high if high * high * high == value
    low

  -> .rational_square_root(value)
    rational = Rational.coerce(value)
    return nil if rational.numerator < 0
    numerator = rational.numerator.isqrt
    denominator = rational.denominator.isqrt
    return nil if numerator * numerator != rational.numerator
    return nil if denominator * denominator != rational.denominator
    Rational.new(numerator, denominator)

  -> .scaled_cubic_characteristic(characteristic, scale)
    scale = Rational.coerce(scale)
    ring = characteristic.ring
    x = ring.generator(0)
    result = x**3
    result += x**2 * (characteristic.coeff(2) / scale)
    result += x * (characteristic.coeff(1) / (scale * scale))
    result + characteristic.coeff(0) / (scale * scale * scale)

  # For u in a cubic field F, let m_u be its characteristic polynomial.
  # If u is non-rational, u is a square in F exactly when
  #
  #   m_u(X^2) =
  #     (X^3 + A X^2 + B X + C)
  #     (X^3 - A X^2 + B X - C)
  #
  # over Q.  C^2 = Norm(u), and the remaining equations reduce to one
  # quartic rational-root test.  Returning the cubic factor makes a positive
  # answer independently checkable; exhausting the rational-root candidates
  # certifies a negative answer.
  -> .cubic_square_factor(characteristic)
    ring = characteristic.ring
    x = ring.generator(0)
    c0 = characteristic.coeff(0)
    c1 = characteristic.coeff(1)
    c2 = characteristic.coeff(2)
    norm = 0 - c0
    norm_root = WeilSexticGaloisGroup.rational_square_root(norm)
    return nil if norm_root == nil

    signs = [norm_root, 0 - norm_root]
    sign_index = 0
    while sign_index < signs.size
      c = signs[sign_index]
      quartic = x**4 + x**2 * (2 * c2) - x * (8 * c) + c2 * c2 - 4 * c1
      candidates = quartic.rational_root_candidates
      candidate_index = 0
      while candidate_index < candidates.size
        a = candidates[candidate_index]
        if quartic.at(a).zero?
          b = (c2 + a * a) / 2
          factor = x**3 + x**2 * a + x * b + c
          conjugate = x**3 - x**2 * a + x * b - c
          square_norm = x**6 + x**4 * c2 + x**2 * c1 + c0
          if (factor * conjugate).eql?(square_norm)
            return factor
          raise "cubic square certificate factorization invariant failed"
        candidate_index += 1
      sign_index += 1
    nil

  # K is F for cyclic h, and F(sqrt(discriminant(h))) for S3.  If u lies in
  # F then u is a square in the latter field exactly when u or u/discriminant
  # is a square in F.  Norm square classes usually reject one or both cases
  # before the cubic factor certificate is attempted.
  -> .square_in_cubic_splitting_field(characteristic, discriminant,
                                      cyclic)
    direct = WeilSexticGaloisGroup.cubic_square_factor(characteristic)
    return [true, direct] if direct != nil
    return [false, nil] if cyclic

    scaled = WeilSexticGaloisGroup.scaled_cubic_characteristic(
      characteristic, discriminant)
    after_adjoining_discriminant = WeilSexticGaloisGroup.cubic_square_factor(scaled)
    if after_adjoining_discriminant != nil
      return [true, after_adjoining_discriminant]
    [false, nil]

  -> .rational_square_in_cubic_splitting_field?(value, discriminant,
                                                cyclic)
    return true if WeilSexticGaloisGroup.rational_square_root(value) != nil
    return false if cyclic
    ratio = Rational.coerce(value) / Rational.coerce(discriminant)
    WeilSexticGaloisGroup.rational_square_root(ratio) != nil

  -> .of(polynomial)
    if polynomial.class_name != "Polynomial" || polynomial.ring.arity != 1 || polynomial.degree != 6
      raise "Weil-sextic Galois classification needs a univariate sextic"
    if polynomial.ring.field.class_name != "RationalField"
      raise "Weil-sextic Galois classification is only implemented over ℚ"

    coefficients = polynomial.coefficients
    i = 0
    while i < coefficients.size
      if coefficients[i].denominator != 1
        raise "a Weil polynomial needs integral coefficients"
      i += 1
    c = []
    coefficients.each -> c.push(item.numerator)
    raise "a Weil polynomial must have constant coefficient 1" if c[0] != 1

    q = WeilSexticGaloisGroup.integer_cube_root(c[6])
    if q <= 0 || q * q * q != c[6]
      raise "a genus-three Weil polynomial needs leading coefficient q^3"
    if c[5] != q * q * c[1] || c[4] != q * c[2]
      raise "degree-six polynomial is not q-reciprocal"

    ring = polynomial.ring
    x = ring.generator(0)
    e1 = 0 - c[1]
    e2 = c[2] - 3 * q
    e3 = 0 - c[3] + 2 * q * c[1]
    real_cubic = x**3 - x**2 * e1 + x * e2 - e3

    sextic_certificate = WeilSexticGaloisGroup.modular_irreducibility_certificate(polynomial)
    if sextic_certificate == nil
      raise "Weil-sextic irreducibility is unknown: no modular witness found"
    cubic_certificate = WeilSexticGaloisGroup.modular_irreducibility_certificate(real_cubic)
    if cubic_certificate == nil
      raise "real Weil cubic irreducibility is unknown: no modular witness found"

    discriminant = real_cubic.discriminant
    if discriminant.numerator <= 0
      raise "real Weil cubic must have three distinct real roots"
    cyclic = WeilSexticGaloisGroup.rational_square_root(discriminant) != nil
    real_group = cyclic ? GaloisGroup.new("A3", 3) : GaloisGroup.new("S3", 6)

    # Symmetric functions of d_i = a_i^2 - 4q.
    r = 4 * q
    d_sum = e1 * e1 - 2 * e2 - 3 * r
    d_pair_sum = e2 * e2 - 2 * e1 * e3
    d_pair_sum -= 2 * r * (e1 * e1 - 2 * e2)
    d_pair_sum += 3 * r * r
    d_product = e3 * e3
    d_product -= r * (e2 * e2 - 2 * e1 * e3)
    d_product += r * r * (e1 * e1 - 2 * e2)
    d_product -= r * r * r

    d_characteristic = x**3 - x**2 * d_sum + x * d_pair_sum - d_product
    pair_characteristic = x**3 - x**2 * d_pair_sum
    pair_characteristic += x * (d_product * d_sum)
    pair_characteristic -= d_product * d_product

    # The roots of d_characteristic are a_i^2 - 4q.  Since the a_i are
    # already certified real, nonnegative coefficients give zero sign changes
    # and hence certify d_i <= 0 by Descartes' rule of signs.
    coefficient_index = 0
    while coefficient_index < 3
      if d_characteristic.coeff(coefficient_index).negative?
        raise "real Weil cubic roots violate the bound |a_i| <= 2*sqrt(q)"
      coefficient_index += 1

    individual = WeilSexticGaloisGroup.square_in_cubic_splitting_field(
      d_characteristic, discriminant, cyclic)
    pair = WeilSexticGaloisGroup.square_in_cubic_splitting_field(
      pair_characteristic, discriminant, cyclic)
    product_square = WeilSexticGaloisGroup.rational_square_in_cubic_splitting_field?(d_product, discriminant, cyclic)

    if !individual[0] && pair[0] && product_square
      raise "inconsistent Weil-sextic square-class relations"

    if individual[0]
      rank = 0
    elsif pair[0]
      rank = 1
    elsif product_square
      rank = 2
    else
      rank = 3

    order = real_group.order * (2**rank)
    if rank == 3 && real_group.name == "S3"
      name = "W(C3)"
    elsif rank == 3 && real_group.name == "A3"
      name = "C2×A4"
    else
      name = "C2^" + rank.to_s + " over " + real_group.name

    certificate = WeilSexticGaloisCertificate.new(
      q, real_cubic, real_group, discriminant,
      sextic_certificate, cubic_certificate,
      individual[0], pair[0], product_square, rank,
      individual[1], pair[1], d_characteristic,
      pair_characteristic, d_product)
    WeilSexticGaloisGroup.new(name, order, certificate)


# Keep the public Polynomial# and IntegerPolynomial# entry points stable.
# GaloisGroup.of retains the exact degree-at-most-three implementation.
+ Polynomial
  -> galois_group
    return WeilSexticGaloisGroup.of(self) if degree == 6
    GaloisGroup.of(self)

  # A successful modular witness is a complete proof over Q by Gauss's
  # lemma.  Absence of one is not evidence of reducibility, so the focused
  # sextic path raises unknown instead of falling into the expensive
  # Kronecker search.
  -> irreducible?
    rational_sextic = @ring.arity == 1
    rational_sextic = rational_sextic && @ring.field.class_name == "RationalField"
    rational_sextic = rational_sextic && degree == 6
    if rational_sextic
      witness = WeilSexticGaloisGroup.modular_irreducibility_certificate(self)
      if witness == nil
        raise "degree-six irreducibility is unknown: no modular witness found"
      return true
    factors = factor
    nonconstant = []
    factors.each ->
      nonconstant.push(item) if item.degree > 0
    nonconstant.size == 1 && nonconstant[0].degree == degree


+ IntegerPolynomial
  -> irreducible?
    rational_polynomial.irreducible?
