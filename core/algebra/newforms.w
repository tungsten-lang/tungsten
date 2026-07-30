# Normalized rational weight-two newforms from the new Hecke quotient.
#
# A rational newform contributes two dimensions to sign-zero modular symbols
# (the plus and minus periods).  When the new quotient has dimension two,
# every prime Hecke operator must therefore act by one rational scalar.  Those
# scalars determine all q-expansion coefficients through the Euler relations.

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
  -> rational_newform(precision = 12)
    RationalWeightTwoNewform.new(
      @space.group, precision, @space.search_limit)


+ Gamma0
  -> rational_newform(precision = 12,
                      search_limit = 1_000_000)
    RationalWeightTwoNewform.new(
      self, precision, search_limit)
