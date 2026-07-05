# GF(2) flip-graph search for the rank of the <3,3,3> matrix-multiplication
# tensor.  A scheme is `rank` rank-1 terms (us[t], vs[t], ws[t]), each factor a
# 9-bit mask over the 3x3 entries (entry (row,col) -> bit row*3+col).  The naive
# scheme has 27 terms; best known is 23 (Laderman 1976), lower bound 19.
#
# Flip (Kauers-Moosbauer), GF(2): for two terms sharing one factor,
#   b(x)c + b'(x)c' = b(x)(c+c') + (b+b')(x)c'   (cross term cancels mod 2),
# which preserves the sum (= the matmul tensor) -- so correctness is invariant
# and we only watch for a factor going to 0 (rank-1) or two terms coinciding
# (rank-2).  All flips are compound XOR-stores `ws[i] = ws[i] ^ ws[j]` (the
# codegen-raw-safe form); verification uses only inline bit-compares + arithmetic.

# Parity of the bits of `vec` selected by `mask`, over 9 bits (returns 0/1).
-> parity(mask, vec) (i64 i64)
  p = 0
  b = 0
  while b < 9
    if ((mask >> b) & 1) == 1
      if ((vec >> b) & 1) == 1
        p = (p + 1) % 2
    b += 1
  p

# 1 iff scheme (us,vs,ws,rank) computes 3x3 matmul on `trials` random GF(2) inputs.
-> verify(us, vs, ws, rank, seed0) (i64[] i64[] i64[] i64 i64)
  ok = 1
  s = seed0
  trial = 0
  while trial < 30
    s = (s * 1103515245 + 12345) % 2147483648
    av = s % 512
    s = (s * 1103515245 + 12345) % 2147483648
    bv = s % 512
    o = 0
    while o < 9
      cs = 0
      t = 0
      while t < rank
        if ((ws[t] >> o) & 1) == 1
          la = parity(us[t], av)
          lb = parity(vs[t], bv)
          if la == 1
            if lb == 1
              cs = (cs + 1) % 2
        t += 1
      oi = o / 3
      oj = o % 3
      ct = 0
      k = 0
      while k < 3
        if ((av >> (oi * 3 + k)) & 1) == 1
          if ((bv >> (k * 3 + oj)) & 1) == 1
            ct = (ct + 1) % 2
        k += 1
      if cs != ct
        ok = 0
      o += 1
    trial += 1
  ok

# Remove zero-factor terms (rank-1 each) and duplicate pairs (rank-2, cancel mod
# 2). Returns the new rank. All array-element moves -- codegen-raw-safe.
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

# (Re)fill us/vs/ws with the naive 27-term <3,3,3> scheme; returns 27.
-> init_naive(us, vs, ws, p2) (i64[] i64[] i64[] i64[])
  r = 0
  i = 0
  while i < 3
    j = 0
    while j < 3
      k = 0
      while k < 3
        us[r] = p2[i * 3 + k]
        vs[r] = p2[k * 3 + j]
        ws[r] = p2[i * 3 + j]
        r += 1
        k += 1
      j += 1
    i += 1
  r

# pow2 (onehot bit values) by doubling -- no shift-store.
p2 = i64[9]
p2[0] = 1
kk = 1
while kk < 9
  p2[kk] = p2[kk - 1] + p2[kk - 1]
  kk += 1

CAP = 64
us = i64[CAP]
vs = i64[CAP]
ws = i64[CAP]

# naive 27-term <3,3,3>:  term (i,j,k) = (A[i][k], B[k][j], C[i][j])
rank = 0
i = 0
while i < 3
  j = 0
  while j < 3
    k = 0
    while k < 3
      us[rank] = p2[i * 3 + k]
      vs[rank] = p2[k * 3 + j]
      ws[rank] = p2[i * 3 + j]
      rank += 1
      k += 1
    j += 1
  i += 1

<< "start: naive rank = " + rank.to_s() + "   verify = " + verify(us, vs, ws, rank, 999).to_s()

# best-so-far scheme
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

# flip-graph random walk
state = 12345
step = 0
since = 0
nstuck = 0
while step < 40000000
  state = (state * 1103515245 + 12345) % 2147483648
  fi = state % rank
  state = (state * 1103515245 + 12345) % 2147483648
  axis = state % 3
  state = (state * 1103515245 + 12345) % 2147483648
  off = state % rank
  # find a partner term sharing the chosen axis-factor with term fi
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
    << "  new best rank = " + best.to_s() + "   verify = " + verify(us, vs, ws, rank, 777).to_s() + "   step " + step.to_s()
    since = 0
  if rank >= best
    since += 1
  if since > 50000
    nstuck += 1
    if nstuck % 20 == 0
      rank = init_naive(us, vs, ws, p2)
    if nstuck % 20 != 0
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
<< "DONE.  best rank = " + best.to_s() + "   final verify = " + verify(bus, bvs, bws, best, 555).to_s() + "   (best known 23, lower bound 19)"
