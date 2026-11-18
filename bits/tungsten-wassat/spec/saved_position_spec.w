use spec
use ../lib/solver

# One long clause (-1 v 2 v ... v width), with a synthetic high clause ID.
# All tail literals are false except the two optional free positions. Keep
# packed headers inside native integers, as in production propagation.
-> scan_position_probe(width, pos, first, second, other, enabled) (i64 i64 i64 i64 i64 i64) i64[]
  ar = i32[width + 2]
  cid = 2147483647
  wassat_hdr_put(ar, 0, cid, width)
  if pos > 0
    ar[1] = 2147483648 | (pos << 15) | width
  asg = i8[width + 1]; lasg = i8[2 * width + 4]
  lvl = i64[width + 1]; rsn = i32[width + 2]; phs = i8[width + 1]
  i = 1
  while i <= width
    ar[i + 1] = i
    asg[i] = -1
    asg[i] = 0 if i - 1 == first || i - 1 == second
    lasg[2 * i] = asg[i]
    lasg[2 * i + 1] = 0 - asg[i]
    i += 1
  ar[2] = -1
  asg[1] = 1; lasg[2] = 1; lasg[3] = -1
  asg[2] = other; lasg[4] = other; lasg[5] = 0 - other
  wd = i64[4 * (2 * width + 4)]; wp = i64[16]; ws = i64[14]
  ws[1] = 16
  wassat_ws_add(wd, wp, ws, 3, 2, 2)
  bd = i64[4 * (2 * width + 4)]; bp = i64[1]
  tr = i32[width + 2]; tr[0] = 1
  st = i64[14]; st[1] = 1; st[13] = enabled
  wassat_propagate(ar, asg, lasg, lvl, rsn, phs, wd, wp, ws, tr, st, 1, bd, bp)
  out = i64[7]
  out[0] = ar[3]
  out[1] = ar[0]
  out[2] = ar[1] & 4294967295
  out[3] = st[2]
  out[4] = asg[2]
  out[5] = rsn[2]
  out[6] = st[1]
  out

describe "Saved clause replacement positions" ->
  it "searches the suffix before wrapping to a free prefix literal" ->
    r = scan_position_probe(9, 5, 3, 7, -1, 1)
    expect(r[0]).to eq(8)
    expect(r[1]).to eq(2147483647)
    expect(r[2]).to eq(2147483648 + 7 * 32768 + 9)
    r = scan_position_probe(9, 6, 3, -1, -1, 1)
    expect(r[0]).to eq(4)
    expect(r[2]).to eq(2147483648 + 3 * 32768 + 9)

  it "finds units and conflicts after scanning both parts of the clause" ->
    r = scan_position_probe(9, 6, -1, -1, 0, 1)
    expect(r[3]).to eq(-1)
    expect(r[4]).to eq(1)
    expect(r[5]).to eq(2147483647)
    expect(r[6]).to eq(2)
    r = scan_position_probe(9, 6, -1, -1, -1, 1)
    expect(r[3]).to eq(2147483647)
    expect(r[6]).to eq(1)

  it "saves only encodable long-clause positions" ->
    [8, 9, 32767, 32768].each -> (width)
      r = scan_position_probe(width, 0, width - 1, -1, -1, 1)
      expect(r[0]).to eq(width)
      expect(r[1]).to eq(2147483647)
      expected = width
      expected += 2147483648 + (width - 1) * 32768 if width > 8 && width < 32768
      expect(r[2]).to eq(expected)

  it "keeps plain headers when saving is disabled" ->
    r = scan_position_probe(9, 0, 7, -1, -1, 0)
    expect(r[0]).to eq(8)
    expect(r[2]).to eq(9)

spec_summary
