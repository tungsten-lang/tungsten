# Certified finite kernels and geometric setup for explicit 2-descent.
#
# Bruin--Poonen--Stoll descent on a smooth plane quartic has two very
# different parts:
#
#   1. arithmetic producers (bitangents, an etale algebra, maximal orders,
#      S-units/class groups, Galois modules, and local images);
#   2. a finite F2 intersection.
#
# This file keeps those trust boundaries visible.  The finite intersection is
# replay-certified here.  It becomes an arithmetic certificate only when
# every condition carries its own independently verified producer
# certificate.  A fake/explicit Selmer intersection is never silently
# promoted to the true Selmer group or to a Mordell--Weil rank.

+ DenseIntegerPolynomialArithmetic
  -> .copy(values)
    out = []
    values.each -> out.push(item)
    out

  -> .trim(values)
    out = DenseIntegerPolynomialArithmetic.copy(values)
    while out.size > 1 && out[out.size - 1] == 0
      out.delete_at(out.size - 1)
    out.push(0) if out.size == 0
    out

  -> .zero?(values)
    reduced = DenseIntegerPolynomialArithmetic.trim(values)
    reduced.size == 1 && reduced[0] == 0

  -> .multiply(left, right)
    a = DenseIntegerPolynomialArithmetic.trim(left)
    b = DenseIntegerPolynomialArithmetic.trim(right)
    return [0] if DenseIntegerPolynomialArithmetic.zero?(a)
    return [0] if DenseIntegerPolynomialArithmetic.zero?(b)
    out = []
    (a.size + b.size - 1).times -> out.push(0)
    i = 0
    while i < a.size
      j = 0
      while j < b.size
        out[i + j] = out[i + j] + a[i] * b[j]
        j += 1
      i += 1
    DenseIntegerPolynomialArithmetic.trim(out)

  -> .add_scaled_shift(target, source, scale, shift)
    out = DenseIntegerPolynomialArithmetic.copy(target)
    needed = source.size + shift
    out.push(0) while out.size < needed
    i = 0
    while i < source.size
      out[i + shift] = out[i + shift] + source[i] * scale
      i += 1
    DenseIntegerPolynomialArithmetic.trim(out)

  # Fraction-free univariate remainder.  Each step replaces
  # R by lc(F)R-lc(R)x^dF, so R=0 proves exact divisibility over Q without
  # constructing any rational intermediate coefficients.
  -> .pseudo_remainder(dividend, divisor)
    f = DenseIntegerPolynomialArithmetic.trim(divisor)
    raise "dense pseudo-division by zero" if DenseIntegerPolynomialArithmetic.zero?(f)
    r = DenseIntegerPolynomialArithmetic.trim(dividend)
    degree = f.size - 1
    leading = f[degree]
    steps = 0
    while !DenseIntegerPolynomialArithmetic.zero?(r) && r.size - 1 >= degree
      raise "dense pseudo-remainder limit exceeded" if steps >= 20_000
      shift = r.size - 1 - degree
      top = r[r.size - 1]
      scaled = []
      r.each -> scaled.push(item * leading)
      r = DenseIntegerPolynomialArithmetic.add_scaled_shift(
        scaled, f, 0 - top, shift)
      steps += 1
    r

  # Exact dense division over Z.  Returning nil at the first nonintegral
  # leading quotient is a conclusive failure; successful zero remainder
  # returns the integral quotient.  The shell-width bitangent proof data are
  # scaled so this inexpensive path applies.
  -> .divide_exact(dividend, divisor)
    f = DenseIntegerPolynomialArithmetic.trim(divisor)
    raise "dense division by zero" if DenseIntegerPolynomialArithmetic.zero?(f)
    r = DenseIntegerPolynomialArithmetic.trim(dividend)
    too_small = r.size < f.size
    too_small = false if DenseIntegerPolynomialArithmetic.zero?(r)
    return nil if too_small
    quotient = []
    width = r.size >= f.size ? r.size - f.size + 1 : 1
    width.times -> quotient.push(0)
    leading = f[f.size - 1]
    while !DenseIntegerPolynomialArithmetic.zero?(r) && r.size >= f.size
      shift = r.size - f.size
      top = r[r.size - 1]
      return nil if top % leading != 0
      coefficient = top / leading
      quotient[shift] = quotient[shift] + coefficient
      r = DenseIntegerPolynomialArithmetic.add_scaled_shift(
        r, f, 0 - coefficient, shift)
    return nil if !DenseIntegerPolynomialArithmetic.zero?(r)
    DenseIntegerPolynomialArithmetic.trim(quotient)


+ SelmerConstraintBlock
  -> new(@name, @width, matrix, right_hand_side, @arithmetic_certificate = nil)
    @name = @name.to_s
    @system = F2LinearSystem.new(@width)
    @system.add_equations(matrix, right_hand_side)

  -> name
    @name

  -> width
    @width

  -> matrix
    @system.matrix

  -> right_hand_side
    @system.right_hand_side

  -> finite_certificate
    @system.certificate

  -> arithmetic_certificate
    @arithmetic_certificate

  -> arithmetic_certified?
    return false if @arithmetic_certificate == nil
    return false if !@arithmetic_certificate.respond_to?("certified?")
    return false if !@arithmetic_certificate.respond_to?("verified?")
    return false if !@arithmetic_certificate.respond_to?(
      "verify_selmer_constraint")
    return false if !@arithmetic_certificate.verified?
    return false if !@arithmetic_certificate.certified?
    @arithmetic_certificate.verify_selmer_constraint(
      @name, @width, self.matrix, self.right_hand_side)

  -> certified?
    finite_certificate.certified? && arithmetic_certified?

  -> to_s
    status = arithmetic_certified? ? "arithmetic certified" : "finite only"
    @name + " (" + status + ")"

  -> inspect
    to_s


