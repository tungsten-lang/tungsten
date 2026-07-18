# Exact support-component peeling for close archive parents.
#
# If A and B are exact decompositions of the same tensor, their symmetric
# difference D is a zero tensor.  Join two terms of D when their Cartesian
# tensor supports overlap, i.e. when all three pairs of factor masks
# intersect.  Distinct graph components then touch disjoint tensor cells, so
# every component must itself be a zero tensor.  Toggling one proper component
# into either parent yields an exact hybrid without enumerating the nullspace
# of the complete difference.
#
# This is deliberately a bounded coordinator move.  Both parents, every
# component relation, every materialized child, and the returned winner pass
# complete n^6 reconstruction gates.  Ordinary worker moves never call it.

use archive_nullspace

-> ffdc_supports_overlap(u0, v0, w0, u1, v1, w1) (i64 i64 i64 i64 i64 i64) i64
  if (u0 & u1) == 0
    return 0
  if (v0 & v1) == 0
    return 0
  if (w0 & w1) == 0
    return 0
  1

-> ffdc_label_components(us, vs, ws, count, labels, queue) (i64[] i64[] i64[] i64 i64[] i64[]) i64
  if count < 1 || labels.size() < count || queue.size() < count
    return 0
  i = 0 ## i64
  while i < count
    labels[i] = 0 - 1
    i += 1
  components = 0 ## i64
  root = 0 ## i64
  while root < count
    if labels[root] < 0
      head = 0 ## i64
      tail = 1 ## i64
      queue[0] = root
      labels[root] = components
      while head < tail
        current = queue[head] ## i64
        head += 1
        other = 0 ## i64
        while other < count
          if labels[other] < 0
            if ffdc_supports_overlap(us[current], vs[current], ws[current], us[other], vs[other], ws[other]) == 1
              labels[other] = components
              queue[tail] = other
              tail += 1
          other += 1
      components += 1
    root += 1
  components

-> ffdc_copy_terms(source_u, source_v, source_w, count, target_u, target_v, target_w) (i64[] i64[] i64[] i64 i64[] i64[] i64[]) i64
  if target_u.size() < count || target_v.size() < count || target_w.size() < count
    return 0
  i = 0 ## i64
  while i < count
    target_u[i] = source_u[i]
    target_v[i] = source_v[i]
    target_w[i] = source_w[i]
    i += 1
  count

-> ffdc_better(rank, bits, best_rank, best_bits) (i64 i64 i64 i64) i64
  if best_rank < 1 || rank < best_rank
    return 1
  if rank == best_rank && bits < best_bits
    return 1
  0

