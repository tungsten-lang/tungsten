# Algebraic curves and their first geometric constructions.
#
# This layer deliberately depends on Field, Polynomial, Ideal, and
# ProjectiveSpace rather than constructing a rational polynomial ring of its
# own.  A curve therefore keeps the coefficient field of its ambient space.

+ AffineChart
  -> new(@projective_curve, @index)
    space = @projective_curve.space
    if @index < 0 || @index >= space.coordinate_count
      raise "projective chart index out of range"
    @equation = @projective_curve.equation.dehomogenize(@index)

  -> projective_curve
    @projective_curve

  -> index
    @index

  -> equation
    @equation

  -> space
    @projective_curve.space

  -> dimension
    space.dimension

  # Insert Xi = 1 so an affine coordinate tuple can be evaluated by the
  # ambient homogeneous polynomial ring without inventing a second ring.
  -> projective_coordinates(coordinates)
    if coordinates.size != space.dimension
      raise "wrong affine coordinate count"
    out = []
    source = 0
    i = 0
    while i < space.coordinate_count
      if i == @index
        out.push(space.field.one)
      else
        out.push(coordinates[source])
        source += 1
      i += 1
    out

  -> contains?(coordinates)
    space.field.zero?(
      @equation.evaluate(projective_coordinates(coordinates)))

  -> point(coordinates)
    space.point(projective_coordinates(coordinates))

  # Homogenization in the same named ambient ring is an exact inverse for a
  # homogeneous equation dehomogenized on this chart.
  -> homogenize
    variable = space.coordinate_names[@index]
    Curve.new(space, @equation.homogenize(variable))

  -> to_s
    label = "AffineChart(" + space.coordinate_names[@index].to_s + " = 1, "
    label + @equation.to_s + " = 0)"

  -> inspect
    to_s


+ Curve
  -> .affine(space, polynomial, chart = nil)
    index = chart == nil ? space.coordinate_count - 1 : chart
    if index < 0 || index >= space.coordinate_count
      raise "projective chart index out of range"
    variable = space.coordinate_names[index]
    Curve.new(space, polynomial.homogenize(variable))

  -> new(@space, polynomial)
    if @space.dimension != 2
      raise "Curve currently supports projective planes"
    @equation = @space.ring.coerce(polynomial)
    @equation.assert_homogeneous
    @singular_locus_cache = nil
    @nonsingular_cache = nil
    @jacobian_cache = nil

  -> space
    @space

  -> equation
    @equation

  -> field
    @space.field

  -> degree
    @equation.degree

  -> assert_homogeneous(expected = nil)
    @equation.assert_homogeneous(expected)
    self

  -> contains?(point)
    return false if point.class_name != "ProjectivePoint"
    return false if point.space != @space
    return false if point.coordinates.size != @space.coordinate_count
    field.zero?(@equation.evaluate_raw(point.coordinates))

  -> partial_derivatives
    out = []
    i = 0
    while i < @space.coordinate_count
      out.push(@equation.derivative(i))
      i += 1
    out

  # The scheme-theoretic singular locus is cut out by f and all first
  # partials.  Including f keeps this definition correct when the
  # characteristic divides degree(f), where Euler's identity cannot recover
  # f from the partials.
  -> singular_locus
    if @singular_locus_cache == nil
      generators = [@equation]
      partial_derivatives.each -> generators.push(item)
      @singular_locus_cache = Ideal.new(generators)
    @singular_locus_cache

  # Projective emptiness of the singular locus.  An ordinary homogeneous ideal
  # is never the unit ideal merely because its projective vanishing set is
  # empty, so we test the standard Xi = 1 affine cover: each chart adjoins
  # Xi - 1 and asks whether the extended ideal is (1).  Principal saturation
  # by a single coordinate is available on Ideal, but saturating by each
  # coordinate in turn is not the same as saturating by the irrelevant ideal
  # (x0,...,xn), so the chart cover remains the certified test here.
  -> nonsingular?
    return @nonsingular_cache if @nonsingular_cache != nil
    locus = singular_locus
    chart = 0
    while chart < @space.coordinate_count
      generators = []
      locus.source_generators.each -> generators.push(item)
      generators.push(@space.coords[chart] - field.one)
      if !Ideal.new(generators).unit?
        @nonsingular_cache = false
        return false
      chart += 1
    @nonsingular_cache = true
    true

  -> dehomogenize(chart = nil)
    index = chart == nil ? @space.coordinate_count - 1 : chart
    @equation.dehomogenize(index)

  -> affine_chart(chart = nil)
    index = chart == nil ? @space.coordinate_count - 1 : chart
    AffineChart.new(self, index)

  # Compatibility with the former polynomial-shaped chart operation.
  -> chart(index)
    affine_chart(index)

  -> genus
    if !nonsingular?
      raise "singular plane curves require normalization before genus"
    d = degree
    (d - 1) * (d - 2) / 2

  -> elliptic?
    degree == 3 && nonsingular?

  # Recognize the chosen coordinates as a short Weierstrass equation up to a
  # nonzero scalar:
  #   λ(y²z - x³ - a xz² - b z³).
  # Converting an arbitrary cubic still needs a rational flex and is kept as a
  # distinct future capability.
  -> short_weierstrass?
    return false if degree != 3
    f = field
    scale = @equation.coeff([0, 2, 1])
    return false if f.zero?(scale)
    a = f.divide(f.negate(@equation.coeff([1, 0, 2])), scale)
    b = f.divide(f.negate(@equation.coeff([0, 0, 3])), scale)
    model = EllipticCurve.new(@space, a, b)
    @equation.eql?(model.equation * scale) && model.nonsingular?

  -> to_short_weierstrass
    raise "plane cubic is not in short Weierstrass coordinates" if !short_weierstrass?
    f = field
    scale = @equation.coeff([0, 2, 1])
    a = f.divide(f.negate(@equation.coeff([1, 0, 2])), scale)
    b = f.divide(f.negate(@equation.coeff([0, 0, 3])), scale)
    EllipticCurve.new(@space, a, b)

  # A smooth plane curve of genus at least two has degree at least four, and
  # its canonical map is an embedding (the quartic case directly, and higher
  # degrees through O(d-3)).  It is therefore not hyperelliptic.  The explicit
  # name distinguishes this theorem from tests for arbitrary curve models.
  -> hyperelliptic_plane_model?
    return false if genus < 2
    false

  -> hyperelliptic?
    hyperelliptic_plane_model?

  -> jacobian
    if @jacobian_cache == nil
      @jacobian_cache = Jacobian.new(self)
    @jacobian_cache

  -> to_s
    "Curve(" + @equation.to_s + " = 0 in " + @space.to_s + ")"

  -> inspect
    to_s


