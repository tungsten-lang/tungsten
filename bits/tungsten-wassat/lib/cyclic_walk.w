# Circular graph-label swap proposals. All search buffers are fixed and reused.
# Explicit machine locals keep the bounded integer score kernel unboxed.
use cyclic_repair

# Three slope changes describe each circular triangular edge penalty.
# Reuse the difference arrays for the finished weighted/unweighted scores.
# The graph is simple and 0 < width <= n/2. At p-width, p, p+width the
# discrete slope changes by +1, -2, +1 (the endpoints may coincide).
-> wassat_cycle_scores(n, width, u, left, right, heads, occ, perm, weights,
                       scores, plain, adjacent) (i64 i64 i64 i32[] i32[] i32[] i32[] i32[] i32[] i64[] i64[] i32[]) i64
  label = (0) ## i64
  while label < n
    scores[label] = 0
    plain[label] = 0
    adjacent[label] = 0
    label += 1
  value = (0) ## i64
  raw_value = (0) ## i64
  slope = (0) ## i64
  raw_slope = (0) ## i64
  at = (heads[u]) ## i64
  while at < heads[u + 1]
    e = (occ[at]) ## i64
    z = (left[e] ^ right[e] ^ u) ## i64
    p = (perm[z]) ## i64
    w = (weights[e]) ## i64
    adjacent[z] = e + 1
    c = (wassat_cycle_cost(0, p, width, n)) ## i64
    d = (wassat_cycle_cost(1, p, width, n) - c) ## i64
    value += w * c
    raw_value += c
    slope += w * d
    raw_slope += d
    lo = (p - width) ## i64
    lo += n if lo < 0
    hi = (p + width) ## i64
    hi -= n if hi >= n
    scores[lo] += w
    scores[p] -= 2 * w
    scores[hi] += w
    plain[lo] += 1
    plain[p] -= 2
    plain[hi] += 1
    at += 1
  scores[0] = value
  plain[0] = raw_value
  label = 1
  while label < n
    value += slope
    raw_value += raw_slope
    slope += scores[label]
    raw_slope += plain[label]
    scores[label] = value
    plain[label] = raw_value
    label += 1
  1

