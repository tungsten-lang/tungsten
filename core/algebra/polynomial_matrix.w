# Polynomial matrices over a univariate polynomial ring F[z].
#
# Row degrees, the leading row coefficient matrix, row reduction by
# Mulders–Storjohann simple transformations (with the unimodular transform),
# and minimal kernel bases computed from an iterative order basis
# (Beckermann–Labahn M-basis, column-by-column pivoting on the residual).
# Reopens nothing; load after polynomial.w.

+ PolynomialMatrix
  -> new(@ring, entries)
    if @ring.class_name != "PolynomialRing" || @ring.arity != 1
      raise "polynomial matrix requires a univariate PolynomialRing"
    @entries = []
    entries.each -> (row)
      out = []
      row.each -> (value)
        out.push(value.class_name == "Polynomial" ? value : @ring.constant(value))
      @entries.push(out)
    @rows = @entries.size
    @cols = @rows == 0 ? 0 : @entries[0].size
    @entries.each -> (row)
      raise "ragged polynomial matrix" if row.size != @cols

  ro :ring, :rows, :cols, :entries

  -> .identity(ring, size)
    entries = []
    i = 0
    while i < size
      row = []
      j = 0
      while j < size
        row.push(i == j ? ring.one : ring.zero)
        j += 1
      entries.push(row)
      i += 1
    PolynomialMatrix.new(ring, entries)

  -> field
    @ring.field

  -> entry(i, j)
    @entries[i][j]

  -> row(i)
    out = []
    @entries[i].each -> (value)
      out.push(value)
    out

  -> copy_entries
    out = []
    @entries.each -> (row)
      copy = []
      row.each -> (value)
        copy.push(value)
      out.push(copy)
    out

  -> z_power(exponent)
    @ring.monomial(field.one, [exponent])

  -> transpose
    entries = []
    j = 0
    while j < @cols
      row = []
      i = 0
      while i < @rows
        row.push(@entries[i][j])
        i += 1
      entries.push(row)
      j += 1
    PolynomialMatrix.new(@ring, entries)

  -> multiply(other)
    raise "polynomial matrix dimension mismatch" if other.rows != @cols
    entries = []
    i = 0
    while i < @rows
      row = []
      j = 0
      while j < other.cols
        acc = @ring.zero
        k = 0
        while k < @cols
          acc = acc + @entries[i][k] * other.entry(k, j)
          k += 1
        row.push(acc)
        j += 1
      entries.push(row)
      i += 1
    PolynomialMatrix.new(@ring, entries)

  -> *(other)
    multiply(other)

  # Apply the matrix to a column vector given as an array of polynomials.
  -> apply(vector)
    raise "polynomial matrix dimension mismatch" if vector.size != @cols
    out = []
    i = 0
    while i < @rows
      acc = @ring.zero
      j = 0
      while j < @cols
        acc = acc + @entries[i][j] * vector[j]
        j += 1
      out.push(acc)
      i += 1
    out

  -> max_degree
    result = -1
    @entries.each -> (row)
      row.each -> (value)
        d = value.degree
        result = d if d > result
    result

  -> row_degree(i)
    result = -1
    @entries[i].each -> (value)
      d = value.degree
      result = d if d > result
    result

  -> row_degrees
    out = []
    i = 0
    while i < @rows
      out.push(row_degree(i))
      i += 1
    out

  # Row i of the leading row coefficient matrix: the coefficients of
  # z^(row degree) in row i. A zero row contributes a zero row.
  -> leading_row_coefficient_matrix
    out = []
    i = 0
    while i < @rows
      d = row_degree(i)
      row = []
      j = 0
      while j < @cols
        row.push(d < 0 ? field.zero : @entries[i][j].coeff([d]))
        j += 1
      out.push(row)
      i += 1
    out

  -> row_reduced?
    i = 0
    while i < @rows
      return false if row_degree(i) < 0
      i += 1
    field_rank(leading_row_coefficient_matrix, @cols) == @rows

  # --- exact linear algebra over the coefficient field ---

  # Reduced row echelon form. Returns [matrix, pivot_columns].
  -> field_echelon(matrix, ncols)
    f = field
    a = []
    matrix.each -> (row)
      copy = []
      row.each -> (value)
        copy.push(value)
      a.push(copy)
    m = a.size
    pivots = []
    row = 0
    col = 0
    while row < m && col < ncols
      pivot = -1
      r = row
      while r < m
        if !f.zero?(a[r][col])
          pivot = r
          break
        r += 1
      if pivot >= 0
        swap = a[row]
        a[row] = a[pivot]
        a[pivot] = swap
        inv = f.inverse(a[row][col])
        j = 0
        while j < ncols
          a[row][j] = f.multiply(a[row][j], inv)
          j += 1
        r = 0
        while r < m
          if r != row
            factor = a[r][col]
            if !f.zero?(factor)
              j = 0
              while j < ncols
                a[r][j] = f.subtract(a[r][j], f.multiply(factor, a[row][j]))
                j += 1
          r += 1
        pivots.push(col)
        row += 1
      col += 1
    [a, pivots]

  -> field_rank(matrix, ncols)
    field_echelon(matrix, ncols)[1].size

  # Basis of { x : matrix * x = 0 } as arrays of field elements.
  -> field_nullspace(matrix, ncols)
    f = field
    echelon = field_echelon(matrix, ncols)
    a = echelon[0]
    pivots = echelon[1]
    out = []
    col = 0
    while col < ncols
      free = true
      pivots.each -> (p)
        free = false if p == col
      if free
        x = []
        j = 0
        while j < ncols
          x.push(f.zero)
          j += 1
        x[col] = f.one
        i = 0
        while i < pivots.size
          x[pivots[i]] = f.negate(a[i][col])
          i += 1
        out.push(x)
      col += 1
    out

  # Left kernel of a field matrix: vectors c with c * matrix = 0.
  -> field_left_kernel(matrix, nrows, ncols)
    transposed = []
    j = 0
    while j < ncols
      row = []
      i = 0
      while i < nrows
        row.push(matrix[i][j])
        i += 1
      transposed.push(row)
      j += 1
    field_nullspace(transposed, nrows)

  # --- row reduction ---

  # Row reduction by simple transformations. Returns [reduced, transform]
  # where reduced = transform * self restricted to the surviving rows; the
  # transform rows are the F[z]-combinations expressing each surviving row.
  -> row_reduce_with_transform
    f = field
    work = copy_entries
    transform = PolynomialMatrix.identity(@ring, @rows).copy_entries
    alive = []
    i = 0
    while i < @rows
      alive.push(i) if row_degree(i) >= 0
      i += 1
    steps = 0
    while true
      raise "polynomial matrix row reduction limit exceeded" if steps > 1_000_000
      steps += 1
      degrees = []
      leading = []
      alive.each -> (r)
        d = -1
        work[r].each -> (value)
          dv = value.degree
          d = dv if dv > d
        degrees.push(d)
        row = []
        work[r].each -> (value)
          row.push(value.coeff([d]))
        leading.push(row)
      kernel = field_left_kernel(leading, alive.size, @cols)
      break if kernel.size == 0
      c = kernel[0]
      k = -1
      idx = 0
      while idx < alive.size
        if !f.zero?(c[idx])
          k = idx if k < 0 || degrees[idx] > degrees[k]
        idx += 1
      target = alive[k]
      new_row = []
      new_transform = []
      j = 0
      while j < @cols
        new_row.push(@ring.zero)
        j += 1
      j = 0
      while j < @rows
        new_transform.push(@ring.zero)
        j += 1
      idx = 0
      while idx < alive.size
        if !f.zero?(c[idx])
          shift = z_power(degrees[k] - degrees[idx]) * c[idx]
          source = alive[idx]
          j = 0
          while j < @cols
            new_row[j] = new_row[j] + work[source][j] * shift
            j += 1
          j = 0
          while j < @rows
            new_transform[j] = new_transform[j] + transform[source][j] * shift
            j += 1
        idx += 1
      work[target] = new_row
      transform[target] = new_transform
      still_alive = []
      alive.each -> (r)
        nonzero = false
        work[r].each -> (value)
          nonzero = true if !value.zero?
        still_alive.push(r) if nonzero
      alive = still_alive
    reduced_entries = []
    transform_entries = []
    alive.each -> (r)
      reduced_entries.push(work[r])
      transform_entries.push(transform[r])
    [PolynomialMatrix.new(@ring, reduced_entries),
     PolynomialMatrix.new(@ring, transform_entries)]

  -> row_reduce
    row_reduce_with_transform[0]

  # Determinant by cofactor expansion (intended for small unimodularity
  # checks, not for large matrices).
  -> determinant
    raise "determinant needs a square polynomial matrix" if @rows != @cols
    determinant_of(@entries, @rows)

  -> determinant_of(entries, size)
    return @ring.one if size == 0
    return entries[0][0] if size == 1
    acc = @ring.zero
    j = 0
    while j < size
      minor = []
      i = 1
      while i < size
        row = []
        k = 0
        while k < size
          row.push(entries[i][k]) if k != j
          k += 1
        minor.push(row)
        i += 1
      term = entries[0][j] * determinant_of(minor, size - 1)
      acc = j % 2 == 0 ? acc + term : acc - term
      j += 1
    acc

  # --- order bases and kernels ---

  # Minimal approximant (order) basis for the rows of `self` viewed as the
  # matrix G: returns [p, residual, degrees] with p a square matrix over
  # F[z] whose rows form a basis of { v : v * G ≡ 0 mod z^order }, and
  # residual = p * G.
  -> order_basis(order)
    f = field
    n = @rows
    p = PolynomialMatrix.identity(@ring, n).copy_entries
    pg = copy_entries
    degrees = []
    i = 0
    while i < n
      degrees.push(0)
      i += 1
    sigma = 0
    while sigma < order
      j = 0
      while j < @cols
        pivot = -1
        i = 0
        while i < n
          if !f.zero?(pg[i][j].coeff([sigma]))
            pivot = i if pivot < 0 || degrees[i] < degrees[pivot]
          i += 1
        if pivot >= 0
          inv = f.inverse(pg[pivot][j].coeff([sigma]))
          i = 0
          while i < n
            if i != pivot
              ci = pg[i][j].coeff([sigma])
              if !f.zero?(ci)
                factor = f.multiply(ci, inv)
                k = 0
                while k < n
                  p[i][k] = p[i][k] - p[pivot][k] * factor
                  k += 1
                k = 0
                while k < @cols
                  pg[i][k] = pg[i][k] - pg[pivot][k] * factor
                  k += 1
            i += 1
          shift = z_power(1)
          k = 0
          while k < n
            p[pivot][k] = p[pivot][k] * shift
            k += 1
          k = 0
          while k < @cols
            pg[pivot][k] = pg[pivot][k] * shift
            k += 1
          degrees[pivot] += 1
        j += 1
      sigma += 1
    [PolynomialMatrix.new(@ring, p), PolynomialMatrix.new(@ring, pg), degrees]

  # Minimal (row-reduced) basis of the kernel { v : self * v = 0 } restricted
  # to vectors of degree at most `degree_bound`. Returns [vectors, degrees]
  # where each vector is an array of `cols` polynomials.
  -> minimal_kernel_basis(degree_bound)
    raise "degree bound must be nonnegative" if degree_bound < 0
    g = transpose
    order = degree_bound + max_degree + 1
    order = 1 if order < 1
    result = g.order_basis(order)
    p = result[0]
    residual = result[1]
    vectors = []
    degrees = []
    i = 0
    while i < p.rows
      d = p.row_degree(i)
      if d >= 0 && d <= degree_bound
        exact = true
        residual.row(i).each -> (value)
          exact = false if !value.zero?
        if exact
          vectors.push(p.row(i))
          degrees.push(d)
      i += 1
    [vectors, degrees]

  -> to_s
    lines = []
    @entries.each -> (row)
      parts = []
      row.each -> (value)
        parts.push(value.to_s)
      lines.push("[" + parts.join(", ") + "]")
    "[" + lines.join(", ") + "]"

  -> inspect
    to_s
