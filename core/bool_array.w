# BoolArray
#
# Bit-packed boolean array. Phase 6i.1b folded the dedicated WBoolArray
# struct into WArray with ebits=1, so a `BoolArray.new(n)` allocates the
# same kind of value as `u1[n]`. The runtime's array_idx/idxset paths
# convert bit values 0/1 ↔ W_TRUE/W_FALSE at the dispatch boundary so
# user-facing semantics match Tungsten truthiness conventions.

+ BoolArray

