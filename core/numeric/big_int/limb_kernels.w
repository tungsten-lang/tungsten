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

  # Literal AArch64 schedule emitted for runtime.c's distinct positive
  # two-by-two-limb multiplication arm. Preserve all four products, the
  # middle/upper carry order, four unconditional stores, and +3/+4 header
  # choice exactly; this is the fidelity checkpoint, not a redesign.
  fn __bigint_mul2_exact(rp, ap, bp) (i64 i64 i64) i64
    ll <<~IR
      ; tungsten:alwaysinline
      entry:
        %size = call i64 asm sideeffect "ldp x8, x9, [${3:x}]\0Aldp x10, x11, [${2:x}]\0Aumulh x12, x8, x10\0Amul x13, x8, x10\0Aumulh x14, x9, x10\0Amul x10, x9, x10\0Amul x15, x11, x8\0Aumulh x8, x11, x8\0Aumulh x16, x11, x9\0Amul x9, x11, x9\0Aadds x10, x10, x12\0Acset w11, hs\0Aadds x8, x8, x14\0Acset w12, hs\0Aadds x8, x8, x9\0Acinc x9, x12, hs\0Aadds x10, x10, x15\0Astp x13, x10, [${1:x}]\0Aadcs x8, x8, x11\0Aadc x9, x16, x9\0Astp x8, x9, [${1:x}, #16]\0Acmp x9, #0\0Amov ${0:x}, #3\0Acinc ${0:x}, ${0:x}, ne", "=r,r,r,r,~{x8},~{x9},~{x10},~{x11},~{x12},~{x13},~{x14},~{x15},~{x16},~{memory},~{cc}"(i64 %rp, i64 %ap, i64 %bp)
        ret i64 %size
    IR

  # Literal AArch64 schedule emitted for runtime.c's distinct positive
  # three-by-three-limb multiplication arm. Preserve all nine products, the
  # column carry order, six unconditional stores, and +5/+6 header choice.
  fn __bigint_mul3_exact(rp, ap, bp) (i64 i64 i64) i64
    ll <<~IR
      ; tungsten:alwaysinline
      entry:
        %size = call i64 asm sideeffect "ldr x8, [${2:x}]\0Aldr x9, [${3:x}]\0Aumulh x10, x9, x8\0Amul x8, x9, x8\0Astr x8, [${1:x}]\0Aldp x8, x9, [${2:x}]\0Aldp x12, x11, [${3:x}]\0Aumulh x13, x11, x8\0Amul x8, x11, x8\0Aadds x8, x8, x10\0Acinc x10, x13, hs\0Aumulh x11, x12, x9\0Amul x9, x12, x9\0Aadds x8, x8, x9\0Astr x8, [${1:x}, #8]\0Aldr x8, [${3:x}, #16]\0Aldp x9, x12, [${2:x}]\0Amul x13, x8, x9\0Aumulh x8, x8, x9\0Aadcs x9, x10, x11\0Aadcs x8, x8, xzr\0Acset w10, hs\0Aadds x9, x9, x13\0Aldp x13, x11, [${3:x}]\0Amul x14, x11, x12\0Aumulh x11, x11, x12\0Aadcs x8, x8, x11\0Acinc x10, x10, hs\0Aadds x9, x9, x14\0Aadcs x8, x8, xzr\0Acset w11, hs\0Aldr x12, [${2:x}, #16]\0Aumulh x14, x13, x12\0Amul x12, x13, x12\0Aadds x9, x9, x12\0Aadcs x8, x8, x14\0Aadc x10, x10, x11\0Astr x9, [${1:x}, #16]\0Aldp x9, x11, [${2:x}, #8]\0Aldp x13, x12, [${3:x}, #8]\0Aumulh x14, x12, x9\0Amul x9, x12, x9\0Aadds x12, x8, x9\0Amul x15, x13, x11\0Aadds x12, x12, x15\0Aadds x10, x10, x14\0Astr x12, [${1:x}, #24]\0Aldr x12, [${2:x}, #16]\0Aldr x14, [${3:x}, #16]\0Aumulh x16, x14, x12\0Acinc x16, x16, hs\0Aadds x8, x8, x9\0Aumulh x9, x13, x11\0Aadcs x9, x10, x9\0Acinc x10, x16, hs\0Acmn x8, x15\0Amul x8, x14, x12\0Aadcs x8, x9, x8\0Acinc x9, x10, hs\0Astp x8, x9, [${1:x}, #32]\0Acmp x9, #0\0Amov ${0:x}, #5\0Acinc ${0:x}, ${0:x}, ne", "=r,r,r,r,~{x8},~{x9},~{x10},~{x11},~{x12},~{x13},~{x14},~{x15},~{x16},~{memory},~{cc}"(i64 %rp, i64 %ap, i64 %bp)
        ret i64 %size
    IR

  # Exact remainder of runtime.c's distinct positive four-by-four-limb arm.
  # Row zero stays the tuned bn_mul_1(n=4) call through the raw C boundary;
  # this literal block preserves the three inlined addmul rows, seven
  # remaining stores, and +7/+8 header choice from the linked C schedule.
  fn __bigint_mul4_addrows_exact(rp, ap, bp, row0_carry) (i64 i64 i64 i64) i64
    ll <<~IR
      ; tungsten:alwaysinline
      entry:
        %size = call i64 asm sideeffect "str ${4:x}, [${1:x}, #32]\0Aldr x8, [${2:x}, #8]\0Aldr x9, [${3:x}]\0Aumulh x10, x9, x8\0Amul x9, x9, x8\0Aldp x11, x12, [${1:x}, #8]\0Aadds x9, x9, x11\0Acinc x10, x10, hs\0Astr x9, [${1:x}, #8]\0Aldr x9, [${3:x}, #8]\0Aumulh x11, x9, x8\0Amul x9, x9, x8\0Aadds x10, x10, x12\0Acset w12, hs\0Aadds x9, x10, x9\0Aadc x10, x12, x11\0Astr x9, [${1:x}, #16]\0Aldr x11, [${3:x}, #16]\0Aumulh x12, x11, x8\0Amul x11, x11, x8\0Aldr x13, [${1:x}, #24]\0Aadds x11, x11, x13\0Acinc x12, x12, hs\0Aadds x10, x11, x10\0Acinc x11, x12, hs\0Astr x10, [${1:x}, #24]\0Aldr x12, [${3:x}, #24]\0Aumulh x13, x12, x8\0Amul x8, x12, x8\0Aadds x8, x8, ${4:x}\0Acinc x12, x13, hs\0Aadds x8, x8, x11\0Acinc x11, x12, hs\0Astp x8, x11, [${1:x}, #32]\0Aldr x12, [${2:x}, #16]\0Aldr x13, [${3:x}]\0Aumulh x14, x13, x12\0Amul x13, x13, x12\0Aadds x9, x13, x9\0Acinc x13, x14, hs\0Astr x9, [${1:x}, #16]\0Aldr x9, [${3:x}, #8]\0Aumulh x14, x9, x12\0Amul x9, x9, x12\0Aadds x10, x13, x10\0Acset w13, hs\0Aadds x9, x10, x9\0Aadc x10, x13, x14\0Astr x9, [${1:x}, #24]\0Aldr x13, [${3:x}, #16]\0Aumulh x14, x13, x12\0Amul x13, x13, x12\0Aadds x8, x13, x8\0Acinc x13, x14, hs\0Aadds x8, x8, x10\0Acinc x10, x13, hs\0Astr x8, [${1:x}, #32]\0Aldr x13, [${3:x}, #24]\0Aumulh x14, x13, x12\0Amul x12, x13, x12\0Aadds x11, x12, x11\0Acinc x12, x14, hs\0Aadds x10, x11, x10\0Acinc x11, x12, hs\0Astp x10, x11, [${1:x}, #40]\0Aldr x12, [${2:x}, #24]\0Aldr x13, [${3:x}]\0Aumulh x14, x13, x12\0Amul x13, x13, x12\0Aadds x9, x13, x9\0Acinc x13, x14, hs\0Astr x9, [${1:x}, #24]\0Aldr x9, [${3:x}, #8]\0Aumulh x14, x9, x12\0Amul x9, x9, x12\0Aadds x8, x13, x8\0Acset w13, hs\0Aadds x8, x8, x9\0Aadc x9, x13, x14\0Astr x8, [${1:x}, #32]\0Aldr x8, [${3:x}, #16]\0Aumulh x13, x8, x12\0Amul x8, x8, x12\0Aadds x8, x8, x10\0Acinc x10, x13, hs\0Aadds x8, x8, x9\0Acinc x9, x10, hs\0Astr x8, [${1:x}, #40]\0Aldr x8, [${3:x}, #24]\0Aumulh x10, x8, x12\0Amul x8, x8, x12\0Aadds x8, x8, x11\0Acinc x10, x10, hs\0Aadds x8, x8, x9\0Acinc x9, x10, hs\0Astp x8, x9, [${1:x}, #48]\0Acmp x9, #0\0Amov ${0:x}, #7\0Acinc ${0:x}, ${0:x}, ne", "=r,r,r,r,r,~{x8},~{x9},~{x10},~{x11},~{x12},~{x13},~{x14},~{memory},~{cc}"(i64 %rp, i64 %ap, i64 %bp, i64 %row0_carry)
        ret i64 %size
    IR

  # Literal AArch64 schedule emitted for runtime.c's pointer-identical
  # positive three-limb square. Preserve all six products, doubled cross
  # terms, carry order, six unconditional stores, and +5/+6 header choice.
  fn __bigint_sqr3_exact(rp, ap) (i64 i64) i64
    ll <<~IR
      ; tungsten:alwaysinline
      entry:
        %size = call i64 asm sideeffect "ldr x8, [${2:x}]\0Amul x9, x8, x8\0Aumulh x8, x8, x8\0Astr x9, [${1:x}]\0Aldp x9, x10, [${2:x}]\0Amul x11, x10, x9\0Aumulh x9, x10, x9\0Alsr x10, x9, #63\0Aextr x9, x9, x11, #63\0Aadds x8, x8, x11, lsl #1\0Aadcs x9, x9, xzr\0Astr x8, [${1:x}, #8]\0Aldp x12, x8, [${2:x}, #8]\0Aldr x11, [${2:x}]\0Amul x13, x8, x11\0Aumulh x8, x8, x11\0Alsr x11, x8, #63\0Aextr x8, x8, x13, #63\0Aadcs x8, x8, x10\0Acinc x10, x11, hs\0Aadds x9, x9, x13, lsl #1\0Aadcs x8, x8, xzr\0Acset x11, hs\0Amul x13, x12, x12\0Aumulh x12, x12, x12\0Aadds x9, x9, x13\0Aadcs x8, x8, x12\0Aadc x10, x10, x11\0Astr x9, [${1:x}, #16]\0Aldp x9, x11, [${2:x}, #8]\0Amul x12, x11, x9\0Aumulh x9, x11, x9\0Alsr x11, x9, #63\0Aextr x9, x9, x12, #63\0Aadds x13, x8, x12, lsl #1\0Aadds x9, x10, x9\0Astr x13, [${1:x}, #24]\0Aldr x10, [${2:x}, #16]\0Aumulh x13, x10, x10\0Aadc x11, x11, x13\0Acmn x8, x12, lsl #1\0Amul x8, x10, x10\0Aadcs x8, x9, x8\0Acinc x9, x11, hs\0Astp x8, x9, [${1:x}, #32]\0Acmp x9, #0\0Amov ${0:x}, #5\0Acinc ${0:x}, ${0:x}, ne", "=r,r,r,~{x8},~{x9},~{x10},~{x11},~{x12},~{x13},~{memory},~{cc}"(i64 %rp, i64 %ap)
        ret i64 %size
    IR

  # Literal AArch64 schedule emitted for runtime.c's pointer-identical
  # positive four-limb square. Preserve all ten products, doubled cross
  # terms, carry order, eight unconditional stores, and +7/+8 header choice.
  fn __bigint_sqr4_exact(rp, ap) (i64 i64) i64
    ll <<~IR
      ; tungsten:alwaysinline
      entry:
        %size = call i64 asm sideeffect "ldr x8, [${2:x}]\0Amul x9, x8, x8\0Aumulh x8, x8, x8\0Astr x9, [${1:x}]\0Aldp x9, x10, [${2:x}]\0Amul x11, x10, x9\0Aumulh x9, x10, x9\0Alsr x10, x9, #63\0Aextr x9, x9, x11, #63\0Aadds x8, x8, x11, lsl #1\0Aadcs x9, x9, xzr\0Astr x8, [${1:x}, #8]\0Aldp x12, x8, [${2:x}, #8]\0Aldr x11, [${2:x}]\0Amul x13, x8, x11\0Aumulh x8, x8, x11\0Alsr x11, x8, #63\0Aextr x8, x8, x13, #63\0Aadcs x8, x8, x10\0Acinc x10, x11, hs\0Aadds x9, x9, x13, lsl #1\0Aadcs x8, x8, xzr\0Acset x11, hs\0Amul x13, x12, x12\0Aumulh x12, x12, x12\0Aadds x9, x9, x13\0Aadcs x8, x8, x12\0Aadc x10, x10, x11\0Astr x9, [${1:x}, #16]\0Aldp x9, x11, [${2:x}]\0Aldp x13, x12, [${2:x}, #16]\0Amul x14, x12, x9\0Aumulh x9, x12, x9\0Alsr x12, x9, #63\0Aextr x9, x9, x14, #63\0Aadds x15, x8, x14, lsl #1\0Amul x16, x13, x11\0Aumulh x11, x13, x11\0Alsr x13, x11, #63\0Aextr x11, x11, x16, #63\0Aadd x14, x16, x14\0Aadd x8, x8, x14, lsl #1\0Aadcs x9, x10, x9\0Aadc x10, x13, x12\0Acmp x8, x15\0Acset x12, lo\0Aadds x9, x9, x11\0Acset x11, hs\0Aadds x9, x9, x12\0Aadc x10, x10, x11\0Astr x8, [${1:x}, #24]\0Aldp x12, x8, [${2:x}, #16]\0Aldr x11, [${2:x}, #8]\0Amul x13, x8, x11\0Aumulh x8, x8, x11\0Alsr x11, x8, #63\0Aextr x8, x8, x13, #63\0Aadds x8, x10, x8\0Acinc x10, x11, hs\0Aadds x9, x9, x13, lsl #1\0Aadcs x8, x8, xzr\0Acset x11, hs\0Amul x13, x12, x12\0Aumulh x12, x12, x12\0Aadds x9, x9, x13\0Aadcs x8, x8, x12\0Aadc x10, x10, x11\0Astr x9, [${1:x}, #32]\0Aldp x9, x11, [${2:x}, #16]\0Amul x12, x11, x9\0Aumulh x9, x11, x9\0Alsr x11, x9, #63\0Aextr x9, x9, x12, #63\0Aadds x13, x8, x12, lsl #1\0Aadds x9, x10, x9\0Astr x13, [${1:x}, #40]\0Aldr x10, [${2:x}, #24]\0Aumulh x13, x10, x10\0Aadc x11, x11, x13\0Acmn x8, x12, lsl #1\0Amul x8, x10, x10\0Aadcs x8, x9, x8\0Acinc x9, x11, hs\0Astp x8, x9, [${1:x}, #48]\0Acmp x9, #0\0Amov ${0:x}, #7\0Acinc ${0:x}, ${0:x}, ne", "=r,r,r,~{x8},~{x9},~{x10},~{x11},~{x12},~{x13},~{x14},~{x15},~{x16},~{memory},~{cc}"(i64 %rp, i64 %ap)
        ret i64 %size
    IR

  # Literal AArch64 schedule emitted for runtime.c's pointer-identical
  # positive five-limb square. Preserve all fifteen products, doubled cross
  # terms, carry order, ten unconditional stores, and +9/+10 header choice.
  fn __bigint_sqr5_exact(rp, ap) (i64 i64) i64
    ll <<~IR
      ; tungsten:alwaysinline
      entry:
        %size = call i64 asm sideeffect "ldr x8, [${2:x}]\0Amul x9, x8, x8\0Aumulh x8, x8, x8\0Astr x9, [${1:x}]\0Aldp x9, x10, [${2:x}]\0Amul x11, x10, x9\0Aumulh x9, x10, x9\0Alsr x10, x9, #63\0Aextr x9, x9, x11, #0x3f\0Aadds x8, x8, x11, lsl #1\0Aadcs x9, x9, xzr\0Astr x8, [${1:x}, #0x8]\0Aldp x12, x8, [${2:x}, #0x8]\0Aldr x11, [${2:x}]\0Amul x13, x8, x11\0Aumulh x8, x8, x11\0Alsr x11, x8, #63\0Aextr x8, x8, x13, #0x3f\0Aadcs x8, x8, x10\0Acinc x10, x11, hs\0Aadds x9, x9, x13, lsl #1\0Aadcs x8, x8, xzr\0Acset w11, hs\0Amul x13, x12, x12\0Aumulh x12, x12, x12\0Aadds x9, x9, x13\0Aadcs x8, x8, x12\0Aadc x10, x10, x11\0Astr x9, [${1:x}, #0x10]\0Aldp x9, x11, [${2:x}]\0Aldp x13, x12, [${2:x}, #0x10]\0Amul x14, x12, x9\0Aumulh x9, x12, x9\0Aextr x12, x9, x14, #0x3f\0Alsr x9, x9, #63\0Aadds x15, x8, x14, lsl #1\0Amul x16, x13, x11\0Aumulh x11, x13, x11\0Aextr x13, x11, x16, #0x3f\0Alsr x11, x11, #63\0Aadd x14, x16, x14\0Aadd x8, x8, x14, lsl #1\0Aadcs x10, x10, x12\0Aadc x9, x11, x9\0Acmp x8, x15\0Acset w11, lo\0Aadds x10, x10, x13\0Acset w12, hs\0Aadds x10, x10, x11\0Aadc x9, x9, x12\0Astr x8, [${1:x}, #0x18]\0Aldp x14, x8, [${2:x}, #0x18]\0Aldp x11, x12, [${2:x}]\0Amul x13, x8, x11\0Aumulh x8, x8, x11\0Alsr x11, x8, #63\0Aextr x8, x8, x13, #0x3f\0Aldr x15, [${2:x}, #0x10]\0Amul x16, x14, x12\0Aumulh x12, x14, x12\0Aadds x14, x10, x13, lsl #1\0Aadd x13, x16, x13\0Aextr x16, x12, x16, #0x3f\0Alsr x12, x12, #63\0Aadd x10, x10, x13, lsl #1\0Aadcs x8, x9, x8\0Aadc x9, x12, x11\0Acmp x10, x14\0Acset w11, lo\0Aadds x8, x8, x16\0Acset w12, hs\0Aadds x8, x8, x11\0Amul x11, x15, x15\0Aumulh x13, x15, x15\0Aadc x9, x9, x12\0Aadds x10, x10, x11\0Aadcs x8, x8, x13\0Acinc x9, x9, hs\0Astr x10, [${1:x}, #0x20]\0Aldp x10, x11, [${2:x}, #0x8]\0Aldp x13, x12, [${2:x}, #0x18]\0Amul x14, x12, x10\0Aumulh x10, x12, x10\0Alsr x12, x10, #63\0Aextr x10, x10, x14, #0x3f\0Aadds x15, x8, x14, lsl #1\0Amul x16, x13, x11\0Aumulh x11, x13, x11\0Alsr x13, x11, #63\0Aextr x11, x11, x16, #0x3f\0Aadd x14, x16, x14\0Aadd x8, x8, x14, lsl #1\0Aadcs x9, x9, x10\0Aadc x10, x13, x12\0Acmp x8, x15\0Acset w12, lo\0Aadds x9, x9, x11\0Acset w11, hs\0Aadds x9, x9, x12\0Aadc x10, x10, x11\0Astr x8, [${1:x}, #0x28]\0Aldp x12, x8, [${2:x}, #0x18]\0Aldr x11, [${2:x}, #0x10]\0Amul x13, x8, x11\0Aumulh x8, x8, x11\0Alsr x11, x8, #63\0Aextr x8, x8, x13, #0x3f\0Aadds x8, x10, x8\0Acinc x10, x11, hs\0Aadds x9, x9, x13, lsl #1\0Aadcs x8, x8, xzr\0Acset w11, hs\0Amul x13, x12, x12\0Aumulh x12, x12, x12\0Aadds x9, x9, x13\0Aadcs x8, x8, x12\0Aadc x10, x10, x11\0Astr x9, [${1:x}, #0x30]\0Aldp x9, x11, [${2:x}, #0x18]\0Amul x12, x11, x9\0Aumulh x9, x11, x9\0Alsr x11, x9, #63\0Aextr x9, x9, x12, #0x3f\0Aadds x13, x8, x12, lsl #1\0Aadds x9, x10, x9\0Astr x13, [${1:x}, #0x38]\0Aldr x10, [${2:x}, #0x20]\0Aumulh x13, x10, x10\0Aadc x11, x11, x13\0Acmn x8, x12, lsl #1\0Amul x8, x10, x10\0Aadcs x8, x9, x8\0Acinc x9, x11, hs\0Astp x8, x9, [${1:x}, #0x40]\0Acmp x9, #0\0Amov ${0:x}, #9\0Acinc ${0:x}, ${0:x}, ne", "=r,r,r,~{x8},~{x9},~{x10},~{x11},~{x12},~{x13},~{x14},~{x15},~{x16},~{memory},~{cc}"(i64 %rp, i64 %ap)
        ret i64 %size
    IR

  # Literal AArch64 schedule emitted for runtime.c's pointer-identical
  # positive six-limb square. Preserve all twenty-one products, doubled cross
  # terms, carry order, twelve unconditional stores, and +11/+12 header choice.
  fn __bigint_sqr6_exact(rp, ap) (i64 i64) i64
    ll <<~IR
      ; tungsten:noinline
      entry:
        %size = call i64 asm sideeffect "ldr x8, [${2:x}]\0Amul x9, x8, x8\0Aumulh x8, x8, x8\0Astr x9, [${1:x}]\0Aldp x9, x10, [${2:x}]\0Amul x11, x10, x9\0Aumulh x9, x10, x9\0Alsr x10, x9, #63\0Aextr x9, x9, x11, #0x3f\0Aadds x8, x8, x11, lsl #1\0Aadcs x9, x9, xzr\0Astr x8, [${1:x}, #0x8]\0Aldp x12, x8, [${2:x}, #0x8]\0Aldr x11, [${2:x}]\0Amul x13, x8, x11\0Aumulh x8, x8, x11\0Alsr x11, x8, #63\0Aextr x8, x8, x13, #0x3f\0Aadcs x8, x8, x10\0Acinc x10, x11, hs\0Aadds x9, x9, x13, lsl #1\0Aadcs x8, x8, xzr\0Acset w11, hs\0Amul x13, x12, x12\0Aumulh x12, x12, x12\0Aadds x9, x9, x13\0Aadcs x8, x8, x12\0Aadc x10, x10, x11\0Astr x9, [${1:x}, #0x10]\0Aldp x9, x11, [${2:x}]\0Aldp x13, x12, [${2:x}, #0x10]\0Amul x14, x12, x9\0Aumulh x9, x12, x9\0Alsr x12, x9, #63\0Aextr x9, x9, x14, #0x3f\0Aadds x15, x8, x14, lsl #1\0Amul x16, x13, x11\0Aumulh x11, x13, x11\0Alsr x13, x11, #63\0Aextr x11, x11, x16, #0x3f\0Aadd x14, x16, x14\0Aadd x8, x8, x14, lsl #1\0Aadcs x9, x10, x9\0Aadc x10, x13, x12\0Acmp x8, x15\0Acset w12, lo\0Aadds x9, x9, x11\0Acset w11, hs\0Aadds x9, x9, x12\0Aadc x10, x10, x11\0Astr x8, [${1:x}, #0x18]\0Aldp x15, x8, [${2:x}, #0x18]\0Aldp x11, x12, [${2:x}]\0Amul x13, x8, x11\0Aumulh x8, x8, x11\0Aextr x11, x8, x13, #0x3f\0Alsr x8, x8, #63\0Aadds x14, x9, x13, lsl #1\0Aldr x16, [${2:x}, #0x10]\0Amul x17, x15, x12\0Aumulh x12, x15, x12\0Alsr x15, x12, #63\0Aextr x12, x12, x17, #0x3f\0Aadd x13, x17, x13\0Aadd x9, x9, x13, lsl #1\0Aadcs x10, x10, x11\0Aadc x8, x15, x8\0Acmp x9, x14\0Acset w11, lo\0Aadds x10, x10, x12\0Acset w12, hs\0Aadds x10, x10, x11\0Amul x11, x16, x16\0Aumulh x13, x16, x16\0Aadc x8, x8, x12\0Aadds x9, x9, x11\0Aadcs x10, x10, x13\0Acinc x8, x8, hs\0Astr x9, [${1:x}, #0x20]\0Aldp x9, x11, [${2:x}]\0Aldp x13, x12, [${2:x}, #0x20]\0Amul x14, x12, x9\0Aumulh x9, x12, x9\0Aextr x12, x9, x14, #0x3f\0Aadds x15, x10, x14, lsl #1\0Amul x16, x13, x11\0Aumulh x11, x13, x11\0Alsr x13, x11, #63\0Aextr x11, x11, x16, #0x3f\0Aldp x17, x2, [${2:x}, #0x10]\0Amul x3, x2, x17\0Aadd x14, x16, x14\0Aadd x16, x14, x3\0Aadd x14, x10, x14, lsl #1\0Aumulh x17, x2, x17\0Alsr x2, x17, #63\0Aadd x9, x13, x9, lsr #63\0Aadcs x8, x8, x12\0Aadc x9, x9, x2\0Acmp x14, x15\0Acset w12, lo\0Aadds x8, x8, x11\0Acset w11, hs\0Aadd x10, x10, x16, lsl #1\0Acmp x10, x14\0Acset w13, lo\0Aadds x8, x8, x12\0Aextr x12, x17, x3, #0x3f\0Aadc x9, x9, x11\0Aadds x8, x8, x12\0Acset w11, hs\0Aadds x8, x8, x13\0Aadc x9, x9, x11\0Astr x10, [${1:x}, #0x28]\0Aldp x15, x10, [${2:x}, #0x20]\0Aldp x11, x12, [${2:x}, #0x8]\0Amul x13, x10, x11\0Aumulh x10, x10, x11\0Alsr x11, x10, #63\0Aextr x10, x10, x13, #0x3f\0Aadds x14, x8, x13, lsl #1\0Aldr x16, [${2:x}, #0x18]\0Amul x17, x15, x12\0Aumulh x12, x15, x12\0Alsr x15, x12, #63\0Aextr x12, x12, x17, #0x3f\0Aadd x13, x17, x13\0Aadd x8, x8, x13, lsl #1\0Aadcs x9, x9, x10\0Aadc x10, x15, x11\0Acmp x8, x14\0Acset w11, lo\0Aadds x9, x9, x12\0Acset w12, hs\0Aadds x9, x9, x11\0Amul x11, x16, x16\0Aumulh x13, x16, x16\0Aadc x10, x10, x12\0Aadds x8, x8, x11\0Aadcs x9, x9, x13\0Acinc x10, x10, hs\0Astr x8, [${1:x}, #0x30]\0Aldp x8, x11, [${2:x}, #0x10]\0Aldp x13, x12, [${2:x}, #0x20]\0Amul x14, x12, x8\0Aumulh x8, x12, x8\0Alsr x12, x8, #63\0Aextr x8, x8, x14, #0x3f\0Aadds x15, x9, x14, lsl #1\0Amul x16, x13, x11\0Aumulh x11, x13, x11\0Alsr x13, x11, #63\0Aextr x11, x11, x16, #0x3f\0Aadd x14, x16, x14\0Aadd x9, x9, x14, lsl #1\0Aadcs x8, x10, x8\0Aadc x10, x13, x12\0Acmp x9, x15\0Acset w12, lo\0Aadds x8, x8, x11\0Acset w11, hs\0Aadds x8, x8, x12\0Aadc x10, x10, x11\0Astr x9, [${1:x}, #0x38]\0Aldp x12, x9, [${2:x}, #0x20]\0Aldr x11, [${2:x}, #0x18]\0Amul x13, x9, x11\0Aumulh x9, x9, x11\0Alsr x11, x9, #63\0Aextr x9, x9, x13, #0x3f\0Aadds x9, x10, x9\0Acinc x10, x11, hs\0Aadds x8, x8, x13, lsl #1\0Aadcs x9, x9, xzr\0Acset w11, hs\0Amul x13, x12, x12\0Aumulh x12, x12, x12\0Aadds x8, x8, x13\0Aadcs x9, x9, x12\0Aadc x10, x10, x11\0Astr x8, [${1:x}, #0x40]\0Aldp x8, x11, [${2:x}, #0x20]\0Amul x12, x11, x8\0Aumulh x8, x11, x8\0Alsr x11, x8, #63\0Aextr x8, x8, x12, #0x3f\0Aadds x13, x9, x12, lsl #1\0Aadds x8, x10, x8\0Astr x13, [${1:x}, #0x48]\0Aldr x10, [${2:x}, #0x28]\0Aumulh x13, x10, x10\0Aadc x11, x11, x13\0Acmn x9, x12, lsl #1\0Amul x9, x10, x10\0Aadcs x8, x8, x9\0Acinc x9, x11, hs\0Astp x8, x9, [${1:x}, #0x50]\0Acmp x9, #0\0Amov ${0:x}, #11\0Acinc ${0:x}, ${0:x}, ne", "=r,r,r,~{x2},~{x3},~{x8},~{x9},~{x10},~{x11},~{x12},~{x13},~{x14},~{x15},~{x16},~{x17},~{memory},~{cc}"(i64 %rp, i64 %ap)
        ret i64 %size
    IR

  # Literal AArch64 schedule emitted for runtime.c's pointer-identical
  # positive seven-limb square. Preserve all twenty-eight products, doubled
  # cross terms, carry order, fourteen stores, and +13/+14 header choice.
  fn __bigint_sqr7_exact(rp, ap) (i64 i64) i64
    ll <<~IR
      ; tungsten:noinline
      entry:
        %size = call i64 asm sideeffect "ldr x8, [${2:x}]\0Amul x9, x8, x8\0Aumulh x8, x8, x8\0Astr x9, [${1:x}]\0Aldp x9, x10, [${2:x}]\0Amul x11, x10, x9\0Aumulh x9, x10, x9\0Aextr x10, x9, x11, #0x3f\0Alsr x9, x9, #63\0Aadds x8, x8, x11, lsl #1\0Aadcs x10, x10, xzr\0Astr x8, [${1:x}, #0x8]\0Aldp x12, x8, [${2:x}, #0x8]\0Aldr x11, [${2:x}]\0Amul x13, x8, x11\0Aumulh x8, x8, x11\0Alsr x11, x8, #63\0Aextr x8, x8, x13, #0x3f\0Aadcs x8, x8, x9\0Acinc x9, x11, hs\0Aadds x10, x10, x13, lsl #1\0Aadcs x8, x8, xzr\0Acset w11, hs\0Amul x13, x12, x12\0Aumulh x12, x12, x12\0Aadds x10, x10, x13\0Aadcs x8, x8, x12\0Aadc x9, x9, x11\0Astr x10, [${1:x}, #0x10]\0Aldp x10, x11, [${2:x}]\0Aldp x13, x12, [${2:x}, #0x10]\0Amul x14, x12, x10\0Aumulh x10, x12, x10\0Alsr x12, x10, #63\0Aextr x10, x10, x14, #0x3f\0Aadds x15, x8, x14, lsl #1\0Amul x16, x13, x11\0Aumulh x11, x13, x11\0Alsr x13, x11, #63\0Aextr x11, x11, x16, #0x3f\0Aadd x14, x16, x14\0Aadd x8, x8, x14, lsl #1\0Aadcs x9, x9, x10\0Aadc x10, x13, x12\0Acmp x8, x15\0Acset w12, lo\0Aadds x9, x9, x11\0Acset w11, hs\0Aadds x9, x9, x12\0Aadc x10, x10, x11\0Astr x8, [${1:x}, #0x18]\0Aldp x15, x8, [${2:x}, #0x18]\0Aldp x11, x12, [${2:x}]\0Amul x13, x8, x11\0Aumulh x8, x8, x11\0Alsr x11, x8, #63\0Aextr x8, x8, x13, #0x3f\0Aadds x14, x9, x13, lsl #1\0Aldr x16, [${2:x}, #0x10]\0Amul x17, x15, x12\0Aumulh x12, x15, x12\0Alsr x15, x12, #63\0Aextr x12, x12, x17, #0x3f\0Aadd x13, x17, x13\0Aadd x9, x9, x13, lsl #1\0Aadcs x8, x10, x8\0Aadc x10, x15, x11\0Acmp x9, x14\0Acset w11, lo\0Aadds x8, x8, x12\0Acset w12, hs\0Aadds x8, x8, x11\0Amul x11, x16, x16\0Aumulh x13, x16, x16\0Aadc x10, x10, x12\0Aadds x9, x9, x11\0Aadcs x8, x8, x13\0Acinc x10, x10, hs\0Astr x9, [${1:x}, #0x20]\0Aldp x9, x11, [${2:x}]\0Aldp x13, x12, [${2:x}, #0x20]\0Amul x14, x12, x9\0Aumulh x9, x12, x9\0Aextr x12, x9, x14, #0x3f\0Aadds x15, x8, x14, lsl #1\0Amul x16, x13, x11\0Aumulh x11, x13, x11\0Alsr x13, x11, #63\0Aextr x11, x11, x16, #0x3f\0Aldp x17, x2, [${2:x}, #0x10]\0Amul x3, x2, x17\0Aadd x14, x16, x14\0Aadd x16, x14, x3\0Aadd x14, x8, x14, lsl #1\0Aumulh x17, x2, x17\0Alsr x2, x17, #63\0Aadd x9, x13, x9, lsr #63\0Aadcs x10, x10, x12\0Aadc x9, x9, x2\0Acmp x14, x15\0Acset w12, lo\0Aadds x10, x10, x11\0Acset w11, hs\0Aadd x13, x8, x16, lsl #1\0Acmp x13, x14\0Acset w8, lo\0Aadds x10, x10, x12\0Aextr x12, x17, x3, #0x3f\0Aadc x9, x9, x11\0Aadds x10, x10, x12\0Acset w11, hs\0Aadds x8, x10, x8\0Aadc x9, x9, x11\0Astr x13, [${1:x}, #0x28]\0Aldp x15, x10, [${2:x}, #0x28]\0Aldp x11, x12, [${2:x}]\0Amul x13, x10, x11\0Aumulh x10, x10, x11\0Aextr x11, x10, x13, #0x3f\0Aadds x14, x8, x13, lsl #1\0Aldp x3, x16, [${2:x}, #0x18]\0Amul x17, x15, x12\0Aumulh x12, x15, x12\0Alsr x15, x12, #63\0Aextr x12, x12, x17, #0x3f\0Aldr x2, [${2:x}, #0x10]\0Amul x4, x16, x2\0Aadd x13, x17, x13\0Aadd x17, x13, x4\0Aadd x13, x8, x13, lsl #1\0Aumulh x16, x16, x2\0Alsr x2, x16, #63\0Aadd x10, x15, x10, lsr #63\0Aadcs x9, x9, x11\0Aadc x10, x10, x2\0Acmp x13, x14\0Acset w11, lo\0Aadds x9, x9, x12\0Acset w12, hs\0Aadd x8, x8, x17, lsl #1\0Acmp x8, x13\0Acset w13, lo\0Aadds x9, x9, x11\0Aextr x11, x16, x4, #0x3f\0Aadc x10, x10, x12\0Aadds x9, x9, x11\0Acset w11, hs\0Aadds x9, x9, x13\0Amul x12, x3, x3\0Aumulh x13, x3, x3\0Aadc x10, x10, x11\0Aadds x8, x8, x12\0Aadcs x9, x9, x13\0Acinc x10, x10, hs\0Astr x8, [${1:x}, #0x30]\0Aldp x8, x11, [${2:x}, #0x8]\0Aldp x13, x12, [${2:x}, #0x28]\0Amul x14, x12, x8\0Aumulh x8, x12, x8\0Aextr x12, x8, x14, #0x3f\0Aadds x15, x9, x14, lsl #1\0Amul x16, x13, x11\0Aumulh x11, x13, x11\0Alsr x13, x11, #63\0Aextr x11, x11, x16, #0x3f\0Aldp x17, x2, [${2:x}, #0x18]\0Amul x3, x2, x17\0Aadd x14, x16, x14\0Aadd x16, x14, x3\0Aadd x14, x9, x14, lsl #1\0Aumulh x17, x2, x17\0Alsr x2, x17, #63\0Aadd x8, x13, x8, lsr #63\0Aadcs x10, x10, x12\0Aadc x8, x8, x2\0Acmp x14, x15\0Acset w12, lo\0Aadds x10, x10, x11\0Acset w11, hs\0Aadd x9, x9, x16, lsl #1\0Acmp x9, x14\0Acset w13, lo\0Aadds x10, x10, x12\0Aextr x12, x17, x3, #0x3f\0Aadc x8, x8, x11\0Aadds x10, x10, x12\0Acset w11, hs\0Aadds x10, x10, x13\0Aadc x8, x8, x11\0Astr x9, [${1:x}, #0x38]\0Aldp x15, x9, [${2:x}, #0x28]\0Aldp x11, x12, [${2:x}, #0x10]\0Amul x13, x9, x11\0Aumulh x9, x9, x11\0Alsr x11, x9, #63\0Aextr x9, x9, x13, #0x3f\0Aadds x14, x10, x13, lsl #1\0Aldr x16, [${2:x}, #0x20]\0Amul x17, x15, x12\0Aumulh x12, x15, x12\0Alsr x15, x12, #63\0Aextr x12, x12, x17, #0x3f\0Aadd x13, x17, x13\0Aadd x10, x10, x13, lsl #1\0Aadcs x8, x8, x9\0Aadc x9, x15, x11\0Acmp x10, x14\0Acset w11, lo\0Aadds x8, x8, x12\0Acset w12, hs\0Aadds x8, x8, x11\0Amul x11, x16, x16\0Aumulh x13, x16, x16\0Aadc x9, x9, x12\0Aadds x10, x10, x11\0Aadcs x8, x8, x13\0Acinc x9, x9, hs\0Astr x10, [${1:x}, #0x40]\0Aldp x10, x11, [${2:x}, #0x18]\0Aldp x13, x12, [${2:x}, #0x28]\0Amul x14, x12, x10\0Aumulh x10, x12, x10\0Alsr x12, x10, #63\0Aextr x10, x10, x14, #0x3f\0Aadds x15, x8, x14, lsl #1\0Amul x16, x13, x11\0Aumulh x11, x13, x11\0Alsr x13, x11, #63\0Aextr x11, x11, x16, #0x3f\0Aadd x14, x16, x14\0Aadd x8, x8, x14, lsl #1\0Aadcs x9, x9, x10\0Aadc x10, x13, x12\0Acmp x8, x15\0Acset w12, lo\0Aadds x9, x9, x11\0Acset w11, hs\0Aadds x9, x9, x12\0Aadc x10, x10, x11\0Astr x8, [${1:x}, #0x48]\0Aldp x12, x8, [${2:x}, #0x28]\0Aldr x11, [${2:x}, #0x20]\0Amul x13, x8, x11\0Aumulh x8, x8, x11\0Alsr x11, x8, #63\0Aextr x8, x8, x13, #0x3f\0Aadds x8, x10, x8\0Acinc x10, x11, hs\0Aadds x9, x9, x13, lsl #1\0Aadcs x8, x8, xzr\0Acset w11, hs\0Amul x13, x12, x12\0Aumulh x12, x12, x12\0Aadds x9, x9, x13\0Aadcs x8, x8, x12\0Aadc x10, x10, x11\0Astr x9, [${1:x}, #0x50]\0Aldp x9, x11, [${2:x}, #0x28]\0Amul x12, x11, x9\0Aumulh x9, x11, x9\0Alsr x11, x9, #63\0Aextr x9, x9, x12, #0x3f\0Aadds x13, x8, x12, lsl #1\0Aadds x9, x10, x9\0Astr x13, [${1:x}, #0x58]\0Aldr x10, [${2:x}, #0x30]\0Aumulh x13, x10, x10\0Aadc x11, x11, x13\0Acmn x8, x12, lsl #1\0Amul x8, x10, x10\0Aadcs x8, x9, x8\0Acinc x9, x11, hs\0Astp x8, x9, [${1:x}, #0x60]\0Acmp x9, #0\0Amov ${0:x}, #13\0Acinc ${0:x}, ${0:x}, ne", "=r,r,r,~{x2},~{x3},~{x4},~{x8},~{x9},~{x10},~{x11},~{x12},~{x13},~{x14},~{x15},~{x16},~{x17},~{memory},~{cc}"(i64 %rp, i64 %ap)
        ret i64 %size
    IR

  # Literal release/LTO schedule for runtime.c's always-inlined positive
  # eight-limb square. Preserve all thirty-six products, doubled cross terms,
  # carry order, sixteen stores, and +15/+16 header choice.
  fn __bigint_sqr8_exact(rp, ap) (i64 i64) i64
    ll <<~IR
      ; tungsten:alwaysinline
      entry:
        %size = call i64 asm sideeffect "ldr x8, [${2:x}]\0Amul x9, x8, x8\0Aumulh x8, x8, x8\0Astr x9, [${1:x}]\0Aldp x9, x10, [${2:x}]\0Amul x11, x10, x9\0Aumulh x9, x10, x9\0Alsr x10, x9, #63\0Aextr x9, x9, x11, #0x3f\0Aadds x8, x8, x11, lsl #1\0Aadcs x9, x9, xzr\0Astr x8, [${1:x}, #0x8]\0Aldp x12, x8, [${2:x}, #0x8]\0Aldr x11, [${2:x}]\0Amul x13, x8, x11\0Aumulh x8, x8, x11\0Alsr x11, x8, #63\0Aextr x8, x8, x13, #0x3f\0Aadcs x8, x8, x10\0Acinc x10, x11, hs\0Aadds x9, x9, x13, lsl #1\0Aadcs x8, x8, xzr\0Acset w11, hs\0Amul x13, x12, x12\0Aumulh x12, x12, x12\0Aadds x9, x9, x13\0Aadcs x8, x8, x12\0Aadc x10, x10, x11\0Astr x9, [${1:x}, #0x10]\0Aldp x9, x11, [${2:x}]\0Aldp x13, x12, [${2:x}, #0x10]\0Amul x14, x12, x9\0Aumulh x9, x12, x9\0Aextr x12, x9, x14, #0x3f\0Alsr x9, x9, #63\0Aadds x15, x8, x14, lsl #1\0Amul x16, x13, x11\0Aumulh x11, x13, x11\0Aextr x13, x11, x16, #0x3f\0Alsr x11, x11, #63\0Aadd x14, x16, x14\0Aadd x8, x8, x14, lsl #1\0Aadcs x10, x10, x12\0Aadc x9, x11, x9\0Acmp x8, x15\0Acset w11, lo\0Aadds x10, x10, x13\0Acset w12, hs\0Aadds x10, x10, x11\0Aadc x9, x9, x12\0Astr x8, [${1:x}, #0x18]\0Aldp x15, x8, [${2:x}, #0x18]\0Aldp x11, x12, [${2:x}]\0Amul x13, x8, x11\0Aumulh x8, x8, x11\0Alsr x11, x8, #63\0Aextr x8, x8, x13, #0x3f\0Aadds x14, x10, x13, lsl #1\0Aldr x16, [${2:x}, #0x10]\0Amul x17, x15, x12\0Aumulh x12, x15, x12\0Alsr x15, x12, #63\0Aextr x12, x12, x17, #0x3f\0Aadd x13, x17, x13\0Aadd x10, x10, x13, lsl #1\0Aadcs x8, x9, x8\0Aadc x9, x15, x11\0Acmp x10, x14\0Acset w11, lo\0Aadds x8, x8, x12\0Acset w12, hs\0Aadds x8, x8, x11\0Amul x11, x16, x16\0Aumulh x13, x16, x16\0Aadc x9, x9, x12\0Aadds x10, x10, x11\0Aadcs x8, x8, x13\0Acinc x9, x9, hs\0Astr x10, [${1:x}, #0x20]\0Aldp x10, x11, [${2:x}]\0Aldp x13, x12, [${2:x}, #0x20]\0Amul x14, x12, x10\0Aumulh x10, x12, x10\0Aextr x12, x10, x14, #0x3f\0Aadds x15, x8, x14, lsl #1\0Amul x16, x13, x11\0Aumulh x11, x13, x11\0Alsr x13, x11, #63\0Aextr x11, x11, x16, #0x3f\0Aldp x17, x2, [${2:x}, #0x10]\0Amul x3, x2, x17\0Aadd x14, x16, x14\0Aadd x16, x14, x3\0Aadd x14, x8, x14, lsl #1\0Aumulh x17, x2, x17\0Alsr x2, x17, #63\0Aadd x10, x13, x10, lsr #63\0Aadcs x9, x9, x12\0Aadc x10, x10, x2\0Acmp x14, x15\0Acset w12, lo\0Aadds x9, x9, x11\0Acset w11, hs\0Aadd x13, x8, x16, lsl #1\0Acmp x13, x14\0Acset w8, lo\0Aextr x14, x17, x3, #0x3f\0Aadds x9, x9, x12\0Aadc x10, x10, x11\0Aadds x9, x9, x14\0Acset w11, hs\0Aadds x8, x9, x8\0Aadc x9, x10, x11\0Astr x13, [${1:x}, #0x28]\0Aldp x15, x10, [${2:x}, #0x28]\0Aldp x11, x12, [${2:x}]\0Amul x13, x10, x11\0Aumulh x10, x10, x11\0Aextr x11, x10, x13, #0x3f\0Aadds x14, x8, x13, lsl #1\0Aldp x3, x16, [${2:x}, #0x18]\0Amul x17, x15, x12\0Aumulh x12, x15, x12\0Alsr x15, x12, #63\0Aextr x12, x12, x17, #0x3f\0Aldr x2, [${2:x}, #0x10]\0Amul x4, x16, x2\0Aadd x13, x17, x13\0Aadd x17, x13, x4\0Aadd x13, x8, x13, lsl #1\0Aumulh x16, x16, x2\0Alsr x2, x16, #63\0Aadd x10, x15, x10, lsr #63\0Aadcs x9, x9, x11\0Aadc x10, x10, x2\0Acmp x13, x14\0Acset w11, lo\0Aadds x9, x9, x12\0Acset w12, hs\0Aadd x8, x8, x17, lsl #1\0Acmp x8, x13\0Acset w13, lo\0Aextr x14, x16, x4, #0x3f\0Aadds x9, x9, x11\0Aadc x10, x10, x12\0Aadds x9, x9, x14\0Acset w11, hs\0Aadds x9, x9, x13\0Amul x12, x3, x3\0Aumulh x13, x3, x3\0Aadc x10, x10, x11\0Aadds x11, x8, x12\0Aadcs x8, x9, x13\0Acinc x9, x10, hs\0Astr x11, [${1:x}, #0x30]\0Aldp x10, x11, [${2:x}]\0Aldp x13, x12, [${2:x}, #0x30]\0Amul x14, x12, x10\0Aumulh x10, x12, x10\0Aextr x12, x10, x14, #0x3f\0Aadds x15, x8, x14, lsl #1\0Amul x16, x13, x11\0Aumulh x11, x13, x11\0Alsr x13, x11, #63\0Aextr x11, x11, x16, #0x3f\0Aldp x17, x2, [${2:x}, #0x10]\0Aldp x4, x3, [${2:x}, #0x20]\0Amul x5, x3, x17\0Aadd x14, x16, x14\0Aadd x16, x14, x5\0Aadd x14, x8, x14, lsl #1\0Aumulh x17, x3, x17\0Aumulh x3, x4, x2\0Alsr x6, x3, #63\0Aadd x10, x13, x10, lsr #63\0Aadd x10, x10, x17, lsr #63\0Aadcs x9, x9, x12\0Aadc x10, x10, x6\0Acmp x14, x15\0Acset w12, lo\0Aadds x9, x9, x11\0Acset w11, hs\0Aadd x13, x8, x16, lsl #1\0Acmp x13, x14\0Acset w14, lo\0Aadds x9, x9, x12\0Aextr x12, x17, x5, #0x3f\0Aadc x10, x10, x11\0Aadds x9, x9, x12\0Acset w11, hs\0Amul x12, x4, x2\0Aadd x15, x16, x12\0Aadd x15, x8, x15, lsl #1\0Acmp x15, x13\0Acset w8, lo\0Aadds x9, x9, x14\0Aextr x12, x3, x12, #0x3f\0Aadc x10, x10, x11\0Aadds x9, x9, x12\0Acset w11, hs\0Aadds x8, x9, x8\0Aadc x9, x10, x11\0Astr x15, [${1:x}, #0x38]\0Aldp x15, x10, [${2:x}, #0x30]\0Aldp x11, x12, [${2:x}, #0x8]\0Amul x13, x10, x11\0Aumulh x10, x10, x11\0Aextr x11, x10, x13, #0x3f\0Aadds x14, x8, x13, lsl #1\0Aldp x3, x16, [${2:x}, #0x20]\0Amul x17, x15, x12\0Aumulh x12, x15, x12\0Alsr x15, x12, #63\0Aextr x12, x12, x17, #0x3f\0Aldr x2, [${2:x}, #0x18]\0Amul x4, x16, x2\0Aadd x13, x17, x13\0Aadd x17, x13, x4\0Aadd x13, x8, x13, lsl #1\0Aumulh x16, x16, x2\0Alsr x2, x16, #63\0Aadd x10, x15, x10, lsr #63\0Aadcs x9, x9, x11\0Aadc x10, x10, x2\0Acmp x13, x14\0Acset w11, lo\0Aadds x9, x9, x12\0Acset w12, hs\0Aadd x8, x8, x17, lsl #1\0Acmp x8, x13\0Acset w13, lo\0Aadds x9, x9, x11\0Aextr x11, x16, x4, #0x3f\0Aadc x10, x10, x12\0Aadds x9, x9, x11\0Acset w11, hs\0Aadds x9, x9, x13\0Amul x12, x3, x3\0Aumulh x13, x3, x3\0Aadc x10, x10, x11\0Aadds x8, x8, x12\0Aadcs x9, x9, x13\0Acinc x10, x10, hs\0Astr x8, [${1:x}, #0x40]\0Aldp x8, x11, [${2:x}, #0x10]\0Aldp x13, x12, [${2:x}, #0x30]\0Amul x14, x12, x8\0Aumulh x8, x12, x8\0Aextr x12, x8, x14, #0x3f\0Aadds x15, x9, x14, lsl #1\0Amul x16, x13, x11\0Aumulh x11, x13, x11\0Alsr x13, x11, #63\0Aextr x11, x11, x16, #0x3f\0Aldp x17, x2, [${2:x}, #0x20]\0Amul x3, x2, x17\0Aadd x14, x16, x14\0Aadd x16, x14, x3\0Aadd x14, x9, x14, lsl #1\0Aumulh x17, x2, x17\0Alsr x2, x17, #63\0Aadd x8, x13, x8, lsr #63\0Aadcs x10, x10, x12\0Aadc x8, x8, x2\0Acmp x14, x15\0Acset w12, lo\0Aadds x10, x10, x11\0Acset w11, hs\0Aadd x9, x9, x16, lsl #1\0Acmp x9, x14\0Acset w13, lo\0Aadds x10, x10, x12\0Aextr x12, x17, x3, #0x3f\0Aadc x8, x8, x11\0Aadds x10, x10, x12\0Acset w11, hs\0Aadds x10, x10, x13\0Aadc x8, x8, x11\0Astr x9, [${1:x}, #0x48]\0Aldp x15, x9, [${2:x}, #0x30]\0Aldp x11, x12, [${2:x}, #0x18]\0Amul x13, x9, x11\0Aumulh x9, x9, x11\0Alsr x11, x9, #63\0Aextr x9, x9, x13, #0x3f\0Aadds x14, x10, x13, lsl #1\0Aldr x16, [${2:x}, #0x28]\0Amul x17, x15, x12\0Aumulh x12, x15, x12\0Alsr x15, x12, #63\0Aextr x12, x12, x17, #0x3f\0Aadd x13, x17, x13\0Aadd x10, x10, x13, lsl #1\0Aadcs x8, x8, x9\0Aadc x9, x15, x11\0Acmp x10, x14\0Acset w11, lo\0Aadds x8, x8, x12\0Acset w12, hs\0Aadds x8, x8, x11\0Amul x11, x16, x16\0Aumulh x13, x16, x16\0Aadc x9, x9, x12\0Aadds x10, x10, x11\0Aadcs x8, x8, x13\0Acinc x9, x9, hs\0Astr x10, [${1:x}, #0x50]\0Aldp x10, x11, [${2:x}, #0x20]\0Aldp x13, x12, [${2:x}, #0x30]\0Amul x14, x12, x10\0Aumulh x10, x12, x10\0Alsr x12, x10, #63\0Aextr x10, x10, x14, #0x3f\0Aadds x15, x8, x14, lsl #1\0Amul x16, x13, x11\0Aumulh x11, x13, x11\0Alsr x13, x11, #63\0Aextr x11, x11, x16, #0x3f\0Aadd x14, x16, x14\0Aadd x8, x8, x14, lsl #1\0Aadcs x9, x9, x10\0Aadc x10, x13, x12\0Acmp x8, x15\0Acset w12, lo\0Aadds x9, x9, x11\0Acset w11, hs\0Aadds x9, x9, x12\0Aadc x10, x10, x11\0Astr x8, [${1:x}, #0x58]\0Aldp x12, x8, [${2:x}, #0x30]\0Aldr x11, [${2:x}, #0x28]\0Amul x13, x8, x11\0Aumulh x8, x8, x11\0Alsr x11, x8, #63\0Aextr x8, x8, x13, #0x3f\0Aadds x8, x10, x8\0Acinc x10, x11, hs\0Aadds x9, x9, x13, lsl #1\0Aadcs x8, x8, xzr\0Acset w11, hs\0Amul x13, x12, x12\0Aumulh x12, x12, x12\0Aadds x9, x9, x13\0Aadcs x8, x8, x12\0Aadc x10, x10, x11\0Astr x9, [${1:x}, #0x60]\0Aldp x9, x11, [${2:x}, #0x30]\0Amul x12, x11, x9\0Aumulh x9, x11, x9\0Alsr x11, x9, #63\0Aextr x9, x9, x12, #0x3f\0Aadds x13, x8, x12, lsl #1\0Aadds x9, x10, x9\0Astr x13, [${1:x}, #0x68]\0Aldr x10, [${2:x}, #0x38]\0Aumulh x13, x10, x10\0Aadc x11, x11, x13\0Acmn x8, x12, lsl #1\0Amul x8, x10, x10\0Aadcs x8, x9, x8\0Acinc x9, x11, hs\0Astp x8, x9, [${1:x}, #0x70]\0Acmp x9, #0\0Amov ${0:x}, #15\0Acinc ${0:x}, ${0:x}, ne", "=r,r,r,~{x2},~{x3},~{x4},~{x5},~{x6},~{x7},~{x8},~{x9},~{x10},~{x11},~{x12},~{x13},~{x14},~{x15},~{x16},~{x17},~{memory},~{cc}"(i64 %rp, i64 %ap)
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

  # Literal current-C bn_add3_fixed schedule for positive equal-width add.
  # Keep the complete carry chain and delay all stores until both operand
  # pairs have been consumed, matching the retained differential oracle.
  fn __bigint_add3_equal_exact(rp, ap, bp) (i64 i64 i64) i64
    ll <<~IR
      ; tungsten:alwaysinline
      entry:
        %carry = call i64 asm sideeffect "ldp x4, x5, [${2:x}]\0Aldr x6, [${2:x}, #16]\0Aldp x8, x9, [${3:x}]\0Aldr x10, [${3:x}, #16]\0Aadds x12, x4, x8\0Aadcs x13, x5, x9\0Aadcs x14, x6, x10\0Astp x12, x13, [${1:x}]\0Astr x14, [${1:x}, #16]\0Acset ${0:x}, hs", "=r,r,r,r,~{x4},~{x5},~{x6},~{x8},~{x9},~{x10},~{x12},~{x13},~{x14},~{memory},~{cc}"(i64 %rp, i64 %ap, i64 %bp)
        ret i64 %carry
    IR

  # Literal current-C bn_add4_fixed / bn_add8_fixed / bn_add16_fixed
  # schedules for positive equal-width add. Each four-limb group loads both
  # operand quads, runs the carry chain, and stores the quad before the next
  # group's loads, exactly as the C kernels do; the carry-out is the flag.
  fn __bigint_add4_equal_exact(rp, ap, bp) (i64 i64 i64) i64
    ll <<~IR
      ; tungsten:noinline
      entry:
        %flag = call i64 asm sideeffect "ldp x4, x5, [${2:x}]\0Aldp x6, x7, [${2:x}, #16]\0Aldp x8, x9, [${3:x}]\0Aldp x10, x11, [${3:x}, #16]\0Aadds x12, x4, x8\0Aadcs x13, x5, x9\0Aadcs x14, x6, x10\0Aadcs x15, x7, x11\0Astp x12, x13, [${1:x}]\0Astp x14, x15, [${1:x}, #16]\0Acset ${0:x}, hs", "=r,r,r,r,~{x4},~{x5},~{x6},~{x7},~{x8},~{x9},~{x10},~{x11},~{x12},~{x13},~{x14},~{x15},~{memory},~{cc}"(i64 %rp, i64 %ap, i64 %bp)
        ret i64 %flag
    IR

  fn __bigint_add8_equal_exact(rp, ap, bp) (i64 i64 i64) i64
    ll <<~IR
      ; tungsten:noinline
      entry:
        %flag = call i64 asm sideeffect "ldp x4, x5, [${2:x}]\0Aldp x6, x7, [${2:x}, #16]\0Aldp x8, x9, [${3:x}]\0Aldp x10, x11, [${3:x}, #16]\0Aadds x12, x4, x8\0Aadcs x13, x5, x9\0Aadcs x14, x6, x10\0Aadcs x15, x7, x11\0Astp x12, x13, [${1:x}]\0Astp x14, x15, [${1:x}, #16]\0Aldp x4, x5, [${2:x}, #32]\0Aldp x6, x7, [${2:x}, #48]\0Aldp x8, x9, [${3:x}, #32]\0Aldp x10, x11, [${3:x}, #48]\0Aadcs x12, x4, x8\0Aadcs x13, x5, x9\0Aadcs x14, x6, x10\0Aadcs x15, x7, x11\0Astp x12, x13, [${1:x}, #32]\0Astp x14, x15, [${1:x}, #48]\0Acset ${0:x}, hs", "=r,r,r,r,~{x4},~{x5},~{x6},~{x7},~{x8},~{x9},~{x10},~{x11},~{x12},~{x13},~{x14},~{x15},~{memory},~{cc}"(i64 %rp, i64 %ap, i64 %bp)
        ret i64 %flag
    IR

  fn __bigint_add16_equal_exact(rp, ap, bp) (i64 i64 i64) i64
    ll <<~IR
      ; tungsten:noinline
      entry:
        %flag = call i64 asm sideeffect "ldp x4, x5, [${2:x}]\0Aldp x6, x7, [${2:x}, #16]\0Aldp x8, x9, [${3:x}]\0Aldp x10, x11, [${3:x}, #16]\0Aadds x12, x4, x8\0Aadcs x13, x5, x9\0Aadcs x14, x6, x10\0Aadcs x15, x7, x11\0Astp x12, x13, [${1:x}]\0Astp x14, x15, [${1:x}, #16]\0Aldp x4, x5, [${2:x}, #32]\0Aldp x6, x7, [${2:x}, #48]\0Aldp x8, x9, [${3:x}, #32]\0Aldp x10, x11, [${3:x}, #48]\0Aadcs x12, x4, x8\0Aadcs x13, x5, x9\0Aadcs x14, x6, x10\0Aadcs x15, x7, x11\0Astp x12, x13, [${1:x}, #32]\0Astp x14, x15, [${1:x}, #48]\0Aldp x4, x5, [${2:x}, #64]\0Aldp x6, x7, [${2:x}, #80]\0Aldp x8, x9, [${3:x}, #64]\0Aldp x10, x11, [${3:x}, #80]\0Aadcs x12, x4, x8\0Aadcs x13, x5, x9\0Aadcs x14, x6, x10\0Aadcs x15, x7, x11\0Astp x12, x13, [${1:x}, #64]\0Astp x14, x15, [${1:x}, #80]\0Aldp x4, x5, [${2:x}, #96]\0Aldp x6, x7, [${2:x}, #112]\0Aldp x8, x9, [${3:x}, #96]\0Aldp x10, x11, [${3:x}, #112]\0Aadcs x12, x4, x8\0Aadcs x13, x5, x9\0Aadcs x14, x6, x10\0Aadcs x15, x7, x11\0Astp x12, x13, [${1:x}, #96]\0Astp x14, x15, [${1:x}, #112]\0Acset ${0:x}, hs", "=r,r,r,r,~{x4},~{x5},~{x6},~{x7},~{x8},~{x9},~{x10},~{x11},~{x12},~{x13},~{x14},~{x15},~{memory},~{cc}"(i64 %rp, i64 %ap, i64 %bp)
        ret i64 %flag
    IR

  # Literal current-C bn_add24_fixed schedule (six four-limb groups).
  fn __bigint_add24_equal_exact(rp, ap, bp) (i64 i64 i64) i64
    ll <<~IR
      ; tungsten:noinline
      entry:
        %flag = call i64 asm sideeffect "ldp x4, x5, [${2:x}]\0Aldp x6, x7, [${2:x}, #16]\0Aldp x8, x9, [${3:x}]\0Aldp x10, x11, [${3:x}, #16]\0Aadds x12, x4, x8\0Aadcs x13, x5, x9\0Aadcs x14, x6, x10\0Aadcs x15, x7, x11\0Astp x12, x13, [${1:x}]\0Astp x14, x15, [${1:x}, #16]\0Aldp x4, x5, [${2:x}, #32]\0Aldp x6, x7, [${2:x}, #48]\0Aldp x8, x9, [${3:x}, #32]\0Aldp x10, x11, [${3:x}, #48]\0Aadcs x12, x4, x8\0Aadcs x13, x5, x9\0Aadcs x14, x6, x10\0Aadcs x15, x7, x11\0Astp x12, x13, [${1:x}, #32]\0Astp x14, x15, [${1:x}, #48]\0Aldp x4, x5, [${2:x}, #64]\0Aldp x6, x7, [${2:x}, #80]\0Aldp x8, x9, [${3:x}, #64]\0Aldp x10, x11, [${3:x}, #80]\0Aadcs x12, x4, x8\0Aadcs x13, x5, x9\0Aadcs x14, x6, x10\0Aadcs x15, x7, x11\0Astp x12, x13, [${1:x}, #64]\0Astp x14, x15, [${1:x}, #80]\0Aldp x4, x5, [${2:x}, #96]\0Aldp x6, x7, [${2:x}, #112]\0Aldp x8, x9, [${3:x}, #96]\0Aldp x10, x11, [${3:x}, #112]\0Aadcs x12, x4, x8\0Aadcs x13, x5, x9\0Aadcs x14, x6, x10\0Aadcs x15, x7, x11\0Astp x12, x13, [${1:x}, #96]\0Astp x14, x15, [${1:x}, #112]\0Aldp x4, x5, [${2:x}, #128]\0Aldp x6, x7, [${2:x}, #144]\0Aldp x8, x9, [${3:x}, #128]\0Aldp x10, x11, [${3:x}, #144]\0Aadcs x12, x4, x8\0Aadcs x13, x5, x9\0Aadcs x14, x6, x10\0Aadcs x15, x7, x11\0Astp x12, x13, [${1:x}, #128]\0Astp x14, x15, [${1:x}, #144]\0Aldp x4, x5, [${2:x}, #160]\0Aldp x6, x7, [${2:x}, #176]\0Aldp x8, x9, [${3:x}, #160]\0Aldp x10, x11, [${3:x}, #176]\0Aadcs x12, x4, x8\0Aadcs x13, x5, x9\0Aadcs x14, x6, x10\0Aadcs x15, x7, x11\0Astp x12, x13, [${1:x}, #160]\0Astp x14, x15, [${1:x}, #176]\0Acset ${0:x}, hs", "=r,r,r,r,~{x4},~{x5},~{x6},~{x7},~{x8},~{x9},~{x10},~{x11},~{x12},~{x13},~{x14},~{x15},~{memory},~{cc}"(i64 %rp, i64 %ap, i64 %bp)
        ret i64 %flag
    IR

  # Exact port of bigint_add_two_limb_magnitudes' same-sign arm: two limb
  # sums with explicit unsigned carries, both low limbs stored, and the
  # carry-out returned for the unconditional third-limb publication.
  fn __bigint_add2_equal_exact(rp, ap, bp) (i64 i64 i64) i64
    ll <<~IR
      ; tungsten:alwaysinline
      entry:
        %rq = inttoptr i64 %rp to ptr
        %aq = inttoptr i64 %ap to ptr
        %bq = inttoptr i64 %bp to ptr
        %a0 = load i64, ptr %aq, align 8
        %a1p = getelementptr inbounds i64, ptr %aq, i64 1
        %a1 = load i64, ptr %a1p, align 8
        %b0 = load i64, ptr %bq, align 8
        %b1p = getelementptr inbounds i64, ptr %bq, i64 1
        %b1 = load i64, ptr %b1p, align 8
        %low = add i64 %a0, %b0
        %carry_low = icmp ult i64 %low, %a0
        %high_sum = add i64 %a1, %b1
        %carry_high = icmp ult i64 %high_sum, %a1
        %carry_low_w = zext i1 %carry_low to i64
        %high = add i64 %high_sum, %carry_low_w
        %carry_high2 = icmp ult i64 %high, %high_sum
        %carry = or i1 %carry_high, %carry_high2
        store i64 %low, ptr %rq, align 8
        %r1p = getelementptr inbounds i64, ptr %rq, i64 1
        store i64 %high, ptr %r1p, align 8
        %carry_w = zext i1 %carry to i64
        ret i64 %carry_w
    IR

  # Literal current-C bn_sub{3,4,8,16,24}_fixed schedules for positive
  # equal-width magnitude subtraction (larger minus smaller). The borrow-out
  # flag is returned for parity with C, which discards it.

  fn __bigint_sub3_equal_exact(rp, ap, bp) (i64 i64 i64) i64
    ll <<~IR
      ; tungsten:noinline
      entry:
        %flag = call i64 asm sideeffect "ldp x4, x5, [${2:x}]\0Aldr x6, [${2:x}, #16]\0Aldp x8, x9, [${3:x}]\0Aldr x10, [${3:x}, #16]\0Asubs x12, x4, x8\0Asbcs x13, x5, x9\0Asbcs x14, x6, x10\0Astp x12, x13, [${1:x}]\0Astr x14, [${1:x}, #16]\0Amov ${0:x}, x14", "=r,r,r,r,~{x4},~{x5},~{x6},~{x7},~{x8},~{x9},~{x10},~{x11},~{x12},~{x13},~{x14},~{x15},~{memory},~{cc}"(i64 %rp, i64 %ap, i64 %bp)
        ret i64 %flag
    IR

  fn __bigint_sub4_equal_exact(rp, ap, bp) (i64 i64 i64) i64
    ll <<~IR
      ; tungsten:noinline
      entry:
        %flag = call i64 asm sideeffect "ldp x4, x5, [${2:x}]\0Aldp x6, x7, [${2:x}, #16]\0Aldp x8, x9, [${3:x}]\0Aldp x10, x11, [${3:x}, #16]\0Asubs x12, x4, x8\0Asbcs x13, x5, x9\0Asbcs x14, x6, x10\0Asbcs x15, x7, x11\0Astp x12, x13, [${1:x}]\0Astp x14, x15, [${1:x}, #16]\0Amov ${0:x}, x15", "=r,r,r,r,~{x4},~{x5},~{x6},~{x7},~{x8},~{x9},~{x10},~{x11},~{x12},~{x13},~{x14},~{x15},~{memory},~{cc}"(i64 %rp, i64 %ap, i64 %bp)
        ret i64 %flag
    IR

  fn __bigint_sub8_equal_exact(rp, ap, bp) (i64 i64 i64) i64
    ll <<~IR
      ; tungsten:noinline
      entry:
        %flag = call i64 asm sideeffect "ldp x4, x5, [${2:x}]\0Aldp x6, x7, [${2:x}, #16]\0Aldp x8, x9, [${3:x}]\0Aldp x10, x11, [${3:x}, #16]\0Asubs x12, x4, x8\0Asbcs x13, x5, x9\0Asbcs x14, x6, x10\0Asbcs x15, x7, x11\0Astp x12, x13, [${1:x}]\0Astp x14, x15, [${1:x}, #16]\0Aldp x4, x5, [${2:x}, #32]\0Aldp x6, x7, [${2:x}, #48]\0Aldp x8, x9, [${3:x}, #32]\0Aldp x10, x11, [${3:x}, #48]\0Asbcs x12, x4, x8\0Asbcs x13, x5, x9\0Asbcs x14, x6, x10\0Asbcs x15, x7, x11\0Astp x12, x13, [${1:x}, #32]\0Astp x14, x15, [${1:x}, #48]\0Amov ${0:x}, x15", "=r,r,r,r,~{x4},~{x5},~{x6},~{x7},~{x8},~{x9},~{x10},~{x11},~{x12},~{x13},~{x14},~{x15},~{memory},~{cc}"(i64 %rp, i64 %ap, i64 %bp)
        ret i64 %flag
    IR

  fn __bigint_sub16_equal_exact(rp, ap, bp) (i64 i64 i64) i64
    ll <<~IR
      ; tungsten:noinline
      entry:
        %flag = call i64 asm sideeffect "ldp x4, x5, [${2:x}]\0Aldp x6, x7, [${2:x}, #16]\0Aldp x8, x9, [${3:x}]\0Aldp x10, x11, [${3:x}, #16]\0Asubs x12, x4, x8\0Asbcs x13, x5, x9\0Asbcs x14, x6, x10\0Asbcs x15, x7, x11\0Astp x12, x13, [${1:x}]\0Astp x14, x15, [${1:x}, #16]\0Aldp x4, x5, [${2:x}, #32]\0Aldp x6, x7, [${2:x}, #48]\0Aldp x8, x9, [${3:x}, #32]\0Aldp x10, x11, [${3:x}, #48]\0Asbcs x12, x4, x8\0Asbcs x13, x5, x9\0Asbcs x14, x6, x10\0Asbcs x15, x7, x11\0Astp x12, x13, [${1:x}, #32]\0Astp x14, x15, [${1:x}, #48]\0Aldp x4, x5, [${2:x}, #64]\0Aldp x6, x7, [${2:x}, #80]\0Aldp x8, x9, [${3:x}, #64]\0Aldp x10, x11, [${3:x}, #80]\0Asbcs x12, x4, x8\0Asbcs x13, x5, x9\0Asbcs x14, x6, x10\0Asbcs x15, x7, x11\0Astp x12, x13, [${1:x}, #64]\0Astp x14, x15, [${1:x}, #80]\0Aldp x4, x5, [${2:x}, #96]\0Aldp x6, x7, [${2:x}, #112]\0Aldp x8, x9, [${3:x}, #96]\0Aldp x10, x11, [${3:x}, #112]\0Asbcs x12, x4, x8\0Asbcs x13, x5, x9\0Asbcs x14, x6, x10\0Asbcs x15, x7, x11\0Astp x12, x13, [${1:x}, #96]\0Astp x14, x15, [${1:x}, #112]\0Amov ${0:x}, x15", "=r,r,r,r,~{x4},~{x5},~{x6},~{x7},~{x8},~{x9},~{x10},~{x11},~{x12},~{x13},~{x14},~{x15},~{memory},~{cc}"(i64 %rp, i64 %ap, i64 %bp)
        ret i64 %flag
    IR

  fn __bigint_sub24_equal_exact(rp, ap, bp) (i64 i64 i64) i64
    ll <<~IR
      ; tungsten:noinline
      entry:
        %flag = call i64 asm sideeffect "ldp x4, x5, [${2:x}]\0Aldp x6, x7, [${2:x}, #16]\0Aldp x8, x9, [${3:x}]\0Aldp x10, x11, [${3:x}, #16]\0Asubs x12, x4, x8\0Asbcs x13, x5, x9\0Asbcs x14, x6, x10\0Asbcs x15, x7, x11\0Astp x12, x13, [${1:x}]\0Astp x14, x15, [${1:x}, #16]\0Aldp x4, x5, [${2:x}, #32]\0Aldp x6, x7, [${2:x}, #48]\0Aldp x8, x9, [${3:x}, #32]\0Aldp x10, x11, [${3:x}, #48]\0Asbcs x12, x4, x8\0Asbcs x13, x5, x9\0Asbcs x14, x6, x10\0Asbcs x15, x7, x11\0Astp x12, x13, [${1:x}, #32]\0Astp x14, x15, [${1:x}, #48]\0Aldp x4, x5, [${2:x}, #64]\0Aldp x6, x7, [${2:x}, #80]\0Aldp x8, x9, [${3:x}, #64]\0Aldp x10, x11, [${3:x}, #80]\0Asbcs x12, x4, x8\0Asbcs x13, x5, x9\0Asbcs x14, x6, x10\0Asbcs x15, x7, x11\0Astp x12, x13, [${1:x}, #64]\0Astp x14, x15, [${1:x}, #80]\0Aldp x4, x5, [${2:x}, #96]\0Aldp x6, x7, [${2:x}, #112]\0Aldp x8, x9, [${3:x}, #96]\0Aldp x10, x11, [${3:x}, #112]\0Asbcs x12, x4, x8\0Asbcs x13, x5, x9\0Asbcs x14, x6, x10\0Asbcs x15, x7, x11\0Astp x12, x13, [${1:x}, #96]\0Astp x14, x15, [${1:x}, #112]\0Aldp x4, x5, [${2:x}, #128]\0Aldp x6, x7, [${2:x}, #144]\0Aldp x8, x9, [${3:x}, #128]\0Aldp x10, x11, [${3:x}, #144]\0Asbcs x12, x4, x8\0Asbcs x13, x5, x9\0Asbcs x14, x6, x10\0Asbcs x15, x7, x11\0Astp x12, x13, [${1:x}, #128]\0Astp x14, x15, [${1:x}, #144]\0Aldp x4, x5, [${2:x}, #160]\0Aldp x6, x7, [${2:x}, #176]\0Aldp x8, x9, [${3:x}, #160]\0Aldp x10, x11, [${3:x}, #176]\0Asbcs x12, x4, x8\0Asbcs x13, x5, x9\0Asbcs x14, x6, x10\0Asbcs x15, x7, x11\0Astp x12, x13, [${1:x}, #160]\0Astp x14, x15, [${1:x}, #176]\0Amov ${0:x}, x15", "=r,r,r,r,~{x4},~{x5},~{x6},~{x7},~{x8},~{x9},~{x10},~{x11},~{x12},~{x13},~{x14},~{x15},~{memory},~{cc}"(i64 %rp, i64 %ap, i64 %bp)
        ret i64 %flag
    IR


  # Straight-line sbcs chains for the generic subtract widths 17..23 (C
  # runs its blocked bn_sub_n loop there): four-limb groups in the fixed
  # kernels' schedule, then a two- and/or one-limb remainder, no branches.
  fn __bigint_sub17_equal_exact(rp, ap, bp) (i64 i64 i64) i64
    ll <<~IR
      ; tungsten:noinline
      entry:
        %flag = call i64 asm sideeffect "ldp x4, x5, [${2:x}]\0Aldp x6, x7, [${2:x}, #16]\0Aldp x8, x9, [${3:x}]\0Aldp x10, x11, [${3:x}, #16]\0Asubs x12, x4, x8\0Asbcs x13, x5, x9\0Asbcs x14, x6, x10\0Asbcs x15, x7, x11\0Astp x12, x13, [${1:x}]\0Astp x14, x15, [${1:x}, #16]\0Aldp x4, x5, [${2:x}, #32]\0Aldp x6, x7, [${2:x}, #48]\0Aldp x8, x9, [${3:x}, #32]\0Aldp x10, x11, [${3:x}, #48]\0Asbcs x12, x4, x8\0Asbcs x13, x5, x9\0Asbcs x14, x6, x10\0Asbcs x15, x7, x11\0Astp x12, x13, [${1:x}, #32]\0Astp x14, x15, [${1:x}, #48]\0Aldp x4, x5, [${2:x}, #64]\0Aldp x6, x7, [${2:x}, #80]\0Aldp x8, x9, [${3:x}, #64]\0Aldp x10, x11, [${3:x}, #80]\0Asbcs x12, x4, x8\0Asbcs x13, x5, x9\0Asbcs x14, x6, x10\0Asbcs x15, x7, x11\0Astp x12, x13, [${1:x}, #64]\0Astp x14, x15, [${1:x}, #80]\0Aldp x4, x5, [${2:x}, #96]\0Aldp x6, x7, [${2:x}, #112]\0Aldp x8, x9, [${3:x}, #96]\0Aldp x10, x11, [${3:x}, #112]\0Asbcs x12, x4, x8\0Asbcs x13, x5, x9\0Asbcs x14, x6, x10\0Asbcs x15, x7, x11\0Astp x12, x13, [${1:x}, #96]\0Astp x14, x15, [${1:x}, #112]\0Aldr x4, [${2:x}, #128]\0Aldr x8, [${3:x}, #128]\0Asbcs x12, x4, x8\0Astr x12, [${1:x}, #128]\0Amov ${0:x}, x12", "=r,r,r,r,~{x4},~{x5},~{x6},~{x7},~{x8},~{x9},~{x10},~{x11},~{x12},~{x13},~{x14},~{x15},~{memory},~{cc}"(i64 %rp, i64 %ap, i64 %bp)
        ret i64 %flag
    IR

  fn __bigint_sub18_equal_exact(rp, ap, bp) (i64 i64 i64) i64
    ll <<~IR
      ; tungsten:noinline
      entry:
        %flag = call i64 asm sideeffect "ldp x4, x5, [${2:x}]\0Aldp x6, x7, [${2:x}, #16]\0Aldp x8, x9, [${3:x}]\0Aldp x10, x11, [${3:x}, #16]\0Asubs x12, x4, x8\0Asbcs x13, x5, x9\0Asbcs x14, x6, x10\0Asbcs x15, x7, x11\0Astp x12, x13, [${1:x}]\0Astp x14, x15, [${1:x}, #16]\0Aldp x4, x5, [${2:x}, #32]\0Aldp x6, x7, [${2:x}, #48]\0Aldp x8, x9, [${3:x}, #32]\0Aldp x10, x11, [${3:x}, #48]\0Asbcs x12, x4, x8\0Asbcs x13, x5, x9\0Asbcs x14, x6, x10\0Asbcs x15, x7, x11\0Astp x12, x13, [${1:x}, #32]\0Astp x14, x15, [${1:x}, #48]\0Aldp x4, x5, [${2:x}, #64]\0Aldp x6, x7, [${2:x}, #80]\0Aldp x8, x9, [${3:x}, #64]\0Aldp x10, x11, [${3:x}, #80]\0Asbcs x12, x4, x8\0Asbcs x13, x5, x9\0Asbcs x14, x6, x10\0Asbcs x15, x7, x11\0Astp x12, x13, [${1:x}, #64]\0Astp x14, x15, [${1:x}, #80]\0Aldp x4, x5, [${2:x}, #96]\0Aldp x6, x7, [${2:x}, #112]\0Aldp x8, x9, [${3:x}, #96]\0Aldp x10, x11, [${3:x}, #112]\0Asbcs x12, x4, x8\0Asbcs x13, x5, x9\0Asbcs x14, x6, x10\0Asbcs x15, x7, x11\0Astp x12, x13, [${1:x}, #96]\0Astp x14, x15, [${1:x}, #112]\0Aldp x4, x5, [${2:x}, #128]\0Aldp x8, x9, [${3:x}, #128]\0Asbcs x12, x4, x8\0Asbcs x13, x5, x9\0Astp x12, x13, [${1:x}, #128]\0Amov ${0:x}, x13", "=r,r,r,r,~{x4},~{x5},~{x6},~{x7},~{x8},~{x9},~{x10},~{x11},~{x12},~{x13},~{x14},~{x15},~{memory},~{cc}"(i64 %rp, i64 %ap, i64 %bp)
        ret i64 %flag
    IR

  fn __bigint_sub19_equal_exact(rp, ap, bp) (i64 i64 i64) i64
    ll <<~IR
      ; tungsten:noinline
      entry:
        %flag = call i64 asm sideeffect "ldp x4, x5, [${2:x}]\0Aldp x6, x7, [${2:x}, #16]\0Aldp x8, x9, [${3:x}]\0Aldp x10, x11, [${3:x}, #16]\0Asubs x12, x4, x8\0Asbcs x13, x5, x9\0Asbcs x14, x6, x10\0Asbcs x15, x7, x11\0Astp x12, x13, [${1:x}]\0Astp x14, x15, [${1:x}, #16]\0Aldp x4, x5, [${2:x}, #32]\0Aldp x6, x7, [${2:x}, #48]\0Aldp x8, x9, [${3:x}, #32]\0Aldp x10, x11, [${3:x}, #48]\0Asbcs x12, x4, x8\0Asbcs x13, x5, x9\0Asbcs x14, x6, x10\0Asbcs x15, x7, x11\0Astp x12, x13, [${1:x}, #32]\0Astp x14, x15, [${1:x}, #48]\0Aldp x4, x5, [${2:x}, #64]\0Aldp x6, x7, [${2:x}, #80]\0Aldp x8, x9, [${3:x}, #64]\0Aldp x10, x11, [${3:x}, #80]\0Asbcs x12, x4, x8\0Asbcs x13, x5, x9\0Asbcs x14, x6, x10\0Asbcs x15, x7, x11\0Astp x12, x13, [${1:x}, #64]\0Astp x14, x15, [${1:x}, #80]\0Aldp x4, x5, [${2:x}, #96]\0Aldp x6, x7, [${2:x}, #112]\0Aldp x8, x9, [${3:x}, #96]\0Aldp x10, x11, [${3:x}, #112]\0Asbcs x12, x4, x8\0Asbcs x13, x5, x9\0Asbcs x14, x6, x10\0Asbcs x15, x7, x11\0Astp x12, x13, [${1:x}, #96]\0Astp x14, x15, [${1:x}, #112]\0Aldp x4, x5, [${2:x}, #128]\0Aldp x8, x9, [${3:x}, #128]\0Asbcs x12, x4, x8\0Asbcs x13, x5, x9\0Astp x12, x13, [${1:x}, #128]\0Aldr x4, [${2:x}, #144]\0Aldr x8, [${3:x}, #144]\0Asbcs x12, x4, x8\0Astr x12, [${1:x}, #144]\0Amov ${0:x}, x12", "=r,r,r,r,~{x4},~{x5},~{x6},~{x7},~{x8},~{x9},~{x10},~{x11},~{x12},~{x13},~{x14},~{x15},~{memory},~{cc}"(i64 %rp, i64 %ap, i64 %bp)
        ret i64 %flag
    IR

  fn __bigint_sub20_equal_exact(rp, ap, bp) (i64 i64 i64) i64
    ll <<~IR
      ; tungsten:noinline
      entry:
        %flag = call i64 asm sideeffect "ldp x4, x5, [${2:x}]\0Aldp x6, x7, [${2:x}, #16]\0Aldp x8, x9, [${3:x}]\0Aldp x10, x11, [${3:x}, #16]\0Asubs x12, x4, x8\0Asbcs x13, x5, x9\0Asbcs x14, x6, x10\0Asbcs x15, x7, x11\0Astp x12, x13, [${1:x}]\0Astp x14, x15, [${1:x}, #16]\0Aldp x4, x5, [${2:x}, #32]\0Aldp x6, x7, [${2:x}, #48]\0Aldp x8, x9, [${3:x}, #32]\0Aldp x10, x11, [${3:x}, #48]\0Asbcs x12, x4, x8\0Asbcs x13, x5, x9\0Asbcs x14, x6, x10\0Asbcs x15, x7, x11\0Astp x12, x13, [${1:x}, #32]\0Astp x14, x15, [${1:x}, #48]\0Aldp x4, x5, [${2:x}, #64]\0Aldp x6, x7, [${2:x}, #80]\0Aldp x8, x9, [${3:x}, #64]\0Aldp x10, x11, [${3:x}, #80]\0Asbcs x12, x4, x8\0Asbcs x13, x5, x9\0Asbcs x14, x6, x10\0Asbcs x15, x7, x11\0Astp x12, x13, [${1:x}, #64]\0Astp x14, x15, [${1:x}, #80]\0Aldp x4, x5, [${2:x}, #96]\0Aldp x6, x7, [${2:x}, #112]\0Aldp x8, x9, [${3:x}, #96]\0Aldp x10, x11, [${3:x}, #112]\0Asbcs x12, x4, x8\0Asbcs x13, x5, x9\0Asbcs x14, x6, x10\0Asbcs x15, x7, x11\0Astp x12, x13, [${1:x}, #96]\0Astp x14, x15, [${1:x}, #112]\0Aldp x4, x5, [${2:x}, #128]\0Aldp x6, x7, [${2:x}, #144]\0Aldp x8, x9, [${3:x}, #128]\0Aldp x10, x11, [${3:x}, #144]\0Asbcs x12, x4, x8\0Asbcs x13, x5, x9\0Asbcs x14, x6, x10\0Asbcs x15, x7, x11\0Astp x12, x13, [${1:x}, #128]\0Astp x14, x15, [${1:x}, #144]\0Amov ${0:x}, x15", "=r,r,r,r,~{x4},~{x5},~{x6},~{x7},~{x8},~{x9},~{x10},~{x11},~{x12},~{x13},~{x14},~{x15},~{memory},~{cc}"(i64 %rp, i64 %ap, i64 %bp)
        ret i64 %flag
    IR

  fn __bigint_sub21_equal_exact(rp, ap, bp) (i64 i64 i64) i64
    ll <<~IR
      ; tungsten:noinline
      entry:
        %flag = call i64 asm sideeffect "ldp x4, x5, [${2:x}]\0Aldp x6, x7, [${2:x}, #16]\0Aldp x8, x9, [${3:x}]\0Aldp x10, x11, [${3:x}, #16]\0Asubs x12, x4, x8\0Asbcs x13, x5, x9\0Asbcs x14, x6, x10\0Asbcs x15, x7, x11\0Astp x12, x13, [${1:x}]\0Astp x14, x15, [${1:x}, #16]\0Aldp x4, x5, [${2:x}, #32]\0Aldp x6, x7, [${2:x}, #48]\0Aldp x8, x9, [${3:x}, #32]\0Aldp x10, x11, [${3:x}, #48]\0Asbcs x12, x4, x8\0Asbcs x13, x5, x9\0Asbcs x14, x6, x10\0Asbcs x15, x7, x11\0Astp x12, x13, [${1:x}, #32]\0Astp x14, x15, [${1:x}, #48]\0Aldp x4, x5, [${2:x}, #64]\0Aldp x6, x7, [${2:x}, #80]\0Aldp x8, x9, [${3:x}, #64]\0Aldp x10, x11, [${3:x}, #80]\0Asbcs x12, x4, x8\0Asbcs x13, x5, x9\0Asbcs x14, x6, x10\0Asbcs x15, x7, x11\0Astp x12, x13, [${1:x}, #64]\0Astp x14, x15, [${1:x}, #80]\0Aldp x4, x5, [${2:x}, #96]\0Aldp x6, x7, [${2:x}, #112]\0Aldp x8, x9, [${3:x}, #96]\0Aldp x10, x11, [${3:x}, #112]\0Asbcs x12, x4, x8\0Asbcs x13, x5, x9\0Asbcs x14, x6, x10\0Asbcs x15, x7, x11\0Astp x12, x13, [${1:x}, #96]\0Astp x14, x15, [${1:x}, #112]\0Aldp x4, x5, [${2:x}, #128]\0Aldp x6, x7, [${2:x}, #144]\0Aldp x8, x9, [${3:x}, #128]\0Aldp x10, x11, [${3:x}, #144]\0Asbcs x12, x4, x8\0Asbcs x13, x5, x9\0Asbcs x14, x6, x10\0Asbcs x15, x7, x11\0Astp x12, x13, [${1:x}, #128]\0Astp x14, x15, [${1:x}, #144]\0Aldr x4, [${2:x}, #160]\0Aldr x8, [${3:x}, #160]\0Asbcs x12, x4, x8\0Astr x12, [${1:x}, #160]\0Amov ${0:x}, x12", "=r,r,r,r,~{x4},~{x5},~{x6},~{x7},~{x8},~{x9},~{x10},~{x11},~{x12},~{x13},~{x14},~{x15},~{memory},~{cc}"(i64 %rp, i64 %ap, i64 %bp)
        ret i64 %flag
    IR

  fn __bigint_sub22_equal_exact(rp, ap, bp) (i64 i64 i64) i64
    ll <<~IR
      ; tungsten:noinline
      entry:
        %flag = call i64 asm sideeffect "ldp x4, x5, [${2:x}]\0Aldp x6, x7, [${2:x}, #16]\0Aldp x8, x9, [${3:x}]\0Aldp x10, x11, [${3:x}, #16]\0Asubs x12, x4, x8\0Asbcs x13, x5, x9\0Asbcs x14, x6, x10\0Asbcs x15, x7, x11\0Astp x12, x13, [${1:x}]\0Astp x14, x15, [${1:x}, #16]\0Aldp x4, x5, [${2:x}, #32]\0Aldp x6, x7, [${2:x}, #48]\0Aldp x8, x9, [${3:x}, #32]\0Aldp x10, x11, [${3:x}, #48]\0Asbcs x12, x4, x8\0Asbcs x13, x5, x9\0Asbcs x14, x6, x10\0Asbcs x15, x7, x11\0Astp x12, x13, [${1:x}, #32]\0Astp x14, x15, [${1:x}, #48]\0Aldp x4, x5, [${2:x}, #64]\0Aldp x6, x7, [${2:x}, #80]\0Aldp x8, x9, [${3:x}, #64]\0Aldp x10, x11, [${3:x}, #80]\0Asbcs x12, x4, x8\0Asbcs x13, x5, x9\0Asbcs x14, x6, x10\0Asbcs x15, x7, x11\0Astp x12, x13, [${1:x}, #64]\0Astp x14, x15, [${1:x}, #80]\0Aldp x4, x5, [${2:x}, #96]\0Aldp x6, x7, [${2:x}, #112]\0Aldp x8, x9, [${3:x}, #96]\0Aldp x10, x11, [${3:x}, #112]\0Asbcs x12, x4, x8\0Asbcs x13, x5, x9\0Asbcs x14, x6, x10\0Asbcs x15, x7, x11\0Astp x12, x13, [${1:x}, #96]\0Astp x14, x15, [${1:x}, #112]\0Aldp x4, x5, [${2:x}, #128]\0Aldp x6, x7, [${2:x}, #144]\0Aldp x8, x9, [${3:x}, #128]\0Aldp x10, x11, [${3:x}, #144]\0Asbcs x12, x4, x8\0Asbcs x13, x5, x9\0Asbcs x14, x6, x10\0Asbcs x15, x7, x11\0Astp x12, x13, [${1:x}, #128]\0Astp x14, x15, [${1:x}, #144]\0Aldp x4, x5, [${2:x}, #160]\0Aldp x8, x9, [${3:x}, #160]\0Asbcs x12, x4, x8\0Asbcs x13, x5, x9\0Astp x12, x13, [${1:x}, #160]\0Amov ${0:x}, x13", "=r,r,r,r,~{x4},~{x5},~{x6},~{x7},~{x8},~{x9},~{x10},~{x11},~{x12},~{x13},~{x14},~{x15},~{memory},~{cc}"(i64 %rp, i64 %ap, i64 %bp)
        ret i64 %flag
    IR

  fn __bigint_sub23_equal_exact(rp, ap, bp) (i64 i64 i64) i64
    ll <<~IR
      ; tungsten:noinline
      entry:
        %flag = call i64 asm sideeffect "ldp x4, x5, [${2:x}]\0Aldp x6, x7, [${2:x}, #16]\0Aldp x8, x9, [${3:x}]\0Aldp x10, x11, [${3:x}, #16]\0Asubs x12, x4, x8\0Asbcs x13, x5, x9\0Asbcs x14, x6, x10\0Asbcs x15, x7, x11\0Astp x12, x13, [${1:x}]\0Astp x14, x15, [${1:x}, #16]\0Aldp x4, x5, [${2:x}, #32]\0Aldp x6, x7, [${2:x}, #48]\0Aldp x8, x9, [${3:x}, #32]\0Aldp x10, x11, [${3:x}, #48]\0Asbcs x12, x4, x8\0Asbcs x13, x5, x9\0Asbcs x14, x6, x10\0Asbcs x15, x7, x11\0Astp x12, x13, [${1:x}, #32]\0Astp x14, x15, [${1:x}, #48]\0Aldp x4, x5, [${2:x}, #64]\0Aldp x6, x7, [${2:x}, #80]\0Aldp x8, x9, [${3:x}, #64]\0Aldp x10, x11, [${3:x}, #80]\0Asbcs x12, x4, x8\0Asbcs x13, x5, x9\0Asbcs x14, x6, x10\0Asbcs x15, x7, x11\0Astp x12, x13, [${1:x}, #64]\0Astp x14, x15, [${1:x}, #80]\0Aldp x4, x5, [${2:x}, #96]\0Aldp x6, x7, [${2:x}, #112]\0Aldp x8, x9, [${3:x}, #96]\0Aldp x10, x11, [${3:x}, #112]\0Asbcs x12, x4, x8\0Asbcs x13, x5, x9\0Asbcs x14, x6, x10\0Asbcs x15, x7, x11\0Astp x12, x13, [${1:x}, #96]\0Astp x14, x15, [${1:x}, #112]\0Aldp x4, x5, [${2:x}, #128]\0Aldp x6, x7, [${2:x}, #144]\0Aldp x8, x9, [${3:x}, #128]\0Aldp x10, x11, [${3:x}, #144]\0Asbcs x12, x4, x8\0Asbcs x13, x5, x9\0Asbcs x14, x6, x10\0Asbcs x15, x7, x11\0Astp x12, x13, [${1:x}, #128]\0Astp x14, x15, [${1:x}, #144]\0Aldp x4, x5, [${2:x}, #160]\0Aldp x8, x9, [${3:x}, #160]\0Asbcs x12, x4, x8\0Asbcs x13, x5, x9\0Astp x12, x13, [${1:x}, #160]\0Aldr x4, [${2:x}, #176]\0Aldr x8, [${3:x}, #176]\0Asbcs x12, x4, x8\0Astr x12, [${1:x}, #176]\0Amov ${0:x}, x12", "=r,r,r,r,~{x4},~{x5},~{x6},~{x7},~{x8},~{x9},~{x10},~{x11},~{x12},~{x13},~{x14},~{x15},~{memory},~{cc}"(i64 %rp, i64 %ap, i64 %bp)
        ret i64 %flag
    IR

  # Exact port of bigint_add_two_limb_magnitudes' opposite-sign arm
  # arithmetic (larger minus smaller over two limbs). Returns the pair as a
  # u128 (high limb in the upper half) so the raw finisher can apply C's
  # one-limb demotion or two-limb publication.
  fn __bigint_sub2_equal_magnitude(ap, bp) (i64 i64) u128
    ll <<~IR
      ; tungsten:alwaysinline
      entry:
        %aq = inttoptr i64 %ap to ptr
        %bq = inttoptr i64 %bp to ptr
        %a0 = load i64, ptr %aq, align 8
        %a1p = getelementptr inbounds i64, ptr %aq, i64 1
        %a1 = load i64, ptr %a1p, align 8
        %b0 = load i64, ptr %bq, align 8
        %b1p = getelementptr inbounds i64, ptr %bq, i64 1
        %b1 = load i64, ptr %b1p, align 8
        %low = sub i64 %a0, %b0
        %borrow = icmp ult i64 %a0, %b0
        %borrow_w = zext i1 %borrow to i64
        %high0 = sub i64 %a1, %b1
        %high = sub i64 %high0, %borrow_w
        %low128 = zext i64 %low to i128
        %high128 = zext i64 %high to i128
        %high_shifted = shl i128 %high128, 64
        %pair = or i128 %high_shifted, %low128
        ret i128 %pair
    IR

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
on macos && arm64
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

  fn __bigint_add3_equal_raw(a, b) (i64 i64) i64
    result = ccall_nobox("w_bigint_alloc_hot4_raw") ## i64
    mask = 140737488355327 ## i64
    rp = (result & mask) + 16 ## i64
    ap = (a & mask) + 16 ## i64
    bp = (b & mask) + 16 ## i64
    carry = __bigint_add3_equal_exact(rp, ap, bp) ## i64
    ccall_nobox("w_bigint_add3_equal_finish_raw", result, carry)

  # Exact C-shaped positive equal-width add@4: bigint_add_equal_fast takes the
  # hot buffer in the power-of-two class of 4+1 limbs, runs the fixed kernel,
  # publishes the carry limb unconditionally, and sizes the result 4 or 5.
  fn __bigint_add4_equal_raw(a, b) (i64 i64) i64
    result = ccall_nobox("w_bigint_alloc_hot8_raw") ## i64
    mask = 140737488355327 ## i64
    rp = (result & mask) + 16 ## i64
    ap = (a & mask) + 16 ## i64
    bp = (b & mask) + 16 ## i64
    carry = __bigint_add4_equal_exact(rp, ap, bp) ## i64
    ccall_nobox("w_bigint_add4_equal_finish_raw", result, carry)

  # Exact C-shaped positive equal-width add@8: bigint_add_equal_fast takes the
  # hot buffer in the power-of-two class of 8+1 limbs, runs the fixed kernel,
  # publishes the carry limb unconditionally, and sizes the result 8 or 9.
  fn __bigint_add8_equal_raw(a, b) (i64 i64) i64
    result = ccall_nobox("w_bigint_alloc_hot16_raw") ## i64
    mask = 140737488355327 ## i64
    rp = (result & mask) + 16 ## i64
    ap = (a & mask) + 16 ## i64
    bp = (b & mask) + 16 ## i64
    carry = __bigint_add8_equal_exact(rp, ap, bp) ## i64
    ccall_nobox("w_bigint_add8_equal_finish_raw", result, carry)

  # Exact C-shaped positive equal-width add@16: bigint_add_equal_fast takes the
  # hot buffer in the power-of-two class of 16+1 limbs, runs the fixed kernel,
  # publishes the carry limb unconditionally, and sizes the result 16 or 17.
  fn __bigint_add16_equal_raw(a, b) (i64 i64) i64
    result = ccall_nobox("w_bigint_alloc_hot32_exact_raw") ## i64
    mask = 140737488355327 ## i64
    rp = (result & mask) + 16 ## i64
    ap = (a & mask) + 16 ## i64
    bp = (b & mask) + 16 ## i64
    carry = __bigint_add16_equal_exact(rp, ap, bp) ## i64
    ccall_nobox("w_bigint_add16_equal_finish_raw", result, carry)

  # Exact C-shaped positive equal-width add@24: the hot buffer in the
  # power-of-two class of 25 limbs (32), the fixed kernel, the unconditional
  # carry-limb store, and a normalized size of 24 or 25.
  fn __bigint_add24_equal_raw(a, b) (i64 i64) i64
    result = ccall_nobox("w_bigint_alloc_hot32_exact_raw") ## i64
    mask = 140737488355327 ## i64
    rp = (result & mask) + 16 ## i64
    ap = (a & mask) + 16 ## i64
    bp = (b & mask) + 16 ## i64
    carry = __bigint_add24_equal_exact(rp, ap, bp) ## i64
    ccall_nobox("w_bigint_add24_equal_finish_raw", result, carry)

  # Exact C-shaped positive add@2 (bigint_add_two_limb_magnitudes, same-sign
  # arm): the exact hot class-four take, two limb sums, and the unconditional
  # third-limb publication with size two or three.
  fn __bigint_add2_equal_raw(a, b) (i64 i64) i64
    result = ccall_nobox("w_bigint_alloc_hot4_raw") ## i64
    mask = 140737488355327 ## i64
    rp = (result & mask) + 16 ## i64
    ap = (a & mask) + 16 ## i64
    bp = (b & mask) + 16 ## i64
    carry = __bigint_add2_equal_exact(rp, ap, bp) ## i64
    ccall_nobox("w_bigint_add2_equal_finish_raw", result, carry)

