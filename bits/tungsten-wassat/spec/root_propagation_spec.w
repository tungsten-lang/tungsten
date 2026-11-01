use spec
use ../lib/solver
use ../lib/preprocess

+ RootPropagationFixture < WassatPreprocess
  -> scan(clauses, assumptions)
    clauses.each -> (c)
      self.store(c)
    assumptions.each -> (l)
      self.assign(l, -1)
    @pst[1] = @ftsize
    wassat_pre_prop(@fla, @fcs, @fcl, @falive, @ftaut, @oh, @on, @ov,
                    @passign, @preason, @tpos, @ftrail, @pst)
    signs = []; trail = []; reasons = []
    v = 0
    while v <= @nvars
      signs.push(@passign[v])
      v += 1
    i = 0
    while i < @pst[1]
      l = @ftrail[i]
      trail.push(l)
      reasons.push(@preason[l < 0 ? -l : l])
      i += 1
    [signs, trail, reasons, @pst[2], @pst[3], @pst[4], @pst[6]]

-> root_literal_value(signs, l)
  l > 0 ? signs[l] : -signs[-l]

# Check each implication directly against its original reason clause, then
# enumerate the small original formula to ensure no satisfying model was
# removed. This oracle does not use occurrence lists or the native scan.
-> check_root_scan(nv, cs, assumptions)
  s = RootPropagationFixture.new(nv, cs, WASSAT_PROOF_NONE, nil)
  r = s.scan(cs, assumptions)
  signs = []
  (nv + 1).times ->
    signs.push(0)
  assumptions.each -> (l)
    signs[l < 0 ? -l : l] = l > 0 ? 1 : -1
  i = assumptions.size
  while i < r[1].size
    l = r[1][i]
    reason = cs[r[2][i]]
    found = false
    reason.each -> (a)
      if a == l
        found = true
      else
        expect(root_literal_value(signs, a)).to eq(-1)
    expect(found).to eq(true)
    expect(root_literal_value(signs, l)).to eq(0)
    signs[l < 0 ? -l : l] = l > 0 ? 1 : -1
    i += 1
  expect(signs).to eq(r[0])
  expect(r[5] <= r[4]).to eq(true)
  models = 0
  mask = 0
  while mask < (1 << nv)
    model = [0]
    v = 1
    while v <= nv
      model.push((mask & (1 << (v - 1))) != 0 ? 1 : -1)
      v += 1
    valid = true
    assumptions.each -> (l)
      valid = false if root_literal_value(model, l) != 1
    cs.each -> (c)
      hit = false
      c.each -> (l)
        hit = true if root_literal_value(model, l) == 1
      valid = false unless hit
    if valid
      models += 1
      r[1].each -> (l)
        expect(root_literal_value(model, l)).to eq(1)
    mask += 1
  if r[3] >= 0
    expect(models).to eq(0)
    cs[r[3]].each -> (l)
      expect(root_literal_value(signs, l)).to eq(-1)
  else
    cs.each -> (c)
      hit = false
      open = []
      c.each -> (l)
        value = root_literal_value(signs, l)
        hit = true if value == 1
        open.push(l) if value == 0
      expect(hit || open.size >= 2).to eq(true)
  r

describe "Root propagation scan bounds" ->
  it "stops at two open literals and revisits after implications" ->
    r = check_root_scan(5, [[-1, -2], [-1, -3], [-1, 2, 3, 4], [-4, 5]], [1])
    expect(r[6] > 0).to eq(true)
    expect(r[5] < r[4]).to eq(true)

  it "preserves conflicts after skipping a non-unit clause" ->
    r = check_root_scan(5, [[-1, -2], [-1, -3], [-1, 2, 3, 4], [-4, 5]], [1, -4])
    expect(r[6] > 0).to eq(true)
    expect(r[3] >= 0).to eq(true)

  it "preserves all models and valid reasons for every partial assignment" ->
    flips = 0
    while flips < 8
      cs = []
      [[1, 2, 3], [-1, 2, -3], [1, -2, 3], [-1, -2, -3]].each -> (clause)
        c = []
        clause.each -> (l)
          v = l < 0 ? -l : l
          c.push((flips & (1 << (v - 1))) == 0 ? l : -l)
        cs.push(c)
      pattern = 0
      while pattern < 27
        assumptions = []
        code = pattern
        v = 1
        while v <= 3
          digit = code % 3
          assumptions.push(digit == 1 ? v : -v) if digit != 0
          code = code / 3
          v += 1
        check_root_scan(3, cs, assumptions)
        pattern += 1
      flips += 1

  it "handles duplicate literals, tautologies and satisfied tails" ->
    check_root_scan(5, [[-1, 2, 2], [-1, 2, -2], [-1, 2, 3, 4], [-3, 5]], [1, 4])
    check_root_scan(5, [[-1, -2, -3, 4, 5], [-4, 5]], [1, 2, 3, 5])

spec_summary
