# spec: compiled -- exercises the native tabu workers and their shared stop cell
use spec
use ../lib/wassat

# With local values 0 and 2 available, the only allowed pair selects value
# 2 in the first domain and 0 in the second. Removing it exhausts both walks.
-> pattern_walk_fixture(allow_model)
  dom = i64[2]; dom[0] = 5; dom[1] = 5
  forbid = i64[2*WASSAT_BLOCK_MAX_SIZE*2]
  a = 0
  while a <= 2
    b = 0
    while b <= 2
      unless allow_model && a == 2 && b == 0
        forbid[a*2+1] |= 1 << b
        forbid[(WASSAT_BLOCK_MAX_SIZE+b)*2] |= 1 << a
      b += 2
    a += 2
  sol = i64[2]; m = i64[24]
  hit = wassat_pattern_walk(2, dom, forbid, sol, m, true)
  [hit, sol[0], sol[1], m[7]]

describe "Signed-domain tabu trajectories" ->
  it "joins the workers and returns the model in the original value coordinates" ->
    result = pattern_walk_fixture(true)
    expect(result[0]).to eq(1)
    expect(result[1]).to eq(2)
    expect(result[2]).to eq(0)

  it "declines when every pair is excluded" ->
    result = pattern_walk_fixture(false)
    expect(result[0]).to eq(0)
    expect(result[3] > 0).to eq(true)

spec_summary
