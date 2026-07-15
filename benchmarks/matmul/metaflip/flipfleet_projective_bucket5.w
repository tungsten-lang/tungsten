# Exact whole-bucket five-circuit dependency medians over GF(2).
#
# Let five distinct factors on one tensor axis form a minimal circuit
#
#     f0 ^ f1 ^ f2 ^ f3 ^ f4 = 0.
#
# Capture every live term whose factor is one of the five f_i and write the
# complementary subtotal in bucket i as the physical GF(2) matrix M_i.  For
# any matrix D,
#
#     sum_i f_i tensor (M_i ^ D) = sum_i f_i tensor M_i.
#
# Unlike flipfleet_projective_circuit5, this operator never chooses one
# representative term from a bucket.  It enumerates all 31 nonempty subset
# masks D = XOR_{j in S} M_j and minimizes sum_i rank(M_i ^ D).  Matrix ranks
# and minimal factorizations are computed directly from physical i64 factors
# with ffsm_rank_factor_matrix, so there is no packed matrix-size limit.
#
# Every local replacement is compared coefficient-for-coefficient.  The state
# search parity-compacts the splice, rebuilds a fresh worker, and runs the full
# n^6 matrix-multiplication gate before returning an endpoint.

use flipfleet_projective_circuit5

-> ffpb5_factor_index(factors, value) (i64[] i64) i64
  found = 0 - 1 ## i64
  i = 0 ## i64
  while i < 5 && found < 0
    if factors[i] == value
      found = i
    i += 1
  found

# Capture all five maximal factor buckets.  selected stores positions in the
# full scheme and bucket_ids assigns the corresponding circuit factor.
-> ffpb5_capture(us, vs, ws, rank, axis, factors, selected, bucket_ids, su, sv, sw, bucket_sizes) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  if axis < 0 || axis > 2 || factors.size() < 5 || selected.size() < rank || bucket_ids.size() < rank || su.size() < rank || sv.size() < rank || sw.size() < rank || bucket_sizes.size() < 5
    return 0 - 1
  i = 0 ## i64
  while i < 5
    bucket_sizes[i] = 0
    i += 1
  made = 0 ## i64
  position = 0 ## i64
  while position < rank
    bucket = ffpb5_factor_index(factors,ffpc5_axis_factor(us,vs,ws,position,axis)) ## i64
    if bucket >= 0
      selected[made] = position
      bucket_ids[made] = bucket
      su[made] = us[position]
      sv[made] = vs[position]
      sw[made] = ws[position]
      bucket_sizes[bucket] = bucket_sizes[bucket] + 1
      made += 1
    position += 1
  i = 0
  while i < 5
    if bucket_sizes[i] < 1
      return 0 - 1
    i += 1
  made

# Factor one physical matrix M_bucket ^ XOR_{j in subset} M_j.  A source
# outer product is present exactly when its own bucket occurs in that XOR.
-> ffpb5_factor_shifted(su, sv, sw, count, axis, bucket_ids, bucket, subset, out_left, out_right) (i64[] i64[] i64[] i64 i64 i64[] i64 i64 i64[] i64[]) i64
  if count < 1 || axis < 0 || axis > 2 || bucket < 0 || bucket >= 5 || bucket_ids.size() < count
    return 0 - 1
  lefts = i64[count]
  rights = i64[count]
  terms = 0 ## i64
  i = 0 ## i64
  while i < count
    id = bucket_ids[i] ## i64
    if id < 0 || id >= 5
      return 0 - 1
    present = 0 ## i64
    if id == bucket
      present = present ^ 1
    if ((subset >> id) & 1) != 0
      present = present ^ 1
    if present != 0
      lefts[terms] = ffpc5_axis_left(su,sv,sw,i,axis)
      rights[terms] = ffpc5_axis_right(su,sv,sw,i,axis)
      terms += 1
    i += 1
  ffsm_rank_factor_matrix(lefts,rights,terms,out_left,out_right)

# Exact rank of D itself.  A zero result means that a nonempty subset mask
# represents the zero matrix and therefore cannot change the decomposition.
-> ffpb5_factor_d(su, sv, sw, count, axis, bucket_ids, subset, out_left, out_right) (i64[] i64[] i64[] i64 i64 i64[] i64 i64[] i64[]) i64
  if count < 1 || axis < 0 || axis > 2 || bucket_ids.size() < count
    return 0 - 1
  lefts = i64[count]
  rights = i64[count]
  terms = 0 ## i64
  i = 0 ## i64
  while i < count
    id = bucket_ids[i] ## i64
    if id < 0 || id >= 5
      return 0 - 1
    if ((subset >> id) & 1) != 0
      lefts[terms] = ffpc5_axis_left(su,sv,sw,i,axis)
      rights[terms] = ffpc5_axis_right(su,sv,sw,i,axis)
      terms += 1
    i += 1
  ffsm_rank_factor_matrix(lefts,rights,terms,out_left,out_right)

