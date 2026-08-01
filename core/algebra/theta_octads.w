# Cayley-octad labels from genus-three theta characteristics.
#
# Fixing an even theta characteristic determines eight Aronhold sets.  Each
# set has seven odd characteristics; two of the eight sets meet in exactly
# one odd characteristic, so the 28 pairwise intersections label the 28
# edges of an abstract eight-point Cayley octad.  This file enumerates and
# replays that finite combinatorics exactly.
#
# Interpreting the eight rows as the points of the geometric Cayley octad of a
# plane quartic still uses the classical theta/determinantal correspondence.
# The certificate keeps that theorem boundary separate from the finite F2
# calculation.


+ ThetaCayleyOctadLabelingCertificate
  -> new(@labeling)
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
    return false if @labeling.class_name != (
      "ThetaCayleyOctadLabeling")
    incidence = @labeling.incidence
    even = @labeling.even_characteristic
    return false if !incidence.certificate.verified?
    return false if !even.certificate.verified? || even.odd?
    return false if even.space != incidence.space

    rows = @labeling.rows
    expected = @labeling.recompute_rows
    return false if rows.to_s != expected.to_s
    return false if rows.size != 8

    row_index = 0
    while row_index < rows.size
      row = rows[row_index]
      return false if row.size != 7
      return false if !F2LinearAlgebra.same_vector?(
        incidence.characteristic_sum(row),
        even.characteristic)
      i = 0
      while i < row.size
        return false if row[i] < 0 || row[i] >= 28
        return false if i > 0 && row[i - 1] >= row[i]
        j = i + 1
        while j < row.size
          return false if !@labeling.azygetic_labels?(
            @labeling.even_label,
            incidence.odd_label(row[i]),
            incidence.odd_label(row[j]))
          k = j + 1
          while k < row.size
            return false if !@labeling.azygetic_labels?(
              incidence.odd_label(row[i]),
              incidence.odd_label(row[j]),
              incidence.odd_label(row[k]))
            k += 1
          j += 1
        i += 1
      row_index += 1

    # The complete graph on the eight rows must recover every odd
    # characteristic exactly once through singleton intersections.
    seen = []
    28.times -> seen.push(false)
    left = 0
    while left < rows.size
      right = left + 1
      while right < rows.size
        label = @labeling.edge_label(left, right)
        return false if label < 0 || label >= 28
        return false if seen[label]
        seen[label] = true
        right += 1
      left += 1
    seen.each -> (value)
      return false if !value
    true

  -> certified?
    verified?

  -> proof_kind
    :exact_finite_aronhold_enumeration

  -> kernel_checked?
    true

  -> theorem
    "the eight Aronhold sets for an even theta characteristic are the rows of its Cayley-octad bitangent matrix"

  -> theorem_reference
    "Dalla Piazza-Fiorentino-Salvati Manni, Definition 3.4, Lemma 3.5, and Remark 3.6"

  -> geometric_correspondence_kernel_checked?
    false


