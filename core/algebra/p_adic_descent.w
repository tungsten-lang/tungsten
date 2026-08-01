# Certified BPS local images at odd primes of good reduction.
#
# For p != 2 and good reduction, multiplication by two is an automorphism on
# the formal group of a Jacobian. Hence
#
#   J(Q_p)/2J(Q_p) = J(F_p)/2J(F_p)
#
# and its F2-dimension is dim J[2](F_p), the fixed-space dimension of
# Frobenius on geometric 2-torsion. We evaluate the BPS line-ratio family on
# every residue disk where every numerator and denominator is a local unit.
# The odd local square class then depends only on the exact residue. If these
# point-difference images reach the independently certified fixed-space
# dimension, they are the complete local image.

+ PlaneQuarticBPSGoodReductionLocalArithmetic
  -> .arithmetic_value(basis, etale_coefficient)
    if etale_coefficient.class_name != "EtaleAlgebraElement"
      raise "BPS local evaluation needs an etale coefficient"
    source = basis.field.coerce(
      etale_coefficient.polynomial.coefficients)
    if basis.class_name == "NumberFieldIsomorphicSUnitSquareClassBasis"
      return basis.source_to_model(source)
    if basis.class_name != "NumberFieldSUnitSquareClassBasis"
      raise "BPS local evaluation needs a number-field S-unit basis"
    source

  -> .line_value(function, basis, coefficients, coordinates)
    if coefficients.size != coordinates.size
      raise "BPS local line evaluation has the wrong arity"
    arithmetic_field = EtaleProductOddLocalArithmetic.basis_data(
      basis)[0]
    value = arithmetic_field.zero
    index = 0
    while index < coefficients.size
      coefficient = arithmetic_value(
        basis, coefficients[index])
      value += coefficient * coordinates[index]
      index += 1
    value

  -> .disk_vector(function_data, local_map, disk)
    functions = function_data.function_components
    nested_bases = local_map.source.component_bases
    nested_maps = local_map.local_maps
    if functions.size != nested_bases.size
      raise "BPS local evaluation component count mismatch"
    coordinates = disk.coordinates
    vector = []
    flat_index = 0
    component_index = 0
    while component_index < functions.size
      function = functions[component_index]
      bases = nested_bases[component_index]
      basis_index = 0
      while basis_index < bases.size
        if flat_index >= nested_maps.size
          raise "BPS local evaluation lost a local factor"
        basis = bases[basis_index]
        numerator = line_value(
          function, basis,
          function.numerator_coefficients,
          coordinates)
        denominator = line_value(
          function, basis,
          function.denominator_coefficients,
          coordinates)
        maps = nested_maps[flat_index]
        maps.each -> (field_map)
          prime = field_map.prime_ideal
          reducer = NumberFieldLocalResidueReduction.new(
            prime)
          numerator_residue = reducer.reduction_allow_zero(
            numerator)
          denominator_residue = reducer.reduction_allow_zero(
            denominator)
          residue_field = prime.residue_field
          if residue_field.zero?(numerator_residue)
            return nil
          if residue_field.zero?(denominator_residue)
            return nil
          ratio = residue_field.divide(
            numerator_residue, denominator_residue)
          character = residue_field.quadratic_character(
            ratio)
          return nil if character == 0
          vector.push(0)
          vector.push(character < 0 ? 1 : 0)
        flat_index += 1
        basis_index += 1
      component_index += 1
    if flat_index != nested_maps.size
      raise "BPS local evaluation has unused local factors"
    F2LinearAlgebra.validate_vector(
      vector, local_map.target_dimension)
    vector

  -> .difference(left, right)
    if left.size != right.size
      raise "BPS local image vectors have different widths"
    out = []
    index = 0
    while index < left.size
      out.push(left[index] ^ right[index])
      index += 1
    out


+ PlaneQuarticBPSImplicitDiskArithmetic
  -> .value_data(function_data, local_map, implicit_disk)
    if implicit_disk.class_name != "PadicCurveImplicitResidueDisk"
      raise "implicit BPS evaluation needs an implicit residue disk"
    if !implicit_disk.certificate.verified?
      raise "implicit BPS residue disk is uncertified"
    if implicit_disk.prime != local_map.rational_prime
      raise "implicit BPS local data changes the prime"
    if implicit_disk.prime == 2
      raise "implicit BPS line evaluation currently needs an odd prime"
    functions = function_data.function_components
    nested_bases = local_map.source.component_bases
    nested_maps = local_map.local_maps
    if functions.size != nested_bases.size
      raise "implicit BPS component count mismatch"
    coordinates = implicit_disk.center_coordinates
    solved = implicit_disk.solved_coordinate_index
    coefficient_coordinates = [0, 0, 0]
    coefficient_coordinates[solved] = 1
    prime_power = (
      implicit_disk.prime**implicit_disk.solved_valuation)
    leading_unit = implicit_disk.solved_unit_residue
    vector = []
    square_classes = []
    flat_index = 0
    component_index = 0
    while component_index < functions.size
      function = functions[component_index]
      bases = nested_bases[component_index]
      basis_index = 0
      while basis_index < bases.size
        if flat_index >= nested_maps.size
          raise "implicit BPS evaluation lost a local factor"
        basis = bases[basis_index]
        numerator = (
          PlaneQuarticBPSGoodReductionLocalArithmetic.line_value(
            function, basis,
            function.numerator_coefficients,
            coordinates))
        denominator_at_center = (
          PlaneQuarticBPSGoodReductionLocalArithmetic.line_value(
            function, basis,
            function.denominator_coefficients,
            coordinates))
        if !denominator_at_center.zero?
          raise "implicit BPS denominator does not vanish at the center"
        denominator_coefficient = (
          PlaneQuarticBPSGoodReductionLocalArithmetic.line_value(
            function, basis,
            function.denominator_coefficients,
            coefficient_coordinates))
        if denominator_coefficient.zero?
          raise "implicit BPS solved coordinate is absent from denominator"
        coordinate_index = 0
        while coordinate_index < coordinates.size
          if coordinate_index != solved
            probe = [0, 0, 0]
            probe[coordinate_index] = 1
            other_coefficient = (
              PlaneQuarticBPSGoodReductionLocalArithmetic.line_value(
                function, basis,
                function.denominator_coefficients,
                probe))
            if !other_coefficient.zero?
              raise "implicit BPS denominator is not the solved coordinate"
          coordinate_index += 1
        denominator_representative = (
          denominator_coefficient *
          prime_power * leading_unit)
        ratio = numerator / denominator_representative

        maps = nested_maps[flat_index]
        maps.each -> (field_map)
          prime = field_map.prime_ideal
          reducer = NumberFieldLocalResidueReduction.new(
            prime)
          numerator_residue = reducer.reduction_allow_zero(
            numerator)
          if prime.residue_field.zero?(numerator_residue)
            raise "implicit BPS numerator is not a local unit"
          coordinate_index = 0
          while coordinate_index < coordinates.size
            coefficient = (
              PlaneQuarticBPSGoodReductionLocalArithmetic.arithmetic_value(
                basis,
                function.numerator_coefficients[
                  coordinate_index]))
            reducer.reduction_allow_zero(coefficient)
            coordinate_index += 1
          denominator_residue = reducer.reduction_allow_zero(
            denominator_coefficient)
          if prime.residue_field.zero?(denominator_residue)
            raise "implicit BPS denominator coefficient is not a local unit"
          square_class = prime.local_square_class(ratio)
          square_classes.push(square_class)
          square_class.vector.each -> vector.push(item)
        flat_index += 1
        basis_index += 1
      component_index += 1
    if flat_index != nested_maps.size
      raise "implicit BPS evaluation has unused local factors"
    F2LinearAlgebra.validate_vector(
      vector, local_map.target_dimension)
    [vector, square_classes]


