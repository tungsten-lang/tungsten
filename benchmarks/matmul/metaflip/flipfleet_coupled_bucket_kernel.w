# Exact coupled multi-codeword descent in one factor-bucket kernel.
#
# Group a tensor subtotal by distinct factors f_i on one axis and write its
# complementary matrices as M_i.  If z_j is any codeword in ker[f_1 ... f_q],
# then for arbitrary complementary matrices D_j,
#
#   M'_i = M_i + sum_j z_j[i] D_j
#
# preserves the tensor.  This operator applies two overlapping codewords with
# independent rank-one D values and minimally refactors every changed bucket.
# Matrix rank is nonseparable, so the pair can drop rank even when either
# correction by itself is rank-neutral.  The one-D dependency medians do not
# search this coupled objective.

use flipfleet_gf2_dependency_median

-> ffcbk_codeword_valid(factors, bucket_count, codeword) (i64[] i64 i64[]) i64
  if factors.size() < bucket_count || codeword.size() < bucket_count
    return 0
  sum = 0 ## i64
  weight = 0 ## i64
  i = 0 ## i64
  while i < bucket_count
    if codeword[i] != 0
      sum = sum ^ factors[i]
      weight += 1
    i += 1
  if sum == 0 && weight >= 2
    return 1
  0

-> ffcbk_factor_bucket_pair(us, vs, ws, rank, axis, term_bucket, bucket, z1, z2, d1_left, d1_right, d2_left, d2_right, out_left, out_right) (i64[] i64[] i64[] i64 i64 i64[] i64 i64 i64 i64 i64 i64 i64 i64[] i64[]) i64
  lefts = i64[rank + 2]
  rights = i64[rank + 2]
  count = 0 ## i64
  position = 0 ## i64
  while position < rank
    if term_bucket[position] == bucket
      lefts[count] = ffpc5_axis_left(us,vs,ws,position,axis)
      rights[count] = ffpc5_axis_right(us,vs,ws,position,axis)
      count += 1
    position += 1
  if z1 != 0
    if d1_left == 0 || d1_right == 0
      return 0 - 1
    lefts[count] = d1_left
    rights[count] = d1_right
    count += 1
  if z2 != 0
    if d2_left == 0 || d2_right == 0
      return 0 - 1
    lefts[count] = d2_left
    rights[count] = d2_right
    count += 1
  ffsm_rank_factor_matrix(lefts,rights,count,out_left,out_right)

# Materialize a complete minimally factored subtotal after applying zero, one,
# Pack [factors,codeword1,codeword2,term_bucket] for the native move surface.
-> ffcbk_pack_layout(factors, term_bucket, rank, bucket_count, codeword1, codeword2, layout) (i64[] i64[] i64 i64 i64[] i64[] i64[]) i64
  required = 3 * bucket_count + rank ## i64
  if rank < 1 || bucket_count < 2 || factors.size() < bucket_count || term_bucket.size() < rank || codeword1.size() < bucket_count || codeword2.size() < bucket_count || layout.size() < required
    return 0
  i = 0 ## i64
  while i < bucket_count
    layout[i] = factors[i]
    layout[bucket_count + i] = codeword1[i]
    layout[2 * bucket_count + i] = codeword2[i]
    i += 1
  i = 0
  while i < rank
    layout[3 * bucket_count + i] = term_bucket[i]
    i += 1
  required

