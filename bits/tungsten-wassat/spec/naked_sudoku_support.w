use ../lib/wassat

# Independent small CNF encoder. Conjunction witnesses are fresh and only
# imply their terms; their numbering/grouping need not match a CSP compiler.
+ NakedTestFormula
  ro :clauses, :sections, :nv

  -> new(@steps, row_clues)
    @n = 4; @cells = 16; @initial = i64[16]; @clauses = []; @sections = {}
    row_clues.each -> (c) @initial[c % 4 * 4 + c / 4] = 1
    next_var = 1; c = 0
    while c < 16
      if @initial[c] != 0
        @initial[c] = next_var; next_var += 3
      c += 1
    @x0end = next_var - 1; @xend = @x0end + steps * 64
    @ystart = @xend + 1; @nv = @xend + (steps + 1) * 64
    @rules = i64[(steps + 1) * 64 * 4]; @singles = i64[(steps + 1) * 64]
    s = 0
    while s <= steps
      c = 0
      while c < 16
        d = 0
        while d < 4
          slot = s * 64 + c * 4 + d
          if s == 0 || @initial[c] == 0
            k = 0
            while k < 4
              @rules[slot * 4 + k] = fresh; k += 1
          @singles[slot] = fresh if s > 0 && @initial[c] == 0
          d += 1
        c += 1
      s += 1
    build

  -> fresh
    @nv += 1
    @nv

  -> emit(row)
    @clauses.push(row)
    0

  -> dnf(terms)
    row = []; helpers = []; taut = false
    terms.each -> (t)
      if t != nil
        if t.size == 0
          taut = true
        elsif t.size == 1
          row.push(t[0]) unless row.include?(t[0])
        else
          a = fresh; row.push(a)
          t.each -> (v) helpers.push([-a, v])
    return 0 if taut
    emit(row)
    helpers.each -> (h) emit(h)
    0

  -> eq_value(s, c, d)
    if s == 0
      return d == 0 ? [] : nil if @initial[c] == 0
      return nil if d == 0
    low = s == 0 ? 1 : 0
    start = s == 0 ? @initial[c] : @x0end + 1 + 4 * ((s - 1) * 16 + c)
    row = []
    row.push(-(start + d - low - 1)) if d > low
    row.push(start + d - low) if d < 4
    row

  -> neg(term)
    return [[]] if term == nil
    out = []; term.each -> (v) out.push([-v])
    out

  -> y(s, c, d)
    @ystart + s * 64 + d * 16 + c

  -> build
    @sections["chains"] = @clauses.size
    c = 0
    while c < 16
      if @initial[c] > 0
        v = @initial[c]; emit([-v, v + 1]); emit([-v - 1, v + 2])
      c += 1
    i = 0
    while i < @steps * 16
      v = @x0end + 1 + i * 4; k = 0
      while k < 3
        emit([-v - k, v + k + 1]); k += 1
      i += 1
    @sections["placements"] = @clauses.size; s = 1
    while s <= @steps
      c = 0
      while c < 16
        d = 0
        while d < 4
          cur = eq_value(s, c, d + 1); old = eq_value(s - 1, c, d + 1)
          z = @singles[s * 64 + c * 4 + d]
          terms = neg(cur); terms.push(old); terms.push([z]) if z > 0
          dnf(terms)
          terms = neg(old); terms.push(cur); dnf(terms)
          dnf([[-z], cur]) if z > 0
          d += 1
        c += 1
      s += 1
    @sections["candidates"] = @clauses.size; s = 0
    while s <= @steps
      c = 0
      while c < 16
        d = 0
        while d < 4
          yy = y(s, c, d)
          if s > 0 && @initial[c] > 0
            emit([-yy, y(s - 1, c, d)]); emit([yy, -y(s - 1, c, d)])
          else
            row = [yy]; term = []; k = 0
            while k < 4
              z = @rules[(s * 64 + c * 4 + d) * 4 + k]
              row.push(z); term.push(-z); k += 1
            if s > 0
              row.push(-y(s - 1, c, d)); term.push(y(s - 1, c, d))
            emit(row); dnf([[-yy], term])
          d += 1
        c += 1
      s += 1
    @sections["progress"] = @clauses.size; s = 1
    while s <= @steps
      pairs = []; witnesses = []; d = 0
      while d < 4
        c = 0
        while c < 16
          if @initial[c] == 0
            pairs.push([y(s - 1, c, d), y(s, c, d)])
            witnesses.push([fresh, fresh, fresh])
          c += 1
        d += 1
      g = fresh; h = fresh; emit([g, h]); row = []
      witnesses.each -> (t) row.push(t[2])
      row.push(-g); emit(row); i = 0
      while i < pairs.size
        old = pairs[i][0]; cur = pairs[i][1]
        a = witnesses[i][0]; b = witnesses[i][1]; diff = witnesses[i][2]
        emit([a, b, -diff, -g]); emit([old, -a, -diff, -g]); emit([-cur, -a, -diff, -g])
        emit([-old, -b, -diff, -g]); emit([cur, -b, -diff, -g]); i += 1
      c = 0
      while c < 16
        emit([-h, -eq_value(s, c, 0)[0]]) if @initial[c] == 0
        c += 1
      s += 1
    @sections["rules"] = @clauses.size; s = 0
    while s <= @steps
      c = 0
      while c < 16
        if s == 0 || @initial[c] == 0
          d = 0
          while d < 4
            k = 0
            while k < 4
              z = @rules[(s * 64 + c * 4 + d) * 4 + k]; atoms = []; other = 0
              while other < 16
                member = k == 0 ? other == c : other != c
                member = member && other % 4 == c % 4 if k == 1
                member = member && other / 4 == c / 4 if k == 2
                member = member && other % 4 / 2 == c % 4 / 2 && other / 8 == c / 8 if k == 3
                if member
                  if k == 0
                    v = 0
                    while v < 4
                      atoms.push(eq_value(s, other, v + 1)) if v != d
                      v += 1
                  else
                    atoms.push(eq_value(s, other, d + 1))
                other += 1
              terms = [[-z]]; atoms.each -> (a) terms.push(a)
              dnf(terms)
              atoms.each -> (a)
                terms = [[z]]; neg(a).each -> (t) terms.push(t)
                dnf(terms)
              k += 1
            d += 1
        c += 1
      s += 1
    @sections["singles"] = @clauses.size; s = 1
    while s <= @steps
      c = 0
      while c < 16
        if @initial[c] == 0
          d = 0
          while d < 4
            z = @singles[s * 64 + c * 4 + d]; row = [z]; v = 0
            while v < 4
              row.push(y(s - 1, c, v)) if v != d
              v += 1
            emit(row); v = 0
            while v < 4
              emit([-z, -y(s - 1, c, v)]) if v != d
              v += 1
            d += 1
        c += 1
      s += 1
    @sections["nonempty"] = @clauses.size; s = 0
    while s <= @steps
      c = 0
      while c < 16
        emit([y(s, c, 0), y(s, c, 1), y(s, c, 2), y(s, c, 3)]); c += 1
      s += 1
    0

  -> formula(mutation = "")
    if mutation != ""
      ci = @sections[mutation]
      @clauses[ci] = [@nv] if ci != nil
    nl = 0; @clauses.each -> (row) nl += row.size
    lits = i64[nl]; offs = i64[@clauses.size]; lens = i64[@clauses.size]; at = 0; ci = 0
    @clauses.each -> (row)
      offs[ci] = at; lens[ci] = row.size
      row.each -> (v)
        lits[at] = v; at += 1
      ci += 1
    {"nvars": @nv, "flat_ncl": ci, "flat_nlits": nl, "flat_lits": lits, "flat_offs": offs, "flat_lens": lens}
