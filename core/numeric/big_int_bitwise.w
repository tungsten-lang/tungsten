# Complete immutable integer bitwise kernels.  The three reserved entrypoints
# take and return raw WValue bit patterns; their caller has already established
# that both operands are integers and that at least one is a heap BigInt.
#
# The heap representation is sign-magnitude.  Positive pairs stay in a direct
# magnitude loop.  A pair containing a negative operand is converted to an
# infinite two's-complement view limb-by-limb, operated on, and (for a negative
# result) converted back to magnitude in the same pass.  One extra limb carries
# the infinite sign extension, after which the storage boundary canonicalizes
# the result and demotes it to inline i48 when possible.

# The operation selector is tested once, outside every limb loop:
#   0 = and, 1 = or, 2 = xor.
fn __bigint_bw_kernel(rp, a, b, as, bs, op) (i64 i64 i64 i64 i64 i64) i64
  ll <<~IR
    entry:
      %rq = inttoptr i64 %rp to ptr

      %amask = ashr i64 %as, 63
      %axsz = xor i64 %as, %amask
      %alen = sub i64 %axsz, %amask
      %bmask = ashr i64 %bs, 63
      %bxsz = xor i64 %bs, %bmask
      %blen = sub i64 %bxsz, %bmask
      %aneg = icmp slt i64 %as, 0
      %bneg = icmp slt i64 %bs, 0

      %aslot = alloca i64, align 8
      %ashl = shl i64 %a, 16
      %ai = ashr i64 %ashl, 16
      %aimask = ashr i64 %ai, 63
      %aix = xor i64 %ai, %aimask
      %aimag = sub i64 %aix, %aimask
      store i64 %aimag, ptr %aslot, align 8
      %atag = and i64 %a, -281474976710656
      %aisbig = icmp eq i64 %atag, -1407374883553280
      %apbits = and i64 %a, 140737488355327
      %alimbbits = add i64 %apbits, 16
      %apheap = inttoptr i64 %alimbbits to ptr
      %ap = select i1 %aisbig, ptr %apheap, ptr %aslot

      %bslot = alloca i64, align 8
      %bshl = shl i64 %b, 16
      %bi = ashr i64 %bshl, 16
      %bimask = ashr i64 %bi, 63
      %bix = xor i64 %bi, %bimask
      %bimag = sub i64 %bix, %bimask
      store i64 %bimag, ptr %bslot, align 8
      %btag = and i64 %b, -281474976710656
      %bisbig = icmp eq i64 %btag, -1407374883553280
      %bpbits = and i64 %b, 140737488355327
      %blimbbits = add i64 %bpbits, 16
      %bpheap = inttoptr i64 %blimbbits to ptr
      %bp = select i1 %bisbig, ptr %bpheap, ptr %bslot

      %anyneg = or i1 %aneg, %bneg
      br i1 %anyneg, label %signed.dispatch, label %positive.dispatch

    positive.dispatch:
      switch i64 %op, label %positive.xor.setup [
        i64 0, label %positive.and.setup
        i64 1, label %positive.or.setup
      ]

    positive.and.setup:
      %a.shorter = icmp ult i64 %alen, %blen
      %and.n = select i1 %a.shorter, i64 %alen, i64 %blen
      %and.n2 = and i64 %and.n, -2
      %and.has2 = icmp ne i64 %and.n2, 0
      br i1 %and.has2, label %positive.and.vec, label %positive.and.tail
    positive.and.vec:
      %and.i = phi i64 [ 0, %positive.and.setup ], [ %and.next, %positive.and.vec ]
      %and.ap = getelementptr inbounds i64, ptr %ap, i64 %and.i
      %and.bp = getelementptr inbounds i64, ptr %bp, i64 %and.i
      %and.rp = getelementptr inbounds i64, ptr %rq, i64 %and.i
      %and.av = load <2 x i64>, ptr %and.ap, align 8
      %and.bv = load <2 x i64>, ptr %and.bp, align 8
      %and.rv = and <2 x i64> %and.av, %and.bv
      store <2 x i64> %and.rv, ptr %and.rp, align 8
      %and.next = add nuw nsw i64 %and.i, 2
      %and.done2 = icmp eq i64 %and.next, %and.n2
      br i1 %and.done2, label %positive.and.tail, label %positive.and.vec
    positive.and.tail:
      %and.base = phi i64 [ 0, %positive.and.setup ], [ %and.n2, %positive.and.vec ]
      %and.odd = icmp ult i64 %and.base, %and.n
      br i1 %and.odd, label %positive.and.scalar, label %exit
    positive.and.scalar:
      %and.sap = getelementptr inbounds i64, ptr %ap, i64 %and.base
      %and.sbp = getelementptr inbounds i64, ptr %bp, i64 %and.base
      %and.srp = getelementptr inbounds i64, ptr %rq, i64 %and.base
      %and.sav = load i64, ptr %and.sap, align 8
      %and.sbv = load i64, ptr %and.sbp, align 8
      %and.srv = and i64 %and.sav, %and.sbv
      store i64 %and.srv, ptr %and.srp, align 8
      br label %exit

    positive.or.setup:
      %or.a.longer = icmp uge i64 %alen, %blen
      %or.lp = select i1 %or.a.longer, ptr %ap, ptr %bp
      %or.sp = select i1 %or.a.longer, ptr %bp, ptr %ap
      %or.ln = select i1 %or.a.longer, i64 %alen, i64 %blen
      %or.sn = select i1 %or.a.longer, i64 %blen, i64 %alen
      %or.sn2 = and i64 %or.sn, -2
      %or.has2 = icmp ne i64 %or.sn2, 0
      br i1 %or.has2, label %positive.or.vec, label %positive.or.tail
    positive.or.vec:
      %or.i = phi i64 [ 0, %positive.or.setup ], [ %or.next, %positive.or.vec ]
      %or.lvp = getelementptr inbounds i64, ptr %or.lp, i64 %or.i
      %or.svp = getelementptr inbounds i64, ptr %or.sp, i64 %or.i
      %or.rvp = getelementptr inbounds i64, ptr %rq, i64 %or.i
      %or.lv = load <2 x i64>, ptr %or.lvp, align 8
      %or.sv = load <2 x i64>, ptr %or.svp, align 8
      %or.rv = or <2 x i64> %or.lv, %or.sv
      store <2 x i64> %or.rv, ptr %or.rvp, align 8
      %or.next = add nuw nsw i64 %or.i, 2
      %or.done2 = icmp eq i64 %or.next, %or.sn2
      br i1 %or.done2, label %positive.or.tail, label %positive.or.vec
    positive.or.tail:
      %or.base = phi i64 [ 0, %positive.or.setup ], [ %or.sn2, %positive.or.vec ]
      %or.odd = icmp ult i64 %or.base, %or.sn
      br i1 %or.odd, label %positive.or.scalar, label %positive.or.copy.setup
    positive.or.scalar:
      %or.slp = getelementptr inbounds i64, ptr %or.lp, i64 %or.base
      %or.ssp = getelementptr inbounds i64, ptr %or.sp, i64 %or.base
      %or.srp = getelementptr inbounds i64, ptr %rq, i64 %or.base
      %or.slv = load i64, ptr %or.slp, align 8
      %or.ssv = load i64, ptr %or.ssp, align 8
      %or.srv = or i64 %or.slv, %or.ssv
      store i64 %or.srv, ptr %or.srp, align 8
      br label %positive.or.copy.setup
    positive.or.copy.setup:
      %or.remaining = sub i64 %or.ln, %or.sn
      %or.rem2 = and i64 %or.remaining, -2
      %or.copy.has2 = icmp ne i64 %or.rem2, 0
      br i1 %or.copy.has2, label %positive.or.copy.vec, label %positive.or.copy.tail
    positive.or.copy.vec:
      %or.ci = phi i64 [ 0, %positive.or.copy.setup ], [ %or.cnext, %positive.or.copy.vec ]
      %or.li = add i64 %or.sn, %or.ci
      %or.clp = getelementptr inbounds i64, ptr %or.lp, i64 %or.li
      %or.crp = getelementptr inbounds i64, ptr %rq, i64 %or.li
      %or.clv = load <2 x i64>, ptr %or.clp, align 8
      store <2 x i64> %or.clv, ptr %or.crp, align 8
      %or.cnext = add nuw nsw i64 %or.ci, 2
      %or.cdone2 = icmp eq i64 %or.cnext, %or.rem2
      br i1 %or.cdone2, label %positive.or.copy.tail, label %positive.or.copy.vec
    positive.or.copy.tail:
      %or.cbase = phi i64 [ 0, %positive.or.copy.setup ], [ %or.rem2, %positive.or.copy.vec ]
      %or.copy.odd = icmp ult i64 %or.cbase, %or.remaining
      br i1 %or.copy.odd, label %positive.or.copy.scalar, label %exit
    positive.or.copy.scalar:
      %or.cli = add i64 %or.sn, %or.cbase
      %or.cslp = getelementptr inbounds i64, ptr %or.lp, i64 %or.cli
      %or.csrp = getelementptr inbounds i64, ptr %rq, i64 %or.cli
      %or.cslv = load i64, ptr %or.cslp, align 8
      store i64 %or.cslv, ptr %or.csrp, align 8
      br label %exit

    positive.xor.setup:
      %xor.a.longer = icmp uge i64 %alen, %blen
      %xor.lp = select i1 %xor.a.longer, ptr %ap, ptr %bp
      %xor.sp = select i1 %xor.a.longer, ptr %bp, ptr %ap
      %xor.ln = select i1 %xor.a.longer, i64 %alen, i64 %blen
      %xor.sn = select i1 %xor.a.longer, i64 %blen, i64 %alen
      %xor.sn2 = and i64 %xor.sn, -2
      %xor.has2 = icmp ne i64 %xor.sn2, 0
      br i1 %xor.has2, label %positive.xor.vec, label %positive.xor.tail
    positive.xor.vec:
      %xor.i = phi i64 [ 0, %positive.xor.setup ], [ %xor.next, %positive.xor.vec ]
      %xor.lvp = getelementptr inbounds i64, ptr %xor.lp, i64 %xor.i
      %xor.svp = getelementptr inbounds i64, ptr %xor.sp, i64 %xor.i
      %xor.rvp = getelementptr inbounds i64, ptr %rq, i64 %xor.i
      %xor.lv = load <2 x i64>, ptr %xor.lvp, align 8
      %xor.sv = load <2 x i64>, ptr %xor.svp, align 8
      %xor.rv = xor <2 x i64> %xor.lv, %xor.sv
      store <2 x i64> %xor.rv, ptr %xor.rvp, align 8
      %xor.next = add nuw nsw i64 %xor.i, 2
      %xor.done2 = icmp eq i64 %xor.next, %xor.sn2
      br i1 %xor.done2, label %positive.xor.tail, label %positive.xor.vec
    positive.xor.tail:
      %xor.base = phi i64 [ 0, %positive.xor.setup ], [ %xor.sn2, %positive.xor.vec ]
      %xor.odd = icmp ult i64 %xor.base, %xor.sn
      br i1 %xor.odd, label %positive.xor.scalar, label %positive.xor.copy.setup
    positive.xor.scalar:
      %xor.slp = getelementptr inbounds i64, ptr %xor.lp, i64 %xor.base
      %xor.ssp = getelementptr inbounds i64, ptr %xor.sp, i64 %xor.base
      %xor.srp = getelementptr inbounds i64, ptr %rq, i64 %xor.base
      %xor.slv = load i64, ptr %xor.slp, align 8
      %xor.ssv = load i64, ptr %xor.ssp, align 8
      %xor.srv = xor i64 %xor.slv, %xor.ssv
      store i64 %xor.srv, ptr %xor.srp, align 8
      br label %positive.xor.copy.setup
    positive.xor.copy.setup:
      %xor.remaining = sub i64 %xor.ln, %xor.sn
      %xor.rem2 = and i64 %xor.remaining, -2
      %xor.copy.has2 = icmp ne i64 %xor.rem2, 0
      br i1 %xor.copy.has2, label %positive.xor.copy.vec, label %positive.xor.copy.tail
    positive.xor.copy.vec:
      %xor.ci = phi i64 [ 0, %positive.xor.copy.setup ], [ %xor.cnext, %positive.xor.copy.vec ]
      %xor.li = add i64 %xor.sn, %xor.ci
      %xor.clp = getelementptr inbounds i64, ptr %xor.lp, i64 %xor.li
      %xor.crp = getelementptr inbounds i64, ptr %rq, i64 %xor.li
      %xor.clv = load <2 x i64>, ptr %xor.clp, align 8
      store <2 x i64> %xor.clv, ptr %xor.crp, align 8
      %xor.cnext = add nuw nsw i64 %xor.ci, 2
      %xor.cdone2 = icmp eq i64 %xor.cnext, %xor.rem2
      br i1 %xor.cdone2, label %positive.xor.copy.tail, label %positive.xor.copy.vec
    positive.xor.copy.tail:
      %xor.cbase = phi i64 [ 0, %positive.xor.copy.setup ], [ %xor.rem2, %positive.xor.copy.vec ]
      %xor.copy.odd = icmp ult i64 %xor.cbase, %xor.remaining
      br i1 %xor.copy.odd, label %positive.xor.copy.scalar, label %exit
    positive.xor.copy.scalar:
      %xor.cli = add i64 %xor.sn, %xor.cbase
      %xor.cslp = getelementptr inbounds i64, ptr %xor.lp, i64 %xor.cli
      %xor.csrp = getelementptr inbounds i64, ptr %rq, i64 %xor.cli
      %xor.cslv = load i64, ptr %xor.cslp, align 8
      store i64 %xor.cslv, ptr %xor.csrp, align 8
      br label %exit

    signed.dispatch:
      %a.longer = icmp uge i64 %alen, %blen
      %maxlen = select i1 %a.longer, i64 %alen, i64 %blen
      %signed.n = add nuw nsw i64 %maxlen, 1
      switch i64 %op, label %signed.xor.setup [
        i64 0, label %signed.and.setup
        i64 1, label %signed.or.setup
      ]

    signed.and.setup:
      %and.rneg = and i1 %aneg, %bneg
      %and.amask = sext i1 %aneg to i64
      %and.bmask = sext i1 %bneg to i64
      %and.rmask = sext i1 %and.rneg to i64
      br label %signed.and.loop
    signed.and.loop:
      %sand.i = phi i64 [ 0, %signed.and.setup ], [ %sand.next, %signed.and.loop ]
      %sand.ac = phi i1 [ true, %signed.and.setup ], [ %sand.ac.next, %signed.and.loop ]
      %sand.bc = phi i1 [ true, %signed.and.setup ], [ %sand.bc.next, %signed.and.loop ]
      %sand.rc = phi i1 [ true, %signed.and.setup ], [ %sand.rc.next, %signed.and.loop ]
      %sand.ain = icmp ult i64 %sand.i, %alen
      %sand.bin = icmp ult i64 %sand.i, %blen
      %sand.aidx = select i1 %sand.ain, i64 %sand.i, i64 0
      %sand.bidx = select i1 %sand.bin, i64 %sand.i, i64 0
      %sand.ag = getelementptr inbounds i64, ptr %ap, i64 %sand.aidx
      %sand.bg = getelementptr inbounds i64, ptr %bp, i64 %sand.bidx
      %sand.aload = load i64, ptr %sand.ag, align 8
      %sand.bload = load i64, ptr %sand.bg, align 8
      %sand.av = select i1 %sand.ain, i64 %sand.aload, i64 0
      %sand.bv = select i1 %sand.bin, i64 %sand.bload, i64 0
      %sand.ax = xor i64 %sand.av, %and.amask
      %sand.bx = xor i64 %sand.bv, %and.bmask
      %sand.aci = zext i1 %sand.ac to i64
      %sand.bci = zext i1 %sand.bc to i64
      %sand.acin = select i1 %aneg, i64 %sand.aci, i64 0
      %sand.bcin = select i1 %bneg, i64 %sand.bci, i64 0
      %sand.at = add i64 %sand.ax, %sand.acin
      %sand.bt = add i64 %sand.bx, %sand.bcin
      %sand.ac.overflow = icmp ult i64 %sand.at, %sand.ax
      %sand.bc.overflow = icmp ult i64 %sand.bt, %sand.bx
      %sand.ac.next = and i1 %aneg, %sand.ac.overflow
      %sand.bc.next = and i1 %bneg, %sand.bc.overflow
      %sand.raw = and i64 %sand.at, %sand.bt
      %sand.rx = xor i64 %sand.raw, %and.rmask
      %sand.rci = zext i1 %sand.rc to i64
      %sand.rcin = select i1 %and.rneg, i64 %sand.rci, i64 0
      %sand.mag = add i64 %sand.rx, %sand.rcin
      %sand.rc.overflow = icmp ult i64 %sand.mag, %sand.rx
      %sand.rc.next = and i1 %and.rneg, %sand.rc.overflow
      %sand.rg = getelementptr inbounds i64, ptr %rq, i64 %sand.i
      store i64 %sand.mag, ptr %sand.rg, align 8
      %sand.next = add nuw nsw i64 %sand.i, 1
      %sand.done = icmp eq i64 %sand.next, %signed.n
      br i1 %sand.done, label %exit, label %signed.and.loop

    signed.or.setup:
      %or.rneg = or i1 %aneg, %bneg
      %or.amask = sext i1 %aneg to i64
      %or.bmask = sext i1 %bneg to i64
      %or.rmask = sext i1 %or.rneg to i64
      br label %signed.or.loop
    signed.or.loop:
      %sor.i = phi i64 [ 0, %signed.or.setup ], [ %sor.next, %signed.or.loop ]
      %sor.ac = phi i1 [ true, %signed.or.setup ], [ %sor.ac.next, %signed.or.loop ]
      %sor.bc = phi i1 [ true, %signed.or.setup ], [ %sor.bc.next, %signed.or.loop ]
      %sor.rc = phi i1 [ true, %signed.or.setup ], [ %sor.rc.next, %signed.or.loop ]
      %sor.ain = icmp ult i64 %sor.i, %alen
      %sor.bin = icmp ult i64 %sor.i, %blen
      %sor.aidx = select i1 %sor.ain, i64 %sor.i, i64 0
      %sor.bidx = select i1 %sor.bin, i64 %sor.i, i64 0
      %sor.ag = getelementptr inbounds i64, ptr %ap, i64 %sor.aidx
      %sor.bg = getelementptr inbounds i64, ptr %bp, i64 %sor.bidx
      %sor.aload = load i64, ptr %sor.ag, align 8
      %sor.bload = load i64, ptr %sor.bg, align 8
      %sor.av = select i1 %sor.ain, i64 %sor.aload, i64 0
      %sor.bv = select i1 %sor.bin, i64 %sor.bload, i64 0
      %sor.ax = xor i64 %sor.av, %or.amask
      %sor.bx = xor i64 %sor.bv, %or.bmask
      %sor.aci = zext i1 %sor.ac to i64
      %sor.bci = zext i1 %sor.bc to i64
      %sor.acin = select i1 %aneg, i64 %sor.aci, i64 0
      %sor.bcin = select i1 %bneg, i64 %sor.bci, i64 0
      %sor.at = add i64 %sor.ax, %sor.acin
      %sor.bt = add i64 %sor.bx, %sor.bcin
      %sor.ac.overflow = icmp ult i64 %sor.at, %sor.ax
      %sor.bc.overflow = icmp ult i64 %sor.bt, %sor.bx
      %sor.ac.next = and i1 %aneg, %sor.ac.overflow
      %sor.bc.next = and i1 %bneg, %sor.bc.overflow
      %sor.raw = or i64 %sor.at, %sor.bt
      %sor.rx = xor i64 %sor.raw, %or.rmask
      %sor.rci = zext i1 %sor.rc to i64
      %sor.rcin = select i1 %or.rneg, i64 %sor.rci, i64 0
      %sor.mag = add i64 %sor.rx, %sor.rcin
      %sor.rc.overflow = icmp ult i64 %sor.mag, %sor.rx
      %sor.rc.next = and i1 %or.rneg, %sor.rc.overflow
      %sor.rg = getelementptr inbounds i64, ptr %rq, i64 %sor.i
      store i64 %sor.mag, ptr %sor.rg, align 8
      %sor.next = add nuw nsw i64 %sor.i, 1
      %sor.done = icmp eq i64 %sor.next, %signed.n
      br i1 %sor.done, label %exit, label %signed.or.loop

    signed.xor.setup:
      %xor.rneg = xor i1 %aneg, %bneg
      %xor.amask = sext i1 %aneg to i64
      %xor.bmask = sext i1 %bneg to i64
      %xor.rmask = sext i1 %xor.rneg to i64
      br label %signed.xor.loop
    signed.xor.loop:
      %sxor.i = phi i64 [ 0, %signed.xor.setup ], [ %sxor.next, %signed.xor.loop ]
      %sxor.ac = phi i1 [ true, %signed.xor.setup ], [ %sxor.ac.next, %signed.xor.loop ]
      %sxor.bc = phi i1 [ true, %signed.xor.setup ], [ %sxor.bc.next, %signed.xor.loop ]
      %sxor.rc = phi i1 [ true, %signed.xor.setup ], [ %sxor.rc.next, %signed.xor.loop ]
      %sxor.ain = icmp ult i64 %sxor.i, %alen
      %sxor.bin = icmp ult i64 %sxor.i, %blen
      %sxor.aidx = select i1 %sxor.ain, i64 %sxor.i, i64 0
      %sxor.bidx = select i1 %sxor.bin, i64 %sxor.i, i64 0
      %sxor.ag = getelementptr inbounds i64, ptr %ap, i64 %sxor.aidx
      %sxor.bg = getelementptr inbounds i64, ptr %bp, i64 %sxor.bidx
      %sxor.aload = load i64, ptr %sxor.ag, align 8
      %sxor.bload = load i64, ptr %sxor.bg, align 8
      %sxor.av = select i1 %sxor.ain, i64 %sxor.aload, i64 0
      %sxor.bv = select i1 %sxor.bin, i64 %sxor.bload, i64 0
      %sxor.ax = xor i64 %sxor.av, %xor.amask
      %sxor.bx = xor i64 %sxor.bv, %xor.bmask
      %sxor.aci = zext i1 %sxor.ac to i64
      %sxor.bci = zext i1 %sxor.bc to i64
      %sxor.acin = select i1 %aneg, i64 %sxor.aci, i64 0
      %sxor.bcin = select i1 %bneg, i64 %sxor.bci, i64 0
      %sxor.at = add i64 %sxor.ax, %sxor.acin
      %sxor.bt = add i64 %sxor.bx, %sxor.bcin
      %sxor.ac.overflow = icmp ult i64 %sxor.at, %sxor.ax
      %sxor.bc.overflow = icmp ult i64 %sxor.bt, %sxor.bx
      %sxor.ac.next = and i1 %aneg, %sxor.ac.overflow
      %sxor.bc.next = and i1 %bneg, %sxor.bc.overflow
      %sxor.raw = xor i64 %sxor.at, %sxor.bt
      %sxor.rx = xor i64 %sxor.raw, %xor.rmask
      %sxor.rci = zext i1 %sxor.rc to i64
      %sxor.rcin = select i1 %xor.rneg, i64 %sxor.rci, i64 0
      %sxor.mag = add i64 %sxor.rx, %sxor.rcin
      %sxor.rc.overflow = icmp ult i64 %sxor.mag, %sxor.rx
      %sxor.rc.next = and i1 %xor.rneg, %sxor.rc.overflow
      %sxor.rg = getelementptr inbounds i64, ptr %rq, i64 %sxor.i
      store i64 %sxor.mag, ptr %sxor.rg, align 8
      %sxor.next = add nuw nsw i64 %sxor.i, 1
      %sxor.done = icmp eq i64 %sxor.next, %signed.n
      br i1 %sxor.done, label %exit, label %signed.xor.loop

    exit:
      ret i64 0
  IR

