# Experimental bounded GF(2) completion. The network orders proposals only;
# flattening ranks and complete tensor equality are the correctness gates.
use core/file
use ../../../lib/metaflip/cli

-> fflr_number(text) (String) i64
  if text.size() < 1 || text.size() > 64
    return 0
  i = 0 ## i64
  if text.slice(i, 1) == "+" || text.slice(i, 1) == "-"
    i += 1
  digits = 0 ## i64
  while i < text.size() && ffcli_decimal_digit(text.slice(i, 1)) >= 0
    i += 1
    digits += 1
  if i < text.size() && text.slice(i, 1) == "."
    i += 1
    while i < text.size() && ffcli_decimal_digit(text.slice(i, 1)) >= 0
      i += 1
      digits += 1
  if digits == 0
    return 0
  if i < text.size() && (text.slice(i, 1) == "e" || text.slice(i, 1) == "E")
    i += 1
    if i < text.size() && (text.slice(i, 1) == "+" || text.slice(i, 1) == "-")
      i += 1
    start = i ## i64
    while i < text.size() && ffcli_decimal_digit(text.slice(i, 1)) >= 0
      i += 1
    if start == i
      return 0
  if i == text.size()
    return 1
  0

# Fixed feature schema: sorted mode descriptors [unfolding rank, histogram of
# all nonzero slice combinations at matrix ranks 0..4]. Row-major MLP weights.
# Offsets: mean 0, scale 18, w1 36, b1 468, w2 492, b2 516.
-> fflr_load(path, model) (String f64[]) i64
  raw = File.read_prefix(path, 32769)
  if raw == nil || raw.size() > 32768
    return 0
  lines = raw.strip().split("\n")
  if lines.size() != 518 || lines[0] != "MFLR1 sorted-slice-ranks 18 24 1"
    return 0
  i = 0 ## i64
  while i < 517
    if fflr_number(lines[i+1]) != 1
      return 0
    value = lines[i+1].to_f() ## f64
    if !(value > -1000000.0 && value < 1000000.0)
      return 0
    if i >= 18 && i < 36 && value < 0.000001
      return 0
    model[i] = value
    i += 1
  1

-> fflr_score(features, model) (f64[] f64[]) f64
  result = model[516] ## f64
  h = 0 ## i64
  while h < 24
    value = model[468+h] ## f64
    i = 0 ## i64
    while i < 18
      normalized = (features[i] - model[i]) / model[18+i] ## f64
      value += normalized * model[36+24*i+h]
      i += 1
    if value > 0.0
      result += value * model[492+h]
    h += 1
  result

-> fflr_outer(u, v, w, b, c) (i64 i64 i64 i64 i64) i64
  value = 0 ## i64
  i = 0 ## i64
  while i < 4
    j = 0 ## i64
    while j < b
      if ((u >> i)&1) != 0 && ((v >> j)&1) != 0
        value ^= w << ((i*b+j)*c)
      j += 1
    i += 1
  value

# Elimination works on signed i64 bit patterns too, including core bit 63.
-> fflr_rank(rows, count, width, pivots) (i64[] i64 i64 i64[]) i64
  p = 0 ## i64
  while p < width
    pivots[p] = 0
    p += 1
  rank = 0 ## i64
  i = 0 ## i64
  while i < count
    value = rows[i] ## i64
    p = width-1
    while p >= 0 && value != 0
      if ((value >> p)&1) != 0
        if pivots[p] != 0
          value ^= pivots[p]
        else
          pivots[p] = value
          rank += 1
          value = 0
      p -= 1
    i += 1
  rank

-> fflr_slices(core, dims, axis, rows) (i64 i64[] i64 i64[]) i64
  i = 0 ## i64
  while i < 4
    rows[i] = 0
    i += 1
  a = 0 ## i64
  while a < dims[0]
    b = 0 ## i64
    while b < dims[1]
      c = 0 ## i64
      while c < dims[2]
        if ((core >> ((a*dims[1]+b)*dims[2]+c))&1) != 0
          if axis == 0
            rows[a] ^= 1 << (b*dims[2]+c)
          elsif axis == 1
            rows[b] ^= 1 << (a*dims[2]+c)
          else
            rows[c] ^= 1 << (a*dims[1]+b)
        c += 1
      b += 1
    a += 1
  0

-> fflr_lower(core, dims, rows, pivots) (i64 i64[] i64[] i64[]) i64
  bound = 0 ## i64
  axis = 0 ## i64
  while axis < 3
    z = fflr_slices(core, dims, axis, rows) ## i64
    r = fflr_rank(rows, dims[axis], 16, pivots) ## i64
    if r > bound
      bound = r
    axis += 1
  bound

