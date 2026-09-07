# Offline parent objective. Prices are certificate-backed per-bucket DP costs
# supplied by bud_products.rb. This is a constructive product upper bound,
# never a tensor-rank lower bound or a proof of optimality.
use bud_parent_shapes

# Offline adapter only: preserve each existing engine's shape/state encoding.
-> ffbp_supported(n, m, p) (i64 i64 i64) i64
  if n == m && m == p && n >= 2 && n <= 7
    return 1
  ffbo_supported(n,m,p)

-> ffbp_load(st, path, n, m, p, capacity, seed, dslack) (i64[] String i64 i64 i64 i64 i64 i64) i64
  if n == m && m == p
    return ffw_load_scheme_cap(st,path,n,capacity,seed,dslack,4,1000,500)
  if ffr_supported(n,m,p) != 1
    return ffbo_load(st,path,n,m,p,capacity,seed,dslack)
  ffr_load_scheme_cap(st,path,n,m,p,capacity,seed,dslack,4,1000,500)

-> ffbp_verify(st, n, m, p) (i64[] i64 i64 i64) i64
  if n == m && m == p
    return ffw_verify_current_exact(st,n)
  if ffr_supported(n,m,p) != 1
    return ffbo_verify(st,n,m,p)
  ffr_verify_current_exact(st,n,m,p)

-> ffbp_wander(st, steps, n, m, p) (i64[] i64 i64 i64 i64) i64
  if n == m && m == p
    return ffw_wander(st,steps)
  ffr_wander(st,steps)

-> ffbp_dump(st, path, n, m, p) (i64[] String i64 i64 i64) i64
  if n == m && m == p
    return ffw_dump_current(st,path)
  if ffr_supported(n,m,p) != 1
    return ffbo_dump(st,path,n,m,p)
  ffr_dump_current(st,path)

-> ffbp_copy(src, dst, words) (i64[] i64[] i64) i64
  i = 0 ## i64
  while i < words
    dst[i] = src[i]
    i += 1
  1

-> ffbp_axis_cost(st, axis, prices, stride, keys, counts) (i64[] i64 i64[] i64 i64[] i64[]) i64
  rank = ffr_current_rank(st) ## i64
  if rank < 1 || rank >= stride || axis < 0 || axis > 2
    return 9223372036854775807
  offset = st[44 + axis] ## i64
  groups = 0 ## i64
  i = 0 ## i64
  while i < rank
    slot = st[st[50] + i] ## i64
    value = st[offset + slot] ## i64
    j = 0 ## i64
    while j < groups && keys[j] != value
      j += 1
    if j == groups
      keys[j] = value
      counts[j] = 0
      groups += 1
    counts[j] += 1
    i += 1
  total = 0 ## i64
  i = 0
  while i < groups
    total += prices[axis * stride + counts[i]]
    i += 1
  total

-> ffbp_cost(st, prices, stride, keys, counts) (i64[] i64[] i64 i64[] i64[]) i64
  best = 9223372036854775807 ## i64
  axis = 0 ## i64
  while axis < 3
    score = ffbp_axis_cost(st, axis, prices, stride, keys, counts) ## i64
    if score < best
      best = score
    axis += 1
  best

# Best pure-axis partition after removing the four live indices of a grid.
-> ffbp_without_four(st, prices, stride, keys, counts, i0, i1, i2, i3) (i64[] i64[] i64 i64[] i64[] i64 i64 i64 i64) i64
  rank = ffr_current_rank(st) ## i64
  best = 9223372036854775807 ## i64
  axis = 0 ## i64
  while axis < 3
    offset = st[44 + axis] ## i64
    groups = 0 ## i64
    i = 0 ## i64
    while i < rank
      if i != i0 && i != i1 && i != i2 && i != i3
        slot = st[st[50] + i] ## i64
        value = st[offset + slot] ## i64
        j = 0 ## i64
        while j < groups && keys[j] != value
          j += 1
        if j == groups
          keys[j] = value
          counts[j] = 0
          groups += 1
        counts[j] += 1
      i += 1
    total = 0 ## i64
    i = 0
    while i < groups
      total += prices[axis * stride + counts[i]]
      i += 1
    if total < best
      best = total
    axis += 1
  best

# Constructive model: zero or one nondegenerate 2x2 grid, then one pure
# bucket axis for the remaining terms. This is not full set packing.
# Grid prices correspond to factor pairs UV, UW, VW, respectively.
-> ffbp_grid_cost(st, prices, stride, keys, counts, grid_prices) (i64[] i64[] i64 i64[] i64[] i64[]) i64
  best = ffbp_cost(st,prices,stride,keys,counts) ## i64
  rank = ffr_current_rank(st) ## i64
  if rank < 4 || rank >= stride || rank > 64 || grid_prices[0] == 0
    return best
  pair = 0 ## i64
  a = 0 ## i64
  while a < 2
    b = a + 1 ## i64
    while b < 3
      ao = st[44 + a] ## i64
      bo = st[44 + b] ## i64
      i = 0 ## i64
      while i < rank
        islot = st[st[50] + i] ## i64
        ai = st[ao + islot] ## i64
        bi = st[bo + islot] ## i64
        j = i + 1 ## i64
        while j < rank
          jslot = st[st[50] + j] ## i64
          aj = st[ao + jslot] ## i64
          bj = st[bo + jslot] ## i64
          if ai != aj && bi != bj
            k = 0 ## i64
            while k < rank
              kslot = st[st[50] + k] ## i64
              if st[ao + kslot] == ai && st[bo + kslot] == bj
                l = 0 ## i64
                while l < rank
                  lslot = st[st[50] + l] ## i64
                  if st[ao + lslot] == aj && st[bo + lslot] == bi
                    score = grid_prices[pair] + ffbp_without_four(st,prices,stride,keys,counts,i,j,k,l) ## i64
                    if score < best
                      best = score
                  l += 1
              k += 1
          j += 1
        i += 1
      pair += 1
      b += 1
    a += 1
  best

-> ffbp_accept(mode, score, anchor_score, trial_best, chunk) (String i64 i64 i64 i64) i64
  if mode == "walk"
    return 1
  if mode == "greedy"
    if score <= anchor_score
      return 1
    return 0
  if mode == "anneal"
    phase = (chunk / 16) % 5 ## i64
    allowance = 0 ## i64
    if phase > 0
      allowance = 1 << (phase - 1)
    if score <= trial_best + allowance
      return 1
  0

-> ffbp_better(score, rank, bits, old_score, old_rank, old_bits) (i64 i64 i64 i64 i64 i64) i64
  if score < old_score
    return 1
  if score == old_score && rank < old_rank
    return 1
  if score == old_score && rank == old_rank && bits < old_bits
    return 1
  0
