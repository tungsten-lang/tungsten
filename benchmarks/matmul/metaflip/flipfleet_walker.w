-> hsh(x) (i64) i64
  y = x ^ (x >> 21) ^ (x >> 42) ## i64
  ((y * 2654435761) >> 13) & 2047

-> chain_link(st, ho, nxo, pvo, slot, key) (i64[] i64 i64 i64 i64 i64) i64
  hb = hsh(key) ## i64
  old = st[ho + hb] ## i64
  st[nxo + slot] = old
  st[pvo + slot] = 0
  if old != 0
    st[pvo + old - 1] = slot + 1
  st[ho + hb] = slot + 1
  0

-> chain_unlink(st, ho, nxo, pvo, slot, key) (i64[] i64 i64 i64 i64 i64) i64
  nn = st[nxo + slot] ## i64
  pp = st[pvo + slot] ## i64
  if pp == 0
    st[ho + hsh(key)] = nn
  if pp != 0
    st[nxo + pp - 1] = nn
  if nn != 0
    st[pvo + nn - 1] = pp
  0

-> ins_term(st, u, v, w, rank) (i64[] i64 i64 i64 i64) i64
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
    c = st[1873 + hsh(u)] ## i64
    while c != 0
      s = c - 1 ## i64
      if st[26 + s] == u
        if st[231 + s] == v
          if st[436 + s] == w
            found = s
      c = st[8017 + s]
      if found >= 0
        c = 0
    if found < 0
      fltop = st[1871] ## i64
      slot = st[1666 + fltop - 1] ## i64
      st[1871] = fltop - 1
      st[26 + slot] = u
      st[231 + slot] = v
      st[436 + slot] = w
      z0 = chain_link(st, 1873, 8017, 8222, slot, u) ## i64
      z0 = chain_link(st, 3921, 8427, 8632, slot, v) ## i64
      z0 = chain_link(st, 5969, 8837, 9042, slot, w) ## i64
      st[1256 + rank] = slot
      st[1461 + slot] = rank
      res = rank + 1
    if found >= 0
      z0 = chain_unlink(st, 1873, 8017, 8222, found, u) ## i64
      z0 = chain_unlink(st, 3921, 8427, 8632, found, v) ## i64
      z0 = chain_unlink(st, 5969, 8837, 9042, found, w) ## i64
      dp = st[1461 + found] ## i64
      lastslot = st[1256 + rank - 1] ## i64
      st[1256 + dp] = lastslot
      st[1461 + lastslot] = dp
      fltop = st[1871] ## i64
      st[1666 + fltop] = found
      st[1871] = fltop + 1
      res = rank - 1
  res

-> chain_count(st, ho, nxo, mo, key, ti) (i64[] i64 i64 i64 i64 i64) i64
  cnt = 0 ## i64
  c = st[ho + hsh(key)] ## i64
  while c != 0
    s = c - 1 ## i64
    if st[mo + s] == key
      if s != ti
        cnt = cnt + 1
    c = st[nxo + s]
  cnt

-> chain_pick(st, ho, nxo, mo, key, ti, want) (i64[] i64 i64 i64 i64 i64 i64) i64
  seen = 0 ## i64
  res = 0 - 1 ## i64
  c = st[ho + hsh(key)] ## i64
  while c != 0
    s = c - 1 ## i64
    if st[mo + s] == key
      if s != ti
        if seen == want
          res = s
        if res < 0
          seen = seen + 1
    c = st[nxo + s]
    if res >= 0
      c = 0
  res

-> chain_rpick(st, ho, nxo, mo, key, ti, rseed) (i64[] i64 i64 i64 i64 i64 i64) i64
  seen = 0 ## i64
  res = 0 - 1 ## i64
  r = rseed ## i64
  c = st[ho + hsh(key)] ## i64
  while c != 0
    s = c - 1 ## i64
    if st[mo + s] == key
      if s != ti
        seen = seen + 1
        r = (r * 1103515245 + 12345) & 2147483647
        if ((r * seen) >> 31) == 0
          res = s
    c = st[nxo + s]
  res

-> pressure(st, u, v, w) (i64[] i64 i64 i64) i64
  cnt = 0 ## i64
  c = st[1873 + hsh(u)] ## i64
  while c != 0
    s = c - 1 ## i64
    if st[26 + s] == u
      mv2 = 0 ## i64
      if st[231 + s] == v
        mv2 = 1
      mw2 = 0 ## i64
      if st[436 + s] == w
        mw2 = 1
      if mv2 + mw2 == 1
        cnt = cnt + 1
    c = st[8017 + s]
  c = st[3921 + hsh(v)] ## i64
  while c != 0
    s = c - 1 ## i64
    if st[231 + s] == v
      if st[26 + s] != u
        if st[436 + s] == w
          cnt = cnt + 1
    c = st[8427 + s]
  cnt

