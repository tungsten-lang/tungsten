# General integral Weierstrass models and FLT-oriented Frey curves.
#
# The short Weierstrass group law remains in curves.w.  This file supplies the
# integral arithmetic layer needed before minimal models, Tate's algorithm,
# conductors, modular representations, and modular-form spaces can be added.
# Its certificates replay finite polynomial identities; they do not import
# modularity, level lowering, or any other theorem from the proof of FLT.

+ WeierstrassInvariantsCertificate
  -> new(@coefficients, @b_invariants, @c_invariants, @discriminant)

  -> coefficients
    @coefficients

  -> b_invariants
    @b_invariants

  -> c_invariants
    @c_invariants

  -> discriminant
    @discriminant

  -> verified?
    answer = false
    begin
      answer = verify!
    rescue error
      answer = false
    answer

  -> verify!
    return false if @coefficients.class_name != "Array"
    return false if @coefficients.size != 5
    return false if @b_invariants.class_name != "Array"
    return false if @b_invariants.size != 4
    return false if @c_invariants.class_name != "Array"
    return false if @c_invariants.size != 2

    i = 0
    while i < @coefficients.size
      return false if !IntegralWeierstrassModel.integer?(@coefficients[i])
      i += 1
    a1 = @coefficients[0]
    a2 = @coefficients[1]
    a3 = @coefficients[2]
    a4 = @coefficients[3]
    a6 = @coefficients[4]

    b2 = a1**2 + 4*a2
    b4 = a1*a3 + 2*a4
    b6 = a3**2 + 4*a6
    b8 = a1**2*a6 + 4*a2*a6 - a1*a3*a4 + a2*a3**2 - a4**2
    return false if !IntegralWeierstrassModel.same_integer_array?(
      @b_invariants, [b2, b4, b6, b8])

    c4 = b2**2 - 24*b4
    c6 = 0 - b2**3 + 36*b2*b4 - 216*b6
    return false if !IntegralWeierstrassModel.same_integer_array?(
      @c_invariants, [c4, c6])

    delta = 0 - b2**2*b8 - 8*b4**3 - 27*b6**2 + 9*b2*b4*b6
    return false if @discriminant != delta
    c4**3 - c6**2 == 1728*delta

  -> certified?
    verified?

  -> to_s
    "WeierstrassInvariantsCertificate(Delta=" + @discriminant.to_s + ")"

  -> inspect
    to_s


# An integral model
#
#   y^2 + a1*x*y + a3*y = x^3 + a2*x^2 + a4*x + a6.
#
# Coefficients are retained as integers so local minimality and conductor
# algorithms can later work prime by prime without losing the chosen model.
+ IntegralWeierstrassModel
  -> .integer?(value)
    name = value.class_name
    name == "Integer" || name == "Int" || name == "BigInt"

  -> .same_integer_array?(left, right)
    return false if left.class_name != "Array" || right.class_name != "Array"
    return false if left.size != right.size
    i = 0
    while i < left.size
      return false if left[i] != right[i]
      i += 1
    true

  -> new(@a1, @a2, @a3, @a4, @a6)
    coefficients.each -> (coefficient)
      if !IntegralWeierstrassModel.integer?(coefficient)
        raise "integral Weierstrass coefficients must be integers"
    @certificate_cache = nil
    @space_cache = nil
    @curve_cache = nil

  -> a1
    @a1

  -> a2
    @a2

  -> a3
    @a3

  -> a4
    @a4

  -> a6
    @a6

  -> coefficients
    [@a1, @a2, @a3, @a4, @a6]

  -> b2
    @a1**2 + 4*@a2

  -> b4
    @a1*@a3 + 2*@a4

  -> b6
    @a3**2 + 4*@a6

  -> b8
    (@a1**2*@a6 + 4*@a2*@a6 - @a1*@a3*@a4 +
     @a2*@a3**2 - @a4**2)

  -> b_invariants
    [b2, b4, b6, b8]

  -> c4
    b2**2 - 24*b4

  -> c6
    0 - b2**3 + 36*b2*b4 - 216*b6

  -> c_invariants
    [c4, c6]

  -> discriminant
    0 - b2**2*b8 - 8*b4**3 - 27*b6**2 + 9*b2*b4*b6

  -> nonsingular?
    discriminant != 0

  -> j_invariant
    raise "singular Weierstrass models have no j-invariant" if !nonsingular?
    Rational.new(c4**3, discriminant)

  -> certificate
    if @certificate_cache == nil
      @certificate_cache = WeierstrassInvariantsCertificate.new(
        coefficients, b_invariants, c_invariants, discriminant)
    @certificate_cache

  -> certified?
    certificate.verified?

  # The exact projective closure
  #
  #   Y^2 Z + a1 X Y Z + a3 Y Z^2
  #     = X^3 + a2 X^2 Z + a4 X Z^2 + a6 Z^3.
  -> projective_curve
    if @curve_cache == nil
      @space_cache = Algebra.rational_projective_plane(:X, :Y, :Z)
      @curve_cache = projective_curve(@space_cache)
    @curve_cache

  -> projective_curve(space)
    if space.dimension != 2
      raise "a Weierstrass model needs a projective plane"
    if space.field.class_name != "RationalField"
      raise "an integral Weierstrass model currently base-changes only to Q"
    x = space.coords[0]
    y = space.coords[1]
    z = space.coords[2]
    equation = (y**2*z + x*y*z*@a1 + y*z**2*@a3 -
      x**3 - x**2*z*@a2 - x*z**2*@a4 - z**3*@a6)
    Curve.new(space, equation)

  -> space
    projective_curve
    @space_cache

  -> equation
    projective_curve.equation

  -> minimal_model
    raise "minimal integral models require a certified local minimization algorithm"

  -> conductor
    raise "elliptic conductors require certified minimal models and Tate's algorithm"

  -> to_s
    "IntegralWeierstrassModel(" + coefficients.join(", ") + ")"

  -> inspect
    to_s


