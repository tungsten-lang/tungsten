# Support-aware outer block composition for exact GF(2) matrix-multiplication
# schemes.  This is the wide-factor sibling of flipfleet_sedoglavic.w.
#
# Factors use flattened i64 buffers with base-2^30 limbs.  Thirty-bit limbs
# keep every shift positive and make decimal parsing/printing overflow-safe:
#
#   rem * 2^30 + limb < 10^9 * 2^30 < 2^60.
#
# Consequently this file can materialise 13x13, 15x15, and larger factors
# without depending on boxed BigInt lowering.  Files use the interoperable
# `R <u> <v> <w>` decimal format; conversion in both directions is performed
# directly on the limb buffers.

-> ffbc_word_bits() i64
  30

-> ffbc_word_base() i64
  1073741824

-> ffbc_words(bits) (i64) i64
  (bits + ffbc_word_bits() - 1) / ffbc_word_bits()

+ FFBCScheme
  -> new(n, m, p, capacity)
    # Scalar i64 -> object-ivar lowering currently leaves raw 1/2 values
    # looking like false/true WValue tags.  Keep all numeric metadata in one
    # typed array, just like the factor limbs themselves.
    @meta = i64[8]
    @meta[0] = n
    @meta[1] = m
    @meta[2] = p
    @meta[3] = capacity
    @meta[4] = 0
    @meta[5] = (n * m + 29) / 30
    @meta[6] = (m * p + 29) / 30
    @meta[7] = (n * p + 29) / 30
    @us = i64[@meta[3] * @meta[5]]
    @vs = i64[@meta[3] * @meta[6]]
    @ws = i64[@meta[3] * @meta[7]]
    # Populated only for schemes materialised by ffbc_compose.  Keeping the
    # audit beside the scheme makes support truncation and parity cancellation
    # independently testable instead of inferring either from the final rank.
    @compose_audit = i64[4]

  -> n()
    @meta[0]
  -> m()
    @meta[1]
  -> p()
    @meta[2]
  -> capacity()
    @meta[3]
  -> rank()
    @meta[4]
  -> set_rank(value)
    @meta[4] = value
  -> uw()
    @meta[5]
  -> vw()
    @meta[6]
  -> ww()
    @meta[7]
  -> us()
    @us
  -> vs()
    @vs
  -> ws()
    @ws
  -> set_compose_audit(nominal, zero_terms, distinct_terms, parity_reduction)
    @compose_audit[0] = nominal
    @compose_audit[1] = zero_terms
    @compose_audit[2] = distinct_terms
    @compose_audit[3] = parity_reduction
  -> compose_nominal()
    @compose_audit[0]
  -> compose_zero_terms()
    @compose_audit[1]
  -> compose_distinct_terms()
    @compose_audit[2]
  -> compose_parity_reduction()
    @compose_audit[3]

-> ffbc_clear(data, offset, words) (i64[] i64 i64) i64
  i = 0 ## i64
  while i < words
    data[offset + i] = 0
    i += 1
  0

-> ffbc_copy(src, src_base, dst, dst_base, words) (i64[] i64 i64[] i64 i64) i64
  i = 0 ## i64
  while i < words
    dst[dst_base + i] = src[src_base + i]
    i += 1
  0

-> ffbc_xor_into(dst, dst_base, src, src_base, words) (i64[] i64 i64[] i64 i64) i64
  i = 0 ## i64
  while i < words
    dst[dst_base + i] = dst[dst_base + i] ^ src[src_base + i]
    i += 1
  0

-> ffbc_words_equal(left, left_base, right, right_base, words) (i64[] i64 i64[] i64 i64) i64
  i = 0 ## i64
  while i < words
    if left[left_base + i] != right[right_base + i]
      return 0
    i += 1
  1

-> ffbc_bit(data, offset, bit) (i64[] i64 i64) i64
  word = bit / ffbc_word_bits() ## i64
  shift = bit % ffbc_word_bits() ## i64
  (data[offset + word] >> shift) & 1

-> ffbc_toggle_bit(data, offset, bit) (i64[] i64 i64) i64
  word = bit / ffbc_word_bits() ## i64
  shift = bit % ffbc_word_bits() ## i64
  data[offset + word] = data[offset + word] ^ (1 << shift)
  0

-> ffbc_factor_zero(data, offset, words) (i64[] i64 i64) i64
  i = 0 ## i64
  while i < words
    if data[offset + i] != 0
      return 0
    i += 1
  1

-> ffbc_factor_valid(data, offset, words, bits) (i64[] i64 i64 i64) i64
  if ffbc_factor_zero(data, offset, words) == 1
    return 0
  used = bits % ffbc_word_bits() ## i64
  if used != 0 && (data[offset + words - 1] >> used) != 0
    return 0
  1

# Decimal -> base-2^30, without String#to_i on a wide value.
-> ffbc_decimal_to_words(text, data, offset, words) (String i64[] i64 i64) i64
  ffbc_clear(data, offset, words)
  if text.size() < 1
    return 0
  i = 0 ## i64
  while i < text.size()
    digit_text = text.slice(i, 1)
    digit = 0 ## i64
    valid_digit = 1 ## i64
    if digit_text == "1"
      digit = 1
    elsif digit_text == "2"
      digit = 2
    elsif digit_text == "3"
      digit = 3
    elsif digit_text == "4"
      digit = 4
    elsif digit_text == "5"
      digit = 5
    elsif digit_text == "6"
      digit = 6
    elsif digit_text == "7"
      digit = 7
    elsif digit_text == "8"
      digit = 8
    elsif digit_text == "9"
      digit = 9
    elsif digit_text != "0"
      valid_digit = 0
    if valid_digit == 0
      return 0
    carry = digit ## i64
    w = 0 ## i64
    while w < words
      value = data[offset + w] * 10 + carry ## i64
      data[offset + w] = value % ffbc_word_base()
      carry = value / ffbc_word_base()
      w += 1
    if carry != 0
      return 0
    i += 1
  if ffbc_factor_zero(data, offset, words) == 1
    return 0
  1

