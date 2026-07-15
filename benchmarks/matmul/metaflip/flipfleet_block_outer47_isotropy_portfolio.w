# Exact GL(4,2)^3 support-orbit search for the rank-47 <4,4,4> outer.
#
# This differs from the older weighted-outer harness in two important ways:
#
# * one GL(4,2) domain is exhausted at a time (all 20,160 matrices), rather
#   than looking only one or two elementary transvections away; and
# * the target set is the current 56-row small-cross frontier: the 54 bounded
#   d450 formulas one through twelve ranks above an explicit GF(2) comparator,
#   plus the new 10x16x16 and 10x16x17 unbalanced winners.
#
# Random starts choose one complete GL matrix independently on I/K/J, then
# exact block-coordinate descent exhausts GL(4,2) on each domain.  Every
# returned outer endpoint is reconstructed exactly.  A target endpoint is
# also fully composed, oriented, reconstructed, serialized, reloaded, and
# reconstructed again before it can be reported as a numerical candidate.
# Nothing is written into the repository; candidate artifacts go to /tmp.
#
# Build and run from the repository root:
#
#   bin/tungsten compile --release --lto -o /tmp/outer47-isotropy \
#     benchmarks/matmul/metaflip/flipfleet_block_outer47_isotropy_portfolio.w
#   /tmp/outer47-isotropy selftest
#   /tmp/outer47-isotropy search 4 0 1 d450
#   /tmp/outer47-isotropy search 4 0 1 d677

use flipfleet_leaf_conjugation
use flipfleet_block_leaf_pool

-> ffo47i_fail(message)
  << "OUTER47_ISOTROPY_FAIL " + message
  exit(1)
  0

-> ffo47i_alloc(text) (String)
  fields = text.split(",")
  if fields.size() != 4
    return nil
  result = i64[4]
  i = 0 ## i64
  while i < 4
    result[i] = fields[i].to_i()
    if result[i] < 2 || result[i] > 8
      return nil
    i += 1
  result

-> ffo47i_dims(text) (String)
  fields = text.split("x")
  if fields.size() != 3
    return nil
  result = i64[3]
  i = 0 ## i64
  while i < 3
    result[i] = fields[i].to_i()
    if result[i] < 1
      return nil
    i += 1
  result

-> ffo47i_rank_table(leaves) (Array)
  table = i64[9 * 9 * 9]
  i = 0 ## i64
  while i < table.size()
    table[i] = 0 - 1
    i += 1
  choice = i64[2]
  n = 2 ## i64
  while n <= 8
    m = 2 ## i64
    while m <= 8
      p = 2 ## i64
      while p <= 8
        if ffbc_find_leaf(leaves, n, m, p, choice) == 1
          table[(n * 9 + m) * 9 + p] = leaves[choice[0]].rank()
        p += 1
      m += 1
    n += 1
  table

-> ffo47i_extent_code(mask, row_alloc, col_alloc) (i64 i64[] i64[]) i64
  row = 0 ## i64
  col = 0 ## i64
  if (mask & 0x000f) != 0
    row = row_alloc[0]
  if (mask & 0x00f0) != 0 && row_alloc[1] > row
    row = row_alloc[1]
  if (mask & 0x0f00) != 0 && row_alloc[2] > row
    row = row_alloc[2]
  if (mask & 0xf000) != 0 && row_alloc[3] > row
    row = row_alloc[3]
  if (mask & 0x1111) != 0
    col = col_alloc[0]
  if (mask & 0x2222) != 0 && col_alloc[1] > col
    col = col_alloc[1]
  if (mask & 0x4444) != 0 && col_alloc[2] > col
    col = col_alloc[2]
  if (mask & 0x8888) != 0 && col_alloc[3] > col
    col = col_alloc[3]
  row * 9 + col

