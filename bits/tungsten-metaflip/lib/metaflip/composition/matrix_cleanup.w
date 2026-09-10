# Bounded shared-factor matrix reduction for term-major 32-bit-limb tensors.
# Algebra only: callers must separately verify every admitted full tensor.
# A budget stop keeps complete reductions and copies unfinished groups intact.
use packed

-> ffwm_slots(capacity) (i64) i64
  slots = 16 ## i64
  while slots < 2*capacity
    slots *= 2
  slots

-> ffwm_scratch_words(capacity, stride) (i64 i64) i64
  if capacity < 1 || capacity > 16384 || stride < 1 || stride > 32
    return 0
  3*capacity*stride + 3*capacity + ffwm_slots(capacity) + 160*stride*stride + 66*stride

# stats: charged algebra work, limit (0=unlimited), exhausted, full axes,
# reduced groups, terms saved. Copying/sorting/validation have separate fixed
# rank/width bounds; this count is not CPU instructions or elapsed time.
-> ffwm_charge(stats, amount) (i64[] i64) i64
  if stats[1] > 0 && amount > stats[1]-stats[0]
    stats[2] = 1
    return 0
  stats[0] += amount
  1

-> ffwm_equal(data, left, right, stride) (i64[] i64 i64 i64) i64
  k = 0 ## i64
  while k < stride
    if data[left+k] != data[right+k]
      return 0
    k += 1
  1

-> ffwm_high(data, offset, stride) (i64[] i64 i64) i64
  limb = stride-1 ## i64
  while limb >= 0
    v = data[offset+limb] ## i64
    if v != 0
      bit = 0 ## i64
      while v > 1
        v = v >> 1
        bit += 1
      return 32*limb+bit
    limb -= 1
  0-1

# Exact column-basis factorization. Scratch writes cannot affect source or
# previously finished groups. -2 means budget stop, not a rank certificate.
-> ffwm_factor(data, scratch, stride, first, links, left, right, base, count, stats) (i64[] i64[] i64 i64 i64 i64 i64 i64 i64 i64[]) i64
  width = 32*stride ## i64
  slab = width*stride ## i64
  columns = base ## i64
  rows = base+slab ## i64
  combinations = base+2*slab ## i64
  left_basis = base+3*slab ## i64
  right_basis = base+4*slab ## i64
  remainder = base+5*slab ## i64
  coefficients = remainder+stride ## i64
  column_used = coefficients+stride ## i64
  row_used = column_used+width ## i64
  if ffwm_charge(stats, 2*width) != 1
    return 0-2
  k = 0 ## i64
  while k < width
    scratch[column_used+k] = 0
    scratch[row_used+k] = 0
    k += 1
  i = first ## i64
  while i >= 0
    limb = 0 ## i64
    while limb < stride
      if ffwm_charge(stats, 1) != 1
        return 0-2
      bits = data[(3*i+right)*stride+limb] ## i64
      while bits != 0
        j = 32*limb+ffpk_ctz(bits) ## i64
        if scratch[column_used+j] == 0
          if ffwm_charge(stats, stride) != 1
            return 0-2
          k = 0
          while k < stride
            scratch[columns+j*stride+k] = 0
            k += 1
          scratch[column_used+j] = 1
        if ffwm_charge(stats, stride) != 1
          return 0-2
        k = 0
        while k < stride
          scratch[columns+j*stride+k] = scratch[columns+j*stride+k] ^ data[(3*i+left)*stride+k]
          k += 1
        bits = bits & (bits-1)
      limb += 1
    i = scratch[links+i]
  basis_count = 0 ## i64
  j = 0 ## i64
  while j < width
    if ffwm_charge(stats, 1) != 1
      return 0-2
    while j < width && scratch[column_used+j] == 0
      j += 1
    if j >= width
      break
    if ffwm_charge(stats, 2*stride) != 1
      return 0-2
    k = 0
    while k < stride
      scratch[remainder+k] = scratch[columns+j*stride+k]
      scratch[coefficients+k] = 0
      k += 1
    pivot = ffwm_high(scratch, remainder, stride) ## i64
    while pivot >= 0
      if ffwm_charge(stats, 3*stride) != 1
        return 0-2
      if scratch[row_used+pivot] == 0
        scratch[row_used+pivot] = 1
        k = 0
        while k < stride
          scratch[rows+pivot*stride+k] = scratch[remainder+k]
          scratch[combinations+pivot*stride+k] = scratch[coefficients+k]
          scratch[left_basis+basis_count*stride+k] = scratch[columns+j*stride+k]
          scratch[right_basis+basis_count*stride+k] = 0
          scratch[coefficients+k] = 0
          k += 1
        bit = 1 << (basis_count%32) ## i64
        scratch[combinations+pivot*stride+basis_count/32] = scratch[combinations+pivot*stride+basis_count/32] ^ bit
        scratch[coefficients+basis_count/32] = bit
        basis_count += 1
        # Matrix rank cannot exceed the number of summands. Once equality
        # is witnessed no remaining columns can make a strict reduction.
        if basis_count == count
          return count
        pivot = 0-1
      else
        k = 0
        while k < stride
          scratch[remainder+k] = scratch[remainder+k] ^ scratch[rows+pivot*stride+k]
          scratch[coefficients+k] = scratch[coefficients+k] ^ scratch[combinations+pivot*stride+k]
          k += 1
        pivot = ffwm_high(scratch, remainder, stride)
    limb = 0 ## i64
    while limb < stride
      bits = scratch[coefficients+limb] ## i64
      while bits != 0
        if ffwm_charge(stats, 1) != 1
          return 0-2
        b = 32*limb+ffpk_ctz(bits) ## i64
        scratch[right_basis+b*stride+j/32] = scratch[right_basis+b*stride+j/32] | (1 << (j%32))
        bits = bits & (bits-1)
      limb += 1
    j += 1
  basis_count

