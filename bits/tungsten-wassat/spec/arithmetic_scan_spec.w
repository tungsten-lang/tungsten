use spec
use ../lib/wassat

# Independent boxed oracle: repeatedly scan every clause to a fixpoint.
-> scan_oracle(rows, assign)
  changed = true
  while changed
    changed = false
    rows.each -> (row)
      safe = false
      free = 0
      last = -1
      j = 1
      while j < row.size
        v = row[j]
        if assign[v] < 0
          free += 1
          last = v
        elsif assign[v] != row[0]
          safe = true
        j += 1
      unless safe
        return 0 if free == 0
        if free == 1
          assign[last] = 1 - row[0]
          changed = true
  1

-> scan_native(rows, initial, seed, color, visits = 0)
  nv = initial.size
  ns = rows.size
  total = 0
  rows.each -> (row) total += row.size - 1
  off = i64[ns + 1]
  elem = i64[total]
  forbid = i8[ns]
  inc_off = i64[nv + 1]
  inc = i64[total]
  assign = i8[nv]
  i = 0
  while i < nv
    assign[i] = initial[i]
    i += 1
  si = 0
  pos = 0
  rows.each -> (row)
    off[si] = pos
    forbid[si] = row[0]
    j = 1
    while j < row.size
      elem[pos] = row[j]
      pos += 1
      j += 1
    si += 1
  off[ns] = pos
  pos = 0
  i = 0
  while i < nv
    inc_off[i] = pos
    si = 0
    while si < ns
      j = off[si]
      while j < off[si + 1]
        if elem[j] == i
          inc[pos] = si
          pos += 1
        j += 1
      si += 1
    i += 1
  inc_off[nv] = pos
  meta = i64[15]
  meta[6] = visits
  trail = i64[nv + 1]
  queue = i64[total + ns + 1]
  stamp = i64[ns]
  status = wassat_arith_propagate(assign, off, elem, forbid, inc_off, inc,
    trail, queue, stamp, meta, nv, ns, seed, color)
  [status, assign, meta]

describe "Arithmetic scope satisfaction scan" ->
  it "matches a global fixpoint oracle across partial assignments and polarities" ->
    graphs = [
      [[0, 0, 1], [1, 1, 2]],
      [[1, 0, 1, 2], [0, 0, 1, 2]],
      [[0, 0, 1], [0, 1, 2], [0, 0, 2], [1, 0, 1, 2]],
      [[1, 2, 0], [1, 2, 1], [0, 0, 1], [1, 2, 0]]
    ]
    checks = 0
    graphs.each -> (rows)
      code = 0
      while code < 27
        init = []
        n = code
        j = 0
        while j < 3
          init.push((n % 3) - 1)
          n = n / 3
          j += 1
        if scan_oracle(rows, init) == 1
          seed = 0
          while seed < 3
            color = 0
            while color < 2
              expected = [init[0], init[1], init[2]]
              want = 0
              if expected[seed] < 0 || expected[seed] == color
                expected[seed] = color
                want = scan_oracle(rows, expected)
              got = scan_native(rows, init, seed, color)
              expect(got[0]).to eq(want)
              if want == 1
                j = 0
                while j < 3
                  expect(got[1][j]).to eq(expected[j])
                  j += 1
              expect(got[2][5]).to eq(1)
              checks += 1
              color += 1
            seed += 1
        code += 1
    << "oracle configurations=[checks]"
    expect(checks > 100).to eq(true)

  it "stops at the first satisfying element of a long scope" ->
    row = [1]
    initial = []
    i = 0
    while i < 15
      row.push(i)
      initial.push(i == 0 ? 0 : -1)
      i += 1
    got = scan_native([row], initial, 14, 1)
    expect(got[0]).to eq(1)
    expect(got[2][6]).to eq(1)
    expect(got[2][7]).to eq(1)
    expect(got[2][9]).to eq(1)

  it "still reads every element needed to force the last free color" ->
    row = [1]
    initial = []
    i = 0
    while i < 15
      row.push(i)
      initial.push(i < 13 ? 1 : -1)
      i += 1
    got = scan_native([row], initial, 13, 1)
    expect(got[0]).to eq(1)
    expect(got[1][14]).to eq(0)
    expect(got[2][8]).to eq(1)
    expect(got[2][7]).to eq(30)

  it "resumes queued implications across a batch boundary without repeating visits" ->
    start = 32765
    while start <= 32767
      got = scan_native([[0, 0, 1], [0, 1, 2]], [-1, -1, -1], 0, 0, start)
      expect(got[0]).to eq(1)
      expect(got[1][0]).to eq(0)
      expect(got[1][1]).to eq(1)
      expect(got[1][2]).to eq(-1)
      expect(got[2][6]).to eq(start + 3)
      expect(got[2][8]).to eq(1)
      expect(got[2][14]).to eq(start == 32765 ? 1 : 2)
      start += 1

spec_summary
