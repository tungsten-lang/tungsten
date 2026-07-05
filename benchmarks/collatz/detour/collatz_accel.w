# Part F: accelerate the descent certificate using the k-step merged-map table.
# Standard identity (the same bit-pattern structure as Part B/D):
#   write n = q*2^k + r.  Running Collatz until k halvings occur does a sequence
#   of operations determined ONLY by r, and yields
#         n  ->  3^a(r) * q + e(r)
#   where a(r) = #odd-steps and e(r) = value reached from r alone.
#   So one table lookup advances n by k halvings.  We precompute a(r), e(r) once.

pow3 = i64[40]
pow3[0] = 1
ii = 1
while ii < 40
  pow3[ii] = pow3[ii - 1] * 3
  ii += 1

kk = 16 ## i64
sz = 1 << kk ## i64
mask = sz - 1 ## i64
ta = i64[65536]
te = i64[65536]

# precompute the table: simulate r until kk halvings have happened
r = 0 ## i64
while r < sz
  n = r ## i64
  halv = 0 ## i64
  a = 0 ## i64
  while halv < kk
    if (n % 2) == 0
      n = n / 2
      halv += 1
    else
      n = 3 * n + 1
      a += 1
  ta[r] = a
  te[r] = n
  r += 1

# self-check: accelerated one-block == true k-halving advance, over many (q,r)
mism = 0 ## i64
qv = 0 ## i64
while qv < 30
  rr = 0 ## i64
  while rr < sz
    start = qv * sz + rr ## i64
    # true: simulate start until kk halvings
    n = start ## i64
    halv = 0 ## i64
    while halv < kk
      if (n % 2) == 0
        n = n / 2
        halv += 1
      else
        n = 3 * n + 1
    acc = pow3[ta[rr]] * qv + te[rr] ## i64
    if acc != n
      mism = mism + 1
    rr += 1
  qv += 1
<< "self-check mismatches (want 0): " + mism.to_s()

# accelerated descent certificate
bcap = 2000000000 ## i64
worst_blocks = 0 ## i64
worst_m = 0 ## i64
m = 3 ## i64
while m <= bcap
  n = m ## i64
  blocks = 0 ## i64
  while n >= m
    q = n >> kk
    rr = n & mask
    n = pow3[ta[rr]] * q + te[rr]
    blocks += 1
  if blocks > worst_blocks
    worst_blocks = blocks
    worst_m = m
  m += 2
<< "certified all n <= " + bcap.to_s() + " descend (no cycle min <= B, all reach 1)"
<< "longest descent: m=" + worst_m.to_s() + " took " + worst_blocks.to_s() + " blocks of " + kk.to_s() + " halvings"