+ PlaneQuarticBPSImplicitDiskValueCertificate
  -> new(@value)
    @verified_cache = nil

  -> theorem
    "stable implicit-coordinate leading data determines the BPS square class throughout the residue disk"

  -> theorem_reference
    "odd local square theorem, p-adic implicit function theorem, and Bruin-Poonen-Stoll sections 6 and 11"

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
    expected = "PlaneQuarticBPSImplicitDiskValue"
    return false if @value.class_name != expected
    data = @value.function_data
    return false if data.class_name != "PlaneQuarticBPSFunctionData"
    return false if !data.certificate.verified?
    local_map = @value.local_map
    return false if local_map.class_name != "EtaleProductOddLocalSquareClassMap"
    return false if !local_map.certificate.verified?
    disk = @value.implicit_disk
    return false if disk.class_name != "PadicCurveImplicitResidueDisk"
    return false if !disk.certificate.verified?
    return false if disk.curve != data.curve
    return false if disk.prime != local_map.rational_prime
    compatible = PlaneQuarticBPSPointDifferenceArithmetic.same_component_polynomials?(
      data, local_map.source)
    return false if !compatible
    replay = PlaneQuarticBPSImplicitDiskArithmetic.value_data(
      data, local_map, disk)
    return false if !F2LinearAlgebra.same_vector?(
      replay[0], @value.vector)
    supplied = @value.square_classes
    return false if replay[1].size != supplied.size
    index = 0
    while index < supplied.size
      return false if !supplied[index].certificate.verified?
      return false if !replay[1][index].certificate.verified?
      return false if (
        supplied[index].prime_ideal !=
        replay[1][index].prime_ideal)
      return false if (
        supplied[index].value != replay[1][index].value)
      return false if !F2LinearAlgebra.same_vector?(
        supplied[index].vector,
        replay[1][index].vector)
      index += 1
    true

  -> certified?
    verified?

  -> proof_kind
    :trusted_implicit_bps_disk_with_exact_local_square_classes

  -> kernel_checked?
    false

  -> arithmetic_replay_checked?
    true

  -> local_descent_constancy_checked?
    verified?


+ PlaneQuarticBPSImplicitDiskValue
  -> new(@function_data, @local_map, @implicit_disk)
    result = PlaneQuarticBPSImplicitDiskArithmetic.value_data(
      @function_data, @local_map, @implicit_disk)
    @vector = result[0]
    @square_classes = result[1]
    @certificate_cache = PlaneQuarticBPSImplicitDiskValueCertificate.new(
      self)
    if !@certificate_cache.verified?
      raise "implicit BPS disk value failed certification"

  -> function_data
    @function_data

  -> local_map
    @local_map

  -> implicit_disk
    @implicit_disk

  -> vector
    F2LinearAlgebra.copy_vector(@vector)

  -> square_classes
    out = []
    @square_classes.each -> out.push(item)
    out

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?


+ PlaneQuarticBPSFunctionData
  -> certify_implicit_disk_value(local_map, implicit_disk)
    PlaneQuarticBPSImplicitDiskValue.new(
      self, local_map, implicit_disk)


+ PlaneQuarticBPSImplicitLocalImageCertificate
  -> new(@image)
    @verified_cache = nil

  -> theorem
    "point differences between certified implicit disks lie in the BPS local Jacobian image"

  -> theorem_reference
    "p-adic implicit function theorem and Bruin-Poonen-Stoll sections 6 and 11"

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
    expected = "PlaneQuarticBPSImplicitLocalImage"
    return false if @image.class_name != expected
    data = @image.function_data
    return false if data.class_name != "PlaneQuarticBPSFunctionData"
    return false if !data.certificate.verified?
    local_map = @image.local_map
    return false if local_map.class_name != "EtaleProductOddLocalSquareClassMap"
    return false if !local_map.certificate.verified?
    disks = @image.implicit_disks
    values = @image.disk_values
    return false if disks.size == 0 || disks.size != values.size
    index = 0
    while index < disks.size
      disk = disks[index]
      value = values[index]
      return false if disk.class_name != "PadicCurveImplicitResidueDisk"
      return false if !disk.certificate.verified?
      return false if disk.curve != data.curve
      return false if disk.prime != local_map.rational_prime
      return false if value.class_name != "PlaneQuarticBPSImplicitDiskValue"
      return false if !value.certificate.verified?
      return false if value.function_data != data
      return false if value.local_map != local_map
      return false if value.implicit_disk != disk
      index += 1

    expected_vectors = []
    base = values[0].vector
    values.each -> (value)
      expected_vectors.push(
        PlaneQuarticBPSGoodReductionLocalArithmetic.difference(
          value.vector, base))
    return false if !F2LinearAlgebra.same_matrix?(
      expected_vectors, @image.vectors)
    span = @image.span_certificate
    return false if !span.verified?
    return false if span.width != local_map.target_dimension
    return false if !F2LinearAlgebra.same_matrix?(
      span.matrix, expected_vectors)
    return false if !span.source_right_hand_side.all? ->
      item == 0
    return false if span.rank != @image.dimension
    true

  -> certified?
    verified?

  -> proof_kind
    :trusted_bps_implicit_disk_exact_span

  -> kernel_checked?
    false

  -> arithmetic_replay_checked?
    true

  -> local_descent_constancy_checked?
    verified?

  -> lower_bound_checked?
    verified?

  -> complete_local_image_checked?
    false


