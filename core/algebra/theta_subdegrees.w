# Exact characteristic-zero subdegree data for the shell-width bitangents.
#
# The degree-27 bitangent projection is factored over its degree-six
# component. The displayed factors are replayed by exact multiplication.
# Relative irreducibility is proved by finite residue factorizations; the two
# sextics use the incompatible patterns 2+2+2 and 3+3.

+ ShellWidthThetaSubdegreeCertificate
  -> new(@scheme_certificate, payloads)
    if @scheme_certificate.class_name != "PlaneQuarticBitangentSchemeCertificate"
      raise "theta subdegrees need a bitangent-scheme certificate"
    if !@scheme_certificate.verified?
      raise "theta subdegrees need a verified bitangent scheme"
    @payloads = []
    payloads.each -> @payloads.push(item)
    prepare_arithmetic
    @verified_cache = nil
    if !verified?
      raise "shell-width theta subdegree certificate failed"

  -> scheme_certificate
    @scheme_certificate

  -> base_field
    @base_field

  -> relative_projection
    @relative_projection

  -> relative_factors
    out = []
    @relative_factors.each -> out.push(item)
    out

  -> component_irreducibility_certificates
    out = []
    @component_irreducibility.each -> out.push(item)
    out

  -> relative_irreducibility_certificates
    out = []
    @relative_irreducibility.each -> out.push(item)
    out

  -> component_polynomials
    out = []
    @scheme_certificate.primary_certificate.components.each ->
      out.push(item.factor)
    out

  -> certificate_verified?(certificate)
    return true if certificate == true
    certificate != nil && certificate.verified?

  -> degree_nine_irreducibility_certificate(source)
    ring = source.ring
    x = ring.generator(0)
    model = x**9 - x**8 + x**7*6 - x**6*2
    model = model - x**5*4 - x**4*4 - x**2*4 - x*3 - 1

    base = NumberField.new(
      x**3 - x**2*4 + x*14 - 12, :u)
    relative_ring = PolynomialRing.new([:z], base)
    z = relative_ring.generator(0)
    relative = z**3 + z**2*(base.one - base.generator)
    relative = relative - z - 1
    relative_certificate = NumberField.relative_modular_irreducibility_certificate(
      relative, 20)
    model_certificate = NumberField.tower_irreducibility_certificate(
      model, relative, relative_certificate)

    source_root = x**8 * Rational.new(-147, 44)
    source_root = source_root + x**7 * Rational.new(171, 44)
    source_root = source_root - x**6 * Rational.new(819, 44)
    source_root = source_root + x**5 * Rational.new(357, 44)
    source_root = source_root + x**4 * Rational.new(1053, 44)
    source_root = source_root + x**3 * Rational.new(309, 44)
    source_root = source_root - x**2 * Rational.new(501, 44)
    source_root = source_root - x * Rational.new(3, 44)
    source_root = source_root + Rational.new(24, 11)
    NumberField.isomorphic_model_irreducibility_certificate(
      source, model, source_root, model_certificate)

  -> degree_twelve_irreducibility_certificate(source)
    ring = source.ring
    x = ring.generator(0)
    model = x**12 - x**11*6 + x**10*17 - x**9*30
    model = model + x**8*36 - x**7*30 + x**6*19
    model = model - x**5*12 + x**4*6 - x**2 + 1

    base_polynomial = x**6 - x**5*2 + x**4 - x**3*2 - x**2 + 1
    base_certificate = NumberField.modular_irreducibility_certificate(
      base_polynomial, 20)
    base = NumberField.new(
      base_polynomial, :u, base_certificate)
    relative_ring = PolynomialRing.new([:z], base)
    z = relative_ring.generator(0)
    relative = z**2 - z + base.generator
    relative_certificate = NumberField.relative_modular_irreducibility_certificate(
      relative, 20)
    model_certificate = NumberField.tower_irreducibility_certificate(
      model, relative, relative_certificate)

    source_root = x**11 * Rational.new(1467, 122)
    source_root = source_root - x**10 * Rational.new(4446, 61)
    source_root = source_root + x**9 * Rational.new(12168, 61)
    source_root = source_root - x**8 * Rational.new(657, 2)
    source_root = source_root + x**7 * Rational.new(43479, 122)
    source_root = source_root - x**6 * Rational.new(31329, 122)
    source_root = source_root + x**5 * Rational.new(8712, 61)
    source_root = source_root - x**4 * Rational.new(6642, 61)
    source_root = source_root + x**3 * Rational.new(7101, 122)
    source_root = source_root + x**2 * Rational.new(2727, 122)
    source_root = source_root - x * Rational.new(189, 61)
    source_root = source_root - Rational.new(2385, 122)
    NumberField.isomorphic_model_irreducibility_certificate(
      source, model, source_root, model_certificate)

  -> prepare_arithmetic
    components = component_polynomials
    if components.size != 3
      raise "shell-width theta subdegrees need three projection components"
    degree_six_certificate = NumberField.modular_irreducibility_certificate(
      components[0], 20)
    @base_field = NumberField.new(
      components[0], :a, degree_six_certificate)
    @component_irreducibility = [
      @base_field.irreducibility_certificate,
      degree_nine_irreducibility_certificate(components[1]),
      degree_twelve_irreducibility_certificate(components[2])
    ]

    ring = PolynomialRing.new([:v], @base_field, :lex)
    @relative_projection = ring.zero
    source_projection = @scheme_certificate.projection_polynomial.monic
    source_projection.each_term -> (coefficient, exponents)
      term = ring.monomial(
        @base_field.coerce(coefficient), exponents)
      @relative_projection = @relative_projection + term

    @relative_factors = []
    @payloads.each -> (payload)
      terms = []
      exponent = 0
      while exponent < payload.size
        coordinates = []
        payload[exponent].each -> (pair)
          coordinates.push(Rational.new(pair[0], pair[1]))
        coefficient = @base_field.coerce(coordinates)
        terms.push([coefficient, [exponent]]) if !coefficient.zero?
        exponent += 1
      @relative_factors.push(Polynomial.new(ring, terms))

    mod_11_root_7 = NumberFieldPowerBasisPrimeReduction.new(
      @base_field, 11, 7)
    mod_11_root_2 = NumberFieldPowerBasisPrimeReduction.new(
      @base_field, 11, 2)
    mod_61_root_47 = NumberFieldPowerBasisPrimeReduction.new(
      @base_field, 61, 47)
    reductions = [
      nil,
      [mod_11_root_7],
      [mod_11_root_7],
      [mod_11_root_7],
      [mod_11_root_2],
      [mod_61_root_47],
      [mod_61_root_47],
      [mod_11_root_7, mod_61_root_47],
      [mod_11_root_2, mod_61_root_47]
    ]
    @relative_irreducibility = []
    index = 0
    while index < @relative_factors.size
      if @relative_factors[index].degree == 1
        @relative_irreducibility.push(nil)
      else
        helper = NumberFieldRelativeModularDegreeIrreducibilityCertificate
        certificate = helper.new(
          @relative_factors[index], reductions[index])
        @relative_irreducibility.push(certificate)
      index += 1

  -> recomposed_projection
    product = @relative_projection.ring.one
    @relative_factors.each -> product = product * item
    product

  -> relative_factor_degrees
    degrees = []
    @relative_factors.each -> degrees.push(item.degree)
    GenusThreeThetaPermutation.sort_integers(degrees)

  -> orbit_signature
    degrees = [1]
    @scheme_certificate.component_degrees.each -> degrees.push(item)
    GenusThreeThetaPermutation.sort_integers(degrees)

  -> stabilizer_subdegrees
    degrees = [1]
    relative_factor_degrees.each -> degrees.push(item)
    GenusThreeThetaPermutation.sort_integers(degrees)

  -> relative_factor_degree_patterns
    out = []
    index = 0
    while index < @relative_factors.size
      certificate = @relative_irreducibility[index]
      if certificate == nil
        out.push([1])
      else
        out.push(certificate.factor_degree_patterns)
      index += 1
    out

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
    return false if !@scheme_certificate.verified?
    return false if @scheme_certificate.component_degrees.to_s != "\[6, 9, 12\]"
    components = component_polynomials
    return false if components.size != @component_irreducibility.size
    index = 0
    while index < components.size
      certificate = @component_irreducibility[index]
      return false if !certificate_verified?(certificate)
      if certificate != true
        return false if !certificate.polynomial.monic.eql?(
          components[index].monic)
      index += 1

    return false if @relative_projection.degree != 27
    return false if @relative_factors.size != 9
    return false if !recomposed_projection.eql?(@relative_projection)
    return false if relative_factor_degrees.to_s != "\[1, 2, 2, 2, 2, 3, 3, 6, 6\]"
    index = 0
    while index < @relative_factors.size
      certificate = @relative_irreducibility[index]
      if @relative_factors[index].degree == 1
        return false if certificate != nil
      else
        return false if certificate == nil || !certificate.verified?
        return false if !certificate.polynomial.eql?(
          @relative_factors[index])
      index += 1
    return false if orbit_signature.to_s != "\[1, 6, 9, 12\]"
    stabilizer_subdegrees.to_s == "\[1, 1, 2, 2, 2, 2, 3, 3, 6, 6\]"

  -> certified?
    verified?

  -> proof_kind
    :exact_relative_factorization_with_modular_irreducibility

  -> kernel_checked?
    true

  -> arithmetic_invariants_checked?
    verified?

  -> .shell_width(scheme_certificate)
    payloads = [
      [
        [[0,1],[-1,1],[0,1],[0,1],[0,1],[0,1]],
        [[1,1],[0,1],[0,1],[0,1],[0,1],[0,1]]
      ],
      [
        [[297,2],[-72,1],[-4,1],[118,27],[-52,81],[-20,243]],
        [[9,1],[-3,1],[0,1],[0,1],[0,1],[0,1]],
        [[1,1],[0,1],[0,1],[0,1],[0,1],[0,1]]
      ],
      [
        [[5211,2],[-1125,1],[-127,1],[2258,27],[-1028,81],[-376,243]],
        [[615,1],[-256,1],[-274,9],[4708,243],[-2104,729],[-776,2187]],
        [[1,1],[0,1],[0,1],[0,1],[0,1],[0,1]]
      ],
      [
        [[-54,1],[9,1],[10,3],[-32,27],[8,81],[4,243]],
        [[10,1],[1,3],[-14,27],[148,729],[8,2187],[-8,6561]],
        [[1,1],[0,1],[0,1],[0,1],[0,1],[0,1]]
      ],
      [
        [[-162,1],[27,1],[10,1],[-32,9],[8,27],[4,81]],
        [[-567,1],[257,1],[260,9],[-1520,81],[704,243],[256,729]],
        [[1,1],[0,1],[0,1],[0,1],[0,1],[0,1]]
      ],
      [
        [[-11421,2],[4941,2],[279,1],[-559,3],[250,9],[92,27]],
        [[675,1],[-297,1],[-34,1],[592,27],[-292,81],[-104,243]],
        [[366,1],[-155,1],[-158,9],[2828,243],[-1292,729],[-472,2187]],
        [[1,1],[0,1],[0,1],[0,1],[0,1],[0,1]]
      ],
      [
        [[243,4],[0,1],[0,1],[0,1],[0,1],[0,1]],
        [[9,2],[-3,1],[-7,3],[74,81],[4,243],[-4,729]],
        [[-4,1],[2,3],[14,27],[-148,729],[-8,2187],[8,6561]],
        [[1,1],[0,1],[0,1],[0,1],[0,1],[0,1]]
      ],
      [
        [[1594323,16],[0,1],[0,1],[0,1],[0,1],[0,1]],
        [[0,1],[0,1],[0,1],[0,1],[0,1],[0,1]],
        [[-2187,1],[729,2],[567,2],[-111,1],[-2,1],[2,3]],
        [[-2187,2],[486,1],[378,1],[-148,1],[-8,3],[8,9]],
        [[-162,1],[108,1],[84,1],[-296,9],[-16,27],[16,81]],
        [[15,1],[2,1],[14,9],[-148,243],[-8,729],[8,2187]],
        [[1,1],[0,1],[0,1],[0,1],[0,1],[0,1]]
      ],
      [
        [[2421009,8],[-1121931,8],[-45927,4],[37503,4],[-3051,2],[-180,1]],
        [[-111537,1],[199017,4],[10935,2],[-3798,1],[573,1],[70,1]],
        [[72171,4],[-31833,4],[-1593,2],[567,1],[-81,1],[-10,1]],
        [[26811,4],[-6615,2],[-186,1],[1843,9],[-922,27],[-320,81]],
        [[-2367,1],[1023,1],[422,3],[-6704,81],[2936,243],[1096,729]],
        [[-336,1],[155,1],[158,9],[-2828,243],[1292,729],[472,2187]],
        [[1,1],[0,1],[0,1],[0,1],[0,1],[0,1]]
      ]
    ]
    ShellWidthThetaSubdegreeCertificate.new(
      scheme_certificate, payloads)


