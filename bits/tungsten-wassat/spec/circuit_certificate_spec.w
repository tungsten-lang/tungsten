use spec
use ../lib/wassat

-> circuit_certificate_fixture(clauses, free_vars, assigned, first = 3, last = 3)
  nlits = 0
  clauses.each -> (clause)
    nlits += clause.size
  lits = i64[nlits]
  offs = i64[clauses.size]
  lens = i64[clauses.size]
  assign = i64[last + 1]
  free = i64[free_vars.size]
  work = i64[5]
  ci = 0
  at = 0
  clauses.each -> (clause)
    offs[ci] = at
    lens[ci] = clause.size
    clause.each -> (lit)
      lits[at] = lit
      at += 1
    ci += 1
  assigned.each -> (lit)
    v = lit < 0 ? -lit : lit
    assign[v] = lit > 0 ? 1 : -1
  i = 0
  free_vars.each -> (v)
    free[i] = v
    i += 1
  ok = wassat_circuit_prefix_supported?(lits, offs, lens, clauses.size,
    assign, free, free_vars.size, first, last, work)
  [ok, work]

-> circuit_certificate_parity8(drop_last = false)
  clauses = []
  row = 0
  while row < 256
    clause = []
    parity = 0
    bit = 0
    while bit < 8
      value = (row >> bit) & 1
      clause.push(value == 1 ? -(bit + 1) : bit + 1)
      parity = parity ^ value
      bit += 1
    clause.push(parity == 0 ? -9 : 9)
    clauses.push(clause) unless drop_last && row == 255
    row += 1
  circuit_certificate_fixture(clauses, [1, 2, 3, 4, 5, 6, 7, 8], [], 9, 9)

-> circuit_gray_fixture(kind)
  clauses = []
  if kind == 2
    clauses.push([29, -29, 1])
    clauses.push([29, -29, -1])
    v = 30
    while v <= 500
      clauses.push([v, -29])
      clauses.push([-v, 29])
      v += 1
    clauses.push([-500])
  else
    v = 29
    while v < 500
      clauses.push([v, -1])
      clauses.push([-v, 1])
      v += 1
    clauses.push([500, 1, -1])
    clauses.push([-500, 1, -1])
    clauses.push([kind == 0 ? 500 : -500])
  while clauses.size < 1500
    clauses.push(kind == 2 ? [30, -29] : [29, -1])
  total = 0
  clauses.each -> (clause)
    total += clause.size
  lits = i64[total]
  offs = i64[clauses.size]
  lens = i64[clauses.size]
  at = 0
  ci = 0
  clauses.each -> (clause)
    offs[ci] = at
    lens[ci] = clause.size
    clause.each -> (lit)
      lits[at] = lit
      at += 1
    ci += 1
  {"nvars": 500, "flat_ncl": clauses.size, "flat_lits": lits,
   "flat_offs": offs, "flat_lens": lens}

