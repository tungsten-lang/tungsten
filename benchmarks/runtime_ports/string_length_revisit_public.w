# True public-dispatch benchmark for String/Symbol#size/#length. Deliberately
# no `use`: baseline must reach the native IC, while each candidate compiler
# must schedule and register core/string_native for unknown C-produced values.

CASE_COUNT = 17
CORPUS_SIZE = 16
CORPUS_MASK = CORPUS_SIZE - 1
DEFAULT_ITERS = 20_000_000
DEFAULT_WARMUP = 500_000

-> fixture(index)
  ccall("w_strlen_fixture", index)

-> fail_check(name, detail)
  << "FAIL [name]: [detail]"
  exit(1)

-> check(name, got, expected)
  if got != expected
    fail_check(name, "got=[got] expected=[expected]")

-> check_bits(name, got, expected)
  check(name, wvalue_bits(got), wvalue_bits(expected))

-> check_case(index, expected_modes)
  value = fixture(index)
  expected = ccall("w_strlen_expected", index)
  check("case.[index].factory", ccall("w_strlen_fixture_valid", value, index), true)
  check("case.[index].mode", ccall("w_strlen_storage_mode", value), expected_modes[index])
  check("case.[index].symbol", ccall("w_strlen_is_symbol", value), index >= 9)
  # Keep the public call first for the stored rope case. The C reference also
  # flattens, so calling it first would silently turn this into a warmed test.
  size_result = value.size
  reference = ccall("w_strlen_reference", value)
  check("case.[index].reference", reference, expected)

  length_result = value.length
  check("case.[index].size", size_result, reference)
  check("case.[index].length", length_result, reference)
  check_bits("case.[index].size.bits", size_result, reference)
  check_bits("case.[index].length.bits", length_result, reference)

  # The former arity -1 wrapper ignored every positional argument. Source
  # name-only fallback must retain that surface for both aliases and types.
  check_bits("case.[index].size.extra1", value.size(101), reference)
  check_bits("case.[index].size.extra4", value.size(1, 2, 3, 4), reference)
  check_bits("case.[index].length.extra1", value.length(101), reference)
  check_bits("case.[index].length.extra4", value.length(1, 2, 3, 4), reference)

  check("case.[index].stable", ccall("w_strlen_fixture_valid", value, index), true)

-> check_rope_first_and_warm
  # A rope is a generic object, not a 0xF9 WValue. Cached and generic runtime
  # dispatch must flatten it before computing the dispatch key/source $value.
  # Exercise size-first and length-first on distinct fresh nodes, then the
  # already-cached path on the same receiver. Raw receiver identity is stable;
  # only WRope.flat is populated.
  rope = ccall("w_strlen_fresh_rope")
  before = wvalue_bits(rope)
  check("rope.size-first.mode", ccall("w_strlen_storage_mode", rope), 8)
  check("rope.size-first.cache-before", ccall("w_strlen_rope_flat_cached", rope), false)
  check("rope.size-first.result", rope.size, 81)
  check("rope.size-first.identity", wvalue_bits(rope), before)
  check("rope.size-first.cache-after", ccall("w_strlen_rope_flat_cached", rope), true)
  check("rope.size-warm.result", rope.size, 81)
  check("rope.size-warm.cache", ccall("w_strlen_rope_flat_cached", rope), true)

  rope = ccall("w_strlen_fresh_rope")
  before = wvalue_bits(rope)
  check("rope.length-first.cache-before", ccall("w_strlen_rope_flat_cached", rope), false)
  check("rope.length-first.result", rope.length, 81)
  check("rope.length-first.identity", wvalue_bits(rope), before)
  check("rope.length-first.cache-after", ccall("w_strlen_rope_flat_cached", rope), true)
  check("rope.length-warm.result", rope.length, 81)

-> check_compiled_blocks
  # Compiled trailing blocks on no-block methods iterate the Integer result.
  # Pin both aliases and both runtime types; tree-walker behavior is covered by
  # the separate interpreter fixture because it intentionally passes/ignores.
  text = fixture(1)
  size_hits = 0
  size_return = text.size -> size_hits += 1
  check("block.string.size.hits", size_hits, 5)
  check("block.string.size.return", size_return, nil)
  length_hits = 0
  length_return = text.length -> length_hits += 1
  check("block.string.length.hits", length_hits, 5)
  check("block.string.length.return", length_return, nil)

  symbol = fixture(10)
  size_hits = 0
  size_return = symbol.size -> size_hits += 1
  check("block.symbol.size.hits", size_hits, 3)
  check("block.symbol.size.return", size_return, nil)
  length_hits = 0
  length_return = symbol.length -> length_hits += 1
  check("block.symbol.length.hits", length_hits, 3)
  check("block.symbol.length.return", length_return, nil)

