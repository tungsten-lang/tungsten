# Packed Rational core surface and arithmetic parity.
# Run both ways:
#   bin/tungsten run spec/numeric/rational_spec.w
#   bin/tungsten compile spec/numeric/rational_spec.w --out /tmp/rational-spec

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()

r = 6/8
check("literal.reduce", r.to_s, "3/4")
check("numerator", r.numerator, 3)
check("denominator", r.denominator, 4)
check("to_a.numerator", r.to_a[0], 3)
check("to_a.denominator", r.to_a[1], 4)
check("to_r.identity", r.to_r, r)

constructed = Rational.new(15, -20)
check("new.reduce_sign", constructed.to_s, "-3/4")
check("new.default_denominator", Rational.new(7).to_s, "7/1")
check("constructor.sugar", Rational(6, 8), 3/4)
rational_class = Rational
check("constructor.dynamic", rational_class.new(10, 15), 2/3)

check("add", 3/4 + 1/2, 5/4)
check("subtract", 1/2 - 1/3, 1/6)
check("multiply", 3/4 * 2/3, 1/2)
check("divide", 3/4 / 1/2, 3/2)
check("integer.divide_rational", 1 / (2/3), 3/2)
check("power.positive", (2/3) ** 3, 8/27)
check("power.negative", (2/3) ** -2, 9/4)

check("compare.rational", 2/3 < 3/4, true)
check("compare.integer.left", 0 < 1/2, true)
check("compare.integer.right", 3/2 > 1, true)
check("compare.bigint.right", 1/2 < 1000000000000000, true)
check("compare.bigint.left", -1000000000000000 < 1/2, true)
check("spaceship", 5/7 <=> 5/7, 0)
check("equal.integer", 2/2 == 1, true)
check("equal.bigint", 1/2 == 1000000000000000, false)

check("negative", (-3/2).negative?, true)
check("abs", (-3/2).abs, 3/2)
check("negate", (3/2).negate, -3/2)
check("reciprocal", (-3/2).reciprocal, -2/3)
check("normalize", (6/8).normalize, 3/4)

check("to_i.positive", (7/3).to_i, 2)
check("to_i.negative", (-7/3).to_i, -2)
check("floor.negative", (-7/3).floor, -3)
check("ceil.positive", (7/3).ceil, 3)
check("round.down", (7/3).round, 2)
check("round.half_positive", (3/2).round, 2)
check("round.half_negative", (-3/2).round, -2)
check("to_f", ((1/4).to_f * ~100.0).to_i, 25)

check("reduced", (6/8).reduced?, true)
check("integer", (6/3).integer?, true)
check("proper", (-3/4).proper?, true)
check("unit_fraction", (-1/9).unit_fraction?, true)
check("fractional_part", (7/3).fractional_part, 1/3)

# Promotion is representation-only: values beyond the packed 22-bit fields
# remain exact, dispatch as Rational, and can reduce back to the packed tier.
large = Rational.new(4194304, 3)
check("large.class_name", large.class_name, "Rational")
check("large.numerator", large.numerator, 4194304)
check("large.denominator", large.denominator, 3)
check("large.to_s", large.to_s, "4194304/3")
check("large.add", large + 1/3, Rational.new(4194305, 3))
check("large.compare", large > 1000000, true)
check("large.cancel_to_small", large * Rational.new(3, 4194304), 1/1)

huge = Rational.new(100000000000000000000, 3)
check("huge.class_name", huge.class_name, "Rational")
check("huge.numerator", huge.numerator, 100000000000000000000)
check("huge.denominator", huge.denominator, 3)
check("huge.multiply_exact", huge * Rational.new(3, 10),
  Rational.new(10000000000000000000, 1))
check("huge.equal_distinct", huge, Rational.new(100000000000000000000, 3))
check("huge.power", Rational.new(10000000000, 3) ** 3,
  Rational.new(1000000000000000000000000000000, 27))
huge_keys = {}
huge_keys[huge] = "exact"
check("huge.hash_key", huge_keys[Rational.new(100000000000000000000, 3)], "exact")
huge_integer = 100000000000000000000 ## big
check("huge.add_bigint", huge + huge_integer,
  Rational.new(400000000000000000000, 3))
check("huge.subtract_bigint", huge_integer - huge,
  Rational.new(200000000000000000000, 3))
check("huge.multiply_bigint", huge * huge_integer,
  Rational.new(10000000000000000000000000000000000000000, 3))
check("huge.divide_bigint", huge / huge_integer, 1/3)
check("bigint.divide_huge", huge_integer / huge, 3/1)
check("huge.negative_denominator",
  Rational.new(100000000000000000000, -3),
  Rational.new(-100000000000000000000, 3))
check("huge.zero_reduces", Rational.new(0, huge_integer), 0/1)