+ ShellWidthThetaGaloisCertificate
  -> new(@subdegrees)
    if @subdegrees.class_name != "ShellWidthThetaSubdegreeCertificate"
      raise "shell-width theta Galois certificate needs exact subdegrees"
    @identification = GenusThreeThetaSubgroupIdentificationCertificate.new(
      TrustedThetaSubgroupClassTable.shell_width,
      @subdegrees.orbit_signature,
      @subdegrees.stabilizer_subdegrees,
      [])
    if !verified?
      raise "shell-width theta Galois subgroup did not verify"

  -> subdegree_certificate
    @subdegrees

  -> identification
    @identification

  -> identified_candidate
    @identification.identified_candidate

  -> verified?
    return false if !@subdegrees.verified?
    return false if !@identification.verified?
    identified_candidate.class_id == 693

  -> certified?
    verified?

  -> proof_kind
    :trusted_subgroup_classification_with_exact_arithmetic_replay

  -> theorem
    "irreducible-factor orbits and point-stabilizer subdegrees determine the Galois permutation subgroup up to conjugacy in the complete subgroup-class table"

  -> theorem_reference
    "Bruin-Poonen-Stoll Lemma 12.6 and finite permutation-group Galois theory"

  -> kernel_checked?
    false

  -> arithmetic_invariants_checked?
    true

  -> arithmetic_to_group_theorem_kernel_checked?
    false

  -> subgroup_table_completeness_checked?
    false

  -> identified_up_to_conjugacy?
    verified?

  -> global_theta_galois_subgroup_certified?
    verified?

  -> global_arithmetic_labeling_certified?
    false

  -> conclusion
    "theta Galois subgroup is class 693 of order 36, up to conjugacy"


+ PlaneQuarticTwoDescentSetup
  -> certify_theta_subdegrees
    if @bitangent_scheme_certificate == nil
      certify_bitangent_scheme
    @theta_subdegree_certificate = ShellWidthThetaSubdegreeCertificate.shell_width(
      @bitangent_scheme_certificate)
    @theta_subdegree_certificate

  -> theta_subdegree_certificate
    @theta_subdegree_certificate

  -> certify_theta_galois_subgroup
    if @theta_subdegree_certificate == nil
      certify_theta_subdegrees
    @theta_galois_certificate = ShellWidthThetaGaloisCertificate.new(
      @theta_subdegree_certificate)
    @theta_galois_certificate

  -> theta_galois_certificate
    @theta_galois_certificate
