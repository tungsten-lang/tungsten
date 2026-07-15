# Exact bounded global one-axis kernel shears.
#
# Each selected term receives exactly one mutable factor.  Consequently the
# endpoint equation is linear: no term changes two factors, so quadratic and
# cubic remainders cannot appear.  The solver builds exact full-coordinate
# GF(2) columns, performs incremental elimination, and materializes kernel
# dependencies as finite involutive moves.

use flipfleet_tunnel_catalyst

-> ffks_words(bits) (i64) i64
  (bits + 62) / 63

-> ffks_clear(values, count) (i64[] i64) i64
  i = 0 ## i64
  while i < count
    values[i] = 0
    i += 1
  count

-> ffks_set_bit(values, bit) (i64[] i64) i64
  word = bit / 63 ## i64
  offset = bit % 63 ## i64
  values[word] = values[word] ^ (1 << offset)
  1

-> ffks_first_bit(values, words) (i64[] i64) i64
  word = 0 ## i64
  while word < words
    if values[word] != 0
      bit = 0 ## i64
      while bit < 63
        if ((values[word] >> bit) & 1) == 1
          return word * 63 + bit
        bit += 1
    word += 1
  0 - 1

-> ffks_xor_from(dest, source, source_offset, count) (i64[] i64[] i64 i64) i64
  i = 0 ## i64
  while i < count
    dest[i] = dest[i] ^ source[source_offset + i]
    i += 1
  count

-> ffks_copy_into(dest, dest_offset, source, count) (i64[] i64 i64[] i64) i64
  i = 0 ## i64
  while i < count
    dest[dest_offset + i] = source[i]
    i += 1
  count

-> ffks_factor(us, vs, ws, term, axis) (i64[] i64[] i64[] i64 i64) i64
  value = us[term] ## i64
  if axis == 1
    value = vs[term]
  if axis == 2
    value = ws[term]
  value

# Deterministic whole-window axis assignments. Modes 0--2 move one common
# axis, 3--5 are the three striped phases, 6 chooses the mutable axis whose
# fixed outer pair is sparsest, and modes >=7 are reproducible mixed plans.
-> ffks_fill_axis_plan(us, vs, ws, count, mode, nonce, axes) (i64[] i64[] i64[] i64 i64 i64 i64[]) i64
  if count < 1 || count > 256 || us.size() < count || vs.size() < count || ws.size() < count || axes.size() < count
    return 0
  term = 0 ## i64
  while term < count
    axis = 0 ## i64
    if mode >= 0 && mode <= 2
      axis = mode
    if mode >= 3 && mode <= 5
      axis = (term + mode - 3) % 3
    if mode == 6
      up = ffw_popcount(us[term]) ## i64
      vp = ffw_popcount(vs[term]) ## i64
      wp = ffw_popcount(ws[term]) ## i64
      score_u = vp * wp ## i64
      score_v = up * wp ## i64
      score_w = up * vp ## i64
      axis = nonce % 3
      best = score_u ## i64
      if axis == 1
        best = score_v
      if axis == 2
        best = score_w
      if score_u < best
        axis = 0
        best = score_u
      if score_v < best
        axis = 1
        best = score_v
      if score_w < best
        axis = 2
    if mode >= 7
      mixed = (us[term] * 6364136223846793005 + vs[term] * 1442695040888963407 + ws[term] * 2862933555777941757 + nonce * 3202034522624059733 + term * 3935559000370003845) & 9223372036854775807 ## i64
      mixed = mixed ^ (mixed >> 29)
      axis = mixed % 3
    axes[term] = axis
    term += 1
  count

-> ffks_build_column(us, vs, ws, term, axis, delta_bit, width, column) (i64[] i64[] i64[] i64 i64 i64 i64 i64[]) i64
  cells = width * width * width ## i64
  words = ffks_words(cells) ## i64
  z = ffks_clear(column, words) ## i64
  u_mask = us[term] ## i64
  v_mask = vs[term] ## i64
  w_mask = ws[term] ## i64
  ub = 0 ## i64
  while ub < width
    u_live = ((u_mask >> ub) & 1) == 1 ## bool
    if axis == 0
      u_live = ub == delta_bit
    if u_live
      vb = 0 ## i64
      while vb < width
        v_live = ((v_mask >> vb) & 1) == 1 ## bool
        if axis == 1
          v_live = vb == delta_bit
        if v_live
          wb = 0 ## i64
          while wb < width
            w_live = ((w_mask >> wb) & 1) == 1 ## bool
            if axis == 2
              w_live = wb == delta_bit
            if w_live
              row = (ub * width + vb) * width + wb ## i64
              z = ffks_set_bit(column, row)
            wb += 1
        vb += 1
    ub += 1
  1

