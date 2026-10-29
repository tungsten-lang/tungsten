use spec
use ../lib/solver

+ PhaseSnapshotFixture < Wassat
  -> prepare_snapshot_test
    @lucky_pending = false
    @pending_simplify = -1
    @use_target = false
    @use_vmtf = true
    @lookahead = 0
    @auto_vivify = false
    @escalate_at = 0
    @no_stable = true
    @walker = nil
    v = 1
    while v <= @nvars
      @phase[v] = -1
      @bphase[v] = 1
      @best_phase[v] = 1
      v += 1
    0

  -> chrono_snapshot_test
    @use_chrono = true
    @chrono_t = 0
    0

  -> rephase_snapshot_test
    @rephase_free = true
    @rephase_at = 1
    @rephase_idx = 1
    0

  -> rollout_snapshot_test
    @lookahead = 2
    0

  -> snapshot_matches_model?(assumption_levels = 0)
    return false unless @tsize == @nvars
    v = 1
    while v <= @nvars
      return false unless @bphase[v] == @assign[v]
      return false unless @best_phase[v] == @assign[v]
      v += 1
    out = 0
    lv = assumption_levels
    while lv < @dlevel
      v = @trail[@trail_lim[lv]].abs
      if @reason[v] < 0
        return false unless @epoch_spine[out] == v
        out += 1
      lv += 1
    out == @epoch_spine_len

-> phase_snapshot_fixture
  # The free variables precede a forced positive variable. Its conflict
  # changes the trail's order and polarity after a long saved prefix.
  s = PhaseSnapshotFixture.new(12, [[6, 7], [6, -7]], WASSAT_PROOF_NONE)
  s.prepare_snapshot_test
  s

describe "Wassat incremental phase snapshots" ->
  it "copies each assignment once on an uninterrupted descent" ->
    s = PhaseSnapshotFixture.new(64, [], WASSAT_PROOF_NONE)
    s.prepare_snapshot_test
    r = s.solve_budget(0)
    expect(r["sat"]).to eq(true)
    expect(r["decisions"]).to eq(64)
    expect(s.snapshot_matches_model?).to eq(true)
    expect(r["phase_snapshots"]).to eq(128)
    expect(r["phase_copied"]).to eq(128)
    expect(r["phase_skipped"]).to eq(4032)
    expect(r["spine_snapshots"]).to eq(64)
    expect(r["spine_scanned"]).to eq(64)
    expect(r["spine_skipped"]).to eq(2016)

  it "refreshes changed prefixes after a nonchronological conflict" ->
    s = phase_snapshot_fixture
    r = s.solve_budget(0)
    expect(r["sat"]).to eq(true)
    expect(r["conflicts"] > 0).to eq(true)
    expect(r["model"].include?(6)).to eq(true)
    expect(s.snapshot_matches_model?).to eq(true)

  it "refreshes prefixes after chronological backtracking" ->
    s = phase_snapshot_fixture
    s.chrono_snapshot_test
    r = s.solve_budget(0)
    expect(r["sat"]).to eq(true)
    expect(r["conflicts"] > 0).to eq(true)
    expect(r["model"].include?(6)).to eq(true)
    expect(s.snapshot_matches_model?).to eq(true)

  it "starts a fresh prefix when a budgeted search continues" ->
    s = phase_snapshot_fixture
    first = s.solve_budget(1)
    expect(first["status"]).to eq(0)
    r = s.solve_budget(0)
    expect(r["sat"]).to eq(true)
    expect(r["model"].include?(6)).to eq(true)
    expect(s.snapshot_matches_model?).to eq(true)
    expect(r["phase_copied"] > first["phase_copied"]).to eq(true)

  it "refreshes snapshots after a restart rewrites the target phases" ->
    s = phase_snapshot_fixture
    s.rephase_snapshot_test
    r = s.solve_budget(0)
    expect(r["sat"]).to eq(true)
    expect(r["restarts"] > 0).to eq(true)
    expect(r["model"].include?(6)).to eq(true)
    expect(s.snapshot_matches_model?).to eq(true)

  it "keeps snapshots correct across speculative rollout branches" ->
    s = phase_snapshot_fixture
    s.rollout_snapshot_test
    r = s.solve_budget(0)
    expect(r["sat"]).to eq(true)
    expect(r["model"].include?(6)).to eq(true)
    expect(s.snapshot_matches_model?).to eq(true)

  it "excludes assumption levels, including duplicate empty levels, from the saved spine" ->
    s = PhaseSnapshotFixture.new(8, [], WASSAT_PROOF_NONE)
    s.prepare_snapshot_test
    r = s.solve_assuming([-1, -1, -2])
    expect(r["sat"]).to eq(true)
    expect(s.best_spine_length).to eq(6)
    expect(s.snapshot_matches_model?(3)).to eq(true)
    expect(r["spine_scanned"] >= 6).to eq(true)
    expect(r["spine_skipped"] >= 0).to eq(true)

spec_summary
