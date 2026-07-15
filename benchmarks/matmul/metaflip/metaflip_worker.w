# Runtime-generic pure-Tungsten metaflip worker for square matrix tensors.
#
# This module is intentionally coordinator-free: it owns one self-describing
# flat i64[] state and performs no Python/runtime subprocess work.  Tensor size
# (2 <= n <= 7), rank, term capacity, and hash capacity are runtime values.
# n <= 7 is the exact signed-i64 factor-mask envelope: n*n <= 49 bits.
#
# Stable public surface (all symbols are prefixed to coexist with the legacy
# generated flipfleet_walker module):
#
#   ffw_default_capacity(n)
#   ffw_state_size(capacity)
#   ffw_default_state_size(n)
#   ff_worker_state_size(n)                 # convenience alias
#   ffw_init_naive(st,n,seed,dslack,cycles,workq,wanderq)
#   ffw_init_naive_cap(st,n,cap,seed,dslack,cycles,workq,wanderq)
#   ffw_init_terms(st,us,vs,ws,rank,n,seed,dslack,cycles,workq,wanderq)
#   ffw_init_terms_cap(st,us,vs,ws,rank,n,cap,seed,dslack,cycles,workq,wanderq)
#   ffw_load_scheme(st,path,n,seed,dslack,cycles,workq,wanderq)
#   ffw_load_scheme_cap(st,path,n,cap,seed,dslack,cycles,workq,wanderq)
#   ffw_reseed_from(dst,src,seed)            # dst and src must be distinct
#   ffw_walk / ffw_work / ffw_wander(st,steps)
#   ffw_verify_best_exact / ffw_verify_current_exact(st,n)
#   ffw_adopt_current(st,allow_density_tie)
#   ffw_export_best / ffw_export_current(st,us,vs,ws)
#   ffw_dump_best / ffw_dump_current(st,path)
#
# The exhaustive verifier checks every one of the n^6 coefficients.  It runs
# at imports and every best adoption, not in the hot proposal loop.


# ---- layout ---------------------------------------------------------------
# Header indices 0..63 are stable telemetry/configuration ABI.
# Array offsets are stored in header slots 44..61, so hot code never rebuilds
# layout arithmetic.  The payload contains 15 capacity-sized arrays and three
# power-of-two hash-head arrays.

-> ffw_hash_capacity(capacity) (i64) i64
  hc = 16 ## i64
  target = capacity * 8 ## i64
  while hc < target
    hc = hc * 2
  hc

-> ffw_state_size(capacity) (i64) i64
  cap = capacity ## i64
  if cap < 1
    cap = 1
  64 + cap * 15 + ffw_hash_capacity(cap) * 3

-> ffw_default_capacity(n) (i64) i64
  # Naive rank plus room for long variable-rank shoulder walks.
  n * n * n + 4 * n * n + 64

-> ffw_default_state_size(n) (i64) i64
  ffw_state_size(ffw_default_capacity(n))

-> ff_worker_state_size(n) (i64) i64
  ffw_default_state_size(n)

-> ffw_layout(st, n, capacity) (i64[] i64 i64) i64
  ok = 1 ## i64
  dim = n * n ## i64
  if n < 2
    ok = 0
  if n > 7
    ok = 0
  if capacity < 4
    ok = 0
  hc = ffw_hash_capacity(capacity) ## i64
  need = 64 + capacity * 15 + hc * 3 ## i64
  # Caller allocates ffw_state_size(capacity) words.  Typed-array `.size()`
  # currently crosses an unsafe boxed boundary inside native worker functions;
  # keep the layout fully raw and expose st[63] for coordinator assertions.
  if ok == 1
    hi = 0 ## i64
    while hi < 64
      st[hi] = 0
      hi += 1
    st[0] = 1179014961                 # "FFW1"
    st[1] = 1
    st[2] = n
    st[3] = dim
    st[4] = capacity
    st[5] = hc
    st[6] = 0                          # current rank
    st[7] = 0 - 1                      # best rank (unadopted)
    st[43] = hc - 1                    # hash mask
    off = 64 ## i64
    st[44] = off                       # current U
    off += capacity
    st[45] = off                       # current V
    off += capacity
    st[46] = off                       # current W
    off += capacity
    st[47] = off                       # best U
    off += capacity
    st[48] = off                       # best V
    off += capacity
    st[49] = off                       # best W
    off += capacity
    st[50] = off                       # live rank-index -> slot
    off += capacity
    st[51] = off                       # slot -> rank-index
    off += capacity
    st[52] = off                       # free slot stack
    off += capacity
    st[53] = off                       # U hash heads
    off += hc
    st[54] = off                       # V hash heads
    off += hc
    st[55] = off                       # W hash heads
    off += hc
    st[56] = off                       # U next links
    off += capacity
    st[57] = off                       # U previous links
    off += capacity
    st[58] = off                       # V next links
    off += capacity
    st[59] = off                       # V previous links
    off += capacity
    st[60] = off                       # W next links
    off += capacity
    st[61] = off                       # W previous links
    off += capacity
    st[63] = off                       # required state words
  ok

-> ffw_valid(st) (i64[]) i64
  ok = 1 ## i64
  if st[0] != 1179014961
    ok = 0
  if st[1] != 1
    ok = 0
  if st[2] < 2
    ok = 0
  if st[2] > 7
    ok = 0
  if st[4] < 4
    ok = 0
  ok

-> ffw_clear_current(st) (i64[]) i64
  cap = st[4] ## i64
  hc = st[5] ## i64
  hz = 0 ## i64
  while hz < hc
    st[st[53] + hz] = 0
    st[st[54] + hz] = 0
    st[st[55] + hz] = 0
    hz += 1
  i = 0 ## i64
  while i < cap
    st[st[52] + i] = cap - 1 - i
    st[st[51] + i] = 0 - 1
    i += 1
  st[6] = 0
  st[37] = 0
  st[62] = cap
  1

-> ffw_seed_rng(st, seed) (i64[] i64) i64
  seedv = seed & 4611686018427387903 ## i64
  inc = seedv + seedv + 1 ## i64
  rng = (seedv ^ 1442695040888963407) & 9223372036854775807 ## i64
  rng = (rng * 6364136223846793005 + inc) & 9223372036854775807
  rng = (rng * 6364136223846793005 + inc) & 9223372036854775807
  st[8] = rng
  st[9] = inc
  1

