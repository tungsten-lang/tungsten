# General integral Weierstrass models and FLT-oriented Frey curves.
#
# The short Weierstrass group law remains in curves.w.  This file supplies the
# integral arithmetic layer used by elliptic_tate.w. Modular representations
# and modular-form spaces remain separate future layers.
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
# Coefficients are retained as integers so certified local minimization and
# conductor calculations work prime by prime without losing the chosen model.
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

  -> .valuation(value, prime)
    raise "valuation prime must be prime" if prime < 2 || !prime.prime?
    return nil if value == 0
    remaining = value.abs
    exponent = 0
    while remaining % prime == 0
      remaining = remaining / prime
      exponent += 1
    exponent

  -> .transformed_coefficients_if_integral(model, u, r, s, t)
    return nil if model.class_name != "IntegralWeierstrassModel"
    return nil if !IntegralWeierstrassModel.integer?(u) || u == 0
    return nil if !IntegralWeierstrassModel.integer?(r)
    return nil if !IntegralWeierstrassModel.integer?(s)
    return nil if !IntegralWeierstrassModel.integer?(t)

    a1 = model.a1
    a2 = model.a2
    a3 = model.a3
    a4 = model.a4
    a6 = model.a6
    numerators = [
      a1 + 2*s,
      a2 - s*a1 + 3*r - s**2,
      a3 + r*a1 + 2*t,
      a4 - s*a3 + 2*r*a2 - (t + r*s)*a1 + 3*r**2 - 2*s*t,
      a6 + r*a4 + r**2*a2 + r**3 - t*a3 - r*t*a1 - t**2
    ]
    denominators = [u, u**2, u**3, u**4, u**6]
    result = []
    i = 0
    while i < numerators.size
      return nil if numerators[i] % denominators[i] != 0
      result.push(numerators[i] / denominators[i])
      i += 1
    result

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

  -> same_model?(other)
    return false if other == nil
    return false if other.class_name != "IntegralWeierstrassModel"
    IntegralWeierstrassModel.same_integer_array?(
      coefficients, other.coefficients)

  -> transform(u, r = 0, s = 0, t = 0)
    IntegralWeierstrassTransformation.new(self, u, r, s, t)

  # A p-scaling exists precisely when an admissible integral change with
  # u=p lowers the discriminant valuation by 12. The congruence classes
  # r mod p^2, s mod p, and t mod p^3 form a complete finite search.
  -> find_p_scaling(prime, search_limit = 250_000)
    raise "local minimization requires a prime" if prime < 2 || !prime.prime?
    required = prime**6
    if required > search_limit
      raise "local minimization unknown: exhaustive p^6 search exceeds limit"
    candidate_s = 0
    while candidate_s < prime
      candidate_r = 0
      while candidate_r < prime**2
        candidate_t = 0
        while candidate_t < prime**3
          transformed = IntegralWeierstrassModel.transformed_coefficients_if_integral(
            self, prime, candidate_r, candidate_s, candidate_t)
          if transformed != nil
            return IntegralWeierstrassTransformation.new(
              self, prime, candidate_r, candidate_s, candidate_t)
          candidate_t += 1
        candidate_r += 1
      candidate_s += 1
    nil

  # These inequalities are sufficient for local minimality: a p-scaling
  # would divide c4, c6, and Delta by p^4, p^6, and p^12 respectively.
  -> locally_minimal_by_invariants?(prime)
    delta_valuation = IntegralWeierstrassModel.valuation(discriminant, prime)
    return false if delta_valuation == nil
    return true if delta_valuation < 12
    c4_valuation = IntegralWeierstrassModel.valuation(c4, prime)
    return true if c4_valuation != nil && c4_valuation < 4
    c6_valuation = IntegralWeierstrassModel.valuation(c6, prime)
    return true if c6_valuation != nil && c6_valuation < 6
    false

  -> local_minimal_model_computation(prime, search_limit = 250_000)
    EllipticLocalMinimalModelComputation.new(self, prime, search_limit)

  -> local_minimal_model(prime, search_limit = 250_000)
    local_minimal_model_computation(prime, search_limit).model

  -> minimal_model_computation(search_limit = 250_000)
    EllipticMinimalModelComputation.new(self, search_limit)

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

  -> minimal_model(search_limit = 250_000)
    minimal_model_computation(search_limit).model

  -> local_reduction(prime, search_limit = 250_000)
    local = local_minimal_model_computation(prime, search_limit)
    EllipticLocalReduction.new(
      local.model, prime, local.certificate, search_limit)

  -> tate_local_data(prime, search_limit = 250_000)
    local = local_minimal_model_computation(prime, search_limit)
    EllipticTateLocalData.new(
      local.model, prime, local.certificate, search_limit)

  -> conductor_computation(search_limit = 250_000)
    EllipticConductorComputation.new(self, search_limit)

  -> conductor(search_limit = 250_000)
    conductor_computation(search_limit).conductor

  -> to_s
    "IntegralWeierstrassModel(" + coefficients.join(", ") + ")"

  -> inspect
    to_s


