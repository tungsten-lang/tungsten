# Certified real roots of univariate rational polynomials.
#
# Sturm sequences count roots with exact Rational arithmetic. Irreducible
# factors of degree greater than one are represented by AlgebraicRealRoot:
# a defining polynomial plus a rational open interval containing exactly one
# root. Refinement bisects and replays Sturm counts; approximation is derived
# from the certified interval and is never itself presented as a proof.

+ Polynomial
  -> validate_sturm_domain
    if @ring.arity != 1 || @ring.field.class_name != "RationalField"
      raise "Sturm operations require a univariate polynomial over ℚ"
    raise "the zero polynomial has no finite Sturm sequence" if zero?
    self

  # Repeated factors are removed, so every Sturm count below is a count of
  # distinct real roots.
  -> sturm_sequence
    validate_sturm_domain
    derivative_polynomial = derivative(0)
    return [self] if derivative_polynomial.zero?
    squarefree_part = self / gcd(derivative_polynomial)
    sequence = [squarefree_part, squarefree_part.derivative(0)]
    while !sequence[sequence.size - 1].zero?
      count = sequence.size
      remainder = sequence[count - 2].rem(sequence[count - 1])
      break if remainder.zero?
      sequence.push(remainder.negate)
    sequence

  -> sturm_variations_at_infinity(sequence, positive)
    variations = 0
    previous = 0
    sequence.each -> (polynomial)
      if !polynomial.zero?
        sign = polynomial.leading_coefficient.negative? ? -1 : 1
        sign = 0 - sign if !positive && polynomial.degree.odd?
        variations += 1 if previous != 0 && previous != sign
        previous = sign
    variations

  # Sign immediately to one side of a rational point. side=-1 is the left
  # limit, side=1 the right limit, and side=0 skips an exact zero.
  -> sturm_polynomial_sign_at(polynomial, point, side)
    current = polynomial
    multiplicity = 0
    value = current.at(point)
    return 0 if side == 0 && value.zero?
    while value.zero? && !current.zero?
      current = current.derivative(0)
      multiplicity += 1
      value = current.zero? ? Rational.new(0) : current.at(point)
    return 0 if value.zero?
    sign = value.negative? ? -1 : 1
    if side < 0 && multiplicity.odd?
      sign = 0 - sign
    sign

  -> sturm_variations_at(sequence, point, side = 0)
    unless side == -1 || side == 0 || side == 1
      raise "Sturm side must be -1, 0, or 1"
    rational = Rational.coerce(point)
    variations = 0
    previous = 0
    sequence.each -> (polynomial)
      sign = sturm_polynomial_sign_at(polynomial, rational, side)
      if sign != 0
        variations += 1 if previous != 0 && previous != sign
        previous = sign
    variations

  # Distinct roots strictly inside (lower, upper). One-sided endpoint signs
  # make the contract correct even when an endpoint itself is a root.
  -> sturm_root_count_with_sequence(sequence, lower, upper)
    left = Rational.coerce(lower)
    right = Rational.coerce(upper)
    raise "Sturm interval needs lower < upper" if left >= right
    left_variations = sturm_variations_at(sequence, left, 1)
    right_variations = sturm_variations_at(sequence, right, -1)
    left_variations - right_variations

  -> sturm_root_count(lower, upper)
    validate_sturm_domain
    sturm_root_count_with_sequence(
      sturm_sequence, lower, upper)

  -> sturm_root_count_closed(lower, upper)
    left = Rational.coerce(lower)
    right = Rational.coerce(upper)
    count = sturm_root_count(left, right)
    count += 1 if at(left).zero?
    count += 1 if at(right).zero?
    count

  -> sturm_root_index_before_with_sequence(sequence, point)
    rational = Rational.coerce(point)
    negative = sturm_variations_at_infinity(sequence, false)
    at_point = sturm_variations_at(sequence, rational, -1)
    negative - at_point

  -> sturm_root_index_before(point)
    validate_sturm_domain
    sturm_root_index_before_with_sequence(sturm_sequence, point)

  -> real_root_count
    validate_sturm_domain
    return 0 if degree <= 0
    sequence = sturm_sequence
    negative = sturm_variations_at_infinity(sequence, false)
    positive = sturm_variations_at_infinity(sequence, true)
    negative - positive

  # Isolate every root of an already squarefree rational polynomial directly,
  # without first factoring it over Q. Number-field defining polynomials and
  # finite etale quotient presentations are already certified squarefree; a
  # complete rational factorization is unrelated to their real embeddings and
  # can be exponentially more expensive than the Sturm replay needed here.
  -> squarefree_real_root_isolation(split_limit = 250_000)
    validate_sturm_domain
    if !squarefree?
      raise "direct real-root isolation needs a squarefree polynomial"
    total = real_root_count
    return RealRootIsolation.new(self, []) if total == 0
    sequence = sturm_sequence
    bound = cauchy_root_bound
    stack = [[0 - bound, bound, total]]
    roots = []
    splits = 0
    while stack.size > 0
      entry = stack.pop
      left = entry[0]
      right = entry[1]
      count = entry[2]
      if count == 1
        root_index = sturm_root_index_before_with_sequence(
          sequence, left)
        roots.push(AlgebraicRealRoot.new(
          self.monic, left, right, root_index))
      else
        splits += 1
        if splits > split_limit
          raise "direct real-root isolation split limit exceeded"
        middle = (left + right) / Rational.new(2)
        if at(middle).zero?
          roots.push(middle)
          left_count = sturm_root_count_with_sequence(
            sequence, left, middle)
          right_count = sturm_root_count_with_sequence(
            sequence, middle, right)
        else
          left_count = sturm_root_count_with_sequence(
            sequence, left, middle)
          right_count = count - left_count
        stack.push([middle, right, right_count]) if right_count > 0
        stack.push([left, middle, left_count]) if left_count > 0
    sorted = Polynomial.sort_real_root_values(roots)
    result = RealRootIsolation.new(self, sorted)
    if !result.certified?
      raise "direct real-root isolation completeness certificate failed"
    result

  -> squarefree_real_roots(split_limit = 250_000)
    squarefree_real_root_isolation(split_limit).roots

  # Strict Cauchy bound: every complex root z satisfies |z| < B.
  -> cauchy_root_bound
    validate_sturm_domain
    return Rational.new(1) if degree <= 0
    leading = leading_coefficient.abs
    maximum = Rational.new(0)
    i = 0
    while i < degree
      ratio = coeff(i).abs / leading
      maximum = ratio if ratio > maximum
      i += 1
    Rational.new(1 + maximum.ceil)

  -> unique_irreducible_factors(search_limit)
    out = []
    factor(search_limit).each -> (piece)
      if piece.degree > 0
        found = false
        i = 0
        while i < out.size
          found = true if out[i] == piece
          i += 1
        out.push(piece) if !found
    out

  # This receiver is expected to be an irreducible non-linear factor.
  -> isolate_irreducible_real_roots(split_limit = 100_000)
    validate_sturm_domain
    if degree <= 1
      raise "nonlinear real-root isolation needs degree at least two"
    if !squarefree?
      raise "isolating factor must be squarefree"
    total = real_root_count
    return [] if total == 0

    bound = cauchy_root_bound
    stack = [[0 - bound, bound, total]]
    roots = []
    splits = 0
    while stack.size > 0
      entry = stack.pop
      left = entry[0]
      right = entry[1]
      count = entry[2]
      if count == 1
        roots.push(AlgebraicRealRoot.new(
          self.monic, left, right, roots.size))
      else
        splits += 1
        if splits > split_limit
          raise "real-root isolation split limit exceeded"
        middle = (left + right) / Rational.new(2)
        if at(middle).zero?
          raise "nonlinear irreducible factor unexpectedly has a rational root"
        left_count = sturm_root_count(left, middle)
        right_count = count - left_count
        stack.push([middle, right, right_count]) if right_count > 0
        stack.push([left, middle, left_count]) if left_count > 0
    roots

  -> .real_root_compare(left, right)
    if left.class_name == "AlgebraicRealRoot"
      return left <=> right
    if right.class_name == "AlgebraicRealRoot"
      return 0 - (right <=> left)
    Rational.coerce(left) <=> Rational.coerce(right)

  -> .sort_real_root_values(values)
    out = []
    values.each -> (value)
      position = out.size
      while position > 0
        comparison = Polynomial.real_root_compare(
          value, out[position - 1])
        break if comparison >= 0
        position -= 1
      out.push(value)
      shift = out.size - 1
      while shift > position
        out[shift] = out[shift - 1]
        shift -= 1
      out[position] = value
    out

  -> real_root_isolation(search_limit = 250_000)
    validate_sturm_domain
    values = []
    unique_irreducible_factors(search_limit).each -> (piece)
      if piece.degree == 1
        root = (Rational.new(0) - piece.coeff(0)) / piece.coeff(1)
        values.push(root)
      else
        piece.isolate_irreducible_real_roots(search_limit).each -> (root)
          values.push(root)
    sorted = Polynomial.sort_real_root_values(values)
    result = RealRootIsolation.new(self, sorted)
    if !result.certified?
      raise "real-root isolation completeness certificate failed"
    result

  -> isolate_real_roots(search_limit = 250_000)
    real_root_isolation(search_limit).roots

  -> real_roots(search_limit = 250_000)
    isolate_real_roots(search_limit)


