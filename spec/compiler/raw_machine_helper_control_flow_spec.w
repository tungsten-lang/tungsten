# Raw machine helpers must preserve their annotated ABI through explicit early
# returns, cross-width casts, reassigned locals, and nested helper calls.

-> raw_machine_early_return(value) (u64) i64
  if value == 0
    return 7 ## i64
  9 ## i64

-> raw_machine_wide_low(a, b) (u64 u64) u64
  product = (a ## u128) * (b ## u128) ## u128
  product ## u64

-> raw_machine_branch_reassign(value, modulus) (u64 u64) u64
  reduced = value ## u64
  if reduced >= modulus
    reduced = reduced - modulus ## u64
  reduced

-> raw_machine_nested(value, modulus) (u64 u64) u64
  raw_machine_branch_reassign(value, modulus) ## u64

-> raw_machine_conditional(value) (u64) u64
  selected = (value == 0 ? 18446744073709551615 : 9223372036854775808) ## u64
  selected

-> raw_machine_mont_shape(a, b, modulus, neg_inverse) (u64 u64 u64 u64) u64
  product = (a ## u128) * (b ## u128) ## u128
  multiplier = (product ## u64) * neg_inverse ## u64
  correction = (multiplier ## u128) * (modulus ## u128) ## u128
  product_low = product ## u64
  product_high = (product >> 64) ## u64
  correction_low = correction ## u64
  correction_high = (correction >> 64) ## u64
  low_sum = product_low + correction_low ## u64
  carry = 0 ## u64
  if low_sum < product_low
    carry = 1 ## u64
  reduced = product_high + correction_high ## u64
  reduced = reduced + carry ## u64
  overflow = 0 ## i64
  if reduced < product_high
    overflow = 1
  if carry != 0
    if reduced == product_high
      overflow = 1
  if overflow != 0 || reduced >= modulus
    reduced = reduced - modulus ## u64
  reduced

if raw_machine_early_return(0 ## u64) != 7
  << "FAIL raw machine early return"
  exit(1)
if raw_machine_early_return(1 ## u64) != 9
  << "FAIL raw machine tail return"
  exit(1)

wide = raw_machine_wide_low(18446744073709551615 ## u64, 3 ## u64) ## u64
wide_expected = 18446744073709551613 ## u64
if wide != wide_expected
  << "FAIL raw machine cross-width cast"
  exit(1)

reduced = raw_machine_nested(18446744073709551615 ## u64, 97 ## u64) ## u64
reduced_expected = 18446744073709551518 ## u64
if reduced != reduced_expected
  << "FAIL raw machine nested branch reassign"
  exit(1)

conditional_max = raw_machine_conditional(0 ## u64) ## u64
if conditional_max != (18446744073709551615 ## u64)
  << "FAIL raw machine conditional true arm"
  exit(1)
conditional_high = raw_machine_conditional(1 ## u64) ## u64
if conditional_high != (9223372036854775808 ## u64)
  << "FAIL raw machine conditional false arm"
  exit(1)

montgomery = raw_machine_mont_shape(
  1234567890123456789 ## u64,
  9876543210987654321 ## u64,
  18446744073709551557 ## u64,
  14694863923124558067 ## u64
) ## u64
if montgomery != (13573944604496830239 ## u64)
  << "FAIL raw machine Montgomery high-bit reduction"
  exit(1)

<< "PASS raw machine helper control flow"