+ IntegralWeierstrassTransformationCertificate
  -> new(@source, @target, @u, @r, @s, @t)

  -> source
    @source

  -> target
    @target

  -> u
    @u

  -> r
    @r

  -> s
    @s

  -> t
    @t

  -> verified?
    answer = false
    begin
      answer = verify!
    rescue error
      answer = false
    answer

  -> verify!
    return false if @source.class_name != "IntegralWeierstrassModel"
    return false if @target.class_name != "IntegralWeierstrassModel"
    return false if !@source.certificate.verified?
    return false if !@target.certificate.verified?
    expected = IntegralWeierstrassModel.transformed_coefficients_if_integral(
      @source, @u, @r, @s, @t)
    return false if expected == nil
    return false if !IntegralWeierstrassModel.same_integer_array?(
      expected, @target.coefficients)
    return false if @source.c4 != @target.c4*@u**4
    return false if @source.c6 != @target.c6*@u**6
    return false if @source.discriminant != @target.discriminant*@u**12
    true

  -> certified?
    verified?

  -> to_s
    "IntegralWeierstrassTransformationCertificate(u=" + @u.to_s + ")"

  -> inspect
    to_s


# An admissible integral change
#
#   x = u^2*x' + r
#   y = u^3*y' + u^2*s*x' + t.
#
# When |u| > 1 and the target remains integral this lowers the discriminant.
+ IntegralWeierstrassTransformation
  -> new(@source, @u, @r = 0, @s = 0, @t = 0)
    coefficients = IntegralWeierstrassModel.transformed_coefficients_if_integral(
      @source, @u, @r, @s, @t)
    if coefficients == nil
      raise "Weierstrass change of variables does not preserve integrality"
    @target = IntegralWeierstrassModel.new(
      coefficients[0], coefficients[1], coefficients[2],
      coefficients[3], coefficients[4])
    @certificate = IntegralWeierstrassTransformationCertificate.new(
      @source, @target, @u, @r, @s, @t)
    raise "Weierstrass transformation certificate failed" if !@certificate.verified?

  -> source
    @source

  -> target
    @target

  -> u
    @u

  -> r
    @r

  -> s
    @s

  -> t
    @t

  -> certificate
    @certificate

  -> certified?
    @certificate.verified?

  -> to_s
    "IntegralWeierstrassTransformation(u=" + @u.to_s + ")"

  -> inspect
    to_s


+ EllipticLocalMinimalModelCertificate
  -> new(@source, @prime, @model, @transformations)

  -> source
    @source

  -> prime
    @prime

  -> model
    @model

  -> transformations
    @transformations

  -> verified?
    answer = false
    begin
      answer = verify!
    rescue error
      answer = false
    answer

  -> verify!
    return false if @source.class_name != "IntegralWeierstrassModel"
    return false if @model.class_name != "IntegralWeierstrassModel"
    return false if @prime < 2 || !@prime.prime?
    return false if !@source.certificate.verified?
    current = @source
    i = 0
    while i < @transformations.size
      step = @transformations[i]
      return false if step.class_name != "IntegralWeierstrassTransformation"
      return false if step.u != @prime
      return false if !step.source.same_model?(current)
      return false if !step.certificate.verified?
      current = step.target
      i += 1
    return false if !current.same_model?(@model)
    return true if @model.locally_minimal_by_invariants?(@prime)

    # When invariant valuations do not settle minimality, replay the complete
    # residue search. A remaining p-scaling would contradict the claim.
    @model.find_p_scaling(@prime, @prime**6) == nil

  -> certified?
    verified?

  -> to_s
    "EllipticLocalMinimalModelCertificate(p=" + @prime.to_s + ")"

  -> inspect
    to_s


+ EllipticLocalMinimalModelComputation
  -> new(@source, @prime, @search_limit = 250_000)
    raise "local minimization requires a nonsingular model" if !@source.nonsingular?
    raise "local minimization requires a prime" if @prime < 2 || !@prime.prime?
    @transformations = []
    @model = @source
    while !@model.locally_minimal_by_invariants?(@prime)
      step = @model.find_p_scaling(@prime, @search_limit)
      break if step == nil
      @transformations.push(step)
      @model = step.target
    @certificate = EllipticLocalMinimalModelCertificate.new(
      @source, @prime, @model, @transformations)
    if !@certificate.verified?
      raise "local Weierstrass minimization certificate failed"

  -> source
    @source

  -> prime
    @prime

  -> model
    @model

  -> transformations
    @transformations

  -> certificate
    @certificate

  -> certified?
    @certificate.verified?

  -> to_s
    ("EllipticLocalMinimalModel(p=" + @prime.to_s +
     ", steps=" + @transformations.size.to_s + ")")

  -> inspect
    to_s