# Base-2^30 -> decimal in 10^9 chunks.  The input is never mutated.
-> ffbc_words_to_decimal(data, offset, words) (i64[] i64 i64)
  tmp = i64[words]
  ffbc_copy(data, offset, tmp, 0, words)
  high = words - 1 ## i64
  while high > 0 && tmp[high] == 0
    high -= 1
  if high == 0 && tmp[0] == 0
    return "0"
  chunks = []
  while high >= 0
    rem = 0 ## i64
    i = high ## i64
    while i >= 0
      current = rem * ffbc_word_base() + tmp[i] ## i64
      tmp[i] = current / 1000000000
      rem = current % 1000000000
      i -= 1
    chunks.push(rem.to_s())
    while high >= 0 && tmp[high] == 0
      high -= 1
  result = chunks[chunks.size() - 1]
  i = chunks.size() - 2
  while i >= 0
    chunk = chunks[i]
    padding = ""
    zeros = 9 - chunk.size() ## i64
    while zeros > 0
      padding = padding + "0"
      zeros -= 1
    result = result + padding + chunk
    i -= 1
  result

# Both ordinary FlipFleet rank-header files and bare `R ...` files are read.
-> ffbc_load(path, n, m, p, capacity) (String i64 i64 i64 i64)
  content = read_file(path)
  if content == nil
    return nil
  scheme = FFBCScheme.new(n, m, p, capacity)
  lines = content.split("\n")
  declared = 0 ## i64
  have_declared = 0 ## i64
  rank = 0 ## i64
  line_index = 0 ## i64
  while line_index < lines.size()
    line = lines[line_index]
    if line.size() > 0
      fields = line.split(" ")
      field_base = 0 ## i64
      is_term = 1 ## i64
      if fields.size() == 1 && rank == 0 && have_declared == 0
        declared = fields[0].to_i()
        have_declared = 1
        is_term = 0
      if fields.size() >= 1 && fields[0] == "R"
        field_base = 1
      if is_term == 1
        if fields.size() < field_base + 3 || rank >= capacity
          return nil
        if ffbc_decimal_to_words(fields[field_base], scheme.us(), rank * scheme.uw(), scheme.uw()) != 1
          return nil
        if ffbc_decimal_to_words(fields[field_base + 1], scheme.vs(), rank * scheme.vw(), scheme.vw()) != 1
          return nil
        if ffbc_decimal_to_words(fields[field_base + 2], scheme.ws(), rank * scheme.ww(), scheme.ww()) != 1
          return nil
        rank += 1
    line_index += 1
  if rank < 1 || (have_declared == 1 && rank != declared)
    return nil
  scheme.set_rank(rank)
  scheme

# Exact reconstruction by (A-coordinate, B-coordinate) slices.  Each slice is
# a chunked C mask, so this is O(sum |U_t||V_t|*Cwords), not O(n^6*r).
-> ffbc_verify_exact(scheme) i64
  if scheme == nil || scheme.rank() < 1
    return 0
  ab = scheme.n() * scheme.m() ## i64
  bc = scheme.m() * scheme.p() ## i64
  ac = scheme.n() * scheme.p() ## i64
  t = 0 ## i64
  while t < scheme.rank()
    if ffbc_factor_valid(scheme.us(), t * scheme.uw(), scheme.uw(), ab) != 1
      return 0
    if ffbc_factor_valid(scheme.vs(), t * scheme.vw(), scheme.vw(), bc) != 1
      return 0
    if ffbc_factor_valid(scheme.ws(), t * scheme.ww(), scheme.ww(), ac) != 1
      return 0
    t += 1

  slices = i64[ab * bc * scheme.ww()]
  t = 0
  while t < scheme.rank()
    ai = 0 ## i64
    while ai < ab
      if ffbc_bit(scheme.us(), t * scheme.uw(), ai) == 1
        bi = 0 ## i64
        while bi < bc
          if ffbc_bit(scheme.vs(), t * scheme.vw(), bi) == 1
            dst = (ai * bc + bi) * scheme.ww() ## i64
            ffbc_xor_into(slices, dst, scheme.ws(), t * scheme.ww(), scheme.ww())
          bi += 1
      ai += 1
    t += 1

  ai = 0
  while ai < ab
    ii = ai / scheme.m() ## i64
    jj = ai % scheme.m() ## i64
    bi = 0
    while bi < bc
      jj2 = bi / scheme.p() ## i64
      kk = bi % scheme.p() ## i64
      expected_bit = 0 - 1 ## i64
      if jj == jj2
        expected_bit = ii * scheme.p() + kk
      src = (ai * bc + bi) * scheme.ww() ## i64
      x = 0
      while x < scheme.ww()
        expected = 0 ## i64
        if expected_bit >= 0 && expected_bit / ffbc_word_bits() == x
          expected = 1 << (expected_bit % ffbc_word_bits())
        if slices[src + x] != expected
          return 0
        x += 1
      bi += 1
    ai += 1
  1

-> ffbc_load_exact(path, n, m, p, capacity) (String i64 i64 i64 i64)
  scheme = ffbc_load(path, n, m, p, capacity)
  if scheme == nil || ffbc_verify_exact(scheme) != 1
    return nil
  scheme

-> ffbc_cumulative(allocation)
  result = i64[allocation.size() + 1]
  i = 0 ## i64
  while i < allocation.size()
    result[i + 1] = result[i] + allocation[i]
    i += 1
  result

-> ffbc_extent(data, base, rows, cols, row_alloc, col_alloc, result) (i64[] i64 i64 i64 i64[] i64[] i64[]) i64
  result[0] = 0
  result[1] = 0
  i = 0 ## i64
  while i < rows
    j = 0 ## i64
    while j < cols
      if ffbc_bit(data, base, i * cols + j) == 1
        if row_alloc[i] > result[0]
          result[0] = row_alloc[i]
        if col_alloc[j] > result[1]
          result[1] = col_alloc[j]
      j += 1
    i += 1
  0

