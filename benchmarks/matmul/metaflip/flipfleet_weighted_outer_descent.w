# Weighted whole-outer isotropy search for support-aware block composition.
#
# The exact rank-47 <4,4,4> scheme is treated as an outer algorithm.  For each
# saved block-composition recipe, elementary GL(4,2)^3 transvections are scored
# by `ffbc_score_allocation`; steepest descent changes only the outer basis and
# therefore preserves its rank and exactness.  The manifest scan deliberately
# reports the gain from newly improved leaves separately from the gain due to
# outer isotropy.
#
# Build and run from the repository root:
#   bin/tungsten compile --release --lto -o /tmp/weighted-outer \
#     benchmarks/matmul/metaflip/flipfleet_weighted_outer_descent.w
#   /tmp/weighted-outer scan
#   /tmp/weighted-outer pairscan
#   /tmp/weighted-outer pairscan677
#   /tmp/weighted-outer representative
#   /tmp/weighted-outer target 26x32x32
#   /tmp/weighted-outer restart 26x32x32 16
#   /tmp/weighted-outer custom 21x21x21 5223 5,6,5,5 6,5,5,5 \
#     5,6,5,5 0 8
#
# `scan` performs deterministic steepest descent for every materialized row in
# block_composition_opportunities.tsv.  `pairscan` also scores all 1,296
# ordered transvection pairs at each local minimum, allowing one unfavorable
# intermediate image.  `target` scans one row and materializes a candidate
# whenever its nominal score is no worse than the checked-in exact rank.
# Outputs are written only under /tmp.

use flipfleet_leaf_conjugation
use flipfleet_block_leaf_pool

-> ffwod_fail(message)
  << "WEIGHTED_OUTER_FAIL " + message
  exit(1)
  0

-> ffwod_alloc(text) (String)
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

-> ffwod_dims(text) (String)
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

# Add the three dimension-two leaves required by the exceptional 12x12x14
# recipe.  This is local to the research harness: the shared 3--8 pool remains
# untouched.
-> ffwod_leaf_pool(root) (String)
  leaves = ffbcp_stable_3_to_8(root)
  ffbcp_add(root, "matmul_2x3x3_rank15_catalog_gf2.txt", 2, 3, 3, leaves)
  ffbcp_add(root, "matmul_2x3x4_rank20_catalog_gf2.txt", 2, 3, 4, leaves)
  ffbcp_add(root, "matmul_2x4x4_rank26_catalog_gf2.txt", 2, 4, 4, leaves)
  leaves

-> ffwod_rank_table(leaves) (Array)
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

# Allocation-free scorer equivalent to `ffbc_score_allocation` for this
# fixed 2--8 leaf pool.  Every start and accepted endpoint is cross-checked
# against the authoritative composer scorer; this table form removes a
# 59-leaf orientation scan from every hill-climb neighbor.
-> ffwod_extent4(mask, row_alloc, col_alloc, result) (i64 i64[] i64[] i64[]) i64
  result[0] = 0
  result[1] = 0
  if (mask & 0x000f) != 0
    result[0] = row_alloc[0]
  if (mask & 0x00f0) != 0 && row_alloc[1] > result[0]
    result[0] = row_alloc[1]
  if (mask & 0x0f00) != 0 && row_alloc[2] > result[0]
    result[0] = row_alloc[2]
  if (mask & 0xf000) != 0 && row_alloc[3] > result[0]
    result[0] = row_alloc[3]
  if (mask & 0x1111) != 0
    result[1] = col_alloc[0]
  if (mask & 0x2222) != 0 && col_alloc[1] > result[1]
    result[1] = col_alloc[1]
  if (mask & 0x4444) != 0 && col_alloc[2] > result[1]
    result[1] = col_alloc[2]
  if (mask & 0x8888) != 0 && col_alloc[3] > result[1]
    result[1] = col_alloc[3]
  1

-> ffwod_extent4_code(mask, row_alloc, col_alloc) (i64 i64[] i64[]) i64
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

-> ffwod_score(outer, alloc_n, alloc_m, alloc_p, ranks) (FFBCScheme i64[] i64[] i64[] i64[]) i64
  if outer.n() != 4 || outer.m() != 4 || outer.p() != 4 || outer.uw() != 1 || outer.vw() != 1 || outer.ww() != 1
    return 0 - 1
  total = 0 ## i64
  term = 0 ## i64
  while term < outer.rank()
    ucode = ffwod_extent4_code(outer.us()[term], alloc_n, alloc_m) ## i64
    vcode = ffwod_extent4_code(outer.vs()[term], alloc_m, alloc_p) ## i64
    wcode = ffwod_extent4_code(outer.ws()[term], alloc_n, alloc_p) ## i64
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
      if sn > 8 || sm > 8 || sp > 8
        return 0 - 1
      rank = ranks[(sn * 9 + sm) * 9 + sp] ## i64
      if rank < 1
        return 0 - 1
      total += rank
    term += 1
  total

