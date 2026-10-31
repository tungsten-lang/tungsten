# Model-only reduction of Boolean constraint blocks to GF(2). Each small
# clause-support block is expanded to its exact forbidden truth table and
# transformed to algebraic normal form. Disjoint quadratic pairs with the
# same local function in every row can serve as independent Boolean inputs.
# All original clauses must pass after lifting the linear solution.
use atomic_stop

# meta: status, blocks, columns, pairs, rank, clauses grouped, ANF XORs,
# eliminated rows, matrix-word XORs, checked literals, stop (1 cancel,2 time).
-> wassat_pair_affine_stop(meta, stop, deadline) (i64[] i64[] i64) i64
  if wassat_stop_load(stop) != 0
    meta[10] = 1
    return 1
  if deadline > 0 && clock_ms() >= deadline
    meta[10] = 2
    return 1
  0

-> wassat_pair_affine_build(lits, offs, lens, nv, nc, supports, widths, anf, meta, stop, deadline) (i64[] i64[] i64[] i64 i64 i32[] i8[] i8[] i64[] i64[] i64) i64
  slots = i32[4096]
  scratch = i32[6]
  groups = 0
  ci = 0
  while ci < nc
    return 0 if (ci & 255) == 0 && wassat_pair_affine_stop(meta, stop, deadline) != 0
    n = lens[ci]
    return 0 if n < 2 || n > 6
    off = offs[ci]
    i = 0
    while i < n
      l = lits[off + i]
      v = l < 0 ? 0 - l : l
      return 0 if v < 1 || v > nv
      j = i
      while j > 0 && scratch[j - 1] > v
        scratch[j] = scratch[j - 1]
        j -= 1
      scratch[j] = v
      i += 1
    h = n
    i = 0
    while i < n
      return 0 if i > 0 && scratch[i - 1] == scratch[i]
      h = (h * 131 + scratch[i]) & 4095
      i += 1
    found = 0
    while slots[h] != 0 && found == 0
      g = slots[h] - 1
      same = widths[g] == n ? 1 : 0
      i = 0
      while i < n && same == 1
        same = 0 if supports[6 * g + i] != scratch[i]
        i += 1
      if same == 1
        found = 1
      else
        h = (h + 1) & 4095
    if found == 0
      return 0 if groups >= 1024
      slots[h] = groups + 1
      widths[groups] = n
      i = 0
      while i < n
        supports[6 * groups + i] = scratch[i]
        i += 1
      groups += 1
    g = slots[h] - 1
    pattern = 0
    i = 0
    while i < n
      l = lits[off + i]
      if l < 0
        j = 0
        while scratch[j] != 0 - l
          j += 1
        pattern = pattern | (1 << j)
      i += 1
    anf[64 * g + pattern] = 1
    meta[5] += 1
    ci += 1
  meta[1] = groups
  return 0 if groups < 2
  # Mobius transform over the Boolean cube. Duplicate clauses set the same
  # truth-table bit; they cannot invent a missing forbidden assignment.
  g = 0
  while g < groups
    return 0 if (g & 31) == 0 && wassat_pair_affine_stop(meta, stop, deadline) != 0
    b = 0
    while b < widths[g]
      mask = 0
      while mask < (1 << widths[g])
        if (mask & (1 << b)) != 0
          anf[64 * g + mask] = anf[64 * g + mask] ^ anf[64 * g + (mask ^ (1 << b))]
          meta[6] += 1
        mask += 1
      b += 1
    g += 1
  1

-> wassat_pair_affine_matrix(supports, widths, anf, nv, mate, code, column, matrix, rhs, meta, stop, deadline) (i32[] i8[] i8[] i64 i32[] i8[] i32[] i64[] i8[] i64[] i64[] i64) i64
  groups = meta[1]
  g = 0
  while g < groups
    return 0 if (g & 31) == 0 && wassat_pair_affine_stop(meta, stop, deadline) != 0
    mask = 1
    while mask < (1 << widths[g])
      if anf[64 * g + mask] != 0
        degree = 0
        a = 0
        b = 0
        i = 0
        while i < widths[g]
          if (mask & (1 << i)) != 0
            if degree == 0
              a = supports[6 * g + i]
            else
              b = supports[6 * g + i]
            degree += 1
          i += 1
        return 0 if degree > 2
        if degree == 2
          return 0 if (mate[a] != 0 && mate[a] != b) || (mate[b] != 0 && mate[b] != a)
          mate[a] = b
          mate[b] = a
      mask += 1
    g += 1
  v = 1
  ncols = 0
  npairs = 0
  while v <= nv
    if column[v] == 0
      column[v] = ncols + 1
      if mate[v] != 0
        column[mate[v]] = ncols + 1
        npairs += 1
      ncols += 1
    v += 1
  meta[2] = ncols
  meta[3] = npairs
  return 0 if npairs == 0
  words = (nv + 63) / 64
  one = 1 ## i64
  g = 0
  while g < groups
    return 0 if (g & 31) == 0 && wassat_pair_affine_stop(meta, stop, deadline) != 0
    rhs[g] = anf[64 * g]
    i = 0
    while i < widths[g]
      v = supports[6 * g + i]
      take = 0
      if mate[v] == 0
        take = anf[64 * g + (1 << i)]
      elsif v < mate[v]
        j = 0
        while j < widths[g] && supports[6 * g + j] != mate[v]
          j += 1
        return 0 if j == widths[g]
        return 0 if anf[64 * g + ((1 << i) | (1 << j))] != 1
        signature = 1 + anf[64 * g + (1 << i)] + 2 * anf[64 * g + (1 << j)]
        return 0 if code[v] != 0 && code[v] != signature
        code[v] = signature
        take = 1
      else
        j = 0
        while j < widths[g] && supports[6 * g + j] != mate[v]
          j += 1
        return 0 if j == widths[g]
      if take == 1
        c = column[v] - 1
        mask = one << (c % 64) ## i64
        at = g * words + c / 64 ## i64
        bits = matrix[at] ## i64
        matrix[at] = bits ^ mask
      i += 1
    g += 1
  1

