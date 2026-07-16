# No `use` and no BigArray class reference: this file is autoloaded solely by
# the exact w_big_array_view result-class hook.

-> check(name, got, expected)
  if got != expected
    << "FAIL [name]: got=[got] expected=[expected]"
    exit(1)

null_ptr = 0 ## i64
ebits = 65 ## i64
size = 7 ## i64
value = ccall_rawargs("w_big_array_view", null_ptr, ebits, size)
check("view.cap", value.cap, 7)
check("view.empty", value.empty?, false)
ccall("w_bace_release", value)
<< "big-array no-use view: ok"
