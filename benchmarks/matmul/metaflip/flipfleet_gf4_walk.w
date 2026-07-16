# GF(4) Frobenius walk with exact GF(2) harvests (move 7 intake, lane
# prefix ffg4_).
#
# FIELD.  GF(4) = GF(2)[w]/(w^2 + w + 1), elements (a, b) meaning a + w*b.
# A factor is a PAIR of GF(2) bitmask words over the n*m cells (component
# a-word, component b-word); addition is componentwise XOR, so flips,
# splits, and toggle cancellation port from the GF(2) walker verbatim.
#
# GAUGE.  Terms are projective: (u, v, w) ~ (c*u, d*v, e*w) whenever
# c*d*e = 1 in GF(4)*.  ffg4_canonicalize_term scales the leading nonzero
# entry of u and of v to 1, absorbing the compensation into w; canonical
# triples drive equality, hashing, and flip-partner matching.
#
# FROBENIUS.  conj(a + w*b) = (a + b) + w*b (w -> w^2).  A term is RATIONAL
# when its canonical form is conj-fixed; otherwise it pairs with its
# conjugate.  The walk applies every move together with its conjugate
# image, so the term multiset stays Frobenius-closed at all times -- the
# invariant that makes both harvests exact.
#
# HARVEST 1 (trace descent, same shape).  A Frobenius-closed exact GF(4)
# scheme descends to an exact GF(2) scheme:
#   rational term  -> 1 GF(2) term (a gauge in which all six component
#                     words of the b-side vanish; found by scanning the 9
#                     (c, d) gauge pairs);
#   conjugate pair -> 3 GF(2) terms by the Karatsuba identity, derived
#                     symbolically: with t = (p+wq) x (r+ws) x (x+wy),
#                     t = C + wD and conj(C + wD) = (C+D) + wD, so
#                     t + conj(t) = D, and
#                     D = (p+q) x (r+s) x (x+y)  +  p x r x x  +  q x s x y
#                     (checked: the eight-term expansion of the first
#                     product cancels prx and qsy and leaves exactly the
#                     six cross terms of D).
#   Descended cost = #rational + 3 * #pairs; every harvest is exhaustively
#   gated (ffw for square shapes).
#
# HARVEST 2 (column packing, doubled shape).  An ALL-RATIONAL GF(4) scheme
# for <n,m,p> packs to an exact GF(2) scheme for <n,m,2p> at cost 2 per
# term: with B = B0 + w*B1 (paired input columns), a rational term's
# bilinear form splits into a block-0 output term (v on the B0 columns)
# and a block-1 output term (v on the B1 columns).  Strassen packs to the
# known <2,2,4> rank-14 block record -- the planted regression.  Packing
# non-rational schemes is future work and is refused, never fudged.
#
# ADMISSION.  ffg4_verify_exact is a complete n^6 GF(4) coefficient check
# (component a must match the matmul coefficient, component b must vanish).
# Harvests re-gate through ffw (square) or the lane's own rectangular
# Brent verifier.

use metaflip_worker

# ---------------------------------------------------------------------------
# Scalars: 2-bit packed (a | b<<1).  Multiplication table of GF(4).

-> ffg4_mul(x, y) (i64 i64) i64
  a1 = x & 1 ## i64
  b1 = (x >> 1) & 1 ## i64
  a2 = y & 1 ## i64
  b2 = (y >> 1) & 1 ## i64
  a = (a1 & a2) ^ (b1 & b2) ## i64
  b = (a1 & b2) ^ (b1 & a2) ^ (b1 & b2) ## i64
  a | (b << 1)

-> ffg4_inv(x) (i64) i64
  if x == 1
    return 1
  if x == 2
    return 3
  if x == 3
    return 2
  0

-> ffg4_conj_scalar(x) (i64) i64
  a = x & 1 ## i64
  b = (x >> 1) & 1 ## i64
  (a ^ b) | (b << 1)

# ---------------------------------------------------------------------------
# Factors: pairs of words (wa, wb).  Scale a whole factor by a scalar.

-> ffg4_scale_a(wa, wb, s) (i64 i64 i64) i64
  sa = s & 1 ## i64
  sb = (s >> 1) & 1 ## i64
  out = 0 ## i64
  if sa == 1
    out = out ^ wa
  if sb == 1
    out = out ^ wb
  out

