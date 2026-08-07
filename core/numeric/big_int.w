
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
    # path ($limbs[i], and other$limbs[i] on a `## BigInt`-hinted receiver).
    # Element access is bounds-independent raw memory: every method owns its
    # own semantic bounds check against |$size| (or $capacity for writes).
    u64[] limbs

  -> zero?
    n = $size ## i64
    n == 0

  -> even?
    n = $size ## i64
    if n == 0
      return true
    low = $limbs[0] ## u64
    (low & 1) == 0

  -> odd?
    n = $size ## i64
    if n == 0
      return false
    low = $limbs[0] ## u64
    (low & 1) != 0

  # Sign predicates compose the header sign with the tag-sign overlay
  # (encoding v4): `-x` hands out the same buffer with bit 47 of the boxed
  # value flipped, so `$size` alone is the HEADER's sign, not the value's.
  # zero?/even?/odd? read magnitude/limb parity and need no composition.
  -> negative?
    n = $size ## i64
    if n == 0
      return false
    flip = (wvalue_bits(self) >> 47) & 1
    flip == 1 ? n > 0 : n < 0

  -> positive?
    n = $size ## i64
    if n == 0
      return false
    flip = (wvalue_bits(self) >> 47) & 1
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
    flip = (wvalue_bits(self) >> 47) & 1
    if flip == 1
      if n > 0
        $size = 0 - n
    else
      if n < 0
        $size = 0 - n
    self

  # Source-routed operators, DECLARATIVE-DISPATCH form (Phase 4): each
  # operator is a typed overload pair. The compiler rewrites the pair
  # into a synthesized dispatcher (exact-tag gate, Phase 1) plus renamed
  # workers; the weak seam (`__w_bigint_plus_src` / `_minus_src` /
  # `_times_src`) binds the (BigInt) WORKER directly — `bigint_src_shape`
  # already proved both operands, so the seam never re-runs the gate.
  # Explicit `x.+(y)` and every dynamic send run the dispatcher: BigInt
  # argument → fast worker, anything else → the (Number) catch-all, which
  # is the polymorphic C boundary (w_add — NEVER w_bigint_add: mixed
  # rational/decimal/complex operands need its full arm chain).
  #
  # The tag re-checks below STAY IN SOURCE and cost nothing: both entry
  # routes prove the operands (dispatcher gate / seam shape gate), so
  # Phase 3's known-bits fold deletes them from the emitted code — and
  # TUNGSTEN_TAG_ASSERT=1 re-arms every one of them as a trap for the
  # differential oracle. NEVER apply infix `+`/`-` to bigint operands in
  # these bodies — that re-enters the arm; compose exported boundaries.
  #
  # Kernel history (why the bodies look like this): SEVEN kernel bodies
  # were measured and rejected under the 5% budget before the fused
  # asm_{add,sub}_uneq form won on the unequal-length arm. The C kernels
  # are dispatch trees of fully-inlined specializations (identity,
  # one-limb, equal-length, word-shape, mutate-in-place, hot-slot reuse);
  # migration proceeds arm by arm, each with its own gate. See
  # benchmarks/runtime_ports/README.md.
  -> +(other)(BigInt)
    if (wvalue_bits(self) & -281474976710656) != -2251799813685248
      return ccall("w_add", self, other)
    if (wvalue_bits(other) & -281474976710656) != -2251799813685248
      return ccall("w_add", self, other)
    an = $size ## i64
    if ((wvalue_bits(self) >> 47) & 1) == 1
      an = 0 - an
    o = other ## BigInt
    bn = o$size ## i64
    if ((wvalue_bits(other) >> 47) & 1) == 1
      bn = 0 - bn
    if an == 0 || bn == 0
      return ccall("w_add", self, other)
    am = an < 0 ? 0 - an : an
    bm = bn < 0 ? 0 - bn : bn
    if am > 4096 || bm > 4096
      return ccall("w_add", self, other)
    mask = 140737488355312
    pa = (wvalue_bits(self) & mask) + 16
    pb = (wvalue_bits(other) & mask) + 16

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
      result = ccall("w_bigint_alloc_boxed", ll + 1)
      rp = (wvalue_bits(result) & mask) + 16
      carry = asm_add_uneq(rp ## i64, lp ## i64, ll ## i64, sp ## i64, sl ## i64) ## u64
      n = ll
      if carry != 0
        r = result ## BigInt
        r$limbs[ll] = carry
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
        xb = o$limbs[k] ## u64
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
    drp = (wvalue_bits(dresult) & mask) + 16
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
    if (wvalue_bits(self) & -281474976710656) != -2251799813685248
      return ccall("w_sub", self, other)
    if (wvalue_bits(other) & -281474976710656) != -2251799813685248
      return ccall("w_sub", self, other)
    an = $size ## i64
    if ((wvalue_bits(self) >> 47) & 1) == 1
      an = 0 - an
    o = other ## BigInt
    bn0 = o$size ## i64
    if ((wvalue_bits(other) >> 47) & 1) == 1
      bn0 = 0 - bn0
    bn = 0 - bn0
    if an == 0 || bn == 0
      return ccall("w_sub", self, other)
    am = an < 0 ? 0 - an : an
    bm = bn < 0 ? 0 - bn : bn
    if am > 4096 || bm > 4096
      return ccall("w_sub", self, other)
    mask = 140737488355312
    pa = (wvalue_bits(self) & mask) + 16
    pb = (wvalue_bits(other) & mask) + 16

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
      result = ccall("w_bigint_alloc_boxed", ll + 1)
      rp = (wvalue_bits(result) & mask) + 16
      carry = asm_add_uneq(rp ## i64, lp ## i64, ll ## i64, sp ## i64, sl ## i64) ## u64
      n = ll
      if carry != 0
        r = result ## BigInt
        r$limbs[ll] = carry
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
        xb = o$limbs[k] ## u64
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
    drp = (wvalue_bits(dresult) & mask) + 16
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
    if (wvalue_bits(self) & -281474976710656) != -2251799813685248
      return ccall("w_mul", self, other)
    if (wvalue_bits(other) & -281474976710656) != -2251799813685248
      return ccall("w_mul", self, other)
    an = $size ## i64
    if ((wvalue_bits(self) >> 47) & 1) == 1
      an = 0 - an
    o = other ## BigInt
    bn = o$size ## i64
    if ((wvalue_bits(other) >> 47) & 1) == 1
      bn = 0 - bn
    if an == 0 || bn == 0
      return ccall("w_mul", self, other)
    am = an < 0 ? 0 - an : an
    bm = bn < 0 ? 0 - bn : bn
    if am < 2 || bm < 2 || am > 24 || bm > 24
      return ccall("w_mul", self, other)
    mask = 140737488355312
    pa = (wvalue_bits(self) & mask) + 16
    pb = (wvalue_bits(other) & mask) + 16
    total = am + bm
    result = ccall("w_bigint_alloc_boxed", total)
    rp = (wvalue_bits(result) & mask) + 16
    asm_mulbase(rp ## i64, 0, pa ## i64, 0, pb ## i64, 0, am ## i64, bm ## i64)
    neg = false
    if (an < 0) != (bn < 0)
      neg = true
    ccall("w_bigint_seal", result, neg ? 0 - total : total)

  -> *(other)(Number)
    ccall("w_mul", self, other)

  # Greatest common divisor. The Lehmer/HGCD kernel stays in the runtime
  # (same tier as modpow's bigint_powmod_any); this override exists so the
  # method surface lives in source AND so dispatch never falls through to
  # Int#gcd's Euclidean remainder loop, which is catastrophically slower on
  # multi-limb receivers.
  -> gcd(other)
    ccall("w_bigint_gcd", self, other)

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
    flip = (wvalue_bits(self) >> 47) & 1
    if flip == 1 ? n < 0 : n > 0
      return self
    ccall("w_bigint_mark_shared_value", self)
    wvalue_from_bits(wvalue_bits(self) ^ 140737488355328)

  # Conversion to the already-integral representation is receiver identity.
  # Do not normalize: callers can observe exact heap identity.
  -> to_i
    self
