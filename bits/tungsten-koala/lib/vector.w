# Vector — a plain dense numeric vector (pure Tungsten, CPU-only)
#
#     v = Vector.new([1, 2, 3])
#     v.dot(Vector.new([4, 5, 6]))   # => 32
#     v.norm                         # => L2 length
#
# Shape rule: every two-operand op returns nil when the sizes differ
# (same convention as DataFrame#column for a missing column).
# normalize returns nil for the zero vector.
#
# NOTE: this Vector intentionally shadows core's generic Vector<T>
# (the numeric-tower / Metal-adjacent type) inside programs that
# `use koala`. Interop with core Vec/Mat types is a follow-up.
#
# NOTE: locals are hoisted from ivars before any `-> (x)` block — the
# interpreter cannot resolve @ivars from a block body — and methods
# that contain closures avoid early `return` (see stats.w).
+ Vector
  ro :values

  -> new(values)
    @values = values

  -> size
    @values.size

  -> empty?
    @values.size == 0

  -> to_a
    @values

  -> [](i)
    @values[i]

  # --- Elementwise arithmetic ---

  # Apply f(a, b) pairwise; nil when sizes differ.
  -> zip_with(other, f)
    out = nil
    if @values.size == other.size
      a = @values
      b = other.to_a
      acc = []
      i = 0
      a.each -> (x)
        acc.push(f.call(x, b[i]))
        i += 1
      out = Vector.new(acc)
    out

  -> add(other)
    f = -> (x, y) x + y
    self.zip_with(other, f)

  -> sub(other)
    f = -> (x, y) x - y
    self.zip_with(other, f)

  # Elementwise (Hadamard) product.
  -> mul(other)
    f = -> (x, y) x * y
    self.zip_with(other, f)

  # Elementwise division (always float).
  -> div(other)
    f = -> (x, y) x.to_f / y.to_f
    self.zip_with(other, f)

  # Multiply every element by scalar k.
  -> scale(k)
    vals = @values
    acc = []
    vals.each -> (v)
      acc.push(v * k)
    Vector.new(acc)

  # --- Products, norms, geometry ---

  # Dot product; nil when sizes differ.
  -> dot(other)
    p = self.mul(other)
    out = nil
    out = Stats.sum(p.to_a) if p != nil
    out

  # Euclidean (L2) norm.
  -> norm
    Math.sqrt(self.dot(self))

  # L1 (Manhattan) norm, as a float.
  -> norm_l1
    vals = @values
    total = 0.to_f
    vals.each -> (v)
      x = v.to_f
      x = 0.to_f - x if x < 0
      total += x
    total

  # Unit-length copy; nil for the zero vector.
  -> normalize
    n = self.norm
    out = nil
    out = self.scale(1.to_f / n) if n > 0
    out

  # Euclidean distance; nil when sizes differ.
  -> distance(other)
    d = self.sub(other)
    out = nil
    out = d.norm if d != nil
    out

  # Cosine similarity; nil when sizes differ or either vector is zero.
  -> cosine_similarity(other)
    d = self.dot(other)
    out = nil
    if d != nil
      na = self.norm
      nb = other.norm
      out = d.to_f / (na * nb) if na > 0 && nb > 0
    out

  -> zero?
    vals = @values
    all = true
    vals.each -> (v)
      all = false if v != 0
    all

  # --- Conversion ---

  -> to_series(name = "vector")
    Series.new(@values, name)

  # 1×n Matrix.
  -> to_row_matrix
    Matrix.new([@values])

  # n×1 Matrix.
  -> to_col_matrix
    vals = @values
    rows = []
    vals.each -> (v)
      rows.push([v])
    Matrix.new(rows)

  # n×1 Matrix — the estimator input convention (see matrix.w): any
  # non-array x answers to_matrix, so a Vector is one single-feature
  # column to Estimator.feature_rows.
  -> to_matrix
    self.to_col_matrix

  -> to_s
    "Vector(n=[@values.size]): " + @values.to_s
