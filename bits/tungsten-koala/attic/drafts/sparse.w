# SparseMatrix — sparse matrix with automatic format selection and GPU acceleration
#
# Formats:
#   :coo — Coordinate (good for construction, random access)
#   :csr — Compressed Sparse Row (fast row slicing, SpMV)
#   :csc — Compressed Sparse Column (fast column slicing)
#   :bsr — Block Sparse Row (block-structured sparsity)
#   :ell — ELLPACK (uniform row lengths, GPU-friendly)
#   :auto — analyze sparsity pattern and pick optimal format (default)
#
# Reference: DyLaClass (IEEE TPDS 2024) for dynamic format selection.

in Tungsten:Koala

+ SparseMatrix
  ro :rows
  ro :cols
  ro :nnz      # number of nonzeros
  ro :format   # :coo, :csr, :csc, :bsr, :ell
  ro :device

  # Internal storage — varies by format
  ro :row_idx, :col_idx, :values        # COO
  ro :indptr, :indices, :data           # CSR / CSC
  ro :block_size, :block_indptr, :block_indices, :block_data  # BSR
  ro :ell_cols, :ell_indices, :ell_data  # ELL

  # Create a sparse matrix.
  #
  #     # From coordinate triples
  #     s = SparseMatrix.new(
  #       rows: 1000, cols: 1000,
  #       row_idx: [0, 0, 1, 2],
  #       col_idx: [0, 2, 1, 2],
  #       values:  [1.0, 2.0, 3.0, 4.0]
  #     )
  #
  #     # Auto format selection (default)
  #     s = SparseMatrix.new(data, format: :auto)
  #
  #     # Force CSR
  #     s = SparseMatrix.new(data, format: :csr)
  -> new(rows:, cols:, row_idx: [], col_idx: [], values: [], format: :auto, device: nil)
    @rows    = rows
    @cols    = cols
    @row_idx = row_idx
    @col_idx = col_idx
    @values  = values
    @nnz     = values.size
    @device  = Device.resolve(device, elements: @nnz)

    @format = case format
    => :auto -> FormatSelector.select(self)
    => _     -> format

    self.build_internal

  # Convert a dense Matrix to sparse.
  -> .from_dense(matrix, format: :auto, device: nil)
    row_idx = []
    col_idx = []
    values  = []
    matrix.rows.times -> (i)
      matrix.cols.times -> (j)
        val = matrix[i, j]
        unless val == 0
          row_idx.push(i)
          col_idx.push(j)
          values.push(val)
    self.new(
      rows: matrix.rows, cols: matrix.cols,
      row_idx: row_idx, col_idx: col_idx, values: values,
      format: format, device: device
    )

  # Create a sparse identity matrix.
  -> .identity(n, format: :csr, device: nil)
    indices = (0...n).to_a
    self.new(
      rows: n, cols: n,
      row_idx: indices, col_idx: indices, values: Array.new(n, 1.0),
      format: format, device: device
    )

  # --- Properties ---

  -> density    @nnz.to_f / (@rows * @cols)
  -> sparsity   1.0 - self.density
  -> empty?     @nnz == 0
  -> square?    @rows == @cols

  # --- Operations ---

  # Matrix multiplication — `A @ B`
  # Dispatches to GPU sparse kernels when available.
  -> @(other)
    case other
    => SparseMatrix
      <! DimensionError, "Dimensions don't align" unless @cols == other.rows
      LinAlg.sparse_matmul(self, other)
    => Matrix
      <! DimensionError, "Dimensions don't align" unless @cols == other.rows
      if @device.gpu?
        GPU.spmm(self.internal_data, @format, other.data, @rows, other.cols, @cols, device: @device)
        |> -> (data) Matrix.new(flat: data, rows: @rows, cols: other.cols, device: @device)
      else
        LinAlg.sparse_dense_matmul(self, other)
    => Vector
      <! DimensionError, "Dimensions don't align" unless @cols == other.size
      if @device.gpu?
        GPU.spmv(self.internal_data, @format, other.values, @rows, @cols, @nnz, device: @device)
        |> -> (data) Vector.new(data, device: @device)
      else
        LinAlg.sparse_matvec(self, other)

  # Element-wise multiplication — `A * B`
  -> *(other)
    case other
    => SparseMatrix -> LinAlg.sparse_elementwise(:*, self, other)
    => Numeric      ->
      new_values = @values.map(-> (v) v * other)
      self.class.new(
        rows: @rows, cols: @cols,
        row_idx: @row_idx.dup, col_idx: @col_idx.dup, values: new_values,
        format: @format, device: @device
      )

  -> +(other) LinAlg.sparse_elementwise(:+, self, other)
  -> -(other) LinAlg.sparse_elementwise(:-, self, other)

  # Dot product — Frobenius inner product of two sparse matrices.
  -> ·(other)
    <! DimensionError, "Matrices must have same dimensions" unless @rows == other.rows && @cols == other.cols
    # Iterate over shared nonzero positions
    sum = 0.0
    self.each_nonzero -> (i, j, v)
      ov = other.get(i, j)
      sum += v * ov unless ov == 0
    sum

  -> dot(other) self · other

  # Transpose.
  -> T
    self.class.new(
      rows: @cols, cols: @rows,
      row_idx: @col_idx.dup, col_idx: @row_idx.dup, values: @values.dup,
      format: self.transposed_format, device: @device
    )

  # --- Access ---

  -> get(row, col)
    case @format
    => :csr ->
      start_idx = @indptr[row]
      end_idx   = @indptr[row + 1]
      pos = @indices[start_idx...end_idx].index(col)
      pos ? @data[start_idx + pos] : 0
    => :coo ->
      idx = @row_idx.each_with_index.find(-> (r, i) r == row && @col_idx[i] == col)
      idx ? @values[idx.last] : 0
    => _ ->
      self.to_csr.get(row, col)

  -> row(i)
    case @format
    => :csr ->
      start_idx = @indptr[i]
      end_idx   = @indptr[i + 1]
      cols = @indices[start_idx...end_idx]
      vals = @data[start_idx...end_idx]
      { indices: cols, values: vals }
    => _ -> self.to_csr.row(i)

  -> each_nonzero(&block)
    case @format
    => :coo ->
      @nnz.times -> (i)
        block.call(@row_idx[i], @col_idx[i], @values[i])
    => :csr ->
      @rows.times -> (i)
        (@indptr[i]...@indptr[i + 1]).each -> (k)
          block.call(i, @indices[k], @data[k])
    => _ -> self.to_coo.each_nonzero(&block)

  # --- Format conversion ---

  -> to_coo
    return self if @format == :coo
    row_idx = []
    col_idx = []
    values  = []
    self.each_nonzero -> (i, j, v)
      row_idx.push(i)
      col_idx.push(j)
      values.push(v)
    self.class.new(
      rows: @rows, cols: @cols,
      row_idx: row_idx, col_idx: col_idx, values: values,
      format: :coo, device: @device
    )

  -> to_csr
    return self if @format == :csr
    coo = self.to_coo
    # Sort by row then column
    triples = coo.row_idx.zip(coo.col_idx, coo.values)
      .sort_by(-> (r, c, _) [r, c])

    indptr  = Array.new(@rows + 1, 0)
    indices = []
    data    = []
    triples.each -> (r, c, v)
      indptr[r + 1] += 1
      indices.push(c)
      data.push(v)
    # Cumulative sum
    (1..@rows).each(-> (i) indptr[i] += indptr[i - 1])

    result = self.class.new(
      rows: @rows, cols: @cols,
      row_idx: [], col_idx: [], values: [],
      format: :csr, device: @device
    )
    result.instance_set(:indptr, indptr)
    result.instance_set(:indices, indices)
    result.instance_set(:data, data)
    result

  -> to_csc
    return self if @format == :csc
    self.T.to_csr.T  # Transpose trick

  -> to_bsr(block_size: nil)
    block_size ||= FormatSelector.detect_block_size(self)
    LinAlg.sparse_to_bsr(self, block_size)

  -> to_ell
    LinAlg.sparse_to_ell(self)

  -> to_dense
    m = Matrix.zeros(@rows, @cols, device: @device)
    self.each_nonzero(-> (i, j, v) m[i, j] = v)
    m

  # Convert to a new format.
  -> to_format(fmt)
    case fmt
    => :coo -> self.to_coo
    => :csr -> self.to_csr
    => :csc -> self.to_csc
    => :bsr -> self.to_bsr
    => :ell -> self.to_ell

  # Transfer to a different device.
  -> to(target_device)
    self.class.new(
      rows: @rows, cols: @cols,
      row_idx: @row_idx.dup, col_idx: @col_idx.dup, values: @values.dup,
      format: @format, device: target_device
    )

  -> to_s
    "SparseMatrix [rows]×[cols] (nnz=[nnz], format=[format], density=[("%.4f" % self.density)], device=[device.kind])"

  # --- Internal ---

  [private]

  -> build_internal
    case @format
    => :csr -> self.build_csr
    => :csc -> self.build_csc
    => :bsr -> self.build_bsr
    => :ell -> self.build_ell
    => :coo -> nil  # COO is the native format

  -> build_csr
    csr = self.to_csr
    @indptr  = csr.indptr
    @indices = csr.indices
    @data    = csr.data

  -> build_csc
    transposed = self.class.new(
      rows: @cols, cols: @rows,
      row_idx: @col_idx, col_idx: @row_idx, values: @values,
      format: :csr, device: @device
    )
    @indptr  = transposed.indptr
    @indices = transposed.indices
    @data    = transposed.data

  -> build_bsr
    @block_size ||= FormatSelector.detect_block_size(self)

  -> build_ell
    # Determine max nonzeros per row
    row_counts = Array.new(@rows, 0)
    @row_idx.each(-> (r) row_counts[r] += 1)
    @ell_cols = row_counts.max

  -> internal_data
    case @format
    => :csr -> { indptr: @indptr, indices: @indices, data: @data }
    => :csc -> { indptr: @indptr, indices: @indices, data: @data }
    => :coo -> { row_idx: @row_idx, col_idx: @col_idx, values: @values }
    => :bsr -> { block_size: @block_size, indptr: @block_indptr, indices: @block_indices, data: @block_data }
    => :ell -> { ell_cols: @ell_cols, indices: @ell_indices, data: @ell_data }

  -> transposed_format
    case @format
    => :csr -> :csc
    => :csc -> :csr
    => _    -> @format


