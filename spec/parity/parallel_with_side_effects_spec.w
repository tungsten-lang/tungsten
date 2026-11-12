## parity xfail `parallel with` body runs interpreted (serial, like `with`) but never runs compiled — lowering/pass_registry.w has a :with arm and no :parallel_with arm, so the statement lowers to nothing
# `parallel with x in 1..3` — the interpreter runs the body once per element
# like `with` (eval_with; there is no parallel scheduler in the tree-walker),
# so an accumulator sees every iteration. Compiled, the body never executes
# (a channel send inside it hangs main forever, so only side effects on
# locals are probed here).
#
# Cross-engine parity spec (scripts/parity.sh).

acc = []
parallel with x in 1..3
  acc.push(x * 2)
<< "parallel.push [acc.sort]"
total = 0
parallel with y in 1..4
  total += y
<< "parallel.sum [total]"