-> ffks_combo_delta(combo, combo_words, term, width) (i64[] i64 i64 i64) i64
  delta = 0 ## i64
  bit = 0 ## i64
  while bit < width
    variable = term * width + bit ## i64
    word = variable / 63 ## i64
    offset = variable % 63 ## i64
    if word < combo_words
      if ((combo[word] >> offset) & 1) == 1
        delta = delta ^ (1 << bit)
    bit += 1
  delta

-> ffks_materialize(us, vs, ws, count, axes, width, combo, combo_words, out_u, out_v, out_w) (i64[] i64[] i64[] i64 i64[] i64 i64[] i64 i64[] i64[] i64[]) i64
  changed = 0 ## i64
  i = 0 ## i64
  while i < count
    out_u[i] = us[i]
    out_v[i] = vs[i]
    out_w[i] = ws[i]
    delta = ffks_combo_delta(combo, combo_words, i, width) ## i64
    if delta != 0
      changed += 1
      if axes[i] == 0
        out_u[i] = out_u[i] ^ delta
      if axes[i] == 1
        out_v[i] = out_v[i] ^ delta
      if axes[i] == 2
        out_w[i] = out_w[i] ^ delta
    if out_u[i] == 0 || out_v[i] == 0 || out_w[i] == 0
      return 0
    i += 1
  changed

-> ffks_is_one_flip(source_u, source_v, source_w, count, out_u, out_v, out_w) (i64[] i64[] i64[] i64 i64[] i64[] i64[]) i64
  candidate_u = i64[count]
  candidate_v = i64[count]
  candidate_w = i64[count]
  code = 0 ## i64
  code_count = fftc_code_count(count) ## i64
  while code < code_count
    z = fftc_copy_terms(source_u, source_v, source_w, count, candidate_u, candidate_v, candidate_w) ## i64
    if fftc_apply_code(candidate_u, candidate_v, candidate_w, count, code, 0 - 1) == 1
      if fftc_terms_same_set(candidate_u, candidate_v, candidate_w, count, out_u, out_v, out_w, count) == 1
        return 1
    code += 1
  0

# Count source terms that cannot be matched in the endpoint multiset.  This is
# invariant under term ordering, unlike the positional `changed` count.  An
# ordinary compatible-pair flip replaces at most two terms, so only distances
# of at most two require the exhaustive one-flip classifier above.
-> ffks_term_set_delta(source_u, source_v, source_w, count, out_u, out_v, out_w) (i64[] i64[] i64[] i64 i64[] i64[] i64[]) i64
  used = i64[count]
  missing = 0 ## i64
  i = 0 ## i64
  while i < count
    found = 0 - 1 ## i64
    j = 0 ## i64
    while j < count && found < 0
      if used[j] == 0
        if fftc_same_term(source_u[i], source_v[i], source_w[i], out_u[j], out_v[j], out_w[j]) == 1
          found = j
      j += 1
    if found >= 0
      used[found] = 1
    if found < 0
      missing += 1
    i += 1
  missing

# Conservative peak scratch estimate in i64 words for one elimination.  The
# full-frontier 5x5 solve is only a few MiB, while the same formulation on a
# 7x7 frontier is deliberately caller-capped near two hundred MiB.
-> ffks_work_words(count, width) (i64 i64) i64
  if count < 1 || count > 256 || width < 1 || width > 49
    return 0
  rows = width * width * width ## i64
  columns = count * width ## i64
  row_words = ffks_words(rows) ## i64
  combo_words = ffks_words(columns) ## i64
  rows + columns * row_words + columns * combo_words + row_words + combo_words

