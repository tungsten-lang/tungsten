# Align-then-relink pair convergence (move 12).
#
# Exact GF(2) content, two coupled meta-operations on same-rank pairs (S1, S2):
#
# (a) Transporter alignment: steepest-ascent over short whole-scheme isotropy
#     words g -- the same elementary coordinate-swap / GL(n,2) transvection
#     generators per contracted domain that flipfleet_global_isotropy
#     enumerates, with the contragredient partner updates baked into
#     ffpa_transform_term_kind so g(S2) stays an exact decomposition at every
#     step -- maximizing OVERLAP(S1, g(S2)) = number of identical rank-one
#     terms after XOR canonicalization, instead of ffgir's density objective.
#     Unlike the density descent, coordinate swaps ARE enumerated: against a
#     fixed reference term set a swap changes the image term set, so it is a
#     real overlap move even though it preserves Hamming weight.
#
# (b) Elastic-band relink: a bounded flip/split walk from S1 preferring moves
#     that shrink |S delta g(S2)| (symmetric difference of canonical term
#     sets), with rank allowed up to rank(S1) + beta.  beta starts at 0 and
#     escalates only on stall; the walk records the minimal beta at which it
#     reaches g(S2) exactly (an empirical barrier height) or the closest
#     approach.  Every same-rank state on the path whose distance to BOTH
#     endpoints exceeds a threshold is a saddle candidate: it is full
#     n^6-gated, serialized, independently re-parsed and re-gated before its
#     bank file is kept.
#
# Caveat discipline: the reported minimum over tried words g of
# |S1 delta g(S2)| is strictly a ONE-SIDED upper bound on orbit distance.
# A witness of 0 proves orbit equivalence; failure to reach 0 proves nothing
# about inequivalence.  Output labels carry the same caveat.

use flipfleet_global_isotropy
use flipfleet_archive_nullspace

-> ffar_shell_quote(text) (String)
  "'" + text.replace("'", "'\"'\"'") + "'"

# Overlap of two duplicate-free XOR-canonical term sets: the number of exactly
# matching rank-one terms.
-> ffar_overlap_count(left_u, left_v, left_w, left_rank, right_u, right_v, right_w, right_rank) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  common = 0 ## i64
  i = 0 ## i64
  while i < left_rank
    if ffnd_term_in(right_u, right_v, right_w, right_rank, left_u[i], left_v[i], left_w[i]) == 1
      common += 1
    i += 1
  common

# Symmetric-difference distance for duplicate-free canonical term sets.
-> ffar_distance(left_u, left_v, left_w, left_rank, right_u, right_v, right_w, right_rank) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  left_rank + right_rank - 2 * ffar_overlap_count(left_u, left_v, left_w, left_rank, right_u, right_v, right_w, right_rank)

-> ffar_term_in_offset(us, vs, ws, base, rank, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
  found = 0 ## i64
  i = 0 ## i64
  while i < rank && found == 0
    if us[base + i] == u && vs[base + i] == v && ws[base + i] == w
      found = 1
    i += 1
  found

-> ffar_distance_offset(left_u, left_v, left_w, left_rank, right_u, right_v, right_w, right_base, right_rank) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64) i64
  common = 0 ## i64
  i = 0 ## i64
  while i < left_rank
    if ffar_term_in_offset(right_u, right_v, right_w, right_base, right_rank, left_u[i], left_v[i], left_w[i]) == 1
      common += 1
    i += 1
  left_rank + right_rank - 2 * common

# Score one whole-scheme generator's image against a fixed reference term set:
# |reference delta g(scheme)| for the single-generator extension g.  The
# transformed masks come from the same authoritative partial-automorphism
# primitive used by apply/replay, so the image stays an exact decomposition.
# Returns the distance, or 0 - 1 when the generator does not apply.
-> ffar_generator_distance(us, vs, ws, rank, n, operation, domain, source, target, ref_u, ref_v, ref_w, ref_rank, scratch_u, scratch_v, scratch_w) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64[] i64[] i64[] i64 i64[] i64[] i64[]) i64
  transformed = i64[3]
  i = 0 ## i64
  while i < rank
    if ffpa_transform_term_kind(us[i], vs[i], ws[i], n, operation, domain, source, target, transformed) != 1
      return 0 - 1
    scratch_u[i] = transformed[0]
    scratch_v[i] = transformed[1]
    scratch_w[i] = transformed[2]
    i += 1
  ffar_distance(scratch_u, scratch_v, scratch_w, rank, ref_u, ref_v, ref_w, ref_rank)