-> ffo47i_score_masks(us, vs, ws, rank, alloc_n, alloc_m, alloc_p, ranks) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[]) i64
  total = 0 ## i64
  term = 0 ## i64
  while term < rank
    ucode = ffo47i_extent_code(us[term], alloc_n, alloc_m) ## i64
    vcode = ffo47i_extent_code(vs[term], alloc_m, alloc_p) ## i64
    wcode = ffo47i_extent_code(ws[term], alloc_n, alloc_p) ## i64
    sn = ucode / 9 ## i64
    wn = wcode / 9 ## i64
    if wn < sn
      sn = wn
    sm = ucode % 9 ## i64
    vm = vcode / 9 ## i64
    if vm < sm
      sm = vm
    sp = vcode % 9 ## i64
    wp = wcode % 9 ## i64
    if wp < sp
      sp = wp
    if sn > 0 && sm > 0 && sp > 0
      leaf_rank = ranks[(sn * 9 + sm) * 9 + sp] ## i64
      if leaf_rank < 1
        return 0 - 1
      total += leaf_rank
    term += 1
  total

-> ffo47i_score(outer, alloc_n, alloc_m, alloc_p, ranks) (FFBCScheme i64[] i64[] i64[] i64[]) i64
  if outer == nil || outer.n() != 4 || outer.m() != 4 || outer.p() != 4 || outer.uw() != 1 || outer.vw() != 1 || outer.ww() != 1
    return 0 - 1
  ffo47i_score_masks(outer.us(), outer.vs(), outer.ws(), outer.rank(), alloc_n, alloc_m, alloc_p, ranks)

# Invert a row-packed 4x4 GF(2) matrix.  A negative return means singular.
-> ffo47i_inverse(code) (i64) i64
  rows = i64[4]
  inverse = i64[4]
  r = 0 ## i64
  while r < 4
    rows[r] = (code >> (r * 4)) & 15
    inverse[r] = 1 << r
    r += 1
  column = 0 ## i64
  while column < 4
    pivot = column ## i64
    while pivot < 4 && (rows[pivot] & (1 << column)) == 0
      pivot += 1
    if pivot == 4
      return 0 - 1
    if pivot != column
      swap = rows[column] ## i64
      rows[column] = rows[pivot]
      rows[pivot] = swap
      swap = inverse[column]
      inverse[column] = inverse[pivot]
      inverse[pivot] = swap
    r = 0
    while r < 4
      if r != column && (rows[r] & (1 << column)) != 0
        rows[r] = rows[r] ^ rows[column]
        inverse[r] = inverse[r] ^ inverse[column]
      r += 1
    column += 1
  result = 0 ## i64
  r = 0
  while r < 4
    result = result | (inverse[r] << (r * 4))
    r += 1
  result

-> ffo47i_transpose(code) (i64) i64
  result = 0 ## i64
  r = 0 ## i64
  while r < 4
    c = 0 ## i64
    while c < 4
      if (code & (1 << (r * 4 + c))) != 0
        result = result | (1 << (c * 4 + r))
      c += 1
    r += 1
  result

-> ffo47i_parity4(value) (i64) i64
  value = value ^ (value >> 2)
  value = value ^ (value >> 1)
  value & 1

# Left multiplication of one row-packed 4x4 factor by `matrix`.
-> ffo47i_left(matrix, mask) (i64 i64) i64
  result = 0 ## i64
  r = 0 ## i64
  while r < 4
    selector = (matrix >> (r * 4)) & 15 ## i64
    row = 0 ## i64
    s = 0 ## i64
    while s < 4
      if (selector & (1 << s)) != 0
        row = row ^ ((mask >> (s * 4)) & 15)
      s += 1
    result = result | (row << (r * 4))
    r += 1
  result

