# Exact bounded atomic-flip tunnels and labeled canceling-pair catalysts.
#
# These operators deliberately keep intermediate states out of the ordinary
# objective gate.  Every individual pair flip is an exact GF(2) identity, and
# callers admit only the final endpoint after a complete tensor check.

use flipfleet_span_refactor

-> fftc_copy_terms(source_u, source_v, source_w, count, dest_u, dest_v, dest_w) (i64[] i64[] i64[] i64 i64[] i64[] i64[]) i64
  i = 0 ## i64
  while i < count
    dest_u[i] = source_u[i]
    dest_v[i] = source_v[i]
    dest_w[i] = source_w[i]
    i += 1
  count

-> fftc_same_term(u0, v0, w0, u1, v1, w1) (i64 i64 i64 i64 i64 i64) i64
  same = 0 ## i64
  if u0 == u1 && v0 == v1 && w0 == w1
    same = 1
  same

-> fftc_terms_same_set(left_u, left_v, left_w, left_count, right_u, right_v, right_w, right_count) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  if left_count != right_count
    return 0
  used = i64[right_count]
  i = 0 ## i64
  while i < left_count
    found = 0 - 1 ## i64
    j = 0 ## i64
    while j < right_count && found < 0
      if used[j] == 0
        if fftc_same_term(left_u[i], left_v[i], left_w[i], right_u[j], right_v[j], right_w[j]) == 1
          found = j
      j += 1
    if found < 0
      return 0
    used[found] = 1
    i += 1
  1

-> fftc_density(us, vs, ws, count) (i64[] i64[] i64[] i64) i64
  bits = 0 ## i64
  i = 0 ## i64
  while i < count
    bits += ffw_popcount(us[i]) + ffw_popcount(vs[i]) + ffw_popcount(ws[i])
    i += 1
  bits

# Ordered compatible-pair flip.  Keeping the order is important: the reverse
# ordering selects the other path through the same two-term identity.
-> fftc_apply_flip(us, vs, ws, count, first, second, axis) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  if first < 0 || second < 0 || first >= count || second >= count || first == second
    return 0
  if axis < 0 || axis > 2
    return 0
  first_u = us[first] ## i64
  first_v = vs[first] ## i64
  first_w = ws[first] ## i64
  second_u = us[second] ## i64
  second_v = vs[second] ## i64
  second_w = ws[second] ## i64
  if first_u == 0 || first_v == 0 || first_w == 0 || second_u == 0 || second_v == 0 || second_w == 0
    return 0
  if axis == 0 && first_u != second_u
    return 0
  if axis == 1 && first_v != second_v
    return 0
  if axis == 2 && first_w != second_w
    return 0
  new_first_u = first_u ## i64
  new_first_v = first_v ## i64
  new_first_w = first_w ## i64
  new_second_u = first_u ## i64
  new_second_v = first_v ## i64
  new_second_w = second_w ## i64
  if axis == 0
    new_first_w = first_w ^ second_w
    new_second_v = first_v ^ second_v
  if axis == 1
    new_first_w = first_w ^ second_w
    new_second_u = first_u ^ second_u
  if axis == 2
    new_first_v = first_v ^ second_v
    new_second_u = first_u ^ second_u
    new_second_v = second_v
    new_second_w = first_w
  if new_first_u == 0 || new_first_v == 0 || new_first_w == 0
    return 0
  if new_second_u == 0 || new_second_v == 0 || new_second_w == 0
    return 0
  if fftc_same_term(new_first_u, new_first_v, new_first_w, first_u, first_v, first_w) == 1
    if fftc_same_term(new_second_u, new_second_v, new_second_w, second_u, second_v, second_w) == 1
      return 0
  us[first] = new_first_u
  vs[first] = new_first_v
  ws[first] = new_first_w
  us[second] = new_second_u
  vs[second] = new_second_v
  ws[second] = new_second_w
  1

-> fftc_apply_code(us, vs, ws, count, code, catalyst_floor) (i64[] i64[] i64[] i64 i64 i64) i64
  if count < 2
    return 0
  pair_code = code / 3 ## i64
  axis = code % 3 ## i64
  first = pair_code / (count - 1) ## i64
  offset = pair_code % (count - 1) ## i64
  second = offset ## i64
  if second >= first
    second += 1
  if first >= count || second >= count
    return 0
  if catalyst_floor >= 0
    if first < catalyst_floor && second < catalyst_floor
      return 0
  fftc_apply_flip(us, vs, ws, count, first, second, axis)

-> fftc_code_count(count) (i64) i64
  count * (count - 1) * 3

# Exhaust all ordered three-flip paths on a selected triple.  This recovers
# the real W->V->W triangle tunnel without accepting either intermediate.
-> fftc_find_tunnel3(source_u, source_v, source_w, wanted_u, wanted_v, wanted_w, out_u, out_v, out_w, path) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  code_count = fftc_code_count(3) ## i64
  state1_u = i64[3]
  state1_v = i64[3]
  state1_w = i64[3]
  state2_u = i64[3]
  state2_v = i64[3]
  state2_w = i64[3]
  state3_u = i64[3]
  state3_v = i64[3]
  state3_w = i64[3]
  code0 = 0 ## i64
  while code0 < code_count
    z = fftc_copy_terms(source_u, source_v, source_w, 3, state1_u, state1_v, state1_w) ## i64
    if fftc_apply_code(state1_u, state1_v, state1_w, 3, code0, 0 - 1) == 1
      code1 = 0 ## i64
      while code1 < code_count
        z = fftc_copy_terms(state1_u, state1_v, state1_w, 3, state2_u, state2_v, state2_w)
        if fftc_apply_code(state2_u, state2_v, state2_w, 3, code1, 0 - 1) == 1
          code2 = 0 ## i64
          while code2 < code_count
            z = fftc_copy_terms(state2_u, state2_v, state2_w, 3, state3_u, state3_v, state3_w)
            if fftc_apply_code(state3_u, state3_v, state3_w, 3, code2, 0 - 1) == 1
              if fftc_terms_same_set(state3_u, state3_v, state3_w, 3, wanted_u, wanted_v, wanted_w, 3) == 1
                z = fftc_copy_terms(state3_u, state3_v, state3_w, 3, out_u, out_v, out_w)
                path[0] = code0
                path[1] = code1
                path[2] = code2
                return 3
            code2 += 1
        code1 += 1
    code0 += 1
  0

