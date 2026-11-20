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

# The wall limit is a backstop: extraction runs on tick allowances, and a
# limit close to the usual cost (0.4 s for half a million gates) made the
# lane come back empty whenever the machine was busy.
WASSAT_GATE_CLOSURE_MS = 8000
# Closure and rewriting alternate at most this often.
WASSAT_GATE_CLOSURE_ROUNDS = 8
# A closure without gates rewrites inputs of at most this many clauses.
WASSAT_GATE_CLOSURE_PLAIN_CLAUSES = 4000000
# Inputs up to this many variables are rewritten whatever the closure merged.
WASSAT_GATE_CLOSURE_REWRITE_ALWAYS = 20000
# Passes of one rewriting: a clause that shrinks to a unit starts another.
WASSAT_GATE_CLOSURE_PASSES = 40
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

-> wassat_gc_grow_arr(old_arr, used, new_cap) (i64[] i64 i64) i64[]
  nxt = i64[new_cap]
  i = 0 ## i64
  while i < used
    nxt[i] = old_arr[i]
    i += 1
  z = ccall("w_value_free_w", old_arr)
  nxt

-> wassat_gc_init_rep(rep, tcon) (i64[] i64) i64
  v = 0 ## i64
  while v <= tcon
    rep[v] = v << 1
    v += 1
  0

-> wassat_gc_census(fcl, ncl, counts, deadline) (i64[] i64 i64[] i64) i64
  n1 = 0 ## i64
  n2 = 0 ## i64
  n3 = 0 ## i64
  n4 = 0 ## i64
  n5 = 0 ## i64
  nlit = 0 ## i64
  ci = 0 ## i64
  while ci < ncl
    n = fcl[ci] ## i64
    nlit += n
    if n == 2
      n2 += 1
    elsif n == 3
      n3 += 1
    elsif n == 1
      n1 += 1
    elsif n == 4
      n4 += 1
    elsif n == 5
      n5 += 1
    ci += 1
    return 0 - 1 if (ci & 65535) == 0 && deadline > 0 && clock_ms() >= deadline
  counts[0] = nlit
  counts[1] = n1
  counts[2] = n2
  counts[3] = n3
  counts[4] = n4
  counts[5] = n5
  0

-> wassat_gc_cfg_decline?(formula)
  return false unless formula.has_key?("config")
  cfg = formula["config"]
  return false if cfg == nil
  u = cfg.units
  b = cfg.binary
  return false if u > 0 || b >= 2
  t = cfg.ternary
  return true if t > WASSAT_GATE_CLOSURE_MAX_INDEXED
  return true if t < 4 && cfg.large < 8
  false

-> wassat_gc_free_state(ga, gmeta)
  i = 0
  while i < ga.size
    z = ccall("w_value_free_w", ga[i]) if ga[i] != nil
    ga[i] = nil
    i += 1
  z = ccall("w_value_free_w", ga)
  z = ccall("w_value_free_w", gmeta) if gmeta != nil
  0

# Fast strided 512-clause structure probe over width 3..5 clauses.
# Counts clauses with (a) a binary side clause (-li | -lj) in (bst, bad), or
# (b) an adjacent width 3..5 clause sharing >= 2 variable IDs.
# Returns -1 when fewer than 128 width 3..5 clauses were sampled, else hit count.
-> wassat_gc_sample_structure(fla, fcs, fcl, ncl, has_bin_adj, bst, bad) (i64[] i64[] i64[] i64 i64 i64[] i64[]) i64
  stride = ncl >> 9 ## i64
  stride = 1 if stride < 1
  ci = 0 ## i64
  steps = 0 ## i64
  sampled = 0 ## i64
  hits = 0 ## i64
  while ci < ncl && steps < 512
    n = fcl[ci] ## i64
    if n >= 3 && n <= 5
      sampled += 1
      off = fcs[ci] ## i64
      hit = 0 ## i64
      if n == 3 && has_bin_adj == 1
        a0 = fla[off] ## i64
        a1 = fla[off + 1] ## i64
        a2 = fla[off + 2] ## i64
        nl0 = a0 > 0 ? ((a0 << 1) | 1) : ((0 - a0) << 1) ## i64
        nl1 = a1 > 0 ? ((a1 << 1) | 1) : ((0 - a1) << 1) ## i64
        nl2 = a2 > 0 ? ((a2 << 1) | 1) : ((0 - a2) << 1) ## i64
        if wassat_gc_has_bin(bst, bad, nl0, nl1) == 1 || wassat_gc_has_bin(bst, bad, nl0, nl2) == 1 || wassat_gc_has_bin(bst, bad, nl1, nl2) == 1
          hit = 1
      if hit == 0 && ci + 1 < ncl
        n2c = fcl[ci + 1] ## i64
        if n2c >= 3 && n2c <= 5
          off2 = fcs[ci + 1] ## i64
          shared = 0 ## i64
          j = 0 ## i64
          while j < n
            lj = fla[off + j] ## i64
            vj = lj < 0 ? 0 - lj : lj ## i64
            k = 0 ## i64
            while k < n2c
              lk = fla[off2 + k] ## i64
              vk = lk < 0 ? 0 - lk : lk ## i64
              if vj == vk
                shared += 1
                break
              k += 1
            j += 1
          hit = 1 if shared >= 2
      hits += hit
    ci += stride
    steps += 1
  return 0 - 1 if sampled < 128
  hits

