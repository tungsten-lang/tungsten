# String#to_i promotes past i64 instead of saturating.
#
# Regression for the 2026-07-22 fix: the strtoll-based parse returned
# LLONG_MAX/MIN (silent saturation) for decimals outside i64. Default Int is
# arbitrary-precision, so overflow must promote to bignum via
# w_bigint_from_dec_str. Non-decimal bases keep the fixed-width parse.
#
# Run: `bin/tungsten -o /tmp/sti spec/core/string_to_i_bignum_spec.w && /tmp/sti`

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

check("to_i.in_range", "12345".to_i(), 12345)
check("to_i.negative", "-12345".to_i(), 0 - 12345)
check("to_i.i64_max", "9223372036854775807".to_i(), 9223372036854775807)
check("to_i.i64_max_plus_one", "9223372036854775808".to_i().to_s(), "9223372036854775808")
check("to_i.u64_max", "18446744073709551615".to_i().to_s(), "18446744073709551615")
check("to_i.huge", "340282366920938463463374607431768211456".to_i().to_s(), "340282366920938463463374607431768211456")
check("to_i.neg_overflow", "-9223372036854775809".to_i().to_s(), "-9223372036854775809")
# Pre-existing (Ruby-divergent) behavior pinned as-is: to_i stops at the
# first underscore (numeric LITERALS accept underscores; String#to_i does
# not). The overflow fix deliberately leaves this untouched.
check("to_i.underscore_stops", "18_446".to_i(), 18)
check("to_i.hex_base", "ff".to_i(16), 255)
