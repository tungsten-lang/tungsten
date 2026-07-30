# Degree-generic Pohst-Zassenhaus Round 2 maximal orders.
#
# Run both ways:
#   bin/tungsten run spec/core/algebra_maximal_orders_spec.w
#   bin/tungsten compile spec/core/algebra_maximal_orders_spec.w \
#     --out /tmp/algebra-maximal-orders-spec

use algebra

-> maximal_order_check(name, got, want)
  equal = got == want
  if got.class_name == "EtaleAlgebraElement"
    equal = got.eql?(want)
  elsif got.class_name == "Array" && want.class_name == "Array"
    equal = got.to_s == want.to_s
  if !equal
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

r = PolynomialRing.new([:x], RationalField.new)
x = r.generator(0)

# The 2-radical of Z[sqrt(5)] is (2, 1 + sqrt(5)). Its multiplier ring is
# Z[(1 + sqrt(5))/2], the full ring of integers.
sqrt5_power = Algebra.order(x**2 - 5)
sqrt5 = sqrt5_power.algebra_order
sqrt5_radical = sqrt5.p_radical(2)
maximal_order_check("sqrt5.order_certificate",
                    sqrt5.certificate.verified?, true)
maximal_order_check("sqrt5.radical_certificate",
                    sqrt5_radical.certificate.verified?, true)
maximal_order_check("sqrt5.radical.contains_two",
                    sqrt5_radical.contains?(sqrt5.algebra.coerce(2)), true)
maximal_order_check("sqrt5.radical.contains_one_plus_generator",
                    sqrt5_radical.contains?(
                      sqrt5.algebra.generator + 1), true)

sqrt5_at_2 = sqrt5.p_maximal_order_with_certificate(2)
sqrt5_maximal = sqrt5_at_2.order
maximal_order_check("sqrt5.round_two_steps",
                    sqrt5_at_2.steps.size, 1)
maximal_order_check("sqrt5.index", sqrt5_maximal.index_from(sqrt5), 2)
maximal_order_check("sqrt5.field_discriminant",
                    sqrt5_maximal.discriminant, 5)
maximal_order_check("sqrt5.contains_half_generator",
                    sqrt5_maximal.contains?(
                      (sqrt5.algebra.generator + 1) / 2), true)
maximal_order_check("sqrt5.p_maximal_certificate",
                    sqrt5_at_2.certificate.verified?, true)

# A fixed Round 2 multiplier ring is an explicit p-maximality certificate.
gaussian = Algebra.order(x**2 + 1).algebra_order
gaussian_at_2 = gaussian.p_maximal_order_with_certificate(2)
maximal_order_check("gaussian.round_two_fixed",
                    gaussian_at_2.steps.size, 0)
maximal_order_check("gaussian.p_maximal_certificate",
                    gaussian_at_2.certificate.verified?, true)

# Pure cubic Q(cuberoot(10)) has power-order index 3.
cuberoot10 = Algebra.order(x**3 - 10).algebra_order
cuberoot10_maximal = cuberoot10.maximal_order_with_certificate
maximal_order_check("cuberoot10.index", cuberoot10_maximal.index, 3)
maximal_order_check("cuberoot10.field_discriminant",
                    cuberoot10_maximal.order.discriminant, -300)
maximal_order_check("cuberoot10.certificate",
                    cuberoot10_maximal.certificate.verified?, true)

# This is a degree-four, deliberately nonmaximal presentation. If b^4 = -16,
# then z=b/2 satisfies z^4+1=0 and Z[z] has discriminant 256. Thus the
# expected index is 64, independently witnessed by an explicit integral
# overorder basis.
scaled_cyclotomic = Algebra.order(x**4 + 16).algebra_order
cyclotomic_maximal = scaled_cyclotomic.maximal_order_with_certificate
b = scaled_cyclotomic.algebra.generator
maximal_order_check("quartic.power_discriminant",
                    scaled_cyclotomic.discriminant, 1_048_576)
maximal_order_check("quartic.maximal_index",
                    cyclotomic_maximal.index, 64)
maximal_order_check("quartic.field_discriminant",
                    cyclotomic_maximal.order.discriminant, 256)
maximal_order_check("quartic.contains_b_over_2",
                    cyclotomic_maximal.order.contains?(b / 2), true)
maximal_order_check("quartic.contains_b2_over_4",
                    cyclotomic_maximal.order.contains?(b**2 / 4), true)
maximal_order_check("quartic.contains_b3_over_8",
                    cyclotomic_maximal.order.contains?(b**3 / 8), true)
maximal_order_check("quartic.degree_generic_certificate",
                    cyclotomic_maximal.certificate.verified?, true)

# Product maximality composes independently certified component orders.
product = Algebra.product_order([x**2 - 5, x**2 + 1])
product_maximal = product.maximal_order_with_certificate
maximal_order_check("product.index", product_maximal.index, 2)
maximal_order_check("product.discriminant",
                    product_maximal.order.discriminant, -20)
product_discriminants = product_maximal.order.component_orders.map ->
  item.discriminant
maximal_order_check("product.component_discriminants",
                    product_discriminants,
                    [5, -4])
maximal_order_check("product.certificate",
                    product_maximal.certificate.verified?, true)

# Resource exhaustion and malformed proof objects are never negative claims.
step_limit_failed = false
begin
  sqrt5.p_maximal_order_with_certificate(2, 0)
rescue error
  step_limit_failed = "[error]".include?("p-maximal order unknown")
maximal_order_check("round_two.step_limit_is_loud",
                    step_limit_failed, true)

bad_step = PMaximalOrderStepCertificate.new(
  sqrt5, 3, sqrt5_radical, sqrt5_maximal)
maximal_order_check("round_two.rejects_wrong_prime",
                    bad_step.verified?, false)
bad_p_maximal = PMaximalOrderCertificate.new(
  sqrt5, 3, sqrt5_maximal)
maximal_order_check("p_maximal.rejects_wrong_index_prime",
                    bad_p_maximal.verified?, false)

bad_global = MaximalOrderCertificate.new(
  sqrt5, sqrt5, sqrt5_maximal,
  [[2, 1], [5, 1]], [])
maximal_order_check("maximal.rejects_wrong_discriminant_factors",
                    bad_global.verified?, false)

nonorder_failed = false
begin
  AlgebraOrder.new(sqrt5.algebra, [
    [Rational.new(1, 2), Rational.new(0)],
    [Rational.new(0), Rational.new(1)]
  ])
rescue error
  nonorder_failed = "[error]".include?("failed certification")
maximal_order_check("order.rejects_nonring_lattice",
                    nonorder_failed, true)

if env("TUNGSTEN_MAXIMAL_ORDER_FULL") == "1"
  # The old cubic HNF implementation found this index-64 order. Round 2
  # reaches the same discriminant without any rank-three special case.
  h47 = Algebra.order(x**3 + x**2*12 - 64).algebra_order
  h47_maximal = h47.maximal_order_with_certificate
  maximal_order_check("full.h47.index", h47_maximal.index, 64)
  maximal_order_check("full.h47.discriminant",
                      h47_maximal.order.discriminant, 81)
  maximal_order_check("full.h47.certificate",
                      h47_maximal.certificate.verified?, true)

<< "algebra_maximal_orders_spec: all checks passed"
