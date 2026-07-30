# Exact finite-field regressions. Elements stay Integer-encoded; all arithmetic
# is interpreted through the owning Field object.

use algebra

-> finite_check(name, got, want)
  if got != want
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

-> monic_irreducible_count(field, degree)
  count = 0
  code = 0
  limit = field.characteristic ** degree
  while code < limit
    remaining = code
    coefficients = []
    i = 0
    while i < degree
      coefficients.push(remaining % field.characteristic)
      remaining = remaining / field.characteristic
      i += 1
    coefficients.push(1)
    count += 1 if field.modulus_irreducible?(coefficients)
    code += 1
  count

f5 = FiniteField.new(5)
finite_check("prime.characteristic", f5.characteristic, 5)
finite_check("prime.degree", f5.degree, 1)
finite_check("prime.order", f5.order, 5)
finite_check("prime.coerce_negative", f5.coerce(-1), 4)
finite_check("prime.add", f5.add(4, 3), 2)
finite_check("prime.subtract", f5.subtract(1, 4), 2)
finite_check("prime.multiply", f5.multiply(3, 4), 2)
finite_check("prime.inverse", f5.inverse(2), 3)
finite_check("prime.divide", f5.divide(3, 2), 4)
finite_check("prime.rational_coercion", f5.coerce(Rational.new(1, 2)), 3)
finite_check("prime.zero_is_square", f5.square?(0), true)
finite_check("prime.square", f5.square?(4), true)
finite_check("prime.nonsquare", f5.square?(2), false)
finite_check("prime.quadratic_character_zero",
             f5.quadratic_character(0), 0)
finite_check("prime.quadratic_character_square",
             f5.quadratic_character(4), 1)
finite_check("prime.quadratic_character_nonsquare",
             f5.quadratic_character(2), -1)
finite_check("prime.projective_normalization",
             f5.normalize_projective_coordinates([2, 4, 0]).to_s,
             "\[1, 2, 0\]")

f25 = FiniteField.new(5, [2, 0, 1])
t25 = f25.encode_coefficients([0, 1])
finite_check("extension.degree", f25.degree, 2)
finite_check("extension.order", f25.order, 25)
finite_check("extension.t_squared", f25.multiply(t25, t25), 3)
finite_check("extension.inverse", f25.multiply(t25, f25.inverse(t25)), 1)
finite_check("extension.square", f25.square?(f25.power(t25, 2)), true)
finite_check("extension.nonsquare", f25.square?(t25), false)
finite_check("extension.quadratic_character",
             f25.quadratic_character(t25), -1)

f125 = FiniteField.new(5, [1, 1, 0, 1])
t125 = f125.encode_coefficients([0, 1])
finite_check("cubic_extension.order", f125.order, 125)
finite_check("cubic_extension.relation",
             f125.power(t125, 3), f125.encode_coefficients([4, 4]))

auto25 = FiniteField.extension(5, 2)
auto125 = f5.extension(3)
finite_check("extension.auto_quadratic", auto25.order, 25)
finite_check("extension.auto_cubic", auto125.order, 125)

# Rabin-certified extensions and the packed base-p representation are
# degree-generic. The deterministic degree-four modulus over F_2 is
# x^4+x+1; unlike a mere root test, the certificate rejects rootless products
# of irreducible quadratics.
f16 = FiniteField.extension(2, 4)
t16 = f16.generator
finite_check("quartic_extension.order", f16.order, 16)
finite_check("quartic_extension.modulus",
             f16.modulus.to_s, "\[1, 1, 0, 0, 1\]")
finite_check("quartic_extension.modulus_certificate",
             f16.modulus_certificate.verified?, true)
finite_check("quartic_extension.relation",
             f16.power(t16, 4), f16.encode_coefficients([1, 1]))
finite_check("quartic_extension.inverse",
             f16.multiply(t16, f16.inverse(t16)), f16.one)
finite_check("quartic_extension.power_basis",
             f16.power_basis.size, 4)
finite_check("quartic_extension.frobenius_period",
             f16.frobenius(t16, 4), t16)
finite_check("quartic_extension.inverse_frobenius",
             f16.inverse_frobenius(f16.frobenius(t16)), t16)
