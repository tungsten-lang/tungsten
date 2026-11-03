-> wassat_resource_binary_graph(lits, offs, lens, nv, nc, ph, nh, m, stop, deadline) (i64[] i64[] i64[] i64 i64 i32[] i32[] i64[] i64[] i64) i64
  ci = 0
  while ci < nc
    return 0 if (ci & 1023) == 0 && wassat_resource_poll(m, stop, deadline) != 0
    if lens[ci] == 2
      o = offs[ci]; a = lits[o]; b = lits[o + 1]
      if a < 0 && b > 0
        ph[1 - a] += 1
      elsif b < 0 && a > 0
        ph[1 - b] += 1
      elsif a < 0 && b < 0
        nh[1 - a] += 1; nh[1 - b] += 1
    ci += 1
  v = 1
  while v <= nv + 1
    ph[v] += ph[v - 1]; nh[v] += nh[v - 1]; v += 1
  m[16] = ph[nv + 1]; m[17] = nh[nv + 1]
  1

-> wassat_resource_binary_edges(lits, offs, lens, nv, nc, ph, nh, pe, ne, m, stop, deadline) (i64[] i64[] i64[] i64 i64 i32[] i32[] i32[] i32[] i64[] i64[] i64) i64
  pc = i32[nv + 1]; ncurs = i32[nv + 1]; v = 0
  while v <= nv
    pc[v] = ph[v]; ncurs[v] = nh[v]; v += 1
  ci = 0
  while ci < nc
    return 0 if (ci & 1023) == 0 && wassat_resource_poll(m, stop, deadline) != 0
    if lens[ci] == 2
      o = offs[ci]; a = lits[o]; b = lits[o + 1]
      if a < 0 && b > 0
        v = 0 - a; pe[pc[v]] = b; pc[v] += 1
      elsif b < 0 && a > 0
        v = 0 - b; pe[pc[v]] = a; pc[v] += 1
      elsif a < 0 && b < 0
        a = 0 - a; b = 0 - b
        ne[ncurs[a]] = b; ncurs[a] += 1
        ne[ncurs[b]] = a; ncurs[b] += 1
    ci += 1
  1

# Mark every original negative-binary partner of a positive consequence of
# the event. All initial heads came from checked original (-time,-choice,head).
-> wassat_resource_mark(a, b, ph, pe, nh, ne, seen, bad, queue, stamp, btag, m, stop, deadline) (i64 i64 i32[] i32[] i32[] i32[] i32[] i32[] i32[] i64 i64 i64[] i64[] i64) i64
  n = 0
  if a > 0
    queue[n] = a; n += 1; seen[a] = stamp
  if b > 0 && b != a
    queue[n] = b; n += 1; seen[b] = stamp
  q = 0
  while q < n
    return -1 if (q & 127) == 0 && wassat_resource_poll(m, stop, deadline) != 0
    v = queue[q]; q += 1; p = nh[v]
    while p < nh[v + 1]
      bad[ne[p]] = btag; p += 1; m[15] += 1
      if (p & 1023) == 0
        return -1 if m[15] + m[18] > 50000000 || wassat_resource_poll(m, stop, deadline) != 0
    p = ph[v]
    while p < ph[v + 1]
      z = pe[p]; p += 1; m[15] += 1
      if seen[z] != stamp
        seen[z] = stamp; queue[n] = z; n += 1
      if (p & 1023) == 0
        return -1 if m[15] + m[18] > 50000000 || wassat_resource_poll(m, stop, deadline) != 0
  1

-> wassat_resource_clash(a, b, ph, pe, seen, bad, queue, stamp, btag, m, stop, deadline) (i64 i64 i32[] i32[] i32[] i32[] i32[] i64 i64 i64[] i64[] i64) i64
  n = 0
  if a > 0
    queue[n] = a; n += 1; seen[a] = stamp
  if b > 0 && b != a
    queue[n] = b; n += 1; seen[b] = stamp
  q = 0
  while q < n
    return -1 if (q & 127) == 0 && wassat_resource_poll(m, stop, deadline) != 0
    v = queue[q]; q += 1; m[15] += 1
    return 1 if bad[v] == btag
    p = ph[v]
    while p < ph[v + 1]
      z = pe[p]; p += 1; m[15] += 1
      if seen[z] != stamp
        seen[z] = stamp; queue[n] = z; n += 1
      if (p & 1023) == 0
        return -1 if m[15] + m[18] > 50000000 || wassat_resource_poll(m, stop, deadline) != 0
  0

