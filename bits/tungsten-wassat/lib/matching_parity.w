# Checked matching parity after unit propagation and binary resolution.
# A selected positive row is exact-one only after binary implication paths
# certify every exclusion. Each variable must join two distinct selected rows.
# An odd closed component then cannot be covered by true edges. No generator
# identifiers or variable-number ranges are used. Proof modes use CDCL.
use atomic_stop
use cnf

# meta: result, units, resolved units, rounds, literal visits, binary edges,
# rows, witness rows, exclusion pairs, graph visits, stop reason, start, end,
# work ticks, components, satisfied-cache hits, cached clauses. stop: 1 cancellation, 2 deadline, 3 work limit.
-> wassat_parity_stop(m, stop, deadline) (i64[] i64[] i64) i64
  if wassat_stop_load(stop) != 0
    m[10] = 1
  elsif deadline > 0 && clock_ms() >= deadline
    m[10] = 2
  elsif m[4] + m[9] + m[15] > 100000000
    m[10] = 3
  m[10]

-> wassat_parity_node(l) (i64) i64
  l > 0 ? 2 * (l - 1) : 2 * (-l - 1) + 1

-> wassat_parity_literal(node) (i64) i64
  (node & 1) == 0 ? node / 2 + 1 : -(node / 2 + 1)

# Result: -1 checked conflict, 0 stopped, 1 saturated. Values are entailed by
# the original formula throughout; satisfied clauses need no further work.
-> wassat_parity_units(lits, offs, lens, nc, values, done, m, stop, deadline) (i64[] i64[] i64[] i64 i8[] i32[] i64[] i64[] i64) i64
  changed = 1
  while changed != 0
    changed = 0
    ci = 0
    while ci < nc
      return 0 if (ci & 1023) == 0 && wassat_parity_stop(m, stop, deadline) != 0
      if done[ci] != 0
        m[15] += 1
      else
        j = 0; open = 0; unit = 0; satisfied = 0
        while j < lens[ci] && open < 2 && satisfied == 0
          return 0 if (j & 4095) == 4095 && wassat_parity_stop(m, stop, deadline) != 0
          l = lits[offs[ci] + j]; v = l < 0 ? -l : l
          a = values[v]; sign = l < 0 ? -1 : 1
          if a == sign
            satisfied = 1
          elsif a == 0
            open += 1; unit = l
          m[4] += 1; j += 1
        if satisfied == 1
          done[ci] = 1; m[16] += 1
        elsif open < 2
          return -1 if open == 0
          v = unit < 0 ? -unit : unit
          values[v] = unit < 0 ? -1 : 1
          m[1] += 1; changed = 1
          done[ci] = 1; m[16] += 1
      ci += 1
  1

# Each pair of consecutive targets records a residual binary clause (a,b)
# as edges not-a -> b and not-b -> a. Rebuild into the same fixed buffers.
-> wassat_parity_binary(lits, offs, lens, nv, nc, values, done, head, dest, links, m, stop, deadline) (i64[] i64[] i64[] i64 i64 i8[] i32[] i32[] i32[] i32[] i64[] i64[] i64) i64
  i = 0
  while i < 2 * nv
    head[i] = 0; i += 1
  count = 0; ci = 0
  while ci < nc
    return -1 if (ci & 1023) == 0 && wassat_parity_stop(m, stop, deadline) != 0
    if done[ci] != 0
      m[15] += 1
    else
      j = 0; open = 0; a = 0; b = 0; satisfied = 0
      while j < lens[ci] && open < 3 && satisfied == 0
        return -1 if (j & 4095) == 4095 && wassat_parity_stop(m, stop, deadline) != 0
        l = lits[offs[ci] + j]; v = l < 0 ? -l : l
        if values[v] == (l < 0 ? -1 : 1)
          satisfied = 1
        elsif values[v] == 0
          if open == 0
            a = wassat_parity_node(l)
          else
            b = wassat_parity_node(l)
          open += 1
        m[4] += 1; j += 1
      if satisfied == 1
        done[ci] = 1; m[16] += 1
      elsif open == 2
        src = a ^ 1
        dest[count] = b; links[count] = head[src]; head[src] = count + 1
        count += 1
        src = b ^ 1
        dest[count] = a; links[count] = head[src]; head[src] = count + 1
        count += 1
    ci += 1
  m[5] = count
  count

