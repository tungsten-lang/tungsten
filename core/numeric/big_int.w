
+ BigInt < Int
  - data
    # BigInt rides a dedicated top-level NaN-box tag (0xFFF8, v4), but WBigint retains its C header
    # byte as the live/parked recycler marker. Keep it explicit so
    # size/capacity/limb0 land at offsets 4/8/16 respectively.
    u8 _type
    u8[3] _pad
    i32 size
    u32 capacity
    u32 _pad2
    # The public predicates need only the first word of the flexible `limbs[]`
    # tail. Naming that word explicitly keeps it a declared u64 view field:
    # compiled code receives raw bits, while the interpreter bridge can expose
    # the same unsigned magnitude without manufacturing an array facade.
    u64 limb0

  -> zero?
    n = $size ## i64
    n == 0

  -> even?
    n = $size ## i64
    if n == 0
      return true
    low = $limb0 ## u64
    (low & 1) == 0

  -> odd?
    n = $size ## i64
    if n == 0
      return false
    low = $limb0 ## u64
    (low & 1) != 0

  -> negative?
    n = $size ## i64
    n < 0

  -> positive?
    n = $size ## i64
    n > 0

  # In-place sign mutation, following the `!` convention (Array#sort!,
  # Hash#merge!). A BigInt keeps its magnitude in a limb array and its sign
  # in a header field, so these are a single field write — O(1) at any
  # width, allocating nothing, versus the copy that `-x` / `abs` must make
  # to leave the receiver untouched. Use them when the receiver is yours;
  # like any bang method they are visible through every reference to it.
  # CAVEAT worth knowing: the runtime returns an operand unchanged for
  # identity-shaped arithmetic (`x + 0`), so a value obtained that way can
  # SHARE storage with its source and a bang method will be visible through
  # both. Mutate values you constructed, exactly as with Array#sort!.
  -> neg!
    n = $size ## i64
    $size = 0 - n
    self

  -> abs!
    n = $size ## i64
    if n < 0
      $size = 0 - n
    self

  # Conversion to the already-integral representation is receiver identity.
  # Do not normalize: callers can observe exact heap identity.
  -> to_i
    self
