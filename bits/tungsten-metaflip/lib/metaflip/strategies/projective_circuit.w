# Exact five-bucket dependency medians over GF(2).
#
# If five distinct factors f_i form a minimal linear circuit
#
#     f0 ^ f1 ^ f2 ^ f3 ^ f4 = 0,
#
# then the same complementary rank-one matrix D may be XORed into the five
# corresponding matrix slices without changing the tensor.  With one live
# term per bucket, each old matrix is rank one.  The search tests both
# D=y tensor z from the selected complementary factors and every nonzero D in
# the at-most-five-dimensional span of the old matrices.  The latter is a
# complete 31-value higher-rank median family.  Size-three dependencies are
# covered by the matrix pencil and size-four dependencies by the Fano-plane
# move; a rank-four five-circuit is the next projective geometry.
#
# The search is offline and admission-sound.  Callers still rebuild and
# exhaustively verify the complete matrix-multiplication tensor.

use circuit_search3
use matrix_pencil

-> ffpc5_axis_factor(us, vs, ws, position, axis) (i64[] i64[] i64[] i64 i64) i64
  if axis == 0
    return us[position]
  if axis == 1
    return vs[position]
  if axis == 2
    return ws[position]
  0

-> ffpc5_axis_left(us, vs, ws, position, axis) (i64[] i64[] i64[] i64 i64) i64
  if axis == 0
    return vs[position]
  return us[position]

-> ffpc5_axis_right(us, vs, ws, position, axis) (i64[] i64[] i64[] i64 i64) i64
  if axis == 2
    return vs[position]
  return ws[position]

-> ffpc5_independent4(a, b, c, d) (i64 i64 i64 i64) i64
  values = i64[4]
  values[0] = a
  values[1] = b
  values[2] = c
  values[3] = d
  subset = 1 ## i64
  while subset < 16
    sum = 0 ## i64
    bit = 0 ## i64
    while bit < 4
      if ((subset >> bit) & 1) != 0
        sum = sum ^ values[bit]
      bit += 1
    if sum == 0
      return 0
    subset += 1
  1

-> ffpc5_toggle_axis(out_u, out_v, out_w, count, capacity, axis, factor, left, right) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64) i64
  if axis == 0
    return ffcis3_toggle(out_u,out_v,out_w,count,capacity,factor,left,right)
  if axis == 1
    return ffcis3_toggle(out_u,out_v,out_w,count,capacity,left,factor,right)
  if axis == 2
    return ffcis3_toggle(out_u,out_v,out_w,count,capacity,left,right,factor)
  0 - 1

# Replace the five selected rank-one slice matrices by M_i ^ (y tensor z).
-> ffpc5_build_endpoint(us, vs, ws, rank, axis, selected, y, z, out_u, out_v, out_w) (i64[] i64[] i64[] i64 i64 i64[] i64 i64 i64[] i64[] i64[]) i64
  if rank < 5 || axis < 0 || axis > 2 || selected.size() < 5 || out_u.size() < rank + 5 || out_v.size() < rank + 5 || out_w.size() < rank + 5 || y == 0 || z == 0
    return 0 - 1
  count = 0 ## i64
  position = 0 ## i64
  while position < rank
    count = ffcis3_toggle(out_u,out_v,out_w,count,out_u.size(),us[position],vs[position],ws[position])
    if count < 0
      return 0 - 1
    position += 1
  item = 0 ## i64
  while item < 5
    position = selected[item] ## i64
    if position < 0 || position >= rank
      return 0 - 1
    factor = ffpc5_axis_factor(us,vs,ws,position,axis) ## i64
    left = ffpc5_axis_left(us,vs,ws,position,axis) ## i64
    right = ffpc5_axis_right(us,vs,ws,position,axis) ## i64
    # Remove the old summand first.
    count = ffpc5_toggle_axis(out_u,out_v,out_w,count,out_u.size(),axis,factor,left,right)
    if count < 0
      return 0 - 1
    if left == y && right == z
      z0 = 0 ## i64
    else
      if left == y
        count = ffpc5_toggle_axis(out_u,out_v,out_w,count,out_u.size(),axis,factor,left,right ^ z)
      else
        if right == z
          count = ffpc5_toggle_axis(out_u,out_v,out_w,count,out_u.size(),axis,factor,left ^ y,right)
        else
          count = ffpc5_toggle_axis(out_u,out_v,out_w,count,out_u.size(),axis,factor,left,right)
          if count >= 0
            count = ffpc5_toggle_axis(out_u,out_v,out_w,count,out_u.size(),axis,factor,y,z)
      if count < 0
        return 0 - 1
    item += 1
  count

