# Strict benchmark-only Array#join tuning harness. The retained production v1
# and isolated candidates are uniquely named and compare against the original
# C implementation in array_join_ref.c:
#
#   v1: exact two-pass behavior with a default-growth final buffer
#   v2: same behavior with exact final-capacity preallocation
#   v3: v1 output path, but reset first_probe after each validation so its
#       capacity is bounded by the largest individual item, not total payload
#   v4: v1 output path, but validate the separator in first_probe itself so
#       the exact eager ordering needs only two recycled buffers
#   v5: validate both separator and first pass in the final buffer, reset it
#       once, then reuse its capacity for the second-pass output
#   v6: validate separator/first-pass text through a benchmark-only raw
#       strlen(as_str(...)) helper, then allocate only the pass-2 output buffer
#
# All six candidates use StringBuffer only as a storage primitive. Direct
# w_to_s/w_strbuf_append calls are intentional: `StringBuffer << value`
# coerces non-text values and would silently change C's separator and custom
# to_s-return errors. The ## recycle buffers keep long timing runs bounded and
# are exception-safe through the compiler cleanup stack.

use ../../core/array
use ../../core/string_buffer

BATCH_SIZE = 256
DEFAULT_ITERS = 100_000
WARMUP_ITERS = 1_000

+ JoinProbe
  -> new(@label, @log, @bad_call)
    @calls = 0

  -> calls
    @calls

  -> to_s
    @calls = @calls + 1
    entry = @label + @calls.to_s
    @log.push(entry)
    if @bad_call == @calls
      return 99
    entry

+ JoinShrinkProbe
  -> new(@holder, @log)
    @calls = 0

  -> calls
    @calls

  -> to_s
    @calls = @calls + 1
    @log.push("m" + @calls.to_s)
    # Shrink only on the first sizing-pass call.  This is memory-safe for C:
    # pass 2 never exceeds the allocation computed from pass 1.
    if @calls == 1
      @holder[0].pop
    "m" + @calls.to_s

