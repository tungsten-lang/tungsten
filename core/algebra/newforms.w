# Simultaneous weight-two Hecke eigenpackets and normalized rational
# newforms from the new Hecke quotient.
#
# The packet splitter forms a deterministic primitive element of the
# commutative Hecke algebra from T_n through Sturm's bound.  Factoring its
# characteristic polynomial separates Galois orbits, while the plus/minus
# modular-symbol periods explain why every irreducible factor occurs twice.
# All matrix and factor identities are replayed exactly.  Semisimplicity,
# multiplicity one, and Sturm sufficiency remain named theorem imports.

+ WeightTwoHeckeEigenpacketDecomposition
  -> new(group, @search_limit = 1_000_000)
    @group = group.class_name == "Gamma0" ? group : Gamma0.new(group)
    @symbols = WeightTwoModularSymbols.new(
      @group, 2, @search_limit)
    @old_new = @symbols.old_new_decomposition
    @sturm_bound = @group.sturm(2)
    if @old_new.new_dimension.odd?
      raise "weight-two new modular-symbol dimension must be even"
    @separator_coefficients = []
    i = 0
    while i <= @sturm_bound.bound
      @separator_coefficients.push(0)
      i += 1
    @separator_matrix = produce_separator
    @packets = produce_packets
    @certificate = WeightTwoHeckeEigenpacketDecompositionCertificate.new(
      self)
    if !@certificate.verified?
      raise "weight-two Hecke eigenpacket certificate failed"

  -> group
    @group

  -> level
    @group.level

  -> weight
    2

  -> search_limit
    @search_limit

  -> symbols
    @symbols

  -> old_new_decomposition
    @old_new

  -> sturm_bound
    @sturm_bound

  -> new_dimension
    @old_new.new_dimension

  -> separator_coefficients
    out = []
    @separator_coefficients.each -> out.push(item)
    out

  -> separator_matrix
    ModularSymbolsLinearAlgebra.copy_matrix(@separator_matrix)

  -> .distinct_factors(polynomial, search_limit)
    out = []
    polynomial.factor(search_limit).each -> (factor)
      if factor.degree > 0
        found = false
        out.each -> (existing)
          found = true if existing.eql?(factor)
        out.push(factor) if !found
    out

  -> .squarefree_degree(polynomial, search_limit)
    total = 0
    WeightTwoHeckeEigenpacketDecomposition.distinct_factors(
      polynomial, search_limit).each -> (factor)
      total += factor.degree
    total

  # A finite product of characteristic-zero coefficient fields is generated
  # by one generic linear combination.  At most d(d-1)/2 coefficients collide
  # on a set of d embeddings, so testing one more integer coefficient makes
  # each primitive-element choice deterministic and exhaustive.
  -> produce_separator
    dimension = new_dimension
    return [] if dimension == 0
    form_dimension = dimension / 2
    separator = HeckeLinearAlgebra.zero_matrix(dimension)
    collision_bound = form_dimension*(form_dimension - 1) / 2
    index = 2
    while index <= @sturm_bound.bound
      operator = @old_new.new_hecke_matrix(index)
      best_matrix = separator
      best_coefficient = 0
      best_degree = (
        WeightTwoHeckeEigenpacketDecomposition.squarefree_degree(
          HeckeLinearAlgebra.characteristic_polynomial(separator),
          @search_limit))
      coefficient = 1
      while coefficient <= collision_bound + 1
        candidate = HeckeLinearAlgebra.matrix_add(
          separator,
          HeckeLinearAlgebra.matrix_scale(operator, coefficient))
        candidate_degree = (
          WeightTwoHeckeEigenpacketDecomposition.squarefree_degree(
            HeckeLinearAlgebra.characteristic_polynomial(candidate),
            @search_limit))
        if candidate_degree > best_degree
          best_degree = candidate_degree
          best_coefficient = coefficient
          best_matrix = candidate
        coefficient += 1
        coefficient = collision_bound + 2 if best_degree == form_dimension
      separator = best_matrix
      @separator_coefficients[index] = best_coefficient
      index = @sturm_bound.bound + 1 if best_degree == form_dimension
      index += 1
    final_polynomial = HeckeLinearAlgebra.characteristic_polynomial(
      separator)
    final_degree = (
      WeightTwoHeckeEigenpacketDecomposition.squarefree_degree(
        final_polynomial, @search_limit))
    if final_degree != form_dimension
      raise "Hecke operators through the Sturm bound did not generate the expected semisimple algebra"
    separator

  -> produce_packets
    return [] if new_dimension == 0
    characteristic = HeckeLinearAlgebra.characteristic_polynomial(
      @separator_matrix)
    factors = WeightTwoHeckeEigenpacketDecomposition.distinct_factors(
      characteristic, @search_limit)
    packets = []
    factors.each -> (factor)
      annihilator = HeckeLinearAlgebra.matrix_polynomial(
        factor, @separator_matrix)
      basis = HeckeLinearAlgebra.left_kernel(annihilator)
      if basis.size != 2*factor.degree
        raise "Hecke packet does not have the expected plus/minus multiplicity"
      packets.push(WeightTwoHeckeEigenpacket.new(
        self, factor, basis))
    combined = []
    packets.each -> (packet)
      packet.basis.each -> (row)
        combined.push(row)
    if ModularSymbolsLinearAlgebra.rank(combined) != new_dimension
      raise "Hecke eigenpackets do not span the new quotient"
    packets

  -> packets
    out = []
    @packets.each -> out.push(item)
    out

  -> size
    @packets.size

  -> [](index)
    @packets[index]

  -> rational_packets
    out = []
    @packets.each -> (packet)
      out.push(packet) if packet.rational?
    out

  -> certificate
    @certificate

  -> certified?
    @certificate.verified?

  -> to_s
    ("HeckeEigenpackets(Gamma0(" + level.to_s +
      "), packets=" + size.to_s + ")")

  -> inspect
    to_s


