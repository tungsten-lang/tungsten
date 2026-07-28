# Exact finite-field regressions. Elements stay Integer-encoded; all arithmetic
# is interpreted through the owning Field object.

use algebra

-> finite_check(name, got, want)
  if got != want
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

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
finite_check("prime.projective_normalization",
             f5.normalize_projective_coordinates([2, 4, 0]).to_s,
             "\[1, 2, 0\]")

f25 = FiniteField.new(5, [2, 0, 1])
t25 = f25.encode_coefficients([0, 1])
finite_check("extension.degree", f25.degree, 2)
finite_check("extension.order", f25.order, 25)
finite_check("extension.t_squared", f25.multiply(t25, t25), 3)
finite_check("extension.inverse", f25.multiply(t25, f25.inverse(t25)), 1)

f125 = FiniteField.new(5, [1, 1, 0, 1])
t125 = f125.encode_coefficients([0, 1])
finite_check("cubic_extension.order", f125.order, 125)
finite_check("cubic_extension.relation",
             f125.power(t125, 3), f125.encode_coefficients([4, 4]))

auto25 = FiniteField.extension(5, 2)
auto125 = f5.extension(3)
finite_check("extension.auto_quadratic", auto25.order, 25)
finite_check("extension.auto_cubic", auto125.order, 125)

field_axioms = true
f25.each_element -> (a)
  f25.each_element -> (b)
    field_axioms = false if f25.add(a, b) != f25.add(b, a)
    field_axioms = false if f25.multiply(a, b) != f25.multiply(b, a)
    if a != 0
      field_axioms = false if f25.multiply(a, f25.inverse(a)) != 1
finite_check("extension.field_axioms", field_axioms, true)

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

<< "algebra_finite_field_spec: all checks passed"
