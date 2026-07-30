# Exact arithmetic invariants for Gamma_0(N), modular curves, and the first
# modular-form space layer.
#
# Integer calculations are replayed directly. Their interpretation as
# subgroup invariants, cusp-form dimensions, and coefficient sufficiency uses
# named classical theorem imports (the Gamma_0 formulas, Riemann--Roch, and
# Sturm's theorem); those proofs are not yet formalized in a Tungsten kernel.

+ ModularFormsArithmetic
  -> .integer?(value)
    name = value.class_name
    name == "Integer" || name == "Int" || name == "BigInt"

  -> .require_level(level)
    if !ModularFormsArithmetic.integer?(level) || level < 1
      raise "Gamma0 level must be a positive integer"
    level

  -> .require_weight(weight)
    if !ModularFormsArithmetic.integer?(weight) || weight < 0
      raise "modular-form weight must be a nonnegative integer"
    weight

  -> .divisors_from_factorization(factorization)
    divisors = [1]
    factorization.each -> (factor)
      existing = []
      divisors.each -> (divisor)
        existing.push(divisor)
      power = 1
      exponent = 1
      while exponent <= factor.exponent
        power *= factor.prime
        existing.each -> (divisor)
          divisors.push(divisor*power)
        exponent += 1
    divisors.sort

  -> .totient(value)
    raise "totient needs a positive integer" if value < 1
    result = value
    value.factor.each -> (factor)
      result = (result / factor.prime) * (factor.prime - 1)
    result

  -> .gamma0_index(level, factorization = nil)
    factors = factorization == nil ? level.factor : factorization
    result = level
    factors.each -> (factor)
      result = (result / factor.prime) * (factor.prime + 1)
    result

  -> .gamma0_cusp_count(level, factorization = nil)
    factors = factorization == nil ? level.factor : factorization
    total = 0
    ModularFormsArithmetic.divisors_from_factorization(factors).each -> (d)
      total += ModularFormsArithmetic.totient(d.gcd(level / d))
    total

  -> .minus_four_symbol_at_prime(prime)
    return 0 if prime == 2
    prime % 4 == 1 ? 1 : -1

  -> .minus_three_symbol_at_prime(prime)
    return -1 if prime == 2
    return 0 if prime == 3
    prime % 3 == 1 ? 1 : -1

  -> .gamma0_order_two_points(level, factorization = nil)
    return 0 if level % 4 == 0
    factors = factorization == nil ? level.factor : factorization
    result = 1
    factors.each -> (factor)
      result *= 1 + ModularFormsArithmetic.minus_four_symbol_at_prime(
        factor.prime)
    result

  -> .gamma0_order_three_points(level, factorization = nil)
    return 0 if level % 9 == 0
    factors = factorization == nil ? level.factor : factorization
    result = 1
    factors.each -> (factor)
      result *= 1 + ModularFormsArithmetic.minus_three_symbol_at_prime(
        factor.prime)
    result

  -> .gamma0_genus(index, cusps, order_two, order_three)
    value = Rational.new(1)
    value += Rational.new(index, 12)
    value -= Rational.new(order_two, 4)
    value -= Rational.new(order_three, 3)
    value -= Rational.new(cusps, 2)
    if value.denominator != 1 || value.numerator < 0
      raise "Gamma0 genus formula did not produce a nonnegative integer"
    value.numerator

  -> .cusp_dimension(group, weight)
    return 0 if weight <= 0 || weight.odd?
    return group.genus if weight == 2
    ((weight - 1)*(group.genus - 1) +
      (weight / 4)*group.order_two_elliptic_points +
      (weight / 3)*group.order_three_elliptic_points +
      (weight / 2 - 1)*group.number_of_cusps)

  -> .eisenstein_dimension(group, weight)
    return 1 if weight == 0
    return 0 if weight.odd?
    return group.number_of_cusps - 1 if weight == 2
    group.number_of_cusps

  -> .modular_dimension(group, weight)
    (ModularFormsArithmetic.cusp_dimension(group, weight) +
      ModularFormsArithmetic.eisenstein_dimension(group, weight))

  -> .sturm_bound(group, weight)
    if weight < 2
      raise "Sturm bound needs weight at least 2"
    numerator = group.index*weight
    (numerator + 11) / 12