-> ffg4_scale_b(wa, wb, s) (i64 i64 i64) i64
  sa = s & 1 ## i64
  sb = (s >> 1) & 1 ## i64
  out = 0 ## i64
  if sb == 1
    out = out ^ wa
  if sa == 1
    out = out ^ wb
  if sb == 1
    out = out ^ wb
  out

-> ffg4_entry(wa, wb, pos) (i64 i64 i64) i64
  ((wa >> pos) & 1) | (((wb >> pos) & 1) << 1)

-> ffg4_first_entry(wa, wb, width) (i64 i64 i64) i64
  pos = 0 ## i64
  while pos < width
    e = ffg4_entry(wa, wb, pos) ## i64
    if e != 0
      return e
    pos += 1
  0

# ---------------------------------------------------------------------------
# Terms: six words (ua, ub, va, vb, wa, wb) in flat arrays at index t.

# Canonicalize in place: scale u by inv(lead(u)), v by inv(lead(v)), w by
# the compensating inverse so the tensor is unchanged.  Returns 1, or 0 for
# a zero factor.
-> ffg4_canonicalize_term(tu_a, tu_b, tv_a, tv_b, tw_a, tw_b, t, uw, vw) (i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64) i64
  lu = ffg4_first_entry(tu_a[t], tu_b[t], uw) ## i64
  lv = ffg4_first_entry(tv_a[t], tv_b[t], vw) ## i64
  if lu == 0 || lv == 0
    return 0
  c = ffg4_inv(lu) ## i64
  d = ffg4_inv(lv) ## i64
  e = ffg4_mul(lu, lv) ## i64
  na = ffg4_scale_a(tu_a[t], tu_b[t], c) ## i64
  nb = ffg4_scale_b(tu_a[t], tu_b[t], c) ## i64
  tu_a[t] = na
  tu_b[t] = nb
  na = ffg4_scale_a(tv_a[t], tv_b[t], d)
  nb = ffg4_scale_b(tv_a[t], tv_b[t], d)
  tv_a[t] = na
  tv_b[t] = nb
  na = ffg4_scale_a(tw_a[t], tw_b[t], e)
  nb = ffg4_scale_b(tw_a[t], tw_b[t], e)
  tw_a[t] = na
  tw_b[t] = nb
  1

-> ffg4_conj_term(tu_a, tu_b, tv_a, tv_b, tw_a, tw_b, t) (i64[] i64[] i64[] i64[] i64[] i64[] i64) i64
  tu_a[t] = tu_a[t] ^ tu_b[t]
  tv_a[t] = tv_a[t] ^ tv_b[t]
  tw_a[t] = tw_a[t] ^ tw_b[t]
  1

-> ffg4_term_is_rational(ua, ub, va, vb, wa, wb, uw, vw) (i64 i64 i64 i64 i64 i64 i64 i64) i64
  # Canonicalize a copy of the term and of its conjugate; equal canonical
  # six-tuples = rational.
  su_a = i64[2]
  su_b = i64[2]
  sv_a = i64[2]
  sv_b = i64[2]
  sw_a = i64[2]
  sw_b = i64[2]
  su_a[0] = ua
  su_b[0] = ub
  sv_a[0] = va
  sv_b[0] = vb
  sw_a[0] = wa
  sw_b[0] = wb
  su_a[1] = ua ^ ub
  su_b[1] = ub
  sv_a[1] = va ^ vb
  sv_b[1] = vb
  sw_a[1] = wa ^ wb
  sw_b[1] = wb
  z = ffg4_canonicalize_term(su_a, su_b, sv_a, sv_b, sw_a, sw_b, 0, uw, vw) ## i64
  z = ffg4_canonicalize_term(su_a, su_b, sv_a, sv_b, sw_a, sw_b, 1, uw, vw)
  if su_a[0] == su_a[1] && su_b[0] == su_b[1] && sv_a[0] == sv_a[1] && sv_b[0] == sv_b[1] && sw_a[0] == sw_a[1] && sw_b[0] == sw_b[1]
    return 1
  0

# ---------------------------------------------------------------------------
# Whole-scheme checks

