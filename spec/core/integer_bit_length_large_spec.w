# Integer#bit_length and #popcount on large BigInts (core/integer.w,
# core/numeric/int.w): exact at every boundary.  The 1,000,000-bit cases are
# the regression: the old bit-at-a-time halving needed minutes and many GB.
#
# Run:
#   bin/tungsten run --interpret spec/core/integer_bit_length_large_spec.w
#   bin/tungsten -o /tmp/integer_bit_length_large_spec spec/core/integer_bit_length_large_spec.w && /tmp/integer_bit_length_large_spec

-> check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

check("small values", (0 ## int).bit_length == 0 && (1 ## int).bit_length == 1 && (255 ## int).bit_length == 8 &&
      (256 ## int).bit_length == 9 && (-256 ## int).bit_length == 8 && (-257 ## int).bit_length == 9)
ok = true
k = 30
while k <= 200
  p = (1 ## int) << k
  ok = false if p.bit_length != k + 1
  ok = false if (p - 1).bit_length != k
  ok = false if (p + 1).bit_length != k + 1
  ok = false if (0 - p).bit_length != k
  ok = false if (0 - (p + 1)).bit_length != k + 1
  k += 1
check("powers of two and neighbours, 2^30 .. 2^200 (both signs)", ok)
x = (3 ## int) ** 5000
check("bit_length of 3^5000 matches its binary digit count", x.bit_length == x.to_s(2).size)
-> reference_popcount(value)
  count = 0
  rest = value
  while rest > 0
    word = rest % 4294967296
    while word > 0
      count += word % 2
      word = word / 2
    rest = rest / 4294967296
  count

check("popcount of 3^5000 matches a 32-bit chunked count", x.popcount == reference_popcount(x))
check("popcount of a negative BigInt counts the magnitude", (0 - x).popcount == x.popcount)
check("popcount of 2^k - 1", (((1 ## int) << 4097) - 1).popcount == 4097)
check("bit_count alias", x.bit_count == x.popcount)
big = ((1 ## int) << 999_999) + 12345
check("bit_length of a 1,000,000-bit value", big.bit_length == 1_000_000)
check("popcount of a 1,000,000-bit value", big.popcount == 7)
<< "integer_bit_length_large_spec: all checks passed"
