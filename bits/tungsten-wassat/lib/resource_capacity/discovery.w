-> wassat_resource_root(parent, v) (i32[] i64) i64
  while parent[v] != v
    parent[v] = parent[parent[v]]; v = parent[v]
  v

-> wassat_resource_union(parent, a, b) (i32[] i64 i64) i64
  a = wassat_resource_root(parent, a); b = wassat_resource_root(parent, b)
  if a < b
    parent[b] = a
  elsif b < a
    parent[a] = b
  0

-> wassat_resource_candidates(lits, offs, lens, nc, group, cid, m, stop, deadline) (i64[] i64[] i64[] i64 i32[] i32[] i64[] i64[] i64) i64
  ci = 0; count = 0
  while ci < nc
    return 0 if (ci & 1023) == 0 && wassat_resource_poll(m, stop, deadline) != 0
    n = lens[ci]
    if n >= 2 && n <= 64
      o = offs[ci]; j = 0; yes = 1
      while j < n && yes != 0
        v = lits[o + j]
        if v <= 0
          yes = 0
        elsif group[v] != 0
          yes = 0
        j += 1
      if yes != 0
        j = 0
        while j < n
          v = lits[o + j]
          if cid[v] == 0
            count += 1; return 0 if count > 50000
            cid[v] = count
          j += 1
    ci += 1
  m[3] = count
  1

-> wassat_resource_terms(lits, offs, lens, nc, group, slot, cid, owner, head1, head2, forbidden, m, stop, deadline) (i64[] i64[] i64[] i64 i32[] i32[] i32[] i32[] i32[] i32[] i8[] i64[] i64[] i64) i64
  ci = 0; ns = m[1]
  while ci < nc
    return 0 if (ci & 1023) == 0 && wassat_resource_poll(m, stop, deadline) != 0
    n = lens[ci]
    if n == 2 || n == 3
      o = offs[ci]; a = 0; b = 0; head = 0; bad = 0; j = 0
      while j < n
        x = lits[o + j]
        if x < 0
          if a == 0
            a = 0 - x
          elsif b == 0
            b = 0 - x
          else
            bad = 1
        else
          head = x
        j += 1
      if a > 0 && b > 0 && bad == 0 && (n == 2 || head > 0)
        tv = 0; ch = 0
        if group[a] > 0 && cid[b] > 0
          tv = a; ch = b
        elsif group[b] > 0 && cid[a] > 0
          tv = b; ch = a
        if tv > 0
          id = cid[ch] - 1; course = group[tv]
          if owner[id] == 0
            owner[id] = course
          elsif owner[id] != course
            owner[id] = -1
          pair = id * ns + slot[tv]
          if n == 2
            forbidden[pair] = 1
          elsif group[head] == 0 && cid[head] == 0
            if head1[pair] == 0
              head1[pair] = head; m[4] += 1
            elsif head1[pair] != head && head2[pair] == 0
              head2[pair] = head
    ci += 1
  1

-> wassat_resource_domains(lits, offs, lens, nc, cid, owner, head1, forbidden, active, domains, m, stop, deadline) (i64[] i64[] i64[] i64 i32[] i32[] i32[] i8[] i8[] i32[] i64[] i64[] i64) i64
  ci = 0; nd = 0; ns = m[1]
  while ci < nc
    return 0 if (ci & 1023) == 0 && wassat_resource_poll(m, stop, deadline) != 0
    n = lens[ci]
    if n >= 2 && n <= 64
      o = offs[ci]; j = 0; course = 0; yes = 1
      while j < n && yes != 0
        v = lits[o + j]
        if v <= 0
          yes = 0
        elsif cid[v] <= 0
          yes = 0
        else
          id = cid[v] - 1
          if owner[id] <= 0 || (course != 0 && owner[id] != course)
            yes = 0
          else
            course = owner[id]; s = 0
            while s < ns
              pair = id * ns + s
              yes = 0 if head1[pair] == 0 && forbidden[pair] == 0
              s += 1
        j += 1
      if yes != 0
        return 0 if nd >= 8192
        domains[nd] = ci; nd += 1; j = 0
        while j < n
          active[cid[lits[o + j]] - 1] = 1; j += 1
    ci += 1
  m[5] = nd
  nd > 0 ? 1 : 0

