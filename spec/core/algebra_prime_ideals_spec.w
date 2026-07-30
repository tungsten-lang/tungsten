# Certified prime decomposition in maximal orders and finite etale products.
#
# Run in the interpreter and native compiler.  The identities cover inert,
# ramified, split, non-p-maximal, number-field, and product-order paths.

use algebra

-> prime_check(name, got, want)
  equal = got == want
  if got.class_name == "Array" && want.class_name == "Array"
    equal = got.to_s == want.to_s
  if !equal
    message = "FAIL " + name + ": got " + got.to_s
    raise message + ", want " + want.to_s
  << "PASS " + name

r = PolynomialRing.new([:x], RationalField.new)
x = r.generator(0)

sqrt5_power = Algebra.order(x**2 - 5)
sqrt5 = sqrt5_power.maximal_order

# 2 is inert in Q(sqrt(5)).
inert = sqrt5.prime_decomposition(2)
inert_prime = inert.prime_ideals[0]
prime_check("inert.certified", inert.certified?, true)
prime_check("inert.factor_count", inert.prime_ideals.size, 1)
prime_check("inert.e", inert.ramification_indices, [1])
prime_check("inert.f", inert.residue_degrees, [2])
prime_check("inert.norm", inert.norms, [4])
prime_check("inert.contains_two",
            inert_prime.contains?(sqrt5.algebra.coerce(2)), true)
prime_check("inert.excludes_one",
            inert_prime.contains?(sqrt5.one), false)
inert_generator_image = inert_prime.reduce(
  sqrt5.algebra.generator)
prime_check("inert.generator_relation",
            inert_prime.residue_field.add(
              inert_prime.residue_field.multiply(
                inert_generator_image,
                inert_generator_image), -5), 0)

# 5 ramifies, while 11 splits.
ramified = sqrt5.prime_decomposition(5)
prime_check("ramified.certified", ramified.certified?, true)
prime_check("ramified.factor_count",
            ramified.prime_ideals.size, 1)
prime_check("ramified.e", ramified.ramification_indices, [2])
prime_check("ramified.f", ramified.residue_degrees, [1])
prime_check("ramified.norm", ramified.norms, [5])
prime_check("ramified.facade",
            Algebra.prime_decomposition(
              sqrt5, 5).norms, [5])

split = sqrt5.prime_decomposition(11)
prime_check("split.certified", split.certified?, true)
prime_check("split.factor_count", split.prime_ideals.size, 2)
prime_check("split.e", split.ramification_indices, [1, 1])
prime_check("split.f", split.residue_degrees, [1, 1])
prime_check("split.norms", split.norms, [11, 11])
prime_check("split.distinct",
            split.prime_ideals[0].eql?(
              split.prime_ideals[1]), false)

# Prime decomposition is only labeled as a Dedekind factorization after the
# source order reaches the Round 2 fixed point at p.
nonmaximal_failed = false
begin
  sqrt5_power.algebra_order.prime_decomposition(2)
rescue error
  nonmaximal_failed = "[error]".include?("not p-maximal")
prime_check("nonmaximal_is_loud", nonmaximal_failed, true)

generator_limit_failed = false
begin
  cubic_unramified = Algebra.order(
    x**3 - x - 1).algebra_order
  cubic_unramified.prime_decomposition(
    2, 250_000, 1)
rescue error
  generator_limit_failed = "[error]".include?(
    "prime decomposition unknown")
prime_check("generator_limit_is_loud",
            generator_limit_failed, true)

# The NumberField facade converts between its alpha power basis and the
# certified generic integral-order basis.
K = NumberField.new(x**2 - 5, :a)
a = K.generator
k2 = K.prime_decomposition(2)
k2_prime = k2.prime_ideals[0]
prime_check("number_field.certified", k2.certified?, true)
prime_check("number_field.f", k2.residue_degrees, [2])
prime_check("number_field.contains_two",
            k2_prime.contains?(K.coerce(2)), true)
prime_check("number_field.excludes_one",
            k2_prime.contains?(K.one), false)
prime_check("number_field.excludes_nonintegral",
            k2_prime.contains?(a / 2), false)
