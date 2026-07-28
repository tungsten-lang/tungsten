# Engine-parity and exact-algorithm regressions for the algebra core.
#
# Covers the operator-dispatch fixes (`==`/`!=` on algebra values, overloaded
# constructor arity), the exact determinant, the subresultant-PRS resultant
# against its Sylvester oracle, cubic Galois groups, power-table evaluation,
# and the Buchberger engine against the S-polynomial criterion.
# Run in both engines:
#   bin/tungsten run spec/core/algebra_engine_spec.w
#   bin/tungsten compile spec/core/algebra_engine_spec.w --out /tmp/algebra-engine-spec

use algebra

-> check(name, got, want)
  if got != want
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

# --- operator equality dispatches to the structural == overrides ---------

x = Poly<ℚ>.new(:x).generator
check("eq.polynomial_structural", x**2 + 1 == x**2 + 1, true)
check("eq.polynomial_unequal", x**2 + 1 == x**2 - 1, false)
check("neq.polynomial", x**2 + 1 != x**2 + 1, false)
check("eq.polynomial_coerced_constant", x - x + 5 == 5, true)

ring_a = Poly<ℚ>.new(:x).ring
ring_b = Poly<ℚ>.new(:x).ring
check("eq.ring_cross_instance", ring_a == ring_b, true)
cross = ring_a.generator(0) + ring_b.generator(0)
check("eq.cross_instance_arithmetic", cross, ring_a.generator(0) * 2)

# --- overloaded constructors resolve by arity -----------------------------

r1 = PolynomialRing.new([:x, :y])
check("ctor.default_field", r1.field.class_name, "RationalField")
check("ctor.default_order", r1.order.to_s, "grevlex")
r2 = PolynomialRing.new([:x, :y], RationalField.new, :lex)
check("ctor.explicit_order", r2.order.to_s, "lex")
check("ctor.to_s", r2.to_s, "ℚ\[x, y; lex\]")

# --- monomial-order ties return equal, never raise ------------------------

check("order.grevlex_tie", r1.monomial_compare([1, 2], [1, 2]), 0)
check("order.lex_tie", r2.monomial_compare([3, 0], [3, 0]), 0)

# --- exact Gaussian determinant over ℚ ------------------------------------

check("det.integer", Algebra.determinant([[1, 2], [3, 4]]), Rational.new(-2))
check("det.rational",
      Algebra.determinant([[Rational.new(1, 2), Rational.new(1, 3)],
                           [Rational.new(1, 4), Rational.new(1, 5)]]),
      Rational.new(1, 60))
check("det.singular",
      Algebra.determinant([[1, 2, 3], [4, 5, 6], [7, 8, 9]]), Rational.new(0))
check("det.four_by_four",
      Algebra.determinant([[2, 0, 1, 3], [1, -1, 4, 0],
                           [0, 2, -2, 1], [5, 1, 0, -3]]),
      Rational.new(116))
check("det.empty", Algebra.determinant([]), Rational.new(1))

# --- subresultant PRS agrees with the Sylvester oracle --------------------

-> check_resultant(name, f, g)
  check("resultant." + name, f.resultant(g), f.sylvester_resultant(g))

check_resultant("high_degree", x**5 - x**3 * 3 + x * 2 - 7, x**4 + x**2 - 1)
check_resultant("non_monic", x**4 * 6 - x**2 * 3 + x - 1, x**3 * 4 + x * 2 - 9)
check_resultant("rational_coefficients",
                x**3 * Rational.new(3, 2) + x * Rational.new(1, 3) - 1,
                x**2 * Rational.new(2, 5) + x - Rational.new(7, 2))
check_resultant("common_root", (x - 2) * (x**2 + 1), (x - 2) * (x + 5))
check_resultant("swapped_degrees", x**2 + x + 1, x**5 - x - 1)
check("resultant.known_value", (x**2 - 2).resultant(x - 1), Rational.new(-1))
check("discriminant.prs_path", (x**3 - x).discriminant, Rational.new(4))

# --- cubic Galois groups ---------------------------------------------------

check("galois.split_cubic", GaloisGroup.of_cubic(x**3 - x), GaloisGroup.new("C1", 1))
check("galois.one_rational_root",
      GaloisGroup.of_cubic(x**3 - x**2 + x - 1), GaloisGroup.new("C2", 2))
check("galois.irreducible_nonsquare_disc",
      GaloisGroup.of_cubic(x**3 - 2), GaloisGroup.new("S3", 6))
check("galois.irreducible_square_disc",
      GaloisGroup.of_cubic(x**3 - x * 3 - 1), GaloisGroup.new("A3", 3))
check("galois.weil_cubic",
      WeilCubic.new(x**3 + x + 1).galois_group, GaloisGroup.new("S3", 6))
inseparable_raised = false
begin
  GaloisGroup.of_cubic(x**3)
rescue error
  inseparable_raised = "[error]".include?("separable")