-> parity(mask, vec, width) (i64 i64 i64) i64
  pr = 0
  b = 0
  while b < width
    if ((mask >> b) & 1) == 1
      if ((vec >> b) & 1) == 1
        pr = (pr + 1) % 2
    b += 1
  pr

-> verify(st, uo, vo, wo, mo, rank, seed0) (i64[] i64 i64 i64 i64 i64 i64) i64
  ok = 1
  s = seed0
  trial = 0
  while trial < 20
    s = (s * 16807) % 2147483647
    s2 = (s * 16807) % 2147483647
    av = ((s * 8388608) ^ s2) % 33554432
    s = (s2 * 16807) % 2147483647
    s2 = (s * 16807) % 2147483647
    bv = ((s * 8388608) ^ s2) % 33554432
    s = s2
    o = 0
    while o < 25
      cs = 0
      t = 0
      while t < rank
        sl = st[mo + t] ## i64
        if ((st[wo + sl] >> o) & 1) == 1
          if parity(st[uo + sl], av, 25) == 1
            if parity(st[vo + sl], bv, 25) == 1
              cs = (cs + 1) % 2
        t += 1
      oi = o / 5
      oj = o % 5
      ct = 0
      kx = 0
      while kx < 5
        if ((av >> (oi * 5 + kx)) & 1) == 1
          if ((bv >> (kx * 5 + oj)) & 1) == 1
            ct = (ct + 1) % 2
        kx += 1
      if cs != ct
        ok = 0
      o += 1
    trial += 1
  ok



-> wpc(x) (i64) i64
  c = 0 ## i64
  y = x ## i64
  while y != 0
    y = y & (y - 1)
    c = c + 1
  c

-> worker_st_size (i64)
  10103

-> init_naive(st, seed, dslack, cycles) (i64[] i64 i64 i64) i64
  st[0] = 1
  kk = 1 ## i64
  while kk < 26
    st[0 + kk] = st[0 + kk - 1] + st[0 + kk - 1]
    kk += 1
  ii = 0 ## i64
  while ii < 205
    st[9247 + ii] = ii
    st[1666 + ii] = 205 - 1 - ii
    ii += 1
  st[1871] = 205
  hz = 0 ## i64
  while hz < 2048
    st[1873 + hz] = 0
    st[3921 + hz] = 0
    st[5969 + hz] = 0
    hz += 1
  rank = 0 ## i64
  ni = 0 ## i64
  while ni < 5
    nj = 0 ## i64
    while nj < 5
      nk = 0 ## i64
      while nk < 5
        tu = st[0 + ni * 5 + nj] ## i64
        tv = st[0 + nj * 5 + nk] ## i64
        tw = st[0 + ni * 5 + nk] ## i64
        rank = ins_term(st, tu, tv, tw, rank)
        nk += 1
      nj += 1
    ni += 1
  bi = 0 ## i64
  while bi < rank
    sl = st[1256 + bi] ## i64
    st[641 + bi] = st[26 + sl]
    st[846 + bi] = st[231 + sl]
    st[1051 + bi] = st[436 + sl]
    bi += 1
  st[10091] = rank
  st[10091 + 1] = rank
  st[10091 + 2] = seed * 1009 + 12345
  st[10091 + 3] = 1
  st[10091 + 4] = 7
  st[10091 + 5] = 0
  st[10091 + 6] = 0
  st[10091 + 7] = 100000000
  st[10091 + 8] = cycles
  st[10091 + 9] = 0
  st[10091 + 10] = dslack
  0

