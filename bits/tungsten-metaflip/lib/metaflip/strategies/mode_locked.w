# Production pooled move: mode-locked exact CP-ALS over GF(2).
#
# A window of k rank-one terms is selected.  Two factor modes are frozen and
# the third is re-solved exactly.  For a fixed output coordinate this is the
# affine system
#
#     A x = b,    A[:,i] = factor_left_i (x) factor_right_i.
#
# The live factor values are a known particular solution.  We row-reduce A,
# enumerate its (bounded) nullspace, and choose a minimum-weight member of the
# affine coset independently for every coordinate.  Rows are stored as k-bit
# coefficient words, rather than packing tensor coordinates into one i64, so
# this continues to work when the frozen-mode product has more than 63 rows.
#
# Public stats layout:
#   [attempts, exact, rank_hits, density_hits, neutral, rejects, candidates,
#    flags]
# `budget` is an attempt count and `nonce` offsets the deterministic window
# stream. Inputs are never modified. A nonzero return is the rank copied to
# out_u/out_v/out_w; zero means no changed exact result.

use pooled_exact

-> ffml_popcount(x) (i64) i64
  n = 0 ## i64
  while x != 0
    x = x & (x - 1)
    n += 1
  n

-> ffml_density(us, vs, ws, count) (i64[] i64[] i64[] i64) i64
  d = 0 ## i64
  i = 0 ## i64
  while i < count
    d += ffml_popcount(us[i])
    d += ffml_popcount(vs[i])
    d += ffml_popcount(ws[i])
    i += 1
  d

-> ffml_factor(us, vs, ws, term, axis) (i64[] i64[] i64[] i64 i64) i64
  if axis == 0
    return us[term]
  if axis == 1
    return vs[term]
  ws[term]

-> ffml_set_factor(us, vs, ws, term, axis, value) (i64[] i64[] i64[] i64 i64 i64) i64
  if axis == 0
    us[term] = value
  if axis == 1
    vs[term] = value
  if axis == 2
    ws[term] = value
  value

-> ffml_copy(us, vs, ws, count, out_u, out_v, out_w) (i64[] i64[] i64[] i64 i64[] i64[] i64[]) i64
  i = 0 ## i64
  while i < count
    out_u[i] = us[i]
    out_v[i] = vs[i]
    out_w[i] = ws[i]
    i += 1
  count

-> ffml_same_term(us, vs, ws, i, j) (i64[] i64[] i64[] i64 i64) i64
  if us[i] == us[j] && vs[i] == vs[j] && ws[i] == ws[j]
    return 1
  0

# Remove zero terms and cancel equal terms in pairs.  The operation is exact
# over GF(2).  Order is intentionally unspecified.
-> ffml_compact(us, vs, ws, count) (i64[] i64[] i64[] i64) i64
  i = 0 ## i64
  while i < count
    if us[i] == 0 || vs[i] == 0 || ws[i] == 0
      last = count - 1 ## i64
      us[i] = us[last]
      vs[i] = vs[last]
      ws[i] = ws[last]
      count = last
    else
      i += 1
  i = 0
  while i < count
    j = i + 1 ## i64
    cancelled = 0 ## i64
    while j < count && cancelled == 0
      if ffml_same_term(us, vs, ws, i, j) == 1
        last = count - 1 ## i64
        us[j] = us[last]
        vs[j] = vs[last]
        ws[j] = ws[last]
        count = last
        last = count - 1
        us[i] = us[last]
        vs[i] = vs[last]
        ws[i] = ws[last]
        count = last
        cancelled = 1
      else
        j += 1
    if cancelled == 0
      i += 1
  count

# Exact equality of two full tensors represented as CP term lists.  This is
# deliberately independent of a packed <=63-bit signature.
-> ffml_exact_equal(au, av, aw, ac, bu, bv, bw, bc, ab, bb, cb) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64 i64 i64) i64
  a = 0 ## i64
  while a < ab
    b = 0 ## i64
    while b < bb
      c = 0 ## i64
      while c < cb
        lhs = 0 ## i64
        i = 0 ## i64
        while i < ac
          if ((au[i] >> a) & 1) == 1 && ((av[i] >> b) & 1) == 1 && ((aw[i] >> c) & 1) == 1
            lhs = lhs ^ 1
          i += 1
        rhs = 0 ## i64
        i = 0
        while i < bc
          if ((bu[i] >> a) & 1) == 1 && ((bv[i] >> b) & 1) == 1 && ((bw[i] >> c) & 1) == 1
            rhs = rhs ^ 1
          i += 1
        if lhs != rhs
          return 0
        c += 1
      b += 1
    a += 1
  1