# Inner-loop form of `fflc_transvection`.  The caller supplies an already
# exact rank-47 outer and this algebraic generator preserves exactness.  The
# accepted endpoint is still independently full-gated below; avoiding two
# complete tensor reconstructions for each of the 36 scored neighbors makes a
# manifest-wide scan practical.
-> ffwod_apply_transvection(source, axis, dst, src) (FFBCScheme i64 i64 i64) i64
  if source == nil || axis < 0 || axis > 2 || dst < 0 || dst >= 4 || src < 0 || src >= 4 || dst == src
    return 0
  t = 0 ## i64
  while t < source.rank()
    if axis == 0
      bits = (source.us()[t] >> (src * 4)) & 0xf ## i64
      source.us()[t] = source.us()[t] ^ (bits << (dst * 4))
      bits = (source.ws()[t] >> (dst * 4)) & 0xf
      source.ws()[t] = source.ws()[t] ^ (bits << (src * 4))
    elsif axis == 1
      bits = source.us()[t] & (0x1111 << src)
      if dst > src
        bits = bits << (dst - src)
      else
        bits = bits >> (src - dst)
      source.us()[t] = source.us()[t] ^ bits
      bits = (source.vs()[t] >> (dst * 4)) & 0xf
      source.vs()[t] = source.vs()[t] ^ (bits << (src * 4))
    else
      bits = source.vs()[t] & (0x1111 << src)
      if dst > src
        bits = bits << (dst - src)
      else
        bits = bits >> (src - dst)
      source.vs()[t] = source.vs()[t] ^ bits
      bits = source.ws()[t] & (0x1111 << dst)
      if src > dst
        bits = bits << (src - dst)
      else
        bits = bits >> (dst - src)
      source.ws()[t] = source.ws()[t] ^ bits
    t += 1
  1

-> ffwod_transvection(source, axis, dst, src) (FFBCScheme i64 i64 i64)
  result = fflc_clone(source)
  if result == nil || ffwod_apply_transvection(result, axis, dst, src) != 1
    return nil
  result

-> ffwod_next(rng) (i64[]) i64
  rng[0] = (rng[0] * 1103515245 + 12345) & 2147483647
  rng[0]

-> ffwod_random_word(source, rng, length) (FFBCScheme i64[] i64)
  current = fflc_clone(source)
  step = 0 ## i64
  while step < length
    axis = ffwod_next(rng) % 3 ## i64
    src = ffwod_next(rng) % 4 ## i64
    dst = ffwod_next(rng) % 3 ## i64
    if dst >= src
      dst += 1
    current = ffwod_transvection(current, axis, dst, src)
    if current == nil
      return nil
    step += 1
  current

# Return [best exact outer image, final score].  `stats` receives starting
# score, final score, accepted generators, and evaluated generators.
-> ffwod_descent(source, alloc_n, alloc_m, alloc_p, leaves, ranks, max_steps, stats) (FFBCScheme i64[] i64[] i64[] Array i64[] i64 i64[])
  current = fflc_clone(source)
  if current == nil
    return nil
  current_score = ffwod_score(current, alloc_n, alloc_m, alloc_p, ranks) ## i64
  if current_score < 1
    return nil
  stats[0] = current_score
  stats[1] = current_score
  stats[2] = 0
  stats[3] = 0
  running = 1 ## i64
  while running == 1 && stats[2] < max_steps
    best_score = current_score ## i64
    best_axis = 0 - 1 ## i64
    best_dst = 0 ## i64
    best_src = 0 ## i64
    axis = 0 ## i64
    while axis < 3
      dst = 0 ## i64
      while dst < 4
        src = 0 ## i64
        while src < 4
          if src != dst
            if ffwod_apply_transvection(current, axis, dst, src) != 1
              ffwod_fail("invalid exact transvection")
            score = ffwod_score(current, alloc_n, alloc_m, alloc_p, ranks) ## i64
            if ffwod_apply_transvection(current, axis, dst, src) != 1
              ffwod_fail("failed transvection inverse")
            stats[3] += 1
            if score > 0 && score < best_score
              best_score = score
              best_axis = axis
              best_dst = dst
              best_src = src
          src += 1
        dst += 1
      axis += 1
    if best_axis < 0
      running = 0
    else
      if ffwod_apply_transvection(current, best_axis, best_dst, best_src) != 1
        ffwod_fail("failed accepted transvection")
      current_score = best_score
      stats[1] = current_score
      stats[2] += 1
  if ffbc_verify_exact(current) != 1
    ffwod_fail("descent endpoint lost exactness")
  if ffbc_score_allocation(current, alloc_n, alloc_m, alloc_p, leaves) != current_score
    ffwod_fail("fast/authoritative endpoint score mismatch")
  [current, current_score]

