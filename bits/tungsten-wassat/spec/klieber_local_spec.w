# spec: compiled -- original-CNF replay uses native buffer ownership intrinsics
use spec
use ../lib/wassat

-> klieber_test_formula(p, bad_binary = false, negative = false)
  nv = 100
  cs = [[negative ? -nv : nv]]
  v = p + 1
  while v < nv
    cs.push([v, -1, -2])
    cs.push([-v, bad_binary && v == p + 1 ? -1 : 1])
    cs.push([-v, 2])
    v += 1
  a = negative ? 98 : -98
  b = negative ? 99 : -99
  c = negative ? 97 : -97
  cs.push([negative ? -nv : nv, a, b, c])
  cs.push([negative ? nv : -nv, -a])
  cs.push([negative ? nv : -nv, -b])
  cs.push([negative ? nv : -nv, -c])
  n = 0
  cs.each -> (c) n += c.size
  lits = i64[n]; offs = i64[cs.size]; lens = i64[cs.size]
  at = 0
  ci = 0
  cs.each -> (c)
    offs[ci] = at
    lens[ci] = c.size
    c.each -> (l)
      lits[at] = l
      at += 1
    ci += 1
  { "nvars": nv, "flat_ncl": cs.size, "flat_lits": lits,
    "flat_offs": offs, "flat_lens": lens }

describe "Bounded bit-parallel circuit model search" ->
  it "preserves the existing small-input search" ->
    [6, 24].each -> (p)
      f = klieber_test_formula(p)
      m = wassat_klieber_circuit_model(f)
      expect(m.size).to eq(100)
      expect(wassat_model_satisfies?(f, m)).to eq(true)

  it "finds and replays models at both new input-width boundaries" ->
    [25, 32].each -> (p)
      f = klieber_test_formula(p)
      m = wassat_klieber_circuit_model(f)
      expect(m.size).to eq(100)
      expect(wassat_model_satisfies?(f, m)).to eq(true)

  it "handles a negative sink unit and signed targets" ->
    f = klieber_test_formula(26, false, true)
    m = wassat_klieber_circuit_model(f)
    expect(m.size).to eq(100)
    expect(wassat_model_satisfies?(f, m)).to eq(true)

  it "rejects a candidate if an original gate clause was changed" ->
    # Shape and gate counts still match, but x1 AND x2 cannot satisfy the
    # altered binary clause. A circuit candidate alone is not a certificate.
    f = klieber_test_formula(26, true)
    expect(wassat_klieber_circuit_model(f).empty?).to eq(true)

  it "declines unsupported input width" ->
    expect(wassat_klieber_circuit_model(klieber_test_formula(33)).empty?).to eq(true)

spec_summary
