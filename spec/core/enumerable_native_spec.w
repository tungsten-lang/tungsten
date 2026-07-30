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
  value >= 5
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

<< "enumerable_native_spec: all checks passed"
