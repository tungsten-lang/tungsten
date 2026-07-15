use flipfleet_ternary_worker

# Exact three-term shared-factor tunnel for the signed {-1,0,1} worker.
#
# If three rank-one terms share a projective factor q, write their remaining
# subtotal as
#
#             q * sum_i a_i b_i.
#
# For a unimodular 3x3 integer matrix M,
#
#       A' = A M,                 B' = M^-1 B
#
# preserves that subtotal exactly.  The five matrices below represent the
# genuinely three-way double cosets among 3x3 matrices whose entries and
# inverse entries are all in {-1,0,1}; the omitted nontrivial coset is just a
# two-term elementary flip plus an idle third term.  Input permutations and
# the eight independent source gauges cover the other representatives.
#
# Crucially, each three-vector sum is evaluated as one endpoint.  We do not
# reject an intermediate +/-2 if the third summand cancels it.  That is what
# lets this move cross a hole in the legal two-term flip graph.


# Two-bit coefficient encoding: 0 -> 0, 1 -> +1, 2 -> -1.  Entries are packed
# row-major.  Matrix codes and inverse codes were exhaustively filtered from
# all 3^9 ternary matrices by det(M) in {-1,+1} and ternary M^-1.
-> fft_gl3_decode(code, index) (i64 i64) i64
  digit = (code >> (2 * index)) & 3 ## i64
  if digit == 2
    return 0 - 1
  digit

-> fft_gl3_matrix_code(kind) (i64) i64
  code = 32938 ## i64
  if kind == 1
    code = 10378
  if kind == 2
    code = 34954
  if kind == 3
    code = 8874
  if kind == 4
    code = 139946
  code

-> fft_gl3_inverse_code(kind) (i64) i64
  code = 92168 ## i64
  if kind == 1
    code = 99488
  if kind == 2
    code = 170002
  if kind == 3
    code = 26144
  if kind == 4
    code = 25769
  code

-> fft_gl3_matrix(kind, row, column) (i64 i64 i64) i64
  fft_gl3_decode(fft_gl3_matrix_code(kind), row * 3 + column)

-> fft_gl3_inverse(kind, row, column) (i64 i64 i64) i64
  fft_gl3_decode(fft_gl3_inverse_code(kind), row * 3 + column)

