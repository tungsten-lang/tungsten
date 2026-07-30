# Complex — dimension-2 hypercomplex (basis: 1, i).
# z = a + bi stored as components [a, b]. Scalar-first.
#
# Literals:
#   %h2-f32[a b]     → Complex<f32>  (math; a + bi)
#   %h2-float2[a b]  → Complex<f32>  (Metal-aligned float2; same order)
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

  -> .i
    class.new([0, 1] ## T[2])

  -> .cis(angle)
    class.new([Math.cos(angle), Math.sin(angle)] ## T[2])

  -> .polar(radius, angle)
    class.new([
      radius * Math.cos(angle),
      radius * Math.sin(angle)
    ] ## T[2])

  # Cayley–Dickson half: Complex doubles R (the reals) to produce
  # itself; there's no lower Hypercomplex level. Returns nil to mark
  # this as the floor of the tower.
  -> half_class
    nil

  # Imaginary *coefficient* (the b in a + bi). The pure-imaginary
  # *value* is inherited from Hypercomplex as `.imaginary`.
  -> imag
    components[1]

  # Scaled modulus avoids overflow and destructive underflow in the inherited
  # naive sum-of-squares norm.
  -> abs
    Math.hypot(real, imag)

  # Argument: the signed angle on the Argand plane, atan2(b, a) ∈ (−π, π].
  # Overrides Hypercomplex's unsigned generalization so a point below the
  # real axis (negative b) reports a negative phase — the polar companion
  # to `abs` for the Argand plot.
  -> arg
    Math.atan2(imag, real)

  -> polar
    [abs, arg]

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

  # Principal complex elementary functions. Unique internal names prevent the
  # compiler's scalar-libm fast path from intercepting compositions such as
  # asin(z), which are themselves defined using complex log and square root.

  -> complex_exp
    scale = Math.exp(real)
    class.new([
      scale * Math.cos(imag),
      scale * Math.sin(imag)
    ] ## T[2])

  -> exp
    self.complex_exp

  -> complex_log
    magnitude = abs
    raise "cannot take log of zero complex value" if magnitude == 0
    class.new([Math.log(magnitude), arg] ## T[2])

  -> log
    self.complex_log

  -> complex_sqrt
    magnitude = abs
    return zero if magnitude == 0

    if real >= 0
      real_part = Math.sqrt(magnitude / ~2.0 + real / ~2.0)
      imag_part = imag / (~2.0 * real_part)
      return class.new([real_part, imag_part] ## T[2])

    imag_part = Math.sqrt(magnitude / ~2.0 - real / ~2.0)
    imag_part = ~0.0 - imag_part if imag < 0
    real_part = imag / (~2.0 * imag_part)
    real_part = ~0.0 - real_part if real_part < 0
    class.new([real_part, imag_part] ## T[2])

  -> sqrt
    self.complex_sqrt

  -> sin_cos
    sine_real = Math.sin(real) * Math.cosh(imag)
    sine_imag = Math.cos(real) * Math.sinh(imag)
    cosine_real = Math.cos(real) * Math.cosh(imag)
    cosine_imag = ~0.0 - Math.sin(real) * Math.sinh(imag)
    [
      class.new([sine_real, sine_imag] ## T[2]),
      class.new([cosine_real, cosine_imag] ## T[2])
    ]

  -> sin
    self.sin_cos[0]

  -> cos
    self.sin_cos[1]

  -> tan
    pair = self.sin_cos
    pair[0] / pair[1]

  -> sinh_cosh
    sine_real = Math.sinh(real) * Math.cos(imag)
    sine_imag = Math.cosh(real) * Math.sin(imag)
    cosine_real = Math.cosh(real) * Math.cos(imag)
    cosine_imag = Math.sinh(real) * Math.sin(imag)
    [
      class.new([sine_real, sine_imag] ## T[2]),
      class.new([cosine_real, cosine_imag] ## T[2])
    ]

  -> sinh
    self.sinh_cosh[0]

  -> cosh
    self.sinh_cosh[1]

  -> tanh
    pair = self.sinh_cosh
    pair[0] / pair[1]

  -> complex_asin
    unit_i = class.i
    inside = unit_i * self + (one - self.sq).complex_sqrt
    unit_i.negate * inside.complex_log

  -> asin
    self.complex_asin

  -> acos
    class.real(~1.5707963267948966) - self.complex_asin

  -> atan
    unit_i = class.i
    iz = unit_i * self
    difference = (one - iz).complex_log - (one + iz).complex_log
    unit_i.scale(~0.5) * difference

  -> asinh
    (self + (self.sq + one).complex_sqrt).complex_log

  -> acosh
    left_root = (self + one).complex_sqrt
    right_root = (self - one).complex_sqrt
    (self + left_root * right_root).complex_log

  -> atanh
    difference = (one + self).complex_log - (one - self).complex_log
    difference.scale(~0.5)

  # Principal power for real or complex exponents. Integer `**` remains the
  # exact binary-exponentiation operation inherited from Hypercomplex.
  -> pow(exponent)
    logarithm = self.complex_log
    if logarithm.scalar_like?(exponent)
      return logarithm.scale(exponent).complex_exp
    (logarithm * exponent).complex_exp