# Positive equal-width magnitude compare, exactly as C's boxed subtract
# entry orders it: the top limbs decide when they differ, otherwise the full
# descending limb scan (mag_cmp).
fn __bigint_equal_compare_raw(ap, bp, n) (i64 i64 i64) i64
  top_offset = (n - 1) * 8 ## i64
  atop = raw_load_u64(ap, top_offset) ## u64
  btop = raw_load_u64(bp, top_offset) ## u64
  compare = 0 ## i64
  if atop != btop
    if atop > btop
      compare = 1
    else
      compare = 0 - 1
    return compare
  k = n - 2 ## i64
  while k >= 0 && compare == 0
    xa = raw_load_u64(ap, k * 8) ## u64
    xb = raw_load_u64(bp, k * 8) ## u64
    if xa != xb
      if xa > xb
        compare = 1
      else
        compare = 0 - 1
    k -= 1
  compare

# Exact C-shaped positive equal-width sub@3 (bigint_sub_any's boxed equal
# route into bigint_sub_equal_fast): compare, the hot take in 3's
# smallest-fit class, the fixed kernel over larger minus smaller, then C's
# exact top-limb publication or trim-and-demote finisher.
on macos && arm64
  fn __bigint_sub3_equal_raw(a, b) (i64 i64) i64
    mask = 140737488355327 ## i64
    ap = (a & mask) + 16 ## i64
    bp = (b & mask) + 16 ## i64
    compare = __bigint_equal_compare_raw(ap, bp, 3) ## i64
    if compare == 0
      return ccall_nobox("w_int", 0)
    lp = ap
    sp = bp
    negative = 0 ## i64
    if compare < 0
      lp = bp
      sp = ap
      negative = 1
    result = ccall_nobox("w_bigint_alloc_hot4_raw") ## i64
    rp = (result & mask) + 16 ## i64
    top = __bigint_sub3_equal_exact(rp, lp, sp) ## i64
    ccall_nobox("w_bigint_sub_equal_top_finish_raw", result, 3, negative, top)

  # Exact C-shaped positive equal-width sub@4 (bigint_sub_any's boxed equal
  # route into bigint_sub_equal_fast): compare, the hot take in 4's
  # smallest-fit class, the fixed kernel over larger minus smaller, then C's
  # exact top-limb publication or trim-and-demote finisher.
  fn __bigint_sub4_equal_raw(a, b) (i64 i64) i64
    mask = 140737488355327 ## i64
    ap = (a & mask) + 16 ## i64
    bp = (b & mask) + 16 ## i64
    compare = __bigint_equal_compare_raw(ap, bp, 4) ## i64
    if compare == 0
      return ccall_nobox("w_int", 0)
    lp = ap
    sp = bp
    negative = 0 ## i64
    if compare < 0
      lp = bp
      sp = ap
      negative = 1
    result = ccall_nobox("w_bigint_alloc_hot4_raw") ## i64
    rp = (result & mask) + 16 ## i64
    top = __bigint_sub4_equal_exact(rp, lp, sp) ## i64
    ccall_nobox("w_bigint_sub_equal_top_finish_raw", result, 4, negative, top)

  # Exact C-shaped positive equal-width sub@8 (bigint_sub_any's boxed equal
  # route into bigint_sub_equal_fast): compare, the hot take in 8's
  # smallest-fit class, the fixed kernel over larger minus smaller, then C's
  # exact top-limb publication or trim-and-demote finisher.
  fn __bigint_sub8_equal_raw(a, b) (i64 i64) i64
    mask = 140737488355327 ## i64
    ap = (a & mask) + 16 ## i64
    bp = (b & mask) + 16 ## i64
    compare = __bigint_equal_compare_raw(ap, bp, 8) ## i64
    if compare == 0
      return ccall_nobox("w_int", 0)
    lp = ap
    sp = bp
    negative = 0 ## i64
    if compare < 0
      lp = bp
      sp = ap
      negative = 1
    result = ccall_nobox("w_bigint_alloc_hot8_raw") ## i64
    rp = (result & mask) + 16 ## i64
    top = __bigint_sub8_equal_exact(rp, lp, sp) ## i64
    ccall_nobox("w_bigint_sub_equal_top_finish_raw", result, 8, negative, top)

  # Exact C-shaped positive equal-width sub@16 (bigint_sub_any's boxed equal
  # route into bigint_sub_equal_fast): compare, the hot take in 16's
  # smallest-fit class, the fixed kernel over larger minus smaller, then C's
  # exact top-limb publication or trim-and-demote finisher.
  fn __bigint_sub16_equal_raw(a, b) (i64 i64) i64
    mask = 140737488355327 ## i64
    ap = (a & mask) + 16 ## i64
    bp = (b & mask) + 16 ## i64
    compare = __bigint_equal_compare_raw(ap, bp, 16) ## i64
    if compare == 0
      return ccall_nobox("w_int", 0)
    lp = ap
    sp = bp
    negative = 0 ## i64
    if compare < 0
      lp = bp
      sp = ap
      negative = 1
    result = ccall_nobox("w_bigint_alloc_hot16_raw") ## i64
    rp = (result & mask) + 16 ## i64
    top = __bigint_sub16_equal_exact(rp, lp, sp) ## i64
    ccall_nobox("w_bigint_sub_equal_top_finish_raw", result, 16, negative, top)

  # Exact C-shaped positive equal-width sub@24 (bigint_sub_any's boxed equal
  # route into bigint_sub_equal_fast): compare, the hot take in 24's
  # smallest-fit class, the fixed kernel over larger minus smaller, then C's
  # exact top-limb publication or trim-and-demote finisher.
  fn __bigint_sub24_equal_raw(a, b) (i64 i64) i64
    mask = 140737488355327 ## i64
    ap = (a & mask) + 16 ## i64
    bp = (b & mask) + 16 ## i64
    compare = __bigint_equal_compare_raw(ap, bp, 24) ## i64
    if compare == 0
      return ccall_nobox("w_int", 0)
    lp = ap
    sp = bp
    negative = 0 ## i64
    if compare < 0
      lp = bp
      sp = ap
      negative = 1
    result = ccall_nobox("w_bigint_alloc_hot32_exact_raw") ## i64
    rp = (result & mask) + 16 ## i64
    top = __bigint_sub24_equal_exact(rp, lp, sp) ## i64
    ccall_nobox("w_bigint_sub_equal_top_finish_raw", result, 24, negative, top)

  # Exact C-shaped positive sub@2 (bigint_add_two_limb_magnitudes,
  # opposite-sign arm): the two-limb compare, larger minus smaller, then C's
  # one-limb demotion or exact two-limb publication.
  fn __bigint_sub2_equal_raw(a, b) (i64 i64) i64
    mask = 140737488355327 ## i64
    ap = (a & mask) + 16 ## i64
    bp = (b & mask) + 16 ## i64
    a1 = raw_load_u64(ap, 8) ## u64
    b1 = raw_load_u64(bp, 8) ## u64
    compare = 0 ## i64
    if a1 != b1
      if a1 > b1
        compare = 1
      else
        compare = 0 - 1
    else
      a0 = raw_load_u64(ap, 0) ## u64
      b0 = raw_load_u64(bp, 0) ## u64
      if a0 > b0
        compare = 1
      else
        if a0 < b0
          compare = 0 - 1
    if compare == 0
      return ccall_nobox("w_int", 0)
    lp = ap
    sp = bp
    negative = 0 ## i64
    if compare < 0
      lp = bp
      sp = ap
      negative = 1
    pair = __bigint_sub2_equal_magnitude(lp, sp) ## u128
    low = pair ## u64
    high_wide = pair >> 64 ## u128
    high = high_wide ## u64
    ccall_nobox(
      "w_bigint_sub2_equal_finish_raw", low ## i64, high ## i64, negative
    )

