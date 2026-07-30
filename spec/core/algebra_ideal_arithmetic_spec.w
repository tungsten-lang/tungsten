# Canonical integral ideal arithmetic and certified Hermite normal forms.

use algebra

-> ideal_check(name, got, want)
  equal = got == want
  if got.class_name == "Array" && want.class_name == "Array"
    equal = got.to_s == want.to_s
  if !equal
    message = "FAIL " + name + ": got " + got.to_s
    raise message + ", want " + want.to_s
  << "PASS " + name

hnf = IntegerHermiteNormalForm.new([
  [2, 0],
  [0, 3],
  [2, 3],
  [4, -3]
])
ideal_check("hnf.certified", hnf.certified?, true)
ideal_check("hnf.basis", hnf.basis_rows, [[2, 0], [0, 3]])
ideal_check("hnf.determinant", hnf.determinant, 6)

redundant_hnf = IntegerHermiteNormalForm.new([
  [6, 0],
  [4, 2],
  [2, 4],
  [2, 2]
])
ideal_check("hnf.gcd_reduction",
            redundant_hnf.basis_rows,
            [[2, 0], [0, 2]])

rank_three_hnf = IntegerHermiteNormalForm.new([
  [2, 4, 4],
  [6, 6, 12],
  [10, 4, 16],
  [4, -2, 2]
])
ideal_check("hnf.rank_three.certified",
            rank_three_hnf.certified?, true)
ideal_check("hnf.rank_three.basis",
            rank_three_hnf.basis_rows,
            [[2, 0, 0], [0, 2, 0], [0, 0, 2]])

r = PolynomialRing.new([:x], RationalField.new)
x = r.generator(0)
O = Algebra.order(x**2 - 5).maximal_order

unit = O.unit_ideal
two = O.principal_ideal(O.algebra.coerce(2))
three = O.principal_ideal(O.algebra.coerce(3))
six = O.principal_ideal(O.algebra.coerce(6))

ideal_check("unit.certified", unit.certified?, true)
ideal_check("unit.norm", unit.norm, 1)
ideal_check("two.norm", two.norm, 4)
ideal_check("three.norm", three.norm, 9)
ideal_check("six.norm", six.norm, 36)
ideal_check("principal.product", two * three, six)
ideal_check("principal.product_norm",
            (two * three).norm, two.norm * three.norm)
ideal_check("unit.product", unit * two, two)
ideal_check("power.zero", two**0, unit)
ideal_check("power.three.norm", (two**3).norm, 64)

product_computation = two.product_with_certificate(three)
ideal_check("product.certificate",
            product_computation.certificate.verified?, true)
ideal_check("product.result",
            product_computation.ideal, six)

sum_computation = two.sum_with_certificate(three)
ideal_check("sum.certificate",
            sum_computation.certificate.verified?, true)
ideal_check("coprime.sum", sum_computation.ideal, unit)

above_5 = O.prime_decomposition(5).prime_ideals[0]
P = above_5.as_ideal
ideal_check("prime.as_ideal.certified", P.certified?, true)
ideal_check("prime.norm", P.norm, 5)
ideal_check("ramified.square", P**2,
            O.principal_ideal(O.algebra.coerce(5)))
ideal_check("valuation.sqrt5",
            above_5.valuation(O.algebra.generator), 1)
ideal_check("valuation.five",
            above_5.valuation(O.algebra.coerce(5)), 2)
ideal_check("valuation.twenty_five",
            above_5.valuation(O.algebra.coerce(25)), 4)
ideal_check("valuation.zero",
            above_5.valuation(O.zero), :infinity)
valuation_certificate = above_5.valuation_with_certificate(
  O.algebra.coerce(25))
ideal_check("valuation.certificate",
            valuation_certificate.certificate.verified?, true)
zero_valuation = above_5.valuation_with_certificate(
  O.one)
ideal_check("valuation.unit_is_zero",
            zero_valuation.value, 0)
ideal_check("valuation.unit_certificate",
            zero_valuation.certificate.verified?, true)
ideal_check("valuation.ideal_power",
            above_5.ideal_valuation(P**3), 3)
ideal_check("prime.power.arbitrary",
            above_5.ideal_power(8), P**8)
unit_ideal_valuation = above_5.ideal_valuation_with_certificate(
  unit)
ideal_check("valuation.unit_ideal_is_zero",
            unit_ideal_valuation.value, 0)
ideal_check("valuation.unit_ideal_certificate",
            unit_ideal_valuation.certificate.verified?, true)

valuation_limit_failed = false
begin
  above_5.valuation(O.algebra.coerce(25), 3)
rescue error
  valuation_limit_failed = true
ideal_check("valuation.limit_is_loud",
            valuation_limit_failed, true)

generated = O.ideal([
  O.algebra.coerce(2),
  O.algebra.generator + 1
])
above_2 = O.prime_decomposition(2).prime_ideals[0]
ideal_check("generated.inert_prime",
            generated, above_2.as_ideal)
ideal_check("generated.norm", generated.norm, 4)

six_factorization = six.factorization
ideal_check("factorization.six.certified",
            six_factorization.certified?, true)
ideal_check("factorization.six.size",
            six_factorization.size, 2)
ideal_check("factorization.six.norms",
            six_factorization.factors.map ->
              item[0].norm,
            [4, 9])
ideal_check("factorization.six.exponents",
            six_factorization.factors.map ->
              item[1],
            [1, 1])

