# Exact search for monochromatic forbidden scopes, with independent colors.
# A scope can forbid either zero or one; unlike NAE, it need not have a
# complementary partner. Counts and XOR remainder avoid rescanning scopes.
# Reuse the decoder's incidence arrays, order and trail. All scratch is fixed.
use atomic_stop
# m: trail size, processed head, nodes, cap, deadline, stop, visits, forces,
# polls, next poll, undo visits, enqueues, branches, conflicts, prepared scopes,
# prepared literals, processed assignments, unused, propagation calls.
-> wassat_mono_poll(m, stop) (i64[] i64[]) i64
  m[8] += 1
  if wassat_stop_requested?(stop)
    m[5] = 3
  elsif m[4] > 0 && clock_ms() >= m[4]
    m[5] = 2
  m[5]

-> wassat_mono_enqueue(asg, trail, m, v, color) (i8[] i64[] i64[] i64 i64) i64
  if asg[v] >= 0
    return asg[v] == color ? 1 : 0
  asg[v] = color
  trail[m[0]] = v
  m[0] += 1
  m[11] += 1
  1

-> wassat_mono_propagate(asg, trail, heads, inc, width, forbid, counts, remain, m, stop, v, color) (i8[] i64[] i64[] i64[] i8[] i8[] i8[] i64[] i64[] i64[] i64 i64) i64
  m[18] += 1
  return 0 if wassat_mono_enqueue(asg, trail, m, v, color) == 0
  good = 1 ## i64
  while m[1] < m[0] && good == 1
    x = trail[m[1]] ## i64
    m[1] += 1
    m[16] += 1
    c = asg[x] ## i64
    p = heads[x] ## i64
    end = heads[x + 1] ## i64
    m[6] += end - p
    forced = 0 ## i64
    while p < end
      si = inc[p] ## i64
      at = 2 * si + c ## i64
      n = counts[at] + 1 ## i64
      counts[at] = n
      remain[si] ^= x
      if c == forbid[si] && counts[2 * si + 1 - c] == 0
        if n == width[si]
          good = 0
        elsif n == width[si] - 1
          forced += 1
          if wassat_mono_enqueue(asg, trail, m, (remain[si] ## i64), 1 - c) == 0
            good = 0
      p += 1
    m[7] += forced
    if m[6] >= m[9]
      m[9] = m[6] + 32768
      return 0 if wassat_mono_poll(m, stop) != 0
  m[13] += 1 if good == 0
  good

-> wassat_mono_undo(asg, trail, heads, inc, counts, remain, m, mark) (i8[] i64[] i64[] i64[] i8[] i64[] i64[] i64) i64
  while m[0] > mark
    i = m[0] - 1 ## i64
    v = trail[i] ## i64
    if i < m[1]
      c = asg[v] ## i64
      p = heads[v] ## i64
      end = heads[v + 1] ## i64
      m[10] += end - p
      while p < end
        si = inc[p] ## i64
        counts[2 * si + c] -= 1
        remain[si] ^= v
        p += 1
    asg[v] = -1
    m[0] -= 1
  m[1] = mark
  0

-> wassat_mono_dfs(asg, trail, heads, inc, width, forbid, counts, remain, order, m, stop, nv) (i8[] i64[] i64[] i64[] i8[] i8[] i8[] i64[] i64[] i64[] i64[] i64) i64
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
    status = wassat_mono_propagate(asg, trail, heads, inc, width, forbid, counts, remain, m, stop, v, color) ## i64
    if status == 1
      status = wassat_mono_dfs(asg, trail, heads, inc, width, forbid, counts, remain, order, m, stop, nv)
      return 1 if status == 1
      if status == 0
        wassat_mono_undo(asg, trail, heads, inc, counts, remain, m, mark)
        return 0
    wassat_mono_undo(asg, trail, heads, inc, counts, remain, m, mark)
    return 0 if m[5] != 0
    color += 1
  -1

# The caller validates sorted distinct scope elements and color polarity,
# and supplies an unassigned array. Symmetry must be checked from every
# original scope before the caller may request the complemented-root cut.
-> wassat_mono_run(asg, offs, elems, forbid, heads, inc, order, trail,
                    nv, ns, cap, deadline, symmetric, m, stop) (i8[] i64[] i64[] i8[] i64[] i64[] i64[] i64[] i64 i64 i64 i64 i64 i64[] i64[]) i64
  m[3] = cap
  m[4] = deadline
  return 0 if wassat_mono_poll(m, stop) != 0
  width = i8[ns]
  counts = i8[2 * ns]
  remain = i64[ns]
  si = 0
  while si < ns
    return 0 if (si & 255) == 0 && wassat_mono_poll(m, stop) != 0
    width[si] = offs[si + 1] - offs[si]
    j = offs[si]
    while j < offs[si + 1]
      remain[si] ^= elems[j]
      j += 1
    m[14] += 1
    m[15] += width[si]
    si += 1
  good = 1
  if symmetric != 0
    good = wassat_mono_propagate(asg, trail, heads, inc, width, forbid,
      counts, remain, m, stop, order[0], 0)
  status = -1
  if good == 1
    status = wassat_mono_dfs(asg, trail, heads, inc, width, forbid,
      counts, remain, order, m, stop, nv)
  m[5] != 0 ? 0 : status
