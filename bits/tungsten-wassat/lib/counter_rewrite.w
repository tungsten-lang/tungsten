# Compact a closed unary-adder suffix without consulting benchmark identities.
# Each node's acyclic gate definitions determine all fresh variables. Exhaustive
# child-count truth tables check EVERY local clause, including overflow, and
# check the output vector. Unique leaf/child use and the closed suffix then
# establish exactly-k over distinct prefix variables. The replacement totalizer
# has the same relation; evaluating the old gates reconstructs original models.
# Only the fast light preprocessing arm opts in. Proof paths keep the original
# encoding, and the coordinator still replays every original clause on SAT.
# Repeated regular leaf subtrees supply a grouping heuristic, not a soundness
# assumption. Unsupported layouts, bounds or resource limits decline unchanged.
#
# m:0 prefix clauses,1 first auxiliary,2 nodes,3 gates,4 leaves,5 exact count,
# 6 stop reason(cancel/deadline/capacity/work),7 deadline,8 polls,9 clause checks,
# 10 local truth cases,11 groups,12 scanned literals,13 copied literals,
# 14 scratch estimate,15 elapsed ms,16 decode steps,17 gate evaluations,
# 18 grouping steps,19 copied clauses,20 new nv,21 new nc,22 new literals,
# 23 original nv. All hot scratch is fixed-size and reused.
use cnf
use atomic_stop

-> wassat_counter_abs(x) (i64) i64
  x < 0 ? 0 - x : x

-> wassat_counter_gcd(a, b) (i64 i64) i64
  while b != 0
    r = a % b ## i64
    a = b; b = r
  a

-> wassat_counter_poll(m, stop) (i64[] i64[]) i64
  m[8] += 1
  m[6] = 1 if wassat_stop_load(stop) != 0
  m[6] = 2 if m[7] > 0 && clock_ms() >= m[7]
  m[6] = 4 if m[9] + m[12] + m[13] + m[16] + m[17] + m[18] + m[19] >= 64000000
  m[6]

-> wassat_counter_c2(l, o, n, ci, a, b) (i64[] i64[] i64[] i64 i64 i64) i64
  return 0 if ci < 0 || ci >= n.size || n[ci] != 2
  p = o[ci] ## i64
  return 0 if p < 0 || p + 2 > l.size
  l[p] == a && l[p + 1] == b ? 1 : 0

-> wassat_counter_c3(l, o, n, ci, a, b, c) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  return 0 if ci < 0 || ci >= n.size || n[ci] != 3
  p = o[ci] ## i64
  return 0 if p < 0 || p + 3 > l.size
  l[p] == a && l[p + 1] == b && l[p + 2] == c ? 1 : 0

# Find a fresh contiguous output block after a prefix that contains all
# leaves. This is only an admission hint; parse and relation checks follow.
-> wassat_counter_find(l, o, n, nv, nc, m, stop) (i64[] i64[] i64[] i64 i64 i64[] i64[]) i64
  return 0 if nc < 8 || n[nc - 1] != 1 || l[o[nc - 1]] < 1
  maximum = 0 ## i64
  ci = 0 ## i64
  while ci + 7 < nc
    if n[ci] == 2 && wassat_counter_c2(l, o, n, ci, 0 - maximum - 2, maximum + 1) != 0
      j = ci + 1 ## i64
      k = 2 ## i64
      while j < nc && k <= 32 && wassat_counter_c2(l, o, n, j, 0 - maximum - k - 1, maximum + k) != 0
        k += 1; j += 1
      if k <= 32 && j + 2 < nc && n[j] == 2 && n[j + 1] == 2
        a = 0 - l[o[j]] ## i64
        b = 0 - l[o[j + 1]] ## i64
        if a > 0 && a <= maximum && b > 0 && b <= maximum && l[o[j] + 1] == maximum + 1 && l[o[j + 1] + 1] == maximum + 1
          if wassat_counter_c3(l, o, n, j + 2, 0 - maximum - 1, a, b) != 0
            m[0] = ci; m[1] = maximum + 1
            return 1
    j = 0 ## i64
    while j < n[ci]
      v = wassat_counter_abs(l[o[ci] + j]) ## i64
      maximum = v if v > maximum
      j += 1; m[12] += 1
      return 0 if (m[12] & 4095) == 0 && wassat_counter_poll(m, stop) != 0
    ci += 1
    return 0 if (ci & 4095) == 0 && wassat_counter_poll(m, stop) != 0
  0

