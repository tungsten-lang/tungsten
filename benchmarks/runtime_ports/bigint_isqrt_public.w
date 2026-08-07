# True-public before/after benchmark for the BigInt#isqrt port (source shim
# over the runtime divide-and-conquer sqrt kernel). Run unchanged before
# (C IC) and after (BigInt#isqrt source body -> ccall bigint_isqrt_any).
#
# Strata by receiver width: one (1-limb; u128 fast path, inline result),
# four, sixteen, sixtyfour (D&C kernel, heap results consumed/freed).
# Results are always fresh (never alias the receiver).

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
  strata = ["one", "four", "sixteen", "sixtyfour"]
  s = 0
  while s < strata.size
    stratum = strata[s]
    values = build_corpus(stratum)
    i = 0
    while i < CORPUS_SIZE
      v = values[i]
      r = v.isqrt
      check_value("lower [stratum]/[i]", r * r <= v, true)
      check_value("upper [stratum]/[i]", (r + 1) * (r + 1) > v, true)
      check_value("nonneg [stratum]/[i]", r >= 0, true)
      i += 1
    s += 1
  # Exact perfect-square edge at a limb boundary
  root = 10 ** 154
  check_value("perfect.square", (root * root).isqrt.to_s(), root.to_s())
  check_value("perfect.minus_one", (root * root - 1).isqrt.to_s(), (root - 1).to_s())
  << "correctness: ok ([strata.size * CORPUS_SIZE * 3 + 2] root-bracketing checks; 1-64 limbs)"

-> time_isqrt(values, iters)
  checksum = 0
  i = 0
  started = thread_cpu_ns()
  while i < iters
    checksum += consume_low_byte(values[i & CORPUS_MASK].isqrt)
    i += 1
  [thread_cpu_ns() - started, checksum]

-> run_bench(stratum, iters, warmup)
  values = build_corpus(stratum)
  time_isqrt(values, warmup)
  result = time_isqrt(values, iters)
  << "RESULT|isqrt-[stratum]|[result[0]]|[iters]|[result[1]]"

args_v = argv()
mode = args_v.size() > 0 ? args_v[0] : "bench"
if mode == "check"
  run_correctness()
  exit(0)

if mode != "bench"
  << "mode must be check or bench"
  exit(2)

stratum = args_v.size() > 1 ? args_v[1] : "one"
iters = args_v.size() > 2 ? args_v[2].to_i : 1_000_000
warmup = args_v.size() > 3 ? args_v[3].to_i : iters / 10
if iters <= 0
  << "iterations must be positive"
  exit(2)
run_bench(stratum, iters, warmup)