+ RootIsolationCertificate
  -> new(@polynomial, lower, upper, @root_index = nil)
    @lower = Rational.coerce(lower)
    @upper = Rational.coerce(upper)

  -> polynomial
    @polynomial

  -> lower_bound
    @lower

  -> upper_bound
    @upper

  -> interval
    [@lower, @upper]

  -> root_index
    @root_index

  -> verified?
    return false if @polynomial.class_name != "Polynomial"
    return false if @polynomial.ring.arity != 1
    return false if @polynomial.ring.field.class_name != "RationalField"
    return false if @polynomial.degree <= 0 || @polynomial.zero?
    return false if @lower >= @upper
    return false if @polynomial.at(@lower).zero?
    return false if @polynomial.at(@upper).zero?
    return false if !@polynomial.squarefree?
    sequence = @polynomial.sturm_sequence
    count = @polynomial.sturm_root_count_with_sequence(
      sequence, @lower, @upper)
    return false if count != 1
    if @root_index != nil
      return false if @root_index < 0
      index = @polynomial.sturm_root_index_before_with_sequence(
        sequence, @lower)
      return false if index != @root_index
    true

  -> root_count
    @polynomial.sturm_root_count(@lower, @upper)

  -> certified?
    verified?

  -> to_s
    "RootIsolationCertificate(" + @lower.to_s + ", " + @upper.to_s + ")"

  -> inspect
    to_s