# Score every possible swap target against the same source label in one pass.
# Reuse tails of the two score buffers; the circular sweep owns their prefixes.
-> wassat_cycle_target_scores(n, ne, width, u, left, right, perm, weights,
                             penalty, scores, plain) (i64 i64 i64 i64 i32[] i32[] i32[] i32[] i32[] i64[] i64[]) i64
  label = (perm[u]) ## i64
  v = 0
  while v < n
    scores[n + v] = 0
    plain[n + v] = 0
    plain[2 * n + v] = wassat_cycle_cost(label, (perm[v] ## i64), width, n)
    v += 1
  e = 0
  while e < ne
    a = (left[e]) ## i64
    b = (right[e]) ## i64
    da = plain[2 * n + b] - penalty[e]
    db = plain[2 * n + a] - penalty[e]
    scores[n + a] += da * weights[e]
    scores[n + b] += db * weights[e]
    plain[n + a] += da
    plain[n + b] += db
    e += 1
  1

-> wassat_cycle_trial(n, ne, width, left, right, heads, occ, perm, tabu,
                      weights, penalty, bad, rng, m, stop, deadline,
                      restarts, steps) (i64 i64 i64 i32[] i32[] i32[] i32[] i32[] i32[] i32[] i32[] i32[] i64[] i64[] i64[] i64 i64 i64) i64
  wassat_cycle_trial_mode(n, ne, width, left, right, heads, occ, perm, tabu, weights, penalty, bad, rng, m, stop, deadline, restarts, steps, 0, m)

-> wassat_cycle_trial_mode(n, ne, width, left, right, heads, occ, perm, tabu,
                      weights, penalty, bad, rng, m, stop, deadline,
                      restarts, steps, allow_repair, repair) (i64 i64 i64 i32[] i32[] i32[] i32[] i32[] i32[] i32[] i32[] i32[] i64[] i64[] i64[] i64 i64 i64 i64 i64[]) i64
  # The optional bound verifier has finished using slot 23 as a poll cursor.
  m[23] = 0
  return 0 if wassat_perm_stop(m, stop, deadline) != 0
  use_sweep = env("WASSAT_CYCLIC_SWEEP") != "0" && width > 0 && width <= n / 2
  size = (use_sweep ? n : 0) ## i64
  # Very sparse graphs have too few repeated distances to repay the n-label pass.
  use_targets = use_sweep && ne >= n && env("WASSAT_CYCLIC_TARGET_CACHE") != "0"
  scores = i64[use_targets ? 2 * size : size]
  plain = i64[use_targets ? 3 * size : size]
  adjacent = i32[size]
  use_repair = allow_repair == 1 && 2 * (n - 2 * width) + 1 >= n
  repair_limit = (n / 32) ## i64
  repair[23] = 1000000000 if use_repair
  best_size = (use_repair ? n : 0) ## i64
  best_perm = i32[best_size]
  m[13] = 1000000000
  # Bound work between polls even for a dense graph or a high-degree hub.
  # One swap scores at most n*max_degree + 2*edges incident edge updates.
  max_degree = (0) ## i64
  v = (0) ## i64
  while v < n
    degree = (heads[v + 1] - heads[v]) ## i64
    max_degree = degree if degree > max_degree
    v += 1
  poll_mask = (255) ## i64
  while poll_mask > 0 && (poll_mask + 1) * (n * max_degree + 2 * ne) > 32768
    poll_mask = (poll_mask - 1) / 2
  restart = (0) ## i64
  while restart < restarts
    return 0 if wassat_perm_stop(m, stop, deadline) != 0
    m[6] += 1
    v = 0
    while v < n
      perm[v] = v
      tabu[v] = 0
      v += 1
    v = n - 1
    while v > 0
      j = (wassat_perm_rand(rng, v + 1)) ## i64
      tmp = (perm[v]) ## i64
      perm[v] = perm[j]
      perm[j] = tmp
      v -= 1
    e = (0) ## i64
    while e < ne
      weights[e] = 1
      e += 1
    step = (0) ## i64
    while step < steps
      return 0 if (step & poll_mask) == 0 && wassat_perm_stop(m, stop, deadline) != 0
      m[7] += 1
      nb = (0) ## i64
      sum = (0) ## i64
      e = 0
      while e < ne
        pen = (wassat_cycle_cost((perm[left[e]] ## i64), (perm[right[e]] ## i64), width, n)) ## i64
        penalty[e] = pen
        sum += pen
        if pen > 0
          bad[nb] = e
          nb += 1
        e += 1
      if sum < m[13]
        m[13] = sum
        if use_repair && sum <= repair_limit
          v = 0
          while v < n
            best_perm[v] = perm[v]
            v += 1
          repair[18] += 1
      return 1 if sum == 0
      edge = (bad[wassat_perm_rand(rng, nb)]) ## i64
      u = (wassat_perm_rand(rng, 2) != 0 ? left[edge] : right[edge]) ## i64
      if use_sweep
        scored = wassat_cycle_scores(n, width, u, left, right, heads, occ, perm, weights, scores, plain, adjacent)
        m[23] += heads[u + 1] - heads[u]
        if use_targets
          scored = wassat_cycle_target_scores(n, ne, width, u, left, right, perm, weights, penalty, scores, plain)
          m[24] += n if m.size >= 26
          m[25] += 2 * ne if m.size >= 26
      best_delta = (1 << 60) ## i64
      target = (-1) ## i64
      ties = (0) ## i64
      # All v != u contribute degree(v), except the shared (u,v) edge.
      # The simple undirected graph therefore contributes 2*ne-2*degree(u).
      # Keep the logical work counter without recounting it per candidate.
      updates = (use_targets ? 2 * ne - 2 * (heads[u + 1] - heads[u]) : 0) ## i64
      v = 0
      while v < n
        if v != u
          delta = (0) ## i64
          ds = (0) ## i64
          at = (0) ## i64
          if use_sweep
            delta = scores[perm[v]] - scores[perm[u]]
            ds = plain[perm[v]] - plain[perm[u]]
            if use_targets
              delta += scores[n + v]
              ds += plain[n + v]
            e = adjacent[v] - 1
            if e >= 0
              # The shared edge keeps its length under the swap. Both cached
              # endpoint scores included a hypothetical zero-length edge.
              d = (width - penalty[e]) ## i64
              d *= 2 if use_targets
              delta -= d * weights[e]
              ds -= d
          else
            at = (heads[u]) ## i64
            while at < heads[u + 1]
              e = occ[at]
              z = (left[e] ^ right[e] ^ u) ## i64
              if z != v
                d = (wassat_cycle_cost((perm[v] ## i64), (perm[z] ## i64), width, n) - penalty[e]) ## i64
                ds += d
                delta += d * weights[e]
                updates += 1
              at += 1
          if !use_targets
            at = heads[v]
            while at < heads[v + 1]
              e = occ[at]
              z = left[e] ^ right[e] ^ v
              if z != u
                d = wassat_cycle_cost((perm[u] ## i64), (perm[z] ## i64), width, n) - penalty[e]
                ds += d
                delta += d * weights[e]
                updates += 1
              at += 1
          admissible = (tabu[u] <= step && tabu[v] <= step) || sum + ds < m[13]
          if admissible
            if delta < best_delta
              best_delta = delta
              target = v
              ties = 1
            elsif delta == best_delta
              ties += 1
              target = v if wassat_perm_rand(rng, ties) == 0
        v += 1
      m[10] += n - 1
      m[11] += updates
      if target < 0
        target = wassat_perm_rand(rng, n)
        best_delta = 0
      if best_delta >= 0
        j = 0
        while j < nb
          weights[bad[j]] += 1
          j += 1
        m[9] += 1
      tmp = perm[u]
      perm[u] = perm[target]
      perm[target] = tmp
      until_step = (step + 3 + wassat_perm_rand(rng, 8)) ## i64
      tabu[u] = until_step
      tabu[target] = until_step
      m[8] += 1
      step += 1
    if use_repair && repair[0] < WASSAT_CYCLE_REPAIR_ROUNDS && m[13] > 0 && m[13] <= repair_limit && m[13] < repair[23]
      repair[23] = m[13]
      repaired = wassat_cycle_repair(n, ne, width, left, right, heads, occ, best_perm, repair, stop, deadline)
      if repair[22] != 0
        m[22] = repair[22]
        return 0
      if repaired == 1
        v = 0
        while v < n
          perm[v] = best_perm[v]
          v += 1
        m[13] = 0
        return 1
    restart += 1
  m[22] = 3
  0