finite_check("quartic_extension.trace", f16.trace(t16), 0)
finite_check("quartic_extension.norm", f16.norm(t16), 1)
finite_check("characteristic_two.every_element_square",
             f16.square?(t16), true)

characteristic_two_character_failed = false
begin
  f16.quadratic_character(t16)
rescue error
  characteristic_two_character_failed = "[error]".include?(
    "characteristic two")
finite_check("characteristic_two.signed_character_is_loud",
             characteristic_two_character_failed, true)

r2 = PolynomialRing.new([:x], FiniteField.new(2))
x2 = r2.generator(0)
finite_check("quartic_extension.minimal_polynomial",
             f16.minimal_polynomial(t16, :x),
             x2**4 + x2 + 1)
finite_check("quartic_extension.minimal_polynomial_certificate",
             f16.minimal_polynomial_certificate(t16, :x).verified?, true)
subfield_element = f16.add(t16, f16.frobenius(t16))
finite_check("quartic_extension.subfield_orbit",
             f16.frobenius_orbit(subfield_element).size, 2)
finite_check("quartic_extension.subfield_minimal_polynomial",
             f16.minimal_polynomial(subfield_element, :x),
             x2**2 + x2 + 1)
nonminimal_finite_certificate = FiniteFieldMinimalPolynomialCertificate.new(
  f16, subfield_element, (x2**2 + x2 + 1)**2)
finite_check("quartic_extension.minimal_certificate_rejects_charpoly",
             nonminimal_finite_certificate.verified?, false)

f256 = FiniteField.extension(2, 8)
t256 = f256.generator
finite_check("degree_eight_extension.order", f256.order, 256)
finite_check("degree_eight_extension.modulus_certificate",
             f256.modulus_certificate.verified?, true)
finite_check("degree_eight_extension.inverse",
             f256.multiply(t256, f256.inverse(t256)), f256.one)
finite_check("degree_eight_extension.orbit",
             f256.frobenius_orbit(t256).size, 8)
finite_check("rabin.irreducible_count.F2.degree4",
             monic_irreducible_count(FiniteField.new(2), 4), 3)
finite_check("rabin.irreducible_count.F2.degree6",
             monic_irreducible_count(FiniteField.new(2), 6), 9)
finite_check("rabin.irreducible_count.F2.degree8",
             monic_irreducible_count(FiniteField.new(2), 8), 30)
finite_check("rabin.irreducible_count.F3.degree4",
             monic_irreducible_count(FiniteField.new(3), 4), 18)

field_axioms = true
f25.each_element -> (a)
  f25.each_element -> (b)
    field_axioms = false if f25.add(a, b) != f25.add(b, a)
    field_axioms = false if f25.multiply(a, b) != f25.multiply(b, a)
    if a != 0
      field_axioms = false if f25.multiply(a, f25.inverse(a)) != 1
finite_check("extension.field_axioms", field_axioms, true)

quartic_field_axioms = true
f16.each_element -> (a)
  f16.each_element -> (b)
    quartic_field_axioms = false if f16.add(a, b) != f16.add(b, a)
    quartic_field_axioms = false if f16.multiply(a, b) != f16.multiply(b, a)
    if a != 0
      quartic_field_axioms = false if f16.multiply(a, f16.inverse(a)) != 1
finite_check("quartic_extension.field_axioms", quartic_field_axioms, true)

# Polynomial arithmetic must never fall back to Integer operations: every
# coefficient is reduced by the owning finite field.
r5 = PolynomialRing.new([:x], f5)
x5 = r5.generator(0)
finite_check("polynomial.add_reduces",
             x5*3 + x5*4, x5*2)
finite_check("polynomial.multiply_reduces",
             (x5 + 4) * (x5 + 1), x5**2 + 4)
division5 = (x5**2 + 4).divmod(x5 + 1)
finite_check("polynomial.quotient", division5[0], x5 + 4)
finite_check("polynomial.remainder", division5[1], r5.zero)
finite_check("polynomial.derivative_characteristic",
             (x5**5 + x5**2*2).derivative(0), x5*4)
finite_check("polynomial.evaluate",
             (x5**2 + x5*2 + 3).at(4), 2)
finite_check("polynomial.discriminant",
             (x5**3 - x5).discriminant, 4)
finite_check("field.determinant",
             Algebra.determinant([[1, 2], [3, 4]], f5), 3)

