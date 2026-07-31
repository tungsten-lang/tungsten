# Dyadic local square classes in number fields.
#
# If P lies over 2 and e = v_P(2), the Local Square Theorem gives
# U_(2e+1) inside K_P^{*2}.  The square map sends the j-th unit filtration
# layer to min(2j,j+e).  Odd layers below 2e contribute f residue-field bits;
# the critical layer 2e contributes the one-dimensional cokernel of
# y |-> y^2+y. Together with valuation parity this gives
# [K_P:Q_2]+2 exact square-class coordinates without enumerating O/P^(2e+1).

+ NumberFieldDyadicSquareClassReplayStep
  -> new(@kind, @before, @difference_profile,
         @coefficient_residue, @payload, @after)

  -> kind
    @kind

  -> before
    @before

  -> difference_profile
    @difference_profile

  -> coefficient_residue
    @coefficient_residue

  -> payload
    @payload

  -> after
    @after


+ NumberFieldDyadicSquareClassArithmetic
  -> .profile(prime_ideal, value)
    NumberFieldPrimeValuationProfile.new(
      prime_ideal.field, value, 2)

  -> .residue_at_valuation(
       prime_ideal, value, valuation,
       uniformizer, profile = nil)
    source = profile
    if source == nil
      source = NumberFieldDyadicSquareClassArithmetic.profile(
        prime_ideal, value)
    if source.value != value
      raise "dyadic residue profile changes its element"
    if source.at(prime_ideal) != valuation
      raise "dyadic residue profile has the wrong target valuation"
    adjusted = source
    already_adjusted = source.class_name == "NumberFieldUniformizerAdjustedValuationProfile"
    if already_adjusted
      if valuation != 0
        raise "nested dyadic residue adjustment is unsupported"
    else
      adjusted = NumberFieldUniformizerAdjustedValuationProfile.new(
        source, prime_ideal, uniformizer, valuation)
    residue = NumberFieldLocalUnitResidue.new(
      prime_ideal, adjusted.value, adjusted)
    [residue.residue, adjusted, residue]

  -> .lift(prime_ideal, residue)
    prime_ideal.lift_residue(residue)

  -> .trace_one(residue_field)
    value = 0
    while value < residue_field.order
      return value if residue_field.trace(value) == 1
      value += 1
    raise "finite residue field has no trace-one element"

  -> .artin_schreier_preimage(
       residue_field, value,
       search_limit = 1_000_000)
    target = residue_field.normalize_element(value)
    candidate = 0
    attempts = 0
    while candidate < residue_field.order
      attempts += 1
      if attempts > search_limit
        raise "Artin-Schreier search limit exceeded"
      image = residue_field.add(
        residue_field.multiply(candidate, candidate),
        candidate)
      return candidate if residue_field.equal?(
        image, target)
      candidate += 1
    raise "residue element is outside the Artin-Schreier image"

  -> .zero_bits(size)
    out = []
    size.times -> out.push(0)
    out

  # Return [coordinate vector, final unit, replay certificate]. Every update
  # multiplies by an explicit square or by the recorded square-class
  # representative. Retaining the already-certified valuation and residue
  # witnesses lets the consumer replay the transcript without performing the
  # expensive local ideal arithmetic a second time.
  -> .coordinates(
       prime_ideal, value, valuation_profile = nil)
    if prime_ideal.class_name != "NumberFieldPrimeIdeal"
      raise "dyadic square classes need a number-field prime ideal"
    if prime_ideal.rational_prime != 2
      raise "dyadic square classes need residue characteristic two"
    field = prime_ideal.field
    element = field.coerce(value)
    raise "zero has no local multiplicative square class" if element.zero?
    profile = valuation_profile
    if profile == nil
      profile = NumberFieldDyadicSquareClassArithmetic.profile(
        prime_ideal, element)
    if profile.class_name != "NumberFieldPrimeValuationProfile"
      raise "dyadic square class needs a general prime valuation profile"
    if !profile.certificate.verified? || profile.value != element
      raise "dyadic square-class valuation profile is uncertified"
    if profile.rational_prime != 2
      raise "dyadic square-class valuation profile changes the prime"

    valuation = profile.at(prime_ideal)
    uniformizer = prime_ideal.uniformizer
    adjusted = NumberFieldUniformizerAdjustedValuationProfile.new(
      profile, prime_ideal, uniformizer, valuation)
    unit = adjusted.value
    residue_data = NumberFieldDyadicSquareClassArithmetic.residue_at_valuation(
      prime_ideal, unit, 0, uniformizer,
      adjusted)
    residue_field = prime_ideal.residue_field
    inverse_residue = residue_field.inverse(
      residue_data[0])
    residue_square_root = residue_field.inverse_frobenius(
      inverse_residue)
    residue_lift = NumberFieldDyadicSquareClassArithmetic.lift(
      prime_ideal, residue_square_root)
    current = unit * residue_lift**2
    initial_current = current

    e = prime_ideal.ramification_index
    f = prime_ideal.residue_degree
    local_degree = e*f
    vector = NumberFieldDyadicSquareClassArithmetic.zero_bits(
      local_degree + 2)
    vector[0] = valuation.abs % 2
    cutoff = 2*e + 1
    final_index = vector.size - 1
    steps = 0
    replay_steps = []

    while current != field.one
      before = current
      difference = current - field.one
      difference_profile = NumberFieldDyadicSquareClassArithmetic.profile(
        prime_ideal, difference)
      depth = difference_profile.at(prime_ideal)
      break if depth >= cutoff
      if depth < 1
        raise "dyadic unit-filtration update left U_1"
      coefficient_data = NumberFieldDyadicSquareClassArithmetic.residue_at_valuation(
        prime_ideal, difference, depth,
        uniformizer, difference_profile)
      coefficient = coefficient_data[0]

      if depth < 2*e && depth.odd?
        kind = :odd
        bits = residue_field.element_coefficients(
          coefficient)
        block = (depth - 1) / 2
        bit_index = 0
        factor = field.one
        lifts = []
        residue_basis = residue_field.power_basis
        while bit_index < f
          bit = bits[bit_index]
          vector[1 + block*f + bit_index] = bit
          if bit == 1
            lift = NumberFieldDyadicSquareClassArithmetic.lift(
              prime_ideal, residue_basis[bit_index])
            lifts.push(lift)
            representative = field.one
            representative += lift * uniformizer.element**depth
            factor *= representative
          else
            lifts.push(nil)
          bit_index += 1
        current *= factor
        payload = [bits, lifts, factor]
      elsif depth < 2*e
        kind = :even
        half_depth = depth / 2
        root = residue_field.inverse_frobenius(
          coefficient)
        lift = NumberFieldDyadicSquareClassArithmetic.lift(
          prime_ideal, root)
        square_root = field.one
        square_root += lift * uniformizer.element**half_depth
        current *= square_root**2
        payload = [root, lift, square_root]
      elsif depth == 2*e
        kind = :critical
        two_profile = NumberFieldDyadicSquareClassArithmetic.profile(
          prime_ideal, field.coerce(2))
        two_data = NumberFieldDyadicSquareClassArithmetic.residue_at_valuation(
          prime_ideal, field.coerce(2), e,
          uniformizer, two_profile)
        d = two_data[0]
        d_square = residue_field.multiply(d, d)
        normalized = residue_field.divide(
          coefficient, d_square)
        deep_bit = residue_field.trace(normalized)
        vector[final_index] = deep_bit
        trace_one = nil
        deep_lift = nil
        representative = field.one
        if deep_bit == 1
          trace_one = NumberFieldDyadicSquareClassArithmetic.trace_one(
            residue_field)
          deep_coefficient = residue_field.multiply(
            d_square, trace_one)
          deep_lift = NumberFieldDyadicSquareClassArithmetic.lift(
            prime_ideal, deep_coefficient)
          representative = field.one
          representative += deep_lift * uniformizer.element**(2*e)
          current *= representative

        intermediate = current
        deep_profile = nil
        deep_residue = nil
        artin_preimage = nil
        correction_root = nil
        correction_lift = nil
        square_root = nil
        if current != field.one
          deep_difference = current - field.one
          deep_profile = NumberFieldDyadicSquareClassArithmetic.profile(
            prime_ideal, deep_difference)
          deep_depth = deep_profile.at(prime_ideal)
          if deep_depth < cutoff
            if deep_depth != 2*e
              raise "critical dyadic update has the wrong depth"
            deep_data = NumberFieldDyadicSquareClassArithmetic.residue_at_valuation(
              prime_ideal, deep_difference,
              deep_depth, uniformizer,
              deep_profile)
            deep_residue = deep_data[2]
            deep_normalized = residue_field.divide(
              deep_data[0], d_square)
            artin_preimage = NumberFieldDyadicSquareClassArithmetic.artin_schreier_preimage(
              residue_field, deep_normalized)
            correction_root = residue_field.multiply(
              d, artin_preimage)
            correction_lift = NumberFieldDyadicSquareClassArithmetic.lift(
              prime_ideal, correction_root)
            square_root = field.one
            square_root += correction_lift * uniformizer.element**e
            current *= square_root**2
        payload = [
          two_profile, two_data[2], d, d_square,
          normalized, deep_bit, trace_one, deep_lift,
          representative, intermediate, deep_profile,
          deep_residue, artin_preimage, correction_root,
          correction_lift, square_root]
      else
        raise "dyadic unit-filtration depth is unsupported"

      replay_steps.push(
        NumberFieldDyadicSquareClassReplayStep.new(
          kind, before, difference_profile,
          coefficient_data[2], payload, current))
      steps += 1
      if steps > 4*e + 8
        raise "dyadic square-class filtration did not terminate"

    tail_profile = nil
    if current != field.one
      tail = current - field.one
      tail_profile = NumberFieldDyadicSquareClassArithmetic.profile(
        prime_ideal, tail)
      if tail_profile.at(prime_ideal) < cutoff
        raise "dyadic square-class tail is not in U_(2e+1)"
    replay = NumberFieldDyadicSquareClassReplayCertificate.new(
      prime_ideal, element, profile, valuation,
      uniformizer, adjusted, residue_data[2],
      residue_square_root, residue_lift,
      initial_current, replay_steps, tail_profile,
      vector, current)
    [vector, current, replay]

  -> .representatives(prime_ideal)
    if prime_ideal.rational_prime != 2
      raise "dyadic representatives need a prime above two"
    field = prime_ideal.field
    residue_field = prime_ideal.residue_field
    uniformizer = prime_ideal.uniformizer
    e = prime_ideal.ramification_index
    out = [uniformizer.element]
    depth = 1
    while depth < 2*e
      residue_field.power_basis.each -> (residue_basis)
        lift = NumberFieldDyadicSquareClassArithmetic.lift(
          prime_ideal, residue_basis)
        representative = field.one
        representative += lift * uniformizer.element**depth
        out.push(representative)
      depth += 2
    two_profile = NumberFieldDyadicSquareClassArithmetic.profile(
      prime_ideal, field.coerce(2))
    two_data = NumberFieldDyadicSquareClassArithmetic.residue_at_valuation(
      prime_ideal, field.coerce(2), e,
      uniformizer, two_profile)
    d_square = residue_field.multiply(
      two_data[0], two_data[0])
    trace_one = NumberFieldDyadicSquareClassArithmetic.trace_one(
      residue_field)
    deep_coefficient = residue_field.multiply(
      d_square, trace_one)
    deep_lift = NumberFieldDyadicSquareClassArithmetic.lift(
      prime_ideal, deep_coefficient)
    deep = field.one
    deep += deep_lift * uniformizer.element**(2*e)
    out.push(deep)
    out


