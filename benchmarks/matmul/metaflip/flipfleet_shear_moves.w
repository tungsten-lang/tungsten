# Exact triangle and low-rank shear moves for FlipFleet.
#
# The three-term move is the GF(2) identity
#
#   (a,p,w) + (b,q,w) + (c,p^q,r)
#     =
#   (a^c,p,w) + (b^c,q,w) + (c,p^q,r^w).
#
# `ffsm_triangle_shear` accepts any of the six assignments of the logical
# transfer/sum/shared axes to U/V/W.  It is an involution.  The implementation
# rejects zero factors, duplicate terms, unchanged term sets, and candidates
# that fail an independent exact local-tensor comparison.
#
# Topologically this is an atomic three-pair-flip macro, not a new component:
# flip the first pair on shared, the resulting pair on sum, then the resulting
# pair on shared again.  Its search value is crossing an intermediate-score
# barrier in one accepted move; a distance-six endpoint is not one pair flip.
#
# More generally, shifting one axis of q terms by `shift` changes their sum by
#
#   shift (x) M,       M = sum_i left_i (x) right_i.
#
# `ffsm_rank_factor_complement` computes an exact, minimal GF(2) rank
# factorization M=sum_j correction_left_j (x) correction_right_j.
# `ffsm_low_rank_shear_append` appends those correction terms (q -> q+r).
# `ffsm_low_rank_shear_absorb` instead folds each correction into an existing
# carrier (q+r -> q+r), of which the triangle shear is the r=1 special case.
#
# Axis codes enumerate (transfer, sum, shared):
#   0 U,V,W    1 U,W,V    2 V,U,W
#   3 V,W,U    4 W,U,V    5 W,V,U

use flipfleet_span_refactor

-> ffsm_axis_get(us, vs, ws, term, axis) (i64[] i64[] i64[] i64 i64) i64
  value = 0 ## i64
  if axis == 0
    value = us[term]
  if axis == 1
    value = vs[term]
  if axis == 2
    value = ws[term]
  value

-> ffsm_axis_set(us, vs, ws, term, axis, value) (i64[] i64[] i64[] i64 i64 i64) i64
  if axis == 0
    us[term] = value
  if axis == 1
    vs[term] = value
  if axis == 2
    ws[term] = value
  value

-> ffsm_axis_code(code, axes) (i64 i64[]) i64
  ok = 0 ## i64
  if code >= 0 && code < 6 && axes.size() >= 3
    if code == 0
      axes[0] = 0
      axes[1] = 1
      axes[2] = 2
    if code == 1
      axes[0] = 0
      axes[1] = 2
      axes[2] = 1
    if code == 2
      axes[0] = 1
      axes[1] = 0
      axes[2] = 2
    if code == 3
      axes[0] = 1
      axes[1] = 2
      axes[2] = 0
    if code == 4
      axes[0] = 2
      axes[1] = 0
      axes[2] = 1
    if code == 5
      axes[0] = 2
      axes[1] = 1
      axes[2] = 0
    ok = 1
  ok

-> ffsm_axis_pair_valid(first, second) (i64 i64) i64
  ok = 0 ## i64
  if first >= 0 && first < 3 && second >= 0 && second < 3 && first != second
    ok = 1
  ok

-> ffsm_arrays_fit(us, vs, ws, count) (i64[] i64[] i64[] i64) i64
  ok = 0 ## i64
  if count >= 0
    if us.size() >= count && vs.size() >= count && ws.size() >= count
      ok = 1
  ok

-> ffsm_same_term(u0, v0, w0, u1, v1, w1) (i64 i64 i64 i64 i64 i64) i64
  same = 0 ## i64
  if u0 == u1 && v0 == v1 && w0 == w1
    same = 1
  same

-> ffsm_terms_well_formed(us, vs, ws, count) (i64[] i64[] i64[] i64) i64
  ok = ffsm_arrays_fit(us, vs, ws, count) ## i64
  if count < 1
    ok = 0
  i = 0 ## i64
  while i < count && ok == 1
    if us[i] <= 0 || vs[i] <= 0 || ws[i] <= 0
      ok = 0
    j = i + 1 ## i64
    while j < count && ok == 1
      if ffsm_same_term(us[i], vs[i], ws[i], us[j], vs[j], ws[j]) == 1
        ok = 0
      j += 1
    i += 1
  ok

