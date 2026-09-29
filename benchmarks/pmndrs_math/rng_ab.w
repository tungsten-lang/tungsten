# StatsRng A/B — does a machine-typed mulberry32 (pmndrs/math
# src/random/mulberry32.ts: Math.imul = 32-bit wrapping multiply) or a 64-bit
# generator (xorshift64*, splitmix64) beat core/stats.w's current StatsRng?
#
#   bin/tungsten --release -o <scratch>/bin/rng_ab benchmarks/pmndrs_math/rng_ab.w
#   benchmarks/pmndrs_math/ab.py <scratch>/bin/rng_ab 1000000 5 base_u32 m32_u32 xs64_u32 sm64_u32
#
# Variants are <generator>_<stream>:
#   generator  core  StatsRng itself (u32 and f streams only)
#              base  RngBase < StatsRng, no overrides (today's core bodies)
#              copy  RngCopy < StatsRng, today's bodies copied verbatim
#              m32   mulberry32, same sequence, locals typed ## i64;
#                    random/next_int call next_u32
#              m32x  as m32, but random/next_int inline the mulberry step
#                    (one dispatch per number instead of two)
#              m32c  as m32, the output mix in a class method shared by
#                    next_u32/random/next_int
#              xs64  xorshift64*, state in an i64[1] cell (new sequence)
#              sm64  splitmix64, state in an i64[1] cell (new sequence)
#              xs64b xorshift64*, 64-bit state in the boxed @state ivar
#   stream     u32   sum of next_u32
#              f     sum of random (U[0,1))
#              i     sum of next_int(1000)
#              ib    sum of next_int(3000000000) (n > 2^31 probe)
#   check            prints outputs to diff against an independent reference
#
# Results 2026-09-25 (M5, --release, ab.py 2M iters x 7, medians; instr/op):
#   u32  core 2016  copy 2015  base 2016 | m32 111  m32c 110  xs64 100  sm64 111
#   f    core 2306                       | m32 198  m32c 111  m32x 112  xs64 102
#   i    copy 2126                       | m32 239  m32c 157  m32x 140
#   Controls: peak 2049 MB (core next_u32 promotes its products to BigInt and
#   leaks ~1 KB per number); every m32/xs64/sm64 variant: 2.1 MB, ~30x wall.
#   All outputs matched an independent Python/C mulberry32 / xorshift64* /
#   splitmix64 / Lemire reference.
#
# StatsRng has no next_int today, so RngBase#next_int is the one-liner a
# caller writes against the current API, `next_u32 % n` (modulo-biased); the
# candidates use Lemire's multiply-shift with rejection (unbiased). Without
# the rejection loop, (u32 * n) >> 32 is exactly pmndrs random.int's
# floor(random() * n) for n < 2^21.
#
# StatsRng is not in core/tungsten.w's autoload table (only :Stats is), so a
# program that names StatsRng without touching Stats fails to link
# ("use of undefined value '@class.StatsRng'"). `Stats.rng` below pulls
# core/stats.w in.

+ RngBase < StatsRng
  -> next_int(n)
    next_u32 % n

# Control with today's core bodies copied verbatim (so control and candidate
# differ only in body, never in inherited-vs-own dispatch).
+ RngCopy < StatsRng
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

  -> next_int(n)
    next_u32 % n