-> ffw_prepare(st, n, capacity, seed, dslack, cycles, workq, wanderq) (i64[] i64 i64 i64 i64 i64 i64 i64) i64
  ok = ffw_layout(st, n, capacity) ## i64
  if ok == 1
    z = ffw_clear_current(st) ## i64
    z = ffw_seed_rng(st, seed)
    cv = cycles ## i64
    if cv < 1
      cv = 1
    wq = workq ## i64
    if wq < 1
      wq = 1
    vq = wanderq ## i64
    if vq < 1
      vq = 1
    ds = dslack ## i64
    if ds < 0
      ds = 0
    st[10] = 1 + ((seed & 4611686018427387903) % 4) # band
    st[11] = 7                         # work/wander threshold
    st[12] = 0                         # sawtooth wraps
    st[13] = 0                         # moves
    st[14] = wq                        # next zone change
    st[15] = cv
    st[16] = 0                         # cycled
    st[17] = ds
    st[18] = wq
    st[19] = vq
    st[36] = 0                         # best bits
    st[37] = 0                         # rolling current-term Zobrist digest
    st[38] = 0                         # last exact result
    st[40] = st[10]                    # band start
    st[41] = 60                        # maximum band
    st[42] = 0                         # last mode: 0 work, 1 wander
  ok


# ---- hashed XOR set of rank-one terms ------------------------------------

-> ffw_hash(st, key) (i64[] i64) i64
  y = key ^ (key >> 21) ^ (key >> 42) ## i64
  ((y * 2654435761) >> 13) & st[43]

# Order-independent live-state fingerprint.  It is deliberately telemetry,
# never an exactness proof: XOR lets ffw_toggle maintain it in O(1), including
# rejected moves whose reverse toggles restore the old value.
-> ffw_term_zobrist(u, v, w) (i64 i64 i64) i64
  # Telemetry hash, optimized for the accepted-state measurement lane.  The
  # masking makes the intended wrapping arithmetic explicit to debug builds.
  x = (u * 6364136223846793005 + v * 1442695040888963407 + w * 2862933555777941757) & 9223372036854775807 ## i64
  x = x ^ (x >> 29)
  x = (x * 3202034522624059733) & 9223372036854775807
  x ^ (x >> 31)

-> ffw_chain_link(st, head, nexto, prevo, slot, key) (i64[] i64 i64 i64 i64 i64) i64
  bucket = ffw_hash(st, key) ## i64
  old = st[head + bucket] ## i64
  st[nexto + slot] = old
  st[prevo + slot] = 0
  if old != 0
    st[prevo + old - 1] = slot + 1
  st[head + bucket] = slot + 1
  1

-> ffw_chain_unlink(st, head, nexto, prevo, slot, key) (i64[] i64 i64 i64 i64 i64) i64
  nn = st[nexto + slot] ## i64
  pp = st[prevo + slot] ## i64
  if pp == 0
    st[head + ffw_hash(st, key)] = nn
  if pp != 0
    st[nexto + pp - 1] = nn
  if nn != 0
    st[prevo + nn - 1] = pp
  1

-> ffw_find_term(st, u, v, w) (i64[] i64 i64 i64) i64
  found = 0 - 1 ## i64
  c = st[st[53] + ffw_hash(st, u)] ## i64
  while c != 0
    slot = c - 1 ## i64
    if st[st[44] + slot] == u
      if st[st[45] + slot] == v
        if st[st[46] + slot] == w
          found = slot
    c = st[st[56] + slot]
    if found >= 0
      c = 0
  found

-> ffw_toggle(st, u, v, w, rank) (i64[] i64 i64 i64 i64) i64
  result = rank ## i64
  if u != 0
    if v != 0
      if w != 0
        found = ffw_find_term(st, u, v, w) ## i64
        if found < 0
          free_top = st[62] ## i64
          if free_top > 0
            slot = st[st[52] + free_top - 1] ## i64
            st[62] = free_top - 1
            st[st[44] + slot] = u
            st[st[45] + slot] = v
            st[st[46] + slot] = w
            z = ffw_chain_link(st, st[53], st[56], st[57], slot, u) ## i64
            z = ffw_chain_link(st, st[54], st[58], st[59], slot, v)
            z = ffw_chain_link(st, st[55], st[60], st[61], slot, w)
            st[st[50] + rank] = slot
            st[st[51] + slot] = rank
            if (st[42] & 2) != 0
              st[37] = st[37] ^ ffw_term_zobrist(u, v, w)
            result = rank + 1
          if free_top <= 0
            st[39] = st[39] + 1
        if found >= 0
          z = ffw_chain_unlink(st, st[53], st[56], st[57], found, u) ## i64
          z = ffw_chain_unlink(st, st[54], st[58], st[59], found, v)
          z = ffw_chain_unlink(st, st[55], st[60], st[61], found, w)
          position = st[st[51] + found] ## i64
          last_slot = st[st[50] + rank - 1] ## i64
          st[st[50] + position] = last_slot
          st[st[51] + last_slot] = position
          free_top = st[62] ## i64
          st[st[52] + free_top] = found
          st[62] = free_top + 1
          st[st[51] + found] = 0 - 1
          if (st[42] & 2) != 0
            st[37] = st[37] ^ ffw_term_zobrist(u, v, w)
          result = rank - 1
  result

-> ffw_chain_count_min(st, head, nexto, factoro, key, excluded, min_slot) (i64[] i64 i64 i64 i64 i64 i64) i64
  count = 0 ## i64
  c = st[head + ffw_hash(st, key)] ## i64
  while c != 0
    slot = c - 1 ## i64
    if st[factoro + slot] == key
      if slot != excluded && slot >= min_slot
        count += 1
    c = st[nexto + slot]
  count