# Decode the effective signed limb count.  Heap sign is the signed header
# composed with the tag overlay; inline integers have zero or one limb.
fn __bigint_bw_signed_size(value) (i64) i64
  if (value & -281474976710656) == -1407374883553280
    ptr = value & 140737488355327 ## i64
    raw = raw_load_u32(ptr, 4) ## i64
    signed = (raw << 32) >> 32 ## i64
    if (value & 140737488355328) != 0
      return 0 - signed
    return signed

  inline = (value << 16) >> 16 ## i64
  if inline == 0
    return 0
  if inline < 0
    return 0 - 1
  1

fn __bigint_bw_inline_and(a, b) (i64 i64) i64
  av = (a << 16) >> 16 ## i64
  bv = (b << 16) >> 16 ## i64
  raw = av & bv ## i64
  -1688849860263936 | (raw & 281474976710655)

fn __bigint_bw_inline_or(a, b) (i64 i64) i64
  av = (a << 16) >> 16 ## i64
  bv = (b << 16) >> 16 ## i64
  raw = av | bv ## i64
  -1688849860263936 | (raw & 281474976710655)

fn __bigint_bw_inline_xor(a, b) (i64 i64) i64
  av = (a << 16) >> 16 ## i64
  bv = (b << 16) >> 16 ## i64
  raw = av ^ bv ## i64
  -1688849860263936 | (raw & 281474976710655)

