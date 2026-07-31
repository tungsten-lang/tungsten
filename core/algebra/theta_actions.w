# Exact symplectic actions on genus-three odd theta characteristics.
#
# The canonical 28/315 incidence is only the geometric reference module.
# Arithmetic descent additionally needs a Galois action on those 28 labels.
# This layer supplies two independently checkable pieces:
#
#   * matrices in Sp6(F2) and their induced incidence-preserving permutations;
#   * Frobenius cycle constraints obtained from exact factorization of a
#     certified degree-27 bitangent projection modulo a good prime.
#
# A cycle constraint is deliberately not called an arithmetic labeling.
# Matching factor degrees to a conjugacy class narrows the possible action but
# does not identify individual bitangent roots across different primes.

+ SymplecticF2MapCertificate
  -> new(@transformation)
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

  # Pairing preservation on basis vectors proves it on the whole space by
  # bilinearity. Nondegeneracy then also proves that the square matrix is
  # invertible.
  -> verify!
    return false if @transformation.class_name != "SymplecticF2Map"
    space = @transformation.space
    return false if space.class_name != "SymplecticF2Space"
    matrix = @transformation.matrix
    return false if matrix.size != space.dimension
    row = 0
    while row < matrix.size
      F2LinearAlgebra.validate_vector(
        matrix[row], space.dimension)
      row += 1

    left = 0
    while left < space.dimension
      source_left = space.vector(1 << left)
      image_left = @transformation.apply(source_left)
      right = 0
      while right < space.dimension
        source_right = space.vector(1 << right)
        image_right = @transformation.apply(source_right)
        image_pairing = space.pairing(
          image_left, image_right)
        source_pairing = space.pairing(
          source_left, source_right)
        return false if image_pairing != source_pairing
        right += 1
      left += 1
    true

  -> certified?
    verified?

  -> proof_kind
    :exact_symplectic_basis_identity

  -> kernel_checked?
    true


+ SymplecticF2Map
  -> new(@space, matrix)
    if @space.class_name != "SymplecticF2Space"
      raise "symplectic map needs a SymplecticF2Space"
    if matrix.class_name != "Array"
      raise "symplectic map matrix must be an Array"
    @matrix = F2LinearAlgebra.copy_matrix(matrix)
    @fixed_subspace_certificate_cache = nil
    @certificate_cache = SymplecticF2MapCertificate.new(self)
    if !@certificate_cache.verified?
      raise "matrix does not preserve the symplectic F2 pairing"

  -> space
    @space

  -> matrix
    F2LinearAlgebra.copy_matrix(@matrix)

  -> apply(vector)
    @space.validate(vector)
    out = []
    row = 0
    while row < @space.dimension
      out.push(F2LinearAlgebra.dot(@matrix[row], vector))
      row += 1
    out

  # The rational 2-torsion over a finite field is the fixed subspace of
  # Frobenius on the geometric 2-torsion module.  Expose the exact kernel of
  # self-I as a replay certificate so local descent can use its dimension as
  # an independently checked upper bound.
  -> fixed_subspace_certificate
    if @fixed_subspace_certificate_cache == nil
      system = F2LinearSystem.new(@space.dimension)
      row = 0
      while row < @space.dimension
        equation = []
        column = 0
        while column < @space.dimension
          value = @matrix[row][column]
          value = value ^ 1 if row == column
          equation.push(value)
          column += 1
        system.add_equation(
          equation, 0, "Frobenius-fixed 2-torsion")
        row += 1
      @fixed_subspace_certificate_cache = system.certificate
    @fixed_subspace_certificate_cache

  -> fixed_dimension
    fixed_subspace_certificate.kernel_dimension

  -> fixed_basis
    fixed_subspace_certificate.kernel_basis

  # self.compose(other)(x) = self(other(x)).
  -> compose(other)
    if other.class_name != "SymplecticF2Map" || other.space != @space
      raise "symplectic maps belong to different spaces"
    other_matrix = other.matrix
    matrix = []
    row = 0
    while row < @space.dimension
      output_row = []
      column = 0
      while column < @space.dimension
        value = 0
        inner = 0
        while inner < @space.dimension
          value = value ^ (
            @matrix[row][inner] & other_matrix[inner][column])
          inner += 1
        output_row.push(value)
        column += 1
      matrix.push(output_row)
      row += 1
    SymplecticF2Map.new(@space, matrix)

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> .identity(space)
    matrix = []
    row = 0
    while row < space.dimension
      output_row = []
      column = 0
      while column < space.dimension
        output_row.push(row == column ? 1 : 0)
        column += 1
      matrix.push(output_row)
      row += 1
    SymplecticF2Map.new(space, matrix)

  # T_v(x) = x + <x,v>v. In characteristic two every nonzero v defines a
  # symplectic transvection; v=0 gives the identity and is accepted.
  -> .transvection(space, vector)
    space.validate(vector)
    dual = []
    i = 0
    while i < space.genus
      dual.push(vector[space.genus + i])
      i += 1
    i = 0
    while i < space.genus
      dual.push(vector[i])
      i += 1

    matrix = []
    row = 0
    while row < space.dimension
      output_row = []
      column = 0
      while column < space.dimension
        value = row == column ? 1 : 0
        value = value ^ (vector[row] & dual[column])
        output_row.push(value)
        column += 1
      matrix.push(output_row)
      row += 1
    SymplecticF2Map.new(space, matrix)


