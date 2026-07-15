use flipfleet_block_leaf_pool

# Pure-Tungsten, single-threaded support-aware scan of exact rank-93 5x5x5
# outers against the complete exact 3..8 leaf pool.  Formula candidates are
# compared with both exact rank-47 outer components and the persisted public /
# exact audit tables.  Exact materialisation is attempted only after a strict
# formula win; a certificate is written only if the compacted exact result is
# still a strict win.
#
#   flipfleet-block-outer5-scan summary 15 32
#   flipfleet-block-outer5-scan table 15 32
#   flipfleet-block-outer5-scan target 17x23x31 all
#
# The scanner itself has no threads, GPU calls, or TUI dependencies.

-> ffbo5_usage() i64
  << "usage: flipfleet-block-outer5-scan <summary|table> LOW HIGH"
  << "       flipfleet-block-outer5-scan target NxMxP (optionally: all or OUTER)"
  0 - 1

-> ffbo5_add_outer(root, label, path, outers, labels, paths) (String String String Array Array Array) i64
  outer = ffbc_load_exact(root + path, 5, 5, 5, 128)
  if outer == nil || outer.rank() != 93
    << "invalid rank-93 outer " + path
    exit(1)
  outers.push(outer)
  labels.push(label)
  paths.push(path)
  1

-> ffbo5_density(scheme) (FFBCScheme) i64
  total = 0 ## i64
  term = 0 ## i64
  while term < scheme.rank()
    word = 0 ## i64
    while word < scheme.uw()
      total += ffbc_popcount_small(scheme.us()[term * scheme.uw() + word])
      word += 1
    word = 0
    while word < scheme.vw()
      total += ffbc_popcount_small(scheme.vs()[term * scheme.vw() + word])
      word += 1
    word = 0
    while word < scheme.ww()
      total += ffbc_popcount_small(scheme.ws()[term * scheme.ww() + word])
      word += 1
    term += 1
  total

-> ffbo5_parse_target(text, dims) (String i64[]) i64
  fields = text.split("x")
  if fields.size() != 3
    return 0
  i = 0 ## i64
  while i < 3
    dims[i] = fields[i].to_i()
    if dims[i] < 15 || dims[i] > 32
      return 0
    i += 1
  if dims[0] > dims[1] || dims[1] > dims[2]
    return 0
  1

-> ffbo5_min_column(body, target, column, best) (String String i64 i64) i64
  lines = body.split("\n")
  i = 1 ## i64
  while i < lines.size()
    if lines[i].starts_with?(target + "\t")
      fields = lines[i].split("\t")
      if column < fields.size()
        value = fields[column].to_i() ## i64
        if value > 0 && value < best
          best = value
        i = lines.size()
      end
    end
    i += 1
  best

# Conservative best persisted comparison.  Both all-field numerical ranks and
# explicit GF(2) ranks are eligible: a new GF(2) term list must beat the
# smallest numerical rank before it is called a record candidate.
-> ffbo5_table_baseline(target, public, records, opportunities, cross, closure, unbalanced, smallblock) (String String String String String String String String) i64
  best = 0x7fffffff ## i64
  best = ffbo5_min_column(public, target, 5, best)
  best = ffbo5_min_column(records, target, 2, best)
  best = ffbo5_min_column(opportunities, target, 2, best)
  best = ffbo5_min_column(opportunities, target, 3, best)
  best = ffbo5_min_column(cross, target, 1, best)
  best = ffbo5_min_column(cross, target, 2, best)
  best = ffbo5_min_column(cross, target, 4, best)
  best = ffbo5_min_column(cross, target, 7, best)
  best = ffbo5_min_column(closure, target, 1, best)
  best = ffbo5_min_column(closure, target, 3, best)
  best = ffbo5_min_column(closure, target, 6, best)
  best = ffbo5_min_column(unbalanced, target, 2, best)
  best = ffbo5_min_column(unbalanced, target, 3, best)
  best = ffbo5_min_column(unbalanced, target, 6, best)
  best = ffbo5_min_column(smallblock, target, 2, best)
  best = ffbo5_min_column(smallblock, target, 3, best)
  best = ffbo5_min_column(smallblock, target, 5, best)
  best = ffbo5_min_column(smallblock, target, 7, best)
  if best == 0x7fffffff
    return 0
  best

