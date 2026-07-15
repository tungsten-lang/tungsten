# Regression: raw-call ABI selection must be independent of definition order.
# A typed caller lowered before a raw-i64 callee used to box its arguments and
# expect a boxed result; the later callee accepted/returned raw machine ints.
# Both sides use LLVM i64, so this linked successfully and failed only when the
# bogus WValue was consumed at runtime.

-> forward_scalar_caller(n, slot) (i64 i64) i64
  forward_scalar_callee(n, slot)

-> forward_scalar_callee(n, slot) (i64 i64) i64
  n * 10 + slot

-> forward_mixed_caller(values, increment) (i64[] i64) i64
  forward_mixed_callee(values, increment)

-> forward_mixed_callee(values, increment) (i64[] i64) i64
  values[0] + increment

# Narrow passthrough callees use the raw-int ABI even when their callers do
# not.  This covers forward registration of that second raw-callable flavor.
-> forward_u32_caller(value) (u32) u32
  forward_u32_callee(value)

-> forward_u32_callee(value) (u32) u32
  value

-> forward_raw_expect(name, got, want)
  if got == want
    return 0
  << "FAIL " + name + " got=" + got.to_s() + " want=" + want.to_s()
  exit(1)

forward_raw_expect("scalar", forward_scalar_caller(4, 2), 42)

values = i64[1]
values[0] = 40
forward_raw_expect("mixed array/scalar", forward_mixed_caller(values, 2), 42)
uvalues = u32[1]
uvalues[0] = 4000000000
forward_raw_expect("u32 passthrough", forward_u32_caller(uvalues[0]), 4000000000)

<< "PASS forward typed raw calls"
