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

  ro :a, :b

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

  # self^n for n >= 0, by repeated squaring.
  -> power(n)
    raise "power needs a nonnegative integer exponent" if n < 0
    result = EisensteinInteger.one
    base = self
    e = n
    while e > 0
      result = result * base if e % 2 == 1
      base = base * base
      e = e / 2
    result

  # The point in the complex plane: 1 is (1, 0) and omega is (-1/2, sqrt(3)/2),
  # so the lattice has unit spacing and N is the squared distance from 0.
  -> plane_point
    [@a - @b / ~2.0, @b * ~0.8660254037844386]

  # Hexagonal ring index: the radius-k centered hexagon is exactly the set
  # with hex_radius <= k, and ring j > 0 holds 6j points.
  -> hex_radius
    hi = 0
    hi = @a if @a > hi
    hi = @b if @b > hi
    lo = 0
    lo = @a if @a < lo
    lo = @b if @b < lo
    hi - lo

  # Every element of norm n, in lexicographic order of (a, b). Since
  # 4N = (2a - b)^2 + 3b^2, the search box is |b| <= 2 sqrt(n/3).
  -> .of_norm(n)
    out = []
    return out if n < 0
    if n == 0
      out.push(EisensteinInteger.zero)
      return out
    bmax = 0
    bmax += 1 while 3 * (bmax + 1) * (bmax + 1) <= 4 * n
    amax = bmax + 1
    amax += 1 while (amax - bmax) * (amax - bmax) <= 4 * n
    a = 0 - amax
    while a <= amax
      b = 0 - bmax
      while b <= bmax
        out.push(EisensteinInteger.new(a, b)) if a * a - a * b + b * b == n
        b += 1
      a += 1
    out

  # [unit, root] with self = unit * root^3, or nil when self is not a unit
  # times a cube. The root's norm is the integer cube root of N(self), so the
  # search is over one norm circle. Each answer is checked by multiplication.
  # Units are tried in the order of `units`, so a true cube comes back with
  # the unit 1 (the root is then fixed up to a cube root of unity).
  -> cube_root_up_to_unit
    return [EisensteinInteger.one, EisensteinInteger.zero] if zero?
    n = norm
    c = 0
    c += 1 while (c + 1) * (c + 1) * (c + 1) <= n
    return nil if c * c * c != n
    circle = EisensteinInteger.of_norm(c)
    units = EisensteinInteger.units
    ui = 0
    while ui < units.size
      ri = 0
      while ri < circle.size
        r = circle[ri]
        if units[ui] * r * r * r == self
          return [units[ui], r]
        ri += 1
      ui += 1
    nil

  -> to_s
    return "[@a]" if @b == 0
    return "[@b]w" if @a == 0
    @b < 0 ? "[@a] - [0 - @b]w" : "[@a] + [@b]w"
