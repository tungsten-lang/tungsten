# Embedded LLVM IR (`ll <<~IR`) and AArch64 assembly (`asm <<~ASM`) function
# bodies. A top-level typed fn whose entire body is one ll/asm call with a
# string literal (heredocs lex raw — brackets never interpolate) becomes that
# IR or asm verbatim. Params: machine ints raw; typed arrays arrive as the
# start-corrected element-0 data address. Compile-only (no interpreter path).
#
# Run: bin/tungsten -o /tmp/embed_spec spec/compiler/embedded_ll_asm_spec.w && /tmp/embed_spec

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

# --- ll: plain arithmetic -----------------------------------------------
fn ll_addmul(a, b) (i64 i64) i64
  ll <<~IR
    %s = add i64 %a, %b
    %p = mul i64 %s, 3
    ret i64 %p
  IR

# --- ll: u64 return boxes unsigned --------------------------------------
fn ll_topbit(a) (u64) u64
  ll <<~IR
    %r = or i64 %a, u0x8000000000000000
    ret i64 %r
  IR

# --- ll: array data pointer + control flow ------------------------------
fn ll_sum4(ap) (u64[]) i64
  ll <<~IR
    %p = inttoptr i64 %ap to ptr
    %v0 = load i64, ptr %p, align 8
    %p1 = getelementptr i64, ptr %p, i64 1
    %v1 = load i64, ptr %p1, align 8
    %p2 = getelementptr i64, ptr %p, i64 2
    %v2 = load i64, ptr %p2, align 8
    %p3 = getelementptr i64, ptr %p, i64 3
    %v3 = load i64, ptr %p3, align 8
    %s01 = add i64 %v0, %v1
    %s23 = add i64 %v2, %v3
    %s = add i64 %s01, %s23
    ret i64 %s
  IR

# --- ll: multi-limb add via wide-integer legalization -------------------
# One i256 add per 4-limb block: LLVM legalizes to adds/adcs chains — the
# carry-chain codegen the portable-loop pattern matching cannot deliver
# (flag spills across back-edges, LLVM #74493).
fn ll_add4_wide(rp, ap, bp) (u64[] u64[] u64[]) i64
  ll <<~IR
    %pa = inttoptr i64 %ap to ptr
    %pb = inttoptr i64 %bp to ptr
    %pr = inttoptr i64 %rp to ptr
    %a = load i256, ptr %pa, align 8
    %b = load i256, ptr %pb, align 8
    %s = add i256 %a, %b
    store i256 %s, ptr %pr, align 8
    %carry_wide = icmp ult i256 %s, %a
    %carry = zext i1 %carry_wide to i64
    ret i64 %carry
  IR

# --- asm: scalar --------------------------------------------------------
fn asm_muladd(a, b) (i64 i64) i64
  asm <<~ASM
    madd x0, x0, x1, x1
    ret
  ASM

# --- asm: the real thing — n-limb add_n with a hardware ADCS chain ------
# x0=rp x1=ap x2=bp x3=n (n > 0, multiple of 4). Returns carry-out.
fn asm_add_n4(rp, ap, bp, n) (u64[] u64[] u64[] i64) i64
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
    sub x3, x3, #4
    cbnz x3, 1b
    cset x0, hs
    ret
  ASM

check("ll.addmul", ll_addmul(10, 4), 42)
one = 1 ## u64
check("ll.topbit_unsigned_box", ll_topbit(one).to_s(16), "8000000000000001")

xs = u64[4]
xs[0] = 100
xs[1] = 200
xs[2] = 300
xs[3] = 400
check("ll.sum4_array_ptr", ll_sum4(xs), 1000)

a4 = u64[4]
b4 = u64[4]
r4 = u64[4]
i = 0 ## i64
while i < 4
  a4[i] = 18446744073709551615  # all ones: forces a full carry chain
  b4[i] = 0
  i += 1
b4[0] = 1
carry = ll_add4_wide(r4, a4, b4)
check("ll.add4_wide_carry", carry, 1)
check("ll.add4_wide_r0", (r4[0] ## u64).to_s(), "0")
check("ll.add4_wide_r3", (r4[3] ## u64).to_s(), "0")

check("asm.muladd", asm_muladd(6, 7), 49)

n = 64 ## i64
aa = u64[n]
bb = u64[n]
rr = u64[n]
i = 0
while i < n
  aa[i] = 18446744073709551615
  bb[i] = 0
  i += 1
bb[0] = 1
carry2 = asm_add_n4(rr, aa, bb, n)
check("asm.add_n4_ripple_carry", carry2, 1)
ok = 1 ## i64
i = 0
while i < n
  if (rr[i] ## u64) != 0
    ok = 0
  i += 1
check("asm.add_n4_ripple_zeros", ok, 1)

# random cross-check vs addcarry-intrinsic reference
state = 88172645463325252 ## u64
i = 0
while i < n
  state = state ^ (state << 13)
  state = state ^ (state >> 7)
  state = state ^ (state << 17)
  aa[i] = state
  state = state ^ (state << 13)
  state = state ^ (state >> 7)
  state = state ^ (state << 17)
  bb[i] = state
  i += 1
carry3 = asm_add_n4(rr, aa, bb, n)
ref_carry = 0 ## u64
i = 0
while i < n
  x = aa[i] ## u64
  y = bb[i] ## u64
  s1 = x + ref_carry
  c1 = addcarry(x, ref_carry)
  s2 = s1 + y
  c2 = addcarry(s1, y)
  if (rr[i] ## u64) != (s2 ## u64)
    << "FAIL asm.add_n4_random limb " + i.to_s()
    exit 1
  ref_carry = (c1 + c2) ## u64
  i += 1
check("asm.add_n4_random_carry", carry3, ref_carry ## i64)
<< "embedded_ll_asm_spec: all checks passed"
