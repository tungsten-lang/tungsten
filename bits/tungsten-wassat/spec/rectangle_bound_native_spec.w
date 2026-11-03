# spec: compiled -- full grid coverage up to 833431 clauses; small cases run on both engines.
use spec
use rectangle_bound_support

describe "Large rectangle-coloring counting certificates" ->
  [ [11,3], [19,4], [29,5] ].each -> (pair)
    it "checks the complete [pair[0]] by [pair[0]] grid with [pair[1]] colors" ->
      m = i64[32]
      expect(wassat_rectangle_refute(rectangle_test_formula(pair[0],pair[1],"",true),m,i64[2])).to eq(-1)
      expect(m[25]).to eq(1)
      expect(m[22]).to eq(2)
      expect(m[21]).to eq(1)
      expect(m[3] > 0).to eq(true)
      expect(m[14]).to eq(m[10])

spec_summary
