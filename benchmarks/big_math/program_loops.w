# Program-level bignum loops — the Tungsten half of the E3 benchmark.
#
# The 21-op matrix times one operation against one mpz_* call, but idiomatic
# GMP reuses its destination across a loop while immutable Tungsten values
# allocate every pass: `big += small` is O(n) here and amortized O(1) there.
# You can win every matrix cell and still lose the real loop — these are the
# real loops. The C twin (program_loops_gmp.c) computes identical values
# with mpz destination reuse; the runner cross-checks the checksums.
#
# Output: <workload>\t<n>\t<ns_per_iter>\t<checksum>

-> bench_accumulate(n)
  r = 1 << 4096
  i = 0 ## i64
  t0 = clock()
  while i < n
    r = r + i
    i = i + 1
  t1 = clock()
  c = r % 1000000007
  << "accumulate\t" + n.to_s() + "\t" + ((t1 - t0) * ~1000000000.0 / n.to_f()).to_s() + "\t" + c.to_s()

-> bench_mulchain(n)
  # `## big`: an untyped accumulator would be raw-slot promoted and wrap at
  # i64 (factorial saturates 2-adically to 0 in 64 bits) — the documented
  # compiled tradeoff. The hint keeps the chain boxed and promoting.
  r = 1 ## big
  i = 2 ## i64
  t0 = clock()
  while i <= n
    r = r * i
    i = i + 1
  t1 = clock()
  c = r % 1000000007
  << "mulchain\t" + n.to_s() + "\t" + ((t1 - t0) * ~1000000000.0 / n.to_f()).to_s() + "\t" + c.to_s()

-> bench_addchain(n)
  # Same ## big rationale as mulchain: fib exceeds i64 by n=93.
  a = 0 ## big
  b = 1 ## big
  i = 0 ## i64
  t0 = clock()
  while i < n
    t = a + b
    a = b
    b = t
    i = i + 1
  t1 = clock()
  c = b % 1000000007
  << "addchain\t" + n.to_s() + "\t" + ((t1 - t0) * ~1000000000.0 / n.to_f()).to_s() + "\t" + c.to_s()

-> bench_subchain(n)
  # Keep a wide positive accumulator while subtracting changing inline words.
  r = 1 << 65536 ## big
  i = 0 ## i64
  probe = 0 ## i64
  t0 = clock()
  while i < n
    r = r - i
    # This value-dependent read prevents sum-chunk folding, isolating the
    # ordinary w_bigint_sub_mut destination path.
    probe = r & 1
    i = i + 1
  t1 = clock()
  c = (r % 1000000007) + probe
  << "subchain\t" + n.to_s() + "\t" + ((t1 - t0) * ~1000000000.0 / n.to_f()).to_s() + "\t" + c.to_s()

-> bench_divchain(n)
  # The start width keeps the positive accumulator boxed across the timed
  # interval while `/ 3` steadily exercises division by an inline word.
  r = 1 << 65536 ## big
  i = 0 ## i64
  t0 = clock()
  while i < n
    r = r / 3
    i = i + 1
  t1 = clock()
  c = r % 1000000007
  << "divchain\t" + n.to_s() + "\t" + ((t1 - t0) * ~1000000000.0 / n.to_f()).to_s() + "\t" + c.to_s()

-> bench_modchain(n, limbs)
  # A literal receiver seed keeps the fail-closed uniqueness proof valid;
  # after the first negligible pass, bump determines the measured width.
  r = (1 << 8191) + 123456789 ## big
  bits = limbs * 64 - 1
  bump = (1 << bits) + 987654321
  divisor = (1 << 63) + 29
  i = 0 ## i64
  t0 = clock()
  while i < n
    r += bump
    r %= divisor
    i += 1
  t1 = clock()
  c = r % 1000000007
  << "modchain" + limbs.to_s() + "\t" + n.to_s() + "\t" + ((t1 - t0) * ~1000000000.0 / n.to_f()).to_s() + "\t" + c.to_s()

-> bench_sqrchain(n, limbs)
  # `%=` leaves a one-limb value in the proven-dead wide receiver. Its spare
  # capacity lets the existing N×1 mut entry consume `r *= r` as a square.
  r = (1 << 8191) + 123456789 ## big
  bits = limbs * 64 - 1
  bump = (1 << bits) + 987654321
  divisor = (1 << 63) + 29
  i = 0 ## i64
  t0 = clock()
  while i < n
    r += bump
    r %= divisor
    r *= r
    i += 1
  t1 = clock()
  c = r % 1000000007
  << "sqrchain" + limbs.to_s() + "\t" + n.to_s() + "\t" + ((t1 - t0) * ~1000000000.0 / n.to_f()).to_s() + "\t" + c.to_s()