# The fixed four-limb positive AND row is small enough that the generic
# sign/width kernel's dispatch costs more than its arithmetic.  Keep the
# proven two-vector source shape direct and return the published top word so
# the caller can use the known-normalized epilogue when it survives.
fn __bigint_bw_and4(rp, ap, bp) (i64 i64 i64) i64
  ll <<~IR
    entry:
      %rq = inttoptr i64 %rp to ptr
      %aq = inttoptr i64 %ap to ptr
      %bq = inttoptr i64 %bp to ptr
      %ag1 = getelementptr inbounds i64, ptr %aq, i64 2
      %bg1 = getelementptr inbounds i64, ptr %bq, i64 2
      %rg1 = getelementptr inbounds i64, ptr %rq, i64 2
      %av0 = load <2 x i64>, ptr %aq, align 8
      %bv0 = load <2 x i64>, ptr %bq, align 8
      %av1 = load <2 x i64>, ptr %ag1, align 8
      %bv1 = load <2 x i64>, ptr %bg1, align 8
      %rv0 = and <2 x i64> %av0, %bv0
      %rv1 = and <2 x i64> %av1, %bv1
      store <2 x i64> %rv0, ptr %rq, align 8
      store <2 x i64> %rv1, ptr %rg1, align 8
      %top = extractelement <2 x i64> %rv1, i64 1
      ret i64 %top
  IR

