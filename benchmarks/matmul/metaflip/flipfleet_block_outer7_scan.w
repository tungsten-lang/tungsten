use flipfleet_block_leaf_pool

# Bounded research audit for using the exact rank-247 7x7x7 scheme as a
# seven-block support-aware outer.  Formula search is specialized for seven
# balanced parts: every outer factor is reduced once to row/column support
# masks and every induced leaf rank is a constant-time lookup.  The lookup is
# the audited GF(2) table through size five (the only sizes balanced targets
# 7..32 can induce).  The fully repository-certificate-backed range is 21..32,
# where every block has size 3..5 inside the complete exact 3..8 leaf pool.

-> ffbo7_sort3(a, b, c, sorted) (i64 i64 i64 i64[]) i64
  sorted[0] = a
  sorted[1] = b
  sorted[2] = c
  if sorted[0] > sorted[1]
    t = sorted[0] ## i64
    sorted[0] = sorted[1]
    sorted[1] = t
  if sorted[1] > sorted[2]
    t = sorted[1]
    sorted[1] = sorted[2]
    sorted[2] = t
  if sorted[0] > sorted[1]
    t = sorted[0]
    sorted[0] = sorted[1]
    sorted[1] = t
  1

# Ranks of exact GF(2) bilinear schemes used by the prior alternate-block
# audit.  A
# dimension-one tensor has rank a*b by its flattening bound.  All remaining
# sorted shapes through five have explicit exact schemes in the pinned source
# catalogues; the subset with minimum dimension at least three is checked into
# this repository and independently gated on every materialisation.
-> ffbo7_leaf_rank(a, b, c) (i64 i64 i64) i64
  d = i64[3]
  ffbo7_sort3(a, b, c, d)
  if d[0] < 1 || d[2] > 5
    return 0 - 1
  if d[0] == 1
    return d[1] * d[2]
  if d[0] == 2
    if d[1] == 2
      if d[2] == 2
        return 7
      if d[2] == 3
        return 11
      if d[2] == 4
        return 14
      if d[2] == 5
        return 18
    elsif d[1] == 3
      if d[2] == 3
        return 15
      if d[2] == 4
        return 20
      if d[2] == 5
        return 25
    elsif d[1] == 4
      if d[2] == 4
        return 26
      if d[2] == 5
        return 33
    elsif d[1] == 5 && d[2] == 5
      return 40
    return 0 - 1
  if d[0] == 3
    if d[1] == 3
      if d[2] == 3
        return 23
      if d[2] == 4
        return 29
      if d[2] == 5
        return 36
    elsif d[1] == 4
      if d[2] == 4
        return 38
      if d[2] == 5
        return 47
    elsif d[1] == 5 && d[2] == 5
      return 58
    return 0 - 1
  if d[0] == 4
    if d[1] == 4
      if d[2] == 4
        return 47
      if d[2] == 5
        return 60
    elsif d[1] == 5 && d[2] == 5
      return 76
    return 0 - 1
  if d[0] == 5 && d[1] == 5 && d[2] == 5
    return 93
  0 - 1

# Pinned explicit-F2 ranks for sorted <2,a,b> through block size eight.  These
# are the verified entries at matmulcatalog revision 0320f745; they complete
# the repository's exact 3--8 pool for rank-only formula comparison.
-> ffbo7_rank2(a, b) (i64 i64) i64
  if a < 2 || a > b || b > 8
    return 0 - 1
  if a == 2
    return (7 * b + 1) / 2
  if a == 3
    return 5 * b
  if a == 4
    if b == 4
      return 26
    return 6 * b + 3
  if a == 5
    if b == 5
      return 40
    if b == 6
      return 47
    if b == 7
      return 55
    if b == 8
      return 63
  if a == 6
    if b == 6
      return 56
    if b == 7
      return 66
    if b == 8
      return 75
  if a == 7
    if b == 7
      return 76
    if b == 8
      return 88
  if a == 8 && b == 8
    return 100
  0 - 1