+ ThetaCayleyOctadLabeling
  -> new(@incidence, @even_characteristic)
    if @incidence.class_name != "GenusThreeThetaIncidence"
      raise "theta Cayley octad needs genus-three incidence"
    if @even_characteristic.class_name != "ThetaQuadraticForm"
      raise "theta Cayley octad needs an even theta characteristic"
    if @even_characteristic.space != @incidence.space
      raise "theta Cayley octad characteristic uses a different space"
    if @even_characteristic.odd? || !@even_characteristic.certificate.verified?
      raise "theta Cayley octad characteristic must be certified and even"
    @parities = []
    encoded = 0
    while encoded < 64
      form = ThetaQuadraticForm.new(
        @incidence.space, @incidence.space.vector(encoded))
      @parities.push(form.arf_invariant)
      encoded += 1
    @even_label = encoded_characteristic(@even_characteristic)
    @rows = recompute_rows
    @certificate_cache = ThetaCayleyOctadLabelingCertificate.new(self)
    if !@certificate_cache.verified?
      raise "theta Cayley-octad labeling failed certification"

  -> incidence
    @incidence

  -> even_characteristic
    @even_characteristic

  -> even_label
    @even_label

  -> rows
    F2LinearAlgebra.copy_matrix(@rows)

  -> encoded_characteristic(form)
    encoded = 0
    while encoded < 64
      if F2LinearAlgebra.same_vector?(
           @incidence.space.vector(encoded),
           form.characteristic)
        return encoded
      encoded += 1
    raise "theta characteristic is not in the genus-three space"

  # e(a,b,c) = -1 exactly when the XOR of the four Arf invariants
  # arf(a), arf(b), arf(c), and arf(a+b+c) is one.
  -> azygetic_labels?(a, b, c)
    value = @parities[a] ^ @parities[b]
    value = value ^ @parities[c]
    value = value ^ @parities[a ^ b ^ c]
    value == 1

  -> extension_compatible?(chosen, candidate)
    candidate_label = @incidence.odd_label(candidate)
    i = 0
    while i < chosen.size
      prior_label = @incidence.odd_label(chosen[i])
      return false if !azygetic_labels?(
        @even_label, prior_label, candidate_label)
      j = i + 1
      while j < chosen.size
        return false if !azygetic_labels?(
          prior_label,
          @incidence.odd_label(chosen[j]),
          candidate_label)
        j += 1
      i += 1
    true

  -> enumerate_rows(chosen, next_index, out)
    if chosen.size == 7
      if F2LinearAlgebra.same_vector?(
           @incidence.characteristic_sum(chosen),
           @even_characteristic.characteristic)
        out.push(F2LinearAlgebra.copy_vector(chosen))
      return

    needed = 7 - chosen.size
    candidate = next_index
    last = 28 - needed
    while candidate <= last
      if extension_compatible?(chosen, candidate)
        extended = F2LinearAlgebra.copy_vector(chosen)
        extended.push(candidate)
        enumerate_rows(extended, candidate + 1, out)
      candidate += 1

  -> recompute_rows
    out = []
    enumerate_rows([], 0, out)
    out

  -> edge_label(left, right)
    if left < 0 || left >= @rows.size || (
       right < 0 || right >= @rows.size || left == right)
      raise "Cayley-octad edge needs two distinct row indices"
    intersection = -1
    i = 0
    while i < @rows[left].size
      value = @rows[left][i]
      j = 0
      while j < @rows[right].size
        if value == @rows[right][j]
          if intersection != -1
            raise "Cayley-octad rows have a nonsingleton intersection"
          intersection = value
        j += 1
      i += 1
    if intersection == -1
      raise "Cayley-octad rows have an empty intersection"
    intersection

  -> row_index(row)
    sorted = GenusThreeThetaPermutation.sort_integers(row)
    index = 0
    while index < @rows.size
      return index if @rows[index].to_s == sorted.to_s
      index += 1
    nil

  -> induced_action(subgroup)
    ThetaCayleyOctadAction.new(self, subgroup)

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?


+ ThetaCayleyOctadActionCertificate
  -> new(@action)
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
    return false if @action.class_name != "ThetaCayleyOctadAction"
    labeling = @action.labeling
    source = @action.source_group
    return false if !labeling.certificate.verified?
    return false if !source.certificate.verified? || source.degree != 28
    generators = @action.generator_permutations
    return false if generators.size != source.generators.size
    lifts = @action.generator_lifts
    return false if lifts.size != generators.size

    index = 0
    while index < generators.size
      return false if generators[index].degree != 8
      transformed_even = lifts[index].transformed_characteristic(
        labeling.even_characteristic)
      return false if !F2LinearAlgebra.same_vector?(
        transformed_even,
        labeling.even_characteristic.characteristic)

      # The induced action on the 28 edges must be exactly the supplied
      # odd-theta permutation, not merely an isomorphic eight-point action.
      left = 0
      while left < 8
        right = left + 1
        while right < 8
          source_edge = labeling.edge_label(left, right)
          target_edge = labeling.edge_label(
            generators[index].apply(left),
            generators[index].apply(right))
          expected_edge = source.generators[index].apply(source_edge)
          return false if target_edge != expected_edge
          right += 1
        left += 1
      index += 1

    group = @action.group
    return false if !group.certificate.verified?
    return false if group.degree != 8
    # Faithfulness follows from the checked action on all 28 edges; equality
    # of the exhaustively enumerated orders catches any construction defect.
    group.order == source.order

  -> certified?
    verified?

  -> proof_kind
    :exact_cayley_octad_permutation_lift

  -> kernel_checked?
    true


