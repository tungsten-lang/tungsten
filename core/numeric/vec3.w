# Vec3 — 3-component vector. Maps to Metal's float3 / half3 / int3 etc.
# Note: Metal's float3 is padded to 16 bytes for alignment; the dense
# 12-byte form is `packed_float3` (forthcoming).
# Literal: %v3-f32[0.93 0.56 1.23]
+ Vec3<T> < Vector<T>
  - data
    T components[3]

  -> new(@components ## T[3])

  ## Component accessors — geometry namespace.

  -> x
    components[0]
  -> y
    components[1]
  -> z
    components[2]

  -> */1(Vector)
    other = @1.components
    class.new([components[0] * other[0], components[1] * other[1], components[2] * other[2]] ## T[3])

  -> */1(Number)
    s = @1
    class.new([components[0] * s, components[1] * s, components[2] * s] ## T[3])

  -> //1(Vector)
    other = @1.components
    class.new([components[0] / other[0], components[1] / other[1], components[2] / other[2]] ## T[3])

  -> //1(Number)
    s = @1
    class.new([components[0] / s, components[1] / s, components[2] / s] ## T[3])

  ## Color namespace.

  -> r
    components[0]
  -> g
    components[1]
  -> b
    components[2]

  ## Texture-coordinate namespace.

  -> s
    components[0]
  -> t
    components[1]
  -> p
    components[2]

  ## Cross product — Vec3-specific.
  # a × b = (a.y·b.z − a.z·b.y, a.z·b.x − a.x·b.z, a.x·b.y − a.y·b.x)
  -> cross/1
    a = components
    b = @1.components
    class.new([
      a[1] * b[2] - a[2] * b[1],
      a[2] * b[0] - a[0] * b[2],
      a[0] * b[1] - a[1] * b[0]
    ] ## T[3])

  ## SIMD swizzles — 2-component (return Vec2).

  -> xy
    Vec2.new([components[0], components[1]] ## T[2])
  -> xz
    Vec2.new([components[0], components[2]] ## T[2])
  -> yz
    Vec2.new([components[1], components[2]] ## T[2])
  -> yx
    Vec2.new([components[1], components[0]] ## T[2])
  -> zx
    Vec2.new([components[2], components[0]] ## T[2])
  -> zy
    Vec2.new([components[2], components[1]] ## T[2])

  ## SIMD swizzles — 3-component (return Vec3).

  -> xyz
    class.new(components)
  -> zyx
    class.new([components[2], components[1], components[0]] ## T[3])

  # Cross-product rotations: `a × b = a.yzx * b.zxy − a.zxy * b.yzx`.
  -> yzx
    class.new([components[1], components[2], components[0]] ## T[3])
  -> zxy
    class.new([components[2], components[0], components[1]] ## T[3])

  # Broadcasts.
  -> xxx
    class.new([components[0], components[0], components[0]] ## T[3])
  -> yyy
    class.new([components[1], components[1], components[1]] ## T[3])
  -> zzz
    class.new([components[2], components[2], components[2]] ## T[3])

  ## Color namespace 3-component.

  -> rgb
    class.new(components)
  -> bgr
    class.new([components[2], components[1], components[0]] ## T[3])
