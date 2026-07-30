# Unconditional certificates that an S-class group has no 2-torsion.
#
# Minkowski's ideal-class theorem says that prime ideals of norm at most an
# explicit bound generate Cl(O_K).  We add the displayed S-prime classes as
# relations and replay principal-ideal relations among that finite factor
# base.  Full rank modulo 2 means that the integral relation lattice has odd
# index in Z^n.  Since Cl(O_K,S) is a quotient of that odd finite group, its
# 2-torsion is trivial.
#
# The ideal arithmetic, prime decompositions, relation vectors, and F2 rank
# are replayed exactly.  Minkowski's theorem is a named trusted theorem import.

+ NumberFieldMinkowskiFactorBaseCertificate
  -> new(@factor_base)
    @verified_cache = nil

  -> factor_base
    @factor_base

  -> theorem
    "Minkowski ideal-class theorem"

  -> proof_kind
    :trusted_theorem_import

  -> kernel_checked?
    false

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
    expected_class = "NumberFieldMinkowskiFactorBase"
    return false if @factor_base.class_name != expected_class
    field = @factor_base.field
    return false if field.class_name != "NumberField"
    return false if !field.maximal_order_certificate.verified?
    expected_bound = @factor_base.compute_bound
    return false if @factor_base.bound != expected_bound
    limit_exceeded = @factor_base.bound > @factor_base.rational_prime_limit
    return false if limit_exceeded

    s_primes = @factor_base.s_primes
    i = 0
    while i < s_primes.size
      prime = s_primes[i]
      return false if prime.class_name != "NumberFieldPrimeIdeal"
      return false if prime.field != field
      return false if !prime.certificate.verified?
      j = 0
      while j < i
        return false if prime.eql?(s_primes[j])
        j += 1
      i += 1

    expected = @factor_base.enumerate_minkowski_primes
    actual = @factor_base.minkowski_primes
    return false if !@factor_base.same_prime_lists?(
      expected, actual)
    i = 0
    while i < actual.size
      return false if actual[i].norm > @factor_base.bound
      i += 1

    combined = []
    actual.each -> (prime)
      combined.push(prime)
    s_primes.each -> (prime)
      found = false
      combined.each -> (existing)
        found = true if existing.eql?(prime)
      combined.push(prime) if !found
    @factor_base.same_prime_lists?(
      combined, @factor_base.primes)

  -> certified?
    verified?

  -> to_s
    text = "NumberFieldMinkowskiFactorBaseCertificate(bound "
    text + @factor_base.bound.to_s + ")"

  -> inspect
    to_s


+ NumberFieldMinkowskiFactorBase
  -> new(@field, s_primes = nil,
         @rational_prime_limit = 100_000,
         @factor_search_limit = 250_000,
         @generator_search_limit = 250_000)
    if @field.class_name != "NumberField"
      raise "Minkowski factor base needs a NumberField"
    @s_primes = []
    if s_primes != nil
      if s_primes.class_name != "Array"
        raise "Minkowski S-primes must be an Array"
      s_primes.each -> (prime)
        @s_primes.push(prime)
    @bound = compute_bound
    if @bound > @rational_prime_limit
      raise "Minkowski factor-base prime limit exceeded; class-group proof unknown"
    @minkowski_primes = enumerate_minkowski_primes
    @primes = []
    @minkowski_primes.each -> (prime)
      @primes.push(prime)
    @s_primes.each -> (prime)
      found = false
      @primes.each -> (existing)
        found = true if existing.eql?(prime)
      @primes.push(prime) if !found
    @certificate_cache = NumberFieldMinkowskiFactorBaseCertificate.new(
      self)
    if !@certificate_cache.verified?
      raise "Minkowski factor base failed certification"

  -> field
    @field

  -> rational_prime_limit
    @rational_prime_limit

  -> factor_search_limit
    @factor_search_limit

  -> generator_search_limit
    @generator_search_limit

  -> compute_bound
    degree = @field.degree
    complex_pairs = @field.signature[1]
    discriminant = @field.field_discriminant.abs
    square_root = discriminant.isqrt
    square_root += 1 if square_root * square_root < discriminant
    numerator = (4 ** complex_pairs) * degree.factorial
    numerator *= square_root
    denominator = (3 ** complex_pairs) * (degree ** degree)
    quotient = numerator / denominator
    quotient += 1 if numerator % denominator != 0
    quotient < 1 ? 1 : quotient

  -> bound
    @bound

  -> enumerate_minkowski_primes
    out = []
    rational_prime = 2
    while rational_prime <= @bound
      if rational_prime.prime?
        decomposition = @field.prime_ideals_above(
          rational_prime, @factor_search_limit,
          @generator_search_limit)
        decomposition.each -> (prime)
          out.push(prime) if prime.norm <= @bound
      rational_prime += 1
    out

  -> same_prime_lists?(left, right)
    return false if left.size != right.size
    i = 0
    while i < left.size
      return false if !left[i].eql?(right[i])
      i += 1
    true

  -> minkowski_primes
    out = []
    @minkowski_primes.each -> (prime)
      out.push(prime)
    out

  -> s_primes
    out = []
    @s_primes.each -> (prime)
      out.push(prime)
    out

  -> primes
    out = []
    @primes.each -> (prime)
      out.push(prime)
    out

  -> size
    @primes.size

  -> index_of(prime_ideal)
    i = 0
    while i < @primes.size
      return i if @primes[i].eql?(prime_ideal)
      i += 1
    nil

  -> include?(prime_ideal)
    index_of(prime_ideal) != nil

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> to_s
    text = "MinkowskiFactorBase(" + @field.to_s
    text + ", bound " + @bound.to_s
    text + ", primes " + size.to_s + ")"

  -> inspect
    to_s


