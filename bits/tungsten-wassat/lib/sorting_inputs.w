# Recover input patterns from shared comparator-control expressions.
# Recognition only guides a candidate; the caller validates original CNF.
use sorting_walk

-> wassat_sorting_root(parent, v) (i32[] i64) i64
  root = v ## i64
  while parent[root] != root
    root = parent[root]
  while parent[v] != v
    next_v = parent[v] ## i64
    parent[v] = root; v = next_v
  root

-> wassat_sorting_join(parent, a, b) (i32[] i64 i64) i64
  a = wassat_sorting_root(parent,a); b = wassat_sorting_root(parent,b)
  if a < b
    parent[b] = a
  else
    parent[a] = b
  0

-> wassat_sorting_abs(x) (i64) i64
  x < 0 ? -x : x

# Improved encodings share ORs of comparator selectors across test circuits.
# Check each full equivalence before removing it from the signal graph.
# Its zero-comparator boundary then supplies the omitted idle-wire bits.
-> wassat_sorting_encoded_inputs(formula, controls, max_flag, group, va, vb, m, stop, deadline)
  nv = formula["nvars"]; nc = formula["flat_ncl"]
  lits = formula["flat_lits"] ## i64[]
  offs = formula["flat_offs"] ## i64[]
  lens = formula["flat_lens"] ## i64[]
  definition = i32[nv+1]; polarity = i8[nv+1]; support = i32[nv+1]
  ci = 0
  while ci < nc
    return nil if (ci & 1023) == 0 && wassat_sorting_poll(m,stop,deadline) != 0
    length = lens[ci]
    if length >= 2 && length <= m[0]
      j = 0; out = 0; valid = true
      while j < length
        lit = lits[offs[ci]+j]
        if wassat_sorting_abs(lit) > max_flag
          valid = false if out != 0
          out = lit
        elsif lit <= 0 || lit > controls
          valid = false
        j += 1
      if valid && out != 0
        v = wassat_sorting_abs(out)
        definition[v] = definition[v] == 0 ? ci+1 : -1
        polarity[v] = out > 0 ? 1 : -1
    m[23] += length; ci += 1
  # A wide implication alone is insufficient: every reverse implication
  # must be present, and repeated literals cannot count as extra support.
  ci = 0
  while ci < nc
    return nil if (ci & 2047) == 0 && wassat_sorting_poll(m,stop,deadline) != 0
    if lens[ci] == 2
      a = lits[offs[ci]]; b = lits[offs[ci]+1]
      if wassat_sorting_abs(a) <= max_flag
        saved = a; a = b; b = saved
      v = wassat_sorting_abs(a)
      if v > max_flag && b < 0 && -b <= controls && definition[v] > 0
        if (a > 0) != (polarity[v] > 0)
          dc = definition[v]-1; j = 0
          while j < lens[dc]
            support[v] |= 1 << j if lits[offs[dc]+j] == -b
            j += 1
    m[23] += lens[ci]; ci += 1
  low = i8[nv+1]; high = i8[nv+1]
  parent = i32[nv+1]; v = 0
  while v <= nv
    return nil if (v & 2047) == 0 && wassat_sorting_poll(m,stop,deadline) != 0
    parent[v] = v
    if definition[v] > 0
      dc = definition[v]-1; mask = 0; j = 0; lo = -1; hi = -1; first_layer = true
      while j < lens[dc]
        lit = lits[offs[dc]+j]
        if lit > 0 && lit <= controls
          mask |= 1 << j
          first_layer = false if group[lit] != 0
          if lo == -1
            lo = va[lit]; hi = vb[lit]
          else
            lo = -2 if lo != va[lit]
            hi = -2 if hi != vb[lit]
        j += 1
      if support[v] != mask
        definition[v] = 0
      else
        m[29] += 1
        if first_layer
          low[v] = lo+1 if lo >= 0
          high[v] = hi+1 if hi >= 0
    else
      definition[v] = 0
    v += 1
  return nil if m[29] == 0
  ci = 0
  while ci < nc
    return nil if (ci & 2047) == 0 && wassat_sorting_poll(m,stop,deadline) != 0
    j = 0; first = 0
    while j < lens[ci]
      v = wassat_sorting_abs(lits[offs[ci]+j])
      if v > max_flag && definition[v] == 0
        if first == 0
          first = v
        else
          z = wassat_sorting_join(parent,first,v)
      j += 1
    m[23] += lens[ci]; ci += 1
  known = i32[nv+1]; values = i32[nv+1]
  ci = 0
  while ci < nc
    return nil if (ci & 1023) == 0 && wassat_sorting_poll(m,stop,deadline) != 0
    j = 0; root = 0
    while j < lens[ci]
      v = wassat_sorting_abs(lits[offs[ci]+j])
      if v > max_flag && definition[v] == 0
        root = wassat_sorting_root(parent,v)
        break
      j += 1
    if root != 0
      j = 0
      while j < lens[ci]
        v = wassat_sorting_abs(lits[offs[ci]+j])
        if definition[v] > 0
          wire = polarity[v] > 0 ? low[v] : high[v]
          if wire > 0
            bit = 1 << (wire-1); value = polarity[v] > 0
            if (known[root] & bit) != 0
              return nil if ((values[root] & bit) != 0) != value
            known[root] |= bit
            values[root] |= bit if value
            m[30] += 1
        j += 1
      if lens[ci] == 2
        j = 0
        while j < 2
          lit = lits[offs[ci]+j]; other = lits[offs[ci]+1-j]
          v = wassat_sorting_abs(lit); u = wassat_sorting_abs(other)
          if definition[v] > 0 && u > max_flag && definition[u] == 0 && (lit > 0) != (polarity[v] > 0)
            wire = other > 0 ? low[v] : high[v]
            if wire > 0
              bit = 1 << (wire-1); value = other > 0
              if (known[root] & bit) != 0
                return nil if ((values[root] & bit) != 0) != value
              known[root] |= bit
              values[root] |= bit if value
              m[30] += 1
          j += 1
    m[23] += lens[ci]; ci += 1
  vectors = i32[4096]; count = 0; v = max_flag+1
  while v <= nv
    return nil if (v & 2047) == 0 && wassat_sorting_poll(m,stop,deadline) != 0
    if known[v] != 0
      return nil if count >= 4096
      lo = 0; hi = m[0]-1
      while (known[v] & (1<<lo)) == 0
        lo += 1
      while (known[v] & (1<<hi)) == 0
        hi -= 1
      b = lo
      while b <= hi
        return nil if (known[v] & (1<<b)) == 0
        b += 1
      value = values[v]
      while b < m[0]
        value |= 1 << b; b += 1
      vectors[count] = value; count += 1
    v += 1
  return nil if count == 0
  m[4] = count; m[31] = count
  vectors
