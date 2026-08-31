# Exact linear algebra over F2 with replayable row-operation certificates.
#
# Descent computations eventually reduce global square classes, norm
# conditions, and local images to intersections of finite F2-vector spaces.
# Those finite calculations are small compared with the arithmetic that
# produces them, but they are also where an accidental rank or parity error
# would become a false Mordell--Weil bound.  This layer therefore returns the
# row operations, canonical RREF, particular solution, and kernel basis as a
# proof object that can be checked without trusting the reducer.

# Raw GF(2) word-slab kernels. Top-level `->` with typed signatures so the
# compiler lowers them to unboxed i64 loops (the class-method context keeps
# every slab access dynamically dispatched); `->` not `fn` because `fn` is
# memoized and these mutate their slab argument.
# Columns are packed 32 to an i64 slot (upper halves stay zero): every bit
# mask a DYNAMIC caller builds stays inside the small-integer range, so the
# pack loop can write straight into the slab without a typed-call boundary
# (measured: a typed-helper call from dynamic context costs ~1.2 us — the
# generic slow-call path — while a direct dynamic store into an i64[] is
# nanoseconds; packing through the helper was 318 of the 322 ms total).
-> f2_slab_bit(st, base, column) (i64[] i64 i64) i64
  (st[base + column / 32] >> (column % 32)) & 1

-> f2_slab_xor(st, target, source, words) (i64[] i64 i64 i64) i64
  w = 0 ## i64
  while w < words
    st[target + w] = st[target + w] ^ st[source + w]
    w += 1
  0

-> f2_slab_swap(st, a, b, words) (i64[] i64 i64 i64) i64
  w = 0 ## i64
  while w < words
    t = st[a + w] ## i64
    st[a + w] = st[b + w]
    st[b + w] = t
    w += 1
  0

-> f2_slab_zero?(st, base, words) (i64[] i64 i64) i64
  acc = 0 ## i64
  w = 0 ## i64
  while w < words
    acc = acc | st[base + w]
    w += 1
  acc == 0 ? 1 : 0

# Full elimination in one typed call: `vals` is the packed right-hand side
# (one bit per row), `pivots` and `ops` are output logs with their counts in
# slot 0 (`ops` records [kind, pivot, other] triples, kind 0 = swap and
# kind 1 = xor, in exactly the order the per-element loop emitted them).
-> f2_slab_reduce(st, height, width, words, vals, pivots, ops) (i64[] i64 i64 i64 i64[] i64[] i64[]) i64
  pivot_row = 0 ## i64
  column = 0 ## i64
  while column < width && pivot_row < height
    selected = pivot_row ## i64
    while selected < height && f2_slab_bit(st, selected * words, column) == 0
      selected += 1
    if selected < height
      if selected != pivot_row
        f2_slab_swap(st, pivot_row * words, selected * words, words)
        t = vals[pivot_row] ## i64
        vals[pivot_row] = vals[selected]
        vals[selected] = t
        n = ops[0] ## i64
        ops[n * 3 + 1] = 0
        ops[n * 3 + 2] = pivot_row
        ops[n * 3 + 3] = selected
        ops[0] = n + 1
      pivot_base = pivot_row * words ## i64
      row = 0 ## i64
      while row < height
        if row != pivot_row && f2_slab_bit(st, row * words, column) != 0
          f2_slab_xor(st, row * words, pivot_base, words)
          vals[row] = vals[row] ^ vals[pivot_row]
          n = ops[0] ## i64
          ops[n * 3 + 1] = 1
          ops[n * 3 + 2] = pivot_row
          ops[n * 3 + 3] = row
          ops[0] = n + 1
        row += 1
      p = pivots[0] ## i64
      pivots[p + 1] = column
      pivots[0] = p + 1
      pivot_row += 1
    column += 1
  pivot_row

