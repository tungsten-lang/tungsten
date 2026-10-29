# Native bit-parallel kernels and work accounting for exact circuit evaluation.

-> wassat_miter28_eval_gate(wval, gv, g_op, g_in0, g_in1, g_inva, g_invb, g_invo,
                            g_cl_off, g_cl_cnt, cl_l_off, cl_l_len, cl_lits, g_inv_res) (i64[] i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  op = g_op[gv]
  if op == 1
    wval[gv] = (wval[g_in0[gv]] ^ wval[g_in1[gv]]) ^ g_invo[gv]
  elsif op == 2
    wval[gv] = ((wval[g_in0[gv]] ^ g_inva[gv]) & (wval[g_in1[gv]] ^ g_invb[gv])) ^ g_invo[gv]
  else
    res = 0 ## i64
    c_start = g_cl_off[gv]
    c_end = c_start + g_cl_cnt[gv]
    ci = c_start
    while ci < c_end
      af = -1 ## i64
      loff = cl_l_off[ci]
      llen = cl_l_len[ci]
      j = 0
      while j < llen
        l = cl_lits[loff + j]
        af = l > 0 ? (af & (-1 ^ wval[l])) : (af & wval[0 - l])
        j += 1
      res = res | af
      ci += 1
    wval[gv] = res ^ g_inv_res[gv]
  0

# Exact work for one completed Gray-code prefix. The first batch evaluates
# the full graph; later batches evaluate the flipped input's fanout cone.
# Count trailing-zero frequencies arithmetically, outside the hot loop.
-> wassat_miter_gray_work(cone_len, n_gates, first, batches) (i64[] i64 i64 i64) i64
  return 0 if batches <= 0
  work = n_gates
  last = first + batches - 1
  half = 1
  k = 0
  while k < cone_len.size
    period = 2 * half
    flips = (last + half) / period - (first + half) / period
    work += flips * cone_len[k]
    half = period
    k += 1
  work

-> wassat_miter28_eval_chunk(wval, p_masks, simd_pis, gray_pis, topo, n_gates,
                             cone_gates, cone_off, cone_len, ctz_tab,
                             g_op, g_in0, g_in1, g_inva, g_invb, g_invo,
                             g_cl_off, g_cl_cnt, cl_l_off, cl_l_len, cl_lits, g_inv_res,
                             out_var, any_sat, b_lo, b_hi) (i64[] i64[] i64[] i64[] i64[] i64 i64[] i64[] i64[] i8[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64[] i64 i64) i64
  return 0 if b_lo >= b_hi || any_sat[0] != 0
  i = 0
  while i < 6
    wval[simd_pis[i]] = p_masks[i]
    i += 1
  gcode = b_lo ^ (b_lo >> 1)
  k = 0
  while k < 22
    wval[gray_pis[k]] = ((gcode >> k) & 1) != 0 ? -1 : 0
    k += 1
  gi = 0
  while gi < n_gates
    wassat_miter28_eval_gate(wval, topo[gi], g_op, g_in0, g_in1, g_inva, g_invb, g_invo,
                             g_cl_off, g_cl_cnt, cl_l_off, cl_l_len, cl_lits, g_inv_res)
    gi += 1
  if wval[out_var] != 0
    any_sat[0] = 1
    return 1
  s = b_lo + 1
  while s < b_hi
    return s - b_lo if (s & 4095) == 0 && any_sat[0] != 0
    lo12 = s & 4095
    fk = lo12 != 0 ? (ctz_tab[lo12] ## i64) : (12 + (ctz_tab[s >> 12] ## i64))
    pv = gray_pis[fk]
    wval[pv] = -1 ^ wval[pv]
    c_start = cone_off[fk]
    c_end = c_start + cone_len[fk]
    ci = c_start
    while ci < c_end
      gv = cone_gates[ci]
      op = g_op[gv]
      if op == 1
        wval[gv] = (wval[g_in0[gv]] ^ wval[g_in1[gv]]) ^ g_invo[gv]
      elsif op == 2
        wval[gv] = ((wval[g_in0[gv]] ^ g_inva[gv]) & (wval[g_in1[gv]] ^ g_invb[gv])) ^ g_invo[gv]
      else
        wassat_miter28_eval_gate(wval, gv, g_op, g_in0, g_in1, g_inva, g_invb, g_invo,
                                 g_cl_off, g_cl_cnt, cl_l_off, cl_l_len, cl_lits, g_inv_res)
      ci += 1
    if wval[out_var] != 0
      any_sat[0] = 1
      return s - b_lo + 1
    s += 1
  b_hi - b_lo

-> wassat_miter32_eval_gate_packed(values, gv,
                             gates,
                             g_cl_off, g_cl_cnt, cl_l_off, cl_l_len, cl_lits) (i64[] i64 i64[] i64[] i64[] i64[] i64[] i64[]) i64
  op = gates[8 * gv + 0]
  if op == 1
    ia = gates[8 * gv + 1]; ib = gates[8 * gv + 2]; vo = gates[8 * gv + 6]
    values[32 * gv + 0] = (values[32 * ia + 0] ^ values[32 * ib + 0]) ^ vo; values[32 * gv + 1] = (values[32 * ia + 1] ^ values[32 * ib + 1]) ^ vo
    values[32 * gv + 16] = (values[32 * ia + 16] ^ values[32 * ib + 16]) ^ vo; values[32 * gv + 17] = (values[32 * ia + 17] ^ values[32 * ib + 17]) ^ vo
    values[32 * gv + 8] = (values[32 * ia + 8] ^ values[32 * ib + 8]) ^ vo; values[32 * gv + 9] = (values[32 * ia + 9] ^ values[32 * ib + 9]) ^ vo
    values[32 * gv + 24] = (values[32 * ia + 24] ^ values[32 * ib + 24]) ^ vo; values[32 * gv + 25] = (values[32 * ia + 25] ^ values[32 * ib + 25]) ^ vo
    values[32 * gv + 2] = (values[32 * ia + 2] ^ values[32 * ib + 2]) ^ vo; values[32 * gv + 3] = (values[32 * ia + 3] ^ values[32 * ib + 3]) ^ vo
    values[32 * gv + 18] = (values[32 * ia + 18] ^ values[32 * ib + 18]) ^ vo; values[32 * gv + 19] = (values[32 * ia + 19] ^ values[32 * ib + 19]) ^ vo
    values[32 * gv + 10] = (values[32 * ia + 10] ^ values[32 * ib + 10]) ^ vo; values[32 * gv + 11] = (values[32 * ia + 11] ^ values[32 * ib + 11]) ^ vo
    values[32 * gv + 26] = (values[32 * ia + 26] ^ values[32 * ib + 26]) ^ vo; values[32 * gv + 27] = (values[32 * ia + 27] ^ values[32 * ib + 27]) ^ vo
    values[32 * gv + 4] = (values[32 * ia + 4] ^ values[32 * ib + 4]) ^ vo; values[32 * gv + 5] = (values[32 * ia + 5] ^ values[32 * ib + 5]) ^ vo
    values[32 * gv + 20] = (values[32 * ia + 20] ^ values[32 * ib + 20]) ^ vo; values[32 * gv + 21] = (values[32 * ia + 21] ^ values[32 * ib + 21]) ^ vo
    values[32 * gv + 12] = (values[32 * ia + 12] ^ values[32 * ib + 12]) ^ vo; values[32 * gv + 13] = (values[32 * ia + 13] ^ values[32 * ib + 13]) ^ vo
    values[32 * gv + 28] = (values[32 * ia + 28] ^ values[32 * ib + 28]) ^ vo; values[32 * gv + 29] = (values[32 * ia + 29] ^ values[32 * ib + 29]) ^ vo
    values[32 * gv + 6] = (values[32 * ia + 6] ^ values[32 * ib + 6]) ^ vo; values[32 * gv + 7] = (values[32 * ia + 7] ^ values[32 * ib + 7]) ^ vo
    values[32 * gv + 22] = (values[32 * ia + 22] ^ values[32 * ib + 22]) ^ vo; values[32 * gv + 23] = (values[32 * ia + 23] ^ values[32 * ib + 23]) ^ vo
    values[32 * gv + 14] = (values[32 * ia + 14] ^ values[32 * ib + 14]) ^ vo; values[32 * gv + 15] = (values[32 * ia + 15] ^ values[32 * ib + 15]) ^ vo
    values[32 * gv + 30] = (values[32 * ia + 30] ^ values[32 * ib + 30]) ^ vo; values[32 * gv + 31] = (values[32 * ia + 31] ^ values[32 * ib + 31]) ^ vo
  elsif op == 2
    ia = gates[8 * gv + 1]; ib = gates[8 * gv + 2]
    va = gates[8 * gv + 4]; vb = gates[8 * gv + 5]; vo = gates[8 * gv + 6]
    values[32 * gv + 0] = ((values[32 * ia + 0] ^ va) & (values[32 * ib + 0] ^ vb)) ^ vo; values[32 * gv + 1] = ((values[32 * ia + 1] ^ va) & (values[32 * ib + 1] ^ vb)) ^ vo
    values[32 * gv + 16] = ((values[32 * ia + 16] ^ va) & (values[32 * ib + 16] ^ vb)) ^ vo; values[32 * gv + 17] = ((values[32 * ia + 17] ^ va) & (values[32 * ib + 17] ^ vb)) ^ vo
    values[32 * gv + 8] = ((values[32 * ia + 8] ^ va) & (values[32 * ib + 8] ^ vb)) ^ vo; values[32 * gv + 9] = ((values[32 * ia + 9] ^ va) & (values[32 * ib + 9] ^ vb)) ^ vo
    values[32 * gv + 24] = ((values[32 * ia + 24] ^ va) & (values[32 * ib + 24] ^ vb)) ^ vo; values[32 * gv + 25] = ((values[32 * ia + 25] ^ va) & (values[32 * ib + 25] ^ vb)) ^ vo
    values[32 * gv + 2] = ((values[32 * ia + 2] ^ va) & (values[32 * ib + 2] ^ vb)) ^ vo; values[32 * gv + 3] = ((values[32 * ia + 3] ^ va) & (values[32 * ib + 3] ^ vb)) ^ vo
    values[32 * gv + 18] = ((values[32 * ia + 18] ^ va) & (values[32 * ib + 18] ^ vb)) ^ vo; values[32 * gv + 19] = ((values[32 * ia + 19] ^ va) & (values[32 * ib + 19] ^ vb)) ^ vo
    values[32 * gv + 10] = ((values[32 * ia + 10] ^ va) & (values[32 * ib + 10] ^ vb)) ^ vo; values[32 * gv + 11] = ((values[32 * ia + 11] ^ va) & (values[32 * ib + 11] ^ vb)) ^ vo
    values[32 * gv + 26] = ((values[32 * ia + 26] ^ va) & (values[32 * ib + 26] ^ vb)) ^ vo; values[32 * gv + 27] = ((values[32 * ia + 27] ^ va) & (values[32 * ib + 27] ^ vb)) ^ vo
    values[32 * gv + 4] = ((values[32 * ia + 4] ^ va) & (values[32 * ib + 4] ^ vb)) ^ vo; values[32 * gv + 5] = ((values[32 * ia + 5] ^ va) & (values[32 * ib + 5] ^ vb)) ^ vo
    values[32 * gv + 20] = ((values[32 * ia + 20] ^ va) & (values[32 * ib + 20] ^ vb)) ^ vo; values[32 * gv + 21] = ((values[32 * ia + 21] ^ va) & (values[32 * ib + 21] ^ vb)) ^ vo
    values[32 * gv + 12] = ((values[32 * ia + 12] ^ va) & (values[32 * ib + 12] ^ vb)) ^ vo; values[32 * gv + 13] = ((values[32 * ia + 13] ^ va) & (values[32 * ib + 13] ^ vb)) ^ vo
    values[32 * gv + 28] = ((values[32 * ia + 28] ^ va) & (values[32 * ib + 28] ^ vb)) ^ vo; values[32 * gv + 29] = ((values[32 * ia + 29] ^ va) & (values[32 * ib + 29] ^ vb)) ^ vo
    values[32 * gv + 6] = ((values[32 * ia + 6] ^ va) & (values[32 * ib + 6] ^ vb)) ^ vo; values[32 * gv + 7] = ((values[32 * ia + 7] ^ va) & (values[32 * ib + 7] ^ vb)) ^ vo
    values[32 * gv + 22] = ((values[32 * ia + 22] ^ va) & (values[32 * ib + 22] ^ vb)) ^ vo; values[32 * gv + 23] = ((values[32 * ia + 23] ^ va) & (values[32 * ib + 23] ^ vb)) ^ vo
    values[32 * gv + 14] = ((values[32 * ia + 14] ^ va) & (values[32 * ib + 14] ^ vb)) ^ vo; values[32 * gv + 15] = ((values[32 * ia + 15] ^ va) & (values[32 * ib + 15] ^ vb)) ^ vo
    values[32 * gv + 30] = ((values[32 * ia + 30] ^ va) & (values[32 * ib + 30] ^ vb)) ^ vo; values[32 * gv + 31] = ((values[32 * ia + 31] ^ va) & (values[32 * ib + 31] ^ vb)) ^ vo
  elsif op == 3
    ia = gates[8 * gv + 1]; ib = gates[8 * gv + 2]; ic = gates[8 * gv + 3]; vo = gates[8 * gv + 6]
    values[32 * gv + 0] = ((values[32 * ia + 0] & values[32 * ib + 0]) | ((values[32 * ia + 0] ^ values[32 * ib + 0]) & values[32 * ic + 0])) ^ vo
    values[32 * gv + 16] = ((values[32 * ia + 16] & values[32 * ib + 16]) | ((values[32 * ia + 16] ^ values[32 * ib + 16]) & values[32 * ic + 16])) ^ vo
    values[32 * gv + 8] = ((values[32 * ia + 8] & values[32 * ib + 8]) | ((values[32 * ia + 8] ^ values[32 * ib + 8]) & values[32 * ic + 8])) ^ vo
    values[32 * gv + 24] = ((values[32 * ia + 24] & values[32 * ib + 24]) | ((values[32 * ia + 24] ^ values[32 * ib + 24]) & values[32 * ic + 24])) ^ vo
    values[32 * gv + 1] = ((values[32 * ia + 1] & values[32 * ib + 1]) | ((values[32 * ia + 1] ^ values[32 * ib + 1]) & values[32 * ic + 1])) ^ vo
    values[32 * gv + 17] = ((values[32 * ia + 17] & values[32 * ib + 17]) | ((values[32 * ia + 17] ^ values[32 * ib + 17]) & values[32 * ic + 17])) ^ vo
    values[32 * gv + 9] = ((values[32 * ia + 9] & values[32 * ib + 9]) | ((values[32 * ia + 9] ^ values[32 * ib + 9]) & values[32 * ic + 9])) ^ vo
    values[32 * gv + 25] = ((values[32 * ia + 25] & values[32 * ib + 25]) | ((values[32 * ia + 25] ^ values[32 * ib + 25]) & values[32 * ic + 25])) ^ vo
    values[32 * gv + 2] = ((values[32 * ia + 2] & values[32 * ib + 2]) | ((values[32 * ia + 2] ^ values[32 * ib + 2]) & values[32 * ic + 2])) ^ vo
    values[32 * gv + 18] = ((values[32 * ia + 18] & values[32 * ib + 18]) | ((values[32 * ia + 18] ^ values[32 * ib + 18]) & values[32 * ic + 18])) ^ vo
    values[32 * gv + 10] = ((values[32 * ia + 10] & values[32 * ib + 10]) | ((values[32 * ia + 10] ^ values[32 * ib + 10]) & values[32 * ic + 10])) ^ vo
    values[32 * gv + 26] = ((values[32 * ia + 26] & values[32 * ib + 26]) | ((values[32 * ia + 26] ^ values[32 * ib + 26]) & values[32 * ic + 26])) ^ vo
    values[32 * gv + 3] = ((values[32 * ia + 3] & values[32 * ib + 3]) | ((values[32 * ia + 3] ^ values[32 * ib + 3]) & values[32 * ic + 3])) ^ vo
    values[32 * gv + 19] = ((values[32 * ia + 19] & values[32 * ib + 19]) | ((values[32 * ia + 19] ^ values[32 * ib + 19]) & values[32 * ic + 19])) ^ vo
    values[32 * gv + 11] = ((values[32 * ia + 11] & values[32 * ib + 11]) | ((values[32 * ia + 11] ^ values[32 * ib + 11]) & values[32 * ic + 11])) ^ vo
    values[32 * gv + 27] = ((values[32 * ia + 27] & values[32 * ib + 27]) | ((values[32 * ia + 27] ^ values[32 * ib + 27]) & values[32 * ic + 27])) ^ vo
    values[32 * gv + 4] = ((values[32 * ia + 4] & values[32 * ib + 4]) | ((values[32 * ia + 4] ^ values[32 * ib + 4]) & values[32 * ic + 4])) ^ vo
    values[32 * gv + 20] = ((values[32 * ia + 20] & values[32 * ib + 20]) | ((values[32 * ia + 20] ^ values[32 * ib + 20]) & values[32 * ic + 20])) ^ vo
    values[32 * gv + 12] = ((values[32 * ia + 12] & values[32 * ib + 12]) | ((values[32 * ia + 12] ^ values[32 * ib + 12]) & values[32 * ic + 12])) ^ vo
    values[32 * gv + 28] = ((values[32 * ia + 28] & values[32 * ib + 28]) | ((values[32 * ia + 28] ^ values[32 * ib + 28]) & values[32 * ic + 28])) ^ vo
    values[32 * gv + 5] = ((values[32 * ia + 5] & values[32 * ib + 5]) | ((values[32 * ia + 5] ^ values[32 * ib + 5]) & values[32 * ic + 5])) ^ vo
    values[32 * gv + 21] = ((values[32 * ia + 21] & values[32 * ib + 21]) | ((values[32 * ia + 21] ^ values[32 * ib + 21]) & values[32 * ic + 21])) ^ vo
    values[32 * gv + 13] = ((values[32 * ia + 13] & values[32 * ib + 13]) | ((values[32 * ia + 13] ^ values[32 * ib + 13]) & values[32 * ic + 13])) ^ vo
    values[32 * gv + 29] = ((values[32 * ia + 29] & values[32 * ib + 29]) | ((values[32 * ia + 29] ^ values[32 * ib + 29]) & values[32 * ic + 29])) ^ vo
    values[32 * gv + 6] = ((values[32 * ia + 6] & values[32 * ib + 6]) | ((values[32 * ia + 6] ^ values[32 * ib + 6]) & values[32 * ic + 6])) ^ vo
    values[32 * gv + 22] = ((values[32 * ia + 22] & values[32 * ib + 22]) | ((values[32 * ia + 22] ^ values[32 * ib + 22]) & values[32 * ic + 22])) ^ vo
    values[32 * gv + 14] = ((values[32 * ia + 14] & values[32 * ib + 14]) | ((values[32 * ia + 14] ^ values[32 * ib + 14]) & values[32 * ic + 14])) ^ vo
    values[32 * gv + 30] = ((values[32 * ia + 30] & values[32 * ib + 30]) | ((values[32 * ia + 30] ^ values[32 * ib + 30]) & values[32 * ic + 30])) ^ vo
    values[32 * gv + 7] = ((values[32 * ia + 7] & values[32 * ib + 7]) | ((values[32 * ia + 7] ^ values[32 * ib + 7]) & values[32 * ic + 7])) ^ vo
    values[32 * gv + 23] = ((values[32 * ia + 23] & values[32 * ib + 23]) | ((values[32 * ia + 23] ^ values[32 * ib + 23]) & values[32 * ic + 23])) ^ vo
    values[32 * gv + 15] = ((values[32 * ia + 15] & values[32 * ib + 15]) | ((values[32 * ia + 15] ^ values[32 * ib + 15]) & values[32 * ic + 15])) ^ vo
    values[32 * gv + 31] = ((values[32 * ia + 31] & values[32 * ib + 31]) | ((values[32 * ia + 31] ^ values[32 * ib + 31]) & values[32 * ic + 31])) ^ vo
  elsif op == 4
    ia = gates[8 * gv + 1]; ib = gates[8 * gv + 2]; ic = gates[8 * gv + 3]; vo = gates[8 * gv + 6]
    values[32 * gv + 0] = ((values[32 * ic + 0] & values[32 * ib + 0]) | ((-1 ^ values[32 * ic + 0]) & values[32 * ia + 0])) ^ vo
    values[32 * gv + 16] = ((values[32 * ic + 16] & values[32 * ib + 16]) | ((-1 ^ values[32 * ic + 16]) & values[32 * ia + 16])) ^ vo
    values[32 * gv + 8] = ((values[32 * ic + 8] & values[32 * ib + 8]) | ((-1 ^ values[32 * ic + 8]) & values[32 * ia + 8])) ^ vo
    values[32 * gv + 24] = ((values[32 * ic + 24] & values[32 * ib + 24]) | ((-1 ^ values[32 * ic + 24]) & values[32 * ia + 24])) ^ vo
    values[32 * gv + 1] = ((values[32 * ic + 1] & values[32 * ib + 1]) | ((-1 ^ values[32 * ic + 1]) & values[32 * ia + 1])) ^ vo
    values[32 * gv + 17] = ((values[32 * ic + 17] & values[32 * ib + 17]) | ((-1 ^ values[32 * ic + 17]) & values[32 * ia + 17])) ^ vo
    values[32 * gv + 9] = ((values[32 * ic + 9] & values[32 * ib + 9]) | ((-1 ^ values[32 * ic + 9]) & values[32 * ia + 9])) ^ vo
    values[32 * gv + 25] = ((values[32 * ic + 25] & values[32 * ib + 25]) | ((-1 ^ values[32 * ic + 25]) & values[32 * ia + 25])) ^ vo
    values[32 * gv + 2] = ((values[32 * ic + 2] & values[32 * ib + 2]) | ((-1 ^ values[32 * ic + 2]) & values[32 * ia + 2])) ^ vo
    values[32 * gv + 18] = ((values[32 * ic + 18] & values[32 * ib + 18]) | ((-1 ^ values[32 * ic + 18]) & values[32 * ia + 18])) ^ vo
    values[32 * gv + 10] = ((values[32 * ic + 10] & values[32 * ib + 10]) | ((-1 ^ values[32 * ic + 10]) & values[32 * ia + 10])) ^ vo
    values[32 * gv + 26] = ((values[32 * ic + 26] & values[32 * ib + 26]) | ((-1 ^ values[32 * ic + 26]) & values[32 * ia + 26])) ^ vo
    values[32 * gv + 3] = ((values[32 * ic + 3] & values[32 * ib + 3]) | ((-1 ^ values[32 * ic + 3]) & values[32 * ia + 3])) ^ vo
    values[32 * gv + 19] = ((values[32 * ic + 19] & values[32 * ib + 19]) | ((-1 ^ values[32 * ic + 19]) & values[32 * ia + 19])) ^ vo
    values[32 * gv + 11] = ((values[32 * ic + 11] & values[32 * ib + 11]) | ((-1 ^ values[32 * ic + 11]) & values[32 * ia + 11])) ^ vo
    values[32 * gv + 27] = ((values[32 * ic + 27] & values[32 * ib + 27]) | ((-1 ^ values[32 * ic + 27]) & values[32 * ia + 27])) ^ vo
    values[32 * gv + 4] = ((values[32 * ic + 4] & values[32 * ib + 4]) | ((-1 ^ values[32 * ic + 4]) & values[32 * ia + 4])) ^ vo
    values[32 * gv + 20] = ((values[32 * ic + 20] & values[32 * ib + 20]) | ((-1 ^ values[32 * ic + 20]) & values[32 * ia + 20])) ^ vo
    values[32 * gv + 12] = ((values[32 * ic + 12] & values[32 * ib + 12]) | ((-1 ^ values[32 * ic + 12]) & values[32 * ia + 12])) ^ vo
    values[32 * gv + 28] = ((values[32 * ic + 28] & values[32 * ib + 28]) | ((-1 ^ values[32 * ic + 28]) & values[32 * ia + 28])) ^ vo
    values[32 * gv + 5] = ((values[32 * ic + 5] & values[32 * ib + 5]) | ((-1 ^ values[32 * ic + 5]) & values[32 * ia + 5])) ^ vo
    values[32 * gv + 21] = ((values[32 * ic + 21] & values[32 * ib + 21]) | ((-1 ^ values[32 * ic + 21]) & values[32 * ia + 21])) ^ vo
    values[32 * gv + 13] = ((values[32 * ic + 13] & values[32 * ib + 13]) | ((-1 ^ values[32 * ic + 13]) & values[32 * ia + 13])) ^ vo
    values[32 * gv + 29] = ((values[32 * ic + 29] & values[32 * ib + 29]) | ((-1 ^ values[32 * ic + 29]) & values[32 * ia + 29])) ^ vo
    values[32 * gv + 6] = ((values[32 * ic + 6] & values[32 * ib + 6]) | ((-1 ^ values[32 * ic + 6]) & values[32 * ia + 6])) ^ vo
    values[32 * gv + 22] = ((values[32 * ic + 22] & values[32 * ib + 22]) | ((-1 ^ values[32 * ic + 22]) & values[32 * ia + 22])) ^ vo
    values[32 * gv + 14] = ((values[32 * ic + 14] & values[32 * ib + 14]) | ((-1 ^ values[32 * ic + 14]) & values[32 * ia + 14])) ^ vo
    values[32 * gv + 30] = ((values[32 * ic + 30] & values[32 * ib + 30]) | ((-1 ^ values[32 * ic + 30]) & values[32 * ia + 30])) ^ vo
    values[32 * gv + 7] = ((values[32 * ic + 7] & values[32 * ib + 7]) | ((-1 ^ values[32 * ic + 7]) & values[32 * ia + 7])) ^ vo
    values[32 * gv + 23] = ((values[32 * ic + 23] & values[32 * ib + 23]) | ((-1 ^ values[32 * ic + 23]) & values[32 * ia + 23])) ^ vo
    values[32 * gv + 15] = ((values[32 * ic + 15] & values[32 * ib + 15]) | ((-1 ^ values[32 * ic + 15]) & values[32 * ia + 15])) ^ vo
    values[32 * gv + 31] = ((values[32 * ic + 31] & values[32 * ib + 31]) | ((-1 ^ values[32 * ic + 31]) & values[32 * ia + 31])) ^ vo
  else
    z64 = 0 ## i64
    m64 = -1 ## i64
    r0 = z64; r1 = z64; r2 = z64; r3 = z64
    r16 = z64; r17 = z64; r18 = z64; r19 = z64
    r8 = z64; r9 = z64; r10 = z64; r11 = z64
    r24 = z64; r25 = z64; r26 = z64; r27 = z64
    r4 = z64; r5 = z64; r6 = z64; r7 = z64
    r20 = z64; r21 = z64; r22 = z64; r23 = z64
    r12 = z64; r13 = z64; r14 = z64; r15 = z64
    r28 = z64; r29 = z64; r30 = z64; r31 = z64
    c_start = g_cl_off[gv]
    c_end = c_start + g_cl_cnt[gv]
    ci = c_start
    while ci < c_end
      af0 = m64; af1 = m64; af2 = m64; af3 = m64
      af16 = m64; af17 = m64; af18 = m64; af19 = m64
      af8 = m64; af9 = m64; af10 = m64; af11 = m64
      af24 = m64; af25 = m64; af26 = m64; af27 = m64
      af4 = m64; af5 = m64; af6 = m64; af7 = m64
      af20 = m64; af21 = m64; af22 = m64; af23 = m64
      af12 = m64; af13 = m64; af14 = m64; af15 = m64
      af28 = m64; af29 = m64; af30 = m64; af31 = m64
      loff = cl_l_off[ci]
      llen = cl_l_len[ci]
      j = 0
      while j < llen
        l = cl_lits[loff + j]
        if l > 0
          af0 = af0 & (-1 ^ values[32 * l + 0]); af1 = af1 & (-1 ^ values[32 * l + 1])
          af16 = af16 & (-1 ^ values[32 * l + 16]); af17 = af17 & (-1 ^ values[32 * l + 17])
          af8 = af8 & (-1 ^ values[32 * l + 8]); af9 = af9 & (-1 ^ values[32 * l + 9])
          af24 = af24 & (-1 ^ values[32 * l + 24]); af25 = af25 & (-1 ^ values[32 * l + 25])
          af2 = af2 & (-1 ^ values[32 * l + 2]); af3 = af3 & (-1 ^ values[32 * l + 3])
          af18 = af18 & (-1 ^ values[32 * l + 18]); af19 = af19 & (-1 ^ values[32 * l + 19])
          af10 = af10 & (-1 ^ values[32 * l + 10]); af11 = af11 & (-1 ^ values[32 * l + 11])
          af26 = af26 & (-1 ^ values[32 * l + 26]); af27 = af27 & (-1 ^ values[32 * l + 27])
          af4 = af4 & (-1 ^ values[32 * l + 4]); af5 = af5 & (-1 ^ values[32 * l + 5])
          af20 = af20 & (-1 ^ values[32 * l + 20]); af21 = af21 & (-1 ^ values[32 * l + 21])
          af12 = af12 & (-1 ^ values[32 * l + 12]); af13 = af13 & (-1 ^ values[32 * l + 13])
          af28 = af28 & (-1 ^ values[32 * l + 28]); af29 = af29 & (-1 ^ values[32 * l + 29])
          af6 = af6 & (-1 ^ values[32 * l + 6]); af7 = af7 & (-1 ^ values[32 * l + 7])
          af22 = af22 & (-1 ^ values[32 * l + 22]); af23 = af23 & (-1 ^ values[32 * l + 23])
          af14 = af14 & (-1 ^ values[32 * l + 14]); af15 = af15 & (-1 ^ values[32 * l + 15])
          af30 = af30 & (-1 ^ values[32 * l + 30]); af31 = af31 & (-1 ^ values[32 * l + 31])
        else
          nl = 0 - l
          af0 = af0 & values[32 * nl + 0]; af1 = af1 & values[32 * nl + 1]
          af16 = af16 & values[32 * nl + 16]; af17 = af17 & values[32 * nl + 17]
          af8 = af8 & values[32 * nl + 8]; af9 = af9 & values[32 * nl + 9]
          af24 = af24 & values[32 * nl + 24]; af25 = af25 & values[32 * nl + 25]
          af2 = af2 & values[32 * nl + 2]; af3 = af3 & values[32 * nl + 3]
          af18 = af18 & values[32 * nl + 18]; af19 = af19 & values[32 * nl + 19]
          af10 = af10 & values[32 * nl + 10]; af11 = af11 & values[32 * nl + 11]
          af26 = af26 & values[32 * nl + 26]; af27 = af27 & values[32 * nl + 27]
          af4 = af4 & values[32 * nl + 4]; af5 = af5 & values[32 * nl + 5]
          af20 = af20 & values[32 * nl + 20]; af21 = af21 & values[32 * nl + 21]
          af12 = af12 & values[32 * nl + 12]; af13 = af13 & values[32 * nl + 13]
          af28 = af28 & values[32 * nl + 28]; af29 = af29 & values[32 * nl + 29]
          af6 = af6 & values[32 * nl + 6]; af7 = af7 & values[32 * nl + 7]
          af22 = af22 & values[32 * nl + 22]; af23 = af23 & values[32 * nl + 23]
          af14 = af14 & values[32 * nl + 14]; af15 = af15 & values[32 * nl + 15]
          af30 = af30 & values[32 * nl + 30]; af31 = af31 & values[32 * nl + 31]
        j += 1
      r0 = r0 | af0; r1 = r1 | af1; r2 = r2 | af2; r3 = r3 | af3
      r16 = r16 | af16; r17 = r17 | af17; r18 = r18 | af18; r19 = r19 | af19
      r8 = r8 | af8; r9 = r9 | af9; r10 = r10 | af10; r11 = r11 | af11
      r24 = r24 | af24; r25 = r25 | af25; r26 = r26 | af26; r27 = r27 | af27
      r4 = r4 | af4; r5 = r5 | af5; r6 = r6 | af6; r7 = r7 | af7
      r20 = r20 | af20; r21 = r21 | af21; r22 = r22 | af22; r23 = r23 | af23
      r12 = r12 | af12; r13 = r13 | af13; r14 = r14 | af14; r15 = r15 | af15
      r28 = r28 | af28; r29 = r29 | af29; r30 = r30 | af30; r31 = r31 | af31
      ci += 1
    values[32 * gv + 0] = r0; values[32 * gv + 1] = r1; values[32 * gv + 2] = r2; values[32 * gv + 3] = r3
    values[32 * gv + 16] = r16; values[32 * gv + 17] = r17; values[32 * gv + 18] = r18; values[32 * gv + 19] = r19
    values[32 * gv + 8] = r8; values[32 * gv + 9] = r9; values[32 * gv + 10] = r10; values[32 * gv + 11] = r11
    values[32 * gv + 24] = r24; values[32 * gv + 25] = r25; values[32 * gv + 26] = r26; values[32 * gv + 27] = r27
    values[32 * gv + 4] = r4; values[32 * gv + 5] = r5; values[32 * gv + 6] = r6; values[32 * gv + 7] = r7
    values[32 * gv + 20] = r20; values[32 * gv + 21] = r21; values[32 * gv + 22] = r22; values[32 * gv + 23] = r23
    values[32 * gv + 12] = r12; values[32 * gv + 13] = r13; values[32 * gv + 14] = r14; values[32 * gv + 15] = r15
    values[32 * gv + 28] = r28; values[32 * gv + 29] = r29; values[32 * gv + 30] = r30; values[32 * gv + 31] = r31
  0

-> wassat_miter32_eval_chunk_packed(values,
                             p_masks, simd_pis, gray_pis, topo, n_gates,
                             cone_gates, cone_off, cone_len, ctz_tab,
                             gates, program,
                             g_cl_off, g_cl_cnt, cl_l_off, cl_l_len, cl_lits,
                             out_var, any_sat, b_lo, b_hi) (i64[] i64[] i64[] i64[] i64[] i64 i64[] i64[] i64[] i8[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64[] i64 i64) i64
  return 0 if b_lo >= b_hi || any_sat[0] != 0
  i = 0
  while i < 6
    pm = p_masks[i]
    pv = simd_pis[i]
    values[32 * pv + 0] = pm; values[32 * pv + 1] = pm; values[32 * pv + 2] = pm; values[32 * pv + 3] = pm
    values[32 * pv + 16] = pm; values[32 * pv + 17] = pm; values[32 * pv + 18] = pm; values[32 * pv + 19] = pm
    values[32 * pv + 8] = pm; values[32 * pv + 9] = pm; values[32 * pv + 10] = pm; values[32 * pv + 11] = pm
    values[32 * pv + 24] = pm; values[32 * pv + 25] = pm; values[32 * pv + 26] = pm; values[32 * pv + 27] = pm
    values[32 * pv + 4] = pm; values[32 * pv + 5] = pm; values[32 * pv + 6] = pm; values[32 * pv + 7] = pm
    values[32 * pv + 20] = pm; values[32 * pv + 21] = pm; values[32 * pv + 22] = pm; values[32 * pv + 23] = pm
    values[32 * pv + 12] = pm; values[32 * pv + 13] = pm; values[32 * pv + 14] = pm; values[32 * pv + 15] = pm
    values[32 * pv + 28] = pm; values[32 * pv + 29] = pm; values[32 * pv + 30] = pm; values[32 * pv + 31] = pm
    i += 1
  pv6 = simd_pis[6]
  values[32 * pv6 + 0] = 0; values[32 * pv6 + 1] = -1; values[32 * pv6 + 2] = 0; values[32 * pv6 + 3] = -1
  values[32 * pv6 + 16] = 0; values[32 * pv6 + 17] = -1; values[32 * pv6 + 18] = 0; values[32 * pv6 + 19] = -1
  values[32 * pv6 + 8] = 0; values[32 * pv6 + 9] = -1; values[32 * pv6 + 10] = 0; values[32 * pv6 + 11] = -1
  values[32 * pv6 + 24] = 0; values[32 * pv6 + 25] = -1; values[32 * pv6 + 26] = 0; values[32 * pv6 + 27] = -1
  values[32 * pv6 + 4] = 0; values[32 * pv6 + 5] = -1; values[32 * pv6 + 6] = 0; values[32 * pv6 + 7] = -1
  values[32 * pv6 + 20] = 0; values[32 * pv6 + 21] = -1; values[32 * pv6 + 22] = 0; values[32 * pv6 + 23] = -1
  values[32 * pv6 + 12] = 0; values[32 * pv6 + 13] = -1; values[32 * pv6 + 14] = 0; values[32 * pv6 + 15] = -1
  values[32 * pv6 + 28] = 0; values[32 * pv6 + 29] = -1; values[32 * pv6 + 30] = 0; values[32 * pv6 + 31] = -1
  pv7 = simd_pis[7]
  values[32 * pv7 + 0] = 0; values[32 * pv7 + 1] = 0; values[32 * pv7 + 2] = -1; values[32 * pv7 + 3] = -1
  values[32 * pv7 + 16] = 0; values[32 * pv7 + 17] = 0; values[32 * pv7 + 18] = -1; values[32 * pv7 + 19] = -1
  values[32 * pv7 + 8] = 0; values[32 * pv7 + 9] = 0; values[32 * pv7 + 10] = -1; values[32 * pv7 + 11] = -1
  values[32 * pv7 + 24] = 0; values[32 * pv7 + 25] = 0; values[32 * pv7 + 26] = -1; values[32 * pv7 + 27] = -1
  values[32 * pv7 + 4] = 0; values[32 * pv7 + 5] = 0; values[32 * pv7 + 6] = -1; values[32 * pv7 + 7] = -1
  values[32 * pv7 + 20] = 0; values[32 * pv7 + 21] = 0; values[32 * pv7 + 22] = -1; values[32 * pv7 + 23] = -1
  values[32 * pv7 + 12] = 0; values[32 * pv7 + 13] = 0; values[32 * pv7 + 14] = -1; values[32 * pv7 + 15] = -1
  values[32 * pv7 + 28] = 0; values[32 * pv7 + 29] = 0; values[32 * pv7 + 30] = -1; values[32 * pv7 + 31] = -1
  pv8 = simd_pis[8]
  values[32 * pv8 + 0] = 0; values[32 * pv8 + 1] = 0; values[32 * pv8 + 2] = 0; values[32 * pv8 + 3] = 0
  values[32 * pv8 + 16] = 0; values[32 * pv8 + 17] = 0; values[32 * pv8 + 18] = 0; values[32 * pv8 + 19] = 0
  values[32 * pv8 + 8] = 0; values[32 * pv8 + 9] = 0; values[32 * pv8 + 10] = 0; values[32 * pv8 + 11] = 0
  values[32 * pv8 + 24] = 0; values[32 * pv8 + 25] = 0; values[32 * pv8 + 26] = 0; values[32 * pv8 + 27] = 0
  values[32 * pv8 + 4] = -1; values[32 * pv8 + 5] = -1; values[32 * pv8 + 6] = -1; values[32 * pv8 + 7] = -1
  values[32 * pv8 + 20] = -1; values[32 * pv8 + 21] = -1; values[32 * pv8 + 22] = -1; values[32 * pv8 + 23] = -1
  values[32 * pv8 + 12] = -1; values[32 * pv8 + 13] = -1; values[32 * pv8 + 14] = -1; values[32 * pv8 + 15] = -1
  values[32 * pv8 + 28] = -1; values[32 * pv8 + 29] = -1; values[32 * pv8 + 30] = -1; values[32 * pv8 + 31] = -1
  pv9 = simd_pis[9]
  values[32 * pv9 + 0] = 0
  values[32 * pv9 + 16] = 0
  values[32 * pv9 + 1] = 0
  values[32 * pv9 + 17] = 0
  values[32 * pv9 + 2] = 0
  values[32 * pv9 + 18] = 0
  values[32 * pv9 + 3] = 0
  values[32 * pv9 + 19] = 0
  values[32 * pv9 + 4] = 0
  values[32 * pv9 + 20] = 0
  values[32 * pv9 + 5] = 0
  values[32 * pv9 + 21] = 0
  values[32 * pv9 + 6] = 0
  values[32 * pv9 + 22] = 0
  values[32 * pv9 + 7] = 0
  values[32 * pv9 + 23] = 0
  values[32 * pv9 + 8] = -1
  values[32 * pv9 + 24] = -1
  values[32 * pv9 + 9] = -1
  values[32 * pv9 + 25] = -1
  values[32 * pv9 + 10] = -1
  values[32 * pv9 + 26] = -1
  values[32 * pv9 + 11] = -1
  values[32 * pv9 + 27] = -1
  values[32 * pv9 + 12] = -1
  values[32 * pv9 + 28] = -1
  values[32 * pv9 + 13] = -1
  values[32 * pv9 + 29] = -1
  values[32 * pv9 + 14] = -1
  values[32 * pv9 + 30] = -1
  values[32 * pv9 + 15] = -1
  values[32 * pv9 + 31] = -1
  pv10 = simd_pis[10]
  values[32 * pv10 + 0] = 0
  values[32 * pv10 + 1] = 0
  values[32 * pv10 + 2] = 0
  values[32 * pv10 + 3] = 0
  values[32 * pv10 + 4] = 0
  values[32 * pv10 + 5] = 0
  values[32 * pv10 + 6] = 0
  values[32 * pv10 + 7] = 0
  values[32 * pv10 + 8] = 0
  values[32 * pv10 + 9] = 0
  values[32 * pv10 + 10] = 0
  values[32 * pv10 + 11] = 0
  values[32 * pv10 + 12] = 0
  values[32 * pv10 + 13] = 0
  values[32 * pv10 + 14] = 0
  values[32 * pv10 + 15] = 0
  values[32 * pv10 + 16] = -1
  values[32 * pv10 + 17] = -1
  values[32 * pv10 + 18] = -1
  values[32 * pv10 + 19] = -1
  values[32 * pv10 + 20] = -1
  values[32 * pv10 + 21] = -1
  values[32 * pv10 + 22] = -1
  values[32 * pv10 + 23] = -1
  values[32 * pv10 + 24] = -1
  values[32 * pv10 + 25] = -1
  values[32 * pv10 + 26] = -1
  values[32 * pv10 + 27] = -1
  values[32 * pv10 + 28] = -1
  values[32 * pv10 + 29] = -1
  values[32 * pv10 + 30] = -1
  values[32 * pv10 + 31] = -1
  gcode = b_lo ^ (b_lo >> 1)
  k = 0
  while k < 21
    gv_val = ((gcode >> k) & 1) != 0 ? -1 : 0
    pv = gray_pis[k]
    values[32 * pv + 0] = gv_val; values[32 * pv + 1] = gv_val; values[32 * pv + 2] = gv_val; values[32 * pv + 3] = gv_val
    values[32 * pv + 16] = gv_val; values[32 * pv + 17] = gv_val; values[32 * pv + 18] = gv_val; values[32 * pv + 19] = gv_val
    values[32 * pv + 8] = gv_val; values[32 * pv + 9] = gv_val; values[32 * pv + 10] = gv_val; values[32 * pv + 11] = gv_val
    values[32 * pv + 24] = gv_val; values[32 * pv + 25] = gv_val; values[32 * pv + 26] = gv_val; values[32 * pv + 27] = gv_val
    values[32 * pv + 4] = gv_val; values[32 * pv + 5] = gv_val; values[32 * pv + 6] = gv_val; values[32 * pv + 7] = gv_val
    values[32 * pv + 20] = gv_val; values[32 * pv + 21] = gv_val; values[32 * pv + 22] = gv_val; values[32 * pv + 23] = gv_val
    values[32 * pv + 12] = gv_val; values[32 * pv + 13] = gv_val; values[32 * pv + 14] = gv_val; values[32 * pv + 15] = gv_val
    values[32 * pv + 28] = gv_val; values[32 * pv + 29] = gv_val; values[32 * pv + 30] = gv_val; values[32 * pv + 31] = gv_val
    k += 1
  gi = 0
  while gi < n_gates
    gv = topo[gi]
    wassat_miter32_eval_gate_packed(values, gv,
                              gates,
                              g_cl_off, g_cl_cnt, cl_l_off, cl_l_len, cl_lits)
    gi += 1
  if (values[32 * out_var + 0] | values[32 * out_var + 1] | values[32 * out_var + 2] | values[32 * out_var + 3] | values[32 * out_var + 4] | values[32 * out_var + 5] | values[32 * out_var + 6] | values[32 * out_var + 7] | values[32 * out_var + 8] | values[32 * out_var + 9] | values[32 * out_var + 10] | values[32 * out_var + 11] | values[32 * out_var + 12] | values[32 * out_var + 13] | values[32 * out_var + 14] | values[32 * out_var + 15] | values[32 * out_var + 16] | values[32 * out_var + 17] | values[32 * out_var + 18] | values[32 * out_var + 19] | values[32 * out_var + 20] | values[32 * out_var + 21] | values[32 * out_var + 22] | values[32 * out_var + 23] | values[32 * out_var + 24] | values[32 * out_var + 25] | values[32 * out_var + 26] | values[32 * out_var + 27] | values[32 * out_var + 28] | values[32 * out_var + 29] | values[32 * out_var + 30] | values[32 * out_var + 31]) != 0
    any_sat[0] = 1
    return 1
  s = b_lo + 1
  while s < b_hi
    return s - b_lo if (s & 4095) == 0 && any_sat[0] != 0
    lo12 = s & 4095
    fk = lo12 != 0 ? (ctz_tab[lo12] ## i64) : (12 + (ctz_tab[s >> 12] ## i64))
    pv = gray_pis[fk]
    nv_pv = -1 ^ values[32 * pv + 0]
    values[32 * pv + 0] = nv_pv; values[32 * pv + 1] = nv_pv; values[32 * pv + 2] = nv_pv; values[32 * pv + 3] = nv_pv
    values[32 * pv + 16] = nv_pv; values[32 * pv + 17] = nv_pv; values[32 * pv + 18] = nv_pv; values[32 * pv + 19] = nv_pv
    values[32 * pv + 8] = nv_pv; values[32 * pv + 9] = nv_pv; values[32 * pv + 10] = nv_pv; values[32 * pv + 11] = nv_pv
    values[32 * pv + 24] = nv_pv; values[32 * pv + 25] = nv_pv; values[32 * pv + 26] = nv_pv; values[32 * pv + 27] = nv_pv
    values[32 * pv + 4] = nv_pv; values[32 * pv + 5] = nv_pv; values[32 * pv + 6] = nv_pv; values[32 * pv + 7] = nv_pv
    values[32 * pv + 20] = nv_pv; values[32 * pv + 21] = nv_pv; values[32 * pv + 22] = nv_pv; values[32 * pv + 23] = nv_pv
    values[32 * pv + 12] = nv_pv; values[32 * pv + 13] = nv_pv; values[32 * pv + 14] = nv_pv; values[32 * pv + 15] = nv_pv
    values[32 * pv + 28] = nv_pv; values[32 * pv + 29] = nv_pv; values[32 * pv + 30] = nv_pv; values[32 * pv + 31] = nv_pv
    c_start = cone_off[fk]
    c_end = c_start + cone_len[fk]
    ci = c_start
    while ci < c_end
      gv = program[8 * ci + 7]
      op = program[8 * ci + 0]
      ia = program[8 * ci + 1]
      ib = program[8 * ci + 2]
      if op == 1
        vo = program[8 * ci + 6]
        values[32 * gv + 0] = (values[32 * ia + 0] ^ values[32 * ib + 0]) ^ vo; values[32 * gv + 1] = (values[32 * ia + 1] ^ values[32 * ib + 1]) ^ vo
        values[32 * gv + 16] = (values[32 * ia + 16] ^ values[32 * ib + 16]) ^ vo; values[32 * gv + 17] = (values[32 * ia + 17] ^ values[32 * ib + 17]) ^ vo
        values[32 * gv + 8] = (values[32 * ia + 8] ^ values[32 * ib + 8]) ^ vo; values[32 * gv + 9] = (values[32 * ia + 9] ^ values[32 * ib + 9]) ^ vo
        values[32 * gv + 24] = (values[32 * ia + 24] ^ values[32 * ib + 24]) ^ vo; values[32 * gv + 25] = (values[32 * ia + 25] ^ values[32 * ib + 25]) ^ vo
        values[32 * gv + 2] = (values[32 * ia + 2] ^ values[32 * ib + 2]) ^ vo; values[32 * gv + 3] = (values[32 * ia + 3] ^ values[32 * ib + 3]) ^ vo
        values[32 * gv + 18] = (values[32 * ia + 18] ^ values[32 * ib + 18]) ^ vo; values[32 * gv + 19] = (values[32 * ia + 19] ^ values[32 * ib + 19]) ^ vo
        values[32 * gv + 10] = (values[32 * ia + 10] ^ values[32 * ib + 10]) ^ vo; values[32 * gv + 11] = (values[32 * ia + 11] ^ values[32 * ib + 11]) ^ vo
        values[32 * gv + 26] = (values[32 * ia + 26] ^ values[32 * ib + 26]) ^ vo; values[32 * gv + 27] = (values[32 * ia + 27] ^ values[32 * ib + 27]) ^ vo
        values[32 * gv + 4] = (values[32 * ia + 4] ^ values[32 * ib + 4]) ^ vo; values[32 * gv + 5] = (values[32 * ia + 5] ^ values[32 * ib + 5]) ^ vo
        values[32 * gv + 20] = (values[32 * ia + 20] ^ values[32 * ib + 20]) ^ vo; values[32 * gv + 21] = (values[32 * ia + 21] ^ values[32 * ib + 21]) ^ vo
        values[32 * gv + 12] = (values[32 * ia + 12] ^ values[32 * ib + 12]) ^ vo; values[32 * gv + 13] = (values[32 * ia + 13] ^ values[32 * ib + 13]) ^ vo
        values[32 * gv + 28] = (values[32 * ia + 28] ^ values[32 * ib + 28]) ^ vo; values[32 * gv + 29] = (values[32 * ia + 29] ^ values[32 * ib + 29]) ^ vo
        values[32 * gv + 6] = (values[32 * ia + 6] ^ values[32 * ib + 6]) ^ vo; values[32 * gv + 7] = (values[32 * ia + 7] ^ values[32 * ib + 7]) ^ vo
        values[32 * gv + 22] = (values[32 * ia + 22] ^ values[32 * ib + 22]) ^ vo; values[32 * gv + 23] = (values[32 * ia + 23] ^ values[32 * ib + 23]) ^ vo
        values[32 * gv + 14] = (values[32 * ia + 14] ^ values[32 * ib + 14]) ^ vo; values[32 * gv + 15] = (values[32 * ia + 15] ^ values[32 * ib + 15]) ^ vo
        values[32 * gv + 30] = (values[32 * ia + 30] ^ values[32 * ib + 30]) ^ vo; values[32 * gv + 31] = (values[32 * ia + 31] ^ values[32 * ib + 31]) ^ vo
      elsif op == 2
        values[32 * gv + 0] = values[32 * ia + 0] & values[32 * ib + 0]
        values[32 * gv + 1] = values[32 * ia + 1] & values[32 * ib + 1]
        values[32 * gv + 2] = values[32 * ia + 2] & values[32 * ib + 2]
        values[32 * gv + 3] = values[32 * ia + 3] & values[32 * ib + 3]
        values[32 * gv + 4] = values[32 * ia + 4] & values[32 * ib + 4]
        values[32 * gv + 5] = values[32 * ia + 5] & values[32 * ib + 5]
        values[32 * gv + 6] = values[32 * ia + 6] & values[32 * ib + 6]
        values[32 * gv + 7] = values[32 * ia + 7] & values[32 * ib + 7]
        values[32 * gv + 8] = values[32 * ia + 8] & values[32 * ib + 8]
        values[32 * gv + 9] = values[32 * ia + 9] & values[32 * ib + 9]
        values[32 * gv + 10] = values[32 * ia + 10] & values[32 * ib + 10]
        values[32 * gv + 11] = values[32 * ia + 11] & values[32 * ib + 11]
        values[32 * gv + 12] = values[32 * ia + 12] & values[32 * ib + 12]
        values[32 * gv + 13] = values[32 * ia + 13] & values[32 * ib + 13]
        values[32 * gv + 14] = values[32 * ia + 14] & values[32 * ib + 14]
        values[32 * gv + 15] = values[32 * ia + 15] & values[32 * ib + 15]
        values[32 * gv + 16] = values[32 * ia + 16] & values[32 * ib + 16]
        values[32 * gv + 17] = values[32 * ia + 17] & values[32 * ib + 17]
        values[32 * gv + 18] = values[32 * ia + 18] & values[32 * ib + 18]
        values[32 * gv + 19] = values[32 * ia + 19] & values[32 * ib + 19]
        values[32 * gv + 20] = values[32 * ia + 20] & values[32 * ib + 20]
        values[32 * gv + 21] = values[32 * ia + 21] & values[32 * ib + 21]
        values[32 * gv + 22] = values[32 * ia + 22] & values[32 * ib + 22]
        values[32 * gv + 23] = values[32 * ia + 23] & values[32 * ib + 23]
        values[32 * gv + 24] = values[32 * ia + 24] & values[32 * ib + 24]
        values[32 * gv + 25] = values[32 * ia + 25] & values[32 * ib + 25]
        values[32 * gv + 26] = values[32 * ia + 26] & values[32 * ib + 26]
        values[32 * gv + 27] = values[32 * ia + 27] & values[32 * ib + 27]
        values[32 * gv + 28] = values[32 * ia + 28] & values[32 * ib + 28]
        values[32 * gv + 29] = values[32 * ia + 29] & values[32 * ib + 29]
        values[32 * gv + 30] = values[32 * ia + 30] & values[32 * ib + 30]
        values[32 * gv + 31] = values[32 * ia + 31] & values[32 * ib + 31]
      elsif op == 3
        ic = program[8 * ci + 3]; vo = program[8 * ci + 6]
        values[32 * gv + 0] = ((values[32 * ia + 0] & values[32 * ib + 0]) | ((values[32 * ia + 0] ^ values[32 * ib + 0]) & values[32 * ic + 0])) ^ vo
        values[32 * gv + 16] = ((values[32 * ia + 16] & values[32 * ib + 16]) | ((values[32 * ia + 16] ^ values[32 * ib + 16]) & values[32 * ic + 16])) ^ vo
        values[32 * gv + 8] = ((values[32 * ia + 8] & values[32 * ib + 8]) | ((values[32 * ia + 8] ^ values[32 * ib + 8]) & values[32 * ic + 8])) ^ vo
        values[32 * gv + 24] = ((values[32 * ia + 24] & values[32 * ib + 24]) | ((values[32 * ia + 24] ^ values[32 * ib + 24]) & values[32 * ic + 24])) ^ vo
        values[32 * gv + 1] = ((values[32 * ia + 1] & values[32 * ib + 1]) | ((values[32 * ia + 1] ^ values[32 * ib + 1]) & values[32 * ic + 1])) ^ vo
        values[32 * gv + 17] = ((values[32 * ia + 17] & values[32 * ib + 17]) | ((values[32 * ia + 17] ^ values[32 * ib + 17]) & values[32 * ic + 17])) ^ vo
        values[32 * gv + 9] = ((values[32 * ia + 9] & values[32 * ib + 9]) | ((values[32 * ia + 9] ^ values[32 * ib + 9]) & values[32 * ic + 9])) ^ vo
        values[32 * gv + 25] = ((values[32 * ia + 25] & values[32 * ib + 25]) | ((values[32 * ia + 25] ^ values[32 * ib + 25]) & values[32 * ic + 25])) ^ vo
        values[32 * gv + 2] = ((values[32 * ia + 2] & values[32 * ib + 2]) | ((values[32 * ia + 2] ^ values[32 * ib + 2]) & values[32 * ic + 2])) ^ vo
        values[32 * gv + 18] = ((values[32 * ia + 18] & values[32 * ib + 18]) | ((values[32 * ia + 18] ^ values[32 * ib + 18]) & values[32 * ic + 18])) ^ vo
        values[32 * gv + 10] = ((values[32 * ia + 10] & values[32 * ib + 10]) | ((values[32 * ia + 10] ^ values[32 * ib + 10]) & values[32 * ic + 10])) ^ vo
        values[32 * gv + 26] = ((values[32 * ia + 26] & values[32 * ib + 26]) | ((values[32 * ia + 26] ^ values[32 * ib + 26]) & values[32 * ic + 26])) ^ vo
        values[32 * gv + 3] = ((values[32 * ia + 3] & values[32 * ib + 3]) | ((values[32 * ia + 3] ^ values[32 * ib + 3]) & values[32 * ic + 3])) ^ vo
        values[32 * gv + 19] = ((values[32 * ia + 19] & values[32 * ib + 19]) | ((values[32 * ia + 19] ^ values[32 * ib + 19]) & values[32 * ic + 19])) ^ vo
        values[32 * gv + 11] = ((values[32 * ia + 11] & values[32 * ib + 11]) | ((values[32 * ia + 11] ^ values[32 * ib + 11]) & values[32 * ic + 11])) ^ vo
        values[32 * gv + 27] = ((values[32 * ia + 27] & values[32 * ib + 27]) | ((values[32 * ia + 27] ^ values[32 * ib + 27]) & values[32 * ic + 27])) ^ vo
        values[32 * gv + 4] = ((values[32 * ia + 4] & values[32 * ib + 4]) | ((values[32 * ia + 4] ^ values[32 * ib + 4]) & values[32 * ic + 4])) ^ vo
        values[32 * gv + 20] = ((values[32 * ia + 20] & values[32 * ib + 20]) | ((values[32 * ia + 20] ^ values[32 * ib + 20]) & values[32 * ic + 20])) ^ vo
        values[32 * gv + 12] = ((values[32 * ia + 12] & values[32 * ib + 12]) | ((values[32 * ia + 12] ^ values[32 * ib + 12]) & values[32 * ic + 12])) ^ vo
        values[32 * gv + 28] = ((values[32 * ia + 28] & values[32 * ib + 28]) | ((values[32 * ia + 28] ^ values[32 * ib + 28]) & values[32 * ic + 28])) ^ vo
        values[32 * gv + 5] = ((values[32 * ia + 5] & values[32 * ib + 5]) | ((values[32 * ia + 5] ^ values[32 * ib + 5]) & values[32 * ic + 5])) ^ vo
        values[32 * gv + 21] = ((values[32 * ia + 21] & values[32 * ib + 21]) | ((values[32 * ia + 21] ^ values[32 * ib + 21]) & values[32 * ic + 21])) ^ vo
        values[32 * gv + 13] = ((values[32 * ia + 13] & values[32 * ib + 13]) | ((values[32 * ia + 13] ^ values[32 * ib + 13]) & values[32 * ic + 13])) ^ vo
        values[32 * gv + 29] = ((values[32 * ia + 29] & values[32 * ib + 29]) | ((values[32 * ia + 29] ^ values[32 * ib + 29]) & values[32 * ic + 29])) ^ vo
        values[32 * gv + 6] = ((values[32 * ia + 6] & values[32 * ib + 6]) | ((values[32 * ia + 6] ^ values[32 * ib + 6]) & values[32 * ic + 6])) ^ vo
        values[32 * gv + 22] = ((values[32 * ia + 22] & values[32 * ib + 22]) | ((values[32 * ia + 22] ^ values[32 * ib + 22]) & values[32 * ic + 22])) ^ vo
        values[32 * gv + 14] = ((values[32 * ia + 14] & values[32 * ib + 14]) | ((values[32 * ia + 14] ^ values[32 * ib + 14]) & values[32 * ic + 14])) ^ vo
        values[32 * gv + 30] = ((values[32 * ia + 30] & values[32 * ib + 30]) | ((values[32 * ia + 30] ^ values[32 * ib + 30]) & values[32 * ic + 30])) ^ vo
        values[32 * gv + 7] = ((values[32 * ia + 7] & values[32 * ib + 7]) | ((values[32 * ia + 7] ^ values[32 * ib + 7]) & values[32 * ic + 7])) ^ vo
        values[32 * gv + 23] = ((values[32 * ia + 23] & values[32 * ib + 23]) | ((values[32 * ia + 23] ^ values[32 * ib + 23]) & values[32 * ic + 23])) ^ vo
        values[32 * gv + 15] = ((values[32 * ia + 15] & values[32 * ib + 15]) | ((values[32 * ia + 15] ^ values[32 * ib + 15]) & values[32 * ic + 15])) ^ vo
        values[32 * gv + 31] = ((values[32 * ia + 31] & values[32 * ib + 31]) | ((values[32 * ia + 31] ^ values[32 * ib + 31]) & values[32 * ic + 31])) ^ vo
      elsif op == 4
        ic = program[8 * ci + 3]; vo = program[8 * ci + 6]
        values[32 * gv + 0] = ((values[32 * ic + 0] & values[32 * ib + 0]) | ((-1 ^ values[32 * ic + 0]) & values[32 * ia + 0])) ^ vo
        values[32 * gv + 16] = ((values[32 * ic + 16] & values[32 * ib + 16]) | ((-1 ^ values[32 * ic + 16]) & values[32 * ia + 16])) ^ vo
        values[32 * gv + 8] = ((values[32 * ic + 8] & values[32 * ib + 8]) | ((-1 ^ values[32 * ic + 8]) & values[32 * ia + 8])) ^ vo
        values[32 * gv + 24] = ((values[32 * ic + 24] & values[32 * ib + 24]) | ((-1 ^ values[32 * ic + 24]) & values[32 * ia + 24])) ^ vo
        values[32 * gv + 1] = ((values[32 * ic + 1] & values[32 * ib + 1]) | ((-1 ^ values[32 * ic + 1]) & values[32 * ia + 1])) ^ vo
        values[32 * gv + 17] = ((values[32 * ic + 17] & values[32 * ib + 17]) | ((-1 ^ values[32 * ic + 17]) & values[32 * ia + 17])) ^ vo
        values[32 * gv + 9] = ((values[32 * ic + 9] & values[32 * ib + 9]) | ((-1 ^ values[32 * ic + 9]) & values[32 * ia + 9])) ^ vo
        values[32 * gv + 25] = ((values[32 * ic + 25] & values[32 * ib + 25]) | ((-1 ^ values[32 * ic + 25]) & values[32 * ia + 25])) ^ vo
        values[32 * gv + 2] = ((values[32 * ic + 2] & values[32 * ib + 2]) | ((-1 ^ values[32 * ic + 2]) & values[32 * ia + 2])) ^ vo
        values[32 * gv + 18] = ((values[32 * ic + 18] & values[32 * ib + 18]) | ((-1 ^ values[32 * ic + 18]) & values[32 * ia + 18])) ^ vo
        values[32 * gv + 10] = ((values[32 * ic + 10] & values[32 * ib + 10]) | ((-1 ^ values[32 * ic + 10]) & values[32 * ia + 10])) ^ vo
        values[32 * gv + 26] = ((values[32 * ic + 26] & values[32 * ib + 26]) | ((-1 ^ values[32 * ic + 26]) & values[32 * ia + 26])) ^ vo
        values[32 * gv + 3] = ((values[32 * ic + 3] & values[32 * ib + 3]) | ((-1 ^ values[32 * ic + 3]) & values[32 * ia + 3])) ^ vo
        values[32 * gv + 19] = ((values[32 * ic + 19] & values[32 * ib + 19]) | ((-1 ^ values[32 * ic + 19]) & values[32 * ia + 19])) ^ vo
        values[32 * gv + 11] = ((values[32 * ic + 11] & values[32 * ib + 11]) | ((-1 ^ values[32 * ic + 11]) & values[32 * ia + 11])) ^ vo
        values[32 * gv + 27] = ((values[32 * ic + 27] & values[32 * ib + 27]) | ((-1 ^ values[32 * ic + 27]) & values[32 * ia + 27])) ^ vo
        values[32 * gv + 4] = ((values[32 * ic + 4] & values[32 * ib + 4]) | ((-1 ^ values[32 * ic + 4]) & values[32 * ia + 4])) ^ vo
        values[32 * gv + 20] = ((values[32 * ic + 20] & values[32 * ib + 20]) | ((-1 ^ values[32 * ic + 20]) & values[32 * ia + 20])) ^ vo
        values[32 * gv + 12] = ((values[32 * ic + 12] & values[32 * ib + 12]) | ((-1 ^ values[32 * ic + 12]) & values[32 * ia + 12])) ^ vo
        values[32 * gv + 28] = ((values[32 * ic + 28] & values[32 * ib + 28]) | ((-1 ^ values[32 * ic + 28]) & values[32 * ia + 28])) ^ vo
        values[32 * gv + 5] = ((values[32 * ic + 5] & values[32 * ib + 5]) | ((-1 ^ values[32 * ic + 5]) & values[32 * ia + 5])) ^ vo
        values[32 * gv + 21] = ((values[32 * ic + 21] & values[32 * ib + 21]) | ((-1 ^ values[32 * ic + 21]) & values[32 * ia + 21])) ^ vo
        values[32 * gv + 13] = ((values[32 * ic + 13] & values[32 * ib + 13]) | ((-1 ^ values[32 * ic + 13]) & values[32 * ia + 13])) ^ vo
        values[32 * gv + 29] = ((values[32 * ic + 29] & values[32 * ib + 29]) | ((-1 ^ values[32 * ic + 29]) & values[32 * ia + 29])) ^ vo
        values[32 * gv + 6] = ((values[32 * ic + 6] & values[32 * ib + 6]) | ((-1 ^ values[32 * ic + 6]) & values[32 * ia + 6])) ^ vo
        values[32 * gv + 22] = ((values[32 * ic + 22] & values[32 * ib + 22]) | ((-1 ^ values[32 * ic + 22]) & values[32 * ia + 22])) ^ vo
        values[32 * gv + 14] = ((values[32 * ic + 14] & values[32 * ib + 14]) | ((-1 ^ values[32 * ic + 14]) & values[32 * ia + 14])) ^ vo
        values[32 * gv + 30] = ((values[32 * ic + 30] & values[32 * ib + 30]) | ((-1 ^ values[32 * ic + 30]) & values[32 * ia + 30])) ^ vo
        values[32 * gv + 7] = ((values[32 * ic + 7] & values[32 * ib + 7]) | ((-1 ^ values[32 * ic + 7]) & values[32 * ia + 7])) ^ vo
        values[32 * gv + 23] = ((values[32 * ic + 23] & values[32 * ib + 23]) | ((-1 ^ values[32 * ic + 23]) & values[32 * ia + 23])) ^ vo
        values[32 * gv + 15] = ((values[32 * ic + 15] & values[32 * ib + 15]) | ((-1 ^ values[32 * ic + 15]) & values[32 * ia + 15])) ^ vo
        values[32 * gv + 31] = ((values[32 * ic + 31] & values[32 * ib + 31]) | ((-1 ^ values[32 * ic + 31]) & values[32 * ia + 31])) ^ vo
      elsif op == 6
        values[32 * gv + 0] = -1 ^ (values[32 * ia + 0] & values[32 * ib + 0])
        values[32 * gv + 1] = -1 ^ (values[32 * ia + 1] & values[32 * ib + 1])
        values[32 * gv + 2] = -1 ^ (values[32 * ia + 2] & values[32 * ib + 2])
        values[32 * gv + 3] = -1 ^ (values[32 * ia + 3] & values[32 * ib + 3])
        values[32 * gv + 4] = -1 ^ (values[32 * ia + 4] & values[32 * ib + 4])
        values[32 * gv + 5] = -1 ^ (values[32 * ia + 5] & values[32 * ib + 5])
        values[32 * gv + 6] = -1 ^ (values[32 * ia + 6] & values[32 * ib + 6])
        values[32 * gv + 7] = -1 ^ (values[32 * ia + 7] & values[32 * ib + 7])
        values[32 * gv + 8] = -1 ^ (values[32 * ia + 8] & values[32 * ib + 8])
        values[32 * gv + 9] = -1 ^ (values[32 * ia + 9] & values[32 * ib + 9])
        values[32 * gv + 10] = -1 ^ (values[32 * ia + 10] & values[32 * ib + 10])
        values[32 * gv + 11] = -1 ^ (values[32 * ia + 11] & values[32 * ib + 11])
        values[32 * gv + 12] = -1 ^ (values[32 * ia + 12] & values[32 * ib + 12])
        values[32 * gv + 13] = -1 ^ (values[32 * ia + 13] & values[32 * ib + 13])
        values[32 * gv + 14] = -1 ^ (values[32 * ia + 14] & values[32 * ib + 14])
        values[32 * gv + 15] = -1 ^ (values[32 * ia + 15] & values[32 * ib + 15])
        values[32 * gv + 16] = -1 ^ (values[32 * ia + 16] & values[32 * ib + 16])
        values[32 * gv + 17] = -1 ^ (values[32 * ia + 17] & values[32 * ib + 17])
        values[32 * gv + 18] = -1 ^ (values[32 * ia + 18] & values[32 * ib + 18])
        values[32 * gv + 19] = -1 ^ (values[32 * ia + 19] & values[32 * ib + 19])
        values[32 * gv + 20] = -1 ^ (values[32 * ia + 20] & values[32 * ib + 20])
        values[32 * gv + 21] = -1 ^ (values[32 * ia + 21] & values[32 * ib + 21])
        values[32 * gv + 22] = -1 ^ (values[32 * ia + 22] & values[32 * ib + 22])
        values[32 * gv + 23] = -1 ^ (values[32 * ia + 23] & values[32 * ib + 23])
        values[32 * gv + 24] = -1 ^ (values[32 * ia + 24] & values[32 * ib + 24])
        values[32 * gv + 25] = -1 ^ (values[32 * ia + 25] & values[32 * ib + 25])
        values[32 * gv + 26] = -1 ^ (values[32 * ia + 26] & values[32 * ib + 26])
        values[32 * gv + 27] = -1 ^ (values[32 * ia + 27] & values[32 * ib + 27])
        values[32 * gv + 28] = -1 ^ (values[32 * ia + 28] & values[32 * ib + 28])
        values[32 * gv + 29] = -1 ^ (values[32 * ia + 29] & values[32 * ib + 29])
        values[32 * gv + 30] = -1 ^ (values[32 * ia + 30] & values[32 * ib + 30])
        values[32 * gv + 31] = -1 ^ (values[32 * ia + 31] & values[32 * ib + 31])
      elsif op == 7
        values[32 * gv + 0] = values[32 * ia + 0] & (-1 ^ values[32 * ib + 0])
        values[32 * gv + 1] = values[32 * ia + 1] & (-1 ^ values[32 * ib + 1])
        values[32 * gv + 2] = values[32 * ia + 2] & (-1 ^ values[32 * ib + 2])
        values[32 * gv + 3] = values[32 * ia + 3] & (-1 ^ values[32 * ib + 3])
        values[32 * gv + 4] = values[32 * ia + 4] & (-1 ^ values[32 * ib + 4])
        values[32 * gv + 5] = values[32 * ia + 5] & (-1 ^ values[32 * ib + 5])
        values[32 * gv + 6] = values[32 * ia + 6] & (-1 ^ values[32 * ib + 6])
        values[32 * gv + 7] = values[32 * ia + 7] & (-1 ^ values[32 * ib + 7])
        values[32 * gv + 8] = values[32 * ia + 8] & (-1 ^ values[32 * ib + 8])
        values[32 * gv + 9] = values[32 * ia + 9] & (-1 ^ values[32 * ib + 9])
        values[32 * gv + 10] = values[32 * ia + 10] & (-1 ^ values[32 * ib + 10])
        values[32 * gv + 11] = values[32 * ia + 11] & (-1 ^ values[32 * ib + 11])
        values[32 * gv + 12] = values[32 * ia + 12] & (-1 ^ values[32 * ib + 12])
        values[32 * gv + 13] = values[32 * ia + 13] & (-1 ^ values[32 * ib + 13])
        values[32 * gv + 14] = values[32 * ia + 14] & (-1 ^ values[32 * ib + 14])
        values[32 * gv + 15] = values[32 * ia + 15] & (-1 ^ values[32 * ib + 15])
        values[32 * gv + 16] = values[32 * ia + 16] & (-1 ^ values[32 * ib + 16])
        values[32 * gv + 17] = values[32 * ia + 17] & (-1 ^ values[32 * ib + 17])
        values[32 * gv + 18] = values[32 * ia + 18] & (-1 ^ values[32 * ib + 18])
        values[32 * gv + 19] = values[32 * ia + 19] & (-1 ^ values[32 * ib + 19])
        values[32 * gv + 20] = values[32 * ia + 20] & (-1 ^ values[32 * ib + 20])
        values[32 * gv + 21] = values[32 * ia + 21] & (-1 ^ values[32 * ib + 21])
        values[32 * gv + 22] = values[32 * ia + 22] & (-1 ^ values[32 * ib + 22])
        values[32 * gv + 23] = values[32 * ia + 23] & (-1 ^ values[32 * ib + 23])
        values[32 * gv + 24] = values[32 * ia + 24] & (-1 ^ values[32 * ib + 24])
        values[32 * gv + 25] = values[32 * ia + 25] & (-1 ^ values[32 * ib + 25])
        values[32 * gv + 26] = values[32 * ia + 26] & (-1 ^ values[32 * ib + 26])
        values[32 * gv + 27] = values[32 * ia + 27] & (-1 ^ values[32 * ib + 27])
        values[32 * gv + 28] = values[32 * ia + 28] & (-1 ^ values[32 * ib + 28])
        values[32 * gv + 29] = values[32 * ia + 29] & (-1 ^ values[32 * ib + 29])
        values[32 * gv + 30] = values[32 * ia + 30] & (-1 ^ values[32 * ib + 30])
        values[32 * gv + 31] = values[32 * ia + 31] & (-1 ^ values[32 * ib + 31])
      elsif op == 8
        values[32 * gv + 0] = (-1 ^ values[32 * ia + 0]) | values[32 * ib + 0]
        values[32 * gv + 1] = (-1 ^ values[32 * ia + 1]) | values[32 * ib + 1]
        values[32 * gv + 2] = (-1 ^ values[32 * ia + 2]) | values[32 * ib + 2]
        values[32 * gv + 3] = (-1 ^ values[32 * ia + 3]) | values[32 * ib + 3]
        values[32 * gv + 4] = (-1 ^ values[32 * ia + 4]) | values[32 * ib + 4]
        values[32 * gv + 5] = (-1 ^ values[32 * ia + 5]) | values[32 * ib + 5]
        values[32 * gv + 6] = (-1 ^ values[32 * ia + 6]) | values[32 * ib + 6]
        values[32 * gv + 7] = (-1 ^ values[32 * ia + 7]) | values[32 * ib + 7]
        values[32 * gv + 8] = (-1 ^ values[32 * ia + 8]) | values[32 * ib + 8]
        values[32 * gv + 9] = (-1 ^ values[32 * ia + 9]) | values[32 * ib + 9]
        values[32 * gv + 10] = (-1 ^ values[32 * ia + 10]) | values[32 * ib + 10]
        values[32 * gv + 11] = (-1 ^ values[32 * ia + 11]) | values[32 * ib + 11]
        values[32 * gv + 12] = (-1 ^ values[32 * ia + 12]) | values[32 * ib + 12]
        values[32 * gv + 13] = (-1 ^ values[32 * ia + 13]) | values[32 * ib + 13]
        values[32 * gv + 14] = (-1 ^ values[32 * ia + 14]) | values[32 * ib + 14]
        values[32 * gv + 15] = (-1 ^ values[32 * ia + 15]) | values[32 * ib + 15]
        values[32 * gv + 16] = (-1 ^ values[32 * ia + 16]) | values[32 * ib + 16]
        values[32 * gv + 17] = (-1 ^ values[32 * ia + 17]) | values[32 * ib + 17]
        values[32 * gv + 18] = (-1 ^ values[32 * ia + 18]) | values[32 * ib + 18]
        values[32 * gv + 19] = (-1 ^ values[32 * ia + 19]) | values[32 * ib + 19]
        values[32 * gv + 20] = (-1 ^ values[32 * ia + 20]) | values[32 * ib + 20]
        values[32 * gv + 21] = (-1 ^ values[32 * ia + 21]) | values[32 * ib + 21]
        values[32 * gv + 22] = (-1 ^ values[32 * ia + 22]) | values[32 * ib + 22]
        values[32 * gv + 23] = (-1 ^ values[32 * ia + 23]) | values[32 * ib + 23]
        values[32 * gv + 24] = (-1 ^ values[32 * ia + 24]) | values[32 * ib + 24]
        values[32 * gv + 25] = (-1 ^ values[32 * ia + 25]) | values[32 * ib + 25]
        values[32 * gv + 26] = (-1 ^ values[32 * ia + 26]) | values[32 * ib + 26]
        values[32 * gv + 27] = (-1 ^ values[32 * ia + 27]) | values[32 * ib + 27]
        values[32 * gv + 28] = (-1 ^ values[32 * ia + 28]) | values[32 * ib + 28]
        values[32 * gv + 29] = (-1 ^ values[32 * ia + 29]) | values[32 * ib + 29]
        values[32 * gv + 30] = (-1 ^ values[32 * ia + 30]) | values[32 * ib + 30]
        values[32 * gv + 31] = (-1 ^ values[32 * ia + 31]) | values[32 * ib + 31]
      elsif op == 9
        values[32 * gv + 0] = values[32 * ia + 0] | values[32 * ib + 0]
        values[32 * gv + 1] = values[32 * ia + 1] | values[32 * ib + 1]
        values[32 * gv + 2] = values[32 * ia + 2] | values[32 * ib + 2]
        values[32 * gv + 3] = values[32 * ia + 3] | values[32 * ib + 3]
        values[32 * gv + 4] = values[32 * ia + 4] | values[32 * ib + 4]
        values[32 * gv + 5] = values[32 * ia + 5] | values[32 * ib + 5]
        values[32 * gv + 6] = values[32 * ia + 6] | values[32 * ib + 6]
        values[32 * gv + 7] = values[32 * ia + 7] | values[32 * ib + 7]
        values[32 * gv + 8] = values[32 * ia + 8] | values[32 * ib + 8]
        values[32 * gv + 9] = values[32 * ia + 9] | values[32 * ib + 9]
        values[32 * gv + 10] = values[32 * ia + 10] | values[32 * ib + 10]
        values[32 * gv + 11] = values[32 * ia + 11] | values[32 * ib + 11]
        values[32 * gv + 12] = values[32 * ia + 12] | values[32 * ib + 12]
        values[32 * gv + 13] = values[32 * ia + 13] | values[32 * ib + 13]
        values[32 * gv + 14] = values[32 * ia + 14] | values[32 * ib + 14]
        values[32 * gv + 15] = values[32 * ia + 15] | values[32 * ib + 15]
        values[32 * gv + 16] = values[32 * ia + 16] | values[32 * ib + 16]
        values[32 * gv + 17] = values[32 * ia + 17] | values[32 * ib + 17]
        values[32 * gv + 18] = values[32 * ia + 18] | values[32 * ib + 18]
        values[32 * gv + 19] = values[32 * ia + 19] | values[32 * ib + 19]
        values[32 * gv + 20] = values[32 * ia + 20] | values[32 * ib + 20]
        values[32 * gv + 21] = values[32 * ia + 21] | values[32 * ib + 21]
        values[32 * gv + 22] = values[32 * ia + 22] | values[32 * ib + 22]
        values[32 * gv + 23] = values[32 * ia + 23] | values[32 * ib + 23]
        values[32 * gv + 24] = values[32 * ia + 24] | values[32 * ib + 24]
        values[32 * gv + 25] = values[32 * ia + 25] | values[32 * ib + 25]
        values[32 * gv + 26] = values[32 * ia + 26] | values[32 * ib + 26]
        values[32 * gv + 27] = values[32 * ia + 27] | values[32 * ib + 27]
        values[32 * gv + 28] = values[32 * ia + 28] | values[32 * ib + 28]
        values[32 * gv + 29] = values[32 * ia + 29] | values[32 * ib + 29]
        values[32 * gv + 30] = values[32 * ia + 30] | values[32 * ib + 30]
        values[32 * gv + 31] = values[32 * ia + 31] | values[32 * ib + 31]
      elsif op == 10
        values[32 * gv + 0] = -1 ^ (values[32 * ia + 0] | values[32 * ib + 0])
        values[32 * gv + 1] = -1 ^ (values[32 * ia + 1] | values[32 * ib + 1])
        values[32 * gv + 2] = -1 ^ (values[32 * ia + 2] | values[32 * ib + 2])
        values[32 * gv + 3] = -1 ^ (values[32 * ia + 3] | values[32 * ib + 3])
        values[32 * gv + 4] = -1 ^ (values[32 * ia + 4] | values[32 * ib + 4])
        values[32 * gv + 5] = -1 ^ (values[32 * ia + 5] | values[32 * ib + 5])
        values[32 * gv + 6] = -1 ^ (values[32 * ia + 6] | values[32 * ib + 6])
        values[32 * gv + 7] = -1 ^ (values[32 * ia + 7] | values[32 * ib + 7])
        values[32 * gv + 8] = -1 ^ (values[32 * ia + 8] | values[32 * ib + 8])
        values[32 * gv + 9] = -1 ^ (values[32 * ia + 9] | values[32 * ib + 9])
        values[32 * gv + 10] = -1 ^ (values[32 * ia + 10] | values[32 * ib + 10])
        values[32 * gv + 11] = -1 ^ (values[32 * ia + 11] | values[32 * ib + 11])
        values[32 * gv + 12] = -1 ^ (values[32 * ia + 12] | values[32 * ib + 12])
        values[32 * gv + 13] = -1 ^ (values[32 * ia + 13] | values[32 * ib + 13])
        values[32 * gv + 14] = -1 ^ (values[32 * ia + 14] | values[32 * ib + 14])
        values[32 * gv + 15] = -1 ^ (values[32 * ia + 15] | values[32 * ib + 15])
        values[32 * gv + 16] = -1 ^ (values[32 * ia + 16] | values[32 * ib + 16])
        values[32 * gv + 17] = -1 ^ (values[32 * ia + 17] | values[32 * ib + 17])
        values[32 * gv + 18] = -1 ^ (values[32 * ia + 18] | values[32 * ib + 18])
        values[32 * gv + 19] = -1 ^ (values[32 * ia + 19] | values[32 * ib + 19])
        values[32 * gv + 20] = -1 ^ (values[32 * ia + 20] | values[32 * ib + 20])
        values[32 * gv + 21] = -1 ^ (values[32 * ia + 21] | values[32 * ib + 21])
        values[32 * gv + 22] = -1 ^ (values[32 * ia + 22] | values[32 * ib + 22])
        values[32 * gv + 23] = -1 ^ (values[32 * ia + 23] | values[32 * ib + 23])
        values[32 * gv + 24] = -1 ^ (values[32 * ia + 24] | values[32 * ib + 24])
        values[32 * gv + 25] = -1 ^ (values[32 * ia + 25] | values[32 * ib + 25])
        values[32 * gv + 26] = -1 ^ (values[32 * ia + 26] | values[32 * ib + 26])
        values[32 * gv + 27] = -1 ^ (values[32 * ia + 27] | values[32 * ib + 27])
        values[32 * gv + 28] = -1 ^ (values[32 * ia + 28] | values[32 * ib + 28])
        values[32 * gv + 29] = -1 ^ (values[32 * ia + 29] | values[32 * ib + 29])
        values[32 * gv + 30] = -1 ^ (values[32 * ia + 30] | values[32 * ib + 30])
        values[32 * gv + 31] = -1 ^ (values[32 * ia + 31] | values[32 * ib + 31])
      else
        wassat_miter32_eval_gate_packed(values, gv,
                                  gates,
                                  g_cl_off, g_cl_cnt, cl_l_off, cl_l_len, cl_lits)
      ci += 1
    if (values[32 * out_var + 0] | values[32 * out_var + 1] | values[32 * out_var + 2] | values[32 * out_var + 3] | values[32 * out_var + 4] | values[32 * out_var + 5] | values[32 * out_var + 6] | values[32 * out_var + 7] | values[32 * out_var + 8] | values[32 * out_var + 9] | values[32 * out_var + 10] | values[32 * out_var + 11] | values[32 * out_var + 12] | values[32 * out_var + 13] | values[32 * out_var + 14] | values[32 * out_var + 15] | values[32 * out_var + 16] | values[32 * out_var + 17] | values[32 * out_var + 18] | values[32 * out_var + 19] | values[32 * out_var + 20] | values[32 * out_var + 21] | values[32 * out_var + 22] | values[32 * out_var + 23] | values[32 * out_var + 24] | values[32 * out_var + 25] | values[32 * out_var + 26] | values[32 * out_var + 27] | values[32 * out_var + 28] | values[32 * out_var + 29] | values[32 * out_var + 30] | values[32 * out_var + 31]) != 0
      any_sat[0] = 1
      return s - b_lo + 1
    s += 1
  b_hi - b_lo


# Attribute completed word-gate work to opcodes after workers join.
-> wassat_miter_gray_op_work(counts, ops, topo, n_gates,
                            cone_gates, cone_off, cone_len,
                            first, batches, words) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64 i64) i64
  return 0 if batches <= 0
  i = 0
  while i < n_gates
    counts[ops[topo[i]]] += words
    i += 1
  last = first + batches - 1
  half = 1
  k = 0
  while k < cone_len.size
    period = 2 * half
    flips = (last + half) / period - (first + half) / period
    weight = flips * words
    if weight != 0
      i = cone_off[k]
      finish = i + cone_len[k]
      while i < finish
        counts[ops[cone_gates[i]]] += weight
        i += 1
    half = period
    k += 1
  0

# Keep every cone's repeated instruction stream adjacent in memory.
-> wassat_miter_pack_cones(cones, gates, program, count) (i64[] i64[] i64[] i64) i64
  i = 0
  while i < count
    gv = cones[i]
    j = 0
    while j < 7
      program[8 * i + j] = gates[8 * gv + j]
      j += 1
    # Normalize all AND input/output polarities into simple bitwise kernels.
    if gates[8 * gv] == 2
      va = gates[8 * gv + 4]; vb = gates[8 * gv + 5]; vo = gates[8 * gv + 6]
      encoded = 2
      if va == vb
        if va == 0
          encoded = vo == 0 ? 2 : 6
        else
          encoded = vo == 0 ? 10 : 9
      else
        encoded = vo == 0 ? 7 : 8
        if va != 0
          program[8 * i + 1] = gates[8 * gv + 2]
          program[8 * i + 2] = gates[8 * gv + 1]
      program[8 * i] = encoded
    program[8 * i + 7] = gv
    i += 1
  0

# Count only repeated Gray updates; the first full-graph batch uses the
# original gate evaluator and is already included in circuit.ops.
-> wassat_miter_gray_program_work(counts, program, cone_off, cone_len,
                                 first, batches, words) (i64[] i64[] i64[] i64[] i64 i64 i64) i64
  return 0 if batches <= 1
  last = first + batches - 1
  half = 1
  k = 0
  while k < cone_len.size
    period = 2 * half
    flips = (last + half) / period - (first + half) / period
    weight = flips * words
    if weight != 0
      i = cone_off[k]
      finish = i + cone_len[k]
      while i < finish
        counts[program[8 * i]] += weight
        i += 1
    half = period
    k += 1
  0