+ GenusThreeThetaPermutationCertificate
  -> new(@theta_permutation)
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
    if @theta_permutation.class_name != "GenusThreeThetaPermutation"
      return false
    incidence = @theta_permutation.incidence
    return false if !incidence.certificate.verified?
    transformation = @theta_permutation.transformation
    return false if !transformation.certificate.verified?
    return false if transformation.space != incidence.space

    permutation = @theta_permutation.permutation
    expected = @theta_permutation.recompute_permutation
    return false if permutation.to_s != expected.to_s
    return false if permutation.size != 28
    seen = []
    i = 0
    while i < 28
      seen.push(false)
      i += 1
    i = 0
    while i < permutation.size
      image = permutation[i]
      return false if image < 0 || image >= 28
      return false if seen[image]
      seen[image] = true
      i += 1

    # A bijection that sends every one of the 315 syzygetic tetrads to a
    # syzygetic tetrad preserves the complete incidence relation.
    quadruples = incidence.syzygetic_quadruples
    i = 0
    while i < quadruples.size
      quadruple = quadruples[i]
      return false if !incidence.syzygetic_indices?(
        permutation[quadruple[0]],
        permutation[quadruple[1]],
        permutation[quadruple[2]],
        permutation[quadruple[3]])
      i += 1
    true

  -> certified?
    verified?

  -> proof_kind
    :exact_theta_incidence_permutation

  -> kernel_checked?
    true


+ GenusThreeThetaPermutation
  -> new(@incidence, @transformation)
    if @incidence.class_name != "GenusThreeThetaIncidence"
      raise "theta permutation needs genus-three incidence"
    if @transformation.class_name != "SymplecticF2Map"
      raise "theta permutation needs a symplectic F2 map"
    if @transformation.space != @incidence.space
      raise "theta permutation uses a different symplectic space"
    @permutation = recompute_permutation
    @certificate_cache = GenusThreeThetaPermutationCertificate.new(
      self)
    if !@certificate_cache.verified?
      raise "symplectic map did not induce a theta-incidence permutation"

  -> incidence
    @incidence

  -> transformation
    @transformation

  -> permutation
    F2LinearAlgebra.copy_vector(@permutation)

  -> apply(index)
    if !F2LinearAlgebra.integer?(index) || index < 0 || index >= 28
      raise "theta index is out of range"
    @permutation[index]

  # Pull q back along the symplectic map. Values on the six basis vectors
  # recover the unique characteristic of the resulting quadratic refinement.
  -> transformed_characteristic(form)
    space = @incidence.space
    left = []
    right = []
    i = 0
    while i < space.genus
      a_basis = space.vector(1 << i)
      b_basis = space.vector(1 << (space.genus + i))
      right.push(form.evaluate(
        @transformation.apply(a_basis)))
      left.push(form.evaluate(
        @transformation.apply(b_basis)))
      i += 1
    left + right

  -> recompute_permutation
    out = []
    forms = @incidence.odd_characteristics
    i = 0
    while i < forms.size
      characteristic = transformed_characteristic(forms[i])
      index = @incidence.odd_characteristic_index(characteristic)
      if index == nil
        raise "symplectic pullback did not preserve odd theta parity"
      out.push(index)
      i += 1
    out

  -> fixed_indices
    out = []
    i = 0
    while i < @permutation.size
      out.push(i) if @permutation[i] == i
      i += 1
    out

  -> cycle_lengths
    seen = []
    i = 0
    while i < @permutation.size
      seen.push(false)
      i += 1
    lengths = []
    seed = 0
    while seed < @permutation.size
      if !seen[seed]
        current = seed
        length = 0
        while !seen[current]
          seen[current] = true
          length += 1
          current = @permutation[current]
        lengths.push(length)
      seed += 1
    GenusThreeThetaPermutation.sort_integers(lengths)

  -> .sort_integers(values)
    out = F2LinearAlgebra.copy_vector(values)
    i = 1
    while i < out.size
      value = out[i]
      position = i
      while position > 0 && out[position - 1] > value
        out[position] = out[position - 1]
        position -= 1
      out[position] = value
      i += 1
    out

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?


