# Parity-sum refutation: a set of parity equations whose sum is 0 = 1.
#
# Tseitin formulas put one parity constraint on every vertex of a graph, over
# the edges at that vertex. Each edge variable occurs in exactly two
# constraints, so adding up all constraints of a connected component cancels
# every variable; when the right-hand sides add up to 1 the component is
# contradictory. Resolution needs exponentially many clauses for that on
# grids and expanders, the sum needs one pass (tseitin_grid_n400_m400 and
# tseitin_d3_n100000 of SAT Competition 2025: a timeout, then 0.1 s).
#
# The lane reads parity equations from the ORIGINAL clauses:
#   XOR    over k = 1..5 variables: all 2^(k-1) clauses forbidding the
#          assignments of one parity (units and equivalences are k = 1, 2);
#   CARD   "exactly a of the literals L" in the binomial encoding, reduced
#          mod 2 (see wassat_parity_cardinality below).
# It then removes, repeatedly, every equation holding a variable that occurs
# in no other remaining equation (such an equation can never be part of a
# cancelling sum), splits what is left into components connected by shared
# variables, and looks for a component in which every variable occurs an even
# number of times and the right-hand sides sum to 1.
#
# Soundness. Every equation is implied by input clauses: the 2^(k-1) clauses
# of an XOR forbid exactly the assignments violating it, and extra clauses on
# the same variables only strengthen the formula. A certificate is a set of
# implied equations whose left-hand sides cancel mod 2 and whose right-hand
# sides do not, which no assignment satisfies. Which equations were removed,
# or missed, or how components were formed cannot make a certificate wrong:
# the evenness of every variable and the sum are counted over exactly the
# equations of the component that is reported.
# This is a sum of all equations of a component, not Gaussian elimination: a
# contradiction that needs a proper subset of a component is not found.
#
# Fast mode only: the verdict carries no clausal proof.

WASSAT_PARITY_SUM_MAX_CLAUSES = 8000000
WASSAT_PARITY_SUM_MAX_VARS = 8000000

# st slots.
#  0 var-set entries   1 XOR equations   2 equations after peeling
#  3 components        4 refuting components   5 equations in the first refutation
#  6 locally contradictory var-set (all assignments forbidden)   7 cardinality equations
#  8 stop (1 capacity, 2 deadline)   9 ticks

# Slot of the sorted variable tuple in the table: index + 1 when present,
# -(free slot) - 1 otherwise.
-> wassat_parity_at(tab, ev, mask, k, a, b, c, d, e) (i64[] i64[] i64 i64 i64 i64 i64 i64 i64) i64
  h = k ## i64
  h = ((h * 1000003) + a) & mask
  h = ((h * 1000003) + b) & mask
  h = ((h * 1000003) + c) & mask
  h = ((h * 1000003) + d) & mask
  h = ((h * 1000003) + e) & mask
  while tab[h] != 0
    base = (tab[h] - 1) * 5 ## i64
    return tab[h] if ev[base] == a && ev[base + 1] == b && ev[base + 2] == c && ev[base + 3] == d && ev[base + 4] == e
    h = (h + 1) & mask
  0 - h - 1

-> wassat_parity_find(par, x) (i64[] i64) i64
  r = x ## i64
  while par[r] != r
    r = par[r]
  while par[x] != r
    nx = par[x] ## i64
    par[x] = r
    x = nx
  r

