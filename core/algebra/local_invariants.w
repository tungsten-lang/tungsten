# Exact local invariants derived from finite plane-curve normalization data.
#
# For a reduced y-distinguished plane equation over characteristic zero,
# ord_x Res_y(f, df/dy) = mu + n - 1 and
# delta = (mu + r - 1)/2. Resultants, valuations, and formula arithmetic are
# replayed exactly; the two classical local-geometry identities are recorded
# as theorem imports rather than presented as kernel proofs.

use core/algebra/local_intersection

+ PlaneCurveLocalPolarCertificate
  -> new(@normalization, @polar_intersection,
         @projection_intersection, @milnor_number)
    @verified_cache = nil

  -> normalization
    @normalization

  -> polar_intersection
    @polar_intersection

  -> projection_intersection
    @projection_intersection

  -> milnor_number
    @milnor_number

  -> theorem
    "for a reduced characteristic-zero plane germ, I(f,f_y)=mu+I(f,x)-1"

  -> milnor_theorem
    theorem

  -> theorem_reference
    "classical polar-intersection formula for the Milnor number"

  -> theorem_dependencies
    [
      @normalization.certificate.theorem,
      @polar_intersection.certificate.theorem,
      @projection_intersection.certificate.theorem,
      theorem]

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
    return false if !@normalization.certificate.verified?
    return false if !@normalization.local_polynomial.squarefree?
    return false if !@polar_intersection.certificate.verified?
    return false if !@projection_intersection.certificate.verified?
    return false if (
      @polar_intersection.normalization != @normalization)
    return false if (
      @projection_intersection.normalization != @normalization)
    expected = (
      @polar_intersection.multiplicity -
      @projection_intersection.multiplicity + 1)
    expected >= 0 && expected == @milnor_number

  -> certified?
    verified?

  -> statement
    ("the polar and projection intersections give Milnor number " +
     @milnor_number.to_s)


+ PlaneLocalInvariants
  -> .distinguished_degree(local_polynomial)
    if local_polynomial.ring.arity != 2
      raise "local plane invariants require a bivariate polynomial"
    if local_polynomial.ring.field.class_name != "RationalField"
      raise "local plane invariants currently require RationalField"
    degree = local_polynomial.degree_in(1)
    if degree < 1
      raise "local plane equation has no dependent-variable degree"
    coefficients = (
      local_polynomial.coefficient_polynomials_in(1))
    leading = coefficients[degree]
    if leading.zero? || leading.degree > 0
      raise (
        "local delta currently requires a constant nonzero " +
        "dependent-variable leading coefficient")
    exponent = 0
    while exponent < degree
      if !local_polynomial.ring.field.zero?(
           coefficients[exponent].coeff(0))
        raise (
          "local delta currently requires a y-distinguished equation; " +
          "change local coordinates or compute a Weierstrass polynomial")
      exponent += 1
    degree

  -> .derivative_resultant(local_polynomial)
    PlaneLocalInvariants.distinguished_degree(
      local_polynomial)
    local_polynomial.bivariate_resultant(
      local_polynomial.derivative(1), 1)


+ PlaneCurveLocalDiscriminantCertificate
  -> new(@local_polynomial, @weierstrass_degree,
         @derivative_resultant, @valuation)
    @verified_cache = nil

  -> local_polynomial
    @local_polynomial

  -> weierstrass_degree
    @weierstrass_degree

  -> derivative_resultant
    @derivative_resultant

  -> valuation
    @valuation

  -> proof_kind
    :exact_bareiss_resultant

  -> milnor_theorem
    "for a reduced y-distinguished plane germ, ord Res_y(f,f_y)=mu+n-1"

  -> kernel_checked?
    true

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
    expected_degree = PlaneLocalInvariants.distinguished_degree(
      @local_polynomial)
    return false if expected_degree != @weierstrass_degree
    expected_resultant = PlaneLocalInvariants.derivative_resultant(
      @local_polynomial)
    return false if expected_resultant != @derivative_resultant
    return false if @derivative_resultant.zero?
    @derivative_resultant.order_at_zero == @valuation

  -> certified?
    verified?

  -> statement
    ("the dependent-variable derivative resultant has local valuation " +
     @valuation.to_s)


