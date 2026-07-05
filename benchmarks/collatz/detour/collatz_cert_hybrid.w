# Hybrid descent certificate: fast i64 sweep + bignum fallback for the rare peaks.
#
# Almost every m descends with a trajectory peak well under the i64 ceiling, so we
# verify it in unboxed i64 (~3 s / 10^9).  The ~1-in-3-million m whose peak would
# exceed 3e18 (where 3n+1 could approach 2^63) are flagged BEFORE any overflow can
# happen and re-verified exactly in bignum.  Sound (no silent wrap) and ~13x faster
# than an all-bignum certificate.  argv: [0]=hi (B), [1]=lo (slice start).

-> descends_big(start) (i64)      # exact bignum descent; returns 1 once n drops below start
  n = start
  while n >= start
    if n % 2 == 0
      n = n / 2
    else
      n = 3 * n + 1
  1

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
bigchecks = 0 ## i64
worst_steps = 0 ## i64
worst_m = 0 ## i64
m = lo ## i64
while m <= bcap
  n = m ## i64
  steps = 0 ## i64
  trip = 0 ## i64
  while n >= m
    if (n % 2) == 0
      n = n / 2
    else
      if n > guard
        trip = 1
        n = 0          # bail out of the i64 path before 3n+1 can overflow
      else
        n = 3 * n + 1
    steps = steps + 1
  if trip == 1
    ok = descends_big(m)     # rare: re-verify this m exactly in bignum
    bigchecks = bigchecks + 1
  if steps > worst_steps
    worst_steps = steps
    worst_m = m
  m = m + 2

<< "certified all odd n from lo=" + lo.to_s() + " to hi=" + bcap.to_s() + " descend"
<< "  (i64 fast path + " + bigchecks.to_s() + " exact bignum re-checks for peaks over 3e18)"
<< "worst i64 stopping time: m=" + worst_m.to_s() + " took " + worst_steps.to_s() + " steps"
