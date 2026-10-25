# Matrix — a plain dense 2-D matrix stored as nested row arrays
# (pure Tungsten, CPU-only; friendly data structure, not a BLAS)
#
#     m = Matrix.new([[1, 2], [3, 4]])
#     m.matmul(Matrix.identity(2))     # => m
#     m.transpose.to_a                 # => [[1, 3], [2, 4]]
#
# The first row fixes the width: longer rows are truncated, shorter
# rows are padded with nil, so a Matrix is always rectangular.
#
# Shape rule: every op with a shape requirement returns nil when it is
# not met (add/sub/mul on mismatched shapes, matmul on misaligned
# inner dims, trace/det/inv on non-square, row/col out of range).
#
# NOTE: this Matrix intentionally shadows core's generic Matrix<T>
# (the column-major Metal/GPU-convention type) inside programs that
# `use koala`. Large matmuls delegate through core Tensor's f64 `dgemm`
# bridge via `.matmul_accel`; the default `.matmul` stays pure Tungsten so
# the interpreter and small products keep working. This Matrix remains the
# tabular compatibility facade: it permits nil padding for ragged rows and
# returns nil on invalid shapes, neither of which belongs in numeric Tensor.

+ Matrix
  ro :entries    # nested row arrays, rectangular after construction

  -> new(rows_a)
    ents = []
    nr = rows_a.size
    if nr > 0
      nc = rows_a[0].size
      i = 0
      while i < nr
        r = rows_a[i]
        row = []
        j = 0
        while j < nc
          row.push(r[j])
          j += 1
        ents.push(row)
        i += 1
    @entries = ents

  # --- Factories ---

  # nr×nc matrix filled with v.
  -> .fill(nr, nc, v)
    rows = []
    i = 0
    while i < nr
      row = []
      j = 0
      while j < nc
        row.push(v)
        j += 1
      rows.push(row)
      i += 1
    Matrix.new(rows)

  -> .zeros(nr, nc = nr)
    Matrix.fill(nr, nc, 0)

  -> .ones(nr, nc = nr)
    Matrix.fill(nr, nc, 1)

  -> .identity(n)
    rows = []
    i = 0
    while i < n
      row = []
      j = 0
      while j < n
        if i == j
          row.push(1)
        else
          row.push(0)
        j += 1
      rows.push(row)
      i += 1
    Matrix.new(rows)

  # Square matrix with `values` on the diagonal.
  -> .diagonal(values)
    n = values.size
    rows = []
    i = 0
    while i < n
      row = []
      j = 0
      while j < n
        if i == j
          row.push(values[i])
        else
          row.push(0)
        j += 1
      rows.push(row)
      i += 1
    Matrix.new(rows)

  # Numeric rank-2 Core Tensor -> this compatibility Matrix. Tensor owns its
  # dense storage and view semantics; Matrix owns Koala's row/column and
  # nil-on-shape-error surface. The nested rows are intentionally copied at
  # this API boundary.
  -> .from_tensor(tensor)
    out = nil
    if tensor != nil && tensor.rank == 2
      out = Matrix.new(tensor.to_rows)
    out

  # --- Shape ---

  -> row_count
    @entries.size

  -> col_count
    out = 0
    out = @entries[0].size if @entries.size > 0
    out

  -> shape
    [self.row_count, self.col_count]

  -> square?
    self.row_count == self.col_count

  -> empty?
    self.row_count == 0

  # --- Access ---

  # Element at (i, j); nil out of range. (Multi-arg `m[i, j]` bracket
  # calls do not parse today, hence a named accessor.)
  #
  # Note: the engine bug that once forced integer-compare bounds checks —
  # nested-array out-of-range reads returning garbage ([[1,2],[3,4]][9]
  # => 2) — was fixed at the runtime root in 3637550 (generic [] / []=
  # IC rows now ride the checked get/set). The explicit checks stay
  # anyway: they deliberately normalize negative/invalid indices to nil.
  -> at(i, j)
    out = nil
    if i >= 0 && i < @entries.size
      r = @entries[i]
      out = r[j] if j >= 0 && j < r.size
    out

  # m[i] — row i as a Vector, same as row(i).
  -> [](i)
    self.row(i)

  # Row i as a Vector (copy); nil out of range.
  -> row(i)
    out = nil
    if i >= 0 && i < @entries.size
      r = @entries[i]
      n = r.size
      vals = []
      j = 0
      while j < n
        vals.push(r[j])
        j += 1
      out = Vector.new(vals)
    out

  # Column j as a Vector; nil out of range.
  -> col(j)
    out = nil
    if j >= 0 && j < self.col_count
      ents = @entries
      nr = ents.size
      vals = []
      i = 0
      while i < nr
        vals.push(ents[i][j])
        i += 1
      out = Vector.new(vals)
    out

  -> to_a
    @entries

  # This compatibility class reopens Core's generic Matrix name. Keep its
  # equality structural and nil-safe instead of inheriting Matrix<T>#==,
  # whose shape comparison assumes the other operand has rows and cols.
  -> ==(other)
    out = false
    if other != nil && other.respond_to?("to_a")
      out = @entries == other.to_a
    out

  -> !=(other)
    !(self == other)

  # Convert a fully populated Matrix into Core's f64 Tensor. Ragged Matrix
  # padding is nil by contract and has no numeric Tensor representation, so
  # leave it as nil rather than coercing it to an arbitrary scalar.
  -> to_tensor
    out = nil
    ok = true
    ents = @entries
    nr = ents.size
    i = 0
    while i < nr
      row = ents[i]
      nc = row.size
      j = 0
      while j < nc
        if row[j] == nil
          ok = false
          break
        j += 1
      break if !ok
      i += 1
    if ok
      out = Tensor.from_rows(@entries, Tensor.f64)
    out

  # --- Elementwise arithmetic ---

  # Apply f(a, b) entrywise; nil when shapes differ.
  -> zip_with(other, f)
    out = nil
    if self.row_count == other.row_count && self.col_count == other.col_count
      a = @entries
      b = other.to_a
      nr = a.size
      nc = self.col_count
      rows = []
      i = 0
      while i < nr
        r = a[i]
        br = b[i]
        row = []
        j = 0
        while j < nc
          row.push(f.call(r[j], br[j]))
          j += 1
        rows.push(row)
        i += 1
      out = Matrix.new(rows)
    out

  -> add(other)
    out = nil
    if self.row_count == other.row_count && self.col_count == other.col_count
      a = @entries
      b = other.to_a
      nr = a.size
      nc = self.col_count
      rows = []
      i = 0
      while i < nr
        r = a[i]
        br = b[i]
        row = []
        j = 0
        while j < nc
          row.push(r[j] + br[j])
          j += 1
        rows.push(row)
        i += 1
      out = Matrix.new(rows)
    out

  -> sub(other)
    out = nil
    if self.row_count == other.row_count && self.col_count == other.col_count
      a = @entries
      b = other.to_a
      nr = a.size
      nc = self.col_count
      rows = []
      i = 0
      while i < nr
        r = a[i]
        br = b[i]
        row = []
        j = 0
        while j < nc
          row.push(r[j] - br[j])
          j += 1
        rows.push(row)
        i += 1
      out = Matrix.new(rows)
    out

  # Elementwise (Hadamard) product — NOT matrix multiplication.
  -> mul(other)
    out = nil
    if self.row_count == other.row_count && self.col_count == other.col_count
      a = @entries
      b = other.to_a
      nr = a.size
      nc = self.col_count
      rows = []
      i = 0
      while i < nr
        r = a[i]
        br = b[i]
        row = []
        j = 0
        while j < nc
          row.push(r[j] * br[j])
          j += 1
        rows.push(row)
        i += 1
      out = Matrix.new(rows)
    out

  # Multiply every entry by scalar k.
  -> scale(k)
    ents = @entries
    nr = ents.size
    nc = self.col_count
    rows = []
    i = 0
    while i < nr
      r = ents[i]
      row = []
      j = 0
      while j < nc
        row.push(r[j] * k)
        j += 1
      rows.push(row)
      i += 1
    Matrix.new(rows)

  # --- Matrix products ---

  # Matrix multiplication; nil unless self.col_count == other.row_count.
  # Pure Tungsten triple loop — correct on both engines. For large
  # products under the compiler, prefer matmul_accel (dgemm).
  -> matmul(other)
    out = nil
    if self.col_count == other.row_count
      a = @entries
      b = other.to_a
      nr = a.size
      inner = self.col_count
      bc = other.col_count
      bt = []
      j = 0
      while j < bc
        col = []
        k = 0
        while k < inner
          col.push(b[k][j])
          k += 1
        bt.push(col)
        j += 1
      rows = []
      i = 0
      while i < nr
        ar = a[i]
        row = []
        j = 0
        while j < bc
          bj = bt[j]
          total = 0
          k = 0
          while k < inner
            total += ar[k] * bj[k]
            k += 1
          row.push(total)
          j += 1
        rows.push(row)
        i += 1
      out = Matrix.new(rows)
    out

  # Core Tensor f64 / Accelerate dgemm path. Returns nil on a shape mismatch
  # or when Matrix's legacy nil padding cannot become a numeric Tensor.
  # The Tensor bridge owns packing, dtype selection and BLAS dispatch; Koala
  # only preserves its Matrix compatibility contract around that Core API.
  -> matmul_accel(other)
    out = nil
    if self.col_count == other.row_count
      left = self.to_tensor
      right = other.to_tensor
      if left != nil && right != nil
        out = Matrix.from_tensor(left.matmul(right))
    out

  # Matrix × Vector -> Vector; nil unless col_count == v.size.
  -> matvec(v)
    out = nil
    if self.col_count == v.size
      a = @entries
      b = v.to_a
      nr = a.size
      nc = self.col_count
      vals = []
      i = 0
      while i < nr
        r = a[i]
        total = 0
        j = 0
        while j < nc
          total += r[j] * b[j]
          j += 1
        vals.push(total)
        i += 1
      out = Vector.new(vals)
    out

  # --- Structure ---

  -> transpose
    nr = self.row_count
    nc = self.col_count
    ents = @entries
    rows = []
    j = 0
    while j < nc
      row = []
      i = 0
      while i < nr
        row.push(ents[i][j])
        i += 1
      rows.push(row)
      j += 1
    Matrix.new(rows)

  # Sum of the diagonal; nil unless square.
  -> trace
    out = nil
    if self.square?
      ents = @entries
      nr = ents.size
      total = 0
      i = 0
      while i < nr
        total += ents[i][i]
        i += 1
      out = total
    out

  # Frobenius norm.
  -> norm
    ents = @entries
    nr = ents.size
    nc = self.col_count
    total = 0
    i = 0
    while i < nr
      r = ents[i]
      j = 0
      while j < nc
        v = r[j]
        total += v * v
        j += 1
      i += 1
    Math.sqrt(total)

  # --- Linear algebra (see linalg.w) ---

  # Determinant; nil unless square (0 when singular).
  -> det
    LinAlg.det(self)

  # Inverse; nil unless square and non-singular.
  -> inv
    LinAlg.inv(self)

  # Solve self * x = b for x (b: Vector or array); nil when unsolvable.
  -> solve(b)
    LinAlg.solve(self, b)

  # Reduced QR: { q: Matrix, r: Matrix } with self == q.matmul(r);
  # nil when empty, wider than tall, or rank-deficient.
  -> qr
    LinAlg.qr(self)

  # Least-squares x minimizing |self*x - b| (b: Vector or array), by
  # Householder QR — the numerically sound route for overdetermined
  # systems. nil when the shapes are unusable or self is rank-deficient.
  -> lstsq(b)
    LinAlg.lstsq(self, b)

  # --- Conversion ---

  # Already a Matrix — self. (The estimator input convention: every
  # tabular type answers to_matrix, so Estimator.feature_rows
  # coerces DataFrame and Matrix through one polymorphic call.)
  -> to_matrix
    self

  # 1×n or n×1 matrix as a Vector; nil otherwise.
  -> to_vector
    out = nil
    out = self.row(0) if self.row_count == 1
    out = self.col(0) if out == nil && self.col_count == 1
    out

  -> to_s
    ents = @entries
    lines = []
    ents.each -> (r)
      cells = []
      r.each -> (v)
        cells.push(v.to_s)
      lines.push("  " + cells.join(" "))
    "Matrix [self.row_count]x[self.col_count]:\n" + lines.join("\n")