+ ThetaPermutationActionCertificate
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
    return false if @action.class_name != "ThetaPermutationAction"
    incidence = @action.incidence
    return false if !incidence.certificate.verified?
    generators = @action.generators
    return false if generators.size == 0
    i = 0
    while i < generators.size
      return false if generators[i].incidence != incidence
      return false if !generators[i].certificate.verified?
      i += 1

    orbits = @action.orbits
    seen = []
    i = 0
    while i < 28
      seen.push(false)
      i += 1
    orbit_index = 0
    while orbit_index < orbits.size
      orbit = orbits[orbit_index]
      return false if orbit.size == 0
      i = 0
      while i < orbit.size
        point = orbit[i]
        return false if point < 0 || point >= 28
        return false if seen[point]
        seen[point] = true
        generator_index = 0
        while generator_index < generators.size
          image = generators[generator_index].apply(point)
          return false if !orbit.include?(image)
          generator_index += 1
        i += 1
      orbit_index += 1
    seen.all? -> item

  -> certified?
    verified?

  -> proof_kind
    :exact_finite_theta_action

  -> kernel_checked?
    true


+ ThetaPermutationAction
  -> new(@incidence, generators)
    if @incidence.class_name != "GenusThreeThetaIncidence"
      raise "theta action needs genus-three incidence"
    if generators.class_name != "Array" || generators.size == 0
      raise "theta action needs at least one generator"
    @generators = []
    generators.each -> (generator)
      if generator.class_name != "GenusThreeThetaPermutation"
        raise "theta action generators must be theta permutations"
      if generator.incidence != @incidence
        raise "theta action generator uses a different incidence"
      @generators.push(generator)
    @orbits = compute_orbits
    @certificate_cache = ThetaPermutationActionCertificate.new(self)
    if !@certificate_cache.verified?
      raise "theta permutation action failed certification"

  -> incidence
    @incidence

  -> generators
    out = []
    @generators.each -> (generator)
      out.push(generator)
    out

  -> compute_orbits
    seen = []
    i = 0
    while i < 28
      seen.push(false)
      i += 1
    out = []
    seed = 0
    while seed < 28
      if !seen[seed]
        orbit = [seed]
        seen[seed] = true
        cursor = 0
        while cursor < orbit.size
          point = orbit[cursor]
          generator_index = 0
          while generator_index < @generators.size
            image = @generators[generator_index].apply(point)
            if !seen[image]
              seen[image] = true
              orbit.push(image)
            generator_index += 1
          cursor += 1
        out.push(GenusThreeThetaPermutation.sort_integers(
          orbit))
      seed += 1
    out

  -> orbits
    F2LinearAlgebra.copy_matrix(@orbits)

  -> orbit_sizes
    sizes = []
    i = 0
    while i < @orbits.size
      sizes.push(@orbits[i].size)
      i += 1
    GenusThreeThetaPermutation.sort_integers(sizes)

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?


