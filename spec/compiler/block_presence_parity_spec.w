# Source-level block-presence queries must agree across the tree-walking and
# compiled engines. In particular, a method that only asks `block?` still owns
# a hidden block slot, and a caller's block must not leak into a nested call.

-> check(name, actual, expected)
  if actual != expected
    << "FAIL " + name + ": got=" + actual.to_s + " expected=" + expected.to_s
    exit(1)

-> implicit_probe
  block?

-> parenthesized_probe
  block?()

-> explicit_probe(&)
  block?

-> compatibility_probe
  block_given?

-> inner_probe
  block?

-> outer_probe
  outer = block?
  inner = inner_probe
  [outer, inner]

-> maybe_yield
  if block?
    yield 40
  else
    :no_block

check("implicit no block", implicit_probe, false)
implicit_with = implicit_probe() -> 99
check("implicit trailing block", implicit_with, true)

check("parenthesized no block", parenthesized_probe, false)
parenthesized_with = parenthesized_probe() -> 99
check("parenthesized trailing block", parenthesized_with, true)

check("explicit no block", explicit_probe, false)
explicit_with = explicit_probe() -> 99
check("explicit trailing block", explicit_with, true)

# Compatibility is deliberate but Core itself uses block?.
check("compatibility no block", compatibility_probe, false)
compatibility_with = compatibility_probe() -> 99
check("compatibility trailing block", compatibility_with, true)

outer_without = outer_probe
check("nested no block outer", outer_without[0], false)
check("nested no block inner", outer_without[1], false)
outer_with = outer_probe() -> 99
check("nested trailing block outer", outer_with[0], true)
check("caller block does not leak", outer_with[1], false)

check("branch no block", maybe_yield, :no_block)
yielded = maybe_yield() -> value + 2
check("branch trailing block", yielded, 42)

# Array's source comparator path is a real Core consumer of block?. Keep this
# deliberately tiny: this spec pins the dispatch choice, not sorting breadth.
descending = [1, 3, 2].sort -> (left, right)
  right <=> left
check("Core block? consumer", descending, [3, 2, 1])

<< "block_presence_parity_spec: all checks passed"
