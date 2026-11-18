# Bounded token-jump search, recovered from repeated graph blocks.
# A proposed path is only a partial assignment. Unit completion and every
# original clause must succeed before a model can be returned. UNSAT additionally
# requires the full original-clause transition contract and exhausted search.
use atomic_stop
use reconfiguration_verify

WASSAT_RECONF_MAX_VERTICES = 512
WASSAT_RECONF_MAX_STATES = 128
WASSAT_RECONF_NODE_CAP = 131072

fn wassat_reconf_pop(x) (i64) i64
  ccall_nobox("__w_bit_ctpop_u64", x) ## i64

fn wassat_reconf_ctz(x) (i64) i64
  ccall_nobox("__w_bit_cttz_u64", x) ## i64

-> wassat_reconf_stop(m, stop, deadline) (i64[] i64[] i64) i64
  return 1 if m[2] != 0
  m[12] += 1
  if wassat_stop_load(stop) != 0
    m[2] = 1
  elsif deadline > 0 && clock_ms() >= deadline
    m[2] = 2
  m[2] != 0 ? 1 : 0

-> wassat_reconf_prepare(lits, offs, lens, nv, nc, units, starts, initial, goal, adj, m, stop, deadline) (i64[] i64[] i64[] i64 i64 i8[] i64[] i64[] i64[] i64[] i64[] i64[] i64) i64
  return 0 if nv < 16 || nv > 750000 || nc < 16 || nc > 3000000
  return 0 if offs.size < nc || lens.size < nc || lits.size > 32000000
  one = 1 ## i64
  ci = 0
  while ci < nc
    return 0 if (ci & 1023) == 0 && wassat_reconf_stop(m, stop, deadline) != 0
    off = offs[ci]
    size = lens[ci]
    return 0 if size < 1 || size > 2048 || off < 0 || off > lits.size || size > lits.size - off
    j = 0
    while j < size
      lit = lits[off + j]
      v = lit < 0 ? 0 - lit : lit
      return 0 if v < 1 || v > nv
      j += 1
    if size == 1
      lit = lits[off]
      v = lit < 0 ? 0 - lit : lit
      sign = lit > 0 ? 1 : 0 - 1
      return 0 if units[v] != 0 && units[v] != sign
      units[v] = sign
    ci += 1
  # The initial contiguous negative-binary prefix describes one graph.
  edges = 0
  n = 0
  while edges < nc && lens[edges] == 2
    off = offs[edges]
    u = lits[off]
    v = lits[off + 1]
    break if u >= 0 || v >= 0
    u = 0 - u
    v = 0 - v
    return 0 if u == v || u > WASSAT_RECONF_MAX_VERTICES || v > WASSAT_RECONF_MAX_VERTICES
    n = u if u > n
    n = v if v > n
    edges += 1
    return 0 if edges > 65536
  return 0 if n < 4 || edges < n || edges >= nc
  words = (n + 63) / 64
  first = lits[offs[0]]
  second = lits[offs[0] + 1]
  count = 0
  ci = 0
  while ci < nc
    return 0 if (ci & 255) == 0 && wassat_reconf_stop(m, stop, deadline) != 0
    if lens[ci] == 2
      off = offs[ci]
      delta = first - lits[off]
      if delta >= 0 && delta <= nv - n && lits[off + 1] == second - delta && edges <= nc - ci
        j = 0
        while j < edges
          return 0 if (j & 1023) == 0 && wassat_reconf_stop(m, stop, deadline) != 0
          break if lens[ci + j] != 2
          a = offs[j]
          b = offs[ci + j]
          break if lits[b] != lits[a] - delta || lits[b + 1] != lits[a + 1] - delta
          j += 1
        if j == edges
          return 0 if count >= WASSAT_RECONF_MAX_STATES
          return 0 if count > 0 && delta < starts[count - 1] + n
          starts[count] = delta
          count += 1
          ci += edges - 1
    ci += 1
  return 0 if count < 2 || starts[0] != 0
  # Addition and removal indicators in the first transition recover the
  # fixed starting set. Every vertex needs one of the two negative units.
  first_row = 0
  second_row = 0
  ci = edges
  while ci < nc && second_row == 0
    return 0 if (ci & 255) == 0 && wassat_reconf_stop(m, stop, deadline) != 0
    if lens[ci] == n
      off = offs[ci]
      base = lits[off]
      j = 0
      while j < n && lits[off + j] == base + j
        j += 1
      if base > 0 && j == n
        if first_row == 0
          first_row = base
        else
          second_row = base
    ci += 1
  return 0 if first_row != n + 1 || second_row < first_row + n || second_row + n - 1 > nv
  initial_count = 0
  goal_count = 0
  v = 0
  while v < n
    a = units[first_row + v]
    b = units[second_row + v]
    return 0 if a > 0 || b > 0 || (a == 0) == (b == 0)
    word = v >> 6
    mask = one << (v & 63) ## i64
    if a < 0
      initial[word] = (initial[word] | mask) ## i64
      initial_count += 1
    g = units[starts[count - 1] + v + 1]
    return 0 if g == 0
    if g > 0
      goal[word] = (goal[word] | mask) ## i64
      goal_count += 1
    v += 1
  return 0 if initial_count < 1 || initial_count != goal_count
  j = 0
  while j < edges
    off = offs[j]
    u = 0 - lits[off] - 1
    v = 0 - lits[off + 1] - 1
    adj[u * words + (v >> 6)] |= one << (v & 63)
    adj[v * words + (u >> 6)] |= one << (u & 63)
    return 0 if (initial[u >> 6] & (one << (u & 63))) != 0 && (initial[v >> 6] & (one << (v & 63))) != 0
    return 0 if (goal[u >> 6] & (one << (u & 63))) != 0 && (goal[v >> 6] & (one << (v & 63))) != 0
    j += 1
  m[1] = 1
  m[3] = n
  m[4] = count
  m[5] = edges
  n

