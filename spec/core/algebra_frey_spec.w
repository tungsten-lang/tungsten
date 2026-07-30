# Integral Weierstrass invariants and the checked FLT Frey construction.
# No nontrivial Fermat solution is used or assumed by this regression.

use algebra

-> frey_check(name, got, want)
  if got != want
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

# y^2 = x^3 - x has Delta=64 and j=1728.
model = IntegralWeierstrassModel.new(0, 0, 0, -1, 0)
frey_check("weierstrass.b", model.b_invariants.join(","), "0,-2,0,-1")
frey_check("weierstrass.c", model.c_invariants.join(","), "48,0")
frey_check("weierstrass.discriminant", model.discriminant, 64)
frey_check("weierstrass.j", model.j_invariant, Rational.new(1728))
frey_check("weierstrass.certificate", model.certificate.verified?, true)
frey_check("weierstrass.plane_degree", model.projective_curve.degree, 3)
frey_check("weierstrass.plane_nonsingular",
           model.projective_curve.nonsingular?, true)

tampered = WeierstrassInvariantsCertificate.new(
  model.coefficients, model.b_invariants, model.c_invariants, 65)
frey_check("weierstrass.tamper_rejected", tampered.verified?, false)
frey_check("weierstrass.facade",
           Algebra.integral_weierstrass(0, 0, 0, -1, 0).discriminant, 64)

# A primitive pair defines a Frey curve whether or not a^p+b^p is a pth
# power. The stricter constructor checks c and therefore cannot have a
# nontrivial positive regression fixture without assuming a counterexample.
frey = FreyCurve.new(2, 3, 5)
a5 = 2**5
b5 = 3**5
sum5 = a5 + b5
frey_check("frey.coefficients", frey.model.coefficients.join(","),
           [0, b5 - a5, 0, 0 - a5*b5, 0].join(","))
frey_check("frey.c4", frey.c4, 16*(a5**2 + a5*b5 + b5**2))
frey_check("frey.discriminant", frey.discriminant,
           16*(a5*b5*sum5)**2)
frey_check("frey.certificate", frey.certificate.verified?, true)
frey_check("frey.not_false_solution", frey.fermat_solution?(3), false)
frey_check("frey.facade", Algebra.frey_curve(2, 3, 5).discriminant,
           frey.discriminant)

wrong_model = IntegralWeierstrassModel.new(0, b5 - a5, 0, 1 - a5*b5, 0)
wrong_frey_certificate = FreyCurveCertificate.new(2, 3, 5, wrong_model)
frey_check("frey.tamper_rejected", wrong_frey_certificate.verified?, false)

false_solution_rejected = false
begin
  FreyCurve.from_fermat_solution(2, 3, 4, 5)
rescue error
  false_solution_rejected = error.to_s.include?("do not satisfy")
frey_check("frey.false_solution_rejected", false_solution_rejected, true)

conductor_unavailable = false
begin
  frey.conductor
rescue error
  conductor_unavailable = error.to_s.include?("Tate")
frey_check("frey.conductor_fails_loudly", conductor_unavailable, true)
