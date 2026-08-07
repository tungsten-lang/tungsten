# True-public benchmark for the bigint `*` operator source path.
# Times the real `a + b` operator on heap BigInt operands. Run unchanged
# before (no arm: w_add -> bigint_add_any direct) and after (w_add's bigint
# arm routes through the compiled BigInt#__big_add source body); compare
# per-stratum medians.
#
# Strata:
#   one       — 1-limb pairs (the dispatch-sensitive ~20ns case)
#   int-arg   — 1-limb bigint + inline int (the add1 shape)
#   four      — 4-limb pairs
#   mixed     — 4-limb pairs with alternating signs (magnitude-subtract path)
#   sixtyfour — 64-limb pairs
# No operand is zero and no pair is identity-shaped, so every result is a
# fresh allocation (or inline demotion) and safe to consume/free.

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

-> big_value(k)
  10 ** 1232 + 11 + k * 2

# ~8 limbs (~512 bits): the skew receiver, inside the schoolbook band.
-> eight_limb_value(k)
  10 ** 154 + 9 + k * 2

-> build_receivers(stratum)
  values = []
  i = 0
  while i < CORPUS_SIZE
    if stratum == "one" || stratum == "int-arg"
      v = one_limb_value(i * 3)
    elsif stratum == "skew"
      v = eight_limb_value(i * 3)
    elsif stratum == "four" || stratum == "mixed"
      v = four_limb_value(i * 3)
    else
      v = big_value(i * 3)
    if stratum == "mixed" && (i & 1) == 1
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
    elsif stratum == "skew"
      v = four_limb_value(i * 5 + 64)
    elsif stratum == "four"
      v = four_limb_value(i * 5 + 64)
    elsif stratum == "mixed"
      v = four_limb_value(i * 5 + 64)
      if (i & 1) == 0
        v = 0 - v
    else
      v = big_value(i * 5 + 64)
    values.push(v)
    i += 1
  values

-> run_correctness
  strata = ["one", "int-arg", "four", "mixed", "sixtyfour", "skew"]
  s = 0
  while s < strata.size
    stratum = strata[s]
    receivers = build_receivers(stratum)
    args = build_args(stratum)
    i = 0
    while i < CORPUS_SIZE
      x = receivers[i]
      y = args[i]
      total = x * y
      check_value("div_inverse [stratum]/[i]", (total / y).to_s(), x.to_s())
      check_value("comm [stratum]/[i]", (y * x).to_s(), total.to_s())
      i += 1
    s += 1
  << "correctness: ok (add/sub inverse + commutativity, 5 strata)"

-> time_add(receivers, args, iters)
  checksum = 0
  i = 0
  started = thread_cpu_ns()
  while i < iters
    k = i & CORPUS_MASK
    checksum += consume_low_byte(receivers[k] * args[k])
    i += 1
  [thread_cpu_ns() - started, checksum]

-> run_bench(stratum, iters, warmup)
  receivers = build_receivers(stratum)
  args = build_args(stratum)
  time_add(receivers, args, warmup)
  result = time_add(receivers, args, iters)
  << "RESULT|mul-[stratum]|[result[0]]|[iters]|[result[1]]"

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