# x & x = x, x & -1 = x, and x & 0 = 0 are allocation-free.  Returning a
# heap operand marks the shared buffer before publishing the alias.
fn __bigint_and_raw(a, b) (i64 i64) i64
  zero = -1688849860263936 ## i64
  negative_one = -1407374883553281 ## i64
  if a == b
    return ccall_nobox("w_bigint_mark_shared_value", a)
  if a == zero || b == zero
    return zero
  if a == negative_one
    return ccall_nobox("w_bigint_mark_shared_value", b)
  if b == negative_one
    return ccall_nobox("w_bigint_mark_shared_value", a)

  aisbig = (a & -281474976710656) == -1407374883553280
  bisbig = (b & -281474976710656) == -1407374883553280
  if !aisbig && !bisbig
    return __bigint_bw_inline_and(a, b)

  as = __bigint_bw_signed_size(a)
  bs = __bigint_bw_signed_size(b)
  if as == 4 && bs == 4
    result4 = ccall_nobox("w_bigint_alloc_hot", 4) ## i64
    rp4 = (result4 & 140737488355327) + 16 ## i64
    ap4 = (a & 140737488355327) + 16 ## i64
    bp4 = (b & 140737488355327) + 16 ## i64
    top4 = __bigint_bw_and4(rp4, ap4, bp4)
    if top4 != 0
      return ccall_nobox("w_bigint_finish_add_raw", result4, 4)
    return ccall_nobox("w_bigint_seal_raw", result4, 4)
  amask = as >> 63 ## i64
  bmask = bs >> 63 ## i64
  alen = (as ^ amask) - amask ## i64
  blen = (bs ^ bmask) - bmask ## i64
  n = alen ## i64
  if blen < alen
    n = blen
  if as < 0 || bs < 0
    n = alen
    if blen > alen
      n = blen
    n += 1
  result = ccall_nobox("w_bigint_alloc_hot", n) ## i64
  rp = (result & 140737488355327) + 16 ## i64
  __bigint_bw_kernel(rp, a, b, as, bs, 0)
  rneg = as < 0 && bs < 0
  signed_n = n ## i64
  if rneg
    signed_n = 0 - n
  ccall_nobox("w_bigint_seal_raw", result, signed_n)