+ Jacobian
  -> new(@curve)

  -> curve
    @curve

  -> dimension
    @curve.genus

  -> to_s
    "Jacobian(dim=" + dimension.to_s + ")"

  -> inspect
    to_s

  # Rank is a certified-only capability.  No heuristic or point-search result
  # is promoted to an arithmetic theorem here.
  -> rank
    raise "Jacobian rank requires a completed certified descent and matching lower bound"


# A rational point on a short Weierstrass model.  The identity is represented
# explicitly rather than by nil coordinates leaking into polynomial code.
+ EllipticPoint
  -> new(@curve, @x, @y, @at_infinity = false)

  -> curve
    @curve

  -> x
    @x

  -> y
    @y

  -> identity?
    @at_infinity

  -> negate
    return self if identity?
    EllipticPoint.new(@curve, @x, @curve.field.negate(@y))

  -> -@
    negate

  -> +/1
    @curve.add(self, @1)

  -> multiply(scalar)
    scalar_class = scalar.class_name
    if scalar_class != "Integer" && scalar_class != "Int" && scalar_class != "BigInt"
      raise "elliptic scalar multiplication needs an integer"
    return negate.multiply(0 - scalar) if scalar < 0
    result = @curve.identity
    addend = self
    multiple = scalar
    while multiple > 0
      result = result + addend if multiple.odd?
      multiple = multiple / 2
      addend = addend + addend if multiple > 0
    result

  -> */1
    multiply(@1)

  -> ==/1
    self.eql?(@1)

  -> eql?(other)
    return false if other.class_name != "EllipticPoint"
    return false if @curve != other.curve
    return true if identity? && other.identity?
    return false if identity? || other.identity?
    @curve.field.equal?(@x, other.x) && @curve.field.equal?(@y, other.y)

  -> projective_point
    if identity?
      return @curve.space.point_raw(0, 1, 0)
    @curve.space.point_raw(@x, @y, @curve.field.one)

  -> to_s
    return "O" if identity?
    x_text = @curve.field.element_to_s(@x)
    y_text = @curve.field.element_to_s(@y)
    "(" + x_text + ", " + y_text + ")"

  -> inspect
    to_s


