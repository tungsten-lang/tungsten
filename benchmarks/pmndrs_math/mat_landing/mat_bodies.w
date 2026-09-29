######## core/numeric/mat4.w  (replace inverse, */1(Mat4), mul_into, */1(Vec4); add the rest)
  # Inverse via cofactor / adjugate formula. Caller is responsible for
  # non-singularity. Terms are in pmndrs/glMatrix order so no cofactor needs
  # a unary minus. TODO(compiler): `-x` on a typed float lowers to a boxed
  # w_neg call; once it lowers to fneg this ordering is cosmetic.
  # Bit-identical to the previous body.
  -> inverse
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
    d = b00 * b11 - b01 * b10 + b02 * b09 + b03 * b08 - b04 * b07 + b05 * b06
    class.new([
      (a[5] * b11 - a[6] * b10 + a[7] * b09) / d,
      (a[2] * b10 - a[1] * b11 - a[3] * b09) / d,
      (a[13] * b05 - a[14] * b04 + a[15] * b03) / d,
      (a[10] * b04 - a[9] * b05 - a[11] * b03) / d,
      (a[6] * b08 - a[4] * b11 - a[7] * b07) / d,
      (a[0] * b11 - a[2] * b08 + a[3] * b07) / d,
      (a[14] * b02 - a[12] * b05 - a[15] * b01) / d,
      (a[8] * b05 - a[10] * b02 + a[11] * b01) / d,
      (a[4] * b10 - a[5] * b08 + a[7] * b06) / d,
      (a[1] * b08 - a[0] * b10 - a[3] * b06) / d,
      (a[12] * b04 - a[13] * b02 + a[15] * b00) / d,
      (a[9] * b02 - a[8] * b04 - a[11] * b00) / d,
      (a[5] * b07 - a[4] * b09 - a[6] * b06) / d,
      (a[0] * b09 - a[1] * b07 + a[2] * b06) / d,
      (a[13] * b01 - a[12] * b03 - a[14] * b00) / d,
      (a[8] * b03 - a[9] * b01 + a[10] * b00) / d
    ] ## T[16])

  # Caller-owned output; loads every input first, so `m.inverse_into(m)`
  # (in-place) is safe.
  -> inverse_into/1(Mat4)
    a = @elements
    o = @1.elements
    m0 = a[0]
    m1 = a[1]
    m2 = a[2]
    m3 = a[3]
    m4 = a[4]
    m5 = a[5]
    m6 = a[6]
    m7 = a[7]
    m8 = a[8]
    m9 = a[9]
    m10 = a[10]
    m11 = a[11]
    m12 = a[12]
    m13 = a[13]
    m14 = a[14]
    m15 = a[15]
    b00 = m0 * m5  - m1 * m4
    b01 = m0 * m6  - m2 * m4
    b02 = m0 * m7  - m3 * m4
    b03 = m1 * m6  - m2 * m5
    b04 = m1 * m7  - m3 * m5
    b05 = m2 * m7  - m3 * m6
    b06 = m8 * m13 - m9 * m12
    b07 = m8 * m14 - m10 * m12
    b08 = m8 * m15 - m11 * m12
    b09 = m9 * m14 - m10 * m13
    b10 = m9 * m15 - m11 * m13
    b11 = m10 * m15 - m11 * m14
    d = b00 * b11 - b01 * b10 + b02 * b09 + b03 * b08 - b04 * b07 + b05 * b06
    o[0] = (m5 * b11 - m6 * b10 + m7 * b09) / d
    o[1] = (m2 * b10 - m1 * b11 - m3 * b09) / d
    o[2] = (m13 * b05 - m14 * b04 + m15 * b03) / d
    o[3] = (m10 * b04 - m9 * b05 - m11 * b03) / d
    o[4] = (m6 * b08 - m4 * b11 - m7 * b07) / d
    o[5] = (m0 * b11 - m2 * b08 + m3 * b07) / d
    o[6] = (m14 * b02 - m12 * b05 - m15 * b01) / d
    o[7] = (m8 * b05 - m10 * b02 + m11 * b01) / d
    o[8] = (m4 * b10 - m5 * b08 + m7 * b06) / d
    o[9] = (m1 * b08 - m0 * b10 - m3 * b06) / d
    o[10] = (m12 * b04 - m13 * b02 + m15 * b00) / d
    o[11] = (m9 * b02 - m8 * b04 - m11 * b00) / d
    o[12] = (m5 * b07 - m4 * b09 - m6 * b06) / d
    o[13] = (m0 * b09 - m1 * b07 + m2 * b06) / d
    o[14] = (m13 * b01 - m12 * b03 - m14 * b00) / d
    o[15] = (m8 * b03 - m9 * b01 + m10 * b00) / d
    @1

  # Matrix-matrix product (column-major). Every operand is loaded once into
  # a local before the result literal is built: the literal stores each
  # element as it is computed, which otherwise forces LLVM to reload the
  # operands after every store (117 loads for 32 values).
  -> */1(Mat4)
    a = @elements
    b = @1.elements
    m0 = a[0]
    m1 = a[1]
    m2 = a[2]
    m3 = a[3]
    m4 = a[4]
    m5 = a[5]
    m6 = a[6]
    m7 = a[7]
    m8 = a[8]
    m9 = a[9]
    m10 = a[10]
    m11 = a[11]
    m12 = a[12]
    m13 = a[13]
    m14 = a[14]
    m15 = a[15]
    n0 = b[0]
    n1 = b[1]
    n2 = b[2]
    n3 = b[3]
    n4 = b[4]
    n5 = b[5]
    n6 = b[6]
    n7 = b[7]
    n8 = b[8]
    n9 = b[9]
    n10 = b[10]
    n11 = b[11]
    n12 = b[12]
    n13 = b[13]
    n14 = b[14]
    n15 = b[15]
    class.new([
      m0 * n0 + m4 * n1 + m8 * n2 + m12 * n3,
      m1 * n0 + m5 * n1 + m9 * n2 + m13 * n3,
      m2 * n0 + m6 * n1 + m10 * n2 + m14 * n3,
      m3 * n0 + m7 * n1 + m11 * n2 + m15 * n3,
      m0 * n4 + m4 * n5 + m8 * n6 + m12 * n7,
      m1 * n4 + m5 * n5 + m9 * n6 + m13 * n7,
      m2 * n4 + m6 * n5 + m10 * n6 + m14 * n7,
      m3 * n4 + m7 * n5 + m11 * n6 + m15 * n7,
      m0 * n8 + m4 * n9 + m8 * n10 + m12 * n11,
      m1 * n8 + m5 * n9 + m9 * n10 + m13 * n11,
      m2 * n8 + m6 * n9 + m10 * n10 + m14 * n11,
      m3 * n8 + m7 * n9 + m11 * n10 + m15 * n11,
      m0 * n12 + m4 * n13 + m8 * n14 + m12 * n15,
      m1 * n12 + m5 * n13 + m9 * n14 + m13 * n15,
      m2 * n12 + m6 * n13 + m10 * n14 + m14 * n15,
      m3 * n12 + m7 * n13 + m11 * n14 + m15 * n15
    ] ## T[16])

  # Allocation-free matrix product for hot loops (pmndrs shape: all of `a`
  # in locals, one column of `b` at a time). `out` may alias either input.
  -> mul_into/2(Mat4 Mat4)
    a = @elements
    b = @1.elements
    o = @2.elements
    m0 = a[0]
    m1 = a[1]
    m2 = a[2]
    m3 = a[3]
    m4 = a[4]
    m5 = a[5]
    m6 = a[6]
    m7 = a[7]
    m8 = a[8]
    m9 = a[9]
    m10 = a[10]
    m11 = a[11]
    m12 = a[12]
    m13 = a[13]
    m14 = a[14]
    m15 = a[15]
    b0 = b[0]
    b1 = b[1]
    b2 = b[2]
    b3 = b[3]
    o[0] = m0 * b0 + m4 * b1 + m8 * b2 + m12 * b3
    o[1] = m1 * b0 + m5 * b1 + m9 * b2 + m13 * b3
    o[2] = m2 * b0 + m6 * b1 + m10 * b2 + m14 * b3
    o[3] = m3 * b0 + m7 * b1 + m11 * b2 + m15 * b3
    b0 = b[4]
    b1 = b[5]
    b2 = b[6]
    b3 = b[7]
    o[4] = m0 * b0 + m4 * b1 + m8 * b2 + m12 * b3
    o[5] = m1 * b0 + m5 * b1 + m9 * b2 + m13 * b3
    o[6] = m2 * b0 + m6 * b1 + m10 * b2 + m14 * b3
    o[7] = m3 * b0 + m7 * b1 + m11 * b2 + m15 * b3
    b0 = b[8]
    b1 = b[9]
    b2 = b[10]
    b3 = b[11]
    o[8] = m0 * b0 + m4 * b1 + m8 * b2 + m12 * b3
    o[9] = m1 * b0 + m5 * b1 + m9 * b2 + m13 * b3
    o[10] = m2 * b0 + m6 * b1 + m10 * b2 + m14 * b3
    o[11] = m3 * b0 + m7 * b1 + m11 * b2 + m15 * b3
    b0 = b[12]
    b1 = b[13]
    b2 = b[14]
    b3 = b[15]
    o[12] = m0 * b0 + m4 * b1 + m8 * b2 + m12 * b3
    o[13] = m1 * b0 + m5 * b1 + m9 * b2 + m13 * b3
    o[14] = m2 * b0 + m6 * b1 + m10 * b2 + m14 * b3
    o[15] = m3 * b0 + m7 * b1 + m11 * b2 + m15 * b3
    @2

  # Matrix-vector product. TODO(compiler): a `(Vec4)` annotation does not
  # type @1's components (the self type `(Mat4)` does), so each component is
  # read once and unboxed with `## T`; without it the body runs boxed.
  -> */1(Vec4)
    v = @1.components
    a = @elements
    x = v[0] ## T
    y = v[1] ## T
    z = v[2] ## T
    w = v[3] ## T
    Vec4.new([
      a[0] * x + a[4] * y + a[8]  * z + a[12] * w,
      a[1] * x + a[5] * y + a[9]  * z + a[13] * w,
      a[2] * x + a[6] * y + a[10] * z + a[14] * w,
      a[3] * x + a[7] * y + a[11] * z + a[15] * w
    ] ## T[4])

  # Caller-owned Vec4 output (may alias the input vector).
  -> mul_vec_into/2(Vec4 Vec4)
    v = @1.components
    o = @2.components
    a = @elements
    x = v[0] ## T
    y = v[1] ## T
    z = v[2] ## T
    w = v[3] ## T
    o[0] = a[0] * x + a[4] * y + a[8]  * z + a[12] * w
    o[1] = a[1] * x + a[5] * y + a[9]  * z + a[13] * w
    o[2] = a[2] * x + a[6] * y + a[10] * z + a[14] * w
    o[3] = a[3] * x + a[7] * y + a[11] * z + a[15] * w
    @2

  # Point transform: (x, y, z, 1) through the matrix, then divide by w
  # (w == 1 for affine matrices; projective matrices get the perspective
  # divide). pmndrs vec3.transformMat4.
  -> transform_point/1(Vec3)
    v = @1.components
    a = @elements
    x = v[0] ## T
    y = v[1] ## T
    z = v[2] ## T
    w = a[3] * x + a[7] * y + a[11] * z + a[15]
    Vec3.new([
      (a[0] * x + a[4] * y + a[8]  * z + a[12]) / w,
      (a[1] * x + a[5] * y + a[9]  * z + a[13]) / w,
      (a[2] * x + a[6] * y + a[10] * z + a[14]) / w
    ] ## T[3])

  # Direction transform: (x, y, z, 0) — the upper 3×3 only, translation ignored.
  -> transform_direction/1(Vec3)
    v = @1.components
    a = @elements
    x = v[0] ## T
    y = v[1] ## T
    z = v[2] ## T
    Vec3.new([
      a[0] * x + a[4] * y + a[8]  * z,
      a[1] * x + a[5] * y + a[9]  * z,
      a[2] * x + a[6] * y + a[10] * z
    ] ## T[3])

  # (optional — only 1.08x over the fixed general inverse)
  # Inverse of an affine matrix (last row 0 0 0 1 — caller guarantees):
  # invert the 3×3 linear part L, then translation' = L⁻¹·(−t).
  -> affine_inverse
    a = @elements
    c00 = a[5] * a[10] - a[6] * a[9]
    c01 = a[6] * a[8] - a[4] * a[10]
    c02 = a[4] * a[9] - a[5] * a[8]
    inv_det = ~1.0 / (a[0] * c00 + a[1] * c01 + a[2] * c02)
    r0 = c00 * inv_det
    r1 = (a[2] * a[9] - a[1] * a[10]) * inv_det
    r2 = (a[1] * a[6] - a[2] * a[5]) * inv_det
    r3 = c01 * inv_det
    r4 = (a[0] * a[10] - a[2] * a[8]) * inv_det
    r5 = (a[2] * a[4] - a[0] * a[6]) * inv_det
    r6 = c02 * inv_det
    r7 = (a[1] * a[8] - a[0] * a[9]) * inv_det
    r8 = (a[0] * a[5] - a[1] * a[4]) * inv_det
    nx = (0 ## T) - a[12]
    ny = (0 ## T) - a[13]
    nz = (0 ## T) - a[14]
    class.new([
      r0, r1, r2, 0 ## T,
      r3, r4, r5, 0 ## T,
      r6, r7, r8, 0 ## T,
      r0 * nx + r3 * ny + r6 * nz,
      r1 * nx + r4 * ny + r7 * nz,
      r2 * nx + r5 * ny + r8 * nz,
      1 ## T
    ] ## T[16])

  # translation(t) · rotation(q) · scale(s) in one pass (pmndrs
  # fromRotationTranslationScale). q need not be unit: k = 2/|q|² folds in
  # the normalization Quaternion#to_rotation_matrix performs. q is read
  # through its w/x/y/z accessors so QuaternionMetal (scalar-last) works too.
  -> .compose(t, q, s)
    w = q.w ## T
    x = q.x ## T
    y = q.y ## T
    z = q.z ## T
    sc = s.components
    sx = sc[0] ## T
    sy = sc[1] ## T
    sz = sc[2] ## T
    tc = t.components
    k = ~2.0 / (w * w + x * x + y * y + z * z)
    xk = x * k
    yk = y * k
    zk = z * k
    xx = x * xk
    xy = x * yk
    xz = x * zk
    yy = y * yk
    yz = y * zk
    zz = z * zk
    wx = w * xk
    wy = w * yk
    wz = w * zk
    class.new([
      (~1.0 - (yy + zz)) * sx, (xy + wz) * sx, (xz - wy) * sx, 0 ## T,
      (xy - wz) * sy, (~1.0 - (xx + zz)) * sy, (yz + wx) * sy, 0 ## T,
      (xz + wy) * sz, (yz - wx) * sz, (~1.0 - (xx + yy)) * sz, 0 ## T,
      tc[0] ## T, tc[1] ## T, tc[2] ## T, 1 ## T
    ] ## T[16])

  # Caller-owned transpose; loads everything first, so in-place is safe.
  -> transpose_into/1(Mat4)
    a = @elements
    o = @1.elements
    m0 = a[0]
    m1 = a[1]
    m2 = a[2]
    m3 = a[3]
    m4 = a[4]
    m5 = a[5]
    m6 = a[6]
    m7 = a[7]
    m8 = a[8]
    m9 = a[9]
    m10 = a[10]
    m11 = a[11]
    m12 = a[12]
    m13 = a[13]
    m14 = a[14]
    m15 = a[15]
    o[0] = m0
    o[1] = m4
    o[2] = m8
    o[3] = m12
    o[4] = m1
    o[5] = m5
    o[6] = m9
    o[7] = m13
    o[8] = m2
    o[9] = m6
    o[10] = m10
    o[11] = m14
    o[12] = m3
    o[13] = m7
    o[14] = m11
    o[15] = m15
    @1

######## core/numeric/mat3.w  (replace inverse, mul_into, */1(Vec3); add inverse_into, mul_vec_into)
  # Inverse via cofactor / adjugate formula; column-0 cofactors are shared
  # with the determinant. Terms are written without unary minus (see
  # Mat4#inverse TODO). Bit-identical to the previous body except that an
  # exactly-zero cofactor may now be +0 where it was -0.
  -> inverse
    a = @elements
    c00 = a[4] * a[8] - a[5] * a[7]
    c01 = a[5] * a[6] - a[3] * a[8]
    c02 = a[3] * a[7] - a[4] * a[6]
    d = a[0] * c00 + a[1] * c01 + a[2] * c02
    class.new([
      c00 / d,
      (a[2] * a[7] - a[1] * a[8]) / d,
      (a[1] * a[5] - a[2] * a[4]) / d,
      c01 / d,
      (a[0] * a[8] - a[2] * a[6]) / d,
      (a[2] * a[3] - a[0] * a[5]) / d,
      c02 / d,
      (a[1] * a[6] - a[0] * a[7]) / d,
      (a[0] * a[4] - a[1] * a[3]) / d
    ] ## T[9])

  # Caller-owned output; loads every input first, so in-place is safe.
  -> inverse_into/1(Mat3)
    a = @elements
    o = @1.elements
    m0 = a[0]
    m1 = a[1]
    m2 = a[2]
    m3 = a[3]
    m4 = a[4]
    m5 = a[5]
    m6 = a[6]
    m7 = a[7]
    m8 = a[8]
    c00 = m4 * m8 - m5 * m7
    c01 = m5 * m6 - m3 * m8
    c02 = m3 * m7 - m4 * m6
    d = m0 * c00 + m1 * c01 + m2 * c02
    o[0] = c00 / d
    o[1] = (m2 * m7 - m1 * m8) / d
    o[2] = (m1 * m5 - m2 * m4) / d
    o[3] = c01 / d
    o[4] = (m0 * m8 - m2 * m6) / d
    o[5] = (m2 * m3 - m0 * m5) / d
    o[6] = c02 / d
    o[7] = (m1 * m6 - m0 * m7) / d
    o[8] = (m0 * m4 - m1 * m3) / d
    @1

  # Allocation-free matrix product (pmndrs shape); `out` may alias either input.
  -> mul_into/2(Mat3 Mat3)
    a = @elements
    b = @1.elements
    o = @2.elements
    m0 = a[0]
    m1 = a[1]
    m2 = a[2]
    m3 = a[3]
    m4 = a[4]
    m5 = a[5]
    m6 = a[6]
    m7 = a[7]
    m8 = a[8]
    b0 = b[0]
    b1 = b[1]
    b2 = b[2]
    o[0] = m0 * b0 + m3 * b1 + m6 * b2
    o[1] = m1 * b0 + m4 * b1 + m7 * b2
    o[2] = m2 * b0 + m5 * b1 + m8 * b2
    b0 = b[3]
    b1 = b[4]
    b2 = b[5]
    o[3] = m0 * b0 + m3 * b1 + m6 * b2
    o[4] = m1 * b0 + m4 * b1 + m7 * b2
    o[5] = m2 * b0 + m5 * b1 + m8 * b2
    b0 = b[6]
    b1 = b[7]
    b2 = b[8]
    o[6] = m0 * b0 + m3 * b1 + m6 * b2
    o[7] = m1 * b0 + m4 * b1 + m7 * b2
    o[8] = m2 * b0 + m5 * b1 + m8 * b2
    @2

  # Matrix-vector product (see Mat4#*/1(Vec4) TODO on the `## T` reads).
  -> */1(Vec3)
    v = @1.components
    a = @elements
    x = v[0] ## T
    y = v[1] ## T
    z = v[2] ## T
    Vec3.new([
      a[0] * x + a[3] * y + a[6] * z,
      a[1] * x + a[4] * y + a[7] * z,
      a[2] * x + a[5] * y + a[8] * z
    ] ## T[3])

  # Caller-owned Vec3 output (may alias the input vector).
  -> mul_vec_into/2(Vec3 Vec3)
    v = @1.components
    o = @2.components
    a = @elements
    x = v[0] ## T
    y = v[1] ## T
    z = v[2] ## T
    o[0] = a[0] * x + a[3] * y + a[6] * z
    o[1] = a[1] * x + a[4] * y + a[7] * z
    o[2] = a[2] * x + a[5] * y + a[8] * z
    @2

######## core/numeric/mat2.w  (replace inverse)
  # Inverse: (1/det) · [[ d, −b ], [ −c, a ]] for `[[a, b], [c, d]]`. The
  # off-diagonal sign moves onto the divisor (-x/d == x/(-d) exactly), so no
  # unary minus (see Mat4#inverse TODO). Bit-identical to the previous body.
  -> inverse
    a = @elements
    d = a[0] * a[3] - a[2] * a[1]
    nd = (0 ## T) - d
    class.new([
      a[3] / d,  a[1] / nd,
      a[2] / nd, a[0] / d
    ] ## T[4])

