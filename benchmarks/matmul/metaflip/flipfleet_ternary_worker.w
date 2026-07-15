# Bounded pure-Tungsten FlipFleet prototype over the integer alphabet {-1,0,1}.
#
# This is intentionally separate from metaflip_worker.w.  A signed factor is
# represented by a positive mask and a negative mask, not by a base-3 packed
# integer.  Consequently every factor still fits in two i64 words through
# 7x7 (49 coordinates).  A rank-one term occupies six words:
#
#   (u_positive, u_negative, v_positive, v_negative, w_positive, w_negative)
#
# Terms are gauge-canonical: the first nonzero coefficient of U and V is +1;
# W absorbs the two compensating signs.  The exhaustive verifier sums integer
# coefficients for all n^6 cells.  Imports are therefore field-correct over Z
# (and hence Q), rather than merely correct modulo two.


# ---- state/layout ---------------------------------------------------------

-> fft_default_capacity(n) (i64) i64
  n * n * n + 4 * n * n + 32

-> fft_state_size(capacity) (i64) i64
  64 + 12 * capacity

-> fft_layout(st, n, capacity) (i64[] i64 i64) i64
  ok = 1 ## i64
  if n < 2 || n > 7 || capacity < 4
    ok = 0
  if ok == 1
    i = 0 ## i64
    while i < 64
      st[i] = 0
      i += 1
    st[0] = 1179018289              # "FFT1"
    st[1] = 1
    st[2] = n
    st[3] = n * n
    st[4] = capacity
    st[5] = 0                       # current rank
    st[6] = 0 - 1                   # best rank
    st[30] = (1 << (n * n)) - 1    # legal factor bits
    off = 64 ## i64
    oi = 32 ## i64
    while oi < 44
      st[oi] = off
      off += capacity
      oi += 1
    st[47] = off                    # required state words
  ok

-> fft_valid(st) (i64[]) i64
  ok = 1 ## i64
  if st[0] != 1179018289 || st[1] != 1
    ok = 0
  if st[2] < 2 || st[2] > 7 || st[4] < 4
    ok = 0
  ok

-> fft_seed_rng(st, seed) (i64[] i64) i64
  value = seed & 4611686018427387903 ## i64
  st[7] = (value ^ 1442695040888963407) & 9223372036854775807
  st[8] = value + value + 1
  st[7] = (st[7] * 6364136223846793005 + st[8]) & 9223372036854775807
  st[7] = (st[7] * 6364136223846793005 + st[8]) & 9223372036854775807
  1

-> fft_prepare(st, n, capacity, seed, max_debt) (i64[] i64 i64 i64 i64) i64
  ok = fft_layout(st, n, capacity) ## i64
  if ok == 1
    z = fft_seed_rng(st, seed) ## i64
    debt = max_debt ## i64
    if debt < 1
      debt = 1
    if debt > 8
      debt = 8
    st[22] = debt
    st[25] = 8192                  # work/wander block length
    st[26] = 262144                # debt restart period
    st[27] = 6                     # work-zone density slack
    st[31] = 0 - 1000000           # move of most recent split
    words = capacity * 12 ## i64
    i = 0 ## i64
    while i < words
      st[64 + i] = 0
      i += 1
  ok


# ---- signed vectors and canonical terms ----------------------------------

-> fft_popcount(x) (i64) i64
  value = x ## i64
  count = 0 ## i64
  while value != 0
    value = value & (value - 1)
    count += 1
  count

-> fft_vector_valid(st, positive, negative) (i64[] i64 i64) i64
  ok = 1 ## i64
  if (positive | negative) == 0
    ok = 0
  if (positive & negative) != 0
    ok = 0
  if ((positive | negative) & st[30]) != (positive | negative)
    ok = 0
  ok

# Compute a + sign*b, with sign in {-1,+1}.  The result is written to the two
# header scratch words 44/45.  Zero is a valid vector sum for combine/cancel;
# callers that need a rank-one factor reject it explicitly.
-> fft_vector_add(st, ap, an, bp, bn, sign) (i64[] i64 i64 i64 i64 i64) i64
  xp = bp ## i64
  xn = bn ## i64
  if sign < 0
    xp = bn
    xn = bp
  ok = 1 ## i64
  if (ap & xp) != 0 || (an & xn) != 0
    ok = 0
  if ok == 1
    positive_union = ap | xp ## i64
    negative_union = an | xn ## i64
    st[44] = positive_union & (st[30] ^ negative_union)
    st[45] = negative_union & (st[30] ^ positive_union)
  ok

-> fft_vector_relation(ap, an, bp, bn) (i64 i64 i64 i64) i64
  relation = 0 ## i64
  if ap == bp && an == bn
    relation = 1
  if ap == bn && an == bp
    relation = 0 - 1
  relation

