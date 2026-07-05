"""Generate a Moosbauer-Poole style C3-symmetric flip-graph walker for <N,N,N>
over GF(2), in Tungsten (port of search/sym5_mp93.w, parameterized).

Quotient walk: every mutation appends the FULL C3 orbit of a term —
(u,v,w), (v, w^T, u^T), (w^T, u, v^T) — then mod-2 dedup collapses even
multiplicities, so the scheme stays closed under the cyclic symmetry
(i,j,k)->(j,k,i) at every step. This is the move set that produced the
5x5=93 and 6x6=153 records (arXiv:2502.04514); the base axis-flip graph
alone plateaus well above them (95 / 161).

Seeds must be C3-closed: the naive <N,N,N> scheme is (term (i,j,k) maps to
term (j,k,i)); a seed FILE is checked for closure and exact validity here
before it is embedded.

Usage: python3 sym_gen2.py <N> <recv> [seedfile|naive] [cap] [plusper] [band]
"""
import sys

from metaflip_proto2 import T, recon
from seed_prep import parse_terms


def tr_mask(mask, n):
    r = 0
    for b in range(n * n):
        if (mask >> b) & 1:
            i, j = divmod(b, n)
            r |= 1 << (j * n + i)
    return r


def check_c3_closed(terms, n):
    s = set(terms)
    for u, v, w in terms:
        if (v, tr_mask(w, n), tr_mask(u, n)) not in s:
            return False
    return True