-> ffsm_term_in(us, vs, ws, count, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  found = 0 ## i64
  i = 0 ## i64
  while i < count && found == 0
    if ffsm_same_term(us[i], vs[i], ws[i], u, v, w) == 1
      found = 1
    i += 1
  found

-> ffsm_terms_same_set(lu, lv, lw, lcount, ru, rv, right_w, rcount) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  same = 0 ## i64
  if lcount == rcount
    if ffsm_arrays_fit(lu, lv, lw, lcount) == 1 && ffsm_arrays_fit(ru, rv, right_w, rcount) == 1
      same = 1
      i = 0 ## i64
      while i < lcount && same == 1
        if ffsm_term_in(ru, rv, right_w, rcount, lu[i], lv[i], lw[i]) == 0
          same = 0
        i += 1
  same

-> ffsm_mask_width(mask) (i64) i64
  width = 0 ## i64
  if mask > 0
    while width < 63 && (mask >> width) != 0
      width += 1
  width

# Exact tensor comparison without a probabilistic fingerprint.  Triangle
# replacements live inside the spans of their three source factors, so reuse
# the span module's complete 27-bit local coordinate tensor.
-> ffsm_verify_local_replacement(lu, lv, lw, lcount, ru, rv, right_w, rcount) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  ok = 0 ## i64
  if lcount == 3 && rcount >= 1 && rcount <= 4
    if ffsm_terms_well_formed(lu, lv, lw, lcount) == 1 && ffsm_terms_well_formed(ru, rv, right_w, rcount) == 1
      ok = ffsr_verify_local_replacement(lu, lv, lw, 3, ru, rv, right_w, rcount)
  ok

-> ffsm_replacement_valid(lu, lv, lw, lcount, ru, rv, right_w, rcount) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  ok = ffsm_terms_well_formed(lu, lv, lw, lcount) ## i64
  if ok == 1
    ok = ffsm_terms_well_formed(ru, rv, right_w, rcount)
  if ok == 1 && ffsm_terms_same_set(lu, lv, lw, lcount, ru, rv, right_w, rcount) == 1
    ok = 0
  if ok == 1
    ok = ffsm_verify_local_replacement(lu, lv, lw, lcount, ru, rv, right_w, rcount)
  ok

-> ffsm_copy_terms(su, sv, sw, count, out_u, out_v, out_w) (i64[] i64[] i64[] i64 i64[] i64[] i64[]) i64
  copied = 0 ## i64
  if ffsm_arrays_fit(su, sv, sw, count) == 1 && ffsm_arrays_fit(out_u, out_v, out_w, count) == 1
    while copied < count
      out_u[copied] = su[copied]
      out_v[copied] = sv[copied]
      out_w[copied] = sw[copied]
      copied += 1
  copied

# Compare sum_i left_i (x) right_i with a supplied rank-r factorization.
-> ffsm_verify_matrix_factorization(lefts, rights, count, correction_left, correction_right, rank) (i64[] i64[] i64 i64[] i64[] i64) i64
  ok = 0 ## i64
  if count >= 0 && rank >= 0
    if lefts.size() >= count && rights.size() >= count
      if correction_left.size() >= rank && correction_right.size() >= rank
        ok = 1
  i = 0 ## i64
  while i < count && ok == 1
    if lefts[i] <= 0 || rights[i] <= 0
      ok = 0
    i += 1
  i = 0
  while i < rank && ok == 1
    if correction_left[i] <= 0 || correction_right[i] <= 0
      ok = 0
    i += 1
  row = 0 ## i64
  while row < 63 && ok == 1
    old_row = 0 ## i64
    i = 0
    while i < count
      if ((lefts[i] >> row) & 1) != 0
        old_row = old_row ^ rights[i]
      i += 1
    new_row = 0 ## i64
    i = 0
    while i < rank
      if ((correction_left[i] >> row) & 1) != 0
        new_row = new_row ^ correction_right[i]
      i += 1
    if old_row != new_row
      ok = 0
    row += 1
  ok

# Minimal GF(2) matrix-rank factorization.  Each nonzero physical matrix row
# is expressed in a basis selected from the original rows; the coefficient
# columns become `correction_left`, and basis rows become `correction_right`.
# Returns -1 for invalid/capacity failure, otherwise the exact rank (including
# zero for a vanishing complementary matrix).
-> ffsm_rank_factor_matrix(lefts, rights, count, correction_left, correction_right) (i64[] i64[] i64 i64[] i64[]) i64
  result = 0 - 1 ## i64
  valid = 1 ## i64
  if count < 0 || lefts.size() < count || rights.size() < count
    valid = 0
  i = 0 ## i64
  while i < count && valid == 1
    if lefts[i] <= 0 || rights[i] <= 0
      valid = 0
    i += 1
  rows = i64[63]
  if valid == 1
    i = 0
    while i < count
      bit = 0 ## i64
      while bit < 63
        if ((lefts[i] >> bit) & 1) != 0
          rows[bit] = rows[bit] ^ rights[i]
        bit += 1
      i += 1
    pivot_values = i64[63]
    pivot_coordinates = i64[63]
    basis_right = i64[63]
    rank = 0 ## i64
    row = 0 ## i64
    while row < 63 && valid == 1
      value = rows[row] ## i64
      coordinates = 0 ## i64
      bit = 62 ## i64
      while bit >= 0 && value != 0 && valid == 1
        if ((value >> bit) & 1) != 0
          if pivot_values[bit] != 0
            value = value ^ pivot_values[bit]
            coordinates = coordinates ^ pivot_coordinates[bit]
          else
            if rank >= 63 || rank >= correction_left.size() || rank >= correction_right.size()
              valid = 0
            else
              basis_right[rank] = rows[row]
              pivot_values[bit] = value
              pivot_coordinates[bit] = coordinates ^ (1 << rank)
              rank += 1
              value = 0
        bit -= 1
      row += 1
    i = 0
    while i < correction_left.size()
      correction_left[i] = 0
      i += 1
    i = 0
    while i < correction_right.size()
      correction_right[i] = 0
      i += 1
    if valid == 1
      j = 0 ## i64
      while j < rank
        correction_right[j] = basis_right[j]
        j += 1
      row = 0
      while row < 63 && valid == 1
        value = rows[row]
        coordinates = 0
        bit = 62
        while bit >= 0 && value != 0
          if ((value >> bit) & 1) != 0
            if pivot_values[bit] == 0
              valid = 0
              value = 0
            else
              value = value ^ pivot_values[bit]
              coordinates = coordinates ^ pivot_coordinates[bit]
          bit -= 1
        j = 0
        while j < rank && valid == 1
          if ((coordinates >> j) & 1) != 0
            correction_left[j] = correction_left[j] | (1 << row)
          j += 1
        row += 1
      if valid == 1
        if ffsm_verify_matrix_factorization(lefts, rights, count, correction_left, correction_right, rank) == 1
          result = rank
  result

-> ffsm_extract_complement(su, sv, sw, count, shift_axis, factor_axis, lefts, rights) (i64[] i64[] i64[] i64 i64 i64 i64[] i64[]) i64
  result = 0 ## i64
  if ffsm_axis_pair_valid(shift_axis, factor_axis) == 1
    if ffsm_arrays_fit(su, sv, sw, count) == 1 && lefts.size() >= count && rights.size() >= count
      right_axis = 3 - shift_axis - factor_axis ## i64
      i = 0 ## i64
      while i < count
        lefts[i] = ffsm_axis_get(su, sv, sw, i, factor_axis)
        rights[i] = ffsm_axis_get(su, sv, sw, i, right_axis)
        i += 1
      result = count
  result

-> ffsm_rank_factor_complement(su, sv, sw, count, shift_axis, factor_axis, correction_left, correction_right) (i64[] i64[] i64[] i64 i64 i64 i64[] i64[]) i64
  result = 0 - 1 ## i64
  if count >= 1 && ffsm_terms_well_formed(su, sv, sw, count) == 1
    lefts = i64[count]
    rights = i64[count]
    if ffsm_extract_complement(su, sv, sw, count, shift_axis, factor_axis, lefts, rights) == count
      result = ffsm_rank_factor_matrix(lefts, rights, count, correction_left, correction_right)
  result

-> ffsm_verify_complement_factorization(su, sv, sw, count, shift_axis, factor_axis, correction_left, correction_right, rank) (i64[] i64[] i64[] i64 i64 i64 i64[] i64[] i64) i64
  ok = 0 ## i64
  if count >= 1 && ffsm_axis_pair_valid(shift_axis, factor_axis) == 1
    lefts = i64[count]
    rights = i64[count]
    if ffsm_extract_complement(su, sv, sw, count, shift_axis, factor_axis, lefts, rights) == count
      ok = ffsm_verify_matrix_factorization(lefts, rights, count, correction_left, correction_right, rank)
  ok

# Shift q terms and append r explicit correction terms.  This is an exact
# q -> q+r escape and returns q+r, or zero when any gate rejects it.
-> ffsm_low_rank_shear_append(su, sv, sw, count, shift_axis, factor_axis, shift, correction_left, correction_right, rank, out_u, out_v, out_w) (i64[] i64[] i64[] i64 i64 i64 i64 i64[] i64[] i64 i64[] i64[] i64[]) i64
  result = 0 ## i64
  out_count = count + rank ## i64
  valid = 1 ## i64
  if count < 1 || rank < 0 || shift <= 0
    valid = 0
  if valid == 1 && ffsm_axis_pair_valid(shift_axis, factor_axis) == 0
    valid = 0
  if valid == 1 && ffsm_terms_well_formed(su, sv, sw, count) == 0
    valid = 0
  if valid == 1 && ffsm_arrays_fit(out_u, out_v, out_w, out_count) == 0
    valid = 0
  if valid == 1
    valid = ffsm_verify_complement_factorization(su, sv, sw, count, shift_axis, factor_axis, correction_left, correction_right, rank)
  if valid == 1
    z = ffsm_copy_terms(su, sv, sw, count, out_u, out_v, out_w) ## i64
    right_axis = 3 - shift_axis - factor_axis ## i64
    i = 0 ## i64
    while i < count
      old = ffsm_axis_get(out_u, out_v, out_w, i, shift_axis) ## i64
      z = ffsm_axis_set(out_u, out_v, out_w, i, shift_axis, old ^ shift)
      i += 1
    j = 0 ## i64
    while j < rank
      term = count + j ## i64
      out_u[term] = 0
      out_v[term] = 0
      out_w[term] = 0
      z = ffsm_axis_set(out_u, out_v, out_w, term, shift_axis, shift)
      z = ffsm_axis_set(out_u, out_v, out_w, term, factor_axis, correction_left[j])
      z = ffsm_axis_set(out_u, out_v, out_w, term, right_axis, correction_right[j])
      j += 1
    # Exactness follows from the already-verified matrix factorization.  The
    # remaining gates enforce legal set semantics.
    if ffsm_terms_well_formed(out_u, out_v, out_w, out_count) == 1
      if ffsm_terms_same_set(su, sv, sw, count, out_u, out_v, out_w, out_count) == 0
        result = out_count
  result

# Rank-neutral version.  The first q input terms are shifted.  The following r
# carriers must have `shift` on shift_axis and correction_left[j] on
# factor_axis; correction_right[j] is XORed into each carrier's remaining
# factor.  The triangle shear is q=2,r=1.
-> ffsm_low_rank_shear_absorb(su, sv, sw, count, rank, shift_axis, factor_axis, shift, correction_left, correction_right, out_u, out_v, out_w) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64[] i64[] i64[] i64[] i64[]) i64
  result = 0 ## i64
  total = count + rank ## i64
  valid = 1 ## i64
  if count < 1 || rank < 1 || shift <= 0
    valid = 0
  if valid == 1 && ffsm_axis_pair_valid(shift_axis, factor_axis) == 0
    valid = 0
  if valid == 1 && ffsm_terms_well_formed(su, sv, sw, total) == 0
    valid = 0
  if valid == 1 && ffsm_arrays_fit(out_u, out_v, out_w, total) == 0
    valid = 0
  if valid == 1
    valid = ffsm_verify_complement_factorization(su, sv, sw, count, shift_axis, factor_axis, correction_left, correction_right, rank)
  if valid == 1
    right_axis = 3 - shift_axis - factor_axis ## i64
    j = 0 ## i64
    while j < rank && valid == 1
      carrier = count + j ## i64
      if ffsm_axis_get(su, sv, sw, carrier, shift_axis) != shift
        valid = 0
      if ffsm_axis_get(su, sv, sw, carrier, factor_axis) != correction_left[j]
        valid = 0
      j += 1
  if valid == 1
    z = ffsm_copy_terms(su, sv, sw, total, out_u, out_v, out_w) ## i64
    i = 0 ## i64
    while i < count
      old = ffsm_axis_get(out_u, out_v, out_w, i, shift_axis) ## i64
      z = ffsm_axis_set(out_u, out_v, out_w, i, shift_axis, old ^ shift)
      i += 1
    j = 0
    while j < rank
      carrier = count + j
      old = ffsm_axis_get(out_u, out_v, out_w, carrier, right_axis)
      z = ffsm_axis_set(out_u, out_v, out_w, carrier, right_axis, old ^ correction_right[j])
      j += 1
    # Exactness follows from the same factorization identity, with each
    # correction XORed into its carrier instead of appended.
    if ffsm_terms_well_formed(out_u, out_v, out_w, total) == 1
      if ffsm_terms_same_set(su, sv, sw, total, out_u, out_v, out_w, total) == 0
        result = total
  result