# -- word-overwrite lanes (E4 stage 3): `r = a op w` with a retained base.
# GMP's twin writes into a retained destination (mpz_*_ui); the compiled
# word-dest entries reuse the dying previous result the same way. The
# limbs argument sets the base width (the mul1@2/4/32 parity cells).

-> bench_wordadd(n, limbs)
  a = ((1 << (limbs * 64 - 8)) + 987654321) ## big
  r = 0 ## big
  i = 0 ## i64
  t0 = clock()
  while i < n
    r = a + 5
    i = i + 1
  t1 = clock()
  c = r % 1000000007
  << "wordadd" + limbs.to_s() + "\t" + n.to_s() + "\t" + ((t1 - t0) * ~1000000000.0 / n.to_f()).to_s() + "\t" + c.to_s()

-> bench_wordsub(n, limbs)
  a = ((1 << (limbs * 64 - 8)) + 987654321) ## big
  r = 0 ## big
  i = 0 ## i64
  t0 = clock()
  while i < n
    r = a - 7
    i = i + 1
  t1 = clock()
  c = r % 1000000007
  << "wordsub" + limbs.to_s() + "\t" + n.to_s() + "\t" + ((t1 - t0) * ~1000000000.0 / n.to_f()).to_s() + "\t" + c.to_s()

-> bench_wordmul(n, limbs)
  a = ((1 << (limbs * 64 - 8)) + 987654321) ## big
  r = 0 ## big
  i = 0 ## i64
  t0 = clock()
  while i < n
    r = a * 3
    i = i + 1
  t1 = clock()
  c = r % 1000000007
  << "wordmul" + limbs.to_s() + "\t" + n.to_s() + "\t" + ((t1 - t0) * ~1000000000.0 / n.to_f()).to_s() + "\t" + c.to_s()

-> bench_wordchain(n, limbs)
  # both vars are dest candidates: the two buffers hand back and forth
  # with no allocation in the steady state, GMP's retained r/a pair.
  # a is overwritten INSIDE the loop, so candidacy needs the literal seed
  # (the width expression reads a parameter and cannot seed); the computed
  # base then flows in through an admitted arithmetic overwrite, whose
  # identity return arrives shared-marked and self-heals on pass one.
  base = (1 << (limbs * 64 - 8)) + 987654321
  a = 0 ## big
  a = base + 0
  r = 0 ## big
  i = 0 ## i64
  t0 = clock()
  while i < n
    r = a + 5
    a = r - 7
    i = i + 1
  t1 = clock()
  c = (a + r) % 1000000007
  << "wordchain" + limbs.to_s() + "\t" + n.to_s() + "\t" + ((t1 - t0) * ~1000000000.0 / n.to_f()).to_s() + "\t" + c.to_s()

# -- pow2 strength-reduction lanes: `x / (1 << k)` and `x % (1 << k)` with a
# literal exponent lower to w_bigint_div_pow2 / w_bigint_mod_pow2 (truncated
# magnitude shift / low-limb truncation) instead of materializing the
# divisor and running general division. GMP twins: mpz_tdiv_q_2exp /
# mpz_tdiv_r_2exp into a retained destination. limbs must exceed 32 so the
# 2048-bit literal shift stays interior. TUNGSTEN_BIGINT_DIV_POW2=0 /
# TUNGSTEN_BIGINT_MOD_POW2=0 rebuilds measure the old generic-divide path.

-> bench_divp2chain(n, limbs)
  bits = limbs * 64 - 1
  x = ((1 << bits) + 987654321) ## big
  q = 0 ## big
  i = 0 ## i64
  t0 = clock()
  while i < n
    q = x / (1 << 2048)
    i += 1
  t1 = clock()
  c = q % 1000000007
  << "divp2chain" + limbs.to_s() + "\t" + n.to_s() + "\t" + ((t1 - t0) * ~1000000000.0 / n.to_f()).to_s() + "\t" + c.to_s()

-> bench_modp2chain(n, limbs)
  bits = limbs * 64 - 1
  x = ((1 << bits) + 987654321) ## big
  q = 0 ## big
  i = 0 ## i64
  t0 = clock()
  while i < n
    q = x % (1 << 2048)
    i += 1
  t1 = clock()
  c = q % 1000000007
  << "modp2chain" + limbs.to_s() + "\t" + n.to_s() + "\t" + ((t1 - t0) * ~1000000000.0 / n.to_f()).to_s() + "\t" + c.to_s()