+ NumberFieldDyadicSquareClassReplayCertificate
  -> new(@prime_ideal, @value, @valuation_profile,
         @valuation, @uniformizer, @adjusted_profile,
         @normalization_residue, @residue_square_root,
         @residue_lift, @initial_current, @steps,
         @tail_profile, @vector, @final_unit)
    @verified_cache = nil

  -> prime_ideal
    @prime_ideal

  -> value
    @value

  -> valuation_profile
    @valuation_profile

  -> vector
    F2LinearAlgebra.copy_vector(@vector)

  -> final_unit
    @final_unit

  -> steps
    out = []
    @steps.each -> out.push(item)
    out

  -> theorem
    "the dyadic square-class coordinates replay through exact higher-unit filtration witnesses"

  -> theorem_reference
    "Local Square Theorem and the dyadic higher-unit squaring filtration"

  -> verified?
    return @verified_cache if @verified_cache != nil
    answer = false
    begin
      answer = verify!
    rescue error
      answer = false
    @verified_cache = answer
    answer

  -> verified_residue_at_valuation?(
       residue, source_profile, valuation)
    return false if residue == nil
    return false if residue.class_name != "NumberFieldLocalUnitResidue"
    return false if !residue.certificate.verified?
    return false if !residue.prime_ideal.eql?(@prime_ideal)
    adjusted = residue.valuation_profile
    return false if adjusted.class_name != "NumberFieldUniformizerAdjustedValuationProfile"
    return false if adjusted.source != source_profile
    return false if !adjusted.prime_ideal.eql?(@prime_ideal)
    return false if adjusted.uniformizer != @uniformizer
    return false if adjusted.exponent != valuation
    return false if adjusted.at(@prime_ideal) != 0
    residue.value == adjusted.value

  -> verified_lift?(lift, residue)
    return false if lift == nil
    return false if lift.field != @prime_ideal.field
    field = @prime_ideal.residue_field
    field.equal?(@prime_ideal.reduce(lift), residue)

  -> verify_odd_step(step, depth, coefficient,
                     expected_vector)
    payload = step.payload
    return false if payload.size != 3
    bits = payload[0]
    lifts = payload[1]
    factor = payload[2]
    residue_field = @prime_ideal.residue_field
    wanted_bits = residue_field.element_coefficients(
      coefficient)
    return false if !F2LinearAlgebra.same_vector?(
      bits, wanted_bits)
    f = @prime_ideal.residue_degree
    return false if bits.size != f || lifts.size != f
    block = (depth - 1) / 2
    replay_factor = @prime_ideal.field.one
    basis = residue_field.power_basis
    index = 0
    while index < f
      bit = bits[index]
      return false if bit != 0 && bit != 1
      expected_vector[1 + block*f + index] = bit
      if bit == 1
        lift = lifts[index]
        return false if !verified_lift?(
          lift, basis[index])
        representative = @prime_ideal.field.one
        representative += lift * @uniformizer.element**depth
        replay_factor *= representative
      else
        return false if lifts[index] != nil
      index += 1
    return false if factor != replay_factor
    step.after == step.before * replay_factor

  -> verify_even_step(step, depth, coefficient)
    payload = step.payload
    return false if payload.size != 3
    root = payload[0]
    lift = payload[1]
    square_root = payload[2]
    residue_field = @prime_ideal.residue_field
    wanted_root = residue_field.inverse_frobenius(
      coefficient)
    return false if !residue_field.equal?(
      root, wanted_root)
    return false if !verified_lift?(lift, root)
    wanted_square_root = @prime_ideal.field.one
    wanted_square_root += lift * @uniformizer.element**(depth / 2)
    return false if square_root != wanted_square_root
    step.after == step.before * square_root**2

  -> verify_critical_step(step, coefficient,
                         expected_vector)
    payload = step.payload
    return false if payload.size != 16
    two_profile = payload[0]
    two_residue = payload[1]
    d = payload[2]
    d_square = payload[3]
    normalized = payload[4]
    deep_bit = payload[5]
    trace_one = payload[6]
    deep_lift = payload[7]
    representative = payload[8]
    intermediate = payload[9]
    deep_profile = payload[10]
    deep_residue = payload[11]
    artin_preimage = payload[12]
    correction_root = payload[13]
    correction_lift = payload[14]
    square_root = payload[15]

    field = @prime_ideal.field
    residue_field = @prime_ideal.residue_field
    e = @prime_ideal.ramification_index
    cutoff = 2*e + 1
    two = field.coerce(2)
    return false if two_profile == nil
    return false if two_profile.class_name != "NumberFieldPrimeValuationProfile"
    return false if !two_profile.certificate.verified?
    return false if two_profile.value != two
    return false if two_profile.rational_prime != 2
    return false if two_profile.at(@prime_ideal) != e
    return false if !verified_residue_at_valuation?(
      two_residue, two_profile, e)
    return false if !residue_field.equal?(
      d, two_residue.residue)
    wanted_d_square = residue_field.multiply(d, d)
    return false if !residue_field.equal?(
      d_square, wanted_d_square)
    wanted_normalized = residue_field.divide(
      coefficient, d_square)
    return false if !residue_field.equal?(
      normalized, wanted_normalized)
    wanted_bit = residue_field.trace(normalized)
    return false if deep_bit != wanted_bit
    return false if deep_bit != 0 && deep_bit != 1
    expected_vector[expected_vector.size - 1] = deep_bit

    wanted_representative = field.one
    if deep_bit == 1
      return false if trace_one == nil
      return false if residue_field.trace(trace_one) != 1
      deep_coefficient = residue_field.multiply(
        d_square, trace_one)
      return false if !verified_lift?(
        deep_lift, deep_coefficient)
      wanted_representative += deep_lift * @uniformizer.element**(2*e)
    else
      return false if trace_one != nil
      return false if deep_lift != nil
    return false if representative != wanted_representative
    wanted_intermediate = step.before * representative
    return false if intermediate != wanted_intermediate

    if intermediate == field.one
      return false if deep_profile != nil
      return false if deep_residue != nil
      return false if artin_preimage != nil
      return false if correction_root != nil
      return false if correction_lift != nil
      return false if square_root != nil
      return step.after == intermediate

    return false if deep_profile == nil
    return false if deep_profile.class_name != "NumberFieldPrimeValuationProfile"
    return false if !deep_profile.certificate.verified?
    return false if deep_profile.value != intermediate - field.one
    return false if deep_profile.rational_prime != 2
    deep_depth = deep_profile.at(@prime_ideal)
    if deep_depth >= cutoff
      return false if deep_residue != nil
      return false if artin_preimage != nil
      return false if correction_root != nil
      return false if correction_lift != nil
      return false if square_root != nil
      return step.after == intermediate

    return false if deep_depth != 2*e
    return false if !verified_residue_at_valuation?(
      deep_residue, deep_profile, deep_depth)
    deep_normalized = residue_field.divide(
      deep_residue.residue, d_square)
    return false if artin_preimage == nil
    artin_image = residue_field.add(
      residue_field.multiply(
        artin_preimage, artin_preimage),
      artin_preimage)
    return false if !residue_field.equal?(
      artin_image, deep_normalized)
    wanted_correction_root = residue_field.multiply(
      d, artin_preimage)
    return false if !residue_field.equal?(
      correction_root, wanted_correction_root)
    return false if !verified_lift?(
      correction_lift, correction_root)
    wanted_square_root = field.one
    wanted_square_root += correction_lift * @uniformizer.element**e
    return false if square_root != wanted_square_root
    step.after == intermediate * square_root**2

  -> verify!
    return false if @prime_ideal.class_name != "NumberFieldPrimeIdeal"
    return false if @prime_ideal.rational_prime != 2
    return false if !@prime_ideal.certificate.verified?
    field = @prime_ideal.field
    return false if @value.zero? || @value.field != field
    return false if @valuation_profile.class_name != "NumberFieldPrimeValuationProfile"
    return false if !@valuation_profile.certificate.verified?
    return false if @valuation_profile.value != @value
    return false if @valuation_profile.rational_prime != 2
    return false if @valuation_profile.at(
      @prime_ideal) != @valuation
    return false if !@uniformizer.certificate.verified?
    return false if !@uniformizer.prime_ideal.eql?(
      @prime_ideal)
    return false if @adjusted_profile.class_name != "NumberFieldUniformizerAdjustedValuationProfile"
    return false if !@adjusted_profile.certificate.verified?
    return false if @adjusted_profile.source != @valuation_profile
    return false if !@adjusted_profile.prime_ideal.eql?(
      @prime_ideal)
    return false if @adjusted_profile.uniformizer != @uniformizer
    return false if @adjusted_profile.exponent != @valuation
    return false if @adjusted_profile.at(@prime_ideal) != 0
    return false if @normalization_residue == nil
    return false if !@normalization_residue.certificate.verified?
    return false if @normalization_residue.valuation_profile != @adjusted_profile
    return false if @normalization_residue.value != @adjusted_profile.value
    residue_field = @prime_ideal.residue_field
    inverse_residue = residue_field.inverse(
      @normalization_residue.residue)
    root_square = residue_field.multiply(
      @residue_square_root, @residue_square_root)
    return false if !residue_field.equal?(
      root_square, inverse_residue)
    return false if !verified_lift?(
      @residue_lift, @residue_square_root)
    wanted_initial = @adjusted_profile.value * @residue_lift**2
    return false if @initial_current != wanted_initial

    e = @prime_ideal.ramification_index
    f = @prime_ideal.residue_degree
    expected_dimension = e*f + 2
    return false if @vector.size != expected_dimension
    expected_vector = NumberFieldDyadicSquareClassArithmetic.zero_bits(
      expected_dimension)
    expected_vector[0] = @valuation.abs % 2
    cutoff = 2*e + 1
    return false if @steps.size > 4*e + 8
    current = @initial_current
    index = 0
    while index < @steps.size
      step = @steps[index]
      return false if step.class_name != "NumberFieldDyadicSquareClassReplayStep"
      return false if step.before != current
      profile = step.difference_profile
      return false if profile.class_name != "NumberFieldPrimeValuationProfile"
      return false if !profile.certificate.verified?
      return false if profile.value != current - field.one
      return false if profile.rational_prime != 2
      depth = profile.at(@prime_ideal)
      return false if depth < 1 || depth >= cutoff
      residue = step.coefficient_residue
      return false if !verified_residue_at_valuation?(
        residue, profile, depth)
      coefficient = residue.residue
      valid = false
      if step.kind == :odd
        return false if depth >= 2*e || !depth.odd?
        valid = verify_odd_step(
          step, depth, coefficient,
          expected_vector)
      elsif step.kind == :even
        return false if depth >= 2*e || depth.odd?
        valid = verify_even_step(
          step, depth, coefficient)
      elsif step.kind == :critical
        return false if depth != 2*e
        valid = verify_critical_step(
          step, coefficient, expected_vector)
      else
        return false
      return false if !valid
      current = step.after
      index += 1

    return false if current != @final_unit
    if current == field.one
      return false if @tail_profile != nil
    else
      return false if @tail_profile == nil
      return false if @tail_profile.class_name != "NumberFieldPrimeValuationProfile"
      return false if !@tail_profile.certificate.verified?
      return false if @tail_profile.value != current - field.one
      return false if @tail_profile.rational_prime != 2
      return false if @tail_profile.at(@prime_ideal) < cutoff
    return false if !F2LinearAlgebra.same_vector?(
      expected_vector, @vector)
    true

  -> certified?
    verified?

  -> proof_kind
    :dyadic_square_theorem_statement_bound_transcript

  -> arithmetic_replay_checked?
    true

  -> complete_square_class_coordinates?
    true


