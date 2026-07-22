# Offline computed rank-at-most-three completion.
#
# For k selected live terms A and k-4 distinct candidate terms B, compute
#
#     E = xor(A) xor xor(B).
#
# If E has tensor rank zero through three, synthesize its missing factors and
# materialize A -> B+E.  The nominal replacement has at most k-1 terms, so a
# successful independent full gate is a strict rank drop.  The source state is
# read-only.  Residuals use the compact UxV-row / W-mask representation shared
# by rank-one and rank-two completion.
#
# Recognition is complete for rank <=3 over GF(2).  Let d be the rank of the
# U-flattening (the VxW slice-space dimension):
#
#   d=1  factor the sole VxW matrix at matrix rank <=3;
#   d=2  test all three GL(2,2) bases, then the complete weight-three
#        relation.  The rank-one/rank-one case uses the width-independent
#        cross-rectangle identities Z=a*d and Z=c*b;
#   d=3  factor all seven nonzero slice combinations and enumerate all 168
#        ordered bases in GL(3,2).
#
# Every basis, coefficient, combination, matrix, factor, rebuild, selected
# source, and materialization workspace is allocated once by ffroc3_search.
# No candidate tuple allocates.

use rank_two_completion

-> ffroc3_slice_matches(rows, row_offset, basis, dim, code) (i64[] i64 i64[] i64 i64) i64
  b = 0 ## i64
  while b < dim
    value = 0 ## i64
    bit = 0 ## i64
    while bit < 3
      if ((code >> bit) & 1) != 0
        value = value ^ basis[bit*dim+b]
      bit += 1
    if rows[row_offset+b] != value
      return 0
    b += 1
  1

# Extract at most three independent U slices. basis stores three flattened
# VxW matrices and coeff[a] is the three-bit coordinate of U slice a.
-> ffroc3_slice_space(rows, dim, basis, coeff) (i64[] i64 i64[] i64[]) i64
  z = ffroc_clear(basis,3*dim) ## i64
  z = ffroc_clear(coeff,dim)
  rank = 0 ## i64
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
      candidate = 1 ## i64
      limit = 1 << rank ## i64
      while candidate < limit && code == 0
        if ffroc3_slice_matches(rows,source_offset,basis,dim,candidate) == 1
          code = candidate
        candidate += 1
      if code == 0
        if rank >= 3
          return 4
        b = 0
        while b < dim
          basis[rank*dim+b] = rows[source_offset+b]
          b += 1
        code = 1 << rank
        rank += 1
    coeff[a] = code
    a += 1
  rank

# Materialize all seven nonzero combinations of a three-matrix basis.  Code
# zero is retained as the cleared matrix at offset zero.
-> ffroc3_build_combos(basis, dim, combos) (i64[] i64 i64[]) i64
  z = ffroc_clear(combos,8*dim) ## i64
  code = 1 ## i64
  while code < 8
    row = 0 ## i64
    while row < dim
      value = 0 ## i64
      bit = 0 ## i64
      while bit < 3
        if ((code >> bit) & 1) != 0
          value = value ^ basis[bit*dim+row]
        bit += 1
      combos[code*dim+row] = value
      row += 1
    code += 1
  7

# Decompose one VxW matrix into zero through three rank-one terms. Rows are W
# masks. combo_v/combo_w use caller-selected offsets; row_basis has length 3.
-> ffroc3_matrix_rank_three(matrices, matrix_offset, width, combo_v, factor_offset, combo_w, row_basis) (i64[] i64 i64 i64[] i64 i64[] i64[]) i64
  z = ffroc_clear(row_basis,3) ## i64
  i = 0 ## i64
  while i < 3
    combo_v[factor_offset+i] = 0
    combo_w[factor_offset+i] = 0
    i += 1
  rank = 0 ## i64
  row = 0 ## i64
  while row < width
    value = matrices[matrix_offset+row] ## i64
    code = 0 ## i64
    if value != 0
      candidate = 1 ## i64
      limit = 1 << rank ## i64
      while candidate < limit && code == 0
        combined = 0 ## i64
        bit = 0 ## i64
        while bit < rank
          if ((candidate >> bit) & 1) != 0
            combined = combined ^ row_basis[bit]
          bit += 1
        if combined == value
          code = candidate
        candidate += 1
      if code == 0
        if rank >= 3
          return 0 - 1
        row_basis[rank] = value
        code = 1 << rank
        rank += 1
    bit = 0
    while bit < rank
      if ((code >> bit) & 1) != 0
        combo_v[factor_offset+bit] = combo_v[factor_offset+bit] | (1 << row)
      bit += 1
    row += 1
  bit = 0
  while bit < rank
    combo_w[factor_offset+bit] = row_basis[bit]
    bit += 1
  rank

