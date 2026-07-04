# Sexagintaquatronion — dimension-64 hypercomplex algebra. Cayley–Dickson
# doubling of Trigintaduonion. Name follows Latin `sexagintaquatro` = 64.
+ Sexagintaquatronion<T> < Hypercomplex<T>
  noncommutative :*
  noassoc       :*

  - data
    T components[64]

  -> new(@components ## T[64])

  -> .dimension
    64

  -> .scalar_index
    0

  -> .zero
    class.new((0...64).map -> 0)

  -> .one
    class.new((0...64).map -> item == 0 ? 1 : 0)

  -> .basis(n)
    raise ArgumentError, "basis index out of range: [n]" if n < 0 || n >= 64
    class.new((0...64).map -> item == n ? 1 : 0)

  -> .real(value)
    class.new((0...64).map -> item == 0 ? value : 0)

  -> .pure(values)
    vi = 0
    out = (0...64).map ->
      if item == 0
        0
      else
        value = values[vi]
        vi += 1
        value
    class.new(out)

  # Cayley–Dickson half: doubling Trigintaduonion produces Sexagintaquatronion.
  -> half_class
    Trigintaduonion

  ## Cayley–Dickson product via Trigintaduonion-pair structure.
  -> */1
    return scale(@1) if scalar_like?(@1)
    a0 = half_class.new(components.slice(0, 32) ## T[32])
    a1 = half_class.new(components.slice(32, 32) ## T[32])
    b0 = half_class.new(@1.components.slice(0, 32) ## T[32])
    b1 = half_class.new(@1.components.slice(32, 32) ## T[32])

    low  = a0 * b0 - b1.conjugate * a1
    high = b1 * a0 + a1 * b0.conjugate

    class.new(low.components.concat(high.components) ## T[64])

  ## Optimized squaring via Cayley–Dickson, recursive through Trigintaduonion#sq.
  -> sq
    a_sq = half_class.new(components.slice(0, 32) ## T[32]).sq
    b    = half_class.new(components.slice(32, 32) ## T[32])
    bn2  = b.abs2
    s2a  = 2 * components[0]
    low  = a_sq.components.map_with_index -> (item, i) i == 0 ? item - bn2 : item
    high = b.components.map -> item * s2a
    class.new(low.concat(high) ## T[64])