# or both codeword corrections.  Config is
# [d1_left,d1_right,d2_left,d2_right,enable1,enable2,bucket_count].
-> ffcbk_materialize_pair(us, vs, ws, rank, axis, layout, config, out_u, out_v, out_w, meta) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64[] i64[] i64[]) i64
  if rank < 1 || axis < 0 || axis > 2 || config.size() < 7 || meta.size() < 8
    return 0 - 1
  d1_left = config[0] ## i64
  d1_right = config[1] ## i64
  d2_left = config[2] ## i64
  d2_right = config[3] ## i64
  enable1 = config[4] ## i64
  enable2 = config[5] ## i64
  bucket_count = config[6] ## i64
  if bucket_count < 2 || layout.size() < 3 * bucket_count + rank
    return 0 - 1
  factors = i64[bucket_count]
  codeword1 = i64[bucket_count]
  codeword2 = i64[bucket_count]
  term_bucket = i64[rank]
  i = 0 ## i64
  while i < bucket_count
    factors[i] = layout[i]
    codeword1[i] = layout[bucket_count + i]
    codeword2[i] = layout[2 * bucket_count + i]
    i += 1
  i = 0
  while i < rank
    term_bucket[i] = layout[3 * bucket_count + i]
    i += 1
  if enable1 < 0 || enable1 > 1 || enable2 < 0 || enable2 > 1
    return 0 - 1
  i = 0
  while i < 8
    meta[i] = 0
    i += 1
  if enable1 == 1 && ffcbk_codeword_valid(factors,bucket_count,codeword1) == 0
    return 0 - 1
  if enable2 == 1 && ffcbk_codeword_valid(factors,bucket_count,codeword2) == 0
    return 0 - 1
  capacity = out_u.size() ## i64
  if out_v.size() < capacity
    capacity = out_v.size()
  if out_w.size() < capacity
    capacity = out_w.size()
  made = 0 ## i64
  base_cost = 0 ## i64
  bucket = 0 ## i64
  while bucket < bucket_count
    base_left = i64[63]
    base_right = i64[63]
    base_rank = ffcbk_factor_bucket_pair(us,vs,ws,rank,axis,term_bucket,bucket,0,0,d1_left,d1_right,d2_left,d2_right,base_left,base_right) ## i64
    if base_rank < 0
      return 0 - 1
    base_cost += base_rank
    shifted_left = i64[63]
    shifted_right = i64[63]
    use1 = 0 ## i64
    use2 = 0 ## i64
    if enable1 == 1
      use1 = codeword1[bucket]
    if enable2 == 1
      use2 = codeword2[bucket]
    shifted_rank = ffcbk_factor_bucket_pair(us,vs,ws,rank,axis,term_bucket,bucket,use1,use2,d1_left,d1_right,d2_left,d2_right,shifted_left,shifted_right) ## i64
    if shifted_rank < 0 || made + shifted_rank > capacity
      return 0 - 1
    term = 0 ## i64
    while term < shifted_rank
      if ffmp_emit_term(axis,factors[bucket],shifted_left[term],shifted_right[term],out_u,out_v,out_w,made) == 0
        return 0 - 1
      made += 1
      term += 1
    bucket += 1
  meta[0] = base_cost
  meta[1] = made
  meta[2] = made - base_cost
  meta[3] = enable1
  meta[4] = enable2
  meta[5] = ffgr_replacement_exact(us,vs,ws,rank,out_u,out_v,out_w,made)
  meta[6] = bucket_count
  meta[7] = rank
  if meta[5] != 1
    return 0 - 1
  made

# Factor a raw 2x2 row-major matrix into physical rank-one terms.  This tiny
# helper is only for exact planted controls; production inputs are already
# represented as complementary factor pairs.
-> ffcbk_factor_raw2(matrix, out_left, out_right) (i64 i64[] i64[]) i64
  if matrix < 0 || matrix > 15 || out_left.size() < 2 || out_right.size() < 2
    return 0 - 1
  rows_left = i64[2]
  rows_right = i64[2]
  count = 0 ## i64
  row = 0 ## i64
  while row < 2
    bits = (matrix >> (row * 2)) & 3 ## i64
    if bits != 0
      rows_left[count] = 1 << row
      rows_right[count] = bits
      count += 1
    row += 1
  ffsm_rank_factor_matrix(rows_left,rows_right,count,out_left,out_right)

-> ffcbk_emit_raw2_bucket(axis, factor, matrix, out_u, out_v, out_w, made) (i64 i64 i64 i64[] i64[] i64[] i64) i64
  lefts = i64[2]
  rights = i64[2]
  matrix_rank = ffcbk_factor_raw2(matrix,lefts,rights) ## i64
  if matrix_rank < 0 || made + matrix_rank > out_u.size() || made + matrix_rank > out_v.size() || made + matrix_rank > out_w.size()
    return 0 - 1
  i = 0 ## i64
  while i < matrix_rank
    if ffmp_emit_term(axis,factor,lefts[i],rights[i],out_u,out_v,out_w,made) == 0
      return 0 - 1
    made += 1
    i += 1
  made

-> ffcbk_build_raw2_subtotal(factors, matrices, bucket_count, axis, out_u, out_v, out_w) (i64[] i64[] i64 i64 i64[] i64[] i64[]) i64
  if factors.size() < bucket_count || matrices.size() < bucket_count
    return 0 - 1
  made = 0 ## i64
  i = 0 ## i64
  while i < bucket_count
    made = ffcbk_emit_raw2_bucket(axis,factors[i],matrices[i],out_u,out_v,out_w,made)
    if made < 0
      return 0 - 1
    i += 1
  made
