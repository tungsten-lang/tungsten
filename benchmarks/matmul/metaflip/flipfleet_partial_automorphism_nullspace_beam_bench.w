# Offline beam/graph laboratory for complete partial-automorphism tunnels.
#
# This deliberately does not participate in the live fleet.  For each chosen
# elementary tensor automorphism it projects away individually fixed terms
# from the nullspace basis, deduplicates the resulting directions, and tests
# bounded single/pair/triple/quadruple XORs of those directions. Every
# projected kernel encountered by the default 7x7 run has dimension at most
# four, so this is its complete nonzero combination closure. Every term
# set is parity compacted, exhaustively n^6-gated, quotiented against both the
# parent and the whole automorphism image, and globally deduplicated before it
# can enter a four-role beam (density, distance, light edge, deterministic
# novelty).  Short words therefore compose genuinely partial exact edges,
# rather than merely composing whole-scheme changes of basis.
#
# Default usage (from the repository root):
#   flipfleet_partial_automorphism_nullspace_beam_bench
# Optional arguments:
#   depth width combo_cap deep_generators continuation_moves trials publish
# Defaults:
#   3     4     128       63              1000000            2      1

use flipfleet_partial_automorphism_nullspace
use flipfleet_global_isotropy

-> ffpanbl_expect(label, condition) (String bool) i64
  if !condition
    << "PARTIAL_AUTOMORPHISM_BEAM_FAIL " + label
    exit(1)
  1

-> ffpanbl_copy_terms(source_u, source_v, source_w, source_offset, target_u, target_v, target_w, target_offset, count) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64) i64
  i = 0 ## i64
  while i < count
    target_u[target_offset + i] = source_u[source_offset + i]
    target_v[target_offset + i] = source_v[source_offset + i]
    target_w[target_offset + i] = source_w[source_offset + i]
    i += 1
  count

-> ffpanbl_same_row(left, left_offset, right, right_offset, words) (i64[] i64 i64[] i64 i64) i64
  same = 1 ## i64
  word = 0 ## i64
  while word < words && same == 1
    if left[left_offset + word] != right[right_offset + word]
      same = 0
    word += 1
  same

-> ffpanbl_row_zero(row, offset, words) (i64[] i64 i64) i64
  zero = 1 ## i64
  word = 0 ## i64
  while word < words && zero == 1
    if row[offset + word] != 0
      zero = 0
    word += 1
  zero

# Remove coefficients of individually fixed terms.  They change no endpoint,
# so retaining them would make the apparent combination count exponentially
# larger without adding a single graph edge.  Equal projected masks are also
# merged. `origin[d]` records the first raw dependency supplying direction d.
-> ffpanbl_project_basis(dependencies, nullity, rank, coefficient_words, stable, effective, origin) (i64[] i64 i64 i64 i64[] i64[] i64[]) i64
  count = 0 ## i64
  dependency = 0 ## i64
  while dependency < nullity
    offset = count * coefficient_words ## i64
    word = 0 ## i64
    while word < coefficient_words
      effective[offset + word] = 0
      word += 1
    term = 0 ## i64
    while term < rank
      value = dependencies[dependency * coefficient_words + term / 64] ## i64
      if stable[term] == 0 && ((value >> (term % 64)) & 1) != 0
        effective[offset + term / 64] = effective[offset + term / 64] | (1 << (term % 64))
      term += 1
    if ffpanbl_row_zero(effective, offset, coefficient_words) == 0
      duplicate = 0 ## i64
      previous = 0 ## i64
      while previous < count && duplicate == 0
        if ffpanbl_same_row(effective, offset, effective, previous * coefficient_words, coefficient_words) == 1
          duplicate = 1
        previous += 1
      if duplicate == 0
        origin[count] = dependency
        count += 1
    dependency += 1
  count

-> ffpanbl_add_combo(effective, coefficient_words, a, b, c, d, kind, origin, combo_rows, combo_kind, combo_a, combo_b, combo_c, combo_count, combo_cap) (i64[] i64 i64 i64 i64 i64 i64 i64[] i64[] i64[] i64[] i64[] i64[] i64 i64) i64
  if combo_count >= combo_cap
    return combo_count
  offset = combo_count * coefficient_words ## i64
  word = 0 ## i64
  while word < coefficient_words
    value = effective[a * coefficient_words + word] ## i64
    if kind >= 2
      value = value ^ effective[b * coefficient_words + word]
    if kind >= 3
      value = value ^ effective[c * coefficient_words + word]
    if kind >= 4
      value = value ^ effective[d * coefficient_words + word]
    combo_rows[offset + word] = value
    word += 1
  if ffpanbl_row_zero(combo_rows, offset, coefficient_words) == 1
    return combo_count
  duplicate = 0 ## i64
  previous = 0 ## i64
  while previous < combo_count && duplicate == 0
    if ffpanbl_same_row(combo_rows, offset, combo_rows, previous * coefficient_words, coefficient_words) == 1
      duplicate = 1
    previous += 1
  if duplicate == 1
    return combo_count
  combo_kind[combo_count] = kind
  combo_a[combo_count] = origin[a]
  combo_b[combo_count] = 0 - 1
  combo_c[combo_count] = 0 - 1
  if kind >= 2
    combo_b[combo_count] = origin[b]
  if kind >= 3
    combo_c[combo_count] = origin[c]
  if kind >= 4
    # Four raw dependency indices fit in bytes at rank 247.  Keep the fourth
    # in the high byte of combo_c so the production-shaped edge record remains
    # compact while deterministic replay retains all four directions.
    combo_c[combo_count] = origin[c] * 256 + origin[d]
  combo_count + 1

