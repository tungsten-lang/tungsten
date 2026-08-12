# Native Tungsten big-integer limb kernels over u64[] arrays — the "can the
# bignum leaf tier move from C to .w?" prototype (2026-07-31, Apple M5 Max).
#
# Kernels: wn_add_nn / wn_sub_nn / wn_cmp_nn / wn_shl / wn_shr / wn_mul_1 /
# wn_addmul_1 (+ 4x/8x manually-unrolled variants) / wn_basecase / wn_kara,
# all offset-addressed, validated in-program against the BigInt oracle
# (sizes 1..80 x 5 fill patterns) AND cross-checked against the hand-asm
# asm_add_no / asm_addmul1 / asm_mulbase intrinsics.
#
# What makes these compile to tight loops (each was verified in the .ll):
#   * typed native sigs — `-> f(a, n) (u64[] i64) i64`, SPACE-separated type
#     list. Without them array params fall back to per-element runtime calls
#     (w_index_raw_u64) and run ~13x slower.
#   * every element read annotated `x = a[i] ## u64`; every shift/compare
#     operand bound with `## u64` (an untyped-literal op can demote and turn
#     lshr into ashr).
#   * addcarry/subborrow/mulhi intrinsics for the carry chains; loops that
#     contain them get `llvm.loop.unroll.count 8` latch metadata by default.
#     Set TUNGSTEN_CARRY_UNROLL=0..64 to disable or tune the count.
#   * impure helpers are `->` methods, NEVER `fn`: arity<=2 `fn` defs are
#     auto-memoized keyed on WValue identity, which returns stale results for
#     array-mutating helpers (rng!) and skips timed work.
#   * asm_* builtin returns are :raw_i64 — rebind `## u64` before adding to a
#     u64 accumulator or the add falls into boxed runtime arithmetic.
#
# COMPILE-ONLY (mulhi/addcarry/subborrow/asm_* have no interpreter support):
#   bin/tungsten -o /tmp/wn_limb benchmarks/limb_native/wn_limb.w
# Run:  /tmp/wn_limb          -> BigInt-oracle self-check only
#       /tmp/wn_limb bench    -> self-check, then kernel benchmark
#       (lanes: native .w / manual-unroll / asm_* intrinsic / BigInt op)

# ── kernels ──────────────────────────────────────────────────────────

# r[ro..ro+n) = a[ao..) + b[bo..); returns carry-out (0/1) as raw.
-> wn_add_nn(r, roff, a, aoff, b, boff, n) (u64[] i64 u64[] i64 u64[] i64 i64) i64
  ra = roff ## i64
  ab = aoff ## i64
  bb = boff ## i64
  nn = n ## i64
  carry = 0 ## u64
  i = 0 ## i64
  while i < nn
    x = a[ab + i] ## u64
    y = b[bb + i] ## u64
    s1 = x + carry
    c1 = addcarry(x, carry)
    s2 = s1 + y
    c2 = addcarry(s1, y)
    r[ra + i] = s2
    carry = c1 + c2
    i += 1
  carry

# 4x-unrolled add_n.
-> wn_add_nn_u4(r, roff, a, aoff, b, boff, n) (u64[] i64 u64[] i64 u64[] i64 i64) i64
  ra = roff ## i64
  ab = aoff ## i64
  bb = boff ## i64
  nn = n ## i64
  carry = 0 ## u64
  i = 0 ## i64
  while i + 4 <= nn
    x = a[ab + i] ## u64
    y = b[bb + i] ## u64
    s1 = x + carry
    c1 = addcarry(x, carry)
    s2 = s1 + y
    c2 = addcarry(s1, y)
    r[ra + i] = s2
    carry = c1 + c2
    x = a[ab + i + 1] ## u64
    y = b[bb + i + 1] ## u64
    s1 = x + carry
    c1 = addcarry(x, carry)
    s2 = s1 + y
    c2 = addcarry(s1, y)
    r[ra + i + 1] = s2
    carry = c1 + c2
    x = a[ab + i + 2] ## u64
    y = b[bb + i + 2] ## u64
    s1 = x + carry
    c1 = addcarry(x, carry)
    s2 = s1 + y
    c2 = addcarry(s1, y)
    r[ra + i + 2] = s2
    carry = c1 + c2
    x = a[ab + i + 3] ## u64
    y = b[bb + i + 3] ## u64
    s1 = x + carry
    c1 = addcarry(x, carry)
    s2 = s1 + y
    c2 = addcarry(s1, y)
    r[ra + i + 3] = s2
    carry = c1 + c2
    i += 4
  while i < nn
    x = a[ab + i] ## u64
    y = b[bb + i] ## u64
    s1 = x + carry
    c1 = addcarry(x, carry)
    s2 = s1 + y
    c2 = addcarry(s1, y)
    r[ra + i] = s2
    carry = c1 + c2
    i += 1
  carry

