# Exact sparse-residual local search for rectangular GF(2) tensors.
#
# A worm state is always seventeen nonzero rank-one terms S plus the complete
# defect carrier G = S XOR T.  G is only seven i64 words for <2,2,5>, but the
# search also treats it as a sparse set of active coefficients.  Replacing one
# factor updates G incrementally by XORing the old and new outer products; a
# periodic rebuild catches any bookkeeping disagreement.
#
# The ordering is deliberately exact rather than projected: syndrome weight
# first, then active coordinate slices (a cheap flattening-rank proxy).  Exact
# ranks of all three tensor flattenings are recorded for every retained best.
# At the weight-one floor the directed move follows the live coefficient
# through a factor slice, allowing neutral residual motion before a bounded
# uphill tunnel.  G=0 is admitted only after the independent rectangular
# worker reconstructs every tensor coefficient.

use metaflip_rect_worker

-> ffrrw_tensor_bits(n, m, p) (i64 i64 i64) i64
  (n * m) * (m * p) * (n * p)

-> ffrrw_tensor_words(n, m, p) (i64 i64 i64) i64
  (ffrrw_tensor_bits(n, m, p) + 63) / 64

-> ffrrw_clear(values, count) (i64[] i64) i64
  i = 0 ## i64
  while i < count
    values[i] = 0
    i += 1
  count

-> ffrrw_copy(source, target, count) (i64[] i64[] i64) i64
  i = 0 ## i64
  while i < count
    target[i] = source[i]
    i += 1
  count

-> ffrrw_equal(left, right, count) (i64[] i64[] i64) i64
  i = 0 ## i64
  while i < count
    if left[i] != right[i]
      return 0
    i += 1
  1

-> ffrrw_bit(values, bit) (i64[] i64) i64
  (values[bit / 64] >> (bit % 64)) & 1

# Toggle one carrier coefficient and return the new exact Hamming weight.
-> ffrrw_toggle_weight(values, bit, weight) (i64[] i64 i64) i64
  was = ffrrw_bit(values, bit) ## i64
  values[bit / 64] = values[bit / 64] ^ (1 << (bit % 64))
  if was == 0
    return weight + 1
  weight - 1

-> ffrrw_weight(values, words) (i64[] i64) i64
  weight = 0 ## i64
  i = 0 ## i64
  while i < words
    weight += ffw_popcount(values[i])
    i += 1
  weight

# XOR one rank-one tensor into the carrier, maintaining its exact weight.
-> ffrrw_xor_outer_weight(carrier, u, v, w, uwidth, vwidth, wwidth, weight) (i64[] i64 i64 i64 i64 i64 i64 i64) i64
  a = 0 ## i64
  while a < uwidth
    if ((u >> a) & 1) != 0
      b = 0 ## i64
      while b < vwidth
        if ((v >> b) & 1) != 0
          c = 0 ## i64
          while c < wwidth
            if ((w >> c) & 1) != 0
              weight = ffrrw_toggle_weight(carrier, (a * vwidth + b) * wwidth + c, weight)
            c += 1
        b += 1
    a += 1
  weight

-> ffrrw_build_mmt_target(target, n, m, p) (i64[] i64 i64 i64) i64
  words = ffrrw_tensor_words(n, m, p) ## i64
  if target.size() < words
    return 0
  z = ffrrw_clear(target, words) ## i64
  vwidth = m * p ## i64
  wwidth = n * p ## i64
  i = 0 ## i64
  while i < n
    k = 0 ## i64
    while k < m
      j = 0 ## i64
      while j < p
        a = i * m + k ## i64
        b = k * p + j ## i64
        c = i * p + j ## i64
        bit = (a * vwidth + b) * wwidth + c ## i64
        target[bit / 64] = target[bit / 64] ^ (1 << (bit % 64))
        j += 1
      k += 1
    i += 1
  words

-> ffrrw_build_term_target(us, vs, ws, rank, n, m, p, target) (i64[] i64[] i64[] i64 i64 i64 i64 i64[]) i64
  words = ffrrw_tensor_words(n, m, p) ## i64
  if target.size() < words
    return 0
  z = ffrrw_clear(target, words) ## i64
  uwidth = n * m ## i64
  vwidth = m * p ## i64
  wwidth = n * p ## i64
  weight = 0 ## i64
  term = 0 ## i64
  while term < rank
    weight = ffrrw_xor_outer_weight(target, us[term], vs[term], ws[term], uwidth, vwidth, wwidth, weight)
    term += 1
  words

