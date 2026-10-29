use spec
use ../lib/miter_eval

# Input patterns repeat every eight bits; check one full period and the sign bit.
-> miter_check_gate(op, tt, inv_a, inv_b, inv_out)
  w0 = i64[8]; w1 = i64[8]; w2 = i64[8]; w3 = i64[8]
  w4 = i64[8]; w5 = i64[8]; w6 = i64[8]; w7 = i64[8]
  words = [w0, w1, w2, w3, w4, w5, w6, w7]
  extra = 0
  while extra < 24
    words.push(i64[8])
    extra += 1
  opcodes = i64[8]; in0 = i64[8]; in1 = i64[8]; in2 = i64[8]
  inva = i64[8]; invb = i64[8]; invo = i64[8]
  offsets = i64[8]; counts = i64[8]
  clause_off = i64[8]; clause_len = i64[8]; lits = i64[24]
  opcodes[4] = op
  in0[4] = 1; in1[4] = 2; in2[4] = 3
  inva[4] = inv_a; invb[4] = inv_b; invo[4] = inv_out
  ncl = 0
  m = 0
  while m < 8
    if ((tt >> m) & 1) != 0
      clause_off[ncl] = 3 * ncl
      clause_len[ncl] = 3
      j = 0
      while j < 3
        lits[3 * ncl + j] = ((m >> j) & 1) != 0 ? 0 - j - 1 : j + 1
        j += 1
      ncl += 1
    m += 1
  counts[4] = ncl
  k = 0
  while k < 32
    w = words[k] ## i64[]
    w[1] = -6148914691236517206 ## i64
    w[2] = -3689348814741910324 ## i64
    w[3] = -1085102592571150096 ## i64
    w[1] = -1 ^ w[1] if (k & 1) != 0
    w[2] = -1 ^ w[2] if (k & 2) != 0
    w[3] = -1 ^ w[3] if (k & 4) != 0
    k += 1
  values = i64[256]
  k = 0
  while k < 32
    w = words[k] ## i64[]
    j = 0
    while j < 8
      values[32 * j + k] = w[j]
      j += 1
    k += 1
  gates = i64[64]
  gates[32] = opcodes[4]
  gates[33] = in0[4]; gates[34] = in1[4]; gates[35] = in2[4]
  gates[36] = inva[4]; gates[37] = invb[4]; gates[38] = invo[4]
  z = wassat_miter32_eval_gate_packed(values, 4,
    gates, offsets, counts, clause_off, clause_len, lits)
  k = 0
  while k < 32
    w = words[k] ## i64[]
    w[4] = values[128 + k]
    k += 1
  errors = 0
  k = 0
  while k < 32
    w = words[k] ## i64[]
    bit = 0
    while bit < 64
      a = (w[1] >> bit) & 1
      b = (w[2] >> bit) & 1
      c = (w[3] >> bit) & 1
      expected = 0
      if op == 1
        expected = a ^ b ^ (inv_out & 1)
      elsif op == 2
        expected = ((a ^ (inv_a & 1)) & (b ^ (inv_b & 1))) ^ (inv_out & 1)
      else
        expected = (tt >> (a + 2 * b + 4 * c)) & 1
      errors += 1 if ((w[4] >> bit) & 1) != expected
      bit = bit == 7 ? 63 : bit + 1
    k += 1
  errors

describe "Thirty-two-word miter gate evaluation" ->
  it "evaluates XOR and XNOR for every input pattern and the sign bit" ->
    expect(miter_check_gate(1, 0, 0, 0, 0)).to eq(0)
    expect(miter_check_gate(1, 0, 0, 0, -1)).to eq(0)
  it "evaluates every input and output polarity of AND" ->
    mask = 0
    while mask < 8
      expect(miter_check_gate(2, 0, (mask & 1) != 0 ? -1 : 0,
        (mask & 2) != 0 ? -1 : 0, (mask & 4) != 0 ? -1 : 0)).to eq(0)
      mask += 1
  it "evaluates majority and its complement" ->
    expect(miter_check_gate(3, 232, 0, 0, 0)).to eq(0)
    expect(miter_check_gate(3, 23, 0, 0, -1)).to eq(0)
  it "evaluates selector and its complement" ->
    expect(miter_check_gate(4, 202, 0, 0, 0)).to eq(0)
    expect(miter_check_gate(4, 53, 0, 0, -1)).to eq(0)
  it "evaluates every three-input truth table through the general fallback" ->
    tt = 0
    while tt < 256
      expect(miter_check_gate(5, tt, 0, 0, 0)).to eq(0)
      tt += 1

spec_summary
