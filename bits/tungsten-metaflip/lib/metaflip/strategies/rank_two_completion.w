# Offline computed rank-at-most-two completion.
#
# This is the next rung above rank_one_completion.  For k selected live terms
# A and k-3 distinct candidate terms B, it computes
#
#     E = xor(A) xor xor(B)
#
# in the same compact UxV-row / W-mask slice representation.  If tensor E has
# rank zero, one, or two, its missing factors are synthesized exactly.  The
# rank-two case yields A -> B+q1+q2, a net k->k-1 replacement even when q1
# and q2 were absent from the candidate pool.
#
# The exact recognizer is adapted from the proven rectangular two-term repair.
# E's U-flattening must have rank at most two.  Over GF(2), a two-dimensional
# slice space has only the three nonzero bases {A,B}, {A,A+B}, {B,A+B}; each
# is accepted only when both VxW basis matrices are rank one.  A rank-one U
# flattening reduces to an exact VxW matrix-rank-at-most-two decomposition.
# All workspaces are allocated once per search, not once per combination.

use rank_one_completion

-> ffroc2_rows_equal(left, left_offset, right, right_offset, count) (i64[] i64 i64[] i64 i64) i64
  i = 0 ## i64
  while i < count
    if left[left_offset+i] != right[right_offset+i]
      return 0
    i += 1
  1

-> ffroc2_rows_xor_equal(value, value_offset, left, left_offset, right, right_offset, count) (i64[] i64 i64[] i64 i64[] i64 i64) i64
  i = 0 ## i64
  while i < count
    if value[value_offset+i] != (left[left_offset+i] ^ right[right_offset+i])
      return 0
    i += 1
  1

-> ffroc2_rows_copy(source, source_offset, target, target_offset, count) (i64[] i64 i64[] i64 i64) i64
  i = 0 ## i64
  while i < count
    target[target_offset+i] = source[source_offset+i]
    i += 1
  count

# Factor a nonzero VxW matrix of rank one. Rows are W masks.
# factor_work[offset]=V and factor_work[offset+1]=W.
-> ffroc2_matrix_rank_one(rows, row_offset, width, factor_work, factor_offset) (i64[] i64 i64 i64[] i64) i64
  v = 0 ## i64
  w = 0 ## i64
  r = 0 ## i64
  while r < width
    row = rows[row_offset+r] ## i64
    if row != 0
      if w == 0
        w = row
      else
        if row != w
          return 0
      v = v | (1 << r)
    r += 1
  if v == 0 || w == 0
    return 0
  factor_work[factor_offset] = v
  factor_work[factor_offset+1] = w
  1

# Decompose one VxW matrix of rank one or two.  Its row space consists only
# of 0, q1, q2, and q1+q2.  Return -1 above rank two.
-> ffroc2_matrix_rank_two(rows, row_offset, width, out_v, out_w) (i64[] i64 i64 i64[] i64[]) i64
  q1 = 0 ## i64
  q2 = 0 ## i64
  v1 = 0 ## i64
  v2 = 0 ## i64
  r = 0 ## i64
  while r < width
    row = rows[row_offset+r] ## i64
    code = 0 ## i64
    if row != 0
      if q1 == 0
        q1 = row
        code = 1
      else
        if row == q1
          code = 1
        else
          if q2 == 0
            q2 = row
            code = 2
          else
            if row == q2
              code = 2
            else
              if row == (q1 ^ q2)
                code = 3
              else
                return 0 - 1
    if (code & 1) != 0
      v1 = v1 | (1 << r)
    if (code & 2) != 0
      v2 = v2 | (1 << r)
    r += 1
  if q1 == 0
    return 0
  out_v[0] = v1
  out_w[0] = q1
  if q2 == 0
    return 1
  out_v[1] = v2
  out_w[1] = q2
  2

