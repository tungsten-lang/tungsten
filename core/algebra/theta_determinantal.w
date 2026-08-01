# Galois-fixed even theta characteristics and symmetric determinantal classes.
#
# A smooth non-hyperelliptic genus-three curve has 36 even theta
# characteristics, in bijection with its 36 equivalence classes of symmetric
# 4x4 linear determinantal representations.  This layer performs the finite
# fixed-point calculation for an explicitly supplied subgroup of the canonical
# Sp6(F2) action.  Applying the result to a curve still requires a certified
# arithmetic identification of that subgroup with the curve's Galois action.


+ ThetaDeterminantalFixedSetCertificate
  -> new(@fixed_set)
    @verified_cache = nil

  -> fixed_set
    @fixed_set

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
    expected = "ThetaDeterminantalFixedSet"
    return false if @fixed_set.class_name != expected
    incidence = @fixed_set.incidence
    subgroup = @fixed_set.subgroup
    return false if !incidence.certificate.verified?
    return false if !subgroup.certificate.verified?
    return false if subgroup.degree != 28
    lifts = @fixed_set.generator_lifts
    return false if lifts.size != subgroup.generators.size
    index = 0
    while index < lifts.size
      return false if !lifts[index].certificate.verified?
      return false if lifts[index].permutation.to_s != (
        subgroup.generators[index].images.to_s)
      index += 1

    forms = @fixed_set.even_characteristics
    return false if forms.size != 36
    forms.each -> (form)
      return false if form.odd? || !form.certificate.verified?

    expected_fixed = []
    forms.each -> (form)
      fixed = true
      lifts.each -> (lift)
        image = lift.transformed_characteristic(form)
        if !F2LinearAlgebra.same_vector?(
             image, form.characteristic)
          fixed = false
      expected_fixed.push(form) if fixed
    supplied = @fixed_set.fixed_characteristics
    return false if supplied.size != expected_fixed.size
    index = 0
    while index < supplied.size
      return false if !F2LinearAlgebra.same_vector?(
        supplied[index].characteristic,
        expected_fixed[index].characteristic)
      index += 1
    true

  -> certified?
    verified?

  -> proof_kind
    :exact_finite_theta_fixed_set

  -> kernel_checked?
    true

  -> theorem
    "even theta characteristics classify symmetric determinantal representations of a smooth plane quartic"

  -> theorem_reference
    "Hesse correspondence for smooth plane quartics"

  -> classification_theorem_kernel_checked?
    false


+ ThetaDeterminantalFixedSet
  -> new(@incidence, @subgroup)
    if @incidence.class_name != "GenusThreeThetaIncidence"
      raise "determinantal fixed set needs genus-three theta incidence"
    if @subgroup.class_name != "FinitePermutationGroup"
      raise "determinantal fixed set needs a finite permutation subgroup"
    if !@subgroup.certificate.verified? || @subgroup.degree != 28
      raise "determinantal fixed set needs a certified 28-point subgroup"
    @generator_lifts = []
    @subgroup.generators.each -> (generator)
      @generator_lifts.push(
        GenusThreeThetaPermutation.from_permutation(
          @incidence, generator))
    @even_characteristics = []
    encoded = 0
    while encoded < 64
      form = ThetaQuadraticForm.new(
        @incidence.space,
        @incidence.space.vector(encoded))
      @even_characteristics.push(form) if !form.odd?
      encoded += 1
    @fixed_characteristics = []
    @even_characteristics.each -> (form)
      fixed = true
      @generator_lifts.each -> (lift)
        image = lift.transformed_characteristic(form)
        if !F2LinearAlgebra.same_vector?(
             image, form.characteristic)
          fixed = false
      @fixed_characteristics.push(form) if fixed
    @certificate_cache = ThetaDeterminantalFixedSetCertificate.new(self)
    if !@certificate_cache.verified?
      raise "determinantal fixed-set certificate failed"

  -> incidence
    @incidence

  -> subgroup
    @subgroup

  -> generator_lifts
    out = []
    @generator_lifts.each -> out.push(item)
    out

  -> even_characteristics
    out = []
    @even_characteristics.each -> out.push(item)
    out

  -> fixed_characteristics
    out = []
    @fixed_characteristics.each -> out.push(item)
    out

  -> fixed_count
    @fixed_characteristics.size

  # No fixed geometric class is an obstruction.  A fixed class is only a
  # candidate: descending its line bundle/matrix can still have a scalar
  # cocycle (Brauer) obstruction.
  -> permutation_fixed_class_obstruction?
    fixed_count == 0

  -> arithmetic_descent_certified?
    false

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?


+ FinitePermutationGroup
  -> determinantal_fixed_set(incidence = nil)
    incidence = Algebra.genus_three_theta_incidence if incidence == nil
    ThetaDeterminantalFixedSet.new(incidence, self)
