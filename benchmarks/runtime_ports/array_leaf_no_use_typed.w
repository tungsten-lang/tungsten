# Deliberately no `use` and no plain array literal: :typed_array_new itself
# must schedule Array's source method table.

-> check(name, got, expected)
  if got != expected
    << "FAIL [name]: got=[got] expected=[expected]"
    exit(1)

value = u8[3]
value[0] = 7
value[2] = 249
check("typed.size", value.size, 3)
check("typed.cap", value.cap, 3)
check("typed.empty", value.empty?, false)
check("typed.first", value.first, 7)
check("typed.last", value.last, 249)
check("typed.extra", value.first(1, 2, 3), 7)

<< "autoload.typed: ok"
