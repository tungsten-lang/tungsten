# Algebra-layer benchmark harness — Gröbner, polynomial normal forms,
# polynomial matrices, LLL, Smith normal form, resultants, GF(2) RREF.
#
# Every input is deterministic (fixed LCG seeds), so before/after timings on
# the same machine are directly comparable and results can be asserted.
#
#   bin/tungsten --release -o /tmp/algebra_bench benchmarks/algebra/algebra_bench.w
#   /tmp/algebra_bench
#
# Prints one "BENCH <name> ms=<n> <checks>" line per section; a final
# "algebra_bench done" line marks a clean run.

use algebra

-> now_ms
  ccall("__w_clock_ms")

# Deterministic LCG (31-bit) — same stream every run.
+ BenchRandom
  -> new(@seed)

  -> next_int(bound)
    @seed = (@seed * 1103515245 + 12345) % 2147483648
    @seed % bound

# ── polynomial add chain (constructor renormalization pressure) ──────────
ring = PolynomialRing.new([:x, :y], RationalField.new, :grevlex)
x = ring.generator(0)
y = ring.generator(1)
rng = BenchRandom.new(7)
t0 = now_ms
acc = ring.zero
i = 0
while i < 400
  acc = acc + x**rng.next_int(40) * y**rng.next_int(40) * (rng.next_int(97) + 1)
  i += 1
t1 = now_ms
<< "BENCH poly_add_chain ms=" + (t1 - t0).to_s + " terms=" + acc.terms.size.to_s

# ── polynomial multiply (dense × dense, then product into sum) ───────────
uring = PolynomialRing.new([:t], RationalField.new)
t = uring.generator(0)
dense_a = uring.zero
dense_b = uring.zero
i = 0
while i <= 60
  dense_a = dense_a + t**i * (i + 1)
  dense_b = dense_b + t**i * (2 * i + 1)
  i += 1
t0 = now_ms
prod = uring.zero
i = 0
while i < 40
  prod = dense_a * dense_b
  i += 1
t1 = now_ms
<< "BENCH poly_mul_dense60 ms=" + (t1 - t0).to_s + " terms=" + prod.terms.size.to_s

# ── multivariate reduction chain (Gröbner normal-form shape) ─────────────
mring = PolynomialRing.new([:a, :b, :c], RationalField.new, :grevlex)
ga = mring.generator(0)
gb = mring.generator(1)
gc = mring.generator(2)
dividend = (ga + gb + gc + 1)**7
divisors = [ga**2 - gb, gb**2 - gc, gc**2 - ga * gb]
t0 = now_ms
division = dividend.divide(divisors)
t1 = now_ms
<< "BENCH poly_reduce_deg7 ms=" + (t1 - t0).to_s + " rem_terms=" + division[1].terms.size.to_s

# ── Gröbner bases ────────────────────────────────────────────────────────
cring = PolynomialRing.new([:a, :b, :c, :d], RationalField.new, :grevlex)
ca = cring.generator(0)
cb = cring.generator(1)
cc = cring.generator(2)
cd = cring.generator(3)
cyclic4 = [
  ca + cb + cc + cd,
  ca * cb + cb * cc + cc * cd + cd * ca,
  ca * cb * cc + cb * cc * cd + cc * cd * ca + cd * ca * cb,
  ca * cb * cc * cd - 1]
t0 = now_ms
gb_cyclic = GroebnerBasis.basis(cyclic4)
t1 = now_ms
<< "BENCH groebner_cyclic4 ms=" + (t1 - t0).to_s + " basis=" + gb_cyclic.size.to_s

kfield = FiniteField.new(32003)
kring = PolynomialRing.new([:u0, :u1, :u2, :u3], kfield, :grevlex)
u0 = kring.generator(0)
u1 = kring.generator(1)
u2 = kring.generator(2)
u3 = kring.generator(3)
katsura = [
  u0 + 2 * u1 + 2 * u2 + 2 * u3 - 1,
  u0**2 + 2 * u1**2 + 2 * u2**2 + 2 * u3**2 - u0,
  2 * u0 * u1 + 2 * u1 * u2 + 2 * u2 * u3 - u1,
  u1**2 + 2 * u0 * u2 + 2 * u1 * u3 - u2]