# 8x-unrolled add_n.
-> wn_add_nn_u8(r, roff, a, aoff, b, boff, n) (u64[] i64 u64[] i64 u64[] i64 i64) i64
  ra = roff ## i64
  ab = aoff ## i64
  bb = boff ## i64
  nn = n ## i64
  carry = 0 ## u64
  i = 0 ## i64
  while i + 8 <= nn
    k = 0 ## i64
    while k < 8
      x = a[ab + i + k] ## u64
      y = b[bb + i + k] ## u64
      s1 = x + carry
      c1 = addcarry(x, carry)
      s2 = s1 + y
      c2 = addcarry(s1, y)
      r[ra + i + k] = s2
      carry = c1 + c2
      k += 1
    i += 8
  while i < nn
    x = a[ab + i] ## u64
    y = b[bb + i] ## u64
    s1 = x + carry
    c1 = addcarry(x, carry)
    s2 = s1 + y
    c2 = addcarry(s1, y)
    r[ra + i] = s2
    carry = c1 + c2
    i += 1
  carry

# r[ro..ro+n) = a[ao..) - b[bo..); returns borrow-out (0/1).
-> wn_sub_nn(r, roff, a, aoff, b, boff, n) (u64[] i64 u64[] i64 u64[] i64 i64) i64
  ra = roff ## i64
  ab = aoff ## i64
  bb = boff ## i64
  nn = n ## i64
  borrow = 0 ## u64
  i = 0 ## i64
  while i < nn
    x = a[ab + i] ## u64
    y = b[bb + i] ## u64
    d1 = x - borrow
    e1 = subborrow(x, borrow)
    d2 = d1 - y
    e2 = subborrow(d1, y)
    r[ra + i] = d2
    borrow = e1 + e2
    i += 1
  borrow

# Compare n-limb numbers: -1 / 0 / 1.
-> wn_cmp_nn(a, aoff, b, boff, n) (u64[] i64 u64[] i64 i64) i64
  ab = aoff ## i64
  bb = boff ## i64
  nn = n ## i64
  i = nn - 1
  while i >= 0
    x = a[ab + i] ## u64
    y = b[bb + i] ## u64
    if x < y
      return 0 - 1
    if x > y
      return 1
    i -= 1
  0

# Left shift by k (1..63): r[ro..ro+n) = a[ao..) << k, returns spilled high bits.
# Runs high->low so r may alias a.
-> wn_shl(r, roff, a, aoff, n, k) (u64[] i64 u64[] i64 i64 i64) i64
  ra = roff ## i64
  ab = aoff ## i64
  nn = n ## i64
  kk = k ## i64
  jk = 64 - kk
  top = a[ab + nn - 1] ## u64
  out = top >> jk
  i = nn - 1
  while i > 0
    x = a[ab + i] ## u64
    y = a[ab + i - 1] ## u64
    r[ra + i] = (x << kk) | (y >> jk)
    i -= 1
  z = a[ab] ## u64
  r[ra] = z << kk
  out

# Right shift by k (1..63): returns the dropped low bits of a[ao].
# Runs low->high so r may alias a.
-> wn_shr(r, roff, a, aoff, n, k) (u64[] i64 u64[] i64 i64 i64) i64
  ra = roff ## i64
  ab = aoff ## i64
  nn = n ## i64
  kk = k ## i64
  jk = 64 - kk
  ones = 0 ## u64
  ones = ones - 1
  mask = ones >> jk
  low = a[ab] ## u64
  out = low & mask
  i = 0 ## i64
  while i < nn - 1
    x = a[ab + i] ## u64
    y = a[ab + i + 1] ## u64
    r[ra + i] = (x >> kk) | (y << jk)
    i += 1
  z = a[ab + nn - 1] ## u64
  r[ra + nn - 1] = z >> kk
  out

# Propagate a small scalar add through r[ro..ro+n); returns final carry (0 expected).
-> wn_add_1(r, roff, n, v) (u64[] i64 i64 i64) i64
  ra = roff ## i64
  nn = n ## i64
  carry = v ## u64
  i = 0 ## i64
  while i < nn && carry != 0
    x = r[ra + i] ## u64
    s = x + carry
    c = addcarry(x, carry)
    r[ra + i] = s
    carry = c + 0
    i += 1
  carry

# r[ro..ro+n) = a[ao..) * v; returns high carry limb.
-> wn_mul_1(r, roff, a, aoff, n, v) (u64[] i64 u64[] i64 i64 u64) i64
  ra = roff ## i64
  ab = aoff ## i64
  nn = n ## i64
  vv = v ## u64
  carry = 0 ## u64
  i = 0 ## i64
  while i < nn
    x = a[ab + i] ## u64
    lo = x * vv
    hi = mulhi(x, vv)
    s = lo + carry
    c = addcarry(lo, carry)
    r[ra + i] = s
    carry = hi + c
    i += 1
  carry

