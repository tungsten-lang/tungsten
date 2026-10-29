use spec
use ../lib/miter_eval

# A conjunction with exactly one satisfying 32-input assignment checks the
# mapping of bit positions, word lanes and Gray inputs independently of counts.
-> miter_match_assignment(first, last, target_batch, lane, bit)
  masks = i64[6]
  masks[0] = -6148914691236517206 ## i64
  masks[1] = -3689348814741910324 ## i64
  masks[2] = -1085102592571150096 ## i64
  masks[3] = -71777214294589696 ## i64
  masks[4] = -281470681808896 ## i64
  masks[5] = -4294967296 ## i64
  simd = i64[11]; gray = i64[24]
  i = 0
  while i < 11
    simd[i] = i + 1
    i += 1
  i = 0
  while i < 21
    gray[i] = i + 12
    i += 1
  assignment = bit | (lane << 6) | ((target_batch ^ (target_batch >> 1)) << 11)
  gates = i64[512]; values = i64[2048]; topo = i64[31]
  i = 0
  while i < 31
    gv = i + 33
    d = 8 * gv
    topo[i] = gv
    gates[d] = 2
    gates[d + 1] = i == 0 ? 1 : gv - 1
    gates[d + 2] = i + 2
    gates[d + 4] = i == 0 && (assignment & 1) == 0 ? -1 : 0
    gates[d + 5] = ((assignment >> (i + 1)) & 1) == 0 ? -1 : 0
    i += 1
  # Input 12 first reaches gate 43; later inputs have shorter suffix cones.
  cones = i64[231]; offsets = i64[24]; lengths = i64[24]
  i = 0; pos = 0
  while i < 21
    offsets[i] = pos
    lengths[i] = 21 - i
    gv = 43 + i
    while gv <= 63
      cones[pos] = gv
      pos += 1
      gv += 1
    i += 1
  ctz = i8[4096]
  i = 1
  while i < 4096
    n = i; k = 0
    while (n & 1) == 0
      n = n >> 1
      k += 1
    ctz[i] = k
    i += 1
  program = i64[8 * pos]
  wassat_miter_pack_cones(cones, gates, program, pos)
  empty = i64[1]; stop = i64[1]
  batches = wassat_miter32_eval_chunk_packed(values,
    masks, simd, gray, topo, 31, cones, offsets, lengths, ctz,
    gates, program, empty, empty, empty, empty, empty, 63, stop, first, last)
  [stop[0], batches]

describe "Circuit assignment coverage" ->
  it "reaches every word lane and high word bits" ->
    [0].each -> (batch)
      lane = 0
      while lane < 32
        [0, 31, 63].each -> (bit)
          expect(miter_match_assignment(batch, batch + 1, batch, lane, bit)).to eq([1, 1])
        lane += 1
  it "reaches the highest Gray bits" ->
    [4095, 1048575, 2097151].each -> (batch)
      expect(miter_match_assignment(batch, batch + 1, batch, 31, 63)).to eq([1, 1])
  it "excludes absent assignments and finds a hit after a Gray transition" ->
    [0, 4095, 1048575, 2097150].each -> (batch)
      expect(miter_match_assignment(batch, batch + 1, batch + 1, 31, 63)).to eq([0, 1])
      expect(miter_match_assignment(batch, batch + 2, batch + 1, 31, 63)).to eq([1, 2])

spec_summary
