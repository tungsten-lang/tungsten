# The mod-2 Steenrod algebra in the Milnor basis, and a minimal resolution of F2 over it: the E2 page Ext_A^{s,t}(F2, F2) of the
# classical Adams spectral sequence for the 2-complete sphere.
#
# Milnor basis: Sq(r1, r2, …) of degree Σ r_i (2^i − 1). Product (Milnor 1958): Sq(R)·Sq(S) = Σ_X c(X) Sq(T(X)) over matrices
# X = (x_ij), i, j ≥ 0, x_00 unused, with Σ_j 2^j x_ij = r_i (i ≥ 1) and Σ_i x_ij = s_j (j ≥ 1); T_n = Σ_{i+j=n} x_ij and
# c(X) = Π_n multinomial(x_{0n}, x_{1,n−1}, …, x_{n0}) mod 2, which is 1 iff the binary digits of each antidiagonal are disjoint.
# Minimal resolution (degree by degree, as in Bruner's programs): C_s = free A-module on generators; in internal degree t, the new
# generators of C_s span ker(d_{s−1}) / im(d_s) in degree t, so dim Ext^{s,t} = number of generators of C_s in degree t.
# Bit vectors use 32-bit words (stored values stay below 2^47).
#
#   use core/algebra/steenrod
#   st = steenrod_new(36)           # Milnor basis and product table through degree 36
#   res = steenrod_resolve(st, 12)  # minimal resolution through homological degree 12
#   steenrod_ext(res, s, t)         # dim Ext^{s,t}

# --- the Milnor basis ---------------------------------------------------------------------------------------------------------

-> steenrod_seq_degree(r)
  d = 0
  w = 1
  i = 0
  while i < r.size
    w = w * 2
    d += r[i] * (w - 1)
    i += 1
  d

-> steenrod_seq_key(r)
  # trailing zeros stripped
  n = r.size
  while n > 0 && r[n - 1] == 0
    n -= 1
  k = ""
  i = 0
  while i < n
    k = k + r[i].to_s + ","
    i += 1
  k

# all Milnor sequences of degree d (no trailing zeros), recursively choosing r_len, …, r_1 from the top weight down
-> steenrod_basis_degree(d)
  out = []
  # largest i with 2^i − 1 ≤ d
  top = 0
  w = 1
  while w * 2 - 1 <= d
    w = w * 2
    top += 1
  steenrod_fill(d, top, [], out)
  out

-> steenrod_fill(rem, i, acc, out)
  if i == 0
    if rem == 0
      seq = acc.reverse
      n = seq.size
      while n > 0 && seq[n - 1] == 0
        n -= 1
      tr = []
      j = 0
      while j < n
        tr.push(seq[j])
        j += 1
      out.push(tr)
    return 0
  wt = 1
  j = 0
  while j < i
    wt = wt * 2
    j += 1
  wt = wt - 1
  c = rem / wt
  while c >= 0
    steenrod_fill(rem - c * wt, i - 1, acc + [c], out)
    c -= 1
  0

# --- the Milnor product ---------------------------------------------------------------------------------------------------------

# enumerate the matrices row by row (rows i = 1 … m, columns j = 1 … n); collect T(X) for admissible X with odd coefficient
-> steenrod_product(r, s)
  m = r.size
  n = s.size
  out = []
  x = []
  i = 0
  while i <= m
    row = []
    j = 0
    while j <= n
      row.push(0)
      j += 1
    x.push(row)
    i += 1
  steenrod_rows(r, s, m, n, 1, x, out)
  out

-> steenrod_rows(r, s, m, n, i, x, out)
  if i > m
    # column zero entries x_0j = s_j − Σ_i x_ij must be ≥ 0
    j = 1
    while j <= n
      tot = 0
      ii = 1
      while ii <= m
        tot += x[ii][j]
        ii += 1
      if tot > s[j - 1]
        return 0
      x[0][j] = s[j - 1] - tot
      j += 1
    # antidiagonals
    tlen = m + n
    t = []
    k = 1
    while k <= tlen
      sum = 0
      orv = 0
      ok = 1
      ii = 0
      while ii <= m
        jj = k - ii
        if jj >= 0 && jj <= n && !(ii == 0 && jj == 0)
          v = x[ii][jj]
          if (orv & v) != 0
            ok = 0
          orv = orv | v
          sum += v
        ii += 1
      if ok == 0
        return 0
      t.push(sum)
      k += 1
    nn = t.size
    while nn > 0 && t[nn - 1] == 0
      nn -= 1
    tr = []
    k = 0
    while k < nn
      tr.push(t[k])
      k += 1
    out.push(tr)
    return 0
  steenrod_cols(r, s, m, n, i, 1, r[i - 1], x, out)
  0