# (a or b), (not-a or x), (not-b or x) entail x. All graph clauses are
# residual original clauses, so this only adds entailed units. Return -1 on
# opposite units and -2 on cancellation; otherwise return the new unit count.
-> wassat_parity_resolve(nv, count, values, head, dest, links, seen, m, stop, deadline) (i64 i64 i8[] i32[] i32[] i32[] i32[] i64[] i64[] i64) i64
  i = 0
  while i < 2 * nv
    seen[i] = 0; i += 1
  added = 0; at = 0
  while at < count
    return -2 if (at & 1023) == 0 && wassat_parity_stop(m, stop, deadline) != 0
    a = dest[at + 1]; b = dest[at]; stamp = at + 1
    e = head[a]
    while e != 0
      seen[dest[e - 1]] = stamp
      e = links[e - 1]; m[9] += 1
      return -2 if (m[9] & 4095) == 0 && wassat_parity_stop(m, stop, deadline) != 0
    e = head[b]
    while e != 0
      node = dest[e - 1]
      if seen[node] == stamp
        v = node / 2 + 1; sign = (node & 1) == 0 ? 1 : -1
        return -1 if values[v] == -sign
        if values[v] == 0
          values[v] = sign; added += 1; m[1] += 1; m[2] += 1
      e = links[e - 1]; m[9] += 1
      return -2 if (m[9] & 4095) == 0 && wassat_parity_stop(m, stop, deadline) != 0
    at += 2
  added

# Selecting a subset of positive rows is sound. The minimum width only limits
# speculative recognition cost; the parity certificate checks all premises.
-> wassat_parity_rows(lits, offs, lens, nv, nc, values, rows, first, second, seen, min_width, m, stop, deadline) (i64[] i64[] i64[] i64 i64 i8[] i32[] i32[] i32[] i32[] i64 i64[] i64[] i64) i64
  ci = 0; nr = 0
  while ci < nc
    return -1 if (ci & 1023) == 0 && wassat_parity_stop(m, stop, deadline) != 0
    # nr <= ci: writing a row ID only overwrites cache slots already read.
    if rows[ci] != 0
      m[15] += 1
    else
      j = 0; size = 0; eligible = 1
      while j < lens[ci] && eligible == 1
        return -1 if (j & 4095) == 4095 && wassat_parity_stop(m, stop, deadline) != 0
        l = lits[offs[ci] + j]; v = l < 0 ? -l : l
        if values[v] == (l < 0 ? -1 : 1) || (values[v] == 0 && l < 0)
          eligible = 0
        elsif values[v] == 0
          size += 1
        m[4] += 1; j += 1
      if eligible == 1 && size >= min_width && size <= 128
        rows[nr] = ci
        j = 0
        while j < lens[ci]
          return -1 if (j & 4095) == 4095 && wassat_parity_stop(m, stop, deadline) != 0
          l = lits[offs[ci] + j]; v = l < 0 ? -l : l
          m[4] += 1
          if values[v] == 0
            # Reject duplicate literals rather than treating a repeated variable
            # in one row as an edge to itself. Reset stamps before this phase.
            return -1 if seen[v] == ci + 1
            seen[v] = ci + 1
            if first[v] == 0
              first[v] = nr + 1
            elsif second[v] == 0
              second[v] = nr + 1
            else
              second[v] = -1
          j += 1
        nr += 1
    ci += 1
  m[6] = nr
  nr

