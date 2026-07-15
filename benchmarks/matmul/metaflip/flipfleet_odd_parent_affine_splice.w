# Odd-parent affine XOR splices over GF(2).
#
# Every exact decomposition in a bank represents the same tensor T.  The
# parity union of an odd number of parents therefore represents T again:
#
#   A XOR B XOR C = T XOR T XOR T = T,
#
# while an even number represents zero.  The routines below canonicalize each
# term multiset by parity and lexicographic order, materialize an arbitrary odd
# parent selection, and provide exact set comparisons/distances for archive
# novelty.  Callers still independently reconstruct and n^6-gate every result.

use flipfleet_partial_automorphism_nullspace

-> ffoas_term_after(u0, v0, w0, u1, v1, w1) (i64 i64 i64 i64 i64 i64) i64
  if u0 > u1
    return 1
  if u0 == u1 && v0 > v1
    return 1
  if u0 == u1 && v0 == v1 && w0 > w1
    return 1
  0

-> ffoas_sort_terms(us, vs, ws, rank) (i64[] i64[] i64[] i64) i64
  gap = rank / 2 ## i64
  while gap > 0
    i = gap ## i64
    while i < rank
      u = us[i] ## i64
      v = vs[i] ## i64
      w = ws[i] ## i64
      j = i ## i64
      while j >= gap && ffoas_term_after(us[j - gap], vs[j - gap], ws[j - gap], u, v, w) == 1
        us[j] = us[j - gap]
        vs[j] = vs[j - gap]
        ws[j] = ws[j - gap]
        j -= gap
      us[j] = u
      vs[j] = v
      ws[j] = w
      i += 1
    gap /= 2
  rank

-> ffoas_canonicalize(raw_u, raw_v, raw_w, raw_count, out_u, out_v, out_w) (i64[] i64[] i64[] i64 i64[] i64[] i64[]) i64
  count = ffpan_parity_compact(raw_u, raw_v, raw_w, raw_count, out_u, out_v, out_w) ## i64
  if count < 0
    return count
  ffoas_sort_terms(out_u, out_v, out_w, count)
  count

-> ffoas_copy_slot(source_u, source_v, source_w, source_offset, target_u, target_v, target_w, target_offset, count) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64) i64
  i = 0 ## i64
  while i < count
    target_u[target_offset + i] = source_u[source_offset + i]
    target_v[target_offset + i] = source_v[source_offset + i]
    target_w[target_offset + i] = source_w[source_offset + i]
    i += 1
  count

# `bank_*` uses fixed-width slots.  `parent_ids` may contain repeats for
# algebraic regression tests, although production closure uses distinct ids.
-> ffoas_materialize(bank_u, bank_v, bank_w, stride, ranks, parent_ids, parent_count, raw_u, raw_v, raw_w, out_u, out_v, out_w) (i64[] i64[] i64[] i64 i64[] i64[] i64 i64[] i64[] i64[] i64[] i64[] i64[]) i64
  raw_count = 0 ## i64
  parent = 0 ## i64
  while parent < parent_count
    id = parent_ids[parent] ## i64
    if id < 0 || id >= ranks.size()
      return 0 - 1
    rank = ranks[id] ## i64
    if rank < 0 || raw_count + rank > raw_u.size() || raw_count + rank > raw_v.size() || raw_count + rank > raw_w.size()
      return 0 - 1
    ffoas_copy_slot(bank_u, bank_v, bank_w, id * stride, raw_u, raw_v, raw_w, raw_count, rank)
    raw_count += rank
    parent += 1
  ffoas_canonicalize(raw_u, raw_v, raw_w, raw_count, out_u, out_v, out_w)

-> ffoas_equal_slot(bank_u, bank_v, bank_w, offset, rank, us, vs, ws, count) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64) i64
  if rank != count
    return 0
  i = 0 ## i64
  while i < rank
    if bank_u[offset + i] != us[i] || bank_v[offset + i] != vs[i] || bank_w[offset + i] != ws[i]
      return 0
    i += 1
  1

# Inputs are canonical sets.  A merge computes exact symmetric-difference
# distance without a quadratic temporary used-array.
-> ffoas_distance_slot(bank_u, bank_v, bank_w, offset, rank, us, vs, ws, count) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64) i64
  left = 0 ## i64
  right = 0 ## i64
  common = 0 ## i64
  while left < rank && right < count
    bu = bank_u[offset + left] ## i64
    bv = bank_v[offset + left] ## i64
    bw = bank_w[offset + left] ## i64
    cu = us[right] ## i64
    cv = vs[right] ## i64
    cw = ws[right] ## i64
    if bu == cu && bv == cv && bw == cw
      common += 1
      left += 1
      right += 1
    else
      if ffoas_term_after(bu, bv, bw, cu, cv, cw) == 1
        right += 1
      else
        left += 1
  rank + count - 2 * common

# Symmetric difference of two canonical term sets.  This is the hot primitive
# for a Gray walk over an odd affine hull: toggling one affine coordinate
# applies parent_0 XOR parent_i, so two sorted merge passes update the exact
# endpoint without rebuilding the selected-parent union from scratch.
-> ffoas_xor_sorted_slot(left_u, left_v, left_w, left_count, right_u, right_v, right_w, right_offset, right_count, out_u, out_v, out_w) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64 i64[] i64[] i64[]) i64
  left = 0 ## i64
  right = 0 ## i64
  out_count = 0 ## i64
  while left < left_count || right < right_count
    take_left = 0 ## i64
    take_right = 0 ## i64
    if right >= right_count
      take_left = 1
    else
      if left >= left_count
        take_right = 1
      else
        lu = left_u[left] ## i64
        lv = left_v[left] ## i64
        lw = left_w[left] ## i64
        ru = right_u[right_offset + right] ## i64
        rv = right_v[right_offset + right] ## i64
        rw = right_w[right_offset + right] ## i64
        if lu == ru && lv == rv && lw == rw
          left += 1
          right += 1
        else
          if ffoas_term_after(lu, lv, lw, ru, rv, rw) == 1
            take_right = 1
          else
            take_left = 1
    if take_left == 1
      if out_count >= out_u.size() || out_count >= out_v.size() || out_count >= out_w.size()
        return 0 - 1
      out_u[out_count] = left_u[left]
      out_v[out_count] = left_v[left]
      out_w[out_count] = left_w[left]
      out_count += 1
      left += 1
    if take_right == 1
      if out_count >= out_u.size() || out_count >= out_v.size() || out_count >= out_w.size()
        return 0 - 1
      out_u[out_count] = right_u[right_offset + right]
      out_v[out_count] = right_v[right_offset + right]
      out_w[out_count] = right_w[right_offset + right]
      out_count += 1
      right += 1
  out_count

-> ffoas_fingerprint(us, vs, ws, rank, out) (i64[] i64[] i64[] i64 i64[]) i64
  first = 7046029254386353131 ## i64
  second = 1442695040888963407 ## i64
  i = 0 ## i64
  while i < rank
    first = (first ^ us[i]) * 6364136223846793005 + vs[i] * 257 + ws[i] * 65537
    second = (second ^ ws[i]) * 3202034522624059733 + us[i] * 263 + vs[i] * 131071
    i += 1
  out[0] = first ^ rank
  out[1] = second ^ (rank * 8191)
  1

-> ffoas_choose(n, k) (i64 i64) i64
  if k < 0 || n < k
    return 0
  if k == 0 || k == n
    return 1
  if k > n - k
    k = n - k
  result = 1 ## i64
  i = 1 ## i64
  while i <= k
    result = result * (n - k + i) / i
    i += 1
  result
