# Randomized frozen-core / exact SAT fringe repair.
#
# One bounded CPU coordinator chooses k live terms as the mutable fringe and
# freezes everything else.  The selected partial tensor is sent to the exact
# Brent-equation encoder in flipfleet_sat_destroy_repair, asking for k-1 (or
# fewer) replacement terms.  Every returned splice is independently checked
# against all n^6 coefficients before admission.
#
# Selection mode 0 is uniform.  Mode 1 starts at a random term and greedily
# minimizes the joint U/V/W support cube, producing much smaller SAT instances
# while still randomizing the frozen core on every attempt.

use metaflip_worker
use flipfleet_sat_destroy_repair

-> fffsat_next(rng) (i64[]) i64
  rng[0] = (rng[0] * 6364136223846793005 + 1442695040888963407) & 9223372036854775807
  rng[0]

-> fffsat_selected_contains(selected, count, value) (i64[] i64 i64) i64
  i = 0 ## i64
  while i < count
    if selected[i] == value
      return 1
    i += 1
  0

-> fffsat_select_uniform(rank, k, seed, selected) (i64 i64 i64 i64[]) i64
  if k < 1 || k > rank || selected.size() < k
    return 0
  positions = i64[rank]
  i = 0 ## i64
  while i < rank
    positions[i] = i
    i += 1
  rng = i64[1]
  rng[0] = seed & 9223372036854775807
  i = 0
  while i < k
    remaining = rank - i ## i64
    pick = i + (fffsat_next(rng) % remaining) ## i64
    swap = positions[i] ## i64
    positions[i] = positions[pick]
    positions[pick] = swap
    selected[i] = positions[i]
    i += 1
  k

-> fffsat_select_clustered(st, k, seed, selected) (i64[] i64 i64 i64[]) i64
  if ffw_valid(st) == 0
    return 0
  rank = st[6] ## i64
  if k < 1 || k > rank || selected.size() < k
    return 0
  capacity = st[4] ## i64
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  if ffw_export_current(st, us, vs, ws) != rank
    return 0
  rng = i64[1]
  rng[0] = seed & 9223372036854775807
  first = fffsat_next(rng) % rank ## i64
  selected[0] = first
  union_u = us[first] ## i64
  union_v = vs[first] ## i64
  union_w = ws[first] ## i64
  count = 1 ## i64
  while count < k
    start = fffsat_next(rng) % rank ## i64
    best = 0 - 1 ## i64
    best_cells = 9223372036854775807 ## i64
    best_support = 9223372036854775807 ## i64
    offset = 0 ## i64
    while offset < rank
      candidate = (start + offset) % rank ## i64
      if fffsat_selected_contains(selected, count, candidate) == 0
        cu = ffw_popcount(union_u | us[candidate]) ## i64
        cv = ffw_popcount(union_v | vs[candidate]) ## i64
        cw = ffw_popcount(union_w | ws[candidate]) ## i64
        cells = cu * cv * cw ## i64
        support = cu + cv + cw ## i64
        if best < 0 || cells < best_cells || (cells == best_cells && support < best_support)
          best = candidate
          best_cells = cells
          best_support = support
      offset += 1
    if best < 0
      return 0
    selected[count] = best
    union_u = union_u | us[best]
    union_v = union_v | vs[best]
    union_w = union_w | ws[best]
    count += 1
  count

-> fffsat_select(st, k, seed, mode, selected) (i64[] i64 i64 i64 i64[]) i64
  if ffw_valid(st) == 0
    return 0
  if mode == 1
    return fffsat_select_clustered(st, k, seed, selected)
  fffsat_select_uniform(st[6], k, seed, selected)

-> fffsat_extract(st, selected, k, su, sv, sw) (i64[] i64[] i64 i64[] i64[] i64[]) i64
  if ffw_valid(st) == 0 || k < 1 || selected.size() < k || su.size() < k || sv.size() < k || sw.size() < k
    return 0
  rank = st[6] ## i64
  i = 0 ## i64
  while i < k
    position = selected[i] ## i64
    if position < 0 || position >= rank
      return 0
    j = 0 ## i64
    while j < i
      if selected[j] == position
        return 0
      j += 1
    slot = st[st[50] + position] ## i64
    su[i] = st[st[44] + slot]
    sv[i] = st[st[45] + slot]
    sw[i] = st[st[46] + slot]
    i += 1
  k

