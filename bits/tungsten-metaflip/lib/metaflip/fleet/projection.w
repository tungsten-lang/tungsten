# Bounded one-coordinate projections of the native positive-i64 tensor format.
# Source and destination must be disjoint slabs. No input mutation, allocations,
# archive policy or implicit widening; multiword shapes use a different format.
use matrix_cleanup

-> ffmp_project_mask(value, rows, columns, drop_row, drop_column) (i64 i64 i64 i64 i64) i64
  new_columns = columns ## i64
  if drop_column >= 0
    new_columns -= 1
  out = 0 ## i64
  while value != 0
    bit = ffmc_high_bit(value) ## i64
    value = value ^ (1 << bit)
    row = bit / columns ## i64
    column = bit % columns ## i64
    if row != drop_row && column != drop_column
      if drop_row >= 0 && row > drop_row
        row -= 1
      if drop_column >= 0 && column > drop_column
        column -= 1
      out = out | (1 << (row * new_columns + column))
  out

-> ffmp_project(source, source_words, source_capacity, rank, n, m, p, axis, removed, output, output_words, capacity) (i64[] i64 i64 i64 i64 i64 i64 i64 i64 i64[] i64 i64) i64
  if n < 1 || m < 1 || p < 1 || n > 63 || m > 63 || p > 63 || n*m > 63 || m*p > 63 || n*p > 63
    return 0 - 1
  if source_capacity < 1 || source_capacity > 1048576 || capacity < 1 || capacity > 1048576 || rank < 0 || rank > source_capacity || rank > capacity
    return 0 - 1
  if source_words < 3 * source_capacity || output_words < 3 * capacity || axis < 0 || axis > 2
    return 0 - 1
  size = n ## i64
  if axis == 1
    size = m
  if axis == 2
    size = p
  if size < 2 || removed < 0 || removed >= size
    return 0 - 1
  umask = ffr_factor_mask(n*m) ## i64
  vmask = ffr_factor_mask(m*p) ## i64
  wmask = ffr_factor_mask(n*p) ## i64
  i = 0 ## i64
  while i < rank
    u = source[i] ## i64
    v = source[source_capacity + i] ## i64
    w = source[2 * source_capacity + i] ## i64
    if u <= 0 || v <= 0 || w <= 0 || (u & umask) != u || (v & vmask) != v || (w & wmask) != w
      return 0 - 1
    i += 1
  kept = 0 ## i64
  i = 0
  while i < rank
    u = source[i] ## i64
    v = source[source_capacity + i] ## i64
    w = source[2 * source_capacity + i] ## i64
    if axis == 0
      u = ffmp_project_mask(u, n, m, removed, 0 - 1)
      w = ffmp_project_mask(w, n, p, removed, 0 - 1)
    if axis == 1
      u = ffmp_project_mask(u, n, m, 0 - 1, removed)
      v = ffmp_project_mask(v, m, p, removed, 0 - 1)
    if axis == 2
      v = ffmp_project_mask(v, m, p, 0 - 1, removed)
      w = ffmp_project_mask(w, n, p, 0 - 1, removed)
    if u != 0 && v != 0 && w != 0
      output[kept] = u
      output[capacity + kept] = v
      output[2 * capacity + kept] = w
      kept += 1
    i += 1
  kept