-> fft_first_sign(positive, negative) (i64 i64) i64
  all = positive | negative ## i64
  sign = 0 ## i64
  if all != 0
    low = all & (0 - all) ## i64
    sign = 0 - 1
    if (positive & low) != 0
      sign = 1
  sign

-> fft_slot_density(st, slot) (i64[] i64) i64
  fft_popcount(st[st[32] + slot] | st[st[33] + slot]) + fft_popcount(st[st[34] + slot] | st[st[35] + slot]) + fft_popcount(st[st[36] + slot] | st[st[37] + slot])

-> fft_current_density(st) (i64[]) i64
  density = 0 ## i64
  i = 0 ## i64
  while i < st[5]
    density += fft_slot_density(st, i)
    i += 1
  density

-> fft_canonicalize_slot(st, slot) (i64[] i64) i64
  up = st[st[32] + slot] ## i64
  un = st[st[33] + slot] ## i64
  vp = st[st[34] + slot] ## i64
  vn = st[st[35] + slot] ## i64
  wp = st[st[36] + slot] ## i64
  wn = st[st[37] + slot] ## i64
  ok = fft_vector_valid(st, up, un) * fft_vector_valid(st, vp, vn) * fft_vector_valid(st, wp, wn) ## i64
  if ok == 1
    if fft_first_sign(up, un) < 0
      swap = up ## i64
      up = un
      un = swap
      swap = wp
      wp = wn
      wn = swap
    if fft_first_sign(vp, vn) < 0
      swap = vp
      vp = vn
      vn = swap
      swap = wp
      wp = wn
      wn = swap
    st[st[32] + slot] = up
    st[st[33] + slot] = un
    st[st[34] + slot] = vp
    st[st[35] + slot] = vn
    st[st[36] + slot] = wp
    st[st[37] + slot] = wn
    st[23] = st[23] + 1
  ok

-> fft_copy_current_slot(st, destination, source) (i64[] i64 i64) i64
  axis = 0 ## i64
  while axis < 6
    st[st[32 + axis] + destination] = st[st[32 + axis] + source]
    axis += 1
  1

-> fft_remove_slot(st, slot) (i64[] i64) i64
  rank = st[5] ## i64
  if slot < 0 || slot >= rank
    return 0
  last = rank - 1 ## i64
  if slot != last
    z = fft_copy_current_slot(st, slot, last) ## i64
  st[5] = last
  1


# ---- exhaustive integer verification ------------------------------------

-> fft_coefficient(positive, negative, index) (i64 i64 i64) i64
  value = 0 ## i64
  if ((positive >> index) & 1) != 0
    value = 1
  if ((negative >> index) & 1) != 0
    value = 0 - 1
  value

-> fft_verify_view_error(st, upo, uno, vpo, vno, wpo, wno, rank, n) (i64[] i64 i64 i64 i64 i64 i64 i64 i64) i64
  error = 0 ## i64
  dim = n * n ## i64
  if n < 2 || n > 7 || rank < 1 || rank > st[4]
    error = 0 - 1
  term = 0 ## i64
  while term < rank && error == 0
    if fft_vector_valid(st, st[upo + term], st[uno + term]) == 0
      error = 0 - 10
    if fft_vector_valid(st, st[vpo + term], st[vno + term]) == 0
      error = 0 - 11
    if fft_vector_valid(st, st[wpo + term], st[wno + term]) == 0
      error = 0 - 12
    term += 1
  ai = 0 ## i64
  while ai < dim && error == 0
    bi = 0 ## i64
    while bi < dim && error == 0
      ci = 0 ## i64
      while ci < dim && error == 0
        got = 0 ## i64
        term = 0
        while term < rank
          a = fft_coefficient(st[upo + term], st[uno + term], ai) ## i64
          if a != 0
            b = fft_coefficient(st[vpo + term], st[vno + term], bi) ## i64
            if b != 0
              c = fft_coefficient(st[wpo + term], st[wno + term], ci) ## i64
              got += a * b * c
          term += 1
        arow = ai / n ## i64
        acol = ai % n ## i64
        brow = bi / n ## i64
        bcol = bi % n ## i64
        crow = ci / n ## i64
        ccol = ci % n ## i64
        want = 0 ## i64
        if acol == brow && arow == crow && bcol == ccol
          want = 1
        if got != want
          error = 1 + (ai * dim + bi) * dim + ci
        ci += 1
      bi += 1
    ai += 1
  error

-> fft_current_exact_error(st) (i64[]) i64
  fft_verify_view_error(st, st[32], st[33], st[34], st[35], st[36], st[37], st[5], st[2])

