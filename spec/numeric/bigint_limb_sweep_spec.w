# Limb-count sweep 1..64 through abs, neg, +, -, <<, >> with a to_s/from_s
# round-trip at every width. The benchmark matrix's DEFAULT_SIZES jumps
# 16 -> 24 -> 32, so 17..23 — exactly where hybrid capacity classes diverge
# from power-of-two ones — is otherwise a correctness blind spot.

-> check(name, ok)
  if ok
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

(1..64).each -> (k)
  bits = 64 * k - 7
  tag = "@" + k.to_s() + "limbs"
  a = (1 << bits) + k * 12345 + 7
  b = (1 << (bits - 3)) + k * 54321 + 3
  na = 0 - a

  check("neg.involution" + tag, 0 - na == a)
  check("abs.negative" + tag, na.abs() == a)
  check("abs.positive" + tag, a.abs() == a)

  check("add.sub.inverse" + tag, (a + b) - b == a)
  check("sub.add.inverse" + tag, (a - b) + b == a)
  check("add.cancel.zero" + tag, a + na == 0)
  check("sub.self.zero" + tag, a - a == 0)

  check("shift.sublimb" + tag, (a << 13) >> 13 == a)
  check("shift.limb.boundary" + tag, (a << 64) >> 64 == a)
  check("shift.top.extract" + tag, a >> bits == 1)

  check("to_s.roundtrip" + tag, a.to_s().to_i() == a)
  check("to_s.roundtrip.neg" + tag, na.to_s().to_i() == na)

<< "bigint_limb_sweep_spec: all checks passed"
