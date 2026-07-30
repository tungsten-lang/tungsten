# Exact monogenic orders, Dedekind index certificates, and finite products.
#
# Run both ways:
#   bin/tungsten run spec/core/algebra_orders_spec.w
#   bin/tungsten compile spec/core/algebra_orders_spec.w \
#     --out /tmp/algebra-orders-spec

use algebra

-> order_check(name, got, want)
  equal = got == want
  if got.class_name == "Polynomial" && want.class_name == "Polynomial"
    equal = got.eql?(want)
  elsif got.class_name == "EtaleAlgebraElement"
    equal = got.eql?(want)
  elsif got.class_name == "EtaleProductOrderElement"
    equal = got.eql?(want)
  elsif got.class_name == "Array" && want.class_name == "Array"
    equal = got.to_s == want.to_s
  if !equal
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

r = PolynomialRing.new([:x], RationalField.new)
x = r.generator(0)

# Clearing denominators and scaling alpha by the primitive leading
# coefficient produces a monic integral equation for beta.
source = x**2*Rational.new(1, 2)
source += x*Rational.new(1, 4) + Rational.new(1, 4)
transformed = Algebra.order(source)
order_check("transform.scale", transformed.generator_scale, 2)
order_check("transform.polynomial",
            transformed.integral_polynomial, x**2 + x + 2)
order_check("transform.certificate",
            transformed.transform_certificate.verified?, true)
order_check("transform.order_certificate",
            transformed.certificate.verified?, true)
order_check("transform.discriminant", transformed.discriminant, -7)

wrong_transform = IntegralGeneratorTransformCertificate.new(
  source, transformed.integral_polynomial, 3)
order_check("transform.rejects_wrong_scale",
            wrong_transform.verified?, false)

# Dedekind's criterion proves maximality of these familiar power orders.
golden = Algebra.order(x**2 - x - 1)
order_check("golden.discriminant", golden.discriminant, 5)
order_check("golden.maximal", golden.maximal?, true)
order_check("golden.maximality_certificate",
            golden.maximality_certificate.verified?, true)
order_check("golden.maximal_order", golden.maximal_order, golden)

factor_limit_failed = false
begin
  golden.maximal?(0)
rescue error
  factor_limit_failed = "[error]".include?("maximality unknown")
order_check("maximality.factor_limit_is_loud",
            factor_limit_failed, true)

gaussian = Algebra.order(x**2 + 1)
gaussian_at_2 = gaussian.index_certificate(2)
order_check("gaussian.discriminant", gaussian.discriminant, -4)
order_check("gaussian.at_2.certified", gaussian_at_2.verified?, true)
order_check("gaussian.at_2.prime_to_index",
            gaussian_at_2.index_prime_to_p?, true)
order_check("gaussian.maximal", gaussian.maximal?, true)

pure_cubic = Algebra.order(x**3 - 2)
order_check("pure_cubic.discriminant", pure_cubic.discriminant, -108)
order_check("pure_cubic.maximal", pure_cubic.maximal?, true)

# Z[sqrt(5)] has index two in the maximal order. The obstruction is an exact
# modular gcd, and maximal_order refuses to manufacture an absent overorder.
sqrt5 = Algebra.order(x**2 - 5)
sqrt5_at_2 = sqrt5.index_certificate(2)
order_check("sqrt5.discriminant", sqrt5.discriminant, 20)
order_check("sqrt5.at_2.certified", sqrt5_at_2.verified?, true)
order_check("sqrt5.at_2.divides_index",
            sqrt5_at_2.p_divides_index?, true)
sqrt5_mod_2_x = sqrt5_at_2.obstruction.ring.generator(0)
order_check("sqrt5.at_2.obstruction",
            sqrt5_at_2.obstruction, sqrt5_mod_2_x + 1)
order_check("sqrt5.obstructed_primes", sqrt5.obstructed_primes, [2])
order_check("sqrt5.not_maximal", sqrt5.maximal?, false)

maximal_order_failed = false
begin
  sqrt5.maximal_order
rescue error
  maximal_order_failed = "[error]".include?("nonmaximal at")
order_check("sqrt5.overorder_is_loud", maximal_order_failed, true)

# The classic pure-cubic index obstruction at 3 is also detected.
cuberoot10 = Algebra.order(x**3 - 10)
order_check("cuberoot10.discriminant", cuberoot10.discriminant, -2700)
order_check("cuberoot10.obstructed_primes",
            cuberoot10.obstructed_primes, [3])

composite_prime = DedekindIndexCertificate.new(golden, 4)
order_check("dedekind.rejects_composite",
            composite_prime.verified?, false)

# The integral lattice is the Z-span of the power basis.
integral_value = golden.element([1, 2])
order_check("membership.integral", golden.contains?(integral_value), true)
order_check("membership.generator", golden.contains?(golden.generator), true)
half_value = golden.algebra.coerce([Rational.new(1, 2), 0])
order_check("membership.fractional", golden.contains?(half_value), false)

fractional_coercion_failed = false
begin
  golden.coerce(half_value)
rescue error
  fractional_coercion_failed = "[error]".include?("not integral")
order_check("membership.coercion_is_loud",
            fractional_coercion_failed, true)

repeated_failed = false
begin
  Algebra.order((x - 1)**2)
rescue error
  repeated_failed = "[error]".include?("failed certification")
order_check("order.rejects_nonetale_quotient", repeated_failed, true)

constant_failed = false
begin
  Algebra.order(r.one)
rescue error
  constant_failed = "[error]".include?("nonconstant")
order_check("order.rejects_constant", constant_failed, true)

# Direct products retain component lattices and exact trace/norm arithmetic.
product = Algebra.product_order([x**2 - x - 1, x**2 + 1])
order_check("product.component_ranks", product.component_ranks, [2, 2])
order_check("product.rank", product.rank, 4)
order_check("product.discriminant", product.discriminant, -20)
order_check("product.certificate", product.certificate.verified?, true)
order_check("product.maximal", product.maximal?, true)

product_generator = product.element([
  product.component_orders[0].generator,
  product.component_orders[1].generator
])
order_check("product.generator_unit", product_generator.unit?, true)
order_check("product.generator_inverse",
            product_generator * product_generator.inverse, product.one)
order_check("product.trace", product_generator.trace, Rational.new(1))
order_check("product.norm", product_generator.norm, Rational.new(-1))

obstructed_product = Algebra.product_order([x**2 - x - 1, x**2 - 5])
order_check("product.nonmaximal", obstructed_product.maximal?, false)
order_check("product.obstructed_components",
            obstructed_product.obstructed_components, [[1, [2]]])

<< "algebra_orders_spec: all checks passed"