# Descend to a one-generator minimum, then score every ordered pair of
# transvections as one move.  The intermediate image is deliberately allowed
# to be worse: this is the smallest systematic ridge-crossing neighborhood.
# After accepting a pair, ordinary descent closes the new basin before the
# next pair neighborhood is evaluated.  `stats` receives starting score,
# final score, accepted pairs, and all evaluated generators/pair endpoints.
-> ffwod_pair_descent(source, alloc_n, alloc_m, alloc_p, leaves, ranks, max_pairs, stats) (FFBCScheme i64[] i64[] i64[] Array i64[] i64 i64[])
  direct_stats = i64[4]
  direct = ffwod_descent(source, alloc_n, alloc_m, alloc_p, leaves, ranks, 64, direct_stats)
  if direct == nil
    return nil
  current = direct[0]
  current_score = direct[1] ## i64
  stats[0] = direct_stats[0]
  stats[1] = current_score
  stats[2] = 0
  stats[3] = direct_stats[3]
  running = 1 ## i64
  while running == 1 && stats[2] < max_pairs
    best_score = current_score ## i64
    best_a1 = 0 - 1 ## i64
    best_d1 = 0 ## i64
    best_s1 = 0 ## i64
    best_a2 = 0 ## i64
    best_d2 = 0 ## i64
    best_s2 = 0 ## i64
    a1 = 0 ## i64
    while a1 < 3
      d1 = 0 ## i64
      while d1 < 4
        s1 = 0 ## i64
        while s1 < 4
          if s1 != d1
            if ffwod_apply_transvection(current, a1, d1, s1) != 1
              ffwod_fail("invalid first pair transvection")
            a2 = 0 ## i64
            while a2 < 3
              d2 = 0 ## i64
              while d2 < 4
                s2 = 0 ## i64
                while s2 < 4
                  if s2 != d2
                    if ffwod_apply_transvection(current, a2, d2, s2) != 1
                      ffwod_fail("invalid second pair transvection")
                    score = ffwod_score(current, alloc_n, alloc_m, alloc_p, ranks) ## i64
                    if ffwod_apply_transvection(current, a2, d2, s2) != 1
                      ffwod_fail("failed second pair inverse")
                    stats[3] += 1
                    if score > 0 && score < best_score
                      best_score = score
                      best_a1 = a1
                      best_d1 = d1
                      best_s1 = s1
                      best_a2 = a2
                      best_d2 = d2
                      best_s2 = s2
                  s2 += 1
                d2 += 1
              a2 += 1
            if ffwod_apply_transvection(current, a1, d1, s1) != 1
              ffwod_fail("failed first pair inverse")
          s1 += 1
        d1 += 1
      a1 += 1
    if best_a1 < 0
      running = 0
    else
      if ffwod_apply_transvection(current, best_a1, best_d1, best_s1) != 1 || ffwod_apply_transvection(current, best_a2, best_d2, best_s2) != 1
        ffwod_fail("failed accepted pair")
      close_stats = i64[4]
      closed = ffwod_descent(current, alloc_n, alloc_m, alloc_p, leaves, ranks, 64, close_stats)
      if closed == nil
        ffwod_fail("failed pair close")
      current = closed[0]
      current_score = closed[1]
      stats[1] = current_score
      stats[2] += 1
      stats[3] += close_stats[3]
  if ffbc_verify_exact(current) != 1 || ffbc_score_allocation(current, alloc_n, alloc_m, alloc_p, leaves) != current_score
    ffwod_fail("pair endpoint gate")
  [current, current_score]

# Walk an equal-formula plateau and re-run directed descent after every
# neutral step.  Reservoir sampling avoids retaining 36 temporary images.
-> ffwod_plateau(source, alloc_n, alloc_m, alloc_p, leaves, ranks, steps, rng, stats) (FFBCScheme i64[] i64[] i64[] Array i64[] i64 i64[] i64[])
  current = fflc_clone(source)
  current_score = ffwod_score(current, alloc_n, alloc_m, alloc_p, ranks) ## i64
  best = current
  best_score = current_score ## i64
  step = 0 ## i64
  while step < steps
    equal_count = 0 ## i64
    chosen_axis = 0 - 1 ## i64
    chosen_dst = 0 ## i64
    chosen_src = 0 ## i64
    axis = 0 ## i64
    while axis < 3
      dst = 0 ## i64
      while dst < 4
        src = 0 ## i64
        while src < 4
          if src != dst
            if ffwod_apply_transvection(current, axis, dst, src) != 1
              ffwod_fail("invalid plateau transvection")
            score = ffwod_score(current, alloc_n, alloc_m, alloc_p, ranks) ## i64
            if ffwod_apply_transvection(current, axis, dst, src) != 1
              ffwod_fail("failed plateau inverse")
            stats[3] += 1
            if score == current_score
              equal_count += 1
              if ffwod_next(rng) % equal_count == 0
                chosen_axis = axis
                chosen_dst = dst
                chosen_src = src
          src += 1
        dst += 1
      axis += 1
    if chosen_axis < 0
      step = steps
    else
      chosen = fflc_clone(current)
      if ffwod_apply_transvection(chosen, chosen_axis, chosen_dst, chosen_src) != 1
        ffwod_fail("failed chosen plateau transvection")
      descent_stats = i64[4]
      descended = ffwod_descent(chosen, alloc_n, alloc_m, alloc_p, leaves, ranks, 64, descent_stats)
      stats[3] += descent_stats[3]
      current = descended[0]
      current_score = descended[1]
      if current_score < best_score
        best = current
        best_score = current_score
      step += 1
  if ffbc_verify_exact(best) != 1 || ffbc_score_allocation(best, alloc_n, alloc_m, alloc_p, leaves) != best_score
    ffwod_fail("plateau endpoint gate")
  [best, best_score]