# The six S3 orientations of <n,m,p>.  Codes and factor transforms:
#   0 n,m,p : U,V,W              3 p,m,n : V^T,U^T,W^T
#   1 m,p,n : V,W^T,U^T          4 m,n,p : U^T,W,V
#   2 p,n,m : W^T,U,V^T          5 n,p,m : W,V^T,U
-> ffbc_orientation_matches(code, n, m, p, tn, tm, tp) (i64 i64 i64 i64 i64 i64 i64) i64
  if code == 0
    if n == tn && m == tm && p == tp
      return 1
    return 0
  if code == 1
    if m == tn && p == tm && n == tp
      return 1
    return 0
  if code == 2
    if p == tn && n == tm && m == tp
      return 1
    return 0
  if code == 3
    if p == tn && m == tm && n == tp
      return 1
    return 0
  if code == 4
    if m == tn && n == tm && p == tp
      return 1
    return 0
  if code == 5
    if n == tn && p == tm && m == tp
      return 1
    return 0
  0

-> ffbc_copy_factor(src, src_base, src_words, dst, dst_words) (i64[] i64 i64 i64[] i64) i64
  ffbc_clear(dst, 0, dst_words)
  words = src_words ## i64
  if dst_words < words
    words = dst_words
  ffbc_copy(src, src_base, dst, 0, words)

-> ffbc_transpose_factor(src, src_base, rows, cols, dst, dst_words) (i64[] i64 i64 i64 i64[] i64) i64
  ffbc_clear(dst, 0, dst_words)
  bit = 0 ## i64
  while bit < rows * cols
    if ffbc_bit(src, src_base, bit) == 1
      i = bit / cols ## i64
      j = bit % cols ## i64
      ffbc_toggle_bit(dst, 0, j * rows + i)
    bit += 1
  0

-> ffbc_orient_term(leaf, term, code, ou, ov, ow) (FFBCScheme i64 i64 i64[] i64[] i64[]) i64
  ub = term * leaf.uw() ## i64
  vb = term * leaf.vw() ## i64
  wb = term * leaf.ww() ## i64
  if code == 0
    ffbc_copy_factor(leaf.us(), ub, leaf.uw(), ou, ou.size())
    ffbc_copy_factor(leaf.vs(), vb, leaf.vw(), ov, ov.size())
    ffbc_copy_factor(leaf.ws(), wb, leaf.ww(), ow, ow.size())
  if code == 1
    ffbc_copy_factor(leaf.vs(), vb, leaf.vw(), ou, ou.size())
    ffbc_transpose_factor(leaf.ws(), wb, leaf.n(), leaf.p(), ov, ov.size())
    ffbc_transpose_factor(leaf.us(), ub, leaf.n(), leaf.m(), ow, ow.size())
  if code == 2
    ffbc_transpose_factor(leaf.ws(), wb, leaf.n(), leaf.p(), ou, ou.size())
    ffbc_copy_factor(leaf.us(), ub, leaf.uw(), ov, ov.size())
    ffbc_transpose_factor(leaf.vs(), vb, leaf.m(), leaf.p(), ow, ow.size())
  if code == 3
    ffbc_transpose_factor(leaf.vs(), vb, leaf.m(), leaf.p(), ou, ou.size())
    ffbc_transpose_factor(leaf.us(), ub, leaf.n(), leaf.m(), ov, ov.size())
    ffbc_transpose_factor(leaf.ws(), wb, leaf.n(), leaf.p(), ow, ow.size())
  if code == 4
    ffbc_transpose_factor(leaf.us(), ub, leaf.n(), leaf.m(), ou, ou.size())
    ffbc_copy_factor(leaf.ws(), wb, leaf.ww(), ov, ov.size())
    ffbc_copy_factor(leaf.vs(), vb, leaf.vw(), ow, ow.size())
  if code == 5
    ffbc_copy_factor(leaf.ws(), wb, leaf.ww(), ou, ou.size())
    ffbc_transpose_factor(leaf.vs(), vb, leaf.m(), leaf.p(), ov, ov.size())
    ffbc_copy_factor(leaf.us(), ub, leaf.uw(), ow, ow.size())
  0

# Materialise any of the six exact S3-equivalent tensor orientations.  Keeping
# this at scheme level lets recipe scans choose the cheapest axis ordering and
# still publish a certificate under the caller's canonical <n,m,p> shape.
-> ffbc_orient_scheme(scheme, code) (FFBCScheme i64)
  if scheme == nil || code < 0 || code >= 6 || ffbc_verify_exact(scheme) != 1
    return nil
  tn = scheme.n() ## i64
  tm = scheme.m() ## i64
  tp = scheme.p() ## i64
  if code == 1
    tn = scheme.m()
    tm = scheme.p()
    tp = scheme.n()
  elsif code == 2
    tn = scheme.p()
    tm = scheme.n()
    tp = scheme.m()
  elsif code == 3
    tn = scheme.p()
    tm = scheme.m()
    tp = scheme.n()
  elsif code == 4
    tn = scheme.m()
    tm = scheme.n()
    tp = scheme.p()
  elsif code == 5
    tn = scheme.n()
    tm = scheme.p()
    tp = scheme.m()

  result = FFBCScheme.new(tn, tm, tp, scheme.rank())
  u = i64[result.uw()]
  v = i64[result.vw()]
  w = i64[result.ww()]
  term = 0 ## i64
  while term < scheme.rank()
    ffbc_orient_term(scheme, term, code, u, v, w)
    ffbc_copy(u, 0, result.us(), term * result.uw(), result.uw())
    ffbc_copy(v, 0, result.vs(), term * result.vw(), result.vw())
    ffbc_copy(w, 0, result.ws(), term * result.ww(), result.ww())
    term += 1
  result.set_rank(scheme.rank())
  if ffbc_verify_exact(result) != 1
    return nil
  result

# Choose the lowest-rank exact leaf matching the requested orientation.
# Ties preserve caller order, then orientation-code order.
-> ffbc_find_leaf(leaves, tn, tm, tp, choice) (Array i64 i64 i64 i64[]) i64
  choice[0] = 0 - 1
  choice[1] = 0 - 1
  best_rank = 0x7fffffff ## i64
  li = 0 ## i64
  while li < leaves.size()
    leaf = leaves[li]
    code = 0 ## i64
    while code < 6
      if leaf.rank() < best_rank && ffbc_orientation_matches(code, leaf.n(), leaf.m(), leaf.p(), tn, tm, tp) == 1
        best_rank = leaf.rank()
        choice[0] = li
        choice[1] = code
      code += 1
    li += 1
  if choice[0] < 0
    return 0
  1

