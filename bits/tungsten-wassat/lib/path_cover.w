# Bounded refutation for a complete path placed in exact-one cell domains.
#
# Primary variable cell*n+value+1 means that cell holds value 0..n-1.
# All n positive cell clauses and every within-cell exclusion are checked;
# exclusions may be implied by a binary auxiliary encoding. Every primary
# literal must also have original predecessor/successor support clauses.
# Thus any occupied cell entails that all n values occur. With exactly one
# value in each of n cells, each value occurs exactly once. Domain filtering
# may then use both cell and value uniqueness. Only an empty domain refutes;
# a nonempty fixpoint, malformed encoding, budget or cancellation is a miss.
# No board geometry, clues, filename or precomputed solution is assumed.
use atomic_stop

WASSAT_PATH_COVER_MAX_WIDTH = 64
WASSAT_PATH_COVER_MAX_VARS = 32768
WASSAT_PATH_COVER_MAX_CLAUSES = 65536
WASSAT_PATH_COVER_WORK = 4000000

# Limit speculative workers to a primary matrix plus a bounded auxiliary
# encoding. Inputs with thousands of unrelated variables for a tiny matrix
# stay on the normal solving arms without spawning this worker.
-> wassat_path_cover_candidate?(nv, ncl, width)
  (width >= 3 && width <= WASSAT_PATH_COVER_MAX_WIDTH &&
    nv >= width * width && nv <= 4 * width * width &&
    nv <= WASSAT_PATH_COVER_MAX_VARS &&
    ncl >= width && ncl <= WASSAT_PATH_COVER_MAX_CLAUSES)

-> wassat_path_cover_miss(out, work) (i64[] i64) i64
  out[2] = work
  0

# out: verdict, width, work, removed candidates, empty axis (1 cell,2 value),
#      empty index+1, stop reason (1 cancelled,2 budget), recognized structure.
-> wassat_path_cover_poll(stop, out, work, budget) (i64[] i64[] i64 i64) i64
  out[2] = work
  if work > budget
    out[6] = 2
    return 1
  if wassat_stop_requested?(stop)
    out[6] = 1
    return 1
  0

