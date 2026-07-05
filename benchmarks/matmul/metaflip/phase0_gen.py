"""Phase 0 prototype: single-candidate vs. exact-mirror best-of-N partner
selection, isolated to that ONE variable — everything else (threshold
schedule, fixed band, periodic plus-move, accept/reject test) is byte-
identical between the two modes, copied verbatim from bucket_gen.py's
proven wcal2 walker.

mode="single": today's approach — chain_rpick reservoir-samples ONE random
  valid partner from the axis's hash chain, commits, accepts/rejects by the
  existing pold/pnew threshold test.

mode="bestof": walks the ENTIRE axis hash chain (every valid partner, not a
  random one), scores each by pre-commit pressure (cheap: pressure() reads
  the CURRENT table state and works on a (u,v,w) triple whether or not it's
  inserted yet, so no commit+revert needed to score a candidate), picks the
  single best-scoring partner, then commits and runs the IDENTICAL
  accept/reject test as "single" mode on that one choice. This is a serial
  reference implementation of the same selection rule Phase 2's GPU kernel
  would run in parallel (one reference term + axis, scan all candidates,
  commit the best) — same algorithm, different execution substrate.

Diagnostics: every move logs candidates_scanned (chain length walked) so a
"no improvement" result can be distinguished from "the prototype has a bug".

Usage: python3 phase0_gen.py <n> <m> <p> <recv> <mode> [seed] [cap] [thr] [band]
"""


