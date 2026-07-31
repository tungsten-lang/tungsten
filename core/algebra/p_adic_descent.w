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
