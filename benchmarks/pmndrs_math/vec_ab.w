# vec_ab.w — pmndrs/math-inspired A/B for Vec2/Vec3/Vec4.
#
# usage: vec_ab <variant> <iters>    (prints `ns/op: X checksum: Y`)
#        vec_ab check 0              (numeric parity lines, control vs candidate)
#
# Classes (every one a direct child of the core class, so dispatch depth is
# identical; each re-declares the `- data` block — see "Methodology" below):
#
#   (core)    the REAL core classes, Vec2/3/4<f64> — variants `…_core`. This
#             is the headline control: exactly today's performance.
#   Vec3Copy  verbatim copies of today's core bodies compiled in the harness
#             subclass context — variants `…_copy` (body-only control).
#   Vec3Base  inherits today's core bodies — variants `…_base`/`…_idiom`.
#             Inherited `class.new` misses the exact-class fast path, so it
#             runs ~2-5% more instructions than core on allocating ops.
#   Vec3Ls    candidate 1 only (fixed-width length_squared/length/normalize),
#             to separate "fixed magnitude" from "fixed body" for the generic
#             Vector methods that call length_squared.
#   Vec3Fast  pmndrs-shaped bodies (unrolled, fused, out-param) that read the
#             other operand with today's core idiom, `b = @1.components` then
#             `b[i]` — isolates the pmndrs structural idea.
#   Vec3Unb   the same bodies plus unboxed operand reads (`b[i] ## T`,
#             `s = @1 ## T`), and the existing core binary ops rewritten the
#             same way: "what core looks like after landing everything".
#   Vec2Base/Vec2Unb, Vec4Base/Vec4Unb: the recommended bodies for 2 and 4.
#
# Methodology: a subclass body sees `@components` as UNTYPED unless the
# subclass re-declares the `- data` block — without it, `a[0]` in a
# subclass lowers to a dynamic `[]` call while the same text in core Vec3
# lowers to a typed load. Re-declaring the identical block reproduces the
# core typing context (same slot, same layout; inherited accessors still
# read it correctly — checked in `check` mode).
#
# Composite variants (`nb_*`) run <iters> integration steps over 1000
# particles, so their ns/op and instr/op are per STEP (/1000 per particle).

+ Vec3Base<T> < Vec3<T>
  - data
    T components[3]