+ FreyCurveCertificate
  -> new(@a, @b, @exponent, @model, @claimed_c = nil)

  -> verified?
    answer = false
    begin
      answer = verify!
    rescue error
      answer = false
    answer

  -> verify!
    return false if !IntegralWeierstrassModel.integer?(@a)
    return false if !IntegralWeierstrassModel.integer?(@b)
    return false if !IntegralWeierstrassModel.integer?(@exponent)
    return false if @a == 0 || @b == 0
    return false if @a.abs.gcd(@b.abs) != 1
    return false if @exponent < 5 || !@exponent.prime?
    return false if @model.class_name != "IntegralWeierstrassModel"
    return false if !@model.certificate.verified?

    left = @a ** @exponent
    right = @b ** @exponent
    sum = left + right
    return false if sum == 0
    expected = [0, right - left, 0, 0 - left*right, 0]
    return false if !IntegralWeierstrassModel.same_integer_array?(
      @model.coefficients, expected)
    return false if @model.c4 != 16*(left**2 + left*right + right**2)
    return false if @model.discriminant != 16*(left*right*sum)**2
    if @claimed_c != nil
      return false if !IntegralWeierstrassModel.integer?(@claimed_c)
      return false if @claimed_c == 0
      return false if @claimed_c ** @exponent != sum
    true

  -> certified?
    verified?

  -> to_s
    "FreyCurveCertificate(p=" + @exponent.to_s + ")"

  -> inspect
    to_s


# The Frey model attached to a primitive proposed pair (a,b) and prime p:
#
#   y^2 = x (x - a^p) (x + b^p).
#
# The pair alone always defines the curve. `from_fermat_solution` additionally
# checks the hypothetical equality a^p + b^p = c^p. No nontrivial fixture is
# baked into the library: accepting one would itself contradict FLT.
+ FreyCurve
  -> .from_fermat_solution(a, b, c, exponent)
    FreyCurve.new(a, b, exponent, c)

  -> new(@a, @b, @exponent, @c = nil)
    integral_data = IntegralWeierstrassModel.integer?(@a)
    integral_data = false if !IntegralWeierstrassModel.integer?(@b)
    integral_data = false if !IntegralWeierstrassModel.integer?(@exponent)
    if !integral_data
      raise "Frey data must be integral"
    raise "Frey data must be nonzero" if @a == 0 || @b == 0
    raise "Frey data must be primitive" if @a.abs.gcd(@b.abs) != 1
    if @exponent < 5 || !@exponent.prime?
      raise "the FLT Frey construction requires a prime exponent at least 5"
    @a_power = @a ** @exponent
    @b_power = @b ** @exponent
    @sum = @a_power + @b_power
    raise "the Frey cubic is singular when a^p + b^p is zero" if @sum == 0
    if @c != nil
      if !IntegralWeierstrassModel.integer?(@c) || @c == 0
        raise "a proposed Fermat solution needs nonzero integral c"
      if @c ** @exponent != @sum
        raise "proposed values do not satisfy a^p + b^p = c^p"
    @model = IntegralWeierstrassModel.new(
      0, @b_power - @a_power, 0, 0 - @a_power*@b_power, 0)
    @certificate = FreyCurveCertificate.new(
      @a, @b, @exponent, @model, @c)
    raise "Frey curve certificate failed" if !@certificate.verified?

  -> a
    @a

  -> b
    @b

  -> c
    @c

  -> exponent
    @exponent

  -> a_power
    @a_power

  -> b_power
    @b_power

  -> fermat_sum
    @sum

  -> model
    @model

  -> curve
    @model.projective_curve

  -> equation
    @model.equation

  -> discriminant
    @model.discriminant

  -> c4
    @model.c4

  -> certificate
    @certificate

  -> fermat_solution?(candidate_c)
    return false if !IntegralWeierstrassModel.integer?(candidate_c)
    candidate_c ** @exponent == @sum

  -> conductor
    @model.conductor

  -> to_s
    ("FreyCurve(a=" + @a.to_s + ", b=" + @b.to_s +
     ", p=" + @exponent.to_s + ")")

  -> inspect
    to_s
