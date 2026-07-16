# Whole-scheme matrix-multiplication isotropy helpers.
#
# A word in the I/K/J coordinate swaps and GL(n,2) transvections from
# `strategies/partial_automorphism` is applied to every rank-one term.  This is
# an exact automorphism of the matrix-multiplication tensor.  The operation is
# useful as a controlled restart experiment, but it must not be mistaken for
# a new algebraic scheme: replaying the same self-inverse generators in
# reverse order recovers the source term set exactly.

use partial_automorphism
use ../fleet/basins

-> ffgir_next(rng) (i64[]) i64
  value = (rng[0] * 6364136223846793005 + 1442695040888963407) & 9223372036854775807 ## i64
  rng[0] = value
  (value >> 32) & 2147483647

# Build a deterministic sparse word.  operation 0 is a coordinate swap and
# operation 1 is an ordered transvection.  Both generators are involutions,
# which keeps replay/inversion cheap and independently testable.
-> ffgir_make_word(n, seed, length, operations, domains, sources, targets) (i64 i64 i64 i64[] i64[] i64[] i64[]) i64
  if n < 2 || n > 7 || length < 1
    return 0
  rng = i64[1]
  rng[0] = (seed ^ (n * 7046029254386353131)) & 9223372036854775807
  made = 0 ## i64
  while made < length
    operation = ffgir_next(rng) & 1 ## i64
    domain = ffgir_next(rng) % 3 ## i64
    source = ffgir_next(rng) % n ## i64
    target = ffgir_next(rng) % (n - 1) ## i64
    if target >= source
      target += 1
    if operation == 0 && source > target
      swap = source ## i64
      source = target
      target = swap
    # Do not emit an adjacent self-cancelling generator.  Longer relations
    # are legal; the inverse test below is authoritative.
    duplicate = 0 ## i64
    if made > 0
      if operations[made - 1] == operation && domains[made - 1] == domain && sources[made - 1] == source && targets[made - 1] == target
        duplicate = 1
    if duplicate == 0
      operations[made] = operation
      domains[made] = domain
      sources[made] = source
      targets[made] = target
      made += 1
  made

-> ffgir_apply_generator(us, vs, ws, rank, n, operation, domain, source, target) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64) i64
  if rank < 1
    return 0
  transformed = i64[3]
  i = 0 ## i64
  while i < rank
    if ffpa_transform_term_kind(us[i], vs[i], ws[i], n, operation, domain, source, target, transformed) != 1
      return 0
    us[i] = transformed[0]
    vs[i] = transformed[1]
    ws[i] = transformed[2]
    i += 1
  rank

-> ffgir_apply_word(us, vs, ws, rank, n, operations, domains, sources, targets, length, inverse) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64[] i64 i64) i64
  if length < 1
    return 0
  step = 0 ## i64
  while step < length
    index = step ## i64
    if inverse != 0
      index = length - 1 - step
    if ffgir_apply_generator(us, vs, ws, rank, n, operations[index], domains[index], sources[index], targets[index]) != rank
      return 0
    step += 1
  rank

-> ffgir_copy_terms(source_u, source_v, source_w, target_u, target_v, target_w, rank) (i64[] i64[] i64[] i64[] i64[] i64[] i64) i64
  i = 0 ## i64
  while i < rank
    target_u[i] = source_u[i]
    target_v[i] = source_v[i]
    target_w[i] = source_w[i]
    i += 1
  rank

-> ffgir_term_equal(left_u, left_v, left_w, left, right_u, right_v, right_w, right) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  equal = 0 ## i64
  if left_u[left] == right_u[right] && left_v[left] == right_v[right] && left_w[left] == right_w[right]
    equal = 1
  equal

# Permutation-invariant symmetric-difference distance for XOR term sets.
-> ffgir_term_set_distance(left_u, left_v, left_w, left_rank, right_u, right_v, right_w, right_rank) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  used = i64[right_rank]
  common = 0 ## i64
  i = 0 ## i64
  while i < left_rank
    found = 0 ## i64
    j = 0 ## i64
    while j < right_rank && found == 0
      if used[j] == 0 && ffgir_term_equal(left_u, left_v, left_w, i, right_u, right_v, right_w, j) == 1
        used[j] = 1
        common += 1
        found = 1
      j += 1
    i += 1
  left_rank + right_rank - common - common

