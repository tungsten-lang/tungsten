# Exact projective-line / matrix-pencil refactors over GF(2).
#
# If every selected factor on `line_axis` belongs to the two-dimensional
# subspace {a,b,a^b}, group the complementary outer products into matrices
# A, B, and C.  Relative to the line basis (a,b), the two tensor slices are
#
#     X = A + C,    Y = B + C.
#
# Consequently every CP decomposition whose line factors stay in that plane
# is represented by one matrix D, at exact cost
#
#     rank(X + D) + rank(Y + D) + rank(D).
#
# Enumerating D in the product of the combined left/right factor spans is
# complete: projecting an arbitrary D into those spans fixes X/Y and cannot
# increase any of the three matrix ranks.  This is a whole-pencil operation,
# not three independent shared-factor reductions.  It can therefore refactor
# five or more live terms even though the complete span-join lane stops at k=4.
#
# The regular exact path is intentionally bounded to at most `max_cells`
# coordinate bits.  A caller may supply a complete i32 rank table (used by the
# audit for 5x5 coordinate pencils) to turn the exhaustive loop into three
# table reads per D.  All returned terms pass an exhaustive local tensor gate;
# `ffmp_splice_state` additionally reconstructs and gates the full n^6 MMT.

use metaflip_worker
use flipfleet_shear_moves
use flipfleet_flatten_gauge

-> ffmp_axis_get(us, vs, ws, position, axis) (i64[] i64[] i64[] i64 i64) i64
  if axis == 0
    return us[position]
  if axis == 1
    return vs[position]
  if axis == 2
    return ws[position]
  0

-> ffmp_line_sort(left, right, third, line) (i64 i64 i64 i64[]) i64
  if left <= 0 || right <= 0 || left == right || third != (left ^ right) || third <= 0 || line.size() < 3
    return 0
  line[0] = left
  line[1] = right
  line[2] = third
  i = 0 ## i64
  while i < 2
    j = i + 1 ## i64
    while j < 3
      if line[j] < line[i]
        temporary = line[i] ## i64
        line[i] = line[j]
        line[j] = temporary
      j += 1
    i += 1
  1

-> ffmp_same_line(left, right, line) (i64 i64 i64[]) i64
  if line.size() < 3
    return 0
  candidate = i64[3]
  if ffmp_line_sort(left,right,left ^ right,candidate) == 0
    return 0
  if candidate[0] == line[0] && candidate[1] == line[1] && candidate[2] == line[2]
    return 1
  0

-> ffmp_line_seen(lines_a, lines_b, lines_c, count, line) (i64[] i64[] i64[] i64 i64[]) i64
  i = 0 ## i64
  while i < count
    if lines_a[i] == line[0] && lines_b[i] == line[1] && lines_c[i] == line[2]
      return 1
    i += 1
  0

# Capture the maximal live subtotal on one projective line.  The original
# factor order is retained in su/sv/sw and selected stores live positions.
-> ffmp_capture_line(us, vs, ws, count, line_axis, line, selected, su, sv, sw) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64[] i64[]) i64
  if line_axis < 0 || line_axis > 2 || line.size() < 3
    return 0
  if selected.size() < count || su.size() < count || sv.size() < count || sw.size() < count
    return 0
  made = 0 ## i64
  position = 0 ## i64
  while position < count
    factor = ffmp_axis_get(us,vs,ws,position,line_axis) ## i64
    if factor == line[0] || factor == line[1] || factor == line[2]
      selected[made] = position
      su[made] = us[position]
      sv[made] = vs[position]
      sw[made] = ws[position]
      made += 1
    position += 1
  made

# Build an insertion-order basis together with a triangular reducer that also
# recovers exact coordinates in that basis.  Ambient factors use at most 63
# bits; coordinate masks are bounded below to at most 30 bits.
-> ffmp_build_basis(values, count, basis, pivots, pivot_coordinates) (i64[] i64 i64[] i64[] i64[]) i64
  if count < 0 || values.size() < count || basis.size() < count || pivots.size() < 63 || pivot_coordinates.size() < 63
    return 0 - 1
  bit = 0 ## i64
  while bit < 63
    pivots[bit] = 0
    pivot_coordinates[bit] = 0
    bit += 1
  rank = 0 ## i64
  item = 0 ## i64
  while item < count
    original = values[item] ## i64
    if original <= 0
      return 0 - 1
    value = original ## i64
    coordinates = 0 ## i64
    bit = 62
    while bit >= 0 && value != 0
      if ((value >> bit) & 1) != 0
        if pivots[bit] != 0
          value = value ^ pivots[bit]
          coordinates = coordinates ^ pivot_coordinates[bit]
        else
          if rank >= 30
            return 0 - 1
          basis[rank] = original
          pivots[bit] = value
          pivot_coordinates[bit] = coordinates ^ (1 << rank)
          rank += 1
          value = 0
      bit -= 1
    item += 1
  rank