-> ffw_chain_pick_min(st, head, nexto, factoro, key, excluded, want, min_slot) (i64[] i64 i64 i64 i64 i64 i64 i64) i64
  found = 0 - 1 ## i64
  seen = 0 ## i64
  c = st[head + ffw_hash(st, key)] ## i64
  while c != 0
    slot = c - 1 ## i64
    if st[factoro + slot] == key
      if slot != excluded && slot >= min_slot
        if seen == want
          found = slot
        seen += 1
    c = st[nexto + slot]
    if found >= 0
      c = 0
  found

-> ffw_pick_partner_min(st, axis, slot, random_word, min_slot) (i64[] i64 i64 i64 i64) i64
  head = st[53] ## i64
  nexto = st[56] ## i64
  factoro = st[44] ## i64
  if axis == 1
    head = st[54]
    nexto = st[58]
    factoro = st[45]
  if axis == 2
    head = st[55]
    nexto = st[60]
    factoro = st[46]
  key = st[factoro + slot] ## i64
  count = ffw_chain_count_min(st, head, nexto, factoro, key, slot, min_slot) ## i64
  found = 0 - 1 ## i64
  if count > 0
    want = (random_word * count) >> 31 ## i64
    found = ffw_chain_pick_min(st, head, nexto, factoro, key, slot, want, min_slot)
  found

-> ffw_pick_partner(st, axis, slot, random_word) (i64[] i64 i64 i64) i64
  ffw_pick_partner_min(st, axis, slot, random_word, 0)


# ---- exactness, density, adoption ----------------------------------------

-> ffw_popcount(value) (i64) i64
  count = 0 ## i64
  x = value ## i64
  while x != 0
    x = x & (x - 1)
    count += 1
  count

-> ffw_view_bits(st, uo, vo, wo, liveo, rank) (i64[] i64 i64 i64 i64 i64) i64
  bits = 0 ## i64
  i = 0 ## i64
  while i < rank
    slot = i ## i64
    if liveo >= 0
      slot = st[liveo + i]
    bits += ffw_popcount(st[uo + slot])
    bits += ffw_popcount(st[vo + slot])
    bits += ffw_popcount(st[wo + slot])
    i += 1
  bits

# Return zero for an exact tensor, a positive 1-based coefficient index for
# the first mismatch, or a negative structural error.  Early mismatch exit is
# both diagnostic and important when rejecting a malformed external seed.
-> ffw_verify_view_error(st, uo, vo, wo, liveo, rank, n) (i64[] i64 i64 i64 i64 i64 i64) i64
  error = 0 ## i64
  dim = n * n ## i64
  one = 1 ## i64
  factor_mask = (one << dim) - 1 ## i64
  if n < 2
    error = 0 - 1
  if n > 7
    error = 0 - 2
  if rank < 1
    error = 0 - 3
  if rank > st[4]
    error = 0 - 4
  t = 0 ## i64
  while t < rank && error == 0
    slot = t ## i64
    if liveo >= 0
      slot = st[liveo + t]
    u = st[uo + slot] ## i64
    v = st[vo + slot] ## i64
    w = st[wo + slot] ## i64
    if u <= 0
      error = 0 - 10
    if v <= 0
      error = 0 - 11
    if w <= 0
      error = 0 - 12
    if (u & factor_mask) != u
      error = 0 - 13
    if (v & factor_mask) != v
      error = 0 - 14
    if (w & factor_mask) != w
      error = 0 - 15
    t += 1
  ai = 0 ## i64
  while ai < dim && error == 0
    bi = 0 ## i64
    while bi < dim && error == 0
      ci = 0 ## i64
      while ci < dim && error == 0
        got = 0 ## i64
        t = 0
        while t < rank
          slot = t
          if liveo >= 0
            slot = st[liveo + t]
          if ((st[uo + slot] >> ai) & 1) == 1
            if ((st[vo + slot] >> bi) & 1) == 1
              if ((st[wo + slot] >> ci) & 1) == 1
                got = got ^ 1
          t += 1
        arow = ai / n ## i64
        acol = ai % n ## i64
        brow = bi / n ## i64
        bcol = bi % n ## i64
        crow = ci / n ## i64
        ccol = ci % n ## i64
        want = 0 ## i64
        if acol == brow
          if arow == crow
            if bcol == ccol
              want = 1
        if got != want
          error = 1 + (ai * dim + bi) * dim + ci
        ci += 1
      bi += 1
    ai += 1
  error

-> ffw_verify_view_exact(st, uo, vo, wo, liveo, rank, n) (i64[] i64 i64 i64 i64 i64 i64) i64
  result = 0 ## i64
  if ffw_verify_view_error(st, uo, vo, wo, liveo, rank, n) == 0
    result = 1
  result

-> ffw_current_exact_error(st, n) (i64[] i64) i64
  ffw_verify_view_error(st, st[44], st[45], st[46], st[50], st[6], n)

-> ffw_best_exact_error(st, n) (i64[] i64) i64
  ffw_verify_view_error(st, st[47], st[48], st[49], 0 - 1, st[7], n)

-> ffw_verify_current_exact(st, n) (i64[] i64) i64
  ok = 0 ## i64
  st[29] = st[29] + 1
  if ffw_valid(st) == 1
    if n == st[2]
      ok = ffw_verify_view_exact(st, st[44], st[45], st[46], st[50], st[6], n)
  st[38] = ok
  if ok == 0
    st[30] = st[30] + 1
  ok

-> ffw_verify_best_exact(st, n) (i64[] i64) i64
  ok = 0 ## i64
  st[29] = st[29] + 1
  if ffw_valid(st) == 1
    if n == st[2]
      if st[7] > 0
        ok = ffw_verify_view_exact(st, st[47], st[48], st[49], 0 - 1, st[7], n)
  st[38] = ok
  if ok == 0
    st[30] = st[30] + 1
  ok

-> ffw_copy_current_to_best(st) (i64[]) i64
  rank = st[6] ## i64
  i = 0 ## i64
  while i < rank
    slot = st[st[50] + i] ## i64
    st[st[47] + i] = st[st[44] + slot]
    st[st[48] + i] = st[st[45] + slot]
    st[st[49] + i] = st[st[46] + slot]
    i += 1
  st[7] = rank
  st[36] = ffw_view_bits(st, st[47], st[48], st[49], 0 - 1, rank)
  rank

