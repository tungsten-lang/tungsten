# Exact GF(2) arbitrary-dependency medians with rank-at-most-two D.
#
# For one fixed tensor axis, group each factor f_i with its full physical
# complementary matrix M_i.  If a bucket set S satisfies XOR_{i in S} f_i=0,
# then the common update M_i -> M_i ^ D is exact for every matrix D.
#
# This module extends flipfleet_gf2_dependency_median from live rank-one D to
# every unique D=A^B formed from two distinct live rank-one complementary
# matrices, retaining the singleton rank-one values as controls.  Every D is
# minimally factored into a canonical physical rank-1/rank-2 representation;
# an exact chained hash table removes duplicate matrices rather than duplicate
# generating pairs.
#
# The per-bucket delta rank(M_i^D)-rank(M_i) lies in [-2,+2].  Negative anchors
# are solved against all other nonpositive bucket factors by coordinate-
# recovering GF(2) elimination.  Zero, one, and two positive buckets are
# considered, prioritizing predicted direct drops, then neutral moves, then
# +1 shoulders.  Materialized endpoints pass coefficient-level local gates,
# parity compaction, a fresh worker rebuild, and the exhaustive n^6 gate.

use flipfleet_gf2_dependency_median

-> fflrd_hash(rank, left0, right0, left1, right1) (i64 i64 i64 i64 i64) i64
  first = ffcis_hash(left0,right0,left1) ## i64
  second = ffcis_hash(right1,rank,982451653) ## i64
  first ^ second

-> fflrd_same(index, rank, left0, right0, left1, right1, ranks, lefts0, rights0, lefts1, rights1) (i64 i64 i64 i64 i64 i64 i64[] i64[] i64[] i64[] i64[]) i64
  if ranks[index] == rank && lefts0[index] == left0 && rights0[index] == right0 && lefts1[index] == left1 && rights1[index] == right1
    return 1
  0

# Canonicalize one or two outer products.  Zero is rejected; rank one and two
# have deterministic ffsm physical factorizations and therefore exact keys.
-> fflrd_canonical(input_left, input_right, count, output_left, output_right) (i64[] i64[] i64 i64[] i64[]) i64
  if count < 1 || count > 2 || input_left.size() < count || input_right.size() < count || output_left.size() < 2 || output_right.size() < 2
    return 0
  output_left[0] = 0
  output_left[1] = 0
  output_right[0] = 0
  output_right[1] = 0
  rank = ffsm_rank_factor_matrix(input_left,input_right,count,output_left,output_right) ## i64
  if rank < 1 || rank > 2
    return 0
  rank

# Register a canonical D in a chained exact hash table.  Returns its new index
# or -1 when an equal physical matrix is already present.
-> fflrd_register(rank, left0, right0, left1, right1, ranks, lefts0, rights0, lefts1, rights1, links, heads, count) (i64 i64 i64 i64 i64 i64[] i64[] i64[] i64[] i64[] i32[] i32[] i64) i64
  if rank < 1 || rank > 2 || count < 0 || count >= ranks.size() || count >= links.size() || heads.size() < 1
    return 0 - 1
  slot = fflrd_hash(rank,left0,right0,left1,right1) & (heads.size() - 1) ## i64
  entry = heads[slot] ## i64
  while entry != 0
    index = entry - 1 ## i64
    if fflrd_same(index,rank,left0,right0,left1,right1,ranks,lefts0,rights0,lefts1,rights1) == 1
      return 0 - 1
    entry = links[index]
  ranks[count] = rank
  lefts0[count] = left0
  rights0[count] = right0
  lefts1[count] = left1
  rights1[count] = right1
  links[count] = heads[slot]
  heads[slot] = count + 1
  count