def gen(n, recv, seed=None, cap=14000000000, plusper=200, band=15):
    DIM = n * n
    MOD = 1 << DIM
    seed_block = ""
    if seed is not None:
        terms = parse_terms(seed)[0]
        S = set()
        for t in terms:
            S.discard(t) if t in S else S.add(t)
        assert recon(S, n, n, n) == T(n, n, n), "seed not a valid decomposition"
        assert check_c3_closed(sorted(S), n), "seed is not C3-symmetric"
        terms = sorted(S)
        seed_rank = len(terms)
        lines = []
        for k, (u, v, w) in enumerate(terms):
            lines.append(f"us[{k}] = {u}")
        for k, (u, v, w) in enumerate(terms):
            lines.append(f"vs[{k}] = {v}")
        for k, (u, v, w) in enumerate(terms):
            lines.append(f"ws[{k}] = {w}")
        body = "\n".join(lines)
        seed_block = f"""rank = 0 ## i64
{body}
rank = {seed_rank}
"""
        arr = seed_rank + 140
    else:
        seed_rank = n * n * n
        arr = seed_rank + 140
        seed_block = f"""rank = 0 ## i64
ni = 0
while ni < {n}
  nj = 0
  while nj < {n}
    nk = 0
    while nk < {n}
      us[rank] = p2[ni * {n} + nj]
      vs[rank] = p2[nj * {n} + nk]
      ws[rank] = p2[ni * {n} + nk]
      rank += 1
      nk += 1
    nj += 1
  ni += 1"""
    return f'''p2 = i64[{DIM + 1}]
p2[0] = 1
kk = 1
while kk < {DIM + 1}
  p2[kk] = p2[kk - 1] + p2[kk - 1]
  kk += 1
us = i64[{arr}]
vs = i64[{arr}]
ws = i64[{arr}]
bus = i64[{arr}]
bvs = i64[{arr}]
bws = i64[{arr}]

-> parity(mask, vec) (i64 i64) i64
  pr = 0
  b = 0
  while b < {DIM}
    if ((mask >> b) & 1) == 1
      if ((vec >> b) & 1) == 1
        pr = (pr + 1) % 2
    b += 1
  pr

-> tr(mask, p2) (i64 i64[]) i64
  r = 0 ## i64
  b = 0 ## i64
  while b < {DIM}
    if ((mask >> b) & 1) == 1
      ii = b / {n} ## i64
      jj = b % {n} ## i64
      r = r | p2[jj * {n} + ii]
    b += 1
  r

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

-> xor_insert_orbit(us, vs, ws, rank, u, v, w, p2) (i64[] i64[] i64[] i64 i64 i64 i64 i64[]) i64
  tw = tr(w, p2) ## i64
  tu = tr(u, p2) ## i64
  tv = tr(v, p2) ## i64
  r1 = xor_insert(us, vs, ws, rank, u, v, w) ## i64
  r2 = xor_insert(us, vs, ws, r1, v, tw, tu) ## i64
  r3 = xor_insert(us, vs, ws, r2, tw, u, tv) ## i64
  r3

-> verify(qs, rs, ts, rank, seed0) (i64[] i64[] i64[] i64 i64) i64
  ok = 1
  s = seed0
  trial = 0
  while trial < 20
    s = (s * 16807) % 2147483647
    s2 = (s * 16807) % 2147483647
    av = ((s * 8388608) ^ s2) % {MOD}
    s = (s2 * 16807) % 2147483647
    s2 = (s * 16807) % 2147483647
    bv = ((s * 8388608) ^ s2) % {MOD}
    s = s2
    o = 0
    while o < {DIM}
      cs = 0
      t = 0
      while t < rank
        if ((ts[t] >> o) & 1) == 1
          if parity(qs[t], av) == 1
            if parity(rs[t], bv) == 1
              cs = (cs + 1) % 2
        t += 1
      oi = o / {n}
      oj = o % {n}
      ct = 0
      kx = 0
      while kx < {n}
        if ((av >> (oi * {n} + kx)) & 1) == 1
          if ((bv >> (kx * {n} + oj)) & 1) == 1
            ct = (ct + 1) % 2
        kx += 1
      if cs != ct
        ok = 0
      o += 1
    trial += 1
  ok

{seed_block}
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
mv = 0 ## i64
while mv < {cap}
  rng = (rng * 1103515245 + 12345) & 2147483647
  ti = (rng * rank) >> 31 ## i64
  ui = us[ti] ## i64
  vi = vs[ti] ## i64
  wi = ws[ti] ## i64
  twi = tr(wi, p2) ## i64
  tui = tr(ui, p2) ## i64
  tvi = tr(vi, p2) ## i64
  rng = (rng * 1103515245 + 12345) & 2147483647
  axis = (((rng >> 22) & 511) * 3) >> 9 ## i64
  st = (((rng >> 11) & 1048575) * rank) >> 20 ## i64
  partner = 0 - 1 ## i64
  jj = st ## i64
  scan = 0 ## i64
  while scan < rank
    if jj != ti
      inorb = 0 ## i64
      if us[jj] == vi
        if vs[jj] == twi
          if ws[jj] == tui
            inorb = 1
      if us[jj] == twi
        if vs[jj] == ui
          if ws[jj] == tvi
            inorb = 1
      if inorb == 0
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
  if partner >= 0
    since = 0
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
    rank = xor_insert_orbit(us, vs, ws, rank, ui, vi, wi, p2) ## i64
    rank = xor_insert_orbit(us, vs, ws, rank, uj, vj, wj, p2) ## i64
    rank = xor_insert_orbit(us, vs, ws, rank, au, av2, aw, p2) ## i64
    rank = xor_insert_orbit(us, vs, ws, rank, bu, bv, bw, p2) ## i64
  if (mv % {plusper}) == 0
    rng = (rng * 1103515245 + 12345) & 2147483647
    pti = (rng * rank) >> 31 ## i64
    rng = (rng * 1103515245 + 12345) & 2147483647
    pj = (rng * rank) >> 31 ## i64
    pu = us[pti] ## i64
    pv = vs[pti] ## i64
    pw = ws[pti] ## i64
    wprime = ws[pj] ## i64
    if wprime != pw
      if wprime != 0
        pw2 = pw ^ wprime ## i64
        rank = xor_insert_orbit(us, vs, ws, rank, pu, pv, wprime, p2) ## i64
        rank = xor_insert_orbit(us, vs, ws, rank, pu, pv, pw2, p2) ## i64
        rank = xor_insert_orbit(us, vs, ws, rank, pu, pv, pw, p2) ## i64
    since = 0
  if rank > best_rank + {band}
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
  if (mv % 1000000) == 0
    << "  mv=" + mv.to_s() + " best=" + best_rank.to_s() + " cur=" + rank.to_s() + " v=" + verify(us, vs, ws, rank, 7).to_s()
    flush()
  mv += 1
<< "DONE best=" + best_rank.to_s() + " verify=" + verify(bus, bvs, bws, best_rank, 31).to_s()
di = 0
while di < best_rank
  << "R " + bus[di].to_s() + " " + bvs[di].to_s() + " " + bws[di].to_s()
  di += 1
'''


