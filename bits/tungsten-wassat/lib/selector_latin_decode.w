# Derive exact-one cells, Latin lines, and private selector relations from original CNF.
use selector_latin_search

-> wassat_qg_abs(x) (i64) i64
  x < 0 ? 0 - x : x

-> wassat_qg_find(parent, x) (i64[] i64) i64
  while parent[x] != x
    parent[x] = parent[parent[x]]
    x = parent[x]
  x

-> wassat_qg_pair(a, b, nv) (i64 i64 i64) i64
  t = 0 ## i64
  if a > b
    t = a
    a = b
    b = t
  (a + nv) * (2 * nv + 1) + b + nv

-> wassat_qg_pair_has(keys, key) (i64[] i64) i64
  mask = keys.size - 1 ## i64
  h = (key * 73856093) & mask ## i64
  while keys[h] != 0 && keys[h] != key
    h = (h + 1) & mask
  keys[h] == key ? 1 : 0

# BCP only: every retained literal and every unit has an original-clause
# reason. No elimination, variable merging, or identity-based recognition.
-> wassat_qg_reduce(lits, offs, lens, nc, units, out, outoffs, outlens, m, stop) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64[] i64[]) i64
  changed = 1 ## i64
  while changed != 0
    return 0 if wassat_qg_poll(m, stop) != 0
    changed = 0
    ci = 0 ## i64
    while ci < nc
      sat = 0 ## i64
      open = 0 ## i64
      last = 0 ## i64
      j = 0 ## i64
      while j < lens[ci]
        l = lits[offs[ci] + j] ## i64
        v = wassat_qg_abs(l) ## i64
        if units[v] == 0
          open += 1
          last = l
        elsif units[v] == l
          sat = 1
          break
        j += 1
      if sat == 0
        return 0 if open == 0
        if open == 1
          units[wassat_qg_abs(last)] = last
          changed = 1
          m[20] += 1
      ci += 1
  count = 0 ## i64
  used = 0 ## i64
  ci = 0
  while ci < nc
    sat = 0
    j = 0
    while j < lens[ci]
      l = lits[offs[ci] + j]
      sat = 1 if units[wassat_qg_abs(l)] == l
      j += 1
    if sat == 0
      outoffs[count] = used
      j = 0
      while j < lens[ci]
        l = lits[offs[ci] + j]
        if units[wassat_qg_abs(l)] == 0
          out[used] = l
          used += 1
        j += 1
      outlens[count] = used - outoffs[count]
      return 0 if outlens[count] > 32
      count += 1
    ci += 1
  m[21] = count
  m[22] = used
  1

# Detect disjoint exact-one cells using an ALO and all pairwise AMO clauses.
-> wassat_qg_cells(lits, offs, lens, nc, nv, keys, cell, sign, members, widths, m, stop) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  ci = 0 ## i64
  while ci < nc
    if lens[ci] == 2
      a = lits[offs[ci]] ## i64
      b = lits[offs[ci] + 1] ## i64
      key = wassat_qg_pair(a, b, nv) ## i64
      h = (key * 73856093) & (keys.size - 1) ## i64
      while keys[h] != 0 && keys[h] != key
        h = (h + 1) & (keys.size - 1)
      keys[h] = key
    ci += 1
  ci = 0
  ng = 0 ## i64
  while ci < nc
    return 0 if (ci & 255) == 0 && wassat_qg_poll(m, stop) != 0
    n = lens[ci] ## i64
    if n == 6 || n == 7
      good = 1 ## i64
      j = 0 ## i64
      while j < n && good != 0
        a = lits[offs[ci] + j]
        k = j + 1 ## i64
        while k < n
          b = lits[offs[ci] + k]
          if wassat_qg_abs(a) == wassat_qg_abs(b) || wassat_qg_pair_has(keys, wassat_qg_pair(0 - a, 0 - b, nv)) == 0
            good = 0
            break
          k += 1
        j += 1
      if good != 0
        existing = cell[wassat_qg_abs(lits[offs[ci]])] ## i64
        if existing != 0
          return 0 if widths[existing - 1] != n
          j = 0
          while j < n
            a = lits[offs[ci] + j]
            return 0 unless cell[wassat_qg_abs(a)] == existing && sign[wassat_qg_abs(a)] == a
            j += 1
        else
          return 0 if ng >= 49
          j = 0
          while j < n
            a = lits[offs[ci] + j]
            return 0 if cell[wassat_qg_abs(a)] != 0
            cell[wassat_qg_abs(a)] = ng + 1
            sign[wassat_qg_abs(a)] = a
            members[ng * 7 + j] = a
            j += 1
          widths[ng] = n
          ng += 1
    ci += 1
  m[23] = ng
  ng == 49 ? 1 : 0

