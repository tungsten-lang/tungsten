# Degeneracy maps and the weight-two old/new Hecke quotient for Gamma_0(N).
#
# The concrete new object is the canonical Hecke quotient of the cuspidal
# modular-symbol space by its old subspace.  Over Q, Atkin-Lehner-Li theory
# identifies this quotient with the embedded new subspace; exposing it as a
# quotient avoids choosing a noncanonical vector-space complement.

+ Gamma0DegeneracyCosets
  -> new(source_level, target_level, @search_limit = 1_000_000)
    @source_group = Gamma0.new(source_level)
    @target_group = Gamma0.new(target_level)
    if @target_group.level % @source_group.level != 0
      raise "degeneracy target level must be a multiple of the source"
    @target_line = Gamma0ProjectiveLine.new(
      @target_group, @search_limit)
    @matrices = []
    @indices = []
    @target_line.pairs.each -> (pair)
      if pair[0] % @source_group.level == 0
        matrix = Gamma0DegeneracyCosets.sl2_lift(
          pair, @target_group.level, @search_limit)
        @matrices.push(matrix)
        @indices.push(@target_line.index_of(matrix[2], matrix[3]))
    @certificate = Gamma0DegeneracyCosetsCertificate.new(self)
    raise "Gamma0 degeneracy-coset certificate failed" if !@certificate.verified?

  -> .sl2_lift(pair, level, search_limit)
    lift = WeightTwoModularSymbols.coprime_lift(
      pair[0], pair[1], level, search_limit)
    bezout = WeightTwoModularSymbols.extended_gcd(
      lift[0], lift[1])
    raise "projective pair has no SL2 lift" if bezout[0] != 1
    [bezout[2], 0 - bezout[1], lift[0], lift[1]]

  -> source_group
    @source_group

  -> target_group
    @target_group

  -> target_line
    @target_line

  -> matrices
    out = []
    @matrices.each -> (matrix)
      out.push([matrix[0], matrix[1], matrix[2], matrix[3]])
    out

  -> indices
    out = []
    @indices.each -> out.push(item)
    out

  -> size
    @matrices.size

  -> certificate
    @certificate

  -> certified?
    @certificate.verified?

  -> to_s
    ("Gamma0DegeneracyCosets(" +
      @source_group.level.to_s + " -> " +
      @target_group.level.to_s + ")")

  -> inspect
    to_s


+ Gamma0DegeneracyCosetsCertificate
  -> new(@cosets)
    @verified_cache = nil

  -> cosets
    @cosets

  -> theorem
    "Gamma_0(N) cosets in Gamma_0(M) are constrained projective rows"

  -> theorem_reference
    "Merel, Universal Fourier expansions of modular forms, proposition 15"

  -> proof_kind
    :trusted_theorem_import

  -> kernel_checked?
    false

  -> arithmetic_replay_checked?
    verified?

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
    return false if @cosets.class_name != "Gamma0DegeneracyCosets"
    source = @cosets.source_group
    target = @cosets.target_group
    return false if target.level % source.level != 0
    expected_size = target.index / source.index
    return false if @cosets.size != expected_size
    seen = {}
    matrices = @cosets.matrices
    indices = @cosets.indices
    i = 0
    while i < matrices.size
      matrix = matrices[i]
      return false if matrix[0]*matrix[3] - matrix[1]*matrix[2] != 1
      return false if matrix[2] % source.level != 0
      index = @cosets.target_line.index_of(matrix[2], matrix[3])
      return false if index != indices[i]
      return false if seen[index.to_s] != nil
      seen[index.to_s] = true
      i += 1
    true

  -> certified?
    verified?

  -> to_s
    ("Gamma0DegeneracyCosetsCertificate(" +
      @cosets.source_group.level.to_s + " -> " +
      @cosets.target_group.level.to_s + ")")

  -> inspect
    to_s


