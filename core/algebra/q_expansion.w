# Exact truncated q-expansions and classical level-one modular forms.
#
# A QExpansion never treats coefficients beyond its precision as zero: reads
# outside the certified truncation raise. E4, E6, and Delta carry certificates
# that replay their divisor-sum/product formulas and the
# E4^3 - E6^2 = 1728*Delta identity.

+ QExpansion
  -> new(coefficients)
    if coefficients.class_name != "Array" || coefficients.size < 1
      raise "q-expansion coefficients must be a nonempty Array"
    @coefficients = []
    coefficients.each -> (coefficient)
      @coefficients.push(Rational.coerce(coefficient))

  -> .zero(precision)
    if !ModularFormsArithmetic.integer?(precision) || precision < 1
      raise "q-expansion precision must be positive"
    coefficients = []
    i = 0
    while i < precision
      coefficients.push(Rational.new(0))
      i += 1
    QExpansion.new(coefficients)

  -> .one(precision)
    expansion = QExpansion.zero(precision)
    coefficients = expansion.coefficients
    coefficients[0] = Rational.new(1)
    QExpansion.new(coefficients)

  -> .q(precision)
    if precision < 2
      raise "q needs precision at least 2"
    coefficients = QExpansion.zero(precision).coefficients
    coefficients[1] = Rational.new(1)
    QExpansion.new(coefficients)

  -> precision
    @coefficients.size

  -> coefficients
    out = []
    @coefficients.each -> (coefficient)
      out.push(coefficient)
    out

  -> coefficient(index)
    if !ModularFormsArithmetic.integer?(index) || index < 0
      raise "q-expansion coefficient index must be nonnegative"
    if index >= precision
      raise "q-expansion coefficient is beyond known precision"
    @coefficients[index]

  -> [](index)
    coefficient(index)

  -> at(index)
    coefficient(index)

  -> valuation
    i = 0
    while i < precision
      return i if !@coefficients[i].zero?
      i += 1
    nil

  -> zero?
    valuation == nil

  -> constant?
    i = 1
    while i < precision
      return false if !@coefficients[i].zero?
      i += 1
    true

  -> truncate(new_precision)
    valid_precision = false
    if ModularFormsArithmetic.integer?(new_precision)
      valid_precision = new_precision >= 1
    if !valid_precision
      raise "q-expansion precision must be positive"
    if new_precision > precision
      raise "cannot infer unknown q-expansion coefficients"
    out = []
    i = 0
    while i < new_precision
      out.push(@coefficients[i])
      i += 1
    QExpansion.new(out)

  -> +(other)
    if other.class_name != "QExpansion"
      out = coefficients
      out[0] = out[0] + Rational.coerce(other)
      return QExpansion.new(out)
    known = precision < other.precision ? precision : other.precision
    out = []
    i = 0
    while i < known
      out.push(@coefficients[i] + other.coefficient(i))
      i += 1
    QExpansion.new(out)

  -> negate
    out = []
    @coefficients.each -> (coefficient)
      out.push(0 - coefficient)
    QExpansion.new(out)

  -> -@
    negate

  -> -(other)
    return self + (0 - Rational.coerce(other)) if other.class_name != "QExpansion"
    self + other.negate

  -> scale(scalar)
    factor = Rational.coerce(scalar)
    out = []
    @coefficients.each -> (coefficient)
      out.push(coefficient*factor)
    QExpansion.new(out)

  -> *(other)
    return scale(other) if other.class_name != "QExpansion"
    known = precision < other.precision ? precision : other.precision
    out = QExpansion.zero(known).coefficients
    i = 0
    while i < known
      j = 0
      while i + j < known
        out[i + j] += @coefficients[i]*other.coefficient(j)
        j += 1
      i += 1
    QExpansion.new(out)

  -> **(exponent)
    if !ModularFormsArithmetic.integer?(exponent) || exponent < 0
      raise "q-expansion power must be a nonnegative integer"
    result = QExpansion.one(precision)
    factor = self
    remaining = exponent
    while remaining > 0
      result = result*factor if remaining.odd?
      remaining /= 2
      factor = factor*factor if remaining > 0
    result

  -> agrees_through?(other, bound)
    return false if other.class_name != "QExpansion"
    if !ModularFormsArithmetic.integer?(bound) || bound < 0
      return false
    return false if bound >= precision || bound >= other.precision
    i = 0
    while i <= bound
      return false if @coefficients[i] != other.coefficient(i)
      i += 1
    true

  -> ==(other)
    return false if other == nil || other.class_name != "QExpansion"
    return false if precision != other.precision
    agrees_through?(other, precision - 1)

  -> eql?(other)
    self == other

  -> to_s
    terms = []
    i = 0
    while i < precision
      coefficient = @coefficients[i]
      if !coefficient.zero?
        if i == 0
          terms.push(coefficient.to_s)
        elsif i == 1
          terms.push(coefficient.to_s + "*q")
        else
          terms.push(coefficient.to_s + "*q^" + i.to_s)
      i += 1
    body = terms.empty? ? "0" : terms.join(" + ")
    body + " + O(q^" + precision.to_s + ")"

  -> inspect
    to_s