# carrier = target XOR sum(terms).  A caller may supply either the actual MMT
# target or a planted synthetic tensor.
-> ffrrw_build_residual(us, vs, ws, rank, n, m, p, target, carrier) (i64[] i64[] i64[] i64 i64 i64 i64 i64[] i64[]) i64
  words = ffrrw_tensor_words(n, m, p) ## i64
  if target.size() < words || carrier.size() < words
    return 0 - 1
  z = ffrrw_copy(target, carrier, words) ## i64
  uwidth = n * m ## i64
  vwidth = m * p ## i64
  wwidth = n * p ## i64
  weight = ffrrw_weight(carrier, words) ## i64
  term = 0 ## i64
  while term < rank
    if us[term] <= 0 || vs[term] <= 0 || ws[term] <= 0
      return 0 - 1
    weight = ffrrw_xor_outer_weight(carrier, us[term], vs[term], ws[term], uwidth, vwidth, wwidth, weight)
    term += 1
  weight

# Active coordinate slices are a cheap rank proxy used in the hot ordering.
# meta: active U/V/W slices and their sum.
-> ffrrw_support_proxy(carrier, n, m, p, meta) (i64[] i64 i64 i64 i64[]) i64
  uwidth = n * m ## i64
  vwidth = m * p ## i64
  wwidth = n * p ## i64
  ua = i64[uwidth]
  va = i64[vwidth]
  wa = i64[wwidth]
  bits = ffrrw_tensor_bits(n, m, p) ## i64
  bit = 0 ## i64
  while bit < bits
    if ffrrw_bit(carrier, bit) != 0
      a = bit / (vwidth * wwidth) ## i64
      b = (bit / wwidth) % vwidth ## i64
      c = bit % wwidth ## i64
      ua[a] = 1
      va[b] = 1
      wa[c] = 1
    bit += 1
  au = 0 ## i64
  av = 0 ## i64
  aw = 0 ## i64
  i = 0 ## i64
  while i < uwidth
    au += ua[i]
    i += 1
  i = 0
  while i < vwidth
    av += va[i]
    i += 1
  i = 0
  while i < wwidth
    aw += wa[i]
    i += 1
  meta[0] = au
  meta[1] = av
  meta[2] = aw
  meta[3] = au + av + aw
  meta[3]

-> ffrrw_row_bit(rows, row_words, row, bit) (i64[] i64 i64 i64) i64
  (rows[row * row_words + bit / 64] >> (bit % 64)) & 1

-> ffrrw_flatten_rank(carrier, n, m, p, axis) (i64[] i64 i64 i64 i64) i64
  uwidth = n * m ## i64
  vwidth = m * p ## i64
  wwidth = n * p ## i64
  rows_count = uwidth ## i64
  columns = vwidth * wwidth ## i64
  if axis == 1
    rows_count = vwidth
    columns = uwidth * wwidth
  if axis == 2
    rows_count = wwidth
    columns = uwidth * vwidth
  row_words = (columns + 63) / 64 ## i64
  rows = i64[rows_count * row_words]
  bits = ffrrw_tensor_bits(n, m, p) ## i64
  cell = 0 ## i64
  while cell < bits
    if ffrrw_bit(carrier, cell) != 0
      a = cell / (vwidth * wwidth) ## i64
      b = (cell / wwidth) % vwidth ## i64
      c = cell % wwidth ## i64
      row = a ## i64
      column = b * wwidth + c ## i64
      if axis == 1
        row = b
        column = a * wwidth + c
      if axis == 2
        row = c
        column = a * vwidth + b
      offset = row * row_words + column / 64 ## i64
      rows[offset] = rows[offset] ^ (1 << (column % 64))
    cell += 1
  rank = 0 ## i64
  column = 0
  while column < columns && rank < rows_count
    pivot = rank ## i64
    while pivot < rows_count && ffrrw_row_bit(rows, row_words, pivot, column) == 0
      pivot += 1
    if pivot < rows_count
      if pivot != rank
        word = 0 ## i64
        while word < row_words
          tmp = rows[rank * row_words + word] ## i64
          rows[rank * row_words + word] = rows[pivot * row_words + word]
          rows[pivot * row_words + word] = tmp
          word += 1
      row = 0 ## i64
      while row < rows_count
        if row != rank && ffrrw_row_bit(rows, row_words, row, column) != 0
          word = 0
          while word < row_words
            rows[row * row_words + word] = rows[row * row_words + word] ^ rows[rank * row_words + word]
            word += 1
        row += 1
      rank += 1
    column += 1
  rank