# Peel, split and sum. Equations: eoff/elen index evars (variable ids, each at
# most once per equation), erhs is 0 or 1. Returns 1 on a refuting component.
-> wassat_parity_sum_close(nv, ne, eoff, elen, erhs, evars, st, members) (i64 i64 i64[] i64[] i64[] i64[] i64[] i8[]) i64
  # Occurrences per variable.
  vst = i64[nv + 3]
  i = 0 ## i64
  while i < ne
    j = 0 ## i64
    while j < elen[i]
      vst[evars[eoff[i] + j] + 1] += 1
      j += 1
    i += 1
  v = 0 ## i64
  while v <= nv
    vst[v + 1] += vst[v]
    v += 1
  inc = i64[vst[nv + 1] + 1]
  fill = i64[nv + 2]
  cnt = i64[nv + 2]
  i = 0
  while i < ne
    j = 0
    while j < elen[i]
      x = evars[eoff[i] + j] ## i64
      inc[vst[x] + fill[x]] = i
      fill[x] += 1
      cnt[x] += 1
      j += 1
    i += 1
  z = ccall("w_value_free_w", fill)
  # Peel equations that hold a variable no other live equation holds.
  dead = i64[ne + 1]
  queue = i64[ne + 1]
  qn = 0 ## i64
  i = 0
  while i < ne
    lone = 0 ## i64
    j = 0
    while j < elen[i]
      lone = 1 if cnt[evars[eoff[i] + j]] == 1
      j += 1
    if lone == 1
      dead[i] = 1
      queue[qn] = i
      qn += 1
    i += 1
  qh = 0 ## i64
  while qh < qn
    i = queue[qh]
    qh += 1
    j = 0
    while j < elen[i]
      x = evars[eoff[i] + j]
      cnt[x] -= 1
      if cnt[x] == 1
        t = vst[x] ## i64
        while t < vst[x + 1]
          g = inc[t] ## i64
          if dead[g] == 0
            dead[g] = 1
            queue[qn] = g
            qn += 1
          t += 1
      j += 1
  z = ccall("w_value_free_w", queue)
  st[2] = ne - qn
  if qn == ne
    z = ccall("w_value_free_w", dead)
    z = ccall("w_value_free_w", cnt)
    z = ccall("w_value_free_w", inc)
    z = ccall("w_value_free_w", vst)
    return 0
  # Components of the live equations.
  par = i64[ne + 1]
  i = 0
  while i < ne
    par[i] = i
    i += 1
  v = 1
  while v <= nv
    if cnt[v] > 0
      first = 0 - 1 ## i64
      t = vst[v]
      while t < vst[v + 1]
        g = inc[t]
        if dead[g] == 0
          if first < 0
            first = wassat_parity_find(par, g)
          else
            r = wassat_parity_find(par, g) ## i64
            par[r] = first if r != first
        t += 1
    v += 1
  # Right-hand sides per final component; a variable of odd count rules its
  # component out (counted once all unions are made).
  sum = i64[ne + 1]
  size = i64[ne + 1]
  bad = i64[ne + 1]
  i = 0
  while i < ne
    if dead[i] == 0
      r = wassat_parity_find(par, i)
      sum[r] = sum[r] ^ erhs[i]
      size[r] += 1
    i += 1
  v = 1
  while v <= nv
    if cnt[v] > 0 && (cnt[v] & 1) == 1
      t = vst[v]
      while t < vst[v + 1]
        g = inc[t]
        bad[wassat_parity_find(par, g)] = 1 if dead[g] == 0
        t += 1
    v += 1
  z = ccall("w_value_free_w", cnt)
  z = ccall("w_value_free_w", inc)
  z = ccall("w_value_free_w", vst)
  found = 0 ## i64
  root = 0 - 1 ## i64
  i = 0
  while i < ne
    if dead[i] == 0 && par[i] == i
      st[3] += 1
      if bad[i] == 0 && sum[i] == 1
        st[4] += 1
        if found == 0
          st[5] = size[i]
          root = i
        found = 1
    i += 1
  if found == 1 && members.size >= ne
    i = 0
    while i < ne
      members[i] = 1 if dead[i] == 0 && wassat_parity_find(par, i) == root
      i += 1
  z = ccall("w_value_free_w", bad)
  z = ccall("w_value_free_w", size)
  z = ccall("w_value_free_w", sum)
  z = ccall("w_value_free_w", par)
  z = ccall("w_value_free_w", dead)
  found

# Does the clause over these n literal codes (any order) exist? Returns its
# index + 1 in the clause index, or 0. xs is scratch of at least 5 slots.
-> wassat_parity_clause(ctab, ck, cmask, lits, n, pick, flip, xs) (i64[] i64[] i64 i64[] i64 i64 i64 i64[]) i64
  # The clause is the literals of `lits` selected by the bits of `pick`,
  # each XORed with flip (0, or 1 for the negated literals).
  m = 0 ## i64
  j = 0 ## i64
  while j < n
    if ((pick >> j) & 1) == 1
      x = lits[j] ^ flip ## i64
      k = m ## i64
      while k > 0 && xs[k - 1] > x
        xs[k] = xs[k - 1]
        k -= 1
      xs[k] = x
      m += 1
    j += 1
  j = m
  while j < 5
    xs[j] = 0
    j += 1
  at = wassat_parity_at(ctab, ck, cmask, m, xs[0], xs[1], xs[2], xs[3], xs[4]) ## i64
  return at if at > 0
  0

-> wassat_parity_bits(x) (i64) i64
  ccall_nobox("__w_bit_ctpop_u64", x) ## i64