# Return the first exact nonzero kernel dependency that is neither a no-op nor
# a single ordinary compatible-pair flip.  Metadata: columns, independent
# columns, dependencies considered, changed terms, local exact, one-flip
# skips, work words, status (1 hit, 0 miss, -1 malformed, -2 work cap).
-> ffks_find_novel_bounded(us, vs, ws, count, axes, width, max_work_words, out_u, out_v, out_w, meta) (i64[] i64[] i64[] i64 i64[] i64 i64 i64[] i64[] i64[] i64[]) i64
  if meta.size() < 8
    return 0
  i = 0 ## i64
  while i < 8
    meta[i] = 0
    i += 1
  if count < 2 || count > 256 || width < 1 || width > 49 || axes.size() < count || us.size() < count || vs.size() < count || ws.size() < count || out_u.size() < count || out_v.size() < count || out_w.size() < count
    meta[7] = 0 - 1
    return 0
  work_words = ffks_work_words(count, width) ## i64
  meta[6] = work_words
  if max_work_words > 0 && work_words > max_work_words
    meta[7] = 0 - 2
    return 0
  i = 0 ## i64
  while i < count
    if axes[i] < 0 || axes[i] > 2
      meta[7] = 0 - 1
      return 0
    if us[i] == 0 || vs[i] == 0 || ws[i] == 0
      meta[7] = 0 - 1
      return 0
    if (us[i] >> width) != 0 || (vs[i] >> width) != 0 || (ws[i] >> width) != 0
      meta[7] = 0 - 1
      return 0
    i += 1
  row_count = width * width * width ## i64
  row_words = ffks_words(row_count) ## i64
  column_count = count * width ## i64
  combo_words = ffks_words(column_count) ## i64
  pivot_basis = i64[row_count]
  z = ffks_clear(pivot_basis, row_count) ## i64
  i = 0
  while i < row_count
    pivot_basis[i] = 0 - 1
    i += 1
  basis_vectors = i64[column_count * row_words]
  basis_combos = i64[column_count * combo_words]
  column = i64[row_words]
  combo = i64[combo_words]
  basis_count = 0 ## i64
  dependencies = 0 ## i64
  one_flip_skips = 0 ## i64
  variable = 0 ## i64
  while variable < column_count
    term = variable / width ## i64
    delta_bit = variable % width ## i64
    z = ffks_build_column(us, vs, ws, term, axes[term], delta_bit, width, column)
    z = ffks_clear(combo, combo_words)
    z = ffks_set_bit(combo, variable)
    reducing = 1 ## i64
    while reducing == 1
      pivot = ffks_first_bit(column, row_words) ## i64
      if pivot < 0
        reducing = 0
        dependencies += 1
        changed = ffks_materialize(us, vs, ws, count, axes, width, combo, combo_words, out_u, out_v, out_w) ## i64
        if changed > 0
          if fftc_terms_same_set(us, vs, ws, count, out_u, out_v, out_w, count) == 0
            if fftc_local_exact(us, vs, ws, count, out_u, out_v, out_w, count) == 1
              set_delta = ffks_term_set_delta(us, vs, ws, count, out_u, out_v, out_w) ## i64
              one_flip = 0 ## i64
              # One ordinary flip can replace only its selected pair.  Use
              # the ordering-invariant multiset distance, then pay for the
              # exhaustive classifier only on the ambiguous small boundary.
              if set_delta <= 2
                one_flip = ffks_is_one_flip(us, vs, ws, count, out_u, out_v, out_w)
              if one_flip == 0
                meta[0] = column_count
                meta[1] = basis_count
                meta[2] = dependencies
                meta[3] = changed
                meta[4] = 1
                meta[5] = one_flip_skips
                meta[7] = 1
                return count
              one_flip_skips += 1
      if pivot >= 0
        basis_index = pivot_basis[pivot] ## i64
        if basis_index < 0
          pivot_basis[pivot] = basis_count
          z = ffks_copy_into(basis_vectors, basis_count * row_words, column, row_words)
          z = ffks_copy_into(basis_combos, basis_count * combo_words, combo, combo_words)
          basis_count += 1
          reducing = 0
        if basis_index >= 0
          z = ffks_xor_from(column, basis_vectors, basis_index * row_words, row_words)
          z = ffks_xor_from(combo, basis_combos, basis_index * combo_words, combo_words)
    variable += 1
  meta[0] = column_count
  meta[1] = basis_count
  meta[2] = dependencies
  meta[3] = 0
  meta[4] = 0
  meta[5] = one_flip_skips
  meta[7] = 0
  0

# Compatibility wrapper for the original small-window research operator.
# Large/global callers must opt into an explicit scratch budget.
-> ffks_find_novel(us, vs, ws, count, axes, width, out_u, out_v, out_w, meta) (i64[] i64[] i64[] i64 i64[] i64 i64[] i64[] i64[] i64[]) i64
  if count > 24
    return 0
  ffks_find_novel_bounded(us, vs, ws, count, axes, width, 0, out_u, out_v, out_w, meta)