five_factorization = O.principal_ideal(
  O.algebra.coerce(5)).factorization
ideal_check("factorization.ramified.certified",
            five_factorization.certified?, true)
ideal_check("factorization.ramified.size",
            five_factorization.size, 1)
ideal_check("factorization.ramified.exponent",
            five_factorization[0][1], 2)

eleven_factorization = O.principal_ideal(
  O.algebra.coerce(11)).factorization
ideal_check("factorization.split.certified",
            eleven_factorization.certified?, true)
ideal_check("factorization.split.size",
            eleven_factorization.size, 2)
ideal_check("factorization.split.exponents",
            eleven_factorization.factors.map ->
              item[1],
            [1, 1])
ideal_check("factorization.unit",
            unit.factorization.size, 0)

# NumberField ideals expose the same certified lattice and factorization data
# without leaking the internal etale-order basis.
K = NumberField.new(x**2 - 5, :a)
a = K.generator
k_six = K.principal_ideal(K.coerce(6))
ideal_check("number_field.principal.certified",
            k_six.certified?, true)
ideal_check("number_field.principal.norm",
            k_six.norm, 36)
ideal_check("number_field.principal.basis_size",
            k_six.basis.size, 2)
k_six_factors = k_six.factorization
ideal_check("number_field.factorization.certified",
            k_six_factors.certified?, true)
ideal_check("number_field.factorization.size",
            k_six_factors.size, 2)
k_above_5 = K.prime_ideals_above(5)[0]
ideal_check("number_field.prime.valuation",
            k_above_5.valuation(a), 1)
ideal_check("number_field.ideal.valuation",
            k_above_5.ideal_valuation(
              K.principal_ideal(K.coerce(25))), 4)
k_generated = K.ideal([K.coerce(2), a + 1])
ideal_check("number_field.generated.norm",
            k_generated.norm, 4)
ideal_check("number_field.generated.contains_two",
            k_generated.contains?(K.coerce(2)), true)
ideal_check("number_field.generated.excludes_one",
            k_generated.contains?(K.one), false)

# Invertible fractional ideals use signed prime valuations.  Their
# certificates replay the numerator/denominator integral factorizations.
two_fractional = two.to_fractional
ideal_check("fractional.integral.certified",
            two_fractional.certified?, true)
ideal_check("fractional.integral.norm",
            two_fractional.norm, Rational.new(4))
ideal_check("fractional.inverse.norm",
            two_fractional.inverse.norm,
            Rational.new(1, 4))
two_inverse_product = two_fractional * two_fractional.inverse
ideal_check("fractional.inverse.product",
            two_inverse_product.unit?, true)
ideal_check("fractional.negative_power.norm",
            (two_fractional ** -2).norm,
            Rational.new(1, 16))
ideal_check("fractional.numerator",
            two_fractional.numerator_ideal, two)
ideal_check("fractional.denominator",
            two_fractional.inverse.denominator_ideal, two)

sqrt_five = O.algebra.generator
sqrt_five_over_two = sqrt_five / Rational.new(2)
principal_fractional_computation = O.principal_fractional_ideal_with_certificate(sqrt_five_over_two)
principal_fractional = principal_fractional_computation.ideal
ideal_check("fractional.principal.certified",
            principal_fractional_computation.certified?, true)
ideal_check("fractional.principal.norm",
            principal_fractional.norm,
            Rational.new(5, 4))
ideal_check("fractional.principal.at_five",
            principal_fractional.valuation(above_5), 1)
ideal_check("fractional.principal.at_two",
            principal_fractional.valuation(above_2), -1)
principal_quotient = principal_fractional / principal_fractional
ideal_check("fractional.principal.inverse_round_trip",
            principal_quotient.unit?, true)

k_fractional = K.principal_fractional_ideal(a / 2)
k_above_2 = K.prime_ideals_above(2)[0]
ideal_check("number_field.fractional.certified",
            k_fractional.certified?, true)
ideal_check("number_field.fractional.norm",
            k_fractional.norm, Rational.new(5, 4))
ideal_check("number_field.fractional.at_five",
            k_fractional.valuation(k_above_5), 1)
ideal_check("number_field.fractional.at_two",
            k_fractional.valuation(k_above_2), -1)
k_fractional_inverse_product = k_fractional * k_fractional.inverse
ideal_check("number_field.fractional.inverse",
            k_fractional_inverse_product.unit?, true)
ideal_check("number_field.integral_to_fractional",
            k_six.to_fractional.norm, Rational.new(36))

zero_fractional_failed = false
begin
  O.principal_fractional_ideal(O.zero)
rescue error
  zero_fractional_failed = true
ideal_check("fractional.zero_is_loud",
            zero_fractional_failed, true)

nonmax_fractional_failed = false
nonmax_order = Algebra.order(x**2 - 5).algebra_order
begin
  AlgebraFractionalIdeal.unit(nonmax_order)
rescue error
  nonmax_fractional_failed = true
ideal_check("fractional.nonmaximal_order_is_loud",
            nonmax_fractional_failed, true)

wrong_order_failed = false
gaussian = Algebra.order(x**2 + 1).algebra_order
ideal_check("distinct_parent_orders",
            O.same_order?(gaussian), false)
begin
  two + gaussian.unit_ideal
rescue error
  wrong_order_failed = true
ideal_check("mismatch_is_loud", wrong_order_failed, true)

<< "algebra_ideal_arithmetic_spec: all checks passed"