# Complete GF(4) exactness over all coefficient triples: component a equals
# the <n,m,p> matmul coefficient, component b vanishes.
-> ffg4_verify_exact(tu_a, tu_b, tv_a, tv_b, tw_a, tw_b, count, n, m, p) (i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64 i64) i64
  um = n * m ## i64
  vm = m * p ## i64
  wm = n * p ## i64
  x = 0 ## i64
  while x < um
    y = 0 ## i64
    while y < vm
      zc = 0 ## i64
      while zc < wm
        acc = 0 ## i64
        t = 0 ## i64
        while t < count
          e1 = ffg4_entry(tu_a[t], tu_b[t], x) ## i64
          if e1 != 0
            e2 = ffg4_entry(tv_a[t], tv_b[t], y) ## i64
            if e2 != 0
              e3 = ffg4_entry(tw_a[t], tw_b[t], zc) ## i64
              if e3 != 0
                acc = acc ^ ffg4_mul(ffg4_mul(e1, e2), e3)
          t += 1
        i = x / m ## i64
        j = x % m ## i64
        j2 = y / p ## i64
        k = y % p ## i64
        i2 = zc / p ## i64
        k2 = zc % p ## i64
        want = 0 ## i64
        if j == j2 && i == i2 && k == k2
          want = 1
        if acc != want
          return 0
        zc += 1
      y += 1
    x += 1
  1

# Frobenius closure: the canonical multiset is fixed by conjugation.
-> ffg4_verify_frobenius_closed(tu_a, tu_b, tv_a, tv_b, tw_a, tw_b, count, uw, vw) (i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64) i64
  matched = i64[count + 1]
  t = 0 ## i64
  while t < count
    if matched[t] == 0
      if ffg4_term_is_rational(tu_a[t], tu_b[t], tv_a[t], tv_b[t], tw_a[t], tw_b[t], uw, vw) == 1
        matched[t] = 1
      else
        cu_a = tu_a[t] ^ tu_b[t] ## i64
        cu_b = tu_b[t] ## i64
        cv_a = tv_a[t] ^ tv_b[t] ## i64
        cv_b = tv_b[t] ## i64
        cw_a = tw_a[t] ^ tw_b[t] ## i64
        cw_b = tw_b[t] ## i64
        found = 0 - 1 ## i64
        s = 0 ## i64
        while s < count
          if s != t && matched[s] == 0
            if tu_a[s] == cu_a && tu_b[s] == cu_b && tv_a[s] == cv_a && tv_b[s] == cv_b && tw_a[s] == cw_a && tw_b[s] == cw_b
              found = s
              s = count
          s += 1
        if found < 0
          return 0
        matched[t] = 1
        matched[found] = 1
    t += 1
  1

# Census: profile[0] = rational terms, profile[1] = conjugate pairs,
# profile[2] = closure flag.  Descended cost = profile[0] + 3*profile[1].
-> ffg4_census(tu_a, tu_b, tv_a, tv_b, tw_a, tw_b, count, uw, vw, profile) (i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64 i64[]) i64
  profile[0] = 0
  profile[1] = 0
  profile[2] = ffg4_verify_frobenius_closed(tu_a, tu_b, tv_a, tv_b, tw_a, tw_b, count, uw, vw)
  t = 0 ## i64
  while t < count
    if ffg4_term_is_rational(tu_a[t], tu_b[t], tv_a[t], tv_b[t], tw_a[t], tw_b[t], uw, vw) == 1
      profile[0] = profile[0] + 1
    t += 1
  profile[1] = (count - profile[0]) / 2
  profile[0] + 3 * profile[1]

# ---------------------------------------------------------------------------
# Harvest 1: trace descent to the same shape over GF(2)

# Find a gauge (c, d) making every b-component word of a rational term
# vanish; write the GF(2) masks into out[0..2].  Returns 1, or 0 when no
# gauge works (counted as an abstain by callers).
-> ffg4_rationalize(ua, ub, va, vb, wa, wb, out) (i64 i64 i64 i64 i64 i64 i64[]) i64
  c = 1 ## i64
  while c <= 3
    d = 1 ## i64
    while d <= 3
      e = ffg4_inv(ffg4_mul(c, d)) ## i64
      nub = ffg4_scale_b(ua, ub, c) ## i64
      nvb = ffg4_scale_b(va, vb, d) ## i64
      nwb = ffg4_scale_b(wa, wb, e) ## i64
      if nub == 0 && nvb == 0 && nwb == 0
        out[0] = ffg4_scale_a(ua, ub, c)
        out[1] = ffg4_scale_a(va, vb, d)
        out[2] = ffg4_scale_a(wa, wb, e)
        return 1
      d += 1
    c += 1
  0

