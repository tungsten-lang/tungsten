# Local 2-torsion dimensions from exact theta-factor orbits.
#
# A decomposition subgroup acts on the 28 odd theta characteristics. The
# irreducible degrees over Q_p are its orbit sizes. Once the global theta
# subgroup is certified up to conjugacy, exhaust every subgroup of the
# representative having the exact local orbit partition and compute its
# fixed subspace on J[2] = F2^6. If all candidates agree, the local rational
# 2-torsion dimension is determined without choosing a root labeling.

+ PlaneQuarticLocalThetaArithmetic
  -> .orbit_signature(function_data, local_map)
    if !PlaneQuarticBPSPointDifferenceArithmetic.same_component_polynomials?(
         function_data, local_map.source)
      raise "local theta data changes the bitangent components"
    component_bases = local_map.source.component_bases
    degrees = function_data.component_degrees
    if component_bases.size != degrees.size
      raise "local theta component count mismatch"
    component_bases.each -> (bases)
      if bases.size != 1
        raise "local theta orbit certificate needs one basis per component"
    local_maps = local_map.local_maps
    if local_maps.size != degrees.size
      raise "local theta localization component count mismatch"
    signature = [1]
    component_index = 0
    while component_index < local_maps.size
      total = 0
      local_maps[component_index].each -> (map)
        prime = map.prime_ideal
        degree = (
          prime.ramification_index *
          prime.residue_degree)
        signature.push(degree)
        total += degree
      if total != degrees[component_index]
        raise "local theta completion degrees do not recover the component"
      component_index += 1
    signature = GenusThreeThetaPermutation.sort_integers(
      signature)
    sum = 0
    signature.each -> sum += item
    if sum != 28
      raise "local theta orbit degrees do not recover 28 bitangents"
    signature

  -> .subgroup_keys(parent, subgroups)
    out = []
    subgroups.each -> (subgroup)
      out.push(FinitePermutationSubgroupArithmetic.key(
        parent, subgroup))
    out

  -> .unique_dimensions(fixed_spaces)
    out = []
    fixed_spaces.each -> (fixed)
      dimension = fixed.dimension
      out.push(dimension) if !out.include?(dimension)
    GenusThreeThetaPermutation.sort_integers(out)


+ PlaneQuarticLocalThetaDimensionCertificate
  -> new(@model)
    @verified_cache = nil

  -> theorem
    "local bitangent factor degrees determine the decomposition-subgroup orbit partition and hence the rational J[2] dimension when every compatible subgroup agrees"

  -> theorem_reference
    "decomposition-group orbits on roots, Riemann-Mumford theta characteristics, and prime-to-p Kummer theory for abelian varieties over local fields"

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
    expected = "PlaneQuarticLocalThetaDimension"
    return false if @model.class_name != expected
    data = @model.function_data
    return false if data.class_name != "PlaneQuarticBPSFunctionData"
    return false if !data.certificate.verified?
    local_map = @model.local_map
    return false if local_map.class_name != "EtaleProductOddLocalSquareClassMap"
    return false if !local_map.certificate.verified?
    return false if local_map.rational_prime == 2
    galois = @model.global_theta_certificate
    return false if galois.class_name != "ShellWidthThetaGaloisCertificate"
    return false if !galois.verified?
    return false if !galois.global_theta_galois_subgroup_certified?
    candidate = galois.identified_candidate
    return false if candidate.class_id != 693
    return false if candidate.group.order != 36

    signature = PlaneQuarticLocalThetaArithmetic.orbit_signature(
      data, local_map)
    return false if signature.to_s != @model.orbit_signature.to_s
    enumeration = @model.subgroup_enumeration
    return false if !enumeration.certificate.verified?
    return false if enumeration.parent != candidate.group
    expected_subgroups = []
    enumeration.subgroups.each -> (subgroup)
      if subgroup.orbit_sizes.to_s == signature.to_s
        expected_subgroups.push(subgroup)
    supplied = @model.compatible_subgroups
    expected_keys = PlaneQuarticLocalThetaArithmetic.subgroup_keys(
      candidate.group, expected_subgroups)
    supplied_keys = PlaneQuarticLocalThetaArithmetic.subgroup_keys(
      candidate.group, supplied)
    return false if expected_keys.to_s != supplied_keys.to_s
    return false if supplied.size == 0

    fixed_spaces = @model.fixed_spaces
    return false if fixed_spaces.size != supplied.size
    index = 0
    while index < fixed_spaces.size
      fixed = fixed_spaces[index]
      return false if !fixed.certificate.verified?
      return false if fixed.subgroup != supplied[index]
      index += 1
    dimensions = PlaneQuarticLocalThetaArithmetic.unique_dimensions(
      fixed_spaces)
    return false if dimensions.to_s != (
      @model.possible_dimensions.to_s)
    return false if dimensions.size != 1
    return false if dimensions[0] != @model.dimension
    true

  -> certified?
    verified?

  -> proof_kind
    :trusted_local_theta_orbits_with_exact_subgroup_exhaustion

  -> kernel_checked?
    false

  -> arithmetic_replay_checked?
    true

  -> subgroup_exhaustion_checked?
    verified?

  -> fixed_spaces_kernel_checked?
    verified?

  -> local_2_quotient_dimension_checked?
    verified?


