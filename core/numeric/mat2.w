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
    Vec2.new([elements[c * 2], elements[c * 2 + 1]] ## T[2])

  -> row(r)
    Vec2.new([elements[r], elements[2 + r]] ## T[2])

  # Linear algebra.

  -> transpose
    class.new([
      elements[0], elements[2],
      elements[1], elements[3]
    ] ## T[4])

  -> determinant
    elements[0] * elements[3] - elements[2] * elements[1]

  -> trace
    elements[0] + elements[3]

  # Inverse: (1/det) · [[ d, −b ], [ −c, a ]] for `[[a, b], [c, d]]`.
  -> inverse
    d = determinant
    class.new([
       elements[3] / d, -elements[1] / d,
      -elements[2] / d,  elements[0] / d
    ] ## T[4])

  # Matrix-matrix product (column-major).
  -> */1
    a = elements
    b = @1.elements
    class.new([
      a[0] * b[0] + a[2] * b[1],   a[1] * b[0] + a[3] * b[1],
      a[0] * b[2] + a[2] * b[3],   a[1] * b[2] + a[3] * b[3]
    ] ## T[4])

  # Matrix-vector product.
  -> */1
    v = @1.components
    Vec2.new([
      elements[0] * v[0] + elements[2] * v[1],
      elements[1] * v[0] + elements[3] * v[1]
    ] ## T[2])