# Hot take in C's capacity class for an equal-width result: the power of two
# above n (bigint_alloc_capacity rounds n+1 up; the subtract path's
# smallest-fit take lands in the same class for every width here).
fn __bigint_equal_class_alloc_raw(n) (i64) i64
  if n <= 7
    return ccall_nobox("w_bigint_alloc_hot8_raw") ## i64
  if n <= 15
    return ccall_nobox("w_bigint_alloc_hot16_raw") ## i64
  ccall_nobox("w_bigint_alloc_hot32_exact_raw") ## i64

# Positive equal-width add at the widths without a fixed C kernel (5..7,
# 9..15, 17..23). C runs its blocked bn_add_n loop from
# bigint_add_equal_fast; source takes the same hot class, runs the quad
# adcs loop, and publishes the carry limb unconditionally as C does.
fn __bigint_add_equal_generic_raw(a, b, n) (i64 i64 i64) i64
  result = __bigint_equal_class_alloc_raw(n) ## i64
  mask = 140737488355327 ## i64
  rp = (result & mask) + 16 ## i64
  ap = (a & mask) + 16 ## i64
  bp = (b & mask) + 16 ## i64
  carry = asm_add_no(rp, 0, ap, 0, bp, 0, n) ## i64
  ccall_nobox("w_bigint_add_equal_finish_raw", result, n, carry)

