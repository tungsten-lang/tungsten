use spec
use ../lib/solver
use ../lib/preprocess

+ RootQueryFixture < Wassat
  ro :qhead, :tsize

  -> prepare_query_test
    @lucky_pending = false
    @auto_vivify = false
    @use_target = false
    @raw_flat = false
    @pending_simplify = -1
    self.set_phases([-1, -2, -3, -4])
    0

-> root_query_model_valid?(clauses, model)
  clauses.all? -> (clause)
    clause.any? -> (lit)
      model.include?(lit)

# The raw flat path deliberately queues input units without propagating them.
-> root_query_flat_artifact(nvars, clauses)
  total = 0
  clauses.each -> (clause)
    total += clause.size
  literals = i64[total]
  offsets = i64[clauses.size]
  lengths = i64[clauses.size]
  offset = 0
  index = 0
  clauses.each -> (clause)
    offsets[index] = offset
    lengths[index] = clause.size
    clause.each -> (lit)
      literals[offset] = lit
      offset += 1
    index += 1
  formula = { "nvars": nvars, "flat_lits": literals, "flat_offs": offsets,
    "flat_lens": lengths, "flat_ncl": clauses.size, "flat_nlits": total }
  wassat_raw_artifact(formula, nvars)

-> root_query_core_valid?(clauses, assumptions, core)
  return false if core.empty?
  return false unless core.all? -> (lit) assumptions.include?(lit)
  mask = 0
  while mask < 16
    model = []
    v = 1
    while v <= 4
      model.push((mask & (1 << (v - 1))) == 0 ? 0 - v : v)
      v += 1
    if root_query_model_valid?(clauses, model)
      return false if core.all? -> (lit) model.include?(lit)
    mask += 1
  true

describe "Wassat root propagation between incremental queries" ->
  it "propagates fresh boxed and flat input units before a SAT query" ->
    clauses = [[1], [2], [-1, -2, 3]]
    solvers = [RootQueryFixture.new(4, clauses, 0, 0)]
    flat = RootQueryFixture.new(4, [], 0, 0, true)
    flat.load_flat(root_query_flat_artifact(4, clauses))
    solvers.push(flat)
    solvers.each -> (solver)
      solver.prepare_query_test
      expect(solver.qhead < solver.tsize).to eq(true)
      result = solver.solve_assuming([4])
      expect(result["status"]).to eq(1)
      expect(root_query_model_valid?(clauses, result["model"])).to eq(true)
      expect(result["model"].include?(4)).to eq(true)

  it "returns a valid failed core after queued root implications" ->
    clauses = [[1], [2], [-1, -2, 3]]
    solver = RootQueryFixture.new(4, clauses, WASSAT_PROOF_WRAT, 0)
    solver.prepare_query_test
    result = solver.solve_assuming([-3])
    expect(result["status"]).to eq(-1)
    expect(result["model"].empty?).to eq(true)
    expect(root_query_core_valid?(clauses, [-3], result["core"])).to eq(true)
    expect(result["proof"].empty?).to eq(false)

  it "keeps a root contradiction terminal across later queries" ->
    clauses = [[1], [2], [-1, -2, 3], [-3]]
    solver = RootQueryFixture.new(4, clauses, 0, 0)
    solver.prepare_query_test
    [[4], [-4], []].each -> (assumptions)
      result = solver.solve_assuming(assumptions)
      expect(result["status"]).to eq(-1)
      expect(result["core"].empty?).to eq(true)
      expect(result["model"].empty?).to eq(true)

  it "replays a learned root unit after a budgeted UNKNOWN result" ->
    clauses = [[1, 2], [1, -2], [-1, 3]]
    solver = RootQueryFixture.new(4, clauses, 0, 0)
    solver.prepare_query_test
    first = solver.solve_assuming_budget([4], 1)
    expect(first["status"]).to eq(0)
    expect(first["conflicts"]).to eq(1)
    expect(solver.qhead < solver.tsize).to eq(true)
    second = solver.solve_assuming_budget([-3], 1)
    expect(second["status"]).to eq(-1)
    expect(second["conflicts"]).to eq(first["conflicts"])
    expect(root_query_core_valid?(clauses, [-3], second["core"])).to eq(true)
    core = second["core"].dup
    third = solver.solve_assuming([3, -4])
    expect(third["status"]).to eq(1)
    expect(root_query_model_valid?(clauses, third["model"])).to eq(true)
    expect(third["model"].include?(-4)).to eq(true)
    expect(first["status"]).to eq(0)
    expect(first["model"].empty?).to eq(true)
    expect(first["core"].empty?).to eq(true)
    expect(second["core"]).to eq(core)

  it "detaches models and cores across SAT and assumption-UNSAT queries" ->
    clauses = [[1], [2], [-1, -2, 3]]
    solver = RootQueryFixture.new(4, clauses, 0, 0)
    solver.prepare_query_test
    first = solver.solve_assuming([-3])
    expect(first["status"]).to eq(-1)
    core = first["core"].dup
    second = solver.solve_assuming([3, 4])
    expect(second["status"]).to eq(1)
    saved_model = second["model"].dup
    third = solver.solve_assuming([-3, -4])
    expect(third["status"]).to eq(-1)
    expect(root_query_core_valid?(clauses, [-3, -4], third["core"])).to eq(true)
    fourth = solver.solve_assuming([3, -4])
    expect(fourth["status"]).to eq(1)
    expect(root_query_model_valid?(clauses, fourth["model"])).to eq(true)
    expect(fourth["model"].include?(-4)).to eq(true)
    expect(first["core"]).to eq(core)
    expect(second["model"]).to eq(saved_model)

spec_summary
