# Native expm1/log1p accuracy, edge semantics, and boxed/raw dispatch parity.
#
# Focused validation:
#   bin/tungsten run spec/core/math_expm1_log1p_spec.w
#   bin/tungsten compile spec/core/math_expm1_log1p_spec.w \
#     --out /tmp/math-expm1-log1p-spec --release --native

-> check(name, condition)
  if !condition
    raise "FAIL " + name
  << "PASS " + name

-> close?(got, want, tolerance)
  difference = got - want
  difference = ~0.0 - difference if difference < ~0.0
  difference <= tolerance

check("expm1 preserves tiny positive input",
      close?(Math.expm1(~1.0e-16), ~1.0e-16, ~1.0e-31))
check("log1p preserves tiny positive input",
      close?(Math.log1p(~1.0e-16), ~1.0e-16, ~1.0e-31))
check("expm1 avoids cutoff cancellation",
      close?(Math.expm1(~1.0e-5), ~1.0000050000166668e-5, ~2.0e-20))
check("log1p avoids cutoff cancellation",
      close?(Math.log1p(~1.0e-5), ~9.999950000333332e-6, ~2.0e-20))

# Array access keeps the argument boxed, exercising the WValue ABI wrappers
# instead of only the compiler's raw-f64 libm path.
boxed = [~1.0e-12]
check("boxed expm1 wrapper",
      close?(Math.expm1(boxed[0]), ~1.0000000000005e-12, ~2.0e-27))
check("boxed log1p wrapper",
      close?(Math.log1p(boxed[0]), ~9.999999999995e-13, ~2.0e-27))
check("integer expm1 coercion",
      close?(Math.expm1(1), ~1.718281828459045, ~2.0e-15))
check("integer log1p coercion",
      close?(Math.log1p(1), ~0.6931471805599453, ~2.0e-16))

check("expm1 preserves negative zero",
      Math.expm1(~-0.0).to_s.starts_with?("-"))
check("log1p preserves negative zero",
      Math.log1p(~-0.0).to_s.starts_with?("-"))

positive_infinity = Math.exp(~1000.0)
negative_infinity = ~0.0 - positive_infinity
check("expm1 positive infinity", Math.expm1(positive_infinity).infinite?)
check("expm1 negative infinity", Math.expm1(negative_infinity) == ~-1.0)
check("log1p positive infinity", Math.log1p(positive_infinity).infinite?)
log1p_minus_one = Math.log1p(~-1.0)
check("log1p minus one", log1p_minus_one.infinite? && log1p_minus_one < ~0.0)
check("log1p domain", Math.log1p(~-2.0).nan?)

<< "math_expm1_log1p_spec: all checks passed"
