# Refined cycle-minimum bound + true elementary reach for Collatz cycle exclusion.
#
# proof.md bounds the minimum element m of an A-odd-step cycle by  m <= M(A) = c_max/Q,
# Q = 2^D - 3^A,  D = ceil(A*log2 3).  Two facts it never uses tighten this for free,
# because m is the cycle MINIMUM:
#
#   v_1 = 1     : n2 = (3m+1)/2^{v1} >= m  =>  2^{v1} <= 3 + 1/m < 4  =>  v1 = 1.
#   v_2 <= 2    : n2 = (3m+1)/2,  n3 = (3n2+1)/2^{v2} >= m,  n2 < 2m
#                 =>  2^{v2} <= (3n2+1)/m = 4.5 + 2.5/m < 8  =>  v2 <= 2   (m >= 3).
#
# In c_max = sum_{i=1..A} 3^{A-i} 2^{S_{i-1}} the terms DECREASE in i (ratio 2/3), so the
# dominant piece is the i=2 term 3^{A-2} 2^{D-A+1}.  v1=1 forces S_1=1, replacing it by
# 3^{A-2}*2 (shrink 3/2);  v2<=2 forces S_2<=3, replacing the i=3 term too (another 3/2).
# Net:  M''(A) = M(A) / (3/2)^2 = M(A)/2.25, a rigorous, elementary tightening.
#
# The point: A<=69 was our 4.5e12 certificate's limit, not the method's.  With Barina's
# verified frontier (2^68 published / 2^71 live) the SAME argument reaches A<=115 / A<=120.
# Runs on the interpreter (bignum):  bin/tungsten collatz_refined.w

<< "A = odd-steps,  D = ceil(A log2 3),  Q = 2^D - 3^A"
<< "M = corpus bound,  M'' = with v1=1 and v2<=2  (should be M/2.25)"
<< ""

# build the frontiers 2^68 (Barina 2021, published) and 2^71 (Barina 2025, live)
b68 = 1
k = 0
while k < 68
  b68 = b68 * 2
  k = k + 1
b71 = b68 * 8

p3 = 1
pw = 1
dexp = 0
rm = 0          # running max of M
rm2 = 0         # running max of M''
# last A cleared under each (frontier, bound) pair
a68 = 0
a68r = 0
a71 = 0
a71r = 0
a = 1
while a <= 130
  p3 = p3 * 3
  while pw <= p3
    pw = pw * 2
    dexp = dexp + 1
  q = pw - p3
  # c_max, tracking the i=2 and i=3 term values (t2, t3) as we go
  cmax = p3 / 3
  t = pw / 2
  t2 = 0
  t3 = 0
  i = a
  while i >= 2
    cmax = cmax + t
    if i == 3
      t3 = t
    if i == 2
      t2 = t
    t = t * 3 / 2
    i = i - 1
  # v1=1: swap the i=2 term 3^{A-2}2^{D-A+1} for 3^{A-2}*2
  cmax1 = cmax
  if a >= 2
    cmax1 = cmax - t2 + (p3 / 9) * 2
  # v2<=2: additionally swap the i=3 term 3^{A-3}2^{D-A+2} for 3^{A-3}*8
  cmax2 = cmax1
  if a >= 3
    cmax2 = cmax1 - t3 + (p3 / 27) * 8
  m = cmax / q
  m2 = cmax2 / q
  if m > rm
    rm = m
  if m2 > rm2
    rm2 = m2
  # record the largest A cleared under each frontier
  if rm < b68
    a68 = a
  if rm2 < b68
    a68r = a
  if rm < b71
    a71 = a
  if rm2 < b71
    a71r = a
  # cross-check window against proof.md, and show the ratio
  if a >= 67
    if a <= 70
      << "  A=" + a.to_s() + "  D=" + dexp.to_s() + "  M=" + m.to_s() + "  M''=" + m2.to_s() + "  M/M''x100=" + ((m * 100) / m2).to_s()
  a = a + 1

<< ""
<< "reach (largest A with running-max bound < frontier B):"
<< "  B = 2^68 (Barina 2021, published):  corpus M -> A<=" + a68.to_s() + "   refined M'' -> A<=" + a68r.to_s()
<< "  B = 2^71 (Barina 2025, live):       corpus M -> A<=" + a71.to_s() + "   refined M'' -> A<=" + a71r.to_s()
<< ""
<< "vs proof.md's self-contained A<=69 (limited by our 4.5e12 certificate, not the method)."
<< "Still ODD-STEPS, not the odd-BLOCKS axis of Simons-de Weger/Hercher: incomparable, weaker coverage."