# Deterministic steepest descent followed by reproducible random words and
# equal-score plateau escapes.  `stats`: best formula, starts, total evaluated
# generators, maximum outer term-set distance among tied best minima, and the
# deterministic direct-descent formula and accepted direct generators.
-> ffwod_multistart(source, alloc_n, alloc_m, alloc_p, leaves, ranks, restarts, seed, stats) (FFBCScheme i64[] i64[] i64[] Array i64[] i64 i64 i64[])
  direct_stats = i64[4]
  direct = ffwod_descent(source, alloc_n, alloc_m, alloc_p, leaves, ranks, 64, direct_stats)
  best = direct[0]
  best_score = direct[1] ## i64
  best_distance = fflc_term_set_distance(source, best) ## i64
  stats[2] = direct_stats[3]
  rng = i64[1]
  rng[0] = seed & 2147483647
  r = 0 ## i64
  while r < restarts
    word_length = 4 + (r % 13) ## i64
    random_start = ffwod_random_word(source, rng, word_length)
    run_stats = i64[4]
    local = ffwod_descent(random_start, alloc_n, alloc_m, alloc_p, leaves, ranks, 64, run_stats)
    stats[2] += run_stats[3]
    plateau_stats = i64[4]
    escaped = ffwod_plateau(local[0], alloc_n, alloc_m, alloc_p, leaves, ranks, 8, rng, plateau_stats)
    stats[2] += plateau_stats[3]
    score = escaped[1] ## i64
    distance = fflc_term_set_distance(source, escaped[0]) ## i64
    if score < best_score || (score == best_score && distance > best_distance)
      best = escaped[0]
      best_score = score
      best_distance = distance
    r += 1
  stats[0] = best_score
  stats[1] = restarts + 1
  stats[3] = best_distance
  stats[4] = direct[1]
  stats[5] = direct_stats[2]
  [best, best_score]

-> ffwod_find_row(root, target) (String String)
  body = read_file(root + "block_composition_opportunities.tsv")
  if body == nil
    return nil
  lines = body.split("\n")
  i = 1 ## i64
  while i < lines.size()
    if lines[i].starts_with?(target + "\t")
      return lines[i].split("\t")
    i += 1
  nil

# Bounded coverage set: every saved gain of at least 250 ranks, plus square
# size strata and several high-value mid-range records.  The exhaustive `scan`
# mode remains available, but this set is cheap enough to rerun after every
# leaf or outer improvement.
-> ffwod_representative(fields) (Array) i64
  if fields == nil || fields.size() != 12 || fields[11].to_i() != 1
    return 0
  if fields[4].to_i() >= 250
    return 1
  target = fields[0] ## String
  if target == "13x13x13" || target == "15x15x15" || target == "16x16x16" || target == "17x17x17" || target == "19x19x19"
    return 1
  if target == "13x16x20" || target == "16x17x20" || target == "17x20x20" || target == "19x20x21" || target == "20x20x25" || target == "23x32x32"
    return 1
  0

-> ffwod_random_scan_row(outer, leaves, ranks, fields, restarts) (FFBCScheme Array i64[] Array i64) i64
  if fields == nil || fields.size() != 12 || fields[11].to_i() != 1
    return 0
  target = fields[0] ## String
  alloc_n = ffwod_alloc(fields[6])
  alloc_m = ffwod_alloc(fields[7])
  alloc_p = ffwod_alloc(fields[8])
  dims = ffwod_dims(target)
  if alloc_n == nil || alloc_m == nil || alloc_p == nil || dims == nil
    ffwod_fail("malformed random-scan recipe " + target)
  base_score = ffbc_score_allocation(outer, alloc_n, alloc_m, alloc_p, leaves) ## i64
  seed = dims[0] * 73856093 + dims[1] * 19349663 + dims[2] * 83492791 + restarts * 97 ## i64
  stats = i64[6]
  started = ccall("__w_clock_ms") ## i64
  result = ffwod_multistart(outer, alloc_n, alloc_m, alloc_p, leaves, ranks, restarts, seed, stats)
  elapsed = ccall("__w_clock_ms") - started ## i64
  << "WEIGHTED_OUTER_RANDOM target=" + target + " base=" + base_score.to_s() + " best=" + result[1].to_s() + " gain=" + (base_score - result[1]).to_s() + " restarts=" + restarts.to_s() + " evals=" + stats[2].to_s() + " distance=" + stats[3].to_s() + " elapsed_ms=" + elapsed.to_s()
  1