-> fft_best_exact_error(st) (i64[]) i64
  fft_verify_view_error(st, st[38], st[39], st[40], st[41], st[42], st[43], st[6], st[2])

-> fft_verify_current_exact(st) (i64[]) i64
  st[18] = st[18] + 1
  ok = 0 ## i64
  if fft_valid(st) == 1 && fft_current_exact_error(st) == 0
    ok = 1
  if ok == 0
    st[19] = st[19] + 1
  ok

-> fft_verify_best_exact(st) (i64[]) i64
  st[18] = st[18] + 1
  ok = 0 ## i64
  if fft_valid(st) == 1 && st[6] > 0 && fft_best_exact_error(st) == 0
    ok = 1
  if ok == 0
    st[19] = st[19] + 1
  ok

-> fft_copy_current_to_best(st) (i64[]) i64
  i = 0 ## i64
  while i < st[5]
    axis = 0 ## i64
    while axis < 6
      st[st[38 + axis] + i] = st[st[32 + axis] + i]
      axis += 1
    i += 1
  st[6] = st[5]
  st[21] = st[20]
  st[6]

-> fft_restore_best(st) (i64[]) i64
  st[5] = st[6]
  i = 0 ## i64
  while i < st[6]
    axis = 0 ## i64
    while axis < 6
      st[st[32 + axis] + i] = st[st[38 + axis] + i]
      axis += 1
    i += 1
  st[20] = st[21]
  st[29] = st[29] + 1
  st[5]

-> fft_maybe_adopt(st) (i64[]) i64
  useful = 0 ## i64
  result = 0 ## i64
  if st[6] < 0 || st[5] < st[6]
    useful = 2
  if st[5] == st[6] && st[20] < st[21]
    useful = 1
  if useful != 0
    if fft_verify_current_exact(st) == 1
      old = st[6] ## i64
      z = fft_copy_current_to_best(st) ## i64
      result = useful
      if useful == 2 && old >= 0
        st[24] = st[24] + old - st[5]
    # fft_verify_current_exact already performed the complete n^6 integer
    # reconstruction.  Its old prototype repeated the same gate here, which
    # doubled the cost of every density/rank publication on 6x6 and 7x7.
    if result == 0
      if st[6] > 0
        z = fft_restore_best(st)
      result = 0 - 1
  result


# ---- initialization and exact ternary seeds ------------------------------

-> fft_finalize_seed(st) (i64[]) i64
  ok = 1 ## i64
  i = 0 ## i64
  while i < st[5]
    if fft_canonicalize_slot(st, i) == 0
      ok = 0
    i += 1
  st[20] = fft_current_density(st)
  result = 0 - 1 ## i64
  if ok == 1 && fft_verify_current_exact(st) == 1
    result = fft_copy_current_to_best(st)
  result

-> fft_init_terms(st, up, un, vp, vn, wp, wn, rank, n, capacity, seed, max_debt) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
  if rank < 1 || rank > capacity
    return 0 - 1
  if fft_prepare(st, n, capacity, seed, max_debt) == 0
    return 0 - 1
  st[5] = rank
  i = 0 ## i64
  while i < rank
    st[st[32] + i] = up[i]
    st[st[33] + i] = un[i]
    st[st[34] + i] = vp[i]
    st[st[35] + i] = vn[i]
    st[st[36] + i] = wp[i]
    st[st[37] + i] = wn[i]
    i += 1
  fft_finalize_seed(st)

# Load the public six-mask certificate format.  The parser is intentionally
# small and strict: one `T n rank` header, exactly six nonnegative decimal
# masks per term, and no nonempty trailing records.  `fft_init_terms` then
# applies canonicalization and the exhaustive n^6 integer gate, so a parsed
# file is not yet a trusted search seed.
-> fft_parse_nonnegative_decimal(text) (String) i64
  value = text.to_i() ## i64
  if value < 0 || value.to_s() != text
    return 0 - 1
  value