+ F2LinearAlgebra
  -> .integer?(value)
    name = value.class_name
    name == "Integer" || name == "Int" || name == "BigInt"

  -> .bit?(value)
    F2LinearAlgebra.integer?(value) && (value == 0 || value == 1)

  -> .copy_vector(vector)
    out = []
    vector.each -> out.push(item)
    out

  -> .copy_matrix(matrix)
    out = []
    matrix.each -> out.push(F2LinearAlgebra.copy_vector(item))
    out

  -> .same_vector?(left, right)
    return false if left.size != right.size
    i = 0
    while i < left.size
      return false if left[i] != right[i]
      i += 1
    true

  -> .same_matrix?(left, right)
    return false if left.size != right.size
    i = 0
    while i < left.size
      return false if !F2LinearAlgebra.same_vector?(left[i], right[i])
      i += 1
    true

  -> .validate_vector(vector, width)
    raise "F2 vectors must be Arrays" if vector.class_name != "Array"
    raise "F2 vector width mismatch" if vector.size != width
    vector.each ->
      raise "F2 entries must be 0 or 1" if !F2LinearAlgebra.bit?(item)
    true

  -> .validate_system(width, matrix, right_hand_side)
    if !F2LinearAlgebra.integer?(width) || width < 0
      raise "F2 system width must be a nonnegative integer"
    if matrix.class_name != "Array" || right_hand_side.class_name != "Array"
      raise "F2 systems need an Array matrix and right-hand side"
    if matrix.size != right_hand_side.size
      raise "F2 system row count does not match its right-hand side"
    i = 0
    while i < matrix.size
      F2LinearAlgebra.validate_vector(matrix[i], width)
      if !F2LinearAlgebra.bit?(right_hand_side[i])
        raise "F2 right-hand sides must be 0 or 1"
      i += 1
    true

  -> .zero_vector?(vector)
    i = 0
    while i < vector.size
      return false if vector[i] != 0
      i += 1
    true

  -> .dot(left, right)
    raise "F2 dot-product width mismatch" if left.size != right.size
    result = 0
    i = 0
    while i < left.size
      result = result ^ (left[i] & right[i])
      i += 1
    result

  -> .satisfies?(matrix, right_hand_side, vector)
    return false if matrix.size != right_hand_side.size
    i = 0
    while i < matrix.size
      return false if F2LinearAlgebra.dot(matrix[i], vector) != right_hand_side[i]
      i += 1
    true

  # Return the leading-column list when matrix is in canonical RREF, nil
  # otherwise.  Zero rows must trail all nonzero rows and each pivot column
  # must be zero in every other row.
  -> .rref_pivots(matrix, width)
    pivots = []
    saw_zero = false
    previous = -1
    row = 0
    while row < matrix.size
      current = matrix[row]
      return nil if current.size != width
      column = 0
      while column < width && current[column] == 0
        column += 1
      if column == width
        saw_zero = true
      else
        return nil if saw_zero || column <= previous
        check = 0
        while check < matrix.size
          if check != row && matrix[check][column] != 0
            return nil
          check += 1
        pivots.push(column)
        previous = column
      row += 1
    pivots

  # Gaussian elimination on rows packed 64 columns to an i64 word (one flat
  # typed slab, metaflip-style): a row operation is `width/64` raw in-place
  # XORs instead of `width` boxed array reads, XORs, and writes, and no
  # per-operation values are allocated. Packing happens on entry and rows
  # unpack only at the API boundary, so every output — rref, operations,
  # pivots, particular, kernel basis — is identical to the per-element form.
  -> .reduce(width, matrix, right_hand_side)
    F2LinearAlgebra.validate_system(width, matrix, right_hand_side)
    height = matrix.size
    words = (width + 31) / 32
    st = i64[height * words]
    row = 0
    while row < height
      source = matrix[row]
      base = row * words
      column = 0
      while column < width
        if source[column] != 0
          slot = base + column / 32
          st[slot] = st[slot] | (1 << (column % 32))
        column += 1
      row += 1
    max_rank = height < width ? height : width
    vals = i64[height < 1 ? 1 : height]
    row = 0
    while row < height
      vals[row] = right_hand_side[row]
      row += 1
    pivot_log = i64[max_rank + 1]
    op_log = i64[height * max_rank * 3 + 1]
    f2_slab_reduce(st, height, width, words, vals, pivot_log, op_log)
    values = []
    row = 0
    while row < height
      values.push(vals[row])
      row += 1
    operations = []
    n = op_log[0]
    i = 0
    while i < n
      operations.push([op_log[i * 3 + 1], op_log[i * 3 + 2], op_log[i * 3 + 3]])
      i += 1
    pivots = []
    n = pivot_log[0]
    i = 0
    while i < n
      pivots.push(pivot_log[i + 1])
      i += 1

    inconsistent = false
    row = 0
    while row < height
      if f2_slab_zero?(st, row * words, words) == 1 && values[row] == 1
        inconsistent = true
      row += 1

    particular = []
    width.times -> particular.push(0)
    basis = []
    if !inconsistent
      row = 0
      while row < pivots.size
        particular[pivots[row]] = values[row]
        row += 1

      free_column = 0
      while free_column < width
        if !pivots.include?(free_column)
          vector = []
          width.times -> vector.push(0)
          vector[free_column] = 1
          row = 0
          while row < pivots.size
            vector[pivots[row]] = f2_slab_bit(st, row * words, free_column)
            row += 1
          basis.push(vector)
        free_column += 1

    unpacked = []
    row = 0
    while row < height
      base = row * words
      out = []
      column = 0
      while column < width
        out.push(f2_slab_bit(st, base, column))
        column += 1
      unpacked.push(out)
      row += 1

    {
      "rref": unpacked,
      "right_hand_side": values,
      "operations": operations,
      "pivots": pivots,
      "inconsistent": inconsistent,
      "particular": particular,
      "kernel_basis": basis
    }