# Exact cardinality constraints in the binomial encoding, as parity equations.
# "At least a of the n literals L" is every clause over n - a + 1 of them
# (among any n - a + 1 literals one is true); "at most a" is every clause over
# a + 1 of their negations. Both sides present means exactly a, hence
#     sum of the variables of L  =  a + (negative literals in L)   (mod 2).
# Found by growing a set L from one clause of s = 3..5 literals while every
# s-subset of L stays a clause, up to 8 literals; a + 1 must be at most 5 too.
# Appends to kv (variables, 8 slots an equation) / kn / kr; returns the count.
-> wassat_parity_cardinality(fla, fcs, fcl, nc, nv, kv, kn, kr, kcap, st, deadline) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64 i64[] i64) i64
  nl = 2 * nv + 4 ## i64
  deg = i32[nl + 2]
  xs = i64[8]
  nmid = 0 ## i64
  ci = 0 ## i64
  while ci < nc
    n = fcl[ci] ## i64
    if n >= 3 && n <= 5
      off = fcs[ci] ## i64
      j = 0 ## i64
      while j < n
        l = fla[off + j] ## i64
        x = l > 0 ? l << 1 : ((0 - l) << 1) | 1 ## i64
        k = j ## i64
        while k > 0 && xs[k - 1] > x
          xs[k] = xs[k - 1]
          k -= 1
        xs[k] = x
        j += 1
      ok = 1 ## i64
      j = 1
      while j < n
        ok = 0 if (xs[j] >> 1) == (xs[j - 1] >> 1)
        j += 1
      if ok == 1
        nmid += 1
        j = 0
        while j < n
          deg[xs[j]] = deg[xs[j]] + 1 if deg[xs[j]] < 1000000
          j += 1
    ci += 1
    if (ci & 65535) == 0 && deadline > 0 && clock_ms() >= deadline
      z = ccall("w_value_free_w", xs)
      z = ccall("w_value_free_w", deg)
      st[8] = 2
      return 0
  if nmid < 8
    z = ccall("w_value_free_w", xs)
    z = ccall("w_value_free_w", deg)
    return 0
  nkeep = 0 ## i64
  ci = 0
  while ci < nc
    n = fcl[ci] ## i64
    if n >= 3 && n <= 5
      off = fcs[ci] ## i64
      keep = 1 ## i64
      j = 0 ## i64
      while j < n
        l = fla[off + j] ## i64
        v2 = (l > 0 ? l : 0 - l) << 1 ## i64
        if deg[v2] < 3 || deg[v2 | 1] < 3
          keep = 0
          j = n
        else
          j += 1
      nkeep += 1 if keep == 1
    ci += 1
    if (ci & 65535) == 0 && deadline > 0 && clock_ms() >= deadline
      z = ccall("w_value_free_w", xs)
      z = ccall("w_value_free_w", deg)
      st[8] = 2
      return 0
  if nkeep < 8
    z = ccall("w_value_free_w", xs)
    z = ccall("w_value_free_w", deg)
    return 0
  csize = 1024 ## i64
  while csize < 2 * nkeep
    csize = csize << 1
  cmask = csize - 1 ## i64
  ctab = i64[csize]
  ck = i64[5 * nkeep + 5]
  clen = i64[nkeep + 1]
  ost = i64[nl + 2]
  ne = 0 ## i64
  ci = 0
  while ci < nc
    n = fcl[ci] ## i64
    if n >= 3 && n <= 5
      off = fcs[ci] ## i64
      keep = 1 ## i64
      j = 0 ## i64
      while j < n
        l = fla[off + j] ## i64
        v2 = (l > 0 ? l : 0 - l) << 1 ## i64
        if deg[v2] < 3 || deg[v2 | 1] < 3
          keep = 0
          j = n
        else
          x = l > 0 ? v2 : (v2 | 1) ## i64
          k = j ## i64
          while k > 0 && xs[k - 1] > x
            xs[k] = xs[k - 1]
            k -= 1
          xs[k] = x
          j += 1
      if keep == 1
        ok = 1 ## i64
        j = 1
        while j < n
          ok = 0 if (xs[j] >> 1) == (xs[j - 1] >> 1)
          j += 1
        if ok == 1 && ne < nkeep
          j = n
          while j < 5
            xs[j] = 0
            j += 1
          at = wassat_parity_at(ctab, ck, cmask, n, xs[0], xs[1], xs[2], xs[3], xs[4]) ## i64
          if at <= 0
            ctab[0 - at - 1] = ne + 1
            j = 0
            while j < 5
              ck[5 * ne + j] = xs[j]
              j += 1
            clen[ne] = n
            j = 0
            while j < n
              ost[xs[j] + 1] += 1
              j += 1
            ne += 1
    ci += 1
    if (ci & 65535) == 0 && deadline > 0 && clock_ms() >= deadline
      z = ccall("w_value_free_w", ost)
      z = ccall("w_value_free_w", clen)
      z = ccall("w_value_free_w", ck)
      z = ccall("w_value_free_w", ctab)
      z = ccall("w_value_free_w", xs)
      z = ccall("w_value_free_w", deg)
      st[8] = 2
      return 0
  z = ccall("w_value_free_w", deg)
  if ne < 8
    z = ccall("w_value_free_w", ost)
    z = ccall("w_value_free_w", xs)
    z = ccall("w_value_free_w", clen)
    z = ccall("w_value_free_w", ck)
    z = ccall("w_value_free_w", ctab)
    return 0
  c = 0 ## i64
  while c <= nl
    ost[c + 1] += ost[c]
    c += 1
  occ = i64[ost[nl] + 1]
  ofill = i64[nl + 2]
  i = 0 ## i64
  while i < ne
    j = 0
    while j < clen[i]
      x = ck[5 * i + j]
      occ[ost[x] + ofill[x]] = i
      ofill[x] += 1
      j += 1
    i += 1
    if (i & 65535) == 0 && deadline > 0 && clock_ms() >= deadline
      z = ccall("w_value_free_w", ofill)
      z = ccall("w_value_free_w", occ)
      z = ccall("w_value_free_w", ost)
      z = ccall("w_value_free_w", xs)
      z = ccall("w_value_free_w", clen)
      z = ccall("w_value_free_w", ck)
      z = ccall("w_value_free_w", ctab)
      st[8] = 2
      return 0
  z = ccall("w_value_free_w", ofill)
  covered = i64[ne + 1]
  inl = i64[nl + 2]
  tried = i64[nl + 2]
  lits = i64[10]
  stamp = 0 ## i64
  ticks = 0 ## i64
  budget = 3000000 + 6 * ne ## i64
  nk = 0 ## i64
  i = 0
  while i < ne && nk < kcap && ticks < budget
    if covered[i] == 0
      s = clen[i] ## i64
      n = s
      stamp += 1
      j = 0
      while j < s
        lits[j] = ck[5 * i + j]
        inl[lits[j]] = stamp
        j += 1
      grew = 1 ## i64
      while grew == 1 && n < 8
        grew = 0
        # Candidates: the one outside literal of a clause holding one fixed
        # literal of L (the rarest, to keep the scan short) and s - 2 more.
        a = lits[0] ## i64
        j = 1
        while j < n
          a = lits[j] if ost[lits[j] + 1] - ost[lits[j]] < ost[a + 1] - ost[a]
          j += 1
        t = ost[a] ## i64
        while t < ost[a + 1] && grew == 0
          g = occ[t] ## i64
          t += 1
          ticks += 1
          if clen[g] == s
            out = 0 ## i64
            d = 0 ## i64
            j = 0
            while j < s
              x = ck[5 * g + j]
              if inl[x] != stamp
                out += 1
                d = x
              j += 1
            if out == 1 && tried[d] != stamp && inl[d ^ 1] != stamp
              tried[d] = stamp
              # d joins when every s - 1 literals of L make a clause with it.
              lits[n] = d
              full = (1 << n) - 1 ## i64
              good = 1 ## i64
              pick = 0 ## i64
              while pick <= full && good == 1
                if wassat_parity_bits(pick) == s - 1
                  ticks += 1
                  good = 0 if wassat_parity_clause(ctab, ck, cmask, lits, n + 1, pick | (1 << n), 0, xs) == 0
                pick += 1
              if good == 1
                inl[d] = stamp
                n += 1
                grew = 1
                stamp += 1
                j = 0
                while j < n
                  inl[lits[j]] = stamp
                  j += 1
      if n > s
        need = n - s + 1 ## i64
        up = need + 1 ## i64
        if up <= 5
          full = (1 << n) - 1
          good = 1
          pick = 0
          while pick <= full && good == 1
            if wassat_parity_bits(pick) == up
              ticks += 1
              good = 0 if wassat_parity_clause(ctab, ck, cmask, lits, n, pick, 1, xs) == 0
            pick += 1
          if good == 1
            # Mark both clause families so the mirrored description of the
            # same constraint (exactly n - a of the negations) is not added.
            neg = 0 ## i64
            pick = 0
            while pick <= full
              b = wassat_parity_bits(pick) ## i64
              if b == s
                at = wassat_parity_clause(ctab, ck, cmask, lits, n, pick, 0, xs)
                covered[at - 1] = 1 if at > 0
              if b == up
                at = wassat_parity_clause(ctab, ck, cmask, lits, n, pick, 1, xs)
                covered[at - 1] = 1 if at > 0
              pick += 1
            j = 0
            while j < n
              kv[8 * nk + j] = lits[j] >> 1
              neg += lits[j] & 1
              j += 1
            kn[nk] = n
            kr[nk] = (need + neg) & 1
            nk += 1
    i += 1
    if nk == 0 && ticks >= 200000
      i = ne
    elsif (i & 4095) == 0 && deadline > 0 && clock_ms() >= deadline
      st[8] = 2
      i = ne
  z = ccall("w_value_free_w", lits)
  z = ccall("w_value_free_w", tried)
  z = ccall("w_value_free_w", inl)
  z = ccall("w_value_free_w", covered)
  z = ccall("w_value_free_w", occ)
  z = ccall("w_value_free_w", ost)
  z = ccall("w_value_free_w", xs)
  z = ccall("w_value_free_w", clen)
  z = ccall("w_value_free_w", ck)
  z = ccall("w_value_free_w", ctab)
  st[9] = ticks
  st[7] = nk
  nk