+ WeightTwoHeckeEigenpacket
  -> new(@decomposition, @separator_polynomial, basis)
    @basis = ModularSymbolsLinearAlgebra.copy_matrix(basis)
    @separator_action = HeckeLinearAlgebra.restrict_operator(
      @decomposition.separator_matrix, @basis)
    @coefficient_field = nil
    @eigenvalues = {}
    @eigenvalue_certificates = {}

  -> decomposition
    @decomposition

  -> group
    @decomposition.group

  -> level
    group.level

  -> weight
    2

  -> basis
    ModularSymbolsLinearAlgebra.copy_matrix(@basis)

  -> dimension
    @basis.size

  -> coefficient_field_degree
    @separator_polynomial.degree

  -> rational?
    coefficient_field_degree == 1

  -> separator_polynomial
    @separator_polynomial

  -> separator_action
    ModularSymbolsLinearAlgebra.copy_matrix(@separator_action)

  -> coefficient_field
    if @coefficient_field == nil
      if rational?
        @coefficient_field = RationalField.new
      else
        @coefficient_field = NumberField.new(
          @separator_polynomial, :theta)
    @coefficient_field

  -> hecke_matrix(index)
    matrix = @decomposition.old_new_decomposition.new_hecke_matrix(
      index)
    HeckeLinearAlgebra.restrict_operator(matrix, @basis)

  -> .flatten_matrix(matrix)
    out = []
    matrix.each -> (row)
      row.each -> (entry)
        out.push(Rational.coerce(entry))
    out

  # Each Hecke operator is a unique polynomial of degree < [K:Q] in the
  # chosen primitive separator.  Solving this exact rational span recovers
  # the corresponding coefficient-field element.
  -> hecke_eigenvalue(index)
    if !ModularFormsArithmetic.integer?(index) || index < 1
      raise "newform Hecke eigenvalue needs a positive index"
    key = index.to_s
    if @eigenvalues[key] == nil
      powers = []
      power = HeckeLinearAlgebra.identity(dimension)
      exponent = 0
      while exponent < coefficient_field_degree
        powers.push(
          WeightTwoHeckeEigenpacket.flatten_matrix(power))
        power = HeckeLinearAlgebra.matrix_product(
          power, @separator_action)
        exponent += 1
      target = WeightTwoHeckeEigenpacket.flatten_matrix(
        hecke_matrix(index))
      coordinates = HeckeLinearAlgebra.row_span_coordinates(
        powers, target)
      if rational?
        @eigenvalues[key] = coordinates[0]
      else
        @eigenvalues[key] = coefficient_field.coerce(coordinates)
    @eigenvalues[key]

  -> coefficient(index)
    hecke_eigenvalue(index)

  -> hecke_eigenvalue_certificate(index)
    key = index.to_s
    if @eigenvalue_certificates[key] == nil
      @eigenvalue_certificates[key] = (
        WeightTwoHeckeEigenvalueCertificate.new(self, index))
    @eigenvalue_certificates[key]

  -> hecke_eigenvalue_certified?(index)
    hecke_eigenvalue_certificate(index).verified?

  -> coefficients(precision)
    if !ModularFormsArithmetic.integer?(precision) || precision < 2
      raise "newform precision must be at least two"
    out = [coefficient_field.zero]
    index = 1
    while index < precision
      out.push(coefficient(index))
      index += 1
    out

  -> q_expansion(precision = 12)
    values = coefficients(precision)
    return QExpansion.new(values) if rational?
    FieldQExpansion.new(coefficient_field, values)

  -> q_expansion_certificate(precision = 12)
    WeightTwoHeckeEigenpacketQExpansionCertificate.new(
      self, precision, q_expansion(precision))

  -> certified?
    @decomposition.certified?

  -> to_s
    ("HeckeEigenpacket(Gamma0(" + level.to_s +
      "), degree=" + coefficient_field_degree.to_s + ")")

  -> inspect
    to_s


