# Exact integer factorization regressions.
# Run interpreted:
#   bin/tungsten run spec/numeric/integer_factorization_spec.w
# Run compiled:
#   bin/tungsten compile spec/numeric/integer_factorization_spec.w \
#     --out /tmp/integer-factorization-spec

-> factor_check(name, got, want)
  if got != want
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

unit = 1.factor
factor_check("unit.empty", unit.empty?, true)
factor_check("unit.size", unit.size, 0)
factor_check("unit.value", unit.value, 1)
factor_check("unit.to_s", unit.to_s, "1")

positive = 2808.factor
factor_check("positive.to_s", positive.to_s, "2^3 * 3^3 * 13")
factor_check("positive.size", positive.size, 3)
factor_check("positive.value", positive.value, 2808)
factor_check("positive.primes", positive.primes.to_s, "\[2, 3, 13\]")
factor_check("positive.map_prime",
             (positive.map -> item.prime).to_s,
             "\[2, 3, 13\]")
factor_check("positive.first_prime", positive[0].prime, 2)
factor_check("positive.first_exponent", positive[0].exponent, 3)
factor_check("positive.first_value", positive[0].value, 8)
factor_check("positive.prime_power_to_s", positive[2].to_s, "13")

negative = (-72).factor
factor_check("negative.sign", negative.sign, -1)
factor_check("negative.to_s", negative.to_s, "-1 * 2^3 * 3^2")
factor_check("negative.value", negative.value, -72)
factor_check("negative.primes", negative.primes.to_s, "\[2, 3\]")
factor_check("negative_one", (-1).factor.to_s, "-1")

factor_check("factorization.equality", 2808.factor, positive)
factor_check("factorization.inequality", 2808.factor == 2809.factor, false)
factor_check("prime_power.equality", PrimePower.new(13, 2), PrimePower.new(13, 2))
factor_check("prime_power.inequality",
             PrimePower.new(13, 1) == PrimePower.new(13, 2), false)

# This exact discriminant support is the quartic program's motivating case.
quartic_discriminant = (2 ** 40) * (3 ** 42) * (13 ** 2)
quartic_factorization = quartic_discriminant.factor
factor_check("quartic.to_s",
             quartic_factorization.to_s,
             "2^40 * 3^42 * 13^2")
factor_check("quartic.distinct_primes",
             quartic_factorization.primes.to_s,
             "\[2, 3, 13\]")
factor_check("quartic.value", quartic_factorization.value, quartic_discriminant)

zero_failed = false
begin
  0.factor
rescue error
  zero_failed = "[error]".include?("undefined")
factor_check("zero.raises", zero_failed, true)

bad_prime_failed = false
begin
  PrimePower.new(1, 2)
rescue error
  bad_prime_failed = "[error]".include?("at least 2")
factor_check("prime_power.bad_prime_raises", bad_prime_failed, true)

bad_exponent_failed = false
begin
  PrimePower.new(2, 0)
rescue error
  bad_exponent_failed = "[error]".include?("positive")
factor_check("prime_power.bad_exponent_raises", bad_exponent_failed, true)

composite_base_failed = false
begin
  PrimePower.new(4, 1)
rescue error
  composite_base_failed = "[error]".include?("must be prime")
factor_check("prime_power.composite_base_raises", composite_base_failed, true)

<< "integer_factorization_spec: all checks passed"
