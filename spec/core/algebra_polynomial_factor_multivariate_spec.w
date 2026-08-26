# Multivariate factorization over finite fields (Hensel lifting) regressions.
# Run both ways:
#   bin/tungsten run spec/core/algebra_polynomial_factor_multivariate_spec.w
#   bin/tungsten compile spec/core/algebra_polynomial_factor_multivariate_spec.w --out /tmp/algebra-polynomial-factor-multivariate-spec

use algebra

-> mf_check(name, got, want)
  equal = got == want
  if got.class_name == "Polynomial"
    equal = got.eql?(want)
  elsif got.class_name == "Array"
    equal = got.to_s == want.to_s
  if !equal
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

-> mf_product(polynomial, entries)
  product = polynomial.ring.one
  entries.each -> (entry)
    product = product * (entry[0] ** entry[1])
  product

-> mf_nonconstant_count(entries)
  count = 0
  entries.each -> (entry)
    count += 1 if !entry[0].constant?
  count

-> mf_multiplicities(entries)
  out = []
  entries.each -> (entry)
    out.push(entry[1]) if !entry[0].constant?
  out.sort

# F_101: 2 is a quadratic non-residue (101 = 5 mod 8), so y^2 - 2x^2 is
# irreducible over F_101 but splits over F_101^2.
f101 = FiniteField.new(101)
r101 = PolynomialRing.new([:x, :y], f101, :grevlex)
x, y = r101.generators

quadric = y**2 - x**2 * 2
line = x * y + x * 3 + 1
cubic = y + x**2 + 5
product3 = quadric * line * cubic
entries3 = product3.factor_multivariate
mf_check("F101.three_factors.count", mf_nonconstant_count(entries3), 3)
mf_check("F101.three_factors.product", mf_product(product3, entries3), product3)
mf_check("F101.three_factors.multiplicities", mf_multiplicities(entries3), [1, 1, 1])
mf_check("F101.three_factors.certified",
         product3.factor_multivariate_with_certificate.verified?, true)

repeated = (y + x)**2 * quadric**3 * (x * y + 1)
entries_repeated = repeated.factor_multivariate
mf_check("F101.repeated.count", mf_nonconstant_count(entries_repeated), 3)
mf_check("F101.repeated.multiplicities", mf_multiplicities(entries_repeated), [1, 2, 3])
mf_check("F101.repeated.product", mf_product(repeated, entries_repeated), repeated)

# Content in the main variable: x^2 - 2 is irreducible over F_101.
with_content = (x**2 - 2) * quadric * (y + x)
entries_content = with_content.factor_multivariate
mf_check("F101.content.count", mf_nonconstant_count(entries_content), 3)
mf_check("F101.content.product", mf_product(with_content, entries_content), with_content)
x_only = 0
entries_content.each -> (entry)
  x_only += 1 if !entry[0].constant? && entry[0].degree_in(:y) == 0
mf_check("F101.content.x_only_factor_count", x_only, 1)

# Unit and a factor whose leading coefficient in y vanishes at x = 0.
scaled = (x * y + x * 3 + 1) * (y**2 + x * y + 1) * 7
entries_scaled = scaled.factor_multivariate
mf_check("F101.unit.first_entry_constant", entries_scaled[0][0].constant?, true)
mf_check("F101.unit.count", mf_nonconstant_count(entries_scaled), 2)
mf_check("F101.unit.product", mf_product(scaled, entries_scaled), scaled)

# Irreducible input returns itself.
irreducible = y**3 + x * y + x**2 + 1
entries_irreducible = irreducible.factor_multivariate
mf_check("F101.irreducible.count", mf_nonconstant_count(entries_irreducible), 1)
mf_check("F101.irreducible.factor", entries_irreducible[0][0], irreducible.monic)

