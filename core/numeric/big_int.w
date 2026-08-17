-> __bigint_shr_u64(value, count) (u64 i64) u64
  value >> count

# Binary greatest-common-divisor loop for two nonzero machine-word
# magnitudes. The caller proves nonzero through normalized one-limb BigInt
# headers, so the loop can strip powers of two without separate zero arms.
-> __bigint_gcd_u64_nonzero(a, b) (u64 u64) u64
  az = ccall_nobox("__w_bit_cttz_u64", a) ## i64
  bz = ccall_nobox("__w_bit_cttz_u64", b) ## i64
  shift = az ## i64
  if bz < shift
    shift = bz
  a >>= az
  b >>= bz
  while a != b
    d = a - b ## u64
    tz = ccall_nobox("__w_bit_cttz_u64", d) ## i64
    lo = b ## u64
    magnitude = d ## u64
    if a < b
      lo = a
      magnitude = 0 - d ## u64
    b = lo
    a = magnitude >> tz ## u64
  a << shift

# Exact whole-function port of runtime.c's AArch64 two-limb GCD leaf. A u128
# follows AAPCS64 directly: low and high result words leave in x0 and x1.
# Generic AArch64 keeps the C rbit/clz schedule. CSSC targets select the
# otherwise-identical single-instruction ctz body used by the native C build.
on arm64
  + BigInt
    fn __bigint_gcd_u128_nonzero(a_hi, a_lo, b_hi, b_lo) (i64 i64 i64 i64) u128
      asm <<~ASM
        cbnz x1, 11f
        rbit x9, x0
        clz x9, x9
        add x9, x9, #64
        b 12f
      11:
        rbit x9, x1
        clz x9, x9
      12:
        cbnz x3, 13f
        rbit x10, x2
        clz x10, x10
        add x10, x10, #64
        b 14f
      13:
        rbit x10, x3
        clz x10, x10
      14:
        cmp x9, x10
        csel x8, x9, x10, lo
        cmp x9, #64
        b.lo 15f
        sub x11, x9, #64
        lsr x1, x0, x11
        mov x0, xzr
        b 16f
      15:
        cbz x9, 16f
        neg x11, x9
        lsr x1, x1, x9
        lsl x11, x0, x11
        orr x1, x1, x11
        lsr x0, x0, x9
      16:
        cmp x10, #64
        b.lo 17f
        sub x11, x10, #64
        lsr x3, x2, x11
        mov x2, xzr
        b 18f
      17:
        cbz x10, 18f
        neg x11, x10
        lsr x3, x3, x10
        lsl x11, x2, x11
        orr x3, x3, x11
        lsr x2, x2, x10
      18:
      1:
        subs x4, x1, x3
        cbz x4, 4f
        sbcs x5, x0, x2
        rbit x6, x4
        clz x6, x6
        cneg x4, x4, lo
        cinv x5, x5, lo
        csel x3, x3, x1, hs
        csel x2, x2, x0, hs
        neg x7, x6
        lsr x1, x4, x6
        lsl x7, x5, x7
        lsr x0, x5, x6
        orr x1, x1, x7
        orr x7, x0, x2
        cbnz x7, 1b
      2:
        subs x4, x1, x3
        b.eq 5f
        nop
        nop
      9:
        rbit x5, x4
        clz x5, x5
        cneg x4, x4, lo
        csel x1, x3, x1, hs
        lsr x3, x4, x5
        subs x4, x1, x3
        b.ne 9b
      4:
        subs x5, x0, x2
        b.eq 6f
        cneg x5, x5, lo
        csel x2, x2, x0, hs
        rbit x6, x5
        clz x6, x6
        lsr x1, x5, x6
        mov x0, xzr
        cbnz x2, 1b
        b 2b
      5:
        mov x0, x1
        mov x1, xzr
        b 20f
      6:
        mov x4, x0
        mov x0, x1
        mov x1, x4
      20:
        cbz x8, 24f
        cmp x8, #64
        b.hs 23f
        neg x9, x8
        lsl x1, x1, x8
        lsr x9, x0, x9
        orr x1, x1, x9
        lsl x0, x0, x8
        b 24f
      23:
        sub x8, x8, #64
        lsl x1, x0, x8
        mov x0, xzr
      24:
        ret
      ASM
    on arm64 with cssc
      fn __bigint_gcd_u128_nonzero(a_hi, a_lo, b_hi, b_lo) (i64 i64 i64 i64) u128
        asm <<~ASM
          .arch_extension cssc
          cbnz x1, 11f
          ctz x9, x0
          add x9, x9, #64
          b 12f
        11:
          ctz x9, x1
        12:
          cbnz x3, 13f
          ctz x10, x2
          add x10, x10, #64
          b 14f
        13:
          ctz x10, x3
        14:
          cmp x9, x10
          csel x8, x9, x10, lo
          cmp x9, #64
          b.lo 15f
          sub x11, x9, #64
          lsr x1, x0, x11
          mov x0, xzr
          b 16f
        15:
          cbz x9, 16f
          neg x11, x9
          lsr x1, x1, x9
          lsl x11, x0, x11
          orr x1, x1, x11
          lsr x0, x0, x9
        16:
          cmp x10, #64
          b.lo 17f
          sub x11, x10, #64
          lsr x3, x2, x11
          mov x2, xzr
          b 18f
        17:
          cbz x10, 18f
          neg x11, x10
          lsr x3, x3, x10
          lsl x11, x2, x11
          orr x3, x3, x11
          lsr x2, x2, x10
        18:
        1:
          subs x4, x1, x3
          cbz x4, 4f
          sbcs x5, x0, x2
          ctz x6, x4
          cneg x4, x4, lo
          cinv x5, x5, lo
          csel x3, x3, x1, hs
          csel x2, x2, x0, hs
          neg x7, x6
          lsr x1, x4, x6
          lsl x7, x5, x7
          lsr x0, x5, x6
          orr x1, x1, x7
          orr x7, x0, x2
          cbnz x7, 1b
        2:
          subs x4, x1, x3
          b.eq 5f
          nop
          nop
        9:
          ctz x5, x4
          cneg x4, x4, lo
          csel x1, x3, x1, hs
          lsr x3, x4, x5
          subs x4, x1, x3
          b.ne 9b
        4:
          subs x5, x0, x2
          b.eq 6f
          cneg x5, x5, lo
          csel x2, x2, x0, hs
          ctz x6, x5
          lsr x1, x5, x6
          mov x0, xzr
          cbnz x2, 1b
          b 2b
        5:
          mov x0, x1
          mov x1, xzr
          b 20f
        6:
          mov x4, x0
          mov x0, x1
          mov x1, x4
        20:
          cbz x8, 24f
          cmp x8, #64
          b.hs 23f
          neg x9, x8
          lsl x1, x1, x8
          lsr x9, x0, x9
          orr x1, x1, x9
          lsl x0, x0, x8
          b 24f
        23:
          sub x8, x8, #64
          lsl x1, x0, x8
          mov x0, xzr
        24:
          ret
        ASM