t0 = now_ms
gb_katsura = GroebnerBasis.basis(katsura)
t1 = now_ms
<< "BENCH groebner_katsura4_f32003 ms=" + (t1 - t0).to_s + " basis=" + gb_katsura.size.to_s

c5ring = PolynomialRing.new([:v0, :v1, :v2, :v3, :v4], kfield, :grevlex)
v0 = c5ring.generator(0)
v1 = c5ring.generator(1)
v2 = c5ring.generator(2)
v3 = c5ring.generator(3)
v4 = c5ring.generator(4)
cyclic5 = [
  v0 + v1 + v2 + v3 + v4,
  v0 * v1 + v1 * v2 + v2 * v3 + v3 * v4 + v4 * v0,
  v0 * v1 * v2 + v1 * v2 * v3 + v2 * v3 * v4 + v3 * v4 * v0 + v4 * v0 * v1,
  v0 * v1 * v2 * v3 + v1 * v2 * v3 * v4 + v2 * v3 * v4 * v0 + v3 * v4 * v0 * v1 + v4 * v0 * v1 * v2,
  v0 * v1 * v2 * v3 * v4 - 1]
t0 = now_ms
gb_cyclic5 = GroebnerBasis.basis(cyclic5)
t1 = now_ms
<< "BENCH groebner_cyclic5_f32003 ms=" + (t1 - t0).to_s + " basis=" + gb_cyclic5.size.to_s


# ── polynomial matrices over F101[z] ─────────────────────────────────────
pfield = FiniteField.new(101)
pring = PolynomialRing.new([:z], pfield)
z = pring.generator(0)
rng = BenchRandom.new(11)
entries = []
i = 0
while i < 5
  row = []
  j = 0
  while j < 10
    p = pring.zero
    d = 0
    while d <= 8
      p = p + z**d * rng.next_int(101)
      d += 1
    row.push(p)
    j += 1
  entries.push(row)
  i += 1
i = 0
while i < 5
  row = []
  j = 0
  while j < 10
    p = entries[i][j] * z + entries[(i + 1) % 5][j] * (rng.next_int(100) + 1)
    row.push(p)
    j += 1
  entries.push(row)
  i += 1
pmatrix = PolynomialMatrix.new(pring, entries)
t0 = now_ms
reduced = pmatrix.row_reduce_with_transform
t1 = now_ms
<< "BENCH polymatrix_row_reduce_10x10d8 ms=" + (t1 - t0).to_s + " maxdeg=" + reduced[0].max_degree.to_s

tall_entries = []
i = 0
while i < 4
  row = []
  j = 0
  while j < 8
    p = pring.zero
    d = 0
    while d <= 6
      p = p + z**d * rng.next_int(101)
      d += 1
    row.push(p)
    j += 1
  tall_entries.push(row)
  i += 1
tall = PolynomialMatrix.new(pring, tall_entries)
t0 = now_ms
obasis = tall.order_basis(24)
t1 = now_ms
<< "BENCH polymatrix_order_basis_24 ms=" + (t1 - t0).to_s + " maxdeg=" + obasis[0].max_degree.to_s

t0 = now_ms
kern = tall.minimal_kernel_basis(10)
t1 = now_ms
<< "BENCH polymatrix_kernel_basis_10 ms=" + (t1 - t0).to_s + " vecs=" + kern[0].size.to_s

# ── exact + approximate LLL (knapsack-style rank 8) ──────────────────────
rng = BenchRandom.new(13)
rank = 12
basis = []
i = 0
while i < rank
  row = []
  j = 0
  while j < rank
    row.push(i == j ? 1 : 0)
    j += 1
  row[rank - 1] = rng.next_int(1000000) + 1
  basis.push(row)
  i += 1
gram = []
i = 0
while i < rank
  row = []
  j = 0
  while j < rank
    row.push(i == j ? 1 : 0)
    j += 1
  gram.push(row)
  i += 1