# Exact permutation-invariant polarity-degree prefilter for XOR-3/4/5 and ITE-3.
# Writes keep_ci[ci] = 1 for eligible width 3..5 clauses and keep_counts[0..2] =
# [n3_keep, n4_keep, n5_keep]. Returns total kept clauses, or -1 on deadline.
-> wassat_gc_prefilter_xi(fla, fcs, fcl, ncl, nl, n3, n4, n5, keep_ci, keep_counts, deadline) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i8[] i64[] i64) i64
  d3 = i8[n3 >= 4 ? nl + 2 : 0]
  d4 = i8[n4 >= 8 ? nl + 2 : 0]
  d5 = i8[n5 >= 16 ? nl + 2 : 0]
  ci = 0 ## i64
  while ci < ncl
    n = fcl[ci] ## i64
    if n == 3 && n3 >= 4
      off = fcs[ci] ## i64
      j = 0 ## i64
      while j < 3
        a = fla[off + j] ## i64
        c = a > 0 ? (a << 1) : (((0 - a) << 1) | 1) ## i64
        d3[c] = d3[c] + 1 if d3[c] < 2
        j += 1
    elsif n == 4 && n4 >= 8
      off = fcs[ci]
      j = 0
      while j < 4
        a = fla[off + j]
        c = a > 0 ? (a << 1) : (((0 - a) << 1) | 1)
        d4[c] = d4[c] + 1 if d4[c] < 4
        j += 1
    elsif n == 5 && n5 >= 16
      off = fcs[ci]
      j = 0
      while j < 5
        a = fla[off + j]
        c = a > 0 ? (a << 1) : (((0 - a) << 1) | 1)
        d5[c] = d5[c] + 1 if d5[c] < 8
        j += 1
    ci += 1
    if (ci & 65535) == 0 && deadline > 0 && clock_ms() >= deadline
      z = ccall("w_value_free_w", d5)
      z = ccall("w_value_free_w", d4)
      z = ccall("w_value_free_w", d3)
      return 0 - 1
  k3 = 0 ## i64
  k4 = 0 ## i64
  k5 = 0 ## i64
  ci = 0
  while ci < ncl
    n = fcl[ci]
    if n == 3 && n3 >= 4
      off = fcs[ci]
      both1 = 0 ## i64
      both2 = 0 ## i64
      j = 0
      while j < 3
        a = fla[off + j]
        vp = (a > 0 ? a : 0 - a) << 1 ## i64
        dp = d3[vp] ## i64
        dn = d3[vp | 1] ## i64
        both1 += 1 if dp >= 1 && dn >= 1
        both2 += 1 if dp >= 2 && dn >= 2
        j += 1
      if both1 == 3 && both2 >= 2
        keep_ci[ci] = 1
        k3 += 1
    elsif n == 4 && n4 >= 8
      off = fcs[ci]
      ok4 = 1 ## i64
      j = 0
      while j < 4
        a = fla[off + j]
        vp = (a > 0 ? a : 0 - a) << 1
        if d4[vp] < 4 || d4[vp | 1] < 4
          ok4 = 0
          break
        j += 1
      if ok4 == 1
        keep_ci[ci] = 1
        k4 += 1
    elsif n == 5 && n5 >= 16
      off = fcs[ci]
      ok5 = 1 ## i64
      j = 0
      while j < 5
        a = fla[off + j]
        vp = (a > 0 ? a : 0 - a) << 1
        if d5[vp] < 8 || d5[vp | 1] < 8
          ok5 = 0
          break
        j += 1
      if ok5 == 1
        keep_ci[ci] = 1
        k5 += 1
    ci += 1
    if (ci & 65535) == 0 && deadline > 0 && clock_ms() >= deadline
      z = ccall("w_value_free_w", d5)
      z = ccall("w_value_free_w", d4)
      z = ccall("w_value_free_w", d3)
      return 0 - 1
  z = ccall("w_value_free_w", d5)
  z = ccall("w_value_free_w", d4)
  z = ccall("w_value_free_w", d3)
  keep_counts[0] = k3
  keep_counts[1] = k4
  keep_counts[2] = k5
  k3 + k4 + k5

