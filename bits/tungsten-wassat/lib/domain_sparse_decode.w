# Disjoint positive domains with negative binary exclusions. Selecting one
# value per domain preserves every positive row, including optional AMO-free
# encodings. Unsupported clauses or contradictory units simply decline.
use atomic_stop

-> wassat_sparse_domain_poll(m, stop, deadline) (i64[] i64[] i64) i64
  m[12] += 1
  if wassat_stop_load(stop) != 0
    m[2] = 1
  elsif deadline > 0 && clock_ms() >= deadline
    m[2] = 2
  m[2] != 0 ? 1 : 0

-> wassat_sparse_domain_prepare(f,m,stop,deadline)
  nv = f["nvars"]; nc = f["flat_ncl"]
  lits = f["flat_lits"] ## i64[]
  offs = f["flat_offs"] ## i64[]
  lens = f["flat_lens"] ## i64[]
  return nil if nv < 1 || nv > 100000 || nc < 1 || nc > 4000000
  owner = i32[nv+1]; stamp = i32[nv+1]; values = i32[nv]; first = i32[nv+1]
  return nil if offs.size < nc || lens.size < nc
  nb = 0; at = 0; ci = 0
  while ci < nc
    return nil if (ci & 1023) == 0 && wassat_sparse_domain_poll(m,stop,deadline) != 0
    width = lens[ci]; off = offs[ci]; j = 0; positive = true
    return nil if width < 1 || width > 32 || off < 0 || off > lits.size || width > lits.size-off
    while j < width
      lit = lits[off+j]
      return nil if lit == 0 || lit > nv || lit < -nv
      positive = false if lit < 0
      j += 1
    if positive && width >= 2
      previous = owner[lits[off]]; j = 0
      while j < width
        v = lits[off+j]
        return nil if stamp[v] == ci+1 || owner[v] != previous
        stamp[v] = ci+1; j += 1
      if previous != 0
        return nil if first[previous]-first[previous-1] != width
      else
        first[nb] = at; j = 0
        while j < width
          v = lits[off+j]; owner[v] = nb+1; values[at] = v; at += 1; j += 1
        nb += 1; first[nb] = at
    elsif !positive && !(width == 1 || (width == 2 && lits[off] < 0 && lits[off+1] < 0))
      return nil
    m[4] += 1; m[5] += width; ci += 1
  ci = 0
  while ci < nc
    return nil if (ci & 1023) == 0 && wassat_sparse_domain_poll(m,stop,deadline) != 0
    if lens[ci] == 1 && lits[offs[ci]] > 0
      v = lits[offs[ci]]
      if owner[v] == 0
        first[nb] = at; owner[v] = nb+1; values[at] = v; at += 1; nb += 1; first[nb] = at
    ci += 1
  return nil if at != nv || nb < 2
  allowed = i8[nv+1]; forced = i32[nb]; heads = i32[nv+2]; ne = 0
  v = 1
  while v <= nv
    allowed[v] = 1; v += 1
  ci = 0
  while ci < nc
    return nil if (ci & 1023) == 0 && wassat_sparse_domain_poll(m,stop,deadline) != 0
    off = offs[ci]
    if lens[ci] == 1
      lit = lits[off]; v = lit < 0 ? -lit : lit
      if lit < 0
        allowed[v] = 0
      else
        b = owner[v]-1
        return nil if forced[b] != 0 && forced[b] != v
        forced[b] = v
    elsif lens[ci] == 2 && lits[off] < 0
      u = -lits[off]; v = -lits[off+1]
      if u == v
        allowed[u] = 0
      elsif owner[u] != owner[v]
        heads[u+1] += 1; heads[v+1] += 1; ne += 1
    ci += 1
  b = 0
  while b < nb
    at = first[b]
    while at < first[b+1]
      v = values[at]
      allowed[v] = 0 if forced[b] != 0 && forced[b] != v
      at += 1
    b += 1
  v = 1
  while v <= nv+1
    heads[v] += heads[v-1]; v += 1
  edges = i32[2*ne]; ids = i32[2*ne]; cursor = i32[nv+1]
  v = 1
  while v <= nv
    cursor[v] = heads[v]; v += 1
  ci = 0; e = 0
  while ci < nc
    return nil if (ci & 1023) == 0 && wassat_sparse_domain_poll(m,stop,deadline) != 0
    off = offs[ci]
    if lens[ci] == 2 && lits[off] < 0
      u = -lits[off]; v = -lits[off+1]
      if owner[u] != owner[v]
        p = cursor[u]; edges[p] = v; ids[p] = e; cursor[u] += 1
        p = cursor[v]; edges[p] = u; ids[p] = e; cursor[v] += 1; e += 1
    ci += 1
  remaining = i32[nb]; queue = i32[nb]; qn = 0; qi = 0; b = 0
  while b < nb
    at = first[b]
    while at < first[b+1]
      remaining[b] += allowed[values[at]]; at += 1
    return nil if remaining[b] == 0
    if remaining[b] == 1
      queue[qn] = b; qn += 1
    b += 1
  while qi < qn
    return nil if wassat_sparse_domain_poll(m,stop,deadline) != 0
    b = queue[qi]; qi += 1; at = first[b]
    while allowed[values[at]] == 0
      at += 1
    u = values[at]; p = heads[u]
    while p < heads[u+1]
      return nil if (p & 16383) == 0 && wassat_sparse_domain_poll(m,stop,deadline) != 0
      v = edges[p]; c = owner[v]-1
      if allowed[v] != 0
        allowed[v] = 0; remaining[c] -= 1; m[24] += 1
        return nil if remaining[c] == 0
        if remaining[c] == 1
          queue[qn] = c; qn += 1
      p += 1
  m[1] = 1; m[3] = nb; m[25] = ne
  { "owner": owner, "values": values, "first": first, "allowed": allowed,
    "heads": heads, "edges": edges, "ids": ids, "nv": nv, "nb": nb, "ne": ne }