+ ThetaBitangentFrobeniusConstraintCertificate
  -> new(@constraint)
    @verified_cache = nil

  -> theorem
    "irreducible factor degrees of a squarefree polynomial over a finite field are the Frobenius cycle lengths on its geometric roots"

  -> theorem_reference
    "finite-field Frobenius orbit and irreducible-factor correspondence"

  -> proof_kind
    :trusted_theorem_import

  -> kernel_checked?
    false

  -> finite_replay_checked?
    true

  -> arithmetic_labeling_checked?
    false

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
    if @constraint.class_name != "ThetaBitangentFrobeniusConstraint"
      return false
    scheme = @constraint.scheme_certificate
    expected_scheme_class = "PlaneQuarticBitangentSchemeCertificate"
    return false if scheme.class_name != expected_scheme_class
    return false if !scheme.verified?
    return false if scheme.etale_degree != 27
    prime = @constraint.prime
    return false if !F2LinearAlgebra.integer?(prime)
    return false if prime < 2 || !prime.prime?

    reduction = @constraint.reduced_projection
    return false if reduction.ring.field.characteristic != prime
    return false if reduction.degree != 27
    return false if reduction.gcd(
      reduction.derivative(0)).degree != 0
    factorization = @constraint.factorization
    return false if factorization.polynomial != reduction
    return false if !factorization.certificate.verified?

    degrees = @constraint.factor_degrees
    total = 0
    i = 0
    while i < degrees.size
      return false if degrees[i] <= 0
      total += degrees[i]
      i += 1
    return false if total != 27

    theta_permutation = @constraint.theta_permutation
    return false if !theta_permutation.certificate.verified?
    distinguished = @constraint.distinguished_theta_index
    return false if distinguished < 0 || distinguished >= 28
    fixed_image = theta_permutation.apply(distinguished)
    return false if fixed_image != distinguished
    theta_cycles = theta_permutation.cycle_lengths.to_s
    theta_cycles == @constraint.expected_cycle_lengths.to_s

  -> certified?
    verified?


+ ThetaBitangentFrobeniusConstraint
  -> new(@scheme_certificate, @prime, @theta_permutation, @distinguished_theta_index, @search_limit = 250_000)
    expected_scheme_class = "PlaneQuarticBitangentSchemeCertificate"
    if @scheme_certificate.class_name != expected_scheme_class
      raise "theta Frobenius constraint needs a bitangent-scheme certificate"
    if !@scheme_certificate.verified?
      raise "theta Frobenius constraint needs a verified bitangent scheme"
    if @theta_permutation.class_name != "GenusThreeThetaPermutation"
      raise "theta Frobenius constraint needs a theta permutation"
    @reduced_projection = reduce_projection
    if @reduced_projection.degree != 27
      raise "bitangent projection loses degree at this prime"
    if @reduced_projection.gcd(
         @reduced_projection.derivative(0)).degree != 0
      raise "bitangent projection is ramified at this prime"
    @factorization = @reduced_projection.factor_with_certificate(
      @search_limit)
    @certificate_cache = ThetaBitangentFrobeniusConstraintCertificate.new(
      self)
    if !@certificate_cache.verified?
      raise "theta permutation has the wrong Frobenius cycle type"

  -> scheme_certificate
    @scheme_certificate

  -> prime
    @prime

  -> theta_permutation
    @theta_permutation

  -> distinguished_theta_index
    @distinguished_theta_index

  -> reduced_projection
    Polynomial.new(
      @reduced_projection.ring,
      @reduced_projection.terms)

  -> factorization
    @factorization

  -> factor_degrees
    out = []
    factors = @factorization.factors
    i = 0
    while i < factors.size
      out.push(factors[i].degree) if factors[i].degree > 0
      i += 1
    GenusThreeThetaPermutation.sort_integers(out)

  -> expected_cycle_lengths
    GenusThreeThetaPermutation.sort_integers(
      [1] + factor_degrees)

  -> reduce_projection
    source = @scheme_certificate.projection_polynomial
    field = FiniteField.new(@prime)
    ring = PolynomialRing.new(
      source.ring.names, field, :lex)
    terms = []
    source.each_term -> (coefficient, exponents)
      reduced = field.embed_from(
        source.ring.field, coefficient)
      terms.push([reduced, exponents])
    Polynomial.new(ring, terms)

  -> cycle_lengths
    @theta_permutation.cycle_lengths

  -> constraint_only?
    true

  -> arithmetic_labeling_certified?
    false

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?


+ PlaneQuarticTwoDescentSetup
  -> certify_theta_frobenius_constraint(prime, theta_permutation, distinguished_theta_index, search_limit = 250_000)
    if @bitangent_scheme_certificate == nil
      certify_bitangent_scheme
    constraint = ThetaBitangentFrobeniusConstraint.new(
      @bitangent_scheme_certificate, prime,
      theta_permutation, distinguished_theta_index,
      search_limit)
    if @theta_frobenius_constraints == nil
      @theta_frobenius_constraints = []
    @theta_frobenius_constraints.push(constraint)
    constraint

  -> theta_frobenius_constraints
    out = []
    if @theta_frobenius_constraints != nil
      @theta_frobenius_constraints.each -> (constraint)
        out.push(constraint)
    out
