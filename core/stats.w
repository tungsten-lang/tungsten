# Stats — distributions, descriptive stats, sampling.
#
# SciPy: scipy.stats · R: stats · Julia: Distributions.jl
# Lives at core/stats (not inside koala): koala is tabular ML/pandas;
# these are the primitive continuous/discrete distributions any sci code needs.
#
# RNG: mulberry32-style xorshift on a 32-bit state for reproducibility.
# Parallel-safe Philox is a follow-up for @gpu Monte Carlo.

use core/special

+ Stats
  # ---- descriptive (plain lists of Float) ----

  -> .mean(xs)
    n = xs.size()
    if n == 0
      return ~0.0
    s = ~0.0
    i = 0
    while i < n
      s = s + xs[i]
      i = i + 1
    s / (n + ~0.0)

  -> .variance(xs, sample = true)
    n = xs.size()
    if n < 2
      return ~0.0
    m = Stats.mean(xs)
    s = ~0.0
    i = 0
    while i < n
      d = xs[i] - m
      s = s + d * d
      i = i + 1
    denom = n + ~0.0
    if sample
      denom = n - ~1.0
    s / denom

  -> .std(xs, sample = true)
    Math.sqrt(Stats.variance(xs, sample))

  -> .median(xs)
    n = xs.size()
    if n == 0
      return ~0.0
    ys = []
    i = 0
    while i < n
      ys = ys.push(xs[i])
      i = i + 1
    # insertion sort
    i = 1
    while i < n
      key = ys[i]
      j = i - 1
      while j >= 0 && ys[j] > key
        ys[j + 1] = ys[j]
        j = j - 1
      ys[j + 1] = key
      i = i + 1
    if n % 2 == 1
      return ys[n / 2]
    (ys[n / 2 - 1] + ys[n / 2]) / ~2.0

  -> .percentile(xs, p)
    # p in [0,100]
    n = xs.size()
    if n == 0
      return ~0.0
    ys = []
    i = 0
    while i < n
      ys = ys.push(xs[i])
      i = i + 1
    i = 1
    while i < n
      key = ys[i]
      j = i - 1
      while j >= 0 && ys[j] > key
        ys[j + 1] = ys[j]
        j = j - 1
      ys[j + 1] = key
      i = i + 1
    if p <= ~0.0
      return ys[0]
    if p >= ~100.0
      return ys[n - 1]
    rank = (p / ~100.0) * (n - ~1.0)
    lo = Math.floor(rank)
    hi = Math.ceil(rank)
    loi = lo
    hii = hi
    if loi == hii
      return ys[loi]
    w = rank - lo
    ys[loi] * (~1.0 - w) + ys[hii] * w

  # ---- PRNG (mulberry32) ----

  -> .rng(seed = 1)
    StatsRng.new(seed)

  # ---- Normal(μ, σ) ----

  -> .norm_pdf(x, mu = ~0.0, sigma = ~1.0)
    z = (x - mu) / sigma
    Math.exp(~0.0 - ~0.5 * z * z) / (sigma * ~2.5066282746310005)

  -> .norm_cdf(x, mu = ~0.0, sigma = ~1.0)
    z = (x - mu) / (sigma * ~1.4142135623730951)
    ~0.5 * (~1.0 + Special.erf(z))

  # ---- Uniform ----

  -> .uniform_pdf(x, a = ~0.0, b = ~1.0)
    if x < a || x > b
      return ~0.0
    ~1.0 / (b - a)

  # ---- Exponential(λ) ----

  -> .expon_pdf(x, lam = ~1.0)
    if x < ~0.0
      return ~0.0
    lam * Math.exp(~0.0 - lam * x)

  -> .expon_cdf(x, lam = ~1.0)
    if x < ~0.0
      return ~0.0
    ~1.0 - Math.exp(~0.0 - lam * x)

  # ---- Poisson(λ) PMF ----

  -> .poisson_pmf(k, lam)
    if k < 0
      return ~0.0
    # e^{-λ} λ^k / k!
    p = Math.exp(~0.0 - lam)
    i = 1
    while i <= k
      p = p * lam / (i + ~0.0)
      i = i + 1
    p

  # ---- Student-t (ν) PDF ----

  -> .t_pdf(x, nu)
    c = Math.exp(Special.lgamma((nu + ~1.0) / ~2.0) - Special.lgamma(nu / ~2.0))
    c = c / Math.sqrt(nu * ~3.141592653589793)
    c * Math.pow(~1.0 + x * x / nu, ~0.0 - (nu + ~1.0) / ~2.0)

  # ---- Gamma(shape α, rate β) PDF ----

  -> .gamma_pdf(x, alpha, beta = ~1.0)
    if x < ~0.0
      return ~0.0
    Math.exp(alpha * Math.log(beta) + (alpha - ~1.0) * Math.log(x) - beta * x - Special.lgamma(alpha))

  # ---- Bernoulli / Binomial ----

  -> .bernoulli_pmf(k, p)
    if k == 0
      return ~1.0 - p
    if k == 1
      return p
    ~0.0

  -> .binom_pmf(k, n, p)
    if k < 0 || k > n
      return ~0.0
    # C(n,k) p^k (1-p)^{n-k}
    # compute in log space
    logc = Special.lgamma(n + ~1.0) - Special.lgamma(k + ~1.0) - Special.lgamma(n - k + ~1.0)
    Math.exp(logc + k * Math.log(p) + (n - k) * Math.log(~1.0 - p))

  # ---- correlation ----

  -> .pearson(xs, ys)
    n = xs.size()
    mx = Stats.mean(xs)
    my = Stats.mean(ys)
    num = ~0.0
    dx2 = ~0.0
    dy2 = ~0.0
    i = 0
    while i < n
      dx = xs[i] - mx
      dy = ys[i] - my
      num = num + dx * dy
      dx2 = dx2 + dx * dx
      dy2 = dy2 + dy * dy
      i = i + 1
    den = Math.sqrt(dx2 * dy2)
    if den == ~0.0
      return ~0.0
    num / den

+ StatsRng
  -> new(seed)
    @state = seed
    if @state == 0
      @state = 1
    self

  -> next_u32
    # mulberry32
    @state = (@state + 0x6D2B79F5) & 0xFFFFFFFF
    t = @state
    t = ((t ^ (t >> 15)) * (t | 1)) & 0xFFFFFFFF
    t = (t ^ (t + (((t ^ (t >> 7)) * (t | 61)) & 0xFFFFFFFF))) & 0xFFFFFFFF
    (t ^ (t >> 14)) & 0xFFFFFFFF

  -> random
    # U[0,1)
    next_u32 / ~4294967296.0

  -> uniform(a = ~0.0, b = ~1.0)
    a + (b - a) * random

  # Box–Muller
  -> normal(mu = ~0.0, sigma = ~1.0)
    u1 = random
    u2 = random
    if u1 < ~1.0e-12
      u1 = ~1.0e-12
    z = Math.sqrt(~0.0 - ~2.0 * Math.log(u1)) * Math.cos(~6.283185307179586 * u2)
    mu + sigma * z

  -> exponential(lam = ~1.0)
    u = random
    if u < ~1.0e-12
      u = ~1.0e-12
    ~0.0 - Math.log(u) / lam

  -> bernoulli(p = ~0.5)
    if random < p
      return 1
    0