-> ffml_same_frozen(us, vs, ws, i, j, axis) (i64[] i64[] i64[] i64 i64 i64) i64
  if axis == 0
    if vs[i] == vs[j] && ws[i] == ws[j]
      return 1
  if axis == 1
    if us[i] == us[j] && ws[i] == ws[j]
      return 1
  if axis == 2
    if us[i] == us[j] && vs[i] == vs[j]
      return 1
  0

# Fill coefficient rows for the two frozen modes.  Each row is a k-bit word;
# therefore the number of rows is unrestricted by the scalar representation.
-> ffml_build_rows(win_u, win_v, win_w, k, axis, ab, bb, cb, rows) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64[]) i64
  left_width = ab ## i64
  right_width = bb ## i64
  if axis == 0
    left_width = bb
    right_width = cb
  if axis == 1
    left_width = ab
    right_width = cb
  if axis == 2
    left_width = ab
    right_width = bb
  r = 0 ## i64
  left = 0 ## i64
  while left < left_width
    right = 0 ## i64
    while right < right_width
      word = 0 ## i64
      i = 0 ## i64
      while i < k
        lf = win_u[i] ## i64
        rf = win_v[i] ## i64
        if axis == 0
          lf = win_v[i]
          rf = win_w[i]
        if axis == 1
          lf = win_u[i]
          rf = win_w[i]
        if axis == 2
          lf = win_u[i]
          rf = win_v[i]
        if ((lf >> left) & 1) == 1 && ((rf >> right) & 1) == 1
          word = word | (1 << i)
        i += 1
      rows[r] = word
      r += 1
      right += 1
    left += 1
  r

# RREF a coefficient-only row system and return a nullspace basis.  Variables
# are the k live terms.  The basis array needs k slots.
-> ffml_nullspace(rows, row_count, k, basis) (i64[] i64 i64 i64[]) i64
  pivots = i64[k]
  c = 0 ## i64
  while c < k
    pivots[c] = 0 - 1
    c += 1
  rank = 0 ## i64
  c = 0
  while c < k
    pivot = 0 - 1 ## i64
    r = rank ## i64
    while r < row_count && pivot < 0
      if ((rows[r] >> c) & 1) == 1
        pivot = r
      r += 1
    if pivot >= 0
      tmp = rows[rank] ## i64
      rows[rank] = rows[pivot]
      rows[pivot] = tmp
      r = 0
      while r < row_count
        if r != rank && ((rows[r] >> c) & 1) == 1
          rows[r] = rows[r] ^ rows[rank]
        r += 1
      pivots[c] = rank
      rank += 1
    c += 1
  nullity = 0 ## i64
  free_col = 0 ## i64
  while free_col < k
    if pivots[free_col] < 0
      vec = 1 << free_col ## i64
      pivot_col = 0 ## i64
      while pivot_col < k
        if pivots[pivot_col] >= 0
          if ((rows[pivots[pivot_col]] >> free_col) & 1) == 1
            vec = vec | (1 << pivot_col)
        pivot_col += 1
      basis[nullity] = vec
      nullity += 1
    free_col += 1
  nullity

# Minimum-weight element of particular + ker(A).  k<=12 in the public search,
# so the complete affine coset costs at most 4096 masks per coordinate.
-> ffml_coset_min(particular, basis, nullity, salt) (i64 i64[] i64 i64) i64
  best = particular ## i64
  best_weight = ffml_popcount(best) ## i64
  best_tie = (best ^ salt) & 65535 ## i64
  mask = 1 ## i64
  limit = 1 << nullity ## i64
  while mask < limit
    x = particular ## i64
    j = 0 ## i64
    while j < nullity
      if ((mask >> j) & 1) == 1
        x = x ^ basis[j]
      j += 1
    weight = ffml_popcount(x) ## i64
    tie = (x ^ salt) & 65535 ## i64
    if weight < best_weight || (weight == best_weight && tie < best_tie)
      best = x
      best_weight = weight
      best_tie = tie
    mask += 1
  best

-> ffml_changed(us, vs, ws, rank, ou, ov, ow, out_rank) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  if rank != out_rank
    return 1
  i = 0 ## i64
  while i < rank
    if us[i] != ou[i] || vs[i] != ov[i] || ws[i] != ow[i]
      return 1
    i += 1
  0

-> ffml_stats_clear(stats) (i64[]) i64
  i = 0 ## i64
  while i < 8
    stats[i] = 0
    i += 1
  1