+ PlaneQuarticBPSImplicitLocalImage
  -> new(@function_data, @local_map, implicit_disks)
    if @function_data.class_name != "PlaneQuarticBPSFunctionData"
      raise "implicit BPS local image needs function data"
    if !@function_data.certificate.verified?
      raise "implicit BPS function data is uncertified"
    if @local_map.class_name != "EtaleProductOddLocalSquareClassMap"
      raise "implicit BPS local image needs an odd localization map"
    if !@local_map.certificate.verified?
      raise "implicit BPS localization map is uncertified"
    if (implicit_disks.class_name != "Array" ||
        implicit_disks.size == 0)
      raise "implicit BPS local image needs residue disks"
    @implicit_disks = []
    @disk_values = []
    implicit_disks.each -> (disk)
      if disk.class_name != "PadicCurveImplicitResidueDisk"
        raise "implicit BPS local image contains a non-implicit disk"
      if disk.curve != @function_data.curve
        raise "implicit BPS local image changes the curve"
      if disk.prime != @local_map.rational_prime
        raise "implicit BPS local image changes the prime"
      @implicit_disks.push(disk)
      @disk_values.push(
        @function_data.certify_implicit_disk_value(
          @local_map, disk))
    @vectors = []
    base = @disk_values[0].vector
    @disk_values.each -> (value)
      @vectors.push(
        PlaneQuarticBPSGoodReductionLocalArithmetic.difference(
          value.vector, base))
    system = F2LinearSystem.new(
      @local_map.target_dimension)
    @vectors.each -> (vector)
      system.add_equation(
        vector, 0,
        "implicit residue-disk point difference")
    @span_certificate = system.certificate
    @certificate_cache = PlaneQuarticBPSImplicitLocalImageCertificate.new(
      self)
    if !@certificate_cache.verified?
      raise "implicit BPS local image failed certification"

  -> function_data
    @function_data

  -> local_map
    @local_map

  -> rational_prime
    @local_map.rational_prime

  -> implicit_disks
    out = []
    @implicit_disks.each -> out.push(item)
    out

  -> disk_values
    out = []
    @disk_values.each -> out.push(item)
    out

  -> vectors
    F2LinearAlgebra.copy_matrix(@vectors)

  -> target_dimension
    @local_map.target_dimension

  -> span_certificate
    @span_certificate

  -> dimension
    @span_certificate.rank

  -> image_basis
    @span_certificate.rref.copy(
      0, @span_certificate.rank)

  -> lower_bound_only?
    true

  -> complete?
    false

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?


+ PlaneQuarticBPSFunctionData
  -> implicit_disk_local_image(local_map, implicit_disks)
    PlaneQuarticBPSImplicitLocalImage.new(
      self, local_map, implicit_disks)


+ PlaneQuarticBPSHenselDiskArithmetic
  -> .supported_local_map?(local_map)
    map_class = local_map.class_name
    if local_map.rational_prime == 2
      return map_class == "EtaleProductDyadicLocalSquareClassMap"
    map_class == "EtaleProductOddLocalSquareClassMap"

  -> .certify_relative_variation(prime_ideal,
                                  relative_variation)
    return true if relative_variation.zero?
    if prime_ideal.rational_prime == 2
      required_valuation = (
        2*prime_ideal.ramification_index + 1)
      actual_valuation = prime_ideal.local_valuation(
        relative_variation)
      if actual_valuation < required_valuation
        raise ("BPS dyadic line variation has valuation " +
               actual_valuation.to_s + ", below required " +
               required_valuation.to_s)
      return true
    reducer = NumberFieldLocalResidueReduction.new(
      prime_ideal)
    residue = reducer.reduction_allow_zero(
      relative_variation)
    if !prime_ideal.residue_field.zero?(residue)
      raise "BPS line square class varies on the Hensel disk"
    true

  -> .line_value_and_stability(
       function, basis, coefficients,
       disk, prime_ideal)
    center = disk.center_coordinates
    value = PlaneQuarticBPSGoodReductionLocalArithmetic.line_value(
      function, basis, coefficients, center)
    if value.zero?
      raise "BPS Hensel-disk line vanishes at the cell center"
    disk.local_coordinate_indices.each -> (coordinate_index)
      coefficient = (
        PlaneQuarticBPSGoodReductionLocalArithmetic.arithmetic_value(
          basis, coefficients[coordinate_index]))
      relative_variation = (
        coefficient*disk.step / value)
      PlaneQuarticBPSHenselDiskArithmetic.certify_relative_variation(
        prime_ideal, relative_variation)
    value

  -> .line_value_data(function_data, local_map, disk)
    if disk.class_name != "PadicPlaneCurveHenselDisk"
      raise "BPS cell evaluation needs a p-adic Hensel disk"
    if !disk.certificate.verified?
      raise "BPS Hensel disk is uncertified"
    if disk.curve != function_data.curve
      raise "BPS Hensel disk changes the curve"
    if disk.prime != local_map.rational_prime
      raise "BPS Hensel disk changes the prime"
    if !PlaneQuarticBPSHenselDiskArithmetic.supported_local_map?(
         local_map)
      raise "BPS Hensel-disk evaluation needs a matching product localization map"
    functions = function_data.function_components
    nested_bases = local_map.source.component_bases
    nested_maps = local_map.local_maps
    if functions.size != nested_bases.size
      raise "BPS Hensel-disk component count mismatch"
    out = []
    flat_index = 0
    component_index = 0
    while component_index < functions.size
      function = functions[component_index]
      bases = nested_bases[component_index]
      basis_index = 0
      while basis_index < bases.size
        if flat_index >= nested_maps.size
          raise "BPS Hensel-disk evaluation lost a local factor"
        basis = bases[basis_index]
        maps = nested_maps[flat_index]
        maps.each -> (field_map)
          prime = field_map.prime_ideal
          numerator = (
            PlaneQuarticBPSHenselDiskArithmetic.line_value_and_stability(
              function, basis,
              function.numerator_coefficients,
              disk, prime))
          denominator = (
            PlaneQuarticBPSHenselDiskArithmetic.line_value_and_stability(
              function, basis,
              function.denominator_coefficients,
              disk, prime))
          out.push([prime, numerator, denominator])
        flat_index += 1
        basis_index += 1
      component_index += 1
    if flat_index != nested_maps.size
      raise "BPS Hensel-disk evaluation has unused local factors"
    out

  -> .stability_checked?(function_data, local_map, disk)
    begin
      PlaneQuarticBPSHenselDiskArithmetic.line_value_data(
        function_data, local_map, disk)
      return true
    rescue error
      return false

  -> .value_data(function_data, local_map, disk)
    line_values = (
      PlaneQuarticBPSHenselDiskArithmetic.line_value_data(
        function_data, local_map, disk))
    vector = []
    square_classes = []
    line_values.each -> (entry)
      square_class = entry[0].local_square_class(
        entry[1] / entry[2])
      square_classes.push(square_class)
      square_class.vector.each -> vector.push(item)
    F2LinearAlgebra.validate_vector(
      vector, local_map.target_dimension)
    [vector, square_classes]


+ PlaneQuarticBPSHenselDiskValueCertificate
  -> new(@value)
    @verified_cache = nil

  -> theorem
    "sufficiently deep linear variations preserve local square classes on a p-adic Hensel disk"

  -> theorem_reference
    "multivariate Hensel lemma, odd and dyadic local square theorems, and Bruin-Poonen-Stoll sections 6 and 11"

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
    expected = "PlaneQuarticBPSHenselDiskValue"
    return false if @value.class_name != expected
    data = @value.function_data
    return false if data.class_name != "PlaneQuarticBPSFunctionData"
    return false if !data.certificate.verified?
    local_map = @value.local_map
    supported = (
      PlaneQuarticBPSHenselDiskArithmetic.supported_local_map?(
        local_map))
    return false if !supported
    return false if !local_map.certificate.verified?
    disk = @value.disk
    return false if disk.class_name != "PadicPlaneCurveHenselDisk"
    return false if !disk.certificate.verified?
    return false if disk.curve != data.curve
    return false if disk.prime != local_map.rational_prime
    compatible = PlaneQuarticBPSPointDifferenceArithmetic.same_component_polynomials?(
      data, local_map.source)
    return false if !compatible
    replay = PlaneQuarticBPSHenselDiskArithmetic.value_data(
      data, local_map, disk)
    return false if !F2LinearAlgebra.same_vector?(
      replay[0], @value.vector)
    supplied = @value.square_classes
    return false if replay[1].size != supplied.size
    index = 0
    while index < supplied.size
      return false if !supplied[index].certificate.verified?
      return false if !replay[1][index].certificate.verified?
      return false if supplied[index].prime_ideal != (
        replay[1][index].prime_ideal)
      return false if supplied[index].value != (
        replay[1][index].value)
      return false if !F2LinearAlgebra.same_vector?(
        supplied[index].vector,
        replay[1][index].vector)
      index += 1
    true

  -> certified?
    verified?

  -> proof_kind
    :trusted_bps_hensel_disk_with_exact_local_replay

  -> kernel_checked?
    false

  -> arithmetic_replay_checked?
    true

  -> local_descent_constancy_checked?
    verified?


