# Weighted finite-domain search over sparse interference incidences. All
# arrays are allocated once by the caller and reused across moves/restarts.
# Only selected values can violate a pair; the active list follows their
# incremental counts, and costs retain the weights of those same pairs.
use domain_sparse_decode

-> wassat_sparse_domain_refresh(b, sol, counts, bad, pos, st) (i64 i32[] i32[] i32[] i32[] i64[]) i64
  active = counts[sol[b]] > 0
  if active && pos[b] == 0
    bad[st[0]] = b; st[0] += 1; pos[b] = st[0]
  elsif !active && pos[b] != 0
    idx = pos[b]-1; st[0] -= 1; last = bad[st[0]]; bad[idx] = last; pos[last] = idx+1; pos[b] = 0
  0

-> wassat_sparse_domain_trial(owner, values, first, allowed, heads, edges, ids, sol, counts, costs, weights, bad, pos, st, m, stop, nv, nb, seed, steps, deadline) (i32[] i32[] i32[] i8[] i32[] i32[] i32[] i32[] i32[] i64[] i32[] i32[] i32[] i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
  i = 0
  while i < weights.size
    return 0 if (i & 4095) == 0 && wassat_sparse_domain_poll(m,stop,deadline) != 0
    weights[i] = 1; m[19] += 1; i += 1
  v = 0
  while v <= nv
    return 0 if (v & 4095) == 0 && wassat_sparse_domain_poll(m,stop,deadline) != 0
    counts[v] = 0; costs[v] = 0; v += 1
  one = 1 ## i64
  rng = seed ## i64
  mask = (one<<57)-one ## i64
  b = 0
  while b < nb
    return 0 if wassat_sparse_domain_poll(m,stop,deadline) != 0
    pos[b] = 0
    rng ^= rng<<13; rng ^= (rng>>7)&mask; rng ^= rng<<17
    at = first[b]; choices = 0
    while at < first[b+1]
      choices += allowed[values[at]]; at += 1
    pick = (rng & 2147483647)%choices; at = first[b]
    while at < first[b+1]
      v = values[at]
      if allowed[v] != 0
        if pick == 0
          sol[b] = v
          break
        pick -= 1
      at += 1
    b += 1
  b = 0
  while b < nb
    return 0 if wassat_sparse_domain_poll(m,stop,deadline) != 0
    u = sol[b]; p = heads[u]
    while p < heads[u+1]
      return 0 if (p & 16383) == 0 && wassat_sparse_domain_poll(m,stop,deadline) != 0
      v = edges[p]; counts[v] += 1; costs[v] += 1; p += 1
    b += 1
  st[0] = 0; st[1] = 0; b = 0
  while b < nb
    st[1] += counts[sol[b]]
    z = wassat_sparse_domain_refresh(b,sol,counts,bad,pos,st); b += 1
  st[1] /= 2
  iteration = 0
  while iteration < steps
    return 0 if (iteration & 255) == 0 && wassat_sparse_domain_poll(m,stop,deadline) != 0
    m[13] = st[1] if st[1] < m[13]
    return 1 if st[1] == 0
    iteration += 1; m[7] += 1; m[22] = iteration
    rng ^= rng<<13; rng ^= (rng>>7)&mask; rng ^= rng<<17
    noise = (rng & 63) == 0; best_b = -1; best_v = 0; best_delta = (1 << 60) ## i64
    ties = 0
    i = 0
    while i < st[0]
      b = bad[i]; u = sol[b]; at = first[b]
      while at < first[b+1]
        v = values[at]
        if v != u && allowed[v] != 0
          delta = costs[v]-costs[u]; m[10] += 1
          return 0 if (m[10] & 65535) == 0 && wassat_sparse_domain_poll(m,stop,deadline) != 0
          if noise || delta <= best_delta
            if !noise && delta < best_delta
              best_delta = delta; ties = 0
            ties += 1
            rng ^= rng<<13; rng ^= (rng>>7)&mask; rng ^= rng<<17
            if (rng & 2147483647)%ties == 0
              best_b = b; best_v = v
        at += 1
      i += 1
    return 0 if best_b < 0
    if best_delta >= 0 && !noise
      m[9] += 1; i = 0
      while i < st[0]
        b = bad[i]; u = sol[b]; p = heads[u]
        while p < heads[u+1]
          v = edges[p]; m[23] += 1
          return 0 if (m[23] & 65535) == 0 && wassat_sparse_domain_poll(m,stop,deadline) != 0
          if v > u && sol[owner[v]-1] == v
            weights[ids[p]] += 1; costs[u] += 1; costs[v] += 1; m[11] += 2
          p += 1
        i += 1
    else
      b = best_b; u = sol[b]; v = best_v; st[1] += counts[v]-counts[u]
      p = heads[u]
      while p < heads[u+1]
        w = edges[p]; counts[w] -= 1; costs[w] -= weights[ids[p]]
        c = owner[w]-1; z = wassat_sparse_domain_refresh(c,sol,counts,bad,pos,st)
        m[11] += 1; p += 1
        return 0 if (m[11] & 65535) == 0 && wassat_sparse_domain_poll(m,stop,deadline) != 0
      p = heads[v]
      while p < heads[v+1]
        w = edges[p]; counts[w] += 1; costs[w] += weights[ids[p]]
        c = owner[w]-1; z = wassat_sparse_domain_refresh(c,sol,counts,bad,pos,st)
        m[11] += 1; p += 1
        return 0 if (m[11] & 65535) == 0 && wassat_sparse_domain_poll(m,stop,deadline) != 0
      sol[b] = v; z = wassat_sparse_domain_refresh(b,sol,counts,bad,pos,st); m[8] += 1
  0