# choose x_ij for j = j0 … n in row i with the weighted budget; x_i0 takes the rest
-> steenrod_cols(r, s, m, n, i, j, budget, x, out)
  if j > n
    x[i][0] = budget
    steenrod_rows(r, s, m, n, i + 1, x, out)
    return 0
  w = 1
  k = 0
  while k < j
    w = w * 2
    k += 1
  c = 0
  while c * w <= budget && c <= s[j - 1]
    x[i][j] = c
    steenrod_cols(r, s, m, n, i, j + 1, budget - c * w, x, out)
    c += 1
  x[i][j] = 0
  0

# --- setup: bases by degree and a product cache -------------------------------------------------------------------------------

-> steenrod_new(tmax)
  basis = []
  index = {}
  d = 0
  while d <= tmax
    b = steenrod_basis_degree(d)
    basis.push(b)
    i = 0
    while i < b.size
      index[steenrod_seq_key(b[i])] = i
      i += 1
    d += 1
  # cache-key radices: every index < kw and every degree < kd, so the key below is collision-free
  kw = 1
  basis.each -> (bb)
    if bb.size + 1 > kw
      kw = bb.size + 1
  {tmax: tmax, basis: basis, index: index, cache: {}, kw: kw, kd: tmax + 1}

# product of basis elements (degree da, index ia) · (degree db, index ib) as a list of indices in degree da + db
-> steenrod_mul(st, da, ia, db, ib)
  key = ((da * st[:kw] + ia) * st[:kd] + db) * st[:kw] + ib
  c = st[:cache]
  if c.has_key?(key)
    return c[key]
  terms = steenrod_product(st[:basis][da][ia], st[:basis][db][ib])
  # mod 2: terms may repeat — cancel in pairs
  cnt = {}
  terms.each -> (tm)
    k = st[:index][steenrod_seq_key(tm)]
    cnt[k] = cnt.fetch(k, 0) + 1
  out = []
  cnt.keys.sort.each -> (k)
    if cnt[k] % 2 == 1
      out.push(k)
  c[key] = out
  out

# --- F2 bit-vector helpers (32-bit words) ---------------------------------------------------------------------------------------

-> steenrod_xor_row(a, ao, b, bo, words) (i64[] i64 i64[] i64 i64) i64
  i = 0
  while i < words
    a[ao + i] = a[ao + i] ^ b[bo + i]
    i += 1
  0

-> steenrod_bit(a, ao, k) (i64[] i64 i64) i64
  (a[ao + k / 32] >> (k % 32)) & 1

-> steenrod_lowbit(a, ao, words) (i64[] i64 i64) i64
  i = 0
  while i < words
    v = a[ao + i]
    if v != 0
      b = 0
      while ((v >> b) & 1) == 0
        b += 1
      return i * 32 + b
    i += 1
  -1

# --- the minimal resolution -------------------------------------------------------------------------------------------------------

# layout of C_s in internal degree t: generators g with deg(g) ≤ t, block of size dim A_{t − deg g} each; returns [offsets, total]
-> steenrod_layout(st, gens, t)
  offs = []
  tot = 0
  gens.each -> (g)
    offs.push(tot)
    if g[0] <= t
      tot += st[:basis][t - g[0]].size
  [offs, tot]

# image of the basis element (generator gi, A-basis element ia of degree t − deg gi) of C_s under d, as a bit vector in C_{s−1} at t
-> steenrod_d_basis(st, gens_s, gi, ia, t, lay_prev, out, ob, words)
  i = 0
  while i < words
    out[ob + i] = 0
    i += 1
  g = gens_s[gi]
  da = t - g[0]
  # d(g) = list of [prev generator h, A-index b] with deg b = deg g − deg h
  g[1].each -> (term)
    h = term[0]
    b = term[1]
    db = g[0] - term[2]
    prods = steenrod_mul(st, da, ia, db, b)
    base = lay_prev[0][h]
    prods.each -> (c)
      k = base + c
      out[ob + k / 32] = out[ob + k / 32] ^ (1 << (k % 32))
  0