-> ffbo5_recipe_text(recipe) (Array)
  recipe[0].join(",") + "|" + recipe[1].join(",") + "|" + recipe[2].join(",") + "|" + recipe[4].to_s() + "x" + recipe[5].to_s() + "x" + recipe[6].to_s() + ":" + recipe[7].to_s()

# Constant-time rank table for every oriented 3..8 leaf shape.  The stable
# pool is exact-gated before this is built; orientation does not change rank.
-> ffbo5_rank_table(leaves) (Array)
  ranks = i64[9 * 9 * 9]
  choice = i64[2]
  a = 3 ## i64
  while a <= 8
    b = 3 ## i64
    while b <= 8
      c = 3 ## i64
      while c <= 8
        if ffbc_find_leaf(leaves, a, b, c, choice) != 1
          return nil
        ranks[a * 81 + b * 9 + c] = leaves[choice[0]].rank()
        c += 1
      b += 1
    a += 1
  ranks

# Six masks per term: U-row, U-column, V-row, V-column, W-row, W-column.
# This representation is the exact information consumed by support-aware
# balanced scoring and works for either square rank-47 or rank-93 outers.
-> ffbo5_support_masks(outer) (FFBCScheme)
  masks = i64[outer.rank() * 6]
  term = 0 ## i64
  while term < outer.rank()
    axis = 0 ## i64
    while axis < 3
      data = outer.us()
      words = outer.uw() ## i64
      rows = outer.n() ## i64
      cols = outer.m() ## i64
      if axis == 1
        data = outer.vs()
        words = outer.vw()
        rows = outer.m()
        cols = outer.p()
      elsif axis == 2
        data = outer.ws()
        words = outer.ww()
        rows = outer.n()
        cols = outer.p()
      bit = 0 ## i64
      while bit < rows * cols
        if ffbc_bit(data, term * words, bit) == 1
          row = bit / cols ## i64
          col = bit % cols ## i64
          masks[term * 6 + axis * 2] = masks[term * 6 + axis * 2] | (1 << row)
          masks[term * 6 + axis * 2 + 1] = masks[term * 6 + axis * 2 + 1] | (1 << col)
        bit += 1
      axis += 1
    term += 1
  masks

-> ffbo5_extra_masks(total, parts) (i64 i64)
  result = []
  extra = total % parts ## i64
  mask = 0 ## i64
  limit = 1 << parts ## i64
  while mask < limit
    if ffbc_popcount_small(mask) == extra
      result.push(mask)
    mask += 1
  result

-> ffbo5_extent(base, extra_mask, support_mask) (i64 i64 i64) i64
  if (extra_mask & support_mask) != 0
    return base + 1
  base

-> ffbo5_fast_score(outer, supports, ranks, bn, bm, bp, en, em, ep) (FFBCScheme i64[] i64[] i64 i64 i64 i64 i64 i64) i64
  total = 0 ## i64
  term = 0 ## i64
  while term < outer.rank()
    offset = term * 6 ## i64
    sn = ffbo5_extent(bn, en, supports[offset]) ## i64
    other = ffbo5_extent(bn, en, supports[offset + 4]) ## i64
    if other < sn
      sn = other
    sm = ffbo5_extent(bm, em, supports[offset + 1]) ## i64
    other = ffbo5_extent(bm, em, supports[offset + 2])
    if other < sm
      sm = other
    sp = ffbo5_extent(bp, ep, supports[offset + 3]) ## i64
    other = ffbo5_extent(bp, ep, supports[offset + 5])
    if other < sp
      sp = other
    if sn < 3 || sn > 8 || sm < 3 || sm > 8 || sp < 3 || sp > 8
      return 0 - 1
    rank = ranks[sn * 81 + sm * 9 + sp] ## i64
    if rank < 1
      return 0 - 1
    total += rank
    term += 1
  total

