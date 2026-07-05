"""Generate a rectangular (n,m,p) energy-walk search in Tungsten.
A is n*m, B is m*p, C is n*p.  u over A bits (i,j)->i*m+j ; v over B (j,k)->j*p+k ; w over C (i,k)->i*p+k.
The flip/xor_insert/pressure/energy machinery is format-agnostic; only verify + seed + dims change."""

def gen(n, m, p, recv, arr=200, cap=14000000000, seed=None, thr=6, thrper=300000, plusper=2000):
    thrspan = thr + 1
    AB, BB, CB = n*m, m*p, n*p
    MODA, MODB = 1 << AB, 1 << BB
    maxbits = max(AB, BB, CB) + 1
    seed_block = ""
    if seed is not None:
        lines = [ln for ln in open(seed).read().splitlines()
                 if ln.startswith(("us[", "vs[", "ws["))]
        seed_rank = len(lines) // 3
        arr = max(arr, seed_rank + 80)
        body = "\n".join(lines)
        seed_block = f"""rank = 0 ## i64
{body}
rank = {seed_rank}
"""
    return f'''-> parity(mask, vec, width) (i64 i64 i64)
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
-> pressure2(us, vs, ws, rank, ua, va, wa, ub, vb, wb) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64) i64
  cnt = 0 ## i64
  k = 0 ## i64
  while k < rank
    ma = 0 ## i64
    if us[k] == ua
      ma = ma + 1
    if vs[k] == va
      ma = ma + 1
    if ws[k] == wa
      ma = ma + 1
    if ma == 2
      cnt = cnt + 1
    mb = 0 ## i64
    if us[k] == ub
      mb = mb + 1
    if vs[k] == vb
      mb = mb + 1
    if ws[k] == wb
      mb = mb + 1
    if mb == 2
      cnt = cnt + 1
    k += 1
  cnt
-> pressure(us, vs, ws, rank, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  cnt = 0 ## i64
  k = 0 ## i64
  while k < rank
    m2 = 0 ## i64
    if us[k] == u
      m2 = m2 + 1
    if vs[k] == v
      m2 = m2 + 1
    if ws[k] == w
      m2 = m2 + 1
    if m2 == 2
      cnt = cnt + 1
    k += 1
  cnt
-> verify(us, vs, ws, rank, seed0) (i64[] i64[] i64[] i64 i64) i64
  ok = 1
  s = seed0
  trial = 0
  while trial < 20
    s = (s * 16807) % 2147483647
    s2 = (s * 16807) % 2147483647
    av = ((s * 8388608) ^ s2) % {MODA}
    s = (s2 * 16807) % 2147483647
    s2 = (s * 16807) % 2147483647
    bv = ((s * 8388608) ^ s2) % {MODB}
    s = s2
    o = 0
    while o < {CB}
      cs = 0
      t = 0
      while t < rank
        if ((ws[t] >> o) & 1) == 1
          if parity(us[t], av, {AB}) == 1
            if parity(vs[t], bv, {BB}) == 1
              cs = (cs + 1) % 2
        t += 1
      oi = o / {p}
      oj = o % {p}
      ct = 0
      kx = 0
      while kx < {m}
        if ((av >> (oi * {m} + kx)) & 1) == 1
          if ((bv >> (kx * {p} + oj)) & 1) == 1
            ct = (ct + 1) % 2
        kx += 1
      if cs != ct
        ok = 0
      o += 1
    trial += 1
  ok
p2 = i64[{maxbits}]
p2[0] = 1
kk = 1
while kk < {maxbits}
  p2[kk] = p2[kk - 1] + p2[kk - 1]
  kk += 1
us = i64[{arr}]
vs = i64[{arr}]
ws = i64[{arr}]
bus = i64[{arr}]
bvs = i64[{arr}]
bws = i64[{arr}]
{seed_block or f"""rank = 0 ## i64
ni = 0
while ni < {n}
  nj = 0
  while nj < {m}
    nk = 0
    while nk < {p}
      us[rank] = p2[ni * {m} + nj]
      vs[rank] = p2[nj * {p} + nk]
      ws[rank] = p2[ni * {p} + nk]
      rank += 1
      nk += 1
    nj += 1
  ni += 1"""}
<< "seed rank=" + rank.to_s() + " verify=" + verify(us, vs, ws, rank, 7).to_s()
flush()
best_rank = rank
bi = 0
while bi < rank
  bus[bi] = us[bi]
  bvs[bi] = vs[bi]
  bws[bi] = ws[bi]
  bi += 1
base = 1
av0 = argv()
if av0.size() > 0
  base = av0[0].to_i()
rng = base * 1009 + 12345 ## i64
since = 0 ## i64
threshold = {thr} ## i64
mv = 0 ## i64
while mv < {cap}
  rng = (rng * 1103515245 + 12345) & 2147483647
  ti = (rng * rank) >> 31 ## i64
  ui = us[ti] ## i64
  vi = vs[ti] ## i64
  wi = ws[ti] ## i64
  rng = (rng * 1103515245 + 12345) & 2147483647
  axis = (((rng >> 22) & 511) * 3) >> 9 ## i64
  st = (((rng >> 11) & 1048575) * rank) >> 20 ## i64
  partner = 0 - 1 ## i64
  jj = st ## i64
  scan = 0 ## i64
  while scan < rank
    if jj != ti
      shr = 0 ## i64
      if axis == 0
        if us[jj] == ui
          shr = 1
      if axis == 1
        if vs[jj] == vi
          shr = 1
      if axis == 2
        if ws[jj] == wi
          shr = 1
      if shr == 1
        partner = jj
        break
    jj = jj + 1
    if jj >= rank
      jj = jj - rank
    scan += 1
  if partner < 0
    since += 1
  else
    uj = us[partner] ## i64
    vj = vs[partner] ## i64
    wj = ws[partner] ## i64
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
    pold = pressure2(us, vs, ws, rank, ui, vi, wi, uj, vj, wj) ## i64
    rankb = rank ## i64
    rank = xor_insert(us, vs, ws, rank, ui, vi, wi) ## i64
    rank = xor_insert(us, vs, ws, rank, uj, vj, wj) ## i64
    rank = xor_insert(us, vs, ws, rank, au, av2, aw) ## i64
    rank = xor_insert(us, vs, ws, rank, bu, bv, bw) ## i64
    pnew = pressure2(us, vs, ws, rank, au, av2, aw, bu, bv, bw) ## i64
    acc = 0 ## i64
    if rank < rankb
      acc = 1
    if pnew + threshold >= pold
      acc = 1
    if acc == 0
      rank = xor_insert(us, vs, ws, rank, ui, vi, wi) ## i64
      rank = xor_insert(us, vs, ws, rank, uj, vj, wj) ## i64
      rank = xor_insert(us, vs, ws, rank, au, av2, aw) ## i64
      rank = xor_insert(us, vs, ws, rank, bu, bv, bw) ## i64
    since = 0
  if (mv % {plusper}) == 0
    rng = (rng * 1103515245 + 12345) & 2147483647
    pti = (rng * rank) >> 31 ## i64
    rng = (rng * 1103515245 + 12345) & 2147483647
    pj = (rng * rank) >> 31 ## i64
    spu = us[pti] ## i64
    spv = vs[pti] ## i64
    spw = ws[pti] ## i64
    wpr = ws[pj] ## i64
    if wpr != spw
      if wpr != 0
        spw2 = spw ^ wpr ## i64
        rank = xor_insert(us, vs, ws, rank, spu, spv, spw) ## i64
        rank = xor_insert(us, vs, ws, rank, spu, spv, wpr) ## i64
        rank = xor_insert(us, vs, ws, rank, spu, spv, spw2) ## i64
  threshold = {thr} - ((mv / {thrper}) % {thrspan}) ## i64
  if rank > best_rank + 10
    ri = 0
    while ri < best_rank
      us[ri] = bus[ri]
      vs[ri] = bvs[ri]
      ws[ri] = bws[ri]
      ri += 1
    rank = best_rank
  if rank < best_rank
    best_rank = rank
    ci = 0
    while ci < rank
      bus[ci] = us[ci]
      bvs[ci] = vs[ci]
      bws[ci] = ws[ci]
      ci += 1
    if best_rank <= {recv}
      << "*** FOUND rank=" + rank.to_s() + " verify=" + verify(us, vs, ws, rank, 7).to_s()
      di = 0
      while di < rank
        << "R " + us[di].to_s() + " " + vs[di].to_s() + " " + ws[di].to_s()
        di += 1
      flush()
  if (mv % 5000000) == 0
    << "  mv=" + mv.to_s() + " best=" + best_rank.to_s() + " cur=" + rank.to_s() + " v=" + verify(us, vs, ws, rank, 7).to_s()
    flush()
  mv += 1
<< "DONE best=" + best_rank.to_s() + " verify=" + verify(bus, bvs, bws, best_rank, 31).to_s()
di = 0
while di < best_rank
  << "R " + bus[di].to_s() + " " + bvs[di].to_s() + " " + bws[di].to_s()
  di += 1
'''

if __name__ == "__main__":
    import sys
    n, m, p, recv = int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
    seed = sys.argv[5] if len(sys.argv) > 5 else None
    cap = int(sys.argv[6]) if len(sys.argv) > 6 else 14000000000
    thr = int(sys.argv[7]) if len(sys.argv) > 7 else 6
    thrper = int(sys.argv[8]) if len(sys.argv) > 8 else 300000
    plusper = int(sys.argv[9]) if len(sys.argv) > 9 else 2000
    print(gen(n, m, p, recv, seed=seed, cap=cap, thr=thr, thrper=thrper, plusper=plusper), end="")