+ EllipticMinimalModelCertificate
  -> new(@source, @model, @factorization, @local_computations)

  -> verified?
    answer = false
    begin
      answer = verify!
    rescue error
      answer = false
    answer

  -> verify!
    return false if @source.class_name != "IntegralWeierstrassModel"
    return false if @model.class_name != "IntegralWeierstrassModel"
    return false if @factorization.class_name != "IntegerFactorization"
    return false if @factorization.value != @source.discriminant.abs
    factors = @factorization.to_a
    return false if factors.size != @local_computations.size
    current = @source
    i = 0
    while i < factors.size
      computation = @local_computations[i]
      return false if computation.class_name != "EllipticLocalMinimalModelComputation"
      return false if computation.prime != factors[i].prime
      return false if !computation.source.same_model?(current)
      return false if !computation.certificate.verified?
      current = computation.model
      i += 1
    return false if !current.same_model?(@model)

    # Later q-scalings are p-adic units and preserve prior p-minimality.
    i = 0
    while i < factors.size
      prime = factors[i].prime
      if !@model.locally_minimal_by_invariants?(prime)
        return false if @model.find_p_scaling(prime, prime**6) != nil
      i += 1
    true

  -> certified?
    verified?

  -> to_s
    "EllipticMinimalModelCertificate(Delta=" + @model.discriminant.to_s + ")"

  -> inspect
    to_s


+ EllipticMinimalModelComputation
  -> new(@source, @search_limit = 250_000)
    raise "minimal models require a nonsingular equation" if !@source.nonsingular?
    @factorization = @source.discriminant.abs.factor
    @local_computations = []
    @model = @source
    @factorization.each -> (factor)
      computation = @model.local_minimal_model_computation(
        factor.prime, @search_limit)
      @local_computations.push(computation)
      @model = computation.model
    @certificate = EllipticMinimalModelCertificate.new(
      @source, @model, @factorization, @local_computations)
    raise "global minimal-model certificate failed" if !@certificate.verified?

  -> source
    @source

  -> model
    @model

  -> factorization
    @factorization

  -> local_computations
    @local_computations

  -> certificate
    @certificate

  -> certified?
    @certificate.verified?

  -> to_s
    "EllipticMinimalModel(Delta=" + @model.discriminant.to_s + ")"

  -> inspect
    to_s


+ EllipticLocalReductionCertificate
  -> new(@model, @prime, @kind, @conductor_exponent,
         @minimality_certificate, @tate_data = nil)

  -> verified?
    answer = false
    begin
      answer = verify!
    rescue error
      answer = false
    answer

  -> verify!
    return false if @model.class_name != "IntegralWeierstrassModel"
    return false if @prime < 2 || !@prime.prime?
    valid_minimality = @minimality_certificate.class_name == "EllipticLocalMinimalModelCertificate"
    return false if !valid_minimality
    return false if @minimality_certificate.prime != @prime
    return false if !@minimality_certificate.model.same_model?(@model)
    return false if !@minimality_certificate.verified?

    delta_valuation = IntegralWeierstrassModel.valuation(
      @model.discriminant, @prime)
    c4_valuation = IntegralWeierstrassModel.valuation(@model.c4, @prime)
    if delta_valuation == 0
      return @kind == :good && @conductor_exponent == 0
    if c4_valuation == 0
      return @kind == :multiplicative && @conductor_exponent == 1
    if @prime < 5
      return false if @tate_data.class_name != "EllipticTateLocalData"
      return false if !@tate_data.source.same_model?(@model)
      return false if @tate_data.prime != @prime
      return false if !@tate_data.certificate.verified?
      return false if @tate_data.kind != :additive
      return false if @tate_data.conductor_exponent != @conductor_exponent
      return @kind == :additive
    expected_exponent = 2
    @kind == :additive && @conductor_exponent == expected_exponent

  -> certified?
    verified?

  -> to_s
    ("EllipticLocalReduction(p=" + @prime.to_s +
     ", " + @kind.to_s + ")")

  -> inspect
    to_s


