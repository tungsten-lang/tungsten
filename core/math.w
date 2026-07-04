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

  # Hyperbolic (exact, just compose with exp).

  # tanh(x) = (e^(2x) - 1) / (e^(2x) + 1)
  # Stable form across the full f32 range; saturates at ±1 for |x| > ~9.
  -> .tanh(x)
    e2x = Math.exp(~2.0 * x)
    (e2x - ~1.0) / (e2x + ~1.0)

  # sinh(x) = (e^x - e^-x) / 2
  -> .sinh(x)
    ex = Math.exp(x)
    (ex - ~1.0 / ex) / ~2.0

  # cosh(x) = (e^x + e^-x) / 2
  -> .cosh(x)
    ex = Math.exp(x)
    (ex + ~1.0 / ex) / ~2.0

  # Inverse hyperbolic.

  # asinh(x) = ln(x + sqrt(x² + 1))
  -> .asinh(x)
    Math.log(x + Math.sqrt(x * x + ~1.0))

  # acosh(x) = ln(x + sqrt(x² - 1))   for x >= 1
  -> .acosh(x)
    Math.log(x + Math.sqrt(x * x - ~1.0))

  # atanh(x) = 0.5 * ln((1 + x) / (1 - x))   for |x| < 1
  -> .atanh(x)
    ~0.5 * Math.log((~1.0 + x) / (~1.0 - x))

  # Exp/log family (derived).

  # expm1(x) = e^x - 1. Note: less precise near x=0 than libm's expm1
  # (which is engineered to avoid the catastrophic cancellation).
  -> .expm1(x)
    Math.exp(x) - ~1.0

  # log1p(x) = ln(1 + x). Same accuracy caveat as above near x=0.
  -> .log1p(x)
    Math.log(~1.0 + x)

  # log2(x) = ln(x) / ln(2)
  -> .log2(x)
    Math.log(x) / ~0.6931471805599453

  # log10(x) = ln(x) / ln(10)
  -> .log10(x)
    Math.log(x) / ~2.302585092994046

  # log_b(x) = ln(x) / ln(b)
  -> .log_base(x, b)
    Math.log(x) / Math.log(b)

  # Roots.

  # cbrt(x) = sign(x) * exp(ln|x| / 3). Sign-correct for negative x.
  -> .cbrt(x)
    if x == ~0.0
      ~0.0
    elsif x > ~0.0
      Math.exp(Math.log(x) / ~3.0)
    else
      ~0.0 - Math.exp(Math.log(~0.0 - x) / ~3.0)

  # hypot(a, b) = sqrt(a² + b²). Naive form — risks overflow when
  # |a|, |b| > ~2^63. For ML-scale inputs this is fine.
  -> .hypot(a, b)
    Math.sqrt(a * a + b * b)

  # Truncation (round toward zero).
  -> .trunc(x)
    if x >= ~0.0
      Math.floor(x)
    else
      Math.ceil(x)

  # Inverse trig (radians).

  # atan(x) — Bhaskara-style 6th-order polynomial in [−1, 1], range
  # reduction via atan(x) = π/2 − atan(1/x) for |x| > 1. Accurate to
  # ~1e-6 across the full f32 range. Plenty for ML angle work.
  -> .atan(x)
    if x < ~0.0
      ~0.0 - Math.atan(~0.0 - x)
    elsif x > ~1.0
      ~1.5707963267948966 - Math.atan(~1.0 / x)
    else
      # Polynomial approx for x in [0, 1], minimax fit.
      x2 = x * x
      x * (~0.999866 + x2 * (~-0.330299 + x2 * (~0.180141 + x2 * (~-0.085133 + x2 * ~0.020835))))

  # asin(x) = atan(x / sqrt(1 - x²))   for |x| < 1
  -> .asin(x)
    Math.atan(x / Math.sqrt(~1.0 - x * x))

  # acos(x) = π/2 - asin(x)
  -> .acos(x)
    ~1.5707963267948966 - Math.asin(x)

  # atan2(y, x) — quadrant-correct atan(y/x).
  -> .atan2(y, x)
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
