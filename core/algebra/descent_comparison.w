# Exact finite comparison modules for explicit descent.
#
# For a true descent setup, Bruin--Poonen--Stoll attach the exact sequence
#
#   0 -> A[phi] -> E^dual -> R^dual -> 0.
#
# The kernel of the global cohomology map is the finite group
#
#   K = R^dual(k) / q(E^dual(k)).
#
# When the Galois action is given by explicit F2 matrices, K is the quotient
# of the fixed space of E^dual/A[phi] by the image of the fixed space of
# E^dual.  This file computes that quotient, the analogous local W_v
# dimensions, the localization of K, and the resulting one-sided rank bound
# with replayable F2 certificates.  The rank-bound constructor deliberately
# requires a separately arithmetic-certified explicit Selmer intersection.

+ F2QuotientInvariantArithmetic
  -> .zero_vector(width)
    out = []
    width.times -> out.push(0)
    out

  -> .apply(matrix, vector)
    out = []
    row = 0
    while row < matrix.size
      out.push(F2LinearAlgebra.dot(matrix[row], vector))
      row += 1
    out

  -> .difference_matrix(matrix)
    out = F2LinearAlgebra.copy_matrix(matrix)
    row = 0
    while row < out.size
      out[row][row] = out[row][row] ^ 1
      row += 1
    out

  -> .left_multiply(row_vector, matrix)
    out = []
    column = 0
    while column < matrix.size
      value = 0
      row = 0
      while row < matrix.size
        value = value ^ (
          row_vector[row] & matrix[row][column])
        row += 1
      out.push(value)
      column += 1
    out

  -> .span_certificate(width, basis)
    system = F2LinearSystem.new(width)
    basis.each -> (vector)
      system.add_equation(vector, 0, "F2 span vector")
    system.certificate

  -> .span_rank(width, basis)
    F2QuotientInvariantArithmetic.span_certificate(
      width, basis).rank

  -> .in_span?(width, basis, vector)
    old_rank = F2QuotientInvariantArithmetic.span_rank(
      width, basis)
    extended = F2LinearAlgebra.copy_matrix(basis)
    extended.push(F2LinearAlgebra.copy_vector(vector))
    F2QuotientInvariantArithmetic.span_rank(
      width, extended) == old_rank

  -> .add(left, right)
    if left.size != right.size
      raise "F2 vector addition width mismatch"
    out = []
    i = 0
    while i < left.size
      out.push(left[i] ^ right[i])
      i += 1
    out

  -> .combine(coefficients, basis, width)
    if coefficients.size != basis.size
      raise "F2 basis coefficient count mismatch"
    out = F2QuotientInvariantArithmetic.zero_vector(width)
    i = 0
    while i < basis.size
      if coefficients[i] == 1
        out = F2QuotientInvariantArithmetic.add(
          out, basis[i])
      i += 1
    out


+ F2QuotientInvariantCertificate
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
    expected = "F2QuotientInvariantComputation"
    return false if @computation.class_name != expected
    return false if !@computation.subspace_span_certificate.verified?
    return false if !@computation.ambient_fixed_certificate.verified?
    return false if !@computation.subspace_fixed_certificate.verified?
    certificate = @computation.quotient_fixed_preimage_certificate
    return false if !certificate.verified?
    return false if !@computation.subspace_invariant?

    quotient_fixed_dimension = (
      certificate.kernel_dimension -
      @computation.subspace_dimension)
    fixed_image_dimension = (
      @computation.ambient_fixed_dimension -
      @computation.subspace_fixed_dimension)
    expected_dimension = (
      quotient_fixed_dimension - fixed_image_dimension)
    return false if expected_dimension != @computation.dimension
    return false if expected_dimension < 0

    width = @computation.width
    denominator = @computation.subspace_basis
    @computation.ambient_fixed_basis.each -> (vector)
      denominator.push(vector)
    denominator_rank = (
      F2QuotientInvariantArithmetic.span_rank(
        width, denominator))
    extended = F2LinearAlgebra.copy_matrix(denominator)
    @computation.representatives.each -> (vector)
      return false if !F2LinearAlgebra.satisfies?(
        certificate.matrix,
        certificate.source_right_hand_side,
        vector)
      extended.push(vector)
    return false if (
      F2QuotientInvariantArithmetic.span_rank(
        width, extended) !=
      denominator_rank + @computation.dimension)
    return false if @computation.representatives.size != (
      @computation.dimension)
    F2QuotientInvariantArithmetic.span_rank(
      width, extended) == certificate.kernel_dimension

  -> certified?
    verified?

  -> proof_kind
    :exact_f2_quotient_invariants

  -> kernel_checked?
    false

  -> arithmetic_replay_checked?
    true


