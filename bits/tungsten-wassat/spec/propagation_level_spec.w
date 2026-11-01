use spec
use ../lib/solver

# (-1 v 4 v -2 v 3) is unit under 1,2,-3. Exercise both watched-slot
# orientations and all relative levels of its three false antecedents.
-> propagated_level(trigger, second, third, current, chrono, flip, width = 4, positive_tail = false)
  ar = i64[6]
  wassat_hdr_put(ar, 0, 7, width)
  ar[1] = flip ? 4 : -1
  ar[2] = flip ? -1 : 4
  ar[3] = positive_tail ? 2 : -2
  ar[4] = 3
  asg = i8[5]
  asg[1] = 1
  asg[2] = positive_tail ? -1 : 1
  asg[3] = -1
  lasg = i8[12]
  lasg[2] = 1
  lasg[3] = -1
  lasg[4] = positive_tail ? -1 : 1
  lasg[5] = positive_tail ? 1 : -1
  lasg[6] = -1
  lasg[7] = 1
  lvl = i64[5]
  lvl[1] = trigger
  lvl[2] = second
  lvl[3] = third
  rsn = i32[5]
  phs = i8[5]
  wd = i64[48]
  wp = i64[16]
  ws = i64[12]
  ws[1] = 16
  wassat_ws_add(wd, wp, ws, 3, 1, 4)
  bd = i64[48]
  bp = i64[1]
  tr = i64[5]
  tr[0] = 1
  st = i64[12]
  st[1] = 1
  st[5] = chrono ? 1 : 0
  wassat_propagate(ar, asg, lasg, lvl, rsn, phs, wd, wp, ws, tr, st, current, bd, bp)
  [lvl[4], rsn[4], tr[1], st[2], asg[4]]

describe "Chronological implication levels" ->
  it "uses the maximum antecedent level in either watch orientation" ->
    [false, true].each -> (flip)
      [0, 1, 2].each -> (a)
        [0, 1, 2].each -> (b)
          [0, 1, 2].each -> (c)
            maximum = a
            maximum = b if b > maximum
            maximum = c if c > maximum
            expect(propagated_level(a, b, c, 2, true, flip)).to eq([maximum, 7, 4, -1, 1])

  it "handles ternary units with either orientation and tail polarity" ->
    [false, true].each -> (flip)
      [false, true].each -> (positive_tail)
        [0, 1, 2].each -> (a)
          [0, 1, 2].each -> (b)
            maximum = a > b ? a : b
            expect(propagated_level(a, b, 2, 2, true, flip, 3, positive_tail)).to eq([maximum, 7, 4, -1, 1])
    expect(propagated_level(0, 1, 0, 2, false, false, 3)).to eq([2, 7, 4, -1, 1])
    expect(propagated_level(0, 0, 0, 0, true, true, 3)).to eq([0, 7, 4, -1, 1])
    expect(propagated_level(1, 1024, 0, 1024, true, false, 3)).to eq([1024, 7, 4, -1, 1])

  it "preserves ordinary propagation and root-level implications" ->
    expect(propagated_level(0, 1, 0, 2, false, false)).to eq([2, 7, 4, -1, 1])
    expect(propagated_level(0, 0, 0, 0, true, true)).to eq([0, 7, 4, -1, 1])

  it "supports high levels introduced by empty assumption levels" ->
    expect(propagated_level(1024, 2, 3, 1024, true, false)).to eq([1024, 7, 4, -1, 1])
    expect(propagated_level(1, 1024, 3, 1024, true, true)).to eq([1024, 7, 4, -1, 1])
    expect(propagated_level(1, 2, 1000, 1024, true, false)).to eq([1000, 7, 4, -1, 1])


-> long_implication_level(width, trigger, current, high_tail, flip)
  ar = i64[width + 2]
  wassat_hdr_put(ar, 0, 7, width)
  ar[1] = flip ? -2 : 1
  ar[2] = flip ? 1 : -2
  asg = i8[width + 1]; lasg = i8[2 * width + 4]
  lvl = i64[width + 1]; rsn = i32[width + 1]; phs = i8[width + 1]
  v = 2
  while v <= width
    ar[v] = -v if v > 2
    asg[v] = 1
    lasg[2 * v] = 1; lasg[2 * v + 1] = -1
    lvl[v] = v == 2 ? trigger : 0
    v += 1
  lvl[width] = current if high_tail
  wd = i64[4 * (2 * width + 4)]; wp = i64[16]; ws = i64[12]
  ws[1] = 16
  wassat_ws_add(wd, wp, ws, 5, 1, 1)
  bd = i64[4 * (2 * width + 4)]; bp = i64[1]
  tr = i64[width + 1]; tr[0] = 2
  st = i64[12]; st[1] = 1; st[5] = 1
  wassat_propagate(ar, asg, lasg, lvl, rsn, phs, wd, wp, ws, tr, st, current, bd, bp)
  [lvl[1], rsn[1], tr[1], st[2], asg[1]]

describe "Bounded implication levels" ->
  it "uses a current-level trigger for clauses of any width" ->
    [3, 4, 7, 32, 65].each -> (width)
      [false, true].each -> (flip)
        expect(long_implication_level(width, 1024, 1024, false, flip)).to eq([1024, 7, 1, -1, 1])

  it "finds a later maximum when the trigger is lower" ->
    [3, 4, 7, 32, 65].each -> (width)
      [false, true].each -> (flip)
        expect(long_implication_level(width, 1, 1024, true, flip)).to eq([1024, 7, 1, -1, 1])
        expect(long_implication_level(width, 1, 1024, false, flip)).to eq([1, 7, 1, -1, 1])

  it "preserves root and wide integer levels" ->
    expect(long_implication_level(65, 0, 0, false, false)).to eq([0, 7, 1, -1, 1])
    expect(long_implication_level(65, 1099511627776, 1099511627776, false, true)).to eq([1099511627776, 7, 1, -1, 1])
    expect(long_implication_level(65, 1, 1099511627776, true, false)).to eq([1099511627776, 7, 1, -1, 1])

spec_summary
