# Exact signed two-parent nullspace geometry for strict {-1,0,1} schemes.
#
# Equal terms are removed from A and B before forming the signed union
#
#   A_remaining + (-B_remaining) = 0.
#
# Each term is already gauge-canonical in the ternary worker: the leading U
# and V coefficients are positive and W carries the total tensor sign.  Thus
# the six masks identify a signed rank-one tensor without probabilistic
# hashing.  Modular row elimination evaluates every coefficient exactly mod p
# and may stop once rank columns-1 is reached, because the all-ones parent
# difference is a known relation.

use flipfleet_ternary_worker

-> fftpns_term_equal(left, left_term, right, right_term) (i64[] i64 i64[] i64) i64
  axis = 0 ## i64
  while axis < 6
    if left[left[32 + axis] + left_term] != right[right[32 + axis] + right_term]
      return 0
    axis += 1
  1

# Gauge-canonical signed tensor negation swaps only the W positive/negative
# masks.  U and V remain in their canonical leading-positive gauges.
-> fftpns_term_opposite(left, left_term, right, right_term) (i64[] i64 i64[] i64) i64
  axis = 0 ## i64
  while axis < 4
    if left[left[32 + axis] + left_term] != right[right[32 + axis] + right_term]
      return 0
    axis += 1
  if left[left[36] + left_term] != right[right[37] + right_term]
    return 0
  if left[left[37] + left_term] != right[right[36] + right_term]
    return 0
  1

# Remove exact common signed columns with a collision-free six-mask compare.
# meta: left-only count, right-only count, common count, union columns.
-> fftpns_reduced_union(left, right, left_indices, right_indices, meta) (i64[] i64[] i64[] i64[] i64[]) i64
  used_right = i64[right[5]]
  left_count = 0 ## i64
  common = 0 ## i64
  i = 0 ## i64
  while i < left[5]
    match = 0 - 1 ## i64
    j = 0 ## i64
    while j < right[5] && match < 0
      if used_right[j] == 0 && fftpns_term_equal(left, i, right, j) == 1
        match = j
      j += 1
    if match >= 0
      used_right[match] = 1
      common += 1
    else
      left_indices[left_count] = i
      left_count += 1
    i += 1
  right_count = 0 ## i64
  j = 0
  while j < right[5]
    if used_right[j] == 0
      right_indices[right_count] = j
      right_count += 1
    j += 1
  meta[0] = left_count
  meta[1] = right_count
  meta[2] = common
  meta[3] = left_count + right_count
  meta[3]

-> fftpns_column_coefficient(st, term, ai, bi, ci) (i64[] i64 i64 i64 i64) i64
  a = fft_coefficient(st[st[32] + term], st[st[33] + term], ai) ## i64
  if a == 0
    return 0
  b = fft_coefficient(st[st[34] + term], st[st[35] + term], bi) ## i64
  if b == 0
    return 0
  c = fft_coefficient(st[st[36] + term], st[st[37] + term], ci) ## i64
  a * b * c

-> fftpns_mod_pow(base, exponent, prime) (i64 i64 i64) i64
  result = 1 ## i64
  value = base % prime ## i64
  power = exponent ## i64
  while power > 0
    if (power & 1) != 0
      result = (result * value) % prime
    value = (value * value) % prime
    power = power >> 1
  result

-> fftpns_mod_sub_product(value, factor, basis_value, prime) (i64 i64 i64 i64) i64
  product = (factor * basis_value) % prime ## i64
  if value >= product
    return value - product
  value + prime - product

# Deterministic diagonal weights for proof-safe Gram screening.  Profile zero
# is the ordinary dot product; later profiles use distinct integer
# polynomials on each tensor axis.  No probabilistic hash is involved.
-> fftpns_gram_weight(index, axis, profile, prime) (i64 i64 i64 i64) i64
  if profile == 0
    return 1
  x = index + 1 ## i64
  q = profile + 1 ## i64
  x2 = x * x ## i64
  value = 1 + (axis + 2) * q * x ## i64
  value += (profile + axis + 3) * x2
  value += (axis * profile + 1) * x2 * x
  value % prime

