use spec
use ../lib/pair_affine

-> pair_affine_formula(nv, cs)
  count = 0
  cs.each -> (c) count += c.size
  lits = i64[count]
  offs = i64[cs.size]
  lens = i64[cs.size]
  p = 0
  ci = 0
  cs.each -> (c)
    offs[ci] = p
    lens[ci] = c.size
    c.each -> (l)
      lits[p] = l
      p += 1
    ci += 1
  { "nvars": nv, "flat_ncl": ci, "flat_lits": lits,
    "flat_offs": offs, "flat_lens": lens }

# Encode (x1*x2 + a*x1 + b*x2) XOR x3 = rhs, then the same
# nonlinear atom XOR x4 = rhs XOR 1. Clauses/literals are reversed later.
-> pair_affine_fixture(signature, rhs)
  cs = []
  last = 3
  while last <= 4
    state = 0
    while state < 8
      a = state & 1
      b = (state >> 1) & 1
      c = (state >> 2) & 1
      value = (a & b) ^ ((signature & 1) & a) ^ (((signature >> 1) & 1) & b) ^ c
      if value != (rhs ^ (last - 3))
        cs.push([a == 1 ? -1 : 1, b == 1 ? -2 : 2, c == 1 ? -last : last])
      state += 1
    last += 1
  cs

-> pair_affine_checked(f, model)
  return false if model.size != f["nvars"]
  ci = 0
  while ci < f["flat_ncl"]
    sat = false
    j = 0
    while j < f["flat_lens"][ci]
      l = f["flat_lits"][f["flat_offs"][ci] + j]
      v = l < 0 ? -l : l
      sat = true if model[v - 1] == l
      j += 1
    return false unless sat
    ci += 1
  true

describe "Boolean pair-function affine model search" ->
  it "lifts all nonlinear pair signatures and both equation parities" ->
    signature = 0
    while signature < 4
      rhs = 0
      while rhs < 2
        f = pair_affine_formula(4, pair_affine_fixture(signature, rhs))
        r = wassat_pair_affine_model(f, i64[2])
        expect(r["meta"][0]).to eq(1)
        expect(r["meta"][2]).to eq(3)
        expect(r["meta"][3]).to eq(1)
        expect(r["meta"][4]).to eq(2)
        expect(pair_affine_checked(f, r["model"])).to eq(true)
        rhs += 1
      signature += 1

  it "handles clause/literal permutations and duplicate clauses" ->
    cs = pair_affine_fixture(3, 1)
    reversed = []
    i = cs.size - 1
    while i >= 0
      c = cs[i]
      reversed.push([c[2], c[1], c[0]])
      i -= 1
    reversed.push(reversed[0])
    f = pair_affine_formula(4, reversed)
    r = wassat_pair_affine_model(f, i64[2])
    expect(r["meta"][0]).to eq(1)
    expect(pair_affine_checked(f, r["model"])).to eq(true)

  it "declines incompatible pair functions without publishing UNSAT" ->
    cs = pair_affine_fixture(0, 0)
    other = pair_affine_fixture(1, 0)
    i = other.size / 2
    while i < other.size
      cs.push(other[i])
      i += 1
    r = wassat_pair_affine_model(pair_affine_formula(4, cs), i64[2])
    expect(r["meta"][0]).to eq(0)
    expect(r["model"].empty?).to eq(true)

  it "declines higher-degree relations and overlapping nonlinear pairs" ->
    cs = pair_affine_fixture(0, 0)
    cs.push([1, 2, 3])
    cs.push([1, 3, 4])
    r = wassat_pair_affine_model(pair_affine_formula(4, cs), i64[2])
    expect(r["meta"][0]).to eq(0)
    # A genuinely quadratic block with intersecting products x1*x2+x2*x3.
    cs = []
    state = 0
    while state < 8
      a = state & 1
      b = (state >> 1) & 1
      c = (state >> 2) & 1
      if ((a & b) ^ (b & c)) == 1
        cs.push([a == 1 ? -1 : 1, b == 1 ? -2 : 2, c == 1 ? -3 : 3])
      state += 1
    other = pair_affine_fixture(0, 0)
    i = other.size / 2
    while i < other.size
      cs.push(other[i])
      i += 1
    r = wassat_pair_affine_model(pair_affine_formula(4, cs), i64[2])
    expect(r["meta"][0]).to eq(0)

  it "returns a miss for an inconsistent reduced linear system" ->
    cs = pair_affine_fixture(0, 0)
    cs.push([-3, 4])
    cs.push([3, -4])
    r = wassat_pair_affine_model(pair_affine_formula(4, cs), i64[2])
    expect(r["meta"][3]).to eq(1)
    expect(r["meta"][0]).to eq(0)
    expect(r["model"].empty?).to eq(true)

  it "requires every original clause after lifting a candidate" ->
    f = pair_affine_formula(2, [[-1], [2]])
    columns = i32[3]
    columns[1] = 1
    columns[2] = 2
    solution = i8[2]
    solution[0] = 1
    solution[1] = 1
    meta = i64[11]
    z = wassat_pair_affine_lift(f["flat_lits"], f["flat_offs"], f["flat_lens"], 2, 2, i32[3], i8[3], columns, solution, i64[2], meta, i64[2], 0)
    expect(z).to eq(0)
    expect(meta[0]).to eq(0)

  it "honors cancellation, deadlines, and declared size bounds" ->
    f = pair_affine_formula(4, pair_affine_fixture(0, 1))
    stop = i64[2]
    z = wassat_stop_cancel(stop)
    r = wassat_pair_affine_model(f, stop)
    expect(r["meta"][10]).to eq(1)
    expect(r["meta"][5]).to eq(0)
    r = wassat_pair_affine_model(f, i64[2], clock_ms() - 1)
    expect(r["meta"][10]).to eq(2)
    f["nvars"] = 1025
    expect(wassat_pair_affine_model(f, i64[2])).to eq(nil)

spec_summary