+ Array
  # Register arity-1 before arity-0.  Exact-arity lookup handles ordinary
  # calls; 2+ arguments fall back to the first same-name entry, so this order
  # makes extras truncate to the separator overload just like the C IC.
  # A default parameter is not equivalent because explicit nil would be
  # replaced by the default instead of rejected.
  -> __c_join(separator)
    ccall("w_ref_array_join1", self, separator)

  -> __c_join
    ccall("w_ref_array_join0", self)

  -> __w_join_v1(separator)
    __w_join_v1_impl(separator)

  -> __w_join_v1
    __w_join_v1_impl("")

  -> __w_join_v1_impl(separator)
    separator_probe = StringBuffer() ## recycle
    ccall("w_strbuf_append", separator_probe, separator)

    # C's sizing pass calls to_s on every element and immediately validates
    # its raw return as text.  Copying into a throwaway buffer reproduces its
    # strlen/NUL boundary without adding a new runtime helper.
    first_probe = StringBuffer() ## recycle
    i = 0
    # Do not cache size: C rereads arr->size at every loop condition, and a
    # user to_s method can mutate the receiver between iterations.
    while i < $size
      text = ccall("w_to_s", self[i])
      ccall("w_strbuf_append", first_probe, text)
      i += 1

    out = StringBuffer() ## recycle
    i = 0
    while i < $size
      if i > 0
        ccall("w_strbuf_append", out, separator)
      text = ccall("w_to_s", self[i])
      ccall("w_strbuf_append", out, text)
      i += 1

    result = ccall("w_strbuf_to_s", out)
    # w_string_take (the C finalizer) returns a fresh mode-7 string for a
    # 6..61-byte result after slab freeze, even if those bytes are interned.
    # w_strbuf_to_s/w_string returns that existing mode-6 value instead.  A
    # zero-length heap append mints the required fresh heap representation.
    if ((wvalue_bits(result) >> 1) & 7) == 6
      slab_frozen = ccall_nobox("w_slab_is_frozen") ## i64
      if slab_frozen == 1
        fresh = ""
        return fresh << result
    result

  -> __w_join_v2(separator)
    __w_join_v2_impl(separator)

  -> __w_join_v2
    __w_join_v2_impl("")

  -> __w_join_v2_impl(separator)
    separator_probe = StringBuffer() ## recycle
    ccall("w_strbuf_append", separator_probe, separator)

    first_probe = StringBuffer() ## recycle
    i = 0
    while i < $size
      text = ccall("w_to_s", self[i])
      ccall("w_strbuf_append", first_probe, text)
      i += 1

    first_count = i
    capacity = first_probe.size
    if first_count > 1
      capacity += separator_probe.size * (first_count - 1)
    out = StringBuffer(capacity + 1) ## recycle
    i = 0
    while i < $size
      if i > 0
        ccall("w_strbuf_append", out, separator)
      text = ccall("w_to_s", self[i])
      ccall("w_strbuf_append", out, text)
      i += 1

    result = ccall("w_strbuf_to_s", out)
    if ((wvalue_bits(result) >> 1) & 7) == 6
      slab_frozen = ccall_nobox("w_slab_is_frozen") ## i64
      if slab_frozen == 1
        fresh = ""
        return fresh << result
    result

  -> __w_join_v3(separator)
    __w_join_v3_impl(separator)

  -> __w_join_v3
    __w_join_v3_impl("")

  -> __w_join_v3_impl(separator)
    separator_probe = StringBuffer() ## recycle
    ccall("w_strbuf_append", separator_probe, separator)

    # `first_probe$length = 0` would be the direct storage spelling, but
    # explicit-receiver view fields are read-only today: the parser accepts a
    # ViewFieldVar as an expression, not as an assignment target. Use the
    # benchmark-only reset helper until this candidate earns production work.
    first_probe = StringBuffer() ## recycle
    i = 0
    while i < $size
      text = ccall("w_to_s", self[i])
      ccall("w_strbuf_append", first_probe, text)
      ccall("w_bench_strbuf_reset", first_probe)
      i += 1

    out = StringBuffer() ## recycle
    i = 0
    while i < $size
      if i > 0
        ccall("w_strbuf_append", out, separator)
      text = ccall("w_to_s", self[i])
      ccall("w_strbuf_append", out, text)
      i += 1

    result = ccall("w_strbuf_to_s", out)
    if ((wvalue_bits(result) >> 1) & 7) == 6
      slab_frozen = ccall_nobox("w_slab_is_frozen") ## i64
      if slab_frozen == 1
        fresh = ""
        return fresh << result
    result

  -> __w_join_v4(separator)
    __w_join_v4_impl(separator)

  -> __w_join_v4
    __w_join_v4_impl("")

  -> __w_join_v4_impl(separator)
    # The separator only needs to cross as_str/StringBuffer validation before
    # any element to_s call. Its bytes do not need separate storage: seed the
    # existing throwaway first-pass buffer, then continue appending validated
    # item texts. This keeps the exact eager failure order with one less
    # recycled allocation and cleanup-stack entry than v1.
    first_probe = StringBuffer() ## recycle
    ccall("w_strbuf_append", first_probe, separator)

    i = 0
    while i < $size
      text = ccall("w_to_s", self[i])
      ccall("w_strbuf_append", first_probe, text)
      i += 1

    out = StringBuffer() ## recycle
    i = 0
    while i < $size
      if i > 0
        ccall("w_strbuf_append", out, separator)
      text = ccall("w_to_s", self[i])
      ccall("w_strbuf_append", out, text)
      i += 1

    result = ccall("w_strbuf_to_s", out)
    if ((wvalue_bits(result) >> 1) & 7) == 6
      slab_frozen = ccall_nobox("w_slab_is_frozen") ## i64
      if slab_frozen == 1
        fresh = ""
        return fresh << result
    result

  -> __w_join_v5(separator)
    __w_join_v5_impl(separator)

  -> __w_join_v5
    __w_join_v5_impl("")

  -> __w_join_v5_impl(separator)
    # One recursion-safe pooled buffer can serve both phases. Seed it with the
    # separator to preserve eager validation, append all first-pass to_s
    # results, reset only its logical length, then reuse the retained capacity
    # for the second-pass output. The reset helper is benchmark-only because
    # explicit-receiver view-field stores are not expressible yet.
    out = StringBuffer() ## recycle
    ccall("w_strbuf_append", out, separator)

    i = 0
    while i < $size
      text = ccall("w_to_s", self[i])
      ccall("w_strbuf_append", out, text)
      i += 1

    ccall("w_bench_strbuf_reset", out)
    i = 0
    while i < $size
      if i > 0
        ccall("w_strbuf_append", out, separator)
      text = ccall("w_to_s", self[i])
      ccall("w_strbuf_append", out, text)
      i += 1

    result = ccall("w_strbuf_to_s", out)
    if ((wvalue_bits(result) >> 1) & 7) == 6
      slab_frozen = ccall_nobox("w_slab_is_frozen") ## i64
      if slab_frozen == 1
        fresh = ""
        return fresh << result
    result

  -> __w_join_v6(separator)
    __w_join_v6_impl(separator)

  -> __w_join_v6
    __w_join_v6_impl("")

  -> __w_join_v6_impl(separator)
    # Preserve C's eager separator validation and exact strlen boundary
    # without allocating or copying into a first-pass StringBuffer. The raw
    # helper is benchmark-only; a production form would need an equally narrow
    # storage primitive and would be considered only if this candidate wins.
    separator_length = ccall_nobox("w_bench_as_str_length", separator) ## i64

    i = 0
    while i < $size
      text = ccall("w_to_s", self[i])
      text_length = ccall_nobox("w_bench_as_str_length", text) ## i64
      i += 1

    # Do not use the measured lengths for preallocation: v2 already showed
    # that exact sizing regresses cheap/medium joins. Allocate one ordinary
    # recycled output buffer only after validation has completed.
    out = StringBuffer() ## recycle
    i = 0
    while i < $size
      if i > 0
        ccall("w_strbuf_append", out, separator)
      text = ccall("w_to_s", self[i])
      ccall("w_strbuf_append", out, text)
      i += 1

    result = ccall("w_strbuf_to_s", out)
    if ((wvalue_bits(result) >> 1) & 7) == 6
      slab_frozen = ccall_nobox("w_slab_is_frozen") ## i64
      if slab_frozen == 1
        fresh = ""
        return fresh << result
    result

  # The benchmark-only v6 helper is not linked into the tree walker. This
  # valid-text mirror uses StringBuffer validation at the same observable
  # points, exercising two passes, NUL truncation, typed loads, and custom-to_s
  # call order. Actual helper calls, fatal errors, and frozen representation
  # are checked on v6 in compiled mode below.
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

    # StringBuffer#size/to_s are bodyless primitive declarations and the
    # current tree walker gives those empty source bodies precedence over its
    # native fallback.  Use default growth and the allowlisted universal
    # w_to_s boundary in this interpreter-only mirror.
    out = StringBuffer()
    i = 0
    while i < $size
      out << separator if i > 0
      out << ccall("w_to_s", self[i])
      i += 1
    ccall("w_to_s", out)

