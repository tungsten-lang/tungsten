# Tree-walker coverage for the source-defined BigArray query leaves. The
# interpreter's narrow w_big_array_view bridge exposes the real native header.

use core/big_array

-> fail_check(name, got, expected)
  << "FAIL [name]: got=[got] ([type(got)]) expected=[expected] ([type(expected)])"
  exit(1)

-> check(name, got, expected)
  if got != expected || type(got) != type(expected)
    fail_check(name, got, expected)

-> check_view(value, expected, empty)
  recv = ccall("w_big_array_view", 0, 65, value)
  check("cap.[expected]", recv.cap, expected)
  check("cap.[expected].extra", recv.cap(1, 2, 3), expected)
  check("empty.[expected]", recv.empty?, empty)
  check("empty.[expected].extra", recv.empty?(1, 2, 3), empty)

check_view(0, 0, true)
check_view(1, 1, false)
check_view(140_737_488_355_327, 140_737_488_355_327, false)
check_view(140_737_488_355_328, 140_737_488_355_328, false)
check_view(-140_737_488_355_328, -140_737_488_355_328, false)
check_view(-140_737_488_355_329, -140_737_488_355_329, false)
check_view(9_223_372_036_854_775_807, 9_223_372_036_854_775_807, false)
check_view(-9_223_372_036_854_775_808, -9_223_372_036_854_775_808, false)

<< "big-array cap/empty interpreter: ok"
