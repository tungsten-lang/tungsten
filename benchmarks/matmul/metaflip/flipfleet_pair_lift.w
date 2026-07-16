# Pair-lift crossover via output-axis concatenation (move 10 intake, lane
# prefix ffpl_).
#
# EXACT CONTENT.  Two exact parents X, Y for <n,m,p> lift into one exact
# scheme for <n,m,2p>: the u/A factor space is SHARED, X's v embeds into
# B-columns 0..p-1 and its w into output columns 0..p-1, Y's into columns
# p..2p-1.  Block-diagonal by construction, the lifted term multiset
# computes <n,m,2p> exactly (verified by the lane's own exhaustive
# rectangular Brent check, since doubled shapes are outside the ffr
# allowlist).
#
# CROSS-PARENT COUPLING.  X-terms and Y-terms sharing a u mask are
# immediate flip partners in the lifted scheme -- a coupling no same-shape
# operator has.  The bounded walk applies rank-neutral flips with a
# cross-block preference and instruments MIXING: a term is mixed when its
# v or w support spans both column blocks.
#
# HARVEST = the Kauers-Wood projection: zeroing the block-2 columns of B
# and C maps each term to its block-1 part (terms whose projected v or w
# vanish drop), and the projected term list parity-compacts to an exact
# <n,m,p> scheme -- exactness is inherited from the lifted scheme, and the
# full gate re-checks it.  The documented no-op trap is real and measured
# here: a SINGLE cross flip's mixed terms project straight back to the
# parent terms (child distance 0), which is why the driver only harvests
# after at least H mixed terms exist.
#
# Metrics per child: term-set distance to each parent (canonical multiset
# symmetric difference).  Union-nullity accounting is noted as follow-up
# (the flipfleet_align_relink helper computes it for square shapes).

use metaflip_worker

# ---------------------------------------------------------------------------
# Exhaustive rectangular verifier (any small <n,m,p>).

-> ffpl_verify_rect(us, vs, ws, count, n, m, p) (i64[] i64[] i64[] i64 i64 i64 i64) i64
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

# ---------------------------------------------------------------------------
# Lift and blocks

# Remap a v mask from m*p columns into the given block of m*2p columns.
-> ffpl_lift_v(v, m, p, block) (i64 i64 i64 i64) i64
  out = 0 ## i64
  j = 0 ## i64
  while j < m
    k = 0 ## i64
    while k < p
      if ((v >> (j * p + k)) & 1) == 1
        out = out | (1 << (j * 2 * p + block * p + k))
      k += 1
    j += 1
  out

-> ffpl_lift_w(w, n, p, block) (i64 i64 i64 i64) i64
  out = 0 ## i64
  i = 0 ## i64
  while i < n
    k = 0 ## i64
    while k < p
      if ((w >> (i * p + k)) & 1) == 1
        out = out | (1 << (i * 2 * p + block * p + k))
      k += 1
    i += 1
  out

# Block masks over the lifted v / w widths.
-> ffpl_v_block_mask(m, p, block) (i64 i64 i64) i64
  out = 0 ## i64
  j = 0 ## i64
  while j < m
    k = 0 ## i64
    while k < p
      out = out | (1 << (j * 2 * p + block * p + k))
      k += 1
    j += 1
  out

-> ffpl_w_block_mask(n, p, block) (i64 i64 i64) i64
  out = 0 ## i64
  i = 0 ## i64
  while i < n
    k = 0 ## i64
    while k < p
      out = out | (1 << (i * 2 * p + block * p + k))
      k += 1
    i += 1
  out

# Build the lifted scheme.  Returns xr + yr.
-> ffpl_lift(xu, xv, xw, xr, yu, yv, yw, yr, n, m, p, lu, lv, lw) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64 i64 i64 i64[] i64[] i64[]) i64
  t = 0 ## i64
  while t < xr
    lu[t] = xu[t]
    lv[t] = ffpl_lift_v(xv[t], m, p, 0)
    lw[t] = ffpl_lift_w(xw[t], n, p, 0)
    t += 1
  t = 0
  while t < yr
    lu[xr + t] = yu[t]
    lv[xr + t] = ffpl_lift_v(yv[t], m, p, 1)
    lw[xr + t] = ffpl_lift_w(yw[t], n, p, 1)
    t += 1
  xr + yr

