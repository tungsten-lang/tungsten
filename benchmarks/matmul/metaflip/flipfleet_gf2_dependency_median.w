# Polynomial exact GF(2) dependency medians over arbitrary factor buckets.
#
# Fix an axis and write the tensor subtotal at each distinct factor f_i as a
# physical complementary matrix M_i.  For a rank-one matrix D taken from a
# live complementary term, define
#
#     delta_i = rank(M_i ^ D) - rank(M_i).
#
# A rank-one update has delta_i in {-1,0,+1}.  Toggling D into any buckets S
# with XOR_{i in S} f_i = 0 preserves the tensor and changes the minimally
# factored local rank by sum_{i in S} delta_i.
#
# For every negative-delta anchor, this operator builds a GF(2) elimination
# basis from every other nonpositive bucket.  If the anchor factor is in that
# span, the recovered dependency is a direct drop.  It then allows one +1
# bucket (at most neutral) or two +1 buckets (at most +1), rebuilding the same
# nonpositive basis only once per anchor.  This finds arbitrary-size zero-sum
# dependencies in polynomial time and strictly subsumes a fixed circuit-size
# scan for this rank-one D family.
#
# All matrix ranks/factorizations operate on physical i64 factors through
# ffsm_rank_factor_matrix.  Every materialized dependency receives an exact
# coefficient-level local gate, parity-compacted full splice, and exhaustive
# n^6 matrix-multiplication gate.

use flipfleet_projective_bucket5

-> ffgdm_factor_index(factors, count, value) (i64[] i64 i64) i64
  found = 0 - 1 ## i64
  i = 0 ## i64
  while i < count && found < 0
    if factors[i] == value
      found = i
    i += 1
  found

# Group all terms by their fixed factor.  Factor insertion order is rotated so
# bounded D scans get a deterministic nonce-dependent prefix.
-> ffgdm_group_axis(us, vs, ws, rank, axis, offset, factors, term_bucket, bucket_sizes) (i64[] i64[] i64[] i64 i64 i64 i64[] i64[] i64[]) i64
  if rank < 1 || axis < 0 || axis > 2 || factors.size() < rank || term_bucket.size() < rank || bucket_sizes.size() < rank
    return 0
  i = 0 ## i64
  while i < rank
    bucket_sizes[i] = 0
    i += 1
  bucket_count = 0 ## i64
  logical = 0 ## i64
  while logical < rank
    position = (logical + offset) % rank ## i64
    factor = ffpc5_axis_factor(us,vs,ws,position,axis) ## i64
    bucket = ffgdm_factor_index(factors,bucket_count,factor) ## i64
    if bucket < 0
      bucket = bucket_count
      factors[bucket_count] = factor
      bucket_count += 1
    logical += 1
  position = 0 ## i64
  while position < rank
    factor = ffpc5_axis_factor(us,vs,ws,position,axis) ## i64
    bucket = ffgdm_factor_index(factors,bucket_count,factor) ## i64
    if bucket < 0
      return 0
    term_bucket[position] = bucket
    bucket_sizes[bucket] = bucket_sizes[bucket] + 1
    position += 1
  bucket_count

# Minimal factorization of M_bucket, or M_bucket ^ (d_left tensor d_right)
# when include_d is nonzero.
-> ffgdm_factor_bucket(us, vs, ws, rank, axis, term_bucket, bucket, include_d, d_left, d_right, out_left, out_right) (i64[] i64[] i64[] i64 i64 i64[] i64 i64 i64 i64 i64[] i64[]) i64
  if rank < 1 || axis < 0 || axis > 2 || term_bucket.size() < rank || bucket < 0
    return 0 - 1
  if include_d != 0 && (d_left <= 0 || d_right <= 0)
    return 0 - 1
  lefts = i64[rank + 1]
  rights = i64[rank + 1]
  count = 0 ## i64
  position = 0 ## i64
  while position < rank
    if term_bucket[position] == bucket
      lefts[count] = ffpc5_axis_left(us,vs,ws,position,axis)
      rights[count] = ffpc5_axis_right(us,vs,ws,position,axis)
      count += 1
    position += 1
  if include_d != 0
    lefts[count] = d_left
    rights[count] = d_right
    count += 1
  ffsm_rank_factor_matrix(lefts,rights,count,out_left,out_right)

