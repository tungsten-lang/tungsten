use spec
use wassat

-> large_proof_fixture
  lines = ["p cnf 3 50001"]
  i = 0
  while i < 50001
    lines.push("1 2 3 0")
    i += 1
  wassat_parse_cnf_native(lines.join("\n") + "\n")

describe "Large lazy proof artifact" ->
  it "keeps clause/proof-id alignment above the lazy threshold in WRAT and DRAT" ->
    f = large_proof_fixture
    [WASSAT_PROOF_WRAT, WASSAT_PROOF_DRAT].each -> (mode)
      pre = WassatPreprocess.new(f["nvars"], [], mode, f)
      pre.intake_flat(f)
      art = pre.artifact
      expect(art["clauses"].size).to eq(50001)
      expect(art["gids"].size).to eq(50001)
      expect(art["clauses"][0]).to eq([1, 2, 3])
      expect(art["clauses"][50000]).to eq([1, 2, 3])
      solver = Wassat.new(f["nvars"], art["clauses"], mode, 0)
      expect(solver.seed_proof_ids(art["gids"], art["next_gid"])).to eq(0)

  it "preserves the trusted-path lazy artifact" ->
    f = large_proof_fixture
    pre = WassatPreprocess.new(f["nvars"], [], WASSAT_PROOF_NONE, f)
    pre.intake_flat(f)
    art = pre.artifact
    expect(art["clauses"].size).to eq(0)
    expect(art["gids"].size).to eq(50001)
