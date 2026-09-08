use ../lib/metaflip/fleet/pair_cleanup

failures = 0 ## i64

-> pc_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL pair cleanup: " + label
    return 1
  0

-> pc_state_case(n, m, p, rectangular) (i64 i64 i64 i64) i64
  failures = 0 ## i64
  capacity = ffw_default_capacity(n) ## i64
  if rectangular != 0
    capacity = ffr_default_capacity(n, m, p)
  st = i64[ffw_state_size(capacity)]
  loaded = 0 ## i64
  if rectangular == 0
    loaded = ffw_init_naive_cap(st, n, capacity, 17, 8, 3, 1000, 2000)
  else
    loaded = ffr_init_naive_cap(st, n, m, p, capacity, 17, 8, 3, 1000, 2000)
  failures += pc_expect("naive control exact", loaded == n * m * p)
  # Split (1,1,1) into three terms. Axis 1 must merge before axis 0 can
  # merge, so default order 0,1,2 needs another complete sweep.
  rank = ffw_toggle(st, 1, 1, 1, st[6]) ## i64
  rank = ffw_toggle(st, 2, 1, 1, rank)
  rank = ffw_toggle(st, 3, 2, 1, rank)
  rank = ffw_toggle(st, 3, 3, 1, rank)
  st[6] = rank
  z = ffw_copy_current_to_best(st) ## i64
  failures += pc_expect("raw endpoint can lose rank comparison", rank == loaded + 2)
  # Keep a distinct current trajectory with one further exact split.
  rank = ffw_toggle(st, 3, 3, 1, rank)
  rank = ffw_toggle(st, 3, 3, 2, rank)
  rank = ffw_toggle(st, 3, 3, 3, rank)
  st[6] = rank
  st[64] = ffw_current_bits(st) - st[36]
  st[42] = st[42] | 2
  st[37] = 0
  i = 0 ## i64
  while i < rank
    slot = st[st[50] + i] ## i64
    st[37] = st[37] ^ ffw_term_zobrist(st[st[44] + slot], st[st[45] + slot], st[st[46] + slot])
    i += 1
  before = i64[ffw_state_size(capacity)]
  i = 0
  while i < st[63]
    before[i] = st[i]
    i += 1
  words = ffpc_scratch_words(capacity) ## i64
  work = i64[words]
  parity_words = ffw_verify_scratch_words(n, m, p) ## i64
  parity = i64[parity_words]
  cleaned = ffpc_gate_best(st, n, m, p, rectangular, work, words, parity, parity_words) ## i64
  failures += pc_expect("fixed point finds full multi-pass drop", cleaned == loaded && st[7] == loaded)
  failures += pc_expect("raw-rank rejection would lose an improvement", before[7] > loaded + 1 && cleaned < loaded + 1)
  failures += pc_expect("current density delta rebased", ffw_current_bits(st) == st[36] + st[64])
  i = 0
  while i < st[63]
    allowed = 0 ## i64
    if i == 7 || i == 10 || i == 14 || i == 24 || i == 25 || i == 29 || i == 33 || i == 36 || i == 38 || i == 64
      allowed = 1
    if i >= st[47] && i < st[50]
      allowed = 1
    if allowed == 0 && st[i] != before[i]
      failures += pc_expect("current slots, chains, RNG, moves and hash unchanged", false)
    i += 1
  # An already reduced endpoint is byte-stable apart from exact telemetry.
  i = 0
  while i < st[63]
    before[i] = st[i]
    i += 1
  repeated = ffpc_gate_best(st, n, m, p, rectangular, work, words, parity, parity_words) ## i64
  failures += pc_expect("idempotent rank", repeated == cleaned)
  i = 0
  while i < st[63]
    if i != 29 && i != 38 && st[i] != before[i]
      failures += pc_expect("idempotent payload and telemetry", false)
    i += 1
  # Reject a structurally legal but wrong tensor without committing any
  # scratch reduction. A second rejection covers undersized parity storage.
  st[st[47]] = st[st[47]] ^ 2
  i = 0
  while i < st[63]
    before[i] = st[i]
    i += 1
  rejected = ffpc_gate_best(st, n, m, p, rectangular, work, words, parity, parity_words) ## i64
  failures += pc_expect("corrupt tensor rejected", rejected < 0)
  i = 0
  while i < st[63]
    if i != 29 && i != 30 && i != 38 && st[i] != before[i]
      failures += pc_expect("rejection is transactional", false)
    i += 1
  st[st[47]] = st[st[47]] ^ 2
  failures += pc_expect("short parity rejected", ffpc_gate_best(st, n, m, p, rectangular, work, words, parity, 0) < 0)
  failures += pc_expect("short workspace rejected", ffpc_gate_best(st, n, m, p, rectangular, work, words - 1, parity, parity_words) < 0)
  failures += pc_expect("reusable slab after rejection", ffpc_gate_best(st, n, m, p, rectangular, work, words, parity, parity_words) == cleaned)
  if rectangular == 0
    failures += pc_expect("square current and best remain exact", ffw_verify_current_exact(st, n) == 1 && ffw_verify_best_exact(st, n) == 1)
    z = ffw_walk(st, 500)
    failures += pc_expect("square walk continues from debt", ffw_verify_current_exact(st, n) == 1 && ffw_verify_best_exact(st, n) == 1)
  else
    failures += pc_expect("rectangular current and best remain exact", ffr_verify_current_exact(st, n, m, p) == 1 && ffr_verify_best_exact(st, n, m, p) == 1)
    z = ffr_walk(st, 500)
    failures += pc_expect("rectangular walk continues from debt", ffr_verify_current_exact(st, n, m, p) == 1 && ffr_verify_best_exact(st, n, m, p) == 1)
  failures

