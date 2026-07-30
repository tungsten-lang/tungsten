# Exact bivariate resultants and certified local delta invariants.

use algebra

-> invariant_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

Q = Algebra.rational_field
R = PolynomialRing.new([:x, :y], Q, :lex)
coordinates = R.generators
x = coordinates[0]
y = coordinates[1]

cusp_equation = y**2 - x**3
cusp_resultant = cusp_equation.bivariate_resultant(
  cusp_equation.derivative(1), 1)
RX = PolynomialRing.new([:x], Q, :lex)
ux = RX.generator(0)
invariant_check("resultant.cusp",
                cusp_resultant == ux**3*(-4))
invariant_check("resultant.order",
                cusp_resultant.order_at_zero == 3 &&
                cusp_resultant.valuation_at_zero == 3)
invariant_check("resultant.alias",
                cusp_equation.resultant_in(
                  cusp_equation.derivative(1), :y) ==
                  cusp_resultant)
two_lines_resultant = (y - x).resultant_in(
  y + x, :y)
invariant_check("resultant.two_lines",
                two_lines_resultant == ux*2)
invariant_check("resultant.common_factor",
                (y**2 - x**2).resultant_in(
                  y - x, :y).zero?)
bareiss_matrix = [
  [RX.zero, ux],
  [ux, RX.one]]
invariant_check("resultant.bareiss_pivot",
                Polynomial.polynomial_bareiss_determinant(
                  bareiss_matrix, RX) == ux**2*(-1))

cusp = cusp_equation.local_delta_invariant(
  0, 1, nil, 3)
invariant_check("cusp.values",
                cusp.weierstrass_degree == 2 &&
                cusp.discriminant_valuation == 3 &&
                cusp.milnor_number == 2 &&
                cusp.branch_count == 1 &&
                cusp.delta == 1)
invariant_check("cusp.resultant_certificate",
                cusp.discriminant_certificate.verified? &&
                cusp.discriminant_certificate.kernel_checked? &&
                cusp.discriminant_certificate.proof_kind ==
                  :exact_bareiss_resultant)
invariant_check("cusp.delta_certificate",
                cusp.certificate.verified? &&
                cusp.certificate.proof_kind ==
                  :trusted_theorem_import &&
                !cusp.certificate.kernel_checked? &&
                cusp.certificate.theorem_dependencies.size == 2)

smooth = (y - x**2).local_delta_invariant(
  0, 1, nil, 2)
invariant_check("smooth.values",
                smooth.delta == 0 &&
                smooth.milnor_number == 0 &&
                smooth.branch_count == 1)

node = (y**2 - x**2 - x**3).local_delta_invariant(
  0, 1, nil, 3)
invariant_check("node.values",
                node.delta == 1 &&
                node.milnor_number == 1 &&
                node.branch_count == 2)

vertical_cusp = (x**2 - y**3).local_delta_invariant(
  0, 1, nil, 3)
invariant_check("vertical_cusp.values",
                vertical_cusp.delta == 1 &&
                vertical_cusp.milnor_number == 2 &&
                vertical_cusp.branch_count == 1)

tacnode = (y**2 - x**4).local_delta_invariant(
  0, 1, nil, 4)
invariant_check("tacnode.values",
                tacnode.delta == 2 &&
                tacnode.milnor_number == 3 &&
                tacnode.branch_count == 2)

ordinary_triple = (
  y*(y - x)*(y + x) + x**4).local_delta_invariant(
    0, 1, nil, 4)
invariant_check("ordinary_triple.values",
                ordinary_triple.delta == 3 &&
                ordinary_triple.branch_count == 3)

mixed = (
  (y**2 - x**3)*(y**2 - x*2)).local_delta_invariant(
    0, 1, nil, 3)
invariant_check("mixed.values",
                mixed.delta == 3 &&
                mixed.branch_count == 2)

shifted = (
  (y - 3)**2 - (x - 2)**3).local_delta_invariant(
    :x, :y, [2, 3], 3)
invariant_check("shifted.value",
                shifted.delta == 1)

normalization = cusp_equation.local_normalization(
  0, 1, nil, 3)
invariant_check("normalization.facade",
                normalization.delta == 1 &&
                normalization.milnor_number == 2 &&
                normalization.delta_certificate.verified?)
invariant_check("algebra.facade",
                Algebra.local_delta(
                  cusp_equation, 0, 1, nil, 3) == 1)

tampered_discriminant = (
  PlaneCurveLocalDiscriminantCertificate.new(
    cusp.normalization.local_polynomial,
    cusp.weierstrass_degree,
    cusp.derivative_resultant,
    cusp.discriminant_valuation + 1))
invariant_check("discriminant.tamper_rejected",
                !tampered_discriminant.verified?)

nondistinguished = x*y**2 + y - x
nondistinguished_rejected = false
begin
  nondistinguished.local_delta_invariant(
    0, 1, nil, 3)
rescue error
  nondistinguished_rejected = true
invariant_check("boundary.distinguished",
                nondistinguished_rejected)