-> ffwod_scan_row(root, outer, leaves, ranks, fields, materialize) (String FFBCScheme Array i64[] Array i64)
  if fields == nil || fields.size() != 12
    return 0
  target = fields[0] ## String
  if fields[11].to_i() != 1
    return 0
  alloc_n = ffwod_alloc(fields[6])
  alloc_m = ffwod_alloc(fields[7])
  alloc_p = ffwod_alloc(fields[8])
  dims = ffwod_dims(target)
  if alloc_n == nil || alloc_m == nil || alloc_p == nil || dims == nil
    ffwod_fail("malformed recipe " + target)
  saved_formula = fields[1].to_i() ## i64
  saved_exact = fields[2].to_i() ## i64
  code = fields[10].to_i() ## i64
  base_score = ffbc_score_allocation(outer, alloc_n, alloc_m, alloc_p, leaves) ## i64
  if base_score < 1
    ffwod_fail("unsupported recipe " + target)
  stats = i64[4]
  started = ccall("__w_clock_ms") ## i64
  result = ffwod_descent(outer, alloc_n, alloc_m, alloc_p, leaves, ranks, 64, stats)
  elapsed = ccall("__w_clock_ms") - started ## i64
  if result == nil
    ffwod_fail("descent failed " + target)
  best_outer = result[0]
  best_score = result[1] ## i64
  row = "WEIGHTED_OUTER target=" + target
  row = row + " saved_formula=" + saved_formula.to_s() + " saved_exact=" + saved_exact.to_s()
  row = row + " base=" + base_score.to_s() + " best=" + best_score.to_s()
  row = row + " leaf_gain=" + (saved_formula - base_score).to_s()
  row = row + " isotropy_gain=" + (base_score - best_score).to_s()
  row = row + " steps=" + stats[2].to_s() + " evals=" + stats[3].to_s()
  row = row + " elapsed_ms=" + elapsed.to_s()

  if materialize != 0 && best_score <= saved_formula
    composed = ffbc_compose(best_outer, alloc_n, alloc_m, alloc_p, leaves)
    if composed == nil || ffbc_verify_exact(composed) != 1
      ffwod_fail("composition gate " + target)
    candidate = composed
    if code != 0
      candidate = ffbc_orient_scheme(composed, code)
    if candidate == nil || candidate.n() != dims[0] || candidate.m() != dims[1] || candidate.p() != dims[2] || ffbc_verify_exact(candidate) != 1
      ffwod_fail("orientation gate " + target)
    output = "/tmp/matmul_" + target + "_rank" + candidate.rank().to_s() + "_weighted_outer_gf2.txt"
    if ffbc_write(output, candidate) != candidate.rank()
      ffwod_fail("write " + target)
    reloaded = ffbc_load_exact(output, dims[0], dims[1], dims[2], candidate.rank() + 8)
    if reloaded == nil || reloaded.rank() != candidate.rank() || ffbc_verify_exact(reloaded) != 1
      ffwod_fail("serialize/reparse " + target)
    row = row + " exact=" + candidate.rank().to_s() + " output=" + output
  << row
  1

-> ffwod_pair_scan_row(root, outer, leaves, ranks, fields) (String FFBCScheme Array i64[] Array i64)
  if fields == nil || fields.size() != 12 || fields[11].to_i() != 1
    return 0
  target = fields[0] ## String
  alloc_n = ffwod_alloc(fields[6])
  alloc_m = ffwod_alloc(fields[7])
  alloc_p = ffwod_alloc(fields[8])
  dims = ffwod_dims(target)
  if alloc_n == nil || alloc_m == nil || alloc_p == nil || dims == nil
    ffwod_fail("malformed pair recipe " + target)
  saved_formula = fields[1].to_i() ## i64
  saved_exact = fields[2].to_i() ## i64
  code = fields[10].to_i() ## i64
  base_score = ffbc_score_allocation(outer, alloc_n, alloc_m, alloc_p, leaves) ## i64
  stats = i64[4]
  started = ccall("__w_clock_ms") ## i64
  result = ffwod_pair_descent(outer, alloc_n, alloc_m, alloc_p, leaves, ranks, 16, stats)
  elapsed = ccall("__w_clock_ms") - started ## i64
  if result == nil
    ffwod_fail("pair descent failed " + target)
  best_outer = result[0]
  best_score = result[1] ## i64
  distance = fflc_term_set_distance(outer, best_outer) ## i64
  row = "WEIGHTED_OUTER_PAIR target=" + target + " saved_formula=" + saved_formula.to_s() + " saved_exact=" + saved_exact.to_s()
  row = row + " base=" + base_score.to_s() + " best=" + best_score.to_s()
  row = row + " pairs=" + stats[2].to_s() + " evals=" + stats[3].to_s() + " distance=" + distance.to_s() + " elapsed_ms=" + elapsed.to_s()

  # A strict formula win is always promising.  A changed outer tying the saved
  # formula is also materialized because mapped-zero and parity reduction are
  # visible only after embedding the leaves.
  if best_score < saved_formula || (best_score == saved_formula && distance > 0)
    composed = ffbc_compose(best_outer, alloc_n, alloc_m, alloc_p, leaves)
    if composed == nil || ffbc_verify_exact(composed) != 1
      ffwod_fail("pair composition gate " + target)
    candidate = composed
    if code != 0
      candidate = ffbc_orient_scheme(composed, code)
    if candidate == nil || candidate.n() != dims[0] || candidate.m() != dims[1] || candidate.p() != dims[2] || ffbc_verify_exact(candidate) != 1
      ffwod_fail("pair orientation gate " + target)
    row = row + " exact=" + candidate.rank().to_s() + " zero=" + candidate.compose_zero_terms().to_s() + " parity=" + candidate.compose_parity_reduction().to_s()
    if candidate.rank() < saved_exact
      output = "/tmp/matmul_" + target + "_rank" + candidate.rank().to_s() + "_weighted_outer_pair_gf2.txt"
      if ffbc_write(output, candidate) != candidate.rank()
        ffwod_fail("pair write " + target)
      reloaded = ffbc_load_exact(output, dims[0], dims[1], dims[2], candidate.rank() + 8)
      if reloaded == nil || reloaded.rank() != candidate.rank() || ffbc_verify_exact(reloaded) != 1
        ffwod_fail("pair serialize/reparse " + target)
      row = row + " strict=1 output=" + output
  << row
  1