+ ThetaCayleyOctadAction
  -> new(@labeling, @source_group)
    if @labeling.class_name != "ThetaCayleyOctadLabeling"
      raise "octad action needs a theta Cayley-octad labeling"
    if @source_group.class_name != "FinitePermutationGroup" || (
       @source_group.degree != 28)
      raise "octad action needs a 28-point finite permutation group"
    @generator_lifts = []
    @generator_permutations = []
    @source_group.generators.each -> (generator)
      lift = GenusThreeThetaPermutation.from_permutation(
        @labeling.incidence, generator)
      @generator_lifts.push(lift)
      images = []
      row_index = 0
      rows = @labeling.rows
      while row_index < rows.size
        image_row = []
        rows[row_index].each -> (odd_index)
          image_row.push(generator.apply(odd_index))
        target = @labeling.row_index(image_row)
        if target == nil
          raise "theta subgroup does not preserve the Cayley-octad rows"
        images.push(target)
        row_index += 1
      @generator_permutations.push(FinitePermutation.new(images))
    @group = FinitePermutationGroup.new(
      @generator_permutations, @source_group.order)
    @certificate_cache = ThetaCayleyOctadActionCertificate.new(self)
    if !@certificate_cache.verified?
      raise "theta Cayley-octad action failed certification"

  -> labeling
    @labeling

  -> source_group
    @source_group

  -> generator_lifts
    out = []
    @generator_lifts.each -> out.push(item)
    out

  -> generator_permutations
    out = []
    @generator_permutations.each -> out.push(item)
    out

  -> group
    @group

  -> orbit_sizes
    @group.orbit_sizes

  -> component_degrees
    orbit_sizes

  # Transport any element of the supplied 28-point subgroup to the eight
  # Aronhold rows.  This is deliberately checked on all 28 edges before the
  # result is returned, so callers may compare arithmetic Frobenius cycle
  # classes without assuming a word in the chosen generators.
  -> induced_permutation(source_element)
    if source_element.class_name != "FinitePermutation" || (
       source_element.degree != @source_group.degree)
      raise "octad element lift needs a source-group permutation"
    present = @source_group.elements.any? -> (element)
      element.key == source_element.key
    if !present
      raise "octad element lift received a permutation outside the subgroup"

    images = []
    rows = @labeling.rows
    row_index = 0
    while row_index < rows.size
      image_row = []
      rows[row_index].each -> (odd_index)
        image_row.push(source_element.apply(odd_index))
      target = @labeling.row_index(image_row)
      if target == nil
        raise "theta subgroup element does not preserve the Cayley-octad rows"
      images.push(target)
      row_index += 1
    result = FinitePermutation.new(images)

    left = 0
    while left < 8
      right = left + 1
      while right < 8
        source_edge = @labeling.edge_label(left, right)
        target_edge = @labeling.edge_label(
          result.apply(left), result.apply(right))
        if target_edge != source_element.apply(source_edge)
          raise "octad element lift changed the induced edge action"
        right += 1
      left += 1
    result

  # Enumerate every generator-equivariant bijection between one orbit of the
  # original 28-point action and one orbit of the induced eight-point action.
  # A returned array has source-group degree; entries outside source_orbit are
  # -1.  This is the exact finite test needed to decide whether a bitangent
  # component and an octad-point component define the same transitive G-set.
  -> equivariant_orbit_maps(source_orbit, target_orbit)
    source_orbits = @source_group.orbits
    target_orbits = @group.orbits
    source_key = GenusThreeThetaPermutation.sort_integers(
      source_orbit).to_s
    target_key = GenusThreeThetaPermutation.sort_integers(
      target_orbit).to_s
    return [] if !source_orbits.any? -> item.to_s == source_key
    return [] if !target_orbits.any? -> item.to_s == target_key
    return [] if source_orbit.size != target_orbit.size

    out = []
    target_orbit.each -> (target_seed)
      mapping = []
      @source_group.degree.times -> mapping.push(-1)
      reverse = []
      @group.degree.times -> reverse.push(-1)
      source_seed = source_orbit[0]
      mapping[source_seed] = target_seed
      reverse[target_seed] = source_seed
      queue = [source_seed]
      cursor = 0
      valid = true
      while cursor < queue.size && valid
        source = queue[cursor]
        target = mapping[source]
        generator_index = 0
        while generator_index < @source_group.generators.size && valid
          source_image = @source_group.generators[generator_index].apply(
            source)
          target_image = @generator_permutations[generator_index].apply(
            target)
          if mapping[source_image] != -1
            valid = false if mapping[source_image] != target_image
          elsif reverse[target_image] != -1
            valid = false
          else
            mapping[source_image] = target_image
            reverse[target_image] = source_image
            queue.push(source_image)
          generator_index += 1
        cursor += 1
      if valid && queue.size == source_orbit.size
        out.push(mapping)
    out

  -> matching_orbit_pairs
    out = []
    @source_group.orbits.each -> (source_orbit)
      @group.orbits.each -> (target_orbit)
        maps = equivariant_orbit_maps(source_orbit, target_orbit)
        if maps.size > 0
          out.push([source_orbit, target_orbit, maps])
    out

  -> frobenius_class_test(frobenius_map)
    ThetaCayleyOctadFrobeniusClassTest.new(
      self, frobenius_map)

  -> subfield_profile
    ThetaCayleyOctadSubfieldProfile.new(self)

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?


