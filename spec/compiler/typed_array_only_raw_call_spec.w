# Regression: a top-level function whose only parameters are typed arrays may
# use the raw integer return ABI.  The array handle itself remains a boxed
# WValue, while the result must cross direct and forward-call boundaries as a
# full-width machine integer without w_int/w_to_i64 churn or i48 truncation.

-> array_only_forward(values) (i64[]) i64
  array_only_value(values)

-> array_only_value(values) (i64[]) i64
  values[0] + values[1]

-> array_pair_forward(left, right) (i64[] i64[]) i64
  array_pair_value(left, right)

-> array_pair_value(left, right) (i64[] i64[]) i64
  left[0] ^ right[0]

-> array_only_expect(label, got, want)
  if got != want
    << "FAIL " + label + " got=" + got.to_s() + " want=" + want.to_s()
    exit(1)

values = i64[2]
values[0] = 281474976710656
values[1] = 17
array_only_expect("single array", array_only_forward(values), 281474976710673)

left = i64[1]
right = i64[1]
left[0] = 562949953421312
right[0] = 33
array_only_expect("array pair", array_pair_forward(left, right), 562949953421345)

<< "PASS typed-array-only raw calls"
