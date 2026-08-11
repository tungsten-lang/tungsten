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

  # Convert any dimension-2 complex value (e.g. the bare wvalue Complex)
  # into this specialization's array-backed representation.
  -> .from(z)
    class.new([z.real, z.imag] ## T[2])

  # Cayley–Dickson half: Complex doubles R (the reals) to produce
  # itself; there's no lower Hypercomplex level. Returns nil to mark
  # this as the floor of the tower.
  -> half_class
    nil

  # Imaginary *coefficient* (the b in a + bi). The pure-imaginary
  # *value* is inherited from Hypercomplex as `.imaginary`.
  -> imag
    components[1]

  # Dimension-2 specialization of Hypercomplex#abs2. Besides avoiding the
  # generic Enumerable pipeline, this keeps reciprocal and division on the
  # same four scalar loads used by the optimized Complex arithmetic below.
  -> abs2
    real * real + imag * imag

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

  # Keep the public representation independent of the compiler's internal
  # specialization name (Complex$f64, Complex$f32, ...), matching bare
  # Complex and the interpreter's generic-erased class table.
  -> to_s
    "Complex(" + real.to_s + ", " + imag.to_s + ")"

# Bare Complex — the lightweight wvalue scalar (Erik 8/8: "Complex.new for
# the wvalue vs Complex<T>.new for the array-based ones"). Two plain ivar
# slots, no inner typed-array allocation; the generic tower above stays the
# array-backed representation and is untouched. The bare name was previously
# unresolvable (the template needs type args), so this class claims it
# without touching the generic registry.
#
# Engine note: the tree-walker erases generics and MERGES Complex<T> and
# bare Complex into one class table (re-open semantics, last-wins methods,
# constructors dispatched by arity: tower new/1 sets @components, bare
# new/2 sets @re/@im). Instances therefore come in two ivar shapes there,
# so every method reads through `real`/`imag`, which fall back from @re/@im
# to @components. Compiled engines keep the classes fully separate and the
# fallback branch is dead (bare instances always carry @re/@im).
#
# Interop: `components` returns [real, imag], so Hypercomplex's structural
# machinery (zip/map arithmetic, approx?, dimension checks) accepts a bare
# Complex as a dimension-2 operand. Convert with `Complex.from(tower_z)`
# and `Complex<f64>.from(bare_z)`. Note: compiled tower == bare compares a
# T[2] typed array against [re, im] and stays false; compare with .approx?
# or convert for cross-representation equality.
+ Complex < Number
  # Slots coerce to machine f64 — the same normalization Complex<f64>'s
  # `## T[2]` storage performs. Keeping the slots machine-typed also keeps
  # every comparison float-vs-float (exactness: 2.0 == 2 is false, and
  # decimal-vs-int ordering currently faults — see the bug lane).
  -> new(a, b)
    @re = a.to_f
    @im = b.to_f

  -> .zero
    Complex.new(0.0, 0.0)

  -> .one
    Complex.new(1.0, 0.0)

  -> .i
    Complex.new(0.0, 1.0)

  -> .real(value)
    Complex.new(value, 0)

  -> .pure(values)
    Complex.new(0, values[0])

  -> .cis(angle)
    Complex.new(Math.cos(angle), Math.sin(angle))

  -> .polar(radius, angle)
    Complex.new(radius * Math.cos(angle), radius * Math.sin(angle))

  -> .from(z)
    Complex.new(z.real, z.imag)

  -> real
    return @re if @re != nil
    @components[0]

  -> imag
    return @im if @im != nil
    @components[1]

  -> dimension
    2

  -> scalar_index
    0

  -> components
    [real, imag]

  -> e0
    real

  -> e1
    imag

  -> e(n)
    return real if n == 0
    return imag if n == 1
    raise ArgumentError, "basis index out of range: [n]"

  -> imaginary
    Complex.new(0, imag)

  -> abs2
    real * real + imag * imag

  -> abs
    Math.hypot(real, imag)

  -> norm
    abs

  -> arg
    Math.atan2(imag, real)

  -> polar
    [abs, arg]

  -> conjugate
    Complex.new(real, 0 - imag)

  -> negate
    Complex.new(0 - real, 0 - imag)

  -> -@
    negate

  -> scalar_like?/1
    !@1.respond_to?("components")

  -> +/1
    return Complex.new(real + @1, imag) if scalar_like?(@1)
    Complex.new(real + @1.real, imag + @1.imag)

  -> -/1
    return Complex.new(real - @1, imag) if scalar_like?(@1)
    Complex.new(real - @1.real, imag - @1.imag)

  ## (a + bi)(c + di) = (ac − bd) + (ad + bc)i — same 4-mul Cayley–Dickson
  ## product as the tower, on scalar slots instead of array elements.
  -> */1
    return scale(@1) if scalar_like?(@1)
    a = real
    b = imag
    c = @1.real
    d = @1.imag
    Complex.new(a * c - b * d, a * d + b * c)

  -> sq
    Complex.new(real * real - imag * imag, 2 * real * imag)

  -> //1
    return scalar_div(@1) if scalar_like?(@1)
    denom = @1.real * @1.real + @1.imag * @1.imag
    raise "division by zero complex value" if denom == 0
    Complex.new(
      (real * @1.real + imag * @1.imag) / denom,
      (imag * @1.real - real * @1.imag) / denom
    )

  -> reciprocal
    Complex.one / self

  -> scale/1
    Complex.new(real * @1, imag * @1)

  -> scalar_add/1
    Complex.new(real + @1, imag)

  -> scalar_sub/1
    Complex.new(real - @1, imag)

  -> scalar_div/1
    raise "division by zero" if @1 == 0
    Complex.new(real / @1, imag / @1)

  -> dot/1
    real * @1.components[0] + imag * @1.components[1]

  -> normalize
    raise "cannot normalize zero complex value" if zero?
    scalar_div(abs)

  -> ==/1
    return false if scalar_like?(@1)
    @1.dimension == 2 && real == @1.real && imag == @1.imag

  -> !=/1
    !(self == @1)

  -> approx?/1
    approx?(@1, 0.000001)

  -> approx?/2
    return false if scalar_like?(@1)
    return false if @1.dimension != 2
    (real - @1.real).abs <= @2 && (imag - @1.imag).abs <= @2

  -> <=>/1
    abs2 <=> @1.abs2

  -> zero?
    real == 0.0 && imag == 0.0

  -> one?
    real == 1.0 && imag == 0.0

  -> unit?
    abs2 == 1.0

  -> is_real?
    imag == 0.0

  -> pure?
    real == 0.0

  -> each_component/&
    &(real)
    &(imag)

  ## Principal elementary functions — same formulas as the tower, on slots.

  -> complex_exp
    scale_by = Math.exp(real)
    Complex.new(scale_by * Math.cos(imag), scale_by * Math.sin(imag))

  -> exp
    self.complex_exp

  -> complex_log
    magnitude = abs
    raise "cannot take log of zero complex value" if magnitude == 0
    Complex.new(Math.log(magnitude), arg)

  -> log
    self.complex_log

  -> complex_sqrt
    magnitude = abs
    return Complex.zero if magnitude == 0
    if real >= 0
      real_part = Math.sqrt(magnitude / 2.0 + real / 2.0)
      imag_part = imag / (2.0 * real_part)
      return Complex.new(real_part, imag_part)
    imag_part = Math.sqrt(magnitude / 2.0 - real / 2.0)
    imag_part = 0.0 - imag_part if imag < 0
    real_part = imag / (2.0 * imag_part)
    real_part = 0.0 - real_part if real_part < 0
    Complex.new(real_part, imag_part)

  -> sqrt
    self.complex_sqrt

  -> sin_cos
    sine_real = Math.sin(real) * Math.cosh(imag)
    sine_imag = Math.cos(real) * Math.sinh(imag)
    cosine_real = Math.cos(real) * Math.cosh(imag)
    cosine_imag = 0.0 - Math.sin(real) * Math.sinh(imag)
    [Complex.new(sine_real, sine_imag), Complex.new(cosine_real, cosine_imag)]

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
    [Complex.new(sine_real, sine_imag), Complex.new(cosine_real, cosine_imag)]

  -> sinh
    self.sinh_cosh[0]

  -> cosh
    self.sinh_cosh[1]

  -> tanh
    pair = self.sinh_cosh
    pair[0] / pair[1]

  -> complex_asin
    unit_i = Complex.i
    inside = unit_i * self + (Complex.one - self.sq).complex_sqrt
    unit_i.negate * inside.complex_log

  -> asin
    self.complex_asin

  -> acos
    Complex.real(1.5707963267948966) - self.complex_asin

  -> atan
    unit_i = Complex.i
    iz = unit_i * self
    difference = (Complex.one - iz).complex_log - (Complex.one + iz).complex_log
    unit_i.scale(0.5) * difference

  -> asinh
    (self + (self.sq + Complex.one).complex_sqrt).complex_log

  -> acosh
    left_root = (self + Complex.one).complex_sqrt
    right_root = (self - Complex.one).complex_sqrt
    (self + left_root * right_root).complex_log

  -> atanh
    difference = (Complex.one + self).complex_log - (Complex.one - self).complex_log
    difference.scale(0.5)

  -> pow(exponent)
    logarithm = self.complex_log
    if logarithm.scalar_like?(exponent)
      return logarithm.scale(exponent).complex_exp
    (logarithm * exponent).complex_exp

  ## Integer power by binary exponentiation (mirrors Hypercomplex#**).
  -> **/1
    return Complex.one if @1 == 0
    base = self
    n = @1
    if n < 0
      base = self.reciprocal
      n = 0 - n
    result = Complex.one
    while n > 0
      result = result * base if n % 2 == 1
      base = base.sq
      n = n / 2
    result

  -> to_s
    "Complex(" + real.to_s + ", " + imag.to_s + ")"