+ ThetaCayleyOctadFrobeniusClassCertificate
  -> new(@test)
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
    expected = "ThetaCayleyOctadFrobeniusClassTest"
    return false if @test.class_name != expected
    action = @test.action
    return false if !action.certificate.verified?
    local = @test.local_theta_permutation
    return false if !local.certificate.verified?
    return false if local.incidence != action.labeling.incidence

    target_cycles = local.cycle_lengths.to_s
    compatible = []
    action.source_group.elements.each -> (element)
      compatible.push(element) if element.cycle_lengths.to_s == target_cycles
    return false if compatible.size != @test.cycle_compatible_count

    seen = {}
    matching = @test.matching_tests
    obstructed = @test.obstructed_tests
    matching.each -> (entry)
      return false if entry.size != 2
      element = entry[0]
      conjugacy = entry[1]
      return false if element.cycle_lengths.to_s != target_cycles
      return false if !conjugacy.certificate.verified?
      return false if !conjugacy.conjugate?
      return false if seen.has_key?(element.key)
      seen[element.key] = true
    obstructed.each -> (entry)
      return false if entry.size != 2
      element = entry[0]
      conjugacy = entry[1]
      return false if element.cycle_lengths.to_s != target_cycles
      return false if !conjugacy.certificate.verified?
      return false if conjugacy.conjugate?
      return false if seen.has_key?(element.key)
      seen[element.key] = true
    return false if seen.size != compatible.size
    compatible.each -> (element)
      return false if !seen.has_key?(element.key)
    return false if matching.size == 0

    pair_orbits = []
    action.group.orbits.each -> (orbit)
      pair_orbits.push(orbit) if orbit.size == 2
    return false if pair_orbits.size != 1
    return false if pair_orbits[0].to_s != @test.pair_orbit.to_s
    expected_pair_cycles = @test.pair_cycle_lengths.to_s
    matching.each -> (entry)
      return false if @test.pair_cycles(entry[0]).to_s != (
        expected_pair_cycles)
    expected_pair_cycles == "\[1, 1\]" || expected_pair_cycles == "\[2\]"

  -> certified?
    verified?

  -> proof_kind
    :exact_symplectic_frobenius_class_filter

  -> kernel_checked?
    true

  -> arithmetic_frobenius_binding_checked?
    false


