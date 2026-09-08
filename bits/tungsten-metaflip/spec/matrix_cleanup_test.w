use ../lib/metaflip/fleet/pair_cleanup

-> mc_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL matrix cleanup: " + label
    return 1
  0

-> mc_gate_case(n, m, p, rectangular) (i64 i64 i64 i64) i64
  capacity = ffr_default_capacity(n, m, p) ## i64
  st = i64[ffw_state_size(capacity)]
  loaded = 0 ## i64
  if rectangular == 0
    loaded = ffw_init_naive_cap(st, n, capacity, 17, 8, 3, 1000, 2000)
  else
    loaded = ffr_init_naive_cap(st, n, m, p, capacity, 17, 8, 3, 1000, 2000)
  failed = mc_expect("naive control", loaded == n * m * p) ## i64
  # Identity matrix = (2,1) + (1,2) + (3,3): no pair shares two factors,
  # but all three terms share U and the residual matrix has exact rank two.
  rank = ffw_toggle(st, 1, 1, 1, st[6]) ## i64
  rank = ffw_toggle(st, 1, 2, 2, rank)
  rank = ffw_toggle(st, 1, 2, 1, rank)
  rank = ffw_toggle(st, 1, 1, 2, rank)
  rank = ffw_toggle(st, 1, 3, 3, rank)
  st[6] = rank
  z = ffw_copy_current_to_best(st) ## i64
  words = ffpc_scratch_words(capacity) ## i64
  work = i64[words]
  before = i64[ffw_state_size(capacity)]
  i = 0 ## i64
  while i < st[63]
    before[i] = st[i]
    i += 1
  i = 0
  while i < rank
    work[i] = st[st[47] + i]
    work[capacity + i] = st[st[48] + i]
    work[2 * capacity + i] = st[st[49] + i]
    i += 1
  failed += mc_expect("pair-only cannot reduce", ffpc_reduce(work, words, capacity, rank, 0, 1, 2) == loaded + 1)
  parity_words = ffw_verify_scratch_words(n, m, p) ## i64
  parity = i64[parity_words]
  cleaned = ffpc_gate_best(st, n, m, p, rectangular, work, words, parity, parity_words) ## i64
  failed += mc_expect("live matrix gate reduces 3 to 2", cleaned == loaded && st[7] == loaded)
  failed += mc_expect("density delta rebased", ffw_current_bits(st) == st[36] + st[64])
  i = 0
  while i < st[63]
    allowed = 0 ## i64
    if i == 7 || i == 10 || i == 14 || i == 24 || i == 25 || i == 29 || i == 33 || i == 36 || i == 38 || i == 64
      allowed = 1
    if i >= st[47] && i < st[50]
      allowed = 1
    if allowed == 0 && st[i] != before[i]
      failed += mc_expect("current walk, RNG and chains unchanged", false)
    i += 1
  failed += mc_expect("idempotent live gate", ffpc_gate_best(st, n, m, p, rectangular, work, words, parity, parity_words) == cleaned)
  if rectangular == 0
    failed += mc_expect("current and best verified", ffw_verify_current_exact(st, n) == 1 && ffw_verify_best_exact(st, n) == 1)
  else
    failed += mc_expect("rectangular current and best verified", ffr_verify_current_exact(st, n, m, p) == 1 && ffr_verify_best_exact(st, n, m, p) == 1)
  failed

failures = mc_gate_case(2, 2, 2, 0) ## i64
failures += mc_gate_case(5, 5, 5, 0)
failures += mc_gate_case(2, 3, 4, 1)
capacity = 256 ## i64
words = ffmc_scratch_words(capacity) ## i64
work = i64[words]
work[0] = 1
work[capacity] = 2
work[2 * capacity] = 4
failures += mc_expect("undersized slab rejected", ffmc_reduce(work, words - 1, capacity, 1) < 0)
failures += mc_expect("bad axis rejected", ffmc_refactor(work, words, capacity, 1, 3, 0) < 0)
failures += mc_expect("bad order rejected", ffmc_refactor(work, words, capacity, 1, 0, 2) < 0)
failures += mc_expect("invalid calls preserve source", work[0] == 1 && work[capacity] == 2 && work[2 * capacity] == 4)
work[0] = 0
failures += mc_expect("zero factor rejected", ffmc_reduce(work, words, capacity, 1) < 0)
work[0] = 0 - 1
failures += mc_expect("sign bit rejected", ffmc_reduce(work, words, capacity, 1) < 0)
failures += mc_expect("empty allowed", ffmc_reduce(work, words, capacity, 0) == 0)
failures += mc_expect("wide highest bit", ffmc_high_bit(1 << 62) == 62)

# Test oracle protocol: compress and all six one-axis neutral transformations.
# Repeated fixed factors, large groups, duplicates, high bits, and rank ties.
if ARGV.size() > 0 && ARGV[0] == "--parity"
  seed = 1709 ## i64
  trial = 0 ## i64
  while trial < 100
    rank = 1 + ((trial * 37) % capacity) ## i64
    original = i64[3 * capacity]
    i = 0 ## i64
    while i < rank
      axis = 0 ## i64
      while axis < 3
        seed = (seed * 1103515245 + 12345) & 2147483647
        value = 1 + ((seed >> 9) % 7) ## i64
        if trial % 4 == 0
          value = value | (value << 45)
        if trial % 4 == 1 && axis == trial % 3
          value = 1 + ((seed >> 8) % 2147483646)
        if trial % 4 == 2
          value = value | (1 << (i % 63))
        original[axis * capacity + i] = value
        axis += 1
      i += 1
    mode = 0 ## i64
    while mode < 7
      << "CASE " + trial.to_s() + " " + mode.to_s()
      i = 0
      while i < rank
        work[i] = original[i]
        work[capacity + i] = original[capacity + i]
        work[2 * capacity + i] = original[2 * capacity + i]
        << "IN " + work[i].to_s() + " " + work[capacity + i].to_s() + " " + work[2 * capacity + i].to_s()
        i += 1
      reduced = 0 ## i64
      if mode == 0
        reduced = ffmc_reduce(work, words, capacity, rank)
      else
        reduced = ffmc_refactor(work, words, capacity, rank, (mode - 1) / 2, (mode - 1) % 2)
      failures += mc_expect("rank cannot increase", reduced >= 0 && reduced <= rank)
      i = 0
      while i < reduced
        << "OUT " + work[i].to_s() + " " + work[capacity + i].to_s() + " " + work[2 * capacity + i].to_s()
        i += 1
      << "END " + reduced.to_s()
      if mode == 0
        failures += mc_expect("matrix fixed point", ffmc_reduce(work, words, capacity, reduced) == reduced)
      mode += 1
    trial += 1

if failures > 0
  exit(1)
<< "PASS matrix cleanup: live exact square/rectangular gate, pair-free reduction, state preservation and input bounds"