-> ffw_restore_best(st) (i64[]) i64
  rank = st[7] ## i64
  z = ffw_clear_current(st) ## i64
  current = 0 ## i64
  i = 0 ## i64
  while i < rank
    current = ffw_toggle(st, st[st[47] + i], st[st[48] + i], st[st[49] + i], current)
    i += 1
  st[6] = current
  st[26] = st[26] + 1
  current

-> ffw_adopt_current(st, allow_density_tie) (i64[] i64) i64
  result = 0 ## i64
  rank = st[6] ## i64
  best = st[7] ## i64
  bits = ffw_view_bits(st, st[44], st[45], st[46], st[50], rank) ## i64
  useful = 0 ## i64
  if best < 0
    useful = 1
  if best >= 0
    if rank < best
      useful = 1
    if allow_density_tie != 0
      if rank == best
        if bits < st[36]
          useful = 1
  if useful == 1
    exact = ffw_verify_current_exact(st, st[2]) ## i64
    if exact == 1
      old_best = best ## i64
      z = ffw_copy_current_to_best(st) ## i64
      st[25] = st[25] + 1
      st[33] = st[33] + 1
      if old_best >= 0
        if rank < old_best
          st[24] = st[24] + 1
          result = 2
      if result == 0
        result = 1
      st[10] = st[40]
      st[14] = st[13] + st[18]
    if exact == 0
      result = 0 - 1
      if best > 0
        z = ffw_restore_best(st)
  result

# Internal algebraic moves start from an exhaustively-gated state and apply
# tensor identities only.  Re-running the n^6 coefficient gate for every rank
# or density improvement would dominate the hot path at 6x6/7x7.  This trusted
# helper is deliberately not part of the coordinator-facing API; imports,
# explicit ffw_adopt_current(), dumps, and harvests retain the exhaustive gate.
-> ffw_adopt_algebraic(st, allow_density_tie) (i64[] i64) i64
  result = 0 ## i64
  rank = st[6] ## i64
  best = st[7] ## i64
  bits = ffw_view_bits(st, st[44], st[45], st[46], st[50], rank) ## i64
  useful = 0 ## i64
  if best < 0
    useful = 1
  if best >= 0
    if rank < best
      useful = 1
    if allow_density_tie != 0
      if rank == best
        if bits < st[36]
          useful = 1
  if useful == 1
    old_best = best ## i64
    z = ffw_copy_current_to_best(st) ## i64
    st[25] = st[25] + 1
    st[33] = st[33] + 1
    if old_best >= 0
      if rank < old_best
        st[24] = st[24] + 1
        result = 2
    if result == 0
      result = 1
    st[10] = st[40]
    st[14] = st[13] + st[18]
  result


# ---- initialization/import/export ----------------------------------------

# String#to_i boxes values above the immediate-integer range.  Keeping both
# at-most-seven-digit chunks and their recombination in declared i64 locals
# avoids the boxed/raw store bug for 7x7 masks with bit 48 set.
-> ffw_parse_decimal_i64(text) (String) i64
  cut = text.size() - 7 ## i64
  value = 0 ## i64
  if cut > 0
    high = text.slice(0, cut).to_i() ## i64
    low = text.slice(cut, 7).to_i() ## i64
    value = high * 10000000 + low
  if cut <= 0
    value = text.to_i()
  value

-> ffw_init_naive_cap(st, n, capacity, seed, dslack, cycles, workq, wanderq) (i64[] i64 i64 i64 i64 i64 i64 i64) i64
  ok = ffw_prepare(st, n, capacity, seed, dslack, cycles, workq, wanderq) ## i64
  result = 0 - 1 ## i64
  if ok == 1
    rank = 0 ## i64
    i = 0 ## i64
    while i < n
      j = 0 ## i64
      while j < n
        k = 0 ## i64
        while k < n
          u = 1 << (i * n + k) ## i64
          v = 1 << (k * n + j) ## i64
          w = 1 << (i * n + j) ## i64
          rank = ffw_toggle(st, u, v, w, rank)
          k += 1
        j += 1
      i += 1
    st[6] = rank
    adopted = ffw_adopt_current(st, 1) ## i64
    if adopted > 0
      result = rank
    if adopted <= 0
      st[39] = st[39] + 1
  result

-> ffw_init_naive(st, n, seed, dslack, cycles, workq, wanderq) (i64[] i64 i64 i64 i64 i64 i64) i64
  ffw_init_naive_cap(st, n, ffw_default_capacity(n), seed, dslack, cycles, workq, wanderq)

-> ffw_init_terms_cap(st, us, vs, ws, rank, n, capacity, seed, dslack, cycles, workq, wanderq) (i64[] i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64 i64) i64
  ok = 1 ## i64
  if rank < 1
    ok = 0
  if rank > capacity
    ok = 0
  # us/vs/ws are raw typed buffers; the caller guarantees at least rank words.
  if ok == 1
    ok = ffw_prepare(st, n, capacity, seed, dslack, cycles, workq, wanderq)
  result = 0 - 1 ## i64
  if ok == 1
    factor_mask = (1 << (n * n)) - 1 ## i64
    current = 0 ## i64
    i = 0 ## i64
    while i < rank
      valid_term = 1 ## i64
      if us[i] <= 0
        valid_term = 0
      if vs[i] <= 0
        valid_term = 0
      if ws[i] <= 0
        valid_term = 0
      if (us[i] & factor_mask) != us[i]
        valid_term = 0
      if (vs[i] & factor_mask) != vs[i]
        valid_term = 0
      if (ws[i] & factor_mask) != ws[i]
        valid_term = 0
      if valid_term == 1
        current = ffw_toggle(st, us[i], vs[i], ws[i], current)
      if valid_term == 0
        ok = 0
      i += 1
    st[6] = current
    if current != rank
      ok = 0
    if ok == 1
      adopted = ffw_adopt_current(st, 1) ## i64
      if adopted > 0
        st[31] = st[31] + 1
        result = current
      if adopted <= 0
        ok = 0
    if ok == 0
      st[39] = st[39] + 1
  result

