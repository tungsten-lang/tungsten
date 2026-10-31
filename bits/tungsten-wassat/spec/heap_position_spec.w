use spec
use ../lib/solver

describe "Heap position representation" ->
  it "rejects unsupported variable indices before allocating solver buffers" ->
    expect(-> () Wassat.new(2147483648, [], WASSAT_PROOF_NONE)).to raise_error

  it "keeps a large positive position distinct from the absent sentinel" ->
    pos = i32[2]
    heap = i64[2]
    act = i64[2]
    st = i64[2]
    pos[1] = 2147483647
    expect(wassat_heap_insert(heap, pos, act, st, 1)).to eq(0)
    expect(pos[1]).to eq(2147483647)
    pos[1] = -1
    expect(wassat_heap_insert(heap, pos, act, st, 1)).to eq(1)
    expect(pos[1]).to eq(0)
    expect(wassat_heap_pop(heap, pos, act, st)).to eq(1)
    expect(pos[1]).to eq(-1)

spec_summary