# Recover two partitions into seven lines and seven shared symbols. A line
# must have exactly the positive literals for its symbol and its cell scope.
-> wassat_qg_grid(lits, offs, lens, nc, nv, cell, sign, widths, canonical, initial, m, stop) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  scopes = i64[98]
  lineclauses = i64[98]
  full = i64[14]
  scopeid = i64[98]
  parent = i64[98]
  first = i64[nv + 1]
  seen = i64[nv + 1]
  ci = 0 ## i64
  nl = 0 ## i64
  nf = 0 ## i64
  one = 1 ## i64
  while ci < nc
    n = lens[ci] ## i64
    if n == 6 || n == 7
      mask = 0 ## i64
      good = 1 ## i64
      j = 0 ## i64
      while j < n
        l = lits[offs[ci] + j] ## i64
        v = wassat_qg_abs(l) ## i64
        if cell[v] == 0 || sign[v] != l
          good = 0
          break
        bit = one << (cell[v] - 1) ## i64
        if (mask & bit) != 0
          good = 0
          break
        mask |= bit
        j += 1
      if good != 0
        return 0 if nl >= 98
        scopes[nl] = mask
        lineclauses[nl] = ci
        parent[nl] = nl
        if n == 7
          k = 0 ## i64
          while k < nf && full[k] != mask
            k += 1
          if k == nf
            return 0 if nf >= 14
            full[nf] = mask
            nf += 1
        nl += 1
    ci += 1
  return 0 unless nl == 98 && nf == 14
  # Deterministic ordering is a heuristic only, never an input fingerprint.
  i = 1 ## i64
  while i < nf
    x = full[i] ## i64
    j = i
    while j > 0 && full[j - 1] > x
      full[j] = full[j - 1]
      j -= 1
    full[j] = x
    i += 1
  axes = i64[14]
  na = 0 ## i64
  nb = 0 ## i64
  i = 0
  while i < 14
    if i == 0 || (full[i] & full[0]) == 0
      return 0 if na >= 7
      axes[na] = i
      na += 1
    else
      return 0 if nb >= 7
      axes[7 + nb] = i
      nb += 1
    i += 1
  return 0 unless na == 7 && nb == 7
  coordinates = i64[49]
  covered = 0 ## i64
  a = 0 ## i64
  while a < 7
    b = 0 ## i64
    while b < 7
      mask = full[axes[a]] & full[axes[7 + b]]
      return 0 if wassat_qg_pop(mask) != 1 || (covered & mask) != 0
      coordinates[wassat_qg_ctz(mask)] = a * 7 + b
      covered |= mask
      b += 1
    a += 1
  return 0 unless wassat_qg_pop(covered) == 49
  i = 0
  while i < 98
    matches = 0 ## i64
    j = 0
    while j < 14
      if (scopes[i] & full[j]) == scopes[i]
        scopeid[i] = j
        matches += 1
      j += 1
    return 0 if matches != 1
    ci = lineclauses[i]
    j = 0
    while j < lens[ci]
      v = wassat_qg_abs(lits[offs[ci] + j])
      if seen[v] == 0
        first[v] = i
      else
        parent[wassat_qg_find(parent, i)] = wassat_qg_find(parent, first[v])
      seen[v] += 1
      return 0 if seen[v] > 2
      j += 1
    i += 1
  roots = i64[7]
  nr = 0 ## i64
  symbols = i64[98]
  i = 0
  while i < 98
    root = wassat_qg_find(parent, i) ## i64
    j = 0
    while j < nr && roots[j] != root
      j += 1
    if j == nr
      return 0 if nr >= 7
      roots[nr] = root
      nr += 1
    symbols[i] = j
    i += 1
  return 0 if nr != 7
  counts = i64[98]
  i = 0
  while i < 98
    k = scopeid[i] * 7 + symbols[i]
    counts[k] += 1
    return 0 if counts[k] != 1
    i += 1
  v = 1
  while v <= nv
    if cell[v] != 0
      return 0 if seen[v] != 2
      g = coordinates[cell[v] - 1] ## i64
      sym = symbols[first[v]] ## i64
      bit = one << sym
      return 0 if (initial[g] & bit) != 0
      initial[g] |= bit
      canonical[v] = (g * 7 + sym + 1) * (sign[v] > 0 ? 1 : -1)
    v += 1
  # Check each line really covers all present values of that symbol in its
  # seven cells, not merely a coincidentally intersecting clause family.
  i = 0
  while i < 98
    n = 0 ## i64
    v = 1
    while v <= nv
      if cell[v] != 0 && (full[scopeid[i]] & (one << (cell[v] - 1))) != 0 && symbols[first[v]] == symbols[i]
        n += 1
      v += 1
    return 0 if n != lens[lineclauses[i]]
    i += 1
  m[24] = nl
  m[25] = nr
  1

