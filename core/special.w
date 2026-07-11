# Special — transcendental / special functions (SciPy `scipy.special` analogue).
#
# Lives in core/special (not core/math) because Math is elementary (exp/log/sin
# and thin compositions). Special functions are the denser catalogue used by
# physics, stats, and numerical analysis: gamma, erf, Bessel, beta, …
#
# Accuracy: series / continued-fraction approximations good to ~1e-10 relative
# on the principal domains documented per function. For edge cases prefer
# libm when a runtime bridge exists.
#
# Lives at core/sci/special.w. Stats that consume these: core/sci/stats.w.

+ Special
  # ---- error function ----
  # Abramowitz & Stegun ~7.1.26 rational approximation; max error ~1.5e-7.

  -> .erf(x)
    if x < ~0.0
      return ~0.0 - Special.erf(~0.0 - x)
    # constants
    p = ~0.3275911
    a1 = ~0.254829592
    a2 = ~0.0 - ~0.284496736
    a3 = ~1.421413741
    a4 = ~0.0 - ~1.453152027
    a5 = ~1.061405429
    t = ~1.0 / (~1.0 + p * x)
    y = ~1.0 - (((((a5 * t + a4) * t) + a3) * t + a2) * t + a1) * t * Math.exp(~0.0 - x * x)
    y

  -> .erfc(x)
    ~1.0 - Special.erf(x)

  # ---- gamma / digamma family ----
  # Lanczos approximation g=5, n=6 (numerical recipes style).

  -> .lanczos_g
    ~5.0

  -> .lanczos_coeff
    [~1.000000000190015,
     ~76.18009172947146,
     ~0.0 - ~86.50532032941677,
     ~24.01409824083091,
     ~0.0 - ~1.231739572450155,
     ~0.001208650973866179,
     ~0.0 - ~0.000005395239384953]

  -> .log_gamma(x)
    if x <= ~0.0
      raise "Special.log_gamma: x must be > 0"
    # reflection for (0,1) via Γ(x)Γ(1−x)=π/sin(πx) handled at gamma()
    g = Special.lanczos_g
    c = Special.lanczos_coeff
    tmp = x + g + ~0.5
    ser = c[0]
    i = 1
    while i < c.size()
      ser = ser + c[i] / (x + (i + ~0.0))
      i = i + 1
    Math.log(~2.5066282746310005 * ser / x) + (x + ~0.5) * Math.log(tmp) - tmp

  -> .gamma(x)
    if x < ~0.5
      # reflection
      return ~3.141592653589793 / (Math.sin(~3.141592653589793 * x) * Special.gamma(~1.0 - x))
    Math.exp(Special.log_gamma(x))

  -> .lgamma(x)
    Special.log_gamma(x)

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
    ~1.0 / (~1.0 + Math.exp(~0.0 - x))

  -> .softplus(x)
    if x > ~20.0
      return x
    Math.log(~1.0 + Math.exp(x))

  # ---- incomplete gamma (lower, series for x < a+1) ----

  -> .gammainc(a, x)
    if x < ~0.0 || a <= ~0.0
      raise "Special.gammainc: domain"
    if x == ~0.0
      return ~0.0
    # series
    ap = a
    sum = ~1.0 / a
    del = sum
    n = 1
    while n < 200
      ap = ap + ~1.0
      del = del * x / ap
      sum = sum + del
      if del < sum * ~1.0e-12
        n = 200
      else
        n = n + 1
    Math.exp(~0.0 - x + a * Math.log(x) - Special.lgamma(a)) * sum
