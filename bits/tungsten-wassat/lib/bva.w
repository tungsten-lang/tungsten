# Bounded variable addition (SimpleBVA: Manthey, Heule, Biere, "Automated
# Reencoding of Boolean Formulas", HVC 2012) over the input's binary and
# ternary clauses.
#
# Some encodings state a product directly: for literals m1..mk and partial
# clauses R1..Rn, all k*n clauses (Ri | mj) are present (pairwise at-most-one
# constraints and transition relations of regular-language constraints are the
# usual sources). One fresh variable x replaces them with k + n clauses
#     (mj | x)  for every j        (Ri | -x)  for every i
# The REGRandom inputs of SAT Competition 2025 shrink from 474,496 clauses to
# 5,863 this way and from a timeout to a third of a second.
#
# Soundness. The removed clause (Ri | mj) is the resolvent of (mj | x) and
# (Ri | -x), so every model of the result is, on the input's variables, a
# model of the input. In the other direction a model of the input extends by
# x = "some mj is false": then every (mj | x) holds, and where x is true some
# mj is false, so every Ri holds because all k*n product clauses were input
# clauses. The match below therefore only ever pairs a row with a clause that
# is alive and is exactly Ri plus one literal, and one step removes exactly
# the clauses it matched. Stopping on a budget, skipping a literal or missing
# a match only loses reduction.
#
# The lane reads clauses of two or three literals over distinct variables;
# every other clause passes through untouched. Fast mode only: the rewritten
# formula carries no proof steps, and the caller replays a model against the
# input clauses.

# A backstop only: the tick allowance bounds the work, and a wall limit near
# the usual cost (0.5 s) made the lane miss on a busy machine.
WASSAT_BVA_MS = 8000
WASSAT_BVA_MIN_SMALL = 256
# Admission. Measured over the 800 inputs of SAT Competition 2025 and 2026
# (60 s, before these gates): the lane halved 35 formulas, decided two (the
# REGRandom pair, 81x and 119x smaller) and cost 1-17 s on the rest. A
# factored formula keeps about a clause per variable at least, so only a
# formula with many small clauses per variable can shrink much; and the lane
# publishes from a single bounded CDCL run, which is only the right tool when
# the factored formula is a different, far smaller problem.
WASSAT_BVA_MIN_DENSITY = 24
WASSAT_BVA_MIN_RATIO = 8
WASSAT_BVA_MAX_SMALL = 1500000
WASSAT_BVA_MAX_VARS = 3900000
# Match work: a base allowance plus a multiple of the small clauses.
WASSAT_BVA_TICKS = 30000000
WASSAT_BVA_TICKS_PER_CLAUSE = 30
# (row, literal) matches one growth round may record.
WASSAT_BVA_PAIRS = 2000000
# The one CDCL run on the factored formula.
WASSAT_BVA_SOLVE_CONFLICTS = 20000
WASSAT_BVA_SOLVE_PROPS = 5000000

# st slots.
#  0 heap size   1 clauses in the pool   2 occurrence entries   3 live clauses
#  4 new variables   5 ticks   6 steps   7 stop (1 budget, 2 deadline, 3 capacity)
#  8 small input clauses   9 clauses out   10 clauses in

-> wassat_bva_push(heap, st, key) (i64[] i64[] i64) i64
  i = st[0] ## i64
  while i > 0 && heap[(i - 1) >> 1] < key
    heap[i] = heap[(i - 1) >> 1]
    i = (i - 1) >> 1
  heap[i] = key
  st[0] += 1
  1

-> wassat_bva_pop(heap, st) (i64[] i64[]) i64
  top = heap[0] ## i64
  n = st[0] - 1 ## i64
  st[0] = n
  key = heap[n] ## i64
  i = 0 ## i64
  more = 1 ## i64
  while more == 1
    c = 2 * i + 1 ## i64
    if c >= n
      more = 0
    else
      c += 1 if c + 1 < n && heap[c + 1] > heap[c]
      if heap[c] > key
        heap[i] = heap[c]
        i = c
      else
        more = 0
  heap[i] = key
  top

# Slot of the unordered literal pair {a, b} in the pair table (linear probing;
# the table is sized so it never fills). An empty slot is claimed.
-> wassat_bva_slot(tkey, tmask, a, b) (i64[] i64 i64 i64) i64
  x = a ## i64
  y = b ## i64
  if b < a
    x = b
    y = a
  key = x * 16777216 + y + 1 ## i64
  h = ((x * 1000003) ^ (y * 998244353)) & tmask ## i64
  while tkey[h] != 0 && tkey[h] != key
    h = (h + 1) & tmask
  tkey[h] = key
  h

