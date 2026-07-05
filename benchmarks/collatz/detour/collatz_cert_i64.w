# Fast i64 descent certificate with an explicit overflow guard.
# True Collatz trajectory peaks for n < ~10^13 stay around 10^16, far below the
# i64 ceiling 2^63 = 9.22e18 -- so unboxed i64 arithmetic is exact AND ~13x faster
# than auto-bignum (which promotes at 2^48).  The guard makes it SOUND: if any n
# ever exceeds 3e18 (so 3n+1 could approach 2^63), it flags overflow instead of
# silently wrapping, and that range must be redone with collatz_cert.w (bignum).
# argv: [0]=hi (bound B), [1]=lo (slice start, for parallel fleets).

av = argv()
bcap = 1000000000 ## i64
lo = 3 ## i64
if av.size() > 0
  bcap = av[0].to_i() ## i64
if av.size() > 1
  lo = av[1].to_i() ## i64
if lo < 3
  lo = 3
if (lo % 2) == 0
  lo = lo + 1

guard = 3000000000000000000 ## i64
overflowed = 0 ## i64
worst_m = 0 ## i64
worst_steps = 0 ## i64
m = lo ## i64
while m <= bcap
  n = m ## i64
  steps = 0 ## i64
  while n >= m
    if (n % 2) == 0
      n = n / 2
    else
      if n > guard
        overflowed = 1
      n = 3 * n + 1
    steps = steps + 1
  if steps > worst_steps
    worst_steps = steps
    worst_m = m
  m = m + 2

if overflowed == 0
  << "certified (i64, guard clean) all odd n from lo=" + lo.to_s() + " to hi=" + bcap.to_s() + " descend"
else
  << "OVERFLOW FLAG SET: i64 insufficient here; rerun this range with collatz_cert.w (bignum)"
<< "worst stopping time: m=" + worst_m.to_s() + " took " + worst_steps.to_s() + " steps"