-> ffw_init_terms(st, us, vs, ws, rank, n, seed, dslack, cycles, workq, wanderq) (i64[] i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64) i64
  cap = ffw_default_capacity(n) ## i64
  ffw_init_terms_cap(st, us, vs, ws, rank, n, cap, seed, dslack, cycles, workq, wanderq)

-> ffw_load_scheme_cap(st, path, n, capacity, seed, dslack, cycles, workq, wanderq) (i64[] String i64 i64 i64 i64 i64 i64 i64) i64
  result = 0 - 1 ## i64
  content = read_file(path)
  if content != nil
    lines = content.split("\n")
    if lines.size() > 0
      line_base = 1 ## i64
      field_base = 0 ## i64
      rank = lines[0].to_i() ## i64
      first_parts = lines[0].split(" ")
      if first_parts.size() >= 4
        if first_parts[0] == "R"
          line_base = 0
          field_base = 1
          rank = lines.size()
          if lines[rank - 1].size() == 0
            rank = rank - 1
      # Imported catalog files may retain both a numeric rank header and
      # `R u v w` row prefixes.  The rectangular worker already accepts this
      # unambiguous mixed spelling; keep square ingestion consistent.  The
      # numeric header remains authoritative and every row is still gated.
      if line_base == 1 && lines.size() > 1
        first_row = lines[1].split(" ")
        if first_row.size() >= 4 && first_row[0] == "R"
          field_base = 1
      ok = 1 ## i64
      if rank < 1
        ok = 0
      if rank > capacity
        ok = 0
      if lines.size() < rank + line_base
        ok = 0
      if ok == 1
        ok = ffw_prepare(st, n, capacity, seed, dslack, cycles, workq, wanderq)
      if ok == 1
        factor_mask = (1 << (n * n)) - 1 ## i64
        current = 0 ## i64
        i = 0 ## i64
        while i < rank
          parts = lines[i + line_base].split(" ")
          valid_term = 1 ## i64
          if parts.size() < field_base + 3
            valid_term = 0
          if valid_term == 1
            u = ffw_parse_decimal_i64(parts[field_base]) ## i64
            v = ffw_parse_decimal_i64(parts[field_base + 1]) ## i64
            w = ffw_parse_decimal_i64(parts[field_base + 2]) ## i64
            if u <= 0
              valid_term = 0
            if v <= 0
              valid_term = 0
            if w <= 0
              valid_term = 0
            if (u & factor_mask) != u
              valid_term = 0
            if (v & factor_mask) != v
              valid_term = 0
            if (w & factor_mask) != w
              valid_term = 0
            if valid_term == 1
              current = ffw_toggle(st, u, v, w, current)
          if valid_term == 0
            ok = 0
          i += 1
        st[6] = current
        if current != rank
          ok = 0
        if ok == 1
          adopted = ffw_adopt_current(st, 1) ## i64
          if adopted > 0
            st[31] = st[31] + 1
            result = current
          if adopted <= 0
            ok = 0
        if ok == 0
          st[39] = st[39] + 1
  result

-> ffw_load_scheme(st, path, n, seed, dslack, cycles, workq, wanderq) (i64[] String i64 i64 i64 i64 i64 i64) i64
  ffw_load_scheme_cap(st, path, n, ffw_default_capacity(n), seed, dslack, cycles, workq, wanderq)

-> ffw_reseed_from(dst, src, seed) (i64[] i64[] i64) i64
  result = 0 - 1 ## i64
  if ffw_valid(src) == 1
    # Source bests were exact-gated on import/harvest and every subsequent
    # internal update is an algebraic identity.  Clone without another n^6
    # pass; the coordinator still gates any externally supplied candidate.
    if src[7] > 0
      n = src[2] ## i64
      rank = src[7] ## i64
      capacity = src[4] ## i64
      dslack = src[17] ## i64
      cycles = src[15] ## i64
      workq = src[18] ## i64
      wanderq = src[19] ## i64
      if ffw_valid(dst) == 1
        if dst[2] == n
          capacity = dst[4]
          dslack = dst[17]
          cycles = dst[15]
          workq = dst[18]
          wanderq = dst[19]
      if capacity >= rank
        ok = ffw_prepare(dst, n, capacity, seed, dslack, cycles, workq, wanderq) ## i64
        if ok == 1
          current = 0 ## i64
          i = 0 ## i64
          while i < rank
            current = ffw_toggle(dst, src[src[47] + i], src[src[48] + i], src[src[49] + i], current)
            i += 1
          dst[6] = current
          adopted = ffw_adopt_algebraic(dst, 1) ## i64
          if adopted > 0
            dst[31] = dst[31] + 1
            result = current
  result

-> ffw_export_best(st, us, vs, ws) (i64[] i64[] i64[] i64[]) i64
  rank = st[7] ## i64
  result = 0 - 1 ## i64
  if rank >= 0
    buo = st[47] ## i64
    bvo = st[48] ## i64
    bwo = st[49] ## i64
    i = 0 ## i64
    while i < rank
      uv = st[buo + i] ## i64
      vv = st[bvo + i] ## i64
      wv = st[bwo + i] ## i64
      us[i] = uv
      vs[i] = vv
      ws[i] = wv
      i += 1
    st[32] = st[32] + 1
    result = rank
  result

-> ffw_export_current(st, us, vs, ws) (i64[] i64[] i64[] i64[]) i64
  rank = st[6] ## i64
  result = 0 - 1 ## i64
  liveo = st[50] ## i64
  uo = st[44] ## i64
  vo = st[45] ## i64
  wo = st[46] ## i64
  i = 0 ## i64
  while i < rank
    slot = st[liveo + i] ## i64
    uv = st[uo + slot] ## i64
    vv = st[vo + slot] ## i64
    wv = st[wo + slot] ## i64
    us[i] = uv
    vs[i] = vv
    ws[i] = wv
    i += 1
  st[32] = st[32] + 1
  result = rank
  result

-> ffw_dump_best(st, path) (i64[] String) i64
  result = 0 - 1 ## i64
  if ffw_verify_best_exact(st, st[2]) == 1
    rank = st[7] ## i64
    body = rank.to_s() + "\n"
    i = 0 ## i64
    while i < rank
      body = body + st[st[47] + i].to_s() + " " + st[st[48] + i].to_s() + " " + st[st[49] + i].to_s() + "\n"
      i += 1
    z = write_file(path, body)
    st[32] = st[32] + 1
    result = rank
  result