# The short Weierstrass model y^2 z = x^3 + a x z^2 + b z^3.
#
# Composition, not inheritance: an elliptic curve *has* a plane cubic model
# (`curve`) and a group law on `EllipticPoint`s.  Geometry (singular locus,
# projective membership) is delegated; arithmetic stays field-protocol exact
# so the same code runs over ℚ and 𝔽_p.
+ EllipticCurve
  -> .short_weierstrass(space, a, b)
    EllipticCurve.new(space, a, b)

  -> new(@space, a, b)
    if @space.dimension != 2
      raise "an elliptic Weierstrass model needs a projective plane"
    characteristic = @space.field.characteristic
    if characteristic == 2 || characteristic == 3
      raise "short Weierstrass form requires characteristic other than 2 or 3"
    @a = @space.field.coerce(a)
    @b = @space.field.coerce(b)
    x = @space.coords[0]
    y = @space.coords[1]
    z = @space.coords[2]
    @equation = y**2 * z - x**3 - x * z**2 * @a - z**3 * @b
    @curve = Curve.new(@space, @equation)
    @identity = EllipticPoint.new(self, nil, nil, true)
    @jacobian_view = EllipticJacobian.new(self)

  -> space
    @space

  -> equation
    @equation

  # The underlying plane cubic. Callers that need Curve APIs use this
  # explicitly rather than treating EllipticCurve as a Curve subclass.
  -> curve
    @curve

  -> a
    @a

  -> b
    @b

  -> identity
    @identity

  -> field
    @space.field

  -> degree
    3

  -> discriminant
    f = field
    inside = f.add(f.multiply(f.coerce(4), f.power(@a, 3)),
                   f.multiply(f.coerce(27), f.power(@b, 2)))
    f.multiply(f.coerce(-16), inside)

  -> nonsingular?
    !field.equal?(discriminant, field.zero)

  -> singular_locus
    @curve.singular_locus

  -> genus
    raise "a singular Weierstrass cubic is not an elliptic curve" if !nonsingular?
    1

  -> elliptic?
    nonsingular?

  -> short_weierstrass?
    true

  -> to_short_weierstrass
    self

  -> contains?(point)
    if point.class_name == "EllipticPoint"
      return false if point.curve != self
      return true if point.identity?
      f = field
      right = f.add(f.add(f.power(point.x, 3), f.multiply(@a, point.x)), @b)
      return f.equal?(f.power(point.y, 2), right)
    @curve.contains?(point)

  -> point(x, y)
    point_element(field.coerce(x), field.coerce(y))

  -> point_raw(x, y)
    px = field.normalize_element(x)
    py = field.normalize_element(y)
    point_element(px, py)

  -> point_element(px, py)
    point = EllipticPoint.new(self, px, py)
    if !contains?(point)
      raise "point is not on the elliptic curve"
    point

  -> projective_point(x, y, z)
    point = @space.point(x, y, z)
    raise "point is not on the elliptic curve" if !@curve.contains?(point)
    point

  -> add(left, right)
    wrong_type = left.class_name != "EllipticPoint" || right.class_name != "EllipticPoint"
    wrong_curve = !wrong_type && (left.curve != self || right.curve != self)
    if wrong_type || wrong_curve
      raise "elliptic points belong to different curves"
    return right if left.identity?
    return left if right.identity?

    f = field
    if f.equal?(left.x, right.x)
      return @identity if f.equal?(f.add(left.y, right.y), f.zero)
      return @identity if f.equal?(left.y, f.zero)
      numerator = f.add(f.multiply(f.coerce(3), f.power(left.x, 2)), @a)
      slope = f.divide(numerator, f.multiply(f.coerce(2), left.y))
    else
      slope = f.divide(f.subtract(right.y, left.y), f.subtract(right.x, left.x))
    x3 = f.subtract(f.subtract(f.power(slope, 2), left.x), right.x)
    y3 = f.subtract(f.multiply(slope, f.subtract(left.x, x3)), left.y)
    point_raw(x3, y3)

  -> jacobian
    @jacobian_view

  -> rank
    raise "Jacobian rank requires a completed certified descent and matching lower bound"

  -> to_s
    "EllipticCurve(" + @equation.to_s + " = 0 in " + @space.to_s + ")"

  -> inspect
    to_s


# Thin Jacobian view for a short Weierstrass model.  Dimension is 1; rank is
# still a certified-only capability.
+ EllipticJacobian
  -> new(@curve)

  -> curve
    @curve

  -> dimension
    1

  -> rank
    raise "Jacobian rank requires a completed certified descent and matching lower bound"

  -> to_s
    "Jacobian(dim=1)"

  -> inspect
    to_s


