# Exact not-all-equal search over verified complementary clause pairs.
# Counts and the XOR of unprocessed elements replace repeated scope scans.
# Every buffer is fixed; rollback distinguishes processed trail entries from
# queued assignments whose incidence updates have not run yet.
use atomic_stop
# m: trail size, processed head, nodes, cap, deadline, stop, visits, forces,
# polls, next poll, undo visits, enqueues, branches, conflicts.
-> wassat_nae_poll(m, stop) (i64[] i64[]) i64
  m[8] += 1
  if wassat_stop_requested?(stop)
    m[5] = 3
  elsif m[4] > 0 && clock_ms() >= m[4]
    m[5] = 2
  m[5]

-> wassat_nae_enqueue(asg, trail, m, v, color) (i8[] i32[] i64[] i64 i64) i64
  if asg[v] >= 0
    return asg[v] == color ? 1 : 0
  asg[v] = color
  trail[m[0]] = v
  m[0] += 1
  m[11] += 1
  1

-> wassat_nae_propagate(asg, trail, heads, inc, width, counts, remain, m, stop, v, color) (i8[] i32[] i32[] i32[] i8[] i8[] i32[] i64[] i64[] i64 i64) i64
  return 0 if wassat_nae_enqueue(asg, trail, m, v, color) == 0
  good = 1 ## i64
  while m[1] < m[0] && good == 1
    x = trail[m[1]] ## i64
    m[1] += 1
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
      if counts[2 * si + 1 - c] == 0
        if n == width[si]
          good = 0
        elsif n == width[si] - 1
          forced += 1
          if wassat_nae_enqueue(asg, trail, m, (remain[si] ## i64), 1 - c) == 0
            good = 0
      p += 1
    m[7] += forced
    if m[6] >= m[9]
      m[9] = m[6] + 32768
      return 0 if wassat_nae_poll(m, stop) != 0
  m[13] += 1 if good == 0
  good

-> wassat_nae_undo(asg, trail, heads, inc, counts, remain, m, mark) (i8[] i32[] i32[] i32[] i8[] i32[] i64[] i64) i64
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

-> wassat_nae_dfs(asg, trail, heads, inc, width, counts, remain, order, m, stop, nv) (i8[] i32[] i32[] i32[] i8[] i8[] i32[] i32[] i64[] i64[] i64) i64
  m[2] += 1
  return 0 if (m[2] & 255) == 1 && wassat_nae_poll(m, stop) != 0
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
    status = wassat_nae_propagate(asg, trail, heads, inc, width, counts, remain, m, stop, v, color) ## i64
    if status == 1
      status = wassat_nae_dfs(asg, trail, heads, inc, width, counts, remain, order, m, stop, nv)
      return 1 if status == 1
      if status == 0
        wassat_nae_undo(asg, trail, heads, inc, counts, remain, m, mark)
        return 0
    wassat_nae_undo(asg, trail, heads, inc, counts, remain, m, mark)
    return 0 if m[5] != 0
    color += 1
  -1