# Positive equal-width subtract at the same widths: C's boxed equal route
# (top-limb compare with the full scan on a tie, bn_sub_n over larger minus
# smaller, then top-limb publication or the trim-and-demote finisher).
on macos && arm64
  fn __bigint_sub_equal_generic_raw(a, b, n) (i64 i64 i64) i64
    mask = 140737488355327 ## i64
    ap = (a & mask) + 16 ## i64
    bp = (b & mask) + 16 ## i64
    compare = __bigint_equal_compare_raw(ap, bp, n) ## i64
    if compare == 0
      return ccall_nobox("w_int", 0)
    lp = ap
    sp = bp
    negative = 0 ## i64
    if compare < 0
      lp = bp
      sp = ap
      negative = 1
    result = __bigint_equal_class_alloc_raw(n) ## i64
    rp = (result & mask) + 16 ## i64
    # The quad loop holds parity through 15 limbs; from 17 its per-iteration
    # overhead measured 5-8% behind C's blocked loop, so those widths take
    # straight-line chains.
    if n >= 17
      top = 0 ## i64
      case n
        17 =>
          top = __bigint_sub17_equal_exact(rp, lp, sp) ## i64
        18 =>
          top = __bigint_sub18_equal_exact(rp, lp, sp) ## i64
        19 =>
          top = __bigint_sub19_equal_exact(rp, lp, sp) ## i64
        20 =>
          top = __bigint_sub20_equal_exact(rp, lp, sp) ## i64
        21 =>
          top = __bigint_sub21_equal_exact(rp, lp, sp) ## i64
        22 =>
          top = __bigint_sub22_equal_exact(rp, lp, sp) ## i64
        23 =>
          top = __bigint_sub23_equal_exact(rp, lp, sp) ## i64
      return ccall_nobox("w_bigint_sub_equal_top_finish_raw", result, n, negative, top)
    asm_sub_no(rp, 0, lp, 0, sp, 0, n)
    ccall_nobox("w_bigint_sub_equal_finish_raw", result, n, negative)

