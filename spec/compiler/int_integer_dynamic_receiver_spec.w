# Generic Integer algorithms and Int's auto-promoting implementation must
# survive erased receiver boundaries in both engines.

-> check(name, got, want)
  if got != want
    << "FAIL [name]: got=[got] want=[want]"
    exit(1)

-> erased_class_name(value)
  value.class_name

-> erased_digits(value, base)
  value.digits(base)

-> erased_even(value)
  value.even?

-> erased_prev(value)
  value.prev

-> erased_succ(value)
  value.succ

-> erased_gcd(value, other)
  value.gcd(other)

-> erased_lcm(value, other)
  value.lcm(other)

-> erased_isqrt(value)
  value.isqrt

-> erased_bit_length(value)
  value.bit_length

-> erased_factorial(value)
  value.factorial

-> erased_chr(value)
  value.chr

-> erased_to_s(value)
  value.to_s

small = 42
big = 1 << 100

check("inline public type", type(small), "Int")
check("inline class name", erased_class_name(small), "Int")
check("inline generic membership", small.is_a?(Integer), true)
check("inline implementation membership", small.is_a?(Int), true)
check("inline not bigint", small.is_a?(BigInt), false)

check("heap public type", type(big), "BigInt")
check("heap class name", erased_class_name(big), "BigInt")
check("heap generic membership", big.is_a?(Integer), true)
check("heap implementation membership", big.is_a?(Int), true)
check("heap concrete membership", big.is_a?(BigInt), true)

small_digits = erased_digits(42, 10)
check("inline generic digits", small_digits, [2, 4])
big_digits = erased_digits(big, 2)
check("heap generic digits size", big_digits.size, 101)
check("heap generic digits low", big_digits.first, 0)
check("heap generic digits high", big_digits.last, 1)

check("inline even", erased_even(small), true)
check("heap even", erased_even(big), true)
check("inline prev", erased_prev(42), 41)
check("inline succ", erased_succ(42), 43)

promoted_hi = erased_succ(140_737_488_355_327)
inline_min = (0 - 140_737_488_355_327) - 1
check("lower boundary is inline", type(inline_min), "Int")
promoted_lo = erased_prev(inline_min)
check("succ promotes", type(promoted_hi), "BigInt")
check("prev promotes", type(promoted_lo), "BigInt")

check("mixed gcd", erased_gcd(big + 14, 15), 15)
check("inline lcm", erased_lcm(21, 6), 42)
check("heap isqrt", erased_isqrt(big), 1 << 50)
check("heap bit length", erased_bit_length(big), 101)

factorial = erased_factorial(20)
check("factorial promotes", type(factorial), "BigInt")
check("factorial exact", erased_to_s(factorial), "2432902008176640000")
check("inline chr", erased_chr(65), "A")

<< "int_integer_dynamic_receiver_spec: all checks passed"