# Select a window.  The first three attempts deliberately look for one pair
# with equal frozen factors (the planted split positive control).  Later
# attempts use deterministic, diverse k=5..12 windows.
-> ffml_select(us, vs, ws, rank, attempt, axis, selected) (i64[] i64[] i64[] i64 i64 i64 i64[]) i64
  if attempt < 3
    i = 0 ## i64
    while i < rank
      j = i + 1 ## i64
      while j < rank
        if ffml_same_frozen(us, vs, ws, i, j, axis) == 1
          selected[0] = i
          selected[1] = j
          return 2
        j += 1
      i += 1
  k = 5 + (attempt % 8) ## i64
  if k > rank
    k = rank
  if k < 2
    return 0
  i = 0
  while i < k
    candidate = (attempt * 17 + axis * 11 + i * 7 + i * i) % rank ## i64
    unique = 0 ## i64
    while unique == 0
      unique = 1
      j = 0 ## i64
      while j < i
        if selected[j] == candidate
          candidate = (candidate + 1) % rank
          unique = 0
          j = i
        else
          j += 1
    selected[i] = candidate
    i += 1
  k

-> ffml_search(us, vs, ws, rank, n, m, p, budget, nonce, out_u, out_v, out_w, stats) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64[] i64[] i64[] i64[]) i64
  if stats.size() < 8
    return 0
  ffml_stats_clear(stats)
  if rank < 2 || budget < 1
    return 0
  if us.size() < rank || vs.size() < rank || ws.size() < rank
    stats[7] = 2
    return 0
  if out_u.size() < rank || out_v.size() < rank || out_w.size() < rank
    stats[7] = 2
    return 0
  ab = n * m ## i64
  bb = m * p ## i64
  cb = n * p ## i64
  if ab < 1 || bb < 1 || cb < 1 || ab > 62 || bb > 62 || cb > 62
    stats[7] = 4
    return 0
  original_density = ffml_density(us, vs, ws, rank) ## i64
  best_rank = rank + 1 ## i64
  best_density = 0x3fffffffffffffff ## i64
  attempt = 0 ## i64
  while attempt < budget
    logical_attempt = nonce + attempt ## i64
    # Every new seed deserves the three cheap merge-pair probes.  Offset only
    # the broader k=5..12 stream; otherwise a fleet-global launch nonce would
    # accidentally disable the closer's strongest measured positive control.
    if attempt < 3
      logical_attempt = attempt
    axis = logical_attempt % 3 ## i64
    selected = i64[12]
    k = ffml_select(us, vs, ws, rank, logical_attempt, axis, selected) ## i64
    stats[0] += 1
    if k >= 2
      win_u = i64[k]
      win_v = i64[k]
      win_w = i64[k]
      i = 0 ## i64
      while i < k
        win_u[i] = us[selected[i]]
        win_v[i] = vs[selected[i]]
        win_w[i] = ws[selected[i]]
        i += 1
      left_width = ab ## i64
      right_width = bb ## i64
      solve_width = cb ## i64
      if axis == 0
        left_width = bb
        right_width = cb
        solve_width = ab
      if axis == 1
        left_width = ab
        right_width = cb
        solve_width = bb
      if axis == 2
        left_width = ab
        right_width = bb
        solve_width = cb
      rows = i64[left_width * right_width]
      row_count = ffml_build_rows(win_u, win_v, win_w, k, axis, ab, bb, cb, rows) ## i64
      null_basis = i64[k]
      nullity = ffml_nullspace(rows, row_count, k, null_basis) ## i64
      if nullity > 0
        solved = i64[k]
        i = 0
        while i < k
          solved[i] = 0
          i += 1
        coordinate = 0 ## i64
        while coordinate < solve_width
          particular = 0 ## i64
          i = 0
          while i < k
            old_factor = ffml_factor(win_u, win_v, win_w, i, axis) ## i64
            if ((old_factor >> coordinate) & 1) == 1
              particular = particular | (1 << i)
            i += 1
          # Keep tie-breaking coordinate-independent.  This deliberately
          # concentrates equal-cost coordinates onto the same live terms;
          # coordinate-varying ties preserve density but needlessly keep both
          # halves of a planted split alive.
          chosen = ffml_coset_min(particular, null_basis, nullity, logical_attempt * 131) ## i64
          i = 0
          while i < k
            if ((chosen >> i) & 1) == 1
              solved[i] = solved[i] | (1 << coordinate)
            i += 1
          coordinate += 1
        # First exact gate: the replacement window alone.
        rep_u = i64[k]
        rep_v = i64[k]
        rep_w = i64[k]
        ffml_copy(win_u, win_v, win_w, k, rep_u, rep_v, rep_w)
        i = 0
        while i < k
          ffml_set_factor(rep_u, rep_v, rep_w, i, axis, solved[i])
          i += 1
        if ffml_exact_equal(win_u, win_v, win_w, k, rep_u, rep_v, rep_w, k, ab, bb, cb) == 1
          candidate_u = i64[rank]
          candidate_v = i64[rank]
          candidate_w = i64[rank]
          ffml_copy(us, vs, ws, rank, candidate_u, candidate_v, candidate_w)
          i = 0
          while i < k
            ffml_set_factor(candidate_u, candidate_v, candidate_w, selected[i], axis, solved[i])
            i += 1
          candidate_rank = ffml_compact(candidate_u, candidate_v, candidate_w, rank) ## i64
          if ffml_changed(us, vs, ws, rank, candidate_u, candidate_v, candidate_w, candidate_rank) == 1
            stats[6] += 1
            # Second gate: full scheme equality, after zero/duplicate compaction.
            if ffml_exact_equal(us, vs, ws, rank, candidate_u, candidate_v, candidate_w, candidate_rank, ab, bb, cb) == 1 && ffpe_verify(candidate_u, candidate_v, candidate_w, candidate_rank, n, m, p) == 1
              stats[1] += 1
              candidate_density = ffml_density(candidate_u, candidate_v, candidate_w, candidate_rank) ## i64
              if candidate_rank < rank
                stats[2] += 1
              if candidate_rank == rank && candidate_density < original_density
                stats[3] += 1
              if candidate_rank == rank && candidate_density == original_density
                stats[4] += 1
              if candidate_rank < best_rank || (candidate_rank == best_rank && candidate_density < best_density)
                best_rank = candidate_rank
                best_density = candidate_density
                ffml_copy(candidate_u, candidate_v, candidate_w, candidate_rank, out_u, out_v, out_w)
            else
              stats[5] += 1
          else
            stats[5] += 1
        else
          stats[5] += 1
    attempt += 1
  if best_rank <= rank
    stats[7] = 1
    return best_rank
  0

