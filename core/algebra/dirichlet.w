# Analytic number theory primitives: von Mangoldt sums, Dirichlet characters,
# Dirichlet L-functions / Riemann zeta, and CM types on (Z/lZ)^*.
#
# Computational mirror of the analytic and combinatorial definitions in
# `Formalism/Statement.lean` and `Formalism/StatementCM.lean` (Satori RH Route B).

use calculus

+ VonMangoldt
  -> .euler_gamma
    ~0.57721566490153286061

  # Returns [p, k] if n = p^k for a prime p and k >= 1, else nil.
  -> .prime_power(n)
    return nil if n < 2
    d = 2
    p = 0
    while d * d <= n
      if n % d == 0
        p = d
        break
      d += 1
    p = n if p == 0
    k = 0
    rem = n
    while rem % p == 0
      rem = rem / p
      k += 1
    return nil if rem != 1
    [p, k]

  -> .lambda(n)
    pp = VonMangoldt.prime_power(n)
    return ~0.0 if pp == nil
    Math.log(pp[0] + ~0.0)

  -> .psi(x)
    limit = (x + ~0.0).floor.to_i
    total = ~0.0
    n = 2
    while n <= limit
      total += VonMangoldt.lambda(n)
      n += 1
    total

  # Sz(x) = sum_{1 <= n <= x} Lambda(n) * (x / n - 1)
  -> .weighted_sum_zeta(x)
    xf = x + ~0.0
    limit = xf.floor.to_i
    total = ~0.0
    n = 2
    while n <= limit
      lam = VonMangoldt.lambda(n)
      if lam > ~0.0
        total += lam * (xf / (n + ~0.0) - ~1.0)
      n += 1
    total

  # Gz(x) = Sz(x) - x log x + (1 + gamma) x
  -> .error_gz(x)
    xf = x + ~0.0
    VonMangoldt.weighted_sum_zeta(xf) - xf * Math.log(xf) + (~1.0 + VonMangoldt.euler_gamma) * xf

  # S(chi, x) = sum_{1 <= n <= x} Lambda(n) * (1 + Re chi(n)) * (x / n - 1)
  -> .weighted_sum(chi, x)
    xf = x + ~0.0
    limit = xf.floor.to_i
    total = ~0.0
    n = 2
    while n <= limit
      lam = VonMangoldt.lambda(n)
      if lam > ~0.0
        w = ~1.0 + chi.at(n).real
        total += lam * w * (xf / (n + ~0.0) - ~1.0)
      n += 1
    total

  # G(chi, x) = S(chi, x) - x log x + (1 + gamma_F) x
  -> .error_g(chi, x, gamma_f)
    xf = x + ~0.0
    VonMangoldt.weighted_sum(chi, xf) - xf * Math.log(xf) + (~1.0 + gamma_f) * xf