+ F2QuotientInvariantComputation
  -> new(@width, subspace_basis, action_matrices)
    if !F2LinearAlgebra.integer?(@width) || @width < 0
      raise "F2 quotient ambient width must be nonnegative"
    @subspace_basis = F2LinearAlgebra.copy_matrix(
      subspace_basis)
    @action_matrices = []
    action_matrices.each -> (matrix)
      @action_matrices.push(
        F2LinearAlgebra.copy_matrix(matrix))
    validate_inputs!
    build_certificates!
    @representatives = compute_representatives
    @certificate_cache = F2QuotientInvariantCertificate.new(
      self)
    if !@certificate_cache.verified?
      raise "F2 quotient-invariant computation failed replay"

  -> validate_inputs!
    @subspace_basis.each -> (vector)
      F2LinearAlgebra.validate_vector(vector, @width)
    @action_matrices.each -> (matrix)
      if matrix.size != @width
        raise "F2 quotient action matrix height mismatch"
      matrix.each -> (row)
        F2LinearAlgebra.validate_vector(row, @width)
      certificate = F2QuotientInvariantArithmetic.span_certificate(
        @width, matrix)
      if certificate.rank != @width
        raise "F2 quotient action matrix must be invertible"
    if F2QuotientInvariantArithmetic.span_rank(
         @width, @subspace_basis) != @subspace_basis.size
      raise "F2 quotient subspace basis is dependent"
    true

  -> build_certificates!
    @subspace_span_certificate = (
      F2QuotientInvariantArithmetic.span_certificate(
        @width, @subspace_basis))
    @annihilator_basis = (
      @subspace_span_certificate.kernel_basis)

    ambient_fixed = F2LinearSystem.new(@width)
    quotient_fixed = F2LinearSystem.new(@width)
    @action_matrices.each -> (matrix)
      difference = (
        F2QuotientInvariantArithmetic.difference_matrix(
          matrix))
      difference.each -> (row)
        ambient_fixed.add_equation(
          row, 0, "ambient fixed vector")
      @annihilator_basis.each -> (annihilator)
        quotient_fixed.add_equation(
          F2QuotientInvariantArithmetic.left_multiply(
            annihilator, difference),
          0, "fixed modulo subspace")
    @ambient_fixed_certificate = ambient_fixed.certificate
    @quotient_fixed_preimage_certificate = (
      quotient_fixed.certificate)

    subspace_fixed = F2LinearSystem.new(
      @subspace_basis.size)
    @action_matrices.each -> (matrix)
      differences = []
      @subspace_basis.each -> (basis_vector)
        image = F2QuotientInvariantArithmetic.apply(
          matrix, basis_vector)
        differences.push(
          F2QuotientInvariantArithmetic.add(
            image, basis_vector))
      coordinate = 0
      while coordinate < @width
        equation = []
        basis_index = 0
        while basis_index < differences.size
          equation.push(
            differences[basis_index][coordinate])
          basis_index += 1
        subspace_fixed.add_equation(
          equation, 0, "fixed subspace vector")
        coordinate += 1
    @subspace_fixed_certificate = subspace_fixed.certificate
    true

  -> compute_representatives
    denominator = F2LinearAlgebra.copy_matrix(
      @subspace_basis)
    ambient_fixed_basis.each -> (vector)
      denominator.push(vector)
    current_rank = F2QuotientInvariantArithmetic.span_rank(
      @width, denominator)
    out = []
    quotient_fixed_preimage_basis.each -> (candidate)
      extended = F2LinearAlgebra.copy_matrix(denominator)
      out.each -> (vector)
        extended.push(vector)
      extended.push(candidate)
      rank = F2QuotientInvariantArithmetic.span_rank(
        @width, extended)
      if rank > current_rank + out.size
        out.push(candidate)
    out

  -> width
    @width

  -> subspace_basis
    F2LinearAlgebra.copy_matrix(@subspace_basis)

  -> action_matrices
    F2LinearAlgebra.copy_matrix(@action_matrices)

  -> subspace_span_certificate
    @subspace_span_certificate

  -> ambient_fixed_certificate
    @ambient_fixed_certificate

  -> subspace_fixed_certificate
    @subspace_fixed_certificate

  -> quotient_fixed_preimage_certificate
    @quotient_fixed_preimage_certificate

  -> subspace_dimension
    @subspace_span_certificate.rank

  -> ambient_fixed_dimension
    @ambient_fixed_certificate.kernel_dimension

  -> ambient_fixed_basis
    @ambient_fixed_certificate.kernel_basis

  -> subspace_fixed_dimension
    @subspace_fixed_certificate.kernel_dimension

  -> quotient_fixed_preimage_dimension
    @quotient_fixed_preimage_certificate.kernel_dimension

  -> quotient_fixed_preimage_basis
    @quotient_fixed_preimage_certificate.kernel_basis

  -> quotient_fixed_dimension
    quotient_fixed_preimage_dimension - subspace_dimension

  -> fixed_image_dimension
    ambient_fixed_dimension - subspace_fixed_dimension

  -> dimension
    quotient_fixed_dimension - fixed_image_dimension

  -> representatives
    F2LinearAlgebra.copy_matrix(@representatives)

  -> denominator_basis
    out = F2LinearAlgebra.copy_matrix(
      @subspace_basis)
    ambient_fixed_basis.each -> (vector)
      out.push(vector)
    out

  -> represents_quotient_fixed_class?(vector)
    F2LinearAlgebra.validate_vector(vector, @width)
    certificate = @quotient_fixed_preimage_certificate
    F2LinearAlgebra.satisfies?(
      certificate.matrix,
      certificate.source_right_hand_side,
      vector)

  -> zero_class?(vector)
    return false if !represents_quotient_fixed_class?(vector)
    F2QuotientInvariantArithmetic.in_span?(
      @width, denominator_basis, vector)

  -> subspace_invariant?
    @action_matrices.each -> (matrix)
      @subspace_basis.each -> (vector)
        image = F2QuotientInvariantArithmetic.apply(
          matrix, vector)
        return false if !F2QuotientInvariantArithmetic.in_span?(
          @width, @subspace_basis, image)
    true

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?


