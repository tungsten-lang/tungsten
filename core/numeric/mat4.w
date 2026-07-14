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
    class.new([
      0 ## T, 0 ## T, 0 ## T, 0 ## T,
      0 ## T, 0 ## T, 0 ## T, 0 ## T,
      0 ## T, 0 ## T, 0 ## T, 0 ## T,
      0 ## T, 0 ## T, 0 ## T, 0 ## T
    ] ## T[16])

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
      @elements[c * 4],     @elements[c * 4 + 1],
      @elements[c * 4 + 2], @elements[c * 4 + 3]
    ] ## T[4])

  -> row(r)
    Vec4.new([
      @elements[r],     @elements[4 + r],
      @elements[8 + r], @elements[12 + r]
    ] ## T[4])

  # Fixed-width componentwise arithmetic avoids Matrix's map/zip temporaries.

  -> negate
    a = @elements
    class.new([
      -a[0], -a[1], -a[2], -a[3],
      -a[4], -a[5], -a[6], -a[7],
      -a[8], -a[9], -a[10], -a[11],
      -a[12], -a[13], -a[14], -a[15]
    ] ## T[16])

  -> +/1
    a = @elements
    b = @1.elements
    class.new([
      a[0] + b[0], a[1] + b[1], a[2] + b[2], a[3] + b[3],
      a[4] + b[4], a[5] + b[5], a[6] + b[6], a[7] + b[7],
      a[8] + b[8], a[9] + b[9], a[10] + b[10], a[11] + b[11],
      a[12] + b[12], a[13] + b[13], a[14] + b[14], a[15] + b[15]
    ] ## T[16])

  -> -/1
    a = @elements
    b = @1.elements
    class.new([
      a[0] - b[0], a[1] - b[1], a[2] - b[2], a[3] - b[3],
      a[4] - b[4], a[5] - b[5], a[6] - b[6], a[7] - b[7],
      a[8] - b[8], a[9] - b[9], a[10] - b[10], a[11] - b[11],
      a[12] - b[12], a[13] - b[13], a[14] - b[14], a[15] - b[15]
    ] ## T[16])

  -> //1(Number)
    a = @elements
    s = @1
    class.new([
      a[0] / s, a[1] / s, a[2] / s, a[3] / s,
      a[4] / s, a[5] / s, a[6] / s, a[7] / s,
      a[8] / s, a[9] / s, a[10] / s, a[11] / s,
      a[12] / s, a[13] / s, a[14] / s, a[15] / s
    ] ## T[16])

  -> ⊙/1
    a = @elements
    b = @1.elements
    class.new([
      a[0] * b[0], a[1] * b[1], a[2] * b[2], a[3] * b[3],
      a[4] * b[4], a[5] * b[5], a[6] * b[6], a[7] * b[7],
      a[8] * b[8], a[9] * b[9], a[10] * b[10], a[11] * b[11],
      a[12] * b[12], a[13] * b[13], a[14] * b[14], a[15] * b[15]
    ] ## T[16])

  # Linear algebra.

  -> transpose
    a = @elements
    class.new([
      a[0], a[4], a[8],  a[12],
      a[1], a[5], a[9],  a[13],
      a[2], a[6], a[10], a[14],
      a[3], a[7], a[11], a[15]
    ] ## T[16])

  -> trace
    a = @elements
    a[0] + a[5] + a[10] + a[15]

  # Determinant from six minors in each 2x4 half. Column-major
  # `M[col, row] = elements[col * 4 + row]`.
  -> determinant
    a = @elements
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
    b00 * b11 - b01 * b10 + b02 * b09 + b03 * b08 - b04 * b07 + b05 * b06

  # Inverse via cofactor / adjugate formula. Caller is responsible for
  # non-singularity. ~80 multiplies — for typed-float receivers this is
  # a target for `@llvm.matrix.multiply.*` and/or Accelerate lowering
  # in a follow-up.
  -> inverse
    a = @elements
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
    d = b00 * b11 - b01 * b10 + b02 * b09 + b03 * b08 - b04 * b07 + b05 * b06
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
    a = @elements
    Vec4.new([
      a[0] * v[0] + a[4] * v[1] + a[8]  * v[2] + a[12] * v[3],
      a[1] * v[0] + a[5] * v[1] + a[9]  * v[2] + a[13] * v[3],
      a[2] * v[0] + a[6] * v[1] + a[10] * v[2] + a[14] * v[3],
      a[3] * v[0] + a[7] * v[1] + a[11] * v[2] + a[15] * v[3]
    ] ## T[4])

  # Matrix-matrix product (column-major: result[c, r] = Σₖ A[k, r] · B[c, k]).
  # 64 multiplies / 48 adds. Target for SIMD `<4 x float>` and ultimately
  # `@llvm.matrix.multiply.f32.v16f32.v16f32` lowering.
  -> */1(Mat4)
    a = @elements
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
