# Positive one-limb BigInt minus positive one-limb BigInt.  The native source
# arithmetic is checked against the retained C boundary at every result class.

+ BigInt
  -> __spec_header_size
    $size

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

-> check_sub1(name, a, b, expected_size)
  got = a - b
  want = ccall("w_bigint_sub", a, b)
  check(name + ".value", got, want)
  check(name + ".header_size", got.__spec_header_size(), expected_size)
  check(name + ".roundtrip", got + b, a)

i48_max = (1 << 47) - 1
high = 1 << 63

# Positive and negative boxed one-limb results.
check_sub1("positive_boxed", high + 91, 17, 1)
check_sub1("negative_boxed", high + 17, high * 2 - 91, -1)

# Exact zero and both i48 result signs demote rather than allocating.
check("zero.value", (high + 17) - (high + 17), 0)
check("positive_i48.value", (high + 17) - high, 17)
check("negative_i48.value", high - (high + 17), 0 - 17)
check("positive_i48.edge", (high + i48_max) - high, i48_max)
check("negative_i48.edge", high - (high + i48_max), 0 - i48_max)

# First values outside i48 remain one-limb heap BigInts with exact signs.
check_sub1("positive_heap_edge", high + i48_max + 1, high, 1)
check_sub1("negative_heap_edge", high, high + i48_max + 1, -1)

# Neighboring widths and sign shapes stay on their prior routes.
two = (1 << 127) + 29
word = high + 11
check("control.two", two - word, ccall("w_bigint_sub", two, word))
check("control.negative_rhs", (high + 31) - (0 - word),
      ccall("w_bigint_sub", high + 31, 0 - word))
check("control.negative_lhs", (0 - (high + 31)) - word,
      ccall("w_bigint_sub", 0 - (high + 31), word))

<< "bigint_sub1_1_source_spec: all checks passed"
