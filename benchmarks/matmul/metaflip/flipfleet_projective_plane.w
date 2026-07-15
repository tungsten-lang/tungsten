# Exact projective-plane quadrilateral refactors over GF(2).
#
# Seven nonzero factors in a three-dimensional factor span form the Fano
# projective plane.  Every complement of a Fano line is a four-point circuit:
#
#     p0 ^ p1 ^ p2 ^ p3 = 0.
#
# If the complementary subtotals at those four factors are matrices A_i, the
# same packed matrix D can therefore be toggled into all four buckets without
# changing the tensor.  The exact objective is
#
#     sum_i rank(A_i ^ D).
#
# For up to `max_cells` we enumerate every D in the combined complementary
# factor spans and every one of the seven four-point circuits.  Larger real
# planes use an exact structured candidate set (buckets, bucket XORs, and all
# rank-one D); that search is admission-sound but not optimization-complete.
# This is the rank-metric four-median analogue of the three-bucket
# matrix-pencil line move.  It is not covered by one k<=4 span refactor when
# the maximal plane subtotal contains five or more terms, and it changes a
# rank-three collection of fixed-axis factors rather than one projective line.
# It does, however, live inside the general flattening-factorization orbit;
# the novelty is structured complete search, not a new algebraic component.
#
# The implementation is deliberately move-lab only.  Every materialized
# result passes an exhaustive local tensor gate; callers can use the generic
# matrix-pencil splice helper for a second full n^6 MMT gate.

use flipfleet_matrix_pencil

-> ffpp_plane_from(left, middle, right, points) (i64 i64 i64 i64[]) i64
  if left <= 0 || middle <= 0 || right <= 0 || points.size() < 7
    return 0
  values = i64[3]
  values[0] = left
  values[1] = middle
  values[2] = right
  basis = i64[3]
  if ffsr_make_basis(values,3,basis) != 3
    return 0
  count = 0 ## i64
  combination = 1 ## i64
  while combination < 8
    value = 0 ## i64
    bit = 0 ## i64
    while bit < 3
      if ((combination >> bit) & 1) != 0
        value = value ^ basis[bit]
      bit += 1
    points[count] = value
    count += 1
    combination += 1
  i = 0 ## i64
  while i < 6
    j = i + 1 ## i64
    while j < 7
      if points[j] < points[i]
        temporary = points[i] ## i64
        points[i] = points[j]
        points[j] = temporary
      j += 1
    i += 1
  7

-> ffpp_plane_equal(left, right) (i64[] i64[]) i64
  if left.size() < 7 || right.size() < 7
    return 0
  i = 0 ## i64
  while i < 7
    if left[i] != right[i]
      return 0
    i += 1
  1

-> ffpp_plane_index(points, value) (i64[] i64) i64
  result = 0 - 1 ## i64
  i = 0 ## i64
  while i < 7 && result < 0
    if points[i] == value
      result = i
    i += 1
  result

-> ffpp_circuit_valid(points, mask) (i64[] i64) i64
  if points.size() < 7 || ffw_popcount(mask) != 4
    return 0
  sum = 0 ## i64
  point = 0 ## i64
  while point < 7
    if ((mask >> point) & 1) != 0
      sum = sum ^ points[point]
    point += 1
  if sum == 0
    return 1
  0

-> ffpp_count_circuits(points) (i64[]) i64
  count = 0 ## i64
  mask = 1 ## i64
  while mask < 128
    count += ffpp_circuit_valid(points,mask)
    mask += 1
  count

-> ffpp_circuit_objective(matrices, base_ranks, base_objective, mask, d, rows, columns) (i64[] i64[] i64 i64 i64 i64 i64) i64
  objective = base_objective ## i64
  point = 0 ## i64
  while point < 7
    if ((mask >> point) & 1) != 0
      objective -= base_ranks[point]
      objective += ffmp_matrix_rank(matrices[point] ^ d,rows,columns)
    point += 1
  objective