-> ffbc_embed(outer_data, outer_base, outer_rows, outer_cols, row_alloc, col_alloc, row_cum, col_cum, local_data, local_rows, local_cols, target_cols, output) (i64[] i64 i64 i64 i64[] i64[] i64[] i64[] i64[] i64 i64 i64 i64[]) i64
  ffbc_clear(output, 0, output.size())
  oi = 0 ## i64
  while oi < outer_rows
    oj = 0 ## i64
    while oj < outer_cols
      if ffbc_bit(outer_data, outer_base, oi * outer_cols + oj) == 1
        i = 0 ## i64
        while i < local_rows && i < row_alloc[oi]
          j = 0 ## i64
          while j < local_cols && j < col_alloc[oj]
            if ffbc_bit(local_data, 0, i * local_cols + j) == 1
              target_bit = (row_cum[oi] + i) * target_cols + col_cum[oj] + j ## i64
              ffbc_toggle_bit(output, 0, target_bit)
            j += 1
          i += 1
      oj += 1
    oi += 1
  0

-> ffbc_term_equal(scheme, term, u, v, w) (FFBCScheme i64 i64[] i64[] i64[]) i64
  if ffbc_words_equal(scheme.us(), term * scheme.uw(), u, 0, scheme.uw()) != 1
    return 0
  if ffbc_words_equal(scheme.vs(), term * scheme.vw(), v, 0, scheme.vw()) != 1
    return 0
  if ffbc_words_equal(scheme.ws(), term * scheme.ww(), w, 0, scheme.ww()) != 1
    return 0
  1

-> ffbc_term_hash(u, v, w, mask) (i64[] i64[] i64[] i64) i64
  h = 17 ## i64
  i = 0 ## i64
  while i < u.size()
    h = (h * 1000003 + u[i] + 97) & mask
    i += 1
  h = (h * 1000003 + 193) & mask
  i = 0
  while i < v.size()
    h = (h * 1000003 + v[i] + 389) & mask
    i += 1
  h = (h * 1000003 + 769) & mask
  i = 0
  while i < w.size()
    h = (h * 1000003 + w[i] + 1543) & mask
    i += 1
  h

# Add a term to a parity set.  `slots` maps a term fingerprint to its stable
# unique-term index; `active` toggles on every repeat.  This handles repeats
# of any multiplicity without deletion/tombstone complexity.
-> ffbc_toggle_term(scheme, u, v, w, slots, active, unique_rank) (FFBCScheme i64[] i64[] i64[] i64[] i64[] i64) i64
  if ffbc_factor_zero(u, 0, u.size()) == 1 || ffbc_factor_zero(v, 0, v.size()) == 1 || ffbc_factor_zero(w, 0, w.size()) == 1
    return unique_rank
  mask = slots.size() - 1 ## i64
  slot = ffbc_term_hash(u, v, w, mask) ## i64
  while slots[slot] != 0
    term = slots[slot] - 1 ## i64
    if ffbc_term_equal(scheme, term, u, v, w) == 1
      active[term] = active[term] ^ 1
      return unique_rank
    slot = (slot + 1) & mask
  if unique_rank >= scheme.capacity()
    return 0 - unique_rank - 1
  ffbc_copy(u, 0, scheme.us(), unique_rank * scheme.uw(), scheme.uw())
  ffbc_copy(v, 0, scheme.vs(), unique_rank * scheme.vw(), scheme.vw())
  ffbc_copy(w, 0, scheme.ws(), unique_rank * scheme.ww(), scheme.ww())
  active[unique_rank] = 1
  slots[slot] = unique_rank + 1
  unique_rank + 1

-> ffbc_compact(scheme, active, unique_rank) (FFBCScheme i64[] i64) i64
  write_at = 0 ## i64
  i = 0 ## i64
  while i < unique_rank
    if active[i] == 1
      if write_at != i
        ffbc_copy(scheme.us(), i * scheme.uw(), scheme.us(), write_at * scheme.uw(), scheme.uw())
        ffbc_copy(scheme.vs(), i * scheme.vw(), scheme.vs(), write_at * scheme.vw(), scheme.vw())
        ffbc_copy(scheme.ws(), i * scheme.ww(), scheme.ws(), write_at * scheme.ww(), scheme.ww())
      write_at += 1
    i += 1
  scheme.set_rank(write_at)
  write_at

# Formula rank before zero/duplicate cancellation.  This is cheap enough to
# scan all balanced block placements before materialising the best recipe.
-> ffbc_score_allocation(outer, alloc_n, alloc_m, alloc_p, leaves) (FFBCScheme i64[] i64[] i64[] Array) i64
  if outer == nil || alloc_n.size() != outer.n() || alloc_m.size() != outer.m() || alloc_p.size() != outer.p()
    return 0 - 1
  ue = i64[2]
  ve = i64[2]
  we = i64[2]
  choice = i64[2]
  total = 0 ## i64
  term = 0 ## i64
  while term < outer.rank()
    ffbc_extent(outer.us(), term * outer.uw(), outer.n(), outer.m(), alloc_n, alloc_m, ue)
    ffbc_extent(outer.vs(), term * outer.vw(), outer.m(), outer.p(), alloc_m, alloc_p, ve)
    ffbc_extent(outer.ws(), term * outer.ww(), outer.n(), outer.p(), alloc_n, alloc_p, we)
    sn = ue[0] ## i64
    if we[0] < sn
      sn = we[0]
    sm = ue[1] ## i64
    if ve[0] < sm
      sm = ve[0]
    sp = ve[1] ## i64
    if we[1] < sp
      sp = we[1]
    if sn > 0 && sm > 0 && sp > 0
      if ffbc_find_leaf(leaves, sn, sm, sp, choice) != 1
        return 0 - 1
      total += leaves[choice[0]].rank()
    term += 1
  total

