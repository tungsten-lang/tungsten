# Deliberately no `use`, literal, typed-array syntax, or argv: exact native
# factory return-type hooks must schedule Array on their own.

-> check(name, got, expected)
  if got != expected
    << "FAIL [name]: got=[got] expected=[expected]"
    exit(1)

empty = ccall("w_array_new_empty")
check("ccall.size", empty.size, 0)
check("ccall.cap", empty.cap, 8)
check("ccall.empty", empty.empty?, true)
check("ccall.first", empty.first, nil)
check("ccall.last", empty.last, nil)

ebits = 8 ## i64
length = 3 ## i64
zeros = ccall_rawargs("w_array_zeros", ebits, length)
check("raw.size", zeros.size, 3)
check("raw.cap", zeros.cap, 3)
check("raw.empty", zeros.empty?, false)
check("raw.first", zeros.first, 0)
check("raw.last", zeros.last(1, 2, 3), 0)

<< "autoload.factories: ok"
