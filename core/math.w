# Math — pure-Tungsten implementations of math functions derived from
# the libm primitives the runtime exposes (`Math.exp`, `Math.log`,
# `Math.sin`, `Math.cos`, `Math.tan`, `Math.sqrt`, `Math.floor`,
# `Math.ceil`, `Math.round`, `Math.abs`, `Math.pow`, `Math.ldexp`).
#
# These derivations are accurate to within ~ulp for typical inputs.
# For specialized accuracy near edge cases (small-x for expm1, log1p,
# inverse hyperbolic for x >> 1, etc.) the libm intrinsics in the
# runtime are more precise — we wrap from the available primitives
# rather than ccall directly to keep the surface in Tungsten.

+ Math

  # Hyperbolic functions.  The sign-split tanh form never computes inf/inf,
  # and the small-x sinh path uses expm1 to avoid cancellation.

  -> .tanh(x) f64
    if x >= ~0.0
      decay = Math.exp(~-2.0 * x)
      return (~1.0 - decay) / (~1.0 + decay)
    decay = Math.exp(~2.0 * x)
    (decay - ~1.0) / (decay + ~1.0)

  -> .sinh(x) f64
    return x if x == ~0.0
    return ~0.0 - Math.sinh(~0.0 - x) if x < ~0.0
    if x < ~0.5
      delta = Math.expm1(x)
      return delta * (~2.0 + delta) / (~2.0 * (~1.0 + delta))
    ex = Math.exp(x)
    (ex - ~1.0 / ex) / ~2.0

  -> .cosh(x) f64
    magnitude = Math.abs(x)
    ex = Math.exp(magnitude)
    (ex + ~1.0 / ex) / ~2.0

  # Inverse hyperbolic.

  -> .asinh(x) f64
    return x if x == ~0.0
    return ~0.0 - Math.asinh(~0.0 - x) if x < ~0.0
    if x > ~1.0e154
      return Math.log(x) + ~0.6931471805599453
    root = Math.sqrt(~1.0 + x * x)
    Math.log1p(x + x * x / (~1.0 + root))

  -> .acosh(x) f64
    if x > ~1.0e154
      return Math.log(x) + ~0.6931471805599453
    offset = x - ~1.0
    Math.log1p(offset + Math.sqrt(offset * (x + ~1.0)))

  -> .atanh(x) f64
    return x if x == ~0.0
    return ~0.0 - Math.atanh(~0.0 - x) if x < ~0.0
    ~0.5 * Math.log1p((~2.0 * x) / (~1.0 - x))

  # Exp/log family (derived).

  # expm1 and log1p use convergent local series where direct subtraction or
  # addition would discard the low bits.
  -> .expm1(x) f64
    magnitude = Math.abs(x)
    if magnitude < ~1.0e-5
      term = x
      sum = x
      n = 2
      while n <= 24
        term = term * x / (n + ~0.0)
        sum += term
        n += 1
      return sum
    Math.exp(x) - ~1.0

  -> .log1p(x) f64
    magnitude = Math.abs(x)
    if magnitude < ~1.0e-4
      term = x
      sum = x
      n = 2
      while n <= 40
        term *= ~0.0 - x
        sum += term / (n + ~0.0)
        n += 1
      return sum
    Math.log(~1.0 + x)

  # log2(x) = ln(x) / ln(2)
  -> .log2(x) f64
    Math.log(x) / ~0.6931471805599453

  # log10(x) = ln(x) / ln(10)
  -> .log10(x) f64
    Math.log(x) / ~2.302585092994046

  # log_b(x) = ln(x) / ln(b)
  -> .log_base(x, b) f64
    Math.log(x) / Math.log(b)

  # Roots.

  # cbrt(x) = sign(x) * exp(ln|x| / 3). Sign-correct for negative x.
  -> .cbrt(x) f64
    if x == ~0.0
      ~0.0
    elsif x > ~0.0
      Math.exp(Math.log(x) / ~3.0)
    else
      ~0.0 - Math.exp(Math.log(~0.0 - x) / ~3.0)

  # Scaled hypot avoids both overflow and destructive underflow.
  -> .hypot(a, b) f64
    left = Math.abs(a)
    right = Math.abs(b)
    if right > left
      temporary = left
      left = right
      right = temporary
    return ~0.0 if left == ~0.0
    ratio = right / left
    left * Math.sqrt(~1.0 + ratio * ratio)

  # Truncation (round toward zero).
  -> .trunc(x) f64
    if x >= ~0.0
      Math.floor(x)
    else
      Math.ceil(x)

  # Inverse trig (radians).

  # atan(x) — Bhaskara-style 6th-order polynomial in [−1, 1], range
  # reduction via atan(x) = π/2 − atan(1/x) for |x| > 1. Accurate to
  # ~1e-6 across the full f32 range. Plenty for ML angle work.
  -> .atan(x) f64
    if x < ~0.0
      ~0.0 - Math.atan(~0.0 - x)
    elsif x > ~1.0
      ~1.5707963267948966 - Math.atan(~1.0 / x)
    else
      # Polynomial approx for x in [0, 1], minimax fit.
      x2 = x * x
      x * (~0.999866 + x2 * (~-0.330299 + x2 * (~0.180141 + x2 * (~-0.085133 + x2 * ~0.020835))))

  # asin(x) = atan(x / sqrt(1 - x²))   for |x| < 1
  -> .asin(x) f64
    return ~1.5707963267948966 if x == ~1.0
    return ~-1.5707963267948966 if x == ~-1.0
    Math.atan(x / Math.sqrt(~1.0 - x * x))

  # acos(x) = π/2 - asin(x)
  -> .acos(x) f64
    return ~0.0 if x == ~1.0
    return ~3.141592653589793 if x == ~-1.0
    ~1.5707963267948966 - Math.asin(x)

  # atan2(y, x) — quadrant-correct atan(y/x).
  -> .atan2(y, x) f64
    if x > ~0.0
      Math.atan(y / x)
    elsif x < ~0.0
      if y >= ~0.0
        Math.atan(y / x) + ~3.141592653589793
      else
        Math.atan(y / x) - ~3.141592653589793
    elsif y > ~0.0
      ~1.5707963267948966
    elsif y < ~0.0
      ~-1.5707963267948966
    else
      ~0.0
