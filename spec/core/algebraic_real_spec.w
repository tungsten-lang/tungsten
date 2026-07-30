# Exact arithmetic and replayable operation certificates for real algebraic
# numbers. Run in interpreter and native engines.

use algebra

-> check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> close?(got, want, tolerance = ~1.0e-12)
  difference = got - want
  difference = ~0.0 - difference if difference < ~0.0
  difference <= tolerance

ring = PolynomialRing.new([:x], RationalField.new)
x = ring.generator(0)
sqrt2 = (x**2 - 2).real_roots[1]
sqrt3 = (x**2 - 3).real_roots[1]
sqrt2_interval = sqrt2.interval
sqrt3_interval = sqrt3.interval

sum = sqrt2 + sqrt3
check("sum.class", sum.class_name == "AlgebraicRealRoot")
check("sum.polynomial",
      sum.defining_polynomial.to_s == "z^4 - 10z^2 + 1")
check("sum.index", sum.root_index == 3)
check("sum.value",
      close?(sum.to_f, ~3.1462643699419726, ~1.0e-14))
operands_immutable = sqrt2.lower_bound == sqrt2_interval[0]
operands_immutable = operands_immutable && sqrt2.upper_bound == sqrt2_interval[1]
operands_immutable = operands_immutable && sqrt3.lower_bound == sqrt3_interval[0]
operands_immutable = operands_immutable && sqrt3.upper_bound == sqrt3_interval[1]
check("sum.operands_immutable", operands_immutable)

product_computation = sqrt2.multiply_with_certificate(sqrt3)
product = product_computation.value
check("product.polynomial",
      product.defining_polynomial.to_s == "z^2 - 6")
check("product.value",
      close?(product.to_f, ~2.449489742783178, ~1.0e-14))
check("product.computation.certified", product_computation.certified?)
check("product.certificate.certified",
      product_computation.certificate.certified?)
check("product.eliminant",
      product_computation.elimination_polynomial.to_s == "z^2 - 6")

# The eliminant treats conjugates independently; certified interval selection
# still recovers the rational value of the chosen positive embedding.
square_computation = sqrt2.multiply_with_certificate(sqrt2)
check("square.rational", square_computation.value == Rational.new(2))
check("square.certified", square_computation.certified?)
check("power.positive", sqrt2**2 == Rational.new(2))

quotient = sqrt2 / sqrt3
check("quotient.polynomial",
      quotient.defining_polynomial.to_s == "z^2 - 2/3")
check("quotient.value",
      close?(quotient.to_f, Math.sqrt(~2.0 / ~3.0), ~1.0e-14))

translated = sqrt2 + 1
scaled = sqrt2 * 2
reciprocal = sqrt2**-1
reverse_quotient = Algebra.real_algebraic_value(2, "/", sqrt2)
check("rational.translation",
      translated.defining_polynomial.to_s == "z^2 - 2z - 1")
check("rational.scaling",
      scaled.defining_polynomial.to_s == "z^2 - 8")
check("reciprocal.polynomial",
      reciprocal.defining_polynomial.to_s == "z^2 - 1/2")
check("facade.reverse_quotient", reverse_quotient == sqrt2)
check("negation", ((-sqrt2) <=> 0) < 0)

check("integer.floor.positive", sqrt2.floor == 1)
check("integer.ceil.positive", sqrt2.ceil == 2)
check("integer.round.positive", sqrt2.round == 1)
negative_sqrt2 = (x**2 - 2).real_roots[0]
check("integer.floor.negative", negative_sqrt2.floor == -2)
check("integer.ceil.negative", negative_sqrt2.ceil == -1)
check("integer.round.negative", negative_sqrt2.round == -1)
check("integer.predicate", !sqrt2.integer?)
check("ordering.less", sqrt2 < sqrt3)
check("ordering.less_equal", sqrt2 <= sqrt2)
check("ordering.greater", sqrt3 > sqrt2)
check("ordering.greater_equal", sqrt3 >= sqrt2)
check("ordering.reverse.less", 1 < sqrt2)
check("ordering.reverse.greater", 2 > sqrt2)

# Equality is algebraic rather than an interval-refinement timeout, even when
# variable names or squarefree defining presentations differ.
other_ring = PolynomialRing.new([:y], RationalField.new)
y = other_ring.generator(0)
renamed_sqrt2 = (y**2 - 2).real_roots[1]
reducible_sqrt2 = AlgebraicRealRoot.new(
  (y**2 - 2) * (y - 5), 0, 4, 1)
zero_conjugate_sqrt2 = AlgebraicRealRoot.new(
  y * (y**2 - 2), 1, 2, 2)
check("equality.renamed_polynomial", sqrt2 == renamed_sqrt2)
check("equality.shared_factor", sqrt2 == reducible_sqrt2)
check("comparison.shared_factor", (sqrt2 <=> reducible_sqrt2) == 0)
check("minimal_polynomial.shared_factor",
      reducible_sqrt2.minimal_polynomial == y**2 - 2)
check("minimal_polynomial.removes_zero_denominator_component",
      Algebra.real_algebraic_value(
        1, "/", zero_conjugate_sqrt2) == reciprocal)

bad_result = AlgebraicRealOperationCertificate.new(
  sqrt2, sqrt3, "*", 1,
  product_computation.elimination_polynomial,
  product_computation.interval[0],
  product_computation.interval[1])
check("certificate.rejects_wrong_result", !bad_result.verified?)

expression_root = Expression.constant(sqrt2)
expression_square = expression_root * expression_root
check("expression.square.constant", expression_square.constant?)
check("expression.square.value",
      expression_square.constant_value == Rational.new(2))
expression_shift = Expression.sum([
  Expression.constant(1), expression_root])
check("expression.reverse_constant_order", expression_shift.constant?)
check("expression.reverse_constant_value",
      expression_shift.constant_value == translated)
expression_reciprocal = Expression.constant(1) / expression_root
check("expression.reverse_division", expression_reciprocal.constant?)
check("expression.reverse_division.value",
      expression_reciprocal.constant_value == reciprocal)
symbol = Expression.variable(:u)
like_terms = symbol + expression_root * symbol
check("expression.algebraic_like_terms",
      like_terms.coefficient(:u, 1).constant_value == translated)
check("expression.transcendental_exact",
      expression_root.exp.operation == "exp")
check("expression.transcendental.evaluate",
      close?(expression_root.exp.evaluate({}), Math.exp(Math.sqrt(~2.0))))

float_raised = false
begin
  sqrt2 + ~1.0
rescue error
  float_raised = true
check("boundary.float_is_loud", float_raised)

zero_raised = false
begin
  sqrt2 / 0
rescue error
  zero_raised = true
check("boundary.division_by_zero_is_loud", zero_raised)

<< "algebraic_real_spec: all checks passed"
