# Tree-walker correctness companion for the production-shaped Array#join
# trial. Public join now exercises the same source body as compiled programs.
# The v6 benchmark's raw C helper is intentionally not linked into eval mode;
# `__tree_join_v6` substitutes StringBuffer validation at the same observable
# points, preserving type/NUL/error/call-order semantics while compiled parity
# and WIRE pin the actual no-copy helper path.

use ../../core/array
use ../../core/string_buffer

+ JoinTreeProbe
  -> new(@label, @log)
    @calls = 0

  -> calls
    @calls

  -> to_s
    @calls += 1
    text = @label + @calls.to_s
    @log.push(text)
    text

+ JoinTreeShrinkProbe
  -> new(@holder, @log)
    @calls = 0

  -> calls
    @calls

  -> to_s
    @calls += 1
    @log.push("m" + @calls.to_s)
    @holder[0].pop if @calls == 1
    "m" + @calls.to_s

+ JoinTreeBadProbe
  -> to_s
    99

+ Array
  -> __tree_join_v6
    __tree_join_impl("")

  -> __tree_join_v6(separator)
    __tree_join_impl(separator)

  -> __tree_join0
    __tree_join_impl("")

  -> __tree_join1(separator)
    __tree_join_impl(separator)

  -> __tree_join_impl(separator)
    separator_probe = StringBuffer()
    separator_probe << separator

    first_probe = StringBuffer()
    i = 0
    while i < $size
      first_probe << ccall("w_to_s", self[i])
      i += 1

    out = StringBuffer()
    i = 0
    while i < $size
      out << separator if i > 0
      out << ccall("w_to_s", self[i])
      i += 1
    ccall("w_to_s", out)

  # Independent source-dispatch mirror for the user-object probes below.
  -> __tree_join_user1(separator)
    separator_probe = StringBuffer()
    separator_probe << separator
    first_probe = StringBuffer()
    i = 0
    while i < $size
      first_probe << self[i].to_s
      i += 1
    out = StringBuffer()
    i = 0
    while i < $size
      out << separator if i > 0
      out << self[i].to_s
      i += 1
    ccall("w_to_s", out)

-> fail_check(name, detail)
  << "FAIL [name]: [detail]"
  exit(1)

-> check(name, got, expected)
  if got != expected
    fail_check(name, "got=[got] expected=[expected]")

-> check_result(name, got, expected)
  check("[name].class", got.class_name, "String")
  check("[name].bytes", got, expected)
  check("[name].size", got.size, expected.size)

-> string_storage_mode(value)
  (wvalue_bits(value) >> 1) & 7

-> check_array(name, got, expected)
  check("[name].size", got.size, expected.size)
  i = 0
  while i < expected.size
    check("[name].[i]", got[i], expected[i])
    i += 1

-> make_nul_text(a, b)
  bytes = u8[3]
  bytes[0] = a
  bytes[1] = 0
  bytes[2] = b
  ccall("w_string_from_byte_array", bytes)

-> build_typed_cases
  cases = []

  wvalues = w64[3]
  wvalues[0] = "first"
  wvalues[1] = nil
  wvalues[2] = "last"
  cases.push(wvalues)

  bools = bool[3]
  bools.push(true)
  bools.push(false)
  bools.push(true)
  cases.push(bools)

  bits = u1[3]
  bits[0] = 1
  bits[1] = 0
  bits[2] = 1
  cases.push(bits)

  u4s = u4[3]
  u4s[0] = 1
  u4s[1] = 9
  u4s[2] = 15
  cases.push(u4s)

  i4s = i4[3]
  i4s[0] = -8
  i4s[1] = -1
  i4s[2] = 7
  cases.push(i4s)

  u8s = u8[4]
  u8s[0] = 3
  u8s[1] = 17
  u8s[2] = 129
  u8s[3] = 251
  cases.push(u8s)

  i8s = i8[3]
  i8s[0] = -128
  i8s[1] = -7
  i8s[2] = 127
  cases.push(i8s)

  u16s = u16[3]
  u16s[0] = 17
  u16s[1] = 32768
  u16s[2] = 65535
  cases.push(u16s)

  i16s = i16[3]
  i16s[0] = -32768
  i16s[1] = -11
  i16s[2] = 32767
  cases.push(i16s)

  u32s = u32[3]
  u32s[0] = 19
  u32s[1] = 1_000_000
  u32s[2] = 4_000_000_000
  cases.push(u32s)

  i32s = i32[3]
  i32s[0] = -2_000_000_000
  i32s[1] = -13
  i32s[2] = 2_000_000_000
  cases.push(i32s)

  u64s = u64[3]
  u64s[0] = 23
  u64s[1] = 1_000_000_000
  u64s[2] = 2_000_000_000
  cases.push(u64s)

  i64s = i64[3]
  i64s[0] = -2_000_000_000
  i64s[1] = -17
  i64s[2] = 2_000_000_000
  cases.push(i64s)

  f32s = f32[3]
  f32s[0] = ~1.5
  f32s[1] = ~-2.25
  f32s[2] = ~3.75
  cases.push(f32s)

  f64s = f64[3]
  f64s[0] = ~-1.25
  f64s[1] = ~2.5
  f64s[2] = ~-4.75
  cases.push(f64s)

  bf16s = bf16[3]
  bf16s[0] = ~1.5
  bf16s[1] = ~-2.0
  bf16s[2] = ~4.0
  cases.push(bf16s)

  cases

