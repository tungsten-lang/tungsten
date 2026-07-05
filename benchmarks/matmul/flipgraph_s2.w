# GF(2) flip-graph for <4,4,4>, SEEDED FROM STRASSEN^2 (49 terms) instead of the
# naive 64 -- so the walk only needs to find a reduction or two to reach 48/47
# (AlphaTensor's GF(2) record) or below (a genuine improvement).
#
# Strassen^2 = the tensor product of two copies of the 2x2 Strassen scheme:
# term (s,t) interleaves block-mask s and scalar-mask t into one 16-bit mask --
# 4x4 entry (2*BR+arp, 2*BC+acp) selected iff block-mask has bit BR*2+BC AND
# scalar-mask has bit arp*2+acp.

N = 4
DIM = 16
VMOD = 65536

-> parity(mask, vec, dim) (i64 i64 i64)
  p = 0
  b = 0
  while b < dim
    if ((mask >> b) & 1) == 1
      if ((vec >> b) & 1) == 1
        p = (p + 1) % 2
    b += 1
  p

-> verify(us, vs, ws, rank, seed0, n, dim, vmod) (i64[] i64[] i64[] i64 i64 i64 i64 i64)
  ok = 1
  s = seed0
  trial = 0
  while trial < 40
    s = (s * 1103515245 + 12345) % 2147483648
    av = s % vmod
    s = (s * 1103515245 + 12345) % 2147483648
    bv = s % vmod
    o = 0
    while o < dim
      cs = 0
      t = 0
      while t < rank
        if ((ws[t] >> o) & 1) == 1
          la = parity(us[t], av, dim)
          lb = parity(vs[t], bv, dim)
          if la == 1
            if lb == 1
              cs = (cs + 1) % 2
        t += 1
      oi = o / n
      oj = o % n
      ct = 0
      k = 0
      while k < n
        if ((av >> (oi * n + k)) & 1) == 1
          if ((bv >> (k * n + oj)) & 1) == 1
            ct = (ct + 1) % 2
        k += 1
      if cs != ct
        ok = 0
      o += 1
    trial += 1
  ok

-> reduce(us, vs, ws, rank) (i64[] i64[] i64[] i64)
  r = rank
  t = 0
  while t < r
    z = 0
    if us[t] == 0
      z = 1
    if vs[t] == 0
      z = 1
    if ws[t] == 0
      z = 1
    if z == 1
      us[t] = us[r - 1]
      vs[t] = vs[r - 1]
      ws[t] = ws[r - 1]
      r -= 1
    if z == 0
      t += 1
  a = 0
  while a < r
    dup = -1
    bb = a + 1
    while bb < r and dup < 0
      if us[a] == us[bb]
        if vs[a] == vs[bb]
          if ws[a] == ws[bb]
            dup = bb
      bb += 1
    if dup >= 0
      us[dup] = us[r - 1]
      vs[dup] = vs[r - 1]
      ws[dup] = ws[r - 1]
      r -= 1
      us[a] = us[r - 1]
      vs[a] = vs[r - 1]
      ws[a] = ws[r - 1]
      r -= 1
    if dup < 0
      a += 1
  r

p2 = i64[DIM]
p2[0] = 1
kk = 1
while kk < DIM
  p2[kk] = p2[kk - 1] + p2[kk - 1]
  kk += 1

# 2x2 Strassen masks (4-bit, over row*2+col indexing), verified earlier.
su = i64[7]
sv = i64[7]
sw = i64[7]
su[0] = 9
su[1] = 12
su[2] = 1
su[3] = 8
su[4] = 3
su[5] = 5
su[6] = 10
sv[0] = 9
sv[1] = 1
sv[2] = 10
sv[3] = 5
sv[4] = 8
sv[5] = 3
sv[6] = 12
sw[0] = 9
sw[1] = 12
sw[2] = 10
sw[3] = 5
sw[4] = 3
sw[5] = 8
sw[6] = 1

CAP = 96
us = i64[CAP]
vs = i64[CAP]
ws = i64[CAP]

