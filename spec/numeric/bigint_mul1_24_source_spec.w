# Positive twenty-four-limb BigInt times positive one-limb BigInt: exact C port.

+ BigInt
  -> __spec_header_size
    $size

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

-> check_mul1(name, wide, word, expected, expected_size)
  before_wide = wide.to_s()
  before_word = word.to_s()
  got = wide * word
  check(name + ".closed_form", got, expected)
  check(name + ".header_size", got.__spec_header_size(), expected_size)
  check(name + ".commuted", word * wide, got)
  check(name + ".quotient", got / word, wide)
  check(name + ".remainder", got % word, 0)
  check(name + ".wide_unchanged", wide.to_s(), before_wide)
  check(name + ".word_unchanged", word.to_s(), before_word)

base = 1 << 64
minimum = 1 << 1472
word = (1 << 63) + 1
check_mul1("minimum", minimum, word, (1 << 1535) + (1 << 1472), 24)

ordinary = minimum + 37
ordinary_word = (1 << 63) + 11
ordinary_product = (1 << 1535) + (11 << 1472) + (37 << 63) + 407
check_mul1("ordinary", ordinary, ordinary_word, ordinary_product, 24)

maximum = (1 << 1536) - 1
maximum_word = base - 1
maximum_product = (1 << 1600) - (1 << 1536) - (1 << 64) + 1
check_mul1("maximum", maximum, maximum_word, maximum_product, 25)

# Signed shapes, identity, and neighboring widths retain their prior routes.
negative_wide = 0 - ordinary
negative_word = 0 - ordinary_word
check("control.negative_wide", negative_wide * ordinary_word,
      0 - ordinary_product)
check("control.negative_word", ordinary * negative_word,
      0 - ordinary_product)
check("control.square", ordinary * ordinary,
      ccall("w_bigint_mul_builtin_exact", ordinary, ordinary))
twenty_three = (1 << 1408) + 31
twenty_five = (1 << 1536) + 43
check("control.twenty_three", twenty_three * ordinary_word,
      ccall("w_bigint_mul_builtin_exact", twenty_three, ordinary_word))
check("control.twenty_five", twenty_five * ordinary_word,
      ccall("w_bigint_mul_builtin_exact", twenty_five, ordinary_word))

mask64 = base - 1
state = 0x9e3779b97f4a7c15
i = 0
while i < 1_000
  wide = 0
  j = 0
  while j < 24
    state = (state * 6364136223846793005 + 1442695040888963407) & mask64
    limb = state
    if j == 23
      limb = ((limb ^ (limb >> 23)) + i + 1) & mask64
      if limb == 0
        limb = 1
    wide += limb << (j * 64)
    j += 1
  state = (state * 6364136223846793005 + 1442695040888963407) & mask64
  word = state | (1 << 63) | 1
  got = wide * word
  want = ccall("w_bigint_mul_builtin_exact", wide, word)
  if got != want || got.__spec_header_size() != want.__spec_header_size()
    << "FAIL public differential at " + i.to_s()
    exit 1
  if word * wide != got || got / word != wide || got % word != 0
    << "FAIL public identity at " + i.to_s()
    exit 1
  i += 1

check("differential.count", i, 1_000)
<< "bigint_mul1_24_source_spec: all checks passed"
