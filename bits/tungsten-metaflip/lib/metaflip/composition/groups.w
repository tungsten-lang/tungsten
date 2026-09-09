# Same-axis groups of up to six terms, with a complete bucket DP. This is
# optimal only for the supplied leaf costs and this disjoint bucket family.
use pairs

-> ffbg_plan(parent, words, cap, rank, axis, costs, cost_words, order, order_words, sizes, size_words, scratch, scratch_words) (i64[] i64 i64 i64 i64 i64[] i64 i64[] i64 i64[] i64 i64[] i64) i64
  if cap < 1 || cap > 4096 || rank < 1 || rank > cap || words < 3*cap || axis < 0 || axis > 2 || cost_words < 7 || order_words < rank || size_words < rank || scratch_words < 4*(cap+1)
    return 0-1
  choice = cap+1 ## i64
  marked = 2*(cap+1) ## i64
  bucket = 3*(cap+1) ## i64
  k = 1 ## i64
  while k <= 6
    if costs[k] < 1 || costs[k] > 16384
      return 0-1
    k += 1
  scratch[0] = 0
  n = 1 ## i64
  while n <= rank
    scratch[n] = 9223372036854775807
    k = 1
    while k <= 6 && k <= n
      price = scratch[n-k]+costs[k] ## i64
      # Equal prices choose the larger exact leaf, retaining its potentially
      # different mapped representation instead of forcing a pair partition.
      if price <= scratch[n]
        scratch[n] = price
        scratch[choice+n] = k
      k += 1
    n += 1
  i = 0 ## i64
  while i < rank
    scratch[marked+i] = 0
    sizes[i] = 0
    i += 1
  output = 0 ## i64
  total = 0 ## i64
  i = 0
  while i < rank
    if scratch[marked+i] == 0
      count = 0 ## i64
      j = i ## i64
      while j < rank
        if parent[axis*cap+j] == parent[axis*cap+i]
          scratch[marked+j] = 1
          scratch[bucket+count] = j
          count += 1
        j += 1
      total += scratch[count]
      while count > 0
        k = scratch[choice+count]
        sizes[output] = k
        j = count-k
        while j < count
          order[output] = scratch[bucket+j]
          output += 1
          j += 1
        count -= k
    i += 1
  if output != rank
    return 0-1
  total

-> ffbg_large(sizes, rank) (i64[] i64) i64
  pos = 0 ## i64
  while pos < rank
    k = sizes[pos] ## i64
    if k > 2
      return 1
    if k < 1
      return 0
    pos += k
  0

# Leaf bank: six factor-major slabs for <k,scale,scale>, k=1..6. Parent
# members are arbitrary linear factor images, not necessarily independent.
-> ffbg_compose(parent, parent_words, cap, rank, n, m, p, axis, scale, leaves, leaf_words, leafcap, costs, cost_words, order, order_words, sizes, size_words, scratch, scratch_words, out, out_words) (i64[] i64 i64 i64 i64 i64 i64 i64 i64 i64[] i64 i64 i64[] i64 i64[] i64 i64[] i64 i64[] i64 i64[] i64) i64
  if n < 1 || m < 1 || p < 1 || n > 63 || m > 63 || p > 63 || n*m > 63 || m*p > 63 || n*p > 63 || scale < 2 || scale > 4 || leafcap < 1 || leafcap > 4096 || leaf_words < 18*leafcap
    return 0-1
  predicted = ffbg_plan(parent, parent_words, cap, rank, axis, costs, cost_words, order, order_words, sizes, size_words, scratch, scratch_words) ## i64
  if predicted < 1 || predicted > 16384
    return 0-1
  a = ffbd_scale(axis, 0, scale) ## i64
  b = ffbd_scale(axis, 1, scale) ## i64
  c = ffbd_scale(axis, 2, scale) ## i64
  stride = ffpk_stride(n*a, m*b, p*c) ## i64
  if stride == 0 || out_words < 3*stride*predicted
    return 0-1
  i = 0 ## i64
  while i < rank
    factor = 0 ## i64
    while factor < 3
      width = ffpk_width(n, m, p, factor) ## i64
      value = parent[factor*cap+i] ## i64
      if value <= 0 || (width < 63 && (value >> width) != 0)
        return 0-1
      factor += 1
    i += 1
  k = 1 ## i64
  while k <= 6
    if costs[k] > leafcap
      return 0-1
    i = 0
    while i < costs[k]
      factor = 0 ## i64
      while factor < 3
        value = leaves[(k-1)*3*leafcap+factor*leafcap+i] ## i64
        if value <= 0 || (value >> ffpk_width(k, scale, scale, factor)) != 0
          return 0-1
        factor += 1
      i += 1
    k += 1
  i = 0
  while i < 3*stride*predicted
    out[i] = 0
    i += 1
  start = 0 ## i64
  output = 0 ## i64
  while start < rank
    k = sizes[start]
    l = 0 ## i64
    while l < costs[k]
      factor = 0 ## i64
      while factor < 3
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
            transpose = 1
          if factor == 1
            old_factor = 2
          if factor == 2
            old_factor = 1
        mask = leaves[(k-1)*3*leafcap+old_factor*leafcap+l] ## i64
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
        while mask > 0
          bit = ffpk_ctz(mask & 4294967295) ## i64
          if (mask & 4294967295) == 0
            bit = 32+ffpk_ctz(mask >> 32)
          lr = bit / scale ## i64
          lc = bit%scale ## i64
          if transpose != 0
            swap = lr ## i64
            lr = lc
            lc = swap
          member = lr / row_scale+lc / col_scale ## i64
          if member < 0 || member >= k
            return 0-1
          outer = parent[factor*cap+order[start+member]] ## i64
          while outer > 0
            obit = ffpk_ctz(outer & 4294967295) ## i64
            if (outer & 4294967295) == 0
              obit = 32+ffpk_ctz(outer >> 32)
            mapped = ((obit / parentcols)*row_scale+lr%row_scale)*(parentcols*col_scale)+(obit%parentcols)*col_scale+lc%col_scale ## i64
            offset = (3*output+factor)*stride+mapped/32 ## i64
            out[offset] = out[offset] ^ (1 << (mapped%32))
            outer = outer & (outer-1)
          mask = mask & (mask-1)
        factor += 1
      output += 1
      l += 1
    start += k
  ffpk_canonicalize(out, out_words, output, stride)
