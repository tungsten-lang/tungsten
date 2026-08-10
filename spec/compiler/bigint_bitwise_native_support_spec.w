# Full BigInt bitwise support must link independently of the BigInt class.
# Every heap integer enters through an opaque C boundary, and this file uses
# only infix operators: there is no BigInt name, large integer literal,
# explicit operator send, or BigInt method call that could trigger autoload and
# mask a missing root-injected support module.

-> opaque_integer(text)
  ccall("w_bigint_from_dec_str", text)

-> c_compare(a, b)
  ccall("w_bigint_compare_c", a, b)

# Function parameters live outside the compiler's local-slot tables. A rhs
# named `b` must still shadow the registry unit `b`, keeping this as ordinary
# dynamic bitwise OR instead of a syntactic quantity conversion pipe.
-> opaque_infix_or(a, b)
  a | b

-> check_value(label, got, expected_text)
  expected = opaque_integer(expected_text)
  if c_compare(got, expected) != 0
    << "FAIL " + label
    exit(1)

one_a = opaque_integer("9223372036854788153")
one_b = opaque_integer("9223372036854788151")
wide_a = opaque_integer("115792089237316195423570985008687907853269984665640564039457584007913129639936")
wide_b = opaque_integer("115792089237316195423570985008687907854971396500245256356774457045071970697223")
negative_wide = opaque_integer("-115792089237316195423570985008687907853269984665640564039457584007913129639936")
inline_value = 255

check_value("one-limb and", one_a & one_b, "9223372036854788145")
check_value("one-limb or", one_a | one_b, "9223372036854788159")
check_value("opaque param infix or", opaque_infix_or(one_a, one_b), "9223372036854788159")
check_value("one-limb xor demotion", one_a ^ one_b, "14")
check_value("wide and", wide_a & wide_b, "115792089237316195423570985008687907853269984665640564039457584007913129639936")
check_value("wide or", wide_a | wide_b, "115792089237316195423570985008687907854971396500245256356774457045071970697223")
check_value("wide xor", wide_a ^ wide_b, "1701411834604692317316873037158841057287")
check_value("identity and", wide_a & wide_a, "115792089237316195423570985008687907853269984665640564039457584007913129639936")
check_value("identity or", wide_a | wide_a, "115792089237316195423570985008687907853269984665640564039457584007913129639936")
check_value("identity xor", wide_a ^ wide_a, "0")
check_value("mixed and", one_a & inline_value, "57")
check_value("mixed and reverse", inline_value & one_a, "57")
check_value("mixed or", one_a | inline_value, "9223372036854788351")
check_value("mixed or reverse", inline_value | one_a, "9223372036854788351")
check_value("mixed xor", one_a ^ inline_value, "9223372036854788294")
check_value("mixed xor reverse", inline_value ^ one_a, "9223372036854788294")
check_value("negative and", negative_wide & one_b, "0")
check_value("negative or", negative_wide | one_b, "-115792089237316195423570985008687907853269984665640564039448360635876274851785")
check_value("negative xor", negative_wide ^ one_b, "-115792089237316195423570985008687907853269984665640564039448360635876274851785")

# Polymorphic arrays store boxed WValues. Their dot-bitwise runtime loop must
# dispatch each element through the full integer path rather than truncating a
# heap BigInt's tagged pointer as an inline i48 payload.
array_left = [one_a, negative_wide]
array_right = [one_b, one_b]
array_and = array_left .& array_right
array_or = array_left .| array_right
array_xor = array_left .^ array_right
check_value("array and positive", array_and[0], "9223372036854788145")
check_value("array and negative", array_and[1], "0")
check_value("array or positive", array_or[0], "9223372036854788159")
check_value("array or negative", array_or[1], "-115792089237316195423570985008687907853269984665640564039448360635876274851785")
check_value("array xor positive", array_xor[0], "14")
check_value("array xor negative", array_xor[1], "-115792089237316195423570985008687907853269984665640564039448360635876274851785")

<< "PASS native BigInt bitwise support"
