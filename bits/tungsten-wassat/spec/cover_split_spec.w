# spec: compiled -- starts solver worker threads
use spec
use ../lib/wassat

-> split_formula(rows, conflicts, nvars)
  lines = []
  rows.each -> (row)
    lines.push(row.join(" ") + " 0")
  conflicts.each -> (edge)
    lines.push("-[edge[0]] -[edge[1]] 0")
  wassat_parse_cnf_native(
    "p cnf [nvars] [lines.size]\n" + lines.join("\n") + "\n"
  )

-> split_complete_edges(n)
  edges = []
  a = 1
  while a <= n
    b = a + 1
    while b <= n
      edges.push([a, b])
      b += 1
    a += 1
  edges

# Deterministic generator: `seed` picks rows of width 3..5 over nvars
# variables and a conflict graph of the requested density (percent).
-> split_random_formula(seed, nvars, nrows, density)
  state = seed * 2654435761 + 12345
  rows = []
  r = 0
  while r < nrows
    width = 3 + (state >> 8) % 3
    state = (state * 1103515245 + 12345) % 2147483648
    row = []
    while row.size < width
      v = 1 + (state >> 8) % nvars
      state = (state * 1103515245 + 12345) % 2147483648
      dup = false
      row.each -> (u)
        dup = true if u == v
      row.push(v) unless dup
    rows.push(row)
    r += 1
  conflicts = []
  a = 1
  while a <= nvars
    b = a + 1
    while b <= nvars
      conflicts.push([a, b]) if (state >> 8) % 100 < density
      state = (state * 1103515245 + 12345) % 2147483648
      b += 1
    a += 1
  conflicts.push([1, 2]) if conflicts.empty?
  split_formula(rows, conflicts, nvars)

# `count` rows of width four stepping around a ring of nvars variables.
-> split_ring_rows(nvars, count)
  rows = []
  r = 0
  while r < count
    rows.push([r % nvars + 1, (r + 7) % nvars + 1, (r + 31) % nvars + 1, (r + 101) % nvars + 1])
    r += 1
  rows

# Every variable conflicts with its next `span` ring neighbours.
-> split_ring_edges(nvars, span)
  edges = []
  a = 0
  while a < nvars
    d = 1
    while d <= span
      edges.push([a + 1, (a + d) % nvars + 1])
      d += 1
    a += 1
  edges

# Number of cases whose units agree with a total assignment (bit v-1 of mask).
-> split_cases_matching(list, mask)
  lits = list["lits"]
  ends = list["ends"]
  matching = 0
  from = 0
  i = 0
  while i < ends.size
    ok = true
    p = from
    while p < ends[i]
      lit = lits[p]
      v = lit > 0 ? lit : 0 - lit
      bit = (mask >> (v - 1)) & 1
      ok = false if (lit > 0 && bit == 0) || (lit < 0 && bit == 1)
      p += 1
    matching += 1 if ok
    from = ends[i]
    i += 1
  matching

-> split_rows_hold?(rows, mask)
  ok = true
  rows.each -> (row)
    hit = false
    row.each -> (v)
      hit = true if ((mask >> (v - 1)) & 1) == 1
    ok = false unless hit
  ok