# Build a coordinate-recovering elimination basis from all nonpositive
# buckets except the selected negative anchor.
-> ffgdm_build_basis(factors, deltas, bucket_count, anchor, pivots, pivot_coordinates, basis_buckets) (i64[] i64[] i64 i64 i64[] i64[] i64[]) i64
  if factors.size() < bucket_count || deltas.size() < bucket_count || pivots.size() < 63 || pivot_coordinates.size() < 63 || basis_buckets.size() < 63
    return 0 - 1
  bit = 0 ## i64
  while bit < 63
    pivots[bit] = 0
    pivot_coordinates[bit] = 0
    basis_buckets[bit] = 0 - 1
    bit += 1
  basis_rank = 0 ## i64
  bucket = 0 ## i64
  while bucket < bucket_count
    if bucket != anchor && deltas[bucket] <= 0
      value = factors[bucket] ## i64
      coordinates = 0 ## i64
      bit = 62
      while bit >= 0 && value != 0
        if ((value >> bit) & 1) != 0
          if pivots[bit] != 0
            value = value ^ pivots[bit]
            coordinates = coordinates ^ pivot_coordinates[bit]
          else
            if basis_rank >= 62
              return 0 - 1
            pivots[bit] = value
            pivot_coordinates[bit] = coordinates ^ (1 << basis_rank)
            basis_buckets[basis_rank] = bucket
            basis_rank += 1
            value = 0
        bit -= 1
    bucket += 1
  basis_rank

-> ffgdm_solve_basis(target, pivots, pivot_coordinates) (i64 i64[] i64[]) i64
  if target < 0 || pivots.size() < 63 || pivot_coordinates.size() < 63
    return 0 - 1
  value = target ## i64
  coordinates = 0 ## i64
  bit = 62 ## i64
  while bit >= 0 && value != 0
    if ((value >> bit) & 1) != 0
      if pivots[bit] == 0
        return 0 - 1
      value = value ^ pivots[bit]
      coordinates = coordinates ^ pivot_coordinates[bit]
    bit -= 1
  coordinates

-> ffgdm_fill_choice(factors, deltas, bucket_count, anchor, positive_a, positive_b, coordinates, basis_buckets, chosen, choice_meta) (i64[] i64[] i64 i64 i64 i64 i64 i64[] i64[] i64[]) i64
  if chosen.size() < bucket_count || choice_meta.size() < 4
    return 0
  bucket = 0 ## i64
  while bucket < bucket_count
    chosen[bucket] = 0
    bucket += 1
  chosen[anchor] = 1
  if positive_a >= 0
    chosen[positive_a] = 1
  if positive_b >= 0
    chosen[positive_b] = 1
  bit = 0 ## i64
  while (coordinates >> bit) != 0
    if ((coordinates >> bit) & 1) != 0
      bucket = basis_buckets[bit] ## i64
      if bucket < 0 || bucket >= bucket_count
        return 0
      chosen[bucket] = 1
    bit += 1
  factor_xor = 0 ## i64
  predicted_delta = 0 ## i64
  selected_count = 0 ## i64
  bucket = 0
  while bucket < bucket_count
    if chosen[bucket] != 0
      factor_xor = factor_xor ^ factors[bucket]
      predicted_delta += deltas[bucket]
      selected_count += 1
    bucket += 1
  if factor_xor != 0 || selected_count < 2
    return 0
  positive_count = 0 ## i64
  if positive_a >= 0
    positive_count += 1
  if positive_b >= 0
    positive_count += 1
  choice_meta[0] = predicted_delta
  choice_meta[1] = positive_count
  choice_meta[2] = selected_count
  choice_meta[3] = coordinates
  1

