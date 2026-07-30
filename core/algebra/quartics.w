# Exact lines and plane-quartic intersections.
#
# A line in P^2 is stored as its canonical dual point [a:b:c], representing
# aX + bY + cZ = 0.  Its parameterization is a deterministic linear map
# P^1 -> P^2.  Restriction therefore uses ordinary exact Polynomial
# arithmetic over the ambient coefficient field.

+ Line
  -> new(@space, equation_or_coefficients)
    initialize_line(equation_or_coefficients, false)

  -> new(@space, equation_or_coefficients, raw)
    initialize_line(equation_or_coefficients, raw)

  -> .raw(space, coefficients)
    Line.new(space, coefficients, true)

  -> initialize_line(equation_or_coefficients, raw)
    if @space.dimension != 2
      raise "a line needs a projective plane"

    coefficients = nil
    if equation_or_coefficients.class_name == "Array"
      if equation_or_coefficients.size != 3
        raise "a plane line needs three coefficients"
      coefficients = []
      equation_or_coefficients.each ->
        coefficient = raw ? @space.field.normalize_element(item) : @space.field.coerce(item)
        coefficients.push(coefficient)
    elsif equation_or_coefficients.class_name == "Polynomial"
      candidate = @space.ring.coerce(equation_or_coefficients)
      if candidate.zero? || !candidate.homogeneous? || candidate.degree != 1
        raise "a line equation must be a nonzero homogeneous linear polynomial"
      coefficients = [
        candidate.coeff([1, 0, 0]),
        candidate.coeff([0, 1, 0]),
        candidate.coeff([0, 0, 1])
      ]
    else
      raise "Line.new needs a linear polynomial or three coefficients"

    @coefficients = @space.field.normalize_projective_coordinates(coefficients)
    @equation = polynomial_from_coefficients(@coefficients)
    initialize_parameterization

  -> space
    @space

  -> field
    @space.field

  -> coefficients
    out = []
    @coefficients.each -> out.push(item)
    out

  -> equation
    @equation

  -> parameter_ring
    @parameter_ring

  -> parameterization
    out = []
    @parameterization.each -> out.push(item)
    out

  -> polynomial_from_coefficients(coefficients)
    terms = []
    i = 0
    while i < 3
      exponents = [0, 0, 0]
      exponents[i] = 1
      terms.push([coefficients[i], exponents])
      i += 1
    Polynomial.new(@space.ring, terms)

  -> parameter_linear_form(left, right)
    Polynomial.new(
      @parameter_ring,
      [[left, [1, 0]], [right, [0, 1]]])

  # Prefer the final nonzero coefficient as pivot. Thus Z = 0 is
  # parameterized by [X:Y:Z] = [X:Y:0], preserving the useful ambient names.
  -> initialize_parameterization
    pivot = 2
    while pivot >= 0 && field.zero?(@coefficients[pivot])
      pivot -= 1
    # Projective normalization rejected the all-zero case.
    raise "line parameterization has no pivot" if pivot < 0

    free = []
    i = 0
    while i < 3
      free.push(i) if i != pivot
      i += 1
    @free_indices = free
    @parameter_ring = PolynomialRing.new(
      [@space.coordinate_names[free[0]], @space.coordinate_names[free[1]]],
      field,
      @space.ring.order)
    parameters = @parameter_ring.generators

    @parameterization = []
    i = 0
    while i < 3
      if i == free[0]
        @parameterization.push(parameters[0])
      elsif i == free[1]
        @parameterization.push(parameters[1])
      else
        first = field.divide(
          field.negate(@coefficients[free[0]]), @coefficients[pivot])
        second = field.divide(
          field.negate(@coefficients[free[1]]), @coefficients[pivot])
        @parameterization.push(parameter_linear_form(first, second))
      i += 1
    self

  -> restrict(polynomial)
    if polynomial.class_name != "Polynomial"
      raise "line restriction needs a Polynomial"
    if polynomial.ring != @space.ring
      raise "line and polynomial belong to different coordinate rings"

    result = @parameter_ring.zero
    polynomial.each_term -> (coefficient, exponents)
      term = @parameter_ring.monomial_raw(coefficient, [0, 0])
      i = 0
      while i < 3
        term = term * (@parameterization[i] ** exponents[i])
        i += 1
      result = result + term
    result

  # Dehomogenize a binary line restriction into the complementary affine
  # parameter. chart=1 means [u:v]=[t:1]; chart=0 means [1:t]. The returned
  # polynomial lives in an actual univariate ring, so exact factorization and
  # residue-degree computations apply directly.
  -> affine_restriction(polynomial, chart = 1)
    if chart != 0 && chart != 1
      raise "line parameter chart must be zero or one"
    restricted = restrict(polynomial)
    remaining = chart == 0 ? 1 : 0
    affine_ring = PolynomialRing.new(
      [@parameter_ring.names[remaining]], field)
    terms = []
    restricted.each_term -> (coefficient, exponents)
      terms.push([coefficient, [exponents[remaining]]])
    Polynomial.new(affine_ring, terms)

  -> point(parameters)
    if parameters.class_name != "Array" || parameters.size != 2
      raise "a line parameter point needs two homogeneous coordinates"
    converted = []
    parameters.each -> (parameter)
      converted.push(field.coerce(parameter))
    point_raw(converted)

  -> point_raw(parameters)
    if parameters.class_name != "Array" || parameters.size != 2
      raise "a line parameter point needs two homogeneous coordinates"
    normalized = field.normalize_projective_coordinates(parameters)
    coordinates = []
    @parameterization.each ->
      coordinates.push(item.evaluate_raw(normalized))
    @space.point_raw(coordinates)

  -> contains?(point)
    return false if point.class_name != "ProjectivePoint"
    return false if point.space != @space
    field.zero?(@equation.evaluate_raw(point.coordinates))

  -> ==/1
    self.eql?(@1)

  -> eql?(other)
    return false if other.class_name != "Line" || other.space != @space
    i = 0
    while i < 3
      return false if !field.equal?(@coefficients[i], other.coefficients[i])
      i += 1
    true

  -> to_s
    "Line(" + @equation.to_s + " = 0)"

  -> inspect
    to_s


