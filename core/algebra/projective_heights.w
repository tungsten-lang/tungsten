# Certified naive and dynamical heights on rational projective space.
#
# A homogeneous map F = [F_0:...:F_N] of degree d is supplied with exact
# homogeneous Nullstellensatz identities
#
#   R*X_i^D = sum_j G_(i,j)*F_j.
#
# The coordinate polynomials and witnesses are required to have integral
# coefficients.  If x is a primitive integral coordinate vector, the common
# divisor of the F_j(x) divides R.  Coefficient one-norms in the forward map
# and identities then give the replayed uniform defect
#
#   |h(F(P)) - d*h(P)| <= log(max(A, B)).
#
# Telescoping this inequality encloses the canonical dynamical height.  The
# finite polynomial identities and height orbit are replayed exactly; the
# standard projective-height and telescoping lemmas are named theorem imports.

use core/calculus
use core/algebra/projective


+ ProjectiveHeightArithmetic
  -> .integral_polynomial?(polynomial)
    polynomial.terms.each -> (term)
      return false if Rational.coerce(term[0]).denominator != 1
    true

  -> .coefficient_one_norm(polynomial)
    total = 0 ## big
    polynomial.terms.each -> (term)
      total += Rational.coerce(term[0]).numerator.abs
    total

  -> .primitive_coordinate_height(point, tolerance = nil)
    if point.space.field.class_name != "RationalField"
      raise "projective height currently requires a rational point"
    maximum = 0 ## big
    point.coordinates.each -> (coordinate)
      rational = Rational.coerce(coordinate)
      if rational.denominator != 1
        raise "normalized rational projective coordinates must be integral"
      size = rational.numerator.abs
      maximum = size if size > maximum
    raise "projective height received the zero coordinate vector" if maximum == 0
    Calculus.certified_log(maximum, tolerance)


+ ProjectiveHomogeneousMapCertificate
  -> new(@map)
    @verified_cache = nil

  -> theorem
    "homogeneous coordinate polynomials define a rational projective map away from their common zero locus"

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
    return false if @map.class_name != "ProjectiveHomogeneousMap"
    space = @map.space
    return false if space.field.class_name != "RationalField"
    polynomials = @map.coordinate_polynomials
    return false if polynomials.size != space.coordinate_count
    degree = @map.degree
    return false if degree < 2
    coefficient_gcd = 0 ## big
    nonzero = false
    polynomials.each -> (polynomial)
      return false if polynomial.ring != space.ring
      return false if polynomial.zero? || !polynomial.homogeneous?
      return false if polynomial.degree != degree
      return false if !ProjectiveHeightArithmetic.integral_polynomial?(polynomial)
      polynomial.terms.each -> (term)
        value = Rational.coerce(term[0]).numerator.abs
        coefficient_gcd = coefficient_gcd.gcd(value)
        nonzero = true if value != 0
    nonzero && coefficient_gcd == 1


+ ProjectiveHomogeneousMap
  -> new(@space, coordinate_polynomials)
    @coordinate_polynomials = []
    coordinate_polynomials.each -> @coordinate_polynomials.push(item)
    @degree = @coordinate_polynomials.size == 0 ? -1 : (
      @coordinate_polynomials[0].degree)
    @certificate_cache = ProjectiveHomogeneousMapCertificate.new(self)
    if !@certificate_cache.verified?
      raise "projective homogeneous map failed certification"

  -> space
    @space

  -> coordinate_polynomials
    answer = []
    @coordinate_polynomials.each -> answer.push(item)
    answer

  -> degree
    @degree

  -> image(point)
    raise "point belongs to a different projective space" if point.space != @space
    values = []
    @coordinate_polynomials.each -> (polynomial)
      values.push(polynomial.evaluate_raw(point.coordinates))
    @space.point_raw(values)

  -> certificate
    @certificate_cache

  -> certified?
    @certificate_cache.verified?


# Turn a certified positive canonical height and a uniform positive lower
# bound for nontorsion points into a finite Mordell--Weil divisibility bound.
# For P=mQ, quadraticity gives m^2*lambda <= hhat(P).
+ MordellWeilHeightIndexCertificate
  -> new(@bound)
    @verified_cache = nil

  -> theorem
    "quadratic canonical heights bound the index of a point in a rank-one Mordell-Weil lattice"

  -> theorem_reference
    "Neron-Tate quadraticity and positivity modulo torsion"

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
    return false if @bound.class_name != "MordellWeilHeightIndexBound"
    height = @bound.point_height
    return false if !height.certificate.verified?
    return false if height.map.degree != 4
    return false if height.lower_bound <= Rational.new(0)
    lower = @bound.nontorsion_height_lower_bound
    return false if lower <= Rational.new(0)
    upper = height.upper_bound
    return false if upper < lower
    maximum = @bound.maximum_multiplier
    return false if maximum < 1
    return false if maximum*maximum*lower > upper
    return false if (maximum + 1)*(maximum + 1)*lower <= upper
    expected = []
    candidate = 3
    while candidate <= maximum
      expected.push(candidate) if candidate.prime?
      candidate += 2
    actual = @bound.odd_prime_candidates
    return false if expected.size != actual.size
    index = 0
    while index < expected.size
      return false if expected[index] != actual[index]
      index += 1
    true