-> fft_load_seed(st, path, expected_n, capacity, seed, max_debt) (i64[] String i64 i64 i64 i64) i64
  raw = read_file(path)
  if raw == nil
    return 0 - 1
  lines = raw.split("\n")
  if lines.size() < 2
    return 0 - 1
  header = lines[0].strip().split(" ")
  if header.size() != 3 || header[0] != "T"
    return 0 - 1
  n = fft_parse_nonnegative_decimal(header[1]) ## i64
  rank = fft_parse_nonnegative_decimal(header[2]) ## i64
  if n != expected_n || n < 2 || n > 7 || rank < 1 || rank > capacity
    return 0 - 1
  up = i64[rank]
  un = i64[rank]
  vp = i64[rank]
  vn = i64[rank]
  wp = i64[rank]
  wn = i64[rank]
  term = 0 ## i64
  line_index = 1 ## i64
  while line_index < lines.size()
    line = lines[line_index].strip()
    if line != ""
      if term >= rank
        return 0 - 1
      fields = line.split(" ")
      if fields.size() != 6
        return 0 - 1
      a = fft_parse_nonnegative_decimal(fields[0]) ## i64
      b = fft_parse_nonnegative_decimal(fields[1]) ## i64
      c = fft_parse_nonnegative_decimal(fields[2]) ## i64
      d = fft_parse_nonnegative_decimal(fields[3]) ## i64
      e = fft_parse_nonnegative_decimal(fields[4]) ## i64
      f = fft_parse_nonnegative_decimal(fields[5]) ## i64
      if a < 0 || b < 0 || c < 0 || d < 0 || e < 0 || f < 0
        return 0 - 1
      up[term] = a
      un[term] = b
      vp[term] = c
      vn[term] = d
      wp[term] = e
      wn[term] = f
      term += 1
    line_index += 1
  if term != rank
    return 0 - 1
  fft_init_terms(st, up,un,vp,vn,wp,wn, rank,n,capacity,seed,max_debt)

# Clone a seed whose best view has already passed the exhaustive integer gate.
# A fleet gates each distinct input file once, then uses this path to avoid
# repeating the O(n^6 rank) import audit for every CPU island.
-> fft_clone_gated_seed(st, source, seed, max_debt) (i64[] i64[] i64 i64) i64
  if fft_valid(source) == 0 || source[6] < 1
    return 0 - 1
  if fft_prepare(st, source[2],source[4],seed,max_debt) == 0
    return 0 - 1
  st[5] = source[6]
  i = 0 ## i64
  while i < source[6]
    axis = 0 ## i64
    while axis < 6
      st[st[32 + axis] + i] = source[source[38 + axis] + i]
      axis += 1
    i += 1
  st[20] = fft_current_density(st)
  fft_copy_current_to_best(st)

# A gauge- and term-order-insensitive telemetry fingerprint.  This is not a
# proof hash; it lets bounded campaigns count returns to a changed equal-rank
# basin without sorting all rank-one terms on the hot path.
-> fft_mix63(value) (i64) i64
  x = value & 9223372036854775807 ## i64
  x = (x ^ (x >> 27)) * 6364136223846793005
  x = x & 9223372036854775807
  x = (x ^ (x >> 31)) * 1442695040888963407
  (x ^ (x >> 29)) & 9223372036854775807

-> fft_current_fingerprint(st) (i64[]) i64
  sum = 0 ## i64
  xor = 0 ## i64
  i = 0 ## i64
  while i < st[5]
    term = 0 ## i64
    axis = 0 ## i64
    while axis < 6
      word = st[st[32 + axis] + i] ## i64
      term = term ^ fft_mix63(word + (axis + 1) * 1099511628211)
      axis += 1
    term = fft_mix63(term)
    sum = (sum + term) & 9223372036854775807
    xor = xor ^ term
    i += 1
  fft_mix63(sum ^ xor ^ st[5] * 32416190071)

-> fft_init_naive(st, n, capacity, seed, max_debt) (i64[] i64 i64 i64 i64) i64
  if fft_prepare(st, n, capacity, seed, max_debt) == 0
    return 0 - 1
  rank = 0 ## i64
  i = 0 ## i64
  while i < n
    j = 0 ## i64
    while j < n
      k = 0 ## i64
      while k < n
        st[st[32] + rank] = 1 << (i * n + k)
        st[st[33] + rank] = 0
        st[st[34] + rank] = 1 << (k * n + j)
        st[st[35] + rank] = 0
        st[st[36] + rank] = 1 << (i * n + j)
        st[st[37] + rank] = 0
        rank += 1
        k += 1
      j += 1
    i += 1
  st[5] = rank
  fft_finalize_seed(st)

-> fft_seed_put(up, un, vp, vn, wp, wn, index, a, b, c, d, e, f) (i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64) i64
  up[index] = a
  un[index] = b
  vp[index] = c
  vn[index] = d
  wp[index] = e
  wn[index] = f
  1

-> fft_init_strassen(st, capacity, seed, max_debt) (i64[] i64 i64 i64) i64
  up = i64[7]
  un = i64[7]
  vp = i64[7]
  vn = i64[7]
  wp = i64[7]
  wn = i64[7]
  z = fft_seed_put(up,un,vp,vn,wp,wn,0, 9,0, 9,0, 9,0) ## i64
  z = fft_seed_put(up,un,vp,vn,wp,wn,1, 12,0, 1,0, 4,8)
  z = fft_seed_put(up,un,vp,vn,wp,wn,2, 1,0, 2,8, 10,0)
  z = fft_seed_put(up,un,vp,vn,wp,wn,3, 8,0, 4,1, 5,0)
  z = fft_seed_put(up,un,vp,vn,wp,wn,4, 3,0, 8,0, 2,1)
  z = fft_seed_put(up,un,vp,vn,wp,wn,5, 4,1, 3,0, 8,0)
  z = fft_seed_put(up,un,vp,vn,wp,wn,6, 2,8, 12,0, 1,0)
  fft_init_terms(st, up,un,vp,vn,wp,wn, 7,2,capacity,seed,max_debt)