# Clause classification under auxiliary assignments only. Bits: satisfied=1,
# unresolved auxiliary=2, pivot present=4, primary literal=8.
-> wassat_qg_aux_kind(lits, offs, lens, ci, canonical, assigned, pivot) (i64[] i64[] i64[] i64 i64[] i64[] i64) i64
  kind = 0 ## i64
  j = 0 ## i64
  while j < lens[ci]
    l = lits[offs[ci] + j] ## i64
    v = wassat_qg_abs(l) ## i64
    if canonical[v] != 0
      kind |= 8
    elsif assigned[v] == l
      return 1
    elsif assigned[v] == 0
      kind |= 2
      kind |= 4 if v == pivot
    j += 1
  kind

# Existentially project a private selector tree. A pivot is legal only when
# it occurs in every unresolved non-primary clause. Both assignments are
# visited, so their leaf CNFs form an exact disjunction.
-> wassat_qg_project(head, links, lits, offs, lens, canonical, assigned, pleaves, poffs, plens, plits, depth, m, stop) (i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64[] i64[]) i64
  m[26] += 1
  return 0 if (m[26] & 63) == 1 && wassat_qg_poll(m, stop) != 0
  if depth > 64 || m[26] > 100000
    m[8] = 4
    return 0
  first = 0 - 1 ## i64
  link = head ## i64
  while link != 0
    m[42] += 1
    return 0 if (m[42] & 255) == 0 && wassat_qg_poll(m, stop) != 0
    ci = link - 1 ## i64
    kind = wassat_qg_aux_kind(lits, offs, lens, ci, canonical, assigned, 0) ## i64
    return 1 if kind == 0
    first = ci if kind != 1 && (kind & 2) != 0 && first < 0
    link = links[ci]
  if first < 0
    return 0 if m[27] >= 4096
    pleaves[2 * m[27]] = m[28]
    link = head
    while link != 0
      ci = link - 1
      if wassat_qg_aux_kind(lits, offs, lens, ci, canonical, assigned, 0) != 1
        return 0 if m[28] >= 65536
        poffs[m[28]] = m[29]
        j = 0 ## i64
        while j < lens[ci]
          l = lits[offs[ci] + j] ## i64
          v = wassat_qg_abs(l) ## i64
          if canonical[v] != 0
            return 0 if m[29] >= 1048576
            plits[m[29]] = canonical[v] * (l > 0 ? 1 : -1)
            m[29] += 1
          j += 1
        plens[m[28]] = m[29] - poffs[m[28]]
        m[28] += 1
      link = links[ci]
    pleaves[2 * m[27] + 1] = m[28] - pleaves[2 * m[27]]
    m[27] += 1
    return 1
  pivot = 0 ## i64
  j = 0
  while j < lens[first]
    return 0 if wassat_qg_poll(m, stop) != 0
    v = wassat_qg_abs(lits[offs[first] + j])
    if canonical[v] == 0 && assigned[v] == 0 && (pivot == 0 || v < pivot)
      valid = 1 ## i64
      link = head
      while link != 0
        ci = link - 1
        kind = wassat_qg_aux_kind(lits, offs, lens, ci, canonical, assigned, v)
        if kind != 1 && (kind & 2) != 0 && (kind & 4) == 0
          valid = 0
          break
        link = links[ci]
      pivot = v if valid != 0
    j += 1
  return 0 if pivot == 0
  assigned[pivot] = 0 - pivot
  a = wassat_qg_project(head, links, lits, offs, lens, canonical, assigned, pleaves, poffs, plens, plits, depth + 1, m, stop) ## i64
  assigned[pivot] = pivot
  b = 0 ## i64
  b = wassat_qg_project(head, links, lits, offs, lens, canonical, assigned, pleaves, poffs, plens, plits, depth + 1, m, stop) if a != 0
  assigned[pivot] = 0
  a & b

