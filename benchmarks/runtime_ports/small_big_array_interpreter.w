# Focused tree-walker coverage for the source-defined public leaves. The
# interpreter's narrow ccall allowlist converts these fixture constructors to
# the raw runtime ABI; compiled benchmark fixtures live in the sibling C file.

-> fail_check(name, got, expected)
  << "FAIL [name]: got=[got] expected=[expected]"
  exit(1)

-> check(name, got, expected)
  if got != expected || type(got) != type(expected)
    fail_check(name, got, expected)

-> check_small(size)
  value = ccall("w_small_array_new", 8, size, 0)
  check("small.[size].size", value.size, size)
  check("small.[size].cap", value.cap, size)
  check("small.[size].empty", value.empty?, size == 0)
  check("small.[size].size-extra", value.size(1, 2, 3), size)
  check("small.[size].cap-extra", value.cap(1, 2, 3), size)
  check("small.[size].empty-extra", value.empty?(1, 2, 3), size == 0)

-> check_big(size)
  value = ccall("w_big_array_view", 0, 65, size)
  check("big.[size].size", value.size, size)
  check("big.[size].size-extra", value.size(1, 2, 3), size)

check_small(0)
check_small(1)
check_small(127)
check_small(128)
check_small(255)

check_big(0)
check_big(140_737_488_355_327)
check_big(140_737_488_355_328)
check_big(-140_737_488_355_328)
check_big(-140_737_488_355_329)
check_big(9_223_372_036_854_775_807)
check_big(-9_223_372_036_854_775_808)

<< "interpreter: ok (SmallArray byte boundaries and BigArray signed-i64/i48-overflow views, including surplus arguments)"