# Descend a Frobenius-closed exact GF(4) scheme to GF(2) terms.
# meta (i64[8]): [0] rational emitted, [1] pairs emitted (3 terms each),
# [2] abstains (no rationalizing gauge), [3] zero terms dropped.
# Returns the emitted GF(2) term count, or -1 when closure fails or any
# rational term abstains.
-> ffg4_harvest_trace(tu_a, tu_b, tv_a, tv_b, tw_a, tw_b, count, uw, vw, out_u, out_v, out_w, meta) (i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64 i64[] i64[] i64[] i64[]) i64
  meta[0] = 0
  meta[1] = 0
  meta[2] = 0
  meta[3] = 0
  if ffg4_verify_frobenius_closed(tu_a, tu_b, tv_a, tv_b, tw_a, tw_b, count, uw, vw) != 1
    return 0 - 1
  handled = i64[count + 1]
  emitted = 0 ## i64
  gauge = i64[4]
  t = 0 ## i64
  while t < count
    if handled[t] == 0
      if ffg4_term_is_rational(tu_a[t], tu_b[t], tv_a[t], tv_b[t], tw_a[t], tw_b[t], uw, vw) == 1
        if ffg4_rationalize(tu_a[t], tu_b[t], tv_a[t], tv_b[t], tw_a[t], tw_b[t], gauge) == 1
          out_u[emitted] = gauge[0]
          out_v[emitted] = gauge[1]
          out_w[emitted] = gauge[2]
          emitted += 1
          meta[0] = meta[0] + 1
          handled[t] = 1
        else
          meta[2] = meta[2] + 1
          return 0 - 1
      else
        cu_a = tu_a[t] ^ tu_b[t] ## i64
        cu_b = tu_b[t] ## i64
        cv_a = tv_a[t] ^ tv_b[t] ## i64
        cv_b = tv_b[t] ## i64
        cw_a = tw_a[t] ^ tw_b[t] ## i64
        cw_b = tw_b[t] ## i64
        partner = 0 - 1 ## i64
        s = 0 ## i64
        while s < count
          if s != t && handled[s] == 0
            if tu_a[s] == cu_a && tu_b[s] == cu_b && tv_a[s] == cv_a && tv_b[s] == cv_b && tw_a[s] == cw_a && tw_b[s] == cw_b
              partner = s
              s = count
          s += 1
        if partner < 0
          return 0 - 1
        # Karatsuba: t + conj(t) = (p^q)x(r^s)x(x^y) + pxrxx + qxsxy with
        # p = a-words, q = b-words of t's three factors.
        p1 = tu_a[t] ## i64
        q1 = tu_b[t] ## i64
        r1 = tv_a[t] ## i64
        s1 = tv_b[t] ## i64
        x1 = tw_a[t] ## i64
        y1 = tw_b[t] ## i64
        cu = p1 ^ q1 ## i64
        cv = r1 ^ s1 ## i64
        cw = x1 ^ y1 ## i64
        if cu != 0 && cv != 0 && cw != 0
          out_u[emitted] = cu
          out_v[emitted] = cv
          out_w[emitted] = cw
          emitted += 1
        else
          meta[3] = meta[3] + 1
        if p1 != 0 && r1 != 0 && x1 != 0
          out_u[emitted] = p1
          out_v[emitted] = r1
          out_w[emitted] = x1
          emitted += 1
        else
          meta[3] = meta[3] + 1
        if q1 != 0 && s1 != 0 && y1 != 0
          out_u[emitted] = q1
          out_v[emitted] = s1
          out_w[emitted] = y1
          emitted += 1
        else
          meta[3] = meta[3] + 1
        meta[1] = meta[1] + 1
        handled[t] = 1
        handled[partner] = 1
    t += 1
  emitted

# ---------------------------------------------------------------------------
# Harvest 2: column packing to <n,m,2p> (all-rational schemes)

# The lane's own exhaustive rectangular verifier for the doubled shape.
-> ffg4_verify_rect(us, vs, ws, count, n, m, p) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  um = n * m ## i64
  vm = m * p ## i64
  wm = n * p ## i64
  a = 0 ## i64
  while a < um
    b = 0 ## i64
    while b < vm
      c = 0 ## i64
      while c < wm
        acc = 0 ## i64
        t = 0 ## i64
        while t < count
          acc = acc ^ (((us[t] >> a) & 1) & ((vs[t] >> b) & 1) & ((ws[t] >> c) & 1))
          t += 1
        i = a / m ## i64
        j = a % m ## i64
        j2 = b / p ## i64
        k = b % p ## i64
        i2 = c / p ## i64
        k2 = c % p ## i64
        want = 0 ## i64
        if j == j2 && i == i2 && k == k2
          want = 1
        if acc != want
          return 0
        c += 1
      b += 1
    a += 1
  1