number_field_image = k2_prime.reduce(a)
prime_check("number_field.generator_relation",
            k2_prime.residue_field.add(
              k2_prime.residue_field.multiply(
                number_field_image, number_field_image), -5), 0)
prime_check("number_field.basis_size",
            k2_prime.basis.size, 2)

# Away from the power-order index, the number-field facade uses the compact
# Dedekind path.  Its certificate replays the finite-field maps and the exact
# ideal identity pO = product P_i^e_i, without retaining a full Frobenius
# residue algebra.
k5 = K.prime_decomposition(5)
prime_check("number_field.dedekind_ramified.class",
            k5.algebra_decomposition.class_name,
            "DedekindAlgebraPrimeDecomposition")
prime_check("number_field.dedekind_ramified.e",
            k5.ramification_indices, [2])
prime_check("number_field.dedekind_ramified.f",
            k5.residue_degrees, [1])
prime_check("number_field.dedekind_ramified.certified",
            k5.certificate.verified?, true)
prime_check("number_field.dedekind_ramified.proof_kind",
            k5.certificate.proof_kind,
            :trusted_theorem_import)
prime_check("number_field.dedekind_ramified.kernel_checked",
            k5.certificate.kernel_checked?, false)
prime_check("number_field.dedekind_ramified.arithmetic_replay",
            k5.certificate.arithmetic_replay_checked?, true)

k11 = K.prime_decomposition(11)
prime_check("number_field.dedekind_split.f",
            k11.residue_degrees, [1, 1])
prime_check("number_field.dedekind_split.norms",
            k11.norms, [11, 11])
prime_check("number_field.dedekind_split.distinct",
            k11.prime_ideals[0].eql?(
              k11.prime_ideals[1]), false)
dedekind_map = k11.prime_ideals[0].algebra_prime_ideal.residue_map
prime_check("number_field.dedekind_map.proof_kind",
            dedekind_map.certificate.proof_kind,
            :exact_dedekind_residue_map)

dedekind_index_failed = false
begin
  DedekindAlgebraPrimeDecomposition.new(
    K.maximal_order_computation, 2)
rescue error
  dedekind_index_failed = "[error]".include?(
    "index prime to p")
prime_check("number_field.dedekind_rejects_index_prime",
            dedekind_index_failed, true)

# In a product, a prime ideal selects one component and contains every other
# component.  At 5 the sqrt(5) component ramifies and the Gaussian component
# splits, giving three primes in total.
product = Algebra.product_order([
  x**2 - 5, x**2 + 1
]).maximal_order
product_at_5 = product.prime_decomposition(5)
prime_check("product.certified", product_at_5.certified?, true)
prime_check("product.factor_count",
            product_at_5.prime_ideals.size, 3)
prime_check("product.e",
            product_at_5.ramification_indices, [2, 1, 1])
prime_check("product.f",
            product_at_5.residue_degrees, [1, 1, 1])
prime_check("product.norms",
            product_at_5.norms, [5, 5, 5])

first_product_prime = product_at_5.prime_ideals[0]
other_component_only = product.element([
  product.component_orders[0].zero,
  product.component_orders[1].one
])
prime_check("product.contains_other_component",
            first_product_prime.contains?(
              other_component_only), true)
prime_check("product.excludes_selected_one",
            first_product_prime.contains?(product.one), false)

s_data = product.s_prime_data([2, 5])
prime_check("s_data.certified", s_data.certified?, true)
prime_check("s_data.rational_primes",
            s_data.rational_primes, [2, 5])
prime_check("s_data.above_5",
            s_data.prime_ideals_above(5).size, 3)
prime_check("s_data.absent_prime",
            s_data.prime_ideals_above(7), [])

repeated_s_failed = false
begin
  product.s_prime_data([2, 2])
rescue error
  repeated_s_failed = "[error]".include?(
    "repeated rational prime")
prime_check("s_data.rejects_repeated_prime",
            repeated_s_failed, true)

bad_ramification_failed = false
begin
  AlgebraPrimeIdeal.new(inert_prime.residue_map, 2)
rescue error
  bad_ramification_failed = "[error]".include?(
    "failed certification")
prime_check("rejects_wrong_ramification",
            bad_ramification_failed, true)

<< "algebra_prime_ideals_spec: all checks passed"