-> ffwod_custom_restart(outer, leaves, ranks, target, saved_exact, alloc_n, alloc_m, alloc_p, code, restart_count) (FFBCScheme Array i64[] String i64 i64[] i64[] i64[] i64 i64) i64
  dims = ffwod_dims(target)
  if dims == nil || alloc_n == nil || alloc_m == nil || alloc_p == nil || code < 0 || code > 5 || restart_count < 0 || restart_count > 128
    ffwod_fail("invalid custom target")
  base_score = ffbc_score_allocation(outer, alloc_n, alloc_m, alloc_p, leaves) ## i64
  if base_score < 1
    ffwod_fail("unsupported custom allocation " + target)
  seed = dims[0] * 73856093 + dims[1] * 19349663 + dims[2] * 83492791 + restart_count * 97 ## i64
  restart_stats = i64[6]
  started = ccall("__w_clock_ms") ## i64
  result = ffwod_multistart(outer, alloc_n, alloc_m, alloc_p, leaves, ranks, restart_count, seed, restart_stats)
  elapsed = ccall("__w_clock_ms") - started ## i64
  best_outer = result[0]
  best_score = result[1] ## i64
  outer_output = "/tmp/matmul_4x4_rank47_weighted_" + target + "_f" + best_score.to_s() + "_gf2.txt"
  if ffbc_write(outer_output, best_outer) != 47
    ffwod_fail("write custom outer " + target)
  outer_reloaded = ffbc_load_exact(outer_output, 4, 4, 4, 128)
  if outer_reloaded == nil || outer_reloaded.rank() != 47 || ffbc_verify_exact(outer_reloaded) != 1
    ffwod_fail("reparse custom outer " + target)
  row = "WEIGHTED_OUTER_CUSTOM target=" + target + " baseline=" + saved_exact.to_s()
  row = row + " base=" + base_score.to_s() + " direct=" + restart_stats[4].to_s() + " best=" + best_score.to_s()
  row = row + " direct_steps=" + restart_stats[5].to_s() + " restarts=" + restart_count.to_s() + " evals=" + restart_stats[2].to_s()
  row = row + " outer_distance=" + restart_stats[3].to_s() + " elapsed_ms=" + elapsed.to_s() + " outer=" + outer_output
  if best_score <= saved_exact
    composed = ffbc_compose(best_outer, alloc_n, alloc_m, alloc_p, leaves)
    if composed == nil || ffbc_verify_exact(composed) != 1
      ffwod_fail("custom composition gate " + target)
    candidate = composed
    if code != 0
      candidate = ffbc_orient_scheme(composed, code)
    if candidate == nil || candidate.n() != dims[0] || candidate.m() != dims[1] || candidate.p() != dims[2] || ffbc_verify_exact(candidate) != 1
      ffwod_fail("custom orientation gate " + target)
    output = "/tmp/matmul_" + target + "_rank" + candidate.rank().to_s() + "_weighted_outer_custom_gf2.txt"
    if ffbc_write(output, candidate) != candidate.rank()
      ffwod_fail("custom write " + target)
    reloaded = ffbc_load_exact(output, dims[0], dims[1], dims[2], candidate.rank() + 8)
    if reloaded == nil || reloaded.rank() != candidate.rank() || ffbc_verify_exact(reloaded) != 1
      ffwod_fail("custom serialize/reparse " + target)
    row = row + " exact=" + candidate.rank().to_s() + " zero=" + candidate.compose_zero_terms().to_s() + " parity=" + candidate.compose_parity_reduction().to_s() + " output=" + output
  << row
  1

av = argv()
if av.size() < 1 || av.size() > 9 || (av[0] != "scan" && av[0] != "scan677" && av[0] != "pairscan" && av[0] != "pairscan677" && av[0] != "representative" && av[0] != "randomscan" && av[0] != "randomscan677" && av[0] != "squares" && av[0] != "target" && av[0] != "restart" && av[0] != "custom" && av[0] != "selftest")
  << "usage: weighted-outer <scan|scan677|pairscan|pairscan677|representative|randomscan|randomscan677|squares|target|restart|custom|selftest> ..."
  exit(1)
if av[0] == "target" && av.size() != 2
  << "target mode requires NxMxP"
  exit(1)
if av[0] == "restart" && av.size() != 3
  << "restart mode requires NxMxP and a restart count"
  exit(1)
if (av[0] == "randomscan" || av[0] == "randomscan677") && av.size() != 2
  << "randomscan mode requires a restart count"
  exit(1)
if av[0] == "squares" && av.size() != 2
  << "squares mode requires a restart count"
  exit(1)
if av[0] == "custom" && av.size() != 8
  << "custom mode requires target baseline alloc_n alloc_m alloc_p s3_code restarts"
  exit(1)

