# Exact one-factor kernel-line fiber completion.
#
# For a nonzero factor-space vector q, choose its highest set bit as a pivot
# and form the quotient representative
#
#   pi_q(x) = x xor (pivot_bit(x) * q).
#
# Thus ker(pi_q)=<q>.  After projecting and parity-compacting one tensor axis,
# every choice of lifts p_i or p_i+q differs from the source by q tensor M for
# one ordinary two-factor matrix M.  `ffsm_rank_factor_matrix` supplies an
# exact minimal completion of M.  A collection of lift changes can therefore
# cross a rank barrier atomically while the returned endpoint remains exact.
#
# This is a move-lab prototype, not a fleet lane.  The caller names projected
# term ordinals after deterministic lexicographic sorting.  Production replay
# should persist the symmetric-difference relation, not ordinals.
#
# Materialization meta (12 words):
#   0 projected terms, 1 residual atoms, 2 completion rank,
#   3 endpoint rank, 4 requested lift changes, 5 term-set distance,
#   6 exact local gate, 7 pivot bit, 8 source density, 9 endpoint density,
#   10 selected ordinals valid, 11 reserved.

use flipfleet_shear_moves
use flipfleet_tunnel_catalyst

-> ffklf_axis_get(us, vs, ws, term, axis) (i64[] i64[] i64[] i64 i64) i64
  value = us[term] ## i64
  if axis == 1
    value = vs[term]
  if axis == 2
    value = ws[term]
  value

-> ffklf_axis_set(us, vs, ws, term, axis, value) (i64[] i64[] i64[] i64 i64 i64) i64
  if axis == 0
    us[term] = value
  if axis == 1
    vs[term] = value
  if axis == 2
    ws[term] = value
  value

-> ffklf_left(us, vs, ws, term, axis) (i64[] i64[] i64[] i64 i64) i64
  value = vs[term] ## i64
  if axis == 1 || axis == 2
    value = us[term]
  value

-> ffklf_right(us, vs, ws, term, axis) (i64[] i64[] i64[] i64 i64) i64
  value = ws[term] ## i64
  if axis == 2
    value = vs[term]
  value

-> ffklf_emit(axis, fixed, left, right, us, vs, ws, term) (i64 i64 i64 i64 i64[] i64[] i64[] i64) i64
  if fixed <= 0 || left <= 0 || right <= 0 || axis < 0 || axis > 2
    return 0
  if term < 0 || term >= us.size() || term >= vs.size() || term >= ws.size()
    return 0
  if axis == 0
    us[term] = fixed
    vs[term] = left
    ws[term] = right
  if axis == 1
    us[term] = left
    vs[term] = fixed
    ws[term] = right
  if axis == 2
    us[term] = left
    vs[term] = right
    ws[term] = fixed
  1

-> ffklf_pivot(kernel) (i64) i64
  if kernel <= 0
    return 0 - 1
  pivot = 0 ## i64
  bit = 1 ## i64
  while bit < 63
    if ((kernel >> bit) & 1) != 0
      pivot = bit
    bit += 1
  pivot

-> ffklf_project_factor(value, kernel, pivot) (i64 i64 i64) i64
  if ((value >> pivot) & 1) != 0
    return value ^ kernel
  value

-> ffklf_same(us, vs, ws, left, other_u, other_v, other_w, right) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  if us[left] == other_u[right] && vs[left] == other_v[right] && ws[left] == other_w[right]
    return 1
  0

-> ffklf_before(u0, v0, w0, u1, v1, w1) (i64 i64 i64 i64 i64 i64) i64
  if u0 < u1
    return 1
  if u0 > u1
    return 0
  if v0 < v1
    return 1
  if v0 > v1
    return 0
  if w0 < w1
    return 1
  0

-> ffklf_sort(us, vs, ws, count) (i64[] i64[] i64[] i64) i64
  i = 1 ## i64
  while i < count
    u = us[i] ## i64
    v = vs[i] ## i64
    w = ws[i] ## i64
    j = i ## i64
    while j > 0 && ffklf_before(u,v,w,us[j-1],vs[j-1],ws[j-1]) == 1
      us[j] = us[j-1]
      vs[j] = vs[j-1]
      ws[j] = ws[j-1]
      j -= 1
    us[j] = u
    vs[j] = v
    ws[j] = w
    i += 1
  count