-> ffpb5_objective(su, vs, ws, count, axis, bucket_ids, subset) (i64[] i64[] i64[] i64 i64 i64[] i64) i64
  objective = 0 ## i64
  bucket = 0 ## i64
  while bucket < 5
    factor_left = i64[63]
    factor_right = i64[63]
    matrix_rank = ffpb5_factor_shifted(su,vs,ws,count,axis,bucket_ids,bucket,subset,factor_left,factor_right) ## i64
    if matrix_rank < 0
      return 0 - 1
    objective += matrix_rank
    bucket += 1
  objective

# Materialize all five minimally factored shifted buckets.  The caller owns
# local/full exact gates; this helper is purely the physical factorization.
-> ffpb5_materialize(su, sv, sw, count, axis, factors, bucket_ids, subset, out_u, out_v, out_w) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64 i64[] i64[] i64[]) i64
  if factors.size() < 5
    return 0 - 1
  capacity = out_u.size() ## i64
  if out_v.size() < capacity
    capacity = out_v.size()
  if out_w.size() < capacity
    capacity = out_w.size()
  made = 0 ## i64
  bucket = 0 ## i64
  while bucket < 5
    factor_left = i64[63]
    factor_right = i64[63]
    matrix_rank = ffpb5_factor_shifted(su,sv,sw,count,axis,bucket_ids,bucket,subset,factor_left,factor_right) ## i64
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

# Optimize one already captured whole-bucket circuit.
#
# meta:
#   0 source terms, 1..5 bucket sizes, 6 subset masks, 7 nonzero D,
#   8 ordinary bucket rank, 9 best shifted rank, 10 best subset,
#   11 best D rank, 12 local exact, 13 same set, 14 term-set distance,
#   15 gain versus source representation, 16 gain versus ordinary rank,
#   17 initialized.
-> ffpb5_optimize_circuit(su, sv, sw, count, axis, factors, bucket_ids, bucket_sizes, out_u, out_v, out_w, meta) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  if count < 5 || factors.size() < 5 || bucket_ids.size() < count || bucket_sizes.size() < 5 || meta.size() < 18
    return 0 - 1
  i = 0 ## i64
  while i < 18
    meta[i] = 0
    i += 1
  meta[0] = count
  i = 0
  while i < 5
    meta[1 + i] = bucket_sizes[i]
    i += 1
  ordinary = ffpb5_objective(su,sv,sw,count,axis,bucket_ids,0) ## i64
  if ordinary < 0
    return 0 - 1
  meta[8] = ordinary
  best_rank = 1000 ## i64
  best_subset = 0 ## i64
  best_d_rank = 0 ## i64
  subset = 1 ## i64
  while subset < 32
    meta[6] = meta[6] + 1
    d_left = i64[63]
    d_right = i64[63]
    d_rank = ffpb5_factor_d(su,sv,sw,count,axis,bucket_ids,subset,d_left,d_right) ## i64
    if d_rank < 0
      return 0 - 1
    if d_rank > 0
      meta[7] = meta[7] + 1
      objective = ffpb5_objective(su,sv,sw,count,axis,bucket_ids,subset) ## i64
      if objective < 0
        return 0 - 1
      if meta[17] == 0 || objective < best_rank || (objective == best_rank && d_rank > best_d_rank)
        best_rank = objective
        best_subset = subset
        best_d_rank = d_rank
        meta[17] = 1
    subset += 1
  if meta[17] == 0
    return 0 - 1
  made = ffpb5_materialize(su,sv,sw,count,axis,factors,bucket_ids,best_subset,out_u,out_v,out_w) ## i64
  if made < 0 || made != best_rank
    return 0 - 1
  exact = ffgr_replacement_exact(su,sv,sw,count,out_u,out_v,out_w,made) ## i64
  if exact != 1
    return 0 - 1
  meta[9] = best_rank
  meta[10] = best_subset
  meta[11] = best_d_rank
  meta[12] = exact
  meta[13] = ffmp_same_term_set(su,sv,sw,count,out_u,out_v,out_w,made)
  meta[14] = ffmp_term_set_distance(su,sv,sw,count,out_u,out_v,out_w,made)
  meta[15] = count - best_rank
  meta[16] = ordinary - best_rank
  made