+ ExplicitSelmerIntersectionCertificate
  -> new(@width, blocks)
    @blocks = []
    blocks.each -> @blocks.push(item)
    system = F2LinearSystem.new(@width)
    @blocks.each -> (block)
      if block.class_name != "SelmerConstraintBlock"
        raise "explicit Selmer certificates need SelmerConstraintBlock inputs"
      raise "Selmer constraint width mismatch" if block.width != @width
      right = block.right_hand_side
      right.each ->
        raise "Selmer subgroup constraints must be homogeneous" if item != 0
      system.add_equations(block.matrix, right)
    @linear_certificate = system.certificate

  -> width
    @width

  -> blocks
    out = []
    @blocks.each -> out.push(item)
    out

  -> linear_certificate
    @linear_certificate

  -> finite_certified?
    @linear_certificate.certified?

  -> arithmetic_certified?
    i = 0
    while i < @blocks.size
      return false if !@blocks[i].arithmetic_certified?
      i += 1
    true

  # `certified?` has the deliberately narrow meaning recorded by the class
  # name: the supplied explicit Selmer conditions and their intersection are
  # certified.  It does not assert equality with the cohomological Selmer
  # group.
  -> certified?
    finite_certified? && arithmetic_certified?

  -> dimension
    @linear_certificate.kernel_dimension

  -> basis
    @linear_certificate.kernel_basis

  -> rank_upper_bound
    raise "an explicit Selmer intersection is not a rank certificate; certify the BPS comparison kernel and rational 2-torsion first"

  -> true_selmer?
    false

  -> to_s
    label = certified? ? "certified" : "finite-only"
    "ExplicitSelmerIntersection(dim=" + dimension.to_s + ", " + label + ")"

  -> inspect
    to_s


+ SelmerConstraintSystem
  -> new(@width)
    if !F2LinearAlgebra.integer?(@width) || @width < 0
      raise "Selmer ambient dimension must be a nonnegative integer"
    @blocks = []

  -> width
    @width

  -> blocks
    out = []
    @blocks.each -> out.push(item)
    out

  -> add_condition(name, matrix, arithmetic_certificate = nil)
    right = []
    matrix.size.times -> right.push(0)
    block = SelmerConstraintBlock.new(
      name, @width, matrix, right, arithmetic_certificate)
    @blocks.push(block)
    self

  -> intersection_certificate
    ExplicitSelmerIntersectionCertificate.new(@width, @blocks)

  -> solve
    intersection_certificate


# Recomputes the exact geometric hypotheses used by the plane-quartic descent
# setup.  `Curve#nonsingular?` is an exact ideal calculation; a resource
# failure raises rather than becoming a false smoothness certificate.
+ SmoothPlaneQuarticCertificate
  -> new(@curve)

  -> curve
    @curve

  -> verified?
    return false if @curve.class_name != "Curve"
    return false if @curve.space.dimension != 2 || @curve.degree != 4
    return false if @curve.field.class_name != "RationalField"
    @curve.nonsingular?

  -> certified?
    verified?

  -> to_s
    "SmoothPlaneQuarticCertificate(" + @curve.equation.to_s + ")"

  -> inspect
    to_s


# The classical exhaustion theorem used by the focused bitangent checker:
# over an algebraic closure of a characteristic-zero field, a smooth plane
# quartic has exactly 28 distinct bitangent lines (equivalently, 28 odd theta
# characteristics).  This object checks the theorem's input hypotheses and
# makes the imported theorem visible in the composed certificate.
+ SmoothPlaneQuarticBitangentCountCertificate
  -> new(@curve)

  -> curve
    @curve

  -> geometric_count
    28

  -> theorem
    "smooth plane quartic over characteristic zero has 28 geometric bitangents"

  # The theorem is a documented mathematical import.  This certificate
  # verifies its hypotheses; it does not claim that the theorem's proof has
  # been formalized in a proof assistant.
  -> proof_kind
    :trusted_theorem_import

  -> kernel_checked?
    false

  -> verified?
    SmoothPlaneQuarticCertificate.new(@curve).verified?

  -> certified?
    verified?

  -> to_s
    "SmoothPlaneQuarticBitangentCountCertificate(28)"

  -> inspect
    to_s


# A focused certificate for a rational hyperflex.  It verifies
#     l.C = 4P = 2(2P)
# exactly, which supplies the rational member needed by BPS section 6.5 to
# construct a 27-member true setup from the 28-member fake setup.
+ RationalHyperflexCertificate
  -> new(@curve, @line)
    @intersection = nil
    @place = nil
    begin
      candidate = @curve.intersection_divisor(@line)
      terms = candidate.terms
      if terms.size == 1 && terms[0][0] == 4
        @intersection = candidate
        @place = terms[0][1]
    rescue e
      @intersection = nil
      @place = nil

  -> curve
    @curve

  -> line
    @line

  -> point
    @place == nil ? nil : @place.point

  -> place
    @place

  -> intersection_divisor
    @intersection

  -> half_intersection
    raise "unverified hyperflex has no half-intersection divisor" if !verified?
    @place * 2

  -> verified?
    return false if !SmoothPlaneQuarticCertificate.new(@curve).verified?
    return false if @line.class_name != "Line" || @line.space != @curve.space
    return false if @intersection == nil || @place == nil
    expected = @place * 4
    return false if @intersection != expected
    restricted = @curve.equation.restrict_to(@line)
    return false if restricted.zero? || restricted.terms.size != 1
    restricted.degree == 4

  -> certified?
    verified?

  -> to_s
    return "UnverifiedRationalHyperflex" if !verified?
    "RationalHyperflex(" + @line.to_s + ", " + point.to_s + ")"

  -> inspect
    to_s


