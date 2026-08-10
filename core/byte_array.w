# ByteArray
#
# Length-counted, mutable, heap-allocated byte buffer. The dedicated
# WBytes struct was folded into WArray with ebits=8, so a
# `ByteArray` value is identical to `u8[N]` at the binary level.
# The runtime intercepts `ByteArray.new(n)` in dispatch and routes it
# through the WArray constructor with ebits=8.

+ ByteArray
