# Odd-prime local square classes in number fields.
#
# For a completion K_P of odd residue characteristic, K_P^*/K_P^{*2} is
# detected by valuation parity and the quadratic character of the residue
# unit. All ideal valuations and residue maps are replayed exactly; the local
# square criterion is a named Hensel-theorem import.

+ NumberFieldLocalValuationCertificate
  -> new(@computation)
    @verified_cache = nil

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
    expected = "NumberFieldLocalValuationComputation"
    return false if @computation.class_name != expected
    prime = @computation.prime_ideal
    return false if !prime.certificate.verified?
    element = @computation.element
    return false if element.zero? || element.field != prime.field
    field = prime.field
    order = field.certify_maximal_order
    algebra_element = field.generic_algebra_element(element)
    coordinates = order.coordinates(algebra_element)
    denominator = 1 ## big
    coordinates.each -> (coefficient)
      denominator = denominator.lcm(
        coefficient.denominator)
    return false if denominator != @computation.clearing_denominator
    scaled = order.algebra.multiply(
      algebra_element, denominator)
    return false if scaled != @computation.scaled_algebra_element
    return false if !order.contains?(scaled)
    integral = @computation.integral_valuation_computation
    return false if !integral.certificate.verified?
    return false if !integral.prime_ideal.eql?(
      prime.algebra_prime_ideal)
    return false if integral.target != scaled
    denominator_valuation = prime.ramification_index
    denominator_valuation *= PadicArithmetic.integer_valuation(
      denominator, prime.rational_prime)
    expected_value = integral.value - denominator_valuation
    expected_value == @computation.value

  -> certified?
    verified?

  -> proof_kind
    :exact_local_prime_valuation

  -> kernel_checked?
    true


# Compute one finite-prime valuation directly in the localized maximal order.
# Clearing the maximal-order coordinate denominators avoids factoring the
# entire principal ideal, which is both unnecessary and much more expensive.
+ NumberFieldLocalValuationComputation
  -> new(@prime_ideal, value)
    if @prime_ideal.class_name != "NumberFieldPrimeIdeal"
      raise "local valuation needs a number-field prime ideal"
    @element = @prime_ideal.field.coerce(value)
    raise "zero has infinite local valuation" if @element.zero?
    field = @prime_ideal.field
    order = field.certify_maximal_order
    algebra_element = field.generic_algebra_element(
      @element)
    coordinates = order.coordinates(algebra_element)
    @clearing_denominator = 1 ## big
    coordinates.each -> (coefficient)
      @clearing_denominator = @clearing_denominator.lcm(
        coefficient.denominator)
    @scaled_algebra_element = order.algebra.multiply(
      algebra_element, @clearing_denominator)
    if !order.contains?(@scaled_algebra_element)
      raise "local valuation failed to clear maximal-order coordinates"
    algebra_prime = @prime_ideal.algebra_prime_ideal
    @integral_valuation_computation = algebra_prime.valuation_with_certificate(
      @scaled_algebra_element)
    denominator_valuation = @prime_ideal.ramification_index
    denominator_valuation *= PadicArithmetic.integer_valuation(
      @clearing_denominator, @prime_ideal.rational_prime)
    @value = @integral_valuation_computation.value - denominator_valuation
    @certificate_cache = NumberFieldLocalValuationCertificate.new(
      self)
    if !@certificate_cache.verified?
      raise "number-field local valuation failed certification"

  -> prime_ideal
    @prime_ideal

  -> element
    @element

  -> clearing_denominator
    @clearing_denominator

  -> scaled_algebra_element
    @scaled_algebra_element

  -> integral_valuation_computation
    @integral_valuation_computation

  -> value
    @value

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?


+ NumberFieldOddPrimeValuationProfileCertificate
  -> new(@profile)
    @verified_cache = nil

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
    profile_class = @profile.class_name
    supported = profile_class == "NumberFieldOddPrimeValuationProfile"
    supported = true if profile_class == "NumberFieldPrimeValuationProfile"
    return false if !supported
    field = @profile.field
    return false if field.class_name != "NumberField"
    prime = @profile.rational_prime
    return false if !prime.prime?
    if profile_class == "NumberFieldOddPrimeValuationProfile"
      return false if prime == 2
    value = @profile.value
    return false if value.zero? || value.field != field
    primes = field.prime_ideals_above(prime)
    values = @profile.values
    return false if values.size != primes.size

    if @profile.uses_certified_principal_ideal?
      computation = @profile.principal_computation
      ideal = @profile.fractional_ideal
      return false if !computation.certificate.verified?
      return false if !computation.order.same_order?(
        field.certify_maximal_order)
      return false if computation.value != field.generic_algebra_element(
        value)
      return false if !computation.ideal.eql?(
        ideal.algebra_fractional_ideal)
      return false if !ideal.certificate.verified?
      index = 0
      while index < primes.size
        return false if values[index] != ideal.valuation(
          primes[index])
        index += 1
    else
      computations = @profile.direct_computations
      return false if computations.size != primes.size
      index = 0
      while index < primes.size
        computation = computations[index]
        return false if !computation.certificate.verified?
        return false if computation.prime_ideal != primes[index]
        return false if computation.element != value
        return false if computation.value != values[index]
        index += 1
    true

  -> certified?
    verified?

  -> proof_kind
    :exact_prime_valuation_profile

  -> kernel_checked?
    true