-> steenrod_resolve(st, smax)
  tmax = st[:tmax]
  # gens[s] = list of [degree, d-image terms [[h, b, deg h]…]]
  gens = []
  s = 0
  while s <= smax
    gens.push([])
    s += 1
  # C_0: one generator in degree 0, mapping to F2 (augmentation)
  gens[0].push([0, []])
  t = 1
  while t <= tmax
    s = 1
    while s <= smax
      # kernel of d_{s−1} : C_{s−1,t} → C_{s−2,t} (for s = 1, the augmentation kills everything of positive degree)
      lp = steenrod_layout(st, gens[s - 1], t)
      n1 = lp[1]
      if n1 > 0
        w1 = (n1 + 31) / 32
        kernel = []
        if s == 1
          k = 0
          while k < n1
            kernel.push(k)
            k += 1
          # represent kernel vectors as unit vectors
          kv = i64[n1 * w1]
          k = 0
          while k < n1
            kv[k * w1 + k / 32] = 1 << (k % 32)
            k += 1
          nk = n1
        else
          lpp = steenrod_layout(st, gens[s - 2], t)
          n2 = lpp[1]
          w2 = (n2 + 31) / 32
          if n2 == 0
            w2 = 1
          # rows: [image (n2 bits) | identity (n1 bits)]
          wt = w2 + w1
          m = i64[n1 * wt + 1]
          row = 0
          gi = 0
          while gi < gens[s - 1].size
            g = gens[s - 1][gi]
            if g[0] <= t
              ia = 0
              while ia < st[:basis][t - g[0]].size
                steenrod_d_basis(st, gens[s - 1], gi, ia, t, lpp, m, row * wt, w2)
                m[row * wt + w2 + row / 32] = m[row * wt + w2 + row / 32] | (1 << (row % 32))
                row += 1
                ia += 1
            gi += 1
          # eliminate on the image part; rows whose image part becomes zero give the kernel (their identity part)
          piv = i64[n2 + 1]
          i = 0
          while i <= n2
            piv[i] = -1
            i += 1
          kv = i64[n1 * w1 + 1]
          nk = 0
          r = 0
          while r < n1
            # reduce row r by earlier pivot rows
            more = 1
            while more == 1
              lb = steenrod_lowbit(m, r * wt, w2)
              if lb < 0 || lb >= n2
                more = 0
              else
                if piv[lb] >= 0
                  steenrod_xor_row(m, r * wt, m, piv[lb] * wt, wt)
                else
                  piv[lb] = r
                  more = 0
            lb = steenrod_lowbit(m, r * wt, w2)
            if lb < 0 || lb >= n2
              i = 0
              while i < w1
                kv[nk * w1 + i] = m[r * wt + w2 + i]
                i += 1
              nk += 1
            r += 1
        # image of d_s : C_{s,t} → C_{s−1,t} from the generators of C_s of degree < t
        im = []
        nimg = 0
        gi = 0
        while gi < gens[s].size
          g = gens[s][gi]
          if g[0] < t
            nimg += st[:basis][t - g[0]].size
          gi += 1
        iv = i64[(nimg + 1) * w1]
        row = 0
        gi = 0
        while gi < gens[s].size
          g = gens[s][gi]
          if g[0] < t
            ia = 0
            while ia < st[:basis][t - g[0]].size
              steenrod_d_basis(st, gens[s], gi, ia, t, lp, iv, row * w1, w1)
              row += 1
              ia += 1
          gi += 1
        # echelon form of the image, then reduce kernel vectors against it; survivors become new generators
        ip = i64[n1 + 1]
        i = 0
        while i <= n1
          ip[i] = -1
          i += 1
        r = 0
        while r < nimg
          more = 1
          while more == 1
            lb = steenrod_lowbit(iv, r * w1, w1)
            if lb < 0
              more = 0
            else
              if ip[lb] >= 0
                steenrod_xor_row(iv, r * w1, iv, ip[lb] * w1, w1)
              else
                ip[lb] = r
                more = 0
          r += 1
        # kernel vectors: reduce against image pivots and previously accepted new vectors (kept in iv as extra rows)
        ext_rows = i64[(nk + 1) * w1]
        np2 = 0
        q = 0
        while q < nk
          more = 1
          while more == 1
            lb = steenrod_lowbit(kv, q * w1, w1)
            if lb < 0
              more = 0
            else
              if ip[lb] >= 0
                if ip[lb] < nimg
                  steenrod_xor_row(kv, q * w1, iv, ip[lb] * w1, w1)
                else
                  steenrod_xor_row(kv, q * w1, ext_rows, (ip[lb] - nimg) * w1, w1)
              else
                more = 0
          lb = steenrod_lowbit(kv, q * w1, w1)
          if lb >= 0
            # new generator with d(g) = this vector
            i = 0
            while i < w1
              ext_rows[np2 * w1 + i] = kv[q * w1 + i]
              i += 1
            ip[lb] = nimg + np2
            np2 += 1
            terms = []
            gi = 0
            while gi < gens[s - 1].size
              g = gens[s - 1][gi]
              if g[0] <= t
                base = lp[0][gi]
                ia = 0
                while ia < st[:basis][t - g[0]].size
                  if steenrod_bit(kv, q * w1, base + ia) == 1
                    terms.push([gi, ia, g[0]])
                  ia += 1
              gi += 1
            gens[s].push([t, terms])
          q += 1
      s += 1
    t += 1
  gens

