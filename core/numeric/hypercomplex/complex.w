# Complex — dimension-2 hypercomplex (basis: 1, i).
# z = a + bi stored as components [a, b]. Scalar-first.
+ Complex<T> < Hypercomplex<T>
  - data
    T components[2]

  -> new(@components ## T[2])

  -> .dimension
    2

  -> .scalar_index
    0

  -> .zero
    class.new((0...2).map -> 0)

  -> .one
    class.new((0...2).map -> item == 0 ? 1 : 0)

  -> .basis(n)
    raise ArgumentError, "basis index out of range: [n]" if n < 0 || n >= 2
    class.new((0...2).map -> item == n ? 1 : 0)

  -> .real(value)
    class.new([value, 0] ## T[2])

  -> .pure(values)
    class.new([0, values[0]] ## T[2])

  # Cayley–Dickson half: Complex doubles R (the reals) to produce
  # itself; there's no lower Hypercomplex level. Returns nil to mark
  # this as the floor of the tower.
  -> half_class
    nil

  # Imaginary *coefficient* (the b in a + bi). The pure-imaginary
  # *value* is inherited from Hypercomplex as `.imaginary`.
  -> imag
    components[1]

  # Argument: the signed angle on the Argand plane, atan2(b, a) ∈ (−π, π].
  # Overrides Hypercomplex's unsigned generalization so a point below the
  # real axis (negative b) reports a negative phase — the polar companion
  # to `abs` for the Argand plot.
  -> arg
    Math.atan2(imag, real)

  ## Cayley–Dickson basis aliases.

  -> e0
    components[0]
  -> e1
    components[1]

  ## Cayley–Dickson product. (a + bi)·(c + di) = (ac − bd) + (ad + bc)i.
  -> */1
    return scale(@1) if scalar_like?(@1)
    a = components[0]
    b = components[1]
    c = @1.components[0]
    d = @1.components[1]
    class.new([a * c - b * d, a * d + b * c] ## T[2])

  ## Optimized squaring: (a + bi)² = (a² − b²) + 2abi.
  ## 4 mults vs general */1's 6 — 33% fewer ops.
  -> sq
    class.new([real * real - imag * imag, 2 * real * imag] ## T[2])