# All valuations above one rational prime. The historical
# NumberFieldOddPrimeValuationProfile name remains the checked entry point for
# odd-local arithmetic; NumberFieldPrimeValuationProfile uses the same exact
# engine at 2. A supplied principal-ideal
# computation is reused when a certified S-unit basis already owns it;
# standalone callers use direct localized valuation certificates instead.
+ NumberFieldOddPrimeValuationProfile
  -> new(@field, value, @rational_prime,
         @fractional_ideal = nil,
         @principal_computation = nil)
    if @field.class_name != "NumberField"
      raise "valuation profile needs a NumberField"
    if !@rational_prime.prime?
      raise "valuation profile needs a rational prime"
    wrong_odd_prime = @rational_prime == 2
    wrong_odd_prime = false if self.class_name != "NumberFieldOddPrimeValuationProfile"
    if wrong_odd_prime
      raise "odd valuation profile needs an odd rational prime"
    @value = @field.coerce(value)
    raise "zero has no finite valuation profile" if @value.zero?
    @values = []
    @direct_computations = []
    supplied = @fractional_ideal != nil
    supplied = true if @principal_computation != nil
    if supplied
      if @fractional_ideal == nil || @principal_computation == nil
        raise "valuation profile needs both ideal and principal computation"
      if @fractional_ideal.class_name != "NumberFieldFractionalIdeal"
        raise "valuation profile has the wrong fractional ideal"
      if @fractional_ideal.field != @field
        raise "valuation profile fractional ideal changes field"
      @field.prime_ideals_above(
        @rational_prime).each -> (prime)
        @values.push(@fractional_ideal.valuation(prime))
    else
      @field.prime_ideals_above(
        @rational_prime).each -> (prime)
        computation = prime.local_valuation_with_certificate(
          @value)
        @direct_computations.push(computation)
        @values.push(computation.value)
    @certificate_cache = NumberFieldOddPrimeValuationProfileCertificate.new(
      self)
    if !@certificate_cache.verified?
      raise "odd-prime valuation profile failed certification"

  -> field
    @field

  -> value
    @value

  -> rational_prime
    @rational_prime

  -> primes
    @field.prime_ideals_above(@rational_prime)

  -> values
    F2LinearAlgebra.copy_vector(@values)

  -> at(prime_ideal)
    index = 0
    profile_primes = primes
    while index < profile_primes.size
      return @values[index] if profile_primes[index].eql?(
        prime_ideal)
      index += 1
    raise "prime ideal is outside the valuation profile"

  -> uses_certified_principal_ideal?
    @fractional_ideal != nil

  -> fractional_ideal
    @fractional_ideal

  -> principal_computation
    @principal_computation

  -> direct_computations
    out = []
    @direct_computations.each -> out.push(item)
    out

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?


+ NumberFieldPrimeValuationProfile < NumberFieldOddPrimeValuationProfile


+ NumberFieldUniformizerAdjustedValuationProfileCertificate
  -> new(@profile)
    @verified_cache = nil

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
    expected = "NumberFieldUniformizerAdjustedValuationProfile"
    return false if @profile.class_name != expected
    source = @profile.source
    return false if !source.certificate.verified?
    uniformizer = @profile.uniformizer
    return false if !uniformizer.certificate.verified?
    prime = @profile.prime_ideal
    return false if uniformizer.prime_ideal != prime
    return false if source.rational_prime != prime.rational_prime
    exponent = @profile.exponent
    expected_value = source.value / uniformizer.element**exponent
    return false if @profile.value != expected_value
    values = @profile.values
    primes = source.primes
    return false if values.size != primes.size
    index = 0
    while index < primes.size
      wanted = source.values[index]
      wanted -= exponent if primes[index].eql?(prime)
      return false if values[index] != wanted
      index += 1
    true

  -> certified?
    verified?

  -> proof_kind
    :exact_uniformizer_adjusted_valuation_profile

  -> kernel_checked?
    true


