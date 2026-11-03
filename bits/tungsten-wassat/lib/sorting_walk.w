# Packed simulation of an input-derived comparator network. No move allocates:
# current/trial bitplanes, saved layer and incumbent matching are reused.
-> wassat_sorting_rand(rng) (u64[]) i64
  x = rng[0] ## u64
  x ^= x << 13
  x ^= x >> 7
  x ^= x << 17
  rng[0] = x
  (x >> 16) & 4294967295

-> wassat_sorting_mutate(mate, allowed, n, layer, rng) (i8[] i32[] i64 i64 u64[]) i64
  a = wassat_sorting_rand(rng) % n ## i64
  b = wassat_sorting_rand(rng) % n ## i64
  while a == b || allowed[(layer*n+a)*n+b] == 0
    a = wassat_sorting_rand(rng) % n
    b = wassat_sorting_rand(rng) % n
  off = layer*n ## i64
  c = mate[off+a] ## i64
  d = mate[off+b] ## i64
  if c == b
    mate[off+a] = -1; mate[off+b] = -1
    return 0
  mate[off+c] = -1 if c >= 0
  mate[off+d] = -1 if d >= 0
  mate[off+a] = b; mate[off+b] = a
  if c >= 0 && d >= 0 && allowed[(layer*n+c)*n+d] != 0 && (wassat_sorting_rand(rng)&3) != 0
    mate[off+c] = d; mate[off+d] = c
  0

-> wassat_sorting_initialize(mate, allowed, n, depth, rng) (i8[] i32[] i64 i64 u64[]) i64
  i = 0 ## i64
  while i < n*depth
    mate[i] = -1; i += 1
  i = 0
  while i < 300
    z = wassat_sorting_mutate(mate,allowed,n,wassat_sorting_rand(rng)%depth,rng)
    i += 1
  0

-> wassat_sorting_evaluate(state, trial, wanted, mate, n, depth, words, start) (u64[] u64[] u64[] i8[] i64 i64 i64 i64) i64
  layer = start ## i64
  while layer < depth
    a = 0 ## i64
    while a < n
      b = mate[layer*n+a] ## i64
      if b >= 0 && b < a
        a += 1
        next
      ia = (layer*n+a)*words ## i64
      ib = (layer*n+b)*words ## i64
      oa = ia+n*words ## i64
      ob = ib+n*words ## i64
      w = 0 ## i64
      while w < words
        va = layer == start ? state[ia+w] : trial[ia+w] ## u64
        if b < 0
          trial[oa+w] = va
        else
          vb = layer == start ? state[ib+w] : trial[ib+w] ## u64
          trial[oa+w] = va & vb
          trial[ob+w] = va | vb
        w += 1
      a += 1
    layer += 1
  cost = 0 ## i64
  i = 0 ## i64
  while i < n*words
    cost += popcount(trial[depth*n*words+i] ^ wanted[i])
    i += 1
  cost

-> wassat_sorting_accept(state, trial, n, depth, words, start) (u64[] u64[] i64 i64 i64 i64) i64
  i = (start+1)*n*words ## i64
  while i < (depth+1)*n*words
    state[i] = trial[i]; i += 1
  0

# m: width, depth, selectors, flags_end, patterns, decoded clauses, steps,
# accepted, restarts, best, stop reason, polls, evaluations, replay clauses,
# decode ms, search ms, completion ms, completion conflicts, verified,
# start, finish, scratch bytes, decode stage, literal visits.
-> wassat_sorting_poll(m, stop, deadline) (i64[] i64[] i64) i64
  m[11] += 1
  m[10] = 1 if wassat_stop_load(stop) != 0
  m[10] = 2 if m[10] == 0 && clock_ms() >= deadline
  m[10]