# Node stride16: first,last,cap,clause start/end,gate start/end,a,b,
# leaf count,min,max,gcd,parent+1,regular,ancestor-covered.
# Gate stride5: op(1 or,2 and,3 step),output,a,b,d.
-> wassat_counter_parse(l, o, n, nv, nc, nodes, gates, owner, index, defined, used, m, stop) (i64[] i64[] i64[] i64 i64 i64[] i64[] i32[] i32[] i8[] i8[] i64[] i64[]) i64
  ci = m[0] ## i64
  base = m[1] ## i64
  maximum = base - 1 ## i64
  nn = 0 ## i64
  ng = 0 ## i64
  leaves = 0 ## i64
  while ci < nc - 1
    return 0 if wassat_counter_poll(m, stop) != 0 || (nn + 1) * 16 > nodes.size
    first = maximum + 1 ## i64
    start = ci ## i64
    cap = 1 ## i64
    return 0 if wassat_counter_c2(l, o, n, ci, 0 - first - 1, first) == 0
    while ci < nc - 1 && wassat_counter_c2(l, o, n, ci, 0 - first - cap, first + cap - 1) != 0
      cap += 1; ci += 1
      return 0 if cap > 32
    return 0 if first + cap - 1 > nv || ci + 2 >= nc || n[ci] != 2 || n[ci + 1] != 2
    a = 0 - l[o[ci]] ## i64
    b = 0 - l[o[ci + 1]] ## i64
    return 0 if a < 1 || a >= first || b < 1 || b >= first || a == b
    return 0 if wassat_counter_c2(l, o, n, ci, 0 - a, first) == 0 || wassat_counter_c2(l, o, n, ci + 1, 0 - b, first) == 0 || wassat_counter_c3(l, o, n, ci + 2, 0 - first, a, b) == 0
    la = 1 ## i64
    lb = 1 ## i64
    cnt = 0 ## i64
    mn = nv ## i64
    mx = 0 ## i64
    gcd = 0 ## i64
    side = 0 ## i64
    while side < 2
      v = side == 0 ? a : b ## i64
      return 0 if used[v] != 0
      used[v] = 1
      child_min = v ## i64
      child_max = v ## i64
      child_count = 1 ## i64
      child_gcd = 0 ## i64
      if v >= base
        return 0 if owner[v] != v || index[v] < 1
        child = (index[v] - 1) * 16 ## i64
        nodes[child + 13] = nn + 1
        la = nodes[child + 2] if side == 0
        lb = nodes[child + 2] if side == 1
        child_count = nodes[child + 9]; child_min = nodes[child + 10]; child_max = nodes[child + 11]; child_gcd = nodes[child + 12]
      else
        leaves += 1
      gcd = wassat_counter_gcd(gcd, child_gcd)
      gcd = wassat_counter_gcd(gcd, wassat_counter_abs(child_min - mn)) if side == 1
      mn = child_min if child_min < mn
      mx = child_max if child_max > mx
      cnt += child_count
      side += 1
    node = nn * 16 ## i64
    nodes[node] = first; nodes[node + 2] = cap; nodes[node + 3] = start; nodes[node + 5] = ng; nodes[node + 7] = a; nodes[node + 8] = b
    nodes[node + 9] = cnt; nodes[node + 10] = mn; nodes[node + 11] = mx; nodes[node + 12] = gcd
    nodes[node + 14] = cnt >= 32 && gcd > 0 && mx - mn == (cnt - 1) * gcd ? 1 : 0
    while ci < nc - 1
      m[16] += 1
      return 0 if (m[16] & 1023) == 0 && wassat_counter_poll(m, stop) != 0
      break if ci > start && wassat_counter_c2(l, o, n, ci, 0 - maximum - 2, maximum + 1) != 0
      off = o[ci] ## i64
      op = 0 ## i64
      z = 0 ## i64
      ga = 0 ## i64
      gb = 0 ## i64
      gd = 0 ## i64
      step = 0 ## i64
      if n[ci] == 2 && l[off] < 0 && l[off + 1] > 0 && ci + 2 < nc
        ga = 0 - l[off]; z = l[off + 1]
        if n[ci + 1] == 2 && l[o[ci + 1]] < 0
          gb = 0 - l[o[ci + 1]]
          if wassat_counter_c2(l, o, n, ci + 1, 0 - gb, z) != 0 && wassat_counter_c3(l, o, n, ci + 2, 0 - z, ga, gb) != 0
            op = 1; step = 3
        elsif n[ci + 1] == 3 && l[o[ci + 1]] < 0 && l[o[ci + 1] + 1] < 0 && ci + 3 < nc
          gb = 0 - l[o[ci + 1]]; gd = 0 - l[o[ci + 1] + 1]
          if wassat_counter_c3(l, o, n, ci + 1, 0 - gb, 0 - gd, z) != 0 && wassat_counter_c2(l, o, n, ci + 2, 0 - z, gd) != 0 && wassat_counter_c3(l, o, n, ci + 3, 0 - z, ga, gb) != 0
            op = 3; step = 4
      elsif n[ci] == 3 && l[off] < 0 && l[off + 1] < 0 && l[off + 2] > 0 && ci + 2 < nc
        gb = 0 - l[off]; ga = 0 - l[off + 1]; z = l[off + 2]
        if wassat_counter_c2(l, o, n, ci + 1, 0 - z, ga) != 0 && wassat_counter_c2(l, o, n, ci + 2, 0 - z, gb) != 0
          op = 2; step = 3
      if op == 0
        return 0 if n[ci] != 2
        ci += 1
      else
        return 0 if z < first || z > nv || defined[z] != 0 || (ng + 1) * 5 > gates.size
        j = 0 ## i64
        while j < (op == 3 ? 3 : 2)
          v = j == 0 ? ga : (j == 1 ? gb : gd) ## i64
          return 0 if v < 1 || v > nv
          valid = (v >= a && v < a + la) || (v >= b && v < b + lb) || (v >= first && defined[v] != 0) ## bool
          return 0 unless valid
          j += 1
        defined[z] = 1
        gates[ng * 5] = op; gates[ng * 5 + 1] = z; gates[ng * 5 + 2] = ga; gates[ng * 5 + 3] = gb; gates[ng * 5 + 4] = gd
        ng += 1; ci += step
        maximum = z if z > maximum
    return 0 if ng - nodes[node + 5] != maximum - first + 1
    nodes[node + 1] = maximum; nodes[node + 4] = ci; nodes[node + 6] = ng
    v = first ## i64
    while v < first + cap
      owner[v] = first; index[v] = nn + 1; v += 1
    # The membership restriction applies to extra monotonic/overflow clauses too.
    cc = start ## i64
    while cc < ci
      j = 0 ## i64
      while j < n[cc]
        v = wassat_counter_abs(l[o[cc] + j]) ## i64
        return 0 unless (v >= a && v < a + la) || (v >= b && v < b + lb) || (v >= first && v <= maximum)
        j += 1
      cc += 1; m[16] += 1
      return 0 if (m[16] & 1023) == 0 && wassat_counter_poll(m, stop) != 0
    nn += 1
  return 0 if nn == 0 || maximum != nv || leaves != nn + 1 || n[nc - 1] != 1
  last = (nn - 1) * 16 ## i64
  k = nodes[last + 2] ## i64
  return 0 if l[o[nc - 1]] != nodes[last] + k - 1
  i = 0 ## i64
  while i < nn
    node = i * 16
    a = nodes[node + 7]; b = nodes[node + 8]
    la = a < base ? 1 : nodes[(index[a] - 1) * 16 + 2]
    lb = b < base ? 1 : nodes[(index[b] - 1) * 16 + 2]
    want = la + lb ## i64
    want = k if want > k
    return 0 if nodes[node + 2] != want || (i < nn - 1 && nodes[node + 13] == 0)
    i += 1
  m[2] = nn; m[3] = ng; m[4] = leaves; m[5] = k
  1