# Parity-compact a local replacement (including the valid empty replacement),
# reconstruct a fresh worker, and run the exhaustive n^6 gate.
-> ffpb5_splice_state(source, selected, selected_count, out_u, out_v, out_w, out_count, candidate, seed) (i64[] i64[] i64 i64[] i64[] i64[] i64 i64[] i64) i64
  if ffw_valid(source) != 1 || selected_count < 1 || out_count < 0
    return 0
  rank = source[6] ## i64
  capacity = source[4] ## i64
  if selected.size() < selected_count || out_u.size() < out_count || out_v.size() < out_count || out_w.size() < out_count
    return 0
  source_u = i64[capacity]
  source_v = i64[capacity]
  source_w = i64[capacity]
  if ffw_export_current(source,source_u,source_v,source_w) != rank
    return 0
  local_u = i64[selected_count]
  local_v = i64[selected_count]
  local_w = i64[selected_count]
  i = 0 ## i64
  while i < selected_count
    if selected[i] < 0 || selected[i] >= rank
      return 0
    j = i + 1 ## i64
    while j < selected_count
      if selected[i] == selected[j]
        return 0
      j += 1
    local_u[i] = source_u[selected[i]]
    local_v[i] = source_v[selected[i]]
    local_w[i] = source_w[selected[i]]
    i += 1
  if ffgr_replacement_exact(local_u,local_v,local_w,selected_count,out_u,out_v,out_w,out_count) != 1
    return 0
  made_u = i64[capacity]
  made_v = i64[capacity]
  made_w = i64[capacity]
  made = 0 ## i64
  position = 0 ## i64
  while position < rank
    if ffmp_position_selected(selected,selected_count,position) == 0
      made_u[made] = source_u[position]
      made_v[made] = source_v[position]
      made_w[made] = source_w[position]
      made += 1
    position += 1
  i = 0
  while i < out_count
    made = ffmp_toggle_term(made_u,made_v,made_w,made,capacity,out_u[i],out_v[i],out_w[i])
    if made < 1
      return 0
    i += 1
  if made < 1
    return 0
  loaded = ffw_init_terms_cap(candidate,made_u,made_v,made_w,made,source[2],capacity,seed,0,1,1,1) ## i64
  if loaded == made && ffw_verify_current_exact(candidate,source[2]) == 1
    return made
  0

