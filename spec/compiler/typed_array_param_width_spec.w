# Regression: a typed-array parameter's element WIDTH must be enforced across
# the native-fn boundary.
#
# A fn declared `(i64[])` compiles its body against an 8-byte element stride,
# but the argument crosses as a plain WValue handle — LLVM sees `i64` either
# way. Handing it a 32-bit-element array used to write 8-byte elements into
# 4-byte slots and past the end of the allocation, with no diagnostic and exit
# status 0; the damage surfaced later as an unrelated bug.
#
# Two enforcement points, so the cost lands only where it must:
#   * statically decidable mismatch -> E_LOWER_TYPED_ARG_MISMATCH at lower time
#     (covered by the Ruby-side compile_regression pin, not here — this file
#     has to compile).
#   * width unknown at the call site -> w_check_array_ebits guard, raising.
# Same-width differences (u64[] vs i64[]) keep the stride and stay legal.

-> fill64(a) (i64[]) i64
  a[0] = 11
  a[1] = 22
  a[2] = 33
  a[3] = 44
  0

-> fill32(a) (i32[]) i64
  a[0] = 7
  a[1] = 8
  0

# Launders the element type: the call site sees only an untyped fn return, so
# lowering cannot prove the width and must fall back to the runtime guard.
-> hide(box)
  box[0]

-> check(label, got, want)
  if got == want
    << "PASS " + label
  else
    << "FAIL " + label + " got=" + got.to_s() + " want=" + want.to_s()
    exit 1

# --- statically known, matching: no guard emitted, plain call
known = i64[4]
z = fill64(known)
check("known i64[] slot0", known[0], 11)
check("known i64[] slot3", known[3], 44)

# --- width unknown but correct: guard passes
hidden = i64[4]
z2 = fill64(hide([hidden]))
check("hidden i64[] slot0", hidden[0], 11)
check("hidden i64[] slot3", hidden[3], 44)

# --- same width, different signedness: stride is identical, still legal
unsigned = u64[4]
z3 = fill64(hide([unsigned]))
check("hidden u64[] slot0", unsigned[0], 11)

# --- narrower declaration, matching argument
narrow = i32[4]
z4 = fill32(hide([narrow]))
check("hidden i32[] slot0", narrow[0], 7)
check("hidden i32[] slot1", narrow[1], 8)

# --- WIDTH MISMATCH: 32-bit elements into an i64[] parameter must raise,
#     not overrun the allocation.
victim = i32[4]
neighbor = i32[4]
j = 0
while j < 4
  victim[j] = 0
  neighbor[j] = 777
  j += 1
raised = false
begin
  z5 = fill64(hide([victim]))
rescue e
  raised = true
check("i32[] into i64[] raises", raised, true)
check("victim slot2 untouched", victim[2], 0)
check("neighbor slot0 untouched", neighbor[0], 777)
check("neighbor slot3 untouched", neighbor[3], 777)

# --- polymorphic array into a typed parameter: w64 slots hold boxed WValues,
#     so raw stores would mint fake pointers. Distinct diagnostic, also raising.
poly = [1, 2, 3, 4]
raised2 = false
begin
  z6 = fill64(hide([poly]))
rescue e2
  raised2 = true
check("polymorphic into i64[] raises", raised2, true)
check("poly slot0 untouched", poly[0], 1)

<< "typed_array_param_width_spec: all checks passed"