# Right multiplication by matrix^T.  Each output column is the parity
# against one row of matrix.
-> ffo47i_right_transpose(mask, matrix) (i64 i64) i64
  result = 0 ## i64
  r = 0 ## i64
  while r < 4
    input_row = (mask >> (r * 4)) & 15 ## i64
    output_row = 0 ## i64
    c = 0 ## i64
    while c < 4
      matrix_row = (matrix >> (c * 4)) & 15 ## i64
      if ffo47i_parity4(input_row & matrix_row) == 1
        output_row = output_row | (1 << c)
      c += 1
    result = result | (output_row << (r * 4))
    r += 1
  result

# Apply A on one physical matrix index and the contragredient action on its
# paired factor.  This is the direct-matrix form of the authoritative
# transvections in flipfleet_partial_automorphism.
-> ffo47i_transform_term(u, v, w, axis, matrix, inverse, output) (i64 i64 i64 i64 i64 i64 i64[]) i64
  output[0] = u
  output[1] = v
  output[2] = w
  inverse_transpose = ffo47i_transpose(inverse) ## i64
  if axis == 0
    output[0] = ffo47i_left(matrix, u)
    output[2] = ffo47i_left(inverse_transpose, w)
  elsif axis == 1
    output[0] = ffo47i_right_transpose(u, matrix)
    output[1] = ffo47i_left(inverse_transpose, v)
  elsif axis == 2
    output[1] = ffo47i_right_transpose(v, matrix)
    output[2] = ffo47i_right_transpose(w, ffo47i_transpose(inverse))
  else
    return 0
  1

-> ffo47i_apply_matrix(outer, axis, matrix, inverse) (FFBCScheme i64 i64 i64) i64
  transformed = i64[3]
  term = 0 ## i64
  while term < outer.rank()
    if ffo47i_transform_term(outer.us()[term], outer.vs()[term], outer.ws()[term], axis, matrix, inverse, transformed) != 1
      return 0
    outer.us()[term] = transformed[0]
    outer.vs()[term] = transformed[1]
    outer.ws()[term] = transformed[2]
    term += 1
  1

-> ffo47i_score_axis(outer, axis, matrix, inverse, alloc_n, alloc_m, alloc_p, ranks) (FFBCScheme i64 i64 i64 i64[] i64[] i64[] i64[]) i64
  total = 0 ## i64
  inverse_transpose = ffo47i_transpose(inverse) ## i64
  term = 0 ## i64
  while term < outer.rank()
    u = outer.us()[term] ## i64
    v = outer.vs()[term] ## i64
    w = outer.ws()[term] ## i64
    if axis == 0
      u = ffo47i_left(matrix, u)
      w = ffo47i_left(inverse_transpose, w)
    elsif axis == 1
      u = ffo47i_right_transpose(u, matrix)
      v = ffo47i_left(inverse_transpose, v)
    elsif axis == 2
      v = ffo47i_right_transpose(v, matrix)
      w = ffo47i_right_transpose(w, inverse_transpose)
    else
      return 0 - 1
    ucode = ffo47i_extent_code(u, alloc_n, alloc_m) ## i64
    vcode = ffo47i_extent_code(v, alloc_m, alloc_p) ## i64
    wcode = ffo47i_extent_code(w, alloc_n, alloc_p) ## i64
    sn = ucode / 9 ## i64
    wn = wcode / 9 ## i64
    if wn < sn
      sn = wn
    sm = ucode % 9 ## i64
    vm = vcode / 9 ## i64
    if vm < sm
      sm = vm
    sp = vcode % 9 ## i64
    wp = wcode % 9 ## i64
    if wp < sp
      sp = wp
    if sn > 0 && sm > 0 && sp > 0
      leaf_rank = ranks[(sn * 9 + sm) * 9 + sp] ## i64
      if leaf_rank < 1
        return 0 - 1
      total += leaf_rank
    term += 1
  total

-> ffo47i_gl(codes, inverses) (i64[] i64[]) i64
  code = 0 ## i64
  count = 0 ## i64
  while code < 65536
    inverse = ffo47i_inverse(code) ## i64
    if inverse >= 0
      if count >= codes.size()
        return 0 - 1
      codes[count] = code
      inverses[count] = inverse
      count += 1
    code += 1
  count