-> ffpp_capture_plane(us, vs, ws, count, plane_axis, points, selected, su, sv, sw) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64[] i64[]) i64
  if plane_axis < 0 || plane_axis > 2 || points.size() < 7
    return 0
  if selected.size() < count || su.size() < count || sv.size() < count || sw.size() < count
    return 0
  made = 0 ## i64
  position = 0 ## i64
  while position < count
    factor = ffmp_axis_get(us,vs,ws,position,plane_axis) ## i64
    if ffpp_plane_index(points,factor) >= 0
      selected[made] = position
      su[made] = us[position]
      sv[made] = vs[position]
      sw[made] = ws[position]
      made += 1
    position += 1
  made

# Search every four-point circuit and every packed D.  `meta` layout:
#   0 cells, 1 candidates enumerated, 2 ordinary bucket rank,
#   3 best projective-plane rank, 4 best circuit mask, 5 best D,
#   6 packed-matrix Hamming distance, 7 circuit count.
-> ffpp_search_circuits(matrices, points, rows, columns, max_cells, best_matrices, meta) (i64[] i64[] i64 i64 i64 i64[] i64[]) i64
  cells = rows * columns ## i64
  if matrices.size() < 7 || points.size() < 7 || best_matrices.size() < 7 || meta.size() < 8
    return 0 - 1
  if rows < 1 || columns < 1 || cells < 1 || cells > max_cells || cells > 25
    return 0 - 1
  base_ranks = i64[7]
  base_objective = 0 ## i64
  point = 0 ## i64
  while point < 7
    base_ranks[point] = ffmp_matrix_rank(matrices[point],rows,columns)
    base_objective += base_ranks[point]
    best_matrices[point] = matrices[point]
    point += 1
  best_objective = base_objective ## i64
  best_mask = 0 ## i64
  best_d = 0 ## i64
  best_distance = 0 ## i64
  circuit_count = 0 ## i64
  enumerated = 0 ## i64
  limit = 1 << cells ## i64
  mask = 1 ## i64
  while mask < 128
    if ffpp_circuit_valid(points,mask) == 1
      circuit_count += 1
      untouched = base_objective ## i64
      point = 0
      while point < 7
        if ((mask >> point) & 1) != 0
          untouched -= base_ranks[point]
        point += 1
      d = 0 ## i64
      while d < limit
        objective = untouched ## i64
        point = 0
        while point < 7
          if ((mask >> point) & 1) != 0
            objective += ffmp_matrix_rank(matrices[point] ^ d,rows,columns)
          point += 1
        distance = 4 * ffw_popcount(d) ## i64
        if objective < best_objective || (objective == best_objective && d != 0 && distance > best_distance)
          best_objective = objective
          best_mask = mask
          best_d = d
          best_distance = distance
        d += 1
        enumerated += 1
    mask += 1
  point = 0
  while point < 7
    best_matrices[point] = matrices[point]
    if ((best_mask >> point) & 1) != 0
      best_matrices[point] = best_matrices[point] ^ best_d
    point += 1
  meta[0] = cells
  meta[1] = enumerated
  meta[2] = base_objective
  meta[3] = best_objective
  meta[4] = best_mask
  meta[5] = best_d
  meta[6] = best_distance
  meta[7] = circuit_count
  best_objective

