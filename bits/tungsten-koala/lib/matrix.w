# Matrix — dense matrix with linear algebra and GPU acceleration
# Supports matrix literal syntax, Unicode operators, and automatic GPU dispatch.

in Tungsten:Koala

+ Matrix
  ro :rows
  ro :cols
  ro :data      # flat row-major array
  ro :device

  # Create a matrix from nested arrays (rows) or flat data.
  #
  #     m = Matrix.new([[1, 2], [3, 4]])
  #     m = Matrix.new(flat: [1, 2, 3, 4], rows: 2, cols: 2)
  -> new(row_data = nil, flat: nil, rows: nil, cols: nil, device: nil)
    case
    => flat
      @data = flat.to_a
      @rows = rows
      @cols = cols
    => row_data
      @data = row_data.flat_map(&:to_a)
      @rows = row_data.size
      @cols = row_data.first.size
    @device = Device.resolve(device, elements: @rows * @cols)
    @buffer = nil
    self.upload if @device.gpu?

  # --- Factories ---

  -> .identity(n, device: nil)
    data = Array.new(n * n, 0)
    n.times(-> (i) data[i * n + i] = 1)
    self.new(flat: data, rows: n, cols: n, device: device)

  -> .zeros(rows, cols = rows, device: nil)
    self.new(flat: Array.new(rows * cols, 0), rows: rows, cols: cols, device: device)

  -> .ones(rows, cols = rows, device: nil)
    self.new(flat: Array.new(rows * cols, 1), rows: rows, cols: cols, device: device)

  -> .random(rows, cols = rows, device: nil)
    self.new(flat: Array.new(rows * cols) { Random.float }, rows: rows, cols: cols, device: device)

  -> .diagonal(values, device: nil)
    n = values.size
    data = Array.new(n * n, 0)
    n.times(-> (i) data[i * n + i] = values[i])
    self.new(flat: data, rows: n, cols: n, device: device)

  -> .from_vector(vec, direction: :row)
    case direction
    => :row    -> self.new([vec.to_a])
    => :column -> self.new(vec.to_a.map(-> (v) [v]))

  # --- Access ---

  -> [](row, col = nil)
    case
    => col == nil
      case row
      => Int   -> Vector.new(@data[row * @cols, @cols])
      => Range -> self.class.new(row.map(-> (r) @data[r * @cols, @cols]))
    => row == :all || row == nil
      col_data = @rows.times.map(-> (r) @data[r * @cols + col])
      Vector.new(col_data)
    =>
      @data[row * @cols + col]

  # Slicing: m[0..2, 1..3]
  -> slice(row_range, col_range)
    row_indices = row_range.to_a
    col_indices = col_range.to_a
    data = row_indices.flat_map -> (r)
      col_indices.map(-> (c) @data[r * @cols + c])
    self.class.new(flat: data, rows: row_indices.size, cols: col_indices.size, device: @device)

  -> []=(row, col, value)
    @data[row * @cols + col] = value
    self.upload if @device.gpu?

  -> size       [@rows, @cols]
  -> square?    @rows == @cols
  -> symmetric? self == self.T

  # --- Core operations ---

  # Matrix multiplication — `A @ B`
  # GPU-accelerated for large matrices.
  #
  #     result = A @ B
  -> @(other)
    <! DimensionError, "Matrix dimensions [self.cols]×[other.rows] don't align" unless @cols == other.rows
    device = Device.resolve(nil, elements: @rows * other.cols)
    if device.gpu?
      result_data = GPU.matmul(@data, other.data, @rows, other.cols, @cols, device: device)
      self.class.new(flat: result_data, rows: @rows, cols: other.cols, device: device)
    else
      data = Array.new(@rows * other.cols, 0)
      @rows.times -> (i)
        other.cols.times -> (j)
          sum = 0
          @cols.times -> (k)
            sum += @data[i * @cols + k] * other.data[k * other.cols + j]
          data[i * other.cols + j] = sum
      self.class.new(flat: data, rows: @rows, cols: other.cols, device: device)

  # Element-wise multiplication — `A * B`
  -> *(other)
    case other
    => Matrix
      <! DimensionError, "Matrices must have same dimensions" unless self.size == other.size
      self.class.new(flat: @data.zip(other.data).map(-> (a, b) a * b), rows: @rows, cols: @cols, device: @device)
    => Numeric
      self.class.new(flat: @data.map(-> (v) v * other), rows: @rows, cols: @cols, device: @device)

  -> +(other)
    case other
    => Matrix
      <! DimensionError, "Matrices must have same dimensions" unless self.size == other.size
      self.class.new(flat: @data.zip(other.data).map(-> (a, b) a + b), rows: @rows, cols: @cols, device: @device)
    => Numeric
      self.class.new(flat: @data.map(-> (v) v + other), rows: @rows, cols: @cols, device: @device)

  -> -(other)
    case other
    => Matrix
      <! DimensionError, "Matrices must have same dimensions" unless self.size == other.size
      self.class.new(flat: @data.zip(other.data).map(-> (a, b) a - b), rows: @rows, cols: @cols, device: @device)
    => Numeric
      self.class.new(flat: @data.map(-> (v) v - other), rows: @rows, cols: @cols, device: @device)

  -> /(scalar)
    self.class.new(flat: @data.map(-> (v) v / scalar), rows: @rows, cols: @cols, device: @device)

  -> **(n)
    <! DimensionError, "Matrix exponentiation requires square matrix" unless self.square?
    case n
    => 0 -> self.class.identity(@rows, device: @device)
    => 1 -> self
    => _ ->
      result = self
      (n - 1).times(-> result = result @ self)
      result

  # Dot product — `A · B` (U+00B7 middle dot)
  # For matrices: Frobenius inner product (sum of element-wise products).
  # Equivalent to Tr(A^T · B).
  #
  #     A · B  # => scalar (Frobenius inner product)
  -> ·(other)
    <! DimensionError, "Matrices must have same dimensions" unless self.size == other.size
    @data.zip(other.data).map(-> (a, b) a * b).sum

  # Dot product — ASCII alias.
  -> dot(other) self · other

  # Tensor product — `A ⊗ B` (U+2297 Kronecker product)
  #
  #     C = A ⊗ B  # => (m·p)×(n·q) matrix
  -> ⊗(other)
    new_rows = @rows * other.rows
    new_cols = @cols * other.cols
    data = Array.new(new_rows * new_cols, 0)
    @rows.times -> (i)
      @cols.times -> (j)
        other.rows.times -> (k)
          other.cols.times -> (l)
            r = i * other.rows + k
            c = j * other.cols + l
            data[r * new_cols + c] = @data[i * @cols + j] * other.data[k * other.cols + l]
    self.class.new(flat: data, rows: new_rows, cols: new_cols, device: @device)

  # Tensor product — ASCII alias.
  -> kronecker(other) self ⊗ other

  # --- Decompositions & properties ---
  # GPU-accelerated when matrix is large enough.

  # Transpose — `A.T`
  -> T
    data = Array.new(@rows * @cols)
    @rows.times -> (i)
      @cols.times -> (j)
        data[j * @rows + i] = @data[i * @cols + j]
    self.class.new(flat: data, rows: @cols, cols: @rows, device: @device)

  # Inverse — `A.inv`
  -> inv
    <! DimensionError, "Inverse requires square matrix" unless self.square?
    <! SingularMatrixError, "Matrix is singular" if self.det == 0
    LinAlg.inv(self)

  # Determinant — `A.det`
  -> det
    <! DimensionError, "Determinant requires square matrix" unless self.square?
    LinAlg.det(self)

  # Trace — `A.trace`
  -> trace
    <! DimensionError, "Trace requires square matrix" unless self.square?
    @rows.times.map(-> (i) @data[i * @cols + i]).sum

  # Rank
  -> rank
    LinAlg.rank(self)

  # SVD — `u, s, vt = A.svd`
  -> svd LinAlg.svd(self)

  # QR — `q, r = A.qr`
  -> qr LinAlg.qr(self)

  # LU — `l, u = A.lu`
  -> lu LinAlg.lu(self)

  # Eigenvalue decomposition — `eigvals, eigvecs = A.eig`
  -> eig LinAlg.eig(self)

  # Cholesky — `L = A.cholesky`
  -> cholesky LinAlg.cholesky(self)

  # --- Norms ---

  # Frobenius norm.
  -> norm
    Math.sqrt(@data.map(-> (v) v * v).sum)

  # Specific norm (1, 2, :inf, :fro).
  -> norm_of(kind)
    LinAlg.norm(self, kind)

  # --- Row/column operations ---

  -> row(i)      Vector.new(@data[i * @cols, @cols])
  -> col(j)      Vector.new(@rows.times.map(-> (i) @data[i * @cols + j]))
  -> diagonal    Vector.new(@rows.times.map(-> (i) @data[i * @cols + i]))
  -> row_count   @rows
  -> col_count   @cols

  -> each_row(&block)
    @rows.times.map(-> (i) self.row(i)).each(&block)

  -> map_rows(&block)
    rows = @rows.times.map(-> (i) block.call(self.row(i)).to_a)
    self.class.new(rows, device: @device)

  # --- Conversion ---

  -> to_a
    @rows.times.map(-> (i) @data[i * @cols, @cols])

  -> to_sparse(format: :auto)
    SparseMatrix.from_dense(self, format: format)

  -> to_vector
    <! DimensionError, "Only 1×n or n×1 matrices can convert to Vector" unless @rows == 1 || @cols == 1
    Vector.new(@data)

  -> to_dataframe(columns: nil)
    cols = columns || @cols.times.map(-> (i) "col_[i]".to_sym)
    col_data = cols.each_with_index.map -> (name, j)
      [name, self.col(j).to_a]
    DataFrame.new(**col_data.to_h)

  -> to_s
    lines = @rows.times.map -> (i)
      row = @data[i * @cols, @cols]
      "  " + row.map(-> (v) v.to_s.rjust(8)).join(" ")
    "Matrix [rows]×[cols] ([device.kind]):\n" + lines.join("\n")

  # --- Device management ---

  # Transfer to a different device.
  -> to(target_device)
    self.class.new(flat: @data, rows: @rows, cols: @cols, device: target_device)

  [private]

  -> upload
    @buffer = DeviceMemory.alloc(@device, @data.size * 8)
    cpu_mem = DeviceMemory.new(Device.cpu, @data.data_pointer, @data.size * 8)
    DeviceMemory.transfer(cpu_mem, @device)

+ DimensionError < Error
+ SingularMatrixError < Error