-> wassat_parity_widths(fcl, nc, wc) (i64[] i64 i64[]) i64
  ci = 0 ## i64
  while ci < nc
    n = fcl[ci] ## i64
    wc[n] += 1 if n >= 1 && n <= 5
    ci += 1
  0

# Two-hash 2-bit sign-complement prefilter for huge formulas (nsmall > 65536).
# Every k-XOR (k in 2..5) and every locally contradictory k-tuple has at least
# one clause with sg[0] == 0 and at least one with sg[0] == 1 on the exact same
# sorted variable tuple. Units (k == 1) are tracked in umask[1..nv].
# Returns candidate count in 2..5, -1 on deadline, -2 on unit clash (meta[0]).
-> wassat_parity_prefilter(fla, fcs, fcl, nc, nv, bf, bmask, umask, meta, deadline) (i64[] i64[] i64[] i64 i64 i64[] i64 i8[] i64[] i64) i64
  xs = i64[8]
  sg = i64[8]
  nu = 0 ## i64
  any_both = 0 ## i64
  ci = 0 ## i64
  while ci < nc
    n = fcl[ci] ## i64
    if n == 1
      l = fla[fcs[ci]] ## i64
      v = l < 0 ? 0 - l : l ## i64
      bit_u = l < 0 ? 2 : 1 ## i64
      prev = umask[v] ## i64
      nu += 1 if prev == 0
      nv_u = prev | bit_u ## i64
      umask[v] = nv_u
      if nv_u == 3
        meta[0] = v
        meta[1] = nu
        z = ccall("w_value_free_w", sg)
        z = ccall("w_value_free_w", xs)
        return 0 - 2
    elsif n >= 2 && n <= 5
      off = fcs[ci] ## i64
      ok = 1 ## i64
      j = 0 ## i64
      while j < n
        l = fla[off + j] ## i64
        x = l < 0 ? 0 - l : l ## i64
        s = l < 0 ? 1 : 0 ## i64
        k = j ## i64
        while k > 0 && xs[k - 1] > x
          xs[k] = xs[k - 1]
          sg[k] = sg[k - 1]
          k -= 1
        xs[k] = x
        sg[k] = s
        j += 1
      j = 1
      while j < n
        ok = 0 if xs[j] == xs[j - 1]
        j += 1
      if ok == 1
        j = n
        while j < 5
          xs[j] = 0
          j += 1
        h1 = n ## i64
        h1 = ((h1 * 1000003) + xs[0]) & bmask
        h1 = ((h1 * 1000003) + xs[1]) & bmask
        h1 = ((h1 * 1000003) + xs[2]) & bmask
        h1 = ((h1 * 1000003) + xs[3]) & bmask
        h1 = ((h1 * 1000003) + xs[4]) & bmask
        h2 = (n * 2654435761) & bmask ## i64
        h2 = ((h2 * 998244353) ^ xs[0]) & bmask
        h2 = ((h2 * 998244353) ^ xs[1]) & bmask
        h2 = ((h2 * 998244353) ^ xs[2]) & bmask
        h2 = ((h2 * 998244353) ^ xs[3]) & bmask
        h2 = ((h2 * 998244353) ^ xs[4]) & bmask
        sbit = sg[0] == 0 ? 1 : 2 ## i64
        w1 = h1 >> 4 ## i64
        sh1 = (h1 & 15) << 1 ## i64
        nw1 = bf[w1] | (sbit << sh1) ## i64
        bf[w1] = nw1
        any_both = 1 if ((nw1 >> sh1) & 3) == 3
        w2 = h2 >> 4 ## i64
        sh2 = (h2 & 15) << 1 ## i64
        bf[w2] = bf[w2] | (sbit << sh2)
    ci += 1
    if (ci & 65535) == 0 && deadline > 0 && clock_ms() >= deadline
      z = ccall("w_value_free_w", sg)
      z = ccall("w_value_free_w", xs)
      return 0 - 1
  meta[1] = nu
  if any_both == 0
    z = ccall("w_value_free_w", sg)
    z = ccall("w_value_free_w", xs)
    return 0
  ncand = 0 ## i64
  ci = 0
  while ci < nc
    n = fcl[ci]
    if n >= 2 && n <= 5
      off = fcs[ci]
      ok = 1
      j = 0
      while j < n
        l = fla[off + j]
        x = l < 0 ? 0 - l : l
        k = j
        while k > 0 && xs[k - 1] > x
          xs[k] = xs[k - 1]
          k -= 1
        xs[k] = x
        j += 1
      j = 1
      while j < n
        ok = 0 if xs[j] == xs[j - 1]
        j += 1
      if ok == 1
        j = n
        while j < 5
          xs[j] = 0
          j += 1
        h1 = n
        h1 = ((h1 * 1000003) + xs[0]) & bmask
        h1 = ((h1 * 1000003) + xs[1]) & bmask
        h1 = ((h1 * 1000003) + xs[2]) & bmask
        h1 = ((h1 * 1000003) + xs[3]) & bmask
        h1 = ((h1 * 1000003) + xs[4]) & bmask
        b1 = (bf[h1 >> 4] >> ((h1 & 15) << 1)) & 3 ## i64
        if b1 == 3
          h2 = (n * 2654435761) & bmask
          h2 = ((h2 * 998244353) ^ xs[0]) & bmask
          h2 = ((h2 * 998244353) ^ xs[1]) & bmask
          h2 = ((h2 * 998244353) ^ xs[2]) & bmask
          h2 = ((h2 * 998244353) ^ xs[3]) & bmask
          h2 = ((h2 * 998244353) ^ xs[4]) & bmask
          b2 = (bf[h2 >> 4] >> ((h2 & 15) << 1)) & 3 ## i64
          ncand += 1 if b2 == 3
    ci += 1
    if (ci & 65535) == 0 && deadline > 0 && clock_ms() >= deadline
      z = ccall("w_value_free_w", sg)
      z = ccall("w_value_free_w", xs)
      return 0 - 1
  z = ccall("w_value_free_w", sg)
  z = ccall("w_value_free_w", xs)
  ncand

