# clz/clz32 (leading zeros), ctz/ctz32 (trailing zeros) and popcount32 on
# raw machine words, alongside the existing popcount and cttz. The 32-bit
# forms use the low 32 bits; zero answers the word width. Compiled code emits
# one llvm.ctlz / cttz / ctpop each; the interpreter computes the same values.

$failures = 0

-> check(label, got, want)
  if got != want
    << "FAIL [label]: got [got], want [want]"
    $failures = $failures + 1

-> lz(x) (i64) i64
  clz(x)

-> lz32(x) (i64) i64
  clz32(x)

-> tz(x) (i64) i64
  ctz(x)

-> tz32(x) (i64) i64
  ctz32(x)

-> pc32(x) (i64) i64
  popcount32(x)

-> elem_lz(a, i) (i32[] i64) i64
  clz32(a[i])

check("clz 1", lz(1), 63)
check("clz 0", lz(0), 64)
check("clz top", lz(0 - 1), 0)
check("clz 255", lz(255), 56)
check("clz32 1", lz32(1), 31)
check("clz32 0", lz32(0), 32)
check("clz32 high bits ignored", lz32(4294967296 + 16), 27)
check("ctz 8", tz(8), 3)
check("ctz 0", tz(0), 64)
check("ctz32 0", tz32(0), 32)
check("ctz32 high", tz32(4294967296), 32)
check("popcount32", pc32(4294967295 + 4294967296), 32)
check("popcount32 small", pc32(7), 3)
a = i32[2]
a[0] = 0 - 1
a[1] = 1024
check("clz32 of negative i32", elem_lz(a, 0), 0)
check("clz32 of element", elem_lz(a, 1), 21)

if $failures > 0
  exit(1)
<< "PASS bit count intrinsics"
