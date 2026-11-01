# Bounded, model-only input search for a topologically ordered Boolean circuit.
# Each word evaluates the current assignment, every one-bit neighbor, and
# random two-bit neighbors. Breakout weights and restarts escape local maxima.
use atomic_stop

-> wassat_klieber_random(r) (i64) i64
  r = (r ^ (r << 13)) & 4294967295
  r = r ^ (r >> 17)
  (r ^ (r << 5)) & 4294967295

# meta: found, input assignment, batches, gate evaluations, best target count,
# stop (1 cancellation, 2 deadline, 3 work cap). Scratch is reused each batch.
-> wassat_klieber_local_search(val, ga, gna, gb, gnb, gpol, targets, meta,
                                p, nv, nt, stop, deadline, max_batches) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64 i64[] i64 i64) i64
  assignments = i64[64]
  scores = i64[64]
  counts = i64[64]
  weights = i64[nt]
  target_words = i64[nt]
  one = 1 ## i64
  r = wassat_klieber_random(1)
  a = r & ((one << p) - 1)
  j = 0
  while j < nt
    weights[j] = 1
    j += 1
  b = 0
  while b < max_batches
    if (b & 31) == 0
      if wassat_stop_load(stop) != 0
        meta[5] = 1
        return 0
      if deadline > 0 && clock_ms() >= deadline
        meta[5] = 2
        return 0
    assignments[0] = a
    i = 0
    while i < p
      assignments[i + 1] = a ^ (one << i)
      val[i + 1] = (0 - ((a >> i) & 1)) ^ (one << (i + 1))
      i += 1
    k = p + 1
    while k < 64
      r = wassat_klieber_random(r)
      x = r % p
      r = wassat_klieber_random(r)
      y = r % p
      assignments[k] = a ^ (one << x) ^ (one << y)
      val[x + 1] = val[x + 1] ^ (one << k)
      val[y + 1] = val[y + 1] ^ (one << k)
      k += 1
    v = p + 1
    while v < nv
      val[v] = ((val[ga[v]] ^ gna[v]) & (val[gb[v]] ^ gnb[v])) ^ gpol[v]
      v += 1
    meta[2] += 1
    meta[3] += nv - p - 1
    k = 0
    while k < 64
      scores[k] = 0
      counts[k] = 0
      k += 1
    j = 0
    while j < nt
      l = targets[j]
      tv = l < 0 ? 0 - l : l
      tw = val[tv] ^ (l < 0 ? -1 : 0)
      target_words[j] = tw
      k = 0
      while k < 64
        if ((tw >> k) & 1) != 0
          scores[k] += weights[j]
          counts[k] += 1
        k += 1
      j += 1
    best = 0
    k = 0
    while k < 64
      meta[4] = counts[k] if counts[k] > meta[4]
      if counts[k] == nt
        meta[0] = 1
        meta[1] = assignments[k]
        return 1
      if scores[k] > scores[best]
        best = k
      elsif scores[k] == scores[best]
        r = wassat_klieber_random(r)
        best = k if (r & 1) != 0
      k += 1
    if (b & 127) == 127
      r = wassat_klieber_random(r)
      a = r & ((one << p) - 1)
      j = 0
      while j < nt
        weights[j] = 1
        j += 1
    else
      if best == 0
        j = 0
        while j < nt
          weights[j] += 1 if (target_words[j] & 1) == 0
          j += 1
      a = assignments[best]
      r = wassat_klieber_random(r)
      if (r & 15) == 0
        r = wassat_klieber_random(r)
        a = a ^ (one << (r % p))
    b += 1
  meta[5] = 3
  0
