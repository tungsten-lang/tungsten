# Centumduodetrigintanion — dimension-128 hypercomplex algebra.
# Cayley–Dickson doubling of Sexagintaquatronion. Name follows Latin
# `centum-duo-de-triginta` = 100 + (30 − 2) = 128.
#
# Literal (scalar-first; no Metal-native type above dimension 16):
#   %h128-f32[e0 e1 … e127]  → Centumduodetrigintanion<f32>
+ Centumduodetrigintanion<T> < Hypercomplex<T>
  noncommutative :*
  noassoc       :*

  - data
    T components[128]

  -> new(@components ## T[128])

  -> .dimension
    128

  -> .scalar_index
    0

  -> .zero
    class.new((0...128).map -> 0)

  -> .one
    class.new((0...128).map -> item == 0 ? 1 : 0)

  -> .basis(n)
    raise ArgumentError, "basis index out of range: [n]" if n < 0 || n >= 128
    class.new((0...128).map -> item == n ? 1 : 0)

  -> .real(value)
    class.new((0...128).map -> item == 0 ? value : 0)

  -> .pure(values)
    vi = 0
    out = (0...128).map ->
      if item == 0
        0
      else
        value = values[vi]
        vi += 1
        value
    class.new(out)

  # Cayley–Dickson half: doubling Sexagintaquatronion produces Centumduodetrigintanion.
  -> half_class
    Sexagintaquatronion

  ## Cayley–Dickson product via Sexagintaquatronion-pair structure.
  -> */1
    return scale(@1) if scalar_like?(@1)
    a0 = half_class.new(components.slice(0, 64) ## T[64])
    a1 = half_class.new(components.slice(64, 64) ## T[64])
    b0 = half_class.new(@1.components.slice(0, 64) ## T[64])
    b1 = half_class.new(@1.components.slice(64, 64) ## T[64])

    low  = a0 * b0 - b1.conjugate * a1
    high = b1 * a0 + a1 * b0.conjugate

    class.new(low.components.concat(high.components) ## T[128])

  ## Optimized squaring via Cayley–Dickson, recursive through Sexagintaquatronion#sq.
  -> sq
    a_sq = half_class.new(components.slice(0, 64) ## T[64]).sq
    b    = half_class.new(components.slice(64, 64) ## T[64])
    bn2  = b.abs2
    s2a  = 2 * components[0]
    low  = a_sq.components.map_with_index -> (item, i) i == 0 ? item - bn2 : item
    high = b.components.map -> item * s2a
    class.new(low.concat(high) ## T[128])