-> fftc_pair_equal(us, vs, ws, first, second) (i64[] i64[] i64[] i64 i64) i64
  fftc_same_term(us[first], vs[first], ws[first], us[second], vs[second], ws[second])

# Exhaust a depth-four labeled catalyst braid on three live terms.  Positions
# three and four are distinct labels even though their factors initially
# agree.  They must agree again at the endpoint before parity cancellation.
-> fftc_find_catalyst4(source_u, source_v, source_w, catalyst_u, catalyst_v, catalyst_w, wanted_u, wanted_v, wanted_w, out_u, out_v, out_w, path) (i64[] i64[] i64[] i64 i64 i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  if catalyst_u == 0 || catalyst_v == 0 || catalyst_w == 0
    return 0
  initial_u = i64[5]
  initial_v = i64[5]
  initial_w = i64[5]
  z = fftc_copy_terms(source_u, source_v, source_w, 3, initial_u, initial_v, initial_w) ## i64
  initial_u[3] = catalyst_u
  initial_v[3] = catalyst_v
  initial_w[3] = catalyst_w
  initial_u[4] = catalyst_u
  initial_v[4] = catalyst_v
  initial_w[4] = catalyst_w
  state1_u = i64[5]
  state1_v = i64[5]
  state1_w = i64[5]
  state2_u = i64[5]
  state2_v = i64[5]
  state2_w = i64[5]
  state3_u = i64[5]
  state3_v = i64[5]
  state3_w = i64[5]
  state4_u = i64[5]
  state4_v = i64[5]
  state4_w = i64[5]
  code_count = fftc_code_count(5) ## i64
  code0 = 0 ## i64
  while code0 < code_count
    z = fftc_copy_terms(initial_u, initial_v, initial_w, 5, state1_u, state1_v, state1_w)
    if fftc_apply_code(state1_u, state1_v, state1_w, 5, code0, 3) == 1
      code1 = 0 ## i64
      while code1 < code_count
        z = fftc_copy_terms(state1_u, state1_v, state1_w, 5, state2_u, state2_v, state2_w)
        if fftc_apply_code(state2_u, state2_v, state2_w, 5, code1, 3) == 1
          code2 = 0 ## i64
          while code2 < code_count
            z = fftc_copy_terms(state2_u, state2_v, state2_w, 5, state3_u, state3_v, state3_w)
            if fftc_apply_code(state3_u, state3_v, state3_w, 5, code2, 3) == 1
              code3 = 0 ## i64
              while code3 < code_count
                z = fftc_copy_terms(state3_u, state3_v, state3_w, 5, state4_u, state4_v, state4_w)
                if fftc_apply_code(state4_u, state4_v, state4_w, 5, code3, 3) == 1
                  if fftc_pair_equal(state4_u, state4_v, state4_w, 3, 4) == 1
                    if fftc_terms_same_set(state4_u, state4_v, state4_w, 3, wanted_u, wanted_v, wanted_w, 3) == 1
                      z = fftc_copy_terms(state4_u, state4_v, state4_w, 3, out_u, out_v, out_w)
                      path[0] = code0
                      path[1] = code1
                      path[2] = code2
                      path[3] = code3
                      return 4
                code3 += 1
            code2 += 1
        code1 += 1
    code0 += 1
  0

-> fftc_local_exact(source_u, source_v, source_w, source_count, out_u, out_v, out_w, out_count) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  width = 0 ## i64
  i = 0 ## i64
  while i < source_count
    bit = 0 ## i64
    while bit < 63
      if ((source_u[i] | source_v[i] | source_w[i]) >> bit) != 0
        if bit + 1 > width
          width = bit + 1
      bit += 1
    i += 1
  i = 0
  while i < out_count
    bit = 0 ## i64
    while bit < 63
      if ((out_u[i] | out_v[i] | out_w[i]) >> bit) != 0
        if bit + 1 > width
          width = bit + 1
      bit += 1
    i += 1
  if width < 1
    return 0
  cells = i64[width * width * width]
  side = 0 ## i64
  while side < 2
    count = source_count ## i64
    use_u = source_u
    use_v = source_v
    use_w = source_w
    if side == 1
      count = out_count
      use_u = out_u
      use_v = out_v
      use_w = out_w
    term = 0 ## i64
    while term < count
      if use_u[term] == 0 || use_v[term] == 0 || use_w[term] == 0
        return 0
      ub = 0 ## i64
      while ub < width
        if ((use_u[term] >> ub) & 1) == 1
          vb = 0 ## i64
          while vb < width
            if ((use_v[term] >> vb) & 1) == 1
              wb = 0 ## i64
              while wb < width
                if ((use_w[term] >> wb) & 1) == 1
                  index = (ub * width + vb) * width + wb ## i64
                  cells[index] = cells[index] ^ 1
                wb += 1
            vb += 1
        ub += 1
      term += 1
    side += 1
  index = 0 ## i64
  while index < cells.size()
    if cells[index] != 0
      return 0
    index += 1
  1