+ PlaneQuarticBPSHenselDiskValue
  -> new(@function_data, @local_map, @disk)
    result = PlaneQuarticBPSHenselDiskArithmetic.value_data(
      @function_data, @local_map, @disk)
    @vector = result[0]
    @square_classes = result[1]
    @certificate_cache = (
      PlaneQuarticBPSHenselDiskValueCertificate.new(self))
    if !@certificate_cache.verified?
      raise "BPS Hensel-disk value failed certification"

  -> function_data
    @function_data

  -> local_map
    @local_map

  -> disk
    @disk

  -> vector
    F2LinearAlgebra.copy_vector(@vector)

  -> square_classes
    out = []
    @square_classes.each -> out.push(item)
    out

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?


+ PlaneQuarticBPSHenselLocalImageCertificate
  -> new(@image)
    @verified_cache = nil

  -> theorem
    "point differences between certified Hensel disks lie in the BPS local Jacobian image"

  -> theorem_reference
    "multivariate Hensel lemma, local square theorems, and Bruin-Poonen-Stoll sections 6 and 11"

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
    expected = "PlaneQuarticBPSHenselLocalImage"
    return false if @image.class_name != expected
    data = @image.function_data
    return false if !data.certificate.verified?
    local_map = @image.local_map
    return false if !local_map.certificate.verified?
    disks = @image.disks
    values = @image.disk_values
    return false if disks.size == 0 || disks.size != values.size
    index = 0
    while index < disks.size
      disk = disks[index]
      value = values[index]
      return false if disk.class_name != "PadicPlaneCurveHenselDisk"
      return false if !disk.certificate.verified?
      return false if disk.curve != data.curve
      return false if disk.prime != local_map.rational_prime
      return false if value.class_name != "PlaneQuarticBPSHenselDiskValue"
      return false if !value.certificate.verified?
      return false if value.function_data != data
      return false if value.local_map != local_map
      return false if value.disk != disk
      index += 1
    expected_vectors = []
    base = values[0].vector
    values.each -> (value)
      expected_vectors.push(
        PlaneQuarticBPSGoodReductionLocalArithmetic.difference(
          value.vector, base))
    return false if !F2LinearAlgebra.same_matrix?(
      expected_vectors, @image.vectors)
    span = @image.span_certificate
    return false if !span.verified?
    return false if span.width != local_map.target_dimension
    return false if !F2LinearAlgebra.same_matrix?(
      span.matrix, expected_vectors)
    return false if !span.source_right_hand_side.all? ->
      item == 0
    span.rank == @image.dimension

  -> certified?
    verified?

  -> proof_kind
    :trusted_bps_hensel_disk_exact_span

  -> kernel_checked?
    false

  -> arithmetic_replay_checked?
    true

  -> lower_bound_checked?
    verified?

  -> complete_local_image_checked?
    false


+ PlaneQuarticBPSHenselLocalImage
  -> new(@function_data, @local_map, disks)
    if @function_data.class_name != "PlaneQuarticBPSFunctionData"
      raise "BPS Hensel local image needs function data"
    if !@function_data.certificate.verified?
      raise "BPS Hensel function data is uncertified"
    if !PlaneQuarticBPSHenselDiskArithmetic.supported_local_map?(
         @local_map)
      raise "BPS Hensel local image needs a matching product localization map"
    if !@local_map.certificate.verified?
      raise "BPS Hensel localization map is uncertified"
    if disks.class_name != "Array" || disks.size == 0
      raise "BPS Hensel local image needs disks"
    @disks = []
    @disk_values = []
    disks.each -> (disk)
      if disk.class_name != "PadicPlaneCurveHenselDisk"
        raise "BPS Hensel local image contains a non-Hensel disk"
      if disk.curve != @function_data.curve
        raise "BPS Hensel local image changes the curve"
      if disk.prime != @local_map.rational_prime
        raise "BPS Hensel local image changes the prime"
      @disks.push(disk)
      @disk_values.push(
        PlaneQuarticBPSHenselDiskValue.new(
          @function_data, @local_map, disk))
    @vectors = []
    base = @disk_values[0].vector
    @disk_values.each -> (value)
      @vectors.push(
        PlaneQuarticBPSGoodReductionLocalArithmetic.difference(
          value.vector, base))
    system = F2LinearSystem.new(
      @local_map.target_dimension)
    @vectors.each -> (vector)
      system.add_equation(
        vector, 0,
        "resolved Hensel-disk point difference")
    @span_certificate = system.certificate
    @certificate_cache = (
      PlaneQuarticBPSHenselLocalImageCertificate.new(self))
    if !@certificate_cache.verified?
      raise "BPS Hensel local image failed certification"

  -> function_data
    @function_data

  -> local_map
    @local_map

  -> rational_prime
    @local_map.rational_prime

  -> disks
    out = []
    @disks.each -> out.push(item)
    out

  -> disk_values
    out = []
    @disk_values.each -> out.push(item)
    out

  -> vectors
    F2LinearAlgebra.copy_matrix(@vectors)

  -> target_dimension
    @local_map.target_dimension

  -> span_certificate
    @span_certificate

  -> dimension
    @span_certificate.rank

  -> image_basis
    @span_certificate.rref.copy(
      0, @span_certificate.rank)

  -> lower_bound_only?
    true

  -> complete?
    false

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?


+ PlaneQuarticBPSFunctionData
  -> hensel_disk_local_image(local_map, disks)
    PlaneQuarticBPSHenselLocalImage.new(
      self, local_map, disks)


