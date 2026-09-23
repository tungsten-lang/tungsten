# One-coordinate restrictions of packed, multiword tensors. Separate source
# and destination slabs are required. This is algebra, not an admission gate.
use packed

-> ffwp_project(source, source_words, rank, n, m, p, axis, removed, output, output_words) (i64[] i64 i64 i64 i64 i64 i64 i64 i64[] i64) i64
  if axis < 0 || axis > 2 || ffpk_valid(source, source_words, rank, n, m, p) != 1
    return 0-1
  nn = n ## i64
  mm = m ## i64
  pp = p ## i64
  size = n ## i64
  if axis == 0
    nn -= 1
  elsif axis == 1
    size = m
    mm -= 1
  else
    size = p
    pp -= 1
  stride = ffpk_stride(n, m, p) ## i64
  target_stride = ffpk_stride(nn, mm, pp) ## i64
  if size < 2 || removed < 0 || removed >= size || target_stride == 0 || output_words < 3*rank*target_stride
    return 0-1
  k = 0 ## i64
  while k < 3*rank*target_stride
    output[k] = 0
    k += 1
  t = 0 ## i64
  while t < rank
    factor = 0 ## i64
    while factor < 3
      row_axis = 0 ## i64
      column_axis = 1 ## i64
      columns = m ## i64
      target_columns = mm ## i64
      if factor > 0
        column_axis = 2
        columns = p
        target_columns = pp
      if factor == 1
        row_axis = 1
      limb = 0 ## i64
      while limb < stride
        bits = source[(3*t+factor)*stride+limb] ## i64
        while bits != 0
          bit = 32*limb+ffpk_ctz(bits) ## i64
          row = bit / columns ## i64
          column = bit%columns ## i64
          if (axis != row_axis || row != removed) && (axis != column_axis || column != removed)
            if axis == row_axis && row > removed
              row -= 1
            if axis == column_axis && column > removed
              column -= 1
            position = row*target_columns+column ## i64
            offset = (3*t+factor)*target_stride+position/32 ## i64
            output[offset] = output[offset] | (1 << (position%32))
          bits = bits & (bits-1)
        limb += 1
      factor += 1
    t += 1
  ffpk_canonicalize(output, output_words, rank, target_stride)

# Apply a basis shear and delete its changed coordinate. The first incident
# factor's changed row/column disappears; only the opposite incident factor's
# XORs survive. Source, work and output are distinct slabs. This is algebra;
# the caller still exact-checks every admitted tensor.
-> ffwp_axis_mask_project(source, source_words, rank, n, m, p, axis, removed, mask, work, work_words, output, output_words) (i64[] i64 i64 i64 i64 i64 i64 i64 i64 i64[] i64 i64[] i64) i64
  stride = ffpk_stride(n, m, p) ## i64
  if axis < 0 || axis > 2 || stride == 0 || ffpk_valid(source, source_words, rank, n, m, p) != 1
    return 0-1
  size = n ## i64
  factor = 2 ## i64
  count = p ## i64
  if axis == 1
    size = m
    factor = 1
  if axis == 2
    size = p
    count = n
  if size < 2 || size > 32 || removed < 0 || removed >= size || mask < 0 || mask >= (1 << size) || ((mask >> removed) & 1) != 0 || work_words < 3*rank*stride
    return 0-1
  i = 0 ## i64
  while i < 3*rank*stride
    work[i] = source[i]
    i += 1
  t = 0 ## i64
  while t < rank
    j = 0 ## i64
    while j < count
      from = removed*p+j ## i64
      if axis == 2
        from = j*p+removed
      if ((source[(3*t+factor)*stride+from/32] >> (from%32)) & 1) != 0
        b = 0 ## i64
        while b < size
          if ((mask >> b) & 1) != 0
            to = b*p+j ## i64
            if axis == 2
              to = j*p+b
            at = (3*t+factor)*stride+to/32 ## i64
            work[at] = work[at] ^ (1 << (to%32))
          b += 1
      j += 1
    t += 1
  ffwp_project(work, 3*rank*stride, rank, n, m, p, axis, removed, output, output_words)

-> ffwp_middle_mask_project(source, source_words, rank, n, m, p, removed, mask, work, work_words, output, output_words) (i64[] i64 i64 i64 i64 i64 i64 i64 i64[] i64 i64[] i64) i64
  ffwp_axis_mask_project(source, source_words, rank, n, m, p, 1, removed, mask, work, work_words, output, output_words)
