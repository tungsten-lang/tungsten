# Exact multiword shared-factor pair constructor. Callers must full-check
# the output tensor before archive admission.
use packed

-> pair_factor_equal(data, first, second, stride, axis) (i64[] i64 i64 i64 i64) i64
  limb = 0 ## i64
  while limb < stride
    if data[(3*first+axis)*stride+limb] != data[(3*second+axis)*stride+limb]
      return 0
    limb += 1
  1

-> pair_expand(source, start, stride, columns, leaf, leaf_rows, leaf_columns, out, target, out_stride) (i64[] i64 i64 i64 i64 i64 i64 i64[] i64 i64) i64
  limb = 0 ## i64
  while limb < stride
    word = source[start+limb] ## i64
    while word != 0
      bit = 32*limb+ffpk_ctz(word) ## i64
      row = 0 ## i64
      column = bit ## i64
      while column >= columns
        row += 1
        column -= columns
      part = leaf ## i64
      while part != 0
        small = ffpk_ctz(part) ## i64
        small_row = 0 ## i64
        small_col = small ## i64
        while small_col >= leaf_columns
          small_row += 1
          small_col -= leaf_columns
        out_bit = (row*leaf_rows+small_row)*(columns*leaf_columns)+column*leaf_columns+small_col ## i64
        if out_bit < 0 || out_bit >= 32*out_stride
          return 0
        out[target+out_bit/32] = out[target+out_bit/32] ^ (1 << (out_bit%32))
        part = part & (part-1)
      word = word & (word-1)
    limb += 1
  1

-> pair_leaf() i64[]
  [1,9,13, 5,3,8, 16,4,352, 20,54,32, 3,8,67,
   8,18,50, 9,10,10, 12,2,152, 28,50,160, 10,24,2,
   32,32,388, 34,45,4, 35,13,68, 51,5,64, 60,48,128]

-> pair_match_w(source, rank, stride, pair_first, pair_second, singles) (i64[] i64 i64 i64[] i64[] i64[]) i64
  if rank < 1 || rank > 2000 || stride < 1 || stride > 32 || source.size() < 3*stride*rank || pair_first.size() < rank || pair_second.size() < rank || singles.size() < rank
    return 0-1
  heads = i64[32768]
  pending = i64[32768]
  pairs = 0 ## i64
  t = 0 ## i64
  while t < rank
    hash = 2166136261 ## i64
    limb = 0 ## i64
    while limb < stride
      hash = ((hash ^ source[(3*t+2)*stride+limb])*16777619) & 2147483647
      limb += 1
    slot = hash & 32767 ## i64
    while heads[slot] != 0 && pair_factor_equal(source,heads[slot]-1,t,stride,2) != 1
      slot = (slot+1) & 32767
    if heads[slot] == 0
      heads[slot] = t+1
      pending[slot] = t+1
    elsif pending[slot] == 0
      pending[slot] = t+1
    else
      pair_first[pairs] = pending[slot]-1
      pair_second[pairs] = t
      pairs += 1
      pending[slot] = 0
    t += 1
  single_count = 0 ## i64
  slot = 0 ## i64
  while slot < 32768
    if pending[slot] != 0
      singles[single_count] = pending[slot]-1
      single_count += 1
    slot += 1
  if single_count != rank-2*pairs
    return 0-1
  pairs