+ PlaneCurveLocalDeltaCertificate
  -> new(@normalization, @milnor_certificate,
         @milnor_number, @delta)
    @verified_cache = nil

  -> normalization
    @normalization

  -> discriminant_certificate
    return @milnor_certificate if (
      @milnor_certificate.class_name ==
      "PlaneCurveLocalDiscriminantCertificate")
    nil

  -> polar_certificate
    return @milnor_certificate if (
      @milnor_certificate.class_name ==
      "PlaneCurveLocalPolarCertificate")
    nil

  -> milnor_certificate
    @milnor_certificate

  -> milnor_number
    @milnor_number

  -> delta
    @delta

  -> theorem
    ("for a reduced characteristic-zero plane germ, " +
     "ord Res_y(f,f_y)=mu+n-1 and 2 delta=mu+r-1")

  -> theorem_reference
    "classical Milnor-discriminant and Milnor-delta formulas"

  -> theorem_dependencies
    [
      @normalization.certificate.theorem,
      @milnor_certificate.milnor_theorem,
      theorem]

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
    return false if !@normalization.certificate.verified?
    return false if !@milnor_certificate.verified?
    local = @normalization.local_polynomial
    return false if !local.squarefree?
    if (@milnor_certificate.class_name ==
        "PlaneCurveLocalDiscriminantCertificate")
      degree = @milnor_certificate.weierstrass_degree
      valuation = @milnor_certificate.valuation
      expected_milnor = valuation - degree + 1
      return false if expected_milnor < 0
      return false if expected_milnor != @milnor_number
    elsif (@milnor_certificate.class_name ==
           "PlaneCurveLocalPolarCertificate")
      return false if (
        @milnor_certificate.milnor_number !=
        @milnor_number)
    else
      return false
    numerator = (
      @milnor_number +
      @normalization.geometric_branch_count - 1)
    return false if numerator < 0 || numerator % 2 != 0
    @delta == numerator / 2

  -> certified?
    verified?

  -> statement
    ("the reduced local plane germ has delta invariant " +
     @delta.to_s + " and Milnor number " +
     @milnor_number.to_s)