# Steepest single-generator step for the overlap objective.  Enumerates the
# exact ffgir generator set: coordinate swaps (operation 0, normalized
# source < target) and ordered elementary transvections (operation 1) over the
# three contracted domains.  out = i64[5] receives operation (0 - 1 when no
# strict improvement exists), domain, source, target, resulting distance.
# Returns the number of evaluated generators (each one is a tried word).
-> ffar_best_overlap_generator(us, vs, ws, rank, n, current_distance, ref_u, ref_v, ref_w, ref_rank, scratch_u, scratch_v, scratch_w, out) (i64[] i64[] i64[] i64 i64 i64 i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[]) i64
  out[0] = 0 - 1
  out[1] = 0
  out[2] = 0
  out[3] = 0
  out[4] = current_distance
  evaluations = 0 ## i64
  operation = 0 ## i64
  while operation < 2
    domain = 0 ## i64
    while domain < 3
      source = 0 ## i64
      while source < n
        target = 0 ## i64
        while target < n
          eligible = 0 ## i64
          if source != target
            eligible = 1
          if operation == 0 && source > target
            eligible = 0
          if eligible == 1
            distance = ffar_generator_distance(us, vs, ws, rank, n, operation, domain, source, target, ref_u, ref_v, ref_w, ref_rank, scratch_u, scratch_v, scratch_w) ## i64
            evaluations += 1
            if distance >= 0 && distance < out[4]
              out[0] = operation
              out[1] = domain
              out[2] = source
              out[3] = target
              out[4] = distance
          target += 1
        source += 1
      domain += 1
    operation += 1
  evaluations

-> ffar_copy_word(src_operations, src_domains, src_sources, src_targets, dst_operations, dst_domains, dst_sources, dst_targets, length) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64) i64
  j = 0 ## i64
  while j < length
    dst_operations[j] = src_operations[j]
    dst_domains[j] = src_domains[j]
    dst_sources[j] = src_sources[j]
    dst_targets[j] = src_targets[j]
    j += 1
  length