+ ThetaCayleyOctadSubfieldProfileCertificate
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
    return false if @profile.class_name != "ThetaCayleyOctadSubfieldProfile"
    action = @profile.action
    return false if !action.certificate.verified?
    enumeration = @profile.subgroup_enumeration
    return false if !enumeration.certificate.verified?
    return false if enumeration.parent != action.source_group
    index_two = @profile.index_two_subgroups
    return false if index_two.size != 3
    index_two.each -> (subgroup)
      return false if subgroup.order * 2 != action.source_group.order

    # Stabilizers of points in the 2-, 6-, and 12-point transitive G-sets
    # have indices 2, 6, and 12.  The Galois correspondence then turns the
    # count of index-two supergroups into the number of quadratic subfields.
    return false if @profile.pair_stabilizer.size != 18
    return false if @profile.sextic_stabilizer.size != 6
    return false if @profile.degree_twelve_stabilizer.size != 3
    return false if @profile.recompute_containing_count(
      @profile.pair_stabilizer) != @profile.pair_quadratic_subfield_count
    return false if @profile.recompute_containing_count(
      @profile.sextic_stabilizer) != @profile.sextic_quadratic_subfield_count
    return false if @profile.recompute_containing_count(
      @profile.degree_twelve_stabilizer) != (
        @profile.degree_twelve_quadratic_subfield_count)
    @profile.pair_quadratic_subfield_count == 1 && (
      @profile.sextic_quadratic_subfield_count == 1) && (
      @profile.degree_twelve_quadratic_subfield_count == 3)

  -> certified?
    verified?

  -> proof_kind
    :exact_subgroup_lattice_replay

  -> kernel_checked?
    true

  -> galois_correspondence_kernel_checked?
    false


+ ThetaCayleyOctadFrobeniusClassTest
  -> new(@action, @frobenius_map)
    if @action.class_name != "ThetaCayleyOctadAction"
      raise "octad Frobenius test needs a Cayley-octad action"
    if @frobenius_map.class_name != "SymplecticF2Map"
      raise "octad Frobenius test needs a matching symplectic map"
    target_space = @action.labeling.incidence.space
    if @frobenius_map.space != target_space
      if @frobenius_map.space.genus != target_space.genus
        raise "octad Frobenius test needs a matching symplectic map"
      @frobenius_map = SymplecticF2Map.new(
        target_space, @frobenius_map.matrix)
    @local_theta_permutation = GenusThreeThetaPermutation.new(
      @action.labeling.incidence, @frobenius_map)
    target_cycles = @local_theta_permutation.cycle_lengths.to_s
    @matching_tests = []
    @obstructed_tests = []
    @action.source_group.elements.each -> (element)
      if element.cycle_lengths.to_s == target_cycles
        target_map = GenusThreeThetaPermutation.from_permutation(
          @action.labeling.incidence, element).transformation
        conjugacy = @frobenius_map.conjugacy_test(target_map)
        entry = [element, conjugacy]
        if conjugacy.conjugate?
          @matching_tests.push(entry)
        else
          @obstructed_tests.push(entry)
    @pair_orbit = nil
    @action.group.orbits.each -> (orbit)
      if orbit.size == 2
        if @pair_orbit != nil
          raise "octad Frobenius test found multiple two-point orbits"
        @pair_orbit = orbit
    if @pair_orbit == nil
      raise "octad Frobenius test needs a two-point orbit"
    if @matching_tests.size == 0
      raise "octad Frobenius class is absent from the candidate subgroup"
    @pair_cycle_lengths = pair_cycles(@matching_tests[0][0])
    @matching_tests.each -> (entry)
      if pair_cycles(entry[0]).to_s != @pair_cycle_lengths.to_s
        raise "octad Frobenius class has ambiguous pair action"
    @certificate_cache = ThetaCayleyOctadFrobeniusClassCertificate.new(
      self)
    if !@certificate_cache.verified?
      raise "octad Frobenius class test failed certification"

  -> action
    @action

  -> frobenius_map
    @frobenius_map

  -> local_theta_permutation
    @local_theta_permutation

  -> matching_tests
    out = []
    @matching_tests.each -> (entry)
      out.push([entry[0], entry[1]])
    out

  -> obstructed_tests
    out = []
    @obstructed_tests.each -> (entry)
      out.push([entry[0], entry[1]])
    out

  -> matching_elements
    out = []
    @matching_tests.each -> (entry)
      out.push(entry[0])
    out

  -> obstructed_elements
    out = []
    @obstructed_tests.each -> (entry)
      out.push(entry[0])
    out

  -> cycle_compatible_count
    @matching_tests.size + @obstructed_tests.size

  -> pair_orbit
    F2LinearAlgebra.copy_vector(@pair_orbit)

  -> pair_cycles(source_element)
    induced = @action.induced_permutation(source_element)
    first = @pair_orbit[0]
    second = @pair_orbit[1]
    if induced.apply(first) == first && induced.apply(second) == second
      return [1, 1]
    if induced.apply(first) == second && induced.apply(second) == first
      return [2]
    raise "octad Frobenius element does not preserve the two-point orbit"

  -> pair_cycle_lengths
    F2LinearAlgebra.copy_vector(@pair_cycle_lengths)

  -> pair_fixed?
    @pair_cycle_lengths.to_s == "\[1, 1\]"

  -> pair_swapped?
    @pair_cycle_lengths.to_s == "\[2\]"

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?


