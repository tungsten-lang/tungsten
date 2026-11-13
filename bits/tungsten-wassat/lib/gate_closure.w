# Congruence closure over the gates an input CNF defines.
#
# Hardware model-checking and equivalence-checking formulas are Tseitin
# renderings of circuits in which the same sub-circuit appears many times
# (two unrollings, two implementations). Two gates of one kind over the same
# inputs have the same output, and identifying those outputs makes the gates
# one layer up syntactically equal in turn. Closing that relation merges
# 40-50% of the variables of such inputs, after which the search is short or
# empty. solver.w's own congruence pass reads AND and XOR gates once and has
# no if-then-else gates, which is where most of these circuits' structure is.
#
# This lane reads three gate kinds from the ORIGINAL clauses:
#   AND   l = r1 & .. & rk   clause (l | -r1 | .. | -rk), binaries (-l | ri)
#   XOR   x1 ^ .. ^ xk = p   all 2^(k-1) clauses of one parity, k = 3..5
#   ITE   l = c ? t : e      (-c -t l) (-c t -l) (c -e l) (c e -l)
# and closes them with a union-find over literals: gates are hashed by kind
# and inputs, two gates with one key have equal outputs, and every gate that
# mentions a merged variable is rewritten through the representative map,
# simplified (constants, repeated and complementary inputs) and hashed again.
#
# Soundness. A gate is a set of input clauses that is logically equivalent to
# "output = kind(inputs)", so every unit and every literal equivalence the
# closure derives holds in EVERY model of the input. The lane never removes
# or rewrites an input clause: its whole effect is to append those implied
# units and equivalence binaries to the formula. A model of the result is a
# model of the input (the caller still replays it), and the result is
# unsatisfiable exactly when the input is. Dropping a gate, stopping early on
# a budget, or missing a gate only loses merges.
# A contradiction (x = -x) is not published from here either: the two
# clashing literals are appended as one more equivalence and the ordinary
# solver refutes the formula by propagation.
#
# Fast mode only: the appended clauses carry no proof steps.

WASSAT_GATE_CLOSURE_MS = 2000
WASSAT_GATE_CLOSURE_MAX_VARS = 6000000
WASSAT_GATE_CLOSURE_MAX_CLAUSES = 24000000
WASSAT_GATE_CLOSURE_MAX_AND = 64
# Extraction work: a base allowance plus a multiple of the input's literals.
WASSAT_GATE_CLOSURE_TICKS = 8000000
WASSAT_GATE_CLOSURE_TICKS_PER_LITERAL = 1
# Clauses of 3..5 literals the XOR/ITE clause set will index.
WASSAT_GATE_CLOSURE_MAX_INDEXED = 6000000

# st slots.
#  0 merges        1 conflict       2 conflict literal a   3 conflict literal b
#  4 queue length  5 stop           6 hash entries         7 occurrence entries
#  8 AND gates     9 XOR gates     10 ITE gates           11 ticks
# 12 installs     13 nbinary       14 indexed clauses     15 deadline polls
# 16 units out    17 equivalences out  18 gates  19 arena used

-> wassat_gc_find(rep, c) (i64[] i64) i64
  v = c >> 1 ## i64
  s = c & 1 ## i64
  while rep[v] != (v << 1)
    p = rep[v] ## i64
    s = s ^ (p & 1)
    v = p >> 1
  root = (v << 1) | s ## i64
  # Path compression: every variable on the walk points at the root.
  v = c >> 1
  s = c & 1
  while rep[v] != (v << 1)
    p = rep[v]
    rep[v] = root ^ s
    s = s ^ (p & 1)
    v = p >> 1
  root

# Identify two literals. Returns 1 when the classes were distinct.
-> wassat_gc_merge(rep, queue, st, tcon, a, b) (i64[] i64[] i64[] i64 i64 i64) i64
  return 0 if st[1] != 0
  ra = wassat_gc_find(rep, a)
  rb = wassat_gc_find(rep, b)
  return 0 if ra == rb
  if ra == (rb ^ 1)
    st[1] = 1
    st[2] = a
    st[3] = b
    return 0
  va = ra >> 1 ## i64
  vb = rb >> 1 ## i64
  keep = rb ## i64
  gone = ra ## i64
  if va == tcon || (vb != tcon && va < vb)
    keep = ra
    gone = rb
  rep[gone >> 1] = keep ^ (gone & 1)
  queue[st[4]] = gone >> 1
  st[4] += 1
  st[0] += 1
  1

