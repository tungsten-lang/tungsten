# Quaternion — dimension-4 hypercomplex algebra (basis: 1, i, j, k).
# Multiplication is non-commutative but associative.
#
# Storage is **scalar-FIRST** (math-natural, matching the recursive
# Cayley–Dickson `(a, b)` pair construction and the textbook reading
# `q = s + xi + yj + zk`):
#
#   components[0] = s (scalar / real part)
#   components[1] = x (i coefficient)
#   components[2] = y (j coefficient)
#   components[3] = z (k coefficient)
#
# For Metal GPU interop, see `QuaternionMetal<T>` — same algebra,
# scalar-LAST storage byte-aligned to `float4` where the scalar lives
# at `.w`. Convert with `Quaternion#to_metal` / `QuaternionMetal#to_math`.
#
# Literals:
#   %h4-f32[s x y z]      → Quaternion<f32>     (math, scalar-first)
#   %h4-float4[x y z w]   → QuaternionMetal<f32> (Metal, scalar-last)
+ Quaternion<T> < Hypercomplex<T>
  noncommutative :*

  - data
    T components[4]

  -> new(@components ## T[4])

  -> .dimension
    4

  -> .scalar_index
    0

  -> .zero
    class.new((0...4).map -> 0)

  -> .one
    class.new((0...4).map -> item == 0 ? 1 : 0)

  -> .basis(n)
    raise ArgumentError, "basis index out of range: [n]" if n < 0 || n >= 4
    class.new((0...4).map -> item == n ? 1 : 0)

  -> .real(value)
    class.new([value, 0, 0, 0] ## T[4])

  -> .pure(values)
    class.new([0, values[0], values[1], values[2]] ## T[4])

  -> .from_axis_angle(axis, angle)
    axis_length = Math.sqrt(axis.x * axis.x + axis.y * axis.y + axis.z * axis.z)
    raise ArgumentError, "cannot build rotation from zero axis" if axis_length == 0

    half = angle / ~2.0
    sin_half = Math.sin(half)
    scale = sin_half / axis_length
    class.new([
      Math.cos(half),
      axis.x * scale,
      axis.y * scale,
      axis.z * scale
    ] ## T[4])

  -> .from_rotation_matrix(matrix)
    m = matrix.elements
    m00 = m[0]
    m01 = m[3]
    m02 = m[6]
    m10 = m[1]
    m11 = m[4]
    m12 = m[7]
    m20 = m[2]
    m21 = m[5]
    m22 = m[8]
    trace = m00 + m11 + m22

    if trace > ~0.0
      s = Math.sqrt(trace + ~1.0) * ~2.0
      q = class.new([
        ~0.25 * s,
        (m21 - m12) / s,
        (m02 - m20) / s,
        (m10 - m01) / s
      ] ## T[4])
      return q.normalize
    elsif m00 > m11 && m00 > m22
      s = Math.sqrt(~1.0 + m00 - m11 - m22) * ~2.0
      q = class.new([
        (m21 - m12) / s,
        ~0.25 * s,
        (m01 + m10) / s,
        (m02 + m20) / s
      ] ## T[4])
      return q.normalize
    elsif m11 > m22
      s = Math.sqrt(~1.0 + m11 - m00 - m22) * ~2.0
      q = class.new([
        (m02 - m20) / s,
        (m01 + m10) / s,
        ~0.25 * s,
        (m12 + m21) / s
      ] ## T[4])
      return q.normalize
    else
      s = Math.sqrt(~1.0 + m22 - m00 - m11) * ~2.0
      q = class.new([
        (m10 - m01) / s,
        (m02 + m20) / s,
        (m12 + m21) / s,
        ~0.25 * s
      ] ## T[4])
      return q.normalize

  # Cayley–Dickson half: doubling Complex produces Quaternion.
  -> half_class
    Complex

  ## Scalar + 3-vector accessors (graphics convention; .w is the scalar,
  ## matching the standard `q = w + xi + yj + zk` reading. `.s` stays as
  ## a synonym for callers preferring "s for scalar".

  -> w
    components[0]
  -> s
    components[0]
  -> x
    components[1]
  -> y
    components[2]
  -> z
    components[3]

  ## Hamilton-basis accessors. The scalar is also reachable through
  ## the inherited `.real` (returns components[scalar_index] = [0]).

  -> i
    components[1]
  -> j
    components[2]
  -> k
    components[3]

  ## Cayley–Dickson basis accessors (.e0 is the scalar).

  -> e0
    components[0]
  -> e1
    components[1]
  -> e2
    components[2]
  -> e3
    components[3]

  ## Hamilton product, scalar-FIRST layout.
  ## (w₁, x₁, y₁, z₁) · (w₂, x₂, y₂, z₂) =
  ##   ( w₁w₂ − x₁x₂ − y₁y₂ − z₁z₂,
  ##     w₁x₂ + x₁w₂ + y₁z₂ − z₁y₂,
  ##     w₁y₂ − x₁z₂ + y₁w₂ + z₁x₂,
  ##     w₁z₂ + x₁y₂ − y₁x₂ + z₁w₂ )
  -> */1
    return scale(@1) if scalar_like?(@1)
    w1 = components[0]
    x1 = components[1]
    y1 = components[2]
    z1 = components[3]
    w2 = @1.components[0]
    x2 = @1.components[1]
    y2 = @1.components[2]
    z2 = @1.components[3]
    class.new([
      w1 * w2 - x1 * x2 - y1 * y2 - z1 * z2,
      w1 * x2 + x1 * w2 + y1 * z2 - z1 * y2,
      w1 * y2 - x1 * z2 + y1 * w2 + z1 * x2,
      w1 * z2 + x1 * y2 - y1 * x2 + z1 * w2
    ] ## T[4])

  ## Optimized squaring: q² = (w² − x² − y² − z², 2wx, 2wy, 2wz).
  ## Closed-form Hamilton squaring — ~10 mults vs general */1's ~28
  ## (64% fewer ops). Used by Octonion#sq through Cayley–Dickson recursion.
  -> sq
    class.new([
      w * w - x * x - y * y - z * z,
      2 * w * x,
      2 * w * y,
      2 * w * z
    ] ## T[4])

  # Quaternion exponential:
  # exp(w + v) = exp(w) * (cos(|v|) + v/|v| sin(|v|)).
  -> exp
    v_norm = Math.sqrt(x * x + y * y + z * z)
    exp_w = Math.exp(w)

    if v_norm == 0
      return class.new([exp_w, 0, 0, 0] ## T[4])

    v_scale = exp_w * Math.sin(v_norm) / v_norm
    class.new([
      exp_w * Math.cos(v_norm),
      x * v_scale,
      y * v_scale,
      z * v_scale
    ] ## T[4])

  # Quaternion logarithm:
  # log(q) = log(|q|) + v/|v| atan2(|v|, w).
  -> log
    magnitude = abs
    raise "cannot take log of zero quaternion" if magnitude == 0

    v_norm = Math.sqrt(x * x + y * y + z * z)
    if v_norm == 0
      return class.new([Math.log(magnitude), 0, 0, 0] ## T[4])

    v_scale = Math.atan2(v_norm, w) / v_norm
    class.new([
      Math.log(magnitude),
      x * v_scale,
      y * v_scale,
      z * v_scale
    ] ## T[4])

  # Return `[axis, angle]`, where axis is a unit Vec3 and angle is radians.
  -> to_axis_angle
    q = normalize
    scalar = q.w
    scalar = ~1.0 if scalar > ~1.0
    scalar = ~-1.0 if scalar < ~-1.0

    angle = ~2.0 * Math.acos(scalar)
    sin_half = Math.sqrt(~1.0 - scalar * scalar)
    if sin_half <= ~0.000001
      return [Vec3.new([~1.0, ~0.0, ~0.0] ## T[3]), angle]

    [
      Vec3.new([q.x / sin_half, q.y / sin_half, q.z / sin_half] ## T[3]),
      angle
    ]

  # Rotate a Vec3 by this quaternion. Non-unit quaternions are normalized
  # first so callers get rotation semantics rather than scale + rotation.
  -> rotate/1
    q = normalize
    vx = @1.x
    vy = @1.y
    vz = @1.z

    tx = ~2.0 * (q.y * vz - q.z * vy)
    ty = ~2.0 * (q.z * vx - q.x * vz)
    tz = ~2.0 * (q.x * vy - q.y * vx)

    Vec3.new([
      vx + q.w * tx + q.y * tz - q.z * ty,
      vy + q.w * ty + q.z * tx - q.x * tz,
      vz + q.w * tz + q.x * ty - q.y * tx
    ] ## T[3])

  -> slerp/2
    a = normalize
    b = @1.normalize
    dot = a.dot(b)

    if dot < ~0.0
      b = -b
      dot = -dot

    if dot > ~0.9995
      result = a + (b - a).scale(@2)
      return result.normalize

    theta_0 = Math.acos(dot)
    theta = theta_0 * @2
    sin_theta = Math.sin(theta)
    sin_theta_0 = Math.sin(theta_0)
    scale0 = Math.cos(theta) - dot * sin_theta / sin_theta_0
    scale1 = sin_theta / sin_theta_0
    a.scale(scale0) + b.scale(scale1)

  # Column-major Mat3 compatible with Mat3#*/1(Vec3).
  -> to_rotation_matrix
    q = normalize
    xx = q.x * q.x
    yy = q.y * q.y
    zz = q.z * q.z
    xy = q.x * q.y
    xz = q.x * q.z
    yz = q.y * q.z
    wx = q.w * q.x
    wy = q.w * q.y
    wz = q.w * q.z

    Mat3.new([
      ~1.0 - ~2.0 * (yy + zz),
      ~2.0 * (xy + wz),
      ~2.0 * (xz - wy),
      ~2.0 * (xy - wz),
      ~1.0 - ~2.0 * (xx + zz),
      ~2.0 * (yz + wx),
      ~2.0 * (xz + wy),
      ~2.0 * (yz - wx),
      ~1.0 - ~2.0 * (xx + yy)
    ] ## T[9])

  ## Conversion to Metal-layout form (scalar moves from index 0 to
  ## index 3, matching `float4.w`). Lowers to a single SIMD shuffle.
  -> to_metal
    QuaternionMetal.new([components[1], components[2], components[3], components[0]] ## T[4])