+ PlaneQuarticBPSTrueComparisonCertificate
  -> new(@comparison)
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
    expected = "PlaneQuarticBPSTrueComparison"
    return false if @comparison.class_name != expected
    source = @comparison.theta_galois_certificate
    return false if !source.certified?
    candidate = source.identified_candidate
    return false if candidate == nil
    return false if candidate.group.degree != 28
    return false if candidate.fixed_points.size != 1
    return false if !@comparison.finite_computation.certified?
    return false if @comparison.true_coordinate_count != 27
    return false if @comparison.geometric_torsion_dimension != 6
    return false if @comparison.rational_two_torsion_dimension < 0
    @comparison.finite_computation.subspace_dimension == 6

  -> certified?
    verified?

  -> proof_kind
    :bps_true_finite_comparison_module

  -> kernel_checked?
    true

  -> theorem
    "for a true descent setup, K = R^dual(k) / q(E^dual(k))"

  -> theorem_reference
    "Bruin-Poonen-Stoll equations (13)-(16) and Theorem 10.14"


+ PlaneQuarticBPSTrueComparison
  -> new(@theta_galois_certificate)
    if !@theta_galois_certificate.respond_to?(
         "identified_candidate")
      raise "BPS comparison needs an identified theta subgroup"
    if !@theta_galois_certificate.certified?
      raise "BPS comparison theta subgroup is uncertified"
    @candidate = @theta_galois_certificate.identified_candidate
    if @candidate == nil
      raise "BPS comparison theta subgroup is not unique"
    @incidence = @candidate.incidence
    fixed = @candidate.fixed_points
    if fixed.size != 1
      raise "BPS true bitangent setup needs one rational theta characteristic"
    @distinguished_theta_index = fixed[0]
    @true_theta_indices = []
    index = 0
    while index < 28
      @true_theta_indices.push(index) if (
        index != @distinguished_theta_index)
      index += 1
    @alpha_basis = build_alpha_basis
    @action_matrices = build_action_matrices(
      @candidate.group)
    @finite_computation = F2QuotientInvariantComputation.new(
      @true_theta_indices.size,
      @alpha_basis, @action_matrices)
    @fixed_space = @candidate.group.theta_fixed_space(
      @incidence)
    @certificate_cache = (
      PlaneQuarticBPSTrueComparisonCertificate.new(self))
    if !@certificate_cache.verified?
      raise "plane-quartic BPS finite comparison failed"

  -> coordinate_position(theta_index)
    position = 0
    while position < @true_theta_indices.size
      return position if (
        @true_theta_indices[position] == theta_index)
      position += 1
    nil

  # The dual of e_Q |-> theta_Q-theta_0 sends v in J[2] to the vector
  # (<v, theta_Q-theta_0>)_Q in the 27-coordinate permutation module.
  -> build_alpha_basis
    out = []
    space = @incidence.space
    base_label = @incidence.odd_label(
      @distinguished_theta_index)
    bit = 0
    while bit < space.dimension
      torsion = space.vector(1 << bit)
      vector = []
      @true_theta_indices.each -> (theta_index)
        difference = space.vector(
          @incidence.odd_label(theta_index) ^
          base_label)
        vector.push(space.pairing(
          torsion, difference))
      out.push(vector)
      bit += 1
    out

  -> build_action_matrices(group)
    if group.class_name != "FinitePermutationGroup"
      raise "BPS comparison action needs a finite permutation group"
    if group.degree != 28 || !group.certificate.verified?
      raise "BPS comparison action needs a certified degree-28 group"
    out = []
    group.generators.each -> (generator)
      matrix = []
      @true_theta_indices.size.times ->
        matrix.push(
          F2QuotientInvariantArithmetic.zero_vector(
            @true_theta_indices.size))
      source = 0
      while source < @true_theta_indices.size
        image_theta = generator.apply(
          @true_theta_indices[source])
        image = coordinate_position(image_theta)
        if image == nil
          raise "theta action moves a true coordinate to the distinguished one"
        matrix[image][source] = 1
        source += 1
      out.push(matrix)
    out

  -> theta_galois_certificate
    @theta_galois_certificate

  -> candidate
    @candidate

  -> distinguished_theta_index
    @distinguished_theta_index

  -> true_theta_indices
    F2LinearAlgebra.copy_vector(@true_theta_indices)

  -> true_coordinate_count
    @true_theta_indices.size

  -> geometric_torsion_dimension
    @alpha_basis.size

  -> alpha_basis
    F2LinearAlgebra.copy_matrix(@alpha_basis)

  -> action_matrices
    F2LinearAlgebra.copy_matrix(@action_matrices)

  -> finite_computation
    @finite_computation

  -> finite_computation_for_subgroup(subgroup)
    finite_computation_for_theta_subgroup(
      subgroup, @distinguished_theta_index)

  -> finite_computation_for_theta_subgroup(
       subgroup, distinguished_theta_index)
    true_indices = []
    index = 0
    while index < 28
      true_indices.push(index) if (
        index != distinguished_theta_index)
      index += 1
    base_label = @incidence.odd_label(
      distinguished_theta_index)
    alpha_basis = []
    bit = 0
    while bit < @incidence.space.dimension
      torsion = @incidence.space.vector(1 << bit)
      vector = []
      true_indices.each -> (theta_index)
        difference = @incidence.space.vector(
          @incidence.odd_label(theta_index) ^
          base_label)
        vector.push(@incidence.space.pairing(
          torsion, difference))
      alpha_basis.push(vector)
      bit += 1

    action_matrices = []
    subgroup.generators.each -> (generator)
      matrix = []
      true_indices.size.times ->
        matrix.push(
          F2QuotientInvariantArithmetic.zero_vector(
            true_indices.size))
      source = 0
      while source < true_indices.size
        image_theta = generator.apply(
          true_indices[source])
        image = true_indices.index(image_theta)
        if image == nil
          raise "local theta action moves a true coordinate to the distinguished one"
        matrix[image][source] = 1
        source += 1
      action_matrices.push(matrix)
    F2QuotientInvariantComputation.new(
      true_indices.size,
      alpha_basis,
      action_matrices)

  -> rational_two_torsion_fixed_space
    @fixed_space

  -> rational_two_torsion_dimension
    @fixed_space.dimension

  -> comparison_kernel_dimension
    @finite_computation.dimension

  -> comparison_kernel_representatives
    @finite_computation.representatives

  # Exact arithmetic subdegrees identify the subgroup up to conjugacy.  That
  # is sufficient for invariant dimensions even though it does not label the
  # 27 characteristic-zero bitangents individually.
  -> arithmetic_galois_certified?
    method = "global_theta_galois_subgroup_certified?"
    supported = @theta_galois_certificate.respond_to?(method)
    supported && @theta_galois_certificate.global_theta_galois_subgroup_certified?

  -> arithmetic_certified?
    arithmetic_galois_certified? && certified?

  -> finite_only?
    !arithmetic_galois_certified?

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> bps_theorem_10_14_complete?
    false

  -> remaining_obligations
    [
      "assemble the complete local images into one arithmetic-certified explicit Selmer intersection",
      "supply a certified local comparison proving ker(kappa) = 0",
      "construct the BPS Theorem 10.14 rank-bound certificate"
    ]

  -> local_comparison(local_theta_dimension, local_image)
    PlaneQuarticBPSLocalComparison.new(
      self, local_theta_dimension, local_image)

  -> good_reduction_local_comparison(theta_fiber,
                                     local_image)
    PlaneQuarticBPSGoodReductionLocalComparison.new(
      self, theta_fiber, local_image)


