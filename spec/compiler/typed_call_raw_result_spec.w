# Regression (studio engine, 2026-10-22): an i64 result crossing a call
# between typed functions must stay a wrapping machine int. Three gaps made
# the compiled engine re-box it through w_int (a heap BigInt from 2^47 up, so
# 1M SplitMix calls leaked ~490 MB) and then promote instead of wrap:
#   * a local bound to a typed-signature call (`x = mix(a)`) stayed a boxed
#     slot, because raw-call analysis looked the callee up by its bare name,
#     not its overload key (`mix|i64`) or lower_call's unique-overload
#     fallback for untyped arguments;
#   * a typed signature with an f64/f32 parameter never got the raw ABI, so
#     `(f64[] i64 f64) i64` returned its result boxed;
#   * a typed fn whose tail used such a local (`x = mix(a); mix(x ^ b)`) was
#     denied the raw ABI by the prepass and returned its result boxed.
# A boxed local promotes where the interpreter (and an inline expression)
# wraps, so each probe below multiplies past 2^63 and shifts: the wrapped
# answer is -3, the promoted one 13. The interpreter is the oracle.

-> trr_check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit(1)

-> trr_mix(x) (i64) i64
  x * 3

# Local bound to a typed call in a typed caller.
-> trr_local(a) (i64) i64
  x = trr_mix(a)
  x = x * 5
  x >> 60

# The same arithmetic with no call: what every probe must agree with.
-> trr_inline(a) (i64) i64
  x = a * 3
  x = x * 5
  x >> 60

# Float parameters: the int result still crosses raw.
-> trr_scaled(xs, a, s) (f64[] i64 f64) i64
  f = xs[0] * s
  a * 3 + (f ## i64)

-> trr_scalar_f(a, s) (i64 f32) i64
  a * 3 + (s ## i64)

-> trr_float_caller(xs, fs, a) (f64[] f32[] i64) i64
  y = trr_scaled(xs, a, ~0.5)
  y = y * 5
  z = trr_scalar_f(a, fs[0])
  z = z * 5
  (y >> 60) * 100 + (z >> 60)

# A tail that flows through a local bound to a typed call.
-> trr_key(a, b) (i64 i64) i64
  x = trr_mix(a)
  trr_mix(x ^ b)

-> trr_key_caller(a) (i64) i64
  k = trr_key(a, 0)
  k = k * 5
  k >> 60

# An untyped caller reaches the only typed overload through lower_call's
# unknown-argument fallback, which is raw too.
-> trr_untyped_caller(a)
  x = trr_mix(a)
  x = x * 5
  x >> 60

# Forward reference: the callee is defined after its caller.
-> trr_forward_caller(a) (i64) i64
  x = trr_forward_callee(a, ~1.0)
  x = x * 5
  x >> 60

-> trr_forward_callee(a, s) (i64 f64) i64
  a * 3

# SplitMix64 finaliser chained through a local, the engine's RNG shape.
-> trr_splitmix(x) (i64) i64
  x = (x ^ ((x >> 30) & 17179869183)) * -4658895280553007687
  x = (x ^ ((x >> 27) & 137438953471)) * -7723592293110705685
  x ^ ((x >> 31) & 8589934591)

-> trr_rng_key(seed, item, frame) (i64 i64 i64) i64
  x = trr_splitmix(frame + 1)
  x = trr_splitmix(item ^ x)
  trr_splitmix(seed ^ x)

-> trr_rng_sum(n, xs) (i64 f64[]) i64
  acc = 0
  i = 0
  while i < n
    acc = acc + (trr_rng_key(7, i, 3) >> 40) + trr_scaled(xs, i, ~0.0)
    i += 1
  acc

a = 1000000000000000000
trr_check("inline wraps", trr_inline(a), -3)
trr_check("local bound to a typed call wraps", trr_local(a), -3)
xs = f64[1]
xs[0] = ~2.0
fs = f32[1]
fs[0] = ~0.25
trr_check("float-param callees return raw", trr_float_caller(xs, fs, a), -303)
trr_check("tail through a typed-call local", trr_key_caller(333333333333333334), -3)
trr_check("forward typed callee with a float param", trr_forward_caller(a), -3)
trr_check("untyped caller of a typed fn", trr_untyped_caller(a), -3)

# Full-width values cross the raw boundary exactly.
trr_check("splitmix key", trr_rng_key(7, 11, 3), 4643338794227744328)
trr_check("i64 max through a float-param fn", trr_scaled(xs, 3074457345618258602, ~0.5), 9223372036854775807)
trr_check("rng sum", trr_rng_sum(1000, xs), 186745181)
