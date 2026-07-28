# Exact sparse multivariate polynomials over an explicit coefficient field.
#
# PolynomialRing owns both the field and the monomial order.  Polynomial never
# silently substitutes ℚ: every coefficient enters through ring.field.coerce.

+ MonomialOrder
  -> new(@name)
    @split = nil
    @left = nil
    @right = nil

  -> new(@name, @split, @left, @right)

  -> name
    @name

  -> split
    @split

  -> left
    @left

  -> right
    @right

  -> .named(value)
    return MonomialOrder.new("grevlex") if value == nil
    return value if value.class_name == "MonomialOrder"
    name = value.to_s
    return MonomialOrder.new("lex") if name == "lex"
    return MonomialOrder.new("grlex") if name == "grlex"
    return MonomialOrder.new("grevlex") if name == "grevlex"
    raise "unknown monomial order: " + name

  -> .lex
    MonomialOrder.new("lex")

  -> .grlex
    MonomialOrder.new("grlex")

  -> .grevlex
    MonomialOrder.new("grevlex")

  # A block/product order compares the first `split` variables with `left`,
  # then the remaining variables with `right`.
  -> .product(split)
    MonomialOrder.product(split, :grevlex, :grevlex)

  -> .product(split, left)
    MonomialOrder.product(split, left, :grevlex)

  -> .product(split, left, right)
    raise "product-order split must be nonnegative" if split < 0
    MonomialOrder.new(
      "product", split, MonomialOrder.named(left), MonomialOrder.named(right))

  -> total_degree(values, first, last)
    result = 0
    i = first
    while i < last
      result += values[i]
      i += 1
    result

  -> lex_compare(a, b, first, last)
    i = first
    while i < last
      return 1 if a[i] > b[i]
      return -1 if a[i] < b[i]
      i += 1
    0

  -> compare_range(a, b, first, last)
    if @name == "lex"
      return lex_compare(a, b, first, last)
    if @name == "grlex"
      ad = total_degree(a, first, last)
      bd = total_degree(b, first, last)
      return 1 if ad > bd
      return -1 if ad < bd
      return lex_compare(a, b, first, last)
    if @name == "grevlex"
      ad = total_degree(a, first, last)
      bd = total_degree(b, first, last)
      return 1 if ad > bd
      return -1 if ad < bd
      i = last - 1
      while i >= first
        # In graded reverse lexicographic order the monomial with the smaller
        # exponent in the last differing variable is the larger monomial.
        return 1 if a[i] < b[i]
        return -1 if a[i] > b[i]
        i -= 1
      # An explicit return: a bare trailing 0 would fall out of the if-arm
      # into the invalid-order raise below whenever the ranges tie.
      return 0
    raise "invalid component monomial order: " + @name

  -> compare(a, b)
    raise "cannot compare monomials of different arity" if a.size != b.size
    if @name == "product"
      raise "product-order split exceeds monomial arity" if @split > a.size
      result = @left.compare_range(a, b, 0, @split)
      return result if result != 0
      return @right.compare_range(a, b, @split, a.size)
    compare_range(a, b, 0, a.size)

  -> ==/1
    other = @1
    return false if other.class_name != "MonomialOrder"
    return false if @name != other.name || @split != other.split
    return false if @left != other.left || @right != other.right
    true

  -> to_s
    if @name == "product"
      return "product(" + @split.to_s + ", " + @left.to_s + ", " + @right.to_s + ")"
    @name

  -> inspect
    to_s


+ PolynomialRing
  -> new(names)
    initialize_polynomial_ring(names, RationalField.new, :grevlex)

  -> new(names, field)
    initialize_polynomial_ring(names, field, :grevlex)

  -> new(names, field, order)
    initialize_polynomial_ring(names, field, order)

  -> initialize_polynomial_ring(names, field, order)
    raise "polynomial generator names must be an Array" if names.class_name != "Array"
    raise "a polynomial ring needs at least one generator" if names.size == 0
    @names = names
    @field = Field.require_supported(field)
    @order = MonomialOrder.named(order)
    self

  ro :names, :field, :order

  -> arity
    @names.size

  -> zero_exponents
    out = []
    i = 0
    while i < arity
      out.push(0)
      i += 1
    out

  -> zero
    Polynomial.new(self, [])

  -> one
    constant(@field.one)

  -> constant(value)
    coefficient = @field.coerce(value)
    return zero if coefficient.zero?
    Polynomial.new(self, [[coefficient, zero_exponents]])

  -> monomial(coefficient, exponents)
    Polynomial.new(self, [[@field.coerce(coefficient), exponents]])

  -> generator(index)
    raise "generator index out of range" if index < 0 || index >= arity
    exponents = zero_exponents
    exponents[index] = 1
    Polynomial.new(self, [[@field.one, exponents]])

  -> generators
    out = []
    i = 0
    while i < arity
      out.push(self.generator(i))
      i += 1
    out

  -> index_of(name)
    sought = name.to_s
    i = 0
    while i < @names.size
      return i if @names[i].to_s == sought
      i += 1
    nil

  -> monomial_compare(left, right)
    @order.compare(left, right)

  -> coerce(value)
    if value.class_name == "Polynomial"
      raise "polynomials belong to different rings" if value.ring != self
      return value
    @field.coerce(value)
    constant(value)

  -> ==/1
    other = @1
    return false if other.class_name != "PolynomialRing"
    return false if @field != other.field || @order != other.order
    return false if @names.size != other.names.size
    i = 0
    while i < @names.size
      return false if @names[i].to_s != other.names[i].to_s
      i += 1
    true

  -> to_s
    parts = []
    @names.each -> parts.push(item.to_s)
    @field.to_s + "\[" + parts.join(", ") + "; " + @order.to_s + "\]"

  -> inspect
    to_s


