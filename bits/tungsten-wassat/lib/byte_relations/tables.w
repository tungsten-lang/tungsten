# Recover complete <=8-free-input relations from asserted implications between
# equality cubes. Wider syntactic inputs must be fixed by original-clause UP.
# Group stride80: full input width,output width,free width,rows,start,end,
# 32 original input IDs,32 output IDs,8 free input IDs,2 spare words.
-> wassat_byte_tables(program, inputs, units, nu, roots, groups, tables, slots, scratch, m, stop, deadline) (i64[] i64[] i64[] i64 i8[] i64[] i64[] i64[] i64[] i64[] i64[] i64) i64
  i = 0
  while i < tables.size
    tables[i] = -1; i += 1
  ng = 0; u = 0; mask = slots.size - 1
  while u < nu
    return 0 if (u & 255) == 0 && wassat_byte_poll(m, stop, deadline) != 0
    lit = units[u]; b = 8 * wassat_byte_abs(lit); u += 1
    next unless program[b] == 1 && program[b + 1] == -lit && program[b + 2] == 2
    a = inputs[program[b + 3]]; c = inputs[program[b + 3] + 1]
    if a < 0 && c > 0
      tmp = a; a = c; c = tmp
    next unless a > 0 && c < 0
    c = -c; ab = 8 * a; cb = 8 * c
    next unless program[ab] == 1 && program[ab + 1] == a && program[cb] == 1 && program[cb + 1] == c
    ni = program[ab + 2]; no = program[cb + 2]
    next if ni < 1 || ni > 32 || no < 1 || no > 32
    j = 0
    while j < ni
      scratch[j] = wassat_byte_abs(inputs[program[ab + 3] + j]); j += 1
    j = 0
    while j < no
      scratch[32 + j] = wassat_byte_abs(inputs[program[cb + 3] + j]); j += 1
    part = 0; good = 1
    while part < 2
      n = part == 0 ? ni : no; off = part * 32
      j = 1
      while j < n
        x = scratch[off + j]; k = j - 1
        while k >= 0 && scratch[off + k] > x
          scratch[off + k + 1] = scratch[off + k]; k -= 1
        scratch[off + k + 1] = x; j += 1
      j = 1
      while j < n
        good = 0 if scratch[off + j - 1] == scratch[off + j]; j += 1
      part += 1
    next if good == 0
    free = 0; pat = 0; j = 0
    while j < ni && good == 1
      v = scratch[j]; k = 0
      while k < ni && wassat_byte_abs(inputs[program[ab + 3] + k]) != v
        k += 1
      bit = inputs[program[ab + 3] + k] > 0 ? 1 : 0
      if roots[v] == 0
        if free == 8
          good = 0
        else
          scratch[64 + free] = v; pat |= bit << free; free += 1
      elsif roots[v] != (bit == 1 ? 1 : -1)
        good = 0
      j += 1
    next if good == 0
    value = 0; j = 0
    while j < no
      v = scratch[32 + j]; k = 0
      while k < no && wassat_byte_abs(inputs[program[cb + 3] + k]) != v
        k += 1
      value |= 1 << j if inputs[program[cb + 3] + k] > 0
      j += 1
    h = (ni * 33 + no) & mask; part = 0
    while part < 2
      n = part == 0 ? ni : no; off = part * 32; j = 0
      while j < n
        h = ((h * 48271) ^ scratch[off + j]) & mask; j += 1
      part += 1
    found = -1; probes = 0
    while slots[h] != 0 && found < 0
      g = slots[h] - 1; p = 80 * g
      same = groups[p] == ni && groups[p + 1] == no ? 1 : 0
      part = 0
      while part < 2 && same == 1
        n = part == 0 ? ni : no; off = part * 32; j = 0
        while j < n && same == 1
          same = 0 if groups[p + 6 + off + j] != scratch[off + j]; j += 1
        part += 1
      if same == 1
        found = g
      else
        probes += 1
        return 0 if probes > 1024
        h = (h + 1) & mask
    if found < 0
      return 0 if 80 * (ng + 1) > groups.size || 256 * (ng + 1) > tables.size
      found = ng; ng += 1; slots[h] = ng; p = 80 * found
      groups[p] = ni; groups[p + 1] = no; groups[p + 2] = free; groups[p + 4] = program[b + 5]; groups[p + 79] = wassat_byte_abs(lit)
      part = 0
      while part < 2
        n = part == 0 ? ni : no; off = part * 32; j = 0
        while j < n
          groups[p + 6 + off + j] = scratch[off + j]; j += 1
        part += 1
      j = 0
      while j < free
        groups[p + 70 + j] = scratch[64 + j]; j += 1
    p = 80 * found; old = tables[256 * found + pat]
    return 0 if old >= 0 && old != value
    groups[p + 3] += 1 if old < 0
    tables[256 * found + pat] = value
    groups[p + 5] = program[b + 6]; groups[p + 78] = wassat_byte_abs(lit)
    m[17] += 1
  m[16] = ng; g = 0
  while g < ng
    m[18] += 1 if groups[80 * g + 3] == (1 << groups[80 * g + 2])
    g += 1
  1

-> wassat_byte_tables_hash(groups, tables, ng) (i64[] i64[] i64) i64
  h = 0; g = 0
  while g < ng
    p = 80 * g; j = 0
    while j < 80
      h = ((h * 48271) ^ groups[p + j]) & 2147483647; j += 1
    j = 0
    while j < 256
      h = ((h * 48271) ^ tables[256 * g + j]) & 2147483647; j += 1
    g += 1
  h
