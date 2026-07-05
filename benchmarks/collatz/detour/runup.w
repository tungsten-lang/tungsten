# runup.w -- empirical validation of Part D's maximal-expander claim.
#
# Part D (see collatz_detour.w / README) showed the UNIQUE maximal-climbing residue class
# at every k is 2^k - 1 = -1 (mod 2^k): the all-ones bit pattern that "impersonates" the
# map's 2-adic fixed point -1.  Such a number does k consecutive odd-steps -- each step the
# -1 keeps it odd, so it climbs x3/2 -- reaching ~3^k before its finite positive value
# forces the descent.  Prediction: the trajectory peak of 2^k - 1 is Theta(3^k), i.e.
# peak/3^k is bounded independent of k.  This checks it directly (plain Int / bignum,
# interpreted: bin/tungsten benchmarks/collatz/detour/runup.w).

<< "2^k - 1 (all ones) is Part D's maximal run-up start; it should climb to ~3^k."
<< "k     steps-to-1     100 * peak / 3^k   (bounded => peak = Theta(3^k))"
k = 10
while k <= 320
  n = 1
  i = 0
  while i < k
    n = n * 2
    i = i + 1
  n = n - 1
  v = n
  peak = n
  steps = 0
  while v != 1
    if (v % 2) == 0
      v = v / 2
    else
      v = 3 * v + 1
    if v > peak
      peak = v
    steps = steps + 1
  p3 = 1
  i = 0
  while i < k
    p3 = p3 * 3
    i = i + 1
  ratio = peak * 100 / p3
  << "" + k.to_s() + "      " + steps.to_s() + "             " + ratio.to_s()
  k = k * 2
<< ""
<< "The run-up (initial climb) provably tops out at  2*3^k - 2:  the j-th odd-step spikes"
<< "to 3^j * 2^(k-j+1) - 2, maximal at j=k.  That is the 100*peak/3^k = 199 seen here."
<< "The GLOBAL trajectory peak equals that climb top for these k and is Theta(3^k) in"
<< "general -- though for some k (e.g. k=77 reaches ~3.8*3^k) a later descent spike edges"
<< "above it, so 199 is the climb-top value, not a universal global maximum."
<< "Either way: 2^k-1 = -1 mod 2^k is Part D's unique maximal expander -- it does k"
<< "consecutive odd-steps (x3/2 each) before its finite positive value forces the descent."