+ PlaneQuarticBPSLocalDiskImageCertificate
  -> new(@image)
    @verified_cache = nil

  -> theorem
    "point differences between certified p-adic curve disks lie in the BPS local Jacobian image"

  -> theorem_reference
    "p-adic implicit and multivariate Hensel theorems, local square theorems, and Bruin-Poonen-Stoll sections 6 and 11"

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
    expected = "PlaneQuarticBPSLocalDiskImage"
    return false if @image.class_name != expected
    data = @image.function_data
    return false if data.class_name != "PlaneQuarticBPSFunctionData"
    return false if !data.certificate.verified?
    local_map = @image.local_map
    supported = (
      PlaneQuarticBPSHenselDiskArithmetic.supported_local_map?(
        local_map))
    return false if !supported
    return false if !local_map.certificate.verified?
    entries = @image.disk_entries
    return false if entries.size == 0
    entries.each -> (entry)
      return false if entry.size != 2
      disk = entry[0]
      value = entry[1]
      disk_kind = disk.class_name
      if disk_kind == "PadicCurveImplicitResidueDisk"
        return false if value.class_name != (
          "PlaneQuarticBPSImplicitDiskValue")
        return false if value.implicit_disk != disk
      elsif disk_kind == "PadicPlaneCurveHenselDisk"
        return false if value.class_name != (
          "PlaneQuarticBPSHenselDiskValue")
        return false if value.disk != disk
      else
        return false
      return false if !disk.certificate.verified?
      return false if !value.certificate.verified?
      return false if disk.curve != data.curve
      return false if disk.prime != local_map.rational_prime
      return false if value.function_data != data
      return false if value.local_map != local_map

    expected_vectors = []
    base = entries[0][1].vector
    entries.each -> (entry)
      expected_vectors.push(
        PlaneQuarticBPSGoodReductionLocalArithmetic.difference(
          entry[1].vector, base))
    return false if !F2LinearAlgebra.same_matrix?(
      expected_vectors, @image.vectors)
    span = @image.span_certificate
    return false if !span.verified?
    return false if span.width != local_map.target_dimension
    return false if !F2LinearAlgebra.same_matrix?(
      span.matrix, expected_vectors)
    return false if !span.source_right_hand_side.all? ->
      item == 0
    return false if span.rank != @image.dimension
    dimension_certificate = @image.dimension_certificate
    if dimension_certificate != nil
      expected = "PlaneQuarticLocalThetaDimension"
      return false if dimension_certificate.class_name != expected
      return false if !dimension_certificate.certificate.verified?
      return false if dimension_certificate.function_data != data
      return false if dimension_certificate.local_map != local_map
      return false if @image.dimension > (
        dimension_certificate.dimension_upper_bound)
    true

  -> certified?
    verified?

  -> proof_kind
    :trusted_bps_mixed_local_disk_exact_span

  -> kernel_checked?
    false

  -> arithmetic_replay_checked?
    true

  -> lower_bound_checked?
    verified?

  -> complete_local_image_checked?
    return false if !verified?
    bound = @image.dimension_certificate
    return false if bound == nil
    @image.dimension == bound.dimension_upper_bound


+ PlaneQuarticBPSLocalDiskImage
  -> new(@function_data, @local_map, disks,
         @dimension_certificate = nil)
    if @function_data.class_name != "PlaneQuarticBPSFunctionData"
      raise "BPS local disk image needs function data"
    if !@function_data.certificate.verified?
      raise "BPS local disk function data is uncertified"
    if !PlaneQuarticBPSHenselDiskArithmetic.supported_local_map?(
         @local_map)
      raise "BPS local disk image needs a matching product localization map"
    if !@local_map.certificate.verified?
      raise "BPS local disk localization map is uncertified"
    if disks.class_name != "Array" || disks.size == 0
      raise "BPS local disk image needs disks"
    if @dimension_certificate != nil
      expected = "PlaneQuarticLocalThetaDimension"
      if @dimension_certificate.class_name != expected
        raise "unsupported BPS local disk dimension certificate"
      if !@dimension_certificate.certificate.verified?
        raise "BPS local disk dimension bound is uncertified"
      if (@dimension_certificate.function_data != @function_data ||
          @dimension_certificate.local_map != @local_map)
        raise "BPS local disk dimension bound changes the problem"
    @disk_entries = []
    disks.each -> (disk)
      value = nil
      kind = disk.class_name
      if kind == "PadicCurveImplicitResidueDisk"
        value = @function_data.certify_implicit_disk_value(
          @local_map, disk)
      elsif kind == "PadicPlaneCurveHenselDisk"
        value = PlaneQuarticBPSHenselDiskValue.new(
          @function_data, @local_map, disk)
      else
        raise "unsupported BPS local disk kind"
      @disk_entries.push([disk, value])
    @vectors = []
    base = @disk_entries[0][1].vector
    @disk_entries.each -> (entry)
      @vectors.push(
        PlaneQuarticBPSGoodReductionLocalArithmetic.difference(
          entry[1].vector, base))
    system = F2LinearSystem.new(
      @local_map.target_dimension)
    @vectors.each -> (vector)
      system.add_equation(
        vector, 0,
        "certified p-adic disk point difference")
    @span_certificate = system.certificate
    @certificate_cache = (
      PlaneQuarticBPSLocalDiskImageCertificate.new(self))
    if !@certificate_cache.verified?
      raise "BPS local disk image failed certification"

  -> function_data
    @function_data

  -> local_map
    @local_map

  -> rational_prime
    @local_map.rational_prime

  -> dimension_certificate
    @dimension_certificate

  -> disk_entries
    out = []
    @disk_entries.each -> (entry)
      out.push([entry[0], entry[1]])
    out

  -> disks
    out = []
    @disk_entries.each -> (entry)
      out.push(entry[0])
    out

  -> disk_values
    out = []
    @disk_entries.each -> (entry)
      out.push(entry[1])
    out

  -> vectors
    F2LinearAlgebra.copy_matrix(@vectors)

  -> target_dimension
    @local_map.target_dimension

  -> span_certificate
    @span_certificate

  -> dimension
    @span_certificate.rank

  -> image_basis
    @span_certificate.rref.copy(
      0, @span_certificate.rank)

  -> lower_bound_only?
    !complete?

  -> complete?
    certificate.complete_local_image_checked?

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?


+ PlaneQuarticBPSFunctionData
  -> local_disk_image(local_map, disks,
                      dimension_certificate = nil)
    PlaneQuarticBPSLocalDiskImage.new(
      self, local_map, disks,
      dimension_certificate)


