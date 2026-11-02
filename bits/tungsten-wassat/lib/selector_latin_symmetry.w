# Check element-renaming automorphisms by exact finite-set equality before restricting search.
use selector_latin_decode

-> wassat_qg_sort_unique(a, n) (i64[] i64) i64
  i = 1 ## i64
  while i < n
    x = a[i] ## i64
    j = i ## i64
    while j > 0 && a[j - 1] > x
      a[j] = a[j - 1]
      j -= 1
    a[j] = x
    i += 1
  used = 0 ## i64
  i = 0
  while i < n
    if used == 0 || a[i] != a[used - 1]
      a[used] = a[i]
      used += 1
    i += 1
  used

# Shared interner for sorted literal clauses and sorted clause-ID leaves.
# IDs carry a kind tag, and collisions always compare the entire sequence.
-> wassat_qg_intern(a, n, kind, insert, keys, data, starts, sizes, meta) (i64[] i64 i64 i64 i64[] i64[] i64[] i64[] i64[]) i64
  n = wassat_qg_sort_unique(a, n)
  hash = kind ## i64
  i = 0 ## i64
  while i < n
    hash = ((hash * 31) + a[i] + 2048) & 1073741823
    i += 1
  slot = hash & (keys.size - 1) ## i64
  probes = 0 ## i64
  while keys[slot] != 0
    id = keys[slot] ## i64
    if sizes[id] == n && data[starts[id]] == kind
      same = 1 ## i64
      i = 0
      while i < n
        same = 0 if data[starts[id] + 1 + i] != a[i]
        i += 1
      return id if same != 0
    slot = (slot + 1) & (keys.size - 1)
    probes += 1
    return 0 if probes >= keys.size
  return 0 if insert == 0 || meta[0] + 1 >= starts.size || meta[1] + n + 1 > data.size
  id = meta[0] + 1
  meta[0] = id
  starts[id] = meta[1]
  sizes[id] = n
  data[meta[1]] = kind
  i = 0
  while i < n
    data[meta[1] + i + 1] = a[i]
    i += 1
  meta[1] += n + 1
  keys[slot] = id
  id

-> wassat_qg_sorted_contains(a, n, value) (i64[] i64 i64) i64
  lo = 0 ## i64
  hi = n ## i64
  while lo < hi
    mid = (lo + hi) / 2 ## i64
    if a[mid] < value
      lo = mid + 1
    else
      hi = mid
  lo < n && a[lo] == value ? 1 : 0

-> wassat_qg_canonical_lit(lit, cols, symbols) (i64 i64[] i64[]) i64
  x = wassat_qg_abs(lit) - 1 ## i64
  v = (x / 49 * 7 + cols[(x / 7) % 7]) * 7 + symbols[x % 7] + 1 ## i64
  lit > 0 ? v : 0 - v

-> wassat_qg_swap(x, a, b) (i64 i64 i64) i64
  x == a ? b : (x == b ? a : x)

-> wassat_qg_swap_lit(lit, a, b) (i64 i64 i64) i64
  x = wassat_qg_abs(lit) - 1 ## i64
  v = (wassat_qg_swap(x / 49, a, b) * 7 + wassat_qg_swap((x / 7) % 7, a, b)) * 7 + wassat_qg_swap(x % 7, a, b) + 1 ## i64
  lit > 0 ? v : 0 - v

-> wassat_qg_subset(a, abase, na, b, bbase, nb) (i64[] i64 i64 i64[] i64 i64) i64
  i = 0 ## i64
  j = 0 ## i64
  while i < na
    while j < nb && b[bbase + j] < a[abase + i]
      j += 1
    return 0 if j == nb || b[bbase + j] != a[abase + i]
    i += 1
  1