# Inseparable in y: y^101 - x has zero y-derivative and is irreducible
# (linear in x); a genuine p-th power is detected too.
inseparable = (y**101 - x) * (y + 1)
entries_inseparable = inseparable.factor_multivariate
mf_check("F101.inseparable.count", mf_nonconstant_count(entries_inseparable), 2)
mf_check("F101.inseparable.product", mf_product(inseparable, entries_inseparable), inseparable)
pth_power = (y + x)**101
entries_pth = pth_power.factor_multivariate
mf_check("F101.pth_power.count", mf_nonconstant_count(entries_pth), 1)
mf_check("F101.pth_power.multiplicity", mf_multiplicities(entries_pth), [101])

# Flat factor list.
flat = quadric * cubic
flat_nonconstant = 0
flat.multivariate_factors.each -> (factor)
  flat_nonconstant += 1 if !factor.constant?
mf_check("F101.flat.nonconstant_size", flat_nonconstant, 2)

# F_10007 with moderate degrees.
f10007 = FiniteField.new(10007)
r10007 = PolynomialRing.new([:x, :y], f10007, :grevlex)
u, v = r10007.generators
big = (v**2 + u * v + 1) * (v**3 + u) * (u + 2) * (v * u**2 + v * 5 + u + 1)
entries_big = big.factor_multivariate
mf_check("F10007.count", mf_nonconstant_count(entries_big), 4)
mf_check("F10007.product", mf_product(big, entries_big), big)
mf_check("F10007.certified", big.factor_multivariate_with_certificate.verified?, true)

# Certificate rejects a wrong factorization.
bad = PolynomialMultivariateFactorization.new(big, [[v**2 + u * v + 1, 1], [v**3 + u, 1]])
mf_check("certificate.rejects_incomplete", bad.verified?, false)

# ---------------------------------------------------------------------
# Three and four variables: Hensel lifting modulo the ideal of the auxiliary
# variables (mf_factor_squarefree_hensel). Every planted factor below is
# irreducible by inspection (linear in some variable with coprime
# coefficients, or a quadratic in y whose discriminant is not a square), so
# the returned monic factors must equal the planted ones as a multiset.

-> mf_sorted_factors(entries)
  out = []
  entries.each -> (entry)
    if !entry[0].constant?
      i = 0
      while i < entry[1]
        out.push(entry[0].monic.to_s)
        i += 1
  out.sort

-> mf_planted(list)
  out = []
  list.each -> out.push(item.monic.to_s)
  out.sort

-> mf_check_planted(name, factors)
  product = factors[0].ring.one
  factors.each -> product = product * item
  entries = product.factor_multivariate
  mf_check(name + ".factors", mf_sorted_factors(entries), mf_planted(factors))
  mf_check(name + ".product", mf_product(product, entries), product)

r3 = PolynomialRing.new([:x, :y, :z], f101, :grevlex)
x3, y3, z3 = r3.generators
mf_check_planted("F101.3var.leading_coefficient",
                 [y3**2 + x3 * z3 + 1, y3**2 + x3 + z3, x3 * z3 * y3 + x3 + 1])
mf_check_planted("F101.3var.content",
                 [x3**2 + z3, y3 + x3 + z3, y3**2 + x3 * y3 * z3 + 1])
mf_check_planted("F101.3var.repeated",
                 [y3 + x3 * z3, y3 + x3 * z3, y3**2 + x3 + 1, z3 + 1])
mf_check_planted("F101.3var.four",
                 [y3 + x3 + 1, y3 + z3 + 2, y3**2 + x3 * z3 + 3, y3 + x3 * z3 + 4])
mf_check_planted("F101.3var.degree_six",
                 [y3**2 + x3**2 + z3**2 + 1, y3**2 + x3 * z3 + y3 + 1, y3**2 + x3 * y3 + z3 * y3 + x3])
# Every specialization of at least one factor splits (a, b, or ab is a
# square), so the recombination must discard extraneous lifted factors.
mf_check_planted("F101.3var.extraneous",
                 [y3**2 - x3, y3**2 - z3, y3**2 - x3 * z3])
