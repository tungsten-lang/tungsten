# Mat2/Mat3/Mat4 A/B: pmndrs/math-inspired bodies vs today's core bodies.
#
#   bin/tungsten --release -o /tmp/mat_ab benchmarks/pmndrs_math/mat_ab.w
#   benchmarks/pmndrs_math/ab.py /tmp/mat_ab 1000000 7 inv4_copy inv4_nn inv4_fast
#   benchmarks/pmndrs_math/mat_num.py /tmp/mat_ab 60      # numeric diffs
#
# Classes per size N:
#   MatNBase  — no overrides (README control). Inherited bodies run, but their
#               `class.new` guard compares against MatN$f64, so a subclass
#               receiver takes the slow w_method_call_cached `new` path: this
#               control is handicapped for every allocating method.
#   MatNCopy  — the core bodies copied verbatim: the true control. Its IR is
#               identical to core's (checked with --ll).
#   MatNRecip / MatNNn / MatNFast — candidates: reciprocal-of-det only /
#               pmndrs term order (no unary minus, divides kept) / pmndrs
#               term order + reciprocal, load-hoisted products, new helpers.
#
# Harness adaptations (compiler gaps, see the pmndrs A/B report):
#   * every non-Base subclass REDECLARES `- data T elements[N]`: without it
#     the subclass's own methods see `@elements` untyped and every `a[i]` is
#     a dynamic `[]` call with boxed arithmetic (Mat4 inverse 57 -> 1480 ns);
#   * core's self-type annotation `(Mat4)` inside Mat4<T> lowers typed, but
#     inside a subclass it does not, so subclass bodies say `(Mat4Copy)` /
#     `(Mat4Fast)` etc. where core says `(Mat4)`;
#   * a subclass that defines only one overload of `*` REPLACES the whole
#     inherited `*` overload set, so Mat3Copy/Mat3Fast define both.
#
# Binary: `<variant> <iters>` prints `ns/op: X checksum: Y`;
# `dump4|dump3|dump2|dumpc <n>` prints inputs and every implementation's
# outputs at full precision for mat_num.py.

# Hash-style pseudo-random in [-1, 1): a plain sin(a·k + b) sequence would
# make every test matrix rank 2.
-> rnd(k)
  x = Math.sin(k * ~12.9898 + ~78.233) * ~43758.5453
  ~2.0 * (x - Math.floor(x)) - ~1.0

-> row_str(tag, e)
  s = tag
  i = 0
  while i < e.size()
    s = s + " " + e[i].to_s
    i += 1
  s

