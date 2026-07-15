# Strict benchmark-only Array#uniq source-port harness. Production dispatch is
# untouched. v1 is the exact quadratic C control flow in Tungsten; v2 keeps
# that path for small/non-text-first inputs and uses Hash only for the one
# equivalence family proven identical to w_eq: String/rope and Symbol keys.

use array_uniq_candidates

BATCH_SIZE = 128
DEFAULT_ITERS = 20_000
WARMUP_ITERS = 500

+ UniqProbe
  -> new(@label)

+ Array
  -> __c_uniq
    ccall("w_ref_array_uniq", self)

-> fail_check(name, detail)
  << "FAIL [name]: [detail]"
  exit(1)

-> check_value(name, got, expected)
  if got != expected
    fail_check(name, "got=[got] expected=[expected]")

-> result_cap(value)
  ccall("w_bench_uniq_array_cap", value)

-> check_result(name, got, expected)
  check_value("[name].size", got.size, expected.size)
  check_value("[name].start", ccall("w_bench_uniq_array_start", got), 0)
  check_value("[name].ebits", ccall("w_bench_uniq_array_ebits", got), 65)
  check_value("[name].cap", result_cap(got), result_cap(expected))
  i = 0
  while i < expected.size
    got_bits = wvalue_bits(got[i]) ## i64
    expected_bits = wvalue_bits(expected[i]) ## i64
    if got_bits != expected_bits
      fail_check("[name].item.[i]", "got-bits=[got_bits] expected-bits=[expected_bits]")
    i += 1

-> check_case(name, values)
  c_result = values.__c_uniq
  v1_result = values.__w_uniq_v1
  v2_result = values.__w_uniq_v2
  public_result = values.uniq
  check_result("[name].v1", v1_result, c_result)
  check_result("[name].v2", v2_result, c_result)
  check_result("[name].public", public_result, c_result)
  source_bits = wvalue_bits(values) ## i64
  c_bits = wvalue_bits(c_result) ## i64
  v1_bits = wvalue_bits(v1_result) ## i64
  v2_bits = wvalue_bits(v2_result) ## i64
  public_bits = wvalue_bits(public_result) ## i64
  if c_bits == source_bits || v1_bits == source_bits || v2_bits == source_bits || public_bits == source_bits
    fail_check("[name].fresh", "uniq returned its receiver")
  if c_bits == v1_bits || c_bits == v2_bits || c_bits == public_bits || v1_bits == v2_bits || v1_bits == public_bits || v2_bits == public_bits
    fail_check("[name].independent", "two paths aliased the same result Array")

-> make_nul_text(a, b)
  bytes = u8[3]
  bytes[0] = a
  bytes[1] = 0
  bytes[2] = b
  ccall("w_string_from_byte_array", bytes)

