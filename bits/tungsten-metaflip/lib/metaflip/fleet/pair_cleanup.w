# Exact algebraic cleanup on the serial candidate-admission path.
# For each axis, XOR all factors with the same other two factors, then repeat
# the axis sweep to a fixed point, followed by shared-factor matrix reduction.
# The raw pair routine matches offline reduce_pairs(0,1,2), as a term set;
# matrix reduction matches compress_terms. Neither is a minimum-rank oracle.
# Scratch and parity slabs belong to the coordinator, never to live workers.

use matrix_cleanup

-> ffpc_hash_capacity(capacity) (i64) i64
  slots = 16 ## i64
  while slots < capacity * 2
    slots *= 2
  slots

-> ffpc_scratch_words(capacity) (i64) i64
  ffmc_scratch_words(capacity)

# Raw slab: three capacity-sized factor arrays, followed by open-addressed
# group indices. Validate before mutation; callers supply explicit capacities
# because typed-array size is not a safe native/raw boundary. The full gate
# requests a larger slab so it can reuse the same storage for matrix cleanup.
-> ffpc_reduce(work, words, capacity, rank, a0, a1, a2) (i64[] i64 i64 i64 i64 i64 i64) i64
  if capacity < 1 || rank < 0 || rank > capacity
    return 0 - 1
  if words < 3 * capacity + ffpc_hash_capacity(capacity)
    return 0 - 1
  if a0 < 0 || a0 > 2 || a1 < 0 || a1 > 2 || a2 < 0 || a2 > 2 || a0 == a1 || a0 == a2 || a1 == a2
    return 0 - 1
  i = 0 ## i64
  while i < rank
    if work[i] <= 0 || work[capacity + i] <= 0 || work[2 * capacity + i] <= 0
      return 0 - 1
    i += 1
  slots = ffpc_hash_capacity(capacity) ## i64
  mask = slots - 1 ## i64
  buckets = 3 * capacity ## i64
  changed = 1 ## i64
  while changed != 0
    before = rank ## i64
    pass = 0 ## i64
    while pass < 3
      axis = a0 ## i64
      if pass == 1
        axis = a1
      if pass == 2
        axis = a2
      left = 0 ## i64
      right = 2 * capacity ## i64
      if axis == 0
        left = capacity
      if axis == 2
        right = capacity
      varying = axis * capacity ## i64
      i = 0
      while i < slots
        work[buckets + i] = 0
        i += 1
      groups = 0 ## i64
      i = 0
      while i < rank
        x = work[left + i] ## i64
        y = work[right + i] ## i64
        value = work[varying + i] ## i64
        bucket = ffw_term_zobrist(x, y, 1) & mask ## i64
        found = 0 - 1 ## i64
        while found < 0
          entry = work[buckets + bucket] - 1 ## i64
          if entry < 0
            # groups <= i: no unread input is overwritten.
            work[left + groups] = x
            work[right + groups] = y
            work[varying + groups] = value
            work[buckets + bucket] = groups + 1
            groups += 1
            found = 1
          else
            if work[left + entry] == x && work[right + entry] == y
              work[varying + entry] = work[varying + entry] ^ value
              found = 1
            else
              bucket = (bucket + 1) & mask
        i += 1
      # A zero group can revive later in the same pass. Drop it only after
      # every original term has contributed, then compact all three arrays.
      kept = 0 ## i64
      i = 0
      while i < groups
        if work[varying + i] != 0
          work[kept] = work[i]
          work[capacity + kept] = work[capacity + i]
          work[2 * capacity + kept] = work[2 * capacity + i]
          kept += 1
        i += 1
      rank = kept
      pass += 1
    changed = 0
    if rank < before
      changed = 1
  rank

# Returns the exact cleaned rank, or -1 on rejection. No candidate payload is
# changed until the independent full tensor gate passes. On a reduction, only
# best terms and improvement telemetry change: current slots/chains, RNG,
# moves, and current Zobrist remain intact. Rebase the density delta so the
# next worker epoch still measures current density against the new best.
-> ffpc_gate_best(st, n, m, p, rectangular, work, words, parity, parity_words) (i64[] i64 i64 i64 i64 i64[] i64 i64[] i64) i64
  st[29] = st[29] + 1
  st[38] = 0
  valid = ffw_valid(st) ## i64
  if rectangular == 0
    if n != m || n != p || st[2] != n || st[3] != n * n
      valid = 0
  else
    if ffr_valid(st) == 0 || ffr_shape_n(st) != n || ffr_shape_m(st) != m || ffr_shape_p(st) != p
      valid = 0
  rank = st[7] ## i64
  capacity = st[4] ## i64
  if valid == 0 || rank < 1 || rank > capacity || words < ffpc_scratch_words(capacity)
    st[30] = st[30] + 1
    return 0 - 1
  umask = ffr_factor_mask(n * m) ## i64
  vmask = ffr_factor_mask(m * p) ## i64
  wmask = ffr_factor_mask(n * p) ## i64
  i = 0 ## i64
  while i < rank
    u = st[st[47] + i] ## i64
    v = st[st[48] + i] ## i64
    w = st[st[49] + i] ## i64
    # Check the source masks, not just the reduced output: malformed bits
    # must not be hidden by a cancellation during cleanup.
    if u <= 0 || v <= 0 || w <= 0 || (u & umask) != u || (v & vmask) != v || (w & wmask) != w
      st[30] = st[30] + 1
      return 0 - 1
    work[i] = u
    work[capacity + i] = v
    work[2 * capacity + i] = w
    i += 1
  cleaned = ffpc_reduce(work, words, capacity, rank, 0, 1, 2) ## i64
  if cleaned > 0
    cleaned = ffmc_reduce(work, words, capacity, cleaned)
  if cleaned < 1 || ffw_support_tensor_error_scratch(work, 0, capacity, 2 * capacity, 0 - 1, cleaned, n, m, p, parity, parity_words) != 0
    st[30] = st[30] + 1
    return 0 - 1
  st[38] = 1
  if cleaned < rank
    old_bits = st[36] ## i64
    i = 0
    while i < cleaned
      st[st[47] + i] = work[i]
      st[st[48] + i] = work[capacity + i]
      st[st[49] + i] = work[2 * capacity + i]
      i += 1
    st[7] = cleaned
    st[36] = ffw_view_bits(st, st[47], st[48], st[49], 0 - 1, cleaned)
    st[64] = st[64] + old_bits - st[36]
    st[24] = st[24] + 1
    st[25] = st[25] + 1
    st[33] = st[33] + 1
    st[10] = st[40]
    st[14] = st[13] + st[18]
  cleaned

-> ffpc_gate_square_best(st, n, work, words, parity, parity_words) (i64[] i64 i64[] i64 i64[] i64) i64
  ffpc_gate_best(st, n, n, n, 0, work, words, parity, parity_words)

-> ffpc_gate_rect_best(st, n, m, p, work, words, parity, parity_words) (i64[] i64 i64 i64 i64[] i64 i64[] i64) i64
  ffpc_gate_best(st, n, m, p, 1, work, words, parity, parity_words)
