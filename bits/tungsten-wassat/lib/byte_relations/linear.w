# Heuristically isolate a zero-guarded byte relation. Isolation is only a
# proposal: the affine map is accepted only after a full local CDCL refutation.
-> wassat_byte_region(program, inputs, groups, g, scratch) (i64[] i64[] i64[] i64 i64[]) i64
  return 0 if g < 1
  p = 80 * g; prev = p - 80
  return 0 unless groups[p] == 32 && groups[p + 1] == 8 && groups[p + 2] == 8
  return 0 unless groups[prev] == 8 && groups[prev + 1] == 8 && groups[prev + 2] == 8
  v = groups[p + 78]; nv = program.size / 8 - 1
  j = 0; indicator = 0; finish = 0
  while j < 8
    v += 1
    while v <= nv && program[8 * v] == 0
      v += 1
    return 0 if v > nv
    b = 8 * v
    return 0 unless program[b] == 1 && program[b + 1] == v && program[b + 2] == 2
    a = inputs[program[b + 3]]; c = inputs[program[b + 3] + 1]
    if a == groups[p + 38 + j]
      a = c; c = groups[p + 38 + j]
    return 0 unless c == groups[p + 38 + j]
    indicator = a if j == 0
    return 0 unless indicator > 0 && a == indicator
    scratch[10 + j] = v; finish = program[b + 6]; j += 1
  first = groups[prev + 79]; v = first - 1; floor = first > 64 ? first - 64 : 1
  while v >= floor
    b = 8 * v
    if program[b] == 1 && program[b + 1] == v && program[b + 2] == 8
      match = 1; j = 0
      while j < 8 && match == 1
        x = inputs[program[b + 3] + j]; k = 0
        while k < 8 && groups[prev + 6 + k] != -x
          k += 1
        match = 0 if k == 8; j += 1
      if match == 1
        nextv = v + 1
        while nextv < first && program[8 * nextv] == 0
          nextv += 1
        q = 8 * nextv
        if nextv < first && program[q] == 2
          a = inputs[program[q + 3]]; c = inputs[program[q + 3] + 1]
          if (a == indicator && c == v) || (c == indicator && a == v)
            scratch[0] = program[b + 5]; scratch[1] = finish; j = 0
            while j < 8
              scratch[2 + j] = groups[prev + 6 + j]; j += 1
            return 1
    v -= 1
  0

-> wassat_byte_region_flat(lits, offs, lens, region, mapping, mapped, flat, local) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  i = 1
  while i <= local[0]
    mapping[mapped[i]] = 0; i += 1
  nv = 8; i = 0
  while i < 8
    v = region[2 + i]; mapping[v] = i + 1; mapped[i + 1] = v; i += 1
  ci = region[0]; used = 0
  return 0 if region[1] - ci > 40000
  while ci < region[1]
    j = 0
    return 0 if used + lens[ci] + 1 > flat.size
    while j < lens[ci]
      l = lits[offs[ci] + j]; v = wassat_byte_abs(l); target = mapping[v]
      if target == 0
        nv += 1
        return 0 if nv >= mapped.size
        target = nv; mapping[v] = nv; mapped[nv] = v
      flat[used] = l > 0 ? target : -target; used += 1; j += 1
    flat[used] = 0; used += 1; ci += 1
  local[0] = nv; local[1] = region[1] - region[0]; local[2] = used
  i = 0
  while i < 8
    local[3 + i] = mapping[region[10 + i]]
    return 0 if local[3 + i] == 0
    i += 1
  1

-> wassat_byte_same_flat(flat, local, other, meta) (i64[] i64[] i64[] i64[]) i64
  i = 0
  while i < 11
    return 0 if local[i] != meta[i]
    i += 1
  i = 0
  while i < local[2]
    return 0 if flat[i] != other[i]
    i += 1
  1