# Laderman's practical rank-23 3x3 scheme.  Every coefficient is in
# {-1,0,1}; the initializer performs the complete 729-cell integer gate.
-> fft_init_laderman(st, capacity, seed, max_debt) (i64[] i64 i64 i64) i64
  up = i64[23]
  un = i64[23]
  vp = i64[23]
  vn = i64[23]
  wp = i64[23]
  wn = i64[23]
  z = fft_seed_put(up,un,vp,vn,wp,wn,0, 7,408, 16,0, 2,0) ## i64
  z = fft_seed_put(up,un,vp,vn,wp,wn,1, 1,8, 16,2, 24,0)
  z = fft_seed_put(up,un,vp,vn,wp,wn,2, 16,0, 266,113, 8,0)
  z = fft_seed_put(up,un,vp,vn,wp,wn,3, 24,1, 17,2, 26,0)
  z = fft_seed_put(up,un,vp,vn,wp,wn,4, 24,0, 2,1, 18,0)
  z = fft_seed_put(up,un,vp,vn,wp,wn,5, 1,0, 1,0, 351,0)
  z = fft_seed_put(up,un,vp,vn,wp,wn,6, 192,1, 33,4, 324,0)
  z = fft_seed_put(up,un,vp,vn,wp,wn,7, 64,1, 4,32, 320,0)
  z = fft_seed_put(up,un,vp,vn,wp,wn,8, 192,0, 4,1, 260,0)
  z = fft_seed_put(up,un,vp,vn,wp,wn,9, 7,240, 32,0, 4,0)
  z = fft_seed_put(up,un,vp,vn,wp,wn,10, 128,0, 140,113, 64,0)
  z = fft_seed_put(up,un,vp,vn,wp,wn,11, 384,4, 80,128, 194,0)
  z = fft_seed_put(up,un,vp,vn,wp,wn,12, 4,256, 16,128, 192,0)
  z = fft_seed_put(up,un,vp,vn,wp,wn,13, 4,0, 64,0, 239,0)
  z = fft_seed_put(up,un,vp,vn,wp,wn,14, 384,0, 128,64, 130,0)
  z = fft_seed_put(up,un,vp,vn,wp,wn,15, 48,4, 96,256, 44,0)
  z = fft_seed_put(up,un,vp,vn,wp,wn,16, 4,32, 32,256, 40,0)
  z = fft_seed_put(up,un,vp,vn,wp,wn,17, 48,0, 256,64, 36,0)
  z = fft_seed_put(up,un,vp,vn,wp,wn,18, 2,0, 8,0, 1,0)
  z = fft_seed_put(up,un,vp,vn,wp,wn,19, 32,0, 128,0, 16,0)
  z = fft_seed_put(up,un,vp,vn,wp,wn,20, 8,0, 4,0, 32,0)
  z = fft_seed_put(up,un,vp,vn,wp,wn,21, 64,0, 2,0, 128,0)
  z = fft_seed_put(up,un,vp,vn,wp,wn,22, 256,0, 256,0, 256,0)
  fft_init_terms(st, up,un,vp,vn,wp,wn, 23,3,capacity,seed,max_debt)


# ---- exact moves ----------------------------------------------------------

-> fft_rand31(st) (i64[]) i64
  st[7] = (st[7] * 6364136223846793005 + st[8]) & 9223372036854775807
  (st[7] >> 32) & 2147483647

-> fft_pair_relation(st, axis, left, right) (i64[] i64 i64 i64) i64
  base = 32 + 2 * axis ## i64
  fft_vector_relation(st[st[base] + left], st[st[base + 1] + left], st[st[base] + right], st[st[base + 1] + right])

