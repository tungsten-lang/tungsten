use spec
use ../lib/wassat

describe "Specialist fingerprint admission" ->
  it "skips inputs outside every fingerprint-consuming lane" ->
    expect(wassat_specialist_fingerprint_mask(65000, 23590384, true)).to eq(0)
    expect(wassat_specialist_fingerprint_mask(3000000, 500000, true)).to eq(0)
    expect(wassat_specialist_fingerprint_mask(10000, 499, true)).to eq(0)
  it "retains both endpoints of SDP admission" ->
    expect(wassat_specialist_fingerprint_mask(10000, 15000, false) & 1).to eq(1)
    expect(wassat_specialist_fingerprint_mask(250000, 350000, false) & 1).to eq(1)
    expect(wassat_specialist_fingerprint_mask(9999, 15000, false) & 1).to eq(0)
    expect(wassat_specialist_fingerprint_mask(250001, 350000, false) & 1).to eq(0)
  it "retains the enclosing lower variable bound for symmetry fixing" ->
    expect(wassat_specialist_fingerprint_mask(100, 500, false) & 2).to eq(2)
    expect(wassat_specialist_fingerprint_mask(40000, 1200000, false) & 2).to eq(2)
    expect(wassat_specialist_fingerprint_mask(99, 500, false) & 2).to eq(0)
    expect(wassat_specialist_fingerprint_mask(40001, 1200000, false) & 2).to eq(0)
  it "honors windmill admission and its explicit disable switch" ->
    expect(wassat_specialist_fingerprint_mask(20000, 100000, true) & 4).to eq(4)
    expect(wassat_specialist_fingerprint_mask(2000000, 20000000, true) & 4).to eq(4)
    expect(wassat_specialist_fingerprint_mask(2000000, 20000001, true)).to eq(0)
    expect(wassat_specialist_fingerprint_mask(65000, 1000000, false)).to eq(0)

spec_summary
