# True-public benchmark for BigInt#to_s. Run unchanged against a PRE
# compiler (IC row 0 live) and a POST compiler (row retired, source shim
# over w_bigint_to_s); interleave samples across the two binaries.
#
# Strata: one (1-limb), four (4-limb), sixtyfour (64-limb receivers).

CORPUS_SIZE = 8
CORPUS_MASK = CORPUS_SIZE - 1

-> consume_low_byte(value)
  ccall("w_leafpub_consume_low_byte", value)

-> thread_cpu_ns
  ccall("w_leafpub_thread_cpu_ns")

-> one_limb_value(k)
  1125899906842624 + k * 2 + 1

-> four_limb_value(k)
  10 ** 76 + 3 + k * 2

-> big_value(k)
  10 ** 1232 + 11 + k * 2

# Each stratum has its OWN builder with a dedicated local: a shared var
# whose branches mix machine-typed and pow-BigInt values gets raw-slot
# promoted and the BigInts truncate through it (10^76 = 0 mod 2^64, so
# the corruption is silent — a leg of the open machine-typing family).
-> build_one
  values = []
  i = 0
  while i < CORPUS_SIZE
    values.push(one_limb_value(i))
    i += 1
  values

-> build_four
  values = []
  i = 0
  while i < CORPUS_SIZE
    values.push(four_limb_value(i))
    i += 1
  values

-> build_big
  values = []
  i = 0
  while i < CORPUS_SIZE
    values.push(big_value(i))
    i += 1
  values

-> build_receivers(stratum)
  if stratum == "one"
    return build_one()
  if stratum == "four"
    return build_four()
  build_big()

-> run_correctness
  strata = ["one", "four", "sixtyfour"]
  s = 0
  while s < strata.size
    receivers = build_receivers(strata[s])
    i = 0
    while i < CORPUS_SIZE
      t = receivers[i].to_s()
      if t.to_i != receivers[i]
        << "FAIL roundtrip [strata[s]]/[i]"
        exit(1)
      if receivers[i].to_s(16).size() < 2
        << "FAIL hex [strata[s]]/[i] size=[receivers[i].to_s(16).size()] val=[receivers[i].to_s(16)]"
        exit(1)
      i += 1
    s += 1
  if build_receivers("four")[0].to_s().size() < 70 || build_receivers("sixtyfour")[0].to_s().size() < 1200
    << "FAIL corpus width"
    exit(1)
  << "correctness: ok (to_s round-trip + hex + corpus width, 3 strata)"

-> time_tos(receivers, iters)
  # Strings abort the shared consume helper, so consume the result's raw
  # NaN-boxed bits directly.
  checksum = 0
  i = 0
  started = thread_cpu_ns()
  while i < iters
    k = i & CORPUS_MASK
    checksum += wvalue_bits(receivers[k].to_s()) & 255
    i += 1
  [thread_cpu_ns() - started, checksum]

-> run_bench(stratum, iters, warmup)
  receivers = build_receivers(stratum)
  time_tos(receivers, warmup)
  result = time_tos(receivers, iters)
  << "RESULT|tos-[stratum]|[result[0]]|[iters]|[result[1]]"

args_v = argv()
mode = args_v.size() > 0 ? args_v[0] : "bench"
if mode == "check"
  run_correctness()
  exit(0)
stratum = args_v.size() > 1 ? args_v[1] : "one"
iters = args_v.size() > 2 ? args_v[2].to_i : 1_000_000
warmup = args_v.size() > 3 ? args_v[3].to_i : iters / 10
run_bench(stratum, iters, warmup)