+ MordellWeilHeightIndexBound
  -> .floor_sqrt_ratio(value)
    rational = Rational.coerce(value)
    raise "height ratio must be nonnegative" if rational < Rational.new(0)
    numerator = rational.numerator
    denominator = rational.denominator
    low = 0 ## big
    high = 1 ## big
    while high*high*denominator <= numerator
      low = high
      high *= 2
    while high - low > 1
      middle = (low + high) / 2
      if middle*middle*denominator <= numerator
        low = middle
      else
        high = middle
    low

  -> new(@point_height, nontorsion_height_lower_bound)
    @nontorsion_height_lower_bound = Rational.coerce(
      nontorsion_height_lower_bound)
    if (@point_height.class_name != "ProjectiveCanonicalHeightEnclosure" ||
        !@point_height.certificate.verified?)
      raise "index bound needs a certified canonical-height enclosure"
    if @point_height.map.degree != 4
      raise "Mordell-Weil index bound needs a duplication map of degree four"
    if @point_height.lower_bound <= Rational.new(0)
      raise "the supplied point is not certified nontorsion by its height"
    if @nontorsion_height_lower_bound <= Rational.new(0)
      raise "nontorsion height lower bound must be positive"
    if @point_height.upper_bound < @nontorsion_height_lower_bound
      raise "point height lies below the claimed uniform lower bound"
    @maximum_multiplier = MordellWeilHeightIndexBound.floor_sqrt_ratio(
      @point_height.upper_bound / @nontorsion_height_lower_bound)
    @odd_prime_candidates = []
    candidate = 3
    while candidate <= @maximum_multiplier
      @odd_prime_candidates.push(candidate) if candidate.prime?
      candidate += 2
    @certificate_cache = MordellWeilHeightIndexCertificate.new(self)
    if !@certificate_cache.verified?
      raise "Mordell-Weil height/index bound failed certification"

  -> point_height
    @point_height

  -> nontorsion_height_lower_bound
    @nontorsion_height_lower_bound

  -> maximum_multiplier
    @maximum_multiplier

  -> odd_prime_candidates
    answer = []
    @odd_prime_candidates.each -> answer.push(item)
    answer

  -> certificate
    @certificate_cache

  -> certified?
    @certificate_cache.verified?


+ ProjectiveHeightDefectCertificate
  -> new(@defect)
    @verified_cache = nil

  -> theorem
    "homogeneous Nullstellensatz identities bound the global naive-height defect"

  -> theorem_reference
    "projective height coefficient bounds and the telescoping canonical-height lemma"

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
    return false if @defect.class_name != "ProjectiveHeightDefectBound"
    map = @defect.map
    return false if !map.certificate.verified?
    scalar_rational = Rational.coerce(@defect.identity_scalar)
    return false if scalar_rational.denominator != 1
    scalar = scalar_rational.numerator
    return false if scalar == 0
    identity_degree = @defect.identity_degree
    return false if identity_degree < map.degree
    witnesses = @defect.witnesses
    count = map.space.coordinate_count
    return false if witnesses.size != count
    coordinates = map.space.coords
    images = map.coordinate_polynomials
    row_index = 0
    while row_index < count
      row = witnesses[row_index]
      return false if row.size != count
      sum = map.space.ring.zero
      column = 0
      while column < count
        witness = row[column]
        return false if witness.ring != map.space.ring
        return false if !ProjectiveHeightArithmetic.integral_polynomial?(witness)
        if !witness.zero?
          return false if !witness.homogeneous?
          return false if witness.degree != identity_degree - map.degree
        sum = sum + witness*images[column]
        column += 1
      expected = coordinates[row_index]**identity_degree*scalar
      return false if sum != expected
      row_index += 1
    return false if @defect.forward_coefficient_bound < 1
    return false if @defect.reverse_coefficient_bound < 1
    @defect.defect_coefficient_bound == [
      @defect.forward_coefficient_bound,
      @defect.reverse_coefficient_bound
    ].max


