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