-> ffbo5_allocation(total, parts, extra_mask) (i64 i64 i64)
  result = i64[parts]
  base = total / parts ## i64
  i = 0 ## i64
  while i < parts
    result[i] = base + ((extra_mask >> i) & 1)
    i += 1
  result

-> ffbo5_fast_recipe(outer, supports, ranks, target_n, target_m, target_p) (FFBCScheme i64[] i64[] i64 i64 i64)
  parts = outer.n() ## i64
  ens = ffbo5_extra_masks(target_n, parts)
  ems = ffbo5_extra_masks(target_m, parts)
  eps = ffbo5_extra_masks(target_p, parts)
  bn = target_n / parts ## i64
  bm = target_m / parts ## i64
  bp = target_p / parts ## i64
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
        score = ffbo5_fast_score(outer, supports, ranks, bn, bm, bp, ens[ni], ems[mi], eps[pi]) ## i64
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
  [ffbo5_allocation(target_n, parts, best_en), ffbo5_allocation(target_m, parts, best_em), ffbo5_allocation(target_p, parts, best_ep), best]

-> ffbo5_fast_oriented_recipe(outer, supports, ranks, target_n, target_m, target_p) (FFBCScheme i64[] i64[] i64 i64 i64)
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
      candidate = ffbo5_fast_recipe(outer, supports, ranks, dims[0], dims[1], dims[2])
      if candidate != nil && candidate[3] < best_score
        best_score = candidate[3]
        best = [candidate[0], candidate[1], candidate[2], candidate[3], dims[0], dims[1], dims[2], code]
    ci += 1
  best

av = argv()
if av.size() < 1 || av.size() > 4
  exit(ffbo5_usage())
mode = av[0]
if mode != "summary" && mode != "table" && mode != "target"
  exit(ffbo5_usage())

root = "benchmarks/matmul/metaflip/"
leaves = ffbcp_stable_3_to_8(root)
if leaves.size() != 56
  << "incomplete exact 3..8 leaf pool: " + leaves.size().to_s()
  exit(1)
ranks = ffbo5_rank_table(leaves)
if ranks == nil
  << "incomplete exact 3..8 rank table"
  exit(1)

outer4a = ffbc_load_exact(root + "matmul_4x4_rank47_d450_gf2.txt", 4, 4, 4, 128)
outer4b = ffbc_load_exact(root + "matmul_4x4_rank47_d677_flips_gf2.txt", 4, 4, 4, 128)
if outer4a == nil || outer4b == nil || outer4a.rank() != 47 || outer4b.rank() != 47
  << "invalid rank-47 comparison outer"
  exit(1)
support4a = ffbo5_support_masks(outer4a)
support4b = ffbo5_support_masks(outer4b)

outers = []
labels = []
paths = []
ffbo5_add_outer(root, "perminov", "matmul_5x5_rank93_catalog_perminov_c843_gf2.txt", outers, labels, paths)
ffbo5_add_outer(root, "alpha", "matmul_5x5_rank93_catalog_alphaevolve_gf2.txt", outers, labels, paths)
ffbo5_add_outer(root, "kauers-a", "matmul_5x5_rank93_catalog_kauers_a_gf2.txt", outers, labels, paths)
ffbo5_add_outer(root, "kauers-b", "matmul_5x5_rank93_catalog_kauers_b_gf2.txt", outers, labels, paths)
ffbo5_add_outer(root, "d967", "matmul_5x5_rank93_d967_four_split_control_gf2.txt", outers, labels, paths)
ffbo5_add_outer(root, "d1155", "matmul_5x5_rank93_d1155_gf2.txt", outers, labels, paths)
ffbo5_add_outer(root, "d1191", "matmul_5x5_rank93_d1191_gf2.txt", outers, labels, paths)