# Exact structured search for planes too large for complete 2^cells scanning.
# The candidate family contains every live bucket matrix, every XOR of two
# buckets, and every rank-one matrix in the combined complementary spans.
# This is incomplete as an optimizer but every accepted update is an exact
# four-point circuit identity.  Rows and columns are bounded by eight so the
# regular enumeration remains useful on real k<=8 plane subtotals.
-> ffpp_search_structured(matrices, points, rows, columns, max_factor_rank, best_matrices, meta) (i64[] i64[] i64 i64 i64 i64[] i64[]) i64
  cells = rows * columns ## i64
  if matrices.size() < 7 || points.size() < 7 || best_matrices.size() < 7 || meta.size() < 8
    return 0 - 1
  if rows < 1 || columns < 1 || rows > max_factor_rank || columns > max_factor_rank || cells > 62
    return 0 - 1
  base_ranks = i64[7]
  base_objective = 0 ## i64
  point = 0 ## i64
  while point < 7
    base_ranks[point] = ffmp_matrix_rank(matrices[point],rows,columns)
    base_objective += base_ranks[point]
    best_matrices[point] = matrices[point]
    point += 1
  best_objective = base_objective ## i64
  best_mask = 0 ## i64
  best_d = 0 ## i64
  best_distance = 0 ## i64
  circuit_count = 0 ## i64
  enumerated = 0 ## i64
  mask = 1 ## i64
  while mask < 128
    if ffpp_circuit_valid(points,mask) == 1
      circuit_count += 1
      source = 0 ## i64
      while source < 7
        d = matrices[source] ## i64
        if d != 0
          objective = ffpp_circuit_objective(matrices,base_ranks,base_objective,mask,d,rows,columns) ## i64
          distance = 4 * ffw_popcount(d) ## i64
          if objective < best_objective || (objective == best_objective && distance > best_distance)
            best_objective = objective
            best_mask = mask
            best_d = d
            best_distance = distance
        enumerated += 1
        source += 1
      left = 0 ## i64
      while left < 6
        right = left + 1 ## i64
        while right < 7
          d = matrices[left] ^ matrices[right] ## i64
          if d != 0
            objective = ffpp_circuit_objective(matrices,base_ranks,base_objective,mask,d,rows,columns) ## i64
            distance = 4 * ffw_popcount(d) ## i64
            if objective < best_objective || (objective == best_objective && distance > best_distance)
              best_objective = objective
              best_mask = mask
              best_d = d
              best_distance = distance
          enumerated += 1
          right += 1
        left += 1
      left_coordinates = 1 ## i64
      while left_coordinates < (1 << rows)
        right_coordinates = 1 ## i64
        while right_coordinates < (1 << columns)
          d = ffmp_outer_bits(left_coordinates,right_coordinates,columns) ## i64
          objective = ffpp_circuit_objective(matrices,base_ranks,base_objective,mask,d,rows,columns) ## i64
          distance = 4 * ffw_popcount(d) ## i64
          if objective < best_objective || (objective == best_objective && distance > best_distance)
            best_objective = objective
            best_mask = mask
            best_d = d
            best_distance = distance
          enumerated += 1
          right_coordinates += 1
        left_coordinates += 1
    mask += 1
  point = 0
  while point < 7
    best_matrices[point] = matrices[point]
    if ((best_mask >> point) & 1) != 0
      best_matrices[point] = best_matrices[point] ^ best_d
    point += 1
  meta[0] = cells
  meta[1] = enumerated
  meta[2] = base_objective
  meta[3] = best_objective
  meta[4] = best_mask
  meta[5] = best_d
  meta[6] = best_distance
  meta[7] = circuit_count
  best_objective

-> ffpp_materialize(plane_axis, points, matrices, left_basis, left_rank, right_basis, right_rank, out_u, out_v, out_w) (i64 i64[] i64[] i64[] i64 i64[] i64 i64[] i64[] i64[]) i64
  if points.size() < 7 || matrices.size() < 7
    return 0
  capacity = out_u.size() ## i64
  if out_v.size() < capacity
    capacity = out_v.size()
  if out_w.size() < capacity
    capacity = out_w.size()
  made = 0 ## i64
  point = 0 ## i64
  while point < 7
    factor_left = i64[30]
    factor_right = i64[30]
    rank = ffmp_factor_matrix(matrices[point],left_basis,left_rank,right_basis,right_rank,factor_left,factor_right) ## i64
    if rank < 0 || made + rank > capacity
      return 0
    term = 0 ## i64
    while term < rank
      if ffmp_emit_term(plane_axis,points[point],factor_left[term],factor_right[term],out_u,out_v,out_w,made) == 0
        return 0
      made += 1
      term += 1
    point += 1
  made

