# The stable BigInt#isqrt seam must follow ordinary open-world method-table
# replacement. PROTECT_THE_CORE! programs reject this reopen before lowering;
# ordinary programs select the final plain definition, just like a method send.

-> opaque_bigint
  ccall("w_bigint_from_dec_str", "170141183460469231731687303715884105727")

-> check(label, got, expected)
  if got != expected
    << "FAIL [label]: got=[got] expected=[expected]"
    exit(1)

+ BigInt
  -> isqrt
    7001

value = opaque_bigint()
check("ordinary reopened dispatch", value.isqrt, 7001)
check("stable seam selects final definition", ccall("__w_bigint_isqrt_src", value), 7001)

<< "PASS BigInt isqrt reopen source seam"