# Rank-only schemes are never passed to the materializer.  Dimension-one
# ranks are exact by flattening; dimension-two ranks come from the pinned
# table above; all remaining entries are repository-gated exact schemes.
-> ffbo7_comparison_formula_leaves(stable)
  leaves = []
  n = 1 ## i64
  while n <= 2
    m = n ## i64
    while m <= 8
      p = m ## i64
      while p <= 8
        rank = m * p ## i64
        if n == 2
          rank = ffbo7_rank2(m, p)
        if rank < 1
          return nil
        leaf = FFBCScheme.new(n, m, p, 1)
        leaf.set_rank(rank)
        leaves.push(leaf)
        p += 1
      m += 1
    n += 1
  i = 0 ## i64
  while i < stable.size()
    leaves.push(stable[i])
    i += 1
  leaves

# Exact GF(2) upper bounds for <7,7,k>, k<=16, followed by complete
# column-block direct-sum closure through 32.  Entries 2..16 are the pinned
# explicit-F2 catalogue schemes (3..8 are also checked into this repository);
# k=1 is naive and k=7 uses the rank-247 outer under audit.
-> ffbo7_seven_square_direct_sum(k) (i64) i64
  if k < 1 || k > 32
    return 0 - 1
  ranks = i64[33]
  i = 0 ## i64
  while i < ranks.size()
    ranks[i] = 0x7fffffff
    i += 1
  ranks[1] = 49
  ranks[2] = 76
  ranks[3] = 111
  ranks[4] = 144
  ranks[5] = 176
  ranks[6] = 212
  ranks[7] = 247
  ranks[8] = 278
  ranks[9] = 316
  ranks[10] = 346
  ranks[11] = 378
  ranks[12] = 404
  ranks[13] = 443
  ranks[14] = 475
  ranks[15] = 511
  ranks[16] = 540
  width = 2 ## i64
  while width <= 32
    split = 1 ## i64
    while split < width
      if ranks[split] < 0x7fffffff && ranks[width - split] < 0x7fffffff
        score = ranks[split] + ranks[width - split] ## i64
        if score < ranks[width]
          ranks[width] = score
      split += 1
    width += 1
  ranks[k]

-> ffbo7_comparison_rank(outer4, leaves, n, m, p) (FFBCScheme Array i64 i64 i64) i64
  recipe = ffbc_best_oriented_balanced_recipe(outer4, n, m, p, leaves)
  if recipe == nil
    return 0 - 1
  result = recipe[3] ## i64
  if n == 7 && m == 7
    direct_sum = ffbo7_seven_square_direct_sum(p) ## i64
    if direct_sum > 0 && direct_sum < result
      result = direct_sum
  result

# For every term, masks are U-row, U-column, V-row, V-column, W-row,
# W-column.  Exact schemes cannot contain a zero factor, so all six masks are
# nonzero after loading.
-> ffbo7_support_masks(outer) (FFBCScheme)
  masks = i64[outer.rank() * 6]
  term = 0 ## i64
  while term < outer.rank()
    axis = 0 ## i64
    while axis < 3
      data = outer.us()
      words = outer.uw() ## i64
      if axis == 1
        data = outer.vs()
        words = outer.vw()
      elsif axis == 2
        data = outer.ws()
        words = outer.ww()
      bit = 0 ## i64
      while bit < 49
        if ffbc_bit(data, term * words, bit) == 1
          row = bit / 7 ## i64
          col = bit % 7 ## i64
          masks[term * 6 + axis * 2] = masks[term * 6 + axis * 2] | (1 << row)
          masks[term * 6 + axis * 2 + 1] = masks[term * 6 + axis * 2 + 1] | (1 << col)
        bit += 1
      axis += 1
    term += 1
  masks

-> ffbo7_extra_masks(total) (i64)
  result = []
  extra = total % 7 ## i64
  mask = 0 ## i64
  while mask < 128
    if ffbc_popcount_small(mask) == extra
      result.push(mask)
    mask += 1
  result

-> ffbo7_extent(base, extra_mask, support_mask) (i64 i64 i64) i64
  if (extra_mask & support_mask) != 0
    return base + 1
  base

