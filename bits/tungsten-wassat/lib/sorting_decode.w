# This recognizer proposes a comparator interpretation, never a verdict.
# Coordinates come from ordered participation flags and a terminal path.
# Signal components and their idle-wire clauses supply the input patterns.
# Other encodings, incomplete coordinates and exhausted bounds return nil.
use sorting_inputs

-> wassat_sorting_decode(formula, m, stop, deadline)
  nv = formula["nvars"]
  nc = formula["flat_ncl"]
  lits = formula["flat_lits"] ## i64[]
  offs = formula["flat_offs"] ## i64[]
  lens = formula["flat_lens"] ## i64[]
  return nil if nv < 16 || nv > 250000 || nc < 16 || nc > 10000000
  return nil if lens.size < nc || offs.size < nc
  scan = nc < 65536 ? nc : 65536
  first_flag = 0
  n = 0
  ci = 0
  # The first wide disjunction defines the participation flag and width.
  while ci < scan
    if lens[ci] >= 8 && lens[ci] <= 16
      off = offs[ci]
      neg = 0; negs = 0; largest = 0; j = 0
      while j < lens[ci]
        lit = lits[off+j]
        if lit < 0
          neg = -lit; negs += 1
        else
          largest = lit if lit > largest
        j += 1
      if negs == 1 && neg > largest && neg <= 2049
        n = lens[ci]; first_flag = neg
        break
    ci += 1
  return nil if first_flag == 0
  controls = first_flag-1
  return nil if controls < n*(n-1)/2
  m[0] = n; m[2] = controls; m[22] = 1
  parent = i32[nv+1]
  i = 0
  while i <= nv
    parent[i] = i; i += 1
  stride = controls+1
  adjacency = i8[stride*stride]
  incidence = i32[2*stride]
  membership = i8[stride]
  flag_clause = i32[4096]
  max_flag = controls
  ci = 0
  while ci < scan
    return nil if (ci & 1023) == 0 && wassat_sorting_poll(m,stop,deadline) != 0
    off = offs[ci]; length = lens[ci]
    if length == 2
      a = -lits[off]; b = -lits[off+1]
      if a > 0 && b > 0 && a <= controls && b <= controls
        return nil if a == b
        adjacency[a*stride+b] = 1; adjacency[b*stride+a] = 1
        z = wassat_sorting_join(parent,a,b)
    if length >= 2 && length <= n
      neg = 0; negs = 0; largest = 0; j = 0
      while j < length
        lit = lits[off+j]
        if lit < 0
          neg = -lit; negs += 1
        else
          largest = lit if lit > largest
        j += 1
      if negs == 1 && neg > controls && neg < 4096 && largest <= controls
        flag_clause[neg] = flag_clause[neg] == 0 ? ci+1 : -1
    ci += 1
  # Participation flags form the consecutive block after the selectors.
  # Signal aliases can have the same clause shape later in the encoding;
  # only build wire memberships from the actual contiguous flag block.
  while max_flag+1 < 4096 && flag_clause[max_flag+1] != 0
    max_flag += 1
  return nil if max_flag <= controls || max_flag >= nv
  flag = first_flag
  while flag <= max_flag
    return nil if flag_clause[flag] < 0
    ci = flag_clause[flag]-1
    j = 0
    while j < lens[ci]
      v = lits[offs[ci]+j]
      if v > 0
        return nil if membership[v] >= 2
        incidence[2*v+membership[v]] = flag
        membership[v] += 1
      j += 1
    flag += 1
  m[3] = max_flag
  roots = i32[10]
  group = i32[stride]
  depth = 0
  v = 1
  while v <= controls
    r = wassat_sorting_root(parent,v)
    if r == v
      return nil if depth >= 10
      roots[depth] = r; depth += 1
    k = 0
    while k < depth && roots[k] != r
      k += 1
    return nil if k == depth
    group[v] = k
    v += 1
  return nil if depth < 2
  m[1] = depth
  allowed = i32[depth*n*n]
  first_flags = i32[4096]
  fs = i32[16]
  layer = 0
  while layer < depth
    nf = 0; flag = first_flag
    while flag <= max_flag
      if flag_clause[flag] != 0
        ci = flag_clause[flag]-1; j = 0; owner = -1
        while j < lens[ci]
          v = lits[offs[ci]+j]
          if v > 0
            owner = group[v] if owner < 0
            return nil if owner != group[v]
          j += 1
        if owner == layer
          return nil if nf >= n
          fs[nf] = flag
          first_flags[flag] = nf+1 if layer == 0
          nf += 1
      flag += 1
    if nf == n
      v = 1
      while v <= controls
        if group[v] == layer
          return nil if membership[v] != 2
          a = -1; b = -1; j = 0
          while j < n
            a = j if fs[j] == incidence[2*v]
            b = j if fs[j] == incidence[2*v+1]
            j += 1
          return nil if a < 0 || b < 0 || a == b || allowed[(layer*n+a)*n+b] != 0
          allowed[(layer*n+a)*n+b] = v; allowed[(layer*n+b)*n+a] = v
        v += 1
    else
      # Preprocessing may alias the final endpoint flags. Its negative
      # matching constraints still form a path of adjacent comparators.
      return nil if layer != depth-1
      count = 0; endpoints = 0; first = 0; smallest = 4096
      v = 1
      while v <= controls
        if group[v] == layer
          count += 1; degree = 0; u = 1
          while u <= controls
            degree += adjacency[v*stride+u]; u += 1
          return nil if degree < 1 || degree > 2
          if degree == 1
            endpoints += 1
            j = 0
            while j < membership[v]
              flag = incidence[2*v+j]
              if flag < smallest
                smallest = flag; first = v
              j += 1
        v += 1
      return nil if count != n-1 || endpoints != 2 || first == 0
      v = first; prev = 0; a = 0
      while a < n-1
        return nil if v == 0
        allowed[(layer*n+a)*n+a+1] = v
        allowed[(layer*n+a+1)*n+a] = v
        next_v = 0; u = 1
        while u <= controls
          next_v = u if adjacency[v*stride+u] != 0 && u != prev
          u += 1
        prev = v; v = next_v; a += 1
      return nil if v != 0
    layer += 1
  # Check the complete decoded matching graph, not only its group sizes.
  va = i32[stride]; vb = i32[stride]
  layer = 0
  while layer < depth
    a = 0
    while a < n
      b = a+1
      while b < n
        v = allowed[(layer*n+a)*n+b]
        if v > 0
          va[v] = a; vb[v] = b
        b += 1
      a += 1
    layer += 1
  v = 1
  while v <= controls
    u = v+1
    while u <= controls
      share = group[v] == group[u] && (va[v] == va[u] || va[v] == vb[u] || vb[v] == va[u] || vb[v] == vb[u])
      return nil if (adjacency[v*stride+u] != 0) != share
      u += 1
    v += 1
  m[22] = 2
  # Distinct test inputs have independent signal variables above flags.
  ci = 0
  while ci < nc
    return nil if (ci & 2047) == 0 && wassat_sorting_poll(m,stop,deadline) != 0
    j = 0; first = 0
    while j < lens[ci]
      v = wassat_sorting_abs(lits[offs[ci]+j])
      if v > max_flag
        if first == 0
          first = v
        else
          z = wassat_sorting_join(parent,first,v)
      j += 1
    m[23] += lens[ci]; ci += 1
  known = i32[nv+1]; values = i32[nv+1]
  ci = 0
  while ci < nc
    return nil if (ci & 2047) == 0 && wassat_sorting_poll(m,stop,deadline) != 0
    if lens[ci] == 2
      off = offs[ci]; a = lits[off]; b = lits[off+1]
      if a < first_flag || a > max_flag || first_flags[a] == 0
        saved = a; a = b; b = saved
      if a >= first_flag && a <= max_flag && first_flags[a] != 0 && wassat_sorting_abs(b) > max_flag
        r = wassat_sorting_root(parent,wassat_sorting_abs(b))
        bit = 1 << (first_flags[a]-1)
        if (known[r] & bit) != 0
          return nil if ((values[r] & bit) != 0) != (b > 0)
        known[r] |= bit
        values[r] |= bit if b > 0
    ci += 1
  vectors = i32[4096]
  count = 0; v = max_flag+1
  while v <= nv
    if known[v] != 0
      return nil if count >= 4096
      lo = 0; hi = n-1
      while (known[v] & (1<<lo)) == 0
        lo += 1
      while (known[v] & (1<<hi)) == 0
        hi -= 1
      b = lo
      while b <= hi
        return nil if (known[v] & (1<<b)) == 0
        b += 1
      value = values[v]
      while b < n
        value |= 1 << b; b += 1
      vectors[count] = value; count += 1
    v += 1
  if count == 0
    return nil if env("WASSAT_SORTING_ENCODING") == "0"
    vectors = wassat_sorting_encoded_inputs(formula,controls,max_flag,group,va,vb,m,stop,deadline)
    return nil if vectors == nil
    count = m[4]
  m[4] = count; m[5] = nc; m[22] = 3
  { "allowed": allowed, "vectors": vectors }
