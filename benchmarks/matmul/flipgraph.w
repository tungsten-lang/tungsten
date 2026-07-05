# Parameterized GF(2) flip-graph search for the rank of the <N,N,N> matmul
# tensor. Validated at N=3 (reaches Laderman's 23). For N=4: naive=64,
# Strassen^2=49, AlphaTensor(GF2)=47 -- below 47 would be a genuine improvement.
#
# A scheme = `rank` terms (us[t],vs[t],ws[t]), each factor a DIM-bit mask over
# the NxN entries (entry (r,c) -> bit r*N+c). Flips (compound XOR-stores, the
# codegen-raw-safe form) preserve the matmul tensor; reductions (zero factor ->
# rank-1, duplicate pair -> rank-2) lower rank. Correctness is invariant by
# construction; verify() spot-checks on random GF(2) matrices anyway.

N = 4
DIM = 16
VMOD = 65536

# Parity of bits of `vec` selected by `mask`, over `dim` bits (0/1).
-> parity(mask, vec, dim) (i64 i64 i64)
  p = 0
  b = 0
  while b < dim
    if ((mask >> b) & 1) == 1
      if ((vec >> b) & 1) == 1
        p = (p + 1) % 2
    b += 1
  p

# 1 iff (us,vs,ws,rank) computes NxN matmul on 30 random GF(2) inputs.
-> verify(us, vs, ws, rank, seed0, n, dim, vmod) (i64[] i64[] i64[] i64 i64 i64 i64 i64)
  ok = 1
  s = seed0
  trial = 0
  while trial < 30
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

# Remove zero-factor terms (rank-1) and duplicate pairs (rank-2). New rank.
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

# Fill us/vs/ws with the naive N^3-term scheme; returns N^3.
-> init_naive(us, vs, ws, p2, n) (i64[] i64[] i64[] i64[] i64)
  r = 0
  i = 0
  while i < n
    j = 0
    while j < n
      k = 0
      while k < n
        us[r] = p2[i * n + k]
        vs[r] = p2[k * n + j]
        ws[r] = p2[i * n + j]
        r += 1
        k += 1
      j += 1
    i += 1
  r

p2 = i64[DIM]
p2[0] = 1
kk = 1
while kk < DIM
  p2[kk] = p2[kk - 1] + p2[kk - 1]
  kk += 1

CAP = 96
us = i64[CAP]
vs = i64[CAP]
ws = i64[CAP]
rank = init_naive(us, vs, ws, p2, N)
<< "start: <" + N.to_s() + "," + N.to_s() + "," + N.to_s() + "> naive rank = " + rank.to_s() + "   verify = " + verify(us, vs, ws, rank, 999, N, DIM, VMOD).to_s()

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
nstuck = 0
while step < 300000000
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
  if since > 120000
    nstuck += 1
    if nstuck % 16 == 0
      rank = init_naive(us, vs, ws, p2, N)
    if nstuck % 16 != 0
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
<< "DONE.  <" + N.to_s() + "> best rank = " + best.to_s() + "   final verify = " + verify(bus, bvs, bws, best, 555, N, DIM, VMOD).to_s()