# Planted positive control: split the U factor of the first term in Strassen's
# GF(2) 2x2 scheme.  The public exact-gated entry point must recover rank 7.
-> ffml_selftest() i64
  us = i64[8]
  vs = i64[8]
  ws = i64[8]
  us[0] = 1
  vs[0] = 9
  ws[0] = 9
  us[1] = 8
  vs[1] = 9
  ws[1] = 9
  us[2] = 12
  vs[2] = 1
  ws[2] = 12
  us[3] = 1
  vs[3] = 10
  ws[3] = 10
  us[4] = 8
  vs[4] = 5
  ws[4] = 5
  us[5] = 3
  vs[5] = 8
  ws[5] = 3
  us[6] = 5
  vs[6] = 3
  ws[6] = 8
  us[7] = 10
  vs[7] = 12
  ws[7] = 1
  out_u = i64[8]
  out_v = i64[8]
  out_w = i64[8]
  stats = i64[8]
  got = ffml_search(us, vs, ws, 8, 2, 2, 2, 3, 0, out_u, out_v, out_w, stats) ## i64
  if got == 7 && stats[2] > 0
    return 1
  0

# A 4x4 naive MMT plus a cancelling duplicate pair.  Solving U freezes a
# 16x16 grid (256 equations), guarding against the old <=63-row packed solver.
-> ffml_wide_selftest() i64
  us = i64[66]
  vs = i64[66]
  ws = i64[66]
  count = 0 ## i64
  a = 0 ## i64
  while a < 4
    b = 0 ## i64
    while b < 4
      c = 0 ## i64
      while c < 4
        us[count] = 1 << (a * 4 + b)
        vs[count] = 1 << (b * 4 + c)
        ws[count] = 1 << (a * 4 + c)
        count += 1
        c += 1
      b += 1
    a += 1
  us[64] = us[0]
  vs[64] = vs[0]
  ws[64] = ws[0]
  us[65] = us[0]
  vs[65] = vs[0]
  ws[65] = ws[0]
  out_u = i64[66]
  out_v = i64[66]
  out_w = i64[66]
  stats = i64[8]
  got = ffml_search(us, vs, ws, 66, 4, 4, 4, 3, 0, out_u, out_v, out_w, stats) ## i64
  if got == 64 && stats[2] > 0
    return 1
  0
