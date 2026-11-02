use spec
use ../lib/wassat

-> aig_capacity_fixture(next_id)
  has_node = i8[8]
  left = i64[8]
  right = i64[8]
  mark = i64[800002]
  conf_stamp = i64[8]
  conf_val = i8[8]
  keys = i64[1048576]
  values = i64[1048576]
  memo_stamp = i64[8]
  memo_val = i64[8]
  state = i64[4]
  # Gate 5 is (a AND b) AND c. Under a=true it becomes b AND c.
  has_node[4] = 1
  left[4] = 1
  right[4] = 2
  has_node[5] = 1
  left[5] = 4
  right[5] = 3
  mark[400001] = 1
  state[1] = next_id
  state[2] = 1
  [has_node, left, right, mark, conf_stamp, conf_val, keys, values,
   memo_stamp, memo_val, state]

-> aig_capacity_restrict(f)
  wassat_aig_restrict_deep(5, 1, f[0], f[1], f[2], f[3], f[4], f[5],
    f[6], f[7], f[8], f[9], f[10])

describe "Wassat AIG rewrite capacity" ->
  it "retains a satisfiable original expression when the rewrite arena is full" ->
    f = aig_capacity_fixture(399999)
    expect(aig_capacity_restrict(f)).to eq(5)
    memo = f[9]
    expect(memo[5]).to eq(5)

  it "still constructs the simplified expression when space is available" ->
    f = aig_capacity_fixture(6)
    expect(aig_capacity_restrict(f)).to eq(6)
    left = f[1]
    right = f[2]
    expect(left[6]).to eq(2)
    expect(right[6]).to eq(3)

  it "reuses an interned node even when no new nodes fit" ->
    f = aig_capacity_fixture(399999)
    nodes = f[0]
    left = f[1]
    right = f[2]
    nodes[6] = 1
    left[6] = 2
    right[6] = 3
    key = (2 + 400000) * 1000003 + (3 + 400000)
    wassat_aig_ht_put(f[6], f[7], key, 6)
    expect(aig_capacity_restrict(f)).to eq(6)

  it "distinguishes missing capacity from an actual Boolean contradiction" ->
    f = aig_capacity_fixture(399999)
    expect(wassat_aig_intern_and(2, 3, f[0], f[1], f[2], f[6], f[7], f[10])).to eq(WASSAT_AIG_NO_NODE)
    expect(wassat_aig_intern_and(2, -2, f[0], f[1], f[2], f[6], f[7], f[10])).to eq(0)

  it "recomputes a stale positive conflict result for a new assumption" ->
    f = aig_capacity_fixture(6)
    stamps = f[4]
    values = f[5]
    stamps[5] = 1
    values[5] = 1
    expect(wassat_aig_cone_has_conflict(5, 2, f[0], f[1], f[2], f[3], stamps, values)).to eq(0)
    expect(stamps[5]).to eq(2)
    expect(values[5]).to eq(0)

  it "recomputes a stale negative conflict result for a new assumption" ->
    f = aig_capacity_fixture(6)
    marks = f[3]
    stamps = f[4]
    values = f[5]
    marks[400000 - 2] = 2
    stamps[5] = 1
    expect(wassat_aig_cone_has_conflict(5, 2, f[0], f[1], f[2], marks, stamps, values)).to eq(1)
    expect(stamps[5]).to eq(2)
    expect(values[5]).to eq(1)

  it "reuses a cached conflict result within the same assumption" ->
    f = aig_capacity_fixture(6)
    stamps = f[4]
    values = f[5]
    stamps[5] = 2
    values[5] = 1
    expect(wassat_aig_cone_has_conflict(5, 2, f[0], f[1], f[2], f[3], stamps, values)).to eq(1)

spec_summary