+ Polynomial
  # Substitute the exact P^1 parameterization of a plane line.  A homogeneous
  # degree-d plane form becomes a homogeneous binary degree-d form.
  -> restrict_to(line)
    if line.class_name != "Line"
      raise "Polynomial#restrict_to needs a Line"
    line.restrict(self)


+ LineIntersectionCertificate
  -> new(@curve, @line, @divisor, @factorization,
         @parameter_chart = 1)

  -> curve
    @curve

  -> line
    @line

  -> divisor
    @divisor

  -> factorization
    @factorization

  -> parameter_chart
    @parameter_chart

  -> verified?
    return false if @curve.class_name != "Curve"
    return false if @line.class_name != "Line" || @line.space != @curve.space
    return false if @divisor.class_name != "Divisor" || @divisor.curve != @curve
    return false if @factorization.class_name != "PolynomialFactorization"
    return false if @parameter_chart != 0 && @parameter_chart != 1
    restricted = @curve.equation.restrict_to(@line)
    return false if restricted.zero?
    return false if !restricted.homogeneous?
    return false if restricted.degree != @curve.degree
    affine = @line.affine_restriction(
      @curve.equation, @parameter_chart)
    return false if !@factorization.polynomial.eql?(affine)
    return false if !@factorization.certificate.verified?
    expected = @curve.intersection_divisor_from_factorization(
      @line, @factorization, @parameter_chart)
    expected.eql?(@divisor)

  -> certified?
    verified?

  -> to_s
    "LineIntersectionCertificate(degree " + @divisor.degree.to_s + ")"

  -> inspect
    to_s


+ LineIntersection
  -> new(@curve, @line, @divisor, @factorization,
         @parameter_chart = 1)
    if !certificate.verified?
      raise "line-intersection certificate failed"

  -> curve
    @curve

  -> line
    @line

  -> divisor
    @divisor

  -> factorization
    @factorization

  -> parameter_chart
    @parameter_chart

  -> certificate
    LineIntersectionCertificate.new(
      @curve, @line, @divisor, @factorization, @parameter_chart)

  -> certified?
    certificate.verified?

  -> to_s
    "LineIntersection(" + @divisor.to_s + ")"

  -> inspect
    to_s