-> fail_check(name, detail)
  << "FAIL [name]: [detail]"
  exit(1)

-> check_value(name, got, expected)
  if got != expected
    fail_check(name, "got=[got] expected=[expected]")

-> check_array(name, got, expected)
  check_value("[name].size", got.size, expected.size)
  i = 0
  while i < expected.size
    check_value("[name].[i]", got[i], expected[i])
    i += 1

-> string_mode(value)
  (wvalue_bits(value) >> 1) & 7

-> check_join_result(name, got, expected, check_mode = true)
  check_value("[name].class", got.class_name, "String")
  check_value("[name].bytes", got, expected)
  check_value("[name].size", got.size, expected.size)
  if check_mode
    check_value("[name].mode", string_mode(got), string_mode(expected))

-> make_nul_text(a, b)
  bytes = u8[3]
  bytes[0] = a
  bytes[1] = 0
  bytes[2] = b
  ccall("w_string_from_byte_array", bytes)

-> build_i16_values
  values = i16[5]
  values[0] = -32768
  values[1] = -1
  values[2] = 0
  values[3] = 7
  values[4] = 32767
  values

-> build_bool_values
  values = bool[5]
  values.push(true)
  values.push(false)
  values.push(true)
  values.push(true)
  values.push(false)
  values

-> build_f32_values
  values = f32[4]
  values[0] = ~1.5
  values[1] = ~-2.25
  values[2] = ~0.0
  values[3] = ~1000.5
  values

# One nonempty case for every currently decoded WArray storage family, plus a
# nonzero-start u8 view.  The C reference copied the same ebits table as the
# production loader, so this corpus catches signedness/boxing drift instead of
# merely exercising the common polymorphic array.
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
  u8s.shift
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

-> check_compiled_case(name, values, separator)
  c_result = values.__c_join(separator)
  check_join_result("[name].v1", values.__w_join_v1(separator), c_result)
  check_join_result("[name].v2", values.__w_join_v2(separator), c_result)
  check_join_result("[name].v3", values.__w_join_v3(separator), c_result)
  check_join_result("[name].v4", values.__w_join_v4(separator), c_result)
  check_join_result("[name].v5", values.__w_join_v5(separator), c_result)
  check_join_result("[name].v6", values.__w_join_v6(separator), c_result)
  check_join_result("[name].public", values.join(separator), c_result)
  c_result

-> check_compiled_noarg_case(name, values)
  c_result = values.__c_join
  check_join_result("[name].v1", values.__w_join_v1, c_result)
  check_join_result("[name].v2", values.__w_join_v2, c_result)
  check_join_result("[name].v3", values.__w_join_v3, c_result)
  check_join_result("[name].v4", values.__w_join_v4, c_result)
  check_join_result("[name].v5", values.__w_join_v5, c_result)
  check_join_result("[name].v6", values.__w_join_v6, c_result)
  check_join_result("[name].public", values.join, c_result)
  c_result

-> call_join_path(values, path, separator)
  if path == "c"
    return values.__c_join(separator)
  if path == "v1"
    return values.__w_join_v1(separator)
  if path == "v2"
    return values.__w_join_v2(separator)
  if path == "v3"
    return values.__w_join_v3(separator)
  if path == "v4"
    return values.__w_join_v4(separator)
  if path == "v5"
    return values.__w_join_v5(separator)
  if path == "v6"
    return values.__w_join_v6(separator)
  values.join(separator)

-> probe_run(path, bad_call)
  log = []
  left = JoinProbe.new("a", log, 0)
  right = JoinProbe.new("b", log, bad_call)
  output = nil
  raised = false
  begin
    output = call_join_path([left, right], path, "|")
  rescue error
    raised = true
  [output, log, left.calls, right.calls, raised]

-> shrink_probe_run(path)
  holder = [nil]
  log = []
  mutator = JoinShrinkProbe.new(holder, log)
  values = [mutator, "b", "c"]
  holder[0] = values
  if path == "tree"
    output = values.__tree_join1("|")
  else
    output = call_join_path(values, path, "|")
  [output, log, mutator.calls, values.size]

-> check_compiled_shrink_paths
  paths = ["c", "v1", "v2", "v3", "v4", "v5", "v6", "public"]
  i = 0
  while i < paths.size
    path = paths[i]
    result = shrink_probe_run(path)
    check_value("shrink.[path].output", result[0], "m2|b")
    check_array("shrink.[path].order", result[1], ["m1", "m2"])
    check_value("shrink.[path].calls", result[2], 2)
    check_value("shrink.[path].final size", result[3], 2)
    i += 1

-> check_compiled_probe_paths
  paths = ["c", "v1", "v2", "v3", "v4", "v5", "v6", "public"]
  i = 0
  while i < paths.size
    path = paths[i]
    valid = probe_run(path, 0)
    check_value("probe.[path].raised", valid[4], false)
    check_value("probe.[path].output", valid[0], "a2|b2")
    check_array("probe.[path].order", valid[1], ["a1", "b1", "a2", "b2"])
    check_value("probe.[path].left calls", valid[2], 2)
    check_value("probe.[path].right calls", valid[3], 2)

    first_bad = probe_run(path, 1)
    check_value("probe.[path].first-pass error", first_bad[4], true)
    check_array("probe.[path].first-pass order", first_bad[1], ["a1", "b1"])
    check_value("probe.[path].first-pass left calls", first_bad[2], 1)
    check_value("probe.[path].first-pass right calls", first_bad[3], 1)

    second_bad = probe_run(path, 2)
    check_value("probe.[path].second-pass error", second_bad[4], true)
    check_array("probe.[path].second-pass order", second_bad[1], ["a1", "b1", "a2", "b2"])
    check_value("probe.[path].second-pass left calls", second_bad[2], 2)
    check_value("probe.[path].second-pass right calls", second_bad[3], 2)
    i += 1

