use packed

# Pair-only first strategy: exact partition, not an optimal packing claim.
# mates[i]=i denotes a singleton. Matched indices are symmetric.
-> ffbd_pairs(parent, words, capacity, rank, axis, mates, mates_words) (i64[] i64 i64 i64 i64 i64[] i64) i64
  if capacity < 1 || capacity > 4096 || capacity < rank || rank < 1 || axis < 0 || axis > 2 || words < 3*capacity || mates_words < rank
    return 0-1
  i = 0 ## i64
  while i < rank
    mates[i] = i
    i += 1
  pairs = 0 ## i64
  i = 0
  while i < rank
    if mates[i] == i
      j = i+1 ## i64
      while j < rank
        if mates[j] == j && parent[axis*capacity+i] == parent[axis*capacity+j]
          mates[i] = j
          mates[j] = i
          pairs += 1
          break
        j += 1
    i += 1
  pairs

-> ffbd_scale(axis, dimension, scale) (i64 i64 i64) i64
  expanded = 2 ## i64
  if axis == 1
    expanded = 0
  if axis == 2
    expanded = 1
  if dimension == expanded
    return 1
  scale

# Parent and pair leaf are one-word exact schemes (checked by the caller).
# The leaf is canonical <2,k,k>; it is oriented to the selected shared axis.
# Singles use the exact naive <k,k,1> permutation, rank k^2.
-> ffbd_compose(parent, parent_words, capacity, rank, n, m, p, axis, scale, leaf, leaf_words, leafcap, leafrank, mates, mates_words, out, out_words) (i64[] i64 i64 i64 i64 i64 i64 i64 i64 i64[] i64 i64 i64 i64[] i64 i64[] i64) i64
  if n < 1 || m < 1 || p < 1 || n > 63 || m > 63 || p > 63 || n*m > 63 || m*p > 63 || n*p > 63 || scale < 2 || scale > 4 || leafcap < 1 || leafcap > 4096 || leafrank < 1 || leafrank > leafcap || leaf_words < 3*leafcap
    return 0-1
  pairs = ffbd_pairs(parent, parent_words, capacity, rank, axis, mates, mates_words) ## i64
  if pairs < 0
    return 0-1
  # Reject out-of-width factors before deriving any packed output offset.
  i = 0 ## i64
  while i < rank
    f = 0 ## i64
    while f < 3
      width = ffpk_width(n, m, p, f) ## i64
      value = parent[f*capacity+i] ## i64
      if value <= 0 || (width < 63 && (value >> width) != 0)
        return 0-1
      f += 1
    i += 1
  i = 0
  while i < leafrank
    f = 0 ## i64
    while f < 3
      width = ffpk_width(2, scale, scale, f) ## i64
      value = leaf[f*leafcap+i] ## i64
      if value <= 0 || (value >> width) != 0
        return 0-1
      f += 1
    i += 1
  a = ffbd_scale(axis, 0, scale) ## i64
  b = ffbd_scale(axis, 1, scale) ## i64
  c = ffbd_scale(axis, 2, scale) ## i64
  stride = ffpk_stride(n*a, m*b, p*c) ## i64
  predicted = (rank-2*pairs)*scale*scale+pairs*leafrank ## i64
  if stride == 0 || predicted > 16384 || out_words < 3*stride*predicted
    return 0-1
  pos = 0 ## i64
  while pos < 3*stride*predicted
    out[pos] = 0
    pos += 1
  output = 0 ## i64
  term = 0 ## i64
  while term < rank
    mate = mates[term] ## i64
    if mate >= term
      count = scale*scale ## i64
      if mate != term
        count = leafrank
      l = 0 ## i64
      while l < count
        factor = 0 ## i64
        while factor < 3
          # Canonical coordinates are (expanded=2, k, k). Permutations:
          # axis0 => (k,k,2); axis1 => (2,k,k); axis2 => (k,2,k).
          old_factor = factor ## i64
          transpose = 0 ## i64
          if axis == 0
            if factor == 0
              old_factor = 1
            if factor == 1
              old_factor = 2
              transpose = 1
            if factor == 2
              old_factor = 0
              transpose = 1
          if axis == 2
            if factor == 0
              old_factor = 0
              transpose = 1
            if factor == 1
              old_factor = 2
            if factor == 2
              old_factor = 1
          leafmask = 0 ## i64
          leafcols = scale ## i64
          if mate != term
            leafmask = leaf[old_factor*leafcap+l]
          else
            # <1,k,k> naive term (0, l/k, l%k).
            leafmask = 1 << (l / scale)
            if old_factor == 1
              leafmask = 1 << l
            if old_factor == 2
              leafmask = 1 << (l%scale)
          row_scale = a ## i64
          col_scale = b ## i64
          parentcols = m ## i64
          if factor == 1
            row_scale = b
            col_scale = c
            parentcols = p
          if factor == 2
            col_scale = c
            parentcols = p
          while leafmask > 0
            bit = 0 ## i64
            # Leaf words can exceed 32 bits, but remain positive i64.
            low = leafmask & 4294967295 ## i64
            if low != 0
              bit = ffpk_ctz(low)
            else
              bit = 32+ffpk_ctz(leafmask >> 32)
            lr = bit / leafcols ## i64
            lc = bit%leafcols ## i64
            if transpose != 0
              swap = lr ## i64
              lr = lc
              lc = swap
            member = term ## i64
            if lr / row_scale != 0 || lc / col_scale != 0
              member = mate
            outer = parent[factor*capacity+member] ## i64
            while outer > 0
              obit = 0 ## i64
              olo = outer & 4294967295 ## i64
              if olo != 0
                obit = ffpk_ctz(olo)
              else
                obit = 32+ffpk_ctz(outer >> 32)
              mapped = ((obit / parentcols)*row_scale+lr%row_scale)*(parentcols*col_scale)+(obit%parentcols)*col_scale+lc%col_scale ## i64
              offset = (3*output+factor)*stride+mapped/32 ## i64
              out[offset] = out[offset] ^ (1 << (mapped%32))
              outer = outer & (outer-1)
            leafmask = leafmask & (leafmask-1)
          factor += 1
        output += 1
        l += 1
    term += 1
  ffpk_canonicalize(out, out_words, output, stride)
