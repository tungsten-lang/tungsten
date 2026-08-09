# BigDecimal — decimals whose significand exceeds i64. A >19-significant-
# digit decimal literal constructs one (both engines: the compiled path
# via w_decimal_from_digits, the walker via w_decimal_parse's big branch);
# arithmetic stays exact through boxed-integer significands and demotes
# back to plain Decimal when the significand fits i64 again.

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

x = 1234567890123456789012345.5
check("type", type(x), "BigDecimal")
check("to_s", x.to_s(), "1234567890123456789012345.5")

# Exact arithmetic, including a 49-digit product
check("add_half", (x + 0.5).to_s(), "1234567890123456789012346")
check("mul2", (x * 2).to_s(), "2469135780246913578024691")
check("square", (x * x).to_s(), "1524157875323883675049534714525228792577351411370.25")
check("roundtrip", (x * 2) / 2 == x, true)

# Demotion: results that fit i64 become plain Decimal again
check("self_sub", (x - x).to_s(), "0")
check("self_sub_type", type(x - x), "Decimal")

# Division follows the plain path's 12-digit precision policy
check("div3", (x / 3).to_s(), "411522630041152263004115.1666666666666")
check("div_half", (x / 0.5).to_s(), "2469135780246913578024691")

# Negation, abs, ordering
check("neg", (0 - x).to_s(), "-1234567890123456789012345.5")
check("abs_neg", (0 - x).abs == x, true)
check("cmp", x <=> 1234567890123456789012344.5, 1)
check("lt", 1234567890123456789012344.5 < x, true)

# Hash keys: equal values constructed differently must collide
h = {}
h[x] = "big"
k = 1234567890123456789012345.0 + 0.5
check("hash_key", h[k], "big")

# Mixed Float promotes to double (the established inexact boundary)
check("float_mix_type", type(x + ~1.5), "Float")

# Small-scale plain decimals are unaffected
y = 0.00000000000000000000001
check("small_type", type(y), "Decimal")
check("small_to_s", y.to_s(), "0.00000000000000000000001")

# Fractional BigDecimal with a wide fraction
z = 0.12345678901234567890123456789
check("frac_type", type(z), "BigDecimal")
check("frac_to_s", z.to_s(), "0.12345678901234567890123456789")
check("frac_sum", (z + z).to_s(), "0.24691357802469135780246913578")

<< "big_decimal_spec: all checks passed"
