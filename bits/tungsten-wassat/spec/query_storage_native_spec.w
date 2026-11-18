# spec: compiled -- native disposal, simultaneous private solvers and borrowed cells
use spec
use ../lib/circuit_cone_search
use circuit_cone_php_fixture

describe "Private solver storage lifetime" ->
  it "retires a growing retained owner at its byte reservation and keeps shared tickets alive" ->
    fixture = cone_php_circuit
    decoded = wassat_cone_decode(fixture[0])
    workspace = wassat_cone_workspace(decoded)
    cache = wassat_cone_retry_cache(10)
    workspace["retry_cache"] = cache; workspace["retry_active"] = true
    pool = i64[3]; stop = i64[2]
    workspace["conflict_budget"] = pool; workspace["conflict_limit"] = 7; workspace["conflict_slot"] = 2
    aliases = i64[decoded["nvars"] + 1]
    first = wassat_cone_prove(decoded, aliases, workspace, fixture[1], fixture[2], 1, 0, false, stop)
    expect(first["equivalent"]).to eq(false)
    expect(cache["resident"]).to eq(1)
    cache["max_bytes"] = cache["bytes"]
    second = wassat_cone_prove(decoded, aliases, workspace, fixture[1], fixture[2], 1, 0, false, stop)
    expect(second["equivalent"]).to eq(false)
    expect(cache["hits"]).to eq(1)
    expect(cache["declined"]).to eq(1)
    expect(cache["resident"]).to eq(0)
    expect(cache["bytes"]).to eq(0)
    expect(pool[0]).to eq(2)
    expect(wassat_stop_load(stop)).to eq(0)
    third = wassat_cone_prove(decoded, aliases, workspace, fixture[1], fixture[2], 1, 0, false, stop)
    expect(third["equivalent"]).to eq(false)
    expect(pool[0]).to eq(3)
    z = wassat_cone_retry_release(workspace)

  it "copies full proof lines across repeated byte-buffer and owner reuse" ->
    expected = ["123 -456 7890 0", "0", "-9999 1 0"]
    i = 0
    while i < 100
      owner = wassat_query_storage()
      solver = Wassat.new(10000, [[1]], WASSAT_PROOF_DRAT, 0, false, owner)
      solver.query_drat_boxed([123, -456, 7890])
      solver.query_drat_boxed([])
      solver.query_drat_boxed([-9999, 1])
      result = solver.result_for(-1)
      detached = result["drat"].map -> (line)
        buffer = StringBuffer()
        buffer.append(line)
        buffer.to_s
      expect(detached).to eq(expected)
      z = wassat_query_destroy(owner)
      # Read after new allocations have had a chance to reuse freed memory.
      expect(detached).to eq(expected)
      i += 1

  it "keeps a separate solver and borrowed clauses alive after private disposal" ->
    rows = [[1, 2], [-1, 2], [1, -2]]
    ordinary = Wassat.new(2, rows, WASSAT_PROOF_DRAT)
    owner = wassat_query_storage()
    private_solver = Wassat.new(2, rows, WASSAT_PROOF_DRAT, 0, false, owner)
    result = private_solver.solve_assuming_budget([1], 100)
    detached_model = result["model"].dup
    expect(result["status"]).to eq(1)
    z = wassat_query_destroy(owner)
    expect(rows).to eq([[1, 2], [-1, 2], [1, -2]])
    formula = cone_fixture_flat(rows, 2)
    expect(wassat_model_satisfies?(formula, detached_model)).to eq(true)
    expect(ordinary.solve_budget(100)["status"]).to eq(1)

  it "isolates simultaneous owners while one solver continues after the other closes" ->
    rows = cone_fixture_rows
    decoded = wassat_cone_decode(cone_fixture_flat(rows, 7))
    workspace = wassat_cone_workspace(decoded)
    cone = wassat_cone_compact(decoded, i64[8], workspace, 4, 3)
    first_owner = wassat_query_storage(); second_owner = wassat_query_storage()
    first = Wassat.new(4, cone["clauses"], WASSAT_PROOF_DRAT, 0, false, first_owner)
    second = Wassat.new(4, cone["clauses"], WASSAT_PROOF_DRAT, 0, false, second_owner)
    expect(first.solve_assuming_budget([4, -3], 1)["status"]).to eq(-1)
    expect(second.solve_assuming_budget([-4, 3], 100)["status"]).to eq(-1)
    z = wassat_query_destroy(second_owner)
    expect(first.solve_assuming_budget([-4, 3], 100)["status"]).to eq(-1)
    z = wassat_query_destroy(first_owner)

  it "closes retained UNKNOWN queries without freeing a shared budget or stop cell" ->
    fixture = cone_php_circuit
    decoded = wassat_cone_decode(fixture[0])
    workspace = wassat_cone_workspace(decoded, 16384)
    cache = wassat_cone_retry_cache(1)
    workspace["retry_cache"] = cache; workspace["retry_active"] = true
    pool = i64[3]; stop = i64[2]
    workspace["conflict_budget"] = pool; workspace["conflict_limit"] = 7; workspace["conflict_slot"] = 2
    aliases = i64[decoded["nvars"] + 1]
    first = wassat_cone_prove(decoded, aliases, workspace, fixture[1], fixture[2], 1, 0, false, stop)
    expect(first["conflicts"]).to eq(1)
    expect(cache["resident"]).to eq(1)
    z = wassat_cone_retry_release(workspace)
    z = wassat_cone_retry_release(workspace)
    expect(cache["resident"]).to eq(0)
    expect(pool[0]).to eq(1)
    expect(wassat_stop_load(stop)).to eq(0)
    second = wassat_cone_prove(decoded, aliases, workspace, fixture[1], fixture[2], 1, 0, false, stop)
    expect(second["conflicts"]).to eq(1)
    expect(pool[0]).to eq(2)
    z = wassat_cone_retry_release(workspace)

spec_summary
