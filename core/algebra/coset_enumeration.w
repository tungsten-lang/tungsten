# Todd–Coxeter coset enumeration (HLT strategy with Holt's coincidence
# processing) for finitely presented groups.
#
# Generators x_0 .. x_(r-1); column 2k is x_k and column 2k+1 is x_k^-1.
# Relators and subgroup generators are lists of columns. The enumeration
# either closes, giving the index [G : H] (with H = 1 the order of G), or stops
# at a coset limit and reports failure. A closed table is a proof: every coset
# row is complete and every relator closes at every coset.
#
#   ce = CosetEnumeration.new(r, relators, subgroup_words, max_cosets)
#   ce.run         # -> index, or -1 if the limit was hit

-> ce_rep(p, k) (i64[] i64) i64
  r = k
  while p[r] != r
    r = p[r]
  c = k
  while p[c] != r
    nx = p[c]
    p[c] = r
    c = nx
  r

# merge cosets k and l; the larger representative dies and is queued
-> ce_merge(p, q, st, k, l) (i64[] i64[] i64[] i64 i64) i64
  a = ce_rep(p, k)
  b = ce_rep(p, l)
  if a == b
    return 0
  lo = a
  hi = b
  if b < a
    lo = b
    hi = a
  p[hi] = lo
  q[st[2]] = hi
  st[2] = st[2] + 1
  1

# coincidence of cosets a and b (Holt, Handbook of CGT, Alg. COINCIDENCE)
-> ce_coincidence(tab, p, q, st, nc, a, b) (i64[] i64[] i64[] i64[] i64 i64 i64) i64
  st[2] = 0
  ce_merge(p, q, st, a, b)
  i = 0
  while i < st[2]
    g = q[i]
    i += 1
    x = 0
    while x < nc
      h = tab[g * nc + x]
      if h >= 0
        xi = x + 1
        if x % 2 == 1
          xi = x - 1
        if tab[h * nc + xi] == g
          tab[h * nc + xi] = -1
        f1 = ce_rep(p, g)
        h1 = ce_rep(p, h)
        t1 = tab[f1 * nc + x]
        t2 = tab[h1 * nc + xi]
        if t1 >= 0
          ce_merge(p, q, st, h1, t1)
        elsif t2 >= 0
          ce_merge(p, q, st, f1, t2)
        else
          tab[f1 * nc + x] = h1
          tab[h1 * nc + xi] = f1
      x += 1
  0

# define a new coset as the image of c under column x; st[0] = number of cosets
-> ce_define(tab, p, st, nc, maxc, c, x) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  d = st[0]
  if d >= maxc
    st[1] = 1
    return -1
  st[0] = d + 1
  p[d] = d
  j = 0
  while j < nc
    tab[d * nc + j] = -1
    j += 1
  xi = x + 1
  if x % 2 == 1
    xi = x - 1
  tab[c * nc + x] = d
  tab[d * nc + xi] = c
  d

-> ce_scan_fill(tab, p, q, st, nc, maxc, c, w, ws, wl) (i64[] i64[] i64[] i64[] i64 i64 i64 i64[] i64 i64) i64
  f = c
  i = ws
  b = c
  j = ws + wl - 1
  while true
    # scan forward
    going = 1
    while going == 1 && i <= j
      nx = tab[f * nc + w[i]]
      if nx >= 0
        f = nx
        i += 1
      else
        going = 0
    if i > j
      if f != b
        ce_coincidence(tab, p, q, st, nc, f, b)
      return 0
    # scan backward
    going = 1
    while going == 1 && j >= i
      xj = w[j] + 1
      if w[j] % 2 == 1
        xj = w[j] - 1
      nb = tab[b * nc + xj]
      if nb >= 0
        b = nb
        j -= 1
      else
        going = 0
    if j < i
      ce_coincidence(tab, p, q, st, nc, f, b)
      return 0
    if i == j
      xi = w[i] + 1
      if w[i] % 2 == 1
        xi = w[i] - 1
      tab[f * nc + w[i]] = b
      tab[b * nc + xi] = f
      return 0
    d = ce_define(tab, p, st, nc, maxc, f, w[i])
    if d < 0
      return -1
  0

# the HLT loop; returns the number of live cosets or -1 on overflow
-> ce_hlt(tab, p, q, st, nc, maxc, w, wstart, wlen, nrel, hstart, hlen, nh) (i64[] i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64 i64[] i64[] i64) i64
  st[0] = 1
  st[1] = 0
  p[0] = 0
  j = 0
  while j < nc
    tab[j] = -1
    j += 1
  k = 0
  while k < nh
    ce_scan_fill(tab, p, q, st, nc, maxc, 0, w, hstart[k], hlen[k])
    k += 1
  c = 0
  while c < st[0]
    if p[c] == c
      k = 0
      while k < nrel && p[c] == c
        if ce_scan_fill(tab, p, q, st, nc, maxc, c, w, wstart[k], wlen[k]) < 0
          return -1
        k += 1
      x = 0
      while x < nc && p[c] == c
        if tab[c * nc + x] < 0
          if ce_define(tab, p, st, nc, maxc, c, x) < 0
            return -1
        x += 1
    c += 1
  live = 0
  c = 0
  while c < st[0]
    if p[c] == c
      live += 1
    c += 1
  live

+ CosetEnumeration
  -> new(@r, relators, subgroup, @maxc)
    @nc = 2 * @r
    total = 0
    relators.each ->(w)
      total += w.size
    subgroup.each ->(w)
      total += w.size
    @w = i64[total + 1]
    @wstart = i64[relators.size + 1]
    @wlen = i64[relators.size + 1]
    @hstart = i64[subgroup.size + 1]
    @hlen = i64[subgroup.size + 1]
    pos = 0
    k = 0
    while k < relators.size
      @wstart[k] = pos
      @wlen[k] = relators[k].size
      relators[k].each ->(x)
        @w[pos] = x
        pos += 1
      k += 1
    k = 0
    while k < subgroup.size
      @hstart[k] = pos
      @hlen[k] = subgroup[k].size
      subgroup[k].each ->(x)
        @w[pos] = x
        pos += 1
      k += 1
    @nrel = relators.size
    @nh = subgroup.size
    @cosets_defined = 0
    self

  ro :cosets_defined

  # index of the subgroup, or -1 if more than max_cosets were needed
  -> run
    tab = i64[@maxc * @nc + 1]
    p = i64[@maxc + 1]
    q = i64[@maxc + 1]
    st = i64[4]
    res = ce_hlt(tab, p, q, st, @nc, @maxc, @w, @wstart, @wlen, @nrel, @hstart, @hlen, @nh)
    @cosets_defined = st[0]
    res

  # freely reduce a word of columns
  -> .reduce(word)
    out = []
    word.each ->(x)
      xi = x + 1
      xi = x - 1 if x % 2 == 1
      if out.size > 0 && out[out.size - 1] == xi
        out.pop
      else
        out.push(x)
    out