# Signed rank-preserving 2x2 basis flip.  For shared U, for example:
#
#   u(v*w + v'*w') = u((v+s v')*w + v'*(w'-s w)).
#
# The other two axes are permutations of the same field identity.  Every
# addition/subtraction is rejected if it would create a coefficient +/-2 or a
# zero rank-one factor.
-> fft_basis_flip_pair(st, left, right, axis, sign, wander) (i64[] i64 i64 i64 i64 i64) i64
  st[12] = st[12] + 1
  if left < 0 || right < 0 || left >= st[5] || right >= st[5] || left == right || axis < 0 || axis > 2
    st[13] = st[13]
    st[11] = st[11] + 1
    return 0
  if sign >= 0
    sign = 1
  if sign < 0
    sign = 0 - 1
  relation = fft_pair_relation(st, axis, left, right) ## i64
  if relation == 0 || (axis < 2 && relation < 0)
    st[11] = st[11] + 1
    return 0

  aup = st[st[32] + left] ## i64
  aun = st[st[33] + left] ## i64
  avp = st[st[34] + left] ## i64
  avn = st[st[35] + left] ## i64
  awp = st[st[36] + left] ## i64
  awn = st[st[37] + left] ## i64
  bup0 = st[st[32] + right] ## i64
  bun0 = st[st[33] + right] ## i64
  bvp = st[st[34] + right] ## i64
  bvn = st[st[35] + right] ## i64
  bwp0 = st[st[36] + right] ## i64
  bwn0 = st[st[37] + right] ## i64
  bup = bup0 ## i64
  bun = bun0 ## i64
  bwp = bwp0 ## i64
  bwn = bwn0 ## i64
  if axis == 2 && relation < 0
    bup = bun0
    bun = bup0
    bwp = bwn0
    bwn = bwp0

  old_density = fft_slot_density(st, left) + fft_slot_density(st, right) ## i64
  ok = 1 ## i64
  x0p = 0 ## i64
  x0n = 0 ## i64
  x1p = 0 ## i64
  x1n = 0 ## i64
  if axis == 0
    ok = fft_vector_add(st, avp,avn,bvp,bvn,sign)
    if ok == 1
      x0p = st[44]
      x0n = st[45]
      ok = fft_vector_add(st, bwp,bwn,awp,awn,0-sign)
      x1p = st[44]
      x1n = st[45]
  if axis == 1
    ok = fft_vector_add(st, aup,aun,bup,bun,sign)
    if ok == 1
      x0p = st[44]
      x0n = st[45]
      ok = fft_vector_add(st, bwp,bwn,awp,awn,0-sign)
      x1p = st[44]
      x1n = st[45]
  if axis == 2
    ok = fft_vector_add(st, aup,aun,bup,bun,sign)
    if ok == 1
      x0p = st[44]
      x0n = st[45]
      ok = fft_vector_add(st, bvp,bvn,avp,avn,0-sign)
      x1p = st[44]
      x1n = st[45]
  if ok == 0 || (x0p | x0n) == 0 || (x1p | x1n) == 0
    st[11] = st[11] + 1
    return 0

  if axis == 0
    st[st[34] + left] = x0p
    st[st[35] + left] = x0n
    st[st[36] + right] = x1p
    st[st[37] + right] = x1n
  if axis == 1
    st[st[32] + left] = x0p
    st[st[33] + left] = x0n
    st[st[36] + right] = x1p
    st[st[37] + right] = x1n
  if axis == 2
    st[st[32] + left] = x0p
    st[st[33] + left] = x0n
    st[st[32] + right] = bup
    st[st[33] + right] = bun
    st[st[34] + right] = x1p
    st[st[35] + right] = x1n
    st[st[36] + right] = bwp
    st[st[37] + right] = bwn
  z = fft_canonicalize_slot(st, left) ## i64
  z = fft_canonicalize_slot(st, right)
  new_density = fft_slot_density(st, left) + fft_slot_density(st, right) ## i64
  accept = 0 ## i64
  if new_density <= old_density + st[27]
    accept = 1
  if wander != 0
    accept = 1
  if accept == 0
    st[st[32] + left] = aup
    st[st[33] + left] = aun
    st[st[34] + left] = avp
    st[st[35] + left] = avn
    st[st[36] + left] = awp
    st[st[37] + left] = awn
    st[st[32] + right] = bup0
    st[st[33] + right] = bun0
    st[st[34] + right] = bvp
    st[st[35] + right] = bvn
    st[st[36] + right] = bwp0
    st[st[37] + right] = bwn0
    st[11] = st[11] + 1
    return 0
  st[20] = st[20] + new_density - old_density
  st[10] = st[10] + 1
  st[13] = st[13] + 1
  adopted = fft_maybe_adopt(st) ## i64
  if adopted == 2
    return 2
  if adopted < 0
    return 0 - 1
  1