-> walk_worker(st, steps) (i64[] i64) i64
  rank = st[10091] ## i64
  best_rank = st[10091 + 1] ## i64
  rng = st[10091 + 2] ## i64
  aband = st[10091 + 3] ## i64
  wthr = st[10091 + 4] ## i64
  wraps = st[10091 + 5] ## i64
  mv = st[10091 + 6] ## i64
  nextesc = st[10091 + 7] ## i64
  cyclesv = st[10091 + 8] ## i64
  dslack = st[10091 + 10] ## i64
  bstart = 1 ## i64
  threshold = 6 ## i64
  sc = 0 ## i64
  while sc < steps
    rng = (rng * 1103515245 + 12345) & 2147483647
    td = (rng * rank) >> 31 ## i64
    ti = st[1256 + td] ## i64
    ui = st[26 + ti] ## i64
    vi = st[231 + ti] ## i64
    wi = st[436 + ti] ## i64
    rng = (rng * 1103515245 + 12345) & 2147483647
    axis = (((rng >> 22) & 511) * 3) >> 9 ## i64
    partner = 0 - 1 ## i64
    rng = (rng * 1103515245 + 12345) & 2147483647
    if axis == 0
      partner = chain_rpick(st, 1873, 8017, 26, ui, ti, rng)
    if axis == 1
      partner = chain_rpick(st, 3921, 8427, 231, vi, ti, rng)
    if axis == 2
      partner = chain_rpick(st, 5969, 8837, 436, wi, ti, rng)
    if partner >= 0
      uj = st[26 + partner] ## i64
      vj = st[231 + partner] ## i64
      wj = st[436 + partner] ## i64
      au = ui ## i64
      av2 = vi ## i64
      aw = wi ## i64
      bu = ui ## i64
      bv = vi ## i64
      bw = wj ## i64
      if axis == 0
        aw = wi ^ wj
        bv = vi ^ vj
      if axis == 1
        aw = wi ^ wj
        bu = ui ^ uj
      if axis == 2
        av2 = vi ^ vj
        aw = wi
        bu = ui ^ uj
        bv = vj
        bw = wi
      pold = pressure(st, ui, vi, wi) + pressure(st, uj, vj, wj) ## i64
      rankb = rank ## i64
      rank = ins_term(st, ui, vi, wi, rank) ## i64
      rank = ins_term(st, uj, vj, wj, rank) ## i64
      rank = ins_term(st, au, av2, aw, rank) ## i64
      rank = ins_term(st, bu, bv, bw, rank) ## i64
      pnew = pressure(st, au, av2, aw) + pressure(st, bu, bv, bw) ## i64
      acc = 0 ## i64
      if rank < rankb
        acc = 1
      if acc == 0
        if pnew + threshold >= pold
          dn = wpc(au) + wpc(av2) + wpc(aw) + wpc(bu) + wpc(bv) + wpc(bw) ## i64
          do0 = wpc(ui) + wpc(vi) + wpc(wi) + wpc(uj) + wpc(vj) + wpc(wj) ## i64
          if dn <= do0 + dslack
            acc = 1
      if acc == 0
        rank = ins_term(st, ui, vi, wi, rank) ## i64
        rank = ins_term(st, uj, vj, wj, rank) ## i64
        rank = ins_term(st, au, av2, aw, rank) ## i64
        rank = ins_term(st, bu, bv, bw, rank) ## i64
    if (mv % 2000) == 0
      rng = (rng * 1103515245 + 12345) & 2147483647
      pd1 = (rng * rank) >> 31 ## i64
      pt1 = st[1256 + pd1] ## i64
      rng = (rng * 1103515245 + 12345) & 2147483647
      pd2 = (rng * rank) >> 31 ## i64
      pt2 = st[1256 + pd2] ## i64
      spu = st[26 + pt1] ## i64
      spv = st[231 + pt1] ## i64
      spw = st[436 + pt1] ## i64
      wpr = st[436 + pt2] ## i64
      if wpr != spw
        if wpr != 0
          spw2 = spw ^ wpr ## i64
          rank = ins_term(st, spu, spv, spw, rank) ## i64
          rank = ins_term(st, spu, spv, wpr, rank) ## i64
          rank = ins_term(st, spu, spv, spw2, rank) ## i64
    threshold = 6 - ((mv / 300000) % 7) ## i64
    if mv >= nextesc
      nb = aband + 1 ## i64
      if aband > wthr
        nb = aband + 12
      if nb > 60
        nb = bstart
        wraps = wraps + 1
        if wraps >= cyclesv
          st[10091 + 9] = 1
      aband = nb
      q = 2500000000 ## i64
      if aband > wthr
        q = 500000000
    if rank <= 93
      q = 10000000000
      nextesc = mv + q
    if rank > best_rank + aband
      hz = 0 ## i64
      while hz < 2048
        st[1873 + hz] = 0
        st[3921 + hz] = 0
        st[5969 + hz] = 0
        hz += 1
      fz = 0 ## i64
      while fz < 205
        st[1666 + fz] = 205 - 1 - fz
        fz += 1
      st[1871] = 205
      rank = 0 ## i64
      ri = 0 ## i64
      while ri < best_rank
        cu = st[641 + ri] ## i64
        cv = st[846 + ri] ## i64
        cw = st[1051 + ri] ## i64
        rank = ins_term(st, cu, cv, cw, rank)
        ri += 1
    if rank < best_rank
      best_rank = rank
      if aband >= wthr - 1
        if aband <= wthr + 1
          wthr = wthr + 1
          if wthr > 58
            wthr = 58
      if aband != bstart
        aband = bstart
      nextesc = mv + 2500000000
      ci = 0 ## i64
      while ci < rank
        sl = st[1256 + ci] ## i64
        st[641 + ci] = st[26 + sl]
        st[846 + ci] = st[231 + sl]
        st[1051 + ci] = st[436 + sl]
        ci += 1
    mv += 1
    sc += 1
  st[10091] = rank
  st[10091 + 1] = best_rank
  st[10091 + 2] = rng
  st[10091 + 3] = aband
  st[10091 + 4] = wthr
  st[10091 + 5] = wraps
  st[10091 + 6] = mv
  st[10091 + 7] = nextesc
  best_rank