-> steenrod_ext(gens, s, t)
  c = 0
  gens[s].each -> (g)
    if g[0] == t
      c += 1
  c

# ==================================================================================================================================
# Odd primes. Milnor basis Q(E) P(R): E ⊆ {0, 1, 2, …} (Q_i of degree 2p^i − 1, exterior, in increasing order), R = (r1, r2, …) with
# P(R) of degree Σ r_i · 2(p^i − 1). Products (Milnor): P(R) Q_k = Q_k P(R) + Σ_{j ≥ 1} Q_{k+j} P(R − p^k e_j); Q's anticommute and
# square to zero; P(R) P(S) = Σ_X c(X) P(T(X)) with Σ_j p^j x_ij = r_i, Σ_i x_ij = s_j, and c(X) = Π_n multinomial(antidiagonal n) mod p.
# An element is a Hash {key → coefficient mod p} with key "e0e1…|r1,r2,…".
# ==================================================================================================================================

-> stp_key(e, r)
  ks = ""
  i = 0
  while i < e.size
    ks = ks + e[i].to_s
    i += 1
  n = r.size
  while n > 0 && r[n - 1] == 0
    n -= 1
  ks = ks + "|"
  i = 0
  while i < n
    ks = ks + r[i].to_s + ","
    i += 1
  ks

-> stp_parse(key)
  parts = key.split("|")
  e = []
  if parts[0].size > 0
    i = 0
    while i < parts[0].size
      e.push(parts[0][i].to_i)
      i += 1
  r = []
  if parts.size > 1 && parts[1].size > 0
    xs = parts[1].split(",")
    i = 0
    while i < xs.size
      if xs[i].size > 0
        r.push(xs[i].to_i)
      i += 1
  [e, r]

-> stp_degree(p, e, r)
  d = 0
  pw = 1
  i = 0
  while i < e.size
    d += e[i] * (2 * pw - 1)
    pw = pw * p
    i += 1
  pw = 1
  i = 0
  while i < r.size
    pw = pw * p
    d += r[i] * 2 * (pw - 1)
    i += 1
  d

# multinomial coefficient of the list v mod p, by Lucas: product over base-p digits of the digit multinomials (0 if a digit sum ≥ p)
-> stp_multinomial(v, p)
  c = 1
  vals = []
  i = 0
  while i < v.size
    vals.push(v[i])
    i += 1
  more = 1
  while more == 1
    more = 0
    digs = []
    s = 0
    i = 0
    while i < vals.size
      d = vals[i] % p
      digs.push(d)
      s += d
      vals[i] = vals[i] / p
      if vals[i] > 0
        more = 1
      i += 1
    if s >= p
      return 0
    # digit multinomial s! / Π d! mod p (s < p, so all factorials are invertible)
    num = 1
    k = 2
    while k <= s
      num = num * k % p
      k += 1
    den = 1
    di = 0
    while di < digs.size
      d = digs[di]
      k = 2
      while k <= d
        den = den * k % p
        k += 1
      di += 1
    # inverse of den mod p
    inv = 1
    ee = p - 2
    bb = den % p
    while ee > 0
      if ee % 2 == 1
        inv = inv * bb % p
      bb = bb * bb % p
      ee = ee / 2
    c = c * num % p * inv % p
  c

