# Fast-only coloring certificate from original XOR and domain clauses.
# A checked Mycielski layer raises a chromatic lower bound by one: given a
# k-coloring of the layer, recolor each original vertex in the apex's color
# with its paired shadow's color. Shadows avoid the apex color and have the
# original's neighbors, so this gives a (k-1)-coloring of the preceding graph.
# The base is a checked edge. No graph name, order, or answer table is used.
use cnf
use atomic_stop

# meta: status, XORs, vertices, edges, palette, lower bound, layers, visits,
# stop (1 cancel, 2 deadline, 3 capacity), local clauses, apex candidates,
# neighborhood comparisons, support groups.
-> wassat_myciel_stop(meta, stop, deadline) (i64[] i64[] i64) i64
  return 1 if meta[8] != 0
  if wassat_stop_load(stop) != 0
    meta[8] = 1
  elsif deadline > 0 && clock_ms() >= deadline
    meta[8] = 2
  meta[8] != 0 ? 1 : 0

-> wassat_myciel_visit(meta, stop, deadline) (i64[] i64[] i64) i64
  meta[7] += 1
  meta[8] = 3 if meta[7] > 2000000
  return wassat_myciel_stop(meta, stop, deadline) if (meta[7] & 255) == 0
  meta[8] != 0 ? 1 : 0

-> wassat_myciel_slot(keys, key, meta, stop, deadline) (i64[] i64 i64[] i64[] i64) i64
  h = ((key ^ (key >> 21) ^ (key >> 7)) * 131) & 65535
  while keys[h] != 0 && keys[h] != key
    return 0 if wassat_myciel_visit(meta, stop, deadline) != 0
    h = (h + 1) & 65535
  h

# Recover a graph vertex from its ordered three Boolean coordinates. Shared
# coordinates between different vertices are conservatively declined.
-> wassat_myciel_vertex(a, b, c, owner, position, coords, meta) (i32 i32 i32 i32[] i8[] i32[] i64[]) i64
  return -1 if a >= b || b >= c
  if owner[a] != 0
    v = owner[a] - 1
    return v if coords[3 * v] == a && coords[3 * v + 1] == b && coords[3 * v + 2] == c
    return -1
  return -1 if owner[b] != 0 || owner[c] != 0
  v = meta[2]
  if v >= 512
    meta[8] = 3
    return -1
  coords[3 * v] = a
  coords[3 * v + 1] = b
  coords[3 * v + 2] = c
  owner[a] = v + 1
  owner[b] = v + 1
  owner[c] = v + 1
  position[b] = 1
  position[c] = 2
  meta[2] += 1
  v

# Each stack frame uses one fixed 512-entry slice. Shadow matching compares
# entire neighborhoods, so greedy matching is exact even with duplicate rows:
# candidates are identical-neighborhood equivalence classes.
-> wassat_myciel_fold(adj, levels, shadows, used, depth, n, meta, stop, deadline) (i8[] i32[] i32[] i8[] i64 i64 i64[] i64[] i64) i64
  return 0 if wassat_myciel_stop(meta, stop, deadline) != 0
  base = depth * 512
  if n == 2
    return adj[levels[base] * 512 + levels[base + 1]] != 0 ? 2 : 0
  return 0 if n < 3 || (n & 1) == 0
  if depth >= 9
    meta[8] = 3
    return 0
  half = (n - 1) / 2
  child = base + 512
  ai = 0
  while ai < n
    return 0 if wassat_myciel_visit(meta, stop, deadline) != 0
    apex = levels[base + ai]
    degree = 0
    i = 0
    while i < n
      degree += 1 if adj[apex * 512 + levels[base + i]] != 0
      i += 1
    if degree == half
      meta[10] += 1
      nu = 0
      nv = 0
      i = 0
      while i < n
        v = levels[base + i]
        if v != apex
          if adj[apex * 512 + v] != 0
            shadows[base + nu] = v
            used[base + nu] = 0
            nu += 1
          else
            levels[child + nv] = v
            nv += 1
        i += 1
      return 0 if nu != half || nv != half
      valid = 1
      i = 0
      while i < half && valid != 0
        j = 0
        while j < i && valid != 0
          return 0 if wassat_myciel_visit(meta, stop, deadline) != 0
          valid = 0 if adj[shadows[base + i] * 512 + shadows[base + j]] != 0
          j += 1
        i += 1
      i = 0
      while i < half && valid != 0
        v = levels[child + i]
        found = -1
        j = 0
        while j < half && found < 0
          if used[base + j] == 0
            u = shadows[base + j]
            same = 1
            k = 0
            while k < half && same != 0
              return 0 if wassat_myciel_visit(meta, stop, deadline) != 0
              other = levels[child + k]
              meta[11] += 1
              same = 0 if adj[v * 512 + other] != adj[u * 512 + other]
              k += 1
            found = j if same != 0
          j += 1
        if found < 0
          valid = 0
        else
          used[base + found] = 1
        i += 1
      if valid != 0
        lower = wassat_myciel_fold(adj, levels, shadows, used, depth + 1, half, meta, stop, deadline)
        if lower > 0
          meta[6] += 1
          return lower + 1
      ai += 1
    else
      ai += 1
  0

