use spec
use rectangle_bound_support

describe "Complete rectangle-coloring counting certificates" ->
  it "derives the tight per-color divisibility contradiction" ->
    m = i64[32]
    expect(wassat_rectangle_refute(rectangle_test_formula(5,2),m,i64[2])).to eq(-1)
    expect(m[25]).to eq(1)
    expect(m[8]).to eq(25)
    expect(m[9]).to eq(25)
    expect(m[14]).to eq(200)
    expect(m[16]).to eq(20)
    expect(m[17]).to eq(20)
    expect(m[18]).to eq(5)
    expect(m[19]).to eq(10)
    expect(m[20]).to eq(2)
    expect(m[21]).to eq(1)
    expect(m[22]).to eq(2)
  it "also checks the strict pair-capacity bound" ->
    m = i64[32]
    expect(wassat_rectangle_refute(rectangle_test_formula(6,2),m,i64[2])).to eq(-1)
    expect(m[16]).to eq(36)
    expect(m[17]).to eq(30)
    expect(m[22]).to eq(1)
  it "recognizes but does not refute satisfiable grid boundaries" ->
    [3,4].each -> (n)
      m = i64[32]
      expect(wassat_rectangle_refute(rectangle_test_formula(n,2),m,i64[2])).to eq(0)
      expect(m[25]).to eq(1)
  it "handles signed variable, literal and clause permutations" ->
    m = i64[32]
    expect(wassat_rectangle_refute(rectangle_test_formula(5,2,"",true),m,i64[2])).to eq(-1)
    expect(m[14]).to eq(200)
  ["domain","amo","rectangle","repeat","polarity","out_of_range"].each -> (mutation)
    it "requires intact original clauses: [mutation]" ->
      m = i64[32]
      expect(wassat_rectangle_refute(rectangle_test_formula(5,2,mutation),m,i64[2])).to eq(0)
      expect(m[25]).to eq(0)
  it "rejects inconsistent counts and truncated arrays" ->
    f = rectangle_test_formula(5,2); f["flat_ncl"] -= 1
    m = i64[32]
    expect(wassat_rectangle_refute(f,m,i64[2])).to eq(0)
    expect(m[23]).to eq(0)
    f = rectangle_test_formula(5,2); f["flat_offs"] = i64[1]
    expect(wassat_rectangle_refute(f,i64[32],i64[2])).to eq(0)
  it "checks native offsets and widths before any indexed scan" ->
    f = rectangle_test_formula(5,2); f["flat_offs"][0] = -1
    expect(wassat_rectangle_refute(f,i64[32],i64[2])).to eq(0)
    f = rectangle_test_formula(5,2); f["flat_offs"][0] = 9223372036854775807
    expect(wassat_rectangle_refute(f,i64[32],i64[2])).to eq(0)
    f = rectangle_test_formula(5,2); f["flat_lens"][0] = 1000000
    expect(wassat_rectangle_refute(f,i64[32],i64[2])).to eq(0)
  it "honors pre-cancellation and expired deadlines before scratch allocation" ->
    f = rectangle_test_formula(5,2); m = i64[32]; stop = i64[2]
    wassat_stop_cancel(stop)
    expect(wassat_rectangle_refute(f,m,stop)).to eq(0)
    expect(m[1]).to eq(1)
    expect(m[23]).to eq(0)
    expect(wassat_rectangle_refute(f,m,i64[2],clock_ms()-1)).to eq(0)
    expect(m[1]).to eq(2)
    expect(m[23]).to eq(0)
  it "requires valid result and stop buffers" ->
    f = rectangle_test_formula(5,2)
    expect(wassat_rectangle_refute(f,i64[1],i64[2])).to eq(0)
    expect(wassat_rectangle_refute(f,i64[32],i64[1])).to eq(0)

spec_summary
