# Octonion — dimension-8 hypercomplex algebra (basis: 1, e1…e7).
# Multiplication is non-commutative and non-associative. The last of
# the four normed division algebras: |a·b| = |a|·|b| holds, but the
# associator (a·b)·c − a·(b·c) is generally non-zero.
+ Octonion<T> < Hypercomplex<T>
  noncommutative :*
  noassoc        :*

  - data
    T components[8]

  -> new(@components ## T[8])

  -> .dimension
    8

  -> .scalar_index
    0

  -> .zero
    class.new((0...8).map -> 0)

  -> .one
    class.new((0...8).map -> item == 0 ? 1 : 0)

  -> .basis(n)
    raise ArgumentError, "basis index out of range: [n]" if n < 0 || n >= 8
    class.new((0...8).map -> item == n ? 1 : 0)

  -> .real(value)
    class.new((0...8).map -> item == 0 ? value : 0)

  -> .pure(values)
    vi = 0
    out = (0...8).map ->
      if item == 0
        0
      else
        value = values[vi]
        vi += 1
        value
    class.new(out)

  # Cayley–Dickson half: doubling Quaternion produces Octonion.
  -> half_class
    Quaternion

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

  ## Cayley–Dickson product via quaternion-pair structure. Octonion as
  ## (q_low, q_high) where each Quaternion holds 4 contiguous scalar-
  ## first components. Octonion and (math) Quaternion both store
  ## scalar-first, so the recursive formula composes directly:
  ##   (a, b) · (c, d) = (a·c − conj(d)·b, d·a + b·conj(c))
  ##
  ## (Use Quaternion<T> here, not QuaternionMetal<T> — the latter's
  ## scalar-LAST storage would mis-align the recursion.)
  -> */1
    return scale(@1) if scalar_like?(@1)
    a0 = half_class.new(components.slice(0, 4) ## T[4])
    a1 = half_class.new(components.slice(4, 4) ## T[4])
    b0 = half_class.new(@1.components.slice(0, 4) ## T[4])
    b1 = half_class.new(@1.components.slice(4, 4) ## T[4])

    low  = a0 * b0 - b1.conjugate * a1
    high = b1 * a0 + a1 * b0.conjugate

    class.new(low.components.concat(high.components) ## T[8])

  ## Direct coefficient product using the same Cayley-Dickson orientation as */1.
  ## Kept separate for benchmarking; */1 still uses the recursive quaternion-pair path.
  -> mul_direct/1
    return scale(@1) if scalar_like?(@1)
    a0 = components[0]
    a1 = components[1]
    a2 = components[2]
    a3 = components[3]
    a4 = components[4]
    a5 = components[5]
    a6 = components[6]
    a7 = components[7]
    b0 = @1.components[0]
    b1 = @1.components[1]
    b2 = @1.components[2]
    b3 = @1.components[3]
    b4 = @1.components[4]
    b5 = @1.components[5]
    b6 = @1.components[6]
    b7 = @1.components[7]
    class.new([
      a0 * b0 - a1 * b1 - a2 * b2 - a3 * b3 - a4 * b4 - a5 * b5 - a6 * b6 - a7 * b7,
      a0 * b1 + a1 * b0 + a2 * b3 - a3 * b2 + a4 * b5 - a5 * b4 - a6 * b7 + a7 * b6,
      a0 * b2 - a1 * b3 + a2 * b0 + a3 * b1 + a4 * b6 + a5 * b7 - a6 * b4 - a7 * b5,
      a0 * b3 + a1 * b2 - a2 * b1 + a3 * b0 + a4 * b7 - a5 * b6 + a6 * b5 - a7 * b4,
      a0 * b4 - a1 * b5 - a2 * b6 - a3 * b7 + a4 * b0 + a5 * b1 + a6 * b2 + a7 * b3,
      a0 * b5 + a1 * b4 - a2 * b7 + a3 * b6 - a4 * b1 + a5 * b0 - a6 * b3 + a7 * b2,
      a0 * b6 + a1 * b7 + a2 * b4 - a3 * b5 - a4 * b2 + a5 * b3 + a6 * b0 - a7 * b1,
      a0 * b7 - a1 * b6 + a2 * b5 + a3 * b4 - a4 * b3 - a5 * b2 + a6 * b1 + a7 * b0
    ] ## T[8])

  ## Optimized squaring via Cayley–Dickson: (a, b)² = (a² − |b|², 2·Re(a)·b).
  ## Recursively uses Quaternion#sq for a² — savings compound through the
  ## tower. ~16 mults vs general */1's ~64 (75% reduction).
  -> sq
    a_sq = half_class.new(components.slice(0, 4) ## T[4]).sq
    b    = half_class.new(components.slice(4, 4) ## T[4])
    bn2  = b.abs2
    s2a  = 2 * components[0]
    low  = a_sq.components.map_with_index -> (item, i) i == 0 ? item - bn2 : item
    high = b.components.map -> item * s2a
    class.new(low.concat(high) ## T[8])
