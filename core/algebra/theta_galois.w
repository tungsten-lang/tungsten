# Replayable finite subgroup identification for genus-three theta modules.
#
# The finite calculations in this file are internal: every supplied
# permutation is checked, its generated group is exhausted, and the complete
# 28-point theta incidence is preserved.  The completeness of a list of
# subgroup-conjugacy-class representatives is a separate, visible trust
# boundary.  For the shell-width quartic the seven records below are the
# classes left after filtering GAP's 1,369 conjugacy classes of subgroups of
# Sp6(F2) by the orbit partition [1, 6, 9, 12].

+ GenusThreeThetaSubgroupCandidate
  -> new(@class_id, @expected_order, generators, @reported_structure = nil, incidence = nil)
    @incidence = incidence == nil ? Algebra.genus_three_theta_incidence : incidence
    @group = FinitePermutationGroup.new(generators, @expected_order)
    @verified_cache = nil
    if !verified?
      raise "theta subgroup candidate failed exact replay"

  -> class_id
    @class_id

  -> expected_order
    @expected_order

  -> reported_structure
    @reported_structure

  -> incidence
    @incidence

  -> group
    @group

  -> preserves_incidence?(permutation)
    blocks = @incidence.syzygetic_quadruples
    labels = @incidence.odd_labels
    images = permutation.images
    index = 0
    while index < blocks.size
      block = blocks[index]
      value = labels[images[block[0]]] ^ labels[images[block[1]]]
      value = value ^ labels[images[block[2]]]
      return false if (value ^ labels[images[block[3]]]) != 0
      index += 1
    true

  -> verified?
    return @verified_cache if @verified_cache != nil
    @verified_cache = verify_fresh
    @verified_cache

  -> verify_fresh
    return false if !@incidence.certificate.verified?
    return false if !@group.certificate.verified?
    return false if @group.order != @expected_order
    @group.generators.each -> (generator)
      return false if !preserves_incidence?(generator)
    true

  -> certified?
    verified?

  -> proof_kind
    :exact_finite_theta_subgroup

  -> kernel_checked?
    true

  -> orbit_sizes
    @group.orbit_sizes

  -> fixed_points
    out = []
    @group.orbits.each -> (orbit)
      out.push(orbit[0]) if orbit.size == 1
    out

  -> stabilizer_orbit_signatures
    out = []
    fixed_points.each -> (point)
      out.push(@group.stabilizer_orbit_sizes(point))
    out

  -> stabilizer_orbit_signatures_for_orbit_size(orbit_size)
    out = []
    @group.orbits.each -> (orbit)
      if orbit.size == orbit_size
        signature = @group.stabilizer_orbit_sizes(orbit[0])
        if !out.any? -> item.to_s == signature.to_s
          out.push(signature)
    out

  -> has_stabilizer_signature?(orbit_size, signature)
    target = GenusThreeThetaPermutation.sort_integers(signature).to_s
    signatures = stabilizer_orbit_signatures_for_orbit_size(
      orbit_size)
    signatures.any? -> item.to_s == target

  -> contains_all_cycle_types?(cycle_types)
    cycle_types.all? -> @group.contains_cycle_lengths?(item)

  -> matches?(orbit_signature, stabilizer_signature, cycle_types)
    target_orbits = GenusThreeThetaPermutation.sort_integers(
      orbit_signature)
    return false if orbit_sizes.to_s != target_orbits.to_s
    return false if !has_stabilizer_signature?(
      6, stabilizer_signature)
    contains_all_cycle_types?(cycle_types)