# Transporter alignment: multi-restart steepest-ascent over short isotropy
# words applied to S2, maximizing term-set overlap with S1.  The word budget
# counts every evaluated candidate word (each enumerated single-generator
# extension and each restart word is a tried g); one neighborhood scan may
# overshoot the budget by at most one neighborhood.
#
# The reported best distance is a ONE-SIDED upper bound on orbit distance:
# 0 proves S1 and S2 share a global-isotropy orbit, anything else proves
# nothing.
#
# verify_steps != 0 additionally rebuilds and full n^6-gates the image after
# EVERY accepted step and restart (test builds); production callers pass 0 and
# rely on the mandatory final gate.
#
# out_operations/out_domains/out_sources/out_targets (each i64 of size
# >= max_word) receive the best word; out_state (i64 of ffw_state_size
# words for the shared capacity) receives the transformed partner g(S2),
# rebuilt from the pristine S2 export and independently full-gated.
#
# meta (i64 of size >= 16): 0 identity distance, 1 best distance (one-sided
# upper bound), 2 best word length, 3 tried words, 4 accepted steps,
# 5 restarts, 6 final-image full-gate flag, 7 best overlap, 8 in-walk verify
# failures, 9 shared rank, 10 word budget.
#
# Returns the best overlap (rank means proven orbit equivalence), or
# 0 - 1 invalid input, 0 - 2 an in-walk exactness gate failed,
# 0 - 3 the final image failed the full gate.
-> ffar_align(st1, st2, n, capacity, budget, max_word, seed, verify_steps, out_operations, out_domains, out_sources, out_targets, out_state, meta) (i64[] i64[] i64 i64 i64 i64 i64 i64 i64[] i64[] i64[] i64[] i64[] i64[]) i64
  i = 0 ## i64
  while i < 16
    meta[i] = 0
    i += 1
  meta[1] = 0 - 1
  meta[10] = budget
  if ffw_valid(st1) != 1 || ffw_valid(st2) != 1 || ffw_n(st1) != n || ffw_n(st2) != n
    return 0 - 1
  if budget < 1 || max_word < 1 || max_word > 64 || capacity < 1
    return 0 - 1
  rank = ffw_best_rank(st1) ## i64
  if rank < 1 || rank > capacity || ffw_best_rank(st2) != rank
    return 0 - 1
  if ffw_verify_best_exact(st1, n) != 1 || ffw_verify_best_exact(st2, n) != 1
    return 0 - 1
  meta[9] = rank
  au = i64[capacity]
  av = i64[capacity]
  aw = i64[capacity]
  bu = i64[capacity]
  bv = i64[capacity]
  bw = i64[capacity]
  cu = i64[capacity]
  cv = i64[capacity]
  cw = i64[capacity]
  su = i64[capacity]
  sv = i64[capacity]
  sw = i64[capacity]
  if ffw_export_best(st1, au, av, aw) != rank || ffw_export_best(st2, bu, bv, bw) != rank
    return 0 - 1
  z = ffgir_copy_terms(bu, bv, bw, cu, cv, cw, rank)
  cur_operations = i64[max_word]
  cur_domains = i64[max_word]
  cur_sources = i64[max_word]
  cur_targets = i64[max_word]
  cur_length = 0 ## i64
  cur_distance = ffar_distance(cu, cv, cw, rank, au, av, aw, rank) ## i64
  tried = 1 ## i64
  best_distance = cur_distance ## i64
  best_length = 0 ## i64
  accepted = 0 ## i64
  restarts = 0 ## i64
  verify_failures = 0 ## i64
  meta[0] = cur_distance
  step = i64[5]
  while tried < budget && best_distance > 0 && verify_failures == 0
    improved = 0 ## i64
    if cur_length < max_word
      tried += ffar_best_overlap_generator(cu, cv, cw, rank, n, cur_distance, au, av, aw, rank, su, sv, sw, step)
      if step[0] >= 0 && step[4] < cur_distance
        if ffgir_apply_generator(cu, cv, cw, rank, n, step[0], step[1], step[2], step[3]) == rank
          cur_operations[cur_length] = step[0]
          cur_domains[cur_length] = step[1]
          cur_sources[cur_length] = step[2]
          cur_targets[cur_length] = step[3]
          cur_length += 1
          cur_distance = step[4]
          accepted += 1
          improved = 1
          if verify_steps != 0
            checked = ffw_init_terms_cap(out_state, cu, cv, cw, rank, n, capacity, seed + 7 * accepted, 0, 1, 1, 1) ## i64
            if checked != rank || ffw_verify_best_exact(out_state, n) != 1
              verify_failures += 1
          if cur_distance < best_distance
            best_distance = cur_distance
            best_length = cur_length
            z = ffar_copy_word(cur_operations, cur_domains, cur_sources, cur_targets, out_operations, out_domains, out_sources, out_targets, cur_length)
    if improved == 0 && best_distance > 0 && verify_failures == 0
      # Stalled hill climb: restart from a fresh short random word applied to
      # the pristine partner.  The restart word itself is a tried g.
      restarts += 1
      z = ffgir_copy_terms(bu, bv, bw, cu, cv, cw, rank)
      cur_length = 0
      cur_distance = meta[0]
      want = 1 + ((seed + restarts * 13) % 4) ## i64
      if want > max_word
        want = max_word
      made = ffgir_make_word(n, seed * 40009 + restarts * 271, want, cur_operations, cur_domains, cur_sources, cur_targets) ## i64
      if made == want
        if ffgir_apply_word(cu, cv, cw, rank, n, cur_operations, cur_domains, cur_sources, cur_targets, made, 0) == rank
          cur_length = made
          cur_distance = ffar_distance(cu, cv, cw, rank, au, av, aw, rank)
          tried += 1
          if verify_steps != 0
            checked = ffw_init_terms_cap(out_state, cu, cv, cw, rank, n, capacity, seed + 11 * restarts, 0, 1, 1, 1) ## i64
            if checked != rank || ffw_verify_best_exact(out_state, n) != 1
              verify_failures += 1
          if cur_distance < best_distance
            best_distance = cur_distance
            best_length = cur_length
            z = ffar_copy_word(cur_operations, cur_domains, cur_sources, cur_targets, out_operations, out_domains, out_sources, out_targets, cur_length)
        else
          z = ffgir_copy_terms(bu, bv, bw, cu, cv, cw, rank)
          cur_length = 0
          cur_distance = meta[0]
  meta[1] = best_distance
  meta[2] = best_length
  meta[3] = tried
  meta[4] = accepted
  meta[5] = restarts
  meta[8] = verify_failures
  if verify_failures > 0
    return 0 - 2
  # Rebuild the best image from the pristine partner export and full-gate it.
  z = ffgir_copy_terms(bu, bv, bw, cu, cv, cw, rank)
  if best_length > 0
    if ffgir_apply_word(cu, cv, cw, rank, n, out_operations, out_domains, out_sources, out_targets, best_length, 0) != rank
      return 0 - 3
  loaded = ffw_init_terms_cap(out_state, cu, cv, cw, rank, n, capacity, seed, 0, 1, 1, 1) ## i64
  if loaded != rank || ffw_verify_best_exact(out_state, n) != 1
    return 0 - 3
  meta[6] = 1
  overlap = rank - best_distance / 2 ## i64
  meta[7] = overlap
  overlap

