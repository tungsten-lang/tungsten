# Steiner (1977), single-circuit (m=1) Collatz cycle exclusion -- computational content.
#
# A "circuit" (Davison/Steiner) is a Collatz cycle with a SINGLE local minimum: an
# ascending run of k odd-steps (each n -> (3n+1)/2, i.e. exponent v=1) followed by one
# descending run of l halvings.  Such a circuit-cycle on the positive integers
# corresponds to a positive-integer solution (k,l,h) of
#
#       (2^(k+l) - 3^k) * h = 2^l - 1 ,        k >= 1, l >= 1, h >= 1.
#
# Steiner proved, via Baker's linear forms in logarithms, that the ONLY positive
# solution is (k,l,h) = (1,1,1) -- the trivial cycle {1,2}.  (Sanity check:
# (2^2 - 3^1)*1 = 1 = 2^1 - 1.)  This program reproduces the BOUNDED, computational
# part of that statement: it sweeps k = 1..K and, for each k, tests the at-most-tiny
# window of candidate l implied by the constraints below, looking for an exact
# positive h.  It must find only (1,1,1).  The all-k result is Steiner's and needs
# Baker -- the "does a power of 2 fall in the interval" question (see baker_bound.md).
#
# Constraints that bound the search (both derived from the equation itself):
#   * h >= 1 forces the divisor <= the right side:
#         2^(k+l) - 3^k <= 2^l - 1  <=>  2^l*(2^k - 1) <= 3^k - 1
#         <=>  2^l <= (3^k - 1)/(2^k - 1) .                       (upper bound on l)
#   * the divisor must be POSITIVE (so D*h = 2^l-1 > 0 with h >= 1):
#         2^(k+l) > 3^k  <=>  2^l > (3/2)^k .                     (lower bound on l)
# So for each k, 2^l must lie in the narrow interval ( (3/2)^k , (3^k-1)/(2^k-1) ] --
# usually 0 or 1 candidate.  For each candidate, with Q = 2^(k+l) - 3^k (>= 1) the
# upper bound is exactly Q <= 2^l - 1, so h = (2^l - 1)/Q is a positive integer iff Q
# divides 2^l - 1 exactly.
#
# Implementation note: the smallest admissible l only grows with k (3^k outruns 2^k),
# so l is carried across the k-sweep instead of rescanned from 0 -- O(K) doublings
# total, not O(K^2).  All values are plain Int (auto-promotes to bignum; 3^100000 has
# ~47700 digits).  Run INTERPRETED -- the interpreter handles plain Int/bignum, while
# compiled bignum can be unreliable and `## i64`/`i64[]` are not dispatched interpreted:
#       bin/tungsten benchmarks/collatz/detour/circuit_m1.w

kmax = 100000          # K reached; adjustable. ~2.6s interpreted on a laptop.

<< "Steiner m=1 (single-circuit) Collatz cycle exclusion -- bounded computational sweep"
<< "equation: (2^(k+l) - 3^k) * h = 2^l - 1,   k,l,h >= 1   (only positive soln: 1,1,1)"
<< "sweeping k = 1 .. " + kmax.to_s() + "   (plain Int / bignum, interpreted)"
<< ""

p3 = 1                 # 3^k
p2k = 1                # 2^k
pkl = 1                # 2^(k+l), with l carried at the positivity threshold for this k
pl = 1                 # 2^l
l = 0                  # carried l: smallest l with 2^(k+l) > 3^k (nondecreasing in k)
sols = 0
k = 1
while k <= kmax
  p3 = p3 * 3
  p2k = p2k * 2
  pkl = pkl + pkl                  # k grew by 1, l fixed: 2^(k+l) doubles
  while pkl <= p3                  # advance l until the divisor 2^(k+l) - 3^k is positive
    pkl = pkl + pkl
    pl = pl + pl
    l = l + 1
  # walk candidate l upward in temps, so the carried (l, pl, pkl) stay at the threshold
  tl = l
  tpl = pl
  tpkl = pkl
  while (tpkl - p3) <= (tpl - 1)   # h >= 1 window: Q <= 2^l - 1
    q = tpkl - p3                  # Q = 2^(k+l) - 3^k  (>= 1 here)
    rhs = tpl - 1                  # 2^l - 1
    if q >= 1
      if (rhs % q) == 0
        h = rhs / q                # positive integer, automatically >= 1 since Q <= rhs
        sols = sols + 1
        << "  SOLUTION  (k,l,h) = (" + k.to_s() + "," + tl.to_s() + "," + h.to_s() + ")   check (2^(k+l)-3^k)*h = " + (q * h).to_s() + " = 2^l-1 = " + rhs.to_s()
    tpkl = tpkl + tpkl
    tpl = tpl + tpl
    tl = tl + 1
  if (k % 20000) == 0
    << "  ... swept through k=" + k.to_s() + ", solutions so far: " + sols.to_s()
  k = k + 1

<< ""
<< "summary: swept k = 1 .. " + kmax.to_s()
<< "  total positive-integer (k,l,h) solutions found: " + sols.to_s()
if sols == 1
  << "  unique solution is (1,1,1) -- the trivial circuit {1,2}, as Steiner (1977) proved."
  << "  bounded computational content only; the all-k result needs Baker (see baker_bound.md)."
else
  << "  WARNING: expected exactly one solution (1,1,1); investigate."
