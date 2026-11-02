use spec
use cyclic_bound_support

describe "Checked circular neighborhood capacity" ->
  it "refutes a crowded even ball from complete original premises" ->
    edges = [[0, 1], [0, 2], [0, 3], [0, 4]]
    f = cycle_bound_fixture(7, 3, edges)
    m = i64[24]
    expect(cycle_bound_check(f, 7, 3, edges, m, i64[4])).to eq(-1)
    expect([m[0], m[2], m[3], m[4], m[5], m[18], m[19]]).to eq([-1, 2, 4, 3, 4, 7, 4])

  it "checks implication supports even with backward alias arcs" ->
    edges = [[0, 1], [0, 2], [0, 3], [0, 4]]
    f = cycle_bound_fixture(7, 3, edges, "", true)
    m = i64[24]
    expect(cycle_bound_check(f, 7, 3, edges, m, i64[4])).to eq(-1)
    expect(m[15] > 0).to eq(true)

  it "declines when a row exclusion is missing" ->
    edges = [[0, 1], [0, 2], [0, 3], [0, 4]]
    f = cycle_bound_fixture(7, 3, edges, "row")
    m = i64[24]
    expect(cycle_bound_check(f, 7, 3, edges, m, i64[4])).to eq(0)
    expect(m[0]).to eq(1)

  it "declines an unchecked graph-edge exclusion" ->
    edges = [[0, 1], [0, 2], [0, 3], [0, 4]]
    f = cycle_bound_fixture(7, 3, edges, "edge")
    m = i64[24]
    expect(cycle_bound_check(f, 7, 3, edges, m, i64[4])).to eq(0)
    expect(m[0]).to eq(1)

  it "requires every matrix column" ->
    edges = [[0, 1], [0, 2], [0, 3], [0, 4]]
    f = cycle_bound_fixture(7, 3, edges, "column")
    m = i64[24]
    expect(cycle_bound_check(f, 7, 3, edges, m, i64[4])).to eq(0)
    expect(m[20]).to eq(0)

  it "does not refute a path with a valid cyclic labeling" ->
    edges = [[0, 1], [1, 2], [2, 3], [3, 4], [4, 5], [5, 6]]
    f = cycle_bound_fixture(7, 3, edges)
    m = i64[24]
    expect(cycle_bound_check(f, 7, 3, edges, m, i64[4])).to eq(0)
    model = []
    v = 1
    while v <= 49
      chosen = (v - 1) % 7 == ((v - 1) / 7 * 3) % 7
      model.push(chosen ? v : -v)
      v += 1
    expect(wassat_model_satisfies?(f, model)).to eq(true)

  it "covers both high and low bitset words without growing scratch" ->
    support = i64[6]; masks = i32[3]; cover = i64[130]; m = i64[24]
    one = 1 ## i64
    support[2] = one << 63
    support[3] = 1
    support[4] = one << 62
    support[5] = 1
    masks[2] = 3
    wassat_cycle_bound_rectangle(1, 2, 2, support, masks, cover, m)
    expect([cover[126], cover[127], cover[128], cover[129]]).to eq([one << 62, 1, one << 62, 1])
    expect([m[14], m[16], cover.size]).to eq([4, 2, 130])

  it "honors prior cancellation and expired deadlines" ->
    m = i64[24]; stop = i64[4]
    wassat_stop_cancel(stop)
    expect(wassat_cycle_bound_poll(m, stop, 0)).to eq(1)
    expect(m[22]).to eq(1)
    m = i64[24]; stop = i64[4]
    expect(wassat_cycle_bound_poll(m, stop, clock_ms() - 1)).to eq(2)
    expect(m[22]).to eq(2)

  it "treats the work ceiling as unknown" ->
    m = i64[24]
    m[14] = 12000000001
    expect(wassat_cycle_bound_poll(m, i64[4], 0)).to eq(3)
    expect([m[0], m[22]]).to eq([0, 3])

  it "requires the high tail bit in a partial coverage word" ->
    edges = [[0, 1], [0, 2], [0, 3], [0, 4]]
    f = cycle_bound_fixture(63, 31, edges, "high_row")
    m = i64[24]
    expect(cycle_bound_check(f, 63, 31, edges, m, i64[4])).to eq(0)
    expect(m[0]).to eq(1)
    expect(m[18]).to eq(0)

  it "requires the sign bit in a full coverage word" ->
    edges = [[0, 1], [0, 2], [0, 3], [0, 4]]
    f = cycle_bound_fixture(64, 32, edges, "high_row")
    m = i64[24]
    expect(cycle_bound_check(f, 64, 32, edges, m, i64[4])).to eq(0)
    expect(m[0]).to eq(1)
    expect(m[18]).to eq(0)

spec_summary
