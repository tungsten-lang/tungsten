# Offline computed rank-one completion for bounded local refactors.
#
# For k selected live terms A and k-2 distinct candidates B, form
#
#     E = xor(A) xor xor(B).
#
# If E is zero, A -> B is an exact k->k-2 replacement.  If E is one
# nonzero rank-one tensor q, A -> (B + q) is an exact k->k-1 replacement;
# importantly q is computed and need not occur in the candidate pool.
#
# A square n x n matrix-multiplication factor has dim=n*n bits.  Instead of
# materializing dim^3 individual coefficients, this strategy stores E as
# dim*dim rows, each row being the complete W mask.  Toggling u*v*w costs
# popcount(u)*popcount(v) XORs.  Rank-one recognition is one dim^2 pass:
# every nonzero row must contain the same W mask and every nonempty U row
# must have the same V support.  This is an offline experiment until corpus
# screens justify a low-cadence fleet arm.

use ../scheme

-> ffroc_slice_words(n) (i64) i64
  dim = n * n ## i64
  dim * dim

-> ffroc_clear(values, count) (i64[] i64) i64
  i = 0 ## i64
  while i < count
    values[i] = 0
    i += 1
  count

# XOR one outer product into the compact UxV row / W-mask representation.
-> ffroc_toggle_slice(rows, u, v, w, dim) (i64[] i64 i64 i64 i64) i64
  ai = 0 ## i64
  ubits = u ## i64
  while ai < dim
    if (ubits & 1) != 0
      bi = 0 ## i64
      vbits = v ## i64
      base = ai * dim ## i64
      while bi < dim
        if (vbits & 1) != 0
          rows[base + bi] = rows[base + bi] ^ w
        vbits = vbits >> 1
        bi += 1
    ubits = ubits >> 1
    ai += 1
  1

# Return 0 for zero, 1 for one nonzero rank-one tensor, and 2 otherwise.
# On return 1, factors contains the unique nonzero U,V,W factor masks.
-> ffroc_classify_slice(rows, n, factors) (i64[] i64 i64[]) i64
  dim = n * n ## i64
  common_w = 0 ## i64
  common_v = 0 ## i64
  u = 0 ## i64
  ai = 0 ## i64
  while ai < dim
    vrow = 0 ## i64
    bi = 0 ## i64
    base = ai * dim ## i64
    while bi < dim
      value = rows[base + bi] ## i64
      if value != 0
        if common_w == 0
          common_w = value
        else
          if value != common_w
            return 2
        vrow = vrow | (1 << bi)
      bi += 1
    if vrow != 0
      if common_v == 0
        common_v = vrow
      else
        if vrow != common_v
          return 2
      u = u | (1 << ai)
    ai += 1
  if common_w == 0
    return 0
  factors[0] = u
  factors[1] = common_v
  factors[2] = common_w
  1

-> ffroc_selected_valid(selected, count, rank) (i64[] i64 i64) i64
  if count < 2 || count > rank
    return 0
  i = 0 ## i64
  while i < count
    if selected[i] < 0 || selected[i] >= rank
      return 0
    j = i + 1 ## i64
    while j < count
      if selected[i] == selected[j]
        return 0
      j += 1
    i += 1
  1

-> ffroc_pool_valid(us, vs, ws, count, dim) (i64[] i64[] i64[] i64 i64) i64
  if count < 1
    return 0
  limit = (1 << dim) - 1 ## i64
  i = 0 ## i64
  while i < count
    if us[i] <= 0 || vs[i] <= 0 || ws[i] <= 0
      return 0
    if (us[i] & limit) != us[i] || (vs[i] & limit) != vs[i] || (ws[i] & limit) != ws[i]
      return 0
    j = i + 1 ## i64
    while j < count
      if us[i] == us[j] && vs[i] == vs[j] && ws[i] == ws[j]
        return 0
      j += 1
    i += 1
  1

