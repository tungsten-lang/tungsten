use flipfleet_ternary_index_word2

# Atomic reduced length-three words in one physical-index isotropy group.
# Final P / P^-T endpoints must be strict ternary, but either of the two
# elementary prefix states may leave {-1,0,1}.  Adjacent inverse generators,
# noncanonical orderings of commuting generators, and signed-permutation
# (coordinate relabeling) matrices are rejected by fftiw3_reduction_reason.

-> fftiw3_generator_id(n,destination,source,sign) (i64 i64 i64 i64) i64
  bit = 0 ## i64
  if sign > 0
    bit = 1
  2 * (destination * n + source) + bit

-> fftiw3_inverse_pair(d1,s1,c1,d2,s2,c2) (i64 i64 i64 i64 i64 i64) i64
  if d1 == d2 && s1 == s2 && ((c1 > 0 && c2 < 0) || (c1 < 0 && c2 > 0))
    return 1
  0

# Row additions E(destination,source) commute precisely when neither source
# is the other's destination.  Canonical ID order quotients their obvious
# reordering duplicates.
-> fftiw3_commute(d1,s1,d2,s2) (i64 i64 i64 i64) i64
  if s1 != d2 && s2 != d1
    return 1
  0

# A signed permutation matrix only relabels/signs physical coordinates.  It
# preserves support size and conjugates the bounded move graph, so it is not a
# tunnel candidate.  Build P exactly from the three row additions.
-> fftiw3_relabel_only(n,d1,s1,c1,d2,s2,c2,d3,s3,c3) (i64 i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
  matrix = i64[49]
  i = 0 ## i64
  while i < n
    matrix[i*n+i] = 1
    i += 1
  if c1 >= 0
    c1 = 1
  else
    c1 = 0 - 1
  if c2 >= 0
    c2 = 1
  else
    c2 = 0 - 1
  if c3 >= 0
    c3 = 1
  else
    c3 = 0 - 1
  column = 0 ## i64
  while column < n
    matrix[d1*n+column] += c1 * matrix[s1*n+column]
    column += 1
  column = 0
  while column < n
    matrix[d2*n+column] += c2 * matrix[s2*n+column]
    column += 1
  column = 0
  while column < n
    matrix[d3*n+column] += c3 * matrix[s3*n+column]
    column += 1
  row = 0 ## i64
  while row < n
    count = 0 ## i64
    column = 0
    while column < n
      value = matrix[row*n+column] ## i64
      if value != 0
        if value != 1 && value != 0 - 1
          return 0
        count += 1
      column += 1
    if count != 1
      return 0
    row += 1
  column = 0
  while column < n
    count = 0
    row = 0
    while row < n
      if matrix[row*n+column] != 0
        count += 1
      row += 1
    if count != 1
      return 0
    column += 1
  1

# 0 means retained.  1 adjacent cancellation, 2 commuting-order duplicate,
# 3 signed coordinate relabeling, 4 malformed.
-> fftiw3_reduction_reason(n,d1,s1,c1,d2,s2,c2,d3,s3,c3) (i64 i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
  if n < 2 || n > 7 || d1 < 0 || d1 >= n || s1 < 0 || s1 >= n || d1 == s1 || d2 < 0 || d2 >= n || s2 < 0 || s2 >= n || d2 == s2 || d3 < 0 || d3 >= n || s3 < 0 || s3 >= n || d3 == s3
    return 4
  if fftiw3_inverse_pair(d1,s1,c1,d2,s2,c2) == 1 || fftiw3_inverse_pair(d2,s2,c2,d3,s3,c3) == 1
    return 1
  id1 = fftiw3_generator_id(n,d1,s1,c1) ## i64
  id2 = fftiw3_generator_id(n,d2,s2,c2) ## i64
  id3 = fftiw3_generator_id(n,d3,s3,c3) ## i64
  if fftiw3_commute(d1,s1,d2,s2) == 1 && id1 > id2
    return 2
  if fftiw3_commute(d2,s2,d3,s3) == 1 && id2 > id3
    return 2
  # Three transvections can become monomial only in the two-coordinate Weyl
  # pattern; avoid building a matrix for every generic audit word.
  if d1 == d3 && s1 == s3 && d2 == s1 && s2 == d1
    if fftiw3_relabel_only(n,d1,s1,c1,d2,s2,c2,d3,s3,c3) == 1
      return 3
  0

-> fftiw3_vector(st,positive,negative,orientation,d1,s1,c1,d2,s2,c2,d3,s3,c3,values) (i64[] i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64[]) i64
  if orientation < 0 || orientation > 1
    return 0
  n = st[2] ## i64
  if c1 >= 0
    c1 = 1
  else
    c1 = 0 - 1
  if c2 >= 0
    c2 = 1
  else
    c2 = 0 - 1
  if c3 >= 0
    c3 = 1
  else
    c3 = 0 - 1
  st[46] = 0
  outp = 0 ## i64
  outn = 0 ## i64
  line = 0 ## i64
  while line < n
    coordinate = 0 ## i64
    while coordinate < n
      bit = line*n+coordinate ## i64
      if orientation == 0
        bit = coordinate*n+line
      values[coordinate] = fft_coefficient(positive,negative,bit)
      coordinate += 1
    values[d1] += c1 * values[s1]
    coordinate = 0
    while coordinate < n
      if values[coordinate] < 0 - 1 || values[coordinate] > 1
        st[46] = 1
      coordinate += 1
    values[d2] += c2 * values[s2]
    coordinate = 0
    while coordinate < n
      if values[coordinate] < 0 - 1 || values[coordinate] > 1
        st[46] = 1
      coordinate += 1
    values[d3] += c3 * values[s3]
    coordinate = 0
    while coordinate < n
      value = values[coordinate] ## i64
      if value < 0 - 1 || value > 1
        return 0
      bit = line*n+coordinate
      if orientation == 0
        bit = coordinate*n+line
      if value == 1
        outp = outp | (1 << bit)
      if value == 0 - 1
        outn = outn | (1 << bit)
      coordinate += 1
    line += 1
  st[44] = outp
  st[45] = outn
  1

# Return 2 for a final-strict endpoint with an illegal elementary prefix, 1
# when both prefixes were strict, zero for a non-strict final endpoint, and -1
# for malformed input.  Reduction is a caller policy; raw remains useful for
# exact inverse and planted algebra tests.
-> fftiw3_raw(st,physical,d1,s1,c1,d2,s2,c2,d3,s3,c3) (i64[] i64 i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
  if fft_valid(st) == 0 || st[5] < 1 || physical < 0 || physical > 2
    return 0 - 1
  n = st[2] ## i64
  if d1 < 0 || d1 >= n || s1 < 0 || s1 >= n || d1 == s1 || d2 < 0 || d2 >= n || s2 < 0 || s2 >= n || d2 == s2 || d3 < 0 || d3 >= n || s3 < 0 || s3 >= n || d3 == s3
    return 0 - 1
  if c1 >= 0
    c1 = 1
  else
    c1 = 0 - 1
  if c2 >= 0
    c2 = 1
  else
    c2 = 0 - 1
  if c3 >= 0
    c3 = 1
  else
    c3 = 0 - 1
  atomic = 0 ## i64
  ok = 1 ## i64
  values = i64[7]
  side = 0 ## i64
  while side < 2 && ok == 1
    z = fft_index_shear_spec(st,physical,side,d1,s1) ## i64
    factor = st[60] ## i64
    orientation = st[61] ## i64
    to1 = st[62] ## i64
    from1 = st[63] ## i64
    z = fft_index_shear_spec(st,physical,side,d2,s2)
    if st[60] != factor || st[61] != orientation
      return 0 - 1
    to2 = st[62]
    from2 = st[63]
    z = fft_index_shear_spec(st,physical,side,d3,s3)
    if st[60] != factor || st[61] != orientation
      return 0 - 1
    to3 = st[62]
    from3 = st[63]
    side_c1 = c1 ## i64
    side_c2 = c2 ## i64
    side_c3 = c3 ## i64
    if side == 1
      side_c1 = 0 - c1
      side_c2 = 0 - c2
      side_c3 = 0 - c3
    slot = 0 ## i64
    while slot < st[5] && ok == 1
      base = 32 + 2*factor ## i64
      ok = fftiw3_vector(st,st[st[base]+slot],st[st[base+1]+slot],orientation,to1,from1,side_c1,to2,from2,side_c2,to3,from3,side_c3,values)
      if ok == 1 && (st[44] | st[45]) == 0
        ok = 0
      if st[46] != 0
        atomic = 1
      slot += 1
    side += 1
  if ok == 0
    return 0

  side = 0
  while side < 2
    z = fft_index_shear_spec(st,physical,side,d1,s1)
    factor = st[60]
    orientation = st[61]
    to1 = st[62]
    from1 = st[63]
    z = fft_index_shear_spec(st,physical,side,d2,s2)
    to2 = st[62]
    from2 = st[63]
    z = fft_index_shear_spec(st,physical,side,d3,s3)
    to3 = st[62]
    from3 = st[63]
    side_c1 = c1
    side_c2 = c2
    side_c3 = c3
    if side == 1
      side_c1 = 0 - c1
      side_c2 = 0 - c2
      side_c3 = 0 - c3
    slot = 0
    while slot < st[5]
      base = 32 + 2*factor
      z = fftiw3_vector(st,st[st[base]+slot],st[st[base+1]+slot],orientation,to1,from1,side_c1,to2,from2,side_c2,to3,from3,side_c3,values)
      st[st[base]+slot] = st[44]
      st[st[base+1]+slot] = st[45]
      slot += 1
    side += 1
  slot = 0
  while slot < st[5]
    z = fft_canonicalize_slot(st,slot)
    slot += 1
  st[20] = fft_current_density(st)
  if atomic != 0
    return 2
  1

-> fftiw3_inverse_raw(st,physical,d1,s1,c1,d2,s2,c2,d3,s3,c3) (i64[] i64 i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
  fftiw3_raw(st,physical,d3,s3,0-c3,d2,s2,0-c2,d1,s1,0-c1)

-> fftiw3_probe(st,physical,d1,s1,c1,d2,s2,c2,d3,s3,c3,meta) (i64[] i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64[]) i64
  i = 0 ## i64
  while i < 6
    meta[i] = 0
    i += 1
  old_density = st[20] ## i64
  old_fingerprint = fft_current_fingerprint(st) ## i64
  result = fftiw3_raw(st,physical,d1,s1,c1,d2,s2,c2,d3,s3,c3) ## i64
  meta[0] = result
  if result <= 0
    return result
  meta[2] = st[20] - old_density
  if fft_current_fingerprint(st) != old_fingerprint
    meta[3] = 1
  inverse = fftiw3_inverse_raw(st,physical,d1,s1,c1,d2,s2,c2,d3,s3,c3) ## i64
  meta[1] = inverse
  if inverse == 2
    meta[5] = 1
  if inverse <= 0 || st[20] != old_density || fft_current_fingerprint(st) != old_fingerprint
    meta[4] = 1
    return 0 - 1
  result