-> ffbo7_score_masks(outer, supports, bn, bm, bp, en, em, ep) (FFBCScheme i64[] i64 i64 i64 i64 i64 i64) i64
  total = 0 ## i64
  term = 0 ## i64
  while term < outer.rank()
    base = term * 6 ## i64
    sn = ffbo7_extent(bn, en, supports[base]) ## i64
    other = ffbo7_extent(bn, en, supports[base + 4]) ## i64
    if other < sn
      sn = other
    sm = ffbo7_extent(bm, em, supports[base + 1]) ## i64
    other = ffbo7_extent(bm, em, supports[base + 2])
    if other < sm
      sm = other
    sp = ffbo7_extent(bp, ep, supports[base + 3]) ## i64
    other = ffbo7_extent(bp, ep, supports[base + 5])
    if other < sp
      sp = other
    rank = ffbo7_leaf_rank(sn, sm, sp) ## i64
    if rank < 1
      return 0 - 1
    total += rank
    term += 1
  total

-> ffbo7_extent_allocation(allocation, support_mask) (i64[] i64) i64
  result = 0 ## i64
  i = 0 ## i64
  while i < 7
    if ((support_mask >> i) & 1) == 1 && allocation[i] > result
      result = allocation[i]
    i += 1
  result

-> ffbo7_score_allocation(outer, supports, an, am, ap) (FFBCScheme i64[] i64[] i64[] i64[]) i64
  total = 0 ## i64
  term = 0 ## i64
  while term < outer.rank()
    base = term * 6 ## i64
    sn = ffbo7_extent_allocation(an, supports[base]) ## i64
    other = ffbo7_extent_allocation(an, supports[base + 4]) ## i64
    if other < sn
      sn = other
    sm = ffbo7_extent_allocation(am, supports[base + 1]) ## i64
    other = ffbo7_extent_allocation(am, supports[base + 2])
    if other < sm
      sm = other
    sp = ffbo7_extent_allocation(ap, supports[base + 3]) ## i64
    other = ffbo7_extent_allocation(ap, supports[base + 5])
    if other < sp
      sp = other
    rank = ffbo7_leaf_rank(sn, sm, sp) ## i64
    if rank < 1
      return 0 - 1
    total += rank
    term += 1
  total

-> ffbo7_copy_allocation(source) (i64[])
  result = i64[7]
  i = 0 ## i64
  while i < 7
    result[i] = source[i]
    i += 1
  result

# Coordinate descent in the radius-one transfer graph around the best
# balanced placement.  `passes=2` examines at most two accepted unit transfers
# on each axis, a deliberately small unbalanced neighborhood rather than an
# unbounded allocation search.
-> ffbo7_neighborhood(outer, supports, recipe, passes) (FFBCScheme i64[] Array i64)
  an = ffbo7_copy_allocation(recipe[0])
  am = ffbo7_copy_allocation(recipe[1])
  ap = ffbo7_copy_allocation(recipe[2])
  best = ffbo7_score_allocation(outer, supports, an, am, ap) ## i64
  pass = 0 ## i64
  evaluated = 0 ## i64
  while pass < passes
    axis = 0 ## i64
    while axis < 3
      current = an
      if axis == 1
        current = am
      elsif axis == 2
        current = ap
      best_axis = best ## i64
      best_src = 0 - 1 ## i64
      best_dst = 0 - 1 ## i64
      src = 0 ## i64
      while src < 7
        dst = 0 ## i64
        while dst < 7
          if src != dst && current[src] > 1 && current[dst] < 5
            current[src] -= 1
            current[dst] += 1
            score = ffbo7_score_allocation(outer, supports, an, am, ap) ## i64
            evaluated += 1
            current[dst] -= 1
            current[src] += 1
            if score > 0 && score < best_axis
              best_axis = score
              best_src = src
              best_dst = dst
          dst += 1
        src += 1
      if best_src >= 0
        current[best_src] -= 1
        current[best_dst] += 1
        best = best_axis
      axis += 1
    pass += 1
  [an, am, ap, best, evaluated]

-> ffbo7_allocation(total, extra_mask) (i64 i64)
  result = i64[7]
  base = total / 7 ## i64
  i = 0 ## i64
  while i < 7
    result[i] = base + ((extra_mask >> i) & 1)
    i += 1
  result