+ NumberFieldUniformizerAdjustedValuationProfile
  -> new(@source, @prime_ideal, @uniformizer, @exponent)
    source_class = @source.class_name
    valid_source = source_class == "NumberFieldOddPrimeValuationProfile"
    valid_source = true if source_class == "NumberFieldPrimeValuationProfile"
    if !valid_source
      raise "adjusted valuation profile needs a certified base profile"
    if @prime_ideal.class_name != "NumberFieldPrimeIdeal"
      raise "adjusted valuation profile needs a number-field prime"
    if @uniformizer.class_name != "NumberFieldPrimeUniformizer"
      raise "adjusted valuation profile needs a certified uniformizer"
    @value = @source.value / @uniformizer.element**@exponent
    @values = @source.values
    index = 0
    @source.primes.each -> (prime)
      if prime.eql?(@prime_ideal)
        @values[index] -= @exponent
      index += 1
    @certificate_cache = NumberFieldUniformizerAdjustedValuationProfileCertificate.new(
      self)
    if !@certificate_cache.verified?
      raise "uniformizer-adjusted valuation profile failed certification"

  -> source
    @source

  -> field
    @source.field

  -> rational_prime
    @source.rational_prime

  -> primes
    @source.primes

  -> prime_ideal
    @prime_ideal

  -> uniformizer
    @uniformizer

  -> exponent
    @exponent

  -> value
    @value

  -> values
    F2LinearAlgebra.copy_vector(@values)

  -> at(prime_ideal)
    index = 0
    profile_primes = primes
    while index < profile_primes.size
      return @values[index] if profile_primes[index].eql?(
        prime_ideal)
      index += 1
    raise "prime ideal is outside the adjusted valuation profile"

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?


+ NumberFieldPrimeUniformizerCertificate
  -> new(@uniformizer)
    @verified_cache = nil

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
    expected = "NumberFieldPrimeUniformizer"
    return false if @uniformizer.class_name != expected
    prime = @uniformizer.prime_ideal
    return false if !prime.certificate.verified?
    element = @uniformizer.element
    return false if element.field != prime.field
    primes = prime.field.prime_ideals_above(
      prime.rational_prime)
    computations = @uniformizer.valuation_computations
    return false if computations.size != primes.size
    index = 0
    while index < primes.size
      computation = computations[index]
      return false if !computation.certificate.verified?
      return false if !computation.prime_ideal.eql?(primes[index])
      return false if computation.element != element
      wanted = primes[index].eql?(prime) ? 1 : 0
      return false if computation.value != wanted
      index += 1
    true

  -> certified?
    verified?

  -> proof_kind
    :exact_prime_valuation_one

  -> kernel_checked?
    true


+ NumberFieldPrimeUniformizer
  -> new(@prime_ideal)
    if @prime_ideal.class_name != "NumberFieldPrimeIdeal"
      raise "local uniformizer needs a number-field prime ideal"
    data = find_element
    @element = data[0]
    @valuation_computations = data[1]
    @certificate_cache = NumberFieldPrimeUniformizerCertificate.new(
      self)
    if !@certificate_cache.verified?
      raise "number-field local uniformizer failed certification"

  -> prime_ideal
    @prime_ideal

  -> field
    @prime_ideal.field

  -> element
    @element

  -> valuation_computations
    out = []
    @valuation_computations.each -> out.push(item)
    out

  -> find_element
    candidates = @prime_ideal.basis
    index = 0
    while index < candidates.size
      candidate = candidates[index]
      data = nil
      if valuation_shape_candidate?(candidate)
        data = separated_uniformizer_data(candidate)
      return [candidate, data] if data != nil
      index += 1
    left = 0
    while left < candidates.size
      right = left + 1
      while right < candidates.size
        scalar = 1
        while scalar <= 16
          candidate = candidates[left] + candidates[right] * scalar
          data = nil
          if valuation_shape_candidate?(candidate)
            data = separated_uniformizer_data(candidate)
          return [candidate, data] if data != nil
          candidate = candidates[left] - candidates[right] * scalar
          data = nil
          if valuation_shape_candidate?(candidate)
            data = separated_uniformizer_data(candidate)
          return [candidate, data] if data != nil
          scalar += 1
        right += 1
      left += 1

    combination_count = 2 ** candidates.size
    if combination_count > 1_000_000
      raise "uniformizer binary-combination search limit exceeded"
    code = 1
    while code < combination_count
      remaining = code
      candidate = field.zero
      candidate_index = 0
      while candidate_index < candidates.size
        if remaining % 2 == 1
          candidate += candidates[candidate_index]
        remaining = remaining / 2
        candidate_index += 1
      if valuation_shape_candidate?(candidate)
        data = separated_uniformizer_data(candidate)
        return [candidate, data] if data != nil
      code += 1
    raise "prime-ideal basis contained no valuation-one uniformizer"

  # Cheap exact screen in P/P^2 and at the other primes over p. The accepted
  # candidate is still followed by full statement-bound valuation
  # computations in separated_uniformizer_data.
  -> valuation_shape_candidate?(candidate)
    algebra_element = field.generic_algebra_element(
      candidate)
    square = @prime_ideal.algebra_prime_ideal.valuation_ideal_power(
      2)
    return false if square.contains?(algebra_element)
    field.prime_ideals_above(
      @prime_ideal.rational_prime).each -> (other)
      if !other.eql?(@prime_ideal)
        return false if other.contains?(candidate)
    true

  -> separated_uniformizer_data(candidate)
    answer = true
    computations = []
    field.prime_ideals_above(
      @prime_ideal.rational_prime).each -> (prime)
      computation = prime.local_valuation_with_certificate(
        candidate)
      computations.push(computation)
      expected = prime.eql?(@prime_ideal) ? 1 : 0
      answer = false if computation.value != expected
    answer ? computations : nil

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?


