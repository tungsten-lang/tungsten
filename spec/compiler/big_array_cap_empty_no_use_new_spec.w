# No `use` and no BigArray class reference: this file is autoloaded solely by
# the exact w_big_array_new result-class hook.

-> check(name, got, expected)
  if got != expected
    << "FAIL [name]: got=[got] expected=[expected]"
    exit(1)

ebits = 65 ## i64
cap = 7 ## i64
value = ccall_rawargs("w_big_array_new", ebits, cap)
check("new.cap", value.cap, 7)
check("new.empty", value.empty?, true)
ccall("w_bace_release", value)
<< "big-array no-use new: ok"