+ NumberFieldDyadicLocalSquareClassCertificate
  -> new(@square_class)
    @verified_cache = nil

  -> theorem
    "dyadic local square classes are the odd unit-filtration layers, the critical Artin-Schreier cokernel, and valuation parity"

  -> theorem_reference
    "Local Square Theorem and the dyadic higher-unit squaring filtration"

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
    expected = "NumberFieldDyadicLocalSquareClass"
    return false if @square_class.class_name != expected
    prime = @square_class.prime_ideal
    return false if prime.rational_prime != 2
    return false if !prime.certificate.verified?
    value = @square_class.value
    return false if value.zero? || value.field != prime.field
    profile = @square_class.valuation_profile
    return false if profile.class_name != "NumberFieldPrimeValuationProfile"
    return false if !profile.certificate.verified?
    return false if profile.value != value
    replay = @square_class.replay_certificate
    return false if replay.class_name != "NumberFieldDyadicSquareClassReplayCertificate"
    return false if !replay.verified?
    return false if !replay.prime_ideal.eql?(prime)
    return false if replay.value != value
    return false if replay.valuation_profile != profile
    vector = @square_class.vector
    expected_dimension = prime.ramification_index
    expected_dimension *= prime.residue_degree
    expected_dimension += 2
    return false if vector.size != expected_dimension
    return false if !F2LinearAlgebra.same_vector?(
      replay.vector, vector)
    return false if replay.final_unit != @square_class.final_unit
    representatives = @square_class.representatives
    representatives.size == expected_dimension

  -> certified?
    verified?

  -> proof_kind
    :dyadic_square_theorem_exact_filtration

  -> kernel_checked?
    false

  -> arithmetic_replay_checked?
    true

  -> complete_square_class_coordinates?
    true


