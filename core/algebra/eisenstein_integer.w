# Z[omega], the Eisenstein integers: a + b*omega with omega a primitive cube
# root of unity, omega^2 + omega + 1 = 0.
#
# This is the triangular lattice's arithmetic, and the exact counterpart of
# Z[i] for the square lattice. It is again a Euclidean domain, with norm
#
#   N(a + b*omega) = a^2 - ab + b^2
#
# multiplicative and nonnegative. The unit group has order **six** — the sixth
# roots of unity {1, -omega^2, omega, -1, omega^2, -omega} — and it is exactly
# the rotation group C6 of the triangular lattice, just as Z[i]'s four units
# are the square lattice's C4. Multiplication by -omega^2 is a sixty-degree
# rotation; conjugation is a reflection.
#
# Between them, Z[i] and Z[omega] cover every rotation a plane lattice can
# have: the crystallographic restriction allows only 2-, 3-, 4- and 6-fold
# symmetry, and the 4-fold and 6-fold cases are these two rings.
#
# Euclidean division rounds each coordinate of the exact quotient to the
# nearest integer. The resulting error e satisfies N(e) <= 3/4 < 1 (the
# maximum of a^2 - ab + b^2 over |a|, |b| <= 1/2), so remainders shrink and
# Euclid's algorithm terminates.
#
# Primes: 3 ramifies, since N(1 - omega) = 3; rational primes p = 1 mod 3
# split; rational primes p = 2 mod 3 stay inert. So an element is prime when
# its norm is a rational prime, or when its norm is p^2 for an inert p.

+ EisensteinInteger
  -> .integer?(value)
    name = value.class_name
    name == "Integer" || name == "Int" || name == "BigInt"

  -> new(a, b)
    if !EisensteinInteger.integer?(a) || !EisensteinInteger.integer?(b)
      raise "an Eisenstein integer needs integer coordinates"
    @a = a
    @b = b

  -> .zero
    EisensteinInteger.new(0, 0)

  -> .one
    EisensteinInteger.new(1, 0)

  -> .omega
    EisensteinInteger.new(0, 1)

  # The six units, in rotation order starting at 1. Multiplying by the second
  # entry turns the lattice sixty degrees.
  -> .units
    [EisensteinInteger.new(1, 0), EisensteinInteger.new(1, 1),
     EisensteinInteger.new(0, 1), EisensteinInteger.new(0 - 1, 0),
     EisensteinInteger.new(0 - 1, 0 - 1), EisensteinInteger.new(0, 0 - 1)]

  -> a
    @a

  -> b
    @b

  -> zero?
    @a == 0 && @b == 0

  # conj(a + b*omega) = (a - b) - b*omega, because conj(omega) = omega^2 = -1 - omega.
  -> conjugate
    EisensteinInteger.new(@a - @b, 0 - @b)

  -> norm
    @a * @a - @a * @b + @b * @b

  -> negate
    EisensteinInteger.new(0 - @a, 0 - @b)

  -> +(other)
    EisensteinInteger.new(@a + other.a, @b + other.b)

  -> -(other)
    EisensteinInteger.new(@a - other.a, @b - other.b)

  # (a + b w)(c + d w) = (ac - bd) + (ad + bc - bd) w, using w^2 = -1 - w.
  -> *(other)
    EisensteinInteger.new(@a * other.a - @b * other.b,
                          @a * other.b + @b * other.a - @b * other.b)

  -> ==(other)
    return false if other.class_name != "EisensteinInteger"
    @a == other.a && @b == other.b

  -> unit?
    norm == 1

  # Sixty degrees counter-clockwise: multiplication by -omega^2 = 1 + omega.
  -> rotated_60(times)
    turns = times % 6
    turns += 6 if turns < 0
    step = EisensteinInteger.new(1, 1)
    out = self
    i = 0
    while i < turns
      out = out * step
      i += 1
    out

  # The twelve images under D6: six rotations, then the mirrored six.
  -> d6_image(index)
    slot = index % 12
    slot += 12 if slot < 0
    base = slot < 6 ? self : conjugate
    base.rotated_60(slot % 6)

  -> .floor_div(x, y)
    q = x / y
    q -= 1 if q * y > x
    q

  -> .round_div(x, y)
    EisensteinInteger.floor_div(2 * x + y, 2 * y)

  -> divmod(other)
    raise "division by zero in Z\[omega]" if other.zero?
    scaled = self * other.conjugate
    denominator = other.norm
    quotient = EisensteinInteger.new(
      EisensteinInteger.round_div(scaled.a, denominator),
      EisensteinInteger.round_div(scaled.b, denominator))
    [quotient, self - quotient * other]

  -> /(other)
    divmod(other)[0]

  -> %(other)
    divmod(other)[1]

  -> divides?(other)
    return other.zero? if zero?
    other.divmod(self)[1].zero?

  -> gcd(other)
    x = self
    y = other
    while !y.zero?
      r = x.divmod(y)[1]
      x = y
      y = r
    x

  -> associates
    out = []
    EisensteinInteger.units.each ->(u)
      out.push(u * self)
    out

  -> prime?
    n = norm
    return false if n <= 1
    return true if n.prime?
    # An inert rational prime p = 2 mod 3 has norm p^2.
    root = 0
    while root * root < n
      root += 1
    return false if root * root != n
    root.prime? && root % 3 == 2

  -> to_s
    return "[@a]" if @b == 0
    return "[@b]w" if @a == 0
    @b < 0 ? "[@a] - [0 - @b]w" : "[@a] + [@b]w"