-> read_best_rank(st) (i64[]) i64
  st[10091 + 1]

-> read_best_u(st, i) (i64[] i64) i64
  st[641 + i]

-> read_best_v(st, i) (i64[] i64) i64
  st[846 + i]

-> read_best_w(st, i) (i64[] i64) i64
  st[1051 + i]

-> read_cycled(st) (i64[]) i64
  st[10091 + 9]

-> verify_best(st) (i64[]) i64
  verify(st, 641, 846, 1051, 9247, st[10091 + 1], 31)

-> best_bits(st) (i64[]) i64
  tb = 0 ## i64
  br = st[10091 + 1] ## i64
  t = 0 ## i64
  while t < br
    tb = tb + wpc(st[641 + t]) + wpc(st[846 + t]) + wpc(st[1051 + t])
    t += 1
  tb

-> reseed_from(st, src, seed) (i64[] i64[] i64) i64
  hz = 0 ## i64
  while hz < 2048
    st[1873 + hz] = 0
    st[3921 + hz] = 0
    st[5969 + hz] = 0
    hz += 1
  fz = 0 ## i64
  while fz < 205
    st[1666 + fz] = 205 - 1 - fz
    fz += 1
  st[1871] = 205
  rank = 0 ## i64
  srank = src[10091 + 1] ## i64
  si = 0 ## i64
  while si < srank
    rank = ins_term(st, src[641 + si], src[846 + si], src[1051 + si], rank)
    si += 1
  ci = 0 ## i64
  while ci < rank
    sl = st[1256 + ci] ## i64
    st[641 + ci] = st[26 + sl]
    st[846 + ci] = st[231 + sl]
    st[1051 + ci] = st[436 + sl]
    ci += 1
  st[10091] = rank
  st[10091 + 1] = rank
  st[10091 + 2] = seed * 1009 + 12345
  st[10091 + 3] = 1
  st[10091 + 4] = 7
  st[10091 + 5] = 0
  st[10091 + 6] = 0
  st[10091 + 7] = 100000000
  st[10091 + 9] = 0
  0

-> load_scheme(st, path, seed) (i64[] String i64) i64
  hz = 0 ## i64
  while hz < 2048
    st[1873 + hz] = 0
    st[3921 + hz] = 0
    st[5969 + hz] = 0
    hz += 1
  fz = 0 ## i64
  while fz < 205
    st[1666 + fz] = 205 - 1 - fz
    fz += 1
  st[1871] = 205
  rank = 0 ## i64
  content = read_file(path)
  lines = content.split("\n")
  srank = lines[0].to_i() ## i64
  si = 0 ## i64
  while si < srank
    parts = lines[si + 1].split(" ")
    rank = ins_term(st, parts[0].to_i(), parts[1].to_i(), parts[2].to_i(), rank)
    si += 1
  ci = 0 ## i64
  while ci < rank
    sl = st[1256 + ci] ## i64
    st[641 + ci] = st[26 + sl]
    st[846 + ci] = st[231 + sl]
    st[1051 + ci] = st[436 + sl]
    ci += 1
  st[10091] = rank
  st[10091 + 1] = rank
  st[10091 + 2] = seed * 1009 + 12345
  st[10091 + 3] = 1
  st[10091 + 4] = 7
  st[10091 + 5] = 0
  st[10091 + 6] = 0
  st[10091 + 7] = 100000000
  st[10091 + 9] = 0
  rank

-> dump_scheme(st, path) (i64[] String) i64
  br = st[10091 + 1] ## i64
  body = br.to_s() + "\n"
  di = 0 ## i64
  while di < br
    body = body + st[641 + di].to_s() + " " + st[846 + di].to_s() + " " + st[1051 + di].to_s() + "\n"
    di += 1
  z = write_file(path, body)
  br