+ PlaneQuarticBPSLocalComparisonCertificate
  -> new(@comparison)
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
    expected = "PlaneQuarticBPSLocalComparison"
    return false if @comparison.class_name != expected
    global = @comparison.global_comparison
    return false if !global.arithmetic_certified?
    theta = @comparison.local_theta_dimension
    return false if !theta.certified?
    return false if theta.global_theta_certificate != (
      global.theta_galois_certificate)
    image = @comparison.local_image
    return false if !image.certified?
    return false if !image.complete?
    return false if image.rational_prime != theta.rational_prime
    computations = @comparison.finite_computations
    return false if computations.size != (
      theta.compatible_subgroups.size)
    computations.each -> (computation)
      return false if !computation.certified?
    return false if @comparison.possible_kernel_dimensions.size != 1
    kernel = @comparison.local_comparison_kernel_dimension
    return false if kernel < 0
    kummer_kernel = theta.dimension - image.dimension
    return false if kummer_kernel != (
      @comparison.kummer_kernel_dimension)
    return false if kummer_kernel < 0
    expected_wv = kernel - kummer_kernel
    return false if expected_wv != @comparison.w_v_dimension
    return false if expected_wv < 0
    ranks = @comparison.possible_global_localization_ranks
    return false if ranks.size != 1
    return false if ranks[0] != (
      @comparison.global_localization_rank)
    if @comparison.global_kernel_killed?
      return false if @comparison.kummer_kernel_dimension != 0
      return false if @comparison.global_localization_rank != (
        global.comparison_kernel_dimension)
    true

  -> certified?
    verified?

  -> proof_kind
    :bps_local_comparison_dimension

  -> kernel_checked?
    true

  -> theorem
    "W_v is the image of ker(alpha_v) in coker(gamma_v)"

  -> theorem_reference
    "Bruin-Poonen-Stoll Definition 10.3 and equation (22)"


