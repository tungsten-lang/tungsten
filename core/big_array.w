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

  -> __enumerable_iteration_mode
    1

  # Inline w_int's overwhelmingly common signed-i48 arm while preserving its
  # canonical BigInt fallback for every other signed-i64 header pattern. The
  # explicit signed annotation matters because the layout view is u64 while
  # WBigArray stores int64_t fields in C.
  -> size
    n = $size ## i64
    if n >= -140_737_488_355_328 && n <= 140_737_488_355_327
      tag = -1_688_849_860_263_936 ## i64  # 0xFFFA000000000000
      mask = 0xFFFFFFFFFFFF ## i64
      return wvalue_from_bits((tag | (n & mask)) ## i64)
    ccall("w_int", n)

  # Match BigArray#size's signed-i48 fast path against the cap header. Raw
  # synthetic headers outside that interval retain w_int's canonical BigInt
  # representation instead of truncating to the 48-bit immediate payload.
  -> cap
    n = $cap ## i64
    if n >= -140_737_488_355_328 && n <= 140_737_488_355_327
      tag = -1_688_849_860_263_936 ## i64  # 0xFFFA000000000000
      mask = 0xFFFFFFFFFFFF ## i64
      return wvalue_from_bits((tag | (n & mask)) ## i64)
    ccall("w_int", n)

  -> empty?
    n = $size ## i64
    if n == 0
      return true
    false

  -> each/&
    $size -> &(self[i]) : self

  # Sorted copy, delegated to Array's working sort machinery (the
  # `array_mergesort` extern the old bodies called only ever existed as a
  # Ruby-engine builtin). Returns a plain polymorphic Array. Unlike
  # Array, BigArray has no native sort IC row, so these bodies are live
  # on the compiled engine — which is also why blockless/comparator are
  # separate definitions: compiled block dispatch specializes per
  # call-site block presence and `block_given?` is not implemented there.
  -> sort
    self.to_a.sort

  -> sort(&)
    self.to_a.sort -> (a, b)
      &(a, b)

  # In-place: sort into a copy, then write back through `[]=`.
  -> sort!
    self.__replace_elements(self.sort)

  -> sort!(&)
    sorted = self.sort -> (a, b)
      &(a, b)
    self.__replace_elements(sorted)

  # Stable in-place sort (`<=>` by default, Ruby-style comparator block
  # optional) via Array#mergesort!'s guaranteed-stable path.
  -> mergesort!
    items = self.to_a
    items.mergesort!
    self.__replace_elements(items)

  -> mergesort!(&)
    items = self.to_a
    items.mergesort! -> (a, b)
      &(a, b)
    self.__replace_elements(items)

  # Overwrite self element-by-element from `other` (same length assumed).
  -> __replace_elements(other)
    n = size
    i = 0
    while i < n
      self[i] = other[i]
      i += 1
    self

  -> shuffle(*opts)
    array_shuffle(self, *opts)

  -> shuffle!(*opts)
    array_shuffle!(self, *opts)

  -> rotate(count = 1)
    array_rotate(self, count)

  -> rotate!(count = 1)
    array_rotate!(self, count)