describe "Wassat covering case split" ->
  it "admits only the strict covering shape" ->
    counts = i64[4]
    f = split_formula([[1, 2, 3], [2, 3, 4]], [[1, 2], [2, 3]], 4)
    expect(wassat_cover_split_census(f["flat_lits"], f["flat_offs"], f["flat_lens"], f["flat_ncl"], 4, counts)).to eq(1)
    expect(counts[0]).to eq(2)
    expect(counts[1]).to eq(2)
    expect(counts[2]).to eq(6)
    mixed = wassat_parse_cnf_native("p cnf 4 3\n1 2 3 0\n-1 2 0\n-3 -4 0\n")
    expect(wassat_cover_split_census(mixed["flat_lits"], mixed["flat_offs"], mixed["flat_lens"], 3, 4, i64[4])).to eq(0)
    negative = wassat_parse_cnf_native("p cnf 4 3\n1 2 3 0\n-1 -2 -3 0\n-3 -4 0\n")
    expect(wassat_cover_split_census(negative["flat_lits"], negative["flat_offs"], negative["flat_lens"], 3, 4, i64[4])).to eq(0)
    unit = wassat_parse_cnf_native("p cnf 4 3\n1 2 3 0\n4 0\n-3 -4 0\n")
    expect(wassat_cover_split_census(unit["flat_lits"], unit["flat_offs"], unit["flat_lens"], 3, 4, i64[4])).to eq(0)

  it "admits dense covering formulas and declines one-row-per-variable encodings" ->
    # 360 variables, 21 conflicts per variable, and either eight or two row
    # occurrences per variable.
    dense_rows = split_ring_rows(360, 720)
    sparse_rows = split_ring_rows(360, 180)
    edges = split_ring_edges(360, 21)
    dense = split_formula(dense_rows, edges, 360)
    plan = wassat_cover_split_admit(dense, false, 4)
    expect(plan["rows"]).to eq(720)
    expect(plan["edges"]).to eq(7560)
    expect(plan["lits"]).to eq(2880 + 15120)
    expect(wassat_cover_split_admit(split_formula(sparse_rows, edges, 360), false, 4)).to eq(nil)
    expect(wassat_cover_split_admit(split_formula(dense_rows, split_ring_edges(360, 19), 360), false, 4)).to eq(nil)
    expect(wassat_cover_split_admit(dense, false, 1)).to eq(nil)

  it "declines small and sparse formulas unless forced" ->
    f = split_formula([[1, 2, 3], [2, 3, 4]], [[1, 2], [2, 3]], 4)
    expect(wassat_cover_split_admit(f, false, 4)).to eq(nil)
    plan = wassat_cover_split_admit(f, true, 4)
    expect(plan["rows"]).to eq(2)
    expect(plan["edges"]).to eq(2)
    expect(plan["lits"]).to eq(10)
    expect(wassat_cover_split_admit(f, true, 1)).to eq(nil)
    mixed = wassat_parse_cnf_native("p cnf 4 3\n1 2 3 0\n-1 2 0\n-3 -4 0\n")
    expect(wassat_cover_split_admit(mixed, true, 4)).to eq(nil)

  it "builds a case list that partitions every assignment covering the rows" ->
    rows = [[1, 2, 3, 4], [3, 4, 5], [5, 6, 7, 8], [1, 6, 8], [2, 5, 7], [4, 7, 8, 9], [1, 9, 3]]
    f = split_formula(rows, [[1, 2], [3, 5], [6, 7]], 9)
    caps = [2, 3, 5, 8, 64]
    caps.each -> (cap)
      list = wassat_cover_split_cases(f, cap)
      expect(list["ends"].size <= cap).to eq(true)
      expect(list["ends"].size >= 2).to eq(true)
      mask = 0
      while mask < 512
        if split_rows_hold?(rows, mask)
          expect(split_cases_matching(list, mask)).to eq(1)
        else
          expect(split_cases_matching(list, mask) <= 1).to eq(true)
        mask += 1

  it "drops a repeated row literal instead of emitting a contradictory case" ->
    rows = [[1, 2, 1, 3], [2, 3, 4]]
    f = split_formula(rows, [[1, 4]], 4)
    list = wassat_cover_split_cases(f, 64)
    mask = 0
    while mask < 16
      expect(split_cases_matching(list, mask)).to eq(1) if split_rows_hold?(rows, mask)
      mask += 1

  it "adds a case's units to an otherwise identical formula" ->
    f = split_formula([[1, 2, 3], [2, 3, 4]], [[1, 2], [2, 3]], 4)
    lits = [3, -1, -2]
    g = wassat_cover_split_formula(f, 10, lits, 0, 3)
    expect(g["flat_ncl"]).to eq(7)
    expect(g["flat_nlits"]).to eq(13)
    expect(g["flat_lens"][4]).to eq(1)
    expect(g["flat_lits"][g["flat_offs"][4]]).to eq(3)
    expect(g["flat_lits"][g["flat_offs"][6]]).to eq(-2)
    expect(g["flat_lens"][0]).to eq(3)
    expect(g["flat_lits"][g["flat_offs"][1] + 2]).to eq(4)

  it "finds a model and replays it against the input" ->
    f = split_formula([[1, 2, 3], [2, 3, 4], [1, 4, 5]], [[1, 2], [2, 3], [4, 5]], 5)
    result = wassat_cover_split_run(f, true, 64, 3, 0)
    expect(result["admitted"]).to eq(true)
    expect(result["status"]).to eq(1)
    expect(wassat_model_satisfies?(f, result["model"])).to eq(true)

  it "refutes only when every case is refuted" ->
    f = split_formula(
      [[1, 2, 3], [1, 2, 4], [1, 3, 4], [2, 3, 4]],
      split_complete_edges(4), 4
    )
    result = wassat_cover_split_run(f, true, 64, 3, 0)
    expect(result["status"]).to eq(-1)
    expect(result["refuted"]).to eq(result["cases"])
    expect(result["retired"]).to eq(0)

  it "agrees with the exact row search on generated formulas" ->
    sat = 0
    unsat = 0
    seed = 1
    while seed <= 40
      nvars = 10 + seed % 9
      f = split_random_formula(seed, nvars, 2 * nvars + seed % 7, 20 + 15 * (seed % 4))
      exact = wassat_covering_solve(f)
      expect(exact["status"] != 0).to eq(true)
      limit = seed % 3 == 0 ? 3 : 64
      result = wassat_cover_split_run(f, true, limit, 2 + seed % 3, seed % 2)
      expect(result["status"]).to eq(exact["status"])
      if result["status"] == 1
        expect(wassat_model_satisfies?(f, result["model"])).to eq(true)
        sat += 1
      else
        expect(result["refuted"]).to eq(result["cases"])
        unsat += 1
      seed += 1
    expect(sat > 5).to eq(true)
    expect(unsat > 5).to eq(true)

spec_summary
