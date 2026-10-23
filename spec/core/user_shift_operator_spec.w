# `obj << x` calls the class's own `<<` on both engines. The compiled runtime
# (w_bit_shl) sent every non-integer, non-string, non-array left operand to
# `+`, so a class defining `<<` (FileHandle, a log, a builder) failed with
# "undefined method '+'"; the tree-walker fed the object to the primitive
# shift and failed too (2026-10-21). A class without its own `<<` keeps the
# existing fallback to its `+`.

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

+ Log
  -> new
    @items = []

  -> <<(item)
    @items.push(item)
    self

  -> size
    @items.size()

  -> first
    @items[0]

+ Adder
  -> new(@v)

  ro :v

  -> +(other)
    Adder.new(@v + other)

log = Log.new
log << "a" << "b"
check("<< reaches the class's method", log.size, 2)
check("chained << returns self", log.first, "a")

sum = Adder.new(1) << 4
check("no << falls back to +", sum.v, 5)