+ EllipticLocalReduction
  -> new(@model, @prime, @minimality_certificate,
         @search_limit = 250_000)
    @delta_valuation = IntegralWeierstrassModel.valuation(
      @model.discriminant, @prime)
    @c4_valuation = IntegralWeierstrassModel.valuation(@model.c4, @prime)
    @tate_data = nil
    if @delta_valuation == 0
      @kind = :good
      @conductor_exponent = 0
    elsif @c4_valuation == 0
      @kind = :multiplicative
      @conductor_exponent = 1
    else
      @kind = :additive
      @conductor_exponent = 2
      if @prime < 5
        @tate_data = EllipticTateLocalData.new(
          @model, @prime, @minimality_certificate, @search_limit)
        @conductor_exponent = @tate_data.conductor_exponent
    @certificate = EllipticLocalReductionCertificate.new(
      @model, @prime, @kind, @conductor_exponent,
      @minimality_certificate, @tate_data)
    raise "local reduction certificate failed" if !@certificate.verified?

  -> model
    @model

  -> prime
    @prime

  -> kind
    @kind

  -> delta_valuation
    @delta_valuation

  -> c4_valuation
    @c4_valuation

  -> good?
    @kind == :good

  -> multiplicative?
    @kind == :multiplicative

  -> additive?
    @kind == :additive

  -> semistable?
    good? || multiplicative?

  -> conductor_exponent
    @conductor_exponent

  -> known_conductor_exponent
    @conductor_exponent

  -> tate_data
    if @tate_data == nil
      @tate_data = EllipticTateLocalData.new(
        @model, @prime, @minimality_certificate, @search_limit)
    @tate_data

  -> kodaira_symbol
    tate_data.kodaira_symbol

  -> tamagawa_number
    tate_data.tamagawa_number

  -> split?
    tate_data.split?

  -> certificate
    @certificate

  -> certified?
    @certificate.verified?

  -> to_s
    ("EllipticLocalReduction(p=" + @prime.to_s +
     ", " + @kind.to_s + ")")

  -> inspect
    to_s


+ EllipticConductorCertificate
  -> new(@source, @minimal_model_computation, @factorization,
         @local_reductions, @conductor)

  -> verified?
    answer = false
    begin
      answer = verify!
    rescue error
      answer = false
    answer

  -> verify!
    return false if @source.class_name != "IntegralWeierstrassModel"
    if @minimal_model_computation.class_name != "EllipticMinimalModelComputation"
      return false
    return false if !@minimal_model_computation.source.same_model?(@source)
    return false if !@minimal_model_computation.certificate.verified?
    model = @minimal_model_computation.model
    return false if @factorization.class_name != "IntegerFactorization"
    return false if @factorization.value != model.discriminant.abs
    factors = @factorization.to_a
    return false if factors.size != @local_reductions.size
    reconstructed = 1
    i = 0
    while i < factors.size
      local = @local_reductions[i]
      return false if local.class_name != "EllipticLocalReduction"
      return false if local.prime != factors[i].prime
      return false if !local.model.same_model?(model)
      return false if !local.certificate.verified?
      exponent = local.known_conductor_exponent
      return false if exponent == nil
      reconstructed *= local.prime**exponent
      i += 1
    reconstructed == @conductor

  -> certified?
    verified?

  -> to_s
    "EllipticConductorCertificate(N=" + @conductor.to_s + ")"

  -> inspect
    to_s


+ EllipticConductorComputation
  -> new(@source, @search_limit = 250_000)
    @minimal_model_computation = @source.minimal_model_computation(
      @search_limit)
    @model = @minimal_model_computation.model
    @factorization = @model.discriminant.abs.factor
    @local_reductions = []
    @conductor = 1
    @factorization.each -> (factor)
      local_computation = @model.local_minimal_model_computation(
        factor.prime, @search_limit)
      local = EllipticLocalReduction.new(
        @model, factor.prime, local_computation.certificate, @search_limit)
      exponent = local.known_conductor_exponent
      @local_reductions.push(local)
      @conductor *= factor.prime**exponent
    @certificate = EllipticConductorCertificate.new(
      @source, @minimal_model_computation, @factorization,
      @local_reductions, @conductor)
    raise "elliptic conductor certificate failed" if !@certificate.verified?

  -> source
    @source

  -> model
    @model

  -> minimal_model_computation
    @minimal_model_computation

  -> factorization
    @factorization

  -> local_reductions
    @local_reductions

  -> conductor
    @conductor

  -> certificate
    @certificate

  -> certified?
    @certificate.verified?

  -> semistable?
    @local_reductions.all? -> (local) local.semistable?

  -> to_s
    "EllipticConductor(N=" + @conductor.to_s + ")"

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

  -> conductor(search_limit = 250_000)
    @model.conductor(search_limit)

  -> to_s
    ("FreyCurve(a=" + @a.to_s + ", b=" + @b.to_s +
     ", p=" + @exponent.to_s + ")")

  -> inspect
    to_s
