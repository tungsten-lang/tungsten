# `## int` values that promoted to a heap BigInt must never be unboxed raw.
#
# `:int` is the BOXED integer type — that is what distinguishes `## int` from
# `## i64`, which is a machine int. Once a `:int` value exceeds i48 it becomes a
# heap BigInt, so `shl 16 / ashr 16` on it sign-extends POINTER bits and every
# op downstream computes on the pointer.
#
# Three lowering paths took that raw route (lowering/ops.w):
#   * the machine-int branch, entered because a plain integer literal infers
#     :i64 — so `big + 1` qualified through the literal alone;
#   * the inline bitwise/div/mod branch, guarded only by the overflow MODE;
#   * the inline comparison branch, likewise.
# Symptoms were pointer-derived garbage from +, -, *, & and >>, and `==`
# answering FALSE for equal values. All three now refuse a `:int` operand and
# fall to the guarded i48 path (tag-checked, w_add/w_sub/w_mul fallback) or the
# boxed runtime ops.
#
# Every expected value below is the interpreter's — it is the arbitrary-
# precision oracle, and these must agree exactly.
#
# Run: `bin/tungsten -o /tmp/ibp spec/compiler/int_bigint_promotion_spec.w && /tmp/ibp`

-> check(name, got, want)
  if got.to_s() == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want
    exit 1

# --- global `## int` promoted past i48 by its own addition ---
big = 140737488355327 ## int
b2 = big + big
check("promote.value", b2, "281474976710654")
check("promote.add", b2 + 1, "281474976710655")
check("promote.sub", b2 - 1, "281474976710653")
check("promote.mul", b2 * 2, "562949953421308")
check("promote.and", b2 & 255, "254")
check("promote.or", b2 | 1, "281474976710655")
check("promote.xor", b2 ^ 255, "281474976710401")
check("promote.shr", b2 >> 8, "1099511627775")
check("promote.div", b2 / 3, "93824992236884")
check("promote.mod", b2 % 7, "6")
check("promote.eq_true", b2 == 281474976710654, "true")
check("promote.eq_false", b2 == 5, "false")
check("promote.neq", b2 != 5, "true")
check("promote.lt", b2 < 5, "false")
check("promote.gt", b2 > 5, "true")
check("promote.gte", b2 >= 281474976710654, "true")

# --- same inside a function body (locals take different lowering paths) ---
-> local_ops
  b = 140737488355327 ## int
  l2 = b + b
  [(l2 + 1), (l2 & 255), (l2 >> 8), (l2 / 3), (l2 % 7), (l2 == 281474976710654)].to_s()
check("local.all_ops", local_ops, "\[281474976710655, 254, 1099511627775, 93824992236884, 6, true]")

# --- loop-carried accumulator crossing i48 mid-loop ---
-> doubling(n)
  acc = 140737488355327 ## int
  i = 0 ## i64
  while i < n
    acc = acc + acc
    i = i + 1
  acc
check("loop.three_doublings", doubling(3), "1125899906842616")
check("loop.ten_doublings", doubling(10), "144115188075854848")

# --- a promoted `:int` mixed with a genuine machine `## i64` operand ---
-> mixed
  b = 140737488355327 ## int
  m2 = b + b
  k = 4 ## i64
  m2 + k
check("mixed.int_plus_i64", mixed, "281474976710658")

# --- `## i64` is a MACHINE int and must keep wrapping semantics untouched ---
-> machine_i64
  x = 140737488355327 ## i64
  y = x + x
  [y, (y & 255), (y >> 8), (y == 281474976710654)].to_s()
check("machine.i64_unchanged", machine_i64, "\[281474976710654, 254, 1099511627775, true]")

# Negative promoted values sign-extend correctly rather than reading a pointer.
neg = 0 - 140737488355328 ## int
n2 = neg + neg
check("negative.value", n2, "-281474976710656")
check("negative.add", n2 + 1, "-281474976710655")
check("negative.abs_gt", n2 < 0, "true")