-> fftpns_weighted_factor_dot(ap, an, bp, bn, dim, axis, profile, prime) (i64 i64 i64 i64 i64 i64 i64 i64) i64
  total = 0 ## i64
  index = 0 ## i64
  while index < dim
    left_value = ((ap >> index) & 1) - ((an >> index) & 1) ## i64
    if left_value != 0
      right_value = ((bp >> index) & 1) - ((bn >> index) & 1) ## i64
      if right_value != 0
        total += left_value * right_value * fftpns_gram_weight(index, axis, profile, prime)
    index += 1
  total %= prime
  if total < 0
    total += prime
  total

# Copy the signed union A_remaining + (-B_remaining) into compact factor
# arrays.  `signs` is +1 for A columns and -1 for B columns.
-> fftpns_union_factor_arrays(left, right, left_indices, left_count, right_indices, right_count, up, un, vp, vn, wp, wn, signs) (i64[] i64[] i64[] i64 i64[] i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  column = 0 ## i64
  while column < left_count
    term = left_indices[column] ## i64
    up[column] = left[left[32] + term]
    un[column] = left[left[33] + term]
    vp[column] = left[left[34] + term]
    vn[column] = left[left[35] + term]
    wp[column] = left[left[36] + term]
    wn[column] = left[left[37] + term]
    signs[column] = 1
    column += 1
  j = 0 ## i64
  while j < right_count
    column = left_count + j
    term = right_indices[j] ## i64
    up[column] = right[right[32] + term]
    un[column] = right[right[33] + term]
    vp[column] = right[right[34] + term]
    vn[column] = right[right[35] + term]
    wp[column] = right[right[36] + term]
    wn[column] = right[right[37] + term]
    signs[column] = 0 - 1
    j += 1
  left_count + right_count

# Rank of vertically stacked weighted Gram matrices
#
#   G_q = M^T D_q M  (mod p).
#
# Every row of every G_q belongs to row(M), so this rank is a deterministic
# lower bound on rank(M), never a heuristic upper estimate.  Since M*1=0 for
# the parent difference, reaching columns-1 proves the all-ones relation is
# the complete rational nullspace.  If it does not reach columns-1, the
# resulting (possibly enlarged) kernel is safe to exhaust: every true binary
# relation is still present and the integer coefficient gate rejects extras.
# meta: Gram rows visited, nonzero rows, parent-relation failures, profiles.
-> fftpns_stacked_gram_rank(up, un, vp, vn, wp, wn, signs, columns, dim, prime, profile_count, basis, have, meta) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64 i64 i64[] i64[] i64[]) i64
  if columns == 0
    return 0
  row_values = i64[columns]
  rank = 0 ## i64
  profile = 0 ## i64
  while profile < profile_count && rank < columns - 1
    source = 0 ## i64
    while source < columns && rank < columns - 1
      relation_sum = 0 ## i64
      column = 0 ## i64
      while column < columns
        u_dot = fftpns_weighted_factor_dot(up[source], un[source], up[column], un[column], dim, 0, profile, prime) ## i64
        value = 0 ## i64
        if u_dot != 0
          v_dot = fftpns_weighted_factor_dot(vp[source], vn[source], vp[column], vn[column], dim, 1, profile, prime) ## i64
          if v_dot != 0
            w_dot = fftpns_weighted_factor_dot(wp[source], wn[source], wp[column], wn[column], dim, 2, profile, prime) ## i64
            value = (((u_dot * v_dot) % prime) * w_dot) % prime
            if signs[source] != signs[column] && value != 0
              value = prime - value
        row_values[column] = value
        relation_sum += value
        relation_sum %= prime
        column += 1
      if relation_sum != 0
        meta[2] += 1
        return 0 - 1

      pivot = 0 ## i64
      admitted = 0 ## i64
      nonzero = 0 ## i64
      while pivot < columns && admitted == 0
        value = row_values[pivot] ## i64
        if value != 0
          nonzero = 1
          if have[pivot] == 1
            column = pivot
            while column < columns
              row_values[column] = fftpns_mod_sub_product(row_values[column], value, basis[pivot * columns + column], prime)
              column += 1
          else
            inverse = fftpns_mod_pow(value, prime - 2, prime) ## i64
            column = pivot
            while column < columns
              normalized = (row_values[column] * inverse) % prime ## i64
              row_values[column] = normalized
              basis[pivot * columns + column] = normalized
              column += 1
            have[pivot] = 1
            rank += 1
            admitted = 1
        pivot += 1
      if nonzero != 0
        meta[1] += 1
      meta[0] += 1
      source += 1
    meta[3] += 1
    profile += 1
  rank