-> wassat_qg_components(lits, offs, lens, nc, nv, canonical, heads, links, scopes, m) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64[] i64[]) i64
  parent = i64[nv + 1]
  index = i64[nv + 1]
  i = 0 ## i64
  while i <= nv
    parent[i] = i
    i += 1
  ci = 0 ## i64
  while ci < nc
    root = 0 ## i64
    j = 0 ## i64
    while j < lens[ci]
      v = wassat_qg_abs(lits[offs[ci] + j]) ## i64
      if canonical[v] == 0
        if root == 0
          root = v
        else
          parent[wassat_qg_find(parent, v)] = wassat_qg_find(parent, root)
      j += 1
    ci += 1
  ci = 0
  ncomp = 0 ## i64
  one = 1 ## i64
  while ci < nc
    root = 0
    scope = 0 ## i64
    j = 0
    while j < lens[ci]
      v = wassat_qg_abs(lits[offs[ci] + j])
      if canonical[v] == 0
        root = wassat_qg_find(parent, v)
      else
        scope |= one << ((wassat_qg_abs(canonical[v]) - 1) / 7)
      j += 1
    if root != 0
      if index[root] == 0
        return 0 if ncomp >= 128
        index[root] = ncomp + 1
        ncomp += 1
      c = index[root] - 1 ## i64
      links[ci] = heads[c]
      heads[c] = ci + 1
      scopes[c] |= scope
    ci += 1
  m[30] = ncomp
  1

-> wassat_qg_leaf_true(leaf, axis, perm, pleaves, poffs, plens, plits, m) (i64 i64 i64[] i64[] i64[] i64[] i64[] i64[]) i64
  ci = pleaves[2 * leaf] ## i64
  last_clause = ci + pleaves[2 * leaf + 1] ## i64
  while ci < last_clause
    ok = 0 ## i64
    j = 0 ## i64
    while j < plens[ci]
      l = plits[poffs[ci] + j] ## i64
      x = wassat_qg_abs(l) - 1 ## i64
      cell = x / 7 ## i64
      pos = axis == 0 ? cell % 7 : cell / 7 ## i64
      value = perm[pos] == x % 7 ? 1 : -1 ## i64
      m[31] += 1
      if (l > 0 && value == 1) || (l < 0 && value == -1)
        ok = 1
        break
      j += 1
    return 0 if ok == 0
    ci += 1
  1

-> wassat_qg_next_perm(perm) (i64[]) i64
  i = 5 ## i64
  while i >= 0 && perm[i] >= perm[i + 1]
    i -= 1
  return 0 if i < 0
  j = 6 ## i64
  while perm[j] <= perm[i]
    j -= 1
  t = perm[i] ## i64
  perm[i] = perm[j]
  perm[j] = t
  i += 1
  j = 6
  while i < j
    t = perm[i]
    perm[i] = perm[j]
    perm[j] = t
    i += 1
    j -= 1
  1