+ ClassicalModularForms
  -> .divisor_power_sum(value, power)
    raise "divisor power sum needs a positive integer" if value < 1
    result = 1
    value.factor.each -> (factor)
      numerator = factor.prime**((factor.exponent + 1)*power) - 1
      denominator = factor.prime**power - 1
      result *= numerator / denominator
    result

  -> .binomial(n, k)
    return 0 if k < 0 || k > n
    kk = k > n - k ? n - k : k
    result = 1
    i = 1
    while i <= kk
      result = (result*(n - kk + i)) / i
      i += 1
    result

  -> .eisenstein_coefficients(weight, precision)
    if precision < 1
      raise "classical modular form precision must be positive"
    coefficients = [1]
    n = 1
    while n < precision
      if weight == 4
        coefficients.push(
          240*ClassicalModularForms.divisor_power_sum(n, 3))
      elsif weight == 6
        coefficients.push(
          (0 - 504)*ClassicalModularForms.divisor_power_sum(n, 5))
      else
        raise "implemented Eisenstein q-expansions are E4 and E6"
      n += 1
    coefficients

  -> .delta_product_coefficients(precision)
    if precision < 2
      raise "Delta q-expansion needs precision at least 2"
    result = QExpansion.q(precision)
    n = 1
    while n < precision
      coefficients = QExpansion.zero(precision).coefficients
      j = 0
      while j <= 24 && j*n < precision
        coefficient = ClassicalModularForms.binomial(24, j)
        coefficient = 0 - coefficient if j.odd?
        coefficients[j*n] = Rational.new(coefficient)
        j += 1
      result = result*QExpansion.new(coefficients)
      n += 1
    result.coefficients

  -> .expected_expansion(kind, precision)
    if kind == :E4
      return QExpansion.new(
        ClassicalModularForms.eisenstein_coefficients(4, precision))
    if kind == :E6
      return QExpansion.new(
        ClassicalModularForms.eisenstein_coefficients(6, precision))
    if kind == :Delta
      return QExpansion.new(
        ClassicalModularForms.delta_product_coefficients(precision))
    raise "unknown classical modular form"

  -> .e4(precision = 12)
    ClassicalModularForm.new(:E4, precision)

  -> .e6(precision = 12)
    ClassicalModularForm.new(:E6, precision)

  -> .delta(precision = 12)
    ClassicalModularForm.new(:Delta, precision)


+ ClassicalModularFormCertificate
  -> new(@kind, @group, @weight, @q_expansion)
    @verified_cache = nil

  -> kind
    @kind

  -> group
    @group

  -> weight
    @weight

  -> q_expansion
    @q_expansion

  -> theorem
    if @kind == :Delta
      return "Delta(q)=q product_(n>=1)(1-q^n)^24 and E4^3-E6^2=1728 Delta"
    "normalized Eisenstein-series divisor-sum q-expansion"

  -> theorem_reference
    "classical level-one modular-form q-expansion identities"

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
    return false if @group.level != 1 || !@group.certificate.verified?
    return false if @q_expansion.class_name != "QExpansion"
    expected_weight = nil
    expected_weight = 4 if @kind == :E4
    expected_weight = 6 if @kind == :E6
    expected_weight = 12 if @kind == :Delta
    return false if expected_weight == nil || @weight != expected_weight
    precision = @q_expansion.precision
    minimum = @kind == :Delta ? 2 : 1
    return false if precision < minimum
    expected = ClassicalModularForms.expected_expansion(
      @kind, precision)
    return false if @q_expansion != expected
    if @kind == :Delta
      e4 = ClassicalModularForms.expected_expansion(:E4, precision)
      e6 = ClassicalModularForms.expected_expansion(:E6, precision)
      identity = (e4**3 - e6**2).scale(Rational.new(1, 1728))
      return false if identity != @q_expansion
    true

  -> certified?
    verified?

  -> to_s
    ("ClassicalModularFormCertificate(" + @kind.to_s +
      ", precision=" + @q_expansion.precision.to_s + ")")

  -> inspect
    to_s


+ ClassicalModularForm
  -> new(@kind, @precision = 12)
    if !ModularFormsArithmetic.integer?(@precision) || @precision < 1
      raise "classical modular form precision must be positive"
    if @kind == :Delta && @precision < 2
      raise "Delta q-expansion needs precision at least 2"
    @group = Gamma0.new(1)
    @weight = nil
    @weight = 4 if @kind == :E4
    @weight = 6 if @kind == :E6
    @weight = 12 if @kind == :Delta
    raise "unknown classical modular form" if @weight == nil
    @q_expansion = ClassicalModularForms.expected_expansion(
      @kind, @precision)
    @certificate = ClassicalModularFormCertificate.new(
      @kind, @group, @weight, @q_expansion)
    if !@certificate.verified?
      raise "classical modular-form certificate failed"

  -> kind
    @kind

  -> name
    @kind.to_s

  -> group
    @group

  -> level
    1

  -> weight
    @weight

  -> precision
    @precision

  -> q_expansion
    @q_expansion

  -> coefficient(index)
    @q_expansion.coefficient(index)

  -> [](index)
    coefficient(index)

  -> certificate
    @certificate

  -> certified?
    @certificate.verified?

  -> to_s
    @kind.to_s + " = " + @q_expansion.to_s

  -> inspect
    to_s