# Directly form c0*a0 + c1*a1 + c2*a2.  The result is written to the worker's
# standard signed-vector scratch pair st[44]/st[45].  st[46] is sticky for one
# GL3 attempt and records that at least one pair of summands has magnitude two
# while the complete endpoint is ternary.  This is cancellation telemetry,
# not by itself proof that every ordering of legal pair flips is blocked.
-> fft_gl3_vector_sum3(st, a0p,a0n,c0, a1p,a1n,c1, a2p,a2n,c2) (i64[] i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
  positive = 0 ## i64
  negative = 0 ## i64
  ok = 1 ## i64
  bit = 0 ## i64
  while bit < st[3] && ok == 1
    x0 = c0 * fft_coefficient(a0p,a0n,bit) ## i64
    x1 = c1 * fft_coefficient(a1p,a1n,bit) ## i64
    x2 = c2 * fft_coefficient(a2p,a2n,bit) ## i64
    value = x0 + x1 + x2 ## i64
    if value < 0 - 1 || value > 1
      ok = 0
    if ok == 1
      if value == 1
        positive = positive | (1 << bit)
      if value == 0 - 1
        negative = negative | (1 << bit)
      if value >= 0 - 1 && value <= 1
        if x0 + x1 < 0 - 1 || x0 + x1 > 1 || x0 + x2 < 0 - 1 || x0 + x2 > 1 || x1 + x2 < 0 - 1 || x1 + x2 > 1
          st[46] = 1
    bit += 1
  st[44] = positive
  st[45] = negative
  ok

-> fft_gl3_restore_three(st, slots, old) (i64[] i64[] i64[]) i64
  j = 0 ## i64
  while j < 3
    axis = 0 ## i64
    while axis < 6
      st[st[32 + axis] + slots[j]] = old[j * 6 + axis]
      axis += 1
    j += 1
  1

# Apply one exact endpoint.  wander < 0 means strict density descent;
# wander == 0 uses the worker's work-zone slack; wander > 0 accepts any novel
# ternary endpoint.  Header counters reserved by this isolated module:
#   48 attempts, 49 accepted, 50 no shared triple, 51 endpoint reject,
#   52 accepted endpoints that used three-way cancellation, 53 no-op reject.
-> fft_gl3_apply(st, slot0,slot1,slot2, shared_axis,kind,gauge_bits,wander) (i64[] i64 i64 i64 i64 i64 i64 i64) i64
  st[48] = st[48] + 1
  if slot0 < 0 || slot1 < 0 || slot2 < 0 || slot0 >= st[5] || slot1 >= st[5] || slot2 >= st[5] || slot0 == slot1 || slot0 == slot2 || slot1 == slot2 || shared_axis < 0 || shared_axis > 2 || kind < 0 || kind > 4
    st[51] = st[51] + 1
    return 0

  slots = i64[3]
  slots[0] = slot0
  slots[1] = slot1
  slots[2] = slot2
  old = i64[18]
  j = 0 ## i64
  while j < 3
    axis = 0 ## i64
    while axis < 6
      old[j * 6 + axis] = st[st[32 + axis] + slots[j]]
      axis += 1
    j += 1

  relation = i64[3]
  relation[0] = 1
  relation[1] = fft_pair_relation(st,shared_axis,slot0,slot1)
  relation[2] = fft_pair_relation(st,shared_axis,slot0,slot2)
  if relation[1] == 0 || relation[2] == 0
    st[50] = st[50] + 1
    return 0

  first_axis = 1 ## i64
  second_axis = 2 ## i64
  if shared_axis == 1
    first_axis = 0
    second_axis = 2
  if shared_axis == 2
    first_axis = 0
    second_axis = 1
  first_base = 32 + 2 * first_axis ## i64
  second_base = 32 + 2 * second_axis ## i64
  shared_base = 32 + 2 * shared_axis ## i64

  gauge = i64[3]
  j = 0
  while j < 3
    gauge[j] = 0 - 1
    if ((gauge_bits >> j) & 1) != 0
      gauge[j] = 1
    j += 1

  outp = i64[6]
  outn = i64[6]
  st[46] = 0
  endpoint_ok = 1 ## i64
  column = 0 ## i64
  while column < 3 && endpoint_ok == 1
    c0 = relation[0] * gauge[0] * fft_gl3_matrix(kind,0,column) ## i64
    c1 = relation[1] * gauge[1] * fft_gl3_matrix(kind,1,column) ## i64
    c2 = relation[2] * gauge[2] * fft_gl3_matrix(kind,2,column) ## i64
    endpoint_ok = fft_gl3_vector_sum3(st,
      old[first_axis * 2],old[first_axis * 2 + 1],c0,
      old[6 + first_axis * 2],old[6 + first_axis * 2 + 1],c1,
      old[12 + first_axis * 2],old[12 + first_axis * 2 + 1],c2)
    if endpoint_ok == 1
      outp[column * 2] = st[44]
      outn[column * 2] = st[45]
      if (st[44] | st[45]) == 0
        endpoint_ok = 0
    if endpoint_ok == 1
      c0 = gauge[0] * fft_gl3_inverse(kind,column,0)
      c1 = gauge[1] * fft_gl3_inverse(kind,column,1)
      c2 = gauge[2] * fft_gl3_inverse(kind,column,2)
      endpoint_ok = fft_gl3_vector_sum3(st,
        old[second_axis * 2],old[second_axis * 2 + 1],c0,
        old[6 + second_axis * 2],old[6 + second_axis * 2 + 1],c1,
        old[12 + second_axis * 2],old[12 + second_axis * 2 + 1],c2)
      if endpoint_ok == 1
        outp[column * 2 + 1] = st[44]
        outn[column * 2 + 1] = st[45]
        if (st[44] | st[45]) == 0
          endpoint_ok = 0
    column += 1
  if endpoint_ok == 0
    st[51] = st[51] + 1
    return 0

  old_density = fft_slot_density(st,slot0) + fft_slot_density(st,slot1) + fft_slot_density(st,slot2) ## i64
  old_fingerprint = fft_current_fingerprint(st) ## i64
  j = 0
  while j < 3
    slot = slots[j] ## i64
    st[st[shared_base] + slot] = old[shared_axis * 2]
    st[st[shared_base + 1] + slot] = old[shared_axis * 2 + 1]
    st[st[first_base] + slot] = outp[j * 2]
    st[st[first_base + 1] + slot] = outn[j * 2]
    st[st[second_base] + slot] = outp[j * 2 + 1]
    st[st[second_base + 1] + slot] = outn[j * 2 + 1]
    z = fft_canonicalize_slot(st,slot) ## i64
    j += 1
  new_fingerprint = fft_current_fingerprint(st) ## i64
  if new_fingerprint == old_fingerprint
    z = fft_gl3_restore_three(st,slots,old) ## i64
    st[53] = st[53] + 1
    return 0

  new_density = fft_slot_density(st,slot0) + fft_slot_density(st,slot1) + fft_slot_density(st,slot2) ## i64
  accept = 0 ## i64
  if wander < 0 && new_density < old_density
    accept = 1
  if wander == 0 && new_density <= old_density + st[27]
    accept = 1
  if wander > 0
    accept = 1
  if accept == 0
    z = fft_gl3_restore_three(st,slots,old) ## i64
    st[51] = st[51] + 1
    return 0

  st[20] = st[20] + new_density - old_density
  st[10] = st[10] + 1
  st[49] = st[49] + 1
  if st[46] != 0
    st[52] = st[52] + 1
  adopted = fft_maybe_adopt(st) ## i64
  if adopted < 0
    return 0 - 1
  if adopted == 2
    return 2
  1

-> fft_gl3_try(st, wander) (i64[] i64) i64
  if st[5] < 3
    st[48] = st[48] + 1
    st[50] = st[50] + 1
    return 0
  axis = fft_rand31(st) % 3 ## i64
  first = fft_rand31(st) % st[5] ## i64
  start = fft_rand31(st) % st[5] ## i64
  second = 0 - 1 ## i64
  third = 0 - 1 ## i64
  scanned = 0 ## i64
  while scanned < st[5]
    candidate = (start + scanned) % st[5] ## i64
    if candidate != first && fft_pair_relation(st,axis,first,candidate) != 0
      if second < 0
        second = candidate
      if second >= 0 && candidate != second && third < 0
        third = candidate
    scanned += 1
  if second < 0 || third < 0
    st[48] = st[48] + 1
    st[50] = st[50] + 1
    return 0
  kind = fft_rand31(st) % 5 ## i64
  gauges = fft_rand31(st) & 7 ## i64
  fft_gl3_apply(st,first,second,third,axis,kind,gauges,wander)

-> fft_gl3_permuted_slot(a,b,c, permutation, position) (i64 i64 i64 i64 i64) i64
  value = a ## i64
  if permutation == 0
    if position == 1
      value = b
    if position == 2
      value = c
  if permutation == 1
    if position == 1
      value = c
    if position == 2
      value = b
  if permutation == 2
    value = b
    if position == 1
      value = a
    if position == 2
      value = c
  if permutation == 3
    value = b
    if position == 1
      value = c
    if position == 2
      value = a
  if permutation == 4
    value = c
    if position == 1
      value = a
    if position == 2
      value = b
  if permutation == 5
    value = c
    if position == 1
      value = b
    if position == 2
      value = a
  value

# Deterministic first-improvement descent.  It restarts the complete scan
# after every strict improvement, so termination is a fixed point for this
# five-orbit GL3 catalogue (all source orders and gauges included).
-> fft_gl3_directed_descent(st) (i64[]) i64
  improvements = 0 ## i64
  changed = 1 ## i64
  while changed == 1
    changed = 0
    axis = 0 ## i64
    while axis < 3 && changed == 0
      a = 0 ## i64
      while a < st[5] - 2 && changed == 0
        b = a + 1 ## i64
        while b < st[5] - 1 && changed == 0
          if fft_pair_relation(st,axis,a,b) != 0
            c = b + 1 ## i64
            while c < st[5] && changed == 0
              if fft_pair_relation(st,axis,a,c) != 0
                permutation = 0 ## i64
                while permutation < 6 && changed == 0
                  slot0 = fft_gl3_permuted_slot(a,b,c,permutation,0) ## i64
                  slot1 = fft_gl3_permuted_slot(a,b,c,permutation,1) ## i64
                  slot2 = fft_gl3_permuted_slot(a,b,c,permutation,2) ## i64
                  kind = 0 ## i64
                  while kind < 5 && changed == 0
                    gauges = 0 ## i64
                    while gauges < 8 && changed == 0
                      result = fft_gl3_apply(st,slot0,slot1,slot2,axis,kind,gauges,0-1) ## i64
                      if result < 0
                        return 0 - 1
                      if result > 0
                        improvements += 1
                        changed = 1
                      gauges += 1
                    kind += 1
                  permutation += 1
              c += 1
          b += 1
        a += 1
      axis += 1
  improvements