# Distribute a small leaf CNF into minimal consistent conjunctions. Terms
# are bounded to 128 x 16 slots. Overflow declines symmetry, never truncates.
-> wassat_qg_expand_leaf(ids, n, data, starts, sizes, terms, pending, counts, tmp, m) (i64[] i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  count = 1 ## i64
  terms[0] = 0
  ci = 0 ## i64
  while ci < n
    id = ids[ci] ## i64
    nc = 0 ## i64
    t = 0 ## i64
    while t < count
      j = 0 ## i64
      while j < sizes[id]
        lit = data[starts[id] + 1 + j] ## i64
        nt = terms[t * 16] ## i64
        return 0 if nt >= 15
        k = 0 ## i64
        valid = 1 ## i64
        while k < nt
          v = terms[t * 16 + 1 + k] ## i64
          tmp[k] = v
          valid = 0 if v == 0 - lit || (v > 0 && lit > 0 && v != lit && (v - 1) / 7 == (lit - 1) / 7)
          k += 1
        tmp[nt] = lit
        nt = wassat_qg_sort_unique(tmp, nt + 1)
        if valid != 0
          k = 0
          while k < nc
            valid = 0 if wassat_qg_subset(pending, k * 16 + 1, pending[k * 16], tmp, 0, nt) != 0
            k += 1
          if valid != 0
            k = 0
            while k < nc
              if wassat_qg_subset(tmp, 0, nt, pending, k * 16 + 1, pending[k * 16]) != 0
                nc -= 1
                z = 0 ## i64
                while z < 16
                  pending[k * 16 + z] = pending[nc * 16 + z]
                  z += 1
              else
                k += 1
            return 0 if nc >= 128
            pending[nc * 16] = nt
            k = 0
            while k < nt
              pending[nc * 16 + k + 1] = tmp[k]
              k += 1
            nc += 1
        j += 1
      t += 1
    k = 0
    while k < nc * 16
      terms[k] = pending[k]
      k += 1
    count = nc
    ci += 1
  counts[0] = count
  m[47] += count
  1

# A tuple has a base-eight permutation code and an axis/line tag. Exact
# integer keys fit in 26 bits; no probabilistic equality is involved.
-> wassat_qg_code_slot(key, keys) (i64 i64[]) i64
  slot = (key * 73856093) & (keys.size - 1) ## i64
  while keys[slot] != 0 && keys[slot] != key
    slot = (slot + 1) & (keys.size - 1)
  slot

-> wassat_qg_swap_code(key, a, b) (i64 i64 i64) i64
  key -= 1
  tag = key >> 21 ## i64
  code = key & 2097151 ## i64
  result = (tag / 7 * 7 + wassat_qg_swap(tag % 7, a, b)) << 21 ## i64
  p = 0 ## i64
  while p < 7
    result |= wassat_qg_swap((code >> (p * 3)) & 7, a, b) << (wassat_qg_swap(p, a, b) * 3)
    p += 1
  result + 1

-> wassat_qg_symmetry(state, tables, tuples, offs, lens, lits, leaves, groups, m, stop) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  started_ms = clock_ms()
  m[44] = 1
  return 0 if wassat_qg_poll(m, stop) != 0
  cols = i64[7]; symbols = i64[7]; seen = i64[21]
  r = 0 ## i64
  while r < 7
    c = 0 ## i64
    while c < 7
      mask = state[r * 7 + c] ## i64
      if mask != 127
        return 0 if wassat_qg_pop(mask) != 6 || seen[r] != 0 || seen[7 + c] != 0
        v = wassat_qg_ctz(127 ^ mask) ## i64
        return 0 if seen[14 + v] != 0
        seen[r] = 1; seen[7 + c] = 1; seen[14 + v] = 1
        cols[c] = r; symbols[v] = r
      c += 1
    return 0 if seen[r] == 0
    r += 1
  # All original domain restrictions become Q(x,x) != x, hence invariant.
  keys = i64[65536]; data = i64[262144]; starts = i64[32768]; sizes = i64[32768]; meta = i64[2]
  buf = i64[128]; ids = i64[128]; primary = i64[8192]
  gl = i64[6 * 256]; gn = i64[6]
  terms = i64[2048]; pending = i64[2048]; counts = i64[1]; tmp = i64[128]
  ci = 0
  while ci < m[13]
    return 0 if lens[ci] > 128 || ((ci & 255) == 0 && wassat_qg_poll(m, stop) != 0)
    j = 0 ## i64
    while j < lens[ci]
      buf[j] = wassat_qg_canonical_lit(lits[offs[ci] + j], cols, symbols)
      j += 1
    id = wassat_qg_intern(buf, lens[ci], 1, 1, keys, data, starts, sizes, meta) ## i64
    return 0 if id == 0
    primary[ci] = id
    ci += 1
  np = wassat_qg_sort_unique(primary, m[13]) ## i64
  m[44] = 2
  gi = 0 ## i64
  while gi < m[14]
    return 0 if wassat_qg_poll(m, stop) != 0
    li = 0 ## i64
    while li < groups[gi * 2 + 1]
      leaf = groups[gi * 2] + li ## i64
      n = leaves[leaf * 2 + 1] ## i64
      return 0 if n > 128
      i = 0 ## i64
      while i < n
        ci = leaves[leaf * 2] + i
        return 0 if lens[ci] > 128
        j = 0
        while j < lens[ci]
          buf[j] = wassat_qg_canonical_lit(lits[offs[ci] + j], cols, symbols)
          j += 1
        id = wassat_qg_intern(buf, lens[ci], 1, 1, keys, data, starts, sizes, meta)
        return 0 if id == 0
        ids[i] = id
        i += 1
      n = wassat_qg_sort_unique(ids, n)
      if n <= 10
        return 0 if wassat_qg_expand_leaf(ids, n, data, starts, sizes, terms, pending, counts, tmp, m) == 0
        t = 0 ## i64
        while t < counts[0]
          i = 0
          while i < terms[t * 16]
            buf[0] = terms[t * 16 + 1 + i]
            id = wassat_qg_intern(buf, 1, 1, 1, keys, data, starts, sizes, meta)
            return 0 if id == 0
            ids[i] = id
            i += 1
          id = wassat_qg_intern(ids, terms[t * 16], 2, 1, keys, data, starts, sizes, meta)
          return 0 if id == 0 || gn[gi] >= 256
          gl[gi * 256 + gn[gi]] = id
          gn[gi] += 1
          t += 1
      else
        id = wassat_qg_intern(ids, n, 2, 1, keys, data, starts, sizes, meta)
        return 0 if id == 0 || gn[gi] >= 256
        gl[gi * 256 + gn[gi]] = id
        gn[gi] += 1
      li += 1
    gi += 1
  # Store the canonical tables and map each root tuple code back to its index.
  tk = i64[131072]; rootindex = i64[131072]; rootcodes = i64[4164]
  tablecodes = i64[14 * 4164]
  ncode = 0 ## i64
  ci = 0
  rootfixed = 0 ## i64
  while ci < 14
    axis = tables[ci * 10] / 7 == tables[ci * 10 + 1] / 7 ? 0 : 1 ## i64
    line = axis == 0 ? tables[ci * 10] / 7 : cols[tables[ci * 10] % 7] ## i64
    rootfixed = line if ci == 0
    k = 0 ## i64
    while k < tables[ci * 10 + 7]
      code = (axis * 7 + line) << 21 ## i64
      p = 0 ## i64
      while p < 7
        cell = tables[ci * 10 + p] ## i64
        pos = axis == 0 ? cols[cell % 7] : cell / 7 ## i64
        code |= symbols[tuples[tables[ci * 10 + 9] + k * 7 + p]] << (pos * 3)
        p += 1
      code += 1
      slot = wassat_qg_code_slot(code, tk) ## i64
      tk[slot] = code
      tablecodes[ncode] = code
      ncode += 1
      if ci == 0
        rootindex[slot] = k + 1
        rootcodes[k] = code
      k += 1
    ci += 1
  others = i64[6]
  i = 0
  r = 0
  while r < 7
    if r != rootfixed
      others[i] = r
      i += 1
    r += 1
  mapped = i64[32768]
  gen = 0 ## i64
  m[44] = 3
  while gen < 5
    return 0 if wassat_qg_poll(m, stop) != 0
    a = others[gen] ## i64
    b = others[gen + 1] ## i64
    # First transform every referenced clause exactly.
    id = 1
    while id <= meta[0]
      return 0 if (id & 255) == 0 && wassat_qg_poll(m, stop) != 0
      mapped[id] = 0
      if data[starts[id]] == 1
        i = 0
        while i < sizes[id]
          buf[i] = wassat_qg_swap_lit(data[starts[id] + i + 1], a, b)
          i += 1
        mapped[id] = wassat_qg_intern(buf, sizes[id], 1, 0, keys, data, starts, sizes, meta)
      id += 1
    i = 0
    while i < np
      target = mapped[primary[i]] ## i64
      return 0 if target == 0 || wassat_qg_sorted_contains(primary, np, target) == 0
      i += 1
    gi = 0
    while gi < m[14]
      li = 0
      while li < gn[gi]
        id = gl[gi * 256 + li]
        i = 0
        while i < sizes[id]
          target = mapped[data[starts[id] + 1 + i]]
          return 0 if target == 0
          buf[i] = target
          i += 1
        target = wassat_qg_intern(buf, sizes[id], 2, 0, keys, data, starts, sizes, meta)
        j = 0
        while j < gn[gi] && gl[gi * 256 + j] != target
          j += 1
        return 0 if target == 0 || j == gn[gi]
        li += 1
      gi += 1
    i = 0
    while i < ncode
      return 0 if (i & 255) == 0 && wassat_qg_poll(m, stop) != 0
      target = wassat_qg_swap_code(tablecodes[i], a, b)
      return 0 if tk[wassat_qg_code_slot(target, tk)] != target
      m[49] += 1
      i += 1
    gen += 1
  # The generators preserve the complete relaxation. Traverse their exact
  # root-tuple orbits, retaining one representative from each component.
  marked = i64[4164]; queue = i64[4164]; representatives = i64[66]
  k = 0
  while k < tables[7]
    if marked[k] == 0
      representatives[k / 64] |= (1 ## i64) << (k % 64)
      m[46] += 1
      head = 0 ## i64
      tail = 1 ## i64
      queue[0] = k
      marked[k] = 1
      while head < tail
        gen = 0
        while gen < 5
          target = wassat_qg_swap_code(rootcodes[queue[head]], others[gen], others[gen + 1])
          slot = wassat_qg_code_slot(target, tk)
          return 0 if tk[slot] != target || rootindex[slot] == 0
          index = rootindex[slot] - 1 ## i64
          if marked[index] == 0
            return 0 if tail >= 4164
            marked[index] = 1
            queue[tail] = index
            tail += 1
          gen += 1
        head += 1
    k += 1
  return 0 if wassat_qg_poll(m, stop) != 0
  m[45] = tables[7]
  i = 0
  while i < 66
    state[49 + i] = representatives[i]
    i += 1
  m[43] = clock_ms() - started_ms
  m[44] = 4
  1
