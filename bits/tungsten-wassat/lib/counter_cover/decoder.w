use ../atomic_stop

# SAT-only candidate decoder. Every accepted model is checked on the original
# CNF; failure to recognize, finish, or satisfy it always means UNKNOWN.
-> wassat_counter_cover_poll(m, stop) (i64[] i64[]) i64
  m[1] += 1
  if wassat_stop_load(stop) != 0
    m[0] = 1
  elsif m[2] > 0 && clock_ms() >= m[2]
    m[0] = 2
  elsif m[3] > 20000000 || m[23] > 2000000000
    m[0] = 3
  m[0]

-> wassat_counter_cover_abs(x) (i64) i64
  x < 0 ? 0 - x : x

-> wassat_counter_cover_root(x, parent) (i64 i64[]) i64
  y = x; v = wassat_counter_cover_abs(y)
  while parent[v] != v
    y = y < 0 ? 0 - parent[v] : parent[v]
    v = wassat_counter_cover_abs(y)
  parent[wassat_counter_cover_abs(x)] = x < 0 ? 0 - y : y
  y

-> wassat_counter_cover_slot(a, b, c, d, keys, slots, m) (i64 i64 i64 i64 i64[] i64[] i64[]) i64
  t = 0
  if a > b
    t = a; a = b; b = t
  if c > d
    t = c; c = d; d = t
  if a > c
    t = a; a = c; c = t
  if b > d
    t = b; b = d; d = t
  if b > c
    t = b; b = c; c = t
  h = ((a * 73856093) ^ (b * 19349663) ^ (c * 83492791) ^ (d * 49979687)) & (slots.size - 1)
  tries = 0
  while tries < 128
    m[3] += 1
    ci = slots[h] - 1
    return h if ci < 0
    p = 4 * ci
    return h if keys[p] == a && keys[p + 1] == b && keys[p + 2] == c && keys[p + 3] == d
    h = (h + 1) & (slots.size - 1); tries += 1
  m[0] = 3
  -1

-> wassat_counter_cover_has(a, b, c, d, keys, slots, m) (i64 i64 i64 i64 i64[] i64[] i64[]) i64
  h = wassat_counter_cover_slot(a, b, c, d, keys, slots, m)
  h >= 0 && slots[h] != 0 ? 1 : 0

-> wassat_counter_cover_keys(lits, offs, lens, nc, parent, keys, widths, slots, m, stop) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64[] i64[]) i64
  h = 0
  while h < slots.size
    slots[h] = 0; h += 1
  scratch = i64[4]; ci = 0
  while ci < nc
    return 0 if (ci & 255) == 0 && wassat_counter_cover_poll(m, stop) != 0
    widths[ci] = 0; j = 0
    while j < 4
      keys[4 * ci + j] = 0; scratch[j] = 0; j += 1
    if lens[ci] <= 4
      n = 0; j = 0; tautology = false
      while j < lens[ci]
        x = wassat_counter_cover_root(lits[offs[ci] + j], parent); k = 0; duplicate = false
        while k < n
          tautology = true if scratch[k] == 0 - x
          duplicate = true if scratch[k] == x
          k += 1
        unless duplicate
          scratch[n] = x; n += 1
        j += 1
      unless tautology
        widths[ci] = n; j = 1
        while j < 4
          x = scratch[j]; k = j
          while k > 0 && scratch[k - 1] > x
            scratch[k] = scratch[k - 1]; k -= 1
          scratch[k] = x; j += 1
        j = 0
        while j < 4
          keys[4 * ci + j] = scratch[j]; j += 1
        h = wassat_counter_cover_slot(scratch[0], scratch[1], scratch[2], scratch[3], keys, slots, m)
        return 0 if h < 0
        slots[h] = ci + 1
    ci += 1
  1

-> wassat_counter_cover_pair_hash(a, b, mask) (i64 i64 i64) i64
  t = 0
  if a > b
    t = a; a = b; b = t
  ((a * 73856093) ^ (b * 19349663)) & mask

