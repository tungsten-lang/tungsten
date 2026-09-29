  # ---- core/numeric/vec3.w: replace the existing binary-op bodies ----
  # `b = @1.components` is untyped, so a bare `b[i]` is a boxed value and
  # every `a[i] op b[i]` runs the generic w_add/w_mul type chain; reading
  # it as `(b[i] ## T)` unboxes it once and the op is a single fadd/fmul.

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

  -> dot/1
    a = @components
    b = @1.components
    a[0] * (b[0] ## T) + a[1] * (b[1] ## T) + a[2] * (b[2] ## T)

  -> lerp/2
    a = @components
    b = @1.components
    t = @2 ## T
    class.new([
      a[0] + ((b[0] ## T) - a[0]) * t,
      a[1] + ((b[1] ## T) - a[1]) * t,
      a[2] + ((b[2] ## T) - a[2]) * t
    ] ## T[3])

  -> cross/1
    a = @components
    b = @1.components
    bx = b[0] ## T
    by = b[1] ## T
    bz = b[2] ## T
    class.new([a[1] * bz - a[2] * by, a[2] * bx - a[0] * bz, a[0] * by - a[1] * bx] ## T[3])

  # ---- new / overriding Vector generics ----

  -> length_squared
    a = @components
    a[0] * a[0] + a[1] * a[1] + a[2] * a[2]

  -> length
    a = @components
    Math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2])

  # Divide (not reciprocal-multiply): measured identical cost, and stays
  # bit-identical to `self / length` (zero vector -> NaN components, as today).
  -> normalize
    a = @components
    l = Math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2])
    class.new([a[0] / l, a[1] / l, a[2] / l] ## T[3])

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

  # self + other * s in one pass (pmndrs scaleAndAdd).
  -> scale_and_add/2
    a = @components
    b = @1.components
    s = @2 ## T
    class.new([a[0] + (b[0] ## T) * s, a[1] + (b[1] ## T) * s, a[2] + (b[2] ## T) * s] ## T[3])

  # Named scalar multiply: same result as `v * s`, but a plain method skips
  # the (Vector)/(Number) overload resolution.
  -> scale/1
    s = @1 ## T
    a = @components
    class.new([a[0] * s, a[1] * s, a[2] * s] ## T[3])

  # `d + d`, not `2 * d`: an int literal times a typed float lowers boxed.
  -> reflect/1
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

  # Same squared-length test as Vector#zero? (true on underflow), inlined.
  -> zero?
    a = @components
    a[0] * a[0] + a[1] * a[1] + a[2] * a[2] == 0

  # ---- allocation-free forms (out may be self or an operand) ----

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
    l = Math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2])
    @1.set(a[0] / l, a[1] / l, a[2] / l)

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