# P(R)·P(S) as a Hash {R-key → coeff}
-> stp_pp(p, r, s)
  m = r.size
  n = s.size
  out = {}
  x = []
  i = 0
  while i <= m
    row = []
    j = 0
    while j <= n
      row.push(0)
      j += 1
    x.push(row)
    i += 1
  stp_pp_rows(p, r, s, m, n, 1, x, out)
  out

-> stp_pp_rows(p, r, s, m, n, i, x, out)
  if i > m
    j = 1
    while j <= n
      tot = 0
      ii = 1
      while ii <= m
        tot += x[ii][j]
        ii += 1
      if tot > s[j - 1]
        return 0
      x[0][j] = s[j - 1] - tot
      j += 1
    c = 1
    t = []
    k = 1
    while k <= m + n
      diag = []
      sum = 0
      ii = 0
      while ii <= m
        jj = k - ii
        if jj >= 0 && jj <= n && !(ii == 0 && jj == 0)
          diag.push(x[ii][jj])
          sum += x[ii][jj]
        ii += 1
      c = c * stp_multinomial(diag, p) % p
      if c == 0
        return 0
      t.push(sum)
      k += 1
    key = stp_key([], t)
    out[key] = (out.fetch(key, 0) + c) % p
    return 0
  stp_pp_cols(p, r, s, m, n, i, 1, r[i - 1], x, out)
  0

-> stp_pp_cols(p, r, s, m, n, i, j, budget, x, out)
  if j > n
    x[i][0] = budget
    stp_pp_rows(p, r, s, m, n, i + 1, x, out)
    return 0
  w = 1
  k = 0
  while k < j
    w = w * p
    k += 1
  c = 0
  while c * w <= budget && c <= s[j - 1]
    x[i][j] = c
    stp_pp_cols(p, r, s, m, n, i, j + 1, budget - c * w, x, out)
    c += 1
  x[i][j] = 0
  0

# multiply the monomial Q(E)P(R) on the right by Q_k: returns a list of [sign·coeff, E', R'] terms (before reducing)
-> stp_times_q(p, e, r, k)
  out = []
  # P(R) Q_k = Q_k P(R) + Σ_{j ≥ 1} Q_{k+j} P(R − p^k e_j)
  pk = 1
  i = 0
  while i < k
    pk = pk * p
    i += 1
  terms = [[k, r]]
  j = 1
  while j <= r.size
    if r[j - 1] >= pk
      r2 = []
      i = 0
      while i < r.size
        r2.push(r[i])
        i += 1
      r2[j - 1] = r2[j - 1] - pk
      terms.push([k + j, r2])
    j += 1
  # then Q(E) · Q_idx: insert idx into E with the sign of moving it past the larger Q's already present
  ti = 0
  while ti < terms.size
    tm = terms[ti]
    ti += 1
    idx = tm[0]
    e2 = []
    i = 0
    while i < e.size
      e2.push(e[i])
      i += 1
    while e2.size <= idx
      e2.push(0)
    if e2[idx] == 0
      sgn = 1
      i = idx + 1
      while i < e2.size
        if e2[i] == 1
          sgn = 0 - sgn
        i += 1
      e2[idx] = 1
      out.push([sgn, e2, tm[1]])
  out

# product of monomials Q(E)P(R) · Q(F)P(S) as a Hash key → coeff mod p
-> stp_mul_mono(p, e, r, f, s)
  # multiply successively by Q_k for each k with f_k = 1 (increasing), then by P(S)
  cur = [[1, e, r]]
  k = 0
  while k < f.size
    if f[k] == 1
      nxt = []
      ci = 0
      while ci < cur.size
        tm = cur[ci]
        ci += 1
        tq = stp_times_q(p, tm[1], tm[2], k)
        qi = 0
        while qi < tq.size
          t2 = tq[qi]
          qi += 1
          nxt.push([tm[0] * t2[0], t2[1], t2[2]])
      cur = nxt
    k += 1
  out = {}
  ci = 0
  while ci < cur.size
    tm = cur[ci]
    ci += 1
    pp = stp_pp(p, tm[2], s)
    pk = pp.keys
    ki = 0
    while ki < pk.size
      rk = pk[ki]
      ki += 1
      rr = stp_parse(rk)[1]
      key = stp_key(tm[1], rr)
      v = (out.fetch(key, 0) + tm[0] * pp[rk]) % p
      if v < 0
        v += p
      out[key] = v
  out