# r[ro..ro+n) += a[ao..) * v; returns carry-out limb.
-> wn_addmul_1(r, roff, a, aoff, n, v) (u64[] i64 u64[] i64 i64 u64) i64
  ra = roff ## i64
  ab = aoff ## i64
  nn = n ## i64
  vv = v ## u64
  carry = 0 ## u64
  i = 0 ## i64
  while i < nn
    x = a[ab + i] ## u64
    t = r[ra + i] ## u64
    lo = x * vv
    hi = mulhi(x, vv)
    s1 = lo + t
    c1 = addcarry(lo, t)
    s2 = s1 + carry
    c2 = addcarry(s1, carry)
    r[ra + i] = s2
    carry = hi + c1 + c2
    i += 1
  carry

# 4x-unrolled addmul_1.
-> wn_addmul_1_u4(r, roff, a, aoff, n, v) (u64[] i64 u64[] i64 i64 u64) i64
  ra = roff ## i64
  ab = aoff ## i64
  nn = n ## i64
  vv = v ## u64
  carry = 0 ## u64
  i = 0 ## i64
  while i + 4 <= nn
    x = a[ab + i] ## u64
    t = r[ra + i] ## u64
    lo = x * vv
    hi = mulhi(x, vv)
    s1 = lo + t
    c1 = addcarry(lo, t)
    s2 = s1 + carry
    c2 = addcarry(s1, carry)
    r[ra + i] = s2
    carry = hi + c1 + c2
    x = a[ab + i + 1] ## u64
    t = r[ra + i + 1] ## u64
    lo = x * vv
    hi = mulhi(x, vv)
    s1 = lo + t
    c1 = addcarry(lo, t)
    s2 = s1 + carry
    c2 = addcarry(s1, carry)
    r[ra + i + 1] = s2
    carry = hi + c1 + c2
    x = a[ab + i + 2] ## u64
    t = r[ra + i + 2] ## u64
    lo = x * vv
    hi = mulhi(x, vv)
    s1 = lo + t
    c1 = addcarry(lo, t)
    s2 = s1 + carry
    c2 = addcarry(s1, carry)
    r[ra + i + 2] = s2
    carry = hi + c1 + c2
    x = a[ab + i + 3] ## u64
    t = r[ra + i + 3] ## u64
    lo = x * vv
    hi = mulhi(x, vv)
    s1 = lo + t
    c1 = addcarry(lo, t)
    s2 = s1 + carry
    c2 = addcarry(s1, carry)
    r[ra + i + 3] = s2
    carry = hi + c1 + c2
    i += 4
  while i < nn
    x = a[ab + i] ## u64
    t = r[ra + i] ## u64
    lo = x * vv
    hi = mulhi(x, vv)
    s1 = lo + t
    c1 = addcarry(lo, t)
    s2 = s1 + carry
    c2 = addcarry(s1, carry)
    r[ra + i] = s2
    carry = hi + c1 + c2
    i += 1
  carry

# 8x-unrolled addmul_1 (inner fixed-count loop; LLVM fully unrolls it).
-> wn_addmul_1_u8(r, roff, a, aoff, n, v) (u64[] i64 u64[] i64 i64 u64) i64
  ra = roff ## i64
  ab = aoff ## i64
  nn = n ## i64
  vv = v ## u64
  carry = 0 ## u64
  i = 0 ## i64
  while i + 8 <= nn
    k = 0 ## i64
    while k < 8
      x = a[ab + i + k] ## u64
      t = r[ra + i + k] ## u64
      lo = x * vv
      hi = mulhi(x, vv)
      s1 = lo + t
      c1 = addcarry(lo, t)
      s2 = s1 + carry
      c2 = addcarry(s1, carry)
      r[ra + i + k] = s2
      carry = hi + c1 + c2
      k += 1
    i += 8
  while i < nn
    x = a[ab + i] ## u64
    t = r[ra + i] ## u64
    lo = x * vv
    hi = mulhi(x, vv)
    s1 = lo + t
    c1 = addcarry(lo, t)
    s2 = s1 + carry
    c2 = addcarry(s1, carry)
    r[ra + i] = s2
    carry = hi + c1 + c2
    i += 1
  carry

# Schoolbook: r[ro..ro+na+nb) = a[ao..ao+na) * b[bo..bo+nb). r must not alias a/b.
-> wn_basecase(r, roff, a, aoff, na, b, boff, nb) (u64[] i64 u64[] i64 i64 u64[] i64 i64) i64
  ra = roff ## i64
  bb = boff ## i64
  la = na ## i64
  lb = nb ## i64
  v0 = b[bb] ## u64
  c0 = wn_mul_1(r, ra, a, aoff, la, v0)
  r[ra + la] = c0
  j = 1 ## i64
  while j < lb
    vj = b[bb + j] ## u64
    cj = wn_addmul_1(r, ra + j, a, aoff, la, vj)
    r[ra + j + la] = cj
    j += 1
  0

