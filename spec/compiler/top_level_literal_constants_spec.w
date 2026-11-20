# A top-level name assigned once from a float literal (bare or `## f64`) or a
# bare integer literal reads as that literal inside function and method bodies
# (collect_top_level_static_types, lower_var, inline_literal_consts), so typed
# loops over it run as fast as with the literal written in. Everything here must
# read exactly as it does on the interpreter: shadowing locals, parameters,
# block parameters and captures win; reassigned names are not constants.
KF = ~0.97
KD = ~0.45 ## f64
KNEG = ~-1.5
KN = 7
KR = ~1.0
KR = ~2.0
KBIG = 900000000000000000
kl = ~0.5
kn = 3

-> check(name, got, want)
  if got != want
    << "FAIL " + name + ": got " + got.to_s() + ", want " + want.to_s()
    exit(1)
  << "PASS " + name

-> typed_sum(a, n) (f64[] i64) f64
  acc = ~0.0 ## f64
  i = 0 ## i64
  while i < n
    acc = (acc + a[(i * KN) % n] * KF - a[i] / KD + KNEG) ## f64
    i += 1
  acc

-> literal_sum(a, n) (f64[] i64) f64
  acc = ~0.0 ## f64
  i = 0 ## i64
  while i < n
    acc = (acc + a[(i * 7) % n] * ~0.97 - a[i] / ~0.45 + ~-1.5) ## f64
    i += 1
  acc

-> local_shadow
  kl = ~2.5
  kl * ~2.0

-> param_shadow(kl)
  kl * ~2.0

-> typed_param_shadow(kn) (i64) i64
  kn * 3

-> block_param_shadow
  [~1.0, ~2.0].map ->(kl) kl * ~2.0

-> capture_shadow
  kl = ~9.0
  f = ->(x) x * kl
  f.call(~2.0)

-> reassigned
  KR * ~3.0

-> untyped(n)
  n * KN

-> big
  KBIG + 1

+ Lamp
  -> new(@w)
  -> scaled
    @w * KF

a = f64[50]
i = 0
while i < 50
  a[i] = Math.sin(i.to_f * ~0.3)
  i += 1
check("typed loop equals the literal loop", typed_sum(a, 50) == literal_sum(a, 50), true)
check("local shadows the constant", local_shadow(), ~5.0)
check("parameter shadows the constant", param_shadow(~4.0), ~8.0)
check("typed parameter shadows the constant", typed_param_shadow(5), 15)
check("block parameter shadows the constant", block_param_shadow(), [~2.0, ~4.0])
check("captured local shadows the constant", capture_shadow(), ~18.0)
check("reassigned name reads its last value", reassigned(), ~6.0)
check("untyped arithmetic", untyped(6), 42)
check("large integer stays exact", big(), 900000000000000001)
check("method body", Lamp.new(~2.0).scaled(), ~1.94)
check("top-level read", KF * ~2.0, ~1.94)
check("negative literal", KNEG * ~2.0, ~-3.0)

-> lower_const_typed(x) (f64) f64
  (x * kl + kn) ## f64

check("lowercase constant in typed code", lower_const_typed(~4.0), ~5.0)
check("typed parameter shadow, int", typed_param_shadow(5), 15)
