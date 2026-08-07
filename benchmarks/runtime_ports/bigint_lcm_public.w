# True-public before/after benchmark for the BigInt#lcm port. Receivers are
# heap BigInts from decimal literals plus arithmetic; the timed loops call the
# real public selector. Run unchanged before (C IC installed) and after (IC
# row retired, Int#lcm source body dispatches); compare per-stratum medians.
#
# Strata target the C handler's specializations:
#   one-big    — 1-limb bigint receiver, 1-limb bigint argument (fused
#                u64 kernel in C)
#   one-int    — 1-limb bigint receiver, inline-int argument
#   multi-co   — 4-limb pairs, effectively coprime (mul-only path)
#   multi-share— 8-limb operands sharing a 4-limb factor (divexact vs
#                general division delta)
#   big-share  — ~32-limb operands sharing a ~16-limb factor
#
# No stratum is identity-shaped (x == y, +/-1 argument, or x | y), so every
# result is a fresh allocation and safe to consume/free.

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

# 1-limb heap bigints: > 2^47, < 2^64
-> one_limb_value(k)
  1125899906842624 + k * 2

# ~4-limb values (~256 bits)
-> four_limb_value(k)
  100000000000000000000000000000000000000000000000000000000000000000000000000003 + k * 2

# ~16-limb values (~1024 bits)
-> sixteen_limb_value(k)
  10 ** 308 + 7 + k * 2

-> build_receivers(stratum)
  values = []
  i = 0
  while i < CORPUS_SIZE
    if stratum == "one-big" || stratum == "one-int"
      v = one_limb_value(i * 3 + 1)
    elsif stratum == "multi-co"
      v = four_limb_value(i * 3 + 1)
    elsif stratum == "multi-share"
      v = four_limb_value(100) * (four_limb_value(i * 3 + 1))
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
      v = one_limb_value(i * 5 + 200)
    elsif stratum == "one-int"
      v = 1000003 + i * 2
    elsif stratum == "multi-co"
      v = four_limb_value(i * 5 + 200)
    elsif stratum == "multi-share"
      v = four_limb_value(100) * (four_limb_value(i * 5 + 200))
    else
      v = sixteen_limb_value(100) * (sixteen_limb_value(i * 5 + 200))
    values.push(v)
    i += 1
  values

-> run_correctness
  # Edge semantics shared by the C handler and Int#lcm
  ten40 = 10 ** 40
  check_value("lcm.zero_left", (0 * ten40).lcm(ten40), 0)
  check_value("lcm.zero_right", ten40.lcm(0), 0)
  check_value("lcm.one", ten40.lcm(1).to_s(), ten40.to_s())
  check_value("lcm.self", ten40.lcm(ten40).to_s(), ten40.to_s())
  check_value("lcm.neg_receiver", (0 - ten40).lcm(3).to_s(), (ten40 * 3).to_s())
  check_value("lcm.neg_arg", ten40.lcm(0 - 3).to_s(), (ten40 * 3).to_s())

  strata = ["one-big", "one-int", "multi-co", "multi-share", "big-share"]
  s = 0
  while s < strata.size
    stratum = strata[s]
    receivers = build_receivers(stratum)
    args = build_args(stratum)
    i = 0
    while i < CORPUS_SIZE
      x = receivers[i]
      y = args[i]
      m = x.lcm(y)
      check_value("nonneg [stratum]/[i]", m > 0, true)
      check_value("mod_x [stratum]/[i]", (m % x).to_s(), "0")
      check_value("mod_y [stratum]/[i]", (m % y).to_s(), "0")
      g = x.gcd(y)
      check_value("product [stratum]/[i]", (m * g).to_s(), (x * y).abs.to_s())
      i += 1
    s += 1
  << "correctness: ok (edge semantics + divisibility/product identities, 5 strata, mixed signs)"

-> time_lcm(receivers, args, iters)
  checksum = 0
  i = 0
  started = thread_cpu_ns()
  while i < iters
    k = i & CORPUS_MASK
    checksum += consume_low_byte(receivers[k].lcm(args[k]))
    i += 1
  [thread_cpu_ns() - started, checksum]

-> run_bench(stratum, iters, warmup)
  receivers = build_receivers(stratum)
  args = build_args(stratum)
  time_lcm(receivers, args, warmup)
  result = time_lcm(receivers, args, iters)
  << "RESULT|lcm-[stratum]|[result[0]]|[iters]|[result[1]]"

args_v = argv()
mode = args_v.size() > 0 ? args_v[0] : "bench"
if mode == "check"
  run_correctness()
  exit(0)

if mode != "bench"
  << "mode must be check or bench"
  exit(2)

stratum = args_v.size() > 1 ? args_v[1] : "one-big"
iters = args_v.size() > 2 ? args_v[2].to_i : 1_000_000
warmup = args_v.size() > 3 ? args_v[3].to_i : iters / 10
if iters <= 0
  << "iterations must be positive"
  exit(2)
run_bench(stratum, iters, warmup)
