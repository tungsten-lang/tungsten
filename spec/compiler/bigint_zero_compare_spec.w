# O(1) zero/sign compares on statically-BigInt operands. The compiled
# __w_*0_big_fast helpers answer from the tag or the header signed size
# composed with the tag-sign overlay; these rows pin all six relations on
# heap bigints, inline ints under a :bigint fact, overlay-negated aliases,
# demoted values, and both literal positions.

-> check(name, got, want)
  if got.to_s() == want.to_s()
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

p = ((1 << 300) + 987654321) ## big
n = 0 - p ## big
z = p - p ## big
s = 7 ## big
sn = 0 - 7 ## big

# Heap positive.
check("cmp0.p.eq", p == 0, false)
check("cmp0.p.neq", p != 0, true)
check("cmp0.p.gt", p > 0, true)
check("cmp0.p.lt", p < 0, false)
check("cmp0.p.gte", p >= 0, true)
check("cmp0.p.lte", p <= 0, false)

# Heap negative through the overlay-negated alias (n shares p's buffer with
# bit 47 flipped — a raw header read would answer these all wrong).
check("cmp0.n.eq", n == 0, false)
check("cmp0.n.neq", n != 0, true)
check("cmp0.n.gt", n > 0, false)
check("cmp0.n.lt", n < 0, true)
check("cmp0.n.gte", n >= 0, false)
check("cmp0.n.lte", n <= 0, true)

# Double negation composes back to positive.
dn = 0 - n ## big
check("cmp0.dn.gt", dn > 0, true)
check("cmp0.dn.lt", dn < 0, false)
check("cmp0.dn.eq", dn == 0, false)

# Exact zero (demoted difference).
check("cmp0.z.eq", z == 0, true)
check("cmp0.z.neq", z != 0, false)
check("cmp0.z.gt", z > 0, false)
check("cmp0.z.lt", z < 0, false)
check("cmp0.z.gte", z >= 0, true)
check("cmp0.z.lte", z <= 0, true)

# Negated zero is still zero.
zn = 0 - z ## big
check("cmp0.zn.eq", zn == 0, true)
check("cmp0.zn.lt", zn < 0, false)
check("cmp0.zn.gte", zn >= 0, true)

# Inline ints riding a :bigint fact take the helper's inline leg.
check("cmp0.s.gt", s > 0, true)
check("cmp0.s.lte", s <= 0, false)
check("cmp0.s.eq", s == 0, false)
check("cmp0.sn.lt", sn < 0, true)
check("cmp0.sn.gte", sn >= 0, false)
check("cmp0.sn.neq", sn != 0, true)

# Demotion mid-flight: a bigint-typed difference that fits i48.
d = ((1 << 100) + 5) ## big
d2 = (1 << 100) ## big
dd = d - d2 ## big
check("cmp0.demoted.gt", dd > 0, true)
check("cmp0.demoted.value", dd, 5)
ddn = d2 - d ## big
check("cmp0.demoted.neg.lt", ddn < 0, true)

# Literal-on-the-left mirrors: `0 < x` is `x > 0`, etc.
check("cmp0.mirror.lt", 0 < p, true)
check("cmp0.mirror.gt", 0 > n, true)
check("cmp0.mirror.lte", 0 <= z, true)
check("cmp0.mirror.gte", 0 >= n, true)
check("cmp0.mirror.eq", 0 == z, true)
check("cmp0.mirror.neq", 0 != p, true)
check("cmp0.mirror.lt.false", 0 < n, false)
check("cmp0.mirror.gte.false", 0 >= p, false)

# Sign flips crossing zero inside a loop (heap -> inline -> heap, overlay
# on and off) keep every relation coherent with a generic-path twin that
# hides the literal zero behind a variable.
-> sign_walk_fused(seed, iters)
  x = seed ## big
  acc = 0 ## i64
  i = 0 ## i64
  while i < iters
    if x > 0
      acc += 1
    if x < 0
      acc += 2
    if x == 0
      acc += 3
    if x >= 0
      acc += 4
    if x <= 0
      acc += 5
    if x != 0
      acc += 6
    x = 0 - x
    if i % 3 == 0
      x = x - 1
    i += 1
  acc

-> sign_walk_generic(seed, iters)
  x = seed ## big
  zero = ((1 << 90) - (1 << 90)) ## big
  acc = 0 ## i64
  i = 0 ## i64
  while i < iters
    if x > zero
      acc += 1
    if x < zero
      acc += 2
    if x == zero
      acc += 3
    if x >= zero
      acc += 4
    if x <= zero
      acc += 5
    if x != zero
      acc += 6
    x = 0 - x
    if i % 3 == 0
      x = x - 1
    i += 1
  acc

wseed = (1 << 80) + 3
check("cmp0.walk.pos.seed", sign_walk_fused(wseed, 50), sign_walk_generic(wseed, 50))
check("cmp0.walk.zero.seed", sign_walk_fused(0, 50), sign_walk_generic(0, 50))
check("cmp0.walk.one.seed", sign_walk_fused(1, 50), sign_walk_generic(1, 50))