# Find the lowest-debt dependency for one D, optionally filtering out short
# dependencies already covered by fixed-circuit operators.
-> ffgdm_find_dependency_min(factors, deltas, bucket_count, positive_limit, minimum_buckets, chosen, choice_meta) (i64[] i64[] i64 i64 i64 i64[] i64[]) i64
  if factors.size() < bucket_count || deltas.size() < bucket_count || chosen.size() < bucket_count || choice_meta.size() < 4 || minimum_buckets < 2
    return 0
  # Exhaust every anchor for a lower-debt family before opening the next
  # family.  Otherwise an early two-positive circuit could hide a direct drop
  # rooted at a later negative bucket.
  positive_count = 0 ## i64
  while positive_count <= positive_limit
    anchor = 0 ## i64
    while anchor < bucket_count
      if deltas[anchor] < 0
        pivots = i64[63]
        pivot_coordinates = i64[63]
        basis_buckets = i64[63]
        basis_rank = ffgdm_build_basis(factors,deltas,bucket_count,anchor,pivots,pivot_coordinates,basis_buckets) ## i64
        if basis_rank >= 0 && positive_count == 0
          coordinates = ffgdm_solve_basis(factors[anchor],pivots,pivot_coordinates) ## i64
          if coordinates >= 0
            if ffgdm_fill_choice(factors,deltas,bucket_count,anchor,0-1,0-1,coordinates,basis_buckets,chosen,choice_meta) == 1
              if choice_meta[2] >= minimum_buckets
                return 1
        if basis_rank >= 0 && positive_count == 1
          positive = 0 ## i64
          while positive < bucket_count
            if deltas[positive] == 1
              coordinates = ffgdm_solve_basis(factors[anchor] ^ factors[positive],pivots,pivot_coordinates) ## i64
              if coordinates >= 0
                if ffgdm_fill_choice(factors,deltas,bucket_count,anchor,positive,0-1,coordinates,basis_buckets,chosen,choice_meta) == 1
                  if choice_meta[2] >= minimum_buckets
                    return 1
            positive += 1
        if basis_rank >= 0 && positive_count == 2
          positive = 0
          while positive < bucket_count - 1
            if deltas[positive] == 1
              second = positive + 1 ## i64
              while second < bucket_count
                if deltas[second] == 1
                  target = factors[anchor] ^ factors[positive] ^ factors[second] ## i64
                  coordinates = ffgdm_solve_basis(target,pivots,pivot_coordinates) ## i64
                  if coordinates >= 0
                    if ffgdm_fill_choice(factors,deltas,bucket_count,anchor,positive,second,coordinates,basis_buckets,chosen,choice_meta) == 1
                      if choice_meta[2] >= minimum_buckets
                        return 1
                second += 1
            positive += 1
      anchor += 1
    positive_count += 1
  0

-> ffgdm_find_dependency(factors, deltas, bucket_count, positive_limit, chosen, choice_meta) (i64[] i64[] i64 i64 i64[] i64[]) i64
  ffgdm_find_dependency_min(factors,deltas,bucket_count,positive_limit,2,chosen,choice_meta)

# Capture all terms in the chosen buckets.
-> ffgdm_capture_choice(us, vs, ws, rank, term_bucket, chosen, selected, su, sv, sw) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64[] i64[]) i64
  if term_bucket.size() < rank || selected.size() < rank || su.size() < rank || sv.size() < rank || sw.size() < rank
    return 0
  made = 0 ## i64
  position = 0 ## i64
  while position < rank
    bucket = term_bucket[position] ## i64
    if bucket >= 0 && bucket < chosen.size()
      if chosen[bucket] != 0
        selected[made] = position
        su[made] = us[position]
        sv[made] = vs[position]
        sw[made] = ws[position]
        made += 1
    position += 1
  made

-> ffgdm_materialize_choice(us, vs, ws, rank, axis, factors, term_bucket, bucket_count, chosen, d_left, d_right, out_u, out_v, out_w) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64 i64[] i64 i64 i64[] i64[] i64[]) i64
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
      matrix_rank = ffgdm_factor_bucket(us,vs,ws,rank,axis,term_bucket,bucket,1,d_left,d_right,factor_left,factor_right) ## i64
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