# Gate extraction and closure. Fills rep and st; when keep_state == 1 and
# gates > 0, stores [gty, glhs, goff, glen, ar, ht, ohead, onext, ogate, queue]
# in ga and [ng, au, hmask, qh] in gmeta (otherwise frees all scratch).
-> wassat_gc_close_state(fla, fcs, fcl, ncl, nv, rep, st, counts, keep_state, ga, gmeta, deadline) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64 Array i64[] i64) i64
  nlit = counts[0] ## i64
  n1 = counts[1] ## i64
  n2 = counts[2] ## i64
  n3 = counts[3] ## i64
  n4 = counts[4] ## i64
  n5 = counts[5] ## i64
  nidx = n3 + n4 + n5 ## i64
  can_xi = 0 ## i64
  if nidx > 0 && nidx <= WASSAT_GATE_CLOSURE_MAX_INDEXED && (n3 >= 4 || n4 >= 8 || n5 >= 16)
    can_xi = 1
  return 0 if n1 == 0 && n2 < 2 && can_xi == 0
  tcon = nv + 1 ## i64
  nl = (nv + 2) << 1 ## i64
  tt = tcon << 1 ## i64
  z = wassat_gc_init_rep(rep, tcon)
  queue = i64[nv + 4]
  nbin = 0 ## i64
  run_and = 0 ## i64
  bst = i64[0]
  bad = i64[0]
  has_bin_adj = 0 ## i64
  if n2 >= 2
    z = ccall("w_value_free_w", bst)
    bst = i64[nl + 2]
    ci = 0 ## i64
    while ci < ncl
      if fcl[ci] == 2
        off = fcs[ci] ## i64
        a = fla[off] ## i64
        b = fla[off + 1] ## i64
        ca = a > 0 ? a << 1 : ((0 - a) << 1) | 1 ## i64
        cb = b > 0 ? b << 1 : ((0 - b) << 1) | 1 ## i64
        if (ca >> 1) != (cb >> 1)
          bst[ca + 1] += 1
          bst[cb + 1] += 1
          nbin += 1
      ci += 1
      if (ci & 65535) == 0 && deadline > 0 && clock_ms() >= deadline
        st[5] = 1
        z = ccall("w_value_free_w", bst)
        z = ccall("w_value_free_w", bad)
        z = ccall("w_value_free_w", queue)
        return 1
    st[13] = nbin
    if nbin >= 2
      has_bin_adj = 1
      c = 0 ## i64
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
        if (ci & 65535) == 0 && deadline > 0 && clock_ms() >= deadline
          st[5] = 1
          z = ccall("w_value_free_w", fill)
          z = ccall("w_value_free_w", bun)
          z = ccall("w_value_free_w", bst)
          z = ccall("w_value_free_w", bad)
          z = ccall("w_value_free_w", queue)
          return 1
      z = ccall("w_value_free_w", bad)
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
      z = ccall("w_value_free_w", fill)
      z = ccall("w_value_free_w", bun)
      run_and = 1 if nbin * 8 >= ncl
    else
      z = ccall("w_value_free_w", bst)
      bst = i64[0]
  elsif n2 == 1
    # Count single non-tautological binary for st[13] parity, no eq/AND possible.
    ci = 0
    while ci < ncl
      if fcl[ci] == 2
        off = fcs[ci]
        a = fla[off]
        b = fla[off + 1]
        va = a > 0 ? a : 0 - a ## i64
        vb = b > 0 ? b : 0 - b ## i64
        nbin += 1 if va != vb
      ci += 1
      if (ci & 65535) == 0 && deadline > 0 && clock_ms() >= deadline
        st[5] = 1
        z = ccall("w_value_free_w", bst)
        z = ccall("w_value_free_w", bad)
        z = ccall("w_value_free_w", queue)
        return 1
    st[13] = nbin
  # ---- units and binary-pair equivalences.
  if n1 > 0 || has_bin_adj == 1
    ci = 0
    while ci < ncl
      n = fcl[ci] ## i64
      if n == 1
        a = fla[fcs[ci]]
        ca = a > 0 ? a << 1 : ((0 - a) << 1) | 1
        z = wassat_gc_merge(rep, queue, st, tcon, ca, tt)
      elsif n == 2 && has_bin_adj == 1
        off = fcs[ci]
        a = fla[off]
        b = fla[off + 1]
        ca = a > 0 ? a << 1 : ((0 - a) << 1) | 1
        cb = b > 0 ? b << 1 : ((0 - b) << 1) | 1
        if (ca >> 1) != (cb >> 1)
          lo = ca < cb ? ca : cb ## i64
          if (lo & 1) == 0 && wassat_gc_has_bin(bst, bad, ca ^ 1, cb ^ 1) == 1
            z = wassat_gc_merge(rep, queue, st, tcon, ca ^ 1, cb)
      ci += 1
      if (ci & 65535) == 0 && deadline > 0 && clock_ms() >= deadline
        st[5] = 1
        z = ccall("w_value_free_w", bst)
        z = ccall("w_value_free_w", bad)
        z = ccall("w_value_free_w", queue)
        return 1
  if run_and == 0 && can_xi == 0
    z = ccall("w_value_free_w", bst)
    z = ccall("w_value_free_w", bad)
    z = ccall("w_value_free_w", queue)
    return 1
  # ---- gate arena (starts small, doubles on demand up to original ceiling).
  maxg_cap = 2 * ncl + 16 ## i64
  acap_cap = 2 * nlit + 64 ## i64
  maxg = maxg_cap < 4096 ? maxg_cap : 4096 ## i64
  acap = acap_cap < 16384 ? acap_cap : 16384 ## i64
  gty = i64[maxg]
  glhs = i64[maxg]
  goff = i64[maxg]
  glen = i64[maxg]
  ar = i64[acap]
  ng = 0 ## i64
  au = 0 ## i64
  ticks = 0 ## i64
  late = 0 ## i64
  budget = WASSAT_GATE_CLOSURE_TICKS + WASSAT_GATE_CLOSURE_TICKS_PER_LITERAL * nlit ## i64
  # ---- AND gates.
  if run_and == 1
    ci = 0
    while ci < ncl && ticks < budget
      n = fcl[ci]
      if n >= 3 && n <= WASSAT_GATE_CLOSURE_MAX_AND + 1
        off = fcs[ci]
        j = 0 ## i64
        while j < n
          a = fla[off + j]
          ca = a > 0 ? a << 1 : ((0 - a) << 1) | 1
          na = ca ^ 1 ## i64
          if bst[na + 1] - bst[na] >= n - 1
            if ng + 2 >= maxg && maxg < maxg_cap
              nmaxg = maxg << 1 ## i64
              nmaxg = maxg_cap if nmaxg > maxg_cap
              gty = wassat_gc_grow_arr(gty, ng, nmaxg)
              glhs = wassat_gc_grow_arr(glhs, ng, nmaxg)
              goff = wassat_gc_grow_arr(goff, ng, nmaxg)
              glen = wassat_gc_grow_arr(glen, ng, nmaxg)
              maxg = nmaxg
            if au + n + 2 >= acap && acap < acap_cap
              nacap = acap << 1 ## i64
              while nacap < au + n + 16
                nacap = nacap << 1
              nacap = acap_cap if nacap > acap_cap
              ar = wassat_gc_grow_arr(ar, au, nacap)
              acap = nacap
            if ng < maxg && au + n < acap
              ok = 1 ## i64
              k = 0 ## i64
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
  unstructured_pure = 0 ## i64
  if can_xi == 1 && late == 0 && nidx >= 32768 && st[0] == 0 && st[1] == 0 && ng == 0
    shits = wassat_gc_sample_structure(fla, fcs, fcl, ncl, has_bin_adj, bst, bad)
    if shits >= 0 && shits < 4
      if has_bin_adj == 1
        can_xi = 0
      else
        unstructured_pure = 1
  z = ccall("w_value_free_w", bst)
  z = ccall("w_value_free_w", bad)
  # Each gate kind has its own allowance; only the deadline ends them all.
  st[11] = ticks
  ticks = 0 if late == 0
  # ---- clause set for sizes 3..5 (sorted literal codes, zero padded).
  if can_xi == 1 && ticks < budget
    use_keep = 0 ## i64
    keep_ci = i8[0]
    n3_eff = n3 ## i64
    n4_eff = n4 ## i64
    n5_eff = n5 ## i64
    nidx_eff = nidx ## i64
    if nidx >= 4096
      z = ccall("w_value_free_w", keep_ci)
      keep_ci = i8[ncl]
      kcounts = i64[3]
      nidx_eff = wassat_gc_prefilter_xi(fla, fcs, fcl, ncl, nl, n3, n4, n5, keep_ci, kcounts, deadline)
      n3_eff = kcounts[0]
      n4_eff = kcounts[1]
      n5_eff = kcounts[2]
      z = ccall("w_value_free_w", kcounts)
      if nidx_eff < 0
        late = 1
        st[5] = 1
        ticks = budget
        can_xi = 0
      elsif (n3_eff < 4 && n4_eff < 8 && n5_eff < 16) || (unstructured_pure == 1 && nidx_eff * 2 < nidx)
        can_xi = 0
      else
        use_keep = 1
    if can_xi == 0
      z = ccall("w_value_free_w", keep_ci)
    else
      ccap = 1024 ## i64
      while ccap < 2 * nidx_eff + 2
        ccap = ccap << 1
      cmask = ccap - 1 ## i64
      cht = i64[ccap]
      sk = i64[5 * nidx_eff + 5]
      tst = i64[nl + 2]
      ni = 0 ## i64
      ci = 0
      while ci < ncl
        n = fcl[ci]
        if n >= 3 && n <= 5 && (use_keep == 0 || keep_ci[ci] == 1)
          off = fcs[ci]
          base = ni * 5 ## i64
          j = 0 ## i64
          while j < 5
            sk[base + j] = 0
            j += 1
          j = 0
          while j < n
            a = fla[off + j]
            sk[base + j] = a > 0 ? a << 1 : ((0 - a) << 1) | 1
            j += 1
          z = wassat_gc_sort(sk, base, n)
          distinct = 1 ## i64
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
        if (ci & 65535) == 0 && deadline > 0 && clock_ms() >= deadline
          late = 1
          st[5] = 1
          ticks = budget
          break
      z = ccall("w_value_free_w", keep_ci)
      st[14] = ni
      # Ternary occurrences per literal.
      toc = i64[0]
      if n3_eff >= 4 && late == 0
        z = ccall("w_value_free_w", toc)
        c = 0
        while c <= nl
          tst[c + 1] += tst[c]
          c += 1
        toc = i64[tst[nl] + 2]
        tfill = i64[nl + 2]
        i = 0 ## i64
        while i < ni
          base = i * 5
          if sk[base + 3] == 0
            j = 0
            while j < 3
              x = sk[base + j] ## i64
              toc[tst[x] + tfill[x]] = i
              tfill[x] += 1
              j += 1
          i += 1
          if (i & 65535) == 0 && deadline > 0 && clock_ms() >= deadline
            late = 1
            st[5] = 1
            ticks = budget
            break
        z = ccall("w_value_free_w", tfill)
      # ---- XOR gates: the representative clause of a parity class has no
      # negative literal, or exactly one on its smallest variable.
      i = 0 ## i64
      while i < ni && ticks < budget && late == 0
        base = i * 5
        n = 3 ## i64
        n = 4 if sk[base + 3] != 0
        n = 5 if sk[base + 4] != 0
        if (n == 3 && n3_eff >= 4) || (n == 4 && n4_eff >= 8) || (n == 5 && n5_eff >= 16)
          negs = 0 ## i64
          j = 0
          while j < n
            negs += sk[base + j] & 1
            j += 1
          if negs == 0 || (negs == 1 && (sk[base] & 1) == 1)
            v0 = sk[base] & (0 - 2) ## i64
            v1 = sk[base + 1] & (0 - 2) ## i64
            v2 = sk[base + 2] & (0 - 2) ## i64
            v3 = n >= 4 ? (sk[base + 3] & (0 - 2)) : 0 ## i64
            v4 = n == 5 ? (sk[base + 4] & (0 - 2)) : 0 ## i64
            ok = 1 ## i64
            if n == 3
              if tst[v0 + 1] - tst[v0] < 2 || tst[v0 + 2] - tst[v0 + 1] < 2 || tst[v1 + 1] - tst[v1] < 2 || tst[v1 + 2] - tst[v1 + 1] < 2 || tst[v2 + 1] - tst[v2] < 2 || tst[v2 + 2] - tst[v2 + 1] < 2
                ok = 0
            # Clause i itself is mask == 0 (negs == 0) or mask == 1 (negs == 1);
            # start directly at the first 2-flip partner clause.
            mask = negs == 0 ? 3 : 2 ## i64
            full = (1 << n) - 1 ## i64
            while mask <= full && ok == 1
              pc = ccall_nobox("__w_bit_ctpop_u64", mask) ## i64
              if (pc & 1) == negs
                x0 = v0 | (mask & 1) ## i64
                x1 = v1 | ((mask >> 1) & 1) ## i64
                x2 = v2 | ((mask >> 2) & 1) ## i64
                x3 = n >= 4 ? (v3 | ((mask >> 3) & 1)) : 0 ## i64
                x4 = n == 5 ? (v4 | ((mask >> 4) & 1)) : 0 ## i64
                ticks += 1
                ok = 0 if wassat_gc_clause_at(cht, sk, cmask, n, x0, x1, x2, x3, x4) <= 0
              mask += 1
            if ok == 1
              if ng + n + 2 >= maxg && maxg < maxg_cap
                nmaxg = maxg << 1
                while nmaxg < ng + n + 8
                  nmaxg = nmaxg << 1
                nmaxg = maxg_cap if nmaxg > maxg_cap
                gty = wassat_gc_grow_arr(gty, ng, nmaxg)
                glhs = wassat_gc_grow_arr(glhs, ng, nmaxg)
                goff = wassat_gc_grow_arr(goff, ng, nmaxg)
                glen = wassat_gc_grow_arr(glen, ng, nmaxg)
                maxg = nmaxg
              if au + n * n + 4 >= acap && acap < acap_cap
                nacap = acap << 1
                while nacap < au + n * n + 16
                  nacap = nacap << 1
                nacap = acap_cap if nacap > acap_cap
                ar = wassat_gc_grow_arr(ar, au, nacap)
                acap = nacap
              if ng + n < maxg && au + n * n < acap
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
        break if st[9] == 0 && ng == 0 && st[0] == 0 && ticks >= 250000
        if (i & 4095) == 0 && deadline > 0 && clock_ms() >= deadline
          ticks = budget
          late = 1
      # ---- ITE gates: clause (l | -c | -t) with l and c positive, its partner
      # (-l | -c | t), and for some e the pair (l | c | -e), (-l | c | e).
      st[11] += ticks
      ticks = 0 if late == 0
      if n3_eff >= 4 && ticks < budget && late == 0
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
        i = 0
        while i < ni && ticks < budget
          base = i * 5
          if sk[base + 3] == 0
            r = 0 ## i64
            while r < 6
              l = sk[base + ord[r * 3]] ## i64
              y = sk[base + ord[r * 3 + 1]] ## i64
              zc = sk[base + ord[r * 3 + 2]] ## i64
              if (l & 1) == 0 && (y & 1) == 1
                cc = y ^ 1 ## i64
                t = zc ^ 1 ## i64
                ln = l ^ 1 ## i64
                if tst[l + 1] - tst[l] >= 2 && tst[ln + 1] - tst[ln] >= 2 && tst[y + 1] - tst[y] >= 2 && tst[cc + 1] - tst[cc] >= 2 && tst[t + 1] - tst[t] >= 1
                  ticks += 1
                  if wassat_gc_has_tern(cht, sk, cmask, ln, y, t) == 1
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
                        if ev != (cc >> 1) && ev != (t >> 1) && ev != (l >> 1)
                          if tst[e + 1] - tst[e] >= 1 && wassat_gc_has_tern(cht, sk, cmask, cc, e, ln) == 1
                            if ng + 2 >= maxg && maxg < maxg_cap
                              nmaxg = maxg << 1
                              nmaxg = maxg_cap if nmaxg > maxg_cap
                              gty = wassat_gc_grow_arr(gty, ng, nmaxg)
                              glhs = wassat_gc_grow_arr(glhs, ng, nmaxg)
                              goff = wassat_gc_grow_arr(goff, ng, nmaxg)
                              glen = wassat_gc_grow_arr(glen, ng, nmaxg)
                              maxg = nmaxg
                            if au + 6 >= acap && acap < acap_cap
                              nacap = acap << 1
                              nacap = acap_cap if nacap > acap_cap
                              ar = wassat_gc_grow_arr(ar, au, nacap)
                              acap = nacap
                            if ng < maxg && au + 3 < acap
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
          break if st[10] == 0 && st[9] == 0 && ng == 0 && st[0] == 0 && ticks >= 250000
          if (i & 4095) == 0 && deadline > 0 && clock_ms() >= deadline
            ticks = budget
            late = 1
        z = ccall("w_value_free_w", ord)
      z = ccall("w_value_free_w", toc)
      z = ccall("w_value_free_w", tst)
      z = ccall("w_value_free_w", sk)
      z = ccall("w_value_free_w", cht)
  st[11] += ticks
  st[18] = ng
  st[19] = au
  if ng == 0
    z = ccall("w_value_free_w", ar)
    z = ccall("w_value_free_w", glen)
    z = ccall("w_value_free_w", goff)
    z = ccall("w_value_free_w", glhs)
    z = ccall("w_value_free_w", gty)
    z = ccall("w_value_free_w", queue)
    return 1
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
  qh = 0 ## i64
  g = 0 ## i64
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
  if keep_state == 1 && st[1] == 0
    ga[0] = gty
    ga[1] = glhs
    ga[2] = goff
    ga[3] = glen
    ga[4] = ar
    ga[5] = ht
    ga[6] = ohead
    ga[7] = onext
    ga[8] = ogate
    ga[9] = queue
    gmeta[0] = ng
    gmeta[1] = au
    gmeta[2] = hmask
    gmeta[3] = qh
  else
    z = ccall("w_value_free_w", ogate)
    z = ccall("w_value_free_w", onext)
    z = ccall("w_value_free_w", ohead)
    z = ccall("w_value_free_w", ht)
    z = ccall("w_value_free_w", ar)
    z = ccall("w_value_free_w", glen)
    z = ccall("w_value_free_w", goff)
    z = ccall("w_value_free_w", glhs)
    z = ccall("w_value_free_w", gty)
    z = ccall("w_value_free_w", queue)
  1

