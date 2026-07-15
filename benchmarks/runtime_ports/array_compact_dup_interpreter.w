# Tree-walker parity for the benchmark-only Array#compact / Array#dup source
# bodies. This deliberately links no benchmark C: v1 is the literal semantic
# oracle and v2 tests the hoisted-size form. The current tree walker does not
# expose retained Array IC names such as compact/dup; compiled parity pins the
# public handlers separately in array_compact_dup_ab.w.

use array_compact_dup_candidates

+ CompactDupTreeProbe
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
      fail_check("[name].[i]",
                 "got-bits=[got_bits] expected-bits=[expected_bits]")
    i += 1

-> check_fresh(name, receiver, values)
  all = [receiver]
  i = 0
  while i < values.size
    all.push(values[i])
    i += 1
  i = 0
  while i < all.size
    j = i + 1
    while j < all.size
      if wvalue_bits(all[i]) == wvalue_bits(all[j])
        fail_check(name, "paths [i] and [j] alias")
      j += 1
    i += 1

-> check_case(name, values)
  compact_v1 = values.__w_compact_v1
  compact_v2 = values.__w_compact_v2
  check_result("[name].compact.v2", compact_v2, compact_v1)
  check_fresh("[name].compact.fresh", values, [compact_v1, compact_v2])

  dup_v1 = values.__w_dup_v1
  dup_v2 = values.__w_dup_v2
  check_result("[name].dup.v2", dup_v2, dup_v1)
  check_fresh("[name].dup.fresh", values, [dup_v1, dup_v2])

  # Both methods are shallow and leave the original live window unchanged.
  check_result("[name].receiver", values, dup_v1)

-> add_typed_cases(cases)
  bools = bool[3]
  bools[0] = true
  bools[1] = false
  bools[2] = true
  cases.push(["bool", bools])

  u1s = u1[3]
  u1s[0] = 1
  u1s[1] = 0
  u1s[2] = 1
  cases.push(["u1", u1s])

  u4s = u4[3]
  u4s[0] = 0
  u4s[1] = 9
  u4s[2] = 15
  cases.push(["u4", u4s])

  i4s = i4[3]
  i4s[0] = -8
  i4s[1] = -1
  i4s[2] = 7
  cases.push(["i4", i4s])

  u8s = u8[4]
  u8s[0] = 3
  u8s[1] = 17
  u8s[2] = 129
  u8s[3] = 251
  cases.push(["u8", u8s])

  i8s = i8[3]
  i8s[0] = -128
  i8s[1] = -7
  i8s[2] = 127
  cases.push(["i8", i8s])

  u16s = u16[3]
  u16s[0] = 17
  u16s[1] = 32768
  u16s[2] = 65535
  cases.push(["u16", u16s])

  i16s = i16[3]
  i16s[0] = -32768
  i16s[1] = -11
  i16s[2] = 32767
  cases.push(["i16", i16s])

  u32s = u32[3]
  u32s[0] = 19
  u32s[1] = 1_000_000
  u32s[2] = 4_000_000_000
  cases.push(["u32", u32s])

  i32s = i32[3]
  i32s[0] = -2_000_000_000
  i32s[1] = -13
  i32s[2] = 2_000_000_000
  cases.push(["i32", i32s])

  u64s = u64[3]
  u64s[0] = 23
  u64s[1] = 1_000_000_000
  u64s[2] = 2_000_000_000
  cases.push(["u64", u64s])

  i64s = i64[3]
  i64s[0] = -2_000_000_000
  i64s[1] = -17
  i64s[2] = 2_000_000_000
  cases.push(["i64", i64s])

  f32s = f32[3]
  f32s[0] = ~-2.25
  f32s[1] = ~0.0
  f32s[2] = ~3.75
  cases.push(["f32", f32s])

  f64s = f64[3]
  f64s[0] = ~-1.25
  f64s[1] = ~0.0
  f64s[2] = ~4.75
  cases.push(["f64", f64s])

  bf16s = bf16[3]
  bf16s[0] = ~-2.0
  bf16s[1] = ~0.0
  bf16s[2] = ~4.0
  cases.push(["bf16", bf16s])

  wvalues = w64[5]
  wvalues[0] = nil
  wvalues[1] = false
  wvalues[2] = "text"
  wvalues[3] = nil
  wvalues[4] = 7
  cases.push(["w64-nil", wvalues])

cases = []
cases.push(["empty", []])
cases.push(["singleton-nil", [nil]])
cases.push(["mixed", [nil, false, 0, "text", nil, true, ~0.0]])

same = CompactDupTreeProbe.new("same")
other = CompactDupTreeProbe.new("same")
cases.push(["object-identity", [same, nil, same, other]])

# Native `shift`/`slice_view` handlers are intentionally absent from the tree
# walker. The compiled gate below covers nonzero starts and borrowed views for
# both polymorphic and typed arrays; eval mode covers every decoded family.
add_typed_cases(cases)

i = 0
while i < cases.size
  check_case(cases[i][0], cases[i][1])
  i += 1

extra = [nil, "kept", false, nil]
check_result("extra.compact.v2", extra.__w_compact_v2("ignored", 99),
             extra.__w_compact_v1("ignored", 99))
check_result("extra.dup.v2", extra.__w_dup_v2("ignored", 99),
             extra.__w_dup_v1("ignored", 99))

block_log = []
block_compact = extra.__w_compact_v2 -> (item)
  block_log.push(item)
block_dup = extra.__w_dup_v2 -> (item)
  block_log.push(item)
check_result("block.compact", block_compact, extra.__w_compact_v1)
check_result("block.dup", block_dup, extra.__w_dup_v1)
check_value("tree-walker ignored block invocation count", block_log.size, 0)

<< "interpreter correctness: ok ([cases.size] polymorphic/typed families, exact compact nil filtering and dup decoding, fresh shallow results, unchanged receivers, and ignored extras; compiled gate covers shifted/view storage and result-iteration blocks)"
