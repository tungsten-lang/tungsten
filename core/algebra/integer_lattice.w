# Exact rational lattices and linear algebra over prime fields.
#
# Algebra orders use column bases in a fixed ambient power basis. The helpers
# here deliberately stay small and exact: rational Gaussian elimination for
# coordinate changes, and canonical RREF kernels over F_p for Round 2
# maximal-order computations.

+ ExactRationalLinearAlgebra
  -> .identity(size)
    rows = []
    i = 0
    while i < size
      row = []
      j = 0
      while j < size
        row.push(Rational.new(i == j ? 1 : 0))
        j += 1
      rows.push(row)
      i += 1
    rows

  -> .matrix_from_columns(columns)
    if columns.class_name != "Array" || columns.size == 0
      raise "matrix needs at least one column"
    row_count = columns[0].size
    rows = []
    i = 0
    while i < row_count
      row = []
      j = 0
      while j < columns.size
        if columns[j].class_name != "Array"
          raise "matrix columns must be arrays"
        if columns[j].size != row_count
          raise "matrix columns have inconsistent sizes"
        row.push(Rational.coerce(columns[j][i]))
        j += 1
      rows.push(row)
      i += 1
    rows

  -> .columns_from_matrix(matrix)
    if matrix.class_name != "Array" || matrix.size == 0
      raise "matrix needs at least one row"
    column_count = matrix[0].size
    columns = []
    j = 0
    while j < column_count
      column = []
      i = 0
      while i < matrix.size
        if matrix[i].size != column_count
          raise "matrix rows have inconsistent sizes"
        column.push(Rational.coerce(matrix[i][j]))
        i += 1
      columns.push(column)
      j += 1
    columns

  -> .inverse(matrix)
    if matrix.class_name != "Array" || matrix.size == 0
      raise "inverse needs a nonempty square matrix"
    size = matrix.size
    augmented = []
    i = 0
    while i < size
      if matrix[i].class_name != "Array" || matrix[i].size != size
        raise "inverse needs a square matrix"
      row = []
      j = 0
      while j < size
        row.push(Rational.coerce(matrix[i][j]))
        j += 1
      j = 0
      while j < size
        row.push(Rational.new(i == j ? 1 : 0))
        j += 1
      augmented.push(row)
      i += 1

    column = 0
    while column < size
      pivot = column
      while pivot < size && augmented[pivot][column].zero?
        pivot += 1
      raise "singular rational matrix" if pivot == size
      if pivot != column
        temporary = augmented[column]
        augmented[column] = augmented[pivot]
        augmented[pivot] = temporary

      pivot_value = augmented[column][column]
      cell = 0
      while cell < size * 2
        augmented[column][cell] = augmented[column][cell] / pivot_value
        cell += 1

      row = 0
      while row < size
        if row != column && !augmented[row][column].zero?
          scale = augmented[row][column]
          cell = 0
          while cell < size * 2
            value = augmented[row][cell]
            augmented[row][cell] = value - scale * augmented[column][cell]
            cell += 1
        row += 1
      column += 1

    inverse = []
    i = 0
    while i < size
      row = []
      j = 0
      while j < size
        row.push(augmented[i][size + j])
        j += 1
      inverse.push(row)
      i += 1
    inverse

  -> .matrix_vector(matrix, vector)
    if matrix.class_name != "Array"
      raise "matrix-vector product needs a matrix"
    result = []
    i = 0
    while i < matrix.size
      if matrix[i].size != vector.size
        raise "matrix-vector dimensions do not match"
      value = Rational.new(0)
      j = 0
      while j < vector.size
        value += Rational.coerce(matrix[i][j]) * Rational.coerce(vector[j])
        j += 1
      result.push(value)
      i += 1
    result

  -> .compose_columns(base_columns, relative_columns)
    base_matrix = ExactRationalLinearAlgebra.matrix_from_columns(
      base_columns)
    out = []
    relative_columns.each -> (relative)
      out.push(ExactRationalLinearAlgebra.matrix_vector(
        base_matrix, relative))
    out

  -> .same_vector?(left, right)
    return false if left.size != right.size
    i = 0
    while i < left.size
      return false if Rational.coerce(left[i]) != Rational.coerce(right[i])
      i += 1
    true


