# Tree-walker parity for direct BigInt signed-length and limb0 view fields.
# Natural arithmetic always normalizes zero back to Integer, so the synthetic
# size-zero/no-storage cases remain a compiled C-fixture gate.

-> check(name, got, expected)
  if got != expected
    << "FAIL interpreter [name]: got=[got] expected=[expected]"
    exit(1)

-> invoke_block(value, method, hits)
  if method == "zero"
    return value.zero? -> (ignored)
      hits[0] += 1
  elsif method == "even"
    return value.even? -> (ignored)
      hits[0] += 1
  elsif method == "odd"
    return value.odd? -> (ignored)
      hits[0] += 1
  elsif method == "negative"
    return value.negative? -> (ignored)
      hits[0] += 1
  elsif method == "positive"
    return value.positive? -> (ignored)
      hits[0] += 1

even = 281474976710656
odd = 281474976710657
negative_even = 0 - even
negative_odd = 0 - odd
multi_even = 18446744073709551616
multi_odd = multi_even + 1

values = [even, odd, negative_even, negative_odd, multi_even, multi_odd]
expected_even = [true, false, true, false, true, false]
expected_negative = [false, false, true, true, false, false]
i = 0
while i < values.size()
  value = values[i]
  check("[i].class", value.class_name, "BigInt")
  check("[i].zero", value.zero?, false)
  check("[i].even", value.even?, expected_even[i])
  check("[i].odd", value.odd?, !expected_even[i])
  check("[i].negative", value.negative?, expected_negative[i])
  check("[i].positive", value.positive?, !expected_negative[i])
  check("[i].extra.zero", value.zero?(1, 2, 3, 4), false)
  check("[i].extra.even", value.even?(1, 2, 3, 4), expected_even[i])
  check("[i].extra.odd", value.odd?(1, 2, 3, 4), !expected_even[i])
  check("[i].extra.negative", value.negative?(1, 2, 3, 4), expected_negative[i])
  check("[i].extra.positive", value.positive?(1, 2, 3, 4), !expected_negative[i])
  i += 1

# Tree-walker source dispatch historically binds but does not implicitly
# iterate an attached block. Pin that compatibility surface independently of
# the compiled path, where the runner requires the native and source binaries
# to produce the same undefined-Bool#each error.
methods = ["zero", "even", "odd", "negative", "positive"]
expected = [false, false, true, false, true]
hits = [0]
i = 0
while i < methods.size()
  check("block result [methods[i]]", invoke_block(odd, methods[i], hits), expected[i])
  check("block ignored [methods[i]]", hits[0], 0)
  i += 1

<< "interpreter: ok (signed length, u64 limb0 parity, one/multi-limb values, extras, autoload, and ignored blocks)"