# Union nullity of a pair: GF(2) nullity of the stacked rank-one tensor
# columns of BOTH term sets (arank + brank columns over n^6 rows), via the
# archive-nullspace elimination helper.  Raising overlap raises union nullity
# one-for-one per matched pair; the splice lanes bottleneck at nullity 1, so
# this is the pair's splice richness before/after alignment.  meta (i64 of
# size >= 6): ffnd_build_nullspace meta 0..4 plus 5 = stacked column count.
-> ffar_union_nullity(au, av, aw, arank, bu, bv, bw, brank, n, meta) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64 i64[]) i64
  count = arank + brank ## i64
  if arank < 1 || brank < 1 || n < 2 || n > 7
    return 0 - 1
  uu = i64[count]
  uv = i64[count]
  uw = i64[count]
  i = 0 ## i64
  while i < arank
    uu[i] = au[i]
    uv[i] = av[i]
    uw[i] = aw[i]
    i += 1
  j = 0 ## i64
  while j < brank
    uu[arank + j] = bu[j]
    uv[arank + j] = bv[j]
    uw[arank + j] = bw[j]
    j += 1
  basis = i64[count * ffnd_combo_words(count)]
  nullity = ffnd_build_nullspace(uu, uv, uw, count, n, basis, meta) ## i64
  meta[5] = count
  nullity

# Delta nullity: nullity of the symmetric-difference set only (the splice-lane
# view; the whole difference of two exact schemes always XORs to tensor zero,
# so a nonempty difference has nullity >= 1).  meta as in ffar_union_nullity
# with 5 = difference size.
-> ffar_delta_nullity(au, av, aw, arank, bu, bv, bw, brank, n, meta) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64 i64[]) i64
  if arank < 1 || brank < 1 || n < 2 || n > 7
    return 0 - 1
  du = i64[arank + brank]
  dv = i64[arank + brank]
  dw = i64[arank + brank]
  owners = i64[arank + brank]
  count = ffnd_build_difference(au, av, aw, arank, bu, bv, bw, brank, du, dv, dw, owners) ## i64
  i = 0 ## i64
  while i < 5
    meta[i] = 0
    i += 1
  meta[5] = count
  if count == 0
    return 0
  basis = i64[count * ffnd_combo_words(count)]
  nullity = ffnd_build_nullspace(du, dv, dw, count, n, basis, meta) ## i64
  meta[5] = count
  nullity

# ---- elastic-band relink ---------------------------------------------------