# Minimal physical factorization of M_bucket ^ D.
-> fflrd_factor_bucket(us, vs, ws, rank, axis, term_bucket, bucket, d_left, d_right, d_rank, out_left, out_right) (i64[] i64[] i64[] i64 i64 i64[] i64 i64[] i64[] i64 i64[] i64[]) i64
  if rank < 1 || axis < 0 || axis > 2 || term_bucket.size() < rank || bucket < 0 || d_rank < 0 || d_rank > 2 || d_left.size() < d_rank || d_right.size() < d_rank
    return 0 - 1
  lefts = i64[rank + 2]
  rights = i64[rank + 2]
  count = 0 ## i64
  position = 0 ## i64
  while position < rank
    if term_bucket[position] == bucket
      lefts[count] = ffpc5_axis_left(us,vs,ws,position,axis)
      rights[count] = ffpc5_axis_right(us,vs,ws,position,axis)
      count += 1
    position += 1
  item = 0 ## i64
  while item < d_rank
    lefts[count] = d_left[item]
    rights[count] = d_right[item]
    count += 1
    item += 1
  ffsm_rank_factor_matrix(lefts,rights,count,out_left,out_right)

# Fill and validate one dependency candidate, admitting only the requested
# predicted-debt ceiling.
-> fflrd_fill_if(factors, deltas, bucket_count, anchor, positive_a, positive_b, coordinates, basis_buckets, debt_ceiling, minimum_buckets, chosen, choice_meta) (i64[] i64[] i64 i64 i64 i64 i64 i64[] i64 i64 i64[] i64[]) i64
  ok = ffgdm_fill_choice(factors,deltas,bucket_count,anchor,positive_a,positive_b,coordinates,basis_buckets,chosen,choice_meta) ## i64
  if ok == 1 && choice_meta[0] <= debt_ceiling && choice_meta[2] >= minimum_buckets
    return 1
  0

# Find a dependency with total predicted delta <= debt_limit.  Direct drops
# are exhausted first; neutral and +1 families open only when requested.
-> fflrd_find_dependency(factors, deltas, bucket_count, debt_limit, minimum_buckets, chosen, choice_meta) (i64[] i64[] i64 i64 i64 i64[] i64[]) i64
  if debt_limit < -1 || debt_limit > 1 || minimum_buckets < 2
    return 0
  debt_ceiling = 0 - 1 ## i64
  while debt_ceiling <= debt_limit
    anchor = 0 ## i64
    while anchor < bucket_count
      if deltas[anchor] < 0
        pivots = i64[63]
        pivot_coordinates = i64[63]
        basis_buckets = i64[63]
        basis_rank = ffgdm_build_basis(factors,deltas,bucket_count,anchor,pivots,pivot_coordinates,basis_buckets) ## i64
        if basis_rank >= 0
          coordinates = ffgdm_solve_basis(factors[anchor],pivots,pivot_coordinates) ## i64
          if coordinates >= 0
            if fflrd_fill_if(factors,deltas,bucket_count,anchor,0-1,0-1,coordinates,basis_buckets,debt_ceiling,minimum_buckets,chosen,choice_meta) == 1
              return 1
          positive = 0 ## i64
          while positive < bucket_count
            if deltas[positive] > 0
              coordinates = ffgdm_solve_basis(factors[anchor] ^ factors[positive],pivots,pivot_coordinates) ## i64
              if coordinates >= 0
                if fflrd_fill_if(factors,deltas,bucket_count,anchor,positive,0-1,coordinates,basis_buckets,debt_ceiling,minimum_buckets,chosen,choice_meta) == 1
                  return 1
            positive += 1
          positive = 0
          while positive < bucket_count - 1
            if deltas[positive] > 0
              second = positive + 1 ## i64
              while second < bucket_count
                if deltas[second] > 0
                  target = factors[anchor] ^ factors[positive] ^ factors[second] ## i64
                  coordinates = ffgdm_solve_basis(target,pivots,pivot_coordinates) ## i64
                  if coordinates >= 0
                    if fflrd_fill_if(factors,deltas,bucket_count,anchor,positive,second,coordinates,basis_buckets,debt_ceiling,minimum_buckets,chosen,choice_meta) == 1
                      return 1
                second += 1
            positive += 1
      anchor += 1
    debt_ceiling += 1
  0

