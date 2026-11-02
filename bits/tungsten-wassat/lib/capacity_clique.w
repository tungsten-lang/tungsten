# Pigeonhole refutation from original positive domain clauses and verified
# pair conflicts at EVERY column. Column positions need no semantic meaning.
# For x -> (r | s), a room choice may imply a resource t via the original
# clause (-x | -r | -a | t) and original unit (a). Two chosen domain values
# conflict if each of their four room combinations is excluded, either by
# (-r | -s) or by (-t | -u) on their implied resources. Nothing is inferred
# from variable numbering, filenames, teacher names, or missing clauses.
# A clique of k+1 positive k-wide domains cannot choose distinct columns.
# This worker belongs only to the fast race; certificate modes continue
# through proof-producing CDCL. It never replaces an existing solving arm.
use atomic_stop

WASSAT_CAPACITY_MAX_VARS = 100000
WASSAT_CAPACITY_MAX_CLAUSES = 1200000
WASSAT_CAPACITY_MAX_BLOCKS = 600
WASSAT_CAPACITY_WALL_MS = 2000

# m: 0 width, 1 blocks, 2 clauses scanned, 3 room links, 4 implications,
# 5 binary probes, 6 pair checks, 7 column checks, 8 clique size, 9 polls,
# 10 stop reason (1 deadline, 2 cancellation, 3 work cap), 11 deadline,
# 17 start, 18 finish, 19 extra bytes, 20 cache hits, 21 hash inserts.
-> wassat_capacity_poll(m, stop) (i64[] i64[]) i64
  m[9] += 1
  if wassat_stop_requested?(stop)
    m[10] = 2
  elsif m[11] > 0 && clock_ms() >= m[11]
    m[10] = 1
  m[10]

-> wassat_capacity_key(a, b, nv) (i64 i64 i64) i64
  a < b ? a * (nv + 1) + b : b * (nv + 1) + a

-> wassat_capacity_binary(table, a, b, nv, insert, m) (i64[] i64 i64 i64 i64 i64[]) i64
  return 0 if a < 1 || b < 1 || a > nv || b > nv || a == b
  key = wassat_capacity_key(a, b, nv) ## i64
  mask = table.size - 1 ## i64
  at = ((key * 1000003) ^ (key >> 17)) & mask ## i64
  probes = 0 ## i64
  while table[at] != 0 && table[at] != key
    probes += 1
    m[5] += 1
    if probes >= 128
      m[10] = 3
      return 0
    at = (at + 1) & mask
  m[5] += 1
  if insert == 1
    m[21] += 1 if table[at] == 0
    table[at] = key
    return 1
  table[at] == key ? 1 : 0

# Cheap bounded admission only; the worker verifies complete source clauses.
-> wassat_capacity_prefix(lits, offs, lens, nc) (i64[] i64[] i64[] i64) i64
  return 0 if nc < 1 || offs.size < nc || lens.size < nc
  limit = nc < 512 ? nc : 512 ## i64
  ci = 0 ## i64
  while ci < limit
    n = lens[ci] ## i64
    off = offs[ci] ## i64
    return 0 if n < 0 || off < 0 || off > lits.size || n > lits.size - off
    if n >= 4 && n <= 64
      good = 1 ## i64
      j = 0 ## i64
      while j < n
        good = 0 if lits[off + j] <= 0
        j += 1
      return n if good == 1
    ci += 1
  0

-> wassat_capacity_bytes(nv, nc) (i64 i64) i64
  size = 1 ## i64
  while size < 2 * nc
    size *= 2
  8 * size + 32 * (nv + 1) + 1048576