-> ffpc5_local_cost(us, vs, ws, selected, axis, y, z) (i64[] i64[] i64[] i64[] i64 i64 i64) i64
  cost = 0 ## i64
  item = 0 ## i64
  while item < 5
    position = selected[item] ## i64
    left = ffpc5_axis_left(us,vs,ws,position,axis) ## i64
    right = ffpc5_axis_right(us,vs,ws,position,axis) ## i64
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

-> ffpc5_changed(us, vs, ws, rank, table, candidate_u, candidate_v, candidate_w, candidate_rank) (i64[] i64[] i64[] i64 i32[] i64[] i64[] i64[] i64) i64
  if candidate_rank != rank
    return 1
  i = 0 ## i64
  while i < candidate_rank
    if ffcis_lookup(us,vs,ws,table,candidate_u[i],candidate_v[i],candidate_w[i]) < 0
      return 1
    i += 1
  0

# The circuit identity permits an arbitrary complementary matrix D, not only
# a rank-one outer product.  Exhaust the at-most-31 nonzero matrices in the
# span of the five live slice matrices.  This adds higher-rank medians while
# preserving a tiny, circuit-local search space.  `stats` stores candidates,
# best local objective, best D, and the two complementary span ranks.
-> ffpc5_span_median_endpoint(us, vs, ws, rank, axis, selected, out_u, out_v, out_w, stats) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64[] i64[]) i64
  if selected.size() < 5 || stats.size() < 5
    return 0 - 1
  axes = i64[2]
  if ffmp_complement_axes(axis,axes) == 0
    return 0 - 1
  left_values = i64[5]
  right_values = i64[5]
  item = 0 ## i64
  while item < 5
    position = selected[item] ## i64
    if position < 0 || position >= rank
      return 0 - 1
    left_values[item] = ffpc5_axis_left(us,vs,ws,position,axis)
    right_values[item] = ffpc5_axis_right(us,vs,ws,position,axis)
    item += 1
  left_basis = i64[5]
  right_basis = i64[5]
  left_pivots = i64[63]
  right_pivots = i64[63]
  left_coordinates = i64[63]
  right_coordinates = i64[63]
  left_rank = ffmp_build_basis(left_values,5,left_basis,left_pivots,left_coordinates) ## i64
  right_rank = ffmp_build_basis(right_values,5,right_basis,right_pivots,right_coordinates) ## i64
  stats[3] = left_rank
  stats[4] = right_rank
  if left_rank < 1 || right_rank < 1 || left_rank * right_rank > 62
    return 0 - 1
  matrices = i64[5]
  item = 0
  while item < 5
    lc = ffmp_coordinates(left_values[item],left_pivots,left_coordinates) ## i64
    rc = ffmp_coordinates(right_values[item],right_pivots,right_coordinates) ## i64
    if lc < 0 || rc < 0
      return 0 - 1
    matrices[item] = ffmp_outer_bits(lc,rc,right_rank)
    item += 1
  best_initialized = 0 ## i64
  best_objective = 1000 ## i64
  best_d = 0 ## i64
  subset = 1 ## i64
  while subset < 32
    d = 0 ## i64
    item = 0
    while item < 5
      if ((subset >> item) & 1) != 0
        d = d ^ matrices[item]
      item += 1
    if d != 0
      stats[0] = stats[0] + 1
      objective = 0 ## i64
      item = 0
      while item < 5
        objective += ffmp_matrix_rank(matrices[item] ^ d,left_rank,right_rank)
        item += 1
      if best_initialized == 0 || objective < best_objective || (objective == best_objective && ffw_popcount(d) > ffw_popcount(best_d))
        best_initialized = 1
        best_objective = objective
        best_d = d
    subset += 1
  stats[1] = best_objective
  stats[2] = best_d
  if best_initialized == 0 || best_objective > 7
    return 0 - 1

  count = 0 ## i64
  position = 0 ## i64
  while position < rank
    count = ffcis3_toggle(out_u,out_v,out_w,count,out_u.size(),us[position],vs[position],ws[position])
    if count < 0
      return 0 - 1
    position += 1
  item = 0
  while item < 5
    position = selected[item]
    factor = ffpc5_axis_factor(us,vs,ws,position,axis) ## i64
    count = ffpc5_toggle_axis(out_u,out_v,out_w,count,out_u.size(),axis,factor,left_values[item],right_values[item])
    if count < 0
      return 0 - 1
    factor_left = i64[30]
    factor_right = i64[30]
    matrix_rank = ffmp_factor_matrix(matrices[item] ^ best_d,left_basis,left_rank,right_basis,right_rank,factor_left,factor_right) ## i64
    if matrix_rank < 0
      return 0 - 1
    term = 0 ## i64
    while term < matrix_rank
      count = ffpc5_toggle_axis(out_u,out_v,out_w,count,out_u.size(),axis,factor,factor_left[term],factor_right[term])
      if count < 0
        return 0 - 1
      term += 1
    item += 1
  count

