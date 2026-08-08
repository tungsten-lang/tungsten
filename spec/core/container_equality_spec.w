# Structural container equality: Array#== and Hash#== compare contents
# (recursively) on every engine. Hash equality is order-INDEPENDENT —
# insertion order is an iteration guarantee, not part of a hash's value.
# Reference cycles terminate (a pair already under comparison is presumed
# equal, Ruby-style).
#
# Run: `bin/tungsten -o /tmp/ceq spec/core/container_equality_spec.w && /tmp/ceq`

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

# -- Arrays: same contents equal, regardless of allocation --
a1 = [1, 2, 3]
a2 = [1, 2, 3]
check("ceq.arr.eq", a1 == a2, true)
check("ceq.arr.neq_len", a1 == [1, 2], false)
check("ceq.arr.neq_elem", a1 == [1, 2, 4], false)
check("ceq.arr.empty", [] == [], true)
check("ceq.arr.strings", ["ab", "cd"] == ["ab", "cd"], true)
check("ceq.arr.mixed", [1, "two", :three] == [1, "two", :three], true)
check("ceq.arr.bang", (a1 != a2), false)

# -- Built element-by-element (exercises boxed/typed tier crossing) --
b = []
b.push(1)
b.push(2)
b.push(3)
check("ceq.arr.built", a1 == b, true)

# -- Nested arrays recurse --
n1 = [[1, 2], [3, [4]]]
n2 = [[1, 2], [3, [4]]]
check("ceq.arr.nested", n1 == n2, true)
check("ceq.arr.nested_neq", n1 == [[1, 2], [3, [5]]], false)

# -- Hashes: order-independent structural equality --
h1 = {a: 1, b: 2, c: 3}
h2 = {}
h2[:c] = 3
h2[:a] = 1
h2[:b] = 2
check("ceq.hash.eq_any_order", h1 == h2, true)
check("ceq.hash.neq_value", h1 == {a: 1, b: 2, c: 4}, false)
check("ceq.hash.neq_missing", h1 == {a: 1, b: 2}, false)
check("ceq.hash.neq_extra", {a: 1, b: 2} == h1, false)
check("ceq.hash.empty", {} == {}, true)
check("ceq.hash.bang", (h1 != h2), false)

# -- Deleted keys don't count --
h3 = {a: 1, b: 2, c: 3, d: 9}
h3.delete(:d)
check("ceq.hash.after_delete", h1 == h3, true)

# -- Nested containers recurse both ways --
deep1 = {list: [1, {x: 2}], name: "n"}
deep2 = {name: "n", list: [1, {x: 2}]}
check("ceq.deep.eq", deep1 == deep2, true)
check("ceq.deep.neq", deep1 == {name: "n", list: [1, {x: 3}]}, false)

# -- include? on arrays of arrays rides == --
outer = [[1, 2], [3, 4]]
check("ceq.include.hit", outer.include?([3, 4]), true)
check("ceq.include.miss", outer.include?([3, 5]), false)

# -- Cross-type never equals --
check("ceq.cross.arr_hash", ([] == {}), false)
check("ceq.cross.arr_int", ([1] == 1), false)

# -- Reference cycles terminate and compare equal by structure --
c1 = []
c1.push(c1)
c2 = []
c2.push(c2)
check("ceq.cycle.self", c1 == c1, true)
check("ceq.cycle.pair", c1 == c2, true)

<< "container equality: all green"