+ NumberFieldDyadicLocalSquareClass
  -> new(@prime_ideal, value, valuation_profile = nil)
    if @prime_ideal.class_name != "NumberFieldPrimeIdeal"
      raise "dyadic square class needs a number-field prime"
    if @prime_ideal.rational_prime != 2
      raise "dyadic square class needs residue characteristic two"
    @value = @prime_ideal.field.coerce(value)
    raise "zero has no local multiplicative square class" if @value.zero?
    @valuation_profile = valuation_profile
    if @valuation_profile == nil
      @valuation_profile = NumberFieldDyadicSquareClassArithmetic.profile(
        @prime_ideal, @value)
    data = NumberFieldDyadicSquareClassArithmetic.coordinates(
      @prime_ideal, @value, @valuation_profile)
    @vector = data[0]
    @final_unit = data[1]
    @replay_certificate = data[2]
    @representatives = NumberFieldDyadicSquareClassArithmetic.representatives(
      @prime_ideal)
    @certificate_cache = NumberFieldDyadicLocalSquareClassCertificate.new(
      self)
    if !@certificate_cache.verified?
      raise "dyadic local square class failed certification"

  -> prime_ideal
    @prime_ideal

  -> field
    @prime_ideal.field

  -> value
    @value

  -> valuation
    @valuation_profile.at(@prime_ideal)

  -> valuation_profile
    @valuation_profile

  -> vector
    F2LinearAlgebra.copy_vector(@vector)

  -> dimension
    @vector.size

  -> final_unit
    @final_unit

  -> replay_certificate
    @replay_certificate

  -> representatives
    out = []
    @representatives.each -> out.push(item)
    out

  -> square?
    F2LinearAlgebra.zero_vector?(@vector)

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?


