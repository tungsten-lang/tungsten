# Function-level A/B benchmark for Array leaf methods that still live in the
# runtime IC table. The __c_* methods call benchmark-only mirrors of the
# current C handlers; __w_* methods are candidate native Tungsten bodies over
# Array's WArray view. Production methods and runtime registrations are not
# changed by this benchmark.

use ../../core/array

CORPUS_SIZE = 32
CORPUS_MASK = CORPUS_SIZE - 1
DEFAULT_ITERS = 10_000_000
WARMUP_ITERS = 50_000

+ Array
  -> __c_size
    ccall("w_ref_array_leaf_size", self)

  -> __c_cap
    ccall("w_ref_array_leaf_cap", self)

  -> __c_empty?
    ccall("w_ref_array_leaf_empty_p", self)

  -> __c_first
    ccall("w_ref_array_leaf_first", self)

  -> __c_last
    ccall("w_ref_array_leaf_last", self)

  # Candidate source implementations. $size/$cap are direct WArray view-field
  # loads; self[index] retains the existing ebits-aware Array indexing path.
  -> __w_size
    $size

  -> __w_cap
    $cap

  -> __w_empty?
    n = $size ## i64
    n == 0

  -> __w_first
    n = $size ## i64
    if n == 0
      return nil
    self[0]

  -> __w_last
    n = $size ## i64
    if n == 0
      return nil
    self[n - 1]

-> fail_check(name, case_index, got, expected)
  << "FAIL [name] case=[case_index] got=[got] expected=[expected]"
  exit(1)

-> check_value(name, case_index, got, expected)
  if got != expected
    fail_check(name, case_index, got, expected)

-> check_case(array, case_index)
  check_value("size", case_index, array.__w_size, array.__c_size)
  check_value("cap", case_index, array.__w_cap, array.__c_cap)
  check_value("empty?", case_index, array.__w_empty?, array.__c_empty?)
  check_value("first", case_index, array.__w_first, array.__c_first)
  check_value("last", case_index, array.__w_last, array.__c_last)

-> run_correctness
  cases = []

  # Polymorphic WValue arrays: empty, singleton, mixed payload, shifted start,
  # and a grown capacity.
  cases.push([])
  cases.push([42])
  cases.push([nil, false, "middle", 99])
  shifted = [10, 20, 30, 40]
  shifted.shift
  cases.push(shifted)
  grown = []
  i = 0
  while i < 20
    grown.push(i * 3 - 7)
    i += 1
  cases.push(grown)

  # Empty typed arrays retain their default backing capacity while size is 0.
  cases.push(bool[0])
  cases.push(u1[0])
  cases.push(u4[0])
  cases.push(i4[0])
  cases.push(u8[0])
  cases.push(i8[0])
  cases.push(u16[0])
  cases.push(i16[0])
  cases.push(u32[0])
  cases.push(i32[0])
  cases.push(u64[0])
  cases.push(i64[0])
  cases.push(f32[0])
  cases.push(f64[0])
  cases.push(bf16[0])
  cases.push(w64[0])

  bools = bool[3]
  bools[0] = true
  bools[1] = false
  bools[2] = true
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

  # i32 currently shares the runtime ebits=32 representation with u32. The
  # benchmark intentionally checks the current public decoding semantics.
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

  wvalues = w64[3]
  wvalues[0] = "first"
  wvalues[1] = nil
  wvalues[2] = "last"
  cases.push(wvalues)

  i = 0
  while i < cases.size
    check_case(cases[i], i)
    i += 1

  << "correctness: ok ([cases.size * 5] exact C/W comparisons; empty/nonempty, shifted, grown, and typed arrays)"

# Timed corpus: eight groups of empty/nonempty polymorphic and typed arrays.
# Keeping the outer corpus at 32 permits a mask instead of modulo in hot loops.
-> build_corpus
  arrays = []
  i = 0
  while i < 8
    arrays.push([])

    plain = [i + 1, i + 11, i + 21, i + 31]
    if (i & 1) == 1
      plain.shift
    arrays.push(plain)

    bytes = u8[4]
    bytes[0] = i + 2
    bytes[1] = i + 12
    bytes[2] = i + 22
    bytes[3] = i + 32
    if (i & 1) == 1
      bytes.shift
    arrays.push(bytes)

    ints = i64[4]
    ints[0] = i + 3
    ints[1] = i + 13
    ints[2] = i + 23
    ints[3] = i + 33
    if (i & 1) == 1
      ints.shift
    arrays.push(ints)
    i += 1
  arrays