# Gate extraction and closure. Fills rep (representative literal code per
# variable) and st. Returns 1 when the closure ran, 0 on a declined shape.
-> wassat_gc_close(fla, fcs, fcl, ncl, nv, rep, st, deadline) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64) i64
  counts = i64[6]
  if wassat_gc_census(fcl, ncl, counts, deadline) < 0
    st[5] = 1
    z = ccall("w_value_free_w", counts)
    return 0
  ga = [nil, nil, nil, nil, nil, nil, nil, nil, nil, nil]
  gmeta = i64[4]
  ran = wassat_gc_close_state(fla, fcs, fcl, ncl, nv, rep, st, counts, 0, ga, gmeta, deadline)
  z = ccall("w_value_free_w", gmeta)
  z = ccall("w_value_free_w", ga)
  z = ccall("w_value_free_w", counts)
  ran

# Returns nil when the lane declines or derives nothing, else the formula
# with the implied units and equivalences appended.
-> wassat_gate_closure_lift(formula, deadline = 0)
  return nil unless formula.has_key?("flat_ncl")
  nv = formula["nvars"]
  nc = formula["flat_ncl"]
  return nil if nv < 8 || nv > WASSAT_GATE_CLOSURE_MAX_VARS || nc < 8 || nc > WASSAT_GATE_CLOSURE_MAX_CLAUSES
  return nil if wassat_gc_cfg_decline?(formula)
  fla = formula["flat_lits"] ## i64[]
  fcs = formula["flat_offs"] ## i64[]
  fcl = formula["flat_lens"] ## i64[]
  counts = i64[6]
  cfg = formula.has_key?("config") ? formula["config"] : nil
  if cfg != nil && cfg.large == 0
    counts[0] = cfg.nliterals
    counts[1] = cfg.units
    counts[2] = cfg.binary
    counts[3] = cfg.ternary
  else
    if wassat_gc_census(fcl, nc, counts, deadline) < 0
      z = ccall("w_value_free_w", counts)
      return nil
  nidx = counts[3] + counts[4] + counts[5]
  can_xi = nidx > 0 && nidx <= WASSAT_GATE_CLOSURE_MAX_INDEXED && (counts[3] >= 4 || counts[4] >= 8 || counts[5] >= 16)
  if counts[1] == 0 && counts[2] < 2 && !can_xi
    z = ccall("w_value_free_w", counts)
    return nil
  st = i64[24]
  rep = i64[nv + 4]
  ga = [nil, nil, nil, nil, nil, nil, nil, nil, nil, nil]
  gmeta = i64[4]
  ran = wassat_gc_close_state(fla, fcs, fcl, nc, nv, rep, st, counts, 0, ga, gmeta, deadline)
  z = ccall("w_value_free_w", gmeta)
  z = ccall("w_value_free_w", ga)
  z = ccall("w_value_free_w", counts)
  if ran != 1 || (st[0] == 0 && st[1] == 0)
    z = ccall("w_value_free_w", rep)
    z = ccall("w_value_free_w", st)
    return nil
  res = wassat_gate_closure_append(formula, rep, st)
  z = ccall("w_value_free_w", rep)
  res

