# Sedenion — dimension-16 hypercomplex algebra (basis: 1, e1…e15).
# Non-commutative, non-associative, and the first Cayley–Dickson level
# with zero divisors and where the multiplicative-norm property
# |a·b| = |a|·|b| no longer holds.
#
# Literals (scalar-first, [e0 e1 … e15]):
#   %h16-f32[e0 e1 … e15]       → Sedenion<f32>  (math)
#   %h16-float4x4[e0 e1 … e15]  → Sedenion<f32>  (Metal-aligned; byte-aliases
#     float4x4, same scalar-first order — no separate metal class)
+ Sedenion<T> < Hypercomplex<T>
  noncommutative :*
  noassoc       :*

  - data
    T components[16]

  -> new(@components ## T[16])

  -> .dimension
    16

  -> .scalar_index
    0

  -> .zero
    class.new((0...16).map -> 0)

  -> .one
    class.new((0...16).map -> item == 0 ? 1 : 0)

  -> .basis(n)
    raise ArgumentError, "basis index out of range: [n]" if n < 0 || n >= 16
    class.new((0...16).map -> item == n ? 1 : 0)

  -> .real(value)
    class.new((0...16).map -> item == 0 ? value : 0)

  -> .pure(values)
    vi = 0
    out = (0...16).map ->
      if item == 0
        0
      else
        value = values[vi]
        vi += 1
        value
    class.new(out)

  # Cayley–Dickson half: doubling Octonion produces Sedenion.
  -> half_class
    Octonion

  -> e0
    components[0]
  -> e1
    components[1]
  -> e2
    components[2]
  -> e3
    components[3]
  -> e4
    components[4]
  -> e5
    components[5]
  -> e6
    components[6]
  -> e7
    components[7]
  -> e8
    components[8]
  -> e9
    components[9]
  -> e10
    components[10]
  -> e11
    components[11]
  -> e12
    components[12]
  -> e13
    components[13]
  -> e14
    components[14]
  -> e15
    components[15]

  ## Reference Cayley–Dickson product via octonion-pair structure
  ## (scalar-first).
  ## Sedenion as (o_low, o_high) where each octonion is 8 contiguous
  ## components: components[0..7] and components[8..15]. Formula:
  ## (a, b) · (c, d) = (a·c − conj(d)·b, d·a + b·conj(c)).
  ##
  ## Sedenion's halves are scalar-first and so is Octonion — we can
  ## construct Octonion instances and reuse their arithmetic directly.
  -> mul_recursive/1
    return scale(@1) if scalar_like?(@1)
    a0 = half_class.new(components.slice(0, 8) ## T[8])
    a1 = half_class.new(components.slice(8, 8) ## T[8])
    b0 = half_class.new(@1.components.slice(0, 8) ## T[8])
    b1 = half_class.new(@1.components.slice(8, 8) ## T[8])

    low  = a0.mul_recursive(b0) - b1.conjugate.mul_recursive(a1)
    high = b1.mul_recursive(a0) + a1.mul_recursive(b0.conjugate)

    class.new(low.components.concat(high.components) ## T[16])

  ## The direct coefficient product avoids recursive half construction and
  ## all intermediate hypercomplex values. Keep mul_recursive/1 as a compact
  ## reference implementation for equivalence testing.
  -> */1
    mul_fast(@1)

  ## Direct coefficient product used by the public multiplication operator.
  -> mul_fast/1
    return scale(@1) if scalar_like?(@1)
    a = components
    b = @1.components
    class.new([
      a[0] * b[0] - a[1] * b[1] - a[2] * b[2] - a[3] * b[3] - a[4] * b[4] - a[5] * b[5] - a[6] * b[6] - a[7] * b[7] - a[8] * b[8] - a[9] * b[9] - a[10] * b[10] - a[11] * b[11] - a[12] * b[12] - a[13] * b[13] - a[14] * b[14] - a[15] * b[15],
      a[0] * b[1] + a[1] * b[0] + a[2] * b[3] - a[3] * b[2] + a[4] * b[5] - a[5] * b[4] - a[6] * b[7] + a[7] * b[6] + a[8] * b[9] - a[9] * b[8] - a[10] * b[11] + a[11] * b[10] - a[12] * b[13] + a[13] * b[12] + a[14] * b[15] - a[15] * b[14],
      a[0] * b[2] - a[1] * b[3] + a[2] * b[0] + a[3] * b[1] + a[4] * b[6] + a[5] * b[7] - a[6] * b[4] - a[7] * b[5] + a[8] * b[10] + a[9] * b[11] - a[10] * b[8] - a[11] * b[9] - a[12] * b[14] - a[13] * b[15] + a[14] * b[12] + a[15] * b[13],
      a[0] * b[3] + a[1] * b[2] - a[2] * b[1] + a[3] * b[0] + a[4] * b[7] - a[5] * b[6] + a[6] * b[5] - a[7] * b[4] + a[8] * b[11] - a[9] * b[10] + a[10] * b[9] - a[11] * b[8] - a[12] * b[15] + a[13] * b[14] - a[14] * b[13] + a[15] * b[12],
      a[0] * b[4] - a[1] * b[5] - a[2] * b[6] - a[3] * b[7] + a[4] * b[0] + a[5] * b[1] + a[6] * b[2] + a[7] * b[3] + a[8] * b[12] + a[9] * b[13] + a[10] * b[14] + a[11] * b[15] - a[12] * b[8] - a[13] * b[9] - a[14] * b[10] - a[15] * b[11],
      a[0] * b[5] + a[1] * b[4] - a[2] * b[7] + a[3] * b[6] - a[4] * b[1] + a[5] * b[0] - a[6] * b[3] + a[7] * b[2] + a[8] * b[13] - a[9] * b[12] + a[10] * b[15] - a[11] * b[14] + a[12] * b[9] - a[13] * b[8] + a[14] * b[11] - a[15] * b[10],
      a[0] * b[6] + a[1] * b[7] + a[2] * b[4] - a[3] * b[5] - a[4] * b[2] + a[5] * b[3] + a[6] * b[0] - a[7] * b[1] + a[8] * b[14] - a[9] * b[15] - a[10] * b[12] + a[11] * b[13] + a[12] * b[10] - a[13] * b[11] - a[14] * b[8] + a[15] * b[9],
      a[0] * b[7] - a[1] * b[6] + a[2] * b[5] + a[3] * b[4] - a[4] * b[3] - a[5] * b[2] + a[6] * b[1] + a[7] * b[0] + a[8] * b[15] + a[9] * b[14] - a[10] * b[13] - a[11] * b[12] + a[12] * b[11] + a[13] * b[10] - a[14] * b[9] - a[15] * b[8],
      a[0] * b[8] - a[1] * b[9] - a[2] * b[10] - a[3] * b[11] - a[4] * b[12] - a[5] * b[13] - a[6] * b[14] - a[7] * b[15] + a[8] * b[0] + a[9] * b[1] + a[10] * b[2] + a[11] * b[3] + a[12] * b[4] + a[13] * b[5] + a[14] * b[6] + a[15] * b[7],
      a[0] * b[9] + a[1] * b[8] - a[2] * b[11] + a[3] * b[10] - a[4] * b[13] + a[5] * b[12] + a[6] * b[15] - a[7] * b[14] - a[8] * b[1] + a[9] * b[0] - a[10] * b[3] + a[11] * b[2] - a[12] * b[5] + a[13] * b[4] + a[14] * b[7] - a[15] * b[6],
      a[0] * b[10] + a[1] * b[11] + a[2] * b[8] - a[3] * b[9] - a[4] * b[14] - a[5] * b[15] + a[6] * b[12] + a[7] * b[13] - a[8] * b[2] + a[9] * b[3] + a[10] * b[0] - a[11] * b[1] - a[12] * b[6] - a[13] * b[7] + a[14] * b[4] + a[15] * b[5],
      a[0] * b[11] - a[1] * b[10] + a[2] * b[9] + a[3] * b[8] - a[4] * b[15] + a[5] * b[14] - a[6] * b[13] + a[7] * b[12] - a[8] * b[3] - a[9] * b[2] + a[10] * b[1] + a[11] * b[0] - a[12] * b[7] + a[13] * b[6] - a[14] * b[5] + a[15] * b[4],
      a[0] * b[12] + a[1] * b[13] + a[2] * b[14] + a[3] * b[15] + a[4] * b[8] - a[5] * b[9] - a[6] * b[10] - a[7] * b[11] - a[8] * b[4] + a[9] * b[5] + a[10] * b[6] + a[11] * b[7] + a[12] * b[0] - a[13] * b[1] - a[14] * b[2] - a[15] * b[3],
      a[0] * b[13] - a[1] * b[12] + a[2] * b[15] - a[3] * b[14] + a[4] * b[9] + a[5] * b[8] + a[6] * b[11] - a[7] * b[10] - a[8] * b[5] - a[9] * b[4] + a[10] * b[7] - a[11] * b[6] + a[12] * b[1] + a[13] * b[0] + a[14] * b[3] - a[15] * b[2],
      a[0] * b[14] - a[1] * b[15] - a[2] * b[12] + a[3] * b[13] + a[4] * b[10] - a[5] * b[11] + a[6] * b[8] + a[7] * b[9] - a[8] * b[6] - a[9] * b[7] - a[10] * b[4] + a[11] * b[5] + a[12] * b[2] - a[13] * b[3] + a[14] * b[0] + a[15] * b[1],
      a[0] * b[15] + a[1] * b[14] - a[2] * b[13] - a[3] * b[12] + a[4] * b[11] + a[5] * b[10] - a[6] * b[9] + a[7] * b[8] - a[8] * b[7] + a[9] * b[6] - a[10] * b[5] - a[11] * b[4] + a[12] * b[3] + a[13] * b[2] - a[14] * b[1] + a[15] * b[0]
    ] ## T[16])
  ## Optimized squaring via Cayley–Dickson, recursive through Octonion#sq.
  ## Same shape — `a² − |b|²` in the low half, `2·Re(a)·b` in the high
  ## half. ~50% reduction over general */1.
  -> sq
    a_sq = half_class.new(components.slice(0, 8) ## T[8]).sq
    b    = half_class.new(components.slice(8, 8) ## T[8])
    bn2  = b.abs2
    s2a  = 2 * components[0]
    low  = a_sq.components.map_with_index -> (item, i) i == 0 ? item - bn2 : item
    high = b.components.map -> item * s2a
    class.new(low.concat(high) ## T[16])

  ## `alternative?`, `is_zero_divisor_pair?`, and the Moufang / Jordan /
  ## flexibility predicates all live on Hypercomplex<T> now — universal
  ## tests that return false starting at Sedenion (where they fail) and
  ## true through Complex/Quaternion/Octonion (where they hold).