# Fill a deterministic bounded prefix of all projected basis singles, pairs,
# triples, and (when present) quadruples. The theoretical total is returned in
# meta[0], attempted tuples in meta[1], unique nonzero masks in meta[2], and
# kind counts in meta[3..6].
-> ffpanbl_build_combos(effective, effective_count, coefficient_words, origin, combo_rows, combo_kind, combo_a, combo_b, combo_c, combo_cap, meta) (i64[] i64 i64 i64[] i64[] i64[] i64[] i64[] i64[] i64 i64[]) i64
  potential = effective_count ## i64
  if effective_count >= 2
    potential += effective_count * (effective_count - 1) / 2
  if effective_count >= 3
    potential += effective_count * (effective_count - 1) * (effective_count - 2) / 6
  if effective_count >= 4
    potential += effective_count * (effective_count - 1) * (effective_count - 2) * (effective_count - 3) / 24
  meta[0] = potential
  meta[1] = 0
  meta[2] = 0
  meta[3] = 0
  meta[4] = 0
  meta[5] = 0
  meta[6] = 0
  count = 0 ## i64
  a = 0 ## i64
  while a < effective_count && count < combo_cap
    before = count ## i64
    count = ffpanbl_add_combo(effective, coefficient_words, a, 0, 0, 0, 1, origin, combo_rows, combo_kind, combo_a, combo_b, combo_c, count, combo_cap)
    meta[1] = meta[1] + 1
    if count > before
      meta[3] = meta[3] + 1
    a += 1
  a = 0
  while a < effective_count - 1 && count < combo_cap
    b = a + 1 ## i64
    while b < effective_count && count < combo_cap
      before = count
      count = ffpanbl_add_combo(effective, coefficient_words, a, b, 0, 0, 2, origin, combo_rows, combo_kind, combo_a, combo_b, combo_c, count, combo_cap)
      meta[1] = meta[1] + 1
      if count > before
        meta[4] = meta[4] + 1
      b += 1
    a += 1
  a = 0
  while a < effective_count - 2 && count < combo_cap
    b = a + 1
    while b < effective_count - 1 && count < combo_cap
      c = b + 1 ## i64
      while c < effective_count && count < combo_cap
        before = count
        count = ffpanbl_add_combo(effective, coefficient_words, a, b, c, 0, 3, origin, combo_rows, combo_kind, combo_a, combo_b, combo_c, count, combo_cap)
        meta[1] = meta[1] + 1
        if count > before
          meta[5] = meta[5] + 1
        c += 1
      b += 1
    a += 1
  a = 0
  while a < effective_count - 3 && count < combo_cap
    b = a + 1
    while b < effective_count - 2 && count < combo_cap
      c = b + 1
      while c < effective_count - 1 && count < combo_cap
        d = c + 1 ## i64
        while d < effective_count && count < combo_cap
          before = count
          count = ffpanbl_add_combo(effective, coefficient_words, a, b, c, d, 4, origin, combo_rows, combo_kind, combo_a, combo_b, combo_c, count, combo_cap)
          meta[1] = meta[1] + 1
          if count > before
            meta[6] = meta[6] + 1
          d += 1
        c += 1
      b += 1
    a += 1
  meta[2] = count
  count

-> ffpanbl_mask_ids(mask, offset, rank, ids) (i64[] i64 i64 i64[]) i64
  count = 0 ## i64
  term = 0 ## i64
  while term < rank
    if ((mask[offset + term / 64] >> (term % 64)) & 1) != 0
      ids[count] = term
      count += 1
    term += 1
  count

# Two order-independent modular fingerprints.  The retained/published states
# are additionally lexicographically sorted; the dual signatures make global
# graph dedup inexpensive before that canonical materialization.
-> ffpanbl_fingerprint(us, vs, ws, rank, out) (i64[] i64[] i64[] i64 i64[]) i64
  p1 = 2147483647 ## i64
  p2 = 2147483629 ## i64
  sum1 = 0 ## i64
  square1 = 0 ## i64
  sum2 = 0 ## i64
  square2 = 0 ## i64
  i = 0 ## i64
  while i < rank
    h1 = ((us[i] % p1) + 257 * (vs[i] % p1) + 65537 * (ws[i] % p1)) % p1 ## i64
    h2 = ((ws[i] % p2) + 263 * (us[i] % p2) + 131071 * (vs[i] % p2)) % p2 ## i64
    sum1 = (sum1 + h1) % p1
    square1 = (square1 + (h1 * h1) % p1) % p1
    sum2 = (sum2 + h2) % p2
    square2 = (square2 + (h2 * h2) % p2) % p2
    i += 1
  out[0] = (sum1 * 65537 + square1 + rank * 8191) % p1
  out[1] = (sum2 * 1009 + square2 + rank * 131071) % p2
  1

-> ffpanbl_term_after(u0, v0, w0, u1, v1, w1) (i64 i64 i64 i64 i64 i64) i64
  after = 0 ## i64
  if u0 > u1
    after = 1
  if u0 == u1 && v0 > v1
    after = 1
  if u0 == u1 && v0 == v1 && w0 > w1
    after = 1
  after

-> ffpanbl_sort_terms(us, vs, ws, rank) (i64[] i64[] i64[] i64) i64
  gap = rank / 2 ## i64
  while gap > 0
    i = gap ## i64
    while i < rank
      u = us[i] ## i64
      v = vs[i] ## i64
      w = ws[i] ## i64
      j = i ## i64
      while j >= gap && ffpanbl_term_after(us[j - gap], vs[j - gap], ws[j - gap], u, v, w) == 1
        us[j] = us[j - gap]
        vs[j] = vs[j - gap]
        ws[j] = ws[j - gap]
        j -= gap
      us[j] = u
      vs[j] = v
      ws[j] = w
      i += 1
    gap /= 2
  rank