+ WeightTwoDegeneracyMap
  -> new(@source, @target, @prime)
    invalid_source = @source.class_name != "WeightTwoModularSymbols"
    invalid_target = @target.class_name != "WeightTwoModularSymbols"
    if invalid_source || invalid_target
      raise "degeneracy map needs weight-two modular-symbol spaces"
    if @prime < 2 || !@prime.prime?
      raise "old/new degeneracy map needs a prime level quotient"
    if @target.level != @source.level*@prime
      raise "degeneracy levels must differ by the selected prime"
    @cosets = Gamma0DegeneracyCosets.new(
      @source.level, @target.level, @target.search_limit)
    @relative_one = produce_relative_one
    @cuspidal_one = produce_cuspidal_one
    @cuspidal_prime = produce_cuspidal_prime
    @certificate = WeightTwoDegeneracyMapCertificate.new(self)
    raise "weight-two degeneracy-map certificate failed" if !@certificate.verified?

  -> source
    @source

  -> target
    @target

  -> prime
    @prime

  -> cosets
    @cosets

  -> produce_relative_one
    target_generators = @target.manin_generators_to_basis
    out = []
    @source.quotient_basis_indices.each -> (generator_index)
      source_pair = @source.projective_line.pair(generator_index)
      source_lift = Gamma0DegeneracyCosets.sl2_lift(
        source_pair, @source.level, @source.search_limit)
      image = ModularSymbolsLinearAlgebra.zero_vector(
        @target.relative_dimension)
      @cosets.matrices.each -> (h)
        c = h[2]*source_lift[0] + h[3]*source_lift[2]
        d = h[2]*source_lift[1] + h[3]*source_lift[3]
        index = @target.projective_line.index_of(c, d)
        coordinates = target_generators[index]
        j = 0
        while j < image.size
          image[j] += coordinates[j]
          j += 1
      out.push(image)
    out

  -> produce_cuspidal_one
    source_basis = @source.cuspidal_basis_coordinates
    target_basis = @target.cuspidal_basis_coordinates
    target_solver = @target.cuspidal_basis_solver
    out = []
    source_basis.each -> (vector)
      relative_image = HeckeLinearAlgebra.row_vector_matrix(
        vector, @relative_one)
      out.push(
        HeckeLinearAlgebra.row_span_coordinates_with_solver(
          target_solver, relative_image))
    out

  # The second prime-level degeneracy map is p^(-1) d_1 T_p on
  # weight-two modular symbols.
  -> produce_cuspidal_prime
    hecke = @target.cuspidal_hecke_matrix(@prime)
    product = HeckeLinearAlgebra.matrix_product(
      @cuspidal_one, hecke)
    out = []
    product.each -> (row)
      scaled = []
      row.each -> (entry)
        scaled.push(entry / Rational.new(@prime))
      out.push(scaled)
    out

  -> relative_matrix_one
    ModularSymbolsLinearAlgebra.copy_matrix(@relative_one)

  -> cuspidal_matrix_one
    ModularSymbolsLinearAlgebra.copy_matrix(@cuspidal_one)

  -> cuspidal_matrix_prime
    ModularSymbolsLinearAlgebra.copy_matrix(@cuspidal_prime)

  -> certificate
    @certificate

  -> certified?
    @certificate.verified?

  -> to_s
    ("DegeneracyMaps(Gamma0(" + @source.level.to_s +
      ") -> Gamma0(" + @target.level.to_s + "))")

  -> inspect
    to_s


+ WeightTwoDegeneracyMapCertificate
  -> new(@map)
    @verified_cache = nil

  -> map
    @map

  -> theorem
    "the two prime-level degeneracy maps on weight-two modular symbols"

  -> theorem_reference
    "Atkin-Lehner, Hecke operators on Gamma_0(m); Merel, proposition 15"

  -> proof_kind
    :trusted_theorem_import

  -> kernel_checked?
    false

  -> arithmetic_replay_checked?
    verified?

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
    return false if @map.class_name != "WeightTwoDegeneracyMap"
    return false if !@map.source.certificate.verified?
    return false if !@map.target.certificate.verified?
    return false if !@map.cosets.certificate.verified?
    return false if @map.target.level != @map.source.level*@map.prime
    return false if !ModularSymbolsLinearAlgebra.same_matrix?(
      @map.relative_matrix_one, @map.produce_relative_one)
    return false if !ModularSymbolsLinearAlgebra.same_matrix?(
      @map.cuspidal_matrix_one, @map.produce_cuspidal_one)
    ModularSymbolsLinearAlgebra.same_matrix?(
      @map.cuspidal_matrix_prime, @map.produce_cuspidal_prime)

  -> certified?
    verified?

  -> to_s
    ("WeightTwoDegeneracyMapCertificate(" +
      @map.source.level.to_s + " -> " +
      @map.target.level.to_s + ")")

  -> inspect
    to_s