# Shared W: 15 terms per matched pair, 9 per singleton. The 15-term leaf
# is the exact 2x3x3 projection of the bundled 2x3x5/r26 GF(2) scheme.
-> pair_compose_w(source, rank, n, m, p, out, meta) (i64[] i64 i64 i64 i64 i64[] i64[]) i64
  stride = ffpk_stride(n,m,p) ## i64
  wide = ffpk_stride(3*n,m,3*p) ## i64
  if stride == 0 || wide == 0 || rank < 1 || rank > 2000 || 3*n > 32 || 3*p > 32 || m > 32 || ffpk_valid(source,source.size(),rank,n,m,p) != 1
    return 0
  pair_first = i64[rank]
  pair_second = i64[rank]
  singles = i64[rank]
  pairs = pair_match_w(source,rank,stride,pair_first,pair_second,singles) ## i64
  if pairs < 0
    return 0
  single_count = rank-2*pairs ## i64
  predicted = 15*pairs+9*single_count ## i64
  if predicted < 1 || predicted > 16384 || out.size() < 3*wide*predicted
    return 0
  leaf = pair_leaf()
  emitted = 0 ## i64
  k = 0 ## i64
  while k < pairs
    first = pair_first[k] ## i64
    second = pair_second[k] ## i64
    j = 0 ## i64
    while j < 15
      a = leaf[3*j] ## i64
      b = leaf[3*j+1] ## i64
      c = leaf[3*j+2] ## i64
      a0 = 0 ## i64
      a1 = 0 ## i64
      bit = 0 ## i64
      while bit < 6
        if (a & (1 << bit)) != 0
          if bit%2 == 0
            a0 = a0 | (1 << (bit/2))
          else
            a1 = a1 | (1 << (bit/2))
        bit += 1
      u = 3*emitted*wide ## i64
      v = u+wide ## i64
      w = v+wide ## i64
      if pair_expand(source,3*first*stride,stride,m,a0,3,1,out,u,wide) != 1
        return 0
      if pair_expand(source,3*second*stride,stride,m,a1,3,1,out,u,wide) != 1
        return 0
      if pair_expand(source,(3*first+1)*stride,stride,p,b & 7,1,3,out,v,wide) != 1
        return 0
      if pair_expand(source,(3*second+1)*stride,stride,p,(b >> 3) & 7,1,3,out,v,wide) != 1
        return 0
      if pair_expand(source,(3*first+2)*stride,stride,p,c,3,3,out,w,wide) != 1
        return 0
      emitted += 1
      j += 1
    k += 1
  k = 0
  while k < single_count
    t = singles[k] ## i64
    i = 0 ## i64
    while i < 3
      j = 0 ## i64
      while j < 3
        u = 3*emitted*wide ## i64
        v = u+wide ## i64
        w = v+wide ## i64
        if pair_expand(source,3*t*stride,stride,m,1 << i,3,1,out,u,wide) != 1 || pair_expand(source,(3*t+1)*stride,stride,p,1 << j,1,3,out,v,wide) != 1 || pair_expand(source,(3*t+2)*stride,stride,p,1 << (3*i+j),3,3,out,w,wide) != 1
          return 0
        emitted += 1
        j += 1
      i += 1
    k += 1
  if emitted != predicted
    return 0
  meta[0] = 3*n
  meta[1] = m
  meta[2] = 3*p
  meta[3] = pairs
  ffpk_canonicalize(out,out.size(),emitted,wide)

-> pair_permute(source, rank, shape, order, out, target_shape) (i64[] i64 i64[] i64[] i64[] i64[]) i64
  source_stride = ffpk_stride(shape[0],shape[1],shape[2]) ## i64
  target_shape[0] = shape[order[0]]
  target_shape[1] = shape[order[1]]
  target_shape[2] = shape[order[2]]
  target_stride = ffpk_stride(target_shape[0],target_shape[1],target_shape[2]) ## i64
  if source_stride == 0 || target_stride == 0 || rank < 1 || out.size() < 3*target_stride*rank || ffpk_valid(source,source.size(),rank,shape[0],shape[1],shape[2]) != 1
    return 0
  i = 0 ## i64
  while i < 3*target_stride*rank
    out[i] = 0
    i += 1
  t = 0 ## i64
  while t < rank
    axis = 0 ## i64
    while axis < 3
      left = 0 ## i64
      right = 2 ## i64
      if axis == 0
        right = 1
      elsif axis == 1
        left = 1
      original_left = order[left] ## i64
      original_right = order[right] ## i64
      lo = original_left ## i64
      hi = original_right ## i64
      if lo > hi
        lo = original_right
        hi = original_left
      original_axis = 2 ## i64
      if lo == 0 && hi == 1
        original_axis = 0
      elsif lo == 1 && hi == 2
        original_axis = 1
      original_columns = shape[hi] ## i64
      target_columns = target_shape[right] ## i64
      limb = 0 ## i64
      while limb < source_stride
        word = source[(3*t+original_axis)*source_stride+limb] ## i64
        while word != 0
          bit = 32*limb+ffpk_ctz(word) ## i64
          row = 0 ## i64
          column = bit ## i64
          while column >= original_columns
            row += 1
            column -= original_columns
          translated = row*target_columns+column ## i64
          if original_left > original_right
            translated = column*target_columns+row
          out[(3*t+axis)*target_stride+translated/32] = out[(3*t+axis)*target_stride+translated/32] | (1 << (translated%32))
          word = word & (word-1)
        limb += 1
      axis += 1
    t += 1
  1

