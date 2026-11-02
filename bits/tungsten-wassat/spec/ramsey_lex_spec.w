use spec
use ../lib/ramsey_lex

-> lex_flat(nv, rows)
  total = 0
  rows.each -> (row) total += row.size
  lits = i64[total]
  offs = i64[rows.size]
  lens = i64[rows.size]
  ci = 0
  pos = 0
  rows.each -> (row)
    offs[ci] = pos
    lens[ci] = row.size
    row.each -> (lit)
      lits[pos] = lit
      pos += 1
    ci += 1
  { "nvars": nv, "nclauses": rows.size, "clauses": [], "boxed": false,
    "flat_lits": lits, "flat_offs": offs, "flat_lens": lens,
    "flat_ncl": rows.size, "flat_nlits": total }

-> lex_rows(n, positive, negative)
  rows = []
  code = 0
  while code < (1 << n)
    size = 0
    v = 0
    while v < n
      size += 1 if (code & (1 << v)) != 0
      v += 1
    color = 0
    while color < 2
      if (color == 0 && positive > 0 && size == positive) || (color == 1 && negative > 0 && size == negative)
        row = []
        e = 1
        i = 0
        while i < n
          j = i + 1
          while j < n
            row.push(color == 0 ? e : 0 - e) if (code & (1 << i)) != 0 && (code & (1 << j)) != 0
            e += 1
            j += 1
          i += 1
        rows.push(row)
      color += 1
    code += 1
  rows

-> lex_encoding_holds(lits, offs, lens, nc, code)
  ci = 0
  while ci < nc
    hit = false
    j = 0
    while j < lens[ci]
      lit = lits[offs[ci] + j]
      v = lit < 0 ? 0 - lit : lit
      truth = (code & (1 << (v - 1))) != 0
      hit = true if truth == (lit > 0)
      j += 1
    return false unless hit
    ci += 1
  true

describe "Complete-clique lex-leader reduction" ->
  it "recognizes complete signed families and preserves every original clause" ->
    n = 3
    while n <= 7
      f = lex_flat(n * (n - 1) / 2, lex_rows(n, 3, n > 3 ? 4 : 3))
      before = f["flat_lits"].to_s
      p = wassat_ramsey_lex_lift(f)
      expect(p != nil).to eq(true)
      expect(f["flat_lits"].to_s).to eq(before)
      work = p["work"]
      expect(work[0]).to eq(1)
      expect(work[6]).to eq(f["flat_ncl"])
      expect(work[12]).to eq(n * (n - 1) / 2)
      expect(work[11]).to eq(n * (n - 1) / 2 * (n - 3))
      g = p["formula"]
      i = 0
      while i < f["flat_nlits"]
        expect(g["flat_lits"][i]).to eq(f["flat_lits"][i])
        i += 1
      n += 1

  it "does not confuse a missing clique plus a duplicate with complete coverage" ->
    rows = lex_rows(5, 3, 3)
    rows[0] = rows[1]
    expect(wassat_ramsey_lex_lift(lex_flat(10, rows))).to eq(nil)
    f = lex_flat(10, lex_rows(5, 3, 3))
    f["flat_ncl"] -= 1
    expect(wassat_ramsey_lex_lift(f)).to eq(nil)

  it "allows repeated clauses and single-color complete families" ->
    rows = lex_rows(5, 3, 0)
    rows.push(rows[0])
    rows.push(rows[0])
    p = wassat_ramsey_lex_lift(lex_flat(10, rows))
    expect(p != nil).to eq(true)
    expect(p["work"][5]).to eq(1)
    expect(p["work"][6]).to eq(10)
    expect(p["work"][7]).to eq(2)

  it "rejects mixed signs, duplicate edges, invalid endpoints and unsupported widths" ->
    [0, 2147483647, -9223372036854775808, -1].each -> (bad)
      f = lex_flat(10, lex_rows(5, 3, 3))
      f["flat_lits"][0] = bad
      expect(wassat_ramsey_lex_lift(f)).to eq(nil)
    f = lex_flat(10, lex_rows(5, 3, 3))
    f["flat_lits"][0] = f["flat_lits"][1]
    expect(wassat_ramsey_lex_lift(f)).to eq(nil)
    f = lex_flat(10, lex_rows(5, 3, 3))
    f["flat_lens"][0] = 4
    expect(wassat_ramsey_lex_lift(f)).to eq(nil)
    f = lex_flat(9, lex_rows(5, 3, 3))
    expect(wassat_ramsey_lex_lift(f)).to eq(nil)

  it "rejects non-cliques even if every clause has a clique-sized width" ->
    f = lex_flat(6, [[1, 2, 3], [1, 2, 4], [1, 3, 5], [2, 3, 6]])
    expect(wassat_ramsey_lex_lift(f)).to eq(nil)

  it "returns no partial reduction after recognition or generation expiry" ->
    f = lex_flat(3, [[1, 2, 3], [-1, -2, -3]])
    expect(wassat_ramsey_lex_lift(f, clock_ms() - 1)).to eq(nil)
    work = i64[16]
    ok = wassat_ramsey_lex_check(f["flat_lits"], f["flat_offs"], f["flat_lens"], 3, 2, 3, work, clock_ms() - 1)
    expect(ok).to eq(0)
    expect(work[1]).to eq(1)
    work = i64[16]
    work[0] = 1
    out = i64[12]
    off = i64[5]
    len = i64[5]
    ok = wassat_ramsey_lex_fill(f["flat_lits"], f["flat_offs"], f["flat_lens"], out, off, len, 3, 2, 3, work, clock_ms() - 1)
    expect(ok).to eq(0)
    expect(work[0]).to eq(0)
    expect(work[1]).to eq(1)
    expect(work[9]).to eq(0)

  it "has precisely the lex-order existential projection for 340 bit-vector pairs" ->
    checks = 0
    m = 1
    while m <= 4
      lits = i64[11 * m]
      offs = i64[3 * m - 2]
      lens = i64[3 * m - 2]
      state = i64[2]
      prefix = 0
      nextvar = 2 * m + 1
      t = 0
      while t < m
        a = t + 1
        b = m + t + 1
        wassat_ramsey_lex_clause(lits, offs, lens, state, prefix, -a, b, 0)
        if t + 1 < m
          wassat_ramsey_lex_clause(lits, offs, lens, state, prefix, -a, -b, nextvar)
          wassat_ramsey_lex_clause(lits, offs, lens, state, prefix, a, b, nextvar)
          prefix = nextvar
          nextvar += 1
        t += 1
      expect(state[0]).to eq(3 * m - 2)
      expect(state[1]).to eq(m == 1 ? 2 : 11 * m - 11)
      code = 0
      while code < (1 << (2 * m))
        want = true
        t = 0
        decided = false
        while t < m && !decided
          a = (code & (1 << t)) != 0
          b = (code & (1 << (m + t))) != 0
          if a != b
            want = b
            decided = true
          t += 1
        found = false
        aux = 0
        while aux < (1 << (m - 1)) && !found
          found = lex_encoding_holds(lits, offs, lens, state[0], code | (aux << (2 * m)))
          aux += 1
        expect(found).to eq(want)
        checks += 1
        code += 1
      m += 1
    expect(checks).to eq(340)

spec_summary