support_sets = []
i = 0 ## i64
while i < outers.size()
  support_sets.push(ffbo5_support_masks(outers[i]))
  i += 1
end

records = read_file(root + "block_composition_records.tsv")
opportunities = read_file(root + "block_composition_opportunities.tsv")
cross = read_file(root + "block_composition_cross_audit.tsv")
closure = read_file(root + "block_composition_queue_closure_audit.tsv")
unbalanced = read_file(root + "block_composition_unbalanced_audit.tsv")
smallblock = read_file(root + "block_composition_smallblock_audit.tsv")
public = read_file(root + "block_composition_outer5_public_baseline.tsv")
if records == nil || opportunities == nil || cross == nil || closure == nil || unbalanced == nil || smallblock == nil || public == nil
  << "missing block/public comparison table"
  exit(1)

low = 15 ## i64
high = 32 ## i64
selector = "all"
if mode == "target"
  if av.size() < 2 || av.size() > 3
    exit(ffbo5_usage())
  dims = i64[3]
  if ffbo5_parse_target(av[1], dims) != 1
    << "target must be sorted and lie in 15..32"
    exit(1)
  low = dims[0]
  high = dims[2]
  if av.size() == 3
    selector = av[2]
  end
else
  if av.size() == 3
    low = av[1].to_i()
    high = av[2].to_i()
  elsif av.size() != 1
    exit(ffbo5_usage())
  end
  if low < 15 || high > 32 || low > high
    << "the pinned public-baseline scan requires 15 <= LOW <= HIGH <= 32"
    exit(1)
  end
end

stats = i64[outers.size() * 8]
# [targets, wins4, ties4, wins_effective, exact_wins, closest_delta4,
#  closest_delta_effective, largest_formula_gain]
i = 0 ## i64
while i < outers.size()
  stats[i * 8 + 5] = 0x7fffffff
  stats[i * 8 + 6] = 0x7fffffff
  i += 1
end

<< "OUTER\tlabel\tdensity\tprobe_16x23x31\tpath"
probe4a = ffbo5_fast_oriented_recipe(outer4a, support4a, ranks, 16, 23, 31)
probe4b = ffbo5_fast_oriented_recipe(outer4b, support4b, ranks, 16, 23, 31)
authoritative4a = ffbc_best_oriented_balanced_recipe(outer4a, 16, 23, 31, leaves)
authoritative4b = ffbc_best_oriented_balanced_recipe(outer4b, 16, 23, 31, leaves)
if probe4a == nil || probe4b == nil || authoritative4a == nil || authoritative4b == nil || probe4a[3] != authoritative4a[3] || probe4b[3] != authoritative4b[3]
  << "fast scorer disagreement for rank-47 comparison probe"
  exit(1)
end
i = 0
while i < outers.size()
  probe = ffbo5_fast_oriented_recipe(outers[i], support_sets[i], ranks, 16, 23, 31)
  authoritative = ffbc_best_oriented_balanced_recipe(outers[i], 16, 23, 31, leaves)
  if probe == nil || authoritative == nil || probe[3] != authoritative[3]
    << "fast scorer disagreement for " + labels[i] + " probe"
    exit(1)
  end
  probe_rank = 0 ## i64
  if probe != nil
    probe_rank = probe[3]
  end
  << "OUTER\t" + labels[i] + "\t" + ffbo5_density(outers[i]).to_s() + "\t" + probe_rank.to_s() + "\t" + paths[i]
  i += 1
end
if mode == "table" || mode == "target"
  << "target\touter\tformula_rank\touter4_rank\ttable_rank\teffective_rank\tdelta4\tdelta_effective\texact_rank\trecipe"
end

