# DETOUR applied to matrix multiplication, over GF(2).
#
# DETOUR idea: let arrival-ORDER certify optimality with no separate cost
# computation. Lifted to algorithm space: expand bilinear matmul schemes in
# COST order (number of multiplications); the first CORRECT scheme reached at
# rank r is minimal-by-arrival -- the wavefront swept everything cheaper and
# nothing correct finished. For the FIND that means "discover a 7-mult scheme";
# for the exhaustion that means "rank 6 finds nothing => 7 is optimal" (the
# Winograd lower bound), certified by arrival.
#
# A scheme = a set of rank-1 terms (u,v,w), each a 4-bit mask over the 4 entries
# of A (u), B (v), C (w). Term (u,v,w) puts product (XOR a_i:u_i) * (XOR b_j:v_j)
# into every output m with w_m=1. Over GF(2) the 2x2 matmul tensor T is fixed;
# a scheme is correct iff XOR of term-supports == T.
#
# The 64 coords (m,i,j) are stored as an i64[64] array of 0/1 -- NOT packed into
# one i64 -- to keep every value small/non-negative and avoid the compiled
# codegen bugs around bit-63 and i64-returning shift helpers. Run compiled:
#   bin/tungsten -o /tmp/detour benchmarks/matmul/detour_strassen.w && /tmp/detour

# XOR rank-1 term (u,v,w)'s support into the 64-slot tensor `out` (in place).
-> add_term(out, u, v, w) (i64[] i64 i64 i64)
  m = 0
  while m < 4
    wm = (w >> m) & 1
    i = 0
    while i < 4
      ui = (u >> i) & 1
      j = 0
      while j < 4
        vj = (v >> j) & 1
        idx = m * 16 + i * 4 + j
        out[idx] = out[idx] ^ (wm & ui & vj)
        j += 1
      i += 1
    m += 1

# True (1) iff tensors a and b (i64[64]) are equal.
-> tensors_equal(a, b) (i64[] i64[])
  eq = 1
  c = 0
  while c < 64
    if a[c] != b[c]
      eq = 0
    c += 1
  eq

# Cost-ordered wavefront. residual is mutated in place (XOR in / XOR out around
# the recursion). Returns the term-count of a found scheme (filling `chosen`),
# or -1 if none with <= depth_left more terms. Branches only over candidates
# covering the lowest still-nonzero coordinate.
-> solve(residual, depth_left, sup, used, chosen, base) (i64[] i64 i64[] i64[] i64[] i64)
  result = -1
  nz = -1
  c = 0
  while c < 64 and nz < 0
    if residual[c] != 0
      nz = c
    c += 1
  if nz < 0
    result = base
  if nz >= 0 and depth_left > 0
    t = 0
    while t < 3375 and result < 0
      cover = sup[t * 64 + nz]
      if cover == 1 and used[t] == 0
        used[t] = 1
        chosen[base] = t
        c2 = 0
        while c2 < 64
          residual[c2] = residual[c2] ^ sup[t * 64 + c2]
          c2 += 1
        r = solve(residual, depth_left - 1, sup, used, chosen, base + 1)
        c2 = 0
        while c2 < 64
          residual[c2] = residual[c2] ^ sup[t * 64 + c2]
          c2 += 1
        if r >= 0
          result = r
        used[t] = 0
      t += 1
  result

# ----- Build the matmul tensor T (i64[64]) -----
target = i64[64]
c = 0
while c < 64
  target[c] = 0
  c += 1
r = 0
while r < 2
  cc = 0
  while cc < 2
    k = 0
    while k < 2
      target[(r * 2 + cc) * 16 + (r * 2 + k) * 4 + (k * 2 + cc)] = 1
      k += 1
    cc += 1
  r += 1

# ----- Verify the two known schemes -----
chk = i64[64]
c = 0
while c < 64
  chk[c] = 0
  c += 1
add_term(chk, 1, 1, 1)
add_term(chk, 2, 4, 1)
add_term(chk, 1, 2, 2)
add_term(chk, 2, 8, 2)
add_term(chk, 4, 1, 4)
add_term(chk, 8, 4, 4)
add_term(chk, 4, 2, 8)
add_term(chk, 8, 8, 8)
<< "naive(8)     correct? " + tensors_equal(chk, target).to_s()

c = 0
while c < 64
  chk[c] = 0
  c += 1
add_term(chk, 9, 9, 9)
add_term(chk, 12, 1, 12)
add_term(chk, 1, 10, 10)
add_term(chk, 8, 5, 5)
add_term(chk, 3, 8, 3)
add_term(chk, 5, 3, 8)
add_term(chk, 10, 12, 1)
<< "strassen(7)  correct? " + tensors_equal(chk, target).to_s()

# ----- Build the 3375 candidate rank-1 terms + their 64-slot supports -----
cu = i64[3375]
cv = i64[3375]
cw = i64[3375]
sup = i64[3375 * 64]
t = 0
uu = 1
while uu < 16
  vv = 1
  while vv < 16
    ww = 1
    while ww < 16
      cu[t] = uu
      cv[t] = vv
      cw[t] = ww
      m = 0
      while m < 4
        wm = (ww >> m) & 1
        i = 0
        while i < 4
          ui = (uu >> i) & 1
          j = 0
          while j < 4
            vj = (vv >> j) & 1
            # store an explicit literal (raw); a bare `&`-expression store gets
            # NaN-box-tagged by the compiler (sup[0] came back 0xFFFA..01).
            slot = 0
            if (wm & ui & vj) == 1
              slot = 1
            sup[t * 64 + m * 16 + i * 4 + j] = slot
            j += 1
          i += 1
        m += 1
      t += 1
      ww += 1
    vv += 1
  uu += 1

used = i64[3375]
zi = 0
while zi < 3375
  used[zi] = 0
  zi += 1
chosen = i64[8]
zj = 0
while zj < 8
  chosen[zj] = 0
  zj += 1
residual = i64[64]
c = 0
while c < 64
  residual[c] = target[c]
  c += 1

<< ""
<< "DETOUR wavefront -- find a correct scheme within a multiplication ceiling:"
c = 0
while c < 64
  residual[c] = target[c]
  c += 1
zk = 0
while zk < 3375
  used[zk] = 0
  zk += 1
got = solve(residual, 8, sup, used, chosen, 0)
<< "  ceiling 8 mults  ->  discovered a " + got.to_s() + "-multiplication scheme from scratch:"
ci = 0
while ci < got
  ti = chosen[ci]
  << "      M" + (ci + 1).to_s() + ":  (a-combo " + cu[ti].to_s() + ", b-combo " + cv[ti].to_s() + ")  ->  outputs " + cw[ti].to_s()
  ci += 1
<< ""
<< "Lowering the ceiling to 7 (discover Strassen) or sweeping rank 6 empty (the"
<< "Winograd lower bound) is the SAME astronomically-large-but-finite GF(2) shell:"
<< "brute DFS does not finish. That hard half is exactly why AlphaTensor used RL,"
<< "not exhaustive search -- the DETOUR by-arrival certificate exists but is costly."