-> build_typed_cases
  cases = []

  cases.push(u8[0])

  bools = bool[6]
  bools[0] = true
  bools[1] = false
  bools[2] = true
  bools[3] = false
  bools[4] = true
  bools[5] = true
  cases.push(bools)

  bits = u1[6]
  bits[0] = 1
  bits[1] = 0
  bits[2] = 1
  bits[3] = 1
  bits[4] = 0
  bits[5] = 0
  cases.push(bits)

  u4s = u4[6]
  u4s[0] = 1
  u4s[1] = 15
  u4s[2] = 1
  u4s[3] = 7
  u4s[4] = 15
  u4s[5] = 0
  cases.push(u4s)

  i4s = i4[6]
  i4s[0] = -8
  i4s[1] = -1
  i4s[2] = 7
  i4s[3] = -8
  i4s[4] = 7
  i4s[5] = 0
  cases.push(i4s)

  u8s = u8[7]
  u8s[0] = 99
  u8s[1] = 3
  u8s[2] = 251
  u8s[3] = 3
  u8s[4] = 17
  u8s[5] = 251
  u8s[6] = 17
  u8s.shift
  cases.push(u8s)

  i8s = i8[6]
  i8s[0] = -128
  i8s[1] = -7
  i8s[2] = 127
  i8s[3] = -128
  i8s[4] = 127
  i8s[5] = 0
  cases.push(i8s)

  u16s = u16[6]
  u16s[0] = 17
  u16s[1] = 32768
  u16s[2] = 65535
  u16s[3] = 17
  u16s[4] = 65535
  u16s[5] = 0
  cases.push(u16s)

  i16s = i16[6]
  i16s[0] = -32768
  i16s[1] = 7
  i16s[2] = -32768
  i16s[3] = 32767
  i16s[4] = 7
  i16s[5] = 0
  cases.push(i16s)

  u32s = u32[6]
  u32s[0] = 19
  u32s[1] = 4_000_000_000
  u32s[2] = 19
  u32s[3] = 1_000_000
  u32s[4] = 4_000_000_000
  u32s[5] = 0
  cases.push(u32s)

  i32s = i32[6]
  i32s[0] = -2_000_000_000
  i32s[1] = -13
  i32s[2] = 2_000_000_000
  i32s[3] = -2_000_000_000
  i32s[4] = 2_000_000_000
  i32s[5] = 0
  cases.push(i32s)

  u64s = u64[6]
  u64s[0] = 23
  u64s[1] = 1_000_000_000
  u64s[2] = 2_000_000_000
  u64s[3] = 23
  u64s[4] = 2_000_000_000
  u64s[5] = 0
  cases.push(u64s)

  i64s = i64[6]
  i64s[0] = -2_000_000_000
  i64s[1] = 17
  i64s[2] = -2_000_000_000
  i64s[3] = 2_000_000_000
  i64s[4] = 17
  i64s[5] = 0
  cases.push(i64s)

  f32s = f32[6]
  f32s[0] = ~1.5
  f32s[1] = ~-2.25
  f32s[2] = ~1.5
  f32s[3] = ~3.75
  f32s[4] = ~-2.25
  f32s[5] = ~0.0
  cases.push(f32s)

  nan = ccall("w_bench_uniq_nan")
  f64s = f64[6]
  f64s[0] = nan
  f64s[1] = nan
  f64s[2] = ~1.0
  f64s[3] = ~1.0
  f64s[4] = ~-0.0
  f64s[5] = ~0.0
  cases.push(f64s)

  bf16s = bf16[6]
  bf16s[0] = ~1.5
  bf16s[1] = ~-2.0
  bf16s[2] = ~1.5
  bf16s[3] = ~4.0
  bf16s[4] = ~-2.0
  bf16s[5] = ~0.0
  cases.push(bf16s)

  wvalues = w64[6]
  wvalues[0] = "first"
  wvalues[1] = nil
  wvalues[2] = "first"
  wvalues[3] = false
  wvalues[4] = nil
  wvalues[5] = false
  cases.push(wvalues)

  cases

