# A genuine plain BigInt operator reopen owns BigInt-left calls, but the
# complete stable seam also serves reverse mixed integer pairs. Those calls
# must stay on the raw helper instead of invoking a body whose receiver is not
# a BigInt.

-> opaque_integer(text)
  ccall("w_bigint_from_dec_str", text)

-> c_compare(a, b)
  ccall("w_bigint_compare_c", a, b)

-> check_small(label, got, expected)
  if got != expected
    << "FAIL " + label
    exit(1)

-> check_integer(label, got, expected_text)
  expected = opaque_integer(expected_text)
  if c_compare(got, expected) != 0
    << "FAIL " + label
    exit(1)

+ BigInt
  -> &(other)
    7001

  -> |(other)
    7002

  -> ^(other)
    7003

opaque = opaque_integer("9223372036854788153")
inline_value = 255

# Opaque values exercise the runtime route into the stable strong seam.
check_small("opaque BigInt lhs and", opaque & inline_value, 7001)
check_small("opaque BigInt lhs or", opaque | inline_value, 7002)
check_small("opaque BigInt lhs xor", opaque ^ inline_value, 7003)

# Explicit sends retain ordinary reopened-method dispatch.
check_small("explicit BigInt lhs and", opaque.&(inline_value), 7001)
check_small("explicit BigInt lhs or", opaque.|(inline_value), 7002)
check_small("explicit BigInt lhs xor", opaque.^(inline_value), 7003)

# Reverse mixed calls enter the same stable seam with a non-BigInt receiver.
# They must retain integer arithmetic rather than entering the reopen.
check_integer("inline lhs and", inline_value & opaque, "57")
check_integer("inline lhs or", inline_value | opaque, "9223372036854788351")
check_integer("inline lhs xor", inline_value ^ opaque, "9223372036854788294")

# Inferred BigInt pairs exercise the compiler's guarded static direct route.
static_a = 1_000_000_000_000_000 ## BigInt
static_b = 1_000_000_000_000_001 ## BigInt
check_small("static BigInt lhs and", static_a & static_b, 7001)
check_small("static BigInt lhs or", static_a | static_b, 7002)
check_small("static BigInt lhs xor", static_a ^ static_b, 7003)

<< "PASS BigInt bitwise reopen source seam"
