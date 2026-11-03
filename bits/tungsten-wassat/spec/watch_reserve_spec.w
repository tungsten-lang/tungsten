use spec
use ../lib/policy

-> reserve_config(nv, nc, units, binary, empty = 0)
  counts = i64[8]
  counts[0] = 3 * (nc - units - binary - empty) + units + 2 * binary
  counts[1] = 3
  counts[2] = units
  counts[3] = binary
  counts[4] = nc - units - binary - empty
  counts[5] = empty
  c = WassatConfig.new(nv, [])
  c.adopt_counts(nc, counts)
  c

describe "Large raw watch reserve policy" ->
  it "counts long clauses rather than every database entry" ->
    expect(reserve_config(500000, 8000000, 4000000, 1000000).watch_extra_percent).to eq(0)
    expect(reserve_config(500000, 8000000, 1000000, 1000000).watch_extra_percent).to eq(25)

  it "leaves small, sparse and already dense watch databases alone" ->
    expect(wassat_watch_reserve_percent(100000, 3999999, 3999999)).to eq(0)
    expect(wassat_watch_reserve_percent(1000000, 8000000, 7999999)).to eq(0)
    expect(wassat_watch_reserve_percent(100000, 6400000, 6400000)).to eq(0)
    expect(wassat_watch_reserve_percent(2000000, 40000000, 30000000)).to eq(0)

  it "admits the moderate-density boundaries" ->
    expect(wassat_watch_reserve_percent(500000, 4000000, 4000000)).to eq(25)
    expect(wassat_watch_reserve_percent(100000, 6400000, 6399999)).to eq(25)

  it "does not mistake empty clauses for watched clauses" ->
    expect(reserve_config(500000, 4000000, 0, 0, 1).watch_extra_percent).to eq(0)

  it "keeps boxed and flat shape accounting consistent" ->
    rows = [[], [1], [1, 2], [1, 2, 3], [-1, -2, -3, 4]]
    lens = i64[5]
    i = 0
    while i < rows.size
      lens[i] = rows[i].size
      i += 1
    a = WassatConfig.new(4, rows)
    b = WassatConfig.from_lens(4, lens, rows.size)
    expect(a.watch_extra_percent).to eq(b.watch_extra_percent)
    expect(a.empty_clause_count).to eq(b.empty_clause_count)

  it "keeps the measured reserve below the existing table-growth bound" ->
    nv = 445862
    maxcl = 8473162
    capacity = 2 * maxcl + 4 * nv + 72
    expanded = wassat_watch_reserve_capacity(capacity, 25)
    expect(expanded > capacity).to eq(true)
    expect(expanded < 4 * maxcl + 4 * nv + 72).to eq(true)
    expect(wassat_watch_reserve_capacity(capacity, 0)).to eq(capacity)

spec_summary