+ NumberFieldDyadicLocalSquareClassMapCertificate
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
    expected = "NumberFieldDyadicLocalSquareClassMap"
    return false if @map.class_name != expected
    prime = @map.prime_ideal
    return false if prime.rational_prime != 2
    return false if !prime.certificate.verified?
    generators = @map.generators
    profiles = @map.valuation_profiles
    square_classes = @map.square_classes
    return false if profiles.size != generators.size
    return false if square_classes.size != generators.size
    expected_dimension = prime.ramification_index
    expected_dimension *= prime.residue_degree
    expected_dimension += 2
    return false if @map.target_dimension != expected_dimension
    expected_matrix = []
    expected_dimension.times ->
      expected_matrix.push([])
    index = 0
    while index < generators.size
      profile = profiles[index]
      return false if profile.class_name != "NumberFieldPrimeValuationProfile"
      return false if !profile.certificate.verified?
      return false if profile.rational_prime != 2
      return false if profile.value != generators[index]
      square_class = square_classes[index]
      return false if !square_class.certificate.verified?
      return false if square_class.prime_ideal != prime
      return false if square_class.value != generators[index]
      return false if square_class.valuation_profile != profile
      vector = square_class.vector
      row = 0
      while row < expected_dimension
        expected_matrix[row].push(vector[row])
        row += 1
      index += 1
    return false if !F2LinearAlgebra.same_matrix?(
      expected_matrix, @map.matrix)
    kernel = @map.kernel_certificate
    return false if !kernel.verified?
    return false if kernel.width != generators.size
    return false if !F2LinearAlgebra.same_matrix?(
      kernel.matrix, expected_matrix)
    kernel.source_right_hand_side.all? -> item == 0

  -> certified?
    verified?

  -> proof_kind
    :exact_dyadic_square_class_matrix

  -> arithmetic_replay_checked?
    true

  -> complete_square_class_coordinates?
    true


