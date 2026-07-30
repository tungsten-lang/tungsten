# Complete finite-field polynomial-factorization regressions.
# Run both ways:
#   bin/tungsten run spec/core/algebra_finite_factor_spec.w
#   bin/tungsten compile spec/core/algebra_finite_factor_spec.w --out /tmp/algebra-finite-factor-spec

use algebra

-> finite_factor_check(name, got, want)
  equal = got == want
  if got.class_name == "Polynomial"
    equal = got.eql?(want)
  elsif got.class_name == "Array"
    equal = got.to_s == want.to_s
  if !equal
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

-> finite_factor_product(polynomial, factors)
  product = polynomial.ring.one
  factors.each -> product = product * item
  product

# Odd characteristic: linear, repeated, equal-degree, and unit factors.
f5 = FiniteField.new(5)
r5 = PolynomialRing.new([:x], f5)
x5 = r5.generator(0)

split5 = x5**5 - x5
split5_factors = split5.factor
finite_factor_check("F5.all_linear.count", split5_factors.size, 5)
finite_factor_check("F5.all_linear.product",
                    finite_factor_product(split5, split5_factors), split5)
finite_factor_check("F5.all_linear.degrees",
                    split5_factors.map -> item.degree,
                    [1, 1, 1, 1, 1])

irreducible_quadratic5 = x5**2 + 2
repeated5 = (x5 + 1)**2 * irreducible_quadratic5**3
repeated5_factors = repeated5.factor
finite_factor_check("F5.repeated.count", repeated5_factors.size, 5)
finite_factor_check("F5.repeated.product",
                    finite_factor_product(repeated5, repeated5_factors),
                    repeated5)
finite_factor_check("F5.repeated.degrees",
                    repeated5_factors.map -> item.degree,
                    [1, 1, 2, 2, 2])

equal_degree5 = x5**6 + x5 + 1
equal_degree5_factors = equal_degree5.factor
finite_factor_check("F5.equal_degree.count",
                    equal_degree5_factors.size, 2)
finite_factor_check("F5.equal_degree.degrees",
                    equal_degree5_factors.map -> item.degree, [3, 3])
finite_factor_check("F5.equal_degree.product",
                    finite_factor_product(
                      equal_degree5, equal_degree5_factors),
                    equal_degree5)

scaled5 = (x5 + 1) * irreducible_quadratic5 * 3
scaled5_factors = scaled5.factor
finite_factor_check("F5.unit.count", scaled5_factors.size, 3)
finite_factor_check("F5.unit.constant", scaled5_factors[0], r5.constant(3))
finite_factor_check("F5.unit.product",
                    finite_factor_product(scaled5, scaled5_factors),
                    scaled5)

# Characteristic two: inseparable p-th powers and deterministic trace
# splitting. These cases distinguish complete squarefree decomposition from
# a derivative-nonzero-only implementation.
f2 = FiniteField.new(2)
r2 = PolynomialRing.new([:x], f2)
x2 = r2.generator(0)
linear2 = x2 + 1
quadratic2 = x2**2 + x2 + 1

inseparable2 = linear2**2 * quadratic2**3
inseparable2_factors = inseparable2.factor
finite_factor_check("F2.inseparable.count",
                    inseparable2_factors.size, 5)
finite_factor_check("F2.inseparable.degrees",
                    inseparable2_factors.map -> item.degree,
                    [1, 1, 2, 2, 2])
finite_factor_check("F2.inseparable.product",
                    finite_factor_product(
                      inseparable2, inseparable2_factors),
                    inseparable2)

pure_pth_power2 = quadratic2**4
pure_pth_power2_factors = pure_pth_power2.factor
finite_factor_check("F2.pth_power.count",
                    pure_pth_power2_factors.size, 4)
finite_factor_check("F2.pth_power.product",
                    finite_factor_product(
                      pure_pth_power2, pure_pth_power2_factors),
                    pure_pth_power2)

quartic_a2 = x2**4 + x2 + 1
quartic_b2 = x2**4 + x2**3 + 1
equal_degree2 = quartic_a2 * quartic_b2
equal_degree2_factors = equal_degree2.factor
finite_factor_check("F2.equal_degree.count",
                    equal_degree2_factors.size, 2)
finite_factor_check("F2.equal_degree.values",
                    equal_degree2_factors.map -> item.to_s,
                    [quartic_a2.to_s, quartic_b2.to_s])

all_degree_four_elements = x2**16 - x2
all_degree_four_factors = all_degree_four_elements.factor
finite_factor_check("F2.distinct_degree.product",
                    finite_factor_product(
                      all_degree_four_elements,
                      all_degree_four_factors),
                    all_degree_four_elements)
finite_factor_check("F2.distinct_degree.degrees",
                    all_degree_four_factors.map -> item.degree,
                    [1, 1, 2, 4, 4, 4])

# Extension coefficient fields use packed residues as raw coefficients. The
# equal-degree trace has m*d iterations for q=2^m.
f4 = FiniteField.extension(2, 2)
r4 = PolynomialRing.new([:x], f4)
x4 = r4.generator(0)
a4 = r4.monomial_raw(f4.generator, r4.zero_exponents)
quadratic_a4 = x4**2 + x4 + a4
quadratic_b4 = x4**2 + a4*x4 + a4
extension_product = quadratic_a4 * quadratic_b4
extension_factors = extension_product.factor
finite_factor_check("F4.equal_degree.count", extension_factors.size, 2)
finite_factor_check("F4.equal_degree.product",
                    finite_factor_product(
                      extension_product, extension_factors),
                    extension_product)
finite_factor_check("F4.equal_degree.irreducible",
                    extension_factors.map ->
                      item.finite_field_irreducible?,
                    [true, true])

# Certificates replay product and irreducibility, and reject an annihilating
# but reducible "factorization" containing only the source polynomial.
# The local named `factor` also guards native lowering hygiene: method bodies
# must dispatch through `self`, not capture a same-named script binding.
factor = "unrelated local binding"
certified = extension_product.factor_with_certificate
finite_factor_check("certificate.verified",
                    certified.certificate.verified?, true)
finite_factor_check("certificate.factors",
                    certified.factors.map -> item.to_s,
                    extension_factors.map -> item.to_s)
tampered = PolynomialFactorizationCertificate.new(
  extension_product, [extension_product])
finite_factor_check("certificate.rejects_reducible_factor",
                    tampered.verified?, false)

rational_ring = PolynomialRing.new([:t], RationalField.new)
t = rational_ring.generator(0)
rational_factorization = (t**4 - 1).factor_with_certificate
finite_factor_check("certificate.rational_compatibility",
                    rational_factorization.certified?, true)

search_limit_failed = false
begin
  equal_degree2.factor(1)
rescue error
  search_limit_failed = "[error]".include?("factorization unknown")
finite_factor_check("search_limit_is_loud", search_limit_failed, true)

finite_factor_check("zero.factor", r2.zero.factor.size, 1)
finite_factor_check("one.factor", r2.one.factor.size, 1)

<< "algebra_finite_factor_spec: all checks passed"
