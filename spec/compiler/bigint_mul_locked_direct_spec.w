# A protected and locked exact-BigInt multiplication may enter the compiled
# Core worker directly. The worker must preserve every neighboring built-in
# route: exact source leaves, the schoolbook band, C fallbacks, signs,
# demotion, and pointer-identical squaring.

use core/numeric/big_int

-> check(label, got, expected)
  if got != expected
    << "FAIL [label]: got=[got] expected=[expected]"
    exit 1

-> multiply(a, b)(BigInt BigInt)
  a * b

-> builtin(a, b)(BigInt BigInt)
  ccall("w_bigint_mul_builtin_exact", a, b)

-> square(a)(BigInt)
  a * a

+ BigIntMulLockedProbe
  -> *(other)
    7301

Tungsten.PROTECT_THE_CORE!
Tungsten.LOCK_THE_DOORS!

word = (1 << 63) + 29
base = 1 << 64

# One-limb through eight-limb scalar leaves, in both operand orders.
i = 1
while i <= 8
  wide = (1 << (64 * i - 1)) + (i * 37) + 1
  expected = builtin(wide, word)
  check("mul1 forward [i]", multiply(wide, word), expected)
  check("mul1 reverse [i]", multiply(word, wide), expected)
  i += 1

# Beyond the source scalar leaves and inside/outside source schoolbook.
nine = (1 << (64 * 9 - 1)) + 97
check("mul1 width nine", multiply(nine, word), builtin(nine, word))
a2 = (1 << 126) + 113
b2 = (1 << 125) + 131
a3 = (1 << 190) + 127
a4 = (1 << 254) + 139
check("schoolbook two by two", multiply(a2, b2), builtin(a2, b2))
a24 = (1 << (64 * 24 - 1)) + 149
b24 = (1 << (64 * 24 - 2)) + 163
check("schoolbook width twenty-four", multiply(a24, b24), builtin(a24, b24))
a25 = (1 << (64 * 25 - 1)) + 179
b25 = (1 << (64 * 25 - 2)) + 191
check("C fallback width twenty-five", multiply(a25, b25), builtin(a25, b25))

# Exact identity retains square arithmetic: one-limb raw positive headers use
# the committed native leaf, while wider identities use the unchanged exact C
# dispatcher. Dynamic identity reaches the same lowering after the tag checks.
check("one-limb syntactic square", square(word), builtin(word, word))
check("one-limb overlay-negative square", square(0 - word),
      builtin(0 - word, 0 - word))
check("syntactic square", square(a2), builtin(a2, a2))
check("two-limb overlay-negative square", square(0 - a2),
      builtin(0 - a2, 0 - a2))
check("three-limb syntactic square", square(a3), builtin(a3, a3))
check("three-limb overlay-negative square", square(0 - a3),
      builtin(0 - a3, 0 - a3))
check("four-limb syntactic square", square(a4), builtin(a4, a4))
check("four-limb overlay-negative square", square(0 - a4),
      builtin(0 - a4, 0 - a4))
same = a2
check("dynamic identity square", multiply(a2, same), builtin(a2, a2))

check("negative left", multiply(0 - nine, word), builtin(0 - nine, word))
check("negative right", multiply(nine, 0 - word), builtin(nine, 0 - word))

# A BigInt-inferred value may demote to an inline i48 at runtime; the exact
# heap-tag guard must reject it before entering the source worker.
heap = 1 << 48
demoted = (heap + 1) - heap
check("demoted left", multiply(demoted, word), word)
check("demoted right", multiply(word, demoted), word)

# A stale exact type fact must not bypass ordinary receiver dispatch. The
# payload tag guard rejects the user object before either BigInt header load.
check("non-BigInt receiver fallback",
      multiply(BigIntMulLockedProbe.new(), word), 7301)

<< "PASS BigInt locked direct worker"
