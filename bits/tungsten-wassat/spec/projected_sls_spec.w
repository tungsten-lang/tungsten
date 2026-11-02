use spec
use ../lib/wassat

-> psls_formula(text)
  f = wassat_parse_cnf(text)
  nc = f["clauses"].size
  nl = 0
  f["clauses"].each -> (c)
    nl += c.size
  lits = i64[nl]
  offs = i64[nc]
  lens = i64[nc]
  ci = 0
  pos = 0
  f["clauses"].each -> (c)
    offs[ci] = pos
    lens[ci] = c.size
    c.each -> (lit)
      lits[pos] = lit
      pos += 1
    ci += 1
  f["flat_ncl"] = nc
  f["flat_nlits"] = nl
  f["flat_lits"] = lits
  f["flat_offs"] = offs
  f["flat_lens"] = lens
  f

-> psls_art(f)
  # Retain empty clauses explicitly; the raw-artifact constructor detects
  # those at intake and reports a refutation before a worker could start.
  nc = f["flat_ncl"]
  alive = i64[nc]
  ci = 0
  while ci < nc
    alive[ci] = 1
    ci += 1
  { "fla": f["flat_lits"], "fcs": f["flat_offs"], "fcl": f["flat_lens"],
    "falive": alive, "ftaut": i64[nc], "fncl": nc,
    "stats": { "vars_substituted": 64 }, "stack": [] }

describe "SLS over a projected formula" ->
  it "requires a substantial proved projection and bounded dimensions" ->
    expect(wassat_pre_sls_projected?(1000, 500, 0)).to eq(true)
    expect(wassat_pre_sls_projected?(1000, 249, 0)).to eq(false)
    expect(wassat_pre_sls_projected?(128, 63, 0)).to eq(false)
    expect(wassat_pre_sls_projected?(128, 64, -1)).to eq(false)
    f = { "nvars": 1000, "flat_ncl": 13501, "flat_nlits": 30501 }
    expect(wassat_pre_sls_shape?(f)).to eq(true)
    f["flat_ncl"] = 500001
    expect(wassat_pre_sls_shape?(f)).to eq(false)

  it "omits dead and tautological slots but retains live empty clauses" ->
    offs = i64[4]
    lens = i64[4]
    alive = i64[4]
    taut = i64[4]
    offs[0] = 7
    lens[0] = 2
    alive[0] = 1
    alive[2] = 1
    taut[2] = 1
    alive[3] = 1
    offs[3] = 9
    dst_offs = i64[4]
    dst_lens = i64[4]
    meta = i64[12]
    stop = i64[4]
    n = wassat_pre_sls_view(offs, lens, alive, taut, 4, dst_offs, dst_lens, meta, stop)
    expect(n).to eq(2)
    expect(dst_offs[0]).to eq(7)
    expect(dst_offs[1]).to eq(9)
    expect(dst_lens[0]).to eq(2)
    expect(dst_lens[1]).to eq(0)
    expect(meta[3]).to eq(2)
    expect(wassat_pre_sls_view(offs, lens, i64[1], taut, 4, dst_offs, dst_lens, meta, stop)).to eq(-1)
    wassat_stop_cancel(stop)
    expect(wassat_pre_sls_view(offs, lens, alive, taut, 4, dst_offs, dst_lens, meta, stop)).to eq(-1)

  it "reconstructs positive and negative aliases before original-clause replay" ->
    f = psls_formula("p cnf 6 8\n-1 -4 0\n1 4 0\n2 -5 0\n-2 5 0\n3 6 0\n-3 -6 0\n1 2 3 0\n-1 -2 0\n")
    pre = WassatPreprocess.new(6, [], WASSAT_PROOF_NONE, f)
    pre.force_full_pipeline
    stop = i64[4]
    pre.set_stop_cell(stop)
    art = pre.run_light_flat(f)
    expect(art["stats"]["vars_substituted"] >= 3).to eq(true)
    res = i64[7]
    meta = i64[12]
    wassat_pre_sls_body(f, art, stop, res, meta)
    expect(res[0]).to eq(1)
    expect(meta[6]).to eq(1)
    expect(wassat_stop_status(stop)).to eq(1)
    reduced = []
    v = 1
    while v <= 6
      reduced.push(res[v] == 1 ? v : -v)
      v += 1
    model = wassat_reconstruct_model(art["stack"], reduced, 6)
    expect(wassat_model_satisfies?(f, model)).to eq(true)

  it "does not publish a model that satisfies only the reduced formula" ->
    original = psls_formula("p cnf 1 1\n-1 0\n")
    reduced = psls_formula("p cnf 1 1\n1 0\n")
    art = psls_art(reduced)
    stop = i64[4]
    res = i64[2]
    meta = i64[12]
    wassat_pre_sls_body(original, art, stop, res, meta)
    expect(res[0]).to eq(0)
    expect(meta[5]).to eq(0)
    expect(meta[6]).to eq(0)
    expect(wassat_stop_requested?(stop)).to eq(false)

  it "never converts an empty clause into a refutation or an empty formula" ->
    f = psls_formula("p cnf 1 1\n0\n")
    art = psls_art(f)
    stop = i64[4]
    res = i64[2]
    meta = i64[12]
    wassat_pre_sls_body(f, art, stop, res, meta)
    expect(res[0]).to eq(0)
    expect(meta[2]).to eq(1)
    expect(meta[4]).to eq(0)
    expect(wassat_stop_status(stop)).to eq(0)

  it "cancels before constructing a partial clause view" ->
    f = psls_formula("p cnf 1 1\n1 0\n")
    art = psls_art(f)
    stop = i64[4]
    wassat_stop_cancel(stop)
    res = i64[2]
    meta = i64[12]
    wassat_pre_sls_body(f, art, stop, res, meta)
    expect(res[0]).to eq(0)
    expect(meta[9]).to eq(1)
    expect(meta[4]).to eq(0)
    expect(meta[6]).to eq(0)

spec_summary