check("galois.inseparable_is_loud", inseparable_raised, true)

# --- power-table evaluation -------------------------------------------------

r3 = PolynomialRing.new([:u, :v])
gens = r3.generators
p = gens[0] ** 2 * gens[1] + 3
check("evaluate.integers", p.evaluate([2, 5]), Rational.new(23))
check("evaluate.rationals", p.evaluate([Rational.new(1, 2), 4]), Rational.new(4))
check("evaluate.matches_at", (x**4 - x + 1).evaluate([7]), (x**4 - x + 1).at(7))

# --- Buchberger engine passes its own criterion -----------------------------

-> groebner_valid?(gens)
  gb = GroebnerBasis.basis(gens)
  ok = true
  gens.each ->
    ok = false if !item.normal_form(gb).zero?
  i = 0
  while i < gb.size
    j = 0
    while j < i
      spoly = GroebnerBasis.s_polynomial(gb[i], gb[j])
      ok = false if !spoly.normal_form(gb).zero?
      j += 1
    i += 1
  ok

vars = PolynomialRing.new([:x, :y, :z])
g = vars.generators
gx = g[0]
gy = g[1]
gz = g[2]
check("groebner.twisted_cubic", groebner_valid?([gy - gx**2, gz - gx**3]), true)
check("groebner.cyclic_3",
      groebner_valid?([gx + gy + gz, gx*gy + gy*gz + gz*gx, gx*gy*gz - 1]), true)
check("groebner.katsura_3",
      groebner_valid?([gx + gy * 2 + gz * 2 - 1,
                       gx**2 + gy**2 * 2 + gz**2 * 2 - gx,
                       gx*gy * 2 + gy*gz * 2 - gy]), true)
check("groebner.unit_ideal",
      GroebnerBasis.unit_ideal?([gx, gx + 1]), true)
check("groebner.zero_ideal_empty_basis",
      GroebnerBasis.basis([vars.zero]).size, 0)

# Reduced bases are canonical: generator order must not matter.
canonical_a = GroebnerBasis.basis([gx + gy + gz, gx*gy + gy*gz + gz*gx, gx*gy*gz - 1])
canonical_b = GroebnerBasis.basis([gx*gy*gz - 1, gx + gy + gz, gx*gy + gy*gz + gz*gx])
same = canonical_a.size == canonical_b.size
i = 0
while i < canonical_a.size && same
  same = canonical_a[i] == canonical_b[i]
  i += 1
check("groebner.canonical_under_permutation", same, true)

# --- geometry negatives ------------------------------------------------------

plane = Algebra.rational_projective_plane
coords = plane.coords
cx = coords[0]
cy = coords[1]
cz = coords[2]
nodal = Curve.new(plane, cy*cy*cz - cx**3 - cx*cx*cz)
check("curve.nodal_is_singular", nodal.nonsingular?, false)
check("curve.off_curve_point", nodal.contains?(plane.point(1, 1, 1)), false)
smooth = Curve.new(plane, cx**3 + cy**3 + cz**3)
check("curve.fermat_cubic_smooth", smooth.nonsingular?, true)
check("curve.fermat_genus", smooth.genus, 1)

# --- formal antiderivatives and exact definite integrals --------------------

cubic_rate = x**2 * 3 + x * 2 + 1
check("antiderivative.power_rule", cubic_rate.antiderivative, x**3 + x**2 + x)
check("antiderivative.derivative_round_trip",
      cubic_rate.antiderivative.derivative(0), cubic_rate)
check("antiderivative.rational_coefficient",
      x.antiderivative, x**2 * Rational.new(1, 2))
check("antiderivative.zero", (x - x).antiderivative, x - x)

gu = gens[0]
gv = gens[1]
mixed = gu**2 * gv + 3
check("antiderivative.partial",
      mixed.antiderivative(:v), gu**2 * gv**2 * Rational.new(1, 2) + gv * 3)
check("antiderivative.partial_round_trip",
      mixed.antiderivative(:u).derivative(:u), mixed)
needs_variable = false
begin
  mixed.antiderivative
rescue error
  needs_variable = "[error]".include?("needs a variable")
check("antiderivative.multivariate_needs_variable", needs_variable, true)

check("substitute.partial_evaluation",
      mixed.substitute(:v, 2), gu**2 * 2 + 3)
check("substitute.matches_evaluate",
      mixed.substitute(:u, 3).substitute(:v, 5),
      r3.constant(mixed.evaluate([3, 5])))

check("integral.monomial", (x**2).definite_integral(0, 1), Rational.new(1, 3))
check("integral.odd_symmetric", (x**3).definite_integral(-1, 1), Rational.new(0))
check("integral.rational_bounds",
      (x * 2).definite_integral(Rational.new(1, 2), 1), Rational.new(3, 4))
check("integral.multivariate",
      mixed.definite_integral(:v, 0, 2), gu**2 * 2 + 6)

<< "algebra_engine_spec: all checks passed"