-> wassat_reconf_before(a, b, depth, distance, states, words) (i64 i64 i64[] i64[] i64[] i64) bool
  fa = depth[a] + distance[a]
  fb = depth[b] + distance[b]
  return fa < fb if fa != fb
  return distance[a] < distance[b] if distance[a] != distance[b]
  # Compare the packed state as an unsigned integer, high word first.
  one = 1 ## i64
  sign = one << 63 ## i64
  j = words - 1
  while j >= 0
    x = states[a * words + j] ^ sign ## i64
    y = states[b * words + j] ^ sign ## i64
    return x < y if x != y
    j -= 1
  false

-> wassat_reconf_up(heap, positions, depth, distance, states, words, at) (i64[] i64[] i64[] i64[] i64[] i64 i64) i64
  node = heap[at]
  while at > 0
    above = (at - 1) / 2
    other = heap[above]
    break unless wassat_reconf_before(node, other, depth, distance, states, words)
    heap[at] = other
    positions[other] = at
    at = above
  heap[at] = node
  positions[node] = at
  0

-> wassat_reconf_hash(state, words, mask) (i64[] i64 i64) i64
  h = 2166136261 ## i64
  j = 0
  while j < words
    h ^= state[j]
    h *= 16777619
    h ^= h >> 33
    j += 1
  h & mask