+ DirichletCharacter
  ro :modulus, :values

  -> .gcd(a, b)
    x = a < 0 ? 0 - a : a
    y = b < 0 ? 0 - b : b
    while y != 0
      t = x % y
      x = y
      y = t
    x

  -> .pow_mod(base, exp, mod)
    return 0 if mod == 1
    res = 1
    b = ((base % mod) + mod) % mod
    e = exp
    while e > 0
      res = (res * b) % mod if e % 2 == 1
      b = (b * b) % mod
      e = e / 2
    res

  -> .prime_factors(n)
    out = []
    m = n
    d = 2
    while d * d <= m
      if m % d == 0
        out.push(d)
        while m % d == 0
          m = m / d
      d += 1
    out.push(m) if m > 1
    out

  -> .prime_power_factors(n)
    out = []
    m = n
    d = 2
    while d * d <= m
      if m % d == 0
        k = 0
        pk = 1
        while m % d == 0
          m = m / d
          k += 1
          pk = pk * d
        out.push([d, k, pk])
      d += 1
    out.push([m, 1, m]) if m > 1
    out

  # Primitive root modulo an odd prime power p^k.
  -> .primitive_root_odd_pp(p, pk)
    phi = (pk / p) * (p - 1)
    pf = DirichletCharacter.prime_factors(phi)
    g = 2
    while g < pk
      if DirichletCharacter.gcd(g, p) == 1
        ok = true
        pf.each -> (q)
          ok = false if DirichletCharacter.pow_mod(g, phi / q, pk) == 1
        return g if ok
      g += 1
    raise "no primitive root found for odd prime power"

  -> .cis_frac(num, den)
    two_pi = ~6.28318530717958647693
    angle = two_pi * ((num % den) + ~0.0) / (den + ~0.0)
    Complex<f64>.cis(angle)

  # Direct constructor taking modulus N >= 1 and array of N Complex<f64> values.
  -> new(@modulus, @values)
    raise "DirichletCharacter modulus must be >= 1" if @modulus < 1
    raise "DirichletCharacter values length must equal modulus" if @values.size != @modulus

  -> .trivial(modulus)
    vals = []
    a = 0
    while a < modulus
      if DirichletCharacter.gcd(a, modulus) == 1
        vals.push(Complex<f64>.one)
      else
        vals.push(Complex<f64>.zero)
      a += 1
    DirichletCharacter.new(modulus, vals)

  -> .quadratic_mod4
    DirichletCharacter.new(4, [
      Complex<f64>.zero,
      Complex<f64>.one,
      Complex<f64>.zero,
      Complex<f64>.real(~0.0 - ~1.0)
    ])

  -> .quadratic_mod3
    DirichletCharacter.new(3, [
      Complex<f64>.zero,
      Complex<f64>.one,
      Complex<f64>.real(~0.0 - ~1.0)
    ])

  # Legendre symbol character mod an odd prime p.
  -> .legendre(p)
    raise "DirichletCharacter.legendre requires an odd prime" if p < 3 || p % 2 == 0
    vals = []
    a = 0
    while a < p
      if a == 0
        vals.push(Complex<f64>.zero)
      else
        r = DirichletCharacter.pow_mod(a, (p - 1) / 2, p)
        if r == 1
          vals.push(Complex<f64>.one)
        else
          vals.push(Complex<f64>.real(~0.0 - ~1.0))
      a += 1
    DirichletCharacter.new(p, vals)

  # Enumerate all characters modulo a prime power p^k.
  -> .all_prime_power(p, k, pk)
    if p == 2
      if k == 1
        return [DirichletCharacter.trivial(2)]
      if k == 2
        return [DirichletCharacter.trivial(4), DirichletCharacter.quadratic_mod4]
      # (Z/2^k Z)^* = <-1> x <5> of orders 2 and 2^(k-2)
      ord5 = pk / 4
      dlog_sign = Array.new(pk, -1)
      dlog_five = Array.new(pk, -1)
      s = 0
      while s < 2
        cur = s == 0 ? 1 : pk - 1
        j = 0
        while j < ord5
          dlog_sign[cur] = s
          dlog_five[cur] = j
          cur = (cur * 5) % pk
          j += 1
        s += 1
      chars = []
      es = 0
      while es < 2
        e5 = 0
        while e5 < ord5
          vals = []
          a = 0
          while a < pk
            if dlog_sign[a] < 0
              vals.push(Complex<f64>.zero)
            else
              z1 = DirichletCharacter.cis_frac(es * dlog_sign[a], 2)
              z2 = DirichletCharacter.cis_frac(e5 * dlog_five[a], ord5)
              vals.push(z1 * z2)
            a += 1
          chars.push(DirichletCharacter.new(pk, vals))
          e5 += 1
        es += 1
      return chars

    # Odd prime power: cyclic of order phi = p^(k-1)*(p-1)
    phi = (pk / p) * (p - 1)
    g = DirichletCharacter.primitive_root_odd_pp(p, pk)
    dlog = Array.new(pk, -1)
    cur = 1
    j = 0
    while j < phi
      dlog[cur] = j
      cur = (cur * g) % pk
      j += 1
    chars = []
    e = 0
    while e < phi
      vals = []
      a = 0
      while a < pk
        if dlog[a] < 0
          vals.push(Complex<f64>.zero)
        else
          vals.push(DirichletCharacter.cis_frac(e * dlog[a], phi))
        a += 1
      chars.push(DirichletCharacter.new(pk, vals))
      e += 1
    chars

  # Enumerate all phi(N) Dirichlet characters modulo N >= 1 via CRT.
  -> .all(modulus)
    raise "modulus must be >= 1" if modulus < 1
    return [DirichletCharacter.trivial(1)] if modulus == 1
    factors = DirichletCharacter.prime_power_factors(modulus)
    pp_lists = []
    factors.each -> (f)
      pp_lists.push(DirichletCharacter.all_prime_power(f[0], f[1], f[2]))
    # Cartesian product over prime-power factors
    combos = [[]]
    pp_lists.each -> (plist)
      next_combos = []
      combos.each -> (prefix)
        plist.each -> (ch)
          row = []
          prefix.each -> (x) row.push(x)
          row.push(ch)
          next_combos.push(row)
      combos = next_combos
    out = []
    combos.each -> (tuple)
      vals = []
      a = 0
      while a < modulus
        prod = Complex<f64>.one
        tuple.each -> (ch)
          prod = prod * ch.at(a)
        vals.push(prod)
        a += 1
      out.push(DirichletCharacter.new(modulus, vals))
    out

  -> at(n)
    r = ((n % @modulus) + @modulus) % @modulus
    @values[r]

  -> trivial?(tol = ~1.0e-9)
    a = 0
    while a < @modulus
      if DirichletCharacter.gcd(a, @modulus) == 1
        return false if (at(a) - Complex<f64>.one).abs > tol
      a += 1
    true

  -> real?(tol = ~1.0e-9)
    a = 0
    while a < @modulus
      return false if at(a).imag.abs > tol
      a += 1
    true

  -> even?(tol = ~1.0e-9)
    (at(-1) - Complex<f64>.one).abs <= tol

  -> odd?(tol = ~1.0e-9)
    !even?(tol)

  -> parity
    even? ? 0 : 1

  -> conjugate
    vals = []
    @values.each -> (v) vals.push(v.conjugate)
    DirichletCharacter.new(@modulus, vals)

  -> inverse
    conjugate

  -> mul(other)
    raise "character multiplication requires equal moduli" if @modulus != other.modulus
    vals = []
    a = 0
    while a < @modulus
      vals.push(@values[a] * other.values[a])
      a += 1
    DirichletCharacter.new(@modulus, vals)

  # Checks whether d | N is an inducing modulus for self.
  -> induced_by?(d, tol = ~1.0e-9)
    return false if d < 1 || @modulus % d != 0
    a = 1
    while a < @modulus
      if DirichletCharacter.gcd(a, @modulus) == 1 && (a - 1) % d == 0
        return false if (at(a) - Complex<f64>.one).abs > tol
      a += 1
    true

  -> conductor(tol = ~1.0e-9)
    d = 1
    while d <= @modulus
      if @modulus % d == 0 && induced_by?(d, tol)
        return d
      d += 1
    @modulus

  -> primitive?(tol = ~1.0e-9)
    conductor(tol) == @modulus

  -> primitive_character(tol = ~1.0e-9)
    q = conductor(tol)
    return self if q == @modulus
    vals = Array.new(q, Complex<f64>.zero)
    a = 0
    while a < q
      if DirichletCharacter.gcd(a, q) == 1
        # Lift a mod q to a coprime residue mod @modulus
        lift = a
        while lift < @modulus * q && DirichletCharacter.gcd(lift, @modulus) != 1
          lift += q
        vals[a] = at(lift)
      a += 1
    DirichletCharacter.new(q, vals)

  # Gauss sum tau(chi) = sum_{a=1}^{N} chi(a) * exp(2 pi i a / N)
  -> gauss_sum
    two_pi = ~6.28318530717958647693
    total = Complex<f64>.zero
    a = 0
    while a < @modulus
      v = @values[a]
      if v.abs2 > ~0.0
        angle = two_pi * (a + ~0.0) / (@modulus + ~0.0)
        total += v * Complex<f64>.cis(angle)
      a += 1
    total

  -> orthogonality_sum(other)
    raise "orthogonality_sum requires equal moduli" if @modulus != other.modulus
    total = Complex<f64>.zero
    a = 0
    while a < @modulus
      total += @values[a] * other.values[a].conjugate
      a += 1
    total