-> ffbc_popcount_small(value) (i64) i64
  result = 0 ## i64
  x = value ## i64
  while x != 0
    result += x & 1
    x = x >> 1
  result

# All allocations whose parts differ by at most one, in deterministic mask
# order.  For a 4-way AlphaTensor outer there are at most six per axis.
-> ffbc_balanced_allocations(total, parts) (i64 i64)
  result = []
  if total < 0 || parts < 1 || parts > 20
    return result
  small = total / parts ## i64
  extra = total % parts ## i64
  mask = 0 ## i64
  limit = 1 << parts ## i64
  while mask < limit
    if ffbc_popcount_small(mask) == extra
      allocation = i64[parts]
      i = 0 ## i64
      while i < parts
        allocation[i] = small + ((mask >> i) & 1)
        i += 1
      result.push(allocation)
    mask += 1
  result

# Every ordered allocation with `parts` entries in the inclusive
# [minimum, maximum] interval and the requested sum.  The balanced scanner is
# intentionally retained above: it is the cheap production default.  This
# bounded enumerator is for the slower support-aware research pass, where an
# outer term can benefit from concentrating width on blocks outside one of its
# supports (for example 6,6,6,8 instead of 6,6,7,7 at total 26).
-> ffbc_bounded_allocations(total, parts, minimum, maximum) (i64 i64 i64 i64)
  result = []
  if parts < 1 || parts > 20 || minimum < 0 || maximum < minimum
    return result
  if total < parts * minimum || total > parts * maximum
    return result
  allocation = i64[parts]
  i = 0 ## i64
  while i < parts
    allocation[i] = minimum
    i += 1
  finished = 0 ## i64
  while finished == 0
    sum = 0 ## i64
    i = 0
    while i < parts
      sum += allocation[i]
      i += 1
    if sum == total
      copy = i64[parts]
      i = 0
      while i < parts
        copy[i] = allocation[i]
        i += 1
      result.push(copy)

    i = parts - 1
    while i >= 0 && allocation[i] == maximum
      allocation[i] = minimum
      i -= 1
    if i < 0
      finished = 1
    else
      next_value = allocation[i] + 1 ## i64
      allocation[i] = next_value
  result

# Return [alloc_n, alloc_m, alloc_p, nominal_rank] for the cheapest balanced
# support placement.  Materialisation may improve further by dropping mapped
# zero terms and cancelling duplicate triples.
-> ffbc_best_balanced_recipe(outer, target_n, target_m, target_p, leaves) (FFBCScheme i64 i64 i64 Array)
  nas = ffbc_balanced_allocations(target_n, outer.n())
  mas = ffbc_balanced_allocations(target_m, outer.m())
  pas = ffbc_balanced_allocations(target_p, outer.p())
  best = nil
  best_score = 0x7fffffff ## i64
  ni = 0 ## i64
  while ni < nas.size()
    mi = 0 ## i64
    while mi < mas.size()
      pi = 0 ## i64
      while pi < pas.size()
        score = ffbc_score_allocation(outer, nas[ni], mas[mi], pas[pi], leaves) ## i64
        if score >= 0 && score < best_score
          best_score = score
          best = [nas[ni], mas[mi], pas[pi], score]
        pi += 1
      mi += 1
    ni += 1
  best

# Bounded analogue of `ffbc_best_balanced_recipe`.  This is exhaustive over
# ordered placements, not just permutations of floor(total/parts) and its
# successor.  The supplied leaf pool must cover every induced effective shape
# in the chosen interval.
-> ffbc_best_bounded_recipe(outer, target_n, target_m, target_p, minimum, maximum, leaves) (FFBCScheme i64 i64 i64 i64 i64 Array)
  nas = ffbc_bounded_allocations(target_n, outer.n(), minimum, maximum)
  mas = ffbc_bounded_allocations(target_m, outer.m(), minimum, maximum)
  pas = ffbc_bounded_allocations(target_p, outer.p(), minimum, maximum)
  best = nil
  best_score = 0x7fffffff ## i64
  ni = 0 ## i64
  while ni < nas.size()
    mi = 0 ## i64
    while mi < mas.size()
      pi = 0 ## i64
      while pi < pas.size()
        score = ffbc_score_allocation(outer, nas[ni], mas[mi], pas[pi], leaves) ## i64
        if score >= 0 && score < best_score
          best_score = score
          best = [nas[ni], mas[mi], pas[pi], score]
        pi += 1
      mi += 1
    ni += 1
  best

# Precompute one outer factor's row/column support extents for every ordered
# pair of block allocations.  Extents are at most `maximum` in the bounded
# scanner, so one i64 can carry both values without allocation in the hot
# three-axis product.  This turns repeated 4x4 mask walks into table reads.
-> ffbc_pair_extent_codes(factors, width, rows, cols, row_allocations, column_allocations, rank) (i64[] i64 i64 i64 Array Array i64)
  row_count = row_allocations.size() ## i64
  column_count = column_allocations.size() ## i64
  result = i64[row_count * column_count * rank]
  extent = i64[2]
  ri = 0 ## i64
  while ri < row_count
    ci = 0 ## i64
    while ci < column_count
      term = 0 ## i64
      while term < rank
        ffbc_extent(factors, term * width, rows, cols,
                    row_allocations[ri], column_allocations[ci], extent)
        result[(ri * column_count + ci) * rank + term] = extent[0] | (extent[1] << 8)
        term += 1
      ci += 1
    ri += 1
  result

# Dense oriented rank lookup for every induced leaf shape in the requested
# bounded interval.  The production pool is tiny (84 exact leaves), but a
# linear pool scan inside every allocation/outer-term combination dominated
# the exhaustive small-cross pass.
-> ffbc_leaf_rank_table(leaves, maximum) (Array i64)
  stride = maximum + 1 ## i64
  table = i64[stride * stride * stride]
  i = 0 ## i64
  while i < table.size()
    table[i] = 0 - 1
    i += 1
  choice = i64[2]
  n = 1 ## i64
  while n <= maximum
    m = 1 ## i64
    while m <= maximum
      p = 1 ## i64
      while p <= maximum
        if ffbc_find_leaf(leaves, n, m, p, choice) == 1
          table[(n * stride + m) * stride + p] = leaves[choice[0]].rank()
        p += 1
      m += 1
    n += 1
  table