+ WeightTwoHeckeEigenvalueCertificate
  -> new(@packet, @index)
    @verified_cache = nil

  -> packet
    @packet

  -> index
    @index

  -> theorem
    "normalized newform coefficient is the T_n eigenvalue"

  -> theorem_reference
    "newform Hecke eigenvalue/q-expansion correspondence"

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
    return false if @packet.class_name != "WeightTwoHeckeEigenpacket"
    if !ModularFormsArithmetic.integer?(@index) || @index < 1
      return false
    return false if !@packet.decomposition.certified?
    operator = @packet.decomposition.symbols.hecke_operator(@index)
    return false if !operator.certificate.verified?
    eigenvalue = @packet.hecke_eigenvalue(@index)
    coefficients = nil
    if @packet.rational?
      coefficients = [Rational.coerce(eigenvalue)]
    else
      coefficients = eigenvalue.coefficients
    ring = @packet.separator_polynomial.ring
    x = ring.generator(0)
    polynomial = ring.zero
    exponent = 0
    while exponent < coefficients.size
      polynomial += x**exponent * coefficients[exponent]
      exponent += 1
    expected_action = HeckeLinearAlgebra.matrix_polynomial(
      polynomial, @packet.separator_action)
    action = @packet.hecke_matrix(@index)
    return false if !ModularSymbolsLinearAlgebra.same_matrix?(
      expected_action, action)
    characteristic = HeckeLinearAlgebra.characteristic_polynomial(
      action)
    if @packet.rational?
      return characteristic == (
        (x - eigenvalue)**@packet.dimension)
    characteristic == (
      @packet.coefficient_field.characteristic_polynomial(
        eigenvalue)**2)

  -> certified?
    verified?

  -> to_s
    ("HeckeEigenvalueCertificate(N=" +
      @packet.level.to_s + ", n=" + @index.to_s + ")")

  -> inspect
    to_s


+ WeightTwoHeckeEigenpacketQExpansionCertificate
  -> new(@packet, @precision, @q_expansion)
    @verified_cache = nil

  -> packet
    @packet

  -> precision
    @precision

  -> q_expansion
    @q_expansion

  -> theorem
    "normalized newform q-expansion from exact Hecke eigenvalues"

  -> theorem_reference
    "newform Hecke eigenvalue/q-expansion correspondence"

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
    return false if @packet.class_name != "WeightTwoHeckeEigenpacket"
    if !ModularFormsArithmetic.integer?(@precision) || @precision < 2
      return false
    expected_class = @packet.rational? ? "QExpansion" : "FieldQExpansion"
    return false if @q_expansion.class_name != expected_class
    return false if @q_expansion.precision != @precision
    if @packet.rational?
      return false if @q_expansion.coefficient(0) != Rational.new(0)
    else
      return false if !@packet.coefficient_field.zero?(
        @q_expansion.coefficient(0))
    index = 1
    while index < @precision
      certificate = @packet.hecke_eigenvalue_certificate(index)
      return false if !certificate.verified?
      return false if (
        @q_expansion.coefficient(index) !=
        @packet.hecke_eigenvalue(index))
      index += 1
    true

  -> certified?
    verified?

  -> to_s
    ("HeckeEigenpacketQExpansionCertificate(N=" +
      @packet.level.to_s + ", precision=" +
      @precision.to_s + ")")

  -> inspect
    to_s


