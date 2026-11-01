use spec
use ../lib/solver

# Two surviving clauses separated by dead input slots. Moving the first
# survivor overlaps its old body, so retaining literal order matters.
-> reduction_storage_fixture(remap)
  cm = i64[8]
  alive = i8[4]
  ar = i64[12]
  lbd = i64[4]
  used = i64[4]
  gid = remap ? i64[4] : i64[1]
  rsn = i32[5]
  state = i64[70]
  cm[0] = 1
  cm[1] = 1
  cm[2] = 3
  cm[3] = 4
  cm[4] = 8
  cm[5] = 1
  cm[6] = 10
  cm[7] = 2
  ar[0] = 1
  ar[1] = -1
  ar[2] = 4294967300
  ar[3] = 1
  ar[4] = 2
  ar[5] = 3
  ar[6] = 4
  ar[7] = 8589934593
  ar[8] = 2
  ar[9] = 12884901890
  ar[10] = -3
  ar[11] = 4
  alive[1] = 1
  alive[3] = 1
  lbd[1] = 4
  lbd[3] = 8
  used[1] = 41
  used[3] = 43
  gid[0] = 77
  rsn[0] = -1
  rsn[1] = 1
  rsn[2] = 3
  rsn[3] = 2
  rsn[4] = -1
  [cm, alive, ar, lbd, used, gid, rsn, state]

describe "Wassat reduction storage" ->
  it "retains ordered clause bodies and remaps root reasons through dead slots" ->
    f = reduction_storage_fixture(true)
    wassat_reduce_compact(f[0], f[1], f[2], f[3], f[4], f[5], f[6], f[7], 4, 4, 1)
    cm = f[0]
    ar = f[2]
    expect([cm[0], cm[1], cm[2], cm[3]]).to eq([1, 4, 6, 2])
    expect([ar[0], ar[1], ar[2], ar[3], ar[4], ar[5], ar[6], ar[7]]).to eq([4, 1, 2, 3, 4, 4294967298, -3, 4])
    expect([f[5][0], f[5][1], f[5][2], f[5][3]]).to eq([-1, 0, -1, 1])
    expect([f[6][1], f[6][2], f[6][3], f[6][4]]).to eq([0, 1, -1, -1])
    expect([f[3][0], f[3][1], f[4][0], f[4][1]]).to eq([4, 8, 41, 43])
    expect([f[7][64], f[7][65], f[7][66], f[7][67], f[7][68], f[7][69]]).to eq([8, 2, 12, 8, 2, 3])

  it "keeps clause indices and reasons when the map is a one-word sentinel" ->
    f = reduction_storage_fixture(false)
    wassat_reduce_compact(f[0], f[1], f[2], f[3], f[4], f[5], f[6], f[7], 4, 4, 0)
    expect([f[0][1], f[0][2], f[0][3], f[0][5], f[0][6], f[0][7]]).to eq([0, 1, 4, 0, 6, 2])
    expect([f[2][0], f[2][5]]).to eq([4294967300, 12884901890])
    expect([f[6][1], f[6][2], f[6][3], f[6][4], f[5][0]]).to eq([1, 3, 2, -1, 77])
    expect([f[7][64], f[7][65], f[7][66], f[7][67], f[7][68], f[7][69]]).to eq([8, 4, 4, 8, 0, 0])

  it "protects originals, binary clauses, low glue and recently used tier two" ->
    cm = i64[16]
    alive = i8[8]
    lbd = i64[8]
    used = i64[8]
    hist = i64[70]
    glues = [0, 2, 4, 6, 6, 8, 70, 100]
    i = 0
    while i < 8
      cm[2 * i + 1] = 3
      alive[i] = 1
      lbd[i] = glues[i]
      i += 1
    cm[11] = 2
    alive[7] = 0
    used[3] = 9
    used[4] = 10
    hist[66] = 100
    hist[69] = 7
    wassat_reduce_select(cm, alive, lbd, used, hist, 8, 10)
    expect([alive[0], alive[1], alive[2], alive[3], alive[4], alive[5], alive[6], alive[7]]).to eq([1, 1, 1, 0, 1, 1, 0, 0])
    expect([hist[2], hist[4], hist[6], hist[8], hist[63]]).to eq([1, 1, 2, 1, 1])
    expect([hist[66], hist[69]]).to eq([116, 7])

  it "handles an empty database without consuming sentinel entries" ->
    cm = i64[1]
    alive = i8[1]
    ar = i64[1]
    lbd = i64[1]
    used = i64[1]
    gid = i64[1]
    rsn = i32[1]
    state = i64[70]
    gid[0] = 77
    wassat_reduce_select(cm, alive, lbd, used, state, 0, 0)
    wassat_reduce_compact(cm, alive, ar, lbd, used, gid, rsn, state, 0, 0, 1)
    expect([state[64], state[65], state[66], state[67], state[68], state[69], gid[0]]).to eq([0, 0, 0, 0, 0, 0, 77])

spec_summary