+ Gamma0InvariantsCertificate
  -> new(@group)
    @verified_cache = nil

  -> group
    @group

  -> theorem
    "classical index, cusp, elliptic-point, and genus formulas for Gamma_0(N)"

  -> theorem_reference
    "Diamond-Shurman, A First Course in Modular Forms, sections 3.1 and 3.5"

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
    return false if @group.class_name != "Gamma0"
    level = @group.level
    return false if !ModularFormsArithmetic.integer?(level) || level < 1
    factorization = @group.factorization
    return false if factorization.class_name != "IntegerFactorization"
    return false if factorization.value != level
    index = ModularFormsArithmetic.gamma0_index(level, factorization)
    cusps = ModularFormsArithmetic.gamma0_cusp_count(level, factorization)
    order_two = ModularFormsArithmetic.gamma0_order_two_points(
      level, factorization)
    order_three = ModularFormsArithmetic.gamma0_order_three_points(
      level, factorization)
    genus = ModularFormsArithmetic.gamma0_genus(
      index, cusps, order_two, order_three)
    return false if @group.index != index
    return false if @group.number_of_cusps != cusps
    return false if @group.order_two_elliptic_points != order_two
    return false if @group.order_three_elliptic_points != order_three
    @group.genus == genus

  -> certified?
    verified?

  -> to_s
    "Gamma0InvariantsCertificate(N=" + @group.level.to_s + ")"

  -> inspect
    to_s


+ Gamma0
  -> new(@level)
    ModularFormsArithmetic.require_level(@level)
    @factorization = @level.factor
    @index = ModularFormsArithmetic.gamma0_index(
      @level, @factorization)
    @number_of_cusps = ModularFormsArithmetic.gamma0_cusp_count(
      @level, @factorization)
    @order_two_elliptic_points = (
      ModularFormsArithmetic.gamma0_order_two_points(
        @level, @factorization))
    @order_three_elliptic_points = (
      ModularFormsArithmetic.gamma0_order_three_points(
        @level, @factorization))
    @genus = ModularFormsArithmetic.gamma0_genus(
      @index, @number_of_cusps,
      @order_two_elliptic_points, @order_three_elliptic_points)
    @certificate = Gamma0InvariantsCertificate.new(self)
    raise "Gamma0 invariant certificate failed" if !@certificate.verified?

  -> level
    @level

  -> factorization
    @factorization

  -> index
    @index

  -> number_of_cusps
    @number_of_cusps

  -> order_two_elliptic_points
    @order_two_elliptic_points

  -> order_three_elliptic_points
    @order_three_elliptic_points

  -> genus
    @genus

  -> modular_curve
    ModularCurveX0.new(self)

  -> cusp_forms(weight = 2)
    CuspForms.new(self, weight)

  -> modular_forms(weight = 2)
    ModularForms.new(self, weight)

  -> sturm(weight = 2)
    SturmBound.new(self, weight)

  -> sturm_bound(weight = 2)
    self.sturm(weight).bound

  -> certificate
    @certificate

  -> certified?
    @certificate.verified?

  -> ==(other)
    other != nil && other.class_name == "Gamma0" && other.level == @level

  -> eql?(other)
    self == other

  -> to_s
    "Gamma0(" + @level.to_s + ")"

  -> inspect
    to_s


+ ModularCurveX0
  -> new(group)
    @group = group.class_name == "Gamma0" ? group : Gamma0.new(group)

  -> group
    @group

  -> level
    @group.level

  -> genus
    @group.genus

  -> connected?
    true

  -> dimension
    1

  -> certificate
    @group.certificate

  -> certified?
    @group.certified?

  -> to_s
    "X0(" + level.to_s + ")"

  -> inspect
    to_s


+ ModularFormSpaceDimensionCertificate
  -> new(@space)
    @verified_cache = nil

  -> space
    @space

  -> theorem
    "Riemann-Roch dimension formula for even-weight modular forms on Gamma_0(N)"

  -> theorem_reference
    "Diamond-Shurman, A First Course in Modular Forms, sections 3.5 and 3.6"

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
    valid_class = @space.class_name == "CuspForms"
    valid_class = true if @space.class_name == "ModularForms"
    return false if !valid_class
    return false if !@space.group.certificate.verified?
    weight = @space.weight
    return false if !ModularFormsArithmetic.integer?(weight) || weight < 0
    expected = 0
    if @space.class_name == "CuspForms"
      expected = ModularFormsArithmetic.cusp_dimension(
        @space.group, weight)
    else
      expected = ModularFormsArithmetic.modular_dimension(
        @space.group, weight)
    @space.dimension == expected

  -> certified?
    verified?

  -> to_s
    ("ModularFormSpaceDimensionCertificate(" +
      @space.class_name + ", N=" + @space.level.to_s +
      ", k=" + @space.weight.to_s + ")")

  -> inspect
    to_s