# Verify all exclusions by binary reachability. A failed check declines this
# component; it is never treated as evidence of satisfiability.
-> wassat_parity_exclusions(lits, offs, lens, values, rows, component, count, head, dest, links, seen, queue, m, stop, deadline) (i64[] i64[] i64[] i8[] i32[] i32[] i64 i32[] i32[] i32[] i32[] i32[] i64[] i64[] i64) i64
  r = 0
  while r < count
    ci = rows[component[r]]; i = 0
    while i < lens[ci]
      return -1 if (i & 4095) == 4095 && wassat_parity_stop(m, stop, deadline) != 0
      a = lits[offs[ci] + i]
      m[4] += 1
      if a > 0 && values[a] == 0
        m[13] += 1; stamp = m[13]
        node = wassat_parity_node(a)
        seen[node] = stamp; queue[0] = node; front = 0; tail = 1
        while front < tail
          return -1 if (front & 255) == 0 && wassat_parity_stop(m, stop, deadline) != 0
          e = head[queue[front]]
          while e != 0
            b = dest[e - 1]
            if seen[b] != stamp
              seen[b] = stamp; queue[tail] = b; tail += 1
            e = links[e - 1]; m[9] += 1
            return -1 if (m[9] & 4095) == 0 && wassat_parity_stop(m, stop, deadline) != 0
          front += 1
        j = i + 1
        while j < lens[ci]
          return -1 if (j & 4095) == 4095 && wassat_parity_stop(m, stop, deadline) != 0
          b = lits[offs[ci] + j]
          m[4] += 1
          if b > 0 && values[b] == 0
            m[8] += 1
            return 0 if seen[wassat_parity_node(-b)] != stamp
          j += 1
      i += 1
    r += 1
  1

-> wassat_matching_parity_check(lits, offs, lens, nv, nc, min_width, m, stop, deadline) (i64[] i64[] i64[] i64 i64 i64 i64[] i64[] i64) i64
  return 0 if nv < 1 || nv > 200000 || nc < 1 || nc > 1000000 || min_width < 2
  return 0 if wassat_parity_stop(m, stop, deadline) != 0
  values = i8[nv + 1]
  head = i32[2 * nv]; dest = i32[2 * nc]; links = i32[2 * nc]
  seen = i32[2 * nv + 1]
  # Entailed assignments only grow. Reuse the later row-ID buffer to memoize
  # satisfied original clauses during propagation and binary extraction.
  rows = i32[nc]
  rounds = 0; added = 1
  while added > 0 && rounds < 8
    z = wassat_parity_units(lits, offs, lens, nc, values, rows, m, stop, deadline)
    return -1 if z == -1
    return 0 if z == 0
    count = wassat_parity_binary(lits, offs, lens, nv, nc, values, rows, head, dest, links, m, stop, deadline)
    return 0 if count < 0
    added = wassat_parity_resolve(nv, count, values, head, dest, links, seen, m, stop, deadline)
    return -1 if added == -1
    return 0 if added == -2
    rounds += 1; m[3] = rounds
  # No stale residual graph: only inspect rows after a fixed point.
  return 0 if added > 0
  first = i32[nv + 1]; second = i32[nv + 1]
  i = 0
  while i <= 2 * nv
    seen[i] = 0; i += 1
  nr = wassat_parity_rows(lits, offs, lens, nv, nc, values, rows, first, second, seen, min_width, m, stop, deadline)
  return 0 if nr < 3
  visited = i8[nr]; component = i32[nr]; queue = i32[2 * nv]
  i = 0
  while i <= 2 * nv
    seen[i] = 0; i += 1
  root = 0
  while root < nr
    if visited[root] == 0
      component[0] = root; visited[root] = 1; front = 0; tail = 1; valid = 1
      m[14] += 1
      while front < tail
        return 0 if (front & 255) == 0 && wassat_parity_stop(m, stop, deadline) != 0
        row = component[front]; ci = rows[row]; j = 0
        while j < lens[ci]
          return 0 if (j & 4095) == 4095 && wassat_parity_stop(m, stop, deadline) != 0
          l = lits[offs[ci] + j]; v = l < 0 ? -l : l
          m[4] += 1
          if values[v] == 0
            if second[v] <= 0
              valid = 0
            else
              other = first[v] + second[v] - row - 2
              if visited[other] == 0
                visited[other] = 1; component[tail] = other; tail += 1
          j += 1
        front += 1
      if valid == 1 && (tail & 1) == 1
        z = wassat_parity_exclusions(lits, offs, lens, values, rows, component, tail, head, dest, links, seen, queue, m, stop, deadline)
        return 0 if z == -1
        if z == 1
          return 0 if wassat_parity_stop(m, stop, deadline) != 0
          m[7] = tail
          return -1
    root += 1
  0