# The affine model y^2 = f(x).  Unlike Curve#hyperelliptic_plane_model?, this
# class records the double-cover structure as part of the model.
+ HyperellipticCurve
  -> new(@polynomial)
    if @polynomial.ring.arity != 1
      raise "hyperelliptic model must be univariate"
    if @polynomial.degree < 3
      raise "hyperelliptic model y^2 = f(x) requires degree at least 3"
    if @polynomial.ring.field.characteristic == 2
      raise "the model y^2 = f(x) is not supported in characteristic 2"
    @jacobian_cache = nil

  -> polynomial
    @polynomial

  -> field
    @polynomial.ring.field

  -> nonsingular?
    @polynomial.squarefree?

  -> genus
    if !nonsingular?
      raise "singular hyperelliptic model requires normalization"
    (@polynomial.degree - 1) / 2

  -> hyperelliptic_model?
    true

  -> hyperelliptic?
    genus >= 2

  -> jacobian
    if @jacobian_cache == nil
      @jacobian_cache = HyperellipticJacobian.new(self)
    @jacobian_cache


# A reduced Mumford pair (u, v), with u monic, deg(v) < deg(u),
# u | (v^2 - f), and deg(u) <= genus.
+ MumfordDivisor
  -> new(@jacobian, u, v)
    ring = @jacobian.curve.polynomial.ring
    @u = ring.coerce(u)
    @v = ring.coerce(v)
    raise "Mumford u cannot be zero" if @u.zero?
    @u = @u.monic
    @v = @v.rem(@u)
    model = @jacobian.model_polynomial
    if !((@v * @v - model).rem(@u)).zero?
      raise "Mumford pair must satisfy u | (v^2 - f)"
    if @u.degree > @jacobian.dimension
      raise "Mumford divisor is not reduced"

  -> jacobian
    @jacobian

  -> u
    @u

  -> v
    @v

  -> identity?
    @u.one? && @v.zero?

  -> reduced?
    monic = @u.ring.field.one?(@u.leading_term[0])
    monic && @v.degree < @u.degree && @u.degree <= @jacobian.dimension

  -> negate
    MumfordDivisor.new(@jacobian, @u, @v.negate)

  -> -@
    negate

  -> +/1
    @jacobian.add(self, @1)

  -> -/1
    @jacobian.add(self, @1.negate)

  -> double
    @jacobian.add(self, self)

  -> multiply(scalar)
    scalar_class = scalar.class_name
    if scalar_class != "Integer" && scalar_class != "Int" && scalar_class != "BigInt"
      raise "Jacobian scalar multiplication needs an integer"
    return negate.multiply(0 - scalar) if scalar < 0
    result = @jacobian.identity
    addend = self
    multiple = scalar
    while multiple > 0
      result = result + addend if multiple.odd?
      multiple = multiple / 2
      addend = addend.double if multiple > 0
    result

  -> */1
    multiply(@1)

  -> ==/1
    self.eql?(@1)

  -> eql?(other)
    return false if other.class_name != "MumfordDivisor"
    @jacobian == other.jacobian && @u.eql?(other.u) && @v.eql?(other.v)

  -> to_s
    "Mumford(u=" + @u.to_s + ", v=" + @v.to_s + ")"

  -> inspect
    to_s


+ HyperellipticJacobian
  -> new(@curve)
    raise "a singular hyperelliptic model has no Jacobian group law here" if !@curve.nonsingular?
    if @curve.polynomial.degree.even?
      raise "Mumford Jacobian arithmetic currently requires an odd-degree model"
    # Non-monic models are normalized once: y^2 = c f_monic becomes
    # (y/sqrt(c))^2 = f_monic only when c is a square in the field.  Over ℚ we
    # require monic input; over finite fields of odd characteristic we scale
    # the model by the inverse of the leading coefficient.
    poly = @curve.polynomial
    if !poly.ring.field.one?(poly.leading_coefficient)
      if poly.ring.field.class_name == "FiniteField"
        @scaled_polynomial = poly.monic
      else
        raise "Mumford Jacobian arithmetic currently requires a monic model"
    else
      @scaled_polynomial = poly
    @identity = MumfordDivisor.new(self, poly.ring.one, poly.ring.zero)

  -> curve
    @curve

  -> identity
    @identity

  -> dimension
    @curve.genus

  -> divisor(u, v)
    MumfordDivisor.new(self, u, v)

  -> model_polynomial
    @scaled_polynomial

  # Reduce a semireduced Mumford pair by repeatedly replacing
  #   (u, v) with ((f - v²)/u, -v mod u_new).
  -> reduce_pair(u, v)
    polynomial = model_polynomial
    u = u.monic
    v = v.rem(u)
    while u.degree > dimension
      next_u = (polynomial - v * v) / u
      next_u = next_u.monic
      v = v.negate.rem(next_u)
      u = next_u
    MumfordDivisor.new(self, u, v)

  # Cantor composition in characteristic other than two. For
  # d = gcd(u1, u2, v1+v2), a three-way Bézout relation gives the
  # simultaneous lift of v; reduce_pair returns its reduced representative.
  -> add(left, right)
    if left.class_name != "MumfordDivisor" || right.class_name != "MumfordDivisor"
      raise "Jacobian addition needs Mumford divisors"
    if left.jacobian != self || right.jacobian != self
      raise "Mumford divisors belong to different Jacobians"
    return right if left.identity?
    return left if right.identity?

    first_gcd = left.u.xgcd(right.u)
    d1 = first_gcd[0]
    a1 = first_gcd[1]
    a2 = first_gcd[2]
    second_gcd = d1.xgcd(left.v + right.v)
    d = second_gcd[0]
    b1 = second_gcd[1]
    b2 = second_gcd[2]
    s1 = b1 * a1
    s2 = b1 * a2
    s3 = b2

    u = (left.u * right.u) / (d * d)
    numerator = s1 * left.u * right.v
    numerator = numerator + s2 * right.u * left.v
    numerator = numerator + s3 * (left.v * right.v + model_polynomial)
    v = (numerator / d).rem(u)
    reduce_pair(u, v)

  -> rank
    raise "Jacobian rank requires a completed certified descent and matching lower bound"


