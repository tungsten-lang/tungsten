# Bignum-safe descent certificate: every odd m in [3,B] reaches a value < m, so
# (by strong induction) every n <= B reaches 1 and no cycle has min element <= B.
# Plain Int (no ## i64) auto-promotes to bignum at the rare trajectory peaks, so
# B is no longer capped by the i64 ceiling.  Pass B as argv[0].
#   bin/tungsten -o cert collatz_cert.w && ./cert 10000000000

av = argv()
bcap = 1000000000
lo = 3
if av.size() > 0
  bcap = av[0].to_i()
if av.size() > 1
  lo = av[1].to_i()      # slice start (for parallel fleets); each m descends independently
if lo < 3
  lo = 3
if (lo % 2) == 0
  lo = lo + 1

worst_m = 0
worst_steps = 0
m = lo
while m <= bcap
  n = m
  steps = 0
  while n >= m
    if n % 2 == 0
      n = n / 2
    else
      n = 3 * n + 1
    steps = steps + 1
  if steps > worst_steps
    worst_steps = steps
    worst_m = m
  m = m + 2

<< "certified all odd n from lo=" + lo.to_s() + " to hi=" + bcap.to_s() + " descend below themselves"
<< "  => (full range) every n reaches 1; no cycle has min element <= B"
<< "longest descent (stopping time): m=" + worst_m.to_s() + " took " + worst_steps.to_s() + " steps"
