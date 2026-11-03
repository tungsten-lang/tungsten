use spec
use ../lib/box_net_decode
use box_net_support

describe "Wassat original-CNF common-net proposals" ->
  it "recovers two surfaces and input anchors without benchmark metadata" ->
    f = box_net_fixture_flat(box_net_fixture_clauses,false)
    dm = i64[32]
    decoded = wassat_box_net_decode(f,i64[2],0,dm)
    expect(decoded == nil).to eq(false)
    expect(decoded["state"][0]).to eq(10)
    expect(decoded["state"][1]).to eq(0)
    expect(decoded["state"][2]).to eq(1)
    expect(dm[4]).to eq(1600)
    expect(dm[5]).to eq(4800)
    expect(decoded["geometry"][0]).to eq(8)
    expect(decoded["geometry"][1]).to eq(3)

  it "recovers arbitrary variable labels" ->
    f = box_net_fixture_flat(box_net_fixture_clauses,true)
    decoded = wassat_box_net_decode(f,i64[2],0,i64[32])
    expect(decoded == nil).to eq(false)
    expect(decoded["mapping"][0]).to eq((121*7) % 461)
    expect(decoded["rotation"][0]).to eq((221*7) % 461)

  it "declines a missing rotation implication and duplicate row incidence" ->
    cs = box_net_fixture_clauses
    filtered = []
    removed = false
    cs.each -> (c)
      if !removed && c.size == 4 && c[0] == -121 && c[3] == 221
        removed = true
      else
        filtered.push(c)
    expect(removed).to eq(true)
    expect(wassat_box_net_decode(box_net_fixture_flat(filtered,false),i64[2],0,i64[32]) == nil).to eq(true)
    damaged = false
    cs.each -> (c)
      if !damaged && c.size == 10
        c[1] = c[0]
        damaged = true
    expect(wassat_box_net_decode(box_net_fixture_flat(cs,false),i64[2],0,i64[32]) == nil).to eq(true)

  it "honors prepublished cancellation before decoding" ->
    stop = i64[2]
    z = wassat_stop_cancel(stop)
    dm = i64[32]
    f = box_net_fixture_flat(box_net_fixture_clauses,false)
    expect(wassat_box_net_decode(f,stop,0,dm) == nil).to eq(true)
    expect(dm[7]).to eq(1)

  it "keeps high visited bits in their own surface and toggles them exactly" ->
    bits = u64[3]
    z = wassat_box_net_single(bits,1,63)
    expect(wassat_box_net_has(bits,1,63)).to eq(1)
    expect(wassat_box_net_has(bits,2,63)).to eq(0)
    z = wassat_box_net_toggle(bits,1,63)
    expect(wassat_box_net_has(bits,1,63)).to eq(0)

  it "checks every original clause, including extra constraints" ->
    cs = box_net_fixture_clauses
    f = box_net_fixture_flat(cs,false)
    values = i8[461]
    b = 0
    while b < 2
      e = 0
      while e < 20
        values[b*60+1+e] = 1
        e += 1
      i = 0
      while i < 10
        values[b*60+21+4*i] = 1
        i += 1
      b += 1
    i = 0
    while i < 10
      values[121+11*i] = 1
      values[221+4*i] = 1
      i += 1
    p = i64[32]
    expect(wassat_box_net_replay(f["flat_lits"],f["flat_offs"],f["flat_lens"],460,f["flat_ncl"],values,p,i64[2],clock_ms()+100000)).to eq(1)
    expect(p[10]).to eq(f["flat_ncl"])
    cs.push([-121])
    bad = box_net_fixture_flat(cs,false)
    expect(wassat_box_net_replay(bad["flat_lits"],bad["flat_offs"],bad["flat_lens"],460,bad["flat_ncl"],values,i64[32],i64[2],clock_ms()+100000)).to eq(0)

spec_summary
