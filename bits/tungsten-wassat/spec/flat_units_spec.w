use spec
use ../lib/solver
use ../lib/preprocess

# Duplicate input units still occupy clause slots. A later unit may be the
# only constraint on another variable, or may contradict an earlier unit.
FLAT_DUPLICATE_SAT = "p cnf 2 9\n-1 0\n-1 0\n-1 0\n-1 0\n-1 0\n-1 0\n-1 0\n-1 0\n2 0\n"
FLAT_DUPLICATE_UNSAT = "p cnf 1 7\n1 0\n1 0\n1 0\n1 0\n1 0\n1 0\n-1 0\n"

-> flat_units_formula(text)
  f = wassat_parse_cnf(text)
  clauses = f["clauses"]
  total = 0
  clauses.each -> (clause)
    total += clause.size
  lits = i64[total]
  offs = i64[clauses.size]
  lens = i64[clauses.size]
  offset = 0
  index = 0
  clauses.each -> (clause)
    offs[index] = offset
    lens[index] = clause.size
    clause.each -> (lit)
      lits[offset] = lit
      offset += 1
    index += 1
  f["flat_lits"] = lits
  f["flat_offs"] = offs
  f["flat_lens"] = lens
  f["flat_ncl"] = clauses.size
  f["flat_nlits"] = total
  f

-> flat_units_artifact(text)
  f = flat_units_formula(text)
  wassat_raw_artifact(f, f["nvars"])

describe "Wassat duplicate input units" ->
  it "keeps a late variable assignment in ordinary flat loading" ->
    s = Wassat.from_flat(2, flat_units_artifact(FLAT_DUPLICATE_SAT), 0)
    expect(s.value(2)).to eq(1)
    r = s.solve_budget(0)
    expect(r["status"]).to eq(1)
    expect(wassat_model_satisfies?(wassat_parse_cnf(FLAT_DUPLICATE_SAT), r["model"])).to eq(true)

  it "keeps a late variable assignment in lean lucky loading" ->
    s = Wassat.from_flat_lucky(2, flat_units_artifact(FLAT_DUPLICATE_SAT))
    expect(s.lucky_probe).to eq(1)
    expect(s.value(-1)).to eq(1)
    expect(s.value(2)).to eq(1)

  it "detects a contradiction after repeated copies of one unit" ->
    s = Wassat.from_flat(1, flat_units_artifact(FLAT_DUPLICATE_UNSAT), 0)
    r = s.solve_budget(0)
    expect(r["status"]).to eq(-1)
    lucky = Wassat.from_flat_lucky(1, flat_units_artifact(FLAT_DUPLICATE_UNSAT))
    expect(lucky.lucky_probe == 1).to eq(false)

  it "retains every unit index through compact metadata loading" ->
    f = flat_units_formula(FLAT_DUPLICATE_UNSAT)
    ncl = f["flat_ncl"]
    units = i64[ncl]
    meta = i64[2 * (ncl + 2)]
    alive = i8[ncl + 2]
    pm = i64[12]
    pm[0] = ncl
    pm[1] = 64
    pm[2] = ncl + 2
    wassat_load_flat_meta(f["flat_offs"], f["flat_lens"], meta, alive, units, pm)
    expect(pm[5]).to eq(ncl)
    expect(units[ncl - 1]).to eq(ncl - 1)

  it "loads formulas with no unit clauses" ->
    s = Wassat.from_flat(2, flat_units_artifact("p cnf 2 1\n1 2 0\n"), 0)
    r = s.solve_budget(0)
    expect(r["status"]).to eq(1)
    expect(wassat_model_satisfies?(wassat_parse_cnf("p cnf 2 1\n1 2 0\n"), r["model"])).to eq(true)

  it "rejects an undersized unit buffer in both native loaders" ->
    f = flat_units_formula("p cnf 1 1\n1 0\n")
    units = i64[0]
    meta = i64[6]
    alive = i8[3]
    pm = i64[12]
    pm[0] = 1
    pm[1] = 16
    pm[2] = 3
    pm[9] = 1
    rejected = false
    begin
      wassat_load_flat_meta(f["flat_offs"], f["flat_lens"], meta, alive, units, pm)
    rescue e
      rejected = true
    expect(rejected).to eq(true)
    arena = i64[16]
    lbd = i64[3]
    gids = i64[3]
    unused = i64[1]
    rejected = false
    begin
      wassat_load_flat(f["flat_lits"], f["flat_offs"], f["flat_lens"], unused, unused, unused, arena, meta, alive, lbd, gids, units, pm)
    rescue e
      rejected = true
    expect(rejected).to eq(true)

spec_summary