# Compute the exact query size without materializing the DIMACS body.
# meta: U/V/W support, cells, variables, clauses, k, want.
-> fffsat_query_dimensions(st, selected, k, want, meta) (i64[] i64[] i64 i64 i64[]) i64
  if ffw_valid(st) == 0 || meta.size() < 8 || want < 1 || want >= k
    return 0
  width = st[2] * st[2] ## i64
  su = i64[k]
  sv = i64[k]
  sw = i64[k]
  if fffsat_extract(st, selected, k, su, sv, sw) != k
    return 0
  ucoords = i64[width]
  vcoords = i64[width]
  wcoords = i64[width]
  local_u = i64[k]
  local_v = i64[k]
  local_w = i64[k]
  target = i64[ffsdr_tensor_words(width * width * width)]
  window = i64[12]
  if ffsdr_prepare_window(su, sv, sw, k, width, width, width, ucoords, vcoords, wcoords, local_u, local_v, local_w, target, window) != 1
    return 0
  cells = window[3] ## i64
  primary = want * (window[0] + window[1] + window[2]) ## i64
  parity = 0 ## i64
  if want > 1
    parity = cells * (want - 1)
  variables = primary + cells * want + parity ## i64
  clauses_per_cell = want * 4 + 1 ## i64
  if want > 1
    clauses_per_cell += (want - 1) * 4
  meta[0] = window[0]
  meta[1] = window[1]
  meta[2] = window[2]
  meta[3] = cells
  meta[4] = variables
  meta[5] = cells * clauses_per_cell
  meta[6] = k
  meta[7] = want
  1

# One deadline-bounded attempt.  This function is intentionally synchronous;
# production calls it only from the single coordinator/SAT child, never from a
# hot walker.  meta: selection mode, k, want, support U/V/W, cells, vars,
# clauses, solver status, decoded terms, applied rank, exact gate.
-> fffsat_attempt(st, k, seed, mode, solver_command, timeout_s, stem, meta) (i64[] i64 i64 i64 String i64 String i64[]) i64
  if ffw_valid(st) == 0 || meta.size() < 13 || ffw_verify_current_exact(st, st[2]) == 0
    return 0
  rank = st[6] ## i64
  if k < 2 || k > rank || k > 32
    return 0
  want = k - 1 ## i64
  selected = i64[k]
  if fffsat_select(st, k, seed, mode, selected) != k
    return 0
  dimensions = i64[8]
  if fffsat_query_dimensions(st, selected, k, want, dimensions) != 1
    return 0
  su = i64[k]
  sv = i64[k]
  sw = i64[k]
  if fffsat_extract(st, selected, k, su, sv, sw) != k
    return 0
  out_u = i64[k]
  out_v = i64[k]
  out_w = i64[k]
  sat_meta = i64[12]
  width = st[2] * st[2] ## i64
  replacement = ffsdr_solve_selected_external(su, sv, sw, k, want, width, width, width, solver_command, timeout_s, stem, out_u, out_v, out_w, sat_meta) ## i64
  meta[0] = mode
  meta[1] = k
  meta[2] = want
  meta[3] = dimensions[0]
  meta[4] = dimensions[1]
  meta[5] = dimensions[2]
  meta[6] = dimensions[3]
  meta[7] = dimensions[4]
  meta[8] = dimensions[5]
  meta[9] = sat_meta[6]
  meta[10] = replacement
  if replacement < 1
    return 0
  applied = ffsdr_apply_current(st, selected, k, out_u, out_v, out_w, replacement) ## i64
  meta[11] = applied
  meta[12] = 0
  if applied > 0 && applied < rank && ffw_verify_current_exact(st, st[2]) == 1
    meta[12] = 1
    return applied
  0