+ NumberFieldPrincipalClassRelation
  -> new(@factor_base, value)
    expected_class = "NumberFieldMinkowskiFactorBase"
    if @factor_base.class_name != expected_class
      raise "principal class relation needs a Minkowski factor base"
    @element = @factor_base.field.coerce(value)
    if @element.zero?
      raise "zero has no principal ideal-class relation"
    relation_field = @factor_base.field
    @fractional_ideal = relation_field.principal_fractional_ideal(
      @element)
    @vector = compute_vector
    if !verified?
      raise "principal ideal is not supported on the displayed factor base"

  -> factor_base
    @factor_base

  -> field
    @factor_base.field

  -> element
    @element

  -> fractional_ideal
    @fractional_ideal

  -> compute_vector
    vector = []
    @factor_base.size.times -> vector.push(0)
    algebra_ideal = @fractional_ideal.algebra_fractional_ideal
    factors = algebra_ideal.factors
    factor_index = 0
    while factor_index < factors.size
      factor = factors[factor_index]
      number_field_prime = NumberFieldPrimeIdeal.new(
        field, factor[0])
      index = @factor_base.index_of(number_field_prime)
      return nil if index == nil
      vector[index] = factor[1].abs % 2
      factor_index += 1
    vector

  -> vector
    return nil if @vector == nil
    F2LinearAlgebra.copy_vector(@vector)

  -> verified?
    return false if !@factor_base.certificate.verified?
    return false if !@fractional_ideal.certificate.verified?
    recomputed = compute_vector
    return false if recomputed == nil || @vector == nil
    F2LinearAlgebra.same_vector?(recomputed, @vector)

  -> certified?
    verified?

  -> to_s
    "PrincipalClassRelation(" + @element.to_s + ")"

  -> inspect
    to_s


+ NumberFieldSClassTwoTorsionCertificate
  -> new(@proof)
    @verified_cache = nil

  -> proof
    @proof

  -> theorem
    "Minkowski generation plus an odd relation-lattice quotient"

  -> proof_kind
    :trusted_theorem_import

  -> kernel_checked?
    false

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
    expected_class = "NumberFieldSClassTwoTorsionProof"
    return false if @proof.class_name != expected_class
    factor_base = @proof.factor_base
    return false if !factor_base.certificate.verified?
    relations = @proof.principal_relations
    relation_rows = []
    i = 0
    while i < relations.size
      relation = relations[i]
      relation_class = "NumberFieldPrincipalClassRelation"
      return false if relation.class_name != relation_class
      return false if relation.factor_base != factor_base
      return false if !relation.verified?
      relation_rows.push(relation.vector)
      i += 1

    expected_rows = @proof.s_prime_rows
    relation_rows.each -> (row)
      expected_rows.push(row)
    return false if !F2LinearAlgebra.same_matrix?(
      expected_rows, @proof.relation_matrix)
    rank_certificate = @proof.rank_certificate
    return false if !rank_certificate.verified?
    return false if rank_certificate.width != factor_base.size
    rank_certificate.rank == factor_base.size

  -> certified?
    verified?

  -> proves_two_torsion_trivial?
    verified?

  -> to_s
    text = "NumberFieldSClassTwoTorsionCertificate(rank "
    text + @proof.rank_certificate.rank.to_s + ")"

  -> inspect
    to_s