+ NumberFieldLocalResidueReduction
  -> new(@prime_ideal)
    if @prime_ideal.class_name != "NumberFieldPrimeIdeal"
      raise "local residue reduction needs a number-field prime"
    if !@prime_ideal.certificate.verified?
      raise "local residue reduction has an uncertified prime"

  -> prime_ideal
    @prime_ideal

  -> field
    @prime_ideal.field

  -> residue_field
    @prime_ideal.residue_field

  # Clear rational denominators prime to p, then use the certified maximal
  # order residue map. Localized callers first clear poles at the other primes
  # above p with separated uniformizers.
  -> reduction(value)
    element = field.coerce(value)
    raise "zero is not a local unit" if element.zero?
    order = field.certify_maximal_order
    algebra_element = field.generic_algebra_element(
      element)
    coordinates = order.coordinates(algebra_element)
    denominator = 1 ## big
    coordinates.each -> (coefficient)
      denominator = denominator.lcm(
        coefficient.denominator)
    if denominator % @prime_ideal.rational_prime == 0
      raise "local residue denominator is not invertible"
    integral = field.multiply(element, denominator)
    reduced = @prime_ideal.reduce(integral)
    if residue_field.zero?(reduced)
      raise "number-field element is not a unit at the local prime"
    residue_field.divide(
      reduced, residue_field.coerce(denominator))


+ NumberFieldLocalUnitResidueCertificate
  -> new(@local_residue)
    @verified_cache = nil

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
    expected = "NumberFieldLocalUnitResidue"
    return false if @local_residue.class_name != expected
    prime = @local_residue.prime_ideal
    return false if !prime.certificate.verified?
    value = @local_residue.value
    return false if value.zero? || value.field != prime.field
    profile = @local_residue.valuation_profile
    return false if !profile.certificate.verified?
    return false if profile.value != value
    return false if profile.rational_prime != prime.rational_prime
    return false if profile.at(prime) != 0

    numerator = @local_residue.numerator
    denominator = @local_residue.denominator
    adjustments = @local_residue.adjustments
    adjustment_index = 0
    replay_numerator = value
    replay_denominator = prime.field.one
    primes = profile.primes
    numerator_valuations = profile.values
    denominator_valuations = []
    primes.size.times -> denominator_valuations.push(0)
    prime_index = 0
    primes.each -> (other)
      if !other.eql?(prime)
        if numerator_valuations[prime_index] < 0
          return false if adjustment_index >= adjustments.size
          adjustment = adjustments[adjustment_index]
          return false if !adjustment[0].eql?(other)
          wanted_exponent = 0 - numerator_valuations[prime_index]
          return false if adjustment[1] != wanted_exponent
          uniformizer = adjustment[2]
          return false if !uniformizer.certificate.verified?
          return false if !uniformizer.prime_ideal.eql?(other)
          factor = uniformizer.element**adjustment[1]
          replay_numerator *= factor
          replay_denominator *= factor
          numerator_valuations[prime_index] += adjustment[1]
          denominator_valuations[prime_index] += adjustment[1]
          adjustment_index += 1
      prime_index += 1
    return false if adjustment_index != adjustments.size
    return false if replay_numerator != numerator
    return false if replay_denominator != denominator
    prime_index = 0
    while prime_index < primes.size
      return false if numerator_valuations[prime_index] < 0
      if primes[prime_index].eql?(prime)
        return false if denominator_valuations[prime_index] != 0
      prime_index += 1

    reduction = NumberFieldLocalResidueReduction.new(
      prime)
    numerator_residue = reduction.reduction(numerator)
    denominator_residue = reduction.reduction(denominator)
    residue = prime.residue_field.divide(
      numerator_residue, denominator_residue)
    prime.residue_field.equal?(
      residue, @local_residue.residue)

  -> certified?
    verified?

  -> proof_kind
    :exact_localized_residue

  -> kernel_checked?
    true