+ RngM32 < StatsRng
  -> next_u32
    s = @state ## i64
    s = (s + 0x6D2B79F5) & 0xFFFFFFFF ## i64
    @state = s
    t = ((s ^ (s >> 15)) * (s | 1)) & 0xFFFFFFFF ## i64
    t = (t ^ (t + (((t ^ (t >> 7)) * (t | 61)) & 0xFFFFFFFF))) & 0xFFFFFFFF ## i64
    (t ^ (t >> 14)) ## i64

  -> random
    (next_u32 ## i64) * ~2.3283064365386963e-10

  # Lemire: floor(u * n / 2^32), rejecting the low window that would bias it.
  # n in [1, 2^32].
  -> next_int(n)
    bound = n ## u64
    m = (next_u32 ## u64) * bound ## u64
    low = m & 0xFFFFFFFF ## u64
    if low < bound
      floor = (4294967296 - bound) % bound ## u64
      while low < floor
        m = (next_u32 ## u64) * bound ## u64
        low = m & 0xFFFFFFFF ## u64
    (m >> 32) ## u64

+ RngM32x < StatsRng
  -> next_u32
    s = @state ## i64
    s = (s + 0x6D2B79F5) & 0xFFFFFFFF ## i64
    @state = s
    t = ((s ^ (s >> 15)) * (s | 1)) & 0xFFFFFFFF ## i64
    t = (t ^ (t + (((t ^ (t >> 7)) * (t | 61)) & 0xFFFFFFFF))) & 0xFFFFFFFF ## i64
    (t ^ (t >> 14)) ## i64

  -> random
    s = @state ## i64
    s = (s + 0x6D2B79F5) & 0xFFFFFFFF ## i64
    @state = s
    t = ((s ^ (s >> 15)) * (s | 1)) & 0xFFFFFFFF ## i64
    t = (t ^ (t + (((t ^ (t >> 7)) * (t | 61)) & 0xFFFFFFFF))) & 0xFFFFFFFF ## i64
    ((t ^ (t >> 14)) ## i64) * ~2.3283064365386963e-10

  -> next_int(n)
    bound = n ## u64
    m = 0 ## u64
    low = 0 ## u64
    floor = 0 ## u64
    first = true
    while first || low < floor
      s = @state ## i64
      s = (s + 0x6D2B79F5) & 0xFFFFFFFF ## i64
      @state = s
      t = ((s ^ (s >> 15)) * (s | 1)) & 0xFFFFFFFF ## i64
      t = (t ^ (t + (((t ^ (t >> 7)) * (t | 61)) & 0xFFFFFFFF))) & 0xFFFFFFFF ## i64
      m = ((t ^ (t >> 14)) ## u64) * bound ## u64
      low = m & 0xFFFFFFFF ## u64
      if first && low < bound
        floor = (4294967296 - bound) % bound ## u64
      first = false
    (m >> 32) ## u64

# m32 with the output mix factored into a class method, so random and
# next_int share it without a second instance dispatch.
+ RngM32c < StatsRng
  -> .mix32(s)
    t = s ## i64
    t = ((t ^ (t >> 15)) * (t | 1)) & 0xFFFFFFFF ## i64
    t = (t ^ (t + (((t ^ (t >> 7)) * (t | 61)) & 0xFFFFFFFF))) & 0xFFFFFFFF ## i64
    (t ^ (t >> 14)) ## i64

  -> next_u32
    s = ((@state ## i64) + 0x6D2B79F5) & 0xFFFFFFFF ## i64
    @state = s
    RngM32c.mix32(s)

  -> random
    s = ((@state ## i64) + 0x6D2B79F5) & 0xFFFFFFFF ## i64
    @state = s
    (RngM32c.mix32(s) ## i64) * ~2.3283064365386963e-10

  -> next_int(n)
    bound = n ## u64
    s = ((@state ## i64) + 0x6D2B79F5) & 0xFFFFFFFF ## i64
    @state = s
    m = (RngM32c.mix32(s) ## u64) * bound ## u64
    low = m & 0xFFFFFFFF ## u64
    if low < bound
      floor = (4294967296 - bound) % bound ## u64
      while low < floor
        s = ((@state ## i64) + 0x6D2B79F5) & 0xFFFFFFFF ## i64
        @state = s
        m = (RngM32c.mix32(s) ## u64) * bound ## u64
        low = m & 0xFFFFFFFF ## u64
    (m >> 32) ## u64

+ RngXs64 < StatsRng
  -> new(seed)
    @state = seed
    @state = 1 if @state == 0
    @cell = i64[1]
    @cell[0] = @state
    self

  -> next_u32
    x = @cell[0] ## u64
    x = x ^ (x >> 12) ## u64
    x = x ^ (x << 25) ## u64
    x = x ^ (x >> 27) ## u64
    @cell[0] = x
    ((x * (2685821657736338717 ## u64)) >> 32) ## u64

  # 53 random bits: [0, 1) on the full double grid.
  -> random
    x = @cell[0] ## u64
    x = x ^ (x >> 12) ## u64
    x = x ^ (x << 25) ## u64
    x = x ^ (x >> 27) ## u64
    @cell[0] = x
    (((x * (2685821657736338717 ## u64)) >> 11) ## u64) * ~1.1102230246251565e-16

  -> next_int(n)
    bound = n ## u64
    m = (next_u32 ## u64) * bound ## u64
    low = m & 0xFFFFFFFF ## u64
    if low < bound
      floor = (4294967296 - bound) % bound ## u64
      while low < floor
        m = (next_u32 ## u64) * bound ## u64
        low = m & 0xFFFFFFFF ## u64
    (m >> 32) ## u64

+ RngSm64 < StatsRng
  -> new(seed)
    @state = seed
    @cell = i64[1]
    @cell[0] = seed
    self

  -> next_u32
    z = (@cell[0] ## u64) + (0x9E3779B97F4A7C15 ## u64) ## u64
    @cell[0] = z
    z = (z ^ (z >> 30)) * (0xBF58476D1CE4E5B9 ## u64) ## u64
    z = (z ^ (z >> 27)) * (0x94D049BB133111EB ## u64) ## u64
    ((z ^ (z >> 31)) >> 32) ## u64

  -> random
    z = (@cell[0] ## u64) + (0x9E3779B97F4A7C15 ## u64) ## u64
    @cell[0] = z
    z = (z ^ (z >> 30)) * (0xBF58476D1CE4E5B9 ## u64) ## u64
    z = (z ^ (z >> 27)) * (0x94D049BB133111EB ## u64) ## u64
    (((z ^ (z >> 31)) >> 11) ## u64) * ~1.1102230246251565e-16

  -> next_int(n)
    bound = n ## u64
    m = (next_u32 ## u64) * bound ## u64
    low = m & 0xFFFFFFFF ## u64
    if low < bound
      floor = (4294967296 - bound) % bound ## u64
      while low < floor
        m = (next_u32 ## u64) * bound ## u64
        low = m & 0xFFFFFFFF ## u64
    (m >> 32) ## u64

+ RngXs64Boxed < StatsRng
  -> next_u32
    x = @state ## u64
    x = x ^ (x >> 12) ## u64
    x = x ^ (x << 25) ## u64
    x = x ^ (x >> 27) ## u64
    @state = x
    ((x * (2685821657736338717 ## u64)) >> 32) ## u64

# Drivers are typed so the shared loop overhead (compare, accumulate) stays
# raw; the per-number cost left is dispatch + the method body.
-> run_u32(r, n)
  s = 0 ## i64
  lim = n ## i64
  i = 0 ## i64
  while i < lim
    s = s + (r.next_u32 ## i64)
    i += 1
  s

-> run_f(r, n)
  s = ~0.0
  lim = n ## i64
  i = 0 ## i64
  while i < lim
    s = s + (r.random ## f64)
    i += 1
  s

-> run_i(r, n, m)
  s = 0 ## i64
  lim = n ## i64
  i = 0 ## i64
  while i < lim
    s = s + (r.next_int(m) ## i64)
    i += 1
  s

-> first(r, k)
  out = []
  i = 0
  while i < k
    out.push(r.next_u32)
    i += 1
  out

-> first_f(r, k)
  out = []
  i = 0
  while i < k
    out.push(r.random)
    i += 1
  out

-> first_i(r, k, m)
  out = []
  i = 0
  while i < k
    out.push(r.next_int(m))
    i += 1
  out

control = Stats.rng(1)
variant = ARGV[0] == nil ? "check" : ARGV[0]
iters = ARGV[1] == nil ? 1000 : ARGV[1].to_i

gen = variant.split("_")[0]
stream = variant.split("_").size > 1 ? variant.split("_")[1] : ""

base = RngBase.new(1)
copy = RngCopy.new(1)
core = StatsRng.new(1)
m32 = RngM32.new(1)
m32x = RngM32x.new(1)
m32c = RngM32c.new(1)
xs64 = RngXs64.new(1)
sm64 = RngSm64.new(1)
xs64b = RngXs64Boxed.new(1)

if variant == "check"
  << "base  seed1 " + first(RngBase.new(1), 5).to_s
  << "m32   seed1 " + first(RngM32.new(1), 5).to_s
  << "m32x  seed1 " + first(RngM32x.new(1), 5).to_s
  << "m32c  seed1 " + first(RngM32c.new(1), 5).to_s
  << "m32c  f seed42 " + first_f(RngM32c.new(42), 3).to_s
  << "m32c == base random x100000: " + (run_f(RngBase.new(9), 100000) == run_f(RngM32c.new(9), 100000)).to_s
  << "m32c int1000 1k " + run_i(RngM32c.new(3), 1000, 1000).to_s
  << "m32c int3e9 1k " + run_i(RngM32c.new(3), 1000, 3000000000).to_s
  << "copy  seed1 " + first(RngCopy.new(1), 5).to_s
  << "core  seed1 " + first(StatsRng.new(1), 5).to_s
  << "base  seed42 " + first(RngBase.new(42), 3).to_s
  << "m32   seed42 " + first(RngM32.new(42), 3).to_s
  << "m32   seed0 " + first(RngM32.new(0), 1).to_s
  # out-of-range seeds: negative, > 2^32, BigInt (> 2^64)
  odd_ok = true
  [-5, 1099511627779, 1180591620717411303433, 4294967296].each -> (sd)
    odd_ok = odd_ok && first(RngBase.new(sd), 3) == first(RngM32.new(sd), 3) && first(RngBase.new(sd), 3) == first(RngM32c.new(sd), 3) && first(RngBase.new(sd), 3) == first(RngM32x.new(sd), 3)
  << "odd seeds base == m32/m32c/m32x: " + odd_ok.to_s + " " + first(RngBase.new(-5), 2).to_s + " " + first(RngBase.new(1180591620717411303433), 2).to_s
  << "xs64  seed1 " + first(RngXs64.new(1), 3).to_s
  << "sm64  seed1 " + first(RngSm64.new(1), 3).to_s
  << "xs64b seed1 " + first(RngXs64Boxed.new(1), 3).to_s
  << "base  f seed42 " + first_f(RngBase.new(42), 3).to_s
  << "m32   f seed42 " + first_f(RngM32.new(42), 3).to_s
  << "m32x  f seed42 " + first_f(RngM32x.new(42), 3).to_s
  << "xs64  f seed1 " + first_f(RngXs64.new(1), 3).to_s
  << "sm64  f seed1 " + first_f(RngSm64.new(1), 3).to_s
  << "m32 == base random x100000: " + (run_f(RngBase.new(9), 100000) == run_f(RngM32.new(9), 100000)).to_s
  << "m32x == base random x100000: " + (run_f(RngBase.new(9), 100000) == run_f(RngM32x.new(9), 100000)).to_s
  << "base u32 1M " + run_u32(RngBase.new(1), 1000000).to_s
  << "m32  u32 1M " + run_u32(RngM32.new(1), 1000000).to_s
  << "m32x u32 1M " + run_u32(RngM32x.new(1), 1000000).to_s
  << "xs64 u32 1M " + run_u32(RngXs64.new(1), 1000000).to_s
  << "sm64 u32 1M " + run_u32(RngSm64.new(1), 1000000).to_s
  << "base int1000 1k " + run_i(RngBase.new(3), 1000, 1000).to_s
  << "m32  int1000 1k " + run_i(RngM32.new(3), 1000, 1000).to_s
  << "m32x int1000 1k " + run_i(RngM32x.new(3), 1000, 1000).to_s
  << "base int3e9 seed3 " + first_i(RngBase.new(3), 5, 3000000000).to_s
  << "m32  int3e9 seed3 " + first_i(RngM32.new(3), 5, 3000000000).to_s
  << "m32x int3e9 seed3 " + first_i(RngM32x.new(3), 5, 3000000000).to_s
  << "m32  int3e9 1k " + run_i(RngM32.new(3), 1000, 3000000000).to_s
  << "m32x int3e9 1k " + run_i(RngM32x.new(3), 1000, 3000000000).to_s
  << "m32  int7 1k " + run_i(RngM32.new(3), 1000, 7).to_s
  << "m32  int1 " + first_i(RngM32.new(3), 3, 1).to_s
  << "m32  int2^32 " + first_i(RngM32.new(1), 3, 4294967296).to_s
else
  r = base
  if gen == "copy"
    r = copy
  if gen == "core"
    r = core
  if gen == "m32"
    r = m32
  if gen == "m32x"
    r = m32x
  if gen == "m32c"
    r = m32c
  if gen == "xs64"
    r = xs64
  if gen == "sm64"
    r = sm64
  if gen == "xs64b"
    r = xs64b
  checksum = 0
  t0 = clock()
  if stream == "u32"
    checksum = run_u32(r, iters)
  if stream == "f"
    checksum = run_f(r, iters)
  if stream == "i"
    checksum = run_i(r, iters, 1000)
  if stream == "ib"
    checksum = run_i(r, iters, 3000000000)
  t1 = clock()
  ns = ~0.0
  ns = (t1 - t0) * ~1000000000.0 / iters if iters > 0
  << "ns/op: " + ns.to_s + " checksum: " + checksum.to_s
