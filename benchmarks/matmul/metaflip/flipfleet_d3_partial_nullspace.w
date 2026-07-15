# Exact partial tensor-axis automorphism tunnels.
#
# This is deliberately distinct from coordinate-index 3-cycles.  The maps are
# the genuine D3 factor actions used by basin identity, for example
#   rho(u,v,w) = (v, transpose(w), transpose(u)).
# For a fixed tensor automorphism phi, a selected subset S may be replaced by
# phi(S) exactly when XOR_{t in S}(t XOR phi(t)) is zero.  We compute the full
# term-delta kernel, project individually fixed terms, row-reduce that projected
# kernel, and then either exhaust every effective combination or enumerate a
# quantified sparse closure.  A measured optional policy can reserve part of
# the cap for reproducible dense selectors, but sparse is the live default.

use flipfleet_partial_automorphism_nullspace
use flipfleet_basin_identity

-> ffd3ns_copy_terms(source_u, source_v, source_w, target_u, target_v, target_w, count) (i64[] i64[] i64[] i64[] i64[] i64[] i64) i64
  i = 0 ## i64
  while i < count
    target_u[i] = source_u[i]
    target_v[i] = source_v[i]
    target_w[i] = source_w[i]
    i += 1
  count

-> ffd3ns_build_deltas(us, vs, ws, rank, n, code, reverse, linear, term_scratch) (i64[] i64[] i64[] i64 i64 i64 i64 FFPANWorkspace i64[]) i64
  words = ffpa_tensor_words(n) ## i64
  transformed_u = linear.transformed_u()
  transformed_v = linear.transformed_v()
  transformed_w = linear.transformed_w()
  deltas = linear.deltas()
  i = 0 ## i64
  while i < rank
    if ffbi_transform_term(us[i], vs[i], ws[i], n, code, reverse, term_scratch) != 1
      return 0
    transformed_u[i] = term_scratch[0]
    transformed_v[i] = term_scratch[1]
    transformed_w[i] = term_scratch[2]
    ffpa_clear_row(deltas, i * words, words)
    ffpa_xor_outer(deltas, i * words, us[i], vs[i], ws[i], n)
    ffpa_xor_outer(deltas, i * words, term_scratch[0], term_scratch[1], term_scratch[2], n)
    i += 1
  words

# Record where each transformed term occurs in the source term set.  -1 means
# phi(t) leaves the source support.  Since phi is injective and schemes are
# parity-compacted term sets, mapped indices are unique.
-> ffd3ns_build_image_index(us, vs, ws, transformed_u, transformed_v, transformed_w, rank, image_index) (i64[] i64[] i64[] i64[] i64[] i64[] i64 i64[]) i64
  mapped = 0 ## i64
  i = 0 ## i64
  while i < rank
    image_index[i] = 0 - 1
    j = 0 ## i64
    while j < rank && image_index[i] < 0
      if transformed_u[i] == us[j] && transformed_v[i] == vs[j] && transformed_w[i] == ws[j]
        image_index[i] = j
        mapped += 1
      j += 1
    i += 1
  mapped

# Project fixed-term coefficients out of the raw nullspace basis, then perform
# a second exact GF(2) elimination in coefficient space.  The returned rows are
# an independent basis of the effective endpoint-changing kernel, rather than
# merely a deduplicated list of projected raw dependencies.
# meta = projected nonzero rows, projected dependent rows.
-> ffd3ns_project_kernel(dependencies, nullity, rank, coefficient_words, stable, effective, pivot_owners, work, meta) (i64[] i64 i64 i64 i64[] i64[] i32[] i64[] i64[]) i64
  i = 0 ## i64
  while i < rank
    pivot_owners[i] = 0
    i += 1
  basis_count = 0 ## i64
  projected_nonzero = 0 ## i64
  projected_dependent = 0 ## i64
  dependency = 0 ## i64
  while dependency < nullity
    word = 0 ## i64
    while word < coefficient_words
      work[word] = dependencies[dependency * coefficient_words + word]
      word += 1
    term = 0 ## i64
    while term < rank
      if stable[term] != 0
        bit = 1 << (term % 64) ## i64
        if (work[term / 64] & bit) != 0
          work[term / 64] = work[term / 64] ^ bit
      term += 1
    pivot = ffpan_first_pivot(work, coefficient_words) ## i64
    had_nonzero = 0 ## i64
    if pivot >= 0
      projected_nonzero += 1
      had_nonzero = 1
    placed = 0 ## i64
    while pivot >= 0 && placed == 0
      owner = pivot_owners[pivot] ## i64
      if owner == 0
        ffpan_copy(work, 0, effective, basis_count * coefficient_words, coefficient_words)
        pivot_owners[pivot] = basis_count + 1
        basis_count += 1
        placed = 1
      else
        ffpan_xor_into(work, 0, effective, (owner - 1) * coefficient_words, coefficient_words)
        pivot = ffpan_first_pivot(work, coefficient_words)
    if placed == 0 && had_nonzero == 1
      projected_dependent += 1
    dependency += 1
  meta[0] = projected_nonzero
  meta[1] = projected_dependent
  basis_count