-> wassat_reconf_search(initial, goal, adj, states, parents, n, horizon, cap, m, stop, deadline) (i64[] i64[] i64[] i64[] i64[] i64 i64 i64 i64[] i64[] i64) i64
  m[24] = 0
  return 0 - 1 if n < 1 || n > WASSAT_RECONF_MAX_VERTICES || horizon < 1 || horizon > WASSAT_RECONF_MAX_STATES
  return 0 - 1 if cap < 2 || cap > WASSAT_RECONF_NODE_CAP || (cap & (cap - 1)) != 0
  words = (n + 63) / 64
  return 0 - 1 if initial.size < words || goal.size < words || adj.size < n * words
  return 0 - 1 if states.size < cap * words || parents.size < cap
  return 0 - 1 if wassat_reconf_stop(m, stop, deadline) != 0
  one = 1 ## i64
  depth = i64[cap]
  distance = i64[cap]
  heap = i64[cap]
  positions = i64[cap]
  table = i64[cap * 2]
  scratch = i64[words]
  blocked_once = i64[words]
  blocked_twice = i64[words]
  j = 0
  while j < words
    states[j] = initial[j]
    scratch[j] = initial[j]
    distance[0] += wassat_reconf_pop(goal[j] & (goal[j] ^ initial[j]))
    j += 1
  parents[0] = 0 - 1
  table[wassat_reconf_hash(scratch, words, cap * 2 - 1)] = 1
  used = 1
  heap_count = 1
  m[8] = 1
  m[23] = distance[0]
  while heap_count > 0
    return 0 - 1 if (m[6] & 63) == 0 && wassat_reconf_stop(m, stop, deadline) != 0
    node = heap[0]
    positions[node] = 0 - 1
    heap_count -= 1
    if heap_count > 0
      child = heap[heap_count]
      at = 0
      while at * 2 + 1 < heap_count
        below = at * 2 + 1
        if below + 1 < heap_count && wassat_reconf_before(heap[below + 1], heap[below], depth, distance, states, words)
          below += 1
        other = heap[below]
        break unless wassat_reconf_before(other, child, depth, distance, states, words)
        heap[at] = other
        positions[other] = at
        at = below
      heap[at] = child
      positions[child] = at
    g = depth[node]
    h = distance[node]
    if h == 0
      m[23] = 0
      return node if g == horizon
      # This completion currently requires one distinct move per encoded
      # state. A shorter path is not silently padded with repeated states.
      return 0 - 1
    if g + h <= horizon && g < horizon
      m[6] += 1
      m[23] = h if h < m[23]
      j = 0
      while j < words
        scratch[j] = states[node * words + j]
        blocked_once[j] = 0
        blocked_twice[j] = 0
        j += 1
      # A token jump removes one token. Vertices attacked by two or more
      # occupied vertices cannot become independent in a single jump.
      word = 0
      while word < words
        occupied_bits = scratch[word] ## i64
        while occupied_bits != 0
          bit = wassat_reconf_ctz(occupied_bits)
          u = word * 64 + bit
          return 0 - 1 if u >= n
          j = 0
          while j < words
            neighbors = adj[u * words + j] ## i64
            blocked_twice[j] |= blocked_once[j] & neighbors
            blocked_once[j] |= neighbors
            j += 1
          occupied_bits = (occupied_bits & (occupied_bits - one)) ## i64
        word += 1
      v = 0
      while v < n
        vw = v >> 6
        vb = one << (v & 63) ## i64
        occupied = scratch[vw] & vb ## i64
        if occupied == 0 && (blocked_twice[vw] & vb) == 0
          conflict = 0 - 1
          j = 0
          while j < words
            blocked = scratch[j] & adj[v * words + j] ## i64
            m[11] += 1
            if blocked != 0
              rest = blocked & (blocked - one) ## i64
              if conflict >= 0 || rest != 0
                conflict = 0 - 2
                break
              conflict = j * 64 + wassat_reconf_ctz(blocked)
            j += 1
          if conflict >= 0 - 1
            u = 0
            limit = n
            if conflict >= 0
              u = conflict
              limit = u + 1
            while u < limit
              uw = u >> 6
              ub = one << (u & 63) ## i64
              occupied = scratch[uw] & ub ## i64
              if occupied != 0
                ng = g + 1
                nh = h
                remove_goal = goal[uw] & ub ## i64
                add_goal = goal[vw] & vb ## i64
                nh += 1 if remove_goal != 0
                nh -= 1 if add_goal != 0
                m[7] += 1
                return 0 - 1 if (m[7] & 255) == 0 && wassat_reconf_stop(m, stop, deadline) != 0
                if ng + nh <= horizon
                  scratch[uw] = (scratch[uw] ^ ub) ## i64
                  scratch[vw] = (scratch[vw] ^ vb) ## i64
                  slot = wassat_reconf_hash(scratch, words, cap * 2 - 1)
                  found = 0 - 1
                  while table[slot] != 0
                    m[10] += 1
                    return 0 - 1 if (m[10] & 1023) == 0 && wassat_reconf_stop(m, stop, deadline) != 0
                    candidate = table[slot] - 1
                    j = 0
                    while j < words && states[candidate * words + j] == scratch[j]
                      j += 1
                    if j == words
                      found = candidate
                      break
                    slot = (slot + 1) & (cap * 2 - 1)
                  if found < 0
                    if used >= cap
                      m[2] = 3
                      return 0 - 1
                    found = used
                    used += 1
                    m[8] = used
                    table[slot] = found + 1
                    j = 0
                    while j < words
                      states[found * words + j] = scratch[j]
                      j += 1
                    depth[found] = horizon + 1
                    distance[found] = nh
                    positions[found] = 0 - 1
                  if ng < depth[found]
                    depth[found] = ng
                    parents[found] = node
                    at = positions[found]
                    if at < 0
                      at = heap_count
                      heap[at] = found
                      positions[found] = at
                      heap_count += 1
                      m[9] = heap_count if heap_count > m[9]
                    z = wassat_reconf_up(heap, positions, depth, distance, states, words, at)
                  scratch[vw] = (scratch[vw] ^ vb) ## i64
                  scratch[uw] = (scratch[uw] ^ ub) ## i64
              u += 1
        v += 1
  m[24] = 1
  0 - 1

