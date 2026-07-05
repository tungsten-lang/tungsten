"""Generate the META-WALK in Tungsten: flip (Algorithm 1) + cross-format edges + per-format best.
Square n=m=N; p wanders in [PMIN,PMAX]. Seeded from a scheme file. Hunts best (N,N,N) < RECV."""
import re

HELPERS = r'''-> parity(mask, vec, width) (i64 i64 i64)
  pr = 0
  b = 0
  while b < width
    if ((mask >> b) & 1) == 1
      if ((vec >> b) & 1) == 1
        pr = (pr + 1) % 2
    b += 1
  pr
-> xor_insert(us, vs, ws, rank, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64)
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
-> widen_cols(mask, rows, oldc, newc, p2) (i64 i64 i64 i64 i64[])
  r = 0 ## i64
  b = 0 ## i64
  while b < rows * oldc
    if ((mask >> b) & 1) == 1
      ii = b / oldc ## i64
      cc = b % oldc ## i64
      r = r | p2[ii * newc + cc]
    b += 1
  r
-> drop_last_col(mask, rows, oldc, p2) (i64 i64 i64 i64[])
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
-> extend(us, vs, ws, rank, n, mm, pp, p2) (i64[] i64[] i64[] i64 i64 i64 i64 i64[])
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
-> project(us, vs, ws, rank, nus, nvs, nws, n, mm, pp, p2) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64 i64 i64[])
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
-> verify(us, vs, ws, rank, seed0, n, mm, pp) (i64[] i64[] i64[] i64 i64 i64 i64 i64)
  ok = 1
  s = seed0
  ab = n * mm ## i64
  bb = mm * pp ## i64
  cb = n * pp ## i64
  ma = 1 << ab ## i64
  mb = 1 << bb ## i64
  trial = 0
  while trial < 16
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
'''

def gen(n=5, recv=92, seedfile='/Users/erik/tungsten/benchmarks/matmul/search/seed_mp93.txt',
        cap=14000000000, M=10000, xperiod=30000, pmin=None, pmax=None, arr=320):
    if pmin is None: pmin = max(2, n - 2)
    if pmax is None: pmax = n + 2
    terms = []
    us = {}; vs = {}; ws = {}
    for line in open(seedfile):
        line = line.strip()
        mm = re.match(r'(us|vs|ws)\[(\d+)\] = (\d+)', line)
        if mm: {'us': us, 'vs': vs, 'ws': ws}[mm.group(1)][int(mm.group(2))] = int(mm.group(3))
        elif line.startswith('R '): terms.append(tuple(int(x) for x in line.split()[1:]))
        elif len(line.split()) == 3: terms.append(tuple(int(x) for x in line.split()))
    if us: terms = [(us[i], vs[i], ws[i]) for i in sorted(us)]
    R = len(terms)
    seedblock = "\n".join(f"us[{r}] = {terms[r][0]}\nvs[{r}] = {terms[r][1]}\nws[{r}] = {terms[r][2]}" for r in range(R))
    return HELPERS + f'''p2 = i64[64]
p2[0] = 1
kk = 1
while kk < 64
  p2[kk] = p2[kk - 1] + p2[kk - 1]
  kk += 1
us = i64[{arr}]
vs = i64[{arr}]
ws = i64[{arr}]
nus = i64[{arr}]
nvs = i64[{arr}]
nws = i64[{arr}]
bus = i64[{arr}]
bvs = i64[{arr}]
bws = i64[{arr}]
bestp = i64[10]
qq = 0
while qq < 10
  bestp[qq] = 999
  qq += 1
{seedblock}
rank = {R} ## i64
p = {n} ## i64
bestp[{n}] = rank
best5 = rank ## i64
ci = 0
while ci < rank
  bus[ci] = us[ci]
  bvs[ci] = vs[ci]
  bws[ci] = ws[ci]
  ci += 1
<< "seed ({n},{n},{n}) rank=" + rank.to_s() + " verify=" + verify(us, vs, ws, rank, 7, {n}, {n}, {n}).to_s()
base = 1
av0 = argv()
if av0.size() > 0
  base = av0[0].to_i()
rng = base * 1009 + 12345 ## i64
lcount = 0 ## i64
mthresh = {M} ## i64
mv = 0 ## i64
while mv < {cap}
  rng = (rng * 1103515245 + 12345) % 2147483648
  ti = rng % rank ## i64
  ui = us[ti] ## i64
  vi = vs[ti] ## i64
  wi = ws[ti] ## i64
  rng = (rng * 1103515245 + 12345) % 2147483648
  axis = (rng >> 22) % 3 ## i64
  st = (rng >> 11) % rank ## i64
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
  if partner >= 0
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
    rank = xor_insert(us, vs, ws, rank, ui, vi, wi) ## i64
    rank = xor_insert(us, vs, ws, rank, uj, vj, wj) ## i64
    rank = xor_insert(us, vs, ws, rank, au, av2, aw) ## i64
    rank = xor_insert(us, vs, ws, rank, bu, bv, bw) ## i64
  if rank < bestp[p]
    bestp[p] = rank
    lcount = 0
    mthresh = {M}
    if p == {n}
      best5 = rank
      di = 0
      while di < rank
        bus[di] = us[di]
        bvs[di] = vs[di]
        bws[di] = ws[di]
        di += 1
      if rank <= {recv}
        << "*** FOUND ({n},{n},{n}) rank=" + rank.to_s() + " verify=" + verify(us, vs, ws, rank, 7, {n}, {n}, {n}).to_s()
        fd = 0
        while fd < rank
          << "R " + us[fd].to_s() + " " + vs[fd].to_s() + " " + ws[fd].to_s()
          fd += 1
        flush()
  if lcount >= mthresh
    rng = (rng * 1103515245 + 12345) % 2147483648
    pti = rng % rank ## i64
    rng = (rng * 1103515245 + 12345) % 2147483648
    pj = rng % rank ## i64
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
    mthresh = lcount + {M}
  if (mv % {xperiod}) == 0
    rng = (rng * 1103515245 + 12345) % 2147483648
    dir = rng % 2 ## i64
    if dir == 0
      if p < {pmax}
        rank = extend(us, vs, ws, rank, {n}, {n}, p, p2) ## i64
        p = p + 1
    if dir == 1
      if p > {pmin}
        rank = project(us, vs, ws, rank, nus, nvs, nws, {n}, {n}, p, p2) ## i64
        p = p - 1
    lcount = 0
    mthresh = {M}
  if (mv % 5000000) == 0
    << "  mv=" + mv.to_s() + " p=" + p.to_s() + " rank=" + rank.to_s() + " best5=" + best5.to_s() + " v=" + verify(us, vs, ws, rank, 7, {n}, {n}, p).to_s()
    flush()
  lcount = lcount + 1
  mv += 1
<< "DONE bestN=" + best5.to_s() + " bestN-1=" + bestp[{n} - 1].to_s() + " bestN+1=" + bestp[{n} + 1].to_s()
'''

if __name__ == "__main__":
    import sys
    if len(sys.argv) > 1:
        n, recv, seedfile = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
        cap = int(sys.argv[4]) if len(sys.argv) > 4 else 14000000000
        print(gen(n=n, recv=recv, seedfile=seedfile, cap=cap), end="")
    else:
        print(gen(), end="")