# Deterministic inputs. kind 0 = well-conditioned (diagonally dominant),
# 1 = near-singular (last column = sum of two others + 1e-8 noise),
# 2 = affine (rotation · scale + translation; Mat2: rotation · scale).
-> gen4(kind, seed)
  e = [
    ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0,
    ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0
  ] ## f64[16]
  j = 0
  while j < 16
    e[j] = rnd(seed + j)
    j += 1
  if kind == 0
    e[0] = e[0] + ~4.0
    e[5] = e[5] + ~4.0
    e[10] = e[10] + ~4.0
    e[15] = e[15] + ~4.0
  if kind == 1
    r = 0
    while r < 4
      e[12 + r] = e[r] + e[4 + r] + ~0.00000001 * rnd(seed + 40 + r)
      r += 1
  if kind == 2
    q = Quaternion<f64>.new([rnd(seed + 20), rnd(seed + 21), rnd(seed + 22), rnd(seed + 23)] ## f64[4])
    m = q.to_rotation_matrix.elements
    sx = ~1.25 + ~0.75 * rnd(seed + 24)
    sy = ~1.25 + ~0.75 * rnd(seed + 25)
    sz = ~1.25 + ~0.75 * rnd(seed + 26)
    e = [
      m[0] * sx, m[1] * sx, m[2] * sx, ~0.0,
      m[3] * sy, m[4] * sy, m[5] * sy, ~0.0,
      m[6] * sz, m[7] * sz, m[8] * sz, ~0.0,
      ~10.0 * rnd(seed + 27), ~10.0 * rnd(seed + 28), ~10.0 * rnd(seed + 29), ~1.0
    ] ## f64[16]
  e

-> gen3(kind, seed)
  e = [~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0] ## f64[9]
  j = 0
  while j < 9
    e[j] = rnd(seed + j)
    j += 1
  if kind == 0
    e[0] = e[0] + ~3.0
    e[4] = e[4] + ~3.0
    e[8] = e[8] + ~3.0
  if kind == 1
    r = 0
    while r < 3
      e[6 + r] = e[r] + e[3 + r] + ~0.00000001 * rnd(seed + 40 + r)
      r += 1
  if kind == 2
    th = ~3.0 * rnd(seed + 20)
    c = Math.cos(th)
    s = Math.sin(th)
    sx = ~1.25 + ~0.75 * rnd(seed + 21)
    sy = ~1.25 + ~0.75 * rnd(seed + 22)
    e = [
      c * sx, s * sx, ~0.0,
      (~0.0 - s) * sy, c * sy, ~0.0,
      ~10.0 * rnd(seed + 23), ~10.0 * rnd(seed + 24), ~1.0
    ] ## f64[9]
  e

-> gen2(kind, seed)
  e = [rnd(seed), rnd(seed + 1), rnd(seed + 2), rnd(seed + 3)] ## f64[4]
  if kind == 0
    e[0] = e[0] + ~2.0
    e[3] = e[3] + ~2.0
  if kind == 1
    e[2] = ~1.5 * e[0] + ~0.00000001 * rnd(seed + 40)
    e[3] = ~1.5 * e[1] + ~0.00000001 * rnd(seed + 41)
  if kind == 2
    th = ~3.0 * rnd(seed + 20)
    c = Math.cos(th)
    s = Math.sin(th)
    sx = ~1.25 + ~0.75 * rnd(seed + 21)
    sy = ~1.25 + ~0.75 * rnd(seed + 22)
    e = [c * sx, s * sx, (~0.0 - s) * sy, c * sy] ## f64[4]
  e

-> zeros(n)
  if n == 4
    return [~0.0, ~0.0, ~0.0, ~0.0] ## f64[4]
  if n == 3
    return [~0.0, ~0.0, ~0.0] ## f64[3]
  if n == 9
    return [~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0] ## f64[9]
  [
    ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0,
    ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0
  ] ## f64[16]

+ Mat4Base<T> < Mat4<T>
  -> dummy
    1

+ Mat4Copy<T> < Mat4<T>
  - data
    T elements[16]

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

  -> */1(Vec4)
    v = @1.components
    a = @elements
    Vec4.new([
      a[0] * v[0] + a[4] * v[1] + a[8]  * v[2] + a[12] * v[3],
      a[1] * v[0] + a[5] * v[1] + a[9]  * v[2] + a[13] * v[3],
      a[2] * v[0] + a[6] * v[1] + a[10] * v[2] + a[14] * v[3],
      a[3] * v[0] + a[7] * v[1] + a[11] * v[2] + a[15] * v[3]
    ] ## T[4])

  -> */1(Mat4Copy)
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

  -> mul_into/2(Mat4Copy Mat4Copy)
    a = @elements
    b = @1.elements
    o = @2.elements
    o[0]  = a[0] * b[0]  + a[4] * b[1]  + a[8]  * b[2]  + a[12] * b[3]
    o[1]  = a[1] * b[0]  + a[5] * b[1]  + a[9]  * b[2]  + a[13] * b[3]
    o[2]  = a[2] * b[0]  + a[6] * b[1]  + a[10] * b[2]  + a[14] * b[3]
    o[3]  = a[3] * b[0]  + a[7] * b[1]  + a[11] * b[2]  + a[15] * b[3]
    o[4]  = a[0] * b[4]  + a[4] * b[5]  + a[8]  * b[6]  + a[12] * b[7]
    o[5]  = a[1] * b[4]  + a[5] * b[5]  + a[9]  * b[6]  + a[13] * b[7]
    o[6]  = a[2] * b[4]  + a[6] * b[5]  + a[10] * b[6]  + a[14] * b[7]
    o[7]  = a[3] * b[4]  + a[7] * b[5]  + a[11] * b[6]  + a[15] * b[7]
    o[8]  = a[0] * b[8]  + a[4] * b[9]  + a[8]  * b[10] + a[12] * b[11]
    o[9]  = a[1] * b[8]  + a[5] * b[9]  + a[9]  * b[10] + a[13] * b[11]
    o[10] = a[2] * b[8]  + a[6] * b[9]  + a[10] * b[10] + a[14] * b[11]
    o[11] = a[3] * b[8]  + a[7] * b[9]  + a[11] * b[10] + a[15] * b[11]
    o[12] = a[0] * b[12] + a[4] * b[13] + a[8]  * b[14] + a[12] * b[15]
    o[13] = a[1] * b[12] + a[5] * b[13] + a[9]  * b[14] + a[13] * b[15]
    o[14] = a[2] * b[12] + a[6] * b[13] + a[10] * b[14] + a[14] * b[15]
    o[15] = a[3] * b[12] + a[7] * b[13] + a[11] * b[14] + a[15] * b[15]
    @2

  -> transpose
    a = @elements
    class.new([
      a[0], a[4], a[8],  a[12],
      a[1], a[5], a[9],  a[13],
      a[2], a[6], a[10], a[14],
      a[3], a[7], a[11], a[15]
    ] ## T[16])

+ Mat4Recip<T> < Mat4<T>
  - data
    T elements[16]

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
    inv_det = ~1.0 / (b00 * b11 - b01 * b10 + b02 * b09 + b03 * b08 - b04 * b07 + b05 * b06)
    class.new([
      ( a[5] * b11 - a[6] * b10 + a[7] * b09) * inv_det,
      (-a[1] * b11 + a[2] * b10 - a[3] * b09) * inv_det,
      ( a[13] * b05 - a[14] * b04 + a[15] * b03) * inv_det,
      (-a[9] * b05 + a[10] * b04 - a[11] * b03) * inv_det,
      (-a[4] * b11 + a[6] * b08 - a[7] * b07) * inv_det,
      ( a[0] * b11 - a[2] * b08 + a[3] * b07) * inv_det,
      (-a[12] * b05 + a[14] * b02 - a[15] * b01) * inv_det,
      ( a[8] * b05 - a[10] * b02 + a[11] * b01) * inv_det,
      ( a[4] * b10 - a[5] * b08 + a[7] * b06) * inv_det,
      (-a[0] * b10 + a[1] * b08 - a[3] * b06) * inv_det,
      ( a[12] * b04 - a[13] * b02 + a[15] * b00) * inv_det,
      (-a[8] * b04 + a[9] * b02 - a[11] * b00) * inv_det,
      (-a[4] * b09 + a[5] * b07 - a[6] * b06) * inv_det,
      ( a[0] * b09 - a[1] * b07 + a[2] * b06) * inv_det,
      (-a[12] * b03 + a[13] * b01 - a[14] * b00) * inv_det,
      ( a[8] * b03 - a[9] * b01 + a[10] * b00) * inv_det
    ] ## T[16])

+ Mat4Nn<T> < Mat4<T>
  - data
    T elements[16]

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
  -> inverse_into/1(Mat4Nn)
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

+ Mat4Fast<T> < Mat4<T>
  - data
    T elements[16]

  # pmndrs invert: no unary minus, one reciprocal of the determinant.
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
    inv_det = ~1.0 / (b00 * b11 - b01 * b10 + b02 * b09 + b03 * b08 - b04 * b07 + b05 * b06)
    class.new([
      (a[5] * b11 - a[6] * b10 + a[7] * b09) * inv_det,
      (a[2] * b10 - a[1] * b11 - a[3] * b09) * inv_det,
      (a[13] * b05 - a[14] * b04 + a[15] * b03) * inv_det,
      (a[10] * b04 - a[9] * b05 - a[11] * b03) * inv_det,
      (a[6] * b08 - a[4] * b11 - a[7] * b07) * inv_det,
      (a[0] * b11 - a[2] * b08 + a[3] * b07) * inv_det,
      (a[14] * b02 - a[12] * b05 - a[15] * b01) * inv_det,
      (a[8] * b05 - a[10] * b02 + a[11] * b01) * inv_det,
      (a[4] * b10 - a[5] * b08 + a[7] * b06) * inv_det,
      (a[1] * b08 - a[0] * b10 - a[3] * b06) * inv_det,
      (a[12] * b04 - a[13] * b02 + a[15] * b00) * inv_det,
      (a[9] * b02 - a[8] * b04 - a[11] * b00) * inv_det,
      (a[5] * b07 - a[4] * b09 - a[6] * b06) * inv_det,
      (a[0] * b09 - a[1] * b07 + a[2] * b06) * inv_det,
      (a[13] * b01 - a[12] * b03 - a[14] * b00) * inv_det,
      (a[8] * b03 - a[9] * b01 + a[10] * b00) * inv_det
    ] ## T[16])

  # Caller-owned output; loads every input first, so `m.inverse_into(m)`
  # (in-place) is safe.
  -> inverse_into/1(Mat4Fast)
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
    inv_det = ~1.0 / (b00 * b11 - b01 * b10 + b02 * b09 + b03 * b08 - b04 * b07 + b05 * b06)
    o[0] = (m5 * b11 - m6 * b10 + m7 * b09) * inv_det
    o[1] = (m2 * b10 - m1 * b11 - m3 * b09) * inv_det
    o[2] = (m13 * b05 - m14 * b04 + m15 * b03) * inv_det
    o[3] = (m10 * b04 - m9 * b05 - m11 * b03) * inv_det
    o[4] = (m6 * b08 - m4 * b11 - m7 * b07) * inv_det
    o[5] = (m0 * b11 - m2 * b08 + m3 * b07) * inv_det
    o[6] = (m14 * b02 - m12 * b05 - m15 * b01) * inv_det
    o[7] = (m8 * b05 - m10 * b02 + m11 * b01) * inv_det
    o[8] = (m4 * b10 - m5 * b08 + m7 * b06) * inv_det
    o[9] = (m1 * b08 - m0 * b10 - m3 * b06) * inv_det
    o[10] = (m12 * b04 - m13 * b02 + m15 * b00) * inv_det
    o[11] = (m9 * b02 - m8 * b04 - m11 * b00) * inv_det
    o[12] = (m5 * b07 - m4 * b09 - m6 * b06) * inv_det
    o[13] = (m0 * b09 - m1 * b07 + m2 * b06) * inv_det
    o[14] = (m13 * b01 - m12 * b03 - m14 * b00) * inv_det
    o[15] = (m8 * b03 - m9 * b01 + m10 * b00) * inv_det
    @1

  # pmndrs multiply shape: every operand element loaded once into a local.
  -> */1(Mat4Fast)
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

  # pmndrs multiply shape: all of `a` in locals, one column of `b` at a
  # time. Stores can no longer clobber pending loads, so out may alias
  # either input.
  -> mul_into/2(Mat4Fast Mat4Fast)
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

  # Matrix-vector product with the vector's components read once as T
  # (an untyped `@1.components[i]` otherwise keeps the whole body boxed).
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

  # Same body without the `## T` element hints (the style of today's
  # `*/1(Vec4)`), to separate the typing effect from the helper itself.
  -> transform_point_plain/1(Vec3)
    v = @1.components
    a = @elements
    x = v[0]
    y = v[1]
    z = v[2]
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

  # Harness-only variants of .compose: all accessors (compose_a) and all
  # `.components` (compose_c — wrong for QuaternionMetal).
  -> .compose_a(t, q, s)
    w = q.w ## T
    x = q.x ## T
    y = q.y ## T
    z = q.z ## T
    sx = s.x ## T
    sy = s.y ## T
    sz = s.z ## T
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
      t.x ## T, t.y ## T, t.z ## T, 1 ## T
    ] ## T[16])

  -> .compose_c(t, q, s)
    qc = q.components
    w = qc[0] ## T
    x = qc[1] ## T
    y = qc[2] ## T
    z = qc[3] ## T
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
  -> transpose_into/1(Mat4Fast)
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

+ Mat3Base<T> < Mat3<T>
  -> dummy
    1

+ Mat3Copy<T> < Mat3<T>
  - data
    T elements[9]

  -> inverse
    a = @elements
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
    d = a[0] * c00 + a[1] * c01 + a[2] * c02
    # Adjugate = transpose(cofactor matrix); column-major store.
    class.new([
      c00 / d, c10 / d, c20 / d,
      c01 / d, c11 / d, c21 / d,
      c02 / d, c12 / d, c22 / d
    ] ## T[9])

  -> determinant
    a = @elements
    a[0] * (a[4] * a[8] - a[5] * a[7]) - a[1] * (a[3] * a[8] - a[5] * a[6]) + a[2] * (a[3] * a[7] - a[4] * a[6])

  -> */1(Vec3)
    v = @1.components
    a = @elements
    Vec3.new([
      a[0] * v[0] + a[3] * v[1] + a[6] * v[2],
      a[1] * v[0] + a[4] * v[1] + a[7] * v[2],
      a[2] * v[0] + a[5] * v[1] + a[8] * v[2]
    ] ## T[3])

  -> */1(Mat3Copy)
    a = @elements
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

  -> mul_into/2(Mat3Copy Mat3Copy)
    a = @elements
    b = @1.elements
    o = @2.elements
    o[0] = a[0] * b[0] + a[3] * b[1] + a[6] * b[2]
    o[1] = a[1] * b[0] + a[4] * b[1] + a[7] * b[2]
    o[2] = a[2] * b[0] + a[5] * b[1] + a[8] * b[2]
    o[3] = a[0] * b[3] + a[3] * b[4] + a[6] * b[5]
    o[4] = a[1] * b[3] + a[4] * b[4] + a[7] * b[5]
    o[5] = a[2] * b[3] + a[5] * b[4] + a[8] * b[5]
    o[6] = a[0] * b[6] + a[3] * b[7] + a[6] * b[8]
    o[7] = a[1] * b[6] + a[4] * b[7] + a[7] * b[8]
    o[8] = a[2] * b[6] + a[5] * b[7] + a[8] * b[8]
    @2

+ Mat3Recip<T> < Mat3<T>
  - data
    T elements[9]

  -> inverse
    a = @elements
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
    inv_det = ~1.0 / (a[0] * c00 + a[1] * c01 + a[2] * c02)
    # Adjugate = transpose(cofactor matrix); column-major store.
    class.new([
      c00 * inv_det, c10 * inv_det, c20 * inv_det,
      c01 * inv_det, c11 * inv_det, c21 * inv_det,
      c02 * inv_det, c12 * inv_det, c22 * inv_det
    ] ## T[9])

+ Mat3Nn<T> < Mat3<T>
  - data
    T elements[9]

  # pmndrs shape: the three column-0 cofactors are shared with the
  # determinant, and every term is written without unary minus.
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
  -> inverse_into/1(Mat3Nn)
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

+ Mat3Fast<T> < Mat3<T>
  - data
    T elements[9]

  # pmndrs shape: the three column-0 cofactors are shared with the
  # determinant, and every term is written without unary minus.
  -> inverse
    a = @elements
    c00 = a[4] * a[8] - a[5] * a[7]
    c01 = a[5] * a[6] - a[3] * a[8]
    c02 = a[3] * a[7] - a[4] * a[6]
    inv_det = ~1.0 / (a[0] * c00 + a[1] * c01 + a[2] * c02)
    class.new([
      c00 * inv_det,
      (a[2] * a[7] - a[1] * a[8]) * inv_det,
      (a[1] * a[5] - a[2] * a[4]) * inv_det,
      c01 * inv_det,
      (a[0] * a[8] - a[2] * a[6]) * inv_det,
      (a[2] * a[3] - a[0] * a[5]) * inv_det,
      c02 * inv_det,
      (a[1] * a[6] - a[0] * a[7]) * inv_det,
      (a[0] * a[4] - a[1] * a[3]) * inv_det
    ] ## T[9])

  # Caller-owned output; loads every input first, so in-place is safe.
  -> inverse_into/1(Mat3Fast)
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
    inv_det = ~1.0 / (m0 * c00 + m1 * c01 + m2 * c02)
    o[0] = c00 * inv_det
    o[1] = (m2 * m7 - m1 * m8) * inv_det
    o[2] = (m1 * m5 - m2 * m4) * inv_det
    o[3] = c01 * inv_det
    o[4] = (m0 * m8 - m2 * m6) * inv_det
    o[5] = (m2 * m3 - m0 * m5) * inv_det
    o[6] = c02 * inv_det
    o[7] = (m1 * m6 - m0 * m7) * inv_det
    o[8] = (m0 * m4 - m1 * m3) * inv_det
    @1

  # pmndrs multiply shape: every operand element loaded once into a local.
  -> */1(Mat3Fast)
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
    n0 = b[0]
    n1 = b[1]
    n2 = b[2]
    n3 = b[3]
    n4 = b[4]
    n5 = b[5]
    n6 = b[6]
    n7 = b[7]
    n8 = b[8]
    class.new([
      m0 * n0 + m3 * n1 + m6 * n2,
      m1 * n0 + m4 * n1 + m7 * n2,
      m2 * n0 + m5 * n1 + m8 * n2,
      m0 * n3 + m3 * n4 + m6 * n5,
      m1 * n3 + m4 * n4 + m7 * n5,
      m2 * n3 + m5 * n4 + m8 * n5,
      m0 * n6 + m3 * n7 + m6 * n8,
      m1 * n6 + m4 * n7 + m7 * n8,
      m2 * n6 + m5 * n7 + m8 * n8
    ] ## T[9])

  # pmndrs multiply shape; out may alias either input.
  -> mul_into/2(Mat3Fast Mat3Fast)
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

  # Same cofactor-row expansion with the middle term's sign folded in
  # (pmndrs determinant shape).
  -> determinant
    a = @elements
    a[0] * (a[4] * a[8] - a[5] * a[7]) + a[1] * (a[5] * a[6] - a[3] * a[8]) + a[2] * (a[3] * a[7] - a[4] * a[6])

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

+ Mat2Base<T> < Mat2<T>
  -> dummy
    1

+ Mat2Copy<T> < Mat2<T>
  - data
    T elements[4]

  -> inverse
    a = @elements
    d = a[0] * a[3] - a[2] * a[1]
    class.new([
       a[3] / d, -a[1] / d,
      -a[2] / d,  a[0] / d
    ] ## T[4])

+ Mat2Recip<T> < Mat2<T>
  - data
    T elements[4]

  -> inverse
    a = @elements
    inv_det = ~1.0 / (a[0] * a[3] - a[2] * a[1])
    class.new([
       a[3] * inv_det, -a[1] * inv_det,
      -a[2] * inv_det,  a[0] * inv_det
    ] ## T[4])

+ Mat2Nn<T> < Mat2<T>
  - data
    T elements[4]

  -> inverse
    a = @elements
    d = a[0] * a[3] - a[2] * a[1]
    nd = (0 ## T) - d
    class.new([
      a[3] / d,  a[1] / nd,
      a[2] / nd, a[0] / d
    ] ## T[4])

+ Mat2Fast<T> < Mat2<T>
  - data
    T elements[4]

  # One reciprocal; the off-diagonal sign rides on it (-a·s == a·(0−s)
  # exactly) instead of a unary minus per element.
  -> inverse
    a = @elements
    inv_det = ~1.0 / (a[0] * a[3] - a[2] * a[1])
    neg_inv_det = (0 ## T) - inv_det
    class.new([
      a[3] * inv_det,     a[1] * neg_inv_det,
      a[2] * neg_inv_det, a[0] * inv_det
    ] ## T[4])


mode = ARGV[0]
k = ARGV[1].to_i

# Timing operands — all built before any branching (compiled
# `Generic<T>.new` inside an `elsif` arm resolves the class to nil).
m4b = Mat4Base<f64>.new(gen4(0, 1))
m4c = Mat4Copy<f64>.new(gen4(0, 1))
m4r = Mat4Recip<f64>.new(gen4(0, 1))
m4n = Mat4Nn<f64>.new(gen4(0, 1))
m4f = Mat4Fast<f64>.new(gen4(0, 1))
n4b = Mat4Base<f64>.new(gen4(0, 101))
n4c = Mat4Copy<f64>.new(gen4(0, 101))
n4f = Mat4Fast<f64>.new(gen4(0, 101))
a4c = Mat4Copy<f64>.new(gen4(2, 7))
a4f = Mat4Fast<f64>.new(gen4(2, 7))
a4u = Mat4<f64>.new(gen4(2, 7))
o4c = Mat4Copy<f64>.new(zeros(16))
o4f = Mat4Fast<f64>.new(zeros(16))
o4n = Mat4Nn<f64>.new(zeros(16))
p4n = Mat4Nn<f64>.new(gen4(0, 1))
q4n = Mat4Nn<f64>.new(zeros(16))
p4f = Mat4Fast<f64>.new(gen4(0, 1))
q4f = Mat4Fast<f64>.new(zeros(16))
v4 = Vec4<f64>.new([~0.3, ~1.2, ~2.5, ~1.0] ## f64[4])
ov4 = Vec4<f64>.new(zeros(4))
p3 = Vec3<f64>.new([~0.3, ~1.2, ~2.5] ## f64[3])
q = Quaternion<f64>.new([~0.8, ~0.2, ~0.4, ~0.3] ## f64[4])
tv = Vec3<f64>.new([~1.0, ~2.0, ~3.0] ## f64[3])
sv = Vec3<f64>.new([~1.5, ~0.5, ~2.0] ## f64[3])
m3b = Mat3Base<f64>.new(gen3(0, 1))
m3c = Mat3Copy<f64>.new(gen3(0, 1))
m3r = Mat3Recip<f64>.new(gen3(0, 1))
m3n = Mat3Nn<f64>.new(gen3(0, 1))
m3f = Mat3Fast<f64>.new(gen3(0, 1))
o3f = Mat3Fast<f64>.new(zeros(9))
o3n = Mat3Nn<f64>.new(zeros(9))
o3c = Mat3Copy<f64>.new(zeros(9))
n3c = Mat3Copy<f64>.new(gen3(0, 101))
n3f = Mat3Fast<f64>.new(gen3(0, 101))
p3n = Mat3Nn<f64>.new(gen3(0, 1))
q3n = Mat3Nn<f64>.new(zeros(9))
p3f = Mat3Fast<f64>.new(gen3(0, 1))
q3f = Mat3Fast<f64>.new(zeros(9))
v3 = Vec3<f64>.new([~0.3, ~1.2, ~2.5] ## f64[3])
ov3 = Vec3<f64>.new(zeros(3))
m2b = Mat2Base<f64>.new(gen2(0, 1))
m2c = Mat2Copy<f64>.new(gen2(0, 1))
m2r = Mat2Recip<f64>.new(gen2(0, 1))
m2n = Mat2Nn<f64>.new(gen2(0, 1))
m2f = Mat2Fast<f64>.new(gen2(0, 1))

acc = ~0.0
i = 0
t0 = clock()

if mode == "inv4_base"
  while i < k
    acc += m4b.inverse.elements[5]
    i++

if mode == "inv4_copy"
  while i < k
    acc += m4c.inverse.elements[5]
    i++

if mode == "inv4_recip"
  while i < k
    acc += m4r.inverse.elements[5]
    i++

if mode == "inv4_nn"
  while i < k
    acc += m4n.inverse.elements[5]
    i++

if mode == "inv4_fast"
  while i < k
    acc += m4f.inverse.elements[5]
    i++

if mode == "inv4_into"
  while i < k
    acc += m4f.inverse_into(o4f).elements[5]
    i++

if mode == "inv4_into_nn"
  while i < k
    acc += m4n.inverse_into(o4n).elements[5]
    i++

if mode == "inv4_chain_nn"
  while i < k
    p4n.inverse_into(q4n)
    acc += q4n.inverse_into(p4n).elements[5]
    i++

if mode == "inv4_chain_fast"
  while i < k
    p4f.inverse_into(q4f)
    acc += q4f.inverse_into(p4f).elements[5]
    i++

if mode == "mul4_base"
  while i < k
    acc += (m4b * n4b).elements[5]
    i++

if mode == "mul4_copy"
  while i < k
    acc += (m4c * n4c).elements[5]
    i++

if mode == "mul4_fast"
  while i < k
    acc += (m4f * n4f).elements[5]
    i++

if mode == "mulinto4_copy"
  while i < k
    acc += m4c.mul_into(n4c, o4c).elements[5]
    i++

if mode == "mulinto4_fast"
  while i < k
    acc += m4f.mul_into(n4f, o4f).elements[5]
    i++

if mode == "mv4_base"
  while i < k
    acc += (m4b * v4).components[1]
    i++

if mode == "mv4_copy"
  while i < k
    acc += (m4c * v4).components[1]
    i++

if mode == "mv4_fast"
  while i < k
    acc += (m4f * v4).components[1]
    i++

if mode == "mv4_into"
  while i < k
    acc += m4f.mul_vec_into(v4, ov4).components[1]
    i++

if mode == "tr4_copy"
  while i < k
    acc += m4c.transpose.elements[1]
    i++

if mode == "tr4_into"
  while i < k
    acc += m4f.transpose_into(o4f).elements[1]
    i++

if mode == "tp_user"
  while i < k
    r = a4u * Vec4<f64>.new([p3.x, p3.y, p3.z, ~1.0] ## f64[4])
    w = r.w
    acc += Vec3<f64>.new([r.x / w, r.y / w, r.z / w] ## f64[3]).components[1]
    i++

if mode == "tp_plain"
  while i < k
    acc += a4f.transform_point_plain(p3).components[1]
    i++

if mode == "tp_fast"
  while i < k
    acc += a4f.transform_point(p3).components[1]
    i++

if mode == "td_user"
  while i < k
    r = a4u * Vec4<f64>.new([p3.x, p3.y, p3.z, ~0.0] ## f64[4])
    acc += Vec3<f64>.new([r.x, r.y, r.z] ## f64[3]).components[1]
    i++

if mode == "td_fast"
  while i < k
    acc += a4f.transform_direction(p3).components[1]
    i++

if mode == "affinv_copy"
  while i < k
    acc += a4c.inverse.elements[13]
    i++

if mode == "affinv_genfast"
  while i < k
    acc += a4f.inverse.elements[13]
    i++

if mode == "affinv_fast"
  while i < k
    acc += a4f.affine_inverse.elements[13]
    i++

if mode == "compose_user"
  while i < k
    rm = q.to_rotation_matrix.elements
    r4 = Mat4<f64>.new([rm[0], rm[1], rm[2], ~0.0, rm[3], rm[4], rm[5], ~0.0, rm[6], rm[7], rm[8], ~0.0, ~0.0, ~0.0, ~0.0, ~1.0] ## f64[16])
    acc += (Mat4<f64>.translation(tv.x, tv.y, tv.z) * r4 * Mat4<f64>.scale(sv.x, sv.y, sv.z)).elements[5]
    i++

if mode == "compose_fast"
  while i < k
    acc += Mat4Fast<f64>.compose(tv, q, sv).elements[5]
    i++

if mode == "compose_fast_c"
  while i < k
    acc += Mat4Fast<f64>.compose_c(tv, q, sv).elements[5]
    i++

if mode == "compose_fast_a"
  while i < k
    acc += Mat4Fast<f64>.compose_a(tv, q, sv).elements[5]
    i++

if mode == "q_w"
  while i < k
    acc += q.w
    i++

if mode == "q_comp0"
  while i < k
    acc += q.components[0]
    i++

if mode == "v_x"
  while i < k
    acc += tv.x
    i++

if mode == "v_comp0"
  while i < k
    acc += tv.components[0]
    i++

if mode == "inv3_base"
  while i < k
    acc += m3b.inverse.elements[4]
    i++

if mode == "inv3_copy"
  while i < k
    acc += m3c.inverse.elements[4]
    i++

if mode == "inv3_recip"
  while i < k
    acc += m3r.inverse.elements[4]
    i++

if mode == "inv3_nn"
  while i < k
    acc += m3n.inverse.elements[4]
    i++

if mode == "inv3_fast"
  while i < k
    acc += m3f.inverse.elements[4]
    i++

if mode == "inv3_into"
  while i < k
    acc += m3f.inverse_into(o3f).elements[4]
    i++

if mode == "inv3_into_nn"
  while i < k
    acc += m3n.inverse_into(o3n).elements[4]
    i++

if mode == "inv3_chain_nn"
  while i < k
    p3n.inverse_into(q3n)
    acc += q3n.inverse_into(p3n).elements[4]
    i++

if mode == "inv3_chain_fast"
  while i < k
    p3f.inverse_into(q3f)
    acc += q3f.inverse_into(p3f).elements[4]
    i++

if mode == "mul3_copy"
  while i < k
    acc += (m3c * n3c).elements[4]
    i++

if mode == "mul3_fast"
  while i < k
    acc += (m3f * n3f).elements[4]
    i++

if mode == "mulinto3_copy"
  while i < k
    acc += m3c.mul_into(n3c, o3c).elements[4]
    i++

if mode == "mulinto3_fast"
  while i < k
    acc += m3f.mul_into(n3f, o3f).elements[4]
    i++

if mode == "det3_base"
  while i < k
    acc += m3b.determinant
    i++

if mode == "det3_copy"
  while i < k
    acc += m3c.determinant
    i++

if mode == "det3_fast"
  while i < k
    acc += m3f.determinant
    i++

if mode == "mv3_copy"
  while i < k
    acc += (m3c * v3).components[1]
    i++

if mode == "mv3_fast"
  while i < k
    acc += (m3f * v3).components[1]
    i++

if mode == "mv3_into"
  while i < k
    acc += m3f.mul_vec_into(v3, ov3).components[1]
    i++

if mode == "inv2_base"
  while i < k
    acc += m2b.inverse.elements[1]
    i++

if mode == "inv2_copy"
  while i < k
    acc += m2c.inverse.elements[1]
    i++

if mode == "inv2_recip"
  while i < k
    acc += m2r.inverse.elements[1]
    i++

if mode == "inv2_nn"
  while i < k
    acc += m2n.inverse.elements[1]
    i++

if mode == "inv2_fast"
  while i < k
    acc += m2f.inverse.elements[1]
    i++

if mode == "empty"
  while i < k
    acc += ~1.0
    i++

t1 = clock()
ns = k > 0 ? (t1 - t0) * ~1000000000.0 / k : ~0.0
<< "ns/op: " << ns << " checksum: " << acc

# ---- numeric dumps: `D <kind> <n> <tag> <values...>` for mat_num.py ----
if mode == "dump4"
  kind = 0
  while kind < 3
    n = 0
    while n < k
      seed = 1000 * kind + 53 * n + 11
      tag = "D " + kind.to_s + " " + n.to_s + " "
      << row_str(tag + "in", gen4(kind, seed))
      << row_str(tag + "in2", gen4(0, seed + 500))
      xb = Mat4Base<f64>.new(gen4(kind, seed))
      xc = Mat4Copy<f64>.new(gen4(kind, seed))
      xr = Mat4Recip<f64>.new(gen4(kind, seed))
      xn = Mat4Nn<f64>.new(gen4(kind, seed))
      xf = Mat4Fast<f64>.new(gen4(kind, seed))
      xu = Mat4<f64>.new(gen4(kind, seed))
      yb = Mat4Base<f64>.new(gen4(0, seed + 500))
      yc = Mat4Copy<f64>.new(gen4(0, seed + 500))
      yf = Mat4Fast<f64>.new(gen4(0, seed + 500))
      << row_str(tag + "inv4.core", xu.inverse.elements)
      << row_str(tag + "inv4.base", xb.inverse.elements)
      << row_str(tag + "inv4.copy", xc.inverse.elements)
      << row_str(tag + "inv4.recip", xr.inverse.elements)
      << row_str(tag + "inv4.nn", xn.inverse.elements)
      << row_str(tag + "inv4.fast", xf.inverse.elements)
      oi = Mat4Fast<f64>.new(gen4(kind, seed))
      << row_str(tag + "inv4.into_inplace", oi.inverse_into(oi).elements)
      oj = Mat4Nn<f64>.new(gen4(kind, seed))
      << row_str(tag + "inv4.into_nn_inplace", oj.inverse_into(oj).elements)
      << row_str(tag + "inv4.affine", xf.affine_inverse.elements)
      << row_str(tag + "mul4.core", (xu * Mat4<f64>.new(gen4(0, seed + 500))).elements)
      << row_str(tag + "mul4.base", (xb * yb).elements)
      << row_str(tag + "mul4.copy", (xc * yc).elements)
      << row_str(tag + "mul4.fast", (xf * yf).elements)
      oc = Mat4Copy<f64>.new(zeros(16))
      << row_str(tag + "mul4.into_copy", xc.mul_into(yc, oc).elements)
      of = Mat4Fast<f64>.new(zeros(16))
      << row_str(tag + "mul4.into_fast", xf.mul_into(yf, of).elements)
      oa = Mat4Fast<f64>.new(gen4(kind, seed))
      << row_str(tag + "mul4.into_alias_a", oa.mul_into(yf, oa).elements)
      ob = Mat4Fast<f64>.new(gen4(0, seed + 500))
      << row_str(tag + "mul4.into_alias_b", xf.mul_into(ob, ob).elements)
      v = Vec4<f64>.new([rnd(seed + 60), rnd(seed + 61), rnd(seed + 62), rnd(seed + 63)] ## f64[4])
      << row_str(tag + "vin", v.components)
      << row_str(tag + "mv4.core", (xu * v).components)
      << row_str(tag + "mv4.copy", (xc * v).components)
      << row_str(tag + "mv4.fast", (xf * v).components)
      ov = Vec4<f64>.new(zeros(4))
      << row_str(tag + "mv4.into", xf.mul_vec_into(v, ov).components)
      p = Vec3<f64>.new([~3.0 * rnd(seed + 64), ~3.0 * rnd(seed + 65), ~3.0 * rnd(seed + 66)] ## f64[3])
      << row_str(tag + "pin", p.components)
      r = xu * Vec4<f64>.new([p.x, p.y, p.z, ~1.0] ## f64[4])
      w = r.w
      << row_str(tag + "tp.user", [r.x / w, r.y / w, r.z / w] ## f64[3])
      << row_str(tag + "tp.plain", xf.transform_point_plain(p).components)
      << row_str(tag + "tp.fast", xf.transform_point(p).components)
      r = xu * Vec4<f64>.new([p.x, p.y, p.z, ~0.0] ## f64[4])
      << row_str(tag + "td.user", [r.x, r.y, r.z] ## f64[3])
      << row_str(tag + "td.fast", xf.transform_direction(p).components)
      << row_str(tag + "tr4.copy", xc.transpose.elements)
      ot = Mat4Fast<f64>.new(gen4(kind, seed))
      << row_str(tag + "tr4.into_inplace", ot.transpose_into(ot).elements)
      n += 1
    kind += 1

if mode == "dump3"
  kind = 0
  while kind < 3
    n = 0
    while n < k
      seed = 1000 * kind + 53 * n + 11
      tag = "D " + kind.to_s + " " + n.to_s + " "
      << row_str(tag + "in", gen3(kind, seed))
      xu = Mat3<f64>.new(gen3(kind, seed))
      xb = Mat3Base<f64>.new(gen3(kind, seed))
      xc = Mat3Copy<f64>.new(gen3(kind, seed))
      xr = Mat3Recip<f64>.new(gen3(kind, seed))
      xn = Mat3Nn<f64>.new(gen3(kind, seed))
      xf = Mat3Fast<f64>.new(gen3(kind, seed))
      << row_str(tag + "inv3.core", xu.inverse.elements)
      << row_str(tag + "inv3.base", xb.inverse.elements)
      << row_str(tag + "inv3.copy", xc.inverse.elements)
      << row_str(tag + "inv3.recip", xr.inverse.elements)
      << row_str(tag + "inv3.nn", xn.inverse.elements)
      << row_str(tag + "inv3.fast", xf.inverse.elements)
      oi = Mat3Fast<f64>.new(gen3(kind, seed))
      << row_str(tag + "inv3.into_inplace", oi.inverse_into(oi).elements)
      oj = Mat3Nn<f64>.new(gen3(kind, seed))
      << row_str(tag + "inv3.into_nn_inplace", oj.inverse_into(oj).elements)
      << row_str(tag + "in2", gen3(0, seed + 500))
      yc = Mat3Copy<f64>.new(gen3(0, seed + 500))
      yf = Mat3Fast<f64>.new(gen3(0, seed + 500))
      << row_str(tag + "mul3.core", (xu * Mat3<f64>.new(gen3(0, seed + 500))).elements)
      << row_str(tag + "mul3.copy", (xc * yc).elements)
      << row_str(tag + "mul3.fast", (xf * yf).elements)
      oc = Mat3Copy<f64>.new(zeros(9))
      << row_str(tag + "mul3.into_copy", xc.mul_into(yc, oc).elements)
      oa = Mat3Fast<f64>.new(gen3(kind, seed))
      << row_str(tag + "mul3.into_alias_a", oa.mul_into(yf, oa).elements)
      ob = Mat3Fast<f64>.new(gen3(0, seed + 500))
      << row_str(tag + "mul3.into_alias_b", xf.mul_into(ob, ob).elements)
      << row_str(tag + "det3.core", [xu.determinant] ## f64[1])
      << row_str(tag + "det3.copy", [xc.determinant] ## f64[1])
      << row_str(tag + "det3.fast", [xf.determinant] ## f64[1])
      v = Vec3<f64>.new([rnd(seed + 60), rnd(seed + 61), rnd(seed + 62)] ## f64[3])
      << row_str(tag + "vin", v.components)
      << row_str(tag + "mv3.core", (xu * v).components)
      << row_str(tag + "mv3.copy", (xc * v).components)
      << row_str(tag + "mv3.fast", (xf * v).components)
      ov = Vec3<f64>.new(zeros(3))
      << row_str(tag + "mv3.into", xf.mul_vec_into(v, ov).components)
      n += 1
    kind += 1

if mode == "dump2"
  kind = 0
  while kind < 3
    n = 0
    while n < k
      seed = 1000 * kind + 53 * n + 11
      tag = "D " + kind.to_s + " " + n.to_s + " "
      << row_str(tag + "in", gen2(kind, seed))
      << row_str(tag + "inv2.core", Mat2<f64>.new(gen2(kind, seed)).inverse.elements)
      << row_str(tag + "inv2.base", Mat2Base<f64>.new(gen2(kind, seed)).inverse.elements)
      << row_str(tag + "inv2.copy", Mat2Copy<f64>.new(gen2(kind, seed)).inverse.elements)
      << row_str(tag + "inv2.recip", Mat2Recip<f64>.new(gen2(kind, seed)).inverse.elements)
      << row_str(tag + "inv2.nn", Mat2Nn<f64>.new(gen2(kind, seed)).inverse.elements)
      << row_str(tag + "inv2.fast", Mat2Fast<f64>.new(gen2(kind, seed)).inverse.elements)
      n += 1
    kind += 1

if mode == "dumpc"
  kind = 0
  while kind < 2
    n = 0
    while n < k
      seed = 1000 * kind + 53 * n + 11
      tag = "D " + kind.to_s + " " + n.to_s + " "
      qq = Quaternion<f64>.new([rnd(seed), rnd(seed + 1), rnd(seed + 2), rnd(seed + 3)] ## f64[4])
      if kind == 1
        qq = qq.normalize
      tt = Vec3<f64>.new([~10.0 * rnd(seed + 4), ~10.0 * rnd(seed + 5), ~10.0 * rnd(seed + 6)] ## f64[3])
      ss = Vec3<f64>.new([~1.25 + ~0.75 * rnd(seed + 7), ~1.25 + ~0.75 * rnd(seed + 8), ~1.25 + ~0.75 * rnd(seed + 9)] ## f64[3])
      << row_str(tag + "qin", qq.components)
      << row_str(tag + "tin", tt.components)
      << row_str(tag + "sin", ss.components)
      rm = qq.to_rotation_matrix.elements
      r4 = Mat4<f64>.new([rm[0], rm[1], rm[2], ~0.0, rm[3], rm[4], rm[5], ~0.0, rm[6], rm[7], rm[8], ~0.0, ~0.0, ~0.0, ~0.0, ~1.0] ## f64[16])
      << row_str(tag + "compose.user", (Mat4<f64>.translation(tt.x, tt.y, tt.z) * r4 * Mat4<f64>.scale(ss.x, ss.y, ss.z)).elements)
      << row_str(tag + "compose.fast", Mat4Fast<f64>.compose(tt, qq, ss).elements)
      << row_str(tag + "compose.fast_metal", Mat4Fast<f64>.compose(tt, qq.to_metal, ss).elements)
      n += 1
    kind += 1
