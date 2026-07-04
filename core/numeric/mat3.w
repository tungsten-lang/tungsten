# Mat3 — 3×3 matrix. Column-major storage matching Metal's float3x3.
+ Mat3<T> < Matrix<T>
  - data
    T elements[9]

  -> new(@elements ## T[9])

  -> rows 3
  -> cols 3

  # Class methods.

  -> .identity
    class.new([
      1 ## T, 0 ## T, 0 ## T,
      0 ## T, 1 ## T, 0 ## T,
      0 ## T, 0 ## T, 1 ## T
    ] ## T[9])

  -> .zero
    class.new((0...9).map -> 0 ## T)

  # Column / row views.

  -> col(c)
    Vec3.new([elements[c * 3], elements[c * 3 + 1], elements[c * 3 + 2]] ## T[3])

  -> row(r)
    Vec3.new([elements[r], elements[3 + r], elements[6 + r]] ## T[3])

  # Linear algebra.

  -> transpose
    class.new([
      elements[0], elements[3], elements[6],
      elements[1], elements[4], elements[7],
      elements[2], elements[5], elements[8]
    ] ## T[9])

  # Determinant via cofactor expansion along column 0. Kept on one line:
  # Tungsten has no leading-operator line continuation, so a multiline form
  # would parse as three separate statements and return only the last term.
  -> determinant
    a = elements
    a[0] * (a[4] * a[8] - a[5] * a[7]) - a[1] * (a[3] * a[8] - a[5] * a[6]) + a[2] * (a[3] * a[7] - a[4] * a[6])

  -> trace
    elements[0] + elements[4] + elements[8]

  # Inverse via cofactor / adjugate formula. Caller is responsible
  # for non-singularity (determinant != 0). For column-major
  # `[[a, b, c], [d, e, f], [g, h, i]]` stored as
  # elements = [a, d, g, b, e, h, c, f, i]:
  #   inv = (1/det) · adjugate(M)
  -> inverse
    a = elements
    d = determinant
    # Cofactors at each (col, row) position.
    c00 =  (a[4] * a[8] - a[5] * a[7])
    c01 = -(a[3] * a[8] - a[5] * a[6])
    c02 =  (a[3] * a[7] - a[4] * a[6])
    c10 = -(a[1] * a[8] - a[2] * a[7])
    c11 =  (a[0] * a[8] - a[2] * a[6])
    c12 = -(a[0] * a[7] - a[1] * a[6])
    c20 =  (a[1] * a[5] - a[2] * a[4])
    c21 = -(a[0] * a[5] - a[2] * a[3])
    c22 =  (a[0] * a[4] - a[1] * a[3])
    # Adjugate = transpose(cofactor matrix); column-major store.
    class.new([
      c00 / d, c10 / d, c20 / d,
      c01 / d, c11 / d, c21 / d,
      c02 / d, c12 / d, c22 / d
    ] ## T[9])

  # Matrix-vector product.
  -> */1(Vec3)
    v = @1.components
    Vec3.new([
      elements[0] * v[0] + elements[3] * v[1] + elements[6] * v[2],
      elements[1] * v[0] + elements[4] * v[1] + elements[7] * v[2],
      elements[2] * v[0] + elements[5] * v[1] + elements[8] * v[2]
    ] ## T[3])

  # Matrix-matrix product (column-major: result[c, r] = Σₖ A[k, r] · B[c, k]).
  -> */1(Mat3)
    a = elements
    b = @1.elements
    class.new([
      a[0] * b[0] + a[3] * b[1] + a[6] * b[2],
      a[1] * b[0] + a[4] * b[1] + a[7] * b[2],
      a[2] * b[0] + a[5] * b[1] + a[8] * b[2],
      a[0] * b[3] + a[3] * b[4] + a[6] * b[5],
      a[1] * b[3] + a[4] * b[4] + a[7] * b[5],
      a[2] * b[3] + a[5] * b[4] + a[8] * b[5],
      a[0] * b[6] + a[3] * b[7] + a[6] * b[8],
      a[1] * b[6] + a[4] * b[7] + a[7] * b[8],
      a[2] * b[6] + a[5] * b[7] + a[8] * b[8]
    ] ## T[9])
