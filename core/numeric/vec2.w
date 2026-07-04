# Vec2 — 2-component vector. Maps to Metal's float2 / half2 / int2 etc.
# Literal: %v2-f32[3.2 5.5]
+ Vec2<T> < Vector<T>
  - data
    T components[2]

  -> new(@components ## T[2])

  ## Component accessors — geometry namespace.

  -> x
    components[0]
  -> y
    components[1]

  -> */1(Vector)
    other = @1.components
    class.new([components[0] * other[0], components[1] * other[1]] ## T[2])

  -> */1(Number)
    s = @1
    class.new([components[0] * s, components[1] * s] ## T[2])

  -> //1(Vector)
    other = @1.components
    class.new([components[0] / other[0], components[1] / other[1]] ## T[2])

  -> //1(Number)
    s = @1
    class.new([components[0] / s, components[1] / s] ## T[2])

  ## Color namespace.

  -> r
    components[0]
  -> g
    components[1]

  ## Texture-coordinate namespace.

  -> s
    components[0]
  -> t
    components[1]

  ## SIMD swizzles — return Vec2<T>.

  -> xy
    class.new(components)
  -> yx
    class.new([components[1], components[0]] ## T[2])
  -> xx
    class.new([components[0], components[0]] ## T[2])
  -> yy
    class.new([components[1], components[1]] ## T[2])