-> wassat_qg_tables(initial, kinds, compfirst, compcount, pleaves, poffs, plens, plits, tables, tuples, supports, state, m, stop) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  perm = i64[7]
  nt = 0 ## i64
  ci = 0 ## i64
  one = 1 ## i64
  while ci < 14
    return 0 if wassat_qg_poll(m, stop) != 0
    tb = ci * 10 ## i64
    line = m[36] == 0 ? ci : (ci < 7 ? ci + 7 : ci - 7) ## i64
    pos = 0 ## i64
    while pos < 7
      tables[tb + pos] = line < 7 ? line * 7 + pos : pos * 7 + line - 7
      perm[pos] = pos
      pos += 1
    tables[tb + 9] = nt
    n = 0 ## i64
    more = 1 ## i64
    while more != 0
      m[32] += 1
      return 0 if (m[32] & 255) == 0 && wassat_qg_poll(m, stop) != 0
      ok = 1 ## i64
      pos = 0
      while pos < 7
        ok = 0 if (initial[tables[tb + pos]] & (one << perm[pos])) == 0
        pos += 1
      c = 0 ## i64
      while c < m[30] && ok != 0
        if kinds[c] == line
          yes = 0 ## i64
          leaf = compfirst[c] ## i64
          while leaf < compfirst[c] + compcount[c]
            if wassat_qg_leaf_true(leaf, line < 7 ? 0 : 1, perm, pleaves, poffs, plens, plits, m) != 0
              yes = 1
              break
            leaf += 1
          ok = yes
        c += 1
      if ok != 0
        return 0 if n >= 4164
        pos = 0
        while pos < 7
          tuples[nt] = perm[pos]
          nt += 1
          supports[((ci * 7 + pos) * 7 + perm[pos]) * 66 + n / 64] |= one << (n % 64)
          pos += 1
        state[49 + ci * 66 + n / 64] |= one << (n % 64)
        n += 1
      more = wassat_qg_next_perm(perm)
    return 0 if n == 0
    tables[tb + 7] = n
    tables[tb + 8] = (n + 63) / 64
    state[2140 + ci] = tables[tb + 8]
    w = 0 ## i64
    while w < tables[tb + 8]
      state[1216 + ci * 66 + w] = w
      w += 1
    ci += 1
  m[33] = nt / 7
  1