# Pack an all-rational exact GF(4) <n,m,p> scheme into GF(2) <n,m,2p>.
# Every input term must rationalize; each emits a block-0 and a block-1
# term (v remapped from m*p to m*2p columns, w from n*p to n*2p outputs).
# Returns the packed term count (2 * input), or -1 when any term fails to
# rationalize (non-rational packing is future work, refused here).
-> ffg4_harvest_pack(tu_a, tu_b, tv_a, tv_b, tw_a, tw_b, count, n, m, p, out_u, out_v, out_w) (i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64 i64 i64[] i64[] i64[] ) i64
  gauge = i64[4]
  emitted = 0 ## i64
  t = 0 ## i64
  while t < count
    if ffg4_rationalize(tu_a[t], tu_b[t], tv_a[t], tv_b[t], tw_a[t], tw_b[t], gauge) != 1
      return 0 - 1
    block = 0 ## i64
    while block < 2
      nv = 0 ## i64
      j = 0 ## i64
      while j < m
        k = 0 ## i64
        while k < p
          if ((gauge[1] >> (j * p + k)) & 1) == 1
            nv = nv | (1 << (j * 2 * p + block * p + k))
          k += 1
        j += 1
      nw = 0 ## i64
      i = 0 ## i64
      while i < n
        k = 0 ## i64
        while k < p
          if ((gauge[2] >> (i * p + k)) & 1) == 1
            nw = nw | (1 << (i * 2 * p + block * p + k))
          k += 1
        i += 1
      out_u[emitted] = gauge[0]
      out_v[emitted] = nv
      out_w[emitted] = nw
      emitted += 1
      block += 1
    t += 1
  emitted

# ---------------------------------------------------------------------------
# Bounded gauge-aware walk

-> ffg4_next(rng) (i64[]) i64
  rng[0] = (rng[0] * 6364136223846793005 + 1442695040888963407) & 9223372036854775807
  rng[0]