# --- Automatic format selection ---
# Uses sparsity pattern analysis to choose the fastest format for the operation + device.
# Inspired by DyLaClass (IEEE TPDS 2024).

+ FormatSelector
  # Analyze sparsity pattern and select optimal format.
  #
  # Heuristics:
  #   - Very sparse + uniform rows → ELL (GPU-friendly, coalesced access)
  #   - Block structure detected → BSR (BLAS-level block ops)
  #   - Row-heavy access pattern → CSR (most general, good SpMV)
  #   - Column-heavy access pattern → CSC
  #   - Under construction / random access → COO
  -> .select(sparse)
    density = sparse.nnz.to_f / (sparse.rows * sparse.cols)
    row_counts = self.row_distribution(sparse)
    row_variance = Stats.var(row_counts)
    has_blocks = self.detect_block_structure?(sparse)
    is_gpu = sparse.device.gpu?

    case
    # Block structure → BSR (especially good for FEM, stencils)
    => has_blocks
      :bsr
    # Very sparse + uniform row lengths + GPU → ELL (coalesced GPU memory access)
    => is_gpu && density < 0.01 && row_variance < row_counts.mean * 0.5
      :ell
    # General sparse → CSR (best all-around for SpMV, row slicing)
    => density < 0.3
      :csr
    # Dense-ish → just use dense
    =>
      :csr  # CSR still works; the caller can convert to dense if needed

  # Detect block size from sparsity pattern.
  # Tries common block sizes (2, 3, 4, 8) and picks the one with best coverage.
  -> .detect_block_size(sparse)
    candidates = [2, 3, 4, 8]
    best_size = 2
    best_coverage = 0.0

    candidates.each -> (bs)
      coverage = self.block_coverage(sparse, bs)
      if coverage > best_coverage
        best_coverage = coverage
        best_size = bs

    best_size

  [private]

  -> .row_distribution(sparse)
    counts = Array.new(sparse.rows, 0)
    sparse.row_idx.each(-> (r) counts[r] += 1)
    counts

  -> .detect_block_structure?(sparse)
    return false if sparse.nnz < 16
    # Sample nonzeros and check if they cluster into aligned blocks
    sample_size = [sparse.nnz, 1000].min
    samples = sparse.row_idx.zip(sparse.col_idx).sample(sample_size)

    [2, 4, 8].any? -> (bs)
      aligned = samples.count -> (r, c)
        r % bs == 0 && c % bs == 0
      aligned.to_f / sample_size > 0.3

  -> .block_coverage(sparse, block_size)
    blocks = {}
    sparse.row_idx.zip(sparse.col_idx).each -> (r, c)
      br = r / block_size
      bc = c / block_size
      blocks[[br, bc]] ||= 0
      blocks[[br, bc]] += 1

    # Coverage = fraction of nonzeros that fill complete blocks
    full_block_elements = block_size * block_size
    covered = blocks.values.count(-> (n) n == full_block_elements) * full_block_elements
    covered.to_f / sparse.nnz
