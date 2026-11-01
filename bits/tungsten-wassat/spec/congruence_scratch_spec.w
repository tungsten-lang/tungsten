use spec
use ../lib/solver

describe "Congruence scratch reuse" ->
  it "resets the entire retained buffer between rounds" ->
    scratch = [nil, nil]
    a = wassat_congruence_buffer(scratch, 0, 8)
    a[0] = 17
    a[7] = 91
    b = wassat_congruence_buffer(scratch, 0, 3)
    expect(a[0]).to eq(0)
    expect(a[7]).to eq(0)
    b[1] = 23
    expect(a[1]).to eq(23)

  it "grows one slot without changing another" ->
    scratch = [nil, nil]
    a = wassat_congruence_buffer(scratch, 0, 2)
    b = wassat_congruence_buffer(scratch, 1, 4)
    a[0] = 7
    b[3] = 19
    c = wassat_congruence_buffer(scratch, 0, 16)
    expect(c.size).to eq(16)
    expect(c[0]).to eq(0)
    expect(c[15]).to eq(0)
    expect(a[0]).to eq(7)
    expect(b[3]).to eq(19)

  it "keeps the single-round path independent" ->
    a = wassat_congruence_buffer(nil, 0, 4)
    a[0] = 13
    b = wassat_congruence_buffer(nil, 0, 4)
    expect(a[0]).to eq(13)
    expect(b[0]).to eq(0)

spec_summary