+ F2LinearSystemCertificate
  -> new(@width, matrix, right_hand_side, reduction)
    @matrix = F2LinearAlgebra.copy_matrix(matrix)
    @source_right_hand_side = F2LinearAlgebra.copy_vector(right_hand_side)
    @rref = F2LinearAlgebra.copy_matrix(reduction["rref"])
    @reduced_right_hand_side = F2LinearAlgebra.copy_vector(
      reduction["right_hand_side"])
    @operations = F2LinearAlgebra.copy_matrix(reduction["operations"])
    @pivots = F2LinearAlgebra.copy_vector(reduction["pivots"])
    @inconsistent = reduction["inconsistent"]
    @particular = F2LinearAlgebra.copy_vector(reduction["particular"])
    @kernel_basis = F2LinearAlgebra.copy_matrix(reduction["kernel_basis"])

  -> width
    @width

  -> matrix
    F2LinearAlgebra.copy_matrix(@matrix)

  -> source_right_hand_side
    F2LinearAlgebra.copy_vector(@source_right_hand_side)

  -> rref
    F2LinearAlgebra.copy_matrix(@rref)

  -> reduced_right_hand_side
    F2LinearAlgebra.copy_vector(@reduced_right_hand_side)

  -> operations
    F2LinearAlgebra.copy_matrix(@operations)

  -> pivots
    F2LinearAlgebra.copy_vector(@pivots)

  -> inconsistent?
    @inconsistent

  -> consistent?
    !@inconsistent

  -> rank
    @pivots.size

  -> kernel_dimension
    @inconsistent ? -1 : @width - self.rank

  -> particular_solution
    raise "inconsistent F2 system has no particular solution" if @inconsistent
    F2LinearAlgebra.copy_vector(@particular)

  -> kernel_basis
    F2LinearAlgebra.copy_matrix(@kernel_basis)

  -> replay
    work = F2LinearAlgebra.copy_matrix(@matrix)
    values = F2LinearAlgebra.copy_vector(@source_right_hand_side)
    @operations.each -> (operation)
      if operation.class_name != "Array" || operation.size != 3
        raise "malformed F2 row operation"
      kind = operation[0]
      left = operation[1]
      right = operation[2]
      invalid_index = !F2LinearAlgebra.integer?(left)
      invalid_index = true if !F2LinearAlgebra.integer?(right)
      invalid_index = true if left < 0 || right < 0
      invalid_index = true if left >= work.size || right >= work.size
      invalid_index = true if left == right
      if invalid_index
        raise "F2 row operation index is invalid"
      if kind == 0
        temporary = work[left]
        work[left] = work[right]
        work[right] = temporary
        value = values[left]
        values[left] = values[right]
        values[right] = value
      elsif kind == 1
        cell = 0
        while cell < @width
          work[right][cell] = work[right][cell] ^ work[left][cell]
          cell += 1
        values[right] = values[right] ^ values[left]
      else
        raise "unknown F2 row operation"
    [work, values]

  # Verification deliberately replays only elementary invertible row
  # operations and derives every dimension claim from the checked RREF.
  -> verified?
    answer = false
    begin
      answer = self.verify_reduction
    rescue e
      answer = false
    answer

  -> verify_reduction
    F2LinearAlgebra.validate_system(
      @width, @matrix, @source_right_hand_side)
    F2LinearAlgebra.validate_system(
      @width, @rref, @reduced_right_hand_side)

    replayed = self.replay
    return false if !F2LinearAlgebra.same_matrix?(replayed[0], @rref)
    return false if !F2LinearAlgebra.same_vector?(
      replayed[1], @reduced_right_hand_side)

    canonical_pivots = F2LinearAlgebra.rref_pivots(@rref, @width)
    return false if canonical_pivots == nil
    return false if !F2LinearAlgebra.same_vector?(
      canonical_pivots, @pivots)

    found_inconsistent = false
    row = 0
    while row < @rref.size
      zero_contradiction = F2LinearAlgebra.zero_vector?(@rref[row])
      zero_contradiction = false if @reduced_right_hand_side[row] != 1
      if zero_contradiction
        found_inconsistent = true
      row += 1
    return false if found_inconsistent != @inconsistent

    if @inconsistent
      return false if @kernel_basis.size != 0
      return true

    return false if @particular.size != @width
    F2LinearAlgebra.validate_vector(@particular, @width)
    return false if !F2LinearAlgebra.satisfies?(
      @matrix, @source_right_hand_side, @particular)
    return false if @kernel_basis.size != @width - @pivots.size

    free_columns = []
    column = 0
    while column < @width
      free_columns.push(column) if !@pivots.include?(column)
      column += 1
    basis_index = 0
    while basis_index < @kernel_basis.size
      vector = @kernel_basis[basis_index]
      F2LinearAlgebra.validate_vector(vector, @width)
      zeros = []
      @matrix.size.times -> zeros.push(0)
      return false if !F2LinearAlgebra.satisfies?(
        @matrix, zeros, vector)
      free_index = 0
      while free_index < free_columns.size
        expected = free_index == basis_index ? 1 : 0
        return false if vector[free_columns[free_index]] != expected
        free_index += 1
      basis_index += 1
    true

  -> certified?
    self.verified?

  -> to_s
    state = @inconsistent ? "inconsistent" : ("kernel dimension " + self.kernel_dimension.to_s)
    "F2LinearSystemCertificate(" + state + ")"

  -> inspect
    to_s