# Exact modular column rank from coefficient rows.  `basis` stores normalized
# echelon rows indexed by pivot column and `have` marks pivots.  meta: rows
# visited, nonzero rows, relation failures, total tensor rows.
-> fftpns_modular_rank(left, right, left_indices, left_count, right_indices, right_count, n, prime, basis, have, meta) (i64[] i64[] i64[] i64 i64[] i64 i64 i64 i64[] i64[] i64[]) i64
  columns = left_count + right_count ## i64
  if columns == 0
    meta[3] = n * n * n * n * n * n
    return 0
  dim = n * n ## i64
  cells = dim * dim * dim ## i64
  meta[3] = cells
  row = i64[columns]
  rank = 0 ## i64
  step = 0 ## i64
  while step < cells && rank < columns - 1
    # 8191 is coprime to 5^6, 6^6, and 7^6, giving a deterministic full
    # permutation that scatters coordinate supports early in elimination.
    cell = (step * 8191 + 97) % cells ## i64
    ai = cell / (dim * dim) ## i64
    bi = (cell / dim) % dim ## i64
    ci = cell % dim ## i64
    relation_sum = 0 ## i64
    column = 0 ## i64
    while column < left_count
      # Keep this hot path inline.  Tungsten currently copies array arguments
      # at ordinary function boundaries; calling fftpns_column_coefficient
      # here would copy the complete worker state once per matrix entry.
      term = left_indices[column] ## i64
      coefficient = ((left[left[32] + term] >> ai) & 1) - ((left[left[33] + term] >> ai) & 1) ## i64
      if coefficient != 0
        coefficient *= ((left[left[34] + term] >> bi) & 1) - ((left[left[35] + term] >> bi) & 1)
      if coefficient != 0
        coefficient *= ((left[left[36] + term] >> ci) & 1) - ((left[left[37] + term] >> ci) & 1)
      relation_sum += coefficient
      value = coefficient ## i64
      if value < 0
        value += prime
      row[column] = value
      column += 1
    j = 0 ## i64
    while j < right_count
      term = right_indices[j] ## i64
      coefficient = ((right[right[32] + term] >> ai) & 1) - ((right[right[33] + term] >> ai) & 1) ## i64
      if coefficient != 0
        coefficient *= ((right[right[34] + term] >> bi) & 1) - ((right[right[35] + term] >> bi) & 1)
      if coefficient != 0
        coefficient *= ((right[right[36] + term] >> ci) & 1) - ((right[right[37] + term] >> ci) & 1)
      coefficient = 0 - coefficient
      relation_sum += coefficient
      value = coefficient ## i64
      if value < 0
        value += prime
      row[left_count + j] = value
      j += 1
    if relation_sum != 0
      meta[2] += 1
      return 0 - 1

    pivot = 0 ## i64
    admitted = 0 ## i64
    nonzero = 0 ## i64
    while pivot < columns && admitted == 0
      value = row[pivot] ## i64
      if value != 0
        nonzero = 1
        if have[pivot] == 1
          column = pivot
          while column < columns
            row[column] = fftpns_mod_sub_product(row[column], value, basis[pivot * columns + column], prime)
            column += 1
        else
          inverse = fftpns_mod_pow(value, prime - 2, prime) ## i64
          column = pivot
          while column < columns
            normalized = (row[column] * inverse) % prime ## i64
            row[column] = normalized
            basis[pivot * columns + column] = normalized
            column += 1
          have[pivot] = 1
          rank += 1
          admitted = 1
      pivot += 1
    if nonzero != 0
      meta[1] += 1
    meta[0] += 1
    step += 1
  rank