t0 = now_ms
lll_exact = ExactGramLatticeReduction.new(gram, basis)
t1 = now_ms
<< "BENCH lll_exact_rank12 ms=" + (t1 - t0).to_s + " certified=" + lll_exact.certified?.to_s

t0 = now_ms
lll_approx = ExactGramLatticeReduction.new(gram, basis, Rational.new(3, 4), :approximate)
t1 = now_ms
<< "BENCH lll_approx_rank12 ms=" + (t1 - t0).to_s + " certified=" + lll_approx.certified?.to_s

# ── Smith normal form (8×8 structured integers) ──────────────────────────
rng = BenchRandom.new(17)
snf_matrix = []
i = 0
while i < 8
  row = []
  j = 0
  while j < 8
    row.push(rng.next_int(41) - 20)
    j += 1
  snf_matrix.push(row)
  i += 1
t0 = now_ms
factors = SmithNormalForm.invariant_factors(snf_matrix)
t1 = now_ms
<< "BENCH snf_8x8 ms=" + (t1 - t0).to_s + " factors=" + factors.size.to_s

rng = BenchRandom.new(29)
snf_big = []
i = 0
while i < 16
  row = []
  j = 0
  while j < 16
    row.push(rng.next_int(2001) - 1000)
    j += 1
  snf_big.push(row)
  i += 1
t0 = now_ms
rounds = 0
factors_big = []
while rounds < 20
  factors_big = SmithNormalForm.invariant_factors(snf_big)
  rounds += 1
t1 = now_ms
<< "BENCH snf_16x16_x20 ms=" + (t1 - t0).to_s + " factors=" + factors_big.size.to_s

# ── resultants (univariate, rational) ────────────────────────────────────
rng = BenchRandom.new(19)
res_a = uring.zero
res_b = uring.zero
i = 0
while i <= 60
  res_a = res_a + t**i * (rng.next_int(19) - 9)
  i += 1
i = 0
while i <= 50
  res_b = res_b + t**i * (rng.next_int(19) - 9)
  i += 1
res_a = res_a + t**60
res_b = res_b + t**50
t0 = now_ms
res = res_a.resultant(res_b)
t1 = now_ms
<< "BENCH resultant_60x50 ms=" + (t1 - t0).to_s + " zero=" + res.zero?.to_s


# ── polynomial dedup / equality-heavy workload (content-hash filter) ─────
rng = BenchRandom.new(31)
dedup_ring = PolynomialRing.new([:p, :q], FiniteField.new(101), :grevlex)
dp = dedup_ring.generator(0)
dq = dedup_ring.generator(1)
distinct = []
i = 0
while i < 120
  poly = dedup_ring.zero
  t = 0
  while t < 12
    poly = poly + dp**rng.next_int(20) * dq**rng.next_int(20) * (rng.next_int(100) + 1)
    t += 1
  distinct.push(poly)
  i += 1
population = []
i = 0
while i < 2000
  population.push(distinct[rng.next_int(120)])
  i += 1
t0 = now_ms
seen = {}
unique = 0
population.each -> (poly)
  key = poly.content_hash
  bucket = seen[key]
  if bucket == nil
    seen[key] = [poly]
    unique += 1
  else
    found = false
    bucket.each -> (candidate)
      found = true if candidate == poly
    if !found
      bucket.push(poly)
      unique += 1
t1 = now_ms
<< "BENCH poly_dedup_2000 ms=" + (t1 - t0).to_s + " unique=" + unique.to_s

# ── GF(2) RREF (160 rows × width 256) ────────────────────────────────────
rng = BenchRandom.new(23)
f2_rows = []
i = 0
while i < 512
  row = []
  j = 0
  while j < 1024
    row.push(rng.next_int(2))
    j += 1
  f2_rows.push(row)
  i += 1
rhs = []
i = 0
while i < 512
  rhs.push(rng.next_int(2))
  i += 1
t0 = now_ms
f2_result = F2LinearAlgebra.reduce(1024, f2_rows, rhs)
t1 = now_ms
<< "BENCH f2_rref_512x1024 ms=" + (t1 - t0).to_s + " out=" + f2_result.size.to_s

<< "algebra_bench done"
