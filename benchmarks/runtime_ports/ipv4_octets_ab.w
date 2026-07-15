# Strict benchmark-only A/B for moving IPv4#octets from its C IC into
# core/ipv4.w.  Public production dispatch remains untouched: `__c_octets`
# calls an exact benchmark copy of C, `__w_octets` is the uniquely named raw
# Tungsten candidate, and `octets` continues to exercise the current public IC.

use ../../core/array
use ../../core/ipv4

CORPUS_SIZE = 4096
CORPUS_MASK = CORPUS_SIZE - 1
BATCH_SIZE = 2048
DEFAULT_ITERS = 5_000_000
WARMUP_ITERS = 50_000

+ Array
  # The explicit Array hint gives compiled lowering a concrete view layout;
  # the tree walker routes the same receiver$field operation through its
  # narrow native-data-field bridge.
  -> __bench_flags
    receiver = self ## Array
    receiver$flags

  -> __bench_ebits
    receiver = self ## Array
    receiver$ebits

  -> __bench_start
    receiver = self ## Array
    receiver$start

+ IPv4
  -> __c_octets
    ccall("w_ref_ipv4_octets", self)

  # Optimized source candidate.  The array literal intentionally retains the
  # C body's polymorphic w64 representation and default capacity.  `$value`
  # is the packed IPv4 word in compiled code and is mirrored exactly by the
  # interpreter, so no storage ccall is needed.
  -> __w_octets
    bits = $value ## i64
    [(bits >> 36) & 0xFF,
     (bits >> 28) & 0xFF,
     (bits >> 20) & 0xFF,
     (bits >> 12) & 0xFF]

-> fail_check(path, case_index, got, expected)
  << "FAIL [path] case=[case_index] got=[got] expected=[expected]"
  exit(1)

-> check_value(path, case_index, got, expected)
  if got != expected
    fail_check(path, case_index, got, expected)

-> check_octets(path, case_index, got, expected)
  if !got.is_a?(Array)
    fail_check(path + ".class", case_index, got.class_name, "Array")
  check_value(path + ".size", case_index, got.size, 4)
  check_value(path + ".cap", case_index, got.cap, 8)
  check_value(path + ".flags", case_index, got.__bench_flags, 2)
  check_value(path + ".ebits", case_index, got.__bench_ebits, 65)
  check_value(path + ".start", case_index, got.__bench_start, 0)
  i = 0
  while i < 4
    check_value(path + ".item", case_index * 4 + i, got[i], expected[i])
    i += 1

-> fixed_cases
  [[IPv4.of(0, 0, 0, 0), [0, 0, 0, 0]],
   [IPv4.of(255, 255, 255, 255), [255, 255, 255, 255]],
   [IPv4.of(1, 2, 3, 4, 0), [1, 2, 3, 4]],
   [IPv4.of(128, 0, 255, 1, 8), [128, 0, 255, 1]],
   [IPv4.of(10, 172, 16, 254, 16), [10, 172, 16, 254]],
   [IPv4.of(169, 254, 128, 127, 24), [169, 254, 128, 127]],
   [IPv4.of(224, 1, 2, 255, 31), [224, 1, 2, 255]],
   [IPv4.of(240, 0, 0, 1, 32), [240, 0, 0, 1]]]

-> make_ip(address, prefix)
  IPv4.of((address >> 24) & 0xFF,
          (address >> 16) & 0xFF,
          (address >> 8) & 0xFF,
          address & 0xFF,
          prefix)

-> build_corpus
  prefixes = [nil]
  prefix = 0
  while prefix <= 32
    prefixes.push(prefix)
    prefix += 1
  values = []
  state = 0x6D2B79F5
  i = 0
  while i < CORPUS_SIZE
    state = (state * 1_664_525 + 1_013_904_223) & 0xFFFFFFFF
    values.push(make_ip(state, prefixes[i % prefixes.size]))
    i += 1
  values

-> check_independent_results(ip, include_c)
  first = ip.__w_octets
  second = ip.__w_octets
  public_result = ip.octets
  check_value("independent W allocations", 0, wvalue_bits(first) == wvalue_bits(second), false)
  check_value("independent W/public allocations", 0, wvalue_bits(first) == wvalue_bits(public_result), false)
  if include_c
    c_result = ip.__c_octets
    check_value("independent C/W allocations", 0, wvalue_bits(c_result) == wvalue_bits(first), false)
  first[0] = 99
  first.push(77)
  check_value("mutated result size", 0, first.size, 5)
  check_value("mutated result capacity", 0, first.cap, 8)
  check_value("independent result contents", 0, second[0], 1)
  check_value("public result contents", 0, public_result[0], 1)
  check_value("receiver unchanged", 0, ip.__w_octets[0], 1)

-> run_interpreter_correctness
  cases = fixed_cases()
  i = 0
  while i < cases.size
    ip = cases[i][0]
    expected = cases[i][1]
    check_octets("W", i, ip.__w_octets, expected)
    check_octets("public", i, ip.octets, expected)
    i += 1
  check_independent_results(IPv4.of(1, 2, 3, 4, 24), false)
  << "interpreter correctness: ok ([cases.size] fixed addresses; values, w64 representation, capacity, and independence)"