-> ffd3ns_combo_row(effective, coefficient_words, a, b, c, d, degree, combos, row) (i64[] i64 i64 i64 i64 i64 i64 i64[] i64) i64
  word = 0 ## i64
  while word < coefficient_words
    value = effective[a * coefficient_words + word] ## i64
    if degree >= 2
      value = value ^ effective[b * coefficient_words + word]
    if degree >= 3
      value = value ^ effective[c * coefficient_words + word]
    if degree >= 4
      value = value ^ effective[d * coefficient_words + word]
    combos[row * coefficient_words + word] = value
    word += 1
  row + 1

# A reproducible full-width selector.  Low selector bits encode the sample and
# therefore distinguish dense rows from one another; the remaining basis bits
# come from a fixed 31-bit LCG.  The independent effective basis makes every
# selector an exact kernel relation.  Full n^6 gating remains authoritative.
-> ffd3ns_dense_row(effective, effective_count, coefficient_words, sample, sample_count, combos, row) (i64[] i64 i64 i64 i64 i64[] i64) i64
  word = 0 ## i64
  while word < coefficient_words
    combos[row * coefficient_words + word] = 0
    word += 1
  tag_bits = 1 ## i64
  tag_capacity = 2 ## i64
  while tag_capacity <= sample_count && tag_bits < effective_count
    tag_bits += 1
    tag_capacity = tag_capacity << 1
  tag = (sample + 1) ^ 1365 ## i64
  rng = ((sample + 1) * 48271 + effective_count * 69621 + 17) & 2147483647 ## i64
  selected = 0 ## i64
  basis = 0 ## i64
  while basis < effective_count
    take = 0 ## i64
    if basis < tag_bits
      take = (tag >> basis) & 1
    else
      rng = (rng * 1103515245 + 12345) & 2147483647
      take = rng & 1
    if take != 0
      ffpan_xor_into(combos, row * coefficient_words, effective, basis * coefficient_words, coefficient_words)
      selected += 1
    basis += 1
  if selected == 0
    ffpan_xor_into(combos, row * coefficient_words, effective, (sample % effective_count) * coefficient_words, coefficient_words)
  row + 1

# meta = theoretical combinations (-1 if >=2^63), emitted, exhaustive,
# singles, pairs, triples, quadruples, dense.
-> ffd3ns_build_combos_policy(effective, effective_count, coefficient_words, combo_cap, exhaustive_dim, dense_milli, combos, meta) (i64[] i64 i64 i64 i64 i64 i64[] i64[]) i64
  theoretical = 0 - 1 ## i64
  if effective_count < 63
    theoretical = (1 << effective_count) - 1
  exhaustive = 0 ## i64
  if effective_count <= exhaustive_dim && theoretical >= 0 && theoretical <= combo_cap
    exhaustive = 1
  meta[0] = theoretical
  meta[1] = 0
  meta[2] = exhaustive
  meta[3] = 0
  meta[4] = 0
  meta[5] = 0
  meta[6] = 0
  meta[7] = 0
  count = 0 ## i64
  if exhaustive == 1
    selector = 1 ## i64
    while selector <= theoretical
      word = 0 ## i64
      while word < coefficient_words
        combos[count * coefficient_words + word] = 0
        word += 1
      basis = 0 ## i64
      while basis < effective_count
        if ((selector >> basis) & 1) != 0
          ffpan_xor_into(combos, count * coefficient_words, effective, basis * coefficient_words, coefficient_words)
        basis += 1
      count += 1
      selector += 1
  if exhaustive == 0
    a = 0 ## i64
    while a < effective_count && count < combo_cap
      count = ffd3ns_combo_row(effective, coefficient_words, a, 0, 0, 0, 1, combos, count)
      meta[3] = meta[3] + 1
      a += 1
    a = 0
    while a < effective_count - 1 && count < combo_cap
      b = a + 1 ## i64
      while b < effective_count && count < combo_cap
        count = ffd3ns_combo_row(effective, coefficient_words, a, b, 0, 0, 2, combos, count)
        meta[4] = meta[4] + 1
        b += 1
      a += 1
    remaining = combo_cap - count ## i64
    dense_budget = (remaining * dense_milli) / 1000 ## i64
    sparse_limit = combo_cap - dense_budget ## i64
    a = 0
    while a < effective_count - 2 && count < sparse_limit
      b = a + 1
      while b < effective_count - 1 && count < sparse_limit
        c = b + 1 ## i64
        while c < effective_count && count < sparse_limit
          count = ffd3ns_combo_row(effective, coefficient_words, a, b, c, 0, 3, combos, count)
          meta[5] = meta[5] + 1
          c += 1
        b += 1
      a += 1
    a = 0
    while a < effective_count - 3 && count < sparse_limit
      b = a + 1
      while b < effective_count - 2 && count < sparse_limit
        c = b + 1
        while c < effective_count - 1 && count < sparse_limit
          d = c + 1 ## i64
          while d < effective_count && count < sparse_limit
            count = ffd3ns_combo_row(effective, coefficient_words, a, b, c, d, 4, combos, count)
            meta[6] = meta[6] + 1
            d += 1
          c += 1
        b += 1
      a += 1
    dense_sample = 0 ## i64
    if dense_milli > 0
      dense_budget = combo_cap - count
    else
      dense_budget = 0
    while dense_sample < dense_budget && count < combo_cap
      count = ffd3ns_dense_row(effective, effective_count, coefficient_words, dense_sample, dense_budget, combos, count)
      meta[7] = meta[7] + 1
      dense_sample += 1
  meta[1] = count
  count