+ NumberFieldSClassTwoTorsionProof
  -> new(@factor_base, relation_elements)
    expected_class = "NumberFieldMinkowskiFactorBase"
    if @factor_base.class_name != expected_class
      raise "S-class proof needs a Minkowski factor base"
    if relation_elements.class_name != "Array"
      raise "S-class principal relations must be an Array"
    @principal_relations = []
    relation_elements.each -> (element)
      @principal_relations.push(
        NumberFieldPrincipalClassRelation.new(
          @factor_base, element))
    @relation_matrix = s_prime_rows
    @principal_relations.each -> (relation)
      @relation_matrix.push(relation.vector)
    @rank_certificate = compute_rank_certificate
    @certificate_cache = NumberFieldSClassTwoTorsionCertificate.new(
      self)
    if !@certificate_cache.verified?
      raise "relations do not certify trivial S-class-group 2-torsion"

  -> field
    @factor_base.field

  -> factor_base
    @factor_base

  -> s_primes
    @factor_base.s_primes

  -> principal_relations
    out = []
    @principal_relations.each -> (relation)
      out.push(relation)
    out

  -> relation_elements
    out = []
    @principal_relations.each -> (relation)
      out.push(relation.element)
    out

  -> s_prime_rows
    rows = []
    @factor_base.s_primes.each -> (prime)
      index = @factor_base.index_of(prime)
      if index == nil
        raise "S-prime is absent from its factor base"
      row = []
      @factor_base.size.times -> row.push(0)
      row[index] = 1
      rows.push(row)
    rows

  -> relation_matrix
    F2LinearAlgebra.copy_matrix(@relation_matrix)

  -> compute_rank_certificate
    system = F2LinearSystem.new(@factor_base.size)
    @relation_matrix.each -> (row)
      system.add_equation(row)
    system.certificate

  -> rank_certificate
    @rank_certificate

  -> two_torsion_trivial?
    certificate.verified?

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> to_s
    text = "SClassTwoTorsionProof(" + field.to_s
    text + ", factor base " + @factor_base.size.to_s + ")"

  -> inspect
    to_s