-> fft_try_flip(st, wander) (i64[] i64) i64
  rank = st[5] ## i64
  if rank < 2
    st[12] = st[12] + 1
    st[11] = st[11] + 1
    return 0
  left = fft_rand31(st) % rank ## i64
  axis = fft_rand31(st) % 3 ## i64
  start = fft_rand31(st) % rank ## i64
  scanned = 0 ## i64
  while scanned < rank
    right = (start + scanned) % rank ## i64
    if right != left
      relation = fft_pair_relation(st, axis, left, right) ## i64
      if relation != 0 && (axis == 2 || relation > 0)
        sign = 1 ## i64
        if (fft_rand31(st) & 1) != 0
          sign = 0 - 1
        return fft_basis_flip_pair(st, left, right, axis,sign,wander)
    scanned += 1
  st[12] = st[12] + 1
  st[11] = st[11] + 1
  0

# Split target = donor + (target-donor) on one factor.  Unlike a blind support
# partition, the first child immediately shares a factor with another term in
# the scheme and therefore opens a real flip door from minimal seeds.
-> fft_split_with_donor(st, target, donor, axis) (i64[] i64 i64 i64) i64
  st[14] = st[14] + 1
  if st[5] >= st[4] || st[5] >= st[6] + st[22]
    return 0
  if target < 0 || donor < 0 || target >= st[5] || donor >= st[5] || target == donor || axis < 0 || axis > 2
    return 0
  base = 32 + axis * 2 ## i64
  if fft_vector_add(st, st[st[base] + target], st[st[base + 1] + target], st[st[base] + donor], st[st[base + 1] + donor], 0-1) == 0
    return 0
  remainder_p = st[44] ## i64
  remainder_n = st[45] ## i64
  if (remainder_p | remainder_n) == 0
    return 0
  new_slot = st[5] ## i64
  z = fft_copy_current_slot(st, new_slot, target) ## i64
  st[st[base] + target] = st[st[base] + donor]
  st[st[base + 1] + target] = st[st[base + 1] + donor]
  st[st[base] + new_slot] = remainder_p
  st[st[base + 1] + new_slot] = remainder_n
  st[5] = st[5] + 1
  z = fft_canonicalize_slot(st, target)
  z = fft_canonicalize_slot(st, new_slot)
  st[20] = fft_current_density(st)
  st[10] = st[10] + 1
  st[15] = st[15] + 1
  st[31] = st[9]
  1

-> fft_split_partition(st, target, axis, selector) (i64[] i64 i64 i64) i64
  st[14] = st[14] + 1
  if st[5] >= st[4] || st[5] >= st[6] + st[22]
    return 0
  if target < 0 || target >= st[5] || axis < 0 || axis > 2
    return 0
  base = 32 + axis * 2 ## i64
  positive = st[st[base] + target] ## i64
  negative = st[st[base + 1] + target] ## i64
  support = positive | negative ## i64
  if fft_popcount(support) < 2
    return 0
  part = support & selector ## i64
  if part == 0 || part == support
    part = support & (0 - support)
  rest = support ^ part ## i64
  if rest == 0
    return 0
  new_slot = st[5] ## i64
  z = fft_copy_current_slot(st, new_slot, target) ## i64
  st[st[base] + target] = positive & part
  st[st[base + 1] + target] = negative & part
  st[st[base] + new_slot] = positive & rest
  st[st[base + 1] + new_slot] = negative & rest
  st[5] = st[5] + 1
  z = fft_canonicalize_slot(st, target)
  z = fft_canonicalize_slot(st, new_slot)
  st[20] = fft_current_density(st)
  st[10] = st[10] + 1
  st[15] = st[15] + 1
  st[31] = st[9]
  1

-> fft_try_split(st) (i64[]) i64
  if st[5] >= st[4] || st[5] >= st[6] + st[22]
    st[14] = st[14] + 1
    return 0
  rank = st[5] ## i64
  trial = 0 ## i64
  while trial < 16
    target = fft_rand31(st) % rank ## i64
    donor = fft_rand31(st) % rank ## i64
    axis = fft_rand31(st) % 3 ## i64
    if target != donor
      if fft_split_with_donor(st, target,donor,axis) == 1
        return 1
    trial += 1
  target = fft_rand31(st) % rank
  axis = fft_rand31(st) % 3
  selector = (fft_rand31(st) << 31) ^ fft_rand31(st) ## i64
  fft_split_partition(st, target,axis,selector)