-> ffar_push_term(mu, mv, mw, count, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  if u == 0 || v == 0 || w == 0
    return count
  mu[count] = u
  mv[count] = v
  mw[count] = w
  count + 1

# Build one random exact flip proposal into mu/mv/mw (first the two removals,
# then the surviving folded terms; a folded term whose new factor cancels to
# zero is dropped, which is the rank-reducing case of the identity).  Every
# variant below is the exact GF(2) four-term identity
#   t1 + t2 = folded1 + folded2
# on a pair sharing the drawn axis factor.  Returns the toggle count, or 0
# when the drawn term has no partner on the drawn axis.
-> ffar_propose_flip(st, rng, mu, mv, mw) (i64[] i64[] i64[] i64[] i64[]) i64
  rank = ffw_current_rank(st) ## i64
  if rank < 2
    return 0
  pick = ffgir_next(rng) % rank ## i64
  axis = ffgir_next(rng) % 3 ## i64
  slot = st[st[50] + pick] ## i64
  partner = ffw_pick_partner(st, axis, slot, ffgir_next(rng)) ## i64
  if partner < 0
    return 0
  u1 = st[st[44] + slot] ## i64
  v1 = st[st[45] + slot] ## i64
  w1 = st[st[46] + slot] ## i64
  u2 = st[st[44] + partner] ## i64
  v2 = st[st[45] + partner] ## i64
  w2 = st[st[46] + partner] ## i64
  variant = ffgir_next(rng) & 1 ## i64
  count = 0 ## i64
  count = ffar_push_term(mu, mv, mw, count, u1, v1, w1)
  count = ffar_push_term(mu, mv, mw, count, u2, v2, w2)
  if axis == 0
    if variant == 0
      count = ffar_push_term(mu, mv, mw, count, u1, v1, w1 ^ w2)
      count = ffar_push_term(mu, mv, mw, count, u1, v1 ^ v2, w2)
    else
      count = ffar_push_term(mu, mv, mw, count, u1, v2, w1 ^ w2)
      count = ffar_push_term(mu, mv, mw, count, u1, v1 ^ v2, w1)
  if axis == 1
    if variant == 0
      count = ffar_push_term(mu, mv, mw, count, u1 ^ u2, v1, w2)
      count = ffar_push_term(mu, mv, mw, count, u1, v1, w1 ^ w2)
    else
      count = ffar_push_term(mu, mv, mw, count, u1 ^ u2, v1, w1)
      count = ffar_push_term(mu, mv, mw, count, u2, v1, w1 ^ w2)
  if axis == 2
    if variant == 0
      count = ffar_push_term(mu, mv, mw, count, u1 ^ u2, v2, w1)
      count = ffar_push_term(mu, mv, mw, count, u1, v1 ^ v2, w1)
    else
      count = ffar_push_term(mu, mv, mw, count, u1 ^ u2, v1, w1)
      count = ffar_push_term(mu, mv, mw, count, u2, v1 ^ v2, w1)
  count

# Build one random exact split proposal (rank + 1): replace (f, v, w) with
# (part, v, w) + (f ^ part, v, w) on a random axis.  Returns the toggle count
# (3), or 0 when the drawn factor has fewer than two set bits.
-> ffar_propose_split(st, rng, mu, mv, mw) (i64[] i64[] i64[] i64[] i64[]) i64
  rank = ffw_current_rank(st) ## i64
  if rank < 1
    return 0
  pick = ffgir_next(rng) % rank ## i64
  axis = ffgir_next(rng) % 3 ## i64
  slot = st[st[50] + pick] ## i64
  u = st[st[44] + slot] ## i64
  v = st[st[45] + slot] ## i64
  w = st[st[46] + slot] ## i64
  factor = u ## i64
  if axis == 1
    factor = v
  if axis == 2
    factor = w
  if ffw_popcount(factor) < 2
    return 0
  draw = ffgir_next(rng) | (ffgir_next(rng) << 31) ## i64
  part = factor & draw ## i64
  if part == 0 || part == factor
    part = factor & (0 - factor)
  rest = factor ^ part ## i64
  count = 0 ## i64
  count = ffar_push_term(mu, mv, mw, count, u, v, w)
  if axis == 0
    count = ffar_push_term(mu, mv, mw, count, part, v, w)
    count = ffar_push_term(mu, mv, mw, count, rest, v, w)
  if axis == 1
    count = ffar_push_term(mu, mv, mw, count, u, part, w)
    count = ffar_push_term(mu, mv, mw, count, u, rest, w)
  if axis == 2
    count = ffar_push_term(mu, mv, mw, count, u, v, part)
    count = ffar_push_term(mu, mv, mw, count, u, v, rest)
  count

# XOR-toggle one term on the live state while maintaining the incremental
# bookkeeping.  track = i64[3]: 0 current rank, 1 common terms with the target
# set, 2 common terms with the source set.  Returns 1 applied, 0 - 1 refused
# (zero factor or capacity refusal; the set is unchanged and the caller must
# roll back the partially applied move).
-> ffar_toggle_track(st, u, v, w, track, tgt_u, tgt_v, tgt_w, tgt_rank, src_u, src_v, src_w, src_rank) (i64[] i64 i64 i64 i64[] i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  if u == 0 || v == 0 || w == 0
    return 0 - 1
  before = track[0] ## i64
  after = ffw_toggle(st, u, v, w, before) ## i64
  if after == before
    return 0 - 1
  st[6] = after
  delta = after - before ## i64
  if ffnd_term_in(tgt_u, tgt_v, tgt_w, tgt_rank, u, v, w) == 1
    track[1] = track[1] + delta
  if ffnd_term_in(src_u, src_v, src_w, src_rank, u, v, w) == 1
    track[2] = track[2] + delta
  track[0] = after
  1

-> ffar_undo_move(st, mu, mv, mw, count, track, tgt_u, tgt_v, tgt_w, tgt_rank, src_u, src_v, src_w, src_rank) (i64[] i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  ok = 1 ## i64
  index = count - 1 ## i64
  while index >= 0
    if ffar_toggle_track(st, mu[index], mv[index], mw[index], track, tgt_u, tgt_v, tgt_w, tgt_rank, src_u, src_v, src_w, src_rank) != 1
      ok = 0
    index -= 1
  ok

# Apply a proposal; on any refusal the already-applied prefix is rolled back
# (all toggles are XOR involutions).  Returns 1 applied, 0 rolled back.
-> ffar_apply_move(st, mu, mv, mw, count, track, tgt_u, tgt_v, tgt_w, tgt_rank, src_u, src_v, src_w, src_rank) (i64[] i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  applied = 0 ## i64
  ok = 1 ## i64
  while applied < count && ok == 1
    if ffar_toggle_track(st, mu[applied], mv[applied], mw[applied], track, tgt_u, tgt_v, tgt_w, tgt_rank, src_u, src_v, src_w, src_rank) != 1
      ok = 0
    if ok == 1
      applied += 1
  if ok == 0
    z = ffar_undo_move(st, mu, mv, mw, applied, track, tgt_u, tgt_v, tgt_w, tgt_rank, src_u, src_v, src_w, src_rank)
  ok

# Publish the live current set: full n^6 gate, serialize, independently
# re-parse into gate_state and re-gate the file bytes.  On any failure the
# file is removed and 0 is returned.
-> ffar_publish_current(st, gate_state, n, capacity, seed, path) (i64[] i64[] i64 i64 i64 String) i64
  rank = ffw_current_rank(st) ## i64
  if rank < 1 || path.size() < 1
    return 0
  if ffw_verify_current_exact(st, n) != 1
    return 0
  if ffw_dump_current(st, path) != rank
    z = system("/bin/rm -f " + ffar_shell_quote(path))
    return 0
  reload = ffw_load_scheme_cap(gate_state, path, n, capacity, seed, 0, 1, 1, 1) ## i64
  if reload != rank || ffw_verify_current_exact(gate_state, n) != 1
    z = system("/bin/rm -f " + ffar_shell_quote(path))
    return 0
  1

# Elastic-band relink from the source set toward the target set.
#
# Bounded walk over exact flip identities (and exact splits once beta > 0)
# preferring moves that shrink |S delta target|: strict shrink is always
# accepted, equal distance is accepted with probability 1/2, growth with
# probability 1/16, all subject to rank <= src_rank + beta.  beta starts at 0
# and escalates only after stall_window moves without a closest-approach
# improvement, up to beta_max.
#
# Saddle harvest: an accepted same-rank state whose distance to BOTH endpoints
# exceeds saddle_threshold is published through ffar_publish_current to
# bank_prefix + "_saddle_<k>.txt" (dump, re-parse, re-gate), spaced at least
# saddle_threshold from every previously harvested state.  A state whose rank
# falls strictly below src_rank is published to bank_prefix + "_drop.txt".
# Pass max_saddles = 0 and bank_prefix = "" to disable all publication.
#
# meta (i64 of size >= 20): 0 start distance, 1 closest approach, 2 moves,
# 3 accepted, 4 rejected, 5 reached flag, 6 beta at reach (0 - 1 when not
# reached), 7 final beta, 8 saddles kept, 9 publish gate failures, 10 max rank
# seen, 11 splits accepted, 12 bookkeeping/exactness failures (must stay 0),
# 13 beta escalations, 14 move index of closest approach, 15 end exactness
# flag, 16 rank-drop events below src_rank, 17 capacity aborts, 18 final
# distance to target, 19 final rank.
#
# Returns the closest approach (0 = target reached exactly: the minimal beta
# in meta 6 is the empirical barrier height), or 0 - 1 on invalid input.
# The closest approach is a ONE-SIDED bound: reaching 0 proves flip-graph
# connectivity within the tried band; anything else proves nothing.
-> ffar_relink(src_u, src_v, src_w, src_rank, tgt_u, tgt_v, tgt_w, tgt_rank, n, capacity, move_budget, beta_max, stall_window, seed, saddle_threshold, max_saddles, bank_prefix, verify_every, meta) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64 i64 i64 String i64 i64[]) i64
  i = 0 ## i64
  while i < 20
    meta[i] = 0
    i += 1
  meta[6] = 0 - 1
  if src_rank < 2 || tgt_rank < 1 || n < 2 || n > 7 || capacity < src_rank
    return 0 - 1
  if move_budget < 0 || beta_max < 0 || stall_window < 1 || max_saddles < 0 || saddle_threshold < 0
    return 0 - 1
  state_size = ffw_state_size(capacity) ## i64
  st = i64[state_size]
  gate_state = i64[state_size]
  loaded = ffw_init_terms_cap(st, src_u, src_v, src_w, src_rank, n, capacity, seed, 0, 1, 1, 1) ## i64
  if loaded != src_rank
    return 0 - 1
  track = i64[3]
  track[0] = src_rank
  track[1] = ffar_overlap_count(src_u, src_v, src_w, src_rank, tgt_u, tgt_v, tgt_w, tgt_rank)
  track[2] = src_rank
  rng = i64[1]
  rng[0] = (seed ^ (n * 7046029254386353131)) & 9223372036854775807
  mu = i64[4]
  mv = i64[4]
  mw = i64[4]
  eu = i64[capacity]
  ev = i64[capacity]
  ew = i64[capacity]
  harvested_u = i64[(max_saddles + 1) * capacity]
  harvested_v = i64[(max_saddles + 1) * capacity]
  harvested_w = i64[(max_saddles + 1) * capacity]
  distance = track[0] + tgt_rank - 2 * track[1] ## i64
  best_distance = distance ## i64
  meta[0] = distance
  reached = 0 ## i64
  reach_beta = 0 - 1 ## i64
  if distance == 0
    reached = 1
    reach_beta = 0
  beta = 0 ## i64
  escalations = 0 ## i64
  accepted = 0 ## i64
  rejected = 0 ## i64
  splits = 0 ## i64
  saddles = 0 ## i64
  gate_failures = 0 ## i64
  bookkeeping_failures = 0 ## i64
  capacity_aborts = 0 ## i64
  rank_drops = 0 ## i64
  max_rank = src_rank ## i64
  closest_move = 0 ## i64
  last_gain = 0 ## i64
  harvest_gate = 0 ## i64
  aborted = 0 ## i64
  moves = 0 ## i64
  while moves < move_budget && reached == 0 && aborted == 0
    moves += 1
    if moves - last_gain > stall_window && beta < beta_max
      beta += 1
      escalations += 1
      last_gain = moves
    is_split = 0 ## i64
    if beta > 0 && track[0] < src_rank + beta
      if (ffgir_next(rng) & 7) == 0
        is_split = 1
    count = 0 ## i64
    if is_split == 1
      count = ffar_propose_split(st, rng, mu, mv, mw)
    if is_split == 0
      count = ffar_propose_flip(st, rng, mu, mv, mw)
    if count < 3
      rejected += 1
    if count >= 3
      old_distance = track[0] + tgt_rank - 2 * track[1] ## i64
      if ffar_apply_move(st, mu, mv, mw, count, track, tgt_u, tgt_v, tgt_w, tgt_rank, src_u, src_v, src_w, src_rank) != 1
        capacity_aborts += 1
        aborted = 1
      else
        new_rank = track[0] ## i64
        new_distance = new_rank + tgt_rank - 2 * track[1] ## i64
        accept = 0 ## i64
        if new_rank <= src_rank + beta
          if new_distance < old_distance
            accept = 1
          if accept == 0 && new_distance == old_distance
            if (ffgir_next(rng) & 1) == 0
              accept = 1
          if accept == 0 && (ffgir_next(rng) & 15) == 0
            accept = 1
        if accept == 0
          if ffar_undo_move(st, mu, mv, mw, count, track, tgt_u, tgt_v, tgt_w, tgt_rank, src_u, src_v, src_w, src_rank) != 1
            capacity_aborts += 1
            aborted = 1
          rejected += 1
        if accept == 1
          accepted += 1
          if is_split == 1
            splits += 1
          if new_rank > max_rank
            max_rank = new_rank
          if new_rank < src_rank
            rank_drops += 1
            if bank_prefix.size() > 0
              if ffar_publish_current(st, gate_state, n, capacity, seed + 53 * rank_drops, bank_prefix + "_drop.txt") == 0
                gate_failures += 1
          if new_distance < best_distance
            best_distance = new_distance
            closest_move = moves
            last_gain = moves
            if best_distance == 0
              reached = 1
              reach_beta = beta
          if verify_every > 0 && aborted == 0
            if (accepted % verify_every) == 0
              if ffw_verify_current_exact(st, n) != 1
                bookkeeping_failures += 1
                aborted = 1
          if reached == 0 && aborted == 0 && saddles < max_saddles && new_rank == src_rank && accepted >= harvest_gate
            source_distance = new_rank + src_rank - 2 * track[2] ## i64
            if new_distance > saddle_threshold && source_distance > saddle_threshold
              stride = saddle_threshold ## i64
              if stride < 8
                stride = 8
              harvest_gate = accepted + stride
              exported = ffw_export_current(st, eu, ev, ew) ## i64
              spaced = 0 ## i64
              if exported == new_rank
                spaced = 1
                back = saddles - 1 ## i64
                while back >= 0 && spaced == 1
                  if ffar_distance_offset(eu, ev, ew, new_rank, harvested_u, harvested_v, harvested_w, back * capacity, src_rank) <= saddle_threshold
                    spaced = 0
                  back -= 1
              if spaced == 1
                path = bank_prefix + "_saddle_" + saddles.to_s() + ".txt"
                if ffar_publish_current(st, gate_state, n, capacity, seed + 91 * saddles + 17, path) == 1
                  base = saddles * capacity ## i64
                  c = 0 ## i64
                  while c < new_rank
                    harvested_u[base + c] = eu[c]
                    harvested_v[base + c] = ev[c]
                    harvested_w[base + c] = ew[c]
                    c += 1
                  saddles += 1
                else
                  gate_failures += 1
  final_rank = track[0] ## i64
  final_distance = final_rank + tgt_rank - 2 * track[1] ## i64
  end_exact = ffw_verify_current_exact(st, n) ## i64
  if end_exact != 1
    bookkeeping_failures += 1
  # Cross-check the incremental distance bookkeeping against a fresh recount.
  exported_end = ffw_export_current(st, eu, ev, ew) ## i64
  if exported_end == final_rank
    recount = ffar_distance(eu, ev, ew, final_rank, tgt_u, tgt_v, tgt_w, tgt_rank) ## i64
    if recount != final_distance
      bookkeeping_failures += 1
  else
    bookkeeping_failures += 1
  meta[1] = best_distance
  meta[2] = moves
  meta[3] = accepted
  meta[4] = rejected
  meta[5] = reached
  meta[6] = reach_beta
  meta[7] = beta
  meta[8] = saddles
  meta[9] = gate_failures
  meta[10] = max_rank
  meta[11] = splits
  meta[12] = bookkeeping_failures
  meta[13] = escalations
  meta[14] = closest_move
  meta[15] = end_exact
  meta[16] = rank_drops
  meta[17] = capacity_aborts
  meta[18] = final_distance
  meta[19] = final_rank
  best_distance
