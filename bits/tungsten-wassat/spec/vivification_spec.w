use spec
use ../lib/solver

# Promote input clauses only while exercising the learned-clause pass, then
# restore their status before search so reduction cannot discard inputs.
+ VivificationFixture < Wassat
  ro :vivified, :formula_unsat, :vivify_phase, :decisions_made, :reductions

  -> prepare_first_conflict
    @auto_vivify = false
    @lucky_pending = false
    @reduce_limit = 1000000
    @reduce_step = 1000000
    @clbd[0] = 3
    @clbd[1] = 3
    @nlearned = 2
    0

  -> arm_automatic_pass
    raise "expected one conflict" unless @conflicts == 1
    raise "expected root unit 1" unless self.value(1) == 1 && @level[1] == 0
    raise "contradiction reached before vivification" unless self.value(7) == 0
    @auto_vivify = true
    @reduce_limit = 1
    0

  -> mark_candidates
    ci = 0
    while ci < @ncl
      if @alive[ci] == 1 && @cmeta[2 * ci + 1] >= 3
        @clbd[ci] = 3
        @nlearned += 1
      ci += 1
    0

  -> restore_irredundant
    ci = 0
    while ci < @ncl
      @clbd[ci] = 0
      ci += 1
    @nlearned = 0
    0

  -> phase_bits
    bits = 0
    v = 1
    while v <= @nvars
      bits = bits | (1 << (v - 1)) if @phase[v] > 0
      v += 1
    bits

  -> root_trail_valid?
    return false unless @dlevel == 0 && @tsize <= @nvars
    seen = i64[@nvars + 1]
    i = 0
    while i < @tsize
      lit = @trail[i]
      v = lit.abs
      return false if seen[v] != 0 || self.value(lit) <= 0 || @level[v] != 0
      seen[v] = 1
      i += 1
    true

-> vivification_duplicate_fixture
  clauses = [[1, 2, 3, 4, 5, 6, 7, 8, 9]]
  i = 2
  while i <= 8
    clauses.push([1, 0 - i])
    i += 1
  clauses.push([1, 9])
  clauses

-> vivification_model_valid?(clauses, model)
  valid = true
  clauses.each -> (clause)
    hit = false
    clause.each -> (lit)
      model.each -> (value)
        hit = true if value == lit
    valid = false unless hit
  valid

describe "Wassat vivification" ->
  it "does not enqueue variables already assigned by a probe" ->
    clauses = vivification_duplicate_fixture
    solver = VivificationFixture.new(9, clauses, 0, 0)
    solver.mark_candidates
    solver.vivify_round
    expect(solver.root_trail_valid?).to eq(true)
    expect(solver.vivified).to eq(1)
    solver.restore_irredundant
    result = solver.solve_budget(1000)
    expect(result["status"]).to eq(1)
    expect(vivification_model_valid?(clauses, result["model"])).to eq(true)

  it "retains a root conflict caused by a derived unit" ->
    clauses = [[1, 2, 3], [4, 5, 6], [1, 7], [1, -7], [-1, 8], [-1, -8]]
    solver = VivificationFixture.new(8, clauses, 0, 0)
    solver.mark_candidates
    solver.vivify_round
    expect(solver.formula_unsat).to eq(true)
    expect(solver.root_trail_valid?).to eq(true)
    solver.restore_irredundant
    result = solver.solve_budget(1000)
    expect(result["status"]).to eq(-1)
    expect(result["model"].empty?).to eq(true)

  it "restores saved phases after implication probes" ->
    solver = VivificationFixture.new(9, vivification_duplicate_fixture, 0, 0)
    solver.set_phases([1, -2, 3, -4, 5, -6, 7, -8, 9])
    before = solver.phase_bits
    solver.mark_candidates
    solver.vivify_round
    expect(solver.phase_bits).to eq(before)

  it "stops the search loop immediately after a vivification root conflict" ->
    clauses = [[7, 8, 9], [10, 11, 12], [1, 2], [1, -2], [7, 13], [7, -13], [-7, 14], [-7, -14]]
    solver = VivificationFixture.new(14, clauses, 0, 0)
    solver.prepare_first_conflict
    first = solver.solve_budget(1)
    expect(first["status"]).to eq(0)
    solver.arm_automatic_pass
    decisions_before = solver.decisions_made
    result = solver.solve_budget(100)
    expect(solver.reductions).to eq(1)
    expect(solver.vivified).to eq(1)
    expect(solver.decisions_made).to eq(decisions_before)
    expect(solver.formula_unsat).to eq(true)
    expect(result["status"]).to eq(-1)
    expect(result["model"].empty?).to eq(true)

  it "handles pending root units before making probe decisions" ->
    clauses = [[1], [-1, 2, 3, 4], [2, -3], [2, -4]]
    solver = VivificationFixture.new(4, clauses, 0, 0)
    solver.mark_candidates
    solver.vivify_round
    expect(solver.root_trail_valid?).to eq(true)
    solver.restore_irredundant
    result = solver.solve_budget(1000)
    expect(result["status"]).to eq(1)
    expect(vivification_model_valid?(clauses, result["model"])).to eq(true)

  it "uses the prepared buffer or skips the pass in fixed-capacity workers" ->
    clauses = vivification_duplicate_fixture
    solver = VivificationFixture.new(9, clauses, 0, 0)
    prepared = solver.vivify_phase != nil
    solver.mark_candidates
    solver.enable_fixed_caps
    solver.vivify_round
    expect(solver.vivified).to eq(prepared ? 1 : 0)
    expect(solver.root_trail_valid?).to eq(true)
    solver.restore_irredundant
    result = solver.solve_budget(1000)
    expect(result["status"]).to eq(1)
    expect(vivification_model_valid?(clauses, result["model"])).to eq(true)

spec_summary
