-> parity(mask, vec, width) (i64 i64 i64) i64
  pr = 0
  b = 0
  while b < width
    if ((mask >> b) & 1) == 1
      if ((vec >> b) & 1) == 1
        pr = (pr + 1) % 2
    b += 1
  pr
-> xor_insert(us, vs, ws, rank, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  res = rank ## i64
  zero = 0 ## i64
  if u == 0
    zero = 1
  if v == 0
    zero = 1
  if w == 0
    zero = 1
  if zero == 0
    found = 0 - 1 ## i64
    k = 0 ## i64
    while k < rank
      if us[k] == u
        if vs[k] == v
          if ws[k] == w
            found = k
            k = rank
      k += 1
    if found < 0
      us[rank] = u
      vs[rank] = v
      ws[rank] = w
      res = rank + 1
    if found >= 0
      us[found] = us[rank - 1]
      vs[found] = vs[rank - 1]
      ws[found] = ws[rank - 1]
      res = rank - 1
  res
-> widen_cols(mask, rows, oldc, newc, p2) (i64 i64 i64 i64 i64[]) i64
  r = 0 ## i64
  b = 0 ## i64
  while b < rows * oldc
    if ((mask >> b) & 1) == 1
      ii = b / oldc ## i64
      cc = b % oldc ## i64
      r = r | p2[ii * newc + cc]
    b += 1
  r
-> drop_last_col(mask, rows, oldc, p2) (i64 i64 i64 i64[]) i64
  r = 0 ## i64
  b = 0 ## i64
  while b < rows * oldc
    if ((mask >> b) & 1) == 1
      ii = b / oldc ## i64
      cc = b % oldc ## i64
      if cc != oldc - 1
        r = r | p2[ii * (oldc - 1) + cc]
    b += 1
  r
-> extend(us, vs, ws, rank, n, mm, pp, p2) (i64[] i64[] i64[] i64 i64 i64 i64 i64[]) i64
  t = 0 ## i64
  while t < rank
    vs[t] = widen_cols(vs[t], mm, pp, pp + 1, p2)
    ws[t] = widen_cols(ws[t], n, pp, pp + 1, p2)
    t += 1
  i = 0 ## i64
  while i < n
    j = 0 ## i64
    while j < mm
      us[rank] = p2[i * mm + j]
      vs[rank] = p2[j * (pp + 1) + pp]
      ws[rank] = p2[i * (pp + 1) + pp]
      rank = rank + 1
      j += 1
    i += 1
  rank
-> project(us, vs, ws, rank, nus, nvs, nws, n, mm, pp, p2) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64 i64 i64[]) i64
  nq = 0 ## i64
  t = 0 ## i64
  while t < rank
    nv = drop_last_col(vs[t], mm, pp, p2) ## i64
    nw = drop_last_col(ws[t], n, pp, p2) ## i64
    nq = xor_insert(nus, nvs, nws, nq, us[t], nv, nw)
    t += 1
  k = 0 ## i64
  while k < nq
    us[k] = nus[k]
    vs[k] = nvs[k]
    ws[k] = nws[k]
    k += 1
  nq
-> verify(us, vs, ws, rank, seed0, n, mm, pp) (i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
  ok = 1
  s = seed0
  ab = n * mm ## i64
  bb = mm * pp ## i64
  cb = n * pp ## i64
  ma = 1 << ab ## i64
  mb = 1 << bb ## i64
  trial = 0
  while trial < 20
    s = (s * 16807) % 2147483647
    av = s % ma
    s = (s * 16807) % 2147483647
    bv = s % mb
    o = 0
    while o < cb
      cs = 0
      t = 0
      while t < rank
        if ((ws[t] >> o) & 1) == 1
          if parity(us[t], av, ab) == 1
            if parity(vs[t], bv, bb) == 1
              cs = (cs + 1) % 2
        t += 1
      oi = o / pp
      oj = o % pp
      ct = 0
      kx = 0
      while kx < mm
        if ((av >> (oi * mm + kx)) & 1) == 1
          if ((bv >> (kx * pp + oj)) & 1) == 1
            ct = (ct + 1) % 2
        kx += 1
      if cs != ct
        ok = 0
      o += 1
    trial += 1
  ok
p2 = i64[64]
p2[0] = 1
kk = 1
while kk < 64
  p2[kk] = p2[kk - 1] + p2[kk - 1]
  kk += 1
us = i64[300]
vs = i64[300]
ws = i64[300]
nus = i64[300]
nvs = i64[300]
nws = i64[300]
rank = 0 ## i64
ni = 0
while ni < 5
  nj = 0
  while nj < 5
    nk = 0
    while nk < 5
      us[rank] = p2[ni * 5 + nj]
      vs[rank] = p2[nj * 5 + nk]
      ws[rank] = p2[ni * 5 + nk]
      rank += 1
      nk += 1
    nj += 1
  ni += 1
<< "naive(5,5,5)   rank=" + rank.to_s() + " verify=" + verify(us, vs, ws, rank, 7, 5, 5, 5).to_s()
rank = extend(us, vs, ws, rank, 5, 5, 5, p2)
<< "extend (5,5,6) rank=" + rank.to_s() + " verify=" + verify(us, vs, ws, rank, 7, 5, 5, 6).to_s()
rank = extend(us, vs, ws, rank, 5, 5, 6, p2)
<< "extend (5,5,7) rank=" + rank.to_s() + " verify=" + verify(us, vs, ws, rank, 7, 5, 5, 7).to_s()
rank = project(us, vs, ws, rank, nus, nvs, nws, 5, 5, 7, p2)
<< "project(5,5,6) rank=" + rank.to_s() + " verify=" + verify(us, vs, ws, rank, 7, 5, 5, 6).to_s()
rank = project(us, vs, ws, rank, nus, nvs, nws, 5, 5, 6, p2)
<< "project(5,5,5) rank=" + rank.to_s() + " verify=" + verify(us, vs, ws, rank, 7, 5, 5, 5).to_s()