-> ffo47i_next(rng) (i64[]) i64
  rng[0] = (rng[0] * 6364136223846793005 + 1442695040888963407) & 9223372036854775807
  (rng[0] >> 24) & 2147483647

# Exhaust one complete GL domain at a time.  `stats` contains final score,
# accepted complete-domain moves, evaluated matrices, and sweeps.
-> ffo47i_block_descent(source, alloc_n, alloc_m, alloc_p, ranks, codes, inverses, max_sweeps, stats) (FFBCScheme i64[] i64[] i64[] i64[] i64[] i64[] i64 i64[])
  current = fflc_clone(source)
  current_score = ffo47i_score(current, alloc_n, alloc_m, alloc_p, ranks) ## i64
  if current == nil || current_score < 1
    return nil
  accepted = 0 ## i64
  evaluations = 0 ## i64
  sweep = 0 ## i64
  running = 1 ## i64
  while running == 1 && sweep < max_sweeps
    changed = 0 ## i64
    step = 0 ## i64
    while step < 3
      axis = (step + sweep) % 3 ## i64
      best_score = current_score ## i64
      best_index = 0 - 1 ## i64
      i = 0 ## i64
      while i < codes.size()
        score = ffo47i_score_axis(current, axis, codes[i], inverses[i], alloc_n, alloc_m, alloc_p, ranks) ## i64
        evaluations += 1
        if score > 0 && score < best_score
          best_score = score
          best_index = i
        i += 1
      if best_index >= 0
        if ffo47i_apply_matrix(current, axis, codes[best_index], inverses[best_index]) != 1
          ffo47i_fail("accepted GL matrix")
        current_score = best_score
        accepted += 1
        changed = 1
      step += 1
    sweep += 1
    if changed == 0
      running = 0
  if ffbc_verify_exact(current) != 1
    ffo47i_fail("block-descent endpoint exact gate")
  if ffo47i_score(current, alloc_n, alloc_m, alloc_p, ranks) != current_score
    ffo47i_fail("block-descent endpoint score gate")
  stats[0] = current_score
  stats[1] = accepted
  stats[2] = evaluations
  stats[3] = sweep
  current

-> ffo47i_random_start(source, rng, codes, inverses) (FFBCScheme i64[] i64[] i64[])
  current = fflc_clone(source)
  axis = 0 ## i64
  while axis < 3
    index = ffo47i_next(rng) % codes.size() ## i64
    if ffo47i_apply_matrix(current, axis, codes[index], inverses[index]) != 1
      return nil
    axis += 1
  current

# Row/column support descriptor used by block composition.  Equality is
# deliberately stricter than a scalar hash and ignores only outer-term order.
-> ffo47i_factor_support(mask) (i64) i64
  rows = 0 ## i64
  cols = 0 ## i64
  r = 0 ## i64
  while r < 4
    row = (mask >> (r * 4)) & 15 ## i64
    if row != 0
      rows = rows | (1 << r)
      cols = cols | row
    r += 1
  rows | (cols << 4)

-> ffo47i_term_support(outer, term) (FFBCScheme i64) i64
  ffo47i_factor_support(outer.us()[term]) | (ffo47i_factor_support(outer.vs()[term]) << 8) | (ffo47i_factor_support(outer.ws()[term]) << 16)

-> ffo47i_support_distance(left, right) (FFBCScheme FFBCScheme) i64
  if left == nil || right == nil
    return 0 - 1
  used = i64[right.rank()]
  common = 0 ## i64
  i = 0 ## i64
  while i < left.rank()
    descriptor = ffo47i_term_support(left, i) ## i64
    found = 0 ## i64
    j = 0 ## i64
    while j < right.rank() && found == 0
      if used[j] == 0 && descriptor == ffo47i_term_support(right, j)
        used[j] = 1
        common += 1
        found = 1
      j += 1
    i += 1
  left.rank() + right.rank() - common - common

