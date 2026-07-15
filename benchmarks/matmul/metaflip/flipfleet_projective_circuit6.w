# Exact six-bucket dependency medians over GF(2).
#
# If six distinct factors f_i form a minimal linear circuit
#
#     f0 ^ f1 ^ f2 ^ f3 ^ f4 ^ f5 = 0,
#
# then XORing the same rank-one matrix D into the six corresponding matrix
# slices preserves the complete tensor.  Each old slice contribution is rank
# one, and M_i ^ D has rank 0, 1, or 2.  This is the rank-five projective
# circuit immediately beyond flipfleet_projective_circuit5.
#
# Six-circuits are found by hash-matching two triples.  For sorted logical
# positions a<b<c<d<e<f, the canonical split (a,b,c)|(d,e,f) has equal XORs.
# Requiring c<d consequently reports every six-set exactly once, without an
# O(rank^5) quintuple scan.  A nonzero triple_cap bounds stored/scanned triples
# per axis; zero is complete.  Admission remains exact: callers rebuild and
# exhaustively verify the full matrix-multiplication tensor.

use flipfleet_circuit_image_search3

-> ffpc6_axis_factor(us, vs, ws, position, axis) (i64[] i64[] i64[] i64 i64) i64
  if axis == 0
    return us[position]
  if axis == 1
    return vs[position]
  if axis == 2
    return ws[position]
  0

-> ffpc6_axis_left(us, vs, ws, position, axis) (i64[] i64[] i64[] i64 i64) i64
  if axis == 0
    return vs[position]
  return us[position]

-> ffpc6_axis_right(us, vs, ws, position, axis) (i64[] i64[] i64[] i64 i64) i64
  if axis == 2
    return vs[position]
  return ws[position]

# In a six-term zero-sum dependency, independence of any five factors is
# equivalent to minimality.  The subset test is only reached after a triple
# XOR collision, so its small fixed cost stays off the scan's hot path.
-> ffpc6_independent5(a, b, c, d, e) (i64 i64 i64 i64 i64) i64
  values = i64[5]
  values[0] = a
  values[1] = b
  values[2] = c
  values[3] = d
  values[4] = e
  subset = 1 ## i64
  while subset < 32
    sum = 0 ## i64
    bit = 0 ## i64
    while bit < 5
      if ((subset >> bit) & 1) != 0
        sum = sum ^ values[bit]
      bit += 1
    if sum == 0
      return 0
    subset += 1
  1

-> ffpc6_toggle_axis(out_u, out_v, out_w, count, capacity, axis, factor, left, right) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64) i64
  if axis == 0
    return ffcis3_toggle(out_u,out_v,out_w,count,capacity,factor,left,right)
  if axis == 1
    return ffcis3_toggle(out_u,out_v,out_w,count,capacity,left,factor,right)
  if axis == 2
    return ffcis3_toggle(out_u,out_v,out_w,count,capacity,left,right,factor)
  0 - 1

# Replace the six selected rank-one slice matrices by M_i ^ (y tensor z).
-> ffpc6_build_endpoint(us, vs, ws, rank, axis, selected, y, z, out_u, out_v, out_w) (i64[] i64[] i64[] i64 i64 i64[] i64 i64 i64[] i64[] i64[]) i64
  if rank < 6 || axis < 0 || axis > 2 || selected.size() < 6 || out_u.size() < rank + 6 || out_v.size() < rank + 6 || out_w.size() < rank + 6 || y == 0 || z == 0
    return 0 - 1
  count = 0 ## i64
  position = 0 ## i64
  while position < rank
    count = ffcis3_toggle(out_u,out_v,out_w,count,out_u.size(),us[position],vs[position],ws[position])
    if count < 0
      return 0 - 1
    position += 1
  item = 0 ## i64
  while item < 6
    position = selected[item] ## i64
    if position < 0 || position >= rank
      return 0 - 1
    factor = ffpc6_axis_factor(us,vs,ws,position,axis) ## i64
    left = ffpc6_axis_left(us,vs,ws,position,axis) ## i64
    right = ffpc6_axis_right(us,vs,ws,position,axis) ## i64
    count = ffpc6_toggle_axis(out_u,out_v,out_w,count,out_u.size(),axis,factor,left,right)
    if count < 0
      return 0 - 1
    if left != y || right != z
      if left == y
        count = ffpc6_toggle_axis(out_u,out_v,out_w,count,out_u.size(),axis,factor,left,right ^ z)
      else
        if right == z
          count = ffpc6_toggle_axis(out_u,out_v,out_w,count,out_u.size(),axis,factor,left ^ y,right)
        else
          count = ffpc6_toggle_axis(out_u,out_v,out_w,count,out_u.size(),axis,factor,left,right)
          if count >= 0
            count = ffpc6_toggle_axis(out_u,out_v,out_w,count,out_u.size(),axis,factor,y,z)
      if count < 0
        return 0 - 1
    item += 1
  count

