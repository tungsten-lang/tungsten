use spec
use ../lib/wassat

-> klieber_masks
  masks = i64[6]
  masks[0] = -6148914691236517206 ## i64
  masks[1] = -3689348814741910324 ## i64
  masks[2] = -1085102592571150096 ## i64
  masks[3] = -71777214294589696 ## i64
  masks[4] = -281470681808896 ## i64
  masks[5] = -4294967296 ## i64
  masks

-> klieber_one_gate(program, v, a, b, na, nb, pol)
  program[0] = v
  program[1] = a
  program[2] = na
  program[3] = b
  program[4] = nb
  program[5] = pol

describe "Packed exhaustive circuit evaluation" ->
  it "packs gate order, indices and signed masks exactly" ->
    ga = i64[10]; gb = i64[10]; na = i64[10]; nb = i64[10]; pol = i64[10]
    ga[8] = 3; gb[8] = 7; na[8] = -1; pol[8] = -1
    ga[7] = 1; gb[7] = 2; nb[7] = -1
    gates = i64[2]; gates[0] = 8; gates[1] = 7
    program = i32[12]
    wassat_klieber_pack_stages(program, gates, ga, na, gb, nb, pol, 2)
    expected = [8, 3, -1, 7, 0, -1, 7, 1, 0, 2, -1, 0]
    i = 0
    while i < 12
      expect(program[i]).to eq(expected[i])
      i += 1

  it "matches scalar truth evaluation for every gate and target polarity" ->
    code = 0
    while code < 16
      program = i32[6]
      na = code & 1; nb = (code >> 1) & 1; pol = (code >> 2) & 1
      klieber_one_gate(program, 7, 1, 2, -na, -nb, -pol)
      offs = i64[2]; offs[1] = 1
      targets = i64[1]; targets[0] = (code & 8) == 0 ? 7 : -7
      found = i64[2]; work = i64[3]
      wassat_klieber_eval_packed(i64[8], klieber_masks(), program, offs,
        targets, found, 6, 1, 0, 1, work, 0)
      expect(found[0]).to eq(1)
      assignment = found[1]
      value = (((assignment & 1) ^ na) & (((assignment >> 1) & 1) ^ nb)) ^ pol
      expect(value).to eq((code & 8) == 0 ? 1 : 0)
      expect(work[0]).to eq(1)
      expect(work[1]).to eq(1)
      code += 1

  it "evaluates incremental stages without repeating shared gates" ->
    program = i32[12]
    klieber_one_gate(program, 7, 1, 2, 0, 0, 0)
    program[6] = 8; program[7] = 7; program[9] = 3
    offs = i64[3]; offs[1] = 1; offs[2] = 2
    targets = i64[2]; targets[0] = 7; targets[1] = 8
    found = i64[2]; work = i64[3]
    wassat_klieber_eval_packed(i64[9], klieber_masks(), program, offs,
      targets, found, 6, 2, 0, 1, work, 0)
    expect(found[1]).to eq(7)
    expect(work[0]).to eq(1)
    expect(work[1]).to eq(2)
    expect(work[2]).to eq(2)

  it "preserves lane 63 through signed word masks" ->
    ga = i64[12]; gb = i64[12]
    ga[7] = 1; gb[7] = 2
    ga[8] = 3; gb[8] = 4
    ga[9] = 5; gb[9] = 6
    ga[10] = 7; gb[10] = 8
    ga[11] = 10; gb[11] = 9
    gates = i64[5]
    i = 0
    while i < 5
      gates[i] = 7 + i
      i += 1
    program = i32[30]
    wassat_klieber_pack_stages(program, gates, ga, i64[12], gb, i64[12], i64[12], 5)
    offs = i64[2]; offs[1] = 5
    targets = i64[1]; targets[0] = 11
    found = i64[2]; work = i64[3]
    wassat_klieber_eval_packed(i64[12], klieber_masks(), program, offs,
      targets, found, 6, 1, 0, 1, work, 0)
    expect(found[0]).to eq(1)
    expect(found[1]).to eq(63)
    expect(work[1]).to eq(5)

  it "counts exhausted batches and zero-gate stages without publishing a result" ->
    program = i32[6]
    klieber_one_gate(program, 9, 1, 2, 0, 0, 0)
    offs = i64[3]; offs[1] = 1; offs[2] = 1
    targets = i64[2]; targets[0] = 9; targets[1] = -9
    found = i64[2]; work = i64[19]; work[0] = 99
    wassat_klieber_eval_packed(i64[10], klieber_masks(), program, offs,
      targets, found, 8, 2, 0, 4, work, 16)
    expect(found[0]).to eq(0)
    expect(work[0]).to eq(99)
    expect(work[16]).to eq(4)
    expect(work[17]).to eq(4)
    expect(work[18]).to eq(8)

  it "stops before gate work for empty chunks and prior cancellation" ->
    found = i64[2]; work = i64[3]
    wassat_klieber_eval_packed(i64[7], klieber_masks(), i32[0], i64[1],
      i64[0], found, 6, 0, 2, 2, work, 0)
    expect(work[0]).to eq(0)
    wassat_stop_cancel(found)
    wassat_klieber_eval_packed(i64[7], klieber_masks(), i32[0], i64[1],
      i64[0], found, 6, 0, 0, 100, work, 0)
    expect(work[0] + work[1] + work[2]).to eq(0)

  it "allows only the first publisher to write the assignment" ->
    found = i64[2]
    expect(wassat_klieber_publish(found, 63)).to eq(1)
    expect(wassat_klieber_publish(found, 5)).to eq(0)
    expect(wassat_stop_load(found)).to eq(1)
    expect(found[1]).to eq(63)
    reserved = i64[2]
    z = ccall("__w_arr_compare_exchange", reserved, 0, 0, -1)
    expect(wassat_klieber_publish(reserved, 5)).to eq(0)
    expect(reserved[1]).to eq(0)

spec_summary
