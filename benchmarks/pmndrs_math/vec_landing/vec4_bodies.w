  # ---- core/numeric/vec4.w: generated from the same pattern as vec3_bodies.w;
  # compiled and parity-checked vs core Vec4<f64>/Vec4<i64> (paste_check24). ----

  -> +/1
    a = @components
    b = @1.components
    class.new([a[0] + (b[0] ## T), a[1] + (b[1] ## T), a[2] + (b[2] ## T), a[3] + (b[3] ## T)] ## T[4])

  -> -/1
    a = @components
    b = @1.components
    class.new([a[0] - (b[0] ## T), a[1] - (b[1] ## T), a[2] - (b[2] ## T), a[3] - (b[3] ## T)] ## T[4])

  -> */1(Vector)
    a = @components
    b = @1.components
    class.new([a[0] * (b[0] ## T), a[1] * (b[1] ## T), a[2] * (b[2] ## T), a[3] * (b[3] ## T)] ## T[4])

  -> */1(Number)
    s = @1 ## T
    a = @components
    class.new([a[0] * s, a[1] * s, a[2] * s, a[3] * s] ## T[4])

  -> dot/1
    a = @components
    b = @1.components
    a[0] * (b[0] ## T) + a[1] * (b[1] ## T) + a[2] * (b[2] ## T) + a[3] * (b[3] ## T)

  -> lerp/2
    a = @components
    b = @1.components
    t = @2 ## T
    class.new([a[0] + ((b[0] ## T) - a[0]) * t, a[1] + ((b[1] ## T) - a[1]) * t, a[2] + ((b[2] ## T) - a[2]) * t, a[3] + ((b[3] ## T) - a[3]) * t] ## T[4])

  -> length_squared
    a = @components
    a[0] * a[0] + a[1] * a[1] + a[2] * a[2] + a[3] * a[3]

  -> length
    a = @components
    Math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2] + a[3] * a[3])

  -> normalize
    a = @components
    l = Math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2] + a[3] * a[3])
    class.new([a[0] / l, a[1] / l, a[2] / l, a[3] / l] ## T[4])

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
    class.new([a[0] + (b[0] ## T) * s, a[1] + (b[1] ## T) * s, a[2] + (b[2] ## T) * s, a[3] + (b[3] ## T) * s] ## T[4])

  -> scale/1
    s = @1 ## T
    a = @components
    class.new([a[0] * s, a[1] * s, a[2] * s, a[3] * s] ## T[4])

  -> reflect/1
    a = @components
    n = @1.components
    nx = n[0] ## T
    ny = n[1] ## T
    nz = n[2] ## T
    nw = n[3] ## T
    d = a[0] * nx + a[1] * ny + a[2] * nz + a[3] * nw
    k = d + d
    class.new([a[0] - nx * k, a[1] - ny * k, a[2] - nz * k, a[3] - nw * k] ## T[4])

  -> project_onto/1
    a = @components
    b = @1.components
    bx = b[0] ## T
    by = b[1] ## T
    bz = b[2] ## T
    bw = b[3] ## T
    k = (a[0] * bx + a[1] * by + a[2] * bz + a[3] * bw) / (bx * bx + by * by + bz * bz + bw * bw)
    class.new([bx * k, by * k, bz * k, bw * k] ## T[4])

  -> zero?
    a = @components
    a[0] * a[0] + a[1] * a[1] + a[2] * a[2] + a[3] * a[3] == 0

  -> set/4
    a = @components
    a[0] = @1
    a[1] = @2
    a[2] = @3
    a[3] = @4
    self

  -> add_into/2
    a = @components
    b = @1.components
    @2.set(a[0] + (b[0] ## T), a[1] + (b[1] ## T), a[2] + (b[2] ## T), a[3] + (b[3] ## T))

  -> sub_into/2
    a = @components
    b = @1.components
    @2.set(a[0] - (b[0] ## T), a[1] - (b[1] ## T), a[2] - (b[2] ## T), a[3] - (b[3] ## T))

  -> scale_into/2
    a = @components
    s = @1 ## T
    @2.set(a[0] * s, a[1] * s, a[2] * s, a[3] * s)

  -> scale_and_add_into/3
    a = @components
    b = @1.components
    s = @2 ## T
    @3.set(a[0] + (b[0] ## T) * s, a[1] + (b[1] ## T) * s, a[2] + (b[2] ## T) * s, a[3] + (b[3] ## T) * s)

  -> normalize_into/1
    a = @components
    l = Math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2] + a[3] * a[3])
    @1.set(a[0] / l, a[1] / l, a[2] / l, a[3] / l)

  -> lerp_into/3
    a = @components
    b = @1.components
    t = @2 ## T
    @3.set(a[0] + ((b[0] ## T) - a[0]) * t, a[1] + ((b[1] ## T) - a[1]) * t, a[2] + ((b[2] ## T) - a[2]) * t, a[3] + ((b[3] ## T) - a[3]) * t)

  -> add_mut/1
    a = @components
    b = @1.components
    a[0] = a[0] + (b[0] ## T)
    a[1] = a[1] + (b[1] ## T)
    a[2] = a[2] + (b[2] ## T)
    a[3] = a[3] + (b[3] ## T)
    self

  -> scale_mut/1
    a = @components
    s = @1 ## T
    a[0] = a[0] * s
    a[1] = a[1] * s
    a[2] = a[2] * s
    a[3] = a[3] * s
    self

  -> scale_and_add_mut/2
    a = @components
    b = @1.components
    s = @2 ## T
    a[0] = a[0] + (b[0] ## T) * s
    a[1] = a[1] + (b[1] ## T) * s
    a[2] = a[2] + (b[2] ## T) * s
    a[3] = a[3] + (b[3] ## T) * s
    self
