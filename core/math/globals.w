# Math globals — opt-in top-level aliases for the Math.* surface.
#
#   use math/globals
#   << sin(0.5) + cos(0.5)
#
# Deliberately NOT loaded by default: these names (log, pow, abs, round, …)
# are common locals and would shadow-collide in code that never asked for
# them. Opting in mirrors Ruby's `include Math`, and makes python-first
# numeric code run unchanged.
#
# Each alias is a plain `->` delegation (not `fn` — the fn memoizer would
# add a cache probe in front of every call). The compiler recognizes these
# exact-delegation defs (math_global_alias_def?, lowering.w) and lowers
# calls to them as the Math intrinsic itself: raw f64 operands go straight
# to libm (call_libm_f64, vectorizable via -fveclib in loops); boxed values
# take the same w_math_* runtime path Math.<name> takes.

-> sin(x)
  Math.sin(x)

-> cos(x)
  Math.cos(x)

-> tan(x)
  Math.tan(x)

-> asin(x)
  Math.asin(x)

-> acos(x)
  Math.acos(x)

-> atan(x)
  Math.atan(x)

-> atan2(y, x)
  Math.atan2(y, x)

-> exp(x)
  Math.exp(x)

-> expm1(x)
  Math.expm1(x)

-> log(x)
  Math.log(x)

-> log1p(x)
  Math.log1p(x)

-> sqrt(x)
  Math.sqrt(x)

-> cbrt(x)
  Math.cbrt(x)

-> pow(x, y)
  Math.pow(x, y)

-> hypot(x, y)
  Math.hypot(x, y)

-> fma(x, y, z)
  Math.fma(x, y, z)

-> ldexp(x, n)
  Math.ldexp(x, n)

-> floor(x)
  Math.floor(x)

-> ceil(x)
  Math.ceil(x)

-> round(x)
  Math.round(x)

-> abs(x)
  Math.abs(x)