-> wassat_counter_cover_decode(formula, m, stop, deadline = 0)
  started = clock_ms(); m[2] = deadline
  return nil if wassat_counter_cover_poll(m, stop) != 0
  nv = formula["nvars"]; nc = formula["flat_ncl"]; nl = formula["flat_nlits"]
  return nil if nv < 1 || nv > 100000 || nc < 1 || nc > 500000 || nl < 1 || nl > 2000000
  lits = formula["flat_lits"]; offs = formula["flat_offs"]; lens = formula["flat_lens"]
  return nil if lits.size < nl || offs.size < nc || lens.size < nc
  present = i64[nv + 1]; ci = 0
  while ci < nc
    return nil if (ci & 255) == 0 && wassat_counter_cover_poll(m, stop) != 0
    o = offs[ci]; n = lens[ci]
    return nil if o < 0 || n < 1 || o > nl || n > nl - o
    j = 0
    while j < n
      v = wassat_counter_cover_abs(lits[o + j]); return nil if v < 1 || v > nv
      present[v] = 1
      j += 1
    ci += 1
  parent = i64[nv + 1]; v = 1
  while v <= nv
    parent[v] = v; v += 1
  cap = 1
  while cap < 2 * nc
    cap *= 2
  keys = i64[4 * nc]; widths = i64[nc]; slots = i64[cap]
  return nil if wassat_counter_cover_keys(lits, offs, lens, nc, parent, keys, widths, slots, m, stop) == 0
  ci = 0
  while ci < nc
    return nil if (ci & 255) == 0 && wassat_counter_cover_poll(m, stop) != 0
    if lens[ci] == 2
      a = lits[offs[ci]]; b = lits[offs[ci] + 1]
      if wassat_counter_cover_has(0 - a, 0 - b, 0, 0, keys, slots, m) == 1
        a = wassat_counter_cover_root(a, parent); b = wassat_counter_cover_root(0 - b, parent)
        return nil if a == 0 - b
        if wassat_counter_cover_abs(a) != wassat_counter_cover_abs(b)
          if wassat_counter_cover_abs(a) > wassat_counter_cover_abs(b)
            parent[wassat_counter_cover_abs(a)] = a < 0 ? 0 - b : b
          else
            parent[wassat_counter_cover_abs(b)] = b < 0 ? 0 - a : a
          m[4] += 1
    ci += 1
  return nil if wassat_counter_cover_keys(lits, offs, lens, nc, parent, keys, widths, slots, m, stop) == 0
  pol = i64[nv + 1]; units = i64[nv + 1]; ci = 0
  while ci < nc
    return nil if (ci & 255) == 0 && wassat_counter_cover_poll(m, stop) != 0
    if lens[ci] >= 5 || lens[ci] == 1
      j = 0
      while j < lens[ci]
        x = wassat_counter_cover_root(lits[offs[ci] + j], parent); v = wassat_counter_cover_abs(x); s = x < 0 ? -1 : 1
        if lens[ci] == 1
          return nil if units[v] != 0 && units[v] != s
          units[v] = s
        else
          return nil if pol[v] != 0 && pol[v] != s
          pol[v] = s
        j += 1
    ci += 1
  inputs = i64[nv + 1]; index = i64[nv + 1]; token = i64[nv + 1]; defined = i64[nv + 1]; ninputs = 0; v = 1
  while v <= nv
    if pol[v] != 0
      inputs[ninputs] = pol[v] * v; ninputs += 1; index[v] = ninputs
      token[v] = pol[v]; defined[v] = 1
    v += 1
  m[5] = ninputs
  return nil if ninputs < 5
  # Complete XOR truth tables, independent of original variable polarity/order.
  xs = i64[4]; signs = i64[4]; xor = i64[6 * nc]; nx = 0; ci = 0
  while ci < nc
    return nil if (ci & 255) == 0 && wassat_counter_cover_poll(m, stop) != 0
    n = widths[ci]
    if n == 3 || n == 4
      j = 0; k = 0
      while j < 4
        x = keys[4 * ci + j]
        if x != 0
          xs[k] = wassat_counter_cover_abs(x); signs[k] = x < 0 ? 1 : 0; k += 1
        j += 1
      j = 1
      while j < n
        x = xs[j]; s = signs[j]; k = j
        while k > 0 && xs[k - 1] > x
          xs[k] = xs[k - 1]; signs[k] = signs[k - 1]; k -= 1
        xs[k] = x; signs[k] = s; j += 1
      mask = 0; j = 0
      while j < n
        mask += signs[j] << j; j += 1
      if mask <= 1
        good = true; pat = 0
        while pat < (1 << n) && good
          parity = (pat ^ (pat >> 1) ^ (pat >> 2) ^ (pat >> 3)) & 1
          if parity == mask
            a = (pat & 1) != 0 ? 0 - xs[0] : xs[0]
            b = (pat & 2) != 0 ? 0 - xs[1] : xs[1]
            c = (pat & 4) != 0 ? 0 - xs[2] : xs[2]
            d = n == 4 ? xs[3] : 0
            d = 0 - d if (pat & 8) != 0
            good = false if wassat_counter_cover_has(a, b, c, d, keys, slots, m) == 0
          pat += 1
        if good
          xor[6 * nx] = n; xor[6 * nx + 1] = 1 - mask; j = 0
          while j < n
            xor[6 * nx + 2 + j] = xs[j]; j += 1
          nx += 1
    ci += 1
  m[6] = nx
  # Index each pair in a ternary clause to propose its third (carry) literal.
  heads = i64[cap]; links = i64[3 * nc]; ci = 0
  while ci < nc
    return nil if (ci & 255) == 0 && wassat_counter_cover_poll(m, stop) != 0
    if widths[ci] == 3
      j = 0; k = 0
      while j < 4
        if keys[4 * ci + j] != 0
          xs[k] = keys[4 * ci + j]; k += 1
        j += 1
      j = 0
      while j < 3
        a = xs[(j + 1) % 3]; b = xs[(j + 2) % 3]
        h = wassat_counter_cover_pair_hash(a, b, cap - 1); id = 3 * ci + j
        links[id] = heads[h]; heads[h] = id + 1; j += 1
    ci += 1
  steps = i64[6 * nx]; used = i64[nx]; ins = i64[3]; ns = 0; progress = true
  while progress
    progress = false; qi = 0; m[7] += 1
    while qi < nx
      m[3] += 1
      return nil if (qi & 255) == 0 && wassat_counter_cover_poll(m, stop) != 0
      if used[qi] == 0
        n = xor[6 * qi]; sum = 0; count = 0; weight = 0; good = true; neg = 0; j = 0
        while j < n
          v = xor[6 * qi + 2 + j]
          if token[v] != 0
            w = wassat_counter_cover_abs(token[v]); good = false if weight != 0 && weight != w; weight = w
            if count < 3
              ins[count] = token[v] < 0 ? 0 - v : v
            count += 1; neg ^= token[v] < 0 ? 1 : 0
          else
            good = false if sum != 0 || defined[v] != 0
            sum = v
          j += 1
        if good && sum != 0 && count == n - 1 && weight <= ninputs
          a = ins[0]; b = ins[1]; c = count == 3 ? ins[2] : 0
          h = wassat_counter_cover_pair_hash(0 - a, 0 - b, cap - 1); id = heads[h] - 1; tries = 0; carry = 0
          while id >= 0 && carry == 0 && tries < 256
            ci = id / 3; pos = id % 3; j = 0; k = 0
            while j < 4
              if keys[4 * ci + j] != 0
                xs[k] = keys[4 * ci + j]; k += 1
              j += 1
            d = xs[pos]; x = xs[(pos + 1) % 3]; y = xs[(pos + 2) % 3]
            if ((x == 0 - a && y == 0 - b) || (x == 0 - b && y == 0 - a)) && defined[wassat_counter_cover_abs(d)] == 0 && wassat_counter_cover_abs(d) != sum
              if count == 2
                if wassat_counter_cover_has(0 - d, a, 0, 0, keys, slots, m) == 1 && wassat_counter_cover_has(0 - d, b, 0, 0, keys, slots, m) == 1
                  carry = d
              else
                if wassat_counter_cover_has(0 - a, 0 - c, d, 0, keys, slots, m) == 1 && wassat_counter_cover_has(0 - b, 0 - c, d, 0, keys, slots, m) == 1 && wassat_counter_cover_has(a, b, 0 - d, 0, keys, slots, m) == 1 && wassat_counter_cover_has(a, c, 0 - d, 0, keys, slots, m) == 1 && wassat_counter_cover_has(b, c, 0 - d, 0, keys, slots, m) == 1
                  carry = d
            id = links[id] - 1; tries += 1; m[3] += 1
          if carry != 0
            used[qi] = 1; progress = true; sum = (neg ^ xor[6 * qi + 1]) == 1 ? 0 - sum : sum
            j = 0
            while j < count
              token[wassat_counter_cover_abs(ins[j])] = 0; j += 1
            token[wassat_counter_cover_abs(sum)] = sum < 0 ? 0 - weight : weight
            token[wassat_counter_cover_abs(carry)] = carry < 0 ? 0 - 2 * weight : 2 * weight
            defined[wassat_counter_cover_abs(sum)] = 1; defined[wassat_counter_cover_abs(carry)] = 1
            steps[6 * ns] = count; steps[6 * ns + 1] = a; steps[6 * ns + 2] = b; steps[6 * ns + 3] = c
            steps[6 * ns + 4] = sum; steps[6 * ns + 5] = carry; ns += 1
      qi += 1
  m[8] = ns
  target = 0; remaining = 0; v = 1
  while v <= nv
    if token[v] != 0
      return nil if units[v] == 0
      remaining += 1; target += wassat_counter_cover_abs(token[v]) if (token[v] > 0) == (units[v] > 0)
    if parent[v] == v && defined[v] == 0 && present[v] != 0
      return nil
    v += 1
  m[9] = remaining; m[10] = target
  return nil if target < 1 || target > ninputs
  row_offs = i64[nc + 1]; rv = i64[nl]; seen = i64[nv + 1]; nr = 0; terms = 0; ci = 0
  while ci < nc
    return nil if (ci & 255) == 0 && wassat_counter_cover_poll(m, stop) != 0
    j = 0; good = true
    while j < lens[ci] && good
      x = wassat_counter_cover_root(lits[offs[ci] + j], parent); v = wassat_counter_cover_abs(x)
      good = false if pol[v] == 0 || (x > 0) != (pol[v] > 0)
      j += 1
    if good
      row_offs[nr] = terms; j = 0
      while j < lens[ci]
        x = wassat_counter_cover_root(lits[offs[ci] + j], parent); v = wassat_counter_cover_abs(x)
        if seen[v] != ci + 1
          rv[terms] = index[v] - 1; terms += 1; seen[v] = ci + 1
        j += 1
      nr += 1
    ci += 1
  row_offs[nr] = terms; m[11] = nr; m[12] = terms; m[13] = clock_ms() - started
  return nil if nr == 0 || wassat_counter_cover_poll(m, stop) != 0
  {"parent": parent, "inputs": inputs, "steps": steps, "nsteps": ns, "ninputs": ninputs, "target": target, "rows": row_offs, "terms": rv, "nrows": nr, "nterms": terms}