-> wassat_matching_parity_refute(formula, stop, deadline = 0, min_width = 5)
  m = i64[17]
  m[11] = clock_ms()
  m[0] = wassat_matching_parity_check(formula["flat_lits"], formula["flat_offs"], formula["flat_lens"], formula["nvars"], formula["flat_ncl"], min_width, m, stop, deadline)
  m[12] = clock_ms()
  m

# Admit unit-rich inputs with wide clauses. This bounded prefix is
# only a cost gate; the worker rechecks the full original-clause certificate.
-> wassat_parity_prefix(lens, nc) (i64[] i64) i64
  limit = nc < 256 ? nc : 256
  ci = 0; units = 0; wide = 0
  while ci < limit
    units += 1 if lens[ci] == 1
    # Original clauses may be much wider than the selected residual rows.
    # Entailed units remove literals before the worker applies its 128 limit.
    wide += 1 if lens[ci] >= 5
    ci += 1
  units >= 8 && wide >= 3 ? 1 : 0

-> wassat_matching_parity_source(formula)
  mode = env("WASSAT_MATCHING_PARITY")
  return nil if mode == "0" || formula == nil
  return nil if env("WASSAT_ARMS") != nil && mode != "1"
  return nil if System.physical_memory_bytes <= 0
  nv = formula["nvars"]; nc = formula["flat_ncl"]
  return nil if nv < 1 || nv > 200000 || nc < 1 || nc > 1000000 || formula["flat_nlits"] > 8000000
  return nil if 40 * (nv + 1) + 25 * nc > System.physical_memory_bytes / 64
  if mode != "1"
    return nil if nv < 128 || nc < 4096
    return nil if wassat_parity_prefix(formula["flat_lens"], nc) == 0
  # Retain the original immutable arrays before any CLI structural rewrite
  # replaces the parser's fields. No clause payload is copied.
  {"nvars": nv, "flat_ncl": nc, "flat_nlits": formula["flat_nlits"],
   "flat_lits": formula["flat_lits"], "flat_offs": formula["flat_offs"],
   "flat_lens": formula["flat_lens"]}

-> wassat_matching_parity_plan(source, workers)
  return nil if source == nil || System.cpu_count <= workers
  i64[17]

-> wassat_matching_parity_arm(lits, offs, lens, nv, nc, m, stop) (i64[] i64[] i64[] i64 i64 i64[] i64[]) i64
  m[11] = clock_ms()
  deadline = m[11] + 100
  result = wassat_matching_parity_check(lits, offs, lens, nv, nc, 5, m, stop, deadline)
  m[12] = clock_ms()
  if result == -1 && wassat_parity_stop(m, stop, deadline) == 0
    z = ccall("__w_arr_store_rel", m, 0, result)
    won = wassat_stop_publish(stop, result)
    return result
  0

-> wassat_matching_parity_start(formula, m, stop)
  lits = formula["flat_lits"]; offs = formula["flat_offs"]; lens = formula["flat_lens"]
  nv = formula["nvars"]; nc = formula["flat_ncl"]
  Thread.new -> wassat_matching_parity_arm(lits, offs, lens, nv, nc, m, stop)

-> wassat_matching_parity_profile(m)
  wassat_prof_note("scout.matching_parity status=[m[0]] units=[m[1]] resolved=[m[2]] rounds=[m[3]] literal_visits=[m[4]] binary_edges=[m[5]] rows=[m[6]] witness_rows=[m[7]] amo_pairs=[m[8]] graph_visits=[m[9]] cache_hits=[m[15]] cached_clauses=[m[16]] stop=[m[10]] ms=[m[12] - m[11]] finish_to_join_ms=[clock_ms() - m[12]]")