gcd5 = (x5**2 - 1).gcd(x5**2 + x5*2 + 1)
finite_check("polynomial.gcd", gcd5, x5 + 1)

rxy5 = PolynomialRing.new([:x, :y], f5)
xy5 = rxy5.generators
gx5 = xy5[0]
gy5 = xy5[1]
gb5 = GroebnerBasis.new([gx5*gy5 - 1, gy5**2 - 1])
finite_check("groebner.membership", gb5.contains?(gx5 - gy5), true)
finite_check("groebner.unit_ideal",
             GroebnerBasis.new([gx5, gx5 - 1]).unit?, true)

# Encoded extension elements are internal field values, not Integers to be
# embedded again through the prime subfield.
r25 = PolynomialRing.new([:u], f25)
u25 = r25.generator(0)
t25_constant = r25.monomial_raw(t25, [0])
finite_check("extension_polynomial.monomial_external_integer",
             r25.monomial(5, [0]), r25.zero)
finite_check("extension_polynomial.monomial_raw_integer",
             r25.monomial_raw(5, [0]), t25_constant)
finite_check("extension_polynomial.evaluate_raw_element",
             (u25 + t25_constant).at_raw(t25), f25.add(t25, t25))
finite_check("extension_polynomial.at_external_integer",
             u25.at(5), f25.zero)
finite_check("extension_polynomial.at_raw_integer",
             u25.at_raw(5), t25)
finite_check("extension_polynomial.evaluate_external_integer",
             u25.evaluate([5]), f25.zero)
finite_check("extension_polynomial.evaluate_raw_integer",
             u25.evaluate_raw([5]), t25)
uv25_ring = PolynomialRing.new([:u, :v], f25)
uv25 = uv25_ring.generators
u25_multi = uv25[0]
v25_multi = uv25[1]
finite_check("extension_polynomial.substitute_external_integer",
             (u25_multi + v25_multi).substitute(:u, 5), v25_multi)
finite_check("extension_polynomial.substitute_raw_integer",
             u25_multi.substitute_raw(:u, 5),
             uv25_ring.monomial_raw(t25, [0, 0]))
finite_check("extension_polynomial.monomial_multiply_external_integer",
             u25.monomial_multiply([0], 5), r25.zero)
finite_check("extension_polynomial.monomial_multiply_raw_integer",
             u25.monomial_multiply_raw([0], 5), u25 * t25_constant)
finite_check("extension_determinant.external_integer",
             Algebra.determinant([[5]], f25), f25.zero)
finite_check("extension_determinant.raw_integer",
             Algebra.determinant_raw([[5]], f25), t25)
finite_check("extension_polynomial.multiply_constant",
             (t25_constant * t25_constant).coeff(0), 3)
finite_check("extension_polynomial.resultant",
             (u25**2 - t25_constant).resultant(u25 - t25_constant),
             f25.subtract(3, t25))

p2f5 = ProjectiveSpace<FiniteField, 2>.new(
  Algebra.field(f5), 2, [:X, :Y, :Z])
point5 = p2f5.point([2, 4, 0])
finite_check("projective.prime_normalization",
             point5.coordinates.to_s, "\[1, 2, 0\]")
finite_check("projective.prime_chart", point5.chart(0).to_s, "\[2, 0\]")

p1f25 = ProjectiveSpace<FiniteField, 1>.new(
  Algebra.field(f25), 1, [:U, :V])
point25 = p1f25.point_raw([t25, 1])
finite_check("projective.extension_chart_raw_element",
             point25.chart(1).to_s, [t25].to_s)
finite_check("projective.extension_round_trip",
             p1f25.homogenize_raw([t25], 1), point25)
finite_check("projective.extension_external_integer",
             p1f25.point([1, 5]).coordinates.to_s, [1, 0].to_s)
finite_check("projective.extension_index_external_integer",
             p1f25[1:5].coordinates.to_s, [1, 0].to_s)
finite_check("projective.extension_raw_integer",
             p1f25.point_raw([1, 5]).coordinates.to_s, [1, t25].to_s)

