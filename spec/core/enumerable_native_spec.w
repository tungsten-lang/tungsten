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

<< "enumerable_native_spec: all checks passed"