# x | x = x, x | 0 = x, and x | -1 = -1 are allocation-free.
fn __bigint_or_raw(a, b) (i64 i64) i64
  zero = -1688849860263936 ## i64
  negative_one = -1407374883553281 ## i64
  if a == b
    return ccall_nobox("w_bigint_mark_shared_value", a)
  if a == zero
    return ccall_nobox("w_bigint_mark_shared_value", b)
  if b == zero
    return ccall_nobox("w_bigint_mark_shared_value", a)
  if a == negative_one || b == negative_one
    return negative_one

  aisbig = (a & -281474976710656) == -1407374883553280
  bisbig = (b & -281474976710656) == -1407374883553280
  if !aisbig && !bisbig
    return __bigint_bw_inline_or(a, b)

  as = __bigint_bw_signed_size(a)
  bs = __bigint_bw_signed_size(b)
  amask = as >> 63 ## i64
  bmask = bs >> 63 ## i64
  alen = (as ^ amask) - amask ## i64
  blen = (bs ^ bmask) - bmask ## i64
  n = alen ## i64
  if blen > alen
    n = blen
  if as < 0 || bs < 0
    n += 1
  result = ccall_nobox("w_bigint_alloc_hot", n) ## i64
  rp = (result & 140737488355327) + 16 ## i64
  __bigint_bw_kernel(rp, a, b, as, bs, 1)
  rneg = as < 0 || bs < 0
  signed_n = n ## i64
  if rneg
    signed_n = 0 - n
  ccall_nobox("w_bigint_seal_raw", result, signed_n)

# x ^ x = 0 and x ^ 0 = x are allocation-free.  XOR of unlike signs is
# negative; like signs are positive.
fn __bigint_xor_raw(a, b) (i64 i64) i64
  zero = -1688849860263936 ## i64
  if a == b
    return zero
  if a == zero
    return ccall_nobox("w_bigint_mark_shared_value", b)
  if b == zero
    return ccall_nobox("w_bigint_mark_shared_value", a)

  aisbig = (a & -281474976710656) == -1407374883553280
  bisbig = (b & -281474976710656) == -1407374883553280
  if !aisbig && !bisbig
    return __bigint_bw_inline_xor(a, b)

  as = __bigint_bw_signed_size(a)
  bs = __bigint_bw_signed_size(b)
  amask = as >> 63 ## i64
  bmask = bs >> 63 ## i64
  alen = (as ^ amask) - amask ## i64
  blen = (bs ^ bmask) - bmask ## i64
  n = alen ## i64
  if blen > alen
    n = blen
  if as < 0 || bs < 0
    n += 1
  result = ccall_nobox("w_bigint_alloc_hot", n) ## i64
  rp = (result & 140737488355327) + 16 ## i64
  __bigint_bw_kernel(rp, a, b, as, bs, 2)
  rneg = (as < 0) != (bs < 0)
  signed_n = n ## i64
  if rneg
    signed_n = 0 - n
  ccall_nobox("w_bigint_seal_raw", result, signed_n)

