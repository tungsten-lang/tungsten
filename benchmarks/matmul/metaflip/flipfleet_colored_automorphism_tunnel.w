# Exact multi-colour partial-automorphism tunnels.
#
# Fix two elementary tensor automorphisms g and h.  Each source term may stay
# put or take exactly one of the three colours g, h, or hg.  For every nonzero
# choice delta
#
#     d(i,c) = t_i XOR c(t_i),  c in {g,h,hg},
#
# a legal coloured tunnel is an XOR-zero set containing at most one colour of
# each source term.  Gaussian elimination first computes the *complete* linear
# relation space of all 3R columns.  We then enforce the nonlinear exclusivity
# condition explicitly.  Thus cross-colour cancellation is visible even when
# neither of the corresponding single-automorphism subsets is exact.
#
# If the projected nullity fits the caller's exhaustive limits, every one of
# the 2^d-1 kernel vectors is checked.  Larger kernels use a quantified bounded
# closure: every basis vector, then every pair of basis vectors that fits, then
# deterministic full-width samples.  Every exclusive endpoint is independently
# gated against the complete n^6 tensor before it is classified.

use flipfleet_partial_automorphism_nullspace
use flipfleet_global_isotropy

+ FFCATWorkspace
  -> new(rank, n, capacity)
    @config = i64[7]
    @config[0] = rank
    @config[1] = n
    @config[2] = capacity
    @config[3] = 3 * rank
    @config[4] = ffpa_tensor_words(n)
    columns = @config[3] ## i64
    words = @config[4] ## i64
    coefficient_words = ffpan_coeff_words(columns) ## i64
    pairs = columns * (columns - 1) / 2 ## i64
    @config[5] = ffpa_table_capacity(pairs)
    @config[6] = 64
    @images_u = i64[columns]
    @images_v = i64[columns]
    @images_w = i64[columns]
    @deltas = i64[columns * words]
    @column_term = i64[columns]
    @column_color = i64[columns]
    @dependencies = i64[columns * coefficient_words]
    @basis_rows = i64[columns * words]
    @basis_coefficients = i64[columns * coefficient_words]
    @pivot_owners = i32[words * 64]
    @work = i64[words]
    @work_coefficients = i64[coefficient_words]
    @current = i64[coefficient_words]
    @assignment = i32[rank]
    @ids = i64[columns]
    @raw_u = i64[capacity]
    @raw_v = i64[capacity]
    @raw_w = i64[capacity]
    @candidate_u = i64[capacity]
    @candidate_v = i64[capacity]
    @candidate_w = i64[capacity]
    @endpoint = i64[ffw_state_size(capacity)]
    @fingerprint_a = i64[columns]
    @fingerprint_b = i64[columns]
    @hash_heads = i32[@config[5]]
    @hash_next = i32[pairs]
    @pair_a = i32[pairs]
    @pair_b = i32[pairs]
    @sparse_rows = i64[@config[6] * coefficient_words]

  -> rank()
    @config[0]
  -> n()
    @config[1]
  -> capacity()
    @config[2]
  -> max_columns()
    @config[3]
  -> words()
    @config[4]
  -> table_capacity()
    @config[5]
  -> sparse_capacity()
    @config[6]
  -> images_u()
    @images_u
  -> images_v()
    @images_v
  -> images_w()
    @images_w
  -> deltas()
    @deltas
  -> column_term()
    @column_term
  -> column_color()
    @column_color
  -> dependencies()
    @dependencies
  -> basis_rows()
    @basis_rows
  -> basis_coefficients()
    @basis_coefficients
  -> pivot_owners()
    @pivot_owners
  -> work()
    @work
  -> work_coefficients()
    @work_coefficients
  -> current()
    @current
  -> assignment()
    @assignment
  -> ids()
    @ids
  -> raw_u()
    @raw_u
  -> raw_v()
    @raw_v
  -> raw_w()
    @raw_w
  -> candidate_u()
    @candidate_u
  -> candidate_v()
    @candidate_v
  -> candidate_w()
    @candidate_w
  -> endpoint()
    @endpoint
  -> fingerprint_a()
    @fingerprint_a
  -> fingerprint_b()
    @fingerprint_b
  -> hash_heads()
    @hash_heads
  -> hash_next()
    @hash_next
  -> pair_a()
    @pair_a
  -> pair_b()
    @pair_b
  -> sparse_rows()
    @sparse_rows

