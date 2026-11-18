use spec
use ../lib/query_storage

describe "Private assumption-query storage" ->
  it "tracks fresh packed buffers and closes exactly once" ->
    owner = wassat_query_storage()
    a = wassat_query_i64(owner, 7); b = wassat_query_i32(owner, 5)
    c = wassat_query_i8(owner, 3); d = wassat_query_u8(owner, 2)
    a[6] = 9; b[4] = -3; c[2] = -1; d[1] = 255
    expect([a[6], b[4], c[2], d[1]]).to eq([9, -3, -1, 255])
    expect(owner.state[1]).to eq(81)
    expect(owner.retention_bytes > owner.state[1]).to eq(true)
    z = wassat_query_release(owner)
    expect(owner.state[0]).to eq(1)
    expect(owner.state[2]).to eq(4)
    expect(owner.retention_bytes).to eq(0)
    z = wassat_query_release(owner)
    expect(owner.state[2]).to eq(4)

  it "keeps borrowed cells and detached values alive after release" ->
    owner = wassat_query_storage()
    borrowed = i64[2]; borrowed[0] = 13
    owned = wassat_query_i64(owner, 2); owned[0] = 29
    detached = [owned[0]]
    z = wassat_query_release(owner)
    expect(borrowed[0]).to eq(13)
    expect(detached).to eq([29])
    expect(owner.state[2]).to eq(1)

spec_summary