-> ffo47i_lookup_exact(body, target) (String String) i64
  lines = body.split("\n")
  i = 1 ## i64
  while i < lines.size()
    if lines[i].starts_with?(target + "\t")
      fields = lines[i].split("\t")
      if fields.size() >= 3
        return fields[2].to_i()
    i += 1
  0 - 1

# Push the current production allocation for one row.  The parallel arrays
# keep the hot search loop free of string parsing or dynamic records.
-> ffo47i_push_target(fields, exact_body, names, dims, formulas, exacts, comparators, alloc_ns, alloc_ms, alloc_ps, codes) (Array String Array Array i64[] i64[] i64[] Array Array Array i64[]) i64
  target_dims = ffo47i_dims(fields[0])
  an = ffo47i_alloc(fields[16])
  am = ffo47i_alloc(fields[17])
  ap = ffo47i_alloc(fields[18])
  if target_dims == nil || an == nil || am == nil || ap == nil
    return 0
  index = names.size() ## i64
  names.push(fields[0])
  dims.push(target_dims)
  formulas[index] = fields[2].to_i()
  comparators[index] = fields[5].to_i()
  exact_rank = ffo47i_lookup_exact(exact_body, fields[0]) ## i64
  if fields[0] == "10x16x16"
    exact_rank = 1558
  if fields[0] == "10x16x17"
    exact_rank = 1694
  if exact_rank < 1
    exact_rank = formulas[index]
  exacts[index] = exact_rank
  alloc_ns.push(an)
  alloc_ms.push(am)
  alloc_ps.push(ap)
  codes[index] = fields[20].to_i()
  1

-> ffo47i_portfolio(root, names, dims, formulas, exacts, comparators, alloc_ns, alloc_ms, alloc_ps, orientation_codes, stats) (String Array Array i64[] i64[] i64[] Array Array Array i64[] i64[]) i64
  full_body = read_file(root + "block_composition_small_cross_unbalanced_full_audit.tsv")
  exact_body = read_file(root + "block_composition_small_cross_bounded_tie_exact_audit.tsv")
  if full_body == nil || exact_body == nil
    return 0
  lines = full_body.split("\n")
  near_losses = 0 ## i64
  winners = 0 ## i64
  i = 1 ## i64
  while i < lines.size()
    if lines[i].size() > 0 && !lines[i].starts_with?("SUMMARY")
      fields = lines[i].split("\t")
      if fields.size() != 21
        return 0
      formula = fields[2].to_i() ## i64
      comparator = fields[5].to_i() ## i64
      gap = formula - comparator ## i64
      selected = 0 ## i64
      if fields[5].size() > 0 && gap >= 1 && gap <= 12
        selected = 1
        near_losses += 1
      if fields[0] == "10x16x16" || fields[0] == "10x16x17"
        selected = 1
        winners += 1
      if selected == 1
        if ffo47i_push_target(fields, exact_body, names, dims, formulas, exacts, comparators, alloc_ns, alloc_ms, alloc_ps, orientation_codes) != 1
          return 0
    i += 1
  stats[0] = near_losses
  stats[1] = winners
  names.size()

-> ffo47i_write_outer(path, outer) (String FFBCScheme) i64
  if ffbc_verify_exact(outer) != 1 || ffbc_write(path, outer) != 47
    return 0
  reloaded = ffbc_load_exact(path, 4, 4, 4, 128)
  if reloaded == nil || reloaded.rank() != 47 || ffbc_verify_exact(reloaded) != 1 || fflc_equal(reloaded, outer) != 1
    return 0
  1