-> run_correctness
  # Drain the bounded polymorphic-array pool and retain every guard. All C/W
  # outputs below consequently start at cap 8, so exact growth/cap parity is
  # observable instead of depending on whichever old capacity a pool held.
  pool_guards = []
  i = 0
  while i < 24
    pool_guards.push([])
    i += 1

  heap_a = "heap-alpha-value" * 8
  heap_b = "heap-alpha-value" * 8
  heap_c = "heap-gamma-value" * 8
  rope_a = ("abcdefgh" * 8) + ("ijklmnop" * 8)
  rope_b = ("abcdefgh" * 8) + ("ijklmnop" * 8)
  rope_c = ("abcdefgh" * 8) + ("qrstuvwx" * 8)

  # Pin the pure-Tungsten WValue classifier before testing the hybrid. These
  # cover every admitted representation (inline/slab/heap String, Symbol,
  # generic-object Rope) and representatives of every guard that must avoid
  # the raw type-byte load.
  check_value("representation.heap.tag", (wvalue_bits(heap_a) >> 48) & 0xFFFF, 0xFFF9)
  check_value("representation.heap.mode", (wvalue_bits(heap_a) >> 1) & 7, 7)
  check_value("representation.rope.tag", (wvalue_bits(rope_a) >> 48) & 0xFFFF, 0)
  check_value("representation.rope.subtag", wvalue_bits(rope_a) & 0xF, 0)
  check_value("classify.inline-string", array_uniq_text_hash_safe?("a"), true)
  check_value("classify.slab-string", array_uniq_text_hash_safe?("slab-value"), true)
  check_value("classify.heap-string", array_uniq_text_hash_safe?(heap_a), true)
  check_value("classify.rope", array_uniq_text_hash_safe?(rope_a), true)
  check_value("classify.symbol", array_uniq_text_hash_safe?(:same), true)
  check_value("classify.nil", array_uniq_text_hash_safe?(nil), false)
  check_value("classify.bool", array_uniq_text_hash_safe?(true), false)
  check_value("classify.int", array_uniq_text_hash_safe?(1), false)
  check_value("classify.float", array_uniq_text_hash_safe?(~1.0), false)
  check_value("classify.array", array_uniq_text_hash_safe?([]), false)
  check_value("classify.hash", array_uniq_text_hash_safe?({}), false)

  check_case("empty", [])
  check_case("singleton", ["only"])
  check_case("first-order", ["b", "a", "b", "c", "a", "d"])
  check_case("string-symbol-distinct", ["same", :same, "same", :same])
  check_case("threshold-quadratic", repeated_text(ARRAY_UNIQ_SMALL_THRESHOLD))
  check_case("threshold-hash", repeated_text(ARRAY_UNIQ_SMALL_THRESHOLD + 1))
  check_case("hybrid-text-large", repeated_text(64))

  check_case("rope-content", [rope_a, rope_b, "tail", rope_a])
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
  check_case("hybrid-heap-first", heap_values)
  check_case("hybrid-rope-first", rope_values)
  check_case("hybrid-symbol-first", symbol_values)
  check_case("nontext-first-stays-quadratic", nontext_first)

  nul_a = make_nul_text(65, 66)
  nul_b = make_nul_text(65, 66)
  nul_c = make_nul_text(65, 67)
  check_case("embedded-nul-content", [nul_a, nul_b, nul_c, nul_a])
  nul_values = []
  i = 0
  while i < 24
    nul_values.push((i & 1) == 1 ? nul_a : nul_c)
    i += 1
  check_case("hybrid-embedded-nul", nul_values)

  # w_eq's numeric relation crosses int/float and float/decimal, while direct
  # int/decimal is currently distinct. Keep both orderings pinned.
  check_case("numeric-cross-a", [1, ~1.0, 1.00, 2.00, ~2.0, 2])
  check_case("numeric-cross-b", [1.00, 1, ~1.0, 2, 2.00, ~2.0])
  check_case("signed-zero", [~0.0, ~-0.0, ~0.0])

  nan = ccall("w_bench_uniq_nan")
  check_case("nan-remains-unique", [nan, nan, nan])

  big_a = ccall("w_bench_uniq_bigint")
  big_b = ccall("w_bench_uniq_bigint")
  check_value("classify.generic-bigint", array_uniq_text_hash_safe?(big_a), false)
  check_case("bigint-value", [big_a, big_b, big_a])

  half = ccall("w_bench_uniq_rational", 1, 2)
  two_quarters = ccall("w_bench_uniq_rational", 2, 4)
  check_case("rational-normalization", [half, two_quarters, half])

  bytes_a = u8[3]
  bytes_b = u8[3]
  i = 0
  while i < 3
    bytes_a[i] = i + 10
    bytes_b[i] = i + 10
    i += 1
  check_case("bytearray-structural", [bytes_a, bytes_b, bytes_a])

  ip_a = ccall("w_bench_uniq_ipv6")
  ip_b = ccall("w_bench_uniq_ipv6")
  mac_a = ccall("w_bench_uniq_mac")
  mac_b = ccall("w_bench_uniq_mac")
  check_value("classify.generic-ipv6", array_uniq_text_hash_safe?(ip_a), false)
  check_value("classify.generic-mac", array_uniq_text_hash_safe?(mac_a), false)
  check_case("netaddr-structural", [ip_a, ip_b, mac_a, mac_b, ip_a])

  same_object = UniqProbe.new("same")
  other_object = UniqProbe.new("same")
  check_case("object-identity", [same_object, same_object, other_object, other_object])

  nested_same = [1]
  nested_other = [1]
  hash_same = {value: 1}
  hash_other = {value: 1}
  check_case("nested-array-identity", [nested_same, nested_same, nested_other, nested_other])
  check_case("hash-identity", [hash_same, hash_same, hash_other, hash_other])

  shifted = ["discard", "a", "b", "a"]
  shifted.shift
  check_case("shifted-polymorphic", shifted)

  # Force v2's text Hash branch while mixing in every important fallback
  # category. Text duplicates use Hash; all remaining comparisons stay w_eq.
  hybrid_mixed = ["lead", 1, ~1.0, 1.00, nan, nan, half, two_quarters,
                  bytes_a, bytes_b, ip_a, ip_b, same_object, same_object,
                  other_object, :lead, "lead", :lead, 2, ~2.0,
                  "tail", "tail", mac_a, mac_b]
  check_case("hybrid-mixed-fallback", hybrid_mixed)

  typed = build_typed_cases()
  i = 0
  while i < typed.size
    check_case("typed.[i]", typed[i])
    i += 1

  extra_values = ["a", "b", "a"]
  extra_c = extra_values.__c_uniq("ignored", 99)
  check_result("extra.v1", extra_values.__w_uniq_v1("ignored", 99), extra_c)
  check_result("extra.v2", extra_values.__w_uniq_v2("ignored", 99), extra_c)
  check_result("extra.public", extra_values.uniq("ignored", 99), extra_c)

  << "correctness: ok (C/v1/v2/public order, fresh independent outputs, exact-bit elements, output cap/growth, every text representation and threshold branch, text-only Hash plus mixed fallback, numeric/NaN/rational/bytes/netaddr/object/nested identity semantics, shifted inputs, extra args, and every typed decoder family)"