# Exact rank-at-most-two decomposition of compact square slices. `workspace`
# has 4*dim words: basis A, basis B, A+B, and U coefficient codes.
# decomp_meta: [0] U-flattening rank, [1] basis variant, [2] tensor rank.
-> ffroc2_decompose_slice(rows, dim, out_u, out_v, out_w, workspace, factor_work, decomp_meta) (i64[] i64 i64[] i64[] i64[] i64[] i64[] i64[]) i64
  decomp_meta[0] = 0
  decomp_meta[1] = 0
  decomp_meta[2] = 0
  basis_a = 0 ## i64
  basis_b = dim ## i64
  combo = dim * 2 ## i64
  coeff = dim * 3 ## i64
  have_a = 0 ## i64
  have_b = 0 ## i64
  a = 0 ## i64
  while a < dim
    source_offset = a * dim ## i64
    nonzero = 0 ## i64
    b = 0 ## i64
    while b < dim
      nonzero = nonzero | rows[source_offset+b]
      b += 1
    code = 0 ## i64
    if nonzero != 0
      if have_a == 0
        z = ffroc2_rows_copy(rows,source_offset,workspace,basis_a,dim) ## i64
        have_a = 1
        code = 1
      else
        if ffroc2_rows_equal(rows,source_offset,workspace,basis_a,dim) == 1
          code = 1
        else
          if have_b == 0
            z = ffroc2_rows_copy(rows,source_offset,workspace,basis_b,dim)
            have_b = 1
            code = 2
          else
            if ffroc2_rows_equal(rows,source_offset,workspace,basis_b,dim) == 1
              code = 2
            else
              if ffroc2_rows_xor_equal(rows,source_offset,workspace,basis_a,workspace,basis_b,dim) == 1
                code = 3
              else
                decomp_meta[0] = 3
                return 0 - 1
    workspace[coeff+a] = code
    a += 1

  if have_a == 0
    return 0

  if have_b == 0
    rank = ffroc2_matrix_rank_two(workspace,basis_a,dim,out_v,out_w) ## i64
    decomp_meta[0] = 1
    decomp_meta[1] = 10
    decomp_meta[2] = rank
    if rank < 1 || rank > 2
      return 0 - 1
    umask = 0 ## i64
    a = 0
    while a < dim
      if workspace[coeff+a] == 1
        umask = umask | (1 << a)
      a += 1
    i = 0 ## i64
    while i < rank
      out_u[i] = umask
      i += 1
    return rank

  # The two-dimensional slice space has precisely three unordered nonzero
  # basis choices over GF(2).
  decomp_meta[0] = 2
  b = 0
  while b < dim
    workspace[combo+b] = workspace[basis_a+b] ^ workspace[basis_b+b]
    b += 1
  variant = 0 ## i64
  while variant < 3
    left = basis_a ## i64
    right = basis_b ## i64
    if variant == 1
      right = combo
    if variant == 2
      left = basis_b
      right = combo
    if ffroc2_matrix_rank_one(workspace,left,dim,factor_work,0) == 1 && ffroc2_matrix_rank_one(workspace,right,dim,factor_work,2) == 1
      ul = 0 ## i64
      ur = 0 ## i64
      a = 0
      while a < dim
        alpha = workspace[coeff+a] & 1 ## i64
        beta = (workspace[coeff+a] >> 1) & 1 ## i64
        lc = alpha ## i64
        rc = beta ## i64
        if variant == 1
          lc = alpha ^ beta
          rc = beta
        if variant == 2
          lc = alpha ^ beta
          rc = alpha
        if lc != 0
          ul = ul | (1 << a)
        if rc != 0
          ur = ur | (1 << a)
        a += 1
      if ul != 0 && ur != 0
        out_u[0] = ul
        out_v[0] = factor_work[0]
        out_w[0] = factor_work[1]
        out_u[1] = ur
        out_v[1] = factor_work[2]
        out_w[1] = factor_work[3]
        decomp_meta[1] = variant
        decomp_meta[2] = 2
        return 2
    variant += 1
  decomp_meta[2] = 3
  0 - 1

-> ffroc2_verify_slice(rows, dim, us, vs, ws, count, rebuilt) (i64[] i64 i64[] i64[] i64[] i64 i64[]) i64
  z = ffroc_clear(rebuilt,dim*dim) ## i64
  i = 0 ## i64
  while i < count
    z = ffroc_toggle_slice(rebuilt,us[i],vs[i],ws[i],dim)
    i += 1
  i = 0
  while i < dim*dim
    if rebuilt[i] != rows[i]
      return 0
    i += 1
  1

-> ffroc2_materialize(st, selected, k, pool_u, pool_v, pool_w, chosen, replacement_count, factor_u, factor_v, factor_w, factor_count, out_state, capacity, seed) (i64[] i64[] i64 i64[] i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64[] i64 i64) i64
  old_rank = st[6] ## i64
  if capacity < old_rank
    return 0
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  rank = ffw_export_current(st,us,vs,ws) ## i64
  if rank != old_rank
    return 0
  source_u = i64[k]
  source_v = i64[k]
  source_w = i64[k]
  i = 0 ## i64
  while i < k
    slot = st[st[50]+selected[i]] ## i64
    source_u[i] = st[st[44]+slot]
    source_v[i] = st[st[45]+slot]
    source_w[i] = st[st[46]+slot]
    i += 1
  i = 0
  while i < k && rank >= 0
    rank = ffroc_toggle_plain(us,vs,ws,rank,capacity,source_u[i],source_v[i],source_w[i])
    i += 1
  i = 0
  while i < replacement_count && rank >= 0
    candidate = chosen[i] ## i64
    rank = ffroc_toggle_plain(us,vs,ws,rank,capacity,pool_u[candidate],pool_v[candidate],pool_w[candidate])
    i += 1
  i = 0
  while i < factor_count && rank >= 0
    rank = ffroc_toggle_plain(us,vs,ws,rank,capacity,factor_u[i],factor_v[i],factor_w[i])
    i += 1
  if rank < 1 || rank >= old_rank
    return 0
  loaded = ffw_init_terms_cap(out_state,us,vs,ws,rank,st[2],capacity,seed,0,1,1,1) ## i64
  if loaded == rank
    if ffw_verify_current_exact(out_state,st[2]) == 1 && ffw_verify_best_exact(out_state,st[2]) == 1
      return rank
  0

