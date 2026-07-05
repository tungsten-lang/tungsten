"""Generate a Tungsten sparsification pass for a GF(2) matmul scheme.

Flips preserve the tensor exactly, so the same move set that hunts rank can
instead hunt DENSITY: walk flips, accept any rank reduction for free, and
otherwise accept a flip iff the scheme's total set-bit count doesn't rise by
more than a small cycling slack (the walker's proven explore/consolidate
rhythm, applied to bits instead of rank). Snap back to the best scheme when
the walk balloons. Rank never increases (no plus moves).

Objective is lexicographic (rank, total_bits): a sparser scheme at the same
rank, or any lower rank, is an improvement and is dumped immediately.

Usage: python3 sparsify_gen.py <n> <m> <p> <seedfile> [cap] [slack] [slackper] [band]
  seedfile: either `R u v w` lines or `us[i] = ...` triples.
Emits Tungsten source on stdout. Generated program CLI:
  binary [rng_base] [dumpfile]
Dump format matches the walkers: first line rank, then `u v w` lines
(prefixed R on stdout blocks), so harvest.py/exact validators apply as-is.
"""
import sys


def read_seed(path):
    terms = []
    us, vs, ws = {}, {}, {}
    for ln in open(path):
        ln = ln.strip()
        if ln.startswith("R "):
            _, u, v, w = ln.split()
            terms.append((int(u), int(v), int(w)))
        elif ln.startswith(("us[", "vs[", "ws[")):
            name = ln[:2]
            idx = int(ln[3:ln.index("]")])
            val = int(ln.split("=")[1])
            {"us": us, "vs": vs, "ws": ws}[name][idx] = val
        elif len(ln.split()) == 3:
            # bare walker-dump format: "rank" header line then "u v w" rows
            terms.append(tuple(int(x) for x in ln.split()))
    if us:
        terms = [(us[i], vs[i], ws[i]) for i in sorted(us)]
    return terms