-> ffgir_terms_equal(left_u, left_v, left_w, left_rank, right_u, right_v, right_w, right_rank) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  equal = 0 ## i64
  if left_rank == right_rank
    if ffgir_term_set_distance(left_u, left_v, left_w, left_rank, right_u, right_v, right_w, right_rank) == 0
      equal = 1
  equal

-> ffgir_density(us, vs, ws, rank) (i64[] i64[] i64[] i64) i64
  density = 0 ## i64
  i = 0 ## i64
  while i < rank
    density += ffw_popcount(us[i]) + ffw_popcount(vs[i]) + ffw_popcount(ws[i])
    i += 1
  density

# Number of matrix coordinates touched by at least one term on each factor,
# summed over U/V/W.  Density measures multiplicity; this measures union
# support and makes the distinction explicit in restart audits.
-> ffgir_union_support(us, vs, ws, rank) (i64[] i64[] i64[] i64) i64
  union_u = 0 ## i64
  union_v = 0 ## i64
  union_w = 0 ## i64
  i = 0 ## i64
  while i < rank
    union_u = union_u | us[i]
    union_v = union_v | vs[i]
    union_w = union_w | ws[i]
    i += 1
  ffw_popcount(union_u) + ffw_popcount(union_v) + ffw_popcount(union_w)

# Count distinct factor masks independently on the three axes.  Equality
# structure controls ordinary partner availability and is invariant under a
# whole-scheme invertible basis change.
-> ffgir_distinct_factor_support(us, vs, ws, rank) (i64[] i64[] i64[] i64) i64
  distinct = 0 ## i64
  axis = 0 ## i64
  while axis < 3
    i = 0 ## i64
    while i < rank
      value = us[i] ## i64
      if axis == 1
        value = vs[i]
      if axis == 2
        value = ws[i]
      seen = 0 ## i64
      j = 0 ## i64
      while j < i && seen == 0
        prior = us[j] ## i64
        if axis == 1
          prior = vs[j]
        if axis == 2
          prior = ws[j]
        if prior == value
          seen = 1
        j += 1
      if seen == 0
        distinct += 1
      i += 1
    axis += 1
  distinct

# Score one whole-scheme generator without materializing its image.  The
# transformed factor masks are still produced by the same authoritative
# partial-automorphism primitive used by apply/replay.
-> ffgir_generator_density(us, vs, ws, rank, n, operation, domain, source, target) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64) i64
  density = 0 ## i64
  transformed = i64[3]
  i = 0 ## i64
  while i < rank
    if ffpa_transform_term_kind(us[i], vs[i], ws[i], n, operation, domain, source, target, transformed) != 1
      return 0 - 1
    density += ffw_popcount(transformed[0]) + ffw_popcount(transformed[1]) + ffw_popcount(transformed[2])
    i += 1
  density

# Find the steepest elementary GL density descent.  `out` receives operation,
# domain, source, target, and resulting density.  Coordinate swaps are omitted:
# they preserve Hamming weight, and conjugating the complete ordered set of
# transvections by a swap merely permutes that same neighborhood.
-> ffgir_best_density_generator(us, vs, ws, rank, n, out) (i64[] i64[] i64[] i64 i64 i64[]) i64
  current = ffgir_density(us, vs, ws, rank) ## i64
  out[0] = 0 - 1
  out[1] = 0
  out[2] = 0
  out[3] = 0
  out[4] = current
  evaluations = 0 ## i64
  domain = 0 ## i64
  while domain < 3
    source = 0 ## i64
    while source < n
      target = 0 ## i64
      while target < n
        if source != target
          density = ffgir_generator_density(us, vs, ws, rank, n, 1, domain, source, target) ## i64
          evaluations += 1
          if density >= 0 && density < out[4]
            out[0] = 1
            out[1] = domain
            out[2] = source
            out[3] = target
            out[4] = density
        target += 1
      source += 1
    domain += 1
  evaluations