-> wassat_gc_sort(ar, off, n) (i64[] i64 i64)
  i = 1
  while i < n
    x = ar[off + i] ## i64
    j = i - 1
    while j >= 0 && ar[off + j] > x
      ar[off + j + 1] = ar[off + j]
      j -= 1
    ar[off + j + 1] = x
    i += 1
  0

# Is (a | b) an input binary clause? bst/bad: sorted adjacency per literal.
-> wassat_gc_has_bin(bst, bad, a, b) (i64[] i64[] i64 i64) i64
  x = a ## i64
  y = b ## i64
  if bst[b + 1] - bst[b] < bst[a + 1] - bst[a]
    x = b
    y = a
  lo = bst[x] ## i64
  hi = bst[x + 1] - 1 ## i64
  while lo <= hi
    mid = (lo + hi) >> 1 ## i64
    m = bad[mid] ## i64
    return 1 if m == y
    if m < y
      lo = mid + 1
    else
      hi = mid - 1
  0

# Look a sorted clause key up in the clause set. Returns index + 1 or 0.
-> wassat_gc_clause_at(cht, sk, cmask, k, a, b, c, d, e) (i64[] i64[] i64 i64 i64 i64 i64 i64 i64) i64
  h = k ## i64
  h = ((h * 1000003) + a) & cmask
  h = ((h * 1000003) + b) & cmask
  h = ((h * 1000003) + c) & cmask
  h = ((h * 1000003) + d) & cmask
  h = ((h * 1000003) + e) & cmask
  while cht[h] != 0
    base = (cht[h] - 1) * 5 ## i64
    return cht[h] if sk[base] == a && sk[base + 1] == b && sk[base + 2] == c && sk[base + 3] == d && sk[base + 4] == e
    h = (h + 1) & cmask
  0 - h - 1

# Ternary membership for three literal codes in any order.
-> wassat_gc_has_tern(cht, sk, cmask, a, b, c) (i64[] i64[] i64 i64 i64 i64) i64
  x = a ## i64
  y = b ## i64
  z = c ## i64
  if x > y
    t = x ## i64
    x = y
    y = t
  if y > z
    t = y
    y = z
    z = t
  if x > y
    t = x
    x = y
    y = t
  return 1 if wassat_gc_clause_at(cht, sk, cmask, 3, x, y, z, 0, 0) > 0
  0