# Out-of-line generic body shared by BigInt#+ and BigInt#-: unequal
# widths, mixed signs, and the over-band bail. `an`/`bn` are the operands'
# effective signed sizes after the operator's own sign treatment (the -
# dispatcher passes `0 - bn0`), and `is_sub` selects the operator's C
# bails: + keeps C for equal-length pairs whose raw signs match (its
# equal-fast arm) and for the one-limb word arms; - keeps C for the
# equal-length pairs whose raw signs match, which after the flip are the
# opposite-effective-sign pairs. One raw function with two direct call
# sites: it stays out of line (a single-caller raw body was inlined back
# into its dispatcher, restoring the prologue this split removes), and a
# method call from inside the class went through the inline cache and cost
# the mixed-sign and skew shapes 15-25%. Plain if/else, never ternaries, for
# raw limb addresses, lengths, and result signs.
fn __bigint_addsub_general_raw(a, b, an, bn, is_sub) (i64 i64 i64 i64 i64) i64
  if is_sub == 0
    # The still-C-specialized one-limb neighbors return to the direct
    # BigInt tree before any generic magnitude/sign setup.
    if an == 1 || an == -1 || bn == 1 || bn == -1
      return ccall_nobox("w_bigint_add", a, b)
  am = an ## i64
  if an < 0
    am = 0 - an
  bm = bn ## i64
  if bn < 0
    bm = 0 - bn
  if am > 4096 || bm > 4096
    if is_sub == 0
      return ccall_nobox("w_add", a, b)
    return ccall_nobox("w_sub", a, b)
  mask = 140737488355312 ## i64
  pa = (a & mask) + 16 ## i64
  pb = (b & mask) + 16 ## i64
  if (an > 0) == (bn > 0)
    # Same effective sign: magnitude add. For + this is the raw-sign-equal
    # stratum, whose equal-length slice past the migrated band is C's
    # equal-fast domain; for - the raw signs differ and C has no such arm.
    if am == bm && is_sub == 0
      return ccall_nobox("w_bigint_add", a, b)
    lp = pa
    ll = am
    sp = pb
    sl = bm
    if am < bm
      lp = pb
      ll = bm
      sp = pa
      sl = am
    result = ccall_nobox("w_bigint_alloc_hot", ll + 1) ## i64
    rp = (result & mask) + 16 ## i64
    carry = asm_add_uneq(rp, lp, ll, sp, sl) ## i64
    negative = 0 ## i64
    if an < 0
      negative = 1
    return ccall_nobox(
      "w_bigint_uneq_add_finish_raw", result, ll, carry, negative
    )
  # Opposite effective signs: magnitude subtract, larger operand's sign
  # wins. For - the raw signs match, so the equal-length slice past the
  # migrated band is bigint_sub_equal_fast's domain.
  if am == bm && is_sub == 1
    return ccall_nobox("w_bigint_sub", a, b)
  cmp = 0 ## i64
  if am != bm
    if am > bm
      cmp = 1
    else
      cmp = 0 - 1
  else
    cmp = __bigint_equal_compare_raw(pa, pb, am) ## i64
  if cmp == 0
    return ccall_nobox("w_int", 0)
  bp2 = pa
  bl = am
  sp2 = pb
  sl2 = bm
  negative = 0 ## i64
  if an < 0
    negative = 1
  if cmp < 0
    bp2 = pb
    bl = bm
    sp2 = pa
    sl2 = am
    negative = 0
    if bn < 0
      negative = 1
  dresult = ccall_nobox("w_bigint_alloc_hot", bl) ## i64
  drp = (dresult & mask) + 16 ## i64
  asm_sub_uneq(drp, bp2, bl, sp2, sl2)
  signed_bl = bl ## i64
  if negative == 1
    signed_bl = 0 - bl
  ccall_nobox("w_bigint_seal_raw", dresult, signed_bl)

