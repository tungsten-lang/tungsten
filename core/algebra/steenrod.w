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
  {tmax: tmax, basis: basis, index: index, cache: {}}

# product of basis elements (degree da, index ia) · (degree db, index ib) as a list of indices in degree da + db
-> steenrod_mul(st, da, ia, db, ib)
  key = ((da * 4096 + ia) * 64 + db) * 4096 + ib
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