# A lifted term is MIXED when its v or w support spans both blocks.
-> ffpl_term_mixed(v, w, n, m, p) (i64 i64 i64 i64 i64) i64
  v0 = v & ffpl_v_block_mask(m, p, 0) ## i64
  v1 = v & ffpl_v_block_mask(m, p, 1) ## i64
  w0 = w & ffpl_w_block_mask(n, p, 0) ## i64
  w1 = w & ffpl_w_block_mask(n, p, 1) ## i64
  if v0 != 0 && v1 != 0
    return 1
  if w0 != 0 && w1 != 0
    return 1
  0

-> ffpl_mixed_count(lv, lw, count, n, m, p) (i64[] i64[] i64 i64 i64 i64) i64
  total = 0 ## i64
  t = 0 ## i64
  while t < count
    total = total + ffpl_term_mixed(lv[t], lw[t], n, m, p)
    t += 1
  total

# ---------------------------------------------------------------------------
# Projection harvest

# Project the lifted scheme onto one block: keep each term's block part of
# v and w (compacted back to m*p / n*p bit positions); terms whose part
# vanishes drop; equal projected terms parity-cancel.  Returns the child
# term count.
-> ffpl_project(lu, lv, lw, count, n, m, p, block, cu, cv, cw) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64[] i64[] i64[]) i64
  kept = 0 ## i64
  t = 0 ## i64
  while t < count
    pv = 0 ## i64
    j = 0 ## i64
    while j < m
      k = 0 ## i64
      while k < p
        if ((lv[t] >> (j * 2 * p + block * p + k)) & 1) == 1
          pv = pv | (1 << (j * p + k))
        k += 1
      j += 1
    pw = 0 ## i64
    i = 0 ## i64
    while i < n
      k = 0 ## i64
      while k < p
        if ((lw[t] >> (i * 2 * p + block * p + k)) & 1) == 1
          pw = pw | (1 << (i * p + k))
        k += 1
      i += 1
    if lu[t] != 0 && pv != 0 && pw != 0
      dup = 0 - 1 ## i64
      s = 0 ## i64
      while s < kept
        if cu[s] == lu[t] && cv[s] == pv && cw[s] == pw
          dup = s
          s = kept
        s += 1
      if dup >= 0
        cu[dup] = cu[kept - 1]
        cv[dup] = cv[kept - 1]
        cw[dup] = cw[kept - 1]
        kept -= 1
      else
        cu[kept] = lu[t]
        cv[kept] = pv
        cw[kept] = pw
        kept += 1
    t += 1
  kept

# Canonical multiset symmetric difference between two term lists.
-> ffpl_distance(au, av, aw, ar, bu, bv, bw, br) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  common = 0 ## i64
  used = i64[br + 1]
  i = 0 ## i64
  while i < ar
    j = 0 ## i64
    while j < br
      if used[j] == 0 && bu[j] == au[i] && bv[j] == av[i] && bw[j] == aw[i]
        used[j] = 1
        common += 1
        j = br
      j += 1
    i += 1
  ar + br - 2 * common

# ---------------------------------------------------------------------------
# Bounded walk + driver

-> ffpl_next(rng) (i64[]) i64
  rng[0] = (rng[0] * 6364136223846793005 + 1442695040888963407) & 9223372036854775807
  rng[0]

