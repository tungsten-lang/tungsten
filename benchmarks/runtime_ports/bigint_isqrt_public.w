# Same-binary benchmark for BigInt#isqrt. The W lane calls the true public
# method; the C lane calls a benchmark-only method over the retained runtime
# boundary. Both pay source dispatch, isolating the square-root implementation.
#
# Strata by receiver width: one/one-high/one-square (1-limb; inline result),
# four, sixteen, sixtyfour (D&C kernel, heap results consumed/freed).
# Results are always fresh (never alias the receiver).

+ BigInt
  -> __c_isqrt_oracle
    ccall("bigint_isqrt_any", self)

CORPUS_SIZE = 8
CORPUS_MASK = CORPUS_SIZE - 1

-> consume_low_byte(value)
  ccall("w_leafpub_consume_low_byte", value)

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
    return 1125899906842624
  if stratum == "one-high"
    return "18446744073708551615".to_i
  if stratum == "one-square"
    root = 4294967279
    return root * root - 4
  if stratum == "four"
    return 10 ** 76 + 3
  if stratum == "sixteen"
    return 10 ** 307 + 9
  if stratum == "sixtyfour"
    return 10 ** 1232 + 11
  << "unknown stratum: [stratum]"
  exit(2)

-> build_corpus(stratum)
  base = stratum_base(stratum)
  values = []
  i = 0
  while i < CORPUS_SIZE
    values.push(base + i * 12345)
    i += 1
  values

-> run_correctness
  strata = ["one", "one-high", "one-square", "four", "sixteen", "sixtyfour"]
  s = 0
  while s < strata.size
    stratum = strata[s]
    values = build_corpus(stratum)
    i = 0
    while i < CORPUS_SIZE
      v = values[i]
      r = v.isqrt
      check_value("C differential [stratum]/[i]", r.to_s(), v.__c_isqrt_oracle.to_s())
      check_value("lower [stratum]/[i]", r * r <= v, true)
      check_value("upper [stratum]/[i]", (r + 1) * (r + 1) > v, true)
      check_value("nonneg [stratum]/[i]", r >= 0, true)
      i += 1
    s += 1
  # Exact perfect-square edge at a limb boundary
  root = 10 ** 154
  check_value("perfect.square", (root * root).isqrt.to_s(), root.to_s())
  check_value("perfect.minus_one", (root * root - 1).isqrt.to_s(), (root - 1).to_s())
  # Deterministic full-word differential sweep. Force bit 63 so every value
  # is a normalized one-limb BigInt and exercises the native source arm.
  state = 88172645463325252 ## u64
  random_checks = 0
  while random_checks < 2048
    state = state ^ (state >> 12) ## u64
    state = state ^ (state << 25) ## u64
    state = state ^ (state >> 27) ## u64
    state = state * 2685821657736338717 ## u64
    magnitude = state | (9223372036854775808 ## u64)
    value = ccall("w_u64", magnitude)
    check_value("random C differential [random_checks]", value.isqrt.to_s(), value.__c_isqrt_oracle.to_s())
    random_checks += 1
  << "correctness: ok ([strata.size * CORPUS_SIZE + random_checks] C differentials + root-bracketing checks; 1-64 limbs)"

-> time_isqrt_w(values, iters)
  checksum = 0
  i = 0
  started = thread_cpu_ns()
  while i < iters
    checksum += consume_low_byte(values[i & CORPUS_MASK].isqrt)
    i += 1
  [thread_cpu_ns() - started, checksum]

-> time_isqrt_c(values, iters)
  checksum = 0
  i = 0
  started = thread_cpu_ns()
  while i < iters
    checksum += consume_low_byte(values[i & CORPUS_MASK].__c_isqrt_oracle)
    i += 1
  [thread_cpu_ns() - started, checksum]

-> run_bench(lane, stratum, iters, warmup)
  values = build_corpus(stratum)
  result = nil
  if lane == "c"
    time_isqrt_c(values, warmup)
    result = time_isqrt_c(values, iters)
  else
    time_isqrt_w(values, warmup)
    result = time_isqrt_w(values, iters)
  << "RESULT|isqrt-[stratum]|[result[0]]|[iters]|[result[1]]"

args_v = argv()
mode = args_v.size() > 0 ? args_v[0] : "bench"
if mode == "check"
  run_correctness()
  exit(0)

if mode != "bench"
  << "mode must be check or bench"
  exit(2)

lane = args_v.size() > 1 ? args_v[1] : "w"
stratum = args_v.size() > 2 ? args_v[2] : "one"
iters = args_v.size() > 3 ? args_v[3].to_i : 1_000_000
warmup = args_v.size() > 4 ? args_v[4].to_i : iters / 10
if iters <= 0
  << "iterations must be positive"
  exit(2)
run_bench(lane, stratum, iters, warmup)