root = "benchmarks/matmul/metaflip/"
program_started = ccall("__w_clock_ms") ## i64
outer_path = "matmul_4x4_rank47_d450_gf2.txt"
if av[0] == "scan677" || av[0] == "pairscan677" || av[0] == "randomscan677"
  outer_path = "matmul_4x4_rank47_d677_flips_gf2.txt"
outer = ffbc_load_exact(root + outer_path, 4, 4, 4, 128)
if outer == nil || outer.rank() != 47
  ffwod_fail("rank-47 outer")
leaves = ffwod_leaf_pool(root)
ranks = ffwod_rank_table(leaves)

checked = 0 ## i64
if av[0] == "squares"
  square_restarts = av[1].to_i() ## i64
  if square_restarts < 0 || square_restarts > 128
    ffwod_fail("squares restart count must be 0..128")
  q = 12 ## i64
  while q <= 32
    recipe = ffbc_best_balanced_recipe(outer, q, q, q, leaves)
    if recipe == nil
      ffwod_fail("unsupported square " + q.to_s())
    seed = q * 73856093 + q * 19349663 + q * 83492791 + square_restarts * 97 ## i64
    stats = i64[6]
    result = ffwod_multistart(outer, recipe[0], recipe[1], recipe[2], leaves, ranks, square_restarts, seed, stats)
    row = "WEIGHTED_OUTER_SQUARE target=" + q.to_s() + "x" + q.to_s() + "x" + q.to_s()
    row = row + " base=" + recipe[3].to_s() + " best=" + result[1].to_s() + " gain=" + (recipe[3] - result[1]).to_s()
    row = row + " alloc=" + recipe[0].join(",") + "|" + recipe[1].join(",") + "|" + recipe[2].join(",")
    row = row + " restarts=" + square_restarts.to_s() + " evals=" + stats[2].to_s() + " distance=" + stats[3].to_s()
    if result[1] < recipe[3]
      candidate = ffbc_compose(result[0], recipe[0], recipe[1], recipe[2], leaves)
      if candidate == nil || candidate.rank() > result[1] || ffbc_verify_exact(candidate) != 1
        ffwod_fail("square composition gate " + q.to_s())
      output = "/tmp/matmul_" + q.to_s() + "x" + q.to_s() + "x" + q.to_s() + "_rank" + candidate.rank().to_s() + "_weighted_outer_gf2.txt"
      if ffbc_write(output, candidate) != candidate.rank()
        ffwod_fail("square write " + q.to_s())
      reloaded = ffbc_load_exact(output, q, q, q, candidate.rank() + 8)
      if reloaded == nil || reloaded.rank() != candidate.rank() || ffbc_verify_exact(reloaded) != 1
        ffwod_fail("square serialize/reparse " + q.to_s())
      row = row + " exact=" + candidate.rank().to_s() + " output=" + output
    << row
    checked += 1
    q += 1
elsif av[0] == "randomscan" || av[0] == "randomscan677"
  random_restarts = av[1].to_i() ## i64
  if random_restarts < 1 || random_restarts > 128
    ffwod_fail("randomscan restart count must be 1..128")
  body = read_file(root + "block_composition_opportunities.tsv")
  if body == nil
    ffwod_fail("missing opportunity manifest")
  lines = body.split("\n")
  i = 1 ## i64
  while i < lines.size()
    if lines[i].size() > 0
      checked += ffwod_random_scan_row(outer, leaves, ranks, lines[i].split("\t"), random_restarts)
    i += 1
elsif av[0] == "selftest"
  if av.size() != 1
    ffwod_fail("selftest takes no arguments")
  axis = 0 ## i64
  while axis < 3
    dst = 0 ## i64
    while dst < 4
      src = 0 ## i64
      while src < 4
        if src != dst
          fast = ffwod_transvection(outer, axis, dst, src)
          authoritative = fflc_transvection(outer, axis, dst, src)
          if fast == nil || authoritative == nil || ffbc_verify_exact(fast) != 1 || fflc_equal(fast, authoritative) != 1
            ffwod_fail("bitwise transvection mismatch")
        src += 1
      dst += 1
    axis += 1
  allocations_n = ffwod_alloc("5,6,5,5")
  allocations_m = ffwod_alloc("6,5,5,5")
  allocations_p = ffwod_alloc("5,6,5,5")
  rng = i64[1]
  rng[0] = 470021
  image = fflc_clone(outer)
  i = 0 ## i64
  while i < 32
    image = ffwod_random_word(image, rng, 1)
    fast_score = ffwod_score(image, allocations_n, allocations_m, allocations_p, ranks) ## i64
    authoritative_score = ffbc_score_allocation(image, allocations_n, allocations_m, allocations_p, leaves) ## i64
    if fast_score != authoritative_score || ffbc_verify_exact(image) != 1
      ffwod_fail("fast score mismatch at image " + i.to_s())
    i += 1
  termination_stats = i64[4]
  termination = ffwod_descent(outer, allocations_n, allocations_m, allocations_p, leaves, ranks, 64, termination_stats)
  if termination == nil || termination[1] != 5223 || termination_stats[2] != 0 || termination_stats[3] != 36
    ffwod_fail("direct-descent loop regression")
  << "PASS weighted outer selftest transvections=36 scores=32 local_minimum_evals=36"
  checked = 1
