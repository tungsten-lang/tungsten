use spec
use ../lib/matching_parity

-> parity_formula(nv, cs)
  count = 0
  cs.each -> (c) count += c.size
  lits = i64[count]; offs = i64[cs.size]; lens = i64[cs.size]
  p = 0; ci = 0
  cs.each -> (c)
    offs[ci] = p; lens[ci] = c.size
    c.each -> (l)
      lits[p] = l; p += 1
    ci += 1
  {"nvars": nv, "flat_ncl": ci, "flat_nlits": count,
   "flat_lits": lits, "flat_offs": offs, "flat_lens": lens}

-> parity_graph(rows)
  cs = []
  rows.each -> (row)
    cs.push(row)
    i = 0
    while i < row.size
      j = i + 1
      while j < row.size
        cs.push([-row[i], -row[j]])
        j += 1
      i += 1
  cs

-> parity_result(nv, cs, width = 2)
  wassat_matching_parity_refute(parity_formula(nv, cs), i64[2], 0, width)

-> parity_wide_rows
  [[1, 2, 3, 4, 5, 6], [1, 2, 3, 7, 8, 9], [4, 5, 6, 7, 8, 9]]

describe "Clause-checked matching parity" ->
  it "checks an odd nonbipartite exact-one component" ->
    r = parity_result(9, parity_graph(parity_wide_rows), 5)
    expect(r[0]).to eq(-1)
    expect(r[7]).to eq(3)
    expect(r[8]).to eq(45)
    expect(r[10]).to eq(0)

  it "declines an even cycle with a matching" ->
    r = parity_result(4, parity_graph([[1, 2], [2, 3], [3, 4], [4, 1]]))
    expect(r[0]).to eq(0)

  it "requires every clause of a minimal odd-cycle certificate" ->
    original = parity_graph([[1, 2], [2, 3], [3, 1]])
    omit = 0
    while omit < original.size
      cs = []; i = 0
      while i < original.size
        cs.push(original[i]) if i != omit
        i += 1
      expect(parity_result(3, cs)[0]).to eq(0)
      omit += 1

  it "derives rows through units and checked binary resolution" ->
    original = parity_graph(parity_wide_rows)
    cs = [[10, 11], [-10, 12], [-11, 12], [-13]]
    original.each -> (c)
      if c[0] > 0
        row = [-12, 13]
        c.each -> (l) row.push(l)
        cs.push(row)
      else
        cs.push(c)
    r = parity_result(13, cs, 5)
    expect(r[0]).to eq(-1)
    expect(r[2]).to eq(1)
    expect(r[7]).to eq(3)

  it "checks exclusions through auxiliary binary implication paths" ->
    cs = []; nv = 9
    parity_graph(parity_wide_rows).each -> (c)
      if c[0] > 0
        cs.push(c)
      else
        nv += 1
        cs.push([c[0], nv]); cs.push([-nv, c[1]])
    expect(parity_result(nv, cs, 5)[0]).to eq(-1)
    # Remove the 1/4 exclusion, which is unique to this row. Parallel edges
    # 1/2 share both endpoints, so removing only one copy is insufficient.
    cs[5] = cs[6]
    expect(parity_result(nv, cs, 5)[0]).to eq(0)

  it "does not assume incidence is closed or ignore excess incidence" ->
    rows = parity_wide_rows
    cs = parity_graph([rows[0], rows[1]])
    expect(parity_result(9, cs, 5)[0]).to eq(0)
    cs = parity_graph(rows)
    cs.push(rows[0])
    expect(parity_result(9, cs, 5)[0]).to eq(0)

  it "does not count a repeated literal as two incident edges" ->
    expect(parity_result(3, [[1, 1], [1, 2], [2, 3], [-1, -2]])[0]).to eq(0)

  it "handles renamed variables and reordered clauses and literals" ->
    original = parity_graph(parity_wide_rows); cs = []
    i = original.size - 1
    while i >= 0
      c = original[i]; row = []; j = c.size - 1
      while j >= 0
        l = c[j]; v = l < 0 ? -l : l
        row.push(l > 0 ? 131 - 7 * v : -(131 - 7 * v))
        j -= 1
      cs.push(row); i -= 1
    expect(parity_result(131, cs, 5)[0]).to eq(-1)

  it "finds a valid component beside unrelated incomplete rows" ->
    cs = [[10, 11, 12, 13, 14]]
    parity_graph(parity_wide_rows).each -> (c) cs.push(c)
    r = parity_result(14, cs, 5)
    expect(r[0]).to eq(-1)
    expect(r[7]).to eq(3)

  it "checks root conflicts and contradictory resolution units" ->
    expect(parity_result(2, [[1], [-1, 2], [-2]])[0]).to eq(-1)
    cs = [[1, 2], [-1, 3], [-2, 3], [-1, -3], [-2, -3]]
    expect(parity_result(3, cs)[0]).to eq(-1)

  it "observes cancellation, deadlines, and a finite work budget" ->
    f = parity_formula(9, parity_graph(parity_wide_rows)); stop = i64[2]
    z = wassat_stop_cancel(stop)
    r = wassat_matching_parity_refute(f, stop)
    expect(r[0]).to eq(0); expect(r[10]).to eq(1); expect(r[4]).to eq(0)
    r = wassat_matching_parity_refute(f, i64[2], clock_ms() - 1)
    expect(r[0]).to eq(0); expect(r[10]).to eq(2)
    m = i64[15]; m[4] = 100000001
    z = wassat_matching_parity_check(f["flat_lits"], f["flat_offs"], f["flat_lens"], 9, f["flat_ncl"], 5, m, i64[2], 0)
    expect(z).to eq(0); expect(m[10]).to eq(3)

  it "leaves original flat clauses unchanged" ->
    cs = parity_graph(parity_wide_rows); f = parity_formula(9, cs)
    r = wassat_matching_parity_refute(f, i64[2])
    expect(r[0]).to eq(-1)
    at = 0; ci = 0
    cs.each -> (c)
      expect(f["flat_offs"][ci]).to eq(at)
      expect(f["flat_lens"][ci]).to eq(c.size)
      c.each -> (l)
        expect(f["flat_lits"][at]).to eq(l); at += 1
      ci += 1

  it "retains original arrays when structural stages replace formula fields" ->
    cs = []
    i = 0
    while i < 8
      cs.push([-100]); i += 1
    parity_graph(parity_wide_rows).each -> (c) cs.push(c)
    while cs.size < 4096
      cs.push([-100, 101])
    f = parity_formula(128, cs)
    source = wassat_matching_parity_source(f)
    expect(source != nil).to eq(true)
    f["nvars"] = 1; f["flat_ncl"] = 1
    f["flat_lits"] = i64[1]; f["flat_lens"] = i64[1]; f["flat_offs"] = i64[1]
    expect(source["nvars"]).to eq(128)
    expect(source["flat_ncl"]).to eq(4096)
    expect(source["flat_lits"][0]).to eq(-100)
    expect(wassat_matching_parity_refute(source, i64[2])[0]).to eq(-1)

spec_summary