-> wassat_path_cover_refute(lits, offs, lens, nv, ncl, n, budget, stop, out) (i64[] i64[] i64[] i64 i64 i64 i64 i64[] i64[]) i64
  return 0 unless wassat_path_cover_candidate?(nv, ncl, n)
  out[1] = n
  work = 0
  return 0 if wassat_path_cover_poll(stop, out, work, budget) != 0
  primary = n * n
  nl = 2 * nv + 2
  rows = i64[n]
  prev = i64[primary + 1]
  succ = i64[primary + 1]
  seen = i64[nl]
  counts = i64[nl + 1]
  binary = 0
  ci = 0
  while ci < ncl
    k = lens[ci]
    return wassat_path_cover_miss(out, work) if k <= 0 || k > n
    off = offs[ci]
    row_ok = k == n ? 1 : 0
    row = -1
    negative = 0
    source = 0
    target_value = -1
    targets_ok = 1
    j = 0
    while j < k
      lit = lits[off + j]
      v = lit < 0 ? 0 - lit : lit
      return wassat_path_cover_miss(out, work + j) if v < 1 || v > nv
      if lit < 0
        row_ok = 0
        negative += 1
        source = v
      else
        if v > primary
          row_ok = 0
          targets_ok = 0
        else
          value = (v - 1) % n
          if target_value < 0
            target_value = value
          elsif target_value != value
            targets_ok = 0
          if row_ok == 1
            r = (v - 1) / n
            row = r if row < 0
            row_ok = 0 if row != r || seen[v] == ci + 1
            seen[v] = ci + 1
      j += 1
    rows[row] = ci + 1 if row_ok == 1 && row >= 0
    if negative == 1 && source <= primary && targets_ok == 1 && target_value >= 0
      value = (source - 1) % n
      prev[source] = ci + 1 if value > 0 && target_value == value - 1
      succ[source] = ci + 1 if value + 1 < n && target_value == value + 1
    if k == 2
      a = lits[off]
      b = lits[off + 1]
      ai = a > 0 ? 2 * a : 2 * (0 - a) + 1
      bi = b > 0 ? 2 * b : 2 * (0 - b) + 1
      counts[(ai ^ 1) + 1] += 1
      counts[(bi ^ 1) + 1] += 1
      binary += 1
    work += k
    return 0 if (ci & 255) == 0 && wassat_path_cover_poll(stop, out, work, budget) != 0
    ci += 1
  i = 0
  while i < n
    return wassat_path_cover_miss(out, work) if rows[i] == 0
    work += 1
    i += 1
  v = 1
  while v <= primary
    value = (v - 1) % n
    return wassat_path_cover_miss(out, work) if value > 0 && prev[v] == 0
    return wassat_path_cover_miss(out, work) if value + 1 < n && succ[v] == 0
    work += 1
    v += 1

  # CSR of original binary implications, including auxiliary variables.
  i = 0
  while i < nl
    counts[i + 1] += counts[i]
    work += 1
    i += 1
  cursor = i64[nl]
  edges = i64[2 * binary]
  queue = i64[nl]
  i = 0
  while i < nl
    cursor[i] = counts[i]
    work += 1
    i += 1
  ci = 0
  while ci < ncl
    if lens[ci] == 2
      off = offs[ci]
      a = lits[off]
      b = lits[off + 1]
      ai = a > 0 ? 2 * a : 2 * (0 - a) + 1
      bi = b > 0 ? 2 * b : 2 * (0 - b) + 1
      edges[cursor[ai ^ 1]] = bi
      cursor[ai ^ 1] += 1
      edges[cursor[bi ^ 1]] = ai
      cursor[bi ^ 1] += 1
      work += 2
    work += 1
    return 0 if (ci & 255) == 0 && wassat_path_cover_poll(stop, out, work, budget) != 0
    ci += 1
  return 0 if wassat_path_cover_poll(stop, out, work, budget) != 0

  # x => not-y for every distinct pair in a cell proves its AMO. Stamps
  # exceed all clause stamps above, allowing the same seen array to be reused.
  v = 1
  while v <= primary
    stamp = ncl + v + 1
    head = 0
    tail = 1
    queue[0] = 2 * v
    seen[2 * v] = stamp
    while head < tail
      u = queue[head]
      head += 1
      work += 1
      e = counts[u]
      while e < counts[u + 1]
        w = edges[e]
        if seen[w] != stamp
          seen[w] = stamp
          queue[tail] = w
          tail += 1
        e += 1
        work += 1
        return 0 if (work & 1023) == 0 && wassat_path_cover_poll(stop, out, work, budget) != 0
    first = ((v - 1) / n) * n + 1
    u = first
    while u < first + n
      return wassat_path_cover_miss(out, work) if u != v && seen[2 * u + 1] != stamp
      work += 1
      u += 1
    return 0 if (v & 31) == 0 && wassat_path_cover_poll(stop, out, work, budget) != 0
    v += 1
  return 0 if wassat_path_cover_poll(stop, out, work, budget) != 0
  out[7] = 1

  allowed = i8[primary + 1]
  v = 1
  while v <= primary
    allowed[v] = 1
    work += 1
    v += 1
  ci = 0
  while ci < ncl
    if lens[ci] == 1
      lit = lits[offs[ci]]
      v = lit < 0 ? 0 - lit : lit
      if v <= primary
        if lit < 0
          if allowed[v] != 0
            allowed[v] = 0
            out[3] += 1
        else
          cell = (v - 1) / n
          value = (v - 1) % n
          j = 0
          while j < n
            u = cell * n + j + 1
            if u != v && allowed[u] != 0
              allowed[u] = 0
              out[3] += 1
            u = j * n + value + 1
            if u != v && allowed[u] != 0
              allowed[u] = 0
              out[3] += 1
            work += 2
            j += 1
    work += 1
    return 0 if (ci & 255) == 0 && wassat_path_cover_poll(stop, out, work, budget) != 0
    ci += 1

  changed = 1
  while changed == 1
    changed = 0
    v = 1
    while v <= primary
      if allowed[v] != 0
        direction = 0
        while direction < 2 && allowed[v] != 0
          support = direction == 0 ? prev[v] : succ[v]
          if support != 0
            ci = support - 1
            off = offs[ci]
            hit = 0
            j = 0
            while j < lens[ci]
              lit = lits[off + j]
              hit = 1 if lit > 0 && allowed[lit] != 0
              work += 1
              j += 1
            if hit == 0
              allowed[v] = 0
              out[3] += 1
              changed = 1
          direction += 1
      work += 1
      return 0 if (v & 255) == 0 && wassat_path_cover_poll(stop, out, work, budget) != 0
      v += 1
    axis = 0
    while axis < 2
      i = 0
      while i < n
        count = 0
        last = 0
        j = 0
        while j < n
          v = axis == 0 ? i * n + j + 1 : j * n + i + 1
          if allowed[v] != 0
            count += 1
            last = v
          work += 1
          j += 1
        if count == 0
          return 0 if wassat_path_cover_poll(stop, out, work, budget) != 0
          out[2] = work
          out[4] = axis + 1
          out[5] = i + 1
          return -1
        if count == 1
          cell = (last - 1) / n
          value = (last - 1) % n
          j = 0
          while j < n
            v = axis == 0 ? j * n + value + 1 : cell * n + j + 1
            if v != last && allowed[v] != 0
              allowed[v] = 0
              out[3] += 1
              changed = 1
            work += 1
            j += 1
        i += 1
      axis += 1
    return 0 if wassat_path_cover_poll(stop, out, work, budget) != 0
  out[2] = work
  0

# The scout owns a 12-slot result; slots8..10 record start/publication/exit.
-> wassat_path_cover_arm_body(formula, width, out, stop)
  out[8] = clock_ms()
  status = wassat_path_cover_refute(
    formula["flat_lits"], formula["flat_offs"], formula["flat_lens"],
    formula["nvars"], formula["flat_ncl"], width, WASSAT_PATH_COVER_WORK,
    stop, out
  )
  if status == -1
    out[0] = -1
    out[9] = clock_ms()
    wassat_stop_publish(stop, -1)
  out[10] = clock_ms()
  status