-> wassat_resource_verify_events(lits, offs, lens, nv, cid, owner, minima, res, witness, head1, head2, forbidden, ph, pe, nh, ne, m, stop, deadline) (i64[] i64[] i64[] i64 i32[] i32[] i32[] i32[] i32[] i32[] i32[] i8[] i32[] i32[] i32[] i32[] i64[] i64[] i64) i64
  count = m[3]; ns = m[1]; nw = m[7]
  return 0 if nw < 1 || nw > 4096 || m[10] < 1 || m[10] > 64
  roots = i32[count]; event_owner = i32[nw * 64]; events = i32[nw * 64]; used_courses = i8[4096]
  nres = 0; evs = 0; load = 0; d = 0
  while d < nw
    ci = witness[d]; o = offs[ci]; course = owner[cid[lits[o]] - 1] - 1
    return 0 if course < 0 || course >= m[0] || used_courses[course] != 0
    used_courses[course] = 1; load += minima[course]; j = 0
    while j < lens[ci]
      id = cid[lits[o + j]] - 1; root = wassat_resource_root(res, id)
      if roots[root] == 0
        nres += 1; return 0 if nres > 64
        roots[root] = nres
      events[evs] = id; event_owner[evs] = roots[root]; evs += 1; j += 1
    d += 1
  return 0 if load <= nres * ns
  seen = i32[nv + 1]; bad = i32[nv + 1]; queue = i32[nv + 1]
  stamp = 0; btag = 0; sl = 0
  while sl < ns
    i = 0
    while i < evs
      return 0 if wassat_resource_poll(m, stop, deadline) != 0 || m[15] + m[18] > 50000000
      ai = events[i]; ap = ai * ns + sl
      if forbidden[ap] == 0
        return 0 if head1[ap] == 0
        stamp += 1; btag += 1
        marked = wassat_resource_mark((head1[ap] ## i64), (head2[ap] ## i64), ph, pe, nh, ne, seen, bad, queue, stamp, btag, m, stop, deadline)
        return 0 if marked != 1
        j = i + 1
        while j < evs
          m[18] += 1
          if (j & 1023) == 0
            return 0 if m[15] + m[18] > 50000000 || wassat_resource_poll(m, stop, deadline) != 0
          bi = events[j]; bp = bi * ns + sl
          if event_owner[j] == event_owner[i] && owner[bi] != owner[ai] && forbidden[bp] == 0
            return 0 if head1[bp] == 0
            stamp += 1
            clash = wassat_resource_clash((head1[bp] ## i64), (head2[bp] ## i64), ph, pe, seen, bad, queue, stamp, btag, m, stop, deadline)
            return 0 if clash != 1
            m[14] += 1
          j += 1
      i += 1
    sl += 1
  m[8] = load; m[9] = nres * ns; m[10] = nres
  1

-> wassat_resource_refute(formula, m, stop, deadline = 0)
  return 0 if m.size < 64 || stop.size < 2
  i = 0
  while i < 64
    m[i] = 0; i += 1
  return 0 if wassat_resource_poll(m, stop, deadline) != 0
  r = wassat_resource_discover(formula, m, stop, deadline)
  return 0 if r == nil
  nv = formula["nvars"]; nc = formula["flat_ncl"]
  lits = formula["flat_lits"]; offs = formula["flat_offs"]; lens = formula["flat_lens"]
  ph = i32[nv + 2]; nh = i32[nv + 2]
  return 0 if wassat_resource_binary_graph(lits, offs, lens, nv, nc, ph, nh, m, stop, deadline) != 1
  pe = i32[m[16]]; ne = i32[m[17]]
  return 0 if wassat_resource_binary_edges(lits, offs, lens, nv, nc, ph, nh, pe, ne, m, stop, deadline) != 1
  ok = wassat_resource_verify_events(lits, offs, lens, nv, r["cid"], r["owner"], r["minima"], r["res"], r["witness"], r["head1"], r["head2"], r["forbidden"], ph, pe, nh, ne, m, stop, deadline)
  return 0 if ok != 1 || wassat_resource_poll(m, stop, deadline) != 0
  -1