+ PlaneQuarticBPSLocalComparison
  -> new(@global_comparison, @local_theta_dimension,
         @local_image)
    if @global_comparison.class_name != (
         "PlaneQuarticBPSTrueComparison")
      raise "local BPS comparison needs the global true comparison"
    if !@global_comparison.arithmetic_certified?
      raise "local BPS comparison needs the arithmetic theta subgroup"
    if @local_theta_dimension.class_name != (
         "PlaneQuarticLocalThetaDimension")
      raise "local BPS comparison needs an exact local theta dimension"
    if !@local_theta_dimension.certified?
      raise "local BPS comparison theta dimension is uncertified"
    complete_method = @local_image.respond_to?("complete?")
    if !complete_method || !@local_image.complete?
      raise "local BPS comparison needs a complete local image"
    if !@local_image.certified?
      raise "local BPS comparison image is uncertified"
    if @local_image.rational_prime != (
         @local_theta_dimension.rational_prime)
      raise "local BPS comparison changes the rational prime"

    @finite_computations = []
    @local_theta_dimension.compatible_subgroups.each -> (subgroup)
      @finite_computations.push(
        @global_comparison.finite_computation_for_subgroup(
          subgroup))
    @possible_kernel_dimensions = []
    @finite_computations.each -> (computation)
      dimension = computation.dimension
      if !@possible_kernel_dimensions.include?(dimension)
        @possible_kernel_dimensions.push(dimension)
    @possible_kernel_dimensions = (
      GenusThreeThetaPermutation.sort_integers(
        @possible_kernel_dimensions))
    if @possible_kernel_dimensions.size != 1
      raise "local theta orbit partition does not determine the BPS comparison kernel"
    @local_comparison_kernel_dimension = (
      @possible_kernel_dimensions[0])
    @kummer_kernel_dimension = (
      @local_theta_dimension.dimension -
      @local_image.dimension)
    @w_v_dimension = (
      @local_comparison_kernel_dimension -
      @kummer_kernel_dimension)
    if @w_v_dimension < 0
      raise "local BPS comparison dimensions are inconsistent"
    @possible_global_localization_ranks = []
    @finite_computations.each -> (computation)
      rank = localization_rank(computation)
      if !@possible_global_localization_ranks.include?(rank)
        @possible_global_localization_ranks.push(rank)
    @possible_global_localization_ranks = (
      GenusThreeThetaPermutation.sort_integers(
        @possible_global_localization_ranks))
    if @possible_global_localization_ranks.size != 1
      raise "local theta orbit partition does not determine global K localization"
    @global_localization_rank = (
      @possible_global_localization_ranks[0])
    @certificate_cache = (
      PlaneQuarticBPSLocalComparisonCertificate.new(self))
    if !@certificate_cache.verified?
      raise "local BPS comparison failed certification"

  -> localization_rank(local_computation)
    global_dimension = (
      @global_comparison.comparison_kernel_dimension)
    return 0 if global_dimension == 0
    if global_dimension != 1
      raise "local BPS localization currently needs global K dimension at most one"
    if local_computation.dimension > 1
      raise "local BPS localization currently needs local K dimension at most one"
    representative = (
      @global_comparison.comparison_kernel_representatives[0])
    if !local_computation.represents_quotient_fixed_class?(
         representative)
      raise "global BPS kernel representative is not locally fixed"
    local_computation.zero_class?(representative) ? 0 : 1

  -> global_comparison
    @global_comparison

  -> local_theta_dimension
    @local_theta_dimension

  -> local_image
    @local_image

  -> rational_prime
    @local_theta_dimension.rational_prime

  -> finite_computations
    out = []
    @finite_computations.each -> out.push(item)
    out

  -> possible_kernel_dimensions
    F2LinearAlgebra.copy_vector(
      @possible_kernel_dimensions)

  -> local_comparison_kernel_dimension
    @local_comparison_kernel_dimension

  -> kummer_kernel_dimension
    @kummer_kernel_dimension

  -> w_v_dimension
    @w_v_dimension

  -> w_v_zero?
    @w_v_dimension == 0

  -> possible_global_localization_ranks
    F2LinearAlgebra.copy_vector(
      @possible_global_localization_ranks)

  -> global_localization_rank
    @global_localization_rank

  -> global_kernel_killed?
    zero_kummer_kernel = @kummer_kernel_dimension == 0
    full_rank = @global_localization_rank == (
      @global_comparison.comparison_kernel_dimension)
    zero_kummer_kernel && full_rank

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?