-> check_invalid_separator_paths
  paths = ["c", "v1", "v2", "v3", "v4", "v5", "v6", "public"]
  i = 0
  while i < paths.size
    path = paths[i]
    log = []
    left = JoinProbe.new("a", log, 0)
    right = JoinProbe.new("b", log, 0)
    raised = false
    begin
      call_join_path([left, right], path, nil)
    rescue error
      raised = true
    check_value("separator.[path].raised", raised, true)
    check_array("separator.[path].order", log, [])
    check_value("separator.[path].left calls", left.calls, 0)
    check_value("separator.[path].right calls", right.calls, 0)
    i += 1

-> check_extra_argument_paths
  values = ["a", "b"]
  c_result = values.__c_join("|", "ignored", 99)
  check_value("extra args C", c_result, "a|b")
  check_join_result("extra args v1", values.__w_join_v1("|", "ignored", 99), c_result)
  check_join_result("extra args v2", values.__w_join_v2("|", "ignored", 99), c_result)
  check_join_result("extra args v3", values.__w_join_v3("|", "ignored", 99), c_result)
  check_join_result("extra args v4", values.__w_join_v4("|", "ignored", 99), c_result)
  check_join_result("extra args v5", values.__w_join_v5("|", "ignored", 99), c_result)
  check_join_result("extra args v6", values.__w_join_v6("|", "ignored", 99), c_result)
  check_join_result("extra args public", values.join("|", "ignored", 99), c_result)

-> run_interpreter_correctness
  check_join_result("tree.empty", ([].__tree_join0), "")
  check_join_result("tree.noarg nonempty", ["a", "b"].__tree_join0, "ab")
  check_join_result("tree.singleton", ["solo"].__tree_join1("ignored"), "solo")
  check_join_result("tree.strings", ["a", "bb", "ccc"].__tree_join1("|"), "a|bb|ccc")
  check_join_result("tree.symbols", [:a, :bb, :ccc].__tree_join1(:x), "axbbxccc")
  check_join_result("tree.mixed", [nil, true, false, 42, -7, ~2.5, :sym, "txt"].__tree_join1("|"),
                    "|true|false|42|-7|2.5|sym|txt")

  nul_item = make_nul_text(65, 66)
  nul_separator = make_nul_text(88, 89)
  check_value("tree.nul item storage", nul_item.size, 3)
  check_value("tree.nul separator storage", nul_separator.size, 3)
  check_join_result("tree.nul item", [nul_item, "C"].__tree_join1("|"), "A|C")
  check_join_result("tree.nul separator", ["a", "b", "c"].__tree_join1(nul_separator), "aXbXc")

  i16_values = build_i16_values()
  bool_values = build_bool_values()
  f32_values = build_f32_values()
  check_join_result("tree.i16", i16_values.__tree_join1(","), "-32768,-1,0,7,32767")
  check_join_result("tree.bool", bool_values.__tree_join1(","), "true,false,true,true,false")
  check_join_result("tree.f32/public", f32_values.__tree_join1("/"), f32_values.join("/"))

  typed_cases = build_typed_cases()
  i = 0
  while i < typed_cases.size
    expected = typed_cases[i].join("|")
    check_join_result("tree.typed branch [i]", typed_cases[i].__tree_join1("|"), expected)
    i += 1

  # Public join now shares the exact two-pass source implementation.
  check_join_result("tree.public ordinary", ["left", "right"].__tree_join1("::"),
                    ["left", "right"].join("::"))

  log = []
  left = JoinProbe.new("a", log, 0)
  right = JoinProbe.new("b", log, 0)
  tree_output = [left, right].__tree_join1("|")
  check_value("tree.probe output", tree_output, "a2|b2")
  check_array("tree.probe order", log, ["a1", "b1", "a2", "b2"])
  check_value("tree.probe left calls", left.calls, 2)
  check_value("tree.probe right calls", right.calls, 2)

  shrink = shrink_probe_run("tree")
  check_value("tree.shrink output", shrink[0], "m2|b")
  check_array("tree.shrink order", shrink[1], ["m1", "m2"])
  check_value("tree.shrink calls", shrink[2], 2)
  check_value("tree.shrink final size", shrink[3], 2)

  public_log = []
  public_left = JoinProbe.new("a", public_log, 0)
  public_right = JoinProbe.new("b", public_log, 0)
  public_output = [public_left, public_right].join("|")
  check_value("tree.public probe output", public_output, "a2|b2")
  check_array("tree.public probe order", public_log, ["a1", "b1", "a2", "b2"])

  << "interpreter correctness: ok (valid bytes/NUL/typed arrays and exact public/candidate two-pass call order)"

-> release_result_array(results)
  ccall("w_ref_array_join_release_batch", results, results.size)

