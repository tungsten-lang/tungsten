use spec
use ../lib/wassat

+ TrialFixture
  ro :base, :temp, :trail, :pos, :neg, :clauses, :packed

  -> new(nv, @clauses)
    @base = i8[nv + 1]
    @temp = i8[nv + 1]
    @trail = i64[nv + 1]
    @pos = []
    @neg = []
    v = 0
    while v <= nv
      @pos.push([])
      @neg.push([])
      v += 1
    ci = 0
    @clauses.each -> (c)
      c.each -> (l)
        if l > 0
          @pos[l].push(ci)
        else
          @neg[-l].push(ci)
      ci += 1
    @packed = wassat_struct_trial_pack(nv, @clauses)

  -> trial(assumptions, native, collect = true, chains = nil, owners = nil, positions = nil)
    wassat_struct_trial_propagate(@base, @temp, @trail, @pos, @neg, @clauses,
      assumptions, chains, owners, positions, native ? @packed : nil, collect)

  -> cleared?
    i = 0
    while i < @temp.size
      return false if @temp[i] != 0
      i += 1
    true

-> trial_compare(f, assumptions)
  a = f.trial(assumptions, false)
  expect(f.cleared?).to eq(true)
  b = f.trial(assumptions, true)
  expect(f.cleared?).to eq(true)
  expect(b.to_s).to eq(a.to_s)
  b

describe "Packed structural trial propagation" ->
  it "preserves ordered binary, ternary and quaternary implications" ->
    f = TrialFixture.new(7, [[-1, 2], [-2, 3], [-2, -3, 4], [-4, 5, 6, 7]])
    r = trial_compare(f, [1, -5, -6])
    expect(r[0]).to eq(1)
    expect(r[2].to_s).to eq([1, -5, -6, 2, 3, 4, 7].to_s)

  it "clears scratch after conflicting assumptions and propagated conflicts" ->
    f = TrialFixture.new(4, [[-1, 2], [-2, 3], [-3, -1]])
    expect(trial_compare(f, [1, -1])[0]).to eq(0)
    expect(trial_compare(f, [1])[0]).to eq(0)
    expect(trial_compare(f, [-1])[0]).to eq(1)

  it "preserves base assignments and duplicate literal behavior" ->
    f = TrialFixture.new(4, [[-1, 2, 2], [-2, 2], [-3, 4]])
    f.base[3] = 1
    trial_compare(f, [1, -2])
    expect(f.base[3]).to eq(1)
    trial_compare(f, [1, 1])
    trial_compare(f, [])

  it "omits unused implication copies without changing status or work" ->
    f = TrialFixture.new(4, [[-1, 2], [-2, 3], [-3, 4]])
    a = f.trial([1], true)
    work = f.packed[5]
    visits = work[3]
    inspections = work[4]
    b = f.trial([1], true, false)
    expect(b[0]).to eq(a[0])
    expect(b[1]).to eq(a[1])
    expect(b[2]).to eq(nil)
    expect(work[3]).to eq(visits * 2)
    expect(work[4]).to eq(inspections * 2)
    expect(work[6]).to eq(a[1])
    expect(f.cleared?).to eq(true)

  it "reuses the same packed arrays across alternating assumptions" ->
    f = TrialFixture.new(5, [[-1, 2], [-2, 3], [1, 4], [-4, 5]])
    i = 0
    while i < 24
      trial_compare(f, [i % 2 == 0 ? 1 : -1])
      i += 1
    expect(f.packed[5][2]).to eq(24)

  it "retains monotone-chain semantics even if a packed index is supplied" ->
    f = TrialFixture.new(4, [])
    owners = i64[5]
    positions = i64[5]
    i = 1
    while i <= 4
      owners[i] = 1
      positions[i] = i - 1
      i += 1
    a = f.trial([4], false, true, [[1, 2, 3, 4]], owners, positions)
    b = f.trial([4], true, true, [[1, 2, 3, 4]], owners, positions)
    expect(b.to_s).to eq(a.to_s)
    expect(b[1]).to eq(4)
    expect(f.packed[5][2]).to eq(0)
    expect(f.cleared?).to eq(true)

  it "retains the general path for larger assumption lists" ->
    f = TrialFixture.new(5, [[-1, 5]])
    trial_compare(f, [1, 2, 3, 4])
    expect(f.packed[5][2]).to eq(0)

  it "preserves the 2048-assignment cutoff and clears the entire trail" ->
    clauses = []
    i = 1
    while i < 2050
      clauses.push([-i, i + 1])
      i += 1
    f = TrialFixture.new(2050, clauses)
    r = trial_compare(f, [1])
    expect(r[0]).to eq(1)
    expect(r[1]).to eq(2048)
    expect(f.cleared?).to eq(true)

spec_summary