-> ffpc6_local_cost(us, vs, ws, selected, axis, y, z) (i64[] i64[] i64[] i64[] i64 i64 i64) i64
  cost = 0 ## i64
  item = 0 ## i64
  while item < 6
    position = selected[item] ## i64
    left = ffpc6_axis_left(us,vs,ws,position,axis) ## i64
    right = ffpc6_axis_right(us,vs,ws,position,axis) ## i64
    if left == y && right == z
      add = 0 ## i64
    else
      if left == y || right == z
        add = 1 ## i64
      else
        add = 2 ## i64
    cost += add
    item += 1
  cost

-> ffpc6_changed(us, vs, ws, rank, table, candidate_u, candidate_v, candidate_w, candidate_rank) (i64[] i64[] i64[] i64 i32[] i64[] i64[] i64[] i64) i64
  if candidate_rank != rank
    return 1
  i = 0 ## i64
  while i < candidate_rank
    if ffcis_lookup(us,vs,ws,table,candidate_u[i],candidate_v[i],candidate_w[i]) < 0
      return 1
    i += 1
  0

# A nonzero triple_cap bounds triples per axis; zero is exhaustive.  A nonzero
# circuit_cap bounds minimal circuits across all axes.  Nonce rotates axes and
# logical term labels, giving bounded archive calls distinct deterministic
# prefixes.
#
# meta:
#   0 triples, 1 equal-XOR matches, 2 separated matches, 3 minimal circuits,
#   4 D candidates, 5 local debt<=4, 6 changed endpoints, 7 rank drops,
#   8 rank neutral, 9 positive-debt shoulders, 10 best rank, 11 best density,
#   12 best local delta, 13 source density, 14 triple cap reached,
#   15 circuit cap reached, 16 best initialized, 17 best axis.
-> ffpc6_search(us, vs, ws, rank, triple_cap, circuit_cap, nonce, out_u, out_v, out_w, meta) (i64[] i64[] i64[] i64 i64 i64 i64 i64[] i64[] i64[] i64[]) i64
  if rank < 6 || us.size() < rank || vs.size() < rank || ws.size() < rank || out_u.size() < rank + 6 || out_v.size() < rank + 6 || out_w.size() < rank + 6 || meta.size() < 18 || triple_cap < 0 || circuit_cap < 0
    return 0
  i = 0 ## i64
  while i < 18
    meta[i] = 0
    i += 1
  meta[13] = ffcis_density(us,vs,ws,rank)
  source_table = i32[ffcis_table_capacity(rank)]
  ffcis_build_table(us,vs,ws,rank,source_table)

  full_triples = rank * (rank - 1) * (rank - 2) / 6 ## i64
  stored_capacity = full_triples ## i64
  if triple_cap > 0 && triple_cap < stored_capacity
    stored_capacity = triple_cap
    meta[14] = 1
  table_capacity = 16 ## i64
  while table_capacity < stored_capacity * 2
    table_capacity *= 2
  heads = i32[table_capacity]
  links = i32[stored_capacity]
  triple_a = i32[stored_capacity]
  triple_b = i32[stored_capacity]
  triple_c = i32[stored_capacity]
  triple_sum = i64[stored_capacity]
  logical_factor = i64[rank]
  logical_position = i64[rank]
  selected = i64[6]
  candidate_u = i64[out_u.size()]
  candidate_v = i64[out_v.size()]
  candidate_w = i64[out_w.size()]

  offset = nonce % rank ## i64
  stop = 0 ## i64
  axis_step = 0 ## i64
  while axis_step < 3 && stop == 0
    axis = (nonce + axis_step) % 3 ## i64
    logical = 0 ## i64
    while logical < rank
      position = (logical + offset + axis * 17) % rank ## i64
      logical_position[logical] = position
      logical_factor[logical] = ffpc6_axis_factor(us,vs,ws,position,axis)
      logical += 1
    h = 0 ## i64
    while h < table_capacity
      heads[h] = 0
      h += 1
    stored = 0 ## i64
    a = 0 ## i64
    while a < rank - 2 && stored < stored_capacity && stop == 0
      b = a + 1 ## i64
      while b < rank - 1 && stored < stored_capacity && stop == 0
        c = b + 1 ## i64
        while c < rank && stored < stored_capacity && stop == 0
          sum = logical_factor[a] ^ logical_factor[b] ^ logical_factor[c] ## i64
          slot = ffcis_hash(sum,0,0) & (table_capacity - 1) ## i64
          entry = heads[slot] ## i64
          while entry != 0 && stop == 0
            previous = entry - 1 ## i64
            if triple_sum[previous] == sum
              meta[1] = meta[1] + 1
              if triple_c[previous] < a
                meta[2] = meta[2] + 1
                pa = triple_a[previous] ## i64
                pb = triple_b[previous] ## i64
                pc = triple_c[previous] ## i64
                if ffpc6_independent5(logical_factor[pa],logical_factor[pb],logical_factor[pc],logical_factor[a],logical_factor[b]) == 1
                  meta[3] = meta[3] + 1
                  selected[0] = logical_position[pa]
                  selected[1] = logical_position[pb]
                  selected[2] = logical_position[pc]
                  selected[3] = logical_position[a]
                  selected[4] = logical_position[b]
                  selected[5] = logical_position[c]
                  yi = 0 ## i64
                  while yi < 6
                    zi = 0 ## i64
                    while zi < 6
                      y = ffpc6_axis_left(us,vs,ws,selected[yi],axis) ## i64
                      z = ffpc6_axis_right(us,vs,ws,selected[zi],axis) ## i64
                      meta[4] = meta[4] + 1
                      local_cost = ffpc6_local_cost(us,vs,ws,selected,axis,y,z) ## i64
                      local_delta = local_cost - 6 ## i64
                      # With D drawn from the six left/right factors, four is
                      # the worst possible local debt (either one matrix
                      # vanishes or two matrices share one factor with D).
                      # Keep the full median neighborhood here: collisions
                      # with unselected live terms can turn a local +4 into a
                      # globally neutral or lowering endpoint.
                      if local_delta <= 4
                        meta[5] = meta[5] + 1
                        candidate_rank = ffpc6_build_endpoint(us,vs,ws,rank,axis,selected,y,z,candidate_u,candidate_v,candidate_w) ## i64
                        if candidate_rank >= 0 && ffpc6_changed(us,vs,ws,rank,source_table,candidate_u,candidate_v,candidate_w,candidate_rank) == 1
                          meta[6] = meta[6] + 1
                          if candidate_rank < rank
                            meta[7] = meta[7] + 1
                          if candidate_rank == rank
                            meta[8] = meta[8] + 1
                          if candidate_rank > rank
                            meta[9] = meta[9] + 1
                          density = ffcis_density(candidate_u,candidate_v,candidate_w,candidate_rank) ## i64
                          better = 0 ## i64
                          if meta[16] == 0 || candidate_rank < meta[10]
                            better = 1
                          if meta[16] == 1 && candidate_rank == meta[10] && density < meta[11]
                            better = 1
                          if better == 1
                            meta[10] = candidate_rank
                            meta[11] = density
                            meta[12] = local_delta
                            meta[16] = 1
                            meta[17] = axis
                            i = 0
                            while i < candidate_rank
                              out_u[i] = candidate_u[i]
                              out_v[i] = candidate_v[i]
                              out_w[i] = candidate_w[i]
                              i += 1
                      zi += 1
                    yi += 1
                  if circuit_cap > 0 && meta[3] >= circuit_cap
                    meta[15] = 1
                    stop = 1
            entry = links[previous]
          if stop == 0
            triple_a[stored] = a
            triple_b[stored] = b
            triple_c[stored] = c
            triple_sum[stored] = sum
            links[stored] = heads[slot]
            heads[slot] = stored + 1
            stored += 1
            meta[0] = meta[0] + 1
          c += 1
        b += 1
      a += 1
    axis_step += 1
  if meta[16] == 1
    return meta[10]
  0
