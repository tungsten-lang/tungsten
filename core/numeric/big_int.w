-> __bigint_shr_u64(value, count) (u64 i64) u64
  value >> count

+ BigInt < Int
  - data
    # BigInt rides a dedicated top-level NaN-box tag (0xFFF8, v4), but WBigint retains its C header
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
    if am < 2 || bm < 2 || am > 24 || bm > 24
      return ccall("w_mul", self, other)
    # Squaring (identical boxed bits, flip included) keeps C's dedicated
    # square path, mirroring bigint_mul_src_shape's a == b exclusion.
    if $value == other$value
      return ccall("w_mul", self, other)

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

  # Division and modulo, source-routed for both-heap-BigInt pairs (any
  # signs and widths — the bodies pass every admitted shape to the same
  # kernel entry the C arm used, so the seam's bail set stays disjoint by
  # construction). The division SPECIALIZATION TREE (preinverse 2-by-1
  # divide, Burnikel-Ziegler recursion, Jebelean exact division, the
  # width-certified quotient/mod kernels) deliberately stays in the
  # runtime: porting it means writing and oracle-validating a new division
  # kernel from scratch, in the region where C's specialization density is
  # highest (assessed 2026-08-08, re-measured with these bodies — the
  # dispatch chain itself is toll-free within noise). The (Number)
  # catch-alls keep the polymorphic entries for rational/decimal/float
  # operands and int promotion.
  -> /(other)(BigInt)
    ccall("w_bigint_div", self, other)

  -> /(other)(Number)
    ccall("w_div", self, other)

  -> %(other)(BigInt)
    ccall("w_bigint_mod", self, other)

  -> %(other)(Number)
    ccall("w_mod", self, other)

  # Shifts route multi-limb BigInts through source while retaining the tuned
  # magnitude kernels behind reentry-free boundaries. The runtime gate keeps
  # ordinary one-limb and zero-shift specializations in C; header-only
  # overshifts are admitted at every width. Every admitted source shape reaches
  # one of these typed bodies exactly once.
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
    magnitude_limbs = n
    if magnitude_limbs < 0
      magnitude_limbs = 0 - magnitude_limbs
    int_tag = -1688849860263936 ## i64
    if k > 0
      if k >= magnitude_limbs * 64
        if n < 0
          return wvalue_from_bits((int_tag | 281474976710655) ## i64)
        return wvalue_from_bits(int_tag)
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

  # Greatest common divisor. The Lehmer/HGCD kernel stays in the runtime
  # (same tier as modpow's bigint_powmod_any); this override exists so the
  # method surface lives in source AND so dispatch never falls through to
  # Int#gcd's Euclidean remainder loop, which is catastrophically slower on
  # multi-limb receivers.
  -> gcd(other)
    ccall("w_bigint_gcd", self, other)

  # Least common multiple. The fused u64 and exact-division kernels stay
  # behind one exported boundary; composing the public gcd, division, and
  # multiplication methods here repeats dispatch and is materially slower
  # for small BigInts. The method surface itself is source-defined.
  -> lcm(other)
    ccall("w_bigint_lcm", self, other)

  # Primality. The small-screen / Mersenne Lucas-Lehmer / Proth / BPSW
  # policy rides the runtime kernel behind one exported boundary until
  # source code can index limbs directly; the method surface lives here.
  -> prime?
    ccall("w_bigint_prime_q", self)

  # Integer square root. The divide-and-conquer kernel (workspace-managed
  # sqrtrem over raw limbs) stays in the runtime; this override keeps the
  # method surface in source and shields BigInt receivers from Int#isqrt's
  # Newton loop, which would promote through full-width division at every
  # step. Negative receivers die inside the kernel with the shared message.
  -> isqrt
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

  # Conversion to Float: the correctly-rounded magnitude walk stays in the
  # runtime behind one exported boundary; the method surface lives here
  # (IC row 4 is retired).
  -> to_f
    ccall("w_bigint_to_f", self)

  # Conversion to String: the divide-and-conquer decimal writer and the
  # base-N chunk loop stay in the runtime behind one exported boundary;
  # the method surface lives here (IC row 0 is retired). Statically
  # :int-typed call sites keep the compiler's w_int_to_s intercept, and
  # print/interpolation paths use w_to_s directly — this body serves
  # dynamic dispatch.
  -> to_s(base = 10)
    ccall("w_bigint_to_s", self, base)