-> validation_buffer_stats(values, reset_each)
  # Use a fresh diagnostic buffer here. A recycled second probe is allowed to
  # inherit the first probe's grown capacity, which is healthy pool behavior
  # but cannot demonstrate the per-invocation capacity bound of reset_each.
  # This helper runs only twice in correctness setup, outside every timing.
  probe = StringBuffer()
  i = 0
  while i < values.size
    text = ccall("w_to_s", values[i])
    ccall("w_strbuf_append", probe, text)
    if reset_each
      ccall("w_bench_strbuf_reset", probe)
    i += 1
  [ccall("w_bench_strbuf_size", probe),
   ccall("w_bench_strbuf_capacity", probe)]

-> check_v3_validation_capacity
  values = build_repeated_workload(1024)
  accumulated = validation_buffer_stats(values, false)
  reset = validation_buffer_stats(values, true)
  check_value("v3 evidence accumulated size positive", accumulated[0] > 0, true)
  check_value("v3 evidence reset logical size", reset[0], 0)
  check_value("v3 evidence capacity below accumulated", reset[1] < accumulated[1], true)
  # Every token in this workload is at most 14 bytes. The constructor's
  # minimum 16-byte capacity should therefore never grow; allow 32 so this
  # remains robust to a small allocator-policy change while still proving the
  # capacity is independent of the 1024-item aggregate payload.
  check_value("v3 evidence bounded capacity", reset[1] <= 32, true)
  << "v3 validation capacity: accumulated=[accumulated[1]] reset=[reset[1]] bytes"

-> check_v6_raw_length_helper
  inline_length = ccall_nobox("w_bench_as_str_length", "abc") ## i64
  symbol_length = ccall_nobox("w_bench_as_str_length", :symbol) ## i64
  rope = ("left-" * 10) + ("right-" * 10)
  rope_length = ccall_nobox("w_bench_as_str_length", rope) ## i64
  nul_text = make_nul_text(65, 66)
  nul_length = ccall_nobox("w_bench_as_str_length", nul_text) ## i64
  check_value("v6 raw inline length", inline_length, 3)
  check_value("v6 raw symbol length", symbol_length, 6)
  check_value("v6 raw rope length", rope_length, 110)
  check_value("v6 raw embedded-NUL boundary", nul_length, 1)

  raised = false
  begin
    invalid_length = ccall_nobox("w_bench_as_str_length", 99) ## i64
  rescue error
    raised = true
  check_value("v6 raw invalid value raises", raised, true)

