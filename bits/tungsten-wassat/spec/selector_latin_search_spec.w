use spec
use ../lib/selector_latin_symmetry

-> wassat_qg_fixture(clauses = [], dnfs = [], cache = 3, cancellation = false, deadline = 0, cap = 0)
  state = i64[2176 * 8]
  tables = i64[140]
  tuples = i64[196]
  supports = i64[14 * 7 * 7 * 66]
  offs = i64[1024]
  lens = i64[1024]
  lits = i64[4096]
  leaves = i64[768]
  groups = i64[12]
  m = i64[64]
  stop = i64[4]
  m[11] = cache
  m[9] = deadline
  m[10] = cap
  wassat_stop_cancel(stop) if cancellation
  c = 0
  while c < 49
    v = (c / 7 + c % 7) % 7
    state[c] = (1 << v) | (1 << ((v + 1) % 7))
    c += 1
  ci = 0
  while ci < 14
    tables[ci * 10 + 7] = 2
    tables[ci * 10 + 8] = 1
    tables[ci * 10 + 9] = ci * 14
    state[49 + ci * 66] = 3
    state[2140 + ci] = 1
    state[1216 + ci * 66] = 0
    p = 0
    while p < 7
      cell = ci < 7 ? ci * 7 + p : p * 7 + ci - 7
      tables[ci * 10 + p] = cell
      v = (cell / 7 + cell % 7) % 7
      k = 0
      while k < 2
        value = (v + k) % 7
        tuples[ci * 14 + k * 7 + p] = value
        supports[((ci * 7 + p) * 7 + value) * 66] |= 1 << k
        k += 1
      p += 1
    ci += 1
  nc = 0
  nl = 0
  clauses.each -> (clause)
    offs[nc] = nl
    lens[nc] = clause.size
    clause.each -> (l)
      lits[nl] = l
      nl += 1
    state[1071 + nc / 64] |= (1 ## i64) << (nc % 64)
    nc += 1
  m[13] = nc
  ng = 0
  leaf = 0
  dnfs.each -> (dnf)
    groups[2 * ng] = leaf
    groups[2 * ng + 1] = dnf.size
    li = 0
    dnf.each -> (term)
      leaves[2 * leaf] = nc
      leaves[2 * leaf + 1] = term.size
      term.each -> (clause)
        offs[nc] = nl
        lens[nc] = clause.size
        clause.each -> (l)
          lits[nl] = l
          nl += 1
        nc += 1
      state[1199 + ng] |= (1 ## i64) << li
      leaf += 1
      li += 1
    ng += 1
  m[14] = ng
  result = wassat_qg_dfs(0, state, tables, tuples, supports, offs, lens, lits, leaves, groups, i64[98], m, stop)
  [result, m, state]

describe "Selector Latin finite-domain search" ->
  it "finds a consistent Latin assignment with every cache mode" ->
    mode = 0
    while mode < 4
      r = wassat_qg_fixture([], [], mode)
      expect(r[0]).to eq(1)
      expect(r[1][0]).to eq(2)
      mode += 1

  it "refutes contradictory clauses" ->
    r = wassat_qg_fixture([[1], [2]])
    expect(r[0]).to eq(-1)
    expect(r[1][5]).to eq(1)

  it "propagates incompatible column tuples" ->
    r = wassat_qg_fixture([[1], [52]])
    expect(r[0]).to eq(-1)
    expect(r[1][4] > 0).to eq(true)

  it "restores satisfied-clause caches when trying a sibling" ->
    r = wassat_qg_fixture([[-1, -59]])
    expect(r[0]).to eq(1)
    expect(r[1][0]).to eq(3)

  it "restores impossible selector leaves when trying a sibling" ->
    r = wassat_qg_fixture([], [[[[-1, -59]]]])
    expect(r[0]).to eq(1)
    expect(r[1][0]).to eq(3)

  it "combines necessary restrictions from selector alternatives" ->
    r = wassat_qg_fixture([], [[[[1]], [[2]]], [[[3]]]])
    expect(r[0]).to eq(-1)
    expect(r[1][6]).to eq(1)

  it "clears high clause-cache bits without changing the assignment" ->
    clauses = []
    i = 0
    while i < 65
      clauses.push([1])
      i += 1
    r = wassat_qg_fixture(clauses)
    expect(r[0]).to eq(1)
    expect(r[1][0]).to eq(1)

  it "clears all 64 impossible selector-leaf bits" ->
    terms = []
    i = 0
    while i < 64
      terms.push([[3]])
      i += 1
    r = wassat_qg_fixture([], [terms])
    expect(r[0]).to eq(-1)
    expect(r[1][6]).to eq(1)

  it "declines a pre-cancelled search before propagation" ->
    r = wassat_qg_fixture([], [], 3, true)
    expect(r[0]).to eq(0)
    expect(r[1][8]).to eq(1)
    expect(r[1][1]).to eq(0)

  it "honors expired deadlines and node budgets" ->
    r = wassat_qg_fixture([], [], 3, false, 1)
    expect(r[0]).to eq(0)
    expect(r[1][8]).to eq(2)
    r = wassat_qg_fixture([], [], 3, false, 0, 1)
    expect(r[0]).to eq(0)
    expect(r[1][8]).to eq(3)
