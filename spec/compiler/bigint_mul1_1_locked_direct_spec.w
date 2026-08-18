# Protected+locked exact-BigInt multiplication may test the committed
# positive, distinct one-limb leaf before entering the polymorphic dispatcher.
# Every neighboring shape must retain ordinary multiplication semantics.

-> check(label, got, expected)
  if got != expected
    << "FAIL [label]: got=[got] expected=[expected]"
    exit 1

-> multiply(a, b)(BigInt BigInt)
  a * b

# Syntactically obvious squaring is excluded before the closed-world guard is
# emitted, preserving the dedicated square path without a runtime precheck.
-> square(a)(BigInt)
  a * a

Tungsten.PROTECT_THE_CORE!
Tungsten.LOCK_THE_DOORS!

base = 1 << 64
heap = 1 << 48
a = heap + 17
b = (1 << 63) + 29

check("positive distinct one limb", multiply(a, b).to_s(),
      "2596148429267570619752649020408301")
check("commuted one limb", multiply(b, a).to_s(),
      "2596148429267570619752649020408301")
check("syntactic square", square(a).to_s(),
      "79228162514273907742752112929")

# Distinct parameter names can still carry one identical WValue. The runtime
# identity test must send this to the same dedicated square route.
same = a
check("dynamic identity square", multiply(a, same).to_s(),
      "79228162514273907742752112929")
check("negative left fallback", multiply(0 - a, b).to_s(),
      "-2596148429267570619752649020408301")
check("negative right fallback", multiply(a, 0 - b).to_s(),
      "-2596148429267570619752649020408301")
check("two limb left fallback", multiply(base + 37, heap + 3).to_s(),
      "5192296858534882979177291596169327")
check("two limb right fallback", multiply(heap + 3, base + 37).to_s(),
      "5192296858534882979177291596169327")

# A BigInt-inferred expression may demote to an inline i48 at runtime. The
# first-stage exact-tag check must reject it before either header load.
demoted = (heap + 1) - heap
check("demoted left tag fallback", multiply(demoted, b), b)
check("demoted right tag fallback", multiply(a, demoted), a)

<< "PASS BigInt mul1@1 locked direct lowering"
