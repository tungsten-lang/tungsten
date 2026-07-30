# Special — transcendental / special functions (SciPy `scipy.special` analogue).
#
# Lives in core/special (not core/math) because Math is elementary (exp/log/sin
# and thin compositions). Special functions are the denser catalogue used by
# physics, stats, and numerical analysis: gamma, erf, Bessel, beta, …
#
# Accuracy: series / continued-fraction approximations are generally good to
# near machine precision on the principal domains documented per function.
# Stats that consume these live in core/stats.w.

+ Special
  # ---- principal complex branches ----

  -> .complex(value, imaginary = ~0.0)
    Complex<f64>.new([value, imaginary])

  # Principal complex log-Gamma from the same Lanczos coefficients as the
  # positive-real implementation. Reflection uses principal complex log and
  # therefore makes the branch choice explicit.
  -> .complex_log_gamma(value)
    z = value
    one = Special.complex(~1.0)
    if z.real < ~0.5
      pi = ~3.14159265358979323846
      reflected = Special.complex_log_gamma(one - z)
      sine = z.scale(pi).sin
      return (
        Special.complex(Math.log(pi)) -
        sine.log - reflected)
    shifted = z - one
    coefficients = Special.lanczos_coeff
    series = Special.complex(coefficients[0])
    index = 1
    while index < coefficients.size
      denominator = shifted + Special.complex(index + ~0.0)
      series += Special.complex(coefficients[index]) / denominator
      index += 1
    t = shifted + Special.complex(Special.lanczos_g + ~0.5)
    (Special.complex(~0.91893853320467274178) +
     (shifted + Special.complex(~0.5))*t.log -
     t + series.log)

  -> .complex_lgamma(value)
    Special.complex_log_gamma(value)

  -> .complex_gamma(value)
    Special.complex_log_gamma(value).exp

  # Entire complex erf power series. The explicit radius guard avoids
  # presenting cancellation-dominated large-|z| evaluation as reliable.
  -> .complex_erf(value)
    z = value
    if z.abs > ~4.0
      raise "Special.complex_erf: |z| > 4 needs an asymptotic branch"
    factor = ~1.12837916709551257390
    z_squared = z.sq
    term = z
    sum = Special.complex(~0.0)
    index = 0
    while index < 500
      sum += term
      ratio = (
        (~0.0 - (2*index + ~1.0)) /
        ((index + ~1.0)*(2*index + ~3.0)))
      term = term*z_squared.scale(ratio)
      if term.abs <= ~2.0e-16*(~1.0 + sum.abs)
        return sum.scale(factor)
      index += 1
    raise "Special.complex_erf: series did not converge"

  # Integer branches of complex Lambert W, refined with Halley's method.
  # The returned value always satisfies a residual-based convergence check;
  # failure raises instead of returning the last iterate.
  -> .complex_lambert_w(value, branch = 0)
    branch_class = branch.class
    integral = (
      branch_class == Integer ||
      branch_class == Int ||
      branch_class == BigInt)
    if !integral
      raise "Special.complex_lambert_w: branch must be an integer"
    z = value
    if z.abs == ~0.0
      return Special.complex(~0.0) if branch == 0
      raise "Special.complex_lambert_w: nonprincipal branches have a pole at zero"
    one = Special.complex(~1.0)
    two = Special.complex(~2.0)
    if branch == 0 && z.abs < ~0.75
      w = z
    else
      logarithm = z.log + Complex<f64>.i.scale(
        ~6.28318530717958647693*(branch + ~0.0))
      w = logarithm - logarithm.log
    iterations = 0
    while iterations < 50
      exponential = w.exp
      residual = w*exponential - z
      denominator = (
        exponential*(w + one) -
        (w + two)*residual / (w.scale(~2.0) + two))
      step = residual / denominator
      w -= step
      if step.abs <= ~3.0e-15*(~1.0 + w.abs)
        final_residual = (w*w.exp - z).abs
        if final_residual <= ~2.0e-14*(~1.0 + z.abs)
          return w
      iterations += 1
    raise "Special.complex_lambert_w: Halley iteration did not converge"

  -> .complex_lambertw(value, branch = 0)
    Special.complex_lambert_w(value, branch)

  # ---- error function ----
  # erf(x) = P(1/2, x^2). The lower incomplete-gamma series is stable for
  # x^2 < 3/2; the complementary continued fraction avoids cancellation in
  # the tails. Both stop at a machine-double relative threshold.

  -> .log_sqrt_pi
    ~0.5723649429247001

  -> .gamma_half_lower(z)
    return ~0.0 if z == ~0.0
    a = ~0.5
    ap = a
    term = ~1.0 / a
    sum = term
    n = 1
    while n < 200
      ap += ~1.0
      term *= z / ap
      sum += term
      if term < sum * ~1.0e-16
        n = 200
      else
        n += 1
    scale = Math.exp(~0.0 - z + a * Math.log(z) - Special.log_sqrt_pi)
    sum * scale

  -> .gamma_half_upper(z)
    a = ~0.5
    tiny = ~1.0e-300
    b = z + ~1.0 - a
    c = ~1.0 / tiny
    d = ~1.0 / b
    fraction = d
    n = 1
    while n < 200
      index = n + ~0.0
      coefficient = (~0.0 - index) * (index - a)
      b += ~2.0
      d = coefficient * d + b
      d = tiny if d < tiny && d > ~0.0 - tiny
      c = b + coefficient / c
      c = tiny if c < tiny && c > ~0.0 - tiny
      d = ~1.0 / d
      delta = d * c
      fraction *= delta
      error = delta - ~1.0
      error = ~0.0 - error if error < ~0.0
      if error < ~1.0e-16
        n = 200
      else
        n += 1
    scale = Math.exp(~0.0 - z + a * Math.log(z) - Special.log_sqrt_pi)
    fraction * scale

  -> .erf(x)
    return ~0.0 if x == ~0.0
    negative = x < ~0.0
    magnitude = negative ? ~0.0 - x : x
    z = magnitude * magnitude
    value = Special.gamma_half_lower(z)
    value = ~1.0 - Special.gamma_half_upper(z) if z >= ~1.5
    negative ? ~0.0 - value : value

  -> .erfc(x)
    if x < ~0.0
      return ~2.0 - Special.erfc(~0.0 - x)
    return ~1.0 if x == ~0.0
    z = x * x
    return ~1.0 - Special.gamma_half_lower(z) if z < ~1.5
    Special.gamma_half_upper(z)

  # ---- gamma / digamma family ----
  # Nine-term Lanczos approximation with g=7.

  -> .lanczos_g
    ~7.0

  -> .lanczos_coeff
    [
      ~0.99999999999980993,
      ~676.5203681218851,
      ~-1259.1392167224028,
      ~771.32342877765313,
      ~-176.61502916214059,
      ~12.507343278686905,
      ~-0.13857109526572012,
      ~0.0000099843695780195716,
      ~0.00000015056327351493116
    ]

  -> .log_gamma(x)
    if x <= ~0.0
      raise "Special.log_gamma: x must be > 0"
    shifted = x - ~1.0
    coefficients = Special.lanczos_coeff
    series = coefficients[0]
    i = 1
    while i < coefficients.size
      series += coefficients[i] / (shifted + (i + ~0.0))
      i += 1
    t = shifted + Special.lanczos_g + ~0.5
    (~0.91893853320467274178 +
      (shifted + ~0.5) * Math.log(t) - t + Math.log(series))

  -> .gamma(x)
    if x < ~0.5
      # reflection
      return ~3.141592653589793 / (Math.sin(~3.141592653589793 * x) * Special.gamma(~1.0 - x))
    Math.exp(Special.log_gamma(x))

  -> .lgamma(x)
    Special.log_gamma(x)

  -> .float_factorial(n)
    result = ~1.0
    i = 2
    while i <= n
      result *= i + ~0.0
      i += 1
    result

  -> .rising_factorial(value, count)
    result = ~1.0
    i = 0
    while i < count
      result *= value + (i + ~0.0)
      i += 1
    result

  # B_(2k)/(2k), k=1..8. These drive differentiated asymptotic
  # expansions for every positive-order polygamma.
  -> .digamma_bernoulli_coefficients
    [
      ~0.083333333333333333,
      ~-0.0083333333333333333,
      ~0.0039682539682539683,
      ~-0.0041666666666666667,
      ~0.0075757575757575758,
      ~-0.021092796092796093,
      ~0.083333333333333333,
      ~-0.44325980392156863
    ]

  # Principal real digamma. Recurrence moves small positive arguments into
  # the rapidly convergent Bernoulli asymptotic regime.
  -> .digamma(x)
    raise "Special.digamma: x must be > 0" if x <= ~0.0
    shifted = x
    correction = ~0.0
    while shifted < ~10.0
      correction -= ~1.0 / shifted
      shifted += ~1.0
    inverse = ~1.0 / shifted
    inverse_squared = inverse * inverse
    power = inverse_squared
    value = Math.log(shifted) - ~0.5 * inverse
    coefficients = Special.digamma_bernoulli_coefficients
    i = 0
    while i < coefficients.size
      value -= coefficients[i] * power
      power *= inverse_squared
      i += 1
    value + correction

  # Positive-real polygamma of integral order. For m>=1 this differentiates
  # the same Bernoulli expansion exactly and applies
  #   psi_m(x) = psi_m(x+1) + (-1)^(m+1) m!/x^(m+1).
  -> .polygamma(order, x)
    integer_name = order.class_name
    integral_order = integer_name == "Integer" || integer_name == "Int"
    integral_order = true if integer_name == "BigInt"
    if !integral_order || order < 0
      raise "Special.polygamma: order must be a nonnegative integer"
    return Special.digamma(x) if order == 0
    raise "Special.polygamma: x must be > 0" if x <= ~0.0

    factorial = Special.float_factorial(order)
    recurrence_sign = order.odd? ? ~1.0 : ~-1.0
    shifted = x
    correction = ~0.0
    while shifted < ~10.0
      correction += recurrence_sign * factorial / shifted**(order + 1)
      shifted += ~1.0

    derivative_sign = order.odd? ? ~-1.0 : ~1.0
    log_sign = order.odd? ? ~1.0 : ~-1.0
    half_sign = order.odd? ? ~1.0 : ~-1.0
    value = log_sign * Special.float_factorial(order - 1) / shifted**order
    value += half_sign * factorial / (~2.0 * shifted**(order + 1))

    coefficients = Special.digamma_bernoulli_coefficients
    k = 1
    while k <= coefficients.size
      rising = Special.rising_factorial(2*k + ~0.0, order)
      denominator = shifted**(2*k + order)
      value -= coefficients[k - 1] * derivative_sign * rising / denominator
      k += 1
    value + correction

  -> .trigamma(x)
    Special.polygamma(1, x)

  # Integer zeta values use
  # psi^(s-1)(1) = (-1)^s (s-1)! zeta(s). Real s>1 is handled by the
  # Euler-Maclaurin Hurwitz-zeta path below.
  -> .zeta(s)
    name = s.class_name
    integral = name == "Integer" || name == "Int" || name == "BigInt"
    if integral
      raise "Special.zeta requires s > 1" if s <= 1
      sign = s.even? ? ~1.0 : ~-1.0
      return (sign * Special.polygamma(s - 1, ~1.0) /
              Special.float_factorial(s - 1))
    Special.hurwitz_zeta(s, ~1.0)

  # Principal real Hurwitz zeta for s>1 and a>0.  Euler-Maclaurin with
  # five Bernoulli corrections gives near-binary64 accuracy after shifting
  # the tail to a+24.
  -> .hurwitz_zeta(s, a)
    if s <= ~1.0 || a <= ~0.0
      raise "Special.hurwitz_zeta requires s > 1 and a > 0"
    shifted = a
    sum = ~0.0
    while shifted < ~24.0
      sum += ~1.0 / shifted**s
      shifted += ~1.0
    sum += shifted**(~1.0 - s) / (s - ~1.0)
    sum += ~0.5 * shifted**(~0.0 - s)
    coefficients = [
      ~0.083333333333333333333,
      ~-0.001388888888888888889,
      ~0.000033068783068783069,
      ~-0.000000826719576719577,
      ~0.000000020876756987868
    ]
    k = 1
    while k <= coefficients.size
      rising = Special.rising_factorial(s, 2*k - 1)
      sum += (coefficients[k - 1] * rising /
              shifted**(s + 2*k - 1))
      k += 1
    sum

  # factorials via gamma(n+1) for non-negative integers / reals
  -> .factorial(n)
    Special.gamma(n + ~1.0)

  # ---- beta ----

  -> .beta(a, b)
    Math.exp(Special.lgamma(a) + Special.lgamma(b) - Special.lgamma(a + b))

  -> .betaln(a, b)
    Special.lgamma(a) + Special.lgamma(b) - Special.lgamma(a + b)

  # ---- Bessel J0, J1 (series for |x|<8, asymptotic otherwise simplified) ----

  -> .j0(x)
    ax = x
    if ax < ~0.0
      ax = ~0.0 - ax
    if ax < ~8.0
      y = x * x
      ans1 = ~57568490574.0 + y * (~0.0 - ~13362590354.0 + y * (~651619640.7 + y * (~0.0 - ~11214424.18 + y * (~77392.33017 + y * ~0.0 - ~184.9052456))))
      ans2 = ~57568490411.0 + y * (~1029532985.0 + y * (~9494680.718 + y * (~59272.64853 + y * (~267.8532712 + y * ~1.0))))
      return ans1 / ans2
    z = ~8.0 / ax
    y = z * z
    xx = ax - ~0.785398164
    ans1 = ~1.0 + y * (~0.0 - ~0.1098628627e-2 + y * (~0.2734510407e-4 + y * (~0.0 - ~0.2073370639e-5 + y * ~0.2093887211e-6)))
    ans2 = ~0.0 - ~0.1562499995e-1 + y * (~0.1430488765e-3 + y * (~0.0 - ~0.6911147651e-5 + y * (~0.7621095161e-6 + y * ~0.0 - ~0.934935152e-7)))
    Math.sqrt(~0.636619772 / ax) * (Math.cos(xx) * ans1 - z * Math.sin(xx) * ans2)

  -> .j1(x)
    ax = x
    if ax < ~0.0
      ax = ~0.0 - ax
    if ax < ~8.0
      y = x * x
      ans1 = x * (~72362614232.0 + y * (~0.0 - ~7895059235.0 + y * (~242396853.1 + y * (~0.0 - ~2972611.439 + y * (~15704.48260 + y * ~0.0 - ~30.16036606)))))
      ans2 = ~144725228442.0 + y * (~2300535178.0 + y * (~18583304.74 + y * (~99447.43394 + y * (~376.9991397 + y * ~1.0))))
      return ans1 / ans2
    z = ~8.0 / ax
    y = z * z
    xx = ax - ~2.356194491
    ans1 = ~1.0 + y * (~0.183105e-2 + y * (~0.0 - ~0.3516396496e-4 + y * (~0.2457520174e-5 + y * ~0.0 - ~0.240337019e-6)))
    ans2 = ~0.04687499995 + y * (~0.0 - ~0.2002690873e-3 + y * (~0.8449199096e-5 + y * (~0.0 - ~0.88228987e-6 + y * ~0.105787412e-6)))
    ans = Math.sqrt(~0.636619772 / ax) * (Math.cos(xx) * ans1 - z * Math.sin(xx) * ans2)
    if x < ~0.0
      return ~0.0 - ans
    ans

  # ---- sigmoid / softplus (ML-adjacent, kept with special) ----

  -> .logistic(x)
    if x >= ~0.0
      return ~1.0 / (~1.0 + Math.exp(~0.0 - x))
    exponential = Math.exp(x)
    exponential / (~1.0 + exponential)

  -> .softplus(x)
    if x > ~20.0
      return x
    return Math.exp(x) if x < ~-20.0
    Math.log1p(Math.exp(x))

  # ---- regularized incomplete gamma ----

  -> .gammainc_series(a, x)
    ap = a
    sum = ~1.0 / a
    term = sum
    n = 1
    while n < 500
      ap += ~1.0
      term *= x / ap
      sum += term
      relative = term / sum
      relative = ~0.0 - relative if relative < ~0.0
      if relative < ~1.0e-16
        n = 500
      else
        n += 1
    sum * Math.exp(~0.0 - x + a*Math.log(x) - Special.lgamma(a))

  # Lentz continued fraction for Q(a,x). This is the stable tail branch;
  # computing it as 1-P would erase the small result.
  -> .gammaincc_fraction(a, x)
    tiny = ~1.0e-300
    b = x + ~1.0 - a
    c = ~1.0 / tiny
    d = ~1.0 / b
    fraction = d
    n = 1
    while n < 500
      index = n + ~0.0
      coefficient = (~0.0 - index)*(index - a)
      b += ~2.0
      d = coefficient*d + b
      d = tiny if d < tiny && d > ~0.0 - tiny
      c = b + coefficient / c
      c = tiny if c < tiny && c > ~0.0 - tiny
      d = ~1.0 / d
      delta = d*c
      fraction *= delta
      error = delta - ~1.0
      error = ~0.0 - error if error < ~0.0
      if error < ~1.0e-16
        n = 500
      else
        n += 1
    (Math.exp(~0.0 - x + a*Math.log(x) - Special.lgamma(a)) *
     fraction)

  -> .gammainc(a, x)
    if x < ~0.0 || a <= ~0.0
      raise "Special.gammainc: domain"
    return ~0.0 if x == ~0.0
    if x < a + ~1.0
      return Special.gammainc_series(a, x)
    ~1.0 - Special.gammaincc_fraction(a, x)

  -> .gammaincc(a, x)
    if x < ~0.0 || a <= ~0.0
      raise "Special.gammaincc: domain"
    return ~1.0 if x == ~0.0
    if x < a + ~1.0
      return ~1.0 - Special.gammainc_series(a, x)
    Special.gammaincc_fraction(a, x)

  # ---- regularized incomplete beta ----

  -> .betainc_fraction(a, b, x)
    maximum = 300
    epsilon = ~3.0e-16
    tiny = ~1.0e-300
    qab = a + b
    qap = a + ~1.0
    qam = a - ~1.0
    c = ~1.0
    d = ~1.0 - qab*x / qap
    d = tiny if d < tiny && d > ~0.0 - tiny
    d = ~1.0 / d
    h = d
    m = 1
    while m <= maximum
      m2 = 2*m
      mm = m + ~0.0
      aa = mm*(b - mm)*x / ((qam + m2)*(a + m2))
      d = ~1.0 + aa*d
      d = tiny if d < tiny && d > ~0.0 - tiny
      c = ~1.0 + aa / c
      c = tiny if c < tiny && c > ~0.0 - tiny
      d = ~1.0 / d
      h *= d*c
      aa = (~0.0 - (a + mm)*(qab + mm)*x /
            ((a + m2)*(qap + m2)))
      d = ~1.0 + aa*d
      d = tiny if d < tiny && d > ~0.0 - tiny
      c = ~1.0 + aa / c
      c = tiny if c < tiny && c > ~0.0 - tiny
      d = ~1.0 / d
      delta = d*c
      h *= delta
      error = delta - ~1.0
      error = ~0.0 - error if error < ~0.0
      return h if error < epsilon
      m += 1
    h

  -> .betainc(a, b, x)
    if a <= ~0.0 || b <= ~0.0 || x < ~0.0 || x > ~1.0
      raise "Special.betainc: domain"
    return ~0.0 if x == ~0.0
    return ~1.0 if x == ~1.0
    front = Math.exp(
      Special.lgamma(a + b) - Special.lgamma(a) -
      Special.lgamma(b) + a*Math.log(x) + b*Math.log1p(~0.0 - x))
    if x < (a + ~1.0) / (a + b + ~2.0)
      return front*Special.betainc_fraction(a, b, x) / a
    ~1.0 - (
      front*Special.betainc_fraction(b, a, ~1.0 - x) / b)

  # ---- principal real Lambert W ----

  -> .lambert_w(x)
    branch_point = ~-0.36787944117144232160
    if x < branch_point
      raise "Special.lambert_w: principal real branch needs x >= -1/e"
    return ~-1.0 if x == branch_point
    return ~0.0 if x == ~0.0
    if x < ~-0.3
      p = Math.sqrt(~2.0*(~2.718281828459045*x + ~1.0))
      w = (~-1.0 + p - p*p / ~3.0 +
           ~0.15277777777777778*p*p*p)
    elsif x < ~3.0
      w = Math.log1p(x)
    else
      logarithm = Math.log(x)
      w = logarithm - Math.log(logarithm)
    iterations = 0
    while iterations < 30
      exponential = Math.exp(w)
      residual = w*exponential - x
      denominator = (
        exponential*(w + ~1.0) -
        (w + ~2.0)*residual / (~2.0*w + ~2.0))
      step = residual / denominator
      w -= step
      error = step < ~0.0 ? ~0.0 - step : step
      return w if error <= ~2.0e-15*(~1.0 + (w < ~0.0 ? ~0.0 - w : w))
      iterations += 1
    w

  -> .lambertw(x)
    Special.lambert_w(x)
