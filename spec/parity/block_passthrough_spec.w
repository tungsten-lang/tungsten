## parity xfail block pass-through (trailing block on a block-less method iterates the result) is compiled-only; the interpreter drops the block and the counters stay 0
# Blocks: a trailing block on a block-less method iterates the result.
#
# Cross-engine parity spec (scripts/parity.sh).

+ Bag
  -> new
    @items = [10, 20, 30]
  -> items
    @items
  -> n
    4

b = Bag.new
s = 0
b.items -> s += item
<< "passthrough.items [s]"
t = 0
b.n -> t += 1
<< "passthrough.n [t]"
u = 0
(-5).abs -> u += 1
<< "passthrough.abs [u]"
