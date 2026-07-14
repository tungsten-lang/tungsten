# Mat2 — 2×2 matrix. Column-major storage matching Metal's float2x2.
#   elements layout:   [ m00, m10,
#                        m01, m11 ]
#   so elements[0..1] is column 0, elements[2..3] is column 1.
+ Mat2<T> < Matrix<T>
  - data
    T elements[4]

  -> new(@elements ## T[4])

  -> rows 2
  -> cols 2

  # Class methods.

  -> .identity
    class.new([1 ## T, 0 ## T, 0 ## T, 1 ## T] ## T[4])

  -> .zero
    class.new([0 ## T, 0 ## T, 0 ## T, 0 ## T] ## T[4])

  # Column / row views.

  -> col(c)
    Vec2.new([@elements[c * 2], @elements[c * 2 + 1]] ## T[2])

  -> row(r)
    Vec2.new([@elements[r], @elements[2 + r]] ## T[2])

  # Fixed-width componentwise arithmetic avoids Matrix's map/zip temporaries.

  -> negate
    a = @elements
    class.new([-a[0], -a[1], -a[2], -a[3]] ## T[4])

  -> +/1
    a = @elements
    b = @1.elements
    class.new([
      a[0] + b[0], a[1] + b[1],
      a[2] + b[2], a[3] + b[3]
    ] ## T[4])

  -> -/1
    a = @elements
    b = @1.elements
    class.new([
      a[0] - b[0], a[1] - b[1],
      a[2] - b[2], a[3] - b[3]
    ] ## T[4])

  -> //1(Number)
    a = @elements
    s = @1
    class.new([a[0] / s, a[1] / s, a[2] / s, a[3] / s] ## T[4])

  -> ⊙/1
    a = @elements
    b = @1.elements
    class.new([
      a[0] * b[0], a[1] * b[1],
      a[2] * b[2], a[3] * b[3]
    ] ## T[4])

  # Linear algebra.

  -> transpose
    a = @elements
    class.new([
      a[0], a[2],
      a[1], a[3]
    ] ## T[4])

  -> determinant
    a = @elements
    a[0] * a[3] - a[2] * a[1]

  -> trace
    a = @elements
    a[0] + a[3]

  # Inverse: (1/det) · [[ d, −b ], [ −c, a ]] for `[[a, b], [c, d]]`.
  -> inverse
    a = @elements
    d = a[0] * a[3] - a[2] * a[1]
    class.new([
       a[3] / d, -a[1] / d,
      -a[2] / d,  a[0] / d
    ] ## T[4])

  # Matrix-matrix product (column-major).
  -> */1(Mat2)
    a = @elements
    b = @1.elements
    class.new([
      a[0] * b[0] + a[2] * b[1],   a[1] * b[0] + a[3] * b[1],
      a[0] * b[2] + a[2] * b[3],   a[1] * b[2] + a[3] * b[3]
    ] ## T[4])

  # Matrix-vector product.
  -> */1(Vec2)
    v = @1.components
    a = @elements
    Vec2.new([
      a[0] * v[0] + a[2] * v[1],
      a[1] * v[0] + a[3] * v[1]
    ] ## T[2])