+ PlaneQuarticBPSGoodReductionLocalImageCertificate
  -> new(@image)
    @verified_cache = nil

  -> theorem
    "at odd good reduction, clean residue-disk point differences spanning the Frobenius-fixed 2-torsion dimension give the complete BPS local image"

  -> theorem_reference
    "good-reduction formal-group divisibility, Kummer theory, and Bruin-Poonen-Stoll sections 6 and 11"

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
    expected = "PlaneQuarticBPSGoodReductionLocalImage"
    return false if @image.class_name != expected
    data = @image.function_data
    return false if data.class_name != "PlaneQuarticBPSFunctionData"
    return false if !data.certificate.verified?
    cover = @image.cover
    return false if cover.class_name != "PadicCurveResidueDiskCover"
    return false if !cover.certificate.verified?
    return false if cover.curve != data.curve
    prime = cover.prime
    return false if prime == 2 || !prime.prime?

    local_map = @image.local_map
    return false if local_map.class_name != "EtaleProductOddLocalSquareClassMap"
    return false if !local_map.certificate.verified?
    return false if local_map.rational_prime != prime
    compatible = PlaneQuarticBPSPointDifferenceArithmetic.same_component_polynomials?(
      data, local_map.source)
    return false if !compatible

    fiber = @image.theta_fiber
    return false if fiber.class_name != "PlaneQuarticFiniteThetaFiber"
    return false if !fiber.certificate.verified?
    return false if fiber.prime != prime
    return false if fiber.scheme_certificate != data.setup.bitangent_scheme_certificate
    return false if !fiber.good_reduction?
    transformation = fiber.theta_permutation.transformation
    fixed = transformation.fixed_subspace_certificate
    return false if !fixed.verified?
    return false if fixed.kernel_dimension != @image.expected_dimension

    entries = @image.disk_vectors
    disks = cover.disks
    return false if entries.size != disks.size
    clean = []
    index = 0
    while index < disks.size
      entry = entries[index]
      return false if entry.size != 2
      return false if entry[0] != disks[index]
      replay = PlaneQuarticBPSGoodReductionLocalArithmetic.disk_vector(
        data, local_map, disks[index])
      if replay == nil
        return false if entry[1] != nil
      else
        return false if entry[1] == nil
        return false if !F2LinearAlgebra.same_vector?(
          replay, entry[1])
        clean.push(entry)
      index += 1
    return false if clean.size == 0
    return false if clean[0][0] != @image.base_disk

    expected_vectors = []
    base = clean[0][1]
    clean.each -> (entry)
      expected_vectors.push(
        PlaneQuarticBPSGoodReductionLocalArithmetic.difference(
          entry[1], base))
    return false if !F2LinearAlgebra.same_matrix?(
      expected_vectors, @image.vectors)

    span = @image.span_certificate
    return false if !span.verified?
    return false if span.width != local_map.target_dimension
    return false if !F2LinearAlgebra.same_matrix?(
      span.matrix, expected_vectors)
    zero_right_hand_side = span.source_right_hand_side.all? ->
      item == 0
    return false if !zero_right_hand_side
    return false if span.rank != @image.dimension
    @image.dimension <= @image.expected_dimension

  -> certified?
    verified?

  -> proof_kind
    :trusted_good_reduction_bps_with_exact_residue_replay

  -> kernel_checked?
    false

  -> arithmetic_replay_checked?
    true

  -> finite_special_fiber_replayed?
    true

  -> frobenius_fixed_dimension_replayed?
    true

  -> local_descent_constancy_checked?
    true

  -> complete_local_image_checked?
    verified? && @image.dimension == @image.expected_dimension


+ PlaneQuarticBPSGoodReductionLocalImage
  -> new(@function_data, @local_map, @theta_fiber, @cover)
    if @function_data.class_name != "PlaneQuarticBPSFunctionData"
      raise "good-reduction BPS local image needs function data"
    if !@function_data.certificate.verified?
      raise "good-reduction BPS function data is uncertified"
    if @local_map.class_name != "EtaleProductOddLocalSquareClassMap"
      raise "good-reduction BPS local image needs an odd localization map"
    if !@local_map.certificate.verified?
      raise "good-reduction BPS localization map is uncertified"
    if @theta_fiber.class_name != "PlaneQuarticFiniteThetaFiber"
      raise "good-reduction BPS local image needs a finite theta fiber"
    if !@theta_fiber.certificate.verified?
      raise "good-reduction BPS theta fiber is uncertified"
    if @cover.class_name != "PadicCurveResidueDiskCover"
      raise "good-reduction BPS local image needs a residue-disk cover"
    if !@cover.certificate.verified?
      raise "good-reduction BPS residue-disk cover is uncertified"
    if @cover.prime != @local_map.rational_prime
      raise "good-reduction BPS local data changes the prime"
    if @cover.prime != @theta_fiber.prime
      raise "good-reduction BPS theta fiber changes the prime"
    if @cover.prime == 2
      raise "good-reduction BPS completion needs an odd prime"
    compatible = PlaneQuarticBPSPointDifferenceArithmetic.same_component_polynomials?(
      @function_data, @local_map.source)
    if !compatible
      raise "good-reduction BPS localization changes etale components"

    @disk_vectors = []
    clean = []
    @cover.disks.each -> (disk)
      vector = PlaneQuarticBPSGoodReductionLocalArithmetic.disk_vector(
        @function_data, @local_map, disk)
      entry = [disk, vector]
      @disk_vectors.push(entry)
      clean.push(entry) if vector != nil
    if clean.size == 0
      raise "no residue disk avoids every BPS zero and pole"
    @base_disk = clean[0][0]
    base_vector = clean[0][1]
    @vectors = []
    clean.each -> (entry)
      @vectors.push(
        PlaneQuarticBPSGoodReductionLocalArithmetic.difference(
          entry[1], base_vector))
    system = F2LinearSystem.new(
      @local_map.target_dimension)
    @vectors.each -> (vector)
      system.add_equation(
        vector, 0,
        "clean residue-disk point difference")
    @span_certificate = system.certificate
    transformation = @theta_fiber.theta_permutation.transformation
    @expected_dimension = transformation.fixed_dimension
    @certificate_cache = PlaneQuarticBPSGoodReductionLocalImageCertificate.new(
      self)
    if !@certificate_cache.verified?
      raise "good-reduction BPS local image failed certification"

  -> function_data
    @function_data

  -> local_map
    @local_map

  -> theta_fiber
    @theta_fiber

  -> cover
    @cover

  -> rational_prime
    @cover.prime

  -> disk_vectors
    out = []
    @disk_vectors.each -> (entry)
      vector = entry[1]
      vector = F2LinearAlgebra.copy_vector(vector) if vector != nil
      out.push([entry[0], vector])
    out

  -> clean_disk_count
    count = 0
    @disk_vectors.each ->
      count += 1 if item[1] != nil
    count

  -> base_disk
    @base_disk

  -> vectors
    F2LinearAlgebra.copy_matrix(@vectors)

  -> target_dimension
    @local_map.target_dimension

  -> span_certificate
    @span_certificate

  -> dimension
    @span_certificate.rank

  -> expected_dimension
    @expected_dimension

  -> image_basis
    @span_certificate.rref.copy(
      0, @span_certificate.rank)

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> complete?
    certificate.complete_local_image_checked?

  -> lower_bound_only?
    !complete?

  -> local_descent_image_certified?
    complete?


+ PadicCurveResidueDiskCover
  -> bps_local_image(function_data, local_map, theta_fiber)
    PlaneQuarticBPSGoodReductionLocalImage.new(
      function_data, local_map, theta_fiber, self)


+ PlaneQuarticBPSFunctionData
  -> good_reduction_local_image(
       local_map, theta_fiber, precision = 20)
    cover = curve.p_adic_residue_disks(
      local_map.rational_prime, precision)
    cover.bps_local_image(
      self, local_map, theta_fiber)