# The consumed ABI can be selected for an opaque local whose dynamic value is
# not an integer.  Keep coercion and error policy at the public runtime entry;
# only raw inline-Int and heap-BigInt patterns may enter the storage predicates.
fn __bigint_bw_is_integer(value) (i64) i64
  tag = value & -281474976710656 ## i64
  if tag == -1688849860263936
    return 1
  if tag == -1407374883553280
    return 1
  0

# A consumed receiver is writable only when it is an unshared, overlay-clear,
# positive heap BigInt and the still-live rhs is a distinct, effective-positive
# heap BigInt of exactly the same width.  Zero means "use immutable fallback";
# canonical live BigInts never have a positive zero-limb width.
fn __bigint_bw_mut_width(a, b) (i64 i64) i64
  if (a & -281474976710656) != -1407374883553280
    return 0
  if (a & 140737488355328) != 0
    return 0
  if (b & -281474976710656) != -1407374883553280
    return 0

  ap = a & 140737488355327 ## i64
  bp = b & 140737488355327 ## i64
  if ap == bp
    return 0
  if raw_load_u8(ap, 1) != 0
    return 0

  araw = raw_load_u32(ap, 4) ## i64
  as = (araw << 32) >> 32 ## i64
  if as <= 0
    return 0
  braw = raw_load_u32(bp, 4) ## i64
  bs = (braw << 32) >> 32 ## i64
  if (b & 140737488355328) != 0
    bs = 0 - bs
  if bs != as
    return 0
  as