-> wassat_capacity_plan(formula, workers, cdcl, sls, pre, extra)
  mode = env("WASSAT_CAPACITY_CLIQUE")
  return nil if mode == "0" || formula == nil
  return nil if env("WASSAT_ARMS") != nil && mode != "1"
  return nil if wassat_race_round1_conflicts != 0
  return nil if System.cpu_count <= workers || System.physical_memory_bytes <= 0
  nv = formula["nvars"]; nc = formula["flat_ncl"]
  return nil if nv < 4 || nv > WASSAT_CAPACITY_MAX_VARS || nc < 1 || nc > WASSAT_CAPACITY_MAX_CLAUSES
  return nil if mode != "1" && (nv < 1000 || nc < 10000)
  width = wassat_capacity_prefix(formula["flat_lits"], formula["flat_offs"], formula["flat_lens"], nc)
  return nil if width == 0
  bytes = wassat_capacity_bytes(nv, nc)
  return nil if bytes > System.physical_memory_bytes / 64
  return nil unless wassat_race_memory_fits?(formula, cdcl, sls, pre, extra + bytes)
  { "meta": i64[24], "witness": i32[65], "width": width, "scratch": bytes }

-> wassat_capacity_decode(lits, offs, lens, nv, nc, width, domains, member, units, rooms, targets, table, m, stop) (i64[] i64[] i64[] i64 i64 i64 i32[] i8[] i8[] i32[] i32[] i64[] i64[] i64[]) i64
  return 0 if width < 2 || width > 64 || offs.size < nc || lens.size < nc
  nb = 0 ## i64
  ci = 0 ## i64
  while ci < nc
    return 0 if (ci & 255) == 0 && wassat_capacity_poll(m, stop) != 0
    n = lens[ci] ## i64
    off = offs[ci] ## i64
    return 0 if n < 0 || n > 64 || off < 0 || off > lits.size || n > lits.size - off
    positive = 1 ## i64
    j = 0 ## i64
    while j < n
      lit = lits[off + j] ## i64
      return 0 if lit == 0 || lit < -nv || lit > nv
      positive = 0 if lit < 0
      j += 1
    units[lits[off]] = 1 if n == 1 && positive == 1
    if n == 2 && lits[off] < 0 && lits[off + 1] < 0
      z = wassat_capacity_binary(table, -lits[off], -lits[off + 1], nv, 1, m)
      return 0 if m[10] != 0
    if n == width && positive == 1
      return 0 if nb >= WASSAT_CAPACITY_MAX_BLOCKS
      j = 0
      while j < width
        v = lits[off + j] ## i64
        # Disjointness also rules out repeated literals inside a domain.
        return 0 if member[v] != 0
        member[v] = 1
        domains[nb * width + j] = v
        j += 1
      nb += 1
    m[2] += 1
    ci += 1
  m[0] = width; m[1] = nb
  return 0 if nb <= width
  ci = 0
  while ci < nc
    return 0 if (ci & 255) == 0 && wassat_capacity_poll(m, stop) != 0
    if lens[ci] == 3
      off = offs[ci]
      x = 0 ## i64
      r = 0 ## i64
      s = 0 ## i64
      j = 0
      while j < 3
        lit = lits[off + j]
        if lit < 0
          x = -lit if x == 0
        elsif r == 0
          r = lit
        else
          s = lit
        j += 1
      if x > 0 && r > 0 && s > 0 && member[x] != 0 && rooms[2 * x] == 0
        rooms[2 * x] = r; rooms[2 * x + 1] = s
        m[3] += 1
    ci += 1
  ci = 0
  while ci < nc
    return 0 if (ci & 255) == 0 && wassat_capacity_poll(m, stop) != 0
    if lens[ci] == 4
      off = offs[ci]
      t = 0 ## i64
      positives = 0 ## i64
      j = 0
      while j < 4
        if lits[off + j] > 0
          t = lits[off + j]; positives += 1
        j += 1
      if positives == 1
        j = 0
        while j < 4
          x = -lits[off + j]
          if x > 0 && member[x] != 0
            side = 0 ## i64
            while side < 2
              r = rooms[2 * x + side] ## i64
              # Two other distinct positions must supply the room and unit.
              k = 0 ## i64
              while r > 0 && k < 4
                if k != j && lits[off + k] == -r
                  h = 0 ## i64
                  while h < 4
                    a = -lits[off + h] ## i64
                    if h != j && h != k && a > 0 && units[a] != 0
                      if targets[2 * x + side] == 0
                        targets[2 * x + side] = t
                        m[4] += 1
                    h += 1
                k += 1
              side += 1
          j += 1
    ci += 1
  nb