-> ffo47i_compose_gate(outer, target_dims, alloc_n, alloc_m, alloc_p, orientation_code, leaves) (FFBCScheme i64[] i64[] i64[] i64[] i64 Array)
  source = ffbc_compose(outer, alloc_n, alloc_m, alloc_p, leaves)
  if source == nil || ffbc_verify_exact(source) != 1
    return nil
  candidate = source
  if orientation_code != 0
    candidate = ffbc_orient_scheme(source, orientation_code)
  if candidate == nil || candidate.n() != target_dims[0] || candidate.m() != target_dims[1] || candidate.p() != target_dims[2] || ffbc_verify_exact(candidate) != 1
    return nil
  candidate

-> ffo47i_search_target(source, source_label, base450, outer677, name, target_dims, base_formula, current_exact, comparator, alloc_n, alloc_m, alloc_p, orientation_code, leaves, ranks, gl_codes, gl_inverses, restarts, seed, bank, bank_paths) (FFBCScheme String FFBCScheme FFBCScheme String i64[] i64 i64 i64 i64[] i64[] i64[] i64 Array i64[] i64[] i64[] i64 i64 Array Array) i64
  rng = i64[1]
  rng[0] = seed & 9223372036854775807
  best = nil
  best_score = 0x7fffffff ## i64
  best_distance = 0 - 1 ## i64
  total_evaluations = 0 ## i64
  total_moves = 0 ## i64
  total_sweeps = 0 ## i64
  run = 0 ## i64
  while run <= restarts
    start = source
    if run > 0
      start = ffo47i_random_start(source, rng, gl_codes, gl_inverses)
    if start == nil
      ffo47i_fail("random GL start " + name)
    descent_stats = i64[4]
    endpoint = ffo47i_block_descent(start, alloc_n, alloc_m, alloc_p, ranks, gl_codes, gl_inverses, 6, descent_stats)
    if endpoint == nil
      ffo47i_fail("GL block descent " + name)
    score = descent_stats[0] ## i64
    distance = ffo47i_support_distance(base450, endpoint) ## i64
    if best == nil || score < best_score || (score == best_score && distance > best_distance)
      best = endpoint
      best_score = score
      best_distance = distance
    total_evaluations += descent_stats[2]
    total_moves += descent_stats[1]
    total_sweeps += descent_stats[3]
    run += 1

  if best == nil || ffbc_verify_exact(best) != 1
    ffo47i_fail("best outer endpoint gate " + name)
  exact_candidate = ffo47i_compose_gate(best, target_dims, alloc_n, alloc_m, alloc_p, orientation_code, leaves)
  if exact_candidate == nil
    ffo47i_fail("composed endpoint gate " + name)
  exact_rank = exact_candidate.rank() ## i64
  formula_gain = base_formula - best_score ## i64
  exact_gain = current_exact - exact_rank ## i64
  comparator_gain = comparator - exact_rank ## i64
  raw_distance = fflc_term_set_distance(base450, best) ## i64
  control_distance = ffo47i_support_distance(outer677, best) ## i64

  output = "-" ## String
  candidate = 0 ## i64
  if formula_gain > 0 || exact_gain > 0
    candidate = 1
    duplicate = 0 - 1 ## i64
    bi = 0 ## i64
    while bi < bank.size() && duplicate < 0
      if ffo47i_support_distance(bank[bi], best) == 0
        duplicate = bi
      bi += 1
    if duplicate >= 0
      output = bank_paths[duplicate]
    elsif best_distance > 0 && control_distance > 0
      output = "/tmp/matmul_4x4_rank47_outer_isotropy_" + source_label + "_" + name + "_f" + best_score.to_s() + "_gf2.txt"
      if ffo47i_write_outer(output, best) != 1
        ffo47i_fail("candidate outer serialize/reparse " + name)
      bank.push(best)
      bank_paths.push(output)
    else
      output = "source-pattern"

    exact_output = "/tmp/matmul_" + name + "_rank" + exact_rank.to_s() + "_outer47_isotropy_" + source_label + "_gf2.txt"
    if ffbc_write(exact_output, exact_candidate) != exact_rank
      ffo47i_fail("candidate composition write " + name)
    reloaded = ffbc_load_exact(exact_output, target_dims[0], target_dims[1], target_dims[2], exact_rank + 8)
    if reloaded == nil || reloaded.rank() != exact_rank || ffbc_verify_exact(reloaded) != 1
      ffo47i_fail("candidate composition serialize/reparse " + name)
    output = output + ";" + exact_output

  row = "OUTER47_ISOTROPY_ROW\t" + name + "\t" + source_label
  row = row + "\t" + base_formula.to_s() + "\t" + best_score.to_s() + "\t" + formula_gain.to_s()
  row = row + "\t" + current_exact.to_s() + "\t" + exact_rank.to_s() + "\t" + exact_gain.to_s()
  row = row + "\t" + comparator.to_s() + "\t" + comparator_gain.to_s()
  row = row + "\t" + best_distance.to_s() + "\t" + raw_distance.to_s() + "\t" + control_distance.to_s()
  row = row + "\t" + total_moves.to_s() + "\t" + total_sweeps.to_s() + "\t" + total_evaluations.to_s()
  row = row + "\t" + candidate.to_s() + "\t" + output
  << row
  candidate