# Even on a bad plane model, every smooth special-fiber point gives a
# nonempty p-adic disk. Point differences from the clean smooth disks are
# certified elements of the local BPS image. At an odd prime, the universal
# bound dim J(Q_p)/2J(Q_p) <= 2g makes this a complete image if the span
# reaches 2g; otherwise it remains an honest lower bound.
+ PlaneQuarticBPSSmoothLocusLocalImageCertificate
  -> new(@image)
    @verified_cache = nil

  -> theorem
    "clean smooth-locus point differences give a BPS local-image lower bound, complete when they attain the odd-prime 2g bound"

  -> theorem_reference
    "multivariate Hensel lifting, p-adic Lie-group multiplication by two, and Bruin-Poonen-Stoll sections 6 and 11"

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
    expected = "PlaneQuarticBPSSmoothLocusLocalImage"
    return false if @image.class_name != expected
    data = @image.function_data
    return false if data.class_name != "PlaneQuarticBPSFunctionData"
    return false if !data.certificate.verified?
    cover = @image.cover
    return false if cover.class_name != "PadicCurveSmoothResidueDiskCover"
    return false if !cover.certificate.verified?
    return false if cover.curve != data.curve
    prime = cover.prime
    return false if prime == 2 || !prime.prime?

    local_map = @image.local_map
    return false if local_map.class_name != "EtaleProductOddLocalSquareClassMap"
    return false if !local_map.certificate.verified?
    return false if local_map.rational_prime != prime
    compatible = PlaneQuarticBPSPointDifferenceArithmetic.same_component_polynomials?(
      data, local_map.source)
    return false if !compatible
    dimension_certificate = @image.dimension_certificate
    if dimension_certificate == nil
      return false if (
        @image.dimension_upper_bound != 2*data.curve.genus)
    else
      expected_bound = "PlaneQuarticCuspidalRegularModel"
      return false if dimension_certificate.class_name != expected_bound
      return false if !dimension_certificate.certificate.verified?
      return false if dimension_certificate.curve != data.curve
      return false if dimension_certificate.prime != prime
      return false if (
        dimension_certificate.dimension_upper_bound !=
        @image.dimension_upper_bound)

    entries = @image.disk_vectors
    disks = cover.disks
    return false if entries.size != disks.size
    clean = []
    index = 0
    while index < disks.size
      entry = entries[index]
      return false if entry.size != 2
      return false if entry[0] != disks[index]
      replay = PlaneQuarticBPSGoodReductionLocalArithmetic.disk_vector(
        data, local_map, disks[index])
      if replay == nil
        return false if entry[1] != nil
      else
        return false if entry[1] == nil
        return false if !F2LinearAlgebra.same_vector?(
          replay, entry[1])
        clean.push(entry)
      index += 1
    return false if clean.size == 0
    return false if clean[0][0] != @image.base_disk

    expected_vectors = []
    base = clean[0][1]
    clean.each -> (entry)
      expected_vectors.push(
        PlaneQuarticBPSGoodReductionLocalArithmetic.difference(
          entry[1], base))
    return false if !F2LinearAlgebra.same_matrix?(
      expected_vectors, @image.vectors)

    span = @image.span_certificate
    return false if !span.verified?
    return false if span.width != local_map.target_dimension
    return false if !F2LinearAlgebra.same_matrix?(
      span.matrix, expected_vectors)
    zero_right_hand_side = span.source_right_hand_side.all? ->
      item == 0
    return false if !zero_right_hand_side
    return false if span.rank != @image.dimension
    @image.dimension <= @image.dimension_upper_bound

  -> certified?
    verified?

  -> proof_kind
    :trusted_odd_local_2g_bound_with_exact_residue_replay

  -> kernel_checked?
    false

  -> arithmetic_replay_checked?
    true

  -> finite_smooth_locus_replayed?
    true

  -> local_descent_constancy_checked?
    true

  -> complete_local_image_checked?
    (verified? &&
     @image.dimension == @image.dimension_upper_bound)


+ PlaneQuarticBPSSmoothLocusLocalImage
  -> new(@function_data, @local_map, @cover,
         @dimension_certificate = nil)
    if @function_data.class_name != "PlaneQuarticBPSFunctionData"
      raise "smooth-locus BPS local image needs function data"
    if !@function_data.certificate.verified?
      raise "smooth-locus BPS function data is uncertified"
    if @local_map.class_name != "EtaleProductOddLocalSquareClassMap"
      raise "smooth-locus BPS local image needs an odd localization map"
    if !@local_map.certificate.verified?
      raise "smooth-locus BPS localization map is uncertified"
    if @cover.class_name != "PadicCurveSmoothResidueDiskCover"
      raise "smooth-locus BPS local image needs a smooth-locus cover"
    if !@cover.certificate.verified?
      raise "smooth-locus BPS residue disks are uncertified"
    if @cover.prime != @local_map.rational_prime
      raise "smooth-locus BPS local data changes the prime"
    if @cover.prime == 2
      raise "smooth-locus BPS 2g bound needs an odd prime"
    compatible = PlaneQuarticBPSPointDifferenceArithmetic.same_component_polynomials?(
      @function_data, @local_map.source)
    if !compatible
      raise "smooth-locus BPS localization changes etale components"
    if @dimension_certificate != nil
      expected_bound = "PlaneQuarticCuspidalRegularModel"
      if @dimension_certificate.class_name != expected_bound
        raise "unsupported smooth-locus local dimension certificate"
      if !@dimension_certificate.certificate.verified?
        raise "smooth-locus local dimension bound is uncertified"
      if (@dimension_certificate.curve != @function_data.curve ||
          @dimension_certificate.prime != @cover.prime)
        raise "smooth-locus local dimension bound changes the problem"

    @disk_vectors = []
    clean = []
    @cover.disks.each -> (disk)
      vector = PlaneQuarticBPSGoodReductionLocalArithmetic.disk_vector(
        @function_data, @local_map, disk)
      entry = [disk, vector]
      @disk_vectors.push(entry)
      clean.push(entry) if vector != nil
    if clean.size == 0
      raise "no smooth residue disk avoids every BPS zero and pole"
    @base_disk = clean[0][0]
    base_vector = clean[0][1]
    @vectors = []
    clean.each -> (entry)
      @vectors.push(
        PlaneQuarticBPSGoodReductionLocalArithmetic.difference(
          entry[1], base_vector))
    system = F2LinearSystem.new(
      @local_map.target_dimension)
    @vectors.each -> (vector)
      system.add_equation(
        vector, 0,
        "clean smooth-locus point difference")
    @span_certificate = system.certificate
    @dimension_upper_bound = 2*@function_data.curve.genus
    if @dimension_certificate != nil
      @dimension_upper_bound = (
        @dimension_certificate.dimension_upper_bound)
    @certificate_cache = PlaneQuarticBPSSmoothLocusLocalImageCertificate.new(
      self)
    if !@certificate_cache.verified?
      raise "smooth-locus BPS local image failed certification"

  -> function_data
    @function_data

  -> local_map
    @local_map

  -> cover
    @cover

  -> dimension_certificate
    @dimension_certificate

  -> rational_prime
    @cover.prime

  -> disk_vectors
    out = []
    @disk_vectors.each -> (entry)
      vector = entry[1]
      vector = F2LinearAlgebra.copy_vector(vector) if vector != nil
      out.push([entry[0], vector])
    out

  -> clean_disk_count
    count = 0
    @disk_vectors.each ->
      count += 1 if item[1] != nil
    count

  -> base_disk
    @base_disk

  -> vectors
    F2LinearAlgebra.copy_matrix(@vectors)

  -> target_dimension
    @local_map.target_dimension

  -> span_certificate
    @span_certificate

  -> dimension
    @span_certificate.rank

  -> dimension_upper_bound
    @dimension_upper_bound

  -> image_basis
    @span_certificate.rref.copy(
      0, @span_certificate.rank)

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> complete?
    certificate.complete_local_image_checked?

  -> lower_bound_only?
    !complete?

  -> local_descent_image_certified?
    complete?