-> ffw_dump_current(st, path) (i64[] String) i64
  result = 0 - 1 ## i64
  if ffw_verify_current_exact(st, st[2]) == 1
    rank = st[6] ## i64
    body = rank.to_s() + "\n"
    i = 0 ## i64
    while i < rank
      slot = st[st[50] + i] ## i64
      body = body + st[st[44] + slot].to_s() + " " + st[st[45] + slot].to_s() + " " + st[st[46] + slot].to_s() + "\n"
      i += 1
    z = write_file(path, body)
    st[32] = st[32] + 1
    result = rank
  result


# ---- move engine ----------------------------------------------------------

-> ffw_rand31(st) (i64[]) i64
  rng = (st[8] * 6364136223846793005 + st[9]) & 9223372036854775807 ## i64
  st[8] = rng
  (rng >> 32) & 2147483647

-> ffw_pressure(st, u, v, w) (i64[] i64 i64 i64) i64
  count = 0 ## i64
  c = st[st[53] + ffw_hash(st, u)] ## i64
  while c != 0
    slot = c - 1 ## i64
    if st[st[44] + slot] == u
      samev = 0 ## i64
      samew = 0 ## i64
      if st[st[45] + slot] == v
        samev = 1
      if st[st[46] + slot] == w
        samew = 1
      if samev + samew == 1
        count += 1
    c = st[st[56] + slot]
  c = st[st[54] + ffw_hash(st, v)] ## i64
  while c != 0
    slot = c - 1 ## i64
    if st[st[45] + slot] == v
      if st[st[44] + slot] != u
        if st[st[46] + slot] == w
          count += 1
    c = st[st[58] + slot]
  count

-> ffw_try_flip_controlled(st, mode, min_slot, pressure_ceiling, pressure_period) (i64[] i64 i64 i64 i64) i64
  st[20] = st[20] + 1
  result = 0 ## i64
  rank_before = st[6] ## i64
  if rank_before < 2
    st[21] = st[21]
    st[22] = st[22] + 1
    result = 0
  if rank_before >= 2
    word = ffw_rand31(st) ## i64
    rank_index = (word * rank_before) >> 31 ## i64
    first = st[st[50] + rank_index] ## i64
    scanned_first = 0 ## i64
    while first < min_slot && scanned_first < rank_before
      rank_index = (rank_index + 1) % rank_before
      first = st[st[50] + rank_index]
      scanned_first += 1
    if first < min_slot
      st[22] = st[22] + 1
      return 0
    ui = st[st[44] + first] ## i64
    vi = st[st[45] + first] ## i64
    wi = st[st[46] + first] ## i64
    word = ffw_rand31(st)
    axis = (((word >> 22) & 511) * 3) >> 9 ## i64
    word = ffw_rand31(st)
    second = ffw_pick_partner_min(st, axis, first, word, min_slot) ## i64
    if second < 0
      st[23] = st[23] + 1
      st[22] = st[22] + 1
    if second >= 0
      uj = st[st[44] + second] ## i64
      vj = st[st[45] + second] ## i64
      wj = st[st[46] + second] ## i64
      au = ui ## i64
      av = vi ## i64
      aw = wi ## i64
      bu = ui ## i64
      bv = vi ## i64
      bw = wj ## i64
      if axis == 0
        aw = wi ^ wj
        bv = vi ^ vj
      if axis == 1
        aw = wi ^ wj
        bu = ui ^ uj
      if axis == 2
        av = vi ^ vj
        bu = ui ^ uj
        bv = vj
        bw = wi
      old_pressure = ffw_pressure(st, ui, vi, wi) + ffw_pressure(st, uj, vj, wj) ## i64
      old_bits = ffw_popcount(ui) + ffw_popcount(vi) + ffw_popcount(wi) ## i64
      old_bits += ffw_popcount(uj) + ffw_popcount(vj) + ffw_popcount(wj)
      rank = rank_before ## i64
      rank = ffw_toggle(st, ui, vi, wi, rank)
      rank = ffw_toggle(st, uj, vj, wj, rank)
      rank = ffw_toggle(st, au, av, aw, rank)
      rank = ffw_toggle(st, bu, bv, bw, rank)
      new_pressure = ffw_pressure(st, au, av, aw) + ffw_pressure(st, bu, bv, bw) ## i64
      new_bits = ffw_popcount(au) + ffw_popcount(av) + ffw_popcount(aw) ## i64
      new_bits += ffw_popcount(bu) + ffw_popcount(bv) + ffw_popcount(bw)
      accept = 0 ## i64
      if rank < rank_before
        accept = 1
      if rank == rank_before
        if mode == 0
          ceiling = pressure_ceiling ## i64
          if ceiling < 0
            ceiling = 0
          period = pressure_period ## i64
          if period < 1
            period = 1
          pressure_slack = ceiling - ((st[13] / period) % (ceiling + 1)) ## i64
          if new_pressure + pressure_slack >= old_pressure
            if new_bits <= old_bits + st[17]
              accept = 1
        if mode != 0
          if new_bits <= old_bits + st[17] + st[10]
            accept = 1
      if accept == 0
        rank = ffw_toggle(st, ui, vi, wi, rank)
        rank = ffw_toggle(st, uj, vj, wj, rank)
        rank = ffw_toggle(st, au, av, aw, rank)
        rank = ffw_toggle(st, bu, bv, bw, rank)
        st[22] = st[22] + 1
      if accept == 1
        st[6] = rank
        st[21] = st[21] + 1
        result = 1
        adopted = ffw_adopt_algebraic(st, 1) ## i64
        if adopted == 2
          result = 2
        if adopted < 0
          result = 0 - 1
      if accept == 0
        st[6] = rank_before
  result

-> ffw_try_flip_core(st, mode, min_slot) (i64[] i64 i64) i64
  ffw_try_flip_controlled(st, mode, min_slot, 6, 300000)

-> ffw_try_flip(st, mode) (i64[] i64) i64
  ffw_try_flip_core(st, mode, 0)

