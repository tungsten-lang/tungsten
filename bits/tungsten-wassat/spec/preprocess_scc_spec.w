use spec
use ../lib/wassat
use ../../tungsten-wrat/lib/wrat

-> scc_preprocess(text, mode = WASSAT_PROOF_NONE)
  f = wassat_parse_cnf(text)
  p = WassatPreprocess.new(f["nvars"], f["clauses"], mode, nil)
  p.intake
  p.run_substitution
  p

describe "Preprocessing SCC scratch reuse and work counters" ->
  it "skips singleton member arrays and resets scratch between rounds" ->
    p = scc_preprocess("p cnf 5 0\n")
    a = p.artifact
    expect(a["stats"]["scc_runs"]).to eq(1)
    expect(a["stats"]["scc_nodes"]).to eq(10)
    expect(a["stats"]["scc_components"]).to eq(10)
    expect(a["stats"]["scc_singletons"]).to eq(10)
    expect(a["stats"]["scc_peak_frames"]).to eq(1)
    expect(a["stats"]["vars_substituted"]).to eq(0)
    p.run_substitution
    b = p.artifact
    expect(b["stats"]["scc_runs"]).to eq(2)
    expect(b["stats"]["scc_nodes"]).to eq(20)
    expect(b["stats"]["scc_components"]).to eq(20)
    expect(b["stats"]["scc_singletons"]).to eq(20)
    expect(b["stats"]["scc_peak_frames"]).to eq(1)
    expect(a["stats"]["scc_runs"]).to eq(1)

  it "retains nontrivial signed components among isolated literals" ->
    p = scc_preprocess("p cnf 5 2\n-1 -2 0\n2 1 0\n")
    a = p.artifact
    expect(a["status"]).to eq(0)
    expect(a["stats"]["vars_substituted"]).to eq(1)
    expect(a["stats"]["scc_nodes"]).to eq(10)
    expect(a["stats"]["scc_components"]).to eq(8)
    expect(a["stats"]["scc_singletons"]).to eq(6)
    expect(a["stats"]["scc_peak_frames"]).to eq(2)

  it "handles a deep implication chain with bounded traversal buffers" ->
    nv = 200
    text = "p cnf [nv] [nv - 1]\n"
    i = 1
    while i < nv
      text = text + "[0 - i] [i + 1] 0\n"
      i += 1
    p = scc_preprocess(text)
    a = p.artifact
    expect(a["status"]).to eq(0)
    expect(a["stats"]["scc_nodes"]).to eq(2 * nv)
    expect(a["stats"]["scc_components"]).to eq(2 * nv)
    expect(a["stats"]["scc_singletons"]).to eq(2 * nv)
    expect(a["stats"]["scc_peak_frames"]).to eq(nv)
    expect(a["stats"]["ticks"]).to eq(2 * (nv - 1))

  it "preserves independently checked contradiction proofs" ->
    text = "p cnf 3 4\n-1 2 0\n-2 -1 0\n1 3 0\n-3 1 0\n"
    r = wassat_solve_preprocessed(text, WASSAT_PROOF_WRAT, 0, 0)
    expect(r["unsat"]).to eq(true)
    expect(wrat_verify(text, wassat_proof_text(r))["verified"]).to eq(true)

spec_summary