+ FFPANBeamLab
  -> new(root_u, root_v, root_w, rank, n, capacity, max_depth, width, combo_cap, seen_capacity)
    @rank = rank
    @n = n
    @capacity = capacity
    @max_depth = max_depth
    @width = width
    @combo_cap = combo_cap
    @seen_capacity = seen_capacity
    @root_density = ffgir_density(root_u, root_v, root_w, rank)
    @root_u = i64[capacity]
    @root_v = i64[capacity]
    @root_w = i64[capacity]
    ffpanbl_copy_terms(root_u, root_v, root_w, 0, @root_u, @root_v, @root_w, 0, rank)

    @workspace = FFPANWorkspace.new(rank, n, capacity)
    @stable = i64[rank]
    coefficient_words = ffpan_coeff_words(rank) ## i64
    @effective = i64[rank * coefficient_words]
    @effective_origin = i64[rank]
    @combo_rows = i64[combo_cap * coefficient_words]
    @combo_kind = i64[combo_cap]
    @combo_a = i64[combo_cap]
    @combo_b = i64[combo_cap]
    @combo_c = i64[combo_cap]
    @candidate_u = i64[capacity]
    @candidate_v = i64[capacity]
    @candidate_w = i64[capacity]
    @gate = i64[ffw_state_size(capacity)]

    @seen1 = i64[seen_capacity]
    @seen2 = i64[seen_capacity]
    @seen_count = 0
    fingerprint = i64[2]
    ffpanbl_fingerprint(root_u, root_v, root_w, rank, fingerprint)
    @seen1[0] = fingerprint[0]
    @seen2[0] = fingerprint[1]
    @seen_count = 1

    @beam_u = i64[width * capacity]
    @beam_v = i64[width * capacity]
    @beam_w = i64[width * capacity]
    @beam_rank = i64[width]
    @beam_density = i64[width]
    @beam_distance = i64[width]
    @beam_sig1 = i64[width]
    @beam_sig2 = i64[width]
    @beam_generators = i64[width * max_depth]
    @beam_kinds = i64[width * max_depth]
    @beam_a = i64[width * max_depth]
    @beam_b = i64[width * max_depth]
    @beam_c = i64[width * max_depth]
    @beam_weights = i64[width * max_depth]
    ffpanbl_copy_terms(root_u, root_v, root_w, 0, @beam_u, @beam_v, @beam_w, 0, rank)
    @beam_rank[0] = rank
    @beam_density[0] = @root_density
    @beam_distance[0] = 0
    @beam_sig1[0] = fingerprint[0]
    @beam_sig2[0] = fingerprint[1]
    @beam_count = 1

    pool_slots = width * 4 ## i64
    @pool_u = i64[pool_slots * capacity]
    @pool_v = i64[pool_slots * capacity]
    @pool_w = i64[pool_slots * capacity]
    @pool_valid = i64[pool_slots]
    @pool_score = i64[pool_slots]
    @pool_rank = i64[pool_slots]
    @pool_density = i64[pool_slots]
    @pool_distance = i64[pool_slots]
    @pool_sig1 = i64[pool_slots]
    @pool_sig2 = i64[pool_slots]
    @pool_generators = i64[pool_slots * max_depth]
    @pool_kinds = i64[pool_slots * max_depth]
    @pool_a = i64[pool_slots * max_depth]
    @pool_b = i64[pool_slots * max_depth]
    @pool_c = i64[pool_slots * max_depth]
    @pool_weights = i64[pool_slots * max_depth]

    # Four reproducible Pareto representatives: all-depth density/distance and
    # depth>=2 density/distance. Slot four is reserved for a rank drop.
    @archive_u = i64[5 * capacity]
    @archive_v = i64[5 * capacity]
    @archive_w = i64[5 * capacity]
    @archive_valid = i64[5]
    @archive_rank = i64[5]
    @archive_density = i64[5]
    @archive_distance = i64[5]
    @archive_depth = i64[5]
    @archive_sig1 = i64[5]
    @archive_sig2 = i64[5]
    @archive_generators = i64[5 * max_depth]
    @archive_kinds = i64[5 * max_depth]
    @archive_a = i64[5 * max_depth]
    @archive_b = i64[5 * max_depth]
    @archive_c = i64[5 * max_depth]
    @archive_weights = i64[5 * max_depth]

  -> root_density()
    @root_density

  -> clear_pool()
    i = 0 ## i64
    while i < @pool_valid.size()
      @pool_valid[i] = 0
      i += 1
    1

  -> register(us, vs, ws, rank, fingerprint, stats)
    ffpanbl_fingerprint(us, vs, ws, rank, fingerprint)
    i = 0 ## i64
    while i < @seen_count
      if @seen1[i] == fingerprint[0] && @seen2[i] == fingerprint[1]
        stats[17] = stats[17] + 1
        return 0
      i += 1
    if @seen_count >= @seen_capacity
      stats[19] = stats[19] + 1
      return 0
    @seen1[@seen_count] = fingerprint[0]
    @seen2[@seen_count] = fingerprint[1]
    @seen_count += 1
    stats[18] = stats[18] + 1
    1

  -> copy_path_pool(target_slot, parent, level, edge)
    d = 0 ## i64
    while d < level
      @pool_generators[target_slot * @max_depth + d] = @beam_generators[parent * @max_depth + d]
      @pool_kinds[target_slot * @max_depth + d] = @beam_kinds[parent * @max_depth + d]
      @pool_a[target_slot * @max_depth + d] = @beam_a[parent * @max_depth + d]
      @pool_b[target_slot * @max_depth + d] = @beam_b[parent * @max_depth + d]
      @pool_c[target_slot * @max_depth + d] = @beam_c[parent * @max_depth + d]
      @pool_weights[target_slot * @max_depth + d] = @beam_weights[parent * @max_depth + d]
      d += 1
    @pool_generators[target_slot * @max_depth + level] = edge[0]
    @pool_kinds[target_slot * @max_depth + level] = edge[1]
    @pool_a[target_slot * @max_depth + level] = edge[2]
    @pool_b[target_slot * @max_depth + level] = edge[3]
    @pool_c[target_slot * @max_depth + level] = edge[4]
    @pool_weights[target_slot * @max_depth + level] = edge[5]
    1

  -> copy_path_archive(target_slot, parent, level, edge)
    d = 0 ## i64
    while d < level
      @archive_generators[target_slot * @max_depth + d] = @beam_generators[parent * @max_depth + d]
      @archive_kinds[target_slot * @max_depth + d] = @beam_kinds[parent * @max_depth + d]
      @archive_a[target_slot * @max_depth + d] = @beam_a[parent * @max_depth + d]
      @archive_b[target_slot * @max_depth + d] = @beam_b[parent * @max_depth + d]
      @archive_c[target_slot * @max_depth + d] = @beam_c[parent * @max_depth + d]
      @archive_weights[target_slot * @max_depth + d] = @beam_weights[parent * @max_depth + d]
      d += 1
    @archive_generators[target_slot * @max_depth + level] = edge[0]
    @archive_kinds[target_slot * @max_depth + level] = edge[1]
    @archive_a[target_slot * @max_depth + level] = edge[2]
    @archive_b[target_slot * @max_depth + level] = edge[3]
    @archive_c[target_slot * @max_depth + level] = edge[4]
    @archive_weights[target_slot * @max_depth + level] = edge[5]
    1

  # candidate_meta: rank, density, root distance, signature 1, signature 2.
  # edge: generator, combination kind, dependency a/b/c, selected weight.
  -> offer(candidate_u, candidate_v, candidate_w, candidate_meta, edge, parent, level)
    candidate_rank = candidate_meta[0] ## i64
    density = candidate_meta[1] ## i64
    distance = candidate_meta[2] ## i64
    if candidate_rank != @rank
      return 0
    rank_gain = @rank - candidate_rank ## i64
    role = 0 ## i64
    while role < 4
      score = rank_gain * 1000000000000000 ## i64
      if role == 0
        score += (@root_density - density) * 1000000000 + distance * 100000 - edge[5]
      if role == 1
        score += distance * 1000000000 + (@root_density - density) * 100000 - edge[5]
      if role == 2
        score += (0 - edge[5]) * 1000000000 + distance * 100000 - density
      if role == 3
        score += (candidate_meta[3] * 1000003 + candidate_meta[4]) % 2147483647
      start = role * @width ## i64
      chosen = 0 - 1 ## i64
      slot = start ## i64
      while slot < start + @width && chosen < 0
        if @pool_valid[slot] == 0
          chosen = slot
        slot += 1
      if chosen < 0
        worst = start ## i64
        slot = start + 1
        while slot < start + @width
          if @pool_score[slot] < @pool_score[worst]
            worst = slot
          if @pool_score[slot] == @pool_score[worst] && @pool_sig1[slot] < @pool_sig1[worst]
            worst = slot
          slot += 1
        if score > @pool_score[worst]
          chosen = worst
        if score == @pool_score[worst] && candidate_meta[3] > @pool_sig1[worst]
          chosen = worst
      if chosen >= 0
        ffpanbl_copy_terms(candidate_u, candidate_v, candidate_w, 0, @pool_u, @pool_v, @pool_w, chosen * @capacity, candidate_rank)
        @pool_valid[chosen] = 1
        @pool_score[chosen] = score
        @pool_rank[chosen] = candidate_rank
        @pool_density[chosen] = density
        @pool_distance[chosen] = distance
        @pool_sig1[chosen] = candidate_meta[3]
        @pool_sig2[chosen] = candidate_meta[4]
        copy_path_pool(chosen, parent, level, edge)
      role += 1
    1

  -> archive_candidate(candidate_u, candidate_v, candidate_w, candidate_meta, edge, parent, level)
    candidate_rank = candidate_meta[0] ## i64
    density = candidate_meta[1] ## i64
    distance = candidate_meta[2] ## i64
    depth = level + 1 ## i64
    slot = 0 ## i64
    while slot < 5
      eligible = 0 ## i64
      better = 0 ## i64
      if slot < 4 && candidate_rank == @rank
        if slot < 2 || depth >= 2
          eligible = 1
      if slot == 4 && candidate_rank < @rank
        eligible = 1
      if eligible == 1 && @archive_valid[slot] == 0
        better = 1
      if eligible == 1 && @archive_valid[slot] == 1
        if slot == 0 || slot == 2
          if density < @archive_density[slot]
            better = 1
          if density == @archive_density[slot] && distance > @archive_distance[slot]
            better = 1
          if density == @archive_density[slot] && distance == @archive_distance[slot] && candidate_meta[3] < @archive_sig1[slot]
            better = 1
        if slot == 1 || slot == 3
          if distance > @archive_distance[slot]
            better = 1
          if distance == @archive_distance[slot] && density < @archive_density[slot]
            better = 1
          if distance == @archive_distance[slot] && density == @archive_density[slot] && candidate_meta[3] > @archive_sig1[slot]
            better = 1
        if slot == 4
          if candidate_rank < @archive_rank[slot]
            better = 1
          if candidate_rank == @archive_rank[slot] && density < @archive_density[slot]
            better = 1
      if better == 1
        ffpanbl_copy_terms(candidate_u, candidate_v, candidate_w, 0, @archive_u, @archive_v, @archive_w, slot * @capacity, candidate_rank)
        @archive_valid[slot] = 1
        @archive_rank[slot] = candidate_rank
        @archive_density[slot] = density
        @archive_distance[slot] = distance
        @archive_depth[slot] = depth
        @archive_sig1[slot] = candidate_meta[3]
        @archive_sig2[slot] = candidate_meta[4]
        copy_path_archive(slot, parent, level, edge)
      slot += 1
    1

  -> scan_parent(parent, level, requested_generators, stats)
    parent_rank = @beam_rank[parent] ## i64
    if parent_rank != @rank
      return 0
    parent_u = i64[@capacity]
    parent_v = i64[@capacity]
    parent_w = i64[@capacity]
    ffpanbl_copy_terms(@beam_u, @beam_v, @beam_w, parent * @capacity, parent_u, parent_v, parent_w, 0, parent_rank)
    words = ffpa_tensor_words(@n) ## i64
    coefficient_words = ffpan_coeff_words(@rank) ## i64
    transformed_u = @workspace.transformed_u()
    transformed_v = @workspace.transformed_v()
    transformed_w = @workspace.transformed_w()
    deltas = @workspace.deltas()
    dependencies = @workspace.dependencies()
    basis_rows = @workspace.basis_rows()
    basis_coefficients = @workspace.basis_coefficients()
    pivot_owners = @workspace.pivot_owners()
    work = @workspace.work()
    work_coefficients = @workspace.work_coefficients()
    ids = @workspace.ids()
    raw_u = @workspace.raw_u()
    raw_v = @workspace.raw_v()
    raw_w = @workspace.raw_w()
    decoded = i64[4]
    nullspace_meta = i64[4]
    combo_meta = i64[7]
    fingerprint = i64[2]
    candidate_meta = i64[5]
    edge = i64[6]
    total_generators = ffpan_elementary_count(@n) ## i64
    generator_count = requested_generators ## i64
    if generator_count > total_generators
      generator_count = total_generators
    start = 0 ## i64
    stride = 1 ## i64
    if level > 0
      start = (parent * 37 + level * 53) % total_generators
      stride = 4
    scanned = 0 ## i64
    while scanned < generator_count
      flat = (start + scanned * stride) % total_generators ## i64
      ffpanbl_expect("decode", ffpan_elementary_decode(@n, flat, decoded) == 1)
      built = ffpa_build_deltas_kind(parent_u, parent_v, parent_w, parent_rank, @n, decoded[0], decoded[1], decoded[2], decoded[3], transformed_u, transformed_v, transformed_w, deltas) ## i64
      ffpanbl_expect("deltas", built == words)
      elimination_started = ccall("__w_clock_ms") ## i64
      nullity = ffpan_nullspace_into(deltas, parent_rank, words, dependencies, basis_rows, basis_coefficients, pivot_owners, work, work_coefficients, nullspace_meta) ## i64
      stats[29] = stats[29] + ccall("__w_clock_ms") - elimination_started
      ffpanbl_expect("nullspace", nullity >= 0 && nullspace_meta[0] + nullity == parent_rank)
      stats[0] = stats[0] + 1
      stats[1] = stats[1] + nullity
      if nullity < stats[2]
        stats[2] = nullity
      if nullity > stats[3]
        stats[3] = nullity
      stable_count = 0 ## i64
      term = 0 ## i64
      while term < parent_rank
        @stable[term] = ffpanbl_row_zero(deltas, term * words, words)
        stable_count += @stable[term]
        term += 1
      stats[31] = stats[31] + stable_count
      if stable_count > stats[32]
        stats[32] = stable_count
      effective_count = ffpanbl_project_basis(dependencies, nullity, parent_rank, coefficient_words, @stable, @effective, @effective_origin) ## i64
      stats[4] = stats[4] + effective_count
      if effective_count > stats[5]
        stats[5] = effective_count
      combo_count = ffpanbl_build_combos(@effective, effective_count, coefficient_words, @effective_origin, @combo_rows, @combo_kind, @combo_a, @combo_b, @combo_c, @combo_cap, combo_meta) ## i64
      stats[6] = stats[6] + combo_meta[0]
      stats[7] = stats[7] + combo_count
      stats[8] = stats[8] + combo_meta[1] - combo_count
      stats[23] = stats[23] + combo_meta[3]
      stats[24] = stats[24] + combo_meta[4]
      stats[25] = stats[25] + combo_meta[5]
      stats[27] = stats[27] + combo_meta[6]
      if combo_count < combo_meta[0]
        stats[26] = stats[26] + 1
      combo = 0 ## i64
      while combo < combo_count
        weight = ffpanbl_mask_ids(@combo_rows, combo * coefficient_words, parent_rank, ids) ## i64
        if weight >= 5
          if ffpa_relation_exact(deltas, ids, weight, words) != 1
            stats[9] = stats[9] + 1
          else
            stats[10] = stats[10] + 1
            admission_started = ccall("__w_clock_ms") ## i64
            ffpan_copy_terms(parent_u, parent_v, parent_w, raw_u, raw_v, raw_w, parent_rank)
            selected = 0 ## i64
            while selected < weight
              position = ids[selected] ## i64
              raw_u[position] = transformed_u[position]
              raw_v[position] = transformed_v[position]
              raw_w[position] = transformed_w[position]
              selected += 1
            candidate_rank = ffpan_parity_compact(raw_u, raw_v, raw_w, parent_rank, @candidate_u, @candidate_v, @candidate_w) ## i64
            full_exact = 0 ## i64
            if candidate_rank > 0 && candidate_rank <= @capacity
              loaded = ffw_init_terms_cap(@gate, @candidate_u, @candidate_v, @candidate_w, candidate_rank, @n, @capacity, 970001 + level * 10007 + parent * 1009 + flat * 17 + combo, 0, 1, 1, 1) ## i64
              if loaded == candidate_rank && ffw_verify_current_exact(@gate, @n) == 1
                full_exact = 1
                stats[11] = stats[11] + 1
            if full_exact == 1
              parent_distance = ffgir_term_set_distance(parent_u, parent_v, parent_w, parent_rank, @candidate_u, @candidate_v, @candidate_w, candidate_rank) ## i64
              global_distance = ffgir_term_set_distance(transformed_u, transformed_v, transformed_w, parent_rank, @candidate_u, @candidate_v, @candidate_w, candidate_rank) ## i64
              if parent_distance == 0
                stats[12] = stats[12] + 1
              if parent_distance != 0 && global_distance == 0
                stats[13] = stats[13] + 1
              if parent_distance != 0 && global_distance != 0
                stats[14] = stats[14] + 1
                density = ffgir_density(@candidate_u, @candidate_v, @candidate_w, candidate_rank) ## i64
                root_distance = ffgir_term_set_distance(@root_u, @root_v, @root_w, @rank, @candidate_u, @candidate_v, @candidate_w, candidate_rank) ## i64
                if candidate_rank < @rank
                  stats[15] = stats[15] + 1
                if candidate_rank == @rank && density < @root_density
                  stats[16] = stats[16] + 1
                if candidate_rank < stats[20]
                  stats[20] = candidate_rank
                if candidate_rank == stats[20] && density < stats[21]
                  stats[21] = density
                if root_distance > stats[22]
                  stats[22] = root_distance
                if register(@candidate_u, @candidate_v, @candidate_w, candidate_rank, fingerprint, stats) == 1
                  candidate_meta[0] = candidate_rank
                  candidate_meta[1] = density
                  candidate_meta[2] = root_distance
                  candidate_meta[3] = fingerprint[0]
                  candidate_meta[4] = fingerprint[1]
                  edge[0] = flat
                  edge[1] = @combo_kind[combo]
                  edge[2] = @combo_a[combo]
                  edge[3] = @combo_b[combo]
                  edge[4] = @combo_c[combo]
                  edge[5] = weight
                  archive_candidate(@candidate_u, @candidate_v, @candidate_w, candidate_meta, edge, parent, level)
                  offer(@candidate_u, @candidate_v, @candidate_w, candidate_meta, edge, parent, level)
            stats[30] = stats[30] + ccall("__w_clock_ms") - admission_started
        combo += 1
      scanned += 1
    scanned

  -> select_next(level)
    next_u = i64[@width * @capacity]
    next_v = i64[@width * @capacity]
    next_w = i64[@width * @capacity]
    next_rank = i64[@width]
    next_density = i64[@width]
    next_distance = i64[@width]
    next_sig1 = i64[@width]
    next_sig2 = i64[@width]
    next_generators = i64[@width * @max_depth]
    next_kinds = i64[@width * @max_depth]
    next_a = i64[@width * @max_depth]
    next_b = i64[@width * @max_depth]
    next_c = i64[@width * @max_depth]
    next_weights = i64[@width * @max_depth]
    used = i64[@pool_valid.size()]
    next_count = 0 ## i64
    progress = 1 ## i64
    while next_count < @width && progress == 1
      progress = 0
      role = 0 ## i64
      while role < 4 && next_count < @width
        selected = 0 - 1 ## i64
        retry = 1 ## i64
        while retry == 1
          retry = 0
          best = 0 - 1 ## i64
          slot = role * @width ## i64
          while slot < (role + 1) * @width
            if @pool_valid[slot] == 1 && used[slot] == 0
              if best < 0 || @pool_score[slot] > @pool_score[best]
                best = slot
              else
                if @pool_score[slot] == @pool_score[best] && @pool_sig1[slot] > @pool_sig1[best]
                  best = slot
            slot += 1
          if best >= 0
            used[best] = 1
            duplicate = 0 ## i64
            prior = 0 ## i64
            while prior < next_count && duplicate == 0
              if next_sig1[prior] == @pool_sig1[best] && next_sig2[prior] == @pool_sig2[best]
                duplicate = 1
              prior += 1
            if duplicate == 1
              retry = 1
            else
              selected = best
        if selected >= 0
          ffpanbl_copy_terms(@pool_u, @pool_v, @pool_w, selected * @capacity, next_u, next_v, next_w, next_count * @capacity, @pool_rank[selected])
          next_rank[next_count] = @pool_rank[selected]
          next_density[next_count] = @pool_density[selected]
          next_distance[next_count] = @pool_distance[selected]
          next_sig1[next_count] = @pool_sig1[selected]
          next_sig2[next_count] = @pool_sig2[selected]
          d = 0 ## i64
          while d <= level
            next_generators[next_count * @max_depth + d] = @pool_generators[selected * @max_depth + d]
            next_kinds[next_count * @max_depth + d] = @pool_kinds[selected * @max_depth + d]
            next_a[next_count * @max_depth + d] = @pool_a[selected * @max_depth + d]
            next_b[next_count * @max_depth + d] = @pool_b[selected * @max_depth + d]
            next_c[next_count * @max_depth + d] = @pool_c[selected * @max_depth + d]
            next_weights[next_count * @max_depth + d] = @pool_weights[selected * @max_depth + d]
            d += 1
          << "PARTIAL_AUTOMORPHISM_BEAM_NODE depth=" + (level + 1).to_s() + " slot=" + next_count.to_s() + " rank=" + next_rank[next_count].to_s() + " density=" + next_density[next_count].to_s() + " root_distance=" + next_distance[next_count].to_s() + " role=" + role.to_s() + " sig=" + next_sig1[next_count].to_s() + ":" + next_sig2[next_count].to_s()
          next_count += 1
          progress = 1
        role += 1
    @beam_count = next_count
    slot = 0
    while slot < next_count
      ffpanbl_copy_terms(next_u, next_v, next_w, slot * @capacity, @beam_u, @beam_v, @beam_w, slot * @capacity, next_rank[slot])
      @beam_rank[slot] = next_rank[slot]
      @beam_density[slot] = next_density[slot]
      @beam_distance[slot] = next_distance[slot]
      @beam_sig1[slot] = next_sig1[slot]
      @beam_sig2[slot] = next_sig2[slot]
      d = 0
      while d <= level
        @beam_generators[slot * @max_depth + d] = next_generators[slot * @max_depth + d]
        @beam_kinds[slot * @max_depth + d] = next_kinds[slot * @max_depth + d]
        @beam_a[slot * @max_depth + d] = next_a[slot * @max_depth + d]
        @beam_b[slot * @max_depth + d] = next_b[slot * @max_depth + d]
        @beam_c[slot * @max_depth + d] = next_c[slot * @max_depth + d]
        @beam_weights[slot * @max_depth + d] = next_weights[slot * @max_depth + d]
        d += 1
      slot += 1
    next_count

  -> run(depth, deep_generators, stats)
    i = 0 ## i64
    while i < stats.size()
      stats[i] = 0
      i += 1
    stats[2] = @rank + 1
    stats[20] = @rank
    stats[21] = @root_density
    level = 0 ## i64
    while level < depth && @beam_count > 0
      clear_pool()
      generators = deep_generators ## i64
      if level == 0
        generators = ffpan_elementary_count(@n)
      parent_count = @beam_count ## i64
      parent = 0 ## i64
      while parent < parent_count
        scan_parent(parent, level, generators, stats)
        parent += 1
      selected = select_next(level) ## i64
      << "PARTIAL_AUTOMORPHISM_BEAM_LEVEL depth=" + (level + 1).to_s() + " parents=" + parent_count.to_s() + " selected=" + selected.to_s() + " seen=" + @seen_count.to_s()
      level += 1
    level

  -> provenance(slot)
    text = "" ## String
    d = 0 ## i64
    while d < @archive_depth[slot]
      decoded = i64[4]
      flat = @archive_generators[slot * @max_depth + d] ## i64
      kind = @archive_kinds[slot * @max_depth + d] ## i64
      dependency_a = @archive_a[slot * @max_depth + d] ## i64
      dependency_b = @archive_b[slot * @max_depth + d] ## i64
      dependency_c = @archive_c[slot * @max_depth + d] ## i64
      weight = @archive_weights[slot * @max_depth + d] ## i64
      ffpan_elementary_decode(@n, flat, decoded)
      edge = "g" + flat.to_s() + "(" + decoded[0].to_s() + ":" + decoded[1].to_s() + ":" + decoded[2].to_s() + ">" + decoded[3].to_s() + ")/c" + kind.to_s() + ":d" + dependency_a.to_s()
      if kind >= 2
        edge += "," + dependency_b.to_s()
      if kind == 3
        edge += "," + dependency_c.to_s()
      if kind >= 4
        edge += "," + (dependency_c / 256).to_s() + "," + (dependency_c % 256).to_s()
      edge += "/w" + weight.to_s()
      if d > 0
        text += ";"
      text += edge
      d += 1
    text

  -> publish(publish_enabled)
    if publish_enabled == 0
      return 0
    labels = ["dense", "far", "deep_dense", "deep_far", "rank_drop"]
    published = 0 ## i64
    slot = 0 ## i64
    while slot < 5
      if @archive_valid[slot] == 1
        duplicate = 0 ## i64
        prior = 0 ## i64
        while prior < slot && duplicate == 0
          if @archive_valid[prior] == 1 && @archive_sig1[prior] == @archive_sig1[slot] && @archive_sig2[prior] == @archive_sig2[slot]
            duplicate = 1
          prior += 1
        if duplicate == 0
          candidate_u = i64[@capacity]
          candidate_v = i64[@capacity]
          candidate_w = i64[@capacity]
          ffpanbl_copy_terms(@archive_u, @archive_v, @archive_w, slot * @capacity, candidate_u, candidate_v, candidate_w, 0, @archive_rank[slot])
          ffpanbl_sort_terms(candidate_u, candidate_v, candidate_w, @archive_rank[slot])
          state = i64[ffw_state_size(@capacity)]
          loaded = ffw_init_terms_cap(state, candidate_u, candidate_v, candidate_w, @archive_rank[slot], @n, @capacity, 980001 + slot, 0, 1, 1, 1) ## i64
          ffpanbl_expect("publish exact", loaded == @archive_rank[slot] && ffw_verify_best_exact(state, @n) == 1)
          path = "benchmarks/matmul/metaflip/matmul_7x7_rank" + @archive_rank[slot].to_s() + "_d" + @archive_density[slot].to_s() + "_partial_auto_beam_" + labels[slot] + "_gf2.txt" ## String
          dumped = ffw_dump_best(state, path) ## i64
          ffpanbl_expect("publish dump", dumped == @archive_rank[slot])
          << "PARTIAL_AUTOMORPHISM_BEAM_PUBLISHED objective=" + labels[slot] + " path=" + path + " rank=" + @archive_rank[slot].to_s() + " density=" + @archive_density[slot].to_s() + " root_distance=" + @archive_distance[slot].to_s() + " depth=" + @archive_depth[slot].to_s() + " sig=" + @archive_sig1[slot].to_s() + ":" + @archive_sig2[slot].to_s() + " provenance=" + provenance(slot)
          published += 1
      slot += 1
    published

  -> continuation(moves, trials)
    if moves < 1 || trials < 1
      return 0
    tested = 0 ## i64
    control_rank_wins = 0 ## i64
    control_density_wins = 0 ## i64
    endpoint_rank_wins = 0 ## i64
    endpoint_density_wins = 0 ## i64
    slot = 0 ## i64
    while slot < 4
      if @archive_valid[slot] == 1 && @archive_rank[slot] == @rank
        duplicate = 0 ## i64
        prior = 0 ## i64
        while prior < slot && duplicate == 0
          if @archive_valid[prior] == 1 && @archive_sig1[prior] == @archive_sig1[slot] && @archive_sig2[prior] == @archive_sig2[slot]
            duplicate = 1
          prior += 1
        if duplicate == 0
          trial = 0 ## i64
          while trial < trials
            seed = 990001 + slot * 1009 + trial * 101 ## i64
            workq = moves / 4 ## i64
            wanderq = moves / 16 ## i64
            if workq < 1
              workq = 1
            if wanderq < 1
              wanderq = 1
            endpoint_state = i64[ffw_state_size(@capacity)]
            control_state = i64[ffw_state_size(@capacity)]
            endpoint_u = i64[@capacity]
            endpoint_v = i64[@capacity]
            endpoint_w = i64[@capacity]
            ffpanbl_copy_terms(@archive_u, @archive_v, @archive_w, slot * @capacity, endpoint_u, endpoint_v, endpoint_w, 0, @archive_rank[slot])
            endpoint_loaded = ffw_init_terms_cap(endpoint_state, endpoint_u, endpoint_v, endpoint_w, @archive_rank[slot], @n, @capacity, seed, 4, 4, workq, wanderq) ## i64
            control_loaded = ffw_init_terms_cap(control_state, @root_u, @root_v, @root_w, @rank, @n, @capacity, seed, 4, 4, workq, wanderq) ## i64
            ffpanbl_expect("continuation init", endpoint_loaded == @rank && control_loaded == @rank)
            ffw_walk(endpoint_state, moves)
            ffw_walk(control_state, moves)
            ffpanbl_expect("continuation exact", ffw_verify_best_exact(endpoint_state, @n) == 1 && ffw_verify_best_exact(control_state, @n) == 1)
            endpoint_rank = ffw_best_rank(endpoint_state) ## i64
            endpoint_density = ffw_best_bits(endpoint_state) ## i64
            control_rank = ffw_best_rank(control_state) ## i64
            control_density = ffw_best_bits(control_state) ## i64
            if endpoint_rank < @rank
              endpoint_rank_wins += 1
            if endpoint_rank == @rank && endpoint_density < @root_density
              endpoint_density_wins += 1
            if control_rank < @rank
              control_rank_wins += 1
            if control_rank == @rank && control_density < @root_density
              control_density_wins += 1
            << "PARTIAL_AUTOMORPHISM_BEAM_CONTINUATION objective=" + slot.to_s() + " trial=" + trial.to_s() + " moves=" + moves.to_s() + " endpoint=r" + endpoint_rank.to_s() + "/d" + endpoint_density.to_s() + " control=r" + control_rank.to_s() + "/d" + control_density.to_s()
            tested += 1
            trial += 1
      slot += 1
    << "PARTIAL_AUTOMORPHISM_BEAM_CONTINUATION_SUMMARY arms=" + tested.to_s() + " moves/arm=" + moves.to_s() + " endpoint_rank_wins=" + endpoint_rank_wins.to_s() + " endpoint_density_wins=" + endpoint_density_wins.to_s() + " control_rank_wins=" + control_rank_wins.to_s() + " control_density_wins=" + control_density_wins.to_s()
    tested