# One affine chart of the geometric bitangent scheme.  A dual line is
#
#   X_pivot - l0 X_free0 - l1 X_free1 = 0.
#
# Substitution gives a binary quartic.  It is geometrically a square exactly
# when it equals (q0 U^2 + q1 UV + q2 V^2)^2 over the algebraic closure.
# Eliminating q0,q1,q2 leaves the line scheme in (l0,l1).
+ PlaneQuarticBitangentChart
  -> new(@curve, @pivot)
    if !SmoothPlaneQuarticCertificate.new(@curve).verified?
      raise "bitangent schemes need a smooth plane quartic over ℚ"
    if @pivot < 0 || @pivot >= 3
      raise "bitangent chart pivot is out of range"
    @free_indices = []
    i = 0
    while i < 3
      @free_indices.push(i) if i != @pivot
      i += 1
    @workspace_ring = PolynomialRing.new(
      [:__bitangent_q0, :__bitangent_q1, :__bitangent_q2,
       :__bitangent_l0, :__bitangent_l1],
      @curve.field,
      MonomialOrder.product(3, :lex, :lex))
    @line_ring = PolynomialRing.new(
      [:__bitangent_l0, :__bitangent_l1], @curve.field, :lex)
    @incidence_ideal = nil
    @line_ideal = nil

  -> curve
    @curve

  -> pivot
    @pivot

  -> free_indices
    F2LinearAlgebra.copy_vector(@free_indices)

  -> workspace_ring
    @workspace_ring

  -> line_ring
    @line_ring

  -> .binomial(n, k)
    return 0 if k < 0 || k > n
    return 1 if k == 0 || k == n
    result = 1
    i = 1
    use_k = k < n - k ? k : n - k
    while i <= use_k
      result = result * (n - use_k + i) / i
      i += 1
    result

  # Coefficients of U^(4-i)V^i after substituting the affine dual line.
  -> binary_coefficients
    coefficients = []
    5.times -> coefficients.push(@workspace_ring.zero)
    field = @curve.field
    @curve.equation.each_term -> (coefficient, exponents)
      pivot_power = exponents[@pivot]
      left_power = exponents[@free_indices[0]]
      right_power = exponents[@free_indices[1]]
      k = 0
      while k <= pivot_power
        choose = PlaneQuarticBitangentChart.binomial(pivot_power, k)
        scalar = field.multiply(coefficient, field.coerce(choose))
        workspace_exponents = [
          0, 0, 0, pivot_power - k, k
        ]
        coefficient_term = @workspace_ring.monomial_raw(
          scalar, workspace_exponents)
        v_power = right_power + k
        u_power = left_power + pivot_power - k
        if u_power + v_power != 4
          raise "quartic line substitution lost homogeneity"
        coefficients[v_power] = coefficients[v_power] + coefficient_term
        k += 1
    coefficients

  -> equations
    coefficients = binary_coefficients
    generators = @workspace_ring.generators
    q0 = generators[0]
    q1 = generators[1]
    q2 = generators[2]
    two = @curve.field.coerce(2)
    [
      coefficients[0] - q0 * q0,
      coefficients[1] - q0 * q1 * two,
      coefficients[2] - (q1 * q1 + q0 * q2 * two),
      coefficients[3] - q1 * q2 * two,
      coefficients[4] - q2 * q2
    ]

  -> line_binary_coefficients
    out = []
    binary_coefficients.each -> out.push(item.drop_variables(3, @line_ring))
    out

  # When the U^4 coefficient a is a nonzero constant, the square root
  # variables can be eliminated without a Gröbner calculation.  Writing
  #
  #   a=r^2, b=2rs, c=s^2+2rt, d=2st, e=t^2
  #
  # and N=4ac-b^2 gives exactly
  #
  #   8a^2 d = bN,        64a^3 e = N^2.
  #
  # Conversely these equations reconstruct r,s,t over the algebraic closure,
  # so they define the same line scheme on this open chart.
  -> direct_square_equations
    coefficients = line_binary_coefficients
    a = coefficients[0]
    return nil if !a.constant? || a.zero?
    b = coefficients[1]
    c = coefficients[2]
    d = coefficients[3]
    e = coefficients[4]
    n = a * c * 4 - b * b
    [
      a * a * d * 8 - b * n,
      a * a * a * e * 64 - n * n
    ]

  # If a is identically zero but b is a nonzero constant, no binary quartic
  # in the chart can be a square: r^2=a forces r=0, hence b=2rs=0.
  -> leading_terms_exclude_square?
    coefficients = line_binary_coefficients
    a = coefficients[0]
    b = coefficients[1]
    a.zero? && b.constant? && !b.zero?

  # In pivot chart 1, l0=0 is the boundary not already covered by pivot
  # chart 0.  The same leading-coefficient obstruction can certify that this
  # one-dimensional stratum contains no bitangent.
  -> first_parameter_zero_excludes_square?
    coefficients = line_binary_coefficients
    a = coefficients[0].substitute(0, 0)
    b = coefficients[1].substitute(0, 0)
    a.zero? && b.constant? && !b.zero?

  -> specialize_modulo(polynomial, u_image, modulus)
    ring = modulus.ring
    v = ring.generator(0)
    u_powers = [ring.one]
    i = 1
    while i <= polynomial.degree_in(0)
      u_powers.push((u_powers[i - 1] * u_image).rem(modulus))
      i += 1
    v_powers = [ring.one]
    i = 1
    while i <= polynomial.degree_in(1)
      v_powers.push((v_powers[i - 1] * v).rem(modulus))
      i += 1
    out = ring.zero
    polynomial.each_term -> (coefficient, exponents)
      term = (u_powers[exponents[0]] * v_powers[exponents[1]]).rem(
        modulus)
      term = term * coefficient
      out = (out + term).rem(modulus)
    out

  # Substitute u=U/D, clear D^deg_u once, and use fraction-free
  # pseudo-division by the integral factor.  This is the exact checker path
  # for large proof data: it avoids repeatedly reducing rational polynomials
  # whose common denominator would otherwise grow at every multiplication.
  -> specialize_cleared(polynomial, image_numerator,
                         image_denominator, factor)
    ring = factor.ring
    v = ring.generator(0)
    maximum = polynomial.degree_in(0)
    u_powers = [ring.one]
    i = 1
    while i <= maximum
      u_powers.push(u_powers[i - 1] * image_numerator)
      i += 1
    v_powers = [ring.one]
    i = 1
    while i <= polynomial.degree_in(1)
      v_powers.push(v_powers[i - 1] * v)
      i += 1
    out = ring.zero
    polynomial.each_term -> (coefficient, exponents)
      denominator_power = image_denominator ** (maximum - exponents[0])
      term = u_powers[exponents[0]] * v_powers[exponents[1]]
      term = term * coefficient * denominator_power
      out = out + term
    out.pseudo_remainder(factor, 0)

  -> dense_cleared_substitution(polynomial, image_coefficients,
                                 image_denominator)
    maximum = polynomial.degree_in(0)
    u_powers = [[1]]
    i = 1
    while i <= maximum
      u_powers.push(DenseIntegerPolynomialArithmetic.multiply(
        u_powers[i - 1], image_coefficients))
      i += 1
    out = [0]
    polynomial.each_term -> (coefficient, exponents)
      if coefficient.class_name == "Rational"
        raise "dense bitangent checker needs integral equations" if coefficient.denominator != 1
        scalar = coefficient.numerator
      else
        scalar = coefficient
      scalar = scalar * (image_denominator ** (maximum - exponents[0]))
      out = DenseIntegerPolynomialArithmetic.add_scaled_shift(
        out, u_powers[exponents[0]], scalar, exponents[1])
    out

  -> incidence_ideal
    @incidence_ideal = Ideal.new(equations) if @incidence_ideal == nil
    @incidence_ideal

  -> line_ideal
    if @line_ideal == nil
      if leading_terms_exclude_square?
        @line_ideal = Ideal.unit(@line_ring)
      else
        direct = direct_square_equations
        if direct == nil
          @line_ideal = incidence_ideal.eliminate(3)
        else
          @line_ideal = Ideal.new(direct)
    @line_ideal

  -> certificate
    BitangentChartCertificate.new(self)

  -> to_s
    "BitangentChart(pivot=" + @pivot.to_s + ")"

  -> inspect
    to_s