# A bounded simple-path walk supplies SAT candidates; full clause replay is mandatory.
-> wassat_reconf_walk(initial, goal, adj, states, parents, n, horizon, m, stop, deadline, seed) (i64[] i64[] i64[] i64[] i64[] i64 i64 i64[] i64[] i64 i64) i64
  words = (n + 63) / 64
  return 0 - 1 if horizon < 2 || horizon >= 128 || states.size < (horizon + 1) * words || parents.size <= horizon
  rng = seed ## i64
  one = 1 ## i64
  trial = 0
  while trial < 10000
    return 0 - 1 if wassat_reconf_stop(m, stop, deadline) != 0
    j = 0
    while j < words
      states[j] = initial[j]
      j += 1
    parents[0] = -1
    depth = 0
    while depth < horizon
      rem = horizon - depth - 1
      target = rem / 3
      target = 7 if target > 7
      total = 0 ## i64
      chosen_u = -1
      chosen_v = -1
      v = 0
      while v < n
        return 0 - 1 if (v & 15) == 0 && wassat_reconf_stop(m, stop, deadline) != 0
        vw = v >> 6
        vb = one << (v & 63) ## i64
        if (states[depth * words + vw] & vb) == 0
          conflict = -1
          j = 0
          while j < words
            blocked = states[depth * words + j] & adj[v * words + j] ## i64
            if blocked != 0
              if conflict >= 0 || (blocked & (blocked - 1)) != 0
                conflict = -2
                break
              conflict = j * 64 + wassat_reconf_ctz(blocked)
            j += 1
          if conflict >= -1
            u = conflict >= 0 ? conflict : 0
            limit = conflict >= 0 ? conflict + 1 : n
            while u < limit
              return 0 - 1 if (u & 63) == 0 && wassat_reconf_stop(m, stop, deadline) != 0
              uw = u >> 6
              ub = one << (u & 63) ## i64
              if (states[depth * words + uw] & ub) != 0
                dist = 0
                j = 0
                while j < words
                  candidate = states[depth * words + j]
                  candidate ^= ub if j == uw
                  candidate |= vb if j == vw
                  dist += wassat_reconf_pop(goal[j] & (goal[j] ^ candidate))
                  j += 1
                if dist <= rem && (dist != 0 || rem == 0)
                  prior = 0
                  repeat = 0
                  while prior <= depth && repeat == 0
                    j = 0
                    while j < words
                      candidate = states[depth * words + j]
                      candidate ^= ub if j == uw
                      candidate |= vb if j == vw
                      break if candidate != states[prior * words + j]
                      j += 1
                    repeat = 1 if j == words
                    prior += 1
                  if repeat == 0
                    diff = dist - target
                    diff = -diff if diff < 0
                    weight = 100 / ((diff + 1) * (diff + 1))
                    weight = 1 if weight == 0
                    total += weight
                    rng = (rng * 48271) % 2147483647
                    if rng % total < weight
                      chosen_u = u
                      chosen_v = v
              u += 1
        v += 1
      break if chosen_u < 0
      j = 0
      while j < words
        states[(depth + 1) * words + j] = states[depth * words + j]
        j += 1
      states[(depth + 1) * words + (chosen_u >> 6)] ^= one << (chosen_u & 63)
      states[(depth + 1) * words + (chosen_v >> 6)] |= one << (chosen_v & 63)
      parents[depth + 1] = depth
      depth += 1
      m[7] += 1
      return 0 - 1 if wassat_reconf_stop(m, stop, deadline) != 0
    if depth == horizon
      m[8] = horizon + 1
      return horizon
    trial += 1
  0 - 1