+ PlaneQuarticBPSGoodReductionLocalComparisonCertificate
  -> new(@comparison)
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
    expected = "PlaneQuarticBPSGoodReductionLocalComparison"
    return false if @comparison.class_name != expected
    global = @comparison.global_comparison
    return false if !global.arithmetic_certified?
    fiber = @comparison.theta_fiber
    return false if !fiber.certified? || !fiber.good_reduction?
    image = @comparison.local_image
    return false if !image.certified? || !image.complete?
    return false if image.theta_fiber != fiber
    computation = @comparison.finite_computation
    return false if !computation.certified?
    fixed = fiber.theta_permutation.transformation.fixed_subspace_certificate
    return false if !fixed.verified?
    return false if fixed.kernel_dimension != (
      @comparison.local_kummer_dimension)
    kummer_kernel = (
      @comparison.local_kummer_dimension -
      image.dimension)
    return false if kummer_kernel != (
      @comparison.kummer_kernel_dimension)
    expected_wv = (
      computation.dimension - kummer_kernel)
    correct = expected_wv == @comparison.w_v_dimension
    correct && expected_wv >= 0

  -> certified?
    verified?

  -> proof_kind
    :bps_good_reduction_local_comparison_dimension

  -> kernel_checked?
    true

  -> theorem
    "W_v is the image of ker(alpha_v) in coker(gamma_v)"

  -> theorem_reference
    "Bruin-Poonen-Stoll Definition 10.3 and equation (22)"


+ PlaneQuarticBPSGoodReductionLocalComparison
  -> new(@global_comparison, @theta_fiber,
         @local_image)
    if @global_comparison.class_name != (
         "PlaneQuarticBPSTrueComparison")
      raise "good local BPS comparison needs the global true comparison"
    if !@global_comparison.arithmetic_certified?
      raise "good local BPS comparison needs the arithmetic theta subgroup"
    if @theta_fiber.class_name != (
         "PlaneQuarticFiniteThetaFiber")
      raise "good local BPS comparison needs a finite theta fiber"
    valid_fiber = @theta_fiber.certified?
    valid_fiber = false if !@theta_fiber.good_reduction?
    if !valid_fiber
      raise "good local BPS comparison theta fiber is uncertified"
    if @local_image.class_name != (
         "PlaneQuarticBPSGoodReductionLocalImage")
      raise "good local BPS comparison needs a good-reduction image"
    valid_image = @local_image.certified?
    valid_image = false if !@local_image.complete?
    if !valid_image
      raise "good local BPS comparison needs a complete local image"
    if @local_image.theta_fiber != @theta_fiber
      raise "good local BPS comparison changes the theta fiber"
    permutation = @theta_fiber.theta_permutation.permutation
    generator = FinitePermutation.new(permutation)
    @decomposition_group = FinitePermutationGroup.new(
      [permutation], generator.order)
    @finite_computation = (
      @global_comparison.finite_computation_for_theta_subgroup(
        @decomposition_group,
        @theta_fiber.distinguished_theta_label))
    fixed = @theta_fiber.theta_permutation.transformation.fixed_subspace_certificate
    @local_kummer_dimension = fixed.kernel_dimension
    @kummer_kernel_dimension = (
      @local_kummer_dimension -
      @local_image.dimension)
    @w_v_dimension = (
      @finite_computation.dimension -
      @kummer_kernel_dimension)
    if @w_v_dimension < 0
      raise "good local BPS comparison dimensions are inconsistent"
    @certificate_cache = (
      PlaneQuarticBPSGoodReductionLocalComparisonCertificate.new(
        self))
    if !@certificate_cache.verified?
      raise "good-reduction local BPS comparison failed certification"

  -> global_comparison
    @global_comparison

  -> theta_fiber
    @theta_fiber

  -> local_image
    @local_image

  -> rational_prime
    @theta_fiber.prime

  -> decomposition_group
    @decomposition_group

  -> finite_computation
    @finite_computation

  -> local_comparison_kernel_dimension
    @finite_computation.dimension

  -> local_kummer_dimension
    @local_kummer_dimension

  -> kummer_kernel_dimension
    @kummer_kernel_dimension

  -> w_v_dimension
    @w_v_dimension

  -> w_v_zero?
    @w_v_dimension == 0

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?


