# Self-validating 3n+1 cycle search over BOTH signs.
#
# Finds every shortcut-map cycle that has an element of magnitude <= R.  The shortcut
# map on odds is  n -> (3n+1)/2^w  with w the exact 2-adic valuation of 3n+1 (works for
# negatives too).  From each odd n0 we iterate; we STOP when either
#   * |n| < |n0|  -> n0 is not its cycle's minimum-magnitude element (it will be reported
#                    from that smaller element), or
#   * n == n0     -> a cycle, and n0 IS its minimum-magnitude representative -> report once.
#
# The point: the 3n+1 map has KNOWN nontrivial cycles over the NEGATIVE integers, so this
# is self-validating -- it MUST recover {1} (trivial, positive), {-1}, {-5,-7}, and the
# length-7 cycle {-17,-25,-37,-55,-41,-61,-91}.  A bug shows up as a missing known cycle,
# not as an unfalsifiable "found nothing".  For each cycle we also read off the block count
# m = #(w>=2 descents) and cross-check proof.md's Lemma 1:  n0*(2^d - 3^a) = c.
#
# Plain Int / bignum, run interpreted:  bin/tungsten benchmarks/collatz/detour/cycle_search.w

r = 20000
maxsteps = 100000
<< "3n+1 shortcut-map cycle search, |element| <= " + r.to_s() + ", both signs"
<< "oracle: must recover  {1}  {-1}  {-5,-7}  and the length-7 negative cycle"
<< ""

found = 0
n0 = 1 - r
while n0 <= r
  absn0 = n0
  if absn0 < 0
    absn0 = 0 - absn0
  # pass 1 -- is n0 the minimum-magnitude representative of a cycle?
  n = n0
  steps = 0
  result = 0
  alen = 0
  while steps < maxsteps
    t = 3 * n + 1
    w = 0
    while (t % 2) == 0
      t = t / 2
      w = w + 1
    n = t
    steps = steps + 1
    if n == n0
      result = 1
      alen = steps
      steps = maxsteps
    else
      av = n
      if av < 0
        av = 0 - av
      if av < absn0
        steps = maxsteps
  if result == 1
    # pass 2 -- recompute d, m, c, list elements, verify Lemma 1
    p3 = 1
    jj = 0
    while jj < alen - 1
      p3 = p3 * 3
      jj = jj + 1
    pw2 = 1
    cc = 0
    dd = 0
    mm = 0
    n = n0
    elts = n0.to_s()
    i = 0
    while i < alen
      cc = cc + p3 * pw2
      t = 3 * n + 1
      w = 0
      while (t % 2) == 0
        t = t / 2
        w = w + 1
      n = t
      dd = dd + w
      if w >= 2
        mm = mm + 1
      ww = 0
      while ww < w
        pw2 = pw2 + pw2
        ww = ww + 1
      if i < alen - 1
        p3 = p3 / 3
        elts = elts + " -> " + n.to_s()
      i = i + 1
    pow2d = 1
    jj = 0
    while jj < dd
      pow2d = pow2d + pow2d
      jj = jj + 1
    pow3a = 1
    jj = 0
    while jj < alen
      pow3a = pow3a * 3
      jj = jj + 1
    lhs = n0 * (pow2d - pow3a)
    match = 0
    if lhs == cc
      match = 1
    found = found + 1
    << "cycle  a=" + alen.to_s() + "  m=" + mm.to_s() + " descents  min-elt=" + n0.to_s()
    << "   orbit: " + elts + " -> " + n0.to_s()
    << "   d=" + dd.to_s() + "  Lemma1: n0*(2^d-3^a)=" + lhs.to_s() + "  c=" + cc.to_s() + "  match=" + match.to_s()
  n0 = n0 + 2
<< ""
<< "total distinct cycles found (|element| <= " + r.to_s() + "): " + found.to_s()
