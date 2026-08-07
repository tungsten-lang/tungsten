# Native Math intrinsic accuracy, edge semantics, boxed/raw dispatch, and FMA
# interpreter/compiler parity.
#
# Focused validation:
#   bin/tungsten run spec/core/math_native_intrinsics_spec.w
#   bin/tungsten compile spec/core/math_native_intrinsics_spec.w \
#     --out /tmp/math-native-intrinsics-spec --release --native

use core/math

-> check(name, condition)
  if !condition
    raise "FAIL " + name
  << "PASS " + name

-> close?(got, want, tolerance)
  difference = got - want
  difference = ~0.0 - difference if difference < ~0.0
  difference <= tolerance

check("cbrt negative", Math.cbrt(~-8.0) == ~-2.0)
check("cbrt preserves negative zero", Math.cbrt(~-0.0).to_s.starts_with?("-"))
check("cbrt tiny", close?(Math.cbrt(~1.0e-300), ~1.0e-100, ~2.0e-116))

check("hypot 3-4-5", Math.hypot(~3.0, ~4.0) == ~5.0)
check("hypot avoids overflow",
      close?(Math.hypot(~3.0e200, ~4.0e200), ~5.0e200, ~1.0e185))
check("hypot avoids underflow",
      close?(Math.hypot(~3.0e-200, ~4.0e-200), ~5.0e-200, ~1.0e-215))

near_one = ~0.9999999999999999
check("asin near one",
      close?(Math.asin(near_one), ~1.5707963118937354, ~2.0e-16))
check("acos near one",
      close?(Math.acos(near_one), ~1.4901161193847656e-8, ~1.0e-23))
check("atan one", Math.atan(~1.0) == ~0.7853981633974483)

# Array access keeps operands boxed, exercising the WValue wrappers.
boxed = [~8.0, ~6.0]
check("boxed cbrt wrapper", Math.cbrt(boxed[0]) == ~2.0)
check("boxed hypot wrapper", Math.hypot(boxed[0], boxed[1]) == ~10.0)
check("integer coercion", Math.cbrt(8) == ~2.0)

# The source atan2 fallback chooses +pi for (-0,-1); native atan2 must retain
# the sign of y and select -pi.
negative_pi = Math.atan2(~-0.0, ~-1.0)
check("atan2 signed-zero quadrant",
      negative_pi < ~0.0 && close?(negative_pi, ~-3.141592653589793, ~1.0e-15))

# The third operand is the separately rounded product. A genuine fused
# multiply-add exposes its nonzero rounding residual; a*b+c rounds to zero.
product = ~1.7 * ~3.3
residual = fma(~1.7, ~3.3, ~0.0 - product)
check("fma is single-rounded", residual != ~0.0)

check("asin domain", Math.asin(~2.0).nan?)
check("acos domain", Math.acos(~2.0).nan?)

<< "math_native_intrinsics_spec: all checks passed"
