use spec
use ../lib/miter_eval

-> miter_count_work(cones, gates, first, batches)
  return 0 if batches <= 0
  work = gates
  s = first + 1
  while s < first + batches
    k = 0
    value = s
    while (value & 1) == 0
      value = value >> 1
      k += 1
    work += cones[k]
    s += 1
  work

-> miter_chunk_count(wide, first, last, output_one, already_stopped)
  w0 = i64[40]; w1 = i64[40]; w2 = i64[40]; w3 = i64[40]
  w4 = i64[40]; w5 = i64[40]; w6 = i64[40]; w7 = i64[40]
  masks = i64[6]; simd = i64[11]; gray = i64[24]
  i = 0
  while i < 11
    simd[i] = i + 1
    i += 1
  n_simd = wide ? 11 : 6
  n_gray = wide ? 21 : 22
  i = 0
  while i < n_gray
    gray[i] = n_simd + 1 + i
    i += 1
  topo = i64[1]; topo[0] = 33
  cones = i64[1]; offsets = i64[24]; lengths = i64[24]
  ctz = i8[4096]
  i = 1
  while i < 4096
    k = 0
    value = i
    while (value & 1) == 0
      value = value >> 1
      k += 1
    ctz[i] = k
    i += 1
  ops = i64[40]; in0 = i64[40]; in1 = i64[40]; in2 = i64[40]
  inva = i64[40]; invb = i64[40]; invo = i64[40]
  cl_off = i64[40]; cl_cnt = i64[40]; lit_off = i64[1]
  lit_len = i64[1]; lits = i64[1]; inv_res = i64[40]
  ops[33] = 1; in0[33] = 1; in1[33] = 1
  invo[33] = output_one ? -1 : 0
  stop = i64[1]; stop[0] = already_stopped ? 1 : 0
  if wide
    gates = i64[320]
    gates[264] = ops[33]
    gates[265] = in0[33]; gates[266] = in1[33]; gates[267] = in2[33]
    gates[268] = inva[33]; gates[269] = invb[33]; gates[270] = invo[33]
    program = i64[8]
    wassat_miter_pack_cones(cones, gates, program, 0)
    values = i64[1280]
    wassat_miter32_eval_chunk_packed(values,
      masks, simd, gray, topo, 1, cones, offsets, lengths, ctz,
      gates, program, cl_off, cl_cnt,
      lit_off, lit_len, lits, 33, stop, first, last)
  else
    wassat_miter28_eval_chunk(w0, masks, simd, gray, topo, 1,
      cones, offsets, lengths, ctz, ops, in0, in1, inva, invb, invo,
      cl_off, cl_cnt, lit_off, lit_len, lits, inv_res, 33, stop, first, last)

describe "Exact Gray-code circuit work counters" ->
  it "matches direct counting for disjoint prefixes and power-of-two boundaries" ->
    cones = i64[24]
    k = 0
    while k < 24
      cones[k] = 3 * k + 1
      k += 1
    [0, 1, 7, 4090, 65530, 1048570].each -> (first)
      [0, 1, 2, 7, 19].each -> (batches)
        expect(wassat_miter_gray_work(cones, 31, first, batches)).to eq(
          miter_count_work(cones, 31, first, batches))
  it "returns evaluated batches from both word widths" ->
    [false, true].each -> (wide)
      expect(miter_chunk_count(wide, 7, 26, false, false)).to eq(19)
      expect(miter_chunk_count(wide, 4090, 4101, false, false)).to eq(11)
  it "counts only completed work on a hit, empty range or prior cancellation" ->
    [false, true].each -> (wide)
      expect(miter_chunk_count(wide, 7, 26, true, false)).to eq(1)
      expect(miter_chunk_count(wide, 7, 7, false, false)).to eq(0)
      expect(miter_chunk_count(wide, 7, 26, false, true)).to eq(0)

  it "attributes completed work to gate opcodes, including empty prefixes" ->
    counts = i64[7]; ops = i64[4]; topo = i64[3]
    ops[1] = 1; ops[2] = 5; ops[3] = 6
    topo[0] = 1; topo[1] = 2; topo[2] = 3
    cones = i64[3]; offsets = i64[3]; lengths = i64[3]
    cones[0] = 1; cones[1] = 3; cones[2] = 2
    offsets[1] = 2; offsets[2] = 3
    lengths[0] = 2; lengths[1] = 1
    wassat_miter_gray_op_work(counts, ops, topo, 3, cones, offsets, lengths, 0, 5, 16)
    expect(counts[1]).to eq(48)
    expect(counts[5]).to eq(32)
    expect(counts[6]).to eq(48)
    wassat_miter_gray_op_work(counts, ops, topo, 3, cones, offsets, lengths, 0, 0, 16)
    expect(counts[1] + counts[5] + counts[6]).to eq(128)

spec_summary