-> pair_compose(source, rank, n, m, p, axis, out, meta) (i64[] i64 i64 i64 i64 i64 i64[] i64[]) i64
  if axis < 0 || axis > 2 || rank < 1 || rank > 2000
    return 0
  if axis == 2
    return pair_compose_w(source,rank,n,m,p,out,meta)
  order = i64[3]
  order[0] = 0
  order[1] = 2
  order[2] = 1
  if axis == 1
    order[0] = 1
    order[1] = 0
    order[2] = 2
  shape = i64[3]
  shape[0] = n
  shape[1] = m
  shape[2] = p
  rotated_shape = i64[3]
  rotated = i64[3*32*2000]
  if pair_permute(source,rank,shape,order,rotated,rotated_shape) != 1
    return 0
  candidate = i64[3*32*16384]
  candidate_meta = i64[4]
  result = pair_compose_w(rotated,rank,rotated_shape[0],rotated_shape[1],rotated_shape[2],candidate,candidate_meta) ## i64
  if result < 1
    return 0
  inverse = i64[3]
  i = 0 ## i64
  while i < 3
    inverse[order[i]] = i
    i += 1
  composed_shape = i64[3]
  composed_shape[0] = candidate_meta[0]
  composed_shape[1] = candidate_meta[1]
  composed_shape[2] = candidate_meta[2]
  if pair_permute(candidate,result,composed_shape,inverse,out,meta) != 1
    return 0
  meta[3] = candidate_meta[3]
  ffpk_canonicalize(out,out.size(),result,ffpk_stride(meta[0],meta[1],meta[2]))

# Cheap exact pair census for bounded queue admission. It uses the same
# greedy pairing order as the constructor, after the same axis permutation.
-> pair_profile(source, rank, n, m, p, axis) (i64[] i64 i64 i64 i64 i64) i64
  if axis < 0 || axis > 2 || rank < 1 || rank > 900 || ffpk_valid(source,source.size(),rank,n,m,p) != 1
    return 0-1
  target_n = n ## i64
  target_m = m ## i64
  target_p = p ## i64
  if axis != 1
    target_n *= 3
  if axis != 2
    target_m *= 3
  if axis != 0
    target_p *= 3
  if target_n > 32 || target_m > 32 || target_p > 32 || ffpk_stride(target_n,target_m,target_p) == 0
    return 0-1
  rotated = source
  rotated_n = n ## i64
  rotated_m = m ## i64
  rotated_p = p ## i64
  if axis != 2
    order = i64[3]
    order[0] = 0
    order[1] = 2
    order[2] = 1
    if axis == 1
      order[0] = 1
      order[1] = 0
      order[2] = 2
    shape = i64[3]
    shape[0] = n
    shape[1] = m
    shape[2] = p
    rotated_shape = i64[3]
    rotated = i64[3*32*900]
    if pair_permute(source,rank,shape,order,rotated,rotated_shape) != 1
      return 0-1
    rotated_n = rotated_shape[0]
    rotated_m = rotated_shape[1]
    rotated_p = rotated_shape[2]
  first = i64[rank]
  second = i64[rank]
  singles = i64[rank]
  pairs = pair_match_w(rotated,rank,ffpk_stride(rotated_n,rotated_m,rotated_p),first,second,singles) ## i64
  if pairs < 4 || 9*rank-3*pairs > 8000
    return 0-1
  pairs