-> ffcat_same_term(u0, v0, w0, u1, v1, w1) (i64 i64 i64 i64 i64 i64) i64
  if u0 == u1 && v0 == v1 && w0 == w1
    return 1
  0

# Images are stored in three rank-sized slabs: 0=g, 1=h, 2=hg.  Only nonzero
# deltas become elimination columns; fixed choices are indistinguishable from
# identity and would otherwise inflate nullity with singleton noise.
-> ffcat_build_columns(us, vs, ws, rank, n, g, h, workspace) (i64[] i64[] i64[] i64 i64 i64[] i64[] FFCATWorkspace) i64
  if workspace == nil || workspace.rank() != rank || workspace.n() != n
    return 0 - 1
  if g.size() < 4 || h.size() < 4 || rank < 1
    return 0 - 1
  images_u = workspace.images_u()
  images_v = workspace.images_v()
  images_w = workspace.images_w()
  deltas = workspace.deltas()
  column_term = workspace.column_term()
  column_color = workspace.column_color()
  words = workspace.words() ## i64
  out_g = i64[3]
  out_h = i64[3]
  out_hg = i64[3]
  term = 0 ## i64
  while term < rank
    if ffpa_transform_term_kind(us[term], vs[term], ws[term], n, g[0], g[1], g[2], g[3], out_g) != 1
      return 0 - 1
    if ffpa_transform_term_kind(us[term], vs[term], ws[term], n, h[0], h[1], h[2], h[3], out_h) != 1
      return 0 - 1
    if ffpa_transform_term_kind(out_g[0], out_g[1], out_g[2], n, h[0], h[1], h[2], h[3], out_hg) != 1
      return 0 - 1
    images_u[term] = out_g[0]
    images_v[term] = out_g[1]
    images_w[term] = out_g[2]
    images_u[rank + term] = out_h[0]
    images_v[rank + term] = out_h[1]
    images_w[rank + term] = out_h[2]
    images_u[2 * rank + term] = out_hg[0]
    images_v[2 * rank + term] = out_hg[1]
    images_w[2 * rank + term] = out_hg[2]
    term += 1

  columns = 0 ## i64
  color = 0 ## i64
  while color < 3
    term = 0
    while term < rank
      image = color * rank + term ## i64
      if ffcat_same_term(us[term], vs[term], ws[term], images_u[image], images_v[image], images_w[image]) == 0
        z = ffpa_clear_row(deltas, columns * words, words) ## i64
        z = ffpa_xor_outer(deltas, columns * words, us[term], vs[term], ws[term], n)
        z = ffpa_xor_outer(deltas, columns * words, images_u[image], images_v[image], images_w[image], n)
        if ffpan_row_zero(deltas, columns * words, words) == 1
          return 0 - 1
        column_term[columns] = term
        column_color[columns] = color
        columns += 1
      term += 1
    color += 1
  columns

-> ffcat_clear(row, words) (i64[] i64) i64
  i = 0 ## i64
  while i < words
    row[i] = 0
    i += 1
  words

-> ffcat_xor_dependency(dependencies, dependency, coefficient_words, current) (i64[] i64 i64 i64[]) i64
  word = 0 ## i64
  while word < coefficient_words
    current[word] = current[word] ^ dependencies[dependency * coefficient_words + word]
    word += 1
  coefficient_words

