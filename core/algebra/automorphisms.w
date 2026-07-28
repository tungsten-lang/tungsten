# Certified geometric automorphisms of smooth plane quartics.
#
# A smooth plane quartic is its canonical model, so every geometric
# automorphism is induced by an element of PGL(3) over the algebraic closure.
# The focused certificate below applies when the displayed coordinates expose
# a unique hyperflex
#
#   P = [1:0:0],   T_P C = { Z = 0 }.
#
# Uniqueness is not inferred from rational points.  It is proved over the
# algebraic closure: the line at infinity meets C only in 4P, and the affine
# hyperflex equations generate the unit ideal over Q.  Every geometric
# automorphism must therefore fix P and its tangent, so after projective
# scaling its matrix has the exact form
#
#   [ a b c ]
#   [ 0 d e ]
#   [ 0 0 1 ],       a*d != 0.
#
# Coefficient comparison in F(A(X,Y,Z)) = lambda*F(X,Y,Z), saturated by a*d,
# then proves that the stabilizer scheme is the reduced identity point.  This
# is a geometric certificate: every ideal statement remains true after base
# change from Q to Qbar.

+ GeometricAutomorphismGroup
  -> new(@curve, @certificate)
    if !@certificate.certified?
      raise "geometric automorphism group needs a verified certificate"

  -> curve
    @curve

  -> certificate
    @certificate

  -> order
    1

  -> name
    "trivial"

  -> certified?
    @certificate.certified?

  -> to_s
    "Trivial geometric automorphism group"

  -> inspect
    to_s


