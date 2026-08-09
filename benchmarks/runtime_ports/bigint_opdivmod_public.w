# True-public benchmark for the bigint `/` and `%` source-routed dispatch
# arm (native one-limb pairs; wider pairs use the exported
# w_bigint_div/w_bigint_mod boundaries). Same-binary A/B via
# TUNGSTEN_BIGINT_SRC_OPS (unset = source arm, 0 = C pinned).
#
# Strata (per op; `mode` argv selects div or mod rows):
#   one      — 1-limb / 1-limb heap pairs with a heap-sized remainder
#   one-smallrem — exact quotient plus an inline remainder
#   one-high — dividend has bit 63 set (unsigned division/codegen seam)
#   one-lt   — |dividend| < |divisor| (zero quotient, identity remainder)
#   one-nega/one-negb/one-negboth — all truncated-sign combinations
#   intarg   — bigint / inline int (control: C, gate excludes)
#   fourtwo  — 4-limb / 2-limb (preinverse band)
#   eq       — 64-limb / 61-limb near-equal (tiny quotient)
#   bz       — 256-limb / 128-limb (Burnikel-Ziegler band)
#   neg      — 4-limb / 2-limb with alternating signs (in-gate; kernel
#              owns sign handling)

+ BigInt
  -> __c_div_oracle(other)
    ccall("w_bigint_div", self, other)

  -> __c_mod_oracle(other)
    ccall("w_bigint_mod", self, other)

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

-> one_limb_divisor(k)
  one_limb_value(k * 5 + 64)

-> build_receivers(stratum)
  values = []
  i = 0
  while i < CORPUS_SIZE
    if stratum == "one" || stratum == "one-nega" || stratum == "one-negb" || stratum == "one-negboth" || stratum == "intarg"
      v = one_limb_value(i * 3) * 512 + 255
    elsif stratum == "one-smallrem"
      v = one_limb_divisor(i) * 512 + 255 + i
    elsif stratum == "one-high"
      v = (1 << 64) - 257 - i * 2
    elsif stratum == "one-lt"
      v = one_limb_value(i * 3)
    elsif stratum == "fourtwo" || stratum == "neg"
      v = 10 ** 76 + 3 + i * 2
    elsif stratum == "eq"
      v = 10 ** 1232 + 11 + i * 2
    else
      v = 10 ** 4928 + 11 + i * 2
    if stratum == "one-nega" || stratum == "one-negboth" || (stratum == "neg" && (i & 1) == 1)
      v = 0 - v
    values.push(v)
    i += 1
  values

-> build_args(stratum)
  values = []
  i = 0
  while i < CORPUS_SIZE
    if stratum == "one" || stratum == "one-nega" || stratum == "one-negb" || stratum == "one-negboth" || stratum == "one-smallrem"
      v = one_limb_divisor(i)
    elsif stratum == "one-high"
      v = one_limb_value(i * 7 + 96)
    elsif stratum == "one-lt"
      v = one_limb_value(i * 3) + 4096
    elsif stratum == "intarg"
      v = 1000003 + i * 2
    elsif stratum == "fourtwo" || stratum == "neg"
      v = 10 ** 38 + 7 + i * 2
    elsif stratum == "eq"
      v = 10 ** 1229 + 17 + i * 2
    else
      v = 10 ** 2464 + 7 + i * 2
    if stratum == "one-negb" || stratum == "one-negboth" || (stratum == "neg" && (i & 1) == 0)
      v = 0 - v
    values.push(v)
    i += 1
  values

-> run_correctness
  strata = ["one", "one-smallrem", "one-high", "one-lt", "one-nega", "one-negb", "one-negboth", "intarg", "fourtwo", "eq", "bz", "neg"]
  s = 0
  while s < strata.size
    stratum = strata[s]
    receivers = build_receivers(stratum)
    args = build_args(stratum)
    i = 0
    while i < CORPUS_SIZE
      x = receivers[i]
      y = args[i]
      q = x / y
      r = x % y
      check_value("div C differential [stratum]/[i]", q.to_s(), x.__c_div_oracle(y).to_s())
      check_value("mod C differential [stratum]/[i]", r.to_s(), x.__c_mod_oracle(y).to_s())
      check_value("roundtrip [stratum]/[i]", (q * y + r).to_s(), x.to_s())
      i += 1
    s += 1
  << "correctness: ok (192 exact C differentials + q*y + r == x, 12 strata)"

-> time_div(receivers, args, iters)
  checksum = 0
  i = 0
  started = thread_cpu_ns()
  while i < iters
    k = i & CORPUS_MASK
    checksum += consume_low_byte(receivers[k] / args[k])
    i += 1
  [thread_cpu_ns() - started, checksum]

-> time_mod(receivers, args, iters)
  checksum = 0
  i = 0
  started = thread_cpu_ns()
  while i < iters
    k = i & CORPUS_MASK
    checksum += consume_low_byte(receivers[k] % args[k])
    i += 1
  [thread_cpu_ns() - started, checksum]

-> run_bench(op, stratum, iters, warmup)
  receivers = build_receivers(stratum)
  args = build_args(stratum)
  if op == "div"
    time_div(receivers, args, warmup)
    result = time_div(receivers, args, iters)
  else
    time_mod(receivers, args, warmup)
    result = time_mod(receivers, args, iters)
  << "RESULT|[op]-[stratum]|[result[0]]|[iters]|[result[1]]"

args_v = argv()
mode = args_v.size() > 0 ? args_v[0] : "bench"
if mode == "check"
  run_correctness()
  exit(0)

if mode != "div" && mode != "mod"
  << "mode must be check, div or mod"
  exit(2)

stratum = args_v.size() > 1 ? args_v[1] : "one"
iters = args_v.size() > 2 ? args_v[2].to_i : 2_000_000
warmup = args_v.size() > 3 ? args_v[3].to_i : iters / 10
if iters <= 0
  << "iterations must be positive"
  exit(2)
run_bench(mode, stratum, iters, warmup)