# Two XOR-linear fingerprints.  They only select hash buckets; every match is
# compared against the complete tensor rows before it is admitted.
-> ffcat_fingerprint_rows(deltas, columns, words, fingerprint_a, fingerprint_b) (i64[] i64 i64 i64[] i64[]) i64
  column = 0 ## i64
  while column < columns
    first = 0 ## i64
    second = 0 ## i64
    word = 0 ## i64
    while word < words
      value = deltas[column * words + word] ## i64
      left = (word * 13 + 7) % 63 + 1 ## i64
      right = (word * 29 + 19) % 63 + 1 ## i64
      first = first ^ (value << left) ^ (value >> (64 - left))
      second = second ^ (value << right) ^ (value >> (64 - right)) ^ (value << ((word % 31) + 1))
      word += 1
    fingerprint_a[column] = first
    fingerprint_b[column] = second
    column += 1
  columns

-> ffcat_fingerprint_slot(first, second, capacity) (i64 i64 i64) i64
  (first ^ (second << 1) ^ (second >> 31)) & (capacity - 1)

-> ffcat_sparse_legal(column_term, column_color, ids, count) (i64[] i64[] i64[] i64) i64
  color_mask = 0 ## i64
  i = 0 ## i64
  while i < count
    color_mask = color_mask | (1 << column_color[ids[i]])
    j = i + 1 ## i64
    while j < count
      if column_term[ids[i]] == column_term[ids[j]]
        return 0
      j += 1
    i += 1
  if color_mask == 1 || color_mask == 2 || color_mask == 4
    return 0
  1

-> ffcat_sparse_store(rows, count, coefficient_words, ids, weight) (i64[] i64 i64 i64[] i64) i64
  offset = count * coefficient_words ## i64
  word = 0 ## i64
  while word < coefficient_words
    rows[offset + word] = 0
    word += 1
  i = 0 ## i64
  while i < weight
    column = ids[i] ## i64
    rows[offset + column / 64] = rows[offset + column / 64] | (1 << (column % 64))
    i += 1
  count + 1

-> ffcat_sparse_cross_coupled(workspace, us, vs, ws, rank, n, g, ids, weight) (FFCATWorkspace i64[] i64[] i64[] i64 i64 i64[] i64[] i64) i64
  assignment = workspace.assignment()
  term = 0 ## i64
  while term < rank
    assignment[term] = 0
    term += 1
  i = 0 ## i64
  while i < weight
    column = ids[i] ## i64
    assignment[workspace.column_term()[column]] = workspace.column_color()[column] + 1
    i += 1
  if ffcat_staging_kind(us, vs, ws, rank, n, g, workspace.images_u(), workspace.images_v(), workspace.images_w(), assignment, workspace.work()) == 0
    return 1
  0

