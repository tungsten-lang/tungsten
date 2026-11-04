# Two watched elements per monochromatic nogood. Watches remain valid after
# backtracking, so rollback clears assignments without touching every scope.
# The caller has checked each scope has at least two distinct elements.
# elems is private mutable scratch: keep the watches in its first two scope
# positions and swap replacements into them. Scope membership is unchanged.
use monochrome_count

# m shares the count backend's search/budget counters. Here [6] counts watch
# visits, [10] undone assignments, [19] scanned elements, [20] watch moves,
# and [21] watches skipped because the other watched element is safe.
-> wassat_mwatch_propagate(asg, trail, offs, elems, heads, links, slots, m, stop, v, color) (i8[] i64[] i64[] i64[] i32[] i32[] i32[] i64[] i64[] i64 i64) i64
  m[18] += 1
  return 0 if wassat_mono_enqueue(asg, trail, m, v, color) == 0
  while m[1] < m[0]
    x = trail[m[1]] ## i64
    c = asg[x] ## i64
    m[1] += 1
    m[16] += 1
    at = 2 * x + c ## i64
    prev = -1 ## i64
    w = heads[at] ## i64
    while w >= 0
      m[6] += 1
      other_slot = slots[w ^ 1] ## i64
      other = elems[other_slot] ## i64
      if asg[other] >= 0 && asg[other] != c
        m[21] += 1
        prev = w
        w = links[w]
        next
      si = w >> 1 ## i64
      old_slot = slots[w] ## i64
      p = offs[si] + 2 ## i64
      end = offs[si + 1] ## i64
      while p < end
        m[19] += 1
        break if asg[elems[p]] != c
        p += 1
      if p < end
        dest = 2 * elems[p] + c ## i64
        next_w = links[w] ## i64
        if prev < 0
          heads[at] = next_w
        else
          links[prev] = next_w
        links[w] = heads[dest]
        heads[dest] = w
        old_element = elems[old_slot] ## i64
        elems[old_slot] = elems[p]
        elems[p] = old_element
        m[20] += 1
        w = next_w
        next
      m[7] += 1
      if wassat_mono_enqueue(asg, trail, m, other, 1 - c) == 0
        m[13] += 1
        return 0
      prev = w
      w = links[w]
    if m[6] >= m[9]
      m[9] = m[6] + 32768
      return 0 if wassat_mono_poll(m, stop) != 0
  1

-> wassat_mwatch_undo(asg, trail, m, mark) (i8[] i64[] i64[] i64) i64
  while m[0] > mark
    m[0] -= 1
    asg[trail[m[0]]] = -1
    m[10] += 1
  m[1] = mark
  0

-> wassat_mwatch_dfs(asg, trail, offs, elems, heads, links, slots, order, m, stop, nv) (i8[] i64[] i64[] i64[] i32[] i32[] i32[] i64[] i64[] i64[] i64) i64
  m[2] += 1
  return 0 if (m[2] & 255) == 1 && wassat_mono_poll(m, stop) != 0
  if m[2] > m[3]
    m[5] = 1
    return 0
  v = -1 ## i64
  i = 0 ## i64
  while i < nv
    if asg[order[i]] < 0
      v = order[i]
      break
    i += 1
  return 1 if v < 0
  mark = m[0] ## i64
  color = 0 ## i64
  while color < 2
    m[12] += 1
    status = wassat_mwatch_propagate(asg, trail, offs, elems, heads, links, slots, m, stop, v, color) ## i64
    if status == 1
      status = wassat_mwatch_dfs(asg, trail, offs, elems, heads, links, slots, order, m, stop, nv)
      return 1 if status == 1
      if status == 0
        wassat_mwatch_undo(asg, trail, m, mark)
        return 0
    wassat_mwatch_undo(asg, trail, m, mark)
    return 0 if m[5] != 0
    color += 1
  -1

-> wassat_mwatch_run(asg, offs, elems, forbid, order, trail, nv, ns, cap, deadline, symmetric, m, stop) (i8[] i64[] i64[] i8[] i64[] i64[] i64 i64 i64 i64 i64 i64[] i64[]) i64
  m[3] = cap
  m[4] = deadline
  return 0 if wassat_mono_poll(m, stop) != 0
  heads = i32[2 * nv]
  links = i32[2 * ns]
  slots = i32[2 * ns]
  i = 0
  while i < 2 * nv
    heads[i] = -1
    i += 1
  si = 0
  while si < ns
    return 0 if (si & 255) == 0 && wassat_mono_poll(m, stop) != 0
    k = 0
    while k < 2
      w = 2 * si + k
      p = offs[si] + k
      at = 2 * elems[p] + forbid[si]
      slots[w] = p
      links[w] = heads[at]
      heads[at] = w
      k += 1
    m[14] += 1
    m[15] += offs[si + 1] - offs[si]
    si += 1
  good = 1
  if symmetric != 0
    good = wassat_mwatch_propagate(asg, trail, offs, elems, heads, links, slots, m, stop, order[0], 0)
  status = -1
  if good == 1
    status = wassat_mwatch_dfs(asg, trail, offs, elems, heads, links, slots, order, m, stop, nv)
  m[5] != 0 ? 0 : status