-> ffbo7_best_recipe(outer, supports, target_n, target_m, target_p) (FFBCScheme i64[] i64 i64 i64)
  ens = ffbo7_extra_masks(target_n)
  ems = ffbo7_extra_masks(target_m)
  eps = ffbo7_extra_masks(target_p)
  bn = target_n / 7 ## i64
  bm = target_m / 7 ## i64
  bp = target_p / 7 ## i64
  best = 0x7fffffff ## i64
  best_en = 0 ## i64
  best_em = 0 ## i64
  best_ep = 0 ## i64
  ni = 0 ## i64
  while ni < ens.size()
    mi = 0 ## i64
    while mi < ems.size()
      pi = 0 ## i64
      while pi < eps.size()
        score = ffbo7_score_masks(outer, supports, bn, bm, bp, ens[ni], ems[mi], eps[pi]) ## i64
        if score > 0 && score < best
          best = score
          best_en = ens[ni]
          best_em = ems[mi]
          best_ep = eps[pi]
        pi += 1
      mi += 1
    ni += 1
  if best == 0x7fffffff
    return nil
  [ffbo7_allocation(target_n, best_en), ffbo7_allocation(target_m, best_em), ffbo7_allocation(target_p, best_ep), best]

-> ffbo7_best_oriented_recipe(outer, supports, target_n, target_m, target_p) (FFBCScheme i64[] i64 i64 i64 i64)
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
  dims = i64[3]
  best = nil
  best_score = 0x7fffffff ## i64
  ci = 0 ## i64
  while ci < 6
    code = codes[ci] ## i64
    ffbc_source_dims_for_orientation(code, target_n, target_m, target_p, dims)
    duplicate = 0 ## i64
    si = 0 ## i64
    while si < seen_count
      if seen_n[si] == dims[0] && seen_m[si] == dims[1] && seen_p[si] == dims[2]
        duplicate = 1
      si += 1
    if duplicate == 0
      seen_n[seen_count] = dims[0]
      seen_m[seen_count] = dims[1]
      seen_p[seen_count] = dims[2]
      seen_count += 1
      recipe = ffbo7_best_recipe(outer, supports, dims[0], dims[1], dims[2])
      if recipe != nil && recipe[3] < best_score
        best_score = recipe[3]
        best = [recipe[0], recipe[1], recipe[2], recipe[3], dims[0], dims[1], dims[2], code]
    ci += 1
  best

-> ffbo7_parse_target(text, dims) (String i64[]) i64
  fields = text.split("x")
  if fields.size() != 3
    return 0
  i = 0 ## i64
  while i < 3
    value = fields[i].to_i() ## i64
    if value < 7 || value > 32
      return 0
    dims[i] = value
    i += 1
  1

av = argv()
if av.size() < 1 || av.size() > 3
  << "usage: outer7-scan <bands|multiples|records|target|neighbor|selftest> [NxMxP] [exact|passes]"
  exit(1)
mode = av[0]
if mode != "bands" && mode != "multiples" && mode != "records" && mode != "target" && mode != "neighbor" && mode != "selftest"
  << "mode must be bands, multiples, records, target, neighbor, or selftest"
  exit(1)

root = "benchmarks/matmul/metaflip/"
outer = ffbc_load_exact(root + "matmul_7x7_rank247_d3554_outer_isotropy_gf2.txt", 7, 7, 7, 320)
if outer == nil || outer.rank() != 247
  << "invalid rank-247 outer"
  exit(1)
outer4 = ffbc_load_exact(root + "matmul_4x4_rank47_d450_gf2.txt", 4, 4, 4, 64)
if outer4 == nil || outer4.rank() != 47
  << "invalid rank-47 comparison outer"
  exit(1)
leaves = ffbcp_stable_3_to_8(root)
if leaves.size() != 56
  << "incomplete stable 3--8 leaf pool"
  exit(1)
comparison_leaves = ffbo7_comparison_formula_leaves(leaves)
if comparison_leaves == nil || comparison_leaves.size() != 120
  << "incomplete exact-rank 1--8 comparison table"
  exit(1)

supports = ffbo7_support_masks(outer)

