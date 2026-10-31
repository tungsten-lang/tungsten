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

spec_summary
