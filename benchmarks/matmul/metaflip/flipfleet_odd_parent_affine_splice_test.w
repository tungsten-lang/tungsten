use flipfleet_odd_parent_affine_splice

-> ffoast_expect(label, condition) (String bool) i64
  if !condition
    << "ODD_PARENT_AFFINE_SPLICE_FAIL " + label
    exit(1)
  1

-> ffoast_toggle(us, vs, ws, rank, capacity, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
  found = 0 - 1 ## i64
  i = 0 ## i64
  while i < rank && found < 0
    if us[i] == u && vs[i] == v && ws[i] == w
      found = i
    i += 1
  if found >= 0
    rank -= 1
    us[found] = us[rank]
    vs[found] = vs[rank]
    ws[found] = ws[rank]
    return rank
  if rank >= capacity
    return 0 - 1
  us[rank] = u
  vs[rank] = v
  ws[rank] = w
  rank + 1

-> ffoast_add_zero_one(us, vs, ws, rank, capacity) (i64[] i64[] i64[] i64 i64) i64
  rank = ffoast_toggle(us, vs, ws, rank, capacity, 3, 3, 5)
  rank = ffoast_toggle(us, vs, ws, rank, capacity, 5, 3, 5)
  ffoast_toggle(us, vs, ws, rank, capacity, 6, 3, 5)

-> ffoast_add_zero_two(us, vs, ws, rank, capacity) (i64[] i64[] i64[] i64 i64) i64
  rank = ffoast_toggle(us, vs, ws, rank, capacity, 3, 5, 7)
  rank = ffoast_toggle(us, vs, ws, rank, capacity, 9, 5, 7)
  ffoast_toggle(us, vs, ws, rank, capacity, 10, 5, 7)

n = 2 ## i64
capacity = 64 ## i64
base_state = i64[ffw_state_size(capacity)]
base_rank = ffw_init_naive_cap(base_state, n, capacity, 930001, 0, 1, 1, 1) ## i64
ffoast_expect("naive exact", base_rank == 8 && ffw_verify_current_exact(base_state, n) == 1)
base_u = i64[capacity]
base_v = i64[capacity]
base_w = i64[capacity]
ffoast_expect("naive export", ffw_export_current(base_state, base_u, base_v, base_w) == base_rank)
base_cu = i64[capacity]
base_cv = i64[capacity]
base_cw = i64[capacity]
base_canonical_rank = ffoas_canonicalize(base_u, base_v, base_w, base_rank, base_cu, base_cv, base_cw) ## i64
ffoast_expect("naive canonical", base_canonical_rank == base_rank)

stride = capacity ## i64
bank_u = i64[3 * stride]
bank_v = i64[3 * stride]
bank_w = i64[3 * stride]
ranks = i64[3]
parent = 0 ## i64
while parent < 3
  raw_u = i64[capacity]
  raw_v = i64[capacity]
  raw_w = i64[capacity]
  ffoas_copy_slot(base_u, base_v, base_w, 0, raw_u, raw_v, raw_w, 0, base_rank)
  rank = base_rank ## i64
  if parent == 0 || parent == 2
    rank = ffoast_add_zero_one(raw_u, raw_v, raw_w, rank, capacity)
  if parent == 1 || parent == 2
    rank = ffoast_add_zero_two(raw_u, raw_v, raw_w, rank, capacity)
  canonical_u = i64[capacity]
  canonical_v = i64[capacity]
  canonical_w = i64[capacity]
  canonical_rank = ffoas_canonicalize(raw_u, raw_v, raw_w, rank, canonical_u, canonical_v, canonical_w) ## i64
  ranks[parent] = canonical_rank
  ffoas_copy_slot(canonical_u, canonical_v, canonical_w, 0, bank_u, bank_v, bank_w, parent * stride, canonical_rank)
  check = i64[ffw_state_size(capacity)]
  loaded = ffw_init_terms_cap(check, canonical_u, canonical_v, canonical_w, canonical_rank, n, capacity, 930101 + parent, 0, 1, 1, 1) ## i64
  ffoast_expect("parent exact", loaded == canonical_rank && ffw_verify_current_exact(check, n) == 1)
  parent += 1
ffoast_expect("planted parent ranks", ranks[0] == 11 && ranks[1] == 11 && ranks[2] == 14)

raw_u = i64[5 * capacity]
raw_v = i64[5 * capacity]
raw_w = i64[5 * capacity]
out_u = i64[5 * capacity]
out_v = i64[5 * capacity]
out_w = i64[5 * capacity]
triple = i64[3]
triple[0] = 0
triple[1] = 1
triple[2] = 2
triple_rank = ffoas_materialize(bank_u, bank_v, bank_w, stride, ranks, triple, 3, raw_u, raw_v, raw_w, out_u, out_v, out_w) ## i64
ffoast_expect("triple cancels shoulders", triple_rank == 8 && ffoas_equal_slot(base_cu, base_cv, base_cw, 0, base_rank, out_u, out_v, out_w, triple_rank) == 1)
triple_state = i64[ffw_state_size(5 * capacity)]
triple_loaded = ffw_init_terms_cap(triple_state, out_u, out_v, out_w, triple_rank, n, 5 * capacity, 930211, 0, 1, 1, 1) ## i64
ffoast_expect("triple full gate", triple_loaded == 8 && ffw_verify_current_exact(triple_state, n) == 1)
ffoast_expect("parent distances", ffoas_distance_slot(bank_u, bank_v, bank_w, 0, ranks[0], out_u, out_v, out_w, triple_rank) == 3 && ffoas_distance_slot(bank_u, bank_v, bank_w, stride, ranks[1], out_u, out_v, out_w, triple_rank) == 3 && ffoas_distance_slot(bank_u, bank_v, bank_w, 2 * stride, ranks[2], out_u, out_v, out_w, triple_rank) == 6)

# Even parity represents zero rather than M_2.
pair = i64[2]
pair[0] = 0
pair[1] = 1
pair_rank = ffoas_materialize(bank_u, bank_v, bank_w, stride, ranks, pair, 2, raw_u, raw_v, raw_w, out_u, out_v, out_w) ## i64
pair_state = i64[ffw_state_size(5 * capacity)]
pair_loaded = ffw_init_terms_cap(pair_state, out_u, out_v, out_w, pair_rank, n, 5 * capacity, 930223, 0, 1, 1, 1) ## i64
ffoast_expect("even parents are zero not tensor", pair_loaded < 0 && ffw_verify_current_exact(pair_state, n) == 0)

# Five parents remain affine-odd.  Repeating A and B twice cancels them and
# leaves C exactly; production enumeration itself uses distinct parents.
five = i64[5]
five[0] = 0
five[1] = 1
five[2] = 2
five[3] = 0
five[4] = 1
five_rank = ffoas_materialize(bank_u, bank_v, bank_w, stride, ranks, five, 5, raw_u, raw_v, raw_w, out_u, out_v, out_w) ## i64
ffoast_expect("five-parent odd parity", five_rank == ranks[2] && ffoas_equal_slot(bank_u, bank_v, bank_w, 2 * stride, ranks[2], out_u, out_v, out_w, five_rank) == 1)

# Bounded contract for the production Gray hull primitive.  Three affine
# parents have four odd endpoints; every incremental two-merge update must
# exactly equal independent selected-parent materialization and pass the full
# tensor gate.  The planted shoulders make the g=3 endpoint visibly collapse.
gray_u = i64[5 * capacity]
gray_v = i64[5 * capacity]
gray_w = i64[5 * capacity]
gray_tmp_u = i64[5 * capacity]
gray_tmp_v = i64[5 * capacity]
gray_tmp_w = i64[5 * capacity]
ffoas_copy_slot(bank_u, bank_v, bank_w, 0, gray_u, gray_v, gray_w, 0, ranks[0])
gray_rank = ranks[0] ## i64
previous_gray = 0 ## i64
index = 0 ## i64
while index < 4
  gray = index ^ (index >> 1) ## i64
  if index > 0
    changed = gray ^ previous_gray ## i64
    bit = 0 ## i64
    while ((changed >> bit) & 1) == 0
      bit += 1
    scratch_rank = ffoas_xor_sorted_slot(gray_u, gray_v, gray_w, gray_rank, bank_u, bank_v, bank_w, 0, ranks[0], gray_tmp_u, gray_tmp_v, gray_tmp_w) ## i64
    gray_rank = ffoas_xor_sorted_slot(gray_tmp_u, gray_tmp_v, gray_tmp_w, scratch_rank, bank_u, bank_v, bank_w, (bit + 1) * stride, ranks[bit + 1], gray_u, gray_v, gray_w) ## i64
  selection = i64[3]
  selection_count = 0 ## i64
  other_count = 0 ## i64
  bit = 0
  while bit < 2
    if ((gray >> bit) & 1) == 1
      selection[selection_count] = bit + 1
      selection_count += 1
      other_count += 1
    bit += 1
  if (other_count & 1) == 0
    move = selection_count ## i64
    while move > 0
      selection[move] = selection[move - 1]
      move -= 1
    selection[0] = 0
    selection_count += 1
  direct_rank = ffoas_materialize(bank_u, bank_v, bank_w, stride, ranks, selection, selection_count, raw_u, raw_v, raw_w, out_u, out_v, out_w) ## i64
  ffoast_expect("gray equals direct", gray_rank == direct_rank && ffoas_equal_slot(gray_u, gray_v, gray_w, 0, gray_rank, out_u, out_v, out_w, direct_rank) == 1)
  gray_state = i64[ffw_state_size(5 * capacity)]
  gray_loaded = ffw_init_terms_cap(gray_state, gray_u, gray_v, gray_w, gray_rank, n, 5 * capacity, 930301 + index, 0, 1, 1, 1) ## i64
  ffoast_expect("gray full gate", gray_loaded == gray_rank && ffw_verify_current_exact(gray_state, n) == 1)
  previous_gray = gray
  index += 1
ffoast_expect("gray planted collapse", gray_rank == ranks[2])

<< "flipfleet_odd_parent_affine_splice_test: all checks passed parents=" + ranks[0].to_s() + "/" + ranks[1].to_s() + "/" + ranks[2].to_s() + " triple_rank=" + triple_rank.to_s() + " pair_zero_rank=" + pair_rank.to_s() + " five_rank=" + five_rank.to_s() + " gray_endpoints=4"
