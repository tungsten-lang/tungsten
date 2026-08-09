# Same-binary benchmark for BigInt#gcd. The W lane calls the true public
# method; the C lane calls a benchmark-only method over the retained public
# runtime boundary. Both pay source dispatch, isolating the GCD implementation.
#
# Strata:
#   one-big  — 1-limb bigint pairs (boxed u64 kernel; dispatch-sensitive)
#   one-int  — 1-limb bigint receiver, inline-int argument
#   near     — near-equal 4-limb pairs (gcd collapses instantly; isolates
#              dispatch/entry overhead at the ~100ns scale)
#   skew     — 8-limb vs 4-limb operands (genuine reduction work)
#   big-share— ~32-limb operands sharing a ~16-limb factor (multi-limb
#              gcd result, heap-allocated)
#
# No timed pair is identity-shaped (x == y or one operand dividing the
# other), so results never alias an input and are safe to consume/free.

+ BigInt
  -> __c_gcd_oracle(other)
    ccall("w_bigint_gcd", self, other)

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

-> one_limb_value(k)
  1125899906842624 + k * 2 + 1

-> four_limb_value(k)
  100000000000000000000000000000000000000000000000000000000000000000000000000003 + k * 2

-> eight_limb_value(k)
  10 ** 153 + 9 + k * 2

-> sixteen_limb_value(k)
  10 ** 308 + 7 + k * 2

-> build_receivers(stratum)
  values = []
  i = 0
  while i < CORPUS_SIZE
    if stratum == "one-big" || stratum == "one-int"
      v = one_limb_value(i * 3)
    elsif stratum == "near"
      v = four_limb_value(i * 3 + 1)
    elsif stratum == "skew"
      v = eight_limb_value(i * 3 + 1)
    else
      v = sixteen_limb_value(100) * (sixteen_limb_value(i * 3 + 1))
    if (i & 1) == 1
      v = 0 - v
    values.push(v)
    i += 1
  values

-> build_args(stratum)
  values = []
  i = 0
  while i < CORPUS_SIZE
    if stratum == "one-big"
      v = one_limb_value(i * 5 + 100)
    elsif stratum == "one-int"
      v = 1000003 + i * 2
    elsif stratum == "near"
      v = four_limb_value(i * 5 + 200)
    elsif stratum == "skew"
      v = four_limb_value(i * 5 + 200)
    else
      v = sixteen_limb_value(100) * (sixteen_limb_value(i * 5 + 200))
    values.push(v)
    i += 1
  values

-> run_correctness
  ten40 = 10 ** 40
  # Shared semantics with the C handler across widths and signs
  check_value("gcd.self", ten40.gcd(ten40).to_s(), ten40.to_s())
  check_value("gcd.one", ten40.gcd(1), 1)
  check_value("gcd.zero_arg", ten40.gcd(0).to_s(), ten40.to_s())
  check_value("gcd.neg_receiver", (0 - ten40).gcd(6), 2)
  check_value("gcd.neg_arg", ten40.gcd(0 - 6), 2)
  check_value("gcd.factor", (ten40 * 3).gcd(ten40 * 7).to_s(), ten40.to_s())
  one_limb_factor = 140737488355329
  one_limb_a = one_limb_factor * 5
  one_limb_b = 0 - one_limb_factor * 7
  one_limb_g = one_limb_a.gcd(one_limb_b)
  check_value("gcd.one_limb_heap_result", one_limb_g.to_s(), one_limb_factor.to_s())
  check_value(
    "gcd.one_limb_heap_result_c",
    one_limb_g.to_s(),
    one_limb_a.__c_gcd_oracle(one_limb_b).to_s()
  )
  high_a = "18446744073709551615".to_i
  high_b = "-9223372036854775809".to_i
  check_value("gcd.one_limb_high_bit", high_a.gcd(high_b), 3)
  check_value(
    "gcd.one_limb_high_bit_c",
    high_a.gcd(high_b).to_s(),
    high_a.__c_gcd_oracle(high_b).to_s()
  )

  strata = ["one-big", "one-int", "near", "skew", "big-share"]
  s = 0
  while s < strata.size
    stratum = strata[s]
    receivers = build_receivers(stratum)
    args = build_args(stratum)
    i = 0
    while i < CORPUS_SIZE
      x = receivers[i]
      y = args[i]
      g = x.gcd(y)
      check_value("C differential [stratum]/[i]", g.to_s(), x.__c_gcd_oracle(y).to_s())
      check_value("pos [stratum]/[i]", g > 0, true)
      check_value("div_x [stratum]/[i]", (x % g).to_s(), "0")
      check_value("div_y [stratum]/[i]", (y % g).to_s(), "0")
      # g is the GREATEST common divisor: the cofactors are coprime
      check_value("greatest [stratum]/[i]", (x / g).gcd(y / g), 1)
      i += 1
    s += 1
  << "correctness: ok (42 exact C differentials + divisor/greatest identities, heap/high-bit one-limb results, mixed signs)"

-> time_gcd_w(receivers, args, iters)
  checksum = 0
  i = 0
  started = thread_cpu_ns()
  while i < iters
    k = i & CORPUS_MASK
    checksum += consume_low_byte(receivers[k].gcd(args[k]))
    i += 1
  [thread_cpu_ns() - started, checksum]

-> time_gcd_c(receivers, args, iters)
  checksum = 0
  i = 0
  started = thread_cpu_ns()
  while i < iters
    k = i & CORPUS_MASK
    checksum += consume_low_byte(receivers[k].__c_gcd_oracle(args[k]))
    i += 1
  [thread_cpu_ns() - started, checksum]

-> run_bench(lane, stratum, iters, warmup)
  receivers = build_receivers(stratum)
  args = build_args(stratum)
  result = nil
  if lane == "c"
    time_gcd_c(receivers, args, warmup)
    result = time_gcd_c(receivers, args, iters)
  else
    time_gcd_w(receivers, args, warmup)
    result = time_gcd_w(receivers, args, iters)
  << "RESULT|gcd-[stratum]|[result[0]]|[iters]|[result[1]]"

args_v = argv()
mode = args_v.size() > 0 ? args_v[0] : "bench"
if mode == "check"
  run_correctness()
  exit(0)

if mode != "bench"
  << "mode must be check or bench"
  exit(2)

lane = args_v.size() > 1 ? args_v[1] : "w"
stratum = args_v.size() > 2 ? args_v[2] : "one-big"
iters = args_v.size() > 3 ? args_v[3].to_i : 1_000_000
warmup = args_v.size() > 4 ? args_v[4].to_i : iters / 10
if iters <= 0
  << "iterations must be positive"
  exit(2)
run_bench(lane, stratum, iters, warmup)
