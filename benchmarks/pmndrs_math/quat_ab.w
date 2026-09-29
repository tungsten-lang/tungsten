# quat_ab.w — A/B of pmndrs/math-inspired Quaternion bodies.
#
# Three controls run today's code: `<op>_core` uses plain Quaternion<f64>
# receivers (exactly today's core), `<op>_base` uses QuatBase<T> (a subclass
# inheriting everything), and `<op>_copy` uses QuatCopy<T> (quaternion.w's
# bodies copied verbatim). They agree to within ~2% instr/op; ratios in the
# report are vs `_core`. QuatFast<T> overrides the bodies with candidates
# written as they would land in core/numeric/hypercomplex/quaternion.w.
# Variant names are the `if mode == ...` blocks at the bottom. The extra
# classes (QuatGuard, QuatNoCheck, QuatIsA, QuatHoist, QuatTyped) exist only
# to A/B operator variants, since an operator has one body per class.
# Vec3Out stands in for a Vec3#put/3 that rotate_into would need in core.
#
# Every benchmark subclass REDECLARES `- data T components[4]`. Without it a
# subclass body sees `@components` as an untyped value: each `a[i]` becomes a
# dynamic `[]` call and every flop a boxed op (about 2800 vs 48 instr for a
# 4-term sum of squares). Inside Quaternion itself, where core declares the
# block, the same body gets typed loads. The redeclaration therefore makes
# QuatFast compile its bodies the way core would. It shares the parent's
# field at the same offset, and every benchmark class carries it so all
# of them have the same layout. To measure the as-specified (no
# redeclaration) build, strip the blocks:
#
#   python3 -c "import sys; s=open(sys.argv[1]).read(); \
#     open(sys.argv[2],'w').write(s.replace('  - data\n    T components[4]\n\n', ''))" \
#     benchmarks/pmndrs_math/quat_ab.w /tmp/quat_ab_untyped.w
#
# Build and run (release only; plain -o is -O0):
#
#   bin/tungsten --release -o /tmp/quat_ab benchmarks/pmndrs_math/quat_ab.w
#   /tmp/quat_ab verify 0                      # numeric agreement report
#   benchmarks/pmndrs_math/ab.py /tmp/quat_ab 1000000 5 norm_core norm_fast
#
# Compiler pitfalls these bodies avoid:
#   - In a T=f32 specialization, `a0 = a[0]` (a local taken from a typed
#     array load, then used in arithmetic) emits invalid LLVM IR ("defined
#     with type 'i64' but expected 'float'"). Writing `a0 = a[0] ## T` is
#     correct for every T and costs nothing for f64.
#   - Any `Generic<T>` class reference, not just `.new`, inside an `elsif`
#     arm resolves to nil. The timed section uses separate `if` blocks.
#   - Unary minus on a typed T value lowers to a boxed w_neg call (about 64
#     instr each). QuatFast writes `x * ~-1.0` or `~0.0 - x` (exact where
#     used) and keeps `*_unary` variants to attribute that cost.
#   - A parameter annotated with a generic type, `-> f/1(Vec3<T>)`, binds
#     the wrong value (`@1.x` returns the class). Bodies here never use
#     `(X<T>)` annotations.
#   - A same-class typed overload `-> */1(Quaternion)` gets typed loads for
#     the operand, but the dispatch guard ignores T: Quaternion<f64> *
#     Quaternion<f32> reads the f32 buffer as f64 and returns garbage (NaN
#     or ~1e200). QuatTyped and mul_into_typed only measure that upper
#     bound; they must not land. A `(Hypercomplex)` annotation is safe: that
#     class has no data block, so the operand's loads stay dynamic.

+ QuatBase<T> < Quaternion<T>
  - data
    T components[4]

  -> ab_tag
    0