# Append the clause (a | b | c); c < 0 makes it binary. Literals are codes.
# Occurrence list of literal q: (q << 1) for binaries, (q << 1) | 1 for
# ternaries. A ternary clause is also on the list of each of its three pairs.
-> wassat_bva_add(cl, clen, alive, ohead, onext, ocls, ocnt, tkey, thead, tnext, tcls, tmask, st, a, b, c) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64[] i64 i64 i64) i64
  i = st[1] ## i64
  base = 3 * i ## i64
  cl[base] = a
  cl[base + 1] = b
  cl[base + 2] = c
  n = c < 0 ? 2 : 3 ## i64
  clen[i] = n
  alive[i] = 1
  j = 0
  while j < n
    q = cl[base + j] ## i64
    oi = (q << 1) | (n - 2) ## i64
    e = st[2] ## i64
    ocls[e] = i
    onext[e] = ohead[oi]
    ohead[oi] = e + 1
    st[2] = e + 1
    ocnt[q] += 1
    j += 1
  if n == 3
    h = wassat_bva_slot(tkey, tmask, a, b) ## i64
    tcls[base] = i
    tnext[base] = thead[h]
    thead[h] = base + 1
    h = wassat_bva_slot(tkey, tmask, a, c)
    tcls[base + 1] = i
    tnext[base + 1] = thead[h]
    thead[h] = base + 2
    h = wassat_bva_slot(tkey, tmask, b, c)
    tcls[base + 2] = i
    tnext[base + 2] = thead[h]
    thead[h] = base + 3
  st[1] = i + 1
  st[3] += 1
  i

-> wassat_bva_kill(cl, clen, alive, ocnt, odead, st, i) (i64[] i64[] i64[] i64[] i64[] i64[] i64) i64
  return 0 if alive[i] == 0
  alive[i] = 0
  base = 3 * i ## i64
  n = clen[i] ## i64
  j = 0
  while j < n
    q = cl[base + j] ## i64
    ocnt[q] -= 1
    odead[(q << 1) | (n - 2)] += 1
    j += 1
  st[3] -= 1
  1

# Unlink the dead clauses from one occurrence list.
-> wassat_bva_clean(ohead, onext, ocls, alive, odead, oi) (i64[] i64[] i64[] i64[] i64[] i64) i64
  prev = 0 ## i64
  e = ohead[oi] ## i64
  while e != 0
    nx = onext[e - 1] ## i64
    if alive[ocls[e - 1]] == 0
      if prev == 0
        ohead[oi] = nx
      else
        onext[prev - 1] = nx
    else
      prev = e
    e = nx
  odead[oi] = 0
  1

# 1 when the input clause at off (n literals) is one the lane rewrites.
-> wassat_bva_small(fla, off, n) (i64[] i64 i64) i64
  return 0 if n != 2 && n != 3
  a = fla[off] ## i64
  b = fla[off + 1] ## i64
  a = 0 - a if a < 0
  b = 0 - b if b < 0
  return 0 if a == b
  return 1 if n == 2
  c = fla[off + 2] ## i64
  c = 0 - c if c < 0
  return 0 if a == c || b == c
  1

# Small clauses, and the ternary ones among them: out[0], out[1].
-> wassat_bva_census(fla, fcs, fcl, nc, out) (i64[] i64[] i64[] i64 i64[]) i64
  n2 = 0 ## i64
  n3 = 0 ## i64
  ci = 0 ## i64
  while ci < nc
    n = fcl[ci] ## i64
    if (n == 2 || n == 3) && wassat_bva_small(fla, fcs[ci], n) == 1
      n2 += 1
      n3 += 1 if n == 3
    ci += 1
  out[0] = n2
  out[1] = n3
  n2