# Complete over five-circuits when circuit_cap is zero.  A positive cap bounds
# circuits (not four-tuples); nonce rotates logical source labels.
#
# meta:
#   0 four-tuples, 1 five-circuits, 2 D candidates, 3 local debt<=2,
#   4 changed endpoints, 5 rank drops, 6 rank neutral, 7 best rank,
#   8 best density, 9 best local delta, 10 source density, 11 cap reached,
#   12 best initialized, 13 best axis.
-> ffpc5_search(us, vs, ws, rank, circuit_cap, nonce, out_u, out_v, out_w, meta) (i64[] i64[] i64[] i64 i64 i64 i64[] i64[] i64[] i64[]) i64
  if rank < 5 || us.size() < rank || vs.size() < rank || ws.size() < rank || out_u.size() < rank + 5 || out_v.size() < rank + 5 || out_w.size() < rank + 5 || meta.size() < 14 || circuit_cap < 0
    return 0
  i = 0 ## i64
  while i < 14
    meta[i] = 0
    i += 1
  meta[10] = ffcis_density(us,vs,ws,rank)
  source_table = i32[ffcis_table_capacity(rank)]
  ffcis_build_table(us,vs,ws,rank,source_table)
  logical_factor = i64[rank]
  logical_left = i64[rank]
  logical_right = i64[rank]
  logical_position = i64[rank]
  selected = i64[5]
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
      logical_factor[logical] = ffpc5_axis_factor(us,vs,ws,position,axis)
      logical_left[logical] = ffpc5_axis_left(us,vs,ws,position,axis)
      logical_right[logical] = ffpc5_axis_right(us,vs,ws,position,axis)
      logical += 1
    table_capacity = 16 ## i64
    while table_capacity < rank * 4
      table_capacity *= 2
    heads = i32[table_capacity]
    links = i32[rank]
    logical = 0
    while logical < rank
      slot = ffcis_hash(logical_factor[logical],0,0) & (table_capacity - 1) ## i64
      links[logical] = heads[slot]
      heads[slot] = logical + 1
      logical += 1
    a = 0 ## i64
    while a < rank - 4 && stop == 0
      b = a + 1 ## i64
      while b < rank - 3 && stop == 0
        c = b + 1 ## i64
        while c < rank - 2 && stop == 0
          d = c + 1 ## i64
          while d < rank - 1 && stop == 0
            meta[0] = meta[0] + 1
            fa = logical_factor[a] ## i64
            fb = logical_factor[b] ## i64
            fc = logical_factor[c] ## i64
            fd = logical_factor[d] ## i64
            if ffpc5_independent4(fa,fb,fc,fd) == 1
              target = fa ^ fb ^ fc ^ fd ## i64
              slot = ffcis_hash(target,0,0) & (table_capacity - 1) ## i64
              entry = heads[slot] ## i64
              while entry != 0 && stop == 0
                e = entry - 1 ## i64
                if e > d && logical_factor[e] == target
                  meta[1] = meta[1] + 1
                  selected[0] = logical_position[a]
                  selected[1] = logical_position[b]
                  selected[2] = logical_position[c]
                  selected[3] = logical_position[d]
                  selected[4] = logical_position[e]
                  yi = 0 ## i64
                  while yi < 5
                    zi = 0 ## i64
                    while zi < 5
                      y = ffpc5_axis_left(us,vs,ws,selected[yi],axis) ## i64
                      z = ffpc5_axis_right(us,vs,ws,selected[zi],axis) ## i64
                      meta[2] = meta[2] + 1
                      local_cost = ffpc5_local_cost(us,vs,ws,selected,axis,y,z) ## i64
                      local_delta = local_cost - 5 ## i64
                      if local_delta <= 2
                        meta[3] = meta[3] + 1
                        candidate_rank = ffpc5_build_endpoint(us,vs,ws,rank,axis,selected,y,z,candidate_u,candidate_v,candidate_w) ## i64
                        if candidate_rank >= 0 && ffpc5_changed(us,vs,ws,rank,source_table,candidate_u,candidate_v,candidate_w,candidate_rank) == 1
                          meta[4] = meta[4] + 1
                          if candidate_rank < rank
                            meta[5] = meta[5] + 1
                          if candidate_rank == rank
                            meta[6] = meta[6] + 1
                          density = ffcis_density(candidate_u,candidate_v,candidate_w,candidate_rank) ## i64
                          better = 0 ## i64
                          if meta[12] == 0 || candidate_rank < meta[7]
                            better = 1
                          if meta[12] == 1 && candidate_rank == meta[7] && density < meta[8]
                            better = 1
                          if better == 1
                            meta[7] = candidate_rank
                            meta[8] = density
                            meta[9] = local_delta
                            meta[12] = 1
                            meta[13] = axis
                            i = 0
                            while i < candidate_rank
                              out_u[i] = candidate_u[i]
                              out_v[i] = candidate_v[i]
                              out_w[i] = candidate_w[i]
                              i += 1
                      zi += 1
                    yi += 1
                  span_stats = i64[5]
                  span_rank = ffpc5_span_median_endpoint(us,vs,ws,rank,axis,selected,candidate_u,candidate_v,candidate_w,span_stats) ## i64
                  meta[2] = meta[2] + span_stats[0]
                  if span_rank >= 0
                    local_delta = span_rank - rank
                    if local_delta <= 2
                      meta[3] = meta[3] + 1
                      if ffpc5_changed(us,vs,ws,rank,source_table,candidate_u,candidate_v,candidate_w,span_rank) == 1
                        meta[4] = meta[4] + 1
                        if span_rank < rank
                          meta[5] = meta[5] + 1
                        if span_rank == rank
                          meta[6] = meta[6] + 1
                        density = ffcis_density(candidate_u,candidate_v,candidate_w,span_rank) ## i64
                        better = 0 ## i64
                        if meta[12] == 0 || span_rank < meta[7]
                          better = 1
                        if meta[12] == 1 && span_rank == meta[7] && density < meta[8]
                          better = 1
                        if better == 1
                          meta[7] = span_rank
                          meta[8] = density
                          meta[9] = local_delta
                          meta[12] = 1
                          meta[13] = axis
                          i = 0
                          while i < span_rank
                            out_u[i] = candidate_u[i]
                            out_v[i] = candidate_v[i]
                            out_w[i] = candidate_w[i]
                            i += 1
                  if circuit_cap > 0 && meta[1] >= circuit_cap
                    meta[11] = 1
                    stop = 1
                entry = links[e]
            d += 1
          c += 1
        b += 1
      a += 1
    axis_step += 1
  if meta[12] == 1
    return meta[7]
  0