+ Vec3Copy<T> < Vec3<T>
  - data
    T components[3]

  # Verbatim copies of today's core bodies (core/numeric/vec3.w, then the
  # core/vector.w generics the candidates replace), compiled in the same
  # subclass context as the candidates so the two differ only in body.

  -> +/1
    other = @1.components
    a = @components
    class.new([a[0] + other[0], a[1] + other[1], a[2] + other[2]] ## T[3])

  -> -/1
    other = @1.components
    a = @components
    class.new([a[0] - other[0], a[1] - other[1], a[2] - other[2]] ## T[3])

  -> */1(Vector)
    other = @1.components
    a = @components
    class.new([a[0] * other[0], a[1] * other[1], a[2] * other[2]] ## T[3])

  -> */1(Number)
    s = @1
    a = @components
    class.new([a[0] * s, a[1] * s, a[2] * s] ## T[3])

  -> //1(Vector)
    other = @1.components
    a = @components
    class.new([a[0] / other[0], a[1] / other[1], a[2] / other[2]] ## T[3])

  -> //1(Number)
    s = @1
    a = @components
    class.new([a[0] / s, a[1] / s, a[2] / s] ## T[3])

  -> dot/1
    other = @1.components
    a = @components
    a[0] * other[0] + a[1] * other[1] + a[2] * other[2]

  -> lerp/2
    other = @1.components
    t = @2
    a = @components
    class.new([
      a[0] + (other[0] - a[0]) * t,
      a[1] + (other[1] - a[1]) * t,
      a[2] + (other[2] - a[2]) * t
    ] ## T[3])

  -> cross/1
    a = @components
    b = @1.components
    class.new([
      a[1] * b[2] - a[2] * b[1],
      a[2] * b[0] - a[0] * b[2],
      a[0] * b[1] - a[1] * b[0]
    ] ## T[3])

  -> length_squared
    dot(self)

  -> length
    length_squared.sqrt

  -> <=>/1
    length_squared <=> @1.length_squared

  -> normalize
    self / length

  -> reflect/1
    self - @1 * (2 * dot(@1))

  -> project_onto/1
    @1 * (dot(@1) / @1.length_squared)

  -> zero?
    length_squared == 0

+ Vec3Ls<T> < Vec3<T>
  - data
    T components[3]

  -> length_squared
    a = @components
    a[0] * a[0] + a[1] * a[1] + a[2] * a[2]

  -> length
    a = @components
    Math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2])

  -> normalize
    a = @components
    inv = ~1.0 / Math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2])
    class.new([a[0] * inv, a[1] * inv, a[2] * inv] ## T[3])

+ Vec3Fast<T> < Vec3<T>
  - data
    T components[3]

  # Candidate 1 — fixed-width magnitude chain (self-only: no operand reads).

  -> length_squared
    a = @components
    a[0] * a[0] + a[1] * a[1] + a[2] * a[2]

  -> length
    a = @components
    Math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2])

  # One sqrt, then multiply by the reciprocal (pmndrs/glMatrix). A zero
  # vector still yields NaN components, exactly like `self / length`.
  -> normalize
    a = @components
    inv = ~1.0 / Math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2])
    class.new([a[0] * inv, a[1] * inv, a[2] * inv] ## T[3])

  # Candidate 1b — divide by the length instead: correctly rounded and
  # bit-identical to today's `self / length`.
  -> normalize_div
    a = @components
    l = Math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2])
    class.new([a[0] / l, a[1] / l, a[2] / l] ## T[3])

  # Candidate 2 — distances without the `(a - b)` temporary.

  -> distance_squared/1
    a = @components
    b = @1.components
    dx = a[0] - b[0]
    dy = a[1] - b[1]
    dz = a[2] - b[2]
    dx * dx + dy * dy + dz * dz

  -> distance/1
    a = @components
    b = @1.components
    dx = a[0] - b[0]
    dy = a[1] - b[1]
    dz = a[2] - b[2]
    Math.sqrt(dx * dx + dy * dy + dz * dz)

  # Candidate 3 — self + other * s in one allocation (pmndrs scaleAndAdd).

  -> scale_and_add/2
    a = @components
    b = @1.components
    s = @2
    class.new([a[0] + b[0] * s, a[1] + b[1] * s, a[2] + b[2] * s] ## T[3])

  # Candidate 4 — fixed-width geometry and predicates.

  -> reflect/1
    a = @components
    n = @1.components
    k = 2 * (a[0] * n[0] + a[1] * n[1] + a[2] * n[2])
    class.new([a[0] - n[0] * k, a[1] - n[1] * k, a[2] - n[2] * k] ## T[3])

  -> project_onto/1
    a = @components
    b = @1.components
    k = (a[0] * b[0] + a[1] * b[1] + a[2] * b[2]) / (b[0] * b[0] + b[1] * b[1] + b[2] * b[2])
    class.new([b[0] * k, b[1] * k, b[2] * k] ## T[3])

  -> zero?
    a = @components
    a[0] * a[0] + a[1] * a[1] + a[2] * a[2] == 0

  # Componentwise zero test (NOT a drop-in: today's zero? is true when the
  # squared length underflows, e.g. [1e-200, 0, 0]).
  -> zero_cw?
    a = @components
    a[0] == 0 && a[1] == 0 && a[2] == 0

  -> <=>/1
    a = @components
    b = @1.components
    (a[0] * a[0] + a[1] * a[1] + a[2] * a[2]) <=> (b[0] * b[0] + b[1] * b[1] + b[2] * b[2])

  # Candidate 5 — out-param form A: write through `out.components`.

  -> add_into/2
    a = @components
    b = @1.components
    o = @2.components
    o[0] = a[0] + b[0]
    o[1] = a[1] + b[1]
    o[2] = a[2] + b[2]
    @2

  -> scale_and_add_into/3
    a = @components
    b = @1.components
    s = @2
    o = @3.components
    o[0] = a[0] + b[0] * s
    o[1] = a[1] + b[1] * s
    o[2] = a[2] + b[2] * s
    @3

  -> normalize_into/1
    a = @components
    inv = ~1.0 / Math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2])
    o = @1.components
    o[0] = a[0] * inv
    o[1] = a[1] * inv
    o[2] = a[2] * inv
    @1

  # Out-param form B: one dynamic call on `out` (pmndrs `set`).

  -> set/3
    a = @components
    a[0] = @1
    a[1] = @2
    a[2] = @3
    self

  -> add_into_set/2
    a = @components
    b = @1.components
    @2.set(a[0] + b[0], a[1] + b[1], a[2] + b[2])

  -> scale_and_add_into_set/3
    a = @components
    b = @1.components
    s = @2
    @3.set(a[0] + b[0] * s, a[1] + b[1] * s, a[2] + b[2] * s)

  # Mutating form (Matrix#add_mut style), today's operand reads.

  -> scale_and_add_mut/2
    a = @components
    b = @1.components
    s = @2
    a[0] = a[0] + b[0] * s
    a[1] = a[1] + b[1] * s
    a[2] = a[2] + b[2] * s
    self

  # Other-operand read forms for dot (informational).

  -> dot_conv/1
    b = @1.components ## T[3]
    a = @components
    a[0] * b[0] + a[1] * b[1] + a[2] * b[2]

  -> dot_acc/1
    a = @components
    a[0] * @1.x + a[1] * @1.y + a[2] * @1.z

+ Vec3Unb<T> < Vec3<T>
  - data
    T components[3]

  # Candidate 0 — existing core binary ops with unboxed operand reads. The
  # untyped `b[i]` is a boxed value, so `a[i] + b[i]` runs the generic
  # w_add type chain; `(b[i] ## T)` unboxes it and the op is one fadd.

  -> +/1
    a = @components
    b = @1.components
    class.new([a[0] + (b[0] ## T), a[1] + (b[1] ## T), a[2] + (b[2] ## T)] ## T[3])

  -> -/1
    a = @components
    b = @1.components
    class.new([a[0] - (b[0] ## T), a[1] - (b[1] ## T), a[2] - (b[2] ## T)] ## T[3])

  -> */1(Vector)
    a = @components
    b = @1.components
    class.new([a[0] * (b[0] ## T), a[1] * (b[1] ## T), a[2] * (b[2] ## T)] ## T[3])

  -> */1(Number)
    s = @1 ## T
    a = @components
    class.new([a[0] * s, a[1] * s, a[2] * s] ## T[3])

  # Named scalar multiply (pmndrs `scale`): same body as `*`(Number) but a
  # plain method, so the call skips typed-overload resolution.
  -> scale/1
    s = @1 ## T
    a = @components
    class.new([a[0] * s, a[1] * s, a[2] * s] ## T[3])

  # Scalar left boxed (today's semantics for integer T / f32; see report).
  -> scale_sbox/1
    s = @1
    a = @components
    class.new([a[0] * s, a[1] * s, a[2] * s] ## T[3])

  -> dot/1
    a = @components
    b = @1.components
    a[0] * (b[0] ## T) + a[1] * (b[1] ## T) + a[2] * (b[2] ## T)

  -> cross/1
    a = @components
    b = @1.components
    bx = b[0] ## T
    by = b[1] ## T
    bz = b[2] ## T
    class.new([a[1] * bz - a[2] * by, a[2] * bx - a[0] * bz, a[0] * by - a[1] * bx] ## T[3])

  -> lerp/2
    a = @components
    b = @1.components
    t = @2 ## T
    class.new([
      a[0] + ((b[0] ## T) - a[0]) * t,
      a[1] + ((b[1] ## T) - a[1]) * t,
      a[2] + ((b[2] ## T) - a[2]) * t
    ] ## T[3])

  # Double dispatch (informational): the OTHER operand multiplies its own
  # typed components by our three unboxed scalars — one dynamic call total.
  -> dot_dd/1
    a = @components
    @1.dot3(a[0], a[1], a[2])

  -> dot3/3
    a = @components
    a[0] * (@1 ## T) + a[1] * (@2 ## T) + a[2] * (@3 ## T)

  # Candidate 1.

  -> length_squared
    a = @components
    a[0] * a[0] + a[1] * a[1] + a[2] * a[2]

  -> length
    a = @components
    Math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2])

  -> normalize
    a = @components
    inv = ~1.0 / Math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2])
    class.new([a[0] * inv, a[1] * inv, a[2] * inv] ## T[3])

  -> normalize_div
    a = @components
    l = Math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2])
    class.new([a[0] / l, a[1] / l, a[2] / l] ## T[3])

  -> normalize_into_div/1
    a = @components
    l = Math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2])
    @1.set(a[0] / l, a[1] / l, a[2] / l)

  # Candidate 2.

  -> distance_squared/1
    a = @components
    b = @1.components
    dx = a[0] - (b[0] ## T)
    dy = a[1] - (b[1] ## T)
    dz = a[2] - (b[2] ## T)
    dx * dx + dy * dy + dz * dz

  -> distance/1
    a = @components
    b = @1.components
    dx = a[0] - (b[0] ## T)
    dy = a[1] - (b[1] ## T)
    dz = a[2] - (b[2] ## T)
    Math.sqrt(dx * dx + dy * dy + dz * dz)

  # Candidate 3.

  -> scale_and_add/2
    a = @components
    b = @1.components
    s = @2 ## T
    class.new([a[0] + (b[0] ## T) * s, a[1] + (b[1] ## T) * s, a[2] + (b[2] ## T) * s] ## T[3])

  -> scale_and_add_sbox/2
    a = @components
    b = @1.components
    s = @2
    class.new([a[0] + (b[0] ## T) * s, a[1] + (b[1] ## T) * s, a[2] + (b[2] ## T) * s] ## T[3])

  # Candidate 4.

  -> reflect/1
    a = @components
    n = @1.components
    nx = n[0] ## T
    ny = n[1] ## T
    nz = n[2] ## T
    k = 2 * (a[0] * nx + a[1] * ny + a[2] * nz)
    class.new([a[0] - nx * k, a[1] - ny * k, a[2] - nz * k] ## T[3])

  # `2 * d` boxes (int literal times a typed float lowers to __w_mul_fast
  # and poisons the rest of the body); `d + d` is exact and stays typed.
  -> reflect2/1
    a = @components
    n = @1.components
    nx = n[0] ## T
    ny = n[1] ## T
    nz = n[2] ## T
    d = a[0] * nx + a[1] * ny + a[2] * nz
    k = d + d
    class.new([a[0] - nx * k, a[1] - ny * k, a[2] - nz * k] ## T[3])

  -> project_onto/1
    a = @components
    b = @1.components
    bx = b[0] ## T
    by = b[1] ## T
    bz = b[2] ## T
    k = (a[0] * bx + a[1] * by + a[2] * bz) / (bx * bx + by * by + bz * bz)
    class.new([bx * k, by * k, bz * k] ## T[3])

  -> zero?
    a = @components
    a[0] * a[0] + a[1] * a[1] + a[2] * a[2] == 0

  -> <=>/1
    a = @components
    b = @1.components
    bx = b[0] ## T
    by = b[1] ## T
    bz = b[2] ## T
    (a[0] * a[0] + a[1] * a[1] + a[2] * a[2]) <=> (bx * bx + by * by + bz * bz)

  # Candidate 5 — out-param (`set` form: one dynamic call on `out`) and
  # mutating forms. `out` may alias self or an operand: every input is read
  # into a local or an argument before `set` writes.

  -> set/3
    a = @components
    a[0] = @1
    a[1] = @2
    a[2] = @3
    self

  -> add_into/2
    a = @components
    b = @1.components
    @2.set(a[0] + (b[0] ## T), a[1] + (b[1] ## T), a[2] + (b[2] ## T))

  -> sub_into/2
    a = @components
    b = @1.components
    @2.set(a[0] - (b[0] ## T), a[1] - (b[1] ## T), a[2] - (b[2] ## T))

  -> scale_into/2
    a = @components
    s = @1 ## T
    @2.set(a[0] * s, a[1] * s, a[2] * s)

  -> scale_and_add_into/3
    a = @components
    b = @1.components
    s = @2 ## T
    @3.set(a[0] + (b[0] ## T) * s, a[1] + (b[1] ## T) * s, a[2] + (b[2] ## T) * s)

  -> normalize_into/1
    a = @components
    inv = ~1.0 / Math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2])
    @1.set(a[0] * inv, a[1] * inv, a[2] * inv)

  -> cross_into/2
    a = @components
    b = @1.components
    bx = b[0] ## T
    by = b[1] ## T
    bz = b[2] ## T
    @2.set(a[1] * bz - a[2] * by, a[2] * bx - a[0] * bz, a[0] * by - a[1] * bx)

  -> lerp_into/3
    a = @components
    b = @1.components
    t = @2 ## T
    @3.set(a[0] + ((b[0] ## T) - a[0]) * t, a[1] + ((b[1] ## T) - a[1]) * t, a[2] + ((b[2] ## T) - a[2]) * t)

  -> add_mut/1
    a = @components
    b = @1.components
    a[0] = a[0] + (b[0] ## T)
    a[1] = a[1] + (b[1] ## T)
    a[2] = a[2] + (b[2] ## T)
    self

  -> scale_mut/1
    a = @components
    s = @1 ## T
    a[0] = a[0] * s
    a[1] = a[1] * s
    a[2] = a[2] * s
    self

  -> scale_and_add_mut/2
    a = @components
    b = @1.components
    s = @2 ## T
    a[0] = a[0] + (b[0] ## T) * s
    a[1] = a[1] + (b[1] ## T) * s
    a[2] = a[2] + (b[2] ## T) * s
    self

+ Vec2Base<T> < Vec2<T>
  - data
    T components[2]

+ Vec2Unb<T> < Vec2<T>
  - data
    T components[2]

  -> dot/1
    a = @components
    b = @1.components
    a[0] * (b[0] ## T) + a[1] * (b[1] ## T)

  -> length_squared
    a = @components
    a[0] * a[0] + a[1] * a[1]

  -> length
    a = @components
    Math.sqrt(a[0] * a[0] + a[1] * a[1])

  -> normalize
    a = @components
    inv = ~1.0 / Math.sqrt(a[0] * a[0] + a[1] * a[1])
    class.new([a[0] * inv, a[1] * inv] ## T[2])

  -> distance_squared/1
    a = @components
    b = @1.components
    dx = a[0] - (b[0] ## T)
    dy = a[1] - (b[1] ## T)
    dx * dx + dy * dy

  -> distance/1
    a = @components
    b = @1.components
    dx = a[0] - (b[0] ## T)
    dy = a[1] - (b[1] ## T)
    Math.sqrt(dx * dx + dy * dy)

  -> scale_and_add/2
    a = @components
    b = @1.components
    s = @2 ## T
    class.new([a[0] + (b[0] ## T) * s, a[1] + (b[1] ## T) * s] ## T[2])

  -> scale_and_add_mut/2
    a = @components
    b = @1.components
    s = @2 ## T
    a[0] = a[0] + (b[0] ## T) * s
    a[1] = a[1] + (b[1] ## T) * s
    self

+ Vec4Base<T> < Vec4<T>
  - data
    T components[4]

+ Vec4Unb<T> < Vec4<T>
  - data
    T components[4]

  -> dot/1
    a = @components
    b = @1.components
    a[0] * (b[0] ## T) + a[1] * (b[1] ## T) + a[2] * (b[2] ## T) + a[3] * (b[3] ## T)

  -> length_squared
    a = @components
    a[0] * a[0] + a[1] * a[1] + a[2] * a[2] + a[3] * a[3]

  -> length
    a = @components
    Math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2] + a[3] * a[3])

  -> normalize
    a = @components
    inv = ~1.0 / Math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2] + a[3] * a[3])
    class.new([a[0] * inv, a[1] * inv, a[2] * inv, a[3] * inv] ## T[4])

  -> distance_squared/1
    a = @components
    b = @1.components
    dx = a[0] - (b[0] ## T)
    dy = a[1] - (b[1] ## T)
    dz = a[2] - (b[2] ## T)
    dw = a[3] - (b[3] ## T)
    dx * dx + dy * dy + dz * dz + dw * dw

  -> distance/1
    a = @components
    b = @1.components
    dx = a[0] - (b[0] ## T)
    dy = a[1] - (b[1] ## T)
    dz = a[2] - (b[2] ## T)
    dw = a[3] - (b[3] ## T)
    Math.sqrt(dx * dx + dy * dy + dz * dz + dw * dw)

  -> scale_and_add/2
    a = @components
    b = @1.components
    s = @2 ## T
    class.new([
      a[0] + (b[0] ## T) * s,
      a[1] + (b[1] ## T) * s,
      a[2] + (b[2] ## T) * s,
      a[3] + (b[3] ## T) * s
    ] ## T[4])

  -> scale_and_add_mut/2
    a = @components
    b = @1.components
    s = @2 ## T
    a[0] = a[0] + (b[0] ## T) * s
    a[1] = a[1] + (b[1] ## T) * s
    a[2] = a[2] + (b[2] ## T) * s
    a[3] = a[3] + (b[3] ## T) * s
    self

mode = ARGV[0]
k = ARGV[1].to_i
acc = ~0.0
sc = ~0.37
tt = ~0.25
dt = ~0.001

# Every operand is built before branching (compiled `Generic<T>.new` inside
# an `elsif` arm resolves the class to nil).
b3a = Vec3Base<f64>.new([~1.5, ~-2.25, ~3.125] ## f64[3])
b3b = Vec3Base<f64>.new([~0.6, ~0.8, ~-0.4] ## f64[3])
l3a = Vec3Ls<f64>.new([~1.5, ~-2.25, ~3.125] ## f64[3])
l3b = Vec3Ls<f64>.new([~0.6, ~0.8, ~-0.4] ## f64[3])
f3a = Vec3Fast<f64>.new([~1.5, ~-2.25, ~3.125] ## f64[3])
f3b = Vec3Fast<f64>.new([~0.6, ~0.8, ~-0.4] ## f64[3])
f3o = Vec3Fast<f64>.new([~0.0, ~0.0, ~0.0] ## f64[3])
u3a = Vec3Unb<f64>.new([~1.5, ~-2.25, ~3.125] ## f64[3])
u3b = Vec3Unb<f64>.new([~0.6, ~0.8, ~-0.4] ## f64[3])
u3o = Vec3Unb<f64>.new([~0.0, ~0.0, ~0.0] ## f64[3])
b3p = Vec3Base<f64>.new([~1.0, ~2.0, ~3.0] ## f64[3])
f3p = Vec3Fast<f64>.new([~1.0, ~2.0, ~3.0] ## f64[3])
u3p = Vec3Unb<f64>.new([~1.0, ~2.0, ~3.0] ## f64[3])
b2a = Vec2Base<f64>.new([~1.5, ~-2.25] ## f64[2])
b2b = Vec2Base<f64>.new([~0.6, ~0.8] ## f64[2])
u2a = Vec2Unb<f64>.new([~1.5, ~-2.25] ## f64[2])
u2b = Vec2Unb<f64>.new([~0.6, ~0.8] ## f64[2])
b2p = Vec2Base<f64>.new([~1.0, ~2.0] ## f64[2])
u2p = Vec2Unb<f64>.new([~1.0, ~2.0] ## f64[2])
b4a = Vec4Base<f64>.new([~1.5, ~-2.25, ~3.125, ~0.5] ## f64[4])
b4b = Vec4Base<f64>.new([~0.6, ~0.8, ~-0.4, ~0.2] ## f64[4])
u4a = Vec4Unb<f64>.new([~1.5, ~-2.25, ~3.125, ~0.5] ## f64[4])
u4b = Vec4Unb<f64>.new([~0.6, ~0.8, ~-0.4, ~0.2] ## f64[4])
b4p = Vec4Base<f64>.new([~1.0, ~2.0, ~3.0, ~4.0] ## f64[4])
u4p = Vec4Unb<f64>.new([~1.0, ~2.0, ~3.0, ~4.0] ## f64[4])
cv3a = Vec3<f64>.new([~1.5, ~-2.25, ~3.125] ## f64[3])
cv3b = Vec3<f64>.new([~0.6, ~0.8, ~-0.4] ## f64[3])
cv3p = Vec3<f64>.new([~1.0, ~2.0, ~3.0] ## f64[3])
cp3a = Vec3Copy<f64>.new([~1.5, ~-2.25, ~3.125] ## f64[3])
cp3b = Vec3Copy<f64>.new([~0.6, ~0.8, ~-0.4] ## f64[3])
cp3p = Vec3Copy<f64>.new([~1.0, ~2.0, ~3.0] ## f64[3])
cv2a = Vec2<f64>.new([~1.5, ~-2.25] ## f64[2])
cv2b = Vec2<f64>.new([~0.6, ~0.8] ## f64[2])
cv2p = Vec2<f64>.new([~1.0, ~2.0] ## f64[2])
cv4a = Vec4<f64>.new([~1.5, ~-2.25, ~3.125, ~0.5] ## f64[4])
cv4b = Vec4<f64>.new([~0.6, ~0.8, ~-0.4, ~0.2] ## f64[4])
cv4p = Vec4<f64>.new([~1.0, ~2.0, ~3.0, ~4.0] ## f64[4])
z0b = Vec3Base<f64>.new([~0.0, ~0.0, ~0.0] ## f64[3])
z0u = Vec3Unb<f64>.new([~0.0, ~0.0, ~0.0] ## f64[3])
tinyb = Vec3Base<f64>.new([~1e-200, ~0.0, ~0.0] ## f64[3])
tinyu = Vec3Unb<f64>.new([~1e-200, ~0.0, ~0.0] ## f64[3])
c3f32 = Vec3<f32>.new([~0.6, ~0.8, ~-0.4] ## f32[3])
c3i64 = Vec3<i64>.new([6, 8, -4] ## i64[3])

# Particle system for the composite: softened gravity toward the origin plus
# velocity damping, semi-implicit Euler, 1000 particles.
np = 1000
pos_b = []
vel_b = []
pos_u = []
vel_u = []
pos_c = []
vel_c = []
pos_k = []
vel_k = []
j = 0
while j < np
  px = ~0.1 * (j % 17) - ~0.8
  py = ~0.1 * (j % 13) - ~0.6
  pz = ~0.1 * (j % 11) + ~0.5
  pos_b << Vec3Base<f64>.new([px, py, pz] ## f64[3])
  vel_b << Vec3Base<f64>.new([~0.0 - py * ~0.5, px * ~0.5, ~0.0] ## f64[3])
  pos_u << Vec3Unb<f64>.new([px, py, pz] ## f64[3])
  vel_u << Vec3Unb<f64>.new([~0.0 - py * ~0.5, px * ~0.5, ~0.0] ## f64[3])
  pos_c << Vec3<f64>.new([px, py, pz] ## f64[3])
  vel_c << Vec3<f64>.new([~0.0 - py * ~0.5, px * ~0.5, ~0.0] ## f64[3])
  pos_k << Vec3Copy<f64>.new([px, py, pz] ## f64[3])
  vel_k << Vec3Copy<f64>.new([~0.0 - py * ~0.5, px * ~0.5, ~0.0] ## f64[3])
  j++
center_b = Vec3Base<f64>.new([~0.0, ~0.0, ~0.0] ## f64[3])
center_u = Vec3Unb<f64>.new([~0.0, ~0.0, ~0.0] ## f64[3])
center_c = Vec3<f64>.new([~0.0, ~0.0, ~0.0] ## f64[3])
center_k = Vec3Copy<f64>.new([~0.0, ~0.0, ~0.0] ## f64[3])
scratch_u = Vec3Unb<f64>.new([~0.0, ~0.0, ~0.0] ## f64[3])
grav = ~1.0
soft = ~0.01
damp = ~0.999

t0 = clock()
i = 0
if mode == "v3_dot_base"
  while i < k
    acc += b3a.dot(b3b)
    i++
elsif mode == "v3_dot_base_core"
  while i < k
    acc += cv3a.dot(cv3b)
    i++
elsif mode == "v3_dot_base_copy"
  while i < k
    acc += cp3a.dot(cp3b)
    i++
elsif mode == "v3_dot_conv"
  while i < k
    acc += f3a.dot_conv(f3b)
    i++
elsif mode == "v3_dot_acc"
  while i < k
    acc += f3a.dot_acc(f3b)
    i++
elsif mode == "v3_dot_unb"
  while i < k
    acc += u3a.dot(u3b)
    i++
elsif mode == "v3_dot_dd"
  while i < k
    acc += u3a.dot_dd(u3b)
    i++
elsif mode == "v3_add_base"
  while i < k
    acc += (b3a + b3b).z
    i++
elsif mode == "v3_add_unb"
  while i < k
    acc += (u3a + u3b).z
    i++
elsif mode == "v3_scale_base"
  while i < k
    acc += (b3a * sc).z
    i++
elsif mode == "v3_scale_sbox"
  while i < k
    acc += u3a.scale_sbox(sc).z
    i++
elsif mode == "v3_scale_named_unb"
  while i < k
    acc += u3a.scale(sc).z
    i++
elsif mode == "v3_scale_unb"
  while i < k
    acc += (u3a * sc).z
    i++
elsif mode == "v3_cross_base"
  while i < k
    acc += b3a.cross(b3b).z
    i++
elsif mode == "v3_cross_unb"
  while i < k
    acc += u3a.cross(u3b).z
    i++
elsif mode == "v3_lerp_base"
  while i < k
    acc += b3a.lerp(b3b, tt).z
    i++
elsif mode == "v3_lerp_unb"
  while i < k
    acc += u3a.lerp(u3b, tt).z
    i++
elsif mode == "v3_ls_base"
  while i < k
    acc += b3a.length_squared
    i++
elsif mode == "v3_ls_fast"
  while i < k
    acc += f3a.length_squared
    i++
elsif mode == "v3_len_base"
  while i < k
    acc += b3a.length
    i++
elsif mode == "v3_len_fast"
  while i < k
    acc += f3a.length
    i++
elsif mode == "v3_norm_base"
  while i < k
    acc += b3a.normalize.z
    i++
elsif mode == "v3_norm_fast"
  while i < k
    acc += f3a.normalize.z
    i++
elsif mode == "v3_norm_div"
  while i < k
    acc += f3a.normalize_div.z
    i++
elsif mode == "v3_dist_idiom"
  while i < k
    acc += (b3a - b3b).length
    i++
elsif mode == "v3_dist_idiom_ls"
  while i < k
    acc += (l3a - l3b).length
    i++
elsif mode == "v3_dist_idiom_unb"
  while i < k
    acc += (u3a - u3b).length
    i++
elsif mode == "v3_dist_fast"
  while i < k
    acc += f3a.distance(f3b)
    i++
elsif mode == "v3_dist_unb"
  while i < k
    acc += u3a.distance(u3b)
    i++
elsif mode == "v3_dsq_idiom"
  while i < k
    acc += (b3a - b3b).length_squared
    i++
elsif mode == "v3_dsq_idiom_ls"
  while i < k
    acc += (l3a - l3b).length_squared
    i++
elsif mode == "v3_dsq_fast"
  while i < k
    acc += f3a.distance_squared(f3b)
    i++
elsif mode == "v3_dsq_unb"
  while i < k
    acc += u3a.distance_squared(u3b)
    i++
elsif mode == "v3_saa_idiom"
  while i < k
    acc += (b3a + b3b * sc).z
    i++
elsif mode == "v3_saa_idiom_unb"
  while i < k
    acc += (u3a + u3b * sc).z
    i++
elsif mode == "v3_saa_fast"
  while i < k
    acc += f3a.scale_and_add(f3b, sc).z
    i++
elsif mode == "v3_saa_sbox"
  while i < k
    acc += u3a.scale_and_add_sbox(u3b, sc).z
    i++
elsif mode == "v3_saa_unb"
  while i < k
    acc += u3a.scale_and_add(u3b, sc).z
    i++
elsif mode == "v3_refl_base"
  while i < k
    acc += b3a.reflect(b3b).z
    i++
elsif mode == "v3_refl_fast"
  while i < k
    acc += f3a.reflect(f3b).z
    i++
elsif mode == "v3_refl_unb"
  while i < k
    acc += u3a.reflect(u3b).z
    i++
elsif mode == "v3_refl_unb2"
  while i < k
    acc += u3a.reflect2(u3b).z
    i++
elsif mode == "v3_proj_base"
  while i < k
    acc += b3a.project_onto(b3b).z
    i++
elsif mode == "v3_proj_ls"
  while i < k
    acc += l3a.project_onto(l3b).z
    i++
elsif mode == "v3_proj_fast"
  while i < k
    acc += f3a.project_onto(f3b).z
    i++
elsif mode == "v3_proj_unb"
  while i < k
    acc += u3a.project_onto(u3b).z
    i++
elsif mode == "v3_zero_base"
  while i < k
    acc += ~1.0 unless b3a.zero?
    i++
elsif mode == "v3_zero_ls"
  while i < k
    acc += ~1.0 unless l3a.zero?
    i++
elsif mode == "v3_zero_fast"
  while i < k
    acc += ~1.0 unless f3a.zero?
    i++
elsif mode == "v3_zero_cw"
  while i < k
    acc += ~1.0 unless f3a.zero_cw?
    i++
elsif mode == "v3_cmp_base"
  while i < k
    acc += (b3a <=> b3b)
    i++
elsif mode == "v3_cmp_ls"
  while i < k
    acc += (l3a <=> l3b)
    i++
elsif mode == "v3_cmp_fast"
  while i < k
    acc += (f3a <=> f3b)
    i++
elsif mode == "v3_cmp_unb"
  while i < k
    acc += (u3a <=> u3b)
    i++
elsif mode == "v3_add_into_fast"
  while i < k
    acc += f3a.add_into(f3b, f3o).z
    i++
elsif mode == "v3_add_into_set_fast"
  while i < k
    acc += f3a.add_into_set(f3b, f3o).z
    i++
elsif mode == "v3_add_into_unb"
  while i < k
    acc += u3a.add_into(u3b, u3o).z
    i++
elsif mode == "v3_saa_into_fast"
  while i < k
    acc += f3a.scale_and_add_into(f3b, sc, f3o).z
    i++
elsif mode == "v3_saa_into_set_fast"
  while i < k
    acc += f3a.scale_and_add_into_set(f3b, sc, f3o).z
    i++
elsif mode == "v3_saa_into_unb"
  while i < k
    acc += u3a.scale_and_add_into(u3b, sc, u3o).z
    i++
elsif mode == "v3_norm_into_fast"
  while i < k
    acc += f3a.normalize_into(f3o).z
    i++
elsif mode == "v3_norm_unb"
  while i < k
    acc += u3a.normalize.z
    i++
elsif mode == "v3_norm_into_unb"
  while i < k
    acc += u3a.normalize_into(u3o).z
    i++
elsif mode == "v3_norm_div_unb"
  while i < k
    acc += u3a.normalize_div.z
    i++
elsif mode == "v3_norm_into_div_unb"
  while i < k
    acc += u3a.normalize_into_div(u3o).z
    i++
elsif mode == "v3_cross_into_unb"
  while i < k
    acc += u3a.cross_into(u3b, u3o).z
    i++
elsif mode == "v3_lerp_into_unb"
  while i < k
    acc += u3a.lerp_into(u3b, tt, u3o).z
    i++
elsif mode == "v3_step_idiom"
  while i < k
    b3p = b3p + b3b * dt
    i++
  acc = b3p.x + b3p.y + b3p.z
elsif mode == "v3_step_idiom_unb"
  while i < k
    u3p = u3p + u3b * dt
    i++
  acc = u3p.x + u3p.y + u3p.z
elsif mode == "v3_step_saa_unb"
  while i < k
    u3p = u3p.scale_and_add(u3b, dt)
    i++
  acc = u3p.x + u3p.y + u3p.z
elsif mode == "v3_step_into_unb"
  while i < k
    u3p.scale_and_add_into(u3b, dt, u3p)
    i++
  acc = u3p.x + u3p.y + u3p.z
elsif mode == "v3_step_mut_fast"
  while i < k
    f3p.scale_and_add_mut(f3b, dt)
    i++
  acc = f3p.x + f3p.y + f3p.z
elsif mode == "v3_step_mut_unb"
  while i < k
    u3p.scale_and_add_mut(u3b, dt)
    i++
  acc = u3p.x + u3p.y + u3p.z
elsif mode == "v2_dot_base"
  while i < k
    acc += b2a.dot(b2b)
    i++
elsif mode == "v2_dot_unb"
  while i < k
    acc += u2a.dot(u2b)
    i++
elsif mode == "v2_ls_base"
  while i < k
    acc += b2a.length_squared
    i++
elsif mode == "v2_ls_unb"
  while i < k
    acc += u2a.length_squared
    i++
elsif mode == "v2_len_base"
  while i < k
    acc += b2a.length
    i++
elsif mode == "v2_len_unb"
  while i < k
    acc += u2a.length
    i++
elsif mode == "v2_norm_base"
  while i < k
    acc += b2a.normalize.y
    i++
elsif mode == "v2_norm_unb"
  while i < k
    acc += u2a.normalize.y
    i++
elsif mode == "v2_dist_idiom"
  while i < k
    acc += (b2a - b2b).length
    i++
elsif mode == "v2_dist_unb"
  while i < k
    acc += u2a.distance(u2b)
    i++
elsif mode == "v2_dsq_idiom"
  while i < k
    acc += (b2a - b2b).length_squared
    i++
elsif mode == "v2_dsq_unb"
  while i < k
    acc += u2a.distance_squared(u2b)
    i++
elsif mode == "v2_saa_idiom"
  while i < k
    acc += (b2a + b2b * sc).y
    i++
elsif mode == "v2_saa_unb"
  while i < k
    acc += u2a.scale_and_add(u2b, sc).y
    i++
elsif mode == "v2_step_idiom"
  while i < k
    b2p = b2p + b2b * dt
    i++
  acc = b2p.x + b2p.y
elsif mode == "v2_step_mut_unb"
  while i < k
    u2p.scale_and_add_mut(u2b, dt)
    i++
  acc = u2p.x + u2p.y
elsif mode == "v4_dot_base"
  while i < k
    acc += b4a.dot(b4b)
    i++
elsif mode == "v4_dot_unb"
  while i < k
    acc += u4a.dot(u4b)
    i++
elsif mode == "v4_ls_base"
  while i < k
    acc += b4a.length_squared
    i++
elsif mode == "v4_ls_unb"
  while i < k
    acc += u4a.length_squared
    i++
elsif mode == "v4_len_base"
  while i < k
    acc += b4a.length
    i++
elsif mode == "v4_len_unb"
  while i < k
    acc += u4a.length
    i++
elsif mode == "v4_norm_base"
  while i < k
    acc += b4a.normalize.w
    i++
elsif mode == "v4_norm_unb"
  while i < k
    acc += u4a.normalize.w
    i++
elsif mode == "v4_dist_idiom"
  while i < k
    acc += (b4a - b4b).length
    i++
elsif mode == "v4_dist_unb"
  while i < k
    acc += u4a.distance(u4b)
    i++
elsif mode == "v4_dsq_idiom"
  while i < k
    acc += (b4a - b4b).length_squared
    i++
elsif mode == "v4_dsq_unb"
  while i < k
    acc += u4a.distance_squared(u4b)
    i++
elsif mode == "v4_saa_idiom"
  while i < k
    acc += (b4a + b4b * sc).w
    i++
elsif mode == "v4_saa_unb"
  while i < k
    acc += u4a.scale_and_add(u4b, sc).w
    i++
elsif mode == "v4_step_idiom"
  while i < k
    b4p = b4p + b4b * dt
    i++
  acc = b4p.x + b4p.y + b4p.z + b4p.w
elsif mode == "v4_step_mut_unb"
  while i < k
    u4p.scale_and_add_mut(u4b, dt)
    i++
  acc = u4p.x + u4p.y + u4p.z + u4p.w
elsif mode == "nb_idiom"
  # (a) today, idiomatic value-semantics code: 6 temporaries per update.
  while i < k
    q = 0
    while q < np
      p = pos_b[q]
      v = vel_b[q]
      d = center_b - p
      r2 = d.length_squared + soft
      kdt = grav * dt / (r2 * Math.sqrt(r2))
      v = v * damp + d * kdt
      pos_b[q] = p + v * dt
      vel_b[q] = v
      q++
    i++
  pos_b.each -> acc += item.x + item.y + item.z
elsif mode == "nb_idiom_unb"
  # Same source as nb_idiom on the landed class (unboxed core ops + fixed
  # length_squared): what existing user code gets for free.
  while i < k
    q = 0
    while q < np
      p = pos_u[q]
      v = vel_u[q]
      d = center_u - p
      r2 = d.length_squared + soft
      kdt = grav * dt / (r2 * Math.sqrt(r2))
      v = v * damp + d * kdt
      pos_u[q] = p + v * dt
      vel_u[q] = v
      q++
    i++
  pos_u.each -> acc += item.x + item.y + item.z
elsif mode == "nb_saa_unb"
  # (b1) value semantics kept, fused with scale_and_add: 4 temporaries.
  while i < k
    q = 0
    while q < np
      p = pos_u[q]
      v = vel_u[q]
      d = center_u - p
      r2 = d.length_squared + soft
      kdt = grav * dt / (r2 * Math.sqrt(r2))
      v = (v * damp).scale_and_add(d, kdt)
      pos_u[q] = p.scale_and_add(v, dt)
      vel_u[q] = v
      q++
    i++
  pos_u.each -> acc += item.x + item.y + item.z
elsif mode == "nb_saa_scale_unb"
  # (b1') value semantics, named `scale` instead of the overloaded `*`.
  while i < k
    q = 0
    while q < np
      p = pos_u[q]
      v = vel_u[q]
      d = center_u - p
      r2 = d.length_squared + soft
      kdt = grav * dt / (r2 * Math.sqrt(r2))
      v = v.scale(damp).scale_and_add(d, kdt)
      pos_u[q] = p.scale_and_add(v, dt)
      vel_u[q] = v
      q++
    i++
  pos_u.each -> acc += item.x + item.y + item.z
elsif mode == "nb_into_unb"
  # (b2) glMatrix out-param style with one scratch vector: 0 temporaries.
  while i < k
    q = 0
    while q < np
      p = pos_u[q]
      v = vel_u[q]
      center_u.sub_into(p, scratch_u)
      r2 = scratch_u.length_squared + soft
      kdt = grav * dt / (r2 * Math.sqrt(r2))
      v.scale_into(damp, v)
      v.scale_and_add_into(scratch_u, kdt, v)
      p.scale_and_add_into(v, dt, p)
      q++
    i++
  pos_u.each -> acc += item.x + item.y + item.z
elsif mode == "nb_mut_unb"
  # (b3) Matrix#add_mut-style mutators + sub_into scratch: 0 temporaries.
  while i < k
    q = 0
    while q < np
      p = pos_u[q]
      v = vel_u[q]
      center_u.sub_into(p, scratch_u)
      r2 = scratch_u.length_squared + soft
      kdt = grav * dt / (r2 * Math.sqrt(r2))
      v.scale_mut(damp).scale_and_add_mut(scratch_u, kdt)
      p.scale_and_add_mut(v, dt)
      q++
    i++
  pos_u.each -> acc += item.x + item.y + item.z
elsif mode == "nb_diff"
  # Numeric divergence of the headline pair: nb_idiom (Base) vs nb_mut_unb
  # (Unb) after <iters> steps; checksum = max |component difference|.
  while i < k
    q = 0
    while q < np
      p = pos_b[q]
      v = vel_b[q]
      d = center_b - p
      r2 = d.length_squared + soft
      kdt = grav * dt / (r2 * Math.sqrt(r2))
      v = v * damp + d * kdt
      pos_b[q] = p + v * dt
      vel_b[q] = v
      pu = pos_u[q]
      vu = vel_u[q]
      center_u.sub_into(pu, scratch_u)
      r2u = scratch_u.length_squared + soft
      kdtu = grav * dt / (r2u * Math.sqrt(r2u))
      vu.scale_mut(damp).scale_and_add_mut(scratch_u, kdtu)
      pu.scale_and_add_mut(vu, dt)
      q++
    i++
  q = 0
  while q < np
    e = (pos_b[q].x - pos_u[q].x).abs + (pos_b[q].y - pos_u[q].y).abs + (pos_b[q].z - pos_u[q].z).abs
    acc = e if e > acc
    q++
elsif mode == "v3_add_base_core"
  while i < k
    acc += (cv3a + cv3b).z
    i++
elsif mode == "v3_add_base_copy"
  while i < k
    acc += (cp3a + cp3b).z
    i++
elsif mode == "v3_scale_base_core"
  while i < k
    acc += (cv3a * sc).z
    i++
elsif mode == "v3_scale_base_copy"
  while i < k
    acc += (cp3a * sc).z
    i++
elsif mode == "v3_cross_base_core"
  while i < k
    acc += cv3a.cross(cv3b).z
    i++
elsif mode == "v3_cross_base_copy"
  while i < k
    acc += cp3a.cross(cp3b).z
    i++
elsif mode == "v3_lerp_base_core"
  while i < k
    acc += cv3a.lerp(cv3b, tt).z
    i++
elsif mode == "v3_lerp_base_copy"
  while i < k
    acc += cp3a.lerp(cp3b, tt).z
    i++
elsif mode == "v3_ls_base_core"
  while i < k
    acc += cv3a.length_squared
    i++
elsif mode == "v3_ls_base_copy"
  while i < k
    acc += cp3a.length_squared
    i++
elsif mode == "v3_len_base_core"
  while i < k
    acc += cv3a.length
    i++
elsif mode == "v3_len_base_copy"
  while i < k
    acc += cp3a.length
    i++
elsif mode == "v3_norm_base_core"
  while i < k
    acc += cv3a.normalize.z
    i++
elsif mode == "v3_norm_base_copy"
  while i < k
    acc += cp3a.normalize.z
    i++
elsif mode == "v3_dist_idiom_core"
  while i < k
    acc += (cv3a - cv3b).length
    i++
elsif mode == "v3_dist_idiom_copy"
  while i < k
    acc += (cp3a - cp3b).length
    i++
elsif mode == "v3_dsq_idiom_core"
  while i < k
    acc += (cv3a - cv3b).length_squared
    i++
elsif mode == "v3_dsq_idiom_copy"
  while i < k
    acc += (cp3a - cp3b).length_squared
    i++
elsif mode == "v3_saa_idiom_core"
  while i < k
    acc += (cv3a + cv3b * sc).z
    i++
elsif mode == "v3_saa_idiom_copy"
  while i < k
    acc += (cp3a + cp3b * sc).z
    i++
elsif mode == "v3_refl_base_core"
  while i < k
    acc += cv3a.reflect(cv3b).z
    i++
elsif mode == "v3_refl_base_copy"
  while i < k
    acc += cp3a.reflect(cp3b).z
    i++
elsif mode == "v3_proj_base_core"
  while i < k
    acc += cv3a.project_onto(cv3b).z
    i++
elsif mode == "v3_proj_base_copy"
  while i < k
    acc += cp3a.project_onto(cp3b).z
    i++
elsif mode == "v3_zero_base_core"
  while i < k
    acc += ~1.0 unless cv3a.zero?
    i++
elsif mode == "v3_zero_base_copy"
  while i < k
    acc += ~1.0 unless cp3a.zero?
    i++
elsif mode == "v3_cmp_base_core"
  while i < k
    acc += (cv3a <=> cv3b)
    i++
elsif mode == "v3_cmp_base_copy"
  while i < k
    acc += (cp3a <=> cp3b)
    i++
elsif mode == "v3_step_idiom_core"
  while i < k
    cv3p = cv3p + cv3b * dt
    i++
  acc = cv3p.x + cv3p.y + cv3p.z
elsif mode == "v3_step_idiom_copy"
  while i < k
    cp3p = cp3p + cp3b * dt
    i++
  acc = cp3p.x + cp3p.y + cp3p.z
elsif mode == "v2_dot_base_core"
  while i < k
    acc += cv2a.dot(cv2b)
    i++
elsif mode == "v2_ls_base_core"
  while i < k
    acc += cv2a.length_squared
    i++
elsif mode == "v2_len_base_core"
  while i < k
    acc += cv2a.length
    i++
elsif mode == "v2_norm_base_core"
  while i < k
    acc += cv2a.normalize.y
    i++
elsif mode == "v2_dist_idiom_core"
  while i < k
    acc += (cv2a - cv2b).length
    i++
elsif mode == "v2_dsq_idiom_core"
  while i < k
    acc += (cv2a - cv2b).length_squared
    i++
elsif mode == "v2_saa_idiom_core"
  while i < k
    acc += (cv2a + cv2b * sc).y
    i++
elsif mode == "v2_step_idiom_core"
  while i < k
    cv2p = cv2p + cv2b * dt
    i++
  acc = cv2p.x + cv2p.y
elsif mode == "v4_dot_base_core"
  while i < k
    acc += cv4a.dot(cv4b)
    i++
elsif mode == "v4_ls_base_core"
  while i < k
    acc += cv4a.length_squared
    i++
elsif mode == "v4_len_base_core"
  while i < k
    acc += cv4a.length
    i++
elsif mode == "v4_norm_base_core"
  while i < k
    acc += cv4a.normalize.w
    i++
elsif mode == "v4_dist_idiom_core"
  while i < k
    acc += (cv4a - cv4b).length
    i++
elsif mode == "v4_dsq_idiom_core"
  while i < k
    acc += (cv4a - cv4b).length_squared
    i++
elsif mode == "v4_saa_idiom_core"
  while i < k
    acc += (cv4a + cv4b * sc).w
    i++
elsif mode == "v4_step_idiom_core"
  while i < k
    cv4p = cv4p + cv4b * dt
    i++
  acc = cv4p.x + cv4p.y + cv4p.z + cv4p.w
elsif mode == "nb_idiom_core"
  # (a) control on the real core Vec3.
  while i < k
    q = 0
    while q < np
      p = pos_c[q]
      v = vel_c[q]
      d = center_c - p
      r2 = d.length_squared + soft
      kdt = grav * dt / (r2 * Math.sqrt(r2))
      v = v * damp + d * kdt
      pos_c[q] = p + v * dt
      vel_c[q] = v
      q++
    i++
  pos_c.each -> acc += item.x + item.y + item.z
elsif mode == "nb_idiom_copy"
  # (a) control on Vec3Copy.
  while i < k
    q = 0
    while q < np
      p = pos_k[q]
      v = vel_k[q]
      d = center_k - p
      r2 = d.length_squared + soft
      kdt = grav * dt / (r2 * Math.sqrt(r2))
      v = v * damp + d * kdt
      pos_k[q] = p + v * dt
      vel_k[q] = v
      q++
    i++
  pos_k.each -> acc += item.x + item.y + item.z
elsif mode == "check"
  << "layout " << u3a.x << " " << u3a.y << " " << u3a.z << " " << (u3a == u3a) << " " << type(u3a + u3b)
  << "dot " << b3a.dot(b3b) << " " << u3a.dot(u3b) << " " << u3a.dot_dd(u3b) << " " << f3a.dot_conv(f3b) << " " << f3a.dot_acc(f3b)
  << "dot-mixedT base " << b3a.dot(c3f32) << " " << b3a.dot(c3i64) << " unb " << u3a.dot(c3f32) << " " << u3a.dot(c3i64)
  << "add " << (b3a + b3b).x << " " << (u3a + u3b).x << " | " << (b3a + b3b).z << " " << (u3a + u3b).z
  << "sub " << (b3a - b3b).y << " " << (u3a - u3b).y
  << "scale " << (b3a * sc).y << " " << (u3a * sc).y << " " << u3a.scale_sbox(sc).y
  << "hadamard " << (b3a * b3b).z << " " << (u3a * u3b).z
  << "cross " << b3a.cross(b3b).x << " " << u3a.cross(u3b).x << " " << u3a.cross_into(u3b, u3o).x << " | " << b3a.cross(b3b).z << " " << u3a.cross(u3b).z
  << "lerp " << b3a.lerp(b3b, tt).z << " " << u3a.lerp(u3b, tt).z << " " << u3a.lerp_into(u3b, tt, u3o).z
  << "ls " << b3a.length_squared << " " << f3a.length_squared << " " << u3a.length_squared
  << "len " << b3a.length << " " << f3a.length << " " << u3a.length
  << "norm-recip " << b3a.normalize.x << " " << f3a.normalize.x << " | " << b3a.normalize.y << " " << f3a.normalize.y << " | " << b3a.normalize.z << " " << f3a.normalize.z
  << "norm-div " << b3a.normalize.x << " " << f3a.normalize_div.x << " | " << b3a.normalize.y << " " << f3a.normalize_div.y << " | " << b3a.normalize.z << " " << f3a.normalize_div.z
  << "norm-into " << u3a.normalize.y << " " << u3a.normalize_into(u3o).y << " " << f3a.normalize_into(f3o).y
  << "dist " << (b3a - b3b).length << " " << f3a.distance(f3b) << " " << u3a.distance(u3b)
  << "dsq " << (b3a - b3b).length_squared << " " << f3a.distance_squared(f3b) << " " << u3a.distance_squared(u3b)
  << "saa " << (b3a + b3b * sc).x << " " << f3a.scale_and_add(f3b, sc).x << " " << u3a.scale_and_add(u3b, sc).x << " " << u3a.scale_and_add_sbox(u3b, sc).x << " " << u3a.scale_and_add_into(u3b, sc, u3o).x
  << "refl " << b3a.reflect(b3b).x << " " << f3a.reflect(f3b).x << " " << u3a.reflect(u3b).x << " | " << b3a.reflect(b3b).z << " " << u3a.reflect(u3b).z
  << "refl2 " << b3a.reflect(b3b).x << " " << u3a.reflect2(u3b).x << " | " << b3a.reflect(b3b).y << " " << u3a.reflect2(u3b).y << " | " << b3a.reflect(b3b).z << " " << u3a.reflect2(u3b).z
  << "norm-div-unb " << b3a.normalize.x << " " << u3a.normalize_div.x << " " << u3a.normalize_into_div(u3o).x << " | " << b3a.normalize.z << " " << u3a.normalize_div.z
  << "proj " << b3a.project_onto(b3b).x << " " << f3a.project_onto(f3b).x << " " << u3a.project_onto(u3b).x << " | " << b3a.project_onto(b3b).z << " " << u3a.project_onto(u3b).z
  << "zero " << b3a.zero? << " " << f3a.zero? << " " << u3a.zero? << " " << f3a.zero_cw?
  << "cmp " << (b3a <=> b3b) << " " << (u3a <=> u3b) << " " << (b3b <=> b3a) << " " << (u3b <=> u3a) << " " << (b3a <=> b3a) << " " << (u3a <=> u3a)
  << "zero-vec normalize " << z0b.normalize.x << " " << z0u.normalize.x << " " << z0u.normalize_into(u3o).x
  << "zero-vec zero? " << z0b.zero? << " " << z0u.zero?
  << "tiny normalize " << tinyb.normalize.x << " " << tinyu.normalize.x
  << "tiny zero? " << tinyb.zero? << " " << tinyu.zero?
  << "v2 " << b2a.dot(b2b) << " " << u2a.dot(u2b) << " | " << b2a.normalize.x << " " << u2a.normalize.x << " | " << (b2a - b2b).length << " " << u2a.distance(u2b) << " | " << (b2a + b2b * sc).x << " " << u2a.scale_and_add(u2b, sc).x
  << "v4 " << b4a.dot(b4b) << " " << u4a.dot(u4b) << " | " << b4a.normalize.x << " " << u4a.normalize.x << " | " << (b4a - b4b).length << " " << u4a.distance(u4b) << " | " << (b4a + b4b * sc).w << " " << u4a.scale_and_add(u4b, sc).w
  << "controls " << cv3a.normalize.x << " " << cp3a.normalize.x << " " << cv3a.reflect(cv3b).z << " " << cp3a.reflect(cp3b).z << " " << (cv3a <=> cv3b) << " " << (cp3a <=> cp3b) << " " << cp3a.length << " " << type(cp3a + cp3b)
  << "alias cross " << u3a.cross(u3b).y << " " << u3a.cross_into(u3b, u3a).y
  << "alias saa " << (u3b + u3b * sc).z << " " << u3b.scale_and_add_into(u3b, sc, u3b).z
t1 = clock()
ns = k > 0 ? (t1 - t0) * ~1000000000.0 / k : ~0.0
<< "ns/op: " << ns << " checksum: " << acc