av = argv()
if av.size() < 1 || av.size() > 5 || (av[0] != "selftest" && av[0] != "search")
  << "usage: outer47-isotropy selftest | search RESTARTS SHARD_ID SHARD_COUNT d450-or-d677"
  exit(1)

root = "benchmarks/matmul/metaflip/"
outer450 = ffbc_load_exact(root + "matmul_4x4_rank47_d450_gf2.txt", 4, 4, 4, 128)
outer677 = ffbc_load_exact(root + "matmul_4x4_rank47_d677_flips_gf2.txt", 4, 4, 4, 128)
leaves = ffbcp_stable_2_to_8(root)
if outer450 == nil || outer677 == nil || leaves.size() != 84 || ffbc_verify_exact(outer450) != 1 || ffbc_verify_exact(outer677) != 1
  ffo47i_fail("exact inputs")
ranks = ffo47i_rank_table(leaves)
gl_codes = i64[20160]
gl_inverses = i64[20160]
gl_count = ffo47i_gl(gl_codes, gl_inverses) ## i64
if gl_count != 20160
  ffo47i_fail("expected 20160 GL(4,2) matrices, got " + gl_count.to_s())

names = []
dims = []
formulas = i64[64]
exacts = i64[64]
comparators = i64[64]
alloc_ns = []
alloc_ms = []
alloc_ps = []
orientation_codes = i64[64]
portfolio_stats = i64[2]
portfolio_count = ffo47i_portfolio(root, names, dims, formulas, exacts, comparators, alloc_ns, alloc_ms, alloc_ps, orientation_codes, portfolio_stats) ## i64
if portfolio_count != 56 || portfolio_stats[0] != 54 || portfolio_stats[1] != 2
  ffo47i_fail("expected 54 near losses plus two winners, got " + portfolio_count.to_s())

