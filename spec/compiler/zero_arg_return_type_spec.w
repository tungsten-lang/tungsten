# `-> f() (T)`: after an empty parameter list, a lone parenthesized type is the
# return type (compiler/lib/parser/definitions.w).  Native lowering rejected
# every call from 2026-07-25 ("no declared signature of 'f' accepts ()")
# because it read the type as a one-parameter signature.

-> check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> answer() (i64)
  42

-> half() (f64)
  0.5

-> label() (String)
  "zero"

-> twice(x) (i64) i64
  x * 2

-> plain() i64
  7

check("() (i64) returns an integer", answer() == 42)
check("() (f64) returns a float", half() == 0.5)
check("() (String) returns a string", label() == "zero")
check("typed one-parameter signature unchanged", twice(21) == 42)
check("bare return type unchanged", plain() == 7)
<< "zero_arg_return_type_spec: all checks passed"