-> ffw_try_split(st) (i64[]) i64
  st[20] = st[20] + 1
  st[27] = st[27] + 1
  result = 0 ## i64
  rank_before = st[6] ## i64
  if rank_before >= st[4]
    st[22] = st[22] + 1
  if rank_before < st[4]
    word = ffw_rand31(st) ## i64
    rank_index = (word * rank_before) >> 31 ## i64
    slot = st[st[50] + rank_index] ## i64
    u = st[st[44] + slot] ## i64
    v = st[st[45] + slot] ## i64
    w = st[st[46] + slot] ## i64
    word = ffw_rand31(st)
    axis = (((word >> 22) & 511) * 3) >> 9 ## i64
    high = ffw_rand31(st) ## i64
    low = ffw_rand31(st) ## i64
    part = ((high << 31) ^ low) & ((1 << st[3]) - 1) ## i64
    factor = u ## i64
    if axis == 1
      factor = v
    if axis == 2
      factor = w
    if part == 0
      part = 1
    if part == factor
      part = part ^ 1
      if part == 0
        part = 2
    au = u ## i64
    av = v ## i64
    aw = w ## i64
    bu = u ## i64
    bv = v ## i64
    bw = w ## i64
    if axis == 0
      au = part
      bu = factor ^ part
    if axis == 1
      av = part
      bv = factor ^ part
    if axis == 2
      aw = part
      bw = factor ^ part
    rank = rank_before ## i64
    rank = ffw_toggle(st, u, v, w, rank)
    rank = ffw_toggle(st, au, av, aw, rank)
    rank = ffw_toggle(st, bu, bv, bw, rank)
    accept = 0 ## i64
    if rank <= st[7] + st[10]
      accept = 1
    if accept == 0
      rank = ffw_toggle(st, u, v, w, rank)
      rank = ffw_toggle(st, au, av, aw, rank)
      rank = ffw_toggle(st, bu, bv, bw, rank)
      st[22] = st[22] + 1
    if accept == 1
      st[6] = rank
      st[21] = st[21] + 1
      st[28] = st[28] + 1
      result = 1
      adopted = ffw_adopt_algebraic(st, 1) ## i64
      if adopted == 2
        result = 2
      if adopted < 0
        result = 0 - 1
    if accept == 0
      st[6] = rank_before
  result

-> ffw_one_controlled(st, mode, split_cadence, pressure_ceiling, pressure_period) (i64[] i64 i64 i64 i64) i64
  result = 0 ## i64
  do_split = 0 ## i64
  if mode != 0
    if st[13] > 0
      if split_cadence > 0 && (st[13] % split_cadence) == 0
        do_split = 1
  if do_split == 1
    result = ffw_try_split(st)
  if do_split == 0
    result = ffw_try_flip_controlled(st, mode, 0, pressure_ceiling, pressure_period)
  st[13] = st[13] + 1
  st[42] = (st[42] & 2) | mode
  if mode == 0
    st[34] = st[34] + 1
  if mode != 0
    st[35] = st[35] + 1
  if st[7] > 0
    if st[6] > st[7] + st[10]
      z = ffw_restore_best(st) ## i64
  result

-> ffw_one(st, mode) (i64[] i64) i64
  ffw_one_controlled(st, mode, 2000, 6, 300000)

-> ffw_work(st, steps) (i64[] i64) i64
  i = 0 ## i64
  while i < steps
    z = ffw_one(st, 0) ## i64
    i += 1
  st[7]

-> ffw_wander(st, steps) (i64[] i64) i64
  i = 0 ## i64
  while i < steps
    z = ffw_one(st, 1) ## i64
    i += 1
  st[7]

-> ffw_advance_zone_controlled(st, work_step, wander_step) (i64[] i64 i64) i64
  band = st[10] ## i64
  work_delta = work_step ## i64
  if work_delta < 1
    work_delta = 1
  wander_delta = wander_step ## i64
  if wander_delta < 1
    wander_delta = 1
  next_band = band + work_delta ## i64
  if band > st[11]
    next_band = band + wander_delta
  if next_band > st[41]
    next_band = st[40]
    st[12] = st[12] + 1
    if st[12] >= st[15]
      st[16] = 1
  st[10] = next_band
  quota = st[18] ## i64
  if next_band > st[11]
    quota = st[19]
  st[14] = st[13] + quota
  next_band

-> ffw_advance_zone(st) (i64[]) i64
  ffw_advance_zone_controlled(st, 1, 12)

-> ffw_walk(st, steps) (i64[] i64) i64
  i = 0 ## i64
  while i < steps
    mode = 0 ## i64
    if st[10] > st[11]
      mode = 1
    z = ffw_one(st, mode) ## i64
    if st[13] >= st[14]
      z = ffw_advance_zone(st)
    i += 1
  st[7]

# One bounded experiment lane may race these controls without changing the
# default hot loop for the rest of the fleet. controls:
#   split cadence, pressure ceiling, pressure period, work-band step,
#   wander-band step, work/wander threshold, maximum band.
-> ffw_walk_tuned(st, steps, controls) (i64[] i64 i64[]) i64
  threshold = controls[5] ## i64
  if threshold < 1
    threshold = 1
  max_band = controls[6] ## i64
  if max_band <= threshold
    max_band = threshold + 1
  st[11] = threshold
  st[41] = max_band
  i = 0 ## i64
  while i < steps
    mode = 0 ## i64
    if st[10] > st[11]
      mode = 1
    z = ffw_one_controlled(st, mode, controls[0], controls[1], controls[2]) ## i64
    if st[13] >= st[14]
      z = ffw_advance_zone_controlled(st, controls[3], controls[4])
    i += 1
  st[7]

-> ffw_enable_cycle_hash(st) (i64[]) i64
  st[42] = st[42] | 2
  fingerprint = 0 ## i64
  i = 0 ## i64
  while i < st[6]
    slot = st[st[50] + i] ## i64
    fingerprint = fingerprint ^ ffw_term_zobrist(st[st[44] + slot], st[st[45] + slot], st[st[46] + slot])
    i += 1
  st[37] = fingerprint
  fingerprint