+ PlaneQuarticAutomorphismCertificate
  -> new(@curve)
    validate_curve
    certify_unique_normalized_hyperflex
    build_stabilizer_ideal
    if !stabilizer_is_identity?
      raise "normalized hyperflex stabilizer is not certified trivial"

  -> curve
    @curve

  -> hyperflex
    @hyperflex

  -> tangent
    @tangent

  -> affine_hyperflex_ideal
    @affine_hyperflex_ideal

  -> stabilizer_ideal
    @stabilizer_ideal

  -> stabilizer_basis
    out = []
    @stabilizer_ideal.basis.each -> out.push(item)
    out

  -> method_name
    "canonical PGL3 stabilizer from a unique normalized hyperflex"

  -> geometric?
    true

  -> certified?
    return false if !@unique_hyperflex_certified
    return false if !@affine_hyperflex_ideal.unit?
    stabilizer_is_identity?

  -> to_s
    "PlaneQuarticAutomorphismCertificate(unique hyperflex, trivial PGL3 stabilizer)"

  -> inspect
    to_s

  -> validate_curve
    if @curve.class_name != "Curve"
      raise "geometric automorphisms need a Curve"
    if @curve.field.class_name != "RationalField"
      raise "geometric automorphism certification is currently implemented over Q"
    if @curve.degree != 4
      raise "geometric automorphism certification currently needs a plane quartic"
    if !@curve.nonsingular?
      raise "geometric automorphisms require a nonsingular curve"
    if @curve.space.dimension != 2
      raise "geometric automorphisms currently need a plane model"

  # A second hyperflex tangent cannot pass through P: its intersection with C
  # would contain P in addition to a point of multiplicity four, contradicting
  # Bezout.  Every possible second hyperflex tangent therefore has a unique
  # equation X=uY+vZ.  Its restriction is a fourth power exactly when
  #
  #   F(uY+vZ,Y,Z) = c*(Y-rZ)^4,
  #
  # where c is the nonzero Y^4 coefficient of F(X,Y,0).  Coefficient
  # comparison gives an ideal in Q[u,v,r]; the unit ideal proves over Qbar
  # that no such tangent exists.
  -> certify_unique_normalized_hyperflex
    ring = @curve.space.ring
    x = ring.generator(0)
    y = ring.generator(1)
    z = ring.generator(2)
    equation = @curve.equation

    infinity_coefficient = equation.coeff([0, 4, 0])
    infinity_model = y**4 * infinity_coefficient
    infinity_restriction = equation.substitute(2, 0)
    if ring.field.zero?(infinity_coefficient) || !infinity_restriction.eql?(infinity_model)
      raise "normalized hyperflex strategy needs C intersect Z=0 only at [1:0:0]"

    point = @curve.space.point(1, 0, 0)
    fx_at_point = equation.derivative(0).evaluate(point.coordinates)
    fy_at_point = equation.derivative(1).evaluate(point.coordinates)
    fz_at_point = equation.derivative(2).evaluate(point.coordinates)
    wrong_tangent = !ring.field.zero?(fx_at_point)
    wrong_tangent = wrong_tangent || !ring.field.zero?(fy_at_point)
    wrong_tangent = wrong_tangent || ring.field.zero?(fz_at_point)
    if wrong_tangent
      raise "normalized hyperflex strategy needs tangent line Z=0 at [1:0:0]"

    hyperflex_ring = PolynomialRing.new([:u, :v, :r], ring.field, :grevlex)
    binary_ring = PolynomialRing.new(
      [:Y, :Z, :u, :v, :r], ring.field, :grevlex)
    binary_variables = binary_ring.generators
    binary_y = binary_variables[0]
    binary_z = binary_variables[1]
    u = binary_variables[2]
    v = binary_variables[3]
    r = binary_variables[4]
    restricted = compose_into(
      equation,
      [u * binary_y + v * binary_z, binary_y, binary_z],
      binary_ring)
    fourth_power = (binary_y - r * binary_z)**4 * infinity_coefficient
    hyperflex_equations = coefficient_polynomials(
      restricted - fourth_power, hyperflex_ring, 2)
    @affine_hyperflex_ideal = Ideal.new(hyperflex_equations)
    if !@affine_hyperflex_ideal.unit?
      raise "normalized hyperflex is not certified unique over the algebraic closure"

    @hyperflex = point
    @tangent = Line.new(@curve.space, z)
    @unique_hyperflex_certified = true

  -> compose_into(source, substitutions, target_ring)
    result = target_ring.zero
    source.each_term -> (coefficient, exponents)
      term = target_ring.constant(coefficient)
      i = 0
      while i < substitutions.size
        term = term * substitutions[i]**exponents[i] if exponents[i] > 0
        i += 1
      result = result + term
    result

  -> same_prefix?(left, right)
    return false if left.size != right.size
    i = 0
    while i < left.size
      return false if left[i] != right[i]
      i += 1
    true

  # Regard a polynomial in X,Y,Z and parameter variables as a polynomial in
  # X,Y,Z with coefficients in the parameter ring.
  -> coefficient_polynomials(polynomial, parameter_ring, prefix_count = 3)
    groups = []
    polynomial.each_term -> (coefficient, exponents)
      prefix = []
      i = 0
      while i < prefix_count
        prefix.push(exponents[i])
        i += 1
      found = -1
      i = 0
      while i < groups.size
        if same_prefix?(groups[i][0], prefix)
          found = i
          break
        i += 1
      if found < 0
        groups.push([prefix, []])
        found = groups.size - 1

      parameter_exponents = []
      i = prefix_count
      while i < exponents.size
        parameter_exponents.push(exponents[i])
        i += 1
      groups[found][1].push([coefficient, parameter_exponents])

    coefficients = []
    groups.each -> (group)
      value = Polynomial.new(parameter_ring, group[1])
      coefficients.push(value) if !value.zero?
    coefficients

  -> build_stabilizer_ideal
    field = @curve.field
    parameter_ring = PolynomialRing.new(
      [:a, :b, :c, :d, :e, :lambda, :inverse], field, :grevlex)
    parameters = parameter_ring.generators
    a = parameters[0]
    b = parameters[1]
    c = parameters[2]
    d = parameters[3]
    e = parameters[4]
    scale = parameters[5]
    inverse = parameters[6]

    combined_ring = PolynomialRing.new(
      [:X, :Y, :Z, :a, :b, :c, :d, :e, :lambda, :inverse],
      field, :grevlex)
    variables = combined_ring.generators
    x = variables[0]
    y = variables[1]
    z = variables[2]
    ca = variables[3]
    cb = variables[4]
    cc = variables[5]
    cd = variables[6]
    ce = variables[7]
    cscale = variables[8]

    transformed_coordinates = [
      x * ca + y * cb + z * cc,
      y * cd + z * ce,
      z
    ]
    identity_coordinates = [x, y, z]
    transformed = compose_into(
      @curve.equation, transformed_coordinates, combined_ring)
    original = compose_into(
      @curve.equation, identity_coordinates, combined_ring)
    comparison = transformed - original * cscale

    equations = coefficient_polynomials(comparison, parameter_ring)
    equations.push(inverse * a * d - parameter_ring.one)
    @stabilizer_ideal = Ideal.new(equations)
    @stabilizer_identity_coordinates = [1, 0, 0, 1, 0, 1, 1]
    @stabilizer_identity_equations = [
      a - 1, b, c, d - 1, e, scale - 1, inverse - 1
    ]

  -> stabilizer_is_identity?
    # The displayed identity matrix is an actual solution, so containment of
    # every coordinate difference proves equality with that reduced point
    # rather than an accidentally empty saturated scheme.
    @stabilizer_ideal.source_generators.each ->
      value = item.evaluate(@stabilizer_identity_coordinates)
      return false if !@curve.field.zero?(value)
    @stabilizer_identity_equations.each ->
      return false if !@stabilizer_ideal.contains?(item)
    true


+ Curve
  -> geometric_automorphisms
    certificate = PlaneQuarticAutomorphismCertificate.new(self)
    GeometricAutomorphismGroup.new(self, certificate)
