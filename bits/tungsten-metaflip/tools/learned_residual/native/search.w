use model

-> fflr_rank_one(core, dims, terms, offset) (i64 i64[] i64[] i64) i64
  if core == 0
    return 0
  pattern = 0 ## i64
  u = 0 ## i64
  v = 0 ## i64
  w = 0 ## i64
  a = 0 ## i64
  while a < dims[0]
    row = 0 ## i64
    b = 0 ## i64
    while b < dims[1]
      mask = (1 << dims[2])-1 ## i64
      fiber = (core >> ((a*dims[1]+b)*dims[2])) & mask ## i64
      if fiber != 0
        if w == 0
          w = fiber
        if w != fiber
          return 0
        row |= 1 << b
      b += 1
    if row != 0
      if pattern == 0
        pattern = row
        v = row
      if row != pattern
        return 0
      u |= 1 << a
    a += 1
  terms[offset] = u
  terms[offset+1] = v
  terms[offset+2] = w
  1

-> fflr_seen(core, depth, keys, depths) (i64 i64 i64[] i64[]) i64
  slot = (core^(core >> 32))&32767 ## i64
  while depths[slot] != 0 && keys[slot] != core
    slot = (slot+1)&32767
  if depths[slot] != 0 && depths[slot] <= depth+1
    return 1
  keys[slot] = core
  depths[slot] = depth+1
  0

-> fflr_answer(target, dims, path, count, out, stats) (i64 i64[] i64[] i64 i64[] i64[]) i64
  actual = 0 ## i64
  i = 0 ## i64
  while i < count
    actual ^= fflr_outer(path[3*i], path[3*i+1], path[3*i+2], dims[1], dims[2])
    out[3*i] = path[3*i]
    out[3*i+1] = path[3*i+1]
    out[3*i+2] = path[3*i+2]
    i += 1
  if actual != target
    return 0-2
  stats[4] = 1
  count

# A complete rank-one alphabet, four-wide beam, <=12000 XORs, <=200ms and
# cancellation polling. Failure is budget/search evidence, never a rank proof.
# Each record is [core, six triples, spare]. All storage has a fixed bound.
# stats: checks, lower-bound prunes, transpositions, predictions, stop reason.
-> fflr_search(target, dims, limit, model, out, stats, budget, milliseconds, stop, seed) (i64 i64[] i64 f64[] i64[] i64[] i64 i64 String i64) i64
  i = 0 ## i64
  while i < 5
    stats[i] = 0
    i += 1
  if limit < 0 || limit > 6 || budget < 1 || budget > 12000 || milliseconds < 1 || milliseconds > 200
    return 0-2
  if stop != "" && File.exists?(stop)
    stats[4] = 7
    return 0-1
  if target == 0
    stats[4] = 1
    return 0
  i = 0
  while i < 3
    if dims[i] < 1 || dims[i] > 4
      stats[4] = 3
      return 0-1
    i += 1
  volume = dims[0]*dims[1]*dims[2] ## i64
  if volume < 64 && (target >> volume) != 0
    return 0-2
  rows = i64[4]
  pivots = i64[16]
  if fflr_lower(target, dims, rows, pivots) > limit
    stats[4] = 2
    return 0-1
  start = ccall("__w_clock_ms") ## i64
  cache = i64[327680]
  keys = i64[32768]
  depths = i64[32768]
  beam = i64[80]
  frontier = i64[80]
  scores = f64[4]
  features = f64[18]
  matrix_rows = i64[4]
  path = i64[18]
  tail = i64[3]
  alphabet = i64[3375]
  au = i64[3375]
  av = i64[3375]
  aw = i64[3375]
  size = 0 ## i64
  u = 1 ## i64
  while u < (1 << dims[0])
    v = 1 ## i64
    while v < (1 << dims[1])
      w = 1 ## i64
      while w < (1 << dims[2])
        alphabet[size] = fflr_outer(u, v, w, dims[1], dims[2])
        au[size] = u
        av[size] = v
        aw[size] = w
        size += 1
        w += 1
      v += 1
    u += 1
  # A reproducible shuffle avoids a systematic low-coordinate prefix at the
  # work cap. It cannot change the exact alphabet or authorize a candidate.
  rng = (seed&2147483647)+1 ## i64
  i = size-1
  while i > 0
    rng = (rng*1103515245+12345)&2147483647
    j = rng%(i+1) ## i64
    tmp = alphabet[i] ## i64
    alphabet[i] = alphabet[j]
    alphabet[j] = tmp
    tmp = au[i]
    au[i] = au[j]
    au[j] = tmp
    tmp = av[i]
    av[i] = av[j]
    av[j] = tmp
    tmp = aw[i]
    aw[i] = aw[j]
    aw[j] = tmp
    i -= 1
  beam[0] = target
  z = fflr_seen(target, 0, keys, depths) ## i64
  count = 1 ## i64
  depth = 0 ## i64
  while depth < limit
    next_count = 0 ## i64
    b = 0 ## i64
    while b < count
      residual = beam[b*20] ## i64
      i = 0
      while i < depth*3
        path[i] = beam[b*20+1+i]
        i += 1
      if fflr_rank_one(residual, dims, path, depth*3) == 1
        return fflr_answer(target, dims, path, depth+1, out, stats)
      k = 0 ## i64
      while k < size
        if stats[0] >= budget
          stats[4] = 4
          return 0-1
        if (stats[0]&63) == 0
          if stop != "" && File.exists?(stop)
            stats[4] = 7
            return 0-1
          if ccall("__w_clock_ms")-start >= milliseconds
            stats[4] = 5
            return 0-1
        stats[0] += 1
        child = residual^alphabet[k] ## i64
        path[3*depth] = au[k]
        path[3*depth+1] = av[k]
        path[3*depth+2] = aw[k]
        remaining = limit-depth-1 ## i64
        if child == 0
          return fflr_answer(target, dims, path, depth+1, out, stats)
        if fflr_seen(child, depth+1, keys, depths) == 1
          stats[2] += 1
        elsif fflr_lower(child, dims, rows, pivots) > remaining
          stats[1] += 1
        elsif remaining >= 1 && fflr_rank_one(child, dims, tail, 0) == 1
          i = 0
          while i < 3
            path[3*(depth+1)+i] = tail[i]
            i += 1
          return fflr_answer(target, dims, path, depth+2, out, stats)
        elsif remaining > 0
          z = fflr_features(child, dims, features, rows, pivots, matrix_rows, cache)
          score = fflr_score(features, model) ## f64
          stats[3] += 1
          pos = next_count ## i64
          if pos > 3
            pos = 3
          if next_count < 4 || score < scores[3]
            while pos > 0 && score < scores[pos-1]
              scores[pos] = scores[pos-1]
              i = 0
              while i < 20
                frontier[pos*20+i] = frontier[(pos-1)*20+i]
                i += 1
              pos -= 1
            scores[pos] = score
            frontier[pos*20] = child
            i = 0
            while i < (depth+1)*3
              frontier[pos*20+1+i] = path[i]
              i += 1
            if next_count < 4
              next_count += 1
        k += 1
      b += 1
    if next_count == 0
      break
    swap = beam
    beam = frontier
    frontier = swap
    count = next_count
    depth += 1
  stats[4] = 6
  0-1
