use spec
use ../lib/wassat

-> view_flat_fixture(text)
  parsed = wassat_parse_cnf(text)
  clauses = parsed["clauses"]
  total = 0
  clauses.each ->(c) total += c.size
  lits = i64[total]
  offs = i64[clauses.size]
  lens = i64[clauses.size]
  ci = 0
  pos = 0
  clauses.each ->(c)
    offs[ci] = pos
    lens[ci] = c.size
    c.each ->(l)
      lits[pos] = l
      pos += 1
    ci += 1
  { "nvars": parsed["nvars"], "clauses": [], "flat_lits": lits,
    "flat_offs": offs, "flat_lens": lens, "flat_ncl": ci,
    "flat_nlits": total }

-> view_result_text(result)
  text = "[result["unsat"]]"
  ["units", "binaries", "control_vars", "detour_phases", "tt_phases"].each ->(key)
    text += " [result[key]]"
  text

describe "Structural pruning clause-view reuse" ->
  it "preserves every ordered deduction for flat and boxed formulas" ->
    text = "p cnf 8 13\n1 2 3 0\n-1 -2 0\n-1 -3 0\n-2 -3 0\n-1 7 0\n-2 7 0\n-3 7 0\n-1 8 0\n-2 8 0\n4 -5 0\n-4 5 6 0\n-6 0\n4 0\n"
    flat = view_flat_fixture(text)
    before = "[flat["flat_lits"]]"
    boxed = wassat_parse_cnf(text)
    a = wassat_structural_prune(8, flat)
    b = wassat_structural_prune(8, boxed)
    expect(view_result_text(a)).to eq(view_result_text(b))
    expect(a["units"].include?(7)).to eq(true)
    expect(a["binaries"].include?([3, 8])).to eq(true)
    expect(flat["clauses"].empty?).to eq(true)
    expect("[flat["flat_lits"]]").to eq(before)
    expect(view_result_text(wassat_structural_prune(8, flat))).to eq(view_result_text(a))

  it "rebuilds the local view after the caller changes flat input" ->
    f = view_flat_fixture("p cnf 2 2\n1 0\n-1 0\n")
    expect(wassat_structural_prune(2, f)["unsat"]).to eq(true)
    f["flat_lits"][1] = 2
    r = wassat_structural_prune(2, f)
    expect(r["unsat"]).to eq(false)
    expect(r["units"].include?(1)).to eq(true)
    expect(r["units"].include?(2)).to eq(true)
    expect(f["clauses"].empty?).to eq(true)

  it "keeps the existing boxed-clause precedence and input ownership" ->
    f = view_flat_fixture("p cnf 2 2\n1 0\n-1 0\n")
    f["clauses"] = [[1], [2]]
    r = wassat_structural_prune(2, f)
    expect(r["unsat"]).to eq(false)
    expect(r["units"].include?(2)).to eq(true)
    expect(f["clauses"]).to eq([[1], [2]])
    expect(f["flat_lits"][1]).to eq(-1)

  it "handles empty inputs and rejects oversized shapes before materialization" ->
    f = view_flat_fixture("p cnf 4 0\n")
    expect(wassat_structural_prune(4, f)["unsat"]).to eq(false)
    expect(wassat_structural_prune(0, { "flat_ncl": 1 })["units"].empty?).to eq(true)
    expect(wassat_structural_prune(4, { "flat_ncl": 1000001 })["binaries"].empty?).to eq(true)

spec_summary
