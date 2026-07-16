# BigInt#to_i is source-only. Heap integers must autoload BigInt without an
# explicit core import and preserve the exact receiver allocation/bit pattern.

-> check_bits(name, got, expected)
  got_bits = wvalue_bits(got)
  expected_bits = wvalue_bits(expected)
  if got_bits != expected_bits
    << "FAIL [name]: got=[got_bits] expected=[expected_bits]"
    exit(1)

positive = 140_737_488_355_328
negative = -140_737_488_355_329
multilimb = 18_446_744_073_709_551_617

check_bits("positive identity", positive.to_i, positive)
check_bits("negative identity", negative.to_i, negative)
check_bits("multilimb identity", multilimb.to_i, multilimb)
check_bits("surplus arguments", multilimb.to_i(1, 2, 3), multilimb)

<< "PASS BigInt#to_i source autoload and receiver identity"