# Normalise gate g through the representative map, simplify it, and hash it.
# A gate whose key is already present has the stored gate's output; a gate
# that degenerates becomes a unit or an equivalence. Dead gates get kind 0.
-> wassat_gc_install(g, rep, gty, glhs, goff, glen, ar, ht, hmask, queue, st, tcon) (i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64[] i64[] i64) i64
  return 0 if st[5] != 0 || st[1] != 0
  st[12] += 1
  tt = tcon << 1 ## i64
  ff = tt | 1 ## i64
  off = goff[g] ## i64
  again = 1
  while again == 1
    again = 0
    ty = gty[g] ## i64
    lhs = wassat_gc_find(rep, glhs[g])
    n = glen[g] ## i64
    if ty == 3
      c = wassat_gc_find(rep, ar[off])
      t = wassat_gc_find(rep, ar[off + 1])
      e = wassat_gc_find(rep, ar[off + 2])
      if (c & 1) == 1
        c = c ^ 1
        x = t ## i64
        t = e
        e = x
      if c == tt
        z = wassat_gc_merge(rep, queue, st, tcon, lhs, t)
        gty[g] = 0
        return 0
      if t == e
        z = wassat_gc_merge(rep, queue, st, tcon, lhs, t)
        gty[g] = 0
        return 0
      if (lhs >> 1) == (c >> 1) || (lhs >> 1) == (t >> 1) || (lhs >> 1) == (e >> 1) || (lhs >> 1) == tcon
        gty[g] = 0
        return 0
      if t == (e ^ 1)
        # c ? -e : e  =  c ^ e
        gty[g] = 2
        glhs[g] = lhs
        ar[off] = c
        ar[off + 1] = e
        glen[g] = 2
        again = 1
      elsif t == tt || t == c
        # c | e
        gty[g] = 1
        glhs[g] = lhs ^ 1
        ar[off] = c ^ 1
        ar[off + 1] = e ^ 1
        glen[g] = 2
        again = 1
      elsif t == ff || t == (c ^ 1)
        # -c & e
        gty[g] = 1
        glhs[g] = lhs
        ar[off] = c ^ 1
        ar[off + 1] = e
        glen[g] = 2
        again = 1
      elsif e == tt || e == (c ^ 1)
        # -c | t
        gty[g] = 1
        glhs[g] = lhs ^ 1
        ar[off] = c
        ar[off + 1] = t ^ 1
        glen[g] = 2
        again = 1
      elsif e == ff || e == c
        # c & t
        gty[g] = 1
        glhs[g] = lhs
        ar[off] = c
        ar[off + 1] = t
        glen[g] = 2
        again = 1
      else
        if (t & 1) == 1
          lhs = lhs ^ 1
          t = t ^ 1
          e = e ^ 1
        glhs[g] = lhs
        ar[off] = c
        ar[off + 1] = t
        ar[off + 2] = e
    elsif ty == 1
      w = 0
      j = 0
      dead = 0
      while j < n && dead == 0
        x = wassat_gc_find(rep, ar[off + j])
        if x == ff || x == (lhs ^ 1)
          dead = 2
        elsif x == lhs
          dead = 1
        elsif x != tt
          ar[off + w] = x
          w += 1
        j += 1
      if dead == 0
        z = wassat_gc_sort(ar, off, w)
        # Sorted codes put x and -x side by side and equal inputs together.
        m = 0
        j = 0
        while j < w && dead == 0
          x = ar[off + j]
          if m > 0 && ar[off + m - 1] == x
            j += 1
          elsif m > 0 && ar[off + m - 1] == (x ^ 1)
            dead = 2
          else
            ar[off + m] = x
            m += 1
            j += 1
        w = m
      if dead == 2
        z = wassat_gc_merge(rep, queue, st, tcon, lhs, ff)
        gty[g] = 0
        return 0
      if dead == 1
        gty[g] = 0
        return 0
      if w == 0
        z = wassat_gc_merge(rep, queue, st, tcon, lhs, tt)
        gty[g] = 0
        return 0
      if lhs == tt
        j = 0
        while j < w
          z = wassat_gc_merge(rep, queue, st, tcon, ar[off + j], tt)
          j += 1
        gty[g] = 0
        return 0
      if w == 1
        z = wassat_gc_merge(rep, queue, st, tcon, lhs, ar[off])
        gty[g] = 0
        return 0
      if lhs == ff
        gty[g] = 0
        return 0
      glhs[g] = lhs
      glen[g] = w
    else
      w = 0
      j = 0
      while j < n
        x = wassat_gc_find(rep, ar[off + j])
        if (x & 1) == 1
          lhs = lhs ^ 1
          x = x ^ 1
        if x == tt
          lhs = lhs ^ 1
        else
          ar[off + w] = x
          w += 1
        j += 1
      z = wassat_gc_sort(ar, off, w)
      # Equal inputs cancel in pairs.
      m = 0
      j = 0
      while j < w
        if j + 1 < w && ar[off + j] == ar[off + j + 1]
          j += 2
        else
          ar[off + m] = ar[off + j]
          m += 1
          j += 1
      w = m
      self_in = 0
      j = 0
      while j < w
        self_in = 1 if (ar[off + j] >> 1) == (lhs >> 1)
        j += 1
      if self_in == 1
        gty[g] = 0
        return 0
      if w == 0
        z = wassat_gc_merge(rep, queue, st, tcon, lhs, ff)
        gty[g] = 0
        return 0
      if w == 1
        z = wassat_gc_merge(rep, queue, st, tcon, lhs, ar[off])
        gty[g] = 0
        return 0
      if (lhs >> 1) == tcon
        if w == 2
          # a ^ b = lhs: equal when lhs is false, complementary when true.
          z = wassat_gc_merge(rep, queue, st, tcon, ar[off], lhs == ff ? ar[off + 1] : (ar[off + 1] ^ 1))
        gty[g] = 0
        return 0
      glhs[g] = lhs
      glen[g] = w
  ty = gty[g]
  n = glen[g]
  h = ty ## i64
  j = 0
  while j < n
    h = ((h * 1000003) + ar[off + j]) & hmask
    j += 1
  while ht[h] != 0
    g2 = ht[h] - 1 ## i64
    return 0 if g2 == g
    if gty[g2] == ty && glen[g2] == n
      o2 = goff[g2] ## i64
      same = 1
      j = 0
      while j < n && same == 1
        same = 0 if ar[o2 + j] != ar[off + j]
        j += 1
      if same == 1
        z = wassat_gc_merge(rep, queue, st, tcon, glhs[g], glhs[g2])
        gty[g] = 0
        return 0
    h = (h + 1) & hmask
  ht[h] = g + 1
  st[6] += 1
  st[5] = 1 if st[6] * 2 > hmask
  1

