# Int is the exact, auto-promoting family. Integer and BigInt are its distinct
# concrete representations; both engines must agree on subtype and overload
# selection at the inline boundary.

-> check(name, condition)
  if condition
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

small = 7
big = 1 << 100

check("small.type", type(small) == "Integer")
check("small.integer", small.is_a?(Integer))
check("small.int", small.is_a?(Int))
check("small.not_bigint", !small.is_a?(BigInt))

check("big.type", type(big) == "BigInt")
check("big.bigint", big.is_a?(BigInt))
check("big.int", big.is_a?(Int))
check("big.not_integer", !big.is_a?(Integer))

promoted = 140_737_488_355_327 + 1
demoted = big - big
check("overflow.promotes", type(promoted) == "BigInt")
check("fitting_result.demotes", type(demoted) == "Integer")

+ IntegerTowerProbe
  -> classify/1(BigInt)
    "bigint"

  -> classify/1(Integer)
    "integer"

  -> classify/1(Int)
    "int"

+ IntegerTowerUserInt < Int
+ IntegerTowerUserInteger < Integer
+ IntegerTowerUserBigInt < BigInt

probe = IntegerTowerProbe.new
check("overload.integer", probe.classify(small) == "integer")
check("overload.bigint", probe.classify(big) == "bigint")
check("overload.int_fallback",
      probe.classify(IntegerTowerUserInt.new) == "int")
check("overload.integer_subclass",
      probe.classify(IntegerTowerUserInteger.new) == "integer")
check("overload.bigint_subclass",
      probe.classify(IntegerTowerUserBigInt.new) == "bigint")

-> opaque_to_f(value)
  value.to_f

small_float = opaque_to_f(7)
zero_float = opaque_to_f(0)
check("to_f.small.type", type(small_float) == "Float")
check("to_f.small.value", small_float == ~7.0)
check("to_f.zero.type", type(zero_float) == "Float")
check("to_f.zero.value", zero_float == ~0.0)

<< "integer_tower_spec: all checks passed"