# meta: active U/V/W slices, rank of U/V/W flattenings, rank sum, proxy sum.
-> ffrrw_structure(carrier, n, m, p, meta) (i64[] i64 i64 i64 i64[]) i64
  proxy = i64[4]
  z = ffrrw_support_proxy(carrier, n, m, p, proxy) ## i64
  meta[0] = proxy[0]
  meta[1] = proxy[1]
  meta[2] = proxy[2]
  meta[3] = ffrrw_flatten_rank(carrier, n, m, p, 0)
  meta[4] = ffrrw_flatten_rank(carrier, n, m, p, 1)
  meta[5] = ffrrw_flatten_rank(carrier, n, m, p, 2)
  meta[6] = meta[3] + meta[4] + meta[5]
  meta[7] = proxy[3]
  meta[6]

-> ffrrw_rand(rng) (i64[]) i64
  value = (rng[0] * 6364136223846793005 + rng[1]) & 9223372036854775807 ## i64
  rng[0] = value
  (value >> 32) & 2147483647

-> ffrrw_factor(us, vs, ws, term, axis) (i64[] i64[] i64[] i64 i64) i64
  if axis == 0
    return us[term]
  if axis == 1
    return vs[term]
  ws[term]

-> ffrrw_set_factor(us, vs, ws, term, axis, value) (i64[] i64[] i64[] i64 i64 i64) i64
  if axis == 0
    us[term] = value
  if axis == 1
    vs[term] = value
  if axis == 2
    ws[term] = value
  value

-> ffrrw_width(n, m, p, axis) (i64 i64 i64 i64) i64
  if axis == 0
    return n * m
  if axis == 1
    return m * p
  n * p

-> ffrrw_unique_after(us, vs, ws, rank, term, axis, value) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  u = us[term] ## i64
  v = vs[term] ## i64
  w = ws[term] ## i64
  if axis == 0
    u = value
  if axis == 1
    v = value
  if axis == 2
    w = value
  i = 0 ## i64
  while i < rank
    if i != term && us[i] == u && vs[i] == v && ws[i] == w
      return 0
    i += 1
  1

