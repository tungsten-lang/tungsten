# Checked minimum-demand / resource-slot capacity refutation.
# Proposal grouping is never a proof: every relevant original event conflict
# is checked separately before returning UNSAT.

-> wassat_resource_abs(x) (i64) i64
  x < 0 ? -x : x

-> wassat_resource_poll(m, stop, deadline) (i64[] i64[] i64) i64
  m[12] += 1
  if wassat_stop_load(stop) != 0
    m[11] = 1
  elsif deadline > 0 && clock_ms() >= deadline
    m[11] = 2
  m[11]

-> wassat_resource_flat_valid(lits, offs, lens, nv, nc, nl, m, stop, deadline) (i64[] i64[] i64[] i64 i64 i64 i64[] i64[] i64) i64
  return 0 if offs.size < nc || lens.size < nc || nl < 0 || nl > lits.size
  ci = 0
  while ci < nc
    return 0 if (ci & 1023) == 0 && wassat_resource_poll(m, stop, deadline) != 0
    n = lens[ci]; off = offs[ci]
    return 0 if n < 1 || n > 65 || off < 0 || off > nl || n > nl - off
    j = 0
    while j < n
      v = wassat_resource_abs(lits[off + j])
      return 0 if v < 1 || v > nv
      j += 1
    ci += 1
  1

-> wassat_resource_clause2(lits, offs, lens, ci, a, b) (i64[] i64[] i64[] i64 i64 i64) i64
  return 0 if ci < 0 || lens[ci] != 2
  o = offs[ci]; x = lits[o]; y = lits[o + 1]
  (x == a && y == b) || (x == b && y == a) ? 1 : 0

-> wassat_resource_clause3(lits, offs, lens, ci, a, b, c) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  return 0 if ci < 0 || lens[ci] != 3 || a == b || a == c || b == c
  o = offs[ci]; hits = 0; j = 0
  while j < 3
    x = lits[o + j]
    hits |= 1 if x == a
    hits |= 2 if x == b
    hits |= 4 if x == c
    j += 1
  hits == 7 ? 1 : 0

# The asserted last prefix bit and all reverse recurrence clauses imply at
# least k of the DISTINCT inputs. Only a complete original chain is accepted.
# Scratch inputs are returned in reverse order. k is returned through scratch[256].
-> wassat_resource_lower(lits, offs, lens, ci, scratch, m, stop, deadline) (i64[] i64[] i64[] i64 i32[] i64[] i64[] i64) i64
  return 0 if ci < 4 || lens[ci] != 1 || lens[ci - 1] != 3
  u = lits[offs[ci]]; return 0 if u <= 0
  o = offs[ci - 1]; j = 0; previous = 0; found = 0
  while j < 3
    x = lits[o + j]; found = 1 if x == 0 - u
    previous = x if x > previous
    j += 1
  k = u - previous
  return 0 if found == 0 || k < 2 || k > 16
  cur = u; last = ci - 1; n = 0
  while n < 256 && last >= k - 1
    return 0 if wassat_resource_poll(m, stop, deadline) != 0
    first = cur - k + 1; base_ci = last - k + 1
    initial = 1; x0 = 0
    if lens[base_ci] == 2
      bo = offs[base_ci]; a = lits[bo]; b = lits[bo + 1]
      x0 = b if a == 0 - first && b > 0
      x0 = a if b == 0 - first && a > 0
    initial = 0 if x0 == 0
    j = 1
    while j < k && initial != 0
      c = base_ci + j
      initial = 0 if lens[c] != 1 || lits[offs[c]] != 0 - first - j
      j += 1
    if initial != 0
      scratch[n] = x0; scratch[256] = k
      m[2] += k + 1
      return n + 1 if n + 1 >= k
      return 0
    return 0 if last < 2 * k - 2
    j = 0; input = 0
    while j < k
      c = last - k + 1 + j
      return 0 if lens[c] != 3
      p = offs[c]; t = 0; x = 0
      while t < 3
        z = lits[p + t]
        x = z if z > 0 && z != first + j - k
        t += 1
      return 0 if x <= 0 || (j > 0 && x != input)
      input = x
      return 0 if wassat_resource_clause3(lits, offs, lens, c, 0 - first - j, first + j - k, input) != 1
      if j > 0
        bc = last - 2 * k + 2 + j - 1
        return 0 if wassat_resource_clause2(lits, offs, lens, bc, 0 - first - j, first + j - k - 1) != 1
      j += 1
    scratch[n] = input; n += 1; cur -= k; last -= 2 * k - 1
    m[2] += 2 * k - 1
  0

-> wassat_resource_groups(lits, offs, lens, nv, nc, group, slot, minima, inputs, m, stop, deadline) (i64[] i64[] i64[] i64 i64 i32[] i32[] i32[] i32[] i64[] i64[] i64) i64
  scratch = i32[257]; ci = 0; ng = 0; ns = 0
  while ci < nc
    return 0 if (ci & 1023) == 0 && wassat_resource_poll(m, stop, deadline) != 0
    if lens[ci] == 1 && lits[offs[ci]] > 0
      n = wassat_resource_lower(lits, offs, lens, ci, scratch, m, stop, deadline)
      return 0 if m[11] != 0
      if n > 0 && (ns == 0 || n == ns)
        return 0 if ng >= 4096
        ns = n; j = 0
        while j < n
          v = scratch[n - 1 - j]
          return 0 if v < 1 || v > nv || group[v] != 0
          group[v] = ng + 1; slot[v] = j; inputs[ng * 256 + j] = v
          j += 1
        minima[ng] = scratch[256]; ng += 1
    ci += 1
  m[0] = ng; m[1] = ns
  ng > 0 ? 1 : 0

-> wassat_resource_decode(formula, m, stop, deadline = 0)
  nv = formula["nvars"]; nc = formula["flat_ncl"]; nl = formula["flat_nlits"]
  return nil if nv < 1 || nv > 1000000 || nc < 1 || nc > 5000000 || nl > 20000000
  lits = formula["flat_lits"]; offs = formula["flat_offs"]; lens = formula["flat_lens"]
  return nil if wassat_resource_flat_valid(lits, offs, lens, nv, nc, nl, m, stop, deadline) != 1
  group = i32[nv + 1]; slot = i32[nv + 1]; minima = i32[4096]; inputs = i32[4096 * 256]
  return nil if wassat_resource_groups(lits, offs, lens, nv, nc, group, slot, minima, inputs, m, stop, deadline) != 1
  {"group": group, "slot": slot, "minima": minima, "inputs": inputs}