# A zero-dimensional affine bitangent chart in triangular form
#   l0 = h(l1),  g(l1) = 0.
# Squarefreeness of g proves that the projected chart is reduced and its
# degree is deg(g).
+ BitangentChartCertificate
  -> new(@chart)
    @relation = nil
    @eliminant = nil
    @univariate_eliminant = nil
    @chart.line_ideal.basis.each -> (polynomial)
      if polynomial.degree_in(0) == 0 && polynomial.degree_in(1) > 0
        @eliminant = polynomial
      elsif polynomial.degree_in(0) == 1
        @relation = polynomial
    if @eliminant != nil
      ring = PolynomialRing.new(
        [@eliminant.ring.names[1]], @eliminant.ring.field, :lex)
      @univariate_eliminant = @eliminant.drop_variables(1, ring)

  -> chart
    @chart

  -> relation
    @relation

  -> eliminant
    @univariate_eliminant

  -> degree
    @univariate_eliminant == nil ? -1 : @univariate_eliminant.degree

  -> squarefree?
    return false if @univariate_eliminant == nil
    @univariate_eliminant.squarefree?

  -> verified?
    return false if @chart.line_ideal.unit?
    return false if @chart.line_ideal.basis.size != 2
    return false if @relation == nil || @eliminant == nil
    # The leading l0 coefficient must be a nonzero constant, so l0 is a
    # unique polynomial function of every root of the eliminant.
    return false if @relation.degree_in(0) != 1
    mixed = false
    @relation.each_term -> (coefficient, exponents)
      mixed = true if exponents[0] == 1 && exponents[1] != 0
    return false if mixed
    leading = @relation.coeff([1, 0])
    return false if @relation.ring.field.zero?(leading)
    return false if @univariate_eliminant == nil
    return false if @univariate_eliminant.degree <= 0
    squarefree?

  -> certified?
    verified?

  -> to_s
    "BitangentChartCertificate(degree=" + degree.to_s + ")"

  -> inspect
    to_s


