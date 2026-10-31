use ../lib/wassat

# Four keys, two locks, two positions, four depths. Each lock accepts two
# keys. Generate the encoding, including the complete OR equivalences,
# witness groups and physical adjacent-depth restrictions, from scratch.
-> keychart_test_formula(extra)
  clauses = []
  primary = 32
  base = 48
  i = 1
  while i <= primary
    clauses.push([i, i + 1, i + 2, i + 3])
    i += 4
  i = 1
  while i <= primary
    a = 0
    while a < 4
      b = a + 1
      while b < 4
        clauses.push([0 - i - a, 0 - i - b])
        b += 1
      a += 1
    i += 4
  k = 0
  while k < 4
    a = 0
    while a < 4
      b = 0
      while b < 4
        clauses.push([0 - (k * 8 + a + 1), 0 - (k * 8 + b + 5)]) if (a - b).abs > 1
        b += 1
      a += 1
    k += 1
  l = 0
  while l < 2
    d = 0
    while d < 8
      v = primary + l * 8 + d + 1
      a = l * 16 + d + 1
      b = a + 8
      clauses.push([0 - v, a, b])
      clauses.push([0 - a, v])
      clauses.push([0 - b, v])
      d += 1
    l += 1
  nv = base
  l = 0
  while l < 2
    k = 0
    while k < 4
      if k / 2 != l
        group = []
        d = 0
        while d < 8
          nv += 1
          group.push(nv)
          clauses.push([0 - nv, k * 8 + d + 1])
          clauses.push([0 - nv, 0 - (primary + l * 8 + d + 1)])
          d += 1
        clauses.push(group)
      k += 1
    l += 1
  extra.each -> (c) clauses.push(c)
  words = 0
  clauses.each -> (c) words += c.size
  lits = i64[words]
  offs = i64[clauses.size]
  lens = i64[clauses.size]
  ci = 0
  pos = 0
  clauses.each -> (c)
    offs[ci] = pos
    lens[ci] = c.size
    c.each -> (lit)
      lits[pos] = lit
      pos += 1
    ci += 1
  { "nvars": nv, "clauses": clauses, "flat_lits": lits,
    "flat_offs": offs, "flat_lens": lens, "flat_ncl": ci, "flat_nlits": words }

-> keychart_test_search(f, p, stop)
  a = wassat_raw_artifact(f, f["nvars"])
  wassat_keychart_prepare(p, a, stop)
  wassat_keychart_search(p, f, stop)