# One-shot driver: lift, walk rank-neutral flips with a cross-block
# preference, harvest both children once mixed_count >= want_mixed (or at
# the end regardless, counted as a forced harvest), gate everything.
# meta (i64[20]):
#   [0] lifted rank  [1] proposals  [2] fired  [3] accepted (== fired:
#       rank-neutral flips at fixed weight policy below)  [4] cross flips
#   [5] peak mixed count  [6] harvest mixed count  [7] forced harvest flag
#   [8] child1 count  [9] child1 gate  [10] child1 distance to X
#   [11] child1 distance to Y  [12] child2 count  [13] child2 gate
#   [14] child2 distance to Y  [15] child2 distance to X
#   [16] walk gate failures (must stay 0)  [17] elapsed ms
# Returns 1 when both children gate exactly, 0 otherwise, negative on
# structural errors (-1 plan, -2 lift not exact).
-> ffpl_run(xu, xv, xw, xr, yu, yv, yw, yr, n, m, p, moves, want_mixed, seed, c1u, c1v, c1w, c2u, c2v, c2w, meta) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  i = 0 ## i64
  while i < 20
    meta[i] = 0
    i += 1
  started = ccall("__w_clock_ms") ## i64
  if n < 2 || m < 2 || p < 2 || xr < 1 || yr < 1
    return 0 - 1
  if m * 2 * p > 60 || n * 2 * p > 60
    return 0 - 1
  count = xr + yr ## i64
  lu = i64[count + 4]
  lv = i64[count + 4]
  lw = i64[count + 4]
  z = ffpl_lift(xu, xv, xw, xr, yu, yv, yw, yr, n, m, p, lu, lv, lw) ## i64
  if ffpl_verify_rect(lu, lv, lw, count, n, m, 2 * p) != 1
    return 0 - 2
  meta[0] = count
  rng = i64[1]
  rng[0] = (seed | 1) & 9223372036854775807
  step = 0 ## i64
  while step < moves
    meta[1] = meta[1] + 1
    t1 = (ffpl_next(rng) >> 33) % count ## i64
    t2 = (ffpl_next(rng) >> 33) % count ## i64
    if t1 != t2 && lu[t1] == lu[t2]
      # Cross-block preference: a same-block pair is only taken one draw
      # in four; a cross pair always fires.
      m1 = ffpl_term_mixed(lv[t1], lw[t1], n, m, p) ## i64
      m2 = ffpl_term_mixed(lv[t2], lw[t2], n, m, p) ## i64
      cross = 0 ## i64
      if m1 == 0 && m2 == 0
        b1 = 0 ## i64
        if (lw[t1] & ffpl_w_block_mask(n, p, 1)) != 0
          b1 = 1
        b2 = 0 ## i64
        if (lw[t2] & ffpl_w_block_mask(n, p, 1)) != 0
          b2 = 1
        if b1 != b2
          cross = 1
      take = 1 ## i64
      if cross == 0 && (ffpl_next(rng) & 3) != 0
        take = 0
      if take == 1
        meta[2] = meta[2] + 1
        if cross == 1
          meta[4] = meta[4] + 1
        # Exact flip: (u,v1,w1),(u,v2,w2) -> (u,v1,w1^w2),(u,v1^v2,w2).
        lw[t1] = lw[t1] ^ lw[t2]
        lv[t2] = lv[t2] ^ lv[t1]
        # Zero folds would change rank; keep the walk rank-neutral by
        # rolling those back.
        if lw[t1] == 0 || lv[t2] == 0
          lv[t2] = lv[t2] ^ lv[t1]
          lw[t1] = lw[t1] ^ lw[t2]
          meta[2] = meta[2] - 1
          if cross == 1
            meta[4] = meta[4] - 1
        else
          meta[3] = meta[3] + 1
          mixed = ffpl_mixed_count(lv, lw, count, n, m, p) ## i64
          if mixed > meta[5]
            meta[5] = mixed
          if want_mixed > 0 && mixed >= want_mixed
            step = moves
    step += 1
  # Verify the lifted scheme once after the walk (every move above is an
  # exact identity; a failure here is structural).
  if ffpl_verify_rect(lu, lv, lw, count, n, m, 2 * p) != 1
    meta[16] = 1
    return 0
  meta[6] = ffpl_mixed_count(lv, lw, count, n, m, p)
  if want_mixed > 0 && meta[6] < want_mixed
    meta[7] = 1
  c1 = ffpl_project(lu, lv, lw, count, n, m, p, 0, c1u, c1v, c1w) ## i64
  c2 = ffpl_project(lu, lv, lw, count, n, m, p, 1, c2u, c2v, c2w) ## i64
  meta[8] = c1
  meta[12] = c2
  ok = 1 ## i64
  if c1 >= 1 && ffpl_verify_rect(c1u, c1v, c1w, c1, n, m, p) == 1
    meta[9] = 1
  else
    ok = 0
  if c2 >= 1 && ffpl_verify_rect(c2u, c2v, c2w, c2, n, m, p) == 1
    meta[13] = 1
  else
    ok = 0
  meta[10] = ffpl_distance(c1u, c1v, c1w, c1, xu, xv, xw, xr)
  meta[11] = ffpl_distance(c1u, c1v, c1w, c1, yu, yv, yw, yr)
  meta[14] = ffpl_distance(c2u, c2v, c2w, c2, yu, yv, yw, yr)
  meta[15] = ffpl_distance(c2u, c2v, c2w, c2, xu, xv, xw, xr)
  meta[17] = ccall("__w_clock_ms") - started
  ok
