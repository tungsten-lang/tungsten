# True-public before/after benchmark for the BigInt#prime? port (source
# shim over the runtime screen/Mersenne/Proth/BPSW policy). Run unchanged
# before (C IC) and after (source shim -> ccall w_bigint_prime_q).
#
# Rows ride the handler's distinct cost paths:
#   one-prime — 2^61-1, deterministic u64 test on a 1-limb heap receiver
#   one-comp  — distinct odd 1-limb composites (small-factor screens)
#   semiprime — (2^61-1)(2^89-1): no small factors, fails a real base test
#   big-prime — 2^255-19: full BPSW accept on 4 limbs
#   mersenne  — 2^127-1: exact Lucas-Lehmer proof path
# Results are Bools; nothing allocates per call, nothing is freed.

CORPUS_SIZE = 8
CORPUS_MASK = CORPUS_SIZE - 1

-> thread_cpu_ns
  ccall("w_leafpub_thread_cpu_ns")

-> fail_check(name, detail)
  << "FAIL [name]: [detail]"
  exit(1)

-> check_value(name, got, expected)
  if got != expected
    fail_check(name, "got=[got] expected=[expected]")

-> build_corpus(stratum)
  values = []
  i = 0
  while i < CORPUS_SIZE
    if stratum == "one-prime"
      values.push(2 ** 61 - 1)
    elsif stratum == "one-comp"
      values.push(1152921504606846977 + i * 2)
    elsif stratum == "semiprime"
      values.push((2 ** 61 - 1) * (2 ** 89 - 1))
    elsif stratum == "big-prime"
      values.push(2 ** 255 - 19)
    else
      values.push(2 ** 127 - 1)
    i += 1
  values

-> expected_result(stratum)
  stratum == "one-prime" || stratum == "big-prime" || stratum == "mersenne"

-> run_correctness
  strata = ["one-prime", "one-comp", "semiprime", "big-prime", "mersenne"]
  s = 0
  while s < strata.size
    stratum = strata[s]
    values = build_corpus(stratum)
    i = 0
    while i < CORPUS_SIZE
      got = values[i].prime?
      if stratum == "one-comp"
        check_value("comp [stratum]/[i]", got, false)
      else
        check_value("fixed [stratum]/[i]", got, expected_result(stratum))
      i += 1
    s += 1
  << "correctness: ok (5 cost-path strata; known primes, composites, Mersenne proof)"

-> time_prime(values, iters)
  checksum = 0
  i = 0
  started = thread_cpu_ns()
  while i < iters
    checksum += values[i & CORPUS_MASK].prime? ? 1 : 0
    i += 1
  [thread_cpu_ns() - started, checksum]

-> run_bench(stratum, iters, warmup)
  values = build_corpus(stratum)
  time_prime(values, warmup)
  result = time_prime(values, iters)
  << "RESULT|prime-[stratum]|[result[0]]|[iters]|[result[1]]"

args_v = argv()
mode = args_v.size() > 0 ? args_v[0] : "bench"
if mode == "check"
  run_correctness()
  exit(0)

if mode != "bench"
  << "mode must be check or bench"
  exit(2)

stratum = args_v.size() > 1 ? args_v[1] : "one-prime"
iters = args_v.size() > 2 ? args_v[2].to_i : 100_000
warmup = args_v.size() > 3 ? args_v[3].to_i : iters / 10
if iters <= 0
  << "iterations must be positive"
  exit(2)
run_bench(stratum, iters, warmup)
