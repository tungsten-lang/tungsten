# Enumerable combinators must dispatch through their trait-expanded Tungsten
# bodies. Hash keeps its public two-argument each/map contract while all other
# inherited combinators operate on canonical [key, value] entries.

-> check(name, condition)
  if !condition
    << "FAIL " + name
    exit(1)

plain = [1, 2, 3, 4]
mapped = plain.map -> (value)
  value * 3
check("array map", mapped.size == 4 && mapped[0] == 3 && mapped[1] == 6 && mapped[2] == 9 && mapped[3] == 12)

typed = i16[3]
typed[0] = -2
typed[1] = 0
typed[2] = 7
typed_map = typed.map -> (value)
  value + 5
check("typed array map", typed_map.size == 3 && typed_map[0] == 3 && typed_map[1] == 5 && typed_map[2] == 12)

check("empty array map", ([].map -> (value) value).size == 0)

hash = {a: 2, b: 5, c: 9}
hash_map = hash.map -> (key, value)
  key.to_s + value.to_s
check("hash map size", hash_map.size == 3)
check("hash map pair args", hash_map.include?("a2") && hash_map.include?("b5") && hash_map.include?("c9"))

pairs = hash.to_a
check("hash to_a size", pairs.size == 3)
pair_products = pairs.map -> (pair)
  pair[1] * 2
check("hash canonical entries", pair_products.include?(4) && pair_products.include?(10) && pair_products.include?(18))

selected = hash.select -> (key, value)
  !(value < 5)
check("hash select entries", selected.size == 2)
selected_values = selected.map -> (pair)
  pair[1]
check("hash select values", selected_values.include?(5) && selected_values.include?(9))

reduced = hash.reduce(0) -> (sum, pair)
  sum + pair[1]
check("hash reduce entry", reduced == 16)

found_pair = hash.find -> (key, value)
  value == 5
check("hash find pair",
      found_pair[0] == :b && found_pair[1] == 5)
check("hash detect missing",
      (hash.detect -> (key, value) value == 99) == nil)
check("hash first pair", hash.first.size == 2)
check("hash include pair", hash.include?([:b, 5]))
check("hash include is not key lookup",
      !hash.include?(:b) && hash.key?(:b))
check("hash all false", !(hash.all? -> (key, value) value < 9))
check("hash any true", hash.any? -> (key, value) value == 9)
check("hash none false", !(hash.none? -> (key, value) value == 2))
check("hash any no block", hash.any?)
check("hash empty false", !hash.empty?)
check("empty hash predicates",
      !({}.any?) && {}.empty?)

check("array all false", !([1, 2, 3].all? -> item < 3))
check("array any true", [1, 2, 3].any? -> item == 2)
check("array none false", !([1, 2, 3].none? -> item == 2))
check("array any truthy", [nil, false, 7].any?)
check("array empty", [].empty?)

+ EachOnly
  is Enumerable

  -> new(@items)

  -> each(&block)
    index = 0
    while index < @items.size
      block(@items[index])
      index += 1

each_only = EachOnly.new([4, 7, 9])
find_calls = 0
generic_found = each_only.find -> (item)
  find_calls += 1
  item > 4
check("generic find",
      generic_found == 7 && find_calls == 2)
check("generic first", each_only.first == 4)
check("generic include", each_only.include?(9))
all_calls = 0
generic_all = each_only.all? -> (item)
  all_calls += 1
  item < 7
check("generic all false",
      !generic_all && all_calls == 2)
check("generic any true", each_only.any? -> item == 7)
check("generic none false", !(each_only.none? -> item == 4))
check("generic empty false", !each_only.empty?)
check("generic empty true", EachOnly.new([]).empty?)

# The predicate latch is not enough: short-circuiting combinators must stop the
# source's `each` itself.  Count visits in the producer, outside the consumer
# block, so these checks catch a source that keeps yielding after the answer is
# final.
+ CountingEach
  is Enumerable

  -> new(@items)
    @visits = 0

  -> visits
    @visits

  -> each(&block)
    index = 0
    while index < @items.size
      @visits += 1
      block(@items[index])
      index += 1

counting = CountingEach.new([4, 7, 9, 12])
check("source find stops", counting.find -> item == 7)
check("source find visits", counting.visits == 2)

counting = CountingEach.new([4, 7, 9, 12])
check("source first value", counting.first == 4)
check("source first visits", counting.visits == 1)

counting = CountingEach.new([4, 7, 9, 12])
check("source include stops", counting.include?(9))
check("source include visits", counting.visits == 3)

counting = CountingEach.new([4, 7, 9, 12])
check("source all stops", !(counting.all? -> item < 9))
check("source all visits", counting.visits == 3)