# Reduce a P-adic unit even when its displayed maximal-order coordinates have
# p in their denominator because of poles at other primes above p. Multiplying
# by separated uniformizers clears those other local denominators without
# changing the target-prime valuation, and the same factor is divided back in
# the residue field.
+ NumberFieldLocalUnitResidue
  -> new(@prime_ideal, value, @valuation_profile)
    if @prime_ideal.class_name != "NumberFieldPrimeIdeal"
      raise "local unit residue needs a number-field prime ideal"
    @value = @prime_ideal.field.coerce(value)
    raise "zero has no local unit residue" if @value.zero?
    profile_class = @valuation_profile.class_name
    valid_profile = profile_class == "NumberFieldOddPrimeValuationProfile"
    valid_profile = true if profile_class == "NumberFieldPrimeValuationProfile"
    adjusted_class = "NumberFieldUniformizerAdjustedValuationProfile"
    valid_profile = true if profile_class == adjusted_class
    if !valid_profile || !@valuation_profile.certificate.verified?
      raise "local unit residue needs a certified valuation profile"
    if @valuation_profile.value != @value
      raise "local unit residue valuation profile changes the element"
    if @valuation_profile.at(@prime_ideal) != 0
      raise "local unit residue needs valuation zero"
    numerator = @value
    denominator = @prime_ideal.field.one
    @adjustments = []
    @valuation_profile.primes.each -> (other)
      if !other.eql?(@prime_ideal)
        valuation = @valuation_profile.at(other)
        if valuation < 0
          exponent = 0 - valuation
          uniformizer = other.uniformizer
          factor = uniformizer.element**exponent
          numerator *= factor
          denominator *= factor
          @adjustments.push([
            other, exponent, uniformizer])
    @numerator = numerator
    @denominator = denominator
    reduction = NumberFieldLocalResidueReduction.new(
      @prime_ideal)
    numerator_residue = reduction.reduction(@numerator)
    denominator_residue = reduction.reduction(@denominator)
    @residue = @prime_ideal.residue_field.divide(
      numerator_residue, denominator_residue)
    @certificate_cache = NumberFieldLocalUnitResidueCertificate.new(
      self)
    if !@certificate_cache.verified?
      raise "number-field local unit residue failed certification"

  -> prime_ideal
    @prime_ideal

  -> value
    @value

  -> valuation_profile
    @valuation_profile

  -> adjustments
    out = []
    @adjustments.each -> (adjustment)
      out.push([
        adjustment[0], adjustment[1], adjustment[2]])
    out

  -> numerator
    @numerator

  -> denominator
    @denominator

  -> residue
    @residue

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?


+ NumberFieldOddLocalSquareClassCertificate
  -> new(@square_class)
    @verified_cache = nil

  -> theorem
    "at odd residue characteristic, a local unit is a square exactly when its residue is a square"

  -> theorem_reference
    "Hensel lemma for the square map on local units"

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
    expected = "NumberFieldOddLocalSquareClass"
    return false if @square_class.class_name != expected
    prime = @square_class.prime_ideal
    return false if prime.rational_prime == 2
    return false if !prime.certificate.verified?
    value = @square_class.value
    return false if value.zero? || value.field != prime.field
    valuation_profile = @square_class.valuation_profile
    return false if !valuation_profile.certificate.verified?
    return false if valuation_profile.value != value
    return false if valuation_profile.rational_prime != prime.rational_prime
    valuation = valuation_profile.at(prime)
    return false if valuation != @square_class.valuation
    uniformizer = @square_class.uniformizer
    return false if !uniformizer.certificate.verified?
    return false if uniformizer.prime_ideal != prime
    unit = value / uniformizer.element**valuation
    local_residue = @square_class.unit_residue
    return false if !local_residue.certificate.verified?
    return false if local_residue.prime_ideal != prime
    return false if local_residue.value != unit
    character = prime.residue_field.quadratic_character(
      local_residue.residue)
    return false if character == 0
    expected_bit = character < 0 ? 1 : 0
    vector = @square_class.vector
    return false if vector.size != 2
    vector[0] == valuation.abs % 2 && vector[1] == expected_bit

  -> certified?
    verified?

  -> proof_kind
    :trusted_local_square_theorem_with_exact_ideal_replay

  -> kernel_checked?
    false

  -> arithmetic_replay_checked?
    true