describe "Wassat circuit original-clause support" ->
  it "accepts a complete AND truth relation" ->
    r = circuit_certificate_fixture([[-1, -2, 3], [1, -3], [2, -3]], [1, 2], [])
    expect(r[0]).to eq(true)

  it "accepts a single-valued partial relation without assuming totality" ->
    r = circuit_certificate_fixture([[3, 1], [-3, 1], [-3, -1]], [1], [])
    expect(r[0]).to eq(true)

  it "rejects an underconstrained output despite both clause polarities" ->
    r = circuit_certificate_fixture([[3, 1], [-3, 2]], [1, 2], [])
    expect(r[0]).to eq(false)
    work = r[1]
    expect(work[4]).to eq(5)

  it "does not mistake a forced sink for a verified gate definition" ->
    r = circuit_certificate_fixture([[3], [3, 1], [-3, 2]], [1, 2], [3])
    expect(r[0]).to eq(false)

  it "rejects an input omitted from enumeration and earlier definitions" ->
    r = circuit_certificate_fixture([[-1, -2, 3], [1, -3], [2, -3]], [2], [])
    expect(r[0]).to eq(false)
    work = r[1]
    expect(work[4]).to eq(3)

  it "uses proven fixed inputs without adding them to the free support" ->
    r = circuit_certificate_fixture([[-1, -2, 3], [1, -3], [2, -3]], [2], [1])
    expect(r[0]).to eq(true)

  it "declines repeated output literals" ->
    r = circuit_certificate_fixture([[3, 3, 1], [-3, -1]], [1], [])
    expect(r[0]).to eq(false)
    work = r[1]
    expect(work[4]).to eq(2)

  it "checks a wide AND relation by unit refutation" ->
    clauses = [[10, -1, -2, -3, -4, -5, -6, -7, -8, -9]]
    free_vars = []
    v = 1
    while v <= 9
      clauses.push([-10, v])
      free_vars.push(v)
      v += 1
    r = circuit_certificate_fixture(clauses, free_vars, [], 10, 10)
    expect(r[0]).to eq(true)
    work = r[1]
    expect(work[2]).to eq(0)

  it "declines an ambiguous wide relation when unit refutation fails" ->
    clauses = [[10, -1, -2, -3, -4, -5, -6, -7, -8, -9], [-10, 1]]
    r = circuit_certificate_fixture(clauses, [1, 2, 3, 4, 5, 6, 7, 8, 9], [], 10, 10)
    expect(r[0]).to eq(false)
    work = r[1]
    expect(work[4]).to eq(4)

  it "proves a negative-only constant without enumerating its irrelevant input" ->
    r = circuit_certificate_fixture([[-3, 1], [-3, -1]], [], [])
    expect(r[0]).to eq(true)

  it "ignores irrelevant inputs in clauses already satisfied by fixed literals" ->
    r = circuit_certificate_fixture([[3, 1, 2], [-3, -1]], [], [1])
    expect(r[0]).to eq(true)

  it "checks definitions in variable order regardless of clause order" ->
    clauses = [[3, -4], [-1, -2, 3], [-3, -2, 4], [1, -3], [2, -4], [2, -3]]
    r = circuit_certificate_fixture(clauses, [1, 2], [], 3, 4)
    expect(r[0]).to eq(true)

  it "checks all four batches of an eight-input truth relation" ->
    r = circuit_certificate_parity8
    expect(r[0]).to eq(true)
    work = r[1]
    expect(work[2]).to eq(4)

  it "rejects an ambiguous row that appears only in the final batch" ->
    r = circuit_certificate_parity8(true)
    expect(r[0]).to eq(false)
    work = r[1]
    expect(work[2]).to eq(4)
    expect(work[4]).to eq(5)

describe "Wassat circuit clause range" ->
  it "excludes SatCoin prefix clauses from the allocated gate span" ->
    lits = i64[5]
    lits[0] = 73; lits[1] = -41
    lits[2] = 66; lits[3] = 1; lits[4] = 2
    offs = i64[2]
    offs[1] = 2
    lens = i64[2]
    lens[0] = 2; lens[1] = 3
    clause_off = i64[75]
    clause_off[74] = 1
    cl_lit_off = i64[2]
    cl_lit_len = i64[1]
    # A guard slot makes the old overflow observable without corrupting the test.
    cl_lits = i64[2]
    cl_lits[1] = 12345
    cur_cl = i64[74]
    wassat_satcoin_fill_pos_clauses(lits, offs, lens, 2, 73, 73,
      clause_off, cl_lit_off, cl_lit_len, cl_lits, cur_cl, 1)
    expect(cl_lit_len[0]).to eq(1)
    expect(cl_lit_off[1]).to eq(1)
    expect(cl_lits[0]).to eq(-41)
    expect(cl_lits[1]).to eq(12345)

  it "includes ASCON gates starting at variable 66" ->
    lits = i64[4]
    lits[0] = 66; lits[1] = -1
    lits[2] = 73; lits[3] = -2
    offs = i64[2]
    offs[1] = 2
    lens = i64[2]
    lens[0] = 2; lens[1] = 2
    clause_off = i64[75]
    m = 67
    while m <= 73
      clause_off[m] = 1
      m += 1
    clause_off[74] = 2
    cl_lit_off = i64[3]
    cl_lit_len = i64[2]
    cl_lits = i64[2]
    cur_cl = i64[74]
    wassat_satcoin_fill_pos_clauses(lits, offs, lens, 2, 66, 73,
      clause_off, cl_lit_off, cl_lit_len, cl_lits, cur_cl, 2)
    expect(cl_lit_len[0]).to eq(1)
    expect(cl_lit_len[1]).to eq(1)
    expect(cl_lit_off[2]).to eq(2)
    expect(cl_lits[0]).to eq(-1)
    expect(cl_lits[1]).to eq(-2)

describe "Wassat Gray-code miter relations" ->
  it "keeps a satisfiable positive output that is allowed but not forced" ->
    expect(wassat_miter28_gray_unsat?(circuit_gray_fixture(0))).to eq(false)

  it "keeps a satisfiable negative output that is allowed but not forced" ->
    expect(wassat_miter28_gray_unsat?(circuit_gray_fixture(1))).to eq(false)

  it "declines tautologies containing both output polarities" ->
    expect(wassat_miter28_gray_unsat?(circuit_gray_fixture(2))).to eq(false)

spec_summary
