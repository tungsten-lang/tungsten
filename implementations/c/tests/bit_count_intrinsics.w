# C-VM bridge coverage for core/bit_ops.w's private raw-count helpers.
# The stage-0 VM cannot execute static class calls such as BitOps.count_ones,
# so exercise the same ccall_nobox boundary directly, including values whose
# unsigned interpretation uses every bit of the machine word.

puts ccall_nobox("__w_bit_ctpop_u32", 0)
puts ccall_nobox("__w_bit_ctpop_u32", -1)
puts ccall_nobox("__w_bit_ctpop_u64", 0)
puts ccall_nobox("__w_bit_ctpop_u64", -1)
puts ccall_nobox("__w_bit_cttz_u32", 0)
puts ccall_nobox("__w_bit_cttz_u32", 2147483648)
puts ccall_nobox("__w_bit_cttz_u64", 0)
puts ccall_nobox("__w_bit_cttz_u64", 1099511627776)