-> wassat_reconf_complete(lits, offs, lens, nv, nc, values, m, stop, deadline) (i64[] i64[] i64[] i64 i64 i8[] i64[] i64[] i64) i64
  pass = 0
  while pass < 16
    changed = 0
    ci = 0
    while ci < nc
      return 0 if (ci & 255) == 0 && wassat_reconf_stop(m, stop, deadline) != 0
      off = offs[ci]
      size = lens[ci]
      j = 0
      sat = false
      count = 0
      last = 0
      while j < size
        lit = lits[off + j]
        v = lit < 0 ? 0 - lit : lit
        a = values[v]
        if a == 0
          count += 1
          last = lit
        elsif (a > 0) == (lit > 0)
          sat = true
          break
        j += 1
      unless sat
        return 0 if count == 0
        if count == 1
          v = last < 0 ? 0 - last : last
          values[v] = last > 0 ? 1 : 0 - 1
          changed += 1
      ci += 1
    m[13] += 1
    m[14] += changed
    break if changed == 0
    pass += 1
  # Unforced auxiliary variables default false; this is only a candidate.
  ci = 0
  while ci < nc
    return 0 if (ci & 255) == 0 && wassat_reconf_stop(m, stop, deadline) != 0
    off = offs[ci]
    j = 0
    sat = false
    while j < lens[ci]
      lit = lits[off + j]
      v = lit < 0 ? 0 - lit : lit
      m[16] += 1
      sat = true if (values[v] > 0) == (lit > 0)
      j += 1
    return 0 unless sat
    m[15] += 1
    ci += 1
  1