-> fflrd_materialize_choice(us, vs, ws, rank, axis, factors, term_bucket, bucket_count, chosen, d_left, d_right, d_rank, out_u, out_v, out_w) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64 i64[] i64[] i64[] i64 i64[] i64[] i64[]) i64
  capacity = out_u.size() ## i64
  if out_v.size() < capacity
    capacity = out_v.size()
  if out_w.size() < capacity
    capacity = out_w.size()
  made = 0 ## i64
  bucket = 0 ## i64
  while bucket < bucket_count
    if chosen[bucket] != 0
      factor_left = i64[63]
      factor_right = i64[63]
      matrix_rank = fflrd_factor_bucket(us,vs,ws,rank,axis,term_bucket,bucket,d_left,d_right,d_rank,factor_left,factor_right) ## i64
      if matrix_rank < 0 || made + matrix_rank > capacity
        return 0 - 1
      term = 0 ## i64
      while term < matrix_rank
        if ffmp_emit_term(axis,factors[bucket],factor_left[term],factor_right[term],out_u,out_v,out_w,made) == 0
          return 0 - 1
        made += 1
        term += 1
    bucket += 1
  made

# Search singleton controls followed by unique pair-XOR D values.  A positive
# d_cap bounds unique D values globally; zero is complete.
#
# meta:
#   0 raw atoms, 1 unique D tested, 2 singleton D, 3 raw pairs,
#   4 duplicate D, 5 rank-one D, 6 rank-two D, 7 buckets,
#   8 negative deltas, 9 zero deltas, 10 +1 deltas, 11 +2 deltas,
#   12 dependencies, 13 direct, 14 neutral, 15 +1 predicted,
#   16 local exact, 17 debt-admitted, 18 full gates, 19 failures,
#   20 endpoint drops, 21 endpoint neutral, 22 shoulders,
#   23 best rank, 24 best density, 25 source rank, 26 source density,
#   27 best axis, 28 best D rank, 29..32 best D factors,
#   33 best dependency buckets, 34/35 best local old/new,
#   36 best predicted delta, 37 D cap reached, 38 best initialized,
#   39 maximum dependency buckets, 40 axes visited.
-> fflrd_search_state_filtered(source, d_cap, debt_cap, nonce, minimum_buckets, minimum_d_rank, candidate, meta) (i64[] i64 i64 i64 i64 i64 i64[] i64[]) i64
  if ffw_valid(source) != 1 || d_cap < 0 || debt_cap < 0 || debt_cap > 1 || minimum_buckets < 2 || minimum_d_rank < 1 || minimum_d_rank > 2 || meta.size() < 41
    return 0
  i = 0 ## i64
  while i < 41
    meta[i] = 0
    i += 1
  rank = source[6] ## i64
  capacity = source[4] ## i64
  if rank < 2
    return 0
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  if ffw_export_current(source,us,vs,ws) != rank
    return 0
  meta[25] = rank
  meta[26] = ffw_current_bits(source)
  scratch = i64[ffw_state_size(capacity)]
  local_out_u = i64[capacity]
  local_out_v = i64[capacity]
  local_out_w = i64[capacity]
  stop = 0 ## i64
  axis_step = 0 ## i64
  while axis_step < 3 && stop == 0
    axis = (nonce + axis_step) % 3 ## i64
    offset = (nonce + axis * 17) % rank ## i64
    factors = i64[rank]
    term_bucket = i64[rank]
    bucket_sizes = i64[rank]
    bucket_count = ffgdm_group_axis(us,vs,ws,rank,axis,offset,factors,term_bucket,bucket_sizes) ## i64
    if bucket_count >= 2
      meta[40] = meta[40] + 1
      meta[7] = meta[7] + bucket_count
      base_ranks = i64[bucket_count]
      bucket = 0 ## i64
      while bucket < bucket_count
        base_left = i64[63]
        base_right = i64[63]
        empty_left = i64[1]
        empty_right = i64[1]
        base_ranks[bucket] = fflrd_factor_bucket(us,vs,ws,rank,axis,term_bucket,bucket,empty_left,empty_right,0,base_left,base_right)
        if base_ranks[bucket] < 0
          stop = 1
        bucket += 1

      atom_left = i64[rank]
      atom_right = i64[rank]
      atom_count = 0 ## i64
      logical = 0 ## i64
      while logical < rank && stop == 0
        position = (logical + offset) % rank ## i64
        left = ffpc5_axis_left(us,vs,ws,position,axis) ## i64
        right = ffpc5_axis_right(us,vs,ws,position,axis) ## i64
        duplicate = 0 ## i64
        atom = 0 ## i64
        while atom < atom_count && duplicate == 0
          if atom_left[atom] == left && atom_right[atom] == right
            duplicate = 1
          atom += 1
        if duplicate == 0
          atom_left[atom_count] = left
          atom_right[atom_count] = right
          atom_count += 1
          meta[0] = meta[0] + 1
        logical += 1

      maximum_d = atom_count * (atom_count + 1) / 2 ## i64
      d_ranks = i64[maximum_d]
      d_left0 = i64[maximum_d]
      d_right0 = i64[maximum_d]
      d_left1 = i64[maximum_d]
      d_right1 = i64[maximum_d]
      table_capacity = 16 ## i64
      while table_capacity < maximum_d * 4
        table_capacity *= 2
      heads = i32[table_capacity]
      links = i32[maximum_d]
      d_count = 0 ## i64

      atom = 0
      while atom < atom_count && stop == 0
        input_left = i64[2]
        input_right = i64[2]
        canonical_left = i64[2]
        canonical_right = i64[2]
        input_left[0] = atom_left[atom]
        input_right[0] = atom_right[atom]
        d_rank = fflrd_canonical(input_left,input_right,1,canonical_left,canonical_right) ## i64
        index = fflrd_register(d_rank,canonical_left[0],canonical_right[0],canonical_left[1],canonical_right[1],d_ranks,d_left0,d_right0,d_left1,d_right1,links,heads,d_count) ## i64
        if index >= 0
          d_count += 1
          meta[2] = meta[2] + 1
        atom += 1
      left_atom = 0 ## i64
      while left_atom < atom_count - 1 && stop == 0
        right_atom = left_atom + 1 ## i64
        while right_atom < atom_count && stop == 0
          meta[3] = meta[3] + 1
          input_left = i64[2]
          input_right = i64[2]
          canonical_left = i64[2]
          canonical_right = i64[2]
          input_left[0] = atom_left[left_atom]
          input_right[0] = atom_right[left_atom]
          input_left[1] = atom_left[right_atom]
          input_right[1] = atom_right[right_atom]
          d_rank = fflrd_canonical(input_left,input_right,2,canonical_left,canonical_right) ## i64
          index = fflrd_register(d_rank,canonical_left[0],canonical_right[0],canonical_left[1],canonical_right[1],d_ranks,d_left0,d_right0,d_left1,d_right1,links,heads,d_count) ## i64
          if index >= 0
            d_count += 1
          else
            meta[4] = meta[4] + 1
          right_atom += 1
        left_atom += 1

      d = 0 ## i64
      while d < d_count && stop == 0
        if d_ranks[d] >= minimum_d_rank
          if d_cap > 0 && meta[1] >= d_cap
            meta[37] = 1
            stop = 1
          else
            meta[1] = meta[1] + 1
        if d_ranks[d] >= minimum_d_rank && stop == 0
          if d_ranks[d] == 1
            meta[5] = meta[5] + 1
          if d_ranks[d] == 2
            meta[6] = meta[6] + 1
          d_left = i64[2]
          d_right = i64[2]
          d_left[0] = d_left0[d]
          d_right[0] = d_right0[d]
          d_left[1] = d_left1[d]
          d_right[1] = d_right1[d]
          deltas = i64[bucket_count]
          bucket = 0
          while bucket < bucket_count
            shifted_left = i64[63]
            shifted_right = i64[63]
            shifted_rank = fflrd_factor_bucket(us,vs,ws,rank,axis,term_bucket,bucket,d_left,d_right,d_ranks[d],shifted_left,shifted_right) ## i64
            if shifted_rank < 0
              stop = 1
            else
              deltas[bucket] = shifted_rank - base_ranks[bucket]
              if deltas[bucket] < 0
                meta[8] = meta[8] + 1
              if deltas[bucket] == 0
                meta[9] = meta[9] + 1
              if deltas[bucket] == 1
                meta[10] = meta[10] + 1
              if deltas[bucket] >= 2
                meta[11] = meta[11] + 1
            bucket += 1
          if stop == 0
            chosen = i64[bucket_count]
            choice_meta = i64[4]
            found = fflrd_find_dependency(factors,deltas,bucket_count,debt_cap,minimum_buckets,chosen,choice_meta) ## i64
            if found == 1
              meta[12] = meta[12] + 1
              if choice_meta[0] < 0
                meta[13] = meta[13] + 1
              if choice_meta[0] == 0
                meta[14] = meta[14] + 1
              if choice_meta[0] == 1
                meta[15] = meta[15] + 1
              if choice_meta[2] > meta[39]
                meta[39] = choice_meta[2]
              selected = i64[rank]
              local_u = i64[rank]
              local_v = i64[rank]
              local_w = i64[rank]
              selected_count = ffgdm_capture_choice(us,vs,ws,rank,term_bucket,chosen,selected,local_u,local_v,local_w) ## i64
              made = fflrd_materialize_choice(us,vs,ws,rank,axis,factors,term_bucket,bucket_count,chosen,d_left,d_right,d_ranks[d],local_out_u,local_out_v,local_out_w) ## i64
              if selected_count >= 2 && made >= 0
                if ffgr_replacement_exact(local_u,local_v,local_w,selected_count,local_out_u,local_out_v,local_out_w,made) == 1
                  meta[16] = meta[16] + 1
                  local_debt = made - selected_count ## i64
                  if local_debt <= debt_cap
                    meta[17] = meta[17] + 1
                    endpoint_rank = ffpb5_splice_state(source,selected,selected_count,local_out_u,local_out_v,local_out_w,made,scratch,999001 + nonce * 4099 + meta[1]) ## i64
                    if endpoint_rank > 0
                      meta[18] = meta[18] + 1
                      endpoint_density = ffw_current_bits(scratch) ## i64
                      if endpoint_rank < rank
                        meta[20] = meta[20] + 1
                      if endpoint_rank == rank
                        meta[21] = meta[21] + 1
                      if endpoint_rank > rank
                        meta[22] = meta[22] + 1
                      better = 0 ## i64
                      if meta[38] == 0 || endpoint_rank < meta[23]
                        better = 1
                      if meta[38] == 1 && endpoint_rank == meta[23] && endpoint_density < meta[24]
                        better = 1
                      if better == 1
                        if ffw_reseed_from(candidate,scratch,1000001 + nonce * 6151 + meta[1]) == endpoint_rank
                          meta[23] = endpoint_rank
                          meta[24] = endpoint_density
                          meta[27] = axis
                          meta[28] = d_ranks[d]
                          meta[29] = d_left0[d]
                          meta[30] = d_right0[d]
                          meta[31] = d_left1[d]
                          meta[32] = d_right1[d]
                          meta[33] = choice_meta[2]
                          meta[34] = selected_count
                          meta[35] = made
                          meta[36] = choice_meta[0]
                          meta[38] = 1
                    else
                      meta[19] = meta[19] + 1
        d += 1
    axis_step += 1
  if meta[38] == 1
    return meta[23]
  0

-> fflrd_search_state_min(source, d_cap, debt_cap, nonce, minimum_buckets, candidate, meta) (i64[] i64 i64 i64 i64 i64[] i64[]) i64
  fflrd_search_state_filtered(source,d_cap,debt_cap,nonce,minimum_buckets,1,candidate,meta)

-> fflrd_search_state(source, d_cap, debt_cap, nonce, candidate, meta) (i64[] i64 i64 i64 i64[] i64[]) i64
  fflrd_search_state_min(source,d_cap,debt_cap,nonce,2,candidate,meta)
