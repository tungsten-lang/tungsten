# Exact finite permutation groups.
#
# This is a deliberately small, replay-oriented layer.  A group is generated
# by explicit permutations and exhausted by breadth-first closure.  It is
# suitable for the small Galois and incidence groups used by certificates;
# callers must provide an element limit rather than accidentally attempting
# to materialize a huge group.

+ FinitePermutation
  -> new(images)
    if images.class_name != "Array"
      raise "finite permutation images must be an Array"
    @images = F2LinearAlgebra.copy_vector(images)
    validate!
    @key_cache = @images.join(",")
    @inverse_cache = nil
    @cycle_lengths_cache = nil

  -> validate!
    seen = []
    @images.size.times -> seen.push(false)
    i = 0
    while i < @images.size
      image = @images[i]
      if !F2LinearAlgebra.integer?(image)
        raise "finite permutation image must be an integer"
      if image < 0 || image >= @images.size
        raise "finite permutation image is out of range"
      if seen[image]
        raise "finite permutation images must be bijective"
      seen[image] = true
      i += 1
    true

  -> degree
    @images.size

  -> images
    F2LinearAlgebra.copy_vector(@images)

  -> apply(index)
    if !F2LinearAlgebra.integer?(index) || index < 0 || index >= degree
      raise "finite permutation point is out of range"
    @images[index]

  # self.compose(other)(x) = self(other(x)).
  -> compose(other)
    if other.class_name != "FinitePermutation" || other.degree != degree
      raise "finite permutations have different degrees"
    out = []
    i = 0
    while i < degree
      out.push(@images[other.apply(i)])
      i += 1
    FinitePermutation.new(out)

  -> inverse
    if @inverse_cache == nil
      out = []
      degree.times -> out.push(0)
      i = 0
      while i < degree
        out[@images[i]] = i
        i += 1
      @inverse_cache = FinitePermutation.new(out)
    @inverse_cache

  -> **(exponent)
    if !F2LinearAlgebra.integer?(exponent)
      raise "finite permutation exponent must be an integer"
    return inverse**(0 - exponent) if exponent < 0
    result = FinitePermutation.identity(degree)
    factor = self
    remaining = exponent
    while remaining > 0
      result = result.compose(factor) if remaining.odd?
      remaining = remaining / 2
      factor = factor.compose(factor) if remaining > 0
    result

  -> cycle_lengths
    if @cycle_lengths_cache != nil
      return F2LinearAlgebra.copy_vector(
        @cycle_lengths_cache)
    seen = []
    degree.times -> seen.push(false)
    lengths = []
    seed = 0
    while seed < degree
      if !seen[seed]
        current = seed
        length = 0
        while !seen[current]
          seen[current] = true
          length += 1
          current = @images[current]
        lengths.push(length)
      seed += 1
    @cycle_lengths_cache = GenusThreeThetaPermutation.sort_integers(
      lengths)
    F2LinearAlgebra.copy_vector(@cycle_lengths_cache)

  -> order
    result = 1
    cycle_lengths.each -> (length)
      result = result / result.gcd(length) * length
    result

  -> identity?
    i = 0
    while i < degree
      return false if @images[i] != i
      i += 1
    true

  -> eql?(other)
    other.class_name == "FinitePermutation" && @images.to_s == other.images.to_s

  -> ==(other)
    eql?(other)

  -> key
    @key_cache

  -> .identity(degree)
    images = []
    i = 0
    while i < degree
      images.push(i)
      i += 1
    FinitePermutation.new(images)