# The reduction itself. Fills the clause pool and st; returns the number of
# variables added.
-> wassat_bva_reduce(nv, maxnew, pcap, cl, clen, alive, ohead, onext, ocls, ocnt, odead, tkey, thead, tnext, tcls, tmask, st, budget, deadline) (i64 i64 i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64[] i64 i64) i64
  nlc = 2 * (nv + maxnew + 2) ## i64
  heap = i64[nlc + 3 * maxnew + 64]
  maxocc = 0 ## i64
  q = 2 ## i64
  while q < nlc
    if ocnt[q] >= 3
      z = wassat_bva_push(heap, st, (ocnt[q] << 24) | q)
      maxocc = ocnt[q] if ocnt[q] > maxocc
    q += 1
  rcap = maxocc + 16 ## i64
  rowc = i64[rcap]
  rch = i64[rcap]
  rowc2 = i64[rcap]
  rch2 = i64[rcap]
  mlits = i64[rcap + 16]
  pairs = WASSAT_BVA_PAIRS ## i64
  pl = i64[pairs + 8]
  pr = i64[pairs + 8]
  pd = i64[pairs + 8]
  touched = i64[pairs + 8]
  ncap = 2 * pairs ## i64
  nd = i64[ncap + 8]
  npv = i64[ncap + 8]
  pcnt = i64[nlc]
  seen = i64[nlc]
  inm = i64[nlc]
  stamp = 0 ## i64
  stepid = 0 ## i64
  ticks = 0 ## i64
  nx = 0 ## i64
  stop = 0 ## i64
  while st[0] > 0 && stop == 0
    key = wassat_bva_pop(heap, st) ## i64
    l = key & 16777215 ## i64
    cnt = key >> 24 ## i64
    if cnt != ocnt[l]
      z = wassat_bva_push(heap, st, (ocnt[l] << 24) | l) if ocnt[l] >= 3
    elsif cnt >= 3 && cnt <= rcap
      st[6] += 1
      nr = 0 ## i64
      side = 0 ## i64
      while side < 2
        oi = (l << 1) | side ## i64
        z = wassat_bva_clean(ohead, onext, ocls, alive, odead, oi) if odead[oi] > 0
        e = ohead[oi] ## i64
        while e != 0
          rowc[nr] = ocls[e - 1]
          rch[nr] = 0
          nr += 1
          e = onext[e - 1]
        side += 1
      stepid += 1
      inm[l] = stepid
      mlits[0] = l
      nm = 1 ## i64
      nn = 0 ## i64
      grow = 1 ## i64
      while grow == 1
        np = 0 ## i64
        nt = 0 ## i64
        r = 0 ## i64
        while r < nr && np < pairs
          cc = rowc[r] ## i64
          base = 3 * cc ## i64
          k = clen[cc] ## i64
          stamp += 1
          # The rest of the row: a, and b for a ternary row.
          a = 0 - 1 ## i64
          b = 0 - 1 ## i64
          j = 0 ## i64
          while j < k
            q = cl[base + j]
            if q != l
              if a < 0
                a = q
              else
                b = q
            j += 1
          ticks += 1
          if alive[cc] == 0
            # A copy another row already dropped: it matches nothing.
            k = 0
          elsif k == 2
            # Every other binary clause holding a is (a | l2).
            oi = a << 1
            z = wassat_bva_clean(ohead, onext, ocls, alive, odead, oi) if odead[oi] > 0
            e = ohead[oi]
            while e != 0 && np < pairs
              d = ocls[e - 1] ## i64
              e = onext[e - 1]
              ticks += 1
              if d != cc
                l2 = cl[3 * d] == a ? cl[3 * d + 1] : cl[3 * d] ## i64
                # A second copy of the row itself: drop it, or it would be
                # counted as a row of its own and then removed only once.
                z = wassat_bva_kill(cl, clen, alive, ocnt, odead, st, d) if l2 == l
                if l2 != l && l2 != (l ^ 1) && inm[l2] != stepid && seen[l2] != stamp
                  seen[l2] = stamp
                  pl[np] = l2
                  pr[np] = r
                  pd[np] = d
                  np += 1
                  if pcnt[l2] == 0
                    touched[nt] = l2
                    nt += 1
                  pcnt[l2] += 1
          elsif k == 3
            # Every other ternary clause holding the pair is (a | b | l2).
            h = wassat_bva_slot(tkey, tmask, a, b) ## i64
            prev = 0 ## i64
            e = thead[h]
            while e != 0 && np < pairs
              d = tcls[e - 1]
              nxe = tnext[e - 1] ## i64
              ticks += 1
              if alive[d] == 0
                if prev == 0
                  thead[h] = nxe
                else
                  tnext[prev - 1] = nxe
              else
                prev = e
                if d != cc
                  db = 3 * d ## i64
                  l2 = cl[db]
                  l2 = cl[db + 1] if l2 == a || l2 == b
                  l2 = cl[db + 2] if l2 == a || l2 == b
                  z = wassat_bva_kill(cl, clen, alive, ocnt, odead, st, d) if l2 == l
                  if l2 != l && l2 != (l ^ 1) && inm[l2] != stepid && seen[l2] != stamp
                    seen[l2] = stamp
                    pl[np] = l2
                    pr[np] = r
                    pd[np] = d
                    np += 1
                    if pcnt[l2] == 0
                      touched[nt] = l2
                      nt += 1
                    pcnt[l2] += 1
              e = nxe
          r += 1
        best = 0 - 1 ## i64
        bc = 0 ## i64
        t = 0 ## i64
        while t < nt
          q = touched[t]
          if pcnt[q] > bc || (pcnt[q] == bc && q < best)
            best = q
            bc = pcnt[q]
          pcnt[q] = 0
          t += 1
        cur = nm * nr - nm - nr ## i64
        nw = (nm + 1) * bc - (nm + 1) - bc ## i64
        if best < 0 || nw <= cur || nn + bc > ncap || nm >= rcap
          grow = 0
        else
          r2 = 0 ## i64
          i = 0 ## i64
          while i < np
            if pl[i] == best
              r = pr[i]
              nd[nn] = pd[i]
              npv[nn] = rch[r]
              nn += 1
              rowc2[r2] = rowc[r]
              rch2[r2] = nn
              r2 += 1
            i += 1
          i = 0
          while i < r2
            rowc[i] = rowc2[i]
            rch[i] = rch2[i]
            i += 1
          nr = r2
          mlits[nm] = best
          inm[best] = stepid
          nm += 1
        if ticks > budget
          grow = 0
          stop = 1
      if nm >= 2 && nm * nr - nm - nr > 0
        if nx >= maxnew || st[1] + nm + nr > pcap
          stop = 3
        else
          x = nv + 1 + nx ## i64
          nx += 1
          xp = x << 1 ## i64
          xn = xp | 1 ## i64
          r = 0
          while r < nr
            cc = rowc[r]
            base = 3 * cc
            k = clen[cc]
            a = 0 - 1 ## i64
            b = 0 - 1 ## i64
            j = 0
            while j < k
              q = cl[base + j]
              if q != l
                if a < 0
                  a = q
                else
                  b = q
              j += 1
            z = wassat_bva_kill(cl, clen, alive, ocnt, odead, st, cc)
            n = rch[r] ## i64
            while n != 0
              z = wassat_bva_kill(cl, clen, alive, ocnt, odead, st, nd[n - 1])
              n = npv[n - 1]
            if b < 0
              z = wassat_bva_add(cl, clen, alive, ohead, onext, ocls, ocnt, tkey, thead, tnext, tcls, tmask, st, a, xn, 0 - 1)
            else
              z = wassat_bva_add(cl, clen, alive, ohead, onext, ocls, ocnt, tkey, thead, tnext, tcls, tmask, st, a, b, xn)
            r += 1
          i = 0
          while i < nm
            z = wassat_bva_add(cl, clen, alive, ohead, onext, ocls, ocnt, tkey, thead, tnext, tcls, tmask, st, mlits[i], xp, 0 - 1)
            i += 1
          z = wassat_bva_push(heap, st, (ocnt[xp] << 24) | xp) if ocnt[xp] >= 3
          z = wassat_bva_push(heap, st, (ocnt[xn] << 24) | xn) if ocnt[xn] >= 3
          z = wassat_bva_push(heap, st, (ocnt[l] << 24) | l) if ocnt[l] >= 3
      if stop == 0 && deadline > 0 && (st[6] & 15) == 0 && clock_ms() >= deadline
        stop = 2
  st[4] = nx
  st[5] = ticks
  st[7] = stop
  nx

