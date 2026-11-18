# spec: compiled -- portfolio threads, quiescent barriers and atomic budgets
use spec
use ../lib/wassat
use circuit_cone_php_fixture
use ../../tungsten-wrat/lib/wrat

+ ConeSlowRaw < Wassat
  -> solve_shared_budget(res, base, cap)
    ccall("__w_sleep_ms", 40)
    super(res, base, cap)

-> cone_fast_test_race(formula, threads = 2, window_ms = 30000, retention_bytes = 0)
  plan = wassat_cone_fast_plan(formula, window_ms, retention_bytes)
  art = wassat_raw_artifact(formula, formula["nvars"])
  wassat_race_build(formula["nvars"], art, threads, formula, nil, 0, 0, 0, 0, 0, 0, nil, nil, nil, 0, plan)

-> cone_restore_env(name, value)
  if value == nil
    Env.delete(name)
  else
    Env.set(name, value)

describe "Comparison-cone fast portfolio" ->
  it "publishes a specialist win with a checked original proof" ->
    rows = cone_fixture_rows(3)
    f = cone_fixture_flat(rows, 15)
    race = cone_fast_test_race(f, 1, 30000, 1048576)
    # The existing enumerator can also refute this tiny fixture. Isolate the
    # cone publication path here; the other examples retain normal workers.
    race["circuit_plan"] = nil
    delayed = ConeSlowRaw.new(15, rows, WASSAT_PROOF_NONE)
    delayed.set_stop_cell(race["stop"])
    race["solvers"][0] = delayed
    result = wassat_race_run(race, 1000)
    expect(result["status"]).to eq(-1)
    expect(result["comparison_cones_won"]).to eq(true)
    expect(race["cone_plan"]["slices"]).to eq(1)
    expect(race["cone_plan"]["state"]["workspace"]["retry_cache"]["resident"]).to eq(0)
    proof = race["cone_plan"]["state"]["result"]["drat_text"]
    text = "p cnf 15 [rows.size]\n"
    rows.each -> (row) text += row.join(" ") + " 0\n"
    expect(wrat_verify(text, proof)["verified"]).to eq(true)

  it "preserves ordinary SAT answers and original models" ->
    f = cone_fixture_flat(cone_rare_rows, 66)
    race = cone_fast_test_race(f)
    result = wassat_race_run(race, 1000)
    expect(result["status"]).to eq(1)
    expect(result["comparison_cones_won"]).to eq(false)
    expect(race["cone_plan"]["state"]["storage_released"]).to eq(true)
    expect(wassat_model_satisfies?(f, result["model"])).to eq(true)

  it "shares exact finite conflict tickets with every raw arm" ->
    f = cone_php_circuit[0]
    [1, 7, 101].each -> (cap)
      race = cone_fast_test_race(f)
      result = wassat_race_run(race, cap)
      expect(result["status"]).to eq(0)
      expect(result["conflicts"]).to eq(cap)
      state = result["conflict_budget"]
      sum = 0; i = 1
      while i < state.size
        sum += state[i]; i += 1
      expect(state[0]).to eq(sum)
      expect(state[0]).to eq(cap)

  it "reports actual work from losing arms in an unlimited race" ->
    f = cone_php_circuit(7, 6)[0]
    race = cone_fast_test_race(f)
    result = wassat_race_run(race, 0)
    expect(result["status"]).to eq(-1)
    actual = race["cone_plan"]["state"]["result"]["conflicts"]
    i = 0
    while i < race["threads"]
      actual += race["solvers"][i].unknown_result["conflicts"]
      i += 1
    expect(result["conflicts"]).to eq(actual)

  it "joins and resumes the worker across ordinary allocation barriers" ->
    old_round = env("WASSAT_ROUND1"); old_realloc = env("WASSAT_REALLOC")
    begin
      Env.set("WASSAT_ROUND1", "10"); Env.set("WASSAT_REALLOC", "1")
      race = cone_fast_test_race(cone_php_circuit[0])
      result = wassat_race_run(race, 500)
      expect(result["status"]).to eq(0)
      expect(result["conflicts"]).to eq(500)
      expect(race["cone_plan"]["slices"] > 1).to eq(true)
    ensure
      cone_restore_env("WASSAT_ROUND1", old_round)
      cone_restore_env("WASSAT_REALLOC", old_realloc)

  it "ends an expired specialist without cancelling ordinary work" ->
    f = cone_php_circuit[0]
    race = cone_fast_test_race(f, 2, 1)
    # Otherwise a fast machine can spend the entire small conflict budget
    # before the one-millisecond deadline has actually elapsed.
    i = 0
    while i < race["threads"]
      delayed = ConeSlowRaw.new(f["nvars"], wassat_formula_clauses(f), WASSAT_PROOF_NONE)
      delayed.set_stop_cell(race["stop"])
      race["solvers"][i] = delayed
      i += 1
    result = wassat_race_run(race, 500)
    expect(result["status"]).to eq(0)
    expect(result["conflicts"]).to eq(500)
    expect(race["cone_plan"]["state"]["finished"]).to eq(true)
    expect(race["cone_plan"]["state"]["result"]["stopped"]).to eq(true)

  it "does not start an injected parallel worker in sequential mode" ->
    old = env("WASSAT_SEQUENTIAL")
    begin
      Env.set("WASSAT_SEQUENTIAL", "1")
      race = cone_fast_test_race(cone_php_circuit[0])
      result = wassat_race_run(race, 50)
      expect(result["conflicts"]).to eq(50)
      expect(race["cone_plan"]["slices"]).to eq(0)
    ensure
      cone_restore_env("WASSAT_SEQUENTIAL", old)

spec_summary