+ FinitePermutationGroupCertificate
  -> new(@group)
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
    return false if @group.class_name != "FinitePermutationGroup"
    generators = @group.generators
    return false if generators.size == 0
    degree = @group.degree
    i = 0
    while i < generators.size
      return false if generators[i].degree != degree
      i += 1

    elements = @group.elements
    return false if elements.size == 0
    return false if !elements[0].identity?
    keys = {}
    i = 0
    while i < elements.size
      return false if elements[i].degree != degree
      key = elements[i].key
      return false if keys.has_key?(key)
      keys[key] = true
      i += 1

    # Replay reachability using the supplied generators and their inverses.
    # Every listed element must be reached and every generator edge must stay
    # in the list.  This proves the list is exactly the generated subgroup,
    # while avoiding a quadratic all-pairs multiplication table.
    steps = []
    generators.each -> (generator)
      steps.push(generator)
      steps.push(generator.inverse)
      return false if !keys.has_key?(generator.key)
    reached = {}
    reached[elements[0].key] = true
    queue = [elements[0]]
    cursor = 0
    while cursor < queue.size
      steps.each -> (step)
        product = step.compose(queue[cursor])
        key = product.key
        return false if !keys.has_key?(key)
        if !reached.has_key?(key)
          reached[key] = true
          queue.push(product)
      cursor += 1
    return false if reached.size != elements.size

    i = 0
    while i < elements.size
      return false if !keys.has_key?(elements[i].inverse.key)
      i += 1
    true

  -> certified?
    verified?

  -> proof_kind
    :exact_finite_group_closure

  -> kernel_checked?
    true


+ FinitePermutationGroup
  -> new(generators, element_limit = 100_000)
    if generators.class_name != "Array" || generators.size == 0
      raise "finite permutation group needs generators"
    @generators = []
    generators.each -> (generator)
      if generator.class_name == "FinitePermutation"
        @generators.push(generator)
      else
        @generators.push(FinitePermutation.new(generator))
    @degree = @generators[0].degree
    @generators.each -> (generator)
      if generator.degree != @degree
        raise "finite permutation group generators have different degrees"
    @element_limit = element_limit
    @elements = enumerate_elements
    @certificate_cache = FinitePermutationGroupCertificate.new(self)
    if !@certificate_cache.verified?
      raise "finite permutation group failed closure certification"

  -> degree
    @degree

  -> generators
    out = []
    @generators.each -> out.push(item)
    out

  -> elements
    out = []
    @elements.each -> out.push(item)
    out

  -> order
    @elements.size

  -> enumerate_elements
    steps = []
    @generators.each -> (generator)
      steps.push(generator)
      steps.push(generator.inverse)
    identity = FinitePermutation.identity(@degree)
    out = [identity]
    seen = {}
    seen[identity.key] = true
    cursor = 0
    while cursor < out.size
      steps.each -> (step)
        candidate = step.compose(out[cursor])
        if !seen.has_key?(candidate.key)
          if out.size >= @element_limit
            raise "finite permutation group element limit exceeded"
          seen[candidate.key] = true
          out.push(candidate)
      cursor += 1
    out

  -> orbits
    seen = []
    @degree.times -> seen.push(false)
    out = []
    seed = 0
    while seed < @degree
      if !seen[seed]
        orbit = []
        @elements.each -> (element)
          image = element.apply(seed)
          if !seen[image]
            seen[image] = true
            orbit.push(image)
        out.push(GenusThreeThetaPermutation.sort_integers(orbit))
      seed += 1
    out

  -> orbit_sizes
    sizes = []
    orbits.each -> sizes.push(item.size)
    GenusThreeThetaPermutation.sort_integers(sizes)

  -> stabilizer_elements(point)
    out = []
    @elements.each -> (element)
      out.push(element) if element.apply(point) == point
    out

  -> stabilizer_orbits(point)
    stabilizer = stabilizer_elements(point)
    seen = []
    @degree.times -> seen.push(false)
    out = []
    seed = 0
    while seed < @degree
      if !seen[seed]
        orbit = []
        stabilizer.each -> (element)
          image = element.apply(seed)
          if !seen[image]
            seen[image] = true
            orbit.push(image)
        out.push(GenusThreeThetaPermutation.sort_integers(orbit))
      seed += 1
    out

  -> stabilizer_orbit_sizes(point)
    sizes = []
    stabilizer_orbits(point).each -> sizes.push(item.size)
    GenusThreeThetaPermutation.sort_integers(sizes)


+ FinitePermutationSubgroupArithmetic
  -> .key(parent, subgroup)
    members = {}
    subgroup.elements.each -> (element)
      members[element.key] = true
    bits = []
    parent.elements.each -> (element)
      bits.push(members.has_key?(element.key) ? 1 : 0)
    bits.join("")

  -> .generated(parent, subgroup, element)
    generators = subgroup.generators
    generators.push(element)
    FinitePermutationGroup.new(
      generators, parent.order)


