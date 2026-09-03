# Tree-walker coverage for the source-defined BigArray query leaves. The
# interpreter's narrow w_big_array_view bridge exposes the real native header.

use core/big_array

-> fail_check(name, got, expected)
  << "FAIL [name]: got=[got] ([type(got)]) expected=[expected] ([type(expected)])"
  exit(1)

# Surplus arguments are an error on both engines (E_LOWER_ARITY at compile
# time where the callee is known; the interpreter raises at the call).
-> surplus_rejected?(f)
  begin
    f.call
    false
  rescue surplus_error
    true

-> check(name, got, expected)
  if got != expected || type(got) != type(expected)
    fail_check(name, got, expected)

-> check_view(value, expected, empty)
  recv = ccall("w_big_array_view", 0, 65, value)
  check("cap.[expected]", recv.cap, expected)
  check("cap.[expected].extra rejected", surplus_rejected?(->() recv.cap(1, 2, 3)), true)
  check("empty.[expected]", recv.empty?, empty)
  check("empty.[expected].extra rejected", surplus_rejected?(->() recv.empty?(1, 2, 3)), true)

check_view(0, 0, true)
check_view(1, 1, false)
check_view(140_737_488_355_327, 140_737_488_355_327, false)
check_view(140_737_488_355_328, 140_737_488_355_328, false)
check_view(-140_737_488_355_328, -140_737_488_355_328, false)
check_view(-140_737_488_355_329, -140_737_488_355_329, false)
check_view(9_223_372_036_854_775_807, 9_223_372_036_854_775_807, false)
check_view(-9_223_372_036_854_775_808, -9_223_372_036_854_775_808, false)

<< "big-array cap/empty interpreter: ok"
