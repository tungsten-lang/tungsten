-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

big = 10 ** 40
negbig = 0 - big

# neg! flips sign in place and returns the receiver
x = big + 0
check("neg!.returns_receiver", (x.neg! == x).to_s(), "true")
check("neg!.value", x.to_s(), negbig.to_s())
x.neg!
check("neg!.involution", x.to_s(), big.to_s())

# abs! on a negative value
y = 0 - (10 ** 45)
y.abs!
check("abs!.negative", y.to_s(), (10 ** 45).to_s())
# abs! on a positive value is a no-op
z = 10 ** 45
z.abs!
check("abs!.positive_noop", z.to_s(), (10 ** 45).to_s())

# mutation IS visible through aliases — the documented bang tradeoff
a = 10 ** 50
b = a
a.neg!
check("bang.alias_visible", (b < 0).to_s(), "true")

# arithmetic still correct after in-place mutation
# NB: `p + 0` returns p itself (identity fast path), so build a distinct
# value to mutate.
p = 10 ** 30
q = 10 ** 30
q.neg!
check("bang.arith_after", (p + q).to_s(), "0")
check("bang.mul_after", (q * 0 - 1).to_s(), "-1")
<< "bang_spec: all checks passed"

# Mixed-width isqrt in one process: the divide-and-conquer workspace grew on
# the operand width alone, but it also holds a guard-limb quotient buffer
# past that, so a later wider call whose operand still fit under a previous
# capacity overflowed the allocation. Widths deliberately interleave.
isq_ok = 1
[200, 800, 1500, 400, 3000, 900, 64].each -> (bits)
  isq_v = (1 << bits) + 12345
  isq_r = isq_v.isqrt
  if isq_r * isq_r > isq_v || (isq_r + 1) * (isq_r + 1) <= isq_v
    isq_ok = 0
check("isqrt.mixed_widths_one_process", isq_ok.to_s(), "1")