# all Milnor monomials of degree d at the prime p (E by subsets of Q_0 … Q_m, R by recursion on the largest weight)
-> stp_basis_degree(p, d)
  out = []
  # Q-parts: subsets of {Q_0, Q_1, …} with total degree ≤ d
  qd = []
  pw = 1
  while 2 * pw - 1 <= d
    qd.push(2 * pw - 1)
    pw = pw * p
  nq = qd.size
  mask = 0
  while mask < (1 << nq)
    qdeg = 0
    e = []
    i = 0
    while i < nq
      bit = (mask >> i) & 1
      e.push(bit)
      qdeg += bit * qd[i]
      i += 1
    rem = d - qdeg
    if rem >= 0 && rem % (2 * (p - 1)) == 0
      # trailing zeros of E stripped
      ne = e.size
      while ne > 0 && e[ne - 1] == 0
        ne -= 1
      e2 = []
      i = 0
      while i < ne
        e2.push(e[i])
        i += 1
      rs = []
      top = 0
      w = p
      while 2 * (w - 1) <= rem
        w = w * p
        top += 1
      stp_fill_r(p, rem, top, [], rs)
      ri = 0
      while ri < rs.size
        out.push(stp_key(e2, rs[ri]))
        ri += 1
    mask += 1
  out

-> stp_fill_r(p, rem, i, acc, out)
  if i == 0
    if rem == 0
      seq = acc.reverse
      out.push(seq)
    return 0
  wt = 1
  j = 0
  while j < i
    wt = wt * p
    j += 1
  wt = 2 * (wt - 1)
  c = rem / wt
  while c >= 0
    stp_fill_r(p, rem - c * wt, i - 1, acc + [c], out)
    c -= 1
  0

-> steenrod_p_new(p, tmax)
  basis = []
  index = {}
  d = 0
  while d <= tmax
    b = stp_basis_degree(p, d)
    basis.push(b)
    i = 0
    while i < b.size
      index[b[i]] = i
      i += 1
    d += 1
  # cache-key radices: every index < kw and every degree < kd, so the key below is collision-free
  kw = 1
  basis.each -> (bb)
    if bb.size + 1 > kw
      kw = bb.size + 1
  {p: p, tmax: tmax, basis: basis, index: index, cache: {}, kw: kw, kd: tmax + 1}

# product of basis elements (da, ia)·(db, ib) as a list of [index in degree da + db, coefficient]
-> steenrod_p_mul(st, da, ia, db, ib)
  key = ((da * st[:kw] + ia) * st[:kd] + db) * st[:kw] + ib
  c = st[:cache]
  if c.has_key?(key)
    return c[key]
  p = st[:p]
  a = stp_parse(st[:basis][da][ia])
  b = stp_parse(st[:basis][db][ib])
  prod = stp_mul_mono(p, a[0], a[1], b[0], b[1])
  out = []
  pkeys = prod.keys
  ki = 0
  while ki < pkeys.size
    k = pkeys[ki]
    ki += 1
    v = prod[k] % p
    if v != 0
      # normalize E (strip trailing zeros) before the index lookup
      pr = stp_parse(k)
      e = pr[0]
      ne = e.size
      while ne > 0 && e[ne - 1] == 0
        ne -= 1
      e2 = []
      i = 0
      while i < ne
        e2.push(e[i])
        i += 1
      out.push([st[:index][stp_key(e2, pr[1])], v])
  c[key] = out
  out

