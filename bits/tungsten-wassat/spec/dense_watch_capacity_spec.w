# spec: compiled -- large flat intake regression; policy boundaries run on both engines
use spec
use ../lib/solver
use ../lib/preprocess

+ DenseWatchCapacityFixture < Wassat
  ro :wp_state, :ccap, :assign

-> dense_watch_formula(width, count)
  lits = i64[width * count + 2]
  offs = i64[count + 2]
  lens = i64[count + 2]
  lits[0] = -1; lits[1] = -2
  offs[0] = 0; offs[1] = 1
  lens[0] = 1; lens[1] = 1
  ci = 0
  while ci < count
    start = width * ci + 2
    offs[ci + 2] = start
    lens[ci + 2] = width
    j = 0
    while j < width
      lits[start + j] = j + 1
      j += 1
    ci += 1
  { "nvars": 3, "nclauses": count + 2, "clauses": [], "boxed": false,
    "flat_lits": lits, "flat_offs": offs, "flat_lens": lens,
    "flat_ncl": count + 2, "flat_nlits": width * count + 2 }

-> dense_watch_load(formula, lean, proof_mode = 0)
  s = DenseWatchCapacityFixture.new(3, [], proof_mode, 0, true)
  s.load_flat(wassat_raw_artifact(formula, 3), lean)
  s

describe "Dense flat watch capacity" ->
  it "reserves relocation space without changing clause capacity or the model" ->
    s = dense_watch_load(dense_watch_formula(3, 131072), false)
    expect(s.ccap).to eq(262146)
    expect(s.wp_state[1]).to eq(4 * s.ccap + 4 * 3 + 72)
    r = s.solve
    expect(r["status"]).to eq(1)
    expect(r["model"]).to eq([-1, -2, 3])

  it "keeps binary implication pools on their existing sizing policy" ->
    s = dense_watch_load(dense_watch_formula(2, 131072), false)
    expect(s.wp_state[1]).to eq(2 * s.ccap + 4 * 3 + 72)
    expect(s.solve["status"]).to eq(-1)

  it "keeps the lean propagation-only loader compact" ->
    s = dense_watch_load(dense_watch_formula(3, 131072), true)
    expect(s.wp_state[1] < 4 * s.ccap).to eq(true)
    expect(s.propagate).to eq(-1)
    expect(s.assign[1]).to eq(-1)
    expect(s.assign[2]).to eq(-1)
    expect(s.assign[3]).to eq(1)

spec_summary
