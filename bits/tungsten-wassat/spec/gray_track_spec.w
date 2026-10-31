use spec
use ../lib/gray_track

# Minimal sufficient clauses, with unused auxiliary capacity matching the
# supported generated layout. No distinct-word or symmetry axioms are needed.
-> gray_fixture(w, b)
  cs = []
  wb = w * b
  col = 0
  while col < b
    row = []
    shift = 0
    while shift < w
      row.push(wb + col * w + shift + 1)
      shift += 1
    cs.push(row)
    col += 1
  col = 1
  while col < b
    shift = 0
    while shift < w
      sel = wb + col * w + shift + 1
      t = 0
      while t < w
        x = t * b + 1
        y = ((t + shift) % w) * b + col + 1
        cs.push([-sel, x, -y])
        cs.push([-sel, -x, y])
        t += 1
      shift += 1
    col += 1
  t = 0
  while t < w
    flips = []
    col = 0
    while col < b
      x = t * b + col + 1
      y = ((t + 1) % w) * b + col + 1
      z = 2 * wb + t * b + col + 1
      cs.push([-z, -x, -y])
      cs.push([-z, x, y])
      cs.push([z, -x, y])
      cs.push([z, x, -y])
      flips.push(z)
      col += 1
    cs.push(flips)
    a = 0
    while a < b
      d = a + 1
      while d < b
        cs.push([-flips[a], -flips[d]])
        d += 1
      a += 1
    t += 1
  cs

-> gray_formula(w, b, cs)
  words = 0
  cs.each -> (c) words += c.size
  lits = i64[words]
  offs = i64[cs.size]
  lens = i64[cs.size]
  ci = 0
  p = 0
  cs.each -> (c)
    offs[ci] = p
    lens[ci] = c.size
    c.each -> (l)
      lits[p] = l
      p += 1
    ci += 1
  { "nvars": w * b * (w + b + 4) / 2,
    "flat_lits": lits, "flat_offs": offs, "flat_lens": lens,
    "flat_ncl": ci, "flat_nlits": words }

-> gray_result(w, b, cs)
  wassat_gray_track_refute(gray_formula(w, b, cs))[0]

describe "Single-track Gray-code counting certificate" ->
  it "refutes nondivisible lengths using every rotation and transition" ->
    [[3, 2], [5, 2], [6, 2], [5, 3], [7, 3], [8, 3]].each -> (shape)
      w = shape[0]
      b = shape[1]
      r = wassat_gray_track_refute(gray_formula(w, b, gray_fixture(w, b)))
      expect(r[0]).to eq(-1)
      expect(r[1]).to eq(w)
      expect(r[2]).to eq(b)
      expect(r[4]).to eq((b - 1) * w * w)
      expect(r[6]).to eq(w * b * (b - 1) / 2)

  it "uses the cached width to skip unrelated or divisible layouts" ->
    expect(wassat_gray_track_bits(27, 3)).to eq(2)
    expect(wassat_gray_track_bits(28, 3)).to eq(0)
    expect(wassat_gray_track_bits(40, 4)).to eq(0)
    expect(wassat_gray_track_bits(27, 2)).to eq(0)
    expect(wassat_gray_track_bits(262145, 42)).to eq(0)

  it "declines divisible lengths that admit cyclic tracks" ->
    [[4, 2], [6, 3], [8, 2], [8, 4]].each -> (shape)
      expect(gray_result(shape[0], shape[1], gray_fixture(shape[0], shape[1]))).to eq(0)

  it "requires each original clause in the minimal admitted fixture" ->
    original = gray_fixture(3, 2)
    omit = 0
    while omit < original.size
      cs = []
      i = 0
      while i < original.size
        cs.push(original[i]) if i != omit
        i += 1
      expect(gray_result(3, 2, cs)).to eq(0)
      omit += 1

  it "does not let duplicate clauses replace missing truth-table rows" ->
    cs = gray_fixture(3, 2)
    cs[21] = cs[20]
    expect(gray_result(3, 2, cs)).to eq(0)

  it "requires distinct selectors and distinct transition bits" ->
    cs = gray_fixture(3, 2)
    cs[1] = [10, 10, 12]
    expect(gray_result(3, 2, cs)).to eq(0)
    cs = gray_fixture(3, 2)
    cs[28] = [13, 13]
    expect(gray_result(3, 2, cs)).to eq(0)

  it "accepts reordered literals and clauses plus redundant clauses" ->
    original = gray_fixture(5, 2)
    cs = []
    i = original.size - 1
    while i >= 0
      c = []
      j = original[i].size - 1
      while j >= 0
        c.push(original[i][j])
        j -= 1
      cs.push(c)
      i -= 1
    cs.push([1, -1])
    cs.push(cs[0])
    expect(gray_result(5, 2, cs)).to eq(-1)

  it "bounds repeated failed admission attempts and counts their scans" ->
    cs = gray_fixture(3, 2)
    cs[21] = cs[20]
    10.times -> cs.push(cs[0])
    f = gray_formula(3, 2, cs)
    r = wassat_gray_track_refute(f)
    expect(r[0]).to eq(0)
    expect(r[7]).to eq(8)
    expect(r[3] >= 8 * f["flat_ncl"]).to eq(true)

  it "declines invalid or unsupported input metadata" ->
    expect(wassat_gray_track_refute(nil)[0]).to eq(0)
    f = gray_formula(3, 2, gray_fixture(3, 2))
    f["nvars"] = 262145
    expect(wassat_gray_track_refute(f)[0]).to eq(0)

spec_summary