# Complete coloured support-2/3/4 search, stopped only when `cap` legal exact
# masks have been retained.  meta: full-row comparisons, truncated, maximum
# support reached.  Canonical index ordering emits each relation once.
-> ffcat_sparse_masks(workspace, us, vs, ws, rank, n, g, columns, cap, meta) (FFCATWorkspace i64[] i64[] i64[] i64 i64 i64[] i64 i64 i64[]) i64
  if cap < 1
    return 0
  if cap > workspace.sparse_capacity()
    cap = workspace.sparse_capacity()
  meta[0] = 0
  meta[1] = 0
  meta[2] = 0
  deltas = workspace.deltas()
  words = workspace.words() ## i64
  coefficient_words = ffpan_coeff_words(columns) ## i64
  column_term = workspace.column_term()
  column_color = workspace.column_color()
  fingerprint_a = workspace.fingerprint_a()
  fingerprint_b = workspace.fingerprint_b()
  ffcat_fingerprint_rows(deltas, columns, words, fingerprint_a, fingerprint_b)
  rows = workspace.sparse_rows()
  ids = i64[4]
  count = 0 ## i64

  a = 0 ## i64
  while a < columns - 1
    b = a + 1 ## i64
    while b < columns
      if fingerprint_a[a] == fingerprint_a[b] && fingerprint_b[a] == fingerprint_b[b]
        meta[0] = meta[0] + 1
        if ffpa_row_equal(deltas, a * words, b * words, words) == 1
          ids[0] = a
          ids[1] = b
          if ffcat_sparse_legal(column_term, column_color, ids, 2) == 1 && ffcat_sparse_cross_coupled(workspace, us, vs, ws, rank, n, g, ids, 2) == 1
            count = ffcat_sparse_store(rows, count, coefficient_words, ids, 2)
            meta[2] = 2
            if count >= cap
              meta[1] = 1
              return count
      b += 1
    a += 1

  capacity = workspace.table_capacity() ## i64
  heads = workspace.hash_heads()
  nexts = workspace.hash_next()
  i = 0
  while i < capacity
    heads[i] = 0
    i += 1
  column = 0 ## i64
  while column < columns
    slot = ffcat_fingerprint_slot(fingerprint_a[column], fingerprint_b[column], capacity) ## i64
    nexts[column] = heads[slot]
    heads[slot] = column + 1
    column += 1
  a = 0
  while a < columns - 2
    b = a + 1
    while b < columns - 1
      wanted_a = fingerprint_a[a] ^ fingerprint_a[b] ## i64
      wanted_b = fingerprint_b[a] ^ fingerprint_b[b] ## i64
      slot = ffcat_fingerprint_slot(wanted_a, wanted_b, capacity)
      chain = heads[slot] ## i64
      while chain != 0
        c = chain - 1 ## i64
        if c > b && fingerprint_a[c] == wanted_a && fingerprint_b[c] == wanted_b
          meta[0] = meta[0] + 1
          if ffpa_pair_equals_single(deltas, a, b, c, words) == 1
            ids[0] = a
            ids[1] = b
            ids[2] = c
            if ffcat_sparse_legal(column_term, column_color, ids, 3) == 1 && ffcat_sparse_cross_coupled(workspace, us, vs, ws, rank, n, g, ids, 3) == 1
              count = ffcat_sparse_store(rows, count, coefficient_words, ids, 3)
              meta[2] = 3
              if count >= cap
                meta[1] = 1
                return count
        chain = nexts[c]
      b += 1
    a += 1

  i = 0
  while i < capacity
    heads[i] = 0
    i += 1
  pair_a = workspace.pair_a()
  pair_b = workspace.pair_b()
  pair_id = 0 ## i64
  a = 0
  while a < columns - 1
    b = a + 1
    while b < columns
      pair_first = fingerprint_a[a] ^ fingerprint_a[b] ## i64
      pair_second = fingerprint_b[a] ^ fingerprint_b[b] ## i64
      slot = ffcat_fingerprint_slot(pair_first, pair_second, capacity)
      chain = heads[slot] ## i64
      while chain != 0
        prior = chain - 1 ## i64
        c = pair_a[prior] ## i64
        d = pair_b[prior] ## i64
        if d < a
          prior_first = fingerprint_a[c] ^ fingerprint_a[d] ## i64
          prior_second = fingerprint_b[c] ^ fingerprint_b[d] ## i64
          if prior_first == pair_first && prior_second == pair_second
            meta[0] = meta[0] + 1
            if ffpa_pair_equal(deltas, a, b, c, d, words) == 1
              ids[0] = c
              ids[1] = d
              ids[2] = a
              ids[3] = b
              if ffcat_sparse_legal(column_term, column_color, ids, 4) == 1 && ffcat_sparse_cross_coupled(workspace, us, vs, ws, rank, n, g, ids, 4) == 1
                count = ffcat_sparse_store(rows, count, coefficient_words, ids, 4)
                meta[2] = 4
                if count >= cap
                  meta[1] = 1
                  return count
        chain = nexts[prior]
      pair_a[pair_id] = a
      pair_b[pair_id] = b
      nexts[pair_id] = heads[slot]
      heads[slot] = pair_id + 1
      pair_id += 1
      b += 1
    a += 1
  count