# Weight after toggling one coordinate of one factor.  The affected outer
# slice is disjoint from all other coordinates on that axis.
-> ffrrw_axis_bit_weight(carrier, u, v, w, axis, coordinate, n, m, p, weight) (i64[] i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
  delta = 1 << coordinate ## i64
  if axis == 0
    return ffrrw_outer_delta_weight(carrier, delta, v, w, n * m, m * p, n * p, weight)
  if axis == 1
    return ffrrw_outer_delta_weight(carrier, u, delta, w, n * m, m * p, n * p, weight)
  ffrrw_outer_delta_weight(carrier, u, v, delta, n * m, m * p, n * p, weight)

# Read-only counterpart of ffrrw_xor_outer_weight.
-> ffrrw_outer_delta_weight(carrier, u, v, w, uwidth, vwidth, wwidth, weight) (i64[] i64 i64 i64 i64 i64 i64 i64) i64
  a = 0 ## i64
  while a < uwidth
    if ((u >> a) & 1) != 0
      b = 0 ## i64
      while b < vwidth
        if ((v >> b) & 1) != 0
          c = 0 ## i64
          while c < wwidth
            if ((w >> c) & 1) != 0
              bit = (a * vwidth + b) * wwidth + c ## i64
              if ffrrw_bit(carrier, bit) == 0
                weight += 1
              else
                weight -= 1
            c += 1
        b += 1
    a += 1
  weight

# Exact coordinate-descent proposal for one factor.  Factor coordinates are
# independent when the other two factors are held fixed, so every bit whose
# outer slice lowers syndrome weight can be toggled simultaneously.
-> ffrrw_coordinate_factor(carrier, u, v, w, axis, n, m, p, rng, weight) (i64[] i64 i64 i64 i64 i64 i64 i64 i64[] i64) i64
  old = u ## i64
  if axis == 1
    old = v
  if axis == 2
    old = w
  width = ffrrw_width(n, m, p, axis) ## i64
  toggles = 0 ## i64
  keep_bit = 0 - 1 ## i64
  keep_penalty = 9223372036854775807 ## i64
  bit = 0 ## i64
  while bit < width
    next_weight = ffrrw_axis_bit_weight(carrier, u, v, w, axis, bit, n, m, p, weight) ## i64
    delta = next_weight - weight ## i64
    take = 0 ## i64
    if delta < 0
      take = 1
    if delta == 0 && (ffrrw_rand(rng) & 31) == 0
      take = 1
    if take == 1
      toggles = toggles | (1 << bit)
      if ((old >> bit) & 1) != 0
        penalty = 0 - delta ## i64
        if penalty < keep_penalty
          keep_penalty = penalty
          keep_bit = bit
    bit += 1
  candidate = old ^ toggles ## i64
  if candidate == 0 && keep_bit >= 0
    candidate = candidate | (1 << keep_bit)
  candidate

-> ffrrw_active_cell(carrier, bits, weight, rng) (i64[] i64 i64 i64[]) i64
  if weight < 1
    return 0 - 1
  want = ffrrw_rand(rng) % weight ## i64
  bit = 0 ## i64
  while bit < bits
    if ffrrw_bit(carrier, bit) != 0
      if want == 0
        return bit
      want -= 1
    bit += 1
  0 - 1

# Follow one live residual coefficient.  Among every legal one-bit factor edit
# whose delta contains that coefficient, retain the minimum exact next weight;
# reservoir ties keep the floor walk from becoming deterministic.
-> ffrrw_directed_proposal(carrier, us, vs, ws, rank, n, m, p, weight, rng, proposal) (i64[] i64[] i64[] i64[] i64 i64 i64 i64 i64 i64[] i64[]) i64
  uwidth = n * m ## i64
  vwidth = m * p ## i64
  wwidth = n * p ## i64
  cell = ffrrw_active_cell(carrier, uwidth * vwidth * wwidth, weight, rng) ## i64
  if cell < 0
    return 0
  ca = cell / (vwidth * wwidth) ## i64
  cb = (cell / wwidth) % vwidth ## i64
  cc = cell % wwidth ## i64
  best_weight = 9223372036854775807 ## i64
  ties = 0 ## i64
  term = 0 ## i64
  while term < rank
    axis = 0 ## i64
    while axis < 3
      covers = 0 ## i64
      coordinate = ca ## i64
      if axis == 0 && ((vs[term] >> cb) & 1) != 0 && ((ws[term] >> cc) & 1) != 0
        covers = 1
      if axis == 1
        coordinate = cb
        if ((us[term] >> ca) & 1) != 0 && ((ws[term] >> cc) & 1) != 0
          covers = 1
      if axis == 2
        coordinate = cc
        if ((us[term] >> ca) & 1) != 0 && ((vs[term] >> cb) & 1) != 0
          covers = 1
      if covers == 1
        old = ffrrw_factor(us, vs, ws, term, axis) ## i64
        candidate = old ^ (1 << coordinate) ## i64
        if candidate != 0 && ffrrw_unique_after(us, vs, ws, rank, term, axis, candidate) == 1
          next_weight = ffrrw_axis_bit_weight(carrier, us[term], vs[term], ws[term], axis, coordinate, n, m, p, weight) ## i64
          if next_weight < best_weight
            best_weight = next_weight
            proposal[0] = term
            proposal[1] = axis
            proposal[2] = candidate
            proposal[3] = next_weight
            ties = 1
          else
            if next_weight == best_weight
              ties += 1
              if ffrrw_rand(rng) % ties == 0
                proposal[0] = term
                proposal[1] = axis
                proposal[2] = candidate
                proposal[3] = next_weight
      axis += 1
    term += 1
  if ties > 0
    return 1
  0

-> ffrrw_random_proposal(carrier, us, vs, ws, rank, n, m, p, weight, rng, mode, proposal) (i64[] i64[] i64[] i64[] i64 i64 i64 i64 i64 i64[] i64 i64[]) i64
  if mode == 1
    if ffrrw_directed_proposal(carrier, us, vs, ws, rank, n, m, p, weight, rng, proposal) == 1
      proposal[4] = 1
      return 1
    # A weight-one carrier can be isolated from every legal one-factor slice.
    # In that case the worm still needs a way out: use a random one-bit edit as
    # the first step of the explicitly bounded uphill tunnel.
    mode = 2
  term = ffrrw_rand(rng) % rank ## i64
  axis = ffrrw_rand(rng) % 3 ## i64
  old = ffrrw_factor(us, vs, ws, term, axis) ## i64
  width = ffrrw_width(n, m, p, axis) ## i64
  candidate = old ## i64
  kind = mode ## i64
  if mode == 0
    candidate = ffrrw_coordinate_factor(carrier, us[term], vs[term], ws[term], axis, n, m, p, rng, weight)
    if candidate == old
      if ffrrw_directed_proposal(carrier, us, vs, ws, rank, n, m, p, weight, rng, proposal) == 1
        proposal[4] = 1
        return 1
  if mode == 2
    candidate = old ^ (1 << (ffrrw_rand(rng) % width))
  if mode == 3
    partner = ffrrw_rand(rng) % rank ## i64
    candidate = old ^ ffrrw_factor(us, vs, ws, partner, axis)
    if candidate == 0
      candidate = old ^ (1 << (ffrrw_rand(rng) % width))
  if candidate == old || candidate == 0
    return 0
  if ffrrw_unique_after(us, vs, ws, rank, term, axis, candidate) != 1
    return 0
  proposal[0] = term
  proposal[1] = axis
  proposal[2] = candidate
  proposal[3] = 0 - 1
  proposal[4] = kind
  1

-> ffrrw_apply_factor_change(carrier, us, vs, ws, term, axis, candidate, n, m, p, weight) (i64[] i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64) i64
  old_u = us[term] ## i64
  old_v = vs[term] ## i64
  old_w = ws[term] ## i64
  new_u = old_u ## i64
  new_v = old_v ## i64
  new_w = old_w ## i64
  if axis == 0
    new_u = candidate
  if axis == 1
    new_v = candidate
  if axis == 2
    new_w = candidate
  weight = ffrrw_xor_outer_weight(carrier, old_u, old_v, old_w, n * m, m * p, n * p, weight)
  weight = ffrrw_xor_outer_weight(carrier, new_u, new_v, new_w, n * m, m * p, n * p, weight)
  z = ffrrw_set_factor(us, vs, ws, term, axis, candidate) ## i64
  weight

-> ffrrw_copy_terms(source_u, source_v, source_w, target_u, target_v, target_w, rank) (i64[] i64[] i64[] i64[] i64[] i64[] i64) i64
  i = 0 ## i64
  while i < rank
    target_u[i] = source_u[i]
    target_v[i] = source_v[i]
    target_w[i] = source_w[i]
    i += 1
  rank

-> ffrrw_terms_equal(left_u, left_v, left_w, right_u, right_v, right_w, rank) (i64[] i64[] i64[] i64[] i64[] i64[] i64) i64
  i = 0 ## i64
  while i < rank
    if left_u[i] != right_u[i] || left_v[i] != right_v[i] || left_w[i] != right_w[i]
      return 0
    i += 1
  1

-> ffrrw_terms_hash(us, vs, ws, rank) (i64[] i64[] i64[] i64) i64
  hash = 1469598103934665603 ## i64
  i = 0 ## i64
  while i < rank
    hash = ((hash ^ us[i]) * 1099511628211) & 9223372036854775807
    hash = ((hash ^ vs[i]) * 1099511628211) & 9223372036854775807
    hash = ((hash ^ ws[i]) * 1099511628211) & 9223372036854775807
    i += 1
  if hash == 0
    return 1
  hash

-> ffrrw_hash_archive_add(archive, count, value) (i64[] i64 i64) i64
  i = 0 ## i64
  while i < count
    if archive[i] == value
      return count
    i += 1
  if count < archive.size()
    archive[count] = value
    return count + 1
  count

# Exact, collision-safe archive of ordered term configurations.  Hashes are
# only a rejection filter; matching hashes are confirmed against every factor.
# The caller controls capacity, while the walk hard-caps it at 64 states.
-> ffrrw_floor_state_equal(archive_u, archive_v, archive_w, state, us, vs, ws, rank) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  base = state * rank ## i64
  term = 0 ## i64
  while term < rank
    if archive_u[base + term] != us[term] || archive_v[base + term] != vs[term] || archive_w[base + term] != ws[term]
      return 0
    term += 1
  1

-> ffrrw_floor_state_add(archive_u, archive_v, archive_w, hashes, count, capacity, us, vs, ws, rank) (i64[] i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64) i64
  value = ffrrw_terms_hash(us, vs, ws, rank) ## i64
  state = 0 ## i64
  while state < count
    if hashes[state] == value && ffrrw_floor_state_equal(archive_u, archive_v, archive_w, state, us, vs, ws, rank) == 1
      return count
    state += 1
  if count >= capacity
    return count
  base = count * rank ## i64
  term = 0 ## i64
  while term < rank
    archive_u[base + term] = us[term]
    archive_v[base + term] = vs[term]
    archive_w[base + term] = ws[term]
    term += 1
  hashes[count] = value
  count + 1

# Run one worm from an arbitrary planted or multiplication-tensor target.
# meta: attempts, start weight, best weight, accepted, strict improvements,
# forced tunnels, floor moves, distinct floor cells, consistency checks,
# exact hit, best proxy, flatten ranks U/V/W, max carrier, final weight,
# uphill accepts, neutral accepts, best-state resets, directed floor attempts,
# distinct floor configurations (capped at 64 per restart).  The extended
# offline entry point also materializes those configurations for correlated
# repair sweeps; the legacy wrapper below preserves every existing caller.
-> ffrrw_walk_target_floor_states(start_u, start_v, start_w, rank, n, m, p, target, attempts, seed, out_u, out_v, out_w, floor_archive, floor_state_u, floor_state_v, floor_state_w, floor_state_capacity, floor_state_count, meta) (i64[] i64[] i64[] i64 i64 i64 i64 i64[] i64 i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64[] i64[]) i64
  i = 0 ## i64
  while i < 21
    meta[i] = 0
    i += 1
  if rank < 1 || attempts < 1
    return 0 - 1
  words = ffrrw_tensor_words(n, m, p) ## i64
  bits = ffrrw_tensor_bits(n, m, p) ## i64
  archive_capacity = floor_state_capacity ## i64
  if archive_capacity > 64
    archive_capacity = 64
  if floor_archive.size() < words || floor_state_count.size() < 1 || archive_capacity < 0
    return 0 - 1
  if floor_state_u.size() < archive_capacity * rank || floor_state_v.size() < archive_capacity * rank || floor_state_w.size() < archive_capacity * rank
    return 0 - 1
  floor_state_count[0] = 0
  current_u = i64[rank]
  current_v = i64[rank]
  current_w = i64[rank]
  best_u = i64[rank]
  best_v = i64[rank]
  best_w = i64[rank]
  z = ffrrw_copy_terms(start_u, start_v, start_w, current_u, current_v, current_w, rank) ## i64
  z = ffrrw_copy_terms(start_u, start_v, start_w, best_u, best_v, best_w, rank)
  carrier = i64[words]
  weight = ffrrw_build_residual(current_u, current_v, current_w, rank, n, m, p, target, carrier) ## i64
  if weight < 0
    return 0 - 1
  proxy_meta = i64[4]
  proxy = ffrrw_support_proxy(carrier, n, m, p, proxy_meta) ## i64
  best_weight = weight ## i64
  best_proxy = proxy ## i64
  meta[1] = weight
  floor_cells = i64[words]
  floor_hashes = i64[64]
  floor_hash_count = 0 ## i64
  floor_state_hashes = i64[64]
  if weight == 1
    cell = ffrrw_active_cell(carrier, bits, weight, i64[2]) ## i64
    if cell >= 0
      floor_cells[cell / 64] = floor_cells[cell / 64] | (1 << (cell % 64))
    floor_hash_count = ffrrw_hash_archive_add(floor_hashes, floor_hash_count, ffrrw_terms_hash(current_u, current_v, current_w, rank))
    floor_state_count[0] = ffrrw_floor_state_add(floor_state_u, floor_state_v, floor_state_w, floor_state_hashes, floor_state_count[0], archive_capacity, current_u, current_v, current_w, rank)
  rng = i64[2]
  rng[0] = (seed & 9223372036854775807) + 1
  rng[1] = 1442695040888963407
  proposal = i64[5]
  stall = 0 ## i64
  since_best = 0 ## i64
  step = 0 ## i64
  max_carrier = weight ## i64
  while step < attempts && best_weight != 0
    random = ffrrw_rand(rng) % 100 ## i64
    mode = 0 ## i64
    if random >= 45 && random < 80
      mode = 1
    if random >= 80 && random < 95
      mode = 2
    if random >= 95
      mode = 3
    forced = 0 ## i64
    if stall >= 96
      mode = 1
      forced = 1
    have = ffrrw_random_proposal(carrier, current_u, current_v, current_w, rank, n, m, p, weight, rng, mode, proposal) ## i64
    if have == 1
      if weight == 1 && proposal[4] == 1
        meta[19] += 1
      term = proposal[0] ## i64
      axis = proposal[1] ## i64
      candidate = proposal[2] ## i64
      old = ffrrw_factor(current_u, current_v, current_w, term, axis) ## i64
      next_weight = ffrrw_apply_factor_change(carrier, current_u, current_v, current_w, term, axis, candidate, n, m, p, weight) ## i64
      next_proxy_meta = i64[4]
      next_proxy = ffrrw_support_proxy(carrier, n, m, p, next_proxy_meta) ## i64
      accept = 0 ## i64
      if next_weight < weight
        accept = 1
      if next_weight == weight
        if next_proxy < proxy || next_weight <= 2 || (ffrrw_rand(rng) & 15) == 0
          accept = 1
      if forced == 1 && next_weight <= best_weight + 12 && next_weight <= 64
        accept = 1
      if next_weight > weight && next_weight <= best_weight + 8 && (ffrrw_rand(rng) & 1023) == 0
        accept = 1
      if accept == 1
        if next_weight > max_carrier
          max_carrier = next_weight
        meta[3] += 1
        if next_weight > weight
          meta[16] += 1
        if next_weight == weight
          meta[17] += 1
        weight = next_weight
        proxy = next_proxy
        if forced == 1
          meta[5] += 1
          stall = 0
        else
          stall += 1
        if weight == 1
          meta[6] += 1
          cell = ffrrw_active_cell(carrier, bits, weight, rng)
          if cell >= 0
            floor_cells[cell / 64] = floor_cells[cell / 64] | (1 << (cell % 64))
          floor_hash_count = ffrrw_hash_archive_add(floor_hashes, floor_hash_count, ffrrw_terms_hash(current_u, current_v, current_w, rank))
          floor_state_count[0] = ffrrw_floor_state_add(floor_state_u, floor_state_v, floor_state_w, floor_state_hashes, floor_state_count[0], archive_capacity, current_u, current_v, current_w, rank)
        better = 0 ## i64
        if weight < best_weight
          better = 1
        if weight == best_weight && proxy < best_proxy
          better = 1
        if better == 1
          best_weight = weight
          best_proxy = proxy
          z = ffrrw_copy_terms(current_u, current_v, current_w, best_u, best_v, best_w, rank)
          meta[4] += 1
          stall = 0
          since_best = 0
        else
          since_best += 1
      else
        undo = ffrrw_apply_factor_change(carrier, current_u, current_v, current_w, term, axis, old, n, m, p, next_weight) ## i64
        weight = undo
        stall += 1
        since_best += 1
      if (step & 4095) == 4095
        check = i64[words]
        rebuilt = ffrrw_build_residual(current_u, current_v, current_w, rank, n, m, p, target, check) ## i64
        meta[8] += 1
        if rebuilt != weight || ffrrw_equal(check, carrier, words) != 1
          return 0 - 2
    else
      stall += 1
      since_best += 1
    # An uphill tunnel is a bounded excursion, not permission to diffuse away
    # from the sparse carrier forever.  Rebase to the best state and launch a
    # fresh tunnel when an episode has not improved for 2,048 proposals.
    if since_best >= 2048
      z = ffrrw_copy_terms(best_u, best_v, best_w, current_u, current_v, current_w, rank)
      weight = ffrrw_build_residual(current_u, current_v, current_w, rank, n, m, p, target, carrier)
      proxy = ffrrw_support_proxy(carrier, n, m, p, proxy_meta)
      stall = 96
      since_best = 0
      meta[18] += 1
    step += 1
  z = ffrrw_copy_terms(best_u, best_v, best_w, out_u, out_v, out_w, rank)
  best_carrier = i64[words]
  rebuilt_best = ffrrw_build_residual(best_u, best_v, best_w, rank, n, m, p, target, best_carrier) ## i64
  if rebuilt_best != best_weight
    return 0 - 2
  structure = i64[8]
  z = ffrrw_structure(best_carrier, n, m, p, structure)
  meta[0] = step
  meta[2] = best_weight
  meta[7] = ffrrw_weight(floor_cells, words)
  meta[9] = 0
  if best_weight == 0
    meta[9] = 1
  meta[10] = structure[7]
  meta[11] = structure[3]
  meta[12] = structure[4]
  meta[13] = structure[5]
  meta[14] = max_carrier
  meta[15] = weight
  meta[20] = floor_hash_count
  z = ffrrw_copy(floor_cells, floor_archive, words)
  best_weight

-> ffrrw_walk_target(start_u, start_v, start_w, rank, n, m, p, target, attempts, seed, out_u, out_v, out_w, floor_archive, meta) (i64[] i64[] i64[] i64 i64 i64 i64 i64[] i64 i64 i64[] i64[] i64[] i64[] i64[]) i64
  unused_u = i64[1]
  unused_v = i64[1]
  unused_w = i64[1]
  unused_count = i64[1]
  ffrrw_walk_target_floor_states(start_u, start_v, start_w, rank, n, m, p, target, attempts, seed, out_u, out_v, out_w, floor_archive, unused_u, unused_v, unused_w, 0, unused_count, meta)

-> ffrrw_independent_gate(us, vs, ws, rank, n, m, p) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  capacity = ffr_default_capacity(n, m, p) ## i64
  state = i64[ffr_state_size(capacity)]
  loaded = ffr_init_terms_cap(state, us, vs, ws, rank, n, m, p, capacity, 2251701, 4, 8, 1000, 250) ## i64
  if loaded == rank && ffr_verify_current_exact(state, n, m, p) == 1
    return 1
  0

# Search every one-term deletion of an exact rank-R source.  The output always
# contains exactly R-1 nonzero distinct terms.  meta: attempts, restarts,
# minimum initial weight, best weight, starts improved, accepted, strict
# improvements, forced tunnels, floor moves, distinct floor cells,
# consistency checks, exact hit, proxy, ranks U/V/W, max carrier, best drop,
# independent exact gate, uphill/neutral accepts, best-state resets, directed
# floor attempts, and summed per-restart floor-configuration coverage.
-> ffrrw_search_rank_minus_one(source_u, source_v, source_w, source_rank, n, m, p, attempts, seed, out_u, out_v, out_w, meta) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64[] i64[] i64[] i64[]) i64
  i = 0 ## i64
  while i < 25
    meta[i] = 0
    i += 1
  if source_rank < 2 || attempts < source_rank
    return 0 - 1
  target_rank = source_rank - 1 ## i64
  target = i64[ffrrw_tensor_words(n, m, p)]
  if ffrrw_build_mmt_target(target, n, m, p) < 1
    return 0 - 1
  per = attempts / source_rank ## i64
  remainder = attempts % source_rank ## i64
  global_weight = 9223372036854775807 ## i64
  global_proxy = 9223372036854775807 ## i64
  min_initial = 9223372036854775807 ## i64
  global_floor = i64[target.size()]
  drop = 0 ## i64
  while drop < source_rank && global_weight != 0
    start_u = i64[target_rank]
    start_v = i64[target_rank]
    start_w = i64[target_rank]
    at = 0 ## i64
    term = 0 ## i64
    while term < source_rank
      if term != drop
        start_u[at] = source_u[term]
        start_v[at] = source_v[term]
        start_w[at] = source_w[term]
        at += 1
      term += 1
    budget = per ## i64
    if drop < remainder
      budget += 1
    local_u = i64[target_rank]
    local_v = i64[target_rank]
    local_w = i64[target_rank]
    local_floor = i64[target.size()]
    local = i64[21]
    local_weight = ffrrw_walk_target(start_u, start_v, start_w, target_rank, n, m, p, target, budget, seed + drop * 104729, local_u, local_v, local_w, local_floor, local) ## i64
    if local_weight < 0
      return local_weight
    if local[1] < min_initial
      min_initial = local[1]
    if local_weight < local[1]
      meta[4] += 1
    better = 0 ## i64
    if local_weight < global_weight
      better = 1
    if local_weight == global_weight && local[10] < global_proxy
      better = 1
    if better == 1
      global_weight = local_weight
      global_proxy = local[10]
      z = ffrrw_copy_terms(local_u, local_v, local_w, out_u, out_v, out_w, target_rank)
      meta[12] = local[10]
      meta[13] = local[11]
      meta[14] = local[12]
      meta[15] = local[13]
      meta[17] = drop
    meta[0] += local[0]
    meta[1] += 1
    meta[5] += local[3]
    meta[6] += local[4]
    meta[7] += local[5]
    meta[8] += local[6]
    word = 0 ## i64
    while word < global_floor.size()
      global_floor[word] = global_floor[word] | local_floor[word]
      word += 1
    meta[10] += local[8]
    if local[14] > meta[16]
      meta[16] = local[14]
    meta[20] += local[16]
    meta[21] += local[17]
    meta[22] += local[18]
    meta[23] += local[19]
    meta[24] += local[20]
    drop += 1
  meta[2] = min_initial
  meta[3] = global_weight
  meta[9] = ffrrw_weight(global_floor, global_floor.size())
  meta[11] = 0
  meta[18] = 0
  if global_weight == 0
    meta[11] = 1
    meta[18] = ffrrw_independent_gate(out_u, out_v, out_w, target_rank, n, m, p)
    if meta[18] != 1
      return 0 - 3
  global_weight
