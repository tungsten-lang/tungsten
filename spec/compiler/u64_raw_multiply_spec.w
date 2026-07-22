# u64 x u64 multiply lowers to a raw wrapping LLVM `mul` when both operands
# are raw-u64-typed — verified at the IR level 2026-07-22 for annotated
# locals at top level, in functions, in Thread closures, and fed from
# subscript reads. This spec pins the mod-2^64 SEMANTICS with xorshift64*
# reference outputs (independent Python-oracle values, inlined) plus a
# 10M-iteration accumulator; if the lowering ever regresses to the
# checked/promoting multiply, wrapping semantics stay identical but these
# exact values guard against any truncation/sign slip in a reimplementation.
#
# Run: `bin/tungsten -o /tmp/u64m spec/compiler/u64_raw_multiply_spec.w && /tmp/u64m`

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

-> xs_next(cell)
  x = cell[0] ## u64
  x = x ^ (x >> 12)
  x = x ^ (x << 25)
  x = x ^ (x >> 27)
  cell[0] = x
  m = 2685821657736338717 ## u64
  (x * m) ## u64

cell = i64[2]
cell[0] = 1
o1 = xs_next(cell)
o2 = xs_next(cell)
o3 = xs_next(cell)
check("xs64.seed1.out1", o1.to_s(16), "47e4ce4b896cdd1d")
check("xs64.seed1.out2", o2.to_s(16), "abcfa6a8e079651d")
check("xs64.seed1.out3", o3.to_s(16), "b9d10d8feb731f57")

cell[0] = 88172645463325252
acc = 0 ## u64
i = 0 ## i64
while i < 10_000_000
  acc = acc ^ xs_next(cell)
  i += 1
check("xs64.10M_accumulator", acc.to_s(), "8847067712279786544")

a = 18446744073709551615 ## u64
b = 18446744073709551615 ## u64
check("u64.max_times_max_wraps", ((a * b) ## u64).to_s(), "1")