-> wassat_capacity_conflict(table, rooms, targets, a, b, nv, m) (i64[] i32[] i32[] i64 i64 i64 i64[]) i64
  return 1 if wassat_capacity_binary(table, a, b, nv, 0, m) == 1
  return 0 if rooms[2 * a] == 0 || rooms[2 * b] == 0
  i = 0 ## i64
  while i < 2
    j = 0 ## i64
    while j < 2
      r = rooms[2 * a + i] ## i64
      s = rooms[2 * b + j] ## i64
      if wassat_capacity_binary(table, r, s, nv, 0, m) == 0
        t = targets[2 * a + i] ## i64
        u = targets[2 * b + j] ## i64
        return 0 if wassat_capacity_binary(table, t, u, nv, 0, m) == 0
      j += 1
    i += 1
  1

-> wassat_capacity_clique(domains, rooms, targets, table, cache, witness, nb, width, nv, m, stop) (i32[] i32[] i32[] i64[] i8[] i32[] i64 i64 i64 i64[] i64[]) i64
  first = 0 ## i64
  while first < nb
    witness[0] = first
    count = 1 ## i64
    b = first + 1 ## i64
    while b < nb && count <= width
      good = 1 ## i64
      k = 0 ## i64
      while k < count && good == 1
        a = witness[k] ## i64
        at = a * nb + b ## i64
        st = cache[at] ## i64
        if st == 0
          m[6] += 1
          return 0 if (m[6] & 63) == 1 && wassat_capacity_poll(m, stop) != 0
          if m[6] > 180000
            m[10] = 3
            return 0
          st = 1
          col = 0 ## i64
          while col < width && st == 1
            m[7] += 1
            st = 2 if wassat_capacity_conflict(table, rooms, targets, (domains[a * width + col] ## i64), (domains[b * width + col] ## i64), nv, m) == 0
            col += 1
          cache[at] = st
          return 0 if m[10] != 0
        else
          m[20] += 1
        good = 0 if st != 1
        k += 1
      if good == 1
        witness[count] = b
        count += 1
      b += 1
    m[8] = count if count > m[8]
    return -1 if count > width
    first += 1
  0

-> wassat_capacity_search(formula, plan, stop, res, base)
  nv = formula["nvars"]; nc = formula["flat_ncl"]
  m = plan["meta"]; witness = plan["witness"]; width = plan["width"]
  m[17] = clock_ms(); m[11] = m[17] + WASSAT_CAPACITY_WALL_MS
  m[19] = plan["scratch"]
  size = 1
  while size < 2 * nc
    size *= 2
  table = i64[size]; domains = i32[WASSAT_CAPACITY_MAX_BLOCKS * width]
  member = i8[nv + 1]; units = i8[nv + 1]
  rooms = i32[2 * (nv + 1)]; targets = i32[2 * (nv + 1)]
  cache = i8[WASSAT_CAPACITY_MAX_BLOCKS * WASSAT_CAPACITY_MAX_BLOCKS]
  nb = wassat_capacity_decode(formula["flat_lits"], formula["flat_offs"], formula["flat_lens"], nv, nc, width, domains, member, units, rooms, targets, table, m, stop)
  hit = 0
  if nb > 0
    hit = wassat_capacity_clique(domains, rooms, targets, table, cache, witness, nb, width, nv, m, stop)
  hit = 0 if wassat_capacity_poll(m, stop) != 0
  m[18] = clock_ms()
  res[base + nv + 6] = m[17]; res[base + nv + 5] = m[18]
  if hit == -1
    z = ccall("__w_arr_store_rel", res, base, hit)
    won = wassat_stop_publish(stop, hit)
  hit

-> wassat_capacity_start(formula, plan, stop, res, base)
  Thread.new -> wassat_capacity_search(formula, plan, stop, res, base)

-> wassat_capacity_profile(plan, status)
  m = plan["meta"]
  wassat_prof_note("race.capacity status=[status] width=[m[0]] domains=[m[1]] clauses=[m[2]] rooms=[m[3]] implications=[m[4]] binary_probes=[m[5]] pairs=[m[6]] columns=[m[7]] clique=[m[8]] polls=[m[9]] stop=[m[10]] cached=[m[20]] binaries=[m[21]] ms=[m[18] - m[17]] extra_bytes=[m[19]]")
