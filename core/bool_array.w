# BoolArray
#
# Bit-packed boolean array. The dedicated WBoolArray struct was folded
# into WArray with ebits=1. `BoolArray.new(n)` reserves capacity for n
# values with size zero, while the `bool[n]` literal creates n readable,
# false-filled values. The runtime's array_idx/idxset paths
# convert bit values 0/1 ↔ W_TRUE/W_FALSE at the dispatch boundary so
# user-facing semantics match Tungsten truthiness conventions.

+ BoolArray