# Repeated steepest descent within the whole-scheme GL orbit.  stats receives
# start density, final density, accepted generators, and evaluated neighbors.
# Every accepted step is rank-neutral and exact by construction; callers must
# still serialize/reparse/full-gate any artifact before publication.
-> ffgir_density_descent(us, vs, ws, rank, n, max_steps, stats) (i64[] i64[] i64[] i64 i64 i64 i64[]) i64
  start = ffgir_density(us, vs, ws, rank) ## i64
  current = start ## i64
  accepted = 0 ## i64
  evaluations = 0 ## i64
  running = 1 ## i64
  while running == 1 && accepted < max_steps
    best = i64[5]
    evaluations += ffgir_best_density_generator(us, vs, ws, rank, n, best)
    if best[0] != 1 || best[4] >= current
      running = 0
    else
      applied = ffgir_apply_generator(us, vs, ws, rank, n, best[0], best[1], best[2], best[3]) ## i64
      if applied != rank
        running = 0
      else
        current = best[4]
        accepted += 1
  stats[0] = start
  stats[1] = current
  stats[2] = accepted
  stats[3] = evaluations
  current

# Coarse, cheap GL-invariant telemetry signature.  Equality only says two
# states may share a global-isotropy orbit; inequality proves they do not.
# This deliberately reuses the matrix-rank histogram already maintained by
# basin telemetry instead of pretending to be a full GL canonicalizer.
-> ffgir_orbit_signature_view(state, current) (i64[] i64) i64
  rank = ffw_best_rank(state) ## i64
  if current != 0
    rank = ffw_current_rank(state)
  (ffbi_gl_invariant_view(state, current) * 257 + rank) & 2147483647

-> ffgir_orbit_signature(state) (i64[]) i64
  ffgir_orbit_signature_view(state, 0)

# Run bounded directed descent on a worker best and build a separately owned,
# independently full-gated state.  A non-improving local minimum returns zero
# without touching `destination`.  stats is the four-word descent descriptor.
-> ffgir_density_descent_state_into(source, destination, n, capacity, seed, dslack, cycles, workq, wanderq, max_steps, stats) (i64[] i64[] i64 i64 i64 i64 i64 i64 i64 i64 i64[]) i64
  if ffw_valid(source) != 1 || ffw_n(source) != n || ffw_verify_best_exact(source, n) != 1
    return 0
  rank = ffw_best_rank(source) ## i64
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  exported = ffw_export_best(source, us, vs, ws) ## i64
  if exported != rank
    return 0
  final_density = ffgir_density_descent(us, vs, ws, rank, n, max_steps, stats) ## i64
  if stats[2] < 1 || final_density >= stats[0]
    return 0
  loaded = ffw_init_terms_cap(destination, us, vs, ws, rank, n, capacity, seed, dslack, cycles, workq, wanderq) ## i64
  if loaded != rank || ffw_best_bits(destination) != final_density || ffw_verify_best_exact(destination, n) != 1
    return 0
  rank

# Export current, replay a word, and return its raw distance to another
# current worker.  A zero value proves that the paired walks remained exactly
# conjugate under the tested global isotropy word.
-> ffgir_conjugate_current_distance(control, image, n, capacity, operations, domains, sources, targets, length) (i64[] i64[] i64 i64 i64[] i64[] i64[] i64[] i64) i64
  cu = i64[capacity]
  cv = i64[capacity]
  cw = i64[capacity]
  iu = i64[capacity]
  iv = i64[capacity]
  iw = i64[capacity]
  control_rank = ffw_export_current(control, cu, cv, cw) ## i64
  image_rank = ffw_export_current(image, iu, iv, iw) ## i64
  if control_rank < 1 || image_rank < 1
    return 0 - 1
  if ffgir_apply_word(cu, cv, cw, control_rank, n, operations, domains, sources, targets, length, 0) != control_rank
    return 0 - 1
  ffgir_term_set_distance(cu, cv, cw, control_rank, iu, iv, iw, image_rank)
