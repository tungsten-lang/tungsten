# Same-binary benchmark for the BigInt#prime? port. The W lane calls the public
# method; the C lane calls the retained runtime implementation through a
# benchmark-only method. Both pay source dispatch and return ordinary Bools,
# isolating the primality implementation without a raw-kernel shortcut.
#
# Rows ride the handler's distinct cost paths:
#   one-prime — 2^61-1, deterministic u64 test on a 1-limb heap receiver
#   one-comp  — distinct odd 1-limb composites (small-factor screens)
#   semiprime — (2^61-1)(2^89-1): no small factors, fails a real base test
#   big-prime — 2^255-19: full BPSW accept on 4 limbs
#   mersenne  — 2^127-1: exact Lucas-Lehmer proof path
# Results are Bools; nothing allocates per call, nothing is freed.

+ BigInt
  -> __c_prime_oracle
    ccall("w_bigint_prime_q", self)

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
  edge_values = [
    "140737488355329".to_i,
    "18446744073709551557".to_i,
    "18446744073709551615".to_i,
    0 - "140737488355329".to_i
  ]
  e = 0
  while e < edge_values.size
    x = edge_values[e]
    check_value("edge C differential [e]", x.prime?, x.__c_prime_oracle)
    e += 1

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

  # Deterministic full-word differential sweep. Force bit 63 so every value is
  # a normalized one-limb heap BigInt and spans the complete unsigned range.
  state = 88172645463325252 ## u64
  random_checks = 0
  while random_checks < 4096
    state = state ^ (state >> 12) ## u64
    state = state ^ (state << 25) ## u64
    state = state ^ (state >> 27) ## u64
    state = state * 2685821657736338717 ## u64
    magnitude = state | (9223372036854775808 ## u64)
    x = ccall("w_u64", magnitude)
    if (random_checks & 7) == 0
      x = 0 - x
    check_value("random C differential [random_checks]", x.prime?, x.__c_prime_oracle)
    random_checks += 1
  << "correctness: ok ([44 + random_checks] C differentials; 5 cost-path strata, full-word one-limb sweep)"

-> time_prime_w(values, iters)
  checksum = 0
  i = 0
  started = thread_cpu_ns()
  while i < iters
    checksum += values[i & CORPUS_MASK].prime? ? 1 : 0
    i += 1
  [thread_cpu_ns() - started, checksum]

-> time_prime_c(values, iters)
  checksum = 0
  i = 0
  started = thread_cpu_ns()
  while i < iters
    checksum += values[i & CORPUS_MASK].__c_prime_oracle ? 1 : 0
    i += 1
  [thread_cpu_ns() - started, checksum]

-> run_bench(lane, stratum, iters, warmup)
  values = build_corpus(stratum)
  result = nil
  if lane == "c"
    time_prime_c(values, warmup)
    result = time_prime_c(values, iters)
  else
    time_prime_w(values, warmup)
    result = time_prime_w(values, iters)
  << "RESULT|prime-[stratum]|[result[0]]|[iters]|[result[1]]"

args_v = argv()
mode = args_v.size() > 0 ? args_v[0] : "bench"
if mode == "check"
  run_correctness()
  exit(0)

if mode != "bench"
  << "mode must be check or bench"
  exit(2)

lane = args_v.size() > 1 ? args_v[1] : "w"
stratum = args_v.size() > 2 ? args_v[2] : "one-prime"
iters = args_v.size() > 3 ? args_v[3].to_i : 100_000
warmup = args_v.size() > 4 ? args_v[4].to_i : iters / 10
if iters <= 0
  << "iterations must be positive"
  exit(2)
run_bench(lane, stratum, iters, warmup)