-> wassat_parity_collect_filtered(fla, fcs, fcl, nc, nv, bf, bmask, umask, tab, tmask, ev, ek, emask, deadline) (i64[] i64[] i64[] i64 i64 i64[] i64 i8[] i64[] i64 i64[] i64[] i64[] i64) i64
  xs = i64[8]
  sg = i64[8]
  ne = 0 ## i64
  v = 1 ## i64
  while v <= nv
    um = umask[v] ## i64
    if um != 0
      at = wassat_parity_at(tab, ev, tmask, 1, v, 0, 0, 0, 0) ## i64
      if at <= 0
        tab[0 - at - 1] = ne + 1
        ev[5 * ne] = v
        ev[5 * ne + 1] = 0
        ev[5 * ne + 2] = 0
        ev[5 * ne + 3] = 0
        ev[5 * ne + 4] = 0
        ek[ne] = 1
        at = ne + 1
        ne += 1
      emask[at - 1] = um
    v += 1
  ci = 0 ## i64
  while ci < nc
    n = fcl[ci] ## i64
    if n >= 2 && n <= 5
      off = fcs[ci] ## i64
      ok = 1 ## i64
      j = 0 ## i64
      while j < n
        l = fla[off + j] ## i64
        x = l < 0 ? 0 - l : l ## i64
        s = l < 0 ? 1 : 0 ## i64
        k = j ## i64
        while k > 0 && xs[k - 1] > x
          xs[k] = xs[k - 1]
          sg[k] = sg[k - 1]
          k -= 1
        xs[k] = x
        sg[k] = s
        j += 1
      j = 1
      while j < n
        ok = 0 if xs[j] == xs[j - 1]
        j += 1
      if ok == 1
        j = n
        while j < 5
          xs[j] = 0
          j += 1
        h1 = n ## i64
        h1 = ((h1 * 1000003) + xs[0]) & bmask
        h1 = ((h1 * 1000003) + xs[1]) & bmask
        h1 = ((h1 * 1000003) + xs[2]) & bmask
        h1 = ((h1 * 1000003) + xs[3]) & bmask
        h1 = ((h1 * 1000003) + xs[4]) & bmask
        b1 = (bf[h1 >> 4] >> ((h1 & 15) << 1)) & 3 ## i64
        if b1 == 3
          h2 = (n * 2654435761) & bmask ## i64
          h2 = ((h2 * 998244353) ^ xs[0]) & bmask
          h2 = ((h2 * 998244353) ^ xs[1]) & bmask
          h2 = ((h2 * 998244353) ^ xs[2]) & bmask
          h2 = ((h2 * 998244353) ^ xs[3]) & bmask
          h2 = ((h2 * 998244353) ^ xs[4]) & bmask
          b2 = (bf[h2 >> 4] >> ((h2 & 15) << 1)) & 3 ## i64
          if b2 == 3
            pat = 0 ## i64
            j = 0
            while j < n
              pat = pat | (sg[j] << j)
              j += 1
            at = wassat_parity_at(tab, ev, tmask, n, xs[0], xs[1], xs[2], xs[3], xs[4])
            if at <= 0
              tab[0 - at - 1] = ne + 1
              ev[5 * ne] = xs[0]
              ev[5 * ne + 1] = xs[1]
              ev[5 * ne + 2] = xs[2]
              ev[5 * ne + 3] = xs[3]
              ev[5 * ne + 4] = xs[4]
              ek[ne] = n
              at = ne + 1
              ne += 1
            emask[at - 1] = emask[at - 1] | (1 << pat)
    ci += 1
    if (ci & 65535) == 0 && deadline > 0 && clock_ms() >= deadline
      z = ccall("w_value_free_w", sg)
      z = ccall("w_value_free_w", xs)
      return 0 - 1
  z = ccall("w_value_free_w", sg)
  z = ccall("w_value_free_w", xs)
  ne

