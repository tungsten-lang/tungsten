# Tree-walker parity for Range methods. A range evaluates to the internal
# hash {rt: :range, from:, to:, exclusive:}, and primitive_runtime_class used
# to classify that as a plain Hash. Every name Hash also answers was then
# resolved against the Hash type class before dispatch_method could reach its
# dedicated range branch: `size` hit Hash's `- data` layout field and returned
# the hash's KEY COUNT (4, not the element count), and `.to_a` died inside
# Hash#to_a with an undefined __enumerable_yields_pair?.
#
# The fix must return EARLY from primitive_runtime_class for a range-tagged
# hash — merely leaving class_name nil is not enough, because the
# `class_name == nil` fallback re-derives the class from w_type_name, which
# reports plain "Hash" for this value. So `size` regressing to 4 here means
# that early return was lost or bypassed again.
#
# Every expectation below is verified to match the COMPILED engine too, with
# ONE exception called out at its check: `Range#length` is interpreter-only —
# compiled, the range materializes to an Array and `length` is undefined
# there. So this is a parity check except where it says otherwise.

-> check(name, got, want)
  if got != want
    << "FAIL [name]: got=[got] want=[want]"
    exit(1)
  << "PASS [name]"

r = (1..100)

# The regression itself: 4 was the tagged hash's key count.
check("inclusive size", r.size, 100)
# `length` shares the range branch's size arm, so it guards the same fix.
# Interpreter-only: compiled, this raises "undefined method 'length' for
# Array" — the range materializes and Array implements only `size`.
check("inclusive length", r.length, 100)
check("exclusive size", (1...100).size, 99)
check("single element size", (7..7).size, 1)
check("offset range size", (5..14).size, 10)

# Names the range branch forwards by materializing to an array. `count` always
# worked (Hash has no `count` data field), so it is the control: it and `size`
# must agree.
check("count agrees with size", r.count, r.size)
check("to_a size", r.to_a.size, 100)
check("first", r.first, 1)
check("sum", r.sum, 5050)
check("min", r.min, 1)
check("max", r.max, 100)
check("includes midpoint", r.include?(50), true)
check("excludes past end", r.include?(101), false)

# A real Hash must keep Hash semantics — the fix narrows the Hash
# classification, so this is the guard against over-narrowing it.
h = {}
check("empty hash size", h.size, 0)
h["a"] = 1
h["b"] = 2
check("hash size after inserts", h.size, 2)
check("hash keys size", h.keys.size, 2)

# An exclusive empty range and a descending range both report 0-ish sizes the
# same way the compiled engine does.
check("empty exclusive range", (5...5).size, 0)

<< "range_primitive_dispatch_spec: all checks passed"