# Allocation-equivalent fast path for the exhaustive bounded scanner.  It
# preserves the exact traversal and first-minimum tie rule of
# `ffbc_best_bounded_recipe`, while precomputing all pairwise U/V/W support
# extents and using a dense oriented leaf-rank table.  Materialisation remains
# behind the ordinary exact gate; this routine changes formula scoring only.
-> ffbc_best_bounded_recipe_fast(outer, target_n, target_m, target_p, minimum, maximum, leaves) (FFBCScheme i64 i64 i64 i64 i64 Array)
  nas = ffbc_bounded_allocations(target_n, outer.n(), minimum, maximum)
  mas = ffbc_bounded_allocations(target_m, outer.m(), minimum, maximum)
  pas = ffbc_bounded_allocations(target_p, outer.p(), minimum, maximum)
  if nas.size() == 0 || mas.size() == 0 || pas.size() == 0
    return nil

  rank = outer.rank() ## i64
  u_codes = ffbc_pair_extent_codes(outer.us(), outer.uw(), outer.n(), outer.m(), nas, mas, rank)
  v_codes = ffbc_pair_extent_codes(outer.vs(), outer.vw(), outer.m(), outer.p(), mas, pas, rank)
  w_codes = ffbc_pair_extent_codes(outer.ws(), outer.ww(), outer.n(), outer.p(), nas, pas, rank)
  leaf_ranks = ffbc_leaf_rank_table(leaves, maximum)
  stride = maximum + 1 ## i64

  best = nil
  best_score = 0x7fffffff ## i64
  ni = 0 ## i64
  while ni < nas.size()
    mi = 0 ## i64
    while mi < mas.size()
      u_base = (ni * mas.size() + mi) * rank ## i64
      pi = 0 ## i64
      while pi < pas.size()
        v_base = (mi * pas.size() + pi) * rank ## i64
        w_base = (ni * pas.size() + pi) * rank ## i64
        score = 0 ## i64
        term = 0 ## i64
        while term < rank && score >= 0
          ue = u_codes[u_base + term] ## i64
          ve = v_codes[v_base + term] ## i64
          we = w_codes[w_base + term] ## i64
          sn = ue & 255 ## i64
          wn = we & 255 ## i64
          if wn < sn
            sn = wn
          sm = (ue >> 8) & 255 ## i64
          vm = ve & 255 ## i64
          if vm < sm
            sm = vm
          sp = (ve >> 8) & 255 ## i64
          wp = (we >> 8) & 255 ## i64
          if wp < sp
            sp = wp
          leaf_rank = 0 - 1 ## i64
          if sn <= maximum && sm <= maximum && sp <= maximum
            leaf_rank = leaf_ranks[(sn * stride + sm) * stride + sp]
          if leaf_rank < 0
            score = 0 - 1
          else
            score += leaf_rank
          term += 1
        if score >= 0 && score < best_score
          best_score = score
          best = [nas[ni], mas[mi], pas[pi], score]
        pi += 1
      mi += 1
    ni += 1
  best

# For a requested canonical target, recover the source dimensions whose
# orientation `code` maps back to that target.
-> ffbc_source_dims_for_orientation(code, target_n, target_m, target_p, dims) (i64 i64 i64 i64 i64[]) i64
  dims[0] = target_n
  dims[1] = target_m
  dims[2] = target_p
  if code == 1
    dims[0] = target_p
    dims[1] = target_n
    dims[2] = target_m
  elsif code == 2
    dims[0] = target_m
    dims[1] = target_p
    dims[2] = target_n
  elsif code == 3
    dims[0] = target_p
    dims[1] = target_m
    dims[2] = target_n
  elsif code == 4
    dims[0] = target_m
    dims[1] = target_n
    dims[2] = target_p
  elsif code == 5
    dims[0] = target_n
    dims[1] = target_p
    dims[2] = target_m
  0

# Scan every unique S3 ordering of the target.  The result is
# [alloc_n, alloc_m, alloc_p, formula_rank, source_n, source_m, source_p,
#  orientation_code].  Orientation order makes a direct target win ties,
# followed by axis swaps; this also keeps selection deterministic when target
# dimensions coincide.
-> ffbc_best_oriented_balanced_recipe(outer, target_n, target_m, target_p, leaves) (FFBCScheme i64 i64 i64 Array)
  codes = i64[6]
  codes[0] = 0
  codes[1] = 4
  codes[2] = 5
  codes[3] = 3
  codes[4] = 1
  codes[5] = 2
  seen_n = i64[6]
  seen_m = i64[6]
  seen_p = i64[6]
  seen_count = 0 ## i64
  source_dims = i64[3]
  best = nil
  best_score = 0x7fffffff ## i64
  ci = 0 ## i64
  while ci < 6
    code = codes[ci] ## i64
    ffbc_source_dims_for_orientation(code, target_n, target_m, target_p, source_dims)
    duplicate = 0 ## i64
    si = 0 ## i64
    while si < seen_count
      if seen_n[si] == source_dims[0] && seen_m[si] == source_dims[1] && seen_p[si] == source_dims[2]
        duplicate = 1
      si += 1
    if duplicate == 0
      seen_n[seen_count] = source_dims[0]
      seen_m[seen_count] = source_dims[1]
      seen_p[seen_count] = source_dims[2]
      seen_count += 1
      candidate = ffbc_best_balanced_recipe(outer, source_dims[0], source_dims[1], source_dims[2], leaves)
      if candidate != nil && candidate[3] < best_score
        best_score = candidate[3]
        best = [candidate[0], candidate[1], candidate[2], candidate[3],
                source_dims[0], source_dims[1], source_dims[2], code]
    ci += 1
  best