# Equal-width positive in-place kernel.  The 2/4/8-limb cases are fully
# unrolled; arbitrary widths use paired vectors plus one scalar tail.  The
# returned word is the post-operation top limb, allowing AND/XOR to normalize
# only on cancellation.  A page-offset hazard guard for long same-index streams
# is intentionally deferred until the source path can be swept on each target.
fn __bigint_bw_mut_kernel(ap, bp, n, op) (i64 i64 i64 i64) i64
  ll <<~IR
    entry:
      %aq = inttoptr i64 %ap to ptr
      %bq = inttoptr i64 %bp to ptr
      switch i64 %op, label %xor.dispatch [
        i64 0, label %and.dispatch
        i64 1, label %or.dispatch
      ]

    and.dispatch:
      switch i64 %n, label %and.general [
        i64 2, label %and.two
        i64 4, label %and.four
        i64 8, label %and.eight
      ]
    and.two:
      %and2.a = load <2 x i64>, ptr %aq, align 8
      %and2.b = load <2 x i64>, ptr %bq, align 8
      %and2.r = and <2 x i64> %and2.a, %and2.b
      store <2 x i64> %and2.r, ptr %aq, align 8
      br label %finish
    and.four:
      %and4.a0 = load <2 x i64>, ptr %aq, align 8
      %and4.b0 = load <2 x i64>, ptr %bq, align 8
      %and4.ap1 = getelementptr inbounds i64, ptr %aq, i64 2
      %and4.bp1 = getelementptr inbounds i64, ptr %bq, i64 2
      %and4.a1 = load <2 x i64>, ptr %and4.ap1, align 8
      %and4.b1 = load <2 x i64>, ptr %and4.bp1, align 8
      %and4.r0 = and <2 x i64> %and4.a0, %and4.b0
      %and4.r1 = and <2 x i64> %and4.a1, %and4.b1
      store <2 x i64> %and4.r0, ptr %aq, align 8
      store <2 x i64> %and4.r1, ptr %and4.ap1, align 8
      br label %finish
    and.eight:
      %and8.ap1 = getelementptr inbounds i64, ptr %aq, i64 2
      %and8.bp1 = getelementptr inbounds i64, ptr %bq, i64 2
      %and8.ap2 = getelementptr inbounds i64, ptr %aq, i64 4
      %and8.bp2 = getelementptr inbounds i64, ptr %bq, i64 4
      %and8.ap3 = getelementptr inbounds i64, ptr %aq, i64 6
      %and8.bp3 = getelementptr inbounds i64, ptr %bq, i64 6
      %and8.a0 = load <2 x i64>, ptr %aq, align 8
      %and8.b0 = load <2 x i64>, ptr %bq, align 8
      %and8.a1 = load <2 x i64>, ptr %and8.ap1, align 8
      %and8.b1 = load <2 x i64>, ptr %and8.bp1, align 8
      %and8.a2 = load <2 x i64>, ptr %and8.ap2, align 8
      %and8.b2 = load <2 x i64>, ptr %and8.bp2, align 8
      %and8.a3 = load <2 x i64>, ptr %and8.ap3, align 8
      %and8.b3 = load <2 x i64>, ptr %and8.bp3, align 8
      %and8.r0 = and <2 x i64> %and8.a0, %and8.b0
      %and8.r1 = and <2 x i64> %and8.a1, %and8.b1
      %and8.r2 = and <2 x i64> %and8.a2, %and8.b2
      %and8.r3 = and <2 x i64> %and8.a3, %and8.b3
      store <2 x i64> %and8.r0, ptr %aq, align 8
      store <2 x i64> %and8.r1, ptr %and8.ap1, align 8
      store <2 x i64> %and8.r2, ptr %and8.ap2, align 8
      store <2 x i64> %and8.r3, ptr %and8.ap3, align 8
      br label %finish
    and.general:
      %and.n2 = and i64 %n, -2
      %and.has2 = icmp ne i64 %and.n2, 0
      br i1 %and.has2, label %and.loop, label %and.tail
    and.loop:
      %and.i = phi i64 [ 0, %and.general ], [ %and.next, %and.loop ]
      %and.ag = getelementptr inbounds i64, ptr %aq, i64 %and.i
      %and.bg = getelementptr inbounds i64, ptr %bq, i64 %and.i
      %and.av = load <2 x i64>, ptr %and.ag, align 8
      %and.bv = load <2 x i64>, ptr %and.bg, align 8
      %and.rv = and <2 x i64> %and.av, %and.bv
      store <2 x i64> %and.rv, ptr %and.ag, align 8
      %and.next = add nuw nsw i64 %and.i, 2
      %and.done = icmp eq i64 %and.next, %and.n2
      br i1 %and.done, label %and.tail, label %and.loop
    and.tail:
      %and.base = phi i64 [ 0, %and.general ], [ %and.n2, %and.loop ]
      %and.odd = icmp ult i64 %and.base, %n
      br i1 %and.odd, label %and.scalar, label %finish
    and.scalar:
      %and.sag = getelementptr inbounds i64, ptr %aq, i64 %and.base
      %and.sbg = getelementptr inbounds i64, ptr %bq, i64 %and.base
      %and.sav = load i64, ptr %and.sag, align 8
      %and.sbv = load i64, ptr %and.sbg, align 8
      %and.srv = and i64 %and.sav, %and.sbv
      store i64 %and.srv, ptr %and.sag, align 8
      br label %finish

    or.dispatch:
      switch i64 %n, label %or.general [
        i64 2, label %or.two
        i64 4, label %or.four
        i64 8, label %or.eight
      ]
    or.two:
      %or2.a = load <2 x i64>, ptr %aq, align 8
      %or2.b = load <2 x i64>, ptr %bq, align 8
      %or2.r = or <2 x i64> %or2.a, %or2.b
      store <2 x i64> %or2.r, ptr %aq, align 8
      br label %finish
    or.four:
      %or4.a0 = load <2 x i64>, ptr %aq, align 8
      %or4.b0 = load <2 x i64>, ptr %bq, align 8
      %or4.ap1 = getelementptr inbounds i64, ptr %aq, i64 2
      %or4.bp1 = getelementptr inbounds i64, ptr %bq, i64 2
      %or4.a1 = load <2 x i64>, ptr %or4.ap1, align 8
      %or4.b1 = load <2 x i64>, ptr %or4.bp1, align 8
      %or4.r0 = or <2 x i64> %or4.a0, %or4.b0
      %or4.r1 = or <2 x i64> %or4.a1, %or4.b1
      store <2 x i64> %or4.r0, ptr %aq, align 8
      store <2 x i64> %or4.r1, ptr %or4.ap1, align 8
      br label %finish
    or.eight:
      %or8.ap1 = getelementptr inbounds i64, ptr %aq, i64 2
      %or8.bp1 = getelementptr inbounds i64, ptr %bq, i64 2
      %or8.ap2 = getelementptr inbounds i64, ptr %aq, i64 4
      %or8.bp2 = getelementptr inbounds i64, ptr %bq, i64 4
      %or8.ap3 = getelementptr inbounds i64, ptr %aq, i64 6
      %or8.bp3 = getelementptr inbounds i64, ptr %bq, i64 6
      %or8.a0 = load <2 x i64>, ptr %aq, align 8
      %or8.b0 = load <2 x i64>, ptr %bq, align 8
      %or8.a1 = load <2 x i64>, ptr %or8.ap1, align 8
      %or8.b1 = load <2 x i64>, ptr %or8.bp1, align 8
      %or8.a2 = load <2 x i64>, ptr %or8.ap2, align 8
      %or8.b2 = load <2 x i64>, ptr %or8.bp2, align 8
      %or8.a3 = load <2 x i64>, ptr %or8.ap3, align 8
      %or8.b3 = load <2 x i64>, ptr %or8.bp3, align 8
      %or8.r0 = or <2 x i64> %or8.a0, %or8.b0
      %or8.r1 = or <2 x i64> %or8.a1, %or8.b1
      %or8.r2 = or <2 x i64> %or8.a2, %or8.b2
      %or8.r3 = or <2 x i64> %or8.a3, %or8.b3
      store <2 x i64> %or8.r0, ptr %aq, align 8
      store <2 x i64> %or8.r1, ptr %or8.ap1, align 8
      store <2 x i64> %or8.r2, ptr %or8.ap2, align 8
      store <2 x i64> %or8.r3, ptr %or8.ap3, align 8
      br label %finish
    or.general:
      %or.n2 = and i64 %n, -2
      %or.has2 = icmp ne i64 %or.n2, 0
      br i1 %or.has2, label %or.loop, label %or.tail
    or.loop:
      %or.i = phi i64 [ 0, %or.general ], [ %or.next, %or.loop ]
      %or.ag = getelementptr inbounds i64, ptr %aq, i64 %or.i
      %or.bg = getelementptr inbounds i64, ptr %bq, i64 %or.i
      %or.av = load <2 x i64>, ptr %or.ag, align 8
      %or.bv = load <2 x i64>, ptr %or.bg, align 8
      %or.rv = or <2 x i64> %or.av, %or.bv
      store <2 x i64> %or.rv, ptr %or.ag, align 8
      %or.next = add nuw nsw i64 %or.i, 2
      %or.done = icmp eq i64 %or.next, %or.n2
      br i1 %or.done, label %or.tail, label %or.loop
    or.tail:
      %or.base = phi i64 [ 0, %or.general ], [ %or.n2, %or.loop ]
      %or.odd = icmp ult i64 %or.base, %n
      br i1 %or.odd, label %or.scalar, label %finish
    or.scalar:
      %or.sag = getelementptr inbounds i64, ptr %aq, i64 %or.base
      %or.sbg = getelementptr inbounds i64, ptr %bq, i64 %or.base
      %or.sav = load i64, ptr %or.sag, align 8
      %or.sbv = load i64, ptr %or.sbg, align 8
      %or.srv = or i64 %or.sav, %or.sbv
      store i64 %or.srv, ptr %or.sag, align 8
      br label %finish

    xor.dispatch:
      switch i64 %n, label %xor.general [
        i64 2, label %xor.two
        i64 4, label %xor.four
        i64 8, label %xor.eight
      ]
    xor.two:
      %xor2.a = load <2 x i64>, ptr %aq, align 8
      %xor2.b = load <2 x i64>, ptr %bq, align 8
      %xor2.r = xor <2 x i64> %xor2.a, %xor2.b
      store <2 x i64> %xor2.r, ptr %aq, align 8
      br label %finish
    xor.four:
      %xor4.a0 = load <2 x i64>, ptr %aq, align 8
      %xor4.b0 = load <2 x i64>, ptr %bq, align 8
      %xor4.ap1 = getelementptr inbounds i64, ptr %aq, i64 2
      %xor4.bp1 = getelementptr inbounds i64, ptr %bq, i64 2
      %xor4.a1 = load <2 x i64>, ptr %xor4.ap1, align 8
      %xor4.b1 = load <2 x i64>, ptr %xor4.bp1, align 8
      %xor4.r0 = xor <2 x i64> %xor4.a0, %xor4.b0
      %xor4.r1 = xor <2 x i64> %xor4.a1, %xor4.b1
      store <2 x i64> %xor4.r0, ptr %aq, align 8
      store <2 x i64> %xor4.r1, ptr %xor4.ap1, align 8
      br label %finish
    xor.eight:
      %xor8.ap1 = getelementptr inbounds i64, ptr %aq, i64 2
      %xor8.bp1 = getelementptr inbounds i64, ptr %bq, i64 2
      %xor8.ap2 = getelementptr inbounds i64, ptr %aq, i64 4
      %xor8.bp2 = getelementptr inbounds i64, ptr %bq, i64 4
      %xor8.ap3 = getelementptr inbounds i64, ptr %aq, i64 6
      %xor8.bp3 = getelementptr inbounds i64, ptr %bq, i64 6
      %xor8.a0 = load <2 x i64>, ptr %aq, align 8
      %xor8.b0 = load <2 x i64>, ptr %bq, align 8
      %xor8.a1 = load <2 x i64>, ptr %xor8.ap1, align 8
      %xor8.b1 = load <2 x i64>, ptr %xor8.bp1, align 8
      %xor8.a2 = load <2 x i64>, ptr %xor8.ap2, align 8
      %xor8.b2 = load <2 x i64>, ptr %xor8.bp2, align 8
      %xor8.a3 = load <2 x i64>, ptr %xor8.ap3, align 8
      %xor8.b3 = load <2 x i64>, ptr %xor8.bp3, align 8
      %xor8.r0 = xor <2 x i64> %xor8.a0, %xor8.b0
      %xor8.r1 = xor <2 x i64> %xor8.a1, %xor8.b1
      %xor8.r2 = xor <2 x i64> %xor8.a2, %xor8.b2
      %xor8.r3 = xor <2 x i64> %xor8.a3, %xor8.b3
      store <2 x i64> %xor8.r0, ptr %aq, align 8
      store <2 x i64> %xor8.r1, ptr %xor8.ap1, align 8
      store <2 x i64> %xor8.r2, ptr %xor8.ap2, align 8
      store <2 x i64> %xor8.r3, ptr %xor8.ap3, align 8
      br label %finish
    xor.general:
      %xor.n2 = and i64 %n, -2
      %xor.has2 = icmp ne i64 %xor.n2, 0
      br i1 %xor.has2, label %xor.loop, label %xor.tail
    xor.loop:
      %xor.i = phi i64 [ 0, %xor.general ], [ %xor.next, %xor.loop ]
      %xor.ag = getelementptr inbounds i64, ptr %aq, i64 %xor.i
      %xor.bg = getelementptr inbounds i64, ptr %bq, i64 %xor.i
      %xor.av = load <2 x i64>, ptr %xor.ag, align 8
      %xor.bv = load <2 x i64>, ptr %xor.bg, align 8
      %xor.rv = xor <2 x i64> %xor.av, %xor.bv
      store <2 x i64> %xor.rv, ptr %xor.ag, align 8
      %xor.next = add nuw nsw i64 %xor.i, 2
      %xor.done = icmp eq i64 %xor.next, %xor.n2
      br i1 %xor.done, label %xor.tail, label %xor.loop
    xor.tail:
      %xor.base = phi i64 [ 0, %xor.general ], [ %xor.n2, %xor.loop ]
      %xor.odd = icmp ult i64 %xor.base, %n
      br i1 %xor.odd, label %xor.scalar, label %finish
    xor.scalar:
      %xor.sag = getelementptr inbounds i64, ptr %aq, i64 %xor.base
      %xor.sbg = getelementptr inbounds i64, ptr %bq, i64 %xor.base
      %xor.sav = load i64, ptr %xor.sag, align 8
      %xor.sbv = load i64, ptr %xor.sbg, align 8
      %xor.srv = xor i64 %xor.sav, %xor.sbv
      store i64 %xor.srv, ptr %xor.sag, align 8
      br label %finish

    finish:
      %topi = sub nuw nsw i64 %n, 1
      %topg = getelementptr inbounds i64, ptr %aq, i64 %topi
      %top = load i64, ptr %topg, align 8
      ret i64 %top
  IR