if av[0] == "selftest"
  # Direct complete-matrix actions must agree with every authoritative
  # elementary transvection, then invert exactly on each physical domain.
  axis = 0 ## i64
  checked = 0 ## i64
  while axis < 3
    dst = 0 ## i64
    while dst < 4
      src = 0 ## i64
      while src < 4
        if src != dst
          matrix = 0x8421 | (1 << (dst * 4 + src)) ## i64
          inverse = ffo47i_inverse(matrix) ## i64
          direct = fflc_clone(outer450)
          if ffo47i_apply_matrix(direct, axis, matrix, inverse) != 1
            ffo47i_fail("direct transvection")
          authoritative = fflc_transvection(outer450, axis, dst, src)
          if authoritative == nil || fflc_equal(direct, authoritative) != 1 || ffbc_verify_exact(direct) != 1
            ffo47i_fail("matrix/transvection mismatch axis=" + axis.to_s() + " dst=" + dst.to_s() + " src=" + src.to_s())
          checked += 1
        src += 1
      dst += 1
    axis += 1

  probes = i64[3]
  probes[0] = 17
  probes[1] = 1009
  probes[2] = 19001
  axis = 0
  while axis < 3
    index = probes[axis] ## i64
    image = fflc_clone(outer450)
    if ffo47i_apply_matrix(image, axis, gl_codes[index], gl_inverses[index]) != 1 || ffo47i_apply_matrix(image, axis, gl_inverses[index], gl_codes[index]) != 1
      ffo47i_fail("matrix inverse replay")
    if fflc_equal(image, outer450) != 1
      ffo47i_fail("matrix inverse mismatch")
    axis += 1

  replayed = 0 ## i64
  i = 0 ## i64
  while i < names.size()
    fast = ffo47i_score(outer450, alloc_ns[i], alloc_ms[i], alloc_ps[i], ranks) ## i64
    authoritative = ffbc_score_allocation(outer450, alloc_ns[i], alloc_ms[i], alloc_ps[i], leaves) ## i64
    if fast != formulas[i] || fast != authoritative
      ffo47i_fail("portfolio formula replay " + names[i] + " fast=" + fast.to_s() + " pinned=" + formulas[i].to_s())
    replayed += 1
    i += 1
  << "PASS outer47 isotropy portfolio gl=" + gl_count.to_s() + " transvections=" + checked.to_s() + " targets=" + replayed.to_s() + " near_losses=" + portfolio_stats[0].to_s() + " winners=" + portfolio_stats[1].to_s()
  exit(0)

restarts = 2 ## i64
shard_id = 0 ## i64
shard_count = 1 ## i64
source_label = "d450" ## String
if av.size() >= 2
  restarts = av[1].to_i()
if av.size() >= 3
  shard_id = av[2].to_i()
if av.size() >= 4
  shard_count = av[3].to_i()
if av.size() >= 5
  source_label = av[4]
if restarts < 0 || restarts > 64 || shard_count < 1 || shard_id < 0 || shard_id >= shard_count || (source_label != "d450" && source_label != "d677")
  ffo47i_fail("invalid search arguments")
source = outer450
if source_label == "d677"
  source = outer677

<< "target\tsource\tbase_formula\tbest_formula\tformula_gain\tcurrent_exact\texact_rank\texact_gain\tf2_comparator\tcomparator_gain\tsupport_distance_d450\tterm_distance_d450\tsupport_distance_d677\taccepted_gl_moves\tsweeps\tgl_evaluations\tnumerical_candidate\toutputs"
bank = []
bank_paths = []
started = ccall("__w_clock_ms") ## i64
checked = 0 ## i64
candidates = 0 ## i64
i = 0 ## i64
while i < names.size()
  if i % shard_count == shard_id
    seed = 47000001 + i * 1000003 + restarts * 7919 ## i64
    candidates += ffo47i_search_target(source, source_label, outer450, outer677, names[i], dims[i], formulas[i], exacts[i], comparators[i], alloc_ns[i], alloc_ms[i], alloc_ps[i], orientation_codes[i], leaves, ranks, gl_codes, gl_inverses, restarts, seed, bank, bank_paths)
    checked += 1
  i += 1
elapsed = ccall("__w_clock_ms") - started ## i64
<< "OUTER47_ISOTROPY_SUMMARY\tsource=" + source_label + "\tshard=" + shard_id.to_s() + "/" + shard_count.to_s() + "\tchecked=" + checked.to_s() + "\trestarts=" + restarts.to_s() + "\tcandidates=" + candidates.to_s() + "\tdistinct_supports=" + bank.size().to_s() + "\telapsed_ms=" + elapsed.to_s()