# Observe accepted-state recurrence on one measurement island. recent is a
# fixed-size direct-mapped filter supplied by the coordinator; stats layout is cursor, count,
# unique, repeats, immediate inverses, accepted observations, last hash,
# previous hash, initialized. No rejection-path work is added.
-> ffw_walk_cycle_watch(st, steps, recent, recent_capacity, stats) (i64[] i64 i64[] i64 i64[]) i64
  if recent_capacity < 1
    return ffw_walk(st, steps)
  if stats[8] == 0
    initial = ffw_enable_cycle_hash(st) ## i64
    initial_slot = (initial ^ (initial >> 32)) & (recent_capacity - 1) ## i64
    recent[initial_slot] = initial
    stats[0] = 0
    stats[1] = 1
    stats[2] = 1
    stats[3] = 0
    stats[4] = 0
    stats[5] = 0
    stats[6] = initial
    stats[7] = 0 - 1
    stats[8] = 1
  i = 0 ## i64
  while i < steps
    accepted_before = st[21] ## i64
    mode = 0 ## i64
    if st[10] > st[11]
      mode = 1
    z = ffw_one(st, mode) ## i64
    if st[21] > accepted_before
      fingerprint = st[37] ## i64
      if stats[7] >= 0 && fingerprint == stats[7]
        stats[4] = stats[4] + 1
      found = 0 ## i64
      filter_slot = (fingerprint ^ (fingerprint >> 32)) & (recent_capacity - 1) ## i64
      if recent[filter_slot] == fingerprint
        found = 1
      if found == 1
        stats[3] = stats[3] + 1
      if found == 0
        stats[2] = stats[2] + 1
        if recent[filter_slot] == 0 && stats[1] < recent_capacity
          stats[1] = stats[1] + 1
        recent[filter_slot] = fingerprint
      stats[5] = stats[5] + 1
      stats[7] = stats[6]
      stats[6] = fingerprint
    if st[13] >= st[14]
      z = ffw_advance_zone(st)
    i += 1
  st[7]

# Exact core/fringe control. The caller initializes core terms in slots
# [0,core_slots); only slots at or above the boundary may participate in a
# flip, so the core remains byte-for-byte fixed for the entire walk. Splits
# are deliberately disabled in this one bounded control lane.
-> ffw_walk_fringe(st, steps, core_slots) (i64[] i64 i64) i64
  boundary = core_slots ## i64
  if boundary < 0
    boundary = 0
  if boundary >= st[6] - 1
    boundary = st[6] - 2
  if boundary < 0
    boundary = 0
  i = 0 ## i64
  while i < steps
    mode = 0 ## i64
    if st[10] > st[11]
      mode = 1
    z = ffw_try_flip_core(st, mode, boundary) ## i64
    st[13] = st[13] + 1
    st[42] = (st[42] & 2) | mode
    if mode == 0
      st[34] = st[34] + 1
    if mode != 0
      st[35] = st[35] + 1
    if st[13] >= st[14]
      z = ffw_advance_zone(st)
    i += 1
  st[7]

-> ffw_set_zone_quotas(st, work_moves, wander_moves) (i64[] i64 i64) i64
  work = work_moves ## i64
  wander = wander_moves ## i64
  if work < 1
    work = 1
  if wander < 1
    wander = 1
  st[18] = work
  st[19] = wander
  quota = work ## i64
  if st[10] > st[11]
    quota = wander
  st[14] = st[13] + quota
  quota


# ---- stable getters -------------------------------------------------------

-> ffw_n(st) (i64[]) i64
  st[2]

-> ffw_capacity(st) (i64[]) i64
  st[4]

-> ffw_current_rank(st) (i64[]) i64
  st[6]

-> ffw_best_rank(st) (i64[]) i64
  st[7]

-> ffw_current_bits(st) (i64[]) i64
  ffw_view_bits(st, st[44], st[45], st[46], st[50], st[6])

-> ffw_best_bits(st) (i64[]) i64
  st[36]

-> ffw_moves(st) (i64[]) i64
  st[13]

-> ffw_band(st) (i64[]) i64
  st[10]

-> ffw_threshold(st) (i64[]) i64
  st[11]

-> ffw_cycled(st) (i64[]) i64
  st[16]

-> ffw_proposals(st) (i64[]) i64
  st[20]

-> ffw_accepted(st) (i64[]) i64
  st[21]

-> ffw_rejected(st) (i64[]) i64
  st[22]

-> ffw_partner_misses(st) (i64[]) i64
  st[23]

-> ffw_rank_drops(st) (i64[]) i64
  st[24]

-> ffw_best_updates(st) (i64[]) i64
  st[25]

-> ffw_restarts(st) (i64[]) i64
  st[26]

-> ffw_split_attempts(st) (i64[]) i64
  st[27]

-> ffw_split_accepted(st) (i64[]) i64
  st[28]

-> ffw_exact_checks(st) (i64[]) i64
  st[29]

-> ffw_exact_failures(st) (i64[]) i64
  st[30]

-> ffw_imports(st) (i64[]) i64
  st[31]

-> ffw_exports(st) (i64[]) i64
  st[32]

-> ffw_adoptions(st) (i64[]) i64
  st[33]

-> ffw_work_moves(st) (i64[]) i64
  st[34]

-> ffw_wander_moves(st) (i64[]) i64
  st[35]

-> ffw_last_verify(st) (i64[]) i64
  st[38]

-> ffw_invalid_inputs(st) (i64[]) i64
  st[39]

-> ffw_read_best_u(st, index) (i64[] i64) i64
  st[st[47] + index]

-> ffw_read_best_v(st, index) (i64[] i64) i64
  st[st[48] + index]

-> ffw_read_best_w(st, index) (i64[] i64) i64
  st[st[49] + index]

-> ffw_read_current_u(st, index) (i64[] i64) i64
  slot = st[st[50] + index] ## i64
  st[st[44] + slot]

-> ffw_read_current_v(st, index) (i64[] i64) i64
  slot = st[st[50] + index] ## i64
  st[st[45] + slot]

-> ffw_read_current_w(st, index) (i64[] i64) i64
  slot = st[st[50] + index] ## i64
  st[st[46] + slot]