-> wassat_resource_group_candidates(lits, offs, lens, nv, nc, group, cid, head1, head2, active, res, m, stop, deadline) (i64[] i64[] i64[] i64 i64 i32[] i32[] i32[] i32[] i8[] i32[] i64[] i64[] i64) i64
  parent = i32[nv + 1]; first = i32[nv + 1]
  v = 0
  while v <= nv
    parent[v] = v; v += 1
  ci = 0
  while ci < nc
    return 0 if (ci & 1023) == 0 && wassat_resource_poll(m, stop, deadline) != 0
    if lens[ci] == 2
      o = offs[ci]; a = wassat_resource_abs(lits[o]); b = wassat_resource_abs(lits[o + 1])
      if group[a] == 0 && cid[a] == 0 && group[b] == 0 && cid[b] == 0
        z = wassat_resource_union(parent, a, b)
    ci += 1
  count = m[3]; ns = m[1]; i = 0
  while i < count
    res[i] = i; s = 0
    if active[i] != 0
      while s < ns
        pair = i * ns + s
        if head1[pair] > 0 && head2[pair] > 0
          z = wassat_resource_union(parent, (head1[pair] ## i64), (head2[pair] ## i64))
        s += 1
    i += 1
  i = 0
  while i < count
    return 0 if (i & 255) == 0 && wassat_resource_poll(m, stop, deadline) != 0
    if active[i] != 0
      s = 0
      while s < ns
        pair = i * ns + s
        if head1[pair] > 0
          root = wassat_resource_root(parent, (head1[pair] ## i64))
          if first[root] == 0
            first[root] = i + 1
          else
            z = wassat_resource_union(res, i, first[root] - 1)
        s += 1
    i += 1
  1

-> wassat_resource_component(lits, offs, lens, cid, owner, minima, active, domains, res, witness, m, stop, deadline) (i64[] i64[] i64[] i32[] i32[] i32[] i8[] i32[] i32[] i32[] i64[] i64[] i64) i64
  count = m[3]; nd = m[5]; ns = m[1]; comp = i32[count]
  loads = i32[count]; capacities = i32[count]; resources = i32[count]
  i = 0
  while i < count
    comp[i] = wassat_resource_root(res, i); i += 1
  d = 0
  while d < nd
    ci = domains[d]; o = offs[ci]; first = cid[lits[o]] - 1; j = 1
    while j < lens[ci]
      z = wassat_resource_union(comp, first, cid[lits[o + j]] - 1); j += 1
    d += 1
  i = 0
  while i < count
    if active[i] != 0 && res[i] == i
      root = wassat_resource_root(comp, i); capacities[root] += ns; resources[root] += 1; m[6] += 1
    i += 1
  keys = i64[32768]; dids = i32[32768]; d = 0
  while d < nd
    return 0 if (d & 255) == 0 && wassat_resource_poll(m, stop, deadline) != 0
    ci = domains[d]; ch = cid[lits[offs[ci]]] - 1; course = owner[ch] - 1
    root = wassat_resource_root(comp, ch); key = root * 4096 + course + 1
    bucket = (key * 1103515245) & 32767
    while keys[bucket] != 0 && keys[bucket] != key
      bucket = (bucket + 1) & 32767
    if keys[bucket] == 0
      keys[bucket] = key; dids[bucket] = d + 1; loads[root] += minima[course]
    d += 1
  best = -1; gap = 0; i = 0
  while i < count
    if loads[i] - capacities[i] > gap && capacities[i] > 0
      best = i; gap = loads[i] - capacities[i]
    i += 1
  return 0 if best < 0
  i = 0; n = 0
  while i < 32768
    if dids[i] > 0 && (keys[i] - 1) / 4096 == best
      witness[n] = domains[dids[i] - 1]; n += 1
    i += 1
  m[7] = n; m[8] = loads[best]; m[9] = capacities[best]; m[10] = resources[best]
  n > 0 ? 1 : 0

-> wassat_resource_discover(formula, m, stop, deadline = 0)
  r = wassat_resource_decode(formula, m, stop, deadline)
  return nil if r == nil
  nv = formula["nvars"]; nc = formula["flat_ncl"]
  lits = formula["flat_lits"]; offs = formula["flat_offs"]; lens = formula["flat_lens"]
  group = r["group"]; slot = r["slot"]; minima = r["minima"]
  cid = i32[nv + 1]
  return nil if wassat_resource_candidates(lits, offs, lens, nc, group, cid, m, stop, deadline) != 1
  count = m[3]; cells = count * m[1]
  return nil if count == 0 || cells > 20000000
  owner = i32[count]; head1 = i32[cells]; head2 = i32[cells]; forbidden = i8[cells]
  return nil if wassat_resource_terms(lits, offs, lens, nc, group, slot, cid, owner, head1, head2, forbidden, m, stop, deadline) != 1
  active = i8[count]; domains = i32[8192]
  return nil if wassat_resource_domains(lits, offs, lens, nc, cid, owner, head1, forbidden, active, domains, m, stop, deadline) != 1
  res = i32[count]
  return nil if wassat_resource_group_candidates(lits, offs, lens, nv, nc, group, cid, head1, head2, active, res, m, stop, deadline) != 1
  witness = i32[4096]
  return nil if wassat_resource_component(lits, offs, lens, cid, owner, minima, active, domains, res, witness, m, stop, deadline) != 1
  r["cid"] = cid; r["owner"] = owner; r["head1"] = head1; r["head2"] = head2; r["forbidden"] = forbidden
  r["res"] = res; r["witness"] = witness
  r
