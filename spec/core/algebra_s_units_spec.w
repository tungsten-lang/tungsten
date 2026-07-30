# Exact archimedean places and replay-certified S-unit square classes.

use algebra

-> sunit_check(name, got, want)
  if got != want
    text = "FAIL " + name + ": got " + got.to_s
    raise text + ", want " + want.to_s
  << "PASS " + name

R = PolynomialRing.new([:t], RationalField.new)
t = R.generator(0)

# Q(sqrt(5)) has signature (2,0).  The signs of -1 and the fundamental unit
# (1+sqrt(5))/2 already give a full-rank square-class signature matrix.
K5 = NumberField.new(t**2 - 5, :a)
a5 = K5.generator
epsilon5 = (K5.one + a5) / 2
A5 = K5.archimedean_data
sunit_check("archimedean.real_quadratic.signature",
            A5.signature.to_s, "\[2, 0\]")
sunit_check("archimedean.real_quadratic.place_count",
            A5.places.size, 2)
sunit_check("archimedean.real_quadratic.certified",
            A5.certificate.verified?, true)
sunit_check("archimedean.real_quadratic.generator_signs",
            A5.real_signs(a5).to_s, "\[-1, 1\]")
sunit_check("archimedean.real_quadratic.unit_bits",
            A5.square_class_signature(epsilon5).to_s, "\[1, 0\]")

U5 = K5.s_unit_square_class_basis(
  [], [-1, epsilon5])
sunit_check("sunit.real_quadratic.dimension", U5.dimension, 2)
sunit_check("sunit.real_quadratic.matrix",
            U5.local_matrix.to_s, "\[\[1, 1\], \[1, 0\]\]")
sunit_check("sunit.real_quadratic.rank",
            U5.rank_certificate.rank, 2)
sunit_check("sunit.real_quadratic.certified",
            U5.certificate.verified?, true)
sunit_check("sunit.real_quadratic.proof_kind",
            U5.certificate.proof_kind, :trusted_theorem_import)
sunit_check("sunit.real_quadratic.arithmetic_replay",
            U5.certificate.arithmetic_replay_checked?, true)
sunit_check("sunit.real_quadratic.not_kernel_theorem",
            U5.certificate.kernel_checked?, false)
sunit_check("sunit.real_quadratic.coordinates",
            U5.coordinates(epsilon5).to_s, "\[0, 1\]")
sunit_check("sunit.real_quadratic.square_equivalence",
            U5.equivalent_mod_squares?(
              epsilon5, epsilon5 * epsilon5**2), true)

dependent_basis_failed = false
begin
  K5.s_unit_square_class_basis([], [-1, 1])
rescue error
  dependent_basis_failed = "[error]".include?("failed certification")
sunit_check("sunit.dependent_basis_rejected",
            dependent_basis_failed, true)

# Q(sqrt(2)) with the unique prime above 2 has dimension three.  The third
# row is ord_P mod 2 and detects sqrt(2).
K2 = NumberField.new(t**2 - 2, :b)
a2 = K2.generator
P2 = K2.prime_ideals_above(2)[0]
epsilon2 = K2.one + a2
U2 = K2.s_unit_square_class_basis(
  [P2], [-1, epsilon2, a2])
sunit_check("sunit.ramified.dimension", U2.dimension, 3)
sunit_check("sunit.ramified.valuation",
            K2.principal_fractional_ideal(a2).valuation(P2), 1)
sunit_check("sunit.ramified.matrix",
            U2.local_matrix.to_s,
            "\[\[1, 1, 1\], \[1, 0, 0\], \[0, 0, 1\]\]")
sunit_check("sunit.ramified.coordinates",
            U2.coordinates(a2 * epsilon2).to_s, "\[0, 1, 1\]")
sunit_check("sunit.ramified.certified", U2.certified?, true)
sunit_check("sunit.support.accepts_S_unit", U2.s_unit?(a2 / 2), true)
sunit_check("sunit.support.rejects_outside_S", U2.s_unit?(3), false)