# A compact producer/checker boundary for a triangular bitangent chart.
# The producer supplies g(v) and u+h(v)=0; the checker substitutes the
# relation into the two exact square equations above and verifies both
# remainders modulo squarefree g.  This avoids asking the checker to repeat a
# costly Gröbner elimination while still checking every geometric root.
+ BitangentEtaleComponentCertificate
  -> new(@chart, @factor, @u_image)
    @image_numerator = nil
    @image_denominator = nil
    @dense_factor = nil
    @dense_image = nil
    @verified_cache = nil
    @verified_fingerprint = nil

  -> new(@chart, @factor, @u_image,
         @image_numerator, @image_denominator)
    @dense_factor = nil
    @dense_image = nil
    @verified_cache = nil
    @verified_fingerprint = nil

  -> new(@chart, @factor, @u_image,
         @image_numerator, @image_denominator,
         dense_factor, dense_image)
    @dense_factor = DenseIntegerPolynomialArithmetic.copy(dense_factor)
    @dense_image = DenseIntegerPolynomialArithmetic.copy(dense_image)
    @verified_cache = nil
    @verified_fingerprint = nil

  -> chart
    @chart

  -> factor
    Polynomial.new(@factor.ring, @factor.terms)

  -> u_image
    Polynomial.new(@u_image.ring, @u_image.terms)

  -> degree
    @factor.degree

  -> verified?
    fingerprint = proof_fingerprint
    if @verified_cache != nil && fingerprint == @verified_fingerprint
      return @verified_cache
    @verified_cache = verify_fresh
    @verified_fingerprint = fingerprint
    @verified_cache

  -> proof_fingerprint
    text = @chart.curve.equation.to_s + "|" + @chart.pivot.to_s
    text = text + "|" + @factor.to_s + "|" + @u_image.to_s
    text = text + "|" + @image_numerator.to_s
    text = text + "|" + @image_denominator.to_s
    text = text + "|" + @dense_factor.to_s + "|" + @dense_image.to_s
    text

  -> dense_polynomial(coefficients)
    return nil if coefficients == nil || coefficients.class_name != "Array"
    ring = @factor.ring
    variable = ring.generator(0)
    polynomial = ring.zero
    i = 0
    while i < coefficients.size
      coefficient = coefficients[i]
      return nil if !F2LinearAlgebra.integer?(coefficient)
      polynomial = polynomial + variable**i * coefficient
      i += 1
    polynomial

  # Every optimized proof payload must reconstruct the public polynomial data.
  # Otherwise a valid divisibility witness for one component could be attached
  # to an unrelated factor, image, or zero-denominator "substitution".
  -> proof_data_bound?
    if @image_numerator == nil
      return false if @image_denominator != nil
      return false if @dense_factor != nil || @dense_image != nil
      return true

    return false if @image_numerator.class_name != "Polynomial"
    return false if @image_numerator.ring != @factor.ring
    field = @factor.ring.field
    denominator = field.coerce(@image_denominator)
    return false if field.zero?(denominator)
    inverse = field.divide(field.one, denominator)
    return false if !(@image_numerator * inverse).eql?(@u_image)

    if @dense_factor == nil
      return @dense_image == nil

    return false if @dense_image == nil
    return false if !F2LinearAlgebra.integer?(@image_denominator)
    reconstructed_factor = dense_polynomial(@dense_factor)
    reconstructed_image = dense_polynomial(@dense_image)
    return false if reconstructed_factor == nil || reconstructed_image == nil
    return false if !reconstructed_factor.eql?(@factor)
    reconstructed_image.eql?(@image_numerator)

  -> verify_fresh
    answer = false
    begin
      answer = verify_unchecked
    rescue e
      answer = false
    answer

  -> verify_unchecked
    return false if @factor.ring != @u_image.ring
    return false if @factor.degree <= 0 || @u_image.degree >= @factor.degree
    return false if !@factor.squarefree?
    return false if !proof_data_bound?
    equations = @chart.direct_square_equations
    return false if equations == nil
    i = 0
    while i < equations.size
      equation = equations[i]
      if @dense_factor != nil
        specialized = @chart.dense_cleared_substitution(
          equation, @dense_image, @image_denominator)
        quotient = DenseIntegerPolynomialArithmetic.divide_exact(
          specialized, @dense_factor)
        zero = quotient != nil
      elsif @image_numerator == nil
        specialized = @chart.specialize_modulo(
          equation, @u_image, @factor)
        zero = specialized.zero?
      else
        specialized = @chart.specialize_cleared(
          equation, @image_numerator, @image_denominator, @factor)
        zero = specialized.zero?
      return false if !zero
      i += 1
    true

  -> certified?
    verified?

  -> .from_integer_data(chart, factor_coefficients,
                         image_denominator, image_coefficients)
    ring = PolynomialRing.new(
      [chart.line_ring.names[1]], chart.curve.field, :lex)
    v = ring.generator(0)
    factor = ring.zero
    i = 0
    while i < factor_coefficients.size
      factor = factor + v**i * factor_coefficients[i]
      i += 1
    numerator = ring.zero
    i = 0
    while i < image_coefficients.size
      numerator = numerator + v**i * image_coefficients[i]
      i += 1
    image = numerator * Rational.new(1, image_denominator)
    BitangentEtaleComponentCertificate.new(
      chart, factor, image, numerator, image_denominator,
      factor_coefficients, image_coefficients)

  -> to_s
    "BitangentEtaleComponentCertificate(degree=" + degree.to_s + ")"

  -> inspect
    to_s