-> ffmp_coordinates(value, pivots, pivot_coordinates) (i64 i64[] i64[]) i64
  if value <= 0 || pivots.size() < 63 || pivot_coordinates.size() < 63
    return 0 - 1
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

-> ffmp_outer_bits(left_coordinates, right_coordinates, right_rank) (i64 i64 i64) i64
  result = 0 ## i64
  left = 0 ## i64
  while (left_coordinates >> left) != 0
    if ((left_coordinates >> left) & 1) != 0
      right = 0 ## i64
      while (right_coordinates >> right) != 0
        if ((right_coordinates >> right) & 1) != 0
          result = result ^ (1 << (left * right_rank + right))
        right += 1
    left += 1
  result

-> ffmp_matrix_rank(matrix, rows, columns) (i64 i64 i64) i64
  if rows < 0 || columns < 0 || rows * columns > 62 || columns > 30
    return 0 - 1
  pivots = i64[30]
  row_mask = 0 ## i64
  if columns > 0
    row_mask = (1 << columns) - 1
  rank = 0 ## i64
  row = 0 ## i64
  while row < rows
    value = (matrix >> (row * columns)) & row_mask ## i64
    bit = columns - 1 ## i64
    while bit >= 0 && value != 0
      if ((value >> bit) & 1) != 0
        if pivots[bit] != 0
          value = value ^ pivots[bit]
        else
          pivots[bit] = value
          rank += 1
          value = 0
      bit -= 1
    row += 1
  rank

# Fill a complete rank table for one packed matrix shape.  The caller controls
# the memory bound explicitly; a 5x5 table has 2^25 i32 entries (128 MiB).
-> ffmp_fill_rank_table(rows, columns, table) (i64 i64 i32[]) i64
  cells = rows * columns ## i64
  if rows < 1 || columns < 1 || cells > 25
    return 0
  limit = 1 << cells ## i64
  if table.size() < limit
    return 0
  matrix = 0 ## i64
  while matrix < limit
    table[matrix] = ffmp_matrix_rank(matrix,rows,columns)
    matrix += 1
  limit

-> ffmp_rank_lookup(matrix, rows, columns, table, limit) (i64 i64 i64 i32[] i64) i64
  if table.size() == limit
    return table[matrix]
  ffmp_matrix_rank(matrix,rows,columns)

# Exhaustive D search.  meta: cells, enumerated, base objective, best
# objective, base D, best D, best packed Hamming distance, rank-table used.
-> ffmp_search_d(slice_x, slice_y, base_d, rows, columns, max_cells, rank_table, meta) (i64 i64 i64 i64 i64 i64 i32[] i64[]) i64
  cells = rows * columns ## i64
  if rows < 1 || columns < 1 || cells < 1 || cells > max_cells || cells > 25 || meta.size() < 8
    return 0 - 1
  limit = 1 << cells ## i64
  table_limit = limit + 1 ## i64
  if rank_table.size() == limit
    table_limit = limit
  base_objective = ffmp_rank_lookup(base_d,rows,columns,rank_table,table_limit) + ffmp_rank_lookup(slice_x ^ base_d,rows,columns,rank_table,table_limit) + ffmp_rank_lookup(slice_y ^ base_d,rows,columns,rank_table,table_limit) ## i64
  best_objective = base_objective ## i64
  best_d = base_d ## i64
  best_distance = 0 ## i64
  d = 0 ## i64
  while d < limit
    objective = ffmp_rank_lookup(d,rows,columns,rank_table,table_limit) + ffmp_rank_lookup(slice_x ^ d,rows,columns,rank_table,table_limit) + ffmp_rank_lookup(slice_y ^ d,rows,columns,rank_table,table_limit) ## i64
    distance = ffw_popcount(d ^ base_d) ## i64
    if objective < best_objective || (objective == best_objective && d != base_d && distance > best_distance)
      best_objective = objective
      best_d = d
      best_distance = distance
    d += 1
  meta[0] = cells
  meta[1] = limit
  meta[2] = base_objective
  meta[3] = best_objective
  meta[4] = base_d
  meta[5] = best_d
  meta[6] = best_distance
  meta[7] = 0
  if rank_table.size() == limit
    meta[7] = 1
  best_d