# Search all unique rank-one D values from live complementary terms.  A
# positive d_cap bounds tested D values globally; zero is complete.
#
# meta:
#   0 live D terms, 1 unique D tested, 2 buckets visited,
#   3/4/5 negative/zero/positive deltas, 6 basis attempts,
#   7 dependencies, 8 direct, 9 one-positive, 10 two-positive,
#   11 local exact, 12 debt-admitted, 13 full gates, 14 failures,
#   15 drops, 16 neutral, 17 shoulders, 18 best rank, 19 best density,
#   20 source rank, 21 source density, 22 best axis, 23/24 best D,
#   25 best dependency buckets, 26/27 best local old/new,
#   28 best predicted delta, 29 D cap reached, 30 best initialized,
#   31 maximum dependency buckets.
-> ffgdm_search_state_min(source, d_cap, debt_cap, nonce, minimum_buckets, candidate, meta) (i64[] i64 i64 i64 i64 i64[] i64[]) i64
  if ffw_valid(source) != 1 || d_cap < 0 || debt_cap < 0 || minimum_buckets < 2 || meta.size() < 32
    return 0
  i = 0 ## i64
  while i < 32
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
  meta[20] = rank
  meta[21] = ffw_current_bits(source)
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
      meta[2] = meta[2] + bucket_count
      base_ranks = i64[bucket_count]
      bucket = 0 ## i64
      while bucket < bucket_count
        base_left = i64[63]
        base_right = i64[63]
        base_ranks[bucket] = ffgdm_factor_bucket(us,vs,ws,rank,axis,term_bucket,bucket,0,0,0,base_left,base_right)
        if base_ranks[bucket] < 0
          stop = 1
        bucket += 1
      d_lefts = i64[rank]
      d_rights = i64[rank]
      d_count = 0 ## i64
      logical = 0 ## i64
      while logical < rank && stop == 0
        position = (logical + offset) % rank ## i64
        meta[0] = meta[0] + 1
        d_left = ffpc5_axis_left(us,vs,ws,position,axis) ## i64
        d_right = ffpc5_axis_right(us,vs,ws,position,axis) ## i64
        duplicate = 0 ## i64
        d = 0 ## i64
        while d < d_count && duplicate == 0
          if d_lefts[d] == d_left && d_rights[d] == d_right
            duplicate = 1
          d += 1
        if duplicate == 0
          d_lefts[d_count] = d_left
          d_rights[d_count] = d_right
          d_count += 1
          meta[1] = meta[1] + 1
          deltas = i64[bucket_count]
          bucket = 0
          while bucket < bucket_count
            shifted_left = i64[63]
            shifted_right = i64[63]
            shifted_rank = ffgdm_factor_bucket(us,vs,ws,rank,axis,term_bucket,bucket,1,d_left,d_right,shifted_left,shifted_right) ## i64
            if shifted_rank < 0
              stop = 1
            else
              deltas[bucket] = shifted_rank - base_ranks[bucket]
              if deltas[bucket] < 0
                meta[3] = meta[3] + 1
              if deltas[bucket] == 0
                meta[4] = meta[4] + 1
              if deltas[bucket] > 0
                meta[5] = meta[5] + 1
            bucket += 1
          if stop == 0
            chosen = i64[bucket_count]
            choice_meta = i64[4]
            meta[6] = meta[6] + 1
            found = ffgdm_find_dependency_min(factors,deltas,bucket_count,2,minimum_buckets,chosen,choice_meta) ## i64
            if found == 1
              meta[7] = meta[7] + 1
              if choice_meta[1] == 0
                meta[8] = meta[8] + 1
              if choice_meta[1] == 1
                meta[9] = meta[9] + 1
              if choice_meta[1] == 2
                meta[10] = meta[10] + 1
              if choice_meta[2] > meta[31]
                meta[31] = choice_meta[2]
              selected = i64[rank]
              local_u = i64[rank]
              local_v = i64[rank]
              local_w = i64[rank]
              selected_count = ffgdm_capture_choice(us,vs,ws,rank,term_bucket,chosen,selected,local_u,local_v,local_w) ## i64
              made = ffgdm_materialize_choice(us,vs,ws,rank,axis,factors,term_bucket,bucket_count,chosen,d_left,d_right,local_out_u,local_out_v,local_out_w) ## i64
              if selected_count >= 2 && made >= 0
                if ffgr_replacement_exact(local_u,local_v,local_w,selected_count,local_out_u,local_out_v,local_out_w,made) == 1
                  meta[11] = meta[11] + 1
                  local_debt = made - selected_count ## i64
                  if local_debt <= debt_cap
                    meta[12] = meta[12] + 1
                    endpoint_rank = ffpb5_splice_state(source,selected,selected_count,local_out_u,local_out_v,local_out_w,made,scratch,990001 + nonce * 4099 + meta[1]) ## i64
                    if endpoint_rank > 0
                      meta[13] = meta[13] + 1
                      endpoint_density = ffw_current_bits(scratch) ## i64
                      if endpoint_rank < rank
                        meta[15] = meta[15] + 1
                      if endpoint_rank == rank
                        meta[16] = meta[16] + 1
                      if endpoint_rank > rank
                        meta[17] = meta[17] + 1
                      better = 0 ## i64
                      if meta[30] == 0 || endpoint_rank < meta[18]
                        better = 1
                      if meta[30] == 1 && endpoint_rank == meta[18] && endpoint_density < meta[19]
                        better = 1
                      if better == 1
                        if ffw_reseed_from(candidate,scratch,991001 + nonce * 6151 + meta[1]) == endpoint_rank
                          meta[18] = endpoint_rank
                          meta[19] = endpoint_density
                          meta[22] = axis
                          meta[23] = d_left
                          meta[24] = d_right
                          meta[25] = choice_meta[2]
                          meta[26] = selected_count
                          meta[27] = made
                          meta[28] = choice_meta[0]
                          meta[30] = 1
                    else
                      meta[14] = meta[14] + 1
          if d_cap > 0 && meta[1] >= d_cap
            meta[29] = 1
            stop = 1
        logical += 1
    axis_step += 1
  if meta[30] == 1
    return meta[18]
  0

-> ffgdm_search_state(source, d_cap, debt_cap, nonce, candidate, meta) (i64[] i64 i64 i64 i64[] i64[]) i64
  ffgdm_search_state_min(source,d_cap,debt_cap,nonce,2,candidate,meta)