elsif av[0] == "custom"
  checked = ffwod_custom_restart(outer, leaves, ranks, av[1], av[2].to_i(), ffwod_alloc(av[3]), ffwod_alloc(av[4]), ffwod_alloc(av[5]), av[6].to_i(), av[7].to_i())
elsif av[0] == "restart"
  restart_count = av[2].to_i() ## i64
  if restart_count < 1 || restart_count > 128
    ffwod_fail("restart count must be 1..128")
  fields = ffwod_find_row(root, av[1])
  if fields == nil || fields.size() != 12 || fields[11].to_i() != 1
    ffwod_fail("unknown materialized target " + av[1])
  target = fields[0] ## String
  alloc_n = ffwod_alloc(fields[6])
  alloc_m = ffwod_alloc(fields[7])
  alloc_p = ffwod_alloc(fields[8])
  dims = ffwod_dims(target)
  code = fields[10].to_i() ## i64
  saved_formula = fields[1].to_i() ## i64
  saved_exact = fields[2].to_i() ## i64
  base_score = ffbc_score_allocation(outer, alloc_n, alloc_m, alloc_p, leaves) ## i64
  seed = dims[0] * 73856093 + dims[1] * 19349663 + dims[2] * 83492791 + restart_count * 97 ## i64
  restart_stats = i64[6]
  started = ccall("__w_clock_ms") ## i64
  result = ffwod_multistart(outer, alloc_n, alloc_m, alloc_p, leaves, ranks, restart_count, seed, restart_stats)
  elapsed = ccall("__w_clock_ms") - started ## i64
  best_outer = result[0]
  best_score = result[1] ## i64
  outer_output = "/tmp/matmul_4x4_rank47_weighted_" + target + "_f" + best_score.to_s() + "_gf2.txt"
  if ffbc_write(outer_output, best_outer) != 47
    ffwod_fail("write restart outer " + target)
  outer_reloaded = ffbc_load_exact(outer_output, 4, 4, 4, 128)
  if outer_reloaded == nil || outer_reloaded.rank() != 47 || ffbc_verify_exact(outer_reloaded) != 1
    ffwod_fail("reparse restart outer " + target)
  row = "WEIGHTED_OUTER_RESTART target=" + target + " saved_formula=" + saved_formula.to_s() + " saved_exact=" + saved_exact.to_s()
  row = row + " base=" + base_score.to_s() + " direct=" + restart_stats[4].to_s() + " best=" + best_score.to_s()
  row = row + " direct_steps=" + restart_stats[5].to_s() + " restarts=" + restart_count.to_s() + " evals=" + restart_stats[2].to_s()
  row = row + " outer_distance=" + restart_stats[3].to_s() + " elapsed_ms=" + elapsed.to_s() + " outer=" + outer_output
  if best_score <= saved_formula
    composed = ffbc_compose(best_outer, alloc_n, alloc_m, alloc_p, leaves)
    if composed == nil || ffbc_verify_exact(composed) != 1
      ffwod_fail("restart composition gate " + target)
    candidate = composed
    if code != 0
      candidate = ffbc_orient_scheme(composed, code)
    if candidate == nil || candidate.n() != dims[0] || candidate.m() != dims[1] || candidate.p() != dims[2] || ffbc_verify_exact(candidate) != 1
      ffwod_fail("restart orientation gate " + target)
    output = "/tmp/matmul_" + target + "_rank" + candidate.rank().to_s() + "_weighted_outer_restart_gf2.txt"
    if ffbc_write(output, candidate) != candidate.rank()
      ffwod_fail("restart write " + target)
    reloaded = ffbc_load_exact(output, dims[0], dims[1], dims[2], candidate.rank() + 8)
    if reloaded == nil || reloaded.rank() != candidate.rank() || ffbc_verify_exact(reloaded) != 1
      ffwod_fail("restart serialize/reparse " + target)
    row = row + " exact=" + candidate.rank().to_s() + " output=" + output
  << row
  checked = 1
elsif av[0] == "target"
  fields = ffwod_find_row(root, av[1])
  if fields == nil
    ffwod_fail("unknown target " + av[1])
  checked += ffwod_scan_row(root, outer, leaves, ranks, fields, 1)
elsif av[0] == "pairscan" || av[0] == "pairscan677"
  body = read_file(root + "block_composition_opportunities.tsv")
  if body == nil
    ffwod_fail("missing opportunity manifest")
  lines = body.split("\n")
  i = 1 ## i64
  while i < lines.size()
    if lines[i].size() > 0
      checked += ffwod_pair_scan_row(root, outer, leaves, ranks, lines[i].split("\t"))
    i += 1
else
  body = read_file(root + "block_composition_opportunities.tsv")
  if body == nil
    ffwod_fail("missing opportunity manifest")
  lines = body.split("\n")
  i = 1 ## i64
  while i < lines.size()
    if lines[i].size() > 0
      fields = lines[i].split("\t")
      if av[0] == "scan" || av[0] == "scan677" || ffwod_representative(fields) == 1
        checked += ffwod_scan_row(root, outer, leaves, ranks, fields, 0)
    i += 1

<< "WEIGHTED_OUTER_SUMMARY checked=" + checked.to_s() + " elapsed_ms=" + (ccall("__w_clock_ms") - program_started).to_s()