-> wassat_gc_count_rep(rep, nv, meta) (i64[] i64 i64[]) i64
  tcon = nv + 1 ## i64
  units = 0 ## i64
  eqs = 0 ## i64
  v = 1 ## i64
  while v <= nv
    r = wassat_gc_find(rep, v << 1)
    if r != (v << 1)
      if (r >> 1) == tcon
        units += 1
      else
        eqs += 1
    v += 1
  meta[0] = units
  meta[1] = eqs
  units + eqs

-> wassat_gc_emit_rep(fla, fcs, fcl, nc, nlits, nv, rep, st, emit_clash, out, off, len, meta) (i64[] i64[] i64[] i64 i64 i64 i64[] i64[] i64 i64[] i64[] i64[] i64[]) i64
  tcon = nv + 1 ## i64
  i = 0 ## i64
  while i < nlits
    out[i] = fla[i]
    i += 1
  i = 0
  while i < nc
    off[i] = fcs[i]
    len[i] = fcl[i]
    i += 1
  p = nlits ## i64
  c = nc ## i64
  v = 1 ## i64
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
        rl = (r & 1) == 0 ? r >> 1 : 0 - (r >> 1) ## i64
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
  if emit_clash == 1 && st[1] != 0
    # The clash a = b against the classes above. A constant side makes the
    # other side a unit; two constants clash outright.
    a = st[2] ## i64
    b = st[3] ## i64
    if (a >> 1) == tcon
      x = a ## i64
      a = b
      b = x
    al = (a & 1) == 0 ? a >> 1 : 0 - (a >> 1) ## i64
    if (a >> 1) == tcon
      off[c] = p
      len[c] = 1
      out[p] = 1
      off[c + 1] = p + 1
      len[c + 1] = 1
      out[p + 1] = 0 - 1
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
      bl = (b & 1) == 0 ? b >> 1 : 0 - (b >> 1) ## i64
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
  meta[0] = c
  meta[1] = p
  c

# The input with the closure's units and equivalences appended.
-> wassat_gate_closure_append(formula, rep, st)
  nv = formula["nvars"]
  nc = formula["flat_ncl"]
  fla = formula["flat_lits"] ## i64[]
  fcs = formula["flat_offs"] ## i64[]
  fcl = formula["flat_lens"] ## i64[]
  nlits = formula["flat_nlits"]
  tcon = nv + 1
  rmeta = i64[2]
  z = wassat_gc_count_rep(rep, nv, rmeta)
  units = rmeta[0]
  eqs = rmeta[1]
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
  z = wassat_gc_emit_rep(fla, fcs, fcl, nc, nlits, nv, rep, st, 1, out, off, len, rmeta)
  c = rmeta[0]
  p = rmeta[1]
  z = ccall("w_value_free_w", rmeta)
  lifted = { "nvars": nv, "nclauses": c, "clauses": [], "boxed": false,
    "flat_lits": out, "flat_offs": off, "flat_lens": len,
    "flat_ncl": c, "flat_nlits": p }
  { "formula": lifted, "work": st, "added_from": nc, "rewritten": false }