+ DirichletL
  # Bernoulli numbers B_{2k} for k = 1..6 (Euler-Maclaurin correction terms).
  -> .bern_even
    [
      ~1.0 / ~6.0,
      (~0.0 - ~1.0) / ~30.0,
      ~1.0 / ~42.0,
      (~0.0 - ~1.0) / ~30.0,
      ~5.0 / ~66.0,
      (~0.0 - ~691.0) / ~2730.0
    ]

  -> .cpow_real_base(base, s)
    return Complex<f64>.zero if base <= ~0.0
    s.scale(Math.log(base)).exp

  # Hurwitz zeta function zeta(s, a) for Re(a) > 0, s != 1 via Euler-Maclaurin.
  -> .hurwitz_zeta(s, a, n_terms = 28)
    af = a + ~0.0
    neg_s = Complex<f64>.zero - s
    sum = Complex<f64>.zero
    k = 0
    while k < n_terms
      sum += DirichletL.cpow_real_base(af + (k + ~0.0), neg_s)
      k += 1
    x = af + (n_terms + ~0.0)
    one = Complex<f64>.one
    x_neg_s = DirichletL.cpow_real_base(x, neg_s)
    # Integral term x^(1 - s) / (s - 1) + (1/2) x^(-s)
    integral_term = DirichletL.cpow_real_base(x, one - s) / (s - one)
    total = sum + integral_term + x_neg_s.scale(~0.5)
    # Bernoulli tail: sum_{m=1}^{6} (B_{2m} / (2m)!) * s(s+1)...(s+2m-2) * x^(-s - 2m + 1)
    inv_x2 = ~1.0 / (x * x)
    poch = s
    fact = ~2.0
    x_pow = x_neg_s.scale(~1.0 / x)
    bern = DirichletL.bern_even
    m = 1
    while m <= 6
      b2m = bern[m - 1]
      total += poch * x_pow.scale(b2m / fact)
      if m < 6
        s1 = s + Complex<f64>.real((2 * m - 1) + ~0.0)
        s2 = s + Complex<f64>.real((2 * m) + ~0.0)
        poch = poch * s1 * s2
        fact = fact * ((2 * m + 1) + ~0.0) * ((2 * m + 2) + ~0.0)
        x_pow = x_pow.scale(inv_x2)
      m += 1
    total

  -> .riemann_zeta(s, n_terms = 28)
    DirichletL.hurwitz_zeta(s, ~1.0, n_terms)

  # Pole-regularized Hurwitz zeta: replaces x^(1-s)/(s-1) by (x^(1-s) - 1)/(s-1),
  # whose limit at s = 1 is -log(x). For non-principal chi (sum chi(a) = 0),
  # the subtracted constant 1/(s-1) cancels identically, making L(chi, 1) exact.
  -> .hurwitz_zeta_reg(s, a, n_terms = 28)
    af = a + ~0.0
    neg_s = Complex<f64>.zero - s
    sum = Complex<f64>.zero
    k = 0
    while k < n_terms
      sum += DirichletL.cpow_real_base(af + (k + ~0.0), neg_s)
      k += 1
    x = af + (n_terms + ~0.0)
    one = Complex<f64>.one
    x_neg_s = DirichletL.cpow_real_base(x, neg_s)
    diff = s - one
    integral_term = diff.abs < ~1.0e-12 ? Complex<f64>.real(~0.0 - Math.log(x)) : (DirichletL.cpow_real_base(x, one - s) - one) / diff
    total = sum + integral_term + x_neg_s.scale(~0.5)
    inv_x2 = ~1.0 / (x * x)
    poch = s
    fact = ~2.0
    x_pow = x_neg_s.scale(~1.0 / x)
    bern = DirichletL.bern_even
    m = 1
    while m <= 6
      b2m = bern[m - 1]
      total += poch * x_pow.scale(b2m / fact)
      if m < 6
        s1 = s + Complex<f64>.real((2 * m - 1) + ~0.0)
        s2 = s + Complex<f64>.real((2 * m) + ~0.0)
        poch = poch * s1 * s2
        fact = fact * ((2 * m + 1) + ~0.0) * ((2 * m + 2) + ~0.0)
        x_pow = x_pow.scale(inv_x2)
      m += 1
    total

  # L(chi, s) = q^(-s) * sum_{a=1}^{q} chi(a) * zeta(s, a / q)
  -> .l_function(chi, s, n_terms = 28)
    q = chi.modulus
    qf = q + ~0.0
    return DirichletL.riemann_zeta(s, n_terms) if q == 1
    non_triv = !chi.trivial?
    sum = Complex<f64>.zero
    a = 1
    while a <= q
      v = chi.at(a)
      if v.abs2 > ~0.0
        hz = non_triv ? DirichletL.hurwitz_zeta_reg(s, (a + ~0.0) / qf, n_terms) : DirichletL.hurwitz_zeta(s, (a + ~0.0) / qf, n_terms)
        sum += v * hz
      a += 1
    DirichletL.cpow_real_base(qf, Complex<f64>.zero - s) * sum

  # Lanczos complex Gamma(z) working identically in both interpreter and native engines.
  -> .complex_log_gamma(z)
    one = Complex<f64>.one
    pi = ~3.14159265358979323846
    if z.real < ~0.5
      reflected = DirichletL.complex_log_gamma(one - z)
      sine = z.scale(pi).sin
      return Complex<f64>.real(Math.log(pi)) - sine.log - reflected
    coeffs = [
      ~0.99999999999980993,
      ~676.5203681218851,
      ~0.0 - ~1259.1392167224028,
      ~771.32342877765313,
      ~0.0 - ~176.61502916214059,
      ~12.507343278686905,
      ~0.0 - ~0.13857109526572012,
      ~9.9843695780195716e-6,
      ~1.5056327351493116e-7
    ]
    shifted = z - one
    series = Complex<f64>.real(coeffs[0])
    i = 1
    while i < coeffs.size
      series += Complex<f64>.real(coeffs[i]) / (shifted + Complex<f64>.real(i + ~0.0))
      i += 1
    t = shifted + Complex<f64>.real(~7.5)
    Complex<f64>.real(~0.91893853320467274178) + (shifted + Complex<f64>.real(~0.5)) * t.log - t + series.log

  -> .complex_gamma(z)
    DirichletL.complex_log_gamma(z).exp

  # Gamma factor pi^(-(s + a)/2) * Gamma((s + a)/2) where a in {0, 1} is parity of chi.
  -> .gamma_factor(chi, s)
    pi = ~3.14159265358979323846
    a = chi.parity
    arg = (s + Complex<f64>.real(a + ~0.0)).scale(~0.5)
    DirichletL.cpow_real_base(pi, Complex<f64>.zero - arg) * DirichletL.complex_gamma(arg)

  # Completed L-function Lambda(chi, s) = q^((s + a)/2) * gamma_factor(chi, s) * L(chi, s).
  -> .completed_l(chi, s, n_terms = 28)
    q = chi.modulus + ~0.0
    a = chi.parity
    arg = (s + Complex<f64>.real(a + ~0.0)).scale(~0.5)
    DirichletL.cpow_real_base(q, arg) * DirichletL.gamma_factor(chi, s) * DirichletL.l_function(chi, s, n_terms)

  # Root number eps(chi) = tau(chi) / (i^a * sqrt(q)) for a primitive character chi.
  -> .root_number(chi)
    tau = chi.gauss_sum
    denom = Math.sqrt(chi.modulus + ~0.0)
    if chi.even?
      return tau.scale(~1.0 / denom)
    tau / Complex<f64>.i.scale(denom)