+ NumberFieldSClassTwoTorsionSearch
  -> new(@field, s_primes = nil,
         @coefficient_bound = 4,
         @element_limit = 100_000,
         rational_prime_limit = 100_000,
         factor_search_limit = 250_000,
         generator_search_limit = 250_000)
    if @field.class_name != "NumberField"
      raise "S-class relation search needs a NumberField"
    if @coefficient_bound < 0 || @element_limit < 1
      raise "S-class relation search bounds must be positive"
    @factor_base = NumberFieldMinkowskiFactorBase.new(
      @field, s_primes, rational_prime_limit,
      factor_search_limit, generator_search_limit)
    @relation_elements = []
    @relation_vectors = []
    @tested_elements = 0
    @rank = matrix_rank(s_prime_rows)
    seed_rational_relations if @rank < @factor_base.size
    search if @rank < @factor_base.size
    if @rank != @factor_base.size
      raise "S-class relation search limit exceeded; 2-torsion remains unknown"
    @proof = NumberFieldSClassTwoTorsionProof.new(
      @factor_base, @relation_elements)

  -> field
    @field

  -> factor_base
    @factor_base

  -> relation_elements
    out = []
    @relation_elements.each -> (element)
      out.push(element)
    out

  -> tested_elements
    @tested_elements

  -> s_prime_rows
    rows = []
    @factor_base.s_primes.each -> (prime)
      row = []
      @factor_base.size.times -> row.push(0)
      row[@factor_base.index_of(prime)] = 1
      rows.push(row)
    rows

  -> current_rows
    rows = s_prime_rows
    @relation_vectors.each -> (vector)
      rows.push(F2LinearAlgebra.copy_vector(vector))
    rows

  -> matrix_rank(rows)
    system = F2LinearSystem.new(@factor_base.size)
    rows.each -> (row)
      system.add_equation(row)
    system.rank

  -> primitive_vector?(vector)
    divisor = 0
    first_nonzero = nil
    vector.each -> (coefficient)
      if coefficient != 0
        divisor = divisor.gcd(coefficient.abs)
        first_nonzero = coefficient if first_nonzero == nil
    return false if first_nonzero == nil
    first_nonzero > 0 && divisor == 1

  -> vector_height(vector)
    height = 0
    vector.each -> (coefficient)
      height = coefficient.abs if coefficient.abs > height
    height

  -> integral_element(vector, basis)
    result = @field.zero
    i = 0
    while i < vector.size
      if vector[i] != 0
        result += basis[i] * vector[i]
      i += 1
    result

  # A principal ideal supported on the factor base can only have rational norm
  # primes represented by that base.  Strip those primes before asking the
  # ideal layer for residue-algebra decompositions; this cheaply rejects small
  # elements whose norms contain very large irrelevant prime factors.
  -> norm_support_within_factor_base?(element)
    norm = element.norm
    return false if norm == 0
    allowed = []
    @factor_base.primes.each -> (prime)
      rational_prime = prime.rational_prime
      allowed.push(rational_prime) if !allowed.include?(rational_prime)
    parts = [norm.numerator.abs, norm.denominator]
    part_index = 0
    while part_index < parts.size
      remaining = parts[part_index]
      allowed_index = 0
      while allowed_index < allowed.size
        rational_prime = allowed[allowed_index]
        while remaining % rational_prime == 0
          remaining = remaining / rational_prime
        allowed_index += 1
      return false if remaining != 1
      part_index += 1
    true

  -> candidate_relation(element)
    return nil if !norm_support_within_factor_base?(element)
    ideal = @field.principal_fractional_ideal(element)
    factors = ideal.algebra_fractional_ideal.factors
    vector = []
    @factor_base.size.times -> vector.push(0)
    i = 0
    while i < factors.size
      factor = factors[i]
      prime = NumberFieldPrimeIdeal.new(@field, factor[0])
      index = @factor_base.index_of(prime)
      return nil if index == nil
      vector[index] = factor[1].abs % 2
      i += 1
    vector

  -> add_relation_if_independent(element, relation)
    rows = current_rows
    old_rank = matrix_rank(rows)
    rows.push(relation)
    new_rank = matrix_rank(rows)
    if new_rank > old_rank
      @relation_elements.push(element)
      @relation_vectors.push(relation)
      @rank = new_rank
      return true
    false

  # Rational primes give inexpensive canonical principal relations.  They are
  # not primitive coefficient vectors, so seed them explicitly before the
  # bounded small-element enumeration.
  -> seed_rational_relations
    rational_prime = 2
    while rational_prime <= @factor_base.bound
      if rational_prime.prime?
        @tested_elements += 1
        return nil if @tested_elements > @element_limit
        element = @field.coerce(rational_prime)
        relation = candidate_relation(element)
        if relation != nil
          add_relation_if_independent(element, relation)
          return true if @rank == @factor_base.size
      rational_prime += 1
    nil

  -> search
    basis = @field.integral_basis
    height = 1
    while height <= @coefficient_bound
      radix = 2 * height + 1
      code = 0
      total = radix ** basis.size
      while code < total
        vector = []
        remaining = code
        i = 0
        while i < basis.size
          vector.push((remaining % radix) - height)
          remaining = remaining / radix
          i += 1
        selected_vector = vector_height(vector) == height
        selected_vector = false if !primitive_vector?(vector)
        if selected_vector
          @tested_elements += 1
          if @tested_elements > @element_limit
            return nil
          element = integral_element(vector, basis)
          relation = candidate_relation(element)
          if relation != nil
            add_relation_if_independent(element, relation)
            return true if @rank == @factor_base.size
        code += 1
      height += 1
    nil

  -> proof
    @proof

  -> result
    @proof

  -> certificate
    @proof.certificate

  -> certified?
    @proof.certified?

  -> to_s
    text = "SClassTwoTorsionSearch(tested "
    text + @tested_elements.to_s + ")"

  -> inspect
    to_s