# Single-pass clause rewrite + linear 2-watched-literal unit propagation +
# hash deduplication over core clauses (without emitting the rep tail yet).
# Newly discovered unit root variables are written into new_units[0..uqn-1]
# and rw_meta: [core_c, core_nlits, total_c, total_nlits, uqn].
# Returns total_c (core_c + appended_c), or -1 on an empty clause.
-> wassat_gc_rewrite_core(fla, fcs, fcl, nc, nv, rep, out, off, len, mark, stamp_box, new_units, rw_meta, st, deadline) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64) i64
  tcon = nv + 1 ## i64
  stamp = stamp_box[0] ## i64
  c = 0 ## i64
  p = 0 ## i64
  uqn = 0 ## i64
  ci = 0 ## i64
  while ci < nc
    n = fcl[ci] ## i64
    o = fcs[ci] ## i64
    start = p ## i64
    stamp += 1
    sat = 0 ## i64
    j = 0 ## i64
    while j < n && sat == 0
      x = fla[o + j] ## i64
      code = x > 0 ? x << 1 : ((0 - x) << 1) | 1 ## i64
      r = wassat_gc_find(rep, code)
      rv = r >> 1 ## i64
      if rv == tcon
        sat = 1 if (r & 1) == 0
      elsif mark[r] != stamp
        if mark[r ^ 1] == stamp
          sat = 1
        else
          mark[r] = stamp
          out[p] = (r & 1) == 0 ? rv : 0 - rv
          p += 1
      j += 1
    if sat == 1
      p = start
    else
      k = p - start ## i64
      if k == 0
        stamp_box[0] = stamp
        st[1] = 1
        return 0 - 1
      if k == 1
        x = out[start] ## i64
        vx = x > 0 ? x : 0 - x ## i64
        rep[vx] = x > 0 ? (tcon << 1) : ((tcon << 1) | 1)
        new_units[uqn] = vx
        uqn += 1
        st[22] += 1
        p = start
      else
        off[c] = start
        len[c] = k
        c += 1
    ci += 1
  passes = 1 ## i64
  if uqn > 0 && c > 0
    passes = 2
    uqn_init = uqn ## i64
    whead = i64[(nv + 2) << 1]
    wnext = i64[2 * c + 4]
    ci = 0
    while ci < c
      o = off[ci] ## i64
      n = len[ci] ## i64
      sat = 0
      m = 0 ## i64
      j = 0
      while j < n && sat == 0
        lit = out[o + j] ## i64
        v = lit > 0 ? lit : 0 - lit ## i64
        rc = rep[v] ## i64
        if (rc >> 1) == tcon
          if ((rc & 1) == 0 && lit > 0) || ((rc & 1) == 1 && lit < 0)
            sat = 1
        else
          out[o + m] = lit
          m += 1
        j += 1
      if sat == 1
        len[ci] = 0
      elsif m == 0
        z = ccall("w_value_free_w", wnext)
        z = ccall("w_value_free_w", whead)
        stamp_box[0] = stamp
        st[1] = 1
        return 0 - 1
      elsif m == 1
        lit = out[o] ## i64
        vx = lit > 0 ? lit : 0 - lit ## i64
        rep[vx] = lit > 0 ? (tcon << 1) : ((tcon << 1) | 1)
        new_units[uqn] = vx
        uqn += 1
        st[22] += 1
        len[ci] = 0
      else
        len[ci] = m
        l0 = out[o] ## i64
        c0 = l0 > 0 ? (l0 << 1) : (((0 - l0) << 1) | 1) ## i64
        n0 = 2 * ci ## i64
        wnext[n0] = whead[c0]
        whead[c0] = n0 + 1
        l1 = out[o + 1] ## i64
        c1 = l1 > 0 ? (l1 << 1) : (((0 - l1) << 1) | 1) ## i64
        n1 = n0 + 1 ## i64
        wnext[n1] = whead[c1]
        whead[c1] = n1 + 1
      ci += 1
    uqh = uqn_init ## i64
    late_rw = 0 ## i64
    while uqh < uqn && late_rw == 0
      uv = new_units[uqh] ## i64
      uqh += 1
      urc = rep[uv] ## i64
      # Watch list of the literal of uv that just became FALSE.
      fcode = (urc & 1) == 0 ? ((uv << 1) | 1) : (uv << 1) ## i64
      e = whead[fcode] ## i64
      whead[fcode] = 0
      while e != 0
        idx = e - 1 ## i64
        nxe = wnext[idx] ## i64
        ci = idx >> 1
        slot = idx & 1 ## i64
        n = len[ci]
        if n > 0
          o = off[ci]
          other = out[o + (slot ^ 1)] ## i64
          ov = other > 0 ? other : 0 - other ## i64
          orc = rep[ov] ## i64
          if (orc >> 1) == tcon && (((orc & 1) == 0 && other > 0) || ((orc & 1) == 1 && other < 0))
            len[ci] = 0
          else
            moved = 0 ## i64
            j = 2 ## i64
            while j < n && moved == 0
              cand = out[o + j] ## i64
              cv = cand > 0 ? cand : 0 - cand ## i64
              crc = rep[cv] ## i64
              if (crc >> 1) != tcon
                out[o + j] = out[o + slot]
                out[o + slot] = cand
                ccode = cand > 0 ? (cv << 1) : ((cv << 1) | 1) ## i64
                wnext[idx] = whead[ccode]
                whead[ccode] = idx + 1
                moved = 1
              elsif ((crc & 1) == 0 && cand > 0) || ((crc & 1) == 1 && cand < 0)
                len[ci] = 0
                moved = 1
              j += 1
            if moved == 0
              if (orc >> 1) == tcon
                z = ccall("w_value_free_w", wnext)
                z = ccall("w_value_free_w", whead)
                stamp_box[0] = stamp
                st[1] = 1
                return 0 - 1
              rep[ov] = other > 0 ? (tcon << 1) : ((tcon << 1) | 1)
              new_units[uqn] = ov
              uqn += 1
              st[22] += 1
              len[ci] = 0
        e = nxe
      if (uqh & 1023) == 0 && deadline > 0 && clock_ms() >= deadline
        late_rw = 1
    z = ccall("w_value_free_w", wnext)
    z = ccall("w_value_free_w", whead)
  st[23] = passes
  # Clauses that became equal are written once: the defining clauses of two
  # merged gates are the same clauses now.
  hcap = 16 ## i64
  while hcap < c * 2
    hcap = hcap << 1
  hmask = hcap - 1 ## i64
  heads = i64[hcap]
  nextc = i64[c + 1]
  hval = i64[c + 1]
  q = 0 ## i64
  wp = 0 ## i64
  ci = 0
  while ci < c
    n = len[ci] ## i64
    if n > 0
      o = off[ci] ## i64
      sat = 0
      m = n ## i64
      if passes == 2
        m = 0
        j = 0
        while j < n && sat == 0
          lit = out[o + j] ## i64
          v = lit > 0 ? lit : 0 - lit ## i64
          rc = rep[v] ## i64
          if (rc >> 1) == tcon
            if ((rc & 1) == 0 && lit > 0) || ((rc & 1) == 1 && lit < 0)
              sat = 1
          else
            out[o + m] = lit
            m += 1
          j += 1
      if sat == 0
        if m == 0
          z = ccall("w_value_free_w", hval)
          z = ccall("w_value_free_w", nextc)
          z = ccall("w_value_free_w", heads)
          stamp_box[0] = stamp
          st[1] = 1
          return 0 - 1
        if m == 1
          lit = out[o] ## i64
          vx = lit > 0 ? lit : 0 - lit ## i64
          if (rep[vx] >> 1) != tcon
            rep[vx] = lit > 0 ? (tcon << 1) : ((tcon << 1) | 1)
            new_units[uqn] = vx
            uqn += 1
            st[22] += 1
        else
          h = 0 ## i64
          stamp += 1
          j = 0
          while j < m
            x = out[o + j] ## i64
            code = x > 0 ? x << 1 : ((0 - x) << 1) | 1 ## i64
            mark[code] = stamp
            h = (h + (code * 2654435761)) & 4611686018427387903
            j += 1
          hb = (h ^ (h >> 16)) & hmask ## i64
          dup = 0 ## i64
          e = heads[hb] ## i64
          while e != 0 && dup == 0
            k = e - 1 ## i64
            if hval[k] == h && len[k] == m
              same = 1 ## i64
              ko = off[k] ## i64
              j = 0
              while j < m && same == 1
                y = out[ko + j] ## i64
                cy = y > 0 ? y << 1 : ((0 - y) << 1) | 1 ## i64
                same = 0 if mark[cy] != stamp
                j += 1
              dup = 1 if same == 1
            e = nextc[k]
          if dup == 0
            j = 0
            while j < m
              out[wp + j] = out[o + j]
              j += 1
            off[q] = wp
            len[q] = m
            hval[q] = h
            nextc[q] = heads[hb]
            heads[hb] = q + 1
            wp += m
            q += 1
          else
            st[16] += 1
    ci += 1
  z = ccall("w_value_free_w", hval)
  z = ccall("w_value_free_w", nextc)
  z = ccall("w_value_free_w", heads)
  stamp_box[0] = stamp
  rmeta = i64[2]
  merged = wassat_gc_count_rep(rep, nv, rmeta) ## i64
  units_cnt = rmeta[0] ## i64
  eqs_cnt = rmeta[1] ## i64
  z = ccall("w_value_free_w", rmeta)
  total_c = q + units_cnt + 2 * eqs_cnt ## i64
  total_p = wp + units_cnt + 4 * eqs_cnt ## i64
  st[17] = merged
  st[20] = total_c
  st[21] = total_p
  rw_meta[0] = q
  rw_meta[1] = wp
  rw_meta[2] = total_c
  rw_meta[3] = total_p
  rw_meta[4] = uqn
  total_c

