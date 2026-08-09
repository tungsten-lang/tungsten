# Same-binary benchmark for BigInt#to_f. The W lane calls the true public
# method; the C lane calls a benchmark-only source method whose entire body is
# the retained public runtime boundary. Both therefore pay source dispatch,
# while only the conversion kernel differs.
#
# Strata: positive/negative 1, 4, and 16-limb finite receivers; 17-limb values
# at the infinity threshold; and 64-limb values that are unconditionally
# infinite from normalized width alone.

+ BigInt
  -> __c_to_f_oracle
    ccall("w_bigint_to_f", self)

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
  # ~16 limbs: the widest stratum that still converts to a FINITE double
  # (doubles top out near 1.8e308; a 64-limb value is always +inf).
  10 ** 300 + 11 + k * 2

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
  values = nil
  if stratum == "one" || stratum == "one-neg"
    values = build_one()
  elsif stratum == "four" || stratum == "four-neg"
    values = build_four()
  elsif stratum == "sixteen" || stratum == "sixteen-neg"
    values = build_big()
  elsif stratum == "seventeen" || stratum == "seventeen-neg"
    values = []
    i = 0
    while i < CORPUS_SIZE
      values.push((1 << 1024) + (1 << 511) + 11 + i * 2)
      i += 1
  else
    values = []
    i = 0
    while i < CORPUS_SIZE
      values.push((1 << 4095) + (1 << 2000) + 11 + i * 2)
      i += 1
  if stratum == "one-neg" || stratum == "four-neg" || stratum == "sixteen-neg" || stratum == "seventeen-neg" || stratum == "sixtyfour-neg"
    i = 0
    while i < values.size
      values[i] = 0 - values[i]
      i += 1
  values

-> run_correctness
  strata = ["one", "one-neg", "four", "four-neg", "sixteen", "sixteen-neg", "seventeen", "seventeen-neg", "sixtyfour", "sixtyfour-neg"]
  s = 0
  while s < strata.size
    receivers = build_receivers(strata[s])
    i = 0
    while i < CORPUS_SIZE
      f = receivers[i].to_f
      if type(f) != "Float"
        << "FAIL type [strata[s]]/[i]"
        exit(1)
      if wvalue_bits(f) != wvalue_bits(receivers[i].__c_to_f_oracle)
        << "FAIL C differential [strata[s]]/[i]"
        exit(1)
      i += 1
    s += 1
  edges = [(1 << 53) - 1, 1 << 53, (1 << 53) + 1, (1 << 53) + 2, (1 << 53) + 3, (1 << 64) - 1, (1 << 100) + (1 << 46) + 3, (1 << 1024) - (1 << 971), (1 << 1024) - (1 << 970), 1 << 1024]
  i = 0
  while i < edges.size
    x = edges[i]
    if wvalue_bits(x.to_f) != wvalue_bits(x.__c_to_f_oracle)
      << "FAIL positive edge [i]"
      exit(1)
    if wvalue_bits((0 - x).to_f) != wvalue_bits((0 - x).__c_to_f_oracle)
      << "FAIL negative edge [i]"
      exit(1)
    i += 1
  if build_receivers("four")[0].to_s().size() < 70 || build_receivers("sixteen")[0].to_s().size() < 300 || build_receivers("sixtyfour")[0].to_s().size() < 1200
    << "FAIL corpus width"
    exit(1)
  << "correctness: ok (100 exact C differentials + corpus width, finite/infinity and sign seams)"

-> time_tof_w(receivers, iters)
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

-> time_tof_c(receivers, iters)
  checksum = 0
  i = 0
  started = thread_cpu_ns()
  while i < iters
    k = i & CORPUS_MASK
    checksum += wvalue_bits(receivers[k].__c_to_f_oracle) & 255
    i += 1
  [thread_cpu_ns() - started, checksum]

-> run_bench(lane, stratum, iters, warmup)
  receivers = build_receivers(stratum)
  result = nil
  if lane == "c"
    time_tof_c(receivers, warmup)
    result = time_tof_c(receivers, iters)
  else
    time_tof_w(receivers, warmup)
    result = time_tof_w(receivers, iters)
  << "RESULT|tof-[stratum]|[result[0]]|[iters]|[result[1]]"

args_v = argv()
mode = args_v.size() > 0 ? args_v[0] : "bench"
if mode == "check"
  run_correctness()
  exit(0)
lane = args_v.size() > 1 ? args_v[1] : "w"
stratum = args_v.size() > 2 ? args_v[2] : "one"
iters = args_v.size() > 3 ? args_v[3].to_i : 3_000_000
warmup = args_v.size() > 4 ? args_v[4].to_i : iters / 10
run_bench(lane, stratum, iters, warmup)
