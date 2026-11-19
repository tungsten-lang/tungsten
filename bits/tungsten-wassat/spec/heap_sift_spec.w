use spec
use ../lib/solver

describe "Stable heap sifting" ->
  it "preserves equal-priority removal order" ->
    heap = i64[8]
    pos = i32[8]
    act = i64[8]
    state = i64[2]
    v = 1
    while v <= 7
      pos[v] = -1
      act[v] = 1
      z = wassat_heap_insert(heap, pos, act, state, v)
      v += 1
    expected = [1, 7, 6, 5, 4, 3, 2]
    expected.each -> (want)
      expect(wassat_heap_pop(heap, pos, act, state)).to eq(want)
      expect(wassat_heap_valid(heap, pos, act, state, 7)).to eq(1)

  it "maintains inverse positions and maximum priority through repeated bumps" ->
    heap = i64[128]
    pos = i32[128]
    act = i64[128]
    state = i64[2]
    v = 1
    while v <= 127
      pos[v] = -1
      act[v] = (v * 17) % 31
      z = wassat_heap_insert(heap, pos, act, state, v)
      v += 1
    k = 0
    while k < 511
      v = (k * 73) % 127 + 1
      act[v] = act[v] + 37
      index = pos[v] ## i64
      z = wassat_heap_up(heap, pos, act, index)
      expect(wassat_heap_valid(heap, pos, act, state, 127)).to eq(1)
      k += 1
    previous = 1000000
    seen = i8[128]
    while state[0] > 0
      v = wassat_heap_pop(heap, pos, act, state)
      expect(seen[v]).to eq(0)
      seen[v] = 1
      expect(act[v] <= previous).to eq(true)
      previous = act[v]
      expect(wassat_heap_valid(heap, pos, act, state, 127)).to eq(1)

  it "does not inspect absent entries when sifting an empty heap" ->
    heap = i64[0]
    pos = i32[0]
    act = i64[0]
    state = i64[2]
    expect(wassat_heap_down(heap, pos, act, state, 0)).to eq(0)
    expect(wassat_heap_up(heap, pos, act, 0)).to eq(0)

  it "preserves a parent tie when an activity bump rescales the heap" ->
    heap = i64[3]
    pos = i32[3]
    act = i64[3]
    state = i64[2]
    heap[0] = 1
    heap[1] = 2
    pos[2] = 1
    act[1] = 4503599627370496
    act[2] = act[1] - 1
    state[0] = 2
    state[1] = 64
    expect(wassat_evsids_bump(act, heap, pos, state, 2, 2)).to eq(1)
    expect(act[1]).to eq(1048576)
    expect(act[2]).to eq(act[1])
    expect(heap[0]).to eq(1)
    expect(pos[2]).to eq(1)

  it "uses the rescaled increment for the rest of an activity batch" ->
    heap = i64[3]
    pos = i32[5]
    act = i64[5]
    state = i64[2]
    vars = i64[3]
    heap[0] = 1
    heap[1] = 2
    pos[2] = 1
    pos[3] = -1
    pos[4] = -1
    act[1] = 4503599627370496
    act[2] = act[1] - 1
    act[3] = -1
    state[0] = 2
    state[1] = 64
    vars[0] = 2
    vars[1] = 3
    vars[2] = 4
    wassat_evsids_batch(act, heap, pos, state, vars, 3, 4)
    expect(act[2]).to eq(act[1])
    expect(heap[0]).to eq(1)
    expect(act[3]).to eq(-1)
    expect(act[4]).to eq(32)
    expect(pos[4]).to eq(-1)
    expect(state[1]).to eq(32)

spec_summary