# Exhaust every unique S3 ordering and every ordered bounded allocation.
# Result layout matches `ffbc_best_oriented_balanced_recipe`, so the existing
# exact oriented materialiser can consume it directly.
-> ffbc_best_oriented_bounded_recipe(outer, target_n, target_m, target_p, minimum, maximum, leaves) (FFBCScheme i64 i64 i64 i64 i64 Array)
  codes = i64[6]
  codes[0] = 0
  codes[1] = 4
  codes[2] = 5
  codes[3] = 3
  codes[4] = 1
  codes[5] = 2
  seen_n = i64[6]
  seen_m = i64[6]
  seen_p = i64[6]
  seen_count = 0 ## i64
  source_dims = i64[3]
  best = nil
  best_score = 0x7fffffff ## i64
  ci = 0 ## i64
  while ci < 6
    code = codes[ci] ## i64
    ffbc_source_dims_for_orientation(code, target_n, target_m, target_p, source_dims)
    duplicate = 0 ## i64
    si = 0 ## i64
    while si < seen_count
      if seen_n[si] == source_dims[0] && seen_m[si] == source_dims[1] && seen_p[si] == source_dims[2]
        duplicate = 1
      si += 1
    if duplicate == 0
      seen_n[seen_count] = source_dims[0]
      seen_m[seen_count] = source_dims[1]
      seen_p[seen_count] = source_dims[2]
      seen_count += 1
      candidate = ffbc_best_bounded_recipe_fast(outer, source_dims[0], source_dims[1], source_dims[2], minimum, maximum, leaves)
      if candidate != nil && candidate[3] < best_score
        best_score = candidate[3]
        best = [candidate[0], candidate[1], candidate[2], candidate[3],
                source_dims[0], source_dims[1], source_dims[2], code]
    ci += 1
  best

# Compose one exact outer scheme under caller-supplied per-axis allocations.
# Every outer term selects the cheapest supplied leaf with a matching S3
# orientation.  Effective leaf sizes are the support-aware maxima/minima from
# Recombination.constructWithAllocation; embeddings truncate coordinates that
# do not fit a particular block.  Zero terms and duplicate triples cancel.
-> ffbc_compose(outer, alloc_n, alloc_m, alloc_p, leaves) (FFBCScheme i64[] i64[] i64[] Array)
  if outer == nil || alloc_n.size() != outer.n() || alloc_m.size() != outer.m() || alloc_p.size() != outer.p()
    return nil
  if ffbc_verify_exact(outer) != 1
    return nil
  li = 0 ## i64
  while li < leaves.size()
    if leaves[li] == nil || ffbc_verify_exact(leaves[li]) != 1
      return nil
    li += 1

  cum_n = ffbc_cumulative(alloc_n)
  cum_m = ffbc_cumulative(alloc_m)
  cum_p = ffbc_cumulative(alloc_p)
  target_n = cum_n[alloc_n.size()] ## i64
  target_m = cum_m[alloc_m.size()] ## i64
  target_p = cum_p[alloc_p.size()] ## i64
  if target_n < 1 || target_m < 1 || target_p < 1
    return nil

  ue = i64[2]
  ve = i64[2]
  we = i64[2]
  choice = i64[2]
  nominal = 0 ## i64
  term = 0 ## i64
  while term < outer.rank()
    ffbc_extent(outer.us(), term * outer.uw(), outer.n(), outer.m(), alloc_n, alloc_m, ue)
    ffbc_extent(outer.vs(), term * outer.vw(), outer.m(), outer.p(), alloc_m, alloc_p, ve)
    ffbc_extent(outer.ws(), term * outer.ww(), outer.n(), outer.p(), alloc_n, alloc_p, we)
    sn = ue[0] ## i64
    if we[0] < sn
      sn = we[0]
    sm = ue[1] ## i64
    if ve[0] < sm
      sm = ve[0]
    sp = ve[1] ## i64
    if we[1] < sp
      sp = we[1]
    if sn > 0 && sm > 0 && sp > 0
      if ffbc_find_leaf(leaves, sn, sm, sp, choice) != 1
        return nil
      nominal += leaves[choice[0]].rank()
    term += 1
  if nominal < 1
    return nil

  result = FFBCScheme.new(target_n, target_m, target_p, nominal)
  table_capacity = 16 ## i64
  while table_capacity < nominal * 4
    table_capacity *= 2
  slots = i64[table_capacity]
  active = i64[nominal]
  unique_rank = 0 ## i64
  nonzero_terms = 0 ## i64

  term = 0
  while term < outer.rank()
    ffbc_extent(outer.us(), term * outer.uw(), outer.n(), outer.m(), alloc_n, alloc_m, ue)
    ffbc_extent(outer.vs(), term * outer.vw(), outer.m(), outer.p(), alloc_m, alloc_p, ve)
    ffbc_extent(outer.ws(), term * outer.ww(), outer.n(), outer.p(), alloc_n, alloc_p, we)
    sn = ue[0]
    if we[0] < sn
      sn = we[0]
    sm = ue[1]
    if ve[0] < sm
      sm = ve[0]
    sp = ve[1]
    if we[1] < sp
      sp = we[1]
    if sn > 0 && sm > 0 && sp > 0
      if ffbc_find_leaf(leaves, sn, sm, sp, choice) != 1
        return nil
      leaf = leaves[choice[0]]
      code = choice[1] ## i64
      local_u = i64[ffbc_words(sn * sm)]
      local_v = i64[ffbc_words(sm * sp)]
      local_w = i64[ffbc_words(sn * sp)]
      global_u = i64[result.uw()]
      global_v = i64[result.vw()]
      global_w = i64[result.ww()]
      lt = 0 ## i64
      while lt < leaf.rank()
        ffbc_orient_term(leaf, lt, code, local_u, local_v, local_w)
        ffbc_embed(outer.us(), term * outer.uw(), outer.n(), outer.m(), alloc_n, alloc_m, cum_n, cum_m, local_u, sn, sm, target_m, global_u)
        ffbc_embed(outer.vs(), term * outer.vw(), outer.m(), outer.p(), alloc_m, alloc_p, cum_m, cum_p, local_v, sm, sp, target_p, global_v)
        ffbc_embed(outer.ws(), term * outer.ww(), outer.n(), outer.p(), alloc_n, alloc_p, cum_n, cum_p, local_w, sn, sp, target_p, global_w)
        if ffbc_factor_zero(global_u, 0, global_u.size()) != 1 && ffbc_factor_zero(global_v, 0, global_v.size()) != 1 && ffbc_factor_zero(global_w, 0, global_w.size()) != 1
          nonzero_terms += 1
        unique_rank = ffbc_toggle_term(result, global_u, global_v, global_w, slots, active, unique_rank)
        if unique_rank < 0
          return nil
        lt += 1
    term += 1

  final_rank = ffbc_compact(result, active, unique_rank) ## i64
  result.set_compose_audit(nominal, nominal - nonzero_terms, unique_rank, nonzero_terms - final_rank)
  if ffbc_verify_exact(result) != 1
    return nil
  result