args = argv()
depth = 3 ## i64
width = 4 ## i64
combo_cap = 128 ## i64
deep_generators = 63 ## i64
continuation_moves = 1000000 ## i64
trials = 2 ## i64
publish_enabled = 1 ## i64
if args.size() > 0
  depth = args[0].to_i()
if args.size() > 1
  width = args[1].to_i()
if args.size() > 2
  combo_cap = args[2].to_i()
if args.size() > 3
  deep_generators = args[3].to_i()
if args.size() > 4
  continuation_moves = args[4].to_i()
if args.size() > 5
  trials = args[5].to_i()
if args.size() > 6
  publish_enabled = args[6].to_i()
ffpanbl_expect("arguments", depth >= 1 && depth <= 4 && width >= 1 && width <= 12 && combo_cap >= 1 && combo_cap <= 4096 && deep_generators >= 1 && deep_generators <= 189 && continuation_moves >= 0 && trials >= 0)

n = 7 ## i64
capacity = ffw_default_capacity(n) ## i64
source = i64[ffw_state_size(capacity)]
source_path = "benchmarks/matmul/metaflip/matmul_7x7_rank247_d3098_global_isotropy_gf2.txt"
rank = ffw_load_scheme_cap(source, source_path, n, capacity, 960001, 0, 1, 1, 1) ## i64
ffpanbl_expect("source", rank == 247 && ffw_verify_best_exact(source, n) == 1)
source_u = i64[capacity]
source_v = i64[capacity]
source_w = i64[capacity]
ffpanbl_expect("source export", ffw_export_best(source, source_u, source_v, source_w) == rank)