fn __bigint_and_mut_raw(a, b) (i64 i64) i64
  if __bigint_bw_is_integer(a) == 0
    return ccall_nobox("w_bit_and", a, b)
  if __bigint_bw_is_integer(b) == 0
    return ccall_nobox("w_bit_and", a, b)
  zero = -1688849860263936 ## i64
  negative_one = -1407374883553281 ## i64
  if a == b || b == negative_one
    return a
  if a == zero || b == zero
    return zero
  if a == negative_one
    return ccall_nobox("w_bigint_mark_shared_value", b)
  n = __bigint_bw_mut_width(a, b)
  if n == 0
    return __bigint_and_raw(a, b)
  ap = (a & 140737488355327) + 16 ## i64
  bp = (b & 140737488355327) + 16 ## i64
  top = __bigint_bw_mut_kernel(ap, bp, n, 0)
  if n == 1
    return ccall_nobox("w_bigint_seal_raw", a, n)
  if top == 0
    return ccall_nobox("w_bigint_seal_raw", a, n)
  a

fn __bigint_or_mut_raw(a, b) (i64 i64) i64
  if __bigint_bw_is_integer(a) == 0
    return ccall_nobox("w_bit_or", a, b)
  if __bigint_bw_is_integer(b) == 0
    return ccall_nobox("w_bit_or", a, b)
  zero = -1688849860263936 ## i64
  negative_one = -1407374883553281 ## i64
  if a == b || b == zero
    return a
  if a == zero
    return ccall_nobox("w_bigint_mark_shared_value", b)
  if a == negative_one || b == negative_one
    return negative_one
  n = __bigint_bw_mut_width(a, b)
  if n == 0
    return __bigint_or_raw(a, b)
  ap = (a & 140737488355327) + 16 ## i64
  bp = (b & 140737488355327) + 16 ## i64
  __bigint_bw_mut_kernel(ap, bp, n, 1)
  a

fn __bigint_xor_mut_raw(a, b) (i64 i64) i64
  if __bigint_bw_is_integer(a) == 0
    return ccall_nobox("w_bit_xor", a, b)
  if __bigint_bw_is_integer(b) == 0
    return ccall_nobox("w_bit_xor", a, b)
  zero = -1688849860263936 ## i64
  if a == b
    return zero
  if b == zero
    return a
  if a == zero
    return ccall_nobox("w_bigint_mark_shared_value", b)
  n = __bigint_bw_mut_width(a, b)
  if n == 0
    return __bigint_xor_raw(a, b)
  ap = (a & 140737488355327) + 16 ## i64
  bp = (b & 140737488355327) + 16 ## i64
  top = __bigint_bw_mut_kernel(ap, bp, n, 2)
  if n == 1
    return ccall_nobox("w_bigint_seal_raw", a, n)
  if top == 0
    return ccall_nobox("w_bigint_seal_raw", a, n)
  a
