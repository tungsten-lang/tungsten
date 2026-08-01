# Embedded-kernel benchmark: the multi-limb add carry chain coded three ways.
#   native  — portable .w loop (addcarry intrinsic; auto-unroll8 latch hint)
#   ll      — embedded LLVM IR, i256 blocks (legalization emits adds/adcs runs)
#   asm     — embedded AArch64, hardware ADCS chain (runtime.c block schedule)
# Compile-only: bin/tungsten -o /tmp/bench_embed benchmarks/limb_native/bench_embed.w && /tmp/bench_embed

fn wn_add_n(rp, ap, bp, n) (u64[] u64[] u64[] i64) i64
  carry = 0 ## u64
  i = 0 ## i64
  while i < n
    x = ap[i] ## u64
    y = bp[i] ## u64
    s1 = x + carry
    c1 = addcarry(x, carry)
    s2 = s1 + y
    c2 = addcarry(s1, y)
    rp[i] = s2
    carry = (c1 + c2) ## u64
    i += 1
  carry ## i64

# n must be a positive multiple of 4.
fn ll_add_n4(rp, ap, bp, n) (u64[] u64[] u64[] i64) i64
  ll <<~IR
    %pa0 = inttoptr i64 %ap to ptr
    %pb0 = inttoptr i64 %bp to ptr
    %pr0 = inttoptr i64 %rp to ptr
    %blocks = lshr i64 %n, 2
    br label %loop
  loop:
    %i = phi i64 [ 0, %0 ], [ %inext, %loop ]
    %cin = phi i64 [ 0, %0 ], [ %cout, %loop ]
    %off = shl i64 %i, 2
    %pa = getelementptr i64, ptr %pa0, i64 %off
    %pb = getelementptr i64, ptr %pb0, i64 %off
    %pr = getelementptr i64, ptr %pr0, i64 %off
    %a = load i256, ptr %pa, align 8
    %b = load i256, ptr %pb, align 8
    %cw = zext i64 %cin to i256
    %s0 = add i256 %a, %b
    %s = add i256 %s0, %cw
    store i256 %s, ptr %pr, align 8
    %g0 = icmp ult i256 %s0, %a
    %g1 = icmp ult i256 %s, %s0
    %g = or i1 %g0, %g1
    %cout = zext i1 %g to i64
    %inext = add i64 %i, 1
    %done = icmp eq i64 %inext, %blocks
    br i1 %done, label %exit, label %loop
  exit:
    ret i64 %cout
  IR

# n must be a positive multiple of 8.
fn asm_add_n8(rp, ap, bp, n) (u64[] u64[] u64[] i64) i64
  asm <<~ASM
    cmn xzr, xzr
  1:
    ldp x4, x5, [x1], #32
    ldp x6, x7, [x1, #-16]
    ldp x8, x9, [x2], #32
    ldp x10, x11, [x2, #-16]
    adcs x12, x4, x8
    adcs x13, x5, x9
    adcs x14, x6, x10
    adcs x15, x7, x11
    stp x12, x13, [x0], #32
    stp x14, x15, [x0, #-16]
    ldp x4, x5, [x1], #32
    ldp x6, x7, [x1, #-16]
    ldp x8, x9, [x2], #32
    ldp x10, x11, [x2, #-16]
    adcs x12, x4, x8
    adcs x13, x5, x9
    adcs x14, x6, x10
    adcs x15, x7, x11
    stp x12, x13, [x0], #32
    stp x14, x15, [x0, #-16]
    sub x3, x3, #8
    cbnz x3, 1b
    cset x0, hs
    ret
  ASM

-> fill(arr, n, seed)
  state = seed ## u64
  i = 0 ## i64
  while i < n
    state = state ^ (state << 13)
    state = state ^ (state >> 7)
    state = state ^ (state << 17)
    arr[i] = state
    i += 1
  nil

-> bench_one(label, which, rp, ap, bp, n, iters)
  best = ~1000000.0
  rep = 0 ## i64
  while rep < 7
    t0 = clock()
    it = 0 ## i64
    sink = 0 ## i64
    while it < iters
      c = 0 ## i64
      if which == 0
        c = wn_add_n(rp, ap, bp, n)
      elsif which == 1
        c = ll_add_n4(rp, ap, bp, n)
      else
        c = asm_add_n8(rp, ap, bp, n)
      sink = sink + c
      it += 1
    t1 = clock()
    el = t1 - t0
    if el < best
      best = el
    rep += 1
  ns_op = best * ~1000000000.0 / iters.to_f()
  per_limb = ns_op / n.to_f()
  << label + " n=" + n.to_s() + ": " + ns_op.to_s() + " ns/op, " + per_limb.to_s() + " ns/limb"
  nil

sizes = [64, 256, 1024]
si = 0
while si < sizes.size()
  n = sizes[si] ## i64
  ap = u64[n]
  bp = u64[n]
  rp = u64[n]
  rr = u64[n]
  fill(ap, n, 88172645463325252)
  fill(bp, n, 1442695040888963407)

  # cross-check all three agree (including carry-out)
  c0 = wn_add_n(rp, ap, bp, n)
  c1 = ll_add_n4(rr, ap, bp, n)
  i = 0 ## i64
  while i < n
    if (rp[i] ## u64) != (rr[i] ## u64)
      << "MISMATCH ll limb " + i.to_s()
      exit 1
    i += 1
  if c0 != c1
    << "MISMATCH ll carry"
    exit 1
  c2 = asm_add_n8(rr, ap, bp, n)
  i = 0
  while i < n
    if (rp[i] ## u64) != (rr[i] ## u64)
      << "MISMATCH asm limb " + i.to_s()
      exit 1
    i += 1
  if c0 != c2
    << "MISMATCH asm carry"
    exit 1

  iters = 3000000 / n
  bench_one("native.w ", 0, rp, ap, bp, n, iters)
  bench_one("embed .ll", 1, rp, ap, bp, n, iters)
  bench_one("embed asm", 2, rp, ap, bp, n, iters)
  si += 1
<< "bench_embed done"
