# Same-binary benchmark for the BigInt#lcm port. The W lane calls the public
# method; the C lane calls the retained fused runtime boundary through a
# benchmark-only method. Both pay source dispatch and return ordinary boxed
# values, isolating the lcm implementation without a raw-kernel shortcut.
#
# Strata target the C handler's specializations:
#   one-big    — 1-limb bigint receiver, 1-limb bigint argument (fused
#                u64 kernel in C, 2-limb result)
#   one-share  — 1-limb bigint pair where one power-of-two magnitude divides
#                the other (1-limb result)
#   one-int    — 1-limb bigint receiver, inline-int argument
#   multi-co   — 4-limb pairs, effectively coprime (mul-only path)
#   multi-share— 8-limb operands sharing a 4-limb factor (divexact vs
#                general division delta)
#   big-share  — ~32-limb operands sharing a ~16-limb factor
#
# No stratum is identity-shaped (x == y, +/-1 argument, or x | y), so every
# result is a fresh allocation and safe to consume/free.

+ BigInt
  -> __c_lcm_oracle(other)
    ccall("w_bigint_lcm", self, other)

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
    if stratum == "one-share"
      v = 1 << (55 + i)
    elsif stratum == "one-big" || stratum == "one-int"
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
    if stratum == "one-share"
      v = 1 << (48 + (i >> 1))
    elsif stratum == "one-big"
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

  strata = ["one-big", "one-share", "one-int", "multi-co", "multi-share", "big-share"]
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
      check_value("C differential [stratum]/[i]", m.to_s(), x.__c_lcm_oracle(y).to_s())
      check_value("nonneg [stratum]/[i]", m > 0, true)
      check_value("mod_x [stratum]/[i]", (m % x).to_s(), "0")
      check_value("mod_y [stratum]/[i]", (m % y).to_s(), "0")
      g = x.gcd(y)
      check_value("product [stratum]/[i]", (m * g).to_s(), (x * y).abs.to_s())
      i += 1
    s += 1

  # Deterministic full-word sweep. Force bit 63 so both operands are
  # normalized one-limb BigInts and exercise the raw-u64/u128 source arm.
  state = 88172645463325252 ## u64
  random_checks = 0
  while random_checks < 2048
    state = state ^ (state >> 12) ## u64
    state = state ^ (state << 25) ## u64
    state = state ^ (state >> 27) ## u64
    state = state * 2685821657736338717 ## u64
    a = state | (9223372036854775808 ## u64)
    state = state ^ (state >> 12) ## u64
    state = state ^ (state << 25) ## u64
    state = state ^ (state >> 27) ## u64
    state = state * 2685821657736338717 ## u64
    b = state | (9223372036854775808 ## u64)
    x = ccall("w_u64", a)
    y = ccall("w_u64", b)
    if (random_checks & 1) == 1
      x = 0 - x
    if (random_checks & 2) == 2
      y = 0 - y
    check_value("random C differential [random_checks]", x.lcm(y).to_s(), x.__c_lcm_oracle(y).to_s())
    random_checks += 1
  << "correctness: ok ([48 + random_checks] C differentials + edge/divisibility/product identities, 6 strata, mixed signs)"

-> time_lcm_w(receivers, args, iters)
  checksum = 0
  i = 0
  started = thread_cpu_ns()
  while i < iters
    k = i & CORPUS_MASK
    checksum += consume_low_byte(receivers[k].lcm(args[k]))
    i += 1
  [thread_cpu_ns() - started, checksum]

-> time_lcm_c(receivers, args, iters)
  checksum = 0
  i = 0
  started = thread_cpu_ns()
  while i < iters
    k = i & CORPUS_MASK
    checksum += consume_low_byte(receivers[k].__c_lcm_oracle(args[k]))
    i += 1
  [thread_cpu_ns() - started, checksum]

-> run_bench(lane, stratum, iters, warmup)
  receivers = build_receivers(stratum)
  args = build_args(stratum)
  result = nil
  if lane == "c"
    time_lcm_c(receivers, args, warmup)
    result = time_lcm_c(receivers, args, iters)
  else
    time_lcm_w(receivers, args, warmup)
    result = time_lcm_w(receivers, args, iters)
  << "RESULT|lcm-[stratum]|[result[0]]|[iters]|[result[1]]"

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