+ NumberFieldDyadicLocalSquareClassMap
  -> new(@prime_ideal, generators,
         valuation_profiles = nil)
    if @prime_ideal.class_name != "NumberFieldPrimeIdeal"
      raise "dyadic square-class map needs a number-field prime"
    if @prime_ideal.rational_prime != 2
      raise "dyadic square-class map needs a prime above two"
    @generators = []
    generators.each ->
      @generators.push(@prime_ideal.field.coerce(item))
    @valuation_profiles = []
    if valuation_profiles == nil
      @generators.each -> (generator)
        @valuation_profiles.push(
          NumberFieldDyadicSquareClassArithmetic.profile(
            @prime_ideal, generator))
    else
      if valuation_profiles.size != @generators.size
        raise "dyadic local square-class valuation-profile count mismatch"
      valuation_profiles.each -> @valuation_profiles.push(item)
    @square_classes = []
    vectors = []
    index = 0
    while index < @generators.size
      square_class = NumberFieldDyadicLocalSquareClass.new(
        @prime_ideal, @generators[index],
        @valuation_profiles[index])
      @square_classes.push(square_class)
      vectors.push(square_class.vector)
      index += 1
    @target_dimension = @prime_ideal.ramification_index
    @target_dimension *= @prime_ideal.residue_degree
    @target_dimension += 2
    @matrix = []
    row = 0
    while row < @target_dimension
      values = []
      vectors.each -> (vector)
        values.push(vector[row])
      @matrix.push(values)
      row += 1
    system = F2LinearSystem.new(
      @generators.size)
    @matrix.each -> (matrix_row)
      system.add_equation(matrix_row)
    @kernel_certificate = system.certificate
    @certificate_cache = NumberFieldDyadicLocalSquareClassMapCertificate.new(
      self)
    if !@certificate_cache.verified?
      raise "dyadic local square-class map failed certification"

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

  -> target_dimension
    @target_dimension

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
      vector, @generators.size)
    out = []
    @matrix.each -> (row)
      out.push(F2LinearAlgebra.dot(row, vector))
    out

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?