# Full integer check of a selected zero relation.  `vector` is indexed first
# by left-only columns and then by negated right-only columns.
-> fftpns_subset_exact(left, right, left_indices, left_count, right_indices, right_count, vector, n) (i64[] i64[] i64[] i64 i64[] i64 i64[] i64) i64
  dim = n * n ## i64
  ai = 0 ## i64
  while ai < dim
    bi = 0 ## i64
    while bi < dim
      ci = 0 ## i64
      while ci < dim
        total = 0 ## i64
        column = 0 ## i64
        while column < left_count
          if vector[column] == 1
            term = left_indices[column] ## i64
            coefficient = ((left[left[32] + term] >> ai) & 1) - ((left[left[33] + term] >> ai) & 1) ## i64
            if coefficient != 0
              coefficient *= ((left[left[34] + term] >> bi) & 1) - ((left[left[35] + term] >> bi) & 1)
            if coefficient != 0
              coefficient *= ((left[left[36] + term] >> ci) & 1) - ((left[left[37] + term] >> ci) & 1)
            total += coefficient
          column += 1
        j = 0 ## i64
        while j < right_count
          if vector[left_count + j] == 1
            term = right_indices[j] ## i64
            coefficient = ((right[right[32] + term] >> ai) & 1) - ((right[right[33] + term] >> ai) & 1) ## i64
            if coefficient != 0
              coefficient *= ((right[right[34] + term] >> bi) & 1) - ((right[right[35] + term] >> bi) & 1)
            if coefficient != 0
              coefficient *= ((right[right[36] + term] >> ci) & 1) - ((right[right[37] + term] >> ci) & 1)
            total -= coefficient
          j += 1
        if total != 0
          return 0
        ci += 1
      bi += 1
    ai += 1
  1

-> fftpns_union_exact(left, right, left_indices, left_count, right_indices, right_count, n) (i64[] i64[] i64[] i64 i64[] i64 i64) i64
  vector = i64[left_count + right_count]
  i = 0 ## i64
  while i < vector.size()
    vector[i] = 1
    i += 1
  fftpns_subset_exact(left, right, left_indices, left_count, right_indices, right_count, vector, n)

# Solve the echelon system for one assignment of its free coordinates.  Free
# coordinates are assigned the bits of `assignment` in increasing order.
# Return the modular nullity.
-> fftpns_null_vector(basis, have, columns, prime, assignment, out) (i64[] i64[] i64 i64 i64 i64[]) i64
  free_count = 0 ## i64
  column = 0 ## i64
  while column < columns
    out[column] = 0
    if have[column] == 0
      if ((assignment >> free_count) & 1) != 0
        out[column] = 1
      free_count += 1
    column += 1
  pivot = columns - 1 ## i64
  while pivot >= 0
    if have[pivot] == 1
      sum = 0 ## i64
      column = pivot + 1
      while column < columns
        if out[column] != 0 && basis[pivot * columns + column] != 0
          sum = (sum + basis[pivot * columns + column] * out[column]) % prime
        column += 1
      if sum == 0
        out[pivot] = 0
      else
        out[pivot] = prime - sum
    pivot -= 1
  free_count

-> fftpns_binary_vector(vector) (i64[]) i64
  i = 0 ## i64
  while i < vector.size()
    if vector[i] != 0 && vector[i] != 1
      return 0
    i += 1
  1

-> fftpns_all_ones(vector) (i64[]) i64
  i = 0 ## i64
  while i < vector.size()
    if vector[i] != 1
      return 0
    i += 1
  1

