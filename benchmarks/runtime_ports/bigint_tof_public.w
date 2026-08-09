# True-public benchmark for BigInt#to_f. Run unchanged against a PRE
# compiler (IC row 4 live) and a POST compiler (row retired, source shim
# over w_bigint_to_f); interleave samples across the two binaries.
#
# Strata: one (1-limb), four (4-limb), sixtyfour (64-limb receivers).

CORPUS_SIZE = 8
CORPUS_MASK = CORPUS_SIZE - 1

-> consume_low_byte(value)
  ccall("w_leafpub_consume_low_byte", value)

-> thread_cpu_ns
  ccall("w_leafpub_thread_cpu_ns")

-> build_receivers(stratum)
  values = []
  i = 0
  while i < CORPUS_SIZE
    if stratum == "one"
      v = 1125899906842624 + i * 2 + 1
    elsif stratum == "four"
      v = 10 ** 76 + 3 + i * 2
    else
      v = 10 ** 1232 + 11 + i * 2
    values.push(v)
    i += 1
  values

-> run_correctness
  strata = ["one", "four", "sixtyfour"]
  s = 0
  while s < strata.size
    receivers = build_receivers(strata[s])
    i = 0
    while i < CORPUS_SIZE
      f = receivers[i].to_f
      if type(f) != "Float"
        << "FAIL type [strata[s]]/[i]"
        exit(1)
      if !(f / f == ~1.0)
        << "FAIL unit [strata[s]]/[i]"
        exit(1)
      i += 1
    s += 1
  << "correctness: ok (to_f type + unit ratio, 3 strata)"

-> time_tof(receivers, iters)
  # Floats abort the shared consume helper, so consume the result's raw
  # NaN-boxed bits directly.
  checksum = 0
  i = 0
  started = thread_cpu_ns()
  while i < iters
    k = i & CORPUS_MASK
    checksum += wvalue_bits(receivers[k].to_f) & 255
    i += 1
  [thread_cpu_ns() - started, checksum]

-> run_bench(stratum, iters, warmup)
  receivers = build_receivers(stratum)
  time_tof(receivers, warmup)
  result = time_tof(receivers, iters)
  << "RESULT|tof-[stratum]|[result[0]]|[iters]|[result[1]]"

args_v = argv()
mode = args_v.size() > 0 ? args_v[0] : "bench"
if mode == "check"
  run_correctness()
  exit(0)
stratum = args_v.size() > 1 ? args_v[1] : "one"
iters = args_v.size() > 2 ? args_v[2].to_i : 3_000_000
warmup = args_v.size() > 3 ? args_v[3].to_i : iters / 10
run_bench(stratum, iters, warmup)
