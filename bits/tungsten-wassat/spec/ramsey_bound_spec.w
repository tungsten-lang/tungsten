use spec
use ../lib/ramsey_bound

-> bound_rows(n, positive, negative)
  rows = []
  color = 0
  while color < 2
    k = color == 0 ? positive : negative
    if k >= 2 && k <= n
      vertices = i64[k]
      i = 0
      while i < k
        vertices[i] = i
        i += 1
      more = true
      while more
        row = []
        i = 0
        while i < k
          j = i + 1
          while j < k
            a = vertices[i]
            b = vertices[j]
            edge = a * (2 * n - a - 1) / 2 + b - a
            row.push(color == 0 ? edge : 0 - edge)
            j += 1
          i += 1
        rows.push(row)
        i = k - 1
        while i >= 0 && vertices[i] == n - k + i
          i -= 1
        if i < 0
          more = false
        else
          vertices[i] += 1
          j = i + 1
          while j < k
            vertices[j] = vertices[j - 1] + 1
            j += 1
    color += 1
  rows

-> bound_flat(n, rows)
  count = 0
  i = 0
  while i < rows.size
    count += rows[i].size
    i += 1
  lits = i64[count]
  offs = i64[rows.size]
  lens = i64[rows.size]
  pos = 0
  i = 0
  while i < rows.size
    offs[i] = pos
    lens[i] = rows[i].size
    j = 0
    while j < rows[i].size
      lits[pos] = rows[i][j]
      pos += 1
      j += 1
    i += 1
  { "nvars": n * (n - 1) / 2, "nclauses": rows.size, "clauses": [], "boxed": false,
    "flat_lits": lits, "flat_offs": offs, "flat_lens": lens,
    "flat_ncl": rows.size, "flat_nlits": count }

-> bound_status(formula)
  result = wassat_ramsey_bound_solve(formula)
  result == nil ? 0 : result["status"]

describe "Original-clique recursive Ramsey refutation" ->
  it "derives the parity refinement from the two-vertex base cases" ->
    upper = i64[81]
    work = i64[10]
    wassat_ramsey_bound_fill(upper, work)
    expect(upper[3 * 9 + 3]).to eq(6)
    expect(upper[3 * 9 + 4]).to eq(9)
    expect(upper[4 * 9 + 4]).to eq(18)
    expect(work[7]).to eq(36)
    expect(work[9] > 0).to eq(true)
    p = 2
    while p <= 8
      expect(upper[2 * 9 + p]).to eq(p)
      q = 2
      while q <= 8
        expect(upper[p * 9 + q]).to eq(upper[q * 9 + p])
        q += 1
      p += 1

  it "declines graphs below the derived bound without inventing a verdict" ->
    expect(bound_status(bound_flat(5, bound_rows(5, 3, 3)))).to eq(0)
    expect(bound_status(bound_flat(8, bound_rows(8, 3, 4)))).to eq(0)
    expect(bound_status(bound_flat(17, bound_rows(17, 4, 4)))).to eq(0)

  it "refutes only after complete original coverage at the derived thresholds" ->
    cases = [[6, 3, 3], [9, 3, 4], [9, 4, 3], [18, 4, 4]]
    i = 0
    while i < cases.size
      n = cases[i][0]
      f = bound_flat(n, bound_rows(n, cases[i][1], cases[i][2]))
      result = wassat_ramsey_bound_solve(f)
      expect(result["status"]).to eq(-1)
      expect(result["work"][6]).to eq(n)
      expect(result["check"][0]).to eq(1)
      expect(result["check"][6]).to eq(f["flat_ncl"])
      i += 1

  it "rejects a missing clique hidden by a duplicate" ->
    rows = bound_rows(6, 3, 3)
    rows[0] = rows[1]
    expect(bound_status(bound_flat(6, rows))).to eq(0)
    f = bound_flat(6, bound_rows(6, 3, 3))
    f["flat_ncl"] -= 1
    expect(bound_status(f)).to eq(0)

  it "rejects unsupported clauses and malformed candidates before publishing" ->
    rows = bound_rows(6, 3, 3)
    rows.push([1])
    expect(bound_status(bound_flat(6, rows))).to eq(0)
    f = bound_flat(6, bound_rows(6, 3, 3))
    f["flat_lits"][0] = 0 - f["flat_lits"][0]
    expect(bound_status(f)).to eq(0)
    f = bound_flat(6, bound_rows(6, 3, 3))
    f["flat_lits"][0] = f["flat_lits"][1]
    expect(bound_status(f)).to eq(0)
    f = bound_flat(6, bound_rows(6, 3, 3))
    f["flat_offs"][0] = f["flat_lits"].size
    expect(bound_status(f)).to eq(0)

  it "declines unsupported variable layouts and one-color families" ->
    f = bound_flat(6, bound_rows(6, 3, 3))
    f["nvars"] -= 1
    expect(wassat_ramsey_bound_solve(f)).to eq(nil)
    expect(bound_status(bound_flat(6, bound_rows(6, 3, 0)))).to eq(0)
    expect(bound_status(bound_flat(6, bound_rows(6, 0, 3)))).to eq(0)

  it "accepts clause reordering and harmless repetitions without mutating input" ->
    original = bound_rows(6, 3, 3)
    rows = []
    i = original.size - 1
    while i >= 0
      rows.push(original[i])
      i -= 1
    rows.push(rows[0])
    f = bound_flat(6, rows)
    before = f["flat_lits"].to_s
    result = wassat_ramsey_bound_solve(f)
    expect(result["status"]).to eq(-1)
    expect(result["check"][7]).to eq(1)
    expect(f["flat_lits"].to_s).to eq(before)

  it "returns unknown without a partial refutation after expiration" ->
    f = bound_flat(6, bound_rows(6, 3, 3))
    result = wassat_ramsey_bound_solve(f, clock_ms() - 1)
    expect(result["status"]).to eq(0)
    expect(result["work"][1]).to eq(1)
    expect(result["work"][3]).to eq(0)
    expect(result["check"]).to eq(nil)

spec_summary