-> ffroc3_factor_combos(combos, dim, combo_rank, combo_v, combo_w, row_basis) (i64[] i64 i64[] i64[] i64[] i64[]) i64
  z = ffroc_clear(combo_rank,8) ## i64
  z = ffroc_clear(combo_v,24)
  z = ffroc_clear(combo_w,24)
  code = 1 ## i64
  while code < 8
    combo_rank[code] = ffroc3_matrix_rank_three(combos,code*dim,dim,combo_v,code*3,combo_w,row_basis)
    code += 1
  7

# Solve a tiny basis change. codes[codes_offset...] contains an ordered
# independent basis in the original slice coordinates. out_u is cleared and
# receives its U masks.
-> ffroc3_transform_u(coeff, dim, codes, codes_offset, dimension, out_u, out_offset) (i64[] i64 i64[] i64 i64 i64[] i64) i64
  i = 0 ## i64
  while i < 3
    out_u[out_offset+i] = 0
    i += 1
  a = 0 ## i64
  while a < dim
    wanted = coeff[a] ## i64
    found = 0 ## i64
    lambda = 0 ## i64
    limit = 1 << dimension ## i64
    while lambda < limit && found == 0
      combined = 0 ## i64
      bit = 0 ## i64
      while bit < dimension
        if ((lambda >> bit) & 1) != 0
          combined = combined ^ codes[codes_offset+bit]
        bit += 1
      if combined == wanted
        found = 1
        bit = 0
        while bit < dimension
          if ((lambda >> bit) & 1) != 0
            out_u[out_offset+bit] = out_u[out_offset+bit] | (1 << a)
          bit += 1
      lambda += 1
    if found == 0
      return 0
    a += 1
  bit = 0
  while bit < dimension
    if out_u[out_offset+bit] == 0
      return 0
    bit += 1
  1

# Test one Z=zv*zw in the d=2 weight-three identity
# A=X+Z, B=Y+Z. matrix_work is [Z,A+Z,B+Z]; scratch[18..21] holds factors.
-> ffroc3_try_weight3_z(combos, a_offset, b_offset, ua, ub, zv, zw, dim, out_u, out_v, out_w, matrix_work, scratch) (i64[] i64 i64 i64 i64 i64 i64 i64 i64[] i64[] i64[] i64[] i64[]) i64
  row = 0 ## i64
  while row < dim
    zrow = 0 ## i64
    if ((zv >> row) & 1) != 0
      zrow = zw
    matrix_work[row] = zrow
    matrix_work[dim+row] = combos[a_offset+row] ^ zrow
    matrix_work[2*dim+row] = combos[b_offset+row] ^ zrow
    row += 1
  if ffroc2_matrix_rank_one(matrix_work,dim,dim,scratch,18) != 1
    return 0
  if ffroc2_matrix_rank_one(matrix_work,2*dim,dim,scratch,20) != 1
    return 0
  if ua == 0 || ub == 0 || (ua ^ ub) == 0 || zv == 0 || zw == 0
    return 0
  out_u[0] = ua
  out_v[0] = scratch[18]
  out_w[0] = scratch[19]
  out_u[1] = ub
  out_v[1] = scratch[20]
  out_w[1] = scratch[21]
  out_u[2] = ua ^ ub
  out_v[2] = zv
  out_w[2] = zw
  1