+ NumberFieldOddLocalSquareClass
  -> new(@prime_ideal, value, valuation_profile = nil)
    if @prime_ideal.class_name != "NumberFieldPrimeIdeal"
      raise "local square class needs a number-field prime ideal"
    if @prime_ideal.rational_prime == 2
      raise "dyadic number-field square classes need deeper unit filtration"
    @value = @prime_ideal.field.coerce(value)
    raise "zero has no local multiplicative square class" if @value.zero?
    @valuation_profile = valuation_profile
    if @valuation_profile == nil
      @valuation_profile = NumberFieldOddPrimeValuationProfile.new(
        @prime_ideal.field, @value,
        @prime_ideal.rational_prime)
    if @valuation_profile.class_name != "NumberFieldOddPrimeValuationProfile"
      raise "local square class needs a base valuation profile"
    if @valuation_profile.value != @value
      raise "local square-class valuation profile changes the element"
    @valuation = @valuation_profile.at(@prime_ideal)
    @uniformizer = @prime_ideal.uniformizer
    @unit_valuation_profile = NumberFieldUniformizerAdjustedValuationProfile.new(
      @valuation_profile, @prime_ideal,
      @uniformizer, @valuation)
    unit = @unit_valuation_profile.value
    @unit_residue = NumberFieldLocalUnitResidue.new(
      @prime_ideal, unit, @unit_valuation_profile)
    character = @prime_ideal.residue_field.quadratic_character(
      @unit_residue.residue)
    if character == 0
      raise "local unit residue vanished"
    @vector = [
      @valuation.abs % 2,
      character < 0 ? 1 : 0]
    @certificate_cache = NumberFieldOddLocalSquareClassCertificate.new(
      self)
    if !@certificate_cache.verified?
      raise "number-field local square class failed certification"

  -> prime_ideal
    @prime_ideal

  -> field
    @prime_ideal.field

  -> value
    @value

  -> valuation
    @valuation

  -> valuation_profile
    @valuation_profile

  -> unit_valuation_profile
    @unit_valuation_profile

  -> uniformizer
    @uniformizer

  -> unit_residue
    @unit_residue

  -> vector
    F2LinearAlgebra.copy_vector(@vector)

  -> square?
    @vector[0] == 0 && @vector[1] == 0

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?


+ NumberFieldOddLocalSquareClassMapCertificate
  -> new(@map)
    @verified_cache = nil

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
    expected = "NumberFieldOddLocalSquareClassMap"
    return false if @map.class_name != expected
    prime = @map.prime_ideal
    return false if prime.rational_prime == 2
    generators = @map.generators
    profiles = @map.valuation_profiles
    square_classes = @map.square_classes
    matrix = @map.matrix
    return false if matrix.size != 2
    return false if matrix[0].size != generators.size
    return false if matrix[1].size != generators.size
    return false if profiles.size != generators.size
    return false if square_classes.size != generators.size
    index = 0
    while index < generators.size
      profile = profiles[index]
      return false if !profile.certificate.verified?
      return false if profile.value != generators[index]
      square_class = square_classes[index]
      return false if !square_class.certificate.verified?
      return false if square_class.prime_ideal != prime
      return false if square_class.value != generators[index]
      return false if square_class.valuation_profile != profile
      return false if matrix[0][index] != square_class.vector[0]
      return false if matrix[1][index] != square_class.vector[1]
      index += 1
    true

  -> certified?
    verified?

  -> proof_kind
    :exact_odd_local_square_class_matrix

  -> kernel_checked?
    false