+ PrimeLinearAlgebra
  -> .normalize(value, prime)
    reduced = value % prime
    reduced += prime if reduced < 0
    reduced

  -> .inverse(value, prime)
    a = PrimeLinearAlgebra.normalize(value, prime)
    raise "zero has no inverse modulo p" if a == 0
    old_r = prime
    r = a
    old_t = 0
    t = 1
    while r != 0
      quotient = old_r / r
      next_r = old_r - quotient * r
      old_r = r
      r = next_r
      next_t = old_t - quotient * t
      old_t = t
      t = next_t
    if old_r != 1
      raise "modular inverse needs a prime modulus"
    PrimeLinearAlgebra.normalize(old_t, prime)

  # Returns [canonical_rref, pivot_columns].
  -> .rref(matrix, prime, column_count = nil)
    if prime < 2 || !prime.prime?
      raise "prime-field RREF needs a prime modulus"
    if matrix.class_name != "Array"
      raise "prime-field RREF needs a matrix"
    if matrix.size == 0
      count = column_count == nil ? 0 : column_count
      return [[], []] if count >= 0
    count = matrix[0].size
    rows = []
    matrix.each -> (source)
      if source.class_name != "Array" || source.size != count
        raise "prime-field matrix rows have inconsistent sizes"
      row = []
      source.each -> (entry)
        row.push(PrimeLinearAlgebra.normalize(entry, prime))
      rows.push(row)

    pivots = []
    pivot_row = 0
    column = 0
    while column < count && pivot_row < rows.size
      selected = pivot_row
      while selected < rows.size && rows[selected][column] == 0
        selected += 1
      if selected < rows.size
        if selected != pivot_row
          temporary = rows[pivot_row]
          rows[pivot_row] = rows[selected]
          rows[selected] = temporary
        inverse = PrimeLinearAlgebra.inverse(
          rows[pivot_row][column], prime)
        cell = 0
        while cell < count
          rows[pivot_row][cell] = PrimeLinearAlgebra.normalize(
            rows[pivot_row][cell] * inverse, prime)
          cell += 1
        row = 0
        while row < rows.size
          if row != pivot_row && rows[row][column] != 0
            scale = rows[row][column]
            cell = 0
            while cell < count
              rows[row][cell] = PrimeLinearAlgebra.normalize(
                rows[row][cell] - scale * rows[pivot_row][cell],
                prime)
              cell += 1
          row += 1
        pivots.push(column)
        pivot_row += 1
      column += 1
    [rows, pivots]

  # Returns [kernel_basis_rows, pivot_columns, free_columns].
  -> .kernel_data(matrix, prime, column_count = nil)
    reduced = PrimeLinearAlgebra.rref(
      matrix, prime, column_count)
    rows = reduced[0]
    pivots = reduced[1]
    count = column_count
    if count == nil
      count = matrix.size == 0 ? 0 : matrix[0].size
    free = []
    column = 0
    while column < count
      free.push(column) if !pivots.include?(column)
      column += 1

    basis = []
    free.each -> (free_column)
      vector = []
      i = 0
      while i < count
        vector.push(0)
        i += 1
      vector[free_column] = 1
      row = 0
      while row < pivots.size
        vector[pivots[row]] = PrimeLinearAlgebra.normalize(
          0 - rows[row][free_column], prime)
        row += 1
      basis.push(vector)
    [basis, pivots, free]

  -> .kernel(matrix, prime, column_count = nil)
    PrimeLinearAlgebra.kernel_data(
      matrix, prime, column_count)[0]


+ AlgebraOrderLattice
  -> new(@algebra, basis_vectors)
    if @algebra.class_name != "EtaleAlgebra"
      raise "order lattice needs an EtaleAlgebra"
    if @algebra.base_field.class_name != "RationalField"
      raise "order lattices are currently implemented over Q"
    @rank = @algebra.dimension
    invalid_basis = basis_vectors.class_name != "Array"
    invalid_basis = true if !invalid_basis && basis_vectors.size != @rank
    if invalid_basis
      raise "order lattice needs rank-many basis vectors"
    @basis_vectors = []
    basis_vectors.each -> (source)
      if source.class_name != "Array" || source.size != @rank
        raise "order lattice basis vector has the wrong dimension"
      vector = []
      source.each -> (entry)
        vector.push(Rational.coerce(entry))
      @basis_vectors.push(vector)
    @basis_matrix = ExactRationalLinearAlgebra.matrix_from_columns(
      @basis_vectors)
    @basis_inverse = ExactRationalLinearAlgebra.inverse(@basis_matrix)
    @determinant = nil

  -> algebra
    @algebra

  -> rank
    @rank

  -> basis_vectors
    out = []
    @basis_vectors.each -> (source)
      vector = []
      source.each -> (entry)
        vector.push(entry)
      out.push(vector)
    out

  -> coordinates(vector)
    ExactRationalLinearAlgebra.matrix_vector(
      @basis_inverse, vector)

  -> ambient_vector(coordinates)
    ExactRationalLinearAlgebra.matrix_vector(
      @basis_matrix, coordinates)

  -> contains_vector?(vector)
    values = coordinates(vector)
    i = 0
    while i < values.size
      return false if values[i].denominator != 1
      i += 1
    true

  -> contains_lattice?(other)
    return false if other.class_name != "AlgebraOrderLattice"
    return false if other.algebra != @algebra
    vectors = other.basis_vectors
    i = 0
    while i < vectors.size
      return false if !contains_vector?(vectors[i])
      i += 1
    true

  -> same_lattice?(other)
    contains_lattice?(other) && other.contains_lattice?(self)

  -> determinant
    if @determinant == nil
      @determinant = Algebra.determinant(
        @basis_matrix, RationalField.new)
    @determinant

  # self is the larger lattice. Return [self : sublattice].
  -> index_from(sublattice)
    if !contains_lattice?(sublattice)
      raise "index needs a contained sublattice"
    quotient = (sublattice.determinant / determinant).abs
    if quotient.denominator != 1
      raise "lattice index is not integral"
    quotient.numerator

  -> compose(relative_basis)
    AlgebraOrderLattice.new(
      @algebra,
      ExactRationalLinearAlgebra.compose_columns(
        @basis_vectors, relative_basis))
