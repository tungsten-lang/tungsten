# spec: compiled -- full CDCL integration; box_net_spec.w covers interpreter parity
use spec
use ../lib/wassat
use box_net_support

-> box_net_fixture_identity
  state = i64[4096]
  i = 0
  while i < 10
    state[192+i] = i
    i += 1
  state

describe "Wassat common-net original-formula completion" ->
  it "completes the proposal and checks all original clauses before copying a model" ->
    f = box_net_fixture_flat(box_net_fixture_clauses,false)
    stop = i64[2]
    decoded = wassat_box_net_decode(f,stop,0,i64[32])
    meta = i64[32]
    out = i64[468]
    hit = wassat_box_net_complete(f,decoded,box_net_fixture_identity,meta,stop,out,0,clock_ms()+10000)
    expect(hit).to eq(1)
    expect(meta[10]).to eq(f["flat_ncl"])
    expect(meta[9]).to eq(0)
    expect(wassat_stop_status(stop)).to eq(0)
    model = []
    i = 1
    while i <= 460
      model.push(out[i] == 1 ? i : -i)
      i += 1
    expect(wassat_model_satisfies?(f,model)).to eq(true)

  it "does not publish UNSAT when a proposal contradicts a satisfiable input" ->
    f = box_net_fixture_flat(box_net_fixture_clauses,false)
    stop = i64[2]
    decoded = wassat_box_net_decode(f,stop,0,i64[32])
    state = box_net_fixture_identity
    state[192] = 1
    state[193] = 0
    meta = i64[32]
    out = i64[468]
    hit = wassat_box_net_complete(f,decoded,state,meta,stop,out,0,clock_ms()+10000)
    expect(hit).to eq(0)
    expect(wassat_stop_load(stop)).to eq(0)
    expect(wassat_stop_status(stop)).to eq(0)
    expect(out[0]).to eq(0)
    expect(meta[10]).to eq(0)

  it "rejects an extra original constraint outside the recovered geometry" ->
    cs = box_net_fixture_clauses
    cs.push([-121])
    f = box_net_fixture_flat(cs,false)
    stop = i64[2]
    decoded = wassat_box_net_decode(f,stop,0,i64[32])
    expect(decoded == nil).to eq(false)
    out = i64[468]
    hit = wassat_box_net_complete(f,decoded,box_net_fixture_identity,i64[32],stop,out,0,clock_ms()+10000)
    expect(hit).to eq(0)
    expect(wassat_stop_load(stop)).to eq(0)
    expect(out[0]).to eq(0)

  it "abandons completion when another arm has already requested cancellation" ->
    f = box_net_fixture_flat(box_net_fixture_clauses,false)
    stop = i64[2]
    decoded = wassat_box_net_decode(f,stop,0,i64[32])
    z = wassat_stop_cancel(stop)
    out = i64[468]
    hit = wassat_box_net_complete(f,decoded,box_net_fixture_identity,i64[32],stop,out,0,clock_ms()+10000)
    expect(hit).to eq(0)
    expect(wassat_stop_status(stop)).to eq(0)
    expect(out[0]).to eq(0)

spec_summary