+ Polynomial
  -> new(@ring, terms)
    raise "polynomial requires a PolynomialRing" if @ring.class_name != "PolynomialRing"
    @terms = normalize_terms(terms)

  ro :ring, :terms

  -> same_monomial?(left, right)
    return false if left.size != right.size
    i = 0
    while i < left.size
      return false if left[i] != right[i]
      i += 1
    true

  -> copy_exponents(source)
    out = []
    i = 0
    while i < source.size
      out.push(source[i])
      i += 1
    out

  -> normalize_terms(input)
    out = []
    i = 0
    while i < input.size
      coefficient = @ring.field.coerce(input[i][0])
      exponents = copy_exponents(input[i][1])
      raise "wrong monomial arity" if exponents.size != @ring.arity
      exponents.each ->
        raise "monomial exponents must be nonnegative integers" if item < 0
      if !coefficient.zero?
        found = -1
        j = 0
        while j < out.size
          if same_monomial?(out[j][1], exponents)
            found = j
            break
          j += 1
        if found >= 0
          sum = out[found][0] + coefficient
          if sum.zero?
            out.delete_at(found)
          else
            out[found][0] = sum
        else
          out.push([coefficient, exponents])
      i += 1

    # Canonical descending order makes the leading term O(1), iteration
    # deterministic, and equality a direct term-list comparison.
    i = 1
    while i < out.size
      j = i
      while j > 0 && @ring.monomial_compare(out[j][1], out[j - 1][1]) > 0
        temporary = out[j - 1]
        out[j - 1] = out[j]
        out[j] = temporary
        j -= 1
      i += 1
    out

  -> coerce(other)
    @ring.coerce(other)

  -> zero?
    @terms.size == 0

  -> one?
    return false if @terms.size != 1 || !@terms[0][0].one?
    i = 0
    while i < @terms[0][1].size
      return false if @terms[0][1][i] != 0
      i += 1
    true

  -> constant?
    return true if zero?
    return false if @terms.size != 1
    i = 0
    while i < @terms[0][1].size
      return false if @terms[0][1][i] != 0
      i += 1
    true

  # Iterate canonical terms without exposing the internal exponent arrays.
  -> each_term(&)
    @terms.each -> (term)
      &(term[0], copy_exponents(term[1]))
    self

  # Coefficient of a monomial.  For a univariate ring, an Integer degree is
  # accepted as shorthand for a one-element exponent array.
  -> coeff(exponents)
    powers = exponents
    powers = [exponents] if exponents.class_name == "Integer" && @ring.arity == 1
    raise "monomial exponents must be an Array" if powers.class_name != "Array"
    raise "wrong monomial arity" if powers.size != @ring.arity
    i = 0
    while i < @terms.size
      return @terms[i][0] if same_monomial?(@terms[i][1], powers)
      i += 1
    @ring.field.zero

  -> coefficient(exponents)
    coeff(exponents)

  -> exponents
    out = []
    @terms.each -> out.push(copy_exponents(item[1]))
    out

  -> +(value)
    other = coerce(value)
    Polynomial.new(@ring, @terms + other.terms)

  -> -(value)
    self + coerce(value).negate

  -> negate
    out = []
    @terms.each -> (term)
      out.push([term[0].negate, copy_exponents(term[1])])
    Polynomial.new(@ring, out)

  -> -@
    negate

  -> *(value)
    other = coerce(value)
    return @ring.zero if zero? || other.zero?
    out = []
    @terms.each -> (left)
      other.terms.each -> (right)
        exponents = []
        i = 0
        while i < @ring.arity
          exponents.push(left[1][i] + right[1][i])
          i += 1
        out.push([left[0] * right[0], exponents])
    Polynomial.new(@ring, out)

  -> **(exponent)
    raise "polynomial exponent must be a nonnegative integer" if exponent < 0
    result = @ring.one
    factor = self
    n = exponent
    while n > 0
      result = result * factor if n.odd?
      n = n / 2
      factor = factor * factor if n > 0
    result

  -> ==/1
    self.eql?(@1)

  -> eql?(value)
    return false if value.class_name == "Nil"
    value_class = value.class_name
    if value_class == "Polynomial"
      return false if value.ring != @ring
    elsif value_class != "Integer" && value_class != "Int" && value_class != "BigInt" && value_class != "Rational"
      return false
    other = coerce(value)
    return false if @terms.size != other.terms.size
    i = 0
    while i < @terms.size
      return false if @terms[i][0] != other.terms[i][0]
      return false if !same_monomial?(@terms[i][1], other.terms[i][1])
      i += 1
    true

  -> term_degree(term)
    degree = 0
    term[1].each -> degree += item
    degree

  -> degree
    return -1 if zero?
    result = 0
    @terms.each ->
      d = term_degree(item)
      result = d if d > result
    result

  -> degree_in(variable)
    index = variable.class_name == "Integer" ? variable : @ring.index_of(variable)
    raise "unknown polynomial variable" if index == nil
    result = 0
    @terms.each -> result = item[1][index] if item[1][index] > result
    result

  -> homogeneous?
    return true if zero?
    expected = term_degree(@terms[0])
    i = 0
    while i < @terms.size
      return false if term_degree(@terms[i]) != expected
      i += 1
    true

  -> assert_homogeneous(expected = nil)
    raise "polynomial is not homogeneous" if !homogeneous?
    if expected != nil && degree != expected
      raise "expected homogeneous degree " + expected.to_s + ", got " + degree.to_s
    self

  -> derivative(variable)
    index = variable.class_name == "Integer" ? variable : @ring.index_of(variable)
    raise "unknown polynomial variable" if index == nil
    out = []
    @terms.each -> (term)
      exponent = term[1][index]
      if exponent > 0
        exponents = copy_exponents(term[1])
        exponents[index] = exponent - 1
        out.push([term[0] * exponent, exponents])
    Polynomial.new(@ring, out)

  # Formal antiderivative in the given variable, with zero constant of
  # integration: c·x^e integrates to c/(e+1)·x^(e+1), exact over a
  # characteristic-zero field.  The per-term divisor e+1 passes through the
  # field so a characteristic-p domain fails loudly instead of dividing by
  # zero.  A univariate polynomial may omit the variable.
  -> antiderivative(variable = nil)
    if variable == nil
      raise "antiderivative needs a variable for multivariate polynomials" if @ring.arity != 1
      variable = 0
    index = variable.class_name == "Integer" ? variable : @ring.index_of(variable)
    raise "unknown polynomial variable" if index == nil
    out = []
    @terms.each -> (term)
      exponent = term[1][index]
      divisor = @ring.field.coerce(exponent + 1)
      raise "antiderivative divides by the field characteristic" if divisor.zero?
      exponents = copy_exponents(term[1])
      exponents[index] = exponent + 1
      out.push([term[0] / divisor, exponents])
    Polynomial.new(@ring, out)

  # Substitute one variable by a field value, leaving an exact polynomial in
  # the remaining variables (the substituted exponent column drops to zero
  # and colliding monomials merge through normalization).
  -> substitute(variable, value)
    index = variable.class_name == "Integer" ? variable : @ring.index_of(variable)
    raise "unknown polynomial variable" if index == nil
    scalar = @ring.field.coerce(value)
    out = []
    @terms.each -> (term)
      exponents = copy_exponents(term[1])
      exponents[index] = 0
      out.push([term[0] * (scalar ** term[1][index]), exponents])
    Polynomial.new(@ring, out)

  # Exact definite integral of a univariate polynomial over [lower, upper],
  # as a field element.
  -> definite_integral(lower, upper)
    raise "definite_integral without a variable needs a univariate polynomial" if @ring.arity != 1
    indefinite = antiderivative(0)
    indefinite.at(upper) - indefinite.at(lower)

  # Exact definite integral in one variable of a multivariate polynomial:
  # the result is the polynomial in the remaining variables.
  -> definite_integral(variable, lower, upper)
    indefinite = antiderivative(variable)
    indefinite.substitute(variable, upper) - indefinite.substitute(variable, lower)

  # Power-table evaluation: values[i]^e is built once per variable by
  # iterated multiplication up to degree_in(i), so a k-term polynomial costs
  # one multiply per (term, variable) instead of a fresh exponentiation per
  # term.
  -> evaluate(values)
    raise "wrong coordinate count" if values.size != @ring.arity
    return @ring.field.zero if zero?
    powers = []
    vi = 0
    while vi < values.size
      base = @ring.field.coerce(values[vi])
      column = [@ring.field.one]
      max_exponent = degree_in(vi)
      e = 1
      while e <= max_exponent
        column.push(column[e - 1] * base)
        e += 1
      powers.push(column)
      vi += 1
    result = @ring.field.zero
    @terms.each -> (term)
      value = term[0]
      ti = 0
      while ti < values.size
        exponent = term[1][ti]
        value = value * powers[ti][exponent] if exponent > 0
        ti += 1
      result = result + value
    result

  -> at(value)
    raise "at is only defined for univariate polynomials" if @ring.arity != 1
    # Horner evaluation avoids constructing large intermediate powers.
    return @ring.field.zero if zero?
    x = @ring.field.coerce(value)
    result = @ring.field.zero
    i = degree
    while i >= 0
      result = result * x + coeff(i)
      i -= 1
    result

  -> homogenize(variable = nil)
    index = variable == nil ? @ring.arity - 1 : @ring.index_of(variable)
    index = variable if variable != nil && variable.class_name == "Integer"
    raise "unknown homogenizing variable" if index == nil || index < 0 || index >= @ring.arity
    target_degree = degree
    out = []
    @terms.each -> (term)
      exponents = copy_exponents(term[1])
      exponents[index] += target_degree - term_degree(term)
      out.push([term[0], exponents])
    Polynomial.new(@ring, out)

  -> dehomogenize(variable)
    index = variable.class_name == "Integer" ? variable : @ring.index_of(variable)
    raise "unknown dehomogenizing variable" if index == nil || index < 0 || index >= @ring.arity
    out = []
    @terms.each -> (term)
      exponents = copy_exponents(term[1])
      exponents[index] = 0
      out.push([term[0], exponents])
    Polynomial.new(@ring, out)

  -> chart(index)
    dehomogenize(index)

  -> monomial_compare(left, right)
    @ring.monomial_compare(left, right)

  -> leading_term
    zero? ? nil : @terms[0]

  -> leading_coefficient
    zero? ? @ring.field.zero : @terms[0][0]

  -> lc
    leading_coefficient

  -> LC
    leading_coefficient

  -> leading_exponents
    zero? ? nil : copy_exponents(@terms[0][1])

  -> monomial_multiply(exponents, coefficient = nil)
    scalar = coefficient == nil ? @ring.field.one : @ring.field.coerce(coefficient)
    raise "wrong monomial arity" if exponents.size != @ring.arity
    out = []
    @terms.each -> (term)
      powers = []
      i = 0
      while i < @ring.arity
        powers.push(term[1][i] + exponents[i])
        i += 1
      out.push([term[0] * scalar, powers])
    Polynomial.new(@ring, out)

  -> monic
    return self if zero?
    monomial_multiply(@ring.zero_exponents, @ring.field.one / leading_coefficient)

  -> monomial_divides?(divisor, dividend)
    i = 0
    while i < divisor.size
      return false if divisor[i] > dividend[i]
      i += 1
    true

  # Multivariate leading-term division. Returns [quotients, remainder].
  -> divide(divisors)
    normalized = []
    divisors.each ->
      polynomial = coerce(item)
      raise "polynomial division by zero" if polynomial.zero?
      normalized.push(polynomial)
    quotients = []
    normalized.each -> quotients.push(@ring.zero)
    pending = self
    remainder = @ring.zero
    while !pending.zero?
      lt = pending.leading_term
      reduced = false
      i = 0
      while i < normalized.size
        divisor = normalized[i]
        dlt = divisor.leading_term
        if monomial_divides?(dlt[1], lt[1])
          powers = []
          j = 0
          while j < @ring.arity
            powers.push(lt[1][j] - dlt[1][j])
            j += 1
          term = @ring.monomial(lt[0] / dlt[0], powers)
          quotients[i] = quotients[i] + term
          pending = pending - term * divisor
          reduced = true
          break
        i += 1
      if !reduced
        single = @ring.monomial(lt[0], copy_exponents(lt[1]))
        remainder = remainder + single
        pending = pending - single
    [quotients, remainder]

  -> divmod(divisor)
    result = divide([divisor])
    [result[0][0], result[1]]

  -> quo(divisor)
    divmod(divisor)[0]

  -> rem(divisor)
    divmod(divisor)[1]

  -> /(divisor)
    result = divmod(divisor)
    raise "polynomial division is not exact" if !result[1].zero?
    result[0]

  -> normal_form(basis)
    divide(basis)[1]

  -> coefficients
    raise "coefficients is only defined for univariate polynomials" if @ring.arity != 1
    return [] if zero?
    out = []
    i = 0
    while i <= degree
      out.push(@ring.field.zero)
      i += 1
    @terms.each -> out[item[1][0]] = item[0]
    out

  # Rational polynomial content: gcd(numerators) / lcm(denominators).
  -> content
    return @ring.field.zero if zero?
    if @ring.field.class_name != "RationalField"
      raise "polynomial content is currently implemented only over ℚ"
    common_denominator = 1
    @terms.each ->
      denominator = item[0].denominator
      common_denominator = (common_denominator / common_denominator.gcd(denominator)) * denominator
    numerator_gcd = 0
    @terms.each ->
      scaled = item[0].numerator * (common_denominator / item[0].denominator)
      numerator_gcd = numerator_gcd.gcd(scaled.abs)
    Rational.new(numerator_gcd, common_denominator)

  -> primitive_part
    return self if zero?
    c = content
    monomial_multiply(@ring.zero_exponents, @ring.field.one / c)

  -> primitive
    primitive_part

  -> determinant(matrix)
    n = matrix.size
    return @ring.field.one if n == 0
    work = []
    row_index = 0
    while row_index < n
      row = []
      column_index = 0
      while column_index < matrix[row_index].size
        row.push(matrix[row_index][column_index])
        column_index += 1
      work.push(row)
      row_index += 1
    det_value = @ring.field.one
    column = 0
    while column < n
      pivot = column
      while pivot < n && work[pivot][column].zero?
        pivot += 1
      return @ring.field.zero if pivot == n
      if pivot != column
        temporary = work[column]
        work[column] = work[pivot]
        work[pivot] = temporary
        det_value = 0 - det_value
      pivot_value = work[column][column]
      det_value = det_value * pivot_value
      row = column + 1
      while row < n
        if !work[row][column].zero?
          factor = work[row][column] / pivot_value
          c = column
          while c < n
            work[row][c] = work[row][c] - factor * work[column][c]
            c += 1
        row += 1
      column += 1
    det_value

  # Univariate resultant.
  #
  # Over ℚ this runs Collins's subresultant polynomial-remainder sequence on
  # integerized primitive coefficient arrays: every pseudo-remainder division
  # is exact by the subresultant theory, so intermediate coefficients stay
  # near determinant-bound size instead of the combinatorial growth of
  # fraction pivoting — while the Sylvester-determinant route costs
  # O((m+n)^3) field operations on an (m+n)-square matrix.  Contents are
  # factored out first and restored through
  # Res(c·F, d·G) = c^deg(G) · d^deg(F) · Res(F, G).  A non-rational
  # coefficient field falls back to exact elimination on the Sylvester
  # matrix.
  -> resultant(other)
    other = coerce(other)
    raise "resultant is only defined for univariate polynomials" if @ring.arity != 1
    m = degree
    n = other.degree
    return @ring.field.zero if m < 0 || n < 0
    return leading_coefficient ** n if m == 0
    return other.leading_coefficient ** m if n == 0
    if @ring.field.class_name == "RationalField"
      self_content = content
      other_content = other.content
      r = Polynomial.integer_subresultant_resultant(
        integerized_coefficients(self_content),
        other.integerized_coefficients(other_content))
      return (self_content ** n) * (other_content ** m) * r
    sylvester_resultant(other)

  # Ascending integer coefficients of self divided by the given content —
  # the primitive integer image used by the subresultant sequence.
  -> integerized_coefficients(polynomial_content)
    out = []
    coefficients.each ->
      out.push((item / polynomial_content).numerator)
    out

  # prem(a, b) = lc(b)^(deg a - deg b + 1) · a  mod  b on ascending integer
  # coefficient arrays (zero is the empty array).  Pseudo-division never
  # leaves the integers; the unused scale factor is applied at the end so
  # the result matches the full lc(b) power whatever the reduction count.
  -> .integer_pseudo_remainder(a, b)
    db = b.size - 1
    lb = b[db]
    r = []
    a.each -> r.push(item)
    reductions = a.size - b.size + 1
    while r.size >= b.size
      dr = r.size - 1
      lead = r[dr]
      reduced = []
      i = 0
      while i < dr
        value = lb * r[i]
        j = i - (dr - db)
        value = value - lead * b[j] if j >= 0 && j < db
        reduced.push(value)
        i += 1
      while reduced.size > 0 && reduced[reduced.size - 1] == 0
        reduced.delete_at(reduced.size - 1)
      r = reduced
      reductions -= 1
      break if r.size == 0
    if reductions > 0 && r.size > 0
      factor = lb ** reductions
      scaled = []
      r.each -> scaled.push(item * factor)
      r = scaled
    r

  # Collins's subresultant PRS on ascending integer arrays: each
  # pseudo-remainder is divided by g·h^δ (exact), with g the previous
  # leading coefficient and h the subresultant scale h ← g^δ / h^(δ-1).
  # The sign tracks Res(f, g) = (-1)^(deg f · deg g) Res(g, f) at the
  # initial swap and per PRS step.
  -> .integer_subresultant_resultant(first, second)
    a = first
    b = second
    s = 1
    if a.size < b.size
      s = 0 - s if (((a.size - 1) * (b.size - 1)) % 2) == 1
      swapped = a
      a = b
      b = swapped
    g = 1
    h = 1
    while b.size - 1 > 0
      da = a.size - 1
      db = b.size - 1
      delta = da - db
      s = 0 - s if da.odd? && db.odd?
      r = Polynomial.integer_pseudo_remainder(a, b)
      return 0 if r.size == 0
      a = b
      divisor = g * (h ** delta)
      reduced = []
      r.each -> reduced.push(item / divisor)
      b = reduced
      g = a[a.size - 1]
      h = (g ** delta) / (h ** (delta - 1)) if delta > 0
    da = a.size - 1
    (s * (b[0] ** da)) / (h ** (da - 1))

  # Exact O((m+n)^3) reference path: the resultant as the determinant of
  # the Sylvester matrix over the coefficient field.  Kept for non-rational
  # fields and as the cross-check oracle for the PRS path in the specs.
  -> sylvester_resultant(other)
    other = coerce(other)
    raise "resultant is only defined for univariate polynomials" if @ring.arity != 1
    m = degree
    n = other.degree
    return @ring.field.zero if m < 0 || n < 0
    return leading_coefficient ** n if m == 0
    return other.leading_coefficient ** m if n == 0
    a = coefficients.reverse
    b = other.coefficients.reverse
    size = m + n
    matrix = []
    r = 0
    while r < size
      row = []
      c = 0
      while c < size
        row.push(@ring.field.zero)
        c += 1
      matrix.push(row)
      r += 1
    r = 0
    while r < n
      c = 0
      while c <= m
        matrix[r][r + c] = a[c]
        c += 1
      r += 1
    r = 0
    while r < m
      c = 0
      while c <= n
        matrix[n + r][r + c] = b[c]
        c += 1
      r += 1
    determinant(matrix)

  -> discriminant
    raise "discriminant is only defined for univariate polynomials" if @ring.arity != 1
    n = degree
    return @ring.field.one if n <= 1
    sign = ((n * (n - 1) / 2).odd?) ? -1 : 1
    @ring.field.coerce(sign) * resultant(derivative(0)) / leading_coefficient

  # View this polynomial as a polynomial in one selected variable. The
  # returned coefficient remains in the same sparse ambient ring, with the
  # selected exponent set to zero. Keeping one ring avoids inventing a
  # recursive polynomial type while still supporting exact pseudo-remainders.
  -> coefficient_in(variable, exponent)
    index = variable.class_name == "Integer" ? variable : @ring.index_of(variable)
    raise "unknown polynomial variable" if index == nil
    out = []
    @terms.each -> (term)
      if term[1][index] == exponent
        powers = copy_exponents(term[1])
        powers[index] = 0
        out.push([term[0], powers])
    Polynomial.new(@ring, out)

  -> highest_active_variable(other)
    candidate = @ring.arity - 1
    while candidate >= 0
      if degree_in(candidate) > 0 || other.degree_in(candidate) > 0
        return candidate
      candidate -= 1
    -1

  # Coefficient content with respect to x_variable. Coefficients only involve
  # variables below `variable` in the recursive calls made by gcd_recursive.
  -> content_in(variable)
    result = nil
    exponent = 0
    while exponent <= degree_in(variable)
      coefficient = coefficient_in(variable, exponent)
      if !coefficient.zero?
        if result.class_name == "Nil"
          result = coefficient.monic
        else
          result = result.gcd_recursive(coefficient, variable - 1)
      exponent += 1
    result.class_name == "Nil" ? @ring.zero : result.monic

  -> primitive_part_in(variable)
    return self if zero?
    coefficient_content = content_in(variable)
    return monic if coefficient_content.constant?
    (self / coefficient_content).monic

  # Pseudo-division in one selected variable. Unlike ordinary division, the
  # leading coefficient may itself be a polynomial in lower variables, so
  # each step cross-multiplies instead of entering a rational-function field.
  -> pseudo_remainder(divisor, variable)
    divisor = coerce(divisor)
    raise "polynomial division by zero" if divisor.zero?
    divisor_degree = divisor.degree_in(variable)
    divisor_lc = divisor.coefficient_in(variable, divisor_degree)
    remainder = self
    steps = 0
    while !remainder.zero? && remainder.degree_in(variable) >= divisor_degree
      raise "polynomial pseudo-remainder limit exceeded" if steps >= 20_000
      remainder_degree = remainder.degree_in(variable)
      remainder_lc = remainder.coefficient_in(variable, remainder_degree)
      powers = @ring.zero_exponents
      powers[variable] = remainder_degree - divisor_degree
      shift = @ring.monomial(@ring.field.one, powers)
      remainder = divisor_lc * remainder - remainder_lc * shift * divisor
      steps += 1
    remainder

  # Primitive polynomial-remainder sequence over
  # ℚ[x0, ..., x_variable]. This is intentionally slow but exact. It supplies
  # a real multivariate GCD without requiring rational-function coefficients.
  -> gcd_recursive(other, variable)
    other = coerce(other)
    return other.monic if zero?
    return monic if other.zero?

    active = variable
    while active >= 0 && degree_in(active) == 0 && other.degree_in(active) == 0
      active -= 1
    return @ring.one if active < 0

    if active == 0
      left = self
      right = other
      while !right.zero?
        remainder = left.rem(right)
        left = right
        right = remainder
      return left.monic

    left_content = content_in(active)
    right_content = other.content_in(active)
    common_content = left_content.gcd_recursive(right_content, active - 1)
    left = left_content.constant? ? monic : (self / left_content).monic
    right = right_content.constant? ? other.monic : (other / right_content).monic

    while !right.zero?
      remainder = left.pseudo_remainder(right, active)
      if !remainder.zero?
        remainder = remainder.primitive_part_in(active)
      left = right
      right = remainder

    primitive_gcd = left.primitive_part_in(active)
    (common_content * primitive_gcd).monic

  -> gcd(other)
    other = coerce(other)
    gcd_recursive(other, highest_active_variable(other))

  -> primitive_gcd(other)
    gcd(other).monic

  # Extended Euclidean algorithm over a univariate polynomial ring.
  # Returns [g, s, t] with s*self + t*other = g and g monic.
  -> xgcd(other)
    other = coerce(other)
    raise "extended gcd is only defined for univariate polynomials" if @ring.arity != 1
    old_remainder = self
    remainder = other
    old_left = @ring.one
    left = @ring.zero
    old_right = @ring.zero
    right = @ring.one

    while !remainder.zero?
      step = old_remainder.divmod(remainder)
      quotient = step[0]
      next_remainder = step[1]
      old_remainder = remainder
      remainder = next_remainder

      next_left = old_left - quotient * left
      old_left = left
      left = next_left
      next_right = old_right - quotient * right
      old_right = right
      right = next_right

    return [@ring.zero, @ring.zero, @ring.zero] if old_remainder.zero?
    scale = @ring.field.one / old_remainder.leading_coefficient
    powers = @ring.zero_exponents
    [old_remainder.monomial_multiply(powers, scale),
     old_left.monomial_multiply(powers, scale),
     old_right.monomial_multiply(powers, scale)]

  -> squarefree?
    return true if degree <= 0
    common = self
    variable = 0
    while variable < @ring.arity
      common = common.gcd(derivative(variable))
      return true if common.degree == 0
      variable += 1
    common.degree == 0

  -> integer_divisors(value)
    n = value.abs
    return [0] if n == 0
    out = []
    i = 1
    while i * i <= n
      if n % i == 0
        out.push(i)
        other = n / i
        out.push(other) if other != i
      i += 1
    out

  -> rational_root_candidates
    raise "factorization is only implemented over ℚ" if @ring.field.class_name != "RationalField"
    values = coefficients
    common_denominator = 1
    values.each ->
      common_denominator = (common_denominator / common_denominator.gcd(item.denominator)) * item.denominator
    integers = values.map -> item.numerator * (common_denominator / item.denominator)
    numerators = integer_divisors(integers[0])
    denominators = integer_divisors(integers[integers.size - 1])
    out = []
    numerators.each -> (p)
      denominators.each -> (q)
        if q != 0
          positive = Rational.new(p, q)
          out.push(positive) if !out.include?(positive)
          negative = 0 - positive
          out.push(negative) if !out.include?(negative)
    out

  -> signed_integer_divisors(value)
    out = []
    integer_divisors(value).each -> (divisor)
      out.push(divisor)
      out.push(0 - divisor) if divisor != 0
    out

  # Exact Lagrange interpolation through integer samples. A candidate is
  # useful to Kronecker's method only when every resulting coefficient is an
  # integer.
  -> interpolate_integer_factor(points, values)
    x = @ring.generator(0)
    candidate = @ring.zero
    i = 0
    while i < points.size
      term = @ring.constant(values[i])
      denominator = 1
      j = 0
      while j < points.size
        if i != j
          term = term * (x - points[j])
          denominator = denominator * (points[i] - points[j])
        j += 1
      term = term * Rational.new(1, denominator)
      candidate = candidate + term
      i += 1

    integer_coefficients = true
    candidate.coefficients.each ->
      integer_coefficients = false if item.denominator != 1
    return nil if !integer_coefficients
    candidate

  # Kronecker's theorem turns exact factor search into finite interpolation:
  # for a degree-d integer factor g and d+1 distinct sample points ai,
  # g(ai) divides f(ai). Enumerating those signed divisors and interpolating
  # therefore finds every possible factor of degree at most floor(n/2).
  -> kronecker_factor(search_limit = 250_000)
    primitive = primitive_part
    primitive = primitive.negate if primitive.leading_coefficient.negative?
    maximum_degree = primitive.degree / 2
    target_degree = 1
    attempts = 0

    while target_degree <= maximum_degree
      # Gather a few extra non-root samples, then retain those with the
      # smallest divisor sets. This changes only search order, not completeness.
      samples = []
      sample_index = 0
      wanted = target_degree + 5
      while samples.size < wanted
        if sample_index == 0
          point = 0
        else
          magnitude = (sample_index + 1) / 2
          point = sample_index.odd? ? magnitude : 0 - magnitude
        sample_index += 1
        value = primitive.at(point)
        if !value.zero?
          divisors = signed_integer_divisors(value.numerator)
          entry = [point, divisors]
          sample_position = samples.size
          while sample_position > 0 && divisors.size < samples[sample_position - 1][1].size
            sample_position -= 1
          samples.push(entry)
          sample_shift = samples.size - 1
          while sample_shift > sample_position
            samples[sample_shift] = samples[sample_shift - 1]
            sample_shift -= 1
          samples[sample_position] = entry

      count = target_degree + 1
      points = []
      divisor_sets = []
      i = 0
      while i < count
        points.push(samples[i][0])
        divisor_sets.push(samples[i][1])
        i += 1

      indices = []
      i = 0
      while i < count
        indices.push(0)
        i += 1
      finished = false
      while !finished
        attempts += 1
        if attempts > search_limit
          raise "Kronecker factor search limit exceeded"

        values = []
        i = 0
        while i < count
          values.push(divisor_sets[i][indices[i]])
          i += 1
        candidate = interpolate_integer_factor(points, values)
        if candidate.class_name != "Nil" && candidate.degree > 0 && candidate.degree < primitive.degree
          candidate = candidate.primitive_part
          candidate = candidate.negate if candidate.leading_coefficient.negative?
          if primitive.rem(candidate).zero?
            return candidate

        carry_index = count - 1
        while carry_index >= 0
          next_choice = indices[carry_index] + 1
          indices[carry_index] = next_choice
          choice_set = divisor_sets[carry_index]
          choice_count = choice_set.size
          if next_choice != choice_count
            break
          indices[carry_index] = 0
          carry_index -= 1
        finished = true if carry_index < 0

      target_degree += 1
    nil

  # Complete exact factorization over ℚ by rational-root extraction followed
  # by bounded Kronecker interpolation for factors of degree at least two.
  # The resource limit fails loudly; it never labels an unsearched residual
  # polynomial irreducible.
  -> factor(search_limit = 250_000)
    raise "factorization is only defined for univariate polynomials" if @ring.arity != 1
    raise "factorization is only implemented over ℚ" if @ring.field.class_name != "RationalField"
    return [self] if degree <= 1

    x = @ring.generator(0)
    root = nil
    rational_root_candidates.each ->
      if root.class_name == "Nil" && at(item).zero?
        root = item
    if root.class_name != "Nil"
      linear = x - root
      return [linear] + (self / linear).factor(search_limit)

    # A quadratic or cubic over a field is reducible exactly when it has a
    # root. The rational-root search above is exhaustive over ℚ.
    return [self] if degree <= 3

    candidate = kronecker_factor(search_limit)
    return [self] if candidate.class_name == "Nil"
    candidate.factor(search_limit) + (self / candidate).factor(search_limit)

  -> factors
    factor

  -> galois_group
    GaloisGroup.of(self)

  -> coefficient_to_s(coefficient)
    if coefficient.class_name == "Rational" && coefficient.denominator == 1
      return coefficient.numerator.to_s
    coefficient.to_s

  -> to_s
    return "0" if zero?
    pieces = []
    @terms.each -> (term)
      coefficient = term[0]
      monomial = ""
      i = 0
      while i < @ring.arity
        exponent = term[1][i]
        if exponent > 0
          monomial += @ring.names[i].to_s
          monomial += "^" + exponent.to_s if exponent != 1
        i += 1
      if monomial == ""
        pieces.push(coefficient_to_s(coefficient))
      elsif coefficient.one?
        pieces.push(monomial)
      elsif coefficient == @ring.field.coerce(-1)
        pieces.push("-" + monomial)
      else
        pieces.push(coefficient_to_s(coefficient) + monomial)
    pieces.join(" + ").replace("+ -", "- ")

  -> inspect
    to_s


# `Poly<K>.new(:x).generator` remains the concise univariate entry point.
# The algebra surface rewrite uses the field-first array constructor:
#
#   Poly<ℚ>.new(:x, :y) -> Poly<ℚ>.new(Algebra.field("ℚ"), [:x, :y])
+ Poly<K>
  with K in (ℚ RationalField)

  -> new(field: Field, names)
    raise "Poly field constructor needs an Array of generator names" if names.class_name != "Array"
    if names.size == 1 && names[0].class_name == "Array"
      names = names[0]
    raise "a polynomial ring needs at least one generator" if names.size == 0
    @ring = PolynomialRing.new(
      names, Field.require_supported(field), :grevlex)

  ro :ring

  -> generator
    @ring.generator(0)

  -> generators
    @ring.generators