# Exact AArch64/macOS port of runtime.c's fixed 4-by-2-limb Knuth leaf.
# These bodies are the optimized instruction schedule emitted from the C
# mag_divmod_42_core algorithm: identical Moller-Granlund reciprocal table,
# normalization, three 3-by-2 quotient digits, and bounded corrections. They
# write only the quotient or remainder limbs selected by the corresponding C
# wrapper; allocation and canonicalization remain the shared runtime policy.
on macos && arm64
  fn __bigint_div_42_exact(rp, up, vp) (i64 i64 i64) i64
    asm <<~ASM
      ldr	x8, [x2, #8]
      clz	x14, x8
      cbz	x14, 2f
      ldr	x10, [x2]
      lsl	x9, x10, x14
      lsl	x8, x8, x14
      lsr	x10, x10, #1
      mvn	w13, w14
      lsr	x10, x10, x13
      orr	x8, x8, x10
      ldp	x11, x12, [x1]
      lsl	x10, x11, x14
      lsl	x15, x12, x14
      lsr	x11, x11, #1
      lsr	x11, x11, x13
      orr	x11, x15, x11
      ldp	x15, x16, [x1, #16]
      lsl	x17, x15, x14
      lsr	x12, x12, #1
      lsr	x12, x12, x13
      orr	x12, x17, x12
      lsl	x17, x16, x14
      lsr	x15, x15, #1
      lsr	x13, x15, x13
      orr	x13, x17, x13
      neg	x14, x14
      lsr	x15, x16, x14
      b	3f
      2:
      mov	x15, #0
      ldp	x10, x11, [x1]
      ldp	x12, x13, [x1, #16]
      ldr	x9, [x2]
      3:
      lsr	x14, x8, #55
      adr	x16, 90f
      add	x14, x16, x14, lsl #1
      sub	x14, x14, #512
      ldrh	w14, [x14]
      lsr	x16, x8, #24
      add	x16, x16, #1
      mul	x17, x16, x14
      mul	x17, x17, x14
      mvn	x17, x17, lsr #40
      add	x14, x17, x14, lsl #11
      mov	x17, #1152921504606846976
      msub	x16, x14, x16, x17
      mul	x16, x16, x14
      lsr	x16, x16, #47
      add	x14, x16, x14, lsl #13
      sbfx	x16, x8, #0, #1
      and	x17, x8, #0x1
      add	x17, x17, x8, lsr #1
      and	x16, x16, x14, lsr #1
      msub	x16, x14, x17, x16
      lsl	x17, x14, #31
      umulh	x14, x16, x14
      add	x14, x17, x14, lsr #1
      adds	x16, x14, #1
      cset	w17, hs
      umulh	x16, x16, x8
      madd	x16, x17, x8, x16
      sub	x14, x14, x8
      sub	x16, x14, x16
      mul	x14, x16, x8
      adds	x14, x14, x9
      b.lo	5f
      cmp	x14, x8
      csel	x17, x8, xzr, hs
      cset	w1, hs
      mvn	x1, x1
      add	x16, x1, x16
      sub	x14, x14, x8
      sub	x14, x14, x17
      5:
      umulh	x17, x16, x9
      adds	x17, x14, x17
      b.lo	11f
      sub	x14, x16, #1
      cmp	x17, x8
      b.lo	8f
      mul	x1, x16, x9
      sub	x16, x16, #2
      cmp	x17, x8
      ccmp	x9, x1, #0, ls
      csel	x14, x14, x16, hi
      8:
      cbz	x15, 12f
      9:
      umulh	x16, x14, x15
      mul	x17, x14, x15
      adds	x17, x13, x17
      adc	x15, x15, x16
      msub	x13, x8, x15, x13
      umulh	x16, x15, x9
      mul	x1, x15, x9
      adds	x1, x9, x1
      adc	x16, x8, x16
      subs	x12, x12, x1
      ngc	x16, x16
      add	x13, x16, x13
      cmp	x13, x17
      cset	w16, hs
      csel	x17, x8, xzr, hs
      csel	x1, x9, xzr, hs
      sub	x15, x15, x16
      add	x15, x15, #1
      adds	x12, x12, x1
      adc	x13, x17, x13
      cmp	x12, x9
      sbcs	xzr, x13, x8
      b.lo	16f
      add	x15, x15, #1
      subs	x12, x12, x9
      sbc	x13, x13, x8
      b	16f
      11:
      mov	x14, x16
      cbnz	x15, 9b
      12:
      cmp	x13, x8
      b.hi	15f
      mov	x15, #0
      b.ne	16f
      cmp	x12, x9
      b.lo	16f
      15:
      subs	x12, x12, x9
      ngc	x15, x8
      add	x13, x13, x15
      mov	w15, #1
      16:
      umulh	x16, x13, x14
      mul	x17, x13, x14
      adds	x17, x12, x17
      adc	x13, x13, x16
      msub	x12, x8, x13, x12
      umulh	x16, x13, x9
      mul	x1, x13, x9
      adds	x1, x9, x1
      adc	x16, x8, x16
      subs	x1, x11, x1
      ngc	x11, x16
      add	x16, x11, x12
      cmp	x16, x17
      cset	w11, hs
      csel	x17, x8, xzr, hs
      csel	x12, x9, xzr, hs
      sub	x11, x13, x11
      add	x11, x11, #1
      adds	x12, x1, x12
      adc	x13, x17, x16
      cmp	x12, x9
      sbcs	xzr, x13, x8
      b.hs	19f
      17:
      umulh	x16, x13, x14
      mul	x14, x13, x14
      adds	x14, x12, x14
      adc	x13, x13, x16
      msub	x12, x8, x13, x12
      umulh	x16, x13, x9
      mul	x17, x13, x9
      adds	x17, x9, x17
      adc	x16, x8, x16
      subs	x17, x10, x17
      ngc	x10, x16
      add	x12, x10, x12
      cmp	x12, x14
      cset	w10, hs
      csel	x14, x8, xzr, hs
      csel	x16, x9, xzr, hs
      sub	x10, x13, x10
      add	x10, x10, #1
      adds	x13, x17, x16
      adc	x12, x14, x12
      cmp	x13, x9
      sbcs	xzr, x12, x8
      b.hs	20f
      stp	x10, x11, [x0]
      str	x15, [x0, #16]
      ret
      19:
      add	x11, x11, #1
      subs	x12, x12, x9
      sbc	x13, x13, x8
      b	17b
      20:
      add	x10, x10, #1
      stp	x10, x11, [x0]
      str	x15, [x0, #16]
      ret
      .p2align 1
      90:
      .short 0x7fd, 0x7f5, 0x7ed, 0x7e5, 0x7dd, 0x7d5, 0x7ce, 0x7c6
      .short 0x7bf, 0x7b7, 0x7b0, 0x7a8, 0x7a1, 0x79a, 0x792, 0x78b
      .short 0x784, 0x77d, 0x776, 0x76f, 0x768, 0x761, 0x75b, 0x754
      .short 0x74d, 0x747, 0x740, 0x739, 0x733, 0x72c, 0x726, 0x720
      .short 0x719, 0x713, 0x70d, 0x707, 0x700, 0x6fa, 0x6f4, 0x6ee
      .short 0x6e8, 0x6e2, 0x6dc, 0x6d6, 0x6d1, 0x6cb, 0x6c5, 0x6bf
      .short 0x6ba, 0x6b4, 0x6ae, 0x6a9, 0x6a3, 0x69e, 0x698, 0x693
      .short 0x68d, 0x688, 0x683, 0x67d, 0x678, 0x673, 0x66e, 0x669
      .short 0x664, 0x65e, 0x659, 0x654, 0x64f, 0x64a, 0x645, 0x640
      .short 0x63c, 0x637, 0x632, 0x62d, 0x628, 0x624, 0x61f, 0x61a
      .short 0x616, 0x611, 0x60c, 0x608, 0x603, 0x5ff, 0x5fa, 0x5f6
      .short 0x5f1, 0x5ed, 0x5e9, 0x5e4, 0x5e0, 0x5dc, 0x5d7, 0x5d3
      .short 0x5cf, 0x5cb, 0x5c6, 0x5c2, 0x5be, 0x5ba, 0x5b6, 0x5b2
      .short 0x5ae, 0x5aa, 0x5a6, 0x5a2, 0x59e, 0x59a, 0x596, 0x592
      .short 0x58e, 0x58a, 0x586, 0x583, 0x57f, 0x57b, 0x577, 0x574
      .short 0x570, 0x56c, 0x568, 0x565, 0x561, 0x55e, 0x55a, 0x556
      .short 0x553, 0x54f, 0x54c, 0x548, 0x545, 0x541, 0x53e, 0x53a
      .short 0x537, 0x534, 0x530, 0x52d, 0x52a, 0x526, 0x523, 0x520
      .short 0x51c, 0x519, 0x516, 0x513, 0x50f, 0x50c, 0x509, 0x506
      .short 0x503, 0x500, 0x4fc, 0x4f9, 0x4f6, 0x4f3, 0x4f0, 0x4ed
      .short 0x4ea, 0x4e7, 0x4e4, 0x4e1, 0x4de, 0x4db, 0x4d8, 0x4d5
      .short 0x4d2, 0x4cf, 0x4cc, 0x4ca, 0x4c7, 0x4c4, 0x4c1, 0x4be
      .short 0x4bb, 0x4b9, 0x4b6, 0x4b3, 0x4b0, 0x4ad, 0x4ab, 0x4a8
      .short 0x4a5, 0x4a3, 0x4a0, 0x49d, 0x49b, 0x498, 0x495, 0x493
      .short 0x490, 0x48d, 0x48b, 0x488, 0x486, 0x483, 0x481, 0x47e
      .short 0x47c, 0x479, 0x477, 0x474, 0x472, 0x46f, 0x46d, 0x46a
      .short 0x468, 0x465, 0x463, 0x461, 0x45e, 0x45c, 0x459, 0x457
      .short 0x455, 0x452, 0x450, 0x44e, 0x44b, 0x449, 0x447, 0x444
      .short 0x442, 0x440, 0x43e, 0x43b, 0x439, 0x437, 0x435, 0x432
      .short 0x430, 0x42e, 0x42c, 0x42a, 0x428, 0x425, 0x423, 0x421
      .short 0x41f, 0x41d, 0x41b, 0x419, 0x417, 0x414, 0x412, 0x410
      .short 0x40e, 0x40c, 0x40a, 0x408, 0x406, 0x404, 0x402, 0x400
    ASM

fn __bigint_mod_42_exact(rp, up, vp) (i64 i64 i64) i64
    asm <<~ASM
      ldr	x9, [x2, #8]
      clz	x8, x9
      cbz	x8, 2f
      ldr	x11, [x2]
      lsl	x10, x11, x8
      lsl	x9, x9, x8
      lsr	x11, x11, #1
      mvn	w14, w8
      lsr	x11, x11, x14
      orr	x9, x9, x11
      ldp	x12, x13, [x1]
      lsl	x11, x12, x8
      lsl	x15, x13, x8
      lsr	x12, x12, #1
      lsr	x12, x12, x14
      orr	x12, x15, x12
      ldp	x15, x16, [x1, #16]
      lsl	x17, x15, x8
      lsr	x13, x13, #1
      lsr	x13, x13, x14
      orr	x13, x17, x13
      lsl	x17, x16, x8
      lsr	x15, x15, #1
      lsr	x14, x15, x14
      orr	x14, x17, x14
      neg	x15, x8
      lsr	x15, x16, x15
      b	3f
      2:
      mov	x15, #0
      ldp	x11, x12, [x1]
      ldp	x13, x14, [x1, #16]
      ldr	x10, [x2]
      3:
      lsr	x16, x9, #55
      adr	x17, 90f
      add	x16, x17, x16, lsl #1
      sub	x16, x16, #512
      ldrh	w16, [x16]
      lsr	x17, x9, #24
      add	x17, x17, #1
      mul	x1, x17, x16
      mul	x1, x1, x16
      mvn	x1, x1, lsr #40
      add	x16, x1, x16, lsl #11
      mov	x1, #1152921504606846976
      msub	x17, x16, x17, x1
      mul	x17, x17, x16
      lsr	x17, x17, #47
      add	x16, x17, x16, lsl #13
      sbfx	x17, x9, #0, #1
      and	x1, x9, #0x1
      add	x1, x1, x9, lsr #1
      and	x17, x17, x16, lsr #1
      msub	x17, x16, x1, x17
      lsl	x1, x16, #31
      umulh	x16, x17, x16
      add	x16, x1, x16, lsr #1
      adds	x17, x16, #1
      cset	w1, hs
      umulh	x17, x17, x9
      madd	x17, x1, x9, x17
      sub	x16, x16, x9
      sub	x17, x16, x17
      mul	x16, x17, x9
      adds	x16, x16, x10
      b.lo	5f
      cmp	x16, x9
      csel	x1, x9, xzr, hs
      cset	w2, hs
      mvn	x2, x2
      add	x17, x2, x17
      sub	x16, x16, x9
      sub	x16, x16, x1
      5:
      umulh	x1, x17, x10
      adds	x1, x16, x1
      b.lo	11f
      sub	x16, x17, #1
      cmp	x1, x9
      b.lo	8f
      mul	x2, x17, x10
      sub	x17, x17, #2
      cmp	x1, x9
      ccmp	x10, x2, #0, ls
      csel	x16, x16, x17, hi
      8:
      cbz	x15, 12f
      9:
      umulh	x17, x16, x15
      mul	x1, x16, x15
      adds	x1, x14, x1
      adc	x15, x15, x17
      msub	x14, x9, x15, x14
      umulh	x17, x15, x10
      mul	x15, x15, x10
      adds	x15, x10, x15
      adc	x17, x9, x17
      subs	x13, x13, x15
      ngc	x15, x17
      add	x14, x15, x14
      cmp	x14, x1
      csel	x15, xzr, x9, lo
      csel	x17, xzr, x10, lo
      adds	x13, x13, x17
      adc	x14, x15, x14
      cmp	x13, x10
      sbcs	xzr, x14, x9
      b.lo	16f
      subs	x13, x13, x10
      sbc	x14, x14, x9
      b	16f
      11:
      mov	x16, x17
      cbnz	x15, 9b
      12:
      cmp	x14, x9
      b.hi	15f
      b.ne	16f
      cmp	x13, x10
      b.lo	16f
      15:
      subs	x13, x13, x10
      ngc	x15, x9
      add	x14, x14, x15
      16:
      umulh	x15, x14, x16
      mul	x17, x14, x16
      adds	x17, x13, x17
      adc	x14, x14, x15
      msub	x13, x9, x14, x13
      umulh	x15, x14, x10
      mul	x14, x14, x10
      adds	x14, x10, x14
      adc	x15, x9, x15
      subs	x12, x12, x14
      ngc	x14, x15
      add	x13, x14, x13
      cmp	x13, x17
      csel	x14, xzr, x9, lo
      csel	x15, xzr, x10, lo
      adds	x12, x12, x15
      adc	x13, x14, x13
      cmp	x12, x10
      sbcs	xzr, x13, x9
      b.hs	19f
      17:
      umulh	x14, x13, x16
      mul	x15, x13, x16
      adds	x15, x12, x15
      adc	x13, x13, x14
      msub	x12, x9, x13, x12
      umulh	x14, x13, x10
      mul	x13, x13, x10
      adds	x13, x10, x13
      adc	x14, x9, x14
      subs	x11, x11, x13
      ngc	x13, x14
      add	x13, x13, x12
      cmp	x13, x15
      csel	x14, xzr, x9, lo
      csel	x12, xzr, x10, lo
      adds	x12, x11, x12
      adc	x11, x14, x13
      cmp	x12, x10
      sbcs	xzr, x11, x9
      b.hs	20f
      18:
      lsr	x9, x11, x8
      lsr	x10, x12, x8
      mvn	w8, w8
      lsl	x11, x11, #1
      lsl	x8, x11, x8
      orr	x8, x8, x10
      stp	x8, x9, [x0]
      ret
      19:
      subs	x12, x12, x10
      sbc	x13, x13, x9
      b	17b
      20:
      subs	x12, x12, x10
      sbc	x11, x11, x9
      b	18b
      .p2align 1
      90:
      .short 0x7fd, 0x7f5, 0x7ed, 0x7e5, 0x7dd, 0x7d5, 0x7ce, 0x7c6
      .short 0x7bf, 0x7b7, 0x7b0, 0x7a8, 0x7a1, 0x79a, 0x792, 0x78b
      .short 0x784, 0x77d, 0x776, 0x76f, 0x768, 0x761, 0x75b, 0x754
      .short 0x74d, 0x747, 0x740, 0x739, 0x733, 0x72c, 0x726, 0x720
      .short 0x719, 0x713, 0x70d, 0x707, 0x700, 0x6fa, 0x6f4, 0x6ee
      .short 0x6e8, 0x6e2, 0x6dc, 0x6d6, 0x6d1, 0x6cb, 0x6c5, 0x6bf
      .short 0x6ba, 0x6b4, 0x6ae, 0x6a9, 0x6a3, 0x69e, 0x698, 0x693
      .short 0x68d, 0x688, 0x683, 0x67d, 0x678, 0x673, 0x66e, 0x669
      .short 0x664, 0x65e, 0x659, 0x654, 0x64f, 0x64a, 0x645, 0x640
      .short 0x63c, 0x637, 0x632, 0x62d, 0x628, 0x624, 0x61f, 0x61a
      .short 0x616, 0x611, 0x60c, 0x608, 0x603, 0x5ff, 0x5fa, 0x5f6
      .short 0x5f1, 0x5ed, 0x5e9, 0x5e4, 0x5e0, 0x5dc, 0x5d7, 0x5d3
      .short 0x5cf, 0x5cb, 0x5c6, 0x5c2, 0x5be, 0x5ba, 0x5b6, 0x5b2
      .short 0x5ae, 0x5aa, 0x5a6, 0x5a2, 0x59e, 0x59a, 0x596, 0x592
      .short 0x58e, 0x58a, 0x586, 0x583, 0x57f, 0x57b, 0x577, 0x574
      .short 0x570, 0x56c, 0x568, 0x565, 0x561, 0x55e, 0x55a, 0x556
      .short 0x553, 0x54f, 0x54c, 0x548, 0x545, 0x541, 0x53e, 0x53a
      .short 0x537, 0x534, 0x530, 0x52d, 0x52a, 0x526, 0x523, 0x520
      .short 0x51c, 0x519, 0x516, 0x513, 0x50f, 0x50c, 0x509, 0x506
      .short 0x503, 0x500, 0x4fc, 0x4f9, 0x4f6, 0x4f3, 0x4f0, 0x4ed
      .short 0x4ea, 0x4e7, 0x4e4, 0x4e1, 0x4de, 0x4db, 0x4d8, 0x4d5
      .short 0x4d2, 0x4cf, 0x4cc, 0x4ca, 0x4c7, 0x4c4, 0x4c1, 0x4be
      .short 0x4bb, 0x4b9, 0x4b6, 0x4b3, 0x4b0, 0x4ad, 0x4ab, 0x4a8
      .short 0x4a5, 0x4a3, 0x4a0, 0x49d, 0x49b, 0x498, 0x495, 0x493
      .short 0x490, 0x48d, 0x48b, 0x488, 0x486, 0x483, 0x481, 0x47e
      .short 0x47c, 0x479, 0x477, 0x474, 0x472, 0x46f, 0x46d, 0x46a
      .short 0x468, 0x465, 0x463, 0x461, 0x45e, 0x45c, 0x459, 0x457
      .short 0x455, 0x452, 0x450, 0x44e, 0x44b, 0x449, 0x447, 0x444
      .short 0x442, 0x440, 0x43e, 0x43b, 0x439, 0x437, 0x435, 0x432
      .short 0x430, 0x42e, 0x42c, 0x42a, 0x428, 0x425, 0x423, 0x421
      .short 0x41f, 0x41d, 0x41b, 0x419, 0x417, 0x414, 0x412, 0x410
      .short 0x40e, 0x40c, 0x40a, 0x408, 0x406, 0x404, 0x402, 0x400
  ASM

# Exact arithmetic/certificate body for mag_div_q_63_certified.  This is the
# Clang 22.1.8 -O3 -mcpu=apple-m5 schedule generated from the C leaf after
# splitting only its capacity-four allocation/finalization into the wrapper.
on macos && arm64
  fn __bigint_div_63_exact(rp, up, vp) (i64 i64 i64) i64
    asm <<~ASM
      .arch_extension cssc
      sub	sp, sp, #48
      stp	x20, x19, [sp, #32]
      mov	x9, x2
      ldr	x8, [x9, #16]!
      clz	x12, x8
      cbz	x12, Ldivq63_2
      lsl	x8, x8, x12
      add	x10, sp, #8
      ldp	x13, x11, [x2]
      lsr	x9, x11, #1
      mvn	w14, w12
      lsr	x15, x9, x14
      add	x9, x10, #16
      lsl	x16, x11, x12
      add	x11, x10, #8
      lsr	x10, x13, #1
      orr	x8, x8, x15
      lsr	x10, x10, x14
      orr	x10, x16, x10
      lsl	x13, x13, x12
      stp	x10, x8, [sp, #16]
      str	x13, [sp, #8]
      ldp	x15, x13, [x1, #32]
      lsl	x16, x13, x12
      lsr	x17, x15, #1
      lsr	x17, x17, x14
      orr	x3, x16, x17
      lsl	x15, x15, x12
      ldp	x2, x16, [x1, #16]
      lsr	x17, x16, #1
      lsr	x17, x17, x14
      orr	x17, x15, x17
      lsl	x15, x16, x12
      lsr	x16, x2, #1
      lsr	x16, x16, x14
      orr	x16, x15, x16
      lsl	x15, x2, x12
      ldp	x1, x2, [x1]
      lsr	x4, x2, #1
      lsr	x4, x4, x14
      orr	x15, x15, x4
      neg	x4, x12
      lsl	x12, x2, x12
      lsr	x1, x1, #1
      lsr	x14, x1, x14
      orr	x12, x12, x14
      add	x2, sp, #8
      lsr	x14, x13, x4
      b	Ldivq63_3
      Ldivq63_2:
      mov	x14, #0
      sub	x11, x9, #8
      ldp	x17, x3, [x1, #32]
      ldp	x15, x16, [x1, #16]
      ldr	x12, [x1, #8]
      ldr	x10, [x11]
      Ldivq63_3:
      lsr	x13, x8, #55
      adr x1, 90f
      add	x13, x1, x13, lsl #1
      sub	x13, x13, #512
      ldrh	w13, [x13]
      lsr	x1, x8, #24
      add	x1, x1, #1
      mul	x4, x1, x13
      mul	x4, x4, x13
      mvn	x4, x4, lsr #40
      add	x13, x4, x13, lsl #11
      mov	x4, #1152921504606846976
      msub	x1, x13, x1, x4
      mul	x1, x1, x13
      lsr	x1, x1, #47
      add	x13, x1, x13, lsl #13
      sbfx	x1, x8, #0, #1
      and	x4, x8, #0x1
      add	x4, x4, x8, lsr #1
      and	x1, x1, x13, lsr #1
      msub	x1, x13, x4, x1
      lsl	x4, x13, #31
      umulh	x13, x1, x13
      add	x13, x4, x13, lsr #1
      adds	x1, x13, #1
      cset	w4, hs
      umulh	x1, x1, x8
      madd	x1, x4, x8, x1
      sub	x13, x13, x8
      sub	x1, x13, x1
      mul	x13, x1, x8
      adds	x13, x13, x10
      b.lo	Ldivq63_5
      cmp	x13, x8
      csel	x4, x8, xzr, hs
      cset	w5, hs
      mvn	x5, x5
      add	x1, x5, x1
      sub	x13, x13, x8
      sub	x13, x13, x4
      Ldivq63_5:
      umulh	x4, x1, x10
      adds	x4, x13, x4
      b.lo	Ldivq63_41
      sub	x13, x1, #1
      cmp	x4, x8
      b.lo	Ldivq63_8
      mul	x5, x1, x10
      sub	x1, x1, #2
      cmp	x4, x8
      ccmp	x10, x5, #0, ls
      csel	x13, x13, x1, hi
      Ldivq63_8:
      cbz	x14, Ldivq63_42
      Ldivq63_9:
      cmp	x14, x8
      b.lo	Ldivq63_12
      b.hi	Ldivq63_69
      cmp	x3, x10
      b.hs	Ldivq63_69
      Ldivq63_12:
      umulh	x1, x14, x13
      mul	x4, x14, x13
      adds	x4, x3, x4
      adc	x14, x14, x1
      msub	x1, x8, x14, x3
      umulh	x3, x14, x10
      mul	x5, x14, x10
      adds	x5, x10, x5
      adc	x3, x8, x3
      subs	x17, x17, x5
      ngc	x3, x3
      add	x3, x3, x1
      cmp	x3, x4
      cset	w1, hs
      csel	x4, x8, xzr, hs
      csel	x5, x10, xzr, hs
      sub	x14, x14, x1
      add	x1, x14, #1
      adds	x17, x17, x5
      adc	x14, x4, x3
      cmp	x17, x10
      sbcs	xzr, x14, x8
      b.hs	Ldivq63_61
      Ldivq63_13:
      ldr	x4, [x2]
      umulh	x3, x4, x1
      mul	x5, x4, x1
      subs	x16, x16, x5
      cinc	x3, x3, lo
      subs	x17, x17, x3
      cset	w3, lo
      subs	x3, x14, x3
      b.lo	Ldivq63_62
      mov	x14, #0
      Ldivq63_15:
      str	x1, [x0, #24]
      cmp	x3, x8
      b.lo	Ldivq63_18
      b.hi	Ldivq63_63
      cmp	x17, x10
      b.hs	Ldivq63_63
      Ldivq63_18:
      umulh	x1, x3, x13
      mul	x4, x3, x13
      adds	x4, x17, x4
      adc	x1, x3, x1
      msub	x17, x8, x1, x17
      umulh	x3, x1, x10
      mul	x5, x1, x10
      adds	x5, x10, x5
      adc	x3, x8, x3
      subs	x16, x16, x5
      ngc	x3, x3
      add	x17, x3, x17
      cmp	x17, x4
      cset	w3, hs
      csel	x4, x8, xzr, hs
      csel	x5, x10, xzr, hs
      sub	x1, x1, x3
      add	x1, x1, #1
      adds	x16, x16, x5
      adc	x17, x4, x17
      cmp	x16, x10
      sbcs	xzr, x17, x8
      b.hs	Ldivq63_56
      Ldivq63_19:
      ldr	x3, [x2]
      umulh	x5, x3, x1
      mul	x4, x3, x1
      subs	x4, x15, x4
      cinc	x15, x5, lo
      subs	x16, x16, x15
      cset	w15, lo
      subs	x17, x17, x15
      b.lo	Ldivq63_57
      mov	x15, #0
      Ldivq63_21:
      str	x1, [x0, #16]
      cmp	x17, x8
      b.lo	Ldivq63_24
      b.hi	Ldivq63_65
      cmp	x16, x10
      b.hs	Ldivq63_65
      Ldivq63_24:
      umulh	x1, x17, x13
      mul	x3, x17, x13
      adds	x3, x16, x3
      adc	x17, x17, x1
      msub	x16, x8, x17, x16
      umulh	x1, x17, x10
      mul	x5, x17, x10
      adds	x5, x10, x5
      adc	x1, x8, x1
      subs	x4, x4, x5
      ngc	x1, x1
      add	x16, x1, x16
      cmp	x16, x3
      cset	w1, hs
      csel	x5, x8, xzr, hs
      csel	x6, x10, xzr, hs
      sub	x17, x17, x1
      add	x3, x17, #1
      adds	x1, x4, x6
      adc	x17, x5, x16
      cmp	x1, x10
      sbcs	xzr, x17, x8
      b.hs	Ldivq63_58
      Ldivq63_25:
      ldr	x4, [x2]
      umulh	x2, x4, x3
      mul	x16, x4, x3
      subs	x16, x12, x16
      cinc	x12, x2, lo
      subs	x1, x1, x12
      cset	w12, lo
      subs	x2, x17, x12
      b.lo	Ldivq63_59
      mov	x12, #0
      Ldivq63_27:
      str	x3, [x0, #8]
      cmp	x2, x8
      b.lo	Ldivq63_30
      b.hi	Ldivq63_67
      cmp	x1, x10
      b.hs	Ldivq63_67
      Ldivq63_30:
      umulh	x11, x2, x13
      mul	x13, x2, x13
      adds	x13, x1, x13
      adc	x11, x2, x11
      msub	x17, x8, x11, x1
      umulh	x1, x11, x10
      mul	x2, x11, x10
      adds	x2, x10, x2
      adc	x1, x8, x1
      subs	x16, x16, x2
      ngc	x1, x1
      add	x1, x1, x17
      cmp	x1, x13
      cset	w13, hs
      csel	x2, x8, xzr, hs
      csel	x17, x10, xzr, hs
      sub	x11, x11, x13
      add	x13, x11, #1
      adds	x17, x16, x17
      adc	x11, x2, x1
      cmp	x17, x10
      sbcs	xzr, x11, x8
      b.hs	Ldivq63_60
      mov	x16, #0
      Ldivq63_32:
      str	x13, [x0]
      mov	x8, #-1
      cbnz	x14, Ldivq63_40
      cbnz	x15, Ldivq63_40
      cbnz	x12, Ldivq63_40
      cbnz	x16, Ldivq63_40
      cbz	x11, Ldivq63_40
      ldr	x8, [x9]
      cmp	x11, x8
      b.hs	Ldivq63_48
      ldr	x8, [x0, #24]
      cbz	x8, Ldivq63_51
      mov	w8, #4
      Ldivq63_40:
      mov	x0, x8
      ldp	x20, x19, [sp, #32]
      add	sp, sp, #48
      ret
      Ldivq63_41:
      mov	x13, x1
      cbnz	x14, Ldivq63_9
      Ldivq63_42:
      cmp	x3, x8
      b.hi	Ldivq63_45
      mov	x14, #0
      b.ne	Ldivq63_50
      cmp	x17, x10
      b.lo	Ldivq63_50
      Ldivq63_45:
      ldr	x6, [x2]
      subs	x5, x16, x6
      cset	w14, lo
      adds	x14, x10, x14
      cset	w1, hs
      subs	x17, x17, x14
      csinc	w14, w1, wzr, hs
      adds	x14, x8, x14
      sub	x4, x3, x14
      b.hs	Ldivq63_49
      cmp	x3, x14
      b.lo	Ldivq63_49
      mov	x14, #0
      mov	w1, #1
      mov	x3, x4
      mov	x16, x5
      b	Ldivq63_15
      Ldivq63_48:
      mov	x8, #-1
      mov	x0, x8
      ldp	x20, x19, [sp, #32]
      add	sp, sp, #48
      ret
      Ldivq63_49:
      mov	x14, #0
      mov	x1, #0
      cmp	x16, x6
      cset	w3, lo
      adds	x17, x17, x3
      cset	w3, hs
      adds	x17, x17, x10
      adc	x3, x4, x3
      add	x3, x3, x8
      b	Ldivq63_15
      Ldivq63_50:
      mov	x1, x14
      b	Ldivq63_15
      Ldivq63_51:
      ldr	x8, [x0, #16]
      cbz	x8, Ldivq63_53
      mov	w8, #3
      mov	x0, x8
      ldp	x20, x19, [sp, #32]
      add	sp, sp, #48
      ret
      Ldivq63_53:
      ldr	x8, [x0, #8]
      cbz	x8, Ldivq63_55
      mov	w8, #2
      mov	x0, x8
      ldp	x20, x19, [sp, #32]
      add	sp, sp, #48
      ret
      Ldivq63_55:
      umin	x8, x13, #1
      mov	x0, x8
      ldp	x20, x19, [sp, #32]
      add	sp, sp, #48
      ret
      Ldivq63_56:
      add	x1, x1, #1
      subs	x16, x16, x10
      sbc	x17, x17, x8
      b	Ldivq63_19
      Ldivq63_57:
      mov	x15, #0
      sub	x1, x1, #1
      adds	x4, x4, x3
      ldr	x3, [x11]
      adcs	x16, x16, x3
      ldr	x3, [x9]
      adc	x17, x3, x17
      b	Ldivq63_21
      Ldivq63_58:
      add	x3, x3, #1
      subs	x1, x1, x10
      sbc	x17, x17, x8
      b	Ldivq63_25
      Ldivq63_59:
      mov	x12, #0
      sub	x3, x3, #1
      adds	x16, x16, x4
      ldr	x17, [x11]
      adcs	x1, x1, x17
      ldr	x17, [x9]
      adc	x2, x17, x2
      b	Ldivq63_27
      Ldivq63_60:
      mov	x16, #0
      add	x13, x13, #1
      cmp	x17, x10
      sbc	x11, x11, x8
      b	Ldivq63_32
      Ldivq63_61:
      add	x1, x1, #1
      subs	x17, x17, x10
      sbc	x14, x14, x8
      b	Ldivq63_13
      Ldivq63_62:
      mov	x14, #0
      sub	x1, x1, #1
      adds	x16, x16, x4
      ldr	x4, [x11]
      adcs	x17, x17, x4
      ldr	x4, [x9]
      adc	x3, x4, x3
      b	Ldivq63_15
      Ldivq63_63:
      ldr	x5, [x2]
      mov	x1, #-1
      umulh	x4, x5, x1
      neg	x6, x5
      cmp	x15, x6
      cinc	x4, x4, lo
      ldr	x6, [x11]
      neg	x7, x6
      adds	x19, x4, x7
      subs	x16, x16, x19
      cset	w19, lo
      cmn	x4, x7
      umulh	x4, x6, x1
      adc	x4, x19, x4
      ldr	x7, [x9]
      neg	x19, x7
      adds	x20, x4, x19
      subs	x17, x17, x20
      cset	w20, lo
      cmn	x4, x19
      add	x4, x15, x5
      umulh	x15, x7, x1
      adc	x15, x20, x15
      subs	x15, x3, x15
      b.hs	Ldivq63_21
      adds	x4, x4, x5
      adcs	x16, x16, xzr
      cset	w1, hs
      adds	x16, x16, x6
      adcs	x17, x17, x1
      cset	w1, hs
      adds	x17, x17, x7
      adc	x15, x15, x1
      mov	x1, #-2
      b	Ldivq63_21
      Ldivq63_65:
      ldr	x5, [x2]
      mov	x3, #-1
      umulh	x1, x5, x3
      neg	x2, x5
      cmp	x12, x2
      cinc	x2, x1, lo
      ldr	x6, [x11]
      neg	x7, x6
      adds	x1, x2, x7
      subs	x1, x4, x1
      cset	w4, lo
      cmn	x2, x7
      umulh	x2, x6, x3
      adc	x7, x4, x2
      ldr	x4, [x9]
      neg	x19, x4
      adds	x2, x7, x19
      subs	x2, x16, x2
      cset	w20, lo
      cmn	x7, x19
      add	x16, x12, x5
      umulh	x12, x4, x3
      adc	x12, x20, x12
      subs	x12, x17, x12
      b.hs	Ldivq63_27
      adds	x16, x16, x5
      adcs	x17, x1, xzr
      cset	w3, hs
      adds	x1, x17, x6
      adcs	x17, x2, x3
      cset	w3, hs
      adds	x2, x17, x4
      adc	x12, x12, x3
      mov	x3, #-2
      b	Ldivq63_27
      Ldivq63_67:
      mov	x13, #-1
      ldp	x8, x17, [x11]
      umulh	x11, x8, x13
      neg	x10, x8
      subs	x10, x16, x10
      cinc	x16, x11, lo
      neg	x3, x17
      adds	x11, x16, x3
      subs	x11, x1, x11
      cset	w1, lo
      cmn	x16, x3
      umulh	x16, x17, x13
      adc	x16, x1, x16
      subs	x16, x2, x16
      b.hs	Ldivq63_32
      cmn	x10, x8
      ldr	x8, [x9]
      adcs	x11, x11, x8
      cinc	x16, x16, hs
      mov	x13, #-2
      b	Ldivq63_32
      Ldivq63_69:
      ldr	x4, [x2]
      mov	x1, #-1
      umulh	x5, x4, x1
      neg	x6, x4
      cmp	x16, x6
      cinc	x5, x5, lo
      neg	x6, x10
      adds	x7, x5, x6
      subs	x17, x17, x7
      cset	w7, lo
      cmn	x5, x6
      umulh	x5, x10, x1
      adc	x5, x7, x5
      neg	x6, x8
      adds	x7, x5, x6
      subs	x3, x3, x7
      cset	w7, lo
      cmn	x5, x6
      add	x16, x16, x4
      umulh	x5, x8, x1
      adc	x5, x7, x5
      subs	x14, x14, x5
      b.hs	Ldivq63_15
      adds	x16, x16, x4
      adcs	x17, x17, xzr
      cset	w1, hs
      adds	x17, x17, x10
      adcs	x1, x3, x1
      cset	w4, hs
      adds	x3, x1, x8
      adc	x14, x14, x4
      mov	x1, #-2
      b	Ldivq63_15
    90:
      .short 0x7fd, 0x7f5, 0x7ed, 0x7e5, 0x7dd, 0x7d5, 0x7ce, 0x7c6
      .short 0x7bf, 0x7b7, 0x7b0, 0x7a8, 0x7a1, 0x79a, 0x792, 0x78b
      .short 0x784, 0x77d, 0x776, 0x76f, 0x768, 0x761, 0x75b, 0x754
      .short 0x74d, 0x747, 0x740, 0x739, 0x733, 0x72c, 0x726, 0x720
      .short 0x719, 0x713, 0x70d, 0x707, 0x700, 0x6fa, 0x6f4, 0x6ee
      .short 0x6e8, 0x6e2, 0x6dc, 0x6d6, 0x6d1, 0x6cb, 0x6c5, 0x6bf
      .short 0x6ba, 0x6b4, 0x6ae, 0x6a9, 0x6a3, 0x69e, 0x698, 0x693
      .short 0x68d, 0x688, 0x683, 0x67d, 0x678, 0x673, 0x66e, 0x669
      .short 0x664, 0x65e, 0x659, 0x654, 0x64f, 0x64a, 0x645, 0x640
      .short 0x63c, 0x637, 0x632, 0x62d, 0x628, 0x624, 0x61f, 0x61a
      .short 0x616, 0x611, 0x60c, 0x608, 0x603, 0x5ff, 0x5fa, 0x5f6
      .short 0x5f1, 0x5ed, 0x5e9, 0x5e4, 0x5e0, 0x5dc, 0x5d7, 0x5d3
      .short 0x5cf, 0x5cb, 0x5c6, 0x5c2, 0x5be, 0x5ba, 0x5b6, 0x5b2
      .short 0x5ae, 0x5aa, 0x5a6, 0x5a2, 0x59e, 0x59a, 0x596, 0x592
      .short 0x58e, 0x58a, 0x586, 0x583, 0x57f, 0x57b, 0x577, 0x574
      .short 0x570, 0x56c, 0x568, 0x565, 0x561, 0x55e, 0x55a, 0x556
      .short 0x553, 0x54f, 0x54c, 0x548, 0x545, 0x541, 0x53e, 0x53a
      .short 0x537, 0x534, 0x530, 0x52d, 0x52a, 0x526, 0x523, 0x520
      .short 0x51c, 0x519, 0x516, 0x513, 0x50f, 0x50c, 0x509, 0x506
      .short 0x503, 0x500, 0x4fc, 0x4f9, 0x4f6, 0x4f3, 0x4f0, 0x4ed
      .short 0x4ea, 0x4e7, 0x4e4, 0x4e1, 0x4de, 0x4db, 0x4d8, 0x4d5
      .short 0x4d2, 0x4cf, 0x4cc, 0x4ca, 0x4c7, 0x4c4, 0x4c1, 0x4be
      .short 0x4bb, 0x4b9, 0x4b6, 0x4b3, 0x4b0, 0x4ad, 0x4ab, 0x4a8
      .short 0x4a5, 0x4a3, 0x4a0, 0x49d, 0x49b, 0x498, 0x495, 0x493
      .short 0x490, 0x48d, 0x48b, 0x488, 0x486, 0x483, 0x481, 0x47e
      .short 0x47c, 0x479, 0x477, 0x474, 0x472, 0x46f, 0x46d, 0x46a
      .short 0x468, 0x465, 0x463, 0x461, 0x45e, 0x45c, 0x459, 0x457
      .short 0x455, 0x452, 0x450, 0x44e, 0x44b, 0x449, 0x447, 0x444
      .short 0x442, 0x440, 0x43e, 0x43b, 0x439, 0x437, 0x435, 0x432
      .short 0x430, 0x42e, 0x42c, 0x42a, 0x428, 0x425, 0x423, 0x421
      .short 0x41f, 0x41d, 0x41b, 0x419, 0x417, 0x414, 0x412, 0x410
      .short 0x40e, 0x40c, 0x40a, 0x408, 0x406, 0x404, 0x402, 0x400
    ASM


# Exact AArch64/macOS port of runtime.c's corrected fixed 6-by-3-limb
# remainder leaf.  This is the Clang 22.1.8 -O3 -mcpu=apple-m5 schedule for
# mag_mod_63: the same normalization, Moller--Granlund reciprocal, four
# 3-by-2 quotient digits, saturated/correction arms, and three-limb result.
on macos && arm64
  fn __bigint_mod_63_raw(a, b) (i64 i64) i64
    asm <<~ASM
      .arch_extension cssc
      sub sp, sp, #96
      stp x22, x21, [sp, #64]
      stp x20, x19, [sp, #80]
      and x2, x1, #0x7fffffffffff
      add x2, x2, #16
      and x1, x0, #0x7fffffffffff
      add x1, x1, #16
      mov x11, x2
      ldr x9, [x11, #16]!
      clz x8, x9
      cbz x8, 2f
      lsl x9, x9, x8
      ldp x11, x10, [x2]
      lsr x12, x10, #1
      mvn w13, w8
      lsr x12, x12, x13
      orr x9, x9, x12
      lsl x10, x10, x8
      lsr x12, x11, #1
      lsr x12, x12, x13
      orr x10, x10, x12
      neg x12, x8
      ldp x16, x15, [x1, #32]
      lsr x14, x15, x12
      lsl x12, x15, x8
      lsr x15, x16, #1
      lsr x15, x15, x13
      orr x17, x12, x15
      lsl x12, x16, x8
      ldp x2, x16, [x1, #16]
      lsr x15, x16, #1
      lsr x15, x15, x13
      orr x15, x12, x15
      mov w12, #64
      sub x4, x12, x8
      stp x9, x10, [sp]
      lsl x12, x11, x8
      str x12, [sp, #16]
      ldur q0, [x1, #8]
      lsl x11, x16, x8
      lsr x16, x2, #1
      lsr x13, x16, x13
      orr x3, x11, x13
      ldr q1, [x1]
      ldr x11, [x1]
      dup.2d v2, x8
      ushl.2d v0, v0, v2
      dup.2d v2, x4
      neg.2d v2, v2
      ushl.2d v1, v1, v2
      orr.16b v0, v1, v0
      lsl x16, x11, x8
      add x2, sp, #16
      add x13, sp, #8
      mov x11, sp
      b 3f
    2:
      mov x14, #0
      sub x13, x11, #8
      ldp x15, x17, [x1, #32]
      ldr x3, [x1, #24]
      ldur q0, [x1, #8]
      ldr x16, [x1]
      ldp x12, x10, [x2]
    3:
      stp x3, x15, [sp, #48]
      stur q0, [sp, #32]
      str x16, [sp, #24]
      lsr x16, x9, #55
      adr x1, 90f
      add x16, x1, x16, lsl #1
      sub x16, x16, #512
      ldrh w16, [x16]
      lsr x1, x9, #24
      add x1, x1, #1
      mul x4, x1, x16
      mul x4, x4, x16
      mvn x4, x4, lsr #40
      add x16, x4, x16, lsl #11
      mov x4, #1152921504606846976
      msub x1, x16, x1, x4
      mul x1, x1, x16
      lsr x1, x1, #47
      add x16, x1, x16, lsl #13
      sbfx x1, x9, #0, #1
      and x4, x9, #0x1
      add x4, x4, x9, lsr #1
      and x1, x1, x16, lsr #1
      msub x1, x16, x4, x1
      lsl x4, x16, #31
      umulh x16, x1, x16
      add x16, x4, x16, lsr #1
      adds x1, x16, #1
      cset w4, hs
      umulh x1, x1, x9
      madd x1, x4, x9, x1
      sub x16, x16, x9
      sub x1, x16, x1
      mul x16, x1, x9
      adds x16, x16, x10
      b.lo 5f
      cmp x16, x9
      csel x4, x9, xzr, hs
      cset w5, hs
      mvn x5, x5
      add x1, x5, x1
      sub x16, x16, x9
      sub x16, x16, x4
    5:
      umulh x4, x1, x10
      adds x4, x16, x4
      b.lo 10f
      sub x16, x1, #1
      cmp x4, x9
      b.lo 8f
      mul x5, x1, x10
      sub x1, x1, #2
      cmp x4, x9
      ccmp x10, x5, #0, ls
      csel x16, x16, x1, hi
    8:
      cbz x14, 11f
    9:
      mov w1, #3
      mov x15, x17
      b 18f
    10:
      mov x16, x1
      cbnz x14, 9b
    11:
      cmp x17, x9
      b.hi 14f
      mov w1, #2
      b.ne 17f
      cmp x15, x10
      b.lo 17f
    14:
      subs x14, x3, x12
      cset w1, lo
      str x14, [sp, #48]
      adds x14, x10, x1
      cset w1, hs
      subs x4, x15, x14
      csinc w14, w1, wzr, hs
      adds x14, x9, x14
      b.hs 33f
      subs x14, x17, x14
      b.lo 33f
      mov w1, #2
      mov x15, x4
      b 18f
    17:
      mov x14, x17
    18:
      add x17, sp, #24
      mov x3, #-1
    19:
      add x4, x17, x1, lsl #3
      ldr x4, [x4, #8]
      cmp x14, x9
      b.lo 22f
      b.hi 27f
      cmp x15, x10
      b.hs 27f
    22:
      umulh x5, x14, x16
      mul x6, x14, x16
      adds x6, x15, x6
      adc x14, x14, x5
      msub x15, x9, x14, x15
      umulh x5, x14, x10
      mul x7, x14, x10
      adds x7, x7, x10
      adc x5, x5, x9
      negs x7, x7
      sbc x15, x15, x5
      adds x5, x7, x4
      cinc x7, x15, hs
      cmp x7, x6
      csel x6, x9, xzr, hs
      cset w15, hs
      csel x19, x10, xzr, hs
      sub x14, x14, x15
      add x4, x14, #1
      adds x15, x5, x19
      adc x14, x6, x7
      cmp x15, x10
      sbcs xzr, x14, x9
      b.hs 25f
    23:
      mul x5, x4, x12
      ldr x6, [x17, x1, lsl #3]
      subs x5, x6, x5
      str x5, [x17, x1, lsl #3]
      umulh x4, x4, x12
      cinc x4, x4, lo
      subs x15, x15, x4
      cset w4, lo
      subs x14, x14, x4
      b.lo 26f
    24:
      cmp x1, #0
      sub x1, x1, #1
      b.gt 19b
      b 28f
    25:
      add x4, x4, #1
      subs x15, x15, x10
      sbc x14, x14, x9
      b 23b
    26:
      adds x4, x5, x12
      str x4, [x17, x1, lsl #3]
      adcs x15, x10, x15
      adc x14, x14, x9
      b 24b
    27:
      ldr x5, [x17, x1, lsl #3]
      ldr x6, [x2]
      umulh x7, x6, x3
      neg x19, x6
      cmp x5, x19
      cinc x7, x7, lo
      ldr x19, [x13]
      neg x20, x19
      adds x21, x7, x20
      subs x4, x4, x21
      cset w21, lo
      cmn x7, x20
      umulh x7, x19, x3
      adc x7, x21, x7
      ldr x20, [x11]
      neg x21, x20
      adds x22, x7, x21
      subs x15, x15, x22
      cset w22, lo
      cmn x7, x21
      umulh x7, x20, x3
      adc x7, x22, x7
      add x5, x5, x6
      adds x6, x5, x6
      adcs x19, x4, x19
      adc x20, x20, x15
      cmp x14, x7
      csel x14, x15, x20, hs
      csel x15, x4, x19, hs
      csel x4, x5, x6, hs
      str x4, [x17, x1, lsl #3]
      b 24b
    28:
      ldr x9, [sp, #24]
      lsr x10, x9, x8
      lsl x11, x15, #1
      mvn w12, w8
      lsl x11, x11, x12
      orr x10, x11, x10
      lsr x11, x15, x8
      lsl x13, x14, #1
      lsl x12, x13, x12
      orr x11, x12, x11
      lsr x12, x14, x8
      cmp x8, #0
      csel x8, x9, x10, eq
      csel x9, x15, x11, eq
      csel x10, x14, x12, eq
      mov w3, #3
      cbnz x10, 30f
      mov w3, #2
      cbnz x9, 30f
      umin x3, x8, #1
    30:
      mov x0, x8
      mov x1, x9
      mov x2, x10
      ldp x20, x19, [sp, #80]
      ldp x22, x21, [sp, #64]
      add sp, sp, #96
      b _w_bigint_mod63_finish_raw
    33:
      str x3, [sp, #48]
      mov w1, #2
      mov x14, x17
      b 18b
      .p2align 1
    90:
      .short 0x7fd, 0x7f5, 0x7ed, 0x7e5, 0x7dd, 0x7d5, 0x7ce, 0x7c6
      .short 0x7bf, 0x7b7, 0x7b0, 0x7a8, 0x7a1, 0x79a, 0x792, 0x78b
      .short 0x784, 0x77d, 0x776, 0x76f, 0x768, 0x761, 0x75b, 0x754
      .short 0x74d, 0x747, 0x740, 0x739, 0x733, 0x72c, 0x726, 0x720
      .short 0x719, 0x713, 0x70d, 0x707, 0x700, 0x6fa, 0x6f4, 0x6ee
      .short 0x6e8, 0x6e2, 0x6dc, 0x6d6, 0x6d1, 0x6cb, 0x6c5, 0x6bf
      .short 0x6ba, 0x6b4, 0x6ae, 0x6a9, 0x6a3, 0x69e, 0x698, 0x693
      .short 0x68d, 0x688, 0x683, 0x67d, 0x678, 0x673, 0x66e, 0x669
      .short 0x664, 0x65e, 0x659, 0x654, 0x64f, 0x64a, 0x645, 0x640
      .short 0x63c, 0x637, 0x632, 0x62d, 0x628, 0x624, 0x61f, 0x61a
      .short 0x616, 0x611, 0x60c, 0x608, 0x603, 0x5ff, 0x5fa, 0x5f6
      .short 0x5f1, 0x5ed, 0x5e9, 0x5e4, 0x5e0, 0x5dc, 0x5d7, 0x5d3
      .short 0x5cf, 0x5cb, 0x5c6, 0x5c2, 0x5be, 0x5ba, 0x5b6, 0x5b2
      .short 0x5ae, 0x5aa, 0x5a6, 0x5a2, 0x59e, 0x59a, 0x596, 0x592
      .short 0x58e, 0x58a, 0x586, 0x583, 0x57f, 0x57b, 0x577, 0x574
      .short 0x570, 0x56c, 0x568, 0x565, 0x561, 0x55e, 0x55a, 0x556
      .short 0x553, 0x54f, 0x54c, 0x548, 0x545, 0x541, 0x53e, 0x53a
      .short 0x537, 0x534, 0x530, 0x52d, 0x52a, 0x526, 0x523, 0x520
      .short 0x51c, 0x519, 0x516, 0x513, 0x50f, 0x50c, 0x509, 0x506
      .short 0x503, 0x500, 0x4fc, 0x4f9, 0x4f6, 0x4f3, 0x4f0, 0x4ed
      .short 0x4ea, 0x4e7, 0x4e4, 0x4e1, 0x4de, 0x4db, 0x4d8, 0x4d5
      .short 0x4d2, 0x4cf, 0x4cc, 0x4ca, 0x4c7, 0x4c4, 0x4c1, 0x4be
      .short 0x4bb, 0x4b9, 0x4b6, 0x4b3, 0x4b0, 0x4ad, 0x4ab, 0x4a8
      .short 0x4a5, 0x4a3, 0x4a0, 0x49d, 0x49b, 0x498, 0x495, 0x493
      .short 0x490, 0x48d, 0x48b, 0x488, 0x486, 0x483, 0x481, 0x47e
      .short 0x47c, 0x479, 0x477, 0x474, 0x472, 0x46f, 0x46d, 0x46a
      .short 0x468, 0x465, 0x463, 0x461, 0x45e, 0x45c, 0x459, 0x457
      .short 0x455, 0x452, 0x450, 0x44e, 0x44b, 0x449, 0x447, 0x444
      .short 0x442, 0x440, 0x43e, 0x43b, 0x439, 0x437, 0x435, 0x432
      .short 0x430, 0x42e, 0x42c, 0x42a, 0x428, 0x425, 0x423, 0x421
      .short 0x41f, 0x41d, 0x41b, 0x419, 0x417, 0x414, 0x412, 0x410
      .short 0x40e, 0x40c, 0x40a, 0x408, 0x406, 0x404, 0x402, 0x400
    ASM

# Exact arithmetic/certificate body for the 8-by-4 specialization of
# mag_div_q_triangular_certified. This is the Clang 22.1.8
# -O3 -mcpu=apple-m5 schedule for the existing C algorithm after only
# splitting its capacity-five allocation/finalization into the source wrapper.
# It preserves the five quotient digits, lazy-low rows, saturated estimates,
# add-backs, and the sufficient triangular certificate.
on macos && arm64
  fn __bigint_div_84_exact(rp, up, vp) (i64 i64 i64) i64
    asm <<~ASM
      .arch_extension cssc
      sub	sp, sp, #208
      stp	x28, x27, [sp, #112]
      stp	x26, x25, [sp, #128]
      stp	x24, x23, [sp, #144]
      stp	x22, x21, [sp, #160]
      stp	x20, x19, [sp, #176]
      stp	x29, x30, [sp, #192]
      add	x29, sp, #192
      mov	x22, x2
      mov	x19, x0
      mov	x23, x2
      ldr	x24, [x23, #24]!
      clz	x10, x24
      sub	x21, x23, #16
      sub	x20, x23, #8
      lsl	x8, x24, x10
      cbz	x10, Ldivq84_2
      ldr	x9, [x20]
      lsr	x11, x9, #1
      mvn	w12, w10
      lsr	x11, x11, x12
      orr	x24, x8, x11
      ldr	x11, [x21]
      lsl	x13, x9, x10
      lsr	x11, x11, #1
      lsr	x11, x11, x12
      orr	x25, x13, x11
      b	Ldivq84_3
      Ldivq84_2:
      ldr	x9, [x20]
      mov	x25, x9
      Ldivq84_3:
      lsr	x11, x24, #55
      adr	x12, 90f
      add	x11, x12, x11, lsl #1
      sub	x11, x11, #512
      ldrh	w11, [x11]
      lsr	x12, x24, #24
      add	x12, x12, #1
      mul	x13, x12, x11
      mul	x13, x13, x11
      mvn	x13, x13, lsr #40
      add	x11, x13, x11, lsl #11
      mov	x13, #1152921504606846976
      msub	x12, x11, x12, x13
      mul	x12, x12, x11
      lsr	x12, x12, #47
      add	x11, x12, x11, lsl #13
      sbfx	x12, x24, #0, #1
      and	x13, x24, #0x1
      add	x13, x13, x24, lsr #1
      and	x12, x12, x11, lsr #1
      msub	x12, x11, x13, x12
      lsl	x13, x11, #31
      umulh	x11, x12, x11
      add	x11, x13, x11, lsr #1
      adds	x12, x11, #1
      cset	w13, hs
      umulh	x12, x12, x24
      madd	x12, x13, x24, x12
      sub	x11, x11, x24
      sub	x11, x11, x12
      mul	x12, x11, x24
      adds	x12, x12, x25
      b.lo	Ldivq84_5
      cmp	x12, x24
      csel	x13, x24, xzr, hs
      cset	w14, hs
      mvn	x14, x14
      add	x11, x14, x11
      sub	x12, x12, x24
      sub	x12, x12, x13
      Ldivq84_5:
      umulh	x13, x11, x25
      adds	x12, x12, x13
      b.lo	Ldivq84_16
      sub	x26, x11, #1
      cmp	x12, x24
      b.lo	Ldivq84_8
      mul	x13, x11, x25
      sub	x11, x11, #2
      cmp	x12, x24
      ccmp	x25, x13, #0, ls
      csel	x26, x26, x11, hi
      Ldivq84_8:
      cbz	x10, Ldivq84_17
      Ldivq84_9:
      add	x11, sp, #8
      add	x23, x11, #24
      add	x21, x11, #8
      add	x20, x11, #16
      lsr	x11, x9, #1
      mvn	w12, w10
      lsr	x11, x11, x12
      orr	x8, x8, x11
      lsl	x9, x9, x10
      ldp	x13, x11, [x22]
      lsr	x14, x11, #1
      lsr	x14, x14, x12
      orr	x9, x9, x14
      stp	x9, x8, [sp, #24]
      lsl	x8, x11, x10
      lsr	x9, x13, #1
      lsr	x9, x9, x12
      orr	x8, x8, x9
      lsl	x9, x13, x10
      stp	x9, x8, [sp, #8]
      ldr	x8, [x1, #56]
      neg	x9, x10
      lsr	x11, x8, x9
      lsl	x8, x8, x10
      ldp	x13, x9, [x1, #40]
      lsr	x14, x9, #1
      lsr	x14, x14, x12
      orr	x8, x8, x14
      mov	w14, #64
      sub	x14, x14, x10
      stp	x8, x11, [sp, #96]
      ldp	q0, q1, [x1, #16]
      lsl	x9, x9, x10
      lsr	x13, x13, #1
      lsr	x12, x13, x12
      orr	x9, x9, x12
      str	x9, [sp, #88]
      ldur	q2, [x1, #24]
      dup.2d	v3, x10
      ushl.2d	v1, v1, v3
      dup.2d	v4, x14
      neg.2d	v4, v4
      ushl.2d	v2, v2, v4
      orr.16b	v1, v2, v1
      ldur	q2, [x1, #8]
      ushl.2d	v0, v0, v3
      ushl.2d	v2, v2, v4
      orr.16b	v0, v2, v0
      stur	q1, [sp, #72]
      stur	q0, [sp, #56]
      cbz	x11, Ldivq84_18
      cmp	x11, x24
      b.lo	Ldivq84_13
      b.hi	Ldivq84_24
      cmp	x8, x25
      b.hs	Ldivq84_24
      Ldivq84_13:
      umulh	x10, x11, x26
      mul	x12, x11, x26
      adds	x12, x8, x12
      adc	x10, x11, x10
      msub	x8, x24, x10, x8
      umulh	x11, x10, x25
      mul	x13, x10, x25
      adds	x13, x25, x13
      adc	x11, x24, x11
      subs	x9, x9, x13
      ngc	x11, x11
      add	x8, x11, x8
      cmp	x8, x12
      cset	w11, hs
      csel	x12, x24, xzr, hs
      csel	x13, x25, xzr, hs
      sub	x10, x10, x11
      add	x10, x10, #1
      adds	x9, x9, x13
      adc	x8, x12, x8
      cmp	x9, x25
      sbcs	xzr, x8, x24
      b.hs	Ldivq84_69
      Ldivq84_14:
      ldp	x11, x12, [sp, #8]
      umulh	x14, x11, x10
      mul	x13, x11, x10
      ldp	x15, x16, [sp, #72]
      subs	x13, x15, x13
      cinc	x15, x14, lo
      mul	x17, x12, x10
      adds	x14, x15, x17
      subs	x14, x16, x14
      cset	w16, lo
      cmn	x15, x17
      stp	x13, x14, [sp, #72]
      umulh	x15, x12, x10
      adc	x15, x16, x15
      subs	x9, x9, x15
      cset	w15, lo
      subs	x8, x8, x15
      b.hs	Ldivq84_26
      sub	x10, x10, #1
      adds	x11, x13, x11
      adcs	x12, x14, x12
      stp	x11, x12, [sp, #72]
      adcs	x9, x9, x25
      adc	x8, x8, x24
      b	Ldivq84_26
      Ldivq84_16:
      mov	x26, x11
      cbnz	x10, Ldivq84_9
      Ldivq84_17:
      ldp	q1, q0, [x1, #32]
      stur	q0, [sp, #88]
      ldr	q0, [x1, #16]
      stur	q0, [sp, #56]
      stur	q1, [sp, #72]
      str	xzr, [sp, #104]
      ldp	x9, x8, [sp, #88]
      cmp	x8, x24
      b.ls	Ldivq84_19
      b	Ldivq84_21
      Ldivq84_18:
      add	x22, sp, #8
      cmp	x8, x24
      b.hi	Ldivq84_21
      Ldivq84_19:
      mov	x10, #0
      b.ne	Ldivq84_27
      cmp	x9, x25
      b.lo	Ldivq84_27
      Ldivq84_21:
      ldr	x12, [x22]
      ldp	x11, x10, [sp, #72]
      subs	x15, x11, x12
      cset	w14, lo
      ldr	x13, [x21]
      adds	x14, x13, x14
      cset	w16, hs
      subs	x14, x10, x14
      stp	x15, x14, [sp, #72]
      csinc	w10, w16, wzr, hs
      adds	x10, x25, x10
      cinc	x15, x24, hs
      cmp	x9, x10
      sbcs	xzr, x8, x15
      b.hs	Ldivq84_23
      mov	x10, #0
      cmp	x11, x12
      cinc	x12, x14, lo
      add	x12, x12, x13
      stp	x11, x12, [sp, #72]
      str	x10, [x19, #32]
      ldr	x10, [sp, #80]
      cmp	x8, x24
      b.hs	Ldivq84_28
      b	Ldivq84_30
      Ldivq84_23:
      subs	x9, x9, x10
      sbc	x8, x8, x15
      mov	w10, #1
      str	x10, [x19, #32]
      ldr	x10, [sp, #80]
      cmp	x8, x24
      b.hs	Ldivq84_28
      b	Ldivq84_30
      Ldivq84_24:
      add	x9, sp, #40
      stp	x8, x11, [sp, #96]
      add	x0, x9, #32
      add	x1, sp, #8
      mov	w2, #4
      mov	x3, #-1
      bl	_bn_submul_1
      ldr	x8, [sp, #104]
      subs	x10, x8, x0
      str	x10, [sp, #104]
      b.hs	Ldivq84_64
      ldp	x8, x9, [sp, #72]
      ldp	x11, x12, [sp, #8]
      adds	x8, x8, x11
      adcs	x9, x9, xzr
      cset	w11, hs
      adds	x9, x9, x12
      stp	x8, x9, [sp, #72]
      ldp	x8, x12, [sp, #88]
      adcs	x8, x8, x11
      cset	w11, hs
      ldp	x9, x13, [sp, #24]
      adds	x9, x8, x9
      adcs	x8, x12, x11
      cset	w11, hs
      adds	x8, x8, x13
      stp	x9, x8, [sp, #88]
      adc	x10, x10, x11
      str	x10, [sp, #104]
      mov	x10, #-2
      Ldivq84_26:
      add	x22, sp, #8
      Ldivq84_27:
      str	x10, [x19, #32]
      ldr	x10, [sp, #80]
      cmp	x8, x24
      b.lo	Ldivq84_30
      Ldivq84_28:
      b.hi	Ldivq84_33
      cmp	x9, x25
      b.hs	Ldivq84_33
      Ldivq84_30:
      umulh	x11, x8, x26
      mul	x12, x8, x26
      adds	x12, x9, x12
      adc	x8, x8, x11
      msub	x9, x24, x8, x9
      umulh	x11, x8, x25
      mul	x13, x8, x25
      adds	x13, x25, x13
      adc	x11, x24, x11
      subs	x10, x10, x13
      ngc	x11, x11
      add	x11, x11, x9
      cmp	x11, x12
      cset	w9, hs
      csel	x12, x24, xzr, hs
      csel	x13, x25, xzr, hs
      sub	x8, x8, x9
      add	x9, x8, #1
      adds	x10, x10, x13
      adc	x11, x12, x11
      cmp	x10, x25
      sbcs	xzr, x11, x24
      b.hs	Ldivq84_65
      Ldivq84_31:
      ldr	x12, [x22]
      umulh	x8, x12, x9
      mul	x13, x12, x9
      ldp	x14, x15, [sp, #64]
      subs	x13, x14, x13
      str	x13, [sp, #64]
      cinc	x16, x8, lo
      ldr	x14, [x21]
      mul	x17, x14, x9
      adds	x8, x16, x17
      subs	x8, x15, x8
      cset	w15, lo
      cmn	x16, x17
      umulh	x16, x14, x9
      str	x8, [sp, #72]
      adc	x15, x15, x16
      subs	x10, x10, x15
      cset	w15, lo
      subs	x11, x11, x15
      b.hs	Ldivq84_35
      sub	x9, x9, #1
      adds	x12, x13, x12
      adcs	x8, x8, x14
      stp	x12, x8, [sp, #64]
      adcs	x10, x10, x25
      adc	x11, x11, x24
      str	x9, [x19, #24]
      add	x27, sp, #40
      cmp	x11, x24
      b.hs	Ldivq84_36
      b	Ldivq84_38
      Ldivq84_33:
      add	x10, sp, #40
      stp	x9, x8, [sp, #88]
      add	x0, x10, #24
      mov	x1, x22
      mov	w2, #4
      mov	x3, #-1
      bl	_bn_submul_1
      ldr	x8, [sp, #96]
      subs	x9, x8, x0
      str	x9, [sp, #96]
      b.hs	Ldivq84_62
      ldr	x8, [x22]
      ldp	x10, x11, [sp, #64]
      adds	x8, x10, x8
      str	x8, [sp, #64]
      ldr	x8, [x21]
      adcs	x10, x11, xzr
      cset	w11, hs
      adds	x8, x10, x8
      str	x8, [sp, #72]
      ldr	x10, [x20]
      ldp	x12, x13, [sp, #80]
      adcs	x11, x12, x11
      cset	w12, hs
      adds	x10, x11, x10
      str	x10, [sp, #80]
      ldr	x11, [x23]
      adcs	x12, x13, x12
      cset	w13, hs
      adds	x11, x12, x11
      adc	x9, x9, x13
      stp	x11, x9, [sp, #88]
      mov	x9, #-2
      Ldivq84_35:
      str	x9, [x19, #24]
      add	x27, sp, #40
      cmp	x11, x24
      b.lo	Ldivq84_38
      Ldivq84_36:
      b.hi	Ldivq84_41
      cmp	x10, x25
      b.hs	Ldivq84_41
      Ldivq84_38:
      umulh	x9, x11, x26
      mul	x12, x11, x26
      adds	x12, x10, x12
      adc	x9, x11, x9
      msub	x10, x24, x9, x10
      umulh	x11, x9, x25
      mul	x13, x9, x25
      adds	x13, x25, x13
      adc	x11, x24, x11
      subs	x13, x8, x13
      ngc	x8, x11
      add	x11, x8, x10
      cmp	x11, x12
      cset	w8, hs
      csel	x12, x24, xzr, hs
      csel	x10, x25, xzr, hs
      sub	x8, x9, x8
      add	x8, x8, #1
      adds	x10, x13, x10
      adc	x11, x12, x11
      cmp	x10, x25
      sbcs	xzr, x11, x24
      b.hs	Ldivq84_66
      Ldivq84_39:
      ldr	x12, [x22]
      umulh	x9, x12, x8
      mul	x13, x12, x8
      ldp	x14, x15, [sp, #56]
      subs	x13, x14, x13
      str	x13, [sp, #56]
      cinc	x16, x9, lo
      ldr	x14, [x21]
      mul	x17, x14, x8
      adds	x9, x16, x17
      subs	x9, x15, x9
      cset	w15, lo
      cmn	x16, x17
      umulh	x16, x14, x8
      str	x9, [sp, #64]
      adc	x15, x15, x16
      subs	x10, x10, x15
      cset	w15, lo
      subs	x11, x11, x15
      b.hs	Ldivq84_43
      sub	x8, x8, #1
      adds	x12, x13, x12
      adcs	x9, x9, x14
      stp	x12, x9, [sp, #56]
      adcs	x10, x10, x25
      adc	x11, x11, x24
      str	x8, [x19, #16]
      cmp	x11, x24
      b.hs	Ldivq84_44
      b	Ldivq84_46
      Ldivq84_41:
      stp	x10, x11, [sp, #80]
      add	x0, x27, #16
      mov	x1, x22
      mov	w2, #4
      mov	x3, #-1
      bl	_bn_submul_1
      ldr	x8, [sp, #88]
      subs	x8, x8, x0
      str	x8, [sp, #88]
      b.hs	Ldivq84_63
      ldr	x9, [x22]
      ldp	x10, x11, [sp, #56]
      adds	x9, x10, x9
      str	x9, [sp, #56]
      ldr	x9, [x21]
      adcs	x10, x11, xzr
      cset	w11, hs
      adds	x9, x10, x9
      str	x9, [sp, #64]
      ldr	x10, [x20]
      ldp	x12, x13, [sp, #72]
      adcs	x11, x12, x11
      cset	w12, hs
      adds	x10, x11, x10
      str	x10, [sp, #72]
      ldr	x11, [x23]
      adcs	x12, x13, x12
      cset	w13, hs
      adds	x11, x12, x11
      adc	x8, x8, x13
      stp	x11, x8, [sp, #80]
      mov	x8, #-2
      Ldivq84_43:
      str	x8, [x19, #16]
      cmp	x11, x24
      b.lo	Ldivq84_46
      Ldivq84_44:
      b.hi	Ldivq84_49
      cmp	x10, x25
      b.hs	Ldivq84_49
      Ldivq84_46:
      umulh	x8, x11, x26
      mul	x12, x11, x26
      adds	x12, x10, x12
      adc	x8, x11, x8
      msub	x10, x24, x8, x10
      umulh	x11, x8, x25
      mul	x13, x8, x25
      adds	x13, x13, x25
      adc	x11, x11, x24
      subs	x9, x9, x13
      ngc	x11, x11
      add	x10, x11, x10
      cmp	x10, x12
      cset	w11, hs
      csel	x12, x24, xzr, hs
      csel	x13, x25, xzr, hs
      sub	x8, x8, x11
      add	x22, x8, #1
      adds	x9, x9, x13
      adc	x10, x12, x10
      cmp	x9, x25
      sbcs	xzr, x10, x24
      b.hs	Ldivq84_67
      Ldivq84_47:
      ldr	x11, [x21]
      mul	x8, x11, x22
      ldr	x12, [sp, #56]
      subs	x8, x12, x8
      str	x8, [sp, #56]
      umulh	x12, x11, x22
      cinc	x12, x12, lo
      subs	x9, x9, x12
      cset	w12, lo
      subs	x10, x10, x12
      b.hs	Ldivq84_51
      sub	x22, x22, #1
      adds	x8, x8, x11
      str	x8, [sp, #56]
      adcs	x9, x25, x9
      adc	x10, x10, x24
      b	Ldivq84_51
      Ldivq84_49:
      stp	x10, x11, [sp, #72]
      mov	x22, #-1
      add	x0, x27, #16
      mov	x1, x21
      mov	w2, #3
      mov	x3, #-1
      bl	_bn_submul_1
      ldp	x10, x11, [sp, #72]
      ldp	x8, x9, [sp, #56]
      subs	x11, x11, x0
      str	x11, [sp, #80]
      b.hs	Ldivq84_51
      ldr	x12, [x21]
      adds	x8, x8, x12
      str	x8, [sp, #56]
      ldr	x12, [x21, #8]
      adcs	x9, x9, xzr
      cset	w13, hs
      adds	x9, x9, x12
      str	x9, [sp, #64]
      ldr	x12, [x21, #16]
      adcs	x10, x10, x13
      cset	w13, hs
      adds	x10, x10, x12
      adc	x11, x11, x13
      stp	x10, x11, [sp, #72]
      mov	x22, #-2
      Ldivq84_51:
      str	x22, [x19, #8]
      cmp	x10, x24
      b.lo	Ldivq84_54
      b.hi	Ldivq84_60
      cmp	x9, x25
      b.hs	Ldivq84_60
      Ldivq84_54:
      umulh	x11, x26, x10
      mul	x12, x26, x10
      adds	x12, x12, x9
      adc	x10, x11, x10
      msub	x9, x24, x10, x9
      umulh	x11, x10, x25
      mul	x13, x10, x25
      adds	x13, x13, x25
      adc	x11, x11, x24
      subs	x8, x8, x13
      ngc	x11, x11
      add	x11, x11, x9
      cmp	x11, x12
      cset	w9, hs
      csel	x12, x24, xzr, hs
      csel	x13, x25, xzr, hs
      sub	x9, x10, x9
      add	x21, x9, #1
      adds	x9, x8, x13
      adc	x8, x12, x11
      cmp	x9, x25
      sbcs	xzr, x8, x24
      b.hs	Ldivq84_68
      Ldivq84_55:
      str	x21, [x19]
      stp	x9, x8, [sp, #56]
      cmp	x8, #2
      b.lo	Ldivq84_58
      ldr	x9, [x23]
      cmp	x8, x9
      b.hs	Ldivq84_58
      ldr	x8, [x19, #32]
      cmp	x8, #0
      mov	w8, #4
      cinc	x0, x8, ne
      b	Ldivq84_59
      Ldivq84_58:
      mov	x0, #-1
      Ldivq84_59:
      ldp	x29, x30, [sp, #192]
      ldp	x20, x19, [sp, #176]
      ldp	x22, x21, [sp, #160]
      ldp	x24, x23, [sp, #144]
      ldp	x26, x25, [sp, #128]
      ldp	x28, x27, [sp, #112]
      add	sp, sp, #208
      ret
      Ldivq84_60:
      stp	x9, x10, [sp, #64]
      mov	x21, #-1
      add	x0, x27, #16
      mov	x1, x20
      mov	w2, #2
      mov	x3, #-1
      bl	_bn_submul_1
      ldp	x8, x10, [sp, #64]
      ldr	x9, [sp, #56]
      subs	x10, x10, x0
      str	x10, [sp, #72]
      b.hs	Ldivq84_55
      ldr	x11, [x20]
      adds	x9, x9, x11
      str	x9, [sp, #56]
      ldr	x11, [x20, #8]
      adcs	x8, x8, x11
      cinc	x10, x10, hs
      str	x10, [sp, #72]
      mov	x21, #-2
      b	Ldivq84_55
      Ldivq84_62:
      ldp	x10, x11, [sp, #80]
      mov	x9, #-1
      ldr	x8, [sp, #72]
      str	x9, [x19, #24]
      add	x27, sp, #40
      cmp	x11, x24
      b.hs	Ldivq84_36
      b	Ldivq84_38
      Ldivq84_63:
      ldp	x10, x11, [sp, #72]
      mov	x8, #-1
      ldr	x9, [sp, #64]
      str	x8, [x19, #16]
      cmp	x11, x24
      b.hs	Ldivq84_44
      b	Ldivq84_46
      Ldivq84_64:
      mov	x10, #-1
      add	x22, sp, #8
      ldp	x9, x8, [sp, #88]
      str	x10, [x19, #32]
      ldr	x10, [sp, #80]
      cmp	x8, x24
      b.hs	Ldivq84_28
      b	Ldivq84_30
      Ldivq84_65:
      add	x9, x9, #1
      subs	x10, x10, x25
      sbc	x11, x11, x24
      b	Ldivq84_31
      Ldivq84_66:
      add	x8, x8, #1
      subs	x10, x10, x25
      sbc	x11, x11, x24
      b	Ldivq84_39
      Ldivq84_67:
      add	x22, x22, #1
      subs	x9, x9, x25
      sbc	x10, x10, x24
      b	Ldivq84_47
      Ldivq84_68:
      add	x21, x21, #1
      subs	x9, x9, x25
      sbc	x8, x8, x24
      b	Ldivq84_55
      Ldivq84_69:
      add	x10, x10, #1
      subs	x9, x9, x25
      sbc	x8, x8, x24
      b	Ldivq84_14
      .p2align 1
    90:
      .short 0x7fd, 0x7f5, 0x7ed, 0x7e5, 0x7dd, 0x7d5, 0x7ce, 0x7c6
      .short 0x7bf, 0x7b7, 0x7b0, 0x7a8, 0x7a1, 0x79a, 0x792, 0x78b
      .short 0x784, 0x77d, 0x776, 0x76f, 0x768, 0x761, 0x75b, 0x754
      .short 0x74d, 0x747, 0x740, 0x739, 0x733, 0x72c, 0x726, 0x720
      .short 0x719, 0x713, 0x70d, 0x707, 0x700, 0x6fa, 0x6f4, 0x6ee
      .short 0x6e8, 0x6e2, 0x6dc, 0x6d6, 0x6d1, 0x6cb, 0x6c5, 0x6bf
      .short 0x6ba, 0x6b4, 0x6ae, 0x6a9, 0x6a3, 0x69e, 0x698, 0x693
      .short 0x68d, 0x688, 0x683, 0x67d, 0x678, 0x673, 0x66e, 0x669
      .short 0x664, 0x65e, 0x659, 0x654, 0x64f, 0x64a, 0x645, 0x640
      .short 0x63c, 0x637, 0x632, 0x62d, 0x628, 0x624, 0x61f, 0x61a
      .short 0x616, 0x611, 0x60c, 0x608, 0x603, 0x5ff, 0x5fa, 0x5f6
      .short 0x5f1, 0x5ed, 0x5e9, 0x5e4, 0x5e0, 0x5dc, 0x5d7, 0x5d3
      .short 0x5cf, 0x5cb, 0x5c6, 0x5c2, 0x5be, 0x5ba, 0x5b6, 0x5b2
      .short 0x5ae, 0x5aa, 0x5a6, 0x5a2, 0x59e, 0x59a, 0x596, 0x592
      .short 0x58e, 0x58a, 0x586, 0x583, 0x57f, 0x57b, 0x577, 0x574
      .short 0x570, 0x56c, 0x568, 0x565, 0x561, 0x55e, 0x55a, 0x556
      .short 0x553, 0x54f, 0x54c, 0x548, 0x545, 0x541, 0x53e, 0x53a
      .short 0x537, 0x534, 0x530, 0x52d, 0x52a, 0x526, 0x523, 0x520
      .short 0x51c, 0x519, 0x516, 0x513, 0x50f, 0x50c, 0x509, 0x506
      .short 0x503, 0x500, 0x4fc, 0x4f9, 0x4f6, 0x4f3, 0x4f0, 0x4ed
      .short 0x4ea, 0x4e7, 0x4e4, 0x4e1, 0x4de, 0x4db, 0x4d8, 0x4d5
      .short 0x4d2, 0x4cf, 0x4cc, 0x4ca, 0x4c7, 0x4c4, 0x4c1, 0x4be
      .short 0x4bb, 0x4b9, 0x4b6, 0x4b3, 0x4b0, 0x4ad, 0x4ab, 0x4a8
      .short 0x4a5, 0x4a3, 0x4a0, 0x49d, 0x49b, 0x498, 0x495, 0x493
      .short 0x490, 0x48d, 0x48b, 0x488, 0x486, 0x483, 0x481, 0x47e
      .short 0x47c, 0x479, 0x477, 0x474, 0x472, 0x46f, 0x46d, 0x46a
      .short 0x468, 0x465, 0x463, 0x461, 0x45e, 0x45c, 0x459, 0x457
      .short 0x455, 0x452, 0x450, 0x44e, 0x44b, 0x449, 0x447, 0x444
      .short 0x442, 0x440, 0x43e, 0x43b, 0x439, 0x437, 0x435, 0x432
      .short 0x430, 0x42e, 0x42c, 0x42a, 0x428, 0x425, 0x423, 0x421
      .short 0x41f, 0x41d, 0x41b, 0x419, 0x417, 0x414, 0x412, 0x410
      .short 0x40e, 0x40c, 0x40a, 0x408, 0x406, 0x404, 0x402, 0x400
    ASM

# Exact AArch64/macOS port of runtime.c's corrected fixed 8-by-4-limb
# remainder leaf.  Keep the C schedule intact: normalization, the shared
# two-entry TLS preinverse cache, five Moller--Granlund 3-by-2 digits, the
# saturated/correction arms, and allocation only after the arithmetic.
# The storage tail is the runtime-owned hot-capacity-4 epilogue, matching the
# C caller's bigint_finish_mag_sub policy.
on macos && arm64
  fn __bigint_mod_84_raw(ap, bp) (i64 i64) i64
    asm <<~ASM
      .arch_extension cssc
        sub  sp, sp, #240
        stp  x28, x27, [sp, #144]
        stp  x26, x25, [sp, #160]
        stp  x24, x23, [sp, #176]
        stp  x22, x21, [sp, #192]
        stp  x20, x19, [sp, #208]
        stp  x29, x30, [sp, #224]
        add  x29, sp, #224
        ldr  x21, [x1, #24]
        clz  x20, x21
        cbz  x20, Lmod84_2
        ldp  x8, x9, [x1]
        lsl  x10, x8, x20
        lsl  x11, x9, x20
        lsr  x8, x8, #1
        mvn  w12, w20
        lsr  x8, x8, x12
        orr  x8, x11, x8
        mov  w11, #64
        sub  x11, x11, x20
        stp  x10, x8, [sp, #48]
        ldr  x8, [x1, #16]
        lsl  x10, x8, x20
        lsr  x9, x9, #1
        lsr  x9, x9, x12
        orr  x22, x10, x9
        lsl  x9, x21, x20
        lsr  x8, x8, #1
        lsr  x8, x8, x12
        orr  x21, x9, x8
        stp  x22, x21, [sp, #64]
        ldr  x8, [x0]
        ldr  q0, [x0]
        lsl  x8, x8, x20
        str  x8, [sp, #80]
        dup.2d  v1, x20
        ldur  q2, [x0, #8]
        ushl.2d  v2, v2, v1
        dup.2d  v3, x11
        neg.2d  v3, v3
        ushl.2d  v0, v0, v3
        orr.16b  v0, v2, v0
        stur  q0, [sp, #88]
        ldr  q0, [x0, #16]
        ldur  q2, [x0, #24]
        ushl.2d  v2, v2, v1
        ushl.2d  v0, v0, v3
        orr.16b  v0, v2, v0
        stur  q0, [sp, #104]
        ldr  q0, [x0, #32]
        ldur  q2, [x0, #40]
        ushl.2d  v1, v2, v1
        ushl.2d  v0, v0, v3
        orr.16b  v0, v1, v0
        stur  q0, [sp, #120]
        ldp  x8, x9, [x0, #48]
        lsr  x8, x8, #1
        lsr  x8, x8, x12
        lsl  x10, x9, x20
        orr  x23, x10, x8
        str  x23, [sp, #136]
        neg  x8, x20
        lsr  x19, x9, x8
        add  x1, sp, #48
        b  Lmod84_3
      Lmod84_2:
        mov  x19, #0
        ldp  q0, q1, [x0]
        stp  q0, q1, [sp, #80]
        ldp  q1, q0, [x0, #32]
        stp  q1, q0, [sp, #112]
        ldr  x23, [sp, #136]
        ldr  x22, [x1, #16]
      Lmod84_3:
        adrp  x0, _bn_mod84_native_preinv_cache@TLVPPAGE
        ldr  x0, [x0, _bn_mod84_native_preinv_cache@TLVPPAGEOFF]
        ldr  x8, [x0]
        blr  x8
        mov  x25, x0
        ldp  x9, x10, [x25]
        cmp  x9, x21
        ccmp  x10, x22, #0, eq
        b.eq  Lmod84_7
        ldp  x9, x10, [x25, #24]
        cmp  x9, x21
        ccmp  x10, x22, #0, eq
        b.ne  Lmod84_8
        ldr  x24, [x25, #40]
        b  Lmod84_15
      Lmod84_7:
        ldr  x24, [x25, #16]
        b  Lmod84_15
      Lmod84_8:
        lsr  x9, x21, #55
        adr  x10, 90f
        add  x9, x10, x9, lsl #1
        sub  x9, x9, #512
        ldrh  w9, [x9]
        lsr  x10, x21, #24
        add  x10, x10, #1
        mul  x11, x10, x9
        mul  x11, x11, x9
        mvn  x11, x11, lsr #40
        add  x9, x11, x9, lsl #11
        mov  x11, #1152921504606846976
        msub  x10, x9, x10, x11
        mul  x10, x10, x9
        lsr  x10, x10, #47
        add  x9, x10, x9, lsl #13
        sbfx  x10, x21, #0, #1
        and  x11, x21, #0x1
        add  x11, x11, x21, lsr #1
        and  x10, x10, x9, lsr #1
        msub  x10, x9, x11, x10
        lsl  x11, x9, #31
        umulh  x9, x10, x9
        add  x9, x11, x9, lsr #1
        adds  x10, x9, #1
        cset  w11, hs
        umulh  x10, x10, x21
        madd  x10, x11, x21, x10
        sub  x9, x9, x21
        sub  x9, x9, x10
        mul  x10, x9, x21
        adds  x10, x10, x22
        b.lo  Lmod84_10
        cmp  x10, x21
        csel  x11, x21, xzr, hs
        cset  w12, hs
        mvn  x12, x12
        add  x9, x12, x9
        sub  x10, x10, x21
        sub  x10, x10, x11
      Lmod84_10:
        umulh  x11, x9, x22
        adds  x11, x10, x11
        b.lo  Lmod84_13
        sub  x24, x9, #1
        cmp  x11, x21
        b.lo  Lmod84_14
        mul  x12, x9, x22
        sub  x9, x9, #2
        cmp  x11, x21
        ccmp  x22, x12, #0, ls
        csel  x24, x24, x9, hi
        b  Lmod84_14
      Lmod84_13:
        mov  x24, x9
      Lmod84_14:
        ldrb  w9, [x25, #48]
        add  w11, w9, #1
        strb  w11, [x25, #48]
        and  x9, x9, #1
        add  x9, x9, x9, lsl #1
        add  x9, x25, x9, lsl #3
        stp  x21, x22, [x9]
        str  x24, [x9, #16]
      Lmod84_15:
        mov  x27, #0
        add  x26, sp, #80
        mov  w30, #2
        mov  w28, #4
        mov  x25, #0
      Lmod84_16:
        cmp  x19, x21
        b.lo  Lmod84_19
        b.hi  Lmod84_24
        cmp  x23, x22
        b.hs  Lmod84_24
      Lmod84_19:
        add  x8, x26, x25
        ldr  x9, [x8, #48]
        umulh  x10, x19, x24
        mul  x11, x19, x24
        adds  x11, x23, x11
        adc  x10, x19, x10
        msub  x12, x21, x10, x23
        umulh  x13, x10, x22
        mul  x14, x10, x22
        adds  x14, x14, x22
        adc  x13, x13, x21
        subs  x14, x27, x14
        sbc  x12, x12, x13
        adds  x9, x14, x9
        cinc  x12, x12, hs
        cmp  x12, x11
        csel  x13, x21, x27, hs
        cset  w11, hs
        csel  x14, x22, x27, hs
        sub  x10, x10, x11
        add  x11, x10, #1
        adds  x10, x9, x14
        adc  x9, x13, x12
        cmp  x10, x22
        sbcs  xzr, x9, x21
        b.hs  Lmod84_22
      Lmod84_20:
        add  x16, x8, #32
        ldp  x12, x13, [x1]
        mul  x14, x12, x11
        ldr  x15, [x16]
        umulh  x12, x12, x11
        subs  x14, x15, x14
        cinc  x12, x12, lo
        mul  x15, x13, x11
        adds  x17, x12, x15
        ldr  x0, [x8, #40]
        subs  x17, x0, x17
        cset  w0, lo
        cmn  x12, x15
        str  x14, [x16]
        str  x17, [x8, #40]
        umulh  x8, x13, x11
        adc  x8, x0, x8
        subs  x23, x10, x8
        cset  w8, lo
        subs  x19, x9, x8
        b.lo  Lmod84_23
      Lmod84_21:
        sub  x25, x25, #8
        cmn  x25, #40
        b.ne  Lmod84_16
        b  Lmod84_27
      Lmod84_22:
        add  x11, x11, #1
        subs  x10, x10, x22
        sbc  x9, x9, x21
        b  Lmod84_20
      Lmod84_23:
        mov  x17, x27
        mov  x0, x16
        mov  x2, x1
        cmn  xzr, xzr
        tbz  w30, #0, Lmod84_tmp2
        ldr  x4, [x0], #8
        ldr  x8, [x2], #8
        adcs  x12, x4, x8
        str  x12, [x16], #8
      Lmod84_tmp2:
        tbz  w30, #1, Lmod84_tmp3
        ldp  x4, x5, [x0], #16
        ldp  x8, x9, [x2], #16
        adcs  x12, x4, x8
        adcs  x13, x5, x9
        stp  x12, x13, [x16], #16
      Lmod84_tmp3:
        tbz  w30, #2, Lmod84_tmp4
        ldp  x4, x5, [x0], #32
        ldp  x6, x7, [x0, #-16]
        ldp  x8, x9, [x2], #32
        ldp  x10, x11, [x2, #-16]
        adcs  x12, x4, x8
        adcs  x13, x5, x9
        adcs  x14, x6, x10
        adcs  x15, x7, x11
        stp  x12, x13, [x16], #32
        stp  x14, x15, [x16, #-16]
      Lmod84_tmp4:
        tbz  w30, #3, Lmod84_tmp5
        ldp  x4, x5, [x0], #32
        ldp  x6, x7, [x0, #-16]
        ldp  x8, x9, [x2], #32
        ldp  x10, x11, [x2, #-16]
        adcs  x12, x4, x8
        adcs  x13, x5, x9
        adcs  x14, x6, x10
        adcs  x15, x7, x11
        stp  x12, x13, [x16], #32
        stp  x14, x15, [x16, #-16]
        ldp  x4, x5, [x0], #32
        ldp  x6, x7, [x0, #-16]
        ldp  x8, x9, [x2], #32
        ldp  x10, x11, [x2, #-16]
        adcs  x12, x4, x8
        adcs  x13, x5, x9
        adcs  x14, x6, x10
        adcs  x15, x7, x11
        stp  x12, x13, [x16], #32
        stp  x14, x15, [x16, #-16]
      Lmod84_tmp5:
        cbz  x17, Lmod84_tmp6
      Lmod84_tmp7:
        ldp  x4, x5, [x0], #32
        ldp  x6, x7, [x0, #-16]
        ldp  x8, x9, [x2], #32
        ldp  x10, x11, [x2, #-16]
        adcs  x12, x4, x8
        adcs  x13, x5, x9
        adcs  x14, x6, x10
        adcs  x15, x7, x11
        stp  x12, x13, [x16], #32
        stp  x14, x15, [x16, #-16]
        ldp  x4, x5, [x0], #32
        ldp  x6, x7, [x0, #-16]
        ldp  x8, x9, [x2], #32
        ldp  x10, x11, [x2, #-16]
        adcs  x12, x4, x8
        adcs  x13, x5, x9
        adcs  x14, x6, x10
        adcs  x15, x7, x11
        stp  x12, x13, [x16], #32
        stp  x14, x15, [x16, #-16]
        ldp  x4, x5, [x0], #32
        ldp  x6, x7, [x0, #-16]
        ldp  x8, x9, [x2], #32
        ldp  x10, x11, [x2, #-16]
        adcs  x12, x4, x8
        adcs  x13, x5, x9
        adcs  x14, x6, x10
        adcs  x15, x7, x11
        stp  x12, x13, [x16], #32
        stp  x14, x15, [x16, #-16]
        ldp  x4, x5, [x0], #32
        ldp  x6, x7, [x0, #-16]
        ldp  x8, x9, [x2], #32
        ldp  x10, x11, [x2, #-16]
        adcs  x12, x4, x8
        adcs  x13, x5, x9
        adcs  x14, x6, x10
        adcs  x15, x7, x11
        stp  x12, x13, [x16], #32
        stp  x14, x15, [x16, #-16]
        sub  x17, x17, #1
        cbnz  x17, Lmod84_tmp7
      Lmod84_tmp6:
        cset  x3, hs
        adds  x8, x23, x22
        cset  w9, hs
        adds  x23, x8, x3
        add  x8, x19, x21
        adc  x19, x8, x9
        b  Lmod84_21
      Lmod84_24:
        add  x8, x26, x25
        ldr  q0, [x8, #32]
        str  q0, [sp]
        ldr  x8, [x8, #48]
        stp  x8, x23, [sp, #16]
        str  x19, [sp, #32]
        mov  x0, sp
        mov  x19, x1
        mov  w2, #4
        mov  x3, #-1
        bl  _bn_submul_1
        mov  x1, x19
        ldr  x8, [sp, #32]
        subs  x8, x8, x0
        str  x8, [sp, #32]
        b.hs  Lmod84_26
        mov  x16, sp
        mov  x17, sp
        mov  x0, x1
        mov  x2, x27
        cmn  xzr, xzr
        tbz  w28, #0, Lmod84_tmp8
        ldr  x4, [x17], #8
        ldr  x8, [x0], #8
        adcs  x12, x4, x8
        str  x12, [x16], #8
      Lmod84_tmp8:
        tbz  w28, #1, Lmod84_tmp9
        ldp  x4, x5, [x17], #16
        ldp  x8, x9, [x0], #16
        adcs  x12, x4, x8
        adcs  x13, x5, x9
        stp  x12, x13, [x16], #16
      Lmod84_tmp9:
        tbz  w28, #2, Lmod84_tmp1810
        ldp  x4, x5, [x17], #32
        ldp  x6, x7, [x17, #-16]
        ldp  x8, x9, [x0], #32
        ldp  x10, x11, [x0, #-16]
        adcs  x12, x4, x8
        adcs  x13, x5, x9
        adcs  x14, x6, x10
        adcs  x15, x7, x11
        stp  x12, x13, [x16], #32
        stp  x14, x15, [x16, #-16]
      Lmod84_tmp1810:
        tbz  w28, #3, Lmod84_tmp1811
        ldp  x4, x5, [x17], #32
        ldp  x6, x7, [x17, #-16]
        ldp  x8, x9, [x0], #32
        ldp  x10, x11, [x0, #-16]
        adcs  x12, x4, x8
        adcs  x13, x5, x9
        adcs  x14, x6, x10
        adcs  x15, x7, x11
        stp  x12, x13, [x16], #32
        stp  x14, x15, [x16, #-16]
        ldp  x4, x5, [x17], #32
        ldp  x6, x7, [x17, #-16]
        ldp  x8, x9, [x0], #32
        ldp  x10, x11, [x0, #-16]
        adcs  x12, x4, x8
        adcs  x13, x5, x9
        adcs  x14, x6, x10
        adcs  x15, x7, x11
        stp  x12, x13, [x16], #32
        stp  x14, x15, [x16, #-16]
      Lmod84_tmp1811:
        cbz  x2, Lmod84_tmp1812
      Lmod84_tmp1813:
        ldp  x4, x5, [x17], #32
        ldp  x6, x7, [x17, #-16]
        ldp  x8, x9, [x0], #32
        ldp  x10, x11, [x0, #-16]
        adcs  x12, x4, x8
        adcs  x13, x5, x9
        adcs  x14, x6, x10
        adcs  x15, x7, x11
        stp  x12, x13, [x16], #32
        stp  x14, x15, [x16, #-16]
        ldp  x4, x5, [x17], #32
        ldp  x6, x7, [x17, #-16]
        ldp  x8, x9, [x0], #32
        ldp  x10, x11, [x0, #-16]
        adcs  x12, x4, x8
        adcs  x13, x5, x9
        adcs  x14, x6, x10
        adcs  x15, x7, x11
        stp  x12, x13, [x16], #32
        stp  x14, x15, [x16, #-16]
        ldp  x4, x5, [x17], #32
        ldp  x6, x7, [x17, #-16]
        ldp  x8, x9, [x0], #32
        ldp  x10, x11, [x0, #-16]
        adcs  x12, x4, x8
        adcs  x13, x5, x9
        adcs  x14, x6, x10
        adcs  x15, x7, x11
        stp  x12, x13, [x16], #32
        stp  x14, x15, [x16, #-16]
        ldp  x4, x5, [x17], #32
        ldp  x6, x7, [x17, #-16]
        ldp  x8, x9, [x0], #32
        ldp  x10, x11, [x0, #-16]
        adcs  x12, x4, x8
        adcs  x13, x5, x9
        adcs  x14, x6, x10
        adcs  x15, x7, x11
        stp  x12, x13, [x16], #32
        stp  x14, x15, [x16, #-16]
        sub  x2, x2, #1
        cbnz  x2, Lmod84_tmp1813
      Lmod84_tmp1812:
        cset  x3, hs
        ldr  x8, [sp, #32]
        add  x8, x8, x3
        str  x8, [sp, #32]
      Lmod84_26:
        ldr  q0, [sp]
        add  x8, x26, x25
        str  q0, [x8, #32]
        ldp  x23, x19, [sp, #16]
        mov  w30, #2
        b  Lmod84_21
      Lmod84_27:
        ldr x8, [sp, #80]
        cbz x20, Lmod84_32
      Lmod84_29:
        ldr x9, [sp, #88]
        lsr x8, x8, x20
        lsl x10, x9, #1
        mvn w11, w20
        lsl x10, x10, x11
        orr x8, x10, x8
        lsr x9, x9, x20
        lsl x10, x23, #1
        lsl x10, x10, x11
        orr x9, x10, x9
        lsr x10, x23, x20
        lsl x12, x19, #1
        lsl x11, x12, x11
        orr x23, x11, x10
        lsr x19, x19, x20
        b Lmod84_33
      Lmod84_32:
        ldr x9, [sp, #88]
      Lmod84_33:
        mov x0, x8
        mov x1, x9
        mov x2, x23
        mov x3, x19
        mov w4, #4
        cbnz x3, Lmod84_34
        mov w10, #3
        mov w11, #2
        umin x4, x0, #1
        cmp x1, #0
        csel w4, w11, w4, ne
        cmp x2, #0
        csel w4, w10, w4, ne
      Lmod84_34:
        ldp x29, x30, [sp, #224]
        ldp x20, x19, [sp, #208]
        ldp x22, x21, [sp, #192]
        ldp x24, x23, [sp, #176]
        ldp x26, x25, [sp, #160]
        ldp x28, x27, [sp, #144]
        add sp, sp, #240
        b _w_bigint_mod84_finish_raw
      90:
          .short 0x7fd, 0x7f5, 0x7ed, 0x7e5, 0x7dd, 0x7d5, 0x7ce, 0x7c6
          .short 0x7bf, 0x7b7, 0x7b0, 0x7a8, 0x7a1, 0x79a, 0x792, 0x78b
          .short 0x784, 0x77d, 0x776, 0x76f, 0x768, 0x761, 0x75b, 0x754
          .short 0x74d, 0x747, 0x740, 0x739, 0x733, 0x72c, 0x726, 0x720
          .short 0x719, 0x713, 0x70d, 0x707, 0x700, 0x6fa, 0x6f4, 0x6ee
          .short 0x6e8, 0x6e2, 0x6dc, 0x6d6, 0x6d1, 0x6cb, 0x6c5, 0x6bf
          .short 0x6ba, 0x6b4, 0x6ae, 0x6a9, 0x6a3, 0x69e, 0x698, 0x693
          .short 0x68d, 0x688, 0x683, 0x67d, 0x678, 0x673, 0x66e, 0x669
          .short 0x664, 0x65e, 0x659, 0x654, 0x64f, 0x64a, 0x645, 0x640
          .short 0x63c, 0x637, 0x632, 0x62d, 0x628, 0x624, 0x61f, 0x61a
          .short 0x616, 0x611, 0x60c, 0x608, 0x603, 0x5ff, 0x5fa, 0x5f6
          .short 0x5f1, 0x5ed, 0x5e9, 0x5e4, 0x5e0, 0x5dc, 0x5d7, 0x5d3
          .short 0x5cf, 0x5cb, 0x5c6, 0x5c2, 0x5be, 0x5ba, 0x5b6, 0x5b2
          .short 0x5ae, 0x5aa, 0x5a6, 0x5a2, 0x59e, 0x59a, 0x596, 0x592
          .short 0x58e, 0x58a, 0x586, 0x583, 0x57f, 0x57b, 0x577, 0x574
          .short 0x570, 0x56c, 0x568, 0x565, 0x561, 0x55e, 0x55a, 0x556
          .short 0x553, 0x54f, 0x54c, 0x548, 0x545, 0x541, 0x53e, 0x53a
          .short 0x537, 0x534, 0x530, 0x52d, 0x52a, 0x526, 0x523, 0x520
          .short 0x51c, 0x519, 0x516, 0x513, 0x50f, 0x50c, 0x509, 0x506
          .short 0x503, 0x500, 0x4fc, 0x4f9, 0x4f6, 0x4f3, 0x4f0, 0x4ed
          .short 0x4ea, 0x4e7, 0x4e4, 0x4e1, 0x4de, 0x4db, 0x4d8, 0x4d5
          .short 0x4d2, 0x4cf, 0x4cc, 0x4ca, 0x4c7, 0x4c4, 0x4c1, 0x4be
          .short 0x4bb, 0x4b9, 0x4b6, 0x4b3, 0x4b0, 0x4ad, 0x4ab, 0x4a8
          .short 0x4a5, 0x4a3, 0x4a0, 0x49d, 0x49b, 0x498, 0x495, 0x493
          .short 0x490, 0x48d, 0x48b, 0x488, 0x486, 0x483, 0x481, 0x47e
          .short 0x47c, 0x479, 0x477, 0x474, 0x472, 0x46f, 0x46d, 0x46a
          .short 0x468, 0x465, 0x463, 0x461, 0x45e, 0x45c, 0x459, 0x457
          .short 0x455, 0x452, 0x450, 0x44e, 0x44b, 0x449, 0x447, 0x444
          .short 0x442, 0x440, 0x43e, 0x43b, 0x439, 0x437, 0x435, 0x432
          .short 0x430, 0x42e, 0x42c, 0x42a, 0x428, 0x425, 0x423, 0x421
          .short 0x41f, 0x41d, 0x41b, 0x419, 0x417, 0x414, 0x412, 0x410
          .short 0x40e, 0x40c, 0x40a, 0x408, 0x406, 0x404, 0x402, 0x400
    ASM


# AArch64/macOS ports of runtime.c's positive fixed add-word arms.  Every arm
# was first checkpointed with C's literal schedule.  The seven-limb body then
# earned the same native carry-death split already present at width eight; all
# other bodies remain literal.  The raw finish boundaries retain the C path's
# vanishingly rare grow-after-carry policy instead of changing allocation or
# result construction.
on macos && arm64
  # Exact positive one-limb add pair from bigint_add_one_limb_magnitudes.
  # Pack carry:sum into u128 so the source caller crosses one raw boundary
  # without boxing either machine value.
  fn __bigint_add1_1_sumcarry(a, b) (i64 i64) u128
    ll <<~IR
      ; tungsten:alwaysinline
      entry:
        %amasked = and i64 %a, 140737488355327
        %bmasked = and i64 %b, 140737488355327
        %ap = inttoptr i64 %amasked to ptr
        %bp = inttoptr i64 %bmasked to ptr
        %avp = getelementptr i8, ptr %ap, i64 16
        %bvp = getelementptr i8, ptr %bp, i64 16
        %av = load i64, ptr %avp, align 8
        %bv = load i64, ptr %bvp, align 8
        %sum = add i64 %av, %bv
        %carry = icmp ult i64 %sum, %av
        %sum128 = zext i64 %sum to i128
        %carry128 = zext i1 %carry to i128
        %high = shl i128 %carry128, 64
        %packed = or i128 %high, %sum128
        ret i128 %packed
    IR

  # Exact positive one-limb multiply pair from bigint_mul_positive_11.
  # Pack high:low into u128 so the source caller crosses one raw boundary
  # without boxing either product word.
  fn __bigint_mul1_1_product(a, b) (i64 i64) u128
    ll <<~IR
      ; tungsten:alwaysinline
      entry:
        %amasked = and i64 %a, 140737488355327
        %bmasked = and i64 %b, 140737488355327
        %ap = inttoptr i64 %amasked to ptr
        %bp = inttoptr i64 %bmasked to ptr
        %avp = getelementptr i8, ptr %ap, i64 16
        %bvp = getelementptr i8, ptr %bp, i64 16
        %av = load i64, ptr %avp, align 8
        %bv = load i64, ptr %bvp, align 8
        %av128 = zext i64 %av to i128
        %bv128 = zext i64 %bv to i128
        %product = mul i128 %av128, %bv128
        ret i128 %product
    IR

  # Literal AArch64 schedule emitted for runtime.c's pointer-identical
  # positive two-limb square. Preserve the three partial products, doubled
  # cross term, carry order, four unconditional stores, and +3/+4 header
  # choice exactly; this is the fidelity checkpoint, not a redesign.
  fn __bigint_sqr2_exact(rp, ap) (i64 i64) i64
    ll <<~IR
      ; tungsten:alwaysinline
      entry:
        %size = call i64 asm sideeffect "ldr x8, [${2:x}]\0Aumulh x9, x8, x8\0Amul x8, x8, x8\0Astr x8, [${1:x}]\0Aldp x8, x10, [${2:x}]\0Amul x11, x10, x8\0Aumulh x8, x10, x8\0Alsr x10, x8, #63\0Aextr x8, x8, x11, #63\0Aadds x9, x9, x11, lsl #1\0Astr x9, [${1:x}, #8]\0Aldr x9, [${2:x}, #8]\0Aumulh x11, x9, x9\0Amul x9, x9, x9\0Aadcs x8, x8, x9\0Aadc x9, x10, x11\0Astp x8, x9, [${1:x}, #16]\0Acmp x9, #0\0Amov ${0:x}, #3\0Acinc ${0:x}, ${0:x}, ne", "=r,r,r,~{x8},~{x9},~{x10},~{x11},~{memory},~{cc}"(i64 %rp, i64 %ap)
        ret i64 %size
    IR

  # Literal AArch64 schedule emitted for runtime.c's positive 2-by-1
  # scalar-word arm. Both products issue independently; one flag chain joins
  # high(product0) to low(product1), then the final carry word determines the
  # exact two- or three-limb result size.
  fn __bigint_mul1_2_exact(rp, ap, word) (i64 i64 i64) i64
    ll <<~IR
      ; tungsten:alwaysinline
      entry:
        %size = call i64 asm sideeffect "ldp x4, x5, [${2:x}]\0Amul x6, x4, ${3:x}\0Amul x7, x5, ${3:x}\0Aumulh x4, x4, ${3:x}\0Aadds x4, x7, x4\0Astp x6, x4, [${1:x}]\0Aumulh x5, x5, ${3:x}\0Acinc x5, x5, hs\0Astr x5, [${1:x}, #16]\0Acmp x5, #0\0Amov ${0:x}, #2\0Acinc ${0:x}, ${0:x}, ne", "=r,r,r,r,~{x4},~{x5},~{x6},~{x7},~{memory},~{cc}"(i64 %rp, i64 %ap, i64 %word)
        ret i64 %size
    IR

  # Literal AArch64 schedule emitted for runtime.c's positive 3-by-1
  # bigint_mul_n1_small arm. Preserve its serial product/carry order and
  # unconditional fourth-limb publication; the final carry selects size 3/4.
  fn __bigint_mul1_3_exact(rp, ap, word) (i64 i64 i64) i64
    ll <<~IR
      ; tungsten:alwaysinline
      entry:
        %size = call i64 asm sideeffect "ldr x4, [${2:x}]\0Amul x5, x4, ${3:x}\0Astr x5, [${1:x}]\0Aumulh x4, x4, ${3:x}\0Aldr x5, [${2:x}, #8]\0Aumulh x6, x5, ${3:x}\0Amul x5, x5, ${3:x}\0Aadds x5, x5, x4\0Acinc x4, x6, hs\0Astr x5, [${1:x}, #8]\0Aldr x5, [${2:x}, #16]\0Aumulh x6, x5, ${3:x}\0Amul x5, x5, ${3:x}\0Aadds x5, x5, x4\0Acinc x4, x6, hs\0Astr x5, [${1:x}, #16]\0Astr x4, [${1:x}, #24]\0Acmp x4, #0\0Amov ${0:x}, #3\0Acinc ${0:x}, ${0:x}, ne", "=r,r,r,r,~{x4},~{x5},~{x6},~{memory},~{cc}"(i64 %rp, i64 %ap, i64 %word)
        ret i64 %size
    IR

  # Literal AArch64 schedule emitted for runtime.c's positive 4-by-1
  # bigint_mul_n1_small arm. Preserve its allocation-independent arithmetic,
  # carry order, unconditional fifth-limb publication, and size 4/5 result.
  fn __bigint_mul1_4_exact(rp, ap, word) (i64 i64 i64) i64
    ll <<~IR
      ; tungsten:alwaysinline
      entry:
        %size = call i64 asm sideeffect "ldp x4, x5, [${2:x}]\0Amul x6, x4, ${3:x}\0Amul x7, x5, ${3:x}\0Aumulh x4, x4, ${3:x}\0Aadds x4, x7, x4\0Astp x6, x4, [${1:x}]\0Aldr x4, [${2:x}, #16]\0Aumulh x6, x4, ${3:x}\0Amul x4, x4, ${3:x}\0Aumulh x5, x5, ${3:x}\0Aadcs x4, x4, x5\0Astr x4, [${1:x}, #16]\0Aldr x4, [${2:x}, #24]\0Aumulh x5, x4, ${3:x}\0Amul x4, x4, ${3:x}\0Aadcs x4, x4, x6\0Acinc x5, x5, hs\0Astp x4, x5, [${1:x}, #24]\0Acmp x5, #0\0Amov ${0:x}, #4\0Acinc ${0:x}, ${0:x}, ne", "=r,r,r,r,~{x4},~{x5},~{x6},~{x7},~{memory},~{cc}"(i64 %rp, i64 %ap, i64 %word)
        ret i64 %size
    IR

  # Literal AArch64 schedule emitted for runtime.c's positive 5-by-1
  # bigint_mul_n1_small arm. This width is a serial low-plus-carry recurrence;
  # preserve every carry materialization and the unconditional top write.
  fn __bigint_mul1_5_exact(rp, ap, word) (i64 i64 i64) i64
    ll <<~IR
      ; tungsten:alwaysinline
      entry:
        %size = call i64 asm sideeffect "ldr x4, [${2:x}]\0Amul x5, x4, ${3:x}\0Astr x5, [${1:x}]\0Aumulh x4, x4, ${3:x}\0Aldr x5, [${2:x}, #8]\0Aumulh x6, x5, ${3:x}\0Amul x5, x5, ${3:x}\0Aadds x4, x5, x4\0Acinc x5, x6, hs\0Astr x4, [${1:x}, #8]\0Aldr x4, [${2:x}, #16]\0Aumulh x6, x4, ${3:x}\0Amul x4, x4, ${3:x}\0Aadds x4, x4, x5\0Acinc x5, x6, hs\0Astr x4, [${1:x}, #16]\0Aldr x4, [${2:x}, #24]\0Aumulh x6, x4, ${3:x}\0Amul x4, x4, ${3:x}\0Aadds x4, x4, x5\0Acinc x5, x6, hs\0Astr x4, [${1:x}, #24]\0Aldr x4, [${2:x}, #32]\0Aumulh x6, x4, ${3:x}\0Amul x4, x4, ${3:x}\0Aadds x4, x4, x5\0Acinc x5, x6, hs\0Astp x4, x5, [${1:x}, #32]\0Acmp x5, #0\0Amov ${0:x}, #5\0Acinc ${0:x}, ${0:x}, ne", "=r,r,r,r,~{x4},~{x5},~{x6},~{memory},~{cc}"(i64 %rp, i64 %ap, i64 %word)
        ret i64 %size
    IR

  # Exact C schedule for positive 6-by-1: the mul1@5 serial recurrence with
  # one additional carry-materialization/store step and a seventh-limb write.
  fn __bigint_mul1_6_exact(rp, ap, word) (i64 i64 i64) i64
    ll <<~IR
      ; tungsten:alwaysinline
      entry:
        %size = call i64 asm sideeffect "ldr x4, [${2:x}]\0Amul x5, x4, ${3:x}\0Astr x5, [${1:x}]\0Aumulh x4, x4, ${3:x}\0Aldr x5, [${2:x}, #8]\0Aumulh x6, x5, ${3:x}\0Amul x5, x5, ${3:x}\0Aadds x4, x5, x4\0Acinc x5, x6, hs\0Astr x4, [${1:x}, #8]\0Aldr x4, [${2:x}, #16]\0Aumulh x6, x4, ${3:x}\0Amul x4, x4, ${3:x}\0Aadds x4, x4, x5\0Acinc x5, x6, hs\0Astr x4, [${1:x}, #16]\0Aldr x4, [${2:x}, #24]\0Aumulh x6, x4, ${3:x}\0Amul x4, x4, ${3:x}\0Aadds x4, x4, x5\0Acinc x5, x6, hs\0Astr x4, [${1:x}, #24]\0Aldr x4, [${2:x}, #32]\0Aumulh x6, x4, ${3:x}\0Amul x4, x4, ${3:x}\0Aadds x4, x4, x5\0Acinc x5, x6, hs\0Astr x4, [${1:x}, #32]\0Aldr x4, [${2:x}, #40]\0Aumulh x6, x4, ${3:x}\0Amul x4, x4, ${3:x}\0Aadds x4, x4, x5\0Acinc x5, x6, hs\0Astp x4, x5, [${1:x}, #40]\0Acmp x5, #0\0Amov ${0:x}, #6\0Acinc ${0:x}, ${0:x}, ne", "=r,r,r,r,~{x4},~{x5},~{x6},~{memory},~{cc}"(i64 %rp, i64 %ap, i64 %word)
        ret i64 %size
    IR

  # Exact C schedule for positive 7-by-1: preserve the complete serial
  # low-plus-carry recurrence, eighth-limb write, and size 7/8 publication.
  fn __bigint_mul1_7_exact(rp, ap, word) (i64 i64 i64) i64
    ll <<~IR
      ; tungsten:alwaysinline
      entry:
        %size = call i64 asm sideeffect "ldr x4, [${2:x}]\0Amul x5, x4, ${3:x}\0Astr x5, [${1:x}]\0Aumulh x4, x4, ${3:x}\0Aldr x5, [${2:x}, #8]\0Aumulh x6, x5, ${3:x}\0Amul x5, x5, ${3:x}\0Aadds x4, x5, x4\0Acinc x5, x6, hs\0Astr x4, [${1:x}, #8]\0Aldr x4, [${2:x}, #16]\0Aumulh x6, x4, ${3:x}\0Amul x4, x4, ${3:x}\0Aadds x4, x4, x5\0Acinc x5, x6, hs\0Astr x4, [${1:x}, #16]\0Aldr x4, [${2:x}, #24]\0Aumulh x6, x4, ${3:x}\0Amul x4, x4, ${3:x}\0Aadds x4, x4, x5\0Acinc x5, x6, hs\0Astr x4, [${1:x}, #24]\0Aldr x4, [${2:x}, #32]\0Aumulh x6, x4, ${3:x}\0Amul x4, x4, ${3:x}\0Aadds x4, x4, x5\0Acinc x5, x6, hs\0Astr x4, [${1:x}, #32]\0Aldr x4, [${2:x}, #40]\0Aumulh x6, x4, ${3:x}\0Amul x4, x4, ${3:x}\0Aadds x4, x4, x5\0Acinc x5, x6, hs\0Astr x4, [${1:x}, #40]\0Aldr x4, [${2:x}, #48]\0Aumulh x6, x4, ${3:x}\0Amul x4, x4, ${3:x}\0Aadds x4, x4, x5\0Acinc x5, x6, hs\0Astp x4, x5, [${1:x}, #48]\0Acmp x5, #0\0Amov ${0:x}, #7\0Acinc ${0:x}, ${0:x}, ne", "=r,r,r,r,~{x4},~{x5},~{x6},~{memory},~{cc}"(i64 %rp, i64 %ap, i64 %word)
        ret i64 %size
    IR

  # Literal current-C tiny8 schedule: issue eight independent products, then
  # settle them with one straight add-with-carry chain and publish limb 8.
  fn __bigint_mul1_8_exact(rp, ap, word) (i64 i64 i64) i64
    ll <<~IR
      ; tungsten:alwaysinline
      entry:
        %size = call i64 asm sideeffect "ldp x8, x9, [${2:x}]\0Amul x10, x8, ${3:x}\0Amul x11, x9, ${3:x}\0Aldp x12, x13, [${2:x}, #16]\0Amul x14, x12, ${3:x}\0Amul x15, x13, ${3:x}\0Aldp x16, x17, [${2:x}, #32]\0Amul x2, x16, ${3:x}\0Amul x3, x17, ${3:x}\0Aldp x4, x5, [${2:x}, #48]\0Amul x6, x4, ${3:x}\0Amul x7, x5, ${3:x}\0Aumulh x8, x8, ${3:x}\0Aadds x8, x11, x8\0Astp x10, x8, [${1:x}]\0Aumulh x8, x9, ${3:x}\0Aadcs x8, x14, x8\0Aumulh x9, x12, ${3:x}\0Aadcs x9, x15, x9\0Astp x8, x9, [${1:x}, #16]\0Aumulh x8, x13, ${3:x}\0Aadcs x8, x2, x8\0Aumulh x9, x16, ${3:x}\0Aadcs x9, x3, x9\0Astp x8, x9, [${1:x}, #32]\0Aumulh x8, x17, ${3:x}\0Aadcs x8, x6, x8\0Aumulh x9, x4, ${3:x}\0Aadcs x9, x7, x9\0Astp x8, x9, [${1:x}, #48]\0Aumulh x8, x5, ${3:x}\0Acinc x8, x8, hs\0Astr x8, [${1:x}, #64]\0Acmp x8, #0\0Amov ${0:x}, #8\0Acinc ${0:x}, ${0:x}, ne", "=r,r,r,r,~{x2},~{x3},~{x4},~{x5},~{x6},~{x7},~{x8},~{x9},~{x10},~{x11},~{x12},~{x13},~{x14},~{x15},~{x16},~{x17},~{memory},~{cc}"(i64 %rp, i64 %ap, i64 %word)
        ret i64 %size
    IR

  fn __bigint_add1_2_exact(rp, ap, word) (i64 i64 i64) i64
    asm <<~ASM
      ldp x4, x5, [x1]
      adds x4, x4, x2
      adcs x5, x5, xzr
      stp x4, x5, [x0]
      cset x0, cs
      ret
    ASM

  fn __bigint_add1_3_exact(rp, ap, word) (i64 i64 i64) i64
    asm <<~ASM
      ldp x4, x5, [x1]
      ldr x6, [x1, #16]
      adds x4, x4, x2
      adcs x5, x5, xzr
      adcs x6, x6, xzr
      stp x4, x5, [x0]
      str x6, [x0, #16]
      cset x0, cs
      ret
    ASM

  fn __bigint_add1_4_exact(rp, ap, word) (i64 i64 i64) i64
    asm <<~ASM
      ldp x4, x5, [x1]
      ldp x6, x7, [x1, #16]
      adds x4, x4, x2
      adcs x5, x5, xzr
      adcs x6, x6, xzr
      adcs x7, x7, xzr
      stp x4, x5, [x0]
      stp x6, x7, [x0, #16]
      cset x0, cs
      ret
    ASM

  fn __bigint_add1_5_exact(rp, ap, word) (i64 i64 i64) i64
    asm <<~ASM
      ldp x4, x5, [x1]
      ldp x6, x7, [x1, #16]
      ldr x8, [x1, #32]
      adds x4, x4, x2
      adcs x5, x5, xzr
      adcs x6, x6, xzr
      adcs x7, x7, xzr
      adcs x8, x8, xzr
      stp x4, x5, [x0]
      stp x6, x7, [x0, #16]
      str x8, [x0, #32]
      cset x0, cs
      ret
    ASM

  fn __bigint_add1_6_exact(rp, ap, word) (i64 i64 i64) i64
    asm <<~ASM
      ldp x4, x5, [x1]
      ldp x6, x7, [x1, #16]
      ldp x8, x9, [x1, #32]
      adds x4, x4, x2
      adcs x5, x5, xzr
      adcs x6, x6, xzr
      adcs x7, x7, xzr
      adcs x8, x8, xzr
      adcs x9, x9, xzr
      stp x4, x5, [x0]
      stp x6, x7, [x0, #16]
      stp x8, x9, [x0, #32]
      cset x0, cs
      ret
    ASM

  fn __bigint_add1_7_exact(rp, ap, word) (i64 i64 i64) i64
    # Native-only follow-up after the literal seven-limb checkpoint: once the
    # carry dies at limb one, the remaining five limbs are unchanged copies.
    # The unlikely arm preserves the complete C carry chain bit-for-bit.
    asm <<~ASM
      ldp x4, x5, [x1]
      ldp x6, x7, [x1, #16]
      ldp x8, x9, [x1, #32]
      ldr x10, [x1, #48]
      adds x4, x4, x2
      adcs x5, x5, xzr
      b.cs 1f
      stp x4, x5, [x0]
      stp x6, x7, [x0, #16]
      stp x8, x9, [x0, #32]
      str x10, [x0, #48]
      mov x0, xzr
      b 2f
    1:
      adcs x6, x6, xzr
      adcs x7, x7, xzr
      adcs x8, x8, xzr
      adcs x9, x9, xzr
      adcs x10, x10, xzr
      stp x4, x5, [x0]
      stp x6, x7, [x0, #16]
      stp x8, x9, [x0, #32]
      str x10, [x0, #48]
      cset x0, cs
    2:
      ret
    ASM

  fn __bigint_add1_8_exact(rp, ap, word) (i64 i64 i64) i64
    asm <<~ASM
      ldp x4, x5, [x1]
      ldp x6, x7, [x1, #16]
      ldp x8, x9, [x1, #32]
      ldp x10, x11, [x1, #48]
      adds x4, x4, x2
      adcs x5, x5, xzr
      b.cs 1f
      stp x4, x5, [x0]
      stp x6, x7, [x0, #16]
      stp x8, x9, [x0, #32]
      stp x10, x11, [x0, #48]
      mov x0, xzr
      b 2f
    1:
      adcs x6, x6, xzr
      adcs x7, x7, xzr
      adcs x8, x8, xzr
      adcs x9, x9, xzr
      adcs x10, x10, xzr
      adcs x11, x11, xzr
      stp x4, x5, [x0]
      stp x6, x7, [x0, #16]
      stp x8, x9, [x0, #32]
      stp x10, x11, [x0, #48]
      cset x0, cs
    2:
      ret
    ASM

  # Literal port of runtime.c's two-limb subtract-word arm.  Keep the final
  # borrow materialization even though the canonical 2-by-1 shape cannot
  # borrow past the top: it is part of the retained C leaf's exact schedule.
  fn __bigint_sub1_2_exact(rp, ap, word) (i64 i64 i64) i64
    asm <<~ASM
      ldp x4, x5, [x1]
      subs x4, x4, x2
      sbcs x5, x5, xzr
      stp x4, x5, [x0]
      cset x0, lo
      ret
    ASM

  # Literal port of runtime.c's three-limb subtract-word arm.  Native-only
  # borrow-death and store scheduling are deliberately deferred until this
  # exact schedule is independently checkpointed.
  fn __bigint_sub1_3_exact(rp, ap, word) (i64 i64 i64) i64
    asm <<~ASM
      ldp x4, x5, [x1]
      ldr x6, [x1, #16]
      subs x4, x4, x2
      sbcs x5, x5, xzr
      sbcs x6, x6, xzr
      stp x4, x5, [x0]
      str x6, [x0, #16]
      cset x0, lo
      ret
    ASM

  # Literal port of runtime.c's four-limb subtract-word arm.  Keep the full
  # flag chain, store order, and final borrow materialization unchanged; any
  # borrow-death or store scheduling experiment belongs after this checkpoint.
  fn __bigint_sub1_4_exact(rp, ap, word) (i64 i64 i64) i64
    asm <<~ASM
      ldp x4, x5, [x1]
      ldp x6, x7, [x1, #16]
      subs x4, x4, x2
      sbcs x5, x5, xzr
      sbcs x6, x6, xzr
      sbcs x7, x7, xzr
      stp x4, x5, [x0]
      stp x6, x7, [x0, #16]
      cset x0, lo
      ret
    ASM

  # Literal port of runtime.c's five-limb subtract-word arm.
  fn __bigint_sub1_5_exact(rp, ap, word) (i64 i64 i64) i64
    asm <<~ASM
      ldp x4, x5, [x1]
      ldp x6, x7, [x1, #16]
      ldr x8, [x1, #32]
      subs x4, x4, x2
      sbcs x5, x5, xzr
      sbcs x6, x6, xzr
      sbcs x7, x7, xzr
      sbcs x8, x8, xzr
      stp x4, x5, [x0]
      stp x6, x7, [x0, #16]
      str x8, [x0, #32]
      cset x0, lo
      ret
    ASM

  # Literal port of runtime.c's six-limb subtract-word arm.
  fn __bigint_sub1_6_exact(rp, ap, word) (i64 i64 i64) i64
    asm <<~ASM
      ldp x4, x5, [x1]
      ldp x6, x7, [x1, #16]
      ldp x8, x9, [x1, #32]
      subs x4, x4, x2
      sbcs x5, x5, xzr
      sbcs x6, x6, xzr
      sbcs x7, x7, xzr
      sbcs x8, x8, xzr
      sbcs x9, x9, xzr
      stp x4, x5, [x0]
      stp x6, x7, [x0, #16]
      stp x8, x9, [x0, #32]
      cset x0, lo
      ret
    ASM

  # Literal port of runtime.c's seven-limb subtract-word arm.
  fn __bigint_sub1_7_exact(rp, ap, word) (i64 i64 i64) i64
    asm <<~ASM
      ldp x4, x5, [x1]
      ldp x6, x7, [x1, #16]
      ldp x8, x9, [x1, #32]
      ldr x10, [x1, #48]
      subs x4, x4, x2
      sbcs x5, x5, xzr
      sbcs x6, x6, xzr
      sbcs x7, x7, xzr
      sbcs x8, x8, xzr
      sbcs x9, x9, xzr
      sbcs x10, x10, xzr
      stp x4, x5, [x0]
      stp x6, x7, [x0, #16]
      stp x8, x9, [x0, #32]
      str x10, [x0, #48]
      cset x0, lo
      ret
    ASM

  # Literal port of runtime.c's eight-limb subtract-word arm.  Unlike the
  # separately optimized add arm, retained C still uses the full borrow chain.
  fn __bigint_sub1_8_exact(rp, ap, word) (i64 i64 i64) i64
    asm <<~ASM
      ldp x4, x5, [x1]
      ldp x6, x7, [x1, #16]
      ldp x8, x9, [x1, #32]
      ldp x10, x11, [x1, #48]
      subs x4, x4, x2
      sbcs x5, x5, xzr
      sbcs x6, x6, xzr
      sbcs x7, x7, xzr
      sbcs x8, x8, xzr
      sbcs x9, x9, xzr
      sbcs x10, x10, xzr
      sbcs x11, x11, xzr
      stp x4, x5, [x0]
      stp x6, x7, [x0, #16]
      stp x8, x9, [x0, #32]
      stp x10, x11, [x0, #48]
      cset x0, lo
      ret
    ASM

  # Native-only follow-up to the exact checkpoint above.  A borrow surviving
  # limb one requires limb one to be zero while limb zero borrowed; on the
  # common path the remaining six limbs are therefore a pure copy.  The rare
  # path retains the exact full borrow chain and store schedule.
  fn __bigint_sub1_8_borrow_death(rp, ap, word) (i64 i64 i64) i64
    asm <<~ASM
      ldp x4, x5, [x1]
      subs x4, x4, x2
      sbcs x5, x5, xzr
      b.cc 1f
      ldp x6, x7, [x1, #16]
      ldp x8, x9, [x1, #32]
      ldp x10, x11, [x1, #48]
      stp x4, x5, [x0]
      stp x6, x7, [x0, #16]
      stp x8, x9, [x0, #32]
      stp x10, x11, [x0, #48]
      mov x0, xzr
      ret
    1:
      ldp x6, x7, [x1, #16]
      ldp x8, x9, [x1, #32]
      ldp x10, x11, [x1, #48]
      sbcs x6, x6, xzr
      sbcs x7, x7, xzr
      sbcs x8, x8, xzr
      sbcs x9, x9, xzr
      sbcs x10, x10, xzr
      sbcs x11, x11, xzr
      stp x4, x5, [x0]
      stp x6, x7, [x0, #16]
      stp x8, x9, [x0, #32]
      stp x10, x11, [x0, #48]
      cset x0, lo
      ret
    ASM

  # Raw effective header size for the admitted boxed-BigInt shape.  Keeping
  # this in source avoids a general numeric conversion in the wide hot arm.
  fn __bigint_effective_size_raw(value) (i64) i64
    ll <<~IR
      entry:
        %ptrbits = and i64 %value, 140737488355312
        %ptr = inttoptr i64 %ptrbits to ptr
        %sizeptr = getelementptr i8, ptr %ptr, i64 4
        %size32 = load i32, ptr %sizeptr, align 1
        %size = sext i32 %size32 to i64
        %shifted = lshr i64 %value, 47
        %flipword = and i64 %shifted, 1
        %flip = icmp ne i64 %flipword, 0
        %negative = sub i64 0, %size
        %effective = select i1 %flip, i64 %negative, i64 %size
        ret i64 %effective
    IR

  # Exact wide prefix/ripple from bigint_add_word_into.  A return <= n is the
  # first untouched limb; n+1 means carry ran off the top.
  fn __bigint_add1_wide_prefix(rp, ap, n, word) (i64 i64 i64 i64) i64
    ll <<~IR
      entry:
        %rptr = inttoptr i64 %rp to ptr
        %aptr = inttoptr i64 %ap to ptr
        %a0 = load i64, ptr %aptr, align 8
        %s0 = add i64 %a0, %word
        store i64 %s0, ptr %rptr, align 8
        %carry0 = icmp ult i64 %s0, %word
        %a1ptr = getelementptr i64, ptr %aptr, i64 1
        %r1ptr = getelementptr i64, ptr %rptr, i64 1
        %a1 = load i64, ptr %a1ptr, align 8
        %c0 = zext i1 %carry0 to i64
        %s1 = add i64 %a1, %c0
        store i64 %s1, ptr %r1ptr, align 8
        %carry1 = icmp ult i64 %s1, %c0
        %has2 = icmp ult i64 2, %n
        %continue1 = and i1 %carry1, %has2
        br i1 %continue1, label %ripple, label %done

      ripple:
        %i = phi i64 [ 2, %entry ], [ %next, %ripple ]
        %src = getelementptr i64, ptr %aptr, i64 %i
        %dst = getelementptr i64, ptr %rptr, i64 %i
        %v = load i64, ptr %src, align 8
        %s = add i64 %v, 1
        store i64 %s, ptr %dst, align 8
        %carry = icmp eq i64 %s, 0
        %next = add i64 %i, 1
        %more = icmp ult i64 %next, %n
        %continue = and i1 %carry, %more
        br i1 %continue, label %ripple, label %done

      done:
        %first_untouched = phi i64 [ 2, %entry ], [ %next, %ripple ]
        %carry_out = phi i1 [ %carry1, %entry ], [ %carry, %ripple ]
        %grown = add i64 %n, 1
        %encoded = select i1 %carry_out, i64 %grown, i64 %first_untouched
        ret i64 %encoded
    IR

  # Exact wide prefix/ripple from bigint_sub_word_into.  Return the first
  # untouched limb so the caller can invoke the retained overlap-copy tail.
  fn __bigint_sub1_wide_prefix(rp, ap, n, word) (i64 i64 i64 i64) i64
    ll <<~IR
      ; tungsten:alwaysinline
      entry:
        %rptr = inttoptr i64 %rp to ptr
        %aptr = inttoptr i64 %ap to ptr
        %a0 = load i64, ptr %aptr, align 8
        %d0 = sub i64 %a0, %word
        store i64 %d0, ptr %rptr, align 8
        %borrow0 = icmp ult i64 %a0, %word
        %a1ptr = getelementptr i64, ptr %aptr, i64 1
        %r1ptr = getelementptr i64, ptr %rptr, i64 1
        %a1 = load i64, ptr %a1ptr, align 8
        %b0 = zext i1 %borrow0 to i64
        %d1 = sub i64 %a1, %b0
        store i64 %d1, ptr %r1ptr, align 8
        %borrow1 = icmp ult i64 %a1, %b0
        %has2 = icmp ult i64 2, %n
        %continue1 = and i1 %borrow1, %has2
        br i1 %continue1, label %ripple, label %done

      ripple:
        %i = phi i64 [ 2, %entry ], [ %next, %ripple ]
        %src = getelementptr i64, ptr %aptr, i64 %i
        %dst = getelementptr i64, ptr %rptr, i64 %i
        %v = load i64, ptr %src, align 8
        %d = sub i64 %v, 1
        store i64 %d, ptr %dst, align 8
        %borrow = icmp eq i64 %v, 0
        %next = add i64 %i, 1
        %more = icmp ult i64 %next, %n
        %continue = and i1 %borrow, %more
        br i1 %continue, label %ripple, label %done

      done:
        %first_untouched = phi i64 [ 2, %entry ], [ %next, %ripple ]
        ret i64 %first_untouched
    IR

# Exact raw wrappers for the positive 4-by-2-limb C leaf.  Keep WValue and
# limb addresses as i64 throughout: routing them through typed source fields
# would box the addresses and re-enter ordinary numeric dispatch.  Allocation,
# result capacities, top-limb normalization, and demotion match mag_div_42 /
# mag_mod_42 and their bigint_finish_mag_sub callers.
fn __bigint_div_42_raw(a, b) (i64 i64) i64
  result = ccall_nobox("w_bigint_alloc_hot", 3) ## i64
  rp = (result & 140737488355327) + 16 ## i64
  ap = (a & 140737488355327) + 16 ## i64
  bp = (b & 140737488355327) + 16 ## i64
  __bigint_div_42_exact(rp, ap, bp)
  outn = 0 ## i64
  if raw_load_u64(rp, 16) != 0
    outn = 3
  elsif raw_load_u64(rp, 8) != 0
    outn = 2
  elsif raw_load_u64(rp, 0) != 0
    outn = 1
  ccall_nobox("w_bigint_finish_sub_raw", result, outn)

fn __bigint_mod_42_raw(a, b) (i64 i64) i64
  result = ccall_nobox("w_bigint_alloc_hot", 2) ## i64
  rp = (result & 140737488355327) + 16 ## i64
  ap = (a & 140737488355327) + 16 ## i64
  bp = (b & 140737488355327) + 16 ## i64
  __bigint_mod_42_exact(rp, ap, bp)
  outn = 0 ## i64
  if raw_load_u64(rp, 8) != 0
    outn = 2
  elsif raw_load_u64(rp, 0) != 0
    outn = 1
  ccall_nobox("w_bigint_finish_sub_raw", result, outn)

fn __bigint_div_63_raw(a, b) (i64 i64) i64
  result = ccall_nobox("w_bigint_alloc_hot4_raw") ## i64
  rp = (result & 140737488355327) + 16 ## i64
  ap = (a & 140737488355327) + 16 ## i64
  bp = (b & 140737488355327) + 16 ## i64
  outn = __bigint_div_63_exact(rp, ap, bp) ## i64
  if outn < 0
    ccall_nobox("w_bigint_release_unfinished_raw", result)
    return ccall_nobox("w_bigint_div_63_after_cert_fail", a, b)
  ccall_nobox("w_bigint_finish_sub_raw", result, outn)

fn __bigint_div_84_raw(a, b) (i64 i64) i64
  result = ccall_nobox("w_bigint_alloc_hot", 5) ## i64
  rp = (result & 140737488355327) + 16 ## i64
  ap = (a & 140737488355327) + 16 ## i64
  bp = (b & 140737488355327) + 16 ## i64
  outn = __bigint_div_84_exact(rp, ap, bp) ## i64
  if outn < 0
    ccall_nobox("w_bigint_release_unfinished_raw", result)
    return ccall_nobox("w_bigint_div_84_after_cert_fail", a, b)
  ccall_nobox("w_bigint_finish_sub_raw", result, outn)

fn __bigint_add1_3_raw(a, b) (i64 i64) i64
  result = ccall_nobox("w_bigint_alloc_hot", 3) ## i64
  mask = 140737488355327 ## i64
  rp = (result & mask) + 16 ## i64
  ap = (a & mask) + 16 ## i64
  bp = (b & mask) + 16 ## i64
  word = raw_load_u64(bp, 0) ## i64
  carry = __bigint_add1_3_exact(rp, ap, word) ## i64
  ccall_nobox("w_bigint_add1_3_finish_raw", result, carry)

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
  signed_size = lt ? 0 - 1 : 1
  ccall_nobox(
    "w_bigint_sub1_1_finish_raw", magnitude, signed_size ## i64
  )

# Exact positive one-limb multiply leaf. The generic runtime gate and typed
# BigInt worker have already proved either a distinct positive one-limb pair
# or C's raw-positive-header one-limb square; this raw worker performs only
# the C leaf's limb loads, 64x64 product, and identical result finishing.
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

# Exact positive two-limb-by-one-limb scalar-word arm. Preserve receiver
# order at the operator seam, then orient only the raw magnitudes after the
# shape gate has proved that exactly one operand has two limbs.
fn __bigint_mul1_2_raw(a, b) (i64 i64) i64
  mask = 140737488355327 ## i64
  abase = a & mask
  bbase = b & mask
  asize = raw_load_u32(abase, 4) ## i64
  wide = abase ## i64
  word_box = bbase ## i64
  if asize != 2
    wide = bbase ## i64
    word_box = abase ## i64
  result = ccall_nobox("w_bigint_alloc_hot4_raw") ## i64
  rp = (result & mask) + 16 ## i64
  ap = wide + 16 ## i64
  word = raw_load_u64(word_box, 16) ## i64
  size = __bigint_mul1_2_exact(rp ## i64, ap ## i64, word) ## i64
  ccall_nobox("w_bigint_mul1_2_finish_raw", result, size)

# Exact positive three-limb-by-one-limb scalar-word arm. The shape gate keeps
# receiver order observable, then this worker performs the same cap-four
# allocation, serial C carry schedule, top write, and size publication.
fn __bigint_mul1_3_raw(a, b) (i64 i64) i64
  mask = 140737488355327 ## i64
  abase = a & mask
  bbase = b & mask
  asize = raw_load_u32(abase, 4) ## i64
  wide = abase ## i64
  word_box = bbase ## i64
  if asize != 3
    wide = bbase ## i64
    word_box = abase ## i64
  result = ccall_nobox("w_bigint_alloc_hot4_raw") ## i64
  rp = (result & mask) + 16 ## i64
  ap = wide + 16 ## i64
  word = raw_load_u64(word_box, 16) ## i64
  size = __bigint_mul1_3_exact(rp ## i64, ap ## i64, word) ## i64
  ccall_nobox("w_bigint_mul1_3_finish_raw", result, size)

# Exact positive four-limb-by-one-limb scalar-word arm. Preserve receiver
# order at the source seam, then reproduce C's capacity-eight allocation,
# literal carry schedule, top write, and header publication.
fn __bigint_mul1_4_raw(a, b) (i64 i64) i64
  mask = 140737488355327 ## i64
  abase = a & mask
  bbase = b & mask
  asize = raw_load_u32(abase, 4) ## i64
  wide = abase ## i64
  word_box = bbase ## i64
  if asize != 4
    wide = bbase ## i64
    word_box = abase ## i64
  result = ccall_nobox("w_bigint_alloc_hot8_raw") ## i64
  rp = (result & mask) + 16 ## i64
  ap = wide + 16 ## i64
  word = raw_load_u64(word_box, 16) ## i64
  size = __bigint_mul1_4_exact(rp ## i64, ap ## i64, word) ## i64
  ccall_nobox("w_bigint_mul1_4_finish_raw", result, size)

# Exact positive five-limb-by-one-limb scalar-word arm. Preserve receiver
# order, capacity-eight allocation, serial carry recurrence, and size 5/6.
fn __bigint_mul1_5_raw(a, b) (i64 i64) i64
  mask = 140737488355327 ## i64
  abase = a & mask
  bbase = b & mask
  asize = raw_load_u32(abase, 4) ## i64
  wide = abase ## i64
  word_box = bbase ## i64
  if asize != 5
    wide = bbase ## i64
    word_box = abase ## i64
  result = ccall_nobox("w_bigint_alloc_hot8_raw") ## i64
  rp = (result & mask) + 16 ## i64
  ap = wide + 16 ## i64
  word = raw_load_u64(word_box, 16) ## i64
  size = __bigint_mul1_5_exact(rp ## i64, ap ## i64, word) ## i64
  ccall_nobox("w_bigint_mul1_5_finish_raw", result, size)

# Exact positive six-limb-by-one-limb scalar-word arm.
fn __bigint_mul1_6_raw(a, b) (i64 i64) i64
  mask = 140737488355327 ## i64
  abase = a & mask
  bbase = b & mask
  asize = raw_load_u32(abase, 4) ## i64
  wide = abase ## i64
  word_box = bbase ## i64
  if asize != 6
    wide = bbase ## i64
    word_box = abase ## i64
  result = ccall_nobox("w_bigint_alloc_hot8_raw") ## i64
  rp = (result & mask) + 16 ## i64
  ap = wide + 16 ## i64
  word = raw_load_u64(word_box, 16) ## i64
  size = __bigint_mul1_6_exact(rp ## i64, ap ## i64, word) ## i64
  ccall_nobox("w_bigint_mul1_6_finish_raw", result, size)

# Exact positive seven-limb-by-one-limb scalar-word arm.
fn __bigint_mul1_7_raw(a, b) (i64 i64) i64
  mask = 140737488355327 ## i64
  abase = a & mask
  bbase = b & mask
  asize = raw_load_u32(abase, 4) ## i64
  wide = abase ## i64
  word_box = bbase ## i64
  if asize != 7
    wide = bbase ## i64
    word_box = abase ## i64
  result = ccall_nobox("w_bigint_alloc_hot8_raw") ## i64
  rp = (result & mask) + 16 ## i64
  ap = wide + 16 ## i64
  word = raw_load_u64(word_box, 16) ## i64
  size = __bigint_mul1_7_exact(rp ## i64, ap ## i64, word) ## i64
  ccall_nobox("w_bigint_mul1_7_finish_raw", result, size)

# Exact positive eight-limb-by-one-limb fixed scalar-word arm.
fn __bigint_mul1_8_raw(a, b) (i64 i64) i64
  mask = 140737488355327 ## i64
  abase = a & mask
  bbase = b & mask
  asize = raw_load_u32(abase, 4) ## i64
  wide = abase ## i64
  word_box = bbase ## i64
  if asize != 8
    wide = bbase ## i64
    word_box = abase ## i64
  result = ccall_nobox("w_bigint_alloc_hot16_raw") ## i64
  rp = (result & mask) + 16 ## i64
  ap = wide + 16 ## i64
  word = raw_load_u64(word_box, 16) ## i64
  size = __bigint_mul1_8_exact(rp ## i64, ap ## i64, word) ## i64
  ccall_nobox("w_bigint_mul1_8_finish_raw", result, size)

# Exact positive two-limb minus positive one-limb C arm.  Allocation, the
# fixed AArch64 schedule, top-limb shrink, and possible i48 demotion remain
# separate steps in the same order as bigint_sub_ui_any.
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

# Montgomery multiplication modulo an odd machine-word modulus. The reduction
# keeps the low-limb carry explicit so it remains exact when the modulus has its
# high bit set and the conceptual 128-bit sum overflows by one bit.
-> __bigint_mont_mul_u64(a, b, modulus, neg_inverse) (u64 u64 u64 u64) u64
  product_low = a * b ## u64
  product_high = mulhi(a, b) ## u64
  multiplier = product_low * neg_inverse ## u64
  correction_low = multiplier * modulus ## u64
  correction_high = mulhi(multiplier, modulus) ## u64

  # The Montgomery multiplier makes product_low + correction_low congruent to
  # zero modulo 2^64. It therefore carries exactly when product_low is nonzero.
  carry = (product_low != 0 ? 1 : 0) ## u64
  wide_reduced = (product_high ## u128) + (correction_high ## u128) ## u128
  wide_reduced = wide_reduced + (carry ## u128) ## u128
  reduced = wide_reduced ## u64
  if (wide_reduced >> 64) != 0
    return reduced - modulus ## u64
  if reduced >= modulus
    return reduced - modulus ## u64
  reduced

# One strong Miller-Rabin witness in Montgomery form. The caller supplies the
# shared per-candidate setup and a base smaller than the normalized one-limb
# BigInt magnitude.
-> __bigint_prime_mr_base_u64(modulus, neg_inverse, one_m, r2, minus_one_m, exponent, shifts, base) (u64 u64 u64 u64 u64 u64 i64 u64) i64
  x = one_m ## u64
  power = __bigint_mont_mul_u64(base, r2, modulus, neg_inverse) ## u64
  e = exponent ## u64
  while e != 0
    if (e & 1) != 0
      x = __bigint_mont_mul_u64(x, power, modulus, neg_inverse) ## u64
    power = __bigint_mont_mul_u64(power, power, modulus, neg_inverse) ## u64
    e = e >> 1 ## u64
  if x == one_m || x == minus_one_m
    return 1 ## i64
  r = 1 ## i64
  while r < shifts
    x = __bigint_mont_mul_u64(x, x, modulus, neg_inverse) ## u64
    if x == minus_one_m
      return 1 ## i64
    r += 1
  0 ## i64

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

  inverse = value ## u64
  inverse = inverse * (2 - value * inverse) ## u64
  inverse = inverse * (2 - value * inverse) ## u64
  inverse = inverse * (2 - value * inverse) ## u64
  inverse = inverse * (2 - value * inverse) ## u64
  inverse = inverse * (2 - value * inverse) ## u64
  neg_inverse = 0 - inverse ## u64
  one_m = (0 - value ## u64) % value ## u64
  r2 = (((one_m ## u128) * (one_m ## u128)) % (value ## u128)) ## u64
  minus_one_m = value - one_m ## u64
  shifts = ccall_nobox("__w_bit_cttz_u64", value - 1 ## u64) ## i64
  exponent = (value - 1 ## u64) >> shifts ## u64

  if __bigint_prime_mr_base_u64(value, neg_inverse, one_m, r2, minus_one_m, exponent, shifts, 2 ## u64) == 0
    return 0 ## i64
  if __bigint_prime_mr_base_u64(value, neg_inverse, one_m, r2, minus_one_m, exponent, shifts, 325 ## u64) == 0
    return 0 ## i64
  if __bigint_prime_mr_base_u64(value, neg_inverse, one_m, r2, minus_one_m, exponent, shifts, 9375 ## u64) == 0
    return 0 ## i64
  if __bigint_prime_mr_base_u64(value, neg_inverse, one_m, r2, minus_one_m, exponent, shifts, 28178 ## u64) == 0
    return 0 ## i64
  if __bigint_prime_mr_base_u64(value, neg_inverse, one_m, r2, minus_one_m, exponent, shifts, 450775 ## u64) == 0
    return 0 ## i64
  if __bigint_prime_mr_base_u64(value, neg_inverse, one_m, r2, minus_one_m, exponent, shifts, 9780504 ## u64) == 0
    return 0 ## i64
  if __bigint_prime_mr_base_u64(value, neg_inverse, one_m, r2, minus_one_m, exponent, shifts, 1795265022 ## u64) == 0
    return 0 ## i64
  1 ## i64

+ BigInt < Int
  - data
    # BigInt rides a dedicated top-level NaN-box tag (0xFFFB), but WBigint retains its C header
    # byte as the live/parked recycler marker. Keep it explicit so
    # size/capacity/limbs land at offsets 4/8/16 respectively.
    u8 _type
    u8[3] _pad
    i32 size
    u32 capacity
    u32 _pad2
    # The flexible limb tail, indexable through the strided inline-element
    # path ($limbs[i], and other$limbs[i] on a receiver whose type is
    # known — a `(BigInt)` typed param or a `## BigInt` hint).
    # Element access is bounds-independent raw memory: every method owns its
    # own semantic bounds check against |$size| (or $capacity for writes).
    u64[] limbs

  # Int's neighboring-value methods operate directly on the inline i48
  # payload. BigInt is Int's heap continuation, so override those methods at
  # the representation boundary and let the exact arithmetic operators either
  # retain a BigInt or canonicalize the crossover result back to Int.
  -> prev
    self - 1

  -> succ
    self + 1

  -> next
    self + 1

# Portable raw-limb funnel for positive sub-limb left shifts. Fresh and
# recycled buffers can occupy page offsets that make a fixed walk direction
# false-conflict in the load/store unit, so select the direction from the
# source/destination delta. Each iteration carries the overlapping source
# limb in SSA and performs one new load and one store.
fn __bigint_shl_positive_funnel(rp, sp, n, k) (i64 i64 i64 i64) i64
  ll <<~IR
    entry:
      %rq = inttoptr i64 %rp to ptr
      %sq = inttoptr i64 %sp to ptr
      %right = sub i64 64, %k
      %last = sub i64 %n, 1
      %base = load i64, ptr %sq, align 8
      %low = shl i64 %base, %k
      store i64 %low, ptr %rq, align 8
      %delta.raw = sub i64 %sp, %rp
      %delta = and i64 %delta.raw, 4095
      %descend = icmp ult i64 %delta, 2048
      br i1 %descend, label %desc.pre, label %asc.pre
    desc.pre:
      %dtop.g = getelementptr inbounds i64, ptr %sq, i64 %last
      %dtop = load i64, ptr %dtop.g, align 8
      br label %desc
    desc:
      %di = phi i64 [ %last, %desc.pre ], [ %dprev, %desc ]
      %dcurrent = phi i64 [ %dtop, %desc.pre ], [ %dlower, %desc ]
      %dprev = sub i64 %di, 1
      %dsrc.g = getelementptr inbounds i64, ptr %sq, i64 %dprev
      %ddst.g = getelementptr inbounds i64, ptr %rq, i64 %di
      %dlower = load i64, ptr %dsrc.g, align 8
      %dhi = shl i64 %dcurrent, %k
      %dlo = lshr i64 %dlower, %right
      %dvalue = or i64 %dhi, %dlo
      store i64 %dvalue, ptr %ddst.g, align 8
      %ddone = icmp eq i64 %di, 1
      br i1 %ddone, label %exit, label %desc
    asc.pre:
      br label %asc
    asc:
      %ai = phi i64 [ 1, %asc.pre ], [ %anext, %asc ]
      %aprevious = phi i64 [ %base, %asc.pre ], [ %acurrent, %asc ]
      %asrc.g = getelementptr inbounds i64, ptr %sq, i64 %ai
      %adst.g = getelementptr inbounds i64, ptr %rq, i64 %ai
      %acurrent = load i64, ptr %asrc.g, align 8
      %ahi = shl i64 %acurrent, %k
      %alo = lshr i64 %aprevious, %right
      %avalue = or i64 %ahi, %alo
      store i64 %avalue, ptr %adst.g, align 8
      %adone = icmp eq i64 %ai, %last
      %anext = add i64 %ai, 1
      br i1 %adone, label %exit, label %asc
    exit:
      ret i64 0
  IR

# Portable raw-limb funnel for positive sub-limb right shifts. The result
# buffer is fresh, but its recycled address can share a 4 KiB offset with the
# receiver. Choose the walk direction from that offset so trailing stores do
# not false-conflict with subsequent loads on Apple M-class cores. Every
# iteration carries the overlapping source limb in SSA and performs one new
# load, one store, and the two complementary shifts.
fn __bigint_shr_positive_funnel(rp, sp, n, k) (i64 i64 i64 i64) i64
  ll <<~IR
    entry:
      %rq = inttoptr i64 %rp to ptr
      %sq = inttoptr i64 %sp to ptr
      %left = sub i64 64, %k
      %last = sub i64 %n, 1
      %delta.raw = sub i64 %sp, %rp
      %delta = and i64 %delta.raw, 4095
      %descend = icmp ult i64 %delta, 2048
      br i1 %descend, label %desc.pre, label %asc.pre
    desc.pre:
      %dtop.g = getelementptr inbounds i64, ptr %sq, i64 %last
      %dtop = load i64, ptr %dtop.g, align 8
      %dstart = sub i64 %n, 2
      br label %desc
    desc:
      %di = phi i64 [ %dstart, %desc.pre ], [ %dprev, %desc ]
      %dcurrent = phi i64 [ %dtop, %desc.pre ], [ %dlower, %desc ]
      %dsrc.g = getelementptr inbounds i64, ptr %sq, i64 %di
      %ddst.g = getelementptr inbounds i64, ptr %rq, i64 %di
      %dlower = load i64, ptr %dsrc.g, align 8
      %dlo = lshr i64 %dlower, %k
      %dhi = shl i64 %dcurrent, %left
      %dvalue = or i64 %dlo, %dhi
      store i64 %dvalue, ptr %ddst.g, align 8
      %ddone = icmp eq i64 %di, 0
      %dprev = sub i64 %di, 1
      br i1 %ddone, label %exit, label %desc
    asc.pre:
      %abase = load i64, ptr %sq, align 8
      br label %asc
    asc:
      %ai = phi i64 [ 0, %asc.pre ], [ %anext, %asc ]
      %acurrent = phi i64 [ %abase, %asc.pre ], [ %ahigher, %asc ]
      %anext = add i64 %ai, 1
      %asrc.g = getelementptr inbounds i64, ptr %sq, i64 %anext
      %adst.g = getelementptr inbounds i64, ptr %rq, i64 %ai
      %ahigher = load i64, ptr %asrc.g, align 8
      %alo = lshr i64 %acurrent, %k
      %ahi = shl i64 %ahigher, %left
      %avalue = or i64 %alo, %ahi
      store i64 %avalue, ptr %adst.g, align 8
      %adone = icmp eq i64 %anext, %last
      br i1 %adone, label %exit, label %asc
    exit:
      ret i64 0
  IR

+ BigInt
  -> zero?
    $size == 0

  -> even?
    if $size == 0
      return true
    ($limbs[0] & 1) == 0

  -> odd?
    if $size == 0
      return false
    ($limbs[0] & 1) != 0

  # Sign predicates compose the header sign with the tag-sign overlay
  # (encoding v4): `-x` hands out the same buffer with bit 47 of the boxed
  # value flipped, so `$size` alone is the HEADER's sign, not the value's.
  # zero?/even?/odd? read magnitude/limb parity and need no composition.
  -> negative?
    n = $size ## i64
    if n == 0
      return false
    flip = ($value >> 47) & 1
    flip == 1 ? n > 0 : n < 0

  -> positive?
    n = $size ## i64
    if n == 0
      return false
    flip = ($value >> 47) & 1
    flip == 1 ? n < 0 : n > 0

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
  # neg! flips the HEADER sign: every view of this buffer — including
  # tag-flipped `-x` aliases — sees its own effective value negate, which
  # is exactly the linked-view arithmetic (`y = -x; x.neg!` leaves y equal
  # to the new -x, i.e. the old x). abs! must instead land the RECEIVER's
  # effective sign on positive, so it composes with the receiver's own
  # overlay bit before choosing the header sign.
  -> neg!
    n = $size ## i64
    $size = 0 - n
    self

  -> abs!
    n = $size ## i64
    flip = ($value >> 47) & 1
    if flip == 1
      if n > 0
        $size = 0 - n
    else
      if n < 0
        $size = 0 - n
    self

  # Source-routed operators, typed overload pairs. Every entry route
  # PROVES both operands are heap BigInts before the body runs, so the
  # bodies carry no tag checks of their own:
  #   - infix `a + b` with statically-inferred bigint operands lowers to
  #     a tag-GUARDED direct call to this worker (ops.w) — the guard is
  #     what makes inference safe, since a bigint RESULT demotes to an
  #     inline int whenever it fits i48;
  #   - infix with unknown types calls w_add, whose bigint arm re-proves
  #     both operands (bigint_src_shape) before routing here;
  #   - explicit `x.+(y)` and dynamic sends run the synthesized
  #     dispatcher, whose (BigInt) gate is an exact-tag compare.
  # The (Number) catch-all keeps the polymorphic C boundary (w_add —
  # NEVER w_bigint_add: mixed rational/decimal/complex operands need its
  # full arm chain). NEVER apply infix `+`/`-` to bigint operands in
  # these bodies — that re-enters the arm; compose exported boundaries.
  #
  # Per-shape routing: C keeps the strata it measurably wins — the
  # equal-length same-RAW-sign pairs (bigint_{add,sub}_equal_fast,
  # source measured 1.12-1.30 against them) and squaring — via in-body
  # bails to the DIRECT bigint entries; w_add's shape gate makes the
  # same split for the unknown-type route. The migrated arm (unequal
  # multi-limb) runs the fused asm kernels at 0.93-1.00 vs C.
  #
  # Kernel history (why the bodies look like this): SEVEN kernel bodies
  # were measured and rejected under the 5% budget before the fused
  # asm_{add,sub}_uneq form won on the unequal-length arm. The C kernels
  # are dispatch trees of fully-inlined specializations (identity,
  # one-limb, equal-length, word-shape, mutate-in-place, hot-slot reuse);
  # migration proceeds arm by arm, each with its own gate. See
  # benchmarks/runtime_ports/README.md.
  -> +(other)(BigInt)
    an = ((     $value >> 47) & 1) == 1 ? 0 - $size      : $size
    bn = ((other$value >> 47) & 1) == 1 ? 0 - other$size : other$size

    on macos && arm64
      # The exact scalar-word gate has already reduced this arm to two signed
      # header loads.  Complete it before the generic magnitude, range,
      # pointer, and boxed-Boolean sign machinery; arithmetic/storage remain
      # byte-for-byte the separately checkpointed C port.
      if bn == 1
        case an
          1 =>
            pair1 = __bigint_add1_1_sumcarry(
              $value ## i64, other$value ## i64
            ) ## u128
            sum1 = pair1 ## u64
            high1 = pair1 >> 64 ## u128
            carry1 = high1 ## u64
            return wvalue_from_bits(
              ccall_nobox(
                "w_bigint_add1_1_finish_raw",
                sum1 ## i64, carry1 ## i64
              ) ## i64
            )
          2 =>
            return wvalue_from_bits(
              __bigint_add1_2_raw($value ## i64, other$value ## i64)
            )
          3 =>
            return wvalue_from_bits(
              __bigint_add1_3_raw($value ## i64, other$value ## i64)
            )
          4 =>
            return wvalue_from_bits(
              __bigint_add1_4_raw($value ## i64, other$value ## i64)
            )
          5 =>
            return wvalue_from_bits(
              __bigint_add1_5_raw($value ## i64, other$value ## i64)
            )
          6 =>
            return wvalue_from_bits(
              __bigint_add1_6_raw($value ## i64, other$value ## i64)
            )
          7 =>
            return wvalue_from_bits(
              __bigint_add1_7_raw($value ## i64, other$value ## i64)
            )
          8 =>
            return wvalue_from_bits(
              __bigint_add1_8_raw($value ## i64, other$value ## i64)
            )
          =>
            if an > 8 && an <= 4096
              wide_n = __bigint_effective_size_raw($value ## i64) ## i64
              result = ccall_rawargs("w_bigint_alloc_hot", wide_n) ## BigInt
              mask_wide = 140737488355312 ## i64
              rp_wide = (result$value & mask_wide) + 16 ## i64
              ap_wide = ($value & mask_wide) + 16 ## i64
              word = other$limbs[0] ## u64
              state = __bigint_add1_wide_prefix(
                rp_wide, ap_wide, wide_n, word ## i64
              ) ## i64
              if state > wide_n
                return wvalue_from_bits(
                  ccall_nobox(
                    "w_bigint_add1_wide_finish_raw",
                    result$value, wide_n, 1 ## i64
                  ) ## i64
                )
              if state < wide_n
                ccall_nobox(
                  "w_bigint_copy_tail_raw",
                  rp_wide, ap_wide, state, wide_n
                )
              return wvalue_from_bits(
                ccall_nobox(
                  "w_bigint_add1_wide_finish_raw",
                  result$value, wide_n, 0 ## i64
                ) ## i64
              )
            return ccall("w_bigint_add", self, other)

    # The declared-BigInt direct route must not turn the still-C-specialized
    # one-limb neighbors into the generic source kernel.  Return them to the
    # direct BigInt tree before any generic magnitude/sign setup; the migrated
    # positive fixed arms above are the sole exceptions.
    if an == 1 || an == -1 || bn == 1 || bn == -1
      return ccall("w_bigint_add", self, other)

    am = an < 0 ? 0 - an : an
    bm = bn < 0 ? 0 - bn : bn

    if am > 4096 || bm > 4096
      return ccall("w_add", self, other)

    mask = 140737488355312
    pa = ($value & mask) + 16
    pb = (other$value & mask) + 16

    if (an > 0) == (bn > 0)
      # Equal-length same-sign pairs are bigint_add_equal_fast's domain —
      # the dedicated C arm source measured 1.12-1.30 against. Route them
      # through the direct bigint entry (not w_add: both operands are
      # proven, skip the polymorphic preamble).
      if am == bm
        return ccall("w_bigint_add", self, other)

      # Same sign: magnitude add. One fused kernel call covers the common
      # limbs AND the longer operand's remainder — no source tail loop.
      # Plain assignments, never ternaries, for raw limb ADDRESSES: a
      # ternary can box its result and `## i64` would then reinterpret the
      # boxed bits as a pointer (and a swapped length underflows the
      # kernel's remainder count into a ~2^64 write loop).
      lp = pa
      ll = am
      sp = pb
      sl = bm

      if am < bm
        lp = pb
        ll = bm
        sp = pa
        sl = am

      result = ccall("w_bigint_alloc_boxed", ll + 1) ## BigInt
      rp = (result$value & mask) + 16
      carry = asm_add_uneq(rp ## i64, lp ## i64, ll ## i64, sp ## i64, sl ## i64) ## u64
      n = ll

      if carry != 0
        result$limbs[ll] = carry
        n = ll + 1

      return ccall("w_bigint_seal", result, an < 0 ? 0 - n : n)

    # Opposite signs: magnitude subtract, larger operand's sign wins.
    cmp = 0
    if am != bm
      cmp = am > bm ? 1 : 0 - 1
    else
      k = am - 1
      while k >= 0 && cmp == 0
        xa = $limbs[k] ## u64
        xb = other$limbs[k] ## u64
        if xa != xb
          cmp = xa > xb ? 1 : 0 - 1
        k -= 1
    if cmp == 0
      return 0

    bp2 = pa
    bl = am
    sp2 = pb
    sl2 = bm

    if cmp < 0
      bp2 = pb
      bl = bm
      sp2 = pa
      sl2 = am
    dresult = ccall("w_bigint_alloc_boxed", bl)
    drp = (dresult$value & mask) + 16
    asm_sub_uneq(drp ## i64, bp2 ## i64, bl ## i64, sp2 ## i64, sl2 ## i64)
    dneg = an < 0
    if cmp < 0
      dneg = bn < 0
    ccall("w_bigint_seal", dresult, dneg ? 0 - bl : bl)

  # Polymorphic catch-all: every non-BigInt argument (int promotion,
  # rational, decimal, complex, float error paths) keeps the full C arm
  # chain. Typed, not plain — a plain sibling would disqualify the group
  # from dispatcher synthesis (plain_count must be 0) and a `super` fall-
  # through would hit Int's BODYLESS `+` and return nil.
  -> +(other)(Number)
    ccall("w_add", self, other)

  -> -(other)(BigInt)
    an  = ((     $value >> 47) & 1) == 1 ? 0 - $size      : $size
    bn0 = ((other$value >> 47) & 1) == 1 ? 0 - other$size : other$size

    on macos && arm64
      if an == 1 && bn0 == 1
        return wvalue_from_bits(
          __bigint_sub1_1_raw($value ## i64, other$value ## i64)
        )
      if an == 2 && bn0 == 1
        return wvalue_from_bits(
          __bigint_sub1_2_raw($value ## i64, other$value ## i64)
        )
      if an == 3 && bn0 == 1
        return wvalue_from_bits(
          __bigint_sub1_3_raw($value ## i64, other$value ## i64)
        )
      if an == 4 && bn0 == 1
        return wvalue_from_bits(
          __bigint_sub1_4_raw($value ## i64, other$value ## i64)
        )
      if an == 5 && bn0 == 1
        return wvalue_from_bits(
          __bigint_sub1_5_raw($value ## i64, other$value ## i64)
        )
      if an == 6 && bn0 == 1
        return wvalue_from_bits(
          __bigint_sub1_6_raw($value ## i64, other$value ## i64)
        )
      if an == 7 && bn0 == 1
        return wvalue_from_bits(
          __bigint_sub1_7_raw($value ## i64, other$value ## i64)
        )
      if an == 8 && bn0 == 1
        return wvalue_from_bits(
          __bigint_sub1_8_raw($value ## i64, other$value ## i64)
        )
      # Exact port of bigint_sub_word_into's wide arm.  Limbs 0 and 1 are
      # always processed, deeper borrow propagation is rare, and the untouched
      # suffix retains C's tuned overlap-copy helper through an inlinable raw
      # boundary.  Allocation and shrink normalization remain in C order.
      if an > 8 && an <= 4096 && bn0 == 1
        wide_n = __bigint_effective_size_raw($value ## i64) ## i64
        result = ccall_rawargs("w_bigint_alloc_hot", wide_n) ## BigInt
        mask_wide = 140737488355312 ## i64
        rp_wide = (result$value & mask_wide) + 16 ## i64
        ap_wide = ($value & mask_wide) + 16 ## i64
        word = other$limbs[0] ## u64
        i = __bigint_sub1_wide_prefix(
          rp_wide, ap_wide, wide_n, word ## i64
        ) ## i64

        if i < wide_n
          ccall_nobox(
            "w_bigint_copy_tail_raw", rp_wide, ap_wide, i, wide_n
          )

        rlen = wide_n ## i64
        top_offset = (wide_n - 1) * 8 ## i64
        if raw_load_u64(rp_wide, top_offset) == 0
          rlen -= 1
        if rlen < wide_n
          return wvalue_from_bits(
            ccall_nobox("w_bigint_finish_sub_raw", result$value, rlen) ## i64
          )
        result$size = rlen
        return result

    bn = 0 - bn0

    am = an < 0 ? 0 - an : an
    bm = bn < 0 ? 0 - bn : bn

    if am > 4096 || bm > 4096
      return ccall("w_sub", self, other)

    mask = 140737488355312
    pa = ($value & mask) + 16
    pb = (other$value & mask) + 16

    if (an > 0) == (bn > 0)
      # Same sign: magnitude add. One fused kernel call covers the common
      # limbs AND the longer operand's remainder — no source tail loop.
      # Plain assignments, never ternaries, for raw limb ADDRESSES: a
      # ternary can box its result and `## i64` would then reinterpret the
      # boxed bits as a pointer (and a swapped length underflows the
      # kernel's remainder count into a ~2^64 write loop).
      lp = pa
      ll = am
      sp = pb
      sl = bm

      if am < bm
        lp = pb
        ll = bm
        sp = pa
        sl = am

      result = ccall("w_bigint_alloc_boxed", ll + 1) ## BigInt
      rp = (result$value & mask) + 16
      carry = asm_add_uneq(rp ## i64, lp ## i64, ll ## i64, sp ## i64, sl ## i64) ## u64
      n = ll

      if carry != 0
        result$limbs[ll] = carry
        n = ll + 1

      return ccall("w_bigint_seal", result, an < 0 ? 0 - n : n)

    # Post-flip opposite signs mean the RAW operand signs MATCH — and the
    # equal-length slice of that stratum is bigint_sub_equal_fast's domain
    # (the C arm source measured up to 1.30 against). Direct bigint entry:
    # both operands are proven, skip the polymorphic preamble.
    if am == bm
      return ccall("w_bigint_sub", self, other)

    # Opposite signs: magnitude subtract, larger operand's sign wins.
    cmp = 0
    if am != bm
      cmp = am > bm ? 1 : 0 - 1
    else
      k = am - 1
      while k >= 0 && cmp == 0
        xa = $limbs[k] ## u64
        xb = other$limbs[k] ## u64
        if xa != xb
          cmp = xa > xb ? 1 : 0 - 1
        k -= 1

    if cmp == 0
      return 0

    bp2 = pa
    bl = am
    sp2 = pb
    sl2 = bm

    if cmp < 0
      bp2 = pb
      bl = bm
      sp2 = pa
      sl2 = am

    dresult = ccall("w_bigint_alloc_boxed", bl)
    drp = (dresult$value & mask) + 16
    asm_sub_uneq(drp ## i64, bp2 ## i64, bl ## i64, sp2 ## i64, sl2 ## i64)
    dneg = an < 0

    if cmp < 0
      dneg = bn < 0

    ccall("w_bigint_seal", dresult, dneg ? 0 - bl : bl)

  -> -(other)(Number)
    ccall("w_sub", self, other)

  # Schoolbook multiply. `asm_mulbase` writes the full na+nb product in one
  # asm block, so this body has no limb loop: shape tests, one alloc, one
  # kernel call, seal (which trims the possible high zero limb). The gate
  # keeps squaring, n-by-1, and everything past the Karatsuba crossover in
  # C. Sign is the XOR of the operands' effective signs; magnitudes only
  # reach the kernel, so a zero result cannot occur here (both operands are
  # multi-limb, hence nonzero).
  -> *(other)(BigInt)
    an = (($value >> 47) & 1) == 1 ? 0 - $size : $size
    bn = ((other$value >> 47) & 1) == 1 ? 0 - other$size : other$size
    am = an < 0 ? 0 - an : an
    bm = bn < 0 ? 0 - bn : bn

    on macos && arm64
      # Exact C-shaped pointer-identical two-limb square. The raw header
      # check intentionally admits a tag-overlay negative just as C does;
      # a true negative header and all wider squares remain on C.
      if $value == other$value && $size == 2
        return wvalue_from_bits(
          __bigint_sqr2_raw($value ## i64, other$value ## i64)
        )

    if am < 2 || bm < 2 || am > 24 || bm > 24
      on macos && arm64
        # Exact C-shaped pointer-identical one-limb square. The runtime
        # source gate has already matched C's raw positive-header test;
        # reuse the committed 64x64 product and result finisher verbatim.
        if $value == other$value && $size == 1
          return wvalue_from_bits(
            __bigint_mul1_1_raw($value ## i64, other$value ## i64)
          )
        # Exact C-shaped positive 1x1 leaf. Keep its selector behind the
        # pre-existing out-of-band test so every multi-limb shape retains
        # its prior hot path. Pointer-identical squaring and signed neighbors
        # remain on C.
        if an == 1 && bn == 1 && $value != other$value
          return wvalue_from_bits(
            __bigint_mul1_1_raw($value ## i64, other$value ## i64)
          )
        if (an == 2 && bn == 1) || (an == 1 && bn == 2)
          return wvalue_from_bits(
            __bigint_mul1_2_raw($value ## i64, other$value ## i64)
          )
        if (an == 3 && bn == 1) || (an == 1 && bn == 3)
          return wvalue_from_bits(
            __bigint_mul1_3_raw($value ## i64, other$value ## i64)
          )
        if (an == 4 && bn == 1) || (an == 1 && bn == 4)
          return wvalue_from_bits(
            __bigint_mul1_4_raw($value ## i64, other$value ## i64)
          )
        if (an == 5 && bn == 1) || (an == 1 && bn == 5)
          return wvalue_from_bits(
            __bigint_mul1_5_raw($value ## i64, other$value ## i64)
          )
        if (an == 6 && bn == 1) || (an == 1 && bn == 6)
          return wvalue_from_bits(
            __bigint_mul1_6_raw($value ## i64, other$value ## i64)
          )
        if (an == 7 && bn == 1) || (an == 1 && bn == 7)
          return wvalue_from_bits(
            __bigint_mul1_7_raw($value ## i64, other$value ## i64)
          )
        if (an == 8 && bn == 1) || (an == 1 && bn == 8)
          return wvalue_from_bits(
            __bigint_mul1_8_raw($value ## i64, other$value ## i64)
          )
      return ccall("w_bigint_mul_builtin_exact", self, other)
    # Every remaining square (identical boxed bits, flip included) keeps C's
    # dedicated path, mirroring bigint_mul_src_shape's a == b exclusion.
    if $value == other$value
      return ccall("w_bigint_mul_builtin_exact", self, other)

    mask = 140737488355312
    pa = ($value & mask) + 16
    pb = (other$value & mask) + 16
    total = am + bm
    result = ccall("w_bigint_alloc_boxed", total)
    rp = (result$value & mask) + 16
    asm_mulbase(rp ## i64, 0, pa ## i64, 0, pb ## i64, 0, am ## i64, bm ## i64)
    neg = false
    if (an < 0) != (bn < 0)
      neg = true
    ccall("w_bigint_seal", result, neg ? 0 - total : total)

  -> *(other)(Number)
    ccall("w_mul", self, other)

  # Bitwise limb kernels. No carry chains, so no asm is needed: the loops
  # are hand-vectorized <2 x i64> IR, which legalizes to NEON/SSE at every
  # opt level and — unlike a scalar loop — never depends on the
  # vectorizer's runtime alias checks (the fresh result buffer cannot be
  # proven noalias from inside the kernel). Both operand counts are >= 2
  # by the callers' shape tests, so the paired loop always runs.
  fn __bigint_bw_and(rp, ap, bp, n) (i64 i64 i64 i64) i64
    ll <<~IR
      entry:
        %rq = inttoptr i64 %rp to ptr
        %aq = inttoptr i64 %ap to ptr
        %bq = inttoptr i64 %bp to ptr
        %n4 = and i64 %n, -4
        %has4 = icmp ne i64 %n4, 0
        br i1 %has4, label %v4, label %mid
      v4:
        %i = phi i64 [ 0, %entry ], [ %inext, %v4 ]
        %i2 = or i64 %i, 2
        %ag0 = getelementptr inbounds i64, ptr %aq, i64 %i
        %bg0 = getelementptr inbounds i64, ptr %bq, i64 %i
        %rg0 = getelementptr inbounds i64, ptr %rq, i64 %i
        %ag1 = getelementptr inbounds i64, ptr %aq, i64 %i2
        %bg1 = getelementptr inbounds i64, ptr %bq, i64 %i2
        %rg1 = getelementptr inbounds i64, ptr %rq, i64 %i2
        %av0 = load <2 x i64>, ptr %ag0, align 8
        %bv0 = load <2 x i64>, ptr %bg0, align 8
        %av1 = load <2 x i64>, ptr %ag1, align 8
        %bv1 = load <2 x i64>, ptr %bg1, align 8
        %rv0 = and <2 x i64> %av0, %bv0
        %rv1 = and <2 x i64> %av1, %bv1
        store <2 x i64> %rv0, ptr %rg0, align 8
        store <2 x i64> %rv1, ptr %rg1, align 8
        %inext = add nuw nsw i64 %i, 4
        %done4 = icmp uge i64 %inext, %n4
        br i1 %done4, label %mid, label %v4
      mid:
        %j = phi i64 [ 0, %entry ], [ %n4, %v4 ]
        %rem = sub i64 %n, %j
        %has2 = icmp uge i64 %rem, 2
        br i1 %has2, label %pair, label %oddpre
      pair:
        %pag = getelementptr inbounds i64, ptr %aq, i64 %j
        %pbg = getelementptr inbounds i64, ptr %bq, i64 %j
        %prg = getelementptr inbounds i64, ptr %rq, i64 %j
        %pav = load <2 x i64>, ptr %pag, align 8
        %pbv = load <2 x i64>, ptr %pbg, align 8
        %prv = and <2 x i64> %pav, %pbv
        store <2 x i64> %prv, ptr %prg, align 8
        %jp = add nuw nsw i64 %j, 2
        br label %oddchk
      oddpre:
        br label %oddchk
      oddchk:
        %k = phi i64 [ %jp, %pair ], [ %j, %oddpre ]
        %hasodd = icmp ult i64 %k, %n
        br i1 %hasodd, label %scalar, label %exit
      scalar:
        %sag = getelementptr inbounds i64, ptr %aq, i64 %k
        %sbg = getelementptr inbounds i64, ptr %bq, i64 %k
        %srg = getelementptr inbounds i64, ptr %rq, i64 %k
        %sav = load i64, ptr %sag, align 8
        %sbv = load i64, ptr %sbg, align 8
        %srv = and i64 %sav, %sbv
        store i64 %srv, ptr %srg, align 8
        br label %exit
      exit:
        ret i64 0
    IR

  # Bitwise AND. Both-effective-positive multi-limb pairs run the source
  # kernel over the common limbs (higher limbs of the longer operand AND
  # to zero, so the result is exactly min-width); seal trims any top
  # zeros and demotes a small survivor to inline i48. One-limb operands,
  # negative operands (C's fused on-the-fly two's-complement pass), and
  # the aliased-receiver identity keep the C arms, mirroring
  # bigint_bitwise_src_shape — the gate and these bails must stay
  # disjoint or w_bit_and would re-enter this body.
  -> &(other)(BigInt)
    an = (($value >> 47) & 1) == 1 ? 0 - $size : $size
    bn = ((other$value >> 47) & 1) == 1 ? 0 - other$size : other$size
    if an < 2 || bn < 2 || an > 4096 || bn > 4096 || $value == other$value
      return ccall("w_bit_and", self, other)

    n = an
    if bn < an
      n = bn

    mask = 140737488355312
    pa = ($value & mask) + 16
    pb = (other$value & mask) + 16
    result = ccall("w_bigint_alloc_boxed", n) ## BigInt
    rp = (result$value & mask) + 16
    __bigint_bw_and(rp ## i64, pa ## i64, pb ## i64, n ## i64)
    ccall("w_bigint_seal", result, n)

  -> &(other)(Number)
    ccall("w_bit_and", self, other)

  # OR/XOR share this two-phase kernel shape: combine over the SHORTER
  # operand's limbs, then copy the longer operand's remainder. lp/ll is
  # the longer operand (callers sort with plain if/else), sl >= 2.
  fn __bigint_bw_or_uneq(rp, lp, ln, sp, sn) (i64 i64 i64 i64 i64) i64
    ll <<~IR
      entry:
        %rq = inttoptr i64 %rp to ptr
        %lq = inttoptr i64 %lp to ptr
        %sq = inttoptr i64 %sp to ptr
        %s4 = and i64 %sn, -4
        %ahas4 = icmp ne i64 %s4, 0
        br i1 %ahas4, label %av4, label %amid
      av4:
        %i = phi i64 [ 0, %entry ], [ %inext, %av4 ]
        %i2 = or i64 %i, 2
        %alg0 = getelementptr inbounds i64, ptr %lq, i64 %i
        %asg0 = getelementptr inbounds i64, ptr %sq, i64 %i
        %arg0 = getelementptr inbounds i64, ptr %rq, i64 %i
        %alg1 = getelementptr inbounds i64, ptr %lq, i64 %i2
        %asg1 = getelementptr inbounds i64, ptr %sq, i64 %i2
        %arg1 = getelementptr inbounds i64, ptr %rq, i64 %i2
        %alv0 = load <2 x i64>, ptr %alg0, align 8
        %asv0 = load <2 x i64>, ptr %asg0, align 8
        %alv1 = load <2 x i64>, ptr %alg1, align 8
        %asv1 = load <2 x i64>, ptr %asg1, align 8
        %arv0 = or <2 x i64> %alv0, %asv0
        %arv1 = or <2 x i64> %alv1, %asv1
        store <2 x i64> %arv0, ptr %arg0, align 8
        store <2 x i64> %arv1, ptr %arg1, align 8
        %inext = add nuw nsw i64 %i, 4
        %adone4 = icmp uge i64 %inext, %s4
        br i1 %adone4, label %amid, label %av4
      amid:
        %j = phi i64 [ 0, %entry ], [ %s4, %av4 ]
        %arem = sub i64 %sn, %j
        %ahas2 = icmp uge i64 %arem, 2
        br i1 %ahas2, label %apair, label %aoddpre
      apair:
        %plg = getelementptr inbounds i64, ptr %lq, i64 %j
        %psg = getelementptr inbounds i64, ptr %sq, i64 %j
        %prg = getelementptr inbounds i64, ptr %rq, i64 %j
        %plv = load <2 x i64>, ptr %plg, align 8
        %psv = load <2 x i64>, ptr %psg, align 8
        %prv = or <2 x i64> %plv, %psv
        store <2 x i64> %prv, ptr %prg, align 8
        %jp = add nuw nsw i64 %j, 2
        br label %aoddchk
      aoddpre:
        br label %aoddchk
      aoddchk:
        %k = phi i64 [ %jp, %apair ], [ %j, %aoddpre ]
        %ahasodd = icmp ult i64 %k, %sn
        br i1 %ahasodd, label %aodd, label %bstart
      aodd:
        %olg = getelementptr inbounds i64, ptr %lq, i64 %k
        %osg = getelementptr inbounds i64, ptr %sq, i64 %k
        %org = getelementptr inbounds i64, ptr %rq, i64 %k
        %olv = load i64, ptr %olg, align 8
        %osv = load i64, ptr %osg, align 8
        %orv = or i64 %olv, %osv
        store i64 %orv, ptr %org, align 8
        br label %bstart
      bstart:
        %m = sub i64 %ln, %sn
        %m4 = and i64 %m, -4
        %bhas4 = icmp ne i64 %m4, 0
        br i1 %bhas4, label %bv4, label %bmid
      bv4:
        %ci = phi i64 [ 0, %bstart ], [ %cinext, %bv4 ]
        %bi = add i64 %sn, %ci
        %bi2 = add i64 %bi, 2
        %blg0 = getelementptr inbounds i64, ptr %lq, i64 %bi
        %brg0 = getelementptr inbounds i64, ptr %rq, i64 %bi
        %blg1 = getelementptr inbounds i64, ptr %lq, i64 %bi2
        %brg1 = getelementptr inbounds i64, ptr %rq, i64 %bi2
        %blv0 = load <2 x i64>, ptr %blg0, align 8
        %blv1 = load <2 x i64>, ptr %blg1, align 8
        store <2 x i64> %blv0, ptr %brg0, align 8
        store <2 x i64> %blv1, ptr %brg1, align 8
        %cinext = add nuw nsw i64 %ci, 4
        %bdone4 = icmp uge i64 %cinext, %m4
        br i1 %bdone4, label %bmid, label %bv4
      bmid:
        %cj = phi i64 [ 0, %bstart ], [ %m4, %bv4 ]
        %brem = sub i64 %m, %cj
        %bhas2 = icmp uge i64 %brem, 2
        br i1 %bhas2, label %bpair, label %boddpre
      bpair:
        %cbi = add i64 %sn, %cj
        %cplg = getelementptr inbounds i64, ptr %lq, i64 %cbi
        %cprg = getelementptr inbounds i64, ptr %rq, i64 %cbi
        %cplv = load <2 x i64>, ptr %cplg, align 8
        store <2 x i64> %cplv, ptr %cprg, align 8
        %cjp = add nuw nsw i64 %cj, 2
        br label %boddchk
      boddpre:
        br label %boddchk
      boddchk:
        %ck = phi i64 [ %cjp, %bpair ], [ %cj, %boddpre ]
        %bhasodd = icmp ult i64 %ck, %m
        br i1 %bhasodd, label %bodd, label %exit
      bodd:
        %obi = add i64 %sn, %ck
        %oblg = getelementptr inbounds i64, ptr %lq, i64 %obi
        %obrg = getelementptr inbounds i64, ptr %rq, i64 %obi
        %oblv = load i64, ptr %oblg, align 8
        store i64 %oblv, ptr %obrg, align 8
        br label %exit
      exit:
        ret i64 0
    IR

  # Bitwise OR. Same arm as `&` (both effective-positive multi-limb,
  # identity and negatives stay C); the result is exactly max-width and
  # its top limb is the longer operand's (nonzero on normalized inputs),
  # so seal's trim scan exits immediately.
  -> |(other)(BigInt)
    an = (($value >> 47) & 1) == 1 ? 0 - $size : $size
    bn = ((other$value >> 47) & 1) == 1 ? 0 - other$size : other$size
    if an < 2 || bn < 2 || an > 4096 || bn > 4096 || $value == other$value
      return ccall("w_bit_or", self, other)

    mask = 140737488355312
    pa = ($value & mask) + 16
    pb = (other$value & mask) + 16

    lp = pa
    ln = an
    sp = pb
    sn = bn
    if an < bn
      lp = pb
      ln = bn
      sp = pa
      sn = an

    result = ccall("w_bigint_alloc_boxed", ln) ## BigInt
    rp = (result$value & mask) + 16
    __bigint_bw_or_uneq(rp ## i64, lp ## i64, ln ## i64, sp ## i64, sn ## i64)
    ccall("w_bigint_seal", result, ln)

  -> |(other)(Number)
    ccall("w_bit_or", self, other)

  # OR/XOR share this two-phase kernel shape: combine over the SHORTER
  # operand's limbs, then copy the longer operand's remainder. lp/ll is
  # the longer operand (callers sort with plain if/else), sl >= 2.
  fn __bigint_bw_xor_uneq(rp, lp, ln, sp, sn) (i64 i64 i64 i64 i64) i64
    ll <<~IR
      entry:
        %rq = inttoptr i64 %rp to ptr
        %lq = inttoptr i64 %lp to ptr
        %sq = inttoptr i64 %sp to ptr
        %islong4 = icmp eq i64 %ln, 4
        %isshort4 = icmp eq i64 %sn, 4
        %eq4 = and i1 %islong4, %isshort4
        br i1 %eq4, label %fast4, label %general
      fast4:
        %f4l0 = load <2 x i64>, ptr %lq, align 8
        %f4s0 = load <2 x i64>, ptr %sq, align 8
        %f4lg1 = getelementptr inbounds i64, ptr %lq, i64 2
        %f4sg1 = getelementptr inbounds i64, ptr %sq, i64 2
        %f4rg1 = getelementptr inbounds i64, ptr %rq, i64 2
        %f4l1 = load <2 x i64>, ptr %f4lg1, align 8
        %f4s1 = load <2 x i64>, ptr %f4sg1, align 8
        %f4r0 = xor <2 x i64> %f4l0, %f4s0
        %f4r1 = xor <2 x i64> %f4l1, %f4s1
        store <2 x i64> %f4r0, ptr %rq, align 8
        store <2 x i64> %f4r1, ptr %f4rg1, align 8
        ret i64 0
      general:
        %s4 = and i64 %sn, -4
        %ahas4 = icmp ne i64 %s4, 0
        br i1 %ahas4, label %av4, label %amid
      av4:
        %i = phi i64 [ 0, %general ], [ %inext, %av4 ]
        %i2 = or i64 %i, 2
        %alg0 = getelementptr inbounds i64, ptr %lq, i64 %i
        %asg0 = getelementptr inbounds i64, ptr %sq, i64 %i
        %arg0 = getelementptr inbounds i64, ptr %rq, i64 %i
        %alg1 = getelementptr inbounds i64, ptr %lq, i64 %i2
        %asg1 = getelementptr inbounds i64, ptr %sq, i64 %i2
        %arg1 = getelementptr inbounds i64, ptr %rq, i64 %i2
        %alv0 = load <2 x i64>, ptr %alg0, align 8
        %asv0 = load <2 x i64>, ptr %asg0, align 8
        %alv1 = load <2 x i64>, ptr %alg1, align 8
        %asv1 = load <2 x i64>, ptr %asg1, align 8
        %arv0 = xor <2 x i64> %alv0, %asv0
        %arv1 = xor <2 x i64> %alv1, %asv1
        store <2 x i64> %arv0, ptr %arg0, align 8
        store <2 x i64> %arv1, ptr %arg1, align 8
        %inext = add nuw nsw i64 %i, 4
        %adone4 = icmp uge i64 %inext, %s4
        br i1 %adone4, label %amid, label %av4
      amid:
        %j = phi i64 [ 0, %general ], [ %s4, %av4 ]
        %arem = sub i64 %sn, %j
        %ahas2 = icmp uge i64 %arem, 2
        br i1 %ahas2, label %apair, label %aoddpre
      apair:
        %plg = getelementptr inbounds i64, ptr %lq, i64 %j
        %psg = getelementptr inbounds i64, ptr %sq, i64 %j
        %prg = getelementptr inbounds i64, ptr %rq, i64 %j
        %plv = load <2 x i64>, ptr %plg, align 8
        %psv = load <2 x i64>, ptr %psg, align 8
        %prv = xor <2 x i64> %plv, %psv
        store <2 x i64> %prv, ptr %prg, align 8
        %jp = add nuw nsw i64 %j, 2
        br label %aoddchk
      aoddpre:
        br label %aoddchk
      aoddchk:
        %k = phi i64 [ %jp, %apair ], [ %j, %aoddpre ]
        %ahasodd = icmp ult i64 %k, %sn
        br i1 %ahasodd, label %aodd, label %bstart
      aodd:
        %olg = getelementptr inbounds i64, ptr %lq, i64 %k
        %osg = getelementptr inbounds i64, ptr %sq, i64 %k
        %org = getelementptr inbounds i64, ptr %rq, i64 %k
        %olv = load i64, ptr %olg, align 8
        %osv = load i64, ptr %osg, align 8
        %orv = xor i64 %olv, %osv
        store i64 %orv, ptr %org, align 8
        br label %bstart
      bstart:
        %m = sub i64 %ln, %sn
        %m4 = and i64 %m, -4
        %bhas4 = icmp ne i64 %m4, 0
        br i1 %bhas4, label %bv4, label %bmid
      bv4:
        %ci = phi i64 [ 0, %bstart ], [ %cinext, %bv4 ]
        %bi = add i64 %sn, %ci
        %bi2 = add i64 %bi, 2
        %blg0 = getelementptr inbounds i64, ptr %lq, i64 %bi
        %brg0 = getelementptr inbounds i64, ptr %rq, i64 %bi
        %blg1 = getelementptr inbounds i64, ptr %lq, i64 %bi2
        %brg1 = getelementptr inbounds i64, ptr %rq, i64 %bi2
        %blv0 = load <2 x i64>, ptr %blg0, align 8
        %blv1 = load <2 x i64>, ptr %blg1, align 8
        store <2 x i64> %blv0, ptr %brg0, align 8
        store <2 x i64> %blv1, ptr %brg1, align 8
        %cinext = add nuw nsw i64 %ci, 4
        %bdone4 = icmp uge i64 %cinext, %m4
        br i1 %bdone4, label %bmid, label %bv4
      bmid:
        %cj = phi i64 [ 0, %bstart ], [ %m4, %bv4 ]
        %brem = sub i64 %m, %cj
        %bhas2 = icmp uge i64 %brem, 2
        br i1 %bhas2, label %bpair, label %boddpre
      bpair:
        %cbi = add i64 %sn, %cj
        %cplg = getelementptr inbounds i64, ptr %lq, i64 %cbi
        %cprg = getelementptr inbounds i64, ptr %rq, i64 %cbi
        %cplv = load <2 x i64>, ptr %cplg, align 8
        store <2 x i64> %cplv, ptr %cprg, align 8
        %cjp = add nuw nsw i64 %cj, 2
        br label %boddchk
      boddpre:
        br label %boddchk
      boddchk:
        %ck = phi i64 [ %cjp, %bpair ], [ %cj, %boddpre ]
        %bhasodd = icmp ult i64 %ck, %m
        br i1 %bhasodd, label %bodd, label %exit
      bodd:
        %obi = add i64 %sn, %ck
        %oblg = getelementptr inbounds i64, ptr %lq, i64 %obi
        %obrg = getelementptr inbounds i64, ptr %rq, i64 %obi
        %oblv = load i64, ptr %oblg, align 8
        store i64 %oblv, ptr %obrg, align 8
        br label %exit
      exit:
        ret i64 0
    IR

  # Bitwise XOR. Same arm as `&`/`|`; equal-length pairs can cancel any
  # number of top limbs, and seal's trim scan restores canonical form
  # (identical pairs never reach here — the gate excludes a == b, whose
  # x ^ x = 0 stays on C's O(1) identity arm).
  -> ^(other)(BigInt)
    an = (($value >> 47) & 1) == 1 ? 0 - $size : $size
    bn = ((other$value >> 47) & 1) == 1 ? 0 - other$size : other$size
    if an < 2 || bn < 2 || an > 4096 || bn > 4096 || $value == other$value
      return ccall("w_bit_xor", self, other)

    mask = 140737488355312
    pa = ($value & mask) + 16
    pb = (other$value & mask) + 16

    lp = pa
    ln = an
    sp = pb
    sn = bn
    if an < bn
      lp = pb
      ln = bn
      sp = pa
      sn = an

    result = ccall("w_bigint_alloc_boxed", ln) ## BigInt
    rp = (result$value & mask) + 16
    __bigint_bw_xor_uneq(rp ## i64, lp ## i64, ln ## i64, sp ## i64, sn ## i64)
    ccall("w_bigint_seal", result, ln)

  -> ^(other)(Number)
    ccall("w_bit_xor", self, other)

  # Division and modulo, source-routed for both-heap-BigInt pairs. A one-limb
  # pair completes in native Tungsten with unsigned hardware division. Since
  # a normalized one-limb heap divisor is > 2^47-1, its quotient is at most
  # 2^17-1 and always fits the inline Integer representation. Remainders use
  # direct inline boxing or the ordinary u64 allocation boundary. Wider pairs
  # retain the division specialization tree (preinverse 2-by-1,
  # Burnikel-Ziegler, Jebelean exact, and width-certified kernels) behind the
  # existing C boundary. The (Number) catch-alls keep polymorphic rational,
  # decimal, Float, and mixed-Integer semantics.
  -> /(other)(BigInt)
    an = $size ## i64
    bn = other$size ## i64
    amask = an >> 63 ## i64
    bmask = bn >> 63 ## i64
    am = (an ^ amask) - amask ## i64
    bm = (bn ^ bmask) - bmask ## i64
    if (am | bm) == 1
      dividend = $limbs[0] ## u64
      divisor = other$limbs[0] ## u64
      quotient = dividend / divisor ## u64
      int_tag = -1688849860263936 ## i64
      if quotient == 0
        return wvalue_from_bits(int_tag)
      asign = ((an >> 63) & 1) ^ (($value >> 47) & 1) ## i64
      bsign = ((bn >> 63) & 1) ^ ((other$value >> 47) & 1) ## i64
      if (asign ^ bsign) == 1
        payload = (281474976710656 - quotient) ## u64
        return wvalue_from_bits((int_tag | payload) ## i64)
      return wvalue_from_bits((int_tag | quotient) ## i64)
    on macos && arm64
      asign42 = ((an >> 63) & 1) ^ (($value >> 47) & 1) ## i64
      bsign42 = ((bn >> 63) & 1) ^ ((other$value >> 47) & 1) ## i64
      if am == 4 && bm == 2 && asign42 == 0 && bsign42 == 0
        return wvalue_from_bits(
          __bigint_div_42_raw($value ## i64, other$value ## i64)
        )
      if am == 6 && bm == 3 && asign42 == 0 && bsign42 == 0
        return wvalue_from_bits(
          __bigint_div_63_raw($value ## i64, other$value ## i64)
        )
      if am == 8 && bm == 4 && asign42 == 0 && bsign42 == 0
        return wvalue_from_bits(
          __bigint_div_84_raw($value ## i64, other$value ## i64)
        )
    ccall("w_bigint_div", self, other)

  -> /(other)(Number)
    ccall("w_div", self, other)

  -> %(other)(BigInt)
    an = $size ## i64
    bn = other$size ## i64
    amask = an >> 63 ## i64
    bmask = bn >> 63 ## i64
    am = (an ^ amask) - amask ## i64
    bm = (bn ^ bmask) - bmask ## i64
    if (am | bm) == 1
      dividend = $limbs[0] ## u64
      divisor = other$limbs[0] ## u64
      remainder = dividend % divisor ## u64
      int_tag = -1688849860263936 ## i64
      if remainder == 0
        return wvalue_from_bits(int_tag)
      if remainder <= 140737488355327
        asign = ((an >> 63) & 1) ^ (($value >> 47) & 1) ## i64
        if asign == 1
          payload = (281474976710656 - remainder) ## u64
          return wvalue_from_bits((int_tag | payload) ## i64)
        return wvalue_from_bits((int_tag | remainder) ## i64)
      result = ccall("w_u64", remainder) ## BigInt
      asign = ((an >> 63) & 1) ^ (($value >> 47) & 1) ## i64
      if asign == 1
        return wvalue_from_bits(result$value ^ 140737488355328)
      return result
    on macos && arm64
      asign42 = ((an >> 63) & 1) ^ (($value >> 47) & 1) ## i64
      bsign42 = ((bn >> 63) & 1) ^ ((other$value >> 47) & 1) ## i64
      if am == 4 && bm == 2 && asign42 == 0 && bsign42 == 0
        return wvalue_from_bits(
          __bigint_mod_42_raw($value ## i64, other$value ## i64)
        )
      if am == 6 && bm == 3 && asign42 == 0 && bsign42 == 0
        return wvalue_from_bits(
          __bigint_mod_63_raw($value ## i64, other$value ## i64)
        )
      if am == 8 && bm == 4 && asign42 == 0 && bsign42 == 0
        mask84 = 140737488355327 ## i64
        ap84 = ($value & mask84) + 16 ## i64
        bp84 = (other$value & mask84) + 16 ## i64
        return wvalue_from_bits(__bigint_mod_84_raw(ap84, bp84))
    ccall("w_bigint_mod", self, other)

  -> %(other)(Number)
    ccall("w_mod", self, other)

  # Shifts route multi-limb BigInts through source while retaining the tuned
  # magnitude kernels behind reentry-free boundaries. Zero shifts perform only
  # the immutable alias handoff in source; ordinary allocation-producing
  # one-limb cases remain in C; header-only overshifts are admitted at every
  # width. Every admitted source shape reaches one of these typed bodies once.
  -> <<(other)(Int)
    # A negative left-shift count is an arithmetic right shift. If that
    # count covers the full magnitude, complete it from header metadata as
    # inline 0/-1 without reading a limb or entering the C shift kernel.
    n = $size ## i64
    flip = (($value >> 47) & 1) ## i64
    if flip == 1
      n = 0 - n
    k_payload = (other$value & 0xFFFFFFFFFFFF) ## i64
    k = (k_payload - ((k_payload >> 47) << 48)) ## i64
    if k == 0
      return ccall("w_bigint_mark_shared_value", self)
    if k < 0
      right_count = 0 - k
      magnitude_limbs = n
      if magnitude_limbs < 0
        magnitude_limbs = 0 - magnitude_limbs
      if right_count >= magnitude_limbs * 64
        int_tag = -1688849860263936 ## i64
        if n < 0
          return wvalue_from_bits((int_tag | 281474976710655) ## i64)
        return wvalue_from_bits(int_tag)
    # Above the runtime's fixed-width left-shift rungs, complete a positive
    # sub-limb shift in source: one recycled allocation, one raw funnel pass,
    # and direct publication of the already-normalized result width. This is
    # retained only through the same-binary-measured 65..224-limb band.
    if n > 64 && n <= 224 && k > 0 && k < 64
      carry = __bigint_shr_u64($limbs[n - 1] ## u64, 64 - k) ## u64
      outn = n ## i64
      if carry != 0
        outn = outn + 1 ## i64
      result = ccall_rawargs("w_bigint_alloc_hot", outn) ## BigInt
      mask = 140737488355312 ## i64
      sp = (($value & mask) + 16) ## i64
      rp = ((result$value & mask) + 16) ## i64
      __bigint_shl_positive_funnel(
        rp ## i64, sp ## i64, n ## i64, k ## i64
      )
      if carry != 0
        result$limbs[n] = carry
      result$size = outn
      return result
    ccall("w_bigint_shl", self, other)

  -> <<(other)(Number)
    ccall("w_bit_shl", self, other)

  -> >>(other)(Int)
    # Overshifts and positive one-limb results that fit i48 can be completed
    # entirely in source. Overshifts need only the effective sign and limb
    # count: arithmetic right shift produces inline 0 or -1 without reading a
    # limb. The one-limb arm is one load, one logical shift, and direct
    # NaN-boxing. The runtime seam admits exactly these subsets; explicit
    # sends repeat the guards here before taking them.
    n = $size ## i64
    flip = (($value >> 47) & 1) ## i64
    if flip == 1
      n = 0 - n
    k_payload = (other$value & 0xFFFFFFFFFFFF) ## i64
    k = (k_payload - ((k_payload >> 47) << 48)) ## i64
    if k == 0
      return ccall("w_bigint_mark_shared_value", self)
    magnitude_limbs = n
    if magnitude_limbs < 0
      magnitude_limbs = 0 - magnitude_limbs
    int_tag = -1688849860263936 ## i64
    if k > 0
      if k >= magnitude_limbs * 64
        if n < 0
          return wvalue_from_bits((int_tag | 281474976710655) ## i64)
        return wvalue_from_bits(int_tag)
    # From 33 through 96 limbs, a positive sub-limb right shift is one
    # allocation plus the portable raw funnel above. Wider magnitudes retain
    # the C kernel: matched sweeps put the crossover above the 10% budget.
    # Publish the already-normalized size directly: if the shifted top
    # vanishes, the preceding funnel limb necessarily receives nonzero bits.
    if n > 32 && n <= 96 && k > 0 && k < 64
      top = __bigint_shr_u64($limbs[n - 1] ## u64, k) ## u64
      outn = n ## i64
      if top == 0
        outn = outn - 1 ## i64
      result = ccall_rawargs("w_bigint_alloc_hot", outn) ## BigInt
      mask = 140737488355312 ## i64
      sp = (($value & mask) + 16) ## i64
      rp = ((result$value & mask) + 16) ## i64
      __bigint_shr_positive_funnel(
        rp ## i64, sp ## i64, n ## i64, k ## i64
      )
      if outn == n
        result$limbs[n - 1] = top
      result$size = outn
      return result
    # A positive multi-limb shift that discards every limb except the top can
    # demote without allocating: load that normalized top limb, apply its
    # residual 0..63-bit shift, and form the inline result directly.
    if n > 1
      top_start = (n - 1) * 64
      if k >= top_start
        magnitude = __bigint_shr_u64($limbs[n - 1] ## u64, k - top_start) ## u64
        if magnitude <= 140737488355327
          return wvalue_from_bits((int_tag | magnitude) ## i64)
    # Tiny negative magnitudes use the same top-limb demotion with arithmetic
    # rounding. The discarded-limb sticky test is unrolled through four limbs;
    # any discarded bit increments the result magnitude before negative boxing.
    if n < -1 && n >= -4
      limb_count = 0 - n
      top_start = (limb_count - 1) * 64
      if k >= top_start
        residual = k - top_start
        top = $limbs[limb_count - 1] ## u64
        magnitude = __bigint_shr_u64(top, residual) ## u64
        sticky = 0 ## i64
        if (magnitude << residual) != top
          sticky = 1
        low0 = $limbs[0] ## u64
        if low0 != 0
          sticky = 1
        if limb_count > 2
          low1 = $limbs[1] ## u64
          if low1 != 0
            sticky = 1
        if limb_count > 3
          low2 = $limbs[2] ## u64
          if low2 != 0
            sticky = 1
        if sticky == 1
          magnitude += 1
        if magnitude <= 140737488355328
          payload = (281474976710656 - magnitude) ## u64
          return wvalue_from_bits((int_tag | payload) ## i64)
    # Wider negative magnitudes take a source demotion only when rounding is
    # already proven without a scan: either the residual top bits or limb zero
    # is nonzero. Unknown-sticky sparse shapes retain the tuned C scan.
    if n < -4
      limb_count = 0 - n
      top_start = (limb_count - 1) * 64
      if k >= top_start
        residual = k - top_start
        top = $limbs[limb_count - 1] ## u64
        magnitude = __bigint_shr_u64(top, residual) ## u64
        sticky = 0 ## i64
        if (magnitude << residual) != top
          sticky = 1
        low0 = $limbs[0] ## u64
        if low0 != 0
          sticky = 1
        if sticky == 1
          magnitude += 1
          if magnitude <= 140737488355328
            payload = (281474976710656 - magnitude) ## u64
            return wvalue_from_bits((int_tag | payload) ## i64)
    if n == 1 && k > 0 && k < 64
      magnitude = __bigint_shr_u64($limbs[0] ## u64, k) ## u64
      if magnitude <= 140737488355327
        return wvalue_from_bits((int_tag | magnitude) ## i64)
    if n == -1 && k > 0 && k < 64
      limb = $limbs[0] ## u64
      magnitude = __bigint_shr_u64(limb, k) ## u64
      if (magnitude << k) != limb
        magnitude += 1
      if magnitude <= 140737488355328
        payload = (281474976710656 - magnitude) ## u64
        return wvalue_from_bits((int_tag | payload) ## i64)
    ccall("w_bigint_shr", self, other)

  -> >>(other)(Number)
    ccall("w_bit_shr", self, other)

  # Greatest common divisor. Normalized one-limb BigInt pairs complete in
  # source with a raw binary-GCD loop and one final boxing decision. Wider
  # pairs retain the Lehmer/HGCD specialization tree behind the existing
  # runtime boundary.
  -> gcd(other)
    if ((other$value >> 48) & 0xFFFF) == 0xFFFB
      big_other = other ## BigInt
      an = $size ## i64
      bn = big_other$size ## i64
      amask = an >> 63 ## i64
      bmask = bn >> 63 ## i64
      am = (an ^ amask) - amask ## i64
      bm = (bn ^ bmask) - bmask ## i64
      if (am | bm) == 1
        magnitude = __bigint_gcd_u64_nonzero(
          $limbs[0] ## u64,
          big_other$limbs[0] ## u64
        ) ## u64
        if magnitude <= 140737488355327
          return wvalue_from_bits((-1688849860263936 | magnitude) ## i64)
        return ccall("w_u64", magnitude)
    ccall("w_bigint_gcd", self, other)

  # Match runtime.c's AArch64-only boxed 2x2-limb specialization.  Aliasing
  # retains the C identity path because it marks/returns the original buffer;
  # distinct values use the exact register-only magnitude leaf above and the
  # same raw allocation/normalization contract as bigint_gcd_any_inline.
  on arm64
    -> gcd(other)
      if ((other$value >> 48) & 0xFFFF) == 0xFFFB
        big_other = other ## BigInt
        an = $size ## i64
        bn = big_other$size ## i64
        amask = an >> 63 ## i64
        bmask = bn >> 63 ## i64
        am = (an ^ amask) - amask ## i64
        bm = (bn ^ bmask) - bmask ## i64
        if (am | bm) == 1
          magnitude = __bigint_gcd_u64_nonzero(
            $limbs[0] ## u64,
            big_other$limbs[0] ## u64
          ) ## u64
          if magnitude <= 140737488355327
            return wvalue_from_bits((-1688849860263936 | magnitude) ## i64)
          return ccall("w_u64", magnitude)
        if am == 2 && bm == 2 && wvalue_bits(self) != wvalue_bits(other)
          magnitude128 = __bigint_gcd_u128_nonzero(
            $limbs[1] ## i64,
            $limbs[0] ## i64,
            big_other$limbs[1] ## i64,
            big_other$limbs[0] ## i64
          ) ## u128
          low = magnitude128 ## u64
          high128 = magnitude128 >> 64 ## u128
          high = high128 ## u64
          if high == 0
            return ccall("w_u64", low)
          boxed_two = wvalue_from_bits((-1688849860263936 | 2) ## i64)
          result = ccall("w_bigint_alloc_boxed", boxed_two) ## BigInt
          result$limbs[0] = low
          result$limbs[1] = high
          result$size = 2
          return ccall("w_bigint_seal_raw", result, 2)
      ccall("w_bigint_gcd", self, other)

  # Least common multiple. One-limb BigInt pairs stay raw through GCD, exact
  # division, and u128 multiplication, then box once. Mixed and multi-limb
  # pairs retain the fused exact-division runtime boundary.
  -> lcm(other)
    if ((other$value >> 48) & 0xFFFF) == 0xFFFB
      big_other = other ## BigInt
      an = $size ## i64
      bn = big_other$size ## i64
      amask = an >> 63 ## i64
      bmask = bn >> 63 ## i64
      am = (an ^ amask) - amask ## i64
      bm = (bn ^ bmask) - bmask ## i64
      if (am | bm) == 1
        a = $limbs[0] ## u64
        b = big_other$limbs[0] ## u64
        divisor = __bigint_gcd_u64_nonzero(a, b) ## u64
        quotient = a ## u64
        if divisor != 1
          quotient = a / divisor ## u64
        product = (quotient ## u128) * (b ## u128) ## u128
        low = product ## u64
        high = (product >> 64) ## u64
        if high == 0
          if low <= 140737488355327
            return wvalue_from_bits((-1688849860263936 | low) ## i64)
          return ccall("w_u64", low)
        return ccall("w_u128", product)
    ccall("w_bigint_lcm", self, other)

  # Primality. Positive one-limb magnitudes use the exact native all-u64
  # deterministic Miller-Rabin path above. Negative and wider receivers retain
  # the Mersenne Lucas-Lehmer / Proth / BPSW runtime policy.
  -> prime?
    n = $size ## i64
    if (($value >> 47) & 1) == 1
      n = 0 - n
    if n == 1
      return __bigint_prime_u64($limbs[0] ## u64) != 0
    if n == -1
      return false
    ccall("w_bigint_prime_q", self)

  # Integer square root. Positive one- and two-limb magnitudes use native
  # seed-and-correct kernels. Negative and wider receivers retain the
  # workspace-managed divide-and-conquer sqrtrem kernel behind the runtime
  # boundary.
  -> isqrt
    n = $size ## i64
    if (($value >> 47) & 1) == 1
      n = 0 - n
    if n == 1
      root = __bigint_isqrt_u64($limbs[0] ## u64) ## u64
      return wvalue_from_bits((-1688849860263936 | root) ## i64)
    if n == 2
      # A normalized two-limb BigInt has a nonzero high word, so ctlz is in
      # 0..63. Masking with 62 is therefore exactly C's `ctlz & ~1`, while
      # also making the 0..62 range explicit to LLVM's i128 shift lowering.
      shift = ccall_nobox("__w_bit_ctlz_u64", $limbs[1] ## u64) & 62 ## i64
      root = __bigint_isqrt_u128(
        $limbs[0] ## i64,
        $limbs[1] ## i64,
        shift ## i64
      ) ## u64
      if root <= 140737488355327
        return wvalue_from_bits((-1688849860263936 | root) ## i64)
      # Match bigint_isqrt_any's one-limb result construction exactly: take
      # the hot result slot, publish the only limb, then publish size last.
      result = ccall_rawargs("w_bigint_alloc_hot", 1) ## BigInt
      result$limbs[0] = root
      result$size = 1
      return result
    ccall("bigint_isqrt_any", self)

  # Non-mutating absolute value. Effective-positive receivers (including
  # zero) return themselves; effective-negative ones hand out the same
  # buffer with the tag-sign overlay flipped — O(1), zero allocation,
  # exactly like `-x`. The buffer is marked shared first so mutate-if-unique
  # arithmetic never edits it in place through one alias while the other
  # still observes it.
  -> abs
    n = $size ## i64
    if n == 0
      return self
    flip = ($value >> 47) & 1
    if flip == 1 ? n < 0 : n > 0
      return self
    ccall("w_bigint_mark_shared_value", self)
    wvalue_from_bits($value ^ 140737488355328)

  # Conversion to the already-integral representation is receiver identity.
  # Do not normalize: callers can observe exact heap identity.
  -> to_i
    self

  # Conversion to Float. Walk the unsigned magnitude from most-significant
  # limb to least, scaling by the exactly representable 2^64 radix each
  # step. The raw f64 accumulator keeps the loop allocation-free; only the
  # final result is boxed. Compose the header sign with the tag-sign overlay
  # just as the other source-defined BigInt operations do.
  -> to_f
    signed_count = $size ## i64
    count = signed_count ## i64
    if count < 0
      count = 0 - count
    value = ~0.0 ## f64
    i = count - 1 ## i64
    while i >= 0
      limb = $limbs[i] ## u64
      limb_value = limb ## f64
      value = value * ~18446744073709551616.0 + limb_value
      i -= 1
    flip = ($value >> 47) & 1
    if flip == 1 ? signed_count > 0 : signed_count < 0
      value = ~0.0 - value
    value

  # Conversion to String: the divide-and-conquer decimal writer and the
  # base-N chunk loop stay in the runtime behind one exported boundary;
  # the method surface lives here (IC row 0 is retired). Statically
  # :int-typed call sites keep the compiler's w_int_to_s intercept, and
  # print/interpolation paths use w_to_s directly — this body serves
  # dynamic dispatch.
  -> to_s(base = 10)
    ccall("w_bigint_to_s", self, base)
