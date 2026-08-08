# BigInt `/` and `%` semantics — pins the source-routed dispatch surface
# (weak-arm seam + BigInt#/ and BigInt#% plumbing bodies over the exported
# w_bigint_div/w_bigint_mod boundaries) on both engines. Division is
# TRUNCATED (C semantics): the quotient rounds toward zero and the
# remainder carries the dividend's sign.

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

a = (1 << 200) + 12345
b = (1 << 100) + 54321

q_want = 1267650600228229401496703151055
r_want = 2950783386
check("pp_div", a / b, q_want)
check("pp_mod", a % b, r_want)
check("roundtrip", (a / b) * b + (a % b), a)

# Truncated semantics, all sign combinations
check("np_div", (0 - a) / b, 0 - q_want)
check("np_mod", (0 - a) % b, 0 - r_want)
check("pn_div", a / (0 - b), 0 - q_want)
check("pn_mod", a % (0 - b), r_want)
check("nn_div", (0 - a) / (0 - b), q_want)
check("nn_mod", (0 - a) % (0 - b), 0 - r_want)

# One-limb heap pairs (the fused u64 arm, in-gate)
p1 = (1 << 60) + 999
p2 = (1 << 49) + 123
check("one_div", p1 / p2, 2047)
check("one_mod", p1 % p2, p1 - 2047 * p2)

# Exact multiple (Jebelean exact-division path)
m = (1 << 300) + 7
check("exact_div", (m * 987654321) / m, 987654321)
check("exact_mod", (m * 987654321) % m, 0)

# Dividend smaller than divisor
check("small_div", b / a, 0)
check("small_mod", b % a, b)

# Inline-int mixes stay on the C arms (gate excludes)
check("int_arg_div", a / 7, (a - a % 7) / 7)
check("int_arg_mod", a % 7, 1)

# Explicit operator sends
check("explicit_div", a./(b), q_want)
check("explicit_mod", a.%(b), r_want)

<< "bigint_divmod_spec: all checks passed"