+ BitangentProjectionCertificate
  -> new(@chart, @projection, @relation)
    @components = nil
    @etale_algebra_cache = nil
    @integral_product_order_cache = nil
    @verified_cache = nil
    @verified_fingerprint = nil

  -> new(@chart, components)
    @components = []
    components.each -> @components.push(item)
    raise "bitangent projection needs at least one etale component" if @components.size == 0
    @projection = @components[0].factor.ring.one
    @components.each -> @projection = @projection * item.factor
    @relation = nil
    @etale_algebra_cache = nil
    @integral_product_order_cache = nil
    @verified_cache = nil
    @verified_fingerprint = nil

  -> chart
    @chart

  -> eliminant
    Polynomial.new(@projection.ring, @projection.terms)

  -> relation
    return nil if @relation == nil
    Polynomial.new(@relation.ring, @relation.terms)

  -> components
    out = []
    return out if @components == nil
    @components.each -> out.push(item)
    out

  # The checked squarefree projection is exactly the coordinate algebra of
  # this reduced affine bitangent chart. Supplied 6/9/12 pieces become a CRT
  # decomposition; they are not assumed irreducible.
  -> etale_algebra
    if !verified?
      raise "unverified bitangent projection has no certified etale algebra"
    if @etale_algebra_cache == nil
      if @components == nil
        @etale_algebra_cache = EtaleAlgebra.new(@projection)
      else
        factors = []
        @components.each -> factors.push(item.factor)
        @etale_algebra_cache = EtaleAlgebra.new(
          @projection, factors, self)
    @etale_algebra_cache

  -> etale_algebra_certificate
    etale_algebra.certificate

  -> etale_algebra_decomposition_certificate
    etale_algebra.decomposition_certificate

  # Integral generator transforms for each supplied CRT component. These are
  # certified power orders, not yet claimed maximal.
  -> integral_product_order
    if !verified?
      raise "unverified bitangent projection has no certified integral order"
    if @integral_product_order_cache == nil
      polynomials = []
      if @components == nil
        polynomials.push(@projection)
      else
        @components.each -> polynomials.push(item.factor)
      @integral_product_order_cache = EtaleProductOrder.new(
        polynomials)
    @integral_product_order_cache

  -> integral_product_order_certificate
    integral_product_order.certificate

  -> degree
    @projection.degree

  -> squarefree?
    squarefree_modulo?(5)

  -> specialize(polynomial, u_image)
    @chart.specialize_modulo(polynomial, u_image, @projection)

  # One squarefree reduction of full degree proves squarefreeness over Q:
  # a repeated factor in characteristic zero would remain repeated at every
  # prime of good degree.  The finite-field gcd is also a much smaller proof
  # object than the enormous rational discriminant of this degree-27 input.
  -> squarefree_modulo?(prime)
    answer = false
    begin
      answer = squarefree_modulo_unchecked?(prime)
    rescue e
      answer = false
    answer

  -> squarefree_modulo_unchecked?(prime)
    field = FiniteField.new(prime)
    ring = PolynomialRing.new([@projection.ring.names[0]], field, :lex)
    terms = []
    @projection.each_term -> (coefficient, exponents)
      terms.push([field.coerce(coefficient), exponents])
    reduced = Polynomial.new(ring, terms)
    return false if reduced.degree != @projection.degree
    reduced.gcd(reduced.derivative(0)).degree == 0

  -> verified?
    fingerprint = proof_fingerprint
    if @verified_cache != nil && fingerprint == @verified_fingerprint
      return @verified_cache
    @verified_cache = verify_fresh
    @verified_fingerprint = fingerprint
    @verified_cache

  -> proof_fingerprint
    text = @chart.curve.equation.to_s + "|" + @projection.to_s
    text = text + "|" + @relation.to_s if @relation != nil
    if @components != nil
      @components.each -> text = text + "|" + item.proof_fingerprint
    text

  -> verify_fresh
    answer = false
    begin
      answer = verify_unchecked
    rescue e
      answer = false
    answer

  -> verify_unchecked
    return false if @projection.ring.arity != 1
    return false if @projection.ring.field != @chart.curve.field
    return false if @projection.degree <= 0 || !squarefree?
    if @components != nil
      total = 0
      i = 0
      while i < @components.size
        component = @components[i]
        return false if component.chart != @chart
        return false if component.factor.ring != @projection.ring
        return false if !component.verified?
        total += component.degree
        i += 1
      return total == @projection.degree

    return false if @relation.ring != @chart.line_ring
    return false if @relation.degree_in(0) != 1

    mixed = false
    @relation.each_term -> (coefficient, exponents)
      mixed = true if exponents[0] == 1 && exponents[1] != 0
    return false if mixed
    scale = @relation.coeff([1, 0])
    return false if @relation.ring.field.zero?(scale)

    u = @chart.line_ring.generator(0)
    tail = @relation - u * scale
    tail_univariate = tail.drop_variables(1, @projection.ring)
    u_image = tail_univariate.negate * @chart.curve.field.divide(
      @chart.curve.field.one, scale)

    equations = @chart.direct_square_equations
    return false if equations == nil
    i = 0
    while i < equations.size
      equation = equations[i]
      return false if !specialize(equation, u_image).rem(@projection).zero?
      i += 1
    true

  -> certified?
    verified?

  -> .from_integer_data(chart, projection_coefficients,
                         relation_denominator, relation_tail_coefficients)
    ring = PolynomialRing.new(
      [chart.line_ring.names[1]], chart.curve.field, :lex)
    projection = ring.zero
    v = ring.generator(0)
    i = 0
    while i < projection_coefficients.size
      projection = projection + v**i * projection_coefficients[i]
      i += 1

    relation = chart.line_ring.generator(0)
    line_v = chart.line_ring.generator(1)
    i = 0
    while i < relation_tail_coefficients.size
      coefficient = Rational.new(
        relation_tail_coefficients[i], relation_denominator)
      relation = relation + line_v**i * coefficient
      i += 1
    BitangentProjectionCertificate.new(chart, projection, relation)

  # Certified projection data for the shell-width quartic in the chart
  # B + l0*S + l1*Z = 0.  These are proof data, not trusted answers:
  # `verified?` substitutes them into the curve-derived square equations.
  -> .shell_width(chart)
    components = []
    components.push(BitangentEtaleComponentCertificate.from_integer_data(
      chart,
      [59049, -52488, 8748, 3240, -1152, 96, 16],
      19683,
      [616734, -269001, -30132, 20124, -3000, -368]))
    components.push(BitangentEtaleComponentCertificate.from_integer_data(
      chart,
      [387420489, -172186884, 6377292, 14880348, -4723920,
       -874800, 221616, 41472, 1920, 64],
      1420541793,
      [67497258528, -8470638099, -1513721115, 2105057484,
       -133485732, -194436936, -25276752, -1115328, -33712]))
    components.push(BitangentEtaleComponentCertificate.from_integer_data(
      chart,
      [2541865828329, 0, 83682825624, 204558018192, 48212327520,
       -306110016, 85030560, 370355328, 104976000, 13250304,
       767232, 18432, 256],
      103870240349763294,
      [-17485495033075191, 54151721320363362, 15350549729219028,
       -76416366932316, -236504539528056, 80418451407264,
       38024261538192, 6415960959360, 540229450752, 22552271424,
       480039552, 5394176]))
    BitangentProjectionCertificate.new(chart, components)

  -> to_s
    "BitangentProjectionCertificate(degree=" + degree.to_s + ")"

  -> inspect
    to_s


