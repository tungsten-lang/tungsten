# Fixed-width bit operations.
#
# These methods deliberately accept raw unsigned machine types rather than
# boxed Integer values.  That makes their width semantics explicit and lets
# compiled hot loops use them without allocating or promoting through BigInt.

+ BitOps
  # Number of set bits in one unsigned 32-bit word. Native compilation
  # recognizes this private helper name and emits llvm.ctpop.i32 directly;
  # the interpreter and C VM provide semantically equivalent fallbacks.
  -> .count_ones_u32(value) (u32) i64
    ccall_nobox("__w_bit_ctpop_u32", value)

  # Number of set bits in one unsigned 64-bit word.  This is the 64-bit form
  # of the same allocation-free operation.
  -> .count_ones_u64(value) (u64) i64
    ccall_nobox("__w_bit_ctpop_u64", value)

  # Number of zero bits above the most-significant set bit. As with the
  # trailing forms, zero has no set bit and returns the full word width.
  -> .leading_zeros_u64(value) (u64) i64
    ccall_nobox("__w_bit_ctlz_u64", value)

  -> .leading_zeros_u32(value) (u32) i64
    ccall_nobox("__w_bit_ctlz_u32", value)

  # Number of zero bits below the least-significant set bit. Zero has no set
  # bit, so it returns the word width. Native emission uses llvm.cttz with
  # is_zero_poison=false, preserving this defined-zero contract.
  -> .trailing_zeros_u64(value) (u64) i64
    ccall_nobox("__w_bit_cttz_u64", value)

  -> .trailing_zeros_u32(value) (u32) i64
    ccall_nobox("__w_bit_cttz_u32", value)