# -- zero/sign-compare lane: statically-BigInt `x > 0` / `x < 0` / `x == 0`
# compile to the O(1) header-sign helpers (__w_*0_big_fast). The per-pass
# negate is the O(1) overlay flip, so the whole body should be width-flat;
# the GMP twin answers the same tests with mpz_sgn on an in-place-negated
# operand. TUNGSTEN_BIGINT_CMP0=0 rebuilds measure the generic-compare path.

-> bench_sgnchain(n, limbs)
  bits = limbs * 64 - 1
  x = ((1 << bits) + 987654321) ## big
  acc = 0 ## i64
  i = 0 ## i64
  t0 = clock()
  while i < n
    if x > 0
      acc += 1
    if x < 0
      acc += 2
    if x == 0
      acc += 4
    x = -x ## big
    i += 1
  t1 = clock()
  << "sgnchain" + limbs.to_s() + "\t" + n.to_s() + "\t" + ((t1 - t0) * ~1000000000.0 / n.to_f()).to_s() + "\t" + (acc % 1000000007).to_s()

# -- fused multiply-accumulate lane: `r += a * b` with MULTI-LIMB factors
# routes through w_bigint_addmul_mut into the multi-limb leg — product in
# retained scratch folded into the proven-dead receiver, no boxed product
# per pass. GMP twin: mpz_addmul. The literal 6000-bit seed keeps the
# uniqueness proof valid and leaves pool headroom (94 limbs in a 128-limb
# bucket) over every swept factor width. Same-binary A/B:
# TUNGSTEN_BIGINT_ADDMUL_ANY=0 restores the boxed-product fallback,
# TUNGSTEN_BIGINT_ADDMUL_ROWS=1 accumulates addmul_1 rows directly.

-> bench_addmulchain(n, limbs)
  fbits = limbs * 32 - 5
  a = ((1 << fbits) + 111111111) ## big
  b = ((1 << fbits) + 222222222) ## big
  r = ((1 << 6000) + 3) ## big
  i = 0 ## i64
  t0 = clock()
  while i < n
    r += a * b
    i += 1
  t1 = clock()
  c = r % 1000000007
  << "addmulchain" + limbs.to_s() + "\t" + n.to_s() + "\t" + ((t1 - t0) * ~1000000000.0 / n.to_f()).to_s() + "\t" + c.to_s()

args = argv()
workload = args.size() > 0 ? args[0] : "all"
n = args.size() > 1 ? args[1].to_i() : 0
limbs = args.size() > 2 ? args[2].to_i() : 65

if workload == "accumulate" || workload == "all"
  bench_accumulate(n > 0 ? n : 2000000)
if workload == "mulchain" || workload == "all"
  bench_mulchain(n > 0 ? n : 50000)
if workload == "addchain" || workload == "all"
  bench_addchain(n > 0 ? n : 300000)
if workload == "subchain" || workload == "all"
  bench_subchain(n > 0 ? n : 100000)
if workload == "divchain" || workload == "all"
  bench_divchain(n > 0 ? n : 30000)
if workload == "modchain" || workload == "all"
  bench_modchain(n > 0 ? n : 2000000, limbs)
if workload == "sqrchain" || workload == "all"
  bench_sqrchain(n > 0 ? n : 2000000, limbs)
if workload == "wordadd" || workload == "all"
  bench_wordadd(n > 0 ? n : 2000000, limbs)
if workload == "wordsub" || workload == "all"
  bench_wordsub(n > 0 ? n : 2000000, limbs)
if workload == "wordmul" || workload == "all"
  bench_wordmul(n > 0 ? n : 2000000, limbs)
if workload == "wordchain" || workload == "all"
  bench_wordchain(n > 0 ? n : 2000000, limbs)
if workload == "divp2chain" || workload == "all"
  bench_divp2chain(n > 0 ? n : 20000, limbs)
if workload == "modp2chain" || workload == "all"
  bench_modp2chain(n > 0 ? n : 200000, limbs)
if workload == "sgnchain" || workload == "all"
  bench_sgnchain(n > 0 ? n : 2000000, limbs)
if workload == "addmulchain" || workload == "all"
  bench_addmulchain(n > 0 ? n : 200000, limbs)
