# No `use` directives: this pins loader coverage for runtime-created receivers
# whose class is visible only in a low-level C factory name, plus ordinary
# constructor paths whose ClassRef already triggers core/tungsten autoload.

-> check(name, got, expected)
  if got != expected
    << "FAIL [name]: got=[got] expected=[expected]"
    exit(1)

small_ebits = 8 ## i64
small_size = 7 ## i64
null_ptr = 0 ## i64
small_from_c = ccall_rawargs("w_small_array_new", small_ebits, small_size, null_ptr)
check("ccall.small.size", small_from_c.size, 7)
check("ccall.small.cap", small_from_c.cap, 7)
check("ccall.small.empty", small_from_c.empty?, false)
check("ccall.small.extra", small_from_c.size(1, 2, 3), 7)

big_ebits = 65 ## i64
big_size = 140_737_488_355_328 ## i64
big_from_c = ccall_rawargs("w_big_array_view", null_ptr, big_ebits, big_size)
check("ccall.big.size-overflow", big_from_c.size, 140_737_488_355_328)
check("ccall.big.extra", big_from_c.size(1, 2, 3), 140_737_488_355_328)

small_from_constructor = SmallArray.new(:u8, 7)
check("constructor.small.size", small_from_constructor.size, 7)
check("constructor.small.cap", small_from_constructor.cap, 7)
check("constructor.small.empty", small_from_constructor.empty?, false)

big_from_constructor = BigArray.new(:w64, 7)
check("constructor.big.size", big_from_constructor.size, 0)

<< "autoload: ok (no-use ccall factories and SmallArray/BigArray constructors)"
