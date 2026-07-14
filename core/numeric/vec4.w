# Vec4 — 4-component vector. Maps to Metal's float4 / half4 / int4 etc.
# Byte-equivalent to Quaternion<T> but without quaternion algebra
# (no conjugate, no Cayley–Dickson product, no scalar/imaginary split).
# Literal: %v4-f32[0.44 0.65 0.24 0.88]
+ Vec4<T> < Vector<T>
  - data
    T components[4]

  -> new(@components ## T[4])

  ## Component accessors — geometry namespace (graphics convention).

  -> x
    @components[0]
  -> y
    @components[1]
  -> z
    @components[2]
  -> w
    @components[3]

  # Fixed-width arithmetic avoids the generic Vector map/zip temporaries.

  -> negate
    a = @components
    class.new([-a[0], -a[1], -a[2], -a[3]] ## T[4])

  -> +/1
    other = @1.components
    a = @components
    class.new([a[0] + other[0], a[1] + other[1], a[2] + other[2], a[3] + other[3]] ## T[4])

  -> -/1
    other = @1.components
    a = @components
    class.new([a[0] - other[0], a[1] - other[1], a[2] - other[2], a[3] - other[3]] ## T[4])

  -> */1(Vector)
    other = @1.components
    a = @components
    class.new([a[0] * other[0], a[1] * other[1], a[2] * other[2], a[3] * other[3]] ## T[4])

  -> */1(Number)
    s = @1
    a = @components
    class.new([a[0] * s, a[1] * s, a[2] * s, a[3] * s] ## T[4])

  -> //1(Vector)
    other = @1.components
    a = @components
    class.new([a[0] / other[0], a[1] / other[1], a[2] / other[2], a[3] / other[3]] ## T[4])

  -> //1(Number)
    s = @1
    a = @components
    class.new([a[0] / s, a[1] / s, a[2] / s, a[3] / s] ## T[4])

  -> ⊙/1
    other = @1.components
    a = @components
    class.new([a[0] * other[0], a[1] * other[1], a[2] * other[2], a[3] * other[3]] ## T[4])

  -> dot/1
    other = @1.components
    a = @components
    a[0] * other[0] + a[1] * other[1] + a[2] * other[2] + a[3] * other[3]

  -> lerp/2
    other = @1.components
    t = @2
    a = @components
    class.new([
      a[0] + (other[0] - a[0]) * t,
      a[1] + (other[1] - a[1]) * t,
      a[2] + (other[2] - a[2]) * t,
      a[3] + (other[3] - a[3]) * t
    ] ## T[4])

  ## Color namespace.

  -> r
    @components[0]
  -> g
    @components[1]
  -> b
    @components[2]
  -> a
    @components[3]

  ## Texture-coordinate namespace.

  -> s
    @components[0]
  -> t
    @components[1]
  -> p
    @components[2]
  -> q
    @components[3]

  ## SIMD swizzles — 2-component (return Vec2).

  -> xy
    Vec2.new([@components[0], @components[1]] ## T[2])
  -> zw
    Vec2.new([@components[2], @components[3]] ## T[2])
  -> xz
    Vec2.new([@components[0], @components[2]] ## T[2])
  -> yw
    Vec2.new([@components[1], @components[3]] ## T[2])

  ## SIMD swizzles — 3-component (return Vec3).

  -> xyz
    Vec3.new([@components[0], @components[1], @components[2]] ## T[3])
  -> yzw
    Vec3.new([@components[1], @components[2], @components[3]] ## T[3])
  -> zyx
    Vec3.new([@components[2], @components[1], @components[0]] ## T[3])

  # Cross-product rotations (on the xyz subset).
  -> yzx
    Vec3.new([@components[1], @components[2], @components[0]] ## T[3])
  -> zxy
    Vec3.new([@components[2], @components[0], @components[1]] ## T[3])

  ## SIMD swizzles — 4-component (return Vec4).

  -> xyzw
    class.new(@components)
  -> wxyz
    class.new([@components[3], @components[0], @components[1], @components[2]] ## T[4])
  -> wzyx
    class.new([@components[3], @components[2], @components[1], @components[0]] ## T[4])

  ## Broadcasts — one component to all four lanes.

  -> xxxx
    class.new([@components[0], @components[0], @components[0], @components[0]] ## T[4])
  -> yyyy
    class.new([@components[1], @components[1], @components[1], @components[1]] ## T[4])
  -> zzzz
    class.new([@components[2], @components[2], @components[2], @components[2]] ## T[4])
  -> wwww
    class.new([@components[3], @components[3], @components[3], @components[3]] ## T[4])

  ## Color namespace — common formats.

  -> rgb
    Vec3.new([@components[0], @components[1], @components[2]] ## T[3])
  -> bgr
    Vec3.new([@components[2], @components[1], @components[0]] ## T[3])
  -> rgba
    class.new(@components)
  -> bgra
    class.new([@components[2], @components[1], @components[0], @components[3]] ## T[4])
  -> argb
    class.new([@components[3], @components[0], @components[1], @components[2]] ## T[4])
  -> abgr
    class.new([@components[3], @components[2], @components[1], @components[0]] ## T[4])
