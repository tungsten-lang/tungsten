# Exact odd-prime square classes in a number-field completion.

use algebra

-> local_square_check(name, got, want)
  if got != want
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

qx = PolynomialRing.new([:x], RationalField.new, :lex)
x = qx.generator(0)
k = NumberField.new(x**2 - 2, :a)
primes = k.prime_ideals_above(7)
prime = primes[0]
primes.each -> (candidate)
  image = candidate.reduce(k.generator)
  prime = candidate if image == 3

local_square_check("prime.residue_degree",
                   prime.residue_degree, 1)
local_square_check("prime.generator_image",
                   prime.reduce(k.generator), 3)

uniformizer = prime.uniformizer
local_square_check("uniformizer.certified",
                   uniformizer.certified?, true)
local_square_check("uniformizer.valuation",
                   k.principal_fractional_ideal(
                     uniformizer.element).valuation(prime),
                   1)

unit_class = prime.local_square_class(k.generator)
local_square_check("local.unit_nonsquare",
                   unit_class.vector.to_s, "\[0, 1\]")
uniformizer_class = prime.local_square_class(7)
local_square_check("local.uniformizer",
                   uniformizer_class.vector.to_s, "\[1, 0\]")
local_square_check("local.theorem_boundary",
                   unit_class.certificate.kernel_checked?, false)
local_square_check("local.arithmetic_replay",
                   unit_class.certificate.arithmetic_replay_checked?,
                   true)

# This element is a unit at a -> 3 and has a pole at the other prime above 7.
# Its power-basis coefficients therefore have 7 in their denominator. Local
# reduction clears the other pole with a separated uniformizer instead of
# rejecting the presentation.
cross_prime_unit = k.one / (k.generator - 4)
cross_prime_class = prime.local_square_class(
  cross_prime_unit)
local_square_check("local.cross_prime.valuation",
                   cross_prime_class.valuation, 0)
local_square_check("local.cross_prime.adjustments",
                   cross_prime_class.unit_residue.adjustments.size, 1)
local_square_check("local.cross_prime.residue",
                   cross_prime_class.unit_residue.residue, 6)
local_square_check("local.cross_prime.vector",
                   cross_prime_class.vector.to_s, "\[0, 1\]")

map = prime.local_square_class_map(
  [k.generator, 7, k.generator * 7])
local_square_check("map.certified", map.certified?, true)
local_square_check("map.matrix",
                   map.matrix.to_s,
                   "\[\[0, 1, 1\], \[1, 0, 1\]\]")
local_square_check("map.rank", map.rank, 2)

# A product S-unit space localizes blockwise at every prime above 7.
unit_basis = k.s_unit_square_class_basis(
  [], [-1, k.one + k.generator])
product_order = EtaleProductOrder.new([
  x**2 - 2
])
product_space = product_order.s_unit_square_class_space(
  [], [[unit_basis]])
product_local = product_space.odd_localization_map(7)
local_square_check("product_local.certified",
                   product_local.certified?, true)
local_square_check("product_local.factor_count",
                   product_local.local_factor_count, 2)
local_square_check("product_local.target_dimension",
                   product_local.target_dimension, 4)
local_square_check("product_local.matrix",
                   product_local.matrix.to_s,
                   "\[\[0, 0\], \[1, 1\], \[0, 0\], \[1, 0\]\]")
local_square_check("product_local.rank",
                   product_local.rank, 2)
local_square_check("product_local.apply",
                   product_local.apply([0, 1]).to_s,
                   "\[0, 1, 0, 0\]")
local_square_check("product_local.theorem_boundary",
                   product_local.certificate.kernel_checked?,
                   false)
local_square_check("product_local.linear_replay",
                   product_local.certificate.linear_kernel_replay_checked?,
                   true)

dyadic_unit = k.prime_ideals_above(2)[0].local_square_class(1)
local_square_check("local.dyadic_dispatch",
                   dyadic_unit.vector.to_s,
                   "\[0, 0, 0, 0\]")
local_square_check("local.dyadic_certified",
                   dyadic_unit.certified?, true)

product_dyadic = false
begin
  product_space.odd_localization_map(2)
rescue error
  product_dyadic = true
local_square_check("product_local.dyadic_loud",
                   product_dyadic, true)

<< "algebra_p_adic_number_field_spec: all checks passed"