+ DescentRequirement
  -> new(@name, @status, @explanation, @certificate = nil)
    @name = @name.to_s
    @status = @status.to_s
    allowed = ["complete", "missing", "conditional", "trusted import"]
    if !allowed.include?(@status)
      raise "unknown descent requirement status: " + @status
    if @status == "complete" && @certificate == nil
      raise "completed descent requirements need a certificate"

  -> name
    @name

  -> status
    @status

  -> explanation
    @explanation

  -> certificate
    @certificate

  -> complete?
    return false if @status != "complete"
    @certificate.respond_to?("certified?") && @certificate.certified?

  -> to_s
    @name + ": " + @status + " — " + @explanation

  -> inspect
    to_s


# The rational hyperflex and the remaining 27 bitangents are the geometric
# prefix for the true descent setup of BPS section 6.5.  A complete true setup
# additionally needs the etale scheme, divisor/line-bundle family, and
# functions whose divisors are twice that family.
+ PlaneQuarticTwoDescentSetup
  -> new(@curve, @distinguished)
    if @distinguished.class_name == "Line"
      @hyperflex_certificate = RationalHyperflexCertificate.new(
        @curve, @distinguished)
    elsif @distinguished.class_name == "RationalHyperflexCertificate"
      @hyperflex_certificate = @distinguished
    else
      raise "distinguished bitangent must be a Line or RationalHyperflexCertificate"
    if !@hyperflex_certificate.certified?
      raise "distinguished line is not a certified rational hyperflex"
    if @hyperflex_certificate.curve != @curve
      raise "distinguished hyperflex belongs to a different curve"
    @bitangent_scheme_certificate = nil
    @integral_product_order = nil
    @maximal_product_order_computation = nil

  -> curve
    @curve

  -> jacobian
    @curve.jacobian

  -> intended_descent_kind
    :true

  # This object is deliberately only a geometric preparation.  It must not
  # identify itself as the true BPS setup until Delta', beta', and f exist.
  -> true_setup?
    false

  -> isogeny
    :two

  -> distinguished_bitangent
    @hyperflex_certificate.line

  -> distinguished_certificate
    @hyperflex_certificate

  -> expected_etale_degree
    27

  -> geometric_prerequisites_certified?
    smooth = SmoothPlaneQuarticCertificate.new(@curve).certified?
    smooth && @hyperflex_certificate.certified?

  -> certified?
    false

  -> complete?
    false

  # For coordinates in which the distinguished hyperflex is Z=0, chart 0
  # contains all other bitangents exactly when the boundary chart (a=0,b=1)
  # is empty.  This is the shell-width curve's inexpensive geometric route.
  -> certify_bitangent_scheme
    coefficients = distinguished_bitangent.coefficients
    field = @curve.field
    standard = field.zero?(coefficients[0])
    standard = false if !field.zero?(coefficients[1])
    standard = false if !field.one?(coefficients[2])
    if !standard
      raise "focused bitangent-scheme certificate currently needs distinguished line Z = 0"
    primary = PlaneQuarticBitangentChart.new(@curve, 0)
    boundary = PlaneQuarticBitangentChart.new(@curve, 1)
    projection = BitangentProjectionCertificate.shell_width(primary)
    if !projection.verified?
      raise "no verified focused projection data for this plane quartic"
    @bitangent_scheme_certificate = PlaneQuarticBitangentSchemeCertificate.new(
      self, primary, boundary, projection)
    if !@bitangent_scheme_certificate.certified?
      raise "plane-quartic bitangent scheme did not verify as 27 plus the distinguished hyperflex"
    @integral_product_order = nil
    @maximal_product_order_computation = nil
    @bitangent_scheme_certificate

  -> bitangent_scheme_certificate
    @bitangent_scheme_certificate

  -> certify_integral_product_order
    if @bitangent_scheme_certificate == nil
      certify_bitangent_scheme
    order = @bitangent_scheme_certificate.integral_product_order
    if @integral_product_order != order
      @maximal_product_order_computation = nil
    @integral_product_order = order
    if !@integral_product_order.certificate.verified?
      raise "bitangent integral product order failed certification"
    @integral_product_order

  -> integral_product_order
    @integral_product_order

  -> certify_maximal_product_order(
       factor_search_limit = 1_000_000,
       step_limit = 10_000)
    if @integral_product_order == nil
      certify_integral_product_order
    computation = @integral_product_order.maximal_order_with_certificate(
      factor_search_limit, step_limit)
    @maximal_product_order_computation = computation
    if !@maximal_product_order_computation.certificate.verified?
      raise "bitangent maximal product order failed certification"
    @maximal_product_order_computation.order

  -> maximal_product_order
    return nil if @maximal_product_order_computation == nil
    @maximal_product_order_computation.order

  -> maximal_product_order_computation
    @maximal_product_order_computation

  -> maximal_product_order_certificate
    return nil if @maximal_product_order_computation == nil
    @maximal_product_order_computation.certificate

  -> requirements
    out = []
    out.push(DescentRequirement.new(
      "smooth plane quartic", "complete",
      "exact singular-locus computation", SmoothPlaneQuarticCertificate.new(@curve)))
    out.push(DescentRequirement.new(
      "rational distinguished odd theta characteristic", "complete",
      "hyperflex intersection is 4P = 2(2P)", @hyperflex_certificate))
    if @bitangent_scheme_certificate == nil
      out.push(DescentRequirement.new(
        "geometric bitangent scheme", "missing",
        "compute and certify the remaining 27 reduced bitangents"))
      out.push(DescentRequirement.new(
        "finite etale bitangent algebra", "missing",
        "construct the squarefree quotient after certifying the bitangent scheme"))
    else
      out.push(DescentRequirement.new(
        "geometric bitangent scheme", "complete",
        "checked degree-27 presentation plus the distinguished hyperflex",
        @bitangent_scheme_certificate))
      out.push(DescentRequirement.new(
        "finite etale bitangent algebra", "complete",
        "squarefree quotient with checked CRT component decomposition",
        @bitangent_scheme_certificate.etale_algebra_certificate))
    if @integral_product_order == nil
      out.push(DescentRequirement.new(
        "integral power product order", "missing",
        "construct certified integral generator transforms for the etale components"))
    else
      out.push(DescentRequirement.new(
        "integral power product order", "complete",
        "certified monogenic Z-orders for each etale component",
        @integral_product_order.certificate))
    out.push(DescentRequirement.new(
      "BPS divisor and function data", "missing",
      "construct Delta', beta', and f with div(f) = 2 beta'"))
    if @maximal_product_order_computation == nil
      out.push(DescentRequirement.new(
        "etale algebra maximal orders", "missing",
        "compute certified integral closures of the degree 6, 9, and 12 components"))
    else
      out.push(DescentRequirement.new(
        "etale algebra maximal orders", "complete",
        "degree-generic Round 2 fixed points for all three components",
        @maximal_product_order_computation.certificate))
    out.push(DescentRequirement.new(
      "S-class group and S-units", "missing",
      "must be unconditional; a GRH bound is conditional, not certified"))
    out.push(DescentRequirement.new(
      "theta Galois module", "missing",
      "identify the 28/315 incidence structure and decomposition actions"))
    out.push(DescentRequirement.new(
      "local descent images", "missing",
      "certified p-adic residue disks and bitangent evaluations"))
    out.push(DescentRequirement.new(
      "explicit Selmer intersection", "missing",
      "the finite F2 kernel is available once arithmetic conditions exist"))
    out.push(DescentRequirement.new(
      "BPS comparison and rank bound", "missing",
      "certify the comparison kernel and rational J[2] dimension"))
    out

  -> missing_requirements
    out = []
    requirements.each -> out.push(item) if !item.complete?
    out

  -> rank_upper_bound
    first = missing_requirements[0]
    raise "certified 2-descent is incomplete at '" + first.name + "': " + first.explanation

  -> to_s
    "PlaneQuarticTwoDescentSetup(geometric prefix, expected etale degree 27)"

  -> inspect
    to_s


