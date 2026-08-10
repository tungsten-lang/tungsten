# BigInt comparison support is linked independently of the BigInt class. Build
# every heap integer through an opaque C boundary so this file contains no
# BigInt class reference, large integer literal, or BigInt method call capable
# of masking a missing native comparator with autoload.

-> opaque_integer(text)
  ccall("w_bigint_from_dec_str", text)

-> c_compare(a, b)
  ccall("w_bigint_compare_c", a, b)

-> check_pair(label, a, b)
  expected = c_compare(a, b)
  if (a <=> b) != expected
    << "FAIL " + label + " spaceship"
    exit(1)
  if (b <=> a) != 0 - expected
    << "FAIL " + label + " reverse spaceship"
    exit(1)
  if (a == b) != (expected == 0)
    << "FAIL " + label + " equality"
    exit(1)
  if (a != b) != (expected != 0)
    << "FAIL " + label + " inequality"
    exit(1)
  if (a < b) != (expected < 0)
    << "FAIL " + label + " less"
    exit(1)
  if (a > b) != (expected > 0)
    << "FAIL " + label + " greater"
    exit(1)
  if (a <= b) != (expected <= 0)
    << "FAIL " + label + " less-equal"
    exit(1)
  if (a >= b) != (expected >= 0)
    << "FAIL " + label + " greater-equal"
    exit(1)

-> check_numeric_value(label, got, expected)
  if c_compare(got, expected) != 0
    << "FAIL " + label
    exit(1)

-> check_collection_paths(values, expected)
  sorted = ccall("w_array_sort", values)
  stable = ccall("w_array_stable_sort", values)
  i = 0
  while i < expected.size()
    check_numeric_value("array sort " + i.to_s(), sorted[i], expected[i])
    check_numeric_value("array stable_sort " + i.to_s(), stable[i], expected[i])
    i += 1

  check_numeric_value("array min", values.min(), expected[0])
  check_numeric_value("array max", values.max(), expected[expected.size() - 1])
  extremes = values.minmax()
  check_numeric_value("array minmax min", extremes[0], expected[0])
  check_numeric_value("array minmax max", extremes[1], expected[expected.size() - 1])

  nested = [[values[0]], [values[2]], [values[1]]]
  nested_sorted = ccall("w_array_sort", nested)
  check_numeric_value("nested array sort low", nested_sorted[0][0], values[2])
  check_numeric_value("nested array sort middle", nested_sorted[1][0], values[1])
  check_numeric_value("nested array sort high", nested_sorted[2][0], values[0])

one_a = opaque_integer("9223372036854788153")
one_b = opaque_integer("9223372036854788151")
one_equal = opaque_integer("9223372036854788153")
negative_header = opaque_integer("-9223372036854788153")
negative_overlay = ccall("w_neg", one_a)
wide = opaque_integer("115792089237316195423570985008687907853269984665640564039457584007913129639936")
wide_middle_a = opaque_integer("115792089237316195423570985008687907854971396500245256356774457045071970697223")
wide_middle_b = opaque_integer("115792089237316195423570985008687907854631114133324317893311082437640202485767")
wide_top_a = opaque_integer("347376267711948586270712955026063723559809953996921692118372752023739388919817")
wide_top_b = opaque_integer("231584178474632390847141970017375815706539969331281128078915168015826259279881")
pos_i48_edge = 140737488355327
neg_i48_edge = -140737488355328
pos_big_edge = opaque_integer("140737488355328")
neg_big_edge = opaque_integer("-140737488355329")
negative_wide = ccall("w_neg", wide_top_a)

check_pair("identity", one_a, one_a)
check_pair("distinct equal buffers", one_a, one_equal)
check_pair("one limb", one_a, one_b)
check_pair("mixed sign", negative_header, one_b)
check_pair("header versus overlay sign", negative_header, negative_overlay)
check_pair("unequal positive widths", wide, one_a)
check_pair("unequal negative widths", ccall("w_neg", wide), negative_header)
check_pair("middle limb difference", wide_middle_a, wide_middle_b)
check_pair("top limb difference", wide_top_a, wide_top_b)
check_pair("inline left", pos_i48_edge, pos_big_edge)
check_pair("inline right", pos_big_edge, pos_i48_edge)
check_pair("negative inline left", neg_i48_edge, neg_big_edge)
check_pair("negative inline right", neg_big_edge, neg_i48_edge)
check_collection_paths(
  [wide_top_a, one_b, negative_header, wide_middle_a, pos_i48_edge, negative_wide],
  [negative_wide, negative_header, pos_i48_edge, one_b, wide_middle_a, wide_top_a]
)

<< "PASS native BigInt comparison support"