# minimal resolution of F_p over the mod-p Steenrod algebra (dense vectors mod p, Gaussian elimination)
-> steenrod_p_resolve(st, smax)
  p = st[:p]
  tmax = st[:tmax]
  gens = []
  s = 0
  while s <= smax
    gens.push([])
    s += 1
  gens[0].push([0, []])
  t = 1
  while t <= tmax
    s = 1
    while s <= smax
      lp = steenrod_layout(st, gens[s - 1], t)
      n1 = lp[1]
      if n1 > 0
        # kernel of d_{s−1} at degree t
        kv = []
        if s == 1
          k = 0
          while k < n1
            v = i64[n1]
            v[k] = 1
            kv.push(v)
            k += 1
        else
          lpp = steenrod_layout(st, gens[s - 2], t)
          n2 = lpp[1]
          rows = []
          gi = 0
          while gi < gens[s - 1].size
            g = gens[s - 1][gi]
            if g[0] <= t
              ia = 0
              while ia < st[:basis][t - g[0]].size
                img = steenrod_p_image(st, gens[s - 1], gi, ia, t, lpp, n2)
                ident = i64[n1]
                ident[rows.size] = 1
                rows.push([img, ident])
                ia += 1
            gi += 1
          kv = steenrod_p_kernel(rows, n2, n1, p)
        # image of d_s at degree t from generators of degree < t
        imgs = []
        gi = 0
        while gi < gens[s].size
          g = gens[s][gi]
          if g[0] < t
            ia = 0
            while ia < st[:basis][t - g[0]].size
              imgs.push(steenrod_p_image(st, gens[s], gi, ia, t, lp, n1))
              ia += 1
          gi += 1
        newv = steenrod_p_complement(imgs, kv, n1, p)
        vi = 0
        while vi < newv.size
          v = newv[vi]
          vi += 1
          terms = []
          gi = 0
          while gi < gens[s - 1].size
            g = gens[s - 1][gi]
            if g[0] <= t
              base = lp[0][gi]
              ia = 0
              while ia < st[:basis][t - g[0]].size
                if v[base + ia] != 0
                  terms.push([gi, ia, g[0], v[base + ia]])
                ia += 1
            gi += 1
          gens[s].push([t, terms])
      s += 1
    t += 1
  gens

# d(a·g) for basis element (generator gi, A-index ia) of C_s at degree t, as a dense vector mod p of length n in C_{s−1}
-> steenrod_p_image(st, gens_s, gi, ia, t, lay_prev, n)
  p = st[:p]
  out = i64[n + 1]
  g = gens_s[gi]
  da = t - g[0]
  ti = 0
  while ti < g[1].size
    term = g[1][ti]
    ti += 1
    h = term[0]
    b = term[1]
    db = g[0] - term[2]
    cf = term[3]
    prs = steenrod_p_mul(st, da, ia, db, b)
    pi2 = 0
    while pi2 < prs.size
      pr = prs[pi2]
      pi2 += 1
      k = lay_prev[0][h] + pr[0]
      out[k] = (out[k] + cf * pr[1]) % p
  out

-> stp_inv(a, p)
  r = 1
  b = a % p
  e = p - 2
  while e > 0
    if e % 2 == 1
      r = r * b % p
    b = b * b % p
    e = e / 2
  r

# rows: [image (length n2), identity (length n1)]; returns the identity parts of rows whose image reduces to zero
-> steenrod_p_kernel(rows, n2, n1, p)
  piv = {}
  out = []
  ri = 0
  while ri < rows.size
    rowp = rows[ri]
    ri += 1
    img = rowp[0]
    idv = rowp[1]
    done = 0
    while done == 0
      lead = -1
      i = 0
      while i < n2 && lead < 0
        if img[i] % p != 0
          lead = i
        i += 1
      if lead < 0
        done = 1
      else
        if piv.has_key?(lead)
          pr = piv[lead]
          f = img[lead] * stp_inv(pr[0][lead], p) % p
          i = 0
          while i < n2
            img[i] = ((img[i] - f * pr[0][i]) % p + p) % p
            i += 1
          i = 0
          while i < n1
            idv[i] = ((idv[i] - f * pr[1][i]) % p + p) % p
            i += 1
        else
          piv[lead] = [img, idv]
          done = 2
    if done == 1
      out.push(idv)
  out

# reduce v against the pivot rows (Hash lead → row); returns the remaining leading index or −1
-> stp_reduce(v, n, p, piv)
  done = 0
  lead = -1
  while done == 0
    lead = -1
    i = 0
    while i < n && lead < 0
      if v[i] % p != 0
        lead = i
      i += 1
    if lead < 0 || !piv.has_key?(lead)
      done = 1
    else
      pv = piv[lead]
      f = v[lead] * stp_inv(pv[lead], p) % p
      i = 0
      while i < n
        v[i] = ((v[i] - f * pv[i]) % p + p) % p
        i += 1
  lead

# vectors of kv independent modulo span(imgs) and of each other
-> steenrod_p_complement(imgs, kv, n, p)
  piv = {}
  i = 0
  while i < imgs.size
    l = stp_reduce(imgs[i], n, p, piv)
    if l >= 0
      piv[l] = imgs[i]
    i += 1
  out = []
  i = 0
  while i < kv.size
    l = stp_reduce(kv[i], n, p, piv)
    if l >= 0
      piv[l] = kv[i]
      out.push(kv[i])
    i += 1
  out
