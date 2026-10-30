use spec
use ../lib/solver

# Mid-search inprocessing passes: root cleaning, failed-literal probing
# (lifting, equivalences), all-clause subsumption, and the full round.
+ InprocessFixture < Wassat
  ro :inprocessings, :nsubst, :inp_equivs, :inp_failed, :inp_lifted, :inp_subsumed, :inp_strengthened

  -> clause_lits(ci)
    out = []
    st = @cmeta[2 * ci]
    n = @cmeta[2 * ci + 1]
    i = 0
    while i < n
      out.push(@arena[st + i])
      i += 1
    out

  -> clause_alive?(ci)
    @alive[ci] == 1

  -> clause_lbd(ci)
    @clbd[ci]

  -> mark_learned(ci, lbd)
    @clbd[ci] = lbd
    0

  # Reduce (and so reach the inprocessing check) every few dozen learned
  # clauses, so small formulas exercise whole rounds mid-search.
  -> tight_reduce
    @reduce_limit = 40
    @reduce_step = 40
    0

  # No lucky dives and no walk, so the search has to earn its model.
  -> plain_search
    @lucky_pending = false
    @use_walk = false
    @walker = nil
    0

  -> escalation_point
    @escalate_at

  -> shrinking?
    @use_shrink

  -> root_value(l)
    return 0 unless @dlevel == 0
    self.value(l)

  -> watch_rebuilds
    @wp_state[3]

-> inprocess_model_valid?(clauses, model)
  valid = true
  clauses.each -> (clause)
    hit = false
    clause.each -> (lit)
      model.each -> (value)
        hit = true if value == lit
    valid = false unless hit
  valid

# A satisfiable formula with a planted model, structured enough (binary
# chains plus ternaries) to give every pass something to do.
-> inprocess_planted(nv, ncl, seed, binary_share = 3)
  rng = seed
  planted = i64[nv + 1]
  v = 1
  while v <= nv
    rng = (rng * 1103515245 + 12345) % 2147483648
    planted[v] = (rng / 65536) % 2 == 0 ? 1 : -1
    v += 1
  clauses = []
  while clauses.size < ncl
    rng = (rng * 1103515245 + 12345) % 2147483648
    k = binary_share > 0 && (rng / 65536) % binary_share == 0 ? 2 : 3
    clause = []
    sat = false
    j = 0
    while j < k
      rng = (rng * 1103515245 + 12345) % 2147483648
      x = (rng / 65536) % nv + 1
      rng = (rng * 1103515245 + 12345) % 2147483648
      lit = (rng / 65536) % 2 == 0 ? x : 0 - x
      sat = true if (lit > 0 ? planted[x] : 0 - planted[x]) > 0
      clause.push(lit)
      j += 1
    clauses.push(clause) if sat
  clauses

-> inprocess_pigeonhole(p, h)
  clauses = []
  i = 0
  while i < p
    row = []
    j = 0
    while j < h
      row.push(i * h + j + 1)
      j += 1
    clauses.push(row)
    i += 1
  j = 0
  while j < h
    a = 0
    while a < p
      b = a + 1
      while b < p
        clauses.push([0 - (a * h + j + 1), 0 - (b * h + j + 1)])
        b += 1
      a += 1
    j += 1
  clauses

