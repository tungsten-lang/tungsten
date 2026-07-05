# ============================================================================
# Factorial vs. Stirling's approximation  —  pure bigint, zero floats
#
#   n! ~= sqrt(2*pi*n) * (n/e)^n               (Stirling-de Moivre)
#
# Stirling's value is irrational and, for n=2000, has ~5736 digits — it
# overflows every IEEE float. So we carry an arbitrary-precision float built
# on bigints: a K-digit integer mantissa + a base-10 exponent. e and 2*pi
# enter as 40-digit integer constants. The exact factorial is an exact bigint.
# The comparison (matching digits, relative error) is done with bigint
# subtraction and division — no float ever touches the magnitudes.
#
# Run:  benchmarks/big_math/run_stirling.sh
# ============================================================================

+ BF                          # a value = @m * 10^@e, @m kept to K=40 sig digits
  -> new(@m, @e)

  -> m
    @m
  -> e
    @e

  # 10^@1 as a bigint
  -> pow10/1
    p = 1 ## big
    i = 0
    while i < @1
      p = p * 10
      i = i + 1
    p

  # floor(sqrt(@1)) for a bigint, via integer Newton iteration
  -> isqrt/1
    n = @1
    if n < 2
      n
    else
      x = n
      y = (x + 1) / 2
      while y < x
        x = y
        y = (x + n / x) / 2
      x

  # renormalize self to exactly 40 significant digits (round half-up)
  -> norm
    k = 40
    m = @m
    e = @e
    if m == 0
      BF.new(m, 0)
    else
      d = m.to_s().size
      if d > k
        drop = d - k
        half = 5 * pow10(drop - 1)
        m = (m + half) / pow10(drop)
        e = e + drop
        if m.to_s().size > k
          m = m / 10
          e = e + 1
        BF.new(m, e)
      elsif d < k
        grow = k - d
        BF.new(m * pow10(grow), e - grow)
      else
        BF.new(m, e)

  # promote a machine int to a normalized BF
  -> from_int/1
    one = 1 ## big
    m = @1 * one
    r = BF.new(m, 0)
    r.norm

  -> mul/1
    r = BF.new(@m * @1.m, @e + @1.e)
    r.norm

  -> div/1
    k = 40
    num = @m * pow10(k + 3)
    q = num / @1.m
    r = BF.new(q, @e - @1.e - (k + 3))
    r.norm

  -> add/1                    # assumes both operands >= 0
    if @e == @1.e
      r = BF.new(@m + @1.m, @e)
      r.norm
    elsif @e > @1.e
      diff = @e - @1.e
      if diff > 80
        self
      else
        r = BF.new(@m * pow10(diff) + @1.m, @1.e)
        r.norm
    else
      diff = @1.e - @e
      if diff > 80
        @1
      else
        r = BF.new(@1.m * pow10(diff) + @m, @e)
        r.norm

  -> sqrt                     # sqrt(self), self > 0
    k = 40
    d = @m.to_s().size
    a = 2 * k + 2 - d - @e
    if a % 2 == 1
      a = a + 1
    x = @m * pow10(@e + a)
    s = isqrt(x)
    r = BF.new(s, 0 - (a / 2))
    r.norm

  -> power/1                  # self ^ @1  (@1 = int >= 0) by squaring
    one = BF.new(1, 0)
    result = one.norm
    b = self
    p = @1
    while p > 0
      if p % 2 == 1
        result = result.mul(b)
      b = b.mul(b)
      p = p / 2
    result

  # ----- the constants, to 40 significant digits -----
  -> e_const
    m = 2718281828459045235360287471352662497757 ## big
    BF.new(m, 0 - 39)

  -> twopi_const
    m = 6283185307179586476925286766559005768394 ## big
    BF.new(m, 0 - 39)

  # Stirling-de Moivre leading term:  sqrt(2*pi*n) * (n/e)^n
  -> stirling/1
    n = @1
    nbf = from_int(n)
    noe = nbf.div(self.e_const)
    powv = noe.power(n)
    twopin = self.twopi_const.mul(nbf)
    root = twopin.sqrt
    root.mul(powv)

  # multiplicative correction factor 1 + 1/(12n) (+ 1/(288 n^2) if @2 >= 2)
  -> corr_factor/2            # @1 = n, @2 = number of terms
    n = @1
    one = from_int(1)
    twelve_n = from_int(12 * n)
    t1 = from_int(1)
    factor = one.add(t1.div(twelve_n))
    if @2 >= 2
      n2 = n * n
      d2 = from_int(288 * n2)
      t1b = from_int(1)
      factor = factor.add(t1b.div(d2))
    factor

  # how many leading digits self's mantissa shares with bigint @1
  -> match_len/1
    a = @m
    b = @1
    while a != b and a > 0
      a = a / 10
      b = b / 10
    a.to_s().size

  # print one comparison row: exact bigint @1 vs Stirling BF @2; @3 = predicted
  # error denominator ("1 part in @3") from the Stirling series.
  -> report/3
    k = 40
    fact = @1
    st = @2
    theory = @3
    sm = st.m
    se = st.e
    edigits = fact.to_s().size
    drop = edigits - k
    exlead = fact / pow10(drop)
    while exlead.to_s().size > k
      exlead = exlead / 10
    sfull = sm * pow10(se)
    diff = fact - sfull
    ad = diff
    sign = "under"
    if ad < 0
      ad = 0 - ad
      sign = "over "
    one_in = sfull / ad
    el = BF.new(exlead, 0)
    matched = el.match_len(sm)
    show16 = pow10(k - 16)
    << "    exact    : " + (exlead / show16).to_s() + "...  x 10^" + (edigits - 1).to_s()
    << "    stirling : " + (sm / show16).to_s() + "...  x 10^" + (sm.to_s().size + se - 1).to_s()
    << "    -> " + matched.to_s() + " digits match;  " + sign + " by 1 part in " + one_in.to_s() + "   (theory: 1 in " + theory.to_s() + ")"

  # The float / log-space approach (the "obvious" way that overflows if done
  # naively). The trick is to never form n!: accumulate ln(n!) as a sum of
  # logs and evaluate Stirling in natural log, so nothing exceeds f64 range.
  # Fast and overflow-proof for any n — but capped at f64's ~15-16 significant
  # digits, so it can report the magnitude and the larger Stirling errors but
  # NOT emit the actual factorial digits, and it hits a precision wall on the
  # deepest correction (see the n=2000 + 1/(288 n^2) row).
  -> flog/1
    n = @1
    reps = 200
    ln10 = ~2.302585092994046
    twopi = ~6.283185307179586
    nf = n.to_f()

    # exact reference: ln(n!) = sum_{k=2}^{n} ln k   (timed over reps runs)
    lnf = ~0.0
    t0 = clock()
    r = 0
    while r < reps
      lnf = ~0.0
      k = 2
      while k <= n
        lnf = lnf + Math.log(k.to_f())
        k = k + 1
      r = r + 1
    t1 = clock()

    # Stirling in natural log, with the SAME multiplicative corrections as the
    # bigint run so the "1 part in N" numbers line up directly.
    ln_st = nf * Math.log(nf) - nf + ~0.5 * Math.log(twopi * nf)
    t2 = clock()
    r2 = 0
    while r2 < reps
      ln_st = nf * Math.log(nf) - nf + ~0.5 * Math.log(twopi * nf)
      r2 = r2 + 1
    t3 = clock()

    f1 = ~1.0 + ~1.0 / (~12.0 * nf)
    f2 = f1 + ~1.0 / (~288.0 * nf * nf)
    ln_st1 = ln_st + Math.log(f1)
    ln_st2 = ln_st + Math.log(f2)

    # recover magnitude + leading digits from the log
    log10 = lnf / ln10
    e10 = log10.floor()
    mant = Math.exp((log10 - e10.to_f()) * ln10)

    # relative error ~= ln(exact) - ln(stirling); "1 part in 1/diff"
    d0 = lnf - ln_st
    d1 = lnf - ln_st1
    d2 = lnf - ln_st2

    << "  -- float/log (f64, ~15-16 sig digits; never forms n!) --"
    << "    digits = " + (e10 + 1).to_s() + ",  leading mantissa = " + mant.to_s() + " (vs exact 9.33.../3.32...)"
    << "    Stirling basic         : 1 part in " + (~1.0 / d0).to_s()
    << "    + 1/(12n)              : 1 part in " + (~1.0 / d1).to_s()
    << "    + 1/(288 n^2)          : 1 part in " + (~1.0 / d2).to_s()
    << "    time (s): sum-of-logs = " + (t1 - t0).to_s() + ",  formula = " + (t3 - t2).to_s() + "  (x" + reps.to_s() + ")"

  -> bench/1
    n = @1
    one = 1 ## big
    reps = 200

    # exact factorial (timed over `reps` runs)
    fact = one
    t0 = clock()
    r = 0
    while r < reps
      fact = one
      i = 2
      while i <= n
        fact = fact * i
        i = i + 1
      r = r + 1
    t1 = clock()

    # stirling formula (timed over `reps` runs)
    st = self.stirling(n)
    t2 = clock()
    r = 0
    while r < reps
      st = self.stirling(n)
      r = r + 1
    t3 = clock()

    c1 = self.corr_factor(n, 1)
    c2 = self.corr_factor(n, 2)
    st1 = st.mul(c1)
    st2 = st.mul(c2)

    # theoretical "1 part in N" error denominators from the Stirling series
    th0 = 12 * n
    th1 = 288 * n * n
    th2 = 51840 * n * n * n / 139

    << "================================================================"
    << n.to_s() + "!  has " + fact.to_s().size.to_s() + " digits"
    fe = t1 - t0
    se2 = t3 - t2
    << "  exact factorial : " + (n - 1).to_s() + " bigint mults/run x " + reps.to_s() + " runs, total s ="
    << fe
    << "  stirling formula: ~11 mults+1 div+1 sqrt/run x " + reps.to_s() + " runs, total s ="
    << se2
    << ""
    << "  Stirling  sqrt(2pi n)(n/e)^n :"
    self.report(fact, st, th0)
    << ""
    << "  + 1/(12n) correction :"
    self.report(fact, st1, th1)
    << ""
    << "  + 1/(288 n^2) correction :"
    self.report(fact, st2, th2)

bf = BF.new(0, 0)
bf.bench(100)
bf.flog(100)
<< ""
bf.bench(2000)
bf.flog(2000)

<< ""
<< "================================================================"
<< "the exact 100! in full (158 digits):"
f100 = 1 ## big
i = 2
while i <= 100
  f100 = f100 * i
  i = i + 1
<< f100.to_s()
