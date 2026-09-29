  # ---- core/numeric/vec2.w: generated from the same pattern as vec3_bodies.w;
  # compiled and parity-checked vs core Vec2<f64>/Vec2<i64> (paste_check24). ----

  -> +/1
    a = @components
    b = @1.components
    class.new([a[0] + (b[0] ## T), a[1] + (b[1] ## T)] ## T[2])

  -> -/1
    a = @components
    b = @1.components
    class.new([a[0] - (b[0] ## T), a[1] - (b[1] ## T)] ## T[2])

  -> */1(Vector)
    a = @components
    b = @1.components
    class.new([a[0] * (b[0] ## T), a[1] * (b[1] ## T)] ## T[2])

  -> */1(Number)
    s = @1 ## T
    a = @components
    class.new([a[0] * s, a[1] * s] ## T[2])

  -> dot/1
    a = @components
    b = @1.components
    a[0] * (b[0] ## T) + a[1] * (b[1] ## T)

  -> lerp/2
    a = @components
    b = @1.components
    t = @2 ## T
    class.new([a[0] + ((b[0] ## T) - a[0]) * t, a[1] + ((b[1] ## T) - a[1]) * t] ## T[2])

  -> length_squared
    a = @components
    a[0] * a[0] + a[1] * a[1]

  -> length
    a = @components
    Math.sqrt(a[0] * a[0] + a[1] * a[1])

  -> normalize
    a = @components
    l = Math.sqrt(a[0] * a[0] + a[1] * a[1])
    class.new([a[0] / l, a[1] / l] ## T[2])

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

  -> scale/1
    s = @1 ## T
    a = @components
    class.new([a[0] * s, a[1] * s] ## T[2])

  -> reflect/1
    a = @components
    n = @1.components
    nx = n[0] ## T
    ny = n[1] ## T
    d = a[0] * nx + a[1] * ny
    k = d + d
    class.new([a[0] - nx * k, a[1] - ny * k] ## T[2])

  -> project_onto/1
    a = @components
    b = @1.components
    bx = b[0] ## T
    by = b[1] ## T
    k = (a[0] * bx + a[1] * by) / (bx * bx + by * by)
    class.new([bx * k, by * k] ## T[2])

  -> zero?
    a = @components
    a[0] * a[0] + a[1] * a[1] == 0

  -> set/2
    a = @components
    a[0] = @1
    a[1] = @2
    self

  -> add_into/2
    a = @components
    b = @1.components
    @2.set(a[0] + (b[0] ## T), a[1] + (b[1] ## T))

  -> sub_into/2
    a = @components
    b = @1.components
    @2.set(a[0] - (b[0] ## T), a[1] - (b[1] ## T))

  -> scale_into/2
    a = @components
    s = @1 ## T
    @2.set(a[0] * s, a[1] * s)

  -> scale_and_add_into/3
    a = @components
    b = @1.components
    s = @2 ## T
    @3.set(a[0] + (b[0] ## T) * s, a[1] + (b[1] ## T) * s)

  -> normalize_into/1
    a = @components
    l = Math.sqrt(a[0] * a[0] + a[1] * a[1])
    @1.set(a[0] / l, a[1] / l)

  -> lerp_into/3
    a = @components
    b = @1.components
    t = @2 ## T
    @3.set(a[0] + ((b[0] ## T) - a[0]) * t, a[1] + ((b[1] ## T) - a[1]) * t)

  -> add_mut/1
    a = @components
    b = @1.components
    a[0] = a[0] + (b[0] ## T)
    a[1] = a[1] + (b[1] ## T)
    self

  -> scale_mut/1
    a = @components
    s = @1 ## T
    a[0] = a[0] * s
    a[1] = a[1] * s
    self

  -> scale_and_add_mut/2
    a = @components
    b = @1.components
    s = @2 ## T
    a[0] = a[0] + (b[0] ## T) * s
    a[1] = a[1] + (b[1] ## T) * s
    self