+ PlaneQuarticBitangentSchemeCertificate
  -> new(@setup, @primary_chart, @boundary_chart)
    @primary_certificate = @primary_chart.certificate
    @count_certificate = SmoothPlaneQuarticBitangentCountCertificate.new(
      @setup.curve)

  -> new(@setup, @primary_chart, @boundary_chart, @primary_certificate)
    @count_certificate = SmoothPlaneQuarticBitangentCountCertificate.new(
      @setup.curve)

  -> setup
    @setup

  -> primary_chart
    @primary_chart

  -> boundary_chart
    @boundary_chart

  -> primary_certificate
    @primary_certificate

  -> count_certificate
    @count_certificate

  -> projection_polynomial
    @primary_certificate.eliminant

  -> etale_algebra
    if !verified?
      raise "unverified bitangent scheme has no certified etale algebra"
    @primary_certificate.etale_algebra

  -> etale_algebra_certificate
    etale_algebra.certificate

  -> etale_algebra_decomposition_certificate
    etale_algebra.decomposition_certificate

  -> integral_product_order
    if !verified?
      raise "unverified bitangent scheme has no certified integral order"
    @primary_certificate.integral_product_order

  -> integral_product_order_certificate
    integral_product_order.certificate

  -> component_degrees
    out = []
    if @primary_certificate.respond_to?("components")
      @primary_certificate.components.each -> out.push(item.degree)
    out

  -> etale_degree
    @primary_certificate.degree

  -> geometric_degree
    etale_degree + 1

  -> verified?
    return false if !@setup.geometric_prerequisites_certified?
    return false if @primary_chart.curve != @setup.curve
    return false if @boundary_chart.curve != @setup.curve
    return false if @primary_chart.pivot != 0 || @boundary_chart.pivot != 1
    return false if !@count_certificate.certified?
    return false if !@primary_certificate.verified?
    return false if etale_degree != 27
    return false if !@boundary_chart.first_parameter_zero_excludes_square?
    geometric_degree == @count_certificate.geometric_count

  -> certified?
    verified?

  -> to_s
    "PlaneQuarticBitangentSchemeCertificate(27 + 1)"

  -> inspect
    to_s


+ Curve
  -> two_descent_setup(distinguished_bitangent:)
    PlaneQuarticTwoDescentSetup.new(self, distinguished_bitangent)


+ Jacobian
  -> two_descent_setup(distinguished_bitangent:)
    @curve.two_descent_setup(distinguished_bitangent: distinguished_bitangent)

  -> rank_upper_bound
    raise "Jacobian rank upper bound requires a completed certified descent"
