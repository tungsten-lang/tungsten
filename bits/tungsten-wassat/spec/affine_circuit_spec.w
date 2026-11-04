use spec
use ../lib/wassat
use ../lib/affine_circuit
use affine_circuit_support

-> affine_small_fixture
  f = AffineCircuitFixture.new(8)
  f.gate([1], 2)
  i = 1
  while i <= 4
    a = f.gate([i], 2); b = f.gate([i + 4], 2)
    f.parity(a, b, true); i += 1
  z = f.gate([1, 2], 8)
  f.clauses.push([z])
  f

describe "Affine constraints in model-only circuits" ->
  it "reduces free inputs and replays every original clause" ->
    f = affine_small_fixture.flat; m = i64[32]
    model = wassat_affine_circuit_model(f, m, i64[2])
    expect(affine_fixture_checked(f, model)).to eq(true)
    expect(m[12]).to eq(4)
    expect(m[13]).to eq(4)
    expect(m[9]).to eq(f["flat_ncl"])

  it "does not infer UNSAT when a nonlinear assertion is impossible" ->
    fixture = affine_small_fixture
    fixture.clauses.push([-1])
    m = i64[32]
    model = wassat_affine_circuit_model(fixture.flat, m, i64[2])
    expect(model.empty?).to eq(true)
    expect(m[0]).to eq(0)

  it "requires the complete parity relation before restricting choices" ->
    fixture = AffineCircuitFixture.new(4)
    a = fixture.gate([1], 2); b = fixture.gate([2], 2)
    fixture.clauses.push([a, b])
    fixture.clauses.push([1]); fixture.clauses.push([2])
    f = fixture.flat; m = i64[32]
    model = wassat_affine_circuit_model(f, m, i64[2])
    expect(m[12]).to eq(0)
    expect(affine_fixture_checked(f, model)).to eq(true)

  it "handles a candidate in the sign-bit lane" ->
    fixture = AffineCircuitFixture.new(7)
    a = fixture.gate([1], 2); b = fixture.gate([7], 2)
    fixture.parity(a, b, true)
    i = 1
    while i <= 6
      fixture.clauses.push([i]); i += 1
    f = fixture.flat; m = i64[32]
    model = wassat_affine_circuit_model(f, m, i64[2])
    expect(affine_fixture_checked(f, model)).to eq(true)
    expect(m[16]).to eq(1)
    expect(model[6]).to eq(-7)

  it "reuses the packed buffer for a later batch" ->
    fixture = AffineCircuitFixture.new(8)
    a = fixture.gate([1], 2); b = fixture.gate([8], 2)
    fixture.parity(a, b, true)
    i = 1
    while i <= 7
      fixture.clauses.push(((70 >> (i - 1)) & 1) == 1 ? [i] : [-i]); i += 1
    f = fixture.flat; m = i64[32]
    model = wassat_affine_circuit_model(f, m, i64[2])
    expect(affine_fixture_checked(f, model)).to eq(true)
    expect(m[16]).to eq(2)

  it "bounds enumeration even when there is little affine information" ->
    fixture = AffineCircuitFixture.new(13)
    fixture.gate([1], 2); m = i64[32]
    model = wassat_affine_circuit_model(fixture.flat, m, i64[2])
    expect(model.empty?).to eq(true)
    expect(m[13]).to eq(13)
    expect(m[16]).to eq(0)

  it "supports primary masks above 32 bits" ->
    p = i64[61]; m = i64[32]
    r = (1 << 60) | (1 << 39) | 1
    expect(wassat_affine_circuit_row(r, p, 60, m)).to eq(1)
    expect(p[60]).to eq(r)
    expect(wassat_affine_circuit_row(r ^ 1, p, 60, m)).to eq(0)
    expect(m[12]).to eq(1)

  it "honors pre-cancellation, deadline and work limits" ->
    f = affine_small_fixture.flat; m = i64[32]; stop = i64[2]
    z = wassat_stop_cancel(stop)
    expect(wassat_affine_circuit_model(f, m, stop).empty?).to eq(true)
    expect(m[11]).to eq(1)
    expect(m[4]).to eq(0)
    m = i64[32]
    expect(wassat_affine_circuit_model(f, m, i64[2], clock_ms() - 1).empty?).to eq(true)
    expect(m[11]).to eq(2)
    m = i64[32]; m[6] = 64000001
    expect(wassat_affine_circuit_poll(m, i64[2], 0)).to eq(1)
    expect(m[11]).to eq(3)

  it "retries cancellation and found-but-unpublished models" ->
    f = affine_small_fixture.flat; m = i64[32]; plan = { "meta": m }
    m[11] = 1
    wassat_affine_circuit_finish_scout(f, plan)
    expect(f["affine_circuit_done"]).to eq(false)
    m[11] = 0; m[0] = 1
    wassat_affine_circuit_finish_scout(f, plan)
    expect(f["affine_circuit_done"]).to eq(false)
    m[0] = 0
    wassat_affine_circuit_finish_scout(f, plan)
    expect(f["affine_circuit_done"]).to eq(true)

  it "declines unsupported primary headers" ->
    f = affine_small_fixture.flat
    f["flat_lits"][0] = 1
    expect(wassat_affine_circuit_primary(f)).to eq(0)
    expect(wassat_affine_circuit_primary(nil)).to eq(0)

spec_summary
