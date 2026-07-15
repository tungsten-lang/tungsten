# Tree-walker parity gate for the isolated Array#uniq candidates. This file
# deliberately has no benchmark-only C include: v1 is the direct w_eq scan and
# serves as the semantic oracle for v2 while exercising the interpreter's
# guarded Hash bridges and raw byte-load intrinsic.

use array_uniq_candidates

+ UniqTreeProbe
  -> new(@label)

-> fail_check(name, detail)
  << "FAIL [name]: [detail]"
  exit(1)

-> check_value(name, got, expected)
  if got != expected
    fail_check(name, "got=[got] expected=[expected]")

-> check_result(name, got, expected)
  check_value("[name].size", got.size, expected.size)
  i = 0
  while i < expected.size
    got_bits = wvalue_bits(got[i])
    expected_bits = wvalue_bits(expected[i])
    if got_bits != expected_bits
      fail_check("[name].[i]", "got-bits=[got_bits] expected-bits=[expected_bits]")
    i += 1

-> check_case(name, values)
  expected = values.__w_uniq_v1
  got = values.__w_uniq_v2
  check_result(name, got, expected)
  if wvalue_bits(got) == wvalue_bits(values)
    fail_check("[name].fresh", "candidate returned its receiver")
  if wvalue_bits(got) == wvalue_bits(expected)
    fail_check("[name].independent", "v1 and v2 aliased the same result Array")

-> repeated_text(count)
  tokens = ["alpha-000", "beta--111", "gamma-222", "delta-333"]
  values = []
  i = 0
  while i < count
    values.push(tokens[i & 3])
    i += 1
  values

-> make_nul_text(a, b)
  bytes = u8[3]
  bytes[0] = a
  bytes[1] = 0
  bytes[2] = b
  ccall("w_string_from_byte_array", bytes)

# The bridge rejects malformed source calls before reaching the native ccall
# boundary. Keep each failure isolated so the runner can pin its exact error.
fatal_case = env("ARRAY_UNIQ_INTERPRETER_FATAL")
if fatal_case == "has-key-arity"
  ccall("w_hash_has_key", {})
  exit(0)
elsif fatal_case == "has-key-receiver"
  ccall("w_hash_has_key", [], "x")
  exit(0)
elsif fatal_case == "set-arity"
  ccall("w_hash_set", {}, "x")
  exit(0)
elsif fatal_case == "set-receiver"
  ccall("w_hash_set", [], "x", true)
  exit(0)

heap_a = "heap-alpha-value" * 8
heap_b = "heap-alpha-value" * 8
heap_c = "heap-gamma-value" * 8
rope_a = ("abcdefgh" * 8) + ("ijklmnop" * 8)
rope_b = ("abcdefgh" * 8) + ("ijklmnop" * 8)
rope_c = ("abcdefgh" * 8) + ("qrstuvwx" * 8)
big = 123456789012345678901234567890
probe = UniqTreeProbe.new("probe")

check_value("representation.heap.tag", (wvalue_bits(heap_a) >> 48) & 0xFFFF, 0xFFF9)
check_value("representation.heap.mode", (wvalue_bits(heap_a) >> 1) & 7, 7)
check_value("representation.rope.tag", (wvalue_bits(rope_a) >> 48) & 0xFFFF, 0)
check_value("representation.rope.subtag", wvalue_bits(rope_a) & 0xF, 0)
check_value("classify.inline", array_uniq_text_hash_safe?("a"), true)
check_value("classify.slab", array_uniq_text_hash_safe?("slab-value"), true)
check_value("classify.heap", array_uniq_text_hash_safe?(heap_a), true)
check_value("classify.rope", array_uniq_text_hash_safe?(rope_a), true)
check_value("classify.symbol", array_uniq_text_hash_safe?(:same), true)
check_value("classify.nil", array_uniq_text_hash_safe?(nil), false)
check_value("classify.bool", array_uniq_text_hash_safe?(true), false)
check_value("classify.int", array_uniq_text_hash_safe?(1), false)
check_value("classify.float", array_uniq_text_hash_safe?(~1.0), false)
check_value("classify.bigint", array_uniq_text_hash_safe?(big), false)
check_value("classify.array", array_uniq_text_hash_safe?([]), false)
check_value("classify.hash", array_uniq_text_hash_safe?({}), false)
check_value("classify.object", array_uniq_text_hash_safe?(probe), false)

check_case("empty", [])
check_case("singleton", ["only"])
check_case("order", ["b", "a", "b", "c", "a"])
check_case("threshold-quadratic", repeated_text(ARRAY_UNIQ_SMALL_THRESHOLD))
check_case("threshold-hash", repeated_text(ARRAY_UNIQ_SMALL_THRESHOLD + 1))

heap_values = []
rope_values = []
symbol_values = []
nontext_first = [0]
i = 0
while i < 24
  heap_values.push((i & 3) == 3 ? heap_c : ((i & 1) == 0 ? heap_a : heap_b))
  rope_values.push((i & 3) == 3 ? rope_c : ((i & 1) == 0 ? rope_a : rope_b))
  symbol_values.push((i & 3) == 3 ? "same" : :same)
  if i > 0
    nontext_first.push((i & 1) == 0 ? "alpha" : "beta")
  i += 1
check_case("heap-hash", heap_values)
check_case("rope-hash", rope_values)
check_case("symbol-hash", symbol_values)
check_case("nontext-first", nontext_first)

nul_a = make_nul_text(65, 66)
nul_b = make_nul_text(65, 66)
nul_c = make_nul_text(65, 67)
nul_values = []
i = 0
while i < 24
  nul_values.push((i & 3) == 3 ? nul_c : nul_a)
  i += 1
check_case("embedded-nul-hash", nul_values)

# Pin fallback families for which ordinary Hash is not a w_eq substitute.
check_case("numeric-order-a", [1, ~1.0, 1.00, 2.00, ~2.0, 2])
check_case("numeric-order-b", [1.00, 1, ~1.0, 2, 2.00, ~2.0])
check_case("bigint-value", [big, big, 1])

bytes_a = u8[3]
bytes_b = u8[3]
i = 0
while i < 3
  bytes_a[i] = i + 10
  bytes_b[i] = i + 10
  i += 1
check_case("bytearray-structural", [bytes_a, bytes_b, bytes_a])

same_object = UniqTreeProbe.new("same")
other_object = UniqTreeProbe.new("same")
check_case("object-identity", [same_object, same_object, other_object, other_object])
nested_same = [1]
nested_other = [1]
check_case("nested-array-identity", [nested_same, nested_same, nested_other, nested_other])
hash_same = {value: 1}
hash_other = {value: 1}
check_case("hash-identity", [hash_same, hash_same, hash_other, hash_other])

u16s = u16[6]
u16s[0] = 17
u16s[1] = 65535
u16s[2] = 17
u16s[3] = 7
u16s[4] = 65535
u16s[5] = 0
check_case("typed-u16", u16s)

wvalues = w64[6]
wvalues[0] = "first"
wvalues[1] = nil
wvalues[2] = "first"
wvalues[3] = false
wvalues[4] = nil
wvalues[5] = false
check_case("typed-w64", wvalues)

extra_values = ["a", "b", "a"]
check_result("extra.v2", extra_values.__w_uniq_v2("ignored", 99),
             extra_values.__w_uniq_v1("ignored", 99))

<< "interpreter correctness: ok (pure tag/rope classifier, guarded Hash bridges, threshold/text representation branches, exact fallback identity/value semantics, typed inputs, and extra arguments; compiled gate covers shifted storage)"