-> text_tokens
  ["alpha-000", "beta--111", "gamma-222", "delta-333",
   "epsilon-44", "zeta--555", "eta---666", "theta-777"]

-> repeated_text(count)
  tokens = text_tokens()
  values = []
  i = 0
  while i < count
    values.push(tokens[i & 7])
    i += 1
  values

-> unique_text(count)
  values = []
  i = 0
  while i < count
    values.push("unique-value-" + i.to_s)
    i += 1
  values

-> repeated_numeric(count)
  values = []
  i = 0
  while i < count
    values.push((i * 17) & 31)
    i += 1
  values

-> mixed_text_first(count)
  values = []
  tokens = text_tokens()
  i = 0
  while i < count
    if (i & 3) == 3
      values.push(i & 15)
    else
      values.push(tokens[i & 7])
    i += 1
  values

-> typed_workload(count)
  values = u16[count]
  i = 0
  while i < count
    values[i] = (i * 13) & 31
    i += 1
  values

-> workload_values(name)
  if name == "empty"
    return []
  if name == "singleton"
    return ["only"]
  if name == "small-text"
    return repeated_text(8)
  if name == "small-mixed"
    return ["a", 1, :a, ~1.0, "a", 1.00, nil, :a]
  if name == "text-low"
    return repeated_text(64)
  if name == "text-unique"
    return unique_text(64)
  if name == "text-large"
    return repeated_text(1024)
  if name == "numeric"
    return repeated_numeric(64)
  if name == "mixed"
    return mixed_text_first(64)
  if name == "typed"
    return typed_workload(64)
  repeated_text(64)

-> result_checksum(result)
  checksum = result.size
  if result.size > 0
    checksum += wvalue_bits(result[0]) & 0xFF
    checksum += wvalue_bits(result[result.size - 1]) & 0xFF
  checksum

-> release_batch(outputs, count)
  ccall("w_bench_uniq_release_batch", outputs, count)

-> time_uniq_c(values, iters)
  outputs = w64[BATCH_SIZE]
  elapsed = 0
  checksum = 0
  completed = 0
  while completed < iters
    count = iters - completed
    count = BATCH_SIZE if count > BATCH_SIZE
    i = 0
    start_ns = clock()
    while i < count
      result = values.__c_uniq
      outputs[i] = result
      checksum += result_checksum(result)
      i += 1
    elapsed += clock() - start_ns
    release_batch(outputs, count)
    completed += count
  [elapsed, checksum]

