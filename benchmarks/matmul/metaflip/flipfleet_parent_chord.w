# Parent-guided chord splits for FlipFleet.
#
# If a term from parent A and a term from parent B agree on two factors, their
# three-point line is an exact zero circuit over GF(2):
#
#   (x,a,b) + (y,a,b) + (x^y,a,b) = 0
#
# (and likewise on the other two axes).  Toggling that circuit in A removes an
# A-only endpoint and inserts the B-only endpoint plus its completion.  This is
# algebraically the ordinary +1 split, but the second parent chooses the chord,
# turning a blind split into a cheap, directed basin bridge.

use metaflip_worker

-> ffpc_same(u0, v0, w0, u1, v1, w1) (i64 i64 i64 i64 i64 i64) i64
  if u0 == u1 && v0 == v1 && w0 == w1
    return 1
  0

-> ffpc_contains(us, vs, ws, count, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  i = 0 ## i64
  while i < count
    if ffpc_same(us[i], vs[i], ws[i], u, v, w) == 1
      return 1
    i += 1
  0

# Return the changing axis, or -1 unless exactly two factors agree.
-> ffpc_axis(u0, v0, w0, u1, v1, w1) (i64 i64 i64 i64 i64 i64) i64
  same_u = 0 ## i64
  same_v = 0 ## i64
  same_w = 0 ## i64
  if u0 == u1
    same_u = 1
  if v0 == v1
    same_v = 1
  if w0 == w1
    same_w = 1
  if same_u + same_v + same_w != 2
    return 0 - 1
  if same_u == 0
    return 0
  if same_v == 0
    return 1
  2

-> ffpc_completion(u0, v0, w0, u1, v1, w1, axis, out) (i64 i64 i64 i64 i64 i64 i64 i64[]) i64
  if out.size() < 3 || axis < 0 || axis > 2
    return 0
  out[0] = u0
  out[1] = v0
  out[2] = w0
  if axis == 0
    out[0] = u0 ^ u1
  if axis == 1
    out[1] = v0 ^ v1
  if axis == 2
    out[2] = w0 ^ w1
  if out[0] == 0 || out[1] == 0 || out[2] == 0
    return 0
  1

-> ffpc_toggle_plain(us, vs, ws, rank, capacity, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
  i = 0 ## i64
  while i < rank
    if ffpc_same(us[i], vs[i], ws[i], u, v, w) == 1
      us[i] = us[rank - 1]
      vs[i] = vs[rank - 1]
      ws[i] = ws[rank - 1]
      return rank - 1
    i += 1
  if rank >= capacity
    return 0 - 1
  us[rank] = u
  vs[rank] = v
  ws[rank] = w
  rank + 1

# Count directed A->B chords.  Endpoints must be exclusive to their parent;
# otherwise the move is a no-op, an immediate reversal, or ordinary closure
# that A could already see without B.
-> ffpc_count(au, av, aw, arank, bu, bv, bw, brank) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  count = 0 ## i64
  ai = 0 ## i64
  while ai < arank
    if ffpc_contains(bu, bv, bw, brank, au[ai], av[ai], aw[ai]) == 0
      bi = 0 ## i64
      while bi < brank
        if ffpc_contains(au, av, aw, arank, bu[bi], bv[bi], bw[bi]) == 0
          axis = ffpc_axis(au[ai], av[ai], aw[ai], bu[bi], bv[bi], bw[bi]) ## i64
          if axis >= 0
            count += 1
        bi += 1
    ai += 1
  count

# Materialize one directed chord by ordinal.  meta receives:
# opportunities, selected A index, selected B index, axis, output rank,
# density, distance to parent B, and exact local-circuit flag.
-> ffpc_make(au, av, aw, arank, bu, bv, bw, brank, ordinal, out_u, out_v, out_w, capacity, meta) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64 i64[]) i64
  opportunities = ffpc_count(au, av, aw, arank, bu, bv, bw, brank) ## i64
  if opportunities < 1 || capacity < arank + 1 || meta.size() < 8
    return 0
  chosen = ordinal % opportunities ## i64
  if chosen < 0
    chosen += opportunities
  seen = 0 ## i64
  selected_a = 0 - 1 ## i64
  selected_b = 0 - 1 ## i64
  selected_axis = 0 - 1 ## i64
  ai = 0 ## i64
  while ai < arank && selected_a < 0
    if ffpc_contains(bu, bv, bw, brank, au[ai], av[ai], aw[ai]) == 0
      bi = 0 ## i64
      while bi < brank && selected_a < 0
        if ffpc_contains(au, av, aw, arank, bu[bi], bv[bi], bw[bi]) == 0
          axis = ffpc_axis(au[ai], av[ai], aw[ai], bu[bi], bv[bi], bw[bi]) ## i64
          if axis >= 0
            if seen == chosen
              selected_a = ai
              selected_b = bi
              selected_axis = axis
            seen += 1
        bi += 1
    ai += 1
  if selected_a < 0
    return 0

  i = 0
  while i < arank
    out_u[i] = au[i]
    out_v[i] = av[i]
    out_w[i] = aw[i]
    i += 1
  completion = i64[3]
  if ffpc_completion(au[selected_a], av[selected_a], aw[selected_a], bu[selected_b], bv[selected_b], bw[selected_b], selected_axis, completion) == 0
    return 0
  rank = arank ## i64
  rank = ffpc_toggle_plain(out_u, out_v, out_w, rank, capacity, au[selected_a], av[selected_a], aw[selected_a])
  if rank < 0
    return 0
  rank = ffpc_toggle_plain(out_u, out_v, out_w, rank, capacity, bu[selected_b], bv[selected_b], bw[selected_b])
  if rank < 0
    return 0
  rank = ffpc_toggle_plain(out_u, out_v, out_w, rank, capacity, completion[0], completion[1], completion[2])
  if rank < 1
    return 0

  density = 0 ## i64
  common = 0 ## i64
  i = 0
  while i < rank
    density += ffw_popcount(out_u[i]) + ffw_popcount(out_v[i]) + ffw_popcount(out_w[i])
    if ffpc_contains(bu, bv, bw, brank, out_u[i], out_v[i], out_w[i]) == 1
      common += 1
    i += 1
  meta[0] = opportunities
  meta[1] = selected_a
  meta[2] = selected_b
  meta[3] = selected_axis
  meta[4] = rank
  meta[5] = density
  meta[6] = rank + brank - 2 * common
  meta[7] = 1
  rank

# Cold-path worker wrapper with independent full-tensor exact gating.
-> ffpc_state_into(dst, parent_a, parent_b, ordinal, seed) (i64[] i64[] i64[] i64 i64) i64
  if ffw_valid(parent_a) == 0 || ffw_valid(parent_b) == 0
    return 0
  n = parent_a[2] ## i64
  if parent_b[2] != n || ffw_verify_best_exact(parent_a, n) == 0 || ffw_verify_best_exact(parent_b, n) == 0
    return 0
  arank = ffw_best_rank(parent_a) ## i64
  brank = ffw_best_rank(parent_b) ## i64
  capacity = parent_a[4] ## i64
  if ffw_valid(dst) == 1 && dst[4] > capacity
    capacity = dst[4]
  au = i64[capacity]
  av = i64[capacity]
  aw = i64[capacity]
  bu = i64[parent_b[4]]
  bv = i64[parent_b[4]]
  bw = i64[parent_b[4]]
  if ffw_export_best(parent_a, au, av, aw) != arank || ffw_export_best(parent_b, bu, bv, bw) != brank
    return 0
  out_u = i64[capacity]
  out_v = i64[capacity]
  out_w = i64[capacity]
  meta = i64[8]
  rank = ffpc_make(au, av, aw, arank, bu, bv, bw, brank, ordinal, out_u, out_v, out_w, capacity, meta) ## i64
  if rank < 1
    return 0
  loaded = ffw_init_terms_cap(dst, out_u, out_v, out_w, rank, n, capacity, seed, parent_a[17], parent_a[15], parent_a[18], parent_a[19]) ## i64
  if loaded == rank && ffw_verify_current_exact(dst, n) == 1
    return rank
  0