# Karatsuba for equal even sizes above the threshold; falls back to basecase.
# ws is scratch: needs ~6n limbs headroom at woff.
-> wn_kara(r, roff, a, aoff, b, boff, n, ws, woff) (u64[] i64 u64[] i64 u64[] i64 i64 u64[] i64) i64
  nn = n ## i64
  if nn <= 24 || (nn & 1) == 1
    wn_basecase(r, roff, a, aoff, nn, b, boff, nn)
    return 0
  ra = roff ## i64
  ab = aoff ## i64
  bb = boff ## i64
  wo = woff ## i64
  m = nn >> 1
  # z0 -> r[ra..ra+n), z2 -> r[ra+n..ra+2n)
  wn_kara(r, ra, a, ab, b, bb, m, ws, wo)
  wn_kara(r, ra + nn, a, ab + m, b, bb + m, m, ws, wo)
  # |a1-a0| -> ws[wo..wo+m), |b1-b0| -> ws[wo+m..wo+2m)
  sa = wn_cmp_nn(a, ab + m, a, ab, m)
  if sa >= 0
    wn_sub_nn(ws, wo, a, ab + m, a, ab, m)
  else
    wn_sub_nn(ws, wo, a, ab, a, ab + m, m)
  sb = wn_cmp_nn(b, bb + m, b, bb, m)
  if sb >= 0
    wn_sub_nn(ws, wo + m, b, bb + m, b, bb, m)
  else
    wn_sub_nn(ws, wo + m, b, bb, b, bb + m, m)
  # tm = |a1-a0|*|b1-b0| -> ws[wo+n..wo+2n), recursion scratch at wo+3n
  wn_kara(ws, wo + nn, ws, wo, ws, wo + m, m, ws, wo + 3 * nn)
  # mid = z0 + z2 -> ws[wo+2n..wo+3n)
  cm = 0 ## i64
  cadd = wn_add_nn(ws, wo + 2 * nn, r, ra, r, ra + nn, nn)
  cm = cm + cadd
  neg = 0 ## i64
  if sa >= 0
    neg = neg + 1
  if sb >= 0
    neg = neg + 1
  if neg == 1
    # (a1-a0)(b1-b0) < 0 -> mid += tm
    cadd2 = wn_add_nn(ws, wo + 2 * nn, ws, wo + 2 * nn, ws, wo + nn, nn)
    cm = cm + cadd2
  else
    csub = wn_sub_nn(ws, wo + 2 * nn, ws, wo + 2 * nn, ws, wo + nn, nn)
    cm = cm - csub
  # r[ra+m ..] += mid, then propagate cm
  c3 = wn_add_nn(r, ra + m, r, ra + m, ws, wo + 2 * nn, nn)
  wn_add_1(r, ra + m + nn, m, cm + c3)
  0

# ── helpers: BigInt oracle bridge ────────────────────────────────────

fn big_of_limbs(arr, off, n)
  ab = off ## i64
  nn = n ## i64
  bv = 0 ## big
  i = nn - 1
  while i >= 0
    x = arr[ab + i] ## u64
    hi = (x >> 32) ## u64
    lo = (x & 4294967295) ## u64
    bv = bv * 4294967296 + hi
    bv = bv * 4294967296 + lo
    i -= 1
  bv

fn big_pow2(k)
  kk = k ## i64
  p = 1 ## big
  i = 0 ## i64
  while i < kk
    p = p * 2
    i += 1
  p

-> big_of_u64(x)
  xx = x ## u64
  hi = (xx >> 32) ## u64
  lo = (xx & 4294967295) ## u64
  bv = 0 ## big
  bv = bv + hi
  bv = bv * 4294967296 + lo
  bv

# ── fills ────────────────────────────────────────────────────────────

-> rng_next(cell)
  x = cell[0] ## u64
  x = x ^ (x >> 12)
  x = x ^ (x << 25)
  x = x ^ (x >> 27)
  cell[0] = x
  m = 2685821657736338717 ## u64
  (x * m) ## u64

-> u64_alt
  x = 0 ## u64
  k = 0 ## i64
  while k < 32
    x = x * 4 + 2
    k += 1
  x

# pattern p: 0 random, 1 all-ones, 2 one-then-zeros, 3 alternating, 4 ones-minus-random-byte
fn wn_fill(arr, n, p, cell)
  nn = n ## i64
  pp = p ## i64
  ones = 0 ## u64
  ones = ones - 1
  alt = u64_alt() ## u64
  i = 0 ## i64
  while i < nn
    if pp == 0
      arr[i] = rng_next(cell)
    elsif pp == 1
      arr[i] = ones
    elsif pp == 2
      if i == 0
        arr[i] = 1
      else
        arr[i] = 0
    elsif pp == 3
      arr[i] = alt
    else
      rv = rng_next(cell) ## u64
      arr[i] = ones - (rv & 255)
    i += 1
  0

fn wn_copy(dst, doff, src, soff, n)
  d0 = doff ## i64
  s0 = soff ## i64
  nn = n ## i64
  i = 0 ## i64
  while i < nn
    dst[d0 + i] = src[s0 + i] ## u64
    i += 1
  0

fn limbs_equal(x, y, n)
  nn = n ## i64
  i = 0 ## i64
  while i < nn
    a1 = x[i] ## u64
    b1 = y[i] ## u64
    if a1 != b1
      return 0
    i += 1
  1

# ── self-check ───────────────────────────────────────────────────────

