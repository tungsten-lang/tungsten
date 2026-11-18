# Propose a cycle for a compact six-type encoding with partially specified
# calls and types. A selected transition must leave its source, enter its
# destination exactly once and agree with the destination type. Sequence
# labels and any additional constraints are handled by original-CNF completion.

# Return a transition index for a clause guarded by one call and enough type
# bits to determine exactly one of the six legal types. Record the first
# payload literal and the payload length for the caller.
-> wassat_stedman_guard(lits, off, width, n, payload) (i64[] i64 i64 i64 i64[]) i64
  call = 0
  j = 0
  while j < width
    l = lits[off + j]
    if l.abs <= n
      return - 1 if call != 0
      call = l
    j += 1
  return - 1 if call == 0
  u = call.abs - 1
  base = n + 1 + 3 * u
  mask = 0
  value = 0
  count = 0
  j = 0
  while j < width
    l = lits[off + j]
    v = l.abs
    if v >= base && v < base + 3
      bit = 1 << (v - base)
      return - 1 if (mask & bit) != 0
      mask |= bit
      value |= bit if l < 0
    elsif l != call
      payload[0] = l if count == 0
      count += 1
    j += 1
  payload[1] = count
  type = 0
  found = -1
  while type < 6
    if (type & mask) == value
      return - 1 if found >= 0
      found = type
    type += 1
  return - 1 if found < 0
  12 * u + 2 * found + (call < 0 ? 1 : 0)

-> wassat_stedman_cover_table(lits, offs, lens, nc, n, dom, dest, dtype) (i64[] i64[] i64[] i64 i64 i64[] i32[] i8[]) bool
  masks = i8[12 * n]
  signs = i8[12 * n]
  invalid = i8[n]
  payload = i64[2]
  bans = 0
  variant = false
  u = 0
  while u < n
    dom[u] = 4095
    u += 1
  ci = 0
  while ci < nc
    w = lens[ci]
    p = offs[ci]
    ci += 1
    return false if w < 1 || w > 7
    a = lits[p]
    v = a.abs
    if w == 1
      if v <= n
        dom[v - 1] &= a > 0 ? 2730 : 1365
      elsif v <= 4 * n
        u = (v - n - 1) / 3
        b = (v - n - 1) % 3
        k = 0
        while k < 12
          dom[u] &= (4095 ^ (1 << k)) if (((k / 2) >> b) & 1) != (a > 0 ? 1 : 0)
          k += 1
        variant = true
      next
    if w == 2
      b = lits[p + 1]
      return false if a >= 0 || b >= 0
      lo = v < b.abs ? v : b.abs
      return false unless (v - b.abs).abs == 1 && lo >= n + 2 && lo < 4 * n && (lo - n - 2) % 3 == 0
      u = (lo - n - 2) / 3
      return false if invalid[u] != 0
      invalid[u] = 1
      bans += 1
      next
    # Label clauses need not be interpreted to propose calls and types.
    j = 0
    j += 1 while j < w && lits[p + j].abs <= 4 * n
    next if j < w
    g = wassat_stedman_guard(lits, p, w, n, payload)
    return false if g < 0 || payload[1] > 1
    if payload[1] == 0
      dom[g / 12] &= (4095 ^ (1 << (g % 12)))
      next
    l = payload[0]
    v = l.abs
    return false if v <= n
    d = (v - n - 1) / 3
    b = 1 << ((v - n - 1) % 3)
    return false if masks[g] != 0 && dest[g] != d
    return false if (masks[g] & b) != 0
    dest[g] = d
    masks[g] |= b
    signs[g] |= b if l > 0
  return false unless bans == n
  g = 0
  while g < 12 * n
    if (dom[g / 12] & (1 << (g % 12))) != 0
      found = -1
      t = 0
      while t < 6
        if (t & masks[g]) == signs[g]
          return false if found >= 0
          found = t
        t += 1
      return false if found < 0
      dtype[g] = found
      variant = true if masks[g] != 7
    g += 1
  variant

