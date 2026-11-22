# spec: compiled -- mulhi/addcarry are compiled-only intrinsics
# A `## u64`-hinted reassignment inside a loop, of a var first assigned
# before the loop (here by an earlier loop), lowers its RHS in u64.
# Regression: such a var was a loop-unboxing candidate, and the unboxed
# assign path lowered `hi + addcarry(a, b)` generically: both operands were
# boxed, the sum promoted to a BigInt, and its pointer bits were stored as
# the u64 result (different garbage per run). Renaming the var in the
# second loop hid the bug. Found in a Montgomery multiply (TLS P-256).
#
# Run:
#   bin/tungsten spec/compiler/loop_hinted_reassign_spec.w

-> check(name, got, want)
  if got != want
    << "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
    exit 1
  << "PASS " + name

-> carry_rows(w, n) (u64[] i64) i64
  j = 0
  while j < n
    hi = mulhi(w[j], w[j]) ## u64
    hi = hi + addcarry(w[j], w[j]) ## u64
    j += 1
  j = 0
  while j < n
    hi = mulhi(w[j], w[j]) ## u64
    hi = hi + addcarry(w[j], w[j]) ## u64
    w[4 + j] = hi
    j += 1
  0

# A u64 var counted in a loop keeps its unsigned reading past 2^63.
-> count_high(start, n) (u64 i64) i64
  x = start ## u64
  limit = 9223372036854775807 ## u64
  seen = 0
  i = 0
  while i < n
    x += 1
    if x > limit
      seen += 1
    i += 1
  seen

# The reported kernel: a two-limb Montgomery multiply whose reduce loop
# reuses `hi` from the multiply loop.
-> mmx(w, r, a, b, mo, to, n, ninv) (u64[] i64 i64 i64 i64 i64 i64 u64) i64
  i = 0
  while i < n + 2
    w[to + i] = 0
    i += 1
  i = 0
  while i < n
    ai = w[a + i]
    c = 0 ## u64
    j = 0
    while j < n
      bj = w[b + j]
      lo = ai * bj ## u64
      hi = mulhi(ai, bj) ## u64
      tj = w[to + j]
      s = tj + lo ## u64
      hi = hi + addcarry(tj, lo) ## u64
      s2 = s + c ## u64
      hi = hi + addcarry(s, c) ## u64
      w[to + j] = s2
      c = hi
      j += 1
    # (every wrapping sum goes through a `## u64` local: an unhinted u64 + u64 that
    # overflows promotes to an Integer, and storing that into u64[] writes garbage)
    tn = w[to + n]
    sn = tn + c ## u64
    cn = w[to + n + 1] + addcarry(tn, c) ## u64
    w[to + n] = sn
    w[to + n + 1] = cn
    k = 0
    while k < n + 2
      w[44 + i * 4 + k] = w[to + k]
      k += 1
    # reduce: add q*m so the low limb vanishes, then shift down one limb
    t0 = w[to]
    q = t0 * ninv ## u64
    m0 = w[mo]
    lo = q * m0 ## u64
    c = mulhi(q, m0) + addcarry(t0, lo) ## u64
    j = 1
    while j < n
      mj = w[mo + j]
      lo = q * mj ## u64
      hi = mulhi(q, mj) ## u64
      tj = w[to + j]
      s = tj + lo ## u64
      hi = hi + addcarry(tj, lo) ## u64
      s2 = s + c ## u64
      hi = hi + addcarry(s, c) ## u64
      w[to + j - 1] = s2
      c = hi
      j += 1
    tn = w[to + n]
    sn = tn + c ## u64
    cn = w[to + n + 1] + addcarry(tn, c) ## u64
    w[to + n - 1] = sn
    w[to + n] = cn
    w[to + n + 1] = 0
    k = 0
    while k < n + 2
      w[36 + i * 4 + k] = w[to + k]
      k += 1
    i += 1
  # t < 2m: r = t - m unless that borrows (and t has no carry limb)
  borrow = 0 ## u64
  j = 0
  while j < n
    tj = w[to + j]
    mj = w[mo + j]
    d = tj - mj ## u64
    b1 = subborrow(tj, mj) ## u64
    d2 = d - borrow ## u64
    b2 = subborrow(d, borrow) ## u64
    w[r + j] = d2
    borrow = b1 | b2
    j += 1
  # keep the subtraction when t[n] == 1 or no borrow
  keep = w[to + n] | (borrow ^ 1) ## u64
  mask = 0 - (keep & 1) ## u64
  j = 0
  while j < n
    tj = w[to + j]
    w[r + j] = tj ^ ((tj ^ w[r + j]) & mask)
    j += 1
  0

-> mp_ninv(m0) (u64) u64
  x = m0 ## u64
  i = 0
  while i < 6
    x = x * (2 - m0 * x) ## u64
    i += 1
  0 - x ## u64

m = u64[60]
m[0] = 0xffffffffffffff61
m[1] = 0xffffffffffffffff
m[10] = 0x123456789abcdef1
m[11] = 0x0fedcba987654321
m[12] = 0x1111111111111111
m[13] = 0x2222222222222222
ninv = mp_ninv(m[0])
mmx(m, 20, 10, 12, 0, 30, 2, ninv)
check("montgomery reduce limb 0", m[36].to_s(16), "20eb71b3b16adf91")
check("montgomery reduce limb 1", m[37].to_s(16), "d2399ea72948707f")
check("montgomery second pass limb 1", m[49].to_s(16), "d129c44686a816b0")
check("montgomery result", m[21].to_s(16) + " " + m[20].to_s(16), "f34686c75a5cc9c d129c44686a816a8")

w = u64[8]
w[0] = 0xffffffffffffff61
w[1] = 0xffffffffffffffff
carry_rows(w, 2)
check("second loop row 0", w[4].to_s(16), "fffffffffffffec3")
check("second loop row 1", w[5].to_s(16), "ffffffffffffffff")
start = 9223372036854775805 ## u64
check("u64 loop var compares unsigned", count_high(start, 4), 2)
