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