-> ffcat_ctz(value) (i64) i64
  bit = 0 ## i64
  while bit < 63 && ((value >> bit) & 1) == 0
    bit += 1
  bit

# Fill one bounded (non-exhaustive) kernel combination.  `index` is zero based.
# Singles and pairs are complete prefixes; the remaining samples mix all basis
# directions with a deterministic 64-bit avalanche.
-> ffcat_fill_bounded(dependencies, nullity, coefficient_words, index, current, kind) (i64[] i64 i64 i64 i64[] i64[]) i64
  ffcat_clear(current, coefficient_words)
  if index < nullity
    ffcat_xor_dependency(dependencies, index, coefficient_words, current)
    kind[0] = 1
    return 1
  local = index - nullity ## i64
  pair_total = nullity * (nullity - 1) / 2 ## i64
  if local < pair_total
    seen = 0 ## i64
    a = 0 ## i64
    while a < nullity - 1
      b = a + 1 ## i64
      while b < nullity
        if seen == local
          ffcat_xor_dependency(dependencies, a, coefficient_words, current)
          ffcat_xor_dependency(dependencies, b, coefficient_words, current)
          kind[0] = 2
          return 1
        seen += 1
        b += 1
      a += 1
  seed = (index + 1) * 6364136223846793005 + 1442695040888963407 ## i64
  chosen = 0 ## i64
  basis = 0 ## i64
  while basis < nullity
    mixed = seed ^ (basis * 7046029254386353131) ## i64
    mixed = mixed ^ (mixed >> 29)
    mixed = mixed * 3202034522624059733
    mixed = mixed ^ (mixed >> 31)
    if (mixed & 1) != 0
      ffcat_xor_dependency(dependencies, basis, coefficient_words, current)
      chosen += 1
    basis += 1
  if chosen == 0
    ffcat_xor_dependency(dependencies, index % nullity, coefficient_words, current)
  kind[0] = 3
  1

-> ffcat_copy_candidate(source_u, source_v, source_w, target_u, target_v, target_w, rank) (i64[] i64[] i64[] i64[] i64[] i64[] i64) i64
  i = 0 ## i64
  while i < rank
    target_u[i] = source_u[i]
    target_v[i] = source_v[i]
    target_w[i] = source_w[i]
    i += 1
  rank

# Return bit 0 when the assignment admits an exact g-then-h staging and bit 1
# when it admits an exact h-then-g staging.  Zero is the interesting case: the
# two colour syndromes cancel only together, so the move is not a composition
# of the corresponding binary partial-automorphism edges.
-> ffcat_staging_kind(us, vs, ws, rank, n, g, images_u, images_v, images_w, assignment, stage) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64[] i32[] i64[]) i64
  words = ffpa_tensor_words(n) ## i64
  ffpa_clear_row(stage, 0, words)
  term = 0 ## i64
  while term < rank
    choice = assignment[term] ## i64
    if choice == 1 || choice == 3
      z = ffpa_xor_outer(stage, 0, us[term], vs[term], ws[term], n)
      z = ffpa_xor_outer(stage, 0, images_u[term], images_v[term], images_w[term], n)
    term += 1
  staged_g = ffpan_row_zero(stage, 0, words) ## i64

  ffpa_clear_row(stage, 0, words)
  commute = 1 ## i64
  commute_probe = i64[3]
  term = 0
  while term < rank
    choice = assignment[term] ## i64
    if choice == 2 || choice == 3
      z = ffpa_xor_outer(stage, 0, us[term], vs[term], ws[term], n)
      z = ffpa_xor_outer(stage, 0, images_u[rank + term], images_v[rank + term], images_w[rank + term], n)
    if choice == 3
      if ffpa_transform_term_kind(images_u[rank + term], images_v[rank + term], images_w[rank + term], n, g[0], g[1], g[2], g[3], commute_probe) != 1
        commute = 0
      else
        if ffcat_same_term(commute_probe[0], commute_probe[1], commute_probe[2], images_u[2 * rank + term], images_v[2 * rank + term], images_w[2 * rank + term]) == 0
          commute = 0
    term += 1
  staged_h = 0 ## i64
  if commute == 1 && ffpan_row_zero(stage, 0, words) == 1
    staged_h = 1
  staged_g + 2 * staged_h

