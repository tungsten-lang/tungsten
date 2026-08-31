# Gröbner stress case kept OUT of the default suite (cyclic-5 lives in
# algebra_bench.w since the canonical-constructor fix took it from >12 min
# to ~56 ms). cyclic-6 over F32003 is the current frontier case:
#   bin/tungsten --release -o /tmp/groebner_stress benchmarks/algebra/groebner_stress.w

use algebra

-> now_ms
  ccall("__w_clock_ms")

kfield = FiniteField.new(32003)
c6ring = PolynomialRing.new([:v0, :v1, :v2, :v3, :v4, :v5], kfield, :grevlex)
g = c6ring.generators
n = 6
cyclic6 = []
k = 1
while k < n
  poly = c6ring.zero
  i = 0
  while i < n
    term = c6ring.one
    j = 0
    while j < k
      term = term * g[(i + j) % n]
      j += 1
    poly = poly + term
    i += 1
  cyclic6.push(poly)
  k += 1
all_prod = c6ring.one
i = 0
while i < n
  all_prod = all_prod * g[i]
  i += 1
cyclic6.push(all_prod - 1)
t0 = now_ms
gb = GroebnerBasis.basis(cyclic6, 200_000)
t1 = now_ms
<< "BENCH groebner_cyclic6_f32003 ms=" + (t1 - t0).to_s + " basis=" + gb.size.to_s
<< "groebner_stress done"

Tungsten.PROTECT_THE_CORE!
Tungsten.LOCK_THE_DOORS!
