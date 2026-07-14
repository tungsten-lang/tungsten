# Vec2 — 2-component vector. Maps to Metal's float2 / half2 / int2 etc.
# Literal: %v2-f32[3.2 5.5]
+ Vec2<T> < Vector<T>
  - data
    T components[2]

  -> new(@components ## T[2])

  ## Component accessors — geometry namespace.

  -> x
    @components[0]
  -> y
    @components[1]

  # Fixed-width arithmetic avoids the generic Vector map/zip temporaries.

  -> negate
    a = @components
    class.new([-a[0], -a[1]] ## T[2])

  -> +/1
    other = @1.components
    a = @components
    class.new([a[0] + other[0], a[1] + other[1]] ## T[2])

  -> -/1
    other = @1.components
    a = @components
    class.new([a[0] - other[0], a[1] - other[1]] ## T[2])

  -> */1(Vector)
    other = @1.components
    a = @components
    class.new([a[0] * other[0], a[1] * other[1]] ## T[2])

  -> */1(Number)
    s = @1
    a = @components
    class.new([a[0] * s, a[1] * s] ## T[2])

  -> //1(Vector)
    other = @1.components
    a = @components
    class.new([a[0] / other[0], a[1] / other[1]] ## T[2])

  -> //1(Number)
    s = @1
    a = @components
    class.new([a[0] / s, a[1] / s] ## T[2])

  -> ⊙/1
    other = @1.components
    a = @components
    class.new([a[0] * other[0], a[1] * other[1]] ## T[2])

  -> dot/1
    other = @1.components
    a = @components
    a[0] * other[0] + a[1] * other[1]

  -> lerp/2
    other = @1.components
    t = @2
    a = @components
    class.new([
      a[0] + (other[0] - a[0]) * t,
      a[1] + (other[1] - a[1]) * t
    ] ## T[2])

  ## Color namespace.

  -> r
    @components[0]
  -> g
    @components[1]

  ## Texture-coordinate namespace.

  -> s
    @components[0]
  -> t
    @components[1]

  ## SIMD swizzles — return Vec2<T>.

  -> xy
    class.new(@components)
  -> yx
    class.new([@components[1], @components[0]] ## T[2])
  -> xx
    class.new([@components[0], @components[0]] ## T[2])
  -> yy
    class.new([@components[1], @components[1]] ## T[2])