+ PadicCurveSmoothResidueDiskCover
  -> bps_smooth_locus_image(
       function_data, local_map, dimension_certificate = nil)
    PlaneQuarticBPSSmoothLocusLocalImage.new(
      function_data, local_map, self,
      dimension_certificate)


+ PlaneQuarticBPSFunctionData
  -> smooth_locus_local_image(
       local_map, precision = 20,
       dimension_certificate = nil)
    cover = curve.p_adic_smooth_residue_disks(
      local_map.rational_prime, precision)
    cover.bps_smooth_locus_image(
      self, local_map, dimension_certificate)


# A complete local BPS image W inside the product of local square-class
# targets imposes the exact global condition loc(x) in W.  Over F2 this is
# equivalent to q*loc(x) = 0 for every q in the orthogonal complement of W.
# Keeping the annihilator and composition certificates separate makes the
# global/local coordinate comparison replayable without choosing pivots by
# hand.
+ PlaneQuarticBPSLocalImageConstraintArithmetic
  -> .supported_image?(image)
    image_class = image.class_name
    return true if image_class == "PlaneQuarticBPSLocalDiskImage"
    return true if image_class == "PlaneQuarticBPSGoodReductionLocalImage"
    image_class == "PlaneQuarticBPSSmoothLocusLocalImage"

  -> .annihilator_certificate(image)
    system = F2LinearSystem.new(
      image.target_dimension)
    image.image_basis.each -> (vector)
      system.add_equation(
        vector, 0,
        "complete local BPS image basis")
    system.certificate

  -> .compose(local_map, annihilator_basis)
    compose_matrix(
      local_map.matrix,
      local_map.target_dimension,
      local_map.source.dimension,
      annihilator_basis)

  -> .compose_matrix(localization, target_width,
                     source_width, annihilator_basis)
    if localization.size != target_width
      raise "localization matrix has the wrong target height"
    out = []
    annihilator_basis.each -> (functional)
      F2LinearAlgebra.validate_vector(
        functional, target_width)
      row = []
      source_width.times -> row.push(0)
      target_index = 0
      while target_index < target_width
        local_row = localization[target_index]
        F2LinearAlgebra.validate_vector(
          local_row, source_width)
        if functional[target_index] == 1
          source_index = 0
          while source_index < source_width
            row[source_index] = (
              row[source_index] ^ local_row[source_index])
            source_index += 1
        target_index += 1
      out.push(row)
    out


+ PlaneQuarticBPSLocalImageConstraintCertificate
  -> new(@constraint)
    @verified_cache = nil

  -> theorem
    "a global descent class satisfies a local Selmer condition exactly when its localization lies in the complete BPS local image"

  -> theorem_reference
    "Bruin-Poonen-Stoll sections 9 through 11"

  -> proof_kind
    :trusted_bps_local_condition_with_exact_f2_preimage

  -> kernel_checked?
    true

  -> arithmetic_replay_checked?
    true

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
    expected = "PlaneQuarticBPSLocalImageConstraint"
    return false if @constraint.class_name != expected
    image = @constraint.local_image
    supported = (
      PlaneQuarticBPSLocalImageConstraintArithmetic.supported_image?(
        image))
    return false if !supported
    return false if !image.certificate.verified?
    return false if !image.complete?
    local_map = image.local_map
    return false if !local_map.certificate.verified?
    return false if local_map.source != @constraint.source
    return false if local_map.rational_prime != (
      @constraint.rational_prime)

    annihilator = @constraint.annihilator_certificate
    return false if !annihilator.verified?
    return false if annihilator.width != (
      local_map.target_dimension)
    return false if !F2LinearAlgebra.same_matrix?(
      annihilator.matrix, image.image_basis)
    return false if !annihilator.source_right_hand_side.all? ->
      item == 0
    expected_matrix = (
      PlaneQuarticBPSLocalImageConstraintArithmetic.compose(
        local_map, annihilator.kernel_basis))
    F2LinearAlgebra.same_matrix?(
      expected_matrix, @constraint.matrix)

  -> verify_selmer_constraint(name, width, matrix,
                              right_hand_side)
    expected_name = (
      "local image p=" +
      @constraint.rational_prime.to_s)
    return false if name.to_s != expected_name
    return false if width != @constraint.source.dimension
    return false if !F2LinearAlgebra.same_matrix?(
      matrix, @constraint.matrix)
    return false if right_hand_side.size != matrix.size
    right_hand_side.all? -> item == 0

  -> certified?
    verified?


+ PlaneQuarticBPSLocalImageConstraint
  -> new(@local_image)
    supported = (
      PlaneQuarticBPSLocalImageConstraintArithmetic.supported_image?(
        @local_image))
    if !supported
      raise "local BPS constraint needs a supported local image"
    if !@local_image.certificate.verified?
      raise "local BPS constraint image is uncertified"
    if !@local_image.complete?
      raise "local BPS constraint needs the complete local image"
    @source = @local_image.local_map.source
    @rational_prime = @local_image.rational_prime
    @annihilator_certificate = (
      PlaneQuarticBPSLocalImageConstraintArithmetic.annihilator_certificate(
        @local_image))
    @matrix = (
      PlaneQuarticBPSLocalImageConstraintArithmetic.compose(
        @local_image.local_map,
        @annihilator_certificate.kernel_basis))
    @certificate_cache = (
      PlaneQuarticBPSLocalImageConstraintCertificate.new(self))
    if !@certificate_cache.verified?
      raise "local BPS image constraint failed certification"

  -> local_image
    @local_image

  -> source
    @source

  -> rational_prime
    @rational_prime

  -> annihilator_certificate
    @annihilator_certificate

  -> matrix
    F2LinearAlgebra.copy_matrix(@matrix)

  -> dimension
    system = F2LinearSystem.new(@source.dimension)
    @matrix.each -> (row)
      system.add_equation(row)
    system.certificate.kernel_dimension

  -> constraint_block
    right = []
    @matrix.size.times -> right.push(0)
    SelmerConstraintBlock.new(
      "local image p=" + @rational_prime.to_s,
      @source.dimension, @matrix, right,
      certificate)

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?


+ PlaneQuarticBPSLocalDiskImage
  -> local_condition
    PlaneQuarticBPSLocalImageConstraint.new(self)


+ PlaneQuarticBPSGoodReductionLocalImage
  -> local_condition
    PlaneQuarticBPSLocalImageConstraint.new(self)


+ PlaneQuarticBPSSmoothLocusLocalImage
  -> local_condition
    PlaneQuarticBPSLocalImageConstraint.new(self)
