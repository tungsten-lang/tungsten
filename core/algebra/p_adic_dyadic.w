# Dyadic local square classes in number fields.
#
# If P lies over 2 and e = v_P(2), the Local Square Theorem gives
# U_(2e+1) inside K_P^{*2}.  The square map sends the j-th unit filtration
# layer to min(2j,j+e).  Odd layers below 2e contribute f residue-field bits;
# the critical layer 2e contributes the one-dimensional cokernel of
# y |-> y^2+y. Together with valuation parity this gives
# [K_P:Q_2]+2 exact square-class coordinates without enumerating O/P^(2e+1).

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

  # Return [coordinate vector, final unit]. Every update multiplies by an
  # explicit square or by the recorded square-class representative.
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

    e = prime_ideal.ramification_index
    f = prime_ideal.residue_degree
    local_degree = e*f
    vector = NumberFieldDyadicSquareClassArithmetic.zero_bits(
      local_degree + 2)
    vector[0] = valuation.abs % 2
    cutoff = 2*e + 1
    final_index = vector.size - 1
    steps = 0

    while current != field.one
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
        bits = residue_field.element_coefficients(
          coefficient)
        block = (depth - 1) / 2
        bit_index = 0
        factor = field.one
        residue_basis = residue_field.power_basis
        while bit_index < f
          bit = bits[bit_index]
          vector[1 + block*f + bit_index] = bit
          if bit == 1
            lift = NumberFieldDyadicSquareClassArithmetic.lift(
              prime_ideal, residue_basis[bit_index])
            representative = field.one
            representative += lift * uniformizer.element**depth
            factor *= representative
          bit_index += 1
        current *= factor
      elsif depth < 2*e
        half_depth = depth / 2
        root = residue_field.inverse_frobenius(
          coefficient)
        lift = NumberFieldDyadicSquareClassArithmetic.lift(
          prime_ideal, root)
        square_root = field.one
        square_root += lift * uniformizer.element**half_depth
        current *= square_root**2
      elsif depth == 2*e
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
            deep_normalized = residue_field.divide(
              deep_data[0], d_square)
            root = NumberFieldDyadicSquareClassArithmetic.artin_schreier_preimage(
              residue_field, deep_normalized)
            root = residue_field.multiply(d, root)
            lift = NumberFieldDyadicSquareClassArithmetic.lift(
              prime_ideal, root)
            square_root = field.one
            square_root += lift * uniformizer.element**e
            current *= square_root**2
      else
        raise "dyadic unit-filtration depth is unsupported"

      steps += 1
      if steps > 4*e + 8
        raise "dyadic square-class filtration did not terminate"

    if current != field.one
      tail = current - field.one
      tail_profile = NumberFieldDyadicSquareClassArithmetic.profile(
        prime_ideal, tail)
      if tail_profile.at(prime_ideal) < cutoff
        raise "dyadic square-class tail is not in U_(2e+1)"
    [vector, current]

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
    replay = NumberFieldDyadicSquareClassArithmetic.coordinates(
      prime, value, profile)
    vector = @square_class.vector
    expected_dimension = prime.ramification_index
    expected_dimension *= prime.residue_degree
    expected_dimension += 2
    return false if vector.size != expected_dimension
    return false if !F2LinearAlgebra.same_vector?(
      replay[0], vector)
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