# Exhaustive local equivalence using 31 parallel count pairs per raw word.
-> wassat_counter_verify(l, o, n, nodes, gates, index, vals, m, stop) (i64[] i64[] i64[] i64[] i64[] i32[] i64[] i64[] i64[]) i64
  ni = 0 ## i64
  one = 1 ## i64
  while ni < m[2]
    return 0 if wassat_counter_poll(m, stop) != 0
    p = ni * 16 ## i64
    first = nodes[p] ## i64
    cap = nodes[p + 2] ## i64
    a = nodes[p + 7] ## i64
    b = nodes[p + 8] ## i64
    la = a < m[1] ? 1 : nodes[(index[a] - 1) * 16 + 2] ## i64
    lb = b < m[1] ? 1 : nodes[(index[b] - 1) * 16 + 2] ## i64
    total = (la + 1) * (lb + 1) ## i64
    chunk_base = 0 ## i64
    while chunk_base < total
      count = total - chunk_base ## i64
      count = 31 if count > 31
      mask = (one << count) - 1 ## i64
      valid = 0 ## i64
      j = 0 ## i64
      while j < la
        vals[a + j] = 0; j += 1
      j = 0
      while j < lb
        vals[b + j] = 0; j += 1
      bit = 0 ## i64
      while bit < count
        ca = (chunk_base + bit) / (lb + 1) ## i64
        cb = (chunk_base + bit) % (lb + 1) ## i64
        word = one << bit ## i64
        valid |= word if ca + cb <= cap
        j = 0
        while j < ca
          vals[a + j] |= word; j += 1
        j = 0
        while j < cb
          vals[b + j] |= word; j += 1
        bit += 1
      g = nodes[p + 5] ## i64
      while g < nodes[p + 6]
        gp = g * 5 ## i64
        op = gates[gp] ## i64
        x = vals[gates[gp + 2]] ## i64
        y = vals[gates[gp + 3]] ## i64
        value = op == 1 ? x | y : x & y ## i64
        value = x | (y & vals[gates[gp + 4]]) if op == 3
        vals[gates[gp + 1]] = value
        g += 1; m[17] += 1
        return 0 if (m[17] & 1023) == 0 && wassat_counter_poll(m, stop) != 0
      j = 0
      while j < cap
        expected = 0 ## i64
        bit = 0
        while bit < count
          ca = (chunk_base + bit) / (lb + 1); cb = (chunk_base + bit) % (lb + 1)
          expected |= one << bit if ca + cb > j
          bit += 1
        return 0 if ((vals[first + j] ^ expected) & valid) != 0
        j += 1
      bad = 0 ## i64
      ci = nodes[p + 3] ## i64
      while ci < nodes[p + 4]
        sat = 0 ## i64
        j = 0
        while j < n[ci]
          lit = l[o[ci] + j] ## i64
          truth = vals[wassat_counter_abs(lit)] ## i64
          sat |= lit > 0 ? truth : mask ^ truth
          j += 1
        bad |= mask ^ sat
        ci += 1; m[9] += 1
        return 0 if (m[9] & 1023) == 0 && wassat_counter_poll(m, stop) != 0
      return 0 if bad != (mask ^ valid)
      m[10] += count
      chunk_base += count
    ni += 1
  1

