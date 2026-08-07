# True-public before/after benchmark for the BigInt#abs port. abs is O(1)
# on every width: identity for effective-positive receivers, a mark-shared
# plus tag-overlay flip for effective-negative ones. No call allocates, and
# negative results ALIAS the receiver's buffer, so the checksum consumes
# raw bits and never frees anything.
#
# Rows: pos (identity return), neg (mark_shared + flip), mixed (alternating,
# branch-predictor-hostile).

CORPUS_SIZE = 16
CORPUS_MASK = CORPUS_SIZE - 1

-> thread_cpu_ns
  ccall("w_leafpub_thread_cpu_ns")

-> fail_check(name, detail)
  << "FAIL [name]: [detail]"
  exit(1)

-> check_value(name, got, expected)
  if got != expected
    fail_check(name, "got=[got] expected=[expected]")

-> base_value(k)
  if (k & 3) == 0
    return 1125899906842624 + k * 2 + 1
  if (k & 3) == 1
    return 10 ** 30 + k * 2 + 1
  if (k & 3) == 2
    return 10 ** 70 + k * 2 + 1
  10 ** 150 + k * 2 + 1

-> build_corpus(stratum)
  values = []
  i = 0
  while i < CORPUS_SIZE
    v = base_value(i)
    if stratum == "neg" || (stratum == "mixed" && (i & 1) == 1)
      v = 0 - v
    values.push(v)
    i += 1
  values

-> run_correctness
  i = 0
  while i < CORPUS_SIZE
    pos = base_value(i)
    neg = 0 - pos

    # Positive receivers return themselves with exact identity
    check_value("pos identity [i]", wvalue_bits(pos.abs) == wvalue_bits(pos), true)
    # Negative receivers return the aliased buffer with the overlay flipped
    a = neg.abs
    check_value("neg value [i]", a.to_s(), pos.to_s())
    check_value("neg alias [i]", wvalue_bits(a) == (wvalue_bits(neg) ^ 140737488355328), true)
    check_value("neg receiver stable [i]", neg.to_s(), (0 - pos).to_s())
    # Double abs is stable; abs of the alias is identity
    check_value("abs idempotent [i]", wvalue_bits(a.abs) == wvalue_bits(a), true)
    # Arithmetic through the alias stays correct
    check_value("alias arith [i]", (a - pos).to_s(), "0")
    check_value("nonneg [i]", a > 0, true)
    i += 1
  << "correctness: ok ([CORPUS_SIZE * 7] identity/alias/value checks; 1-8 limb mixed widths)"

-> time_abs(values, iters)
  checksum = 0
  i = 0
  started = thread_cpu_ns()
  while i < iters
    checksum += wvalue_bits(values[i & CORPUS_MASK].abs) & 255
    i += 1
  [thread_cpu_ns() - started, checksum]

-> run_bench(stratum, iters, warmup)
  values = build_corpus(stratum)
  time_abs(values, warmup)
  result = time_abs(values, iters)
  << "RESULT|abs-[stratum]|[result[0]]|[iters]|[result[1]]"

args_v = argv()
mode = args_v.size() > 0 ? args_v[0] : "bench"
if mode == "check"
  run_correctness()
  exit(0)

if mode != "bench"
  << "mode must be check or bench"
  exit(2)

stratum = args_v.size() > 1 ? args_v[1] : "pos"
iters = args_v.size() > 2 ? args_v[2].to_i : 20_000_000
warmup = args_v.size() > 3 ? args_v[3].to_i : iters / 10
if iters <= 0
  << "iterations must be positive"
  exit(2)
run_bench(stratum, iters, warmup)
