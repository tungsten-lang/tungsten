# Resultant, discriminant, and exact determinants for Polynomial.
# Reopens Polynomial; load after polynomial.w.

+ Polynomial
  -> determinant(matrix)
    n = matrix.size
    return @ring.field.one if n == 0
    work = []
    row_index = 0
    while row_index < n
      row = []
      column_index = 0
      while column_index < matrix[row_index].size
        row.push(@ring.field.normalize_element(
          matrix[row_index][column_index]))
        column_index += 1
      work.push(row)
      row_index += 1
    det_value = @ring.field.one
    column = 0
    while column < n
      pivot = column
      while pivot < n && field_zero?(work[pivot][column])
        pivot += 1
      return @ring.field.zero if pivot == n
      if pivot != column
        temporary = work[column]
        work[column] = work[pivot]
        work[pivot] = temporary
        det_value = field_neg(det_value)
      pivot_value = work[column][column]
      det_value = field_mul(det_value, pivot_value)
      row = column + 1
      while row < n
        if !field_zero?(work[row][column])
          factor = field_div(work[row][column], pivot_value)
          c = column
          while c < n
            work[row][c] = field_add(work[row][c], field_neg(field_mul(factor, work[column][c])))
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
    return field_pow(leading_coefficient, n) if m == 0
    return field_pow(other.leading_coefficient, m) if n == 0
    if @ring.field.class_name == "RationalField"
      self_content = content
      other_content = other.content
      r = Polynomial.integer_subresultant_resultant(
        integerized_coefficients(self_content),
        other.integerized_coefficients(other_content))
      return field_mul(
        field_mul(field_pow(self_content, n), field_pow(other_content, m)),
        @ring.field.coerce(r))
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
    return field_pow(leading_coefficient, n) if m == 0
    return field_pow(other.leading_coefficient, m) if n == 0
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
    field_div(
      field_mul(@ring.field.coerce(sign), resultant(derivative(0))),
      leading_coefficient)

  -> order_at_zero
    if @ring.arity != 1
      raise "order_at_zero is only defined for univariate polynomials"
    return nil if zero?
    exponent = 0
    while exponent <= degree
      return exponent if !field_zero?(coeff(exponent))
      exponent += 1
    nil

  -> valuation_at_zero
    order_at_zero

  # Coefficients in one variable, represented as univariate polynomials in
  # the other. This small recursive-polynomial boundary is enough for exact
  # bivariate Sylvester resultants without changing Polynomial's sparse
  # coefficient representation.
  -> coefficient_polynomials_in(variable)
    if @ring.arity != 2
      raise "coefficient_polynomials_in currently requires two variables"
    index = (
      variable.class_name == "Int" ?
      variable : @ring.index_of(variable))
    if index == nil || index < 0 || index >= 2
      raise "unknown bivariate coefficient variable"
    other = 1 - index
    coefficient_ring = PolynomialRing.new(
      [@ring.names[other]], @ring.field, @ring.order)
    out = []
    exponent = 0
    while exponent <= degree_in(index)
      out.push(coefficient_ring.zero)
      exponent += 1
    self.each_term -> (coefficient, exponents)
      power = exponents[index]
      out[power] += coefficient_ring.monomial(
        coefficient, [exponents[other]])
    out

  # Fraction-free determinant over a univariate polynomial domain. Bareiss
  # divisions are exact minors, preventing rational-function coefficient
  # growth in the bivariate Sylvester matrix.
  -> .polynomial_bareiss_determinant(matrix, ring)
    size = matrix.size
    return ring.one if size == 0
    work = []
    matrix.each -> (source_row)
      if source_row.size != size
        raise "polynomial determinant requires a square matrix"
      row = []
      source_row.each -> row.push(ring.coerce(item))
      work.push(row)
    sign = 1
    previous = ring.one
    pivot_index = 0
    while pivot_index + 1 < size
      pivot_row = pivot_index
      while (pivot_row < size &&
             work[pivot_row][pivot_index].zero?)
        pivot_row += 1
      return ring.zero if pivot_row == size
      if pivot_row != pivot_index
        temporary = work[pivot_index]
        work[pivot_index] = work[pivot_row]
        work[pivot_row] = temporary
        sign = 0 - sign
      pivot = work[pivot_index][pivot_index]
      row_index = pivot_index + 1
      while row_index < size
        column_index = pivot_index + 1
        while column_index < size
          numerator = (
            pivot*work[row_index][column_index] -
            work[row_index][pivot_index]*
              work[pivot_index][column_index])
          work[row_index][column_index] = (
            pivot_index == 0 ?
            numerator : numerator / previous)
          column_index += 1
        work[row_index][pivot_index] = ring.zero
        row_index += 1
      previous = pivot
      pivot_index += 1
    result = work[size - 1][size - 1]
    sign < 0 ? -result : result

  # Exact bivariate resultant with respect to `variable`. The result is a
  # univariate polynomial in the remaining variable.
  -> bivariate_resultant(other, variable)
    other = coerce(other)
    if @ring.arity != 2
      raise "bivariate_resultant requires a two-variable ring"
    index = (
      variable.class_name == "Int" ?
      variable : @ring.index_of(variable))
    if index == nil || index < 0 || index >= 2
      raise "unknown bivariate resultant variable"
    left = coefficient_polynomials_in(index)
    right = other.coefficient_polynomials_in(index)
    m = degree_in(index)
    n = other.degree_in(index)
    coefficient_ring = left[0].ring
    return coefficient_ring.zero if zero? || other.zero?
    return left[0]**n if m == 0
    return right[0]**m if n == 0

    size = m + n
    matrix = []
    row_index = 0
    while row_index < size
      row = []
      size.times -> row.push(coefficient_ring.zero)
      matrix.push(row)
      row_index += 1
    row_index = 0
    while row_index < n
      coefficient_index = 0
      while coefficient_index <= m
        matrix[row_index][row_index + coefficient_index] = (
          left[m - coefficient_index])
        coefficient_index += 1
      row_index += 1
    row_index = 0
    while row_index < m
      coefficient_index = 0
      while coefficient_index <= n
        matrix[n + row_index][row_index + coefficient_index] = (
          right[n - coefficient_index])
        coefficient_index += 1
      row_index += 1
    Polynomial.polynomial_bareiss_determinant(
      matrix, coefficient_ring)

  -> resultant_in(other, variable)
    return resultant(other) if @ring.arity == 1
    bivariate_resultant(other, variable)