# Group the clauses of at most five distinct variables by variable set and
# record, per set, which sign patterns occur (bit p: the clause negating
# exactly the positions of p). Returns the number of sets, -1 on the deadline.
-> wassat_parity_collect(fla, fcs, fcl, nc, tab, tmask, ev, ek, emask, deadline) (i64[] i64[] i64[] i64 i64[] i64 i64[] i64[] i64[] i64) i64
  xs = i64[8]
  sg = i64[8]
  ne = 0 ## i64
  ci = 0 ## i64
  while ci < nc
    n = fcl[ci] ## i64
    if n >= 1 && n <= 5
      off = fcs[ci] ## i64
      ok = 1 ## i64
      j = 0 ## i64
      while j < n
        l = fla[off + j] ## i64
        x = l < 0 ? 0 - l : l ## i64
        s = l < 0 ? 1 : 0 ## i64
        k = j ## i64
        while k > 0 && xs[k - 1] > x
          xs[k] = xs[k - 1]
          sg[k] = sg[k - 1]
          k -= 1
        xs[k] = x
        sg[k] = s
        j += 1
      j = 1
      while j < n
        ok = 0 if xs[j] == xs[j - 1]
        j += 1
      if ok == 1
        j = n
        while j < 5
          xs[j] = 0
          j += 1
        pat = 0 ## i64
        j = 0
        while j < n
          pat = pat | (sg[j] << j)
          j += 1
        at = wassat_parity_at(tab, ev, tmask, n, xs[0], xs[1], xs[2], xs[3], xs[4]) ## i64
        if at <= 0
          tab[0 - at - 1] = ne + 1
          ev[5 * ne] = xs[0]
          ev[5 * ne + 1] = xs[1]
          ev[5 * ne + 2] = xs[2]
          ev[5 * ne + 3] = xs[3]
          ev[5 * ne + 4] = xs[4]
          ek[ne] = n
          at = ne + 1
          ne += 1
        emask[at - 1] = emask[at - 1] | (1 << pat)
    ci += 1
    if (ci & 65535) == 0 && deadline > 0 && clock_ms() >= deadline
      z = ccall("w_value_free_w", sg)
      z = ccall("w_value_free_w", xs)
      return 0 - 1
  z = ccall("w_value_free_w", sg)
  z = ccall("w_value_free_w", xs)
  ne

