# QuaternionMetal — Metal-aligned counterpart of Quaternion<T>. Same
# algebra (Hamilton product, non-commutative, associative, one of the
# four normed division algebras), different storage layout.
#
# Storage is **scalar-LAST**, byte-aliased to Metal's `float4` where the
# scalar lives at `.w`:
#
#   components[0] = x (i coefficient)
#   components[1] = y (j coefficient)
#   components[2] = z (k coefficient)
#   components[3] = w (scalar / real part)
#
# This is the layout to reach for at GPU boundaries — `metal_emitter`
# lowers `## quaternion_metal` parameters to MSL `float4` with zero
# repacking. For math-natural Cayley–Dickson recursion (where Octonion
# uses Quaternion as its half), reach for the scalar-first `Quaternion<T>`
# instead.
#
# Literal: %h4-float4[x y z w] (Metal form; the `float4` in the type
# slot signals the scalar-last layout).
+ QuaternionMetal<T> < Hypercomplex<T>
  noncommutative :*

  - data
    T components[4]

  -> new(@components ## T[4])

  -> .dimension
    4

  -> .scalar_index
    3

  -> .zero
    class.new((0...4).map -> 0)

  -> .one
    class.new((0...4).map -> item == 3 ? 1 : 0)

  -> .basis(n)
    raise ArgumentError, "basis index out of range: [n]" if n < 0 || n >= 4
    idx = n == 0 ? 3 : n - 1
    class.new((0...4).map -> item == idx ? 1 : 0)

  -> .real(value)
    class.new([0, 0, 0, value] ## T[4])

  -> .pure(values)
    class.new([values[0], values[1], values[2], 0] ## T[4])

  # Cayley–Dickson half: same algebra structure as Quaternion (doubling
  # Complex), just stored scalar-LAST for Metal float4 alignment.
  -> half_class
    Complex

  # Scalar lives at components[3] — matches Metal's float4.w.
  -> scalar_index
    3

  ## Scalar + 3-vector accessors (graphics convention: .w is the scalar).

  -> x
    components[0]
  -> y
    components[1]
  -> z
    components[2]
  -> w
    components[3]

  ## Hamilton-basis accessors (.h is the scalar; .i/.j/.k the basis units).

  -> i
    components[0]
  -> j
    components[1]
  -> k
    components[2]
  -> h
    components[3]

  ## Cayley–Dickson basis accessors (.e0 is the scalar by convention).

  -> e1
    components[0]
  -> e2
    components[1]
  -> e3
    components[2]
  -> e0
    components[3]

  -> e(n)
    n == 0 ? components[3] : components[n - 1]

  ## Color-namespace accessors (RGBA). Alpha at components[3] matches .w
  ## and Metal's MTLPixelFormatRGBA*.

  -> r
    components[0]
  -> g
    components[1]
  -> b
    components[2]
  -> a
    components[3]

  ## Texture-coordinate-namespace accessors (STPQ).

  -> s
    components[0]
  -> t
    components[1]
  -> p
    components[2]
  -> q
    components[3]

  ## Hamilton product, scalar-LAST layout.
  -> */1
    return scale(@1) if scalar_like?(@1)
    x1 = components[0]
    y1 = components[1]
    z1 = components[2]
    w1 = components[3]
    x2 = @1.components[0]
    y2 = @1.components[1]
    z2 = @1.components[2]
    w2 = @1.components[3]
    class.new([
      w1 * x2 + x1 * w2 + y1 * z2 - z1 * y2,
      w1 * y2 - x1 * z2 + y1 * w2 + z1 * x2,
      w1 * z2 + x1 * y2 - y1 * x2 + z1 * w2,
      w1 * w2 - x1 * x2 - y1 * y2 - z1 * z2
    ] ## T[4])

  ## Optimized squaring: q² = (2wx, 2wy, 2wz, w² − x² − y² − z²).
  ## Closed-form Hamilton squaring in scalar-LAST layout — ~10 mults vs
  ## general */1's ~28 (64% reduction).
  -> sq
    class.new([
      2 * w * x,
      2 * w * y,
      2 * w * z,
      w * w - x * x - y * y - z * z
    ] ## T[4])

  ## Conversion to math-layout form (scalar moves from index 3 to
  ## index 0). Lowers to a single SIMD shuffle.
  -> to_math
    Quaternion.new([components[3], components[0], components[1], components[2]] ## T[4])

  ## SIMD swizzles — return Vec2<T> / Vec3<T> / Vec4<T> values byte-
  ## aligned to Metal's float2 / float3 / float4. Each body's literal-
  ## array-with-constant-indices pattern lowers to one shufflevector
  ## or native SIMD shuffle.

  ## 2-component — geometry namespace.

  -> xy
    Vec2.new([components[0], components[1]] ## T[2])
  -> zw
    Vec2.new([components[2], components[3]] ## T[2])

  ## 3-component — geometry namespace.

  # The imaginary 3-vector (i, j, k) — the "vector part" of a quaternion.
  -> xyz
    Vec3.new([components[0], components[1], components[2]] ## T[3])

  # Cross-product rotations: `a × b = a.yzx * b.zxy - a.zxy * b.yzx`.
  -> yzx
    Vec3.new([components[1], components[2], components[0]] ## T[3])
  -> zxy
    Vec3.new([components[2], components[0], components[1]] ## T[3])

  ## 4-component — geometry namespace.

  -> xyzw
    Vec4.new(components)
  -> wxyz
    Vec4.new([components[3], components[0], components[1], components[2]] ## T[4])
  -> wzyx
    Vec4.new([components[3], components[2], components[1], components[0]] ## T[4])

  ## Broadcasts.

  -> xxxx
    Vec4.new([components[0], components[0], components[0], components[0]] ## T[4])
  -> yyyy
    Vec4.new([components[1], components[1], components[1], components[1]] ## T[4])
  -> zzzz
    Vec4.new([components[2], components[2], components[2], components[2]] ## T[4])
  -> wwww
    Vec4.new([components[3], components[3], components[3], components[3]] ## T[4])

  ## Color namespace.

  -> rg
    Vec2.new([components[0], components[1]] ## T[2])
  -> ba
    Vec2.new([components[2], components[3]] ## T[2])

  -> rgb
    Vec3.new([components[0], components[1], components[2]] ## T[3])
  -> bgr
    Vec3.new([components[2], components[1], components[0]] ## T[3])

  -> rgba
    Vec4.new(components)
  -> bgra
    Vec4.new([components[2], components[1], components[0], components[3]] ## T[4])
  -> argb
    Vec4.new([components[3], components[0], components[1], components[2]] ## T[4])
  -> abgr
    Vec4.new([components[3], components[2], components[1], components[0]] ## T[4])

  -> rrrr
    Vec4.new([components[0], components[0], components[0], components[0]] ## T[4])
  -> gggg
    Vec4.new([components[1], components[1], components[1], components[1]] ## T[4])
  -> bbbb
    Vec4.new([components[2], components[2], components[2], components[2]] ## T[4])
  -> aaaa
    Vec4.new([components[3], components[3], components[3], components[3]] ## T[4])

  ## Texture-coordinate namespace.

  -> st
    Vec2.new([components[0], components[1]] ## T[2])
  -> pq
    Vec2.new([components[2], components[3]] ## T[2])

  -> stp
    Vec3.new([components[0], components[1], components[2]] ## T[3])

  -> stpq
    Vec4.new(components)
  -> qpts
    Vec4.new([components[3], components[2], components[1], components[0]] ## T[4])

  -> ssss
    Vec4.new([components[0], components[0], components[0], components[0]] ## T[4])
  -> tttt
    Vec4.new([components[1], components[1], components[1], components[1]] ## T[4])
  -> pppp
    Vec4.new([components[2], components[2], components[2], components[2]] ## T[4])
  -> qqqq
    Vec4.new([components[3], components[3], components[3], components[3]] ## T[4])

  ## Hamilton namespace. h = scalar = components[3], i/j/k at [0]/[1]/[2].
  ## So `.hijk` ≠ `.xyzw` — it's the scalar-first reordering matching
  ## the textbook reading `q = h + ix + jy + kz`.

  -> ij
    Vec2.new([components[0], components[1]] ## T[2])
  -> kh
    Vec2.new([components[2], components[3]] ## T[2])

  -> ijk
    Vec3.new([components[0], components[1], components[2]] ## T[3])
  -> jki
    Vec3.new([components[1], components[2], components[0]] ## T[3])
  -> kij
    Vec3.new([components[2], components[0], components[1]] ## T[3])

  -> ijkh
    Vec4.new(components)
  -> hijk
    Vec4.new([components[3], components[0], components[1], components[2]] ## T[4])
  -> kjih
    Vec4.new([components[2], components[1], components[0], components[3]] ## T[4])

  -> iiii
    Vec4.new([components[0], components[0], components[0], components[0]] ## T[4])
  -> jjjj
    Vec4.new([components[1], components[1], components[1], components[1]] ## T[4])
  -> kkkk
    Vec4.new([components[2], components[2], components[2], components[2]] ## T[4])
  -> hhhh
    Vec4.new([components[3], components[3], components[3], components[3]] ## T[4])