-> wassat_gc_watch(g, v, ohead, onext, ogate, st) (i64 i64 i64[] i64[] i64[] i64[]) i64
  e = st[7] ## i64
  if e >= ogate.size
    st[5] = 1
    return 0
  ogate[e] = g
  onext[e] = ohead[v]
  ohead[v] = e + 1
  st[7] = e + 1
  1

# Rewrite every gate that mentions a merged-away variable.
-> wassat_gc_drain(qh, rep, gty, glhs, goff, glen, ar, ht, hmask, queue, st, tcon, ohead, onext, ogate, deadline) (i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  q = qh ## i64
  while q < st[4] && st[5] == 0 && st[1] == 0
    v = queue[q] ## i64
    q += 1
    e = ohead[v] ## i64
    ohead[v] = 0
    while e != 0 && st[5] == 0 && st[1] == 0
      g = ogate[e - 1] ## i64
      e = onext[e - 1]
      if gty[g] != 0
        if wassat_gc_install(g, rep, gty, glhs, goff, glen, ar, ht, hmask, queue, st, tcon) == 1 || gty[g] != 0
          r = wassat_gc_find(rep, v << 1) >> 1 ## i64
          z = wassat_gc_watch(g, r, ohead, onext, ogate, st) if r != tcon
    if (q & 255) == 0 && deadline > 0
      st[15] += 1
      st[5] = 1 if clock_ms() >= deadline
  q

# Gate extraction and closure. Fills rep (representative literal code per
# variable) and st. Returns 1 when the closure ran, 0 on a declined shape.
-> wassat_gc_close(fla, fcs, fcl, ncl, nv, rep, st, deadline) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64) i64
  tcon = nv + 1 ## i64
  nl = (nv + 2) << 1 ## i64
  tt = tcon << 1 ## i64
  v = 0
  while v <= tcon
    rep[v] = v << 1
    v += 1
  queue = i64[nv + 4]
  # ---- census: binaries per literal, clauses of 3..5 distinct variables.
  bst = i64[nl + 2]
  nbin = 0
  nidx = 0
  nlit = 0
  ci = 0
  while ci < ncl
    n = fcl[ci] ## i64
    off = fcs[ci] ## i64
    nlit += n
    if n == 2
      a = fla[off] ## i64
      b = fla[off + 1] ## i64
      ca = a > 0 ? a << 1 : ((0 - a) << 1) | 1 ## i64
      cb = b > 0 ? b << 1 : ((0 - b) << 1) | 1 ## i64
      if (ca >> 1) != (cb >> 1)
        bst[ca + 1] += 1
        bst[cb + 1] += 1
        nbin += 1
    elsif n >= 3 && n <= 5
      nidx += 1
    ci += 1
  st[13] = nbin
  c = 0
  while c <= nl
    bst[c + 1] += bst[c]
    c += 1
  # Unsorted adjacency, then a second bucket pass in literal order, which
  # leaves every list sorted without a comparison sort.
  bun = i64[2 * nbin + 2]
  fill = i64[nl + 2]
  ci = 0
  while ci < ncl
    if fcl[ci] == 2
      off = fcs[ci]
      a = fla[off]
      b = fla[off + 1]
      ca = a > 0 ? a << 1 : ((0 - a) << 1) | 1
      cb = b > 0 ? b << 1 : ((0 - b) << 1) | 1
      if (ca >> 1) != (cb >> 1)
        bun[bst[ca] + fill[ca]] = cb
        fill[ca] += 1
        bun[bst[cb] + fill[cb]] = ca
        fill[cb] += 1
    ci += 1
  bad = i64[2 * nbin + 2]
  c = 0
  while c < nl
    fill[c] = 0
    c += 1
  c = 0
  while c < nl
    p = bst[c] ## i64
    pe = bst[c + 1] ## i64
    while p < pe
      y = bun[p] ## i64
      bad[bst[y] + fill[y]] = c
      fill[y] += 1
      p += 1
    c += 1
  # ---- units and binary-pair equivalences.
  ci = 0
  while ci < ncl
    n = fcl[ci]
    off = fcs[ci]
    if n == 1
      a = fla[off]
      ca = a > 0 ? a << 1 : ((0 - a) << 1) | 1
      z = wassat_gc_merge(rep, queue, st, tcon, ca, tt)
    elsif n == 2
      a = fla[off]
      b = fla[off + 1]
      ca = a > 0 ? a << 1 : ((0 - a) << 1) | 1
      cb = b > 0 ? b << 1 : ((0 - b) << 1) | 1
      if (ca >> 1) != (cb >> 1) && wassat_gc_has_bin(bst, bad, ca ^ 1, cb ^ 1) == 1
        z = wassat_gc_merge(rep, queue, st, tcon, ca ^ 1, cb)
    ci += 1
  # ---- gate arena.
  maxg = 2 * ncl + 16 ## i64
  gty = i64[maxg]
  glhs = i64[maxg]
  goff = i64[maxg]
  glen = i64[maxg]
  acap = 2 * nlit + 64 ## i64
  ar = i64[acap]
  ng = 0
  au = 0
  ticks = 0
  late = 0
  budget = WASSAT_GATE_CLOSURE_TICKS + WASSAT_GATE_CLOSURE_TICKS_PER_LITERAL * nlit ## i64
  # ---- AND gates.
  # An AND gate of k inputs owns k binaries, so a formula with few binaries
  # per clause has few gates per clause: skip the scan.
  ci = 0
  ci = ncl if nbin * 8 < ncl
  while ci < ncl && ticks < budget
    n = fcl[ci]
    if n >= 3 && n <= WASSAT_GATE_CLOSURE_MAX_AND + 1
      off = fcs[ci]
      j = 0
      while j < n
        a = fla[off + j]
        ca = a > 0 ? a << 1 : ((0 - a) << 1) | 1
        na = ca ^ 1 ## i64
        if bst[na + 1] - bst[na] >= n - 1 && ng < maxg && au + n < acap
          ok = 1
          k = 0
          while k < n && ok == 1
            if k != j
              b = fla[off + k]
              cb = b > 0 ? b << 1 : ((0 - b) << 1) | 1
              ticks += 1
              ok = 0 if wassat_gc_has_bin(bst, bad, na, cb ^ 1) == 0
            k += 1
          if ok == 1
            gty[ng] = 1
            glhs[ng] = ca
            goff[ng] = au
            glen[ng] = n - 1
            k = 0
            while k < n
              if k != j
                b = fla[off + k]
                cb = b > 0 ? b << 1 : ((0 - b) << 1) | 1
                ar[au] = cb ^ 1
                au += 1
              k += 1
            ng += 1
            st[8] += 1
        j += 1
    ci += 1
    if (ci & 4095) == 0 && deadline > 0 && clock_ms() >= deadline
      ticks = budget
      late = 1
  # Each gate kind has its own allowance; only the deadline ends them all.
  st[11] = ticks
  ticks = 0 if late == 0
  # ---- clause set for sizes 3..5 (sorted literal codes, zero padded).
  if nidx > 0 && nidx <= WASSAT_GATE_CLOSURE_MAX_INDEXED && ticks < budget
    ccap = 1024 ## i64
    while ccap < 2 * nidx + 2
      ccap = ccap << 1
    cmask = ccap - 1 ## i64
    cht = i64[ccap]
    sk = i64[5 * nidx + 5]
    tst = i64[nl + 2]
    ni = 0
    ci = 0
    while ci < ncl
      n = fcl[ci]
      if n >= 3 && n <= 5
        off = fcs[ci]
        base = ni * 5 ## i64
        j = 0
        while j < 5
          sk[base + j] = 0
          j += 1
        j = 0
        while j < n
          a = fla[off + j]
          sk[base + j] = a > 0 ? a << 1 : ((0 - a) << 1) | 1
          j += 1
        z = wassat_gc_sort(sk, base, n)
        distinct = 1
        j = 1
        while j < n
          distinct = 0 if (sk[base + j] >> 1) == (sk[base + j - 1] >> 1)
          j += 1
        if distinct == 1
          at = wassat_gc_clause_at(cht, sk, cmask, n, sk[base], sk[base + 1], sk[base + 2], sk[base + 3], sk[base + 4])
          if at <= 0
            cht[0 - at - 1] = ni + 1
            if n == 3
              tst[sk[base] + 1] += 1
              tst[sk[base + 1] + 1] += 1
              tst[sk[base + 2] + 1] += 1
            ni += 1
      ci += 1
    st[14] = ni
    # Ternary occurrences per literal.
    c = 0
    while c <= nl
      tst[c + 1] += tst[c]
      c += 1
    toc = i64[tst[nl] + 2]
    c = 0
    while c < nl
      fill[c] = 0
      c += 1
    i = 0
    while i < ni
      base = i * 5
      if sk[base + 3] == 0
        j = 0
        while j < 3
          x = sk[base + j] ## i64
          toc[tst[x] + fill[x]] = i
          fill[x] += 1
          j += 1
      i += 1
    # ---- XOR gates: the representative clause of a parity class has no
    # negative literal, or exactly one on its smallest variable.
    xs = i64[8]
    i = 0
    while i < ni && ticks < budget
      base = i * 5
      n = 3
      n = 4 if sk[base + 3] != 0
      n = 5 if sk[base + 4] != 0
      negs = 0
      j = 0
      while j < n
        negs += sk[base + j] & 1
        j += 1
      if negs == 0 || (negs == 1 && (sk[base] & 1) == 1)
        ok = 1
        mask = 0
        full = (1 << n) - 1 ## i64
        while mask <= full && ok == 1
          # Parity of the sign pattern must equal the class parity.
          pc = 0
          j = 0
          while j < n
            pc += (mask >> j) & 1
            j += 1
          if (pc & 1) == negs
            j = 0
            while j < 5
              xs[j] = 0
              j += 1
            j = 0
            while j < n
              xs[j] = (sk[base + j] & (0 - 2)) | ((mask >> j) & 1)
              j += 1
            ticks += 1
            ok = 0 if wassat_gc_clause_at(cht, sk, cmask, n, xs[0], xs[1], xs[2], xs[3], xs[4]) <= 0
          mask += 1
        if ok == 1 && ng + n < maxg && au + n * n < acap
          # A clause with `negs` negations forbids the assignment with that
          # many true variables, so x1 ^ .. ^ xn = 1 - negs.
          st[9] += 1
          j = 0
          while j < n
            gty[ng] = 2
            glhs[ng] = (sk[base + j] & (0 - 2)) | (negs == 0 ? 1 : 0)
            goff[ng] = au
            glen[ng] = n - 1
            k = 0
            while k < n
              if k != j
                ar[au] = sk[base + k] & (0 - 2)
                au += 1
              k += 1
            ng += 1
            j += 1
      i += 1
      if (i & 4095) == 0 && deadline > 0 && clock_ms() >= deadline
        ticks = budget
        late = 1
    # ---- ITE gates: clause (l | -c | -t) with c positive, its partner
    # (-l | -c | t), and for some e the pair (l | c | -e), (-l | c | e).
    ord = i64[18]
    ord[0] = 0
    ord[1] = 1
    ord[2] = 2
    ord[3] = 0
    ord[4] = 2
    ord[5] = 1
    ord[6] = 1
    ord[7] = 0
    ord[8] = 2
    ord[9] = 1
    ord[10] = 2
    ord[11] = 0
    ord[12] = 2
    ord[13] = 0
    ord[14] = 1
    ord[15] = 2
    ord[16] = 1
    ord[17] = 0
    st[11] += ticks
    ticks = 0 if late == 0
    i = 0
    while i < ni && ticks < budget
      base = i * 5
      if sk[base + 3] == 0
        r = 0
        while r < 6
          l = sk[base + ord[r * 3]] ## i64
          y = sk[base + ord[r * 3 + 1]] ## i64
          zc = sk[base + ord[r * 3 + 2]] ## i64
          if (y & 1) == 1
            cc = y ^ 1 ## i64
            t = zc ^ 1 ## i64
            ticks += 1
            if wassat_gc_has_tern(cht, sk, cmask, l ^ 1, y, t) == 1
              # Clauses holding both c and l: scan the shorter list.
              sx = cc ## i64
              sy = l ## i64
              if tst[l + 1] - tst[l] < tst[cc + 1] - tst[cc]
                sx = l
                sy = cc
              p = tst[sx]
              pe = tst[sx + 1]
              while p < pe
                ob = toc[p] * 5 ## i64
                p += 1
                ticks += 1
                third = 0 - 1 ## i64
                if sk[ob] == sy
                  third = sk[ob + 1] == sx ? sk[ob + 2] : sk[ob + 1]
                elsif sk[ob + 1] == sy
                  third = sk[ob] == sx ? sk[ob + 2] : sk[ob]
                elsif sk[ob + 2] == sy
                  third = sk[ob] == sx ? sk[ob + 1] : sk[ob]
                if third >= 0
                  e = third ^ 1 ## i64
                  ev = e >> 1 ## i64
                  if ev != (cc >> 1) && ev != (t >> 1) && ev != (l >> 1) && ng < maxg && au + 3 < acap
                    if wassat_gc_has_tern(cht, sk, cmask, cc, e, l ^ 1) == 1
                      gty[ng] = 3
                      glhs[ng] = l
                      goff[ng] = au
                      glen[ng] = 3
                      ar[au] = cc
                      ar[au + 1] = t
                      ar[au + 2] = e
                      au += 3
                      ng += 1
                      st[10] += 1
          r += 1
      i += 1
      if (i & 4095) == 0 && deadline > 0 && clock_ms() >= deadline
        ticks = budget
        late = 1
  st[11] += ticks
  st[18] = ng
  st[19] = au
  return 1 if ng == 0 && st[4] == 0
  # ---- closure.
  hcap = 1024 ## i64
  while hcap < 4 * ng + 4
    hcap = hcap << 1
  hmask = hcap - 1 ## i64
  ht = i64[hcap]
  ocap = 3 * (au + ng) + 64 ## i64
  ohead = i64[nv + 4]
  onext = i64[ocap]
  ogate = i64[ocap]
  qh = 0
  g = 0
  while g < ng && st[5] == 0 && st[1] == 0
    if wassat_gc_install(g, rep, gty, glhs, goff, glen, ar, ht, hmask, queue, st, tcon) == 1
      off = goff[g]
      n = glen[g]
      j = 0
      while j < n
        z = wassat_gc_watch(g, ar[off + j] >> 1, ohead, onext, ogate, st)
        j += 1
      z = wassat_gc_watch(g, glhs[g] >> 1, ohead, onext, ogate, st)
    qh = wassat_gc_drain(qh, rep, gty, glhs, goff, glen, ar, ht, hmask, queue, st, tcon, ohead, onext, ogate, deadline)
    g += 1
    if (g & 4095) == 0 && deadline > 0
      st[15] += 1
      st[5] = 1 if clock_ms() >= deadline
  1