-> wassat_sorting_search(allowed, vectors, mate, m, stop, deadline, max_steps) (i32[] i32[] i8[] i64[] i64[] i64 i64) i64
  return 0 if wassat_sorting_poll(m,stop,deadline) != 0
  n = m[0] ## i64
  depth = m[1] ## i64
  count = m[4] ## i64
  words = (count+63)/64 ## i64
  state = u64[(depth+1)*n*words]
  trial = u64[(depth+1)*n*words]
  wanted = u64[n*words]
  best = i8[n*depth]
  saved = i8[n]
  rng = u64[1]
  rng[0] = 1
  i = 0 ## i64
  while i < count
    v = vectors[i] ## i64
    ones = popcount(v) ## i64
    a = 0 ## i64
    bit = 1 ## u64
    bit <<= i%64
    while a < n
      state[a*words+i/64] |= bit if (v & (1<<a)) != 0
      wanted[a*words+i/64] |= bit if a >= n-ones
      a += 1
    i += 1
  # A comparator that never exchanges any decoded input only wastes the
  # first layer's matching slots. Remove it from this proposal search.
  a = 0 ## i64
  while a < n
    b = a+1 ## i64
    while b < n
      inversion = 0 ## i64
      w = 0 ## i64
      while w < words
        inversion = 1 if (state[a*words+w] | state[b*words+w]) != state[b*words+w]
        w += 1
      if inversion == 0
        allowed[a*n+b] = 0; allowed[b*n+a] = 0
      b += 1
    a += 1
  # Every layer must retain a move; avoid a retry loop on a degenerate input.
  layer = 0 ## i64
  while layer < depth
    any = 0 ## i64
    i = layer*n*n
    while i < (layer+1)*n*n
      any = 1 if allowed[i] != 0
      i += 1
    return 0 if any == 0
    layer += 1
  z = wassat_sorting_initialize(mate,allowed,n,depth,rng)
  cost = wassat_sorting_evaluate(state,trial,wanted,mate,n,depth,words,0) ## i64
  z = wassat_sorting_accept(state,trial,n,depth,words,0)
  m[9] = cost; m[12] = 1
  i = 0
  while i < n*depth
    best[i] = mate[i]; i += 1
  return 1 if cost == 0
  while m[6] < max_steps
    step = m[6] ## i64
    return 0 if (step & 1023) == 0 && wassat_sorting_poll(m,stop,deadline) != 0
    if (step & 65535) == 0 && step != 0
      m[8] += 1
      if wassat_sorting_rand(rng)%4 != 0
        i = 0
        while i < n*depth
          mate[i] = best[i]; i += 1
        i = 0
        while i < 2+m[8]%11
          z = wassat_sorting_mutate(mate,allowed,n,wassat_sorting_rand(rng)%depth,rng)
          i += 1
      else
        z = wassat_sorting_initialize(mate,allowed,n,depth,rng)
      cost = wassat_sorting_evaluate(state,trial,wanted,mate,n,depth,words,0)
      m[12] += 1
      z = wassat_sorting_accept(state,trial,n,depth,words,0)
    layer = wassat_sorting_rand(rng)%depth
    i = 0
    while i < n
      saved[i] = mate[layer*n+i]; i += 1
    z = wassat_sorting_mutate(mate,allowed,n,layer,rng)
    candidate = wassat_sorting_evaluate(state,trial,wanted,mate,n,depth,words,layer) ## i64
    m[12] += 1
    take = candidate <= cost
    unless take
      f = (step & 65535)/~65536.0 ## f64
      temp = ~0.15+~12.0*(~1.0-f)*(~1.0-f) ## f64
      draw = (wassat_sorting_rand(rng)+~0.5)/~4294967296.0 ## f64
      take = draw < Math.exp((cost-candidate) / temp)
    if take
      cost = candidate; m[7] += 1
      z = wassat_sorting_accept(state,trial,n,depth,words,layer)
      if cost < m[9]
        m[9] = cost
        i = 0
        while i < n*depth
          best[i] = mate[i]; i += 1
        return 1 if cost == 0
    else
      i = 0
      while i < n
        mate[layer*n+i] = saved[i]; i += 1
    m[6] += 1
  m[10] = 3
  0
