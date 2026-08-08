# Array sort ordering regressions.
#
# Signed typed arrays (i8/i16/i32/i64) must sort in SIGNED order on every
# algorithm and every size tier — the typed kernels compare storage bits as
# unsigned, and the runtime maps signedness onto them with a sign-bit flip
# (w_ta_sign_flip). Before 8/8 every typed fast path returned unsigned
# order (negatives after positives) while the Ruby engine sorted correctly.
#
# Floats sort via the IEEE-754 total-order key transform: deterministic
# -inf … -0.0 … +inf, NaN last, on both the pdq and radix tiers.
#
# Boxed (polymorphic) arrays of all-ints or all-doubles take typed-kernel
# fast paths; mixed arrays keep the w_value_compare comparator path.
#
# Run: `bin/tungsten -o /tmp/sortspec spec/core/array_sort_order_spec.w && /tmp/sortspec`
# Engine parity: also run interpreted. (--ruby lacks the explicit-algorithm
# methods ipnsort/tsort/skasort/wolfsort — blockless sort checks only.)

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

-> lcg(s)
  s * 6364136223846793005 + 1442695040888963407

# comparator mergesort is independent machinery — the ordering oracle
-> expected(src)
  e = src.sort -> (x, y)
    x <=> y
  e.to_s

# sizes straddle every tier: pdq (<2048 for i64), radix, and the 64-bit
# radix→ipnsort upper cutoff at 131072
-> check_i64_all_algos(n)
  a = i64[n]
  s = 987654321 + n ## i64
  i = 0 ## i64
  while i < n
    s = lcg(s)
    a[i] = s
    i += 1
  want = expected(a)
  label = " i64 n=" + n.to_s()
  check("sort" + label, a.sort.to_s, want)
  check("sort!" + label, a.sort!.to_s, want)
  check("ipnsort" + label, a.ipnsort.to_s, want)
  check("tsort" + label, a.tsort.to_s, want)
  check("skasort" + label, a.skasort.to_s, want)
  check("wolfsort" + label, a.wolfsort.to_s, want)
  check("csort" + label, a.csort.to_s, want)

check_i64_all_algos(17)
check_i64_all_algos(1000)
check_i64_all_algos(5000)

# the >131072 tier (ipnsort), signed
big = i64[140000]
bs = 42 ## i64
bi = 0 ## i64
while bi < 140000
  bs = lcg(bs)
  big[bi] = bs
  bi += 1
sorted_big = big.sort
check("sort i64 n=140000 first<=last", (sorted_big[0] <= sorted_big[139999]).to_s, "true")
check("sort i64 n=140000 signed", (sorted_big[0] < 0 && sorted_big[139999] > 0).to_s, "true")
mono = true
bi = 1
while bi < 140000
  if sorted_big[bi - 1] > sorted_big[bi]
    mono = false
  bi += 1
check("sort i64 n=140000 nondecreasing", mono.to_s, "true")

# i32 signed, both tiers (radix from 512)
c = i32[600]
cs = 5 ## i64
ci = 0 ## i64
while ci < 600
  cs = lcg(cs)
  c[ci] = ((cs >> 16) & 4294967295) - 2147483648
  ci += 1
check("sort i32 n=600", c.sort.to_s, expected(c))

# small i32 with negatives — the original repro shape
d = i32[6]
d[0] = 3
d[1] = 0 - 1
d[2] = 2
d[3] = 0 - 5
d[4] = 0
d[5] = 7
neg_first = d.sort
check("sort i32 negatives first", neg_first[0].to_s + "," + neg_first[1].to_s, "-5,-1")

# floats: deterministic total order with specials, on both tiers
f = f64[5]
f[0] = 1.to_f
f[1] = Math.sqrt((0 - 1).to_f)
f[2] = (0 - 3).to_f
f[3] = Math.exp(710.to_f)
f[4] = 0.to_f - Math.exp(710.to_f)
fs = f.sort
check("sort f64 specials", fs[0].to_s + "|" + fs[1].to_s + "|" + fs[2].to_s + "|" + fs[3].to_s + "|" + fs[4].to_s, "-inf|-3|1|inf|nan")

g = f64[600]
gi = 0 ## i64
while gi < 600
  g[gi] = (300 - gi).to_f
  gi += 1
g[7] = Math.sqrt((0 - 1).to_f)
gsorted = g.sort
check("sort f64 radix nan last", (gsorted[599].to_s == "nan").to_s, "true")
check("sort f64 radix first", gsorted[0].to_s, "-299")

# boxed arrays: all-int fast path, all-double fast path, mixed fallback
h = []
hs = 31337 ## i64
hi = 0 ## i64
while hi < 300
  hs = lcg(hs)
  h.push((hs & 140737488355327) - 70368744177664)
  hi += 1
check("sort boxed ints", h.sort.to_s, expected(h))

fl = []
hi = 0
hs = 777 ## i64
while hi < 300
  hs = lcg(hs)
  fl.push(((hs & 65535) - 32768).to_f / 7)
  hi += 1
check("sort boxed doubles", fl.sort.to_s, expected(fl))

mixed = [3, 3.to_f / 2, 2, (0 - 1).to_f / 2, 7, 17.to_f / 4, 0 - 3]
check("sort boxed mixed", mixed.sort.to_s, expected(mixed))

# comparator path is stable: keys v/100, payload v%100 keeps input order
pairs = [302, 101, 305, 203, 104, 208]
stable = pairs.sort -> (x, y)
  (x / 100) <=> (y / 100)
stable_want = [101, 104, 203, 208, 302, 305]
check("sort block stable", stable.to_s, stable_want.to_s)

# mergesort! — the guaranteed-stable in-place spelling
ms = [5, 3, 9, 3, 1]
ms.mergesort!
ms_want = [1, 3, 3, 5, 9]
check("mergesort!", ms.to_s, ms_want.to_s)

# stable_sort: typed arrays match sort exactly (equal values there are
# indistinguishable); mixed polymorphic ties keep input order — the one
# blockless case where stability is observable (2 vs 2.0 compare equal)
sst = i64[1000]
ss = 20260808 ## i64
si = 0 ## i64
while si < 1000
  ss = lcg(ss)
  sst[si] = ss
  si += 1
check("stable_sort typed matches sort", (sst.stable_sort.to_s == sst.sort.to_s).to_s, "true")

sm1 = [2.to_f, 2, 1]
sr1 = sm1.stable_sort
check("stable_sort mixed float first", type(sr1[1]) + "," + type(sr1[2]), "Float,Integer")
sm2 = [2, 2.to_f, 1]
sr2 = sm2.stable_sort
check("stable_sort mixed int first", type(sr2[1]) + "," + type(sr2[2]), "Integer,Float")

sp = pairs.stable_sort -> (x, y)
  (x / 100) <=> (y / 100)
check("stable_sort block stable", sp.to_s, stable_want.to_s)

<< "PASS array_sort_order_spec"