fn expect_eq(name, got, want, fails)
  gs = got.to_s()
  ws2 = want.to_s()
  if gs != ws2
    << "FAIL " + name + " got=" + gs + " want=" + ws2
    fails[0] = (fails[0] ## i64) + 1
  0

fn check_size(n, p, a, b, r, r2, ws, cell, fails)
  nn = n ## i64
  tag = " n=" + nn.to_s() + " p=" + p.to_s()
  wn_fill(a, nn, p, cell)
  if p == 2
    # carry-chain: a = ones, b = 1,0,0...
    wn_fill(a, nn, 1, cell)
    wn_fill(b, nn, 2, cell)
  else
    wn_fill(b, nn, p, cell)
    if p == 1
      wn_fill(b, nn, 0, cell)
  ba = big_of_limbs(a, 0, nn)
  bb2 = big_of_limbs(b, 0, nn)
  shiftn = big_pow2(64 * nn)

  # add (plain + unrolled + asm cross-check)
  c = wn_add_nn(r, 0, a, 0, b, 0, nn)
  got = big_of_limbs(r, 0, nn) + big_of_u64(c) * shiftn
  expect_eq("add" + tag, got, ba + bb2, fails)
  c4 = wn_add_nn_u4(r2, 0, a, 0, b, 0, nn)
  if limbs_equal(r, r2, nn) == 0 || (c4 ## i64) != (c ## i64)
    << "FAIL add_u4 mismatch" + tag
    fails[0] = (fails[0] ## i64) + 1
  c8 = wn_add_nn_u8(r2, 0, a, 0, b, 0, nn)
  if limbs_equal(r, r2, nn) == 0 || (c8 ## i64) != (c ## i64)
    << "FAIL add_u8 mismatch" + tag
    fails[0] = (fails[0] ## i64) + 1
  ca = asm_add_no(r2, 0, a, 0, b, 0, nn)
  if limbs_equal(r, r2, nn) == 0 || (ca ## i64) != (c ## i64)
    << "FAIL add_asm mismatch" + tag
    fails[0] = (fails[0] ## i64) + 1

  # sub both directions
  cmp = wn_cmp_nn(a, 0, b, 0, nn)
  bcmp = 0
  if ba > bb2
    bcmp = 1
  if ba < bb2
    bcmp = 0 - 1
  expect_eq("cmp" + tag, cmp, bcmp, fails)
  if cmp >= 0
    bw = wn_sub_nn(r, 0, a, 0, b, 0, nn)
    expect_eq("sub" + tag, big_of_limbs(r, 0, nn), ba - bb2, fails)
    expect_eq("sub_borrow" + tag, bw ## i64, 0, fails)
    bw2 = wn_sub_nn(r, 0, b, 0, a, 0, nn)
    got2 = big_of_limbs(r, 0, nn)
    if ba == bb2
      expect_eq("sub_rev" + tag, got2 + big_of_u64(bw2), 0, fails)
    else
      expect_eq("sub_rev" + tag, got2, shiftn + bb2 - ba, fails)
      expect_eq("sub_rev_borrow" + tag, bw2 ## i64, 1, fails)
  else
    bw = wn_sub_nn(r, 0, b, 0, a, 0, nn)
    expect_eq("sub" + tag, big_of_limbs(r, 0, nn), bb2 - ba, fails)
    expect_eq("sub_borrow" + tag, bw ## i64, 0, fails)

  # shifts
  kshifts = i64[4]
  kshifts[0] = 1
  kshifts[1] = 7
  kshifts[2] = 31
  kshifts[3] = 63
  ki = 0 ## i64
  while ki < 4
    k = kshifts[ki] ## i64
    spill = wn_shl(r, 0, a, 0, nn, k)
    got3 = big_of_limbs(r, 0, nn) + big_of_u64(spill) * shiftn
    expect_eq("shl" + k.to_s() + tag, got3, ba * big_pow2(k), fails)
    dropped = wn_shr(r, 0, a, 0, nn, k)
    got4 = big_of_limbs(r, 0, nn) * big_pow2(k) + big_of_u64(dropped)
    expect_eq("shr" + k.to_s() + tag, got4, ba, fails)
    ki += 1

  # mul_1 / addmul_1 with a full-range multiplier
  v = rng_next(cell) ## u64
  onesv = 0 ## u64
  onesv = onesv - 1
  if p == 1
    v = onesv + 0
  cm = wn_mul_1(r, 0, a, 0, nn, v)
  got5 = big_of_limbs(r, 0, nn) + big_of_u64(cm) * shiftn
  expect_eq("mul1" + tag, got5, ba * big_of_u64(v), fails)

  wn_copy(r, 0, b, 0, nn)
  br0 = big_of_limbs(r, 0, nn)
  cam = wn_addmul_1(r, 0, a, 0, nn, v)
  got6 = big_of_limbs(r, 0, nn) + big_of_u64(cam) * shiftn
  expect_eq("addmul1" + tag, got6, br0 + ba * big_of_u64(v), fails)
  wn_copy(r2, 0, b, 0, nn)
  cam4 = wn_addmul_1_u4(r2, 0, a, 0, nn, v)
  if limbs_equal(r, r2, nn) == 0 || big_of_u64(cam4).to_s() != big_of_u64(cam).to_s()
    << "FAIL addmul_u4 mismatch" + tag
    fails[0] = (fails[0] ## i64) + 1
  wn_copy(r2, 0, b, 0, nn)
  cam8 = wn_addmul_1_u8(r2, 0, a, 0, nn, v)
  if limbs_equal(r, r2, nn) == 0 || big_of_u64(cam8).to_s() != big_of_u64(cam).to_s()
    << "FAIL addmul_u8 mismatch" + tag
    fails[0] = (fails[0] ## i64) + 1
  wn_copy(r2, 0, b, 0, nn)
  cama = asm_addmul1(r2, 0, a, 0, v, nn)
  if limbs_equal(r, r2, nn) == 0 || big_of_u64(cama).to_s() != big_of_u64(cam).to_s()
    << "FAIL addmul_asm mismatch" + tag
    fails[0] = (fails[0] ## i64) + 1

  # square-shape basecase + asm cross-check
  wn_basecase(r, 0, a, 0, nn, b, 0, nn)
  expect_eq("mulbase" + tag, big_of_limbs(r, 0, 2 * nn), ba * bb2, fails)
  asm_mulbase(r2, 0, a, 0, b, 0, nn, nn)
  if limbs_equal(r, r2, 2 * nn) == 0
    << "FAIL mulbase_asm mismatch" + tag
    fails[0] = (fails[0] ## i64) + 1

  # karatsuba (even sizes only take the recursive path)
  wn_kara(r2, 0, a, 0, b, 0, nn, ws, 0)
  if limbs_equal(r, r2, 2 * nn) == 0
    << "FAIL kara mismatch" + tag
    fails[0] = (fails[0] ## i64) + 1
  0

fn run_check
  a = u64[128]
  b = u64[128]
  r = u64[300]
  r2 = u64[300]
  ws = u64[1200]
  cell = i64[2]
  cell[0] = 88172645463325252
  fails = i64[2]
  fails[0] = 0
  n = 1 ## i64
  while n <= 80
    p = 0 ## i64
    while p < 5
      check_size(n, p, a, b, r, r2, ws, cell, fails)
      p += 1
    if n < 40
      n += 1
    else
      n += 3
  # asymmetric basecase shapes
  shapes = i64[12]
  shapes[0] = 13
  shapes[1] = 7
  shapes[2] = 24
  shapes[3] = 1
  shapes[4] = 31
  shapes[5] = 17
  shapes[6] = 64
  shapes[7] = 3
  shapes[8] = 80
  shapes[9] = 79
  shapes[10] = 2
  shapes[11] = 40
  si = 0 ## i64
  while si < 12
    na = shapes[si] ## i64
    nb = shapes[si + 1] ## i64
    wn_fill(a, na, 0, cell)
    wn_fill(b, nb, 0, cell)
    ba = big_of_limbs(a, 0, na)
    bb2 = big_of_limbs(b, 0, nb)
    wn_basecase(r, 0, a, 0, na, b, 0, nb)
    expect_eq("mulbase_asym na=" + na.to_s() + " nb=" + nb.to_s(), big_of_limbs(r, 0, na + nb), ba * bb2, fails)
    si += 2
  nf = fails[0] ## i64
  if nf == 0
    << "CHECK PASS (all kernels vs BigInt oracle + asm cross-check)"
    return 0
  << "CHECK FAILED: " + nf.to_s() + " failures"
  1

# ── benchmark ────────────────────────────────────────────────────────

-> spin(iters)
  it = iters ## i64
  x = 1 ## u64
  k = 0 ## i64
  while k < it
    x = x + k
    x = x ^ 3
    k += 1
  x

# Typed lane helpers: the iters loop lives inside a fn whose array params
# are statically typed, so kernel calls are direct (no per-call ebits guard)
# and element access is inline.
-> lane_add(kind, r, a, b, n, iters) (i64 u64[] u64[] u64[] i64 i64) i64
  it = iters ## i64
  nn = n ## i64
  acc = 0 ## u64
  i = 0 ## i64
  if kind == 1
    while i < it
      acc = acc + wn_add_nn(r, 0, a, 0, b, 0, nn)
      i += 1
  elsif kind == 2
    while i < it
      acc = acc + wn_add_nn_u4(r, 0, a, 0, b, 0, nn)
      i += 1
  elsif kind == 3
    while i < it
      acc = acc + wn_add_nn_u8(r, 0, a, 0, b, 0, nn)
      i += 1
  elsif kind == 4
    while i < it
      cc = asm_add_no(r, 0, a, 0, b, 0, nn)
      acc = acc + (cc ## u64)
      i += 1
  else
    while i < it
      acc = acc + wn_sub_nn(r, 0, a, 0, b, 0, nn)
      i += 1
  acc ## i64

-> lane_mul1(kind, r, a, n, v, iters) (i64 u64[] u64[] i64 u64 i64) i64
  it = iters ## i64
  nn = n ## i64
  vv = v ## u64
  acc = 0 ## u64
  i = 0 ## i64
  if kind == 1
    while i < it
      acc = acc + wn_mul_1(r, 0, a, 0, nn, vv)
      i += 1
  elsif kind == 2
    while i < it
      acc = acc + wn_addmul_1(r, 0, a, 0, nn, vv)
      i += 1
  elsif kind == 3
    while i < it
      acc = acc + wn_addmul_1_u4(r, 0, a, 0, nn, vv)
      i += 1
  elsif kind == 4
    while i < it
      acc = acc + wn_addmul_1_u8(r, 0, a, 0, nn, vv)
      i += 1
  else
    while i < it
      cc = asm_addmul1(r, 0, a, 0, vv, nn)
      acc = acc + (cc ## u64)
      i += 1
  acc ## i64

-> lane_mulfull(kind, r, a, b, ws, n, iters) (i64 u64[] u64[] u64[] u64[] i64 i64) i64
  it = iters ## i64
  nn = n ## i64
  acc = 0 ## u64
  i = 0 ## i64
  if kind == 1
    while i < it
      acc = acc + wn_basecase(r, 0, a, 0, nn, b, 0, nn)
      i += 1
  elsif kind == 2
    while i < it
      cc = asm_mulbase(r, 0, a, 0, b, 0, nn, nn)
      acc = acc + (cc ## u64)
      i += 1
  else
    while i < it
      acc = acc + wn_kara(r, 0, a, 0, b, 0, nn, ws, 0)
      i += 1
  acc ## i64

-> lane_misc(kind, r, a, b, n, iters) (i64 u64[] u64[] u64[] i64 i64) i64
  it = iters ## i64
  nn = n ## i64
  acc = 0 ## u64
  i = 0 ## i64
  if kind == 1
    while i < it
      acc = acc + wn_cmp_nn(a, 0, b, 0, nn)
      i += 1
  elsif kind == 2
    while i < it
      acc = acc + wn_shl(r, 0, a, 0, nn, 13)
      i += 1
  else
    while i < it
      acc = acc + wn_shr(r, 0, a, 0, nn, 13)
      i += 1
  acc ## i64

-> lane_big(kind, ba, bb2, iters)
  it = iters ## i64
  i = 0 ## i64
  if kind == 1
    while i < it
      t = ba + bb2
      i += 1
  else
    while i < it
      t = ba * bb2
      i += 1
  0

# lane ids:
#  1 add native   2 add u4      3 add u8      4 add asm      5 big add
#  6 sub native   7 mul1        8 addmul      9 addmul u4   10 addmul u8
# 11 addmul asm  12 base nat   13 base asm   14 big mul     15 kara
# 16 cmp         17 shl13      18 shr13      19 spin
-> lane_run(id, r, a, b, ws, n, v, ba, bb2, iters)
  if id <= 3
    return lane_add(id, r, a, b, n, iters)
  if id == 4
    return lane_add(4, r, a, b, n, iters)
  if id == 5
    return lane_big(1, ba, bb2, iters)
  if id == 6
    return lane_add(5, r, a, b, n, iters)
  if id == 7
    return lane_mul1(1, r, a, n, v, iters)
  if id == 8
    return lane_mul1(2, r, a, n, v, iters)
  if id == 9
    return lane_mul1(3, r, a, n, v, iters)
  if id == 10
    return lane_mul1(4, r, a, n, v, iters)
  if id == 11
    return lane_mul1(5, r, a, n, v, iters)
  if id == 12
    return lane_mulfull(1, r, a, b, ws, n, iters)
  if id == 13
    return lane_mulfull(2, r, a, b, ws, n, iters)
  if id == 14
    return lane_big(2, ba, bb2, iters)
  if id == 15
    return lane_mulfull(3, r, a, b, ws, n, iters)
  if id == 16
    return lane_misc(1, r, a, b, n, iters)
  if id == 17
    return lane_misc(2, r, a, b, n, iters)
  if id == 18
    return lane_misc(3, r, a, b, n, iters)
  spin(iters)

fn measure_ns(id, r, a, b, ws, n, v, ba, bb2, sink)
  iters = 16 ## i64
  elapsed = ~0.0
  guard = 0 ## i64
  while elapsed < ~0.004 && guard < 36
    iters = iters * 2
    t0 = clock()
    sg = lane_run(id, r, a, b, ws, n, v, ba, bb2, iters)
    t1 = clock()
    sink[0] = (sink[0] ## u64) + sg
    elapsed = t1 - t0
    guard += 1
  best = ~1000000000.0
  s = 0 ## i64
  while s < 9
    t0 = clock()
    sg = lane_run(id, r, a, b, ws, n, v, ba, bb2, iters)
    t1 = clock()
    sink[0] = (sink[0] ## u64) + sg
    d = t1 - t0
    if d < best
      best = d
    s += 1
  best * ~1000000000.0 / iters.to_f()

fn fmt2(x)
  # fixed 2-decimal string for a nonnegative float
  xi = (x * ~100.0 + ~0.5).to_i()
  whole = xi / 100
  frac = xi % 100
  fs = frac.to_s()
  if frac < 10
    fs = "0" + fs
  whole.to_s() + "." + fs

fn bench_row(opname, lane, id, r, a, b, ws, n, v, ba, bb2, sink, ghz, per_limb_sq)
  ns = measure_ns(id, r, a, b, ws, n, v, ba, bb2, sink)
  nn = n ## i64
  cyc = ns * ghz
  denom = nn.to_f()
  if per_limb_sq == 1
    denom = denom * nn.to_f()
  cpl = cyc / denom
  << opname + " n=" + nn.to_s() + " " + lane + " ns=" + fmt2(ns) + " c/l=" + fmt2(cpl)
  ns

fn run_bench
  a = u64[1024]
  b = u64[1024]
  r = u64[2100]
  ws = u64[8300]
  sink = u64[2]
  sink[0] = 0
  cell = i64[2]
  cell[0] = 424242424242
  wn_fill(a, 1024, 0, cell)
  wn_fill(b, 1024, 0, cell)
  v = 25214903917 ## u64
  zed = u64[2]

  # cycle-time estimate from a 2-op dependent chain
  bogus = 0 ## big
  ghz_best = ~0.0
  t = 0 ## i64
  while t < 7
    it = 50000000 ## i64
    t0 = clock()
    sg = spin(it)
    t1 = clock()
    sink[0] = (sink[0] ## u64) + sg
    g = ~2.0 * it.to_f() / (t1 - t0) / ~1000000000.0
    if g > ghz_best
      ghz_best = g
    t += 1
  << "est_freq_ghz=" + fmt2(ghz_best)

  sizes = i64[16]
  sizes[0] = 4
  sizes[1] = 8
  sizes[2] = 16
  sizes[3] = 24
  sizes[4] = 32
  sizes[5] = 48
  sizes[6] = 64
  sizes[7] = 128
  sizes[8] = 256
  sizes[9] = 512
  sizes[10] = 1024
  nsz = 11 ## i64

  si = 0 ## i64
  while si < nsz
    n = sizes[si] ## i64
    ba = big_of_limbs(a, 0, n)
    bb2 = big_of_limbs(b, 0, n)
    bench_row("add_n", "native", 1, r, a, b, ws, n, v, ba, bb2, sink, ghz_best, 0)
    bench_row("add_n", "nat_u4", 2, r, a, b, ws, n, v, ba, bb2, sink, ghz_best, 0)
    bench_row("add_n", "nat_u8", 3, r, a, b, ws, n, v, ba, bb2, sink, ghz_best, 0)
    bench_row("add_n", "asm   ", 4, r, a, b, ws, n, v, ba, bb2, sink, ghz_best, 0)
    bench_row("add_n", "bigint", 5, r, a, b, ws, n, v, ba, bb2, sink, ghz_best, 0)
    bench_row("sub_n", "native", 6, r, a, b, ws, n, v, ba, bb2, sink, ghz_best, 0)
    bench_row("mul_1", "native", 7, r, a, b, ws, n, v, ba, bb2, sink, ghz_best, 0)
    bench_row("addmul_1", "native", 8, r, a, b, ws, n, v, ba, bb2, sink, ghz_best, 0)
    bench_row("addmul_1", "nat_u4", 9, r, a, b, ws, n, v, ba, bb2, sink, ghz_best, 0)
    bench_row("addmul_1", "nat_u8", 10, r, a, b, ws, n, v, ba, bb2, sink, ghz_best, 0)
    bench_row("addmul_1", "asm   ", 11, r, a, b, ws, n, v, ba, bb2, sink, ghz_best, 0)
    if n <= 256
      bench_row("mul_bc", "native", 12, r, a, b, ws, n, v, ba, bb2, sink, ghz_best, 1)
      bench_row("mul_bc", "asm   ", 13, r, a, b, ws, n, v, ba, bb2, sink, ghz_best, 1)
    bench_row("mul", "bigint", 14, r, a, b, ws, n, v, ba, bb2, sink, ghz_best, 1)
    if n >= 32
      bench_row("mul", "kara  ", 15, r, a, b, ws, n, v, ba, bb2, sink, ghz_best, 1)
    bench_row("cmp", "native", 16, r, a, a, ws, n, v, ba, bb2, sink, ghz_best, 0)
    bench_row("shl", "native", 17, r, a, b, ws, n, v, ba, bb2, sink, ghz_best, 0)
    bench_row("shr", "native", 18, r, a, b, ws, n, v, ba, bb2, sink, ghz_best, 0)
    si += 1
  << "sink=" + (sink[0] ## u64).to_s()
  0

args = argv()
want_bench = 0
ai = 0
while ai < args.size()
  if args[ai] == "bench"
    want_bench = 1
  ai += 1
rc = run_check()
if rc == 0 && want_bench == 1
  run_bench()
