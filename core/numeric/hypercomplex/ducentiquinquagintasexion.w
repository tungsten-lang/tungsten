# Ducentiquinquagintasexion — dimension-256 hypercomplex algebra.
# Cayley–Dickson doubling of Centumduodetrigintanion. Name follows
# Latin `ducenti-quinquaginta-sex` = 200 + 50 + 6 = 256.
#
# Literal (scalar-first; no Metal-native type above dimension 16):
#   %h256-f32[e0 e1 … e255]  → Ducentiquinquagintasexion<f32>
+ Ducentiquinquagintasexion<T> < Hypercomplex<T>
  noncommutative :*
  noassoc       :*

  - data
    T components[256]

  -> new(@components ## T[256])

  -> .dimension
    256

  -> .scalar_index
    0

  -> .zero
    class.new((0...256).map -> 0)

  -> .one
    class.new((0...256).map -> item == 0 ? 1 : 0)

  -> .basis(n)
    raise ArgumentError, "basis index out of range: [n]" if n < 0 || n >= 256
    class.new((0...256).map -> item == n ? 1 : 0)

  -> .real(value)
    class.new((0...256).map -> item == 0 ? value : 0)

  -> .pure(values)
    vi = 0
    out = (0...256).map ->
      if item == 0
        0
      else
        value = values[vi]
        vi += 1
        value
    class.new(out)

  # Cayley–Dickson half: doubling Centumduodetrigintanion produces Ducentiquinquagintasexion.
  -> half_class
    Centumduodetrigintanion

  ## Cayley–Dickson product via Centumduodetrigintanion-pair structure.
  -> */1
    return scale(@1) if scalar_like?(@1)
    a0 = half_class.new(components.slice(0, 128) ## T[128])
    a1 = half_class.new(components.slice(128, 128) ## T[128])
    b0 = half_class.new(@1.components.slice(0, 128) ## T[128])
    b1 = half_class.new(@1.components.slice(128, 128) ## T[128])

    low  = a0 * b0 - b1.conjugate * a1
    high = b1 * a0 + a1 * b0.conjugate

    class.new(low.components.concat(high.components) ## T[256])

  ## Optimized squaring via Cayley–Dickson, recursive through Centumduodetrigintanion#sq.
  -> sq
    a_sq = half_class.new(components.slice(0, 128) ## T[128]).sq
    b    = half_class.new(components.slice(128, 128) ## T[128])
    bn2  = b.abs2
    s2a  = 2 * components[0]
    low  = a_sq.components.map_with_index -> (item, i) i == 0 ? item - bn2 : item
    high = b.components.map -> item * s2a
    class.new(low.concat(high) ## T[256])
