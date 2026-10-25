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

  # Koala's compatibility Vector reopens Core's generic Vector name. Own
  # equality here so comparisons against nil or unrelated objects do not fall
  # through to Core Vector<T>#==, which assumes the other operand has a
  # dimension. This is also the natural structural equality for dense vectors.
  -> ==(other)
    out = false
    if other != nil && other.respond_to?("to_a")
      out = @values == other.to_a
    out

  -> !=(other)
    !(self == other)

  # --- Elementwise arithmetic ---

  # Apply f(a, b) pairwise; nil when sizes differ.
  -> zip_with(other, f)
    out = nil
    if @values.size == other.size
      a = @values
      b = other.to_a
      n = a.size
      acc = []
      i = 0
      while i < n
        acc.push(f.call(a[i], b[i]))
        i += 1
      out = Vector.new(acc)
    out

  -> add(other)
    out = nil
    a = @values
    if a.size == other.size
      b = other.to_a
      n = a.size
      acc = []
      i = 0
      while i < n
        acc.push(a[i] + b[i])
        i += 1
      out = Vector.new(acc)
    out

  -> sub(other)
    out = nil
    a = @values
    if a.size == other.size
      b = other.to_a
      n = a.size
      acc = []
      i = 0
      while i < n
        acc.push(a[i] - b[i])
        i += 1
      out = Vector.new(acc)
    out

  # Elementwise (Hadamard) product.
  -> mul(other)
    out = nil
    a = @values
    if a.size == other.size
      b = other.to_a
      n = a.size
      acc = []
      i = 0
      while i < n
        acc.push(a[i] * b[i])
        i += 1
      out = Vector.new(acc)
    out

  # Elementwise division (always float).
  -> div(other)
    out = nil
    a = @values
    if a.size == other.size
      b = other.to_a
      n = a.size
      acc = []
      i = 0
      while i < n
        acc.push(a[i].to_f / b[i].to_f)
        i += 1
      out = Vector.new(acc)
    out

  # Multiply every element by scalar k.
  -> scale(k)
    vals = @values
    n = vals.size
    acc = []
    i = 0
    while i < n
      acc.push(vals[i] * k)
      i += 1
    Vector.new(acc)

  # --- Products, norms, geometry ---

  # Dot product; nil when sizes differ.
  -> dot(other)
    out = nil
    a = @values
    if a.size == other.size
      b = other.to_a
      n = a.size
      total = 0
      i = 0
      while i < n
        total += a[i] * b[i]
        i += 1
      out = total
    out

  # Euclidean (L2) norm.
  -> norm
    vals = @values
    n = vals.size
    total = 0
    i = 0
    while i < n
      v = vals[i]
      total += v * v
      i += 1
    Math.sqrt(total)

  # L1 (Manhattan) norm, as a float.
  -> norm_l1
    vals = @values
    n = vals.size
    total = 0.to_f
    i = 0
    while i < n
      x = vals[i].to_f
      x = 0.to_f - x if x < 0
      total += x
      i += 1
    total

  # Unit-length copy; nil for the zero vector.
  -> normalize
    n = self.norm
    out = nil
    out = self.scale(1.to_f / n) if n > 0
    out

  # Euclidean distance; nil when sizes differ.
  -> distance(other)
    out = nil
    a = @values
    if a.size == other.size
      b = other.to_a
      n = a.size
      total = 0
      i = 0
      while i < n
        d = a[i] - b[i]
        total += d * d
        i += 1
      out = Math.sqrt(total)
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
    n = vals.size
    all = true
    i = 0
    while i < n
      if vals[i] != 0
        all = false
        break
      i += 1
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