-> fflr_features(core, dims, out, rows, pivots, matrix_rows, cache) (i64 i64[] f64[] i64[] i64[] i64[] i64[]) i64
  unit = 1.0 ## f64
  axis = 0 ## i64
  while axis < 3
    z = fflr_slices(core, dims, axis, rows) ## i64
    rank = fflr_rank(rows, dims[axis], 16, pivots) ## i64
    out[axis*6] = rank * unit
    i = 1 ## i64
    while i < 6
      out[axis*6+i] = 0.0
      i += 1
    columns = dims[2] ## i64
    if axis == 2
      columns = dims[1]
    combinations = (1 << dims[axis])-1 ## i64
    choice = 1 ## i64
    while choice <= combinations
      matrix = 0 ## i64
      i = 0
      while i < dims[axis]
        if ((choice >> i)&1) != 0
          matrix ^= rows[i]
        i += 1
      # Width is part of the cache key; matrices have at most 16 bits.
      key = columns*65536+matrix ## i64
      r = cache[key]-1 ## i64
      if r < 0
        i = 0
        while i < 4
          mask = (1 << columns)-1 ## i64
          matrix_rows[i] = (matrix >> (i*columns)) & mask
          i += 1
        r = fflr_rank(matrix_rows, 4, columns, pivots)
        cache[key] = r+1
      out[axis*6+1+r] += unit / combinations
      choice += 1
    axis += 1
  # Lexicographic sort removes mode-order dependence without density features.
  i = 1 ## i64
  while i < 3
    j = i ## i64
    while j > 0
      k = 0 ## i64
      while k < 6 && out[j*6+k] == out[(j-1)*6+k]
        k += 1
      if k == 6 || out[j*6+k] > out[(j-1)*6+k]
        break
      k = 0
      while k < 6
        value = out[j*6+k] ## f64
        out[j*6+k] = out[(j-1)*6+k]
        out[(j-1)*6+k] = value
        k += 1
      j -= 1
    i += 1
  0

# Build mode bases from the residual's fibers, never from its removed recipe.
# bases[axis*4+i] stores original ambient vectors; piv/code define a linear
# left inverse on that mode space and an arbitrary extension to its complement.
-> fflr_compress(terms, count, widths, dims, bases, piv, codes) (i64[] i64 i64[] i64[] i64[] i64[] i64[]) i64
  axis = 0 ## i64
  while axis < 3
    dims[axis] = 0
    p = 0 ## i64
    while p < 63
      piv[axis*63+p] = 0
      codes[axis*63+p] = 0
      p += 1
    left = 0 ## i64
    right = 2 ## i64
    if axis == 0
      left = 1
    if axis == 2
      right = 1
    i = 0 ## i64
    while i < widths[left]
      j = 0 ## i64
      while j < widths[right]
        original = 0 ## i64
        t = 0 ## i64
        while t < count
          if ((terms[3*t+left] >> i)&1) != 0 && ((terms[3*t+right] >> j)&1) != 0
            original ^= terms[3*t+axis]
          t += 1
        value = original ## i64
        code = 1 << dims[axis] ## i64
        p = widths[axis]-1
        while p >= 0 && value != 0
          if ((value >> p)&1) != 0
            if piv[axis*63+p] != 0
              value ^= piv[axis*63+p]
              code ^= codes[axis*63+p]
            else
              if dims[axis] == 4
                return 0
              piv[axis*63+p] = value
              codes[axis*63+p] = code
              bases[axis*4+dims[axis]] = original
              dims[axis] += 1
              value = 0
          p -= 1
        j += 1
      i += 1
    axis += 1
  1

-> fflr_project(value, axis, width, piv, codes) (i64 i64 i64 i64[] i64[]) i64
  result = 0 ## i64
  p = width-1 ## i64
  while p >= 0
    if ((value >> p)&1) != 0 && piv[axis*63+p] != 0
      value ^= piv[axis*63+p]
      result ^= codes[axis*63+p]
    p -= 1
  result

-> fflr_core(terms, count, widths, dims, piv, codes) (i64[] i64 i64[] i64[] i64[] i64[]) i64
  core = 0 ## i64
  t = 0 ## i64
  while t < count
    u = fflr_project(terms[3*t], 0, widths[0], piv, codes) ## i64
    v = fflr_project(terms[3*t+1], 1, widths[1], piv, codes) ## i64
    w = fflr_project(terms[3*t+2], 2, widths[2], piv, codes) ## i64
    if u != 0 && v != 0 && w != 0
      core ^= fflr_outer(u, v, w, dims[1], dims[2])
    t += 1
  core

-> fflr_lift(code, axis, bases) (i64 i64 i64[]) i64
  value = 0 ## i64
  i = 0 ## i64
  while i < 4
    if ((code >> i)&1) != 0
      value ^= bases[axis*4+i]
    i += 1
  value