-> wassat_gc_push_units(queue, st, new_units, uqn) (i64[] i64[] i64[] i64) i64
  i = 0 ## i64
  while i < uqn
    if st[4] < queue.size
      queue[st[4]] = new_units[i]
      st[4] += 1
    i += 1
  0

# Check binary equivalences among shrunk core clauses and cascade any merges
# through the persistent gate state.
-> wassat_gc_close_incremental(fla, fcs, fcl, ncl, nv, rep, st, ga, gmeta, deadline) (i64[] i64[] i64[] i64 i64 i64[] i64[] Array i64[] i64) i64
  tcon = nv + 1 ## i64
  nl = (nv + 2) << 1 ## i64
  st[0] = 0
  st[16] = 0
  st[22] = 0
  st[23] = 0
  ng = gmeta[0] ## i64
  if ng > 0
    gty = ga[0] ## i64[]
    glhs = ga[1] ## i64[]
    goff = ga[2] ## i64[]
    glen = ga[3] ## i64[]
    ar = ga[4] ## i64[]
    ht = ga[5] ## i64[]
    ohead = ga[6] ## i64[]
    onext = ga[7] ## i64[]
    ogate = ga[8] ## i64[]
    queue = ga[9] ## i64[]
    hmask = gmeta[2] ## i64
    # If hash or watch pool ran past 75% across rounds, compact active gates.
    if st[6] * 3 > hmask || st[7] + 4 * ng > ogate.size
      i = 0 ## i64
      while i <= hmask
        ht[i] = 0
        i += 1
      i = 0
      while i < ohead.size
        ohead[i] = 0
        i += 1
      st[5] = 0
      st[6] = 0
      st[7] = 0
      gmeta[3] = st[4]
      g = 0 ## i64
      while g < ng && st[5] == 0 && st[1] == 0
        if gty[g] != 0
          if wassat_gc_install(g, rep, gty, glhs, goff, glen, ar, ht, hmask, queue, st, tcon) == 1
            off = goff[g]
            n = glen[g]
            j = 0 ## i64
            while j < n
              z = wassat_gc_watch(g, ar[off + j] >> 1, ohead, onext, ogate, st)
              j += 1
            z = wassat_gc_watch(g, glhs[g] >> 1, ohead, onext, ogate, st)
          gmeta[3] = wassat_gc_drain(gmeta[3], rep, gty, glhs, goff, glen, ar, ht, hmask, queue, st, tcon, ohead, onext, ogate, deadline)
        g += 1
    else
      gmeta[3] = wassat_gc_drain(gmeta[3], rep, gty, glhs, goff, glen, ar, ht, hmask, queue, st, tcon, ohead, onext, ogate, deadline)
    # Check any new binary equivalences in the shrunk core clauses.
    if st[1] == 0 && st[5] == 0
      nbin = 0 ## i64
      ci = 0 ## i64
      while ci < ncl
        nbin += 1 if fcl[ci] == 2
        ci += 1
      if nbin >= 2
        bst = i64[nl + 2]
        nbin = 0
        ci = 0
        while ci < ncl
          if fcl[ci] == 2
            off = fcs[ci] ## i64
            a = fla[off] ## i64
            b = fla[off + 1] ## i64
            ca = a > 0 ? a << 1 : ((0 - a) << 1) | 1 ## i64
            cb = b > 0 ? b << 1 : ((0 - b) << 1) | 1 ## i64
            if (ca >> 1) != (cb >> 1)
              bst[ca + 1] += 1
              bst[cb + 1] += 1
              nbin += 1
          ci += 1
        if nbin >= 2
          c = 0 ## i64
          while c <= nl
            bst[c + 1] += bst[c]
            c += 1
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
          z = ccall("w_value_free_w", fill)
          z = ccall("w_value_free_w", bun)
          ci = 0
          while ci < ncl
            if fcl[ci] == 2
              off = fcs[ci]
              a = fla[off]
              b = fla[off + 1]
              ca = a > 0 ? a << 1 : ((0 - a) << 1) | 1
              cb = b > 0 ? b << 1 : ((0 - b) << 1) | 1
              if (ca >> 1) != (cb >> 1)
                lo = ca < cb ? ca : cb ## i64
                if (lo & 1) == 0 && wassat_gc_has_bin(bst, bad, ca ^ 1, cb ^ 1) == 1
                  z = wassat_gc_merge(rep, queue, st, tcon, ca ^ 1, cb)
            ci += 1
          z = ccall("w_value_free_w", bad)
          if gmeta[3] < st[4] && st[1] == 0 && st[5] == 0
            gmeta[3] = wassat_gc_drain(gmeta[3], rep, gty, glhs, goff, glen, ar, ht, hmask, queue, st, tcon, ohead, onext, ogate, deadline)
        z = ccall("w_value_free_w", bst)
  1

