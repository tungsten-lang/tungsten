# w_bace_seed deliberately has no loader result mapping. The only operation
# capable of scheduling BigArray here is the exact w_big_array_view_range hook.

-> check(name, got, expected)
  if got != expected
    << "FAIL [name]: got=[got] expected=[expected]"
    exit(1)

base = ccall("w_bace_seed")
value = ccall("w_big_array_view_range", base, 0, 0, true)
check("range.cap", value.cap, 0)
check("range.empty", value.empty?, true)
ccall("w_bace_release", value)
ccall("w_bace_release", base)
<< "big-array no-use range: ok"