+ WeightTwoOldNewDecomposition
  -> new(space)
    if space.class_name != "WeightTwoModularSymbols"
      raise "old/new decomposition needs weight-two modular symbols"
    @space = space
    @degeneracy_maps = []
    old_generators = []
    @space.group.factorization.each -> (factor)
      prime = factor.prime
      source = WeightTwoModularSymbols.new(
        @space.level / prime, 2, @space.search_limit)
      map = WeightTwoDegeneracyMap.new(source, @space, prime)
      @degeneracy_maps.push(map)
      map.cuspidal_matrix_one.each -> (row)
        old_generators.push(row)
      map.cuspidal_matrix_prime.each -> (row)
        old_generators.push(row)
    @old_basis = HeckeLinearAlgebra.row_basis(
      old_generators, @space.cuspidal_dimension)
    @new_quotient = HeckeLinearAlgebra.quotient_map(
      @old_basis, @space.cuspidal_dimension)
    @certificate = WeightTwoOldNewCertificate.new(self)
    raise "weight-two old/new certificate failed" if !@certificate.verified?

  -> space
    @space

  -> degeneracy_maps
    out = []
    @degeneracy_maps.each -> out.push(item)
    out

  -> old_basis
    ModularSymbolsLinearAlgebra.copy_matrix(@old_basis)

  -> old_dimension
    @old_basis.size

  -> new_dimension
    @new_quotient[0].size

  -> new_quotient_basis_indices
    out = []
    @new_quotient[0].each -> out.push(item)
    out

  -> old_hecke_matrix(prime)
    matrix = @space.cuspidal_hecke_matrix(prime)
    HeckeLinearAlgebra.restrict_operator(matrix, @old_basis)

  -> new_hecke_matrix(prime)
    matrix = @space.cuspidal_hecke_matrix(prime)
    # This also checks that the old row span is invariant: changing a
    # representative by an old vector must map to zero in the quotient.
    old_quotient_images = HeckeLinearAlgebra.matrix_product(
      @old_basis, matrix)
    quotient_map = @new_quotient[1]
    old_quotient_images.each -> (image)
      reduced = HeckeLinearAlgebra.row_vector_matrix(
        image, quotient_map)
      zero = ModularSymbolsLinearAlgebra.zero_vector(new_dimension)
      if !ModularSymbolsLinearAlgebra.same_vector?(reduced, zero)
        raise "old modular-symbol subspace is not Hecke invariant"
    HeckeLinearAlgebra.quotient_operator(matrix, @old_basis)

  -> old_characteristic_polynomial(prime)
    HeckeLinearAlgebra.characteristic_polynomial(
      old_hecke_matrix(prime))

  -> new_characteristic_polynomial(prime)
    polynomial = HeckeLinearAlgebra.characteristic_polynomial(
      new_hecke_matrix(prime))
    total = @space.hecke_operator(prime).characteristic_polynomial
    old = old_characteristic_polynomial(prime)
    if old*polynomial != total
      raise "old/new Hecke characteristic polynomials do not compose"
    polynomial

  -> certificate
    @certificate

  -> certified?
    @certificate.verified?

  -> to_s
    ("OldNew(Gamma0(" + @space.level.to_s +
      "), old=" + old_dimension.to_s +
      ", new=" + new_dimension.to_s + ")")

  -> inspect
    to_s


+ WeightTwoOldNewCertificate
  -> new(@decomposition)
    @verified_cache = nil

  -> decomposition
    @decomposition

  -> theorem
    "Atkin-Lehner-Li old/new decomposition over Q"

  -> theorem_reference
    "Atkin-Lehner, Hecke operators on Gamma_0(m); Li, Newforms and functional equations"

  -> proof_kind
    :trusted_theorem_import

  -> kernel_checked?
    false

  -> arithmetic_replay_checked?
    verified?

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
    if @decomposition.class_name != "WeightTwoOldNewDecomposition"
      return false
    space = @decomposition.space
    return false if !space.certificate.verified?
    maps = @decomposition.degeneracy_maps
    map_index = 0
    while map_index < maps.size
      return false if !maps[map_index].certificate.verified?
      map_index += 1
    old_basis = @decomposition.old_basis
    return false if ModularSymbolsLinearAlgebra.rank(old_basis) != old_basis.size
    return false if (
      @decomposition.old_dimension +
      @decomposition.new_dimension != space.cuspidal_dimension)
    true

  -> certified?
    verified?

  -> to_s
    ("WeightTwoOldNewCertificate(N=" +
      @decomposition.space.level.to_s + ")")

  -> inspect
    to_s


+ WeightTwoModularSymbols
  -> old_new_decomposition
    WeightTwoOldNewDecomposition.new(self)

  -> old_new
    old_new_decomposition