# Maximal regular leaf subtrees recover repeated groups without filenames,
# timestep sizes or component counts. Sorting them preserves related leaves.
-> wassat_counter_group(nodes, used, groups, inputs, m, stop) (i64[] i8[] i64[] i64[] i64[] i64[]) i64
  ng = 0 ## i64
  # Parents were decoded after children. Propagate ancestor coverage once,
  # in reverse node order; an unbalanced tree must not cause a quadratic walk.
  ni = m[2] - 1 ## i64
  while ni >= 0
    p = ni * 16 ## i64
    parent = nodes[p + 13] ## i64
    covered = 0 ## i64
    if parent > 0
      pp = (parent - 1) * 16 ## i64
      covered = nodes[pp + 15] != 0 || nodes[pp + 14] != 0 ? 1 : 0
    nodes[p + 15] = covered
    if nodes[p + 14] != 0
      if covered == 0
        return 0 if ng >= groups.size
        at = ng ## i64
        while at > 0 && nodes[groups[at - 1] * 16 + 10] > nodes[p + 10]
          groups[at] = groups[at - 1]; at -= 1
        groups[at] = ni; ng += 1
    ni -= 1; m[18] += 1
    return 0 if (m[18] & 255) == 0 && wassat_counter_poll(m, stop) != 0
  ni = 0
  pos = 0 ## i64
  while ni < ng
    p = groups[ni] * 16
    v = nodes[p + 10] ## i64
    j = 0 ## i64
    while j < nodes[p + 9]
      return 0 if v < 1 || v >= m[1] || used[v] != 1 || pos >= inputs.size
      used[v] = 2
      inputs[pos] = v; pos += 1; v += nodes[p + 12]; j += 1; m[18] += 1
      return 0 if (m[18] & 1023) == 0 && wassat_counter_poll(m, stop) != 0
    ni += 1
  return 0 if pos != m[4] || ng < 2
  m[11] = ng
  1

