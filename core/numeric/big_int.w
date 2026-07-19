
+ BigInt < Int
  - data
    # WBigint is a generic-subtag object. Lowering supplies the implicit type
    # byte at offset 0; keep the explicit C alignment bytes visible here so
    # length/capacity/limb0 land at offsets 4/8/16 respectively.
    u8[3] _pad
    i32 length
    u32 capacity
    u32 _pad2
    # The public predicates need only the first word of the flexible `limbs[]`
    # tail. Naming that word explicitly keeps it a declared u64 view field:
    # compiled code receives raw bits, while the interpreter bridge can expose
    # the same unsigned magnitude without manufacturing an array facade.
    u64 limb0

  -> zero?
    n = $length ## i64
    n == 0

  -> even?
    n = $length ## i64
    if n == 0
      return true
    low = $limb0 ## u64
    (low & 1) == 0

  -> odd?
    n = $length ## i64
    if n == 0
      return false
    low = $limb0 ## u64
    (low & 1) != 0

  -> negative?
    n = $length ## i64
    n < 0

  -> positive?
    n = $length ## i64
    n > 0

  # Conversion to the already-integral representation is receiver identity.
  # Do not normalize: callers can observe exact heap identity.
  -> to_i
    self