-> run_compiled_correctness
  # Make runtime as_str failures catchable inside this correctness process so
  # error order can be inspected.  Valid benchmark paths are unaffected.
  ccall("w_enable_catchable_die")

  check_value("empty noarg", check_compiled_noarg_case("empty.noarg", []), "")
  check_value("nonempty noarg", check_compiled_noarg_case("nonempty.noarg", ["a", "b"]), "ab")
  check_value("empty separator", check_compiled_case("empty.separator", [], "unused"), "")
  check_value("singleton", check_compiled_case("singleton", ["solo"], "ignored"), "solo")
  check_value("strings", check_compiled_case("strings", ["a", "bb", "ccc"], "|"), "a|bb|ccc")
  check_value("symbols", check_compiled_case("symbols", [:a, :bb, :ccc], :x), "axbbxccc")
  check_value("mixed", check_compiled_case("mixed", [nil, true, false, 42, -7, ~2.5, :sym, "txt"], "|"),
              "|true|false|42|-7|2.5|sym|txt")

  nul_item = make_nul_text(65, 66)
  nul_separator = make_nul_text(88, 89)
  check_value("nul item storage", nul_item.size, 3)
  check_value("nul separator storage", nul_separator.size, 3)
  check_value("nul item", check_compiled_case("nul.item", [nul_item, "C"], "|"), "A|C")
  check_value("nul separator", check_compiled_case("nul.separator", ["a", "b", "c"], nul_separator), "aXbXc")

  rope_item = ("left-" * 10) + ("right-" * 10)
  rope_separator = (":" * 40) + (";" * 40)
  check_compiled_case("rope.item", [rope_item, "tail"], "|")
  check_compiled_case("rope.separator", ["a", "b", "c"], rope_separator)

  check_value("i16", check_compiled_case("typed.i16", build_i16_values(), ","), "-32768,-1,0,7,32767")
  check_value("bool", check_compiled_case("typed.bool", build_bool_values(), ","), "true,false,true,true,false")
  check_compiled_case("typed.f32", build_f32_values(), "/")

  typed_cases = build_typed_cases()
  i = 0
  while i < typed_cases.size
    check_compiled_case("typed.branch.[i]", typed_cases[i], "|")
    i += 1

  check_compiled_probe_paths()
  check_compiled_shrink_paths()
  check_invalid_separator_paths()
  check_extra_argument_paths()
  check_v3_validation_capacity()
  check_v6_raw_length_helper()

  # Before freeze, all paths use the existing six-byte slab entry.
  prefreeze = ["abc", "def"].__c_join
  check_value("prefreeze known bytes", prefreeze, "abcdef")
  check_value("prefreeze known mode", string_mode(prefreeze), 6)
  check_value("prefreeze known identity", wvalue_bits(prefreeze), wvalue_bits("abcdef"))
  check_compiled_noarg_case("prefreeze.known", ["abc", "def"])

  # >61-byte outputs are fresh mode-7 strings in every slab state.
  long_values = ["xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
                 "yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy"]
  long_c1 = long_values.__c_join
  long_c2 = long_values.__c_join
  long_v11 = long_values.__w_join_v1
  long_v12 = long_values.__w_join_v1
  long_v21 = long_values.__w_join_v2
  long_v22 = long_values.__w_join_v2
  long_v31 = long_values.__w_join_v3
  long_v32 = long_values.__w_join_v3
  long_v41 = long_values.__w_join_v4
  long_v42 = long_values.__w_join_v4
  long_v51 = long_values.__w_join_v5
  long_v52 = long_values.__w_join_v5
  long_v61 = long_values.__w_join_v6
  long_v62 = long_values.__w_join_v6
  long_p1 = long_values.join
  long_p2 = long_values.join
  long_results = [long_c1, long_c2, long_v11, long_v12,
                  long_v21, long_v22, long_v31, long_v32,
                  long_v41, long_v42, long_v51, long_v52,
                  long_v61, long_v62, long_p1, long_p2]
  i = 0
  while i < long_results.size
    check_value("long fresh mode [i]", string_mode(long_results[i]), 7)
    check_value("long fresh size [i]", long_results[i].size, 80)
    i += 1
  check_value("long C freshness", wvalue_bits(long_c1) == wvalue_bits(long_c2), false)
  check_value("long v1 freshness", wvalue_bits(long_v11) == wvalue_bits(long_v12), false)
  check_value("long v2 freshness", wvalue_bits(long_v21) == wvalue_bits(long_v22), false)
  check_value("long v3 freshness", wvalue_bits(long_v31) == wvalue_bits(long_v32), false)
  check_value("long v4 freshness", wvalue_bits(long_v41) == wvalue_bits(long_v42), false)
  check_value("long v5 freshness", wvalue_bits(long_v51) == wvalue_bits(long_v52), false)
  check_value("long v6 freshness", wvalue_bits(long_v61) == wvalue_bits(long_v62), false)
  check_value("long public freshness", wvalue_bits(long_p1) == wvalue_bits(long_p2), false)
  release_result_array(long_results)

  # After freeze, w_string_take always returns a fresh mode-7 value for the
  # same bytes.  This is the subtle representation edge that a plain
  # StringBuffer#to_s port misses.
  freeze_slab()
  known_values = ["abc", "def"]
  frozen_c = known_values.__c_join
  frozen_c2 = known_values.__c_join
  frozen_v1 = known_values.__w_join_v1
  frozen_v12 = known_values.__w_join_v1
  frozen_v2 = known_values.__w_join_v2
  frozen_v22 = known_values.__w_join_v2
  frozen_v3 = known_values.__w_join_v3
  frozen_v32 = known_values.__w_join_v3
  frozen_v4 = known_values.__w_join_v4
  frozen_v42 = known_values.__w_join_v4
  frozen_v5 = known_values.__w_join_v5
  frozen_v52 = known_values.__w_join_v5
  frozen_v6 = known_values.__w_join_v6
  frozen_v62 = known_values.__w_join_v6
  frozen_public = known_values.join
  frozen_public2 = known_values.join
  frozen_results = [frozen_c, frozen_c2, frozen_v1, frozen_v12,
                    frozen_v2, frozen_v22, frozen_v3, frozen_v32,
                    frozen_v4, frozen_v42, frozen_v5, frozen_v52,
                    frozen_v6, frozen_v62, frozen_public, frozen_public2]
  i = 0
  while i < frozen_results.size
    check_value("frozen known bytes [i]", frozen_results[i], "abcdef")
    check_value("frozen known mode [i]", string_mode(frozen_results[i]), 7)
    check_value("frozen differs from slab [i]",
                wvalue_bits(frozen_results[i]) == wvalue_bits("abcdef"), false)
    i += 1
  check_value("frozen C freshness", wvalue_bits(frozen_c) == wvalue_bits(frozen_c2), false)
  check_value("frozen v1 freshness", wvalue_bits(frozen_v1) == wvalue_bits(frozen_v12), false)
  check_value("frozen v2 freshness", wvalue_bits(frozen_v2) == wvalue_bits(frozen_v22), false)
  check_value("frozen v3 freshness", wvalue_bits(frozen_v3) == wvalue_bits(frozen_v32), false)
  check_value("frozen v4 freshness", wvalue_bits(frozen_v4) == wvalue_bits(frozen_v42), false)
  check_value("frozen v5 freshness", wvalue_bits(frozen_v5) == wvalue_bits(frozen_v52), false)
  check_value("frozen v6 freshness", wvalue_bits(frozen_v6) == wvalue_bits(frozen_v62), false)
  check_value("frozen public freshness", wvalue_bits(frozen_public) == wvalue_bits(frozen_public2), false)
  release_result_array(frozen_results)

  frozen_empty = [([].__c_join), ([].__w_join_v1), ([].__w_join_v2),
                  ([].__w_join_v3), ([].__w_join_v4), ([].__w_join_v5),
                  ([].__w_join_v6), ([].join)]
  i = 0
  while i < frozen_empty.size
    check_value("frozen empty bytes [i]", frozen_empty[i], "")
    check_value("frozen empty mode [i]", string_mode(frozen_empty[i]), 0)
    i += 1

  << "compiled correctness: ok (C/v1-v6/public bytes, modes, NUL, typed arrays, exact errors/call order, arity split, frozen-slab representation, v3 bounded capacity, v4/v5 reduced buffers, and v6 raw validation)"

-> workload_tokens
  ["alpha-000000", "beta--111111", "gamma-222222", "delta-333333",
   "epsilon-4444", "zeta--555555", "eta---666666", "theta-777777"]

-> build_repeated_workload(count)
  tokens = workload_tokens()
  values = []
  i = 0
  while i < count
    values.push(tokens[i & 7])
    i += 1
  values