outside_support_failed = false
begin
  K2.s_unit_square_class_basis([], [-1, a2])
rescue error
  outside_support_failed = "[error]".include?("failed certification")
sunit_check("sunit.outside_support_rejected",
            outside_support_failed, true)

# Q(i) has no real sign rows.  At either split prime above 5, i maps to a
# nonsquare, which detects the nontrivial torsion square class.  In contrast
# -1 has coordinate zero because -1=i^2 in this field.
imaginary_field = NumberField.new(t**2 + 1, :i)
i = imaginary_field.generator
imaginary_arch = imaginary_field.archimedean_data
sunit_check("archimedean.imaginary.signature",
            imaginary_arch.signature.to_s, "\[0, 1\]")
sunit_check("archimedean.imaginary.complex_trivial",
            imaginary_arch.complex_places[0].square_class_bit(i), 0)
P5 = imaginary_field.prime_ideals_above(5)[0]
chi5 = NumberFieldQuadraticResidueCharacter.new(P5)
sunit_check("residue_character.certified", chi5.certified?, true)
sunit_check("residue_character.i", chi5.character(i), -1)
sunit_check("residue_character.i_bit", chi5.bit(i), 1)
imaginary_units = imaginary_field.s_unit_square_class_basis(
  [], [i], [chi5])
sunit_check("sunit.imaginary.dimension", imaginary_units.dimension, 1)
sunit_check("sunit.imaginary.matrix",
            imaginary_units.local_matrix.to_s, "\[\[1\]\]")
sunit_check("sunit.imaginary.minus_one_is_square",
            imaginary_units.coordinates(-1).to_s, "\[0\]")
sunit_check("sunit.imaginary.certified",
            imaginary_units.certified?, true)

characteristic_two_failed = false
begin
  p2_character = NumberFieldQuadraticResidueCharacter.new(P2)
rescue error
  characteristic_two_failed = "[error]".include?(
    "invalid number-field quadratic residue character")
sunit_check("residue_character.characteristic_two_rejected",
            characteristic_two_failed, true)

denominator_failed = false
begin
  chi5.bit(Rational.new(1, 5))
rescue error
  denominator_failed = "[error]".include?(
    "divides the maximal-order denominator")
sunit_check("residue_character.denominator_rejected",
            denominator_failed, true)

# Product archimedean data does not assume its squarefree components are
# irreducible.  Here the first factor contributes two real places and the
# second contributes one complex pair.
product_order = EtaleProductOrder.new([
  t**2 - 5, t**2 + 1
])
product_arch = product_order.archimedean_data
sunit_check("archimedean.product.component_signatures",
            product_arch.component_signatures.to_s,
            "\[\[2, 0\], \[0, 1\]\]")
sunit_check("archimedean.product.signature",
            product_arch.signature.to_s, "\[2, 1\]")
product_value = product_order.element([
  product_order.component_orders[0].generator,
  product_order.component_orders[1].one
])
sunit_check("archimedean.product.real_signs",
            product_arch.real_signs(product_value).to_s,
            "\[-1, 1\]")
sunit_check("archimedean.product.certified",
            product_arch.certified?, true)

# Direct Sturm isolation remains complete for a reducible squarefree quotient
# and sign evaluation detects an exact rational zero without factoring.
reducible_polynomial = (t - 1) * (t**2 - 2)
direct_roots = reducible_polynomial.squarefree_real_root_isolation
sunit_check("archimedean.direct_squarefree.root_count",
            direct_roots.roots.size, 3)
sunit_check("archimedean.direct_squarefree.certified",
            direct_roots.certified?, true)
reducible_order = EtaleProductOrder.new([
  reducible_polynomial
])
reducible_arch = reducible_order.archimedean_data
linear_value = reducible_order.component_orders[
  0].algebra.coerce([-1, 1, 0])
reducible_value = reducible_order.element([linear_value])
sunit_check("archimedean.direct_squarefree.signs",
            reducible_arch.real_signs(reducible_value).to_s,
            "\[-1, 0, 1\]")

<< "algebra_s_units_spec: all checks passed"
