# Array.new and SmallArray.new must agree across native, self-hosted, and Ruby
# execution. In particular, Array's fill is one repeated object reference,
# while SmallArray has fixed size and coerces stores to its element tier.

-> check(name, ok)
  if ok
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

+ ArrayArgumentProbe
  -> .size_of(values)
    values.size()

# A parenthesized array literal is an ordinary positional argument. The
# interpreter once peeled it off as a trailing block payload, turning
# `A.f([1, 2])` into a block-bearing zero-argument call.
check("array.literal.class_method_arg", ArrayArgumentProbe.size_of([1, 2]) == 2)

empty = Array.new()
check("array.new.empty", empty.size == 0)

defaults = Array.new(3)
check("array.new.default_nil", defaults.size == 3 && defaults[0] == nil && defaults[2] == nil)

fill = [1]
aliases = Array.new(2, fill)
aliases[0].push(2)
check("array.new.fill_alias", aliases[1].size == 2 && aliases[1][1] == 2)

array_class = Array
dynamic = array_class.new(2, 7)
check("array.new.dynamic_class", dynamic.size == 2 && dynamic[0] == 7 && dynamic[1] == 7)

array_bad_size = false
begin
  Array.new(-1)
rescue error
  array_bad_size = true
check("array.new.negative", array_bad_size)

array_bad_type = false
begin
  Array.new("2")
rescue error
  array_bad_type = true
check("array.new.type", array_bad_type)

small_class = SmallArray
kind = :i32
signed = small_class.new(kind, 3)
signed[0] = 0xFFFFFFFF
signed[-1] = -3
check("smallarray.dynamic_type", signed.size == 3 && signed[0] == -1 && signed[2] == -3)

bytes = SmallArray.new(:u8, 2)
bytes[0] = 300
bytes[8] = 99
check("smallarray.coerce_bounds", bytes[0] == 44 && bytes[8] == nil && bytes.size == 2)
check("smallarray.identity", type(bytes) == "SmallArray")

small_empty = SmallArray.new(:w64, 0)
check("smallarray.empty", small_empty.size == 0)

small_bad_size = false
begin
  SmallArray.new(:i32, 256)
rescue error
  small_bad_size = true
check("smallarray.bounds", small_bad_size)