+ PlaneQuarticBPSRankUpperBoundCertificate
  -> new(@bound)
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
    expected = "PlaneQuarticBPSRankUpperBound"
    return false if @bound.class_name != expected
    comparison = @bound.global_comparison
    return false if !comparison.arithmetic_certified?
    return false if comparison.geometric_torsion_dimension != 6
    intersection = @bound.explicit_intersection
    return false if intersection.class_name != (
      "ExplicitSelmerIntersectionCertificate")
    return false if !intersection.certified?
    local = @bound.kernel_killing_local_comparison
    return false if !local.certified?
    return false if local.global_comparison != comparison
    return false if !local.global_kernel_killed?
    selmer_bound = (
      intersection.dimension +
      comparison.comparison_kernel_dimension -
      local.global_localization_rank)
    return false if selmer_bound != (
      @bound.selmer_dimension_upper_bound)
    rank_bound = (
      selmer_bound -
      comparison.rational_two_torsion_dimension)
    return false if rank_bound != @bound.rank_upper_bound
    rank_bound >= 0

  -> certified?
    verified?

  -> proof_kind
    :bps_theorem_10_14_rank_upper_bound

  -> kernel_checked?
    true

  -> theorem
    "Theorem 10.14 bounds Sel_2 by ker(kappa) plus the explicit Selmer intersection; the Kummer sequence subtracts dim J(Q)[2]"

  -> theorem_reference
    "Bruin-Poonen-Stoll Theorem 10.14 and the multiplication-by-2 Kummer sequence"


+ PlaneQuarticBPSRankUpperBound
  -> new(@global_comparison, @explicit_intersection,
         @kernel_killing_local_comparison)
    if @global_comparison.class_name != (
         "PlaneQuarticBPSTrueComparison")
      raise "BPS rank bound needs the global true comparison"
    if !@global_comparison.arithmetic_certified?
      raise "BPS rank bound needs an arithmetic global comparison"
    if @explicit_intersection.class_name != (
         "ExplicitSelmerIntersectionCertificate")
      raise "BPS rank bound needs an explicit Selmer intersection"
    if !@explicit_intersection.certified?
      raise "BPS rank bound needs arithmetic-certified local conditions"
    if @kernel_killing_local_comparison.class_name != (
         "PlaneQuarticBPSLocalComparison")
      raise "BPS rank bound needs a local comparison certificate"
    if !@kernel_killing_local_comparison.certified?
      raise "BPS rank bound local comparison is uncertified"
    if @kernel_killing_local_comparison.global_comparison != (
         @global_comparison)
      raise "BPS rank bound mixes global comparison modules"
    if !@kernel_killing_local_comparison.global_kernel_killed?
      raise "supplied local comparison does not kill the global BPS kernel"
    @selmer_dimension_upper_bound = (
      @explicit_intersection.dimension +
      @global_comparison.comparison_kernel_dimension -
      @kernel_killing_local_comparison.global_localization_rank)
    @rank_upper_bound = (
      @selmer_dimension_upper_bound -
      @global_comparison.rational_two_torsion_dimension)
    if @rank_upper_bound < 0
      raise "BPS rank upper-bound dimensions are inconsistent"
    @certificate_cache = (
      PlaneQuarticBPSRankUpperBoundCertificate.new(self))
    if !@certificate_cache.verified?
      raise "BPS rank upper bound failed certification"

  -> global_comparison
    @global_comparison

  -> explicit_intersection
    @explicit_intersection

  -> kernel_killing_local_comparison
    @kernel_killing_local_comparison

  -> selmer_dimension_upper_bound
    @selmer_dimension_upper_bound

  -> rank_upper_bound
    @rank_upper_bound

  -> chabauty_eligible?
    @rank_upper_bound < 3

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?


