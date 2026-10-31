# spec: compiled -- thread worker uses native monotonic clocks
use spec
use keychart_fixture

describe "Keychart model worker" ->
  it "infers domains and shared supports without instance metadata" ->
    f = keychart_test_formula([])
    p = wassat_keychart_plan(f)
    expect(p != nil).to eq(true)
    expect(p["meta"].to_s).to eq([4, 2, 2, 32, 48].to_s)
    expect(p["allowed"][0]).to eq(1)
    expect(p["allowed"][2]).to eq(0)
    expect(p["wkey"][49]).to eq(17)
    expect(p["wlock"][49]).to eq(33)
    model = keychart_test_search(f, p, i64[4])
    expect(model.size).to eq(f["nvars"])
    expect(wassat_model_satisfies?(f, model)).to eq(true)

  it "treats additional original constraints as mandatory during repair" ->
    f = keychart_test_formula([[1], [5], [19], [23]])
    p = wassat_keychart_plan(f)
    model = keychart_test_search(f, p, i64[4])
    expect(model.size).to eq(f["nvars"])
    expect(wassat_model_satisfies?(f, model)).to eq(true)
    expect(p["state"][10] > 0).to eq(true)

  it "never publishes a refutation or stops other arms after a repair miss" ->
    f = keychart_test_formula([[1], [-1]])
    p = wassat_keychart_plan(f)
    stop = i64[4]
    model = keychart_test_search(f, p, stop)
    expect(model.empty?).to eq(true)
    expect(wassat_stop_load(stop)).to eq(0)
    expect(wassat_stop_status(stop)).to eq(0)


  it "charges repair queries to their own shared conflict slot" ->
    # An independent two-variable refutation requires actual CDCL work;
    # primary-variable units can settle at the root without a conflict ticket.
    f = keychart_test_formula([[81, 82], [81, -82], [-81, 82], [-81, -82]])
    f["nvars"] = 82
    p = wassat_keychart_plan(f)
    stop = i64[4]
    art = wassat_raw_artifact(f, f["nvars"])
    wassat_keychart_prepare(p, art, stop)
    tickets = i64[3]
    p["solver"].set_shared_conflict_budget(tickets, 1, 2)
    model = wassat_keychart_search(p, f, stop)
    expect(tickets[0]).to eq(1)
    expect(tickets[1]).to eq(0)
    expect(tickets[2]).to eq(tickets[0])
    expect(p["state"][11]).to eq(tickets[0])
    expect(model.empty? || wassat_model_satisfies?(f, model)).to eq(true)