# Direct ordered triangle constructor for one logical-axis assignment.
-> ffsm_triangle_shear(su, sv, sw, axis_code, out_u, out_v, out_w) (i64[] i64[] i64[] i64 i64[] i64[] i64[]) i64
  result = 0 ## i64
  axes = i64[3]
  valid = ffsm_axis_code(axis_code, axes) ## i64
  if valid == 1 && ffsm_terms_well_formed(su, sv, sw, 3) == 0
    valid = 0
  if valid == 1 && ffsm_arrays_fit(out_u, out_v, out_w, 3) == 0
    valid = 0
  if valid == 1
    transfer_axis = axes[0] ## i64
    sum_axis = axes[1] ## i64
    shared_axis = axes[2] ## i64
    p = ffsm_axis_get(su, sv, sw, 0, sum_axis) ## i64
    q = ffsm_axis_get(su, sv, sw, 1, sum_axis) ## i64
    summed = ffsm_axis_get(su, sv, sw, 2, sum_axis) ## i64
    shared = ffsm_axis_get(su, sv, sw, 0, shared_axis) ## i64
    if ffsm_axis_get(su, sv, sw, 1, shared_axis) != shared
      valid = 0
    if (p ^ q) != summed
      valid = 0
    if valid == 1
      shift = ffsm_axis_get(su, sv, sw, 2, transfer_axis) ## i64
      correction_left = i64[1]
      correction_right = i64[1]
      correction_left[0] = summed
      correction_right[0] = shared
      result = ffsm_low_rank_shear_absorb(su, sv, sw, 2, 1, transfer_axis, sum_axis, shift, correction_left, correction_right, out_u, out_v, out_w)
      if result == 3
        if ffsm_verify_local_replacement(su, sv, sw, 3, out_u, out_v, out_w, 3) == 0
          result = 0
  result