+ ThetaCayleyOctadSubfieldProfile
  -> new(@action)
    if @action.class_name != "ThetaCayleyOctadAction"
      raise "octad subfield profile needs a Cayley-octad action"
    @subgroup_enumeration = @action.source_group.subgroup_enumeration
    @index_two_subgroups = []
    @subgroup_enumeration.subgroups.each -> (subgroup)
      if subgroup.order * 2 == @action.source_group.order
        @index_two_subgroups.push(subgroup)

    pair_orbit = nil
    sextic_orbit = nil
    @action.group.orbits.each -> (orbit)
      pair_orbit = orbit if orbit.size == 2
      sextic_orbit = orbit if orbit.size == 6
    if pair_orbit == nil || sextic_orbit == nil
      raise "octad subfield profile needs two- and six-point orbits"
    degree_twelve_orbit = nil
    @action.source_group.orbits.each -> (orbit)
      degree_twelve_orbit = orbit if orbit.size == 12
    if degree_twelve_orbit == nil
      raise "octad subfield profile needs a degree-twelve bitangent orbit"

    @pair_stabilizer = []
    @sextic_stabilizer = []
    @action.source_group.elements.each -> (element)
      induced = @action.induced_permutation(element)
      @pair_stabilizer.push(element) if induced.apply(pair_orbit[0]) == (
        pair_orbit[0])
      @sextic_stabilizer.push(element) if induced.apply(sextic_orbit[0]) == (
        sextic_orbit[0])
    @degree_twelve_stabilizer = @action.source_group.stabilizer_elements(
      degree_twelve_orbit[0])
    @pair_quadratic_subfield_count = recompute_containing_count(
      @pair_stabilizer)
    @sextic_quadratic_subfield_count = recompute_containing_count(
      @sextic_stabilizer)
    @degree_twelve_quadratic_subfield_count = recompute_containing_count(
      @degree_twelve_stabilizer)
    @certificate_cache = ThetaCayleyOctadSubfieldProfileCertificate.new(
      self)
    if !@certificate_cache.verified?
      raise "octad subfield profile failed certification"

  -> action
    @action

  -> subgroup_enumeration
    @subgroup_enumeration

  -> index_two_subgroups
    out = []
    @index_two_subgroups.each -> (subgroup)
      out.push(subgroup)
    out

  -> pair_stabilizer
    out = []
    @pair_stabilizer.each -> (element)
      out.push(element)
    out

  -> sextic_stabilizer
    out = []
    @sextic_stabilizer.each -> (element)
      out.push(element)
    out

  -> degree_twelve_stabilizer
    out = []
    @degree_twelve_stabilizer.each -> (element)
      out.push(element)
    out

  -> subgroup_contains_all?(subgroup, elements)
    keys = {}
    subgroup.elements.each -> (element)
      keys[element.key] = true
    elements.all? -> (element)
      keys.has_key?(element.key)

  -> recompute_containing_count(elements)
    count = 0
    @index_two_subgroups.each -> (subgroup)
      count += 1 if subgroup_contains_all?(subgroup, elements)
    count

  -> pair_quadratic_subfield_count
    @pair_quadratic_subfield_count

  -> sextic_quadratic_subfield_count
    @sextic_quadratic_subfield_count

  -> degree_twelve_quadratic_subfield_count
    @degree_twelve_quadratic_subfield_count

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?


+ GenusThreeThetaIncidence
  -> cayley_octad_labeling(even_characteristic)
    ThetaCayleyOctadLabeling.new(self, even_characteristic)


+ ThetaDeterminantalFixedSet
  -> fixed_octad_labelings
    out = []
    @fixed_characteristics.each -> (form)
      out.push(@incidence.cayley_octad_labeling(form))
    out

  -> unique_fixed_octad_action
    if @fixed_characteristics.size != 1
      raise "unique fixed octad action needs exactly one fixed even class"
    @incidence.cayley_octad_labeling(
      @fixed_characteristics[0]).induced_action(@subgroup)