+ F2LinearSolution
  -> new(@certificate)
    if @certificate.class_name != "F2LinearSystemCertificate"
      raise "F2 solutions need an F2LinearSystemCertificate"
    raise "F2 solution needs a verified row-reduction certificate" if !@certificate.verified?

  -> certificate
    @certificate

  -> certified?
    @certificate.certified?

  -> consistent?
    @certificate.consistent?

  -> inconsistent?
    @certificate.inconsistent?

  -> rank
    @certificate.rank

  -> dimension
    @certificate.kernel_dimension

  -> kernel_dimension
    self.dimension

  -> basis
    @certificate.kernel_basis

  -> particular_solution
    @certificate.particular_solution

  -> contains?(vector)
    return false if self.inconsistent?
    F2LinearAlgebra.validate_vector(vector, @certificate.width)
    F2LinearAlgebra.satisfies?(
      @certificate.matrix,
      @certificate.source_right_hand_side,
      vector)

  -> to_s
    return "EmptyF2AffineSpace" if self.inconsistent?
    "F2AffineSpace(dim=" + self.dimension.to_s + ")"

  -> inspect
    self.to_s


+ F2LinearSystem
  -> new(@width)
    if !F2LinearAlgebra.integer?(@width) || @width < 0
      raise "F2 system width must be a nonnegative integer"
    @matrix = []
    @right_hand_side = []
    @labels = []

  -> width
    @width

  -> row_count
    @matrix.size

  -> matrix
    F2LinearAlgebra.copy_matrix(@matrix)

  -> right_hand_side
    F2LinearAlgebra.copy_vector(@right_hand_side)

  -> labels
    F2LinearAlgebra.copy_vector(@labels)

  -> add_equation(coefficients, value = 0, label = nil)
    F2LinearAlgebra.validate_vector(coefficients, @width)
    raise "F2 right-hand sides must be 0 or 1" if !F2LinearAlgebra.bit?(value)
    @matrix.push(F2LinearAlgebra.copy_vector(coefficients))
    @right_hand_side.push(value)
    @labels.push(label == nil ? nil : label.to_s)
    self

  -> add_equations(matrix, right_hand_side, labels = nil)
    F2LinearAlgebra.validate_system(@width, matrix, right_hand_side)
    bad_labels = labels != nil && labels.class_name != "Array"
    bad_labels = true if labels != nil && labels.size != matrix.size
    if bad_labels
      raise "F2 equation labels must match the row count"
    i = 0
    while i < matrix.size
      label = labels == nil ? nil : labels[i]
      add_equation(matrix[i], right_hand_side[i], label)
      i += 1
    self

  -> certificate
    reduction = F2LinearAlgebra.reduce(
      @width, @matrix, @right_hand_side)
    F2LinearSystemCertificate.new(
      @width, @matrix, @right_hand_side, reduction)

  -> solve
    F2LinearSolution.new(certificate)

  -> consistent?
    solve.consistent?

  -> inconsistent?
    !consistent?

  -> rank
    solve.rank

  -> dimension
    solve.dimension

  -> kernel_basis
    solve.basis

  -> to_s
    "F2LinearSystem(" + row_count.to_s + "x" + @width.to_s + ")"

  -> inspect
    to_s
