# Signed union-find: each union is an equality entailed by an original gate
# or by congruence of two previously checked definitions.
-> wassat_byte_find(parent, lit) (i64[] i64) i64
  v = wassat_byte_abs(lit); root = v; parity = 1
  while parent[root] != root
    p = parent[root]; parity = -parity if p < 0; root = wassat_byte_abs(p)
  node = v; suffix = parity
  while parent[node] != node
    p = parent[node]; parent[node] = suffix * root
    suffix = -suffix if p < 0
    node = wassat_byte_abs(p)
  lit > 0 ? parity * root : -parity * root

-> wassat_byte_union(parent, a, b, m) (i64[] i64 i64 i64[]) i64
  a = wassat_byte_find(parent, a); b = wassat_byte_find(parent, b)
  return 1 if a == b
  return -1 if a == -b
  if wassat_byte_abs(a) > wassat_byte_abs(b)
    tmp = a; a = b; b = tmp
  parent[wassat_byte_abs(b)] = b > 0 ? a : -a
  m[8] += 1
  1

-> wassat_byte_congruence(program, inputs, roots, parent, nv, keys, slots, scratch, m, stop, deadline) (i64[] i64[] i8[] i64[] i64 i64[] i64[] i64[] i64[] i64[] i64) i64
  v = 1
  while v <= nv + 1
    parent[v] = v; v += 1
  v = 1
  while v <= nv
    if roots[v] != 0
      return -1 if wassat_byte_union(parent, v, roots[v] > 0 ? nv + 1 : -nv - 1, m) < 0
    v += 1
  pass = 0; mask = slots.size - 1
  while pass < 16
    before = m[8]; used = 1; j = 0
    while j < slots.size
      slots[j] = 0; j += 1
    v = 1
    while v <= nv
      return 0 if (v & 1023) == 0 && wassat_byte_poll(m, stop, deadline) != 0
      b = 8 * v; kind = program[b]; out = program[b + 1]
      nf = program[b + 2]; off = program[b + 3]; n = 0
      ct = wassat_byte_find(parent, nv + 1)
      if kind == 1
        fixed = 0; j = 0
        while j < nf && fixed == 0
          x = wassat_byte_find(parent, inputs[off + j])
          if x == -ct
            fixed = 1
          elsif x != ct
            k = 0
            while k < n && scratch[k] != x
              fixed = 1 if scratch[k] == -x
              k += 1
            if k == n
              scratch[n] = x; n += 1
          j += 1
        if fixed == 1
          return -1 if wassat_byte_union(parent, out, -ct, m) < 0
          v += 1; next
        if n <= 1
          return -1 if wassat_byte_union(parent, out, n == 0 ? ct : scratch[0], m) < 0
          v += 1; next
        j = 1
        while j < n
          x = scratch[j]; k = j - 1
          while k >= 0 && scratch[k] > x
            scratch[k + 1] = scratch[k]; k -= 1
          scratch[k + 1] = x; j += 1
      elsif kind == 2
        a = wassat_byte_find(parent, inputs[off]); c = wassat_byte_find(parent, inputs[off + 1])
        y = wassat_byte_find(parent, out); flip = program[b + 4] & 1
        if wassat_byte_abs(a) == wassat_byte_abs(ct)
          flip ^= a == ct ? 1 : 0
          return -1 if wassat_byte_union(parent, out, flip == 0 ? c : -c, m) < 0
          v += 1; next
        if wassat_byte_abs(c) == wassat_byte_abs(ct)
          flip ^= c == ct ? 1 : 0
          return -1 if wassat_byte_union(parent, out, flip == 0 ? a : -a, m) < 0
          v += 1; next
        if wassat_byte_abs(y) == wassat_byte_abs(ct)
          flip ^= y == ct ? 1 : 0
          return -1 if wassat_byte_union(parent, a, flip == 0 ? c : -c, m) < 0
          v += 1; next
        if wassat_byte_abs(a) == wassat_byte_abs(c)
          flip ^= a != c ? 1 : 0
          return -1 if wassat_byte_union(parent, out, flip == 0 ? -ct : ct, m) < 0
          v += 1; next
        flip ^= a < 0 ? 1 : 0; flip ^= c < 0 ? 1 : 0
        out = -out if flip != 0
        a = wassat_byte_abs(a); c = wassat_byte_abs(c); n = 2
        scratch[0] = a < c ? a : c; scratch[1] = a < c ? c : a
      else
        v += 1; next
      h = kind; j = 0
      while j < n
        h = ((h * 48271) ^ scratch[j]) & mask; j += 1
      found = 0; probes = 0
      while slots[h] != 0 && found == 0
        at = slots[h]; same = keys[at + 1] == kind && keys[at + 2] == n ? 1 : 0
        j = 0
        while j < n && same == 1
          same = 0 if keys[at + 3 + j] != scratch[j]
          j += 1
        if same == 1
          return -1 if wassat_byte_union(parent, out, keys[at], m) < 0
          found = 1
        else
          probes += 1
          return 0 if probes > 1024
          h = (h + 1) & mask
        m[9] += 1
      if found == 0
        return 0 if used + n + 3 > keys.size
        slots[h] = used; keys[used] = out; keys[used + 1] = kind; keys[used + 2] = n
        j = 0
        while j < n
          keys[used + 3 + j] = scratch[j]; j += 1
        used += n + 3
      v += 1
    pass += 1; m[10] = pass
    return 1 if m[8] == before
  0
