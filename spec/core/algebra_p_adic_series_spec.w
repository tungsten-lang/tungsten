# Truncated p-adic series, Newton-polygon zero counts, Weierstrass factors,
# power sums, and Z/p^K kernels with a computed corank.
#
#   bin/tungsten run spec/core/algebra_p_adic_series_spec.w
#   bin/tungsten compile spec/core/algebra_p_adic_series_spec.w \
#     --out /tmp/algebra-p-adic-series-spec

use algebra

-> series_check(name, got, want)
  if got != want
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

ring = PadicSeriesRing.new(5, 12, 16)
modulus = 5 ** 12
series_check("ring.modulus", ring.modulus, modulus)
series_check("ring.valuation.zero", ring.valuation(0), 12)
series_check("ring.valuation.125", ring.valuation(125), 3)
series_check("ring.unit_inverse", (ring.unit_inverse(7) * 7) % modulus, 1)
series_check("ring.divide_power", ring.divide_power(250, 2), 10)

# (1 + t) * (1 + t)^-1 == 1
one_plus_t = ring.series([1, 1])
inverse = one_plus_t.inverse
product = one_plus_t * inverse
series_check("series.inverse.constant", product.coefficient(0), 1)
series_check("series.inverse.tail", product.order == 0 && (product - ring.one).zero?, true)
series_check("series.inverse.alternating", inverse.coefficient(3), modulus - 1)

# derivative and scaled antiderivative round trip
cubic = ring.series([4, 3, 7, 11])
derivative = cubic.derivative
series_check("series.derivative", derivative.coefficient(1), 14)
back = derivative.scaled_antiderivative(4, 0)
series_check("series.antiderivative", (back - cubic + ring.constant(4)).zero?, true)

# scaled antiderivative clears a 5-adic denominator: integral of 3 t^4 is
# 3 t^5 / 5, so the scale exponent 1 returns 3 t^5
quartic_term = ring.series([0, 0, 0, 0, 3])
scaled = quartic_term.scaled_antiderivative(6, 1)
series_check("series.antiderivative.scaled", scaled.coefficient(5), 3)
series_check("series.antiderivative.digits", scaled.known_digits, 12)
raised = false
begin
  quartic_term.scaled_antiderivative(6, 0)
rescue error
  raised = true
series_check("series.antiderivative.denominator_guard", raised, true)

# evaluate by Horner
series_check("series.evaluate", cubic.evaluate(2), 4 + 6 + 28 + 88)

# Weierstrass preparation: phi = (t - 5)(t - 10)(1 + t)
phi = ring.series([modulus - 5, 1]) * ring.series([modulus - 10, 1]) * one_plus_t
series_check("weierstrass.degree", phi.weierstrass_degree, 2)
factor = phi.weierstrass_factor(2)
series_check("weierstrass.factor.c0", factor[0], 50)
series_check("weierstrass.factor.c1", factor[1], modulus - 15)
series_check("weierstrass.factor.monic", factor[2], 1)

# zeros with v(t) >= 1: both roots; with v(t) >= 2: none
count1 = phi.disk_zero_count(1, 100)
series_check("strassmann.radius1", count1[0], 2)
count2 = phi.disk_zero_count(2, 100)
series_check("strassmann.radius2", count2[0], 0)
psi = ring.series([modulus - 25, 1]) * ring.series([modulus - 5, 1]) * one_plus_t
series_check("strassmann.radius2.one_root", psi.disk_zero_count(2, 100)[0], 1)
inconclusive = false
begin
  phi.disk_zero_count(1, 1)
rescue error
  inconclusive = true
series_check("strassmann.tail_guard", inconclusive, true)

# power sums of the roots 5 and 10
sums = PadicSeries.power_sums(factor, 3, modulus)
series_check("power_sums.p1", sums[1], 15)
series_check("power_sums.p2", sums[2], 125)
series_check("power_sums.p3", sums[3], 1125)
cubic_roots = [modulus - 6, 11, modulus - 6, 1]
cubic_sums = PadicSeries.power_sums(cubic_roots, 4, modulus)
series_check("power_sums.cubic.p1", cubic_sums[1], 6)
series_check("power_sums.cubic.p2", cubic_sums[2], 14)
series_check("power_sums.cubic.p4", cubic_sums[4], 98)

# kernels over Z/p^K
kernel = PadicKernel.new([[1, 2, 3], [2, 4, 6]], 3, ring)
series_check("kernel.rank", kernel.rank, 1)
series_check("kernel.dimension", kernel.dimension, 2)
series_check("kernel.lost_digits", kernel.lost_digits, 0)
vector = kernel.vectors[0]
series_check("kernel.vector.replay", (vector[0] + 2 * vector[1] + 3 * vector[2]) % modulus, 0)

pivot_kernel = PadicKernel.new([[5, 1, 0], [0, 5, 1]], 3, ring)
series_check("kernel.valuation.dimension", pivot_kernel.dimension, 1)
series_check("kernel.valuation.lost_digits", pivot_kernel.lost_digits, 2)
primitive = pivot_kernel.primitive_vector(0)
pv = primitive[0]
series_check("kernel.valuation.vector", pv.to_s, "\[1, " + (5 ** 10 - 5).to_s + ", 25\]")
series_check("kernel.valuation.digits", primitive[1], 10)

full_rank = PadicKernel.new([[1, 0], [0, 1]], 2, ring)
series_check("kernel.full_rank.dimension", full_rank.dimension, 0)

<< "algebra_p_adic_series_spec: all checks passed"