-> fftpns_raw_opposite(up, un, vp, vn, wp, wn, left, right) (i64[] i64[] i64[] i64[] i64[] i64[] i64 i64) i64
  if up[left] != up[right] || un[left] != un[right] || vp[left] != vp[right] || vn[left] != vn[right]
    return 0
  if wp[left] != wn[right] || wn[left] != wp[right]
    return 0
  1

# Splice selected B terms into A, cancel exact opposite tensor pairs, then use
# the ternary worker's strict parser-equivalent initialization and exhaustive
# n^6 integer gate.  meta: selected A/B, raw rank, opposite cancellations,
# gated rank, exact.
-> fftpns_materialize(left, right, left_indices, left_count, right_indices, right_count, vector, seed, meta) (i64[] i64[] i64[] i64 i64[] i64 i64[] i64 i64[])
  remove_left = i64[left[5]]
  selected_left = 0 ## i64
  i = 0 ## i64
  while i < left_count
    if vector[i] == 1
      remove_left[left_indices[i]] = 1
      selected_left += 1
    i += 1
  selected_right = 0 ## i64
  j = 0 ## i64
  while j < right_count
    if vector[left_count + j] == 1
      selected_right += 1
    j += 1
  raw_capacity = left[5] + selected_right ## i64
  up = i64[raw_capacity]
  un = i64[raw_capacity]
  vp = i64[raw_capacity]
  vn = i64[raw_capacity]
  wp = i64[raw_capacity]
  wn = i64[raw_capacity]
  raw_count = 0 ## i64
  term = 0 ## i64
  while term < left[5]
    if remove_left[term] == 0
      up[raw_count] = left[left[32] + term]
      un[raw_count] = left[left[33] + term]
      vp[raw_count] = left[left[34] + term]
      vn[raw_count] = left[left[35] + term]
      wp[raw_count] = left[left[36] + term]
      wn[raw_count] = left[left[37] + term]
      raw_count += 1
    term += 1
  j = 0
  while j < right_count
    if vector[left_count + j] == 1
      term = right_indices[j] ## i64
      up[raw_count] = right[right[32] + term]
      un[raw_count] = right[right[33] + term]
      vp[raw_count] = right[right[34] + term]
      vn[raw_count] = right[right[35] + term]
      wp[raw_count] = right[right[36] + term]
      wn[raw_count] = right[right[37] + term]
      raw_count += 1
    j += 1

  used = i64[raw_count]
  compact_up = i64[raw_count]
  compact_un = i64[raw_count]
  compact_vp = i64[raw_count]
  compact_vn = i64[raw_count]
  compact_wp = i64[raw_count]
  compact_wn = i64[raw_count]
  compact_count = 0 ## i64
  cancellations = 0 ## i64
  term = 0
  while term < raw_count
    if used[term] == 0
      opposite = 0 - 1 ## i64
      other = term + 1 ## i64
      while other < raw_count && opposite < 0
        if used[other] == 0 && fftpns_raw_opposite(up, un, vp, vn, wp, wn, term, other) == 1
          opposite = other
        other += 1
      if opposite >= 0
        used[opposite] = 1
        cancellations += 1
      else
        compact_up[compact_count] = up[term]
        compact_un[compact_count] = un[term]
        compact_vp[compact_count] = vp[term]
        compact_vn[compact_count] = vn[term]
        compact_wp[compact_count] = wp[term]
        compact_wn[compact_count] = wn[term]
        compact_count += 1
    term += 1

  meta[0] = selected_left
  meta[1] = selected_right
  meta[2] = raw_count
  meta[3] = cancellations
  meta[4] = compact_count
  if compact_count < 1
    return nil
  n = left[2] ## i64
  capacity = fft_default_capacity(n) ## i64
  if capacity < compact_count
    capacity = compact_count + 8
  child = i64[fft_state_size(capacity)]
  rank = fft_init_terms(child, compact_up, compact_un, compact_vp, compact_vn, compact_wp, compact_wn, compact_count, n, capacity, seed, 4) ## i64
  if rank != compact_count || fft_verify_current_exact(child) != 1
    return nil
  meta[5] = 1
  child
