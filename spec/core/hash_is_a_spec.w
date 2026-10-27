# Hash#is_a? — a Hash answers is_a?(Hash) on every engine.
#
# The compiled runtime's w_value_is_a had no Hash arm, so `{}.is_a?(Hash)`
# was false compiled (though `{}.class` printed Hash) and true interpreted.
#
# Run:
#   bin/tungsten spec/core/hash_is_a_spec.w
#   bin/tungsten run --interpret spec/core/hash_is_a_spec.w

passed = Atomic.new(0)

-> check(name, condition)
  raise "FAIL " + name if !condition
  passed.increment()
  << "PASS " + name

empty = {}
filled = {"a" => 1, "b" => [2]}
nested = {"t" => {}}

check("an empty Hash is_a? Hash", empty.is_a?(Hash))
check("a filled Hash is_a? Hash", filled.is_a?(Hash))
check("a nested Hash value is_a? Hash", nested["t"].is_a?(Hash))
check("a Hash is not an Array", !filled.is_a?(Array))
check("an Array is not a Hash", ![1, 2].is_a?(Hash))
check("a String is not a Hash", !"{}".is_a?(Hash))
check("an Int is not a Hash", !3.is_a?(Hash))
check("nil is not a Hash", !nil.is_a?(Hash))
check("the string form names Hash", filled.is_a?("Hash"))

<< "[passed.get] passed"
