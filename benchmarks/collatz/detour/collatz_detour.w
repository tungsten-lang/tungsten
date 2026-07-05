# Collatz via DETOUR-style symbolic merge.
# Three demonstrations:
#   A) a Collatz operation-path merges into ONE affine map (x -> (mul*x+add)/den);
#      a loop "closes" iff that map has a positive-integer fixed point.
#   B) Terras's parity-vector bijection: a bit pattern mod 2^k fully determines
#      the merged operations (the structure you intuited).
#   C) the cycle equation  n*(2^d - 3^a) = c  searched in DETOUR cost-order (rising d):
#      the first sequence that closes is the minimal cycle.

# closure test for a merged affine map x -> (mul*x + add)/den
-> show_close(mul, add, den) (i64 i64 i64)
  q = den - mul ## i64
  if q <= 0
    << "  branch diverges here (den <= mul): no contracting fixed point"
  else
    if (add % q) == 0
      x = add / q ## i64
      << "  LOOP CLOSES at x = " + x.to_s() + "   map: (" + mul.to_s() + "x + " + add.to_s() + ") / " + den.to_s()
    else
      << "  fixed point add/(den-mul) = " + add.to_s() + "/" + q.to_s() + " is not an integer -> no cycle"
  0

# parity vector of the first k Collatz steps, packed low-bit-first
-> pv(x, k) (i64 i64)
  n = x ## i64
  v = 0 ## i64
  i = 0 ## i64
  while i < k
    p = n % 2 ## i64
    v = v | (p << i)
    if p == 0
      n = n / 2
    else
      n = (3 * n + 1) / 2
    i += 1
  v

# population count (number of 1-bits) = number of odd shortcut-steps in a parity vector
-> popcount(v) (i64)
  c = 0 ## i64
  w = v ## i64
  while w > 0
    c = c + (w & 1)
    w = w / 2
  c

# does full Collatz from n0 reach 1 (1 = yes, 0 = blew past step cap = candidate cycle)
-> reaches_one(n0) (i64)
  n = n0 ## i64
  steps = 0 ## i64
  res = 0 ## i64
  while steps < 200000
    if n == 1
      res = 1
      steps = 200000
    else
      if (n % 2) == 0
        n = n / 2
      else
        n = 3 * n + 1
      steps += 1
  res

# ---- powers of two and three ----
pow2 = i64[40]
pow2[0] = 1
i = 1
while i < 40
  pow2[i] = pow2[i - 1] * 2
  i += 1
pow3 = i64[26]
pow3[0] = 1
i = 1
while i < 26
  pow3[i] = pow3[i - 1] * 3
  i += 1

# ============================================================
<< "=== Part A: a Collatz path becomes ONE affine map ==="
# the trivial cycle 1 ->(3x+1)-> 4 ->(/2)-> 2 ->(/2)-> 1, composed op by op.
# state is the map x -> (mul*x + add)/den.  odd: mul'=3mul, add'=3add+den.  even: den'=2den.
mul = 1 ## i64
add = 0 ## i64
den = 1 ## i64
mul = 3 * mul
add = 3 * add + den
<< "  after 3x+1 :  (" + mul.to_s() + "x + " + add.to_s() + ") / " + den.to_s()
den = 2 * den
<< "  after /2   :  (" + mul.to_s() + "x + " + add.to_s() + ") / " + den.to_s() + "   (/2 . /2 will make den=4)"
den = 2 * den
<< "  after /2   :  (" + mul.to_s() + "x + " + add.to_s() + ") / " + den.to_s() + "   <- one merged map for the whole path"
show_close(mul, add, den)
<< ""

# ============================================================
<< "=== Part B: a bit pattern mod 2^k determines the merged ops (Terras bijection) ==="
seen = i64[4096]
k = 1
while k <= 12
  sz = pow2[k]
  j = 0
  while j < sz
    seen[j] = 0
    j += 1
  ok = 1 ## i64
  x = 0
  while x < sz
    v = pv(x, k)
    if seen[v] == 1
      ok = 0
    seen[v] = 1
    x += 1
  if ok == 1
    << "  k=" + k.to_s() + "  " + sz.to_s() + " residue classes -> " + sz.to_s() + " distinct parity vectors  (bijection holds)"
  else
    << "  k=" + k.to_s() + "  COLLISION (bijection fails!)"
  k += 1
<< ""

# ============================================================
<< "=== Part C: search for a closing loop, DETOUR cost-order (rising d) ==="
<< "  cycle eq:  n * (2^d - 3^a) = c   where c is fixed by the halving pattern"
dmax = 34
found_nontrivial = 0 ## i64
cands = 0 ## i64
maxn = 0 ## i64

# a = 1 odd-step.  c = 2^0 = 1.
d = 2
while d <= dmax
  q = pow2[d] - pow3[1]
  if q > 0
    if (1 % q) == 0
      n1 = 1 / q
      cands += 1
      if n1 > maxn
        maxn = n1
  d += 1

# a = 2.  one cut c1 in 1..d-1.  c = 3*2^0 + 1*2^c1 = 3 + 2^c1.
d = 4
while d <= dmax
  q = pow2[d] - pow3[2]
  c1 = 1
  while c1 <= d - 1
    cc = 3 + pow2[c1] ## i64
    if q > 0
      if (cc % q) == 0
        n1 = cc / q
        if n1 > 0
          if (n1 % 2) == 1
            cands += 1
            if n1 > maxn
              maxn = n1
            if reaches_one(n1) == 0
              found_nontrivial = 1
              << "  *** CANDIDATE CYCLE a=2 d=" + d.to_s() + " n=" + n1.to_s()
    c1 += 1
  d += 1