-> ffwm_axis(data, scratch, capacity, rank, stride, axis, stats) (i64[] i64[] i64 i64 i64 i64 i64[]) i64
  heads = 3*capacity*stride ## i64
  tails = heads+capacity ## i64
  links = tails+capacity ## i64
  buckets = links+capacity ## i64
  slots = ffwm_slots(capacity) ## i64
  base = buckets+slots ## i64
  left = 0 ## i64
  right = 2 ## i64
  if axis == 0
    left = 1
  if axis == 2
    right = 1
  if ffwm_charge(stats, slots) != 1
    return rank
  k = 0 ## i64
  while k < slots
    scratch[buckets+k] = 0
    k += 1
  groups = 0 ## i64
  i = 0 ## i64
  while i < rank
    if ffwm_charge(stats, stride) != 1
      return rank
    hash = 2166136261 ## i64
    k = 0
    while k < stride
      hash = ((hash ^ data[(3*i+axis)*stride+k])*16777619) & 4294967295
      k += 1
    # Fold high coordinate bits into the bucket bits. A polynomial hash
    # without this avalanche clusters sparse coordinate vectors badly.
    hash = ((hash ^ (hash >> 16))*1000003) & 4294967295
    hash = hash ^ (hash >> 16)
    bucket = hash & (slots-1) ## i64
    found = 0 ## i64
    while found == 0
      if ffwm_charge(stats, stride+1) != 1
        return rank
      group = scratch[buckets+bucket]-1 ## i64
      if group < 0
        scratch[buckets+bucket] = groups+1
        scratch[heads+groups] = i
        scratch[tails+groups] = i
        groups += 1
        found = 1
      elsif ffwm_equal(data, (3*i+axis)*stride, (3*scratch[heads+group]+axis)*stride, stride) == 1
        scratch[links+scratch[tails+group]] = i
        scratch[tails+group] = i
        found = 1
      else
        bucket = (bucket+1) & (slots-1)
    scratch[links+i] = 0-1
    i += 1
  kept = 0 ## i64
  group = 0 ## i64
  while group < groups
    first = scratch[heads+group] ## i64
    second = scratch[links+first] ## i64
    factor = second >= 0 && stats[2] == 0 ## bool
    if factor && scratch[links+second] < 0 && ffwm_equal(data, (3*first+left)*stride, (3*second+left)*stride, stride) == 0 && ffwm_equal(data, (3*first+right)*stride, (3*second+right)*stride, stride) == 0
      factor = false
    replacement = 0-1 ## i64
    count = 0 ## i64
    if factor
      i = first
      while i >= 0
        count += 1
        i = scratch[links+i]
      reduced = ffwm_factor(data, scratch, stride, first, links, left, right, base, count, stats) ## i64
      if reduced >= 0 && reduced < count
        replacement = reduced
    if replacement >= 0
      b = 0 ## i64
      while b < replacement
        k = 0
        while k < stride
          scratch[(3*kept+axis)*stride+k] = data[(3*first+axis)*stride+k]
          scratch[(3*kept+left)*stride+k] = scratch[base+96*stride*stride+b*stride+k]
          scratch[(3*kept+right)*stride+k] = scratch[base+128*stride*stride+b*stride+k]
          k += 1
        kept += 1
        b += 1
      stats[4] += 1
      stats[5] += count-replacement
    else
      i = first
      while i >= 0
        k = 0
        while k < 3*stride
          scratch[3*kept*stride+k] = data[3*i*stride+k]
          k += 1
        kept += 1
        i = scratch[links+i]
    group += 1
  i = 0
  while i < 3*kept*stride
    data[i] = scratch[i]
    i += 1
  if stats[2] == 0
    stats[3] += 1
  kept

-> ffwm_reduce(data, words, rank, n, m, p, scratch, scratch_words, budget, stats, stats_words) (i64[] i64 i64 i64 i64 i64 i64[] i64 i64 i64[] i64) i64
  stride = ffpk_stride(n, m, p) ## i64
  needed = ffwm_scratch_words(rank, stride) ## i64
  if stats_words < 6 || needed == 0 || scratch_words < needed || budget < 0 || budget > 1000000000 || ffpk_valid(data, words, rank, n, m, p) != 1
    return 0-1
  i = 0 ## i64
  while i < 6
    stats[i] = 0
    i += 1
  stats[1] = budget
  capacity = rank ## i64
  before = rank+1 ## i64
  while rank > 0 && rank < before && stats[2] == 0
    before = rank
    axis = 0 ## i64
    while axis < 3 && rank > 0 && stats[2] == 0
      rank = ffwm_axis(data, scratch, capacity, rank, stride, axis, stats)
      axis += 1
  rank = ffpk_canonicalize(data, words, rank, stride)
  rank
