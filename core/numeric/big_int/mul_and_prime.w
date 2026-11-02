# Out-of-line schoolbook multiply for BigInt#*'s in-band pairs (2..24
# limbs, unequal or mixed-sign, never squaring): one alloc, one asm_mulbase
# call writing the whole na+nb product, seal (which trims the possible high
# zero limb). `Tungsten.noinline!` keeps this single-caller body out of the
# dispatcher, which otherwise inherited its frame (six register pairs).
fn __bigint_times_general_raw(a, b, an, bn) (i64 i64 i64 i64) i64
  Tungsten.noinline!
  am = an ## i64
  if an < 0
    am = 0 - an
  bm = bn ## i64
  if bn < 0
    bm = 0 - bn
  mask = 140737488355312 ## i64
  pa = (a & mask) + 16 ## i64
  pb = (b & mask) + 16 ## i64
  total = am + bm ## i64
  result = ccall_nobox("w_bigint_alloc_hot", total) ## i64
  rp = (result & mask) + 16 ## i64
  asm_mulbase(rp, 0, pa, 0, pb, 0, am, bm)
  signed_total = total ## i64
  if (an < 0) != (bn < 0)
    signed_total = 0 - total
  ccall_nobox("w_bigint_seal_raw", result, signed_total)

on macos && arm64
  fn __bigint_add1_1_raw(a, b) (i64 i64) i64
    pair1 = __bigint_add1_1_sumcarry(a, b) ## u128
    sum1 = pair1 ## u64
    high1 = pair1 >> 64 ## u128
    carry1 = high1 ## u64
    ccall_nobox("w_bigint_add1_1_finish_raw", sum1 ## i64, carry1 ## i64)

  fn __bigint_add1_2_raw(a, b) (i64 i64) i64
    result = ccall_nobox("w_bigint_alloc_hot", 2) ## i64
    mask = 140737488355327 ## i64
    rp = (result & mask) + 16 ## i64
    ap = (a & mask) + 16 ## i64
    bp = (b & mask) + 16 ## i64
    word = raw_load_u64(bp, 0) ## i64
    carry = __bigint_add1_2_exact(rp, ap, word) ## i64
    ccall_nobox("w_bigint_add1_2_finish_raw", result, carry)

  fn __bigint_add1_4_raw(a, b) (i64 i64) i64
    result = ccall_nobox("w_bigint_alloc_hot", 4) ## i64
    mask = 140737488355327 ## i64
    rp = (result & mask) + 16 ## i64
    ap = (a & mask) + 16 ## i64
    bp = (b & mask) + 16 ## i64
    word = raw_load_u64(bp, 0) ## i64
    carry = __bigint_add1_4_exact(rp, ap, word) ## i64
    ccall_nobox("w_bigint_add1_4_finish_raw", result, carry)

  fn __bigint_add1_5_raw(a, b) (i64 i64) i64
    result = ccall_nobox("w_bigint_alloc_hot", 5) ## i64
    mask = 140737488355327 ## i64
    rp = (result & mask) + 16 ## i64
    ap = (a & mask) + 16 ## i64
    bp = (b & mask) + 16 ## i64
    word = raw_load_u64(bp, 0) ## i64
    carry = __bigint_add1_5_exact(rp, ap, word) ## i64
    ccall_nobox("w_bigint_add1_5_finish_raw", result, carry)

  fn __bigint_add1_6_raw(a, b) (i64 i64) i64
    result = ccall_nobox("w_bigint_alloc_hot", 6) ## i64
    mask = 140737488355327 ## i64
    rp = (result & mask) + 16 ## i64
    ap = (a & mask) + 16 ## i64
    bp = (b & mask) + 16 ## i64
    word = raw_load_u64(bp, 0) ## i64
    carry = __bigint_add1_6_exact(rp, ap, word) ## i64
    ccall_nobox("w_bigint_add1_6_finish_raw", result, carry)

  fn __bigint_add1_7_raw(a, b) (i64 i64) i64
    result = ccall_nobox("w_bigint_alloc_hot", 7) ## i64
    mask = 140737488355327 ## i64
    rp = (result & mask) + 16 ## i64
    ap = (a & mask) + 16 ## i64
    bp = (b & mask) + 16 ## i64
    word = raw_load_u64(bp, 0) ## i64
    carry = __bigint_add1_7_exact(rp, ap, word) ## i64
    ccall_nobox("w_bigint_add1_7_finish_raw", result, carry)

  fn __bigint_add1_8_raw(a, b) (i64 i64) i64
    result = ccall_nobox("w_bigint_alloc_hot", 8) ## i64
    mask = 140737488355327 ## i64
    rp = (result & mask) + 16 ## i64
    ap = (a & mask) + 16 ## i64
    bp = (b & mask) + 16 ## i64
    word = raw_load_u64(bp, 0) ## i64
    carry = __bigint_add1_8_exact(rp, ap, word) ## i64
    ccall_nobox("w_bigint_add1_8_finish_raw", result, carry)

# Exact positive one-limb subtract-word leaf.  Arithmetic stays in native
# source; the raw finisher retains C's i48 demotion and bit-48 exact-cap-one
# hot-slot policy.
fn __bigint_sub1_1_magnitude(ap, bp) (i64 i64) i64
  ll <<~IR
    ; tungsten:alwaysinline
    entry:
      %aptr = inttoptr i64 %ap to ptr
      %bptr = inttoptr i64 %bp to ptr
      %av = load i64, ptr %aptr, align 8
      %word = load i64, ptr %bptr, align 8
      %diff = sub i64 %av, %word
      %lt = icmp ult i64 %av, %word
      %neg = sub i64 0, %diff
      %magnitude = select i1 %lt, i64 %neg, i64 %diff
      ret i64 %magnitude
  IR

fn __bigint_sub1_1_raw(a, b) (i64 i64) i64
  mask = 140737488355327 ## i64
  ap = (a & mask) + 16 ## i64
  bp = (b & mask) + 16 ## i64
  av = raw_load_u64(ap, 0) ## u64
  word = raw_load_u64(bp, 0) ## u64
  lt = av < word
  magnitude = __bigint_sub1_1_magnitude(ap, bp) ## i64
  signed_size = (lt ? 0 - 1 : 1) ## i64
  ccall_nobox(
    "w_bigint_sub1_1_finish_raw", magnitude, signed_size
  )

# Exact positive one-limb multiply leaf. The generic runtime gate and typed
# BigInt worker have already proved either a distinct positive one-limb pair
# or C's raw-positive-header one-limb square; this raw worker performs only
# the C leaf's limb loads, 64x64 product, and identical result finishing.
on macos && arm64
  fn __bigint_mul1_1_raw(a, b) (i64 i64) i64
    product = __bigint_mul1_1_product(a, b) ## u128
    low = product ## u64
    high_wide = product >> 64 ## u128
    high = high_wide ## u64
    ccall_nobox(
      "w_bigint_mul1_1_finish_raw", low ## i64, high ## i64
    )

  # Exact pointer-identical positive two-limb square. The runtime gate has
  # already matched C's raw positive-header identity shape. Reproduce its exact
  # hot capacity-4 allocation, fixed kernel, and unconditional +3/+4 header.
  fn __bigint_sqr2_raw(a, b) (i64 i64) i64
    result = ccall_nobox("w_bigint_alloc_hot4_raw") ## i64
    mask = 140737488355327 ## i64
    rp = (result & mask) + 16 ## i64
    ap = (a & mask) + 16 ## i64
    size = __bigint_sqr2_exact(rp ## i64, ap ## i64) ## i64
    ccall_nobox("w_bigint_sqr2_finish_raw", result, size)

  # Exact pointer-identical positive three-limb square. The runtime gate has
  # already matched C's raw positive-header identity shape. Reproduce its exact
  # hot capacity-8 allocation, fixed kernel, and unconditional +5/+6 header.
  fn __bigint_sqr3_raw(a, b) (i64 i64) i64
    result = ccall_nobox("w_bigint_alloc_hot8_raw") ## i64
    mask = 140737488355327 ## i64
    rp = (result & mask) + 16 ## i64
    ap = (a & mask) + 16 ## i64
    size = __bigint_sqr3_exact(rp ## i64, ap ## i64) ## i64
    ccall_nobox("w_bigint_sqr3_finish_raw", result, size)

  # Exact pointer-identical positive four-limb square. The runtime gate has
  # already matched C's raw positive-header identity shape. Reproduce its exact
  # hot capacity-8 allocation, fixed kernel, and unconditional +7/+8 header.
  fn __bigint_sqr4_raw(a, b) (i64 i64) i64
    result = ccall_nobox("w_bigint_alloc_hot8_raw") ## i64
    mask = 140737488355327 ## i64
    rp = (result & mask) + 16 ## i64
    ap = (a & mask) + 16 ## i64
    size = __bigint_sqr4_exact(rp ## i64, ap ## i64) ## i64
    ccall_nobox("w_bigint_sqr4_finish_raw", result, size)

  # Exact pointer-identical positive five-limb square. The runtime gate has
  # already matched C's raw positive-header identity shape. Reproduce its exact
  # capacity-16 allocation, fixed leaf schedule, and +9/+10 header. The native
  # follow-up inlines that schedule only after the exact noinline checkpoint.
  fn __bigint_sqr5_raw(a, b) (i64 i64) i64
    result = ccall_nobox("w_bigint_alloc_hot16_raw") ## i64
    mask = 140737488355327 ## i64
    rp = (result & mask) + 16 ## i64
    ap = (a & mask) + 16 ## i64
    size = __bigint_sqr5_exact(rp ## i64, ap ## i64) ## i64
    ccall_nobox("w_bigint_sqr5_finish_raw", result, size)

  # Exact pointer-identical positive six-limb square. The runtime gate has
  # already matched C's raw positive-header identity shape. Reproduce its exact
  # capacity-16 allocation, fixed noinline leaf schedule, and +11/+12 header.
  fn __bigint_sqr6_raw(a, b) (i64 i64) i64
    result = ccall_nobox("w_bigint_alloc_hot16_raw") ## i64
    mask = 140737488355327 ## i64
    rp = (result & mask) + 16 ## i64
    ap = (a & mask) + 16 ## i64
    size = __bigint_sqr6_exact(rp ## i64, ap ## i64) ## i64
    ccall_nobox("w_bigint_sqr6_finish_raw", result, size)

  # Exact pointer-identical positive seven-limb square. The runtime gate has
  # already matched C's raw positive-header identity shape. Reproduce its exact
  # capacity-16 allocation, fixed noinline leaf schedule, and +13/+14 header.
  fn __bigint_sqr7_raw(a, b) (i64 i64) i64
    result = ccall_nobox("w_bigint_alloc_hot16_raw") ## i64
    mask = 140737488355327 ## i64
    rp = (result & mask) + 16 ## i64
    ap = (a & mask) + 16 ## i64
    size = __bigint_sqr7_exact(rp ## i64, ap ## i64) ## i64
    ccall_nobox("w_bigint_sqr7_finish_raw", result, size)

  # Exact pointer-identical positive eight-limb square. The runtime gate has
  # already matched C's raw positive-header identity shape. Reproduce its exact
  # capacity-16 allocation, inlined fixed leaf schedule, and +15/+16 header.
  fn __bigint_sqr8_raw(a, b) (i64 i64) i64
    result = ccall_nobox("w_bigint_alloc_hot16_raw") ## i64
    mask = 140737488355327 ## i64
    rp = (result & mask) + 16 ## i64
    ap = (a & mask) + 16 ## i64
    size = __bigint_sqr8_exact(rp ## i64, ap ## i64) ## i64
    ccall_nobox("w_bigint_sqr8_finish_raw", result, size)

# Exact pointer-identical positive sixteen-limb split square. Preserve C's
# capacity-32 allocation, bn_sqr16_split kernel call, and +31/+32 publication.
fn __bigint_sqr16_raw(a, b) (i64 i64) i64
  result = ccall_nobox("w_bigint_alloc_hot32_raw") ## i64
  mask = 140737488355327 ## i64
  rp = (result & mask) + 16 ## i64
  ap = (a & mask) + 16 ## i64
  ccall_nobox("w_bigint_sqr16_kernel_raw", rp, ap)
  ccall_nobox("w_bigint_sqr16_finish_raw", result)

# Exact distinct positive two-by-two-limb multiplication. The runtime gate
# has already matched C's raw-positive-header shape and excluded identity.
# Reproduce its capacity-4 allocation, fixed kernel, and +3/+4 publication.
on macos && arm64
  fn __bigint_mul2_raw(a, b) (i64 i64) i64
    result = ccall_nobox("w_bigint_alloc_hot4_raw") ## i64
    mask = 140737488355327 ## i64
    rp = (result & mask) + 16 ## i64
    ap = (a & mask) + 16 ## i64
    bp = (b & mask) + 16 ## i64
    size = __bigint_mul2_exact(rp ## i64, ap ## i64, bp ## i64) ## i64
    ccall_nobox("w_bigint_mul2_finish_raw", result, size)

  # Exact distinct positive three-by-three-limb multiplication. The runtime gate
  # has already matched C's raw-positive-header shape and excluded identity.
  fn __bigint_mul3_raw(a, b) (i64 i64) i64
    result = ccall_nobox("w_bigint_alloc_hot8_raw") ## i64
    mask = 140737488355327 ## i64
    rp = (result & mask) + 16 ## i64
    ap = (a & mask) + 16 ## i64
    bp = (b & mask) + 16 ## i64
    size = __bigint_mul3_exact(rp ## i64, ap ## i64, bp ## i64) ## i64
    ccall_nobox("w_bigint_mul3_finish_raw", result, size)

  # Exact distinct positive four-by-four-limb multiplication. Preserve C's
  # tuned general mul_1 call for row zero, then execute its literal inlined
  # addmul remainder from native Tungsten.
  fn __bigint_mul4_raw(a, b) (i64 i64) i64
    result = ccall_nobox("w_bigint_alloc_hot8_raw") ## i64
    mask = 140737488355327 ## i64
    rp = (result & mask) + 16 ## i64
    ap = (a & mask) + 16 ## i64
    bp = (b & mask) + 16 ## i64
    row0_carry = ccall_nobox("w_bigint_mul4_first_row_raw", rp, bp, ap) ## i64
    size = __bigint_mul4_addrows_exact(
      rp ## i64, ap ## i64, bp ## i64, row0_carry
    ) ## i64
    ccall_nobox("w_bigint_mul4_finish_raw", result, size)

# Exact distinct positive five-by-five-limb multiplication. C has no fixed
# five-limb arithmetic leaf: preserve its generic schoolbook decomposition
# literally—one mul_1(n=5) row followed by four addmul_1(n=5) rows—while
# moving allocation, row sequencing, and publication into native Tungsten.
fn __bigint_mul5_raw(a, b) (i64 i64) i64
  result = ccall_nobox("w_bigint_alloc_hot16_raw") ## i64
  mask = 140737488355327 ## i64
  rp = (result & mask) + 16 ## i64
  ap = (a & mask) + 16 ## i64
  bp = (b & mask) + 16 ## i64
  ccall_nobox("w_bigint_mul5_first_row_raw", rp, bp, ap)
  ccall_nobox("w_bigint_mul5_add_row_raw", rp, bp, ap, 1)
  ccall_nobox("w_bigint_mul5_add_row_raw", rp, bp, ap, 2)
  ccall_nobox("w_bigint_mul5_add_row_raw", rp, bp, ap, 3)
  ccall_nobox("w_bigint_mul5_add_row_raw", rp, bp, ap, 4)
  ccall_nobox("w_bigint_mul5_finish_raw", result)

# Exact distinct positive six-by-six-limb multiplication. Preserve C's
# generic schoolbook decomposition literally—one mul_1(n=6) row followed by
# five addmul_1(n=6) rows—while moving allocation, row sequencing, and
# publication into native Tungsten.
fn __bigint_mul6_raw(a, b) (i64 i64) i64
  result = ccall_nobox("w_bigint_alloc_hot16_raw") ## i64
  mask = 140737488355327 ## i64
  rp = (result & mask) + 16 ## i64
  ap = (a & mask) + 16 ## i64
  bp = (b & mask) + 16 ## i64
  ccall_nobox("w_bigint_mul6_first_row_raw", rp, bp, ap)
  ccall_nobox("w_bigint_mul6_add_row_raw", rp, bp, ap, 1)
  ccall_nobox("w_bigint_mul6_add_row_raw", rp, bp, ap, 2)
  ccall_nobox("w_bigint_mul6_add_row_raw", rp, bp, ap, 3)
  ccall_nobox("w_bigint_mul6_add_row_raw", rp, bp, ap, 4)
  ccall_nobox("w_bigint_mul6_add_row_raw", rp, bp, ap, 5)
  ccall_nobox("w_bigint_mul6_finish_raw", result)

# Exact distinct positive seven-by-seven-limb multiplication. Preserve C's
# generic schoolbook decomposition literally—one mul_1(n=7) row followed by
# six addmul_1(n=7) rows—while moving allocation, row sequencing, and
# publication into native Tungsten.
fn __bigint_mul7_raw(a, b) (i64 i64) i64
  result = ccall_nobox("w_bigint_alloc_hot16_raw") ## i64
  mask = 140737488355327 ## i64
  rp = (result & mask) + 16 ## i64
  ap = (a & mask) + 16 ## i64
  bp = (b & mask) + 16 ## i64
  ccall_nobox("w_bigint_mul7_first_row_raw", rp, bp, ap)
  ccall_nobox("w_bigint_mul7_add_row_raw", rp, bp, ap, 1)
  ccall_nobox("w_bigint_mul7_add_row_raw", rp, bp, ap, 2)
  ccall_nobox("w_bigint_mul7_add_row_raw", rp, bp, ap, 3)
  ccall_nobox("w_bigint_mul7_add_row_raw", rp, bp, ap, 4)
  ccall_nobox("w_bigint_mul7_add_row_raw", rp, bp, ap, 5)
  ccall_nobox("w_bigint_mul7_add_row_raw", rp, bp, ap, 6)
  ccall_nobox("w_bigint_mul7_finish_raw", result)

# Exact distinct positive eight-by-eight-limb multiplication. Preserve C's
# fixed bn_mul_eq8_inline split literally: one mul_1(n=8) row followed by
# seven fully unrolled addmul_8 rows.
fn __bigint_mul8_raw(a, b) (i64 i64) i64
  result = ccall_nobox("w_bigint_alloc_hot16_raw") ## i64
  mask = 140737488355327 ## i64
  rp = (result & mask) + 16 ## i64
  ap = (a & mask) + 16 ## i64
  bp = (b & mask) + 16 ## i64
  ccall_nobox("w_bigint_mul8_first_row_raw", rp, bp, ap)
  ccall_nobox("w_bigint_mul8_add_row_raw", rp, bp, ap, 1)
  ccall_nobox("w_bigint_mul8_add_row_raw", rp, bp, ap, 2)
  ccall_nobox("w_bigint_mul8_add_row_raw", rp, bp, ap, 3)
  ccall_nobox("w_bigint_mul8_add_row_raw", rp, bp, ap, 4)
  ccall_nobox("w_bigint_mul8_add_row_raw", rp, bp, ap, 5)
  ccall_nobox("w_bigint_mul8_add_row_raw", rp, bp, ap, 6)
  ccall_nobox("w_bigint_mul8_add_row_raw", rp, bp, ap, 7)
  ccall_nobox("w_bigint_mul8_finish_raw", result)

# Exact distinct positive twelve-by-twelve-limb multiplication. Preserve C's
# fixed bn_mul_eq12 leaf literally; source owns only the same capacity-32
# allocation, fixed-kernel call, and +23/+24 publication.
fn __bigint_mul12_raw(a, b) (i64 i64) i64
  result = ccall_nobox("w_bigint_alloc_hot32_raw") ## i64
  mask = 140737488355327 ## i64
  rp = (result & mask) + 16 ## i64
  ap = (a & mask) + 16 ## i64
  bp = (b & mask) + 16 ## i64
  ccall_nobox("w_bigint_mul12_kernel_raw", rp, bp, ap)
  ccall_nobox("w_bigint_mul12_finish_raw", result)

# Exact distinct positive fifteen-by-fifteen-limb multiplication. Preserve
# C's fixed bn_mul_eq15 leaf literally; source owns only the same capacity-32
# allocation, fixed-kernel call, and +29/+30 publication.
fn __bigint_mul15_raw(a, b) (i64 i64) i64
  result = ccall_nobox("w_bigint_alloc_hot32_raw") ## i64
  mask = 140737488355327 ## i64
  rp = (result & mask) + 16 ## i64
  ap = (a & mask) + 16 ## i64
  bp = (b & mask) + 16 ## i64
  ccall_nobox("w_bigint_mul15_kernel_raw", rp, bp, ap)
  ccall_nobox("w_bigint_mul15_finish_raw", result)

# Exact distinct positive sixteen-by-sixteen-limb multiplication. Preserve
# C's fixed bn_mul_eq16 leaf literally; source owns only the same capacity-32
# allocation, fixed-kernel call, and +31/+32 publication.
fn __bigint_mul16_raw(a, b) (i64 i64) i64
  result = ccall_nobox("w_bigint_alloc_hot32_raw") ## i64
  mask = 140737488355327 ## i64
  rp = (result & mask) + 16 ## i64
  ap = (a & mask) + 16 ## i64
  bp = (b & mask) + 16 ## i64
  ccall_nobox("w_bigint_mul16_kernel_raw", rp, bp, ap)
  ccall_nobox("w_bigint_mul16_finish_raw", result)

# Exact distinct positive seventeen-by-seventeen-limb multiplication. Preserve
# C's fixed bn_mul_eq17 leaf literally; source owns only the same capacity-64
# allocation, fixed-kernel call, and +33/+34 publication.
fn __bigint_mul17_raw(a, b) (i64 i64) i64
  result = ccall_nobox("w_bigint_alloc_hot64_raw") ## i64
  mask = 140737488355327 ## i64
  rp = (result & mask) + 16 ## i64
  ap = (a & mask) + 16 ## i64
  bp = (b & mask) + 16 ## i64
  ccall_nobox("w_bigint_mul17_kernel_raw", rp, bp, ap)
  ccall_nobox("w_bigint_mul17_finish_raw", result)

# Exact distinct positive twenty-one-by-twenty-one-limb multiplication.
# Preserve C's fixed bn_mul_eq21 leaf literally; source owns only the same
# capacity-64 allocation, fixed-kernel call, and +41/+42 publication.
fn __bigint_mul21_raw(a, b) (i64 i64) i64
  result = ccall_nobox("w_bigint_alloc_hot64_raw") ## i64
  mask = 140737488355327 ## i64
  rp = (result & mask) + 16 ## i64
  ap = (a & mask) + 16 ## i64
  bp = (b & mask) + 16 ## i64
  ccall_nobox("w_bigint_mul21_kernel_raw", rp, bp, ap)
  ccall_nobox("w_bigint_mul21_finish_raw", result)

# Exact distinct positive twenty-four-by-twenty-four-limb multiplication.
# Preserve C's selected top-level difference-form leaf literally; source owns
# only the same capacity-64 allocation, kernel call, and +47/+48 publication.
fn __bigint_mul24_raw(a, b) (i64 i64) i64
  result = ccall_nobox("w_bigint_alloc_hot64_raw") ## i64
  mask = 140737488355327 ## i64
  rp = (result & mask) + 16 ## i64
  ap = (a & mask) + 16 ## i64
  bp = (b & mask) + 16 ## i64
  ccall_nobox("w_bigint_mul24_kernel_raw", rp, bp, ap)
  ccall_nobox("w_bigint_mul24_finish_raw", result)

# Exact positive two-limb-by-one-limb scalar-word arm. Preserve receiver
# order at the operator seam, then orient only the raw magnitudes after the
# shape gate has proved that exactly one operand has two limbs.
on macos && arm64
  fn __bigint_mul1_2_raw(a, b) (i64 i64) i64
    result = ccall_nobox("w_bigint_alloc_hot4_raw") ## i64
    mask = 140737488355327 ## i64
    abase = a & mask
    bbase = b & mask
    asize = raw_load_u32(abase, 4) ## i64
    wide = abase ## i64
    word_box = bbase ## i64
    if asize != 2
      wide = bbase ## i64
      word_box = abase ## i64
    rp = (result & mask) + 16 ## i64
    ap = wide + 16 ## i64
    word = raw_load_u64(word_box, 16) ## i64
    size = __bigint_mul1_2_exact(rp ## i64, ap ## i64, word) ## i64
    ccall_nobox("w_bigint_mul1_2_finish_raw", result, size)

  # Exact positive three-limb-by-one-limb scalar-word arm. The shape gate keeps
  # receiver order observable, then this worker performs the same cap-four
  # allocation, serial C carry schedule, top write, and size publication.
  fn __bigint_mul1_3_raw(a, b) (i64 i64) i64
    result = ccall_nobox("w_bigint_alloc_hot4_raw") ## i64
    mask = 140737488355327 ## i64
    abase = a & mask
    bbase = b & mask
    asize = raw_load_u32(abase, 4) ## i64
    wide = abase ## i64
    word_box = bbase ## i64
    if asize != 3
      wide = bbase ## i64
      word_box = abase ## i64
    rp = (result & mask) + 16 ## i64
    ap = wide + 16 ## i64
    word = raw_load_u64(word_box, 16) ## i64
    size = __bigint_mul1_3_exact(rp ## i64, ap ## i64, word) ## i64
    ccall_nobox("w_bigint_mul1_3_finish_raw", result, size)

  # Exact positive four-limb-by-one-limb scalar-word arm. Preserve receiver
  # order at the source seam, then reproduce C's capacity-eight allocation,
  # literal carry schedule, top write, and header publication.
  fn __bigint_mul1_4_raw(a, b) (i64 i64) i64
    result = ccall_nobox("w_bigint_alloc_hot8_raw") ## i64
    mask = 140737488355327 ## i64
    abase = a & mask
    bbase = b & mask
    asize = raw_load_u32(abase, 4) ## i64
    wide = abase ## i64
    word_box = bbase ## i64
    if asize != 4
      wide = bbase ## i64
      word_box = abase ## i64
    rp = (result & mask) + 16 ## i64
    ap = wide + 16 ## i64
    word = raw_load_u64(word_box, 16) ## i64
    size = __bigint_mul1_4_exact(rp ## i64, ap ## i64, word) ## i64
    ccall_nobox("w_bigint_mul1_4_finish_raw", result, size)

  # Exact positive five-limb-by-one-limb scalar-word arm. Preserve receiver
  # order, capacity-eight allocation, serial carry recurrence, and size 5/6.
  fn __bigint_mul1_5_raw(a, b) (i64 i64) i64
    result = ccall_nobox("w_bigint_alloc_hot8_raw") ## i64
    mask = 140737488355327 ## i64
    abase = a & mask
    bbase = b & mask
    asize = raw_load_u32(abase, 4) ## i64
    wide = abase ## i64
    word_box = bbase ## i64
    if asize != 5
      wide = bbase ## i64
      word_box = abase ## i64
    rp = (result & mask) + 16 ## i64
    ap = wide + 16 ## i64
    word = raw_load_u64(word_box, 16) ## i64
    size = __bigint_mul1_5_exact(rp ## i64, ap ## i64, word) ## i64
    ccall_nobox("w_bigint_mul1_5_finish_raw", result, size)

  # Exact positive six-limb-by-one-limb scalar-word arm.
  fn __bigint_mul1_6_raw(a, b) (i64 i64) i64
    result = ccall_nobox("w_bigint_alloc_hot8_raw") ## i64
    mask = 140737488355327 ## i64
    abase = a & mask
    bbase = b & mask
    asize = raw_load_u32(abase, 4) ## i64
    wide = abase ## i64
    word_box = bbase ## i64
    if asize != 6
      wide = bbase ## i64
      word_box = abase ## i64
    rp = (result & mask) + 16 ## i64
    ap = wide + 16 ## i64
    word = raw_load_u64(word_box, 16) ## i64
    size = __bigint_mul1_6_exact(rp ## i64, ap ## i64, word) ## i64
    ccall_nobox("w_bigint_mul1_6_finish_raw", result, size)

  # Exact positive seven-limb-by-one-limb scalar-word arm.
  fn __bigint_mul1_7_raw(a, b) (i64 i64) i64
    result = ccall_nobox("w_bigint_alloc_hot8_raw") ## i64
    mask = 140737488355327 ## i64
    abase = a & mask
    bbase = b & mask
    asize = raw_load_u32(abase, 4) ## i64
    wide = abase ## i64
    word_box = bbase ## i64
    if asize != 7
      wide = bbase ## i64
      word_box = abase ## i64
    rp = (result & mask) + 16 ## i64
    ap = wide + 16 ## i64
    word = raw_load_u64(word_box, 16) ## i64
    size = __bigint_mul1_7_exact(rp ## i64, ap ## i64, word) ## i64
    ccall_nobox("w_bigint_mul1_7_finish_raw", result, size)

  # Exact positive eight-limb-by-one-limb fixed scalar-word arm.
  fn __bigint_mul1_8_raw(a, b) (i64 i64) i64
    result = ccall_nobox("w_bigint_alloc_hot16_raw") ## i64
    mask = 140737488355327 ## i64
    abase = a & mask
    bbase = b & mask
    asize = raw_load_u32(abase, 4) ## i64
    wide = abase ## i64
    word_box = bbase ## i64
    if asize != 8
      wide = bbase ## i64
      word_box = abase ## i64
    rp = (result & mask) + 16 ## i64
    ap = wide + 16 ## i64
    word = raw_load_u64(word_box, 16) ## i64
    size = __bigint_mul1_8_exact(rp ## i64, ap ## i64, word) ## i64
    ccall_nobox("w_bigint_mul1_8_finish_raw", result, size)

# Exact positive sixteen-limb-by-one-limb fixed scalar-word arm. Preserve
# C's cap-32 allocation, unchanged bn_mul_1_f16 kernel, carry store, and
# exact +16/+17 publication while moving the outer leaf into Tungsten.
fn __bigint_mul1_16_raw(a, b) (i64 i64) i64
  mask = 140737488355327 ## i64
  abase = a & mask
  bbase = b & mask
  asize = raw_load_u32(abase, 4) ## i64
  wide = abase ## i64
  word_box = bbase ## i64
  if asize != 16
    wide = bbase ## i64
    word_box = abase ## i64
  result = ccall_nobox("w_bigint_alloc_hot32_raw") ## i64
  rp = (result & mask) + 16 ## i64
  ap = wide + 16 ## i64
  word = raw_load_u64(word_box, 16) ## i64
  carry = ccall_nobox("w_bigint_mul1_16_kernel_raw", rp, ap, word) ## i64
  ccall_nobox("w_bigint_mul1_16_finish_raw", result, carry)

# Exact positive twenty-four-limb-by-one-limb fixed scalar-word arm. Keep
# C's cap-32 allocation, unchanged bn_mul_1_f24 kernel, carry store, and
# exact +24/+25 publication while moving only the outer leaf to Tungsten.
fn __bigint_mul1_24_raw(a, b) (i64 i64) i64
  mask = 140737488355327 ## i64
  abase = a & mask
  bbase = b & mask
  asize = raw_load_u32(abase, 4) ## i64
  wide = abase ## i64
  word_box = bbase ## i64
  if asize != 24
    wide = bbase ## i64
    word_box = abase ## i64
  result = ccall_nobox("w_bigint_alloc_hot32_raw") ## i64
  rp = (result & mask) + 16 ## i64
  ap = wide + 16 ## i64
  word = raw_load_u64(word_box, 16) ## i64
  carry = ccall_nobox("w_bigint_mul1_24_kernel_raw", rp, ap, word) ## i64
  ccall_nobox("w_bigint_mul1_24_finish_raw", result, carry)

# Exact positive thirty-two-limb-by-one-limb fixed scalar-word arm. Keep
# C's cap-64 allocation, unchanged bn_mul_1_f32 kernel, carry store, and
# exact +32/+33 publication while moving only the outer leaf to Tungsten.
fn __bigint_mul1_32_raw(a, b) (i64 i64) i64
  mask = 140737488355327 ## i64
  abase = a & mask
  bbase = b & mask
  asize = raw_load_u32(abase, 4) ## i64
  wide = abase ## i64
  word_box = bbase ## i64
  if asize != 32
    wide = bbase ## i64
    word_box = abase ## i64
  result = ccall_nobox("w_bigint_alloc_hot64_raw") ## i64
  rp = (result & mask) + 16 ## i64
  ap = wide + 16 ## i64
  word = raw_load_u64(word_box, 16) ## i64
  carry = ccall_nobox("w_bigint_mul1_32_kernel_raw", rp, ap, word) ## i64
  ccall_nobox("w_bigint_mul1_32_finish_raw", result, carry)

# Exact positive forty-limb-by-one-limb fixed scalar-word arm. Keep C's
# cap-64 allocation, unchanged bn_mul_1_f40 kernel, carry store, and exact
# +40/+41 publication while moving only the outer leaf to Tungsten.
fn __bigint_mul1_40_raw(a, b) (i64 i64) i64
  mask = 140737488355327 ## i64
  abase = a & mask
  bbase = b & mask
  asize = raw_load_u32(abase, 4) ## i64
  wide = abase ## i64
  word_box = bbase ## i64
  if asize != 40
    wide = bbase ## i64
    word_box = abase ## i64
  result = ccall_nobox("w_bigint_alloc_hot64_raw") ## i64
  rp = (result & mask) + 16 ## i64
  ap = wide + 16 ## i64
  word = raw_load_u64(word_box, 16) ## i64
  carry = ccall_nobox("w_bigint_mul1_40_kernel_raw", rp, ap, word) ## i64
  ccall_nobox("w_bigint_mul1_40_finish_raw", result, carry)

# Exact positive forty-eight-limb-by-one-limb fixed scalar-word arm. Keep C's
# cap-64 allocation, unchanged bn_mul_1_f48 kernel, carry store, and exact
# +48/+49 publication while moving only the outer leaf to Tungsten.
fn __bigint_mul1_48_raw(a, b) (i64 i64) i64
  mask = 140737488355327 ## i64
  abase = a & mask
  bbase = b & mask
  asize = raw_load_u32(abase, 4) ## i64
  wide = abase ## i64
  word_box = bbase ## i64
  if asize != 48
    wide = bbase ## i64
    word_box = abase ## i64
  result = ccall_nobox("w_bigint_alloc_hot64_raw") ## i64
  rp = (result & mask) + 16 ## i64
  ap = wide + 16 ## i64
  word = raw_load_u64(word_box, 16) ## i64
  carry = ccall_nobox("w_bigint_mul1_48_kernel_raw", rp, ap, word) ## i64
  ccall_nobox("w_bigint_mul1_48_finish_raw", result, carry)

# Exact positive sixty-four-limb-by-one-limb fixed scalar-word arm. Keep C's
# cap-128 allocation, unchanged bn_mul_1_f64 kernel, carry store, and exact
# +64/+65 publication while moving only the outer leaf to Tungsten.
fn __bigint_mul1_64_raw(a, b) (i64 i64) i64
  mask = 140737488355327 ## i64
  abase = a & mask
  bbase = b & mask
  asize = raw_load_u32(abase, 4) ## i64
  wide = abase ## i64
  word_box = bbase ## i64
  if asize != 64
    wide = bbase ## i64
    word_box = abase ## i64
  result = ccall_nobox("w_bigint_alloc_hot128_raw") ## i64
  rp = (result & mask) + 16 ## i64
  ap = wide + 16 ## i64
  word = raw_load_u64(word_box, 16) ## i64
  carry = ccall_nobox("w_bigint_mul1_64_kernel_raw", rp, ap, word) ## i64
  ccall_nobox("w_bigint_mul1_64_finish_raw", result, carry)

# Exact positive two-limb minus positive one-limb C arm.  Allocation, the
# fixed AArch64 schedule, top-limb shrink, and possible i48 demotion remain
# separate steps in the same order as bigint_sub_ui_any.
on macos && arm64
  fn __bigint_sub1_2_raw(a, b) (i64 i64) i64
    result = ccall_nobox("w_bigint_sub1_2_alloc_hot_raw") ## i64
    mask = 140737488355327 ## i64
    rp = (result & mask) + 16 ## i64
    ap = (a & mask) + 16 ## i64
    bp = (b & mask) + 16 ## i64
    word = raw_load_u64(bp, 0) ## i64
    borrow = __bigint_sub1_2_exact(rp, ap, word) ## i64
    ccall_nobox("w_bigint_sub1_2_finish_raw", result)

  # Exact positive three-limb minus positive one-limb C arm.  The fixed leaf
  # publishes every limb before the retained shrink-by-one result policy runs.
  fn __bigint_sub1_3_raw(a, b) (i64 i64) i64
    result = ccall_nobox("w_bigint_alloc_hot", 3) ## i64
    mask = 140737488355327 ## i64
    rp = (result & mask) + 16 ## i64
    ap = (a & mask) + 16 ## i64
    bp = (b & mask) + 16 ## i64
    word = raw_load_u64(bp, 0) ## i64
    borrow = __bigint_sub1_3_exact(rp, ap, word) ## i64
    ccall_nobox("w_bigint_sub1_3_finish_raw", result)

  # Exact positive four-limb minus positive one-limb C arm.  The generic cap-four
  # hot allocation and shrink-by-one finisher deliberately remain separate, in
  # the same order as bigint_sub_ui_any.
  fn __bigint_sub1_4_raw(a, b) (i64 i64) i64
    result = ccall_nobox("w_bigint_alloc_hot", 4) ## i64
    mask = 140737488355327 ## i64
    rp = (result & mask) + 16 ## i64
    ap = (a & mask) + 16 ## i64
    bp = (b & mask) + 16 ## i64
    word = raw_load_u64(bp, 0) ## i64
    borrow = __bigint_sub1_4_exact(rp, ap, word) ## i64
    ccall_nobox("w_bigint_sub1_4_finish_raw", result)

  # Exact positive five-limb minus positive one-limb C arm.
  fn __bigint_sub1_5_raw(a, b) (i64 i64) i64
    result = ccall_nobox("w_bigint_alloc_hot", 5) ## i64
    mask = 140737488355327 ## i64
    rp = (result & mask) + 16 ## i64
    ap = (a & mask) + 16 ## i64
    bp = (b & mask) + 16 ## i64
    word = raw_load_u64(bp, 0) ## i64
    borrow = __bigint_sub1_5_exact(rp, ap, word) ## i64
    ccall_nobox("w_bigint_sub1_5_finish_raw", result)

  # Exact positive six-limb minus positive one-limb C arm.
  fn __bigint_sub1_6_raw(a, b) (i64 i64) i64
    result = ccall_nobox("w_bigint_alloc_hot", 6) ## i64
    mask = 140737488355327 ## i64
    rp = (result & mask) + 16 ## i64
    ap = (a & mask) + 16 ## i64
    bp = (b & mask) + 16 ## i64
    word = raw_load_u64(bp, 0) ## i64
    borrow = __bigint_sub1_6_exact(rp, ap, word) ## i64
    ccall_nobox("w_bigint_sub1_6_finish_raw", result)

  # Exact positive seven-limb minus positive one-limb C arm.
  fn __bigint_sub1_7_raw(a, b) (i64 i64) i64
    result = ccall_nobox("w_bigint_alloc_hot", 7) ## i64
    mask = 140737488355327 ## i64
    rp = (result & mask) + 16 ## i64
    ap = (a & mask) + 16 ## i64
    bp = (b & mask) + 16 ## i64
    word = raw_load_u64(bp, 0) ## i64
    borrow = __bigint_sub1_7_exact(rp, ap, word) ## i64
    ccall_nobox("w_bigint_sub1_7_finish_raw", result)

  # Exact positive eight-limb minus positive one-limb C arm.
  fn __bigint_sub1_8_raw(a, b) (i64 i64) i64
    result = ccall_nobox("w_bigint_alloc_hot", 8) ## i64
    mask = 140737488355327 ## i64
    rp = (result & mask) + 16 ## i64
    ap = (a & mask) + 16 ## i64
    bp = (b & mask) + 16 ## i64
    word = raw_load_u64(bp, 0) ## i64
    borrow = __bigint_sub1_8_borrow_death(rp, ap, word) ## i64
    ccall_nobox("w_bigint_sub1_8_finish_raw", result)

# Exact floor square root for one machine-word magnitude. A hardware f64
# square root supplies a 32-bit seed; integer correction makes the result
# exact at perfect-square and binary64-rounding boundaries.
-> __bigint_isqrt_u64(value) (u64) u64
  root_i = Math.sqrt(value ## f64) ## i64
  if root_i > 4294967295
    root_i = 4294967295
  root = root_i ## u64
  square = root * root ## u64
  while square > value
    root -= 1
    square = root * root ## u64
  while value - square > (root << 1)
    root += 1
    square = root * root ## u64
  root

# Exact floor square root for a normalized two-limb magnitude. Normalize by an
# even shift so the top limb reaches bit 62, extend its exact 32-bit root with
# one 64/64 quotient, then correct the resulting 64-bit root in integer space.
# The quotient seed is within three of the exact root (Zimmermann's sqrtrem2
# base case), so the correction loops remain bounded.
fn __bigint_isqrt_u128(lo, hi, shift) (i64 i64 i64) i64
  ll <<~IR
    entry:
      %hi.wide = zext i64 %hi to i128
      %hi.word = shl i128 %hi.wide, 64
      %lo.wide = zext i64 %lo to i128
      %input = or i128 %hi.word, %lo.wide
      %shift.wide = zext i64 %shift to i128
      %normalized = shl i128 %input, %shift.wide
      %nlo = trunc i128 %normalized to i64
      %nhi.wide = lshr i128 %normalized, 64
      %nhi = trunc i128 %nhi.wide to i64
      br label %seed
    seed:
      %hi.f64 = uitofp i64 %nhi to double
      %sqrt.f64 = call double @sqrt(double %hi.f64)
      %high.raw = fptoui double %sqrt.f64 to i64
      %high.over = icmp ugt i64 %high.raw, 4294967295
      %high.seed = select i1 %high.over, i64 4294967295, i64 %high.raw
      %high.square = mul i64 %high.seed, %high.seed
      %high.rem.seed = sub i64 %nhi, %high.square
      br label %high.correct.down
    high.correct.down:
      %high.root.down = phi i64 [ %high.seed, %seed ], [ %high.root.dec, %high.correct.down.more ]
      %high.rem.down = phi i64 [ %high.rem.seed, %seed ], [ %high.rem.inc, %high.correct.down.more ]
      %high.negative = icmp slt i64 %high.rem.down, 0
      br i1 %high.negative, label %high.correct.down.more, label %high.correct.up
    high.correct.down.more:
      %high.twice.down = shl i64 %high.root.down, 1
      %high.delta.down = sub i64 %high.twice.down, 1
      %high.rem.inc = add i64 %high.rem.down, %high.delta.down
      %high.root.dec = sub i64 %high.root.down, 1
      br label %high.correct.down
    high.correct.up:
      %high.root.up = phi i64 [ %high.root.down, %high.correct.down ], [ %high.root.inc, %high.correct.up.more ]
      %high.rem.up = phi i64 [ %high.rem.down, %high.correct.down ], [ %high.rem.dec, %high.correct.up.more ]
      %high.twice.up = shl i64 %high.root.up, 1
      %high.too.small = icmp ugt i64 %high.rem.up, %high.twice.up
      br i1 %high.too.small, label %high.correct.up.more, label %extend
    high.correct.up.more:
      %high.delta.up = add i64 %high.twice.up, 1
      %high.rem.dec = sub i64 %high.rem.up, %high.delta.up
      %high.root.inc = add i64 %high.root.up, 1
      br label %high.correct.up
    extend:
      %rem.top = shl i64 %high.rem.up, 31
      %lo.top = lshr i64 %nlo, 33
      %numerator = or i64 %rem.top, %lo.top
      %quotient.raw = udiv i64 %numerator, %high.root.up
      %quotient.over = icmp ugt i64 %quotient.raw, 4294967295
      %quotient = select i1 %quotient.over, i64 4294967295, i64 %quotient.raw
      %high.word = shl i64 %high.root.up, 32
      %root.seed = or i64 %high.word, %quotient
      %root.seed.wide = zext i64 %root.seed to i128
      %square.seed = mul i128 %root.seed.wide, %root.seed.wide
      %rem.seed = sub i128 %normalized, %square.seed
      br label %correct.down
    correct.down:
      %root.down = phi i64 [ %root.seed, %extend ], [ %root.decremented, %correct.down.more ]
      %rem.down = phi i128 [ %rem.seed, %extend ], [ %rem.incremented, %correct.down.more ]
      %too.large = icmp slt i128 %rem.down, 0
      br i1 %too.large, label %correct.down.more, label %correct.up
    correct.down.more:
      %root.down.wide = zext i64 %root.down to i128
      %twice.down = shl i128 %root.down.wide, 1
      %delta.down = sub i128 %twice.down, 1
      %rem.incremented = add i128 %rem.down, %delta.down
      %root.decremented = sub i64 %root.down, 1
      br label %correct.down
    correct.up:
      %root.up = phi i64 [ %root.down, %correct.down ], [ %root.incremented, %correct.up.more ]
      %rem.up = phi i128 [ %rem.down, %correct.down ], [ %rem.decremented, %correct.up.more ]
      %root.up.wide = zext i64 %root.up to i128
      %twice.root = shl i128 %root.up.wide, 1
      %too.small = icmp ugt i128 %rem.up, %twice.root
      br i1 %too.small, label %correct.up.more, label %exit
    correct.up.more:
      %delta.up = add i128 %twice.root, 1
      %rem.decremented = sub i128 %rem.up, %delta.up
      %root.incremented = add i64 %root.up, 1
      br label %correct.up
    exit:
      %half.shift = lshr i64 %shift, 1
      %root = lshr i64 %root.up, %half.shift
      ret i64 %root
  IR

# Montgomery multiplication modulo an odd machine-word modulus (subtract-form
# REDC: inverse * modulus == 1 mod 2^64, so multiplier * modulus shares the
# exact low 64 bits of a * b and the reduction is borrow-only).
-> __bigint_mont_mul_u64(a, b, modulus, inverse) (u64 u64 u64 u64) u64
  product_low = a * b ## u64
  product_high = mulhi(a, b) ## u64
  multiplier = product_low * inverse ## u64
  correction_high = mulhi(multiplier, modulus) ## u64
  if product_high < correction_high
    return product_high - correction_high + modulus ## u64
  product_high - correction_high ## u64

# One strong Miller-Rabin witness in Montgomery form with a pre-converted
# Montgomery base `bm = base * R mod modulus`.
-> __bigint_prime_mr_pow_u64(modulus, inverse, one_m, minus_one_m, exponent, shifts, bm) (u64 u64 u64 u64 u64 i64 u64) i64
  x = bm ## u64
  power = bm ## u64
  e = exponent >> 1 ## u64
  while e != 0
    power = __bigint_mont_mul_u64(power, power, modulus, inverse) ## u64
    if (e & 1) != 0
      x = __bigint_mont_mul_u64(x, power, modulus, inverse) ## u64
    e = e >> 1 ## u64
  if x == one_m || x == minus_one_m
    return 1 ## i64
  r = 1 ## i64
  while r < shifts
    x = __bigint_mont_mul_u64(x, x, modulus, inverse) ## u64
    if x == minus_one_m
      return 1 ## i64
    r += 1
  0 ## i64

# One strong Miller-Rabin witness in Montgomery form. The caller supplies the
# shared per-candidate setup and a base smaller than the normalized one-limb
# BigInt magnitude.
-> __bigint_prime_mr_base_u64(modulus, inverse, one_m, r2, minus_one_m, exponent, shifts, base) (u64 u64 u64 u64 u64 u64 i64 u64) i64
  bm = __bigint_mont_mul_u64(base, r2, modulus, inverse) ## u64
  __bigint_prime_mr_pow_u64(modulus, inverse, one_m, minus_one_m, exponent, shifts, bm)

# Exact deterministic primality for normalized positive one-limb BigInts. Such
# values are at least 2^47, so after the small-factor screen the all-u64
# seven-witness set is the only required range; smaller witness tiers can never
# be reached by this representation.
-> __bigint_prime_u64(value) (u64) i64
  # Keep the helper exact for the whole machine-word range. The equality arms
  # also preserve early exits between the constant-divisibility tests instead
  # of encouraging the optimizer to speculate the complete screen at once.
  if value < 2
    return 0 ## i64
  if value == 2
    return 1 ## i64
  if value % 2 == 0
    return 0 ## i64
  if value == 3
    return 1 ## i64
  if value % 3 == 0
    return 0 ## i64
  if value == 5
    return 1 ## i64
  if value % 5 == 0
    return 0 ## i64
  if value == 7
    return 1 ## i64
  if value % 7 == 0
    return 0 ## i64
  if value == 11
    return 1 ## i64
  if value % 11 == 0
    return 0 ## i64
  if value == 13
    return 1 ## i64
  if value % 13 == 0
    return 0 ## i64
  if value == 17
    return 1 ## i64
  if value % 17 == 0
    return 0 ## i64
  if value == 19
    return 1 ## i64
  if value % 19 == 0
    return 0 ## i64
  if value == 23
    return 1 ## i64
  if value % 23 == 0
    return 0 ## i64
  if value == 29
    return 1 ## i64
  if value % 29 == 0
    return 0 ## i64
  if value == 31
    return 1 ## i64
  if value % 31 == 0
    return 0 ## i64
  if value == 37
    return 1 ## i64
  if value % 37 == 0
    return 0 ## i64
  if value == 41
    return 1 ## i64
  if value % 41 == 0
    return 0 ## i64
  if value == 43
    return 1 ## i64
  if value % 43 == 0
    return 0 ## i64
  if value == 47
    return 1 ## i64
  if value % 47 == 0
    return 0 ## i64
  if value == 53
    return 1 ## i64
  if value % 53 == 0
    return 0 ## i64

  inverse = (3 * value) ^ 2 ## u64
  inverse = inverse * (2 - value * inverse) ## u64
  inverse = inverse * (2 - value * inverse) ## u64
  inverse = inverse * (2 - value * inverse) ## u64
  inverse = inverse * (2 - value * inverse) ## u64
  one_m = (0 - value ## u64) % value ## u64
  minus_one_m = value - one_m ## u64
  shifts = ccall_nobox("__w_bit_cttz_u64", value - 1 ## u64) ## i64
  exponent = (value - 1 ## u64) >> shifts ## u64

  # Test witness 2 using 2*R mod value directly, avoiding the 128-bit % for r2
  # on >99.999% of composite inputs.
  two_m = one_m >= minus_one_m ? one_m - minus_one_m : one_m + one_m ## u64
  if __bigint_prime_mr_pow_u64(value, inverse, one_m, minus_one_m, exponent, shifts, two_m) == 0
    return 0 ## i64

  r2 = (((one_m ## u128) * (one_m ## u128)) % (value ## u128)) ## u64
  if __bigint_prime_mr_base_u64(value, inverse, one_m, r2, minus_one_m, exponent, shifts, 325 ## u64) == 0
    return 0 ## i64
  if __bigint_prime_mr_base_u64(value, inverse, one_m, r2, minus_one_m, exponent, shifts, 9375 ## u64) == 0
    return 0 ## i64
  if __bigint_prime_mr_base_u64(value, inverse, one_m, r2, minus_one_m, exponent, shifts, 28178 ## u64) == 0
    return 0 ## i64
  if __bigint_prime_mr_base_u64(value, inverse, one_m, r2, minus_one_m, exponent, shifts, 450775 ## u64) == 0
    return 0 ## i64
  if __bigint_prime_mr_base_u64(value, inverse, one_m, r2, minus_one_m, exponent, shifts, 9780504 ## u64) == 0
    return 0 ## i64
  if __bigint_prime_mr_base_u64(value, inverse, one_m, r2, minus_one_m, exponent, shifts, 1795265022 ## u64) == 0
    return 0 ## i64
  1 ## i64