# Optimize one maximal plane subtotal.  `meta` layout:
#   0 source terms, 1/2 complementary span ranks, 3 cells,
#   4 candidates enumerated, 5 ordinary bucket rank, 6 best plane rank,
#   7 best circuit mask, 8 best D, 9 packed-matrix distance,
#   10 local exact, 11 same term set, 12 term-set distance,
#   13 search mode (1 complete, 2 structured), 14 source minus ordinary rank,
#   15 source minus best rank.
-> ffpp_optimize_group(su, sv, sw, count, plane_axis, points, max_cells, out_u, out_v, out_w, meta) (i64[] i64[] i64[] i64 i64 i64[] i64 i64[] i64[] i64[] i64[]) i64
  if count < 1 || su.size() < count || sv.size() < count || sw.size() < count || points.size() < 7 || meta.size() < 16
    return 0
  axes = i64[2]
  if ffmp_complement_axes(plane_axis,axes) == 0
    return 0
  left_values = i64[count]
  right_values = i64[count]
  i = 0 ## i64
  while i < count
    if ffpp_plane_index(points,ffmp_axis_get(su,sv,sw,i,plane_axis)) < 0
      return 0
    left_values[i] = ffmp_axis_get(su,sv,sw,i,axes[0])
    right_values[i] = ffmp_axis_get(su,sv,sw,i,axes[1])
    i += 1
  left_basis = i64[count]
  right_basis = i64[count]
  left_pivots = i64[63]
  right_pivots = i64[63]
  left_coordinates = i64[63]
  right_coordinates = i64[63]
  left_rank = ffmp_build_basis(left_values,count,left_basis,left_pivots,left_coordinates) ## i64
  right_rank = ffmp_build_basis(right_values,count,right_basis,right_pivots,right_coordinates) ## i64
  meta[0] = count
  meta[1] = left_rank
  meta[2] = right_rank
  meta[3] = left_rank * right_rank
  if left_rank < 1 || right_rank < 1 || left_rank * right_rank > 62
    return 0
  matrices = i64[7]
  i = 0
  while i < count
    lc = ffmp_coordinates(left_values[i],left_pivots,left_coordinates) ## i64
    rc = ffmp_coordinates(right_values[i],right_pivots,right_coordinates) ## i64
    if lc < 0 || rc < 0
      return 0
    outer = ffmp_outer_bits(lc,rc,right_rank) ## i64
    point = ffpp_plane_index(points,ffmp_axis_get(su,sv,sw,i,plane_axis)) ## i64
    if point < 0
      return 0
    matrices[point] = matrices[point] ^ outer
    i += 1
  best_matrices = i64[7]
  search_meta = i64[8]
  search_mode = 1 ## i64
  best = 0 - 1 ## i64
  if left_rank * right_rank <= max_cells
    best = ffpp_search_circuits(matrices,points,left_rank,right_rank,max_cells,best_matrices,search_meta)
  if left_rank * right_rank > max_cells
    search_mode = 2
    best = ffpp_search_structured(matrices,points,left_rank,right_rank,8,best_matrices,search_meta)
  if best < 0
    return 0
  made = ffpp_materialize(plane_axis,points,best_matrices,left_basis,left_rank,right_basis,right_rank,out_u,out_v,out_w) ## i64
  if made < 1
    return 0
  exact = ffgr_replacement_exact(su,sv,sw,count,out_u,out_v,out_w,made) ## i64
  if exact != 1
    return 0
  meta[4] = search_meta[1]
  meta[5] = search_meta[2]
  meta[6] = search_meta[3]
  meta[7] = search_meta[4]
  meta[8] = search_meta[5]
  meta[9] = search_meta[6]
  meta[10] = exact
  meta[11] = ffmp_same_term_set(su,sv,sw,count,out_u,out_v,out_w,made)
  meta[12] = ffmp_term_set_distance(su,sv,sw,count,out_u,out_v,out_w,made)
  meta[13] = search_mode
  meta[14] = count - search_meta[2]
  meta[15] = count - search_meta[3]
  made
