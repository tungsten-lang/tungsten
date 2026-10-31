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

  it "resumes a capped repair with the same arena and cumulative tickets" ->
    # Four pigeons in three holes, independent of the recognized keychart.
    # This needs CDCL work and ultimately refutes the original formula.
    extra = []
    pigeon = 0
    while pigeon < 4
      v = 81 + pigeon * 3
      extra.push([v, v + 1, v + 2])
      other = pigeon + 1
      while other < 4
        hole = 0
        while hole < 3
          extra.push([0 - v - hole, 0 - 81 - other * 3 - hole])
          hole += 1
        other += 1
      pigeon += 1
    f = keychart_test_formula(extra)
    f["nvars"] = 92
    p = wassat_keychart_plan(f)
    stop = i64[4]
    art = wassat_raw_artifact(f, f["nvars"])
    wassat_keychart_prepare(p, art, stop)
    tickets = i64[3]
    p["solver"].set_shared_conflict_budget(tickets, 10000, 2)
    # Distinct depths provide a valid structural candidate, so any conflict
    # comes from the additional original clauses.
    i = 0
    while i < 8
      p["value"][i] = i / 2
      i += 1
    wassat_keychart_rebuild(p["allowed"], p["value"], p["count"], p["other"], p["dist"], p["weight"], p["gain"], p["state"], 4, 2, 2, 4)
    expect(wassat_keychart_set_candidate(p, f).empty?).to eq(true)
    expect(wassat_keychart_repair_until(p, f, stop, 1).empty?).to eq(true)
    expect(p["state"][11]).to eq(1)
    expect(p["state"][17]).to eq(0)
    expect(wassat_keychart_repair_until(p, f, stop, 1000).empty?).to eq(true)
    expect(p["state"][11] > 1).to eq(true)
    expect(p["state"][11] <= 1000).to eq(true)
    expect(p["state"][17]).to eq(1)
    expect(p["state"][11]).to eq(tickets[0])
    expect(tickets[2]).to eq(tickets[0])
    expect(wassat_stop_status(stop)).to eq(0)