# a = 3.  cuts c1<c2 in 1..d-1.  c = 9 + 3*2^c1 + 2^c2.
d = 5
while d <= dmax
  q = pow2[d] - pow3[3]
  c1 = 1
  while c1 <= d - 2
    c2 = c1 + 1
    while c2 <= d - 1
      cc = 9 + 3 * pow2[c1] + pow2[c2] ## i64
      if q > 0
        if (cc % q) == 0
          n1 = cc / q
          if n1 > 0
            if (n1 % 2) == 1
              cands += 1
              if n1 > maxn
                maxn = n1
              if reaches_one(n1) == 0
                found_nontrivial = 1
                << "  *** CANDIDATE CYCLE a=3 d=" + d.to_s() + " n=" + n1.to_s()
      c2 += 1
    c1 += 1
  d += 1

# a = 4.  cuts c1<c2<c3.  c = 27 + 9*2^c1 + 3*2^c2 + 2^c3.
d = 7
while d <= dmax
  q = pow2[d] - pow3[4]
  c1 = 1
  while c1 <= d - 3
    c2 = c1 + 1
    while c2 <= d - 2
      c3 = c2 + 1
      while c3 <= d - 1
        cc = 27 + 9 * pow2[c1] + 3 * pow2[c2] + pow2[c3] ## i64
        if q > 0
          if (cc % q) == 0
            n1 = cc / q
            if n1 > 0
              if (n1 % 2) == 1
                cands += 1
                if n1 > maxn
                  maxn = n1
                if reaches_one(n1) == 0
                  found_nontrivial = 1
                  << "  *** CANDIDATE CYCLE a=4 d=" + d.to_s() + " n=" + n1.to_s()
        c3 += 1
      c2 += 1
    c1 += 1
  d += 1

<< "  searched a=1..4, d up to " + dmax.to_s()
<< "  integer fixed points found: " + cands.to_s() + "   largest n: " + maxn.to_s()
if found_nontrivial == 0
  << "  every closing loop funnels to 1  ->  NO nontrivial cycle in this cost range"
else
  << "  !!! a nontrivial cycle was found — Collatz would be FALSE"
<< ""

# ============================================================
# Part D answers your conjecture directly: "from a bit pattern, do the merged
# ops bring you back down?"  For a class x mod 2^k, the k-step merged map is
# ~ (3^a x + c)/2^k where a = #odd-steps = popcount(parity vector).  It CONTRACTS
# (sends x below itself) iff 3^a < 2^k, i.e. a < k*log_3(2) ~= 0.6309*k.
<< "=== Part D: which bit patterns contract? (the heuristic, made exact) ==="
kd = 4
while kd <= 20
  szc = pow2[kd]
  astar = 0
  while pow3[astar] < pow2[kd]
    astar += 1
  contract = 0 ## i64
  suma = 0 ## i64
  maxa = 0 ## i64
  allodd = 0 - 1 ## i64
  x = 0
  while x < szc
    a = popcount(pv(x, kd)) ## i64
    suma = suma + a
    if a > maxa
      maxa = a
    if a == kd
      allodd = x
    if a < astar
      contract += 1
    x += 1
  pct = contract * 1000 / szc ## i64
  meanx10 = suma * 10 / szc ## i64
  << "  k=" + kd.to_s() + ": contract if a<" + astar.to_s() + " (a*=ceil .6309k).  mean a=" + meanx10.to_s() + "/10  worst a=" + maxa.to_s()
  << "         contracting classes: " + contract.to_s() + "/" + szc.to_s() + " = " + pct.to_s() + "/1000.  unique all-odd class x=" + allodd.to_s() + " (= 2^k-1 = -1 mod 2^k)"
  kd += 4
<< "  takeaway: the worst bit pattern (a=k) is the 2-adic neighborhood of -1, the map's"
<< "  OTHER fixed point; it climbs for exactly k steps then its real value forces it off."
<< ""

# ============================================================
# Part E: the rigorously attackable certificate.  If every n in [2,B] reaches a
# value below itself, then (by strong induction) every n<=B reaches 1, AND no
# cycle has its minimum element <= B.  Push B as high as compute allows.
<< "=== Part E: certificate — every n <= B reaches 1 (no cycle min <= B, no divergence <= B) ==="
bcap = 1000000000 ## i64
worst_m = 0 ## i64
worst_steps = 0 ## i64
maxval = 0 ## i64
m = 3 ## i64
while m <= bcap
  n = m ## i64
  steps = 0 ## i64
  while n >= m
    if (n % 2) == 0
      n = n / 2
    else
      n = 3 * n + 1
    if n > maxval
      maxval = n
    steps += 1
  if steps > worst_steps
    worst_steps = steps
    worst_m = m
  m += 2
<< "  certified: all n <= " + bcap.to_s() + " descend below themselves -> reach 1; no cycle with min <= B"
<< "  longest descent: m=" + worst_m.to_s() + " took " + worst_steps.to_s() + " steps;  max value on any trajectory = " + maxval.to_s()
