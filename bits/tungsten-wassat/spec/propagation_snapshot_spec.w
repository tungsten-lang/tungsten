use spec
use ../lib/solver

+ SnapshotRepairCancelFixture < Wassat
  ro :qhead, :tsize, :wp_state, :formula_unsat

  -> cancel_after_next_repair(stop)
    self.rebuild_watches
    li = 0
    while li < 2 * @nvars + 4
      @wsdir[4 * li + 2] = @wsdir[4 * li + 1]
      li += 1
    @wp_state[1] = @wp_state[0]
    @test_cancel_stop = stop

  -> rebuild_watches
    result = super
    wassat_stop_cancel(@test_cancel_stop) if @test_cancel_stop != nil
    result

  -> retain_pending_root
    self.enable_chrono
    @trail_lim[0] = @tsize
    @dlevel = 1
    self.enqueue(2, -1)
    self.enqueue_lvl(3, -1, 0)

describe "Propagation snapshot root reuse" ->
  it "closes fresh root units once and reuses the completed queue" ->
    s = Wassat.new(4, [[1], [-1, 2], [-2, 3]], 0, 0)
    values = i8[5]; counters = i64[4]
    expect(s.propagation_snapshot([], values, counters)).to eq(1)
    expect(values[1]).to eq(1)
    expect(values[2]).to eq(1)
    expect(values[3]).to eq(1)
    expect(counters[1]).to eq(3)
    expect(s.propagation_snapshot([], values, counters)).to eq(1)
    expect(counters[0]).to eq(2)
    expect(counters[1]).to eq(3)

  it "retracts successful and failed assumptions without replaying closed roots" ->
    s = Wassat.new(4, [[1], [-1, 2], [-3, 4]], 0, 0)
    values = i8[5]; counters = i64[4]
    expect(s.propagation_snapshot([3], values, counters)).to eq(1)
    expect(values[4]).to eq(1)
    expect(s.propagation_snapshot([3, -4], values, counters)).to eq(-1)
    props = counters[1]
    expect(s.propagation_snapshot([], values, counters)).to eq(1)
    expect(counters[1]).to eq(props)
    expect(values[1]).to eq(1)
    expect(values[2]).to eq(1)
    expect(values[3]).to eq(0)
    expect(values[4]).to eq(0)
    expect(s.propagation_snapshot([-3], values, counters)).to eq(1)
    expect(values[3]).to eq(-1)
    expect(values[4]).to eq(0)

  it "replays a root contradiction on repeated queries" ->
    s = SnapshotRepairCancelFixture.new(3, [[1], [-1, 2], [-2]], 0, 0)
    values = i8[4]; counters = i64[4]
    expect(s.propagation_snapshot([], values, counters)).to eq(-1)
    expect(s.propagation_snapshot([], values, counters)).to eq(-1)
    expect(s.propagation_snapshot([3], values, counters)).to eq(-1)
    expect(counters[3]).to eq(3)
    expect(s.formula_unsat).to eq(false)

  it "propagates newly installed root units before the next snapshot" ->
    s = Wassat.new(4, [[1], [-2, 3], [-4, 2]], 0, 0)
    values = i8[5]; counters = i64[4]
    expect(s.propagation_snapshot([], values, counters)).to eq(1)
    s.install_pruning_clause([4], false)
    expect(s.propagation_snapshot([], values, counters)).to eq(1)
    expect(values[2]).to eq(1)
    expect(values[3]).to eq(1)
    expect(values[4]).to eq(1)

  it "replays a root scan interrupted during watch repair" ->
    clauses = [[-1], [-4], [1, 2, 3], [1, -2, 3], [-3, 4]]
    s = SnapshotRepairCancelFixture.new(4, clauses, 0, 0)
    values = i8[5]; counters = i64[4]; stop = i64[4]
    s.set_stop_cell(stop)
    s.cancel_after_next_repair(stop)
    expect(s.propagation_snapshot([], values, counters)).to eq(0)
    expect(s.wp_state[11]).to eq(1)
    expect(s.qhead).to eq(0)
    expect(values[1]).to eq(0)
    expect(counters[2]).to eq(1)
    s.set_stop_cell(nil)
    expect(s.propagation_snapshot([], values, counters)).to eq(-1)
    expect(s.formula_unsat).to eq(false)

  it "retracts a cancelled assumption scan and resumes on the same formula" ->
    s = SnapshotRepairCancelFixture.new(4, [[1, 2, 3], [-1, 2, 3], [-3, 4]], 0, 0)
    values = i8[5]; counters = i64[4]; stop = i64[4]
    s.set_stop_cell(stop)
    s.cancel_after_next_repair(stop)
    expect(s.propagation_snapshot([-1], values, counters)).to eq(0)
    expect(s.qhead).to eq(0)
    expect(s.wp_state[11]).to eq(1)
    s.set_stop_cell(nil)
    expect(s.propagation_snapshot([-1, -2], values, counters)).to eq(1)
    expect(values[3]).to eq(1)
    expect(values[4]).to eq(1)
    expect(s.propagation_snapshot([], values, counters)).to eq(1)
    expect(values[1]).to eq(0)
    expect(values[3]).to eq(0)
    expect(values[4]).to eq(0)

  it "propagates out-of-order root assignments retained by a chronological backjump" ->
    s = SnapshotRepairCancelFixture.new(4, [[1], [-3, 4]], 0, 0)
    values = i8[5]; counters = i64[4]
    expect(s.propagation_snapshot([], values, counters)).to eq(1)
    s.retain_pending_root
    expect(s.propagation_snapshot([], values, counters)).to eq(1)
    expect(values[1]).to eq(1)
    expect(values[2]).to eq(0)
    expect(values[3]).to eq(1)
    expect(values[4]).to eq(1)

spec_summary
