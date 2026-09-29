  -> +/1(Hypercomplex)
    a = @components
    b = @1.components
    b0 = b[0] ## T
    b1 = b[1] ## T
    b2 = b[2] ## T
    b3 = b[3] ## T
    class.new([a[0] + b0, a[1] + b1, a[2] + b2, a[3] + b3] ## T[4])

  -> +/1(Number)
    scalar_add(@1)

  -> -/1(Hypercomplex)
    a = @components
    b = @1.components
    b0 = b[0] ## T
    b1 = b[1] ## T
    b2 = b[2] ## T
    b3 = b[3] ## T
    class.new([a[0] - b0, a[1] - b1, a[2] - b2, a[3] - b3] ## T[4])

  -> -/1(Number)
    scalar_sub(@1)

  -> negate
    a = @components
    class.new([a[0] * ~-1.0, a[1] * ~-1.0, a[2] * ~-1.0, a[3] * ~-1.0] ## T[4])

  -> conjugate
    a = @components
    class.new([a[0], a[1] * ~-1.0, a[2] * ~-1.0, a[3] * ~-1.0] ## T[4])

  -> scale/1
    s = @1 ## T
    a = @components
    class.new([a[0] * s, a[1] * s, a[2] * s, a[3] * s] ## T[4])

  -> dot/1
    a = @components
    b = @1.components
    b0 = b[0] ## T
    b1 = b[1] ## T
    b2 = b[2] ## T
    b3 = b[3] ## T
    a[0] * b0 + a[1] * b1 + a[2] * b2 + a[3] * b3

  -> abs2
    a = @components
    a[0] * a[0] + a[1] * a[1] + a[2] * a[2] + a[3] * a[3]

  -> normalize
    a = @components
    n = a[0] * a[0] + a[1] * a[1] + a[2] * a[2] + a[3] * a[3]
    raise "cannot normalize zero hypercomplex value" if n == 0
    len = Math.sqrt(n)
    class.new([a[0] / len, a[1] / len, a[2] / len, a[3] / len] ## T[4])

  -> */1(Hypercomplex)
    a = @components
    b = @1.components
    a0 = a[0] ## T
    a1 = a[1] ## T
    a2 = a[2] ## T
    a3 = a[3] ## T
    b0 = b[0] ## T
    b1 = b[1] ## T
    b2 = b[2] ## T
    b3 = b[3] ## T
    class.new([
      a0 * b0 - a1 * b1 - a2 * b2 - a3 * b3,
      a0 * b1 + a1 * b0 + a2 * b3 - a3 * b2,
      a0 * b2 - a1 * b3 + a2 * b0 + a3 * b1,
      a0 * b3 + a1 * b2 - a2 * b1 + a3 * b0
    ] ## T[4])

  -> */1(Number)
    scale(@1)

  -> rotate/1
    a = @components
    qw = a[0] ## T
    qx = a[1] ## T
    qy = a[2] ## T
    qz = a[3] ## T
    n = qw * qw + qx * qx + qy * qy + qz * qz
    raise "cannot normalize zero hypercomplex value" if n == 0
    k = ~2.0 / n
    vx = @1.x ## T
    vy = @1.y ## T
    vz = @1.z ## T
    tx = k * (qy * vz - qz * vy)
    ty = k * (qz * vx - qx * vz)
    tz = k * (qx * vy - qy * vx)
    Vec3.new([
      vx + qw * tx + qy * tz - qz * ty,
      vy + qw * ty + qz * tx - qx * tz,
      vz + qw * tz + qx * ty - qy * tx
    ] ## T[3])

  -> to_rotation_matrix
    a = @components
    qw = a[0] ## T
    qx = a[1] ## T
    qy = a[2] ## T
    qz = a[3] ## T
    n = qw * qw + qx * qx + qy * qy + qz * qz
    raise "cannot normalize zero hypercomplex value" if n == 0
    k = ~2.0 / n
    xs = qx * k
    ys = qy * k
    zs = qz * k
    wx = qw * xs
    wy = qw * ys
    wz = qw * zs
    xx = qx * xs
    xy = qx * ys
    xz = qx * zs
    yy = qy * ys
    yz = qy * zs
    zz = qz * zs
    Mat3.new([
      ~1.0 - (yy + zz), xy + wz, xz - wy,
      xy - wz, ~1.0 - (xx + zz), yz + wx,
      xz + wy, yz - wx, ~1.0 - (xx + yy)
    ] ## T[9])

  -> slerp/2
    a = @components
    b = @1.components
    t = @2 ## T
    a0 = a[0] ## T
    a1 = a[1] ## T
    a2 = a[2] ## T
    a3 = a[3] ## T
    b0 = b[0] ## T
    b1 = b[1] ## T
    b2 = b[2] ## T
    b3 = b[3] ## T
    na = a0 * a0 + a1 * a1 + a2 * a2 + a3 * a3
    nb = b0 * b0 + b1 * b1 + b2 * b2 + b3 * b3
    raise "cannot normalize zero hypercomplex value" if na == 0 || nb == 0
    ia = ~1.0 / Math.sqrt(na)
    ib = ~1.0 / Math.sqrt(nb)
    d = (a0 * b0 + a1 * b1 + a2 * b2 + a3 * b3) * ia * ib
    if d < ~0.0
      d = ~0.0 - d
      ib = ~0.0 - ib
    if d > ~0.9995
      c0 = (~1.0 - t) * ia
      c1 = t * ib
      r0 = c0 * a0 + c1 * b0
      r1 = c0 * a1 + c1 * b1
      r2 = c0 * a2 + c1 * b2
      r3 = c0 * a3 + c1 * b3
      inv = ~1.0 / Math.sqrt(r0 * r0 + r1 * r1 + r2 * r2 + r3 * r3)
      return class.new([r0 * inv, r1 * inv, r2 * inv, r3 * inv] ## T[4])
    theta_0 = Math.acos(d)
    theta = theta_0 * t
    s1 = Math.sin(theta) / Math.sqrt((~1.0 - d) * (~1.0 + d))
    s0 = Math.cos(theta) - d * s1
    c0 = s0 * ia
    c1 = s1 * ib
    class.new([c0 * a0 + c1 * b0, c0 * a1 + c1 * b1, c0 * a2 + c1 * b2, c0 * a3 + c1 * b3] ## T[4])

  -> .from_rotation_matrix(matrix)
    m = matrix.elements
    m00 = m[0] ## T
    m01 = m[3] ## T
    m02 = m[6] ## T
    m10 = m[1] ## T
    m11 = m[4] ## T
    m12 = m[7] ## T
    m20 = m[2] ## T
    m21 = m[5] ## T
    m22 = m[8] ## T
    trace = m00 + m11 + m22
    q0 = ~0.0 ## T
    q1 = ~0.0 ## T
    q2 = ~0.0 ## T
    q3 = ~0.0 ## T
    if trace > ~0.0
      root = Math.sqrt(trace + ~1.0)
      r = ~0.5 / root
      q0 = ~0.5 * root
      q1 = (m21 - m12) * r
      q2 = (m02 - m20) * r
      q3 = (m10 - m01) * r
    elsif m00 > m11 && m00 > m22
      root = Math.sqrt(~1.0 + m00 - m11 - m22)
      r = ~0.5 / root
      q0 = (m21 - m12) * r
      q1 = ~0.5 * root
      q2 = (m01 + m10) * r
      q3 = (m02 + m20) * r
    elsif m11 > m22
      root = Math.sqrt(~1.0 + m11 - m00 - m22)
      r = ~0.5 / root
      q0 = (m02 - m20) * r
      q1 = (m01 + m10) * r
      q2 = ~0.5 * root
      q3 = (m12 + m21) * r
    else
      root = Math.sqrt(~1.0 + m22 - m00 - m11)
      r = ~0.5 / root
      q0 = (m10 - m01) * r
      q1 = (m02 + m20) * r
      q2 = (m12 + m21) * r
      q3 = ~0.5 * root
    inv = ~1.0 / Math.sqrt(q0 * q0 + q1 * q1 + q2 * q2 + q3 * q3)
    class.new([q0 * inv, q1 * inv, q2 * inv, q3 * inv] ## T[4])

  # Candidate 1: fixed-width overrides of the inherited Hypercomplex generics.

  -> put/4
    c = @components
    c[0] = @1 ## T
    c[1] = @2 ## T
    c[2] = @3 ## T
    c[3] = @4 ## T
    self

  -> mul_into/2
    a = @components
    b = @1.components
    a0 = a[0] ## T
    a1 = a[1] ## T
    a2 = a[2] ## T
    a3 = a[3] ## T
    b0 = b[0] ## T
    b1 = b[1] ## T
    b2 = b[2] ## T
    b3 = b[3] ## T
    @2.put(
      a0 * b0 - a1 * b1 - a2 * b2 - a3 * b3,
      a0 * b1 + a1 * b0 + a2 * b3 - a3 * b2,
      a0 * b2 - a1 * b3 + a2 * b0 + a3 * b1,
      a0 * b3 + a1 * b2 - a2 * b1 + a3 * b0
    )

  -> normalize_into/1
    a = @components
    a0 = a[0] ## T
    a1 = a[1] ## T
    a2 = a[2] ## T
    a3 = a[3] ## T
    n = a0 * a0 + a1 * a1 + a2 * a2 + a3 * a3
    raise "cannot normalize zero hypercomplex value" if n == 0
    len = Math.sqrt(n)
    @1.put(a0 / len, a1 / len, a2 / len, a3 / len)

  -> rotate_into/2
    a = @components
    qw = a[0] ## T
    qx = a[1] ## T
    qy = a[2] ## T
    qz = a[3] ## T
    n = qw * qw + qx * qx + qy * qy + qz * qz
    raise "cannot normalize zero hypercomplex value" if n == 0
    k = ~2.0 / n
    vx = @1.x ## T
    vy = @1.y ## T
    vz = @1.z ## T
    tx = k * (qy * vz - qz * vy)
    ty = k * (qz * vx - qx * vz)
    tz = k * (qx * vy - qy * vx)
    @2.put(
      vx + qw * tx + qy * tz - qz * ty,
      vy + qw * ty + qz * tx - qx * tz,
      vz + qw * tz + qx * ty - qy * tx
    )
