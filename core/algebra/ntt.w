# Exact dense univariate multiplication over prime fields via 3-prime NTT
# + CRT — the exact-arithmetic large-degree lane (a floating FFT cannot
# carry exact finite-field products without rounding proofs; the
# number-theoretic transform is exact by construction).
#
# The product's integer coefficients are bounded by (d+1)(p-1)^2 < 2^76 for
# p < 2^31 and any practical degree, so three NTT-friendly primes near 2^30
# (joint modulus ~2^90) recover them exactly through CRT, then one
# reduction mod p lands back in the field. Every transform runs in typed
# i64 code (values < 2^30, products < 2^60 — raw i64 throughout).

# Iterative in-place radix-2 NTT mod `m` over a power-of-two length `n`.
# `roots` holds the per-stage twiddle bases: roots[s] is a primitive
# (2^(s+1))-th root of unity mod m, for stages s = 0 .. log2(n)-1.
-> ntt_transform(a, n, m, roots) (i64[] i64 i64 i64[]) i64
  # bit-reversal permutation
  j = 0 ## i64
  i = 1 ## i64
  while i < n
    bit = n >> 1 ## i64
    while (j & bit) != 0
      j = j ^ bit
      bit = bit >> 1
    j = j | bit
    if i < j
      t = a[i] ## i64
      a[i] = a[j]
      a[j] = t
    i += 1
  len = 2 ## i64
  stage = 0 ## i64
  while len <= n
    wlen = roots[stage] ## i64
    half = len >> 1 ## i64
    base = 0 ## i64
    while base < n
      w = 1 ## i64
      k = 0 ## i64
      while k < half
        u = a[base + k] ## i64
        v = (a[base + k + half] * w) % m ## i64
        s = u + v ## i64
        s = s - m if s >= m
        d = u - v ## i64
        d = d + m if d < 0
        a[base + k] = s
        a[base + k + half] = d
        w = (w * wlen) % m
        k += 1
      base += len
    len = len << 1
    stage += 1
  0

# Pointwise product c[i] = a[i]*b[i] mod m, then nothing else — kept typed.
-> ntt_pointwise(a, b, n, m) (i64[] i64[] i64 i64) i64
  i = 0 ## i64
  while i < n
    a[i] = (a[i] * b[i]) % m
    i += 1
  0

# Scale by n^{-1} mod m after the inverse transform.
-> ntt_scale(a, n, m, ninv) (i64[] i64 i64 i64) i64
  i = 0 ## i64
  while i < n
    a[i] = (a[i] * ninv) % m
    i += 1
  0

+ NttMultiply
  # Three classic NTT primes sharing primitive root 3 (verified — a prime
  # without g=3 makes the transform silently non-invertible on symmetric
  # inputs): 119·2^23+1, 5·2^25+1, 7·2^26+1. Joint modulus ~2^86 covers
  # (d+1)(p-1)^2 for p < 2^31 up to degree ~2^24.
  -> .primes
    [998244353, 167772161, 469762049]

  -> .powmod(base, exp, m)
    result = 1
    b = base % m
    e = exp
    while e > 0
      result = (result * b) % m if e % 2 == 1
      b = (b * b) % m
      e = e / 2
    result

  # Per-stage twiddles for length n (power of two): stage s uses a
  # primitive 2^(s+1)-th root. `invert` selects the inverse transform.
  -> .stage_roots(m, n, invert)
    g = 3
    stages = 0
    len = 2
    while len <= n
      stages += 1
      len = len * 2
    out = i64[stages < 1 ? 1 : stages]
    s = 0
    len = 2
    while len <= n
      root = NttMultiply.powmod(g, (m - 1) / len, m)
      root = NttMultiply.powmod(root, m - 2, m) if invert
      out[s] = root
      s += 1
      len = len * 2
    out

  # Exact product of two coefficient arrays (integers in [0, p)) over
  # F_p, p < 2^31. Returns the dense product coefficients mod p.
  -> .multiply_mod_p(ca, cb, p)
    need = ca.size + cb.size - 1
    n = 1
    while n < need
      n = n * 2
    primes = NttMultiply.primes
    residues = []
    t = 0
    while t < primes.size
      m = primes[t]
      fa = i64[n]
      fb = i64[n]
      i = 0
      while i < ca.size
        fa[i] = ca[i] % m
        i += 1
      i = 0
      while i < cb.size
        fb[i] = cb[i] % m
        i += 1
      ntt_transform(fa, n, m, NttMultiply.stage_roots(m, n, false))
      ntt_transform(fb, n, m, NttMultiply.stage_roots(m, n, false))
      ntt_pointwise(fa, fb, n, m)
      ntt_transform(fa, n, m, NttMultiply.stage_roots(m, n, true))
      ntt_scale(fa, n, m, NttMultiply.powmod(n, m - 2, m))
      residues.push(fa)
      t += 1
    # CRT: x = r1 + m1*t1 + m1*m2*t2 with garner coefficients.
    m1 = primes[0]
    m2 = primes[1]
    m3 = primes[2]
    inv_m1_mod_m2 = NttMultiply.powmod(m1 % m2, m2 - 2, m2)
    m1m2 = m1 * m2
    inv_m1m2_mod_m3 = NttMultiply.powmod(m1m2 % m3, m3 - 2, m3)
    r1 = residues[0]
    r2 = residues[1]
    r3 = residues[2]
    out = []
    i = 0
    while i < need
      a1 = r1[i]
      t1 = ((r2[i] - a1 % m2 + m2) * inv_m1_mod_m2) % m2
      x12 = a1 + m1 * t1
      t2 = ((r3[i] - x12 % m3 + m3) * inv_m1m2_mod_m3) % m3
      x = x12 + m1m2 * t2
      out.push(x % p)
      i += 1
    out