+ NumberFieldOddLocalSquareClassMap
  -> new(@prime_ideal, generators, valuation_profiles = nil)
    if @prime_ideal.class_name != "NumberFieldPrimeIdeal"
      raise "local square-class map needs a number-field prime"
    if @prime_ideal.rational_prime == 2
      raise "dyadic local square-class maps are not implemented"
    @generators = []
    generators.each ->
      @generators.push(@prime_ideal.field.coerce(item))
    @valuation_profiles = []
    if valuation_profiles == nil
      @generators.each -> (generator)
        @valuation_profiles.push(
          NumberFieldOddPrimeValuationProfile.new(
            @prime_ideal.field, generator,
            @prime_ideal.rational_prime))
    else
      if valuation_profiles.size != @generators.size
        raise "local square-class valuation-profile count mismatch"
      valuation_profiles.each -> (profile)
        @valuation_profiles.push(profile)
    @matrix = [[], []]
    @square_classes = []
    generator_index = 0
    @generators.each -> (generator)
      square_class = NumberFieldOddLocalSquareClass.new(
        @prime_ideal, generator,
        @valuation_profiles[generator_index])
      @square_classes.push(square_class)
      vector = square_class.vector
      @matrix[0].push(vector[0])
      @matrix[1].push(vector[1])
      generator_index += 1
    @certificate_cache = NumberFieldOddLocalSquareClassMapCertificate.new(
      self)
    if !@certificate_cache.verified?
      raise "odd local square-class map failed certification"

  -> prime_ideal
    @prime_ideal

  -> generators
    out = []
    @generators.each -> out.push(item)
    out

  -> valuation_profiles
    out = []
    @valuation_profiles.each -> out.push(item)
    out

  -> square_classes
    out = []
    @square_classes.each -> out.push(item)
    out

  -> matrix
    F2LinearAlgebra.copy_matrix(@matrix)

  -> rank
    system = F2LinearSystem.new(@generators.size)
    @matrix.each -> (row)
      system.add_equation(row)
    system.rank

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?


+ NumberFieldPrimeIdeal
  -> local_valuation_with_certificate(value)
    NumberFieldLocalValuationComputation.new(
      self, value)

  -> local_valuation(value)
    local_valuation_with_certificate(value).value

  -> uniformizer
    if @uniformizer_cache == nil
      @uniformizer_cache = NumberFieldPrimeUniformizer.new(
        self)
    @uniformizer_cache

  -> local_square_class(value)
    if rational_prime == 2
      return NumberFieldDyadicLocalSquareClass.new(
        self, value)
    NumberFieldOddLocalSquareClass.new(self, value)

  -> local_square_class_map(generators, valuation_profiles = nil)
    if rational_prime == 2
      return NumberFieldDyadicLocalSquareClassMap.new(
        self, generators, valuation_profiles)
    NumberFieldOddLocalSquareClassMap.new(
      self, generators, valuation_profiles)


# The product localization map from a certified global S-unit square-class
# space to all completions above one odd rational prime. This is an exact
# finite F2 matrix once the local square-class theorem has been imported. It
# is an input to a BPS local-image comparison, not the local image itself.
+ EtaleProductOddLocalArithmetic
  -> .basis_data(basis)
    arithmetic_basis = basis
    if basis.class_name == "NumberFieldIsomorphicSUnitSquareClassBasis"
      arithmetic_basis = basis.model_basis
    if arithmetic_basis.class_name != "NumberFieldSUnitSquareClassBasis"
      raise "odd localization needs a certified number-field S-unit basis"
    [
      arithmetic_basis.field,
      arithmetic_basis.generators,
      arithmetic_basis.generator_fractional_ideals,
      arithmetic_basis.generator_fractional_ideal_computations
    ]


+ EtaleProductOddLocalSquareClassMapCertificate
  -> new(@map)
    @verified_cache = nil

  -> theorem
    "odd local square classes are detected by valuation parity and residue quadratic character"

  -> theorem_reference
    "Hensel lemma for the square map on local units"

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
    expected = "EtaleProductOddLocalSquareClassMap"
    return false if @map.class_name != expected
    source = @map.source
    return false if source.class_name != "EtaleProductSUnitSquareClassSpace"
    return false if !source.certificate.verified?
    prime = @map.rational_prime
    return false if !prime.prime? || prime == 2
    bases = source.flat_bases
    local_maps = @map.local_maps
    return false if local_maps.size != bases.size

    expected_matrix = []
    @map.target_dimension.times ->
      row = []
      source.dimension.times -> row.push(0)
      expected_matrix.push(row)

    row_offset = 0
    column_offset = 0
    basis_index = 0
    while basis_index < bases.size
      basis = bases[basis_index]
      data = EtaleProductOddLocalArithmetic.basis_data(
        basis)
      field = data[0]
      generators = data[1]
      return false if generators.size != basis.dimension
      expected_primes = field.prime_ideals_above(prime)
      maps = local_maps[basis_index]
      return false if maps.size != expected_primes.size
      local_index = 0
      while local_index < maps.size
        local_map = maps[local_index]
        return false if !local_map.certificate.verified?
        return false if !local_map.prime_ideal.eql?(
          expected_primes[local_index])
        local_generators = local_map.generators
        return false if local_generators.size != generators.size
        generator_index = 0
        while generator_index < generators.size
          return false if local_generators[generator_index] != generators[
            generator_index]
          generator_index += 1
        block = local_map.matrix
        block_row = 0
        while block_row < 2
          block_column = 0
          while block_column < basis.dimension
            expected_matrix[row_offset + block_row][
              column_offset + block_column] = block[
                block_row][block_column]
            block_column += 1
          block_row += 1
        row_offset += 2
        local_index += 1
      column_offset += basis.dimension
      basis_index += 1
    return false if row_offset != @map.target_dimension
    return false if column_offset != source.dimension
    return false if !F2LinearAlgebra.same_matrix?(
      expected_matrix, @map.matrix)

    kernel = @map.kernel_certificate
    return false if !kernel.verified?
    return false if kernel.width != source.dimension
    return false if !F2LinearAlgebra.same_matrix?(
      kernel.matrix, expected_matrix)
    kernel.source_right_hand_side.all? -> item == 0

  -> certified?
    verified?

  -> proof_kind
    :trusted_local_square_theorem_with_exact_matrix_replay

  -> kernel_checked?
    false

  -> arithmetic_replay_checked?
    true

  -> linear_kernel_replay_checked?
    true


