# Complete raw integer comparison for every pair containing at least one
# BigInt. The caller establishes that both WValues are integers. Inline i48
# operands become zero/one-limb magnitudes; BigInt sign composes the signed
# header with the tag overlay. Equal-width magnitudes use a paired backward
# scan, halving loop branches across long shared prefixes.
fn __bigint_compare_raw(a, b) (i64 i64) i64
  ll <<~IR
    entry:
      %axor = xor i64 %a, -1407374883553280
      %bxor = xor i64 %b, -1407374883553280
      %abor = or i64 %axor, %bxor
      %abtag = and i64 %abor, -140737488355328
      %bothpostag = icmp eq i64 %abtag, 0
      br i1 %bothpostag, label %fast.hdr, label %slow.entry

    fast.hdr:
      %fapbits = and i64 %a, 140737488355327
      %fbpbits = and i64 %b, 140737488355327
      %fap = inttoptr i64 %fapbits to ptr
      %fbp = inttoptr i64 %fbpbits to ptr
      %fasp = getelementptr i8, ptr %fap, i64 4
      %fbsp = getelementptr i8, ptr %fbp, i64 4
      %fasz32 = load i32, ptr %fasp, align 4
      %fbsz32 = load i32, ptr %fbsp, align 4
      %faspos = icmp sgt i32 %fasz32, 0
      %fbspos = icmp sgt i32 %fbsz32, 0
      %fbothpos = and i1 %faspos, %fbspos
      br i1 %fbothpos, label %fast.len, label %slow.entry

    fast.len:
      %fszeq = icmp eq i32 %fasz32, %fbsz32
      br i1 %fszeq, label %fast.eqlen, label %fast.difflen

    fast.difflen:
      %fszgt = icmp sgt i32 %fasz32, %fbsz32
      %fszcmp = select i1 %fszgt, i64 1, i64 -1
      ret i64 %fszcmp

    fast.eqlen:
      %fal = getelementptr i8, ptr %fap, i64 16
      %fbl = getelementptr i8, ptr %fbp, i64 16
      switch i32 %fasz32, label %fast.wide [
        i32 1, label %fast.1
        i32 2, label %fast.2
        i32 3, label %fast.3
        i32 4, label %fast.4
      ]

    fast.4:
      %fa3p = getelementptr i64, ptr %fal, i64 3
      %fb3p = getelementptr i64, ptr %fbl, i64 3
      %fa3 = load i64, ptr %fa3p, align 8
      %fb3 = load i64, ptr %fb3p, align 8
      %feq3 = icmp eq i64 %fa3, %fb3
      br i1 %feq3, label %fast.3, label %fast.4.diff
    fast.4.diff:
      %fgt3 = icmp ugt i64 %fa3, %fb3
      %fcmp3 = select i1 %fgt3, i64 1, i64 -1
      ret i64 %fcmp3

    fast.3:
      %fa2p = getelementptr i64, ptr %fal, i64 2
      %fb2p = getelementptr i64, ptr %fbl, i64 2
      %fa2 = load i64, ptr %fa2p, align 8
      %fb2 = load i64, ptr %fb2p, align 8
      %feq2 = icmp eq i64 %fa2, %fb2
      br i1 %feq2, label %fast.2, label %fast.3.diff
    fast.3.diff:
      %fgt2 = icmp ugt i64 %fa2, %fb2
      %fcmp2 = select i1 %fgt2, i64 1, i64 -1
      ret i64 %fcmp2

    fast.2:
      %fa1p = getelementptr i64, ptr %fal, i64 1
      %fb1p = getelementptr i64, ptr %fbl, i64 1
      %fa1 = load i64, ptr %fa1p, align 8
      %fb1 = load i64, ptr %fb1p, align 8
      %feq1 = icmp eq i64 %fa1, %fb1
      br i1 %feq1, label %fast.1, label %fast.2.diff
    fast.2.diff:
      %fgt1 = icmp ugt i64 %fa1, %fb1
      %fcmp1 = select i1 %fgt1, i64 1, i64 -1
      ret i64 %fcmp1

    fast.1:
      %fa0 = load i64, ptr %fal, align 8
      %fb0 = load i64, ptr %fbl, align 8
      %feq0 = icmp eq i64 %fa0, %fb0
      br i1 %feq0, label %ret.zero, label %fast.1.diff
    fast.1.diff:
      %fgt0 = icmp ugt i64 %fa0, %fb0
      %fcmp0 = select i1 %fgt0, i64 1, i64 -1
      ret i64 %fcmp0

    fast.wide:
      %fsame = icmp eq i64 %a, %b
      br i1 %fsame, label %ret.zero, label %fast.wide.scan
    fast.wide.scan:
      %falen = zext i32 %fasz32 to i64
      br label %scan.parity

    slow.entry:
      %same = icmp eq i64 %a, %b
      br i1 %same, label %ret.zero, label %a.kind

    a.kind:
      %atag = and i64 %a, -281474976710656
      %aisbig = icmp eq i64 %atag, -1407374883553280
      br i1 %aisbig, label %a.big, label %a.int
    a.big:
      %apbits = and i64 %a, 140737488355327
      %ap = inttoptr i64 %apbits to ptr
      %asp = getelementptr i8, ptr %ap, i64 4
      %asz32 = load i32, ptr %asp, align 4
      %asz = sext i32 %asz32 to i64
      %aflipbits = and i64 %a, 140737488355328
      %aflip = icmp ne i64 %aflipbits, 0
      %anegsz = sub i64 0, %asz
      %aeff = select i1 %aflip, i64 %anegsz, i64 %asz
      %abneg = icmp slt i64 %aeff, 0
      %abnegmask = ashr i64 %asz, 63
      %abxor = xor i64 %asz, %abnegmask
      %ablen = sub i64 %abxor, %abnegmask
      %alimbp = getelementptr i8, ptr %ap, i64 16
      br label %b.kind
    a.int:
      %ashl = shl i64 %a, 16
      %ai = ashr i64 %ashl, 16
      %aineg = icmp slt i64 %ai, 0
      %aimask = ashr i64 %ai, 63
      %aixor = xor i64 %ai, %aimask
      %aimag = sub i64 %aixor, %aimask
      %aizero = icmp eq i64 %aimag, 0
      %ailen = select i1 %aizero, i64 0, i64 1
      br label %b.kind

    b.kind:
      %saneg = phi i1 [ %abneg, %a.big ], [ %aineg, %a.int ]
      %salen = phi i64 [ %ablen, %a.big ], [ %ailen, %a.int ]
      %amag = phi i64 [ 0, %a.big ], [ %aimag, %a.int ]
      %sal = phi ptr [ %alimbp, %a.big ], [ null, %a.int ]
      %btag = and i64 %b, -281474976710656
      %bisbig = icmp eq i64 %btag, -1407374883553280
      br i1 %bisbig, label %b.big, label %b.int
    b.big:
      %bpbits = and i64 %b, 140737488355327
      %bp = inttoptr i64 %bpbits to ptr
      %bsp = getelementptr i8, ptr %bp, i64 4
      %bsz32 = load i32, ptr %bsp, align 4
      %bsz = sext i32 %bsz32 to i64
      %bflipbits = and i64 %b, 140737488355328
      %bflip = icmp ne i64 %bflipbits, 0
      %bnegsz = sub i64 0, %bsz
      %beff = select i1 %bflip, i64 %bnegsz, i64 %bsz
      %bbneg = icmp slt i64 %beff, 0
      %bbnegmask = ashr i64 %bsz, 63
      %bbxor = xor i64 %bsz, %bbnegmask
      %bblen = sub i64 %bbxor, %bbnegmask
      %blimbp = getelementptr i8, ptr %bp, i64 16
      br label %compare.sign
    b.int:
      %bshl = shl i64 %b, 16
      %bi = ashr i64 %bshl, 16
      %bineg = icmp slt i64 %bi, 0
      %bimask = ashr i64 %bi, 63
      %bixor = xor i64 %bi, %bimask
      %bimag = sub i64 %bixor, %bimask
      %bizero = icmp eq i64 %bimag, 0
      %bilen = select i1 %bizero, i64 0, i64 1
      br label %compare.sign

    compare.sign:
      %bneg = phi i1 [ %bbneg, %b.big ], [ %bineg, %b.int ]
      %blen = phi i64 [ %bblen, %b.big ], [ %bilen, %b.int ]
      %bmag = phi i64 [ 0, %b.big ], [ %bimag, %b.int ]
      %sbl = phi ptr [ %blimbp, %b.big ], [ null, %b.int ]
      %signsdiff = xor i1 %saneg, %bneg
      br i1 %signsdiff, label %ret.sign, label %compare.length
    ret.sign:
      %signcmp = select i1 %saneg, i64 -1, i64 1
      ret i64 %signcmp

    compare.length:
      %lendiff = icmp ne i64 %salen, %blen
      br i1 %lendiff, label %ret.length, label %compare.zero
    ret.length:
      %lengreater = icmp ugt i64 %salen, %blen
      %lencmp = select i1 %lengreater, i64 1, i64 -1
      %neglencmp = sub i64 0, %lencmp
      %finallencmp = select i1 %saneg, i64 %neglencmp, i64 %lencmp
      ret i64 %finallencmp

    compare.zero:
      %bothzero = icmp eq i64 %salen, 0
      br i1 %bothzero, label %ret.zero, label %compare.one
    compare.one:
      %isone = icmp eq i64 %salen, 1
      br i1 %isone, label %one.load.a, label %scan.setup
    one.load.a:
      br i1 %aisbig, label %one.a.big, label %one.a.int
    one.a.big:
      %aone = load i64, ptr %sal, align 8
      br label %one.load.b
    one.a.int:
      br label %one.load.b
    one.load.b:
      %avone = phi i64 [ %aone, %one.a.big ], [ %amag, %one.a.int ]
      br i1 %bisbig, label %one.b.big, label %one.b.int
    one.b.big:
      %bone = load i64, ptr %sbl, align 8
      br label %one.compare
    one.b.int:
      br label %one.compare
    one.compare:
      %bvone = phi i64 [ %bone, %one.b.big ], [ %bmag, %one.b.int ]
      %oneeq = icmp eq i64 %avone, %bvone
      br i1 %oneeq, label %ret.zero, label %one.result
    one.result:
      %onegt = icmp ugt i64 %avone, %bvone
      %onecmp = select i1 %onegt, i64 1, i64 -1
      %negonecmp = sub i64 0, %onecmp
      %finalonecmp = select i1 %saneg, i64 %negonecmp, i64 %onecmp
      ret i64 %finalonecmp

    scan.setup:
      %istwo = icmp eq i64 %salen, 2
      br i1 %istwo, label %two.high, label %scan.parity
    two.high:
      %atwop = getelementptr i64, ptr %sal, i64 1
      %btwop = getelementptr i64, ptr %sbl, i64 1
      %atwo = load i64, ptr %atwop, align 8
      %btwo = load i64, ptr %btwop, align 8
      %twohieq = icmp eq i64 %atwo, %btwo
      br i1 %twohieq, label %two.low, label %two.high.result
    two.high.result:
      %twohigt = icmp ugt i64 %atwo, %btwo
      %twohicmp = select i1 %twohigt, i64 1, i64 -1
      br label %ret.mag
    two.low:
      %atwolow = load i64, ptr %sal, align 8
      %btwolow = load i64, ptr %sbl, align 8
      %twoloweq = icmp eq i64 %atwolow, %btwolow
      br i1 %twoloweq, label %ret.zero, label %two.low.result
    two.low.result:
      %twolowgt = icmp ugt i64 %atwolow, %btwolow
      %twolowcmp = select i1 %twolowgt, i64 1, i64 -1
      br label %ret.mag

    scan.parity:
      %aneg = phi i1 [ false, %fast.wide.scan ], [ %saneg, %scan.setup ]
      %alen = phi i64 [ %falen, %fast.wide.scan ], [ %salen, %scan.setup ]
      %al = phi ptr [ %fal, %fast.wide.scan ], [ %sal, %scan.setup ]
      %bl = phi ptr [ %fbl, %fast.wide.scan ], [ %sbl, %scan.setup ]
      %oddmask = and i64 %alen, 1
      %isodd = icmp ne i64 %oddmask, 0
      br i1 %isodd, label %scan.odd, label %scan.loop.pre
    scan.odd:
      %topi = sub i64 %alen, 1
      %atopp = getelementptr i64, ptr %al, i64 %topi
      %btopp = getelementptr i64, ptr %bl, i64 %topi
      %atop = load i64, ptr %atopp, align 8
      %btop = load i64, ptr %btopp, align 8
      %topeq = icmp eq i64 %atop, %btop
      br i1 %topeq, label %scan.loop.pre, label %scan.odd.result
    scan.odd.result:
      %topgt = icmp ugt i64 %atop, %btop
      %topcmp = select i1 %topgt, i64 1, i64 -1
      br label %ret.mag
    scan.loop.pre:
      %evenstart = sub i64 %alen, 1
      %oddstart = sub i64 %alen, 2
      %start = select i1 %isodd, i64 %oddstart, i64 %evenstart
      br label %scan.loop
    scan.loop:
      %idx = phi i64 [ %start, %scan.loop.pre ], [ %next, %scan.next ]
      %loidx = sub i64 %idx, 1
      %ahp = getelementptr i64, ptr %al, i64 %idx
      %bhp = getelementptr i64, ptr %bl, i64 %idx
      %alp = getelementptr i64, ptr %al, i64 %loidx
      %blp = getelementptr i64, ptr %bl, i64 %loidx
      %ah = load i64, ptr %ahp, align 8
      %bh = load i64, ptr %bhp, align 8
      %alo = load i64, ptr %alp, align 8
      %blo = load i64, ptr %blp, align 8
      %hdiff = xor i64 %ah, %bh
      %ldiff = xor i64 %alo, %blo
      %pairdiff = or i64 %hdiff, %ldiff
      %paireq = icmp eq i64 %pairdiff, 0
      br i1 %paireq, label %scan.next, label %scan.pair.result
    scan.next:
      %next = sub i64 %idx, 2
      %done = icmp eq i64 %idx, 1
      br i1 %done, label %ret.zero, label %scan.loop
    scan.pair.result:
      %hieq = icmp eq i64 %ah, %bh
      %higt = icmp ugt i64 %ah, %bh
      %logt = icmp ugt i64 %alo, %blo
      %highcmp = select i1 %higt, i64 1, i64 -1
      %lowcmp = select i1 %logt, i64 1, i64 -1
      %paircmp = select i1 %hieq, i64 %lowcmp, i64 %highcmp
      br label %ret.mag

    ret.mag:
      %magcmp = phi i64 [ %twohicmp, %two.high.result ], [ %twolowcmp, %two.low.result ], [ %topcmp, %scan.odd.result ], [ %paircmp, %scan.pair.result ]
      %magneg = phi i1 [ %saneg, %two.high.result ], [ %saneg, %two.low.result ], [ %aneg, %scan.odd.result ], [ %aneg, %scan.pair.result ]
      %negmagcmp = sub i64 0, %magcmp
      %finalmagcmp = select i1 %magneg, i64 %negmagcmp, i64 %magcmp
      ret i64 %finalmagcmp
    ret.zero:
      ret i64 0
  IR
