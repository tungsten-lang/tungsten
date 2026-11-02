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