n = low ## i64
while n <= high
  m = n ## i64
  while m <= high
    p = m ## i64
    while p <= high
      target = n.to_s() + "x" + m.to_s() + "x" + p.to_s()
      include_target = 1 ## i64
      if mode == "target" && target != av[1]
        include_target = 0
      end
      if include_target == 1
        recipe4a = ffbo5_fast_oriented_recipe(outer4a, support4a, ranks, n, m, p)
        recipe4b = ffbo5_fast_oriented_recipe(outer4b, support4b, ranks, n, m, p)
        if recipe4a == nil || recipe4b == nil
          << "missing rank-47 comparison for " + target
          exit(1)
        end
        rank4 = recipe4a[3] ## i64
        if recipe4b[3] < rank4
          rank4 = recipe4b[3]
        end
        table_rank = ffbo5_table_baseline(target, public, records, opportunities, cross, closure, unbalanced, smallblock) ## i64
        effective = rank4 ## i64
        if table_rank > 0 && table_rank < effective
          effective = table_rank
        end

        oi = 0 ## i64
        while oi < outers.size()
          if selector == "all" || selector == labels[oi]
            recipe = ffbo5_fast_oriented_recipe(outers[oi], support_sets[oi], ranks, n, m, p)
            if recipe == nil
              << "missing rank-93 recipe for " + labels[oi] + " " + target
              exit(1)
            end
            formula = recipe[3] ## i64
            delta4 = formula - rank4 ## i64
            delta_effective = formula - effective ## i64
            stats[oi * 8] += 1
            if delta4 < stats[oi * 8 + 5]
              stats[oi * 8 + 5] = delta4
            end
            if delta_effective < stats[oi * 8 + 6]
              stats[oi * 8 + 6] = delta_effective
            end
            if delta4 < 0
              stats[oi * 8 + 1] += 1
              if 0 - delta4 > stats[oi * 8 + 7]
                stats[oi * 8 + 7] = 0 - delta4
              end
            elsif delta4 == 0
              stats[oi * 8 + 2] += 1
            end
            exact_rank = 0 ## i64
            if delta_effective < 0
              stats[oi * 8 + 3] += 1
              result = ffbc_compose_oriented_recipe(outers[oi], n, m, p, leaves, recipe)
              if result == nil || ffbc_verify_exact(result) != 1
                << "exact materialisation failed for " + labels[oi] + " " + target
                exit(1)
              end
              exact_rank = result.rank()
              if exact_rank < effective
                stats[oi * 8 + 4] += 1
                output = "/tmp/matmul_" + target + "_rank" + exact_rank.to_s() + "_outer5_" + labels[oi] + "_gf2.txt"
                if ffbc_write(output, result) < 1
                  << "failed to write exact winner " + output
                  exit(1)
                end
                << "WINNER\t" + target + "\t" + labels[oi] + "\t" + formula.to_s() + "\t" + exact_rank.to_s() + "\t" + effective.to_s() + "\t" + output
              end
            end
            if mode == "table" || mode == "target"
              << target + "\t" + labels[oi] + "\t" + formula.to_s() + "\t" + rank4.to_s() + "\t" + table_rank.to_s() + "\t" + effective.to_s() + "\t" + delta4.to_s() + "\t" + delta_effective.to_s() + "\t" + exact_rank.to_s() + "\t" + ffbo5_recipe_text(recipe)
            end
          end
          oi += 1
        end
      end
      p += 1
    end
    m += 1
  end
  n += 1
end

i = 0
while i < outers.size()
  if selector == "all" || selector == labels[i]
    << "SUMMARY\t" + labels[i] + "\ttargets=" + stats[i * 8].to_s() + "\twins4=" + stats[i * 8 + 1].to_s() + "\tties4=" + stats[i * 8 + 2].to_s() + "\twins_effective=" + stats[i * 8 + 3].to_s() + "\texact_wins=" + stats[i * 8 + 4].to_s() + "\tclosest_delta4=" + stats[i * 8 + 5].to_s() + "\tclosest_delta_effective=" + stats[i * 8 + 6].to_s() + "\tlargest_formula_gain=" + stats[i * 8 + 7].to_s()
  end
  i += 1
end