-> ffklf_contains(us, vs, ws, count, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  i = 0 ## i64
  while i < count
    if us[i] == u && vs[i] == v && ws[i] == w
      return i
    i += 1
  0 - 1

-> ffklf_distinct(us, vs, ws, count) (i64[] i64[] i64[] i64) i64
  i = 0 ## i64
  while i < count
    if us[i] <= 0 || vs[i] <= 0 || ws[i] <= 0
      return 0
    j = i + 1 ## i64
    while j < count
      if us[i] == us[j] && vs[i] == vs[j] && ws[i] == ws[j]
        return 0
      j += 1
    i += 1
  1

-> ffklf_distance(left_u, left_v, left_w, left_count, right_u, right_v, right_w, right_count) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  common = 0 ## i64
  i = 0 ## i64
  while i < left_count
    if ffklf_contains(right_u,right_v,right_w,right_count,left_u[i],left_v[i],left_w[i]) >= 0
      common += 1
    i += 1
  left_count + right_count - common - common

-> ffklf_clear(values, count) (i64[] i64) i64
  i = 0 ## i64
  while i < count
    values[i] = 0
    i += 1
  count

# Build one endpoint. `selected` contains distinct ordinals in the sorted
# quotient presentation; toggling an ordinal chooses the other lift of that
# term.  The residual is represented as a list of rank-one matrix atoms so the
# shared minimal matrix factorizer can consume it without a packed-width cap.
-> ffklf_materialize(source_u, source_v, source_w, source_count, axis, kernel, selected, selected_count, out_u, out_v, out_w, meta) (i64[] i64[] i64[] i64 i64 i64 i64[] i64 i64[] i64[] i64[] i64[]) i64
  if source_count < 1 || source_u.size() < source_count || source_v.size() < source_count || source_w.size() < source_count
    return 0
  if axis < 0 || axis > 2 || kernel <= 0 || selected_count < 0 || selected.size() < selected_count || meta.size() < 12
    return 0
  z = ffklf_clear(meta,12) ## i64
  pivot = ffklf_pivot(kernel) ## i64
  if pivot < 0
    return 0

  projected_u = i64[source_count]
  projected_v = i64[source_count]
  projected_w = i64[source_count]
  atom_capacity = source_count + selected_count
  atom_left = i64[atom_capacity]
  atom_right = i64[atom_capacity]
  atom_count = 0 ## i64
  projected_count = 0 ## i64
  term = 0 ## i64
  while term < source_count
    if source_u[term] <= 0 || source_v[term] <= 0 || source_w[term] <= 0
      return 0
    factor = ffklf_axis_get(source_u,source_v,source_w,term,axis) ## i64
    lift = (factor >> pivot) & 1 ## i64
    projected = ffklf_project_factor(factor,kernel,pivot) ## i64
    if lift != 0
      atom_left[atom_count] = ffklf_left(source_u,source_v,source_w,term,axis)
      atom_right[atom_count] = ffklf_right(source_u,source_v,source_w,term,axis)
      atom_count += 1
    if projected != 0
      u = source_u[term] ## i64
      v = source_v[term] ## i64
      w = source_w[term] ## i64
      if axis == 0
        u = projected
      if axis == 1
        v = projected
      if axis == 2
        w = projected
      found = ffklf_contains(projected_u,projected_v,projected_w,projected_count,u,v,w) ## i64
      if found >= 0
        projected_count -= 1
        projected_u[found] = projected_u[projected_count]
        projected_v[found] = projected_v[projected_count]
        projected_w[found] = projected_w[projected_count]
      else
        projected_u[projected_count] = u
        projected_v[projected_count] = v
        projected_w[projected_count] = w
        projected_count += 1
    term += 1
  z = ffklf_sort(projected_u,projected_v,projected_w,projected_count)

  # Validate the recipe before changing the residual. Duplicate ordinals would
  # silently cancel algebraically but are rejected as malformed replay data.
  pick = 0 ## i64
  while pick < selected_count
    ordinal = selected[pick] ## i64
    if ordinal < 0 || ordinal >= projected_count
      return 0
    earlier = 0 ## i64
    while earlier < pick
      if selected[earlier] == ordinal
        return 0
      earlier += 1
    pick += 1
  meta[10] = 1

  pick = 0
  while pick < selected_count
    ordinal = selected[pick]
    factor = ffklf_axis_get(projected_u,projected_v,projected_w,ordinal,axis)
    z = ffklf_axis_set(projected_u,projected_v,projected_w,ordinal,axis,factor ^ kernel)
    atom_left[atom_count] = ffklf_left(projected_u,projected_v,projected_w,ordinal,axis)
    atom_right[atom_count] = ffklf_right(projected_u,projected_v,projected_w,ordinal,axis)
    atom_count += 1
    pick += 1

  correction_left = i64[63]
  correction_right = i64[63]
  correction_rank = ffsm_rank_factor_matrix(atom_left,atom_right,atom_count,correction_left,correction_right) ## i64
  if correction_rank < 0
    return 0
  endpoint_rank = projected_count + correction_rank ## i64
  if out_u.size() < endpoint_rank || out_v.size() < endpoint_rank || out_w.size() < endpoint_rank
    return 0
  term = 0
  while term < projected_count
    out_u[term] = projected_u[term]
    out_v[term] = projected_v[term]
    out_w[term] = projected_w[term]
    term += 1
  factor = 0 ## i64
  while factor < correction_rank
    if ffklf_emit(axis,kernel,correction_left[factor],correction_right[factor],out_u,out_v,out_w,projected_count+factor) != 1
      return 0
    factor += 1
  z = ffklf_sort(out_u,out_v,out_w,endpoint_rank)
  if ffklf_distinct(out_u,out_v,out_w,endpoint_rank) != 1
    return 0

  meta[0] = projected_count
  meta[1] = atom_count
  meta[2] = correction_rank
  meta[3] = endpoint_rank
  meta[4] = selected_count
  meta[5] = ffklf_distance(source_u,source_v,source_w,source_count,out_u,out_v,out_w,endpoint_rank)
  meta[7] = pivot
  meta[8] = fftc_density(source_u,source_v,source_w,source_count)
  meta[9] = fftc_density(out_u,out_v,out_w,endpoint_rank)
  if fftc_local_exact(source_u,source_v,source_w,source_count,out_u,out_v,out_w,endpoint_rank) != 1
    return 0
  meta[6] = 1
  endpoint_rank

# Apply a stored disjoint zero relation in either orientation. This is the
# durable replay surface: left->right and right->left are the same involution,
# while a partial/mixed state fails closed.
-> ffklf_apply_relation(state_u, state_v, state_w, state_count, capacity, left_u, left_v, left_w, left_count, right_u, right_v, right_w, right_count, out_u, out_v, out_w, replay_meta) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[]) i64
  if state_count < 1 || capacity < state_count || state_u.size() < state_count || state_v.size() < state_count || state_w.size() < state_count
    return 0
  if left_count < 1 || right_count < 1 || left_u.size() < left_count || left_v.size() < left_count || left_w.size() < left_count || right_u.size() < right_count || right_v.size() < right_count || right_w.size() < right_count
    return 0
  if out_u.size() < capacity || out_v.size() < capacity || out_w.size() < capacity || replay_meta.size() < 8
    return 0
  z = ffklf_clear(replay_meta,8) ## i64
  if ffklf_distinct(left_u,left_v,left_w,left_count) != 1 || ffklf_distinct(right_u,right_v,right_w,right_count) != 1
    return 0
  if fftc_local_exact(left_u,left_v,left_w,left_count,right_u,right_v,right_w,right_count) != 1
    return 0
  i = 0 ## i64
  while i < left_count
    if ffklf_contains(right_u,right_v,right_w,right_count,left_u[i],left_v[i],left_w[i]) >= 0
      return 0
    i += 1

  left_present = 1 ## i64
  right_present = 1 ## i64
  i = 0
  while i < left_count
    if ffklf_contains(state_u,state_v,state_w,state_count,left_u[i],left_v[i],left_w[i]) < 0
      left_present = 0
    i += 1
  i = 0
  while i < right_count
    if ffklf_contains(state_u,state_v,state_w,state_count,right_u[i],right_v[i],right_w[i]) < 0
      right_present = 0
    i += 1
  if left_present == right_present
    return 0

  remove_u = left_u
  remove_v = left_v
  remove_w = left_w
  remove_count = left_count ## i64
  add_u = right_u
  add_v = right_v
  add_w = right_w
  add_count = right_count ## i64
  if right_present == 1
    remove_u = right_u
    remove_v = right_v
    remove_w = right_w
    remove_count = right_count
    add_u = left_u
    add_v = left_v
    add_w = left_w
    add_count = left_count
    replay_meta[0] = 1

  final_count = state_count - remove_count + add_count ## i64
  if final_count < 1 || final_count > capacity
    return 0
  i = 0
  while i < state_count
    out_u[i] = state_u[i]
    out_v[i] = state_v[i]
    out_w[i] = state_w[i]
    i += 1
  count = state_count ## i64
  i = 0
  while i < remove_count
    found = ffklf_contains(out_u,out_v,out_w,count,remove_u[i],remove_v[i],remove_w[i]) ## i64
    if found < 0
      return 0
    count -= 1
    out_u[found] = out_u[count]
    out_v[found] = out_v[count]
    out_w[found] = out_w[count]
    i += 1
  i = 0
  while i < add_count
    if ffklf_contains(out_u,out_v,out_w,count,add_u[i],add_v[i],add_w[i]) >= 0
      return 0
    out_u[count] = add_u[i]
    out_v[count] = add_v[i]
    out_w[count] = add_w[i]
    count += 1
    i += 1
  z = ffklf_sort(out_u,out_v,out_w,count)
  if count != final_count || ffklf_distinct(out_u,out_v,out_w,count) != 1
    return 0
  replay_meta[1] = remove_count
  replay_meta[2] = add_count
  replay_meta[3] = count
  replay_meta[4] = ffklf_distance(state_u,state_v,state_w,state_count,out_u,out_v,out_w,count)
  if fftc_local_exact(state_u,state_v,state_w,state_count,out_u,out_v,out_w,count) != 1
    return 0
  replay_meta[5] = 1
  count