+ TrustedThetaSubgroupClassTable
  -> new(@ambient_group, @total_class_count, records, @source, @filter)
    @records = []
    records.each -> @records.push(item)
    @candidates_cache = nil
    @verified_cache = nil

  -> ambient_group
    @ambient_group

  -> total_class_count
    @total_class_count

  -> source
    @source

  -> filter
    @filter

  -> records
    out = []
    @records.each -> out.push(item)
    out

  -> candidates
    if @candidates_cache == nil
      @candidates_cache = []
      incidence = Algebra.genus_three_theta_incidence
      @records.each -> (record)
        @candidates_cache.push(
          GenusThreeThetaSubgroupCandidate.new(
            record[0], record[1], record[3], record[2],
            incidence))
    out = []
    @candidates_cache.each -> out.push(item)
    out

  # This verifies the finite records, not exhaustion of all subgroup classes.
  -> verified?
    return @verified_cache if @verified_cache != nil
    @verified_cache = verify_fresh
    @verified_cache

  -> verify_fresh
    return false if @ambient_group != "Sp6(F2)"
    return false if @total_class_count != 1_369
    return false if @records.size != 7
    ids = {}
    candidates.each -> (candidate)
      return false if !candidate.verified?
      return false if ids.has_key?(candidate.class_id)
      ids[candidate.class_id] = true
      return false if candidate.orbit_sizes.to_s != "\[1, 6, 9, 12\]"
    true

  -> certified?
    verified?

  -> proof_kind
    :trusted_complete_external_classification

  -> kernel_checked?
    false

  -> finite_records_replayed?
    verified?

  -> completeness_replayed?
    false

  -> trusted_complete?
    true

  -> .shell_width
    records = []
    records.push([
      693, 36, "S3 x S3",
      [
        [0,17,1,16,19,3,18,2,12,15,14,13,11,27,26,10,22,6,7,23,5,20,21,4,8,9,25,24],
        [0,25,26,3,5,4,14,15,11,18,17,8,13,12,6,7,19,10,9,16,22,23,20,21,24,1,2,27]
      ]
    ])
    records.push([
      700, 36, nil,
      [
        [4,25,2,13,21,17,18,22,0,24,6,14,27,15,7,3,20,9,23,10,5,1,12,26,16,8,19,11],
        [27,12,2,6,7,17,13,8,11,24,18,1,4,19,0,23,20,16,26,15,9,14,21,3,5,22,10,25]
      ]
    ])
    records.push([
      947, 72, nil,
      [
        [27,22,10,6,1,26,16,11,0,23,17,7,4,13,8,19,24,20,18,15,2,25,12,5,3,21,9,14],
        [25,27,17,19,11,23,3,12,1,13,9,22,7,26,4,24,6,5,18,16,20,8,14,2,15,0,10,21]
      ]
    ])
    records.push([
      949, 72, nil,
      [
        [0,15,26,4,3,5,25,14,8,17,18,11,24,13,7,1,22,9,10,21,20,19,16,23,12,6,2,27],
        [0,10,25,19,3,13,26,6,16,7,9,12,21,8,15,2,20,14,17,27,22,11,5,24,4,18,1,23]
      ]
    ])
    records.push([
      950, 72, nil,
      [
        [0,15,26,4,3,5,25,14,8,17,18,11,24,13,7,1,22,9,10,21,20,19,16,23,12,6,2,27],
        [0,18,1,19,3,13,2,15,16,14,17,12,21,8,6,26,20,7,9,27,22,11,5,24,4,10,25,23]
      ]
    ])
    records.push([
      953, 72, nil,
      [
        [1,5,3,7,10,4,8,6,11,0,9,2,21,26,17,12,18,22,15,27,25,23,14,16,24,19,20,13],
        [3,2,1,0,7,6,5,4,9,8,11,10,15,14,13,12,18,19,16,17,22,23,20,21,24,25,26,27],
        [3,2,1,0,8,11,10,9,4,7,6,5,16,19,17,18,12,14,15,13,20,23,22,21,24,26,25,27]
      ]
    ])
    records.push([
      1130, 144, nil,
      [
        [6,1,4,3,2,5,0,7,8,9,10,11,12,25,24,15,16,22,21,19,20,18,17,23,14,13,26,27],
        [21,20,22,23,17,9,18,10,11,19,8,16,7,14,6,15,12,13,4,5,26,2,25,1,0,24,27,3],
        [25,1,2,26,4,5,13,12,8,16,19,11,7,6,14,15,9,17,18,10,20,21,22,23,24,0,3,27]
      ]
    ])
    TrustedThetaSubgroupClassTable.new(
      "Sp6(F2)", 1_369, records,
      "GAP ConjugacyClassesSubgroups(Sp(6,2)) via Sage",
      "orbit sizes \[1, 6, 9, 12\]")


+ GenusThreeThetaSubgroupIdentificationCertificate
  -> new(@table, orbit_signature, stabilizer_signature, cycle_types)
    @orbit_signature = GenusThreeThetaPermutation.sort_integers(
      orbit_signature)
    @stabilizer_signature = GenusThreeThetaPermutation.sort_integers(
      stabilizer_signature)
    @cycle_types = []
    cycle_types.each ->
      @cycle_types.push(
        GenusThreeThetaPermutation.sort_integers(item))
    @survivors_cache = nil
    @verified_cache = nil

  -> table
    @table

  -> orbit_signature
    F2LinearAlgebra.copy_vector(@orbit_signature)

  -> stabilizer_signature
    F2LinearAlgebra.copy_vector(@stabilizer_signature)

  -> cycle_types
    out = []
    @cycle_types.each -> out.push(F2LinearAlgebra.copy_vector(item))
    out

  -> survivors
    if @survivors_cache == nil
      @survivors_cache = []
      @table.candidates.each -> (candidate)
        if candidate.matches?(
             @orbit_signature, @stabilizer_signature,
             @cycle_types)
          @survivors_cache.push(candidate)
    out = []
    @survivors_cache.each -> out.push(item)
    out

  -> identified_candidate
    return nil if survivors.size != 1
    survivors[0]

  -> verified?
    return @verified_cache if @verified_cache != nil
    @verified_cache = verify_fresh
    @verified_cache

  -> verify_fresh
    return false if @table.class_name != "TrustedThetaSubgroupClassTable"
    return false if !@table.verified?
    return false if @orbit_signature.to_s != "\[1, 6, 9, 12\]"
    return false if @stabilizer_signature.to_s != "\[1, 1, 2, 2, 2, 2, 3, 3, 6, 6\]"
    candidate = identified_candidate
    return false if candidate == nil
    candidate.class_id == 693 && candidate.expected_order == 36

  -> certified?
    verified?

  -> proof_kind
    :trusted_classification_with_exact_finite_replay

  -> kernel_checked?
    false

  -> finite_replay_checked?
    verified?

  -> subgroup_table_completeness_checked?
    false

  -> arithmetic_invariants_checked?
    false

  -> global_galois_group_certified?
    false

  -> conclusion
    return "unverified" if !verified?
    "unique supplied subgroup class 693, order 36, reported structure S3 x S3"

  -> .shell_width
    identity = []
    28.times -> identity.push(1)
    cycle_types = [
      identity,
      [1,1,1,1,1,1,1,1,1,1,3,3,3,3,3,3],
      [1,1,1,1,2,2,2,2,2,2,2,2,2,2,2,2],
      [1,3,3,3,3,3,3,3,3,3],
      [1,3,6,6,6,6]
    ]
    GenusThreeThetaSubgroupIdentificationCertificate.new(
      TrustedThetaSubgroupClassTable.shell_width,
      [1,6,9,12],
      [1,1,2,2,2,2,3,3,6,6],
      cycle_types)


+ Algebra
  -> .shell_width_theta_subgroup_identification
    GenusThreeThetaSubgroupIdentificationCertificate.shell_width
