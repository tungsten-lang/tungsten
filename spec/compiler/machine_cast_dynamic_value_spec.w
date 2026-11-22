# Explicit machine-int casts of values with no static integer type:
# - `gi = gp ## i64` where gp is a bare f64 local raised "expected int, got
#   double" instead of truncating like `(gp + ~0.0) ## i64`;
# - `(a > b) ## i64` failed at run time; a boolean now converts to 1 / 0 on
#   every engine.
# - `t = GLOBAL ## i32[]` inside a typed fn segfaulted: the top-level typed
#   array was stack-promoted to a SmallArray that the fn read with the
#   typed-array layout.

$failures = 0

-> check(label, got, want)
  if got != want
    << "FAIL [label]: got [got], want [want]"
    $failures = $failures + 1

-> trunc_bare(x, g) (f64 i64) i64
  gp = x * g
  gi = gp ## i64
  gi

-> trunc_neg(x) (f64) i64
  y = x * 3
  y ## i64

-> bool_cast(a, b) (i64 i64) i64
  t = (a > b) ## i64
  t + 1

-> bool_sum(a, b) (i64 i64) i64
  ((a == b) ## i64) + ((a < b) ## i64) * 2

TA = i32[8]
TA[1] = 42

-> global_cast(n) (i64) i64
  t = TA ## i32[]
  t[n]

check("bare f64 local", trunc_bare(~0.69, 4), 2)
check("bare f64 negative", trunc_neg(~-0.9), -2)
check("bool true", bool_cast(3, 2), 2)
check("bool false", bool_cast(1, 2), 1)
check("bool sum eq", bool_sum(4, 4), 1)
check("bool sum lt", bool_sum(1, 4), 2)
x = (3 > 2) ## i64
check("top-level bool", x, 1)
check("global typed array cast", global_cast(1), 42)
check("global typed array zero", global_cast(2), 0)

if $failures > 0
  exit(1)
<< "PASS machine cast dynamic value"
