use ../lib/wassat

-> rectangle_test_formula(n, k, mutation = "", rename = false)
  nv = n*n*k; cs = []; r = 0
  while r < n
    c = 0
    while c < n
      row = []; a = 0
      while a < k
        row.push((r*n+c)*k+a+1); a += 1
      cs.push(row)
      a = 0
      while a < k
        b = a+1
        while b < k
          cs.push([-((r*n+c)*k+a+1), -((r*n+c)*k+b+1)])
          b += 1
        a += 1
      c += 1
    r += 1
  first_rect = cs.size; r = 0
  while r < n
    s = r+1
    while s < n
      c = 0
      while c < n
        d = c+1
        while d < n
          a = 0
          while a < k
            cs.push([-((r*n+c)*k+a+1),-((r*n+d)*k+a+1),-((s*n+c)*k+a+1),-((s*n+d)*k+a+1)])
            a += 1
          d += 1
        c += 1
      s += 1
    r += 1
  cs[0] = cs[-1] if mutation == "domain"
  cs[1] = cs[-1] if mutation == "amo"
  cs[first_rect] = cs[-1] if mutation == "rectangle"
  cs[first_rect][0] = cs[first_rect][1] if mutation == "repeat"
  cs[1][0] = -cs[1][0] if mutation == "polarity"
  cs[1][0] = nv+1 if mutation == "out_of_range"
  nl = 0; cs.each -> (row) nl += row.size
  lits = i64[nl]; offs = i64[cs.size]; lens = i64[cs.size]; at = 0; ci = 0
  cs = cs.reverse if rename
  cs.each -> (row)
    row = row.reverse if rename
    offs[ci] = at; lens[ci] = row.size
    row.each -> (lit)
      l = lit
      if rename
        v = l.abs; sign = l < 0 ? -1 : 1
        sign = -sign if (v % 3) == 0
        l = sign*(nv-v+1)
      lits[at] = l; at += 1
    ci += 1
  {"nvars": nv, "flat_ncl": ci, "flat_nlits": nl, "flat_lits": lits, "flat_offs": offs, "flat_lens": lens}