# Enumerate minimal five-circuits among distinct factor buckets.  A positive
# circuit_cap bounds circuits globally; zero is complete.  Only endpoints at
# most debt_cap above the source are subjected to the full n^6 gate.
#
# meta:
#   0 four-tuples, 1 circuits, 2 captured terms, 3 subset masks,
#   4 nonzero D, 5 local exact, 6 debt-admitted, 7 full gates,
#   8 full failures, 9 rank drops, 10 neutral, 11 positive shoulders,
#   12 best rank, 13 best density, 14 source rank, 15 source density,
#   16 cap reached, 17 best initialized, 18 best axis,
#   19 best local source, 20 best local replacement, 21 best subset,
#   22 largest bucket, 23 distinct factors across axes, 24 minimum local debt,
#   25 local drops, 26 local neutral, 27 local +1, 28 local +2,
#   29 local debt >=3.
-> ffpb5_search_state(source, circuit_cap, debt_cap, nonce, candidate, meta) (i64[] i64 i64 i64 i64[] i64[]) i64
  if ffw_valid(source) != 1 || circuit_cap < 0 || debt_cap < 0 || meta.size() < 30
    return 0
  i = 0 ## i64
  while i < 30
    meta[i] = 0
    i += 1
  meta[24] = 1000
  rank = source[6] ## i64
  capacity = source[4] ## i64
  if rank < 5
    return 0
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  if ffw_export_current(source,us,vs,ws) != rank
    return 0
  meta[14] = rank
  meta[15] = ffw_current_bits(source)
  scratch = i64[ffw_state_size(capacity)]
  local_capacity = 315 ## i64
  local_out_u = i64[local_capacity]
  local_out_v = i64[local_capacity]
  local_out_w = i64[local_capacity]
  offset = nonce % rank ## i64
  stop = 0 ## i64
  axis_step = 0 ## i64
  while axis_step < 3 && stop == 0
    axis = (nonce + axis_step) % 3 ## i64
    unique = i64[rank]
    unique_count = 0 ## i64
    logical = 0 ## i64
    while logical < rank
      position = (logical + offset + axis * 17) % rank ## i64
      factor = ffpc5_axis_factor(us,vs,ws,position,axis) ## i64
      seen = 0 ## i64
      u = 0 ## i64
      while u < unique_count && seen == 0
        if unique[u] == factor
          seen = 1
        u += 1
      if seen == 0
        unique[unique_count] = factor
        unique_count += 1
      logical += 1
    meta[23] = meta[23] + unique_count
    table_capacity = 16 ## i64
    while table_capacity < unique_count * 4
      table_capacity *= 2
    heads = i32[table_capacity]
    links = i32[unique_count]
    u = 0
    while u < unique_count
      slot = ffcis_hash(unique[u],0,0) & (table_capacity - 1) ## i64
      links[u] = heads[slot]
      heads[slot] = u + 1
      u += 1
    a = 0 ## i64
    while a < unique_count - 4 && stop == 0
      b = a + 1 ## i64
      while b < unique_count - 3 && stop == 0
        c = b + 1 ## i64
        while c < unique_count - 2 && stop == 0
          d = c + 1 ## i64
          while d < unique_count - 1 && stop == 0
            meta[0] = meta[0] + 1
            fa = unique[a] ## i64
            fb = unique[b] ## i64
            fc = unique[c] ## i64
            fd = unique[d] ## i64
            if ffpc5_independent4(fa,fb,fc,fd) == 1
              target = fa ^ fb ^ fc ^ fd ## i64
              slot = ffcis_hash(target,0,0) & (table_capacity - 1) ## i64
              entry = heads[slot] ## i64
              while entry != 0 && stop == 0
                e = entry - 1 ## i64
                if e > d && unique[e] == target
                  meta[1] = meta[1] + 1
                  factors = i64[5]
                  factors[0] = fa
                  factors[1] = fb
                  factors[2] = fc
                  factors[3] = fd
                  factors[4] = target
                  selected = i64[rank]
                  bucket_ids = i64[rank]
                  su = i64[rank]
                  sv = i64[rank]
                  sw = i64[rank]
                  bucket_sizes = i64[5]
                  captured = ffpb5_capture(us,vs,ws,rank,axis,factors,selected,bucket_ids,su,sv,sw,bucket_sizes) ## i64
                  if captured >= 5
                    meta[2] = meta[2] + captured
                    bucket = 0 ## i64
                    while bucket < 5
                      if bucket_sizes[bucket] > meta[22]
                        meta[22] = bucket_sizes[bucket]
                      bucket += 1
                    local_meta = i64[18]
                    made = ffpb5_optimize_circuit(su,sv,sw,captured,axis,factors,bucket_ids,bucket_sizes,local_out_u,local_out_v,local_out_w,local_meta) ## i64
                    meta[3] = meta[3] + local_meta[6]
                    meta[4] = meta[4] + local_meta[7]
                    if made >= 0 && local_meta[12] == 1
                      meta[5] = meta[5] + 1
                      local_debt = made - captured ## i64
                      if local_debt < meta[24]
                        meta[24] = local_debt
                      if local_debt < 0
                        meta[25] = meta[25] + 1
                      if local_debt == 0
                        meta[26] = meta[26] + 1
                      if local_debt == 1
                        meta[27] = meta[27] + 1
                      if local_debt == 2
                        meta[28] = meta[28] + 1
                      if local_debt >= 3
                        meta[29] = meta[29] + 1
                      if local_debt <= debt_cap
                        meta[6] = meta[6] + 1
                        endpoint_rank = ffpb5_splice_state(source,selected,captured,local_out_u,local_out_v,local_out_w,made,scratch,980001 + nonce * 4099 + meta[1]) ## i64
                        if endpoint_rank > 0
                          meta[7] = meta[7] + 1
                          endpoint_density = ffw_current_bits(scratch) ## i64
                          if endpoint_rank < rank
                            meta[9] = meta[9] + 1
                          if endpoint_rank == rank
                            meta[10] = meta[10] + 1
                          if endpoint_rank > rank
                            meta[11] = meta[11] + 1
                          better = 0 ## i64
                          if meta[17] == 0 || endpoint_rank < meta[12]
                            better = 1
                          if meta[17] == 1 && endpoint_rank == meta[12] && endpoint_density < meta[13]
                            better = 1
                          if better == 1
                            if ffw_reseed_from(candidate,scratch,981001 + nonce * 6151 + meta[1]) == endpoint_rank
                              meta[12] = endpoint_rank
                              meta[13] = endpoint_density
                              meta[17] = 1
                              meta[18] = axis
                              meta[19] = captured
                              meta[20] = made
                              meta[21] = local_meta[10]
                        else
                          meta[8] = meta[8] + 1
                  if circuit_cap > 0 && meta[1] >= circuit_cap
                    meta[16] = 1
                    stop = 1
                entry = links[e]
            d += 1
          c += 1
        b += 1
      a += 1
    axis_step += 1
  if meta[17] == 1
    return meta[12]
  0
