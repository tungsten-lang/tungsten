# Multiple assignment over machine-typed locals: a literal right side with
# one value per target lowers through hidden typed locals, so a swap is
# plain register moves (scripts/test-multi-assign-swap-wire.sh pins the
# WIRE: no Array, no boxing).

-> expect(name, cond)
  if cond
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

-> multi_assign_fib(n) (i64) i64
  a = 0 ## i64
  b = 1 ## i64
  i = 0 ## i64
  while i < n
    a, b = b, a + b
    i += 1
  a

-> multi_assign_swap_diff(x, y) (f64 f64) f64
  x, y = y, x
  x - y

-> multi_assign_rotate(a, b, c) (i64 i64 i64) i64
  a, b, c = b, c, a
  a * 100 + b * 10 + c

expect("i64 swap in a loop", multi_assign_fib(50) == 12586269025)
expect("f64 parameter swap", multi_assign_swap_diff(~1.0, ~3.0) == ~2.0)
expect("three-way rotation", multi_assign_rotate(1, 2, 3) == 231)
