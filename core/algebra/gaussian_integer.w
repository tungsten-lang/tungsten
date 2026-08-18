# Z[i], the Gaussian integers: complex numbers a + bi with a, b in Z.
#
# Z[i] is a Euclidean domain. The norm N(a + bi) = a^2 + b^2 is multiplicative
# and takes nonnegative integer values, and for any z and nonzero w there are
# q, r with z = qw + r and N(r) < N(w) — found by rounding the exact rational
# quotient z * conj(w) / N(w) to the nearest lattice point. Euclid's algorithm
# therefore works verbatim, which is what `gcd` uses.
#
# The unit group is {1, i, -1, -i}: the four fourth-roots of unity, and
# exactly the rotation group C4 of the square lattice. Multiplication by i is
# a quarter turn counter-clockwise, and complex conjugation is reflection in
# the real axis, so the eight symmetries of the square lattice — the dihedral
# group D4 — are precisely
#
#     z -> u * z        and        z -> u * conj(z),      u a unit.
#
# That is why lattice geometry wants Z[i] rather than a rotation formalism
# built for three dimensions: the arithmetic here is exact and integral, and
# a lattice point never leaves the lattice.
#
# Primes: up to units, a Gaussian integer is prime exactly when its norm is a
# rational prime (this covers 1 + i, of norm 2, and the splitting primes
# p = 1 mod 4), or when it is a rational prime p = 3 mod 4 times a unit —
# those stay inert.

+ GaussianInteger
  -> .integer?(value)
    name = value.class_name
    name == "Integer" || name == "Int" || name == "BigInt"

  -> new(re, im)
    if !GaussianInteger.integer?(re) || !GaussianInteger.integer?(im)
      raise "a Gaussian integer needs integer real and imaginary parts"
    @re = re
    @im = im

  -> .of(re, im)
    GaussianInteger.new(re, im)

  -> .zero
    GaussianInteger.new(0, 0)

  -> .one
    GaussianInteger.new(1, 0)

  -> .i
    GaussianInteger.new(0, 1)

  # The four units, in rotation order 1, i, -1, -i.
  -> .units
    [GaussianInteger.new(1, 0), GaussianInteger.new(0, 1),
     GaussianInteger.new(0 - 1, 0), GaussianInteger.new(0, 0 - 1)]

  -> re
    @re

  -> im
    @im

  -> zero?
    @re == 0 && @im == 0

  -> conjugate
    GaussianInteger.new(@re, 0 - @im)

  -> norm
    @re * @re + @im * @im

  -> negate
    GaussianInteger.new(0 - @re, 0 - @im)

  -> +(other)
    GaussianInteger.new(@re + other.re, @im + other.im)

  -> -(other)
    GaussianInteger.new(@re - other.re, @im - other.im)

  -> *(other)
    GaussianInteger.new(@re * other.re - @im * other.im,
                        @re * other.im + @im * other.re)

  -> ==(other)
    return false if other.class_name != "GaussianInteger"
    @re == other.re && @im == other.im

  -> unit?
    norm == 1

  # Multiplication by i — a quarter turn counter-clockwise about the origin.
  -> times_i
    GaussianInteger.new(0 - @im, @re)

  -> rotated_ccw(times)
    turns = times % 4
    turns += 4 if turns < 0
    out = self
    i = 0
    while i < turns
      out = out.times_i
      i += 1
    out

  # The lattice-packing convention counts quarter turns clockwise, which is
  # multiplication by -i.
  -> rotated_cw(times)
    rotated_ccw(0 - times)

  # The eight images of a lattice point under D4, indexed 0..7: rotations
  # first, then the mirrored rotations.
  -> d4_image(index)
    slot = index % 8
    slot += 8 if slot < 0
    base = slot < 4 ? self : conjugate
    base.rotated_ccw(slot % 4)

  # Exact floor division by a positive divisor. Tungsten's integer division
  # truncates toward zero, so a negative dividend needs one correction step.
  -> .floor_div(a, b)
    q = a / b
    q -= 1 if q * b > a
    q

  # Nearest integer to n / d for positive d: floor((2n + d) / 2d).
  -> .round_div(n, d)
    GaussianInteger.floor_div(2 * n + d, 2 * d)

  # Euclidean division: returns [quotient, remainder] with N(remainder) less
  # than N(other).
  -> divmod(other)
    raise "division by zero in Z[i]" if other.zero?
    scaled = self * other.conjugate
    denominator = other.norm
    quotient = GaussianInteger.new(
      GaussianInteger.round_div(scaled.re, denominator),
      GaussianInteger.round_div(scaled.im, denominator))
    [quotient, self - quotient * other]

  -> /(other)
    divmod(other)[0]

  -> %(other)
    divmod(other)[1]

  -> divides?(other)
    return other.zero? if zero?
    other.divmod(self)[1].zero?

  # Greatest common divisor, determined up to a unit.
  -> gcd(other)
    a = self
    b = other
    while !b.zero?
      r = a.divmod(b)[1]
      a = b
      b = r
    a

  -> associates
    out = []
    units = GaussianInteger.units
    i = 0
    while i < units.size
      out.push(units[i] * self)
      i += 1
    out

  -> prime?
    return false if zero? || unit?
    if @re == 0 || @im == 0
      magnitude = @re == 0 ? @im : @re
      magnitude = 0 - magnitude if magnitude < 0
      return magnitude.prime? && magnitude % 4 == 3
    norm.prime?

  -> to_s
    return "[@re]" if @im == 0
    return "[@im]i" if @re == 0
    @im < 0 ? "[@re] - [0 - @im]i" : "[@re] + [@im]i"