# Build the 49-term Strassen^2 scheme.
rank = 0
s = 0
while s < 7
  t = 0
  while t < 7
    us[rank] = 0
    vs[rank] = 0
    ws[rank] = 0
    blk = 0
    while blk < 4
      scl = 0
      while scl < 4
        idx = (2 * (blk / 2) + scl / 2) * 4 + (2 * (blk % 2) + scl % 2)
        if ((su[s] >> blk) & 1) == 1
          if ((su[t] >> scl) & 1) == 1
            us[rank] = us[rank] ^ p2[idx]
        if ((sv[s] >> blk) & 1) == 1
          if ((sv[t] >> scl) & 1) == 1
            vs[rank] = vs[rank] ^ p2[idx]
        if ((sw[s] >> blk) & 1) == 1
          if ((sw[t] >> scl) & 1) == 1
            ws[rank] = ws[rank] ^ p2[idx]
        scl += 1
      blk += 1
    rank += 1
    t += 1
  s += 1

<< "start: Strassen^2 rank = " + rank.to_s() + "   verify = " + verify(us, vs, ws, rank, 999, N, DIM, VMOD).to_s() + "   (expect 49, 1)"

bus = i64[CAP]
bvs = i64[CAP]
bws = i64[CAP]
best = rank
ci = 0
while ci < rank
  bus[ci] = us[ci]
  bvs[ci] = vs[ci]
  bws[ci] = ws[ci]
  ci += 1

state = 12345
step = 0
since = 0
while step < 400000000
  state = (state * 1103515245 + 12345) % 2147483648
  roll = state % 6
  didplus = 0
  # PLUS move (escape local minima): split a term, rank+1, sum preserved.
  if roll == 0
    if rank < best + 4
      if rank < 90
        state = (state * 1103515245 + 12345) % 2147483648
        pt = state % rank
        state = (state * 1103515245 + 12345) % 2147483648
        u1 = (state % 65535) + 1
        if u1 != us[pt]
          us[rank] = us[pt] ^ u1
          vs[rank] = vs[pt]
          ws[rank] = ws[pt]
          us[pt] = u1
          rank += 1
          didplus = 1
  if didplus == 0
    state = (state * 1103515245 + 12345) % 2147483648
    fi = state % rank
    state = (state * 1103515245 + 12345) % 2147483648
    axis = state % 3
    state = (state * 1103515245 + 12345) % 2147483648
    off = state % rank
    fj = -1
    scan = 0
    while scan < rank and fj < 0
      cand = (off + scan) % rank
      if cand != fi
        if axis == 0 and us[cand] == us[fi]
          fj = cand
        if axis == 1 and vs[cand] == vs[fi]
          fj = cand
        if axis == 2 and ws[cand] == ws[fi]
          fj = cand
      scan += 1
    if fj >= 0
      if axis == 0
        ws[fi] = ws[fi] ^ ws[fj]
        vs[fj] = vs[fi] ^ vs[fj]
      if axis == 1
        ws[fi] = ws[fi] ^ ws[fj]
        us[fj] = us[fi] ^ us[fj]
      if axis == 2
        vs[fi] = vs[fi] ^ vs[fj]
        us[fj] = us[fi] ^ us[fj]
  rank = reduce(us, vs, ws, rank)
  if rank < best
    best = rank
    ci = 0
    while ci < rank
      bus[ci] = us[ci]
      bvs[ci] = vs[ci]
      bws[ci] = ws[ci]
      ci += 1
    << "  new best rank = " + best.to_s() + "   verify = " + verify(us, vs, ws, rank, 777, N, DIM, VMOD).to_s() + "   step " + step.to_s()
    since = 0
  if rank >= best
    since += 1
  if since > 600000
    ci = 0
    while ci < best
      us[ci] = bus[ci]
      vs[ci] = bvs[ci]
      ws[ci] = bws[ci]
      ci += 1
    rank = best
    since = 0
  step += 1

<< ""
<< "DONE.  <4> best rank = " + best.to_s() + "   final verify = " + verify(bus, bvs, bws, best, 555, N, DIM, VMOD).to_s() + "   (Strassen^2 49, AlphaTensor 47)"