+ EtaleProductSClassTwoTorsionCertificate
  -> new(@proof)
    @verified_cache = nil

  -> proof
    @proof

  -> theorem
    "class groups and S-class groups commute with finite products"

  -> proof_kind
    :trusted_theorem_import

  -> kernel_checked?
    false

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

  -> same_prime_sets?(left, right)
    return false if left.size != right.size
    i = 0
    while i < left.size
      found = false
      j = 0
      while j < right.size
        found = true if left[i].eql?(right[j])
        j += 1
      return false if !found
      i += 1
    true

  -> expected_s_primes(field)
    out = []
    @proof.rational_primes.each -> (rational_prime)
      field.prime_ideals_above(
        rational_prime).each -> (prime)
        out.push(prime)
    out

  -> verify!
    expected_class = "EtaleProductSClassTwoTorsionProof"
    return false if @proof.class_name != expected_class
    order = @proof.order
    return false if order.class_name != "EtaleProductOrder"
    return false if !order.certificate.verified?
    rational_primes = @proof.rational_primes
    i = 0
    while i < rational_primes.size
      return false if !rational_primes[i].prime?
      j = 0
      while j < i
        return false if rational_primes[j] == rational_primes[i]
        j += 1
      i += 1
    component_proofs = @proof.component_proofs
    return false if component_proofs.size != order.component_count
    component_orders = order.component_algebra_orders
    component_index = 0
    while component_index < component_proofs.size
      proofs = component_proofs[component_index]
      return false if proofs.class_name != "Array"
      return false if proofs.size == 0
      component_polynomial = component_orders[
        component_index].algebra.defining_polynomial.monic
      product = component_polynomial.ring.one
      i = 0
      while i < proofs.size
        field_proof = proofs[i]
        proof_class = "NumberFieldSClassTwoTorsionProof"
        return false if field_proof.class_name != proof_class
        return false if !field_proof.certificate.verified?
        field = field_proof.field
        polynomial = field.defining_polynomial
        return false if polynomial.ring != component_polynomial.ring
        j = 0
        while j < i
          previous = proofs[j].field.defining_polynomial
          return false if polynomial.gcd(previous).degree != 0
          j += 1
        product *= polynomial.monic
        expected_primes = expected_s_primes(field)
        return false if !same_prime_sets?(
          expected_primes, field_proof.s_primes)
        i += 1
      return false if !product.monic.eql?(component_polynomial)
      component_index += 1
    true

  -> certified?
    verified?

  -> proves_two_torsion_trivial?
    verified?

  -> to_s
    text = "EtaleProductSClassTwoTorsionCertificate("
    text + @proof.field_count.to_s + " fields)"

  -> inspect
    to_s


+ EtaleProductSClassTwoTorsionProof
  -> new(@order, rational_primes, component_proofs)
    if @order.class_name != "EtaleProductOrder"
      raise "product S-class proof needs an EtaleProductOrder"
    if rational_primes.class_name != "Array"
      raise "product S-class rational primes must be an Array"
    if component_proofs.class_name != "Array"
      raise "product S-class component proofs must be an Array"
    @rational_primes = []
    rational_primes.each -> (prime)
      @rational_primes.push(prime)
    @component_proofs = []
    component_proofs.each -> (proofs)
      if proofs.class_name != "Array"
        raise "each etale component needs an Array of field proofs"
      copied = []
      proofs.each -> (proof)
        copied.push(proof)
      @component_proofs.push(copied)
    @certificate_cache = EtaleProductSClassTwoTorsionCertificate.new(
      self)
    if !@certificate_cache.verified?
      raise "product S-class 2-torsion proof failed certification"

  -> order
    @order

  -> rational_primes
    out = []
    @rational_primes.each -> (prime)
      out.push(prime)
    out

  -> component_proofs
    out = []
    @component_proofs.each -> (proofs)
      copied = []
      proofs.each -> (proof)
        copied.push(proof)
      out.push(copied)
    out

  -> field_count
    count = 0
    @component_proofs.each -> (proofs)
      count += proofs.size
    count

  -> certificate
    @certificate_cache

  -> two_torsion_trivial?
    certificate.verified?

  -> certified?
    certificate.verified?

  -> to_s
    text = "EtaleProductSClassTwoTorsionProof("
    text + field_count.to_s + " fields)"

  -> inspect
    to_s


+ NumberField
  -> minkowski_factor_base(
       s_primes = nil,
       rational_prime_limit = 100_000,
       factor_search_limit = 250_000,
       generator_search_limit = 250_000)
    NumberFieldMinkowskiFactorBase.new(
      self, s_primes, rational_prime_limit,
      factor_search_limit, generator_search_limit)

  -> certify_s_class_two_torsion(
       s_primes = nil,
       coefficient_bound = 4,
       element_limit = 100_000,
       rational_prime_limit = 100_000,
       factor_search_limit = 250_000,
       generator_search_limit = 250_000)
    NumberFieldSClassTwoTorsionSearch.new(
      self, s_primes, coefficient_bound,
      element_limit, rational_prime_limit,
      factor_search_limit,
      generator_search_limit).proof