# Control: today's quaternion.w bodies copied verbatim (comments, the
# constructor and the data block dropped), so Quaternion-defined methods
# run on a receiver of their defining class, as they do in core.
# Hypercomplex-defined methods stay inherited, as in core.
+ QuatCopy<T> < Quaternion<T>
  noncommutative :*

  - data
    T components[4]

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

  -> half_class
    Complex

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

  -> i
    components[1]
  -> j
    components[2]
  -> k
    components[3]

  -> e0
    components[0]
  -> e1
    components[1]
  -> e2
    components[2]
  -> e3
    components[3]

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

  -> sq
    class.new([
      w * w - x * x - y * y - z * z,
      2 * w * x,
      2 * w * y,
      2 * w * z
    ] ## T[4])

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

  -> to_metal
    QuaternionMetal.new([components[1], components[2], components[3], components[0]] ## T[4])

+ QuatFast<T> < Quaternion<T>
  - data
    T components[4]

  # Candidate 6: Shoemake with r = 0.5 / root multiplies and no trailing
  # normalize (pmndrs fromMat3). Branch selection is the same as today's.
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
    if trace > ~0.0
      root = Math.sqrt(trace + ~1.0)
      r = ~0.5 / root
      return class.new([~0.5 * root, (m21 - m12) * r, (m02 - m20) * r, (m10 - m01) * r] ## T[4])
    if m00 > m11 && m00 > m22
      root = Math.sqrt(~1.0 + m00 - m11 - m22)
      r = ~0.5 / root
      return class.new([(m21 - m12) * r, ~0.5 * root, (m01 + m10) * r, (m02 + m20) * r] ## T[4])
    if m11 > m22
      root = Math.sqrt(~1.0 + m11 - m00 - m22)
      r = ~0.5 / root
      return class.new([(m02 - m20) * r, (m01 + m10) * r, ~0.5 * root, (m12 + m21) * r] ## T[4])
    root = Math.sqrt(~1.0 + m22 - m00 - m11)
    r = ~0.5 / root
    class.new([(m10 - m01) * r, (m02 + m20) * r, (m12 + m21) * r, ~0.5 * root] ## T[4])

  # Candidate 6b: the same Shoemake form, keeping today's unit-output
  # guarantee through one inline sqrt and reciprocal.
  -> .from_rotation_matrix_normalized(matrix)
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

  # The scalar guard is a (Hypercomplex) / (Number) overload pair, not
  # `scalar_like?`: dispatch uses the runtime is_a test (~250 instr) where
  # the respond_to?("components") call cost ~2000. The operand stays
  # untyped (Hypercomplex has no data block), so `## T` converts mixed-T
  # operands correctly.
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

  # TODO: unary minus on a typed T value lowers to a boxed w_neg call (a
  # compiler bug); `x * ~-1.0` is the same IEEE negation (signed zeros
  # included) as a native fmul. Revert to `-x` once the lowering is fixed.
  -> negate
    a = @components
    class.new([a[0] * ~-1.0, a[1] * ~-1.0, a[2] * ~-1.0, a[3] * ~-1.0] ## T[4])

  -> conjugate
    a = @components
    class.new([a[0], a[1] * ~-1.0, a[2] * ~-1.0, a[3] * ~-1.0] ## T[4])

  # The natural spellings, to attribute the w_neg cost.
  -> negate_unary
    a = @components
    class.new([-a[0], -a[1], -a[2], -a[3]] ## T[4])

  -> conjugate_unary
    a = @components
    class.new([a[0], -a[1], -a[2], -a[3]] ## T[4])

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

  # One sqrt, one divide, four multiplies.
  -> normalize
    a = @components
    n = a[0] * a[0] + a[1] * a[1] + a[2] * a[2] + a[3] * a[3]
    raise "cannot normalize zero hypercomplex value" if n == 0
    inv = ~1.0 / Math.sqrt(n)
    class.new([a[0] * inv, a[1] * inv, a[2] * inv, a[3] * inv] ## T[4])

  # Latency A/B partner for normalize: four divides by the norm.
  -> normalize_div
    a = @components
    n = a[0] * a[0] + a[1] * a[1] + a[2] * a[2] + a[3] * a[3]
    raise "cannot normalize zero hypercomplex value" if n == 0
    len = Math.sqrt(n)
    class.new([a[0] / len, a[1] / len, a[2] / len, a[3] / len] ## T[4])

  # Candidate 2: Hamilton product with all eight scalars loaded once.
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

  # Candidate 3: rotate by q/|q| with no normalized temporary. With
  # n = |q|^2, t = (2/n)(q_v x v) and v' = v + w t + q_v x t is exactly
  # today's formula applied to q/|q|, with no sqrt.
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

  # Candidate 3b: pmndrs transformQuat semantics, assumes |q| = 1.
  -> rotate_unit/1
    a = @components
    qw = a[0] ## T
    qx = a[1] ## T
    qy = a[2] ## T
    qz = a[3] ## T
    vx = @1.x ## T
    vy = @1.y ## T
    vz = @1.z ## T
    tx = ~2.0 * (qy * vz - qz * vy)
    ty = ~2.0 * (qz * vx - qx * vz)
    tz = ~2.0 * (qx * vy - qy * vx)
    Vec3.new([
      vx + qw * tx + qy * tz - qz * ty,
      vy + qw * ty + qz * tx - qx * tz,
      vz + qw * tz + qx * ty - qy * tx
    ] ## T[3])

  # Candidate 4: Shoemake s = 2/n, no normalized temporary.
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

  # Candidate 5: one dot on raw components, sign flip on locals, one
  # allocation. Keeps today's semantics: inputs are normalized (through
  # 1/|a| and 1/|b| folded into the coefficients), and the 0.9995 nlerp
  # branch still renormalizes. The flip is written `~0.0 - d` (exact: d < 0,
  # ib > 0) because `-d` lowers to boxed w_neg (see negate's TODO).
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
    s1 = Math.sin(theta) / Math.sin(theta_0)
    s0 = Math.cos(theta) - d * s1
    c0 = s0 * ia
    c1 = s1 * ib
    class.new([c0 * a0 + c1 * b0, c0 * a1 + c1 * b1, c0 * a2 + c1 * b2, c0 * a3 + c1 * b3] ## T[4])

  # slerp with `-d` / `-ib`, to attribute the w_neg cost.
  -> slerp_unary/2
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
      d = -d
      ib = -ib
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
    s1 = Math.sin(theta) / Math.sin(theta_0)
    s0 = Math.cos(theta) - d * s1
    c0 = s0 * ia
    c1 = s1 * ib
    class.new([c0 * a0 + c1 * b0, c0 * a1 + c1 * b1, c0 * a2 + c1 * b2, c0 * a3 + c1 * b3] ## T[4])

  # Candidate 5b: slerp with sin(theta_0) = sqrt((1 - d)(1 + d)), which
  # drops one transcendental call. 1 - d is exact for d in [0.5, 1].
  -> slerp_sqrt/2
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

  # Candidate 5c: assumes |a| = |b| = 1, like pmndrs slerp; keeps the
  # 0.9995 renormalized-nlerp branch.
  -> slerp_unit/2
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
    d = a0 * b0 + a1 * b1 + a2 * b2 + a3 * b3
    sign = ~1.0 ## T
    if d < ~0.0
      d = ~0.0 - d
      sign = ~-1.0 ## T
    if d > ~0.9995
      c0 = ~1.0 - t
      c1 = t * sign
      r0 = c0 * a0 + c1 * b0
      r1 = c0 * a1 + c1 * b1
      r2 = c0 * a2 + c1 * b2
      r3 = c0 * a3 + c1 * b3
      inv = ~1.0 / Math.sqrt(r0 * r0 + r1 * r1 + r2 * r2 + r3 * r3)
      return class.new([r0 * inv, r1 * inv, r2 * inv, r3 * inv] ## T[4])
    theta_0 = Math.acos(d)
    theta = theta_0 * t
    s1 = Math.sin(theta) / Math.sin(theta_0)
    c0 = Math.cos(theta) - d * s1
    c1 = s1 * sign
    class.new([c0 * a0 + c1 * b0, c0 * a1 + c1 * b1, c0 * a2 + c1 * b2, c0 * a3 + c1 * b3] ## T[4])

  # Candidate 7: caller-owned outputs. Every input scalar is read before
  # the first store, so `out` may alias either input.
  #
  # `put/4` stores four scalars into this quaternion's own typed buffer.
  # It is sound for any out T (`## T` converts) and needs one dynamic call,
  # where writing through `o = @2.components; o[i] = ...` needs four.
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

  # Writes through the out Vec3's own put/3 (Vec3Out below stands in for
  # a core Vec3#put/3).
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

  # Direct stores through the out's components array: four dynamic []=.
  -> mul_into_store/2
    a = @components
    b = @1.components
    o = @2.components
    a0 = a[0] ## T
    a1 = a[1] ## T
    a2 = a[2] ## T
    a3 = a[3] ## T
    b0 = b[0] ## T
    b1 = b[1] ## T
    b2 = b[2] ## T
    b3 = b[3] ## T
    o[0] = a0 * b0 - a1 * b1 - a2 * b2 - a3 * b3
    o[1] = a0 * b1 + a1 * b0 + a2 * b3 - a3 * b2
    o[2] = a0 * b2 - a1 * b3 + a2 * b0 + a3 * b1
    o[3] = a0 * b3 + a1 * b2 - a2 * b1 + a3 * b0
    @2

  # Upper bound only: typed params make @1/@2 loads and stores typed, but
  # the guard ignores T (see header).
  -> mul_into_typed/2(QuatFast QuatFast)
    a = @components
    b = @1.components
    o = @2.components
    a0 = a[0] ## T
    a1 = a[1] ## T
    a2 = a[2] ## T
    a3 = a[3] ## T
    b0 = b[0] ## T
    b1 = b[1] ## T
    b2 = b[2] ## T
    b3 = b[3] ## T
    o[0] = a0 * b0 - a1 * b1 - a2 * b2 - a3 * b3
    o[1] = a0 * b1 + a1 * b0 + a2 * b3 - a3 * b2
    o[2] = a0 * b2 - a1 * b3 + a2 * b0 + a3 * b1
    o[3] = a0 * b3 + a1 * b2 - a2 * b1 + a3 * b0
    @2

  -> normalize_into_store/1
    a = @components
    o = @1.components
    a0 = a[0] ## T
    a1 = a[1] ## T
    a2 = a[2] ## T
    a3 = a[3] ## T
    n = a0 * a0 + a1 * a1 + a2 * a2 + a3 * a3
    raise "cannot normalize zero hypercomplex value" if n == 0
    inv = ~1.0 / Math.sqrt(n)
    o[0] = a0 * inv
    o[1] = a1 * inv
    o[2] = a2 * inv
    o[3] = a3 * inv
    @1

  -> rotate_into_store/2
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
    o = @2.components
    o[0] = vx + qw * tx + qy * tz - qz * ty
    o[1] = vy + qw * ty + qz * tx - qx * tz
    o[2] = vz + qw * tz + qx * ty - qy * tx
    @2

# Stand-in for a core Vec3#put/3 (rotate_into's out parameter).
+ Vec3Out<T> < Vec3<T>
  - data
    T components[3]

  -> put/3
    c = @components
    c[0] = @1 ## T
    c[1] = @2 ## T
    c[2] = @3 ## T
    self

# The same bodies behind today's `return ... if scalar_like?(@1)` guard.
+ QuatGuard<T> < Quaternion<T>
  - data
    T components[4]

  -> +/1
    return scalar_add(@1) if scalar_like?(@1)
    a = @components
    b = @1.components
    b0 = b[0] ## T
    b1 = b[1] ## T
    b2 = b[2] ## T
    b3 = b[3] ## T
    class.new([a[0] + b0, a[1] + b1, a[2] + b2, a[3] + b3] ## T[4])

  -> */1
    return scale(@1) if scalar_like?(@1)
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

# No guard at all (unsafe for scalars; measures the guard's cost).
+ QuatNoCheck<T> < Quaternion<T>
  - data
    T components[4]

  -> +/1
    a = @components
    b = @1.components
    b0 = b[0] ## T
    b1 = b[1] ## T
    b2 = b[2] ## T
    b3 = b[3] ## T
    class.new([a[0] + b0, a[1] + b1, a[2] + b2, a[3] + b3] ## T[4])

  -> */1
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

# The guard spelled as an is_a? test instead of respond_to?("components").
+ QuatIsA<T> < Quaternion<T>
  - data
    T components[4]

  -> +/1
    return scalar_add(@1) if !@1.is_a?(Hypercomplex)
    a = @components
    b = @1.components
    b0 = b[0] ## T
    b1 = b[1] ## T
    b2 = b[2] ## T
    b3 = b[3] ## T
    class.new([a[0] + b0, a[1] + b1, a[2] + b2, a[3] + b3] ## T[4])

  -> */1
    return scale(@1) if !@1.is_a?(Hypercomplex)
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

# Candidate 2, literally: hoist a = @components / b = @1.components and
# load each scalar once, without unboxing the other operand's scalars.
+ QuatHoist<T> < Quaternion<T>
  - data
    T components[4]

  -> +/1
    return scalar_add(@1) if scalar_like?(@1)
    a = @components
    b = @1.components
    class.new([a[0] + b[0], a[1] + b[1], a[2] + b[2], a[3] + b[3]] ## T[4])

  -> */1
    return scale(@1) if scalar_like?(@1)
    a = @components
    b = @1.components
    a0 = a[0] ## T
    a1 = a[1] ## T
    a2 = a[2] ## T
    a3 = a[3] ## T
    b0 = b[0]
    b1 = b[1]
    b2 = b[2]
    b3 = b[3]
    class.new([
      a0 * b0 - a1 * b1 - a2 * b2 - a3 * b3,
      a0 * b1 + a1 * b0 + a2 * b3 - a3 * b2,
      a0 * b2 - a1 * b3 + a2 * b0 + a3 * b1,
      a0 * b3 + a1 * b2 - a2 * b1 + a3 * b0
    ] ## T[4])

# Upper bound only: same-class typed overloads. They are fast but not safe
# with mixed T (see header), so they must not land.
+ QuatTyped<T> < Quaternion<T>
  - data
    T components[4]

  -> +/1(QuatTyped)
    a = @components
    b = @1.components
    class.new([a[0] + b[0], a[1] + b[1], a[2] + b[2], a[3] + b[3]] ## T[4])

  -> +/1(Number)
    scalar_add(@1)

  -> */1(QuatTyped)
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

# ---------------------------------------------------------------------------
# Numeric agreement (mode "verify"). Each line reports the max relative
# difference vs the control: max_i |ctl_i - cand_i| / max_i |ctl_i|.
# 999 marks a NaN.

-> maxf(p, q)
  p > q ? p : q

-> rel_arr(pc, qc, count)
  num = ~0.0
  den = ~0.0
  i = 0
  while i < count
    d = (pc[i] - qc[i]).abs
    num = d if d > num
    num = ~999.0 if !(d >= ~0.0)
    m = pc[i].abs
    den = m if m > den
    i += 1
  den > ~0.0 ? num / den : num

-> rel_q(p, q)
  rel_arr(p.components, q.components, 4)

-> rel_v(p, q)
  rel_arr(p.components, q.components, 3)

-> rel_m(p, q)
  rel_arr(p.elements, q.elements, 9)

-> rel_s(p, q)
  d = (p - q).abs
  return ~999.0 if !(d >= ~0.0)
  m = p.abs
  m > ~0.0 ? d / m : d

-> comp(i, j)
  Math.sin(~1.7 * i + ~2.3 * j + ~0.37 * i * j + ~0.1)

-> mag(i)
  ms = [~0.001, ~0.1, ~1.0, ~7.5, ~1000.0]
  ms[i % 5]

-> qb(i, s)
  QuatBase<f64>.new([comp(i, 0) * s, comp(i, 1) * s, comp(i, 2) * s, comp(i, 3) * s] ## f64[4])

-> qf(i, s)
  QuatFast<f64>.new([comp(i, 0) * s, comp(i, 1) * s, comp(i, 2) * s, comp(i, 3) * s] ## f64[4])

-> vec(i, s)
  Vec3<f64>.new([comp(i, 5) * s, comp(i, 6) * s, comp(i, 7) * s] ## f64[3])

-> fast_of(q)
  QuatFast<f64>.new([q.w, q.x, q.y, q.z] ## f64[4])

-> base_of(q)
  QuatBase<f64>.new([q.w, q.x, q.y, q.z] ## f64[4])

-> report(name, err, count)
  << "verify " + name + " max_rel " + err.to_s + " n " + count.to_s

-> verify_basic(n)
  e = (0...28).map -> ~0.0
  out = QuatFast<f64>.new([~0.0, ~0.0, ~0.0, ~0.0] ## f64[4])
  i = 0
  while i < n
    b1 = qb(i, mag(i))
    b2 = qb(i + 101, mag(i / 5))
    f1 = qf(i, mag(i))
    f2 = qf(i + 101, mag(i / 5))
    nc1 = QuatNoCheck<f64>.new([f1.w, f1.x, f1.y, f1.z] ## f64[4])
    nc2 = QuatNoCheck<f64>.new([f2.w, f2.x, f2.y, f2.z] ## f64[4])
    ia1 = QuatIsA<f64>.new([f1.w, f1.x, f1.y, f1.z] ## f64[4])
    ia2 = QuatIsA<f64>.new([f2.w, f2.x, f2.y, f2.z] ## f64[4])
    h1 = QuatHoist<f64>.new([f1.w, f1.x, f1.y, f1.z] ## f64[4])
    h2 = QuatHoist<f64>.new([f2.w, f2.x, f2.y, f2.z] ## f64[4])
    t1 = QuatTyped<f64>.new([f1.w, f1.x, f1.y, f1.z] ## f64[4])
    t2 = QuatTyped<f64>.new([f2.w, f2.x, f2.y, f2.z] ## f64[4])
    g1 = QuatGuard<f64>.new([f1.w, f1.x, f1.y, f1.z] ## f64[4])
    g2 = QuatGuard<f64>.new([f2.w, f2.x, f2.y, f2.z] ## f64[4])
    sc = comp(i, 9) * ~3.0
    e[0] = maxf(e[0], rel_q(b1 + b2, f1 + f2))
    e[1] = maxf(e[1], rel_q(b1 - b2, f1 - f2))
    e[2] = maxf(e[2], rel_q(b1.negate, f1.negate))
    e[3] = maxf(e[3], rel_q(b1.scale(sc), f1.scale(sc)))
    e[4] = maxf(e[4], rel_s(b1.dot(b2), f1.dot(f2)))
    e[5] = maxf(e[5], rel_s(b1.abs2, f1.abs2))
    e[6] = maxf(e[6], rel_q(b1.normalize, f1.normalize))
    e[7] = maxf(e[7], rel_q(b1.normalize, f1.normalize_div))
    e[8] = maxf(e[8], rel_q(b1.conjugate, f1.conjugate))
    e[9] = maxf(e[9], rel_q(b1 * b2, f1 * f2))
    e[10] = maxf(e[10], rel_q(b1 * b2, h1 * h2))
    e[11] = maxf(e[11], rel_q(b1 * b2, nc1 * nc2))
    e[12] = maxf(e[12], rel_q(b1 * b2, ia1 * ia2))
    e[13] = maxf(e[13], rel_q(b1 * b2, t1 * t2))
    e[14] = maxf(e[14], rel_q(b1 * b2, f1.mul_into(f2, out)))
    e[15] = maxf(e[15], rel_q(b1.normalize, f1.normalize_into(out)))
    e[26] = maxf(e[26], rel_q(b1 * b2, f1.mul_into_store(f2, out)))
    e[27] = maxf(e[27], rel_q(b1.normalize, f1.normalize_into_store(out)))
    e[16] = maxf(e[16], rel_q(b1 + sc, f1 + sc))
    e[17] = maxf(e[17], rel_q(b1 - 2, f1 - 2))
    e[18] = maxf(e[18], rel_q(b1 * sc, f1 * sc))
    e[19] = maxf(e[19], rel_q(b1 + b2, h1 + h2))
    e[20] = maxf(e[20], rel_q(b1 + b2, g1 + g2))
    e[21] = maxf(e[21], rel_q(b1 * b2, g1 * g2))
    e[22] = maxf(e[22], rel_q(b1 + b2, f1 + b2))
    e[23] = maxf(e[23], rel_q(b1 * b2, f1 * b2))
    e[24] = maxf(e[24], rel_q(b1 - sc, f1 - sc))
    e[25] = maxf(e[25], (b1.dot(b2) - f1.dot(f2)).abs / (b1.abs * b2.abs))
    i += 1
  names = ["add", "sub", "negate", "scale", "dot", "abs2", "normalize", "normalize_div",
    "conjugate", "mul", "mul_hoist_boxed", "mul_nocheck", "mul_isa", "mul_typed_overload",
    "mul_into", "normalize_into", "add_scalar_f64", "sub_scalar_int", "mul_scalar", "add_hoist_boxed",
    "add_guard", "mul_guard", "add_cross_class", "mul_cross_class", "sub_scalar_f64", "dot_rel_to_norms",
    "mul_into_store", "normalize_into_store"]
  j = 0
  while j < 28
    report(names[j], e[j], n)
    j += 1

-> verify_aliasing
  f1 = qf(3, ~2.0)
  f2 = qf(7, ~0.5)
  b1 = qb(3, ~2.0)
  b2 = qb(7, ~0.5)
  expect = b1 * b2
  report("mul_into_alias_self", rel_q(expect, f1.mul_into(f2, f1)), 1)
  f3 = qf(3, ~2.0)
  report("mul_into_alias_arg", rel_q(expect, f3.mul_into(f2, f2)), 1)
  f4 = qf(3, ~2.0)
  report("normalize_into_alias", rel_q(b1.normalize, f4.normalize_into(f4)), 1)
  v = vec(4, ~3.0)
  bv = b1.rotate(v)
  vo = Vec3Out<f64>.new([v.x, v.y, v.z] ## f64[3])
  report("rotate_into_alias", rel_v(bv, qf(3, ~2.0).rotate_into(vo, vo)), 1)
  report("rotate_into_store_alias", rel_v(bv, qf(3, ~2.0).rotate_into_store(v, v)), 1)
  o32 = QuatFast<f32>.new([~0.0, ~0.0, ~0.0, ~0.0] ## f32[4])
  # f1 and f2 were overwritten by the alias checks above; use fresh inputs.
  report("mul_into_f64_to_f32_out", rel_q(expect, qf(3, ~2.0).mul_into(qf(7, ~0.5), o32)), 1)

-> verify_rotate(n)
  e_rot = ~0.0
  e_into = ~0.0
  e_unit = ~0.0
  e_mat = ~0.0
  vo = Vec3Out<f64>.new([~0.0, ~0.0, ~0.0] ## f64[3])
  vs = Vec3<f64>.new([~0.0, ~0.0, ~0.0] ## f64[3])
  e_store = ~0.0
  i = 0
  while i < n
    b = qb(i, mag(i))
    f = qf(i, mag(i))
    v = vec(i + 7, mag(i / 5) * ~10.0)
    e_rot = maxf(e_rot, rel_v(b.rotate(v), f.rotate(v)))
    e_into = maxf(e_into, rel_v(b.rotate(v), f.rotate_into(v, vo)))
    e_store = maxf(e_store, rel_v(b.rotate(v), f.rotate_into_store(v, vs)))
    bu = b.normalize
    fu = fast_of(bu)
    e_unit = maxf(e_unit, rel_v(bu.rotate(v), fu.rotate_unit(v)))
    e_mat = maxf(e_mat, rel_m(b.to_rotation_matrix, f.to_rotation_matrix))
    i += 1
  report("rotate_nonunit", e_rot, n)
  report("rotate_into", e_into, n)
  report("rotate_into_store", e_store, n)
  report("rotate_unit_on_unit_q", e_unit, n)
  report("to_rotation_matrix_nonunit", e_mat, n)

-> slerp_pair_errs(b1, b2, t, errs)
  f1 = fast_of(b1)
  f2 = fast_of(b2)
  expect = b1.slerp(b2, t)
  errs[0] = maxf(errs[0], rel_q(expect, f1.slerp(b2, t)))
  errs[1] = maxf(errs[1], rel_q(expect, f1.slerp_sqrt(f2, t)))
  u1 = b1.normalize
  u2 = b2.normalize
  expect_u = u1.slerp(u2, t)
  errs[2] = maxf(errs[2], rel_q(expect_u, fast_of(u1).slerp_unit(fast_of(u2), t)))

-> verify_slerp(n)
  ts = [~0.0, ~0.25, ~0.5, ~0.73, ~1.0, ~1.3]
  epss = [~0.001, ~0.000001, ~0.000000001, ~0.0]
  general = [~0.0, ~0.0, ~0.0]
  antipodal = [~0.0, ~0.0, ~0.0]
  identical = [~0.0, ~0.0, ~0.0]
  i = 0
  count = 0
  while i < n
    t = ts[i % 6]
    a = qb(i, mag(i))
    slerp_pair_errs(a, qb(i + 101, mag(i / 5)), t, general)
    eps = epss[i % 4]
    s2 = mag(i / 3)
    p = qb(i + 57, eps)
    near_anti = base_of(a.normalize.scale(~-1.0 * s2) + p)
    near_same = base_of(a.normalize.scale(s2) + p)
    slerp_pair_errs(a, near_anti, t, antipodal)
    slerp_pair_errs(a, near_same, t, identical)
    count += 1
    i += 1
  names = ["slerp", "slerp_sqrt", "slerp_unit"]
  j = 0
  while j < 3
    report(names[j] + "_general", general[j], count)
    report(names[j] + "_near_antipodal", antipodal[j], count)
    report(names[j] + "_near_identical", identical[j], count)
    j += 1

-> fromrot_one(axis, angle, errs)
  q = QuatBase<f64>.from_axis_angle(axis, angle)
  m = q.to_rotation_matrix
  expect = QuatBase<f64>.from_rotation_matrix(m)
  got = QuatFast<f64>.from_rotation_matrix(m)
  got_n = QuatFast<f64>.from_rotation_matrix_normalized(m)
  errs[0] = maxf(errs[0], rel_q(expect, got))
  errs[1] = maxf(errs[1], rel_q(expect, got_n))
  errs[2] = maxf(errs[2], (Math.sqrt(got.abs2) - ~1.0).abs)
  drift = m.elements
  md = Mat3<f64>.new([
    drift[0] * ~1.01, drift[1] * ~1.01, drift[2] * ~1.01,
    drift[3] * ~1.01, drift[4] * ~1.01, drift[5] * ~1.01,
    drift[6] * ~1.01, drift[7] * ~1.01, drift[8] * ~1.01
  ] ## f64[9])
  errs[3] = maxf(errs[3], rel_q(QuatBase<f64>.from_rotation_matrix(md), QuatFast<f64>.from_rotation_matrix(md)))
  errs[4] = maxf(errs[4], rel_q(QuatBase<f64>.from_rotation_matrix(md), QuatFast<f64>.from_rotation_matrix_normalized(md)))

-> verify_fromrot(n)
  pi = ~3.141592653589793
  axes = [
    Vec3<f64>.new([~1.0, ~0.0, ~0.0] ## f64[3]),
    Vec3<f64>.new([~0.0, ~1.0, ~0.0] ## f64[3]),
    Vec3<f64>.new([~0.0, ~0.0, ~1.0] ## f64[3]),
    Vec3<f64>.new([~1.0, ~1.0, ~0.0] ## f64[3]),
    Vec3<f64>.new([~1.0, ~1.0, ~1.0] ## f64[3]),
    Vec3<f64>.new([~-0.3, ~0.8, ~0.52] ## f64[3])
  ]
  angles = [~0.000000001, ~0.000001, ~0.001, ~0.5, ~2.0, pi - ~0.000001, pi, pi + ~0.3, ~-1.2]
  near_identity = [~0.0, ~0.0, ~0.0, ~0.0, ~0.0]
  half_turn = [~0.0, ~0.0, ~0.0, ~0.0, ~0.0]
  other = [~0.0, ~0.0, ~0.0, ~0.0, ~0.0]
  count = 0
  ai = 0
  while ai < 6
    gi = 0
    while gi < 9
      ang = angles[gi]
      if gi < 3
        fromrot_one(axes[ai], ang, near_identity)
      else
        if gi >= 5 && gi <= 6
          fromrot_one(axes[ai], ang, half_turn)
        else
          fromrot_one(axes[ai], ang, other)
      count += 1
      gi += 1
    ai += 1
  i = 0
  while i < n
    fromrot_one(vec(i, ~1.0), comp(i, 11) * ~4.0, other)
    count += 1
    i += 1
  groups = [near_identity, half_turn, other]
  gnames = ["near_identity", "half_turn", "general"]
  g = 0
  while g < 3
    errs = groups[g]
    report("from_rotation_matrix_" + gnames[g], errs[0], count)
    report("from_rotation_matrix_normalized_" + gnames[g], errs[1], count)
    report("from_rotation_matrix_unit_dev_" + gnames[g], errs[2], count)
    report("from_rotation_matrix_drift1pct_" + gnames[g], errs[3], count)
    report("from_rotation_matrix_normalized_drift1pct_" + gnames[g], errs[4], count)
    g += 1

# The three controls must agree exactly (same bodies), and the negation
# workarounds must match the unary-minus spellings, signed zeros included.
-> qk(kind, i, s)
  c = [comp(i, 0) * s, comp(i, 1) * s, comp(i, 2) * s, comp(i, 3) * s]
  if kind == 0
    return Quaternion<f64>.new([c[0], c[1], c[2], c[3]] ## f64[4])
  QuatCopy<f64>.new([c[0], c[1], c[2], c[3]] ## f64[4])

-> verify_controls(n)
  e = (0...16).map -> ~0.0
  i = 0
  while i < n
    b1 = qb(i, mag(i))
    b2 = qb(i + 101, mag(i / 5))
    v = vec(i + 7, ~3.0)
    m = b1.to_rotation_matrix
    kind = 0
    while kind < 2
      k1 = qk(kind, i, mag(i))
      k2 = qk(kind, i + 101, mag(i / 5))
      o = kind * 8
      e[o] = maxf(e[o], rel_q(b1 + b2, k1 + k2))
      e[o + 1] = maxf(e[o + 1], rel_q(b1 * b2, k1 * k2))
      e[o + 2] = maxf(e[o + 2], rel_q(b1.normalize, k1.normalize))
      e[o + 3] = maxf(e[o + 3], rel_v(b1.rotate(v), k1.rotate(v)))
      e[o + 4] = maxf(e[o + 4], rel_q(b1.slerp(b2, ~0.3), k1.slerp(k2, ~0.3)))
      e[o + 5] = maxf(e[o + 5], rel_m(m, k1.to_rotation_matrix))
      kind += 1
    e[6] = maxf(e[6], rel_q(QuatBase<f64>.from_rotation_matrix(m), Quaternion<f64>.from_rotation_matrix(m)))
    e[14] = maxf(e[14], rel_q(QuatBase<f64>.from_rotation_matrix(m), QuatCopy<f64>.from_rotation_matrix(m)))
    f1 = qf(i, mag(i))
    f2 = qf(i + 101, mag(i / 5))
    e[7] = maxf(e[7], rel_q(f1.negate_unary, f1.negate))
    e[15] = maxf(e[15], rel_q(f1.slerp_unary(f2, ~0.3), f1.slerp(f2, ~0.3)))
    i += 1
  names = ["core_add", "core_mul", "core_normalize", "core_rotate", "core_slerp", "core_to_rotation_matrix",
    "core_from_rotation_matrix", "negate_vs_unary", "copy_add", "copy_mul", "copy_normalize", "copy_rotate",
    "copy_slerp", "copy_to_rotation_matrix", "copy_from_rotation_matrix", "slerp_vs_unary"]
  j = 0
  while j < 16
    report(names[j], e[j], n)
    j += 1
  z = QuatFast<f64>.new([~0.0, ~0.0, ~-0.0, ~1.0] ## f64[4])
  zb = QuatBase<f64>.new([~0.0, ~0.0, ~-0.0, ~1.0] ## f64[4])
  # atan2(zero, -1) is +pi for +0.0 and -pi for -0.0.
  ctl = [Math.atan2(zb.negate.w, ~-1.0), Math.atan2(zb.negate.y, ~-1.0), Math.atan2(zb.conjugate.x, ~-1.0)]
  got = [Math.atan2(z.negate.w, ~-1.0), Math.atan2(z.negate.y, ~-1.0), Math.atan2(z.conjugate.x, ~-1.0)]
  << "signed zeros (negate.w, negate.y, conjugate.x): ctl " + ctl.to_s + " fast " + got.to_s

# f32 receivers must compile and agree with the f32 control, and mixed-T
# operands must keep working (today's generic bodies handle them).
-> verify_f32_and_mixed
  b1 = QuatBase<f32>.new([~0.9, ~-0.3, ~0.4, ~1.2] ## f32[4])
  b2 = QuatBase<f32>.new([~-0.2, ~0.8, ~0.5, ~-0.6] ## f32[4])
  f1 = QuatFast<f32>.new([~0.9, ~-0.3, ~0.4, ~1.2] ## f32[4])
  f2 = QuatFast<f32>.new([~-0.2, ~0.8, ~0.5, ~-0.6] ## f32[4])
  v = Vec3<f32>.new([~0.3, ~-1.7, ~2.2] ## f32[3])
  report("f32_add", rel_q(b1 + b2, f1 + f2), 1)
  report("f32_mul", rel_q(b1 * b2, f1 * f2), 1)
  report("f32_normalize", rel_q(b1.normalize, f1.normalize), 1)
  report("f32_dot", rel_s(b1.dot(b2), f1.dot(f2)), 1)
  report("f32_rotate", rel_v(b1.rotate(v), f1.rotate(v)), 1)
  report("f32_to_rotation_matrix", rel_m(b1.to_rotation_matrix, f1.to_rotation_matrix), 1)
  report("f32_slerp", rel_q(b1.slerp(b2, ~0.37), f1.slerp(f2, ~0.37)), 1)
  m = b1.to_rotation_matrix
  report("f32_from_rotation_matrix", rel_q(QuatBase<f32>.from_rotation_matrix(m), QuatFast<f32>.from_rotation_matrix(m)), 1)
  d1 = QuatBase<f64>.new([~0.9, ~-0.3, ~0.4, ~1.2] ## f64[4])
  g1 = QuatFast<f64>.new([~0.9, ~-0.3, ~0.4, ~1.2] ## f64[4])
  t1 = QuatTyped<f64>.new([~0.9, ~-0.3, ~0.4, ~1.2] ## f64[4])
  t2 = QuatTyped<f32>.new([~-0.2, ~0.8, ~0.5, ~-0.6] ## f32[4])
  report("mixed_f64_f32_add", rel_q(d1 + b2, g1 + f2), 1)
  report("mixed_f64_f32_mul", rel_q(d1 * b2, g1 * f2), 1)
  report("mixed_f64_f32_dot", rel_s(d1.dot(b2), g1.dot(f2)), 1)
  report("mixed_f64_f32_slerp", rel_q(d1.slerp(b2, ~0.37), g1.slerp(f2, ~0.37)), 1)
  report("mixed_f64_f32_mul_typed_overload", rel_q(d1 * b2, t1 * t2), 1)
  << "mixed typed-overload result: " + (t1 * t2).to_s + " control: " + (d1 * b2).to_s

# ---------------------------------------------------------------------------
# Timed section: one variant per process, `<variant> <iters>`.

mode = ARGV[0]
iters = ARGV[1].to_i

if mode == "verify"
  verify_basic(250)
  verify_aliasing
  verify_rotate(250)
  verify_slerp(240)
  verify_fromrot(60)
  verify_controls(120)
  verify_f32_and_mixed

# General non-unit operands; the far slerp pair has a negative dot
# (exercises the sign flip) and the near pair takes the 0.9995 branch.
# Controls: base = subclass inheriting core (QuatBase), core = plain
# Quaternion<f64> receivers (today's core exactly), copy = QuatCopy.
ba = QuatBase<f64>.new([~0.9, ~-0.3, ~0.4, ~1.2] ## f64[4])
bb = QuatBase<f64>.new([~-0.2, ~0.8, ~0.5, ~-0.6] ## f64[4])
bc = QuatBase<f64>.new([~0.901, ~-0.298, ~0.399, ~1.2005] ## f64[4])
ca = Quaternion<f64>.new([~0.9, ~-0.3, ~0.4, ~1.2] ## f64[4])
cb = Quaternion<f64>.new([~-0.2, ~0.8, ~0.5, ~-0.6] ## f64[4])
cc = Quaternion<f64>.new([~0.901, ~-0.298, ~0.399, ~1.2005] ## f64[4])
pa = QuatCopy<f64>.new([~0.9, ~-0.3, ~0.4, ~1.2] ## f64[4])
pb = QuatCopy<f64>.new([~-0.2, ~0.8, ~0.5, ~-0.6] ## f64[4])
pc = QuatCopy<f64>.new([~0.901, ~-0.298, ~0.399, ~1.2005] ## f64[4])
fa = QuatFast<f64>.new([~0.9, ~-0.3, ~0.4, ~1.2] ## f64[4])
fb = QuatFast<f64>.new([~-0.2, ~0.8, ~0.5, ~-0.6] ## f64[4])
fc = QuatFast<f64>.new([~0.901, ~-0.298, ~0.399, ~1.2005] ## f64[4])
ga = QuatGuard<f64>.new([~0.9, ~-0.3, ~0.4, ~1.2] ## f64[4])
gb = QuatGuard<f64>.new([~-0.2, ~0.8, ~0.5, ~-0.6] ## f64[4])
na = QuatNoCheck<f64>.new([~0.9, ~-0.3, ~0.4, ~1.2] ## f64[4])
nb = QuatNoCheck<f64>.new([~-0.2, ~0.8, ~0.5, ~-0.6] ## f64[4])
ia = QuatIsA<f64>.new([~0.9, ~-0.3, ~0.4, ~1.2] ## f64[4])
ib = QuatIsA<f64>.new([~-0.2, ~0.8, ~0.5, ~-0.6] ## f64[4])
ha = QuatHoist<f64>.new([~0.9, ~-0.3, ~0.4, ~1.2] ## f64[4])
hb = QuatHoist<f64>.new([~-0.2, ~0.8, ~0.5, ~-0.6] ## f64[4])
ta = QuatTyped<f64>.new([~0.9, ~-0.3, ~0.4, ~1.2] ## f64[4])
tb = QuatTyped<f64>.new([~-0.2, ~0.8, ~0.5, ~-0.6] ## f64[4])
# Unit operands with bit-identical components for every class.
bu = ba.normalize
bv = bb.normalize
cu = Quaternion<f64>.new([bu.w, bu.x, bu.y, bu.z] ## f64[4])
cv = Quaternion<f64>.new([bv.w, bv.x, bv.y, bv.z] ## f64[4])
pu = QuatCopy<f64>.new([bu.w, bu.x, bu.y, bu.z] ## f64[4])
pv = QuatCopy<f64>.new([bv.w, bv.x, bv.y, bv.z] ## f64[4])
fu = QuatFast<f64>.new([bu.w, bu.x, bu.y, bu.z] ## f64[4])
fv = QuatFast<f64>.new([bv.w, bv.x, bv.y, bv.z] ## f64[4])
fo = QuatFast<f64>.new([~0.0, ~0.0, ~0.0, ~0.0] ## f64[4])
vec_in = Vec3<f64>.new([~0.3, ~-1.7, ~2.2] ## f64[3])
vec_out = Vec3Out<f64>.new([~0.0, ~0.0, ~0.0] ## f64[3])
vec_out_plain = Vec3<f64>.new([~0.0, ~0.0, ~0.0] ## f64[3])
# from_rotation_matrix inputs: trace > 0 branch, and the m22 (last) branch.
axis_z = Vec3<f64>.new([~0.1, ~-0.2, ~1.0] ## f64[3])
m_trace = bu.to_rotation_matrix
m_diag = QuatBase<f64>.from_axis_angle(axis_z, ~3.0).to_rotation_matrix
sc = ~1.75
t = ~0.37

acc = ~0.0
t0 = clock()
i = 0

# Harness overhead: loop + the checksum consumers used below.
if mode == "ovh_q"
  while i < iters
    acc += fa.w
    i++
if mode == "ovh_v"
  while i < iters
    acc += vec_in.x
    i++
if mode == "ovh_m"
  while i < iters
    acc += m_trace.trace
    i++

# Every op against the three controls.
if mode == "add_base"
  while i < iters
    acc += (ba + bb).w
    i++
if mode == "add_core"
  while i < iters
    acc += (ca + cb).w
    i++
if mode == "add_copy"
  while i < iters
    acc += (pa + pb).w
    i++
if mode == "add_fast"
  while i < iters
    acc += (fa + fb).w
    i++
if mode == "sub_base"
  while i < iters
    acc += (ba - bb).w
    i++
if mode == "sub_core"
  while i < iters
    acc += (ca - cb).w
    i++
if mode == "sub_copy"
  while i < iters
    acc += (pa - pb).w
    i++
if mode == "sub_fast"
  while i < iters
    acc += (fa - fb).w
    i++
if mode == "neg_base"
  while i < iters
    acc += ba.negate.w
    i++
if mode == "neg_core"
  while i < iters
    acc += ca.negate.w
    i++
if mode == "neg_copy"
  while i < iters
    acc += pa.negate.w
    i++
if mode == "neg_fast"
  while i < iters
    acc += fa.negate.w
    i++
if mode == "conj_base"
  while i < iters
    acc += ba.conjugate.x
    i++
if mode == "conj_core"
  while i < iters
    acc += ca.conjugate.x
    i++
if mode == "conj_copy"
  while i < iters
    acc += pa.conjugate.x
    i++
if mode == "conj_fast"
  while i < iters
    acc += fa.conjugate.x
    i++
if mode == "scale_base"
  while i < iters
    acc += ba.scale(sc).w
    i++
if mode == "scale_core"
  while i < iters
    acc += ca.scale(sc).w
    i++
if mode == "scale_copy"
  while i < iters
    acc += pa.scale(sc).w
    i++
if mode == "scale_fast"
  while i < iters
    acc += fa.scale(sc).w
    i++
if mode == "dot_base"
  while i < iters
    acc += ba.dot(bb)
    i++
if mode == "dot_core"
  while i < iters
    acc += ca.dot(cb)
    i++
if mode == "dot_copy"
  while i < iters
    acc += pa.dot(pb)
    i++
if mode == "dot_fast"
  while i < iters
    acc += fa.dot(fb)
    i++
if mode == "abs2_base"
  while i < iters
    acc += ba.abs2
    i++
if mode == "abs2_core"
  while i < iters
    acc += ca.abs2
    i++
if mode == "abs2_copy"
  while i < iters
    acc += pa.abs2
    i++
if mode == "abs2_fast"
  while i < iters
    acc += fa.abs2
    i++
if mode == "norm_base"
  while i < iters
    acc += ba.normalize.w
    i++
if mode == "norm_core"
  while i < iters
    acc += ca.normalize.w
    i++
if mode == "norm_copy"
  while i < iters
    acc += pa.normalize.w
    i++
if mode == "norm_fast"
  while i < iters
    acc += fa.normalize.w
    i++
if mode == "mul_base"
  while i < iters
    acc += (ba * bb).w
    i++
if mode == "mul_core"
  while i < iters
    acc += (ca * cb).w
    i++
if mode == "mul_copy"
  while i < iters
    acc += (pa * pb).w
    i++
if mode == "mul_fast"
  while i < iters
    acc += (fa * fb).w
    i++
if mode == "rot_base"
  while i < iters
    acc += ba.rotate(vec_in).x
    i++
if mode == "rot_core"
  while i < iters
    acc += ca.rotate(vec_in).x
    i++
if mode == "rot_copy"
  while i < iters
    acc += pa.rotate(vec_in).x
    i++
if mode == "rot_fast"
  while i < iters
    acc += fa.rotate(vec_in).x
    i++
if mode == "rot_unitq_base"
  while i < iters
    acc += bu.rotate(vec_in).x
    i++
if mode == "rot_unitq_core"
  while i < iters
    acc += cu.rotate(vec_in).x
    i++
if mode == "rot_unitq_copy"
  while i < iters
    acc += pu.rotate(vec_in).x
    i++
if mode == "rot_unitq_fast"
  while i < iters
    acc += fu.rotate(vec_in).x
    i++
if mode == "tomat_base"
  while i < iters
    acc += ba.to_rotation_matrix.trace
    i++
if mode == "tomat_core"
  while i < iters
    acc += ca.to_rotation_matrix.trace
    i++
if mode == "tomat_copy"
  while i < iters
    acc += pa.to_rotation_matrix.trace
    i++
if mode == "tomat_fast"
  while i < iters
    acc += fa.to_rotation_matrix.trace
    i++
if mode == "slerp_far_base"
  while i < iters
    acc += ba.slerp(bb, t).w
    i++
if mode == "slerp_far_core"
  while i < iters
    acc += ca.slerp(cb, t).w
    i++
if mode == "slerp_far_copy"
  while i < iters
    acc += pa.slerp(pb, t).w
    i++
if mode == "slerp_far_fast"
  while i < iters
    acc += fa.slerp(fb, t).w
    i++
if mode == "slerp_far_unitq_base"
  while i < iters
    acc += bu.slerp(bv, t).w
    i++
if mode == "slerp_far_unitq_core"
  while i < iters
    acc += cu.slerp(cv, t).w
    i++
if mode == "slerp_far_unitq_copy"
  while i < iters
    acc += pu.slerp(pv, t).w
    i++
if mode == "slerp_far_unitq_fast"
  while i < iters
    acc += fu.slerp(fv, t).w
    i++
if mode == "slerp_near_base"
  while i < iters
    acc += ba.slerp(bc, t).w
    i++
if mode == "slerp_near_core"
  while i < iters
    acc += ca.slerp(cc, t).w
    i++
if mode == "slerp_near_copy"
  while i < iters
    acc += pa.slerp(pc, t).w
    i++
if mode == "slerp_near_fast"
  while i < iters
    acc += fa.slerp(fc, t).w
    i++
if mode == "fromrot_trace_base"
  while i < iters
    acc += QuatBase<f64>.from_rotation_matrix(m_trace).w
    i++
if mode == "fromrot_trace_core"
  while i < iters
    acc += Quaternion<f64>.from_rotation_matrix(m_trace).w
    i++
if mode == "fromrot_trace_copy"
  while i < iters
    acc += QuatCopy<f64>.from_rotation_matrix(m_trace).w
    i++
if mode == "fromrot_trace_fast"
  while i < iters
    acc += QuatFast<f64>.from_rotation_matrix(m_trace).w
    i++
if mode == "fromrot_diag_base"
  while i < iters
    acc += QuatBase<f64>.from_rotation_matrix(m_diag).w
    i++
if mode == "fromrot_diag_core"
  while i < iters
    acc += Quaternion<f64>.from_rotation_matrix(m_diag).w
    i++
if mode == "fromrot_diag_copy"
  while i < iters
    acc += QuatCopy<f64>.from_rotation_matrix(m_diag).w
    i++
if mode == "fromrot_diag_fast"
  while i < iters
    acc += QuatFast<f64>.from_rotation_matrix(m_diag).w
    i++

# Candidate-only variants.
if mode == "add_guard"
  while i < iters
    acc += (ga + gb).w
    i++
if mode == "add_isa"
  while i < iters
    acc += (ia + ib).w
    i++
if mode == "add_nocheck"
  while i < iters
    acc += (na + nb).w
    i++
if mode == "add_hoist"
  while i < iters
    acc += (ha + hb).w
    i++
if mode == "add_typed"
  while i < iters
    acc += (ta + tb).w
    i++
if mode == "neg_unary"
  while i < iters
    acc += fa.negate_unary.w
    i++
if mode == "conj_unary"
  while i < iters
    acc += fa.conjugate_unary.x
    i++
if mode == "norm_div"
  while i < iters
    acc += fa.normalize_div.w
    i++
if mode == "mul_guard"
  while i < iters
    acc += (ga * gb).w
    i++
if mode == "mul_isa"
  while i < iters
    acc += (ia * ib).w
    i++
if mode == "mul_nocheck"
  while i < iters
    acc += (na * nb).w
    i++
if mode == "mul_hoist"
  while i < iters
    acc += (ha * hb).w
    i++
if mode == "mul_typed"
  while i < iters
    acc += (ta * tb).w
    i++
if mode == "rot_unit"
  while i < iters
    acc += fu.rotate_unit(vec_in).x
    i++
if mode == "slerp_far_unary"
  while i < iters
    acc += fa.slerp_unary(fb, t).w
    i++
if mode == "slerp_far_sqrt"
  while i < iters
    acc += fa.slerp_sqrt(fb, t).w
    i++
if mode == "slerp_far_unit"
  while i < iters
    acc += fu.slerp_unit(fv, t).w
    i++
if mode == "fromrot_trace_fastn"
  while i < iters
    acc += QuatFast<f64>.from_rotation_matrix_normalized(m_trace).w
    i++
if mode == "fromrot_diag_fastn"
  while i < iters
    acc += QuatFast<f64>.from_rotation_matrix_normalized(m_diag).w
    i++
if mode == "mul_into"
  while i < iters
    acc += fa.mul_into(fb, fo).w
    i++
if mode == "mul_into_store"
  while i < iters
    acc += fa.mul_into_store(fb, fo).w
    i++
if mode == "mul_into_typed"
  while i < iters
    acc += fa.mul_into_typed(fb, fo).w
    i++
if mode == "norm_into"
  while i < iters
    acc += fa.normalize_into(fo).w
    i++
if mode == "norm_into_store"
  while i < iters
    acc += fa.normalize_into_store(fo).w
    i++
if mode == "rot_into"
  while i < iters
    acc += fa.rotate_into(vec_in, vec_out).x
    i++
if mode == "rot_into_store"
  while i < iters
    acc += fa.rotate_into_store(vec_in, vec_out_plain).x
    i++

t1 = clock()
ns = iters > 0 ? (t1 - t0) * ~1000000000.0 / iters : ~0.0
<< "ns/op: " << ns << " checksum: " << acc
