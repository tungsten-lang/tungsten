# Bounded beam search over exact mixed escape recipes.
#
# Unlike the old split+split composition control, a recipe may mix generic
# split, fixed-cube break, orbit split, polarization, and two-split compose.
# Every edge is an exact identity from `strategies/escape`; the beam scores only
# complete endpoints and keeps the recipe needed for deterministic replay.

use ../scheme
use escape

-> ffbr_copy(source_u, source_v, source_w, count, dest_u, dest_v, dest_w) (i64[] i64[] i64[] i64 i64[] i64[] i64[]) i64
  i = 0 ## i64
  while i < count
    dest_u[i] = source_u[i]
    dest_v[i] = source_v[i]
    dest_w[i] = source_w[i]
    i += 1
  count

-> ffbr_copy_slot(source_u, source_v, source_w, source_offset, count, dest_u, dest_v, dest_w, dest_offset) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64) i64
  i = 0 ## i64
  while i < count
    dest_u[dest_offset + i] = source_u[source_offset + i]
    dest_v[dest_offset + i] = source_v[source_offset + i]
    dest_w[dest_offset + i] = source_w[source_offset + i]
    i += 1
  count

-> ffbr_same_term(u0, v0, w0, u1, v1, w1) (i64 i64 i64 i64 i64 i64) i64
  same = 0 ## i64
  if u0 == u1 && v0 == v1 && w0 == w1
    same = 1
  same

-> ffbr_common(left_u, left_v, left_w, left_count, right_u, right_v, right_w, right_count) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  used = i64[right_count]
  common = 0 ## i64
  i = 0 ## i64
  while i < left_count
    j = 0 ## i64
    found = 0 - 1 ## i64
    while j < right_count && found < 0
      if used[j] == 0
        if ffbr_same_term(left_u[i], left_v[i], left_w[i], right_u[j], right_v[j], right_w[j]) == 1
          found = j
      j += 1
    if found >= 0
      used[found] = 1
      common += 1
    i += 1
  common

-> ffbr_same_set(left_u, left_v, left_w, left_count, right_u, right_v, right_w, right_count) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  if left_count != right_count
    return 0
  same = 0 ## i64
  if ffbr_common(left_u, left_v, left_w, left_count, right_u, right_v, right_w, right_count) == left_count
    same = 1
  same

-> ffbr_density(us, vs, ws, count) (i64[] i64[] i64[] i64) i64
  bits = 0 ## i64
  i = 0 ## i64
  while i < count
    bits += ffw_popcount(us[i]) + ffw_popcount(vs[i]) + ffw_popcount(ws[i])
    i += 1
  bits

-> ffbr_score(base_u, base_v, base_w, base_rank, us, vs, ws, rank) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  common = ffbr_common(base_u, base_v, base_w, base_rank, us, vs, ws, rank) ## i64
  distance = base_rank + rank - 2 * common ## i64
  debt = rank - base_rank ## i64
  if debt < 0
    debt = 0
  # Rank debt dominates; within an equal shoulder prefer a far endpoint, then
  # lower density.  This keeps the production beam near R+2 instead of letting
  # a spectacularly distant polarization consume all continuation budget.
  distance * 10000 - debt * 100000 - ffbr_density(us, vs, ws, rank)

-> ffbr_apply_branch(us, vs, ws, rank, capacity, n, branch, nonce_base, meta) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64[]) i64
  kind = (branch % 5) + 1 ## i64
  variant = branch / 5 ## i64
  nonce = nonce_base + variant * 97 + kind * 17 ## i64
  ffe_apply(us, vs, ws, rank, capacity, n, kind, nonce, meta)

-> ffbr_slot_same(candidate_u, candidate_v, candidate_w, candidate_rank, slots_u, slots_v, slots_w, slot_offset, slot_rank) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64) i64
  if candidate_rank != slot_rank
    return 0
  slot_u = i64[slot_rank]
  slot_v = i64[slot_rank]
  slot_w = i64[slot_rank]
  z = ffbr_copy_slot(slots_u, slots_v, slots_w, slot_offset, slot_rank, slot_u, slot_v, slot_w, 0) ## i64
  ffbr_same_set(candidate_u, candidate_v, candidate_w, candidate_rank, slot_u, slot_v, slot_w, slot_rank)

