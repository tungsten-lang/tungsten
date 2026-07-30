# Exact sparse multivariate polynomials over an explicit coefficient field.
#
# PolynomialRing owns both the field and the monomial order.  Polynomial never
# silently substitutes ℚ: every coefficient enters through ring.field.coerce.
# Algorithmic layers live in sibling files (resultant, gcd, factor) and reopen
# Polynomial so the public surface stays one class.

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
    return zero if @field.zero?(coefficient)
    Polynomial.new(self, [[coefficient, zero_exponents]])

  -> monomial(coefficient, exponents)
    Polynomial.new(self, [[@field.coerce(coefficient), exponents]])

  # Construct a monomial whose coefficient is already a normalized field
  # element (not an external scalar to embed through the prime subfield).
  -> monomial_raw(coefficient, exponents)
    Polynomial.new(self, [[@field.normalize_element(coefficient), exponents]])

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

  # Coefficient arithmetic always goes through the ring field so FiniteField
  # residues never leak as unreduced Integers (e.g. 3+3 = 6 in F_5).
  -> field_add(left, right)
    @ring.field.add(left, right)

  -> field_mul(left, right)
    @ring.field.multiply(left, right)

  -> field_neg(value)
    @ring.field.negate(value)

  -> field_div(left, right)
    @ring.field.divide(left, right)

  -> field_zero?(value)
    @ring.field.zero?(value)

  -> field_one?(value)
    @ring.field.one?(value)

  -> field_eq?(left, right)
    @ring.field.equal?(left, right)

  -> field_pow(value, exponent)
    @ring.field.power(value, exponent)

  -> normalize_terms(input)
    out = []
    i = 0
    while i < input.size
      coefficient = @ring.field.normalize_element(input[i][0])
      exponents = copy_exponents(input[i][1])
      raise "wrong monomial arity" if exponents.size != @ring.arity
      exponents.each ->
        raise "monomial exponents must be nonnegative integers" if item < 0
      if !field_zero?(coefficient)
        found = -1
        j = 0
        while j < out.size
          if same_monomial?(out[j][1], exponents)
            found = j
            break
          j += 1
        if found >= 0
          sum = field_add(out[found][0], coefficient)
          if field_zero?(sum)
            out.delete_at(found)
          else
            out[found][0] = sum
        else
          out.push([coefficient, exponents])
      i += 1
    sort_terms_descending(out)

  # In-place insertion sort into the ring's monomial order (largest first).
  -> sort_terms_descending(out)
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

  # Linear merge of two term lists already sorted descending by monomial order.
  -> merge_sorted_terms(left, right)
    out = []
    i = 0
    j = 0
    while i < left.size && j < right.size
      cmp = @ring.monomial_compare(left[i][1], right[j][1])
      if cmp > 0
        out.push([left[i][0], copy_exponents(left[i][1])])
        i += 1
      elsif cmp < 0
        out.push([right[j][0], copy_exponents(right[j][1])])
        j += 1
      else
        sum = field_add(left[i][0], right[j][0])
        if !field_zero?(sum)
          out.push([sum, copy_exponents(left[i][1])])
        i += 1
        j += 1
    while i < left.size
      out.push([left[i][0], copy_exponents(left[i][1])])
      i += 1
    while j < right.size
      out.push([right[j][0], copy_exponents(right[j][1])])
      j += 1
    out

  -> coerce(other)
    @ring.coerce(other)

  -> zero?
    @terms.size == 0

  -> one?
    return false if @terms.size != 1 || !field_one?(@terms[0][0])
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
      out.push([field_neg(term[0]), copy_exponents(term[1])])
    # Negation preserves monomial order.
    Polynomial.new(@ring, out)

  -> -@
    negate

  # Sparse multiplication: each left term scales the already-sorted right
  # factor into another sorted list; those lists are merged so the product
  # never re-sorts a quadratic bag of monomials.
  -> *(value)
    other = coerce(value)
    return @ring.zero if zero? || other.zero?
    if @ring.arity == 1
      dense = dense_multiply(other)
      return dense if dense.class_name != "Nil"
    result_terms = []
    @terms.each -> (left)
      partial = []
      other.terms.each -> (right)
        exponents = []
        i = 0
        while i < @ring.arity
          exponents.push(left[1][i] + right[1][i])
          i += 1
        partial.push([field_mul(left[0], right[0]), exponents])
      result_terms = merge_sorted_terms(result_terms, partial)
    Polynomial.new(@ring, result_terms)

  # Dense univariate product when both sides fill enough of their degree
  # range that an array multiply beats sparse pair generation.
  -> dense_multiply(other)
    return nil if @ring.arity != 1
    self_degree = degree
    other_degree = other.degree
    return nil if self_degree < 0 || other_degree < 0
    self_terms = @terms.size
    other_terms = other.terms.size
    # Sparse remains better when either factor is very sparse.
    return nil if self_terms * 2 < self_degree || other_terms * 2 < other_degree
    left = coefficients
    right = other.coefficients
    product_degree = self_degree + other_degree
    product = []
    i = 0
    while i <= product_degree
      product.push(@ring.field.zero)
      i += 1
    i = 0
    while i <= self_degree
      if !field_zero?(left[i])
        j = 0
        while j <= other_degree
          if !field_zero?(right[j])
            product[i + j] = field_add(product[i + j], field_mul(left[i], right[j]))
          j += 1
      i += 1
    out = []
    i = product_degree
    while i >= 0
      if !field_zero?(product[i])
        out.push([product[i], [i]])
      i -= 1
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
      return false if !field_eq?(@terms[i][0], other.terms[i][0])
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
        scale = @ring.field.coerce(exponent)
        # In characteristic p the p-th power terms vanish automatically.
        if !field_zero?(scale)
          out.push([field_mul(term[0], scale), exponents])
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
      raise "antiderivative divides by the field characteristic" if field_zero?(divisor)
      exponents = copy_exponents(term[1])
      exponents[index] = exponent + 1
      out.push([field_div(term[0], divisor), exponents])
    Polynomial.new(@ring, out)

  -> substitution_index(variable)
    index = variable.class_name == "Integer" ? variable : @ring.index_of(variable)
    raise "unknown polynomial variable" if index == nil
    index

  # Substitute one variable by an external scalar. Integers embed through the
  # field's prime subfield; packed extension-field residues use substitute_raw.
  -> substitute(variable, value)
    substitute_element(
      substitution_index(variable), @ring.field.coerce(value))

  # Internal/raw variant for an already-normalized coefficient-field element.
  -> substitute_raw(variable, value)
    substitute_element(
      substitution_index(variable), @ring.field.normalize_element(value))

  -> substitute_element(index, scalar)
    out = []
    @terms.each -> (term)
      exponents = copy_exponents(term[1])
      power = term[1][index]
      exponents[index] = 0
      out.push([field_mul(term[0], field_pow(scalar, power)), exponents])
    Polynomial.new(@ring, out)

  # Exact definite integral of a univariate polynomial over [lower, upper],
  # as a field element.
  -> definite_integral(lower, upper)
    raise "definite_integral without a variable needs a univariate polynomial" if @ring.arity != 1
    indefinite = antiderivative(0)
    @ring.field.subtract(indefinite.at(upper), indefinite.at(lower))

  # Exact definite integral in one variable of a multivariate polynomial:
  # the result is the polynomial in the remaining variables.
  -> definite_integral(variable, lower, upper)
    indefinite = antiderivative(variable)
    indefinite.substitute(variable, upper) - indefinite.substitute(variable, lower)

  # Public evaluation embeds external scalars through Field#coerce. In a packed
  # extension field this distinguishes the Integer p (the scalar zero) from
  # the raw encoded basis element whose representation also happens to be p.
  -> evaluate(values)
    raise "wrong coordinate count" if values.size != @ring.arity
    coerced = []
    values.each -> coerced.push(@ring.field.coerce(item))
    evaluate_raw(coerced)

  # Power-table evaluation of already-normalized field elements. values[i]^e
  # is built once per variable by iterated multiplication up to degree_in(i),
  # so a k-term polynomial costs one multiply per (term, variable) instead of
  # a fresh exponentiation per term.
  -> evaluate_raw(values)
    raise "wrong coordinate count" if values.size != @ring.arity
    return @ring.field.zero if zero?
    powers = []
    vi = 0
    while vi < values.size
      base = @ring.field.normalize_element(values[vi])
      column = [@ring.field.one]
      max_exponent = degree_in(vi)
      e = 1
      while e <= max_exponent
        column.push(field_mul(column[e - 1], base))
        e += 1
      powers.push(column)
      vi += 1
    result = @ring.field.zero
    @terms.each -> (term)
      value = term[0]
      ti = 0
      while ti < values.size
        exponent = term[1][ti]
        value = field_mul(value, powers[ti][exponent]) if exponent > 0
        ti += 1
      result = field_add(result, value)
    result

  -> at(value)
    raise "at is only defined for univariate polynomials" if @ring.arity != 1
    return @ring.field.zero if zero?
    at_element(@ring.field.coerce(value))

  # Horner evaluation at an already-normalized coefficient-field element.
  -> at_raw(value)
    raise "at_raw is only defined for univariate polynomials" if @ring.arity != 1
    return @ring.field.zero if zero?
    at_element(@ring.field.normalize_element(value))

  -> at_element(x)
    result = @ring.field.zero
    i = degree
    while i >= 0
      result = field_add(field_mul(result, x), coeff(i))
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
    monomial_multiply_element(exponents, scalar)

  # Internal/raw coefficient variant of monomial_multiply.
  -> monomial_multiply_raw(exponents, coefficient = nil)
    scalar = coefficient == nil ? @ring.field.one : @ring.field.normalize_element(coefficient)
    monomial_multiply_element(exponents, scalar)

  -> monomial_multiply_element(exponents, scalar)
    raise "wrong monomial arity" if exponents.size != @ring.arity
    out = []
    @terms.each -> (term)
      powers = []
      i = 0
      while i < @ring.arity
        powers.push(term[1][i] + exponents[i])
        i += 1
      out.push([field_mul(term[0], scalar), powers])
    Polynomial.new(@ring, out)

  -> monic
    return self if zero?
    monomial_multiply_raw(@ring.zero_exponents, field_div(@ring.field.one, leading_coefficient))

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
          term = @ring.monomial_raw(field_div(lt[0], dlt[0]), powers)
          quotients[i] = quotients[i] + term
          pending = pending - term * divisor
          reduced = true
          break
        i += 1
      if !reduced
        single = @ring.monomial_raw(lt[0], copy_exponents(lt[1]))
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
    monomial_multiply_raw(@ring.zero_exponents, field_div(@ring.field.one, c))

  -> primitive
    primitive_part

  # Highest exponent among the first `count` variables (0 if none appear).
  -> degree_in_prefix(count)
    raise "prefix length out of range" if count < 0 || count > @ring.arity
    result = 0
    @terms.each -> (term)
      i = 0
      while i < count
        result = term[1][i] if term[1][i] > result
        i += 1
    result

  # Embed into a ring with `count` new leading variables (exponents 0).
  -> lift_variables(count, new_ring)
    raise "lift arity mismatch" if new_ring.arity != @ring.arity + count
    out = []
    @terms.each -> (term)
      exponents = []
      i = 0
      while i < count
        exponents.push(0)
        i += 1
      term[1].each -> exponents.push(item)
      out.push([term[0], exponents])
    Polynomial.new(new_ring, out)

  # Drop the first `count` variables (they must not appear).
  -> drop_variables(count, new_ring)
    raise "drop arity mismatch" if new_ring.arity != @ring.arity - count
    raise "cannot drop variables that still appear" if degree_in_prefix(count) != 0
    out = []
    @terms.each -> (term)
      exponents = []
      i = count
      while i < @ring.arity
        exponents.push(term[1][i])
        i += 1
      out.push([term[0], exponents])
    Polynomial.new(new_ring, out)

  # Re-host coefficients in another ring of equal arity (used after elimination
  # when the surviving variable names match the original ring's tail).
  -> rename_into(new_ring)
    raise "rename arity mismatch" if new_ring.arity != @ring.arity
    out = []
    @terms.each -> (term)
      out.push([term[0], copy_exponents(term[1])])
    Polynomial.new(new_ring, out)

  -> galois_group
    GaloisGroup.of(self)

  -> coefficient_to_s(coefficient)
    @ring.field.element_to_s(coefficient)

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
      elsif field_one?(coefficient)
        pieces.push(monomial)
      elsif field_eq?(coefficient, @ring.field.coerce(-1))
        pieces.push("-" + monomial)
      else
        pieces.push(coefficient_to_s(coefficient) + monomial)
    pieces.join(" + ").replace("+ -", "- ")

  -> inspect
    to_s

  -> to_expression
    Expression.from_polynomial(self)


# `Poly<K>.new(:x).generator` remains the concise univariate entry point.
# The algebra surface rewrite uses the field-first array constructor:
#
#   Poly<ℚ>.new(:x, :y) -> Poly<ℚ>.new(Algebra.field("ℚ"), [:x, :y])

+ Poly<K>
  with K in (ℚ RationalField FiniteField)

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