-> ffsm_order_index(order, position) (i64 i64) i64
  index = position ## i64
  if order == 1
    if position == 0
      index = 1
    if position == 1
      index = 0
  if order == 2
    if position == 1
      index = 2
    if position == 2
      index = 1
  if order == 3
    if position == 0
      index = 2
    if position == 1
      index = 0
    if position == 2
      index = 1
  if order == 4
    if position == 0
      index = 1
    if position == 1
      index = 2
    if position == 2
      index = 0
  if order == 5
    if position == 0
      index = 2
    if position == 1
      index = 1
    if position == 2
      index = 0
  index

# Try all six term orderings and six logical-axis assignments.  meta[0] is
# the winning axis code and meta[1] the winning term-order code.
-> ffsm_find_triangle_shear(su, sv, sw, out_u, out_v, out_w, meta) (i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  result = 0 ## i64
  if ffsm_terms_well_formed(su, sv, sw, 3) == 1
    if ffsm_arrays_fit(out_u, out_v, out_w, 3) == 1 && meta.size() >= 2
      ordered_u = i64[3]
      ordered_v = i64[3]
      ordered_w = i64[3]
      order = 0 ## i64
      while order < 6 && result == 0
        i = 0 ## i64
        while i < 3
          source = ffsm_order_index(order, i) ## i64
          ordered_u[i] = su[source]
          ordered_v[i] = sv[source]
          ordered_w[i] = sw[source]
          i += 1
        axis_code = 0 ## i64
        while axis_code < 6 && result == 0
          made = ffsm_triangle_shear(ordered_u, ordered_v, ordered_w, axis_code, out_u, out_v, out_w) ## i64
          if made == 3
            result = 3
            meta[0] = axis_code
            meta[1] = order
          axis_code += 1
        order += 1
  result

# Six-argument native-compiler admission wrappers.  The current compiler's
# direct top-level typed-call ABI is bounded at six arguments; keeping these
# fixed-three-term entry points avoids dynamic-array boxing while preserving
# the parallel-array core used by fleet integration.  `packed` is interleaved
# [u0,v0,w0,u1,v1,w1,u2,v2,w2].
-> ffsm_pack_three(us, vs, ws, packed) (i64[] i64[] i64[] i64[]) i64
  result = 0 ## i64
  if ffsm_arrays_fit(us, vs, ws, 3) == 1 && packed.size() >= 9
    i = 0 ## i64
    while i < 3
      packed[i * 3] = us[i]
      packed[i * 3 + 1] = vs[i]
      packed[i * 3 + 2] = ws[i]
      i += 1
    result = 3
  result

-> ffsm_unpack_three(packed, us, vs, ws) (i64[] i64[] i64[] i64[]) i64
  result = 0 ## i64
  if packed.size() >= 9 && ffsm_arrays_fit(us, vs, ws, 3) == 1
    i = 0 ## i64
    while i < 3
      us[i] = packed[i * 3]
      vs[i] = packed[i * 3 + 1]
      ws[i] = packed[i * 3 + 2]
      i += 1
    result = 3
  result

-> ffsm_triangle_shear_packed(su, sv, sw, axis_code, packed) (i64[] i64[] i64[] i64 i64[]) i64
  out_u = i64[3]
  out_v = i64[3]
  out_w = i64[3]
  made = ffsm_triangle_shear(su, sv, sw, axis_code, out_u, out_v, out_w) ## i64
  if made == 3
    made = ffsm_pack_three(out_u, out_v, out_w, packed)
  made

-> ffsm_find_triangle_shear_packed(su, sv, sw, packed, meta) (i64[] i64[] i64[] i64[] i64[]) i64
  out_u = i64[3]
  out_v = i64[3]
  out_w = i64[3]
  made = ffsm_find_triangle_shear(su, sv, sw, out_u, out_v, out_w, meta) ## i64
  if made == 3
    made = ffsm_pack_three(out_u, out_v, out_w, packed)
  made

-> ffsm_verify_three_to_three(lu, lv, lw, ru, rv, right_w) (i64[] i64[] i64[] i64[] i64[] i64[]) i64
  ffsm_verify_local_replacement(lu, lv, lw, 3, ru, rv, right_w, 3)

-> ffsm_validate_three_to_three(lu, lv, lw, ru, rv, right_w) (i64[] i64[] i64[] i64[] i64[] i64[]) i64
  ffsm_replacement_valid(lu, lv, lw, 3, ru, rv, right_w, 3)