+ WeightTwoHeckeEigenpacketDecompositionCertificate
  -> new(@decomposition)
    @verified_cache = nil

  -> decomposition
    @decomposition

  -> theorem
    "simultaneous weight-two newform decomposition through the Sturm bound"

  -> theorem_reference
    "Sturm coefficient bound, Hecke semisimplicity, and strong multiplicity one"

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
    if @decomposition.class_name != "WeightTwoHeckeEigenpacketDecomposition"
      return false
    old_new = @decomposition.old_new_decomposition
    return false if !old_new.certificate.verified?
    sturm = @decomposition.sturm_bound
    return false if !sturm.certificate.verified?
    dimension = @decomposition.new_dimension
    return false if dimension.odd?
    coefficients = @decomposition.separator_coefficients
    return false if coefficients.size != sturm.bound + 1
    expected_separator = HeckeLinearAlgebra.zero_matrix(dimension)
    index = 2
    while index <= sturm.bound
      if coefficients[index] != 0
        expected_separator = HeckeLinearAlgebra.matrix_add(
          expected_separator,
          HeckeLinearAlgebra.matrix_scale(
            old_new.new_hecke_matrix(index),
            coefficients[index]))
      index += 1
    if !ModularSymbolsLinearAlgebra.same_matrix?(
         expected_separator, @decomposition.separator_matrix)
      return false

    combined = []
    packets = @decomposition.packets
    packet_index = 0
    while packet_index < packets.size
      packet = packets[packet_index]
      factor = packet.separator_polynomial
      return false if factor.degree < 1
      return false if !factor.eql?(factor.monic)
      irreducible_factors = factor.factor(
        @decomposition.search_limit)
      return false if irreducible_factors.size != 1
      return false if !irreducible_factors[0].eql?(factor)
      return false if packet.dimension != 2*factor.degree
      return false if (
        HeckeLinearAlgebra.characteristic_polynomial(
          packet.separator_action) != factor**2)
      packet.basis.each -> (row)
        combined.push(row)
      # Replay only the Hecke operators actually used to construct the
      # primitive separator.  Once its squarefree degree is dim/2, it already
      # has the maximum possible number of eigenvalues; constructing every
      # unused T_n through the Sturm bound would add no evidence.
      index = 2
      while index <= sturm.bound
        if coefficients[index] != 0
          action = packet.hecke_matrix(index)
          eigenvalue = packet.hecke_eigenvalue(index)
          expected_characteristic = nil
          if packet.rational?
            ring = factor.ring
            x = ring.generator(0)
            expected_characteristic = (
              (x - eigenvalue)**packet.dimension)
          else
            expected_characteristic = (
              packet.coefficient_field.characteristic_polynomial(
                eigenvalue)**2)
          if (HeckeLinearAlgebra.characteristic_polynomial(action) !=
              expected_characteristic)
            return false
        index += 1
      packet_index += 1
    if ModularSymbolsLinearAlgebra.rank(combined) != dimension
      return false
    @decomposition.packets.size == 0 || dimension > 0

  -> certified?
    verified?

  -> to_s
    ("WeightTwoHeckeEigenpacketCertificate(N=" +
      @decomposition.level.to_s + ")")

  -> inspect
    to_s

