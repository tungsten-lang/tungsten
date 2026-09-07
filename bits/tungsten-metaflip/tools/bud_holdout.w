use bud_parent_score

# Offline only: remove a fixed list of literal summands, walk its residual
# tensor algebraically, then reinsert them before ANY full-tensor admission.
# A residual state is not a matrix-multiplication scheme and must not be dumped.
# Buffers are caller-owned: indices has count words, held has 3*count words.
-> ffbh_extract(st, indices, held, count) (i64[] i64[] i64[] i64) i64
  rank = st[6] ## i64
  if count < 0 || count >= rank
    return 0
  i = 0 ## i64
  while i < count
    if indices[i] < 0 || indices[i] >= rank
      return 0
    j = 0 ## i64
    while j < i
      if indices[i] == indices[j]
        return 0
      j += 1
    slot = st[st[50] + indices[i]] ## i64
    axis = 0 ## i64
    while axis < 3
      held[3*i + axis] = st[st[44 + axis] + slot]
      axis += 1
    i += 1
  1

-> ffbh_remove(st, held, count) (i64[] i64[] i64) i64
  if count < 0 || count >= st[6]
    return 0
  i = 0 ## i64
  while i < count
    if ffw_find_term(st,held[3*i],held[3*i+1],held[3*i+2]) < 0
      return 0
    j = 0 ## i64
    while j < i
      if held[3*i] == held[3*j] && held[3*i+1] == held[3*j+1] && held[3*i+2] == held[3*j+2]
        return 0
      j += 1
    i += 1
  current = st[6] ## i64
  i = 0
  while i < count
    current = ffw_toggle(st,held[3*i],held[3*i+1],held[3*i+2],current)
    i += 1
  st[6] = current
  # Establish the new INTERNAL residual target's rank/density best. No public
  # exactness claim is made by this algebraic state initialization.
  z = ffw_copy_current_to_best(st) ## i64
  1

# Returns the number of held terms cancelled by the evolved residual, or -1
# on a capacity error. Cancellation is valid GF(2) arithmetic, but is recorded
# separately from surviving held structure. Never mutates the walked source.
-> ffbh_join(src, dst, words, held, count) (i64[] i64[] i64 i64[] i64) i64
  if count < 0 || src[6] + count > src[4]
    return 0 - 1
  z = ffbp_copy(src,dst,words) ## i64
  current = dst[6] ## i64
  cancelled = 0 ## i64
  i = 0 ## i64
  while i < count
    if ffw_find_term(dst,held[3*i],held[3*i+1],held[3*i+2]) >= 0
      cancelled += 1
    current = ffw_toggle(dst,held[3*i],held[3*i+1],held[3*i+2],current)
    i += 1
  dst[6] = current
  dst[64] = ffw_view_bits(dst,dst[44],dst[45],dst[46],dst[50],current) - dst[36]
  cancelled

# A caller-verified elementary holdout has one certificate-backed leaf cost.
# Use that cover only while its literal terms all survive in the joined full
# tensor (cancelled == 0). Otherwise keep the ordinary constructive cover.
# This does not enumerate grids, so it has no rank-64 grid-search restriction.
-> ffbh_cost(whole, residual, cancelled, held_cost, prices, stride, keys, counts, grid_prices) (i64[] i64[] i64 i64 i64[] i64 i64[] i64[] i64[]) i64
  best = ffbp_grid_cost(whole,prices,stride,keys,counts,grid_prices) ## i64
  if held_cost > 0 && cancelled == 0
    part = 0 ## i64
    if residual[6] > 0
      part = ffbp_cost(residual,prices,stride,keys,counts)
    # Avoid overflow on the invalid-state sentinel, and keep the old tie.
    if part < best && held_cost < best - part
      best = held_cost + part
  best
