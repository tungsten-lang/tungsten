use spec
use ../lib/box_net_decode
use box_net_support

describe "Wassat common-net scratch reuse" ->
  it "preserves the bijection and both anchors while constructing fresh paths" ->
    formula = box_net_fixture_flat(box_net_fixture_clauses,false)
    stop = i64[2]
    decoded = wassat_box_net_decode(formula,stop,0,i64[32])
    state = decoded["state"]
    geometry = decoded["geometry"]
    scratch = i64[4096]
    rng = u64[3]
    rng[0] = 712837
    state[30] = 1
    candidate = wassat_box_net_search(geometry,scratch,state,rng,stop,0,512)
    expect(state[25]).to eq(0)
    expect(state[9] < 1000000).to eq(true)
    expect(state[8] <= 512).to eq(true)
    expect(state[8]).to eq(state[27]+state[28])
    expect(state[26] > 0).to eq(true)
    expect(state[29] >= state[26]).to eq(true)
    seen = i8[10]
    i = 0
    while i < 10
      v = scratch[192+i]
      expect(v >= 0 && v < 10).to eq(true)
      if v >= 0 && v < 10
        expect(seen[v]).to eq(0)
        seen[v] = 1
      expect(scratch[256+i] >= 0 && scratch[256+i] < 4).to eq(true)
      i += 1
    expect(scratch[192]).to eq(0)
    expect(scratch[193]).to eq(1)
    expect(scratch[256]).to eq(0)
    if candidate == 1
      expect(state[18]).to eq(1)
      expect(state[19]+state[20]+state[21]+state[22]).to eq(0)

  it "resolves coordinate collisions and restores the older branch entries" ->
    scratch = i64[4096]
    # These three distinct coordinates all hash to bucket zero.
    scratch[2112] = 0; scratch[2176] = 0
    scratch[2113] = 1; scratch[2177] = 23
    scratch[2114] = -1; scratch[2178] = -23
    scratch[2560] = 3
    scratch[2688] = 0; scratch[2689] = 1; scratch[2690] = 2
    expect(wassat_box_net_path_find(scratch,0,0)).to eq(0)
    expect(wassat_box_net_path_find(scratch,1,23)).to eq(1)
    expect(wassat_box_net_path_find(scratch,-1,-23)).to eq(2)
    expect(wassat_box_net_path_find(scratch,2,46)).to eq(-1)
    # Backtracking removes the deepest entry, not the whole bucket.
    scratch[2560] = scratch[2690]
    expect(wassat_box_net_path_find(scratch,-1,-23)).to eq(-1)
    expect(wassat_box_net_path_find(scratch,1,23)).to eq(1)
    expect(wassat_box_net_path_find(scratch,0,0)).to eq(0)
    scratch[2560] = scratch[2689]
    expect(wassat_box_net_path_find(scratch,1,23)).to eq(-1)
    expect(wassat_box_net_path_find(scratch,0,0)).to eq(0)
    scratch[2560] = scratch[2688]
    expect(wassat_box_net_path_find(scratch,0,0)).to eq(-1)
    expect(scratch[2752]).to eq(10)
    expect(scratch[2753] >= 10).to eq(true)

spec_summary
