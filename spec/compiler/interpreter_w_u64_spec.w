# The eval engine mirrors native w_u64 boxing with its arbitrary-precision
# Integer representation, including the unsigned half above signed i64 max.

-> box_u64(value)(u64)
  ccall("w_u64", value)

-> check(name, got, expected)
  if got.to_s() != expected
    << "FAIL [name]: got=[got] expected=[expected]"
    exit(1)

values = u64[4]
values[0] = 17
values[1] = 140737488355328
values[2] = 9223372036854775808
values[3] = 18446744073709551615

check("inline", box_u64(values[0]), "17")
check("heap", box_u64(values[1]), "140737488355328")
check("high_bit", box_u64(values[2]), "9223372036854775808")
check("max", box_u64(values[3]), "18446744073709551615")

<< "interpreter w_u64: ok"