if mode == "selftest"
  if ffbo7_rank2(2, 8) != 28 || ffbo7_rank2(4, 7) != 45 || ffbo7_rank2(6, 8) != 75 || ffbo7_rank2(8, 8) != 100
    << "OUTER7_SELFTEST_FAIL pinned dimension-two table"
    exit(1)
  li = 0 ## i64
  while li < leaves.size()
    leaf = leaves[li]
    if leaf.n() <= 5 && leaf.m() <= 5 && leaf.p() <= 5
      if ffbo7_leaf_rank(leaf.n(), leaf.m(), leaf.p()) != leaf.rank()
        << "OUTER7_SELFTEST_FAIL leaf rank table"
        exit(1)
    li += 1
  a21 = i64[7]
  i = 0 ## i64
  while i < 7
    a21[i] = 3
    i += 1
  fast21 = ffbo7_score_allocation(outer, supports, a21, a21, a21) ## i64
  authoritative21 = ffbc_score_allocation(outer, a21, a21, a21, leaves) ## i64
  best21 = ffbo7_best_oriented_recipe(outer, supports, 21, 21, 21)
  comparison21 = ffbo7_comparison_rank(outer4, comparison_leaves, 21, 21, 21) ## i64
  if fast21 != 5681 || authoritative21 != fast21 || best21 == nil || best21[3] != fast21 || comparison21 != 5223
    << "OUTER7_SELFTEST_FAIL 21x21x21"
    exit(1)
  best24 = ffbo7_best_oriented_recipe(outer, supports, 24, 24, 24)
  if best24 == nil || best24[3] != 8471 || ffbc_score_allocation(outer, best24[0], best24[1], best24[2], leaves) != 8471
    << "OUTER7_SELFTEST_FAIL 24x24x24"
    exit(1)
  comparison7 = ffbo7_comparison_rank(outer4, comparison_leaves, 7, 7, 7) ## i64
  if comparison7 != 247 || ffbo7_seven_square_direct_sum(27) != 915
    << "OUTER7_SELFTEST_FAIL 7x7x7 comparison"
    exit(1)
  << "flipfleet_block_outer7_scan: all checks passed 21=5681/5223 24=8471"
  exit(0)

<< "target\tformula_rank\tcomparison_rank\tdelta\talloc_n\talloc_m\talloc_p\tsource\ts3_code\texact_rank"
targets = 0 ## i64
exact_checks = 0 ## i64

if mode == "target" || mode == "neighbor"
  if av.size() < 2
    << "target mode requires NxMxP"
    exit(1)
  dims = i64[3]
  if ffbo7_parse_target(av[1], dims) != 1
    << "target dimensions must each be in 7..32"
    exit(1)
  recipe = ffbo7_best_oriented_recipe(outer, supports, dims[0], dims[1], dims[2])
  if recipe == nil
    << "no balanced recipe for " + av[1]
    exit(1)
  if mode == "neighbor"
    passes = 2 ## i64
    if av.size() == 3
      passes = av[2].to_i()
    if passes < 1 || passes > 8
      << "neighbor passes must be in 1..8"
      exit(1)
    local = ffbo7_neighborhood(outer, supports, recipe, passes)
    row = av[1] + "\t" + local[3].to_s() + "\t" + recipe[3].to_s() + "\t" + (local[3] - recipe[3]).to_s()
    row = row + "\t" + local[0].join(",") + "\t" + local[1].join(",") + "\t" + local[2].join(",")
    row = row + "\t" + recipe[4].to_s() + "x" + recipe[5].to_s() + "x" + recipe[6].to_s() + "\t" + recipe[7].to_s() + "\tNA"
    << row
    << "NEIGHBOR passes=" + passes.to_s() + " evaluated=" + local[4].to_s()
    targets = 1
  else
    row = av[1] + "\t" + recipe[3].to_s() + "\tNA\tNA"
    row = row + "\t" + recipe[0].join(",") + "\t" + recipe[1].join(",") + "\t" + recipe[2].join(",")
    row = row + "\t" + recipe[4].to_s() + "x" + recipe[5].to_s() + "x" + recipe[6].to_s() + "\t" + recipe[7].to_s()
    if av.size() == 3 && av[2] == "exact"
      if dims[0] < 21 || dims[1] < 21 || dims[2] < 21
        << "exact mode requires the checked-in 3--8 leaf range (target dimensions 21..32)"
        exit(1)
      result = ffbc_compose_oriented_recipe(outer, dims[0], dims[1], dims[2], leaves, recipe)
      if result == nil || ffbc_verify_exact(result) != 1
        << "exact composition failed"
        exit(1)
      row = row + "\t" + result.rank().to_s()
      exact_checks = 1
    else
      row = row + "\tNA"
    << row
    targets = 1