# CM types on (Z/lZ)^* for an odd prime l >= 3 (mirrors `Formalism/StatementCM.lean`).
+ CMType
  ro :prime, :elements

  -> new(@prime, elems)
    raise "CMType requires odd prime l >= 3" if @prime < 3 || @prime % 2 == 0
    @set = {}
    @elements = []
    elems.each -> (e)
      r = ((e % @prime) + @prime) % @prime
      if r != 0 && !@set.has_key?(r)
        @set[r] = true
        @elements.push(r)
    @elements = @elements.sort

  -> contains?(g)
    r = ((g % @prime) + @prime) % @prime
    @set.has_key?(r)

  -> neg(g)
    r = ((g % @prime) + @prime) % @prime
    r == 0 ? 0 : @prime - r

  -> has_one?
    contains?(1)

  # IsCMType: for every unit g in (Z/lZ)^*, g in Phi iff -g not in Phi.
  -> valid?
    g = 1
    while g < @prime
      return false if contains?(g) == contains?(neg(g))
      g += 1
    true

  # dualType Phi = insert 1 ((Phi.erase 1).image (-g))
  -> dual
    out = [1]
    @elements.each -> (g)
      if g != 1
        out.push(neg(g))
    CMType.new(@prime, out)

  # counts Phi sigma : sigma not in Phi && sigma != -1
  -> counts?(sigma)
    r = ((sigma % @prime) + @prime) % @prime
    r != 0 && !contains?(r) && r != @prime - 1

  # All 2^((l-3)/2) CM types on (Z/lZ)^* containing 1.
  -> .all_with_one(l)
    raise "CMType.all_with_one requires odd prime l >= 3" if l < 3 || l % 2 == 0
    half = (l - 1) / 2
    pairs = []
    g = 2
    while g <= half
      pairs.push([g, l - g])
      g += 1
    n_pairs = pairs.size
    total = 1
    i = 0
    while i < n_pairs
      total = total * 2
      i += 1
    out = []
    mask = 0
    while mask < total
      elems = [1]
      bit = 0
      while bit < n_pairs
        pick = ((mask >> bit) & 1) == 0 ? pairs[bit][0] : pairs[bit][1]
        elems.push(pick)
        bit += 1
      out.push(CMType.new(l, elems))
      mask += 1
    out