-> wassat_qg_decode_native(source_lits, source_offs, source_lens, nv, nc, state, tables, tuples, supports, eoffs, elens, elits, leaves, groups, canonical, m, stop) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  return 0 if nv < 49 || nv > 10000 || nc < 100 || nc > 100000
  return 0 if source_lits.size > 1048576
  started_ms = clock_ms()
  units = i64[nv + 1]
  lits = i64[source_lits.size]
  offs = i64[nc]
  lens = i64[nc]
  m[40] = 1
  return 0 if wassat_qg_reduce(source_lits, source_offs, source_lens, nc, units, lits, offs, lens, m, stop) == 0
  nc = m[21]
  cap = 1
  while cap < 2 * nc + 1
    cap *= 2
  keys = i64[cap]
  cell = i64[nv + 1]
  sign = i64[nv + 1]
  members = i64[343]
  widths = i64[49]
  m[40] = 2
  return 0 if wassat_qg_cells(lits, offs, lens, nc, nv, keys, cell, sign, members, widths, m, stop) == 0
  initial = i64[49]
  m[40] = 3
  return 0 if wassat_qg_grid(lits, offs, lens, nc, nv, cell, sign, widths, canonical, initial, m, stop) == 0
  heads = i64[128]
  links = i64[nc]
  scopes = i64[128]
  m[40] = 4
  return 0 if wassat_qg_components(lits, offs, lens, nc, nv, canonical, heads, links, scopes, m) == 0
  pleaves = i64[8192]
  poffs = i64[65536]
  plens = i64[65536]
  plits = i64[1048576]
  compfirst = i64[128]
  compcount = i64[128]
  kinds = i64[128]
  assigned = i64[nv + 1]
  c = 0
  m[40] = 5
  while c < m[30]
    compfirst[c] = m[27]
    return 0 if scopes[c] == 0
    return 0 if wassat_qg_project(heads[c], links, lits, offs, lens, canonical, assigned, pleaves, poffs, plens, plits, 0, m, stop) == 0
    compcount[c] = m[27] - compfirst[c]
    return 0 if compcount[c] < 1 || compcount[c] > 64
    row = -1
    col = -1
    scope = scopes[c] ## i64
    j = 0
    while j < 49
      if ((scope >> j) & 1) != 0
        row = j / 7 if row == -1
        col = j % 7 if col == -1
        row = -2 if row != j / 7
        col = -2 if col != j % 7
      j += 1
    kinds[c] = row >= 0 ? row : (col >= 0 ? col + 7 : -1)
    c += 1
  i = 0
  while i < 49
    state[i] = initial[i]
    i += 1
  a = 0
  b = 0
  c = 0
  while c < m[30]
    a += 1 if kinds[c] >= 0 && kinds[c] < 7
    b += 1 if kinds[c] >= 7
    c += 1
  m[36] = b > a ? 1 : 0
  m[40] = 6
  return 0 if wassat_qg_tables(initial, kinds, compfirst, compcount, pleaves, poffs, plens, plits, tables, tuples, supports, state, m, stop) == 0
  positive = i64[49]
  negative = i64[49]
  ec = 0
  en = 0
  ci = 0
  m[40] = 7
  while ci < nc
    j = 0
    while j < 49
      positive[j] = 0
      negative[j] = 0
      j += 1
    pure = 1
    j = 0
    while j < lens[ci]
      l = lits[offs[ci] + j]
      if canonical[wassat_qg_abs(l)] == 0
        pure = 0
        break
      k = canonical[wassat_qg_abs(l)] * (l > 0 ? 1 : -1)
      x = wassat_qg_abs(k) - 1
      if k > 0
        positive[x / 7] |= 1 << (x % 7)
      else
        negative[x / 7] |= 1 << (x % 7)
      j += 1
    if pure != 0
      tautology = 0
      j = 0
      while j < 49
        tautology = 1 if wassat_qg_pop(negative[j]) >= 2 || (positive[j] & negative[j]) != 0 || (positive[j] & initial[j]) == initial[j]
        j += 1
      if tautology == 0
        return 0 if ec >= 8192 || en + lens[ci] > 131072
        eoffs[ec] = en
        elens[ec] = lens[ci]
        j = 0
        while j < lens[ci]
          l = lits[offs[ci] + j]
          elits[en] = canonical[wassat_qg_abs(l)] * (l > 0 ? 1 : -1)
          en += 1
          j += 1
        state[1071 + ec / 64] |= (1 ## i64) << (ec % 64)
        ec += 1
    ci += 1
  m[13] = ec
  leaf = 0
  ng = 0
  c = 0
  while c < m[30]
    if kinds[c] < 0
      return 0 if ng >= 6
      groups[2 * ng] = leaf
      groups[2 * ng + 1] = compcount[c]
      li = 0
      while li < compcount[c]
        source = compfirst[c] + li
        leaves[2 * leaf] = ec
        leaves[2 * leaf + 1] = pleaves[2 * source + 1]
        ci = pleaves[2 * source]
        while ci < pleaves[2 * source] + pleaves[2 * source + 1]
          return 0 if ec >= 16384 || en + plens[ci] > 131072
          eoffs[ec] = en
          elens[ec] = plens[ci]
          j = 0
          while j < plens[ci]
            elits[en] = plits[poffs[ci] + j]
            en += 1
            j += 1
          ec += 1
          ci += 1
        leaf += 1
        state[1199 + ng] |= (1 ## i64) << li
        li += 1
      ng += 1
    c += 1
  m[14] = ng
  m[34] = clock_ms() - started_ms
  m[40] = 8
  1