-> wassat_pair_affine_eliminate(matrix, rhs, solution, nv, meta, stop, deadline) (i64[] i8[] i8[] i64 i64[] i64[] i64) i64
  words = (nv + 63) / 64
  nrows = meta[1]
  ncols = meta[2]
  pivots = i32[nrows]
  one = 1 ## i64
  rank = 0
  col = 0
  while col < ncols && rank < nrows
    return 0 if (col & 15) == 0 && wassat_pair_affine_stop(meta, stop, deadline) != 0
    mask = one << (col % 64) ## i64
    pivot = rank
    while pivot < nrows && (matrix[pivot * words + col / 64] & mask) == 0
      pivot += 1
    if pivot < nrows
      if pivot != rank
        w = 0
        while w < words
          bits = matrix[rank * words + w] ## i64
          matrix[rank * words + w] = matrix[pivot * words + w]
          matrix[pivot * words + w] = bits
          w += 1
        t = rhs[rank]
        rhs[rank] = rhs[pivot]
        rhs[pivot] = t
      row = rank + 1
      while row < nrows
        if (matrix[row * words + col / 64] & mask) != 0
          w = 0
          while w < words
            a = row * words + w ## i64
            b = rank * words + w ## i64
            bits = matrix[a] ## i64
            other = matrix[b] ## i64
            matrix[a] = bits ^ other
            meta[8] += 1
            w += 1
          rhs[row] = rhs[row] ^ rhs[rank]
          meta[7] += 1
        row += 1
      pivots[rank] = col
      rank += 1
    col += 1
  meta[4] = rank
  row = rank
  while row < nrows
    # Echelon construction has exhausted every column on these rows.
    return 0 if rhs[row] != 0
    row += 1
  row = rank - 1
  while row >= 0
    return 0 if (row & 31) == 0 && wassat_pair_affine_stop(meta, stop, deadline) != 0
    col = pivots[row]
    value = rhs[row]
    c = col + 1
    while c < ncols
      mask = one << (c % 64)
      value = value ^ solution[c] if (matrix[row * words + c / 64] & mask) != 0
      c += 1
    solution[col] = value
    row -= 1
  1

-> wassat_pair_affine_lift(lits, offs, lens, nv, nc, mate, code, column, solution, model, meta, stop, deadline) (i64[] i64[] i64[] i64 i64 i32[] i8[] i32[] i8[] i64[] i64[] i64[] i64) i64
  v = 1
  while v <= nv
    value = solution[column[v] - 1]
    if mate[v] == 0
      model[v - 1] = value == 1 ? v : 0 - v
    elsif v < mate[v]
      signature = code[v] - 1
      return 0 if signature < 0
      a = 0
      found = 0
      while a < 2 && found == 0
        b = 0
        while b < 2 && found == 0
          image = (a & b) ^ ((signature & 1) & a) ^ (((signature >> 1) & 1) & b)
          if image == value
            model[v - 1] = a == 1 ? v : 0 - v
            model[mate[v] - 1] = b == 1 ? mate[v] : 0 - mate[v]
            found = 1
          b += 1
        a += 1
      return 0 if found == 0
    v += 1
  ci = 0
  while ci < nc
    return 0 if (ci & 255) == 0 && wassat_pair_affine_stop(meta, stop, deadline) != 0
    j = 0
    sat = 0
    while j < lens[ci] && sat == 0
      l = lits[offs[ci] + j]
      v = l < 0 ? 0 - l : l
      sat = 1 if model[v - 1] == l
      meta[9] += 1
      j += 1
    return 0 if sat == 0
    ci += 1
  meta[0] = 1
  1

-> wassat_pair_affine_model(formula, stop, deadline = 0)
  return nil if formula == nil
  nv = formula["nvars"]
  nc = formula["flat_ncl"]
  return nil if nv < 2 || nv > 1024 || nc < 4 || nc > 32768
  meta = i64[11]
  result = { "meta": meta, "model": [] }
  return result if wassat_pair_affine_stop(meta, stop, deadline) != 0
  supports = i32[6144]
  widths = i8[1024]
  anf = i8[65536]
  return result if wassat_pair_affine_build(formula["flat_lits"], formula["flat_offs"], formula["flat_lens"], nv, nc, supports, widths, anf, meta, stop, deadline) == 0
  mate = i32[nv + 1]
  code = i8[nv + 1]
  column = i32[nv + 1]
  matrix = i64[meta[1] * ((nv + 63) / 64)]
  rhs = i8[meta[1]]
  return result if wassat_pair_affine_matrix(supports, widths, anf, nv, mate, code, column, matrix, rhs, meta, stop, deadline) == 0
  solution = i8[meta[2]]
  return result if wassat_pair_affine_eliminate(matrix, rhs, solution, nv, meta, stop, deadline) == 0
  model = i64[nv]
  return result if wassat_pair_affine_lift(formula["flat_lits"], formula["flat_offs"], formula["flat_lens"], nv, nc, mate, code, column, solution, model, meta, stop, deadline) == 0
  result["model"] = model
  result