+ GaloisGroup
  -> new(@name, @order)

  -> name
    @name

  -> order
    @order

  -> certified?
    true

  -> ==/1
    self.eql?(@1)

  -> eql?(other)
    return false if other.class_name != "GaloisGroup"
    @name == other.name && @order == other.order

  # The Galois group of a separable cubic over ℚ, decided exactly.  Counting
  # rational roots (with deflation) is all a cubic needs — no general
  # factorization: three roots give C1, exactly one gives C2 (the residual
  # quadratic is irreducible), and an irreducible cubic has group A3 exactly
  # when its discriminant is a rational square — √disc is fixed by precisely
  # the even permutations of the roots — and S3 otherwise.
  -> .of_cubic(polynomial)
    if polynomial.ring.arity != 1 || polynomial.degree != 3
      raise "cubic Galois group needs a univariate cubic"
    if polynomial.ring.field.class_name != "RationalField"
      raise "cubic Galois group is only implemented over ℚ"
    if !polynomial.squarefree?
      raise "cubic Galois group needs a separable cubic"
    generator = polynomial.ring.generator(0)
    work = polynomial
    rational_roots = 0
    found = true
    while found && work.degree > 1
      found = false
      candidates = work.rational_root_candidates
      index = 0
      while index < candidates.size && !found
        candidate = candidates[index]
        if work.at(candidate).zero?
          found = true
          rational_roots += 1
          work = work.quo(generator - candidate)
        index += 1
    rational_roots += 1 if work.degree == 1
    return GaloisGroup.new("C1", 1) if rational_roots == 3
    return GaloisGroup.new("C2", 2) if rational_roots == 1
    return GaloisGroup.new("A3", 3) if GaloisGroup.rational_square?(polynomial.discriminant)
    GaloisGroup.new("S3", 6)

  -> .of(polynomial)
    if polynomial.ring.arity != 1
      raise "Galois group needs a univariate polynomial"
    if polynomial.ring.field.class_name != "RationalField"
      raise "Galois group is only implemented over ℚ"
    if !polynomial.squarefree?
      raise "Galois group needs a separable polynomial"
    return GaloisGroup.new("C1", 1) if polynomial.degree <= 1
    if polynomial.degree == 2
      candidates = polynomial.rational_root_candidates
      index = 0
      while index < candidates.size
        return GaloisGroup.new("C1", 1) if polynomial.at(candidates[index]).zero?
        index += 1
      return GaloisGroup.new("C2", 2)
    return GaloisGroup.of_cubic(polynomial) if polynomial.degree == 3
    raise "Galois groups above degree three are not implemented"

  # A reduced rational p/q (q > 0) is a square exactly when p >= 0 and both
  # p and q are perfect squares.
  -> .rational_square?(value)
    return false if value.numerator < 0
    p = value.numerator
    q = value.denominator
    rp = p.isqrt
    rq = q.isqrt
    rp * rp == p && rq * rq == q

  -> to_s
    @name

  -> inspect
    to_s


+ WeilCubic
  -> new(@polynomial)
    if @polynomial.ring.arity != 1 || @polynomial.degree != 3
      raise "a Weil cubic must be univariate of degree 3"

  -> polynomial
    @polynomial

  -> field
    @polynomial.ring.field

  -> discriminant
    @polynomial.discriminant

  -> galois_group
    GaloisGroup.of_cubic(@polynomial)