# The algebra-local generic rewrite accepts mathematical finite-field tags;
# the runtime field object, not the tag spelling, owns the arithmetic.
surface_p2 = ProjectiveSpace<𝔽_5, 2>.new(:A, :B, :C)
surface_x = Poly<𝔽_5>.new(:x).generator
finite_check("surface.projective_f5", surface_p2.field, f5)
finite_check("surface.poly_f5", (surface_x**5 - surface_x).at(3), 0)

composite_failed = false
begin
  FiniteField.new(9)
rescue error
  composite_failed = "[error]".include?("must be prime")
finite_check("composite_characteristic_is_loud", composite_failed, true)

reducible_failed = false
begin
  FiniteField.new(5, [4, 0, 1])
rescue error
  reducible_failed = "[error]".include?("irreducible")
finite_check("reducible_modulus_is_loud", reducible_failed, true)

rootless_reducible_failed = false
begin
  # x^4+x^2+1 = (x^2+x+1)^2 over F_2, but has no F_2-root.
  FiniteField.new(2, [1, 0, 1, 0, 1])
rescue error
  rootless_reducible_failed = "[error]".include?("irreducible")
finite_check("rootless_reducible_modulus_is_loud",
             rootless_reducible_failed, true)

extension_search_unknown = false
begin
  FiniteField.extension(2, 8, 1)
rescue error
  extension_search_unknown = "[error]".include?(
    "extension construction unknown")
finite_check("extension_search_limit_is_loud",
             extension_search_unknown, true)

# Polynomial arithmetic over 𝔽_p routes coefficients through the field, so
# residues never escape as unreduced Integers.
ring = PolynomialRing.new([:x], f5)
x = ring.generator(0)
finite_check("poly.constant_add", (ring.constant(3) + ring.constant(3)).to_s, "1")
finite_check("poly.freshman_dream", ((x + 1)**5).to_s, "x^5 + 1")
finite_check("poly.product", ((x + 2) * (x + 3)).to_s, "x^2 + 1")
finite_check("poly.evaluate", (x**2 + 1).at(2), 0)
finite_check("poly.gcd", ((x**2 - 1).gcd(x - 1)).to_s, "x + 4")

# Short Weierstrass group law over a small prime field.
plane = ProjectiveSpace<FiniteField, 2>.new(
  Algebra.field(f5), 2, [:X, :Y, :Z])
# y^2 = x^3 + 1 over F_5 has discriminant -432 ≡ 3 (mod 5), nonsingular.
curve = EllipticCurve.new(plane, 0, 1)
finite_check("elliptic.fp.nonsingular", curve.nonsingular?, true)
finite_check("elliptic.fp.jacobian_class", curve.jacobian.class_name, "EllipticJacobian")
p = curve.point(0, 1)
finite_check("elliptic.fp.inverse", (p + (-p)).identity?, true)
finite_check("elliptic.fp.double_on_curve", curve.contains?(p + p), true)

plane25 = ProjectiveSpace<FiniteField, 2>.new(
  Algebra.field(f25), 2, [:X, :Y, :Z])
curve25 = EllipticCurve.new(plane25, 0, 1)
finite_check("elliptic.extension.external_integer",
             curve25.point(5, 1).x, f25.zero)
finite_check("elliptic.extension.raw_integer",
             curve25.point_raw(5, 12).x, t25)

# A smooth plane quintic has genus six, so its zeta workflow constructs and
# counts over extension degrees one through six. This is the end-to-end
# regression that the historical cubic cap made impossible.
plane2 = ProjectiveSpace<FiniteField, 2>.new(
  Algebra.field(FiniteField.new(2)), 2, [:X, :Y, :Z])
fermat_coordinates = plane2.coords
fermat_quintic = Curve.new(
  plane2,
  fermat_coordinates[0]**5 +
    fermat_coordinates[1]**5 +
    fermat_coordinates[2]**5)
fermat_zeta = fermat_quintic.zeta
finite_check("geometry.genus_six", fermat_quintic.genus, 6)
finite_check("geometry.genus_six_extension_counts",
             fermat_zeta.counts.to_s, "\[3, 5, 9, 65, 33, 65\]")
finite_check("geometry.genus_six_zeta_degree",
             fermat_zeta.numerator.degree, 12)
finite_check("geometry.genus_six_zeta_numerator",
             fermat_zeta.numerator.to_s,
             "64T^12 + 48T^8 + 12T^4 + 1")

<< "algebra_finite_field_spec: all checks passed"