+ ProjectiveHeightDefectBound
  -> new(@map, @identity_scalar, @identity_degree, witnesses)
    @witnesses = []
    witnesses.each -> (row)
      copied = []
      row.each -> copied.push(item)
      @witnesses.push(copied)
    @forward_coefficient_bound = 0 ## big
    @map.coordinate_polynomials.each -> (polynomial)
      bound = ProjectiveHeightArithmetic.coefficient_one_norm(polynomial)
      @forward_coefficient_bound = bound if bound > @forward_coefficient_bound
    @reverse_coefficient_bound = 0 ## big
    @witnesses.each -> (row)
      bound = 0 ## big
      row.each -> (polynomial)
        bound += ProjectiveHeightArithmetic.coefficient_one_norm(polynomial)
      @reverse_coefficient_bound = bound if bound > @reverse_coefficient_bound
    @defect_coefficient_bound = [
      @forward_coefficient_bound,
      @reverse_coefficient_bound
    ].max
    @certificate_cache = ProjectiveHeightDefectCertificate.new(self)
    if !@certificate_cache.verified?
      raise "projective height-defect identity failed certification"

  -> map
    @map

  -> identity_scalar
    @identity_scalar

  -> identity_degree
    @identity_degree

  -> witnesses
    answer = []
    @witnesses.each -> (row)
      copied = []
      row.each -> copied.push(item)
      answer.push(copied)
    answer

  -> forward_coefficient_bound
    @forward_coefficient_bound

  -> reverse_coefficient_bound
    @reverse_coefficient_bound

  -> defect_coefficient_bound
    @defect_coefficient_bound

  -> log_bound(tolerance = nil)
    Calculus.certified_log(@defect_coefficient_bound, tolerance)

  -> certificate
    @certificate_cache

  -> certified?
    @certificate_cache.verified?


+ ProjectiveCanonicalHeightCertificate
  -> new(@height)
    @verified_cache = nil

  -> theorem
    "the canonical dynamical height is the scaled-height limit with a geometric defect tail"

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
    return false if @height.class_name != "ProjectiveCanonicalHeightEnclosure"
    map = @height.map
    defect = @height.defect_bound
    return false if !map.certificate.verified? || !defect.certificate.verified?
    return false if defect.map != map || @height.iterations < 0
    points = @height.orbit
    return false if points.size != @height.iterations + 1
    return false if points[0] != @height.point
    index = 1
    while index < points.size
      return false if points[index] != map.image(points[index - 1])
      index += 1
    final_height = ProjectiveHeightArithmetic.primitive_coordinate_height(
      points[points.size - 1], @height.tolerance)
    return false if !final_height.certified?
    return false if final_height.interval != @height.final_naive_height.interval
    power = map.degree**@height.iterations
    scaled = final_height.interval / power
    defect_log = defect.log_bound(@height.tolerance)
    tail = defect_log.upper_bound / ((map.degree - 1)*power)
    lower = scaled.lower_bound - tail
    lower = Rational.new(0) if lower < Rational.new(0)
    expected = CertifiedRealInterval.new(lower, scaled.upper_bound + tail)
    @height.interval == expected


+ ProjectiveCanonicalHeightEnclosure
  -> new(@map, @defect_bound, @point, @iterations = 4,
         @tolerance = nil)
    raise "height enclosure needs a nonnegative iteration count" if @iterations < 0
    raise "height enclosure map/defect mismatch" if @defect_bound.map != @map
    raise "height enclosure point belongs to a different space" if (
      @point.space != @map.space)
    @orbit = [@point]
    index = 0
    while index < @iterations
      @orbit.push(@map.image(@orbit[@orbit.size - 1]))
      index += 1
    @final_naive_height = ProjectiveHeightArithmetic.primitive_coordinate_height(
      @orbit[@orbit.size - 1], @tolerance)
    power = @map.degree**@iterations
    scaled = @final_naive_height.interval / power
    defect_log = @defect_bound.log_bound(@tolerance)
    tail = defect_log.upper_bound / ((@map.degree - 1)*power)
    lower = scaled.lower_bound - tail
    lower = Rational.new(0) if lower < Rational.new(0)
    @interval = CertifiedRealInterval.new(
      lower, scaled.upper_bound + tail)
    @certificate_cache = ProjectiveCanonicalHeightCertificate.new(self)
    if !@certificate_cache.verified?
      raise "projective canonical-height enclosure failed certification"

  -> map
    @map

  -> defect_bound
    @defect_bound

  -> point
    @point

  -> iterations
    @iterations

  -> tolerance
    @tolerance

  -> orbit
    answer = []
    @orbit.each -> answer.push(item)
    answer

  -> final_naive_height
    @final_naive_height

  -> interval
    @interval

  -> lower_bound
    @interval.lower_bound

  -> upper_bound
    @interval.upper_bound

  -> width
    @interval.width

  -> certificate
    @certificate_cache

  -> certified?
    @certificate_cache.verified?