# One bounded gauge-aware GF(4) walk step set: random Frobenius-respecting
# flips on projectively shared u factors, applied to a flat term store.
# Acceptance is lex(descended cost, total support weight); every accepted
# state is re-verified exactly (this is an intake lane: gate every accept).
# meta (i64[12]): [0] proposals [1] fired [2] accepted [3] rejected
# [4] gate failures (must stay 0) [5] final count [6] final descended cost
# [7] best descended cost [8] rational at end [9] pairs at end.
# Returns the best descended cost reached, or -1 on a structural failure.
-> ffg4_walk(tu_a, tu_b, tv_a, tv_b, tw_a, tw_b, count_in, n, m, p, moves, seed, meta) (i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64[]) i64
  i = 0 ## i64
  while i < 12
    meta[i] = 0
    i += 1
  uw = n * m ## i64
  vw = m * p ## i64
  count = count_in ## i64
  if ffg4_verify_exact(tu_a, tu_b, tv_a, tv_b, tw_a, tw_b, count, n, m, p) != 1
    return 0 - 1
  profile = i64[4]
  cost = ffg4_census(tu_a, tu_b, tv_a, tv_b, tw_a, tw_b, count, uw, vw, profile) ## i64
  best = cost ## i64
  rng = i64[1]
  rng[0] = (seed | 1) & 9223372036854775807
  step = 0 ## i64
  while step < moves
    meta[0] = meta[0] + 1
    # Draw a pair sharing a projective u factor.  Draw from bit 33 up: the
    # LCG's low bits have tiny periods (the flipfleet_sat_cdcl_test lesson)
    # and a low-bit modulus locks consecutive draws into a fixed stride.
    t1 = (ffg4_next(rng) >> 33) % count ## i64
    t2 = (ffg4_next(rng) >> 33) % count ## i64
    fired = 0 ## i64
    if t1 != t2
      # Projective match: canonical u of t2 equals canonical u of t1 after
      # some scalar; test all three nonzero scalars.
      s = 1 ## i64
      while s <= 3 && fired == 0
        if ffg4_scale_a(tu_a[t2], tu_b[t2], s) == tu_a[t1] && ffg4_scale_b(tu_a[t2], tu_b[t2], s) == tu_b[t1]
          # Snapshot both terms for an exact reject-rollback.
          snap = i64[12]
          snap[0] = tu_a[t1]
          snap[1] = tu_b[t1]
          snap[2] = tv_a[t1]
          snap[3] = tv_b[t1]
          snap[4] = tw_a[t1]
          snap[5] = tw_b[t1]
          snap[6] = tu_a[t2]
          snap[7] = tu_b[t2]
          snap[8] = tv_a[t2]
          snap[9] = tv_b[t2]
          snap[10] = tw_a[t2]
          snap[11] = tw_b[t2]
          # Re-gauge t2 by (s, 1, inv(s)) so u2 == u1 exactly, then flip:
          # (u, v1, w1), (u, v2, w2) -> (u, v1, w1 + w2), (u, v1 + v2, w2).
          inv = ffg4_inv(s) ## i64
          nwa = ffg4_scale_a(tw_a[t2], tw_b[t2], inv) ## i64
          nwb = ffg4_scale_b(tw_a[t2], tw_b[t2], inv) ## i64
          tu_a[t2] = tu_a[t1]
          tu_b[t2] = tu_b[t1]
          tw_a[t2] = nwa
          tw_b[t2] = nwb
          tw_a[t1] = tw_a[t1] ^ tw_a[t2]
          tw_b[t1] = tw_b[t1] ^ tw_b[t2]
          tv_a[t2] = tv_a[t2] ^ tv_a[t1]
          tv_b[t2] = tv_b[t2] ^ tv_b[t1]
          fired = 1
          meta[1] = meta[1] + 1
          # Zero factors after folding = the reduction case; drop them.
          drop1 = 0 ## i64
          if tw_a[t1] == 0 && tw_b[t1] == 0
            drop1 = 1
          drop2 = 0 ## i64
          if tv_a[t2] == 0 && tv_b[t2] == 0
            drop2 = 1
          # Verify and accept/reject on the (possibly compacted) store.
          keep_u_a = i64[count]
          keep_u_b = i64[count]
          keep_v_a = i64[count]
          keep_v_b = i64[count]
          keep_w_a = i64[count]
          keep_w_b = i64[count]
          kept = 0 ## i64
          idx = 0 ## i64
          while idx < count
            skip = 0 ## i64
            if idx == t1 && drop1 == 1
              skip = 1
            if idx == t2 && drop2 == 1
              skip = 1
            if skip == 0
              keep_u_a[kept] = tu_a[idx]
              keep_u_b[kept] = tu_b[idx]
              keep_v_a[kept] = tv_a[idx]
              keep_v_b[kept] = tv_b[idx]
              keep_w_a[kept] = tw_a[idx]
              keep_w_b[kept] = tw_b[idx]
              kept += 1
            idx += 1
          exact = ffg4_verify_exact(keep_u_a, keep_u_b, keep_v_a, keep_v_b, keep_w_a, keep_w_b, kept, n, m, p) ## i64
          accept = 0 ## i64
          new_cost = 0 ## i64
          if exact == 1
            new_cost = ffg4_census(keep_u_a, keep_u_b, keep_v_a, keep_v_b, keep_w_a, keep_w_b, kept, uw, vw, profile)
            if profile[2] == 1 && new_cost <= cost
              accept = 1
          if accept == 1
            meta[2] = meta[2] + 1
            idx = 0
            while idx < kept
              tu_a[idx] = keep_u_a[idx]
              tu_b[idx] = keep_u_b[idx]
              tv_a[idx] = keep_v_a[idx]
              tv_b[idx] = keep_v_b[idx]
              tw_a[idx] = keep_w_a[idx]
              tw_b[idx] = keep_w_b[idx]
              idx += 1
            count = kept
            cost = new_cost
            if cost < best
              best = cost
          else
            meta[3] = meta[3] + 1
            if exact == 0
              meta[4] = meta[4] + 1
            # Restore both terms from the pre-move snapshot.
            tu_a[t1] = snap[0]
            tu_b[t1] = snap[1]
            tv_a[t1] = snap[2]
            tv_b[t1] = snap[3]
            tw_a[t1] = snap[4]
            tw_b[t1] = snap[5]
            tu_a[t2] = snap[6]
            tu_b[t2] = snap[7]
            tv_a[t2] = snap[8]
            tv_b[t2] = snap[9]
            tw_a[t2] = snap[10]
            tw_b[t2] = snap[11]
        s += 1
    step += 1
  meta[5] = count
  meta[6] = cost
  meta[7] = best
  z = ffg4_census(tu_a, tu_b, tv_a, tv_b, tw_a, tw_b, count, uw, vw, profile) ## i64
  meta[8] = profile[0]
  meta[9] = profile[1]
  best