-> build_utf8_workload
  tokens = ["λambda-000", "naïve-111", "café--222", "日本語-333",
            "한국어-444", "русский-555", "नमस्ते-666", "🚀-orbit-777"]
  values = []
  i = 0
  while i < 64
    values.push(tokens[i & 7])
    i += 1
  values

-> build_typed_workload
  values = i16[64]
  i = 0
  while i < 64
    values[i] = i * 97 - 3000
    i += 1
  values

-> workload_values(name)
  if name == "empty"
    return []
  if name == "singleton"
    return ["alpha-000000"]
  if name == "pair"
    return build_repeated_workload(2)
  if name == "four"
    return build_repeated_workload(4)
  if name == "eight"
    return build_repeated_workload(8)
  if name == "medium"
    return build_repeated_workload(64)
  if name == "large"
    return build_repeated_workload(256)
  if name == "huge"
    return build_repeated_workload(1024)
  if name == "utf8"
    return build_utf8_workload()
  if name == "typed"
    return build_typed_workload()
  build_repeated_workload(64)

-> release_batch(outputs, count)
  ccall("w_ref_array_join_release_batch", outputs, count)

-> time_join_c(values, separator, iters)
  outputs = w64[BATCH_SIZE]
  checksum = 0
  elapsed = 0
  completed = 0
  while completed < iters
    count = iters - completed
    count = BATCH_SIZE if count > BATCH_SIZE
    i = 0
    start_ns = clock()
    while i < count
      out = values.__c_join(separator)
      outputs[i] = out
      checksum += out.size
      i += 1
    elapsed += clock() - start_ns
    release_batch(outputs, count)
    completed += count
  [elapsed, checksum]

-> time_join_v1(values, separator, iters)
  outputs = w64[BATCH_SIZE]
  checksum = 0
  elapsed = 0
  completed = 0
  while completed < iters
    count = iters - completed
    count = BATCH_SIZE if count > BATCH_SIZE
    i = 0
    start_ns = clock()
    while i < count
      out = values.__w_join_v1_impl(separator)
      outputs[i] = out
      checksum += out.size
      i += 1
    elapsed += clock() - start_ns
    release_batch(outputs, count)
    completed += count
  [elapsed, checksum]

-> time_join_v2(values, separator, iters)
  outputs = w64[BATCH_SIZE]
  checksum = 0
  elapsed = 0
  completed = 0
  while completed < iters
    count = iters - completed
    count = BATCH_SIZE if count > BATCH_SIZE
    i = 0
    start_ns = clock()
    while i < count
      out = values.__w_join_v2_impl(separator)
      outputs[i] = out
      checksum += out.size
      i += 1
    elapsed += clock() - start_ns
    release_batch(outputs, count)
    completed += count
  [elapsed, checksum]

-> time_join_v3(values, separator, iters)
  outputs = w64[BATCH_SIZE]
  checksum = 0
  elapsed = 0
  completed = 0
  while completed < iters
    count = iters - completed
    count = BATCH_SIZE if count > BATCH_SIZE
    i = 0
    start_ns = clock()
    while i < count
      out = values.__w_join_v3_impl(separator)
      outputs[i] = out
      checksum += out.size
      i += 1
    elapsed += clock() - start_ns
    release_batch(outputs, count)
    completed += count
  [elapsed, checksum]

-> time_join_v4(values, separator, iters)
  outputs = w64[BATCH_SIZE]
  checksum = 0
  elapsed = 0
  completed = 0
  while completed < iters
    count = iters - completed
    count = BATCH_SIZE if count > BATCH_SIZE
    i = 0
    start_ns = clock()
    while i < count
      out = values.__w_join_v4_impl(separator)
      outputs[i] = out
      checksum += out.size
      i += 1
    elapsed += clock() - start_ns
    release_batch(outputs, count)
    completed += count
  [elapsed, checksum]

-> time_join_v5(values, separator, iters)
  outputs = w64[BATCH_SIZE]
  checksum = 0
  elapsed = 0
  completed = 0
  while completed < iters
    count = iters - completed
    count = BATCH_SIZE if count > BATCH_SIZE
    i = 0
    start_ns = clock()
    while i < count
      out = values.__w_join_v5_impl(separator)
      outputs[i] = out
      checksum += out.size
      i += 1
    elapsed += clock() - start_ns
    release_batch(outputs, count)
    completed += count
  [elapsed, checksum]

-> time_join_v6(values, separator, iters)
  outputs = w64[BATCH_SIZE]
  checksum = 0
  elapsed = 0
  completed = 0
  while completed < iters
    count = iters - completed
    count = BATCH_SIZE if count > BATCH_SIZE
    i = 0
    start_ns = clock()
    while i < count
      out = values.__w_join_v6_impl(separator)
      outputs[i] = out
      checksum += out.size
      i += 1
    elapsed += clock() - start_ns
    release_batch(outputs, count)
    completed += count
  [elapsed, checksum]

-> time_join_public(values, separator, iters)
  outputs = w64[BATCH_SIZE]
  checksum = 0
  elapsed = 0
  completed = 0
  while completed < iters
    count = iters - completed
    count = BATCH_SIZE if count > BATCH_SIZE
    i = 0
    start_ns = clock()
    while i < count
      out = values.join(separator)
      outputs[i] = out
      checksum += out.size
      i += 1
    elapsed += clock() - start_ns
    release_batch(outputs, count)
    completed += count
  [elapsed, checksum]