-> wassat_byte_linear_oracle(flat, local, stop, deadline, m)
  return nil if wassat_byte_poll(m, stop, deadline) != 0
  clauses = []; c = []; i = 0
  while i < local[2]
    if flat[i] == 0
      clauses.push(c); c = []
    else
      c.push(flat[i])
    i += 1
  s = Wassat.new(local[0], clauses, 0, 0)
  s.set_stop_cell(stop); s.disable_walk; s.disable_inprocess; s.enable_fixed_caps
  assumptions = [-1, -2, -3, -4, -5, -6, -7, -8]
  images = i64[9]; i = 0; prior_conflicts = 0
  while i < 9
    return nil if wassat_byte_poll(m, stop, deadline) != 0
    a = i == 0 ? 0 : 1 << (i - 1); j = 0
    while j < 8
      assumptions[j] = (a >> j) & 1 == 1 ? j + 1 : -j - 1; j += 1
    r = s.solve_assuming_budget(assumptions, 20000)
    m[21] += 1; m[40] += r["conflicts"] - prior_conflicts
    prior_conflicts = r["conflicts"]
    return nil unless r["status"] == 1
    value = 0; j = 0
    while j < 8
      value |= 1 << j if s.value(local[3 + j]) == 1; j += 1
    images[i] = value; i += 1
  # The samples propose a map. The mismatch formula proves it universally.
  nv = local[0]; diffs = []; bit = 0
  while bit < 8
    expected = 0; j = 0
    while j < 8
      if ((images[j + 1] ^ images[0]) >> bit) & 1 == 1
        if expected == 0
          expected = j + 1
        else
          a = expected; b = j + 1; nv += 1
          clauses.push([a, b, -nv]); clauses.push([-a, -b, -nv])
          clauses.push([a, -b, nv]); clauses.push([-a, b, nv]); expected = nv
      j += 1
    if expected == 0
      nv += 1; expected = nv; clauses.push([-expected])
    expected = -expected if (images[0] >> bit) & 1 == 1
    b = local[3 + bit]; nv += 1
    clauses.push([expected, b, -nv]); clauses.push([-expected, -b, -nv])
    clauses.push([expected, -b, nv]); clauses.push([-expected, b, nv]); diffs.push(nv); bit += 1
  clauses.push(diffs)
  p = Wassat.new(nv, clauses, 0, 0); p.set_stop_cell(stop)
  p.disable_walk; p.disable_inprocess; p.enable_fixed_caps
  r = p.solve_budget(256); m[41] += r["conflicts"]
  while r["status"] == 0 && r["conflicts"] < 20000
    return nil if wassat_byte_poll(m, stop, deadline) != 0
    previous = r["conflicts"]
    left = 20000 - previous; left = 256 if left > 256
    r = p.solve_budget(left); m[41] += r["conflicts"] - previous
    return nil if r["status"] == 0 && r["conflicts"] <= previous
  return nil if r["status"] != -1 || wassat_byte_poll(m, stop, deadline) != 0
  m[22] += 1
  images

-> wassat_byte_linear_groups(formula, program, inputs, groups, tables, m, stop, deadline)
  nv = formula["nvars"]; mapping = nil; mapped = nil; flat = nil
  local = i64[11]; region = i64[18]
  cache_flat = []; cache_meta = []; cache_images = []
  ng = m[16]; g = 0
  while g < ng
    return 0 if wassat_byte_poll(m, stop, deadline) != 0
    if wassat_byte_region(program, inputs, groups, g, region) == 1
      if mapping == nil
        # Arithmetic scratch is unnecessary for plain lookup circuits. Bound
        # each buffer by the input as well as the fixed worker ceiling.
        map_cap = nv + 1; map_cap = 8193 if map_cap > 8193
        flat_cap = formula["flat_nlits"] + formula["flat_ncl"]
        flat_cap = 200000 if flat_cap > 200000
        mapping = i64[nv + 1]; mapped = i64[map_cap]; flat = i64[flat_cap]
      return 0 if wassat_byte_region_flat(formula["flat_lits"], formula["flat_offs"], formula["flat_lens"], region, mapping, mapped, flat, local) == 0
      hit = -1; k = 0
      while k < cache_flat.size && hit < 0
        hit = k if wassat_byte_same_flat(flat, local, cache_flat[k], cache_meta[k]) == 1
        k += 1
      if hit < 0
        return 0 if cache_flat.size >= 4
        images = wassat_byte_linear_oracle(flat, local, stop, deadline, m)
        return 0 if images == nil
        fc = i64[local[2]]; mc = i64[11]; j = 0
        while j < local[2]
          fc[j] = flat[j]; j += 1
        j = 0
        while j < 11
          mc[j] = local[j]; j += 1
        hit = cache_flat.size
        cache_flat.push(fc); cache_meta.push(mc); cache_images.push(images)
        m[20] += 1
      images = cache_images[hit]
      p = 80 * m[16]
      return 0 if p + 80 > groups.size || 256 * (m[16] + 1) > tables.size
      groups[p] = 8; groups[p + 1] = 8; groups[p + 2] = 8; groups[p + 3] = 256
      groups[p + 4] = region[0]; groups[p + 5] = region[1]
      j = 0
      while j < 8
        groups[p + 6 + j] = region[2 + j]; groups[p + 70 + j] = region[2 + j]
        groups[p + 38 + j] = region[10 + j]; j += 1
      a = 0
      while a < 256
        val = images[0]; j = 0
        while j < 8
          val ^= images[j + 1] ^ images[0] if (a >> j) & 1 == 1; j += 1
        tables[256 * m[16] + a] = val; a += 1
      m[16] += 1; m[18] += 1; m[19] += 1
    g += 1
  1
