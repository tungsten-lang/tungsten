# Regression: compound assignments to indexed typed-array parameters must
# read and update those elements, not unrelated uninitialized locals.

-> update_values(values) (i64[]) i64
  values[0] += 1
  values[1] *= 3
  values[0] + values[1]

values = i64[2]
values[0] = 41
values[1] = 7
result = update_values(values) ## i64
if result != 63 || values[0] != 42 || values[1] != 21
  << "FAIL indexed compound assignment result=" + result.to_s() + " first=" + values[0].to_s() + " second=" + values[1].to_s()
  exit(1)

<< "PASS indexed compound assignment parameter"