-> ffmp_complement_axes(line_axis, axes) (i64 i64[]) i64
  if axes.size() < 2
    return 0
  if line_axis == 0
    axes[0] = 1
    axes[1] = 2
    return 1
  if line_axis == 1
    axes[0] = 0
    axes[1] = 2
    return 1
  if line_axis == 2
    axes[0] = 0
    axes[1] = 1
    return 1
  0

-> ffmp_factor_matrix(matrix, left_basis, left_rank, right_basis, right_rank, out_left, out_right) (i64 i64[] i64 i64[] i64 i64[] i64[]) i64
  if left_rank < 1 || right_rank < 1 || left_rank * right_rank > 62
    return 0 - 1
  lefts = i64[63]
  rights = i64[63]
  count = 0 ## i64
  left = 0 ## i64
  while left < left_rank
    right = 0 ## i64
    while right < right_rank
      if ((matrix >> (left * right_rank + right)) & 1) != 0
        lefts[count] = left_basis[left]
        rights[count] = right_basis[right]
        count += 1
      right += 1
    left += 1
  ffsm_rank_factor_matrix(lefts,rights,count,out_left,out_right)

-> ffmp_emit_term(line_axis, line_factor, left, right, out_u, out_v, out_w, position) (i64 i64 i64 i64 i64[] i64[] i64[] i64) i64
  if line_axis == 0
    out_u[position] = line_factor
    out_v[position] = left
    out_w[position] = right
    return 1
  if line_axis == 1
    out_u[position] = left
    out_v[position] = line_factor
    out_w[position] = right
    return 1
  if line_axis == 2
    out_u[position] = left
    out_v[position] = right
    out_w[position] = line_factor
    return 1
  0

-> ffmp_materialize(line_axis, line, slice_x, slice_y, d, left_basis, left_rank, right_basis, right_rank, out_u, out_v, out_w) (i64 i64[] i64 i64 i64 i64[] i64 i64[] i64 i64[] i64[] i64[]) i64
  if line.size() < 3
    return 0
  capacity = out_u.size() ## i64
  if out_v.size() < capacity
    capacity = out_v.size()
  if out_w.size() < capacity
    capacity = out_w.size()
  matrices = i64[3]
  matrices[0] = slice_x ^ d
  matrices[1] = slice_y ^ d
  matrices[2] = d
  made = 0 ## i64
  colour = 0 ## i64
  while colour < 3
    factor_left = i64[30]
    factor_right = i64[30]
    rank = ffmp_factor_matrix(matrices[colour],left_basis,left_rank,right_basis,right_rank,factor_left,factor_right) ## i64
    if rank < 0 || made + rank > capacity
      return 0
    term = 0 ## i64
    while term < rank
      if ffmp_emit_term(line_axis,line[colour],factor_left[term],factor_right[term],out_u,out_v,out_w,made) == 0
        return 0
      made += 1
      term += 1
    colour += 1
  made

-> ffmp_same_term_set(su, sv, sw, source_count, out_u, out_v, out_w, out_count) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  if source_count != out_count
    return 0
  i = 0 ## i64
  while i < source_count
    found = 0 ## i64
    j = 0 ## i64
    while j < out_count
      if su[i] == out_u[j] && sv[i] == out_v[j] && sw[i] == out_w[j]
        found = 1
      j += 1
    if found == 0
      return 0
    i += 1
  1

-> ffmp_term_set_distance(su, sv, sw, source_count, out_u, out_v, out_w, out_count) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  common = 0 ## i64
  i = 0 ## i64
  while i < source_count
    j = 0 ## i64
    while j < out_count
      if su[i] == out_u[j] && sv[i] == out_v[j] && sw[i] == out_w[j]
        common += 1
        j = out_count
      else
        j += 1
    i += 1
  source_count + out_count - 2 * common

