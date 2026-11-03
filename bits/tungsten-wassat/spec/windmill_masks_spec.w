use spec
use ../lib/windmill

# Exercise the recovered-chain kernel directly with one pair. Keeping the
# fixture small lets the interpreter check the same 61-bit boundary without
# constructing a full sixty-row windmill and running its search portfolio.
-> windmill_mask_fixture(rows)
  nt = rows - 1
  guard = i64[2 * nt]
  pv = i64[nt]
  tv = i64[nt]
  lits = i64[8 * nt]
  offs = i64[3 * nt]
  lens = i64[3 * nt]
  vbase = 2 * nt + 1
  pbase = vbase + rows
  tbase = pbase + 2 * nt
  nv = tbase + 3 * nt - 1
  r = 0
  while r < nt
    a = 2 * r + 1
    b = a + 1
    v = vbase + r
    guard[2 * r] = a
    guard[2 * r + 1] = b
    pv[r] = pbase + 2 * r
    tv[r] = tbase + 3 * r
    pos = 8 * r
    offs[3 * r] = pos
    offs[3 * r + 1] = pos + 3
    offs[3 * r + 2] = pos + 6
    lens[3 * r] = 3
    lens[3 * r + 1] = 3
    lens[3 * r + 2] = 2
    lits[pos] = -a
    lits[pos + 1] = -b
    lits[pos + 2] = v
    lits[pos + 3] = -a
    lits[pos + 4] = -b
    lits[pos + 5] = -(v + 1)
    lits[pos + 6] = v
    lits[pos + 7] = -(v + 1)
    r += 1
  formula = { "nvars": nv, "flat_ncl": 3 * nt, "flat_nlits": 8 * nt,
    "flat_lits": lits, "flat_offs": offs, "flat_lens": lens }
  layout = { "cols": 2, "rows": rows, "sbase": nv + 1,
    "nmoves": nt - 1, "guard": guard, "pvar": pv, "tvar": tv }
  [formula, layout]

describe "Wassat wide pair-cut masks" ->
  it "preserves all 61 cut positions and both high membership masks" ->
    fixture = windmill_mask_fixture(60)
    info = wassat_windmill_recover_v(fixture[0], fixture[1])
    expect(info == nil).to eq(false)
    expect(info["npairs"]).to eq(1)
    expect(info["root_mask"][0]).to eq(2305843009213693951)
    off = info["pair_pc_off"]
    masks = info["pc_kill"]
    expect(off[1] - off[0]).to eq(118)
    expect(masks[off[1] - 2]).to eq(576460752303423487)
    expect(masks[off[1] - 1]).to eq(1152921504606846976)

  it "still rejects an incomplete wide chain and an unsupported row count" ->
    fixture = windmill_mask_fixture(60)
    fixture[0]["flat_lens"][89] = 1
    expect(wassat_windmill_recover_v(fixture[0], fixture[1]) == nil).to eq(true)
    fixture = windmill_mask_fixture(61)
    expect(wassat_windmill_recover_v(fixture[0], fixture[1]) == nil).to eq(true)

spec_summary
