# Mat4 — 4×4 matrix. Column-major storage matching Metal's float4x4 —
# THE workhorse type for 3D affine transforms, projection matrices,
# bone-skinning, and most GPU linear algebra.
+ Mat4<T> < Matrix<T>
  - data
    T elements[16]

  -> new(@elements ## T[16])

  -> rows 4
  -> cols 4

  # Class methods.

  -> .identity
    class.new([
      1 ## T, 0 ## T, 0 ## T, 0 ## T,
      0 ## T, 1 ## T, 0 ## T, 0 ## T,
      0 ## T, 0 ## T, 1 ## T, 0 ## T,
      0 ## T, 0 ## T, 0 ## T, 1 ## T
    ] ## T[16])

  -> .zero
    class.new((0...16).map -> 0 ## T)

  # Affine translation: identity with the last column set to [tx, ty, tz, 1].
  -> .translation(tx, ty, tz)
    class.new([
      1 ## T, 0 ## T, 0 ## T, 0 ## T,
      0 ## T, 1 ## T, 0 ## T, 0 ## T,
      0 ## T, 0 ## T, 1 ## T, 0 ## T,
      tx,     ty,     tz,     1 ## T
    ] ## T[16])

  # Scale matrix (diagonal).
  -> .scale(sx, sy, sz)
    class.new([
      sx,     0 ## T, 0 ## T, 0 ## T,
      0 ## T, sy,     0 ## T, 0 ## T,
      0 ## T, 0 ## T, sz,     0 ## T,
      0 ## T, 0 ## T, 0 ## T, 1 ## T
    ] ## T[16])

  # Column / row views.

  -> col(c)
    Vec4.new([
      elements[c * 4],     elements[c * 4 + 1],
      elements[c * 4 + 2], elements[c * 4 + 3]
    ] ## T[4])

  -> row(r)
    Vec4.new([
      elements[r],     elements[4 + r],
      elements[8 + r], elements[12 + r]
    ] ## T[4])

  # Linear algebra.

  -> transpose
    class.new([
      elements[0], elements[4], elements[8],  elements[12],
      elements[1], elements[5], elements[9],  elements[13],
      elements[2], elements[6], elements[10], elements[14],
      elements[3], elements[7], elements[11], elements[15]
    ] ## T[16])

  -> trace
    elements[0] + elements[5] + elements[10] + elements[15]

  # Determinant via cofactor expansion along the first column.
  # Column-major `M[col, row] = elements[col * 4 + row]`.
  -> determinant
    a = elements
    # 2x2 sub-determinants of the bottom-right portion (rows 1-3, cols 1-3).
    # These get reused across cofactors.
    s0 = a[5]  * a[10] - a[9]  * a[6]
    s1 = a[5]  * a[14] - a[13] * a[6]
    s2 = a[9]  * a[14] - a[13] * a[10]
    s3 = a[1]  * a[10] - a[9]  * a[2]
    s4 = a[1]  * a[14] - a[13] * a[2]
    s5 = a[1]  * a[6]  - a[5]  * a[2]
    # 3x3 cofactors of the first row.
    c0 =  a[0]  * (s0 * a[15] - s1 * a[11] + s2 * a[7])
    c1 = -a[4]  * (s3 * a[15] - s4 * a[11] + (a[9]  * a[2]  - a[1]  * a[10]) * a[7])
    c2 =  a[8]  * (s5 * a[15] + (a[13] * a[2]  - a[1]  * a[14]) * a[7] + s4 * a[3])
    c3 = -a[12] * (s5 * a[11] + (a[9]  * a[2]  - a[1]  * a[10]) * a[7] + s3 * a[3])
    c0 + c1 + c2 + c3

  # Inverse via cofactor / adjugate formula. Caller is responsible for
  # non-singularity. ~80 multiplies — for typed-float receivers this is
  # a target for `@llvm.matrix.multiply.*` and/or Accelerate lowering
  # in a follow-up.
  -> inverse
    a = elements
    d = determinant
    # Compute the 16 cofactors via 2x2 sub-determinants.
    b00 = a[0] * a[5]  - a[1] * a[4]
    b01 = a[0] * a[6]  - a[2] * a[4]
    b02 = a[0] * a[7]  - a[3] * a[4]
    b03 = a[1] * a[6]  - a[2] * a[5]
    b04 = a[1] * a[7]  - a[3] * a[5]
    b05 = a[2] * a[7]  - a[3] * a[6]
    b06 = a[8] * a[13] - a[9] * a[12]
    b07 = a[8] * a[14] - a[10] * a[12]
    b08 = a[8] * a[15] - a[11] * a[12]
    b09 = a[9] * a[14] - a[10] * a[13]
    b10 = a[9] * a[15] - a[11] * a[13]
    b11 = a[10] * a[15] - a[11] * a[14]
    class.new([
      ( a[5] * b11 - a[6] * b10 + a[7] * b09) / d,
      (-a[1] * b11 + a[2] * b10 - a[3] * b09) / d,
      ( a[13] * b05 - a[14] * b04 + a[15] * b03) / d,
      (-a[9] * b05 + a[10] * b04 - a[11] * b03) / d,
      (-a[4] * b11 + a[6] * b08 - a[7] * b07) / d,
      ( a[0] * b11 - a[2] * b08 + a[3] * b07) / d,
      (-a[12] * b05 + a[14] * b02 - a[15] * b01) / d,
      ( a[8] * b05 - a[10] * b02 + a[11] * b01) / d,
      ( a[4] * b10 - a[5] * b08 + a[7] * b06) / d,
      (-a[0] * b10 + a[1] * b08 - a[3] * b06) / d,
      ( a[12] * b04 - a[13] * b02 + a[15] * b00) / d,
      (-a[8] * b04 + a[9] * b02 - a[11] * b00) / d,
      (-a[4] * b09 + a[5] * b07 - a[6] * b06) / d,
      ( a[0] * b09 - a[1] * b07 + a[2] * b06) / d,
      (-a[12] * b03 + a[13] * b01 - a[14] * b00) / d,
      ( a[8] * b03 - a[9] * b01 + a[10] * b00) / d
    ] ## T[16])

  # Matrix-vector product (column-major: result_i = Σⱼ M[i,j] · v[j]).
  -> */1(Vec4)
    v = @1.components
    Vec4.new([
      elements[0] * v[0] + elements[4] * v[1] + elements[8]  * v[2] + elements[12] * v[3],
      elements[1] * v[0] + elements[5] * v[1] + elements[9]  * v[2] + elements[13] * v[3],
      elements[2] * v[0] + elements[6] * v[1] + elements[10] * v[2] + elements[14] * v[3],
      elements[3] * v[0] + elements[7] * v[1] + elements[11] * v[2] + elements[15] * v[3]
    ] ## T[4])

  # Matrix-matrix product (column-major: result[c, r] = Σₖ A[k, r] · B[c, k]).
  # 64 multiplies / 48 adds. Target for SIMD `<4 x float>` and ultimately
  # `@llvm.matrix.multiply.f32.v16f32.v16f32` lowering.
  -> */1(Mat4)
    a = elements
    b = @1.elements
    class.new([
      a[0] * b[0]  + a[4] * b[1]  + a[8]  * b[2]  + a[12] * b[3],
      a[1] * b[0]  + a[5] * b[1]  + a[9]  * b[2]  + a[13] * b[3],
      a[2] * b[0]  + a[6] * b[1]  + a[10] * b[2]  + a[14] * b[3],
      a[3] * b[0]  + a[7] * b[1]  + a[11] * b[2]  + a[15] * b[3],
      a[0] * b[4]  + a[4] * b[5]  + a[8]  * b[6]  + a[12] * b[7],
      a[1] * b[4]  + a[5] * b[5]  + a[9]  * b[6]  + a[13] * b[7],
      a[2] * b[4]  + a[6] * b[5]  + a[10] * b[6]  + a[14] * b[7],
      a[3] * b[4]  + a[7] * b[5]  + a[11] * b[6]  + a[15] * b[7],
      a[0] * b[8]  + a[4] * b[9]  + a[8]  * b[10] + a[12] * b[11],
      a[1] * b[8]  + a[5] * b[9]  + a[9]  * b[10] + a[13] * b[11],
      a[2] * b[8]  + a[6] * b[9]  + a[10] * b[10] + a[14] * b[11],
      a[3] * b[8]  + a[7] * b[9]  + a[11] * b[10] + a[15] * b[11],
      a[0] * b[12] + a[4] * b[13] + a[8]  * b[14] + a[12] * b[15],
      a[1] * b[12] + a[5] * b[13] + a[9]  * b[14] + a[13] * b[15],
      a[2] * b[12] + a[6] * b[13] + a[10] * b[14] + a[14] * b[15],
      a[3] * b[12] + a[7] * b[13] + a[11] * b[14] + a[15] * b[15]
    ] ## T[16])