-> run_compiled_correctness(values)
  cases = fixed_cases()
  i = 0
  while i < cases.size
    ip = cases[i][0]
    expected = cases[i][1]
    check_octets("C fixed", i, ip.__c_octets, expected)
    check_octets("W fixed", i, ip.__w_octets, expected)
    check_octets("public fixed", i, ip.octets, expected)
    i += 1

  i = 0
  while i < values.size
    ip = values[i]
    c_result = ip.__c_octets
    w_result = ip.__w_octets
    public_result = ip.octets
    check_octets("C corpus", i, c_result, c_result)
    check_octets("W/C corpus", i, w_result, c_result)
    check_octets("public/C corpus", i, public_result, c_result)
    i += 1

  check_independent_results(IPv4.of(1, 2, 3, 4, 24), true)
  << "compiled correctness: ok ([cases.size] fixed + [values.size] corpus addresses; C/W/public values, representation, capacity, and independence)"

-> release_batch(outputs, count)
  ccall("w_ref_ipv4_octets_release_batch", outputs, count)

-> time_octets_c(values, iters)
  outputs = w64[BATCH_SIZE]
  checksum = 0
  elapsed = 0
  completed = 0
  while completed < iters
    count = iters - completed
    if count > BATCH_SIZE
      count = BATCH_SIZE
    i = 0
    start_ns = clock()
    while i < count
      out = values[(completed + i) & CORPUS_MASK].__c_octets
      outputs[i] = out
      checksum += out[0] * 257 + out[3]
      i += 1
    elapsed += clock() - start_ns
    release_batch(outputs, count)
    completed += count
  [elapsed, checksum]

-> time_octets_unique(values, iters)
  outputs = w64[BATCH_SIZE]
  checksum = 0
  elapsed = 0
  completed = 0
  while completed < iters
    count = iters - completed
    if count > BATCH_SIZE
      count = BATCH_SIZE
    i = 0
    start_ns = clock()
    while i < count
      out = values[(completed + i) & CORPUS_MASK].__w_octets
      outputs[i] = out
      checksum += out[0] * 257 + out[3]
      i += 1
    elapsed += clock() - start_ns
    release_batch(outputs, count)
    completed += count
  [elapsed, checksum]

-> time_octets_public(values, iters)
  outputs = w64[BATCH_SIZE]
  checksum = 0
  elapsed = 0
  completed = 0
  while completed < iters
    count = iters - completed
    if count > BATCH_SIZE
      count = BATCH_SIZE
    i = 0
    start_ns = clock()
    while i < count
      out = values[(completed + i) & CORPUS_MASK].octets
      outputs[i] = out
      checksum += out[0] * 257 + out[3]
      i += 1
    elapsed += clock() - start_ns
    release_batch(outputs, count)
    completed += count
  [elapsed, checksum]

# Exercise one full cleanup batch plus a partial tail during CHECK_ONLY.  The
# elapsed values are intentionally ignored; this is a memory-safety/checksum
# smoke test, not a performance sample.
-> run_batch_smoke(values)
  smoke_iters = BATCH_SIZE + 17
  c_result = time_octets_c(values, smoke_iters)
  w_result = time_octets_unique(values, smoke_iters)
  public_result = time_octets_public(values, smoke_iters)
  check_value("batch smoke C/W checksum", 0, w_result[1], c_result[1])
  check_value("batch smoke C/public checksum", 0, public_result[1], c_result[1])
  << "batch cleanup smoke: ok ([smoke_iters] results per path; full + partial batch)"

-> time_candidate(values, iters, path)
  if path == "public"
    return time_octets_public(values, iters)
  time_octets_unique(values, iters)

-> combine_results(first, second)
  [first[0] + second[0], first[1] + second[1]]

-> report_result(path, c_result, w_result, iters)
  if c_result[1] != w_result[1]
    << "FAIL benchmark checksum octets.[path]: C=[c_result[1]] W=[w_result[1]]"
    exit(1)
  c_ns = c_result[0] * 1_000_000_000 / (iters * 2)
  w_ns = w_result[0] * 1_000_000_000 / (iters * 2)
  ratio = w_result[0] / c_result[0]
  << "RESULT|octets.[path]|[c_ns]|[w_ns]|[ratio]|[c_result[1]]"

# Each process runs C/W/W/C or W/C/C/W.  Summing both legs per implementation
# cancels first-order drift more strongly than a single C/W alternation.
-> run_pair(values, iters, parity, path, emit = true)
  if parity == 0
    c_first = time_octets_c(values, iters)
    w_first = time_candidate(values, iters, path)
    w_second = time_candidate(values, iters, path)
    c_second = time_octets_c(values, iters)
  else
    w_first = time_candidate(values, iters, path)
    c_first = time_octets_c(values, iters)
    c_second = time_octets_c(values, iters)
    w_second = time_candidate(values, iters, path)
  c_result = combine_results(c_first, c_second)
  w_result = combine_results(w_first, w_second)
  if emit
    report_result(path, c_result, w_result, iters)

-> run_bench(values, iters, parity, path)
  run_pair(values, WARMUP_ITERS, parity, path, false)
  run_pair(values, iters, parity, path)

args = argv()
mode = args.size > 0 ? args[0] : "bench"

if mode == "interpreter-check"
  run_interpreter_correctness()
  exit(0)

values = build_corpus()
if mode == "check"
  run_compiled_correctness(values)
  run_batch_smoke(values)
  exit(0)

iters = DEFAULT_ITERS
if args.size > 1
  iters = args[1].to_i
if iters <= 0
  << "iterations must be positive"
  exit(2)

parity = 0
if args.size > 2
  if args[2] != "0" && args[2] != "1"
    << "sample parity must be 0 (C/W/W/C) or 1 (W/C/C/W)"
    exit(2)
  parity = args[2].to_i

path = args.size > 3 ? args[3] : "unique"
if path != "unique" && path != "public"
  << "candidate path must be unique or public"
  exit(2)

run_bench(values, iters, parity, path)
