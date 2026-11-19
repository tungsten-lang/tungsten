use spec
use ../lib/solver

+ VmtfBatchFixture < Wassat
  -> exercise(floor, mark)
    # Initial order 1..6, with the decision cursor at 4.
    (1..6).each -> (v)
      @vq_prev[v] = v - 1
      @vq_next[v] = v + 1
      @vq_stamp[v] = 7 - v
    @vq_next[6] = 0
    @vq_state[0] = 1
    @vq_state[1] = 6
    @vq_state[2] = 6
    @vq_state[3] = 4
    @vq_state[4] = floor
    vars = i64[5]
    [1, 6, 3, 3, 2].each_with_index -> (v, i) vars[i] = v
    marks = i8[7]
    (0...vars.size).each -> (i) marks[vars[i]] = mark
    wassat_vmtf_batch(@vq_next, @vq_prev, @vq_stamp, @vq_state, vars, marks, vars.size, mark)
    forward = []
    v = @vq_state[0]
    6.times ->
      forward.push(v)
      v = @vq_next[v]
    expect(v).to eq(0)
    backward = []
    v = @vq_state[1]
    6.times ->
      backward.push(v)
      v = @vq_prev[v]
    expect(v).to eq(0)
    expect(backward).to eq(forward.reverse)
    expect(@vq_state[3]).to eq(4)
    (1..6).each -> (i) expect(marks[i]).to eq(0)
    [forward, @vq_state[2], @vq_stamp[2], @vq_stamp[3], @vq_stamp[6]]

describe "Batched move-to-front updates" ->
  it "moves the old tail and stamps a repeated head only once" ->
    s = VmtfBatchFixture.new(6, [], WASSAT_PROOF_NONE)
    expect(s.exercise(0, 0)).to eq([[2, 3, 6, 1, 4, 5], 9, 9, 8, 7])

  it "clears reason marks even on secondary variables that stay in place" ->
    s = VmtfBatchFixture.new(6, [], WASSAT_PROOF_NONE)
    expect(s.exercise(2, 1)).to eq([[2, 3, 1, 4, 5, 6], 8, 8, 7, 1])

spec_summary
