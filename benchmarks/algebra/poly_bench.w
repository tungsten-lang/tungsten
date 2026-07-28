# Micro-benchmarks for exact polynomial arithmetic.
#
# Wall-clock needs the compiled binary:
#
#   bin/tungsten -o /tmp/poly_bench benchmarks/algebra/poly_bench.w && /tmp/poly_bench
#
# `bin/tungsten run` prints work counters only (no clock ccall in the interpreter).

use algebra

-> time_multiplies(label, left, right, rounds)
  i = 0
  acc = left.ring.zero
  t0 = ccall("__w_clock_ms")
  while i < rounds
    acc = left * right
    i += 1
  t1 = ccall("__w_clock_ms")
  ms = t1 - t0
  per = ms == 0 ? 0 : (ms * 1000) / rounds
  << label + " rounds=" + rounds.to_s + " total_ms=" + ms.to_s + " us_per_op≈" + per.to_s + " terms=" + acc.terms.size.to_s

-> work_multiplies(label, left, right, rounds)
  i = 0
  acc = left.ring.zero
  while i < rounds
    acc = left * right
    i += 1
  << label + " rounds=" + rounds.to_s + " terms=" + acc.terms.size.to_s + " degree=" + acc.degree.to_s

ring = PolynomialRing.new([:x], RationalField.new, :grevlex)
x = ring.generator(0)

dense_a = ring.zero
dense_b = ring.zero
i = 0
while i <= 25
  dense_a = dense_a + x**i
  dense_b = dense_b + x**i * (i + 1)
  i += 1

sparse_a = x**40 + x**3 + 1
sparse_b = x**37 + x**11 + x + 2

multi = PolynomialRing.new([:x, :y, :z], RationalField.new, :grevlex)
mx = multi.generator(0)
my = multi.generator(1)
mz = multi.generator(2)
multi_a = mx**5 + my**5 + mz**5 + mx * my * mz
multi_b = (mx + my + mz)**3

<< "algebra poly bench"
# Compiled builds resolve __w_clock_ms; the tree-walker does not. Prefer
# wall-clock when available by compiling this file.
work_multiplies("dense_univariate_deg25", dense_a, dense_b, 100)
work_multiplies("sparse_univariate", sparse_a, sparse_b, 200)
work_multiplies("multivariate_grevlex", multi_a, multi_b, 30)

gb_ring = PolynomialRing.new([:a, :b], RationalField.new, :lex)
a = gb_ring.generator(0)
b = gb_ring.generator(1)
gb = GroebnerBasis.basis([a * b - 1, b**2 - a])
<< "ideal_gb basis_size=" + gb.size.to_s

f5 = FiniteField.new(5)
fr = PolynomialRing.new([:t], f5)
t = fr.generator(0)
fa = fr.zero
fb = fr.zero
i = 0
while i <= 20
  fa = fa + t**i
  fb = fb + t**i * 2
  i += 1
work_multiplies("dense_f5_deg20", fa, fb, 150)

<< "poly_bench done"