-> ffd3ns_build_combos(effective, effective_count, coefficient_words, combo_cap, exhaustive_dim, combos, meta) (i64[] i64 i64 i64 i64 i64[] i64[]) i64
  ffd3ns_build_combos_policy(effective, effective_count, coefficient_words, combo_cap, exhaustive_dim, 0, combos, meta)

-> ffd3ns_build_combos_mixed(effective, effective_count, coefficient_words, combo_cap, exhaustive_dim, combos, meta) (i64[] i64 i64 i64 i64 i64[] i64[]) i64
  ffd3ns_build_combos_policy(effective, effective_count, coefficient_words, combo_cap, exhaustive_dim, 500, combos, meta)

-> ffd3ns_mask_ids(mask, offset, rank, ids) (i64[] i64 i64 i64[]) i64
  count = 0 ## i64
  term = 0 ## i64
  while term < rank
    if ((mask[offset + term / 64] >> (term % 64)) & 1) != 0
      ids[count] = term
      count += 1
    term += 1
  count

# Exact set-stability test under the precomputed source-support permutation.
-> ffd3ns_selected_set_stable(mask, offset, rank, image_index) (i64[] i64 i64 i64[]) i64
  term = 0 ## i64
  while term < rank
    if ((mask[offset + term / 64] >> (term % 64)) & 1) != 0
      mapped = image_index[term] ## i64
      if mapped < 0 || ((mask[offset + mapped / 64] >> (mapped % 64)) & 1) == 0
        return 0
    term += 1
  1

+ FFD3NSWorkspace
  -> new(rank, n, capacity, combo_cap)
    @config = i64[4]
    @config[0] = rank
    @config[1] = n
    @config[2] = capacity
    @config[3] = combo_cap
    coefficient_words = ffpan_coeff_words(rank) ## i64
    @linear = FFPANWorkspace.new(rank, n, capacity)
    @source_u = i64[capacity]
    @source_v = i64[capacity]
    @source_w = i64[capacity]
    @effective = i64[rank * coefficient_words]
    @project_pivots = i32[rank]
    @project_work = i64[coefficient_words]
    @stable = i64[rank]
    @image_index = i64[rank]
    @combos = i64[combo_cap * coefficient_words]
    @candidate_u = i64[capacity]
    @candidate_v = i64[capacity]
    @candidate_w = i64[capacity]
    @gate = i64[ffw_state_size(capacity)]
    @best = i64[ffw_state_size(capacity)]
    @best_meta = i64[4]
    @best_meta[0] = 0
    @best_meta[1] = rank
    @best_meta[2] = 9223372036854775807
    @best_meta[3] = 0 - 1
    @seen_ids = i64[combo_cap]
    @term_scratch = i64[3]

  -> rank()
    @config[0]
  -> n()
    @config[1]
  -> capacity()
    @config[2]
  -> combo_cap()
    @config[3]
  -> linear()
    @linear
  -> source_u()
    @source_u
  -> source_v()
    @source_v
  -> source_w()
    @source_w
  -> effective()
    @effective
  -> project_pivots()
    @project_pivots
  -> project_work()
    @project_work
  -> stable()
    @stable
  -> image_index()
    @image_index
  -> combos()
    @combos
  -> candidate_u()
    @candidate_u
  -> candidate_v()
    @candidate_v
  -> candidate_w()
    @candidate_w
  -> gate()
    @gate
  -> seen_ids()
    @seen_ids
  -> term_scratch()
    @term_scratch
  -> best()
    @best
  -> best_meta()
    @best_meta
  -> reset_best(source_rank, source_density)
    @best_meta[0] = 0
    @best_meta[1] = source_rank
    @best_meta[2] = source_density
    @best_meta[3] = 0 - 1
    1
  -> offer_best(candidate, rank, density, distance, seed)
    better = 0 ## i64
    if @best_meta[0] == 0 || rank < @best_meta[1]
      better = 1
    if rank == @best_meta[1] && density < @best_meta[2]
      better = 1
    if rank == @best_meta[1] && density == @best_meta[2] && distance > @best_meta[3]
      better = 1
    if better == 1
      if ffw_reseed_from(@best, candidate, seed) == rank
        @best_meta[0] = 1
        @best_meta[1] = rank
        @best_meta[2] = density
        @best_meta[3] = distance
        return 1
    0

