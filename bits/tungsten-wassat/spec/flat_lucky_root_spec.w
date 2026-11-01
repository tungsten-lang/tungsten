use spec
use ../lib/solver

-> lucky_root_fixture(text, state_size = 8)
  f = wassat_parse_cnf(text)
  cs = f["clauses"]
  count = 0
  cs.each -> (clause) count += clause.size
  lits = i64[count]; offs = i64[cs.size]; lens = i64[cs.size]
  ci = 0; pos = 0
  cs.each -> (clause)
    offs[ci] = pos; lens[ci] = clause.size
    clause.each -> (lit)
      lits[pos] = lit
      pos += 1
    ci += 1
  nv = f["nvars"]
  head = i32[2 * nv + 4]; links = i32[2 * cs.size]
  sign = i8[nv + 1]; trail = i32[nv + 2]; st = i64[state_size]
  rc = wassat_flat_lucky_init(lits, offs, lens, head, links, sign, trail, st, cs.size, nv)
  [lits, offs, lens, head, links, sign, trail, st, nv, rc]

-> lucky_root_dive_check(a, polarity, backward)
  rc = wassat_flat_lucky_dive(a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8], polarity, backward)
  pm = i64[2]; pm[1] = a[1].size
  wassat_verify_flat_i8(a[0], a[1], a[2], a[5], pm)
  [rc, pm[0]]

describe "Flat lucky watches satisfied by permanent roots" ->
  it "skips a satisfied clause without losing propagation from the following clause" ->
    a = lucky_root_fixture("p cnf 3 3\n1 0\n1 2 0\n-1 3 0\n")
    expect(a[9]).to eq(0)
    expect(a[5][1]).to eq(1)
    expect(a[5][3]).to eq(1)
    expect(a[7][2]).to eq(2)
    expect(a[3][2] < 0).to eq(true)
    expect(a[3][4]).to eq(-1)
    expect(lucky_root_dive_check(a, -1, 0)).to eq([1, 1])
    expect(lucky_root_dive_check(a, 1, 1)).to eq([1, 1])
    expect(a[5][1]).to eq(1)
    expect(a[5][3]).to eq(1)
  it "handles negative root units and retains false-root implications" ->
    a = lucky_root_fixture("p cnf 3 3\n-1 0\n-1 2 0\n1 -3 0\n")
    expect(a[9]).to eq(0)
    expect(a[5][1]).to eq(-1)
    expect(a[5][3]).to eq(-1)
    expect(a[3][3] < 0).to eq(true)
    expect(lucky_root_dive_check(a, 1, 0)).to eq([1, 1])
    expect(lucky_root_dive_check(a, -1, 1)).to eq([1, 1])
    expect(a[5][1]).to eq(-1)
  it "handles a satisfying unit arriving after clause attachment" ->
    a = lucky_root_fixture("p cnf 3 3\n1 2 0\n1 0\n-1 3 0\n")
    expect(a[9]).to eq(0)
    expect(a[3][4] >= 0).to eq(true)
    expect(a[5][3]).to eq(1)
    expect(lucky_root_dive_check(a, -1, 0)).to eq([1, 1])
  it "preserves duplicate watches and later root implications" ->
    a = lucky_root_fixture("p cnf 3 4\n1 0\n1 2 0\n2 2 0\n-2 3 0\n")
    expect(a[9]).to eq(0)
    expect(a[7][3]).to eq(1)
    expect(lucky_root_dive_check(a, -1, 0)).to eq([1, 1])
    expect(a[5][2]).to eq(1)
    expect(a[5][3]).to eq(1)
    expect(lucky_root_dive_check(a, 1, 1)).to eq([1, 1])
  it "still detects a contradictory later root unit" ->
    a = lucky_root_fixture("p cnf 2 3\n1 0\n1 2 0\n-1 0\n")
    expect(a[9]).to eq(-1)

describe "Flat lucky replacement lookahead" ->
  it "moves a later replacement before a long false prefix" ->
    a = lucky_root_fixture("p cnf 11 10\n-1 -2 -3 -4 -5 -6 -7 -8 9 -10 11 0\n1 0\n2 0\n3 0\n4 0\n5 0\n6 0\n7 0\n8 0\n10 0\n")
    expect(a[9]).to eq(0)
    expect(a[5][9]).to eq(0)
    expect(a[5][11]).to eq(0)
    expect(a[7][4]).to eq(1)
    expect(a[7][5]).to eq(2)
    expect(a[7][6]).to eq(0)
    expect(a[7][7]).to eq(6)
    expect(lucky_root_dive_check(a, -1, 0)).to eq([1, 1])
    expect(a[5][11]).to eq(1)
    expect(lucky_root_dive_check(a, 1, 1)).to eq([1, 1])
  it "propagates the sole remaining replacement and its consequences" ->
    a = lucky_root_fixture("p cnf 11 11\n-1 -2 -3 -4 -5 -6 -7 -8 9 -10 0\n-9 11 0\n1 0\n2 0\n3 0\n4 0\n5 0\n6 0\n7 0\n8 0\n10 0\n")
    expect(a[9]).to eq(0)
    expect(a[5][9]).to eq(1)
    expect(a[5][11]).to eq(1)
    expect(a[7][2]).to eq(11)
    expect(a[7][4]).to eq(1)
    expect(a[7][5]).to eq(1)
    expect(a[7][6]).to eq(1)
    expect(lucky_root_dive_check(a, -1, 0)).to eq([1, 1])
  it "preserves repeated unassigned literals across opposite dives" ->
    a = lucky_root_fixture("p cnf 9 9\n-1 -2 -3 -4 -5 -6 -7 -8 9 9 0\n1 0\n2 0\n3 0\n4 0\n5 0\n6 0\n7 0\n8 0\n")
    expect(a[9]).to eq(0)
    expect(a[7][4]).to eq(1)
    expect(lucky_root_dive_check(a, -1, 0)).to eq([1, 1])
    expect(a[5][9]).to eq(1)
    expect(lucky_root_dive_check(a, 1, 1)).to eq([1, 1])
  it "keeps four-slot library state valid without optional counters" ->
    a = lucky_root_fixture("p cnf 10 10\n-1 -2 -3 -4 -5 -6 -7 -8 9 -10 0\n1 0\n2 0\n3 0\n4 0\n5 0\n6 0\n7 0\n8 0\n10 0\n", 4)
    expect(a[9]).to eq(0)
    expect(a[5][9]).to eq(1)
    expect(lucky_root_dive_check(a, -1, 0)).to eq([1, 1])
    expect(lucky_root_dive_check(a, 1, 1)).to eq([1, 1])

spec_summary
