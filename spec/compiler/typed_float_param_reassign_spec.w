# Typed float parameters the body reassigns (compiled and interpreted).
# (2026-11-21, Blade image decoders: `-> eotf(tr, v) (i64 f64) f64` with
# `v = ~0.0 if v < ~0.0` failed to compile: "'%.v' defined with type 'i64' but
# expected 'double'".) A reassigned parameter gets a stack slot, and the
# prologue made it an i64 slot holding the BOXED argument, while every reader
# and writer of a machine-float variable loads/stores its slot as a raw
# double. The slot is now a double (float for f32) holding the converted
# entry value -- the same treatment captured float parameters get
# (typed_float_param_capture_spec).
#
# Run: bin/tungsten -o /tmp/tfpr spec/compiler/typed_float_param_reassign_spec.w && /tmp/tfpr

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

# conditional reassignment, then a read
-> clamp0(v) (f64) f64
  v = ~0.0 if v < ~0.0
  v

# reassignment inside a branch with an early return
-> eotf(tr, v) (i64 f64) f64
  v = ~0.0 if v < ~0.0
  if tr == 1
    return v * ~2.0
  v

# compound assignment in a loop
-> grow(v, n) (f64 i64) f64
  i = 0
  while i < n
    v += ~0.5
    i += 1
  v

# f32 parameter
-> halve(v) (f32) f32
  v = v / (2.0 ## f32)
  v

check("clamp negative", clamp0(~-1.5), ~0.0)
check("clamp positive untouched", clamp0(~2.25), ~2.25)
check("early return branch", eotf(1, ~0.75), ~1.5)
check("fallthrough branch", eotf(0, ~0.75), ~0.75)
check("clamped then returned", eotf(1, ~-3.0), ~0.0)
x = 3
check("dynamic float argument", clamp0(x / ~4.0), ~0.75)
check("compound assign in loop", grow(~1.0, 4), ~3.0)
check("f32 parameter", halve(3.0 ## f32) == (1.5 ## f32), true)
<< "typed_float_param_reassign_spec: all passed"