+ PlaneQuarticBPSModTwoSaturationCertificate
  -> new(@saturation)
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
    expected = "PlaneQuarticBPSModTwoSaturation"
    return false if @saturation.class_name != expected
    bound = @saturation.rank_bound
    return false if bound.class_name != (
      "PlaneQuarticBPSRankUpperBound")
    return false if !bound.certified?
    space = @saturation.space
    return false if space.class_name != (
      "EtaleProductSUnitSquareClassSpace")
    return false if !space.certified?
    norm_source = nil
    bound.explicit_intersection.blocks.each -> (block)
      arithmetic = block.arithmetic_certificate
      if arithmetic != nil && arithmetic.class_name == (
           "PlaneQuarticBPSNormConstraintCertificate")
        norm_source = arithmetic.constraint.source
    return false if norm_source == nil || norm_source != space
    values = @saturation.descent_values
    return false if values.size == 0
    vectors = []
    values.each -> (value)
      value_class = value.class_name
      supported = value_class == (
        "PlaneQuarticBPSPointDifferenceDescentValue")
      supported = true if value_class == (
        "PlaneQuarticBPSClosedPlaceDifferenceDescentValue")
      return false if !supported
      return false if !value.certificate.verified?
      return false if !value.certificate.known_jacobian_image_element?
      return false if value.space != space
      vectors.push(value.coordinates)
    span = @saturation.image_span_certificate
    return false if !span.verified?
    return false if span.width != space.dimension
    return false if !F2LinearAlgebra.same_matrix?(
      span.matrix, vectors)
    expected_dimension = (
      bound.rank_upper_bound +
      bound.global_comparison.
        rational_two_torsion_dimension)
    return false if expected_dimension != (
      @saturation.mod_two_dimension)
    return false if span.rank != expected_dimension
    return false if @saturation.exact_rank != (
      bound.rank_upper_bound)
    return false if @saturation.selmer_dimension != (
      expected_dimension)
    return false if @saturation.sha_two_dimension != 0
    @saturation.two_saturated?

  -> certified?
    verified?

  -> proof_kind
    :bps_mod_two_saturation_from_full_kummer_span

  -> theorem
    "independent explicit images give independent classes in J(Q)/2J(Q); the Kummer dimension is rank J(Q) plus dim J(Q)[2], and a full mod-two image makes the generated subgroup have odd index"

  -> theorem_reference
    "multiplication-by-2 Kummer sequence and finite-index saturation lemma"

  -> kernel_checked?
    true


+ PlaneQuarticBPSModTwoSaturation
  -> new(@rank_bound, descent_values)
    if @rank_bound.class_name != (
         "PlaneQuarticBPSRankUpperBound")
      raise "mod-two saturation needs a BPS rank bound"
    if !@rank_bound.certified?
      raise "mod-two saturation rank bound is uncertified"
    if descent_values.class_name != "Array" || (
         descent_values.size == 0)
      raise "mod-two saturation needs explicit global descent values"
    @descent_values = []
    @space = nil
    system = nil
    descent_values.each -> (value)
      value_class = value.class_name
      supported = value_class == (
        "PlaneQuarticBPSPointDifferenceDescentValue")
      supported = true if value_class == (
        "PlaneQuarticBPSClosedPlaceDifferenceDescentValue")
      if !supported
        raise "mod-two saturation needs certified rational divisor images"
      if !value.certificate.verified?
        raise "mod-two saturation contains an uncertified divisor image"
      @space = value.space if @space == nil
      if value.space != @space
        raise "mod-two saturation mixes global descent spaces"
      if system == nil
        system = F2LinearSystem.new(
          @space.dimension)
      system.add_equation(
        value.coordinates, 0,
        "known rational divisor BPS image")
      @descent_values.push(value)
    @image_span_certificate = system.certificate
    @mod_two_dimension = (
      @rank_bound.rank_upper_bound +
      @rank_bound.global_comparison.
        rational_two_torsion_dimension)
    if @image_span_certificate.rank != (
         @mod_two_dimension)
      raise "known divisor images do not span the full possible Kummer quotient"
    @exact_rank = @rank_bound.rank_upper_bound
    @selmer_dimension = @mod_two_dimension
    @sha_two_dimension = 0
    @certificate_cache = (
      PlaneQuarticBPSModTwoSaturationCertificate.new(
        self))
    if !@certificate_cache.verified?
      raise "mod-two saturation certificate failed"

  -> rank_bound
    @rank_bound

  -> descent_values
    out = []
    @descent_values.each -> out.push(item)
    out

  -> space
    @space

  -> image_span_certificate
    @image_span_certificate

  -> image_span_dimension
    @image_span_certificate.rank

  -> mod_two_dimension
    @mod_two_dimension

  -> exact_rank
    @exact_rank

  -> selmer_dimension
    @selmer_dimension

  -> sha_two_dimension
    @sha_two_dimension

  -> odd_index?
    true

  -> two_saturated?
    odd_index?

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?


+ PlaneQuarticTwoDescentSetup
  -> certify_bps_true_finite_comparison
    if @theta_galois_certificate == nil
      certify_theta_galois_subgroup
    PlaneQuarticBPSTrueComparison.new(
      @theta_galois_certificate)