-> wassat_reconf_model(lits, offs, lens, nv, nc, m, stop, res, base, deadline) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64 i64) i64
  one = 1 ## i64
  return 0 if nv < 16 || nv > 750000 || nc < 16 || nc > 3000000
  return 0 if wassat_reconf_stop(m, stop, deadline) != 0
  values = i8[nv + 1]
  starts = i64[WASSAT_RECONF_MAX_STATES]
  initial = i64[8]
  goal = i64[8]
  adj = i64[WASSAT_RECONF_MAX_VERTICES * 8]
  n = wassat_reconf_prepare(lits, offs, lens, nv, nc, values, starts, initial, goal, adj, m, stop, deadline)
  m[20] = clock_ms() - m[17]
  return 0 if n == 0
  words = (n + 63) / 64
  cap = WASSAT_RECONF_NODE_CAP
  states = i64[cap * words]
  parents = i64[cap]
  began = clock_ms()
  node = wassat_reconf_search(initial, goal, adj, states, parents, n, m[4], cap, m, stop, deadline)
  m[19] = clock_ms() - began
  if node < 0 && m[24] == 1 && wassat_reconf_stop(m, stop, deadline) == 0
    began = clock_ms()
    certified = wassat_rc_verify(lits, offs, lens, nv, nc, n, starts, initial, goal, m, stop, deadline)
    m[29] = clock_ms() - began
    return -1 if certified == 1
    return 0
  walk = node < 0 && m[2] == 0
  retry = 0
  checked = 0
  while retry < 8
    return 0 if wassat_reconf_stop(m, stop, deadline) != 0
    if retry > 0
      v = 0
      while v <= nv
        return 0 if (v & 4095) == 0 && wassat_reconf_stop(m, stop, deadline) != 0
        values[v] = 0
        v += 1
      recognized = wassat_reconf_prepare(lits, offs, lens, nv, nc, values, starts, initial, goal, adj, m, stop, deadline)
      return 0 if recognized != n
    if walk
      began = clock_ms()
      node = wassat_reconf_walk(initial, goal, adj, states, parents, n, m[4], m, stop, deadline, retry + 1)
      m[19] += clock_ms() - began
    return 0 if node < 0
    step = m[4] - 1
    compatible = 1
    while step >= 0 && compatible != 0
      return 0 if node < 0 || node >= m[8]
      v = 0
      while v < n
        variable = starts[step] + v + 1
        sign = 0 - 1
        sign = 1 if (states[node * words + (v >> 6)] & (one << (v & 63))) != 0
        if values[variable] != 0 && values[variable] != sign
          compatible = 0
          break
        values[variable] = sign
        v += 1
      node = parents[node]
      step -= 1
    return 0 if compatible != 0 && node != 0
    if compatible != 0
      began = clock_ms()
      checked = wassat_reconf_complete(lits, offs, lens, nv, nc, values, m, stop, deadline)
      m[21] += clock_ms() - began
      break if checked != 0
    return 0 unless walk
    return 0 if wassat_reconf_stop(m, stop, deadline) != 0
    m[30] += 1
    retry += 1
  return 0 if checked == 0
  v = 1
  while v <= nv
    return 0 if (v & 4095) == 0 && wassat_reconf_stop(m, stop, deadline) != 0
    res[base + v] = values[v] > 0 ? 1 : 0
    v += 1
  m[18] = clock_ms()
  return 0 if wassat_reconf_stop(m, stop, deadline) != 0
  m[0] = 1
  1

-> wassat_reconf_run(lits, offs, lens, nv, nc, m, stop, res, base, wall_ms) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64 i64) i64
  m[17] = clock_ms()
  deadline = wall_ms > 0 ? m[17] + wall_ms : 0
  found = wassat_reconf_model(lits, offs, lens, nv, nc, m, stop, res, base, deadline)
  m[18] = clock_ms()
  found

# Conservative full-cap scratch and result budget, including array headers.
-> wassat_reconf_bytes(nv) (i64) i64
  WASSAT_RECONF_NODE_CAP * 15 * 8 + (nv + 8) * 9 + 40000 + 1048576

-> wassat_reconf_prefix(lits, offs, lens, nv, nc) (i64[] i64[] i64[] i64 i64) i64
  return 0 if nv < 64 || nv > 750000 || nc < 1000 || nc > 3000000
  return 0 if offs.size < nc || lens.size < nc || lits.size < 2
  ci = 0
  largest = 0
  while ci < 512
    if lens[ci] != 2
      return 1 if ci >= largest && largest >= 4
      return 0
    off = offs[ci]
    return 0 if off < 0 || off > lits.size - 2
    u = lits[off]
    v = lits[off + 1]
    if u >= 0 || v >= 0
      return 1 if ci >= largest && largest >= 4
      return 0
    return 0 if u < 0 - WASSAT_RECONF_MAX_VERTICES || v < 0 - WASSAT_RECONF_MAX_VERTICES
    largest = -u if -u > largest
    largest = -v if -v > largest
    ci += 1
  1