# Parity-set toggle for exported plain arrays.  It deliberately mirrors the
# worker's GF(2) set semantics, including collisions with already-live terms.
-> ffroc_toggle_plain(us, vs, ws, rank, capacity, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
  i = 0 ## i64
  while i < rank
    if us[i] == u && vs[i] == v && ws[i] == w
      last = rank - 1 ## i64
      us[i] = us[last]
      vs[i] = vs[last]
      ws[i] = ws[last]
      return last
    i += 1
  if rank >= capacity
    return 0 - 1
  us[rank] = u
  vs[rank] = v
  ws[rank] = w
  rank + 1

# Materialize a discovered relation into a fresh worker and exhaustively gate
# both current and best schemes.  The source is only read.  chosen[] contains
# indices into the candidate pool, never raw factor masks.
-> ffroc_materialize(st, selected, k, pool_u, pool_v, pool_w, chosen, replacement_count, factors, kind, out_state, capacity, seed) (i64[] i64[] i64 i64[] i64[] i64[] i64[] i64 i64[] i64 i64[] i64 i64) i64
  old_rank = st[6] ## i64
  if capacity < old_rank
    return 0
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  rank = ffw_export_current(st, us, vs, ws) ## i64
  if rank != old_rank
    return 0

  # Snapshot selected factor triples before parity toggles reorder the plain
  # arrays through swap-removal.
  source_u = i64[k]
  source_v = i64[k]
  source_w = i64[k]
  i = 0 ## i64
  while i < k
    slot = st[st[50] + selected[i]] ## i64
    source_u[i] = st[st[44] + slot]
    source_v[i] = st[st[45] + slot]
    source_w[i] = st[st[46] + slot]
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
  if kind == 1 && rank >= 0
    rank = ffroc_toggle_plain(us,vs,ws,rank,capacity,factors[0],factors[1],factors[2])
  if rank < 1 || rank >= old_rank
    return 0

  loaded = ffw_init_terms_cap(out_state,us,vs,ws,rank,st[2],capacity,seed,0,1,1,1) ## i64
  if loaded == rank
    if ffw_verify_current_exact(out_state,st[2]) == 1 && ffw_verify_best_exact(out_state,st[2]) == 1
      return rank
  0

# meta layout:
# [0] leaf combinations, [1] zero residuals, [2] rank-one residuals,
# [3] non-rank-one residuals, [4] full gates, [5] accepted,
# [6] final rank, [7..9] computed q (zero for a zero residual),
# [10] source rank, [11] replacement count, [12] budget exhausted.
-> ffroc_enumerate(st, selected, k, pool_u, pool_v, pool_w, pool_count, replacement_count, start, depth, chosen, residual, factors, max_checks, out_state, capacity, seed, meta) (i64[] i64[] i64 i64[] i64[] i64[] i64 i64 i64 i64 i64[] i64[] i64[] i64 i64[] i64 i64 i64[]) i64
  if meta[5] != 0
    return meta[6]
  if meta[0] >= max_checks
    meta[12] = 1
    return 0
  if depth == replacement_count
    meta[0] += 1
    kind = ffroc_classify_slice(residual,st[2],factors) ## i64
    if kind == 0
      meta[1] += 1
    else
      if kind == 1
        meta[2] += 1
      else
        meta[3] += 1
    if kind <= 1
      meta[4] += 1
      rank = ffroc_materialize(st,selected,k,pool_u,pool_v,pool_w,chosen,replacement_count,factors,kind,out_state,capacity,seed + meta[0]) ## i64
      if rank > 0
        meta[5] = 1
        meta[6] = rank
        if kind == 1
          meta[7] = factors[0]
          meta[8] = factors[1]
          meta[9] = factors[2]
        return rank
    return 0

  remaining = replacement_count - depth ## i64
  last = pool_count - remaining ## i64
  candidate = start ## i64
  while candidate <= last
    chosen[depth] = candidate
    z = ffroc_toggle_slice(residual,pool_u[candidate],pool_v[candidate],pool_w[candidate],st[3]) ## i64
    rank = ffroc_enumerate(st,selected,k,pool_u,pool_v,pool_w,pool_count,replacement_count,candidate+1,depth+1,chosen,residual,factors,max_checks,out_state,capacity,seed,meta) ## i64
    z = ffroc_toggle_slice(residual,pool_u[candidate],pool_v[candidate],pool_w[candidate],st[3])
    if rank > 0
      return rank
    if meta[0] >= max_checks
      meta[12] = 1
      return 0
    candidate += 1
  0

# Search one selected source window against all (k-2)-subsets of a bounded
# candidate pool, stopping at max_checks.  This public entry verifies the
# source before enumeration; discovered relations receive an independent
# fresh-state full gate in ffroc_materialize.
-> ffroc_search(st, selected, k, pool_u, pool_v, pool_w, pool_count, max_checks, out_state, capacity, seed, meta) (i64[] i64[] i64 i64[] i64[] i64[] i64 i64 i64[] i64 i64 i64[]) i64
  i = 0 ## i64
  while i < 13
    meta[i] = 0
    i += 1
  if ffw_valid(st) == 0
    return 0
  rank = st[6] ## i64
  meta[10] = rank
  replacement_count = k - 2 ## i64
  meta[11] = replacement_count
  if k < 3 || replacement_count > pool_count || max_checks < 1
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
    slot = st[st[50] + selected[i]] ## i64
    z = ffroc_toggle_slice(residual,st[st[44]+slot],st[st[45]+slot],st[st[46]+slot],st[3])
    i += 1
  chosen = i64[replacement_count]
  factors = i64[3]
  ffroc_enumerate(st,selected,k,pool_u,pool_v,pool_w,pool_count,replacement_count,0,0,chosen,residual,factors,max_checks,out_state,capacity,seed,meta)
