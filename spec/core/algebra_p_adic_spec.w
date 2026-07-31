# Exact rational p-adic square classes and certified Hensel lifts.

use algebra

-> padic_check(name, got, want)
  if got != want
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

q3 = Algebra.p_adic_field(3, 8)
padic_check("q3.dimension", q3.square_class_dimension, 2)
padic_check("q3.valuation", q3.coerce(Rational.new(2, 27)).valuation, -3)
padic_check("q3.unit_residue", q3.coerce(Rational.new(2, 27)).unit_residue(2), 2)
padic_check("q3.square", q3.coerce(9).square?, true)
padic_check("q3.nonsquare_unit", q3.square_class(18).vector.to_s, "\[0, 1\]")
padic_check("q3.uniformizer", q3.square_class(12).vector.to_s, "\[1, 0\]")
padic_check("q3.class_product",
            (q3.square_class(18) * q3.square_class(12)).vector.to_s,
            "\[1, 1\]")
padic_check("q3.congruence",
            q3.coerce(1).congruent?(1 + 3**6, 6), true)

q2 = Algebra.p_adic_field(2, 8)
padic_check("q2.dimension", q2.square_class_dimension, 3)
padic_check("q2.minus_one", q2.square_class(-1).vector.to_s, "\[0, 1, 0\]")
padic_check("q2.five", q2.square_class(5).vector.to_s, "\[0, 0, 1\]")
padic_check("q2.ten", q2.square_class(10).vector.to_s, "\[1, 0, 1\]")
padic_check("q2.square", q2.coerce(49).square?, true)

qx = PolynomialRing.new([:x], RationalField.new, :lex)
x = qx.generator(0)
root = Algebra.p_adic_field(7, 6).hensel_root(x**2 - 2, 3)
padic_check("hensel.certified", root.certified?, true)
padic_check("hensel.precision", root.precision, 6)
padic_check("hensel.evaluation", root.evaluate_residue, 0)
padic_check("hensel.start", root.residue % 7, 3)
padic_check("hensel.theorem_boundary",
            root.certificate.kernel_checked?, false)
padic_check("hensel.arithmetic_replay",
            root.certificate.arithmetic_replay_checked?, true)
refined = root.refine(9)
padic_check("hensel.refine", refined.residue % root.modulus, root.residue)

bad = false
begin
  Algebra.p_adic_field(7, 5).hensel_root(x**2 - 2, 1)
rescue error
  bad = true
padic_check("hensel.rejects_nonroot", bad, true)

padic_check("padic.completion_boundary",
            q3.arbitrary_completed_elements_implemented?, false)

<< "algebra_p_adic_spec: all checks passed"