+ Curve
  # Reconstruct the scheme-theoretic line-intersection divisor from a
  # certified factorization of one affine P^1 chart. Linear factors become
  # rational Place objects; irreducibles of degree > 1 become ClosedPlace
  # objects carrying their residue polynomial and proof. The omitted degree
  # is precisely the multiplicity of the rational point at infinity.
  -> intersection_divisor_from_factorization(line, factorization, parameter_chart = 1)
    if line.class_name != "Line" || line.space != @space
      raise "intersection line belongs to a different projective plane"
    if factorization.class_name != "PolynomialFactorization"
      raise "line intersection needs a certified polynomial factorization"
    if parameter_chart != 0 && parameter_chart != 1
      raise "line parameter chart must be zero or one"
    affine = line.affine_restriction(@equation, parameter_chart)
    if !factorization.polynomial.eql?(affine)
      raise "factorization belongs to a different line restriction"
    if !factorization.certified?
      raise "line-restriction factorization is not certified"

    terms = []
    infinity_multiplicity = degree - affine.degree
    if infinity_multiplicity < 0
      raise "line restriction exceeds the curve's degree"
    if infinity_multiplicity > 0
      infinity_parameters = parameter_chart == 1 ? [field.one, field.zero] : [field.zero, field.one]
      terms.push([
        infinity_multiplicity,
        place(line.point_raw(infinity_parameters))
      ])

    factors = factorization.factors
    i = 0
    while i < factors.size
      factor = factors[i]
      if factor.degree == 1
        root = field.divide(
          field.negate(factor.coeff(0)), factor.coeff(1))
        parameters = parameter_chart == 1 ? [root, field.one] : [field.one, root]
        terms.push([1, place(line.point_raw(parameters))])
      elsif factor.degree > 1
        terms.push([
          1,
          ClosedPlace.new(
            self, line, factor, parameter_chart, factorization)
        ])
      i += 1

    divisor = Divisor.new(self, terms)
    if divisor.degree != degree
      raise "line-intersection divisor failed Bezout degree"
    divisor

  # Exact line intersection over coefficient fields with certified
  # univariate factorization (currently Q and arbitrary finite fields).
  -> line_intersection(line, factor_search_limit = 250_000)
    if line.class_name != "Line" || line.space != @space
      raise "intersection line belongs to a different projective plane"
    restricted = @equation.restrict_to(line)
    if restricted.zero?
      raise "intersection divisor is undefined when the line is a curve component"
    if !restricted.homogeneous? || restricted.degree != degree
      raise "line restriction lost the curve's homogeneous degree"

    parameter_chart = 1
    affine = line.affine_restriction(@equation, parameter_chart)
    factorization = affine.factor_with_certificate(factor_search_limit)
    divisor = intersection_divisor_from_factorization(
      line, factorization, parameter_chart)
    LineIntersection.new(
      self, line, divisor, factorization, parameter_chart)

  -> intersection(line, factor_search_limit = 250_000)
    line_intersection(line, factor_search_limit)

  -> intersection_divisor(line, factor_search_limit = 250_000)
    line_intersection(line, factor_search_limit).divisor

  -> intersection_certificate(line, factor_search_limit = 250_000)
    line_intersection(line, factor_search_limit).certificate

  -> binary_quartic_coefficients(polynomial)
    if polynomial.ring.arity != 2 || polynomial.degree != 4 || !polynomial.homogeneous?
      raise "bitangent test needs a homogeneous binary quartic"
    [
      polynomial.coeff([4, 0]),
      polynomial.coeff([3, 1]),
      polynomial.coeff([2, 2]),
      polynomial.coeff([1, 3]),
      polynomial.coeff([0, 4])
    ]

  # Canonical projective key for a nonzero coefficient vector over F_p.
  # Integer base-q encoding avoids dynamic String keys in this hot loop.
  -> finite_projective_key(coefficients)
    normalized = field.normalize_projective_coordinates(coefficients)
    q = field.order
    key = 0 ## big
    normalized.each -> key = key * q + item
    key

  -> quadratic_square_key(a, b, c)
    two = field.coerce(2)
    a2 = field.multiply(a, a)
    ab2 = field.multiply(two, field.multiply(a, b))
    middle = field.add(
      field.multiply(b, b),
      field.multiply(two, field.multiply(a, c)))
    bc2 = field.multiply(two, field.multiply(b, c))
    c2 = field.multiply(c, c)
    finite_projective_key([a2, ab2, middle, bc2, c2])

  -> add_quadratic_square_keys(keys)
    q = field.order
    b = 0
    while b < q
      c = 0
      while c < q
        keys[quadratic_square_key(field.one, b, c)] = true
        c += 1
      b += 1
    c = 0
    while c < q
      keys[quadratic_square_key(field.zero, field.one, c)] = true
      c += 1
    keys[quadratic_square_key(field.zero, field.zero, field.one)] = true
    keys

  -> add_bitangent_if_square(lines, square_keys, coefficients)
    line = Line.raw(@space, coefficients)
    restricted = @equation.restrict_to(line)
    return nil if restricted.zero?
    coefficient_vector = binary_quartic_coefficients(restricted)
    key = finite_projective_key(coefficient_vector)
    lines.push(line) if square_keys.has_key?(key)

  # Complete base-field-rational bitangent enumeration for a plane quartic
  # over an odd finite field. There are q^2+q+1 dual lines; the same number of
  # projective binary quadratics. Precomputing their square classes makes the
  # scan O(q^2) exact field work rather than O(q^4).
  -> bitangents
    if field.class_name != "FiniteField"
      raise "bitangents require a finite coefficient field"
    if field.characteristic == 2
      raise "bitangent square testing requires odd characteristic"
    if degree != 4
      raise "bitangents currently require a plane quartic"

    if @bitangents_cache == nil
      square_keys = {}
      add_quadratic_square_keys(square_keys)
      lines = []
      q = field.order

      b = 0
      while b < q
        c = 0
        while c < q
          add_bitangent_if_square(lines, square_keys, [field.one, b, c])
          c += 1
        b += 1
      c = 0
      while c < q
        add_bitangent_if_square(
          lines, square_keys, [field.zero, field.one, c])
        c += 1
      add_bitangent_if_square(
        lines, square_keys, [field.zero, field.zero, field.one])
      @bitangents_cache = lines

    out = []
    @bitangents_cache.each -> out.push(item)
    out