def gen(n, m, p, recv, mode, arr=200, cap=14000000000, seed=None, thr=6, thrper=300000,
        plusper=2000, band=10, stopat=None, scan_budget=None):
    assert mode in ("single", "bestof")
    AB, BB, CB = n * m, m * p, n * p
    maxbits = max(AB, BB, CB) + 1
    seed_lines = None
    if seed is not None:
        seed_lines = [ln for ln in open(seed).read().splitlines()
                      if ln.startswith(("us[", "vs[", "ws["))]
        seed_rank = len(seed_lines) // 3
        arr = max(arr, seed_rank + 80)
    else:
        seed_rank = n * m * p
        arr = max(arr, seed_rank + 80)
    TS = 1
    while TS < 8 * arr + 8:
        TS *= 2

    off = {}
    cur = 0
    for name, size in [("P2", maxbits), ("US", arr), ("VS", arr), ("WS", arr),
                       ("BUS", arr), ("BVS", arr), ("BWS", arr),
                       ("LIVE", arr), ("POS", arr), ("FL", arr), ("FLT", 2),
                       ("HU", TS), ("HV", TS), ("HW", TS),
                       ("NXU", arr), ("PVU", arr), ("NXV", arr), ("PVV", arr),
                       ("NXW", arr), ("PVW", arr), ("IDL", arr),
                       ("SU", arr + 8), ("SV", arr + 8), ("SW", arr + 8)]:
        off[name] = cur
        cur += size
    TOT = cur
    O = off

    if seed_lines is not None:
        seed_terms = "\n".join(
            ln.replace("us[", f"st[{O['SU']} + ").replace("vs[", f"st[{O['SV']} + ")
              .replace("ws[", f"st[{O['SW']} + ")
            for ln in seed_lines)
        seed_block = f"""{seed_terms}
bi = 0
while bi < {seed_rank}
  tu = st[{O['SU']} + bi] ## i64
  tv = st[{O['SV']} + bi] ## i64
  tw = st[{O['SW']} + bi] ## i64
  rank = ins_term(st, tu, tv, tw, rank)
  bi += 1"""
    else:
        seed_block = f"""ni = 0
while ni < {n}
  nj = 0
  while nj < {m}
    nk = 0
    while nk < {p}
      tu = st[{O['P2']} + ni * {m} + nj] ## i64
      tv = st[{O['P2']} + nj * {p} + nk] ## i64
      tw = st[{O['P2']} + ni * {p} + nk] ## i64
      rank = ins_term(st, tu, tv, tw, rank)
      nk += 1
    nj += 1
  ni += 1"""

    stop_block = ""
    if stopat is not None:
        stop_block = f"""    if best_rank <= {stopat}
      mv = {cap}"""

    scan_budget_block = ""
    if scan_budget is not None:
        scan_budget_block = f"""  if totalscanned >= {scan_budget}
    mv = {cap}"""

    thrspan = thr + 1

    if mode == "single":
        select_block = f"""  scanned = 1 ## i64
  rng = (rng * 1103515245 + 12345) & 2147483647
  partner = 0 - 1 ## i64
  if axis == 0
    partner = chain_rpick(st, {O['HU']}, {O['NXU']}, {O['US']}, ui, ti, rng)
  if axis == 1
    partner = chain_rpick(st, {O['HV']}, {O['NXV']}, {O['VS']}, vi, ti, rng)
  if axis == 2
    partner = chain_rpick(st, {O['HW']}, {O['NXW']}, {O['WS']}, wi, ti, rng)"""
    else:
        select_block = f"""  scanned = 0 ## i64
  partner = 0 - 1 ## i64
  best_score = 0 - 1000000000 ## i64
  key = ui ## i64
  ho = {O['HU']} ## i64
  nxo = {O['NXU']} ## i64
  mo = {O['US']} ## i64
  if axis == 1
    key = vi
    ho = {O['HV']}
    nxo = {O['NXV']}
    mo = {O['VS']}
  if axis == 2
    key = wi
    ho = {O['HW']}
    nxo = {O['NXW']}
    mo = {O['WS']}
  c = st[ho + hsh(key)] ## i64
  while c != 0
    s = c - 1 ## i64
    if st[mo + s] == key
      if s != ti
        scanned += 1
        cuj = st[{O['US']} + s] ## i64
        cvj = st[{O['VS']} + s] ## i64
        cwj = st[{O['WS']} + s] ## i64
        cau = ui ## i64
        cav = vi ## i64
        caw = wi ## i64
        cbu = ui ## i64
        cbv = vi ## i64
        cbw = cwj ## i64
        if axis == 0
          caw = wi ^ cwj
          cbv = vi ^ cvj
        if axis == 1
          caw = wi ^ cwj
          cbu = ui ^ cuj
        if axis == 2
          cav = vi ^ cvj
          caw = wi
          cbu = ui ^ cuj
          cbv = cvj
          cbw = wi
        cscore = pressure(st, cau, cav, caw) + pressure(st, cbu, cbv, cbw) ## i64
        if cscore > best_score
          best_score = cscore
          partner = s
    c = st[nxo + s]"""

    return f'''st = i64[{TOT}]
st[0] = 1
kk = 1
while kk < {maxbits}
  st[0 + kk] = st[0 + kk - 1] + st[0 + kk - 1]
  kk += 1
ii = 0
while ii < {arr}
  st[{O['LIVE']} + ii] = ii
  st[{O['FL']} + ii] = {arr} - 1 - ii
  st[{O['IDL']} + ii] = ii
  ii += 1
st[{O['FLT']}] = {arr}

-> hsh(x) (i64) i64
  y = x ^ (x >> 21) ^ (x >> 42) ## i64
  ((y * 2654435761) >> 13) & {TS - 1}

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
    c = st[{O['HU']} + hsh(u)] ## i64
    while c != 0
      s = c - 1 ## i64
      if st[{O['US']} + s] == u
        if st[{O['VS']} + s] == v
          if st[{O['WS']} + s] == w
            found = s
      c = st[{O['NXU']} + s]
      if found >= 0
        c = 0
    if found < 0
      fltop = st[{O['FLT']}] ## i64
      slot = st[{O['FL']} + fltop - 1] ## i64
      st[{O['FLT']}] = fltop - 1
      st[{O['US']} + slot] = u
      st[{O['VS']} + slot] = v
      st[{O['WS']} + slot] = w
      z0 = chain_link(st, {O['HU']}, {O['NXU']}, {O['PVU']}, slot, u) ## i64
      z0 = chain_link(st, {O['HV']}, {O['NXV']}, {O['PVV']}, slot, v) ## i64
      z0 = chain_link(st, {O['HW']}, {O['NXW']}, {O['PVW']}, slot, w) ## i64
      st[{O['LIVE']} + rank] = slot
      st[{O['POS']} + slot] = rank
      res = rank + 1
    if found >= 0
      z0 = chain_unlink(st, {O['HU']}, {O['NXU']}, {O['PVU']}, found, u) ## i64
      z0 = chain_unlink(st, {O['HV']}, {O['NXV']}, {O['PVV']}, found, v) ## i64
      z0 = chain_unlink(st, {O['HW']}, {O['NXW']}, {O['PVW']}, found, w) ## i64
      dp = st[{O['POS']} + found] ## i64
      lastslot = st[{O['LIVE']} + rank - 1] ## i64
      st[{O['LIVE']} + dp] = lastslot
      st[{O['POS']} + lastslot] = dp
      fltop = st[{O['FLT']}] ## i64
      st[{O['FL']} + fltop] = found
      st[{O['FLT']}] = fltop + 1
      res = rank - 1
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
  c = st[{O['HU']} + hsh(u)] ## i64
  while c != 0
    s = c - 1 ## i64
    if st[{O['US']} + s] == u
      mv2 = 0 ## i64
      if st[{O['VS']} + s] == v
        mv2 = 1
      mw2 = 0 ## i64
      if st[{O['WS']} + s] == w
        mw2 = 1
      if mv2 + mw2 == 1
        cnt = cnt + 1
    c = st[{O['NXU']} + s]
  c = st[{O['HV']} + hsh(v)] ## i64
  while c != 0
    s = c - 1 ## i64
    if st[{O['VS']} + s] == v
      if st[{O['US']} + s] != u
        if st[{O['WS']} + s] == w
          cnt = cnt + 1
    c = st[{O['NXV']} + s]
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
    av = ((s * 8388608) ^ s2) % {1 << AB}
    s = (s2 * 16807) % 2147483647
    s2 = (s * 16807) % 2147483647
    bv = ((s * 8388608) ^ s2) % {1 << BB}
    s = s2
    o = 0
    while o < {n * p}
      cs = 0
      t = 0
      while t < rank
        sl = st[mo + t] ## i64
        if ((st[wo + sl] >> o) & 1) == 1
          if parity(st[uo + sl], av, {AB}) == 1
            if parity(st[vo + sl], bv, {BB}) == 1
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

rank = 0 ## i64
{seed_block}
<< "seed rank=" + rank.to_s() + " verify=" + verify(st, {O['US']}, {O['VS']}, {O['WS']}, {O['LIVE']}, rank, 7).to_s()
flush()
best_rank = rank ## i64
bi = 0
while bi < rank
  sl = st[{O['LIVE']} + bi] ## i64
  st[{O['BUS']} + bi] = st[{O['US']} + sl]
  st[{O['BVS']} + bi] = st[{O['VS']} + sl]
  st[{O['BWS']} + bi] = st[{O['WS']} + sl]
  bi += 1
base = 1
dumpfile = ""
av0 = argv()
if av0.size() > 0
  base = av0[0].to_i()
if av0.size() > 1
  dumpfile = av0[1]
rng = base * 1009 + 12345 ## i64
threshold = {thr} ## i64
totalscanned = 0 ## i64
mv = 0 ## i64
while mv < {cap}
  rng = (rng * 1103515245 + 12345) & 2147483647
  td = (rng * rank) >> 31 ## i64
  ti = st[{O['LIVE']} + td] ## i64
  ui = st[{O['US']} + ti] ## i64
  vi = st[{O['VS']} + ti] ## i64
  wi = st[{O['WS']} + ti] ## i64
  rng = (rng * 1103515245 + 12345) & 2147483647
  axis = (((rng >> 22) & 511) * 3) >> 9 ## i64
{select_block}
  totalscanned = totalscanned + scanned
{scan_budget_block}
  if partner >= 0
    uj = st[{O['US']} + partner] ## i64
    vj = st[{O['VS']} + partner] ## i64
    wj = st[{O['WS']} + partner] ## i64
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
    if pnew + threshold >= pold
      acc = 1
    if acc == 0
      rank = ins_term(st, ui, vi, wi, rank) ## i64
      rank = ins_term(st, uj, vj, wj, rank) ## i64
      rank = ins_term(st, au, av2, aw, rank) ## i64
      rank = ins_term(st, bu, bv, bw, rank) ## i64
  if (mv % {plusper}) == 0
    rng = (rng * 1103515245 + 12345) & 2147483647
    pd1 = (rng * rank) >> 31 ## i64
    pt1 = st[{O['LIVE']} + pd1] ## i64
    rng = (rng * 1103515245 + 12345) & 2147483647
    pd2 = (rng * rank) >> 31 ## i64
    pt2 = st[{O['LIVE']} + pd2] ## i64
    spu = st[{O['US']} + pt1] ## i64
    spv = st[{O['VS']} + pt1] ## i64
    spw = st[{O['WS']} + pt1] ## i64
    wpr = st[{O['WS']} + pt2] ## i64
    if wpr != spw
      if wpr != 0
        spw2 = spw ^ wpr ## i64
        rank = ins_term(st, spu, spv, spw, rank) ## i64
        rank = ins_term(st, spu, spv, wpr, rank) ## i64
        rank = ins_term(st, spu, spv, spw2, rank) ## i64
  threshold = {thr} - ((mv / {thrper}) % {thrspan}) ## i64
  if rank > best_rank + {band}
    while rank > 0
      sl = st[{O['LIVE']} + rank - 1] ## i64
      cu = st[{O['US']} + sl] ## i64
      cv = st[{O['VS']} + sl] ## i64
      cw = st[{O['WS']} + sl] ## i64
      rank = ins_term(st, cu, cv, cw, rank)
    ri = 0
    while ri < best_rank
      cu = st[{O['BUS']} + ri] ## i64
      cv = st[{O['BVS']} + ri] ## i64
      cw = st[{O['BWS']} + ri] ## i64
      rank = ins_term(st, cu, cv, cw, rank)
      ri += 1
  if rank < best_rank
    best_rank = rank
    << "IMP rank=" + rank.to_s() + " mv=" + mv.to_s() + " scanned=" + totalscanned.to_s()
    flush()
    if dumpfile.size() > 0
      dumpbody = rank.to_s() + "\n"
      di2 = 0
      while di2 < rank
        sl2 = st[{O['LIVE']} + di2] ## i64
        dumpbody = dumpbody + st[{O['US']} + sl2].to_s() + " " + st[{O['VS']} + sl2].to_s() + " " + st[{O['WS']} + sl2].to_s() + "\n"
        di2 += 1
      write_file(dumpfile, dumpbody)
    ci = 0
    while ci < rank
      sl = st[{O['LIVE']} + ci] ## i64
      st[{O['BUS']} + ci] = st[{O['US']} + sl]
      st[{O['BVS']} + ci] = st[{O['VS']} + sl]
      st[{O['BWS']} + ci] = st[{O['WS']} + sl]
      ci += 1
{stop_block}
  if (mv % 50000000) == 0
    << "  mv=" + mv.to_s() + " best=" + best_rank.to_s() + " cur=" + rank.to_s() + " scanned=" + totalscanned.to_s() + " v=" + verify(st, {O['US']}, {O['VS']}, {O['WS']}, {O['LIVE']}, rank, 7).to_s()
    flush()
  mv += 1
<< "DONE best=" + best_rank.to_s() + " totalscanned=" + totalscanned.to_s() + " totalmoves=" + mv.to_s() + " verify=" + verify(st, {O['BUS']}, {O['BVS']}, {O['BWS']}, {O['IDL']}, best_rank, 31).to_s()
'''


if __name__ == "__main__":
    import sys
    n, m, p, recv, mode = int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]), sys.argv[5]
    seed = sys.argv[6] if len(sys.argv) > 6 and sys.argv[6] != "naive" else None
    cap = int(sys.argv[7]) if len(sys.argv) > 7 else 14000000000
    thr = int(sys.argv[8]) if len(sys.argv) > 8 else 6
    band = int(sys.argv[9]) if len(sys.argv) > 9 else 10
    print(gen(n, m, p, recv, mode, seed=seed, cap=cap, thr=thr, band=band), end="")