def gen(n, m, p, seedfile, cap=300000000, slack=2, slackper=200000, band=30):
    terms = read_seed(seedfile)
    seed_rank = len(terms)
    arr = seed_rank + 8
    AB, BB, CB = n * m, m * p, n * p
    MODA, MODB = 1 << AB, 1 << BB
    slackspan = slack + 1
    seed_lines = "\n".join(
        f"us[{i}] = {u}\nvs[{i}] = {v}\nws[{i}] = {w}"
        for i, (u, v, w) in enumerate(terms))

    return f'''-> parity(mask, vec, width) (i64 i64 i64)
  pr = 0
  b = 0
  while b < width
    if ((mask >> b) & 1) == 1
      if ((vec >> b) & 1) == 1
        pr = (pr + 1) % 2
    b += 1
  pr
-> pc(x) (i64) i64
  c = 0 ## i64
  y = x ## i64
  while y != 0
    y = y & (y - 1)
    c = c + 1
  c
-> total_bits(us, vs, ws, rank) (i64[] i64[] i64[] i64) i64
  tb = 0 ## i64
  k = 0 ## i64
  while k < rank
    tb = tb + pc(us[k]) + pc(vs[k]) + pc(ws[k])
    k += 1
  tb
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
        o = {CB}
      o += 1
    trial += 1
  ok

us = i64[{arr}]
vs = i64[{arr}]
ws = i64[{arr}]
bus = i64[{arr}]
bvs = i64[{arr}]
bws = i64[{arr}]
rank = 0 ## i64
{seed_lines}
rank = {seed_rank}
<< "seed rank=" + rank.to_s() + " bits=" + total_bits(us, vs, ws, rank).to_s() + " verify=" + verify(us, vs, ws, rank, 7).to_s()
flush()

base = 1
dumpfile = ""
av0 = argv()
if av0.size() > 0
  base = av0[0].to_i()
if av0.size() > 1
  dumpfile = av0[1]
rng = base * 1009 + 12345 ## i64

bits = total_bits(us, vs, ws, rank) ## i64
best_rank = rank ## i64
best_bits = bits ## i64
bi = 0
while bi < rank
  bus[bi] = us[bi]
  bvs[bi] = vs[bi]
  bws[bi] = ws[bi]
  bi += 1

slackv = 0 ## i64
mv = 0 ## i64
while mv < {cap}
  rng = (rng * 1103515245 + 12345) & 2147483647
  ti = (rng * rank) >> 31 ## i64
  rng = (rng * 1103515245 + 12345) & 2147483647
  axis = (((rng >> 22) & 511) * 3) >> 9 ## i64
  ui = us[ti] ## i64
  vi = vs[ti] ## i64
  wi = ws[ti] ## i64
  rng = (rng * 1103515245 + 12345) & 2147483647
  start = (rng * rank) >> 31 ## i64
  partner = 0 - 1 ## i64
  scan = 0 ## i64
  while scan < rank
    k = start + scan ## i64
    if k >= rank
      k = k - rank
    if k != ti
      hit = 0 ## i64
      if axis == 0
        if us[k] == ui
          hit = 1
      if axis == 1
        if vs[k] == vi
          hit = 1
      if axis == 2
        if ws[k] == wi
          hit = 1
      if hit == 1
        partner = k
        scan = rank
    scan += 1
  if partner < 0
    # Flip-poor scheme (a flip-isolated vertex has no partners at all —
    # our 4x4-47 is one): structured plus-escape. Split ti's w on another
    # term's w so the two new terms are flippable; rank rises by 1 and the
    # band snap-back below pulls the walk home if it doesn't pay off.
    rng = (rng * 1103515245 + 12345) & 2147483647
    pd = (rng * rank) >> 31 ## i64
    wpr = ws[pd] ## i64
    if pd != ti
      if wpr != wi
        rank = xor_insert(us, vs, ws, rank, ui, vi, wi)
        rank = xor_insert(us, vs, ws, rank, ui, vi, wpr)
        rank = xor_insert(us, vs, ws, rank, ui, vi, wi ^ wpr)
        bits = total_bits(us, vs, ws, rank)
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
    rankb = rank ## i64
    bitsb = bits ## i64
    rank = xor_insert(us, vs, ws, rank, ui, vi, wi)
    rank = xor_insert(us, vs, ws, rank, uj, vj, wj)
    rank = xor_insert(us, vs, ws, rank, au, av2, aw)
    rank = xor_insert(us, vs, ws, rank, bu, bv, bw)
    bits = total_bits(us, vs, ws, rank)
    acc = 0 ## i64
    if rank < rankb
      acc = 1
    if bits <= bitsb + slackv
      acc = 1
    if acc == 0
      rank = xor_insert(us, vs, ws, rank, ui, vi, wi)
      rank = xor_insert(us, vs, ws, rank, uj, vj, wj)
      rank = xor_insert(us, vs, ws, rank, au, av2, aw)
      rank = xor_insert(us, vs, ws, rank, bu, bv, bw)
      bits = bitsb
  improved = 0 ## i64
  if rank < best_rank
    improved = 1
  if rank == best_rank
    if bits < best_bits
      improved = 1
  if improved == 1
    best_rank = rank
    best_bits = bits
    ci = 0
    while ci < rank
      bus[ci] = us[ci]
      bvs[ci] = vs[ci]
      bws[ci] = ws[ci]
      ci += 1
    << "IMP rank=" + rank.to_s() + " bits=" + bits.to_s() + " mv=" + mv.to_s() + " v=" + verify(us, vs, ws, rank, 7).to_s()
    flush()
    if dumpfile.size() > 0
      dumpbody = rank.to_s() + "\\n"
      di = 0
      while di < rank
        dumpbody = dumpbody + bus[di].to_s() + " " + bvs[di].to_s() + " " + bws[di].to_s() + "\\n"
        di += 1
      write_file(dumpfile, dumpbody)
  snap = 0 ## i64
  if bits > best_bits + {band}
    snap = 1
  if rank > best_rank + 3
    snap = 1
  if snap == 1
    ri = 0
    while ri < best_rank
      us[ri] = bus[ri]
      vs[ri] = bvs[ri]
      ws[ri] = bws[ri]
      ri += 1
    rank = best_rank
    bits = best_bits
  slackv = {slack} - ((mv / {slackper}) % {slackspan}) ## i64
  if (mv % 20000000) == 0
    << "  mv=" + mv.to_s() + " best_bits=" + best_bits.to_s() + " cur_bits=" + bits.to_s() + " rank=" + rank.to_s() + " v=" + verify(us, vs, ws, rank, 7).to_s()
    flush()
  mv += 1

<< "DONE best=" + best_rank.to_s() + " bits=" + best_bits.to_s() + " verify=" + verify(bus, bvs, bws, best_rank, 31).to_s()
di = 0
while di < best_rank
  << "R " + bus[di].to_s() + " " + bvs[di].to_s() + " " + bws[di].to_s()
  di += 1
'''


if __name__ == "__main__":
    n, m, p, seedfile = int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
    cap = int(sys.argv[5]) if len(sys.argv) > 5 else 300000000
    slack = int(sys.argv[6]) if len(sys.argv) > 6 else 2
    slackper = int(sys.argv[7]) if len(sys.argv) > 7 else 200000
    band = int(sys.argv[8]) if len(sys.argv) > 8 else 30
    sys.stdout.write(gen(n, m, p, seedfile, cap=cap, slack=slack, slackper=slackper, band=band))