# Formula scoring deliberately avoids materialisation, so several balanced
# allocation/S3 recipes can tie at the minimum while cancelling to different
# exact ranks.  Scan every formula-minimising tie and return the lowest exact
# one as [alloc_n, alloc_m, alloc_p, formula_rank, source_n, source_m,
# source_p, orientation_code, exact_rank].  Equal exact ranks preserve the
# deterministic orientation/mask traversal used by the formula selector.
-> ffbc_best_exact_oriented_balanced_recipe(outer, target_n, target_m, target_p, leaves) (FFBCScheme i64 i64 i64 Array)
  formula_best = ffbc_best_oriented_balanced_recipe(outer, target_n, target_m, target_p, leaves)
  if formula_best == nil
    return nil
  formula_rank = formula_best[3] ## i64
  codes = i64[6]
  codes[0] = 0
  codes[1] = 4
  codes[2] = 5
  codes[3] = 3
  codes[4] = 1
  codes[5] = 2
  seen_n = i64[6]
  seen_m = i64[6]
  seen_p = i64[6]
  seen_count = 0 ## i64
  source_dims = i64[3]
  best = nil
  best_exact_rank = 0x7fffffff ## i64
  ci = 0 ## i64
  while ci < 6
    code = codes[ci] ## i64
    ffbc_source_dims_for_orientation(code, target_n, target_m, target_p, source_dims)
    duplicate = 0 ## i64
    si = 0 ## i64
    while si < seen_count
      if seen_n[si] == source_dims[0] && seen_m[si] == source_dims[1] && seen_p[si] == source_dims[2]
        duplicate = 1
      si += 1
    if duplicate == 0
      seen_n[seen_count] = source_dims[0]
      seen_m[seen_count] = source_dims[1]
      seen_p[seen_count] = source_dims[2]
      seen_count += 1
      nas = ffbc_balanced_allocations(source_dims[0], outer.n())
      mas = ffbc_balanced_allocations(source_dims[1], outer.m())
      pas = ffbc_balanced_allocations(source_dims[2], outer.p())
      ni = 0 ## i64
      while ni < nas.size()
        mi = 0 ## i64
        while mi < mas.size()
          pi = 0 ## i64
          while pi < pas.size()
            score = ffbc_score_allocation(outer, nas[ni], mas[mi], pas[pi], leaves) ## i64
            if score == formula_rank
              candidate = ffbc_compose(outer, nas[ni], mas[mi], pas[pi], leaves)
              if candidate == nil
                return nil
              if candidate.rank() < best_exact_rank
                best_exact_rank = candidate.rank()
                best = [nas[ni], mas[mi], pas[pi], formula_rank,
                        source_dims[0], source_dims[1], source_dims[2], code,
                        best_exact_rank]
            pi += 1
          mi += 1
        ni += 1
    ci += 1
  best

# Materialise an oriented recipe and return an exact scheme under the original
# requested dimensions.
-> ffbc_compose_oriented_recipe(outer, target_n, target_m, target_p, leaves, recipe) (FFBCScheme i64 i64 i64 Array Array)
  if recipe == nil || recipe.size() < 8
    return nil
  source = ffbc_compose(outer, recipe[0], recipe[1], recipe[2], leaves)
  if source == nil
    return nil
  result = source
  if recipe[7] != 0
    result = ffbc_orient_scheme(source, recipe[7])
  if result == nil || result.n() != target_n || result.m() != target_m || result.p() != target_p || ffbc_verify_exact(result) != 1
    return nil
  result

-> ffbc_write(path, scheme) (String FFBCScheme) i64
  if scheme == nil || scheme.rank() < 1 || ffbc_verify_exact(scheme) != 1
    return 0 - 1
  lines = []
  t = 0 ## i64
  while t < scheme.rank()
    u = ffbc_words_to_decimal(scheme.us(), t * scheme.uw(), scheme.uw())
    v = ffbc_words_to_decimal(scheme.vs(), t * scheme.vw(), scheme.vw())
    w = ffbc_words_to_decimal(scheme.ws(), t * scheme.ww(), scheme.ww())
    lines.push("R " + u + " " + v + " " + w)
    t += 1
  if write_file(path, lines.join("\n") + "\n") == nil
    return 0 - 1
  scheme.rank()

# File-level convenience wrapper.  `leaf_paths` and dimension arrays are
# parallel.  All inputs and the final output are exact-gated before publish.
-> ffbc_compose_files(outer_path, outer_n, outer_m, outer_p, alloc_n, alloc_m, alloc_p, leaf_paths, leaf_ns, leaf_ms, leaf_ps, output_path) (String i64 i64 i64 i64[] i64[] i64[] Array i64[] i64[] i64[] String) i64
  outer = ffbc_load_exact(outer_path, outer_n, outer_m, outer_p, 4096)
  if outer == nil || leaf_paths.size() != leaf_ns.size() || leaf_paths.size() != leaf_ms.size() || leaf_paths.size() != leaf_ps.size()
    return 0 - 1
  leaves = []
  i = 0 ## i64
  while i < leaf_paths.size()
    leaf = ffbc_load_exact(leaf_paths[i], leaf_ns[i], leaf_ms[i], leaf_ps[i], 4096)
    if leaf == nil
      return 0 - 1
    leaves.push(leaf)
    i += 1
  result = ffbc_compose(outer, alloc_n, alloc_m, alloc_p, leaves)
  if result == nil
    return 0 - 1
  ffbc_write(output_path, result)