# Returns { "status": 0 or -1, "work": st }.
-> wassat_parity_sum_unsat(formula, deadline = 0, witness = nil)
  st = i64[16]
  miss = { "status": 0, "work": st }
  return miss unless formula.has_key?("flat_ncl")
  nv = formula["nvars"]
  nc = formula["flat_ncl"]
  return miss if nv < 1 || nv > WASSAT_PARITY_SUM_MAX_VARS || nc < 1 || nc > WASSAT_PARITY_SUM_MAX_CLAUSES
  cfg = formula.has_key?("config") ? formula["config"] : nil
  if cfg != nil
    return miss if cfg.units == 0 && cfg.binary < 2 && cfg.ternary < 4 && cfg.large < 8
  fla = formula["flat_lits"] ## i64[]
  fcs = formula["flat_offs"] ## i64[]
  fcl = formula["flat_lens"] ## i64[]
  wc = i64[6]
  if cfg != nil && cfg.large == 0
    wc[1] = cfg.units
    wc[2] = cfg.binary
    wc[3] = cfg.ternary
  else
    z = wassat_parity_widths(fcl, nc, wc)
  n1 = wc[1]
  n2 = wc[2]
  n3 = wc[3]
  n4 = wc[4]
  n5 = wc[5]
  z = ccall("w_value_free_w", wc)
  nsmall = n1 + n2 + n3 + n4 + n5
  return miss if nsmall == 0
  return miss if n1 == 0 && n2 < 2 && n3 < 4 && n4 < 8 && n5 < 16
  has_card_shape = n3 >= 8 || n4 >= 30 || n5 >= 112
  n25 = n2 + n3 + n4 + n5
  cap_s = nsmall
  ne = 0
  units_only = false
  tab = nil
  ev = nil
  ek = nil
  emask = nil
  if nsmall > 65536
    bcnt = 65536
    while bcnt < n25 && bcnt < 4194304
      bcnt = bcnt << 1
    bmask = bcnt - 1
    bf = i64[(bcnt >> 4) + 2]
    umask = i8[nv + 2]
    meta = i64[2]
    ncand = wassat_parity_prefilter(fla, fcs, fcl, nc, nv, bf, bmask, umask, meta, deadline)
    clash_v = meta[0]
    nu = meta[1]
    z = ccall("w_value_free_w", meta)
    if ncand == 0 - 2
      z = ccall("w_value_free_w", umask)
      z = ccall("w_value_free_w", bf)
      st[6] = 1
      if witness != nil
        ev1 = i64[5]
        ev1[0] = clash_v
        witness["local"] = true
        witness["vars"] = ev1
        witness["offset"] = 0
        witness["width"] = 1
      return { "status": 0 - 1, "work": st }
    if ncand < 0
      z = ccall("w_value_free_w", umask)
      z = ccall("w_value_free_w", bf)
      st[8] = 2
      return miss
    if ncand == 0
      z = ccall("w_value_free_w", bf)
      if witness != nil || !has_card_shape
        z = ccall("w_value_free_w", umask)
        st[1] = nu
        return miss
      units_only = true
      ev = i64[5 * nu + 5]
      ek = i64[nu + 1]
      emask = i64[nu + 1]
      if nu > 0
        v = 1
        while v <= nv
          um = umask[v] ## i64
          if um != 0
            ev[5 * ne] = v
            ek[ne] = 1
            emask[ne] = um
            ne += 1
          v += 1
      z = ccall("w_value_free_w", umask)
    else
      cap_s = ncand + nu
      tsize = 1024
      while tsize < 2 * cap_s + 4
        tsize = tsize << 1
      tmask = tsize - 1
      tab = i64[tsize]
      ev = i64[5 * cap_s + 5]
      ek = i64[cap_s + 1]
      emask = i64[cap_s + 1]
      ne = wassat_parity_collect_filtered(fla, fcs, fcl, nc, nv, bf, bmask, umask, tab, tmask, ev, ek, emask, deadline)
      z = ccall("w_value_free_w", umask)
      z = ccall("w_value_free_w", bf)
  else
    tsize = 1024
    while tsize < 2 * cap_s
      tsize = tsize << 1
    tmask = tsize - 1
    tab = i64[tsize]
    ev = i64[5 * cap_s + 5]
    ek = i64[cap_s + 1]
    emask = i64[cap_s + 1]
    ne = wassat_parity_collect(fla, fcs, fcl, nc, tab, tmask, ev, ek, emask, deadline)
  z = ccall("w_value_free_w", tab) if tab != nil
  if ne < 0
    z = ccall("w_value_free_w", emask)
    z = ccall("w_value_free_w", ek)
    z = ccall("w_value_free_w", ev)
    st[8] = 2
    return miss
  st[0] = ne
  # Pattern sets by parity of the number of negated positions, per width.
  evenm = i64[6]
  oddm = i64[6]
  k = 1
  while k <= 5
    p = 0
    while p < (1 << k)
      bits = wassat_parity_bits(p)
      if (bits & 1) == 0
        evenm[k] = evenm[k] | (1 << p)
      else
        oddm[k] = oddm[k] | (1 << p)
      p += 1
    k += 1
  # A clause with negated positions p forbids the assignment x = p, so the
  # clauses of even p forbid every even-weight assignment: the sum is odd.
  eoff = i64[ne + 1]
  elen = i64[ne + 1]
  erhs = i64[ne + 1]
  evars = i64[5 * ne + 5]
  nq = 0
  nl = 0
  i = 0
  while i < ne
    k = ek[i]
    m = emask[i]
    he = (m & evenm[k]) == evenm[k]
    ho = (m & oddm[k]) == oddm[k]
    if he && ho
      # Every assignment of these variables is forbidden.
      st[6] = 1
      z = ccall("w_value_free_w", evars)
      z = ccall("w_value_free_w", erhs)
      z = ccall("w_value_free_w", elen)
      z = ccall("w_value_free_w", eoff)
      z = ccall("w_value_free_w", oddm)
      z = ccall("w_value_free_w", evenm)
      z = ccall("w_value_free_w", emask)
      z = ccall("w_value_free_w", ek)
      if witness != nil
        witness["local"] = true
        witness["vars"] = ev
        witness["offset"] = 5*i
        witness["width"] = k
      else
        z = ccall("w_value_free_w", ev)
      return { "status": 0 - 1, "work": st }
    if he || ho
      eoff[nq] = nl
      elen[nq] = k
      erhs[nq] = he ? 1 : 0
      j = 0
      while j < k
        evars[nl] = ev[5 * i + j]
        nl += 1
        j += 1
      nq += 1
    i += 1
  z = ccall("w_value_free_w", oddm)
  z = ccall("w_value_free_w", evenm)
  z = ccall("w_value_free_w", emask)
  z = ccall("w_value_free_w", ek)
  z = ccall("w_value_free_w", ev)
  st[1] = nq
  members = i8[witness == nil ? 0 : nq]
  if nq > 0 && !units_only
    hit = wassat_parity_sum_close(nv, nq, eoff, elen, erhs, evars, st, members)
    if hit == 1
      if witness != nil
        witness["members"] = members
        witness["vars"] = evars
        witness["offsets"] = eoff
        witness["lengths"] = elen
        witness["rhs"] = erhs
      else
        z = ccall("w_value_free_w", members)
        z = ccall("w_value_free_w", evars)
        z = ccall("w_value_free_w", erhs)
        z = ccall("w_value_free_w", elen)
        z = ccall("w_value_free_w", eoff)
      return { "status": 0 - 1, "work": st }
  # The exporter proves each selected row from its complete XOR truth table.
  # A cardinality-derived parity needs a different local certificate.
  if witness != nil || !has_card_shape
    z = ccall("w_value_free_w", members)
    z = ccall("w_value_free_w", evars)
    z = ccall("w_value_free_w", erhs)
    z = ccall("w_value_free_w", elen)
    z = ccall("w_value_free_w", eoff)
    return miss
  # Again with the cardinality equations beside the XORs (a second pass, so
  # that extra equations can never cost a refutation the XORs give alone).
  nmid = n3 + n4 + n5
  kcap = (nmid >> 2) + 8
  kv = i64[8 * kcap + 8]
  kn = i64[kcap + 1]
  kr = i64[kcap + 1]
  nk = wassat_parity_cardinality(fla, fcs, fcl, nc, nv, kv, kn, kr, kcap, st, deadline)
  if nk == 0
    z = ccall("w_value_free_w", kr)
    z = ccall("w_value_free_w", kn)
    z = ccall("w_value_free_w", kv)
    z = ccall("w_value_free_w", members)
    z = ccall("w_value_free_w", evars)
    z = ccall("w_value_free_w", erhs)
    z = ccall("w_value_free_w", elen)
    z = ccall("w_value_free_w", eoff)
    return miss
  nt = nq + nk
  eoff2 = i64[nt + 1]
  elen2 = i64[nt + 1]
  erhs2 = i64[nt + 1]
  evars2 = i64[nl + 8 * nk + 8]
  i = 0
  while i < nq
    eoff2[i] = eoff[i]
    elen2[i] = elen[i]
    erhs2[i] = erhs[i]
    i += 1
  i = 0
  while i < nl
    evars2[i] = evars[i]
    i += 1
  z = ccall("w_value_free_w", evars)
  z = ccall("w_value_free_w", erhs)
  z = ccall("w_value_free_w", elen)
  z = ccall("w_value_free_w", eoff)
  p2 = nl
  i = 0
  while i < nk
    eoff2[nq + i] = p2
    elen2[nq + i] = kn[i]
    erhs2[nq + i] = kr[i]
    j = 0
    while j < kn[i]
      evars2[p2] = kv[8 * i + j]
      p2 += 1
      j += 1
    i += 1
  z = ccall("w_value_free_w", kr)
  z = ccall("w_value_free_w", kn)
  z = ccall("w_value_free_w", kv)
  st[2] = 0
  st[3] = 0
  hit = wassat_parity_sum_close(nv, nt, eoff2, elen2, erhs2, evars2, st, members)
  z = ccall("w_value_free_w", members)
  z = ccall("w_value_free_w", evars2)
  z = ccall("w_value_free_w", erhs2)
  z = ccall("w_value_free_w", elen2)
  z = ccall("w_value_free_w", eoff2)
  return { "status": 0 - 1, "work": st } if hit == 1
  miss
