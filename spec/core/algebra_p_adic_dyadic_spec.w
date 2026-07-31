# Complete dyadic square classes through the exact higher-unit filtration.

use algebra

-> dyadic_check(name, got, want)
  if got != want
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

-> check_representative_basis(name, prime)
  representatives = NumberFieldDyadicSquareClassArithmetic.representatives(
    prime)
  expected_dimension = prime.ramification_index
  expected_dimension *= prime.residue_degree
  expected_dimension += 2
  dyadic_check(name + ".representative_count",
                representatives.size,
                expected_dimension)
  index = 0
  while index < representatives.size
    square_class = prime.dyadic_square_class(
      representatives[index])
    expected = []
    representatives.size.times ->
      expected.push(expected.size == index ? 1 : 0)
    dyadic_check(name + ".basis_" + index.to_s,
                  square_class.vector.to_s,
                  expected.to_s)
    dyadic_check(name + ".basis_certified_" + index.to_s,
                  square_class.certified?, true)
    index += 1

-> check_all_classes(name, prime)
  representatives = NumberFieldDyadicSquareClassArithmetic.representatives(
    prime)
  class_count = 2 ** representatives.size
  code = 0
  while code < class_count
    remaining = code
    value = prime.field.one
    expected = []
    index = 0
    while index < representatives.size
      bit = remaining % 2
      remaining = remaining / 2
      expected.push(bit)
      value *= representatives[index] if bit == 1
      index += 1
    square_class = prime.dyadic_square_class(value)
    dyadic_check(name + ".class_" + code.to_s,
                  square_class.vector.to_s,
                  expected.to_s)
    code += 1

R = PolynomialRing.new([:x], RationalField.new)
x = R.generator(0)

# Totally ramified degree two: e=2, f=1 and local square-class dimension 4.
K2 = NumberField.new(x**2 - 2, :a)
a = K2.generator
P2 = K2.prime_ideals_above(2)[0]
dyadic_check("ramified.e", P2.ramification_index, 2)
dyadic_check("ramified.f", P2.residue_degree, 1)
check_representative_basis("ramified", P2)
check_all_classes("ramified", P2)
square = P2.dyadic_square_class(
  (K2.one + a)**2)
dyadic_check("ramified.square_zero",
              square.vector.to_s,
              "\[0, 0, 0, 0\]")
ramified_representatives = square.representatives
ramified_map = P2.local_square_class_map(
  ramified_representatives)
dyadic_check("ramified.map_certified",
              ramified_map.certified?, true)
dyadic_check("ramified.map_rank",
              ramified_map.rank, 4)
dyadic_check("ramified.map_matrix",
              ramified_map.matrix.to_s,
              "\[\[1, 0, 0, 0\], \[0, 1, 0, 0\], \[0, 0, 1, 0\], \[0, 0, 0, 1\]\]")
product = P2.dyadic_square_class(
  ramified_representatives[0] *
  ramified_representatives[1])
dyadic_check("ramified.multiplicative",
              product.vector.to_s,
              "\[1, 1, 0, 0\]")

# Unramified degree two: e=1, f=2 and the same total dimension, with two
# independent residue-field bits in U_1/U_2.
K5 = NumberField.new(x**2 - 5, :b)
P5 = K5.prime_ideals_above(2)[0]
dyadic_check("unramified.e", P5.ramification_index, 1)
dyadic_check("unramified.f", P5.residue_degree, 2)
check_representative_basis("unramified", P5)
check_all_classes("unramified", P5)

# The product map uses the same complete local target and reuses each global
# S-unit generator's statement-bound principal-ideal certificate.
U2 = K2.s_unit_square_class_basis(
  [P2], [-1, K2.one + a, a])
product_order = EtaleProductOrder.new([
  x**2 - 2
])
product_space = product_order.s_unit_square_class_space(
  [2], [[U2]])
product_local = product_space.localization_map(2)
dyadic_check("product.factor_count",
              product_local.local_factor_count, 1)
dyadic_check("product.target_dimension",
              product_local.target_dimension, 4)
dyadic_check("product.rank",
              product_local.rank, 3)
dyadic_check("product.certified",
              product_local.certified?, true)
dyadic_check("product.complete_coordinates",
              product_local.certificate.complete_square_class_coordinates?,
              true)

odd_profile_failed = false
begin
  NumberFieldOddPrimeValuationProfile.new(
    K5, K5.one, 2)
rescue error
  odd_profile_failed = true
dyadic_check("odd_profile_still_rejects_two",
              odd_profile_failed, true)

<< "algebra_p_adic_dyadic_spec: all checks passed"