+ NumberFieldPrimeIdeal
  # Deterministic additive lift through the certified surjective residue map.
  -> lift_residue(value)
    residue = residue_field.normalize_element(value)
    rational_prime = self.rational_prime
    map = @algebra_prime_ideal.residue_map
    order = @field.certify_maximal_order
    columns = []
    source_indices = []
    index = 0
    while index < order.rank
      coordinates = PrimeLinearAlgebra.zero_vector(
        order.rank)
      coordinates[index] = 1
      image = map.image_order_coordinates(
        coordinates)
      candidate = residue_field.element_coefficients(
        image)
      trial = []
      columns.each -> trial.push(item)
      trial.push(candidate)
      old_rank = columns.size
      new_rank = PrimeLinearAlgebra.rank_columns(
        trial, rational_prime,
        residue_field.degree)
      if new_rank > old_rank
        columns.push(candidate)
        source_indices.push(index)
      index += 1
    small_solution = PrimeLinearAlgebra.solve_columns(
      columns,
      residue_field.element_coefficients(residue),
      rational_prime)
    solution = PrimeLinearAlgebra.zero_vector(
      order.rank)
    index = 0
    while index < small_solution.size
      solution[source_indices[index]] = small_solution[index]
      index += 1
    algebra_element = order.element(solution)
    lift = @field.generic_order_vector_to_element(
      algebra_element.coefficients)
    if reduce(lift) != residue
      raise "residue-field lift failed exact replay"
    lift

  -> dyadic_square_class(value, valuation_profile = nil)
    NumberFieldDyadicLocalSquareClass.new(
      self, value, valuation_profile)

  -> dyadic_square_class_map(
       generators, valuation_profiles = nil)
    NumberFieldDyadicLocalSquareClassMap.new(
      self, generators, valuation_profiles)