# Beam result metadata: endpoint rank, score, distance, depth, and the chosen
# operation kinds in recipe[0..depth).  Branches use three nonce variants.
-> ffbr_beam_search(source_u, source_v, source_w, source_rank, capacity, n, depth, beam_width, nonce_base, out_u, out_v, out_w, recipe, meta) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64[] i64[] i64[] i64[] i64[]) i64
  if source_rank < 1 || capacity < source_rank + 2 || depth < 1 || depth > 3 || beam_width < 1 || beam_width > 16
    return 0
  beam_u = i64[beam_width * capacity]
  beam_v = i64[beam_width * capacity]
  beam_w = i64[beam_width * capacity]
  beam_ranks = i64[beam_width]
  beam_scores = i64[beam_width]
  beam_recipes = i64[beam_width * depth]
  z = ffbr_copy_slot(source_u, source_v, source_w, 0, source_rank, beam_u, beam_v, beam_w, 0) ## i64
  beam_ranks[0] = source_rank
  beam_scores[0] = 0
  beam_count = 1 ## i64
  level = 0 ## i64
  while level < depth
    next_u = i64[beam_width * capacity]
    next_v = i64[beam_width * capacity]
    next_w = i64[beam_width * capacity]
    next_ranks = i64[beam_width]
    next_scores = i64[beam_width]
    next_recipes = i64[beam_width * depth]
    next_count = 0 ## i64
    parent = 0 ## i64
    while parent < beam_count
      branch = 0 ## i64
      while branch < 15
        candidate_u = i64[capacity]
        candidate_v = i64[capacity]
        candidate_w = i64[capacity]
        parent_rank = beam_ranks[parent] ## i64
        z = ffbr_copy_slot(beam_u, beam_v, beam_w, parent * capacity, parent_rank, candidate_u, candidate_v, candidate_w, 0)
        move_meta = i64[8]
        candidate_rank = ffbr_apply_branch(candidate_u, candidate_v, candidate_w, parent_rank, capacity, n, branch, nonce_base + level * 1009, move_meta) ## i64
        if candidate_rank > 0 && move_meta[7] == 1
          duplicate = 0 ## i64
          slot = 0 ## i64
          while slot < next_count && duplicate == 0
            duplicate = ffbr_slot_same(candidate_u, candidate_v, candidate_w, candidate_rank, next_u, next_v, next_w, slot * capacity, next_ranks[slot])
            slot += 1
          if duplicate == 0
            score = ffbr_score(source_u, source_v, source_w, source_rank, candidate_u, candidate_v, candidate_w, candidate_rank) ## i64
            target_slot = next_count ## i64
            if next_count < beam_width
              next_count += 1
            if target_slot >= beam_width
              target_slot = 0
              scan = 1 ## i64
              while scan < beam_width
                if next_scores[scan] < next_scores[target_slot]
                  target_slot = scan
                scan += 1
              if score <= next_scores[target_slot]
                target_slot = 0 - 1
            if target_slot >= 0
              z = ffbr_copy_slot(candidate_u, candidate_v, candidate_w, 0, candidate_rank, next_u, next_v, next_w, target_slot * capacity)
              next_ranks[target_slot] = candidate_rank
              next_scores[target_slot] = score
              rindex = 0 ## i64
              while rindex < level
                next_recipes[target_slot * depth + rindex] = beam_recipes[parent * depth + rindex]
                rindex += 1
              next_recipes[target_slot * depth + level] = (branch % 5) + 1
        branch += 1
      parent += 1
    if next_count == 0
      return 0
    beam_u = next_u
    beam_v = next_v
    beam_w = next_w
    beam_ranks = next_ranks
    beam_scores = next_scores
    beam_recipes = next_recipes
    beam_count = next_count
    level += 1
  best = 0 ## i64
  i = 1 ## i64
  while i < beam_count
    if beam_scores[i] > beam_scores[best]
      best = i
    i += 1
  result_rank = beam_ranks[best] ## i64
  z = ffbr_copy_slot(beam_u, beam_v, beam_w, best * capacity, result_rank, out_u, out_v, out_w, 0)
  i = 0
  while i < depth
    recipe[i] = beam_recipes[best * depth + i]
    i += 1
  common = ffbr_common(source_u, source_v, source_w, source_rank, out_u, out_v, out_w, result_rank) ## i64
  meta[0] = result_rank
  meta[1] = beam_scores[best]
  meta[2] = source_rank + result_rank - 2 * common
  meta[3] = depth
  result_rank

# Exhaustive depth-two planted-recovery helper over the same mixed branch
# alphabet.  It validates that the enumerator, not merely the identity checker,
# can rediscover a hidden recipe endpoint.
-> ffbr_find_target2(source_u, source_v, source_w, source_rank, capacity, n, nonce_base, wanted_u, wanted_v, wanted_w, wanted_rank, out_recipe) (i64[] i64[] i64[] i64 i64 i64 i64 i64[] i64[] i64[] i64 i64[]) i64
  first_u = i64[capacity]
  first_v = i64[capacity]
  first_w = i64[capacity]
  second_u = i64[capacity]
  second_v = i64[capacity]
  second_w = i64[capacity]
  branch0 = 0 ## i64
  while branch0 < 15
    z = ffbr_copy(source_u, source_v, source_w, source_rank, first_u, first_v, first_w) ## i64
    move0 = i64[8]
    rank0 = ffbr_apply_branch(first_u, first_v, first_w, source_rank, capacity, n, branch0, nonce_base, move0) ## i64
    if rank0 > 0 && move0[7] == 1
      branch1 = 0 ## i64
      while branch1 < 15
        z = ffbr_copy(first_u, first_v, first_w, rank0, second_u, second_v, second_w)
        move1 = i64[8]
        rank1 = ffbr_apply_branch(second_u, second_v, second_w, rank0, capacity, n, branch1, nonce_base + 1009, move1) ## i64
        if rank1 == wanted_rank && move1[7] == 1
          if ffbr_same_set(second_u, second_v, second_w, rank1, wanted_u, wanted_v, wanted_w, wanted_rank) == 1
            out_recipe[0] = (branch0 % 5) + 1
            out_recipe[1] = (branch1 % 5) + 1
            return rank1
        branch1 += 1
    branch0 += 1
  0