fatal_case = env("ARRAY_JOIN_INTERPRETER_FATAL")
if fatal_case == "integer-empty"
  [].join(123)
  exit(0)
elsif fatal_case == "explicit-nil"
  ["a"].join(nil)
  exit(0)
elsif fatal_case == "bad-to-s"
  [JoinTreeBadProbe.new()].join("|")
  exit(0)

check_result("empty", ([].join), "")
check_result("noarg nonempty", ["a", "b"].join, "ab")
check_result("singleton", ["solo"].join("ignored"), "solo")
check_result("strings", ["a", "bb", "ccc"].join("|"), "a|bb|ccc")
check_result("symbols", [:a, :bb, :ccc].join(:x), "axbbxccc")
check_result("v6 mirror strings", ["a", "bb", "ccc"].__tree_join_v6("|"), "a|bb|ccc")
check_result("v6 mirror symbols", [:a, :bb, :ccc].__tree_join_v6(:x), "axbbxccc")
check_result("extra arguments", ["a", "b"].join("|", "ignored", 99), "a|b")
check_result("mixed", [nil, true, false, 42, -7, ~2.5, :sym, "txt"].join("|"),
             "|true|false|42|-7|2.5|sym|txt")

nul_item = make_nul_text(65, 66)
nul_separator = make_nul_text(88, 89)
check("nul item storage", nul_item.size, 3)
check("nul separator storage", nul_separator.size, 3)
check_result("nul item", [nul_item, "C"].join("|"), "A|C")
check_result("nul separator", ["a", "b", "c"].join(nul_separator), "aXbXc")
check_result("v6 mirror nul item", [nul_item, "C"].__tree_join_v6("|"), "A|C")
check_result("v6 mirror nul separator", ["a", "b", "c"].__tree_join_v6(nul_separator), "aXbXc")

typed_cases = build_typed_cases()
typed_expected = ["first||last", "true|false|true", "true|false|true",
                  "1|9|15", "-8|-1|7", "3|17|129|251",
                  "-128|-7|127", "17|32768|65535", "-32768|-11|32767",
                  "19|1000000|4000000000", "2294967296|4294967283|2000000000",
                  "23|1000000000|2000000000", "-2000000000|-17|2000000000",
                  "1.5|-2.25|3.75", "-1.25|2.5|-4.75", "1.5|-2|4"]
i = 0
while i < typed_cases.size
  check_result("typed [i]", typed_cases[i].join("|"), typed_expected[i])
  check_result("v6 mirror typed [i]", typed_cases[i].__tree_join_v6("|"), typed_expected[i])
  i += 1

log = []
left = JoinTreeProbe.new("a", log)
right = JoinTreeProbe.new("b", log)
check_result("probe output", [left, right].join("|"), "a2|b2")
check_array("probe order", log, ["a1", "b1", "a2", "b2"])
check("probe left calls", left.calls, 2)
check("probe right calls", right.calls, 2)

v6_log = []
v6_left = JoinTreeProbe.new("a", v6_log)
v6_right = JoinTreeProbe.new("b", v6_log)
check_result("v6 mirror probe output", [v6_left, v6_right].__tree_join_v6("|"), "a2|b2")
check_array("v6 mirror probe order", v6_log, ["a1", "b1", "a2", "b2"])
check("v6 mirror probe left calls", v6_left.calls, 2)
check("v6 mirror probe right calls", v6_right.calls, 2)

holder = [nil]
shrink_log = []
mutator = JoinTreeShrinkProbe.new(holder, shrink_log)
shrinking = [mutator, "b", "c"]
holder[0] = shrinking
check_result("shrink output", shrinking.join("|"), "m2|b")
check_array("shrink order", shrink_log, ["m1", "m2"])
check("shrink calls", mutator.calls, 2)
check("shrink final size", shrinking.size, 2)

v6_holder = [nil]
v6_shrink_log = []
v6_mutator = JoinTreeShrinkProbe.new(v6_holder, v6_shrink_log)
v6_shrinking = [v6_mutator, "b", "c"]
v6_holder[0] = v6_shrinking
check_result("v6 mirror shrink output", v6_shrinking.__tree_join_v6("|"), "m2|b")
check_array("v6 mirror shrink order", v6_shrink_log, ["m1", "m2"])
check("v6 mirror shrink calls", v6_mutator.calls, 2)
check("v6 mirror shrink final size", v6_shrinking.size, 2)

check_result("independent mirror", ["left", "right"].__tree_join1("::"), "left::right")

# StringBuffer#to_s can return an already-interned mode-6 slab value. Once the
# slab freezes, Array#join must repair that into a fresh mode-7 heap String on
# every call, matching the former C `w_string_take` representation contract.
frozen_values = ["abc", "def"]
prefreeze = frozen_values.join
check("prefreeze bytes", prefreeze, "abcdef")
check("prefreeze mode", string_storage_mode(prefreeze), 6)
ccall("w_slab_freeze_safe")
frozen_one = frozen_values.join
frozen_two = frozen_values.join
check("frozen first bytes", frozen_one, "abcdef")
check("frozen second bytes", frozen_two, "abcdef")
check("frozen first mode", string_storage_mode(frozen_one), 7)
check("frozen second mode", string_storage_mode(frozen_two), 7)
if wvalue_bits(frozen_one) == wvalue_bits(frozen_two)
  fail_check("frozen freshness", "two joins returned the same heap String")

<< "interpreter correctness: ok (public plus v6 semantic mirror; overloads, bytes/NUL, every typed decoder branch, live-size shrink, exact two-pass order, and frozen-slab freshness)"
