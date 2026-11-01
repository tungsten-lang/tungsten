use spec
use ../lib/solver

# Independently derive the surviving trail and maximum-priority cursor from
# the suffix being removed. Equal stamps retain the old cursor, or the last
# variable on the original trail when a new maximum is first encountered.
-> check_backjump_cursor(stamps, levels, initial, target, chrono, present)
  tr = i64[10]; tlim = i64[4]; asg = i8[9]; lasg = i8[22]
  lvl = i64[9]; rsn = i32[9]; heap = i64[9]; hpos = i32[9]
  act = i64[9]; hst = i64[2]; vqs = i64[9]; vst = i64[5]
  kept = i64[10]; st = i64[4]
  tlim[1] = 3; tlim[2] = 6
  st[0] = 3; st[1] = 8; st[3] = 17; vst[3] = initial
  prefix = target == 3 ? 8 : target * 3
  expected = []
  removed = []
  v = 1
  while v <= 8
    lit = (v % 2) == 0 ? 0 - v : v
    tr[v - 1] = lit
    pol = lit > 0 ? 1 : -1
    asg[v] = pol; lasg[2 * v] = pol; lasg[2 * v + 1] = 0 - pol
    rsn[v] = v + 10; lvl[v] = levels[v]; vqs[v] = stamps[v]
    hpos[v] = -1
    act[v] = v
    z = wassat_heap_insert(heap, hpos, act, hst, v) if present
    if v <= prefix || (chrono == 1 && levels[v] <= target)
      expected.push(lit)
    else
      removed.push(v)
    v += 1
  want = initial
  maximum = stamps[initial]
  removed.each -> (v)
    maximum = stamps[v] if stamps[v] > maximum
  if maximum > stamps[initial]
    removed.each -> (v)
      want = v if stamps[v] == maximum
  wassat_backjump(tr, tlim, asg, lasg, lvl, rsn, heap, hpos, act,
    hst, vqs, vst, kept, st, target, chrono)
  expect(st[3]).to eq(17 + removed.size)
  expect(vst[3]).to eq(want)
  expect(st[0]).to eq(target)
  expect(st[1]).to eq(expected.size)
  expect(st[2]).to eq(prefix)
  expect(wassat_heap_valid(heap, hpos, act, hst, 8)).to eq(1)
  i = 0
  while i < expected.size
    expect(tr[i]).to eq(expected[i])
    i += 1
  v = 1
  while v <= 8
    cleared = removed.include?(v)
    pol = (v % 2) == 0 ? -1 : 1
    want_pol = cleared ? 0 : pol
    expect(asg[v]).to eq(want_pol)
    expect(lasg[2 * v]).to eq(want_pol)
    expect(lasg[2 * v + 1]).to eq(0 - want_pol)
    expect(rsn[v]).to eq(cleared ? -1 : v + 10)
    expect(vqs[v]).to eq(stamps[v])
    expect(lvl[v]).to eq(levels[v])
    expect(hpos[v] >= 0).to eq(present || cleared)
    v += 1
  # A no-op jump must not count the same removals twice.
  wassat_backjump(tr, tlim, asg, lasg, lvl, rsn, heap, hpos, act,
    hst, vqs, vst, kept, st, target, chrono)
  expect(st[3]).to eq(17 + removed.size)
  0

describe "Backjump cursor and unassignment accounting" ->
  it "preserves the highest timestamp, ties, chronology and heap membership" ->
    patterns = [[0, 8, 7, 6, 5, 4, 3, 2, 1],
      [0, 1, 2, 3, 4, 5, 6, 7, 8],
      [0, 1, 7, 1, 7, 1, 7, 1, 7],
      [0, 1099511627776, 2, 1099511627780, 3, 1099511627780, 5, 6, 7]]
    levels_set = [[0, 1, 1, 1, 2, 2, 2, 3, 3],
      [0, 0, 1, 1, 0, 1, 2, 1, 3]]
    patterns.each -> (stamps)
      levels_set.each -> (levels)
        [0, 3, 8].each -> (initial)
          [0, 1, 2, 3].each -> (target)
            [0, 1].each -> (chrono)
              [false, true].each -> (present)
                check_backjump_cursor(stamps, levels, initial, target, chrono, present)

spec_summary
