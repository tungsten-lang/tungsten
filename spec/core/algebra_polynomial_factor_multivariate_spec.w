# Bivariate factorization over finite fields (Hensel lifting) regressions.
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
# Three and four variables route through Kronecker substitution
# (mf_factor_entries_kronecker). That path is present but not exercised here:
# the smallest trivariate product did not finish within ten minutes, so it is
# documented as experimental in doc/algebra.md until the recombination search
# is made practical.

<< "algebra_polynomial_factor_multivariate_spec: all checks passed"
