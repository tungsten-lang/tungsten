# spec: compiled -- dispatcher model verification uses native ownership cleanup
use spec
use ../lib/wassat

describe "Specialist registry without a fingerprint" ->
  it "runs a lane that needs no fingerprint when the mask is empty" ->
    lits = i64[2500]; offs = i64[500]; lens = i64[500]
    ci = 0
    while ci < 500
      offs[ci] = ci * 5
      lens[ci] = 5
      j = 0
      while j < 5
        lits[ci * 5 + j] = j + 1
        j += 1
      ci += 1
    formula = {"nvars": 50, "flat_ncl": 500, "flat_nlits": 2500,
      "flat_lits": lits, "flat_offs": offs, "flat_lens": lens}
    expect(wassat_specialist_fingerprint_mask(50, 500, true)).to eq(0)
    result = {"recognized": false, "status": 0, "model": [],
      "conflicts": 0, "decisions": 0, "props": 0}
    res = wassat_specialists_solve(formula, result)
    expect(res["status"]).to eq(1)
    expect(res["lane"]).to eq("vdwb")
    expect(wassat_model_satisfies?(formula, res["model"])).to eq(true)

spec_summary
