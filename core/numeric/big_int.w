+ BigInt < Int
  - data
    # WBigint is a generic-subtag object. Lowering supplies the implicit type
    # byte at offset 0; keep the explicit C alignment bytes visible here so
    # length/capacity/limbs land at offsets 4/8/16 respectively.
    u8[3] _pad
    i32 length
    u32 capacity
    u32 _pad2
    u64[] limbs