+ AlgebraicRealRoot
  is Comparable

  -> integer_value?(value)
    name = value.class_name
    name == "Integer" || name == "Int" || name == "BigInt"

  -> new(@defining_polynomial, lower, upper, @root_index = 0)
    @lower = Rational.coerce(lower)
    @upper = Rational.coerce(upper)
    @sturm_sequence = @defining_polynomial.sturm_sequence
    if !RootIsolationCertificate.new(
         @defining_polynomial, @lower, @upper, @root_index).verified?
      raise "invalid algebraic-real isolating interval"
    if @root_index < 0
      raise "algebraic-real root index must be nonnegative"

  -> defining_polynomial
    @defining_polynomial

  -> minimal_polynomial(search_limit = 250_000)
    selected = nil
    @defining_polynomial.unique_irreducible_factors(search_limit).each -> (piece)
      count = piece.sturm_root_count(@lower, @upper)
      if count == 1
        if selected != nil
          raise "algebraic-real interval selected multiple irreducible factors"
        selected = piece.monic
    if selected == nil
      raise "algebraic-real interval selected no irreducible factor"
    selected

  -> root_index
    @root_index

  -> lower_bound
    @lower

  -> upper_bound
    @upper

  -> interval
    [@lower, @upper]

  -> width
    @upper - @lower

  -> certificate
    RootIsolationCertificate.new(
      @defining_polynomial, @lower, @upper, @root_index)

  -> certified?
    certificate.verified?

  -> refine!
    middle = (@lower + @upper) / Rational.new(2)
    if @defining_polynomial.at(middle).zero?
      raise "algebraic-real defining factor has a rational midpoint root"
    left_count = @defining_polynomial.sturm_root_count_with_sequence(
      @sturm_sequence, @lower, middle)
    if left_count == 1
      @upper = middle
    else
      right_count = @defining_polynomial.sturm_root_count_with_sequence(
        @sturm_sequence, middle, @upper)
      if right_count != 1
        raise "algebraic-real refinement lost its unique root"
      @lower = middle
    self

  -> refine!(steps)
    if !integer_value?(steps) || steps < 0
      raise "root refinement steps must be a nonnegative integer"
    i = 0
    while i < steps
      self.refine!
      i += 1
    self

  -> refined(steps = 1)
    copy = AlgebraicRealRoot.new(
      @defining_polynomial, @lower, @upper, @root_index)
    copy.refine!(steps)

  -> approximation(digits = 16)
    if !integer_value?(digits) || digits < 0
      raise "root approximation digits must be a nonnegative integer"
    scale = 1 ## big
    i = 0
    while i < digits
      scale *= 10
      i += 1
    target = Rational.new(1) / scale
    copy = self.refined(0)
    steps = 0
    while copy.width > target
      if steps > digits * 8 + 256
        raise "root approximation refinement limit exceeded"
      copy.refine!
      steps += 1
    (copy.lower_bound + copy.upper_bound) / Rational.new(2)

  -> approximate(digits = 15)
    self.approximation(digits).to_f

  -> to_f
    self.approximate(15)

  -> compare_rational(value, refinement_limit = 10_000)
    rational = Rational.coerce(value)
    steps = 0
    while true
      return -1 if @upper <= rational
      return 1 if @lower >= rational
      if steps >= refinement_limit
        raise "algebraic-real comparison refinement limit exceeded"
      refine!
      steps += 1

  -> <=>(other)
    if other.class_name != "AlgebraicRealRoot"
      return compare_rational(other)
    left_polynomial = canonical_defining_polynomial
    right_polynomial = other.canonical_defining_polynomial
    if left_polynomial == right_polynomial
      return @root_index <=> other.root_index

    # Distinct presentations may still select a root of the same rational
    # factor. Detect that algebraically before interval refinement: otherwise
    # equal roots would overlap forever and eventually hit the separation
    # limit.
    common = left_polynomial.gcd(right_polynomial)
    if common.degree > 0
      left_count = common.sturm_root_count(@lower, @upper)
      right_count = common.sturm_root_count(
        other.lower_bound, other.upper_bound)
      if left_count == 1 && right_count == 1
        left_index = common.sturm_root_index_before(@lower)
        right_index = common.sturm_root_index_before(other.lower_bound)
        return left_index <=> right_index

    steps = 0
    while true
      return -1 if @upper <= other.lower_bound
      return 1 if @lower >= other.upper_bound
      if steps >= 10_000
        raise "algebraic-real comparison could not separate the roots"
      if width >= other.width
        refine!
      else
        other.refine!
      steps += 1

  -> canonical_defining_polynomial
    ring = PolynomialRing.new([:__root], RationalField.new)
    @defining_polynomial.rename_into(ring).monic

  -> eql?(other)
    return false if other.class_name != "AlgebraicRealRoot"
    (self <=> other) == 0

  -> ==/1
    other = @1
    return (self <=> other) == 0 if other.class_name == "AlgebraicRealRoot"
    name = other.class_name
    rational = name == "Rational" || name == "Integer" || name == "Int" || name == "BigInt"
    return (self <=> other) == 0 if rational
    false

  -> <(other)
    (self <=> other) < 0

  -> <=(other)
    (self <=> other) <= 0

  -> >(other)
    (self <=> other) > 0

  -> >=(other)
    (self <=> other) >= 0

  -> zero?
    (self <=> Rational.new(0)) == 0

  -> one?
    (self <=> Rational.new(1)) == 0

  -> sign
    self <=> Rational.new(0)

  -> negative?
    self.sign < 0

  -> positive?
    self.sign > 0

  -> to_s
    "RootOf(" + @defining_polynomial.to_s + ", " + @root_index.to_s + ")"

  -> inspect
    to_s + " in (" + @lower.to_s + ", " + @upper.to_s + ")"