# Scan one non-identity D3 x reversal map.  meta:
# raw-nullity, fixed terms, effective dimension, theoretical combinations,
# attempted, exhaustive, set-stable, relation failures, materialized, exact,
# source quotient, global quotient, D3-canonical quotient, algebraic genuine,
# source-D3-novel genuine, canonical-unique, rank drops, density improvements,
# best rank, best density, max source distance, tensor words, mapped terms,
# capped, elimination ms, admission ms, parity rank drops, failures.
-> ffd3ns_scan_state_policy(state, code, reverse, exhaustive_dim, dense_milli, workspace, meta) (i64[] i64 i64 i64 i64 FFD3NSWorkspace i64[]) i64
  if meta.size() < 28 || workspace == nil || code < 0 || code > 5 || reverse < 0 || reverse > 1
    return 0 - 1
  if code == 0 && reverse == 0
    return 0
  i = 0 ## i64
  while i < 28
    meta[i] = 0
    i += 1
  rank = ffw_best_rank(state) ## i64
  n = ffw_n(state) ## i64
  capacity = workspace.capacity() ## i64
  if rank != workspace.rank() || n != workspace.n() || ffw_verify_best_exact(state, n) != 1
    meta[27] = meta[27] + 1
    return 0 - 1
  source_u = workspace.source_u()
  source_v = workspace.source_v()
  source_w = workspace.source_w()
  if ffw_export_best(state, source_u, source_v, source_w) != rank
    meta[27] = meta[27] + 1
    return 0 - 1
  source_density = ffw_best_bits(state) ## i64
  meta[18] = rank
  meta[19] = source_density
  linear = workspace.linear()
  words = ffd3ns_build_deltas(source_u, source_v, source_w, rank, n, code, reverse, linear, workspace.term_scratch()) ## i64
  if words != ffpa_tensor_words(n)
    meta[27] = meta[27] + 1
    return 0 - 1
  meta[21] = words
  transformed_u = linear.transformed_u()
  transformed_v = linear.transformed_v()
  transformed_w = linear.transformed_w()
  image_index = workspace.image_index()
  meta[22] = ffd3ns_build_image_index(source_u, source_v, source_w, transformed_u, transformed_v, transformed_w, rank, image_index)
  dependencies = linear.dependencies()
  nullspace_meta = i64[4]
  elimination_started = ccall("__w_clock_ms") ## i64
  nullity = ffpan_nullspace_into(linear.deltas(), rank, words, dependencies, linear.basis_rows(), linear.basis_coefficients(), linear.pivot_owners(), linear.work(), linear.work_coefficients(), nullspace_meta) ## i64
  if nullity < 0
    meta[27] = meta[27] + 1
    return 0 - 1
  meta[0] = nullity
  stable = workspace.stable()
  stable_count = 0 ## i64
  term = 0 ## i64
  while term < rank
    stable[term] = ffpan_row_zero(linear.deltas(), term * words, words)
    stable_count += stable[term]
    term += 1
  meta[1] = stable_count
  project_meta = i64[2]
  effective_count = ffd3ns_project_kernel(dependencies, nullity, rank, ffpan_coeff_words(rank), stable, workspace.effective(), workspace.project_pivots(), workspace.project_work(), project_meta) ## i64
  meta[2] = effective_count
  meta[24] = ccall("__w_clock_ms") - elimination_started
  combo_meta = i64[8]
  combo_count = ffd3ns_build_combos_policy(workspace.effective(), effective_count, ffpan_coeff_words(rank), workspace.combo_cap(), exhaustive_dim, dense_milli, workspace.combos(), combo_meta) ## i64
  meta[3] = combo_meta[0]
  meta[4] = combo_count
  meta[5] = combo_meta[2]
  if combo_meta[0] < 0 || combo_count < combo_meta[0]
    meta[23] = 1
  ids = linear.ids()
  raw_u = linear.raw_u()
  raw_v = linear.raw_v()
  raw_w = linear.raw_w()
  candidate_u = workspace.candidate_u()
  candidate_v = workspace.candidate_v()
  candidate_w = workspace.candidate_w()
  gate = workspace.gate()
  source_id = ffbi_best_id(state) ## i64
  seen_ids = workspace.seen_ids()
  seen_count = 0 ## i64
  admission_started = ccall("__w_clock_ms") ## i64
  combo = 0 ## i64
  while combo < combo_count
    offset = combo * ffpan_coeff_words(rank) ## i64
    weight = ffd3ns_mask_ids(workspace.combos(), offset, rank, ids) ## i64
    if ffpa_relation_exact(linear.deltas(), ids, weight, words) != 1
      meta[7] = meta[7] + 1
    else
      if ffd3ns_selected_set_stable(workspace.combos(), offset, rank, image_index) == 1
        meta[6] = meta[6] + 1
      else
        meta[8] = meta[8] + 1
        ffd3ns_copy_terms(source_u, source_v, source_w, raw_u, raw_v, raw_w, rank)
        selected = 0 ## i64
        while selected < weight
          position = ids[selected] ## i64
          raw_u[position] = transformed_u[position]
          raw_v[position] = transformed_v[position]
          raw_w[position] = transformed_w[position]
          selected += 1
        candidate_rank = ffpan_parity_compact(raw_u, raw_v, raw_w, rank, candidate_u, candidate_v, candidate_w) ## i64
        if candidate_rank < rank
          meta[26] = meta[26] + 1
        if candidate_rank < 1 || candidate_rank > capacity
          meta[27] = meta[27] + 1
        else
          loaded = ffw_init_terms_cap(gate, candidate_u, candidate_v, candidate_w, candidate_rank, n, capacity, 980001 + code * 10007 + reverse * 1009 + combo, 0, 1, 1, 1) ## i64
          if loaded != candidate_rank || ffw_verify_best_exact(gate, n) != 1
            meta[27] = meta[27] + 1
          else
            meta[9] = meta[9] + 1
            source_distance = ffpan_term_set_distance_unique(source_u, source_v, source_w, rank, candidate_u, candidate_v, candidate_w, candidate_rank) ## i64
            global_distance = ffpan_term_set_distance_unique(transformed_u, transformed_v, transformed_w, rank, candidate_u, candidate_v, candidate_w, candidate_rank) ## i64
            if source_distance == 0
              meta[10] = meta[10] + 1
            if source_distance != 0 && global_distance == 0
              meta[11] = meta[11] + 1
            if source_distance != 0 && global_distance != 0
              meta[13] = meta[13] + 1
              canonical_id = ffbi_best_id(gate) ## i64
              if canonical_id == source_id
                meta[12] = meta[12] + 1
              else
                meta[14] = meta[14] + 1
                duplicate = 0 ## i64
                seen = 0 ## i64
                while seen < seen_count && duplicate == 0
                  if seen_ids[seen] == canonical_id
                    duplicate = 1
                  seen += 1
                if duplicate == 0 && seen_count < workspace.combo_cap()
                  seen_ids[seen_count] = canonical_id
                  seen_count += 1
                  meta[15] = meta[15] + 1
                density = ffw_best_bits(gate) ## i64
                if candidate_rank < rank
                  meta[16] = meta[16] + 1
                if candidate_rank == rank && density < source_density
                  meta[17] = meta[17] + 1
                if candidate_rank < meta[18]
                  meta[18] = candidate_rank
                  meta[19] = density
                if candidate_rank == meta[18] && density < meta[19]
                  meta[19] = density
                if source_distance > meta[20]
                  meta[20] = source_distance
                workspace.offer_best(gate, candidate_rank, density, source_distance, 981001 + code * 101 + reverse * 17 + combo)
    combo += 1
  meta[25] = ccall("__w_clock_ms") - admission_started
  combo_count

-> ffd3ns_scan_state(state, code, reverse, exhaustive_dim, workspace, meta) (i64[] i64 i64 i64 FFD3NSWorkspace i64[]) i64
  ffd3ns_scan_state_policy(state, code, reverse, exhaustive_dim, 0, workspace, meta)
