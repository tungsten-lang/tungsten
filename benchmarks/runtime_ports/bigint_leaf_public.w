# True-public before/after benchmark for the BigInt#prev/succ/next port.
# Receivers come from ordinary big decimal literals plus arithmetic, so the
# corpus takes the production literal-autoload path and the timed loops call
# the real public selectors. Run unchanged before (C IC installed) and after
# (IC rows retired, Int source bodies dispatch); compare per-stratum medians.
#
# Strata: one-limb (2^60 range), two-limb (2^100), four-limb (2^220), and
# the i48 demotion crossover (2^47 +/- 1), each with alternating signs.

CORPUS_SIZE = 16
CORPUS_MASK = CORPUS_SIZE - 1
DEFAULT_ITERS = 10_000_000
WARMUP_ITERS = 1_000_000

-> consume_low_byte(value)
  ccall("w_leafpub_consume_low_byte", value)

-> is_bigint(value)
  ccall("w_leafpub_is_bigint", value)

-> thread_cpu_ns
  ccall("w_leafpub_thread_cpu_ns")

-> fail_check(name, detail)
  << "FAIL [name]: [detail]"
  exit(1)

-> check_value(name, got, expected)
  if got != expected
    fail_check(name, "got=[got] expected=[expected]")

-> stratum_base(stratum)
  if stratum == "one"
    return 1152921504606846976
  if stratum == "two"
    return 1267650600228229401496703205376
  if stratum == "four"
    return 1684996666696914987166688442938726917102321526408785780068975640576
  if stratum == "crossover"
    return 140737488355328
  << "unknown stratum: [stratum]"
  exit(2)

-> build_corpus(stratum)
  base = stratum_base(stratum)
  values = []
  i = 0
  while i < CORPUS_SIZE
    step = stratum == "crossover" ? (i / 2) & 1 : i * 3
    value = base + step
    if (i & 1) == 1
      value = 0 - value
    values.push(value)
    i += 1
  values

-> run_correctness
  strata = ["one", "two", "four", "crossover"]
  s = 0
  while s < strata.size
    stratum = strata[s]
    values = build_corpus(stratum)
    i = 0
    while i < CORPUS_SIZE
      value = values[i]
      check_value("corpus bigint [stratum]/[i]", is_bigint(value), true)
      p = value.prev
      n = value.succ
      x = value.next
      check_value("prev inverse [stratum]/[i]", p + 1, value)
      check_value("succ inverse [stratum]/[i]", n - 1, value)
      check_value("next equals succ [stratum]/[i]", x, n)
      check_value("prev order [stratum]/[i]", p < value, true)
      check_value("succ order [stratum]/[i]", n > value, true)
      i += 1
    s += 1
  << "correctness: ok ([strata.size * CORPUS_SIZE * 6] checks; 4 strata, mixed signs)"

-> time_prev(values, iters)
  checksum = 0
  i = 0
  started = thread_cpu_ns()
  while i < iters
    checksum += consume_low_byte(values[i & CORPUS_MASK].prev)
    i += 1
  [thread_cpu_ns() - started, checksum]

-> time_succ(values, iters)
  checksum = 0
  i = 0
  started = thread_cpu_ns()
  while i < iters
    checksum += consume_low_byte(values[i & CORPUS_MASK].succ)
    i += 1
  [thread_cpu_ns() - started, checksum]

-> time_next(values, iters)
  checksum = 0
  i = 0
  started = thread_cpu_ns()
  while i < iters
    checksum += consume_low_byte(values[i & CORPUS_MASK].next)
    i += 1
  [thread_cpu_ns() - started, checksum]

-> run_bench(method, stratum, iters)
  values = build_corpus(stratum)
  if method == "prev"
    time_prev(values, WARMUP_ITERS)
    result = time_prev(values, iters)
  elsif method == "succ"
    time_succ(values, WARMUP_ITERS)
    result = time_succ(values, iters)
  elsif method == "next"
    time_next(values, WARMUP_ITERS)
    result = time_next(values, iters)
  else
    << "unknown method: [method]"
    exit(2)
  << "RESULT|[method]-[stratum]|[result[0]]|[iters]|[result[1]]"

args = argv()
mode = args.size() > 0 ? args[0] : "bench"
if mode == "check"
  run_correctness()
  exit(0)

if mode != "bench"
  << "mode must be check or bench"
  exit(2)

method = args.size() > 1 ? args[1] : "succ"
stratum = args.size() > 2 ? args[2] : "one"
iters = args.size() > 3 ? args[3].to_i : DEFAULT_ITERS
if iters <= 0
  << "iterations must be positive"
  exit(2)
run_bench(method, stratum, iters)