# meta layout:
# [0] tuples, [1] exact decomposition attempts, [2] zero, [3] rank one,
# [4] rank two, [5] rank >2, [6] compact rebuild gates, [7] full gates,
# [8] accepted, [9] final rank, [10..15] q1/q2 factors,
# [16] source rank, [17] replacement count, [18] budget exhausted.
-> ffroc2_enumerate(st, selected, k, pool_u, pool_v, pool_w, pool_count, replacement_count, start, depth, chosen, residual, factor_u, factor_v, factor_w, workspace, factor_work, decomp_meta, rebuilt, max_checks, out_state, capacity, seed, meta) (i64[] i64[] i64 i64[] i64[] i64[] i64 i64 i64 i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64[] i64 i64 i64[]) i64
  if meta[8] != 0
    return meta[9]
  if meta[0] >= max_checks
    meta[18] = 1
    return 0
  if depth == replacement_count
    meta[0] += 1
    meta[1] += 1
    factor_count = ffroc2_decompose_slice(residual,st[3],factor_u,factor_v,factor_w,workspace,factor_work,decomp_meta) ## i64
    if factor_count < 0
      meta[5] += 1
      return 0
    if factor_count == 0
      meta[2] += 1
    if factor_count == 1
      meta[3] += 1
    if factor_count == 2
      meta[4] += 1
    meta[6] += 1
    if ffroc2_verify_slice(residual,st[3],factor_u,factor_v,factor_w,factor_count,rebuilt) == 0
      return 0
    meta[7] += 1
    rank = ffroc2_materialize(st,selected,k,pool_u,pool_v,pool_w,chosen,replacement_count,factor_u,factor_v,factor_w,factor_count,out_state,capacity,seed+meta[0]) ## i64
    if rank > 0
      meta[8] = 1
      meta[9] = rank
      if factor_count > 0
        meta[10] = factor_u[0]
        meta[11] = factor_v[0]
        meta[12] = factor_w[0]
      if factor_count > 1
        meta[13] = factor_u[1]
        meta[14] = factor_v[1]
        meta[15] = factor_w[1]
      return rank
    return 0

  remaining = replacement_count - depth ## i64
  last = pool_count - remaining ## i64
  candidate = start ## i64
  while candidate <= last
    chosen[depth] = candidate
    z = ffroc_toggle_slice(residual,pool_u[candidate],pool_v[candidate],pool_w[candidate],st[3]) ## i64
    rank = ffroc2_enumerate(st,selected,k,pool_u,pool_v,pool_w,pool_count,replacement_count,candidate+1,depth+1,chosen,residual,factor_u,factor_v,factor_w,workspace,factor_work,decomp_meta,rebuilt,max_checks,out_state,capacity,seed,meta) ## i64
    z = ffroc_toggle_slice(residual,pool_u[candidate],pool_v[candidate],pool_w[candidate],st[3])
    if rank > 0
      return rank
    if meta[0] >= max_checks
      meta[18] = 1
      return 0
    candidate += 1
  0

-> ffroc2_search(st, selected, k, pool_u, pool_v, pool_w, pool_count, max_checks, out_state, capacity, seed, meta) (i64[] i64[] i64 i64[] i64[] i64[] i64 i64 i64[] i64 i64 i64[]) i64
  i = 0 ## i64
  while i < 19
    meta[i] = 0
    i += 1
  if ffw_valid(st) == 0
    return 0
  rank = st[6] ## i64
  replacement_count = k - 3 ## i64
  meta[16] = rank
  meta[17] = replacement_count
  if k < 4 || replacement_count < 1 || replacement_count > pool_count || max_checks < 1
    return 0
  if ffroc_selected_valid(selected,k,rank) == 0
    return 0
  if ffroc_pool_valid(pool_u,pool_v,pool_w,pool_count,st[3]) == 0
    return 0
  if capacity < rank || ffw_verify_current_exact(st,st[2]) == 0
    return 0
  residual = i64[ffroc_slice_words(st[2])]
  z = ffroc_clear(residual,ffroc_slice_words(st[2])) ## i64
  i = 0
  while i < k
    slot = st[st[50]+selected[i]] ## i64
    z = ffroc_toggle_slice(residual,st[st[44]+slot],st[st[45]+slot],st[st[46]+slot],st[3])
    i += 1
  chosen = i64[replacement_count]
  factor_u = i64[2]
  factor_v = i64[2]
  factor_w = i64[2]
  workspace = i64[st[3]*4]
  factor_work = i64[4]
  decomp_meta = i64[3]
  rebuilt = i64[ffroc_slice_words(st[2])]
  ffroc2_enumerate(st,selected,k,pool_u,pool_v,pool_w,pool_count,replacement_count,0,0,chosen,residual,factor_u,factor_v,factor_w,workspace,factor_work,decomp_meta,rebuilt,max_checks,out_state,capacity,seed,meta)