# Returns nil when the lane declines or derives nothing, else the formula
# with the implied units and equivalences appended.
-> wassat_gate_closure_lift(formula, deadline = 0)
  return nil unless formula.has_key?("flat_ncl")
  nv = formula["nvars"]
  nc = formula["flat_ncl"]
  return nil if nv < 8 || nv > WASSAT_GATE_CLOSURE_MAX_VARS || nc < 8 || nc > WASSAT_GATE_CLOSURE_MAX_CLAUSES
  fla = formula["flat_lits"]
  fcs = formula["flat_offs"]
  fcl = formula["flat_lens"]
  nlits = formula["flat_nlits"]
  st = i64[24]
  rep = i64[nv + 4]
  return nil unless wassat_gc_close(fla, fcs, fcl, nc, nv, rep, st, deadline) == 1
  return nil if st[0] == 0 && st[1] == 0
  tcon = nv + 1
  # Count, then fill.
  units = 0
  eqs = 0
  v = 1
  while v <= nv
    r = wassat_gc_find(rep, v << 1)
    if r != (v << 1)
      if (r >> 1) == tcon
        units += 1
      else
        eqs += 1
    v += 1
  st[16] = units
  st[17] = eqs
  extra_c = units + 2 * eqs
  extra_l = units + 4 * eqs
  if st[1] != 0
    extra_c += 2
    extra_l += ((st[2] >> 1) == tcon || (st[3] >> 1) == tcon) ? 2 : 4
  out = i64[nlits + extra_l]
  off = i64[nc + extra_c]
  len = i64[nc + extra_c]
  i = 0
  while i < nlits
    out[i] = fla[i]
    i += 1
  i = 0
  while i < nc
    off[i] = fcs[i]
    len[i] = fcl[i]
    i += 1
  p = nlits
  c = nc
  v = 1
  while v <= nv
    r = wassat_gc_find(rep, v << 1)
    if r != (v << 1)
      if (r >> 1) == tcon
        off[c] = p
        len[c] = 1
        out[p] = (r & 1) == 0 ? v : 0 - v
        p += 1
        c += 1
      else
        rl = (r & 1) == 0 ? r >> 1 : 0 - (r >> 1)
        off[c] = p
        len[c] = 2
        out[p] = 0 - v
        out[p + 1] = rl
        off[c + 1] = p + 2
        len[c + 1] = 2
        out[p + 2] = v
        out[p + 3] = 0 - rl
        p += 4
        c += 2
    v += 1
  if st[1] != 0
    # The clash a = b against the classes above. A constant side makes the
    # other side a unit; two constants clash outright.
    a = st[2]
    b = st[3]
    if (a >> 1) == tcon
      x = a
      a = b
      b = x
    al = (a & 1) == 0 ? a >> 1 : 0 - (a >> 1)
    if (a >> 1) == tcon
      al = 1
      bl = 0 - 1
      off[c] = p
      len[c] = 1
      out[p] = al
      off[c + 1] = p + 1
      len[c + 1] = 1
      out[p + 1] = bl
      p += 2
    elsif (b >> 1) == tcon
      off[c] = p
      len[c] = 1
      out[p] = (b & 1) == 0 ? al : 0 - al
      off[c + 1] = p + 1
      len[c + 1] = 1
      out[p + 1] = out[p]
      p += 2
    else
      bl = (b & 1) == 0 ? b >> 1 : 0 - (b >> 1)
      off[c] = p
      len[c] = 2
      out[p] = 0 - al
      out[p + 1] = bl
      off[c + 1] = p + 2
      len[c + 1] = 2
      out[p + 2] = al
      out[p + 3] = 0 - bl
      p += 4
    c += 2
  lifted = { "nvars": nv, "nclauses": c, "clauses": [], "boxed": false,
    "flat_lits": out, "flat_offs": off, "flat_lens": len,
    "flat_ncl": c, "flat_nlits": p }
  { "formula": lifted, "work": st, "added_from": nc }
