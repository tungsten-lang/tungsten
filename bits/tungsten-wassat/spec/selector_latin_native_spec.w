# spec: compiled -- exhaustive 7! line enumeration exceeds the interpreter fixture budget
use spec
use ../lib/wassat

-> selector_fixture(mode)
  clauses = []
  cell = 0
  while cell < 49
    alo = []
    v = 0
    while v < 7
      alo.push(cell * 7 + v + 1)
      w = v + 1
      while w < 7
        clauses.push([0 - (cell * 7 + v + 1), 0 - (cell * 7 + w + 1)]) unless mode == 3 && cell == 0 && v == 0 && w == 1
        w += 1
      v += 1
    clauses.push(alo)
    cell += 1
  axis = 0
  nv = 343
  while axis < 2
    line = 0
    while line < 7
      v = 0
      while v < 7
        alo = []
        pos = 0
        while pos < 7
          cell = axis == 0 ? line * 7 + pos : pos * 7 + line
          alo.push(cell * 7 + v + 1)
          pos += 1
        clauses.push(alo)
        v += 1
      nv += 1
      pos = 0
      while pos < 7
        row = axis == 0 ? line : pos
        col = axis == 0 ? pos : line
        cell = row * 7 + col
        clauses.push([nv, cell * 7 + (row + col) % 7 + 1])
        clauses.push([0 - nv, cell * 7 + (row + col + 1) % 7 + 1])
        pos += 1
      line += 1
    axis += 1
  clauses.push([-1, -59]) if mode == 1 || mode == 2
  clauses.push([-2, -60]) if mode == 2
  nc = clauses.size
  offs = i64[nc]; lens = i64[nc]; lits = i64[nc * 7]
  used = 0
  i = 0
  while i < nc
    offs[i] = used
    lens[i] = clauses[i].size
    clauses[i].each -> (l)
      lits[used] = l
      used += 1
    i += 1
  m = i64[64]
  hit = wassat_selector_latin_run(lits, offs, lens, nv, nc, m, i64[4], clock_ms() + 5000, 10000)
  [hit, m]

describe "selector Latin recognition from clauses" ->
  it "leaves a satisfiable complete relation to the solving arms" ->
    r = selector_fixture(0)
    expect(r[0]).to eq(0)
    expect(r[1][41]).to eq(1)
    expect(r[1][23]).to eq(49)
  it "searches an asymmetric satisfiable relation without symmetry pruning" ->
    r = selector_fixture(1)
    expect(r[0]).to eq(0)
    expect(r[1][41]).to eq(1)
    expect(r[1][48]).to eq(0)
  it "refutes both remaining exact alternatives" ->
    r = selector_fixture(2)
    expect(r[0]).to eq(1)
    expect(r[1][41]).to eq(-1)
  it "declines incomplete exact-one evidence" ->
    r = selector_fixture(3)
    expect(r[0]).to eq(0)
    expect(r[1][40] < 8).to eq(true)
spec_summary