elsif mode == "records"
  content = read_file(root + "block_composition_records.tsv")
  if content == nil
    << "missing block_composition_records.tsv"
    exit(1)
  lines = content.split("\n")
  li = 1 ## i64
  while li < lines.size()
    if lines[li].size() > 0
      fields = lines[li].split("\t")
      if fields.size() < 3
        << "malformed record row"
        exit(1)
      text = fields[0]
      dims = i64[3]
      if ffbo7_parse_target(text, dims) != 1
        << "record target outside 7..32: " + text
        exit(1)
      baseline = fields[2].to_i() ## i64
      recipe = ffbo7_best_oriented_recipe(outer, supports, dims[0], dims[1], dims[2])
      if recipe == nil
        << "no balanced recipe for " + text
        exit(1)
      row = text + "\t" + recipe[3].to_s() + "\t" + baseline.to_s() + "\t" + (recipe[3] - baseline).to_s()
      row = row + "\t" + recipe[0].join(",") + "\t" + recipe[1].join(",") + "\t" + recipe[2].join(",")
      row = row + "\t" + recipe[4].to_s() + "x" + recipe[5].to_s() + "x" + recipe[6].to_s() + "\t" + recipe[7].to_s() + "\tNA"
      << row
      targets += 1
    li += 1
elsif mode == "multiples"
  n = 7 ## i64
  while n <= 32
    m = n ## i64
    while m <= 32
      p = m ## i64
      while p <= 32
        if n % 7 == 0 || m % 7 == 0 || p % 7 == 0
          recipe = ffbo7_best_oriented_recipe(outer, supports, n, m, p)
          if recipe == nil
            << "no balanced recipe for " + n.to_s() + "x" + m.to_s() + "x" + p.to_s()
            exit(1)
          comparison = ffbo7_comparison_rank(outer4, comparison_leaves, n, m, p) ## i64
          if comparison < 1
            << "no rank-47 comparison recipe for " + n.to_s() + "x" + m.to_s() + "x" + p.to_s()
            exit(1)
          row = n.to_s() + "x" + m.to_s() + "x" + p.to_s() + "\t" + recipe[3].to_s() + "\t" + comparison.to_s() + "\t" + (recipe[3] - comparison).to_s()
          row = row + "\t" + recipe[0].join(",") + "\t" + recipe[1].join(",") + "\t" + recipe[2].join(",")
          row = row + "\t" + recipe[4].to_s() + "x" + recipe[5].to_s() + "x" + recipe[6].to_s() + "\t" + recipe[7].to_s() + "\tNA"
          << row
          targets += 1
        p += 1
      m += 1
    n += 1
else
  starts = i64[4]
  ends = i64[4]
  starts[0] = 7
  starts[1] = 14
  starts[2] = 21
  starts[3] = 28
  ends[0] = 13
  ends[1] = 20
  ends[2] = 27
  ends[3] = 32
  band = 0 ## i64
  while band < 4
    n = starts[band] ## i64
    while n <= ends[band]
      m = n ## i64
      while m <= ends[band]
        p = m ## i64
        while p <= ends[band]
          recipe = ffbo7_best_oriented_recipe(outer, supports, n, m, p)
          if recipe == nil
            << "no balanced recipe for " + n.to_s() + "x" + m.to_s() + "x" + p.to_s()
            exit(1)
          comparison = ffbo7_comparison_rank(outer4, comparison_leaves, n, m, p) ## i64
          if comparison < 1
            << "no rank-47 comparison recipe for " + n.to_s() + "x" + m.to_s() + "x" + p.to_s()
            exit(1)
          row = n.to_s() + "x" + m.to_s() + "x" + p.to_s() + "\t" + recipe[3].to_s() + "\t" + comparison.to_s() + "\t" + (recipe[3] - comparison).to_s()
          row = row + "\t" + recipe[0].join(",") + "\t" + recipe[1].join(",") + "\t" + recipe[2].join(",")
          row = row + "\t" + recipe[4].to_s() + "x" + recipe[5].to_s() + "x" + recipe[6].to_s() + "\t" + recipe[7].to_s() + "\tNA"
          << row
          targets += 1
          p += 1
        m += 1
      n += 1
    band += 1

<< "SUMMARY mode=" + mode + " targets=" + targets.to_s() + " exact_checks=" + exact_checks.to_s()