-> wassat_myciel_check(lits, offs, lens, nv, nc, meta, stop, deadline) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64) i64
  return 0 if nv < 6 || nv > 10000 || nc < 8 || nc > 40000
  return 0 if wassat_myciel_stop(meta, stop, deadline) != 0
  ci = 0
  triples = 0
  while ci < nc
    return 0 if wassat_myciel_visit(meta, stop, deadline) != 0
    n = lens[ci]
    return 0 if n < 1 || n > 3
    triples += 1 if n == 3
    j = 0
    while j < n
      l = lits[offs[ci] + j]
      v = l < 0 ? 0 - l : l
      return 0 if v < 1 || v > nv
      j += 1
    ci += 1
  return 0 if triples < 13
  # A support key is three sorted positive ids in base 16384 (42 bits).
  # A bit per sign pattern records literal presence, not clause counts.
  keys = i64[65536]
  patterns = i32[65536]
  occupied = i32[triples]
  ci = 0
  while ci < nc
    return 0 if wassat_myciel_visit(meta, stop, deadline) != 0
    if lens[ci] == 3
      off = offs[ci]
      a = lits[off]
      b = lits[off + 1]
      c = lits[off + 2]
      av = a < 0 ? 0 - a : a
      bv = b < 0 ? 0 - b : b
      cv = c < 0 ? 0 - c : c
      if av > bv
        t = a; a = b; b = t
        t = av; av = bv; bv = t
      if bv > cv
        t = b; b = c; c = t
        t = bv; bv = cv; cv = t
      if av > bv
        t = a; a = b; b = t
        t = av; av = bv; bv = t
      if av != bv && bv != cv
        key = (av * 16384 + bv) * 16384 + cv
        slot = wassat_myciel_slot(keys, key, meta, stop, deadline)
        return 0 if meta[8] != 0
        if keys[slot] == 0
          occupied[meta[12]] = slot
          meta[12] += 1
        keys[slot] = key
        # TODO(parser): the frozen compiler rejects arithmetic chaining of
        # parenthesized ternaries. Assemble this three-bit sign mask explicitly.
        mask = 0
        mask = mask | 1 if a < 0
        mask = mask | 2 if b < 0
        mask = mask | 4 if c < 0
        patterns[slot] = patterns[slot] | (1 << mask)
    ci += 1
  ga = i32[nv + 1]
  gb = i32[nv + 1]
  parity = i8[nv + 1]
  group_index = 0
  while group_index < meta[12]
    return 0 if wassat_myciel_visit(meta, stop, deadline) != 0
    slot = occupied[group_index]
    bits = patterns[slot]
    even = (bits & 150) == 150
    odd = (bits & 105) == 105
    if even || odd
      # All four forbidden assignments are literally in the original CNF.
      return 0 if even && odd
      key = keys[slot]
      o = key % 16384
      b = (key / 16384) % 16384
      a = key / 268435456
      return 0 if ga[o] != 0
      ga[o] = a
      gb[o] = b
      parity[o] = odd ? 1 : 0
      meta[1] += 1
    group_index += 1
  return 0 if meta[1] < 3
  owner = i32[nv + 1]
  position = i8[nv + 1]
  coords = i32[1536]
  adj = i8[512 * 512]
  relation = i8[512 * 512]
  left = i32[3]
  right = i32[3]
  pol = i8[3]
  ci = 0
  while ci < nc
    return 0 if wassat_myciel_visit(meta, stop, deadline) != 0
    if lens[ci] == 3
      good = 1
      j = 0
      while j < 3 && good != 0
        l = lits[offs[ci] + j]
        o = l < 0 ? 0 - l : l
        if ga[o] == 0
          good = 0
        else
          left[j] = ga[o]
          right[j] = gb[o]
          pol[j] = parity[o] ^ (l < 0 ? 1 : 0)
        j += 1
      if good != 0
        j = 1
        while j < 3
          a = left[j]; b = right[j]; p = pol[j]
          k = j
          while k > 0 && left[k - 1] > a
            left[k] = left[k - 1]
            right[k] = right[k - 1]
            pol[k] = pol[k - 1]
            k -= 1
          left[k] = a; right[k] = b; pol[k] = p
          j += 1
        # Coordinate order must agree on both endpoints. Unsupported
        # interleaved layouts are ignored, never guessed into graph edges.
        if left[0] < left[1] && left[1] < left[2] && right[0] < right[1] && right[1] < right[2]
          u = wassat_myciel_vertex(left[0], left[1], left[2], owner, position, coords, meta)
          return 0 if u < 0
          v = wassat_myciel_vertex(right[0], right[1], right[2], owner, position, coords, meta)
          return 0 if v < 0 || u == v
          mask = pol[0] + 2 * pol[1] + 4 * pol[2]
          at = u * 512 + v
          return 0 if adj[at] != 0 && relation[at] != mask
          meta[3] += 1 if adj[at] == 0
          adj[at] = 1
          adj[v * 512 + u] = 1
          relation[at] = mask
          relation[v * 512 + u] = mask
    ci += 1
  nb = meta[2]
  return 0 if nb < 2
  # Necessary size check only; acceptance still requires every graph edge.
  # An inverse layer removes an apex and halves the remaining vertices.
  size = nb
  while size > 2 && (size & 1) != 0
    size = (size - 1) / 2
  return 0 if size != 2
  # Signed XOR edges transport a consistent coordinate complement for each
  # vertex. Requiring cycle consistency gives one common eight-label palette.
  flips = i8[512]
  seen = i8[512]
  queue = i32[512]
  root = 0
  while root < nb
    if seen[root] == 0
      seen[root] = 1
      queue[0] = root
      head = 0
      tail = 1
      while head < tail
        u = queue[head]
        v = 0
        while v < nb
          return 0 if wassat_myciel_visit(meta, stop, deadline) != 0
          if adj[u * 512 + v] != 0
            f = flips[u] ^ relation[u * 512 + v]
            if seen[v] == 0
              seen[v] = 1
              flips[v] = f
              queue[tail] = v
              tail += 1
            elsif flips[v] != f
              return 0
          v += 1
        head += 1
    root += 1
  allowed = i32[nb]
  v = 0
  while v < nb
    allowed[v] = 255
    v += 1
  ci = 0
  while ci < nc
    return 0 if wassat_myciel_visit(meta, stop, deadline) != 0
    n = lens[ci]
    off = offs[ci]
    l = lits[off]
    x = l < 0 ? 0 - l : l
    group = owner[x]
    local = group != 0
    j = 1
    while j < n && local
      l = lits[off + j]
      x = l < 0 ? 0 - l : l
      local = false if owner[x] != group
      j += 1
    if local
      meta[9] += 1
      v = group - 1
      color = 0
      while color < 8
        raw = color ^ flips[v]
        satisfied = 0
        j = 0
        while j < n
          l = lits[off + j]
          x = l < 0 ? 0 - l : l
          bit = (raw >> position[x]) & 1
          satisfied = 1 if (l > 0 && bit == 1) || (l < 0 && bit == 0)
          j += 1
        allowed[v] = allowed[v] & (255 ^ (1 << color)) if satisfied == 0
        color += 1
    ci += 1
  palette = 0
  v = 0
  while v < nb
    return 0 if allowed[v] == 0
    palette = palette | allowed[v]
    v += 1
  color = 0
  while color < 8
    meta[4] += 1 if (palette & (1 << color)) != 0
    color += 1
  levels = i32[5120]
  shadows = i32[5120]
  used = i8[5120]
  v = 0
  while v < nb
    levels[v] = v
    v += 1
  lower = wassat_myciel_fold(adj, levels, shadows, used, 0, nb, meta, stop, deadline)
  meta[5] = lower
  return 0 if lower <= meta[4] || wassat_myciel_stop(meta, stop, deadline) != 0
  meta[0] = -1
  -1

-> wassat_mycielski_refute(formula, stop, deadline = 0)
  meta = i64[13]
  if formula != nil
    z = wassat_myciel_check(formula["flat_lits"], formula["flat_offs"], formula["flat_lens"], formula["nvars"], formula["flat_ncl"], meta, stop, deadline)
  meta

-> wassat_mycielski_unsat?(formula)
  return false if env("WASSAT_MYCIELSKI") == "0"
  return false if formula["nvars"] < 6 || formula["nvars"] > 10000 || formula["flat_ncl"] > 40000
  started = clock_ms()
  m = wassat_mycielski_refute(formula, i64[1], started + 50)
  if env("WASSAT_PROFILE") == "1"
    wassat_prof_note("mycielski status=[m[0]] xors=[m[1]] vertices=[m[2]] edges=[m[3]] palette=[m[4]] lower=[m[5]] layers=[m[6]] visits=[m[7]] stop=[m[8]] local_clauses=[m[9]] candidates=[m[10]] comparisons=[m[11]] supports=[m[12]] ms=[clock_ms() - started]")
  m[0] == -1