-> run_correctness
  check("fixture count", ccall("w_strlen_case_count"), CASE_COUNT)
  expected_modes = [0, 5, 2, 3, 6, 6, 7, 7, 8,
                    0, 3, 3, 6, 6, 7, 7, 7]
  i = 0
  while i < CASE_COUNT
    check_case(i, expected_modes)
    i += 1
  check_rope_first_and_warm()
  check_compiled_blocks()
  << "correctness: ok (17 String/Symbol representations; byte counts, UTF-8, embedded NUL, rope first/warm dispatch, extras, blocks, Integer bits, and stability)"

-> corpus(indexes)
  values = []
  i = 0
  while i < CORPUS_SIZE
    values.push(fixture(indexes[i]))
    i += 1
  values

-> corpus_for(stratum)
  if stratum.ends_with?(".inline")
    if stratum.starts_with?("string.")
      return corpus([0, 1, 2, 3, 1, 2, 3, 0, 3, 2, 1, 0, 1, 3, 2, 1])
    return corpus([9, 10, 11, 10, 11, 9, 10, 11, 10, 9, 11, 10, 9, 10, 11, 10])
  if stratum.ends_with?(".slab")
    if stratum.starts_with?("string.")
      return corpus([4, 5, 4, 5, 5, 4, 5, 4, 4, 5, 4, 5, 5, 4, 5, 4])
    return corpus([12, 13, 12, 13, 13, 12, 13, 12, 12, 13, 12, 13, 13, 12, 13, 12])
  if stratum.ends_with?(".heap")
    if stratum.starts_with?("string.")
      return corpus([6, 7, 6, 7, 7, 6, 7, 6, 6, 7, 6, 7, 7, 6, 7, 6])
    return corpus([14, 15, 16, 14, 15, 16, 14, 15, 16, 15, 14, 16, 14, 15, 16, 14])
  if stratum.ends_with?(".nul")
    if stratum.starts_with?("string.")
      return corpus([3, 7, 3, 7, 7, 3, 7, 3, 3, 7, 3, 7, 7, 3, 7, 3])
    return corpus([11, 15, 11, 15, 15, 11, 15, 11, 11, 15, 11, 15, 15, 11, 15, 11])
  if stratum.ends_with?(".rope-warm") && stratum.starts_with?("string.")
    return corpus([8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8])
  fail_check("stratum", "unknown [stratum]")

# Three arguments keep these clock-bearing functions outside the compiler's
# <=2-argument pure-function memoization rule. Each method has an independent
# body and timing checksum so no result is hidden behind a dynamic name call.
-> time_string_size(values, iters, run_id)
  checksum = 0
  i = 0
  started = ccall_nobox("w_strlen_thread_cpu_ns") ## i64
  while i < iters
    checksum += values[i & CORPUS_MASK].size
    i += 1
  [ccall_nobox("w_strlen_thread_cpu_ns") - started, checksum]

-> time_string_length(values, iters, run_id)
  checksum = 0
  i = 0
  started = ccall_nobox("w_strlen_thread_cpu_ns") ## i64
  while i < iters
    checksum += values[i & CORPUS_MASK].length
    i += 1
  [ccall_nobox("w_strlen_thread_cpu_ns") - started, checksum]

-> time_symbol_size(values, iters, run_id)
  checksum = 0
  i = 0
  started = ccall_nobox("w_strlen_thread_cpu_ns") ## i64
  while i < iters
    checksum += values[i & CORPUS_MASK].size
    i += 1
  [ccall_nobox("w_strlen_thread_cpu_ns") - started, checksum]

-> time_symbol_length(values, iters, run_id)
  checksum = 0
  i = 0
  started = ccall_nobox("w_strlen_thread_cpu_ns") ## i64
  while i < iters
    checksum += values[i & CORPUS_MASK].length
    i += 1
  [ccall_nobox("w_strlen_thread_cpu_ns") - started, checksum]

-> timed(stratum, values, iters, run_id)
  if stratum.starts_with?("string.size.")
    return time_string_size(values, iters, run_id)
  if stratum.starts_with?("string.length.")
    return time_string_length(values, iters, run_id)
  if stratum.starts_with?("symbol.size.")
    return time_symbol_size(values, iters, run_id)
  if stratum.starts_with?("symbol.length.")
    return time_symbol_length(values, iters, run_id)
  fail_check("timing", "unknown [stratum]")

-> run_bench(stratum, iters, warmup)
  values = corpus_for(stratum)
  timed(stratum, values, warmup, 0)
  result = timed(stratum, values, iters, 1)
  << "RESULT|[stratum]|[result[0]]|[iters]|[result[1]]"

args = argv()
mode = args.size() > 0 ? args[0] : "check"
if mode == "check"
  run_correctness()
  exit(0)
if mode != "bench" || args.size() < 4
  << "usage: string-length-revisit-public bench STRATUM ITERS WARMUP"
  exit(2)
run_bench(args[1], args[2].to_i, args[3].to_i)
