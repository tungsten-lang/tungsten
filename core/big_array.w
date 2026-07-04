# BigArray
#
# Same shape as Array, but i64 fields for >2^32 elements. Used for
# mmap'd weights, KV cache, large datasets — anywhere a 2^32 element
# cap would overflow.

+ BigArray
  is Enumerable

  # Layout matches WBigArray in runtime.h. The leading W_TYPE_BIG_ARRAY
  # byte at C-offset 0 is the dispatch discriminator; the view here
  # starts at C-offset 1 and the lowering adds the implicit-type-byte
  # adjustment via class_uses_implicit_type_byte?(BigArray)=true.
  # Order is `ebits, flags` (not `flags, ebits` like Array) so the
  # shared array_storage_bits / array_read helpers can index `ebits`
  # at C-offset 1 the same way for both tiers.
  - data (WBigArray)
      u8    ebits
      u8    flags
      u8[5] _pad
      u64   start
      u64   size
      u64   cap
    * u8[]  slots

  -> each/&
    $size -> &(self[i]) : self

  -> sort(&)
    if block_given?
      array_mergesort(self) -> (a, b)
        &(a, b)
    else
      array_mergesort(self)

  -> sort!
    mergesort!

  -> sort!(&)
    mergesort! -> (a, b)
      &(a, b)

  -> mergesort!
    array_mergesort!(self)

  -> mergesort!(&)
    array_mergesort!(self) -> (a, b)
      &(a, b)

  -> shuffle(*opts)
    array_shuffle(self, *opts)

  -> shuffle!(*opts)
    array_shuffle!(self, *opts)

  -> rotate(count = 1)
    array_rotate(self, count)

  -> rotate!(count = 1)
    array_rotate!(self, count)