+ CuspForms
  -> new(group, @weight = 2)
    @group = group.class_name == "Gamma0" ? group : Gamma0.new(group)
    ModularFormsArithmetic.require_weight(@weight)
    @dimension = ModularFormsArithmetic.cusp_dimension(
      @group, @weight)
    @dimension_certificate = ModularFormSpaceDimensionCertificate.new(self)
    if !@dimension_certificate.verified?
      raise "cusp-form dimension certificate failed"

  -> group
    @group

  -> level
    @group.level

  -> weight
    @weight

  -> dimension
    @dimension

  -> zero?
    @dimension == 0

  -> sturm
    SturmBound.new(@group, @weight)

  -> sturm_bound
    self.sturm.bound

  -> q_expansion_precision
    self.sturm.precision

  -> dimension_certificate
    @dimension_certificate

  -> certified?
    @dimension_certificate.verified?

  -> to_s
    ("CuspForms(Gamma0(" + level.to_s +
      "), weight=" + @weight.to_s +
      ", dimension=" + @dimension.to_s + ")")

  -> inspect
    to_s


+ ModularForms
  -> new(group, @weight = 2)
    @group = group.class_name == "Gamma0" ? group : Gamma0.new(group)
    ModularFormsArithmetic.require_weight(@weight)
    @dimension = ModularFormsArithmetic.modular_dimension(
      @group, @weight)
    @dimension_certificate = ModularFormSpaceDimensionCertificate.new(self)
    if !@dimension_certificate.verified?
      raise "modular-form dimension certificate failed"

  -> group
    @group

  -> level
    @group.level

  -> weight
    @weight

  -> dimension
    @dimension

  -> cusp_dimension
    ModularFormsArithmetic.cusp_dimension(@group, @weight)

  -> eisenstein_dimension
    ModularFormsArithmetic.eisenstein_dimension(@group, @weight)

  -> cusp_forms
    CuspForms.new(@group, @weight)

  -> sturm
    SturmBound.new(@group, @weight)

  -> sturm_bound
    self.sturm.bound

  -> q_expansion_precision
    self.sturm.precision

  -> dimension_certificate
    @dimension_certificate

  -> certified?
    @dimension_certificate.verified?

  -> to_s
    ("ModularForms(Gamma0(" + level.to_s +
      "), weight=" + @weight.to_s +
      ", dimension=" + @dimension.to_s + ")")

  -> inspect
    to_s


+ SturmBoundCertificate
  -> new(@group, @weight, @bound)
    @verified_cache = nil

  -> group
    @group

  -> weight
    @weight

  -> bound
    @bound

  -> theorem
    "Sturm coefficient bound for modular forms on Gamma_0(N)"

  -> theorem_reference
    "Sturm, On the congruence of modular forms, LNM 1240 (1987)"

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
    return false if @group.class_name != "Gamma0"
    return false if !@group.certificate.verified?
    return false if !ModularFormsArithmetic.integer?(@weight)
    return false if @weight < 2
    expected = ModularFormsArithmetic.sturm_bound(@group, @weight)
    @bound == expected

  -> certified?
    verified?

  -> to_s
    ("SturmBoundCertificate(N=" + @group.level.to_s +
      ", k=" + @weight.to_s +
      ", B=" + @bound.to_s + ")")

  -> inspect
    to_s


+ SturmBound
  -> new(group, @weight = 2)
    @group = group.class_name == "Gamma0" ? group : Gamma0.new(group)
    ModularFormsArithmetic.require_weight(@weight)
    @bound = ModularFormsArithmetic.sturm_bound(@group, @weight)
    @certificate = SturmBoundCertificate.new(
      @group, @weight, @bound)
    raise "Sturm-bound certificate failed" if !@certificate.verified?

  -> group
    @group

  -> level
    @group.level

  -> weight
    @weight

  -> bound
    @bound

  # Coefficients a_0 through a_B occupy B+1 array slots.
  -> precision
    @bound + 1

  -> certificate
    @certificate

  -> certified?
    @certificate.verified?

  -> to_i
    @bound

  -> to_s
    ("SturmBound(N=" + level.to_s +
      ", k=" + @weight.to_s +
      ", B=" + @bound.to_s + ")")

  -> inspect
    to_s
