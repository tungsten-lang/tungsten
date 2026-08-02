# Direct C-reference/native-source A/B for the BigInt sign-mutation kernels.
# Both legs are source-dispatched under unique names; only the operation body
# differs. Production public dispatch is measured separately.

CASE_COUNT = 16
CORPUS_SIZE = 16
CORPUS_MASK = CORPUS_SIZE - 1

+ Int

+ BigInt < Int
  - data
    u8 _type
    u8[3] _pad
    i32 length
    u32 capacity
    u32 _pad2
    u64 limb0

  -> __c_neg_bang
    ccall("w_bigbang_c_neg", self)

  -> __c_abs_bang
    ccall("w_bigbang_c_abs", self)

  -> __w_neg_bang
    n = $length ## i64
    $length = 0 - n
    self

  -> __w_abs_bang
    n = $length ## i64
    if n < 0
      $length = 0 - n
    self

-> fixture(index)
  ccall("w_bigbang_fixture", index)

-> signed_size(value)
  ccall("w_bigbang_signed_size", value)

-> set_size(value, size)
  ccall("w_bigbang_set_size", value, size)

-> observe(value)
  ccall("w_bigbang_observe", value)

-> check_value(name, got, expected)
  if got != expected
    << "FAIL [name]: got=[got] expected=[expected]"
    exit(1)

-> run_correctness
  check_value("fixture count", ccall("w_bigbang_case_count"), CASE_COUNT)
  i = 0
  while i < CASE_COUNT
    cvalue = fixture(i)
    wvalue = fixture(i)
    original_size = ccall("w_bigbang_expected_size", i)
    cbits = wvalue_bits(cvalue)
    wbits = wvalue_bits(wvalue)

    check_value("C neg return [i]", wvalue_bits(cvalue.__c_neg_bang), cbits)
    check_value("W neg return [i]", wvalue_bits(wvalue.__w_neg_bang), wbits)
    check_value("neg size C/W [i]", signed_size(cvalue), signed_size(wvalue))
    check_value("neg expected [i]", signed_size(wvalue), 0 - original_size)

    set_size(cvalue, 0 - original_size.abs)
    set_size(wvalue, 0 - original_size.abs)
    check_value("C abs return [i]", wvalue_bits(cvalue.__c_abs_bang), cbits)
    check_value("W abs return [i]", wvalue_bits(wvalue.__w_abs_bang), wbits)
    check_value("abs size C/W [i]", signed_size(cvalue), signed_size(wvalue))
    check_value("abs expected [i]", signed_size(wvalue), original_size.abs)
    i += 1
  << "correctness: ok ([CASE_COUNT * 8] C/source identity and sign checks)"

-> build_corpus
  values = []
  i = 0
  while i < CORPUS_SIZE
    value = fixture(i)
    set_size(value, signed_size(value).abs)
    values.push(value)
    i += 1
  values

-> reset_positive(values)
  i = 0
  while i < CORPUS_SIZE
    set_size(values[i], signed_size(values[i]).abs)
    i += 1

-> time_neg_c(values, iters, run_id)
  checksum = 0
  i = 0
  started = ccall("w_bigbang_thread_cpu_ns")
  while i < iters
    value = values[i & CORPUS_MASK]
    value.__c_neg_bang
    checksum += observe(value)
    i += 1
  [ccall("w_bigbang_thread_cpu_ns") - started, checksum]

-> time_neg_w(values, iters, run_id)
  checksum = 0
  i = 0
  started = ccall("w_bigbang_thread_cpu_ns")
  while i < iters
    value = values[i & CORPUS_MASK]
    value.__w_neg_bang
    checksum += observe(value)
    i += 1
  [ccall("w_bigbang_thread_cpu_ns") - started, checksum]

-> time_abs_positive_c(values, iters, run_id)
  checksum = 0
  i = 0
  started = ccall("w_bigbang_thread_cpu_ns")
  while i < iters
    value = values[i & CORPUS_MASK]
    value.__c_abs_bang
    checksum += observe(value)
    i += 1
  [ccall("w_bigbang_thread_cpu_ns") - started, checksum]

-> time_abs_positive_w(values, iters, run_id)
  checksum = 0
  i = 0
  started = ccall("w_bigbang_thread_cpu_ns")
  while i < iters
    value = values[i & CORPUS_MASK]
    value.__w_abs_bang
    checksum += observe(value)
    i += 1
  [ccall("w_bigbang_thread_cpu_ns") - started, checksum]

-> time_pair_c(values, iters, run_id)
  checksum = 0
  i = 0
  started = ccall("w_bigbang_thread_cpu_ns")
  while i < iters
    value = values[i & CORPUS_MASK]
    value.__c_neg_bang
    value.__c_abs_bang
    checksum += observe(value)
    i += 1
  [ccall("w_bigbang_thread_cpu_ns") - started, checksum]

-> time_pair_w(values, iters, run_id)
  checksum = 0
  i = 0
  started = ccall("w_bigbang_thread_cpu_ns")
  while i < iters
    value = values[i & CORPUS_MASK]
    value.__w_neg_bang
    value.__w_abs_bang
    checksum += observe(value)
    i += 1
  [ccall("w_bigbang_thread_cpu_ns") - started, checksum]

-> timed(name, leg, values, iters, run_id)
  if name == "neg"
    return leg == "c" ? time_neg_c(values, iters, run_id) : time_neg_w(values, iters, run_id)
  if name == "abs-positive"
    return leg == "c" ? time_abs_positive_c(values, iters, run_id) : time_abs_positive_w(values, iters, run_id)
  if name == "neg-abs-pair"
    return leg == "c" ? time_pair_c(values, iters, run_id) : time_pair_w(values, iters, run_id)
  << "unknown benchmark: [name]"
  exit(2)

-> run_bench(name, iters, parity)
  values = build_corpus()
  first = parity == 0 ? "c" : "w"
  second = parity == 0 ? "w" : "c"

  reset_positive(values)
  a = timed(name, first, values, iters, 1)
  reset_positive(values)
  b = timed(name, second, values, iters, 2)
  reset_positive(values)
  c = timed(name, second, values, iters, 3)
  reset_positive(values)
  d = timed(name, first, values, iters, 4)

  if first == "c"
    c_elapsed = a[0] + d[0]
    c_checksum = a[1] + d[1]
    w_elapsed = b[0] + c[0]
    w_checksum = b[1] + c[1]
  else
    w_elapsed = a[0] + d[0]
    w_checksum = a[1] + d[1]
    c_elapsed = b[0] + c[0]
    c_checksum = b[1] + c[1]

  check_value("benchmark checksum [name]", w_checksum, c_checksum)
  calls = name == "neg-abs-pair" ? iters * 4 : iters * 2
  << "RESULT|[name]|[c_elapsed]|[w_elapsed]|[calls]|[c_checksum]"

args = argv()
mode = args.size() > 0 ? args[0] : "bench"
if mode == "check"
  run_correctness()
  exit(0)

name = args.size() > 1 ? args[1] : "neg"
iters = args.size() > 2 ? args[2].to_i : 20_000_000
parity = args.size() > 3 ? args[3].to_i : 0
if iters <= 0 || !(parity in (0 1))
  << "usage: bench <name> <positive-iters> <0|1>"
  exit(2)
run_bench(name, iters, parity)