failures += pc_state_case(2, 2, 2, 0)
failures += pc_state_case(5, 5, 5, 0)
failures += pc_state_case(2, 3, 4, 1)

capacity = 256 ## i64
words = ffpc_scratch_words(capacity) ## i64
work = i64[words]
work[0] = 1
work[capacity] = 2
work[2 * capacity] = 4
failures += pc_expect("bad axis order rejected", ffpc_reduce(work, words, capacity, 1, 0, 0, 2) < 0)
failures += pc_expect("invalid order does not mutate input", work[0] == 1 && work[capacity] == 2 && work[2 * capacity] == 4)
work[1] = 1
work[capacity + 1] = 2
work[2 * capacity + 1] = 4
failures += pc_expect("duplicate cancellation", ffpc_reduce(work, words, capacity, 2, 0, 1, 2) == 0)
failures += pc_expect("empty fixed point", ffpc_reduce(work, words, capacity, 0, 0, 1, 2) == 0)
work[0] = 0
failures += pc_expect("zero input rejected", ffpc_reduce(work, words, capacity, 1, 0, 1, 2) < 0)

# These invalid high-bit terms cancel to zero and would evade an output-only
# mask check. Admission must reject the original malformed representation.
invalid = i64[ffw_state_size(capacity)]
z = ffw_init_naive_cap(invalid, 2, capacity, 17, 0, 1, 1, 1) ## i64
invalid[invalid[47] + 8] = 16
invalid[invalid[48] + 8] = 1
invalid[invalid[49] + 8] = 1
invalid[invalid[47] + 9] = 16
invalid[invalid[48] + 9] = 1
invalid[invalid[49] + 9] = 1
invalid[7] = 10
small_parity = i64[1]
failures += pc_expect("cleanup cannot hide invalid source masks", ffpc_gate_square_best(invalid, 2, work, words, small_parity, 1) < 0 && invalid[7] == 10)

# A machine-readable corpus for the independent Python/offline parity test.
# Input order, collisions, zero/reviving groups, and all six axis orders are
# exercised. Large masks use the signed-i64 envelope, not Python-only widths.
if ARGV.size() > 0 && ARGV[0] == "--parity"
  seed = 1709 ## i64
  trial = 0 ## i64
  while trial < 80
    rank = 1 + ((trial * 37) % capacity) ## i64
    original = i64[3 * capacity]
    i = 0
    while i < rank
      axis = 0 ## i64
      while axis < 3
        seed = (seed * 1103515245 + 12345) & 2147483647
        value = 1 + ((seed >> 9) % 7) ## i64
        if trial % 4 == 0
          value = value | (value << 45)
        original[axis * capacity + i] = value
        axis += 1
      i += 1
    a0 = 0 ## i64
    while a0 < 3
      a1 = 0 ## i64
      while a1 < 3
        if a0 != a1
          a2 = 3 - a0 - a1 ## i64
          << "CASE " + trial.to_s() + " " + a0.to_s() + " " + a1.to_s() + " " + a2.to_s()
          i = 0
          while i < rank
            work[i] = original[i]
            work[capacity + i] = original[capacity + i]
            work[2 * capacity + i] = original[2 * capacity + i]
            << "IN " + work[i].to_s() + " " + work[capacity + i].to_s() + " " + work[2 * capacity + i].to_s()
            i += 1
          reduced = ffpc_reduce(work, words, capacity, rank, a0, a1, a2) ## i64
          i = 0
          while i < reduced
            << "OUT " + work[i].to_s() + " " + work[capacity + i].to_s() + " " + work[2 * capacity + i].to_s()
            i += 1
          << "END " + reduced.to_s()
        a1 += 1
      a0 += 1
    trial += 1

if failures > 0
  exit(1)
<< "PASS pair cleanup: exact square/rectangular admission, fixed point, transaction, density and continuation"
