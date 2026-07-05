# excursions.w -- the up-and-back-down "first passage" excursion, and how well the
# bits BEFORE the run-up predict (a) how many steps until the trajectory crosses back
# below its start level and (b) the integer it lands on.
#
# Object: the stopping time   sig(n) = least k with T^k(n) < n   (shortcut map
# T: even -> n/2, odd -> (3n+1)/2 -- the same map Part B's bijection uses).
# Over the first k steps the path merges to   T^k(n) = (3^a * n + c) / 2^k ,  a = #odd-steps.
#
# Two crossing times are computed per n:
#   sig_mult = first k with 3^a < 2^k   -- the multiplier alone dips below 1.
#              This depends ONLY on the parity vector, i.e. ONLY on n's low bits.
#   sig_act  = first k with the actual integer v < n   -- includes the +c additive.
# Always sig_mult <= sig_act. Equal => low bits predicted the crossing exactly;
# sig_act > sig_mult => the accumulated +1s held v above n for extra steps (the residual
# the low bits cannot see). Run interpreted: bin/tungsten benchmarks/collatz/detour/excursions.w

n_max = 20000

# -------- 1. Sample excursion pairs: (n before) -> (v after), steps, and the bits --------
<< "1. EXCURSION PAIRS  (shortcut map; first passage strictly below the start)"
<< "n      low8bits  tc  steps  odd  peak       lands_on  v*1000/n  sig_mult"
n = 2
while n <= 33
  # low 8 bits as a string (the pattern that drives the run-up)
  bits = ""
  m = n
  j = 0
  while j < 8
    if (m % 2) == 1
      bits = "1" + bits
    else
      bits = "0" + bits
    m = m / 2
    j = j + 1
  # trailing-ones count
  tc = 0
  m = n
  while (m % 2) == 1
    tc = tc + 1
    m = m / 2
  # run the excursion
  v = n
  k = 0
  a = 0
  peak = n
  p2 = 1
  p3 = 1
  sig_mult = 0
  while v >= n
    if (v % 2) == 0
      v = v / 2
    else
      v = (3 * v + 1) / 2
      a = a + 1
      p3 = p3 * 3
    k = k + 1
    p2 = p2 * 2
    if v > peak
      peak = v
    if sig_mult == 0
      if p3 < p2
        sig_mult = k
  ratio = v * 1000 / n
  << "" + n.to_s() + "    " + bits + "  " + tc.to_s() + "    " + k.to_s() + "     " + a.to_s() + "    " + peak.to_s() + "      " + v.to_s() + "       " + ratio.to_s() + "        " + sig_mult.to_s()
  n = n + 1
<< ""

# -------- accumulators for the bulk scan --------
max_k = 64
dist = []
i = 0
while i < max_k
  dist.push(0)
  i = i + 1
max_t = 24
tc_count = []
tc_sum = []
tc_min = []
tc_max = []
i = 0
while i < max_t
  tc_count.push(0)
  tc_sum.push(0)
  tc_min.push(999)
  tc_max.push(0)
  i = i + 1
agree = 0
total = 0
gap1 = 0
gap2 = 0
gap_big = 0

# -------- bulk scan n = 2..n_max --------
n = 2
while n <= n_max
  tc = 0
  m = n
  while (m % 2) == 1
    tc = tc + 1
    m = m / 2
  v = n
  k = 0
  a = 0
  p2 = 1
  p3 = 1
  sig_mult = 0
  while v >= n
    if (v % 2) == 0
      v = v / 2
    else
      v = (3 * v + 1) / 2
      a = a + 1
      p3 = p3 * 3
    k = k + 1
    p2 = p2 * 2
    if sig_mult == 0
      if p3 < p2
        sig_mult = k
  # k is sig_act now
  if k < max_k
    dist[k] = dist[k] + 1
  if tc < max_t
    tc_count[tc] = tc_count[tc] + 1
    tc_sum[tc] = tc_sum[tc] + k
    if k < tc_min[tc]
      tc_min[tc] = k
    if k > tc_max[tc]
      tc_max[tc] = k
  total = total + 1
  if sig_mult == k
    agree = agree + 1
  else
    d = k - sig_mult
    if d == 1
      gap1 = gap1 + 1
    else
      if d == 2
        gap2 = gap2 + 1
      else
        gap_big = gap_big + 1
  n = n + 1

# -------- 2. stopping-time distribution (Terras) --------
<< "2. STOPPING-TIME DISTRIBUTION  over n = 2.." + n_max.to_s() + "   (sig_act = steps to first passage)"
<< "steps   count    permil"
s = 1
while s < max_k
  if dist[s] > 0
    pm = dist[s] * 1000 / total
    << "  " + s.to_s() + "      " + dist[s].to_s() + "     " + pm.to_s()
  s = s + 1
<< ""

# -------- 3. trailing-ones predictor --------
<< "3. PREDICTOR: trailing 1-bits of n  ->  steps to cross back  (more 1s = longer climb)"
<< "trail1s  count    avg_steps(x100)  min  max"
t = 0
while t < max_t
  if tc_count[t] > 0
    avg = tc_sum[t] * 100 / tc_count[t]
    << "  " + t.to_s() + "       " + tc_count[t].to_s() + "      " + avg.to_s() + "          " + tc_min[t].to_s() + "    " + tc_max[t].to_s()
  t = t + 1
<< ""

# -------- 4. how often the LOW BITS ALONE predict the crossing step exactly --------
<< "4. PREDICTABILITY FROM LOW BITS ALONE  (sig_mult, parity vector only)  vs reality (sig_act)"
ap = agree * 1000 / total
<< "exact match sig_mult == sig_act : " + agree.to_s() + " / " + total.to_s() + "  = " + ap.to_s() + " permil"
<< "held up 1 extra step (additive +c) : " + gap1.to_s()
<< "held up 2 extra steps              : " + gap2.to_s()
<< "held up 3+ extra steps             : " + gap_big.to_s()
<< ""
<< "Reading: the multiplicative crossing step is a pure function of n's low bits."
<< "The misses are exactly the additive constant c (set by the HIGH bits) keeping v"
<< "above n a step or two longer -- the only part of the return the low bits can't see."