# Returns nil when the lane declines the shape, else { "formula", "work" (st) }
# where "formula" (more variables, fewer clauses) is nil when the product
# structure found is too small to matter.
# min_ratio: the result is kept only when it has at most 1/min_ratio of the
# input's clauses. min_small: fewest binary and ternary clauses worth reading.
# min_density: fewest such clauses per variable.
-> wassat_bva_lift(formula, deadline = 0, min_ratio = WASSAT_BVA_MIN_RATIO, min_small = WASSAT_BVA_MIN_SMALL, min_density = WASSAT_BVA_MIN_DENSITY)
  return nil unless formula.has_key?("flat_ncl")
  nv = formula["nvars"]
  nc = formula["flat_ncl"]
  return nil if nv < 8 || nv > WASSAT_BVA_MAX_VARS
  fla = formula["flat_lits"]
  fcs = formula["flat_offs"]
  fcl = formula["flat_lens"]
  # No formula with fewer clauses than the density asks for can pass.
  return nil if nc < min_density * nv
  cen = i64[2]
  z = wassat_bva_census(fla, fcs, fcl, nc, cen)
  nsmall = cen[0]
  nsmall3 = cen[1]
  return nil if nsmall < min_small || nsmall > WASSAT_BVA_MAX_SMALL || nsmall < min_density * nv
  # A result is kept only below nc / min_ratio clauses, and a step removes
  # small clauses only.
  return nil if (nc - nsmall) * min_ratio >= nc
  maxnew = nv + 1024
  pcap = nsmall + (nsmall >> 1) + 1024
  nlc = 2 * (nv + maxnew + 2)
  st = i64[16]
  cl = i64[3 * pcap]
  clen = i64[pcap]
  alive = i64[pcap]
  ohead = i64[2 * nlc]
  ocnt = i64[nlc]
  odead = i64[2 * nlc]
  onext = i64[3 * pcap]
  ocls = i64[3 * pcap]
  # Pair table for ternary clauses: at most three pairs a clause, half full.
  tsize = 1024
  if nsmall3 > 0
    while tsize < 6 * pcap
      tsize = tsize << 1
  tmask = tsize - 1
  tkey = i64[tsize]
  thead = i64[tsize]
  tnext = i64[3 * pcap]
  tcls = i64[3 * pcap]
  ci = 0
  while ci < nc
    off = fcs[ci]
    n = fcl[ci]
    if wassat_bva_small(fla, off, n) == 1
      a = fla[off]
      b = fla[off + 1]
      ca = a > 0 ? a << 1 : ((0 - a) << 1) | 1
      cb = b > 0 ? b << 1 : ((0 - b) << 1) | 1
      cc = 0 - 1
      if n == 3
        c = fla[off + 2]
        cc = c > 0 ? c << 1 : ((0 - c) << 1) | 1
      z = wassat_bva_add(cl, clen, alive, ohead, onext, ocls, ocnt, tkey, thead, tnext, tcls, tmask, st, ca, cb, cc)
    ci += 1
  st[8] = nsmall
  st[10] = nc
  budget = WASSAT_BVA_TICKS + WASSAT_BVA_TICKS_PER_CLAUSE * nsmall
  nx = wassat_bva_reduce(nv, maxnew, pcap, cl, clen, alive, ohead, onext, ocls, ocnt, odead, tkey, thead, tnext, tcls, tmask, st, budget, deadline)
  live = st[3]
  outc = nc - nsmall + live
  st[9] = outc
  return { "formula": nil, "work": st } if nx == 0 || outc * min_ratio > nc
  # Count literals, then fill: untouched clauses first, then the pool.
  outl = 0
  ci = 0
  while ci < nc
    outl += fcl[ci] if wassat_bva_small(fla, fcs[ci], fcl[ci]) == 0
    ci += 1
  np = st[1]
  i = 0
  while i < np
    outl += clen[i] if alive[i] == 1
    i += 1
  out = i64[outl + 1]
  off2 = i64[outc + 1]
  len2 = i64[outc + 1]
  p = 0
  c2 = 0
  ci = 0
  while ci < nc
    off = fcs[ci]
    n = fcl[ci]
    if wassat_bva_small(fla, off, n) == 0
      off2[c2] = p
      len2[c2] = n
      j = 0
      while j < n
        out[p] = fla[off + j]
        p += 1
        j += 1
      c2 += 1
    ci += 1
  i = 0
  while i < np
    if alive[i] == 1
      n = clen[i]
      off2[c2] = p
      len2[c2] = n
      j = 0
      while j < n
        q = cl[3 * i + j]
        out[p] = (q & 1) == 0 ? q >> 1 : 0 - (q >> 1)
        p += 1
        j += 1
      c2 += 1
    i += 1
  lifted = { "nvars": nv + nx, "nclauses": c2, "clauses": [], "boxed": false,
    "flat_lits": out, "flat_offs": off2, "flat_lens": len2,
    "flat_ncl": c2, "flat_nlits": p }
  { "formula": lifted, "work": st }