# Single predecessor and successor constraints. If all possible incoming
# arcs come from the same source, that source must go here. A fixed outgoing
# arc excludes every competing incoming arc. Iterate to a fixed point.
-> wassat_stedman_cover_propagate(n, dom, dest, dtype, limit, calls, types) (i64 i64[] i32[] i8[] i64 i8[] i8[]) i64
  owner = i32[n]
  forced = i32[n]
  required = i32[n]
  incoming = i64[n]
  round = 0
  while round < limit
    round += 1
    changed = false
    u = 0
    while u < n
      owner[u] = -1
      forced[u] = -1
      required[u] = -1
      incoming[u] = 0
      u += 1
    u = 0
    while u < n
      mask = dom[u]
      k = 0
      while k < 12
        bit = 1 << k
        if (mask & bit) != 0
          g = 12 * u + k
          v = dest[g]
          pair = 3 << (2 * dtype[g])
          if (dom[v] & pair) == 0
            dom[u] &= (4095 ^ bit)
            changed = true
          else
            if owner[v] == -1
              owner[v] = u
            elsif owner[v] != u
              owner[v] = -2
            incoming[v] |= pair
            if mask == bit
              return 0 if forced[v] >= 0 && forced[v] != u
              forced[v] = u
        k += 1
      return 0 if dom[u] == 0
      u += 1
    v = 0
    while v < n
      return 0 if owner[v] == -1
      if owner[v] >= 0
        u = owner[v]
        return 0 if required[u] >= 0 && required[u] != v
        required[u] = v
      v += 1
    u = 0
    complete = true
    while u < n
      old = dom[u]
      mask = old & incoming[u]
      k = 0
      while k < 12
        bit = 1 << k
        if (mask & bit) != 0
          v = dest[12 * u + k]
          mask &= (4095 ^ bit) if (required[u] >= 0 && required[u] != v) || (forced[v] >= 0 && forced[v] != u)
        k += 1
      return 0 if mask == 0
      complete = false if (mask & (mask - 1)) != 0
      changed = true if mask != old
      dom[u] = mask
      u += 1
    if complete
      # Require a single cycle through all sixes before pinning a model.
      seen = i8[n]
      u = 0
      count = 0
      while seen[u] == 0
        seen[u] = 1
        k = 0
        k += 1 while (1 << k) != dom[u]
        calls[u] = k % 2
        types[u] = k / 2
        u = dest[12 * u + k]
        count += 1
      return (count == n && u == 0) ? round : 0
    return 0 unless changed
  0

-> wassat_stedman_cover_scan(nv, nc, lits, offs, lens, node_cap) (i64 i64 i64[] i64[] i64[] i64)
  return nil if nv > 81920 || nc < 12 || node_cap < 1
  bits = 2
  hint = i64[2]
  while bits <= 16
    div = 4 + bits
    numerator = nv + bits
    n = numerator / div
    bits += 1
    next unless numerator % div == 0 && n >= 5 && n <= 4096
    next if nc < 12 * n || nc > n * (12 * (5 + 2 * (div - 4)) + 5)
    # A wrong arithmetic decomposition typically fails on its first guard.
    ci = 0
    guards = 0
    while ci < 12
      w = lens[ci]
      break if w < 1 || w > 7
      if w >= 3
        break if wassat_stedman_guard(lits, offs[ci], w, n, hint) < 0
        guards += 1
      ci += 1
    next unless ci == 12 && guards >= 2
    dom = i64[n]
    dest = i32[12 * n]
    dtype = i8[12 * n]
    next unless wassat_stedman_cover_table(lits, offs, lens, nc, n, dom, dest, dtype)
    calls = i8[n]
    types = i8[n]
    limit = node_cap < 256 ? node_cap : 256
    rounds = wassat_stedman_cover_propagate(n, dom, dest, dtype, limit, calls, types)
    if rounds > 0
      return { "calls": calls, "types": types, "n": n, "rounds": rounds }
  nil
