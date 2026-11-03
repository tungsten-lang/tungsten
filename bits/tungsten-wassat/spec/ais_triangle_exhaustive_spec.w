# spec: compiled -- exhaustive 1024-graph oracle exceeds the tree-walker memory budget
# The focused AIS spec checks the same bound and its rejection cases on both engines.
use spec
use ../lib/wassat

describe "Wassat AIS triangle bound exhaustive oracle" ->
  it "never overstates the cover size on any five-vertex graph" ->
    pairs = [[1,2], [1,3], [1,4], [1,5], [2,3], [2,4], [2,5], [3,4], [3,5], [4,5]]
    mask = 0
    while mask < 1024
      adj = i8[25]
      i = 0
      while i < pairs.size
        if (mask & (1 << i)) != 0
          a = pairs[i][0] - 1; b = pairs[i][1] - 1
          adj[a * 5 + b] = 1; adj[b * 5 + a] = 1
        i += 1
      minimum = 5
      cover = 0
      while cover < 32
        valid = true; size = 0; v = 0
        while v < 5
          size += 1 if (cover & (1 << v)) != 0
          v += 1
        i = 0
        while i < pairs.size
          a = pairs[i][0] - 1; b = pairs[i][1] - 1
          valid = false if adj[a * 5 + b] != 0 && (cover & ((1 << a) | (1 << b))) == 0
          i += 1
        minimum = size if valid && size < minimum
        cover += 1
      meta = i64[4]
      bound = wassat_ais_triangle_bound(adj, 5, meta)
      expect(bound <= minimum).to eq(true)
      mask += 1

spec_summary
