# True-public benchmark for the bigint bitwise-XOR source arm. Times the
# real `a ^ b` operator on heap BigInt operands, same binary A/B via
# TUNGSTEN_BIGINT_SRC_OPS (unset = source arm, 0 = C pinned).
#
# Strata:
#   one        — 1-limb pairs (control: C's fused u64 arm)
#   int-arg    — 1-limb bigint ^ inline int (control: C)
#   four       — equal 4-limb positive pairs (source arm)
#   fortyeight — equal 48-limb positive pairs (source arm; the page-rehome
#                hazard width C guards in bignum_bitwise_positive_equal)
#   sixtyfour  — equal 64-limb positive pairs (source arm)
#   skew       — 64-limb ^ 4-limb (source arm; result is MAX-width — the tail-copy path)
#   neg        — 4-limb pairs, alternating signs (control: C's fused
#                two's-complement pass)
# No pair is identity-shaped (a != b always), so the identity arm never
# short-circuits a timed op.

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
  10 ** 76 + 3 + k * 2

-> fortyeight_limb_value(k)
  10 ** 923 + 11 + k * 2

-> big_value(k)
  10 ** 1232 + 11 + k * 2

-> build_receivers(stratum)
  values = []
  i = 0
  while i < CORPUS_SIZE
    if stratum == "one" || stratum == "int-arg"
      v = one_limb_value(i * 3)
    elsif stratum == "four" || stratum == "neg"
      v = four_limb_value(i * 3)
    elsif stratum == "fortyeight"
      v = fortyeight_limb_value(i * 3)
    else
      v = big_value(i * 3)
    if stratum == "neg" && (i & 1) == 1
      v = 0 - v
    values.push(v)
    i += 1
  values

-> build_args(stratum)
  values = []
  i = 0
  while i < CORPUS_SIZE
    if stratum == "one"
      v = one_limb_value(i * 5 + 64)
    elsif stratum == "int-arg"
      v = 1000003 + i * 2
    elsif stratum == "four" || stratum == "neg"
      v = four_limb_value(i * 5 + 64)
    elsif stratum == "fortyeight"
      v = fortyeight_limb_value(i * 5 + 64)
    elsif stratum == "skew"
      v = four_limb_value(i * 5 + 64)
    else
      v = big_value(i * 5 + 64)
    if stratum == "neg" && (i & 1) == 0
      v = 0 - v
    values.push(v)
    i += 1
  values

-> run_correctness
  strata = ["one", "int-arg", "four", "fortyeight", "sixtyfour", "skew", "neg"]
  s = 0
  while s < strata.size
    stratum = strata[s]
    receivers = build_receivers(stratum)
    args = build_args(stratum)
    i = 0
    while i < CORPUS_SIZE
      x = receivers[i]
      y = args[i]
      r = x ^ y
      check_value("comm [stratum]/[i]", (y ^ x).to_s(), r.to_s())
      check_value("invol [stratum]/[i]", (r ^ y).to_s(), x.to_s())
      check_value("zero [stratum]/[i]", (x ^ 0).to_s(), x.to_s())
      i += 1
    s += 1
  << "correctness: ok (commutativity + involution + zero, 7 strata)"

-> time_xor(receivers, args, iters)
  checksum = 0
  i = 0
  started = thread_cpu_ns()
  while i < iters
    k = i & CORPUS_MASK
    checksum += consume_low_byte(receivers[k] ^ args[k])
    i += 1
  [thread_cpu_ns() - started, checksum]

-> run_bench(stratum, iters, warmup)
  receivers = build_receivers(stratum)
  args = build_args(stratum)
  time_xor(receivers, args, warmup)
  result = time_xor(receivers, args, iters)
  << "RESULT|xor-[stratum]|[result[0]]|[iters]|[result[1]]"

args_v = argv()
mode = args_v.size() > 0 ? args_v[0] : "bench"
if mode == "check"
  run_correctness()
  exit(0)

if mode != "bench"
  << "mode must be check or bench"
  exit(2)

stratum = args_v.size() > 1 ? args_v[1] : "one"
iters = args_v.size() > 2 ? args_v[2].to_i : 5_000_000
warmup = args_v.size() > 3 ? args_v[3].to_i : iters / 10
if iters <= 0
  << "iterations must be positive"
  exit(2)
run_bench(stratum, iters, warmup)
