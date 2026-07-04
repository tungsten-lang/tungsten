# Vector — generic real-valued N-dimensional vectors. Distinct from
# Hypercomplex (which carries algebra structure like Cayley–Dickson
# multiplication and conjugation); a Vector is just a tuple of T values
# with componentwise arithmetic and L2 geometry.
#
# Concrete subclasses (in core/numeric/): Vec2<T>, Vec3<T>, Vec4<T>.
# Literal syntax (parser hook pending):
#   %v2-f32[3.2 5.5]
#   %v3-f32[0.93 0.56 1.23]
#   %v4-f32[0.44 0.65 0.24 0.88]
+ Vector<T> < Number
  with T in (
    f16 f32 f64 f80 f128 f256
    bf16 tf32 fp8 fp4 nf4
    mxfp8 mxfp6 mxfp4
    posit8 posit16 posit32 posit64
    i8 i16 i32 i64 i128
    u8 u16 u32 u64 u128
  )

  is Comparable

  # Magnitude

  # Squared L2 length: Σ cᵢ². Exact for integer T.
  -> length_squared
    components/sq:sum

  # L2 length: √(Σ cᵢ²).
  -> length
    components.pythagorean

  -> magnitude
    length

  # `abs` and `abs2` as the Number contract: vectors interpret these as
  # magnitude and squared-magnitude.
  -> abs
    length

  -> abs2
    length_squared

  # Comparison — vectors are ordered by magnitude.

  -> <=>/1
    length_squared <=> @1.length_squared

  # Exact componentwise equality (overrides Comparable's magnitude `==`).
  -> ==/1
    @1.dimension == dimension && components == @1.components

  -> !=/1
    !(self == @1)

  # Arithmetic — componentwise.

  -> negate
    class.new(components.map -> -item)

  -> -@
    negate

  -> +/1
    class.new(components.zip(@1.components).map -> item[0] + item[1])

  -> -/1
    class.new(components.zip(@1.components).map -> item[0] - item[1])

  # Multiplication is type-dispatched at the call site:
  #
  #   v * other  where other is a Vector → Hadamard (componentwise)
  #   v * other  where other is a scalar Number → componentwise scale
  #
  # The `(Vector)` / `(Number)` param-type lists pick the right body via
  # the same typed-overload mechanism Tungsten uses for method dispatch
  # elsewhere. The `⊙` (Hadamard) operator is also available explicitly
  # when you want to be unambiguous regardless of receiver typing.

  # Hadamard (componentwise) product — same convention as GLSL/MSL.
  -> */1(Vector)
    class.new(components.zip(@1.components).map -> item[0] * item[1])

  # Scalar multiplication.
  -> */1(Number)
    scalar = @1
    class.new(components.map -> item * scalar)

  # Explicit Hadamard alias — `v1 ⊙ v2` lowers to this method.
  -> ⊙/1
    class.new(components.zip(@1.components).map -> item[0] * item[1])

  # Latin alias for callers who prefer ASCII.
  -> hadamard/1
    self ⊙ @1

  # Hadamard division — type-dispatched parallel of `*`.
  -> //1(Vector)
    class.new(components.zip(@1.components).map -> item[0] / item[1])

  -> //1(Number)
    scalar = @1
    class.new(components.map -> item / scalar)

  # Geometry

  # Inner product: Σ aᵢ·bᵢ.
  -> dot/1 0
    components.each_with_index -> acc += item * @1.components[i]

  # Direction with magnitude 1.
  -> normalize
    self / length

  # Linear interpolation: self + (other - self) * t.
  -> lerp/2
    self + (@1 - self) * @2

  # Reflection across a unit normal: v − 2 (v·n) n.
  -> reflect/1
    self - @1 * (2 * dot(@1))

  # Project self onto another vector: ((self·other) / (other·other)) · other.
  -> project_onto/1
    @1 * (dot(@1) / @1.length_squared)

  # Outer (tensor) product: `u ⊗ v` produces an M×N matrix where
  # M = u.dimension, N = v.dimension and result[i, j] = u[i] · v[j].
  # Column-major store: column j holds u · v[j].
  -> ⊗/1
    a = components
    b = @1.components
    m = dimension
    n = @1.dimension
    elems = (0...(m * n)).map ->
      c = i / m
      r = i % m
      a[r] * b[c]
    Mat<T, m, n>.new(elems ## T[m * n])

  # Latin alias for the outer product.
  -> outer/1
    self ⊗ @1

  # Predicates

  -> zero?
    length_squared == 0

  -> unit?
    length_squared == 1

  # True when self and @1 are collinear (parallel or anti-parallel).
  # Dimension-agnostic Cauchy–Schwarz equality: (a·b)² == |a|²·|b|², which
  # holds exactly when the vectors are linearly dependent. Avoids `cross`,
  # which only exists for Vec3.
  -> parallel?/1
    d = dot(@1)
    d * d == length_squared * @1.length_squared

  # Parts

  -> dimension
    components.size

  # Iteration

  -> each_component/&
    components.each -> &(item)

  # Generic SIMD gather: `v.shuffle([2, 0, 1])` returns the components
  # at those indices as a `T[N]` array. Concrete subclasses supply
  # named fast-path swizzles (`.xy`, `.xyz`, broadcasts) for common
  # patterns; this is the generic fallback for arbitrary permutations.
  -> shuffle/1
    components.shuffle(@1)

  # Conversion

  -> to_s

  -> hash