-> finish_timing(start_ns, checksum)
  [clock() - start_ns, checksum]

-> time_size_c(arrays, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += arrays[i & CORPUS_MASK].__c_size
    i += 1
  finish_timing(start_ns, checksum)

-> time_size_w(arrays, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += arrays[i & CORPUS_MASK].__w_size
    i += 1
  finish_timing(start_ns, checksum)

-> time_cap_c(arrays, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += arrays[i & CORPUS_MASK].__c_cap
    i += 1
  finish_timing(start_ns, checksum)

-> time_cap_w(arrays, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += arrays[i & CORPUS_MASK].__w_cap
    i += 1
  finish_timing(start_ns, checksum)

-> time_empty_c(arrays, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += arrays[i & CORPUS_MASK].__c_empty? ? 1 : 0
    i += 1
  finish_timing(start_ns, checksum)

-> time_empty_w(arrays, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += arrays[i & CORPUS_MASK].__w_empty? ? 1 : 0
    i += 1
  finish_timing(start_ns, checksum)

-> time_first_c(arrays, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    bits = wvalue_bits(arrays[i & CORPUS_MASK].__c_first) ## i64
    checksum += bits & 0xFF
    i += 1
  finish_timing(start_ns, checksum)

-> time_first_w(arrays, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    bits = wvalue_bits(arrays[i & CORPUS_MASK].__w_first) ## i64
    checksum += bits & 0xFF
    i += 1
  finish_timing(start_ns, checksum)

-> time_last_c(arrays, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    bits = wvalue_bits(arrays[i & CORPUS_MASK].__c_last) ## i64
    checksum += bits & 0xFF
    i += 1
  finish_timing(start_ns, checksum)

-> time_last_w(arrays, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    bits = wvalue_bits(arrays[i & CORPUS_MASK].__w_last) ## i64
    checksum += bits & 0xFF
    i += 1
  finish_timing(start_ns, checksum)

-> report_result(name, c_result, w_result, iters)
  if c_result[1] != w_result[1]
    << "FAIL benchmark checksum [name]: C=[c_result[1]] W=[w_result[1]]"
    exit(1)
  c_ns = c_result[0] * 1_000_000_000 / iters
  w_ns = w_result[0] * 1_000_000_000 / iters
  ratio = w_result[0] / c_result[0]
  << "RESULT|[name]|[c_ns]|[w_ns]|[ratio]|[c_result[1]]"

-> run_pair(arrays, iters, parity, name, emit = true)
  if name == "size"
    if parity == 0
      c_result = time_size_c(arrays, iters)
      w_result = time_size_w(arrays, iters)
    else
      w_result = time_size_w(arrays, iters)
      c_result = time_size_c(arrays, iters)
  elsif name == "cap"
    if parity == 0
      c_result = time_cap_c(arrays, iters)
      w_result = time_cap_w(arrays, iters)
    else
      w_result = time_cap_w(arrays, iters)
      c_result = time_cap_c(arrays, iters)
  elsif name == "empty?"
    if parity == 0
      c_result = time_empty_c(arrays, iters)
      w_result = time_empty_w(arrays, iters)
    else
      w_result = time_empty_w(arrays, iters)
      c_result = time_empty_c(arrays, iters)
  elsif name == "first"
    if parity == 0
      c_result = time_first_c(arrays, iters)
      w_result = time_first_w(arrays, iters)
    else
      w_result = time_first_w(arrays, iters)
      c_result = time_first_c(arrays, iters)
  else
    if parity == 0
      c_result = time_last_c(arrays, iters)
      w_result = time_last_w(arrays, iters)
    else
      w_result = time_last_w(arrays, iters)
      c_result = time_last_c(arrays, iters)
  if emit
    report_result(name, c_result, w_result, iters)

-> run_bench(arrays, iters, parity, only = nil)
  names = ["size", "cap", "empty?", "first", "last"]
  i = 0
  while i < names.size
    if only == nil || only == "" || only == names[i]
      run_pair(arrays, WARMUP_ITERS, parity, names[i], false)
    i += 1
  i = 0
  while i < names.size
    if only == nil || only == "" || only == names[i]
      run_pair(arrays, iters, parity, names[i])
    i += 1

args = argv()
mode = args.size > 0 ? args[0] : "bench"

if mode == "check"
  run_correctness()
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
    << "sample parity must be 0 (C/W) or 1 (W/C)"
    exit(2)
  parity = args[2].to_i

only = args.size > 3 ? args[3] : nil
run_bench(build_corpus(), iters, parity, only)