describe "Wassat inprocessing" ->
  it "strips root-false literals and drops root-satisfied clauses" ->
    clauses = [[1], [-1, 2, 3], [1, 4, 5], [6, 7, 8]]
    s = InprocessFixture.new(8, clauses, WASSAT_PROOF_NONE, 0)
    s.clean_root_clauses
    expect(s.clause_lits(1)).to eq([2, 3])
    expect(s.clause_alive?(2)).to eq(false)
    expect(s.clause_alive?(3)).to eq(true)
    # the shortened clause now propagates as a binary
    r = s.solve_assuming([-2])
    expect(r["status"]).to eq(1)
    expect(r["model"].include?(3)).to eq(true)
    expect(inprocess_model_valid?(clauses, r["model"])).to eq(true)

  it "skips a clean when nothing changed since the last one" ->
    clauses = [[1], [-1, 2, 3], [1, 4, 5], [6, 7, 8]]
    s = InprocessFixture.new(8, clauses, WASSAT_PROOF_NONE, 0)
    s.clean_root_clauses
    n0 = s.watch_rebuilds
    s.clean_root_clauses
    expect(s.watch_rebuilds).to eq(n0)

  it "cleans again once subsumption rewrote a clause body" ->
    clauses = [[-2, 3], [1, 2, 3], [4, 5, 6]]
    s = InprocessFixture.new(6, clauses, WASSAT_PROOF_NONE, 0)
    s.clean_root_clauses
    n0 = s.watch_rebuilds
    s.run_subsume(1, 100000)
    s.clean_root_clauses
    expect(s.watch_rebuilds > n0).to eq(true)

  it "asserts a unit exposed by cleaning and detects a root conflict" ->
    s = InprocessFixture.new(4, [[1], [2], [-1, -2, 3, 4], [-3], [-4]], WASSAT_PROOF_NONE, 0)
    s.clean_root_clauses
    r = s.solve_budget(100)
    expect(r["status"]).to eq(-1)

  it "finds a subsumer whose first literal differs from the target's" ->
    clauses = [[2, 3], [1, 2, 3], [4, 5, 6]]
    s = InprocessFixture.new(6, clauses, WASSAT_PROOF_NONE, 0)
    s.run_subsume(1, 100000)
    expect(s.clause_alive?(1)).to eq(false)
    expect(s.clause_alive?(0)).to eq(true)
    s.clean_root_clauses
    r = s.solve_budget(100)
    expect(r["status"]).to eq(1)
    expect(inprocess_model_valid?(clauses, r["model"])).to eq(true)

  it "strengthens an irredundant clause by self-subsuming resolution" ->
    clauses = [[-2, 3], [1, 2, 3], [4, 5, 6]]
    s = InprocessFixture.new(6, clauses, WASSAT_PROOF_NONE, 0)
    s.run_subsume(1, 100000)
    expect(s.clause_lits(1)).to eq([1, 3])
    expect(s.clause_lbd(1)).to eq(0)
    s.clean_root_clauses
    r = s.solve_assuming([-1, -3])
    expect(r["status"]).to eq(-1)

  it "promotes a learned subsumer that deletes an irredundant clause" ->
    clauses = [[2, 3], [1, 2, 3], [4, 5, 6]]
    s = InprocessFixture.new(6, clauses, WASSAT_PROOF_NONE, 0)
    s.mark_learned(0, 3)
    s.run_subsume(1, 100000)
    expect(s.clause_alive?(1)).to eq(false)
    expect(s.clause_lbd(0)).to eq(0)

  it "never resolves with a tautological subsumer" ->
    clauses = [[1, -1], [-1, 2, 3], [4, 5, 6]]
    s = InprocessFixture.new(6, clauses, WASSAT_PROOF_NONE, 0)
    s.run_subsume(1, 100000)
    expect(s.clause_lits(1)).to eq([-1, 2, 3])
    expect(s.clause_alive?(1)).to eq(true)

  it "leaves irredundant clauses alone in learned-only mode" ->
    clauses = [[2, 3], [1, 2, 3], [4, 5, 6]]
    s = InprocessFixture.new(6, clauses, WASSAT_PROOF_NONE, 0)
    s.run_subsume(0, 100000)
    expect(s.clause_alive?(1)).to eq(true)

  it "turns a failed literal into a root unit" ->
    clauses = [[-1, 2], [-1, 3], [-2, -3], [1, 4, 5], [4, 5, 6]]
    s = InprocessFixture.new(6, clauses, WASSAT_PROOF_NONE, 0)
    s.prepare_inprocessing
    s.probe_round(1000000)
    expect(s.root_value(1)).to eq(-1)
    expect(s.inp_failed >= 1).to eq(true)
    r = s.solve_budget(100)
    expect(r["status"]).to eq(1)
    expect(inprocess_model_valid?(clauses, r["model"])).to eq(true)

  it "lifts a literal implied by both polarities of a probe" ->
    clauses = [[-1, 2], [-2, 3], [1, 3], [3, 4, 5], [-4, -5, 6]]
    s = InprocessFixture.new(6, clauses, WASSAT_PROOF_NONE, 0)
    s.prepare_inprocessing
    s.probe_round(1000000)
    expect(s.root_value(3)).to eq(1)
    expect(s.inp_lifted >= 1).to eq(true)

  it "states probe equivalences as binaries that substitution collapses" ->
    # 1 -> 4 needs the ternary, and -1 -> -4 is a binary: 1 <=> 4.
    clauses = [[-1, 2], [-1, 3], [-2, -3, 4], [1, -4], [4, 5, 6], [-5, -6, 1]]
    s = InprocessFixture.new(6, clauses, WASSAT_PROOF_NONE, 0)
    s.prepare_inprocessing
    s.probe_round(1000000)
    expect(s.inp_equivs >= 1).to eq(true)
    s.clean_root_clauses
    s.substitute_equivalences
    s.clean_root_clauses
    expect(s.nsubst >= 1).to eq(true)
    r = s.solve_budget(1000)
    expect(r["status"]).to eq(1)
    expect(inprocess_model_valid?(clauses, r["model"])).to eq(true)

  it "keeps the verdict and model under frequent rounds on a satisfiable formula" ->
    clauses = inprocess_planted(300, 1290, 20261029, 0)
    s = InprocessFixture.new(300, clauses, WASSAT_PROOF_NONE, 0)
    s.plain_search
    s.enable_inprocess(1, 20)
    s.tight_reduce
    r = s.solve_budget(200000)
    expect(r["status"]).to eq(1)
    expect(inprocess_model_valid?(clauses, r["model"])).to eq(true)
    expect(s.inprocessings > 0).to eq(true)

  # Planted inputs include tautologies and duplicate literals, which is how
  # this caught a tautological subsumer "strengthening" irredundant clauses.
  it "finds valid models across planted formulas with every pass active" ->
    bad = 0
    rounds = 0
    seed = 1
    while seed <= 8
      nv = seed % 2 == 0 ? 300 : 400
      share = seed % 3 == 0 ? 0 : (seed % 3 == 1 ? 3 : 5)
      ncl = share == 0 ? nv * 43 / 10 : nv * 5
      clauses = inprocess_planted(nv, ncl, seed * 7919, share)
      s = InprocessFixture.new(nv, clauses, WASSAT_PROOF_NONE, 0)
      s.plain_search
      s.enable_inprocess(1, 10 + seed % 30)
      s.tight_reduce
      s.enable_fixed_caps if seed % 4 == 0
      r = s.solve_budget(300000)
      rounds += s.inprocessings
      bad += 1 unless r["status"] == 1 && inprocess_model_valid?(clauses, r["model"])
      seed += 1
    expect(bad).to eq(0)
    expect(rounds > 8).to eq(true)

  it "keeps the verdict under frequent rounds on an unsatisfiable formula" ->
    clauses = inprocess_pigeonhole(8, 7)
    s = InprocessFixture.new(56, clauses, WASSAT_PROOF_NONE, 0)
    s.enable_inprocess(1, 20)
    s.tight_reduce
    r = s.solve_budget(0)
    expect(r["status"]).to eq(-1)
    expect(s.inprocessings > 0).to eq(true)

  it "runs no round on a solver whose race arm leaves inprocessing out" ->
    clauses = inprocess_planted(300, 1290, 20261029, 0)
    s = InprocessFixture.new(300, clauses, WASSAT_PROOF_NONE, 0)
    s.plain_search
    s.enable_inprocess(1, 20)
    s.disable_inprocess
    s.tight_reduce
    r = s.solve_budget(200000)
    expect(r["status"]).to eq(1)
    expect(s.inprocessings).to eq(0)

  it "keeps fixed-capacity solvers allocation-free by preparing up front" ->
    clauses = inprocess_planted(150, 640, 77)
    s = InprocessFixture.new(150, clauses, WASSAT_PROOF_NONE, 0)
    s.enable_inprocess(1, 20)
    s.tight_reduce
    s.enable_fixed_caps
    r = s.solve_budget(200000)
    expect(r["status"]).to eq(1)
    expect(inprocess_model_valid?(clauses, r["model"])).to eq(true)

  it "never substitutes in a solver that has answered assumption queries" ->
    clauses = [[-1, 2], [-1, 3], [-2, -3, 4], [1, -4], [4, 5, 6], [-5, -6, 1]]
    s = InprocessFixture.new(6, clauses, WASSAT_PROOF_NONE, 0)
    r0 = s.solve_assuming([4])
    expect(r0["status"]).to eq(1)
    s.prepare_inprocessing
    s.probe_round(1000000)
    expect(s.inp_equivs).to eq(0)

  it "keeps stable-only arms out of frontier escalation" ->
    s = InprocessFixture.new(4, [[1, 2], [3, 4]], WASSAT_PROOF_NONE, 0)
    s.enable_stable_only
    expect(s.escalation_point).to eq(0)

  it "drops All-UIP shrinking when frontier mode turns chrono on" ->
    s = InprocessFixture.new(4, [[1, 2], [3, 4]], WASSAT_PROOF_NONE, 0)
    s.enable_shrink
    s.enable_frontier_mode
    expect(s.shrinking?).to eq(false)

spec_summary