+ RationalWeightTwoNewform
  -> new(group, @precision = 12,
         @search_limit = 1_000_000)
    @group = group.class_name == "Gamma0" ? group : Gamma0.new(group)
    if !ModularFormsArithmetic.integer?(@precision) || @precision < 2
      raise "rational newform precision must be at least two"
    @symbols = WeightTwoModularSymbols.new(
      @group, 2, @search_limit)
    @old_new = @symbols.old_new_decomposition
    if @old_new.new_dimension != 2
      raise "rational newform recovery needs a two-dimensional new symbol quotient"
    @eigenvalues = {}
    @q_expansion = produce_q_expansion
    @certificate = RationalWeightTwoNewformCertificate.new(self)
    raise "rational weight-two newform certificate failed" if !@certificate.verified?

  -> group
    @group

  -> level
    @group.level

  -> weight
    2

  -> precision
    @precision

  -> symbols
    @symbols

  -> old_new_decomposition
    @old_new

  -> hecke_eigenvalue(prime)
    if prime < 2 || !prime.prime?
      raise "newform Hecke eigenvalue needs a prime"
    key = prime.to_s
    if @eigenvalues[key] == nil
      matrix = @old_new.new_hecke_matrix(prime)
      wrong_size = matrix.size != 2
      wrong_size = true if !wrong_size && matrix[0].size != 2
      wrong_size = true if !wrong_size && matrix[1].size != 2
      if wrong_size
        raise "rational newform needs a two-dimensional Hecke matrix"
      zero = Rational.new(0)
      not_scalar = matrix[0][1] != zero || matrix[1][0] != zero
      not_scalar = true if !not_scalar && matrix[0][0] != matrix[1][1]
      if not_scalar
        raise "new Hecke quotient is not one rational eigenpacket"
      @eigenvalues[key] = matrix[0][0]
    @eigenvalues[key]

  -> prime_power_coefficient(prime, exponent)
    return Rational.new(1) if exponent == 0
    eigenvalue = hecke_eigenvalue(prime)
    return eigenvalue if exponent == 1
    if level % prime == 0
      return eigenvalue**exponent
    previous_previous = Rational.new(1)
    previous = eigenvalue
    power = 2
    while power <= exponent
      current = (
        eigenvalue*previous -
        Rational.new(prime)*previous_previous)
      previous_previous = previous
      previous = current
      power += 1
    previous

  -> coefficient(index)
    if !ModularFormsArithmetic.integer?(index) || index < 1
      raise "normalized newform coefficient needs a positive index"
    result = Rational.new(1)
    index.factor.each -> (factor)
      result *= prime_power_coefficient(
        factor.prime, factor.exponent)
    result

  -> produce_q_expansion
    coefficients = [Rational.new(0)]
    n = 1
    while n < @precision
      coefficients.push(coefficient(n))
      n += 1
    QExpansion.new(coefficients)

  -> q_expansion
    @q_expansion

  -> certificate
    @certificate

  -> certified?
    @certificate.verified?

  -> to_s
    ("RationalNewform(Gamma0(" + level.to_s +
      "), weight=2, precision=" + @precision.to_s + ")")

  -> inspect
    to_s


+ RationalWeightTwoNewformCertificate
  -> new(@newform)
    @verified_cache = nil

  -> newform
    @newform

  -> theorem
    "normalized eigenform coefficients from Hecke eigenvalues and Euler factors"

  -> theorem_reference
    "Atkin-Lehner-Li newform theory and the Hecke multiplicativity relations"

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
    if @newform.class_name != "RationalWeightTwoNewform"
      return false
    return false if !@newform.group.certificate.verified?
    decomposition = @newform.old_new_decomposition
    return false if !decomposition.certificate.verified?
    return false if decomposition.new_dimension != 2
    expansion = @newform.q_expansion
    return false if expansion.class_name != "QExpansion"
    return false if expansion.precision != @newform.precision
    return false if expansion.coefficient(0) != Rational.new(0)
    return false if expansion.coefficient(1) != Rational.new(1)
    n = 1
    while n < @newform.precision
      return false if expansion.coefficient(n) != @newform.coefficient(n)
      n += 1
    true

  -> certified?
    verified?

  -> to_s
    ("RationalWeightTwoNewformCertificate(N=" +
      @newform.level.to_s + ", precision=" +
      @newform.precision.to_s + ")")

  -> inspect
    to_s


+ WeightTwoOldNewDecomposition
  -> eigenpackets
    WeightTwoHeckeEigenpacketDecomposition.new(
      @space.group, @space.search_limit)

  -> rational_newform(precision = 12)
    RationalWeightTwoNewform.new(
      @space.group, precision, @space.search_limit)


+ WeightTwoModularSymbols
  -> eigenpackets
    WeightTwoHeckeEigenpacketDecomposition.new(
      @group, @search_limit)


+ Gamma0
  -> eigenpackets(search_limit = 1_000_000)
    WeightTwoHeckeEigenpacketDecomposition.new(
      self, search_limit)

  -> rational_newform(precision = 12,
                      search_limit = 1_000_000)
    RationalWeightTwoNewform.new(
      self, precision, search_limit)