-> time_uniq_v1(values, iters)
  outputs = w64[BATCH_SIZE]
  elapsed = 0
  checksum = 0
  completed = 0
  while completed < iters
    count = iters - completed
    count = BATCH_SIZE if count > BATCH_SIZE
    i = 0
    start_ns = clock()
    while i < count
      result = values.__w_uniq_v1
      outputs[i] = result
      checksum += result_checksum(result)
      i += 1
    elapsed += clock() - start_ns
    release_batch(outputs, count)
    completed += count
  [elapsed, checksum]

-> time_uniq_v2(values, iters)
  outputs = w64[BATCH_SIZE]
  elapsed = 0
  checksum = 0
  completed = 0
  while completed < iters
    count = iters - completed
    count = BATCH_SIZE if count > BATCH_SIZE
    i = 0
    start_ns = clock()
    while i < count
      result = values.__w_uniq_v2
      outputs[i] = result
      checksum += result_checksum(result)
      i += 1
    elapsed += clock() - start_ns
    release_batch(outputs, count)
    completed += count
  [elapsed, checksum]

-> time_candidate(values, iters, path)
  if path == "v1"
    return time_uniq_v1(values, iters)
  time_uniq_v2(values, iters)

-> combine_results(first, second)
  [first[0] + second[0], first[1] + second[1]]

-> run_pair(values, iters, parity, path, workload, emit = true)
  if parity == 0
    c_first = time_uniq_c(values, iters)
    w_first = time_candidate(values, iters, path)
    w_second = time_candidate(values, iters, path)
    c_second = time_uniq_c(values, iters)
  else
    w_first = time_candidate(values, iters, path)
    c_first = time_uniq_c(values, iters)
    c_second = time_uniq_c(values, iters)
    w_second = time_candidate(values, iters, path)

  c_result = combine_results(c_first, c_second)
  w_result = combine_results(w_first, w_second)
  if c_result[1] != w_result[1]
    fail_check("benchmark.[path].[workload]", "C checksum=[c_result[1]] W checksum=[w_result[1]]")
  if emit
    c_ns = c_result[0] * 1_000_000_000 / (iters * 2)
    w_ns = w_result[0] * 1_000_000_000 / (iters * 2)
    << "RESULT|uniq.[path].[workload]|[c_ns]|[w_ns]|[w_result[0] / c_result[0]]|[c_result[1]]"

-> run_batch_smoke
  values = repeated_text(64)
  iters = BATCH_SIZE + 11
  c_result = time_uniq_c(values, iters)
  v1_result = time_uniq_v1(values, iters)
  v2_result = time_uniq_v2(values, iters)
  check_value("batch.v1", v1_result[1], c_result[1])
  check_value("batch.v2", v2_result[1], c_result[1])
  << "batch cleanup smoke: ok ([iters] results per path; full + partial batch)"

args = argv()
mode = args.size > 0 ? args[0] : "bench"

if mode == "check"
  run_correctness()
  run_batch_smoke()
  exit(0)

iters = args.size > 1 ? args[1].to_i : DEFAULT_ITERS
if iters <= 0
  << "iterations must be positive"
  exit(2)

parity = args.size > 2 ? args[2].to_i : 0
if parity != 0 && parity != 1
  << "sample parity must be 0 or 1"
  exit(2)

path = args.size > 3 ? args[3] : "v2"
if path != "v1" && path != "v2"
  << "candidate path must be v1 or v2"
  exit(2)

workload = args.size > 4 ? args[4] : "text-low"
valid = workload == "empty" || workload == "singleton" || workload == "small-text" || workload == "small-mixed" || workload == "text-low" || workload == "text-unique" || workload == "text-large" || workload == "numeric" || workload == "mixed" || workload == "typed"
if !valid
  << "invalid workload"
  exit(2)

values = workload_values(workload)
run_pair(values, WARMUP_ITERS, parity, path, workload, false)
run_pair(values, iters, parity, path, workload)