+ FinitePermutationSubgroupEnumerationCertificate
  -> new(@enumeration)
    @verified_cache = nil

  -> theorem
    "closure under adjoining every parent-group element exhausts all finite subgroups"

  -> theorem_reference
    "finite subgroup generation"

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
    expected = "FinitePermutationSubgroupEnumeration"
    return false if @enumeration.class_name != expected
    parent = @enumeration.parent
    return false if !parent.certificate.verified?
    subgroups = @enumeration.subgroups
    return false if subgroups.size == 0
    parent_keys = {}
    parent.elements.each -> (element)
      parent_keys[element.key] = true
    keys = {}
    subgroups.each -> (subgroup)
      return false if !subgroup.certificate.verified?
      subgroup.elements.each -> (element)
        return false if !parent_keys.has_key?(element.key)
      key = FinitePermutationSubgroupArithmetic.key(
        parent, subgroup)
      return false if keys.has_key?(key)
      keys[key] = true
    return false if subgroups[0].order != 1

    # Any subgroup has a finite generating sequence. Starting at the identity,
    # closure under adjoining each next generator follows edges checked here,
    # so every subgroup of the parent occurs in the supplied list.
    subgroups.each -> (subgroup)
      subgroup_members = {}
      subgroup.elements.each -> (element)
        subgroup_members[element.key] = true
      parent.elements.each -> (element)
        if !subgroup_members.has_key?(element.key)
          generated = (
            FinitePermutationSubgroupArithmetic.generated(
              parent, subgroup, element))
          key = FinitePermutationSubgroupArithmetic.key(
            parent, generated)
          return false if !keys.has_key?(key)
    true

  -> certified?
    verified?

  -> proof_kind
    :exact_finite_subgroup_exhaustion

  -> kernel_checked?
    true


+ FinitePermutationSubgroupEnumeration
  -> new(@parent, subgroup_limit = 10_000)
    if @parent.class_name != "FinitePermutationGroup"
      raise "subgroup enumeration needs a finite permutation group"
    if !@parent.certificate.verified?
      raise "subgroup enumeration parent is uncertified"
    identity = FinitePermutation.identity(
      @parent.degree)
    first = FinitePermutationGroup.new(
      [identity], @parent.order)
    @subgroups = [first]
    seen = {}
    seen[FinitePermutationSubgroupArithmetic.key(
      @parent, first)] = true
    cursor = 0
    while cursor < @subgroups.size
      subgroup = @subgroups[cursor]
      members = {}
      subgroup.elements.each -> (element)
        members[element.key] = true
      @parent.elements.each -> (element)
        if !members.has_key?(element.key)
          generated = (
            FinitePermutationSubgroupArithmetic.generated(
              @parent, subgroup, element))
          key = FinitePermutationSubgroupArithmetic.key(
            @parent, generated)
          if !seen.has_key?(key)
            if @subgroups.size >= subgroup_limit
              raise "finite permutation subgroup limit exceeded"
            seen[key] = true
            @subgroups.push(generated)
      cursor += 1
    @certificate_cache = (
      FinitePermutationSubgroupEnumerationCertificate.new(
        self))
    if !@certificate_cache.verified?
      raise "finite permutation subgroup enumeration failed certification"

  -> parent
    @parent

  -> subgroups
    out = []
    @subgroups.each -> out.push(item)
    out

  -> size
    @subgroups.size

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?


+ FinitePermutationGroup
  -> subgroup_enumeration(subgroup_limit = 10_000)
    FinitePermutationSubgroupEnumeration.new(
      self, subgroup_limit)

  -> subgroups(subgroup_limit = 10_000)
    subgroup_enumeration(subgroup_limit).subgroups

  -> contains_cycle_lengths?(lengths)
    target = GenusThreeThetaPermutation.sort_integers(lengths).to_s
    @elements.any? -> item.cycle_lengths.to_s == target

  -> cycle_types
    seen = {}
    out = []
    @elements.each -> (element)
      lengths = element.cycle_lengths
      key = lengths.to_s
      if !seen.has_key?(key)
        seen[key] = true
        out.push(lengths)
    out

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?