+ PlaneCurveLocalDeltaInvariant
  -> new(@normalization)
    local = @normalization.local_polynomial
    if !local.squarefree?
      raise "local delta requires a reduced plane equation"
    @weierstrass_degree = nil
    @derivative_resultant = nil
    @discriminant_valuation = nil
    @discriminant_certificate = nil
    @polar_intersection = nil
    @projection_intersection = nil
    @polar_certificate = nil
    @method = :polar_intersection

    distinguished = false
    begin
      @weierstrass_degree = (
        PlaneLocalInvariants.distinguished_degree(local))
      distinguished = true
    rescue error
      distinguished = false

    if distinguished
      @method = :derivative_resultant
      @derivative_resultant = (
        PlaneLocalInvariants.derivative_resultant(local))
      if @derivative_resultant.zero?
        raise "local derivative resultant vanished"
      @discriminant_valuation = (
        @derivative_resultant.order_at_zero)
      @milnor_number = (
        @discriminant_valuation -
        @weierstrass_degree + 1)
      @discriminant_certificate = (
        PlaneCurveLocalDiscriminantCertificate.new(
          local, @weierstrass_degree,
          @derivative_resultant,
          @discriminant_valuation))
      milnor_certificate = @discriminant_certificate
    else
      source = @normalization.source_polynomial
      y_index = PlaneLocalGeometry.variable_index(
        source, @normalization.y_variable)
      x_index = PlaneLocalGeometry.variable_index(
        source, @normalization.x_variable)
      polar = source.derivative(y_index)
      projection = (
        source.ring.generator(x_index) -
        @normalization.point[0])
      @polar_intersection = (
        @normalization.intersection_with(
          polar, @normalization.x_variable,
          @normalization.y_variable))
      @projection_intersection = (
        @normalization.intersection_with(
          projection, @normalization.x_variable,
          @normalization.y_variable))
      @milnor_number = (
        @polar_intersection.multiplicity -
        @projection_intersection.multiplicity + 1)
      @polar_certificate = PlaneCurveLocalPolarCertificate.new(
        @normalization, @polar_intersection,
        @projection_intersection, @milnor_number)
      milnor_certificate = @polar_certificate
    if @milnor_number < 0
      raise "local Milnor formula produced a negative value"
    numerator = (
      @milnor_number +
      @normalization.geometric_branch_count - 1)
    if numerator < 0 || numerator % 2 != 0
      raise "local delta formula did not produce a nonnegative integer"
    @delta = numerator / 2
    @certificate = PlaneCurveLocalDeltaCertificate.new(
      @normalization, milnor_certificate,
      @milnor_number, @delta)
    if !@certificate.verified?
      raise "local delta certificate did not verify"

  -> normalization
    @normalization

  -> weierstrass_degree
    @weierstrass_degree

  -> computation_method
    @method

  -> derivative_resultant
    @derivative_resultant

  -> discriminant_valuation
    @discriminant_valuation

  -> branch_count
    @normalization.geometric_branch_count

  -> milnor_number
    @milnor_number

  -> delta
    @delta

  -> discriminant_certificate
    @discriminant_certificate

  -> polar_intersection
    @polar_intersection

  -> projection_intersection
    @projection_intersection

  -> polar_certificate
    @polar_certificate

  -> certificate
    @certificate

  -> to_s
    ("PlaneCurveLocalDeltaInvariant(delta=" +
     @delta.to_s + ", mu=" +
     @milnor_number.to_s + ", branches=" +
     branch_count.to_s + ")")

  -> inspect
    to_s


+ PlaneCurveLocalNormalization
  -> local_delta_invariant
    if @local_delta_invariant == nil
      @local_delta_invariant = (
        PlaneCurveLocalDeltaInvariant.new(self))
    @local_delta_invariant

  -> discriminant_valuation
    local_delta_invariant.discriminant_valuation

  -> milnor_number
    local_delta_invariant.milnor_number

  -> delta
    local_delta_invariant.delta

  -> delta_certificate
    local_delta_invariant.certificate


+ Polynomial
  -> local_delta_invariant(x_variable = 0, y_variable = 1,
                            point = nil, maximum_power = 6,
                            search_margin = 0,
                            recursion_limit = 8,
                            parameter = :t)
    local_normalization(
      x_variable, y_variable, point,
      maximum_power, search_margin,
      recursion_limit, parameter).local_delta_invariant

  -> local_delta(x_variable = 0, y_variable = 1,
                  point = nil, maximum_power = 6,
                  search_margin = 0,
                  recursion_limit = 8,
                  parameter = :t)
    local_delta_invariant(
      x_variable, y_variable, point,
      maximum_power, search_margin,
      recursion_limit, parameter).delta


+ Algebra
  -> .local_delta_invariant(polynomial, x_variable = 0,
                             y_variable = 1, point = nil,
                             maximum_power = 6,
                             search_margin = 0,
                             recursion_limit = 8,
                             parameter = :t)
    polynomial.local_delta_invariant(
      x_variable, y_variable, point,
      maximum_power, search_margin,
      recursion_limit, parameter)

  -> .local_delta(polynomial, x_variable = 0,
                   y_variable = 1, point = nil,
                   maximum_power = 6,
                   search_margin = 0,
                   recursion_limit = 8,
                   parameter = :t)
    Algebra.local_delta_invariant(
      polynomial, x_variable, y_variable, point,
      maximum_power, search_margin,
      recursion_limit, parameter).delta
