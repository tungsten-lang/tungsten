# Part G: where can a Collatz cycle close?  The base-2 / base-3 competition.
#
# A cycle with A odd-steps (3x+1) and D halvings needs the log-jump to cancel:
#       A*log2(3) = D        i.e.   2^D = 3^A.
# log2(3) is irrational, so 2^D = 3^A NEVER holds -> Q = 2^D - 3^A >= 1 always.
# The minimum element of an A-cycle is  m = c / Q  with
#       c = sum_{i=1..A} 3^(A-i) * 2^(S_{i-1}),   0 = S_0 < S_1 < ... < S_{A-1} <= D-1.
# c is maximised by packing all halvings early (S_{i-1} as large as possible); call
# that c_max.  Increasing D only shrinks c_max/Q, so D = ceil(A*log2 3) is the worst
# case and  m <= c_max/Q  is then a RIGOROUS upper bound on the cycle minimum for
# every D.  If c_max/Q < B and we verified all n <= B reach 1, that A is excluded.
#
# c_max/Q is huge only where Q is tiny -- the convergents of log2(3).  Ordering
# candidates by Q (smallest first) is the DETOUR cost function for cycle search.
#
# All bignum, runs via the interpreter:  bin/tungsten collatz_convergents.w

<< "convergent-style cycle-hiding spots for log2(3)  (smaller Q/3^A = deeper hiding):"
<< "  A = odd-steps,  D = ceil(A*log2 3),  Q = 2^D - 3^A,  m < c_max/Q = rigorous min bound"
<< ""

p3 = 1            # 3^A
pw = 1            # smallest power of two strictly greater than 3^A
dexp = 0          # its exponent D
bestnum = 1       # record ratio Q/3^A held as bestnum/bestden (start 1/1)
bestden = 1
rmax = 0
a = 1
while a <= 100
  p3 = p3 * 3
  while pw <= p3
    pw = pw * 2
    dexp = dexp + 1
  q = pw - p3
  # tight c_max: i=1 term is 3^(A-1); i=a..2 terms are 2^(D-1), *3/2 each step down
  cmax = p3 / 3
  t = pw / 2
  i = a
  while i >= 2
    cmax = cmax + t
    t = t * 3 / 2
    i = i - 1
  mbound = cmax / q
  if mbound > rmax
    rmax = mbound          # running max = the verified bound B needed to exclude through A
  # report record-small relative gaps (the convergents = the cycle-hiding spots)
  if q * bestden < bestnum * p3
    bestnum = q
    bestden = p3
    depth = p3 / q
    << "  A=" + a.to_s() + "  D=" + dexp.to_s() + "  Q=" + q.to_s() + "  depth 3^A/Q=" + depth.to_s() + "  min<=" + mbound.to_s()
  # milestone table: the verified bound B required to exclude every cycle through A
  if a >= 45
    if a <= 90
      if (a % 5) == 0
        << "    >> exclude all cycles through A=" + a.to_s() + "  needs verified B > " + rmax.to_s()
  if a >= 66
    if a <= 72
      << "    >> exclude all cycles through A=" + a.to_s() + "  needs verified B > " + rmax.to_s()
  if a == 94
    << "    >> exclude all cycles through A=" + a.to_s() + "  needs verified B > " + rmax.to_s()
  a = a + 1

<< ""
<< "reading: the running max (B-needed) is the cost of expanding A.  It grows ~1.5^A"
<< "through the generic range, so each ~1.5x in B buys +1 in A (a decade buys ~+5.7);"
<< "the deep convergents (A=41, then A=94) are the spikes.  NOTE A here is ODD-STEPS;"
<< "Simons-de Weger 2005 exclude m-cycles for m<=68 where m counts BLOCKS of consecutive"
<< "odd integers (m<=odd-steps) via Rhin's log-form bound -- a stronger, different axis."
