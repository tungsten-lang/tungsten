# Blocks: block? / yield in a method, explicit `&` block parameters.
#
# Cross-engine parity spec (scripts/parity.sh).

-> maybe_yield
  if block?
    yield 40
  else
    "no block"
<< "block? [maybe_yield() -> item + 2] [maybe_yield()]"
-> twice(&)
  &(1)
  &(2)
acc = []
twice() -> acc.push(item * 3)
<< "amp [acc]"
-> each_pair(&)
  &(1, 2)
  &(3, 4)
pairs = []
each_pair() ->(a, b) pairs.push(a * b)
<< "amp.two [pairs]"
