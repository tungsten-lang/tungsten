# Exact GF(2) shared-factor matrix compression for cold candidate processing.
# Three capacity-sized input arrays are followed by reusable output/group and
# 63-column elimination slabs. No allocation, worker state or randomness here.
# This is algebraic reduction, NOT a tensor verifier. Admission must verify.
use ../rect

-> ffmc_hash_capacity(capacity) (i64) i64
  slots = 16 ## i64
  while slots < capacity * 2
    slots *= 2
  slots

-> ffmc_scratch_words(capacity) (i64) i64
  9 * capacity + ffmc_hash_capacity(capacity) + 315

-> ffmc_high_bit(value) (i64) i64
  bit = 0 ## i64
  if value >> 32 != 0
    value = value >> 32
    bit += 32
  if value >> 16 != 0
    value = value >> 16
    bit += 16
  if value >> 8 != 0
    value = value >> 8
    bit += 8
  if value >> 4 != 0
    value = value >> 4
    bit += 4
  if value >> 2 != 0
    value = value >> 2
    bit += 2
  if value >> 1 != 0
    bit += 1
  bit

-> ffmc_valid(work, words, capacity, rank) (i64[] i64 i64 i64) i64
  if capacity < 1 || capacity > 1048576 || rank < 0 || rank > capacity
    return 0
  if words < ffmc_scratch_words(capacity)
    return 0
  i = 0 ## i64
  while i < rank
    if work[i] <= 0 || work[capacity + i] <= 0 || work[2 * capacity + i] <= 0
      return 0
    i += 1
  1

# Caller has validated the slab. Group iteration preserves first occurrence;
# factorization selects original columns in ascending (or descending) order.
# neutral=0 only replaces a group if its exact matrix rank strictly drops.
# neutral=1 also replaces rank ties, for bounded background basis proposals.
-> ffmc_axis(work, capacity, rank, axis, neutral, reverse_columns) (i64[] i64 i64 i64 i64 i64) i64
  output = 3 * capacity ## i64
  heads = 6 * capacity ## i64
  tails = 7 * capacity ## i64
  links = 8 * capacity ## i64
  buckets = 9 * capacity ## i64
  slots = ffmc_hash_capacity(capacity) ## i64
  columns = buckets + slots ## i64
  rows = columns + 63 ## i64
  combinations = rows + 63 ## i64
  left_basis = combinations + 63 ## i64
  right_basis = left_basis + 63 ## i64
  fixed_offset = axis * capacity ## i64
  left_offset = 0 ## i64
  right_offset = 2 * capacity ## i64
  if axis == 0
    left_offset = capacity
  if axis == 2
    right_offset = capacity
  i = 0 ## i64
  while i < slots
    work[buckets + i] = 0
    i += 1
  groups = 0 ## i64
  i = 0
  while i < rank
    key = work[fixed_offset + i] ## i64
    bucket = ffw_term_zobrist(key, 1, 1) & (slots - 1) ## i64
    found = 0 ## i64
    while found == 0
      group = work[buckets + bucket] - 1 ## i64
      if group < 0
        work[buckets + bucket] = groups + 1
        work[heads + groups] = i
        work[tails + groups] = i
        groups += 1
        found = 1
      else
        if work[fixed_offset + work[heads + group]] == key
          work[links + work[tails + group]] = i
          work[tails + group] = i
          found = 1
        else
          bucket = (bucket + 1) & (slots - 1)
    work[links + i] = 0 - 1
    i += 1
  kept = 0 ## i64
  group = 0 ## i64
  while group < groups
    first = work[heads + group] ## i64
    second = work[links + first] ## i64
    factor = 0 ## i64
    if second >= 0
      factor = 1
      # Two independent nonzero outer products already have matrix rank 2.
      if neutral == 0 && work[links + second] < 0 && work[left_offset + first] != work[left_offset + second] && work[right_offset + first] != work[right_offset + second]
        factor = 0
    replacement = 0 - 1 ## i64
    if factor == 1
      j = 0 ## i64
      while j < 63
        work[columns + j] = 0
        work[rows + j] = 0
        work[combinations + j] = 0
        work[right_basis + j] = 0
        j += 1
      count = 0 ## i64
      i = first
      while i >= 0
        left = work[left_offset + i] ## i64
        right = work[right_offset + i] ## i64
        while right != 0
          j = ffmc_high_bit(right)
          work[columns + j] = work[columns + j] ^ left
          right = right ^ (1 << j)
        count += 1
        i = work[links + i]
      basis_count = 0 ## i64
      column_index = 0 ## i64
      while column_index < 63
        j = column_index
        if reverse_columns == 1
          j = 62 - column_index
        column = work[columns + j] ## i64
        remainder = column ## i64
        coefficients = 0 ## i64
        while remainder != 0
          pivot = ffmc_high_bit(remainder) ## i64
          if work[rows + pivot] == 0
            bit = 1 << basis_count ## i64
            work[rows + pivot] = remainder
            work[combinations + pivot] = coefficients ^ bit
            work[left_basis + basis_count] = column
            basis_count += 1
            coefficients = bit
            remainder = 0
          else
            remainder = remainder ^ work[rows + pivot]
            coefficients = coefficients ^ work[combinations + pivot]
        while coefficients != 0
          b = ffmc_high_bit(coefficients) ## i64
          work[right_basis + b] = work[right_basis + b] | (1 << j)
          coefficients = coefficients ^ (1 << b)
        column_index += 1
      if basis_count < count || neutral == 1
        replacement = basis_count
    if replacement >= 0
      b = 0 ## i64
      while b < replacement
        work[output + fixed_offset + kept] = work[fixed_offset + first]
        work[output + left_offset + kept] = work[left_basis + b]
        work[output + right_offset + kept] = work[right_basis + b]
        kept += 1
        b += 1
    else
      i = first
      while i >= 0
        work[output + kept] = work[i]
        work[output + capacity + kept] = work[capacity + i]
        work[output + 2 * capacity + kept] = work[2 * capacity + i]
        kept += 1
        i = work[links + i]
    group += 1
  i = 0
  while i < kept
    work[i] = work[output + i]
    work[capacity + i] = work[output + capacity + i]
    work[2 * capacity + i] = work[output + 2 * capacity + i]
    i += 1
  kept

# Matches the offline compress_terms axis order (0,1,2) to a fixed point.
# The first three arrays are changed only after complete source validation.
-> ffmc_reduce(work, words, capacity, rank) (i64[] i64 i64 i64) i64
  if ffmc_valid(work, words, capacity, rank) == 0
    return 0 - 1
  changed = 1 ## i64
  while changed == 1
    before = rank ## i64
    axis = 0 ## i64
    while axis < 3
      rank = ffmc_axis(work, capacity, rank, axis, 0, 0)
      axis += 1
    changed = 0
    if rank < before
      changed = 1
  rank

-> ffmc_refactor(work, words, capacity, rank, axis, reverse_columns) (i64[] i64 i64 i64 i64 i64) i64
  if axis < 0 || axis > 2 || reverse_columns < 0 || reverse_columns > 1 || ffmc_valid(work, words, capacity, rank) == 0
    return 0 - 1
  ffmc_axis(work, capacity, rank, axis, 1, reverse_columns)