# Closure, then rewriting, repeated while the rewriting still uncovers units
# for the next closure to work with. Returns nil when the first closure
# declines or merges nothing. When that closure ends in a clash, or merges
# too little to pay for rewriting a large input (under one variable in 200),
# or the first rewriting is not a tenth shorter than the input, the result is
# the appending lift's: "rewritten" is false. Otherwise
#   { "rewritten": true, "formula", "work" (the first round's st), "rounds",
#     "units", "clauses_in", "clauses_out", "refuted", "history" }.
# The result has the same models as the input. "refuted" is true when a
# clause became empty; the formula then holds the two units (1) and (-1).
-> wassat_gate_closure_reduce(formula, deadline = 0)
  return nil unless formula.has_key?("flat_ncl")
  nv = formula["nvars"]
  nc = formula["flat_ncl"]
  return nil if nv < 8 || nv > WASSAT_GATE_CLOSURE_MAX_VARS || nc < 8 || nc > WASSAT_GATE_CLOSURE_MAX_CLAUSES
  return nil if wassat_gc_cfg_decline?(formula)
  fla = formula["flat_lits"] ## i64[]
  fcs = formula["flat_offs"] ## i64[]
  fcl = formula["flat_lens"] ## i64[]
  nlits = formula["flat_nlits"]
  counts = i64[6]
  cfg = formula.has_key?("config") ? formula["config"] : nil
  if cfg != nil && cfg.large == 0
    counts[0] = cfg.nliterals
    counts[1] = cfg.units
    counts[2] = cfg.binary
    counts[3] = cfg.ternary
  else
    if wassat_gc_census(fcl, nc, counts, deadline) < 0
      z = ccall("w_value_free_w", counts)
      return nil
  nidx = counts[3] + counts[4] + counts[5]
  can_xi = nidx > 0 && nidx <= WASSAT_GATE_CLOSURE_MAX_INDEXED && (counts[3] >= 4 || counts[4] >= 8 || counts[5] >= 16)
  if counts[1] == 0 && counts[2] < 2 && !can_xi
    z = ccall("w_value_free_w", counts)
    return nil

  st = i64[24]
  rep = i64[nv + 4]
  ga = [nil, nil, nil, nil, nil, nil, nil, nil, nil, nil]
  gmeta = i64[4]
  ran = wassat_gc_close_state(fla, fcs, fcl, nc, nv, rep, st, counts, 1, ga, gmeta, deadline)
  z = ccall("w_value_free_w", counts)

  if ran != 1 || (st[0] == 0 && st[1] == 0)
    wassat_gc_free_state(ga, gmeta)
    z = ccall("w_value_free_w", rep)
    z = ccall("w_value_free_w", st)
    return nil
  if st[1] != 0 || (nv > WASSAT_GATE_CLOSURE_REWRITE_ALWAYS && st[0] * 200 < nv) || (st[18] == 0 && nc > WASSAT_GATE_CLOSURE_PLAIN_CLAUSES)
    wassat_gc_free_state(ga, gmeta)
    res_app = wassat_gate_closure_append(formula, rep, st)
    z = ccall("w_value_free_w", rep)
    return res_app

  mark = i64[(nv + 3) * 2]
  stamp_box = i64[1]
  new_units = i64[nv + 4]
  rw_meta = i64[5]
  out = i64[nlits + 8]
  off = i64[nc + 8]
  len = i64[nc + 8]
  kept = wassat_gc_rewrite_core(fla, fcs, fcl, nc, nv, rep, out, off, len, mark, stamp_box, new_units, rw_meta, st, deadline)
  if kept >= 0 && kept * 10 > nc * 9
    z = ccall("w_value_free_w", len)
    z = ccall("w_value_free_w", off)
    z = ccall("w_value_free_w", out)
    z = ccall("w_value_free_w", rw_meta)
    z = ccall("w_value_free_w", new_units)
    z = ccall("w_value_free_w", stamp_box)
    z = ccall("w_value_free_w", mark)
    wassat_gc_free_state(ga, gmeta)
    res_app = wassat_gate_closure_append(formula, rep, st)
    z = ccall("w_value_free_w", rep)
    return res_app

  first = i64[24]
  i = 0
  while i < 24
    first[i] = st[i]
    i += 1
  hist = i64[4 * WASSAT_GATE_CLOSURE_ROUNDS + 4]
  hist[0] = st[17]
  hist[1] = st[22]
  hist[2] = st[16]
  hist[3] = kept
  rounds = 1
  known = st[17]
  refuted = false
  core_fla = out
  core_fcs = off
  core_fcl = len
  core_nc = rw_meta[0]
  core_nlits = rw_meta[1]

  if kept < 0
    refuted = true
  elsif ga[9] != nil && rw_meta[4] > 0
    q_arr = ga[9] ## i64[]
    z = wassat_gc_push_units(q_arr, st, new_units, rw_meta[4])

  going = !refuted && rounds < WASSAT_GATE_CLOSURE_ROUNDS && st[5] == 0 && known > 0 && st[22] > 0 && first[18] > 0
  while going
    going = false
    z = wassat_gc_close_incremental(core_fla, core_fcs, core_fcl, core_nc, nv, rep, st, ga, gmeta, deadline)
    if st[1] == 0 && st[0] != 0
      out2 = i64[core_nlits + 8]
      off2 = i64[core_nc + 8]
      len2 = i64[core_nc + 8]
      kept = wassat_gc_rewrite_core(core_fla, core_fcs, core_fcl, core_nc, nv, rep, out2, off2, len2, mark, stamp_box, new_units, rw_meta, st, deadline)
      z = ccall("w_value_free_w", core_fcl)
      z = ccall("w_value_free_w", core_fcs)
      z = ccall("w_value_free_w", core_fla)
      core_fla = out2
      core_fcs = off2
      core_fcl = len2
      core_nc = rw_meta[0]
      core_nlits = rw_meta[1]
      hist[4 * rounds] = st[17]
      hist[4 * rounds + 1] = st[22]
      hist[4 * rounds + 2] = st[16]
      hist[4 * rounds + 3] = kept
      rounds += 1
      if kept < 0
        refuted = true
      else
        if ga[9] != nil && rw_meta[4] > 0
          q_arr = ga[9] ## i64[]
          z = wassat_gc_push_units(q_arr, st, new_units, rw_meta[4])
        going = rounds < WASSAT_GATE_CLOSURE_ROUNDS && st[5] == 0 && st[17] > known && st[22] > 0
        known = st[17]

  z = ccall("w_value_free_w", rw_meta)
  z = ccall("w_value_free_w", new_units)
  z = ccall("w_value_free_w", stamp_box)
  z = ccall("w_value_free_w", mark)
  wassat_gc_free_state(ga, gmeta)

  if refuted
    z = ccall("w_value_free_w", core_fcl)
    z = ccall("w_value_free_w", core_fcs)
    z = ccall("w_value_free_w", core_fla)
    z = ccall("w_value_free_w", rep)
    z = ccall("w_value_free_w", st)
    rout = i64[2]
    roff = i64[2]
    rlen = i64[2]
    rout[0] = 1
    rout[1] = 0 - 1
    roff[0] = 0
    rlen[0] = 1
    roff[1] = 1
    rlen[1] = 1
    reduced_ref = { "nvars": nv, "nclauses": 2, "clauses": [], "boxed": false,
      "flat_lits": rout, "flat_offs": roff, "flat_lens": rlen,
      "flat_ncl": 2, "flat_nlits": 2 }
    return { "rewritten": true, "formula": reduced_ref, "work": first, "rounds": rounds, "units": 2, "history": hist,
      "clauses_in": formula["flat_ncl"], "clauses_out": 2, "refuted": true }

  rmeta = i64[2]
  z = wassat_gc_count_rep(rep, nv, rmeta)
  units_out = rmeta[0]
  eqs_out = rmeta[1]
  final_c = core_nc + units_out + 2 * eqs_out
  final_l = core_nlits + units_out + 4 * eqs_out
  fout = i64[final_l + 1]
  foff = i64[final_c + 1]
  flen = i64[final_c + 1]
  z = wassat_gc_emit_rep(core_fla, core_fcs, core_fcl, core_nc, core_nlits, nv, rep, st, 0, fout, foff, flen, rmeta)
  out_nc = rmeta[0]
  out_nl = rmeta[1]
  z = ccall("w_value_free_w", rmeta)
  z = ccall("w_value_free_w", core_fcl)
  z = ccall("w_value_free_w", core_fcs)
  z = ccall("w_value_free_w", core_fla)
  z = ccall("w_value_free_w", rep)
  z = ccall("w_value_free_w", st)
  reduced = { "nvars": nv, "nclauses": out_nc, "clauses": [], "boxed": false,
    "flat_lits": fout, "flat_offs": foff, "flat_lens": flen,
    "flat_ncl": out_nc, "flat_nlits": out_nl }
  { "rewritten": true, "formula": reduced, "work": first, "rounds": rounds, "units": units_out, "history": hist,
    "clauses_in": formula["flat_ncl"], "clauses_out": out_nc, "refuted": false }

