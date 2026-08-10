# Same-binary gate for the complete native BigInt/integer comparator. Both
# timed lanes return a boxed -1/0/1 through identical C wrappers; the source
# lane calls the production __w_bigint_compare_src seam and the oracle lane
# calls the retained C implementation. Public comparison syntax is checked
# separately below so a favorable kernel result cannot hide routing failure.

CORPUS_SIZE = 8
CORPUS_MASK = CORPUS_SIZE - 1

-> thread_cpu_ns
  ccall("w_leafpub_thread_cpu_ns")

-> source_compare(a, b)
  ccall("w_bigint_compare_source", a, b)

-> c_compare(a, b)
  ccall("w_bigint_compare_c", a, b)

-> make_width_value(limbs, salt)
  (1 << (limbs * 64 - 1)) + (1 << (limbs * 64 - 65)) + salt * 2 + 1

-> build_pairs(stratum)
  left = []
  right = []
  i = 0
  while i < CORPUS_SIZE
    if stratum.starts_with?("width-")
      width = stratum.split("-")[1].to_i
      a = make_width_value(width, i + 7)
      left.push(a + 5)
      right.push(a + 3)
    elsif stratum == "unequal"
      left.push(make_width_value(8, i + 31))
      right.push(make_width_value(4, i + 37))
    elsif stratum == "negative"
      a = make_width_value(8, i + 41)
      left.push(0 - (a + 5))
      right.push(0 - (a + 3))
    elsif stratum == "negative-unequal"
      left.push(0 - make_width_value(8, i + 43))
      right.push(0 - make_width_value(4, i + 47))
    elsif stratum == "mixed-sign"
      left.push(0 - make_width_value(8, i + 49))
      right.push(make_width_value(8, i + 53))
    elsif stratum == "identity"
      a = make_width_value(16, i + 59)
      left.push(a)
      right.push(a)
    elsif stratum == "int-left"
      left.push(17 + i)
      right.push((1 << 63) + i * 2 + 1)
    elsif stratum == "int-right"
      left.push((1 << 63) + i * 2 + 1)
      right.push(17 + i)
    elsif stratum == "int-neg-left"
      left.push(-17 - i)
      right.push(0 - ((1 << 63) + i * 2 + 1))
    elsif stratum == "int-neg-right"
      left.push(0 - ((1 << 63) + i * 2 + 1))
      right.push(-17 - i)
    else
      left.push((1 << 63) + i * 2 + 1)
      right.push(0)
    i += 1
  [left, right]

-> check_public(label, a, b, expected)
  if (a <=> b) != expected
    << "FAIL public spaceship " + label
    exit(1)
  if (a == b) != (expected == 0)
    << "FAIL public equality " + label
    exit(1)
  if (a != b) != (expected != 0)
    << "FAIL public inequality " + label
    exit(1)
  if (a < b) != (expected < 0)
    << "FAIL public less " + label
    exit(1)
  if (a > b) != (expected > 0)
    << "FAIL public greater " + label
    exit(1)
  if (a <= b) != (expected <= 0)
    << "FAIL public less-equal " + label
    exit(1)
  if (a >= b) != (expected >= 0)
    << "FAIL public greater-equal " + label
    exit(1)

-> run_correctness
  strata = ["width-1", "width-2", "width-3", "width-4", "width-8", "width-64", "width-257", "unequal", "negative", "negative-unequal", "mixed-sign", "identity", "int-left", "int-right", "int-neg-left", "int-neg-right", "int-zero"]
  checks = 0
  s = 0
  while s < strata.size()
    pair = build_pairs(strata[s])
    i = 0
    while i < CORPUS_SIZE
      got = source_compare(pair[0][i], pair[1][i])
      expected = c_compare(pair[0][i], pair[1][i])
      if got != expected
        << "FAIL source/C " + strata[s] + "/" + i.to_s()
        exit(1)
      check_public(strata[s], pair[0][i], pair[1][i], expected)
      reverse = source_compare(pair[1][i], pair[0][i])
      if reverse != 0 - expected
        << "FAIL antisymmetry " + strata[s] + "/" + i.to_s()
        exit(1)
      checks += 1
      i += 1
    s += 1

  # Deterministic differential sweep. Vary both widths independently, move
  # the first differing bit through low/middle/high limbs, and rotate all sign
  # combinations plus mixed inline operands. This validates the production
  # helper directly; the smaller matrix above additionally exercises every
  # public operator and method route.
  widths = [1, 2, 3, 4, 5, 8, 16, 31, 64, 127, 257]
  d = 0
  while d < 4096
    aw = widths[d % widths.size()]
    bw = widths[(d * 7 + 3) % widths.size()]
    a = make_width_value(aw, d + 101)
    b = make_width_value(bw, d + 103)
    if aw == bw && aw > 1
      differing_limb = (d * 13) % (aw - 1)
      b += 1 << (differing_limb * 64)
    if (d & 1) != 0
      a = 0 - a
    if (d & 2) != 0
      b = 0 - b
    if d % 11 == 0
      b = d % 1001 - 500
    got = source_compare(a, b)
    expected = c_compare(a, b)
    if got != expected
      << "FAIL differential " + d.to_s() + " (" + aw.to_s() + "/" + bw.to_s() + ")"
      exit(1)
    if source_compare(b, a) != 0 - expected
      << "FAIL differential antisymmetry " + d.to_s()
      exit(1)
    checks += 1
    d += 1
  << "correctness: ok (" + checks.to_s() + " exact boxed C differentials plus every public comparison operator)"

-> time_compare_source(left, right, iters)
  checksum = 0
  i = 0
  started = thread_cpu_ns()
  while i < iters
    k = i & CORPUS_MASK
    checksum += source_compare(left[k], right[k])
    i += 1
  [thread_cpu_ns() - started, checksum]

-> time_compare_c(left, right, iters)
  checksum = 0
  i = 0
  started = thread_cpu_ns()
  while i < iters
    k = i & CORPUS_MASK
    checksum += c_compare(left[k], right[k])
    i += 1
  [thread_cpu_ns() - started, checksum]

-> run_bench(lane, stratum, iters, warmup)
  pair = build_pairs(stratum)
  result = nil
  if lane == "c"
    time_compare_c(pair[0], pair[1], warmup)
    result = time_compare_c(pair[0], pair[1], iters)
  else
    time_compare_source(pair[0], pair[1], warmup)
    result = time_compare_source(pair[0], pair[1], iters)
  << "RESULT|compare-" + stratum + "|" + result[0].to_s() + "|" + iters.to_s() + "|" + result[1].to_s()

args_v = argv()
mode = args_v.size() > 0 ? args_v[0] : "bench"
if mode == "check"
  run_correctness()
  exit(0)
lane = args_v.size() > 1 ? args_v[1] : "w"
stratum = args_v.size() > 2 ? args_v[2] : "width-4"
iters = args_v.size() > 3 ? args_v[3].to_i : 2_000_000
warmup = args_v.size() > 4 ? args_v[4].to_i : iters / 10
run_bench(lane, stratum, iters, warmup)