-> time_candidate(values, separator, iters, path)
  if path == "v1"
    return time_join_v1(values, separator, iters)
  if path == "v3"
    return time_join_v3(values, separator, iters)
  if path == "v4"
    return time_join_v4(values, separator, iters)
  if path == "v5"
    return time_join_v5(values, separator, iters)
  if path == "v6"
    return time_join_v6(values, separator, iters)
  if path == "public"
    return time_join_public(values, separator, iters)
  time_join_v2(values, separator, iters)

-> time_baseline(values, separator, iters, path)
  if path == "v1"
    return time_join_v1(values, separator, iters)
  time_join_c(values, separator, iters)

-> combine_results(first, second)
  [first[0] + second[0], first[1] + second[1]]

-> report_result(path, baseline, workload, base_result, w_result, iters)
  if base_result[1] != w_result[1]
    fail_check("benchmark checksum join.[path]-vs-[baseline].[workload]", "base=[base_result[1]] W=[w_result[1]]")
  base_ns = base_result[0] * 1_000_000_000 / (iters * 2)
  w_ns = w_result[0] * 1_000_000_000 / (iters * 2)
  ratio = w_result[0] / base_result[0]
  << "RESULT|join.[path].[workload]|[base_ns]|[w_ns]|[ratio]|[base_result[1]]|[baseline]"

-> run_pair(values, separator, iters, parity, path, baseline, workload, emit = true)
  if parity == 0
    base_first = time_baseline(values, separator, iters, baseline)
    w_first = time_candidate(values, separator, iters, path)
    w_second = time_candidate(values, separator, iters, path)
    base_second = time_baseline(values, separator, iters, baseline)
  else
    w_first = time_candidate(values, separator, iters, path)
    base_first = time_baseline(values, separator, iters, baseline)
    base_second = time_baseline(values, separator, iters, baseline)
    w_second = time_candidate(values, separator, iters, path)
  base_result = combine_results(base_first, base_second)
  w_result = combine_results(w_first, w_second)
  if emit
    report_result(path, baseline, workload, base_result, w_result, iters)

-> run_batch_smoke
  values = build_repeated_workload(64)
  separator = "::"
  smoke_iters = BATCH_SIZE + 17
  c_result = time_join_c(values, separator, smoke_iters)
  v1_result = time_join_v1(values, separator, smoke_iters)
  v2_result = time_join_v2(values, separator, smoke_iters)
  v3_result = time_join_v3(values, separator, smoke_iters)
  v4_result = time_join_v4(values, separator, smoke_iters)
  v5_result = time_join_v5(values, separator, smoke_iters)
  v6_result = time_join_v6(values, separator, smoke_iters)
  public_result = time_join_public(values, separator, smoke_iters)
  check_value("batch smoke v1", v1_result[1], c_result[1])
  check_value("batch smoke v2", v2_result[1], c_result[1])
  check_value("batch smoke v3", v3_result[1], c_result[1])
  check_value("batch smoke v4", v4_result[1], c_result[1])
  check_value("batch smoke v5", v5_result[1], c_result[1])
  check_value("batch smoke v6", v6_result[1], c_result[1])
  check_value("batch smoke public", public_result[1], c_result[1])
  << "batch cleanup smoke: ok ([smoke_iters] heap results per path; full + partial batch)"

-> run_bench(values, separator, iters, parity, path, baseline, workload)
  run_pair(values, separator, WARMUP_ITERS, parity, path, baseline, workload, false)
  run_pair(values, separator, iters, parity, path, baseline, workload)

-> run_fatal_case(kind, path)
  if kind == "integer-empty"
    call_join_path([], path, 123)
  elsif kind == "explicit-nil"
    call_join_path(["a"], path, nil)
  elsif kind == "bad-to-s"
    log = []
    bad = JoinProbe.new("b", log, 1)
    call_join_path([bad], path, "|")
  else
    << "unknown fatal case"
    exit(2)
  << "fatal case unexpectedly returned"
  exit(0)

args = argv()
mode = args.size > 0 ? args[0] : "bench"

if mode == "interpreter-check"
  run_interpreter_correctness()
  exit(0)

if mode == "check"
  run_compiled_correctness()
  run_batch_smoke()
  exit(0)

if mode == "fatal"
  if args.size < 3
    << "fatal mode requires a case and path"
    exit(2)
  run_fatal_case(args[1], args[2])
  exit(0)

iters = args.size > 1 ? args[1].to_i : DEFAULT_ITERS
if iters <= 0
  << "iterations must be positive"
  exit(2)

parity = args.size > 2 ? args[2].to_i : 0
if parity != 0 && parity != 1
  << "sample parity must be 0 (C/W/W/C) or 1 (W/C/C/W)"
  exit(2)

path = args.size > 3 ? args[3] : "v2"
if path != "v1" && path != "v2" && path != "v3" && path != "v4" && path != "v5" && path != "v6" && path != "public"
  << "candidate path must be v1, v2, v3, v4, v5, v6, or public"
  exit(2)

workload = args.size > 4 ? args[4] : "medium"
valid_workload = workload == "empty" || workload == "singleton" || workload == "pair" || workload == "four" || workload == "eight" || workload == "medium" || workload == "large" || workload == "huge" || workload == "utf8" || workload == "typed"
if !valid_workload
  << "workload must be empty, singleton, pair, four, eight, medium, large, huge, utf8, or typed"
  exit(2)

baseline = args.size > 5 ? args[5] : "c"
if baseline != "c" && baseline != "v1"
  << "baseline path must be c or v1"
  exit(2)
if baseline == path
  << "baseline and candidate paths must differ"
  exit(2)

run_bench(workload_values(workload), "::", iters, parity, path, baseline, workload)
