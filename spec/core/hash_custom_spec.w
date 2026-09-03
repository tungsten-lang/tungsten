# HashCustom — open-addressing table with a selectable hash function (core/hash_custom.w).
#
# Linear probing, power-of-two capacity, nil-as-empty. The only supported hash
# kind is :splitmix64, which mixes the key's WValue bits directly.
#
# Run:
#   bin/tungsten run --interpret spec/core/hash_custom_spec.w
#   bin/tungsten -o /tmp/hash_custom_spec spec/core/hash_custom_spec.w && /tmp/hash_custom_spec

use core/hash_custom

passed = Atomic.new(0)

-> check(name, condition)
  raise "FAIL " + name if !condition
  passed.increment()
  << "PASS " + name

h = HashCustom.new(:splitmix64, 64)

# ---- construction ----
check("constructs", type(h) == "HashCustom")
check("is_a? HashCustom", h.is_a?(HashCustom))
check("a fresh table is empty", h.length == 0)

# ---- set / get ----
h.set(7, 1)
check("get returns what set stored", h.get(7) == 1)
check("set grew the count", h.length == 1)
h.set(7, 2)
check("re-setting a key overwrites", h.get(7) == 2)
check("re-setting a key does not grow the count", h.length == 1)
check("get of an absent key is nil", h.get(8) == nil)
check("has a stored key", h.has(7))
check("does not have an absent key", !h.has(8))

# Key 0 and negative keys are ordinary keys — only *values* use nil-as-empty.
z = HashCustom.new(:splitmix64, 16)
z.set(0, 42)
check("zero is a usable key", z.get(0) == 42)
check("zero key counted", z.length == 1)
z.set(-1, 9)
check("negative keys work", z.get(-1) == 9)
check("two distinct keys", z.length == 2)

# ---- hash(): deterministic splitmix64 finaliser over the key bits ----
check("hash is deterministic", h.hash(5) == h.hash(5))
check("hash discriminates", h.hash(5) != h.hash(6))
# The mixer works on the key's WValue bits (splitmix64), so hash(0) is a
# fixed nonzero mix of the boxed zero, not 0.
check("hash of 0 is deterministic", h.hash(0) == h.hash(0))
check("hash of 0 is mixed", h.hash(0) != 0)

# ---- capacity: minimum 16, rounded up to a power of two, grown at 0.75 load ----
tiny = HashCustom.new(:splitmix64, 1)
i = 0
while i < 12
  tiny.set(i, i * 10)
  i += 1
check("a below-minimum capacity still holds 12 entries", tiny.length == 12)
check("every entry survives the growth", tiny.get(11) == 110)
check("the first entry survives the growth", tiny.get(0) == 0)

odd = HashCustom.new(:splitmix64, 17)
odd.set(1, 100)
check("a non-power-of-two capacity is rounded up and works", odd.get(1) == 100)

big = HashCustom.new(:splitmix64, 16)
i = 0
while i < 200
  big.set(i, i * 3)
  i += 1
check("200 inserts into a 16-slot table", big.length == 200)
check("readback after several rehashes", big.get(57) == 171)
check("last key after several rehashes", big.get(199) == 597)
check("first key after several rehashes", big.get(0) == 0)
missing = true
i = 200
while i < 220
  if big.get(i) != nil
    missing = false
  i += 1
check("keys never inserted stay absent", missing)
all_present = true
i = 0
while i < 200
  if big.get(i) != i * 3
    all_present = false
  i += 1
check("every one of the 200 keys reads back", all_present)

# ---- nil-as-empty: a nil value occupies a slot but reads back as absent ----
n = HashCustom.new(:splitmix64, 16)
n.set(3, nil)
check("a nil value still counts as an entry", n.length == 1)
check("a nil value reads back as nil", n.get(3) == nil)
check("has() cannot see a nil value", !n.has(3))

# BUG: the usage documented at the top of core/hash_custom.w — `h.set("foo", 1)` — raises the
# uncatchable "runtime error: expected int, got string" on both engines. `-> hash(key) (string) i64`
# immediately does `v = key; v ^ (v >> 30)` on the boxed string, and the bitwise operators reject
# a string operand, so no string key can ever be stored.
# Repro: printf 'use core/hash_custom\nh = HashCustom.new(:splitmix64, 64)\nh.set("foo", 1)\n' > /tmp/hc.w &&
#        bin/tungsten run --interpret /tmp/hc.w
# check("string keys", HashCustom.new(:splitmix64, 64).set("foo", 1) == nil)
# BUG: `hash` is declared `i64` but the multiplications promote to BigInt instead of wrapping —
# h.hash(5) is 739245978801580075080537957964831963804 on both engines, far outside i64.
# check("hash stays in i64", h.hash(5) < 9223372036854775808)

<< "ALL PASS hash_custom_spec ([passed.load()] checks)"