# Cheap nomination for the early scout and expanded-size admission.
# The full decoder still checks every premise and original clause.
-> wassat_reconf_large_prefix(lits, offs, lens, nc) (i64[] i64[] i64[] i64) i64
  if offs.size < nc || lens.size < nc
    return 0
  edges = 0
  n = 0
  while edges < nc && edges < 65536 && lens[edges] == 2
    off = offs[edges]
    return 0 if off < 0 || off > lits.size - 2
    u = lits[off]; v = lits[off + 1]
    break if u >= 0 || v >= 0
    u = -u; v = -v
    return 0 if u == v || u > WASSAT_RECONF_MAX_VERTICES || v > WASSAT_RECONF_MAX_VERTICES
    n = u if u > n
    n = v if v > n
    edges += 1
  return 0 if n < 4 || edges < n || edges >= nc || edges >= 65536
  ci = edges
  end = edges + 65536
  end = nc if end > nc
  checks = 0
  while ci < end
    if lens[ci] == n
      off = offs[ci]
      return 0 if off < 0 || off > lits.size - n
      base = lits[off]
      if base > 0
        j = 0
        while j < n && lits[off + j] == base + j
          checks += 1
          return 0 if checks > 65536
          j += 1
        return base == n + 1 ? 1 : 0 if j == n
    ci += 1
  0

-> wassat_reconf_plan(formula, workers, cdcl_arenas, sls_arenas)
  mode = env("WASSAT_RECONFIGURATION")
  return nil if mode == "0" || formula == nil
  return nil if env("WASSAT_ARMS") != nil && mode != "1"
  return nil if System.cpu_count <= workers || System.physical_memory_bytes <= 0
  return nil unless formula.has_key?("flat_ncl")
  nv = formula["nvars"]
  nc = formula["flat_ncl"]
  return nil if nv < 16 || nv > 750000 || nc < 16 || nc > 3000000
  return nil if formula["flat_nlits"] > 8000000
  if mode != "1"
    return nil if wassat_reconf_prefix(formula["flat_lits"], formula["flat_offs"], formula["flat_lens"], nv, nc) == 0
    if nv > 500000 || nc > 1500000 || formula["flat_lits"].size > 8000000
      return nil if wassat_reconf_large_prefix(formula["flat_lits"], formula["flat_offs"], formula["flat_lens"], nc) == 0
  bytes = wassat_reconf_bytes(nv) + wassat_rc_verify_bytes(nc)
  return nil unless wassat_race_memory_fits?(formula, cdcl_arenas, sls_arenas, 1, bytes)
  m = i64[32]
  m[22] = bytes
  { "meta": m }

-> wassat_reconf_arm(lits, offs, lens, nv, nc, m, stop, res) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[]) i64
  found = wassat_reconf_run(lits, offs, lens, nv, nc, m, stop, res, 0, 2000)
  m[18] = clock_ms()
  res[nv + 6] = m[17]
  res[nv + 5] = m[18]
  if found != 0 && wassat_stop_load(stop) == 0
    z = ccall("__w_arr_store_rel", res, 0, found)
    won = wassat_stop_publish(stop, found)
    return found
  0

-> wassat_reconf_start(formula, plan, stop, res)
  lits = formula["flat_lits"]; offs = formula["flat_offs"]; lens = formula["flat_lens"]
  nv = formula["nvars"]; nc = formula["flat_ncl"]; m = plan["meta"]
  Thread.new -> wassat_reconf_arm(lits, offs, lens, nv, nc, m, stop, res)

-> wassat_reconf_profile(plan, status)
  m = plan["meta"]
  wassat_prof_note("scout.reconfiguration status=[status] recognized=[m[1]] stopped=[m[2]] vertices=[m[3]] stages=[m[4]] edges=[m[5]] expanded=[m[6]] generated=[m[7]] states=[m[8]] peak_heap=[m[9]] hash_probes=[m[10]] graph_words=[m[11]] polls=[m[12]] lift_passes=[m[13]] lift_assigned=[m[14]] replay_clauses=[m[15]] replay_literals=[m[16]] prepare_ms=[m[20]] search_ms=[m[19]] lift_ms=[m[21]] scratch_bytes=[m[22]] best_missing=[m[23]] exhausted=[m[24]] verified=[m[25]] verify_probes=[m[26]] verify_clauses=[m[27]] amo_pairs=[m[28]] verify_ms=[m[29]] rejected=[m[30]] ms=[m[18] - m[17]]")
