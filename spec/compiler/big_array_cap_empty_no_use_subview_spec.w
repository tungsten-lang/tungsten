# w_bace_seed deliberately has no loader result mapping. The only operation
# capable of scheduling BigArray here is the exact w_big_array_subview hook.

-> check(name, got, expected)
  if got != expected
    << "FAIL [name]: got=[got] expected=[expected]"
    exit(1)

base = ccall("w_bace_seed")
zero = 0 ## i64
value = ccall_rawargs("w_big_array_subview", base, zero, zero)
check("subview.cap", value.cap, 0)
check("subview.empty", value.empty?, true)
ccall("w_bace_release", value)
ccall("w_bace_release", base)
<< "big-array no-use subview: ok"