# Optimize one already-captured maximal line subtotal.  meta layout:
#   0 k, 1/2 complementary span ranks, 3 cells, 4 enumerated,
#   5 ordinary three-bucket rank, 6 best pencil rank,
#   7 base D, 8 best D, 9 packed distance, 10 local exact,
#   11 same set, 12 term-set distance, 13 rank-table used.
-> ffmp_optimize_group(su, sv, sw, count, line_axis, line, max_cells, rank_table, out_u, out_v, out_w, meta) (i64[] i64[] i64[] i64 i64 i64[] i64 i32[] i64[] i64[] i64[] i64[]) i64
  if count < 2 || su.size() < count || sv.size() < count || sw.size() < count || line.size() < 3 || meta.size() < 14
    return 0
  axes = i64[2]
  if ffmp_complement_axes(line_axis,axes) == 0
    return 0
  left_values = i64[count]
  right_values = i64[count]
  i = 0 ## i64
  while i < count
    line_factor = ffmp_axis_get(su,sv,sw,i,line_axis) ## i64
    if line_factor != line[0] && line_factor != line[1] && line_factor != line[2]
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
  if left_rank < 1 || right_rank < 1 || left_rank * right_rank > max_cells
    meta[0] = count
    meta[1] = left_rank
    meta[2] = right_rank
    meta[3] = left_rank * right_rank
    return 0
  matrices = i64[3]
  i = 0
  while i < count
    lc = ffmp_coordinates(left_values[i],left_pivots,left_coordinates) ## i64
    rc = ffmp_coordinates(right_values[i],right_pivots,right_coordinates) ## i64
    if lc < 0 || rc < 0
      return 0
    outer = ffmp_outer_bits(lc,rc,right_rank) ## i64
    line_factor = ffmp_axis_get(su,sv,sw,i,line_axis)
    colour = 0 ## i64
    if line_factor == line[1]
      colour = 1
    if line_factor == line[2]
      colour = 2
    matrices[colour] = matrices[colour] ^ outer
    i += 1
  slice_x = matrices[0] ^ matrices[2] ## i64
  slice_y = matrices[1] ^ matrices[2] ## i64
  search_meta = i64[8]
  best_d = ffmp_search_d(slice_x,slice_y,matrices[2],left_rank,right_rank,max_cells,rank_table,search_meta) ## i64
  if best_d < 0
    return 0
  made = ffmp_materialize(line_axis,line,slice_x,slice_y,best_d,left_basis,left_rank,right_basis,right_rank,out_u,out_v,out_w) ## i64
  if made < 1
    return 0
  exact = ffgr_replacement_exact(su,sv,sw,count,out_u,out_v,out_w,made) ## i64
  if exact != 1
    return 0
  meta[0] = count
  meta[1] = left_rank
  meta[2] = right_rank
  meta[3] = search_meta[0]
  meta[4] = search_meta[1]
  meta[5] = search_meta[2]
  meta[6] = search_meta[3]
  meta[7] = search_meta[4]
  meta[8] = search_meta[5]
  meta[9] = search_meta[6]
  meta[10] = exact
  meta[11] = ffmp_same_term_set(su,sv,sw,count,out_u,out_v,out_w,made)
  meta[12] = ffmp_term_set_distance(su,sv,sw,count,out_u,out_v,out_w,made)
  meta[13] = search_meta[7]
  made

-> ffmp_position_selected(selected, count, position) (i64[] i64 i64) i64
  i = 0 ## i64
  while i < count
    if selected[i] == position
      return 1
    i += 1
  0

-> ffmp_toggle_term(us, vs, ws, count, capacity, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
  i = 0 ## i64
  while i < count
    if us[i] == u && vs[i] == v && ws[i] == w
      us[i] = us[count-1]
      vs[i] = vs[count-1]
      ws[i] = ws[count-1]
      return count - 1
    i += 1
  if count >= capacity || u <= 0 || v <= 0 || w <= 0
    return 0 - 1
  us[count] = u
  vs[count] = v
  ws[count] = w
  count + 1

# Parity-compact a local replacement into a fresh worker state and run the
# exhaustive n^6 matrix-multiplication gate.  The source remains untouched.
-> ffmp_splice_state(source, selected, selected_count, out_u, out_v, out_w, out_count, candidate, seed) (i64[] i64[] i64 i64[] i64[] i64[] i64 i64[] i64) i64
  if ffw_valid(source) != 1 || selected_count < 1 || out_count < 1
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
  loaded = ffw_init_terms_cap(candidate,made_u,made_v,made_w,made,source[2],capacity,seed,0,1,1,1) ## i64
  if loaded == made && ffw_verify_current_exact(candidate,source[2]) == 1
    return made
  0
