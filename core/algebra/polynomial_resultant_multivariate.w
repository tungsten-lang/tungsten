# Exact resultants and discriminants with respect to one variable, in any
# arity. The Sylvester matrix with respect to `variable` has entries that are
# polynomials of the same ring in the remaining variables; its determinant is
# computed fraction-free (Bareiss), so every intermediate division is an exact
# polynomial division. Reopens Polynomial; load after polynomial_resultant.w
# and polynomial_gcd.w (uses coefficient_in).

+ Polynomial
  -> variable_index_of(variable)
    index = variable.class_name == "Int" ? variable : @ring.index_of(variable)
    if index == nil || index < 0 || index >= @ring.arity
      raise "unknown polynomial variable"
    index

  -> derivative_in(variable)
    derivative(variable_index_of(variable))

  # Coefficients with respect to `variable`, as polynomials of the same ring
  # not involving `variable`, indexed by exponent 0..bound. Missing high
  # coefficients are zero, so a formal degree above the actual one is allowed.
  -> coefficient_list_in(variable, bound = nil)
    index = variable_index_of(variable)
    top = bound == nil ? degree_in(index) : bound
    out = []
    exponent = 0
    while exponent <= top
      out.push(coefficient_in(index, exponent))
      exponent += 1
    out

  # Determinant of the Sylvester matrix of (self, other) with respect to
  # `variable`, using the formal degrees m and n (actual degrees may be lower;
  # then the top coefficients are zero, which is what the discriminant
  # convention in characteristic p needs).
  -> sylvester_resultant_in(other, variable, m, n)
    index = variable_index_of(variable)
    left = coefficient_list_in(index, m)
    right = other.coefficient_list_in(index, n)
    size = m + n
    return @ring.one if size == 0
    matrix = []
    row_index = 0
    while row_index < size
      row = []
      size.times -> row.push(@ring.zero)
      matrix.push(row)
      row_index += 1
    row_index = 0
    while row_index < n
      coefficient_index = 0
      while coefficient_index <= m
        matrix[row_index][row_index + coefficient_index] = left[m - coefficient_index]
        coefficient_index += 1
      row_index += 1
    row_index = 0
    while row_index < m
      coefficient_index = 0
      while coefficient_index <= n
        matrix[n + row_index][row_index + coefficient_index] = right[n - coefficient_index]
        coefficient_index += 1
      row_index += 1
    Polynomial.polynomial_bareiss_determinant(matrix, @ring)

  # Resultant with respect to `variable` for any arity. The result lives in
  # the same ring and does not involve `variable`. Univariate rings keep the
  # field-valued `resultant`; two-variable rings agree with
  # `bivariate_resultant` up to the ring the answer is stated in.
  -> resultant_in(other, variable)
    other = coerce(other)
    return resultant(other) if @ring.arity == 1
    index = variable_index_of(variable)
    return @ring.zero if zero? || other.zero?
    m = degree_in(index)
    n = other.degree_in(index)
    return coefficient_in(index, 0)**n if m == 0
    return other.coefficient_in(index, 0)**m if n == 0
    sylvester_resultant_in(other, index, m, n)

  # Discriminant with respect to `variable`:
  # (-1)^(n(n-1)/2) * Res(f, f') / lc(f), with f' taken at formal degree n-1.
  -> discriminant_in(variable)
    return discriminant if @ring.arity == 1
    index = variable_index_of(variable)
    n = degree_in(index)
    return @ring.one if n <= 1
    sign = ((n * (n - 1) / 2).odd?) ? -1 : 1
    derived = derivative(index)
    return @ring.zero if derived.zero?
    resultant_value = sylvester_resultant_in(derived, index, n, n - 1)
    quotient = resultant_value / coefficient_in(index, n)
    sign < 0 ? -quotient : quotient