-> wassat_counter_emit(l, o, n, a, b, c, m) (i64[] i64[] i64[] i64 i64 i64 i64[]) i64
  ci = m[21] ## i64
  off = m[22] ## i64
  if ci >= n.size || ci >= o.size || off + 3 > l.size
    m[6] = 3
    return 0
  o[ci] = off
  width = 0 ## i64
  if a != 0
    l[off + width] = a; width += 1
  if b != 0
    l[off + width] = b; width += 1
  if c != 0
    l[off + width] = c; width += 1
  n[ci] = width; m[21] += 1; m[22] += width
  1

-> wassat_counter_build(inputs, lo, size, k, l, o, n, m, stop) (i64[] i64 i64 i64 i64[] i64[] i64[] i64[] i64[]) i64
  return inputs[lo] if size == 1
  return 0 if m[6] != 0 || wassat_counter_poll(m, stop) != 0
  half = size / 2 ## i64
  a = wassat_counter_build(inputs, lo, half, k, l, o, n, m, stop) ## i64
  b = wassat_counter_build(inputs, lo + half, size - half, k, l, o, n, m, stop) ## i64
  return 0 if a == 0 || b == 0 || m[6] != 0
  la = half < k ? half : k ## i64
  lb = size - half < k ? size - half : k ## i64
  cap = size < k ? size : k ## i64
  z = m[20] + 1 ## i64
  m[20] += cap
  if m[20] > m[23]
    m[6] = 3
    return 0
  i = 0 ## i64
  while i <= la
    j = 0 ## i64
    while j <= lb
      sum = i + j ## i64
      ai = i > 0 ? 0 - a - i + 1 : 0 ## i64
      bj = j > 0 ? 0 - b - j + 1 : 0 ## i64
      if sum > 0 && sum <= k
        ok = wassat_counter_emit(l, o, n, ai, bj, z + sum - 1, m)
      elsif sum == k + 1
        ok = wassat_counter_emit(l, o, n, ai, bj, 0, m)
      if sum < cap
        an = i < la ? a + i : 0 ## i64
        bn = j < lb ? b + j : 0 ## i64
        ok = wassat_counter_emit(l, o, n, an, bn, 0 - z - sum, m)
      return 0 if m[6] != 0
      j += 1
    i += 1
  j = 1 ## i64
  while j < cap
    ok = wassat_counter_emit(l, o, n, 0 - z - j, z + j - 1, 0, m)
    j += 1
  z