+ PlaneQuarticLocalThetaDimension
  -> new(@function_data, @local_map,
         @global_theta_certificate)
    if @function_data.class_name != "PlaneQuarticBPSFunctionData"
      raise "local theta dimension needs BPS function data"
    if !@function_data.certificate.verified?
      raise "local theta function data is uncertified"
    if @local_map.class_name != "EtaleProductOddLocalSquareClassMap"
      raise "local theta dimension needs an odd localization map"
    if !@local_map.certificate.verified?
      raise "local theta localization map is uncertified"
    if @global_theta_certificate.class_name != (
         "ShellWidthThetaGaloisCertificate")
      raise "local theta dimension needs the global theta subgroup"
    if !@global_theta_certificate.verified?
      raise "global theta subgroup certificate is unverified"
    @orbit_signature = (
      PlaneQuarticLocalThetaArithmetic.orbit_signature(
        @function_data, @local_map))
    candidate = @global_theta_certificate.identified_candidate
    @subgroup_enumeration = (
      candidate.group.subgroup_enumeration)
    @compatible_subgroups = []
    @subgroup_enumeration.subgroups.each -> (subgroup)
      if subgroup.orbit_sizes.to_s == @orbit_signature.to_s
        @compatible_subgroups.push(subgroup)
    if @compatible_subgroups.size == 0
      raise "no global theta subgroup has the local orbit partition"
    @fixed_spaces = []
    @compatible_subgroups.each -> (subgroup)
      @fixed_spaces.push(subgroup.theta_fixed_space)
    @possible_dimensions = (
      PlaneQuarticLocalThetaArithmetic.unique_dimensions(
        @fixed_spaces))
    if @possible_dimensions.size != 1
      raise "local theta orbit partition does not determine J[2]"
    @dimension = @possible_dimensions[0]
    @certificate_cache = (
      PlaneQuarticLocalThetaDimensionCertificate.new(self))
    if !@certificate_cache.verified?
      raise "local theta dimension certificate failed"

  -> function_data
    @function_data

  -> curve
    @function_data.curve

  -> local_map
    @local_map

  -> rational_prime
    @local_map.rational_prime

  -> global_theta_certificate
    @global_theta_certificate

  -> orbit_signature
    F2LinearAlgebra.copy_vector(@orbit_signature)

  -> subgroup_enumeration
    @subgroup_enumeration

  -> compatible_subgroups
    out = []
    @compatible_subgroups.each -> out.push(item)
    out

  -> compatible_subgroup_count
    @compatible_subgroups.size

  -> fixed_spaces
    out = []
    @fixed_spaces.each -> out.push(item)
    out

  -> possible_dimensions
    F2LinearAlgebra.copy_vector(
      @possible_dimensions)

  -> dimension
    @dimension

  -> dimension_upper_bound
    @dimension

  -> local_2_quotient_dimension
    @dimension

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?


+ PlaneQuarticTwoDescentSetup
  -> certify_local_theta_dimension(local_map)
    if @bps_function_data == nil
      certify_divisor_function_data
    if @theta_galois_certificate == nil
      certify_theta_galois_subgroup
    PlaneQuarticLocalThetaDimension.new(
      @bps_function_data, local_map,
      @theta_galois_certificate)
