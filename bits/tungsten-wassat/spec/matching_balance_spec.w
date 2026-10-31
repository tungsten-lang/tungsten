use spec
use ../lib/matching_balance

-> balance_formula(nv, cs)
  count = 0
  cs.each -> (c) count += c.size
  lits = i64[count]
  offs = i64[cs.size]
  lens = i64[cs.size]
  p = 0
  ci = 0
  cs.each -> (c)
    offs[ci] = p
    lens[ci] = c.size
    c.each -> (l)
      lits[p] = l
      p += 1
    ci += 1
  { "nvars": nv, "flat_ncl": ci, "flat_lits": lits,
    "flat_offs": offs, "flat_lens": lens }

-> balance_graph(rows)
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

-> balance_result(nv, cs)
  wassat_matching_balance_refute(balance_formula(nv, cs), i64[2])

describe "Exact-one bipartite matching balance" ->
  it "refutes unequal bipartitions with every row and exclusion checked" ->
    cs = balance_graph([[1, 2, 3], [4, 5, 6], [1, 4], [2, 5], [3, 6]])
    r = balance_result(6, cs)
    expect(r[0]).to eq(-1)
    expect(r[1]).to eq(5)
    expect(r[2]).to eq(6)
    expect(r[4]).to eq(2)
    expect(r[5]).to eq(3)
    expect(r[7]).to eq(9)

  it "requires every premise in a minimal certificate" ->
    original = balance_graph([[1, 2], [1], [2]])
    omit = 0
    while omit < original.size
      cs = []
      i = 0
      while i < original.size
        cs.push(original[i]) if i != omit
        i += 1
      expect(balance_result(2, cs)[0]).to eq(0)
      omit += 1

  it "does not replace a missing exclusion with a duplicate" ->
    cs = balance_graph([[1, 2, 3], [4, 5, 6], [1, 4], [2, 5], [3, 6]])
    cs[1] = cs[2]
    expect(balance_result(6, cs)[0]).to eq(0)

  it "declines balanced or nonbipartite components" ->
    cs = balance_graph([[1, 2], [2, 3], [3, 4], [4, 1]])
    expect(balance_result(4, cs)[0]).to eq(0)
    cs = balance_graph([[1, 2], [2, 3], [3, 1]])
    expect(balance_result(3, cs)[0]).to eq(0)

  it "checks components separately when global counts can cancel" ->
    cs = balance_graph([[1, 2], [1], [2], [3, 4], [3], [4]])
    r = balance_result(4, cs)
    expect(r[0]).to eq(-1)
    expect(r[4] + r[5]).to eq(3)

  it "handles permuted identifiers across native mask-word boundaries" ->
    cs = balance_graph([[1, 63, 64], [65, 127, 128], [1, 65], [63, 127], [64, 128]])
    reversed = []
    i = cs.size - 1
    while i >= 0
      row = []
      j = cs[i].size - 1
      while j >= 0
        row.push(cs[i][j])
        j -= 1
      reversed.push(row)
      i -= 1
    expect(balance_result(128, reversed)[0]).to eq(-1)

  it "allows irrelevant unit and mixed clauses outside the UNSAT subset" ->
    cs = balance_graph([[1, 2], [1], [2]])
    cs.push([-4])
    cs.push([-3, 4])
    cs.push([-4, 3])
    expect(balance_result(4, cs)[0]).to eq(-1)

  it "rejects repeated variables and incomplete or excessive incidence" ->
    expect(balance_result(3, [[1, 1], [1, 2], [2, 3]])[0]).to eq(0)
    expect(balance_result(3, [[1, 2], [1], [-1, -2]])[0]).to eq(0)
    expect(balance_result(3, [[1], [1], [1]])[0]).to eq(0)

  it "observes resource bounds, cancellation, and deadlines" ->
    f = balance_formula(2, balance_graph([[1, 2], [1], [2]]))
    stop = i64[2]
    z = wassat_stop_cancel(stop)
    r = wassat_matching_balance_refute(f, stop)
    expect(r[8]).to eq(1)
    expect(r[6]).to eq(0)
    r = wassat_matching_balance_refute(f, i64[2], clock_ms() - 1)
    expect(r[8]).to eq(2)
    f["nvars"] = 4097
    r = wassat_matching_balance_refute(f, i64[2])
    expect(r[0]).to eq(0)
    expect(r[6]).to eq(0)

spec_summary
