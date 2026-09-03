# Tuple — heterogeneous, fixed, index-addressable value grouping (core/tuple.w).
#
# Run:
#   bin/tungsten run --interpret spec/core/tuple_spec.w
#   bin/tungsten -o /tmp/tuple_spec spec/core/tuple_spec.w && /tmp/tuple_spec

passed = Atomic.new(0)

-> check(name, condition)
  raise "FAIL " + name if !condition
  passed.increment()
  << "PASS " + name

t = Tuple.new([1, "two", ~3.0])
check("new keeps items", t.items == [1, "two", ~3.0])
check("of builds a tuple", Tuple.of([1, 2]).items == [1, 2])
check("type", type(t) == "Tuple")

# indexing / size
check("index 0", t[0] == 1)
check("index 1", t[1] == "two")
check("index 2", t[2] == ~3.0)
check("index negative", t[-1] == ~3.0)
check("index out of range", t[3] == nil)
check("size", t.size == 3)
check("length", t.length == 3)
check("first", t.first == 1)
check("last", t.last == ~3.0)
check("empty? false", !t.empty?)

empty = Tuple.new([])
check("empty size", empty.size == 0)
check("empty? true", empty.empty?)
check("empty first", empty.first == nil)
check("empty last", empty.last == nil)
check("empty to_s", empty.to_s == "()")

# conversion
check("to_a", t.to_a == [1, "two", ~3.0])
check("to_array", t.to_array == [1, "two", ~3.0])
check("to_s", Tuple.new([1, 2, 3]).to_s == "(1, 2, 3)")
check("to_s mixed", Tuple.new([1, "two", ~3.5]).to_s == "(1, two, 3.5)")
check("to_s single", Tuple.new([7]).to_s == "(7)")

# equality is structural, element-wise
check("== same", Tuple.new([1, 2]) == Tuple.new([1, 2]))
check("== differs", !(Tuple.new([1, 2]) == Tuple.new([1, 3])))
check("== size differs", !(Tuple.new([1, 2]) == Tuple.new([1, 2, 3])))
check("== exact types", !(Tuple.new([2]) == Tuple.new([~2.0])))
check("eql? same", Tuple.new(["a", nil]).eql?(Tuple.new(["a", nil])))
check("eql? against array", Tuple.new([1, 2]).eql?([1, 2]))
check("!= differs", Tuple.new([1]) != Tuple.new([2]))
check("== empty", Tuple.new([]) == Tuple.new([]))

# each yields every item in order and returns self
seen = []
ret = t.each -> (x)
  seen.push(x)
check("each order", seen == [1, "two", ~3.0])
check("each returns self", ret == t)

# Enumerable combinators (index-based iteration mode)
nums = Tuple.new([3, 1, 2])
check("map", nums.map(-> (x) x * 2) == [6, 2, 4])
check("select", nums.select(-> (x) x > 1) == [3, 2])
check("sum", nums.sum == 6)
check("include?", nums.include?(2) && !nums.include?(9))
check("to_a via trait matches items", nums.to_a == [3, 1, 2])
check("count", nums.count == 3)
check("reduce", nums.reduce(0, -> (acc, x) acc + x) == 6)
check("min/max", nums.min == 1 && nums.max == 3)
check("sort", nums.sort == [1, 2, 3])
check("unicode item", Tuple.new(["日本", "é"])[0] == "日本")
check("nested tuple", Tuple.new([Tuple.new([1]), 2])[0][0] == 1)

<< "ALL PASS tuple_spec ([passed.load()] checks)"