# Correct arbitrary-width rank-one/rank-one cross-rectangle completion.
# For A=a*b and B=c*d, Z=a*d (or symmetrically c*b) makes both A+Z and B+Z
# rank at most one.  There is no exponential mask scan and widths through 62
# are handled by the same i64 representation as the square workers.
-> ffroc3_d2_rank_one_cross(combos, a_code, b_code, ua, ub, dim, combo_v, combo_w, out_u, out_v, out_w, matrix_work, scratch, meta) (i64[] i64 i64 i64 i64 i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  av = combo_v[a_code*3] ## i64
  aw = combo_w[a_code*3] ## i64
  bv = combo_v[b_code*3] ## i64
  bw = combo_w[b_code*3] ## i64
  meta[4] += 1
  if ffroc3_try_weight3_z(combos,a_code*dim,b_code*dim,ua,ub,av,bw,dim,out_u,out_v,out_w,matrix_work,scratch) == 1
    return 3
  meta[4] += 1
  if ffroc3_try_weight3_z(combos,a_code*dim,b_code*dim,ua,ub,bv,aw,dim,out_u,out_v,out_w,matrix_work,scratch) == 1
    return 3
  0

# Complete d=2 weight-three case.  A rank-two anchor needs only the nine
# nonzero column-space x row-space rectangles.  Two rank-one anchors use the
# cross identity above. meta[4]=tested Z, meta[5]=anchor rank.
-> ffroc3_d2_weight3(combos, a_code, b_code, ua, ub, dim, combo_rank, combo_v, combo_w, out_u, out_v, out_w, matrix_work, scratch, meta) (i64[] i64 i64 i64 i64 i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  ra = combo_rank[a_code] ## i64
  rb = combo_rank[b_code] ## i64
  if ra < 1 || rb < 1 || ra > 2 || rb > 2
    return 0
  anchor = a_code ## i64
  anchor_rank = ra ## i64
  if rb == 2
    anchor = b_code
    anchor_rank = rb
  meta[5] = anchor_rank
  if anchor_rank == 2
    li = 0 ## i64
    while li < 3
      zv = combo_v[anchor*3] ## i64
      if li == 1
        zv = combo_v[anchor*3+1]
      if li == 2
        zv = combo_v[anchor*3] ^ combo_v[anchor*3+1]
      ri = 0 ## i64
      while ri < 3
        zw = combo_w[anchor*3] ## i64
        if ri == 1
          zw = combo_w[anchor*3+1]
        if ri == 2
          zw = combo_w[anchor*3] ^ combo_w[anchor*3+1]
        meta[4] += 1
        if ffroc3_try_weight3_z(combos,a_code*dim,b_code*dim,ua,ub,zv,zw,dim,out_u,out_v,out_w,matrix_work,scratch) == 1
          return 3
        ri += 1
      li += 1
    return 0
  if ra == 1 && rb == 1
    return ffroc3_d2_rank_one_cross(combos,a_code,b_code,ua,ub,dim,combo_v,combo_w,out_u,out_v,out_w,matrix_work,scratch,meta)
  0

# decomp_meta: [0] U-flatten rank, [1] case 10/20..22/29/30,
# [2] returned rank, [3] tested GL/basis choices, [4] tested Z,
# [5] weight-three anchor rank.
-> ffroc3_decompose_slice(rows, dim, out_u, out_v, out_w, basis, coeff, combos, combo_rank, combo_v, combo_w, matrix_work, scratch, decomp_meta) (i64[] i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  if dim < 1 || dim > 62
    return 0 - 1
  z = ffroc_clear(out_u,3) ## i64
  z = ffroc_clear(out_v,3)
  z = ffroc_clear(out_w,3)
  z = ffroc_clear(decomp_meta,6)
  dimension = ffroc3_slice_space(rows,dim,basis,coeff) ## i64
  decomp_meta[0] = dimension
  if dimension == 0
    return 0
  if dimension > 3
    decomp_meta[2] = 4
    return 0 - 1
  z = ffroc3_build_combos(basis,dim,combos)
  z = ffroc3_factor_combos(combos,dim,combo_rank,combo_v,combo_w,scratch)

  if dimension == 1
    rank = combo_rank[1] ## i64
    decomp_meta[1] = 10
    decomp_meta[2] = rank
    if rank < 1 || rank > 3
      return 0 - 1
    umask = 0 ## i64
    a = 0 ## i64
    while a < dim
      if coeff[a] != 0
        umask = umask | (1 << a)
      a += 1
    term = 0 ## i64
    while term < rank
      out_u[term] = umask
      out_v[term] = combo_v[3+term]
      out_w[term] = combo_w[3+term]
      term += 1
    return rank

  if dimension == 2
    best_rank = 4 ## i64
    best_variant = 0 ## i64
    variant = 0 ## i64
    while variant < 3
      left_code = 1 ## i64
      right_code = 2 ## i64
      if variant == 1
        right_code = 3
      if variant == 2
        left_code = 2
        right_code = 3
      decomp_meta[3] += 1
      left_rank = combo_rank[left_code] ## i64
      right_rank = combo_rank[right_code] ## i64
      if left_rank > 0 && right_rank > 0 && left_rank+right_rank <= 3 && left_rank+right_rank < best_rank
        scratch[3] = left_code
        scratch[4] = right_code
        if ffroc3_transform_u(coeff,dim,scratch,3,2,scratch,6) == 1
          at = 0 ## i64
          term = 0 ## i64
          while term < left_rank
            scratch[9+at] = scratch[6]
            scratch[12+at] = combo_v[left_code*3+term]
            scratch[15+at] = combo_w[left_code*3+term]
            at += 1
            term += 1
          term = 0
          while term < right_rank
            scratch[9+at] = scratch[7]
            scratch[12+at] = combo_v[right_code*3+term]
            scratch[15+at] = combo_w[right_code*3+term]
            at += 1
            term += 1
          best_rank = at
          best_variant = variant
      variant += 1
    if best_rank <= 3
      term = 0
      while term < best_rank
        out_u[term] = scratch[9+term]
        out_v[term] = scratch[12+term]
        out_w[term] = scratch[15+term]
        term += 1
      decomp_meta[1] = 20 + best_variant
      decomp_meta[2] = best_rank
      return best_rank

    scratch[3] = 1
    scratch[4] = 2
    if ffroc3_transform_u(coeff,dim,scratch,3,2,scratch,6) != 1
      return 0 - 1
    rank = ffroc3_d2_weight3(combos,1,2,scratch[6],scratch[7],dim,combo_rank,combo_v,combo_w,out_u,out_v,out_w,matrix_work,scratch,decomp_meta) ## i64
    if rank == 3
      decomp_meta[1] = 29
      decomp_meta[2] = 3
      return 3
    decomp_meta[2] = 4
    return 0 - 1

  # d=3: enumerate the 168 ordered independent triples in GL(3,2).
  code0 = 1 ## i64
  while code0 < 8
    code1 = 1 ## i64
    while code1 < 8
      if code1 != code0
        code2 = 1 ## i64
        while code2 < 8
          if code2 != code0 && code2 != code1 && code2 != (code0 ^ code1)
            decomp_meta[3] += 1
            if combo_rank[code0] == 1 && combo_rank[code1] == 1 && combo_rank[code2] == 1
              scratch[3] = code0
              scratch[4] = code1
              scratch[5] = code2
              if ffroc3_transform_u(coeff,dim,scratch,3,3,scratch,6) == 1
                out_u[0] = scratch[6]
                out_v[0] = combo_v[code0*3]
                out_w[0] = combo_w[code0*3]
                out_u[1] = scratch[7]
                out_v[1] = combo_v[code1*3]
                out_w[1] = combo_w[code1*3]
                out_u[2] = scratch[8]
                out_v[2] = combo_v[code2*3]
                out_w[2] = combo_w[code2*3]
                decomp_meta[1] = 30
                decomp_meta[2] = 3
                return 3
          code2 += 1
      code1 += 1
    code0 += 1
  decomp_meta[2] = 4
  0 - 1

-> ffroc3_verify_slice(rows, dim, us, vs, ws, count, rebuilt) (i64[] i64 i64[] i64[] i64[] i64 i64[]) i64
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

# Compact full-scheme rebuild into caller-owned work arrays followed by an
# independent fresh worker gate. No source state word is mutated.
-> ffroc3_materialize(st, selected_u, selected_v, selected_w, k, pool_u, pool_v, pool_w, chosen, replacement_count, factor_u, factor_v, factor_w, factor_count, full_u, full_v, full_w, out_state, capacity, seed) (i64[] i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64 i64) i64
  old_rank = st[6] ## i64
  # Export by direct read: ffw_export_current accounts an export in st[32],
  # while offline completion promises a byte-for-byte immutable source.
  rank = old_rank ## i64
  i = 0 ## i64
  while i < old_rank
    slot = st[st[50]+i] ## i64
    full_u[i] = st[st[44]+slot]
    full_v[i] = st[st[45]+slot]
    full_w[i] = st[st[46]+slot]
    i += 1
  i = 0 ## i64
  while i < k && rank >= 0
    rank = ffroc_toggle_plain(full_u,full_v,full_w,rank,capacity,selected_u[i],selected_v[i],selected_w[i])
    i += 1
  i = 0
  while i < replacement_count && rank >= 0
    candidate = chosen[i] ## i64
    rank = ffroc_toggle_plain(full_u,full_v,full_w,rank,capacity,pool_u[candidate],pool_v[candidate],pool_w[candidate])
    i += 1
  i = 0
  while i < factor_count && rank >= 0
    rank = ffroc_toggle_plain(full_u,full_v,full_w,rank,capacity,factor_u[i],factor_v[i],factor_w[i])
    i += 1
  if rank < 1 || rank >= old_rank
    return 0
  loaded = ffw_init_terms_cap(out_state,full_u,full_v,full_w,rank,st[2],capacity,seed,0,1,1,1) ## i64
  if loaded == rank && ffw_verify_current_exact(out_state,st[2]) == 1 && ffw_verify_best_exact(out_state,st[2]) == 1
    return rank
  0

# meta: [0] tuples, [1] decompositions, [2..5] residual rank 0..3,
# [6] rank>3, [7] compact rebuilds, [8] full gates, [9] accepted,
# [10] final rank, [11..19] q1/q2/q3, [20] source rank,
# [21] replacement count, [22] budget exhausted,
# [23..27] U-flatten dimensions 0/1/2/3/>3.
-> ffroc3_enumerate(st, selected_u, selected_v, selected_w, k, pool_u, pool_v, pool_w, pool_count, replacement_count, start, depth, chosen, residual, factor_u, factor_v, factor_w, basis, coeff, combos, combo_rank, combo_v, combo_w, matrix_work, scratch, decomp_meta, rebuilt, full_u, full_v, full_w, max_checks, out_state, capacity, seed, meta) (i64[] i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64 i64 i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64[] i64 i64 i64[]) i64
  if meta[9] != 0
    return meta[10]
  if meta[0] >= max_checks
    meta[22] = 1
    return 0
  if depth == replacement_count
    meta[0] += 1
    meta[1] += 1
    factor_count = ffroc3_decompose_slice(residual,st[3],factor_u,factor_v,factor_w,basis,coeff,combos,combo_rank,combo_v,combo_w,matrix_work,scratch,decomp_meta) ## i64
    dimension = decomp_meta[0] ## i64
    if dimension >= 0 && dimension <= 3
      meta[23+dimension] += 1
    else
      meta[27] += 1
    if factor_count < 0
      meta[6] += 1
      return 0
    meta[2+factor_count] += 1
    meta[7] += 1
    if ffroc3_verify_slice(residual,st[3],factor_u,factor_v,factor_w,factor_count,rebuilt) == 0
      return 0
    meta[8] += 1
    rank = ffroc3_materialize(st,selected_u,selected_v,selected_w,k,pool_u,pool_v,pool_w,chosen,replacement_count,factor_u,factor_v,factor_w,factor_count,full_u,full_v,full_w,out_state,capacity,seed+meta[0]) ## i64
    if rank > 0
      meta[9] = 1
      meta[10] = rank
      i = 0 ## i64
      while i < factor_count
        meta[11+i*3] = factor_u[i]
        meta[12+i*3] = factor_v[i]
        meta[13+i*3] = factor_w[i]
        i += 1
      return rank
    return 0

  remaining = replacement_count - depth ## i64
  last = pool_count - remaining ## i64
  candidate = start ## i64
  while candidate <= last
    chosen[depth] = candidate
    z = ffroc_toggle_slice(residual,pool_u[candidate],pool_v[candidate],pool_w[candidate],st[3]) ## i64
    rank = ffroc3_enumerate(st,selected_u,selected_v,selected_w,k,pool_u,pool_v,pool_w,pool_count,replacement_count,candidate+1,depth+1,chosen,residual,factor_u,factor_v,factor_w,basis,coeff,combos,combo_rank,combo_v,combo_w,matrix_work,scratch,decomp_meta,rebuilt,full_u,full_v,full_w,max_checks,out_state,capacity,seed,meta) ## i64
    z = ffroc_toggle_slice(residual,pool_u[candidate],pool_v[candidate],pool_w[candidate],st[3])
    if rank > 0
      return rank
    if meta[0] >= max_checks
      meta[22] = 1
      return 0
    candidate += 1
  0

-> ffroc3_search(st, selected, k, pool_u, pool_v, pool_w, pool_count, max_checks, out_state, capacity, seed, meta) (i64[] i64[] i64 i64[] i64[] i64[] i64 i64 i64[] i64 i64 i64[]) i64
  i = 0 ## i64
  while i < 28
    meta[i] = 0
    i += 1
  if ffw_valid(st) == 0
    return 0
  rank = st[6] ## i64
  replacement_count = k - 4 ## i64
  meta[20] = rank
  meta[21] = replacement_count
  if k < 4 || replacement_count < 0 || replacement_count > pool_count || max_checks < 1
    return 0
  if ffroc_selected_valid(selected,k,rank) == 0
    return 0
  if replacement_count > 0 && ffroc_pool_valid(pool_u,pool_v,pool_w,pool_count,st[3]) == 0
    return 0
  # Verify the source through the read-only view gate.  The public worker
  # verifier increments source counters, which would violate this strategy's
  # immutable-source contract even though it leaves the terms untouched.
  if capacity < rank || ffw_verify_view_exact(st,st[44],st[45],st[46],st[50],st[6],st[2]) == 0
    return 0

  dim = st[3] ## i64
  residual = i64[dim*dim]
  z = ffroc_clear(residual,dim*dim) ## i64
  selected_u = i64[k]
  selected_v = i64[k]
  selected_w = i64[k]
  i = 0
  while i < k
    slot = st[st[50]+selected[i]] ## i64
    selected_u[i] = st[st[44]+slot]
    selected_v[i] = st[st[45]+slot]
    selected_w[i] = st[st[46]+slot]
    z = ffroc_toggle_slice(residual,selected_u[i],selected_v[i],selected_w[i],dim)
    i += 1

  chosen = i64[replacement_count]
  factor_u = i64[3]
  factor_v = i64[3]
  factor_w = i64[3]
  basis = i64[3*dim]
  coeff = i64[dim]
  combos = i64[8*dim]
  combo_rank = i64[8]
  combo_v = i64[24]
  combo_w = i64[24]
  matrix_work = i64[3*dim]
  scratch = i64[24]
  decomp_meta = i64[6]
  rebuilt = i64[dim*dim]
  full_u = i64[capacity]
  full_v = i64[capacity]
  full_w = i64[capacity]
  ffroc3_enumerate(st,selected_u,selected_v,selected_w,k,pool_u,pool_v,pool_w,pool_count,replacement_count,0,0,chosen,residual,factor_u,factor_v,factor_w,basis,coeff,combos,combo_rank,combo_v,combo_w,matrix_work,scratch,decomp_meta,rebuilt,full_u,full_v,full_w,max_checks,out_state,capacity,seed,meta)
