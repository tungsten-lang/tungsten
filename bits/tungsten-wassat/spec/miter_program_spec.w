use spec
use ../lib/miter_eval

describe "Contiguous cone instruction records" ->
  it "preserves metadata, signed masks, destinations and repeated gates" ->
    gates = i64[40]
    i = 0
    while i < 40
      gates[i] = i - 20
      i += 1
    cones = i64[3]
    cones[0] = 4; cones[1] = 2; cones[2] = 4
    program = i64[24]
    wassat_miter_pack_cones(cones, gates, program, 3)
    i = 0
    while i < 3
      j = 0
      while j < 7
        expect(program[8 * i + j]).to eq(gates[8 * cones[i] + j])
        j += 1
      expect(program[8 * i + 7]).to eq(cones[i])
      i += 1
  it "does not touch storage for an empty cone" ->
    empty = i64[1]; program = i64[1]; program[0] = 123
    wassat_miter_pack_cones(empty, empty, program, 0)
    expect(program[0]).to eq(123)



-> miter_program_matches_scalar(op, tt, first, last, phase)
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
  topo = i64[2]; topo[0] = 34; topo[1] = 35
  cones = i64[2]; cones[0] = 34; cones[1] = 35
  offsets = i64[24]; lengths = i64[24]; lengths[0] = 2
  ctz = i8[4096]
  i = 1
  while i < 4096
    n = i; k = 0
    while (n & 1) == 0
      n = n >> 1
      k += 1
    ctz[i] = k
    i += 1
  gates = i64[320]
  d = 8 * 34
  gates[d] = op; gates[d + 1] = 12; gates[d + 2] = 1; gates[d + 3] = 2
  inv_a = op == 2 ? (phase & 1) : 1
  inv_b = op == 2 ? ((phase >> 1) & 1) : 0
  inv_out = op == 2 ? ((phase >> 2) & 1) : 1
  gates[d + 4] = inv_a != 0 ? -1 : 0
  gates[d + 5] = inv_b != 0 ? -1 : 0
  gates[d + 6] = inv_out != 0 ? -1 : 0
  d = 8 * 35
  gates[d] = 1; gates[d + 1] = 34; gates[d + 2] = 34
  cl_off = i64[40]; cl_count = i64[40]
  lit_off = i64[8]; lit_len = i64[8]; lits = i64[24]
  input_ids = i64[3]; input_ids[0] = 12; input_ids[1] = 1; input_ids[2] = 2
  count = 0; m = 0
  while m < 8
    if ((tt >> m) & 1) != 0
      lit_off[count] = 3 * count; lit_len[count] = 3
      j = 0
      while j < 3
        lits[3 * count + j] = ((m >> j) & 1) != 0 ? 0 - input_ids[j] : input_ids[j]
        j += 1
      count += 1
    m += 1
  cl_count[34] = count
  program = i64[16]; values = i64[1280]; stop = i64[1]
  wassat_miter_pack_cones(cones, gates, program, 2)
  batches = wassat_miter32_eval_chunk_packed(values, masks, simd, gray, topo, 2,
    cones, offsets, lengths, ctz, gates, program, cl_off, cl_count,
    lit_off, lit_len, lits, 35, stop, first, last)
  errors = batches == last - first && stop[0] == 0 ? 0 : 1
  a = ((last - 1) ^ ((last - 1) >> 1)) & 1
  lane = 0
  while lane < 32
    bit = 0
    while bit < 64
      b = bit & 1; c = (bit >> 1) & 1
      expected = (tt >> (a + 2 * b + 4 * c)) & 1
      expected = a ^ b ^ 1 if op == 1
      expected = ((a ^ inv_a) & (b ^ inv_b)) ^ inv_out if op == 2
      errors += 1 if ((values[32 * 34 + lane] >> bit) & 1) != expected
      bit = bit == 7 ? 63 : bit + 1
    lane += 1
  errors

describe "Cone program execution" ->
  it "matches scalar gate values after Gray transitions for every opcode" ->
    [[1, 0], [2, 0], [3, 23], [4, 53], [5, 150], [5, 0], [5, 255]].each -> (pair)
      expect(miter_program_matches_scalar(pair[0], pair[1], 0, 2, 5)).to eq(0)
      expect(miter_program_matches_scalar(pair[0], pair[1], 0, 4, 5)).to eq(0)
      expect(miter_program_matches_scalar(pair[0], pair[1], 4094, 4097, 5)).to eq(0)



  it "covers every AND input/output polarity through the Gray program" ->
    phase = 0
    while phase < 8
      expect(miter_program_matches_scalar(2, 0, 0, 2, phase)).to eq(0)
      expect(miter_program_matches_scalar(2, 0, 0, 4, phase)).to eq(0)
      phase += 1

describe "Normalized instruction work counters" ->
  it "counts each opcode's repeated Gray updates and excludes initial batches" ->
    counts = i64[11]; program = i64[24]
    program[0] = 2; program[8] = 6; program[16] = 10
    offsets = i64[2]; lengths = i64[2]
    offsets[1] = 2; lengths[0] = 2; lengths[1] = 1
    wassat_miter_gray_program_work(counts, program, offsets, lengths, 0, 5, 32)
    expect(counts[2]).to eq(64)
    expect(counts[6]).to eq(64)
    expect(counts[10]).to eq(32)
    wassat_miter_gray_program_work(counts, program, offsets, lengths, 0, 0, 32)
    wassat_miter_gray_program_work(counts, program, offsets, lengths, 0, 1, 32)
    expect(counts[2] + counts[6] + counts[10]).to eq(160)

spec_summary