counting = CountingEach.new([4, 7, 9, 12])
check("source any stops", counting.any? -> item == 7)
check("source any visits", counting.visits == 2)

counting = CountingEach.new([4, 7, 9, 12])
check("source none stops", !(counting.none? -> item == 7))
check("source none visits", counting.visits == 2)

counting = CountingEach.new([4, 7, 9, 12])
check("source take values", counting.take(2) == [4, 7])
check("source take visits", counting.visits == 2)

counting = CountingEach.new([4, 7, 9, 12])
check("source take zero", counting.take(0) == [])
check("source take zero visits", counting.visits == 0)

counting = CountingEach.new([4, 7, 9, 12])
check("source take_while values", (counting.take_while -> item < 9) == [4, 7])
check("source take_while visits failing item", counting.visits == 3)

counting = CountingEach.new([4, 7, 9, 12])
check("source empty false", !counting.empty?)
check("source empty visits", counting.visits == 1)

# Pair-yielding collections use the same stop protocol without changing their
# public `(key, value)` callback shape.
+ CountingPairs
  is Enumerable

  -> new(@pairs)
    @visits = 0

  -> visits
    @visits

  -> __enumerable_iteration_mode
    2

  -> __enumerable_yields_pair?
    true

  -> each(&block)
    index = 0
    while index < @pairs.size
      @visits += 1
      pair = @pairs[index]
      block(pair[0], pair[1])
      index += 1

pair_source = CountingPairs.new([[:a, 2], [:b, 5], [:c, 9]])
check("pair source first", pair_source.first == [:a, 2])
check("pair source first visits", pair_source.visits == 1)

pair_source = CountingPairs.new([[:a, 2], [:b, 5], [:c, 9]])
check("pair source find", (pair_source.find -> (key, value) value == 5) == [:b, 5])
check("pair source find visits", pair_source.visits == 2)

pair_source = CountingPairs.new([[:a, 2], [:b, 5], [:c, 9]])
check("pair source any", pair_source.any? -> (key, value) value == 5)
check("pair source any visits", pair_source.visits == 2)

pair_source = CountingPairs.new([[:a, 2], [:b, 5], [:c, 9]])
check("pair source take", pair_source.take(2) == [[:a, 2], [:b, 5]])
check("pair source take visits", pair_source.visits == 2)

# A right-unbounded producer is the semantic proof: every operation below
# would hang if Enumerable merely stopped calling its predicate while allowing
# the source to continue.
+ InfiniteEach
  is Enumerable

  -> new
    @visits = 0

  -> visits
    @visits

  -> each(&block)
    item = 0
    while true
      @visits += 1
      block(item)
      item += 1

infinite = InfiniteEach.new
check("infinite find", (infinite.find -> item == 3) == 3)
check("infinite find visits", infinite.visits == 4)

infinite = InfiniteEach.new
check("infinite first", infinite.first == 0)
check("infinite first visits", infinite.visits == 1)

infinite = InfiniteEach.new
check("infinite include", infinite.include?(4))
check("infinite include visits", infinite.visits == 5)

infinite = InfiniteEach.new
check("infinite all", !(infinite.all? -> item < 3))
check("infinite all visits", infinite.visits == 4)

infinite = InfiniteEach.new
check("infinite any", infinite.any? -> item == 2)
check("infinite any visits", infinite.visits == 3)

infinite = InfiniteEach.new
check("infinite none", !(infinite.none? -> item == 3))
check("infinite none visits", infinite.visits == 4)

infinite = InfiniteEach.new
check("infinite take", infinite.take(3) == [0, 1, 2])
check("infinite take visits", infinite.visits == 3)

infinite = InfiniteEach.new
check("infinite take_while", (infinite.take_while -> item < 3) == [0, 1, 2])
check("infinite take_while visits", infinite.visits == 4)

infinite = InfiniteEach.new
check("infinite empty", !infinite.empty?)
check("infinite empty visits", infinite.visits == 1)

# Early termination is an unwind, so producer cleanup must still run.  This is
# why Enumerable uses a private exception signal rather than the compiler's
# currently-cheaper block-return jump, which skips intervening ensure frames.
+ EnsuredInfiniteEach
  is Enumerable

  -> new
    @finished = false

  -> finished?
    @finished

  -> each(&block)
    item = 0
    begin
      while true
        block(item)
        item += 1
    ensure
      @finished = true

ensured = EnsuredInfiniteEach.new
check("early stop runs source ensure value", ensured.first == 0)
check("early stop runs source ensure", ensured.finished?)

raised = false
begin
  EachOnly.new([1]).any? -> (item)
    raise "predicate failure"
rescue error
  raised = error == "predicate failure"
check("predicate errors propagate", raised)

<< "enumerable_native_spec: all checks passed"