def gen_sawtooth(n, recv, cap=14000000000, plusper=200, stopat=None,
                  z1max=4, z1q=100000000, workq=3000000000, wstep=10, wq=500000000,
                  thr0=10, thrbump=2, rsmax=4, band=None):
    """Sawtooth-schedule variant of gen(): self-calibrating band escalation
    (start zone / work zone / wander zone, threshold rises to descent band +
    thrbump, sawtooth wrap past 60 with reset-to-seed + fresh RNG on the 2nd
    wrap) ported onto the C3-symmetric quotient walker. Naive seed only."""
    DIM = n * n
    MOD = 1 << DIM
    seed_rank = n * n * n
    arr = seed_rank + 400
    naive_fill = f"""ni = 0
while ni < {n}
  nj = 0
  while nj < {n}
    nk = 0
    while nk < {n}
      us[rank] = p2[ni * {n} + nj]
      vs[rank] = p2[nj * {n} + nk]
      ws[rank] = p2[ni * {n} + nk]
      rank += 1
      nk += 1
    nj += 1
  ni += 1"""

    def indent(text, pad):
        return "\n".join(pad + line if line else line for line in text.split("\n"))
    stop_block = ""
    if stopat is not None:
        stop_block = f"""    if best_rank <= {stopat}
      mv = {cap}"""
    return f'''p2 = i64[{DIM + 1}]
p2[0] = 1
kk = 1
while kk < {DIM + 1}
  p2[kk] = p2[kk - 1] + p2[kk - 1]
  kk += 1
us = i64[{arr}]
vs = i64[{arr}]
ws = i64[{arr}]
bus = i64[{arr}]
bvs = i64[{arr}]
bws = i64[{arr}]

-> parity(mask, vec) (i64 i64) i64
  pr = 0
  b = 0
  while b < {DIM}
    if ((mask >> b) & 1) == 1
      if ((vec >> b) & 1) == 1
        pr = (pr + 1) % 2
    b += 1
  pr

-> tr(mask, p2) (i64 i64[]) i64
  r = 0 ## i64
  b = 0 ## i64
  while b < {DIM}
    if ((mask >> b) & 1) == 1
      ii = b / {n} ## i64
      jj = b % {n} ## i64
      r = r | p2[jj * {n} + ii]
    b += 1
  r

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

-> xor_insert_orbit(us, vs, ws, rank, u, v, w, p2) (i64[] i64[] i64[] i64 i64 i64 i64 i64[]) i64
  tw = tr(w, p2) ## i64
  tu = tr(u, p2) ## i64
  tv = tr(v, p2) ## i64
  r1 = xor_insert(us, vs, ws, rank, u, v, w) ## i64
  r2 = xor_insert(us, vs, ws, r1, v, tw, tu) ## i64
  r3 = xor_insert(us, vs, ws, r2, tw, u, tv) ## i64
  r3

-> verify(qs, rs, ts, rank, seed0) (i64[] i64[] i64[] i64 i64) i64
  ok = 1
  s = seed0
  trial = 0
  while trial < 20
    s = (s * 16807) % 2147483647
    s2 = (s * 16807) % 2147483647
    av = ((s * 8388608) ^ s2) % {MOD}
    s = (s2 * 16807) % 2147483647
    s2 = (s * 16807) % 2147483647
    bv = ((s * 8388608) ^ s2) % {MOD}
    s = s2
    o = 0
    while o < {DIM}
      cs = 0
      t = 0
      while t < rank
        if ((ts[t] >> o) & 1) == 1
          if parity(qs[t], av) == 1
            if parity(rs[t], bv) == 1
              cs = (cs + 1) % 2
        t += 1
      oi = o / {n}
      oj = o % {n}
      ct = 0
      kx = 0
      while kx < {n}
        if ((av >> (oi * {n} + kx)) & 1) == 1
          if ((bv >> (kx * {n} + oj)) & 1) == 1
            ct = (ct + 1) % 2
        kx += 1
      if cs != ct
        ok = 0
      o += 1
    trial += 1
  ok

rank = 0 ## i64
{naive_fill}
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
{"bstart = " + str(band) + " ## i64" if band is not None else f"""rng = (rng * 1103515245 + 12345) & 2147483647
rng = (rng * 1103515245 + 12345) & 2147483647
rng = (rng * 1103515245 + 12345) & 2147483647
bstart = 1 + ((rng >> 27) % {rsmax}) ## i64"""}
aband = bstart ## i64
nextesc = {z1q} ## i64
wthr = {thr0} ## i64
wraps = 0 ## i64
<< "BSTART " + bstart.to_s()
flush()
since = 0 ## i64
mv = 0 ## i64
while mv < {cap}
  rng = (rng * 1103515245 + 12345) & 2147483647
  ti = (rng * rank) >> 31 ## i64
  ui = us[ti] ## i64
  vi = vs[ti] ## i64
  wi = ws[ti] ## i64
  twi = tr(wi, p2) ## i64
  tui = tr(ui, p2) ## i64
  tvi = tr(vi, p2) ## i64
  rng = (rng * 1103515245 + 12345) & 2147483647
  axis = (((rng >> 22) & 511) * 3) >> 9 ## i64
  st = (((rng >> 11) & 1048575) * rank) >> 20 ## i64
  partner = 0 - 1 ## i64
  jj = st ## i64
  scan = 0 ## i64
  while scan < rank
    if jj != ti
      inorb = 0 ## i64
      if us[jj] == vi
        if vs[jj] == twi
          if ws[jj] == tui
            inorb = 1
      if us[jj] == twi
        if vs[jj] == ui
          if ws[jj] == tvi
            inorb = 1
      if inorb == 0
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
  if partner >= 0
    since = 0
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
    rank = xor_insert_orbit(us, vs, ws, rank, ui, vi, wi, p2) ## i64
    rank = xor_insert_orbit(us, vs, ws, rank, uj, vj, wj, p2) ## i64
    rank = xor_insert_orbit(us, vs, ws, rank, au, av2, aw, p2) ## i64
    rank = xor_insert_orbit(us, vs, ws, rank, bu, bv, bw, p2) ## i64
  if (mv % {plusper}) == 0
    rng = (rng * 1103515245 + 12345) & 2147483647
    pti = (rng * rank) >> 31 ## i64
    rng = (rng * 1103515245 + 12345) & 2147483647
    pj = (rng * rank) >> 31 ## i64
    pu = us[pti] ## i64
    pv = vs[pti] ## i64
    pw = ws[pti] ## i64
    wprime = ws[pj] ## i64
    if wprime != pw
      if wprime != 0
        pw2 = pw ^ wprime ## i64
        rank = xor_insert_orbit(us, vs, ws, rank, pu, pv, wprime, p2) ## i64
        rank = xor_insert_orbit(us, vs, ws, rank, pu, pv, pw2, p2) ## i64
        rank = xor_insert_orbit(us, vs, ws, rank, pu, pv, pw, p2) ## i64
    since = 0
  if mv >= nextesc
    nb = aband + 1 ## i64
    if aband > wthr
      nb = aband + {wstep}
    if nb > 60
      nb = bstart
      wraps = wraps + 1
      if wraps >= 2
        wraps = 0
        rng = ((rng ^ (mv & 2147483647)) * 1103515245 + 54321) & 2147483647
        rng = (rng * 1103515245 + 12345) & 2147483647
        rng = (rng * 1103515245 + 12345) & 2147483647
        rank = 0
{indent(naive_fill, "        ")}
        best_rank = rank
        rci = 0
        while rci < rank
          bus[rci] = us[rci]
          bvs[rci] = vs[rci]
          bws[rci] = ws[rci]
          rci += 1
        << "RESTART mv=" + mv.to_s()
        flush()
    aband = nb
    q = {z1q} ## i64
    if aband > {z1max}
      q = {workq}
    if aband > wthr
      q = {wq}
    nextesc = mv + q
    << "BAND band=" + aband.to_s() + " rank=" + rank.to_s() + " mv=" + mv.to_s()
    flush()
  if rank > best_rank + aband
    ri = 0
    while ri < best_rank
      us[ri] = bus[ri]
      vs[ri] = bvs[ri]
      ws[ri] = bws[ri]
      ri += 1
    rank = best_rank
  if rank < best_rank
    best_rank = rank
    << "IMP rank=" + rank.to_s() + " band=" + aband.to_s() + " mv=" + mv.to_s()
    flush()
    ci = 0
    while ci < rank
      bus[ci] = us[ci]
      bvs[ci] = vs[ci]
      bws[ci] = ws[ci]
      ci += 1
    if aband + {thrbump} > wthr
      wthr = aband + {thrbump}
      if wthr > 58
        wthr = 58
      << "WTHR thr=" + wthr.to_s() + " band=" + aband.to_s() + " mv=" + mv.to_s()
      flush()
    if aband != bstart
      aband = bstart
      << "BAND band=" + aband.to_s() + " rank=" + rank.to_s() + " mv=" + mv.to_s()
      flush()
    nextesc = mv + {z1q}
    if best_rank <= {recv}
      << "*** FOUND rank=" + rank.to_s() + " verify=" + verify(us, vs, ws, rank, 7).to_s()
      di = 0
      while di < rank
        << "R " + us[di].to_s() + " " + vs[di].to_s() + " " + ws[di].to_s()
        di += 1
      flush()
{stop_block}
  if (mv % 1000000) == 0
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
    n, recv = int(sys.argv[1]), int(sys.argv[2])
    seed = sys.argv[3] if len(sys.argv) > 3 and sys.argv[3] != "naive" else None
    cap = int(sys.argv[4]) if len(sys.argv) > 4 else 14000000000
    plusper = int(sys.argv[5]) if len(sys.argv) > 5 else 200
    band = int(sys.argv[6]) if len(sys.argv) > 6 else 15
    print(gen(n, recv, seed=seed, cap=cap, plusper=plusper, band=band), end="")