+ EtaleProductOddLocalSquareClassMap
  -> new(@source, @rational_prime)
    if @source.class_name != "EtaleProductSUnitSquareClassSpace"
      raise "odd localization needs a true product S-unit square-class space"
    if !@source.certificate.verified?
      raise "odd localization source is uncertified"
    if !@rational_prime.prime? || @rational_prime == 2
      raise "product localization currently needs an odd rational prime"
    @local_maps = []
    @matrix = []
    column_offset = 0
    @source.flat_bases.each -> (basis)
      data = EtaleProductOddLocalArithmetic.basis_data(
        basis)
      field = data[0]
      generators = data[1]
      ideals = data[2]
      computations = data[3]
      if generators.size != basis.dimension
        raise "S-unit basis dimension disagrees with its generators"
      incomplete = ideals.size != generators.size
      incomplete = true if computations.size != generators.size
      if incomplete
        raise "S-unit basis has incomplete principal-ideal evidence"
      profiles = []
      generator_index = 0
      while generator_index < generators.size
        profiles.push(
          NumberFieldOddPrimeValuationProfile.new(
            field, generators[generator_index],
            @rational_prime, ideals[generator_index],
            computations[generator_index]))
        generator_index += 1
      maps = []
      field.prime_ideals_above(
        @rational_prime).each -> (prime)
        local_map = prime.local_square_class_map(
          generators, profiles)
        maps.push(local_map)
        local_map.matrix.each -> (block_row)
          row = []
          @source.dimension.times -> row.push(0)
          block_column = 0
          while block_column < basis.dimension
            row[column_offset + block_column] = block_row[
              block_column]
            block_column += 1
          @matrix.push(row)
      @local_maps.push(maps)
      column_offset += basis.dimension
    if column_offset != @source.dimension
      raise "odd localization matrix does not cover the source basis"
    system = F2LinearSystem.new(@source.dimension)
    @matrix.each -> (row)
      system.add_equation(row)
    @kernel_certificate = system.certificate
    @certificate_cache = EtaleProductOddLocalSquareClassMapCertificate.new(
      self)
    if !@certificate_cache.verified?
      raise "product odd localization failed certification"

  -> source
    @source

  -> rational_prime
    @rational_prime

  -> local_maps
    out = []
    @local_maps.each -> (maps)
      copied = []
      maps.each -> copied.push(item)
      out.push(copied)
    out

  -> prime_ideals
    out = []
    @local_maps.each -> (maps)
      maps.each -> (local_map)
        out.push(local_map.prime_ideal)
    out

  -> local_factor_count
    prime_ideals.size

  -> target_dimension
    @matrix.size

  -> matrix
    F2LinearAlgebra.copy_matrix(@matrix)

  -> rank
    @kernel_certificate.rank

  -> kernel_dimension
    @kernel_certificate.kernel_dimension

  -> kernel_basis
    @kernel_certificate.kernel_basis

  -> kernel_certificate
    @kernel_certificate

  -> apply(vector)
    F2LinearAlgebra.validate_vector(
      vector, @source.dimension)
    out = []
    @matrix.each -> (row)
      out.push(F2LinearAlgebra.dot(row, vector))
    out

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?


+ EtaleProductSUnitSquareClassSpace
  -> odd_localization_map(rational_prime)
    EtaleProductOddLocalSquareClassMap.new(
      self, rational_prime)