+ EtaleProductDyadicLocalSquareClassMapCertificate
  -> new(@map)
    @verified_cache = nil

  -> theorem
    "dyadic local square classes are computed by the complete higher-unit filtration"

  -> theorem_reference
    "Local Square Theorem for finite extensions of Q_2"

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
    expected = "EtaleProductDyadicLocalSquareClassMap"
    return false if @map.class_name != expected
    source = @map.source
    return false if source.class_name != "EtaleProductSUnitSquareClassSpace"
    return false if !source.certificate.verified?
    local_maps = @map.local_maps
    bases = source.flat_bases
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
      maps = local_maps[basis_index]
      expected_primes = field.prime_ideals_above(2)
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
        while block_row < block.size
          block_column = 0
          while block_column < basis.dimension
            expected_matrix[row_offset + block_row][
              column_offset + block_column] = block[
                block_row][block_column]
            block_column += 1
          block_row += 1
        row_offset += block.size
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
    :dyadic_square_theorem_exact_product_matrix

  -> arithmetic_replay_checked?
    true

  -> complete_square_class_coordinates?
    true

  -> kernel_checked?
    false


+ EtaleProductDyadicLocalSquareClassMap
  -> new(@source)
    if @source.class_name != "EtaleProductSUnitSquareClassSpace"
      raise "dyadic localization needs a true product S-unit square-class space"
    if !@source.certificate.verified?
      raise "dyadic localization source is uncertified"
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
          NumberFieldPrimeValuationProfile.new(
            field, generators[generator_index], 2,
            ideals[generator_index],
            computations[generator_index]))
        generator_index += 1
      maps = []
      field.prime_ideals_above(2).each -> (prime)
        local_map = NumberFieldDyadicLocalSquareClassMap.new(
          prime, generators, profiles)
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
      raise "dyadic localization matrix does not cover the source basis"
    system = F2LinearSystem.new(
      @source.dimension)
    @matrix.each -> (row)
      system.add_equation(row)
    @kernel_certificate = system.certificate
    @certificate_cache = EtaleProductDyadicLocalSquareClassMapCertificate.new(
      self)
    if !@certificate_cache.verified?
      raise "product dyadic localization failed certification"

  -> source
    @source

  -> rational_prime
    2

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
  -> dyadic_localization_map
    EtaleProductDyadicLocalSquareClassMap.new(
      self)

  -> localization_map(rational_prime)
    return dyadic_localization_map if rational_prime == 2
    odd_localization_map(rational_prime)