# Combine two terms sharing two projective factors.  If W is opposite, its
# sign is absorbed into the changing U or V factor before addition.
-> fft_combine_pair_axis(st, left, right, changing_axis) (i64[] i64 i64 i64) i64
  if left < 0 || right <= left || right >= st[5]
    return 0
  relation = 1 ## i64
  if changing_axis == 0
    if fft_pair_relation(st, 1,left,right) != 1
      return 0
    relation = fft_pair_relation(st, 2,left,right)
    if relation == 0
      return 0
  if changing_axis == 1
    if fft_pair_relation(st, 0,left,right) != 1
      return 0
    relation = fft_pair_relation(st, 2,left,right)
    if relation == 0
      return 0
  if changing_axis == 2
    if fft_pair_relation(st, 0,left,right) != 1 || fft_pair_relation(st, 1,left,right) != 1
      return 0
    relation = 1
  base = 32 + changing_axis * 2 ## i64
  if fft_vector_add(st, st[st[base] + left], st[st[base + 1] + left], st[st[base] + right], st[st[base + 1] + right], relation) == 0
    return 0
  combined_p = st[44] ## i64
  combined_n = st[45] ## i64
  before = st[5] ## i64
  if (combined_p | combined_n) == 0
    z = fft_remove_slot(st, right) ## i64
    z = fft_remove_slot(st, left)
  if (combined_p | combined_n) != 0
    st[st[base] + left] = combined_p
    st[st[base + 1] + left] = combined_n
    z = fft_canonicalize_slot(st, left) ## i64
    z = fft_remove_slot(st, right)
  st[20] = fft_current_density(st)
  st[10] = st[10] + 1
  st[17] = st[17] + 1
  if before > st[5]
    st[24] = st[24] + before - st[5]
  adopted = fft_maybe_adopt(st) ## i64
  if adopted == 2
    return 2
  if adopted < 0
    return 0 - 1
  1

-> fft_try_combine(st) (i64[]) i64
  st[16] = st[16] + 1
  i = 0 ## i64
  while i < st[5]
    j = i + 1 ## i64
    while j < st[5]
      axis = 0 ## i64
      while axis < 3
        result = fft_combine_pair_axis(st, i,j,axis) ## i64
        if result != 0
          return result
        axis += 1
      j += 1
    i += 1
  0


# ---- bounded walker/export -----------------------------------------------

-> fft_step(st) (i64[]) i64
  moves = st[9] ## i64
  result = 0 ## i64
  if moves > 0 && (moves % st[26]) == 0 && st[5] > st[6]
    z = fft_restore_best(st) ## i64
  combine_period = 128 ## i64
  if st[5] > st[6]
    combine_period = 16
  # A newly inserted donor is a catalyst.  Give basis flips 512 moves to
  # redistribute it before allowing the obvious inverse combine.
  allow_combine = 1 ## i64
  if st[5] > st[6] && moves - st[31] < 512
    allow_combine = 0
  if allow_combine == 1 && (moves % combine_period) == 0
    result = fft_try_combine(st)
  if result == 0 && (moves % 1024) == 1023 && st[5] < st[6] + st[22]
    result = fft_try_split(st)
  if result == 0
    wander = 0 ## i64
    if ((moves / st[25]) % 4) == 3
      wander = 1
    result = fft_try_flip(st, wander)
  st[9] = moves + 1
  result

-> fft_walk(st, steps) (i64[] i64) i64
  rank_drops = 0 ## i64
  i = 0 ## i64
  while i < steps
    result = fft_step(st) ## i64
    if result == 2
      rank_drops += 1
    if result < 0
      return 0 - 1
    i += 1
  rank_drops

-> fft_export_best(st, up,un,vp,vn,wp,wn) (i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  if fft_verify_best_exact(st) == 0
    return 0 - 1
  i = 0 ## i64
  while i < st[6]
    up[i] = st[st[38] + i]
    un[i] = st[st[39] + i]
    vp[i] = st[st[40] + i]
    vn[i] = st[st[41] + i]
    wp[i] = st[st[42] + i]
    wn[i] = st[st[43] + i]
    i += 1
  st[6]

-> fft_dump_current(st, path) (i64[] String) i64
  if fft_verify_current_exact(st) == 0
    return 0 - 1
  body = "T " + st[2].to_s() + " " + st[5].to_s() + "\n"
  i = 0 ## i64
  while i < st[5]
    body = body + st[st[32]+i].to_s() + " " + st[st[33]+i].to_s() + " " + st[st[34]+i].to_s() + " " + st[st[35]+i].to_s() + " " + st[st[36]+i].to_s() + " " + st[st[37]+i].to_s() + "\n"
    i += 1
  wrote = write_file(path, body)
  if wrote
    return st[5]
  0 - 1

-> fft_dump_best(st, path) (i64[] String) i64
  if fft_verify_best_exact(st) == 0
    return 0 - 1
  body = "T " + st[2].to_s() + " " + st[6].to_s() + "\n"
  i = 0 ## i64
  while i < st[6]
    body = body + st[st[38]+i].to_s() + " " + st[st[39]+i].to_s() + " " + st[st[40]+i].to_s() + " " + st[st[41]+i].to_s() + " " + st[st[42]+i].to_s() + " " + st[st[43]+i].to_s() + "\n"
    i += 1
  wrote = write_file(path, body)
  if wrote
    return st[6]
  0 - 1