+ RealRootIsolation
  -> new(@polynomial, roots)
    @roots = []
    roots.each -> (root)
      @roots.push(root)

  -> polynomial
    @polynomial

  -> roots
    out = []
    @roots.each -> (root)
      out.push(root)
    out

  -> intervals
    out = []
    @roots.each -> (root)
      if root.class_name == "AlgebraicRealRoot"
        out.push(root.interval)
      else
        rational = Rational.coerce(root)
        out.push([rational, rational])
    out

  -> verified?
    return false if @polynomial.class_name != "Polynomial"
    return false if @polynomial.ring.arity != 1
    return false if @polynomial.ring.field.class_name != "RationalField"
    return false if @polynomial.zero?
    return false if @polynomial.real_root_count != @roots.size

    i = 0
    while i < @roots.size
      root = @roots[i]
      if root.class_name == "AlgebraicRealRoot"
        return false if !root.certified?
        divisor = root.defining_polynomial
        return false if !@polynomial.rem(divisor).zero?
      else
        return false if !@polynomial.at(root).zero?
      if i > 0
        comparison = Polynomial.real_root_compare(
          @roots[i - 1], root)
        return false if comparison >= 0
      i += 1
    true

  -> certified?
    verified?

  -> to_s
    "RealRootIsolation(" + @roots.size.to_s + " roots)"

  -> inspect
    to_s