seen_capacity = 250000 ## i64
lab = FFPANBeamLab.new(source_u, source_v, source_w, rank, n, capacity, depth, width, combo_cap, seen_capacity)
stats = i64[40]
started = ccall("__w_clock_ms") ## i64
completed_depth = lab.run(depth, deep_generators, stats) ## i64
elapsed = ccall("__w_clock_ms") - started ## i64
min_nullity = stats[2] ## i64
if min_nullity > rank
  min_nullity = 0
coverage_milli = 0 ## i64
if stats[6] > 0
  coverage_milli = stats[7] * 1000 / stats[6]
<< "PARTIAL_AUTOMORPHISM_BEAM_SUMMARY depth=" + completed_depth.to_s() + " width=" + width.to_s() + " combo_cap=" + combo_cap.to_s() + " generators=" + stats[0].to_s() + " nullity_min=" + min_nullity.to_s() + " nullity_max=" + stats[3].to_s() + " nullity_avg_milli=" + (stats[1] * 1000 / stats[0]).to_s() + " effective_max=" + stats[5].to_s() + " effective_avg_milli=" + (stats[4] * 1000 / stats[0]).to_s() + " theoretical_combos=" + stats[6].to_s() + " unique_combo_masks=" + stats[7].to_s() + " coverage_milli=" + coverage_milli.to_s() + " singles=" + stats[23].to_s() + " pairs=" + stats[24].to_s() + " triples=" + stats[25].to_s() + " quadruples=" + stats[27].to_s() + " capped_generators=" + stats[26].to_s() + " materialized=" + stats[10].to_s() + " exact=" + stats[11].to_s() + " source_quotient=" + stats[12].to_s() + " global_quotient=" + stats[13].to_s() + " genuine=" + stats[14].to_s() + " graph_unique=" + stats[18].to_s() + " graph_duplicate=" + stats[17].to_s() + " seen_overflow=" + stats[19].to_s() + " rank_drops=" + stats[15].to_s() + " density_better=" + stats[16].to_s() + " best_rank=" + stats[20].to_s() + " best_density=" + stats[21].to_s() + " max_root_distance=" + stats[22].to_s() + " stable_avg_milli=" + (stats[31] * 1000 / stats[0]).to_s() + " stable_max=" + stats[32].to_s() + " elimination_ms=" + stats[29].to_s() + " admission_ms=" + stats[30].to_s() + " elapsed_ms=" + elapsed.to_s()
published = lab.publish(publish_enabled) ## i64
continued = lab.continuation(continuation_moves, trials) ## i64
<< "flipfleet_partial_automorphism_nullspace_beam_bench: done published=" + published.to_s() + " continuation_arms=" + continued.to_s()