# Return the best exact single-component peel from either parent.  The
# symmetric difference is bounded before graph work; testing both bases covers
# a component and its complementary union without exponential subset search.
#
# meta layout:
# [0] difference terms, [1] support components, [2] relations tested,
# [3] exact relations, [4] children gated, [5] exact children,
# [6] winner rank, [7] winner density, [8] winner component,
# [9] winner base (0=A, 1=B), [10] winner relation size,
# [11] independent returned-winner gate.
-> ffdc_crossover_best_states(parent_a, parent_b, n, max_difference, output, capacity, seed, dslack, cycles, workq, wanderq, meta) (i64[] i64[] i64 i64 i64[] i64 i64 i64 i64 i64 i64 i64[]) i64
  if meta.size() < 12 || capacity < 1 || output.size() < ffw_state_size(capacity)
    return 0
  mi = 0 ## i64
  while mi < 12
    meta[mi] = 0
    mi += 1
  if max_difference < 4 || ffw_valid(parent_a) != 1 || ffw_valid(parent_b) != 1
    return 0
  if parent_a[2] != n || parent_b[2] != n
    return 0
  # Coordinator callers have usually just gated the candidate, but this move
  # treats both parents as untrusted inputs and proves them independently.
  if ffw_verify_best_exact(parent_a, n) != 1 || ffw_verify_best_exact(parent_b, n) != 1
    return 0

  arank = ffw_best_rank(parent_a) ## i64
  brank = ffw_best_rank(parent_b) ## i64
  acap = parent_a[4] ## i64
  bcap = parent_b[4] ## i64
  au = i64[acap]
  av = i64[acap]
  aw = i64[acap]
  bu = i64[bcap]
  bv = i64[bcap]
  bw = i64[bcap]
  z = ffw_export_best(parent_a, au, av, aw) ## i64
  z = ffw_export_best(parent_b, bu, bv, bw)

  difference_capacity = arank + brank ## i64
  du = i64[difference_capacity]
  dv = i64[difference_capacity]
  dw = i64[difference_capacity]
  owners = i64[difference_capacity]
  count = ffnd_build_difference(au, av, aw, arank, bu, bv, bw, brank, du, dv, dw, owners) ## i64
  meta[0] = count
  if count < 4 || count > max_difference
    return 0

  labels = i64[count]
  queue = i64[count]
  components = ffdc_label_components(du, dv, dw, count, labels, queue) ## i64
  meta[1] = components
  # One component is the original full parent difference, not a hybrid.
  if components < 2
    return 0

  combo_words = ffnd_combo_words(count) ## i64
  relation = i64[combo_words]
  candidate_u = i64[capacity]
  candidate_v = i64[capacity]
  candidate_w = i64[capacity]
  winner_u = i64[capacity]
  winner_v = i64[capacity]
  winner_w = i64[capacity]
  scratch = i64[ffw_state_size(capacity)]
  winner_rank = 0 - 1 ## i64
  winner_bits = 0 ## i64

  component = 0 ## i64
  while component < components
    z = ffnd_clear(relation, 0, combo_words)
    relation_size = 0 ## i64
    term = 0 ## i64
    while term < count
      if labels[term] == component
        z = ffnd_set_mask_bit(relation, 0, term)
        relation_size += 1
      term += 1
    meta[2] = meta[2] + 1
    relation_exact = ffnd_relation_exact(du, dv, dw, count, n, relation, 0) ## i64
    if relation_exact == 1
      meta[3] = meta[3] + 1
      base = 0 ## i64
      while base < 2
        base_u = au
        base_v = av
        base_w = aw
        base_rank = arank ## i64
        if base == 1
          base_u = bu
          base_v = bv
          base_w = bw
          base_rank = brank
        child_rank = ffnd_materialize(base_u, base_v, base_w, base_rank, du, dv, dw, count, relation, candidate_u, candidate_v, candidate_w) ## i64
        if child_rank > 0
          meta[4] = meta[4] + 1
          loaded = ffw_init_terms_cap(scratch, candidate_u, candidate_v, candidate_w, child_rank, n, capacity, seed + component * 17 + base, dslack, cycles, workq, wanderq) ## i64
          if loaded == child_rank && ffw_verify_best_exact(scratch, n) == 1
            meta[5] = meta[5] + 1
            child_bits = ffw_best_bits(scratch) ## i64
            if ffdc_better(child_rank, child_bits, winner_rank, winner_bits) == 1
              copied = ffdc_copy_terms(candidate_u, candidate_v, candidate_w, child_rank, winner_u, winner_v, winner_w) ## i64
              if copied == child_rank
                winner_rank = child_rank
                winner_bits = child_bits
                meta[8] = component
                meta[9] = base
                meta[10] = relation_size
        base += 1
    component += 1

  if winner_rank < 1
    return 0
  loaded = ffw_init_terms_cap(output, winner_u, winner_v, winner_w, winner_rank, n, capacity, seed + 1009, dslack, cycles, workq, wanderq) ## i64
  if loaded != winner_rank || ffw_verify_best_exact(output, n) != 1
    return 0
  meta[6] = winner_rank
  meta[7] = winner_bits
  meta[11] = 1
  winner_rank
