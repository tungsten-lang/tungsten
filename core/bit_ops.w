# Fixed-width bit operations.
#
# These methods deliberately accept raw unsigned machine types rather than
# boxed Integer values.  That makes their width semantics explicit and lets
# compiled hot loops use them without allocating or promoting through BigInt.

+ BitOps
  # Number of set bits in one unsigned 32-bit word.  The fixed five-stage
  # SWAR reduction has data-independent cost and no lookup-table loads.
  -> .count_ones_u32(value) (u32) i64
    x = value
    x = x - ((x >> 1) & (0x55555555 ## u32))
    x = (x & (0x33333333 ## u32)) + ((x >> 2) & (0x33333333 ## u32))
    x = (x + (x >> 4)) & (0x0F0F0F0F ## u32)
    x = (x * (0x01010101 ## u32)) & (0xFFFFFFFF ## u32)
    (x >> 24) ## i64

  # Number of set bits in one unsigned 64-bit word.  This is the 64-bit form
  # of the same allocation-free SWAR reduction.
  -> .count_ones_u64(value) (u64) i64
    x = value
    x = x - ((x >> 1) & (0x5555555555555555 ## u64))
    x = (x & (0x3333333333333333 ## u64)) + ((x >> 2) & (0x3333333333333333 ## u64))
    x = (x + (x >> 4)) & (0x0F0F0F0F0F0F0F0F ## u64)
    x = (x * (0x0101010101010101 ## u64)) & (0xFFFFFFFFFFFFFFFF ## u64)
    (x >> 56) ## i64