-> wassat_counter_rewrite(formula, stop = nil, deadline = 0)
  nv = formula["nvars"]
  nc = formula["flat_ncl"]
  return nil if nv > 1000000 || nv < 128 || nc > 5000000 || nc < 128
  l = formula["flat_lits"]; o = formula["flat_offs"]; n = formula["flat_lens"]
  started = clock_ms()
  m = i64[32]
  stop = i64[4] if stop == nil
  m[7] = started + 2000
  m[7] = deadline if deadline > 0 && deadline < m[7]
  return nil if wassat_counter_poll(m, stop) != 0
  return nil if wassat_counter_find(l, o, n, nv, nc, m, stop) == 0
  # Includes the private replacement formula and a conservative leaf buffer.
  # No additional CDCL/preprocessor is constructed; the existing light arm
  # reuses its allocated preprocessing capacity and gets a smaller solver.
  scratch = 104 * (nv - m[1] + 2) + 26 * (nv + 1)
  scratch += 8 * (formula["flat_nlits"] + 4) + 16 * (nc + 2) + 65536
  return nil if scratch > 134217728
  m[14] = scratch
  nodes = i64[8 * (nv - m[1] + 2)]
  gates = i64[5 * (nv - m[1] + 2)]
  owner = i32[nv + 1]; index = i32[nv + 1]; defined = i8[nv + 1]; used = i8[nv + 1]
  return nil if wassat_counter_parse(l, o, n, nv, nc, nodes, gates, owner, index, defined, used, m, stop) == 0
  vals = i64[nv + 1]
  return nil if wassat_counter_verify(l, o, n, nodes, gates, index, vals, m, stop) == 0
  groups = i64[256]; inputs = i64[m[4]]
  return nil if wassat_counter_group(nodes, used, groups, inputs, m, stop) == 0
  nl = i64[formula["flat_nlits"] + 4]; no = i64[nc + 2]; nn = i64[nc + 2]
  return nil if wassat_counter_copy_prefix(l, o, n, nl, no, nn, m, stop) == 0
  m[20] = m[1] - 1; m[23] = nv
  root = wassat_counter_build(inputs, 0, m[4], m[5], nl, no, nn, m, stop)
  return nil if root == 0 || m[6] != 0
  ok = wassat_counter_emit(nl, no, nn, root + m[5] - 1, 0, 0, m)
  return nil if m[6] != 0 || m[20] >= nv || m[21] >= nc
  m[15] = clock_ms() - started
  { "formula": { "nvars": m[20], "clauses": [], "boxed": false, "flat_lits": nl, "flat_offs": no, "flat_lens": nn, "flat_ncl": m[21], "flat_nlits": m[22] }, "meta": m, "nodes": nodes, "gates": gates }

-> wassat_counter_copy_prefix(l, o, n, nl, no, nn, m, stop) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  ci = 0 ## i64
  at = 0 ## i64
  while ci < m[0]
    no[ci] = at; nn[ci] = n[ci]
    j = 0 ## i64
    while j < n[ci]
      nl[at] = l[o[ci] + j]; at += 1; j += 1; m[13] += 1
      return 0 if (at & 4095) == 0 && wassat_counter_poll(m, stop) != 0
    ci += 1; m[19] += 1
    return 0 if (ci & 1023) == 0 && wassat_counter_poll(m, stop) != 0
  m[21] = ci; m[22] = at
  1

# The reconstruction stack uses signs (-1/0/+1), unlike the compact counter's
# truth words. Its prefix is already reconstructed before this entry is undone.
-> wassat_counter_lift_sign(sign, gates, m) (i64[] i64[] i64[]) i64
  g = 0 ## i64
  while g < m[3]
    p = g * 5 ## i64
    a = sign[gates[p + 2]] > 0 ## bool
    b = sign[gates[p + 3]] > 0 ## bool
    op = gates[p] ## i64
    value = op == 1 ? a || b : a && b ## bool
    value = a || (b && sign[gates[p + 4]] > 0) if op == 3
    sign[gates[p + 1]] = value ? 1 : -1
    g += 1
  1

-> wassat_counter_profile(m)
  wassat_prof_note("pre.counter prefix=[m[0]] base=[m[1]] nodes=[m[2]] gates=[m[3]] inputs=[m[4]] bound=[m[5]] groups=[m[11]] cases=[m[10]] checks=[m[9]] scanned=[m[12]] copied=[m[13]] decoded=[m[16]] gate_evaluations=[m[17]] grouped=[m[18]] copied_clauses=[m[19]] polls=[m[8]] scratch_bytes=[m[14]] new_vars=[m[20]] new_clauses=[m[21]] ms=[m[15]]")