# Audit one generator pair.  The return value is the number of genuine
# multi-colour endpoints.  `meta` layout:
#   0 columns, 1 nullity, 2 exhaustive, 3 theoretical combinations (-1 if
#   too large), 4 combinations scanned, 5 exclusive, 6 delta gates,
#   7 endpoint gates, 8 failures, 9 monochrome, 10 multicolour,
#   11 source quotient, 12/13/14 g/h/hg quotients, 15 genuine,
#   16 rank drops, 17 density improvements, 18 best rank, 19 best density,
#   20 max source distance, 21 max min-global distance, 22 max selected terms,
#   23/24/25 bounded singles/pairs/random samples, 26 g-first staged,
#   27 h-first staged, 28 irreducibly cross-colour, 29/30 cross-colour rank
#   drops/density improvements, 31 max cross-colour source distance,
#   32 injected exact support<=4 masks, 33 sparse search truncated,
#   34 sparse fingerprint hits fully compared.
-> ffcat_audit_pair(us, vs, ws, rank, n, capacity, g, h, max_exhaustive_bits, combination_cap, seed, workspace, best_u, best_v, best_w, meta) (i64[] i64[] i64[] i64 i64 i64 i64[] i64[] i64 i64 i64 FFCATWorkspace i64[] i64[] i64[] i64[]) i64
  if workspace == nil || meta.size() < 35 || best_u.size() < capacity || best_v.size() < capacity || best_w.size() < capacity
    return 0 - 1
  i = 0 ## i64
  while i < 35
    meta[i] = 0
    i += 1
  source_density = ffgir_density(us, vs, ws, rank) ## i64
  meta[18] = rank
  meta[19] = source_density
  columns = ffcat_build_columns(us, vs, ws, rank, n, g, h, workspace) ## i64
  if columns < 1
    return 0 - 1
  meta[0] = columns
  words = workspace.words() ## i64
  coefficient_words = ffpan_coeff_words(columns) ## i64
  nullspace_meta = i64[4]
  nullity = ffpan_nullspace_into(workspace.deltas(), columns, words, workspace.dependencies(), workspace.basis_rows(), workspace.basis_coefficients(), workspace.pivot_owners(), workspace.work(), workspace.work_coefficients(), nullspace_meta) ## i64
  if nullity < 1
    return 0
  meta[1] = nullity
  theoretical = 0 - 1 ## i64
  if nullity < 62
    theoretical = (1 << nullity) - 1
  meta[3] = theoretical
  exhaustive = 0 ## i64
  limit = combination_cap ## i64
  if nullity <= max_exhaustive_bits && theoretical >= 0 && theoretical <= combination_cap
    exhaustive = 1
    limit = theoretical
  meta[2] = exhaustive
  if limit < 1
    return 0

  sparse_count = 0 ## i64
  if exhaustive == 0
    sparse_cap = workspace.sparse_capacity() ## i64
    if sparse_cap > limit
      sparse_cap = limit
    sparse_meta = i64[3]
    sparse_count = ffcat_sparse_masks(workspace, us, vs, ws, rank, n, g, columns, sparse_cap, sparse_meta)
    meta[32] = sparse_count
    meta[33] = sparse_meta[1]
    meta[34] = sparse_meta[0]

  dependencies = workspace.dependencies()
  current = workspace.current()
  assignment = workspace.assignment()
  column_term = workspace.column_term()
  column_color = workspace.column_color()
  deltas = workspace.deltas()
  ids = workspace.ids()
  images_u = workspace.images_u()
  images_v = workspace.images_v()
  images_w = workspace.images_w()
  raw_u = workspace.raw_u()
  raw_v = workspace.raw_v()
  raw_w = workspace.raw_w()
  candidate_u = workspace.candidate_u()
  candidate_v = workspace.candidate_v()
  candidate_w = workspace.candidate_w()
  endpoint = workspace.endpoint()
  stage = workspace.work()
  ffcat_clear(current, coefficient_words)
  kind = i64[1]
  combination = 1 ## i64
  while combination <= limit
    if exhaustive == 1
      toggled = ffcat_ctz(combination) ## i64
      ffcat_xor_dependency(dependencies, toggled, coefficient_words, current)
    else
      if combination <= sparse_count
        ffpan_copy(workspace.sparse_rows(), (combination - 1) * coefficient_words, current, 0, coefficient_words)
      else
        ffcat_fill_bounded(dependencies, nullity, coefficient_words, combination - sparse_count - 1, current, kind)
        if kind[0] == 1
          meta[23] = meta[23] + 1
        if kind[0] == 2
          meta[24] = meta[24] + 1
        if kind[0] == 3
          meta[25] = meta[25] + 1
    meta[4] = meta[4] + 1

    term = 0
    while term < rank
      assignment[term] = 0
      term += 1
    conflict = 0 ## i64
    selected_columns = 0 ## i64
    selected_terms = 0 ## i64
    color_mask = 0 ## i64
    column = 0 ## i64
    while column < columns && conflict == 0
      if ((current[column / 64] >> (column % 64)) & 1) != 0
        term = column_term[column]
        color = column_color[column]
        if assignment[term] != 0
          conflict = 1
        else
          assignment[term] = color + 1
          ids[selected_columns] = column
          selected_columns += 1
          selected_terms += 1
          color_mask = color_mask | (1 << color)
      column += 1
    if conflict == 0 && selected_columns > 0
      meta[5] = meta[5] + 1
      if selected_terms > meta[22]
        meta[22] = selected_terms
      if ffpa_relation_exact(deltas, ids, selected_columns, words) != 1
        meta[8] = meta[8] + 1
      else
        meta[6] = meta[6] + 1
        if color_mask == 1 || color_mask == 2 || color_mask == 4
          meta[9] = meta[9] + 1
        else
          meta[10] = meta[10] + 1
        ffcat_copy_candidate(us, vs, ws, raw_u, raw_v, raw_w, rank)
        term = 0
        while term < rank
          choice = assignment[term] ## i64
          if choice > 0
            image = (choice - 1) * rank + term ## i64
            raw_u[term] = images_u[image]
            raw_v[term] = images_v[image]
            raw_w[term] = images_w[image]
          term += 1
        endpoint_rank = ffpan_parity_compact(raw_u, raw_v, raw_w, rank, candidate_u, candidate_v, candidate_w) ## i64
        full_exact = 0 ## i64
        if endpoint_rank > 0 && endpoint_rank <= capacity
          loaded = ffw_init_terms_cap(endpoint, candidate_u, candidate_v, candidate_w, endpoint_rank, n, capacity, 910019 + seed * 131 + combination * 17, 0, 1, 1, 1) ## i64
          if loaded == endpoint_rank && ffw_verify_current_exact(endpoint, n) == 1
            full_exact = 1
            meta[7] = meta[7] + 1
        if full_exact == 0
          meta[8] = meta[8] + 1
        if full_exact == 1
          source_distance = ffpan_term_set_distance_unique(us, vs, ws, rank, candidate_u, candidate_v, candidate_w, endpoint_rank) ## i64
          g_distance = ffpan_term_set_distance_unique(images_u, images_v, images_w, rank, candidate_u, candidate_v, candidate_w, endpoint_rank) ## i64
          h_distance = ffpan_term_set_distance_unique(images_u, images_v, images_w, rank, candidate_u, candidate_v, candidate_w, endpoint_rank) ## i64
          # h and hg slabs need explicit offsets, so compute their distances
          # with a compact copy into raw scratch after retaining source/g.
          term = 0
          while term < rank
            raw_u[term] = images_u[rank + term]
            raw_v[term] = images_v[rank + term]
            raw_w[term] = images_w[rank + term]
            term += 1
          h_distance = ffpan_term_set_distance_unique(raw_u, raw_v, raw_w, rank, candidate_u, candidate_v, candidate_w, endpoint_rank)
          term = 0
          while term < rank
            raw_u[term] = images_u[2 * rank + term]
            raw_v[term] = images_v[2 * rank + term]
            raw_w[term] = images_w[2 * rank + term]
            term += 1
          hg_distance = ffpan_term_set_distance_unique(raw_u, raw_v, raw_w, rank, candidate_u, candidate_v, candidate_w, endpoint_rank) ## i64
          if source_distance == 0
            meta[11] = meta[11] + 1
          if g_distance == 0
            meta[12] = meta[12] + 1
          if h_distance == 0
            meta[13] = meta[13] + 1
          if hg_distance == 0
            meta[14] = meta[14] + 1
          multicolor = 0 ## i64
          if color_mask != 1 && color_mask != 2 && color_mask != 4
            multicolor = 1
          if multicolor == 1 && source_distance != 0 && g_distance != 0 && h_distance != 0 && hg_distance != 0
            meta[15] = meta[15] + 1
            endpoint_density = ffgir_density(candidate_u, candidate_v, candidate_w, endpoint_rank) ## i64
            if endpoint_rank < rank
              meta[16] = meta[16] + 1
            if endpoint_rank == rank && endpoint_density < source_density
              meta[17] = meta[17] + 1
            if source_distance > meta[20]
              meta[20] = source_distance
            min_global = g_distance ## i64
            if h_distance < min_global
              min_global = h_distance
            if hg_distance < min_global
              min_global = hg_distance
            if min_global > meta[21]
              meta[21] = min_global
            # Reject endpoints obtainable by simply chaining two already-exact
            # binary partial-automorphism edges.  In the canonical order, g is
            # applied to colours g/hg first; if that syndrome vanishes, the
            # remaining h step necessarily vanishes as well.  A reverse h-first
            # staging is also recognized when g and h commute on every hg term.
            staging = ffcat_staging_kind(us, vs, ws, rank, n, g, images_u, images_v, images_w, assignment, stage) ## i64
            staged_g = staging & 1 ## i64
            staged_h = (staging >> 1) & 1 ## i64
            if staged_g == 1
              meta[26] = meta[26] + 1
            if staged_h == 1
              meta[27] = meta[27] + 1
            if staged_g == 0 && staged_h == 0
              meta[28] = meta[28] + 1
              if endpoint_rank < rank
                meta[29] = meta[29] + 1
              if endpoint_rank == rank && endpoint_density < source_density
                meta[30] = meta[30] + 1
              if source_distance > meta[31]
                meta[31] = source_distance
              better = 0 ## i64
              if endpoint_rank < meta[18]
                better = 1
              if endpoint_rank == meta[18] && endpoint_density < meta[19]
                better = 1
              if endpoint_rank == meta[18] && endpoint_density == meta[19] && source_distance >= meta[31]
                better = 1
              if better == 1
                meta[18] = endpoint_rank
                meta[19] = endpoint_density
                ffcat_copy_candidate(candidate_u, candidate_v, candidate_w, best_u, best_v, best_w, endpoint_rank)
    combination += 1
  meta[28]