irreducible3 = y3**3 + x3 * y3 * z3 + x3**2 + z3 + 1
entries_irreducible3 = irreducible3.factor_multivariate
mf_check("F101.3var.irreducible", mf_sorted_factors(entries_irreducible3), [irreducible3.to_s])
scaled3 = (y3**2 + x3 * z3 + 1) * (y3 + x3 + z3) * 5
entries_scaled3 = scaled3.factor_multivariate
mf_check("F101.3var.unit.first_entry_constant", entries_scaled3[0][0].constant?, true)
mf_check("F101.3var.unit.product", mf_product(scaled3, entries_scaled3), scaled3)
mf_check("F101.3var.certified",
         ((y3**2 + x3 * z3 + 1) * (x3 * z3 * y3 + x3 + 1)).factor_multivariate_with_certificate.verified?, true)
flat3 = 0
((y3**2 + x3 + z3) * (y3 + x3 * z3 + 4)).multivariate_factors.each -> (factor)
  flat3 += 1 if !factor.constant?
mf_check("F101.3var.flat", flat3, 2)

r4 = PolynomialRing.new([:w, :x, :y, :z], f101, :grevlex)
w4, x4, y4, z4 = r4.generators
mf_check_planted("F101.4var.three",
                 [y4 + w4 * x4 + z4, y4**2 + w4 * z4 + x4 + 1, w4 * y4 + x4 * z4 + 1])
mf_check_planted("F101.4var.leading_coefficient",
                 [w4 * y4 + x4 + z4 + 1, x4 * y4**2 + w4 * z4 * y4 + 1])

# F_2 and F_3: the specialization point is found by exhaustive enumeration.
f2 = FiniteField.new(2)
s3 = PolynomialRing.new([:x, :y, :z], f2, :grevlex)
x2, y2, z2 = s3.generators
mf_check_planted("F2.3var.two", [y2**2 + y2 + x2 * z2 + 1, y2 + x2 + z2])
mf_check_planted("F2.3var.three", [y2**2 + y2 + 1, y2 + x2 * z2, y2 + x2 + z2 + 1])
s4 = PolynomialRing.new([:w, :x, :y, :z], f2, :grevlex)
w2, x2b, y2b, z2b = s4.generators
mf_check_planted("F2.4var", [y2b**2 + y2b + w2 * x2b + 1, y2b + x2b * z2b + w2])

f3 = FiniteField.new(3)
u3 = PolynomialRing.new([:x, :y, :z], f3, :grevlex)
xa, ya, za = u3.generators
mf_check_planted("F3.3var.three", [ya**2 + xa * za + 1, ya + xa + za, ya**2 + ya + 2])
mf_check_planted("F3.3var.leading_coefficient", [xa * ya + za + 1, ya**2 + xa * ya + za])
mf_check_planted("F3.3var.cube", [xa + ya + za, xa + ya + za, xa + ya + za])

# F_4 = F_2[a]/(a^2 + a + 1): y^2 + y + a has no root in F_4.
f4 = FiniteField.new(2, [1, 1, 1])
alpha = f4.element_from_index(2)
v3 = PolynomialRing.new([:x, :y, :z], f4, :grevlex)
xb, yb, zb = v3.generators
alpha3 = v3.monomial_raw(alpha, v3.zero_exponents)
mf_check_planted("F4.3var", [yb**2 + yb + alpha3, yb + alpha3 * xb + zb])

# F_10007 with a cubic factor.
v10007 = PolynomialRing.new([:x, :y, :z], f10007, :grevlex)
xc, yc, zc = v10007.generators
mf_check_planted("F10007.3var", [yc**3 + xc * zc + 1, yc**2 + xc + zc * 5, xc * yc + zc * 7 + 1])

<< "algebra_polynomial_factor_multivariate_spec: all checks passed"
